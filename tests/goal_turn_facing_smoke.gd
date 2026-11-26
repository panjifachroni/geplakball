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
	var red = game.get_node("Players/RedPlayer4")
	var blue = game.get_node("Players/BluePlayer4")
	var teammate = game.get_node("Players/RedPlayer1")
	# A center crossing, partial overlap, and exact line tangency are all non-goals.
	for pair in [
		[Vector2(1420, 560), Vector2(1435, 560)],
		[Vector2(1435, 560), Vector2(1440, 560)],
		[Vector2(1440, 560), Vector2(1450, 560)],
	]:
		game._on_ball_segment(pair[0], pair[1])
		check(game.score == [0, 0] and game.pending_restart.is_empty(), "Partial right-line crossing must not score")
	game._on_ball_segment(Vector2(1450, 560), Vector2(1450.1, 560))
	check(game.score == [1, 0], "Entire ball beyond right line must score")
	game.reset_match()
	for pair in [
		[Vector2(180, 560), Vector2(165, 560)],
		[Vector2(165, 560), Vector2(155, 560)],
		[Vector2(155, 560), Vector2(150, 560)],
	]:
		game._on_ball_segment(pair[0], pair[1])
		check(game.score == [0, 0] and game.pending_restart.is_empty(), "Partial left-line crossing must not score")
	game._on_ball_segment(Vector2(150, 560), Vector2(149.9, 560))
	check(game.score == [0, 1], "Entire ball beyond left line must score")
	game.reset_match()
	# Predictive goal audio must use the same full-ball test.
	ball.position = Vector2(1438, 560)
	ball.velocity = Vector2(60, 0)
	game._predict_goal_audio()
	check(not game.match_audio.get_node("Goal").playing, "Ball stopping on white line must not predict a goal")
	# A tiny kick leaves the previous kicker closest, but another player must retrieve.
	game.reset_match()
	for player in game.players:
		player.position = Vector2(300, 300)
	ball.position = Vector2(800, 560)
	red.prepare_kick(ball)
	blue.position = Vector2(900, 592)
	teammate.position = Vector2(950, 592)
	game.ready_player = red
	ball.receive_slap(red.center(), 60, red, Vector2.RIGHT)
	await create_timer(0.5).timeout
	check(ball.is_stopped() and ball.last_kicker == red, "Tiny shot must settle with original kicker recorded")
	check(game.ready_player == blue and blue.can_reach(ball), "Nearest eligible opponent must retrieve instead of previous kicker")
	check(not game.can_take_shot(red), "Previous kicker must be ineligible")
	ball.last_touch = teammate
	ball.receive_slap(red.center(), 1000, red, Vector2.RIGHT)
	check(ball.velocity == Vector2.ZERO, "Passive touch must not unlock the previous kicker")
	ball.receive_slap(blue.center(), 60, blue, Vector2.LEFT)
	await create_timer(0.5).timeout
	check(ball.last_kicker == blue and game.ready_player == red, "Different player's kick must make original kicker eligible again")
	# Selection is across both teams; a closer teammate may also take the next kick.
	game.reset_match()
	for player in game.players:
		player.position = Vector2(300, 300)
	ball.position = Vector2(800, 560)
	red.prepare_kick(ball)
	teammate.position = Vector2(850, 592)
	blue.position = Vector2(950, 592)
	game.ready_player = red
	ball.receive_slap(red.center(), 60, red, Vector2.RIGHT)
	await create_timer(0.5).timeout
	check(game.ready_player == teammate, "Closest teammate must be eligible; no forced team alternation")
	# Keeper coverage shifts the entire body vertically; sprites never rotate.
	game.reset_match()
	var keeper = game.get_node("Players/BlueGoalkeeper")
	var keeper_home: Vector2 = keeper.position
	var original_foot: Vector2 = keeper.foot_offset()
	red.position = Vector2(600, 250)
	game.ready_player = red
	game._update_keeper_position(1.0)
	check(keeper.position.y < keeper_home.y, "Shooter above must shift keeper toward upper post")
	red.position = Vector2(600, 850)
	game._update_keeper_position(1.0)
	check(keeper.position.y > keeper_home.y, "Shooter below must shift keeper toward lower post")
	check(absf(keeper.position.y - keeper_home.y) <= game.keeper_cover_distance, "Coverage shift must stay modest and between posts")
	check(keeper.position.x == keeper_home.x and keeper.foot_offset() == original_foot, "Coverage must preserve horizontal depth and local foot offset")
	check(keeper.get_node("Sprite2D").rotation == 0 and keeper.get_node("Body").rotation == 0, "Neither sprite nor collision may rotate")
	var covered_position: Vector2 = keeper.position
	ball.velocity = Vector2(100, 0)
	red.position = Vector2(600, 200)
	game._update_keeper_position(1.0)
	check(keeper.position == covered_position, "Keeper must hold selected coverage during ball flight")
	ball.velocity = Vector2.ZERO
	red.position = Vector2(600, 592)
	game._update_keeper_position(1.0)
	check(keeper.position == keeper_home, "Central shooter must center keeper again")
	red.position = Vector2(600, 850)
	game._update_keeper_position(0.05)
	check(keeper.position.y > keeper_home.y and keeper.position.y - keeper_home.y <= 9.01, "Coverage shift must move smoothly at configured speed")
	var left_keeper = game.get_node("Players/RedGoalkeeper")
	var left_home: Vector2 = game._keeper_homes[left_keeper]
	blue.position = Vector2(1000, 850)
	game.ready_player = blue
	game._update_keeper_position(1.0)
	check(left_keeper.position.y > left_home.y, "Left keeper must also cover lower opposition shooter")
	blue.position = Vector2(1000, 200)
	game._update_keeper_position(1.0)
	check(left_keeper.position.y < left_home.y, "Left keeper must also cover upper opposition shooter")
	game.reset_match()
	check(ball.last_kicker == null, "Reset must clear last kicker lock")
	game.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	print("Goal, turn and facing checks completed; failures: ", failures)
	quit(1 if failures else 0)
