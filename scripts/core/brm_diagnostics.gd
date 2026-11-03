extends RefCounted

# Turns one resource channel's statistics into player-facing warnings. Pure:
# the hub only maps the returned codes to translated text and colours.

enum Severity { INFO = 0, WARNING = 1, ERROR = 2 }

const NO_INPUT := "no_input"
const ZERO_SUPPLY := "zero_supply"
const NO_OUTPUT := "no_output"
const NO_DEMAND := "no_demand"
const SHORTAGE := "shortage"
const UNUSED := "unused"
const CYCLE := "cycle"
const PORT_UNREGISTERED := "port_unregistered"
const INVALID_VALUES := "invalid_values"
const GRAPH_TRUNCATED := "graph_truncated"
const MANY_PORTS := "many_ports"
const PENDING_RELOAD := "pending_reload"
const PORTS_BLOCKED := "ports_blocked"
const BACKLOG := "backlog"

# Unused supply below this share of the supply is rounding, not a warning.
const UNUSED_WARNING_SHARE := 0.001


static func evaluate(stats: Dictionary) -> Array:
    var codes: Array = []
    var supply := float(stats.get("supply", 0.0))
    var connected_inputs := int(stats.get("connected_inputs", 0))
    var targets := int(stats.get("targets", 0))
    var finite_demand := float(stats.get("finite_demand", 0.0))
    var uncapped := int(stats.get("uncapped", 0))
    var unused := float(stats.get("unused", 0.0))

    if int(stats.get("pending_reload_ports", 0)) > 0:
        codes.append({"code": PENDING_RELOAD, "severity": Severity.WARNING, "value": int(stats.pending_reload_ports)})
    if int(stats.get("unregistered_ports", 0)) > 0:
        codes.append({"code": PORT_UNREGISTERED, "severity": Severity.ERROR, "value": int(stats.unregistered_ports)})
    if int(stats.get("cycles", 0)) > 0:
        codes.append({"code": CYCLE, "severity": Severity.ERROR, "value": int(stats.cycles)})
    if int(stats.get("invalid_values", 0)) > 0:
        codes.append({"code": INVALID_VALUES, "severity": Severity.WARNING, "value": int(stats.invalid_values)})
    if bool(stats.get("graph_truncated", false)):
        codes.append({"code": GRAPH_TRUNCATED, "severity": Severity.WARNING, "value": 0})

    if connected_inputs <= 0:
        codes.append({"code": NO_INPUT, "severity": Severity.INFO, "value": 0})
    elif supply <= 0.0:
        codes.append({"code": ZERO_SUPPLY, "severity": Severity.WARNING, "value": 0})

    if targets <= 0:
        codes.append({"code": NO_OUTPUT, "severity": Severity.INFO, "value": 0})
    elif finite_demand <= 0.0 and uncapped <= 0 and int(stats.get("blocked_ports", 0)) <= 0:
        codes.append({"code": NO_DEMAND, "severity": Severity.INFO, "value": 0})
    if int(stats.get("blocked_ports", 0)) > 0:
        codes.append({"code": PORTS_BLOCKED, "severity": Severity.INFO, "value": int(stats.blocked_ports)})

    var rate_demand := float(stats.get("rate_demand", finite_demand))
    if bool(stats.get("shortage", false)) and supply > 0.0:
        codes.append({"code": SHORTAGE, "severity": Severity.WARNING, "value": rate_demand})
    elif bool(stats.get("backlog", false)) and supply > 0.0:
        # Machines could drain their waiting stock faster: informative only.
        codes.append({"code": BACKLOG, "severity": Severity.INFO, "value": finite_demand})
    elif targets > 0 and supply > 0.0 and unused > supply * UNUSED_WARNING_SHARE:
        codes.append({"code": UNUSED, "severity": Severity.INFO, "value": unused})

    if int(stats.get("port_count", 0)) > 64:
        codes.append({"code": MANY_PORTS, "severity": Severity.INFO, "value": int(stats.port_count)})

    return codes


static func worst_severity(codes: Array) -> int:
    var worst := -1
    for entry in codes:
        worst = maxi(worst, int(entry.get("severity", 0)))
    return worst
