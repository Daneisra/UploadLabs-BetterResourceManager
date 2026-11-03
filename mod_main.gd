extends Node

const MOD_DIR := "Daneisra-BetterResourceManager"
const MOD_ID := "Daneisra-BetterResourceManager"
const MOD_VERSION := "0.1.0"
const MOD_BUILD := "rc.1"
const LOG_NAME := "Daneisra:BRM:Main"
const MOD_ROOT := "res://mods-unpacked/Daneisra-BetterResourceManager"
const MANAGER_UNLOCKS := preload("res://mods-unpacked/Daneisra-BetterResourceManager/scripts/global/manager_unlocks.gd")
const LEGACY_ALIASES := preload("res://mods-unpacked/Daneisra-BetterResourceManager/scripts/global/legacy_scene_aliases.gd")

# Mods that register the same smart_thread_manager / smart_gpu_manager ids.
# Mod Loader 7.0.1 reads manifest incompatibilities but does not enforce them,
# so BRM checks for them itself before registering anything that could collide.
const LEGACY_CONFLICTS := [
    "kuuk-SmartThreadManager",
    "kuuk-SmartGPUManager",
    "guardipee14-AdaptiveSmartManager",
]
const LEGACY_WINDOW_IDS := ["smart_thread_manager", "smart_gpu_manager"]
const HUB_WINDOW_ID := "better_resource_hub"

const RUNTIME_PREFLIGHT_PATHS := [
    MOD_ROOT + "/scripts/core/brm_allocator.gd",
    MOD_ROOT + "/scripts/core/brm_demand_tracker.gd",
    MOD_ROOT + "/scripts/core/brm_port_layout.gd",
    MOD_ROOT + "/scripts/core/brm_cycle_guard.gd",
    MOD_ROOT + "/scripts/core/brm_diagnostics.gd",
    MOD_ROOT + "/scripts/global/brm_utils.gd",
    MOD_ROOT + "/scripts/global/window_graph.gd",
    MOD_ROOT + "/scripts/global/smart_window_graph.gd",
    MOD_ROOT + "/scripts/global/smart_window_data.gd",
    MOD_ROOT + "/scripts/global/distribution_modes.gd",
    MOD_ROOT + "/scripts/global/legacy_scene_aliases.gd",
    MOD_ROOT + "/scripts/global/brm_runtime_probe.gd",
    MOD_ROOT + "/scripts/smart_resource_container.gd",
    MOD_ROOT + "/scripts/option_desktop_button.gd",
    MOD_ROOT + "/scripts/toggle_desktop_button.gd",
    MOD_ROOT + "/scripts/hub/brm_action_button.gd",
    MOD_ROOT + "/scripts/hub/brm_output_port.gd",
    MOD_ROOT + "/scripts/hub/brm_resource_channel.gd",
    MOD_ROOT + "/scripts/hub/brm_hub_ui.gd",
    MOD_ROOT + "/scenes/windows/window_smart_manager.gd",
    MOD_ROOT + "/scenes/windows/window_better_resource_hub.gd",
    MOD_ROOT + "/scenes/windows/window_smart_thread_manager.tscn",
    MOD_ROOT + "/scenes/windows/window_smart_gpu_manager.tscn",
    MOD_ROOT + "/scenes/windows/window_better_resource_hub.tscn",
    MOD_ROOT + "/scenes/ports/brm_input_port.tscn",
    MOD_ROOT + "/scenes/ports/brm_output_port.tscn",
]

var mod_dir_path := ""
var translations_dir_path := ""
var legacy_aliases = null
var active_conflicts: Array[String] = []


static func _normalized_versions(value) -> Array[String]:
    var result: Array[String] = []

    if value is Array:
        for item in value:
            var version := str(item).strip_edges()
            if not version.is_empty():
                result.append(version)
        return result

    if value is String:
        for item in str(value).split(",", false):
            var version := str(item).strip_edges()
            if not version.is_empty():
                result.append(version)

    return result


static func _get_compat_array(manifest: Dictionary) -> Array[String]:
    var godot: Dictionary = manifest.get("extra", {}).get("godot", {})
    return _normalized_versions(godot.get("compatible_game_version", []))


static func is_good_version(manifest: Dictionary) -> bool:
    var project_version := str(
        ProjectSettings.get_setting("application/config/version", "0.0.0")
    )
    return _get_compat_array(manifest).has(project_version)


