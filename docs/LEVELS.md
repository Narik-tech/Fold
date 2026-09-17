# FOLD / The Quiet Dimension — original puzzle designs

These three original levels introduce movement through four spatial coordinates. X is always available, Y is height, and rotating exchanges the visible depth direction between Z and W. Rotation preserves the player's coordinates, including the hidden coordinate. Solving a puzzle therefore changes the player's position in four dimensions; it does not toggle arbitrary geometry.

All coordinates below are `(X, Y, Z, W)` at the player's feet. Collectible coordinates in the `levels/*.tres` resources are floating centers, 0.85 units above the intended standing surface. Each resource also includes deterministic resting waypoints under `solution` and zero-based `jump_segments`: a value of 7 means jump from waypoint 7 to waypoint 8. `LevelData.solutions()` returns all waypoint arrays. Create and edit gardens visually using [FOLD Levels](LEVEL_EDITOR.md).

## 01 / A direction unseen

**Idea:** walk around a wall using W.

The wall at X 0 covers the whole traversable Z direction, but occupies only W -0.8 through +0.8. The floor continues in both Z and W. The collectible sits at W +2.4 on the wall's far-dimensional side; the exit sits at W 0.

1. Walk to X -2.2, before the wall.
2. Rotate to make W the depth direction, then move to W +2.4.
3. Cross X 0 and collect the echo. Continue to X +2.2.
4. Return to W 0 and walk to the exit at X +5.15.

The route needs no jumping. The wall is 3.7 units tall, well above the jump height. Its Z extent goes beyond the floor to discourage walking around its visible end.

## 02 / The missing span

**Idea:** use a bridge that occupies another W slice.

The islands end at X -2.8 and begin at X +2.8, leaving a 5.6-unit gap. A bridge crosses this gap only near W +2.65, with usable centerline Z 0. A jump with speed 4.2, launch velocity 7.2 and gravity 18 travels approximately 3.36 units on level ground, so the direct gap is too wide.

1. Stay on the first island at X -4, Z 0.
2. Rotate to W and move to W +2.65.
3. Walk across X along the bridge, collecting both echoes at X -1.4 and +1.4.
4. Reach X +4 on the far island before returning to W 0.
5. Walk to the exit at X +5.2.

Both bridge ends overlap the islands by 0.6 units. Its top matches the island tops at Y 0, so the entire intended route is walkable.

## 03 / Two turns from home

**Idea:** retain one hidden coordinate, switch back to the other direction, then climb.

The first wall, at X -2.7, is thin in W. The second wall, at X 0, is thin in Z and covers all traversable W. Three echoes mark the W bypass, the Z bypass, and the middle stair. The exit stands 2.4 units above the floor on the final stair.

1. Before the first wall, at X -4.1, rotate to W and move to W +2.4.
2. Cross to X -1.2 and collect the first echo.
3. While between the walls, return to W 0.
4. Rotate to Z, move to Z +2.4, and cross the second wall to X +0.85. Collect the second echo.
5. At X +0.85, return to Z 0. This narrow but safe strip lies between the wall and the first stair.
6. Jump onto the first stair at `(1.9, 0.8, 0, 0)`.
7. Jump onto the second stair at `(3.15, 1.6, 0, 0)` and collect its echo.
8. Jump onto the final stair at `(4.65, 2.4, 0, 0)` and walk to the exit.

Each rise is 0.8 units, below the approximately 1.44-unit jump apex. Stair footprints overlap slightly so there are no accidental cracks. The final platform is too high to reach directly from the ground. Both walls are 4 units tall.

## Geometry conventions for validation

- Floors are axis-aligned four-dimensional boxes with top Y 0. A player is 1.25 units tall, with horizontal radius 0.27 along X, Z, and W.
- An ordinary segment changes only X, Z, or W and keeps a supported feet height. It may require a view rotation before movement.
- A tagged jump segment links resting positions on adjacent stair tops. Interpolating it as a straight walking segment is not a valid collision test; use the game's jump physics.
- All routes keep both hidden and visible horizontal coordinates inside the supporting geometry.
- Wall lengths intentionally extend beyond the floor in the direction that should be blocked; their other dimension contains the intended bypass.
- The puzzles and geometry are original, inspired by the general concept of exploring four-dimensional spaces rather than reproducing another game's maps, assets, or narrative.
