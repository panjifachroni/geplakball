extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var menu = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame
	var music = menu.get_node("MenuMusic")
	var old_music = weakref(music)
	check(music.playing and music.stream.get_length() > 0, "Menu must play footie.wav")
	check(music.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "Menu music must loop")
	menu._on_start_pressed()
	await process_frame
	await process_frame
	var game = current_scene
	check(game.scene_file_path == "res://scenes/main.tscn", "Start must enter match")
	check(old_music.get_ref() == null, "Menu audio node must be freed on entering match")
	check(game.get_node_or_null("MenuMusic") == null, "Match must not contain menu music")
	var pause_menu = game.get_node("PauseMenu")
	pause_menu._on_pause_pressed()
	await create_timer(0.12).timeout
	check(paused and pause_menu.visible, "Pause menu must open normally")
	check(old_music.get_ref() == null and game.get_node_or_null("MenuMusic") == null, "Pause must not start footie music")
	check(game.get_node("MatchAudio/Crowd").playing, "Match crowd must keep playing during pause")
	pause_menu._on_mainMenu_pressed()
	await process_frame
	await process_frame
	check(not paused and current_scene.scene_file_path == "res://scenes/main_menu.tscn", "Return must reopen main menu")
	check(current_scene.get_node("MenuMusic").playing, "Footie music must resume only after returning to main menu")
	current_scene.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	print("Menu music checks completed; failures: ", failures)
	quit(1 if failures else 0)