func _init() -> void:
    mod_dir_path = ModLoaderMod.get_unpacked_dir().path_join(MOD_DIR)

    var manifest := _read_json_dictionary(
        mod_dir_path.path_join("manifest.json"),
        "manifest"
    )

    if manifest.is_empty():
        ModLoaderLog.error(
            "Manifest could not be loaded. Initialization stopped.",
            LOG_NAME
        )
        return

    if not is_good_version(manifest):
        ModLoaderLog.warning(
            "Game version '%s' is not in tested versions %s. Loading is allowed for compatibility testing." % [
                ProjectSettings.get_setting("application/config/version", "0.0.0"),
                str(_get_compat_array(manifest))
            ],
            LOG_NAME
        )

    _add_translations()

    ModLoaderLog.success(
        "Better Resource Manager initialized, version: %s-%s" % [MOD_VERSION, MOD_BUILD],
        LOG_NAME
    )


func _ready() -> void:
    ModLoaderLog.info("Window registration started...", LOG_NAME)

    if not has_node("/root/Data"):
        ModLoaderLog.error(
            "No Data singleton found. Window registration stopped.",
            LOG_NAME
        )
        return

    if not _validate_runtime_resources():
        ModLoaderLog.error(
            "Runtime preflight failed. No Better Resource Manager windows were registered.",
            LOG_NAME
        )
        return

    active_conflicts = _find_active_conflicts()
    if not active_conflicts.is_empty():
        ModLoaderLog.error(
            "Conflicting manager mods are active: %s. BRM does not register Smart Thread/GPU Manager nor install legacy scene aliases while they run. Disable them in the mod list, then restart. Better Resource Hub is still registered under its own id." % ", ".join(active_conflicts),
            LOG_NAME
        )

    var registered := _add_to_data(active_conflicts.is_empty())

    # Only redirect legacy scene paths when BRM itself owns both legacy ids;
    # otherwise another mod's managers would load BRM scenes.
    if active_conflicts.is_empty() and LEGACY_WINDOW_IDS.all(func(id): return registered.has(id)):
        _install_legacy_aliases()
    elif active_conflicts.is_empty():
        ModLoaderLog.warning(
            "Legacy scene aliases not installed: BRM did not register both smart manager ids.",
            LOG_NAME
        )


func _find_active_conflicts() -> Array[String]:
    var result: Array[String] = []
    for mod_id: String in LEGACY_CONFLICTS:
        if ModLoaderMod.is_mod_active(mod_id):
            result.append(mod_id)
    return result


func _install_legacy_aliases() -> void:
    legacy_aliases = LEGACY_ALIASES.new()
    var success: bool = legacy_aliases.install(mod_dir_path.path_join("scenes/windows"))
    for path in legacy_aliases.installed:
        ModLoaderLog.info("Legacy scene alias active: %s" % path, LOG_NAME)
    for path in legacy_aliases.failed:
        ModLoaderLog.error(
            "Legacy scene alias could not be verified: %s. Saved managers from that mod may not load; do not save over your main slot until this is resolved." % path,
            LOG_NAME
        )
    if success:
        ModLoaderLog.success(
            "Legacy smart manager scene paths resolve to BRM (%d aliases)." % legacy_aliases.installed.size(),
            LOG_NAME
        )


func _validate_runtime_resources() -> bool:
    var success := true

    for raw_path in RUNTIME_PREFLIGHT_PATHS:
        var path := str(raw_path)

        if not ResourceLoader.exists(path):
            ModLoaderLog.error(
                "Runtime preflight resource does not exist: %s" % path,
                LOG_NAME
            )
            success = false
            continue

        var loaded_resource = load(path)
        if loaded_resource == null:
            ModLoaderLog.error(
                "Runtime preflight could not load: %s" % path,
                LOG_NAME
            )
            success = false
            continue

        if loaded_resource is Script:
            var script_resource: Script = loaded_resource
            if not script_resource.can_instantiate():
                ModLoaderLog.error(
                    "Runtime preflight script cannot instantiate: %s" % path,
                    LOG_NAME
                )
                success = false

    if success:
        ModLoaderLog.success(
            "Runtime preflight passed for %d scripts/scenes." % RUNTIME_PREFLIGHT_PATHS.size(),
            LOG_NAME
        )

    return success


