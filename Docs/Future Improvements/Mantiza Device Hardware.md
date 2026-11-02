# Future Improvements: Mantiza Device (Hardware)

_Started: 2026-11-02 · Status: living list, add to it as the prototype teaches us more · Prototype: M5Stack **StickS3** (K150) · Datasheet: [StickS3.pdf](../StickS3.pdf) · Plan: [Mantiza v2 plan, section 7](../Mantiza%20Roadmap/mantiza-v2-plan.md)_

## Why this file exists
The **StickS3 is our prototype only**. Later we build **our own device on a custom ESP32 board**. While we build and test the prototype, we write down every limitation we hit here, so the custom board fixes it.

**Verdict on the StickS3 for the prototype:** good enough. It has everything the plan needs from the device: Bluetooth LE mouse + keyboard, a command channel, a status screen, two programmable buttons, a motion sensor, a speaker and a microphone (section 2 below).

## How to read this document
| Marker | Meaning |
|---|---|
| ✅ | Confirmed from the StickS3 PDF, M5Stack docs or Espressif docs |
| 📰 | Reported by one user, vendor or third-party site |
| ❓ | Unknown; to be measured on the prototype |
| _(idea)_ | Our own suggestion for the custom board, not yet designed or tested |
| _(estimate)_ | Our own guess, not measured |

Priority: **P1** = must fix before real users; **P2** = should fix; **P3** = nice to have.

---

## 1. What the StickS3 is (facts we rely on)

| Part | Detail | Source |
|---|---|---|
| Chip | ESP32-S3-PICO-1-N8R8: dual-core Xtensa LX7 up to 240 MHz, 8 MB flash, 8 MB Octal PSRAM | ✅ [D1] |
| Wireless | 2.4 GHz Wi-Fi and **Bluetooth 5 (LE)**. **No Bluetooth Classic** on ESP32-S3: "ESP-NimBLE supports Bluetooth LE only. Classic Bluetooth is not supported." | ✅ [D1][D2][D3] |
| Screen | 1.14" ST7789P3, 135 × 240 (SPI: G39 MOSI, G40 SCK, G45 RS, G41 CS, G21 RST, G38 backlight) | ✅ [D1] |
| Buttons | **KEY1** (front, G11) and **KEY2** (side, G12) are programmable. A third **power button** goes to the power chip: single click = power on / **reset**, double click = power off, long press = download mode | ✅ [D1][D4] |
| Power chip | M5PM1 (I2C 0x6E): power modes, charge status, battery voltage reading, speaker enable, motion-sensor interrupt | ✅ [D1] |
| Motion sensor | BMI270 6-axis (I2C 0x68), interrupt wired to the power chip | ✅ [D1] |
| Audio | ES8311 codec, MEMS microphone (SNR 65 dB), AW8737 amplifier, 8 Ω 1 W speaker | ✅ [D1] |
| IR | Transmitter G46, receiver G42 | ✅ [D1] |
| Battery | 250 mAh lithium, charged over USB-C 5 V. Schematic labels the charge current "190mA" | ✅ [D1] (schematic) |
| Power use | Off 14.02 µA · L1 standby 52.47 µA · L2 deep sleep 102.40 µA · L3A core active 36.69 mA · full load 519.02 mA (all at 4.2 V) | ✅ [D1] |
| Size / weight | 48 × 24 × 15 mm, 20 g | ✅ [D1] |
| Operating temperature | **0 to 40 °C** | ✅ [D1][D4] |
| Expansion | Hat2 bus (2.54 mm, 16 pins), HY2.0-4P Grove port (G9, G10), magnetic back. **Hat 18650C battery add-on does not fit** | ✅ [D1] |
| Vibration motor | **None** listed | ✅ (absent from features and pin map [D1]) |

## 2. Prototype check against the plan

| Plan feature | StickS3 | Status |
|---|---|---|
| Bluetooth mouse + keyboard (AssistiveTouch) | Bluetooth LE HID (HID over GATT) | ✅ hardware fits; prove in T1 |
| Command channel from the app | Custom Bluetooth LE service next to HID | ✅ hardware fits; prove in T2 |
| Status screen | 135 × 240 colour | ✅ English text (v1) |
| Approve / Cancel | KEY1 = Approve, KEY2 = Cancel | ✅ |
| Shake to stop | BMI270 | ✅ |
| Beeps | Speaker (keep volume < 75% on battery [D1]) | ✅ |
| Battery % | Power chip reads battery voltage and charge status | ✅ |
| Wake on button | KEY1/KEY2 and motion interrupt wake the device (power diagram) | ✅ |
| Updates over Bluetooth | 8 MB flash fits two firmware copies; `ble_ota` exists | ✅ hardware fits; not tested |

