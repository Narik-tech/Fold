# FOLD / The Quiet Dimension — original puzzle designs

These four original levels introduce movement through four spatial coordinates and combine it in a maze. X is always available, Y is height, and rotating exchanges the visible depth direction between Z and W. Rotation preserves the player's coordinates, including the hidden coordinate. Solving a puzzle therefore changes the player's position in four dimensions; it does not toggle arbitrary geometry.

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

## 04 / The fourfold labyrinth

**Idea:** learn the connections between two overlapping mazes, then climb above them and discover a route home.

The lower garden contains 18 rooms on a five-unit grid: X and Z are -5, 0, or +5; W is 0 or +5. Nineteen passages connect them into a maze with two loops. The floor is continuous beneath the rooms, corridors have at least 4.55 units of clear space, and 2.8-unit walls block jumping directly through the lower maze. Teal landmark rings identify rooms and fold courts. Echoes can be collected in any order.

X connects neighboring rooms; Z leads around each maze layer; W opens passages between the two layers. Y is essential to reach the fifth echo and gate. The ascent has four 0.8-unit jumps to Y 3.2. Broad sky bridges continue through W and Z before two more 0.8-unit jumps reach the gate at Y 4.8. Once above the maze, attentive players can also use wall tops as shortcuts.

Each named echo saves its safe feet position as the latest checkpoint. Falling preserves echoes, and R starts the chapter over. Amber rings mark collected echoes. H starts with the earliest missing echo after a pickup, advances through the route hints and gate hint, then cycles back while any echoes remain. Landmarks obey the same slice visibility as the world.

Spoiler route (hold E from 0° to approximately 90° to move in W; hold Q back toward 0° to move in Z):

1. **Lantern:** from `(-5, 0, -5, 0)`, walk along Z to the folding court at Z 0. Fold and walk to W +5. Return to Z movement and walk to Z -5.
2. **Orchard:** return to Z 0, walk across X to 0, follow Z to -5, then X to +5.
3. **Heart:** at Orchard, fold back to W 0. Cross X to 0, then Z to 0. This central room also connects back to the entrance court.
4. **Stillwater:** continue to Z +5 and X -5. Fold to W +5 to find the hidden alcove. The neighboring room at X 0 offers a second W passage, creating another short loop.
5. **Sky:** leave Stillwater along X to +5. Fold to W 0, then follow Z to 0. Pale steps lead east: jump to X 7 / Y 0.8, X 8.4 / Y 1.6, X 9.8 / Y 2.4, and X 11.2 / Y 3.2. Fold to W +5, follow the bridge back to X +5, then along Z to -5.
6. **Home:** stay at Z -5 / W +5 and cross the sky bridge toward negative X. Jump from X -1 to the stair at X -2.4 / Y 4.0, then onto the terrace at X -3.8 / Y 4.8. The amber gate waits at X -5.

The editable resource is `levels/04_the_fourfold_labyrinth.tres`. Its proof route has 31 supported waypoints and six jump segments. Gameplay tests run the complete route with real physics, check alternate loop traversal and out-of-order collection, and verify that the entrance walls block direct shortcuts.

## Geometry conventions for validation

- Floors are axis-aligned four-dimensional boxes with top Y 0. A player is 1.25 units tall, with horizontal radius 0.27 along X, Z, and W.
- An ordinary segment changes only X, Z, or W and keeps a supported feet height. It may require a view rotation before movement.
- A tagged jump segment links resting positions on adjacent stair tops. Interpolating it as a straight walking segment is not a valid collision test; use the game's jump physics.
- All routes keep both hidden and visible horizontal coordinates inside the supporting geometry.
- Wall lengths intentionally extend beyond the floor in the direction that should be blocked; their other dimension contains the intended bypass.
- The puzzles and geometry are original, inspired by the general concept of exploring four-dimensional spaces rather than reproducing another game's maps, assets, or narrative.
