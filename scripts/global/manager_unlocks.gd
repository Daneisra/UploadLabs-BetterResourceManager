extends RefCounted

# Each BRM window unlocks with the installed game's ordinary manager. 3.0
# moved Thread Manager from a token perk to research, so the requirement is
# read from the game at registration time instead of being hard-coded.
const UNLOCK_SOURCES := {
    "smart_thread_manager": "thread_manager",
    "smart_gpu_manager": "gpu_manager",
    "better_resource_hub": "thread_manager",
}


static func synchronize(data: Dictionary, base_windows: Dictionary) -> void:
    for smart_id: String in UNLOCK_SOURCES.keys():
        if not data.get("windows", {}).has(smart_id):
            continue
        var base_definition: Dictionary = base_windows.get(UNLOCK_SOURCES[smart_id], {})
        if not base_definition.has("requirement"):
            continue

        var requirement = base_definition.requirement
        if not requirement is String and not requirement is Array:
            continue

        var destinations: Array = [data.windows[smart_id]]
        var guide: Dictionary = data.get("guides", {}).get("window_" + smart_id, {})
        destinations.append_array(guide.get("entries", []))
        for destination: Dictionary in destinations:
            # Do not share mutable arrays with Data or between guide entries.
            destination.requirement = requirement.duplicate(true) if requirement is Array else requirement
            if base_definition.has("requirement_mode"):
                destination.requirement_mode = base_definition.requirement_mode
            else:
                destination.erase("requirement_mode")
