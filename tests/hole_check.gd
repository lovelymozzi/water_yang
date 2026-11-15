extends Node

# 구멍 흡입 회귀 검사. 렌더가 없으므로 기하 수치로만 본다.
#   Godot 4.7.2 --headless --path . tests/hole_check.tscn

var _scene: Node
var _frames := 0
var _failures: Array[String] = []


func _ready() -> void:
	UiBridge.standalone_autostart = false
	_scene = (load("res://scenes/main_scene.tscn") as PackedScene).instantiate()
	_scene.set_script(null)
	add_child(_scene)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames < 10:
		return
	set_process(false)
	var manager: LevelManager = _scene.get_node("LevelManager")
	if "--absorb-capture" in OS.get_cmdline_user_args():
		var layout := LevelLayoutWriter.load_json("res://resources/levels/stage_001.json")
		LevelLayoutWriter.apply_to_manager(manager, layout)
		for fixture_cat in manager.get_node("LayoutCats").get_children():
			fixture_cat.set_process(false)
		await get_tree().process_frame
		for step: Dictionary in layout["solution"].slice(0, 9):
			var moving_cat := manager.get_node("LayoutCats/Cat_%d" % int(step["cat_id"])) as CatEntity
			moving_cat.request_path_to(Vector2i(int(step["to_cell"][0]), int(step["to_cell"][1])))
			moving_cat.advance(1.05 / moving_cat.move_speed_cells)
		var fixture_cat := manager.get_node("LayoutCats/Cat_0") as CatEntity
		_expect(fixture_cat.is_absorbing(), "1레벨 실제 이동 경로에서 흡입이 시작되지 않았다")
		_expect(fixture_cat.get_node_or_null("AbsorbLevelUp") == null, "제거한 흡입 이펙트가 생성됐다")
		for overlay in ["IceDissolveMesh", "IceDissolveSnowTop", "IceDissolveSnowBottom"]:
			_scene.get_node("Camera3D/" + overlay).hide()
		for sample_index in 13:
			if sample_index > 0 and is_instance_valid(fixture_cat) and fixture_cat.is_absorbing():
				fixture_cat.advance(0.05)
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("/tmp/water-yang-absorb-only-%02d.png" % sample_index)
		_report()
		get_tree().quit(0 if _failures.is_empty() else 1)
		return
	_check_layout(manager)
	_check_runtime_outline_sync(manager)
	for check in [
		_check_not_a_path, _check_no_trigger_when_far, _check_lead_absorb,
		_check_rear_does_not_absorb, _check_color_pair, _check_clears_level,
	]:
		# 완료된 흡입은 구멍도 닫는다. 각 검사는 같은 초기 배치에서 독립적으로 시작한다.
		for cell in manager.get_hole_cells():
			manager._set_cell_state(cell, LevelManager.CellState.EMPTY)
		manager._hole_cells.clear()
		manager._hole_color_ids.clear()
		manager._hole_ice_counts.clear()
		for visual in manager.get_node("HoleVisuals").get_children():
			visual.get_parent().remove_child(visual)
			visual.queue_free()
		manager._sync_hole_layout()
		manager._build_hole_visuals()
		await check.call(manager)
	set_process(false)
	var closing_effects := []
	for portal in manager.get_node("HoleVisuals").find_children("PortalFX_*", "Node3D", false, false):
		if not portal.get_node("Twinkles").emitting:
			closing_effects.append(portal)
	_expect(not closing_effects.is_empty(), "차원문 이펙트의 종료 검사가 실행되지 않았다")
	await get_tree().create_timer(0.3).timeout
	await get_tree().process_frame
	for portal in closing_effects:
		_expect(not is_instance_valid(portal), "닫힌 차원문의 이펙트가 남아 있다")
	LevelLayoutWriter.apply_to_manager(manager, LevelLayoutWriter.load_json("res://resources/levels/stage_008.json"))
	await get_tree().process_frame
	var locked := 0
	var unlock_count := 0
	for cell in manager.get_hole_cells():
		var portal := manager.get_node("HoleVisuals/PortalFX_%d_%d" % [cell.x, cell.y]) as Node3D
		_expect(portal.visible == not manager.is_hole_locked(cell), "얼음 잠금과 차원문 빛 표시가 다르다")
		for emitter: CPUParticles3D in portal.get_children():
			_expect(emitter.emitting == portal.visible, "잠긴 차원문에서 입자가 생성된다")
		if manager.is_hole_locked(cell):
			locked += 1
	for entry: Dictionary in manager._ice_covers.values():
		unlock_count = maxi(unlock_count, int(entry["count"]))
	_expect(locked > 0, "얼음 아래 차원문 이펙트 검사가 실행되지 않았다")
	manager._escaped_count = unlock_count
	manager._refresh_ice_covers()
	for cell in manager.get_hole_cells():
		var portal := manager.get_node("HoleVisuals/PortalFX_%d_%d" % [cell.x, cell.y]) as Node3D
		_expect(portal.visible, "얼음 해제 후 차원문의 빛이 켜지지 않았다")
		for emitter: CPUParticles3D in portal.get_children():
			_expect(emitter.emitting, "얼음 해제 후 입자가 생성되지 않는다")
	print("[차원문 FX] 원본 리소스 설정·짝 색·상승·깊이 가림·종료 정리·얼음 해제 검사")
	_report()
	await get_tree().process_frame
	_scene.queue_free()
	await get_tree().process_frame
	# 동기 수치 루프에서 재생한 사운드의 오디오 스레드 해제를 기다린다.
	await get_tree().create_timer(0.1).timeout
	get_tree().quit(0 if _failures.is_empty() else 1)


