extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	for team in [0, 1]:
		for flat in [false, true]:
			for edge in [-1, 0, 1]:
				var player = load("res://scenes/paper_player.tscn").instantiate()
				player.position = Vector2(2400, 2400)
				player.team = team
				if team == 1:
					player.team_texture = load("res://aset/paper-player2.png")
					player.idle_region = Rect2(56, 0, 40, 32)
					player.slap_region = Rect2(0, 0, 56, 32)
				root.add_child(player)
				if flat:
					player.slap()
					player.get_node("SlapTimer").stop()
				var bounds: Rect2 = player.collision_bounds()
				var sprite: Sprite2D = player.get_node("Sprite2D")
				var opaque: Rect2i = player.team_texture.get_image().get_region(Rect2i(sprite.region_rect)).get_used_rect()
				check(bounds.size == Vector2(opaque.size) * sprite.scale + Vector2(4, 4), "Collider must cover the visible frame in each pose/team")
				for speed in [200.0, 1200.0]:
					var ball = load("res://scenes/ball.tscn").instantiate()
					ball.friction = 0
					ball.position = Vector2(bounds.position.x - 12, bounds.get_center().y + edge * (bounds.size.y * 0.5 - 2))
					root.add_child(ball)
					ball.velocity = Vector2(speed, 0)
					await create_timer(0.04).timeout
					check(ball.velocity.x < 0, "Top, middle and bottom of both poses must rebound at all speeds")
					if speed < 320:
						check(player.knockback_velocity == Vector2.ZERO, "Slow rebounds must not push")
					ball.queue_free()
					await process_frame
				player.queue_free()
				await process_frame
	print("Full-body collision checks completed; failures: ", failures)
	quit(1 if failures else 0)
