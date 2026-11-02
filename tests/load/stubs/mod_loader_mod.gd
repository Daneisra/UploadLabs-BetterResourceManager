class_name ModLoaderMod extends RefCounted
static var active: Array[String] = []
static var translations: Array[String] = []


static func get_unpacked_dir() -> String:
    return "res://mods-unpacked/"


static func add_translation(path: String) -> void:
    translations.append(path)


static func is_mod_active(mod_id: String) -> bool:
    return active.has(mod_id)