# 씬에 놓인 구멍이 정확히 한 칸이고, 바닥 타일 위에 표시된다.
func _check_layout(manager: LevelManager) -> void:
	var holes: Array[Vector2i] = manager.get_hole_cells()
	_expect(not holes.is_empty(), "씬에 구멍이 하나도 없다")
	if holes.is_empty():
		return
	var hole: Vector2i = holes[0]
	_expect(manager.is_hole(hole), "구멍 칸이 is_hole() 로 조회되지 않는다: %s" % [hole])
	_expect(
		manager.get_node("TileVisuals").get_node_or_null("Tile_%d_%d" % [hole.x, hole.y]) != null,
		"구멍 칸에 바닥 타일이 없다: %s" % [hole]
	)
	var hole_visual := manager.get_node("HoleVisuals").get_node_or_null("CatHole_%d_%d" % [hole.x, hole.y]) as Node3D
	_expect(
		hole_visual != null,
		"구멍 비주얼이 만들어지지 않았다: %s" % [hole]
	)
	if hole_visual != null:
		_expect(
			is_equal_approx(hole_visual.position.y, manager.floor_tile_height + manager.hole_visual_height),
			"구멍 비주얼이 바닥 타일 위에 놓이지 않았다: %s" % [hole]
		)
	var portal := manager.get_node_or_null("HoleVisuals/PortalFX_%d_%d" % [hole.x, hole.y]) as Node3D
	_expect(portal != null, "차원문 빛/반짝임이 만들어지지 않았다")
	if portal != null:
		_expect(portal.get_parent() == hole_visual.get_parent(), "차원문 이펙트가 꽃 회전을 상속한다")
		# Twinkles include their largest billboard's bounding sphere in XZ:
		# zero lateral motion then keeps the entire rising sprite over the aperture.
		# Sharing the hole node's origin is insufficient: its pit is higher.
		var tested_origins := 0
		for emitter: CPUParticles3D in portal.get_children():
			var material := emitter.mesh.material as StandardMaterial3D
			if emitter.name != "ApertureGlow":
				# Godot uses BOX=3; 2 is SPHERE_SURFACE and ignores box extents.
				_expect(emitter.emission_shape == CPUParticles3D.EMISSION_SHAPE_BOX,
					"%s의 실제 발생 형태가 박스가 아니어서 지정한 범위가 적용되지 않는다" % emitter.name)
				_expect(is_zero_approx(emitter.emission_box_extents.y)
					and Vector2(emitter.emission_box_extents.x, emitter.emission_box_extents.z).length() < 0.05,
					"%s의 발생점이 중앙 회오리 안쪽에 모여 있지 않다" % emitter.name)
			var bounds := emitter.emission_box_extents
			if emitter.name == "Twinkles":
				var quad := emitter.mesh as QuadMesh
				var max_curve_scale := 0.0
				for sample in 1001:
					max_curve_scale = maxf(max_curve_scale, emitter.scale_amount_curve.sample(float(sample) / 1000.0))
				var sprite_radius := quad.size.length() * 0.5 * emitter.scale_amount_max * max_curve_scale
				bounds += Vector3(sprite_radius, 0, sprite_radius)
				_expect(is_zero_approx(emitter.spread), "반짝임이 상승 중 차원문 밖으로 퍼진다")
				_expect(quad.size.x > 0.25 and quad.size.y > 0.25, "차원문 반짝임 크기가 작아졌다")
				var horizontal_radius := Vector2(emitter.emission_box_extents.x, emitter.emission_box_extents.z).length() + sprite_radius
				_expect(horizontal_radius < 0.25, "최대 크기 반짝임이 중앙 회오리의 안쪽 절반 반경을 넘는다")
				print("[입자 반경] 발생점+최대 크기의 XZ 반경 상한 %.3f / 입구 반경 0.5" %
					horizontal_radius)
			for x in [-1.0, 1.0]:
				for z in [-1.0, 1.0]:
					var origin := emitter.to_global(Vector3(x * bounds.x, 0, z * bounds.z))
					if emitter.emission_shape == CPUParticles3D.EMISSION_SHAPE_POINT:
						origin = emitter.global_position
					var hit_aperture := false
					for mesh: MeshInstance3D in hole_visual.find_children("*", "MeshInstance3D", true, false):
						for surface in mesh.mesh.get_surface_count():
							if mesh.mesh.surface_get_material(surface).resource_name.to_lower() != "hole":
								continue
							var arrays := mesh.mesh.surface_get_arrays(surface)
							var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
							var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
							for triangle in range(0, indices.size(), 3):
								var hit: Variant = Geometry3D.ray_intersects_triangle(origin + Vector3.UP, Vector3.DOWN,
									mesh.to_global(vertices[indices[triangle]]), mesh.to_global(vertices[indices[triangle + 1]]), mesh.to_global(vertices[indices[triangle + 2]]))
								if hit is Vector3 and absf(origin.y - hit.y - portal.scale.x * 0.005) < 0.0001:
									hit_aperture = true
					_expect(hit_aperture, "차원문 이펙트의 발생/반짝임 최대 크기 범위가 실제 구멍 표면을 벗어난다")
					tested_origins += 1
			_expect(emitter.color.is_equal_approx(manager.get_hole_rim_color(manager.get_hole_color_id(hole)).lerp(Color.WHITE, 0.55)),
				"차원문 이펙트의 짝 색이 다르다")
			_expect(emitter.local_coords and emitter.direction.is_equal_approx(Vector3.UP)
				and emitter.gravity.is_zero_approx(), "차원문 이펙트 좌표계/방향이 다르다")
			if emitter.name == "Twinkles":
				_expect(emitter.initial_velocity_min > 0.0, "반짝임이 입구에서 위로 올라가지 않는다")
				var camera := _scene.get_node("Camera3D") as Camera3D
				var shortest_life := emitter.lifetime * (1.0 - emitter.lifetime_randomness)
				var start := emitter.to_global(Vector3.UP * emitter.initial_velocity_min * shortest_life * 0.15)
				var end := emitter.to_global(Vector3.UP * emitter.initial_velocity_min * shortest_life * 0.82)
				var rise := camera.unproject_position(start).y - camera.unproject_position(end).y
				_expect(rise > get_viewport().get_visible_rect().size.y * 0.008,
					"반짝임의 보이는 구간에서 화면상 상승량이 너무 작다: %.2fpx" % rise)
				_expect(emitter.emitting and emitter.can_process(), "반짝임 재생이 중지되어 있다")
				print("[입자 상승 투영] 최소 속도/수명 기준 보이는 구간 %.2fpx" % rise)
			else:
				_expect(is_zero_approx(emitter.initial_velocity_max), "차원문에 고정된 빛이 이동한다")
			if emitter.name == "RisingLight":
				var shaft := emitter.mesh as QuadMesh
				_expect(is_zero_approx(shaft.center_offset.y - shaft.size.y * 0.5), "빛줄기 밑부분이 차원문에 고정되지 않았다")
			_expect(emitter.amount <= 12 and emitter.process_mode == Node.PROCESS_MODE_INHERIT, "입자 수나 일시정지 설정이 다르다")
			_expect(not material.no_depth_test and material.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED,
				"차원문 빛이 고양이를 뚫거나 투명 영역이 깊이를 쓴다")
			_expect(is_zero_approx(emitter.color_ramp.sample(0.0).a) and is_zero_approx(emitter.color_ramp.sample(1.0).a),
				"차원문 빛/입자가 갑자기 켜지거나 꺼진다")
		print("[차원문 타겟] 실제 구멍 표면 위 발생점 %d개, 빛줄기 하단 고정" % tested_origins)
	# 인접 조회는 4방향만이다. 대각선은 걸리지 않는다.
	_expect(manager.adjacent_hole(hole + Vector2i.LEFT) == hole, "옆칸에서 구멍을 못 찾았다")
	_expect(manager.adjacent_hole(hole + Vector2i(1, 1)) == null, "대각선이 인접으로 걸렸다")
	print("[구멍] %s 한 칸, 타일 위 배치, 4방향 인접만 걸림" % [hole])


