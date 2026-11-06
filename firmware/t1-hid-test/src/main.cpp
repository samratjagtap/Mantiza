// Mantiza Phase 0, tests T1, T1b and T2
// StickS3 acts as a Bluetooth LE mouse + keyboard for an iPhone (AssistiveTouch pointer).
// T1b adds key combinations (Command+Space, Return, Tab, arrows), an experimental
// Fn/Globe key and mouse buttons 4..8.
// T2 adds a private "command channel" service: the Mantiza test app writes the same
// text commands as the serial port ("m 100 0", "t hello", "ping 3") and the device
// answers with notifications ("pong 3", "ask 5", "ok ...").
//
// Buttons:  KEY2 (side)  = select next test
//           KEY1 (front) = run the selected test
// Serial:   USB at 115200 baud, type "help" for commands.

#include <M5Unified.h>
#include <NimBLEDevice.h>
#include <NimBLEHIDDevice.h>
#include <Preferences.h>

static const char* DEVICE_NAME = "Mantiza T2";

// T2 command channel (must match the app, apps/phase0-test)
static const char* COMMAND_SERVICE_UUID = "f665cd1c-b15f-4ffa-b950-9d0f007b7db5";
static const char* COMMAND_WRITE_UUID   = "2af74626-d331-4239-bd47-2ef715cab51e";  // app -> device
static const char* COMMAND_EVENT_UUID   = "7a537076-9f59-4e6d-94eb-c90356cea6f3";  // device -> app (notify)

// ---------------------------------------------------------------------------
// HID report map: keyboard (report 1) + relative mouse (report 2)
// ---------------------------------------------------------------------------
static const uint8_t REPORT_ID_KEYBOARD = 1;
static const uint8_t REPORT_ID_MOUSE    = 2;

// Bump this whenever REPORT_MAP or the list of services changes. The iPhone caches
// both for a paired device, so a change needs a fresh pairing: old bonds are cleared on boot.
// 3 = T2 command channel added.
static const uint32_t REPORT_MAP_VERSION = 3;

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
  0x05, 0x01, 0x09, 0x30, 0x09, 0x31, 0x09, 0x38,  // X, Y, Wheel
  0x15, 0x81, 0x25, 0x7F,
  0x75, 0x08, 0x95, 0x03,
  0x81, 0x06,       //     Input (Data, Var, Rel)
  0xC0,             //   End Collection
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
static volatile bool         connected     = false;

// T2: commands written by the app arrive on the Bluetooth task; they are queued
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
  for (int i = 0; i < 40; i++) sendMouse(0, -127, -127, 0);
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

// HID key codes used by the T1b tests
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
// Tests (selected with KEY2, run with KEY1)
// ---------------------------------------------------------------------------
static const char* TYPE_TEST_TEXT = "Hello Mantiza! ABC xyz 123 @#?";

struct Test { const char* name; void (*run)(); };

static void testCorner()  { cornerReset(); }
static void testSquare()  { mouseMove(200, 0); mouseMove(0, 200); mouseMove(-200, 0); mouseMove(0, -200); }
static void testClick()   { mouseClick(); }
static void testLong()    { mouseLongPress(1000); }
static void testScroll()  { for (int i = 0; i < 5; i++) mouseScroll(-1); }
static void testType()    { typeText(TYPE_TEST_TEXT); }
static void testPaste()   { pasteCmdV(); }
static void testHome()    { homeCmdH(); }

// T1b: open an app through Search without touching its icon.
static void testSearch() {
  sendCombo("cmd+space");
  delay(700);                 // wait for Search to open
  typeText("Notes");
  delay(500);                 // wait for results
  sendKey(0, KEY_ENTER);
}
static void testReturn()  { typeText("Mantiza T1b test"); sendKey(0, KEY_ENTER); }
static void testTab()     { sendKey(0, KEY_TAB); }
static void testFnH()     { sendCombo("fn+h"); }
static void testFnC()     { sendCombo("fn+c"); }
static void testFnN()     { sendCombo("fn+n"); }
static void testFnUp()    { sendCombo("fn+up"); }
static void testButton4() { mouseButtonClick(4); }
static void testButton5() { mouseButtonClick(5); }

