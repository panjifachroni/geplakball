extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func shoot(game: Node2D, player: Node2D, direction: Vector2) -> void:
	game.aiming_player = player
	game.drag_start = Vector2.ZERO
	game.drag_end = -direction.normalized() * 240.0
	game.fire_aimed_shot()

func _run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.blue_ai_enabled = false
	root.add_child(game)
	await physics_frame
	await physics_frame
	var ball = game.get_node("Ball")
	var red = game.get_node("Players/RedGoalkeeper")
	var blue = game.get_node("Players/BlueGoalkeeper")
	for keeper in [red, blue]:
		check(is_equal_approx(keeper.center().y, 560.0), "Both keepers must start centered between posts")
	# Retrieving the ball must not return the keeper before a kick is taken.
	ball.position = Vector2(1400, 670)
	game._ensure_ready_kicker()
	check(game.ready_player == blue and blue.can_reach(ball), "Nearest keeper must retrieve stationary ball")
	var kick_position: Vector2 = blue.position
	await create_timer(0.4).timeout
	check(blue.position == kick_position, "Keeper must stay with ball while waiting to shoot")
	shoot(game, blue, Vector2.UP)
	check(blue.position == kick_position, "Keeper must finish slap before returning")
	await create_timer(0.24).timeout
	check(blue.position == game._keeper_homes[blue], "Keeper must return home after open-play kick")
	check(ball.velocity.length() > 0, "Keeper return must not stop the ball")
	# Both keepers recover after the physical push has finished.
	game.reset_match()
	red.receive_impact(Vector2(-1200, 0), 1600.0)
	blue.receive_impact(Vector2(1200, 0), 1600.0)
	await create_timer(0.1).timeout
	check(red.position.x < game._keeper_homes[red].x, "Red keeper must visibly move under impact")
	check(blue.position.x > game._keeper_homes[blue].x, "Blue keeper must visibly move under impact")
	await create_timer(0.7).timeout
	check(red.position == game._keeper_homes[red] and blue.position == game._keeper_homes[blue], "Both keepers must recover to goal center after impact")
	# Field players retain ordinary knockback behavior.
	var field_player = game.get_node("Players/RedPlayer1")
	var field_home: Vector2 = field_player.position
	field_player.receive_impact(Vector2(0, 1200), 1600.0)
	await create_timer(0.8).timeout
	check(field_player.position.distance_to(field_home) > 10, "Field players must not receive keeper recovery")
	# Keeper rule overrides out/corner re-entry placement.
	for kind in ["Out", "Corner"]:
		game.reset_match()
		var point := Vector2(1435, 165) if kind == "Corner" else Vector2(800, 165)
		var inward := Vector2(-1, 1) if kind == "Corner" else Vector2.DOWN
		blue.position = point + Vector2(0, 90)
		game._award_restart(kind, 1, point, inward)
		check(game.restart_taker == blue, "Keeper must be the selected taker in setup")
		shoot(game, blue, inward)
		await create_timer(0.24).timeout
		check(blue.position == game._keeper_homes[blue], "Keeper restart taker must return to goal center")
	# A reset clears pending recovery.
	game.reset_match()
	blue.receive_impact(Vector2(1200, 0))
	game.reset_match()
	check(game._keeper_recoveries.is_empty(), "R must clear pending keeper recovery")
	check(blue.position == game._keeper_homes[blue], "Reset must center keeper")
	print("Keeper recovery checks completed; failures: ", failures)
	game.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	quit(1 if failures else 0)
