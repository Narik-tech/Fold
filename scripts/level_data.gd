class_name LevelData
extends RefCounted
## Original four-dimensional puzzle dioramas.
## Vector4 axes are X, Y (height), Z, W. Platform tops and solution
## waypoints use the player's feet; seeds use their floating center.


static func all_levels() -> Array[Dictionary]:
	return [
		{
			"title": "01  /  A direction unseen",
			"subtitle": "The wall has another edge.",
			"lesson": "Rotate your view to walk along W. The same place can open in another direction.",
			"hints": [
				"This wall fills the Z direction, but it is thin along W.",
				"Before the wall, rotate to reveal W and walk toward W +2.4.",
				"Cross the wall's X position, collect the echo, then return to W 0 for the exit."
			],
			"start": Vector4(-5.1, 0.0, 0.0, 0.0),
			"goal": Vector4(5.15, 0.0, 0.0, 0.0),
			"goal_hint": "Return to W 0 on the far side.",
			"boxes": [
				_box(Vector4(0.0, -0.5, 0.0, 0.0), Vector4(13.0, 1.0, 7.2, 7.2), "stone"),
				_box(Vector4(0.0, 1.85, 0.0, 0.0), Vector4(0.65, 3.7, 10.0, 1.6), "wall")
			],
			"seeds": [Vector4(0.0, 0.85, 0.0, 2.4)],
			"solution": [
				Vector4(-5.1, 0.0, 0.0, 0.0),
				Vector4(-2.2, 0.0, 0.0, 0.0),
				Vector4(-2.2, 0.0, 0.0, 2.4),
				Vector4(0.0, 0.0, 0.0, 2.4),
				Vector4(2.2, 0.0, 0.0, 2.4),
				Vector4(2.2, 0.0, 0.0, 0.0),
				Vector4(5.15, 0.0, 0.0, 0.0)
			],
			"jump_segments": []
		},
		{
			"title": "02  /  The missing span",
			"subtitle": "A crossing, just out of plane.",
			"lesson": "A bridge can be present in the world and absent from your current slice.",
			"hints": [
				"The space between these islands is too wide for a jump.",
				"Rotate while still on the first island. Look along positive W for a narrow bridge.",
				"At Z 0, move to W +2.65. Walk across X, then return to W 0."
			],
			"start": Vector4(-5.2, 0.0, 0.0, 0.0),
			"goal": Vector4(5.2, 0.0, 0.0, 0.0),
			"goal_hint": "Find the bridge at W +2.65.",
			"boxes": [
				_box(Vector4(-4.65, -0.5, 0.0, 0.0), Vector4(3.7, 1.0, 7.2, 7.2), "stone"),
				_box(Vector4(4.65, -0.5, 0.0, 0.0), Vector4(3.7, 1.0, 7.2, 7.2), "stone"),
				_box(Vector4(0.0, -0.25, 0.0, 2.65), Vector4(6.8, 0.5, 1.7, 1.2), "bridge")
			],
			"seeds": [Vector4(-1.4, 0.85, 0.0, 2.65), Vector4(1.4, 0.85, 0.0, 2.65)],
			"solution": [
				Vector4(-5.2, 0.0, 0.0, 0.0),
				Vector4(-4.0, 0.0, 0.0, 0.0),
				Vector4(-4.0, 0.0, 0.0, 2.65),
				Vector4(-1.4, 0.0, 0.0, 2.65),
				Vector4(1.4, 0.0, 0.0, 2.65),
				Vector4(4.0, 0.0, 0.0, 2.65),
				Vector4(4.0, 0.0, 0.0, 0.0),
				Vector4(5.2, 0.0, 0.0, 0.0)
			],
			"jump_segments": []
		},
		{
			"title": "03  /  Two turns from home",
			"subtitle": "Carry one direction into another.",
			"lesson": "Keep your position in the hidden axis. Use both Z and W, then climb toward the last echo.",
			"hints": [
				"Pass the first wall at W +2.4 and collect the first echo.",
				"Between the walls, return to W 0. Rotate back to Z and pass the next wall at Z +2.4.",
				"After the second echo, stop at X +0.85 and return to Z 0. Jump up the three low steps."
			],
			"start": Vector4(-5.2, 0.0, 0.0, 0.0),
			"goal": Vector4(5.05, 2.4, 0.0, 0.0),
			"goal_hint": "The exit waits above Z 0, W 0.",
			"boxes": [
				_box(Vector4(0.0, -0.5, 0.0, 0.0), Vector4(13.0, 1.0, 7.2, 7.2), "stone"),
				_box(Vector4(-2.7, 2.0, 0.0, 0.0), Vector4(0.7, 4.0, 10.0, 1.8), "wall"),
				_box(Vector4(0.0, 2.0, 0.0, 0.0), Vector4(0.7, 4.0, 1.8, 10.0), "wall"),
				_box(Vector4(1.9, 0.4, 0.0, 0.0), Vector4(1.2, 0.8, 2.3, 2.3), "step"),
				_box(Vector4(3.2, 0.8, 0.0, 0.0), Vector4(1.5, 1.6, 2.3, 2.3), "step"),
				_box(Vector4(4.95, 1.2, 0.0, 0.0), Vector4(2.1, 2.4, 2.3, 2.3), "step")
			],
			"seeds": [
				Vector4(-1.2, 0.85, 0.0, 2.4),
				Vector4(0.85, 0.85, 2.4, 0.0),
				Vector4(3.15, 2.45, 0.0, 0.0)
			],
			"solution": [
				Vector4(-5.2, 0.0, 0.0, 0.0),
				Vector4(-4.1, 0.0, 0.0, 0.0),
				Vector4(-4.1, 0.0, 0.0, 2.4),
				Vector4(-1.2, 0.0, 0.0, 2.4),
				Vector4(-1.2, 0.0, 0.0, 0.0),
				Vector4(-1.2, 0.0, 2.4, 0.0),
				Vector4(0.85, 0.0, 2.4, 0.0),
				Vector4(0.85, 0.0, 0.0, 0.0),
				Vector4(1.9, 0.8, 0.0, 0.0),
				Vector4(3.15, 1.6, 0.0, 0.0),
				Vector4(4.65, 2.4, 0.0, 0.0),
				Vector4(5.05, 2.4, 0.0, 0.0)
			],
			"jump_segments": [7, 8, 9]
		}
	]


static func solutions() -> Array[Array]:
	var routes: Array[Array] = []
	for level in all_levels():
		routes.append(level["solution"])
	return routes


static func _box(center: Vector4, size: Vector4, kind: String) -> Dictionary:
	return {"center": center, "size": size, "kind": kind}
