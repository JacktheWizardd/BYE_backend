import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).parents[1] / "schedule-api-config.sh"
# Fictional values only; real keys never appear in tests.
GOOD = "bye_pk_" + "Fictional0123456789abcdefABCDEF_-xyz"


def run(env=None, file_text=None):
    """Source the config in a clean temp directory and print the plist entries."""
    with tempfile.TemporaryDirectory() as root:
        if file_text is not None:
            (Path(root) / "config").mkdir()
            (Path(root) / "config" / "schedule-api.local").write_text(file_text)
        clean = {k: v for k, v in os.environ.items() if not k.startswith("BYE_SCHEDULE_API")}
        clean.update(env or {})
        return subprocess.run(["sh", "-c", f'. "{SCRIPT}"; schedule_api_plist'], cwd=root, env=clean,
                              capture_output=True, text=True)


class ScheduleAPIConfigTests(unittest.TestCase):
    def test_no_key_builds_an_unconfigured_app(self):
        result = run()
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    def test_key_from_the_local_file_goes_into_the_plist(self):
        result = run(file_text=f"# comment\nKEY = {GOOD}\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"<key>BYEScheduleAPIKey</key><string>{GOOD}</string>", result.stdout)
        self.assertIn("<string>https://nahvhampsxtasfwvvfei.supabase.co/functions/v1/bye-schedule-api</string>", result.stdout)

    def test_environment_wins_over_the_file(self):
        other = GOOD.replace("Fictional", "Environmen")
        result = run(env={"BYE_SCHEDULE_API_KEY": other, "BYE_SCHEDULE_API_URL": "http://127.0.0.1:8787/fixture"},
                     file_text=f"KEY={GOOD}\nURL=https://example.test/api\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(other, result.stdout)
        self.assertIn("http://127.0.0.1:8787/fixture", result.stdout)

    def test_dangerous_or_wrong_keys_are_refused_without_printing_them(self):
        for key in ("sb_secret_FictionalSecretValue123456", "sb_publishable_FictionalPublic123456",
                    "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.sig", "bye_job_FictionalToken123456789",
                    "bye_pk_short", "bye_pk_Has spaces and <tags> 1234567", "bye_pk_paste_the_key_from_the_dashboard"):
            with self.subTest(key=key[:12]):
                result = run(env={"BYE_SCHEDULE_API_KEY": key})
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")
                self.assertNotIn(key, result.stderr)

    def test_url_must_be_https_or_loopback(self):
        for url in ("http://example.test/api", "ftp://example.test", "https://user@example.test/api", "https://example.test/a b"):
            with self.subTest(url=url):
                self.assertNotEqual(run(env={"BYE_SCHEDULE_API_KEY": GOOD, "BYE_SCHEDULE_API_URL": url}).returncode, 0)
        self.assertEqual(run(env={"BYE_SCHEDULE_API_KEY": GOOD, "BYE_SCHEDULE_API_URL": "http://localhost:8787"}).returncode, 0)

    def test_file_is_read_not_executed(self):
        with tempfile.TemporaryDirectory() as marker:
            flag = Path(marker) / "ran"
            result = run(file_text=f"touch {flag}\nKEY={GOOD}\n")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(flag.exists())


if __name__ == "__main__":
    unittest.main()
