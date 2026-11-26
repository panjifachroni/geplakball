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
	game.restart_delay = 0.06
	await physics_frame
	await physics_frame
	var ball = game.get_node("Ball")
	var red = game.get_node("Players/RedPlayer4")
	var blue = game.get_node("Players/BluePlayer4")
	check(red.can_reach(ball), "Initial kicker must have ball at feet")
	check(red.foot_position().distance_to(ball.position) < 0.1, "Ball must sit exactly at initial kicker's feet")
	var old_position: Vector2 = red.position
	red.position += Vector2(45, 0)
	check(not red.can_reach(ball), "Player 45 pixels from ball must not reach it")
	red.slap(Vector2.RIGHT, 1000)
	check(ball.velocity == Vector2.ZERO, "Distant slap must not launch the ball")
	red.position = old_position
	red.get_node("SlapTimer").stop()
	red._on_slap_timer_timeout()
	# Sideline: preserve exact segment-line intersection and award opposite team.
	ball.last_touch = red
	game._on_ball_segment(Vector2(600, 180), Vector2(700, 150))
	await create_timer(0.12).timeout
	check(game.restart_kind == "Out", "Top sideline must award out")
	check(game.restart_team == 1 and game.restart_taker.team == 1, "Red last touch must award blue")
	check(ball.position.distance_to(Vector2(650, 165)) < 0.01, "Out must use exact crossing point")
	check(ball.frozen and ball.velocity == Vector2.ZERO, "Restart ball must stop after the delay")
	check(game.restart_taker.foot_position().distance_to(ball.position) < 0.1, "Restart taker must teleport with ball at feet")
	check(not game.can_take_shot(red), "Opponent must not take restart")
	ball.receive_slap(ball.position, 1000, red, Vector2.DOWN)
	check(ball.frozen and ball.velocity == Vector2.ZERO, "Ball must reject a restart by the wrong team")
	game.aiming_player = game.restart_taker
	game.drag_start = Vector2.ZERO
	game.drag_end = Vector2(0, 120)
	game.fire_aimed_shot()
	check(ball.frozen, "Outward restart direction must be rejected")
	game.aiming_player = game.restart_taker
	game.drag_start = Vector2.ZERO
	game.drag_end = Vector2(0, -120)
	game.fire_aimed_shot()
	check(not ball.frozen and ball.velocity.y > 0, "Legal restart must resume play immediately")
	check(game.restart_taker == null, "Restart ownership must clear after legal shot")
	# Right sideline of a defending blue team: red gets upper-right corner.
	game.reset_match()
	ball.last_touch = blue
	game._on_ball_segment(Vector2(1420, 300), Vector2(1450, 310))
	await create_timer(0.12).timeout
	check(game.restart_kind == "Corner" and game.restart_team == 0, "Blue defender exit must award red corner")
	check(ball.position == Vector2(1435, 165), "Upper-right corner must sit exactly on corner")
	check(game.restart_taker.team == 0, "Corner taker must belong to opponent")
	# Left defending red team: blue gets lower-left corner.
	game.reset_match()
	ball.last_touch = red
	game._on_ball_segment(Vector2(180, 850), Vector2(150, 860))
	await create_timer(0.12).timeout
	check(game.restart_kind == "Corner" and game.restart_team == 1, "Red defender exit must award blue corner")
	check(ball.position == Vector2(165, 955), "Lower-left corner position must be exact")
	# Attacker over goal line: defender gets restart at original crossing.
	game.reset_match()
	ball.last_touch = red
	game._on_ball_segment(Vector2(1420, 800), Vector2(1450, 820))
	await create_timer(0.12).timeout
	check(game.restart_kind == "Tendangan gawang" and game.restart_team == 1, "Attacker exit must award defender goal kick")
	var keeper = game.get_node("Players/BlueGoalkeeper")
	var keeper_spot: Vector2 = game._initial_positions[keeper] + keeper.foot_offset()
	check(ball.position == keeper_spot and game.restart_taker == keeper, "Goal kick must use blue keeper and keeper position")
	# Earliest crossing must win when a fast diagonal traverses two boundaries.
	var first_exit: Dictionary = game.find_exit(Vector2(1400, 180), Vector2(1500, 100))
	check(first_exit.side == "top", "Earliest diagonal crossing must win")
	check(first_exit.point.distance_to(Vector2(1418.75, 165)) < 0.01, "Diagonal intersection must be precise")
	# Real physics movement must trigger a restart, not just direct callbacks.
	game.reset_match()
	ball.position = Vector2(800, 175)
	ball.last_touch = blue
	ball.velocity = Vector2(0, -1000)
	await create_timer(0.15).timeout
	check(not game.pending_restart.is_empty() and not ball.frozen, "Live out must wait while the ball still moves")
	await create_timer(1.85).timeout
	check(game.restart_kind == "Out" and game.restart_team == 0, "Live physics crossing must award opposite team")
	check(ball.position.distance_to(Vector2(800, 165)) < 0.01 and ball.frozen, "Live out must remain on line without repeated exits")
	# Crossing between posts is a goal rather than a corner.
	game.reset_match()
	ball.last_touch = red
	game._on_ball_segment(Vector2(1420, 560), Vector2(1460, 560))
	await create_timer(game._restart_remaining + 0.1).timeout
	check(game.score == [1, 0], "Right goal must score for red")
	check(game.restart_kind == "Gol! Kickoff" and game.restart_team == 1, "Conceding team must get kickoff")
	check(ball.position == Vector2(800, 560), "Kickoff must return to center")
	game.reset_match()
	check(game.score == [0, 0] and game.restart_taker == null and not ball.frozen, "R must clear restart and score state")
	print("Restart checks completed; failures: ", failures)
	game.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	quit(1 if failures else 0)
