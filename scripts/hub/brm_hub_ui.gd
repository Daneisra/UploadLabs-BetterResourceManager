extends RefCounted

# Small control factory and number helpers for the hub window. Colours follow
# the Upload Labs palette used by the smart manager scenes (dark blue panels,
# pale text, orange accent).

const ActionButtonScript = preload("res://mods-unpacked/Daneisra-BetterResourceManager/scripts/hub/brm_action_button.gd")

const COLOR_TEXT := Color(0.85098, 0.968627, 1.0)
const COLOR_MUTED := Color(0.568627, 0.694118, 0.901961)
const COLOR_CPU := Color(0.40, 0.75, 1.0)
const COLOR_GPU := Color(0.72, 0.55, 1.0)
const COLOR_DEMAND := Color(1.0, 0.521569, 0.0)
const COLOR_OK := Color(0.45, 0.85, 0.50)
const COLOR_WARNING := Color(1.0, 0.75, 0.30)
const COLOR_ERROR := Color(1.0, 0.38, 0.38)
const COLOR_PANEL := Color(0.0627451, 0.0705882, 0.0980392, 1.0)
const COLOR_BORDER := Color(0.270588, 0.333333, 0.458824, 1.0)

const FONT_SMALL := 16
const FONT_NORMAL := 18
const FONT_TITLE := 22

const SI_PREFIXES := {
    "k": 1e3, "K": 1e3, "M": 1e6, "G": 1e9, "T": 1e12, "P": 1e15,
    "E": 1e18, "Z": 1e21, "Y": 1e24, "R": 1e27, "Q": 1e30,
}


static func label(text: String, color: Color = COLOR_TEXT, size: int = FONT_NORMAL) -> Label:
    var node := Label.new()
    node.text = text
    node.mouse_filter = Control.MOUSE_FILTER_IGNORE
    node.add_theme_color_override("font_color", color)
    node.add_theme_font_size_override("font_size", size)
    node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    return node


static func button(text: String, tooltip: String, callback: Callable, toggle: bool = false) -> Button:
    var node: Button = ActionButtonScript.new()
    node.text = text
    node.tooltip_text = tooltip
    node.toggle_mode = toggle
    node.focus_mode = Control.FOCUS_NONE
    node.theme_type_variation = &"ItemButton"
    node.add_theme_font_size_override("font_size", FONT_NORMAL)
    node.custom_minimum_size = Vector2(36, 32)
    if toggle:
        node.toggled.connect(func(_on): callback.call())
    else:
        node.pressed.connect(callback)
    return node


static func line_edit(text: String, placeholder: String, tooltip: String, on_commit: Callable) -> LineEdit:
    var node := LineEdit.new()
    node.text = text
    node.placeholder_text = placeholder
    node.tooltip_text = tooltip
    node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    node.add_theme_font_size_override("font_size", FONT_SMALL)
    node.custom_minimum_size = Vector2(60, 30)
    node.select_all_on_focus = true
    node.text_submitted.connect(func(value: String):
        on_commit.call(value)
        node.release_focus()
    )
    node.focus_exited.connect(func(): on_commit.call(node.text))
    return node


static func separator(color: Color) -> HSeparator:
    var node := HSeparator.new()
    var style := StyleBoxLine.new()
    style.color = Color(color, 0.6)
    style.thickness = 2
    node.add_theme_stylebox_override("separator", style)
    node.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return node


static func format_value(value: float, suffix: String = "Hz") -> String:
    if is_nan(value):
        return "NaN"
    if is_inf(value):
        return "∞"
    return str(Utils.print_string(value)) + suffix


# Accepts "2.5e21", "2.5 Z", "2,5ZHz", "1500". Empty text means "no value".
# Returns NAN when the text is not a number.
static func parse_value(text: String) -> float:
    var value := text.strip_edges().replace(",", ".").replace(" ", "")
    if value.is_empty():
        return -1.0
    if value.ends_with("Hz") or value.ends_with("hz"):
        value = value.substr(0, value.length() - 2)
    var multiplier := 1.0
    if not value.is_empty() and SI_PREFIXES.has(value.right(1)):
        multiplier = float(SI_PREFIXES[value.right(1)])
        value = value.substr(0, value.length() - 1)
    if not value.is_valid_float():
        return NAN
    var number := value.to_float() * multiplier
    return number if is_finite(number) and number >= 0.0 else NAN
