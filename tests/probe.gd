extends SceneTree
## Probe: replicate the rules-test sequence frame by frame, headless.

func _initialize() -> void:
	var game: Node2D = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	_run(game)


func _run(game: Node2D) -> void:
	for i in 5:
		await process_frame
	print("PHASE boot state=", game.state)
	game.segments[1] = game.Side.RIGHT
	game.chop(game.Side.LEFT)          # chips + flying log spawn
	for i in 10:
		await process_frame
	print("PHASE after-chop state=", game.state)
	game.time_left = 0.001
	for i in 30:
		await process_frame
	print("PHASE after-death state=", game.state)
	for i in 40:
		await process_frame
	print("PHASE game-over state=", game.state)
	game._reset()
	for i in 20:
		await process_frame
	print("PHASE reset state=", game.state)
	quit(0)
