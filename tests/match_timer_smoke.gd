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
	current_scene = game
	await physics_frame
	await physics_frame
	var ball = game.get_node("Ball")
	var clock = game.get_node("HUD/MatchClock")
	var crowd = game.get_node("MatchAudio/Crowd")
	var whistle = game.get_node("MatchAudio/Whistle")
	check(game.match_duration == 180 and clock.text == "03:00", "Match must start at three minutes")
	check(game.get_node_or_null("HUD/FullTime") == null, "Match must not contain a custom result screen")
	check(whistle.stream.get_length() > 0, "Whistle WAV must load")
	var initial: float = game.time_remaining
	await create_timer(0.15).timeout
	check(game.time_remaining < initial, "Clock must count down during play")
	game.get_node("PauseMenu")._on_pause_pressed()
	var paused_time: float = game.time_remaining
	await create_timer(0.08).timeout
	var crowd_before: float = crowd.get_playback_position()
	await create_timer(0.2).timeout
	check(is_equal_approx(game.time_remaining, paused_time), "Clock must stop during pause")
	check(crowd.get_playback_position() > crowd_before, "Crowd must continue during pause")
	game.get_node("PauseMenu")._on_resume_pressed()
	await create_timer(0.08).timeout
	check(game.time_remaining < paused_time, "Clock must resume")
	game.time_remaining = 60.0
	game._update_match_clock()
	check(clock.text == "01:00", "Clock must format whole minutes")
	game.reset_match()
	game.score = [2, 1]
	game._queue_restart("Out", 1, Vector2(800, 165), Vector2.DOWN)
	ball.velocity = Vector2(800, 0)
	game.time_remaining = 0.05
	await create_timer(0.12).timeout
	check(game.match_over and clock.text == "00:00", "Zero time must end match")
	check(ball.frozen and ball.play_locked and ball.is_stopped(), "Full time must stop and lock ball")
	check(whistle.playing, "Full time must play whistle")
	check(current_scene == game, "Match must stay visible while whistle is playing")
	check(game.score == [2, 1], "Final score must remain unchanged")
	check(game.pending_restart.is_empty() and game.ready_player == null, "Full time must cancel pending restart")
	game._on_ball_segment(Vector2(1440, 560), Vector2(1460, 560))
	check(game.score == [2, 1], "Late goal must not change score")
	var red = game.get_node("Players/RedPlayer4")
	ball.receive_slap(ball.position, 1000, red, Vector2.RIGHT)
	check(ball.is_stopped() and not game.can_take_shot(red), "Late shots must be rejected")
	game.get_node("PauseMenu")._on_pause_pressed()
	check(not paused and not game.get_node("PauseMenu").visible, "Pause must not interrupt full-time whistle")
	# Reset must cancel both audio and the eventual menu transition.
	var reset_key := InputEventKey.new()
	reset_key.keycode = KEY_R
	reset_key.pressed = true
	game._unhandled_input(reset_key)
	check(not game.match_over and game.time_remaining == 180, "R must reset time")
	check(not whistle.playing, "R must cancel the whistle")
	await create_timer(whistle.stream.get_length() + 0.1).timeout
	check(current_scene == game, "Canceled whistle must not cause stale menu transition")
	game._finish_match()
	await create_timer(0.1).timeout
	check(current_scene == game and whistle.playing, "Menu must not open before whistle finishes")
	var remaining: float = whistle.stream.get_length() - whistle.get_playback_position()
	await create_timer(remaining + 0.2).timeout
	check(current_scene.scene_file_path == "res://scenes/main_menu.tscn", "Whistle finish must automatically return to main menu")
	check(current_scene.get_node("MenuMusic").playing, "Menu music must start after whistle has finished")
	current_scene.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	print("Match timer and whistle checks completed; failures: ", failures)
	quit(1 if failures else 0)
