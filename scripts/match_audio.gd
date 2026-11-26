extends Node
## Match-owned audio: crowd alone keeps playing while the match is paused.

var _missed_for_shot := false
var _goal_for_shot := false


func _ready() -> void:
	# Runtime WAV loading also works before Godot imports a newly added asset.
	$Whistle.stream = AudioStreamWAV.load_from_file("res://aset/whistle.wav")
	$Whistle.stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	var crowd_stream := $Crowd.stream.duplicate() as AudioStreamWAV
	crowd_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	crowd_stream.loop_begin = 0
	crowd_stream.loop_end = int(round(crowd_stream.get_length() * crowd_stream.mix_rate))
	$Crowd.stream = crowd_stream
	$Crowd.play()


func play_kick() -> void:
	_missed_for_shot = false
	_goal_for_shot = false
	$Kick.play()


func play_miss() -> void:
	if _missed_for_shot or $Goal.playing:
		return
	_missed_for_shot = true
	$Missed.play()


func play_goal() -> void:
	if _goal_for_shot:
		return
	_goal_for_shot = true
	_missed_for_shot = true
	$Missed.stop()
	$Goal.play()


func goal_kickoff_delay() -> float:
	# Prediction may already have started the celebration before the goal is scored.
	var elapsed: float = $Goal.get_playback_position() if $Goal.playing else 0.0
	return maxf(0.0, $Goal.stream.get_length() - elapsed - 0.3)


func reset_effects() -> void:
	_missed_for_shot = false
	_goal_for_shot = false
	$Kick.stop()
	$Missed.stop()
	$Goal.stop()
	$Whistle.stop()


func play_full_time() -> void:
	reset_effects()
	$Whistle.play()


