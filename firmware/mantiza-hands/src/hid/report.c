#include "report.h"
#include <stdlib.h>
#include <string.h>

// Report mode: 6-key keyboard, absolute pointer (buttons/X/Y/wheel/pan), consumer control.
// BLE carries the report ID in the Report Reference descriptor, not in the payload.
// Keyboard first: iOS only treats the device as a hardware keyboard (Shift, layouts) in this order.
// The absolute X/Y (16-bit, 0..32767) maps 1:1 onto the whole screen on iOS 27 in portrait
// (measured by jinwon-int/esp32-iphone-agent, PR #105), so no acceleration or calibration of speed.
const uint8_t hid_report_map[] = {
  0x05,0x01, 0x09,0x06, 0xA1,0x01, 0x85,HID_REPORT_KEYBOARD,
  0x05,0x07, 0x19,0xE0, 0x29,0xE7, 0x15,0x00, 0x25,0x01,
  0x75,0x01, 0x95,0x08, 0x81,0x02,
  0x75,0x08, 0x95,0x01, 0x81,0x03,
  0x05,0x08, 0x19,0x01, 0x29,0x05, 0x75,0x01, 0x95,0x05, 0x91,0x02,
  0x75,0x03, 0x95,0x01, 0x91,0x03,
  0x05,0x07, 0x19,0x00, 0x29,0x65, 0x15,0x00, 0x25,0x65,
  0x75,0x08, 0x95,0x06, 0x81,0x00, 0xC0,

  0x05,0x01, 0x09,0x02, 0xA1,0x01, 0x85,HID_REPORT_MOUSE,
  0x09,0x01, 0xA1,0x00, 0x05,0x09, 0x19,0x01, 0x29,0x05,
  0x15,0x00, 0x25,0x01, 0x95,0x05, 0x75,0x01, 0x81,0x02,
  0x95,0x01, 0x75,0x03, 0x81,0x03,
  0x05,0x01, 0x09,0x30, 0x09,0x31, 0x16,0x00,0x00, 0x26,0xFF,0x7F,
  0x75,0x10, 0x95,0x02, 0x81,0x02,
  0x09,0x38, 0x15,0x81, 0x25,0x7F, 0x75,0x08, 0x95,0x01, 0x81,0x06,
  0x05,0x0C, 0x0A,0x38,0x02, 0x15,0x81, 0x25,0x7F, 0x75,0x08, 0x95,0x01, 0x81,0x06,
  0xC0, 0xC0,

  0x05,0x0C, 0x09,0x01, 0xA1,0x01, 0x85,HID_REPORT_CONSUMER,
  0x15,0x00, 0x26,0xFF,0x03, 0x19,0x00, 0x2A,0xFF,0x03,
  0x75,0x10, 0x95,0x01, 0x81,0x00, 0xC0
};
const size_t hid_report_map_size = sizeof hid_report_map;

void hid_mouse_report(uint8_t out[HID_MOUSE_LEN], uint8_t buttons, uint16_t x, uint16_t y, int8_t wheel, int8_t pan) {
  if (x > HID_ABS_MAX) x = HID_ABS_MAX;
  if (y > HID_ABS_MAX) y = HID_ABS_MAX;
  out[0] = buttons;
  out[1] = x & 0xFF;
  out[2] = x >> 8;
  out[3] = y & 0xFF;
  out[4] = y >> 8;
  out[5] = (uint8_t)wheel;
  out[6] = (uint8_t)pan;
}

