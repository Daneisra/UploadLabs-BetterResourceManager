# Shared distribution algorithms derived from kuuk / Omisse Smart Manager 3.0.0.
# Player-facing Ratio / Demand / Graph behavior is intentionally preserved.

static func distribution_ratio(value: float, state: Dictionary) -> void:
    var wdata = state.wdata
    var demands = state.demands

    var remaining := value
    var total: float = demands.values().reduce(
        func(acc, flt): return acc + flt,
        0.0
    )
    var ratio := (
        clampf(remaining / total, 0.0, 1.0)
        if not is_zero_approx(total)
        else 0.0
    )

    for key in demands.keys():
        var amount: float = float(demands[key]) * ratio
        wdata[key].set_count(amount)
        remaining -= amount

    state.demand = total
    _set_storages(clampf(remaining, 0.0, INF), state)


static func distribution_demand(value: float, state: Dictionary) -> void:
    distribution_ratio(value, state)

    _state_average_demands(state)
    state.demand = _get_demand_sum(state.demands)

    if is_zero_approx(value):
        # Original bug: `return` lived inside this loop, which could leave
        # every target after the first one with a stale count.
        for wd in state.wdata.values():
            wd.set_count(0.0)
        return

    var remaining := _set_targets_demand(value, state)

    # Demand mode is demand-first, not demand-capped. After every finite
    # target has received its calculated demand, keep using the full incoming
    # supply. Existing uncapped/storage targets retain first claim on true
    # leftovers (matching the GPU-manager behavior). If there are no uncapped
    # targets, distribute the surplus back across finite targets using demand
    # as the weight. This guarantees total Demand-mode allocation tracks the
    # available supply instead of leaving usable Thread CPU idle.
    if remaining > 0.0 and state.storages.is_empty():
        remaining = _boost_finite_targets_with_surplus(remaining, state)

    _set_storages(remaining, state)


static func distribution_graph(value: float, state: Dictionary) -> void:
    _state_average_demands(state)
    state.demand = _get_demand_sum(state.demands)

    var remaining := value
    remaining = _set_targets_graph(remaining, state)
    _set_storages(remaining, state)


static func _set_targets_demand(value: float, state: Dictionary) -> float:
    var wdata = state.wdata
    var demands = state.demands
    var targets: Array = state.consumers + state.managers
    var remaining := value

    if is_zero_approx(value):
        for name in targets:
            wdata[name].set_count(0.0)
        return 0.0

    # Preserve Demand mode's small-demand-first behavior, but fix the
    # pathological shortage tail from the original 3.0.0 implementation.
    # The old code gave the first unsatisfied target 90% of the remaining
    # supply, then the next target 90% of the new remainder, producing an
    # exponential 10x allocation ladder (GHz -> MHz -> kHz -> Hz -> 0).
    # Once a sorted target cannot be fully satisfied, every remaining target
    # has demand >= that target, so the remaining supply can be split evenly
    # across the unsatisfied tail without exceeding any target's demand.
    targets.sort_custom(
        func(a, b): return demands[a] < demands[b]
    )

    var index := 0
    while index < targets.size():
        var name: StringName = targets[index]
        var target_demand := maxf(float(demands.get(name, 0.0)), 0.0)

        if is_zero_approx(target_demand):
            wdata[name].set_count(0.0)
            index += 1
            continue

        if target_demand < remaining:
            wdata[name].set_count(target_demand)
            remaining -= target_demand
            index += 1
            continue

        var unsatisfied_count := targets.size() - index
        if unsatisfied_count <= 0 or remaining <= 0.0:
            for tail_index in range(index, targets.size()):
                wdata[targets[tail_index]].set_count(0.0)
            remaining = 0.0
            break

        var fair_share := remaining / float(unsatisfied_count)
        for tail_index in range(index, targets.size()):
            var tail_name: StringName = targets[tail_index]
            wdata[tail_name].set_count(fair_share)

        remaining = 0.0
        break

    # Demand mode intentionally gives storage/uncapped targets only true
    # leftover supply after finite consumers are handled.
    return (
        0.0
        if value < float(state.demand)
        else clampf(remaining, 0.0, INF)
    )


static func _boost_finite_targets_with_surplus(
    surplus: float,
    state: Dictionary
) -> float:
    if surplus <= 0.0 or is_zero_approx(surplus):
        return 0.0

    var targets: Array = state.consumers + state.managers
    if targets.is_empty():
        return surplus

    var demands = state.demands
    var wdata = state.wdata
    var positive_demand_total := 0.0

    for name in targets:
        positive_demand_total += maxf(
            float(demands.get(name, 0.0)),
            0.0
        )

    if positive_demand_total > 0.0 and not is_zero_approx(positive_demand_total):
        for name in targets:
            var base_demand := maxf(
                float(demands.get(name, 0.0)),
                0.0
            )
            var bonus := surplus * base_demand / positive_demand_total
            wdata[name].set_count(base_demand + bonus)
    else:
        # If every calculated demand is currently zero, there is no useful
        # demand weight. Split the available supply evenly so Demand mode still
        # honors the full-utilization rule rather than silently dropping it.
        var share := surplus / float(targets.size())
        for name in targets:
            wdata[name].set_count(share)

    return 0.0


