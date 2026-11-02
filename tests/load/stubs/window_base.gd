class_name WindowBase extends Control
# Test double of Upload Labs' WindowBase (only what BRM uses).
var containers: Array[ResourceContainer] = []
var paused: bool = false
var importing: bool = false
var closing: bool = false


func _ready() -> void:
    for node in find_children("*", "ResourceContainer", true, false):
        if not containers.has(node):
            containers.append(node)


func save() -> Dictionary:
    var container_data: Dictionary = {}
    for container in containers:
        container_data[str(get_path_to(container))] = {"id": container.id, "outputs_id": container.outputs_id.duplicate()}
    return {"container_data": container_data, "name": str(name)}


func export() -> Dictionary:
    return save()
