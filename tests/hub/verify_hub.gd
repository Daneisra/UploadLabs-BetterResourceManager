extends SceneTree

# Isolated Better Resource Hub suite. Loads the real mod scripts from their
# res://mods-unpacked/... paths with small WindowBase / ResourceContainer
# doubles. It never loads Upload Labs or a save: results prove the allocation
# logic, not in-game compatibility.

const Allocator = preload("res://mods-unpacked/Daneisra-BetterResourceManager/scripts/core/brm_allocator.gd")
const Tracker = preload("res://mods-unpacked/Daneisra-BetterResourceManager/scripts/core/brm_demand_tracker.gd")
const Layout = preload("res://mods-unpacked/Daneisra-BetterResourceManager/scripts/core/brm_port_layout.gd")
const CycleGuard = preload("res://mods-unpacked/Daneisra-BetterResourceManager/scripts/core/brm_cycle_guard.gd")
const Diagnostics = preload("res://mods-unpacked/Daneisra-BetterResourceManager/scripts/core/brm_diagnostics.gd")
const Channel = preload("res://mods-unpacked/Daneisra-BetterResourceManager/scripts/hub/brm_resource_channel.gd")
const WData = preload("res://mods-unpacked/Daneisra-BetterResourceManager/scripts/global/smart_window_data.gd")
const Legacy = preload("res://mods-unpacked/Daneisra-BetterResourceManager/scripts/global/distribution_modes.gd")
const Aliases = preload("res://mods-unpacked/Daneisra-BetterResourceManager/scripts/global/legacy_scene_aliases.gd")
const Unlocks = preload("res://mods-unpacked/Daneisra-BetterResourceManager/scripts/global/manager_unlocks.gd")

const CPU := "clock_speed"
const GPU := "gpu_speed"
const POLICIES := [0, 1, 2, 3]

var checks := 0
var failures := 0
var fixtures: Array[Node] = []
var sections: Dictionary = {}
var current_section := ""
var _id_counter := 0


class WorkProcess extends Node:
    var goal_obj: Node
    var speed_obj: Node
    var resources: Array[ResourceContainer] = []
    var should_consume := true


class WorkGoal extends Node:
    var value := 1.0


class WorkSpeed extends Node:
    var resource: ResourceContainer
    var rate := 1.0
    var inf_speed := false


func _init() -> void:
    call_deferred("run")


func run() -> void:
    section("01 aggregation CPU", test_aggregation.bind(CPU))
    section("02 aggregation GPU", test_aggregation.bind(GPU))
    section("03 distribution 2/10/30/100", test_distribution_sizes)
    section("04 CPU/GPU independent", test_independence)
    section("05 conservation fuzz", test_conservation_fuzz)
    section("06 no over-allocation extremes", test_extremes)
    section("07 fair shortage", test_fair_shortage)
    section("08 priorities and weights", test_priorities_weights)
    section("09 surplus redistribution", test_surplus)
    section("10 demand variations", test_demand_variation)
    section("11 cycle detection", test_cycles)
    section("12 uncapped consumers", test_uncapped)
    section("13 dynamic ports", test_dynamic_ports)
    section("14 port ids after save/reload", test_port_persistence)
    section("15 legacy manager compatibility", test_legacy_compatibility)
    section("16 AI Trainer regression", test_ai_trainer_regression)
    section("17 determinism", test_determinism)
    section("18 diagnostics", test_diagnostics)
    section("19 performance", test_performance)

    for node in fixtures:
        if is_instance_valid(node):
            node.free()
    fixtures.clear()

    for name in sections.keys():
        print("BRM HUB SECTION %s: %d checks, %d failures" % [name, sections[name].checks, sections[name].failures])
    print("BRM HUB: %d checks, %d failures" % [checks, failures])
    quit(0 if failures == 0 else 1)


# --- 1/2 aggregation ------------------------------------------------------

func test_aggregation(resource: String) -> void:
    for size in [2, 10, 50]:
        var hub := make_window("hub_%s_%d" % [resource, size])
        var inputs: Array = []
        var expected := 0.0
        for index in range(size):
            var amount := float(index + 1) * 1.5e18
            inputs.append({"uid": "in_%d" % index, "container": hub_input(hub, resource, amount)})
            expected += amount
        var consumer := make_consumer("sink_%s_%d" % [resource, size], resource, 1.0, 1.0, 1e30, 0.0)
        var out := hub_output(hub, resource)
        wire(out, consumer.speed)
        var channel := Channel.new(resource, hub)
        channel.set_ports(inputs, [{"uid": "out_1", "container": out, "settings": Layout.default_settings()}])
        channel.tick(Channel.Mode.AUTO)
        near(channel.stats.supply, expected, "%d inputs aggregate" % size)
        check(channel.stats.connected_inputs == size, "%d inputs counted as connected" % size)
        near(consumer.speed.count, expected, "%d inputs: whole pool delivered, nothing created" % size)
        check(channel.stats.allocated <= expected * (1.0 + 1e-12), "%d inputs: no over-allocation" % size)


# --- 3 distribution --------------------------------------------------------

func test_distribution_sizes() -> void:
    for size in [2, 10, 30, 100]:
        var hub := make_window("hub_dist_%d" % size)
        var consumers: Array = []
        var total := 0.0
        var out := hub_output(hub, CPU)
        for index in range(size):
            var consumer := make_consumer("c%d_%d" % [size, index], CPU, 10.0 * (index + 1), 1.0, 1.0, 0.0)
            wire(out, consumer.speed)
            consumers.append(consumer)
            total += 10.0 * (index + 1)
        var supply_input := hub_input(hub, CPU, total * 2.0)
        var channel := Channel.new(CPU, hub)
        channel.set_ports([{"uid": "in_1", "container": supply_input}], [{"uid": "out_1", "container": out, "settings": Layout.default_settings()}])
        channel.tick(Channel.Mode.AUTO)
        near(channel.stats.finite_demand, total, "%d consumers: total demand read" % size)
        var allocated := 0.0
        var satisfied := true
        for consumer in consumers:
            allocated += consumer.speed.count
            satisfied = satisfied and consumer.speed.count + 1e-9 >= consumer.data_demand
        check(satisfied, "%d consumers: every demand satisfied with enough supply" % size)
        near(allocated, total * 2.0, "%d consumers: surplus redistributed, pool fully used" % size)

        supply_input.count = total * 0.5
        channel.tick(Channel.Mode.AUTO)
        allocated = 0.0
        for consumer in consumers:
            allocated += consumer.speed.count
        near(allocated, total * 0.5, "%d consumers: shortage uses the whole pool" % size)
        check(channel.stats.shortage, "%d consumers: shortage reported" % size)
        var fair_share := minf(consumers[0].data_demand, total * 0.5 / float(size))
        near(consumers[0].speed.count, fair_share, "%d consumers: smallest demand gets min(demand, fair share)" % size)


