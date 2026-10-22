import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("admin_artifact", Path(__file__).with_name("admin-artifact.py"))
artifact = importlib.util.module_from_spec(spec)
spec.loader.exec_module(artifact)


class AdminArtifactTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()

    def archive(self, extra=None, manifest_update=None):
        files = {"index.html": b"shell", "assets/app.js": b"javascript"}
        digest = hashlib.sha256()
        for name in sorted(files):
            digest.update(name.encode() + b"\0" + files[name] + b"\0")
        manifest = {"format": "sparq.admin.artifact.v1", "version": "0.2.0", "files": sorted(files), "fingerprint": digest.hexdigest()}
        manifest.update(manifest_update or {})
        files[artifact.MANIFEST] = json.dumps(manifest).encode()
        files.update(extra or {})
        path = self.root / "admin.tar.gz"
        with tarfile.open(path, "w:gz") as writer:
            for name, body in files.items():
                header = tarfile.TarInfo(name)
                header.size = len(body)
                writer.addfile(header, io.BytesIO(body))
        return path, hashlib.sha256(path.read_bytes()).hexdigest()

    def test_install_verified_admin_without_app_version_coupling(self):
        path, sha = self.archive()
        files, manifest = artifact.read_artifact(path, sha, "0.2.0")
        artifact.install(files, self.root / "staging/public/admin")
        self.assertEqual(manifest["version"], "0.2.0")
        self.assertEqual((self.root / "staging/public/admin/index.html").read_text(), "shell")

    def test_corruption_and_wrong_version_are_rejected(self):
        path, sha = self.archive()
        with self.assertRaisesRegex(ValueError, "SHA256 不匹配"):
            artifact.read_artifact(path, "0" * 64, "0.2.0")
        with self.assertRaisesRegex(ValueError, "版本"):
            artifact.read_artifact(path, sha, "0.3.0")
        path, sha = self.archive(manifest_update={"fingerprint": "bad"})
        with self.assertRaisesRegex(ValueError, "指纹"):
            artifact.read_artifact(path, sha, "0.2.0")

    def test_traversal_and_runtime_assets_are_rejected_before_writing(self):
        for name in ["../escape", "/escape", "__app__/app.js", "plugin-assets/plugin.js"]:
            with self.subTest(name=name):
                path, sha = self.archive({name: b"invalid"})
                with self.assertRaises(ValueError):
                    artifact.read_artifact(path, sha, "0.2.0")
        self.assertFalse((self.root / "escape").exists())

    def test_existing_application_resources_are_preserved(self):
        destination = self.root / "public/admin"
        (destination / "__app__").mkdir(parents=True)
        sentinel = destination / "__app__/app.js"
        sentinel.write_text("user application")
        path, sha = self.archive()
        files, _ = artifact.read_artifact(path, sha, "0.2.0")
        with self.assertRaisesRegex(ValueError, "拒绝覆盖"):
            artifact.install(files, destination)
        self.assertEqual(sentinel.read_text(), "user application")


if __name__ == "__main__":
    unittest.main()
