#!/usr/bin/env python3
"""Reject identifying local build paths and common credentials in release files.

This is a targeted packaging gate, not a comprehensive secret/privacy audit.
Never print matched bytes: diagnostics identify only the affected file/category.
"""
import pathlib
import re
import sys


def violations(data: bytes, home: pathlib.Path | None = None) -> set[str]:
    home = home or pathlib.Path.home()
    found = set()
    for encoding in ("utf-8", "utf-16-le", "utf-16-be"):
        text = data.decode(encoding, errors="ignore")
        if re.search(r"/Users/|/(?:private/)?var/folders/", text):
            found.add("personal filesystem path")
        username = home.name
        if len(username) >= 4 and re.search(r"(?<![\w])" + re.escape(username) + r"(?![\w])", text, re.I):
            found.add("local username")
        if re.search(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|\b(?:ghp_|github_pat_|sk-proj-)[A-Za-z0-9_-]{10,}|\bAKIA[A-Z0-9]{16}\b", text):
            found.add("possible credential")
    return found


def check(root: pathlib.Path) -> bool:
    failures = []
    for path in sorted(root.rglob("*")):
        if path.is_symlink():
            data = str(path.readlink()).encode()
        elif path.is_file():
            data = path.read_bytes()
        else:
            continue
        for category in sorted(violations(data)):
            failures.append((str(path.relative_to(root)), category))
    for name, category in failures:
        print(f"Distribution privacy check failed: {name}: {category}", file=sys.stderr)
    if not failures:
        print("Distribution privacy check passed.")
    return not failures


if __name__ == "__main__":
    if len(sys.argv) != 2 or not pathlib.Path(sys.argv[1]).is_dir():
        raise SystemExit("Usage: check-distribution-privacy.py DIRECTORY")
    raise SystemExit(0 if check(pathlib.Path(sys.argv[1])) else 1)
