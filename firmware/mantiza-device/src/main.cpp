// Mantiza device firmware (Phase 1). Started as a copy of firmware/t1-hid-test (tests T1, T1b, T2,
// T4d, T9), which stays as the record of those tests.
// Change from the test firmware: an ABSOLUTE pointer (ABSOLUTE_POINTER=1). "tap x y" takes x, y in
// 0..32767 across the whole screen and the pointer jumps there in one report: no corner reset, no
// small steps, no calibration (shown over BLE on an iPhone by jinwon-int/esp32-iphone-agent #104,
// 2026-10-27). ABSOLUTE_POINTER=0 builds the old relative mouse as a fallback.
//
// StickS3 acts as a Bluetooth LE mouse + keyboard for an iPhone (AssistiveTouch pointer).
// The Mantiza app (apps/mantiza) writes text commands on a private "command channel" service
// ("tap x y", "t hello", "k cmd+space", "status Opening WhatsApp") and the device answers with
// notifications ("ok ...", "hi ...", "stop").
//
// Screen:   Mantiza's pixel head and wordmark, connection, battery and what Mantiza is doing.
// Buttons:  front = Stop while a task runs; any button wakes the screen.
// Serial:   USB at 115200 baud, type "help" for commands.

#include <M5Unified.h>
#include <NimBLEDevice.h>
#include <NimBLEHIDDevice.h>
#include <Preferences.h>

#ifndef ABSOLUTE_POINTER
#define ABSOLUTE_POINTER 1
#endif

static const char* DEVICE_NAME = "Mantiza";

// Command channel (must match the app, apps/mantiza/Sources/Mantiza/DeviceLink.swift)
static const char* COMMAND_SERVICE_UUID = "f665cd1c-b15f-4ffa-b950-9d0f007b7db5";
static const char* COMMAND_WRITE_UUID   = "2af74626-d331-4239-bd47-2ef715cab51e";  // app -> device
static const char* COMMAND_EVENT_UUID   = "7a537076-9f59-4e6d-94eb-c90356cea6f3";  // device -> app (notify)

// ---------------------------------------------------------------------------
// HID report map: keyboard (report 1) + mouse (report 2) + special keys (report 3) + Focus (report 4)
// ---------------------------------------------------------------------------
static const uint8_t REPORT_ID_KEYBOARD = 1;
static const uint8_t REPORT_ID_MOUSE    = 2;
static const uint8_t REPORT_ID_CONSUMER = 3;
static const uint8_t REPORT_ID_SYSTEM   = 4;

// Bump this whenever REPORT_MAP or the list of services changes. The iPhone caches
// both for a paired device, so a change needs a fresh pairing: old bonds are cleared on boot.
// 3 = T2 command channel added. 4 = absolute pointer (5 = relative fallback build).
// 6 = special keys + Focus key added (7 = relative fallback build).
static const uint32_t REPORT_MAP_VERSION = ABSOLUTE_POINTER ? 6 : 7;

