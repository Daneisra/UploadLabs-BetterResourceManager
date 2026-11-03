class_name ResourceContainer extends Node
# Test double of Upload Labs' ResourceContainer: only the members BRM reads.
var id: String = ""
var type: int = 0
var resource: String = ""
var required: float = 1.0
var production: float = 0.0
var count: float = 0.0
var input = null
var input_id: String = ""
var outputs: Array = []
var outputs_id: Array[String] = []
var transfer: Array = []
var looping: Array = []
var default_resource: String = ""
var force_resource: bool = false
var limit: float = -1.0
var suffix: String = "Hz"


func update_connections() -> void:
    pass


func tick() -> void:
    pass
