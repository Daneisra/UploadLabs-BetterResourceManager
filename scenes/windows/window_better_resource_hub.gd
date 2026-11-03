extends WindowIndexed

# Better Resource Hub: one node that pools CPU (clock_speed) and GPU
# (gpu_speed) from any number of input ports and distributes each pool to any
# number of output ports. Ports are real native input/output containers created
# from the saved layout.
#
# Save contract (do not rename without a migration):
#   brm_layout     port list + uid counters (scripts/core/brm_port_layout.gd)
#   brm_port_state container id / outputs_id per port uid (fallback restore)
#   brm_mode, brm_compact, brm_format
#   port container path: PanelContainer/MainContainer/<Cpu|Gpu>/<Inputs|Outputs>/<uid>/Port
#
# Upload Labs assigns saved properties before _ready ("set on load"), so the
# brm_layout setter builds the port nodes immediately; container_data restored
# by the game afterwards finds every port at its saved path.

const PortLayout = preload("res://mods-unpacked/Daneisra-BetterResourceManager/scripts/core/brm_port_layout.gd")
const Diagnostics = preload("res://mods-unpacked/Daneisra-BetterResourceManager/scripts/core/brm_diagnostics.gd")
const Channel = preload("res://mods-unpacked/Daneisra-BetterResourceManager/scripts/hub/brm_resource_channel.gd")
const UI = preload("res://mods-unpacked/Daneisra-BetterResourceManager/scripts/hub/brm_hub_ui.gd")
const SmartWindowGraph = preload("res://mods-unpacked/Daneisra-BetterResourceManager/scripts/global/smart_window_graph.gd")
const Probe = preload("res://mods-unpacked/Daneisra-BetterResourceManager/scripts/global/brm_runtime_probe.gd")
const LegacyAliases = preload("res://mods-unpacked/Daneisra-BetterResourceManager/scripts/global/legacy_scene_aliases.gd")
const INPUT_PORT_SCENE := preload("res://mods-unpacked/Daneisra-BetterResourceManager/scenes/ports/brm_input_port.tscn")
const OUTPUT_PORT_SCENE := preload("res://mods-unpacked/Daneisra-BetterResourceManager/scenes/ports/brm_output_port.tscn")

const MAIN_PATH := "PanelContainer/MainContainer"
const SECTION_NODES := {"clock_speed": "Cpu", "gpu_speed": "Gpu"}
const SAVE_FORMAT := 1
const UI_REFRESH_TICKS := 6
const LOG_PREFIX := "[Daneisra-BetterResourceManager][Hub]"
const MODE_ITEMS := ["brm_mode_auto", "brm_mode_demand", "brm_mode_ratio", "brm_mode_priority", "brm_mode_graph"]

@onready var mode_button = $OptionButton

var brm_layout: Dictionary:
    get:
        return PortLayout.to_save(_layout)
    set(value):
        _restore_layout(value)

var brm_port_state: Dictionary:
    get:
        return _port_state()
    set(value):
        _pending_port_state = value.duplicate(true) if value is Dictionary else {}
        _apply_port_state()

var brm_mode: int:
    get:
        return _mode
    set(value):
        _mode = clampi(int(value), Channel.Mode.AUTO, Channel.Mode.GRAPH)
        if is_node_ready():
            _apply_mode()

var brm_compact: bool:
    get:
        return _compact
    set(value):
        _compact = bool(value)
        if is_node_ready():
            _apply_compact()

var brm_format: int:
    get:
        return SAVE_FORMAT
    set(_value):
        pass

# Fallback for readers that only know the legacy managers' single "demand".
var demand: float:
    get:
        return get_resource_demand(PortLayout.CPU_RESOURCE) + get_resource_demand(PortLayout.GPU_RESOURCE)

var _layout: Dictionary = {}
var _layout_ready := false
var _mode: int = Channel.Mode.AUTO
var _compact := false
var _ports: Dictionary = {}
var _channels: Dictionary = {}
var _pending_port_state: Dictionary = {}
var _graph = null
var _ui_counter := 0
var _post_ready_done := false
var _unregistered: Dictionary = {}
var _open_settings: Dictionary = {}
var _relayout_pending := false
# Ports the game did not collect itself and that had to be appended to
# containers (tests expect 0 for hubs created normally).
var late_appended_ports := 0
# Ports created after the window was set up. The game only feeds ports that
# existed from the start, so these stay inactive until the save is reloaded.
var _live_ports: Dictionary = {}
# Loading a save replays connection_created for every restored wire; the
# free-input helper only reacts to wires made after the hub has run a while,
# so a port the player removed is not brought back on every load.
const AUTO_INPUT_ARM_TICKS := 30
var _ticks_alive := 0


func _ensure_ports() -> void:
    if not _layout_ready:
        _layout = PortLayout.default_layout()
        _layout_ready = true
    if not is_node_ready():
        PortLayout.top_up_spares(_layout)
    _ensure_sections()
    _sync_port_nodes()


