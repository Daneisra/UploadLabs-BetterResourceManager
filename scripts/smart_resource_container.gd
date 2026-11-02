extends ResourceContainer

const SmartWindowGraph = preload(
    "res://mods-unpacked/Daneisra-BetterResourceManager/scripts/global/smart_window_graph.gd"
)
const SmartWindowData = preload(
    "res://mods-unpacked/Daneisra-BetterResourceManager/scripts/global/smart_window_data.gd"
)
const SmartDistribution = preload(
    "res://mods-unpacked/Daneisra-BetterResourceManager/scripts/global/distribution_modes.gd"
)
const BRMUtils = preload(
    "res://mods-unpacked/Daneisra-BetterResourceManager/scripts/global/brm_utils.gd"
)
const BRMAllocator = preload(
    "res://mods-unpacked/Daneisra-BetterResourceManager/scripts/core/brm_allocator.gd"
)
const BRMDemandTracker = preload(
    "res://mods-unpacked/Daneisra-BetterResourceManager/scripts/core/brm_demand_tracker.gd"
)
const DISTRIBUTION_LOG_PREFIX := "[Daneisra-BetterResourceManager][Distribution]"

@export var use_count: bool = false

var _distribution_mode: int = 0

@export_enum("Ratio", "Demand", "Graph", "Auto")
var distribution_mode: int = 0:
    get:
        return _distribution_mode
    set(value):
        _distribution_mode = clampi(int(value), 0, 3)
        data_changed = true


var demand: float = 0.0
# Finite demand is the value used by the original Ratio / Demand / Graph
# algorithms. Some speed-only windows have no finite material-derived cap and
# are intentionally handled by the original fallback/storage path instead.
var finite_demand: float = 0.0
var uncapped_target_count: int = 0
var uncapped_starved_count: int = 0
var uncapped_allocated_total: float = 0.0
var bound_window_count: int = 0
var graph = null

# AAC compatibility surface. This is derived from the manager's existing
# internal window data and is never used to mutate topology.
var window_binds: Dictionary = {}

var state: Dictionary = {
    "wdata": {},
    "consumers": [],
    "managers": [],
    "storages": [],
    "storage_connections": 0
}

var state_keep := ["wdata"]
var data_changed := false
var distribution_callable: Callable
var _auto_tracker = BRMDemandTracker.new()
var _validation_samples_remaining: int = 0
const CONSERVATION_RELATIVE_WARNING_THRESHOLD := 0.000001
var _validation_reason: String = ""
var _validation_sequence: int = 0


enum SmartContainerMode {
    RATIO = 0,
    DEMAND = 1,
    GRAPH = 2,
    AUTO = 3,
}


func _ready() -> void:
    super()
    data_changed = true
    request_distribution_validation("initial")


func _on_graph_changed() -> void:
    data_changed = true


func update_connections() -> void:
    super()
    data_changed = true
    request_distribution_validation("topology_change")


func tick() -> void:
    # Update must always happen before distribution.
    if data_changed:
        _update_data()
        _update_callable(distribution_mode)
        data_changed = false

    # Preserve vanilla ResourceContainer behavior.
    for item: ResourceContainer in looping:
        item.count = 0

    _update_state_tick()

    if not distribution_callable.is_valid():
        _update_callable(distribution_mode)

    distribution_callable.call(count, state)
    demand = float(state.get_or_add("demand", 0.0))
    finite_demand = demand
    bound_window_count = int(state.wdata.size())
    uncapped_target_count = int(state.storages.size())
    _update_uncapped_allocation_state()

    if _validation_samples_remaining > 0:
        _log_distribution_validation()
        _validation_samples_remaining -= 1


func _allocation_for_data(data) -> float:
    var total := 0.0
    if data == null:
        return total
    for provided_id in data.provided:
        if data.inputs.has(provided_id):
            total += float(data.inputs[provided_id].count)
    return total


func _update_uncapped_allocation_state() -> void:
    uncapped_starved_count = 0
    uncapped_allocated_total = 0.0

    for name in state.storages:
        if not state.wdata.has(name):
            continue
        var amount := _allocation_for_data(state.wdata[name])
        uncapped_allocated_total += amount
        if is_zero_approx(amount):
            uncapped_starved_count += 1


