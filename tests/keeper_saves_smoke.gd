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
	var saves = game._keeper_saves
	saves.rng.seed = 42
	for team in [0, 1]:
		game.reset_match()
		var keeper = game._goalkeeper(team)
		keeper.position.y = 652 # Body at y=620; incoming shot aims toward top.
		ball.position = Vector2(600 if team == 0 else 1000, 490)
		ball.velocity = Vector2(-900 if team == 0 else 900, 0)
		game.ready_player = null
		var start: Vector2 = keeper.position
		saves.update(game, keeper, 0.1)
		check(keeper.position == start, "Keeper must have visible reaction delay")
		for frame in range(40):
			saves.update(game, keeper, 0.05)
		check(keeper.position.y < start.y and keeper.position.x == start.x, "Save must move vertically toward shot")
		check(keeper.position.distance_to(start) <= game.keeper_save_max_move + 0.01, "One read must respect 75 px movement budget")
		check(keeper.center().y > 510, "Keeper must not perfectly cross whole mouth to every shot")
		var covered: Vector2 = keeper.position
		ball.velocity = -ball.velocity
		saves.update(game, keeper, 0.5)
		check(keeper.position == covered, "Keeper must not chase a ball moving away")
	game.reset_match()
	var keeper = game.get_node("Players/BlueGoalkeeper")
	keeper.position.y = 612 # Body y=580, just outside a static sweep at y=620.
	ball.position = Vector2(1320, 620)
	ball.velocity = Vector2(1000, 0)
	saves.reads[keeper] = {"wait": 0.0, "target_y": 620.0, "budget": 75.0}
	game._update_chance_audio()
	check(not game.match_audio.get_node("Goal").playing, "Goal cue must not pre-celebrate a path the moving keeper can still save")
	check(game.match_audio.get_node("Missed").playing, "Keeper save chance must still trigger near-shot crowd reaction")
	game.reset_match()
	ball.position = Vector2(1000, 620)
	ball.velocity = Vector2(800, 0)
	ball.last_kicker = game.get_node("Players/RedPlayer4")
	ball.last_touch = ball.last_kicker
	var start: Vector2 = keeper.position
	await create_timer(0.12).timeout
	check(keeper.position == start, "Live keeper must not react instantly")
	await create_timer(0.23).timeout
	check(keeper.position.y > start.y and keeper.position.y - start.y < 35, "Live save must be gradual and bounded by speed")
	await create_timer(0.35).timeout
	check(ball.last_touch == keeper and game.score == [0, 0], "Moving keeper must be able to make a real collision save")
	game.reset_match()
	check(saves.reads.is_empty(), "Reset must clear keeper reaction state")
	await create_timer(0.12).timeout
	game.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	print("Keeper save checks completed; failures: ", failures)
	quit(1 if failures else 0)