static const uint8_t REPORT_MAP[] = {
  // Keyboard
  0x05, 0x01,       // Usage Page (Generic Desktop)
  0x09, 0x06,       // Usage (Keyboard)
  0xA1, 0x01,       // Collection (Application)
  0x85, REPORT_ID_KEYBOARD,
  0x05, 0x07,       //   Usage Page (Key Codes)
  0x19, 0xE0, 0x29, 0xE7,  // Modifiers: Left Ctrl .. Right GUI
  0x15, 0x00, 0x25, 0x01,
  0x75, 0x01, 0x95, 0x08,
  0x81, 0x02,       //   Input (Data, Var, Abs): modifier byte
  0x95, 0x01, 0x75, 0x08,
  0x81, 0x01,       //   Input (Const): reserved byte
  0x95, 0x05, 0x75, 0x01,
  0x05, 0x08, 0x19, 0x01, 0x29, 0x05,
  0x91, 0x02,       //   Output (Data, Var, Abs): LEDs
  0x95, 0x01, 0x75, 0x03,
  0x91, 0x01,       //   Output (Const): LED padding
  0x95, 0x06, 0x75, 0x08,
  0x15, 0x00, 0x25, 0x65,
  0x05, 0x07, 0x19, 0x00, 0x29, 0x65,
  0x81, 0x00,       //   Input (Data, Array): 6 key codes
  0x05, 0xFF,       //   Usage Page (Apple vendor "top case"), experimental
  0x09, 0x03,       //   Usage (Fn / Globe key)
  0x15, 0x00, 0x25, 0x01,
  0x75, 0x01, 0x95, 0x01,
  0x81, 0x02,       //   Input (Data, Var, Abs): Fn bit
  0x75, 0x07, 0x95, 0x01,
  0x81, 0x01,       //   Input (Const): Fn padding
  0xC0,             // End Collection

  // Mouse
  0x05, 0x01,       // Usage Page (Generic Desktop)
  0x09, 0x02,       // Usage (Mouse)
  0xA1, 0x01,       // Collection (Application)
  0x85, REPORT_ID_MOUSE,
  0x09, 0x01,       //   Usage (Pointer)
  0xA1, 0x00,       //   Collection (Physical)
  0x05, 0x09, 0x19, 0x01, 0x29, 0x08,  // Buttons 1..8
  0x15, 0x00, 0x25, 0x01,
  0x95, 0x08, 0x75, 0x01,
  0x81, 0x02,       //     Input (Data, Var, Abs): buttons
#if ABSOLUTE_POINTER
  0x05, 0x01, 0x09, 0x30, 0x09, 0x31,  // X, Y
  0x16, 0x00, 0x00, 0x26, 0xFF, 0x7F,  // 0..32767
  0x75, 0x10, 0x95, 0x02,
  0x81, 0x02,       //     Input (Data, Var, Abs): x, y (16 bit each)
  0x09, 0x38,       //     Wheel
  0x15, 0x81, 0x25, 0x7F,
  0x75, 0x08, 0x95, 0x01,
  0x81, 0x06,       //     Input (Data, Var, Rel)
#else
  0x05, 0x01, 0x09, 0x30, 0x09, 0x31, 0x09, 0x38,  // X, Y, Wheel
  0x15, 0x81, 0x25, 0x7F,
  0x75, 0x08, 0x95, 0x03,
  0x81, 0x06,       //     Input (Data, Var, Rel)
#endif
  0xC0,             //   End Collection
  0xC0,             // End Collection

  // Special keys: the HID Consumer page usages Apple lists for keyboards (Accessory Design
  // Guidelines R32 Update 1, Table 14-3): Home, Lock, Screenshot, brightness, media, Siri,
  // volume, Spotlight, Globe, on-screen keyboard. One 16-bit usage per report, 0 = released.
  0x05, 0x0C,       // Usage Page (Consumer)
  0x09, 0x01,       // Usage (Consumer Control)
  0xA1, 0x01,       // Collection (Application)
  0x85, REPORT_ID_CONSUMER,
  0x15, 0x00, 0x26, 0xFF, 0x03,  // Logical 0..1023
  0x19, 0x00, 0x2A, 0xFF, 0x03,  // Usage 0..0x3FF
  0x75, 0x10, 0x95, 0x01,
  0x81, 0x00,       //   Input (Data, Array): one usage
  0xC0,             // End Collection

  // Focus: Generic Desktop "System Do Not Disturb" (same guidelines, Table 14-4: Toggle Focus Mode)
  0x05, 0x01,       // Usage Page (Generic Desktop)
  0x09, 0x80,       // Usage (System Control)
  0xA1, 0x01,       // Collection (Application)
  0x85, REPORT_ID_SYSTEM,
  0x09, 0x9B,       //   Usage (System Do Not Disturb)
  0x15, 0x00, 0x25, 0x01,
  0x75, 0x01, 0x95, 0x01,
  0x81, 0x02,       //   Input (Data, Var, Abs): pressed bit
  0x75, 0x07, 0x95, 0x01,
  0x81, 0x01,       //   Input (Const): padding
  0xC0              // End Collection
};

// Keyboard modifier bits
static const uint8_t MOD_LSHIFT = 0x02;
static const uint8_t MOD_LGUI   = 0x08;  // Command key on Apple devices

// ---------------------------------------------------------------------------
// Bluetooth state
// ---------------------------------------------------------------------------
static NimBLEHIDDevice*      hid           = nullptr;
static NimBLECharacteristic* keyboardInput = nullptr;
static NimBLECharacteristic* mouseInput    = nullptr;
static NimBLECharacteristic* consumerInput = nullptr;
static NimBLECharacteristic* systemInput   = nullptr;
static volatile bool         connected     = false;

// Commands written by the app arrive on the Bluetooth task; they are queued
// and run in loop() so mouse/keyboard timing stays on one task.
struct AppCommand { char text[160]; };
static QueueHandle_t         appQueue      = nullptr;
static NimBLECharacteristic* eventOutput   = nullptr;
static volatile bool         appLinked     = false;  // app subscribed to events

class ServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer* server, ble_gap_conn_desc* desc) override {
    connected = true;
    Serial.println("[ble] connected");
  }
  void onDisconnect(NimBLEServer* server) override {
    connected = false;
    appLinked = false;
    Serial.println("[ble] disconnected, advertising again");
    NimBLEDevice::startAdvertising();
  }
  void onAuthenticationComplete(ble_gap_conn_desc* desc) override {
    Serial.printf("[ble] pairing %s (bonded=%d)\n",
                  desc->sec_state.encrypted ? "ok" : "FAILED",
                  desc->sec_state.bonded);
  }
};

class CommandWriteCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* c) override {
    NimBLEAttValue v = c->getValue();
    AppCommand cmd;
    size_t n = min((size_t)v.length(), sizeof(cmd.text) - 1);
    memcpy(cmd.text, v.data(), n);
    cmd.text[n] = 0;
    if (xQueueSend(appQueue, &cmd, 0) != pdTRUE) Serial.println("[t2] queue full, command dropped");
  }
};

class CommandEventCallbacks : public NimBLECharacteristicCallbacks {
  void onSubscribe(NimBLECharacteristic* c, ble_gap_conn_desc* desc, uint16_t subValue) override {
    appLinked = (subValue != 0);
    Serial.printf("[t2] app %s\n", appLinked ? "linked" : "unlinked");
  }
};

// Sends a text event to the app (no-op if the app isn't listening).
static void sendEvent(const String& text) {
  if (!eventOutput) return;
  eventOutput->setValue((const uint8_t*)text.c_str(), text.length());
  eventOutput->notify();
  Serial.printf("[t2] -> app: %s\n", text.c_str());
}

