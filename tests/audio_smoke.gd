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
	var audio = game.get_node("MatchAudio")
	var ball = game.get_node("Ball")
	var kick = audio.get_node("Kick")
	var crowd = audio.get_node("Crowd")
	var missed = audio.get_node("Missed")
	var goal = audio.get_node("Goal")
	for player in [crowd, kick, missed, goal]:
		check(player.stream.get_length() > 0, "Each WAV must load and have a duration")
		print(player.name, " duration: ", player.stream.get_length())
	check(crowd.playing and crowd.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "Crowd must start with match and loop")
	# A successful kick, rather than aiming or a rejected shot, triggers the effect.
	game.aiming_player = game.ready_player
	game.drag_start = Vector2.ZERO
	game.drag_end = Vector2(0, 100)
	game.fire_aimed_shot()
	check(kick.playing, "Successful kick must play kick audio")
	game.reset_match()
	check(crowd.playing and not kick.playing, "Reset must preserve crowd and clear effects")
	# Ordinary sideline out must never produce a missed-shot reaction.
	game._on_ball_segment(Vector2(600, 180), Vector2(700, 150))
	check(not missed.playing, "Ordinary out must be silent apart from crowd")
	game.reset_match()
	# Actual post collision triggers missed shot; net collisions after goal do not.
	ball.position = Vector2(1400, 460)
	ball.velocity = Vector2(1000, 0)
	await create_timer(0.1).timeout
	check(missed.playing, "Post collision must play missed-shot audio")
	var miss_time: float = missed.get_playback_position()
	game._on_goal_post_hit()
	check(missed.get_playback_position() >= miss_time, "Repeated post contacts in same shot must not restart reaction")
	game.reset_match()
	ball.last_touch = game.get_node("Players/RedPlayer4")
	game._on_ball_segment(Vector2(1420, 430), Vector2(1450, 430))
	check(missed.playing, "Attacking exit narrowly outside post must play missed shot")
	game.reset_match()
	ball.last_touch = game.get_node("Players/RedPlayer4")
	game._on_ball_segment(Vector2(1420, 800), Vector2(1450, 800))
	check(not missed.playing, "Wide miss far from goal must not play reaction")
	game.reset_match()
	ball.last_touch = game.get_node("Players/RedPlayer4")
	game._on_ball_segment(Vector2(1420, 560), Vector2(1460, 560))
	check(goal.playing and not missed.playing, "Goal must play goal audio and suppress missed shot")
	var delay: float = audio.goal_kickoff_delay()
	check(absf(delay + goal.get_playback_position() - (goal.stream.get_length() - 0.3)) < 0.08, "Kickoff target must be 0.3 seconds before goal audio end")
	# Exercise the existing pause menu action, not just an audio process-mode check.
	Input.action_press("ui_cancel")
	game.get_node("PauseMenu")._input(InputEventAction.new())
	Input.action_release("ui_cancel")
	check(paused, "Pause menu must pause match")
	await create_timer(0.08).timeout
	var crowd_before: float = crowd.get_playback_position()
	var goal_before: float = goal.get_playback_position()
	var remaining: float = game._restart_remaining
	await create_timer(0.2).timeout
	check(crowd.playing and crowd.get_playback_position() > crowd_before, "Crowd must keep advancing while paused")
	check(is_equal_approx(game._restart_remaining, remaining), "Goal kickoff countdown must pause with match")
	check(absf(goal.get_playback_position() - goal_before) < 0.04, "Goal audio must pause with goal countdown")
	game.get_node("PauseMenu")._on_resume_pressed()
	check(not paused, "Resume must restore match")
	# The ball is already stopped, so kickoff should happen at the audio cue.
	await create_timer(maxf(0.0, game._restart_remaining - 0.12)).timeout
	check(not game.pending_restart.is_empty(), "Goal kickoff must not happen before sound cue")
	await create_timer(0.16).timeout
	check(game.pending_restart.is_empty() and game.restart_kind == "Gol! Kickoff", "Kickoff must be ready at goal audio cue")
	check(goal.playing, "Goal audio must still be playing when kickoff is ready")
	var tail: float = goal.stream.get_length() - goal.get_playback_position()
	check(tail > 0.12 and tail < 0.5, "Kickoff must leave about 0.3 seconds of goal audio")
	game.reset_match()
	check(not goal.playing and crowd.playing, "R must cancel celebration and preserve crowd")
	game.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	print("Audio checks completed; failures: ", failures)
	quit(1 if failures else 0)