// T2: the device asks the app ("ask N") and counts the app's answers ("ack N").
// This shows whether the app answers while it is in the background.
static uint32_t askSent = 0, askAnswered = 0, askSentAt = 0, lastAskMs = 0;
static uint32_t beatsReceived = 0, lastBeatAt = 0;
static bool     autoAsk = false;
static const uint32_t AUTO_ASK_EVERY_MS = 5000;

static void sendAsk() {
  askSent++;
  askSentAt = millis();
  sendEvent("ask " + String(askSent));
}
static void resetT2Counts() { askSent = askAnswered = lastAskMs = beatsReceived = 0; }
static void testAsk()     { sendAsk(); }
static void testAutoAsk() {
  autoAsk = !autoAsk;
  resetT2Counts();
  Serial.printf("[t2] auto ask %s\n", autoAsk ? "ON" : "OFF");
}

// T4d: the device starts screen sharing with no touch on the phone. It opens the
// test app through Search and tells it to share; the app shows the picker and has
// the device click the picker's share button ("tap x y").
static void testShare() {
  sendCombo("cmd+space");
  delay(800);                 // wait for Search to open
  typeText("Mantiza Test");
  delay(700);                 // wait for results
  sendKey(0, KEY_ENTER);
  delay(1500);                // wait for the app to come to the front
  sendEvent("share");
}

// Moves the pointer to a spot counted from the top-left corner.
// Moves across first, then down, always in equal steps of GO_STEP counts: iOS speeds up
// bigger and diagonal steps more, so only equal straight steps give a distance that is
// the same for every step. The spot is rounded to a multiple of GO_STEP.
static const int GO_STEP = 5;
static void goTo(int x, int y) {
  cornerReset();
  delay(100);
  x = (x + GO_STEP / 2) / GO_STEP * GO_STEP;
  y = (y + GO_STEP / 2) / GO_STEP * GO_STEP;
  mouseMove(x, 0, GO_STEP);
  mouseMove(0, y, GO_STEP);
}

// T9: battery. The screen goes off (like the real device most of the time) and the
// device sends "batt <percent> <millivolts> <minutes> <charging>" to the app every minute.
// Any button turns the screen on for 10 s; the first press only wakes it.
static bool     battTest = false;
static uint32_t battStartAt = 0, lastBattAt = 0, screenOnUntil = 0;
static int      battStartPct = 0;
static const uint32_t BATT_EVERY_MS = 60000, SCREEN_ON_MS = 10000;

static void sendBatt() {
  int pct = M5.Power.getBatteryLevel();
  int mv  = M5.Power.getBatteryVoltage();
  bool charging = M5.Power.isCharging() == m5::Power_Class::is_charging;
  uint32_t minutes = (millis() - battStartAt) / 60000;
  sendEvent("batt " + String(pct) + " " + String(mv) + " " + String(minutes) + " " + String(charging ? 1 : 0));
  Serial.printf("[t9] %u min: %d%% %d mV%s\n", minutes, pct, mv, charging ? " CHARGING" : "");
}
static void testBattery() {
  battTest = !battTest;
  if (battTest) {
    battStartAt = lastBattAt = millis();
    battStartPct = M5.Power.getBatteryLevel();
    screenOnUntil = millis() + SCREEN_ON_MS;
    sendBatt();
  } else {
    M5.Display.setBrightness(80);
  }
  Serial.printf("[t9] battery test %s\n", battTest ? "ON" : "OFF");
}

