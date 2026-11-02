extends RefCounted

# One resource (clock_speed or gpu_speed) of a Better Resource Hub.
#
#   inputs  -> one pool (sum of what the connected sources really deliver)
#   pool    -> output ports (per-port settings: priority, weight, max, min...)
#   port    -> the machines connected to it (demand-first, then surplus)
#
# CPU and GPU never share a channel, so no conversion between them can occur.
# Topology work (targets, roles, loop detection) only runs when something
# changed; each tick only reads demands and runs the O(n log n) allocator.

const Allocator = preload("res://mods-unpacked/Daneisra-BetterResourceManager/scripts/core/brm_allocator.gd")
const DemandTracker = preload("res://mods-unpacked/Daneisra-BetterResourceManager/scripts/core/brm_demand_tracker.gd")
const CycleGuard = preload("res://mods-unpacked/Daneisra-BetterResourceManager/scripts/core/brm_cycle_guard.gd")
const SmartWindowData = preload("res://mods-unpacked/Daneisra-BetterResourceManager/scripts/global/smart_window_data.gd")
const SmartDistribution = preload("res://mods-unpacked/Daneisra-BetterResourceManager/scripts/global/distribution_modes.gd")
const BRMUtils = preload("res://mods-unpacked/Daneisra-BetterResourceManager/scripts/global/brm_utils.gd")

enum Mode {
    AUTO = 0,
    DEMAND = 1,
    RATIO = 2,
    PRIORITY = 3,
    GRAPH = 4,
}

const MODE_POLICIES := {
    Mode.AUTO: Allocator.Policy.AUTO,
    Mode.DEMAND: Allocator.Policy.DEMAND,
    Mode.RATIO: Allocator.Policy.RATIO,
    Mode.PRIORITY: Allocator.Policy.PRIORITY,
}

# Safety net for topology events the game might not report to us.
const PERIODIC_REBUILD_TICKS := 300
const ROLE_REFRESH_TICKS := 5
# Relative demand/setting drift below which the previous allocation is reused.
const DEMAND_REUSE_TOLERANCE := 0.001

var resource := ""
var hub: Node = null
# [{uid: String, container: ResourceContainer}]
var inputs: Array = []
# [{uid: String, container: ResourceContainer, settings: Dictionary}]
var outputs: Array = []
# SmartWindowGraph owned by the hub, only set while in Graph mode.
var graph = null

var stats: Dictionary = {}
var port_flows: Dictionary = {}
var port_demands: Dictionary = {}

var _dirty := true
var _ticks_since_rebuild := 0
var _wdata: Dictionary = {}
var _window_port: Dictionary = {}
var _port_windows: Dictionary = {}
var _loop_containers: Array = []
var _graph_truncated := false
var _tracker := DemandTracker.new()
var _legacy_state: Dictionary = {"wdata": {}}
var _cached_signature := PackedFloat64Array()
var _cached_allocations: Dictionary = {}
var _cached_top: Dictionary = {}


func _init(p_resource: String = "", p_hub: Node = null) -> void:
    resource = p_resource
    hub = p_hub
    stats = _empty_stats()


func set_ports(p_inputs: Array, p_outputs: Array) -> void:
    inputs = p_inputs
    outputs = p_outputs
    _dirty = true


func mark_dirty() -> void:
    _dirty = true


func get_finite_demand() -> float:
    return float(stats.get("finite_demand", 0.0))


func get_targets() -> Dictionary:
    return _wdata


func tick(mode: int) -> void:
    _ticks_since_rebuild += 1
    if _dirty or _ticks_since_rebuild >= PERIODIC_REBUILD_TICKS:
        _rebuild()

    var supply := _read_supply()

    # Roles and required amounts change rarely; goals, inflow and stock are
    # read live by get_auto_demand() every tick.
    var refresh_roles := _ticks_since_rebuild % ROLE_REFRESH_TICKS == 0
    for name in _wdata.keys():
        var data = _wdata[name]
        if not is_instance_valid(data.window):
            _dirty = true
            continue
        if refresh_roles:
            data.update()

    for container in _loop_containers:
        if is_instance_valid(container):
            container.count = 0.0

    var result: Dictionary
    if mode == Mode.GRAPH:
        result = _tick_graph(supply.value)
    else:
        result = _tick_ports(supply.value, int(MODE_POLICIES.get(mode, Allocator.Policy.AUTO)), mode == Mode.AUTO)

    _write_port_flows()

    stats = {
        "supply": supply.value,
        "connected_inputs": supply.connected,
        "allocated": float(result.get("allocated", 0.0)),
        "unused": float(result.get("unused", 0.0)),
        "finite_demand": float(result.get("finite_demand", 0.0)),
        "uncapped": int(result.get("uncapped_count", 0)),
        "shortage": bool(result.get("shortage", false)),
        "invalid_values": int(result.get("invalid_values", 0)) + supply.invalid,
        "targets": _wdata.size(),
        "cycles": _loop_containers.size(),
        "graph_truncated": _graph_truncated,
        "port_count": inputs.size() + outputs.size(),
    }