static func _set_targets_graph(remaining: float, state: Dictionary) -> float:
    var multi: float = float(state.get_or_add("multiplier", 1.0))

    var demands = state.demands
    var wdata = state.wdata
    var line_suppliers = state.get_or_add("line_suppliers", [])
    var line_receivers = state.get_or_add("line_receivers", [])

    if is_zero_approx(remaining):
        for name in state.get_or_add(
            "targets",
            state.consumers + state.managers
        ):
            wdata[name].set_count(0.0)
    else:
        var start_remaining := remaining

        for name in line_suppliers:
            var amount := minf(
                remaining,
                float(demands[name]) * multi
            )
            wdata[name].set_count(amount)
            remaining -= amount

        var receiver_demand: float = line_receivers.reduce(
            func(acc, n): return acc + demands[n],
            0.0
        )
        var is_zero_receiver := is_zero_approx(receiver_demand)
        var diff_ratio := (
            remaining / receiver_demand
            if not is_zero_receiver
            else 0.0
        )
        var rem_mult := clampf(diff_ratio, 0.0, 1.0)
        rem_mult = (
            1.0
            if is_equal_approx(rem_mult, 1.0)
            else rem_mult
        )

        var diff := remap(
            absf(1.0 - clampf(diff_ratio, 0.0, 2.0)),
            0.0,
            1.0,
            1e-14,
            1.0
        )

        if (diff_ratio >= 1.0 or is_zero_receiver) and multi < 1.0:
            multi = clampf(
                0.5 * (multi + multi * (1.0 + diff)),
                1e-14,
                1.0
            )
        elif diff_ratio < 1.0 and not is_zero_receiver:
            multi = clampf(
                0.5 * (multi + multi * (1.0 - diff)),
                1e-14,
                1.0
            )

        for name in line_receivers:
            var amount := minf(
                remaining,
                float(demands[name]) * rem_mult
            )
            wdata[name].set_count(amount)
            remaining -= amount

        if multi < 1.0:
            state.demand = start_remaining / multi
            remaining = 0.0

        remaining = clampf(remaining, 0.0, INF)

    state.multiplier = multi
    return remaining


static func _set_storages(remaining: float, state: Dictionary) -> void:
    var storages = state.storages
    var wdata = state.wdata
    var connections := int(state.storage_connections)

    # Defensive fix: a storage role can transiently exist while its provided
    # inputs are changing. Never divide by zero during that topology transition.
    if connections <= 0:
        for name in storages:
            wdata[name].set_count(0.0)
        return

    for name in storages:
        var data = wdata[name]
        data.set_count(
            remaining * float(data.provided.size()) / float(connections)
        )


static func _state_average_demands(state: Dictionary) -> void:
    const STEP := 0.5

    var old = state.get_or_add("old_demands", {})
    var current = state.get_or_add("demands", {})

    for key in current:
        current[key] = lerpf(
            float(old.get_or_add(key, 0.0)),
            float(current[key]),
            STEP
        )
        old[key] = current[key]


static func _get_demand_sum(demands: Dictionary) -> float:
    return demands.values().reduce(_sum_acc, 0.0)


static func _sum_acc(acc: float, val: float) -> float:
    return acc + val


# Auto (BRM): backlog-aware demand, smoothed, then the shared allocator. Finite
# consumers and chained managers are served first with max-min fairness,
# uncapped targets share the leftovers, and any real surplus returns to the
# finite consumers in proportion to their demand so usable supply is not left
# idle. state.auto_demands and state.allocator are filled by the container.
static func distribution_auto(value: float, state: Dictionary) -> void:
    var allocator = state.get("allocator")
    var tracker = state.get("tracker")
    var auto_demands: Dictionary = state.get("auto_demands", {})
    var requests: Array = []

    for name in state.consumers + state.managers:
        var raw := float(auto_demands.get(name, 0.0))
        requests.append({
            "key": str(name),
            "demand": tracker.smooth(str(name), raw) if tracker != null else raw,
        })
    for name in state.storages:
        requests.append({
            "key": str(name),
            "demand": 0.0,
            "uncapped": true,
            # Original storages share leftovers by number of wired inputs.
            "weight": float(maxi(state.wdata[name].provided.size(), 1)),
        })

    # 0 = BRMAllocator.Policy.AUTO (passed in through state, see container).
    var result: Dictionary = allocator.allocate(value, requests, 0)
    for name in state.wdata.keys():
        state.wdata[name].set_count(float(result.allocations.get(str(name), 0.0)))
    state.demand = float(result.finite_demand)
    state.auto_result = result
