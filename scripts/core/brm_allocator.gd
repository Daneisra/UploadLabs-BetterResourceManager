extends RefCounted

# Pure allocation engine for Better Resource Hub and the legacy managers'
# Auto mode. It only reads plain dictionaries, so the isolated tests exercise
# exactly the code the game runs.
#
# A request is a Dictionary:
#   key: String       stable identity, used for deterministic ordering
#   demand: float     finite demand estimate (>= 0)
#   uncapped: bool    also accepts any amount beyond its demand (sellers,
#                     miners...). A demand of INF is read as uncapped.
#   weight: float     relative share (default 1.0)
#   priority: int     higher is served first / favoured (default 0)
#   max: float        hard ceiling (INF = none)
#   min: float        desired floor, served before demand when possible
#   enabled: bool     disabled targets always receive 0
#
# Every policy guarantees: allocations >= 0 and sum(allocations) <= supply.
# Results only depend on the inputs (requests are ordered by priority, then
# key), so identical inputs always give identical allocations.

enum Policy {
    AUTO = 0,
    DEMAND = 1,
    RATIO = 2,
    PRIORITY = 3,
}

# Soft-priority base used by Auto: one priority step doubles a target's share
# while resources are short, without ever starving lower priorities entirely.
const AUTO_PRIORITY_BASE := 2.0
const PRIORITY_MIN := -10
const PRIORITY_MAX := 10
const WEIGHT_MAX := 1000000.0


static func allocate(supply: float, raw_requests: Array, policy: int) -> Dictionary:
    var invalid := 0
    var budget := supply
    if not is_finite(budget) or budget < 0.0:
        if is_nan(budget) or is_inf(budget):
            invalid += 1
        budget = 0.0

    var given: Dictionary = {}
    var requests: Array = []
    for raw in raw_requests:
        var clean := sanitize_request(raw)
        invalid += int(clean._invalid)
        requests.append(clean)
        given[clean.key] = 0.0
    requests.sort_custom(_compare_requests)

    var finite_demand := 0.0
    var uncapped := 0
    for request in requests:
        if not request.enabled:
            continue
        finite_demand += minf(request.demand, request.max)
        if request.uncapped:
            uncapped += 1

    var start := budget
    match policy:
        Policy.DEMAND:
            _policy_demand(budget, requests, given)
        Policy.RATIO:
            _policy_ratio(budget, requests, given, finite_demand)
        Policy.PRIORITY:
            _policy_priority(budget, requests, given)
        _:
            _policy_auto(budget, requests, given)

    var allocated := _enforce_conservation(given, start)
    return {
        "allocations": given,
        "allocated": allocated,
        "unused": maxf(start - allocated, 0.0),
        "supply": start,
        "finite_demand": finite_demand,
        "uncapped_count": uncapped,
        "shortage": finite_demand > 0.0 and finite_demand > start * (1.0 + 1e-9),
        "invalid_values": invalid,
    }


static func sanitize_request(raw) -> Dictionary:
    var source: Dictionary = raw if raw is Dictionary else {}
    var invalid := 0

    var uncapped := bool(source.get("uncapped", false))
    var demand := float(source.get("demand", 0.0))
    if is_nan(demand):
        invalid += 1
        demand = 0.0
    elif is_inf(demand):
        if demand > 0.0:
            uncapped = true
        demand = 0.0
    demand = maxf(demand, 0.0)

    var weight := float(source.get("weight", 1.0))
    if not is_finite(weight):
        invalid += 1
        weight = 1.0
    weight = clampf(weight, 0.0, WEIGHT_MAX)

    var maximum := float(source.get("max", INF))
    if is_nan(maximum):
        invalid += 1
        maximum = INF
    maximum = maxf(maximum, 0.0)

    var minimum := float(source.get("min", 0.0))
    if not is_finite(minimum):
        invalid += 1
        minimum = 0.0
    minimum = clampf(minimum, 0.0, maximum)

    return {
        "key": str(source.get("key", "")),
        "demand": demand,
        "uncapped": uncapped,
        "weight": weight,
        "priority": clampi(int(source.get("priority", 0)), PRIORITY_MIN, PRIORITY_MAX),
        "max": maximum,
        "min": minimum,
        "enabled": bool(source.get("enabled", true)),
        "_invalid": invalid,
    }


