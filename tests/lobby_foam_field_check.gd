extends SceneTree

# Data/synchronization checks; rendered comparison remains the visual check.
func _initialize() -> void:
	var atlas := (load("res://water_yang/lobby_foam_field.png") as Texture2D).get_image()
	var profile := (load("res://water_yang/lobby_foam_profile.png") as Texture2D).get_image()
	assert(atlas.get_size() == Vector2i(3072, 1280))
	assert(profile.get_size() == Vector2i(512, 60))
	var widths: Array[float] = []
	for frame in 60:
		var previous := -1.0
		for angle in 512:
			var data := profile.get_pixel(angle, frame)
			var mapped := (data.r * 65280.0 + data.g * 255.0) / 65535.0
			assert(mapped > previous, "Angular mapping folds and changes connectedness")
			if angle == 255 or angle == 256:
				assert(absf(mapped - 0.5) < 0.02, "The two streams do not meet at the feet")
			previous = mapped
			widths.append(data.b * 0.16)
		assert(profile.get_pixel(0, frame).r < 0.02 and profile.get_pixel(511, frame).r > 0.98, "Crown anchor moved")
		var count := 0
		var origin := Vector2i(frame % 6, frame / 6) * Vector2i(512, 128)
		for y in range(0, 128, 2):
			for x in range(0, 512, 2):
				if atlas.get_pixelv(origin + Vector2i(x, y)).r > 0.5:
					count += 1
		assert(count > 50 and count < 8000, "Missing or solid foam field")
	assert(widths.max() > 0.10 and widths.min() < 0.005, "Measured thick/thin contact variation is missing")
	print("REFERENCE FOAM DATA CHECK: PASS (60 SDF frames; positive angular transport; shared crown and feet anchors; measured contact widths)")
	quit()
