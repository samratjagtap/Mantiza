#include "hands.h"
#include <esp_task_wdt.h>
#include "ble_link.h"
#include "ui.h"
#include "src/hid/report.h"

const int KEY_EDGE_MS = 15;      // per key down/up: at 5 ms iOS dropped characters (jinwon-int #104)
const int REPORT_MS = 8;         // between pointer reports in a stroke
const int TAP_HOLD_MS = 60;
const int SETTLE_MS = 30;        // pointer at the target before pressing
const uint32_t WAKE_AFTER_MS = 2000;  // iOS hides an idle pointer after ~2 s
const int WAKE_MS = 300;              // and needs a moment to show it again before a click lands
const long STROKE_MAX = 100;
const long LONGPRESS_MAX_MS = 5000;

static uint32_t session;
static uint8_t buttons;
static uint16_t posX = HID_ABS_MAX / 2, posY = HID_ABS_MAX / 2;
static uint32_t lastPointerMs;
static bool releasePending = true;

static bool send(uint8_t report, const uint8_t *data, size_t n, int pauseMs) {
  esp_task_wdt_reset();
  if (ble_hid_send(report, data, n, session)) { delay(pauseMs); return true; }
  releasePending = true;
  return false;
}

static bool pointer(uint16_t x, uint16_t y, int wheel = 0, int pan = 0, int pauseMs = REPORT_MS) {
  uint8_t r[HID_MOUSE_LEN];
  hid_mouse_report(r, buttons, x, y, wheel, pan);
  posX = x;
  posY = y;
  lastPointerMs = millis();
  return send(HID_REPORT_MOUSE, r, sizeof r, pauseMs);
}

// Show the pointer again if iOS hid it, so the next click lands where we aim.
static bool wakeAt(uint16_t x, uint16_t y) {
  bool idle = millis() - lastPointerMs > WAKE_AFTER_MS;
  if (!pointer(x, y)) return false;
  if (idle) delay(WAKE_MS);
  return true;
}

static bool setButtons(uint8_t b) {
  buttons = b;
  return pointer(posX, posY);
}

void hands_release() { releasePending = true; hands_poll(); }

void hands_poll() {
  uint32_t current = ble_hid_session();
  if (current != session) { session = current; releasePending = true; }
  if (!releasePending) return;
  buttons = 0;
  if (!session) return;
  uint8_t zero[8] = {0}, m[HID_MOUSE_LEN];
  hid_mouse_report(m, 0, posX, posY, 0, 0);
  // Try each release even if another report failed. Retry on the next loop if necessary.
  bool a = send(HID_REPORT_MOUSE, m, sizeof m, REPORT_MS), k = send(HID_REPORT_KEYBOARD, zero, HID_KEYBOARD_LEN, KEY_EDGE_MS),
       c = send(HID_REPORT_CONSUMER, zero, HID_CONSUMER_LEN, KEY_EDGE_MS);
  releasePending = !(a && k && c);
}

static bool keyboard(const uint8_t report[8]) {
  if (!send(HID_REPORT_KEYBOARD, report, HID_KEYBOARD_LEN, KEY_EDGE_MS)) return false;
  uint8_t zero[8] = {0};
  return send(HID_REPORT_KEYBOARD, zero, HID_KEYBOARD_LEN, KEY_EDGE_MS);
}

static bool consumer(uint16_t usage) {
  uint8_t down[] = {(uint8_t)(usage & 0xFF), (uint8_t)(usage >> 8)}, zero[2] = {0};
  bool ok = send(HID_REPORT_CONSUMER, down, sizeof down, 40);
  bool released = send(HID_REPORT_CONSUMER, zero, sizeof zero, KEY_EDGE_MS);
  return ok && released;
}

static bool inRange(long v) { return v >= 0 && v <= HID_ABS_MAX; }

static bool tap(uint16_t x, uint16_t y, int holdMs) {
  if (!wakeAt(x, y)) return false;
  delay(SETTLE_MS);
  bool down = setButtons(1);
  delay(holdMs);
  bool up = setButtons(0);
  return down && up;
}

