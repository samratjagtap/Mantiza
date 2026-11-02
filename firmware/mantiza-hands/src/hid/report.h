// BLE HID report IDs and US keyboard encoding, shared with the host tests.
// Adapted from await-ovo/esp32-iphone-agent (MIT, (c) 2026 Henry Yuan); absolute pointer from jinwon-int's fork.
#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum { HID_REPORT_MOUSE = 1, HID_REPORT_KEYBOARD = 2, HID_REPORT_CONSUMER = 3 };
enum { HID_MOUSE_LEN = 7, HID_KEYBOARD_LEN = 8, HID_CONSUMER_LEN = 2 };
#define HID_ABS_MAX 32767

extern const uint8_t hid_report_map[];
extern const size_t hid_report_map_size;

// Absolute pointer report: buttons, x and y (little-endian, 0..HID_ABS_MAX), wheel, pan.
void hid_mouse_report(uint8_t out[HID_MOUSE_LEN], uint8_t buttons, uint16_t x, uint16_t y, int8_t wheel, int8_t pan);

// Low byte: keyboard usage; bit 8: left Shift. Zero means unsupported.
uint16_t hid_ascii(uint8_t c);
// Parse the whole combination before sending any keys. Output is an 8-byte keyboard report.
bool hid_combo(const char *combo, uint8_t report[8]);
// Consumer usage for a name (home, search, globe, keyboard, playpause, volup, voldown) or 0xNNNN; zero if unknown.
uint16_t hid_consumer(const char *name);

#ifdef __cplusplus
}
#endif