static const Test TESTS[] = {
  {"9 Battery test",   testBattery},
  {"4 Share screen",   testShare},
  {"2 Ask app once",   testAsk},
  {"2 Auto ask 5s",    testAutoAsk},
  {"b Search Notes",   testSearch},
  {"b Type+Return",    testReturn},
  {"b Tab (FKA)",      testTab},
  {"b Fn+H Home",      testFnH},
  {"b Fn+C Control",   testFnC},
  {"b Fn+N Notific.",  testFnN},
  {"b Fn+Up Switcher", testFnUp},
  {"b Button 4",       testButton4},
  {"b Button 5",       testButton5},
  {"Corner reset", testCorner},
  {"Square 200",   testSquare},
  {"Click",        testClick},
  {"Long press",   testLong},
  {"Scroll",       testScroll},
  {"Type text",    testType},
  {"Paste Cmd+V",  testPaste},
  {"Home Cmd+H?",  testHome},
};
static const int TEST_COUNT = sizeof(TESTS) / sizeof(TESTS[0]);
static int selectedTest = 0;
static String lastAction = "-";

// ---------------------------------------------------------------------------
// Screen (135 x 240, portrait)
// ---------------------------------------------------------------------------
static void drawScreen() {
  auto& d = M5.Display;
  d.startWrite();
  d.fillScreen(TFT_BLACK);
  d.setTextSize(1);

  d.setTextColor(TFT_CYAN, TFT_BLACK);
  d.setCursor(4, 4);
  d.print("Mantiza T2");
  d.setCursor(78, 4);
  d.setTextColor(appLinked ? TFT_GREEN : TFT_DARKGREY, TFT_BLACK);
  d.print(appLinked ? "App:on" : "App:--");

  d.setCursor(4, 18);
  d.setTextColor(connected ? TFT_GREEN : TFT_ORANGE, TFT_BLACK);
  d.print(connected ? "Connected" : "Waiting...");
  d.setTextColor(TFT_WHITE, TFT_BLACK);
  d.setCursor(90, 18);
  d.printf("%d%%", (int)M5.Power.getBatteryLevel());

  // The list is longer than the screen: show a window that follows the selection.
  static const int VISIBLE = 9;
  static int top = 0;
  if (selectedTest < top) top = selectedTest;
  if (selectedTest >= top + VISIBLE) top = selectedTest - VISIBLE + 1;
  for (int i = top; i < TEST_COUNT && i < top + VISIBLE; i++) {
    int y = 38 + (i - top) * 17;
    bool sel = (i == selectedTest);
    if (sel) d.fillRect(0, y - 3, 135, 16, TFT_DARKGREY);
    d.setTextColor(TFT_WHITE, sel ? TFT_DARKGREY : TFT_BLACK);
    d.setCursor(4, y);
    d.printf("%s %s", sel ? ">" : " ", TESTS[i].name);
  }

  // T2 counters: A = asks answered / sent, last answer time; B = app heartbeats
  // T9 instead while the battery test runs: start % -> now %, minutes
  d.setTextColor(autoAsk || battTest ? TFT_GREEN : TFT_YELLOW, TFT_BLACK);
  d.setCursor(4, 200);
  if (battTest) d.printf("T9 %d%%>%d%% %umin", battStartPct, (int)M5.Power.getBatteryLevel(), (millis() - battStartAt) / 60000);
  else d.printf("A%u/%u %ums B%u", askAnswered, askSent, lastAskMs, beatsReceived);
  d.setTextColor(TFT_YELLOW, TFT_BLACK);
  d.setCursor(4, 212);
  d.print(lastAction.substring(0, 21));
  d.setTextColor(TFT_LIGHTGREY, TFT_BLACK);
  d.setCursor(4, 226);
  d.print("Side=next Front=run");
  d.endWrite();
}

