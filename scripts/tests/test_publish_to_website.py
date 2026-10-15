import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).parents[1] / file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


publisher = load("publisher", "publish-to-website.py")
appcast = load("appcast_for_publish", "make-appcast.py")
SITE = "https://bye-website.jack-truong2k1.workers.dev/updates/"


class PublishTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        root = Path(self.temp.name)
        self.dist, self.site = root / "dist", root / "site"
        self.dist.mkdir()
        (self.site / "public").mkdir(parents=True)
        self.metadata = root / "beta-version.sh"
        self.metadata.write_text('BETA_VERSION=0.3.0-beta.5\nBETA_BUILD=7\nBETA_APP_NAME="BYE Beta"\n')
        self.zip = self.write("BYE-0.3.0-beta.5-AppleSilicon.zip", b"zip-bytes")
        self.write("BYE-0.3.0-beta.5-AppleSilicon.dmg", b"dmg-bytes")
        self.appcast = root / "appcast.xml"
        self.write_appcast(SITE + self.zip.name, self.zip.stat().st_size)

    def tearDown(self):
        self.temp.cleanup()

    def write(self, name, data):
        path = self.dist / name
        path.write_bytes(data)
        (self.dist / (name + ".sha256")).write_text(f"{hashlib.sha256(data).hexdigest()}  {name}\n")
        return path

    def write_appcast(self, url, length, build=7):
        self.appcast.write_text(appcast.update(appcast.EMPTY, version="0.3.0-beta.5", build=build, url=url,
                                               signature="sig", length=length, notes="<ul></ul>"))

    def publish(self, **kwargs):
        return publisher.publish(self.site, dist=self.dist, appcast=self.appcast, metadata=self.metadata, **kwargs)

    def test_copies_release_and_adds_cache_rule_from_wrangler_jsonc(self):
        (self.site / "wrangler.jsonc").write_text('{\n  // static site\n  "name": "bye-website",\n  "assets": {"directory": "./public",},\n}\n')
        self.publish()
        public = self.site / "public"
        for path in ("updates/appcast.xml", "updates/BYE-0.3.0-beta.5-AppleSilicon.zip",
                     "updates/BYE-0.3.0-beta.5-AppleSilicon.zip.sha256",
                     "downloads/BYE-0.3.0-beta.5-AppleSilicon.dmg", "downloads/BYE-0.3.0-beta.5-AppleSilicon.dmg.sha256"):
            self.assertTrue((public / path).is_file(), path)
        self.assertIn("/updates/appcast.xml\n  Cache-Control: public, max-age=300", (public / "_headers").read_text())

    def test_wrangler_toml_and_existing_headers_kept(self):
        (self.site / "wrangler.toml").write_text('name = "bye-website"\n[assets]\ndirectory = "public"\n')
        (self.site / "public/_headers").write_text("/*\n  X-Frame-Options: DENY")
        self.publish(downloads="files")
        self.publish(downloads="files")
        headers = (self.site / "public/_headers").read_text()
        self.assertTrue(headers.startswith("/*\n  X-Frame-Options: DENY\n"))
        self.assertEqual(headers.count("/updates/appcast.xml"), 1)
        self.assertTrue((self.site / "public/files/BYE-0.3.0-beta.5-AppleSilicon.dmg").is_file())

    def test_explicit_assets_without_wrangler(self):
        self.publish(assets=Path("public"))
        self.assertTrue((self.site / "public/updates/appcast.xml").is_file())
        with self.assertRaises(publisher.PublishError):
            self.publish()

    def test_mismatched_enclosure_refused_before_copying(self):
        self.write_appcast("https://example.com/other.zip", self.zip.stat().st_size)
        with self.assertRaises(publisher.PublishError):
            self.publish(assets=Path("public"))
        self.assertFalse((self.site / "public/updates").exists())

    def test_wrong_build_length_or_checksum_refused(self):
        self.write_appcast(SITE + self.zip.name, self.zip.stat().st_size, build=6)
        with self.assertRaises(publisher.PublishError):
            self.publish(assets=Path("public"))
        self.write_appcast(SITE + self.zip.name, 1)
        with self.assertRaises(publisher.PublishError):
            self.publish(assets=Path("public"))
        self.write_appcast(SITE + self.zip.name, self.zip.stat().st_size)
        self.zip.write_bytes(b"changed!!")
        with self.assertRaises(publisher.PublishError):
            self.publish(assets=Path("public"))


if __name__ == "__main__":
    unittest.main()