# --- 4 independence -------------------------------------------------------

func test_independence() -> void:
    var hub := make_window("hub_indep")
    var cpu_in := hub_input(hub, CPU, 1000.0)
    var gpu_in := hub_input(hub, GPU, 0.0)
    var cpu_out := hub_output(hub, CPU)
    var gpu_out := hub_output(hub, GPU)
    var cpu_consumer := make_consumer("cpu_only", CPU, 100.0, 1.0, 1.0, 0.0)
    var gpu_consumer := make_consumer("gpu_only", GPU, 100.0, 1.0, 1.0, 0.0)
    wire(cpu_out, cpu_consumer.speed)
    wire(gpu_out, gpu_consumer.speed)
    var cpu := Channel.new(CPU, hub)
    var gpu := Channel.new(GPU, hub)
    cpu.set_ports([{"uid": "cpu_in_1", "container": cpu_in}], [{"uid": "cpu_out_1", "container": cpu_out, "settings": Layout.default_settings()}])
    gpu.set_ports([{"uid": "gpu_in_1", "container": gpu_in}], [{"uid": "gpu_out_1", "container": gpu_out, "settings": Layout.default_settings()}])
    cpu.tick(Channel.Mode.AUTO)
    gpu.tick(Channel.Mode.AUTO)
    near(cpu_consumer.speed.count, 1000.0, "CPU consumer receives the CPU pool")
    near(gpu_consumer.speed.count, 0.0, "GPU consumer gets no CPU (no conversion)")
    gpu_in.count = 500.0
    cpu.tick(Channel.Mode.AUTO)
    gpu.tick(Channel.Mode.AUTO)
    near(cpu_consumer.speed.count, 1000.0, "GPU supply does not change CPU allocations")
    near(gpu_consumer.speed.count, 500.0, "GPU consumer receives the GPU pool")
    near(cpu.stats.supply + gpu.stats.supply, 1500.0, "pools are counted separately")

    # A CPU output wired to a GPU-speed machine is not a GPU source: the CPU
    # channel only sees CPU targets.
    check(not cpu.get_targets().has("gpu_only"), "GPU machine is not a CPU target")


# --- 5/6 conservation -----------------------------------------------------

func test_conservation_fuzz() -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = 20261102
    var violations := 0
    var cap_violations := 0
    var absorb_failures := 0
    for case_index in range(600):
        var supply := pow(10.0, rng.randf_range(-3.0, 25.0)) if rng.randf() > 0.05 else 0.0
        var requests: Array = []
        var count := rng.randi_range(0, 40)
        for index in range(count):
            var demand := pow(10.0, rng.randf_range(-3.0, 24.0))
            if rng.randf() < 0.1:
                demand = 0.0
            var request := {
                "key": "r%03d" % index,
                "demand": demand,
                "uncapped": rng.randf() < 0.15,
                "weight": rng.randf_range(0.0, 5.0),
                "priority": rng.randi_range(-3, 3),
                "max": pow(10.0, rng.randf_range(0.0, 25.0)) if rng.randf() < 0.3 else INF,
                "min": pow(10.0, rng.randf_range(-3.0, 22.0)) if rng.randf() < 0.2 else 0.0,
                "enabled": rng.randf() > 0.1,
            }
            requests.append(request)
        for policy in POLICIES:
            var result := Allocator.allocate(supply, requests, policy)
            var total := 0.0
            for request in requests:
                var amount := float(result.allocations[request.key])
                if not is_finite(amount) or amount < 0.0 or (not request.enabled and amount != 0.0):
                    violations += 1
                if amount > float(request.max) * (1.0 + 1e-9) + 1e-9:
                    cap_violations += 1
                total += amount
            if total > supply * (1.0 + 1e-12):
                violations += 1
            if policy == Allocator.Policy.AUTO:
                var capacity := 0.0
                var absorbs := false
                for request in requests:
                    if request.enabled and (request.demand > 0.0 or request.uncapped) and request.weight > 0.0:
                        absorbs = true
                        capacity += float(request.max)
                if absorbs and capacity >= supply * 1.000001 and total < supply * (1.0 - 1e-6):
                    absorb_failures += 1
    check(violations == 0, "no negative, non-finite, disabled or over-supply allocation (%d)" % violations)
    check(cap_violations == 0, "maximum limits respected (%d)" % cap_violations)
    check(absorb_failures == 0, "Auto leaves nothing idle when targets can absorb it (%d)" % absorb_failures)


func test_extremes() -> void:
    var cases := [
        {"supply": 1.0e300, "demands": [1.0e300, 1.0e300, 5.0e299]},
        {"supply": 1.0e-300, "demands": [1.0e-300, 2.0e-300]},
        {"supply": 5.36e21, "demands": [2.68e20, 7.36e19, 5.886e8]},
        {"supply": NAN, "demands": [10.0]},
        {"supply": INF, "demands": [10.0]},
        {"supply": -5.0, "demands": [10.0]},
        {"supply": 100.0, "demands": [NAN, INF, -INF, -3.0, 50.0]},
    ]
    for entry in cases:
        var requests: Array = []
        for index in range(entry.demands.size()):
            requests.append({"key": "e%d" % index, "demand": entry.demands[index]})
        for policy in POLICIES:
            var result := Allocator.allocate(entry.supply, requests, policy)
            var total := 0.0
            var finite := true
            for key in result.allocations.keys():
                finite = finite and is_finite(float(result.allocations[key])) and float(result.allocations[key]) >= 0.0
                total += float(result.allocations[key])
            check(finite, "extreme %s policy %d: finite non-negative" % [str(entry.supply), policy])
            check(total <= float(result.supply) * (1.0 + 1e-12), "extreme %s policy %d: within supply" % [str(entry.supply), policy])
    var invalid := Allocator.allocate(NAN, [{"key": "a", "demand": NAN}], Allocator.Policy.AUTO)
    check(int(invalid.invalid_values) >= 2, "invalid values are counted")
    near(float(invalid.allocated), 0.0, "NaN supply allocates nothing")
    var infinite := Allocator.allocate(INF, [{"key": "a", "demand": 1.0}], Allocator.Policy.AUTO)
    near(float(infinite.allocated), 0.0, "infinite supply is refused, never distributed")
    var uncapped := Allocator.allocate(100.0, [{"key": "a", "demand": INF}, {"key": "b", "demand": 50.0}], Allocator.Policy.AUTO)
    near(float(uncapped.allocations.b), 50.0, "INF demand is read as uncapped and served after finite demand")
    near(float(uncapped.allocations.a), 50.0, "uncapped receives the leftovers")