# 구멍은 경로로 쓰이지 않는다. 브릿지가 구멍을 지나가면 인접 판정 전에 밟게 된다.
func _check_runtime_outline_sync(manager: LevelManager) -> void:
	var cat := manager.get_node_or_null("LayoutCats/Cat_C0") as CatEntity
	var hole := manager.get_node_or_null("HoleVisuals/CatHole_0_0")
	_expect(cat != null and hole != null, "Runtime outline sync test nodes are missing")
	if cat == null or hole == null:
		return
	var expected := 0.031
	var expected_brightness := 1.42
	cat.outline_width = 0.011
	cat.cat_hole_outline_width = expected
	cat.outline_brightness = expected_brightness
	# Property setters defer material application; invoke the same live update
	# path once so this test covers the non-editor (runtime) branch.
	cat.call("_apply_current_shader_parameters")
	var expected_outline_color: Color = manager.get_pair_color(cat.color_id).darkened(0.27)
	expected_outline_color = Color(
		minf(expected_outline_color.r * expected_brightness, 1.0),
		minf(expected_outline_color.g * expected_brightness, 1.0),
		minf(expected_outline_color.b * expected_brightness, 1.0),
		cat.outline_color.a
	)
	var hole_style: Dictionary = hole.get("_cat_visual_style")
	var hole_outline_color: Color = hole_style["outline_color"] if hole_style.get("outline_color") is Color else Color()
	_expect(
		is_equal_approx(float(hole.call("get_applied_outline_width")), expected),
		"Runtime CatHole outline width was not copied independently from the matching CatEntity"
	)
	_expect(
		hole_style.get("outline_color") is Color
		and is_equal_approx(hole_outline_color.r, expected_outline_color.r)
		and is_equal_approx(hole_outline_color.g, expected_outline_color.g)
		and is_equal_approx(hole_outline_color.b, expected_outline_color.b)
		and is_equal_approx(hole_outline_color.a, expected_outline_color.a),
		"Runtime cat outline brightness was not copied to the matching CatHole"
	)
	print("[runtime outline] CatHole received %.3f" % expected)


