extends RefCounted
## One delayed, imperfect read of an incoming ball, with a bounded lateral movement.

var rng := RandomNumberGenerator.new()
var reads: Dictionary = {}


func _init() -> void:
	rng.randomize()


func reset() -> void:
	reads.clear()


func could_still_intercept(game: Node2D, side: String, horizon: float) -> bool:
	var keeper = game._goalkeeper(0 if side == "left" else 1)
	if not reads.has(keeper) or keeper in game._keeper_recoveries or not keeper.knockback_velocity.is_zero_approx():
		return false
	var read: Dictionary = reads[keeper]
	var movement := minf(float(read.budget), maxf(0.0, horizon - maxf(0.0, float(read.wait))) * game.keeper_save_speed)
	if movement <= 0.0 or absf(game.ball.velocity.x) < 1.0:
		return false
	var dx: float = keeper.center().x - game.ball.global_position.x
	var half: Vector2 = keeper.collision_half_extents()
	var reach: float = half.y + game.ball.radius()
	if dx * game.ball.velocity.x < 0 and absf(dx) > half.x + game.ball.radius():
		return false
	var arrival := maxf(0.0, dx / game.ball.velocity.x)
	var ball_y: float = game.ball.global_position.y + game.ball.velocity.y * arrival
	var future_y := move_toward(keeper.center().y, float(read.target_y), movement)
	return absf(future_y - ball_y) <= reach


func update(game: Node2D, keeper: Node2D, delta: float) -> void:
	var ball = game.ball
	var dx: float = keeper.center().x - ball.global_position.x
	var speed: float = ball.velocity.length()
	if ball.play_locked or ball.frozen or speed < ball.max_speed * 0.2 or absf(ball.velocity.x) < 80.0:
		reads.erase(keeper)
		return
	var arrival: float = dx / ball.velocity.x
	if arrival <= 0.0 or arrival > 1.2 or absf(dx) > game.keeper_save_range:
		reads.erase(keeper)
		return
	var travel: float = absf(dx) * speed / absf(ball.velocity.x)
	if ball.friction > 0.0 and travel > speed * speed / (2.0 * ball.friction):
		reads.erase(keeper)
		return
	var predicted_y: float = ball.global_position.y + ball.velocity.y * arrival
	if predicted_y < game.GOAL_TOP - 60.0 or predicted_y > game.GOAL_BOTTOM + 60.0:
		reads.erase(keeper)
		return
	var half: Vector2 = keeper.collision_half_extents()
	if not reads.has(keeper):
		var error := rng.randf_range(-14.0, 14.0)
		reads[keeper] = {
			"wait": game.keeper_reaction_delay,
			"target_y": clampf(predicted_y + error, game.GOAL_TOP + half.y + 1.0, game.GOAL_BOTTOM - half.y - 1.0),
			"budget": game.keeper_save_max_move,
		}
	var read: Dictionary = reads[keeper]
	read.wait -= delta
	if read.wait > 0.0 or read.budget <= 0.0:
		return
	var step := clampf(float(read.target_y) - keeper.center().y, -game.keeper_save_speed * delta, game.keeper_save_speed * delta)
	step = clampf(step, -float(read.budget), float(read.budget))
	var before: Vector2 = keeper.global_position
	keeper.move_player(Vector2(0, step))
	read.budget = maxf(0.0, float(read.budget) - before.distance_to(keeper.global_position))
