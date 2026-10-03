Play **FOLD - The Quiet Dimension**, a four-dimensional puzzle platformer with five floating gardens, continuous Q/E folding, echo checkpoints, and a shape-to-shape jumping course.

### Downloads

- **Windows (64-bit Intel/AMD):** download `FOLD-v0.1.0-windows-x86_64.zip`, extract the entire archive, then run `Fold.exe`.
- **Linux (64-bit Intel/AMD):** download `FOLD-v0.1.0-linux-x86_64.tar.gz`, extract it, then run `./Fold.x86_64`. If needed, run `chmod +x Fold.x86_64` first.

Keep `Fold.pck` alongside the executable. Godot is bundled; no separate engine installation is needed. The game uses OpenGL Compatibility rendering and requires a desktop display, working graphics drivers, a keyboard, and a mouse.

### Controls

Mouse to look; WASD/arrows to move; Space to jump; hold Q/E to fold; H for hints; R to restart; Escape to pause, select a chapter, or quit; M to mute.

**Progress lasts for the current session only.** Echo checkpoints in the labyrinth and folded ascent persist until you restart the chapter or close the game.

### Source and verification

The release includes corresponding source in `FOLD-v0.1.0-source.tar.gz`, license notices in each playable package, and `SHA256SUMS.txt` for verifying the downloads. Source and build instructions are also available at this release's Git tag. FOLD is licensed under GPL-3.0-only; Godot retains its own licenses.

Built with official Godot 4.6 stable export templates. The release workflow runs the project's 17 regression scripts and checks that the extracted game starts on both Windows and Linux before publishing.
