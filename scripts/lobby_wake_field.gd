class_name LobbyWakeField
extends RefCounted

# Source panels solve the moving-wall condition on live mesh/water sections.
# Foam consists of material filaments with no image or shape-restoring spring.
const CAPACITY := 16
const SAMPLES := 9
var strands: Array[PackedVector2Array] = []
var thicknesses: Array[PackedFloat32Array] = []
var strand_normals: Array[PackedVector2Array] = []
var strand_scales := PackedFloat32Array()
var ages := PackedFloat32Array()
var lifetimes := PackedFloat32Array()
var opacities := PackedFloat32Array()
var identities := PackedInt32Array()
var variations := PackedFloat32Array()
var birth_points := PackedVector2Array()
var sections: Array[PackedVector2Array] = []
var section_velocities: Array[PackedVector2Array] = []
var section_incidence: Array[PackedFloat32Array] = []
var panel_starts := PackedVector2Array()
var panel_ends := PackedVector2Array()
var panel_normals := PackedVector2Array()
var panel_strengths := PackedFloat32Array()
var panel_velocities := PackedVector2Array()
var section_panel_offsets := PackedInt32Array()
var center := Vector2.ZERO
var axis := Vector2.RIGHT
var side := Vector2.DOWN
var source_velocity := Vector2.ZERO
var body_width := 1.0
var sample_contact := Vector2.ZERO
var sample_normal := Vector2.ZERO
var sample_distance := INF
var sample_wall_velocity := Vector2.ZERO
var boundary_residual := 0.0
var _random := RandomNumberGenerator.new()
var _next := 0
var _emission := 0
var _identity_counter := 0
var _rhythm_distance := 0.0
var _emission_budget := 0.0
var _next_arrival := 0.0024
var _previous_center := Vector2.ZERO
var _has_center := false


func _init() -> void:
	_random.seed = 615937
	strands.resize(CAPACITY)
	thicknesses.resize(CAPACITY)
	strand_normals.resize(CAPACITY)
	strand_scales.resize(CAPACITY)
	ages.resize(CAPACITY)
	lifetimes.resize(CAPACITY)
	opacities.resize(CAPACITY)
	identities.resize(CAPACITY)
	variations.resize(CAPACITY)
	birth_points.resize(CAPACITY)


func sample_velocity(point: Vector2, contact_only: bool = false) -> Vector2:
	if sections.is_empty():
		sample_distance = INF
		return Vector2.ZERO
	var result := Vector2.ZERO
	for panel in (0 if contact_only else panel_starts.size()):
		var edge := panel_ends[panel] - panel_starts[panel]
		var length := edge.length()
		var tangent := edge / length
		var relative := point - panel_starts[panel]
		var x := relative.dot(tangent)
		var y := relative.dot(panel_normals[panel])
		# A finite core removes the velocity jump across a coarse panel and
		# the logarithmic endpoint spike. The exact mesh wall is enforced below.
		var core := body_width * 0.01
		var height := sqrt(y * y + core * core)
		var r0 := x * x + height * height
		var r1 := (x - length) * (x - length) + height * height
		var tangential := 0.5 * log(r0 / r1)
		var normal := y / height * atan2(height * length, x * (x - length) + height * height)
		result += (tangent * tangential + panel_normals[panel] * normal) * (panel_strengths[panel] / TAU)
	# Retain the exact triangle-cut boundary between collocation points.
	sample_distance = INF
	for section_index in sections.size():
		var section := sections[section_index]
		for index in section.size():
			var a := section[index]
			var b := section[(index + 1) % section.size()]
			var closest := Geometry2D.get_closest_point_to_segment(point, a, b)
			var distance := point.distance_to(closest)
			if distance < sample_distance:
				sample_distance = distance
				sample_contact = closest
				var edge := (b - a).normalized()
				sample_normal = Vector2(edge.y, -edge.x)
				sample_wall_velocity = source_velocity
				if section_velocities.size() == sections.size():
					var t := a.distance_to(closest) / maxf(a.distance_to(b), 0.000001)
					sample_wall_velocity = section_velocities[section_index][index].lerp(section_velocities[section_index][(index + 1) % section.size()], t)
	# Sections have counterclockwise winding. The nearest edge's oriented
	# normal gives the distance sign, including at convex/concave vertices.
	# Ray-cast containment can misclassify a point on an extended vertex ray.
	if (point - sample_contact).dot(sample_normal) < 0.0:
		sample_distance = -sample_distance
	# At a polygon corner, one incident edge's normal can point into its
	# neighbor. Use the signed-distance gradient for contact and projection.
	# Retain the oriented edge normal within floating-point tolerance.
	if absf(sample_distance) > body_width * 0.0001:
		sample_normal = (point - sample_contact) / sample_distance
	var contact := 1.0 - smoothstep(0.0, body_width * 0.035, maxf(sample_distance, 0.0))
	result -= sample_normal * (result - sample_wall_velocity).dot(sample_normal) * contact
	return result