func _ready() -> void:
    _ensure_ports()

    super()

    for resource in SECTION_NODES.keys():
        _channels[resource] = Channel.new(resource, self)
    _refresh_channel_ports()

    _setup_mode_button()
    _apply_mode()
    _apply_compact()
    _connect_runtime_signals()
    call_deferred("_post_ready")


func _post_ready() -> void:
    _post_ready_done = true
    _verify_ports()
    var sample_input = null
    var sample_output = null
    for entry in _ports.values():
        if PortLayout.is_input(entry.kind) and sample_input == null:
            sample_input = entry.container
        elif PortLayout.is_output(entry.kind) and sample_output == null:
            sample_output = entry.container
    Probe.run_once(self, sample_input, sample_output)
    _refresh_ui()
    _relayout()


func tick(_delta: float) -> void:
    if _ticks_alive < AUTO_INPUT_ARM_TICKS:
        _ticks_alive += 1
    for channel in _channels.values():
        channel.tick(_mode)
    _diagnose_silent_inputs()

    _ui_counter += 1
    if _ui_counter >= UI_REFRESH_TICKS:
        _ui_counter = 0
        _refresh_ui()


# Wired inputs that stay at 0: log what the game shows about their source,
# at most INPUT_REPORT_LIMIT times per session (read-only diagnosis).
static var _input_reports := 0
const INPUT_REPORT_LIMIT := 3
const INPUT_REPORT_TICKS := 120
var _silent_ticks := 0


func _diagnose_silent_inputs() -> void:
    if _input_reports >= INPUT_REPORT_LIMIT:
        return
    var silent := false
    for channel in _channels.values():
        if channel.count_silent_inputs() > 0:
            silent = true
    _silent_ticks = _silent_ticks + 1 if silent else 0
    if _silent_ticks < INPUT_REPORT_TICKS:
        return
    _silent_ticks = 0
    _input_reports += 1
    for resource in _channels.keys():
        for line in _channels[resource].describe_inputs():
            print("%s Silent input window='%s' resource=%s %s" % [LOG_PREFIX, name, resource, line])
        for line in _channels[resource].describe_input_differences():
            print("%s Input diff window='%s' resource=%s %s" % [LOG_PREFIX, name, resource, line])
    var live: Array = _live_ports.keys()
    print("%s Input report window='%s' live_ports=%s" % [LOG_PREFIX, name, ",".join(live)])


func get_resource_demand(resource: String) -> float:
    var channel = _channels.get(resource)
    return channel.get_finite_demand() if channel != null else 0.0


# Read by upstream managers (SmartWindowData.is_uncapped_manager).
func get_resource_uncapped(resource: String) -> bool:
    var channel = _channels.get(resource)
    return channel != null and channel.has_uncapped_targets()


func get_channel(resource: String):
    return _channels.get(resource)


# --- Layout and port nodes -------------------------------------------------

func _restore_layout(value) -> void:
    var parsed := PortLayout.from_save(value)
    if not parsed.valid:
        push_warning("%s Saved layout of '%s' is unreadable; keeping the current ports." % [LOG_PREFIX, name])
        return
    if int(parsed.report.dropped) > 0 or int(parsed.report.duplicates) > 0:
        push_warning("%s Saved layout of '%s': %d invalid and %d duplicate port(s) ignored." % [
            LOG_PREFIX, name, int(parsed.report.dropped), int(parsed.report.duplicates)
        ])
    _layout = parsed.layout
    _layout_ready = true
    if not is_node_ready():
        # Saved before spares existed, or spares used since: top them up while
        # new ports can still be set up with the window.
        PortLayout.top_up_spares(_layout)
    _ensure_sections()
    _sync_port_nodes()
    if is_node_ready():
        _refresh_channel_ports()


func add_port(kind: int) -> String:
    var uid := ""
    if is_node_ready():
        uid = PortLayout.reveal_spare(_layout, kind)
    var revealed := not uid.is_empty()
    if not revealed:
        uid = PortLayout.add_port(_layout, kind)
    if uid.is_empty():
        return ""
    if revealed:
        _apply_spare_visibility(uid)
    elif is_node_ready():
        _live_ports[uid] = true
    _sync_port_nodes()
    _refresh_channel_ports()
    _refresh_ui()
    _relayout()
    print("%s Port added window='%s' uid='%s'" % [LOG_PREFIX, name, uid])
    return uid


func remove_port(uid: String) -> bool:
    var entry = _ports.get(uid)
    if entry == null:
        return false
    if _is_port_connected(entry.container):
        return false
    if _live_ports.has(uid):
        _live_ports.erase(uid)
        PortLayout.remove_port(_layout, uid)
    else:
        # A port set up with the window is kept as a hidden spare: it works
        # again at once if a port of that kind is added later.
        PortLayout.set_spare(_layout, uid, true)
        _apply_spare_visibility(uid)
    _sync_port_nodes()
    _refresh_channel_ports()
    _refresh_ui()
    _relayout()
    print("%s Port removed window='%s' uid='%s'" % [LOG_PREFIX, name, uid])
    return true