func _read_supply() -> Dictionary:
    var total := 0.0
    var connected := 0
    var invalid := 0
    for port in inputs:
        var container = port.container
        if not is_instance_valid(container):
            continue
        if _is_input_connected(container):
            connected += 1
        var value := float(container.count)
        if not is_finite(value):
            invalid += 1
            continue
        total += maxf(value, 0.0)
    return {"value": total, "connected": connected, "invalid": invalid}


func _tick_ports(supply: float, policy: int, smooth: bool) -> Dictionary:
    var window_requests: Dictionary = {}
    for name in _wdata.keys():
        var request := _window_request(name, _wdata[name], smooth)
        window_requests[name] = request

    var port_requests: Array = []
    port_demands.clear()
    for port in outputs:
        var names: Array = _port_windows.get(port.uid, [])
        var settings: Dictionary = port.settings
        var demand := 0.0
        var uncapped := false
        for name in names:
            if window_requests.has(name):
                demand += float(window_requests[name].demand)
                uncapped = uncapped or bool(window_requests[name].uncapped)

        var maximum := float(settings.get("max", -1.0))
        if bool(settings.get("manual", false)):
            # Manual: ignore the estimate, ask for exactly the configured
            # maximum (or everything that is left when none is set).
            demand = maximum if maximum >= 0.0 else 0.0
            uncapped = maximum < 0.0
        port_demands[port.uid] = demand

        port_requests.append({
            "key": port.uid,
            "demand": demand,
            "uncapped": uncapped,
            "weight": float(settings.get("weight", 1.0)),
            "priority": int(settings.get("priority", 0)),
            "max": maximum if maximum >= 0.0 else INF,
            "min": float(settings.get("min", 0.0)),
            "enabled": bool(settings.get("enabled", true)) and not names.is_empty(),
        })

    var signature := _signature(supply, policy, port_requests, window_requests)
    var top: Dictionary
    if _signature_matches(signature):
        top = _cached_top.duplicate()
        for name in _cached_allocations.keys():
            if _wdata.has(name):
                _wdata[name].set_count(float(_cached_allocations[name]))
    else:
        top = Allocator.allocate(supply, port_requests, policy)
        _cached_allocations.clear()
        for port in outputs:
            var names: Array = _port_windows.get(port.uid, [])
            if names.is_empty():
                continue
            var inner_requests: Array = []
            for name in names:
                inner_requests.append(window_requests[name])
            var amount := float(top.allocations.get(port.uid, 0.0))
            var inner := Allocator.allocate(amount, inner_requests, Allocator.Policy.DEMAND)
            for name in names:
                var share := float(inner.allocations.get(name, 0.0))
                _cached_allocations[name] = share
                _wdata[name].set_count(share)
        _cached_signature = signature
        _cached_top = top.duplicate()

    # Port-level finite demand counts configured manual amounts; report the
    # machines' own demand instead so chained managers see the real need.
    var machine_demand := 0.0
    var uncapped_machines := 0
    for name in window_requests.keys():
        if _window_port.has(name):
            machine_demand += float(window_requests[name].demand)
            if bool(window_requests[name].uncapped):
                uncapped_machines += 1
    top["finite_demand"] = machine_demand
    top["uncapped_count"] = uncapped_machines
    top["shortage"] = machine_demand > 0.0 and machine_demand > supply * (1.0 + 1e-9)
    return top


# Everything the allocation depends on. Supply must match exactly (reusing
# a result computed for a larger supply would hand out more than exists);
# demands and settings may drift by DEMAND_REUSE_TOLERANCE.
func _signature(supply: float, policy: int, port_requests: Array, window_requests: Dictionary) -> PackedFloat64Array:
    var values := PackedFloat64Array([supply, float(policy), float(outputs.size()), float(window_requests.size())])
    for request in port_requests:
        values.append_array([
            float(request.demand), 1.0 if request.uncapped else 0.0, float(request.weight),
            float(request.priority), float(request.max), float(request.min), 1.0 if request.enabled else 0.0,
        ])
    for name in window_requests.keys():
        values.append(float(window_requests[name].demand))
        values.append(1.0 if window_requests[name].uncapped else 0.0)
    return values


