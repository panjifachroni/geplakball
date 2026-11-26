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
	var kicker = game.get_node("Players/RedPlayer4")
	var teammate = game.get_node("Players/RedPlayer1")
	var opponent = game.get_node("Players/BluePlayer4")
	for reverse in [false, true]:
		game.reset_match()
		for player in game.players:
			player.position = Vector2(250, 250)
		ball.position = Vector2(800, 560)
		ball.last_kicker = kicker
		kicker.position = Vector2(800, 592)
		var closer = teammate if reverse else opponent
		var farther = opponent if reverse else teammate
		closer.position = Vector2(800, 582) # Body 10 px away, but not already at the ball's feet.
		farther.prepare_kick(ball) # Body about 49 px away, feet touching ball.
		check(closer.center().distance_to(ball.position) < farther.center().distance_to(ball.position), "Fixture must have a strictly closer player")
		game.ready_player = farther
		game._pickup_locked = false
		game._ensure_ready_kicker()
		check(game.ready_player == closer, "Cached in-range player must not skip a closer player of either team")
		check(closer.can_reach(ball), "Chosen closest player must be prepared to kick")
		check(not game.can_take_shot(farther) and game.can_take_shot(closer), "Only selected player can take the kick")
		check(game.ready_player != kicker, "Previous kicker must remain excluded even if physically closest")
		for repeat in range(5):
			game._ensure_ready_kicker()
			check(game.ready_player == closer, "Teleporting selected player must not cause ownership oscillation")
		# Blue automation must not substitute a different blue teammate.
		if closer.team == 1:
			game.blue_ai_enabled = true
			game._blue_ai.tick(game, 0.0)
			check(game._blue_ai.actor == closer, "AI must use exactly the selected nearest blue player")
			game.blue_ai_enabled = false
			game._blue_ai.reset()
	# A real tiny shot must select from both teams, despite passive last-touch changes.
	game.reset_match()
	for player in game.players:
		player.position = Vector2(250, 250)
	ball.position = Vector2(800, 560)
	kicker.prepare_kick(ball)
	opponent.position = Vector2(850, 592)
	teammate.position = Vector2(950, 592)
	game.ready_player = kicker
	ball.receive_slap(kicker.center(), 60, kicker, Vector2.RIGHT)
	ball.last_touch = opponent
	await create_timer(0.18).timeout
	check(ball.is_stopped() and game.ready_player == opponent, "Live stopped ball must go to nearest eligible player immediately")
	game.reset_match()
	for player in game.players:
		player.position = Vector2(250, 250)
	ball.position = Vector2(800, 560)
	kicker.prepare_kick(ball)
	teammate.position = Vector2(850, 592)
	opponent.position = Vector2(950, 592)
	game.ready_player = kicker
	ball.receive_slap(kicker.center(), 60, kicker, Vector2.RIGHT)
	await create_timer(0.18).timeout
	check(game.ready_player == teammate, "Closer teammate must still be allowed; no forced opposing-team turn")
	game.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	print("Nearest pickup checks completed; failures: ", failures)
	quit(1 if failures else 0)
