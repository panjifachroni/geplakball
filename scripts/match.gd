extends Node2D

const MAX_DRAG := 240.0
const MIN_SHOT := 260.0
const MAX_SHOT := 1450.0
const CasualAI := preload("res://scripts/casual_ai.gd")
const RestartFormations := preload("res://scripts/restart_formations.gd")
const KeeperSaves := preload("res://scripts/keeper_saves.gd")
const PlayerSpacing := preload("res://scripts/player_spacing.gd")
# White line centers in the original 1600 x 1120 field texture.
const PITCH := Rect2(165, 165, 1270, 790)
const GOAL_TOP := 460.0
const GOAL_BOTTOM := 660.0
const GOAL_LINE_HALF_WIDTH := 5.0

const GoalScene := preload("res://scenes/goal_scene.tscn")

@export_range(1.0, 2.0, 0.1) var restart_delay: float = 1.5
@export var chance_audio_range: float = 320.0
@export var chance_audio_margin: float = 80.0
@export_range(0.0, 80.0, 5.0) var keeper_cover_distance: float = 60.0
@export var keeper_cover_speed: float = 180.0
@export var keeper_close_range: float = 260.0
@export var keeper_cover_fade_range: float = 480.0
@export var keeper_reaction_delay: float = 0.20
@export var keeper_save_speed: float = 155.0
@export var keeper_save_max_move: float = 75.0
@export var keeper_save_range: float = 500.0
@export var counter_retreat_distance: float = 80.0
@export var match_duration: float = 180.0
@export var blue_ai_enabled := true

var _blue_ai = CasualAI.new()
var _restart_formations = RestartFormations.new()
var _keeper_saves = KeeperSaves.new()
var _player_spacing = PlayerSpacing.new()
var _advanced_play: Dictionary = {}
var restart_formation := ""

var time_remaining: float = 180.0
var match_over := false

var pending_restart: Dictionary = {}
var _restart_remaining := 0.0

var aiming_player: Node2D
var ready_player: Node2D
var restart_taker: Node2D
var restart_team := -1
var restart_kind := ""
var restart_inward := Vector2.ZERO
var score := [0, 0]
var drag_start := Vector2.ZERO
var drag_end := Vector2.ZERO
var _settle_time := 0.0
var _initial_positions: Dictionary = {}
var _return_after_restart: Dictionary = {}
var _keeper_homes: Dictionary = {}
var _keeper_recoveries: Dictionary = {}
var _pickup_locked := false
var _pickup_position := Vector2.ZERO
var _pickup_last_kicker: Node2D

@onready var ball = $Ball
@onready var players = $Players.get_children()
@onready var match_audio = $MatchAudio


func _ready() -> void:
	time_remaining = match_duration
	match_audio.get_node("Whistle").finished.connect(_on_full_time_whistle_finished)
	_update_match_clock()
	_update_scoreboard()
	for player in players:
		if player.is_goalkeeper:
			# Keep the defensive depth, and align the keeper's body with goal center.
			player.position.y = PITCH.get_center().y - player.get_node("Body").position.y
			_keeper_homes[player] = player.global_position
			player.pushed.connect(_on_keeper_pushed.bind(player))
		_initial_positions[player] = player.position
	ball.segment_travelled.connect(_on_ball_segment)
	ball.kicked.connect(_on_ball_kicked)
	ball.goal_post_hit.connect(_on_goal_post_hit)
	_ensure_ready_kicker()


func can_take_shot(player: Node2D) -> bool:
	var owner: Node2D = restart_taker if is_instance_valid(restart_taker) else ready_player
	return not match_over and pending_restart.is_empty() and ball.is_stopped() and player == owner and player != ball.last_kicker and player.can_reach(ball)


func _on_ball_kicked() -> void:
	_keeper_saves.reset()
	if not _advanced_play.is_empty() and is_instance_valid(ball.last_kicker):
		_advanced_play.counter_started = ball.last_kicker.team != _advanced_play.team
	_pickup_locked = false
	ready_player = null
	match_audio.play_kick()