func _check_not_a_path(manager: LevelManager) -> void:
	var hole: Vector2i = manager.get_hole_cells()[0]
	var cat: CatEntity = _fresh_cat(manager, hole + Vector2i(0, 3))
	_expect(not cat.can_enter(hole), "구멍으로 들어갈 수 있다고 판정했다")
	cat.path_queue.clear()
	cat.request_path_to(hole)
	_expect(cat.path_queue.is_empty(), "구멍으로 가는 경로가 생겼다: %s" % [cat.path_queue])


# 두 칸 떨어져 있으면 아무 일도 없다. 인접한 순간에만 걸려야 한다.
func _check_no_trigger_when_far(manager: LevelManager) -> void:
	var hole: Vector2i = manager.get_hole_cells()[0]
	var cat: CatEntity = _fresh_cat(manager, hole + Vector2i(0, 3))
	cat.request_path_to(hole + Vector2i(0, 2))
	cat.advance(1.2 / cat.move_speed_cells)
	_expect(cat.body_cells[0] == hole + Vector2i(0, 2), "이동이 되지 않았다: %s" % [cat.body_cells])
	_expect(not cat.is_absorbing(), "두 칸 떨어졌는데 흡입이 시작됐다")


# 리드가 구멍 옆칸에 들어선 순간 흡입이 시작되고, 몸 전체가 구멍으로 들어가 사라진다.
func _check_lead_absorb(manager: LevelManager) -> void:
	# 네 방향, 양쪽 리드, 양쪽 흡입 끝에서 실제 리그의 곡선·접선·스케일을 검사한다.
	var directions := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	var facings := ["up", "right", "down", "left"]
	var tile := manager.fitted_tile_size()
	var worst_bone_gap := 0.0
	var worst_front_leg_gap := 0.0
	var max_sway := 0.0
	UiBridge.is_hosted = true
	for facing in 4:
		for tail_lead in 2:
			for from_lead in [true, false]:
				var probe := _fresh_cat(manager, Vector2i(3, 4), facings[facing])
				if tail_lead == 1:
					probe._flip_lead()
				var head_first: bool = from_lead != probe._lead_is_tail
				var heading: Vector2i = directions[facing] * (1 if head_first else -1)
				var entry_cell: Vector2i = probe.body_cells[0] if from_lead else probe.body_cells.back()
				var test_hole := entry_cell + heading
				probe._begin_absorb(test_hole, from_lead)
				var polyline := probe._body_polyline()
				var cumulative := probe._cumulative_lengths(polyline)
				var total: float = cumulative[cumulative.size() - 1]
				var entry_arc := 0.0 if from_lead else total
				var entry_point: Vector3 = probe._sample_polyline(polyline, cumulative, entry_arc)
				var center := manager.grid_to_world(test_hole, manager.cat_world_y)
				var travel := entry_point.distance_to(center) + tile * CatEntity.ABSORB_SINK_CELLS
				var distances := probe._stretched_chain_distances()
				var model_scale := probe._grid_fitted_model_scale()
				var front_legs := probe._skeleton.find_bone("Bone001")
				var shoulders := probe._skeleton.find_bone("Bone003")
				var previous_position := entry_point
				var previous_direction := manager.grid_dir_to_world(directions[facing])
				var saw_sloping_pose := false
				var min_side := 0.0
				var max_side := 0.0
				for step in range(1, 161):
					probe._swallowed_arc = travel * float(step) / 160.0
					probe._update_visual_pose()
					worst_front_leg_gap = maxf(worst_front_leg_gap,
						_bone_world(probe, front_legs).distance_to(_bone_world(probe, shoulders)))
					var pose := probe._absorb_pose_at(polyline, cumulative, total, entry_arc)
					var point: Vector3 = pose[0]
					var direction: Vector3 = pose[1]
					var basis := probe._fbx_basis_for_direction(direction)
					var displacement := point - previous_position
					_expect(point.is_finite() and basis.is_finite(), "흡입 포즈가 유효하지 않다")
					_expect(absf(basis.determinant() - 1.0) < 0.00001
						and basis.transposed().is_equal_approx(basis.inverse()), "흡입 회전에 전단이 있다")
					_expect(direction.dot(previous_direction) > 0.995, "흡입 회전이 경계에서 튄다")
					_expect(displacement.length() <= travel / 160.0 + 0.00001, "흡입 위치가 점프했다")
					_expect(point.y <= previous_position.y + 0.00001, "잠기던 고양이가 위로 튄다")
					_expect(displacement.normalized().dot(direction * (1.0 if head_first else -1.0)) > 0.995,
						"본 방향이 실제 잠수 경로를 따르지 않는다")
					if absf(direction.y) > 0.2 and absf(direction.y) < 0.9:
						saw_sloping_pose = true
					previous_position = point
					previous_direction = direction
					for index in probe._bone_chain.size():
						var bone: int = probe._bone_chain[index]
						var arc: float = distances[index] * model_scale
						var body_arc: float = total - arc if probe._lead_is_tail else arc
						var baseline := probe._absorb_pose_at(polyline, cumulative, total, body_arc)
						var swaying := probe._pose_at(polyline, cumulative, total, body_arc)
						var expected: Vector3 = swaying[0]
						var offset: Vector3 = expected - baseline[0]
						var sideways := offset.dot(probe._absorb_head_axis.cross(Vector3.UP).normalized())
						min_side = minf(min_side, sideways)
						max_side = maxf(max_side, sideways)
						max_sway = maxf(max_sway, offset.length() / tile)
						_expect(offset.length() <= tile * CatEntity.ABSORB_SWAY_CELLS + 0.00001,
							"흡입 흔들림이 최대 진폭을 넘었다")
						_expect(absf(offset.y) < 0.00001, "흡입 흔들림이 잠수 높이를 바꿨다")
						if absf(baseline[1].y) > 0.00001:
							_expect(offset.length() < 0.00001 and swaying[1].is_equal_approx(baseline[1]),
								"구멍 진입 곡선이나 수직 잠수 경로가 흔들렸다")
						worst_bone_gap = maxf(worst_bone_gap, _bone_world(probe, bone).distance_to(expected))
						_expect(probe._skeleton.get_bone_pose_scale(bone).is_equal_approx(Vector3.ONE),
							"흡입 중 본 스케일이 바뀌었다")
				_expect(saw_sloping_pose, "수평 몸통이 아래로 휘는 중간 자세가 없다")
				_expect(min_side < -tile * 0.01 and max_side > tile * 0.01, "흡입 몸통의 좌우 흔들림이 없다")
				_expect(Vector2(previous_position.x - center.x, previous_position.z - center.z).length() < 0.00001,
					"수직 잠수 위치가 구멍 중심과 다르다")
				probe._swallowed_arc = probe._absorb_required_arc
				var last_arc := total if from_lead else 0.0
				var last_pose := probe._absorb_pose_at(polyline, cumulative, total, last_arc)
				_expect(absf(last_pose[0].y - (center.y - tile * CatEntity.ABSORB_SINK_CELLS)) < 0.00001,
					"흡입 완료 길이와 마지막 본의 낙하 깊이가 다르다")
	_expect(worst_bone_gap < 0.001, "흡입 계산 경로와 실제 본 위치가 어긋난다: %.6f" % worst_bone_gap)
	_expect(worst_front_leg_gap < 0.001, "흡입 중 앞발이 어깨에서 떨어졌다")
	UiBridge.is_hosted = false
	print("[입체 흡입] 16개 방향/리드/진입 조합, 2560개 포즈, 최대 본 오차 %.6f" % worst_bone_gap)
	print("[흡입 흔들림] 최대 좌우 변위 %.4f칸, 입구/잠수 경로 고정" % max_sway)

	var hole: Vector2i = manager.get_hole_cells()[0]
	var hole_color: int = manager.get_hole_color_id(hole)
	var cat: CatEntity = _fresh_cat(manager, hole + Vector2i(0, 2))
	_expect((cat._cat_material.get_shader_parameter("absorb_light_portal") as Vector4).is_zero_approx(),
		"일반 고양이에 흡입 빛 가림이 켜져 있다")
	var length: int = cat.body_cells.size()

	cat.request_path_to(hole + Vector2i(0, 1))
	cat.advance(0.5 / cat.move_speed_cells)
	_expect(not cat.is_absorbing(), "전이 중에 흡입이 시작됐다")
	cat.advance(0.6 / cat.move_speed_cells)
	_expect(cat.is_absorbing(), "구멍 옆칸에 들어섰는데 흡입이 시작되지 않았다")
	_expect(cat._absorb_cell == hole, "흡입 대상 구멍이 다르다: %s" % [cat._absorb_cell])
	_expect(cat._absorb_from_lead, "리드가 닿았는데 후미쪽 흡입으로 잡혔다")
	_expect(cat.get_node_or_null("AbsorbLevelUp") == null, "제거한 흡입 이펙트가 생성됐다")
	_expect(manager.get_node_or_null("HoleVisuals/AbsorbLevelUpWarmup") == null,
		"제거한 흡입 이펙트의 사전 재생이 남아 있다")
	for material in [cat._cat_material, cat._material_id_2, cat._outline_material, cat._material_id_2_outline]:
		_expect((material.get_shader_parameter("absorb_light_portal") as Vector4).is_zero_approx(),
			"흡입 중 고양이 몸을 덮는 발광이 남아 있다")
	var absorb_players := cat.find_children("*", "AudioStreamPlayer", true, false)
	var absorb_overlay_played := false
	for player in absorb_players:
		if player.stream == preload("res://src/sound/time_out2.mp3") and player.playing:
			absorb_overlay_played = true
			break
	_expect(absorb_overlay_played, "구멍 흡입이 시작될 때 time_out2 오버레이 사운드가 재생되지 않았다")

	# 흡입이 시작되면 점유를 즉시 놓는다.
	for cell in cat.body_cells:
		_expect(
			not manager.is_cell_blocked_for(null, cell) or manager.is_hole(cell),
			"흡입 중인 고양이가 %s 를 아직 막고 있다" % [cell]
		)
	# 조작을 받지 않는다.
	cat.request_path_to(hole + Vector2i(0, 3))
	_expect(cat.path_queue.is_empty(), "흡입 중에 이동 요청이 큐에 들어갔다")
	_expect(cat.body_cells.size() == length, "흡입이 몸 길이를 바꿨다: %d" % cat.body_cells.size())

	# 머리 본이 구멍 중심을 지나 아래로 내려간다.
	var hole_center: Vector3 = manager.grid_to_world(hole, manager.cat_world_y)
	var progressed := false
	var sank := false
	var elapsed := 0.0
	while cat.is_absorbing() and elapsed < 3.0:
		cat.advance(1.0 / 120.0)
		elapsed += 1.0 / 120.0
		if not cat.is_absorbing():
			break
		var head: Vector3 = _head_bone_world(cat)
		if Vector2(head.x - hole_center.x, head.z - hole_center.z).length() < 0.05:
			progressed = true
		if head.y < hole_center.y - 0.4:
			sank = true
	_expect(progressed, "머리가 구멍 중심 위를 지나가지 않았다")
	_expect(sank, "머리가 구멍 아래로 내려가지 않았다")
	_expect(not cat.is_absorbing(), "흡입이 끝나지 않았다 (%.2f초)" % elapsed)
	_expect(not manager.get_cats().has(cat), "흡입이 끝났는데 고양이가 목록에 남았다")
	var hole_shards := manager.get_node("HoleVisuals").get_node_or_null(
		"HoleCloseShards_%d_%d" % [hole.x, hole.y]
	) as GPUParticles3D
	_expect(hole_shards != null, "구멍이 닫힐 때 짝 색 파티클이 생성되지 않았다")
	if hole_shards != null:
		var shard_mesh := hole_shards.draw_pass_1 as BoxMesh
		var shard_material: StandardMaterial3D = null
		if shard_mesh != null:
			shard_material = shard_mesh.material as StandardMaterial3D
		_expect(
			shard_material != null
			and shard_material.albedo_color == manager.get_hole_rim_color(hole_color),
			"구멍 닫힘 파티클 색이 짝 색과 다르다"
		)
	var pop_players := manager.find_children("*", "AudioStreamPlayer", true, false)
	var hole_pop_played := false
	for player in pop_players:
		if player.stream == preload("res://src/sound/bubble_pop.mp3"):
			hole_pop_played = true
			break
	_expect(hole_pop_played, "구멍이 닫힐 때 연결된 팝 사운드가 재생되지 않았다")
	print("[흡입] 리드가 %.3f초에 구멍 %s 로 사라졌다" % [elapsed, hole])


