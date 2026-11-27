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
	var ai = game._blue_ai
	ai.rng.seed = 314159
	check(game.blue_ai_enabled, "Casual blue AI must be enabled by default")
	check(game.can_human_take_shot(game.ready_player), "Human must control ready red player")
	await create_timer(2.1).timeout
	check(ball.last_kicker == null and ai.actor == null, "AI must never steal red's turn")
	# Normal CPU still has a human-readable thinking delay, including pause/resume.
	var keeper = game.get_node("Players/BlueGoalkeeper")
	var spot: Vector2 = game._initial_positions[keeper] + keeper.foot_offset()
	game._award_restart("Tendangan gawang", 1, spot, Vector2.LEFT)
	ai.tick(game, 0.0)
	check(ai.actor == keeper and ai.think_remaining >= 0.8 and ai.think_remaining <= 1.4, "Normal CPU must think for 0.8-1.4 seconds")
	check(not game.can_human_take_shot(keeper), "Human must not control blue while AI is enabled")
	await create_timer(0.25).timeout
	check(ball.frozen and ball.last_kicker == null, "AI must not kick instantly")
	game.get_node("PauseMenu")._on_pause_pressed()
	var thinking: float = ai.think_remaining
	await create_timer(0.2).timeout
	check(is_equal_approx(ai.think_remaining, thinking) and ball.frozen, "AI thinking must freeze during pause")
	game.get_node("PauseMenu")._on_resume_pressed()
	await create_timer(maxf(0.1, ai.think_remaining - 0.2)).timeout
	check(game.aiming_player == keeper, "AI must briefly show its aim before shooting")
	await create_timer(0.3).timeout
	check(ball.last_kicker == keeper and not ball.frozen, "Blue must automatically take legal goal kick")
	check(game.restart_taker == null, "AI kick must clear restart ownership through normal rules")
	# Randomized plans should contain both passes and shots, not perfect repeated shots.
	game.reset_match()
	ball.position = Vector2(1100, 560)
	var blue = game.get_node("Players/BluePlayer4")
	blue.prepare_kick(ball)
	var kinds: Dictionary = {}
	var powers: Dictionary = {}
	for attempt in range(100):
		var plan: Dictionary = ai.choose_shot(game, blue)
		kinds[plan.kind] = true
		powers[int(plan.strength)] = true
		check(plan.strength >= game.MIN_SHOT and plan.strength <= game.MAX_SHOT, "AI must use same strength limits as human")
		check(is_equal_approx(plan.direction.length(), 1.0), "AI direction must be normalized")
	check(kinds.has("pass") and kinds.has("shot") and powers.size() > 3, "AI must mix passes/shots with varied power")
	# Every restart uses legal inward directions, even after accuracy variation.
	for setup in [
		[Vector2(165, 165), Vector2(1, 1)],
		[Vector2(165, 955), Vector2(1, -1)],
		[Vector2(1435, 165), Vector2(-1, 1)],
		[Vector2(1435, 955), Vector2(-1, -1)],
	]:
		game.reset_match()
		game._award_restart("Corner", 1, setup[0], setup[1])
		var taker = game.restart_taker
		for attempt in range(12):
			var plan: Dictionary = ai.choose_shot(game, taker)
			check(game._restart_direction_valid(plan.direction), "AI corner must point inside both boundary lines")
		ai.tick(game, 0.0)
		ai.think_remaining = 0.01
		await create_timer(0.06).timeout
		check(ball.last_kicker == taker and not ball.frozen, "AI must actually execute corner via ordinary shot code")
	# Unreachable blue player is selected by the same nearest-player retrieval logic.
	game.reset_match()
	ball.position = Vector2(1050, 650)
	game.ready_player = null
	game._ensure_ready_kicker()
	check(game.ready_player.team == 1 and game.ready_player.can_reach(ball), "Nearest blue must prepare automatically")
	ai.tick(game, 0.0)
	check(ai.actor == game.ready_player, "AI must pick up blue open-play turns")
	game.reset_match()
	check(ai.actor == null and ai.decision.is_empty(), "R must cancel queued AI shot")
	await create_timer(2.1).timeout
	check(ball.last_kicker == null, "Canceled AI shot must not fire in a new red turn")
	game._award_restart("Out", 1, Vector2(800, 165), Vector2.DOWN)
	ai.tick(game, 0.0)
	game._finish_match()
	ai.tick(game, 5.0)
	check(ai.actor == null and ball.frozen and ball.is_stopped(), "Full time must cancel AI and reject late shots")
	game.reset_match()
	game.blue_ai_enabled = false
	game._award_restart("Out", 1, Vector2(800, 165), Vector2.DOWN)
	check(game.can_human_take_shot(game.restart_taker), "Disabling AI must restore manual blue control")
	ai.tick(game, 5.0)
	check(ai.actor == null and ball.frozen, "Disabled AI must never fire")
	game.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	print("Casual AI checks completed; failures: ", failures)
	quit(1 if failures else 0)