func can_human_take_shot(player: Node2D) -> bool:
	if not can_take_shot(player):
		return false
	if not blue_ai_enabled:
		return true
	var owner: Node2D = restart_taker if is_instance_valid(restart_taker) else ready_player
	return player.team == 0 and owner == player


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		reset_match()
		return
	if match_over:
		return
	if blue_ai_enabled and is_instance_valid(aiming_player) and aiming_player.team == 1:
		return
	if event is InputEventMouseMotion and aiming_player != null:
		drag_end = get_global_mouse_position()
		$AimOverlay.queue_redraw()
	if not event is InputEventMouseButton:
		return
	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		aiming_player = null
		$AimOverlay.queue_redraw()
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		var mouse := get_global_mouse_position()
		var closest: Node2D
		var distance := INF
		for player in players:
			var local_mouse: Vector2 = player.to_local(mouse)
			if Rect2(-60, -96, 120, 96).has_point(local_mouse) and can_human_take_shot(player):
				var candidate: float = mouse.distance_to(player.center())
				if candidate < distance:
					closest = player
					distance = candidate
		if closest != null and ball.is_stopped():
			aiming_player = closest
			drag_start = mouse
			drag_end = mouse
	else:
		if aiming_player != null:
			drag_end = get_global_mouse_position()
			fire_aimed_shot()
	$AimOverlay.queue_redraw()


func aim_power() -> float:
	return clampf(drag_start.distance_to(drag_end) / MAX_DRAG, 0.0, 1.0)


func _restart_direction_valid(direction: Vector2) -> bool:
	if restart_taker == null:
		return true
	if restart_inward.x != 0 and direction.x * restart_inward.x <= 0:
		return false
	if restart_inward.y != 0 and direction.y * restart_inward.y <= 0:
		return false
	return true


func fire_aimed_shot() -> void:
	if aiming_player != null and can_take_shot(aiming_player):
		var pull := drag_start - drag_end
		if pull.length() >= 8.0 and _restart_direction_valid(pull.normalized()):
			aiming_player.slap(pull.normalized(), lerpf(MIN_SHOT, MAX_SHOT, aim_power()))
			if not ball.frozen and not ball.velocity.is_zero_approx():
				_schedule_restart_return(aiming_player)
				restart_taker = null
				restart_team = -1
				restart_kind = ""
				ready_player = null
	aiming_player = null
	_settle_time = 0.0


func _physics_process(delta: float) -> void:
	if match_over:
		return
	time_remaining = maxf(0.0, time_remaining - delta)
	_update_match_clock()
	if time_remaining <= 0.0:
		_finish_match()
		return
	# Choose before keeper coverage/recovery can move candidates on the stop frame.
	if not ball.is_stopped():
		_pickup_locked = false
		ready_player = null
	elif restart_taker == null and pending_restart.is_empty() and aiming_player == null:
		_ensure_ready_kicker()
	_update_keeper_position(delta)
	_update_chance_audio()
	_update_restart_return(delta)
	_update_keeper_recovery(delta)
	if not pending_restart.is_empty():
		_restart_remaining -= delta
		if _restart_remaining <= 0.0 and ball.is_stopped():
			_finish_pending_restart()
	if aiming_player != null and not can_take_shot(aiming_player):
		aiming_player = null
	if not ball.is_stopped():
		_settle_time = 0.0
		ready_player = null
	elif restart_taker == null and pending_restart.is_empty():
		_settle_time += delta
		if aiming_player == null and _settle_time >= 0.3:
			_ensure_ready_kicker()
	_blue_ai.tick(self, delta)
	$HUD/Power2.value = aim_power() * 100.0 if aiming_player != null else 0.0
	if not pending_restart.is_empty():
		var message: String
		if pending_restart.kind == "Gol! Kickoff":
			message = "GOOOL! Tim %s | Bersiap kickoff..." % team_name(1 - pending_restart.team)
		else:
			message = "%s — Tim %s | Menunggu bola berhenti..." % [pending_restart.kind, team_name(pending_restart.team)]
		$HUD/Status.text = message
		$HUD/Status2.text = message
	elif aiming_player != null:
		var message := "AI Biru membidik..." if blue_ai_enabled and aiming_player.team == 1 else "Kekuatan %d%% | Lepas untuk menembak | Klik kanan: batal" % int(aim_power() * 100.0)
		$HUD/Status.text = message
		$HUD/Status2.text = message
	elif is_instance_valid(_blue_ai.actor):
		$HUD/Status.text = "AI Biru sedang berpikir... Kamu tim Merah"
		$HUD/Status2.text = $HUD/Status.text
	elif restart_taker != null:
		$HUD/Status.text = "%s — Tim %s | Bidik ke dalam lapangan" % [restart_kind, team_name(restart_team)]
		$HUD/Status2.text = "%s — Tim %s | Bidik ke dalam lapangan" % [restart_kind, team_name(restart_team)]
	elif not ball.is_stopped():
		$HUD/Status.text = "Bola bergerak | R: ulang pertandingan"
		$HUD/Status2.text = "Bola bergerak | R: ulang pertandingan"
	else:
		$HUD/Status.text = "Bola di kaki: klik pemain, tarik ke belakang, lalu lepas | R: ulang"
		$HUD/Status2.text = "Bola di kaki: klik pemain, tarik ke belakang, lalu lepas | R: ulang"
	_update_scoreboard()
	$AimOverlay.queue_redraw()


