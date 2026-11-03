#include "ui.h"
#include <M5Unified.h>
#include <esp_task_wdt.h>
#include "audio.h"
#include "ble_link.h"

const uint32_t SCREEN_OFF_MS = 15000;   // idle screen only
const uint32_t PAIRING_WINDOW_MS = 120000;
const uint32_t TALK_HOLD_MS = 300;      // A held this long starts push-to-talk
const uint32_t PAIR_HOLD_MS = 3000;     // A and B held together this long open pairing
const size_t EVENT_LEN = 24;
const float SHAKE_G = 2.2f;             // acceleration magnitude that counts as a shake peak
const int SHAKE_PEAKS = 3;              // peaks within SHAKE_WINDOW_MS
const uint32_t SHAKE_WINDOW_MS = 800;

static SemaphoreHandle_t lock;
static QueueHandle_t events;
static String deviceName, screenText, nextText;
static UiState state = UI_IDLE;
static int progStep, progTotal;
static volatile bool dirty = true, stopLatched;
static volatile uint32_t stopCount;
static volatile int askAnswer = -1;  // -1 waiting, 0 no, 1 yes
// Non-blocking prompt (ui_prompt): the answer goes out as an event, the app can withdraw it.
static volatile bool prompting;
static volatile uint32_t promptDeadline;
static UiState promptBefore = UI_IDLE;
static volatile int battery = -1;
static volatile bool charging;
static uint32_t lastActivity;
static bool screenOn = true;

static void pushEvent(const char *e) {
  char buf[EVENT_LEN] = {0};
  strncpy(buf, e, sizeof buf - 1);
  xQueueSend(events, buf, 0);
}

static void beep(int freq, int ms) {
  if (M5.Speaker.isEnabled()) M5.Speaker.tone(freq, ms);
}

static void requestStop() {
  stopLatched = true;
  stopCount++;
  askAnswer = 0;
  pushEvent("stop");
  beep(400, 300);
}

void ui_event(const char *e) { pushEvent(e); }

static uint16_t headerColor(UiState s) {
  switch (s) {
    case UI_RUN: return TFT_BLUE;
    case UI_ASK: return TFT_ORANGE;
    case UI_DONE: return TFT_DARKGREEN;
    case UI_ERROR: return TFT_RED;
    default: return TFT_DARKGREY;
  }
}

static void draw() {
  xSemaphoreTake(lock, portMAX_DELAY);
  UiState s = state;
  String text = screenText, next = nextText;
  bool listening = audio_recording();
  int step = progStep, total = progTotal;
  xSemaphoreGive(lock);

  auto &d = M5.Display;
  d.startWrite();
  d.fillScreen(TFT_BLACK);
  uint16_t header = listening ? TFT_PURPLE : headerColor(s);
  d.fillRect(0, 0, d.width(), 22, header);
  d.setTextColor(TFT_WHITE, header);
  d.setTextSize(1);
  d.setFont(&fonts::FreeSansBold9pt7b);
  d.setCursor(4, 3);
  const char *title = listening ? "Listening" : s == UI_RUN ? "Working" : s == UI_ASK ? "Approve?" : s == UI_DONE ? "Done" : s == UI_ERROR ? "Problem" : "Mantiza";
  d.print(title);
  char right[24];
  int b = battery;
  snprintf(right, sizeof right, "%s%d%%", charging ? "+" : "", b < 0 ? 0 : b);
  d.setCursor(d.width() - d.textWidth(right) - 4, 3);
  d.print(right);

  d.setTextColor(TFT_WHITE, TFT_BLACK);
  d.setFont(&fonts::FreeSans9pt7b);
  d.setCursor(4, 30);
  if (listening) {
    d.println("Speak now.");
    d.setTextColor(TFT_LIGHTGREY, TFT_BLACK);
    d.println("Let go of A when done.");
    int w = d.width() - 8;
    d.drawRect(4, d.height() - 18, w, 12, TFT_WHITE);
    d.fillRect(5, d.height() - 17, (w - 2) * audio_level() / 100, 10, TFT_MAGENTA);
  } else if (s == UI_IDLE) {
    bool linked = ble_connected();
    const char *hid = ble_hid_state();
    d.setTextColor(linked ? TFT_GREEN : TFT_ORANGE, TFT_BLACK);
    d.println(linked ? "App connected" : "Waiting for app");
    d.setTextColor(strcmp(hid, "ok") == 0 ? TFT_GREEN : TFT_ORANGE, TFT_BLACK);
    d.println(strcmp(hid, "ok") == 0 ? "Pointer ready" : "Pointer not paired");
    d.setTextColor(TFT_LIGHTGREY, TFT_BLACK);
    if (ble_pairing_open()) d.println("Pairing open");
    else if (next.length()) d.println("A: " + next);
    else d.println(deviceName);
    if (linked) { d.setTextColor(TFT_CYAN, TFT_BLACK); d.println("Hold A to talk"); }
  } else {
    String t = text;
    t.replace("|", "\n");
    d.println(t);
  }
  if (!listening && s == UI_RUN && total > 0) {
    int w = d.width() - 8;
    d.drawRect(4, d.height() - 14, w, 10, TFT_WHITE);
    d.fillRect(5, d.height() - 13, (w - 2) * min(step, total) / total, 8, TFT_CYAN);
  }
  if (!listening && s == UI_ASK) {
    d.setTextColor(TFT_YELLOW, TFT_BLACK);
    d.setCursor(4, d.height() - 18);
    d.print("A = Yes      B = No");
  }
  d.endWrite();
}