func _sync_port_nodes() -> void:
    var wanted: Dictionary = {}
    for port in _layout.get("ports", []):
        wanted[str(port.uid)] = port

    for uid in _ports.keys():
        if not wanted.has(uid):
            _destroy_port_node(uid)

    for port in _layout.get("ports", []):
        if not _ports.has(str(port.uid)):
            _create_port_node(port)

    _apply_port_state()


func _create_port_node(port: Dictionary) -> void:
    var kind := int(port.kind)
    var resource := PortLayout.resource_for(kind)
    var section := _section(resource)
    if section == null:
        return
    var is_input := PortLayout.is_input(kind)
    var list: Node = section.get_node("Inputs" if is_input else "Outputs")

    var row := VBoxContainer.new()
    row.name = str(port.uid)
    row.add_theme_constant_override("separation", 2)
    row.mouse_filter = Control.MOUSE_FILTER_IGNORE

    var container: Node = (INPUT_PORT_SCENE if is_input else OUTPUT_PORT_SCENE).instantiate()
    container.name = "Port"
    container.set("default_resource", resource)
    row.add_child(container)

    var line := HBoxContainer.new()
    line.name = "Line"
    line.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var uid := str(port.uid)
    var name_edit := UI.line_edit(str(port.get("label", "")), "", tr("brm_name_tooltip"), func(text: String): _on_label_committed(uid, text))
    name_edit.name = "Name"
    line.add_child(name_edit)
    var flow_label := UI.label("", UI.COLOR_MUTED, UI.FONT_SMALL)
    flow_label.name = "Flow"
    flow_label.autowrap_mode = TextServer.AUTOWRAP_OFF
    line.add_child(flow_label)

    var settings_box: Control = null
    if not is_input:
        var settings_button := UI.button("⚙", tr("brm_settings_tooltip"), func(): _toggle_settings(uid))
        settings_button.name = "SettingsButton"
        line.add_child(settings_button)
    var remove_button := UI.button("×", tr("brm_remove_port"), func(): remove_port(uid))
    remove_button.name = "RemoveButton"
    line.add_child(remove_button)
    row.add_child(line)

    if not is_input:
        settings_box = _build_settings(uid)
        settings_box.visible = _open_settings.has(uid)
        row.add_child(settings_box)

    list.add_child(row)
    row.visible = not PortLayout.is_spare(port)
    # Owned by the window like nodes of a regular window scene: the game finds
    # a window's containers with find_children(), which only returns owned
    # nodes (alpha.2 ports were reported "missing from window containers").
    row.owner = self
    container.owner = self
    _ports[uid] = {
        "uid": uid,
        "kind": kind,
        "resource": resource,
        "row": row,
        "container": container,
        "line": line,
        "name_edit": name_edit,
        "flow_label": flow_label,
        "remove_button": remove_button,
        "settings_box": settings_box,
    }

    if _post_ready_done:
        _adopt_runtime_container(container)


func _destroy_port_node(uid: String) -> void:
    var entry = _ports.get(uid)
    _ports.erase(uid)
    _open_settings.erase(uid)
    _unregistered.erase(uid)
    if entry == null:
        return
    var container = entry.container
    if is_instance_valid(container):
        if "containers" in self and containers.has(container):
            containers.erase(container)
        var resources = _desktop_resources()
        if resources is Dictionary and "id" in container and resources.get(container.id) == container:
            resources.erase(container.id)
    if is_instance_valid(entry.row):
        entry.row.get_parent().remove_child(entry.row)
        entry.row.queue_free()


# A port added while the hub is already on the desktop was not part of the
# window when the game collected its containers. Add it the same way, and
# report it if the desktop still does not know it (see _verify_ports).
func _adopt_runtime_container(container: Node) -> void:
    if "containers" in self and not containers.has(container):
        containers.append(container)
    if "id" in container and str(container.id).is_empty():
        container.id = _new_container_id()
    var resources = _desktop_resources()
    if resources is Dictionary and "id" in container and not resources.has(container.id):
        resources[container.id] = container
        print("%s Registered runtime port id='%s' window='%s'" % [LOG_PREFIX, str(container.id), name])
    _verify_ports()


func _verify_ports() -> void:
    _unregistered.clear()
    var resources = _desktop_resources()
    for uid in _ports.keys():
        var container = _ports[uid].container
        if not is_instance_valid(container):
            continue
        if "containers" in self and not containers.has(container):
            containers.append(container)
            late_appended_ports += 1
            print("%s Port '%s' was missing from window containers; added." % [LOG_PREFIX, uid])
        if resources is Dictionary and "id" in container and resources.get(container.id) != container:
            _unregistered[uid] = true
    if not _unregistered.is_empty():
        push_warning("%s %d port(s) of '%s' are not registered on the desktop: %s" % [
            LOG_PREFIX, _unregistered.size(), name, ",".join(_unregistered.keys())
        ])


func _apply_spare_visibility(uid: String) -> void:
    var entry = _ports.get(uid)
    if entry != null and is_instance_valid(entry.row):
        entry.row.visible = not PortLayout.is_spare(PortLayout.get_port(_layout, uid))


