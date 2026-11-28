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
	var audio = game.get_node("MatchAudio")
	var goal = audio.get_node("Goal")
	var missed = audio.get_node("Missed")
	var keeper = game.get_node("Players/BlueGoalkeeper")
	var attacker = game.get_node("Players/RedPlayer4")
	# Early post cue: play before any physical contact.
	ball.position = Vector2(1320, 460)
	ball.velocity = Vector2(1000, 0)
	ball.last_touch = attacker
	game._update_chance_audio()
	check(missed.playing and ball.velocity.x > 0, "Post cue must play before ball reaches post")
	check(ball.position.x == 1320 and game.score == [0, 0], "Prediction must not move ball or score")
	# A keeper physically in the way must block the goal prediction.
	game.reset_match()
	keeper.position = Vector2(1400, 592)
	await physics_frame
	await physics_frame
	ball.position = Vector2(1320, 560)
	ball.velocity = Vector2(1000, 0)
	ball.last_touch = attacker
	game._update_chance_audio()
	check(not goal.playing and missed.playing, "Near chance must play missed reaction even when keeper can save")
	# A near miss can anticipate crossing, while a wide miss stays silent.
	game.reset_match()
	ball.position = Vector2(1320, 430)
	ball.velocity = Vector2(1000, 0)
	ball.last_touch = attacker
	game._update_chance_audio()
	check(missed.playing and game.pending_restart.is_empty(), "Near miss cue must precede actual exit")
	game.reset_match()
	ball.position = Vector2(1320, 800)
	ball.velocity = Vector2(1000, 0)
	ball.last_touch = attacker
	game._update_chance_audio()
	check(not goal.playing and not missed.playing, "Wide exit must not produce early reaction")
	game.reset_match()
	ball.position = Vector2(1400, 560)
	ball.velocity = Vector2(60, 0)
	game._update_chance_audio()
	check(not goal.playing, "Ball that will stop before line must not trigger goal cue")
	# Chance reaction starts first; a confirmed goal replaces it without overlap.
	game.reset_match()
	keeper.position = Vector2(1300, 800)
	await physics_frame
	await physics_frame
	ball.position = Vector2(1320, 560)
	ball.velocity = Vector2(1000, 0)
	ball.last_touch = attacker
	game._update_chance_audio()
	check(missed.playing and not goal.playing and game.score == [0, 0], "Near attempt must start missed reaction before actual goal")
	for frame in range(24):
		if game.score == [1, 0]:
			break
		await physics_frame
	await create_timer(0.04).timeout
	check(game.score == [1, 0], "Actual crossing must still award exactly one goal")
	var elapsed: float = goal.get_playback_position()
	check(goal.playing and not missed.playing and elapsed < 0.5, "Confirmed goal must stop missed reaction and begin goal sound")
	var expected: float = goal.stream.get_length() - elapsed - 0.3
	check(absf(game._restart_remaining - expected) < 0.12, "Kickoff countdown must subtract already-played goal audio")
	await create_timer(maxf(0.0, game._restart_remaining + 0.04)).timeout
	check(game.pending_restart.is_empty() and game.restart_kind == "Gol! Kickoff", "Early goal cue must still finish in kickoff")
	var tail: float = goal.stream.get_length() - goal.get_playback_position()
	check(goal.playing and tail > 0.12 and tail < 0.5, "Kickoff must retain roughly 0.3 seconds of audio")
	game.reset_match()
	check(not goal.playing and not missed.playing, "Reset must cancel anticipated sounds")
	game.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	print("Audio prediction checks completed; failures: ", failures)
	quit(1 if failures else 0)
