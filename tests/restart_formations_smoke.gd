extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func verify_slots(game: Node2D, team: int, slots: Array, attack_team: int, bottom: bool, taker: Node2D) -> void:
	var actual: Array[Vector2] = []
	for player in game.players:
		if player.team == team and not player.is_goalkeeper and player != taker:
			actual.append(player.center())
	check(actual.size() == slots.size(), "Every reference slot must be occupied")
	for slot in slots:
		var local: Vector2 = slot
		if attack_team == 1:
			local.x = 1.0 - local.x
		if bottom:
			local.y = 1.0 - local.y
		var expected: Vector2 = game.PITCH.position + local * game.PITCH.size
		var found := false
		for center in actual:
			if center.distance_to(expected) <= 72.1:
				found = true
				actual.erase(center)
				break
		check(found, "Formation must stay near mirrored reference slots while allowing collision clearance")

func _run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.blue_ai_enabled = false
	root.add_child(game)
	await physics_frame
	await physics_frame
	var layouts = game._restart_formations
	var pitch: Rect2 = game.PITCH
	for team in [0, 1]:
		for bottom in [false, true]:
			for setup in [["Out", 0.75, "attacking_out"], ["Out", 0.94, "corner"], ["Corner", 1.0, "corner"]]:
				game.reset_match()
				var x: float = setup[1] if team == 0 else 1.0 - setup[1]
				var point := pitch.position + Vector2(x * pitch.size.x, pitch.size.y if bottom else 0.0)
				game._award_restart(setup[0], team, point, Vector2.UP if bottom else Vector2.DOWN)
				var taker = game.restart_taker
				check(game.restart_formation == setup[2], "Restart area must select correct layout")
				check(game.ball.position.distance_to(point) < 0.1 and taker.can_reach(game.ball), "Ball must remain at exact line position and kicker feet")
				check(not taker.is_goalkeeper, "Reference scenario must retain outfield kicker")
				verify_slots(game, team, layouts.CORNER_ATTACK if setup[2] == "corner" else layouts.OUT_ATTACK, team, bottom, taker)
				verify_slots(game, 1 - team, layouts.CORNER_DEFENCE if setup[2] == "corner" else layouts.OUT_DEFENCE, team, bottom, taker)
				for player in game.players:
					check(player.get_node("Sprite2D").scale == Vector2(3, 3), "Player size must remain unchanged")
					if player.is_goalkeeper:
						check(player.position == game._keeper_homes[player], "Goalkeeper must start in own goal")
					if player != taker:
						check(pitch.has_point(player.center()), "Other players must remain inside pitch")
	for team in [0, 1]:
		for progress in [0.1, 0.5, 0.59]:
			var x: float = progress if team == 0 else 1.0 - progress
			check(layouts.layout_for("Out", team, pitch.position + Vector2(x * pitch.size.x, 0), pitch).is_empty(), "Midfield and defensive out must preserve existing positions")
		check(layouts.layout_for("Tendangan gawang", team, pitch.get_center(), pitch).is_empty(), "Goal kick must not change")
		check(layouts.layout_for("Gol! Kickoff", team, pitch.get_center(), pitch).is_empty(), "Kickoff must not change")
	game.reset_match()
	var point := pitch.position + Vector2(pitch.size.x * 0.75, 0)
	game._award_restart("Out", 0, point, Vector2.DOWN)
	var taker = game.restart_taker
	game.aiming_player = taker
	game.drag_start = Vector2.ZERO
	game.drag_end = Vector2(0, -240)
	game.fire_aimed_shot()
	check(not game.ball.frozen and game.ball.last_kicker == taker, "New formation must permit actual restart kick")
	game.reset_match()
	check(game.restart_formation.is_empty(), "Reset must clear layout state")
	await create_timer(0.12).timeout
	game.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	print("Restart formation checks completed; failures: ", failures)
	quit(1 if failures else 0)