static void setupBluetooth() {
  NimBLEDevice::init(DEVICE_NAME);

  Preferences prefs;
  prefs.begin("mantiza", false);
  if (prefs.getUInt("mapver", 0) != REPORT_MAP_VERSION) {
    NimBLEDevice::deleteAllBonds();
    prefs.putUInt("mapver", REPORT_MAP_VERSION);
    Serial.println("[ble] report map changed: old pairings cleared, pair again");
  }
  prefs.end();
  // Bonding, no MITM ("Just Works"), LE Secure Connections
  NimBLEDevice::setSecurityAuth(true, false, true);
  NimBLEDevice::setSecurityIOCap(BLE_HS_IO_NO_INPUT_OUTPUT);

  NimBLEServer* server = NimBLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());

  hid = new NimBLEHIDDevice(server);
  keyboardInput = hid->inputReport(REPORT_ID_KEYBOARD);
  hid->outputReport(REPORT_ID_KEYBOARD);
  mouseInput = hid->inputReport(REPORT_ID_MOUSE);
  consumerInput = hid->inputReport(REPORT_ID_CONSUMER);
  systemInput = hid->inputReport(REPORT_ID_SYSTEM);

  hid->manufacturer()->setValue("Mantiza");
  hid->pnp(0x02, 0xE502, 0xA111, 0x0210);  // USB vendor ID source, test IDs
  hid->hidInfo(0x00, 0x01);
  hid->reportMap((uint8_t*)REPORT_MAP, sizeof(REPORT_MAP));
  hid->startServices();
  hid->setBatteryLevel(M5.Power.getBatteryLevel());

  NimBLEService* commandService = server->createService(COMMAND_SERVICE_UUID);
  NimBLECharacteristic* commandWrite = commandService->createCharacteristic(
      COMMAND_WRITE_UUID, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR);
  commandWrite->setCallbacks(new CommandWriteCallbacks());
  eventOutput = commandService->createCharacteristic(
      COMMAND_EVENT_UUID, NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);
  eventOutput->setCallbacks(new CommandEventCallbacks());
  commandService->start();

  NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
  adv->setAppearance(0x03C2);  // HID mouse
  adv->addServiceUUID(hid->hidService()->getUUID());
  adv->setScanResponse(true);
  adv->start();
  Serial.printf("[ble] advertising as \"%s\"\n", DEVICE_NAME);
}

// ---------------------------------------------------------------------------
// Mouse
// ---------------------------------------------------------------------------
static const uint32_t REPORT_GAP_MS = 15;  // roughly one Bluetooth connection interval
static uint8_t mouseButtons = 0;

#if ABSOLUTE_POINTER
// Absolute pointer: x, y in 0..ABS_MAX across the whole screen. One report puts it there.
static const int ABS_MAX = 32767;
static int curX = ABS_MAX / 2, curY = ABS_MAX / 2;

static void sendMouseAbs(uint8_t buttons, int x, int y, int8_t wheel) {
  if (!connected) return;
  curX = constrain(x, 0, ABS_MAX);
  curY = constrain(y, 0, ABS_MAX);
  uint8_t report[6] = {buttons, (uint8_t)(curX & 0xFF), (uint8_t)(curX >> 8),
                       (uint8_t)(curY & 0xFF), (uint8_t)(curY >> 8), (uint8_t)wheel};
  mouseInput->setValue(report, sizeof(report));
  mouseInput->notify();
  delay(REPORT_GAP_MS);
}

// Buttons and wheel at the current spot; dx, dy shift it (in 0..32767 units).
static void sendMouse(uint8_t buttons, int8_t dx, int8_t dy, int8_t wheel) {
  sendMouseAbs(buttons, curX + dx, curY + dy, wheel);
}

static void mouseMove(int dx, int dy, int step = 10) {
  sendMouseAbs(mouseButtons, curX + dx, curY + dy, 0);
}
#else
static void sendMouse(uint8_t buttons, int8_t dx, int8_t dy, int8_t wheel) {
  if (!connected) return;
  uint8_t report[4] = {buttons, (uint8_t)dx, (uint8_t)dy, (uint8_t)wheel};
  mouseInput->setValue(report, sizeof(report));
  mouseInput->notify();
  delay(REPORT_GAP_MS);
}

// Moves by any amount, split into steps of at most `step` counts.
static void mouseMove(int dx, int dy, int step = 10) {
  while (dx != 0 || dy != 0) {
    int sx = constrain(dx, -step, step);
    int sy = constrain(dy, -step, step);
    sendMouse(mouseButtons, sx, sy, 0);
    dx -= sx;
    dy -= sy;
  }
}
#endif

static void mouseClick() {
  sendMouse(0x01, 0, 0, 0);
  delay(50);
  sendMouse(0x00, 0, 0, 0);
}

static void mouseLongPress(uint32_t ms) {
  sendMouse(0x01, 0, 0, 0);
  delay(ms);
  sendMouse(0x00, 0, 0, 0);
}

// Clicks mouse button 1..8 (4 and up can be assigned to actions on the iPhone).
static void mouseButtonClick(int button) {
  sendMouse(1 << (button - 1), 0, 0, 0);
  delay(50);
  sendMouse(0x00, 0, 0, 0);
}

static void mouseScroll(int8_t amount) {
  sendMouse(mouseButtons, 0, 0, amount);
}

