#!/usr/bin/env python3
"""Local app/source milestones. Never include caches, Git, or user data."""
import datetime
import hashlib
import json
import pathlib
import sys
import tarfile
import tempfile

root = pathlib.Path(__file__).resolve().parent.parent
phase = sys.argv[1] if len(sys.argv) >= 2 else "manual"
app_name = sys.argv[2] if len(sys.argv) >= 3 else "BYE.app"
if app_name not in {"BYE.app", "BYE Apple AI Beta.app", "BYE Beta.app"}:
    raise SystemExit("Unknown app name")
if phase not in {"before-build", "after-build", "manual"}:
    raise SystemExit("Expected before-build, after-build, or manual")
history = root / "archive" / "app-history"
history.mkdir(parents=True, exist_ok=True)
stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S")
destination = pathlib.Path(tempfile.mkdtemp(prefix=f"{stamp}-{phase}-", dir=history))
files = []
for entry in ["Package.swift", "README.md", "THIRD_PARTY_NOTICES.md", ".gitignore", "Sources", "Tests", "scripts", "docs"]:
    path = root / entry
    candidates = path.rglob("*") if path.is_dir() else [path]
    files.extend(p for p in candidates if p.is_file() and not p.is_symlink() and "__pycache__" not in p.parts and p.name != ".DS_Store")

def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()

with tarfile.open(destination / "source.tar.gz", "w:gz") as archive:
    for path in sorted(files):
        archive.add(path, arcname=str(path.relative_to(root)), recursive=False)
app = root / "dist" / app_name
executable = app / "Contents/MacOS/Classwise"
if app.is_dir():
    with tarfile.open(destination / (app_name + ".tar.gz"), "w:gz") as archive:
        archive.add(app, arcname=app_name)
manifest = {
    "createdAtUTC": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "phase": phase,
    "appName": app_name,
    "sourceSHA256": {str(p.relative_to(root)): digest(p) for p in sorted(files)},
    "executableSHA256": digest(executable) if executable.is_file() else None,
    "association": ("App built successfully from this source snapshot." if phase == "after-build" else
                    "Working source and previously packaged app captured separately. They may differ; use an after-build snapshot for a matched release."),
    "exclusions": ["Git metadata", "build caches", "Application Support", "private user data"],
}
(destination / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(f"Saved local {phase} history: {destination}")
