extends Node

## Web host (godot-bridge.js) and Godot scene boundary.
## The host supplies config.godotScene as "lobby" or "main" for each UI scene.

signal host_initialize(stage_data: Dictionary)
signal host_start
signal host_pause(reason: String)
signal host_resume
signal host_force_quit(reason: String)
signal host_message(topic: String, payload)

const HOST_SCENES := {
	"lobby": "res://scenes/lobby_scene.tscn",
	"main": "res://scenes/main_scene.tscn",
}

var is_hosted := false
var auto_pause := true
var standalone_autostart := true
var standalone_stage := {"stage": 1, "seed": 0, "config": {"godotScene": "lobby"}}

var _iface = null
var _cb = null
var _host_scene_loading := false
var _start_after_scene_ready := false
var _host_scene_cache := {}
var _host_scene_instances := {}
var _active_host_scene: Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.has_feature("web") and JavaScriptBridge.eval("typeof window.UiBridge !== 'undefined'"):
		_iface = JavaScriptBridge.get_interface("UiBridge")
	if _iface != null:
		is_hosted = true
		_cb = JavaScriptBridge.create_callback(_on_command)
		_iface.setHandler(_cb)
		_iface.ready()
	elif standalone_autostart:
		_standalone_boot.call_deferred()


func _standalone_boot() -> void:
	await get_tree().process_frame
	emit_signal("host_initialize", standalone_stage)
	emit_signal("host_start")


func _on_command(args: Array) -> void:
	var message = JSON.parse_string(str(args[0]))
	if message == null or typeof(message) != TYPE_DICTIONARY:
		push_warning("[UiBridge] Command parse failed: %s" % [args])
		return
	var payload: Dictionary = message.get("payload", {})
	match message.get("cmd", ""):
		"initialize":
			_initialize_host_scene(payload)
		"startGame":
			if _host_scene_loading:
				_start_after_scene_ready = true
			else:
				emit_signal("host_start")
		"pauseGame":
			if auto_pause:
				get_tree().paused = true
			emit_signal("host_pause", str(payload.get("reason", "")))
		"resumeGame":
			if auto_pause:
				get_tree().paused = false
			if _host_scene_loading:
				_start_after_scene_ready = true
			else:
				emit_signal("host_resume")
		"forceQuit":
			_start_after_scene_ready = false
			emit_signal("host_force_quit", str(payload.get("reason", "")))
		"message":
			var topic := str(payload.get("topic", ""))
			if topic == "load_scene":
				var scene_data: Dictionary = payload.get("payload", {})
				_initialize_host_scene(scene_data)
			else:
				emit_signal("host_message", topic, payload.get("payload"))
		_:
			push_warning("[UiBridge] Unknown command: %s" % [message.get("cmd", "")])


func _initialize_host_scene(stage_data: Dictionary) -> void:
	_host_scene_loading = true
	var config: Dictionary = stage_data.get("config", {})
	var scene_key := str(config.get("godotScene", ""))
	var scene_path: String = HOST_SCENES.get(scene_key, "")
	if scene_path.is_empty():
		_host_scene_loading = false
		post_error("Unknown host scene: %s" % scene_key)
		return
	var preload_scenes: Array = config.get("preloadGodotScenes", [])
	for preload_key in preload_scenes:
		var preload_path: String = HOST_SCENES.get(str(preload_key), "")
		if preload_path.is_empty():
			_host_scene_loading = false
			post_error("Unknown preload scene: %s" % preload_key)
			return
		if not _host_scene_cache.has(preload_path):
			var preload_scene := ResourceLoader.load(preload_path) as PackedScene
			if preload_scene == null:
				_host_scene_loading = false
				post_error("Could not preload host scene: %s" % preload_path)
				return
			_host_scene_cache[preload_path] = preload_scene
	var scene := _host_scene_instances.get(scene_path) as Node
	if scene == null:
		var packed_scene := _host_scene_cache.get(scene_path) as PackedScene
		if packed_scene == null:
			packed_scene = ResourceLoader.load(scene_path) as PackedScene
			if packed_scene == null:
				_host_scene_loading = false
				post_error("Could not load host scene: %s" % scene_path)
				return
			_host_scene_cache[scene_path] = packed_scene
		scene = packed_scene.instantiate()
		_host_scene_instances[scene_path] = scene
	if scene != _active_host_scene:
		if _active_host_scene != null:
			_active_host_scene.process_mode = Node.PROCESS_MODE_DISABLED
			var previous_scene := _active_host_scene as Node3D
			if previous_scene != null:
				previous_scene.hide()
		if scene.get_parent() != self:
			scene.process_mode = Node.PROCESS_MODE_DISABLED
			var scene_3d := scene as Node3D
			if scene_3d != null:
				scene_3d.hide()
			add_child(scene)
		scene.process_mode = Node.PROCESS_MODE_INHERIT
		var active_scene := scene as Node3D
		if active_scene != null:
			active_scene.show()
			var camera := active_scene.get_node_or_null("Camera3D") as Camera3D
			if camera != null:
				camera.make_current()
		_active_host_scene = scene
		await get_tree().process_frame
	emit_signal("host_initialize", stage_data)
	_host_scene_loading = false
	notify_initialized()
	await get_tree().process_frame
	post_progress({"sceneReady": scene_key})
	if _start_after_scene_ready:
		_start_after_scene_ready = false
		emit_signal("host_start")


func notify_initialized() -> void:
	_post("initialized", {})


func post_hud(fields: Dictionary) -> void:
	_post("hud", fields)


func post_progress(data: Dictionary) -> void:
	_post("progress", data)


func post_end(outcome: String, score: int, stats: Dictionary = {}) -> void:
	_post("end", {"outcome": outcome, "score": score, "stats": stats})


func post_error(message: String) -> void:
	_post("error", {"message": message})


func _post(type: String, payload: Dictionary) -> void:
	if _iface == null:
		return
	_iface.post(type, JSON.stringify(payload))