# --- 7 fairness -----------------------------------------------------------

func test_fair_shortage() -> void:
    for policy in [Allocator.Policy.AUTO, Allocator.Policy.DEMAND]:
        var equal := Allocator.allocate(200.0, [req("a", 100), req("b", 100), req("c", 100), req("d", 100)], policy)
        for key in ["a", "b", "c", "d"]:
            near(float(equal.allocations[key]), 50.0, "policy %d equal shortage share %s" % [policy, key])
        var maxmin := Allocator.allocate(110.0, [req("small", 10), req("big1", 100), req("big2", 100)], policy)
        near(float(maxmin.allocations.small), 10.0, "policy %d small demand fully served" % policy)
        near(float(maxmin.allocations.big1), 50.0, "policy %d remaining split evenly (1)" % policy)
        near(float(maxmin.allocations.big2), 50.0, "policy %d remaining split evenly (2)" % policy)
    var ratio := Allocator.allocate(200.0, [req("a", 100), req("b", 300)], Allocator.Policy.RATIO)
    near(float(ratio.allocations.a), 50.0, "Ratio scales every demand by the same factor (a)")
    near(float(ratio.allocations.b), 150.0, "Ratio scales every demand by the same factor (b)")
    var starved := Allocator.allocate(1.0, [req("x", 1e21), req("y", 1e21), req("z", 1e21)], Allocator.Policy.AUTO)
    for key in ["x", "y", "z"]:
        check(float(starved.allocations[key]) > 0.3, "tiny supply still reaches %s (no starvation ladder)" % key)


# --- 8 priorities / weights -------------------------------------------------

func test_priorities_weights() -> void:
    var strict := Allocator.allocate(120.0, [req("high", 100, 1.0, 1), req("low", 100, 1.0, 0)], Allocator.Policy.PRIORITY)
    near(float(strict.allocations.high), 100.0, "Priority: higher tier fully served first")
    near(float(strict.allocations.low), 20.0, "Priority: lower tier gets the rest")
    var strict_starve := Allocator.allocate(80.0, [req("high", 100, 1.0, 1), req("low", 100, 1.0, 0)], Allocator.Policy.PRIORITY)
    near(float(strict_starve.allocations.low), 0.0, "Priority: lower tier may starve (documented)")

    var soft := Allocator.allocate(120.0, [req("high", 1000, 1.0, 1), req("low", 1000, 1.0, 0)], Allocator.Policy.AUTO)
    near(float(soft.allocations.high), 80.0, "Auto: one priority step doubles the share")
    near(float(soft.allocations.low), 40.0, "Auto: lower priority is never starved")

    var weighted := Allocator.allocate(400.0, [req("w3", 1000, 3.0), req("w1", 1000, 1.0)], Allocator.Policy.AUTO)
    near(float(weighted.allocations.w3), 300.0, "Auto: weight 3 gets three shares")
    near(float(weighted.allocations.w1), 100.0, "Auto: weight 1 gets one share")

    var with_min := Allocator.allocate(100.0, [req("high", 1000, 1.0, 5), {"key": "low", "demand": 1000.0, "min": 30.0}], Allocator.Policy.PRIORITY)
    near(float(with_min.allocations.low), 30.0, "Priority: minimum reserved for a low priority")
    near(float(with_min.allocations.high), 70.0, "Priority: rest goes to the high tier")

    var capped := Allocator.allocate(1000.0, [{"key": "cap", "demand": 1000.0, "max": 100.0}, req("free", 50)], Allocator.Policy.AUTO)
    near(float(capped.allocations.cap), 100.0, "maximum limit respected")
    near(float(capped.allocations.free), 900.0, "surplus beyond a maximum goes elsewhere")

    var disabled := Allocator.allocate(100.0, [{"key": "off", "demand": 50.0, "enabled": false}, req("on", 50)], Allocator.Policy.AUTO)
    near(float(disabled.allocations.off), 0.0, "disabled target receives nothing")
    near(float(disabled.allocations.on), 100.0, "enabled target receives the pool")


# --- 9 surplus --------------------------------------------------------------

func test_surplus() -> void:
    var auto := Allocator.allocate(1000.0, [req("a", 100), req("b", 300)], Allocator.Policy.AUTO)
    near(float(auto.allocations.a), 250.0, "Auto surplus in proportion to demand (a)")
    near(float(auto.allocations.b), 750.0, "Auto surplus in proportion to demand (b)")
    near(float(auto.unused), 0.0, "Auto leaves no unused supply")
    var ratio := Allocator.allocate(1000.0, [req("a", 100), req("b", 300)], Allocator.Policy.RATIO)
    near(float(ratio.unused), 600.0, "Ratio keeps the original behaviour: surplus without uncapped targets stays unused")
    var demand := Allocator.allocate(1000.0, [req("a", 100), req("b", 300)], Allocator.Policy.DEMAND)
    near(float(demand.unused), 0.0, "Demand keeps test23 surplus boost")
    var idle := Allocator.allocate(90.0, [req("a", 0), req("b", 0), req("c", 0)], Allocator.Policy.AUTO)
    near(float(idle.allocations.a), 30.0, "no demand anywhere: even split (test23 rule)")

    # Channel: freed capacity is redistributed on the next tick.
    var hub := make_window("hub_redistribute")
    var out := hub_output(hub, CPU)
    var first := make_consumer("first", CPU, 100.0, 1.0, 1.0, 0.0)
    var second := make_consumer("second", CPU, 100.0, 1.0, 1.0, 0.0)
    wire(out, first.speed)
    wire(out, second.speed)
    var supply := hub_input(hub, CPU, 150.0)
    var channel := Channel.new(CPU, hub)
    channel.set_ports([{"uid": "in", "container": supply}], [{"uid": "out", "container": out, "settings": Layout.default_settings()}])
    channel.tick(Channel.Mode.DEMAND)
    near(first.speed.count, 75.0, "shortage split before pause")
    first.window.paused = true
    channel.tick(Channel.Mode.DEMAND)
    near(second.speed.count, 150.0, "paused consumer's share is redistributed")
    near(first.speed.count, 0.0, "paused consumer receives nothing")
    first.window.paused = false


# --- 10 demand variation ----------------------------------------------------