uint16_t hid_ascii(uint8_t c) {
  if (c >= 'a' && c <= 'z') return 0x04 + c - 'a';
  if (c >= 'A' && c <= 'Z') return 0x104 + c - 'A';
  if (c >= '1' && c <= '9') return 0x1E + c - '1';
  if (c == '0') return 0x27;
  if (c == '\n' || c == '\r') return 0x28;
  if (c == '\b') return 0x2A;
  if (c == '\t') return 0x2B;
  if (c == ' ') return 0x2C;
  if (c == 0x1B) return 0x29;
  if (c == 0x7F) return 0x4C;
  const char *plain = "-=[]\\;',./`";
  const char *shift = "_+{}|:\"<>?~";
  const uint8_t usages[] = {0x2D,0x2E,0x2F,0x30,0x31,0x33,0x34,0x36,0x37,0x38,0x35};
  for (size_t i = 0; i < sizeof usages; i++) {
    if (c == (uint8_t)plain[i]) return usages[i];
    if (c == (uint8_t)shift[i]) return 0x100 | usages[i];
  }
  const char *digits = "!@#$%^&*()";
  for (int i = 0; i < 10; i++) if (c == (uint8_t)digits[i]) return 0x100 | (0x1E + i);
  return 0;
}

bool hid_combo(const char *combo, uint8_t report[8]) {
  uint8_t out[8] = {0};
  int keys = 0;
  if (!*combo) return false;
  for (const char *p = combo; *p;) {
    const char *end = strchr(p, '+');
    size_t n = end ? (size_t)(end - p) : strlen(p);
    uint16_t key = 0;
    if (!n) return false;
    if (n == 1) key = hid_ascii((uint8_t)*p);
    else if (n == 3 && !memcmp(p, "cmd", n)) out[0] |= 8;
    else if (n == 4 && !memcmp(p, "ctrl", n)) out[0] |= 1;
    else if (n == 3 && !memcmp(p, "alt", n)) out[0] |= 4;
    else if (n == 5 && !memcmp(p, "shift", n)) out[0] |= 2;
    else if (n == 5 && !memcmp(p, "enter", n)) key = 0x28;
    else if (n == 3 && !memcmp(p, "esc", n)) key = 0x29;
    else if (n == 3 && !memcmp(p, "tab", n)) key = 0x2B;
    else if (n == 9 && !memcmp(p, "backspace", n)) key = 0x2A;
    else if (n == 5 && !memcmp(p, "space", n)) key = 0x2C;
    else if (n == 2 && !memcmp(p, "up", n)) key = 0x52;
    else if (n == 4 && !memcmp(p, "down", n)) key = 0x51;
    else if (n == 4 && !memcmp(p, "left", n)) key = 0x50;
    else if (n == 5 && !memcmp(p, "right", n)) key = 0x4F;
    else return false;
    if (n == 1 && !key) return false;
    if (key) {
      if (key & 0x100) out[0] |= 2;
      bool duplicate = false;
      for (int i = 0; i < keys; i++) if (out[i + 2] == (uint8_t)key) duplicate = true;
      if (!duplicate) {
        if (keys == 6) return false;
        out[2 + keys++] = (uint8_t)key;
      }
    }
    if (!end) break;
    p = end + 1;
    if (!*p) return false;
  }
  memcpy(report, out, sizeof out);
  return true;
}

uint16_t hid_consumer(const char *name) {
  // Apple's Home button is consumer 0x0040 (Menu); AC Home (0x0223) did nothing on iOS 27 (jinwon-int #17).
  if (!strcmp(name, "home")) return 0x0040;
  if (!strcmp(name, "achome")) return 0x0223;
  if (!strcmp(name, "search")) return 0x0221;
  if (!strcmp(name, "globe")) return 0x029D;
  if (!strcmp(name, "keyboard")) return 0x01AE;  // toggles the on-screen keyboard
  if (!strcmp(name, "playpause")) return 0x00CD;
  if (!strcmp(name, "volup")) return 0x00E9;
  if (!strcmp(name, "voldown")) return 0x00EA;
  if (name[0] == '0' && (name[1] == 'x' || name[1] == 'X')) {
    char *end;
    unsigned long u = strtoul(name + 2, &end, 16);
    if (*end == 0 && u > 0 && u <= 0x3FF) return (uint16_t)u;
  }
  return 0;
}