func _add_translations() -> void:
    translations_dir_path = mod_dir_path.path_join("translations")

    # Use the res:// resource path directly so this works for mounted ZIP mods,
    # not only physically unpacked directories.
    var names := Array(DirAccess.get_files_at(translations_dir_path))
    names.sort()
    for raw_name in names:
        var name := str(raw_name)
        if name.ends_with(".translation"):
            ModLoaderMod.add_translation(
                translations_dir_path.path_join(name)
            )


func _add_to_data(include_legacy: bool) -> Array[String]:
    var path := mod_dir_path.path_join("data/brm_data.json")
    var data := _read_json_dictionary(path, "data")

    if data.is_empty():
        ModLoaderLog.error(
            "Data registry could not be loaded.",
            LOG_NAME
        )
        return []

    if not include_legacy:
        for window_id: String in LEGACY_WINDOW_IDS:
            data.windows.erase(window_id)
            data.guides.erase("window_" + window_id)

    # 3.0 moved Thread Manager from a token perk to ordinary research.
    # Follow the installed game's base managers, not a version-specific key.
    MANAGER_UNLOCKS.synchronize(data, Data.windows)
    for window_id in data.windows.keys():
        ModLoaderLog.info(
            "%s unlock follows base manager: %s" % [window_id, str(data.windows[window_id].requirement)],
            LOG_NAME
        )

    var success := true
    var registered_windows: Array[String] = []

    for raw_key in data.keys():
        var key := str(raw_key)
        var incoming = data[raw_key]

        if not incoming is Dictionary:
            ModLoaderLog.error(
                "Data.%s is not a dictionary. Skipping." % key,
                LOG_NAME
            )
            success = false
            continue

        var registry = Data.get(key)
        if not registry is Dictionary:
            ModLoaderLog.error(
                "Data.%s is unavailable or is not a dictionary. Skipping." % key,
                LOG_NAME
            )
            success = false
            continue

        for raw_entry in incoming.keys():
            var entry := str(raw_entry)

            # Check the registry KEY, never overwrite another registration.
            if registry.has(entry):
                ModLoaderLog.error(
                    "Data.%s.%s already exists. Better Resource Manager will not overwrite it. Remove the original Smart Thread/GPU Manager or Adaptive Smart Manager mods before using BRM." % [
                        key,
                        entry
                    ],
                    LOG_NAME
                )
                success = false
                continue

            registry[entry] = incoming[raw_entry]

            if key == "windows":
                registered_windows.append(entry)

    for entry in registered_windows:
        if not Attributes.window_attributes.has(entry):
            Attributes.window_attributes[entry] = {}

        var attributes = Data.windows[entry].get("attributes", {})
        if attributes is Dictionary:
            for raw_attr_name in attributes.keys():
                var attr_name := str(raw_attr_name)
                Attributes.window_attributes[entry][attr_name] = Attribute.new(
                    attributes[raw_attr_name]
                )

    if success:
        ModLoaderLog.success(
            "Registered windows: %s" % ", ".join(registered_windows),
            LOG_NAME
        )
    elif not registered_windows.is_empty():
        ModLoaderLog.warning(
            "Better Resource Manager registered only: %s; check for conflicting mods." % ", ".join(registered_windows),
            LOG_NAME
        )
    else:
        ModLoaderLog.error(
            "No Better Resource Manager windows were registered.",
            LOG_NAME
        )

    return registered_windows


func get_aac_compatibility_info() -> Dictionary:
    return {
        "provider": MOD_ID,
        "version": "%s-%s" % [MOD_VERSION, MOD_BUILD],
        "window_ids": [
            "smart_thread_manager",
            "smart_gpu_manager",
            HUB_WINDOW_ID
        ],
        "resources": [
            "clock_speed",
            "gpu_speed"
        ],
        "semantics": {
            "count": "live_manager_supply",
            "demand": "finite_bound_window_demand",
            "uncapped_target_count": "connected_targets_without_a_finite_material_derived_cap",
            "window_binds": "read_only_compatibility_view"
        },
        "topology_control": false
    }


func _read_json_dictionary(path: String, label: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        ModLoaderLog.error(
            "%s file not found: %s" % [label.capitalize(), path],
            LOG_NAME
        )
        return {}

    var text := FileAccess.get_file_as_string(path)
    var parsed = JSON.parse_string(text)

    if not parsed is Dictionary:
        ModLoaderLog.error(
            "%s JSON is invalid or is not a dictionary: %s" % [
                label.capitalize(),
                path
            ],
            LOG_NAME
        )
        return {}

    return parsed
