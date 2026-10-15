#!/usr/bin/env python3
"""Copy a packaged BYE release into the website repository's static assets.

Run after scripts/package-beta.sh. Copies the appcast and the update zip into
<assets>/updates/ and the DMG into <assets>/<downloads>/, and makes sure
_headers keeps the appcast's cache short. It never commits, pushes or deploys:
review the website repository's diff, then commit and deploy it yourself.
"""
import argparse
import hashlib
import json
import pathlib
import re
import shutil
import sys
import tomllib
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parents[1]
S = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
HEADER_PATH = "/updates/appcast.xml"
HEADER_RULE = f"{HEADER_PATH}\n  Cache-Control: public, max-age=300\n"


class PublishError(Exception):
    pass


def beta_metadata(path: pathlib.Path) -> tuple[str, str]:
    values = dict(re.findall(r'^(BETA_VERSION|BETA_BUILD)="?([^"\n]+)"?$', path.read_text(), re.M))
    if set(values) != {"BETA_VERSION", "BETA_BUILD"}:
        raise PublishError(f"{path} lacks BETA_VERSION/BETA_BUILD")
    return values["BETA_VERSION"], values["BETA_BUILD"]


def strip_jsonc(text: str) -> str:
    """Remove // and /* */ comments outside strings, then trailing commas."""
    out, i, quote = [], 0, None
    while i < len(text):
        c = text[i]
        if quote:
            out.append(c)
            if c == "\\" and i + 1 < len(text):
                out.append(text[i + 1])
                i += 1
            elif c == quote:
                quote = None
        elif c == '"':
            quote = c
            out.append(c)
        elif text.startswith("//", i):
            i = text.find("\n", i)
            if i < 0:
                break
            continue
        elif text.startswith("/*", i):
            i = text.find("*/", i) + 2
            if i < 2:
                break
            continue
        else:
            out.append(c)
        i += 1
    return re.sub(r",(\s*[}\]])", r"\1", "".join(out))


def assets_directory(site: pathlib.Path) -> pathlib.Path:
    """The Worker's static-assets folder from its wrangler configuration."""
    for name in ("wrangler.toml", "wrangler.jsonc", "wrangler.json"):
        config = site / name
        if not config.exists():
            continue
        if name.endswith(".toml"):
            data = tomllib.loads(config.read_text())
        else:
            data = json.loads(strip_jsonc(config.read_text()))
        directory = (data.get("assets") or {}).get("directory")
        if directory:
            return (site / directory).resolve()
        raise PublishError(f"{name} has no assets.directory; pass --assets")
    raise PublishError("no wrangler.toml/jsonc/json found; pass --assets")


def sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def check_checksum(path: pathlib.Path) -> None:
    recorded = (path.parent / (path.name + ".sha256")).read_text().split()[0]
    if recorded != sha256(path):
        raise PublishError(f"{path.name} does not match its .sha256 file")


def check_appcast(appcast: pathlib.Path, build: str, zip_path: pathlib.Path) -> None:
    channel = ET.parse(appcast).getroot().find("channel")
    items = channel.findall("item") if channel is not None else []
    if not items:
        raise PublishError("appcast.xml has no releases")
    newest = max(items, key=lambda item: int(item.findtext(S + "version", "0")))
    if newest.findtext(S + "version") != build:
        raise PublishError(f"newest appcast build is {newest.findtext(S + 'version')}, expected {build}")
    enclosure = newest.find("enclosure")
    url = enclosure.get("url", "") if enclosure is not None else ""
    if not url.endswith("/updates/" + zip_path.name):
        raise PublishError(f"appcast enclosure {url!r} does not point at /updates/{zip_path.name}")
    if enclosure.get("length") != str(zip_path.stat().st_size):
        raise PublishError("appcast enclosure length does not match the zip")


def ensure_headers(assets: pathlib.Path) -> bool:
    """Add the short-cache rule for the appcast; returns True when changed."""
    headers = assets / "_headers"
    text = headers.read_text() if headers.exists() else ""
    if any(line.strip() == HEADER_PATH for line in text.splitlines()):
        return False
    if text and not text.endswith("\n"):
        text += "\n"
    headers.write_text(text + ("\n" if text else "") + HEADER_RULE)
    return True


def publish(site: pathlib.Path, *, assets: pathlib.Path | None = None, downloads: str = "downloads",
            dist: pathlib.Path = ROOT / "dist", appcast: pathlib.Path = ROOT / "appcast.xml",
            metadata: pathlib.Path = ROOT / "scripts/beta-version.sh") -> list[pathlib.Path]:
    version, build = beta_metadata(metadata)
    zip_path = dist / f"BYE-{version}-AppleSilicon.zip"
    dmg_path = dist / f"BYE-{version}-AppleSilicon.dmg"
    for path in (zip_path, dmg_path, appcast):
        if not path.exists():
            raise PublishError(f"missing {path}; run scripts/package-beta.sh first")
    check_checksum(zip_path)
    check_checksum(dmg_path)
    check_appcast(appcast, build, zip_path)
    assets = (site / assets).resolve() if assets else assets_directory(site)
    if not assets.is_dir():
        raise PublishError(f"assets folder {assets} does not exist")
    updates, downloads_dir = assets / "updates", assets / downloads
    updates.mkdir(exist_ok=True)
    downloads_dir.mkdir(parents=True, exist_ok=True)
    copied = []
    for source, folder in ((zip_path, updates), (zip_path.with_name(zip_path.name + ".sha256"), updates),
                           (dmg_path, downloads_dir), (dmg_path.with_name(dmg_path.name + ".sha256"), downloads_dir)):
        copied.append(pathlib.Path(shutil.copy2(source, folder / source.name)))
    # The appcast goes last so it never names a zip that is not in place.
    copied.append(pathlib.Path(shutil.copy2(appcast, updates / "appcast.xml")))
    if ensure_headers(assets):
        copied.append(assets / "_headers")
    return copied


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("website", type=pathlib.Path, help="website repository folder")
    parser.add_argument("--assets", type=pathlib.Path, help="static-assets folder, relative to the website folder")
    parser.add_argument("--downloads", default="downloads", help="folder for the DMG inside the assets folder")
    args = parser.parse_args()
    try:
        copied = publish(args.website.resolve(), assets=args.assets, downloads=args.downloads)
    except (PublishError, OSError, ValueError, ET.ParseError) as error:
        print(f"Publish failed: {error}", file=sys.stderr)
        return 1
    for path in copied:
        print(f"Wrote {path}")
    print("Review the website repository's changes, then commit and deploy it.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
