extends Node
signal distance_level_set(distance: int)
signal unhandled_input(event: InputEvent, position: Vector2)
signal window_deleted(window)
signal window_moved(window)
signal connection_created(output_id: String, input_id: String)
signal connection_deleted(output_id: String, input_id: String)
