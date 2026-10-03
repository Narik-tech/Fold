#!/usr/bin/env python3
"""Package a standalone Godot export using only Python's standard library."""

import argparse
import io
from pathlib import Path
import re
import subprocess
import tarfile
import zipfile


ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", required=True, choices=("windows", "linux"))
    parser.add_argument("--version", required=True)
    parser.add_argument("--build-dir", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args()
    if not re.fullmatch(r"v\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?", args.version):
        parser.error("version must be a release tag such as v0.1.0")

    executable = "Fold.exe" if args.platform == "windows" else "Fold.x86_64"
    build_dir = args.build_dir.resolve()
    for name in (executable, "Fold.pck"):
        if not (build_dir / name).is_file() or (build_dir / name).stat().st_size == 0:
            parser.error(f"missing or empty export: {build_dir / name}")

    # Include platform libraries emitted by Godot, but never intermediate logs.
    files = {executable: build_dir / executable, "Fold.pck": build_dir / "Fold.pck"}
    for path in sorted(build_dir.rglob("*")):
        if path.is_file() and (path.suffix.lower() == ".dll" or ".so" in path.suffixes):
            files[path.relative_to(build_dir).as_posix()] = path
    files["LICENSE"] = ROOT / "LICENSE"
    for name in ("README.txt", "GODOT_LICENSE.txt", "GODOT_COPYRIGHT.txt"):
        files[name] = ROOT / "distribution" / name

    # git archive substitutes this marker, allowing source downloads to be
    # repackaged without a .git directory or Git installed.
    commit = (ROOT / "distribution" / "SOURCE_COMMIT.txt").read_text().strip()
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        try:
            commit = subprocess.check_output(
                ["git", "-c", f"safe.directory={ROOT.as_posix()}", "rev-parse", "HEAD"],
                cwd=ROOT, text=True, stderr=subprocess.DEVNULL,
            ).strip()
        except (FileNotFoundError, subprocess.CalledProcessError):
            parser.error("source commit is unavailable; use a Git checkout or an official source archive")
    source = (
        f"FOLD {args.version}\nSource commit: {commit}\n\n"
        f"Corresponding source: FOLD-{args.version}-source.tar.gz on this release:\n"
        f"https://github.com/Narik-tech/Fold/releases/tag/{args.version}\n\n"
        f"Source tree: https://github.com/Narik-tech/Fold/tree/{commit}\n"
        "Build instructions: docs/RELEASING.md in the source archive.\n"
        "Build with Godot 4.6 stable and its official export templates.\n\n"
        "FOLD is licensed under GPL-3.0-only; see LICENSE.\n"
        "The unmodified Godot runtime and bundled libraries have separate licenses;\n"
        "see GODOT_LICENSE.txt and GODOT_COPYRIGHT.txt.\n"
    ).encode("utf-8")

    folder = f"FOLD-{args.version}-{args.platform}-x86_64"
    args.output_dir.mkdir(parents=True, exist_ok=True)
    extension = ".zip" if args.platform == "windows" else ".tar.gz"
    destination = args.output_dir / (folder + extension)
    if destination.exists():
        parser.error(f"refusing to overwrite {destination}")

    if args.platform == "windows":
        with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for name, path in sorted(files.items()):
                archive.write(path, f"{folder}/{name}")
            archive.writestr(f"{folder}/SOURCE.txt", source)
    else:
        with tarfile.open(destination, "w:gz") as archive:
            for name, path in sorted(files.items()):
                info = archive.gettarinfo(str(path), f"{folder}/{name}")
                info.mode = 0o755 if name == executable else 0o644
                info.uid = info.gid = 0
                info.uname = info.gname = ""
                with path.open("rb") as data:
                    archive.addfile(info, data)
            info = tarfile.TarInfo(f"{folder}/SOURCE.txt")
            info.size = len(source)
            info.mode = 0o644
            archive.addfile(info, io.BytesIO(source))
    print(destination.resolve())


if __name__ == "__main__":
    main()
