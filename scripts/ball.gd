extends CharacterBody2D
## Top-down ball: no gravity, with friction and rebounds against paper players.

signal segment_travelled(from: Vector2, to: Vector2)
signal kicked
signal goal_post_hit

@export var friction: float = 560.0
@export var bounce: float = 0.75
@export var max_speed: float = 1600.0

var last_touch: Node2D
var last_kicker: Node2D
var _start_position: Vector2
var restart_owner: Node2D
var frozen := false
var play_locked := false
var _launch_body: PhysicsBody2D
var _launch_start := Vector2.ZERO
var _launch_direction := Vector2.ZERO
var _launch_clearance := 0.0
var _launch_separation := 0.0


func _ready() -> void:
	_start_position = global_position
	$AnimatedSprite2D.stop()
	_update_collision_mask()


func receive_slap(origin: Vector2, strength: float, player: Node2D, aimed_direction: Vector2 = Vector2.ZERO) -> void:
	if play_locked:
		return
	if not is_stopped():
		return
	if restart_owner != null and player != restart_owner:
		return
	if player == last_kicker:
		return
	restart_owner = null
	frozen = false
	var direction := aimed_direction if not aimed_direction.is_zero_approx() else global_position - origin
	if direction.is_zero_approx():
		direction = Vector2.RIGHT
	velocity = (velocity * 0.15 + direction.normalized() * strength).limit_length(max_speed)
	_begin_launch_exception(player)
	last_touch = player
	last_kicker = player
	_update_collision_mask()
	_update_animation()
	kicked.emit()


func _physics_process(delta: float) -> void:
	_update_collision_mask()
	if frozen:
		return
	var motion := velocity * delta
	# Consume the remaining motion after each bounce to prevent tunneling.
	for _iteration in range(4):
		if motion.is_zero_approx():
			break
		var previous := global_position
		var collision := move_and_collide(motion)
		segment_travelled.emit(previous, global_position)
		if frozen:
			return
		if collision == null:
			_update_launch_exception()
			break
		# Restore before consuming the rebound, even when it returns in this same frame.
		_clear_launch_exception()
		var normal := collision.get_normal()
		var incoming_speed := velocity.length()
		var impact := -normal * maxf(0.0, -velocity.dot(normal))
		var collider = collision.get_collider()
		var rebound := bounce
		if collider.is_in_group("goal_net"):
			rebound = 0.3
		elif collider.is_in_group("goal_post"):
			rebound = 0.9
			goal_post_hit.emit()
		velocity = velocity.bounce(normal) * rebound
		motion = collision.get_remainder().bounce(normal) * rebound
		_update_collision_mask()
		if collider is StaticBody2D and collider.get_parent().has_method("slap"):
			if not play_locked:
				last_touch = collider.get_parent()
			collider.get_parent().receive_impact(impact, max_speed, incoming_speed)
	velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
	_update_launch_exception()
	_update_collision_mask()
	_update_animation()


func _update_animation() -> void:
	if not is_stopped():
		$AnimatedSprite2D.speed_scale = clampf(velocity.length() / 350.0, 0.25, 3.0)
		$AnimatedSprite2D.play("roll")
	else:
		$AnimatedSprite2D.pause()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		reset_ball()


func reset_ball() -> void:
	_clear_launch_exception()
	play_locked = false
	frozen = false
	restart_owner = null
	global_position = _start_position
	velocity = Vector2.ZERO
	last_touch = null
	last_kicker = null
	$AnimatedSprite2D.stop()
	_update_collision_mask()


func place_for_restart(point: Vector2, owner: Node2D) -> void:
	_clear_launch_exception()
	play_locked = false
	global_position = point
	velocity = Vector2.ZERO
	frozen = true
	restart_owner = owner
	last_touch = null
	last_kicker = null
	$AnimatedSprite2D.stop()
	_update_collision_mask()


func is_stopped() -> bool:
	return velocity == Vector2.ZERO


func finish_match() -> void:
	_clear_launch_exception()
	velocity = Vector2.ZERO
	frozen = true
	play_locked = true
	restart_owner = null
	$AnimatedSprite2D.pause()
	_update_collision_mask()


func radius() -> float:
	var circle: CircleShape2D = $CollisionShape2D.shape
	return circle.radius * maxf(absf(global_scale.x), absf(global_scale.y))


func _begin_launch_exception(player: Node2D) -> void:
	_clear_launch_exception()
	_launch_body = player.get_node("Body") as PhysicsBody2D
	var body_shape: CircleShape2D = _launch_body.get_node("CollisionShape2D").shape
	_launch_start = global_position
	_launch_direction = velocity.normalized()
	_launch_separation = radius() + body_shape.radius * maxf(absf(_launch_body.global_scale.x), absf(_launch_body.global_scale.y)) + 2.0
	var offset := global_position - _launch_body.global_position
	var projection := offset.dot(_launch_direction)
	var discriminant := projection * projection - (offset.length_squared() - _launch_separation * _launch_separation)
	_launch_clearance = 2.0
	if discriminant >= 0.0:
		_launch_clearance = maxf(2.0, -projection + sqrt(discriminant) + 2.0)
	add_collision_exception_with(_launch_body)


func _update_launch_exception() -> void:
	if not is_instance_valid(_launch_body):
		_launch_body = null
		return
	if is_stopped() or velocity.dot(_launch_direction) <= 0.0:
		_clear_launch_exception()
		return
	var progress := (global_position - _launch_start).dot(_launch_direction)
	if progress >= _launch_clearance and global_position.distance_to(_launch_body.global_position) > _launch_separation:
		_clear_launch_exception()


func _clear_launch_exception() -> void:
	if is_instance_valid(_launch_body):
		remove_collision_exception_with(_launch_body)
	_launch_body = null


func _update_collision_mask() -> void:
	# Goal frame/net always collide. Very slow balls can pass through paper players.
	var hits_players := velocity.length() >= max_speed * 0.2
	collision_mask = 12 if hits_players else 8
	# Slow balls also must not block a paper player that is still being pushed.
	collision_layer = 2 if hits_players else 16
