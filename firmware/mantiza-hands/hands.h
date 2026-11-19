// Pointer/keyboard gestures over BLE HID; called only from the Arduino loop.
// Adapted from await-ovo/esp32-iphone-agent hid_control (MIT, (c) 2026 Henry Yuan), absolute pointer version.
#pragma once
#include <Arduino.h>

// Clear held keys on a new HID session, retry failed releases, and let go of a button held by `press` once no
// command has come for HELD_MAX_MS (the app may have died mid-drag).
void hands_poll();
void hands_release();  // let go of every button and key
String hands_run(const String &line);  // "ok [result]" or "err <why>"