# Weighted max-min fair fill ("water filling"): each item receives
# budget * weight / total_weight unless that exceeds its remaining cap, in which
# case it is capped and the rest is shared again. Sorting by cap/weight turns
# this into a single O(n log n) sweep. Returns the unused budget.
static func water_fill(budget: float, items: Array, given: Dictionary) -> float:
    if budget <= 0.0:
        return 0.0

    var active: Array = []
    for item in items:
        var cap := float(item.cap)
        var weight := float(item.weight)
        if cap <= 0.0 or weight <= 0.0:
            continue
        active.append({"key": item.key, "cap": cap, "weight": weight, "ratio": cap / weight})

    if active.is_empty():
        return budget

    active.sort_custom(func(a, b):
        if a.ratio == b.ratio:
            return a.key < b.key
        return a.ratio < b.ratio
    )

    # Remaining weight from suffix sums, never by subtraction: removing a huge
    # weight from a running total can cancel a tiny one to 0.0 and leave the
    # rest of the budget undistributed.
    var suffix: Array[float] = []
    suffix.resize(active.size() + 1)
    suffix[active.size()] = 0.0
    for back in range(active.size() - 1, -1, -1):
        suffix[back] = suffix[back + 1] + float(active[back].weight)

    var remaining := budget
    var index := 0
    while index < active.size() and remaining > 0.0:
        var item: Dictionary = active[index]
        var total_weight: float = suffix[index]
        if total_weight <= 0.0:
            break
        var level := remaining / total_weight
        if level >= float(item.ratio):
            given[item.key] = float(given.get(item.key, 0.0)) + float(item.cap)
            remaining -= float(item.cap)
            index += 1
            continue

        # Nobody else saturates: share what is left by weight and stop.
        for tail_index in range(index, active.size()):
            var tail: Dictionary = active[tail_index]
            given[tail.key] = float(given.get(tail.key, 0.0)) + level * float(tail.weight)
        remaining = 0.0

    return maxf(remaining, 0.0)


static func _policy_auto(budget: float, requests: Array, given: Dictionary) -> void:
    budget = _fill_minimums(budget, requests, given)

    # Finite demand is shared across ALL priorities with a soft priority
    # multiplier, so a shortage never starves a consumer entirely.
    var items: Array = []
    for request in requests:
        if request.enabled:
            items.append(_item(request, minf(request.demand, request.max) - given[request.key], _auto_weight(request)))
    budget = water_fill(budget, items, given)

    budget = _fill_uncapped(budget, requests, given, true)

    # Real surplus goes back to finite consumers in proportion to their demand.
    # An underestimated demand (hidden backlog, conversion we cannot read)
    # therefore never leaves usable CPU/GPU idle.
    _fill_surplus(budget, requests, given, true)


static func _policy_priority(budget: float, requests: Array, given: Dictionary) -> void:
    # Strict tiers: a lower priority only receives what higher tiers left.
    budget = _fill_minimums(budget, requests, given)
    var tiers := _tiers(requests)
    for tier in tiers:
        var items: Array = []
        for request in tier:
            if request.enabled:
                items.append(_item(request, minf(request.demand, request.max) - given[request.key], request.weight))
        budget = water_fill(budget, items, given)
    for tier in tiers:
        budget = _fill_uncapped(budget, tier, given, false)
    _fill_surplus(budget, requests, given, false)


static func _policy_demand(budget: float, requests: Array, given: Dictionary) -> void:
    # Smallest demand first, equal split of the unsatisfied tail: the
    # unweighted max-min fair fill, i.e. test23's Demand shortage behaviour.
    var items: Array = []
    for request in requests:
        if request.enabled:
            items.append(_item(request, minf(request.demand, request.max), 1.0))
    budget = water_fill(budget, items, given)
    budget = _fill_uncapped_equal(budget, requests, given)
    _fill_surplus(budget, requests, given, false, true)


