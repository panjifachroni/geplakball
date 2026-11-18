extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func shoot(game: Node2D, direction: Vector2) -> void:
	game.aiming_player = game.restart_taker
	game.drag_start = Vector2.ZERO
	game.drag_end = -direction.normalized() * 240.0
	game.fire_aimed_shot()

func _run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await physics_frame
	await physics_frame
	var ball = game.get_node("Ball")
	# Out taker rejoins near the touchline, rather than returning to the old position.
	game.get_node("Players/BluePlayer3").position = Vector2(760, 310)
	var point := Vector2(780, 165)
	var taker: Node2D = game._nearest_player(point, 1)
	var home := taker.global_position
	game._award_restart("Out", 1, point, Vector2.DOWN)
	var kick_spot := taker.global_position
	check(kick_spot != home and taker.can_reach(ball), "Out taker must first prepare at touchline")
	shoot(game, Vector2.UP)
	await create_timer(0.22).timeout
	check(taker.global_position == kick_spot and ball.frozen, "Rejected shot must not return the taker")
	shoot(game, Vector2(2, 1))
	check(taker.global_position == kick_spot, "Taker must finish the slap before returning")
	check(ball.velocity.length() > 1000, "Return scheduling must preserve shot strength")
	await create_timer(0.24).timeout
	check(taker.center().distance_to(point + Vector2(0, 140)) < 0.1, "Out taker must move a little inside from the restart point")
	check(taker.global_position.distance_to(home) > 10, "Out taker must not return to the saved old position")
	check(ball.position.distance_to(point) > 100 and ball.velocity.length() > 0, "Ball must continue travelling after taker returns")
	# Every corner returns its taker only a moderate distance inside both lines.
	var corners := [
		[Vector2(1435, 165), Vector2(-1, 1), 0],
		[Vector2(165, 165), Vector2(1, 1), 1],
		[Vector2(165, 955), Vector2(1, -1), 1],
		[Vector2(1435, 955), Vector2(-1, -1), 0],
	]
	for corner in corners:
		game.reset_match()
		var corner_point: Vector2 = corner[0]
		var inward: Vector2 = corner[1]
		home = game._nearest_player(corner_point, corner[2]).position
		game._award_restart("Corner", corner[2], corner_point, inward)
		taker = game.restart_taker
		shoot(game, inward)
		await create_timer(0.24).timeout
		var center: Vector2 = taker.center()
		check(game.PITCH.grow(-30).has_point(center), "Corner taker must finish inside the pitch")
		check(center.distance_to(corner_point) >= 150 and center.distance_to(corner_point) < 320, "Corner return must keep moderate distance from corner")
		check(taker.position.distance_to(home) > 50, "Corner taker must rejoin nearby rather than crossing to old position")
	# Reset cancels an outstanding return rather than moving a player later.
	game.reset_match()
	game._award_restart("Out", 1, Vector2(650, 165), Vector2.DOWN)
	taker = game.restart_taker
	shoot(game, Vector2(2, 1))
	game.reset_match()
	home = taker.position
	await create_timer(0.3).timeout
	check(taker.position == home, "R must cancel queued return")
	check(game._return_after_restart.is_empty(), "R must clear return bookkeeping")
	# Keeper restarts retain the existing keeper placement.
	game.reset_match()
	game._award_restart("Tendangan gawang", 1, Vector2(1296, 571), Vector2.LEFT)
	taker = game.restart_taker
	home = taker.position
	shoot(game, Vector2.LEFT)
	check(game._return_after_restart.is_empty(), "Goal kicks must not schedule out/corner returns")
	check(taker.position == home, "Keeper must stay in keeper position")
	print("Restart return checks completed; failures: ", failures)
	quit(1 if failures else 0)
