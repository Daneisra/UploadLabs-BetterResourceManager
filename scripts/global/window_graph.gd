extends RefCounted

const BRMUtils = preload("res://mods-unpacked/Daneisra-BetterResourceManager/scripts/global/brm_utils.gd")

var LOG_NAME = "Daneisra:BRM:WindowGraph"

signal changed
signal _internal_update

var nodes: Dictionary[String, RefCounted]
var container_binds: Dictionary
var DataClass = NodeData

var _runtime_signals_connected = false
var _waiting_for_signals_ready = false


func _init() -> void:
    _connect_signals()


func set_data_holder(type):
    DataClass = type


func add_node(window: WindowBase) -> void:
    if _add_node_silent(window):
        _internal_update.emit()


func remove_node(name: String):
    if _remove_node_silent(name):
        _internal_update.emit()


func add_node_chained(window: WindowBase, trigger_update = true):
    if window == null || nodes.has(window.name):
        return

    _add_node_silent(window)

    for next_window in DataClass.get_inputs_as_window(window):
        add_node_chained(next_window, false)

    for next_window in DataClass.get_outputs_as_window(window):
        add_node_chained(next_window, false)

    if trigger_update:
        _internal_update.emit()


func _add_node_silent(window: WindowBase) -> bool:
    if window == null || nodes.has(window.name):
        return false

    nodes[window.name] = DataClass.new(window)

    for id in nodes[window.name].container_ids:
        container_binds[id] = window.name

    return true


func _remove_node_silent(name: String) -> bool:
    if !nodes.has(name):
        return false

    for other in nodes[name].left:
        _disconnect_name(other, name)

    for other in nodes[name].right:
        _disconnect_name(other, name)

    for id in nodes[name].container_ids:
        container_binds.erase(id)

    nodes.erase(name)
    return true


func _connect_signals() -> void:
    if !Signals:
        ModLoaderLog.error(
            "Signals not found",
            LOG_NAME + ":_connect_signals"
        )
        return

    if !Signals.is_node_ready():
        var callback = Callable(self, "_on_signals_ready")
        if !Signals.ready.is_connected(callback):
            Signals.ready.connect(callback, CONNECT_ONE_SHOT)
            _waiting_for_signals_ready = true
    else:
        _connect_runtime_signals()

    if !_internal_update.is_connected(_on_internal_update):
        _internal_update.connect(_on_internal_update)


func _on_signals_ready() -> void:
    _waiting_for_signals_ready = false
    _connect_runtime_signals()


func _connect_runtime_signals() -> void:
    if _runtime_signals_connected:
        return

    if !Signals.window_deleted.is_connected(_on_window_deleted):
        Signals.window_deleted.connect(_on_window_deleted)

    if !Signals.connection_created.is_connected(_on_connections_changed):
        Signals.connection_created.connect(_on_connections_changed)

    if !Signals.connection_deleted.is_connected(_on_connections_changed):
        Signals.connection_deleted.connect(_on_connections_changed)

    _runtime_signals_connected = true


func dispose() -> void:
    if Signals:
        if Signals.window_deleted.is_connected(_on_window_deleted):
            Signals.window_deleted.disconnect(_on_window_deleted)

        if Signals.connection_created.is_connected(_on_connections_changed):
            Signals.connection_created.disconnect(_on_connections_changed)

        if Signals.connection_deleted.is_connected(_on_connections_changed):
            Signals.connection_deleted.disconnect(_on_connections_changed)

        var ready_callback = Callable(self, "_on_signals_ready")
        if (
            _waiting_for_signals_ready
            && Signals.ready.is_connected(ready_callback)
        ):
            Signals.ready.disconnect(ready_callback)

    if _internal_update.is_connected(_on_internal_update):
        _internal_update.disconnect(_on_internal_update)

    _waiting_for_signals_ready = false
    _runtime_signals_connected = false


func _on_internal_update() -> void:
    call_deferred("emit_signal", "changed")


func _on_connections_changed(output: String, input: String) -> void:
    if !container_binds.has(output) && !container_binds.has(input):
        return

    if container_binds.has(input):
        _update_node(container_binds[input])

    if container_binds.has(output):
        _update_node(container_binds[output])


