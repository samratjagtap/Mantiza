// Mantiza Hands: the M5StickS3 as the iPhone's Bluetooth LE pointer + keyboard, driven by the Mantiza app.
// The iPhone captures its own screen and decides; this board only executes input and shows status.
// Based on ESP32 iPhone Agent by Henry Yuan (await-ovo/esp32-iphone-agent and jinwon-int forks, MIT).
//
// Protocol: one line per command, "<id> <command>", answered "<id> ok [result]" or "<id> err <why>".
// The same lines work over the BLE cmd/reply characteristics and USB serial (115200). Unsolicited events
// from the device are sent as "evt <name>" (a, b, stop, pairing, yes, no, timeout, talk_start UTT,
// talk_end UTT PACKETS, talk_short UTT). Holding A records speech for the app (audio.h).
//
// Pointer (absolute, x and y in 0..32767 across the whole screen):
//   at X Y | wake | move DX DY | tap X Y [hold_ms] | longpress X Y [ms] | stroke X1 Y1 X2 Y2 N
//   press | release | scroll V H | park
// Keys: type TEXT (US ASCII) | key COMBO (cmd+v, enter, shift+tab ...) | home | consumer NAME|0xNNNN
// Board: ping | status | version | ui STATE [STEP/TOTAL] TEXT | next TEXT | ask SECONDS TEXT | pair | unpair
//        prompt SECONDS TEXT (non-blocking ask; evt yes|no|timeout follows) | unprompt [TEXT]
//        audio UTT SEQ (send a recorded packet again; over USB the reply carries it as plain hex)
// Auth (BLE only; see session_auth.h): secret HEX64 | hello -> ok NONCE | auth HMAC_HEX; then every other BLE
//   line carries " ~TAG" (HMAC of the line keyed by the session). ping, version, status need no tag.

#include <M5Unified.h>
#include <esp_task_wdt.h>
#include <esp_mac.h>
#include "ble_link.h"
#include "hands.h"
#include "ui.h"
#include "session_auth.h"
#include "audio.h"

#ifndef DEBUG_SERIAL
#define DEBUG_SERIAL 0
#endif

const char *FIRMWARE_VERSION = "0.4.3";
const uint32_t APP_SILENT_MS = 8000;  // the app pings every 2 s while a task runs
const int WATCHDOG_MS = 8000;
const uint32_t ASK_MAX_S = 120;
const uint32_t PAIRING_WINDOW_MS = 120000;

const char *resetReason() {
  switch (esp_reset_reason()) {
    case ESP_RST_POWERON: return "power-on";
    case ESP_RST_BROWNOUT: return "brownout";
    case ESP_RST_TASK_WDT: case ESP_RST_INT_WDT: case ESP_RST_WDT: return "watchdog";
    case ESP_RST_PANIC: return "crash";
    case ESP_RST_SW: return "software";
    case ESP_RST_USB: return "usb";
    default: return "other";
  }
}

String statusJson() {
  char s[360];
  snprintf(s, sizeof s,
           "{\"fw\":\"%s\",\"up\":%lu,\"rst\":\"%s\",\"heap\":%u,\"hid\":\"%s\",\"hgen\":%lu,"
           "\"batt\":%d,\"chg\":%s,\"pair\":%s,\"stop\":%lu,\"auth\":\"%s\","
           "\"ble\":{\"mtu\":%u,\"phy\":%u,\"rdrop\":%lu,\"hdrop\":%lu,\"n\":%d}}",
           FIRMWARE_VERSION, millis(), resetReason(), (unsigned)heap_caps_get_free_size(MALLOC_CAP_INTERNAL),
           ble_hid_state(), (unsigned long)ble_hid_generation(), ui_battery(), ui_charging() ? "true" : "false",
           ble_pairing_open() ? "true" : "false", (unsigned long)ui_stop_count(), auth_state(), ble_mtu(), ble_phy(),
           (unsigned long)ble_reply_drops(), (unsigned long)ble_hid_drops(), ble_peers());
  return s;
}

// "ui run 3/7 Opening chat" or "ui done Sent"
String uiCommand(const String &arg) {
  int sp = arg.indexOf(' ');
  String name = sp < 0 ? arg : arg.substring(0, sp);
  String rest = sp < 0 ? "" : arg.substring(sp + 1);
  bool known;
  UiState s = ui_state_from(name, known);
  if (!known) return "err ui needs idle|run|done|error|info";
  int step = 0, total = 0;
  int sp2 = rest.indexOf(' ');
  String first = sp2 < 0 ? rest : rest.substring(0, sp2);
  if (sscanf(first.c_str(), "%d/%d", &step, &total) == 2) rest = sp2 < 0 ? "" : rest.substring(sp2 + 1);
  else step = total = 0;
  ui_show(s, rest, step, total);
  return "ok";
}