func team_name(team: int) -> String:
	return "Merah" if team == 0 else "Biru"


func _nearest_player(point: Vector2, team: int = -1, excluded: Node2D = null) -> Node2D:
	var nearest: Node2D
	var distance := INF
	for player in players:
		if player == excluded:
			continue
		if team != -1 and player.team != team:
			continue
		var candidate: float = player.center().distance_squared_to(point)
		if candidate < distance:
			nearest = player
			distance = candidate
	return nearest


func _ensure_ready_kicker() -> void:
	if match_over or not pending_restart.is_empty() or not ball.is_stopped():
		return
	if is_instance_valid(restart_taker):
		ready_player = restart_taker
		return
	# Only retain an owner chosen in this stationary episode, never an arbitrary
	# cached in-range player. After teleporting, retain the choice so it cannot flip.
	if _pickup_locked and ball.last_kicker == _pickup_last_kicker and ball.global_position.distance_to(_pickup_position) < 0.5 and is_instance_valid(ready_player) and ready_player != ball.last_kicker and ready_player.can_reach(ball):
		_update_keeper_position()
		return
	var closest := _nearest_player(ball.global_position, -1, ball.last_kicker)
	if closest != ready_player:
		_blue_ai.reset()
		aiming_player = null
	ready_player = closest
	if ready_player != null:
		if not ready_player.can_reach(ball):
			ready_player.prepare_kick(ball)
		_pickup_locked = true
		_pickup_position = ball.global_position
		_pickup_last_kicker = ball.last_kicker
		_try_resolve_counter(ready_player)
		var retreat_limits := _retreat_on_turnover(ready_player)
		_separate_players(retreat_limits)
	_update_keeper_position()


func _retreat_on_turnover(owner: Node2D) -> Dictionary:
	if not is_instance_valid(ball.last_kicker) or ball.last_kicker.team == owner.team:
		return {}
	# Only break up an advanced set-piece attack, once per formation.
	# Ordinary alternating shots must not gradually rewrite the base formation.
	if _advanced_play.is_empty() or _advanced_play.team != ball.last_kicker.team or _advanced_play.get("retreated", false):
		return {}
	_advanced_play.retreated = true
	var limits: Dictionary = {}
	var previous_team: int = ball.last_kicker.team
	var direction := 1.0 if previous_team == 0 else -1.0
	var candidates: Array = []
	for player in players:
		if player.team == previous_team and not player.is_goalkeeper:
			candidates.append(player)
	# Pull the supporting attackers back first, leaving forward passing options.
	candidates.sort_custom(func(a, b): return a.center().x * direction < b.center().x * direction)
	var advanced: Array = candidates.filter(func(player): return (player.center().x - PITCH.get_center().x) * direction > 0.0)
	for player in candidates:
		if player not in advanced:
			advanced.append(player)
	for index in range(mini(2, advanced.size())):
		var player: Node2D = advanced[index]
		if _return_after_restart.get("player") == player:
			_return_after_restart.clear()
		var target := Vector2(PITCH.get_center().x - direction * (160.0 + index * 80.0), PITCH.position.y + PITCH.size.y * (0.32 if index == 0 else 0.68))
		player.global_position += target - player.center()
		player.knockback_velocity = Vector2.ZERO
		limits[player] = Rect2(PITCH.position if previous_team == 0 else Vector2(PITCH.get_center().x + 6, PITCH.position.y), Vector2(PITCH.size.x * 0.5 - 6, PITCH.size.y))
	return limits