func _update_node(name: String):
    if !nodes.has(name):
        return

    nodes[name].update_connections()

    for window in DataClass.get_inputs_as_window(nodes[name].window):
        add_node_chained(window, false)

    for window in DataClass.get_outputs_as_window(nodes[name].window):
        add_node_chained(window, false)

    _internal_update.emit()


func _on_window_deleted(window):
    if !window:
        ModLoaderLog.error(
            "Window doesn't exist.",
            LOG_NAME + ":_on_window_deleted"
        )
        return

    remove_node(window.name)


func _disconnect_name(existing: String, disconnected: String):
    if !nodes.has(existing):
        return

    nodes[existing].left = nodes[existing].left.filter(
        func(n): return n != disconnected
    )
    nodes[existing].right = nodes[existing].right.filter(
        func(n): return n != disconnected
    )


func is_receiver(
    node: String,
    source: String,
    depth: int = 0,
    visited: Array = []
) -> bool:
    var result = false

    if (
        !nodes.has(node)
        || !nodes.has(source)
        || visited.has(node)
        || node == source
    ):
        return result

    result = _depends_on(node, source)

    if depth > 0 && !result:
        var next_visited = visited.duplicate()
        next_visited.append(node)
        result = nodes[node].left.filter(
            func(n): return !next_visited.has(n)
        ).any(
            is_receiver.bind(source, depth - 1, next_visited)
        )

    return result


func is_supplier(
    node: String,
    target: String,
    depth: int = 0,
    visited: Array = []
) -> bool:
    var result = false

    if (
        !nodes.has(node)
        || !nodes.has(target)
        || visited.has(node)
        || node == target
    ):
        return result

    result = _source_for(node, target)

    if depth > 0 && !result:
        var next_visited = visited.duplicate()
        next_visited.append(node)
        result = nodes[node].right.filter(
            func(n): return !next_visited.has(n)
        ).any(
            is_supplier.bind(target, depth - 1, next_visited)
        )

    return result


func has_connection(
    node: String,
    to: String,
    depth: int = 0,
    visited: Array = []
) -> bool:
    if !nodes.has(node) || !nodes.has(to) || visited.has(node):
        return false

    if node == to:
        return true

    var connection = _depends_on(node, to) || _source_for(node, to)
    var next_visited = visited.duplicate()
    next_visited.append(node)

    if depth > 0 && !connection:
        connection = nodes[node].left.filter(
            func(n): return !next_visited.has(n)
        ).any(
            has_connection.bind(to, depth - 1, next_visited)
        ) || nodes[node].right.filter(
            func(n): return !next_visited.has(n)
        ).any(
            has_connection.bind(to, depth - 1, next_visited)
        )

    return connection


func _depends_on(node_name: String, target: String) -> bool:
    if !nodes.has(node_name):
        return false
    return nodes[node_name].left.has(target)


func _source_for(node_name: String, target: String) -> bool:
    if !nodes.has(node_name):
        return false
    return nodes[node_name].right.has(target)


class NodeData extends RefCounted:
    const LOG_NAME = "Daneisra:BRM:WindowGraph:NodeData"

    var window: WindowBase = null
    var left: Array = []
    var right: Array = []
    var container_ids: Array = []

    static func get_inputs_as_window(source: WindowBase) -> Array:
        if source:
            return source.containers.map(
                func(c): return c.input
            ).filter(
                func(i): return i != null
            ).map(
                BRMUtils.get_parent_window
            )

        ModLoaderLog.error(
            "Window doesn't exist.",
            LOG_NAME + ":get_inputs_as_window"
        )
        return []

    static func get_outputs_as_window(source: WindowBase) -> Array:
        if source:
            var result = []

            for array in source.containers.map(
                func(c): return c.outputs
            ).filter(
                func(a): return a != null && a.size() > 0
            ):
                result.append_array(
                    array.map(
                        BRMUtils.get_parent_window
                    ).filter(
                        func(w): return w != null
                    )
                )

            return result

        ModLoaderLog.error(
            "Window doesn't exist.",
            LOG_NAME + ":get_outputs_as_window"
        )
        return []

    func _init(target_window: WindowBase) -> void:
        window = target_window
        container_ids = window.containers.map(
            func(c): return c.id
        )
        update_connections()

    func update_connections() -> void:
        left = get_inputs_as_window(window).map(
            func(w): return w.name
        )
        right = get_outputs_as_window(window).map(
            func(w): return w.name
        )