func test_demand_variation() -> void:
    var tracker := Tracker.new()
    near(tracker.smooth("k", 100.0), 100.0, "first sample taken as is")
    near(tracker.smooth("k", 101.0), 100.0, "change inside deadband ignored")
    var risen := tracker.smooth("k", 200.0)
    check(risen > 150.0 and risen < 200.0, "rise is fast but smoothed (%s)" % risen)
    var value := risen
    for _i in range(20):
        value = tracker.smooth("k", 200.0)
    near(value, 200.0, "converges to a stable new demand", 0.03)
    var fallen := tracker.smooth("k", 100.0)
    check(fallen > 150.0, "fall is slower than rise (%s)" % fallen)
    for _i in range(40):
        value = tracker.smooth("k", 0.0)
    near(value, 0.0, "settles to zero when demand disappears")
    tracker.retain([])
    check(tracker.size() == 0, "stale keys dropped")

    var hub := make_window("hub_variation")
    var out := hub_output(hub, CPU)
    var a := make_consumer("var_a", CPU, 100.0, 1.0, 1.0, 0.0)
    var b := make_consumer("var_b", CPU, 100.0, 1.0, 1.0, 0.0)
    wire(out, a.speed)
    wire(out, b.speed)
    var supply := hub_input(hub, CPU, 150.0)
    var channel := Channel.new(CPU, hub)
    channel.set_ports([{"uid": "in", "container": supply}], [{"uid": "out", "container": out, "settings": Layout.default_settings()}])
    channel.tick(Channel.Mode.AUTO)
    near(a.speed.count, 75.0, "equal demands split evenly")
    a.goal.value = 30.0
    for _i in range(30):
        channel.tick(Channel.Mode.AUTO)
    # Supply now exceeds demand (130): both get demand plus a proportional
    # share of the 20 surplus.
    near(a.speed.count, 150.0 * 30.0 / 130.0, "lower demand is followed", 0.03)
    near(b.speed.count, 150.0 * 100.0 / 130.0, "freed share moves to the other consumer", 0.03)
    near(a.speed.count + b.speed.count, 150.0, "conservation while demand changes")


# --- 11 cycles ----------------------------------------------------------

func test_cycles() -> void:
    var adjacency := {"A": ["B"], "B": ["C"], "C": ["A", "D"], "D": []}
    var closure := CycleGuard.upstream_closure("A", CycleGuard.from_adjacency(adjacency))
    check(closure.names.has("B") and closure.names.has("C") and closure.names.has("D"), "closure follows every upstream window")
    check(closure.names.has("A"), "a loop back to the start is detected")
    check(not closure.truncated, "small graph not truncated")
    var big := {}
    for index in range(10000):
        big["n%d" % index] = ["n%d" % (index + 1), "n0"]
    var bounded := CycleGuard.upstream_closure("n0", CycleGuard.from_adjacency(big), 500)
    check(bounded.truncated and int(bounded.visited) <= 500, "huge looping graph stops at the node budget")

    # hub CPU out -> manager -> hub CPU in: the manager must receive nothing.
    var hub := make_window("hub_cycle")
    var manager := make_window("loop_manager")
    var manager_in := add_container(manager, CPU, 1, true)
    var manager_out := add_container(manager, CPU, 1, false)
    var hub_in := hub_input(hub, CPU, 0.0)
    var real_source := make_window("real_source")
    var real_out := add_container(real_source, CPU, 1, false)
    var hub_in2 := hub_input(hub, CPU, 500.0)
    wire(real_out, hub_in2)
    wire(manager_out, hub_in)
    var out := hub_output(hub, CPU)
    wire(out, manager_in)
    var consumer := make_consumer("after_loop", CPU, 100.0, 1.0, 1.0, 0.0)
    wire(out, consumer.speed)
    manager_in.count = 999.0
    var channel := Channel.new(CPU, hub)
    channel.set_ports([{"uid": "in1", "container": hub_in}, {"uid": "in2", "container": hub_in2}], [{"uid": "out", "container": out, "settings": Layout.default_settings()}])
    channel.tick(Channel.Mode.AUTO)
    near(manager_in.count, 0.0, "loop target receives nothing")
    check(int(channel.stats.cycles) == 1, "loop reported once")
    near(consumer.speed.count, 500.0, "rest of the network keeps working")
    check(not channel.get_targets().has("loop_manager"), "loop target excluded from allocation")

    # Direct self-loop: hub out -> hub in.
    var self_hub := make_window("hub_self")
    var self_in := hub_input(self_hub, GPU, 0.0)
    var self_out := hub_output(self_hub, GPU)
    wire(self_out, self_in)
    self_in.count = 123.0
    var self_channel := Channel.new(GPU, self_hub)
    self_channel.set_ports([{"uid": "in", "container": self_in}], [{"uid": "out", "container": self_out, "settings": Layout.default_settings()}])
    self_channel.tick(Channel.Mode.AUTO)
    self_channel.tick(Channel.Mode.AUTO)
    near(self_in.count, 0.0, "self-loop cannot recirculate supply")

    # Vanilla loop protection list is honoured too.
    var vanilla_hub := make_window("hub_vanilla_loop")
    var vanilla_out := hub_output(vanilla_hub, CPU)
    var looped := make_consumer("vanilla_looped", CPU, 100.0, 1.0, 1.0, 0.0)
    wire(vanilla_out, looped.speed)
    vanilla_out.looping.append(looped.speed)
    var vanilla_supply := hub_input(vanilla_hub, CPU, 100.0)
    var vanilla := Channel.new(CPU, vanilla_hub)
    vanilla.set_ports([{"uid": "in", "container": vanilla_supply}], [{"uid": "out", "container": vanilla_out, "settings": Layout.default_settings()}])
    vanilla.tick(Channel.Mode.AUTO)
    near(looped.speed.count, 0.0, "target in vanilla looping list receives nothing")


# --- 12 uncapped ----------------------------------------------------------

func test_uncapped() -> void:
    var hub := make_window("hub_uncapped")
    var out := hub_output(hub, GPU)
    var finite := make_consumer("finite_gpu", GPU, 100.0, 1.0, 1.0, 0.0)
    var seller := make_window("seller")
    var seller_speed := add_container(seller, GPU, 1, true)
    var miner := make_window("miner")
    var miner_speed := add_container(miner, GPU, 1, true)
    wire(out, finite.speed)
    wire(out, seller_speed)
    wire(out, miner_speed)
    var supply := hub_input(hub, GPU, 1000.0)
    var channel := Channel.new(GPU, hub)
    channel.set_ports([{"uid": "in", "container": supply}], [{"uid": "out", "container": out, "settings": Layout.default_settings()}])
    for mode in [Channel.Mode.AUTO, Channel.Mode.DEMAND, Channel.Mode.RATIO, Channel.Mode.PRIORITY]:
        channel.tick(mode)
        near(finite.speed.count, 100.0, "mode %d: finite demand served first" % mode)
        near(seller_speed.count, 450.0, "mode %d: uncapped targets share leftovers (1)" % mode)
        near(miner_speed.count, 450.0, "mode %d: uncapped targets share leftovers (2)" % mode)
        check(int(channel.stats.uncapped) == 2, "mode %d: uncapped targets counted" % mode)
    supply.count = 50.0
    channel.tick(Channel.Mode.AUTO)
    near(finite.speed.count, 50.0, "shortage: finite consumer before uncapped")
    near(seller_speed.count, 0.0, "shortage: uncapped gets nothing")


