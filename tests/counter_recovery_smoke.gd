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
	var ball = game.ball
	for team in [0, 1]:
		for kind in ["Out", "Corner"]:
			game.reset_match()
			var original: Dictionary = {}
			for player in game.players:
				original[player] = player.position
			var progress := 0.75 if kind == "Out" else 1.0
			var x: float = progress if team == 0 else 1.0 - progress
			var point: Vector2 = game.PITCH.position + Vector2(x * game.PITCH.size.x, 0)
			game._award_restart(kind, team, point, Vector2.DOWN)
			check(not game._advanced_play.is_empty(), "Advanced restart must remember pre-formation positions")
			var taker = game.restart_taker
			ball.receive_slap(taker.center(), 500, taker, Vector2.DOWN)
			game.restart_taker = null
			game.restart_kind = ""
			check(not game._advanced_play.counter_started, "Original attacking kick must not count as counter")
			var counter = game.get_node("Players/BluePlayer3" if team == 0 else "Players/RedPlayer3")
			var keeper = game._goalkeeper(team)
			ball.velocity = Vector2.ZERO
			ball.position = keeper.center() + Vector2(250 if team == 0 else -250, 0)
			counter.prepare_kick(ball)
			ball.receive_slap(counter.center(), 600, counter, Vector2.LEFT if team == 0 else Vector2.RIGHT)
			check(game._advanced_play.counter_started, "Opposing deliberate kick must start counter state")
			var counter_positions: Dictionary = {}
			for player in game.players:
				if player.team != team and not player.is_goalkeeper:
					counter_positions[player] = player.center()
			ball.velocity = Vector2.ZERO
			ball.position = keeper.foot_position()
			var keeper_position: Vector2 = keeper.position
			game.ready_player = null
			game._pickup_locked = false
			game._ensure_ready_kicker()
			check(game.ready_player == keeper and keeper.can_reach(ball), "Keeper must retain ball at feet after winning counter")
			check(keeper.position == keeper_position, "Formation reset must not teleport keeper away from possession")
			for player in game.players:
				if player.team == team and not player.is_goalkeeper:
					check(player.position.distance_to(original[player]) <= 144.1, "Previously advanced players must return near pre-restart positions with safe spacing")
				elif counter_positions.has(player):
					var back := -1.0 if player.team == 0 else 1.0
					var expected: Vector2 = counter_positions[player] + Vector2(back * 80, 0)
					expected = expected.clamp(game.PITCH.position + Vector2(35, 35), game.PITCH.end - Vector2(35, 35))
					var bounds: Rect2 = player.placement_bounds(player.global_position)
					var behind: bool = bounds.end.x < 800 if player.team == 0 else bounds.position.x > 800
					check(behind or player.center().distance_to(expected) <= 96.1, "Countering side must retreat, with two supports behind halfway")
			check(game._advanced_play.is_empty(), "Counter reset must run only once")
			game._ensure_ready_kicker()
			check(game.ready_player == keeper, "Rechecking possession must keep keeper selected")
	# A mere rebound off the other team is not a deliberate counterattack.
	game.reset_match()
	game._award_restart("Out", 0, Vector2(1181, 165), Vector2.DOWN)
	var taker = game.restart_taker
	ball.receive_slap(taker.center(), 500, taker, Vector2.DOWN)
	game.restart_taker = null
	ball.velocity = Vector2.ZERO
	var keeper = game._goalkeeper(0)
	ball.position = keeper.foot_position()
	ball.last_touch = game.get_node("Players/BluePlayer3")
	game._pickup_locked = false
	game.ready_player = null
	game._ensure_ready_kicker()
	check(not game._advanced_play.is_empty(), "Passive touch alone must not reset attacking formation")
	game.reset_match()
	check(game._advanced_play.is_empty(), "R must clear remembered formation")
	await create_timer(0.12).timeout
	game.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	print("Counter recovery checks completed; failures: ", failures)
	quit(1 if failures else 0)