// Pushes the pointer far into the top-left corner so its position is known.
static void cornerReset() {
#if ABSOLUTE_POINTER
  sendMouseAbs(0, 0, 0, 0);
#else
  for (int i = 0; i < 40; i++) sendMouse(0, -127, -127, 0);
#endif
}

// ---------------------------------------------------------------------------
// Keyboard (US layout; set the iPhone's hardware keyboard layout to U.S.)
// ---------------------------------------------------------------------------
// Presses up to 6 keys together (plus modifiers and Fn), then releases them all.
static void sendKeys(uint8_t modifiers, bool fn, const uint8_t* codes, int count, uint32_t holdMs = 0) {
  if (!connected) return;
  uint8_t press[9]   = {modifiers, 0, 0, 0, 0, 0, 0, 0, (uint8_t)(fn ? 1 : 0)};
  uint8_t release[9] = {0};
  for (int i = 0; i < count && i < 6; i++) press[2 + i] = codes[i];
  keyboardInput->setValue(press, sizeof(press));
  keyboardInput->notify();
  delay(REPORT_GAP_MS + holdMs);
  keyboardInput->setValue(release, sizeof(release));
  keyboardInput->notify();
  delay(REPORT_GAP_MS);
}

static void sendKey(uint8_t modifiers, uint8_t keycode) {
  sendKeys(modifiers, false, &keycode, 1);
}

// Maps one ASCII character to a HID key code and modifier. Returns false if unsupported.
static bool asciiToKey(char c, uint8_t& mod, uint8_t& code) {
  mod = 0;
  if (c >= 'a' && c <= 'z') { code = 0x04 + (c - 'a'); return true; }
  if (c >= 'A' && c <= 'Z') { code = 0x04 + (c - 'A'); mod = MOD_LSHIFT; return true; }
  if (c >= '1' && c <= '9') { code = 0x1E + (c - '1'); return true; }
  if (c == '0') { code = 0x27; return true; }

  static const char* shiftedDigits = "!@#$%^&*()";
  const char* p = strchr(shiftedDigits, c);
  if (p && c) { code = 0x1E + (p - shiftedDigits); mod = MOD_LSHIFT; return true; }

  struct { char plain, shifted; uint8_t code; } symbols[] = {
    {'-', '_', 0x2D}, {'=', '+', 0x2E}, {'[', '{', 0x2F}, {']', '}', 0x30},
    {'\\', '|', 0x31}, {';', ':', 0x33}, {'\'', '"', 0x34}, {'`', '~', 0x35},
    {',', '<', 0x36}, {'.', '>', 0x37}, {'/', '?', 0x38},
  };
  for (auto& s : symbols) {
    if (c == s.plain)   { code = s.code; return true; }
    if (c == s.shifted) { code = s.code; mod = MOD_LSHIFT; return true; }
  }
  if (c == ' ')  { code = 0x2C; return true; }
  if (c == '\n') { code = 0x28; return true; }
  return false;
}

static void typeText(const char* text) {
  for (const char* c = text; *c; c++) {
    uint8_t mod, code;
    if (asciiToKey(*c, mod, code)) sendKey(mod, code);
    else Serial.printf("[kbd] skipped unsupported character 0x%02X\n", (uint8_t)*c);
  }
}

static void pasteCmdV()  { sendKey(MOD_LGUI, 0x19); }  // Command + V
static void homeCmdH()   { sendKey(MOD_LGUI, 0x0B); }  // Command + H (experimental on iPhone)

// HID key codes
static const uint8_t KEY_ENTER = 0x28, KEY_ESC = 0x29, KEY_BACKSPACE = 0x2A, KEY_TAB = 0x2B,
                     KEY_SPACE = 0x2C, KEY_RIGHT = 0x4F, KEY_LEFT = 0x50, KEY_DOWN = 0x51, KEY_UP = 0x52;

// Sends a combination written like "cmd+space", "fn+h", "tab+h" or "ctrl+alt+shift+h".
// Modifiers: cmd, ctrl, alt (opt), shift, fn (globe). Keys: a-z, 0-9, space, enter,
// tab, esc, backspace, up, down, left, right. Returns false if a part is unknown.
static bool sendCombo(String combo, uint32_t holdMs = 0) {
  combo.toLowerCase();
  combo += "+";
  uint8_t mods = 0, codes[6];
  int count = 0;
  bool fn = false;
  int start = 0;
  for (int plus = combo.indexOf('+'); plus >= 0; start = plus + 1, plus = combo.indexOf('+', start)) {
    String part = combo.substring(start, plus);
    part.trim();
    uint8_t code = 0, mod = 0;
    if      (part == "cmd" || part == "gui")   mods |= MOD_LGUI;
    else if (part == "ctrl")                   mods |= 0x01;
    else if (part == "shift")                  mods |= MOD_LSHIFT;
    else if (part == "alt" || part == "opt")   mods |= 0x04;
    else if (part == "fn" || part == "globe")  fn = true;
    else {
      if      (part == "space")                         code = KEY_SPACE;
      else if (part == "enter" || part == "return")     code = KEY_ENTER;
      else if (part == "tab")                           code = KEY_TAB;
      else if (part == "esc")                           code = KEY_ESC;
      else if (part == "backspace" || part == "bksp")   code = KEY_BACKSPACE;
      else if (part == "up")                            code = KEY_UP;
      else if (part == "down")                          code = KEY_DOWN;
      else if (part == "left")                          code = KEY_LEFT;
      else if (part == "right")                         code = KEY_RIGHT;
      else if (part.length() == 1 && asciiToKey(part.charAt(0), mod, code)) mods |= mod;
      else { Serial.printf("[kbd] unknown key \"%s\"\n", part.c_str()); return false; }
      if (count < 6) codes[count++] = code;
    }
  }
  sendKeys(mods, fn, codes, count, holdMs);
  return true;
}