static func _policy_ratio(budget: float, requests: Array, given: Dictionary, finite_demand: float) -> void:
    # Original Ratio: every finite target receives demand * min(1, supply /
    # demand); only uncapped targets receive the leftovers.
    var ratio := 0.0
    if finite_demand > 0.0:
        ratio = clampf(budget / finite_demand, 0.0, 1.0)
    for request in requests:
        if request.enabled:
            var amount := minf(minf(request.demand, request.max) * ratio, budget)
            given[request.key] = float(given[request.key]) + amount
            budget -= amount
    _fill_uncapped_equal(maxf(budget, 0.0), requests, given)


static func _fill_minimums(budget: float, requests: Array, given: Dictionary) -> float:
    for tier in _tiers(requests):
        var floors: Array = []
        for request in tier:
            if request.enabled:
                floors.append(_item(request, request.min - given[request.key], request.weight))
        budget = water_fill(budget, floors, given)
    return budget


static func _fill_uncapped(budget: float, requests: Array, given: Dictionary, soft_priority: bool) -> float:
    var items: Array = []
    for request in requests:
        if request.enabled and request.uncapped:
            var weight: float = _auto_weight(request) if soft_priority else request.weight
            items.append(_item(request, request.max - given[request.key], weight))
    return water_fill(budget, items, given)


static func _fill_uncapped_equal(budget: float, requests: Array, given: Dictionary) -> float:
    var items: Array = []
    for request in requests:
        if request.enabled and request.uncapped:
            items.append(_item(request, request.max - given[request.key], 1.0))
    return water_fill(budget, items, given)


static func _fill_surplus(budget: float, requests: Array, given: Dictionary, soft_priority: bool, ignore_weight: bool = false) -> float:
    if budget <= 0.0:
        return 0.0
    var items: Array = []
    var weighted_total := 0.0
    for request in requests:
        if not request.enabled or (request.uncapped and request.demand <= 0.0):
            continue
        var base := 1.0
        if not ignore_weight:
            base = _auto_weight(request) if soft_priority else request.weight
        var weight: float = base * request.demand
        weighted_total += weight
        items.append({"key": request.key, "cap": request.max - given[request.key], "weight": weight, "base": base})

    if weighted_total <= 0.0:
        # No demand signal at all: split evenly (test23 Demand rule) while
        # still honouring every ceiling.
        for item in items:
            item.weight = item.base
    return water_fill(budget, items, given)


static func _enforce_conservation(given: Dictionary, supply: float) -> float:
    var total := 0.0
    for key in given.keys():
        var value := float(given[key])
        if not is_finite(value) or value < 0.0:
            value = 0.0
        given[key] = value
        total += value

    if total > supply and total > 0.0:
        # Floating-point rounding only: scale down so the sum never exceeds the
        # real supply. Never invent CPU/GPU.
        var factor := (supply / total) * (1.0 - 1e-12)
        total = 0.0
        for key in given.keys():
            given[key] = float(given[key]) * factor
            total += float(given[key])
    return total


static func _auto_weight(request: Dictionary) -> float:
    return float(request.weight) * pow(AUTO_PRIORITY_BASE, float(request.priority))


static func _item(request: Dictionary, cap: float, weight: float) -> Dictionary:
    return {"key": request.key, "cap": maxf(cap, 0.0), "weight": weight}


static func _tiers(sorted_requests: Array) -> Array:
    var tiers: Array = []
    var current: Array = []
    var has_priority := false
    var current_priority := 0
    for request in sorted_requests:
        if not has_priority or int(request.priority) != current_priority:
            if not current.is_empty():
                tiers.append(current)
            current = []
            current_priority = int(request.priority)
            has_priority = true
        current.append(request)
    if not current.is_empty():
        tiers.append(current)
    return tiers


static func _compare_requests(a: Dictionary, b: Dictionary) -> bool:
    if int(a.priority) != int(b.priority):
        return int(a.priority) > int(b.priority)
    return str(a.key) < str(b.key)