func _finite_starved_count() -> int:
    var count_starved := 0
    var finite_names: Array = []
    finite_names.append_array(state.consumers)
    finite_names.append_array(state.managers)

    for name in finite_names:
        if not state.wdata.has(name):
            continue
        var target_demand := float(state.demands.get(name, 0.0))
        var amount := _allocation_for_data(state.wdata[name])
        if target_demand > 0.0 and is_zero_approx(amount):
            count_starved += 1

    return count_starved


func _lowest_finite_allocation_summary(limit: int = 5) -> String:
    var entries: Array = []
    var finite_names: Array = []
    finite_names.append_array(state.consumers)
    finite_names.append_array(state.managers)

    for name in finite_names:
        if not state.wdata.has(name):
            continue

        # Keep this diagnostic focused on actual finite demand. A connected
        # consumer with zero current demand is idle, not starved.
        var target_demand := float(state.demands.get(name, 0.0))
        if target_demand <= 0.0 or is_zero_approx(target_demand):
            continue

        entries.append({
            "name": str(name),
            "amount": _allocation_for_data(state.wdata[name])
        })

    entries.sort_custom(func(a, b): return float(a["amount"]) < float(b["amount"]))

    var parts: Array[String] = []
    for index in range(mini(limit, entries.size())):
        var entry = entries[index]
        parts.append("%s:%s" % [str(entry["name"]), _format_metric(float(entry["amount"]))])

    return ",".join(parts)


func request_distribution_validation(reason: String = "manual") -> void:
    _validation_reason = reason
    _validation_samples_remaining = maxi(_validation_samples_remaining, 1)


func _log_distribution_validation() -> void:
    _validation_sequence += 1

    var total_allocated := 0.0
    for raw_name in state.wdata.keys():
        total_allocated += _allocation_for_data(state.wdata[raw_name])

    var lowest_finite := _lowest_finite_allocation_summary()
    var finite_starved := _finite_starved_count()

    var residual := float(count) - total_allocated
    var unused_headroom := maxf(residual, 0.0)
    var overallocated := maxf(-residual, 0.0)
    var supply_abs := absf(float(count))
    var unused_headroom_relative := 0.0
    var overallocated_relative := 0.0
    if supply_abs > 0.0:
        unused_headroom_relative = unused_headroom / supply_abs
        overallocated_relative = overallocated / supply_abs

    print("%s Sample seq=%d reason='%s' mode=%d(%s) use_count=%s supply='%s' finite_demand='%s' uncapped=%d uncapped_starved=%d uncapped_allocated='%s' bound_windows=%d allocated='%s' unused_headroom='%s' unused_headroom_relative=%s overallocated='%s' overallocated_relative=%s consumers=%d finite_starved=%d managers=%d storages=%d graph_suppliers=%d graph_receivers=%d lowest_finite='%s'" % [
        DISTRIBUTION_LOG_PREFIX,
        _validation_sequence,
        _validation_reason,
        distribution_mode,
        _mode_name(distribution_mode),
        str(use_count),
        _format_metric(float(count)),
        _format_metric(float(demand)),
        int(uncapped_target_count),
        int(uncapped_starved_count),
        _format_metric(float(uncapped_allocated_total)),
        int(bound_window_count),
        _format_metric(total_allocated),
        _format_metric(unused_headroom),
        str(unused_headroom_relative),
        _format_metric(overallocated),
        str(overallocated_relative),
        state.consumers.size(),
        finite_starved,
        state.managers.size(),
        state.storages.size(),
        state.get_or_add("line_suppliers", []).size(),
        state.get_or_add("line_receivers", []).size(),
        lowest_finite
    ])

    # Unused supply is valid headroom (especially in Demand mode when all
    # finite demand is already satisfied). Only over-allocation violates the
    # manager's conservation contract.
    if overallocated_relative > CONSERVATION_RELATIVE_WARNING_THRESHOLD:
        push_warning("%s Distribution over-allocation exceeded tolerance: supply=%s allocated=%s overallocated=%s relative=%s" % [
            DISTRIBUTION_LOG_PREFIX,
            _format_metric(float(count)),
            _format_metric(total_allocated),
            _format_metric(overallocated),
            str(overallocated_relative)
        ])


