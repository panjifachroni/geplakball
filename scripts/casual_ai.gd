extends RefCounted
## A small, deliberately imperfect opponent; all shots go through normal match rules.

var rng := RandomNumberGenerator.new()
var actor: Node2D
var think_remaining := 0.0
var decision: Dictionary = {}


func _init() -> void:
	rng.randomize()


func reset() -> void:
	actor = null
	think_remaining = 0.0
	decision.clear()


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
		think_remaining = rng.randf_range(1.0, 2.0)
		decision = choose_shot(game, taker)
		return
	think_remaining -= delta
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
	var goal := Vector2(game.PITCH.position.x - 40.0, rng.randf_range(game.GOAL_TOP + 15.0, game.GOAL_BOTTOM - 15.0))
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
	var shot_chance := 0.62 if origin.distance_to(goal) < 500.0 else 0.28
	if is_restart and game.restart_kind == "Corner":
		shot_chance = 0.0
	if not teammates.is_empty() and rng.randf() > shot_chance:
		# Favor forward options loosely, rather than solving an optimal sequence.
		var receiver: Node2D = teammates[rng.randi_range(0, teammates.size() - 1)]
		target = receiver.foot_position() + Vector2(rng.randf_range(-25, 25), rng.randf_range(-25, 25))
		kind = "pass"
	elif origin.distance_to(goal) > 500.0 and rng.randf() < 0.15:
		kind = "wild"
	var direction := (target - origin).normalized()
	if direction.is_zero_approx():
		direction = Vector2.LEFT
	var error := 0.06 if kind == "pass" else 0.12
	if kind == "wild":
		error = 0.18
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
	strength *= rng.randf_range(0.88, 1.08) if kind == "pass" else rng.randf_range(0.9, 1.12)
	if kind == "wild":
		strength = rng.randf_range(game.MAX_SHOT * 0.75, game.MAX_SHOT * 0.98)
	strength = clampf(strength, game.MIN_SHOT + 60.0, game.MAX_SHOT * 0.98)
	return {"direction": direction, "strength": strength, "kind": kind}
