extends RefCounted

# Port model of a Better Resource Hub, independent from the scene tree.
#
# Every port has a stable uid ("cpu_in_3"). Uids come from per-kind counters
# that only ever increase and are saved with the layout, so removing a port
# never lets a later port inherit its node path, container id or connections.
# The uid is also the port's node name, which is what Upload Labs uses as the
# key of the saved container data.

enum Kind {
    CPU_INPUT = 0,
    CPU_OUTPUT = 1,
    GPU_INPUT = 2,
    GPU_OUTPUT = 3,
}

const FORMAT := 1
const KIND_PREFIXES := ["cpu_in", "cpu_out", "gpu_in", "gpu_out"]
const CPU_RESOURCE := "clock_speed"
const GPU_RESOURCE := "gpu_speed"
const MAX_LABEL_LENGTH := 32
# Not a gameplay limit: a guard against corrupted or hand-edited saves. The UI
# warns long before this (see SOFT_PORT_WARNING).
const PORTS_PER_KIND_GUARD := 256
const SOFT_PORT_WARNING := 64
# Hidden ports kept ready per kind. In Upload Labs 3.0.12 a port created after
# the window was set up stays at 0 until the save is reloaded, while ports
# that exist from the start work (observed in alpha.3). Revealing a spare
# therefore works at once; spares are topped up again on every load.
const SPARE_INPUTS := 8
const SPARE_OUTPUTS := 4


static func default_layout() -> Dictionary:
    var layout := {"format": FORMAT, "ports": [], "next": {}}
    for kind in [Kind.CPU_INPUT, Kind.CPU_OUTPUT, Kind.GPU_INPUT, Kind.GPU_OUTPUT]:
        add_port(layout, kind)
    top_up_spares(layout)
    return layout


static func spare_target(kind: int) -> int:
    return SPARE_INPUTS if is_input(kind) else SPARE_OUTPUTS


static func is_spare(port: Dictionary) -> bool:
    return bool(port.get("spare", false))


static func visible_ports_of(layout: Dictionary, kind: int) -> Array:
    return ports_of(layout, kind).filter(func(port): return not is_spare(port))


static func spare_ports_of(layout: Dictionary, kind: int) -> Array:
    return ports_of(layout, kind).filter(func(port): return is_spare(port))


# Adds hidden spares until every kind has its target. Returns how many.
static func top_up_spares(layout: Dictionary) -> int:
    var added := 0
    for kind in [Kind.CPU_INPUT, Kind.CPU_OUTPUT, Kind.GPU_INPUT, Kind.GPU_OUTPUT]:
        var missing := spare_target(kind) - spare_ports_of(layout, kind).size()
        for _i in range(missing):
            if add_port(layout, kind, true).is_empty():
                break
            added += 1
    return added


# Turns the first spare of a kind into a visible port; "" when none is left.
static func reveal_spare(layout: Dictionary, kind: int) -> String:
    for port in layout.get("ports", []):
        if int(port.get("kind", -1)) == kind and is_spare(port):
            port.spare = false
            return str(port.uid)
    return ""


static func set_spare(layout: Dictionary, uid: String, spare: bool) -> bool:
    var index := find_port(layout, uid)
    if index < 0:
        return false
    layout.ports[index].spare = spare
    return true


static func empty_layout() -> Dictionary:
    return {"format": FORMAT, "ports": [], "next": {}}


static func default_settings() -> Dictionary:
    return {
        "priority": 0,
        "weight": 1.0,
        "max": -1.0,
        "min": 0.0,
        "enabled": true,
        "manual": false,
    }


static func is_input(kind: int) -> bool:
    return kind == Kind.CPU_INPUT or kind == Kind.GPU_INPUT


static func is_output(kind: int) -> bool:
    return kind == Kind.CPU_OUTPUT or kind == Kind.GPU_OUTPUT


static func resource_for(kind: int) -> String:
    return CPU_RESOURCE if kind == Kind.CPU_INPUT or kind == Kind.CPU_OUTPUT else GPU_RESOURCE


static func is_valid_kind(kind) -> bool:
    return (kind is int or kind is float) and int(kind) >= Kind.CPU_INPUT and int(kind) <= Kind.GPU_OUTPUT


static func add_port(layout: Dictionary, kind: int, spare: bool = false) -> String:
    if not is_valid_kind(kind):
        return ""
    if ports_of(layout, kind).size() >= PORTS_PER_KIND_GUARD:
        return ""
    var prefix: String = KIND_PREFIXES[kind]
    var next: Dictionary = layout.get_or_add("next", {})
    var number := maxi(int(next.get(prefix, 1)), 1)
    var uid := "%s_%d" % [prefix, number]
    while find_port(layout, uid) >= 0:
        number += 1
        uid = "%s_%d" % [prefix, number]
    next[prefix] = number + 1

    var port := {"uid": uid, "kind": kind, "label": "", "spare": spare}
    if is_output(kind):
        port["settings"] = default_settings()
    layout.get_or_add("ports", []).append(port)
    return uid


