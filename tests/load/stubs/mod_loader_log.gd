class_name ModLoaderLog extends RefCounted
static var lines: Array[String] = []


static func _add(level: String, message: String, name: String) -> void:
    lines.append("%s %s: %s" % [level, name, message])
    print("%s %s: %s" % [level, name, message])


static func info(message: String, name: String) -> void:
    _add("INFO", message, name)


static func success(message: String, name: String) -> void:
    _add("SUCCESS", message, name)


static func warning(message: String, name: String) -> void:
    _add("WARNING", message, name)


static func error(message: String, name: String) -> void:
    _add("MODERROR", message, name)


static func debug(message: String, name: String) -> void:
    _add("DEBUG", message, name)