// ---------------------------------------------------------------------------
// Special keys (Consumer page) and the Focus key
// ---------------------------------------------------------------------------
struct SpecialKey { const char* name; uint16_t usage; };
static const SpecialKey SPECIAL_KEYS[] = {
  {"home", 0x0040},       {"lock", 0x0030},     {"screenshot", 0x0065},
  {"brighter", 0x006F},   {"dimmer", 0x0070},   {"next", 0x00B5},
  {"previous", 0x00B6},   {"playpause", 0x00CD}, {"siri", 0x00CF},
  {"mute", 0x00E2},       {"louder", 0x00E9},   {"softer", 0x00EA},
  {"keyboard", 0x01AE},   {"globe", 0x029D},    {"spotlight", 0x0221},
};

static void sendConsumer(uint16_t usage, uint32_t holdMs = 40) {
  if (!connected || !consumerInput) return;
  uint8_t press[2] = {(uint8_t)(usage & 0xFF), (uint8_t)(usage >> 8)};
  uint8_t release[2] = {0, 0};
  consumerInput->setValue(press, sizeof(press));
  consumerInput->notify();
  delay(REPORT_GAP_MS + holdMs);
  consumerInput->setValue(release, sizeof(release));
  consumerInput->notify();
  delay(REPORT_GAP_MS);
}

static void sendFocusKey() {
  if (!connected || !systemInput) return;
  uint8_t press = 0x01, release = 0x00;
  systemInput->setValue(&press, 1);
  systemInput->notify();
  delay(REPORT_GAP_MS + 40);
  systemInput->setValue(&release, 1);
  systemInput->notify();
  delay(REPORT_GAP_MS);
}

// "key <name> [times]" or "key 0x00e9 [times]". Returns false if the name is unknown.
static bool pressSpecialKey(String args) {
  args.trim();
  args.toLowerCase();
  int times = 1;
  int sp = args.indexOf(' ');
  if (sp > 0) { times = constrain(args.substring(sp + 1).toInt(), 1, 20); args = args.substring(0, sp); }
  for (int i = 0; i < times; i++) {
    if (args == "focus") { sendFocusKey(); }
    else if (args.startsWith("0x")) { sendConsumer((uint16_t)strtol(args.c_str() + 2, nullptr, 16)); }
    else {
      bool found = false;
      for (auto& k : SPECIAL_KEYS) if (args == k.name) { sendConsumer(k.usage); found = true; break; }
      if (!found) return false;
    }
    if (times > 1) delay(60);
  }
  return true;
}

// ---------------------------------------------------------------------------
// Actions used by the app
// ---------------------------------------------------------------------------
// Opens the Mantiza app through Search and asks it to start screen sharing (the app shows
// Apple's picker and has the device press "Share Entire Screen").
static void openAppAndShare() {
  sendCombo("cmd+space");
  delay(800);                 // wait for Search to open
  typeText("Mantiza");
  delay(700);                 // wait for results
  sendKey(0, KEY_ENTER);
  delay(1500);                // wait for the app to come to the front
  sendEvent("share");
}

// Moves the pointer to a spot. Absolute build: x, y in 0..32767, one report.
// Relative build (fallback): counted from the top-left corner, across then down in equal steps
// of GO_STEP counts (iOS speeds up bigger and diagonal steps, so only equal straight steps
// give a predictable distance).
static const int GO_STEP = 5;
static void goTo(int x, int y) {
#if ABSOLUTE_POINTER
  sendMouseAbs(mouseButtons, x, y, 0);
#else
  cornerReset();
  delay(100);
  x = (x + GO_STEP / 2) / GO_STEP * GO_STEP;
  y = (y + GO_STEP / 2) / GO_STEP * GO_STEP;
  mouseMove(x, 0, GO_STEP);
  mouseMove(0, y, GO_STEP);
#endif
}

// Drag (like a finger swipe): press at x1,y1, slide to x2,y2, let go. Absolute units (0..32767).
// Used for system gestures, e.g. down from the top-right corner opens Control Centre.
static void dragTo(int x1, int y1, int x2, int y2, int steps = 14) {
#if ABSOLUTE_POINTER
  sendMouseAbs(0, x1, y1, 0);
  delay(60);
  sendMouseAbs(0x01, x1, y1, 0);
  delay(80);
  for (int i = 1; i <= steps; i++)
    sendMouseAbs(0x01, x1 + (x2 - x1) * i / steps, y1 + (y2 - y1) * i / steps, 0);
  delay(60);
  sendMouseAbs(0, x2, y2, 0);
#endif
}

