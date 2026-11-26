extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func sync_physics() -> void:
	await physics_frame
	await physics_frame

func _run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.blue_ai_enabled = false
	root.add_child(game)
	await sync_physics()
	var ball = game.get_node("Ball")
	var red = game.get_node("Players/RedPlayer4")
	# Aimed shots must follow the pull direction, independent of radial direction.
	game.aiming_player = red
	game.drag_start = Vector2.ZERO
	game.drag_end = Vector2(0, 60)
	game.fire_aimed_shot()
	check(ball.velocity.y < 0 and absf(ball.velocity.x) < 0.1, "Aimed shot must travel upward")
	var weak_speed: float = ball.velocity.length()
	game.reset_match()
	await sync_physics()
	game.aiming_player = red
	game.drag_start = Vector2.ZERO
	game.drag_end = Vector2(0, 240)
	game.fire_aimed_shot()
	check(ball.velocity.length() > weak_speed * 2.0, "Long pull must shoot harder")
	check(ball.velocity.length() > 1100, "Full power must exceed previous speed cap")
	game.reset_match()
	await sync_physics()
	game.aiming_player = red
	game.drag_start = Vector2.ZERO
	game.drag_end = Vector2(1, 1)
	game.fire_aimed_shot()
	check(ball.velocity == Vector2.ZERO, "Click without dragging must not shoot")
	# An unreachable settled ball gets the nearest player teleported to its feet.
	var baseline: Dictionary = {}
	for player in game.players:
		baseline[player] = player.position
	ball.position = Vector2(800, 880)
	var nearest = game._nearest_player(ball.position)
	var old_position: Vector2 = nearest.position
	await create_timer(1.8).timeout
	check(nearest.position.distance_to(old_position) > 50, "Nearest player must approach unreachable ball")
	check(nearest.can_reach(ball), "Teleport must finish within kicking reach")
	check(ball.velocity == Vector2.ZERO, "Approaching must not automatically shoot")
	for player in game.players:
		if player != nearest and not player.is_goalkeeper:
			check(player.position == baseline[player], "Only nearest field player should retrieve; keepers may adjust cover")
	# Automatic retrieval waits for the ball to settle.
	game.reset_match()
	await sync_physics()
	ball.position = Vector2(800, 880)
	ball.velocity = Vector2(700, 0)
	await create_timer(0.2).timeout
	check(game.ready_player == null, "Players must not chase a fast moving ball")
	game.reset_match()
	var obstacle = load("res://scenes/paper_player.tscn").instantiate()
	obstacle.position = Vector2(2000, 2032)
	root.add_child(obstacle)
	ball.global_position = Vector2(1930, 2000)
	ball.velocity = Vector2(900, 0)
	await create_timer(0.18).timeout
	check(ball.velocity.x < 0, "Strong impact must still rebound")
	check(obstacle.position.x > 2001, "Strong impact must displace player")
	check(obstacle.position.x < 2050, "Knockback must remain small")
	await create_timer(0.3).timeout
	check(obstacle.knockback_velocity == Vector2.ZERO, "Knockback must settle")
	obstacle.position = Vector2(2000, 2032)
	ball.global_position = Vector2(1955, 2000)
	ball.velocity = Vector2(300, 0)
	await create_timer(0.12).timeout
	check(obstacle.position.x == 2000, "Weak impacts must not displace players")
	game.reset_match()
	check(ball.global_position == Vector2(800, 560), "Reset must restore ball")
	check(nearest.position == game._initial_positions[nearest], "Reset must restore formation")
	print("Gameplay checks completed; failures: ", failures)
	game.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	quit(1 if failures else 0)
