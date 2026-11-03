class_name WindowBase extends VBoxContainer
# Test double of Upload Labs' WindowBase (only what BRM uses). Like the real
# window (observed in game), containers are collected before the subclass
# _ready body runs, so nodes added inside a subclass _ready are missed.
var paused: bool = false
var importing: bool = false
var closing: bool = false
@onready var containers: Array[ResourceContainer] = _collect_containers()


func _collect_containers() -> Array[ResourceContainer]:
    var result: Array[ResourceContainer] = []
    # owned = true, like find_children()'s default: only nodes owned by the
    # window are containers (observed in game).
    for node in find_children("*", "ResourceContainer", true, true):
        result.append(node)
    return result


var base_enter_tree_calls := 0


func _enter_tree() -> void:
    base_enter_tree_calls += 1


func _ready() -> void:
    pass


func save() -> Dictionary:
    var container_data: Dictionary = {}
    for container in containers:
        container_data[str(get_path_to(container))] = {"id": container.id, "outputs_id": container.outputs_id.duplicate()}
    return {"container_data": container_data, "name": str(name)}


func export() -> Dictionary:
    return save()
