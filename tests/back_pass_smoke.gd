extends SceneTree

var failures := 0
var pushes := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	for team in [0, 1]:
		var arena := Node2D.new()
		root.add_child(arena)
		var player = load("res://scenes/paper_player.tscn").instantiate()
		player.team = team
		if team == 1:
			player.team_texture = load("res://aset/paper-player2.png")
			player.idle_region = Rect2(56, 0, 40, 32)
			player.slap_region = Rect2(0, 0, 56, 32)
		player.position = Vector2(1000, 1032)
		arena.add_child(player)
		player.pushed.connect(func(): pushes += 1)
		pushes = 0
		var ball = load("res://scenes/ball.tscn").instantiate()
		ball.position = player.foot_position()
		ball.friction = 0.0
		arena.add_child(ball)
		await physics_frame
		await physics_frame
		var direction := Vector2.LEFT if team == 0 else Vector2.RIGHT
		ball.receive_slap(player.center(), 900.0, player, direction)
		check(player.get_node("Body") in ball.get_collision_exceptions(), "Launch must ignore only kicker collision")
		await create_timer(0.18).timeout
		check(ball.velocity.dot(direction) > 0 and pushes == 0, "Back pass must cross shooter without bouncing or pushing")
		check((ball.position - player.center()).dot(direction) > 50, "Back pass must emerge behind shooter")
		check(ball.get_collision_exceptions().is_empty(), "Kicker collision must restore immediately after clearance")
		# Rebound off a physical wall must then hit the original shooter.
		var wall := StaticBody2D.new()
		wall.collision_layer = 8
		wall.position = Vector2(850 if team == 0 else 1150, 1026)
		var wall_collision := CollisionShape2D.new()
		var wall_shape := RectangleShape2D.new()
		wall_shape.size = Vector2(10, 220)
		wall_collision.shape = wall_shape
		wall.add_child(wall_collision)
		arena.add_child(wall)
		await create_timer(0.34).timeout
		check(pushes > 0, "Returning rebound must physically hit the original shooter")
		check(ball.get_collision_exceptions().is_empty(), "Rebound must not retain shooter exception")
		arena.queue_free()
		await physics_frame
		await physics_frame
	# Other players remain collidable even during the launch grace.
	var arena := Node2D.new()
	root.add_child(arena)
	var shooter = load("res://scenes/paper_player.tscn").instantiate()
	shooter.position = Vector2(1000, 1032)
	arena.add_child(shooter)
	var receiver = load("res://scenes/paper_player.tscn").instantiate()
	receiver.position = Vector2(840, 1032)
	arena.add_child(receiver)
	pushes = 0
	receiver.pushed.connect(func(): pushes += 1)
	var ball = load("res://scenes/ball.tscn").instantiate()
	ball.position = shooter.foot_position()
	ball.friction = 0.0
	arena.add_child(ball)
	await physics_frame
	await physics_frame
	ball.receive_slap(shooter.center(), 900, shooter, Vector2.LEFT)
	check(receiver.get_node("Body") not in ball.get_collision_exceptions(), "Receiver collision must never be disabled")
	await create_timer(0.25).timeout
	check(pushes > 0, "Back pass must still strike another player")
	ball.reset_ball()
	shooter.prepare_kick(ball)
	ball.receive_slap(shooter.center(), 100, shooter, Vector2.LEFT)
	ball.friction = 560.0
	await create_timer(0.25).timeout
	check(ball.is_stopped() and ball.get_collision_exceptions().is_empty(), "Very weak kick must clear launch exception when it stops")
	ball.reset_ball()
	shooter.prepare_kick(ball)
	ball.receive_slap(shooter.center(), 900, shooter, Vector2.LEFT)
	ball.place_for_restart(Vector2(1000, 1200), receiver)
	check(ball.get_collision_exceptions().is_empty(), "Out/goal restart must clear launch exception")
	ball.reset_ball()
	check(ball.get_collision_exceptions().is_empty() and ball.last_kicker == null, "R must clear launch and anti-dribble state")
	arena.queue_free()
	await process_frame
	print("Back pass checks completed; failures: ", failures)
	quit(1 if failures else 0)
