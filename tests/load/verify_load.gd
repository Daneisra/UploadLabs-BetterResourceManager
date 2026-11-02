extends SceneTree

# Loads every BRM script and scene in Godot with test doubles of the game's
# classes, autoloads and base scenes, then exercises what can be exercised
# without Upload Labs: registration, legacy scene aliases in Godot's real
# resource cache, and the hub's set-on-load / save / reload cycle.
# This is a load and contract test, not proof of in-game behaviour.

const MOD_ROOT := "res://mods-unpacked/Daneisra-BetterResourceManager"
const KUUK_STM := "res://mods-unpacked/kuuk-SmartThreadManager/scenes/windows/window_smart_thread_manager.tscn"
const KUUK_SGM := "res://mods-unpacked/kuuk-SmartGPUManager/scenes/windows/window_smart_gpu_manager.tscn"
const ASM_STM := "res://mods-unpacked/guardipee14-AdaptiveSmartManager/scenes/windows/window_smart_thread_manager.tscn"

var checks := 0
var failures := 0


func _init() -> void:
    call_deferred("run")


func run() -> void:
    await process_frame
    test_every_script_loads()
    test_scenes_instantiate()
    await test_registration_and_aliases()
    await test_hub_save_reload()
    await test_legacy_manager_save()
    for node in root.get_children():
        if node.has_meta("keep") and node.legacy_aliases != null:
            node.legacy_aliases.release()
            node.queue_free()
    await process_frame
    print("BRM LOAD: %d checks, %d failures" % [checks, failures])
    quit(0 if failures == 0 else 1)


func test_every_script_loads() -> void:
    var scripts: Array[String] = []
    _collect(MOD_ROOT, ".gd", scripts)
    check(scripts.size() >= 20, "all mod scripts found (%d)" % scripts.size())
    for path in scripts:
        var script = load(path)
        check(script is Script, "script parses: %s" % path)
        if script is Script:
            check(script.can_instantiate(), "script can instantiate: %s" % path)


func test_scenes_instantiate() -> void:
    var scenes: Array[String] = []
    _collect(MOD_ROOT, ".tscn", scenes)
    check(scenes.size() == 5, "five scenes found (%d)" % scenes.size())
    for path in scenes:
        var scene = load(path)
        check(scene is PackedScene, "scene loads: %s" % path)
        if scene is PackedScene:
            var node: Node = scene.instantiate()
            check(node != null, "scene instantiates: %s" % path)
            if node != null:
                node.free()

    for file in ["window_smart_thread_manager.tscn", "window_smart_gpu_manager.tscn"]:
        var manager: Node = load(MOD_ROOT + "/scenes/windows/" + file).instantiate()
        # Save keys of the kuuk / ASM managers ("container_data" paths).
        check(manager.get_node_or_null("PanelContainer/MainContainer/Input") is ResourceContainer, "%s keeps PanelContainer/MainContainer/Input" % file)
        check(manager.get_node_or_null("PanelContainer/MainContainer/Output") is ResourceContainer, "%s keeps PanelContainer/MainContainer/Output" % file)
        check(manager.get_node("OptionButton").item_count == 4, "%s offers Ratio/Demand/Graph/Auto" % file)
        check(manager.get_node("OptionButton").get_item_id(3) == 3, "%s Auto option id is 3" % file)
        manager.free()


func test_registration_and_aliases() -> void:
    var main_script: GDScript = load(MOD_ROOT + "/mod_main.gd")
    var mod: Node = main_script.new()
    root.add_child(mod)
    await process_frame
    for id in ["smart_thread_manager", "smart_gpu_manager", "better_resource_hub"]:
        check(autoload("Data").windows.has(id), "registered window %s" % id)
        check(autoload("Attributes").window_attributes.has(id), "attributes for %s" % id)
    check(autoload("Data").windows.better_resource_hub.requirement == ["research.thread_manager"], "hub follows Thread Manager unlock")
    check(autoload("Data").guides.has("window_better_resource_hub"), "hub guide registered")
    check(ModLoaderMod.translations.size() == 2, "en + fr translations registered (%d)" % ModLoaderMod.translations.size())
    check(mod.legacy_aliases != null and mod.legacy_aliases.failed.is_empty(), "every legacy alias verified")
    check(mod.legacy_aliases != null and mod.legacy_aliases.installed.size() == 4, "four legacy aliases installed")

    for alias in [KUUK_STM, KUUK_SGM, ASM_STM]:
        # Exactly how a save names the scene: res://scenes/windows/ + filename.
        var saved_filename: String = "../../" + str(alias).trim_prefix("res://")
        var scene = load("res://scenes/windows/" + saved_filename)
        check(scene is PackedScene, "legacy save filename resolves: %s" % saved_filename)
        if scene is PackedScene:
            var window: Node = scene.instantiate()
            check(window.get_script().resource_path.begins_with(MOD_ROOT), "legacy path instantiates the BRM manager")
            check(window.scene_file_path == alias, "instance remembers the legacy path it came from")
            window.free()
    check(ResourceLoader.exists(KUUK_STM), "ResourceLoader.exists() sees the alias")

    # A second registration must not overwrite anything.
    var duplicate: Node = main_script.new()
    root.add_child(duplicate)
    await process_frame
    var refused := ModLoaderLog.lines.filter(func(line: String): return line.contains("already exists"))
    check(refused.size() >= 3, "existing registrations are never overwritten")
    check(duplicate.legacy_aliases == null, "no alias takeover when BRM does not own the legacy ids")
    duplicate.queue_free()
    mod.set_meta("keep", true)