# --- 13 dynamic ports -------------------------------------------------------

func test_dynamic_ports() -> void:
    var layout := Layout.default_layout()
    check(Layout.ports_of(layout, Layout.Kind.CPU_INPUT).size() == 1, "default layout has one port of each kind")
    var second := Layout.add_port(layout, Layout.Kind.CPU_INPUT)
    var third := Layout.add_port(layout, Layout.Kind.CPU_INPUT)
    check(second == "cpu_in_2" and third == "cpu_in_3", "uids are sequential per kind")
    check(Layout.remove_port(layout, second), "port removed")
    var fourth := Layout.add_port(layout, Layout.Kind.CPU_INPUT)
    check(fourth == "cpu_in_4", "a removed uid is never reused")
    check(Layout.find_port(layout, second) < 0, "removed port is gone")
    for _i in range(300):
        Layout.add_port(layout, Layout.Kind.GPU_OUTPUT)
    check(Layout.ports_of(layout, Layout.Kind.GPU_OUTPUT).size() == Layout.PORTS_PER_KIND_GUARD, "corruption guard caps a kind at %d ports" % Layout.PORTS_PER_KIND_GUARD)
    check(Layout.add_port(layout, 99).is_empty(), "unknown kind refused")
    check(Layout.set_setting(layout, "cpu_out_1", "priority", 50) and int(Layout.get_port(layout, "cpu_out_1").settings.priority) == 10, "settings are clamped")
    check(not Layout.set_setting(layout, "cpu_in_1", "priority", 1), "inputs have no allocation settings")
    check(Layout.set_label(layout, "cpu_in_1", "  AI Trainer line\n  ") and Layout.get_port(layout, "cpu_in_1").label == "AI Trainer line", "labels are trimmed")

    # Channel follows ports added and removed while running.
    var hub := make_window("hub_dynamic")
    var a := make_consumer("dyn_a", CPU, 100.0, 1.0, 1.0, 0.0)
    var b := make_consumer("dyn_b", CPU, 100.0, 1.0, 1.0, 0.0)
    var out_a := hub_output(hub, CPU)
    var out_b := hub_output(hub, CPU)
    wire(out_a, a.speed)
    wire(out_b, b.speed)
    var in_1 := hub_input(hub, CPU, 100.0)
    var in_2 := hub_input(hub, CPU, 100.0)
    var channel := Channel.new(CPU, hub)
    channel.set_ports([{"uid": "cpu_in_1", "container": in_1}], [{"uid": "cpu_out_1", "container": out_a, "settings": Layout.default_settings()}])
    channel.tick(Channel.Mode.AUTO)
    near(a.speed.count, 100.0, "one port: single target")
    channel.set_ports(
        [{"uid": "cpu_in_1", "container": in_1}, {"uid": "cpu_in_2", "container": in_2}],
        [{"uid": "cpu_out_1", "container": out_a, "settings": Layout.default_settings()}, {"uid": "cpu_out_2", "container": out_b, "settings": Layout.default_settings()}]
    )
    channel.tick(Channel.Mode.AUTO)
    near(channel.stats.supply, 200.0, "added input joins the pool")
    near(a.speed.count + b.speed.count, 200.0, "added output receives its share")
    near(float(channel.port_flows.cpu_out_2), b.speed.count, "per-port flow reported")
    channel.set_ports([{"uid": "cpu_in_2", "container": in_2}], [{"uid": "cpu_out_2", "container": out_b, "settings": Layout.default_settings()}])
    channel.tick(Channel.Mode.AUTO)
    near(channel.stats.supply, 100.0, "removed input leaves the pool")
    near(b.speed.count, 100.0, "remaining output gets everything")
    check(not channel.get_targets().has("dyn_a"), "removed output's machine is no longer a target")

    var empty := Channel.new(CPU, make_window("hub_empty"))
    empty.set_ports([], [])
    empty.tick(Channel.Mode.AUTO)
    near(empty.stats.supply, 0.0, "no input: zero supply, no error")
    check(int(empty.stats.targets) == 0, "no output: no target, no error")

    # Disabled port and manual port.
    var settings_off := Layout.default_settings()
    settings_off.enabled = false
    var settings_manual := Layout.default_settings()
    settings_manual.manual = true
    settings_manual.max = 30.0
    channel.set_ports(
        [{"uid": "cpu_in_1", "container": in_1}, {"uid": "cpu_in_2", "container": in_2}],
        [{"uid": "cpu_out_1", "container": out_a, "settings": settings_manual}, {"uid": "cpu_out_2", "container": out_b, "settings": settings_off}]
    )
    channel.tick(Channel.Mode.AUTO)
    near(a.speed.count, 30.0, "manual output receives exactly its configured amount")
    near(b.speed.count, 0.0, "switched-off output receives nothing")
    near(channel.stats.unused, 170.0, "what nobody may take is reported unused")


# --- 14 persistence ---------------------------------------------------------

