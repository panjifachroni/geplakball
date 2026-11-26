extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func check_scores(game: Node2D, red: int, blue: int) -> void:
	check(game.get_node("HUD/ScoreRed").text == str(red), "Red score label must match match state")
	check(game.get_node("HUD/ScoreRedShadow").text == str(red), "Red shadow must match red score")
	check(game.get_node("HUD/ScoreBlue").text == str(blue), "Blue score label must match match state")
	check(game.get_node("HUD/ScoreBlueShadow").text == str(blue), "Blue shadow must match blue score")

func _run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.blue_ai_enabled = false
	root.add_child(game)
	await physics_frame
	await physics_frame
	check_scores(game, 0, 0)
	check(game.get_node("HUD/TextureRect").texture.resource_path == "res://aset/ScoreBoard.png", "New scoreboard artwork must be preserved")
	check(game.get_node("HUD/MatchClock").text == "03:00", "Three-minute clock must exist alongside scoreboard")
	check(game.get_node_or_null("HUD/Score") == null, "Old combined score label must not be required")
	game._on_ball_segment(Vector2(1440, 560), Vector2(1460, 560))
	check_scores(game, 1, 0)
	game.pending_restart.clear()
	game.ball.reset_ball()
	game._on_ball_segment(Vector2(160, 560), Vector2(140, 560))
	check_scores(game, 1, 1)
	game.reset_match()
	check_scores(game, 0, 0)
	check(game.get_node("HUD/MatchClock").text == "03:00", "Reset must update timer immediately")
	game.score = [12, 9]
	game._update_scoreboard()
	check_scores(game, 12, 9)
	game.time_remaining = 0.01
	await create_timer(0.05).timeout
	check(game.match_over and game.get_node("HUD/MatchClock").text == "00:00", "Full time must still update the clock")
	check_scores(game, 12, 9)
	check(game.get_node("MatchAudio/Whistle").playing, "Full time must preserve whistle behavior with new scoreboard")
	check(game.get_node_or_null("HUD/FullTime") == null, "No result UI should be reintroduced by conflict resolution")
	game.reset_match()
	check_scores(game, 0, 0)
	game.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	print("Scoreboard checks completed; failures: ", failures)
	quit(1 if failures else 0)