func _format_metric(value: float) -> String:
    if is_nan(value):
        return "NaN"
    if is_inf(value):
        return "∞" if value > 0.0 else "-∞"
    return Utils.print_string(value)


func _mode_name(mode: int) -> String:
    match mode:
        SmartContainerMode.RATIO:
            return "Ratio"
        SmartContainerMode.DEMAND:
            return "Demand"
        SmartContainerMode.GRAPH:
            return "Graph"
        SmartContainerMode.AUTO:
            return "Auto"
        _:
            return "Unknown"


func _role_name(role_value: int) -> String:
    match role_value:
        SmartWindowData.SmartWindowRoles.ARTIFACT:
            return "artifact"
        SmartWindowData.SmartWindowRoles.CONSUMER:
            return "consumer"
        SmartWindowData.SmartWindowRoles.STORAGE:
            return "uncapped_storage"
        SmartWindowData.SmartWindowRoles.MANAGER:
            return "manager"
        _:
            return "unknown"


func _update_callable(mode: int) -> void:
    match mode:
        SmartContainerMode.RATIO:
            distribution_callable = SmartDistribution.distribution_ratio
        SmartContainerMode.DEMAND:
            distribution_callable = SmartDistribution.distribution_demand
        SmartContainerMode.GRAPH:
            distribution_callable = SmartDistribution.distribution_graph
        SmartContainerMode.AUTO:
            distribution_callable = SmartDistribution.distribution_auto
        _:
            distribution_callable = SmartDistribution.distribution_ratio


func _clear_state() -> void:
    for key in state.keys():
        if not state_keep.has(key):
            state.erase(key)


func _update_data() -> void:
    _clear_state()
    _update_windows(state)
    _update_graph(
        state,
        distribution_mode == SmartContainerMode.GRAPH
    )
    _refresh_aac_window_binds()


func _update_state_tick() -> void:
    for data in state.wdata.values():
        data.update()
    _wdata_set_roles(state)
    if graph != null:
        _wdata_set_graph_roles(state)
    state.demands = _get_demands(state)
    if distribution_mode == SmartContainerMode.AUTO:
        var auto_demands: Dictionary = {}
        for name in state.wdata.keys():
            auto_demands[name] = state.wdata[name].get_auto_demand()
        state.auto_demands = auto_demands
        state.allocator = BRMAllocator
        state.tracker = _auto_tracker
        _auto_tracker.retain(Array(state.wdata.keys()).map(func(key): return str(key)))


func _update_windows(target_state: Dictionary) -> void:
    _update_wdata(
        transfer,
        target_state.wdata
    )
    _wdata_set_roles(target_state)


func _update_graph(
    target_state: Dictionary,
    need_graph: bool = true
) -> void:
    if not need_graph and graph != null:
        var callback: Callable = Callable(self, "_on_graph_changed")
        if graph.changed.is_connected(callback):
            graph.changed.disconnect(callback)

        graph.release_filter_depth(self, 0)
        graph.dispose()
        graph = null

    if need_graph and graph == null:
        var manager_window = BRMUtils.get_parent_window(self)
        if manager_window == null:
            return

        graph = SmartWindowGraph.new(manager_window)
        graph.request_filter_depth(self, 0)

        var callback: Callable = Callable(self, "_on_graph_changed")
        if not graph.changed.is_connected(callback):
            graph.changed.connect(callback)

    if graph != null:
        _wdata_set_graph_roles(target_state)


func _update_wdata(
    target_inputs: Array[ResourceContainer],
    wdata: Dictionary
) -> void:
    var windows: Array = []
    var ids: Array = []

    for container: ResourceContainer in target_inputs:
        ids.append(container.id)
        var target_window = BRMUtils.get_parent_window(container)
        if target_window != null:
            windows.append(target_window)

    for target_window in windows:
        wdata.get_or_add(
            target_window.name,
            SmartWindowData.new(target_window)
        ).set_containers(ids)

    var names: Array = []
    for target_window in windows:
        names.append(target_window.name)

    for key: StringName in wdata.keys():
        if not names.has(key):
            wdata.erase(key)