---

## 3. Improvements for our custom board

### 3.1 Power and battery

| # | Problem on StickS3 | Evidence | Improvement for custom board | Priority |
|---|---|---|---|---|
| H1 | **Small battery (250 mAh).** With the chip running (36.69 mA) plus Bluetooth and screen, a full day is unlikely | ✅ [D1]; runtime ~2–4 h with screen + Bluetooth active _(estimate)_; one buyer reports about 4 h on standby 📰 [D5] | Bigger battery. **Size it from T9 measurements** (target: a full day of normal use). Leave space in the enclosure | P1 |
| H2 | **No add-on battery option:** the Hat 18650C does not fit | ✅ [D1] | Battery built in at the right size (H1); no add-on needed | P2 |
| H3 | **Slow charge for a bigger battery:** 190 mA charge current | ✅ [D1] schematic | Charger sized for the new battery (higher current, with thermal limits) | P2 |
| H4 | **Brown-out risk:** "keep the speaker volume below 75%" on battery "to avoid unexpected device reboot" | ✅ [D1] | Power supply with headroom for speaker peaks and Bluetooth transmit peaks at the same time (stronger regulator, more bulk capacitance) _(idea)_ | P1 |
| H5 | **Battery % is voltage-based** (ADC through the power chip), which is imprecise under load | ✅ [D1] (VBAT_ADC) | A battery fuel-gauge chip for an accurate % _(idea)_ | P3 |
| H6 | **Deep sleep drops the Bluetooth link**, so waking means the iPhone reconnects (slower start) | Deep sleep powers down the radio _(general ESP32 behaviour)_; reconnect time ❓ | Measure in the prototype: light sleep (stays connected) vs deep sleep. Design the power budget around the winner | P2 |
| H7 | **USB-C needed to charge** | ✅ [D1] | Keep USB-C for charging. Consider wireless (Qi) charging _(idea)_ | P3 |

### 3.2 Buttons and user interaction

