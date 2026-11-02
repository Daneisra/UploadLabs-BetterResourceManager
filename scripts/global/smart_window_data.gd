extends RefCounted

# Auto mode also counts material already waiting in a consumer's buffer: a
# machine with a large backlog can use more CPU/GPU than its inflow alone
# suggests (see docs/ARCHITECTURE.md, "AI Trainer under-allocation").
const BACKLOG_HORIZON_SECONDS := 10.0

enum SmartWindowRoles {
    ARTIFACT,
    CONSUMER,
    STORAGE,
    MANAGER,
}

var window: WindowBase
var inputs: Dictionary[String, ResourceContainer]
var role: SmartWindowRoles = SmartWindowRoles.ARTIFACT
var process_component: Node

var provided: Array = []
# _has_modern_speed() result, refreshed by set_containers()/update().
var _modern_speed := false
var dependent: Array = []
var container_data: Dictionary[String, SmartContainerData]

# Read-only compatibility alias used by Adaptive Auto Connector's validator.
# It intentionally exposes the live ResourceContainer objects that correspond
# to this manager's own supplied inputs without giving AAC mutation authority.
var own_sources: Array:
    get:
        var result: Array = []
        for name in provided:
            if inputs.has(name):
                result.append(inputs[name])
        return result


func _init(target_window: WindowBase) -> void:
    window = target_window
    process_component = window.get_node_or_null("Process")

    set_containers()


func set_containers(sources: Array = []) -> void:
    inputs.clear()
    for container: ResourceContainer in window.containers:
        if is_instance_valid(container) and container.is_in_group("input"):
            inputs[container.id] = container
    provided = inputs.keys().filter(sources.has)
    dependent = inputs.keys().filter(
        func(name):
            return (
                not provided.has(name)
                and _is_material(inputs[name])
                and _is_process_material(inputs[name])
            )
    )

    for name in container_data.keys():
        if not dependent.has(name):
            container_data.erase(name)

    for name in dependent:
        if not container_data.has(name):
            container_data[name] = SmartContainerData.new(inputs[name])

    _modern_speed = _has_modern_speed()
    if "demand" in window:
        role = SmartWindowRoles.MANAGER
    elif not dependent.is_empty() and (window.has_method("get_goal") or _modern_speed):
        role = SmartWindowRoles.CONSUMER
    elif window.is_in_group("window"):
        role = SmartWindowRoles.STORAGE
    else:
        role = SmartWindowRoles.ARTIFACT


func _is_modern_process() -> bool:
    return (
        not window.has_method("get_goal")
        and is_instance_valid(process_component)
        and "goal_obj" in process_component
        and "speed_obj" in process_component
        and "resources" in process_component
        and "should_consume" in process_component
    )


func _has_modern_speed() -> bool:
    if not _is_modern_process():
        return false
    var speed = process_component.speed_obj
    return (
        is_instance_valid(process_component.goal_obj)
        and is_instance_valid(speed)
        and "resource" in speed
        and "rate" in speed
        and is_instance_valid(speed.resource)
        and provided.has(speed.resource.id)
        and (not "inf_speed" in speed or not speed.inf_speed)
    )


func _is_process_material(container: ResourceContainer) -> bool:
    if not _is_modern_process():
        return true
    # 3.0 keeps consumed resources on Process, not every material-looking
    # container elsewhere in a window (which can include unrelated buffers).
    return (
        bool(process_component.should_consume)
        and process_component.resources.has(container)
        and float(container.required) > 0.0
    )


func get_demand() -> float:
    if provided.is_empty():
        return 0.0

    if role == SmartWindowRoles.MANAGER:
        return _manager_demand()

    return get_min_production_ratio() * get_goal()


func get_count_demand() -> float:
    if provided.is_empty():
        return 0.0

    if role == SmartWindowRoles.MANAGER:
        return _manager_demand()

    return get_min_count_ratio() * get_goal()