// Board-level commands from the app; everything else is a pointer/keyboard command for hands_run().
String board(const String &line, const String &id, bool usb) {
  int sp = line.indexOf(' ');
  String cmd = sp < 0 ? line : line.substring(0, sp);
  String arg = sp < 0 ? "" : line.substring(sp + 1);
  if (cmd == "hello") return "ok " + auth_hello();
  if (cmd == "auth") return auth_check(arg) ? "ok" : "err auth failed";
  if (cmd == "secret") return auth_set(arg);
  if (cmd == "ping") return "ok";
  if (cmd == "version") return String("ok ") + FIRMWARE_VERSION;
  if (cmd == "status") return String("ok ") + statusJson();
  if (cmd == "ui") return uiCommand(arg);
  if (cmd == "next") { ui_set_next(arg); return "ok"; }
  if (cmd == "audio") return audio_command(arg, usb);
  if (cmd == "pair") { ble_open_pairing(PAIRING_WINDOW_MS); return "ok"; }
  if (cmd == "ask") {
    int sp2 = arg.indexOf(' ');
    long seconds = sp2 < 0 ? 0 : arg.substring(0, sp2).toInt();
    if (seconds < 1 || seconds > (long)ASK_MAX_S) return "err ask needs SECONDS (1..120) TEXT";
    int answer = ui_ask(arg.substring(sp2 + 1), seconds * 1000);
    return answer == 1 ? "ok yes" : answer == 0 ? "ok no" : "ok timeout";
  }
  if (cmd == "prompt") {  // like ask, but answers at once; the choice follows as evt yes|no|timeout
    int sp2 = arg.indexOf(' ');
    long seconds = sp2 < 0 ? 0 : arg.substring(0, sp2).toInt();
    if (seconds < 1 || seconds > (long)ASK_MAX_S) return "err prompt needs SECONDS (1..120) TEXT";
    ui_prompt(arg.substring(sp2 + 1), seconds * 1000);
    return "ok";
  }
  if (cmd == "unprompt") return ui_unprompt(arg.length() ? arg : String("Answered on phone")) ? "ok" : "ok ended";
  if (cmd == "unpair") {
    ble_reply(id + " ok");  // answer before the link goes down
    auth_clear();
    ble_unpair();
    return "ok";            // for USB; over BLE the peers are gone, so this second reply is dropped
  }
  return hands_run(line);
}

void statusTask(void *) {
  int lastBattery = -2;
  for (;;) {
    vTaskDelay(pdMS_TO_TICKS(1000));
    int b = ui_battery();
    if (b >= 0 && b != lastBattery) { lastBattery = b; ble_set_battery(b); }
    if (ble_connected()) ble_status(statusJson());
  }
}

void sendEvent(const String &event) {
  ble_reply("evt " + event);
  Serial.println("evt " + event);
}

String handle(const String &raw, bool usb) {
  String line = raw;
  line.trim();
  if (!usb && !auth_line(line)) {
    int sp0 = line.indexOf(' ');
    return (sp0 < 0 ? line : line.substring(0, sp0)) + " err auth";
  }
  int sp = line.indexOf(' ');
  String id = sp < 0 ? line : line.substring(0, sp);
  String rest = sp < 0 ? "" : line.substring(sp + 1);
  rest.trim();
  if (!(id.toInt() || id == "0")) return "err missing request id";
#if DEBUG_SERIAL
  unsigned long started = millis();
#endif
  String reply = board(rest, id, usb);
#if DEBUG_SERIAL
  Serial.printf("[%s] %s -> %s (%lu ms)\n", id.c_str(), rest.c_str(), reply.c_str(), millis() - started);
#endif
  return reply.length() ? id + " " + reply : "";
}

void setup() {
  auto cfg = M5.config();
  M5.begin(cfg);
  Serial.begin(115200);
  esp_task_wdt_config_t wdt = {.timeout_ms = WATCHDOG_MS, .idle_core_mask = 0, .trigger_panic = true};
  esp_task_wdt_reconfigure(&wdt);
  esp_task_wdt_add(NULL);

  uint8_t mac[6];
  esp_read_mac(mac, ESP_MAC_BT);
  char suffix[5];
  snprintf(suffix, sizeof suffix, "%02X%02X", mac[4], mac[5]);
  String name = "Mantiza Hands " + String(suffix);
  ui_begin(name);
  audio_begin();
  auth_begin();
  ble_begin(name);
  xTaskCreatePinnedToCore(statusTask, "status", 4096, NULL, 1, NULL, 1);
  Serial.printf("boot %s fw %s: reset %s, free heap %u\n", name.c_str(), FIRMWARE_VERSION, resetReason(),
                (unsigned)heap_caps_get_free_size(MALLOC_CAP_INTERNAL));
}

void loop() {
  static bool linked = false;
  esp_task_wdt_reset();
  hands_poll();
  static int peers = 0;
  if (linked && !ble_connected()) {
    hands_release();  // the app may disconnect while the system keeps its HID connection
    ui_show(UI_IDLE, "");
  }
  if (ble_peers() != peers) auth_reset();  // a central came or went: authenticate again
  peers = ble_peers();
  linked = ble_connected();

  String event;
  while (ui_pop_event(event)) sendEvent(event);

  if (Serial.available()) {  // USB serial takes the same "<id> <command>" lines, for the Mac harness
    String reply = handle(Serial.readStringUntil('\n'), true);
    if (reply.length()) Serial.println(reply);
    return;
  }
  // While a task runs the app sends a line at least every 2 s; silence means it crashed or was closed.
  static uint32_t lastAppLine = millis();
  UiState s = ui_state();
  if ((s == UI_RUN || s == UI_ASK) && linked && millis() - lastAppLine > APP_SILENT_MS) {
    hands_release();
    ui_show(UI_ERROR, "The phone app stopped|responding. Open Mantiza.");
  }
  String line;
  if (!ble_pop_cmd(line, 50)) return;
  lastAppLine = millis();
  String reply = handle(line, false);
  if (reply.length()) ble_reply(reply);
}
