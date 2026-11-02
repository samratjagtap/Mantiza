// BLE GATT link to the Mantiza iOS app: cmd/reply, status heartbeat, and encrypted HID.
// Adapted from await-ovo/esp32-iphone-agent (MIT, (c) 2026 Henry Yuan). h2zero NimBLE-Arduino 2.5.x;
// build with build.sh (it force-includes nimble_cfg.h, the host buffer sizes).
#pragma once
#include <Arduino.h>

// Command service, also used by the app's AccessorySetupKit discovery descriptor.
#define MANTIZA_UUID(s) "f5da" s "-6c5e-4c62-bbd9-ba1b370af73d"
#define MANTIZA_SERVICE_UUID MANTIZA_UUID("0600")

void ble_begin(const String &name);
bool ble_connected();
bool ble_pop_cmd(String &line, uint32_t wait_ms);  // next `cmd` write, oldest first
void ble_reply(const String &line);                // queued
void ble_status(const String &json);               // latest wins
void ble_unpair();
void ble_set_battery(uint8_t percent);

// New bonds are accepted only while pairing is open: always when the board has no bonds,
// otherwise for a short window the user opens on the device. Re-encryption of an existing bond is always fine.
void ble_open_pairing(uint32_t ms);
bool ble_pairing_open();

// One encrypted HID host. The session changes on HID changes or a command peer leaving;
// an in-flight gesture must never continue on a newly connected host.
const char *ble_hid_state();  // ok | asleep | off
uint32_t ble_hid_session();  // zero until mouse, keyboard and consumer reports are subscribed
uint32_t ble_hid_generation();  // also changes when HID reconnects between status heartbeats
bool ble_hid_send(uint8_t report, const uint8_t *data, size_t len, uint32_t session);

uint16_t ble_mtu();
uint8_t ble_phy();       // 1 or 2 (Mbit)
uint32_t ble_reply_drops();  // replies that never got out to a subscribed peer
uint32_t ble_hid_drops();    // HID reports that could not be sent
int ble_peers();         // connected centrals