func _refresh_channel_ports() -> void:
    for resource in _channels.keys():
        var inputs: Array = []
        var outputs: Array = []
        for port in _layout.get("ports", []):
            var kind := int(port.kind)
            if PortLayout.resource_for(kind) != resource or not _ports.has(str(port.uid)) or PortLayout.is_spare(port):
                continue
            var entry: Dictionary = _ports[str(port.uid)]
            if PortLayout.is_input(kind):
                inputs.append({"uid": entry.uid, "container": entry.container})
            else:
                outputs.append({"uid": entry.uid, "container": entry.container, "settings": port.get("settings", PortLayout.default_settings())})
                var container = entry.container
                if container.has_signal("brm_topology_changed") and not container.brm_topology_changed.is_connected(_on_topology_changed):
                    container.brm_topology_changed.connect(_on_topology_changed)
        _channels[resource].set_ports(inputs, outputs)
        _channels[resource].graph = _graph


func _port_state() -> Dictionary:
    var state: Dictionary = {}
    for uid in _ports.keys():
        var container = _ports[uid].container
        if not is_instance_valid(container) or not "id" in container:
            continue
        var outputs_id: Array = []
        if "outputs_id" in container:
            outputs_id = Array(container.outputs_id)
        state[uid] = {"id": str(container.id), "outputs_id": outputs_id}
    return state


func _apply_port_state() -> void:
    if _pending_port_state.is_empty() or ("importing" in self and importing):
        return
    for uid in _pending_port_state.keys():
        if not _ports.has(uid):
            continue
        var saved = _pending_port_state[uid]
        var container = _ports[uid].container
        if saved is Dictionary and is_instance_valid(container):
            var saved_id := str(saved.get("id", ""))
            if "id" in container and not saved_id.is_empty():
                container.id = saved_id
            if "outputs_id" in container and saved.get("outputs_id") is Array:
                var typed: Array[String] = []
                for value in saved.outputs_id:
                    typed.append(str(value))
                container.outputs_id = typed
        _pending_port_state.erase(uid)


# --- Save ---------------------------------------------------------------------

func _scene_filename() -> String:
    # Keep the path this window was loaded from (legacy-compatible), like
    # the smart managers do.
    if not scene_file_path.is_empty():
        return LegacyAliases.to_save_filename(scene_file_path)
    return Data.windows[window].scene + ".tscn"


func export() -> Dictionary:
    var dict: Dictionary = super()
    dict["filename"] = _scene_filename()
    dict["brm_format"] = SAVE_FORMAT
    dict["brm_layout"] = PortLayout.to_save(_layout)
    dict["brm_mode"] = _mode
    dict["brm_compact"] = _compact
    # No brm_port_state: a pasted copy must get fresh container ids.
    dict.erase("brm_port_state")
    return dict


func save() -> Dictionary:
    var dict: Dictionary = super()
    dict["filename"] = _scene_filename()
    dict["brm_format"] = SAVE_FORMAT
    dict["brm_layout"] = PortLayout.to_save(_layout)
    dict["brm_mode"] = _mode
    dict["brm_compact"] = _compact
    dict["brm_port_state"] = _port_state()
    return dict


# --- UI ---------------------------------------------------------------------

func _ensure_sections() -> void:
    var main := get_node_or_null(MAIN_PATH)
    if main == null:
        return
    if main.get_node_or_null("Toolbar") == null:
        var toolbar := HBoxContainer.new()
        toolbar.name = "Toolbar"
        toolbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
        var compact_button := UI.button(tr("brm_compact"), tr("brm_compact_tooltip"), _on_compact_toggled, true)
        compact_button.name = "CompactButton"
        compact_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        toolbar.add_child(compact_button)
        main.add_child(toolbar)
        toolbar.owner = self

    for resource in SECTION_NODES.keys():
        if main.get_node_or_null(SECTION_NODES[resource]) != null:
            continue
        var section := _build_section(resource)
        main.add_child(section)
        section.owner = self
        for child in section.get_children():
            child.owner = self


func _build_section(resource: String) -> Control:
    var is_cpu := resource == PortLayout.CPU_RESOURCE
    var color := UI.COLOR_CPU if is_cpu else UI.COLOR_GPU
    var section := VBoxContainer.new()
    section.name = SECTION_NODES[resource]
    section.mouse_filter = Control.MOUSE_FILTER_IGNORE
    section.add_theme_constant_override("separation", 4)

    section.add_child(UI.separator(color))
    var header := HBoxContainer.new()
    header.name = "Header"
    header.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var title := UI.label(tr("brm_section_cpu" if is_cpu else "brm_section_gpu"), color, UI.FONT_TITLE)
    title.name = "Title"
    title.autowrap_mode = TextServer.AUTOWRAP_OFF
    header.add_child(title)
    var summary := UI.label("", UI.COLOR_TEXT, UI.FONT_SMALL)
    summary.name = "Summary"
    summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    header.add_child(summary)
    section.add_child(header)

    var inputs := VBoxContainer.new()
    inputs.name = "Inputs"
    inputs.mouse_filter = Control.MOUSE_FILTER_IGNORE
    section.add_child(inputs)
    var input_kind := PortLayout.Kind.CPU_INPUT if is_cpu else PortLayout.Kind.GPU_INPUT
    var add_input := UI.button(tr("brm_add_cpu_input" if is_cpu else "brm_add_gpu_input"), tr("brm_add_input_tooltip"), func(): add_port(input_kind))
    add_input.name = "AddInput"
    section.add_child(add_input)

    var outputs := VBoxContainer.new()
    outputs.name = "Outputs"
    outputs.mouse_filter = Control.MOUSE_FILTER_IGNORE
    section.add_child(outputs)
    var output_kind := PortLayout.Kind.CPU_OUTPUT if is_cpu else PortLayout.Kind.GPU_OUTPUT
    var add_output := UI.button(tr("brm_add_cpu_output" if is_cpu else "brm_add_gpu_output"), tr("brm_add_output_tooltip"), func(): add_port(output_kind))
    add_output.name = "AddOutput"
    section.add_child(add_output)

    var status := UI.label("", UI.COLOR_MUTED, UI.FONT_SMALL)
    status.name = "Status"
    status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    section.add_child(status)
    return section


