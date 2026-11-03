extends WindowIndexed

const LegacyAliases = preload("res://mods-unpacked/Daneisra-BetterResourceManager/scripts/global/legacy_scene_aliases.gd")
# Option id of BRM's Auto mode. It is saved separately (brm_auto_mode) and
# container_mode keeps a Ratio/Demand/Graph value, so the original mods can
# still read a save written by BRM.
const AUTO_MODE_ID := 3

@onready var input = $PanelContainer/MainContainer/Input
@onready var output = $PanelContainer/MainContainer/Output
@onready var progress_bar = $PanelContainer/MainContainer/Progress/ProgressBar
@onready var demand_label = $PanelContainer/MainContainer/Progress/ProgressContainer/DemandsLabel
@onready var percent_label = $PanelContainer/MainContainer/Progress/ProgressContainer/PercentLabel
@onready var mode_button = $OptionButton
@onready var use_count_button = $PanelContainer/MainContainer/UseCountButton

var _container_mode: int = 1

@export_enum("Ratio", "Demand", "Graph")
var container_mode: int = 1:
    get:
        return _container_mode
    set(value):
        _container_mode = clampi(int(value), 0, 2)
        if is_node_ready():
            _apply_container_mode()


var _brm_auto: bool = false

@export var brm_auto_mode: bool = false:
    get:
        return _brm_auto
    set(value):
        _brm_auto = bool(value)
        if is_node_ready():
            _apply_container_mode()


var _use_count: bool = false

@export var use_count: bool = false:
    get:
        return _use_count
    set(value):
        _use_count = bool(value)
        if is_node_ready():
            _apply_use_count()


var demand:
    get:
        if is_instance_valid(output):
            return float(output.demand)
        return 0.0


func _ready() -> void:
    super()
    _apply_compatibility_metadata()
    _apply_container_mode()
    _apply_use_count()


func _apply_compatibility_metadata() -> void:
    # Some optional UI/window scanners inspect category metadata directly on
    # live controls instead of reading Data.windows. Mirror the canonical
    # registry values defensively without changing manager behavior.
    var window_data = Data.windows.get(window, {})
    if not window_data is Dictionary:
        return

    var category := str(window_data.get("category", ""))
    var sub_category := str(window_data.get("sub_category", ""))

    var nodes: Array[Node] = [self]
    nodes.append_array(find_children("*", "Node", true, false))

    var applied := 0
    for node in nodes:
        if not is_instance_valid(node):
            continue
        if not node.has_meta("category"):
            node.set_meta("category", category)
        if not node.has_meta("sub_category"):
            node.set_meta("sub_category", sub_category)
        if not node.has_meta("window_id"):
            node.set_meta("window_id", str(window))
        applied += 1

    print("[Daneisra-BetterResourceManager][Compatibility] Metadata window='%s' category='%s' sub_category='%s' nodes=%d" % [
        str(window),
        category,
        sub_category,
        applied
    ])


func tick(_delta: float) -> void:
    # A disconnected input may keep its last value; it delivers nothing any
    # more, so it must not be redistributed (same rule as the hub).
    if "input_id" in input and str(input.input_id).is_empty() and float(input.count) != 0.0:
        input.count = 0.0
    output.count = input.count

    var current_demand := float(demand)
    var uncapped_targets := 0
    var uncapped_starved := 0
    if "uncapped_target_count" in output:
        uncapped_targets = int(output.uncapped_target_count)
    if "uncapped_starved_count" in output:
        uncapped_starved = int(output.uncapped_starved_count)

    var progress_value := (
        float(input.count) / current_demand
        if not is_zero_approx(current_demand)
        else 0.0
    )

    progress_bar.value = lerpf(
        progress_bar.min_value,
        progress_bar.max_value,
        progress_value
    )

    # The manager input row already shows live supply. Use the progress row to
    # report demand explicitly. Speed-only miners/schedulers have no finite
    # material-derived demand cap in the original algorithm; they are handled
    # as fallback targets. Do not mislabel that state as simply "0 demand".
    var comparison := _get_common_comparison_display(
        current_demand,
        float(input.count)
    )
    var need_text := str(comparison.get(
        "need",
        Utils.print_string(current_demand)
    ))
    var supply_text := str(comparison.get(
        "supply",
        Utils.print_string(float(input.count))
    ))

    if uncapped_targets > 0:
        demand_label.text = "Need: "
        if not is_zero_approx(current_demand):
            demand_label.text += (
                need_text
                + output.suffix
                + " + ∞ ×"
                + str(uncapped_targets)
            )
        else:
            demand_label.text += (
                "∞ ×"
                + str(uncapped_targets)
            )

        # Keep the GPU manager's Demand presentation consistent with the
        # Thread manager: show the translated Supply value in the same common
        # promoted unit instead of replacing the right-hand side with only an
        # "uncapped" count. The ×N next to infinity preserves the uncapped
        # target count without forcing players to compare mixed suffixes.
        if _shows_full_supply():
            percent_label.text = (
                "Supply: "
                + supply_text
                + output.suffix
            )
            if float(input.count) > 0.0:
                percent_label.text += " · 100% used"
            if uncapped_starved > 0:
                percent_label.text += (
                    " · "
                    + str(uncapped_starved)
                    + " starved"
                )
        else:
            percent_label.text = "%d uncapped" % uncapped_targets
            if uncapped_starved > 0:
                percent_label.text += " · %d starved" % uncapped_starved
    else:
        demand_label.text = (
            "Need: "
            + need_text
            + output.suffix
        )
        if _shows_full_supply() and float(input.count) > 0.0:
            percent_label.text = (
                "Supply: "
                + supply_text
                + output.suffix
                + " · 100% used"
            )
        else:
            percent_label.text = (
                Utils.print_string(
                    100.0 * progress_value,
                    false
                )
                + "%"
            )


