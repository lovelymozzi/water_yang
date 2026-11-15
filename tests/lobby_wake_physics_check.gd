extends SceneTree

const FIELD = preload("res://scripts/lobby_wake_field.gd")

func _initialize() -> void:
	var circle := PackedVector2Array()
	for index in 96:
		circle.append(Vector2(cos(TAU * index / 96.0), sin(TAU * index / 96.0)))
	var sections: Array[PackedVector2Array] = [circle]
	var field = FIELD.new()
	var largest_error := 0.0
	for velocity in [Vector2(0.65, 0.0), Vector2(1.3, 0.0), Vector2(-0.65, 0.2)]:
		field.step(0.0, sections, 2.0, velocity)
		assert(field.boundary_residual < velocity.length() * 0.01)
		assert(field.sample_velocity(Vector2(1000, 1000)).length() < 0.001)
		for index in 32:
			var angle := TAU * (index + 0.5) / 32.0
			var normal := Vector2(cos(angle), sin(angle))
			var p := normal * 1.5
			# Analytic translating-circle solution, independent of the solver.
			var expected: Vector2 = (normal * (2.0 * velocity.dot(normal)) - velocity) / 2.25
			var error: float = field.sample_velocity(p).distance_to(expected) / velocity.length()
			largest_error = maxf(largest_error, error)
			assert(error < 0.04, "Panel flow differs from the analytic circle solution")
			assert(absf((field.sample_velocity(normal * 1.001) - velocity).dot(normal)) < velocity.length() * 0.03)
			var dx: Vector2 = (field.sample_velocity(p + Vector2(0.001, 0.0)) - field.sample_velocity(p - Vector2(0.001, 0.0))) / 0.002
			var dy: Vector2 = (field.sample_velocity(p + Vector2(0.0, 0.001)) - field.sample_velocity(p - Vector2(0.0, 0.001))) / 0.002
			assert(absf(dx.x + dy.y) < velocity.length() * 0.02)
	# An exterior point just below a polygon vertex must not be pushed inwards.
	field.sample_velocity(Vector2(0.177427, -1.007993), true)
	assert(field.sample_distance > 0.0 and field.sample_normal.y < 0.0, "Exterior vertex-ray contact has an inverted distance sign")
	field.sample_velocity(Vector2(0.177427, -0.960665), true)
	assert(field.sample_distance < 0.0 and field.sample_normal.y < 0.0, "Interior contact does not point out of the solid")
	var emissions: Array[int] = []
	for speed in [0.0, 0.325, 0.65]:
		var moving = FIELD.new()
		var live_circle := circle.duplicate()
		var live: Array[PackedVector2Array] = [live_circle]
		var seen := {}
		var shape_changed := false
		for frame in 480:
			for index in live_circle.size():
				live_circle[index].x += speed / 60.0
			live[0] = live_circle
			moving.step(1.0 / 60.0, live, 2.0, Vector2(speed, 0.0))
			for particle in FIELD.CAPACITY:
				if moving.lifetimes[particle] <= 0.0:
					continue
				assert(moving.lifetimes[particle] <= 3.2, "Slow speed lengthens foam lifetime")
				var identity: int = moving.identities[particle]
				var curve: PackedVector2Array = moving.strands[particle]
				if not seen.has(identity):
					seen[identity] = curve.duplicate()
					var birthplace: Vector2 = moving.birth_points[particle]
					assert(absf(birthplace.distance_to(Vector2(speed * (frame + 1) / 60.0, 0.0)) - 1.0) < 0.04, "Birth is detached from the true contact boundary")
				var initial: PackedVector2Array = seen[identity]
				for marker in FIELD.SAMPLES:
					assert(curve[marker].is_finite())
					# Independent geometric lower bound for the regular 96-gon;
					# avoids sharing the solver's signed-distance implementation.
					var circle_center := Vector2(speed * (frame + 1) / 60.0, 0.0)
					assert(curve[marker].distance_to(circle_center) >= cos(PI / 96.0) - 0.0001, "Foam entered the solid circle section")
					if marker > 0 and moving.ages[particle] > 0.3:
						if absf(curve[marker].distance_to(curve[marker - 1]) / maxf(initial[marker].distance_to(initial[marker - 1]), 0.00001) - 1.0) > 0.025:
							shape_changed = true
		emissions.append(moving._emission)
		if speed >= 0.65:
			assert(shape_changed, "Foam retains a rigid repeated shape")
			var before: int = moving._emission
			for frame in 40:
				moving.step(1.0 / 60.0, live, 2.0, Vector2.ZERO)
			assert(moving._emission == before, "Stopped body creates foam")
			for lifetime in moving.lifetimes:
				assert(lifetime == 0.0, "Stationary afterimage survives 2/3 second")
	assert(emissions[0] == 0 and emissions[2] > emissions[1] * 3, "Foam creation is not coupled to displaced kinetic energy")
	# An isolated small paw uses its own contact curvature, not torso width.
	var paw = FIELD.new()
	var paw_radius := 0.12
	var paw_births := 0
	var maximum_birth_turn := 0.0
	for frame in 360:
		var paw_center := Vector2(1.3 * (frame + 1) / 60.0, 0.0)
		var paw_section := PackedVector2Array()
		for vertex in 96:
			paw_section.append(paw_center + Vector2.from_angle(TAU * vertex / 96.0) * paw_radius)
		var paw_sections: Array[PackedVector2Array] = [paw_section]
		paw.step(1.0 / 60.0, paw_sections, 2.0, Vector2(1.3, 0.0))
		for particle in FIELD.CAPACITY:
			if paw.lifetimes[particle] <= 0.0:
				continue
			var scale: float = paw.strand_scales[particle]
			assert(scale > 0.0 and scale < paw_radius * 2.3, "Paw foam inherits the whole body's scale")
			for thickness in paw.thicknesses[particle]:
				assert(thickness <= scale * 0.1001, "Paw foam grows back to torso thickness")
			if paw.ages[particle] > 0.000001:
				continue
			paw_births += 1
			var curve: PackedVector2Array = paw.strands[particle]
			var normals: PackedVector2Array = paw.strand_normals[particle]
			var normal: Vector2 = normals[FIELD.SAMPLES / 2]
			var tangent := Vector2(-normal.y, normal.x)
			for marker in FIELD.SAMPLES:
				var turn := rad_to_deg(acos(clampf(normal.dot(normals[marker]), -1.0, 1.0)))
				maximum_birth_turn = maxf(maximum_birth_turn, turn)
				assert(turn <= 60.001, "Paw foam wraps around the back at birth")
				if marker > 0:
					assert((curve[marker] - curve[marker - 1]).dot(tangent) >= -0.00001, "Paw foam folds back at birth")
	assert(paw_births > 0, "Small-paw fixture created no foam to check")
	# A dry object must not preserve an unrelated wake.
	var dry: Array[PackedVector2Array] = []
	field.step(0.1, dry, 2.0, Vector2.RIGHT)
	assert(field.panel_starts.is_empty())
	assert(field.lifetimes.count(0.0) == FIELD.CAPACITY)
	assert(field.sample_velocity(Vector2.ZERO) == Vector2.ZERO and field.sample_distance == INF)
	print("MESH FLOW CHECK: PASS; circle relative error=", largest_error, "; 8s emissions (stop/half/normal)=", emissions, "; deformation, contact births, no penetration, rapid stop dissipation, dry mesh")
	print("PAW PATCH CHECK: PASS; births=", paw_births, "; maximum departure from source normal=", maximum_birth_turn, "deg; local thickness, no birth loops")
	quit()