func _separate_players(limits: Dictionary = {}) -> void:
	var anchor: Node2D = restart_taker if is_instance_valid(restart_taker) else ready_player
	var waiting: Node2D = _return_after_restart.get("player") if not ball.is_stopped() else null
	_player_spacing.arrange(players, PITCH, anchor, waiting, limits)


func _remember_advanced_formation(team: int) -> void:
	if not _advanced_play.is_empty() and _advanced_play.team == team:
		_advanced_play.counter_started = false
		_advanced_play.retreated = false
		return
	var before: Dictionary = {}
	for player in players:
		before[player] = player.global_position
	_advanced_play = {"team": team, "before": before, "counter_started": false}


func _try_resolve_counter(keeper: Node2D) -> void:
	if _advanced_play.is_empty() or not _advanced_play.counter_started:
		return
	if not keeper.is_goalkeeper or keeper.team != _advanced_play.team or not keeper.can_reach(ball):
		return
	if not is_instance_valid(ball.last_kicker) or ball.last_kicker.team == keeper.team:
		return
	var attacking_team: int = _advanced_play.team
	var before: Dictionary = _advanced_play.before
	_advanced_play.clear()
	_return_after_restart.clear()
	_keeper_recoveries.erase(keeper)
	_keeper_saves.reset()
	# The countering side eases toward its own goal; its keeper stays guarding.
	for player in players:
		if player.is_goalkeeper or player.team == attacking_team:
			continue
		var back := -1.0 if player.team == 0 else 1.0
		var target: Vector2 = player.center() + Vector2(back * counter_retreat_distance, 0)
		target = target.clamp(PITCH.position + Vector2(35, 35), PITCH.end - Vector2(35, 35))
		player.global_position += target - player.center()
		player.knockback_velocity = Vector2.ZERO
	for player in players:
		if player.team == attacking_team and not player.is_goalkeeper and before.has(player):
			player.global_position = before[player]
			player.knockback_velocity = Vector2.ZERO
	restart_formation = ""


func _update_keeper_position(delta: float = 0.0) -> void:
	var shooter: Node2D = aiming_player
	if not is_instance_valid(shooter):
		shooter = restart_taker
	if not is_instance_valid(shooter):
		shooter = ready_player
	for keeper in _keeper_homes:
		keeper.reset_facing()
		if not pending_restart.is_empty():
			continue
		if keeper in _keeper_recoveries or not keeper.knockback_velocity.is_zero_approx():
			continue
		if keeper == ready_player or keeper == restart_taker or keeper == aiming_player:
			continue
		if not ball.is_stopped():
			_keeper_saves.update(self, keeper, delta)
			continue
		_keeper_saves.reads.erase(keeper)
		var target: Vector2 = _keeper_homes[keeper]
		if is_instance_valid(shooter) and shooter.team != keeper.team:
			var offset_y: float = shooter.center().y - PITCH.get_center().y
			if absf(offset_y) > 60.0:
				target.y += clampf(offset_y / (PITCH.size.y * 0.5), -1.0, 1.0) * keeper_cover_distance
				var goal_x: float = PITCH.position.x if keeper.team == 0 else PITCH.end.x
				var nearest_mouth := Vector2(goal_x, clampf(shooter.center().y, GOAL_TOP, GOAL_BOTTOM))
				var distance: float = shooter.center().distance_to(nearest_mouth)
				var blend := clampf((keeper_cover_fade_range - distance) / maxf(1.0, keeper_cover_fade_range - keeper_close_range), 0.0, 1.0)
				var half: Vector2 = keeper.collision_half_extents()
				var inside := 1.0 if keeper.team == 0 else -1.0
				# Close the gap between keeper and post to less than one ball diameter.
				var near_post := Vector2(goal_x + inside * (half.x + ball.radius() - 3.0), GOAL_TOP + half.y + 1.0 if offset_y < 0 else GOAL_BOTTOM - half.y - 1.0)
				near_post -= keeper.get_node("Body").position
				target = target.lerp(near_post, blend)
		var next_position: Vector2 = keeper.global_position.move_toward(target, keeper_cover_speed * delta)
		keeper.move_player(next_position - keeper.global_position)