# 리드가 아닌 끝은 흡입을 걸지 않는다. 후진으로 후미가 구멍 옆칸에 닿아도 들어가지 않고,
# 그 끝을 잡았다 놓아 리드로 만들어야 들어간다.
func _check_rear_does_not_absorb(manager: LevelManager) -> void:
	var hole: Vector2i = manager.get_hole_cells()[0]
	# 리드는 구멍에서 먼 쪽에 두고, 후미가 구멍 쪽을 향하게 세운다.
	var cat: CatEntity = _fresh_cat(manager, hole + Vector2i(0, 5), "down")
	var rear_before: Vector2i = cat.body_cells[cat.body_cells.size() - 1]
	_expect(rear_before == hole + Vector2i(0, 2), "후진 시작 자세가 기대와 다르다: %s" % [cat.body_cells])
	_expect(not cat.is_absorbing(), "시작 자세에서 이미 흡입됐다: %s" % [cat.body_cells])

	# 손가락으로 자기 몸을 가리키면 후진이다. 후미가 구멍 옆칸으로 밀려 나간다.
	cat.request_path_to(cat.body_cells[1])
	cat.advance(1.2 / cat.move_speed_cells)
	var rear_after: Vector2i = cat.body_cells[cat.body_cells.size() - 1]
	_expect(
		rear_after == hole + Vector2i(0, 1),
		"후미가 구멍 옆칸으로 밀리지 않았다: %s" % [cat.body_cells]
	)
	_expect(not cat.is_absorbing(), "리드가 아닌 후미가 닿았는데 흡입이 시작됐다")

	# 그 끝을 잡아 리드로 만드는 순간 들어간다.
	cat.begin_drag(rear_after)
	_expect(cat.is_absorbing(), "구멍 옆 끝을 잡았는데 흡입이 시작되지 않았다")
	_expect(cat._absorb_cell == hole, "흡입 대상 구멍이 다르다: %s" % [cat._absorb_cell])
	_drain(cat)
	print("[흡입] 후미 %s 는 흡입되지 않고, 잡아서 리드로 만들면 들어간다" % [rear_before])


