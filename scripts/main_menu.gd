extends Control

const MENU_MUSIC := preload("res://aset/footie.wav")

var _menu_music: AudioStreamPlayer


func _ready() -> void:
	# Owned by this scene: it cannot survive a transition into the match/pause menu.
	_menu_music = AudioStreamPlayer.new()
	_menu_music.name = "MenuMusic"
	var music_stream := MENU_MUSIC.duplicate() as AudioStreamWAV
	music_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	music_stream.loop_begin = 0
	music_stream.loop_end = int(round(music_stream.get_length() * music_stream.mix_rate))
	_menu_music.stream = music_stream
	_menu_music.volume_db = -12.0
	add_child(_menu_music)
	_menu_music.play()


func _on_start_pressed() -> void:
	_menu_music.stop()
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_credits_pressed() -> void:
	pass # Replace with function body.


func _on_quit_pressed() -> void:
	_menu_music.stop()
	get_tree().quit()
