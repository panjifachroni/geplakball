extends RefCounted
## Reference layouts use normalized body positions, with the attacking team going right.

const ATTACKING_OUT_START := 0.60
const CORNER_OUT_START := 0.88

const OUT_ATTACK := [Vector2(0.42, 0.22), Vector2(0.40, 0.64), Vector2(0.76, 0.50), Vector2(0.71, 0.87)]
const OUT_DEFENCE := [Vector2(0.55, 0.13), Vector2(0.84, 0.32), Vector2(0.56, 0.53), Vector2(0.87, 0.74), Vector2(0.52, 0.89)]
const CORNER_ATTACK := [Vector2(0.745, 0.18), Vector2(0.764, 0.49), Vector2(0.656, 0.655), Vector2(0.814, 0.88)]
const CORNER_DEFENCE := [Vector2(0.642, 0.154), Vector2(0.864, 0.313), Vector2(0.590, 0.487), Vector2(0.899, 0.672), Vector2(0.604, 0.80)]


func layout_for(kind: String, team: int, point: Vector2, pitch: Rect2) -> String:
	if kind == "Corner":
		return "corner"
	if kind != "Out":
		return ""
	# Only the touchlines in the attacking end; midfield out keeps its current shape.
	if minf(absf(point.y - pitch.position.y), absf(point.y - pitch.end.y)) > 1.0:
		return ""
	var progress := (point.x - pitch.position.x) / pitch.size.x
	if team == 1:
		progress = 1.0 - progress
	if progress < ATTACKING_OUT_START:
		return ""
	return "corner" if progress > CORNER_OUT_START else "attacking_out"


func apply_layout(kind: String, team: int, point: Vector2, pitch: Rect2, players: Array, taker: Node2D, keeper_homes: Dictionary) -> String:
	var layout := layout_for(kind, team, point, pitch)
	if layout.is_empty():
		return ""
	var attacking: Array[Node2D] = []
	var defending: Array[Node2D] = []
	for player in players:
		if player == taker:
			continue
		if player.is_goalkeeper:
			# Keep goalkeepers guarding their own goal; a keeper taking the restart is exempt.
			if keeper_homes.has(player):
				player.global_position = keeper_homes[player]
			continue
		if player.team == team:
			attacking.append(player)
		else:
			defending.append(player)
	var attack_slots: Array = (CORNER_ATTACK if layout == "corner" else OUT_ATTACK).duplicate()
	var defence_slots: Array = CORNER_DEFENCE if layout == "corner" else OUT_DEFENCE
	# Rare keeper-taken restart leaves five outfield teammates, rather than four.
	if attacking.size() > attack_slots.size():
		attack_slots.append(Vector2(0.32, 0.50))
	var from_bottom := point.y > pitch.get_center().y
	_assign_slots(attacking, attack_slots, team, from_bottom, pitch)
	_assign_slots(defending, defence_slots, team, from_bottom, pitch)
	return layout


func _assign_slots(candidates: Array[Node2D], slots: Array, attack_team: int, from_bottom: bool, pitch: Rect2) -> void:
	var available: Array[Node2D] = candidates.duplicate()
	for slot in slots:
		if available.is_empty():
			return
		var local: Vector2 = slot
		if attack_team == 1:
			local.x = 1.0 - local.x
		if from_bottom:
			local.y = 1.0 - local.y
		var target := pitch.position + local * pitch.size
		var nearest: Node2D = available[0]
		for player in available:
			if player.center().distance_squared_to(target) < nearest.center().distance_squared_to(target):
				nearest = player
		nearest.global_position += target - nearest.center()
		available.erase(nearest)
