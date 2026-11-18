extends CharacterBody2D
## Top-down ball: no gravity, with friction and rebounds against paper players.

signal segment_travelled(from: Vector2, to: Vector2)

@export var friction: float = 560.0
@export var bounce: float = 0.75
@export var max_speed: float = 1600.0

var last_touch: Node2D
var _start_position: Vector2
var restart_owner: Node2D
var frozen := false
var play_locked := false


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
	restart_owner = null
	frozen = false
	var direction := aimed_direction if not aimed_direction.is_zero_approx() else global_position - origin
	if direction.is_zero_approx():
		direction = Vector2.RIGHT
	velocity = (velocity * 0.15 + direction.normalized() * strength).limit_length(max_speed)
	last_touch = player
	_update_collision_mask()
	_update_animation()


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
			break
		var normal := collision.get_normal()
		var incoming_speed := velocity.length()
		var impact := -normal * maxf(0.0, -velocity.dot(normal))
		var collider = collision.get_collider()
		var rebound := bounce
		if collider.is_in_group("goal_net"):
			rebound = 0.3
		elif collider.is_in_group("goal_post"):
			rebound = 0.9
		velocity = velocity.bounce(normal) * rebound
		motion = collision.get_remainder().bounce(normal) * rebound
		_update_collision_mask()
		if collider is StaticBody2D and collider.get_parent().has_method("slap"):
			if not play_locked:
				last_touch = collider.get_parent()
			collider.get_parent().receive_impact(impact, max_speed, incoming_speed)
	velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
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
	play_locked = false
	frozen = false
	restart_owner = null
	global_position = _start_position
	velocity = Vector2.ZERO
	last_touch = null
	$AnimatedSprite2D.stop()
	_update_collision_mask()


func place_for_restart(point: Vector2, owner: Node2D) -> void:
	play_locked = false
	global_position = point
	velocity = Vector2.ZERO
	frozen = true
	restart_owner = owner
	last_touch = null
	$AnimatedSprite2D.stop()
	_update_collision_mask()


func is_stopped() -> bool:
	return velocity == Vector2.ZERO


func _update_collision_mask() -> void:
	# Goal frame/net always collide. Very slow balls can pass through paper players.
	var hits_players := velocity.length() >= max_speed * 0.2
	collision_mask = 12 if hits_players else 8
	# Slow balls also must not block a paper player that is still being pushed.
	collision_layer = 2 if hits_players else 16