func test_port_persistence() -> void:
    var layout := Layout.default_layout()
    Layout.add_port(layout, Layout.Kind.GPU_OUTPUT)
    Layout.add_port(layout, Layout.Kind.GPU_OUTPUT)
    Layout.remove_port(layout, "gpu_out_2")
    Layout.set_label(layout, "gpu_out_3", "AI Trainer")
    Layout.set_setting(layout, "gpu_out_3", "weight", 2.5)
    var saved := Layout.to_save(layout)

    # Godot ConfigFile text round trip (what the save file uses).
    var text := var_to_str(saved)
    var restored := Layout.from_save(str_to_var(text))
    check(restored.valid, "saved layout reloads")
    check(uids(restored.layout) == uids(layout), "uids and order survive save/reload")
    check(Layout.get_port(restored.layout, "gpu_out_3").label == "AI Trainer", "label survives")
    near(float(Layout.get_port(restored.layout, "gpu_out_3").settings.weight), 2.5, "settings survive")
    check(Layout.add_port(restored.layout, Layout.Kind.GPU_OUTPUT) == "gpu_out_4", "counter survives: no uid reuse after reload")

    # JSON round trip turns ints into floats; still accepted.
    var json := Layout.from_save(JSON.parse_string(JSON.stringify(saved)))
    check(json.valid and uids(json.layout) == uids(layout), "JSON-typed save accepted")

    # Corrupted data.
    var corrupt := {
        "ports": [
            {"uid": "cpu_in_1", "kind": 0},
            {"uid": "cpu_in_1", "kind": 0},
            {"uid": "cpu_in_x", "kind": 0},
            {"uid": "gpu_out_7", "kind": 1},
            {"uid": "gpu_out_7", "kind": 3, "settings": {"weight": NAN, "priority": 99, "max": -5}},
            {"uid": "zzz", "kind": 42},
            "garbage",
        ],
        "next": {"cpu_in": -4, "gpu_out": 2},
    }
    var repaired := Layout.from_save(corrupt)
    check(uids(repaired.layout) == ["cpu_in_1", "gpu_out_7"], "only valid unique ports kept")
    check(int(repaired.report.duplicates) == 1 and int(repaired.report.dropped) == 4, "dropped and duplicate ports reported")
    check(int(repaired.layout.next.gpu_out) == 8, "counter raised above kept uids")
    check(int(Layout.get_port(repaired.layout, "gpu_out_7").settings.priority) == 10, "corrupted settings sanitised")
    check(not Layout.from_save("not a layout").valid, "non-dictionary save rejected")

    # Container node path contract is derived from the uid only.
    check(Layout.KIND_PREFIXES[Layout.Kind.CPU_INPUT] == "cpu_in" and Layout.KIND_PREFIXES[Layout.Kind.GPU_OUTPUT] == "gpu_out", "uid prefixes are part of the save contract")


# --- 15 legacy compatibility -------------------------------------------------

func test_legacy_compatibility() -> void:
    var kuuk_stm := "res://mods-unpacked/kuuk-SmartThreadManager/scenes/windows/window_smart_thread_manager.tscn"
    check(Aliases.to_save_filename(kuuk_stm) == "../../mods-unpacked/kuuk-SmartThreadManager/scenes/windows/window_smart_thread_manager.tscn", "kuuk STM path saved exactly as kuuk wrote it")
    check(Aliases.to_save_filename("res://mods-unpacked/kuuk-SmartGPUManager/scenes/windows/window_smart_gpu_manager.tscn") == "../../mods-unpacked/kuuk-SmartGPUManager/scenes/windows/window_smart_gpu_manager.tscn", "kuuk SGM path saved exactly as kuuk wrote it")
    check(Aliases.to_save_filename("res://scenes/windows/window_trainer.tscn") == "window_trainer.tscn", "vanilla paths keep their short form")
    check(("res://scenes/windows/" + Aliases.to_save_filename(kuuk_stm)).simplify_path() == kuuk_stm, "saved filename resolves back to the aliased path")
    check(Aliases.LEGACY_SCENES.size() == 4, "kuuk and ASM scene paths are aliased")
    for alias in Aliases.LEGACY_SCENES.keys():
        check(str(Aliases.LEGACY_SCENES[alias]) in ["window_smart_thread_manager.tscn", "window_smart_gpu_manager.tscn"], "alias target is a BRM manager scene")

    var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://brm_data.json"))
    for id in ["smart_thread_manager", "smart_gpu_manager", "better_resource_hub"]:
        check(data.windows.has(id), "window id registered: %s" % id)
        check(str(data.windows[id].scene).begins_with("../../mods-unpacked/Daneisra-BetterResourceManager/scenes/windows/"), "%s scene lives in the BRM folder" % id)
    check(data.windows.smart_thread_manager.category == "cpu" and data.windows.smart_gpu_manager.category == "gpu", "legacy categories unchanged")
    var modern := data.duplicate(true)
    Unlocks.synchronize(modern, {"thread_manager": {"requirement": ["research.thread_manager"], "requirement_mode": 0}, "gpu_manager": {"requirement": ["research.gpu_manager"]}})
    check(modern.windows.better_resource_hub.requirement == ["research.thread_manager"], "hub unlocks with the base Thread Manager")
    check(modern.guides.window_better_resource_hub.entries[0].requirement == ["research.thread_manager"], "hub guide unlocks with it")
    check(modern.windows.smart_gpu_manager.requirement == ["research.gpu_manager"], "GPU manager unlock unchanged")
    var reduced := data.duplicate(true)
    reduced.windows.erase("smart_thread_manager")
    reduced.guides.erase("window_smart_thread_manager")
    Unlocks.synchronize(reduced, {"thread_manager": {"requirement": "perk.thread_manager"}})
    check(reduced.windows.better_resource_hub.requirement == "perk.thread_manager", "hub still syncs when legacy managers are not registered")

    # Legacy Auto (manager option id 3) through distribution_modes.
    var state := legacy_state()
    var tracker := Tracker.new()
    state.auto_demands = {"p1": 100.0, "p2": 300.0}
    state.allocator = Allocator
    state.tracker = tracker
    Legacy.distribution_auto(1000.0, state)
    near(state.wdata.p1.own_sources[0].count, 100.0, "legacy Auto: finite demand first (1)")
    near(state.wdata.p2.own_sources[0].count, 300.0, "legacy Auto: finite demand first (2)")
    near(state.wdata.store.own_sources[0].count, 600.0, "legacy Auto: uncapped target takes the leftovers, as in the original")
    near(float(state.demand), 400.0, "legacy Auto reports finite demand")

    var no_storage := legacy_state()
    no_storage.storages = []
    no_storage.storage_connections = 0
    no_storage.auto_demands = {"p1": 100.0, "p2": 300.0}
    no_storage.allocator = Allocator
    no_storage.tracker = Tracker.new()
    Legacy.distribution_auto(1000.0, no_storage)
    near(no_storage.wdata.p1.own_sources[0].count, 250.0, "legacy Auto without uncapped: surplus back to finite consumers (1)")
    near(no_storage.wdata.p2.own_sources[0].count, 750.0, "legacy Auto without uncapped: surplus back to finite consumers (2)")

    # Original modes are untouched: Ratio leaves surplus to storages.
    var ratio_state := legacy_state()
    Legacy.distribution_ratio(1000.0, ratio_state)
    near(ratio_state.wdata.p1.own_sources[0].count, 100.0, "legacy Ratio unchanged (finite)")
    near(ratio_state.wdata.store.own_sources[0].count, 600.0, "legacy Ratio unchanged (storage gets leftovers)")


func legacy_state() -> Dictionary:
    var p1 := make_consumer("legacy_p1", CPU, 100.0, 1.0, 1.0, 0.0)
    var p2 := make_consumer("legacy_p2", CPU, 300.0, 1.0, 1.0, 0.0)
    var store := make_window("legacy_store")
    var store_speed := add_container(store, CPU, 1, true)
    var store_data = WData.new(store)
    store_data.set_containers([store_speed.id])
    return {
        "wdata": {"p1": p1.data, "p2": p2.data, "store": store_data},
        "demands": {"p1": 100.0, "p2": 300.0, "store": 0.0},
        "old_demands": {},
        "consumers": ["p1", "p2"],
        "managers": [],
        "storages": ["store"],
        "storage_connections": 1,
    }


