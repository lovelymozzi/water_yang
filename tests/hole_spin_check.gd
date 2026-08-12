extends SceneTree

const HOLE_SCENE := preload("res://scenes/cat_hole.tscn")
const HOLE_SHADER := preload("res://scripts/hole_spin.gdshader")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var hole := HOLE_SCENE.instantiate() as Node3D
	root.add_child(hole)
	hole.call("apply_hole_colors", Color.WHITE, Color.BLACK)
	await process_frame

	var animation_player := hole.get_node_or_null("AnimationPlayer") as AnimationPlayer
	_expect(animation_player != null, "CatHole AnimationPlayer가 없다")
	if animation_player != null:
		_expect(animation_player.is_playing(), "spin 애니메이션이 자동 재생되지 않는다")
		animation_player.advance(1.0)
		_expect(is_equal_approx(hole.rotation.y, PI * 0.5), "1초 후 모델의 Y 회전값이 90도가 아니다")

	var pit_material := _find_pit_material(hole)
	_expect(pit_material != null, "hole 표면에 ShaderMaterial이 적용되지 않았다")
	if pit_material != null:
		_expect(pit_material.shader == HOLE_SHADER, "hole 표면에 회전 셰이더가 연결되지 않았다")
		_expect(
			is_equal_approx(float(pit_material.get_shader_parameter("rotation_duration")), 4.0),
			"UV 회전 주기가 4초가 아니다"
		)

	hole.queue_free()
	if _failures.is_empty():
		print("HOLE SPIN CHECK: PASS")
		quit(0)
	else:
		print("HOLE SPIN CHECK: FAIL\n%s" % "\n".join(_failures))
		quit(1)


func _find_pit_material(node: Node) -> ShaderMaterial:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			for surface_index in mesh_instance.mesh.get_surface_count():
				var material := mesh_instance.get_surface_override_material(surface_index) as ShaderMaterial
				if material != null and material.shader == HOLE_SHADER:
					return material
	for child in node.get_children():
		var found := _find_pit_material(child)
		if found != null:
			return found
	return null


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
