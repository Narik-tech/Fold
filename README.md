# FOLD — The Quiet Dimension

A playable, original four-dimensional puzzle platformer made in Godot. Explore three floating gardens, collect their echoes, and find the amber gate. Folding the view exchanges Z and W, exposing paths that lie outside your current three-dimensional slice.

Inspired by the spatial navigation described by [Miegakure](https://miegakure.com/). FOLD has its own levels, visuals, character, and synthesized audio.

![A hidden bridge revealed in the fourth dimension](docs/preview.png)

## Play

On this Windows workspace, double-click **PLAY.cmd**. A portable Godot 4.6 engine is already available in `.tools/godot`.

Alternatively, import **project.godot** into Godot 4.3 or newer and press **F5**. The project uses the Compatibility renderer and has no add-ons or external asset dependencies. It was tested with Godot 4.6 on Windows.

| Input | Action |
| --- | --- |
| WASD / arrow keys | Move relative to the camera |
| Space | Jump |
| Q or E | Fold / unfold between XYZ and XYW |
| H | Show the next hint |
| R | Restart the current garden |
| Escape | Pause / resume |
| M | Mute / unmute |
| Enter | Start / continue after completion |
| 01 / 02 / 03 buttons | Choose a garden |

Fold while standing on a surface. Find every echo in the garden, then enter its gate. Falling returns you to the start and preserves collected echoes; restarting clears the garden. The orientation panel shows the visible axes and your coordinates. Each hint becomes more explicit when you press H again.

## Gardens

1. **A direction unseen:** walk around a wall's edge in W.
2. **The missing span:** discover a bridge outside the starting slice.
3. **Two turns from home:** preserve hidden coordinates, use both depth axes, and climb the final steps.

These are three short puzzle chambers rather than a full campaign. Progress is kept for the current session. Spoiler walkthroughs and geometry notes are in [docs/LEVELS.md](docs/LEVELS.md).

## How the fourth dimension works

Every solid, echo, and player position lives in `(x, y, z, w)`. Y is height. X is always available. In the normal view, movement changes Z and preserves W; folding swaps those roles. W is a spatial coordinate, not time or a separate level.

The renderer intersects each 4D axis-aligned box with a 3D hyperplane passing through the player. During the fold, it computes the exact box intersection at every intermediate Z–W angle. Collision remains in 4D, so changing the view never teleports through a solid. Walking pauses during the 0.7-second fold, and folds require ground contact.

The prototype supports one rotation plane, axis-aligned 4D solids, and a finite 4D player collision box. Faint silhouettes mark nearby solids touching the traveler's thickness just outside the visible slice. Trees are decorative cross-sections and have no collision. This is a focused implementation of the slice-navigation mechanic, not a general 4D physics engine.

## Project structure

- `scripts/main.gd`: 4D movement, collision, game state, procedural 3D scene.
- `scripts/slice_geometry.gd`: exact slab intersections and collision predicates.
- `scripts/level_data.gd`: original 4D gardens and solution waypoints.
- `scripts/game_hud.gd`: title, chapters, hints, coordinates, pause, completion.
- `scripts/soundscape.gd`: generated ambient sound and interaction cues.
- `assets/stone.gdshader`: tiled stone and garden surface material.
- `tests/`: headless geometry and real-physics playthrough checks.

Run tests from the project directory (replace the executable with your Godot path on other machines):

```powershell
& '.tools/godot/Godot_v4.6-stable_win64_console.exe' --headless --path . --script tests/test_slice_geometry.gd
& '.tools/godot/Godot_v4.6-stable_win64_console.exe' --headless --path . --script tests/test_playthrough.gd
& '.tools/godot/Godot_v4.6-stable_win64_console.exe' --headless --path . --script tests/test_interactions.gd
```

To produce a rendered screenshot in `test-output`, run with `-- --capture` or `-- --capture-title`. Add `--level2`, `--level3`, or `--folded` after the separator to inspect other views.
