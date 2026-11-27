extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.blue_ai_enabled = false
	root.add_child(game)
	await physics_frame
	await physics_frame
	var ball = game.get_node("Ball")
	var kicker = game.ready_player
	ball.friction = 0.0
	ball.velocity = Vector2(10, 0)
	check(not game.can_take_shot(kicker), "Even 10 px/s must block aiming")
	ball.receive_slap(ball.position, 1000, kicker, Vector2.UP)
	check(ball.velocity == Vector2(10, 0), "Ball must reject a kick before fully stopping")
	ball.position = Vector2(800, 880)
	var baseline: Dictionary = {}
	for player in game.players:
		baseline[player] = player.position
	await create_timer(0.4).timeout
	for player in game.players:
		check(player.position == baseline[player], "No player may teleport while the ball is creeping")
	ball.friction = 560.0
	await create_timer(0.4).timeout
	check(ball.is_stopped() and game.ready_player != null, "Kicker must prepare once the ball fully stops")
	check(game.ready_player.can_reach(ball), "Stopped ball must have prepared kicker")
	# Restart delay is a minimum, never a forced stop of a still-moving ball.
	game.reset_match()
	ball.friction = 0.0
	ball.position = Vector2(800, 175)
	ball.velocity = Vector2(0, -600)
	ball.last_touch = kicker
	await create_timer(1.7).timeout
	check(not game.pending_restart.is_empty() and not ball.frozen, "Restart must wait beyond 1.5 seconds when the ball still moves")
	ball.friction = 560.0
	await create_timer(1.3).timeout
	check(game.pending_restart.is_empty() and ball.frozen, "Restart must complete after natural stop")
	check(ball.position.distance_to(Vector2(800, 165)) < 0.1, "Waiting for stop must preserve out crossing point")
	# All speeds rebound; only medium/heavy impacts push.
	for speed in [200.0, 600.0, 1200.0]:
		var player = load("res://scenes/paper_player.tscn").instantiate()
		player.position = Vector2(2000, 2032)
		root.add_child(player)
		var sample = load("res://scenes/ball.tscn").instantiate()
		sample.position = Vector2(player.collision_bounds().position.x - 12, player.center().y)
		root.add_child(sample)
		sample.velocity = Vector2(speed, 0)
		await create_timer(0.12).timeout
		if speed < 320.0:
			check(sample.velocity.x < 0, "Below 20% ball must still rebound")
			check(player.position.x == 2000, "Below 20% must not displace player")
		elif speed < 960.0:
			check(sample.velocity.x < 0, "Medium impact must rebound")
			check(player.impact_tier == player.ImpactTier.MEDIUM and player.position.x > 2000, "20-60% must apply medium push")
		else:
			check(sample.velocity.x < 0, "Heavy impact must rebound")
			check(player.impact_tier == player.ImpactTier.HEAVY and player.knockback_velocity.length() > 200, "60%+ must apply heavier push")
		sample.queue_free()
		player.queue_free()
		await process_frame
	# Ratios derive from configured max speed, including the exact thresholds.
	var probe = load("res://scenes/paper_player.tscn").instantiate()
	root.add_child(probe)
	probe.receive_impact(Vector2(199, 0), 1000.0)
	check(probe.knockback_velocity == Vector2.ZERO, "19.9% must not push")
	probe.receive_impact(Vector2(200, 0), 1000.0)
	check(probe.impact_tier == probe.ImpactTier.MEDIUM, "Exactly 20% must push medium")
	probe.knockback_velocity = Vector2.ZERO
	probe.receive_impact(Vector2(600, 0), 1000.0)
	check(probe.impact_tier == probe.ImpactTier.HEAVY, "Exactly 60% must push heavy")
	# Posts remain physical even for slow balls.
	var slow = load("res://scenes/ball.tscn").instantiate()
	slow.position = Vector2(1415, 460)
	root.add_child(slow)
	slow.velocity = Vector2(150, 0)
	await create_timer(0.08).timeout
	check(slow.velocity.x < 0, "Slow ball must still rebound from goal post")
	print("Motion and collision checks completed; failures: ", failures)
	quit(1 if failures else 0)