// ---------------------------------------------------------------------------
// Screen (135 x 240, portrait) in Mantiza's pixel look (images/, same as the app):
// the pixel mantis head, the MANTIZA wordmark, two lights (iPhone, app), battery, and what Mantiza
// is doing. The app sends "status <text>" at every step. The head moves a little: the eyes blink
// now and then, a scan line runs through it while a task runs, and it is dim while no iPhone is
// connected. Drawn into an off-screen canvas first, so nothing flickers.
// The screen turns off after a minute without news and wakes on a button or a new status.
// ---------------------------------------------------------------------------
static String statusText = "Ready";
static bool   taskRunning = false;   // the app said a task is running: front button = Stop
static uint32_t screenOnUntil = 0;
static bool   screenOn = true;
static const uint32_t SCREEN_ON_MS = 60000;

static void wakeScreen() { screenOnUntil = millis() + SCREEN_ON_MS; }

// Mantiza's colours (apps/mantiza/Sources/MantizaKit/Theme.swift), as RGB565.
static constexpr uint16_t rgb(uint8_t r, uint8_t g, uint8_t b) {
  return ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3);
}
static const uint16_t M_INK     = rgb(0x0D, 0x0A, 0x12);
static const uint16_t M_LINE    = rgb(0x2A, 0x23, 0x33);
static const uint16_t M_TEXT    = rgb(0xEE, 0xEA, 0xF4);
static const uint16_t M_DIM     = rgb(0x8A, 0x83, 0x94);
static const uint16_t M_MAGENTA = rgb(0xD7, 0x01, 0xA5);
static const uint16_t M_GREEN   = rgb(0x02, 0xF3, 0x4C);
static const uint16_t M_MAGENTA_DIM = rgb(0x45, 0x08, 0x37);
static const uint16_t M_GREEN_DIM   = rgb(0x0A, 0x4A, 0x20);

// The pixel art from images/o1-gridded.svg and images/o6-lockup.svg (M magenta, G green).
static const char* HEAD[] = {
  "G..........G",
  ".G........G.",
  "..G......G..",
  "MMMMMMMMMMMM",
  "MGGMMMMMMGGM",
  "MGGMMMMMMGGM",
  ".MMMMMMMMMM.",
  "..MMMMMMMM..",
  "...MMMMMM...",
  "....MMMM....",
  ".....MM.....",
};
static const char* WORDMARK[] = {  // M A N T I Z A, 5 x 7 letters, the Z green
  "M...M..MMM..M...M.MMMMM..MMM..GGGGG..MMM.",
  "MM.MM.M...M.MM..M...M.....M.......G.M...M",
  "M.M.M.M...M.M.M.M...M.....M......G..M...M",
  "M.M.M.MMMMM.M..MM...M.....M.....G...MMMMM",
  "M...M.M...M.M...M...M.....M....G....M...M",
  "M...M.M...M.M...M...M.....M...G.....M...M",
  "M...M.M...M.M...M...M....MMM..GGGGG.M...M",
};

static M5Canvas canvas(&M5.Display);
static uint32_t lastBlink = 0;

// One grid of square pixels. scanRow: that row is drawn bright (-1 = none); eyesShut: green
// cells in rows 4-5 (the eyes) are drawn magenta.
static void drawGrid(const char* const* rows, int nRows, int x, int y, int cell, int gap,
                     bool dim, int scanRow = -1, bool eyesShut = false) {
  for (int r = 0; r < nRows; r++) {
    for (int c = 0; rows[r][c]; c++) {
      char ch = rows[r][c];
      if (ch == '.') continue;
      bool green = ch == 'G' && !(eyesShut && (r == 4 || r == 5));
      uint16_t col = green ? (dim ? M_GREEN_DIM : M_GREEN) : (dim ? M_MAGENTA_DIM : M_MAGENTA);
      if (r == scanRow) col = green ? M_TEXT : rgb(0xFF, 0x6A, 0xD8);
      canvas.fillRect(x + c * cell, y + r * cell, cell - gap, cell - gap, col);
    }
  }
}

// "■ IPHONE ............ LINKED"
static void drawLight(int y, const char* name, bool on, const char* onText, const char* offText) {
  canvas.fillRect(6, y, 6, 6, on ? M_GREEN : M_MAGENTA);
  canvas.setTextColor(M_DIM);
  canvas.setTextDatum(top_left);
  canvas.drawString(name, 18, y - 1);
  canvas.setTextColor(on ? M_GREEN : M_DIM);
  canvas.setTextDatum(top_right);
  canvas.drawString(on ? onText : offText, 129, y - 1);
}

