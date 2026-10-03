# Desktop releases

FOLD uses **Godot 4.6 stable**, its matching standard (non-.NET) export templates,
and Python 3 for packaging. `export_presets.cfg` defines 64-bit Windows and Linux
release exports. Players do not need the editor or Python.

## Build locally

Install the editor and matching export templates from the
[official Godot 4.6 release](https://github.com/godotengine/godot-builds/releases/tag/4.6-stable).
Verify the downloaded files against that release's `SHA512-SUMS.txt`.
On a fresh checkout, import the project once:

```text
godot --headless --editor --path . --quit
```

Create `builds/windows`, `builds/linux`, and `builds/release`, then run:

```text
godot --headless --path . --export-release "Windows Desktop" builds/windows/Fold.exe
godot --headless --path . --export-release "Linux" builds/linux/Fold.x86_64
python scripts/package_release.py --platform windows --version v0.1.0 --build-dir builds/windows --output-dir builds/release
python scripts/package_release.py --platform linux --version v0.1.0 --build-dir builds/linux --output-dir builds/release
```

Use the path to your Godot executable in place of `godot`. On this Windows
workspace it is `.tools/godot/Godot_v4.6-stable_win64_console.exe`. Use an empty
output directory for each release: the packager refuses to overwrite archives.

Each archive contains the executable, its adjacent `Fold.pck`, player
instructions, FOLD's license, Godot's license and third-party notices, and a
pointer to the exact source commit. The Linux tar archive records executable
permissions. Runtime resources include all five campaign levels and the shape
samples; editor tooling, tests, documentation, and generated builds are excluded.

Run the regression commands in the main README before publishing. Extract each
archive outside the source directory and check it on the target operating
system, so the game cannot accidentally load files from the source checkout:

```text
Fold.exe --headless --quit-after 60
./Fold.x86_64 --headless --quit-after 60
```

Also launch normally to check graphics, input, and sound. Automated startup
checks do not replace interactive playtesting.

## Publish on GitHub

The `Build and release` Actions workflow builds on native Windows and Linux
runners, validates downloads, runs the existing regression suite, packages the
game, and smoke-tests each extracted archive. The publish job runs only after
both platforms succeed. It adds a source archive and SHA-256 checksums, uploads
all four assets to a draft release, and then publishes it.

For a new version, update `distribution/RELEASE_NOTES.md`, the Windows version
fields in `export_presets.cfg`, and `config/version` in `project.godot`. Commit
the changes, create a new `vMAJOR.MINOR.PATCH` tag, and push that tag. Tags must
identify the exact source used for the binaries. The workflow also accepts a
manual dispatch with an existing tag. It does not overwrite existing releases.

The publish command uses `--verify-tag` and checks that the existing tag resolves
to the built commit. It deliberately omits `--target`: GitHub can require a
workflow-write permission when an explicit target has different workflow files
from the default branch, and `GITHUB_TOKEN` cannot receive that permission.
For an existing tag, `--target` does not determine the released source. See
[GitHub's release API documentation](https://docs.github.com/en/rest/releases/releases#create-a-release).

Godot notices in `distribution/GODOT_LICENSE.txt` and `GODOT_COPYRIGHT.txt` come
from the official `godotengine/godot` **4.6-stable** source tag. Refresh them when
upgrading the engine.

The source archive includes `distribution/SOURCE_COMMIT.txt`, expanded by
`git archive` to the release commit. This lets the same packaging commands work
from an extracted source download without Git installed.