func _build_settings(uid: String) -> Control:
    var box := VBoxContainer.new()
    box.name = "Settings"
    box.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var settings: Dictionary = PortLayout.get_port(_layout, uid).get("settings", PortLayout.default_settings())

    var first := HBoxContainer.new()
    first.mouse_filter = Control.MOUSE_FILTER_IGNORE
    first.add_child(UI.label(tr("brm_priority"), UI.COLOR_MUTED, UI.FONT_SMALL))
    first.add_child(UI.button("−", tr("brm_priority_tooltip"), func(): _step_setting(uid, "priority", -1)))
    var priority_label := UI.label(str(settings.priority), UI.COLOR_TEXT, UI.FONT_SMALL)
    priority_label.name = "PriorityValue"
    priority_label.autowrap_mode = TextServer.AUTOWRAP_OFF
    first.add_child(priority_label)
    first.add_child(UI.button("+", tr("brm_priority_tooltip"), func(): _step_setting(uid, "priority", 1)))
    first.add_child(UI.label(tr("brm_weight"), UI.COLOR_MUTED, UI.FONT_SMALL))
    var weight_edit := UI.line_edit(_number_text(float(settings.weight)), "1", tr("brm_weight_tooltip"), func(text: String): _commit_number(uid, "weight", text))
    weight_edit.name = "Weight"
    first.add_child(weight_edit)
    box.add_child(first)

    var second := HBoxContainer.new()
    second.mouse_filter = Control.MOUSE_FILTER_IGNORE
    second.add_child(UI.label(tr("brm_min"), UI.COLOR_MUTED, UI.FONT_SMALL))
    var min_edit := UI.line_edit(_limit_text(float(settings.min), true), "0", tr("brm_min_tooltip"), func(text: String): _commit_number(uid, "min", text))
    min_edit.name = "Min"
    second.add_child(min_edit)
    second.add_child(UI.label(tr("brm_max"), UI.COLOR_MUTED, UI.FONT_SMALL))
    var max_edit := UI.line_edit(_limit_text(float(settings.max), false), "∞", tr("brm_max_tooltip"), func(text: String): _commit_number(uid, "max", text))
    max_edit.name = "Max"
    second.add_child(max_edit)
    box.add_child(second)

    var third := HBoxContainer.new()
    third.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var enabled_button := UI.button("", tr("brm_enabled_tooltip"), func(): _flip_setting(uid, "enabled"))
    enabled_button.name = "Enabled"
    enabled_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    third.add_child(enabled_button)
    var manual_button := UI.button("", tr("brm_manual_tooltip"), func(): _flip_setting(uid, "manual"))
    manual_button.name = "Manual"
    manual_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    third.add_child(manual_button)
    box.add_child(third)
    _sync_settings_box(uid, box)
    return box


func _sync_settings_box(uid: String, box: Control = null) -> void:
    if box == null:
        var entry = _ports.get(uid)
        if entry == null or entry.settings_box == null:
            return
        box = entry.settings_box
    var settings: Dictionary = PortLayout.get_port(_layout, uid).get("settings", PortLayout.default_settings())
    var priority_label = box.find_child("PriorityValue", true, false)
    if priority_label != null:
        priority_label.text = ("+%d" % settings.priority) if int(settings.priority) > 0 else str(settings.priority)
    var enabled_button = box.find_child("Enabled", true, false)
    if enabled_button != null:
        enabled_button.text = tr("brm_enabled_on") if settings.enabled else tr("brm_enabled_off")
        enabled_button.add_theme_color_override("font_color", UI.COLOR_OK if settings.enabled else UI.COLOR_ERROR)
    var manual_button = box.find_child("Manual", true, false)
    if manual_button != null:
        manual_button.text = tr("brm_manual_manual") if settings.manual else tr("brm_manual_auto")
    for field in ["Weight", "Min", "Max"]:
        var edit = box.find_child(field, true, false)
        if edit == null or edit.has_focus():
            continue
        match field:
            "Weight":
                edit.text = _number_text(float(settings.weight))
            "Min":
                edit.text = _limit_text(float(settings.min), true)
            "Max":
                edit.text = _limit_text(float(settings.max), false)