static void wakeScreen() {
  lastActivity = millis();
  if (!screenOn) { M5.Display.setBrightness(128); screenOn = true; }
}

static void uiTask(void *) {
  uint32_t peaks[SHAKE_PEAKS] = {0};
  int peak = 0;
  uint32_t lastBattery = 0, lastIdleRedraw = 0, lastLevelDraw = 0;
  bool pairingHeld = false;
  for (;;) {
    M5.update();
    bool pressed = M5.BtnA.wasPressed() || M5.BtnB.wasPressed();
    if (pressed) wakeScreen();

    bool both = M5.BtnA.isPressed() && M5.BtnB.isPressed();
    if (both && M5.BtnA.pressedFor(PAIR_HOLD_MS) && M5.BtnB.pressedFor(PAIR_HOLD_MS) && !pairingHeld) {
      pairingHeld = true;
      audio_stop();
      ble_open_pairing(PAIRING_WINDOW_MS);
      pushEvent("pairing");
      beep(1500, 120);
      dirty = true;
    }
    if (!M5.BtnA.isPressed() && !M5.BtnB.isPressed()) pairingHeld = false;

    // Push-to-talk: hold A anywhere except an approval question (there A is "yes").
    if (state != UI_ASK && !both && !pairingHeld && M5.BtnA.wasHold()) { audio_start(); wakeScreen(); dirty = true; }
    if (audio_recording() && !M5.BtnA.isPressed()) { audio_stop(); dirty = true; }
    if (audio_recording() && millis() - lastLevelDraw > 100) { lastLevelDraw = millis(); dirty = true; }

    if (state == UI_ASK) {
      if (M5.BtnA.wasClicked()) { askAnswer = 1; beep(2000, 60); }
      if (M5.BtnB.wasClicked()) { askAnswer = 0; beep(800, 60); }
      if (prompting && (askAnswer >= 0 || (int32_t)(millis() - promptDeadline) >= 0)) {
        int answer = askAnswer;
        prompting = false;
        pushEvent(answer == 1 ? "yes" : answer == 0 ? "no" : "timeout");
        ui_show(promptBefore, answer == 1 ? "Approved" : answer == 0 ? "Cancelled" : "No answer");
      }
    } else if (state == UI_RUN) {
      if (!both && !pairingHeld && (M5.BtnB.wasClicked() || M5.BtnB.wasHold())) requestStop();
      if (!both && !pairingHeld && M5.BtnA.wasClicked()) pushEvent("a");  // the app pauses the task
    } else if (!both && !pairingHeld) {
      if (M5.BtnA.wasClicked()) pushEvent("a");
      if (M5.BtnB.wasHold()) requestStop();
      else if (M5.BtnB.wasClicked()) pushEvent("b");
    }

    if (M5.Imu.isEnabled()) {  // shake to stop: a few strong peaks close together
      float x, y, z;
      if (M5.Imu.getAccel(&x, &y, &z) && sqrtf(x * x + y * y + z * z) > SHAKE_G) {
        uint32_t now = millis();
        if (now - peaks[(peak + SHAKE_PEAKS - 1) % SHAKE_PEAKS] > 120) {  // one peak per swing
          peaks[peak] = now;
          peak = (peak + 1) % SHAKE_PEAKS;
          if (now - peaks[peak] < SHAKE_WINDOW_MS && (state == UI_RUN || state == UI_ASK)) {
            requestStop();
            memset(peaks, 0, sizeof peaks);
          }
        }
      }
    }

    if (millis() - lastBattery > 10000 || !lastBattery) {
      lastBattery = millis();
      int level = M5.Power.getBatteryLevel();
      bool chg = M5.Power.isCharging() == m5::Power_Class::is_charging;
      if (level != battery || chg != charging) { battery = level; charging = chg; dirty = true; }
    }
    if (state == UI_IDLE && millis() - lastIdleRedraw > 1000) {  // link and pointer state change on their own
      lastIdleRedraw = millis();
      dirty = true;
    }
    if (state == UI_IDLE && screenOn && millis() - lastActivity > SCREEN_OFF_MS) {
      M5.Display.setBrightness(0);
      screenOn = false;
    }
    if (dirty && screenOn) {
      dirty = false;
      draw();
    }
    vTaskDelay(pdMS_TO_TICKS(20));
  }
}

