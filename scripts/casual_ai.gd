extends RefCounted
## Moderate opponent: weighs lanes/keeper position, but retains human-sized errors.

var rng := RandomNumberGenerator.new()
var actor: Node2D
var think_remaining := 0.0
var decision: Dictionary = {}
var _reviewed := false


func _init() -> void:
	rng.randomize()


func reset() -> void:
	actor = null
	think_remaining = 0.0
	decision.clear()
	_reviewed = false


func tick(game: Node2D, delta: float) -> void:
	var taker: Node2D = game.restart_taker if is_instance_valid(game.restart_taker) else game.ready_player
	if not game.blue_ai_enabled or game.match_over or not game.pending_restart.is_empty() or not game.ball.is_stopped():
		_cancel(game)
		return
	if not is_instance_valid(taker) or taker.team != 1 or not game.can_take_shot(taker):
		_cancel(game)
		return
	if actor != taker:
		_cancel(game)
		actor = taker
		think_remaining = rng.randf_range(0.8, 1.4)
		decision = choose_shot(game, taker)
		return
	think_remaining -= delta
	if think_remaining <= 0.4 and not _reviewed:
		decision = choose_shot(game, actor)
		_reviewed = true
	if think_remaining <= 0.35:
		game.aiming_player = actor
		game.drag_start = Vector2.ZERO
		var power := inverse_lerp(game.MIN_SHOT, game.MAX_SHOT, float(decision.strength))
		game.drag_end = -decision.direction * clampf(power, 0.04, 1.0) * game.MAX_DRAG
	if think_remaining <= 0.0:
		game.fire_aimed_shot()
		reset()


func _cancel(game: Node2D) -> void:
	if is_instance_valid(actor) and game.aiming_player == actor:
		game.aiming_player = null
	reset()


func choose_shot(game: Node2D, shooter: Node2D) -> Dictionary:
	var origin: Vector2 = game.ball.global_position
	var goal := _goal_target(game, shooter)
	var target := goal
	var kind := "shot"
	var teammates: Array[Node2D] = []
	var is_restart: bool = game.restart_taker == shooter
	for player in game.players:
		if player == shooter or player.team != 1 or player.is_goalkeeper:
			continue
		var gap: float = origin.distance_to(player.foot_position())
		if gap >= 100.0 and gap <= 1000.0:
			if is_restart or player.center().x < origin.x - 50.0:
				teammates.append(player)
	var shot_chance := 0.80 if origin.distance_to(goal) < 600.0 else 0.50
	if _lane_score(game, shooter, goal) < -1.0:
		shot_chance *= 0.45
	if is_restart and game.restart_kind == "Corner":
		shot_chance = 0.0
	if not teammates.is_empty() and rng.randf() > shot_chance:
		var receiver := _pass_receiver(game, shooter, teammates)
		target = receiver.foot_position() + Vector2(rng.randf_range(-12, 12), rng.randf_range(-12, 12))
		kind = "pass"
	elif origin.distance_to(goal) > 500.0 and rng.randf() < 0.06:
		kind = "wild"
	var direction := (target - origin).normalized()
	if direction.is_zero_approx():
		direction = Vector2.LEFT
	var error := 0.025 if kind == "pass" else 0.035
	if kind == "wild":
		error = 0.10
	direction = direction.rotated(rng.randf_range(-error, error))
	if is_restart:
		# Corner/out/goal-kick direction must enter the pitch, including both corner axes.
		if game.restart_inward.x != 0:
			direction.x = signf(game.restart_inward.x) * maxf(absf(direction.x), 0.2)
		if game.restart_inward.y != 0:
			direction.y = signf(game.restart_inward.y) * maxf(absf(direction.y), 0.2)
		direction = direction.normalized()
	var travel: float = origin.distance_to(target) + (140.0 if kind != "pass" else 0.0)
	var strength := sqrt(2.0 * maxf(game.ball.friction, 1.0) * travel)
	strength *= rng.randf_range(0.96, 1.04) if kind == "pass" else rng.randf_range(1.0, 1.06)
	if kind == "wild":
		strength = rng.randf_range(game.MAX_SHOT * 0.75, game.MAX_SHOT * 0.98)
	strength = clampf(strength, game.MIN_SHOT + 60.0, game.MAX_SHOT * 0.995)
	return {"direction": direction, "strength": strength, "kind": kind, "target": target}


func _goal_target(game: Node2D, shooter: Node2D) -> Vector2:
	var best := Vector2(game.PITCH.position.x - 40, game.PITCH.get_center().y)
	var best_score := -INF
	var keeper = game._goalkeeper(0)
	for y in [game.GOAL_TOP + 22.0, game.GOAL_TOP + 55.0, game.PITCH.get_center().y, game.GOAL_BOTTOM - 55.0, game.GOAL_BOTTOM - 22.0]:
		var target := Vector2(game.PITCH.position.x - 40, y)
		var value := _lane_score(game, shooter, target)
		value += absf(y - keeper.center().y) * 0.003 + rng.randf_range(-0.12, 0.12)
		if value > best_score:
			best = target
			best_score = value
	return best


func _pass_receiver(game: Node2D, shooter: Node2D, teammates: Array[Node2D]) -> Node2D:
	var best: Node2D = teammates[0]
	var best_score := -INF
	for receiver in teammates:
		var space := 200.0
		for opponent in game.players:
			if opponent.team != shooter.team:
				space = minf(space, opponent.center().distance_to(receiver.center()))
		var value := _lane_score(game, shooter, receiver.foot_position(), receiver)
		value += (game.ball.global_position.x - receiver.center().x) * 0.001 + space * 0.003
		value += rng.randf_range(-0.15, 0.15)
		if value > best_score:
			best = receiver
			best_score = value
	return best


func _lane_score(game: Node2D, shooter: Node2D, target: Vector2, receiver: Node2D = null) -> float:
	var origin: Vector2 = game.ball.global_position
	var value := 0.0
	for player in game.players:
		if player == shooter or player == receiver:
			continue
		var nearest := Geometry2D.get_closest_point_to_segment(player.center(), origin, target)
		var clearance: float = player.collision_half_extents().length() + game.ball.radius() + 12.0
		var gap: float = nearest.distance_to(player.center())
		if gap < clearance:
			value -= (1.0 - gap / clearance) * (4.0 if player.is_goalkeeper else 3.0)
	return value