# Intersect every travelled segment, including rebounds, with the pitch lines.
# The earliest crossing wins, even for diagonal shots across two lines in one frame.
func find_exit(from: Vector2, to: Vector2) -> Dictionary:
	var result: Dictionary = {}
	var earliest := INF
	var travel := to - from
	var edges := [
		["left", 0, PITCH.position.x, travel.x < 0 and from.x >= PITCH.position.x and to.x < PITCH.position.x],
		["right", 0, PITCH.end.x, travel.x > 0 and from.x <= PITCH.end.x and to.x > PITCH.end.x],
		["top", 1, PITCH.position.y, travel.y < 0 and from.y >= PITCH.position.y and to.y < PITCH.position.y],
		["bottom", 1, PITCH.end.y, travel.y > 0 and from.y <= PITCH.end.y and to.y > PITCH.end.y],
	]
	for edge in edges:
		if not edge[3]:
			continue
		var axis: int = edge[1]
		var t: float = (float(edge[2]) - from[axis]) / travel[axis]
		var point := from + travel * t
		if point.x < PITCH.position.x - 0.01 or point.x > PITCH.end.x + 0.01:
			continue
		if point.y < PITCH.position.y - 0.01 or point.y > PITCH.end.y + 0.01:
			continue
		if t < earliest:
			earliest = t
			result = {"side": edge[0], "point": point}
	return result


func _on_ball_segment(from: Vector2, to: Vector2) -> void:
	if match_over or not pending_restart.is_empty() or ball.frozen:
		return
	var goal := find_goal_crossing(from, to)
	if not goal.is_empty():
		var defending_team := 0 if goal.side == "left" else 1
		score[1 - defending_team] += 1
		_update_scoreboard()
		var goal_instance := GoalScene.instantiate()
		add_child(goal_instance)
		get_tree().create_timer(4.5).timeout.connect(func() -> void:
			if is_instance_valid(goal_instance):
				goal_instance.queue_free()
		)
		_queue_restart("Gol! Kickoff", defending_team, PITCH.get_center(), Vector2.ZERO)
		return
	var exit := find_exit(from, to)
	if exit.is_empty():
		return
	var last_team: int = ball.last_touch.team if is_instance_valid(ball.last_touch) else 0
	var side: String = exit.side
	var point: Vector2 = exit.point
	if side == "top" or side == "bottom":
		var inward := Vector2.DOWN if side == "top" else Vector2.UP
		_queue_restart("Out", 1 - last_team, point, inward)
		return
	var defending_team := 0 if side == "left" else 1
	var inward := Vector2.RIGHT if side == "left" else Vector2.LEFT
	if point.y > GOAL_TOP and point.y < GOAL_BOTTOM:
		# Center crossing is not enough: the rear edge must clear the entire white line.
		return
	elif last_team == defending_team:
		var corner_y := PITCH.position.y if point.y < PITCH.get_center().y else PITCH.end.y
		var vertical := 1.0 if corner_y == PITCH.position.y else -1.0
		_queue_restart("Corner", 1 - last_team, Vector2(point.x, corner_y), Vector2(inward.x, vertical))
	else:
		# A genuine attacking near miss: crossing just above/below the goal mouth.
		if minf(absf(point.y - GOAL_TOP), absf(point.y - GOAL_BOTTOM)) <= 80.0:
			match_audio.play_miss()
		var keeper := _goalkeeper(defending_team)
		var keeper_spot: Vector2 = _initial_positions[keeper] + keeper.foot_offset()
		_queue_restart("Tendangan gawang", defending_team, keeper_spot, inward)


