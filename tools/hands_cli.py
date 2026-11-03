#!/usr/bin/env python3
"""Mac test harness for Mantiza Hands over USB serial (same "<id> <command>" protocol as the app uses over BLE).

    python3 tools/hands_cli.py status
    python3 tools/hands_cli.py send "at 16383 16383" "tap 16383 16383"
    python3 tools/hands_cli.py grid        # pointer visits 9 points (no clicks), check each on the phone
    python3 tools/hands_cli.py type "Hello, World! 123"
    python3 tools/hands_cli.py stress 200  # 200 pointer moves, then report HID drops
    python3 tools/hands_cli.py events      # print button / shake events until Ctrl-C
    python3 tools/hands_cli.py talk out.wav  # hold A on the stick, speak, let go: saves the recording

USB only on purpose: if the Mac bonded with the board over Bluetooth, macOS could adopt it as its own keyboard/mouse.
Requires pyserial (pip install -r tools/requirements.txt).
"""
import argparse
import glob
import itertools
import json
import sys
import time
import wave

import serial

import adpcm

ABS_MAX = 32767
GRID = (0.12, 0.5, 0.88)


class Hands:
    def __init__(self, port=None):
        port = port or next(iter(sorted(glob.glob("/dev/cu.usbmodem*"))), None)
        if not port:
            sys.exit("no board on USB (/dev/cu.usbmodem*)")
        self.serial = serial.Serial(port, 115200, timeout=0.1)
        self.ids = itertools.count(1)
        time.sleep(0.2)
        self.serial.reset_input_buffer()

    def call(self, command, timeout=5.0):
        """Send one command and return its reply text ("ok ..." / "err ..."); events are printed as they pass."""
        request = next(self.ids)
        self.serial.write(f"{request} {command}\n".encode())
        deadline = time.time() + timeout
        buffer = b""
        while time.time() < deadline:
            buffer += self.serial.read(256)
            while b"\n" in buffer:
                raw, buffer = buffer.split(b"\n", 1)
                line = raw.decode(errors="replace").strip()
                if line.startswith(f"{request} "):
                    return line[len(str(request)) + 1:]
                if line.startswith("evt "):
                    print(f"  ({line})")
        return "err no reply"

    def status(self):
        reply = self.call("status")
        return json.loads(reply[3:]) if reply.startswith("ok ") else {"error": reply}


def units(fraction):
    return round(fraction * ABS_MAX)


def cmd_grid(hands, args):
    for y, x in itertools.product(GRID, GRID):
        reply = hands.call(f"at {units(x)} {units(y)}")
        print(f"pointer at x={x:.2f} y={y:.2f} of the screen -> {reply}")
        time.sleep(args.pause)


def cmd_stress(hands, args):
    before = hands.status().get("ble", {}).get("hdrop", 0)
    started = time.time()
    failed = 0
    for i in range(args.count):
        x = units(0.3 + 0.4 * (i % 2))
        failed += not hands.call(f"at {x} {units(0.5)}").startswith("ok")
    elapsed = time.time() - started
    after = hands.status().get("ble", {}).get("hdrop", 0)
    print(f"{args.count} moves in {elapsed:.1f} s ({1000 * elapsed / args.count:.0f} ms each), "
          f"{failed} failed replies, {after - before} HID drops")


def cmd_events(hands, args):
    print("waiting for events (press A/B or shake the stick); Ctrl-C to stop")
    try:
        while True:
            line = hands.serial.readline().decode(errors="replace").strip()
            if line.startswith("evt "):
                print(line)
    except KeyboardInterrupt:
        pass


def cmd_talk(hands, args):
    print("hold A on the stick, speak, then let go")
    deadline = time.time() + 60
    while time.time() < deadline:
        line = hands.serial.readline().decode(errors="replace").strip()
        if line.startswith("evt talk_start"):
            print("recording...")
        elif line.startswith("evt talk_short"):
            sys.exit("too short; hold A while you speak")
        elif line.startswith("evt talk_end"):
            _, _, utt, count = line.split()
            break
    else:
        sys.exit("no recording within 60 s")
    samples = []
    for seq in range(int(count)):
        reply = hands.call(f"audio {utt} {seq}")
        if not reply.startswith("ok "):
            sys.exit(f"packet {seq}: {reply}")
        got, pcm = adpcm.decode_packet(bytes.fromhex(reply[3:]))
        assert got == seq, (got, seq)
        samples += pcm
    with wave.open(args.out, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(16000)
        w.writeframes(b"".join(int(s).to_bytes(2, "little", signed=True) for s in samples))
    print(f"{args.out}: {len(samples) / 16000:.1f} s from {count} packets")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--port")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("status")
    send = sub.add_parser("send")
    send.add_argument("lines", nargs="+")
    grid = sub.add_parser("grid")
    grid.add_argument("--pause", type=float, default=2.0)
    typing = sub.add_parser("type")
    typing.add_argument("text")
    stress = sub.add_parser("stress")
    stress.add_argument("count", type=int, nargs="?", default=200)
    sub.add_parser("events")
    talk = sub.add_parser("talk")
    talk.add_argument("out", nargs="?", default="talk.wav")
    args = parser.parse_args()

    hands = Hands(args.port)
    if args.command == "status":
        print(json.dumps(hands.status(), indent=2))
    elif args.command == "send":
        for line in args.lines:
            print(f"{line!r} -> {hands.call(line, timeout=130)}")
    elif args.command == "type":
        print(hands.call(f"type {args.text}", timeout=30))
    else:
        {"grid": cmd_grid, "stress": cmd_stress, "events": cmd_events, "talk": cmd_talk}[args.command](hands, args)


if __name__ == "__main__":
    main()