static func remove_port(layout: Dictionary, uid: String) -> bool:
    var index := find_port(layout, uid)
    if index < 0:
        return false
    layout.ports.remove_at(index)
    return true


static func find_port(layout: Dictionary, uid: String) -> int:
    var ports: Array = layout.get("ports", [])
    for index in range(ports.size()):
        if str(ports[index].get("uid", "")) == uid:
            return index
    return -1


static func get_port(layout: Dictionary, uid: String) -> Dictionary:
    var index := find_port(layout, uid)
    return layout.ports[index] if index >= 0 else {}


static func ports_of(layout: Dictionary, kind: int) -> Array:
    var result: Array = []
    for port in layout.get("ports", []):
        if int(port.get("kind", -1)) == kind:
            result.append(port)
    return result


static func set_label(layout: Dictionary, uid: String, label: String) -> bool:
    var index := find_port(layout, uid)
    if index < 0:
        return false
    layout.ports[index].label = sanitize_label(label)
    return true


static func set_setting(layout: Dictionary, uid: String, setting: String, value) -> bool:
    var index := find_port(layout, uid)
    if index < 0 or not is_output(int(layout.ports[index].kind)):
        return false
    var settings: Dictionary = layout.ports[index].get_or_add("settings", default_settings())
    if not default_settings().has(setting):
        return false
    settings[setting] = value
    layout.ports[index].settings = sanitize_settings(settings)
    return true


static func sanitize_label(value) -> String:
    var text := str(value).strip_edges().replace("\n", " ").replace("\r", " ")
    return text.substr(0, MAX_LABEL_LENGTH)


static func sanitize_settings(value) -> Dictionary:
    var source: Dictionary = value if value is Dictionary else {}
    var result := default_settings()
    result.priority = clampi(int(_finite_or(source.get("priority", 0), 0.0)), -10, 10)
    result.weight = clampf(_finite_or(source.get("weight", 1.0), 1.0), 0.0, 1000000.0)
    var maximum := _finite_or(source.get("max", -1.0), -1.0)
    result.max = maximum if maximum >= 0.0 else -1.0
    result.min = maxf(_finite_or(source.get("min", 0.0), 0.0), 0.0)
    if result.max >= 0.0:
        result.min = minf(result.min, result.max)
    result.enabled = bool(source.get("enabled", true))
    result.manual = bool(source.get("manual", false))
    return result


# Rebuild a trusted layout from untrusted saved data. Unknown kinds, duplicate
# uids and malformed entries are dropped; counters are raised past every uid
# that is kept so a new port can never reuse one.
static func from_save(value) -> Dictionary:
    var layout := empty_layout()
    var report := {"dropped": 0, "duplicates": 0}
    if not value is Dictionary:
        return {"layout": layout, "report": report, "valid": false}

    var seen: Dictionary = {}
    var counts: Dictionary = {}
    for raw_port in value.get("ports", []):
        if not raw_port is Dictionary or not is_valid_kind(raw_port.get("kind")):
            report.dropped += 1
            continue
        var kind := int(raw_port.kind)
        var uid := str(raw_port.get("uid", ""))
        var prefix: String = KIND_PREFIXES[kind]
        if not _is_valid_uid(uid, prefix):
            report.dropped += 1
            continue
        if seen.has(uid):
            report.duplicates += 1
            continue
        if int(counts.get(kind, 0)) >= PORTS_PER_KIND_GUARD:
            report.dropped += 1
            continue
        seen[uid] = true
        counts[kind] = int(counts.get(kind, 0)) + 1

        var port := {"uid": uid, "kind": kind, "label": sanitize_label(raw_port.get("label", "")), "spare": bool(raw_port.get("spare", false))}
        if is_output(kind):
            port["settings"] = sanitize_settings(raw_port.get("settings", {}))
        layout.ports.append(port)

    var raw_next = value.get("next", {})
    for prefix in KIND_PREFIXES:
        var saved := 1
        if raw_next is Dictionary:
            saved = maxi(int(_finite_or(raw_next.get(prefix, 1), 1.0)), 1)
        layout.next[prefix] = maxi(saved, _highest_number(layout, prefix) + 1)

    return {"layout": layout, "report": report, "valid": true}


static func to_save(layout: Dictionary) -> Dictionary:
    return {
        "format": FORMAT,
        "ports": layout.get("ports", []).duplicate(true),
        "next": layout.get("next", {}).duplicate(true),
    }


static func _highest_number(layout: Dictionary, prefix: String) -> int:
    var highest := 0
    for port in layout.ports:
        var uid := str(port.uid)
        if uid.begins_with(prefix + "_"):
            highest = maxi(highest, int(uid.substr(prefix.length() + 1)))
    return highest


static func _is_valid_uid(uid: String, prefix: String) -> bool:
    if not uid.begins_with(prefix + "_"):
        return false
    var number := uid.substr(prefix.length() + 1)
    return number.is_valid_int() and int(number) > 0 and str(int(number)) == number


static func _finite_or(value, fallback: float) -> float:
    if not (value is int or value is float):
        return fallback
    var number := float(value)
    return number if is_finite(number) else fallback
