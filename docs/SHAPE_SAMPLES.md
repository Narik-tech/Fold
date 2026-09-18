# Regular 4D shape samples

Open **4D Samples** in the FOLD Levels workspace, select a shape, and choose **Playtest**. Each sample is a small playground with one shape, a broad floor, two echoes, and an exit. All six can be completed by walking and folding; jumping is optional.

| Sample | Resource | Solid edges |
| --- | --- | --- |
| 5-cell | `res://levels/samples/5_cell.tres` | 10 |
| Tesseract | `res://levels/samples/tesseract.tres` | 32 |
| 16-cell | `res://levels/samples/16_cell.tres` | 24 |
| 24-cell | `res://levels/samples/24_cell.tres` | 96 |
| 120-cell | `res://levels/samples/120_cell.tres` | 1,200 |
| 600-cell | `res://levels/samples/600_cell.tres` | 720 |

The names count three-dimensional cells, not edges. Cells and faces are open: only the narrow beams along the edges collide with the traveler. The floor intersects the lower part of each shape so you can walk into its interior and around its beams.

## Explore a sample

Walk along X toward the first echo at the center. Press **Q** or **E** to expose W, then walk to **W +1.5** for the second echo. Return to **W 0** and continue to the amber gate at **X +6**. Keep the starting Z coordinate while following this short route. Press **H** for the sample's hints.

The game shows a three-dimensional **cross-section** of the shape at your current hidden coordinate. A beam crossing the view can appear as a small block; a beam running along the view appears as a long rod. Folding or moving in W changes the cross-section. Parts outside the slice still exist in the four-dimensional world.

The tesseract sample begins at its near cubic side, with the shape centered at **W +2.5**. This makes the cube's edges visible immediately. Folding reveals the direction connecting that side to the far side. Other shapes begin at **W 0** through their centers.

## Adapt a shape

Use **Save As** to make your own level from a sample. Select its shape and edit:

- **Position X/Y/Z/W** to move the whole frame.
- **Scale** to resize the frame uniformly. Scale is its circumradius: the distance from its center to each vertex. All samples use scale **5**.
- **Edge thickness** to set the full width of each solid beam. It is independent of Scale, so enlarging a frame keeps its beams thin unless you change this control too. Samples use **0.12–0.16**.

The traveler's collision body is 1.25 units tall and 0.54 units wide along X, Z, and W. Leave gaps wider than that body. A larger scale can make the dense 120-cell and 600-cell easier to explore. Inspect both editor projections and playtest after changing size, thickness, or position.

To launch a sample directly:

```powershell
& '.tools/godot/Godot_v4.6-stable_win64_console.exe' --path . -- --level=res://levels/samples/120_cell.tres
```

The samples are separate from the three campaign gardens. Their saved solution routes are checked by `tests/test_shape_samples.gd`, which walks the actual player through each frame, folds in W, collects both echoes, and reaches the gate.