func _wdata_set_roles(target_state: Dictionary) -> void:
    var consumers: Array = []
    var managers: Array = []
    var storages: Array = []
    var storage_connections := 0

    for name in target_state.wdata.keys():
        var role = target_state.wdata[name].role

        match role:
            SmartWindowData.SmartWindowRoles.CONSUMER:
                consumers.append(name)
            SmartWindowData.SmartWindowRoles.MANAGER:
                var manager_data = target_state.wdata[name]
                if manager_data.is_uncapped_manager() and manager_data.get_demand() <= 0.0:
                    # A downstream hub that only feeds uncapped machines would
                    # get 0 as a finite manager: Ratio/Demand/Graph give it the
                    # leftovers like any other uncapped target instead.
                    storages.append(name)
                    storage_connections += manager_data.provided.size()
                else:
                    managers.append(name)
            SmartWindowData.SmartWindowRoles.STORAGE:
                storages.append(name)
                storage_connections += target_state.wdata[name].provided.size()

    target_state.consumers = consumers
    target_state.managers = managers
    target_state.storages = storages
    target_state.storage_connections = storage_connections


func _wdata_set_graph_roles(target_state: Dictionary) -> void:
    var filtered_depth: Dictionary = {}
    if graph != null:
        var raw_filtered = graph.filtered.get(0, {})
        if raw_filtered is Dictionary:
            filtered_depth = raw_filtered

    var line_suppliers: Array = []
    for name in target_state.consumers:
        var payload: Dictionary = {}
        var raw_payload = filtered_depth.get(
            name,
            {
                "suppliers": 0,
                "receivers": 0
            }
        )
        if raw_payload is Dictionary:
            payload = raw_payload

        if int(payload.get("suppliers", 0)) == 0:
            line_suppliers.append(name)

    for name in target_state.managers:
        if not line_suppliers.has(name):
            line_suppliers.append(name)

    var line_receivers: Array = []
    for name in target_state.consumers:
        if not line_suppliers.has(name):
            line_receivers.append(name)

    target_state.line_suppliers = line_suppliers
    target_state.line_receivers = line_receivers


func _get_demands(target_state: Dictionary) -> Dictionary:
    var output: Dictionary = {}

    for name in target_state.wdata.keys():
        output[name] = (
            target_state.wdata[name].get_count_demand()
            if use_count
            else target_state.wdata[name].get_demand()
        )

    return output


func _refresh_aac_window_binds() -> void:
    window_binds.clear()

    for data in state.wdata.values():
        if (
            data != null
            and is_instance_valid(data.window)
        ):
            window_binds[data.window] = data


func get_aac_manager_snapshot() -> Dictionary:
    var parent_window = BRMUtils.get_parent_window(self)
    var bindings: Array[Dictionary] = []

    for data in window_binds.values():
        bindings.append({
            "window_name": (
                str(data.window.name)
                if is_instance_valid(data.window)
                else ""
            ),
            "demand": (
                data.get_count_demand()
                if use_count
                else data.get_demand()
            ),
            "own_source_count": data.provided.size()
        })

    return {
        "provider": "Daneisra-BetterResourceManager",
        "window_name": (
            str(parent_window.name)
            if is_instance_valid(parent_window)
            else ""
        ),
        "resource": str(resource),
        "count": float(count),
        "demand": float(demand),
        "finite_demand": float(finite_demand),
        "uncapped_target_count": int(uncapped_target_count),
        "uncapped_starved_count": int(uncapped_starved_count),
        "uncapped_allocated_total": float(uncapped_allocated_total),
        "bound_window_count": int(bound_window_count),
        "distribution_mode": int(distribution_mode),
        "use_count": use_count,
        "bindings": bindings,
        "read_only": true
    }


func _exit_tree() -> void:
    if graph != null:
        var callback: Callable = Callable(self, "_on_graph_changed")
        if graph.changed.is_connected(callback):
            graph.changed.disconnect(callback)

        graph.release_filter_depth(self, 0)
        graph.dispose()
        graph = null

    window_binds.clear()
