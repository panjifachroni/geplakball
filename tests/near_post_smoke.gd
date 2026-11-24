extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await physics_frame
	await physics_frame
	var ball = game.get_node("Ball")
	var red = game.get_node("Players/RedPlayer4")
	var blue = game.get_node("Players/BluePlayer4")
	for setup in [
		[1, Vector2(1250, 780), Vector2(1435, 660)],
		[1, Vector2(1250, 380), Vector2(1435, 460)],
		[0, Vector2(350, 780), Vector2(165, 660)],
		[0, Vector2(350, 380), Vector2(165, 460)],
	]:
		game.reset_match()
		var keeper = game._goalkeeper(setup[0])
		var shooter = red if setup[0] == 1 else blue
		shooter.position = setup[1]
		game.ready_player = shooter
		game._update_keeper_position(2.0)
		var body: CircleShape2D = keeper.get_node("Body/CollisionShape2D").shape
		var gap: float = keeper.center().distance_to(setup[2]) - body.radius - 7.0
		check(gap >= 0 and gap < ball.radius() * 2, "Near-post gap must be too narrow for a full ball")
		check(keeper.center().y - body.radius > game.GOAL_TOP and keeper.center().y + body.radius < game.GOAL_BOTTOM, "Keeper must stay between posts")
		check(keeper.get_node("Sprite2D").rotation == 0, "Near-post cover must not rotate sprite")
	game.reset_match()
	var keeper = game.get_node("Players/BlueGoalkeeper")
	var home: Vector2 = game._keeper_homes[keeper]
	red.position = Vector2(1100, 780)
	game.ready_player = red
	game._update_keeper_position(2.0)
	check(keeper.position.x > home.x and keeper.position.x < 1400, "Medium distance must partially close toward near post")
	red.position = Vector2(600, 850)
	game._update_keeper_position(2.0)
	check(keeper.position.x == home.x and absf(keeper.position.y - home.y) <= 60, "Distant shooter must retain normal cover")
	red.position = Vector2(1250, 592)
	game._update_keeper_position(2.0)
	check(keeper.position == home, "Central shooter must not force keeper to a post")
	# A fast ball aimed through the near-post corridor must physically hit the keeper.
	red.position = Vector2(1250, 780)
	game._update_keeper_position(2.0)
	await physics_frame
	await physics_frame
	ball.position = Vector2(1290, 720)
	ball.last_touch = red
	ball.velocity = (Vector2(1435, 645) - ball.position).normalized() * 1000.0
	await create_timer(0.2).timeout
	check(ball.last_touch == keeper, "Near-post keeper must intercept ball with actual collision")
	check(game.score == [0, 0], "Blocked near-post shot must not score")
	game.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	print("Near-post checks completed; failures: ", failures)
	quit(1 if failures else 0)
