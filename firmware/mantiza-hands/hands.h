// Pointer/keyboard gestures over BLE HID; called only from the Arduino loop.
// Adapted from await-ovo/esp32-iphone-agent hid_control (MIT, (c) 2026 Henry Yuan), absolute pointer version.
#pragma once
#include <Arduino.h>

void hands_poll();     // clear held keys on a new HID session, retry failed releases
void hands_release();  // let go of every button and key
String hands_run(const String &line);  // "ok [result]" or "err <why>"