static void drawScreen() {
  uint32_t now = millis();
  canvas.fillScreen(M_INK);
  canvas.setTextFont(1);   // the built-in 6 x 8 pixel font
  canvas.setTextSize(1);

  // Battery, top right
  canvas.setTextColor(M_DIM);
  canvas.setTextDatum(top_right);
  canvas.drawString(String((int)M5.Power.getBatteryLevel()) + "%", 129, 4);

  // The head: dim without an iPhone, a scan line while working, a blink every few seconds
  int scan = taskRunning ? (int)((now / 90) % 14) - 1 : -1;      // rows -1..12, a short pause off the head
  bool blink = !taskRunning && connected && now - lastBlink < 140;
  drawGrid(HEAD, 11, 25, 16, 7, 1, !connected, scan, blink);
  drawGrid(WORDMARK, 7, 6, 102, 3, 0, !connected);

  canvas.drawFastHLine(6, 132, 123, M_LINE);
  drawLight(140, "IPHONE", connected, "LINKED", "WAITING");
  drawLight(154, "APP", appLinked, "READY", "NOT OPEN");
  canvas.drawFastHLine(6, 166, 123, M_LINE);

  // What Mantiza is doing, wrapped at 20 characters
  canvas.setTextDatum(top_left);
  canvas.setTextColor(M_TEXT);
  int y = 174, last = taskRunning ? 206 : 228;
  String rest = statusText;
  bool first = true;
  while (rest.length() > 0 && y <= last) {
    int cut = rest.length() <= 20 ? rest.length() : rest.lastIndexOf(' ', 20);
    if (cut <= 0) cut = min((int)rest.length(), 20);
    canvas.drawString((first ? "> " : "  ") + rest.substring(0, cut), 6, y);
    rest = rest.substring(cut);
    rest.trim();
    first = false;
    y += 11;
  }

  if (taskRunning) {   // the front button stops the task
    canvas.fillRect(0, 218, 135, 22, M_MAGENTA);
    canvas.setTextColor(M_INK);
    canvas.setTextDatum(middle_center);
    canvas.drawString("FRONT BUTTON = STOP", 67, 229);
  }
  canvas.pushSprite(0, 0);
}

// Redraw for the head's movement: ~11 frames a second while a task runs, a blink every 4.5 s
// when idle; nothing while the screen is off.
static bool animationDue() {
  if (!screenOn) return false;
  static uint32_t lastFrame = 0;
  uint32_t now = millis();
  if (taskRunning && now - lastFrame >= 90) { lastFrame = now; return true; }
  if (!taskRunning && connected) {
    if (now - lastBlink >= 4500) { lastBlink = now; return true; }        // shut the eyes
    if (now - lastBlink >= 140 && lastFrame < lastBlink + 140) { lastFrame = now; return true; }  // open them
  }
  return false;
}

// ---------------------------------------------------------------------------
// Serial commands
// ---------------------------------------------------------------------------
static void printHelp() {
  Serial.println(
    "Commands:\n"
    "  m <dx> <dy>        move pointer (any size)\n"
    "  s <dx> <dy> <n>    send one raw step <n> times (dx, dy in -127..127)\n"
    "  r                  corner reset (top-left)\n"
    "  c                  click\n"
    "  l <ms>             long press\n"
    "  w <n>              scroll wheel (negative = down)\n"
    "  t <text>           type text\n"
    "  p                  paste (Command+V)\n"
    "  h                  Command+H (home?)\n"
    "  k <combo>          key combination, e.g. k cmd+space, k enter, k tab+h, k fn+c\n"
    "  K <ms> <combo>     same, but hold the keys for <ms> first\n"
    "  b <1-8>            click mouse button 1..8\n"
    "  go <x> <y>         pointer to x,y (absolute build: 0..32767 across the screen;\n"
    "                     relative build: counts from the top-left corner)\n"
    "  tap <x> <y>        same, then click\n"
    "  drag <x1> <y1> <x2> <y2>  press, slide, let go (absolute build; 0..32767)\n"
    "  share              open the Mantiza app and ask it to share the screen\n"
    "  key <name> [n]     special key: home lock screenshot brighter dimmer louder softer mute\n"
    "                     playpause next previous siri spotlight globe keyboard focus, or 0x....\n"
    "  status <text>      show what Mantiza is doing (no reply)\n"
    "  task on|off        a task is running: front button = Stop (no reply)\n"
    "  help               this list\n"
    "From the app only: ping <n> (-> pong <n>), hello (-> hi ...)");
}

// Answers to the serial port, and also to the app if the command came from it.
static void reply(const String& text, bool fromApp) {
  Serial.println(text);
  if (fromApp) sendEvent(text);
}

static bool wordIs(const String& line, const char* word) {
  size_t n = strlen(word);
  return line.startsWith(word) && (line.length() == n || line.charAt(n) == ' ');
}

