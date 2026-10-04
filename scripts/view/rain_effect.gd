class_name RainEffect
extends CPUParticles2D

var started := false

func _ready() -> void:
	emitting = false
	visible = false
	amount = 900
	lifetime = 0.55
	preprocess = 0.4
	emission_shape = EMISSION_SHAPE_RECTANGLE
	direction = Vector2(0.18, 1.0)
	spread = 4.0
	gravity = Vector2(0.0, 160.0)
	initial_velocity_min = 520.0
	initial_velocity_max = 700.0
	particle_flag_align_y = true
	local_coords = true
	color = Color(0.73, 0.87, 1.0, 0.66)
	scale_amount_min = 0.7
	scale_amount_max = 1.2
	var streak_gradient := Gradient.new()
	streak_gradient.colors = PackedColorArray([Color(1, 1, 1, 0), Color.WHITE])
	var streak := GradientTexture2D.new()
	streak.gradient = streak_gradient
	streak.width = 2
	streak.height = 20
	streak.fill_from = Vector2(0.5, 0.0)
	streak.fill_to = Vector2(0.5, 1.0)
	texture = streak
	get_viewport().size_changed.connect(_fit_viewport)
	_fit_viewport()

func _fit_viewport() -> void:
	var size := get_viewport_rect().size
	position = size * 0.5 - Vector2(0.0, 100.0)
	emission_rect_extents = (size + Vector2(160.0, 160.0)) * 0.5

func reset_weather() -> void:
	started = false
	emitting = false
	visible = false

func update_weather(raining: bool, running: bool, heavy: bool) -> void:
	var target_amount := 900 if heavy else 300
	if amount != target_amount:
		amount = target_amount
	if not raining:
		reset_weather()
		return
	if running and not started:
		speed_scale = 1.0
		restart()
		started = true
	visible = started
	emitting = started
	# A paused experiment freezes existing drops; FPS stays live in the HUD.
	speed_scale = 1.0 if running else 0.0