func test_hub_save_reload() -> void:
    var hub_scene: PackedScene = load(MOD_ROOT + "/scenes/windows/window_better_resource_hub.tscn")

    # New hub from Add Node: one port of each kind.
    var hub: Node = hub_scene.instantiate()
    root.add_child(hub)
    await process_frame
    await process_frame
    for path in ["Cpu/Inputs/cpu_in_1/Port", "Cpu/Outputs/cpu_out_1/Port", "Gpu/Inputs/gpu_in_1/Port", "Gpu/Outputs/gpu_out_1/Port"]:
        check(hub.get_node_or_null("PanelContainer/MainContainer/" + path) is ResourceContainer, "default port at %s" % path)
    check(hub.containers.size() == 4, "default ports are window containers (%d)" % hub.containers.size())
    var cpu_port = hub.get_node("PanelContainer/MainContainer/Cpu/Inputs/cpu_in_1/Port")
    check(cpu_port.resource == "clock_speed", "CPU port forced to clock_speed")
    check(hub.get_node("PanelContainer/MainContainer/Gpu/Outputs/gpu_out_1/Port").resource == "gpu_speed", "GPU port forced to gpu_speed")
    check(hub.get_node("PanelContainer/MainContainer/Cpu/Outputs/cpu_out_1/Port").get_script().resource_path.ends_with("brm_output_port.gd"), "output port uses the hub output script")

    # Runtime add / remove.
    var uid: String = hub.add_port(1)
    check(uid == "cpu_out_2", "runtime port added (%s)" % uid)
    var added = hub.get_node_or_null("PanelContainer/MainContainer/Cpu/Outputs/cpu_out_2/Port")
    check(added is ResourceContainer and hub.containers.has(added), "runtime port joins window containers")
    added.outputs_id.append("connected-target")
    check(not hub.remove_port("cpu_out_2"), "connected port cannot be removed")
    added.outputs_id.clear()
    check(hub.remove_port("cpu_out_2"), "disconnected port removed")
    await process_frame
    check(hub.get_node_or_null("PanelContainer/MainContainer/Cpu/Outputs/cpu_out_2") == null, "removed port node is gone")
    check(hub.containers.size() == 4, "removed port left window containers")
    hub.add_port(3)
    hub.add_port(3)
    hub.remove_port("gpu_out_2")
    hub.brm_mode = 3
    var gpu_out_3 = hub.get_node("PanelContainer/MainContainer/Gpu/Outputs/gpu_out_3/Port")
    gpu_out_3.outputs_id.append("trainer-speed-id")

    var saved: Dictionary = hub.save()
    check(saved.has("brm_layout") and saved.has("brm_port_state") and saved.has("brm_mode"), "hub save contains its layout, port state and mode")
    check(str(saved.filename).ends_with("Daneisra-BetterResourceManager/scenes/windows/window_better_resource_hub.tscn"), "hub save filename points at the BRM scene")
    check(saved.container_data.has("PanelContainer/MainContainer/Gpu/Outputs/gpu_out_3/Port"), "container data keyed by stable port path")
    check(not hub.export().has("brm_port_state"), "export (copy/paste) carries no container ids")

    # Reload exactly like the game: instantiate, set saved keys before _ready
    # (in the sorted order a ConfigFile gives back), then enter the tree.
    var text := var_to_str(saved)
    var record: Dictionary = str_to_var(text)
    var reloaded: Node = hub_scene.instantiate()
    var keys := record.keys()
    keys.sort()
    for key in keys:
        if key in ["container_data", "filename", "name"]:
            continue
        reloaded.set(key, record[key])
    for path in record.container_data.keys():
        check(reloaded.get_node_or_null(NodePath(path)) is ResourceContainer, "port exists before _ready: %s" % path)
    root.add_child(reloaded)
    await process_frame
    await process_frame
    var restored_ids: Dictionary = reloaded.brm_port_state
    for port_uid in saved.brm_port_state.keys():
        check(restored_ids.has(port_uid) and restored_ids[port_uid].id == saved.brm_port_state[port_uid].id, "container id survives reload: %s" % port_uid)
    check(Array(reloaded.get_node("PanelContainer/MainContainer/Gpu/Outputs/gpu_out_3/Port").outputs_id) == ["trainer-speed-id"], "output connections survive reload")
    check(reloaded.brm_mode == 3, "mode survives reload")
    check(reloaded.containers.size() == hub.containers.size(), "no default ports added on top of a saved layout")
    check(reloaded.add_port(3) == "gpu_out_4", "uid counter survives reload")

    # Runtime paths: ticks, UI refresh and every UI action, in every mode.
    var cpu_in = reloaded.get_node("PanelContainer/MainContainer/Cpu/Inputs/cpu_in_1/Port")
    cpu_in.count = 1000.0
    cpu_in.input_id = "upstream"
    for mode in range(5):
        reloaded._on_mode_selected(reloaded.mode_button.get_item_index(mode))
        check(reloaded.brm_mode == mode, "mode %d selectable" % mode)
        for _i in range(8):
            reloaded.tick(0.05)
        reloaded._refresh_ui()
    near(reloaded.get_channel("clock_speed").stats.supply, 1000.0, "hub tick reads its CPU input")
    check(reloaded.get_resource_demand("gpu_speed") == 0.0, "GPU demand separate from CPU")
    reloaded._toggle_settings("cpu_out_1")
    reloaded._step_setting("cpu_out_1", "priority", 2)
    reloaded._flip_setting("cpu_out_1", "enabled")
    reloaded._flip_setting("cpu_out_1", "manual")
    reloaded._commit_number("cpu_out_1", "max", "2.5Z")
    reloaded._commit_number("cpu_out_1", "min", "1e3")
    reloaded._commit_number("cpu_out_1", "weight", "not a number")
    var settings: Dictionary = reloaded.brm_layout.ports.filter(func(port): return port.uid == "cpu_out_1")[0].settings
    check(int(settings.priority) == 2 and not settings.enabled and settings.manual, "settings buttons update the layout")
    near(float(settings.max), 2.5e21, "max parsed from 2.5Z")
    near(float(settings.min), 1000.0, "min parsed from 1e3")
    near(float(settings.weight), 1.0, "invalid weight ignored")
    reloaded._on_label_committed("cpu_out_1", "AI Trainer")
    check(reloaded.brm_layout.ports[1].label == "AI Trainer", "port name stored")
    var compact_button = reloaded.get_node("PanelContainer/MainContainer/Toolbar/CompactButton")
    compact_button.button_pressed = true
    check(reloaded.brm_compact, "compact view toggles")
    reloaded.tick(0.05)
    reloaded._refresh_ui()
    var status: Label = reloaded.get_node("PanelContainer/MainContainer/Cpu/Status")
    check(not status.text.is_empty(), "status line filled")
    reloaded._on_mode_selected(reloaded.mode_button.get_item_index(4))
    root.remove_child(reloaded)
    check(reloaded._graph == null, "Graph mode resources released when the hub leaves the tree")
    root.add_child(reloaded)
    reloaded.tick(0.05)

    for node in [hub, reloaded]:
        node.queue_free()
    await process_frame