func _signature_matches(signature: PackedFloat64Array) -> bool:
    if signature.size() != _cached_signature.size() or signature.is_empty():
        return false
    if signature[0] != _cached_signature[0]:
        return false
    for index in range(1, signature.size()):
        var current := signature[index]
        var previous := _cached_signature[index]
        if current == previous:
            continue
        if not is_finite(current) or not is_finite(previous):
            return false
        if absf(current - previous) > maxf(absf(current), absf(previous)) * DEMAND_REUSE_TOLERANCE:
            return false
    return true


func _window_request(name: String, data, smooth: bool) -> Dictionary:
    var demand := 0.0
    var uncapped := false
    match data.role:
        SmartWindowData.SmartWindowRoles.CONSUMER, SmartWindowData.SmartWindowRoles.MANAGER:
            demand = data.get_auto_demand()
            if smooth:
                demand = _tracker.smooth(name, demand)
        SmartWindowData.SmartWindowRoles.STORAGE:
            uncapped = true
    return {"key": name, "demand": demand, "uncapped": uncapped}


# Graph mode keeps the original algorithm (line suppliers / receivers and the
# self-adjusting multiplier). Per-port settings other than "enabled" do not
# apply there; see docs/ARCHITECTURE.md.
func _tick_graph(supply: float) -> Dictionary:
    var state := _legacy_state
    var wdata: Dictionary = {}
    for port in outputs:
        if not bool(port.settings.get("enabled", true)):
            for name in _port_windows.get(port.uid, []):
                _wdata[name].set_count(0.0)
            continue
        for name in _port_windows.get(port.uid, []):
            wdata[name] = _wdata[name]

    for key in state.keys():
        if not ["wdata", "old_demands", "multiplier"].has(key):
            state.erase(key)
    state.wdata = wdata

    var consumers: Array = []
    var managers: Array = []
    var storages: Array = []
    var storage_connections := 0
    var demands: Dictionary = {}
    for name in wdata.keys():
        var data = wdata[name]
        match data.role:
            SmartWindowData.SmartWindowRoles.CONSUMER:
                consumers.append(name)
            SmartWindowData.SmartWindowRoles.MANAGER:
                managers.append(name)
            SmartWindowData.SmartWindowRoles.STORAGE:
                storages.append(name)
                storage_connections += data.provided.size()
        demands[name] = data.get_auto_demand()
    state.consumers = consumers
    state.managers = managers
    state.storages = storages
    state.storage_connections = storage_connections
    state.demands = demands
    _set_graph_roles(state)

    SmartDistribution.distribution_graph(supply, state)

    var allocated := 0.0
    for data in wdata.values():
        for source in data.own_sources:
            allocated += maxf(float(source.count), 0.0)
    if allocated > supply and allocated > 0.0:
        # The original Graph code can briefly hand out its full supply twice
        # while the multiplier settles; never deliver more than the pool.
        var factor := supply / allocated
        for data in wdata.values():
            for source in data.own_sources:
                source.count = maxf(float(source.count), 0.0) * factor
        allocated = supply

    var finite := 0.0
    for name in consumers + managers:
        finite += float(demands.get(name, 0.0))
    return {
        "allocated": allocated,
        "unused": maxf(supply - allocated, 0.0),
        "finite_demand": finite,
        "uncapped_count": storages.size(),
        "shortage": finite > supply * (1.0 + 1e-9),
        "invalid_values": 0,
    }


func _set_graph_roles(state: Dictionary) -> void:
    var filtered_depth: Dictionary = {}
    if graph != null:
        var raw_filtered = graph.filtered.get(0, {})
        if raw_filtered is Dictionary:
            filtered_depth = raw_filtered

    var line_suppliers: Array = []
    for name in state.consumers:
        var payload = filtered_depth.get(name, {"suppliers": 0})
        if not payload is Dictionary or int(payload.get("suppliers", 0)) == 0:
            line_suppliers.append(name)
    for name in state.managers:
        if not line_suppliers.has(name):
            line_suppliers.append(name)

    var line_receivers: Array = []
    for name in state.consumers:
        if not line_suppliers.has(name):
            line_receivers.append(name)

    state.line_suppliers = line_suppliers
    state.line_receivers = line_receivers


