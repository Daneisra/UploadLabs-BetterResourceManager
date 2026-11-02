extends ResourceContainer

# Output port of a Better Resource Hub. The hub computes every target's share
# from one pool spanning all outputs of a resource, so the vanilla
# per-container transfer must not run on top of it (same approach as
# smart_resource_container.gd).

signal brm_topology_changed


func tick() -> void:
    # Preserve vanilla loop protection: a looping target receives nothing.
    for item: ResourceContainer in looping:
        if is_instance_valid(item):
            item.count = 0


func update_connections() -> void:
    super()
    brm_topology_changed.emit()