| # | Problem on StickS3 | Evidence | Improvement for custom board | Priority |
|---|---|---|---|---|
| H8 | **Power button resets on a single click.** A pocket press mid-task restarts the device and kills the task | ✅ [D1][D4] | Power/reset that cannot be pressed by accident: long-press to power off, **pin-hole** reset _(idea)_. Firmware must also resume safely after any reset | P1 |
| H9 | **Only two programmable buttons**, KEY2 on the side | ✅ [D1] | Dedicated **Approve**, **Cancel** and a distinct **Stop** button with different shapes, easy to feel in a pocket _(idea)_ | P2 |
| H10 | **No vibration motor:** approvals need the screen or a beep (not silent) | ✅ [D1] | Add a small vibration motor for silent alerts ("needs approval") _(idea)_ | P2 |
| H11 | **Small screen (1.14", 135 × 240)** | ✅ [D1] | Evaluate a larger or lower-power screen; it must render Hindi (Devanagari) later _(idea)_ | P3 |

### 3.3 Radio and security

| # | Problem on StickS3 | Evidence | Improvement for custom board | Priority |
|---|---|---|---|---|
| H12 | **Antenna is fragile:** "Disassembly may damage the antenna PFC circuit" | ✅ [D1][D4] | Design and tune the antenna for **in-pocket, next-to-body** use; test range and drop-outs _(idea)_ | P1 |
| H13 | **Wi-Fi and Bluetooth share one 2.4 GHz radio** | ✅ ESP32-S3 has one 2.4 GHz radio [D1] | Keep Wi-Fi **off** during tasks; Bluetooth only _(idea)_. Re-check if we ever add Wi-Fi features | P2 |
| H14 | **A device that can tap anything is a security risk** if its firmware is replaced or read | Plan section 9 (device security) | Turn on **Secure Boot V2** and **flash encryption** (supported on ESP32-S3 [D6]); signed firmware updates; bond only with the owner's phone | P1 |
| H15 | **Bluetooth LE only (no Classic)** | ✅ [D2][D3] | Fine for an iPhone mouse over Bluetooth LE (existing projects use it 📰). Re-check chip choice only if T1 shows Bluetooth LE problems | P3 |

### 3.4 Size, cost and environment

| # | Problem on StickS3 | Evidence | Improvement for custom board | Priority |
|---|---|---|---|---|
| H16 | **Operating temperature 0–40 °C.** Indian summers and pockets can go above 40 °C | ✅ [D1][D4] | Choose parts and a battery rated for higher temperatures; add a temperature check that pauses tasks when too hot _(idea)_. **Test in real heat** ❓ | P1 |
| H17 | **Parts we don't need:** IR transmitter/receiver, Hat2 bus, Grove port | ✅ [D1] (present on board) | Remove them to cut cost, size and power _(idea)_ | P2 |
| H18 | **Chip may be more than we need** (8 MB Octal PSRAM) | ✅ [D1] | Re-check memory needs after firmware is written; a cheaper ESP32 module may be enough _(idea)_ | P3 |
| H19 | **No water or dust protection** listed | Not mentioned in [D1] | Splash resistance for pocket use _(idea)_ | P3 |
| H20 | **Mounting:** magnetic back exists, but no tested way to attach to the phone | ✅ [D1] | A mount (e.g. magnetic, MagSafe-compatible ring) or lanyard _(idea, untested)_ | P3 |

### 3.5 Selling the device (later)

| # | Item | Evidence | Action | Priority |
|---|---|---|---|---|
| H21 | **Wireless certification** before selling | India: Bluetooth devices generally need a **WPC ETA** (Equipment Type Approval) before import or sale 📰 [D7] (consultancy sources, check with DoT/WPC). Other countries have their own (e.g. FCC, CE) | Use a **pre-certified ESP32 module** to make certification easier _(idea)_; confirm rules with an expert before selling | P1 (before selling) |

---

## 4. What the prototype must measure (feeds this file)

| Measure | Test in plan | Feeds |
|---|---|---|
| Battery runtime: screen on + Bluetooth; screen off + connected; deep sleep | T9 | H1, H6 |
| Speaker + Bluetooth together on battery: any reboots? | new | H4 |
| Reconnect time after deep sleep | new | H6 |
| Bluetooth range and drop-outs with the device in a pocket | new | H12 |
| Device temperature in a pocket on a hot day | new | H16 |
| Accidental power-button presses in a pocket | new | H8 |

## 5. How to add a new improvement
Add a row in the right table with: a new number (H22, H23, …), the problem, the evidence (with a marker), the improvement, and a priority. If it needs a measurement, add it to section 4.

---

## 6. Sources

| # | Source |
|---|---|
| D1 | M5Stack StickS3 (K150) documentation, saved as [Docs/StickS3.pdf](../StickS3.pdf) (updated 2026-05-21) and online at [docs.m5stack.com/en/core/StickS3](https://docs.m5stack.com/en/core/StickS3) |
| D2 | [Espressif: ESP32-S3-PICO-1 datasheet](https://www.espressif.com/sites/default/files/documentation/esp32-s3-pico-1_datasheet_en.pdf) |
| D3 | [ESP-IDF: Bluetooth overview for ESP32-S3](https://docs.espressif.com/projects/esp-idf/en/stable/esp32s3/api-guides/bluetooth.html) |
| D4 | [M5Stack StickS3 online docs: buttons, notes, operating temperature](https://docs.m5stack.com/en/core/StickS3) |
| D5 | [Botland: M5StickS3 listing and review](https://botland.store/stick-series/27815-m5sticks3-iot-development-module-esp32-s3-pico-1-m5stack-k150-6972934171955.html) |
| D6 | [ESP-IDF: Flash encryption for ESP32-S3](https://docs.espressif.com/projects/esp-idf/en/latest/esp32s3/security/flash-encryption.html) and the ESP-IDF Security guides (Secure Boot V2) |
| D7 | [WPC ETA certificate for import in India (consultancy article)](https://www.agileregulatory.com/blogs/wpc-eta-certificate-for-import-in-india) and [DoT clarification on ETA and import licence (PDF)](https://dot.gov.in/sites/default/files/Clarification%20regrading%20ETA%20and%20import%20license_0.pdf?download=1) |