func _setup_mode_button() -> void:
    if not is_instance_valid(mode_button):
        return
    mode_button.clear()
    for index in range(MODE_ITEMS.size()):
        mode_button.add_item(tr(MODE_ITEMS[index]), index)
    mode_button.tooltip_text = tr("brm_mode_tooltip")
    if not mode_button.item_selected.is_connected(_on_mode_selected):
        mode_button.item_selected.connect(_on_mode_selected)


func _apply_mode() -> void:
    if _mode == Channel.Mode.GRAPH and _graph == null:
        _graph = SmartWindowGraph.new(self)
        _graph.request_filter_depth(self, 0)
        _graph.changed.connect(_on_topology_changed)
    elif _mode != Channel.Mode.GRAPH and _graph != null:
        _dispose_graph()
    for channel in _channels.values():
        channel.graph = _graph
        channel.mark_dirty()
    if is_instance_valid(mode_button):
        var index: int = mode_button.get_item_index(_mode)
        if index >= 0 and mode_button.selected != index:
            mode_button.select(index)


func _apply_compact() -> void:
    var main := get_node_or_null(MAIN_PATH)
    if main == null:
        return
    var compact_button = main.get_node_or_null("Toolbar/CompactButton")
    if compact_button != null:
        compact_button.set_pressed_no_signal(_compact)
        compact_button.text = tr("brm_compact_on") if _compact else tr("brm_compact")
    for entry in _ports.values():
        if is_instance_valid(entry.line):
            entry.line.visible = not _compact
        if entry.settings_box != null and is_instance_valid(entry.settings_box):
            entry.settings_box.visible = not _compact and _open_settings.has(entry.uid)
    for resource in SECTION_NODES.keys():
        var section := _section(resource)
        if section == null:
            continue
        section.get_node("AddInput").visible = not _compact
        section.get_node("AddOutput").visible = not _compact
    # Update what compact mode hides in the summary/status first, so the
    # resize below measures the final content.
    if not _channels.is_empty():
        _refresh_ui()
    _relayout()


func _refresh_ui() -> void:
    for resource in _channels.keys():
        var channel = _channels[resource]
        var section := _section(resource)
        if section == null:
            continue
        var stats: Dictionary = channel.stats.duplicate()
        var unregistered := 0
        for uid in _unregistered.keys():
            if _ports.has(uid) and _ports[uid].resource == resource:
                unregistered += 1
        stats["unregistered_ports"] = unregistered
        var pending := 0
        for uid in _live_ports.keys():
            if _ports.has(uid) and _ports[uid].resource == resource:
                pending += 1
        stats["pending_reload_ports"] = pending

        var summary: Label = section.get_node("Header/Summary")
        var text := _fmt("brm_summary", [
            UI.format_value(float(stats.supply)),
            UI.format_value(float(stats.allocated)),
            UI.format_value(float(stats.unused)),
        ])
        if not _compact:
            text += "\n" + _fmt("brm_summary_demand", [UI.format_value(float(stats.finite_demand))])
            if int(stats.uncapped) > 0:
                text += " + ∞ ×%d" % int(stats.uncapped)
        summary.text = text

        var codes := Diagnostics.evaluate(stats)
        var status: Label = section.get_node("Status")
        var messages: Array[String] = []
        for entry in codes:
            messages.append(_diagnostic_text(entry))
        status.text = " · ".join(messages) if not messages.is_empty() else tr("brm_diag_ok")
        var severity := Diagnostics.worst_severity(codes)
        var color := UI.COLOR_OK
        if severity == Diagnostics.Severity.ERROR:
            color = UI.COLOR_ERROR
        elif severity == Diagnostics.Severity.WARNING:
            color = UI.COLOR_WARNING
        elif severity == Diagnostics.Severity.INFO:
            color = UI.COLOR_MUTED
        status.add_theme_color_override("font_color", color)
        status.visible = not _compact or severity >= Diagnostics.Severity.WARNING

    _refresh_port_rows()


func _refresh_port_rows() -> void:
    var counters: Dictionary = {}
    for port in _layout.get("ports", []):
        var uid := str(port.uid)
        if not _ports.has(uid) or PortLayout.is_spare(port):
            continue
        var entry: Dictionary = _ports[uid]
        var kind := int(port.kind)
        counters[kind] = int(counters.get(kind, 0)) + 1
        var channel = _channels.get(entry.resource)

        var placeholder := _fmt("brm_input_n" if PortLayout.is_input(kind) else "brm_output_n", [int(counters[kind])])
        if PortLayout.is_output(kind) and channel != null:
            var target_title := _first_target_title(channel, uid)
            if not target_title.is_empty():
                placeholder = target_title
        entry.name_edit.placeholder_text = placeholder

        var connected := _is_port_connected(entry.container)
        entry.remove_button.disabled = connected
        entry.remove_button.tooltip_text = tr("brm_remove_connected") if connected else tr("brm_remove_port")

        if _live_ports.has(uid):
            entry.flow_label.text = tr("brm_port_after_reload")
            entry.flow_label.tooltip_text = tr("brm_port_after_reload_tooltip")
            entry.flow_label.mouse_filter = Control.MOUSE_FILTER_PASS
            entry.flow_label.add_theme_color_override("font_color", UI.COLOR_WARNING)
            continue
        if channel == null:
            continue
        var flow := float(channel.port_flows.get(uid, 0.0))
        if PortLayout.is_output(kind):
            var port_demand := float(channel.port_demands.get(uid, 0.0))
            entry.flow_label.text = "%s / %s" % [UI.format_value(flow), UI.format_value(port_demand)]
            var settings: Dictionary = port.get("settings", {})
            entry.flow_label.add_theme_color_override("font_color", UI.COLOR_ERROR if not bool(settings.get("enabled", true)) else (UI.COLOR_DEMAND if flow + 1e-9 < port_demand * 0.999 else UI.COLOR_MUTED))
        else:
            entry.flow_label.text = UI.format_value(flow)
        if entry.settings_box != null and entry.settings_box.visible:
            _sync_settings_box(uid)