static void runTest(int index) {
  if (!connected) {
    lastAction = "Not connected";
    return;
  }
  Serial.printf("[test] %s\n", TESTS[index].name);
  uint32_t start = millis();
  TESTS[index].run();
  lastAction = String(TESTS[index].name) + " " + String(millis() - start) + "ms";
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
    "  ask                T2: ask the app once (app answers \"ack N\")\n"
    "  go <x> <y>         T4d: pointer to x,y counted from the top-left corner\n"
    "  tap <x> <y>        T4d: same, then click\n"
    "  share              T4d: open Mantiza Test and ask it to share the screen\n"
    "  help               this list\n"
    "From the app only: ping <n> (-> pong <n>), ack <n>, beat <n>, hello");
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

  // T2 words first ("ping" would otherwise be read as "p" = paste, "hello" as "h" = home).
  long num = line.indexOf(' ') > 0 ? line.substring(line.indexOf(' ') + 1).toInt() : 0;
  if (wordIs(line, "ping"))  { sendEvent("pong " + String(num)); return; }
  if (wordIs(line, "hello")) { sendEvent("hi " + String(DEVICE_NAME) + " battery " + String((int)M5.Power.getBatteryLevel()) + "%"); return; }
  if (wordIs(line, "ack")) {
    askAnswered++;
    if ((uint32_t)num == askSent) lastAskMs = millis() - askSentAt;
    lastAction = "app ack " + String(num) + " " + String(lastAskMs) + "ms";
    return;
  }
  if (wordIs(line, "beat")) {
    beatsReceived++;
    lastBeatAt = millis();
    lastAction = "app beat " + String(num);
    return;
  }
  if (wordIs(line, "ask")) { sendAsk(); reply("ok", fromApp); return; }
  if (wordIs(line, "shared")) {        // T4d: the app reports the result of "share"
    lastAction = line.substring(0, 21);
    Serial.printf("[t4d] %s\n", line.c_str());
    return;
  }

  int gx = 0, gy = 0;                  // T4d: go / tap at a spot from the top-left corner
  bool isGo = wordIs(line, "go"), isTap = wordIs(line, "tap");
  if ((isGo || isTap) && !connected) { reply("not connected to the iPhone yet", fromApp); return; }
  if ((isGo || isTap) && sscanf(line.c_str() + (isGo ? 2 : 3), "%d %d", &gx, &gy) == 2) {
    goTo(gx, gy);
    if (isTap) { delay(150); mouseClick(); }
    lastAction = line.substring(0, 21);
    reply("ok " + line, fromApp);
    return;
  }
  if (wordIs(line, "share")) { if (connected) testShare(); reply("ok share", fromApp); return; }

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

  lastAction = (fromApp ? "app: " : "") + line.substring(0, fromApp ? 16 : 21);
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

  appQueue = xQueueCreate(16, sizeof(AppCommand));
  setupBluetooth();
  drawScreen();
  Serial.println("Mantiza T2 ready. Type: help");
}

void loop() {
  M5.update();
  static bool wasConnected = false, wasLinked = false;
  bool redraw = (connected != wasConnected) || (appLinked != wasLinked);
  wasConnected = connected;
  wasLinked = appLinked;

  AppCommand appCmd;                   // T2: commands from the app
  while (xQueueReceive(appQueue, &appCmd, 0) == pdTRUE) {
    handleCommand(String(appCmd.text), true);
    redraw = true;
  }

  static uint32_t lastAutoAsk = 0;     // T2: ask the app every 5 s
  if (autoAsk && connected && millis() - lastAutoAsk >= AUTO_ASK_EVERY_MS) {
    lastAutoAsk = millis();
    sendAsk();
    redraw = true;
  }

  bool keyNext = M5.BtnB.wasPressed();  // KEY2 (side): next test
  bool keyRun  = M5.BtnA.wasPressed();  // KEY1 (front): run test

  if (battTest) {                      // T9: report every minute, screen off when idle
    if (millis() - lastBattAt >= BATT_EVERY_MS) {
      lastBattAt = millis();
      sendBatt();
      redraw = true;
    }
    static bool screenOn = true;
    bool wake = keyNext || keyRun;
    if (wake && !screenOn) keyNext = keyRun = false;  // first press only wakes the screen
    if (wake) screenOnUntil = millis() + SCREEN_ON_MS;
    bool shouldBeOn = millis() < screenOnUntil;
    if (shouldBeOn != screenOn) {
      screenOn = shouldBeOn;
      M5.Display.setBrightness(screenOn ? 80 : 0);
      redraw = true;
    }
  }

  if (keyNext) {
    selectedTest = (selectedTest + 1) % TEST_COUNT;
    redraw = true;
  }
  if (keyRun) {
    runTest(selectedTest);
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

  if (redraw) drawScreen();
  delay(10);
}
