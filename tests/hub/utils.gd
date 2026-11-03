extends Node
enum resource_types { MATERIAL, FLOW, BOOST, MATERIAL_LIMITED, SETTING, HEAT, FLUID, UNIT }


func print_string(value: float, _short: bool = true) -> String:
    return String.num_scientific(snappedf(value, 0.001)) if absf(value) >= 1e6 else str(snappedf(value, 0.001))
