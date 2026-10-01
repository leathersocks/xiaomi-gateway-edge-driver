from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[1]


def repository_bytes(path: Path) -> bytes:
    """Return the canonical bytes Git stores for normalized text files."""
    return path.read_bytes().replace(b"\r\n", b"\n")


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

    def test_gateway_capability_exposes_connected_devices(self):
        definition = json.loads(
            (ROOT / "capabilities" / "xiaomiGatewayDevices.json").read_text(
                encoding="utf-8"
            )
        )
        attributes = definition["attributes"]
        self.assertIn("connectedDeviceCount", attributes)
        self.assertIn("connectedDevices", attributes)

        presentation = json.loads(
            (
                ROOT
                / "capabilities"
                / "xiaomiGatewayDevices-presentation.template.json"
            ).read_text(encoding="utf-8")
        )
        # Keep inventory attributes/events available without a duplicate text card.
        self.assertEqual(presentation["detailView"], [])
        self.assertEqual(presentation["dashboard"]["states"], [])

        for tag in ("en", "ko", "ko-KR"):
            translation = json.loads(
                (
                    ROOT
                    / "translations"
                    / f"xiaomiGatewayDevices-{tag}.json"
                ).read_text(encoding="utf-8")
            )
            translated = translation["attributes"]
            self.assertIn("connectedDeviceCount", translated)
            self.assertIn("connectedDevices", translated)

        status = json.loads(
            (ROOT / "capabilities" / "xiaomiGatewayStatus.json").read_text(
                encoding="utf-8"
            )
        )
        self.assertEqual(set(status["attributes"]), {"gatewayStatus"})
        profile = yaml.safe_load(
            (ROOT / "profiles" / "xiaomi-gateway.yml").read_text(encoding="utf-8")
        )
        profile_caps = {c["id"] for c in profile["components"][0]["capabilities"]}
        self.assertIn("locketforest19027." + definition["id"], profile_caps)
        self.assertEqual(definition["id"], "connectedDevices")

    def test_gateway_layout_has_one_status_and_view_selector(self):
        status = json.loads(
            (ROOT / "capabilities" / "xiaomiGatewayStatus-presentation.template.json")
            .read_text(encoding="utf-8")
        )
        self.assertEqual(status["detailView"], [])
        self.assertEqual(len(status["dashboard"]["states"]), 1)
        state = status["dashboard"]["states"][0]
        self.assertEqual(state["label"], "{{gatewayStatus.value}}")
        self.assertEqual(
            [item["key"] for item in state["alternatives"]],
            ["online", "degraded", "offline"],
        )
        view = json.loads(
            (ROOT / "capabilities" / "gatewayView-presentation.template.json")
            .read_text(encoding="utf-8")
        )
        self.assertEqual(len(view["detailView"]), 1)
        self.assertEqual(view["detailView"][0]["displayType"], "list")
        self.assertEqual(view["detailView"][0]["list"]["command"]["name"], "setView")
        for profile_name in ("xiaomi-gateway", "xiaomi-gateway-setup"):
            profile = yaml.safe_load(
                (ROOT / "profiles" / f"{profile_name}.yml").read_text(encoding="utf-8")
            )
            view_cap = next(
                cap for cap in profile["components"][0]["capabilities"]
                if cap["id"] == "locketforest19027.gatewayView"
            )
            self.assertEqual(view_cap["config"]["values"], [
                {"key": "view.value", "enabledValues": ["bridge", "settings"]},
                {"key": "setView", "enabledValues": ["bridge", "settings"]},
            ])

    def test_native_bridge_view_preserves_setup_and_child_identity(self):
        profiles = ROOT / "profiles"
        bridge = yaml.safe_load(
            (profiles / "xiaomi-gateway.yml").read_text(encoding="utf-8")
        )
        setup = yaml.safe_load(
            (profiles / "xiaomi-gateway-setup.yml").read_text(encoding="utf-8")
        )
        self.assertEqual(bridge["components"][0]["categories"], [{"name": "Bridges"}])
        self.assertEqual(setup["components"][0]["categories"], [{"name": "Hub"}])
        self.assertEqual(bridge["preferences"], setup["preferences"])
        self.assertEqual(
            bridge["components"][0]["capabilities"],
            setup["components"][0]["capabilities"],
        )
        discovery = (ROOT / "src" / "discovery.lua").read_text(encoding="utf-8")
        self.assertIn('profile = "xiaomi-gateway-setup"', discovery)
        manager = (ROOT / "src" / "child_manager.lua").read_text(encoding="utf-8")
        self.assertIn('type = "EDGE_CHILD"', manager)
        self.assertIn("parent_device_id = parent.id", manager)

        for view in ("settings", "bridge"):
            payload = json.loads(
                (ROOT / "ui" / f"gateway-{view}-view.json").read_text(encoding="utf-8")
            )
            self.assertEqual(payload, {
                "component": "main", "capability": "locketforest19027.gatewayView",
                "command": "setView", "arguments": [view],
            })

        definition = json.loads(
            (ROOT / "capabilities" / "gatewayView.json").read_text(encoding="utf-8")
        )
        self.assertEqual(
            definition["commands"]["setView"]["arguments"][0]["schema"]["enum"],
            ["bridge", "settings"],
        )
        for tag in ("en", "ko", "ko-KR"):
            translation = json.loads(
                (ROOT / "translations" / f"gatewayView-{tag}.json").read_text(
                    encoding="utf-8"
                )
            )
            self.assertEqual(
                set(translation["attributes"]["view"]["i18n"]["value"]),
                {"bridge", "settings"},
            )

    def test_checksum_manifest_entries_are_current(self):
        for line in (ROOT / "SHA256SUMS.txt").read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            expected, relative = line.split(maxsplit=1)
            path = ROOT / relative
            self.assertTrue(path.is_file(), f"checksum path missing: {relative}")
            actual = hashlib.sha256(repository_bytes(path)).hexdigest()
            self.assertEqual(actual, expected, relative)


if __name__ == "__main__":
    unittest.main()
