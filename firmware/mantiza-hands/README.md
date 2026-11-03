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

1. The first time (no bonds), pairing is open. Later, hold **A and B together** for 3 s to open it for 2 minutes.
2. On the iPhone: Settings > Accessibility > Touch > AssistiveTouch > Devices > Bluetooth Devices > **Mantiza Hands XXXX**.
3. Keep Portrait Orientation Lock on (the absolute pointer maps onto the portrait screen).

## Session auth

Only the paired Mantiza app may drive the stick over Bluetooth (every app on the phone shares the same BLE connection).

1. The app makes a random secret and sends `secret HEX64`. The stick shows **Pair code NNNN**; press **A** within 60 s if the
   app shows the same code. The secret is kept in flash. A new secret is only accepted when none exists or pairing is open
   (hold A and B for 3 s), so another app cannot replace it.
2. On each connection: `hello` returns a nonce, the app answers `auth HMAC_HEX`.
3. After that every BLE line ends with ` ~TAG`: the first 8 bytes of HMAC-SHA256(secret, session nonce + line), hex. Ids must
   go up. Lines without a valid tag get `err auth`. `ping`, `version`, `status`, `hello`, `auth` and `secret` need no tag.

USB serial is not checked, so the Mac harness keeps working. `unpair` also erases the secret. `status` shows `"auth"`.

## Buttons

| Screen | A | B |
|---|---|---|
| Idle | click: event `a` (run next suggestion); hold: talk | click: event `b` (also cancels a heard request); hold 1 s: stop |
| Working | hold: talk (answer a question) | click or hold: emergency stop |
| Approve? (`ask`, `prompt`) | Yes | No |
| Pair code | Confirm | Cancel |

Shaking the stick while it is working or asking is also an emergency stop. Holding **A and B together** for 3 s
opens pairing.

## Talking to the stick

Hold A, speak, let go. The stick records 16 kHz speech with its microphone, encodes it as IMA ADPCM (4:1) and
streams it to the app on the `audio` characteristic (`...0604`, notify), encrypted with AES-128-CTR under a key
derived from the session (see `audio.h`); nothing is sent before the app has authenticated. The app transcribes it
on the phone. Events: `talk_start UTT`, `talk_end UTT PACKETS`, `talk_short UTT`; `audio UTT SEQ` sends a lost packet
again. `tools/hands_cli.py talk out.wav` records over USB to a WAV for testing.

## Protocol

One line per command, `<id> <command>`, answered `<id> ok [result]` or `<id> err <why>`, over the BLE command service (`f5da0600-6c5e-4c62-bbd9-ba1b370af73d`: cmd `...0601` write, reply `...0602` notify, status `...0603` read/notify JSON every second) or USB serial at 115200. Device events arrive as `evt a|b|stop|pairing|yes|no|timeout`; `prompt SECONDS TEXT` shows an approval without blocking (the answer comes as `evt yes|no|timeout`, and `unprompt` withdraws it when the phone answered first). The full command list is at the top of `mantiza-hands.ino`.

Pointer positions are absolute, 0..32767 across the whole screen in each axis.

## Tests

```sh
cc -I firmware/mantiza-hands firmware/mantiza-hands/tests/test_report.c firmware/mantiza-hands/src/hid/report.c -o /tmp/test_report && /tmp/test_report
python3 tools/hands_cli.py status|grid|type TEXT|stress N|events   # pip install -r tools/requirements.txt
```