# Inflow-based demand plus the work needed to drain the current buffer within
# BACKLOG_HORIZON_SECONDS. Never lower than get_demand().
func get_auto_demand(horizon: float = BACKLOG_HORIZON_SECONDS) -> float:
    if provided.is_empty():
        return 0.0

    if role == SmartWindowRoles.MANAGER:
        return _manager_demand()

    var goal := get_goal()
    if goal <= 0.0 or dependent.is_empty():
        return 0.0

    var safe_horizon := horizon if is_finite(horizon) and horizon > 0.0 else BACKLOG_HORIZON_SECONDS
    var ratio := INF
    for name in dependent:
        ratio = minf(ratio, container_data[name].get_backlog_ratio(safe_horizon))
    var demand := ratio * goal
    return demand if is_finite(demand) and demand > 0.0 else 0.0


func get_provided_resource() -> String:
    for name in provided:
        if inputs.has(name) and "resource" in inputs[name]:
            return str(inputs[name].resource)
    return ""


func _manager_demand() -> float:
    # A Better Resource Hub manages two independent resources; ask it for the
    # one this manager actually supplies instead of a mixed total.
    var value := 0.0
    if window.has_method("get_resource_demand"):
        value = float(window.get_resource_demand(get_provided_resource()))
    else:
        value = float(window.demand)
    return value if is_finite(value) and value > 0.0 else 0.0


func set_count(value: float) -> void:
    var size := provided.size()

    # Defensive fix for transient topology updates.
    if size <= 0:
        return

    var split_value := value / float(size)
    for container in provided.map(
        func(name): return inputs[name]
    ):
        container.count = split_value


func get_min_production_ratio() -> float:
    if dependent.is_empty():
        return 0.0

    if dependent.size() == 1:
        return container_data[dependent[0]].get_production_ratio()

    return dependent.map(
        func(name): return container_data[name].get_production_ratio()
    ).reduce(minf)


func get_min_count_ratio() -> float:
    if dependent.is_empty():
        return 0.0

    if dependent.size() == 1:
        return container_data[dependent[0]].get_count_ratio()

    return dependent.map(
        func(name): return container_data[name].get_count_ratio()
    ).reduce(minf)


func get_goal() -> float:
    if role != SmartWindowRoles.CONSUMER or window.paused:
        return 0.0
    if window.has_method("get_goal"):
        return float(window.get_goal())
    if (
        _modern_speed
        and is_instance_valid(process_component)
        and is_instance_valid(process_component.speed_obj)
        and is_instance_valid(process_component.goal_obj)
    ):
        var rate := float(process_component.speed_obj.rate)
        if rate <= 0.0 or not is_finite(rate):
            return 0.0
        # Process.progress advances by supplied speed * rate. Convert the
        # work per operation back to units of the manager's CPU/GPU supply.
        var goal := float(process_component.goal_obj.value) / rate
        return goal if is_finite(goal) and goal > 0.0 else 0.0
    return 0.0


func update() -> void:
    # Required amounts, goal values and finite/uncapped roles can change
    # during play. The manager refreshes this before reading each demand.
    set_containers(provided.duplicate())
    for data in container_data.values():
        data.update()


func _is_material(container: ResourceContainer) -> bool:
    return (
        container.type == Utils.resource_types.MATERIAL
        or container.type == Utils.resource_types.MATERIAL_LIMITED
    )


class SmartContainerData extends RefCounted:
    var container: ResourceContainer
    var multiplier: float = 0.0

    func _init(target: ResourceContainer) -> void:
        container = target
        multiplier = _get_multiplier()

    func get_production_ratio() -> float:
        return multiplier * float(container.production)

    func get_count_ratio() -> float:
        return multiplier * float(container.count)

    func get_backlog_ratio(horizon: float) -> float:
        var inflow := maxf(float(container.production), 0.0)
        var stock := maxf(float(container.count), 0.0)
        var ratio := multiplier * (inflow + stock / horizon)
        return ratio if is_finite(ratio) else 0.0

    func _get_multiplier() -> float:
        var divisor := (
            float(container.required)
            if not is_zero_approx(float(container.required))
            else 1.0
        )
        return 1.0 / divisor

    func update() -> void:
        multiplier = _get_multiplier()
