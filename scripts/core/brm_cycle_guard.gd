extends RefCounted

# Cycle detection for CPU/GPU flow. A target that can send the same resource
# back into the hub (directly or through managers) would make the hub count
# its own output as new supply. The hub computes, once per topology change,
# every window that is upstream of it for one resource; a target inside that
# set is part of a loop and receives nothing.
#
# The walk is iterative with a visited set and a node budget, so a looping or
# huge graph can never recurse or spin forever.

const DEFAULT_NODE_BUDGET := 4096


# upstream: Callable(name: String) -> Array of upstream window names.
static func upstream_closure(start: String, upstream: Callable, node_budget: int = DEFAULT_NODE_BUDGET) -> Dictionary:
    var visited: Dictionary = {}
    var queue: Array = [start]
    var head := 0
    var truncated := false

    while head < queue.size():
        var current: String = queue[head]
        head += 1
        var neighbours = upstream.call(current)
        if not neighbours is Array:
            continue
        for raw_name in neighbours:
            var name := str(raw_name)
            if name.is_empty() or visited.has(name):
                continue
            if visited.size() >= node_budget:
                truncated = true
                break
            visited[name] = true
            queue.append(name)
        if truncated:
            break

    return {"names": visited, "truncated": truncated, "visited": visited.size()}


static func from_adjacency(adjacency: Dictionary) -> Callable:
    return func(name: String) -> Array:
        return adjacency.get(name, [])