func _first_target_title(channel, uid: String) -> String:
    for name in channel.get_targets().keys():
        if channel._window_port.get(name, "") != uid:
            continue
        var target = channel.get_targets()[name].window
        if not is_instance_valid(target):
            continue
        if target.has_method("get_window_name"):
            var title := str(target.get_window_name())
            if not title.is_empty():
                return title
        if "window" in target and Data.windows.has(target.window):
            return tr(str(Data.windows[target.window].get("name", target.name)))
        return str(target.name)
    return ""


func _diagnostic_text(entry: Dictionary) -> String:
    var code := str(entry.code)
    var value = entry.get("value", 0)
    match code:
        Diagnostics.SHORTAGE, Diagnostics.UNUSED:
            return _fmt("brm_diag_" + code, [UI.format_value(float(value))])
        Diagnostics.CYCLE, Diagnostics.PORT_UNREGISTERED, Diagnostics.MANY_PORTS, Diagnostics.PENDING_RELOAD:
            return _fmt("brm_diag_" + code, [int(value)])
        _:
            return tr("brm_diag_" + code)


# The window root is a VBoxContainer: it grows with its content but never
# shrinks by itself. Wait until minimum sizes have propagated (two frames),
# then ask for the smallest height (Control clamps to the minimum size) and
# let the desktop redraw this window's connection lines.
func _relayout() -> void:
    if _relayout_pending or not is_inside_tree():
        return
    _relayout_pending = true
    # Keep the tree: get_tree() is null if the window leaves it meanwhile, and
    # the lock must be released on every path or later resizes stop.
    var tree := get_tree()
    await tree.process_frame
    if not is_inside_tree():
        _relayout_pending = false
        return
    await tree.process_frame
    _relayout_pending = false
    if not is_inside_tree():
        return
    size = Vector2(size.x, 0.0)
    if Signals.has_signal("window_moved"):
        Signals.emit_signal("window_moved", self)


# --- Event handlers ---------------------------------------------------------

func _on_mode_selected(index: int) -> void:
    var previous := _mode
    _mode = clampi(int(mode_button.get_item_id(index)), Channel.Mode.AUTO, Channel.Mode.GRAPH)
    _apply_mode()
    print("%s Mode changed window='%s' previous=%d current=%d" % [LOG_PREFIX, name, previous, _mode])


func _on_compact_toggled() -> void:
    var main := get_node_or_null(MAIN_PATH)
    var compact_button = main.get_node_or_null("Toolbar/CompactButton") if main != null else null
    _compact = compact_button.button_pressed if compact_button != null else not _compact
    _apply_compact()


func _toggle_settings(uid: String) -> void:
    if _open_settings.has(uid):
        _open_settings.erase(uid)
    else:
        _open_settings[uid] = true
    var entry = _ports.get(uid)
    if entry != null and entry.settings_box != null:
        entry.settings_box.visible = _open_settings.has(uid) and not _compact
        _sync_settings_box(uid)
    _relayout()


func _on_label_committed(uid: String, text: String) -> void:
    PortLayout.set_label(_layout, uid, text)


func _step_setting(uid: String, setting: String, step: int) -> void:
    var settings: Dictionary = PortLayout.get_port(_layout, uid).get("settings", PortLayout.default_settings())
    PortLayout.set_setting(_layout, uid, setting, int(settings.get(setting, 0)) + step)
    _settings_changed(uid)


func _flip_setting(uid: String, setting: String) -> void:
    var settings: Dictionary = PortLayout.get_port(_layout, uid).get("settings", PortLayout.default_settings())
    PortLayout.set_setting(_layout, uid, setting, not bool(settings.get(setting, false)))
    _settings_changed(uid)


func _commit_number(uid: String, setting: String, text: String) -> void:
    var value := UI.parse_value(text)
    if is_nan(value):
        _sync_settings_box(uid)
        return
    if setting == "weight" and value < 0.0:
        value = 1.0
    if setting == "min" and value < 0.0:
        value = 0.0
    PortLayout.set_setting(_layout, uid, setting, value)
    _settings_changed(uid)


func _settings_changed(uid: String) -> void:
    _refresh_channel_ports()
    _sync_settings_box(uid)