# 색이 짝이 아니면 옆칸에 들어서도 빠지지 않는다. 짝이면 같은 자리에서 빠진다.
func _check_color_pair(manager: LevelManager) -> void:
	var hole: Vector2i = manager.get_hole_cells()[0]
	var hole_color: int = manager.get_hole_color_id(hole)
	_expect(hole_color >= 0, "구멍에 색이 지정되지 않았다: %s" % [hole])
	var other_color: int = hole_color + 1

	_expect(
		manager.adjacent_hole(hole + Vector2i.LEFT, other_color) == null,
		"색이 다른데 인접 구멍으로 걸렸다"
	)
	_expect(
		manager.adjacent_hole(hole + Vector2i.LEFT, hole_color) == hole,
		"색이 같은데 인접 구멍을 못 찾았다"
	)
	_expect(
		manager.adjacent_hole(hole + Vector2i.LEFT, -1) == hole,
		"와일드카드가 구멍을 못 찾았다"
	)

	var mismatched: CatEntity = _fresh_cat(manager, hole + Vector2i(0, 2))
	mismatched.color_id = other_color
	mismatched.request_path_to(hole + Vector2i(0, 1))
	mismatched.advance(1.2 / mismatched.move_speed_cells)
	_expect(
		mismatched.body_cells[0] == hole + Vector2i(0, 1),
		"색이 다른 고양이가 구멍 옆칸으로 못 갔다: %s" % [mismatched.body_cells]
	)
	_expect(not mismatched.is_absorbing(), "색이 다른데 흡입이 시작됐다")

	var matched: CatEntity = _fresh_cat(manager, hole + Vector2i(0, 2))
	matched.color_id = hole_color
	matched.request_path_to(hole + Vector2i(0, 1))
	matched.advance(1.2 / matched.move_speed_cells)
	_expect(matched.is_absorbing(), "색이 같은데 흡입이 시작되지 않았다")
	_drain(matched)
	print("[색] 구멍 %s(색 %d) 는 같은 색 고양이만 받는다" % [hole, hole_color])


