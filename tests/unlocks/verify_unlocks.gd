extends SceneTree

const UNLOCKS := preload("res://manager_unlocks.gd")
var failures := 0
var checks := 0


func _init() -> void:
    var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://brm_data.json"))
    for modern: bool in [false, true]:
        var data := original.duplicate(true)
        var cpu_requirement = ["research.thread_manager"] if modern else "perk.thread_manager"
        var gpu_requirement = ["research.gpu_manager"] if modern else "research.gpu_manager"
        var base := {
            "thread_manager": {"requirement": cpu_requirement},
            "gpu_manager": {"requirement": gpu_requirement}
        }
        if modern:
            base.thread_manager.requirement_mode = 0
            base.gpu_manager.requirement_mode = 1
        UNLOCKS.synchronize(data, base)
        for id: String in ["thread_manager", "gpu_manager"]:
            var smart_id := "smart_" + id
            var requirement = base[id].requirement
            var destinations: Array = [data.windows[smart_id]]
            destinations.append_array(data.guides["window_" + smart_id].entries)
            for entry: Dictionary in destinations:
                check(entry.requirement == requirement, "%s requirement (modern=%s)" % [smart_id, modern])
                check(entry.get("requirement_mode", 0) == base[id].get("requirement_mode", 0), "requirement mode")
                check(not requirements_met(entry.requirement, {}), "locked before base unlock")
                var key: String = requirement[0] if modern else requirement
                check(requirements_met(entry.requirement, {key: true}), "available after base unlock")
            for key: String in original.windows[smart_id]:
                if key == "requirement":
                    continue
                check(data.windows[smart_id][key] == original.windows[smart_id][key], "unrelated metadata unchanged")
        if modern:
            data.windows.smart_thread_manager.requirement.append("mutation")
            check(base.thread_manager.requirement == ["research.thread_manager"], "base array remains independent")
            check(data.guides.window_smart_thread_manager.entries[0].requirement == ["research.thread_manager"], "guide array remains independent")
            data.guides.window_smart_thread_manager.entries[0].requirement.append("mutation")
            check(data.guides.window_smart_thread_manager.entries[1].requirement == ["research.thread_manager"], "guide entries remain independent")

    var unchanged := original.duplicate(true)
    UNLOCKS.synchronize(unchanged, {})
    check(unchanged == original, "missing base definitions retain original gates")
    UNLOCKS.synchronize(unchanged, {"thread_manager": {"requirement": 42}})
    check(unchanged == original, "invalid base requirement retains original gate")
    var stale_mode := original.duplicate(true)
    stale_mode.windows.smart_thread_manager.requirement_mode = 1
    UNLOCKS.synchronize(stale_mode, {"thread_manager": {"requirement": "perk.thread_manager"}})
    check(not stale_mode.windows.smart_thread_manager.has("requirement_mode"), "legacy mode shape restored")
    print("ASM UNLOCKS: %d checks, %d failures" % [checks, failures])
    quit(0 if failures == 0 else 1)


func requirements_met(requirement, unlocked: Dictionary) -> bool:
    var keys: Array = requirement if requirement is Array else [requirement]
    for key: String in keys:
        if not unlocked.get(key, false):
            return false
    return true


func check(condition: bool, label: String) -> void:
    checks += 1
    if not condition:
        failures += 1
        push_error(label)
