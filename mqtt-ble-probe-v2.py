#!/usr/bin/env python3
"""
Resilient MQTT 3.1.1 BLE probe for Xiaomi openmiio.

Features:
- subscribes to all topics by default (#)
- automatically reconnects if Mosquitto closes the connection
- finds _async.ble_event recursively in JSON payloads
- prints topic + raw payload for malformed/unknown BLE-shaped messages
- decodes known Xiaomi TH Clock / miaomiaoce.sensor_ht.o2 EIDs:
    19457 temperature: little-endian float32
    19458 humidity: uint8
    18435 battery: uint8
"""

from __future__ import annotations

import argparse
import json
import os
import socket
import struct
import time


def enc_varint(n: int) -> bytes:
    out = bytearray()
    while True:
        b = n % 128
        n //= 128
        if n:
            b |= 0x80
        out.append(b)
        if not n:
            return bytes(out)


def enc_str(s: str) -> bytes:
    b = s.encode("utf-8")
    return struct.pack("!H", len(b)) + b


def read_exact(s: socket.socket, n: int) -> bytes:
    buf = bytearray()
    while len(buf) < n:
        chunk = s.recv(n - len(buf))
        if not chunk:
            raise ConnectionError("MQTT connection closed")
        buf.extend(chunk)
    return bytes(buf)


def read_packet(s: socket.socket):
    first = read_exact(s, 1)[0]
    multiplier = 1
    remaining = 0
    while True:
        b = read_exact(s, 1)[0]
        remaining += (b & 0x7F) * multiplier
        if not (b & 0x80):
            break
        multiplier *= 128
        if multiplier > 128**3:
            raise ValueError("Malformed MQTT remaining length")
    return first, read_exact(s, remaining)


def mqtt_connect(host: str, port: int, topic: str):
    cid = f"st-ble-probe-{os.getpid()}-{int(time.time())}"
    s = socket.create_connection((host, port), timeout=5)
    s.settimeout(5)

    # CONNECT MQTT 3.1.1, clean session, keepalive 30 sec
    vh = enc_str("MQTT") + bytes([4, 2]) + struct.pack("!H", 30)
    payload = enc_str(cid)
    s.sendall(bytes([0x10]) + enc_varint(len(vh) + len(payload)) + vh + payload)

    ptype, body = read_packet(s)
    if (ptype >> 4) != 2 or len(body) < 2 or body[1] != 0:
        raise RuntimeError(f"CONNACK failed: type={ptype:#x} body={body!r}")

    # SUBSCRIBE QoS0
    sub_body = struct.pack("!H", 1) + enc_str(topic) + b"\x00"
    s.sendall(bytes([0x82]) + enc_varint(len(sub_body)) + sub_body)
    ptype, body = read_packet(s)
    if (ptype >> 4) != 9:
        raise RuntimeError(f"SUBACK not received: type={ptype:#x} body={body!r}")

    return s


def parse_publish(first: int, body: bytes):
    if len(body) < 2:
        raise ValueError("Short PUBLISH packet")
    tlen = struct.unpack("!H", body[:2])[0]
    if len(body) < 2 + tlen:
        raise ValueError("Short MQTT topic")
    topic = body[2:2+tlen].decode("utf-8", "replace")
    pos = 2 + tlen
    qos = (first >> 1) & 0x03
    if qos:
        pos += 2
    return topic, body[pos:]


def find_ble_events(obj):
    """Yield dicts that look like Xiaomi _async.ble_event params."""
    found = []

    def walk(x):
        if isinstance(x, dict):
            method = x.get("method")
            params = x.get("params")
            if method == "_async.ble_event" and isinstance(params, dict):
                found.append(params)

            # Some wrappers carry the method elsewhere but params itself
            # already has dev/evt/frmCnt.
            if (
                isinstance(params, dict)
                and isinstance(params.get("dev"), dict)
                and isinstance(params.get("evt"), list)
                and "frmCnt" in params
            ):
                if params not in found:
                    found.append(params)

            for v in x.values():
                walk(v)
        elif isinstance(x, list):
            for v in x:
                walk(v)

    walk(obj)
    return found


def decode_edata(eid, edata):
    try:
        raw = bytes.fromhex(edata)
    except Exception:
        return None

    try:
        if eid == 19457 and len(raw) >= 4:
            return ("temperature", round(struct.unpack("<f", raw[:4])[0], 1), "°C")
        if eid == 19458 and len(raw) >= 1:
            return ("humidity", round(float(raw[0]), 1), "%")
        if eid == 18435 and len(raw) >= 1:
            return ("battery", int(raw[0]), "%")
    except Exception:
        return None
    return None


def print_event(topic: str, params: dict):
    dev = params.get("dev") or {}
    print("\n--- BLE EVENT ---")
    print("topic :", topic)
    print("did   :", dev.get("did"))
    print("mac   :", dev.get("mac"))
    print("pdid  :", dev.get("pdid"))
    print("frmCnt:", params.get("frmCnt"))
    print("gwts  :", params.get("gwts"))

    for item in params.get("evt") or []:
        eid = item.get("eid")
        edata = item.get("edata")
        decoded = decode_edata(eid, edata)
        if decoded:
            name, value, unit = decoded
            print(f"evt   : eid={eid} edata={edata} -> {name}={value}{unit}")
        else:
            print(f"evt   : eid={eid} edata={edata}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="192.168.10.41")
    ap.add_argument("--port", type=int, default=1883)
    ap.add_argument("--topic", default="#")
    ap.add_argument("--reconnect", type=float, default=3.0)
    args = ap.parse_args()

    print(f"Target: mqtt://{args.host}:{args.port}/{args.topic}")
    print("Ctrl+C to stop.")

    while True:
        s = None
        try:
            s = mqtt_connect(args.host, args.port, args.topic)
            print("Subscribed; waiting for BLE events...")

            last_outbound = time.monotonic()
            ping_sent_at = None

            while True:
                now = time.monotonic()

                if ping_sent_at is not None and now - ping_sent_at >= 10:
                    raise TimeoutError("PINGRESP timeout")

                if ping_sent_at is None and now - last_outbound >= 15:
                    s.sendall(b"\xC0\x00")  # PINGREQ
                    last_outbound = now
                    ping_sent_at = now

                try:
                    first, body = read_packet(s)
                except socket.timeout:
                    continue

                ptype = first >> 4
                if ptype == 13:  # PINGRESP
                    ping_sent_at = None
                    continue
                if ptype != 3:   # PUBLISH
                    continue

                topic, payload = parse_publish(first, body)
                text = payload.decode("utf-8", "replace")

                if "_async.ble_event" not in text and '"dev"' not in text:
                    continue

                try:
                    obj = json.loads(text)
                    events = find_ble_events(obj)
                except Exception:
                    events = []

                if events:
                    for params in events:
                        print_event(topic, params)
                elif "_async.ble_event" in text:
                    print("\n--- BLE-SHAPED MESSAGE (unparsed) ---")
                    print("topic:", topic)
                    print(text[:2000])

        except KeyboardInterrupt:
            print("\nStopped.")
            return
        except Exception as e:
            print(f"\nMQTT disconnected/error: {e}")
            print(f"Reconnecting in {args.reconnect:g}s...")
            time.sleep(args.reconnect)
        finally:
            if s:
                try:
                    s.close()
                except Exception:
                    pass


if __name__ == "__main__":
    main()
