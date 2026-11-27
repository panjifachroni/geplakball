extends RefCounted
## Resolve teleports from current transforms, without waiting for physics caches.

const GAP := 4.0

func arrange(players: Array, pitch: Rect2, anchor: Node2D, waiting: Node2D = null, limits: Dictionary = {}) -> void:
	var ordered: Array = []
	for preferred in [anchor, waiting]:
		if is_instance_valid(preferred) and preferred not in ordered:
			ordered.append(preferred)
	for player in players:
		if player.is_goalkeeper and player not in ordered:
			ordered.append(player)
	for player in players:
		if player not in ordered:
			ordered.append(player)
	var occupied: Array[Rect2] = []
	for player in ordered:
		var desired: Vector2 = player.global_position
		if player == anchor or player == waiting:
			occupied.append(player.placement_bounds(desired).grow(GAP * 0.5))
			continue
		var chosen := _find_position(player, desired, occupied, limits.get(player, pitch), limits.has(player))
		if chosen != desired:
			player.global_position = chosen
			player.knockback_velocity = Vector2.ZERO
		occupied.append(player.placement_bounds(chosen).grow(GAP * 0.5))


func _find_position(player: Node2D, desired: Vector2, occupied: Array[Rect2], pitch: Rect2, constrain: bool = false) -> Vector2:
	# Preserve an already clear position, including a keeper at the goal line.
	if (not constrain or pitch.encloses(player.placement_bounds(desired))) and _clear(player.placement_bounds(desired).grow(GAP * 0.5), occupied):
		return desired
	var local: Rect2 = player.placement_bounds(Vector2.ZERO)
	var search_center := desired.clamp(pitch.position - local.position, pitch.end - local.end)
	for ring in range(1, 65):
		var radius := ring * 8.0
		var samples := maxi(16, ring * 8)
		for index in range(samples):
			var candidate := search_center + Vector2.RIGHT.rotated(index * TAU / samples) * radius
			var bounds: Rect2 = player.placement_bounds(candidate)
			if pitch.encloses(bounds) and _clear(bounds.grow(GAP * 0.5), occupied):
				return candidate
	# Complete the search over the pitch rather than reusing a blocked position.
	for y in range(int(pitch.position.y - local.position.y), int(pitch.end.y - local.end.y) + 1, 16):
		for x in range(int(pitch.position.x - local.position.x), int(pitch.end.x - local.end.x) + 1, 16):
			var candidate := Vector2(x, y)
			if _clear(player.placement_bounds(candidate).grow(GAP * 0.5), occupied):
				return candidate
	push_error("No clear player placement found inside pitch")
	return desired


func _clear(bounds: Rect2, occupied: Array[Rect2]) -> bool:
	for other in occupied:
		if bounds.intersects(other):
			return false
	return true