func test_legacy_manager_save() -> void:
    var alias_scene: PackedScene = load(KUUK_SGM)
    var manager: Node = alias_scene.instantiate()
    manager.set("container_mode", 1)
    manager.set("brm_auto_mode", true)
    root.add_child(manager)
    await process_frame
    var saved: Dictionary = manager.save()
    check(saved.filename == "../../mods-unpacked/kuuk-SmartGPUManager/scenes/windows/window_smart_gpu_manager.tscn", "manager loaded from a kuuk path keeps saving that path")
    check(saved.container_mode == 1, "container_mode stays a value kuuk understands")
    check(saved.brm_auto_mode == true, "Auto stored separately")
    var output = manager.get_node("PanelContainer/MainContainer/Output")
    check(output.distribution_mode == 3, "Auto drives the smart container")
    manager.queue_free()

    var fresh: Node = load(MOD_ROOT + "/scenes/windows/window_smart_thread_manager.tscn").instantiate()
    root.add_child(fresh)
    await process_frame
    check(str(fresh.save().filename).ends_with("Daneisra-BetterResourceManager/scenes/windows/window_smart_thread_manager.tscn"), "new manager saves the BRM path")
    fresh.queue_free()
    await process_frame


# Autoload names are not compile-time identifiers in a --script entry point.
func autoload(singleton: String) -> Node:
    return root.get_node("/root/" + singleton)


func _collect(directory: String, extension: String, result: Array[String]) -> void:
    for file in DirAccess.get_files_at(directory):
        if file.ends_with(extension):
            result.append(directory.path_join(file))
    for sub in DirAccess.get_directories_at(directory):
        _collect(directory.path_join(sub), extension, result)


func near(actual: float, expected: float, label: String) -> void:
    check(absf(actual - expected) <= maxf(absf(expected), 1e-12) * 1e-9, "%s: expected %s, got %s" % [label, expected, actual])


func check(condition: bool, label: String) -> void:
    checks += 1
    if not condition:
        failures += 1
        push_error(label)
