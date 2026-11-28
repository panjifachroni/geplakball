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
	for team in [0, 1]:
		for counter in [false, true]:
			game.reset_match()
			var point := Vector2(1250 if team == 0 else 350, 165)
			game._award_restart("Out", team, point, Vector2.DOWN)
			game._advanced_play.counter_started = counter
			for player in game.players:
				if not player.is_goalkeeper:
					player.position += Vector2(70, 80)
			var defending: int = 1 - team
			var keeper = game._goalkeeper(defending)
			var spot: Vector2 = game._initial_positions[keeper] + keeper.foot_offset()
			# Exercise the delayed restart path as used for an end-line exit.
			game._queue_restart("Tendangan gawang", defending, spot, Vector2.LEFT if defending == 1 else Vector2.RIGHT)
			game.ball.velocity = Vector2.ZERO
			game._restart_remaining = 0.0
			game._physics_process(0.02)
			check(game.restart_taker == keeper and keeper.can_reach(game.ball), "Goal kick must belong to defending keeper")
			check(game._advanced_play.is_empty() and game.restart_formation.is_empty(), "Goal kick must clear attack/counter formation context")
			for player in game.players:
				if not player.is_goalkeeper:
					check(player.position == game._initial_positions[player], "Every field player must regain starting formation")
	game.match_audio.reset_effects()
	await create_timer(0.12).timeout
	game.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	print("Goal kick formation checks completed; failures: ", failures)
	quit(1 if failures else 0)
