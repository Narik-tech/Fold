# Regular 4D shape samples

Open **4D Samples** in the FOLD Levels workspace, select a shape's **edge frame** or **solid faces** entry, and choose **Playtest**. All six regular convex 4D shapes have both versions. Each sample has one shape, a broad floor, two echoes, and an exit. Walking and folding are enough; jumping is optional.

| Shape | Edge frame resource | Solid faces resource |
| --- | --- | --- |
| 5-cell | `res://levels/samples/5_cell.tres` | `res://levels/samples/solid_5_cell.tres` |
| Tesseract | `res://levels/samples/tesseract.tres` | `res://levels/samples/solid_tesseract.tres` |
| 16-cell | `res://levels/samples/16_cell.tres` | `res://levels/samples/solid_16_cell.tres` |
| 24-cell | `res://levels/samples/24_cell.tres` | `res://levels/samples/solid_24_cell.tres` |
| 120-cell | `res://levels/samples/120_cell.tres` | `res://levels/samples/solid_120_cell.tres` |
| 600-cell | `res://levels/samples/600_cell.tres` | `res://levels/samples/solid_600_cell.tres` |

The names count three-dimensional cells. The tesseract has eight cubic cells; the 120-cell has 120 dodecahedral cells. A **solid faces** shape fills the entire convex four-dimensional volume. Its visible three-dimensional cross-section has opaque faces and a collidable interior. You cannot walk through the center. An **edge frame** has narrow solid beams along its edges, leaving its faces, cells, and interior open.

## Explore a solid faces sample

All six solid samples use scale **2.5**, with the shape centered at `(0, 1, 0, 0)`. Start at **X -6.5**, safely outside the shape, and keep **Z 0** throughout the route:

1. Hold **E** to **90°**, release, and walk along W to **W +2** for the first echo.
2. Continue to **W +4.5**, beyond the shape's full extent.
3. Walk along X to the second echo at **X 0**, then continue to **X +6.5**.
4. Walk back to **W 0** for the amber gate.

The route goes around the filled volume. Walking directly toward the center is blocked by its faces. Press **H** for the route hints. The solid can disappear when the slice moves beyond its boundary; it still occupies its original position in four-dimensional space.

## Explore an edge frame sample

Walk along X toward the first echo at the center. Press **Q** or **E** to expose W, then walk to **W +1.5** for the second echo. Return to **W 0** and continue to the amber gate at **X +6**. Keep the starting Z coordinate while following this route. The floor intersects the lower part of each frame so you can walk into its interior and around its beams.

The tesseract frame begins at its near cubic side, with the shape centered at **W +2.5**. Folding reveals the direction connecting that side to the far side. Other frames begin at **W 0** through their centers.

## What the slice shows

The game displays a three-dimensional **cross-section** at your current hidden coordinate. For a frame, a beam crossing the view can appear as a small block, while a beam running along the view appears as a rod. For a solid, the cross-section is a closed polyhedron whose faces change as you fold or move in W. Parts outside the slice still exist in the four-dimensional world.

## Adapt a shape

Use **Save As** to make your own level from a sample. Select its shape and edit:

- **Representation** to switch between **Edge frame** and **Solid faces**.
- **Position X/Y/Z/W** to move the whole shape.
- **Scale** to resize it uniformly. Scale is the circumradius: the distance from its center to every vertex.
- **Edge thickness** to set the full width of each beam in an edge frame. It is independent of Scale and does not apply to solid faces.

The traveler's collision body is 1.25 units tall and 0.54 units wide along X, Z, and W. Leave that much clearance around solids or between beams. Switching an open frame to solid faces can obstruct a route or enclose an echo, start, or exit; move those markers outside the filled shape and playtest the route.

To launch a solid sample directly:

```powershell
& '.tools/godot/Godot_v4.6-stable_win64_console.exe' --path . -- --level=res://levels/samples/solid_120_cell.tres
```

The samples are separate from the four campaign gardens. `tests/test_solid_samples.gd` checks all six outside routes through actual player movement and folding, verifies that direct movement into each solid is blocked, and collects both echoes before reaching the gate. `tests/test_shape_samples.gd` checks the recorded routes for the edge frame samples. Run `tests/solid_shape_preview.gd` without `--headless` to capture all six solid samples and two additional fold angles of the 120-cell.
