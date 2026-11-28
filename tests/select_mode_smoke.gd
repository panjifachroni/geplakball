extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func wait_for_scene() -> void:
	await process_frame
	await process_frame

func _run() -> void:
	var menu = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	menu.get_node("VBoxContainer/Button").pressed.emit()
	await wait_for_scene()
	check(current_scene.scene_file_path == "res://scenes/select_mode.tscn", "Start must open existing mode selection")
	current_scene.get_node("Button").pressed.emit()
	await wait_for_scene()
	var game = current_scene
	check(game.scene_file_path == "res://scenes/local_match.tscn" and not game.blue_ai_enabled, "1v1 must enter local match with CPU disabled")
	for team in [0, 1]:
		game.reset_match()
		var keeper = game._goalkeeper(team)
		var spot: Vector2 = game._initial_positions[keeper] + keeper.foot_offset()
		game._award_restart("Tendangan gawang", team, spot, Vector2.RIGHT if team == 0 else Vector2.LEFT)
		check(game.can_human_take_shot(keeper), "Both teams must accept human aim in local mode")
		await create_timer(1.65).timeout
		check(game.ball.last_kicker == null and game._blue_ai.actor == null, "Local opponent must wait for the second human")
		game.aiming_player = keeper
		game.drag_start = Vector2.ZERO
		game.drag_end = Vector2(-180 if team == 0 else 180, 0)
		game.fire_aimed_shot()
		check(game.ball.last_kicker == keeper and not game.ball.is_stopped(), "Each local team must be able to take a manual shot")
	game.reset_match()
	check(not game.blue_ai_enabled, "R must preserve local mode")
	game.get_node("PauseMenu")._on_pause_pressed()
	check(paused, "Local game must pause normally")
	game.get_node("PauseMenu")._on_mainMenu_pressed()
	await wait_for_scene()
	current_scene.get_node("VBoxContainer/Button").pressed.emit()
	await wait_for_scene()
	# Esc returns to the main menu without starting a match.
	var cancel := InputEventKey.new()
	cancel.keycode = KEY_ESCAPE
	cancel.pressed = true
	current_scene._unhandled_key_input(cancel)
	await wait_for_scene()
	check(current_scene.scene_file_path == "res://scenes/main_menu.tscn", "Esc must return from mode selection")
	current_scene.get_node("VBoxContainer/Button").pressed.emit()
	await wait_for_scene()
	current_scene.get_node("Button2").pressed.emit()
	await wait_for_scene()
	game = current_scene
	check(game.scene_file_path == "res://scenes/main.tscn" and game.blue_ai_enabled, "CPU selection after local play must restore CPU mode")
	var blue = game._goalkeeper(1)
	game._award_restart("Tendangan gawang", 1, game._initial_positions[blue] + blue.foot_offset(), Vector2.LEFT)
	check(not game.can_human_take_shot(blue), "CPU team must reject human control")
	game._blue_ai.tick(game, 0.0)
	check(game._blue_ai.actor == blue, "CPU must plan its own shot")
	game.match_audio.reset_effects()
	await create_timer(0.12).timeout
	game.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	print("Mode selection and local play checks completed; failures: ", failures)
	quit(1 if failures else 0)
