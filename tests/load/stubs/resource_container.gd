class_name ResourceContainer extends Control
signal resource_set
signal connection_out_set
@export var default_resource: String = ""
@export var force_resource: bool = false
@export var limit: float = -1.0
@export var exporting: Array[Node] = []
var id: String = ""
var type: int = 1
var resource: String = ""
var variation: int = 0
var required: float = 1.0
var production: float = 0.0
var count: float = 0.0
var suffix: String = "Hz"
var input = null
var input_id: String = ""
var outputs: Array = []
var outputs_id: Array[String] = []
var transfer: Array = []
var looping: Array = []


func _ready() -> void:
    if id.is_empty():
        id = "stub%d" % get_instance_id()
    resource = default_resource


func set_resource(value: String, _variation: int = 0) -> void:
    resource = value
    resource_set.emit()


func update_connections() -> void:
    pass


func tick() -> void:
    pass