# 마지막 고양이가 흡입되면 클리어 신호가 나온다. 탈출과 같은 경로를 쓴다.
func _check_clears_level(manager: LevelManager) -> void:
	for cat in manager.get_cats().duplicate():
		_drain(cat)
	var cleared := [false]
	manager.level_cleared.connect(func(): cleared[0] = true)
	var hole: Vector2i = manager.get_hole_cells()[0]
	var last: CatEntity = _fresh_cat(manager, hole + Vector2i(0, 2))
	last.request_path_to(hole + Vector2i(0, 1))
	last.advance(1.2 / last.move_speed_cells)
	_expect(last.is_absorbing(), "마지막 고양이가 흡입되지 않았다")
	_drain(last)
	_expect(cleared[0], "마지막 고양이가 사라졌는데 클리어 신호가 없다")
	print("[클리어] 마지막 고양이 흡입으로 level_cleared 발생")


# 검사용 고양이를 구멍에서 떨어진 자리에 새로 만든다. 기존 고양이는 정리한다.
func _fresh_cat(manager: LevelManager, cell: Vector2i, facing := "up") -> CatEntity:
	for existing in manager.get_cats().duplicate():
		manager.release_cat_cell(existing)
		manager._cats.erase(existing)
		existing.get_parent().remove_child(existing)
		existing.queue_free()

	var cat := CatEntity.new()
	cat.set_script(load("res://scripts/cat_entity.gd"))
	cat.facing_name = facing
	cat.grid_pos = cell
	cat.initial_length = 4
	manager.get_node("LayoutCats").add_child(cat)
	cat.initialize_runtime(manager)
	manager.update_cat_occupancy(cat)
	manager._cats.append(cat)
	cat.advance(0.0)
	return cat


func _drain(cat: CatEntity) -> void:
	var elapsed := 0.0
	while is_instance_valid(cat) and cat.is_absorbing() and elapsed < 3.0:
		cat.advance(1.0 / 120.0)
		elapsed += 1.0 / 120.0


func _head_bone_world(cat: CatEntity) -> Vector3:
	return _bone_world(cat, cat._bone_chain[0])


func _tail_bone_world(cat: CatEntity) -> Vector3:
	return _bone_world(cat, cat._bone_chain[cat._bone_chain.size() - 1])


func _bone_world(cat: CatEntity, bone: int) -> Vector3:
	var skeleton: Skeleton3D = cat._skeleton
	return skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _report() -> void:
	if _failures.is_empty():
		print("HOLE CHECK: PASS")
		return
	print("HOLE CHECK: FAIL (%d)" % _failures.size())
	for failure in _failures:
		print("  - ", failure)