// The board plays the whole stroke at REPORT_MS per report: one command per report would be one link round trip
// (~170 ms), the finger would crawl and iOS would snap a page back (jinwon-int #74). Always let go at the end.
static bool stroke(long x1, long y1, long x2, long y2, long n) {
  if (!wakeAt(x1, y1)) return false;
  delay(SETTLE_MS);
  bool ok = setButtons(1);
  for (long i = 1; i <= n && ok; i++) ok = pointer(x1 + (x2 - x1) * i / n, y1 + (y2 - y1) * i / n);
  bool up = setButtons(0);
  return ok && up;
}

String hands_run(const String &line) {
  int sp = line.indexOf(' ');
  String cmd = sp < 0 ? line : line.substring(0, sp);
  String arg = sp < 0 ? "" : line.substring(sp + 1);
  long a = 0, b = 0, c = 0, d = 0, e = 0;
  int n = sscanf(arg.c_str(), "%ld %ld %ld %ld %ld", &a, &b, &c, &d, &e);
  hands_poll();
  if (!session) return "err mouse not ready (pair in AssistiveTouch > Devices)";
  if (releasePending) return "err release pending";
  bool ok = false;
  if (cmd == "at" || cmd == "wake") {
    if (cmd == "wake") { a = posX; b = posY; n = 2; }
    if (n < 2 || !inRange(a) || !inRange(b)) return "err at needs x y in 0..32767";
    ok = wakeAt(a, b);
  } else if (cmd == "move") {  // relative to the last position, in absolute units
    if (n < 2) return "err move needs dx dy";
    ok = wakeAt(constrain(posX + a, 0, HID_ABS_MAX), constrain(posY + b, 0, HID_ABS_MAX));
  } else if (cmd == "tap") {
    if (n < 2 || !inRange(a) || !inRange(b)) return "err tap needs x y in 0..32767";
    ok = tap(a, b, n >= 3 ? constrain(c, 20, 1000) : TAP_HOLD_MS);
  } else if (cmd == "longpress") {
    if (n < 2 || !inRange(a) || !inRange(b)) return "err longpress needs x y [ms]";
    ok = tap(a, b, n >= 3 ? constrain(c, 300, LONGPRESS_MAX_MS) : 1000);
  } else if (cmd == "stroke") {
    if (n != 5 || !inRange(a) || !inRange(b) || !inRange(c) || !inRange(d)) return "err stroke needs x1 y1 x2 y2 n";
    if (e < 1 || e > STROKE_MAX) return "err stroke needs n in 1.." + String(STROKE_MAX);
    ok = stroke(a, b, c, d, e);
  } else if (cmd == "press") {
    ok = setButtons(1);
  } else if (cmd == "release") {
    hands_release();
    ok = !releasePending;
  } else if (cmd == "scroll") {
    if (n != 2 || a < -127 || a > 127 || b < -127 || b > 127) return "err scroll needs v h in -127..127";
    ok = pointer(posX, posY, a, b);
  } else if (cmd == "park") {  // off content, left edge middle, after taps
    ok = pointer(HID_ABS_MAX * 15 / 1000, HID_ABS_MAX / 2);
  } else if (cmd == "type") {
    // Reject the whole string before typing, so unsupported UTF-8 never produces partial text.
    for (size_t i = 0; i < arg.length(); i++)
      if (!hid_ascii((uint8_t)arg[i])) return "err type supports ASCII only";
    ok = true;
    for (size_t i = 0; i < arg.length() && ok; i++) {
      if (ui_stop_requested()) { hands_release(); return "err stopped"; }
      uint16_t key = hid_ascii((uint8_t)arg[i]);
      uint8_t report[8] = {(uint8_t)(key & 0x100 ? 2 : 0), 0, (uint8_t)key};
      ok = keyboard(report);
    }
  } else if (cmd == "key") {
    uint8_t report[8];
    if (!hid_combo(arg.c_str(), report)) return "err unknown key or too many keys";
    ok = keyboard(report);
  } else if (cmd == "home") {  // Home Screen
    ok = consumer(hid_consumer("home"));
  } else if (cmd == "consumer") {
    uint16_t u = hid_consumer(arg.c_str());
    if (!u) return "err unknown consumer key";
    ok = consumer(u);
  } else return "err unknown command";
  if (!ok) hands_release();
  return ok ? "ok" : "err HID send failed";
}