func _on_topology_changed() -> void:
    for channel in _channels.values():
        channel.mark_dirty()


func _on_connection_changed(_output_id = "", input_id = "") -> void:
    _on_topology_changed()
    if _ticks_alive < AUTO_INPUT_ARM_TICKS:
        return
    # An input takes a single wire. When the last free input of a resource
    # gets connected, offer a new free one right away.
    for entry in _ports.values():
        if PortLayout.is_input(entry.kind) and is_instance_valid(entry.container) and str(entry.container.id) == str(input_id):
            call_deferred("_keep_free_input", int(entry.kind))
            return


func _keep_free_input(kind: int) -> void:
    if not is_inside_tree():
        return
    for port in PortLayout.visible_ports_of(_layout, kind):
        var entry = _ports.get(str(port.uid))
        if entry != null and not _is_port_connected(entry.container):
            return
    add_port(kind)


func _on_window_deleted(_window = null) -> void:
    _on_topology_changed()


func _connect_runtime_signals() -> void:
    for signal_name in ["connection_created", "connection_deleted"]:
        if Signals.has_signal(signal_name) and not Signals.is_connected(signal_name, _on_connection_changed):
            Signals.connect(signal_name, _on_connection_changed)
    if Signals.has_signal("window_deleted") and not Signals.is_connected("window_deleted", _on_window_deleted):
        Signals.connect("window_deleted", _on_window_deleted)


func _disconnect_runtime_signals() -> void:
    for signal_name in ["connection_created", "connection_deleted"]:
        if Signals.has_signal(signal_name) and Signals.is_connected(signal_name, _on_connection_changed):
            Signals.disconnect(signal_name, _on_connection_changed)
    if Signals.has_signal("window_deleted") and Signals.is_connected("window_deleted", _on_window_deleted):
        Signals.disconnect("window_deleted", _on_window_deleted)


func _dispose_graph() -> void:
    if _graph == null:
        return
    if _graph.changed.is_connected(_on_topology_changed):
        _graph.changed.disconnect(_on_topology_changed)
    _graph.release_filter_depth(self, 0)
    _graph.dispose()
    _graph = null


# Notifications instead of _enter_tree/_exit_tree overrides: an override
# replaces WindowBase's own implementation, and the game sets the window up
# there (observed in alpha.1/alpha.2: transparent background, connection lines
# not following the window, "canvas_item is null" errors).
func _notification(what: int) -> void:
    match what:
        NOTIFICATION_ENTER_TREE:
            if not is_node_ready():
                # A new hub (no saved layout) builds its default ports before
                # the game's own _ready collects the window's containers.
                _ensure_ports()
                return
            _connect_runtime_signals()
            _apply_mode()
            _on_topology_changed()
        NOTIFICATION_EXIT_TREE:
            _dispose_graph()
            for channel in _channels.values():
                channel.graph = null
            _disconnect_runtime_signals()


# --- Helpers ------------------------------------------------------------------

func _section(resource: String) -> Control:
    return get_node_or_null(MAIN_PATH + "/" + str(SECTION_NODES.get(resource, ""))) as Control


func _is_port_connected(container) -> bool:
    if not is_instance_valid(container):
        return false
    if "input_id" in container and not str(container.input_id).is_empty():
        return true
    if "outputs_id" in container and not container.outputs_id.is_empty():
        return true
    if "outputs" in container and container.outputs is Array and not container.outputs.is_empty():
        return true
    return false


func _desktop_resources():
    if not has_node("/root/Globals"):
        return null
    var globals := get_node("/root/Globals")
    if not "desktop" in globals:
        return null
    var desktop = globals.get("desktop")
    if not is_instance_valid(desktop) or not "resources" in desktop:
        return null
    return desktop.get("resources")


func _new_container_id() -> String:
    var resources = _desktop_resources()
    var rng := RandomNumberGenerator.new()
    rng.randomize()
    while true:
        var id := "%012x" % (rng.randi() * 65536 + (rng.randi() & 0xFFFF))
        id = id.right(12)
        if not (resources is Dictionary and resources.has(id)):
            return id
    return ""


func _number_text(value: float) -> String:
    if is_equal_approx(value, roundf(value)) and absf(value) < 1e6:
        return str(int(roundf(value)))
    return str(snappedf(value, 0.001)) if absf(value) < 1e6 else String.num_scientific(value)


func _limit_text(value: float, zero_is_empty: bool) -> String:
    if value < 0.0 or (zero_is_empty and value <= 0.0):
        return ""
    # Show the game's compact notation when it reads back to the same value,
    # otherwise plain scientific notation (always accepted by parse_value).
    var compact := str(Utils.print_string(value))
    var parsed := UI.parse_value(compact)
    if not is_nan(parsed) and is_equal_approx(parsed, value):
        return compact
    return String.num_scientific(value)


# tr() % args, tolerant of a missing or placeholder-less translation.
func _fmt(key: String, args: Array) -> String:
    var template := tr(key)
    if template.count("%") < args.size():
        return template + " " + " ".join(args.map(func(item): return str(item)))
    return template % args