func _write_port_flows() -> void:
    port_flows.clear()
    for port in outputs:
        var container = port.container
        if not is_instance_valid(container):
            continue
        var flow := 0.0
        for target in _targets_of(container):
            flow += maxf(float(target.count), 0.0)
        port_flows[port.uid] = flow
        container.count = flow
    for port in inputs:
        if is_instance_valid(port.container):
            port_flows[port.uid] = maxf(float(port.container.count), 0.0)


func _rebuild() -> void:
    _dirty = false
    _cached_signature = PackedFloat64Array()
    _cached_allocations.clear()
    # Next tick refreshes every role (0 % ROLE_REFRESH_TICKS == 0).
    _ticks_since_rebuild = 0

    var loop_windows := _upstream_windows()
    var windows: Dictionary = {}
    var window_containers: Dictionary = {}
    _window_port.clear()
    _port_windows.clear()
    _loop_containers.clear()

    for port in outputs:
        var container = port.container
        var names: Array = []
        _port_windows[port.uid] = names
        if not is_instance_valid(container):
            continue

        for looping_target in _looping_of(container):
            _loop_containers.append(looping_target)

        for target in _targets_of(container):
            var target_window = BRMUtils.get_parent_window(target)
            if target_window == null or not is_instance_valid(target_window):
                continue
            if target_window == hub or loop_windows.has(str(target_window.name)):
                # Sending this resource there would bring it back into the hub.
                _loop_containers.append(target)
                continue
            var name := str(target_window.name)
            windows[name] = target_window
            window_containers.get_or_add(name, []).append(target.id)
            if not _window_port.has(name):
                # A machine wired to several ports belongs to the first one;
                # its allocation is still split over all its wired inputs.
                _window_port[name] = port.uid
                names.append(name)

    var rebuilt: Dictionary = {}
    for name in windows.keys():
        var data = _wdata.get(name)
        if data == null or data.window != windows[name]:
            data = SmartWindowData.new(windows[name])
        data.set_containers(window_containers[name])
        rebuilt[name] = data
    _wdata = rebuilt
    _tracker.retain(_wdata.keys())


# Every window that can send this resource into the hub, following only
# connections of this resource. Bounded walk, see brm_cycle_guard.gd.
func _upstream_windows() -> Dictionary:
    var names: Dictionary = {}
    if not is_instance_valid(hub):
        return names

    var by_key: Dictionary = {}
    var hub_key := str(hub.get_instance_id())
    by_key[hub_key] = hub
    var channel_resource := resource
    var upstream := func(key: String) -> Array:
        var result: Array = []
        var window = by_key.get(key)
        if not is_instance_valid(window) or not "containers" in window:
            return result
        for container in window.containers:
            if not is_instance_valid(container) or not "input" in container:
                continue
            if "resource" in container and str(container.resource) != channel_resource:
                continue
            var source = container.input
            if source == null or not is_instance_valid(source):
                continue
            var source_window = BRMUtils.get_parent_window(source)
            if source_window == null:
                continue
            var source_key := str(source_window.get_instance_id())
            by_key[source_key] = source_window
            result.append(source_key)
        return result

    var closure := CycleGuard.upstream_closure(hub_key, upstream)
    _graph_truncated = bool(closure.truncated)
    for key in closure.names.keys():
        var window = by_key.get(key)
        if is_instance_valid(window):
            names[str(window.name)] = true
    return names


static func _targets_of(container) -> Array:
    var result: Array = []
    var candidates: Array = []
    if "transfer" in container:
        candidates = container.transfer
    elif "outputs" in container:
        candidates = container.outputs
    var looping: Array = _looping_of(container)
    for target in candidates:
        if is_instance_valid(target) and not looping.has(target):
            result.append(target)
    return result


static func _looping_of(container) -> Array:
    if "looping" in container and container.looping is Array:
        return container.looping
    return []


static func _is_input_connected(container) -> bool:
    if "input_id" in container:
        return not str(container.input_id).is_empty()
    if "input" in container:
        return container.input != null
    return false


static func _empty_stats() -> Dictionary:
    return {
        "supply": 0.0, "connected_inputs": 0, "allocated": 0.0, "unused": 0.0,
        "finite_demand": 0.0, "uncapped": 0, "shortage": false, "invalid_values": 0,
        "targets": 0, "cycles": 0, "graph_truncated": false, "port_count": 0,
    }
