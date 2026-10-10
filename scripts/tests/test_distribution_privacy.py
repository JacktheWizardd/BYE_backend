import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("privacy", Path(__file__).parents[1] / "check-distribution-privacy.py")
privacy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(privacy)


class DistributionPrivacyTests(unittest.TestCase):
    def test_binary_paths_and_utf16_are_detected(self):
        for encoding in ("utf-8", "utf-16-le", "utf-16-be"):
            for text in ("/Users/FictionalBuilder/project", "/private/var/folders/example", "/var/folders/example"):
                with self.subTest(encoding=encoding, text=text):
                    self.assertIn("personal filesystem path", privacy.violations(b"\0\0" + text.encode(encoding)))

    def test_username_detected_without_printing_its_value(self):
        self.assertIn("local username", privacy.violations(b"metadata\0FictionalBuilder\0", Path("/home/FictionalBuilder")))
        self.assertNotIn("local username", privacy.violations(b"FictionalBuilders", Path("/home/FictionalBuilder")))

    def test_private_key_marker_and_token_are_detected(self):
        for data in (b"-----BEGIN OPENSSH PRIVATE KEY-----", b"ghp_" + b"fictional" * 5):
            self.assertIn("possible credential", privacy.violations(data))

    def test_neutral_paths_and_credits_are_allowed(self):
        self.assertEqual(privacy.violations(b"/build/BYE/Sources/main.swift\0MIT License\0/Applications\0"), set())

    def test_recursive_package_and_symlink_checks(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            (root / "Applications").symlink_to("/Applications")
            (root / "Contents").mkdir()
            file = root / "Contents" / "binary"
            file.write_bytes(b"/build/BYE")
            self.assertTrue(privacy.check(root))
            file.write_bytes(b"/Users/FictionalBuilder/project")
            self.assertFalse(privacy.check(root))


if __name__ == "__main__":
    unittest.main()
