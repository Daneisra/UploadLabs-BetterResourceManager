extends "res://mods-unpacked/Daneisra-BetterResourceManager/scripts/global/window_graph.gd"

var manager: WindowBase
var depth_to_keep: Dictionary[int, Dictionary]
var filtered: Dictionary[int, Dictionary]


func _init(target_manager: WindowBase) -> void:
    super()
    manager = target_manager
    LOG_NAME = "Daneisra:BRM:SmartWindowGraph"
    add_node_chained(manager)


func request_filter_depth(caller: Object, depth: int):
    if depth_to_keep.has(depth) && depth_to_keep[depth].has(caller):
        return false

    depth_to_keep.get_or_add(depth, {})[caller] = true
    _update_filter(depth)
    return true


func release_filter_depth(caller: Object, depth: int):
    if !depth_to_keep.has(depth) || !depth_to_keep[depth].has(caller):
        return false

    depth_to_keep[depth].erase(caller)

    if depth_to_keep[depth].is_empty():
        depth_to_keep.erase(depth)
        filtered.erase(depth)

    return true


func _on_internal_update() -> void:
    super()

    for depth in depth_to_keep:
        _update_filter(depth)


func _update_filter(depth) -> void:
    # Rebuild instead of updating in place so disconnected/stale windows are
    # removed from the Graph-mode snapshot.
    filtered[depth] = {}

    var keys = nodes.keys().filter(
        is_receiver.bind(manager.name, depth)
    )

    for key in keys:
        filtered[depth][key] = _get_payload(key, keys)


func _get_payload(name: String, allowed_names: Array):
    return {
        "suppliers": _get_filtered_suppliers_count(name, allowed_names),
        "receivers": _get_filtered_receivers_count(name, allowed_names),
    }


func _get_filtered_suppliers_count(
    node: String,
    allowed_names: Array,
    visited = []
) -> int:
    var result = 0

    if !nodes.has(node) || allowed_names.is_empty() || visited.has(node):
        return result

    var next_visited = visited.duplicate()
    next_visited.append(node)

    var next_array = nodes[node].left.filter(allowed_names.has)
    result += next_array.size()

    for next_name in next_array:
        result += _get_filtered_suppliers_count(
            next_name,
            allowed_names,
            next_visited
        )

    return result


func _get_filtered_receivers_count(
    node: String,
    allowed_names: Array,
    visited = []
) -> int:
    var result = 0

    if !nodes.has(node) || allowed_names.is_empty() || visited.has(node):
        return result

    var next_visited = visited.duplicate()
    next_visited.append(node)

    var next_array = nodes[node].right.filter(allowed_names.has)
    result += next_array.size()

    for next_name in next_array:
        result += _get_filtered_receivers_count(
            next_name,
            allowed_names,
            next_visited
        )

    return result
