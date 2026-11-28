extends "res://scripts/main_menu.gd"
## Both modes share the same match rules; local play disables the blue CPU.

func _on_local_pressed() -> void:
	_start_match("res://scenes/local_match.tscn")


func _on_cpu_pressed() -> void:
	_start_match("res://scenes/main.tscn")


func _start_match(scene_path: String) -> void:
	_menu_music.stop()
	get_tree().change_scene_to_file(scene_path)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		_menu_music.stop()
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
