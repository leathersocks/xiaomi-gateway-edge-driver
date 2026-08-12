from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[1]


class RepositoryTests(unittest.TestCase):
    def test_json_and_yaml_files_parse(self):
        for path in ROOT.rglob("*.json"):
            json.loads(path.read_text(encoding="utf-8"))
        for path in list(ROOT.rglob("*.yml")) + list(ROOT.rglob("*.yaml")):
            yaml.safe_load(path.read_text(encoding="utf-8"))

    def test_profile_references_exist(self):
        profile_names = {
            yaml.safe_load(path.read_text(encoding="utf-8"))["name"]
            for path in (ROOT / "profiles").glob("*.yml")
        }
        for source in (ROOT / "src").glob("*.lua"):
            text = source.read_text(encoding="utf-8")
            for profile in re.findall(r'profile\s*=\s*"([^"]+)"', text):
                self.assertIn(
                    profile,
                    profile_names,
                    f"missing profile {profile} referenced by {source.name}",
                )

    def test_runtime_ownership_and_exact_topics(self):
        mqtt = (ROOT / "src" / "mqtt_ble.lua").read_text(encoding="utf-8")
        self.assertIn('"miio/report"', mqtt)
        self.assertIn('"central/report"', mqtt)
        self.assertNotIn('local DEFAULT_TOPIC = "#"', mqtt)
        self.assertIn("MAX_PACKET_BYTES", mqtt)
        tools = ROOT / "xiaomi-gateway-edge-tools"
        self.assertFalse(tools.exists() and any(tools.rglob("*")))
        self.assertTrue((ROOT / "OPENMIIO-RUNTIME.md").is_file())
        self.assertTrue((ROOT / "OPENMIIO-RUNTIME.en.md").is_file())

    def test_version_and_changelog_match(self):
        version, date = (ROOT / "VERSION.txt").read_text(encoding="utf-8").splitlines()
        for changelog in ("CHANGELOG.md", "CHANGELOG.en.md"):
            text = (ROOT / changelog).read_text(encoding="utf-8")
            self.assertIn(f"## {version} — {date}", text)

    def test_checksum_manifest_entries_are_current(self):
        for line in (ROOT / "SHA256SUMS.txt").read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            expected, relative = line.split(maxsplit=1)
            path = ROOT / relative
            self.assertTrue(path.is_file(), f"checksum path missing: {relative}")
            actual = hashlib.sha256(path.read_bytes()).hexdigest()
            self.assertEqual(actual, expected, relative)


if __name__ == "__main__":
    unittest.main()
