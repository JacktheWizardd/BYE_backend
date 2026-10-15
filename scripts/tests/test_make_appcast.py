import importlib.util
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

spec = importlib.util.spec_from_file_location("appcast", Path(__file__).parents[1] / "make-appcast.py")
appcast = importlib.util.module_from_spec(spec)
spec.loader.exec_module(appcast)
S = appcast.S
URL = "https://bye-website.jack-truong2k1.workers.dev/updates/BYE-{0}-AppleSilicon.zip"
NOTES = "# BYE\n\n## What changed\n\n- Added **updates** & `zip` <safe>.\n- Second item.\n\n## Install\n\n- Not a change.\n"


def add(feed, version, build, signature="sig"):
    return appcast.update(feed, version=version, build=build, url=URL.format(version), signature=signature,
                          length=123, notes=appcast.release_notes(NOTES), date="Wed, 14 Oct 2026 12:00:00 GMT")


def items(feed):
    return ET.fromstring(feed).find("channel").findall("item")


class AppcastTests(unittest.TestCase):
    def test_insert_into_empty_feed(self):
        [item] = items(add(appcast.EMPTY, "0.3.0-beta.5", 7))
        self.assertEqual(item.findtext(S + "version"), "7")
        self.assertEqual(item.findtext(S + "shortVersionString"), "0.3.0-beta.5")
        self.assertEqual(item.findtext(S + "minimumSystemVersion"), "14.0")
        enclosure = item.find("enclosure")
        self.assertEqual(enclosure.get("url"), URL.format("0.3.0-beta.5"))
        self.assertEqual(enclosure.get(S + "edSignature"), "sig")
        self.assertEqual(enclosure.get("length"), "123")

    def test_newer_build_first_and_older_kept(self):
        feed = add(add(appcast.EMPTY, "0.3.0-beta.5", 7), "0.3.0-beta.6", 8)
        self.assertEqual([i.findtext(S + "version") for i in items(feed)], ["8", "7"])

    def test_same_build_replaced(self):
        feed = add(add(appcast.EMPTY, "0.3.0-beta.5", 7, "old"), "0.3.0-beta.5", 7, "new")
        [item] = items(feed)
        self.assertEqual(item.find("enclosure").get(S + "edSignature"), "new")

    def test_lower_build_rejected(self):
        feed = add(appcast.EMPTY, "0.3.0-beta.6", 8)
        with self.assertRaises(ValueError):
            add(feed, "0.3.0-beta.5", 7)

    def test_release_notes_escaped_and_scoped(self):
        notes = appcast.release_notes(NOTES)
        self.assertEqual(notes, "<ul><li>Added <strong>updates</strong> &amp; <code>zip</code> &lt;safe&gt;.</li>"
                                "<li>Second item.</li></ul>")
        self.assertIn("&lt;strong&gt;", add(appcast.EMPTY, "0.3.0-beta.5", 7))

    def test_signature_output_parsed(self):
        self.assertEqual(appcast.parse_signature('sparkle:edSignature="abc+/=" length="4567"'), ("abc+/=", 4567))
        with self.assertRaises(ValueError):
            appcast.parse_signature("error")


if __name__ == "__main__":
    unittest.main()
