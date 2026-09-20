"""Run with: python3 -m unittest discover -s Tests/PackagingTests.

Exercise packaging failures in an isolated fixture, without compiling or signing.
"""
from pathlib import Path
import fcntl
import shutil
import subprocess
import tempfile
import unittest


class BuildAppTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "tools").mkdir()
        shutil.copyfile(Path(__file__).resolve().parents[2] / "tools/build-app.sh",
                        self.root / "tools/build-app.sh")
        resources = self.root / "Sources/MacZ/Resources"
        resources.mkdir(parents=True)
        (resources / "AppIcon.icns").write_text("fixture icon")
        (self.root / "LICENSE").write_text("fixture licence")
        binary = self.root / "binary"
        binary.mkdir()
        (binary / "MacZ").write_text("new executable")
        self.old = self.root / "dist/MacZ.app"
        self.old.mkdir(parents=True)
        (self.old / "old-bundle-marker").write_text("original")
        self.commands = self.root / "commands"
        self.commands.mkdir()
        self.env = {"PATH": f"{self.commands}:/usr/bin:/bin", "MOCK_BIN": str(binary)}
        self.command("swift", '[[ "$*" == *--show-bin-path* ]] && echo "$MOCK_BIN"\nexit 0')
        self.command("codesign", 'exit 0')

    def command(self, name, body):
        path = self.commands / name
        path.write_text("#!/bin/bash\n" + body + "\n")
        path.chmod(0o755)

    def build(self, *args):
        return subprocess.run(["/bin/bash", "tools/build-app.sh", *args], cwd=self.root,
                              env=self.env, capture_output=True, text=True)

    def assert_original_preserved(self):
        self.assertEqual((self.old / "old-bundle-marker").read_text(), "original")
        self.assertEqual(list((self.root / "dist").iterdir()), [self.old])

    def test_signing_failure_preserves_existing_app(self):
        self.command("codesign", "exit 1")
        self.assertNotEqual(self.build().returncode, 0)
        self.assert_original_preserved()

    def test_verification_failure_preserves_existing_app(self):
        self.command("codesign", '[[ "$1" != --verify ]]')
        self.assertNotEqual(self.build().returncode, 0)
        self.assert_original_preserved()

    def test_failed_final_rename_restores_existing_app(self):
        self.command("mv", '[[ "$1" == dist/.macz-build.*/MacZ.app ]] && exit 1\nexec /bin/mv "$@"')
        self.assertNotEqual(self.build().returncode, 0)
        self.assert_original_preserved()

    def test_success_replaces_bundle_without_stale_files(self):
        result = self.build("--universal")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.old / "old-bundle-marker").exists())
        self.assertEqual((self.old / "Contents/MacOS/MacZ").read_text(), "new executable")
        self.assertEqual(list((self.root / "dist").iterdir()), [self.old])

    def test_rejects_extra_arguments(self):
        self.assertNotEqual(self.build("--universal", "unexpected").returncode, 0)
        self.assert_original_preserved()

    def test_overlapping_build_is_rejected_before_touching_output(self):
        (self.root / ".build").mkdir()
        with (self.root / ".build/macz-build.lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            result = self.build()
            self.assertNotEqual(result.returncode, 0)
            self.assert_original_preserved()

    def test_build_lock_is_released_after_failure(self):
        self.command("codesign", "exit 1")
        self.assertNotEqual(self.build().returncode, 0)
        self.command("codesign", "exit 0")
        result = self.build()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_lock_remains_held_during_signing_and_verification(self):
        self.command("codesign", """exec /usr/bin/python3 - <<'PY'
import fcntl
import sys
with open('.build/macz-build.lock', 'w') as lock:
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        sys.exit(0)
sys.exit(1)
PY""")
        result = self.build()
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
