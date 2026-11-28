extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func check_spacing(game: Node2D, context: String) -> void:
	for i in range(game.players.size()):
		var player: Node2D = game.players[i]
		var bounds: Rect2 = player.placement_bounds(player.global_position)
		for j in range(i + 1, game.players.size()):
			var other: Node2D = game.players[j]
			check(not bounds.grow(1.5).intersects(other.placement_bounds(other.global_position).grow(1.5)), context + ": standing bodies must have room between " + player.name + " and " + other.name)

func _run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.blue_ai_enabled = false
	root.add_child(game)
	await physics_frame
	for team in [0, 1]:
		var keeper = game._goalkeeper(team)
		check(keeper.team_texture.resource_path == "res://aset/keeper%d.png" % (team + 1), "New keeper sheet must be assigned to corresponding team")
		var idle_pixels: Rect2i = keeper.team_texture.get_image().get_region(Rect2i(keeper.idle_region)).get_used_rect()
		var flat_pixels: Rect2i = keeper.team_texture.get_image().get_region(Rect2i(keeper.slap_region)).get_used_rect()
		check(idle_pixels.size.x == 30 and flat_pixels.size.x == 52, "Both keeper poses must include the entire painted body")
		for bottom in [false, true]:
			for kind in ["Out", "Corner"]:
				game.reset_match()
				var progress := 0.75 if kind == "Out" else 1.0
				var x: float = progress if team == 0 else 1 - progress
				var point: Vector2 = game.PITCH.position + Vector2(x * game.PITCH.size.x, game.PITCH.size.y if bottom else 0.0)
				game._award_restart(kind, team, point, Vector2.UP if bottom else Vector2.DOWN)
				check_spacing(game, "Restart")
				var previous = game.restart_taker
				var direction := 1.0 if team == 0 else -1.0
				var advanced_before: Array = []
				for player in game.players:
					if player.team == team and not player.is_goalkeeper and (player.center().x - game.PITCH.get_center().x) * direction > 0:
						advanced_before.append(player)
				game.restart_taker = null
				game.restart_kind = ""
				game.ball.last_kicker = previous
				game.ball.last_touch = previous
				var defender = game.get_node("Players/BluePlayer4" if team == 0 else "Players/RedPlayer4")
				game.ball.place_for_restart(defender.foot_position(), null)
				game.ball.last_kicker = previous
				game.ready_player = null
				game._pickup_locked = false
				game._ensure_ready_kicker()
				check(game.ready_player.team != team and game.ready_player.can_reach(game.ball), "Defender must retain recovered ball at feet")
				var retreated := 0
				for player in advanced_before:
					var bounds: Rect2 = player.placement_bounds(player.global_position)
					if (bounds.end.x < 800 if team == 0 else bounds.position.x > 800):
						retreated += 1
				check(retreated == 2, "Exactly two advanced attackers must fall fully behind halfway")
				check_spacing(game, "Turnover")
				var positions: Array = game.players.map(func(player): return player.position)
				game._ensure_ready_kicker()
				check(positions == game.players.map(func(player): return player.position), "Same stationary possession must not trigger repeated retreats")
	# Dense teleport setup must resolve immediately, without a physics-frame refresh.
	game.reset_match()
	for player in game.players:
		if not player.is_goalkeeper:
			player.position = Vector2(800, 550)
	game._separate_players()
	check_spacing(game, "Crowded arrangement")
	# A keeper returning home must also relocate anyone blocking that spot.
	var keeper = game._goalkeeper(0)
	var blocker = game.get_node("Players/BluePlayer1")
	blocker.position = game._keeper_homes[keeper]
	keeper.position += Vector2(80, 0)
	game.ready_player = null
	game._keeper_recoveries[keeper] = 0.01
	game._update_keeper_recovery(0.1)
	check_spacing(game, "Keeper home recovery")
	game._award_restart("Tendangan gawang", 1, game._keeper_homes[game._goalkeeper(1)] + game._goalkeeper(1).foot_offset(), Vector2.LEFT)
	check_spacing(game, "Goal kick")
	game.reset_match()
	check_spacing(game, "Reset")
	# Ordinary alternating shots must retain the original formation.
	for team in [0, 1]:
		game.reset_match()
		var previous = game.get_node("Players/RedPlayer4" if team == 0 else "Players/BluePlayer4")
		var defender = game.get_node("Players/BluePlayer1" if team == 0 else "Players/RedPlayer1")
		game.ball.place_for_restart(defender.foot_position(), null)
		game.ball.last_kicker = previous
		game._pickup_locked = false
		game.ready_player = null
		var before: Array = game.players.map(func(player): return player.position)
		game._ensure_ready_kicker()
		check(game.ready_player.team != team, "Open-play defender must win possession")
		check(before == game.players.map(func(player): return player.position), "Ordinary possession change must not rearrange standing players")
		check_spacing(game, "Open-play turnover")
	game.match_audio.reset_effects()
	await create_timer(0.12).timeout
	game.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	print("Turnover and spacing checks completed; failures: ", failures)
	quit(1 if failures else 0)
