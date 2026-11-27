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
	var ai = game._blue_ai
	ai.rng.seed = 456
	var ball = game.ball
	var shooter = game.get_node("Players/BluePlayer4")
	var keeper = game._goalkeeper(0)
	for player in game.players:
		if not player.is_goalkeeper:
			player.position = Vector2(1400, 900)
	ball.position = Vector2(700, 560)
	shooter.prepare_kick(ball)
	keeper.position.y = 522 # Body y=490, leaving lower goal area open.
	for attempt in range(20):
		var target: Vector2 = ai._goal_target(game, shooter)
		check(target.y >= 560, "CPU should prefer goal area away from an upper-positioned keeper")
	keeper.position.y = 662 # Body y=630, leaving upper goal area open.
	for attempt in range(20):
		var target: Vector2 = ai._goal_target(game, shooter)
		check(target.y <= 560, "CPU should prefer goal area away from a lower-positioned keeper")
	# Avoid an obstructed passing lane in favor of an open, less pressured teammate.
	ball.position = Vector2(1100, 560)
	shooter.prepare_kick(ball)
	var upper = game.get_node("Players/BluePlayer3")
	var lower = game.get_node("Players/BluePlayer5")
	upper.position = Vector2(700, 432)
	lower.position = Vector2(700, 782)
	game.get_node("Players/RedPlayer1").position = Vector2(900, 512)
	game.get_node("Players/RedPlayer2").position = Vector2(700, 432)
	var teammates: Array[Node2D] = [upper, lower]
	for attempt in range(20):
		check(ai._pass_receiver(game, shooter, teammates) == lower, "CPU should choose clear pass over blocked pressured receiver")
	game.reset_match()
	# Each out taker stays at the line while moving, then rejoins only at zero speed.
	for team in [0, 1]:
		game.reset_match()
		game._award_restart("Out", team, Vector2(800, 165), Vector2.DOWN)
		var taker = game.restart_taker
		var outside: Vector2 = taker.position
		game.aiming_player = taker
		game.drag_start = Vector2.ZERO
		game.drag_end = Vector2(0, -160)
		game.fire_aimed_shot()
		await create_timer(0.25).timeout
		check(not ball.is_stopped() and taker.position == outside, "Out taker must stay outside until ball truly stops")
		ball.velocity = Vector2.ZERO
		game._update_restart_return(0.02)
		check(taker.center().distance_to(Vector2(800, 305)) <= 70, "Out taker must rejoin nearby after full stop while avoiding full-body overlap")
	game.reset_match()
	await create_timer(0.12).timeout
	game.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	print("CPU decision and out timing checks completed; failures: ", failures)
	quit(1 if failures else 0)
