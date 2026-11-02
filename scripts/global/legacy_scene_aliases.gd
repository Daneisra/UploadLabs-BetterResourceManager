extends RefCounted

# Saves remember every window by its scene path ("filename", relative to
# res://scenes/windows/). Smart managers placed with kuuk's mods or with
# Adaptive Smart Manager therefore point at another mod's folder:
#
#   ../../mods-unpacked/kuuk-SmartThreadManager/scenes/windows/window_smart_thread_manager.tscn
#
# Instead of rewriting the save, BRM loads its own manager scene a second time
# and makes that copy own the legacy path in Godot's resource cache
# (Resource.take_over_path). Loading the legacy path then returns the BRM scene
# while the alias is held. Windows loaded that way keep saving the legacy path
# (see window_smart_manager.gd), so the save stays readable by the original
# mods: nothing is migrated and the change is reversible.
#
# Mod Loader mounts every ZIP, even disabled ones, so a legacy file can exist
# in res:// while its mod is inactive. The cache entry takes precedence over
# the file for ordinary load() calls; the alias is only skipped when the legacy
# mod is actually active (BRM then registers nothing that could collide).

const LEGACY_SCENES := {
    "res://mods-unpacked/kuuk-SmartThreadManager/scenes/windows/window_smart_thread_manager.tscn": "window_smart_thread_manager.tscn",
    "res://mods-unpacked/kuuk-SmartGPUManager/scenes/windows/window_smart_gpu_manager.tscn": "window_smart_gpu_manager.tscn",
    "res://mods-unpacked/guardipee14-AdaptiveSmartManager/scenes/windows/window_smart_thread_manager.tscn": "window_smart_thread_manager.tscn",
    "res://mods-unpacked/guardipee14-AdaptiveSmartManager/scenes/windows/window_smart_gpu_manager.tscn": "window_smart_gpu_manager.tscn",
}

var _held: Array[Resource] = []
var installed: Array[String] = []
var failed: Array[String] = []


func install(scene_directory: String) -> bool:
    for alias_path: String in LEGACY_SCENES.keys():
        var source_path := scene_directory.path_join(str(LEGACY_SCENES[alias_path]))
        var scene := ResourceLoader.load(source_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
        if not scene is PackedScene:
            failed.append(alias_path)
            continue

        scene.take_over_path(alias_path)
        _held.append(scene)

        var resolved := ResourceLoader.load(alias_path, "PackedScene")
        if resolved == scene:
            installed.append(alias_path)
        else:
            failed.append(alias_path)

    return failed.is_empty()


func release() -> void:
    _held.clear()
    installed.clear()


# res://scenes/windows/ relative form used by save files.
static func to_save_filename(scene_path: String) -> String:
    if scene_path.begins_with("res://scenes/windows/"):
        return scene_path.trim_prefix("res://scenes/windows/")
    if scene_path.begins_with("res://"):
        return "../../" + scene_path.trim_prefix("res://")
    return scene_path
