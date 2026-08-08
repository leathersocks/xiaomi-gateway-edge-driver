#!/usr/bin/env python3
"""
Install openmiio_agent MIPS on Xiaomi Multimode Gateway (mgl03) over an
already-open Telnet port, then start only the MQTT + central modules.

No Xiaomi token/key is required by this script.
It does not embed or print any account secrets.

Target validated for this workflow:
  model: lumi.gateway.mgl03
  firmware family: 1.5.0.x
  Telnet login: admin (blank password or admin fallback)
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import os
import re
import socket
import sys
import time
import urllib.request

OPENMIIO_URL = (
    "https://github.com/AlexxIT/openmiio_agent/releases/download/"
    "v1.2.1/openmiio_agent_mips"
)
OPENMIIO_MD5 = "6c3f4dca62647b9d19a81e1ccaa5ccc0"
REMOTE_BIN = "/data/openmiio_agent"
REMOTE_TMP = "/data/openmiio_agent.st-upload"
REMOTE_LOG = "/var/log/st-openmiio.log"
# Keep Base64 command comfortably below BusyBox/Telnet input-line limits.
CHUNK_BYTES = 384


class TelnetSession:
    IAC = 255
    DONT = 254
    DO = 253
    WONT = 252
    WILL = 251
    SB = 250
    SE = 240

    def __init__(self, host: str, port: int = 23, timeout: float = 5.0):
        self.host = host
        self.port = port
        self.timeout = timeout
        self.sock: socket.socket | None = None

    def connect(self):
        self.sock = socket.create_connection((self.host, self.port), timeout=self.timeout)
        self.sock.settimeout(0.25)

    def close(self):
        if self.sock:
            try:
                self.sock.close()
            finally:
                self.sock = None

    def _send(self, data: bytes):
        assert self.sock is not None
        self.sock.sendall(data)

    def sendline(self, line: str):
        self._send(line.encode("utf-8") + b"\r\n")

    def _filter_telnet(self, data: bytes) -> bytes:
        """Strip basic Telnet negotiations and refuse options."""
        assert self.sock is not None
        out = bytearray()
        i = 0
        n = len(data)
        while i < n:
            b = data[i]
            if b != self.IAC:
                out.append(b)
                i += 1
                continue

            if i + 1 >= n:
                break
            cmd = data[i + 1]

            if cmd == self.IAC:
                out.append(self.IAC)
                i += 2
                continue

            if cmd in (self.DO, self.DONT, self.WILL, self.WONT):
                if i + 2 >= n:
                    break
                opt = data[i + 2]
                if cmd in (self.DO, self.DONT):
                    self._send(bytes([self.IAC, self.WONT, opt]))
                else:
                    self._send(bytes([self.IAC, self.DONT, opt]))
                i += 3
                continue

            if cmd == self.SB:
                end = data.find(bytes([self.IAC, self.SE]), i + 2)
                if end < 0:
                    break
                i = end + 2
                continue

            i += 2
        return bytes(out)

    def read_available(self, seconds: float = 0.8) -> str:
        assert self.sock is not None
        end = time.time() + seconds
        buf = bytearray()
        while time.time() < end:
            try:
                chunk = self.sock.recv(8192)
                if not chunk:
                    break
                buf.extend(self._filter_telnet(chunk))
                end = max(end, time.time() + 0.15)
            except socket.timeout:
                time.sleep(0.03)
        return buf.decode("utf-8", "replace")

    def read_until_any(self, needles: tuple[str, ...], timeout: float = 5.0) -> str:
        assert self.sock is not None
        end = time.time() + timeout
        text = ""
        lower_needles = tuple(x.lower() for x in needles)
        while time.time() < end:
            text += self.read_available(0.25)
            low = text.lower()
            if any(n in low for n in lower_needles):
                return text
        return text

    def login_mgl03(self):
        banner = self.read_until_any(("login:", "# ", "Password:"), timeout=3.0)
        if "# " in banner:
            return

        # Most mgl03 gateways use admin with blank password.
        self.sendline("admin")
        resp = self.read_until_any(("Password:", "# "), timeout=3.0)

        if "# " in resp:
            return

        if "password:" in resp.lower():
            self.sendline("")
            resp2 = self.read_until_any(("Password:", "# "), timeout=2.0)
            if "# " in resp2:
                return

            # Some stock images accept admin/admin.
            self.sendline("admin")
            resp3 = self.read_until_any(("# ", "login:", "incorrect"), timeout=3.0)
            if "# " in resp3:
                return

        raise RuntimeError(
            "Telnet login failed. Expected mgl03 admin shell prompt '# '. "
            "Do not continue with the ARM/mgl001 installer."
        )

    def command(self, command: str, timeout: float = 8.0) -> tuple[str, int]:
        marker = "__D%06d__" % (int(time.time() * 1000) % 1000000)
        wrapped = f"{command}; rc=$?; printf '\\n{marker}:%s\\n' \"$rc\""
        self.sendline(wrapped)
        text = self.read_until_any((marker + ":",), timeout=timeout)
        m = re.search(re.escape(marker) + r":(-?\d+)", text)
        if not m:
            raise RuntimeError(f"Command timeout or missing marker: {command}\n{text[-1000:]}")
        rc = int(m.group(1))
        # Remove echoed command/marker noise for concise display.
        cleaned = text.replace("\r", "")
        return cleaned, rc


def md5_bytes(data: bytes) -> str:
    return hashlib.md5(data).hexdigest()


def download_binary() -> bytes:
    print("Downloading openmiio_agent MIPS v1.2.1...")
    req = urllib.request.Request(
        OPENMIIO_URL,
        headers={"User-Agent": "SmartThings-openmiio-mgl03-installer/1.2"},
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        data = r.read()
    got = md5_bytes(data)
    if got.lower() != OPENMIIO_MD5:
        raise RuntimeError(f"Local MD5 mismatch: got {got}, expected {OPENMIIO_MD5}")
    print(f"Downloaded {len(data):,} bytes; MD5 OK ({got}).")
    return data


def test_port(host: str, port: int, timeout: float = 2.0) -> bool:
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--gateway-ip", default="192.168.10.41")
    ap.add_argument("--telnet-port", type=int, default=23)
    ap.add_argument("--mqtt-port", type=int, default=1883)
    ap.add_argument(
        "--force-restart",
        action="store_true",
        help="Restart an existing openmiio_agent. Default is to refuse touching it.",
    )
    args = ap.parse_args()

    if not test_port(args.gateway_ip, args.telnet_port):
        raise RuntimeError(
            f"Telnet {args.gateway_ip}:{args.telnet_port} is not open. "
            "Run the mgl03 set_ip_info Telnet-enable step first."
        )

    data = download_binary()

    print(f"Connecting Telnet {args.gateway_ip}:{args.telnet_port}...")
    t = TelnetSession(args.gateway_ip, args.telnet_port)
    t.connect()
    try:
        t.login_mgl03()
        print("Telnet login OK (mgl03 admin shell).")

        # mgl03 Telnet echoes long input lines by default. Disable echo before
        # Base64 transfer so long upload commands do not flood/corrupt reads.
        try:
            t.command("stty -echo", timeout=4.0)
            print("Telnet echo disabled.")
        except Exception as e:
            print(f"Warning: could not disable Telnet echo: {e}")

        # Identify gateway before changing anything.
        ident, _ = t.command(
            "cat /etc/rootfs_fw_info 2>/dev/null; "
            "grep -E '^(model|did|mac|key)=' /data/miio/device.conf 2>/dev/null | "
            "sed 's/^key=.*/key=[hidden]/'"
        )
        print("Gateway info (secrets hidden):")
        for line in ident.splitlines():
            if line.strip() and not re.search(r"__D\d{6}__:", line) and "printf " not in line:
                print("  " + line)

        running, _ = t.command("ps w | grep '[o]penmiio_agent' || true")
        process_lines = [
            ln.strip() for ln in running.splitlines()
            if "openmiio_agent" in ln and not re.search(r"__D\d{6}__:", ln)
        ]
        if process_lines and not args.force_restart:
            print("\nExisting openmiio_agent detected:")
            for ln in process_lines:
                print("  " + ln)
            print(
                "\nRefusing to replace/restart an existing agent. "
                "Re-run with --force-restart only if you intentionally want this installer "
                "to own the process."
            )
            return 3

        if process_lines:
            print("Stopping existing openmiio_agent (--force-restart)...")
            t.command("killall openmiio_agent 2>/dev/null || true; sleep 1")

        installed_md5, _ = t.command(
            f"[ -f {REMOTE_BIN} ] && md5sum {REMOTE_BIN} || true"
        )
        if OPENMIIO_MD5 in installed_md5.lower():
            print("Existing /data/openmiio_agent MD5 OK; skipping upload.")
            t.command(f"chmod 755 {REMOTE_BIN}")
        else:
            print(f"Uploading in {CHUNK_BYTES}-byte chunks...")
            t.command(f"rm -f {REMOTE_TMP}")
            total = (len(data) + CHUNK_BYTES - 1) // CHUNK_BYTES
            for idx in range(total):
                chunk = data[idx * CHUNK_BYTES:(idx + 1) * CHUNK_BYTES]
                b64 = base64.b64encode(chunk).decode("ascii")
                _, rc = t.command(
                    f"printf '%s' '{b64}' | base64 -d >> {REMOTE_TMP}",
                    timeout=10.0,
                )
                if rc != 0:
                    raise RuntimeError(f"Upload failed at chunk {idx + 1}/{total}")
                if (idx + 1) % 100 == 0 or idx + 1 == total:
                    print(f"  {idx + 1}/{total}")

            remote_md5, _ = t.command(f"md5sum {REMOTE_TMP}")
            if OPENMIIO_MD5 not in remote_md5.lower():
                raise RuntimeError(
                    "Remote MD5 mismatch after upload. "
                    f"Expected {OPENMIIO_MD5}; response: {remote_md5[-500:]}"
                )
            print("Remote MD5 OK.")

            _, rc = t.command(
                f"mv {REMOTE_TMP} {REMOTE_BIN} && chmod 755 {REMOTE_BIN}"
            )
            if rc != 0:
                raise RuntimeError("Failed to install/chmod openmiio_agent.")

        # BLE -> MQTT path matching XiaomiGateway3's BLE-relevant modules.
        # miio    : publishes miio/report (some BLE events arrive here)
        # mqtt    : starts/publishes via the gateway's Mosquitto on public :1883
        # cache   : patches/caches BLE service responses for local operation
        # central : proxies central socket and publishes central/report
        # z3 is intentionally omitted because this workflow is BLE-only
        start_cmd = (
            f"rm -f {REMOTE_LOG}; "
            f"( {REMOTE_BIN} miio mqtt cache central --log.level=trace "
            f"> {REMOTE_LOG} 2>&1 </dev/null & )"
        )
        print("Starting openmiio_agent: miio + mqtt + cache + central...")
        t.command(start_cmd)
        time.sleep(3)

        status, _ = t.command(
            "ps w | grep '[o]penmiio_agent' || true; "
            "netstat -ltnp 2>/dev/null | grep ':1883 ' || true; "
            f"tail -n 40 {REMOTE_LOG} 2>/dev/null || true",
            timeout=6.0,
        )
        print("\nRemote status:")
        for line in status.splitlines():
            if line.strip() and not re.search(r"__D\d{6}__:", line) and "printf " not in line:
                print("  " + line)

    finally:
        t.close()

    time.sleep(1)
    if test_port(args.gateway_ip, args.mqtt_port, timeout=3.0):
        print(f"\nSUCCESS: MQTT broker is reachable at {args.gateway_ip}:{args.mqtt_port}")
        print("Next: subscribe to topic # and wait for BLE advertisements.")
        return 0

    print(
        f"\nopenmiio upload/start completed, but {args.gateway_ip}:{args.mqtt_port} "
        "is not reachable yet. Check /var/log/st-openmiio.log via Telnet."
    )
    return 2


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print("\nCancelled.")
        raise SystemExit(130)
    except Exception as e:
        print(f"\nERROR: {e}", file=sys.stderr)
        raise SystemExit(1)