func _on_goal_post_hit() -> void:
	if not match_over and pending_restart.is_empty() and not ball.frozen:
		match_audio.play_miss()


func find_goal_crossing(from: Vector2, to: Vector2) -> Dictionary:
	var clearance: float = ball.radius() + GOAL_LINE_HALF_WIDTH
	for side in ["left", "right"]:
		var plane: float = PITCH.position.x - clearance if side == "left" else PITCH.end.x + clearance
		var crosses: bool = from.x >= plane and to.x < plane if side == "left" else from.x <= plane and to.x > plane
		if not crosses:
			continue
		var t := (plane - from.x) / (to.x - from.x)
		var point := from.lerp(to, t)
		if point.y - ball.radius() > GOAL_TOP and point.y + ball.radius() < GOAL_BOTTOM:
			return {"side": side, "point": point}
	return {}


func _update_chance_audio() -> void:
	if match_over or ball.frozen or ball.play_locked or ball.is_stopped() or not pending_restart.is_empty():
		return
	var speed: float = ball.velocity.length()
	if speed < 100.0 or absf(ball.velocity.x) < 40.0:
		return
	# React to a close goal attempt, including one that the keeper may save.
	# A goal celebration is reserved for the actual full-ball crossing.
	var goal_x: float = PITCH.end.x if ball.velocity.x > 0 else PITCH.position.x
	var dx: float = goal_x - ball.global_position.x
	var arrival: float = dx / ball.velocity.x
	if arrival < 0.0 or arrival > 1.5 or absf(dx) > chance_audio_range:
		return
	var projected_y: float = ball.global_position.y + ball.velocity.y * arrival
	if projected_y < GOAL_TOP - chance_audio_margin or projected_y > GOAL_BOTTOM + chance_audio_margin:
		return
	var travel: float = absf(dx) * speed / absf(ball.velocity.x)
	if ball.friction > 0.0 and travel > speed * speed / (2.0 * ball.friction):
		return
	match_audio.play_miss()


func _goalkeeper(team: int) -> Node2D:
	for player in players:
		if player.team == team and player.is_goalkeeper:
			return player
	return _nearest_player(Vector2(PITCH.position.x if team == 0 else PITCH.end.x, PITCH.get_center().y), team)


func _queue_restart(kind: String, team: int, point: Vector2, inward: Vector2) -> void:
	if match_over:
		return
	_blue_ai.reset()
	_pickup_locked = false
	# Snapshot the first exit; later rebounds cannot change the restart decision.
	pending_restart = {"kind": kind, "team": team, "point": point, "inward": inward}
	_restart_remaining = restart_delay
	if kind == "Gol! Kickoff":
		match_audio.play_goal()
		_restart_remaining = match_audio.goal_kickoff_delay()
	ball.play_locked = true
	aiming_player = null
	ready_player = null
	for player in players:
		player.get_node("SlapTimer").stop()
		player._on_slap_timer_timeout()


func _finish_pending_restart() -> void:
	var decision := pending_restart.duplicate()
	pending_restart.clear()
	if decision.kind == "Gol! Kickoff":
		_restore_formation()
	_award_restart(decision.kind, decision.team, decision.point, decision.inward)


func _award_restart(kind: String, team: int, point: Vector2, inward: Vector2) -> void:
	if kind == "Tendangan gawang":
		_restore_formation()
		restart_formation = ""
	_keeper_saves.reset()
	if not _restart_formations.layout_for(kind, team, point, PITCH).is_empty():
		_remember_advanced_formation(team)
	_blue_ai.reset()
	_pickup_locked = false
	_return_after_restart.clear()
	aiming_player = null
	_settle_time = 0.0
	for player in players:
		player.knockback_velocity = Vector2.ZERO
		player.get_node("SlapTimer").stop()
		player._on_slap_timer_timeout()
	restart_kind = kind
	restart_team = team
	restart_inward = inward
	restart_taker = _goalkeeper(team) if kind == "Tendangan gawang" else _nearest_player(point, team)
	ready_player = restart_taker
	ball.place_for_restart(point, restart_taker)
	restart_formation = _restart_formations.apply_layout(kind, team, point, PITCH, players, restart_taker, _keeper_homes)
	if not restart_formation.is_empty():
		_keeper_recoveries.clear()
	restart_taker.prepare_kick(ball)
	_update_keeper_position()
	# Give the stationary restart ball enough room to leave the line cleanly.
	for player in players:
		if player == restart_taker:
			continue
		var offset: Vector2 = player.center() - point
		if offset.length() < 90.0:
			if offset.is_zero_approx():
				offset = Vector2.DOWN
			player.global_position += offset.normalized() * (90.0 - offset.length())
	_separate_players()
	$AimOverlay.queue_redraw()