func _get_common_comparison_display(
    need_value: float,
    supply_value: float
) -> Dictionary:
    # Pick one natural Upload Labs magnitude from the larger of Need/Supply,
    # then express both values in that same magnitude. This avoids both of the
    # confusing failure modes we already tested:
    #
    #   1) unrelated prefixes side by side (RHz vs aeHz), and
    #   2) endlessly growing a smaller unit (799.7RHz instead of promotion).
    #
    # Utils.print_string() owns the game's compact magnitude progression; ASM
    # only derives the numeric scale from its returned text. No suffix ladder
    # or promotion threshold is hard-coded here.
    var reference_value := maxf(
        absf(need_value),
        absf(supply_value)
    )

    if is_zero_approx(reference_value):
        return {
            "need": "0",
            "supply": "0"
        }

    var natural_text := str(
        Utils.print_string(reference_value)
    ).strip_edges()
    var parsed := _parse_compact_value(natural_text)

    if parsed.is_empty():
        return {
            "need": Utils.print_string(need_value),
            "supply": Utils.print_string(supply_value)
        }

    var shown_reference := float(
        parsed.get("number", 0.0)
    )
    var magnitude_prefix := str(
        parsed.get("prefix", "")
    )

    if is_zero_approx(shown_reference):
        return {
            "need": Utils.print_string(need_value),
            "supply": Utils.print_string(supply_value)
        }

    var scale := reference_value / absf(shown_reference)
    if is_zero_approx(scale):
        return {
            "need": Utils.print_string(need_value),
            "supply": Utils.print_string(supply_value)
        }

    return {
        "need": (
            _format_same_unit_number(need_value / scale)
            + magnitude_prefix
        ),
        "supply": (
            _format_same_unit_number(supply_value / scale)
            + magnitude_prefix
        )
    }


func _parse_compact_value(text_value: String) -> Dictionary:
    var value_text := text_value.strip_edges()
    if value_text.is_empty():
        return {}

    var split_index := 0
    while split_index < value_text.length():
        var ch := value_text.substr(split_index, 1)
        var is_digit := ch >= "0" and ch <= "9"

        if (
            is_digit
            or ch == "."
            or ch == ","
            or ch == "-"
            or ch == "+"
        ):
            split_index += 1
            continue

        break

    if split_index <= 0:
        return {}

    var number_text := value_text.substr(
        0,
        split_index
    ).replace(",", "")

    if (
        number_text == ""
        or number_text == "-"
        or number_text == "+"
        or number_text == "."
        or number_text == "-."
        or number_text == "+."
    ):
        return {}

    return {
        "number": number_text.to_float(),
        "prefix": value_text.substr(
            split_index
        ).strip_edges()
    }


func _format_same_unit_number(value: float) -> String:
    var magnitude := absf(value)
    var decimals := 2

    if magnitude >= 100.0:
        decimals = 1
    elif magnitude >= 1.0:
        decimals = 2
    elif magnitude >= 0.1:
        decimals = 3
    elif magnitude >= 0.01:
        decimals = 4
    elif magnitude >= 0.001:
        decimals = 5
    else:
        decimals = 8

    var result := ("%.*f" % [decimals, value])

    while result.contains(".") and result.ends_with("0"):
        result = result.substr(
            0,
            result.length() - 1
        )

    if result.ends_with("."):
        result = result.substr(
            0,
            result.length() - 1
        )

    return result