static void handleCommand(String line, bool fromApp = false) {
  line.trim();
  if (line.isEmpty()) return;
  if (fromApp) Serial.printf("[t2] <- app: %s\n", line.c_str());

  // Words first ("ping" would otherwise be read as "p" = paste, "hello" as "h" = home).
  long num = line.indexOf(' ') > 0 ? line.substring(line.indexOf(' ') + 1).toInt() : 0;
  if (wordIs(line, "ping"))  { sendEvent("pong " + String(num)); return; }
  // "status" and "task" get no reply: the app sends them without waiting, and an extra reply
  // would be taken as the answer to the next command.
  if (wordIs(line, "status")) { statusText = line.length() > 7 ? line.substring(7) : ""; wakeScreen(); return; }
  if (wordIs(line, "task"))   { taskRunning = line.endsWith("on"); wakeScreen(); return; }
  if (wordIs(line, "hello")) { sendEvent("hi " + String(DEVICE_NAME) + " battery " + String((int)M5.Power.getBatteryLevel()) + "% abs " + String(ABSOLUTE_POINTER)); return; }
  int gx = 0, gy = 0;                  // go / tap at a spot
  bool isGo = wordIs(line, "go"), isTap = wordIs(line, "tap");
  if ((isGo || isTap) && !connected) { reply("not connected to the iPhone yet", fromApp); return; }
  if ((isGo || isTap) && sscanf(line.c_str() + (isGo ? 2 : 3), "%d %d", &gx, &gy) == 2) {
    goTo(gx, gy);
    if (isTap) { delay(ABSOLUTE_POINTER ? 40 : 150); mouseClick(); }
    reply("ok " + line, fromApp);
    return;
  }
  int d1 = 0, d2 = 0, d3 = 0, d4 = 0;  // drag x1 y1 x2 y2 (absolute units)
  if (wordIs(line, "drag")) {
    if (!connected) { reply("not connected to the iPhone yet", fromApp); return; }
    if (!ABSOLUTE_POINTER || sscanf(line.c_str() + 4, "%d %d %d %d", &d1, &d2, &d3, &d4) != 4) {
      reply("error " + line, fromApp);
      return;
    }
    dragTo(d1, d2, d3, d4);
    reply("ok " + line, fromApp);
    return;
  }
  if (wordIs(line, "key")) {
    if (!connected) { reply("not connected to the iPhone yet", fromApp); return; }
    if (!pressSpecialKey(line.substring(3))) { reply("error " + line, fromApp); return; }
    reply("ok " + line, fromApp);
    return;
  }
  if (wordIs(line, "share")) { if (connected) openAppAndShare(); reply("ok share", fromApp); return; }

  if (!connected && line != "help") {
    reply("not connected to the iPhone yet", fromApp);
    return;
  }
  char cmd = line.charAt(0);
  String args = line.length() > 2 ? line.substring(2) : "";
  int a = 0, b = 0, n = 0;

  if (line == "help")                 printHelp();
  else if (cmd == 'm' && sscanf(args.c_str(), "%d %d", &a, &b) == 2) mouseMove(a, b);
  else if (cmd == 's' && sscanf(args.c_str(), "%d %d %d", &a, &b, &n) == 3) {
    for (int i = 0; i < n; i++) sendMouse(mouseButtons, constrain(a, -127, 127), constrain(b, -127, 127), 0);
  }
  else if (cmd == 'r')                cornerReset();
  else if (cmd == 'c')                mouseClick();
  else if (cmd == 'l' && sscanf(args.c_str(), "%d", &a) == 1) mouseLongPress(a);
  else if (cmd == 'w' && sscanf(args.c_str(), "%d", &a) == 1) mouseScroll(constrain(a, -127, 127));
  else if (cmd == 't')                typeText(args.c_str());
  else if (cmd == 'p')                pasteCmdV();
  else if (cmd == 'h')                homeCmdH();
  else if (cmd == 'k' && !args.isEmpty()) { if (!sendCombo(args)) { reply("error " + line, fromApp); return; } }
  else if (cmd == 'K' && sscanf(args.c_str(), "%d", &a) == 1 && args.indexOf(' ') > 0) {
    if (!sendCombo(args.substring(args.indexOf(' ') + 1), a)) { reply("error " + line, fromApp); return; }
  }
  else if (cmd == 'b' && sscanf(args.c_str(), "%d", &a) == 1 && a >= 1 && a <= 8) mouseButtonClick(a);
  else { reply("unknown command: " + line, fromApp); return; }

  reply("ok " + line, fromApp);
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
void setup() {
  auto cfg = M5.config();
  M5.begin(cfg);
  Serial.begin(115200);
  M5.Display.setRotation(0);
  M5.Display.setBrightness(80);
  canvas.setColorDepth(16);
  canvas.setPsram(true);
  canvas.createSprite(M5.Display.width(), M5.Display.height());

  appQueue = xQueueCreate(16, sizeof(AppCommand));
  setupBluetooth();
  drawScreen();
  wakeScreen();
  Serial.println("Mantiza ready. Type: help");
}

void loop() {
  M5.update();
  static bool wasConnected = false, wasLinked = false;
  bool redraw = (connected != wasConnected) || (appLinked != wasLinked);
  wasConnected = connected;
  wasLinked = appLinked;

  AppCommand appCmd;                   // commands from the app
  while (xQueueReceive(appQueue, &appCmd, 0) == pdTRUE) {
    handleCommand(String(appCmd.text), true);
    redraw = true;
  }

  // Front button: Stop while a task runs (the app stops at once). Any button wakes the screen;
  // a press on a dark screen only wakes it.
  bool front = M5.BtnA.wasPressed();
  bool side  = M5.BtnB.wasPressed();
  if (front || side) {
    bool wasDark = !screenOn;
    wakeScreen();
    if (front && !wasDark && taskRunning) {
      sendEvent("stop");
      statusText = "Stopping...";
    }
    redraw = true;
  }
  bool shouldBeOn = millis() < screenOnUntil;
  if (shouldBeOn != screenOn) {
    screenOn = shouldBeOn;
    M5.Display.setBrightness(screenOn ? 80 : 0);
    redraw = true;
  }

  static String line;
  while (Serial.available()) {
    char ch = Serial.read();
    if (ch == '\n' || ch == '\r') {
      if (!line.isEmpty()) { handleCommand(line); redraw = true; }
      line = "";
    } else {
      line += ch;
    }
  }

  static uint32_t lastBattery = 0;
  if (millis() - lastBattery > 30000) {
    lastBattery = millis();
    if (hid) hid->setBatteryLevel(M5.Power.getBatteryLevel());
    redraw = true;
  }

  if (animationDue()) redraw = true;
  if (redraw) drawScreen();
  delay(10);
}