func _schedule_restart_return(player: Node2D) -> void:
	if player.is_goalkeeper:
		if player == restart_taker and restart_kind in ["Out", "Corner"]:
			_return_after_restart = {"player": player, "target": _keeper_homes[player], "remaining": 0.18, "wait_for_stop": true, "keeper": true}
			return
		_keeper_recoveries[player] = 0.18
		return
	if player != restart_taker or restart_kind not in ["Out", "Corner"]:
		return
	var target_center: Vector2 = ball.global_position + restart_inward * 140.0
	if restart_kind == "Corner":
		# Rejoin play a little inside both lines, without returning across the pitch.
		target_center = ball.global_position + restart_inward * Vector2(150.0, 140.0)
	target_center = target_center.clamp(PITCH.position + Vector2(50, 50), PITCH.end - Vector2(50, 50))
	var target: Vector2 = target_center - player.get_node("Body").position
	_return_after_restart = {"player": player, "target": target, "remaining": 0.18, "wait_for_stop": true}


func _on_keeper_pushed(keeper: Node2D) -> void:
	_keeper_recoveries[keeper] = 0.2


func _update_keeper_recovery(delta: float) -> void:
	for keeper in _keeper_recoveries.keys():
		if not _return_after_restart.is_empty() and _return_after_restart.player == keeper and _return_after_restart.get("wait_for_stop", false) and not ball.is_stopped():
			continue
		# A keeper taking a restart or lining up a kick stays with the ball until shooting.
		if keeper == restart_taker or keeper == aiming_player:
			continue
		if keeper == ready_player and ball.is_stopped() and pending_restart.is_empty():
			continue
		if not keeper.knockback_velocity.is_zero_approx():
			_keeper_recoveries[keeper] = 0.2
			continue
		_keeper_recoveries[keeper] -= delta
		if _keeper_recoveries[keeper] > 0.0:
			continue
		keeper.global_position = _keeper_homes[keeper]
		keeper.knockback_velocity = Vector2.ZERO
		keeper.impact_tier = keeper.ImpactTier.NONE
		keeper.get_node("SlapTimer").stop()
		keeper._on_slap_timer_timeout()
		_keeper_recoveries.erase(keeper)
		_separate_players()


func _update_restart_return(delta: float) -> void:
	if _return_after_restart.is_empty():
		return
	_return_after_restart.remaining -= delta
	if _return_after_restart.remaining > 0.0:
		return
	if _return_after_restart.get("wait_for_stop", false) and not ball.is_stopped():
		return
	var player: Node2D = _return_after_restart.player
	var target: Vector2 = _return_after_restart.target
	var is_keeper: bool = _return_after_restart.get("keeper", false)
	_return_after_restart.clear()
	if not is_instance_valid(player):
		return
	player.knockback_velocity = Vector2.ZERO
	_keeper_recoveries.erase(player)
	player.global_position = target if is_keeper else _available_return_position(player, target)
	_separate_players()


func _available_return_position(player: Node2D, target: Vector2) -> Vector2:
	var occupied: Array[Rect2] = []
	for other in players:
		if other != player:
			occupied.append(other.placement_bounds(other.global_position).grow(PlayerSpacing.GAP * 0.5))
	occupied.append(Rect2(ball.global_position - Vector2.ONE * ball.radius(), Vector2.ONE * ball.radius() * 2.0))
	return _player_spacing._find_position(player, target, occupied, PITCH)


