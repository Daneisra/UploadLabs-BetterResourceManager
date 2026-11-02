extends RefCounted

# Read-only runtime observation of the game API the hub depends on. Upload
# Labs' scripts are not public; instead of guessing, the first hub of a session
# logs which of the expected members really exist. Nothing is called or
# modified here. Output is one block per session, prefixed [BRM][Probe].

const PREFIX := "[Daneisra-BetterResourceManager][Probe]"

const WINDOW_MEMBERS := ["containers", "window", "paused", "importing", "closing", "save", "export", "tick", "process"]
const CONTAINER_MEMBERS := [
    "id", "resource", "count", "production", "required", "type", "input", "input_id", "outputs",
    "outputs_id", "transfer", "looping", "connection_type", "default_resource", "force_resource",
    "limit", "suffix", "set_resource", "update_connections", "tick", "can_connect",
]
const SIGNAL_HINTS := ["connection", "window", "container", "resource", "desktop"]

static var _done := false


static func run_once(hub: Node, sample_input: Node, sample_output: Node) -> void:
    if _done or not is_instance_valid(hub):
        return
    _done = true

    var lines: Array[String] = []
    lines.append("window class=%s members=%s" % [hub.get_class(), _members(hub, WINDOW_MEMBERS)])
    if is_instance_valid(sample_input):
        lines.append("input port script=%s members=%s" % [_script_path(sample_input), _members(sample_input, CONTAINER_MEMBERS)])
        lines.append("input port children=%s" % _child_names(sample_input))
    if is_instance_valid(sample_output):
        lines.append("output port script=%s members=%s" % [_script_path(sample_output), _members(sample_output, CONTAINER_MEMBERS)])
        lines.append("output port children=%s" % _child_names(sample_output))

    var desktop = null
    var tree := hub.get_tree()
    if tree != null and tree.root.has_node("Globals"):
        var globals := tree.root.get_node("Globals")
        if "desktop" in globals:
            desktop = globals.get("desktop")
    lines.append("desktop=%s resources=%s" % [
        str(is_instance_valid(desktop)),
        (typeof(desktop.get("resources")) if is_instance_valid(desktop) and "resources" in desktop else -1)
    ])

    if tree != null and tree.root.has_node("Signals"):
        var signals := tree.root.get_node("Signals")
        var names: Array[String] = []
        for entry in signals.get_signal_list():
            var signal_name := str(entry.get("name", ""))
            for hint in SIGNAL_HINTS:
                if signal_name.contains(hint):
                    names.append(signal_name)
                    break
        names.sort()
        lines.append("signals=%s" % ",".join(names))

    for line in lines:
        print("%s %s" % [PREFIX, line])


static func _members(object: Object, expected: Array) -> String:
    var present: Array[String] = []
    var missing: Array[String] = []
    for member: String in expected:
        if member in object or object.has_method(member):
            present.append(member)
        else:
            missing.append(member)
    return "present[%s] missing[%s]" % [",".join(present), ",".join(missing)]


static func _script_path(node: Node) -> String:
    var script = node.get_script()
    return script.resource_path if script is Script else "none"


static func _child_names(node: Node) -> String:
    var names: Array[String] = []
    for child in node.get_children():
        names.append("%s:%s" % [child.name, child.get_class()])
    return ",".join(names)