void ui_begin(const String &name) {
  lock = xSemaphoreCreateMutex();
  events = xQueueCreate(8, EVENT_LEN);
  deviceName = name;
  M5.Display.setRotation(1);
  M5.Display.setBrightness(128);
  M5.BtnA.setHoldThresh(TALK_HOLD_MS);  // A held: push-to-talk (A + B held 3 s: pairing)
  M5.BtnB.setHoldThresh(1000);  // B held 1 s is an emergency stop
  lastActivity = millis();
  xTaskCreatePinnedToCore(uiTask, "ui", 6144, NULL, 1, NULL, 1);
}

void ui_show(UiState s, const String &text, int step, int total) {
  xSemaphoreTake(lock, portMAX_DELAY);
  state = s;
  screenText = text;
  progStep = step;
  progTotal = total;
  xSemaphoreGive(lock);
  if (s == UI_RUN) stopLatched = false;
  if (s == UI_DONE) beep(2500, 80);
  if (s == UI_ERROR) beep(500, 200);
  wakeScreen();
  dirty = true;
}

void ui_set_next(const String &suggestion) {
  xSemaphoreTake(lock, portMAX_DELAY);
  nextText = suggestion;
  xSemaphoreGive(lock);
  dirty = true;
}

int ui_ask(const String &text, uint32_t timeout_ms) {
  UiState before = state;
  askAnswer = -1;
  ui_show(UI_ASK, text);
  beep(1800, 100);
  uint32_t start = millis();
  while (askAnswer < 0 && millis() - start < timeout_ms) {
    esp_task_wdt_reset();
    delay(20);
  }
  int answer = askAnswer;
  ui_show(before == UI_ASK ? UI_IDLE : before, answer == 1 ? "Approved" : answer == 0 ? "Cancelled" : "No answer");
  return answer;
}

void ui_prompt(const String &text, uint32_t timeout_ms) {
  if (!prompting) promptBefore = state == UI_ASK ? UI_IDLE : state;
  askAnswer = -1;
  promptDeadline = millis() + timeout_ms;
  prompting = true;
  ui_show(UI_ASK, text);
  beep(1800, 100);
}

bool ui_unprompt(const String &text) {
  if (!prompting) return false;
  prompting = false;
  ui_show(promptBefore, text);
  return true;
}

bool ui_stop_requested() { return stopLatched; }
void ui_clear_stop() { stopLatched = false; }
uint32_t ui_stop_count() { return stopCount; }

bool ui_pop_event(String &event) {
  char buf[EVENT_LEN];
  if (xQueueReceive(events, buf, 0) != pdTRUE) return false;
  event = buf;
  return true;
}

int ui_battery() { return battery; }
UiState ui_state() { return state; }
bool ui_charging() { return charging; }

UiState ui_state_from(const String &name, bool &known) {
  known = true;
  if (name == "idle") return UI_IDLE;
  if (name == "run") return UI_RUN;
  if (name == "done") return UI_DONE;
  if (name == "error") return UI_ERROR;
  if (name == "info") return UI_INFO;
  known = false;
  return UI_IDLE;
}