func _restore_formation() -> void:
	_advanced_play.clear()
	_keeper_saves.reset()
	_keeper_recoveries.clear()
	for player in players:
		player.position = _initial_positions[player]
		player.knockback_velocity = Vector2.ZERO
		player.get_node("SlapTimer").stop()
		player._on_slap_timer_timeout()
		player.reset_facing()
	_separate_players()


func reset_match() -> void:
	restart_formation = ""
	_blue_ai.reset()
	_pickup_locked = false
	_pickup_last_kicker = null
	get_tree().paused = false
	$PauseMenu.visible = false
	match_over = false
	time_remaining = match_duration
	_update_match_clock()
	match_audio.reset_effects()
	_return_after_restart.clear()
	pending_restart.clear()
	_restart_remaining = 0.0
	aiming_player = null
	ready_player = null
	restart_taker = null
	restart_team = -1
	restart_kind = ""
	restart_inward = Vector2.ZERO
	score = [0, 0]
	_update_scoreboard()
	_settle_time = 0.0
	_restore_formation()
	ball.reset_ball()
	_ensure_ready_kicker()


func _update_match_clock() -> void:
	var seconds := ceili(time_remaining)
	$HUD/MatchClock.text = "%02d:%02d" % [int(seconds / 60.0), seconds % 60]
	$HUD/MatchClockShadow.text = "%02d:%02d" % [int(seconds / 60.0), seconds % 60]


func _update_scoreboard() -> void:
	$HUD/ScoreRed.text = str(score[0])
	$HUD/ScoreRedShadow.text = str(score[0])
	$HUD/ScoreBlue.text = str(score[1])
	$HUD/ScoreBlueShadow.text = str(score[1])


func _finish_match() -> void:
	if match_over:
		return
	_advanced_play.clear()
	_keeper_saves.reset()
	_blue_ai.reset()
	_pickup_locked = false
	get_tree().paused = false
	$PauseMenu.hide()
	match_over = true
	time_remaining = 0.0
	_update_match_clock()
	pending_restart.clear()
	_return_after_restart.clear()
	_keeper_recoveries.clear()
	aiming_player = null
	ready_player = null
	restart_taker = null
	restart_team = -1
	restart_kind = ""
	ball.finish_match()
	for player in players:
		player.knockback_velocity = Vector2.ZERO
		player.impact_tier = player.ImpactTier.NONE
		player.get_node("SlapTimer").stop()
		player._on_slap_timer_timeout()
	_update_scoreboard()
	$HUD/Status.text = "Waktu habis"
	$HUD/Status2.text = $HUD/Status.text
	$HUD/Power2.value = 0
	$AimOverlay.queue_redraw()
	match_audio.play_full_time()


func _on_full_time_whistle_finished() -> void:
	_complete_full_time.call_deferred()


func _complete_full_time() -> void:
	if match_over and is_inside_tree():
		_return_to_main_menu()


func _return_to_main_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func draw_aim(canvas: Node2D) -> void:
	if aiming_player == null:
		if ready_player != null:
			canvas.draw_arc(to_local(ready_player.foot_position()), 18.0, 0, TAU, 40, Color(1, 0.85, 0.2), 3.0, true)
		return
	var origin := to_local(ball.global_position)
	var pull := drag_start - drag_end
	var color := Color(0.4, 1, 0.8).lerp(Color(1, 0.35, 0.2), aim_power())
	canvas.draw_arc(to_local(aiming_player.foot_position()), aiming_player.KICK_REACH, 0, TAU, 40, Color(1, 1, 1, 0.5), 2.0, true)
	if pull.length() < 8.0:
		return
	var direction := pull.normalized()
	if not _restart_direction_valid(direction):
		color = Color(1, 0.2, 0.2)
	var tip := origin + direction * lerpf(45.0, 230.0, aim_power())
	canvas.draw_line(origin, tip, color, 5.0, true)
	canvas.draw_colored_polygon(PackedVector2Array([tip + direction * 16.0, tip - direction * 10.0 + direction.orthogonal() * 12.0, tip - direction * 10.0 - direction.orthogonal() * 12.0]), color)