func _on_input_resource_set() -> void:
    # Preserve original behavior: manager output follows the forced input
    # resource. Thread stays clock_speed; GPU stays gpu_speed.
    output.set_resource(input.resource)


func _shows_full_supply() -> bool:
    return _container_mode == 1 or _brm_auto


func _scene_filename() -> String:
    # Keep the path this window was loaded from. A manager placed with kuuk's
    # mods keeps its kuuk path (resolved by legacy_scene_aliases.gd), so the
    # save can still be opened with the original mods.
    if not scene_file_path.is_empty():
        return LegacyAliases.to_save_filename(scene_file_path)
    return Data.windows[window].scene + ".tscn"


func export() -> Dictionary:
    var dict: Dictionary = super()
    dict["filename"] = _scene_filename()
    dict["container_mode"] = _container_mode
    dict["use_count"] = _use_count
    dict["brm_auto_mode"] = _brm_auto
    return dict


func save() -> Dictionary:
    var dict: Dictionary = super()
    dict["filename"] = _scene_filename()
    dict["container_mode"] = _container_mode
    dict["use_count"] = _use_count
    dict["brm_auto_mode"] = _brm_auto
    return dict


func _on_option_button_item_selected(index: int) -> void:
    var previous_mode := _container_mode
    var selected_id := int(mode_button.get_item_id(index))
    var selected_mode := clampi(selected_id, 0, 2)
    if selected_id == AUTO_MODE_ID:
        _brm_auto = true
    else:
        _brm_auto = false
        _container_mode = selected_mode
    _apply_container_mode()
    if is_instance_valid(output) and output.has_method("request_distribution_validation"):
        output.call("request_distribution_validation", "mode_change")

    var output_mode := -1
    if is_instance_valid(output) and "distribution_mode" in output:
        output_mode = int(output.get("distribution_mode"))

    print("[Daneisra-BetterResourceManager][Window] Mode changed window='%s' previous=%d selected=%d current=%d auto=%s output=%d label='%s'" % [
        str(name),
        previous_mode,
        selected_id,
        _container_mode,
        str(_brm_auto),
        output_mode,
        str(mode_button.get_item_text(index))
    ])


func _on_use_count_button_toggled(toggled_on: bool) -> void:
    _use_count = toggled_on
    _apply_use_count()
    if is_instance_valid(output) and output.has_method("request_distribution_validation"):
        output.call("request_distribution_validation", "base_change")

    var output_use_count := false
    if is_instance_valid(output) and "use_count" in output:
        output_use_count = bool(output.get("use_count"))

    print("[Daneisra-BetterResourceManager][Window] Base changed window='%s' requested=%s current=%s output=%s label='%s'" % [
        str(name),
        str(toggled_on),
        str(_use_count),
        str(output_use_count),
        str(use_count_button.text)
    ])


func _apply_container_mode() -> void:
    if is_instance_valid(output) and "distribution_mode" in output:
        output.set("distribution_mode", AUTO_MODE_ID if _brm_auto else _container_mode)
    _sync_mode_button()


func _apply_use_count() -> void:
    if is_instance_valid(output) and "use_count" in output:
        output.set("use_count", _use_count)
    _sync_use_count_button()


func _sync_mode_button() -> void:
    if not is_instance_valid(mode_button):
        return

    var item_index: int = int(mode_button.get_item_index(AUTO_MODE_ID if _brm_auto else _container_mode))
    if item_index >= 0 and mode_button.selected != item_index:
        mode_button.select(item_index)


func _sync_use_count_button() -> void:
    if not is_instance_valid(use_count_button):
        return

    use_count_button.button_pressed = _use_count
    use_count_button.text = (
        tr("stm_count_text")
        if _use_count
        else tr("stm_cps_text")
    )


func get_aac_manager_info() -> Dictionary:
    return {
        "provider": "Daneisra-BetterResourceManager",
        "window_id": str(window),
        "window_name": str(name),
        "resource": str(output.resource),
        "count": float(output.count),
        "demand": float(output.demand),
        "finite_demand": float(output.finite_demand) if "finite_demand" in output else float(output.demand),
        "uncapped_target_count": int(output.uncapped_target_count) if "uncapped_target_count" in output else 0,
        "uncapped_starved_count": int(output.uncapped_starved_count) if "uncapped_starved_count" in output else 0,
        "uncapped_allocated_total": float(output.uncapped_allocated_total) if "uncapped_allocated_total" in output else 0.0,
        "bound_window_count": int(output.bound_window_count) if "bound_window_count" in output else 0,
        "distribution_mode": AUTO_MODE_ID if _brm_auto else _container_mode,
        "use_count": _use_count,
        "read_only": true
    }