func step(delta: float, water_sections: Array[PackedVector2Array], width: float, velocity: Vector2, water_velocities: Array[PackedVector2Array] = [], water_incidence: Array[PackedFloat32Array] = []) -> void:
	source_velocity = velocity
	body_width = width
	sections = water_sections
	section_velocities = water_velocities
	section_incidence = water_incidence
	if sections.is_empty():
		# A dry mesh cannot displace water or carry a fake contact outline.
		lifetimes.fill(0.0)
		panel_starts.clear()
		panel_ends.clear()
		panel_normals.clear()
		panel_strengths.clear()
		panel_velocities.clear()
		section_panel_offsets.clear()
		_emission_budget = 0.0
		return
	var bounds := Rect2(sections[0][0], Vector2.ZERO)
	var total_perimeter := 0.0
	for section in sections:
		for index in section.size():
			bounds = bounds.expand(section[index])
			total_perimeter += section[index].distance_to(section[(index + 1) % section.size()])
	center = bounds.get_center()
	if _has_center and center.distance_to(_previous_center) >= width:
		lifetimes.fill(0.0)
		_emission_budget = 0.0
	_previous_center = center
	_has_center = true
	panel_starts.clear()
	panel_ends.clear()
	panel_normals.clear()
	panel_velocities.clear()
	section_panel_offsets.clear()
	# ponytail: about 48 planar boundary panels; use a free-surface solver
	# if vertical waves, splashes or 3D turbulence must be solved physically.
	for section_index in sections.size():
		var section := sections[section_index]
		section_panel_offsets.append(panel_starts.size())
		var lengths := PackedFloat32Array([0.0])
		for index in section.size():
			lengths.append(lengths[-1] + section[index].distance_to(section[(index + 1) % section.size()]))
		var count := maxi(6, roundi(48.0 * lengths[-1] / total_perimeter))
		var samples := PackedVector2Array()
		var velocities := PackedVector2Array()
		var segment := 0
		for index in count:
			var distance := lengths[-1] * float(index) / count
			while segment + 1 < section.size() and lengths[segment + 1] < distance:
				segment += 1
			var t := (distance - lengths[segment]) / maxf(lengths[segment + 1] - lengths[segment], 0.000001)
			samples.append(section[segment].lerp(section[(segment + 1) % section.size()], t))
			velocities.append(velocity if water_velocities.is_empty() else water_velocities[section_index][segment].lerp(water_velocities[section_index][(segment + 1) % section.size()], t))
		for index in count:
			var a := samples[index]
			var b := samples[(index + 1) % count]
			var edge := (b - a).normalized()
			panel_starts.append(a)
			panel_ends.append(b)
			panel_normals.append(Vector2(edge.y, -edge.x))
			panel_velocities.append((velocities[index] + velocities[(index + 1) % count]) * 0.5)
	section_panel_offsets.append(panel_starts.size())
	var panel_count := panel_starts.size()
	panel_strengths.resize(panel_count)
	panel_strengths.fill(0.0)
	var matrix: Array[PackedFloat32Array] = []
	for row in panel_count:
		var coefficients := PackedFloat32Array()
		var point := (panel_starts[row] + panel_ends[row]) * 0.5
		for column in panel_count:
			if row == column:
				coefficients.append(0.5)
				continue
			var edge := panel_ends[column] - panel_starts[column]
			var length := edge.length()
			var tangent := edge / length
			var relative := point - panel_starts[column]
			var x := relative.dot(tangent)
			var y := relative.dot(panel_normals[column])
			var tangential := 0.5 * log(maxf(x*x+y*y, 0.00000001) / maxf((x-length)*(x-length)+y*y, 0.00000001))
			var normal := atan2(y * length, x * (x - length) + y * y)
			coefficients.append((tangent * tangential + panel_normals[column] * normal).dot(panel_normals[row]) / TAU)
		matrix.append(coefficients)
	# Direct elimination with pivoting remains stable when paws merge with
	# the torso at the waterline; fixed-count relaxation did not converge.
	var original: Array[PackedFloat32Array] = matrix.duplicate(true)
	var right_hand := PackedFloat32Array()
	for row in panel_count:
		right_hand.append(panel_velocities[row].dot(panel_normals[row]))
	for pivot in panel_count:
		var best := pivot
		for row in range(pivot + 1, panel_count):
			if absf(matrix[row][pivot]) > absf(matrix[best][pivot]):
				best = row
		assert(absf(matrix[best][pivot]) > 0.00000001, "Degenerate water-contact panel system")
		if best != pivot:
			var swap := matrix[pivot]
			matrix[pivot] = matrix[best]
			matrix[best] = swap
			var swap_value := right_hand[pivot]
			right_hand[pivot] = right_hand[best]
			right_hand[best] = swap_value
		for row in range(pivot + 1, panel_count):
			var factor := matrix[row][pivot] / matrix[pivot][pivot]
			matrix[row][pivot] = 0.0
			for column in range(pivot + 1, panel_count):
				matrix[row][column] -= factor * matrix[pivot][column]
			right_hand[row] -= factor * right_hand[pivot]
	for row in range(panel_count - 1, -1, -1):
		var value := right_hand[row]
		for column in range(row + 1, panel_count):
			value -= matrix[row][column] * panel_strengths[column]
		panel_strengths[row] = value / matrix[row][row]
	boundary_residual = 0.0
	for row in panel_count:
		var residual := panel_velocities[row].dot(panel_normals[row])
		for column in panel_count:
			residual -= original[row][column] * panel_strengths[column]
		boundary_residual = maxf(boundary_residual, absf(residual))
	# Each marker follows the local fluid velocity. Stretch thins the film,
	# shear erodes it, and detached material dissipates quickly.
	for index in CAPACITY:
		if lifetimes[index] <= 0.0:
			continue
		ages[index] += delta
		var curve := strands[index]
		var previous := curve.duplicate()
		var widths := thicknesses[index]
		var normals := strand_normals[index]
		var local_scale := strand_scales[index]
		var separation := 0.0
		if velocity.length_squared() > 0.000001:
			for marker in SAMPLES:
				var point := curve[marker]
				var midpoint := point + sample_velocity(point) * (delta * 0.5)
				point += sample_velocity(midpoint) * delta
				# The wall can overtake a marker between the two RK stages.
				# Resolve the updated point, not the midpoint's contact position.
				sample_velocity(point, true)
				if sample_distance < local_scale * 0.012:
					point = sample_contact + sample_normal * local_scale * 0.012
				separation += maxf(sample_distance, 0.0) / float(SAMPLES)
				curve[marker] = point
		for marker in SAMPLES:
			var left := maxi(0, marker - 1)
			var right := mini(SAMPLES - 1, marker + 1)
			# Use material arc length: a folded chord can approach zero even
			# when neither adjacent segment has compressed.
			var length := curve[left].distance_to(curve[marker]) + curve[marker].distance_to(curve[right])
			var old_length := previous[left].distance_to(previous[marker]) + previous[marker].distance_to(previous[right])
			var strain := log(maxf(length / maxf(old_length, 0.000001), 0.05))
			var width_change := clampf(-strain - absf(strain) * 0.12, -delta * 5.0, delta * 5.0)
			widths[marker] = minf(local_scale * 0.10, widths[marker] * exp(width_change - delta * 0.22))
			var tangent := (curve[right] - curve[left]).normalized()
			var normal := Vector2(tangent.y, -tangent.x)
			# Material-side continuity at a cusp: never flip the sheet by 180°.
			if normal.dot(normals[marker]) < 0.0:
				normal = -normal
			if not normal.is_zero_approx():
				normals[marker] = normals[marker].slerp(normal, 1.0 - exp(-delta * 8.0)).normalized()
		var decay := 0.20 + smoothstep(local_scale * 0.025, local_scale * 0.20, separation) * 5.0
		if velocity.length() < 0.05:
			decay = 8.0
		opacities[index] *= exp(-delta * decay)
		strands[index] = curve
		thicknesses[index] = widths
		strand_normals[index] = normals
		if ages[index] >= lifetimes[index] or opacities[index] < 0.025:
			lifetimes[index] = 0.0
	# Bow-foam arrivals are driven by normal kinetic-energy flux, not time.
	var candidates: Array[Vector3] = []
	var work := 0.0
	for section_index in sections.size():
		var section := sections[section_index]
		for edge_index in section.size():
			var edge := section[(edge_index + 1) % section.size()] - section[edge_index]
			var normal := Vector2(edge.y, -edge.x).normalized()
			var wall_velocity := source_velocity
			if not water_velocities.is_empty():
				wall_velocity = (water_velocities[section_index][edge_index] + water_velocities[section_index][(edge_index + 1) % section.size()]) * 0.5
			# A shallow triangle can sweep the intersection line very quickly
			# without imparting that speed to water. Recover true 3D normal
			# incidence before computing its kinetic-energy flux.
			var incidence := 1.0
			if not water_incidence.is_empty():
				incidence = (water_incidence[section_index][edge_index] + water_incidence[section_index][(edge_index + 1) % section.size()]) * 0.5
			work += pow(maxf(wall_velocity.dot(normal) * incidence, 0.0), 3.0) * edge.length()
			candidates.append(Vector3(section_index, edge_index, work))
	_rhythm_distance += velocity.length() * delta
	if velocity.length() >= 0.05:
		_emission_budget += work * delta / (9.81 * pow(width, 3.0))
	while work > 0.000001 and _emission_budget >= _next_arrival:
		_emission_budget -= _next_arrival
		_next_arrival = _random.randf_range(0.0018, 0.0038)
		var target := _random.randf() * work
		var selected := 0
		while candidates[selected].z < target:
			selected += 1
		var section := sections[int(candidates[selected].x)]
		var source_edge := int(candidates[selected].y)
		var lengths := PackedFloat32Array([0.0])
		for edge in section.size():
			lengths.append(lengths[-1] + section[edge].distance_to(section[(edge + 1) % section.size()]))
		var coordinate := lerpf(lengths[source_edge], lengths[source_edge + 1], _random.randf())
		# A paw must not inherit a torso-sized arc that wraps behind it.
		# Walk only the locally facing contact surface (within 60 degrees of
		# the pressure-selected edge); use that span for thickness as well.
		var source_tangent := (section[(source_edge + 1) % section.size()] - section[source_edge]).normalized()
		var available := Vector2.ZERO
		for direction in 2:
			var edge := source_edge
			var span := coordinate - lengths[edge] if direction == 0 else lengths[edge + 1] - coordinate
			for boundary in section.size() - 1:
				if span >= width * 0.5:
					break
				edge = posmod(edge + (-1 if direction == 0 else 1), section.size())
				var tangent := (section[(edge + 1) % section.size()] - section[edge]).normalized()
				if tangent.dot(source_tangent) < 0.5:
					break
				span += lengths[edge + 1] - lengths[edge]
			available[direction] = minf(span, width * 0.5)
		var local_scale := minf(width, available.x + available.y)
		var arc := local_scale * _random.randf_range(0.55, 1.0)
		# Keep endpoint sampling on the accepted side of a polygon corner.
		var left_extent := minf(arc * 0.5, maxf(available.x - local_scale * 0.0001, 0.0))
		var right_extent := minf(arc * 0.5, maxf(available.y - local_scale * 0.0001, 0.0))
		var curve := PackedVector2Array()
		var widths := PackedFloat32Array()
		var normals := PackedVector2Array()
		for marker in SAMPLES:
			var ratio := float(marker) / (SAMPLES - 1)
			var distance := fposmod(coordinate + (ratio - 0.5) * 2.0 * (left_extent if ratio <= 0.5 else right_extent), lengths[-1])
			var edge := 0
			while edge + 1 < section.size() and lengths[edge + 1] < distance:
				edge += 1
			var a := section[edge]
			var b := section[(edge + 1) % section.size()]
			var tangent := (b - a).normalized()
			var normal := Vector2(tangent.y, -tangent.x)
			var point := a.lerp(b, (distance - lengths[edge]) / maxf(lengths[edge + 1] - lengths[edge], 0.000001))
			curve.append(point + normal * local_scale * 0.012)
			widths.append(local_scale * _random.randf_range(0.055, 0.095) * pow(sin(PI * ratio), 0.65))
			normals.append(normal)
		strands[_next] = curve
		thicknesses[_next] = widths
		strand_normals[_next] = normals
		strand_scales[_next] = local_scale
		ages[_next] = 0.0
		lifetimes[_next] = _random.randf_range(2.4, 3.2)
		opacities[_next] = smoothstep(0.08, 0.65, velocity.length())
		_identity_counter += 1
		identities[_next] = _identity_counter
		variations[_next] = _random.randf()
		birth_points[_next] = curve[SAMPLES / 2]
		_next = (_next + 1) % CAPACITY
		_emission += 1
