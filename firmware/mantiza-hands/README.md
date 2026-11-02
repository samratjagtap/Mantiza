# Mantiza Hands firmware (M5StickS3)

The stick is the iPhone's Bluetooth LE pointer and keyboard. The Mantiza app decides what to do; the stick only executes input and shows status.

## Build and flash

Needs `arduino-cli`, the `esp32:esp32` core 3.3.x and the `M5Unified` and `NimBLE-Arduino` (2.5.x) libraries:

```sh
arduino-cli config add board_manager.additional_urls https://espressif.github.io/arduino-esp32/package_esp32_index.json
arduino-cli core install esp32:esp32
arduino-cli lib install M5Unified NimBLE-Arduino
firmware/mantiza-hands/build.sh               # build + flash the stick on USB
firmware/mantiza-hands/build.sh --build-only  # compile only
```

If flashing leaves the stick in download mode (screen dark), press the side power button once.
**Do not hold the side power button:** a long press enters download mode.

## Pairing

1. The first time (no bonds), pairing is open. Later, hold **A** for 3 s on the idle screen to open it for 2 minutes.
2. On the iPhone: Settings > Accessibility > Touch > AssistiveTouch > Devices > Bluetooth Devices > **Mantiza Hands XXXX**.
3. Keep Portrait Orientation Lock on (the absolute pointer maps onto the portrait screen).

## Buttons

| Screen | A | B |
|---|---|---|
| Idle | click: event `a` (run next suggestion); hold 3 s: open pairing | click: event `b`; hold 1 s: stop |
| Working | | click or hold: emergency stop |
| Approve? | Yes | No |

Shaking the stick while it is working or asking is also an emergency stop.

## Protocol

One line per command, `<id> <command>`, answered `<id> ok [result]` or `<id> err <why>`, over the BLE command service (`f5da0600-6c5e-4c62-bbd9-ba1b370af73d`: cmd `...0601` write, reply `...0602` notify, status `...0603` read/notify JSON every second) or USB serial at 115200. Device events arrive as `evt a|b|stop|pairing`. The full command list is at the top of `mantiza-hands.ino`.

Pointer positions are absolute, 0..32767 across the whole screen in each axis.

## Tests

```sh
cc -I firmware/mantiza-hands firmware/mantiza-hands/tests/test_report.c firmware/mantiza-hands/src/hid/report.c -o /tmp/test_report && /tmp/test_report
python3 tools/hands_cli.py status|grid|type TEXT|stress N|events   # pip install -r tools/requirements.txt
```
