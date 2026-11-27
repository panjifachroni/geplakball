@tool
extends Area2D
## Each team can define its own pose layout in its sprite sheet.

signal pushed

@export var idle_region := Rect2(0, 0, 32, 32):
	set(value):
		idle_region = value
		if is_node_ready():
			$Sprite2D.region_rect = idle_region
			_sync_body_collision()
@export var slap_region := Rect2(32, 0, 64, 32)
@export var slap_strength: float = 1050.0
@export_enum("Merah", "Biru") var team: int = 0
@export var is_goalkeeper := false

const KICK_REACH := 22.0
enum ImpactTier { NONE, MEDIUM, HEAVY }

var knockback_velocity := Vector2.ZERO
var impact_tier: ImpactTier = ImpactTier.NONE
var _shot_direction := Vector2.ZERO
var _current_strength: float = 1050.0

var _slap_active := false
var _hit_balls: Array[Node2D] = []
var _placement_key := ""
var _placement_local := Rect2()

@export var team_texture: Texture2D = preload("res://aset/paper-player.png"):
	set(value):
		team_texture = value
		if is_node_ready():
			$Sprite2D.texture = team_texture
			_sync_body_collision()


func _ready() -> void:
	$Sprite2D.texture = team_texture
	$Sprite2D.region_rect = idle_region
	# Per-player shape: changing one pose must not resize every teammate's collider.
	$Body/CollisionShape2D.shape = RectangleShape2D.new()
	_sync_body_collision()
	$SlapHitbox.position = foot_offset()
	reset_facing()


func reset_facing() -> void:
	$Sprite2D.rotation = 0.0


func center() -> Vector2:
	return $Body.global_position


func _sync_body_collision() -> void:
	var region: Rect2 = $Sprite2D.region_rect
	var image := team_texture.get_image()
	var used: Rect2i = image.get_region(Rect2i(region)).get_used_rect()
	if used.size == Vector2i.ZERO:
		used = Rect2i(Vector2i.ZERO, Vector2i(region.size))
	var pixel_scale: Vector2 = $Sprite2D.scale.abs()
	var local_center := Vector2(used.position) + Vector2(used.size) * 0.5 - region.size * 0.5
	$Body.position = $Sprite2D.position + local_center * pixel_scale
	var shape: RectangleShape2D = $Body/CollisionShape2D.shape
	shape.size = Vector2(used.size) * pixel_scale + Vector2(4, 4)


func collision_half_extents() -> Vector2:
	var shape: RectangleShape2D = $Body/CollisionShape2D.shape
	return shape.size * $Body.global_scale.abs() * 0.5


func collision_bounds() -> Rect2:
	var half := collision_half_extents()
	return Rect2(center() - half, half * 2.0)


func placement_bounds(at_position: Vector2) -> Rect2:
	# Formation spacing follows the standing body, not the entire slap animation.
	var key := str([team_texture.get_instance_id(), idle_region, $Sprite2D.scale, $Sprite2D.position])
	if key == _placement_key:
		return Rect2(at_position + _placement_local.position, _placement_local.size)
	var result := Rect2()
	for region: Rect2 in [idle_region]:
		var used := team_texture.get_image().get_region(Rect2i(region)).get_used_rect()
		var size: Vector2 = Vector2(used.size) * $Sprite2D.scale.abs() + Vector2(4, 4)
		var offset: Vector2 = $Sprite2D.position + (Vector2(used.position) + Vector2(used.size) * 0.5 - region.size * 0.5) * $Sprite2D.scale.abs()
		var bounds := Rect2(offset - size * 0.5, size)
		result = bounds if result.size == Vector2.ZERO else result.merge(bounds)
	_placement_key = key
	_placement_local = result
	return Rect2(at_position + result.position, result.size)


func foot_offset() -> Vector2:
	return Vector2(42.0 if team == 0 else -42.0, -6.0)


func foot_position() -> Vector2:
	return global_position + foot_offset()


func can_reach(ball: Node2D) -> bool:
	return foot_position().distance_to(ball.global_position) <= KICK_REACH


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	move_player(knockback_velocity * delta)
	knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, 1100.0 * delta)
	if knockback_velocity.is_zero_approx():
		impact_tier = ImpactTier.NONE


func move_player(motion: Vector2) -> void:
	if motion.is_zero_approx():
		return
	if not $Body.test_move($Body.global_transform, motion):
		global_position += motion


func receive_impact(impact: Vector2, ball_max_speed: float = 1600.0, incoming_speed: float = -1.0) -> void:
	var speed := impact.length() if incoming_speed < 0.0 else incoming_speed
	var ratio := speed / maxf(ball_max_speed, 1.0)
	if ratio < 0.2 or impact.is_zero_approx():
		return
	var push_speed: float
	if ratio >= 0.6:
		impact_tier = ImpactTier.HEAVY
		push_speed = lerpf(330.0, 460.0, clampf((ratio - 0.6) / 0.4, 0.0, 1.0))
	else:
		impact_tier = ImpactTier.MEDIUM
		push_speed = lerpf(140.0, 230.0, clampf((ratio - 0.2) / 0.4, 0.0, 1.0))
	# Glancing contact transfers less force than a head-on collision.
	push_speed *= clampf(impact.length() / maxf(speed, 1.0), 0.1, 1.0)
	knockback_velocity = (knockback_velocity + impact.normalized() * push_speed).limit_length(540.0)
	pushed.emit()


func prepare_kick(ball: Node2D) -> void:
	knockback_velocity = Vector2.ZERO
	impact_tier = ImpactTier.NONE
	$SlapTimer.stop()
	_on_slap_timer_timeout()
	global_position = ball.global_position - foot_offset()


func slap(direction: Vector2 = Vector2.ZERO, strength: float = -1.0) -> void:
	if _slap_active or Engine.is_editor_hint():
		return
	_slap_active = true
	_shot_direction = direction.normalized()
	_current_strength = slap_strength if strength < 0.0 else strength
	_hit_balls.clear()
	$Sprite2D.region_rect = slap_region
	_sync_body_collision()
	$SlapTimer.start()
	# Query feet directly: teleporting must not wait for cached Area2D overlaps.
	for body in get_tree().get_nodes_in_group("balls"):
		_on_slap_hitbox_body_entered(body)


func _on_slap_hitbox_body_entered(body: Node2D) -> void:
	if not _slap_active or body in _hit_balls:
		return
	if body.is_in_group("balls") and body.has_method("receive_slap") and can_reach(body):
		_hit_balls.append(body)
		body.receive_slap(center(), _current_strength, self, _shot_direction)


func _on_slap_timer_timeout() -> void:
	_slap_active = false
	_hit_balls.clear()
	$Sprite2D.region_rect = idle_region
	_sync_body_collision()
