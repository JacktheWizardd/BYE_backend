#!/usr/bin/env python3
"""Insert or replace one release in the Sparkle appcast.

Items are keyed by build number (CFBundleVersion), which Sparkle compares.
Re-running for the same build replaces its item; a lower build than the newest
existing item is rejected so the feed can never offer a downgrade as latest.
"""
import argparse
import email.utils
import html
import pathlib
import re
import sys
import xml.etree.ElementTree as ET

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE)
S = "{%s}" % SPARKLE
EMPTY = """<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
<channel><title>BYE Updates</title></channel>
</rss>
"""


def inline(text: str) -> str:
    text = html.escape(text, quote=False)
    text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
    return re.sub(r"`(.+?)`", r"<code>\1</code>", text)


def release_notes(markdown: str) -> str:
    """HTML for the "What changed" section of the prerelease notes."""
    match = re.search(r"^## What changed\s*$(.*?)(?=^## |\Z)", markdown, re.M | re.S)
    if not match:
        raise ValueError("release notes need a '## What changed' section")
    items = [inline(line[2:].strip()) for line in match.group(1).splitlines() if line.startswith("- ")]
    if not items:
        raise ValueError("'## What changed' has no bullet items")
    return "<ul>" + "".join(f"<li>{item}</li>" for item in items) + "</ul>"


def parse_signature(output: str) -> tuple[str, int]:
    signature = re.search(r'sparkle:edSignature="([^"]+)"', output)
    length = re.search(r'length="(\d+)"', output)
    if not signature or not length:
        raise ValueError("sign_update output lacks edSignature/length")
    return signature.group(1), int(length.group(1))


def update(feed: str, *, version: str, build: int, url: str, signature: str, length: int,
           notes: str, minimum_system: str = "14.0", date: str | None = None) -> str:
    root = ET.fromstring(feed)
    channel = root.find("channel")
    if channel is None:
        raise ValueError("appcast has no channel")
    existing = [item for item in channel.findall("item")]
    builds = [int(item.findtext(S + "version", "0")) for item in existing]
    if builds and build < max(builds):
        raise ValueError(f"build {build} is lower than newest appcast build {max(builds)}")
    for item, old in zip(existing, builds):
        if old == build:
            channel.remove(item)
    item = ET.Element("item")
    ET.SubElement(item, "title").text = f"BYE {version}"
    ET.SubElement(item, "pubDate").text = date or email.utils.formatdate(usegmt=True)
    ET.SubElement(item, S + "version").text = str(build)
    ET.SubElement(item, S + "shortVersionString").text = version
    ET.SubElement(item, S + "minimumSystemVersion").text = minimum_system
    ET.SubElement(item, "description").text = notes
    ET.SubElement(item, "enclosure", {"url": url, "length": str(length),
                                      "type": "application/octet-stream", S + "edSignature": signature})
    # Newest first, after channel metadata.
    position = next((i for i, child in enumerate(channel) if child.tag == "item"), len(channel))
    channel.insert(position, item)
    ET.indent(root)
    return '<?xml version="1.0" encoding="utf-8"?>\n' + ET.tostring(root, encoding="unicode") + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--appcast", type=pathlib.Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", type=int, required=True)
    parser.add_argument("--url", required=True)
    parser.add_argument("--signature-output", required=True, help="sign_update output")
    parser.add_argument("--notes", type=pathlib.Path, required=True)
    args = parser.parse_args()
    if not args.url.startswith(("https://", "http://127.0.0.1", "http://localhost")):
        print("Appcast enclosure URL must use HTTPS.", file=sys.stderr)
        return 1
    signature, length = parse_signature(args.signature_output)
    feed = args.appcast.read_text() if args.appcast.exists() else EMPTY
    args.appcast.write_text(update(feed, version=args.version, build=args.build, url=args.url,
                                   signature=signature, length=length,
                                   notes=release_notes(args.notes.read_text())))
    print(f"Updated {args.appcast} for {args.version} (build {args.build})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
