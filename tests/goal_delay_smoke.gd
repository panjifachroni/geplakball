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
	root.add_child(game)
	await physics_frame
	await physics_frame
	var ball = game.get_node("Ball")
	var red = game.get_node("Players/RedPlayer4")
	var blue_keeper = game.get_node("Players/BlueGoalkeeper")
	check(is_equal_approx(game.restart_delay, 1.5), "Default restart delay must be 1.5 seconds")
	# Goal posts must rebound before the ball can cross the goal line.
	ball.position = Vector2(1400, 460)
	ball.velocity = Vector2(1000, 0)
	ball.last_touch = red
	await create_timer(0.1).timeout
	check(ball.velocity.x < 0, "Right upper post must rebound the ball")
	check(game.pending_restart.is_empty() and game.score == [0, 0], "Post strike must not be counted as goal/out")
	game.reset_match()
	ball.position = Vector2(200, 660)
	ball.velocity = Vector2(-1000, 0)
	await create_timer(0.1).timeout
	check(ball.velocity.x > 0, "Left lower post must rebound the ball")
	check(game.pending_restart.is_empty(), "Left post strike must keep play alive")
	# Goal stays visible in the net while the restart is pending.
	game.reset_match()
	blue_keeper.position = Vector2(1300, 800)
	ball.position = Vector2(1400, 560)
	ball.velocity = Vector2(1000, 0)
	ball.last_touch = red
	await create_timer(0.12).timeout
	check(not game.pending_restart.is_empty(), "Goal must create pending restart")
	check(game.score == [1, 0], "Goal must count once immediately")
	check(not ball.frozen and ball.play_locked, "Pending goal must allow motion but reject kicks")
	check(ball.position.x > 1435 and ball.position.x <= 1481, "Net back must retain ball inside goal")
	check(ball.velocity.x < 0, "Back net must rebound the moving ball")
	check(not game.can_take_shot(red), "Kicks must be disabled during goal delay")
	var snapshot: Vector2 = ball.velocity
	ball.receive_slap(ball.position, 1400, red, Vector2.UP)
	check(ball.velocity == snapshot, "Ball must ignore slap during pending restart")
	await create_timer(0.3).timeout
	check(game.score == [1, 0] and not game.pending_restart.is_empty(), "Net rebounds must not duplicate the goal")
	check(ball.position != Vector2(800, 560), "Kickoff must not happen early")
	await create_timer(game._restart_remaining + 0.1).timeout
	check(game.pending_restart.is_empty() and ball.frozen, "Goal restart must follow the goal audio cue")
	check(ball.position == Vector2(800, 560) and game.restart_team == 1, "Goal must end in opponent kickoff")
	# Snapshot the original out point even if the ball later moves elsewhere.
	game.reset_match()
	ball.position = Vector2(800, 175)
	ball.velocity = Vector2(0, -900)
	ball.last_touch = red
	await create_timer(0.15).timeout
	check(not game.pending_restart.is_empty() and not ball.frozen, "Out ball must continue moving during delay")
	check(ball.position.y < 165, "Out ball must travel beyond touchline")
	await create_timer(1.5).timeout
	check(ball.position.distance_to(Vector2(800, 165)) < 0.1, "Delayed out must restore original crossing point")
	check(game.restart_team == 1 and ball.frozen, "Delayed out must preserve original opposite team")
	# Goal kicks go to the keeper's home side, even when keeper was displaced.
	game.reset_match()
	blue_keeper.position = Vector2(1100, 300)
	ball.last_touch = red
	game._on_ball_segment(Vector2(1420, 800), Vector2(1450, 820))
	await create_timer(1.6).timeout
	check(game.restart_taker == blue_keeper, "Goalkeeper must take defensive goal kick")
	check(ball.position == game._initial_positions[blue_keeper] + blue_keeper.foot_offset(), "Goal kick must use keeper home position")
	check(blue_keeper.can_reach(ball), "Goal kick must put ball at keeper feet")
	# Reset cancels pending decisions without a stale delayed teleport.
	game.reset_match()
	ball.last_touch = red
	game._on_ball_segment(Vector2(600, 180), Vector2(700, 150))
	game.reset_match()
	await create_timer(1.6).timeout
	check(game.pending_restart.is_empty() and game.restart_taker == null, "R must cancel pending restart")
	check(not ball.play_locked and not ball.frozen, "R must unlock play")
	print("Goal and delay checks completed; failures: ", failures)
	game.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	quit(1 if failures else 0)