# --- 16 AI Trainer ----------------------------------------------------------
#
# Reported on Upload Labs 3.0.12 with kuuk's Smart GPU Manager:
#   GPU Cluster Mk.47 -> GPU Manager -> Smart GPU Manager
#   Smart GPU Manager -> Neuron Reinforcer, AI Trainer, Text Generator
#   AI Trainer fed ~268 EHz (~334k neurons/s); wired straight to the GPU Manager
#   it got ~2.95 ZHz (~736k neurons/s) while ~5.36 ZHz was available.
# The save copy shows the AI Trainer holding 1.84e16 text in its input.
# Two causes reproduce here: (1) Ratio/Graph never give surplus to finite
# consumers (kuuk Demand neither), and (2) count/s demand only reads the
# inflow, not the backlog waiting in the trainer. The simulation proves the
# allocation, not neuron production; the in-game check is still required.

func test_ai_trainer_regression() -> void:
    var supply := 5.36e21
    var direct := 2.95e21
    var hub := make_window("hub_ai")
    var out := hub_output(hub, GPU)
    # Rate-based demand of each machine = production / required * goal / rate.
    var trainer := make_consumer("trainer0", GPU, 2.68e20, 1.0, 1.0, 1.84e16)
    trainer.material.required = 1.0e9
    trainer.material.production = 1.0e9
    trainer.goal.value = 2.68e20
    trainer.data.update()
    var reinforcer := make_consumer("reinforcer0", GPU, 7.36e19, 1.0, 1.0, 0.0)
    var text_generator := make_consumer("generator_text0", GPU, 5.886e8, 1.0, 1.0, 0.0)
    for consumer in [trainer, reinforcer, text_generator]:
        wire(out, consumer.speed)
    near(trainer.data.get_demand(), 2.68e20, "trainer count/s demand reproduces ~268 EHz")
    check(trainer.data.get_auto_demand() > trainer.data.get_demand() * 2.0, "Auto demand counts the trainer's text backlog")

    # Legacy policies on the same targets reproduce the limitation.
    for legacy in ["ratio", "graph"]:
        var state := {
            "wdata": {"trainer0": trainer.data, "reinforcer0": reinforcer.data, "generator_text0": text_generator.data},
            "demands": {"trainer0": trainer.data.get_demand(), "reinforcer0": reinforcer.data.get_demand(), "generator_text0": text_generator.data.get_demand()},
            "old_demands": {"trainer0": trainer.data.get_demand(), "reinforcer0": reinforcer.data.get_demand(), "generator_text0": text_generator.data.get_demand()},
            "consumers": ["trainer0", "reinforcer0", "generator_text0"],
            "managers": [],
            "storages": [],
            "storage_connections": 0,
            "line_suppliers": ["trainer0", "reinforcer0", "generator_text0"],
            "line_receivers": [],
        }
        if legacy == "ratio":
            Legacy.distribution_ratio(supply, state)
        else:
            Legacy.distribution_graph(supply, state)
        near(trainer.speed.count, 2.68e20, "legacy %s caps the trainer at its count/s demand (bug reproduced)" % legacy, 1e-6)
        check(trainer.speed.count < direct, "legacy %s gives less than the direct GPU Manager wire" % legacy)

    var input := hub_input(hub, GPU, supply)
    var channel := Channel.new(GPU, hub)
    channel.set_ports([{"uid": "gpu_in_1", "container": input}], [{"uid": "gpu_out_1", "container": out, "settings": Layout.default_settings()}])
    channel.tick(Channel.Mode.AUTO)
    check(trainer.speed.count >= direct, "BRM Auto gives the trainer at least the direct-wire 2.95 ZHz (%s)" % trainer.speed.count)
    near(channel.stats.allocated, supply, "BRM Auto distributes the whole 5.36 ZHz", 1e-9)
    check(reinforcer.speed.count >= 7.36e19 and text_generator.speed.count >= 5.886e8, "other AI machines keep their demand")

    # Every hub mode except Ratio/Graph-on-finite-only keeps the trainer fed.
    for mode in [Channel.Mode.DEMAND, Channel.Mode.PRIORITY]:
        channel.tick(mode)
        check(trainer.speed.count >= direct, "BRM mode %d also feeds the trainer beyond 2.95 ZHz" % mode)

    # Shortage: backlog-aware Auto gives the trainer more than its inflow share.
    input.count = 3.0e20
    for _i in range(5):
        channel.tick(Channel.Mode.AUTO)
    check(trainer.speed.count > 2.68e20 * 0.75, "shortage: trainer keeps most of the pool thanks to its backlog")
    near(channel.stats.allocated, 3.0e20, "shortage: pool fully used", 1e-9)
    check(reinforcer.speed.count > 0.0, "shortage: reinforcer is not starved")

    # Chained: GPU Manager -> BRM hub (as a manager target) keeps the demand.
    check(channel.get_finite_demand() >= trainer.data.get_auto_demand() * 0.9, "hub reports the trainer's real demand upstream")


# --- 17 determinism --------------------------------------------------------

func test_determinism() -> void:
    var requests: Array = []
    for index in range(30):
        requests.append({"key": "k%02d" % index, "demand": float((index * 37) % 11) * 1e18, "priority": index % 3, "weight": 1.0 + float(index % 4)})
    var shuffled := requests.duplicate(true)
    shuffled.reverse()
    for policy in POLICIES:
        var first := Allocator.allocate(1.234e20, requests, policy)
        var second := Allocator.allocate(1.234e20, requests, policy)
        var third := Allocator.allocate(1.234e20, shuffled, policy)
        check(first.allocations == second.allocations, "policy %d: same input, same result" % policy)
        check(first.allocations == third.allocations, "policy %d: request order does not matter" % policy)


# --- 18 diagnostics --------------------------------------------------------

