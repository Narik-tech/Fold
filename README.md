# FOLD — The Quiet Dimension

A playable, original four-dimensional puzzle platformer made in Godot. Explore three floating gardens, collect their echoes, and find the amber gate. Folding the view exchanges Z and W, exposing paths that lie outside your current three-dimensional slice.

Inspired by the spatial navigation described by [Miegakure](https://miegakure.com/). FOLD has its own levels, visuals, character, and synthesized audio.

![A hidden bridge revealed in the fourth dimension](docs/preview.png)

## Play

On this Windows workspace, double-click **PLAY.cmd**. A portable Godot 4.6 engine is already available in `.tools/godot`.

Alternatively, import **project.godot** into Godot 4.6 or newer and press **F5**. The project uses the Compatibility renderer and has no external asset dependencies. The included FOLD Levels add-on provides visual level authoring.

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

## Create a level

Double-click **EDIT_LEVELS.cmd**, or open the project in Godot and select the **FOLD Levels** workspace at the top of the editor. The bundled plugin is enabled in the project settings.

Start with **New**, add platforms and echoes, and drag them on the X/Z or X/W grid. Edit height and all four dimensions in the object controls. Set the start and gate, then use **Playtest** to try the garden in the actual game. Save your creation as a `.tres` file under `levels/custom/`; no scripting is required. See [the level editor guide](docs/LEVEL_EDITOR.md) for controls and geometry tips.

## Project structure

- `scenes/main.tscn` and `scripts/main.gd`: compose the game systems; coordinate 4D movement, collision, and session state.
- `game/world_view.tscn` and `game/world_view.gd`: own environment, traveler, level geometry, and slice rendering.
- `levels/`: typed `FoldLevel` / `FoldBox` resources and the three campaign gardens as editable `.tres` files.
- `scripts/level_data.gd`: explicit campaign catalog; returns independent runtime snapshots.
- `scripts/slice_geometry.gd`: pure slab intersection and collision calculations.
- `scripts/game_hud.gd` and `scripts/soundscape.gd`: UI signals and audio, wired by the main scene controller.
- `addons/fold_level_editor/`: visual authoring workspace, document history, and projection canvas.
- `assets/stone.gdshader`: tiled stone and garden surface material.
- `tests/`: geometry, gameplay, input, resource, and editor regression checks.

The structure follows Godot's guidance on [scene organization](https://docs.godotengine.org/en/stable/tutorials/best_practices/scene_organization.html), [resources for data](https://docs.godotengine.org/en/stable/tutorials/best_practices/node_alternatives.html), and [project organization](https://docs.godotengine.org/en/stable/tutorials/best_practices/project_organization.html). World, HUD, and audio have separate lifetimes within a composed scene; the controller supplies the world with data and connects UI signals. Level resources hold authoring data, while runtime dictionaries are isolated snapshots. Input actions live in Project Settings, and documentation/generated captures are excluded from asset import with `.gdignore`.

Run tests from the project directory (replace the executable with your Godot path on other machines):

```powershell
& '.tools/godot/Godot_v4.6-stable_win64_console.exe' --headless --path . --script tests/test_slice_geometry.gd
& '.tools/godot/Godot_v4.6-stable_win64_console.exe' --headless --path . --script tests/test_playthrough.gd
& '.tools/godot/Godot_v4.6-stable_win64_console.exe' --headless --path . --script tests/test_interactions.gd
& '.tools/godot/Godot_v4.6-stable_win64_console.exe' --headless --path . --script tests/test_level_resources.gd
& '.tools/godot/Godot_v4.6-stable_win64_console.exe' --headless --path . --script tests/test_custom_levels.gd
& '.tools/godot/Godot_v4.6-stable_win64_console.exe' --headless --path . --script tests/test_level_editor.gd
& '.tools/godot/Godot_v4.6-stable_win64_console.exe' --headless --path . --script tests/test_editor_ui.gd
```

To produce a rendered screenshot in `test-output`, run with `-- --capture` or `-- --capture-title`. Add `--level2`, `--level3`, or `--folded` after the separator to inspect other views.

Run `--script tests/editor_preview.gd` without `--headless` to capture the editor panel at desktop and compact sizes. Add `-- --playtest` to the `test_editor_ui.gd` command to also launch and stop a real game window. Import the project once in the editor before running scripts on a fresh checkout so Godot registers the named resource classes.

To run a saved custom garden directly, append `-- --level=res://levels/custom/my_garden.tres`. For a persistent F5 override, assign a `FoldLevel` resource to the main scene's **Level Override** property in the Inspector. The campaign list is explicit in `scripts/level_data.gd`, so saving a draft never silently adds it to the campaign.
