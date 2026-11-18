extends Node2D

const MAX_DRAG := 240.0
const MIN_SHOT := 260.0
const MAX_SHOT := 1450.0
# White line centers in the original 1600 x 1120 field texture.
const PITCH := Rect2(165, 165, 1270, 790)
const GOAL_TOP := 460.0
const GOAL_BOTTOM := 660.0

@export_range(1.0, 2.0, 0.1) var restart_delay: float = 1.5

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

@onready var ball = $Ball
@onready var players = $Players.get_children()


func _ready() -> void:
	for player in players:
		if player.is_goalkeeper:
			# Keep the defensive depth, and align the keeper's body with goal center.
			player.position.y = PITCH.get_center().y - player.get_node("Body").position.y
			_keeper_homes[player] = player.global_position
			player.pushed.connect(_on_keeper_pushed.bind(player))
		_initial_positions[player] = player.position
	ball.segment_travelled.connect(_on_ball_segment)
	_ensure_ready_kicker()


func can_take_shot(player: Node2D) -> bool:
	return pending_restart.is_empty() and ball.is_stopped() and player.can_reach(ball) and (restart_taker == null or player == restart_taker)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		reset_match()
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
			if Rect2(-60, -96, 120, 96).has_point(local_mouse) and can_take_shot(player):
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
	$HUD/Power.value = aim_power() * 100.0 if aiming_player != null else 0.0
	if not pending_restart.is_empty():
		$HUD/Status.text = "%s — Tim %s | Menunggu bola berhenti..." % [pending_restart.kind, team_name(pending_restart.team)]
	elif aiming_player != null:
		$HUD/Status.text = "Kekuatan %d%% | Lepas untuk menembak | Klik kanan: batal" % int(aim_power() * 100.0)
	elif restart_taker != null:
		$HUD/Status.text = "%s — Tim %s | Bidik ke dalam lapangan" % [restart_kind, team_name(restart_team)]
	elif not ball.is_stopped():
		$HUD/Status.text = "Bola bergerak | R: ulang pertandingan"
	else:
		$HUD/Status.text = "Bola di kaki: klik pemain, tarik ke belakang, lalu lepas | R: ulang"
	$HUD/Score.text = "MERAH  %d  :  %d  BIRU" % score
	$AimOverlay.queue_redraw()


func team_name(team: int) -> String:
	return "Merah" if team == 0 else "Biru"


func _nearest_player(point: Vector2, team: int = -1) -> Node2D:
	var nearest: Node2D
	var distance := INF
	for player in players:
		if team != -1 and player.team != team:
			continue
		var candidate: float = player.center().distance_squared_to(point)
		if candidate < distance:
			nearest = player
			distance = candidate
	return nearest


func _ensure_ready_kicker() -> void:
	if not ball.is_stopped():
		return
	for player in players:
		if player.can_reach(ball):
			ready_player = player
			return
	ready_player = _nearest_player(ball.global_position)
	if ready_player != null:
		ready_player.prepare_kick(ball)


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
	if not pending_restart.is_empty() or ball.frozen:
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
		score[1 - defending_team] += 1
		_queue_restart("Gol! Kickoff", defending_team, PITCH.get_center(), Vector2.ZERO)
	elif last_team == defending_team:
		var corner_y := PITCH.position.y if point.y < PITCH.get_center().y else PITCH.end.y
		var vertical := 1.0 if corner_y == PITCH.position.y else -1.0
		_queue_restart("Corner", 1 - last_team, Vector2(point.x, corner_y), Vector2(inward.x, vertical))
	else:
		var keeper := _goalkeeper(defending_team)
		var keeper_spot: Vector2 = _initial_positions[keeper] + keeper.foot_offset()
		_queue_restart("Tendangan gawang", defending_team, keeper_spot, inward)


func _goalkeeper(team: int) -> Node2D:
	for player in players:
		if player.team == team and player.is_goalkeeper:
			return player
	return _nearest_player(Vector2(PITCH.position.x if team == 0 else PITCH.end.x, PITCH.get_center().y), team)


func _queue_restart(kind: String, team: int, point: Vector2, inward: Vector2) -> void:
	# Snapshot the first exit; later rebounds cannot change the restart decision.
	pending_restart = {"kind": kind, "team": team, "point": point, "inward": inward}
	_restart_remaining = restart_delay
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
	restart_taker.prepare_kick(ball)
	# Give the stationary restart ball enough room to leave the line cleanly.
	for player in players:
		if player == restart_taker:
			continue
		var offset: Vector2 = player.center() - point
		if offset.length() < 90.0:
			if offset.is_zero_approx():
				offset = Vector2.DOWN
			player.global_position += offset.normalized() * (90.0 - offset.length())
	$AimOverlay.queue_redraw()


func _schedule_restart_return(player: Node2D) -> void:
	if player.is_goalkeeper:
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
	_return_after_restart = {"player": player, "target": target, "remaining": 0.18}


func _on_keeper_pushed(keeper: Node2D) -> void:
	_keeper_recoveries[keeper] = 0.2


func _update_keeper_recovery(delta: float) -> void:
	for keeper in _keeper_recoveries.keys():
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


func _update_restart_return(delta: float) -> void:
	if _return_after_restart.is_empty():
		return
	_return_after_restart.remaining -= delta
	if _return_after_restart.remaining > 0.0:
		return
	var player: Node2D = _return_after_restart.player
	var target: Vector2 = _return_after_restart.target
	_return_after_restart.clear()
	if not is_instance_valid(player):
		return
	player.knockback_velocity = Vector2.ZERO
	player.global_position = _available_return_position(player, target)


func _available_return_position(player: Node2D, target: Vector2) -> Vector2:
	var body: StaticBody2D = player.get_node("Body")
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = body.get_node("CollisionShape2D").shape
	query.collision_mask = 14
	query.exclude = [body.get_rid()]
	var offsets: Array[Vector2] = [Vector2.ZERO]
	for radius in [60.0, 100.0, 140.0]:
		for index in range(8):
			offsets.append(Vector2.RIGHT.rotated(index * TAU / 8.0) * radius)
	for offset in offsets:
		var candidate: Vector2 = target + offset
		var center: Vector2 = candidate + body.position
		if not PITCH.grow(-30.0).has_point(center):
			continue
		query.transform = Transform2D(0.0, center)
		if get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
			return candidate
	# Keep the intended return point if an unusually crowded formation blocks all options.
	return target


func _restore_formation() -> void:
	_keeper_recoveries.clear()
	for player in players:
		player.position = _initial_positions[player]
		player.knockback_velocity = Vector2.ZERO
		player.get_node("SlapTimer").stop()
		player._on_slap_timer_timeout()


func reset_match() -> void:
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
	_settle_time = 0.0
	_restore_formation()
	ball.reset_ball()
	_ensure_ready_kicker()


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