func test_diagnostics() -> void:
    check(codes({"connected_inputs": 0, "targets": 0}).has(Diagnostics.NO_INPUT), "no input reported")
    check(codes({"connected_inputs": 0, "targets": 0}).has(Diagnostics.NO_OUTPUT), "no output reported")
    check(codes({"connected_inputs": 1, "supply": 0.0, "targets": 1, "finite_demand": 1.0}).has(Diagnostics.ZERO_SUPPLY), "zero supply reported")
    check(codes({"connected_inputs": 1, "supply": 10.0, "targets": 2, "finite_demand": 0.0}).has(Diagnostics.NO_DEMAND), "no demand reported")
    check(codes({"connected_inputs": 1, "supply": 10.0, "targets": 2, "finite_demand": 50.0, "shortage": true}).has(Diagnostics.SHORTAGE), "shortage reported")
    check(codes({"connected_inputs": 1, "supply": 10.0, "targets": 2, "finite_demand": 5.0, "unused": 5.0}).has(Diagnostics.UNUSED), "unused reported")
    check(codes({"cycles": 2}).has(Diagnostics.CYCLE), "loop reported")
    check(codes({"unregistered_ports": 1}).has(Diagnostics.PORT_UNREGISTERED), "unregistered port reported")
    check(Diagnostics.worst_severity(Diagnostics.evaluate({"cycles": 1})) == Diagnostics.Severity.ERROR, "loop is an error")


# --- 19 performance --------------------------------------------------------

func test_performance() -> void:
    var hub := make_window("hub_perf")
    var outputs: Array = []
    for port_index in range(10):
        var out := hub_output(hub, CPU)
        var settings := Layout.default_settings()
        settings.priority = port_index % 3
        outputs.append({"uid": "cpu_out_%d" % port_index, "container": out, "settings": settings})
        for index in range(10):
            var consumer := make_consumer("perf_%d_%d" % [port_index, index], CPU, 1e18 * (index + 1), 1.0, 1.0, 1e10)
            wire(out, consumer.speed)
    var inputs: Array = []
    for index in range(20):
        inputs.append({"uid": "cpu_in_%d" % index, "container": hub_input(hub, CPU, 1e19)})
    var channel := Channel.new(CPU, hub)
    channel.set_ports(inputs, outputs)
    channel.tick(Channel.Mode.AUTO)
    var started := Time.get_ticks_usec()
    var ticks := 300
    for _i in range(ticks):
        channel.tick(Channel.Mode.AUTO)
    var per_tick_ms := float(Time.get_ticks_usec() - started) / 1000.0 / float(ticks)
    print("BRM HUB PERF: 100 consumers, 10 outputs, 20 inputs, steady: %.3f ms per tick" % per_tick_ms)
    check(per_tick_ms < 5.0, "steady topology reuses the allocation (%.3f ms)" % per_tick_ms)
    near(channel.stats.allocated, 2e20, "large topology conserves supply", 1e-9)

    # Worst case: supply changes every tick, so everything is recomputed.
    var first_input: ResourceContainer = inputs[0].container
    started = Time.get_ticks_usec()
    for index in range(ticks):
        first_input.count = 1e19 + float(index) * 1e15
        channel.tick(Channel.Mode.AUTO)
    var changing_ms := float(Time.get_ticks_usec() - started) / 1000.0 / float(ticks)
    print("BRM HUB PERF: same topology, supply changing every tick: %.3f ms per tick" % changing_ms)
    check(changing_ms < 20.0, "full recomputation stays under a frame budget (%.3f ms)" % changing_ms)

    # The reuse path never hands out more than the current supply.
    first_input.count = 1e19
    channel.tick(Channel.Mode.AUTO)
    var before: float = channel.stats.allocated
    first_input.count = 1e19 * (1.0 - 1e-6)
    channel.tick(Channel.Mode.AUTO)
    check(channel.stats.allocated <= channel.stats.supply, "tiny supply drop is recomputed, never over-allocated")
    check(channel.stats.allocated < before, "allocation follows the smaller supply")


# --- helpers ------------------------------------------------------------------

func section(name: String, callable: Callable) -> void:
    current_section = name
    sections[name] = {"checks": 0, "failures": 0}
    callable.call()


func req(key: String, demand: float, weight: float = 1.0, priority: int = 0) -> Dictionary:
    return {"key": key, "demand": demand, "weight": weight, "priority": priority}


func codes(stats: Dictionary) -> Array:
    return Diagnostics.evaluate(stats).map(func(entry): return entry.code)


func uids(layout: Dictionary) -> Array:
    return layout.ports.map(func(port): return str(port.uid))


func next_id() -> String:
    _id_counter += 1
    return "%012x" % _id_counter


func make_window(name: String) -> WindowBase:
    var window := WindowBase.new()
    window.name = name
    window.add_to_group("window")
    fixtures.append(window)
    return window


func add_container(window: WindowBase, resource: String, type: int, is_input: bool, count: float = 0.0) -> ResourceContainer:
    var container := ResourceContainer.new()
    container.id = next_id()
    container.resource = resource
    container.type = type
    container.count = count
    if is_input:
        container.add_to_group("input")
    window.add_child(container)
    window.containers.append(container)
    return container


func hub_input(hub: WindowBase, resource: String, count: float) -> ResourceContainer:
    var container := add_container(hub, resource, 1, true, count)
    container.input_id = "upstream-" + container.id
    return container


func hub_output(hub: WindowBase, resource: String) -> ResourceContainer:
    return add_container(hub, resource, 1, false)


func wire(output: ResourceContainer, input: ResourceContainer) -> void:
    output.outputs.append(input)
    output.transfer.append(input)
    output.outputs_id.append(input.id)
    input.input = output
    input.input_id = output.id


# Modern 3.0 Process consumer whose count/s demand is
# production / required * goal / rate (= demand with the defaults below).
func make_consumer(name: String, resource: String, demand: float, rate: float, required: float, stock: float) -> Dictionary:
    var window := make_window(name)
    var speed := add_container(window, resource, 1, true)
    var material := add_container(window, "file", 0, true, stock)
    material.required = required
    material.production = required
    var process := WorkProcess.new()
    process.name = "Process"
    var goal := WorkGoal.new()
    goal.value = demand * rate
    var work_speed := WorkSpeed.new()
    work_speed.resource = speed
    work_speed.rate = rate
    process.add_child(goal)
    process.add_child(work_speed)
    process.goal_obj = goal
    process.speed_obj = work_speed
    process.resources.append(material)
    window.add_child(process)
    var data = WData.new(window)
    data.set_containers([speed.id])
    return {"window": window, "speed": speed, "material": material, "goal": goal, "work_speed": work_speed, "data": data, "data_demand": demand}


func near(actual: float, expected: float, label: String, tolerance: float = 1e-6) -> void:
    var scale := maxf(absf(expected), 1e-12)
    check(absf(actual - expected) <= scale * tolerance, "%s: expected %s, got %s" % [label, expected, actual])


func check(condition: bool, label: String) -> void:
    checks += 1
    sections[current_section].checks += 1
    if not condition:
        failures += 1
        sections[current_section].failures += 1
        push_error("[%s] %s" % [current_section, label])
