// Status screen, buttons A/B, shake-to-stop and beeps for the M5StickS3 (135 x 240 LCD, BMI270, speaker).
// Runs in its own task so buttons and the emergency stop work while a gesture or typing is in progress.
#pragma once
#include <Arduino.h>

enum UiState { UI_IDLE, UI_RUN, UI_ASK, UI_DONE, UI_ERROR, UI_INFO };

void ui_begin(const String &name);
// Show a state. text may contain '|' for line breaks. step/total > 0 draws a progress bar while running.
void ui_show(UiState state, const String &text, int step = 0, int total = 0);
void ui_set_next(const String &suggestion);  // "Next: ..." line on the idle screen
// Ask the user on the device: 1 = A (yes), 0 = B (no) or stopped, -1 = timeout. Blocks, feeding the watchdog.
int ui_ask(const String &text, uint32_t timeout_ms);

// Ask without blocking: the answer arrives as event "yes", "no" (B or stop) or "timeout"; ui_unprompt withdraws
// it (answered elsewhere, e.g. on the phone) and returns false if it had already ended.
void ui_prompt(const String &text, uint32_t timeout_ms);
bool ui_unprompt(const String &text);

bool ui_stop_requested();   // latched until ui_clear_stop()
void ui_clear_stop();
uint32_t ui_stop_count();
bool ui_pop_event(String &event);  // "a", "b", "stop", "pairing", "yes", "no", "timeout", "talk_…" for the app
void ui_event(const char *event);  // queue an event for the app (up to 23 characters)

int ui_battery();     // percent, -1 if unknown
bool ui_charging();
UiState ui_state_from(const String &name, bool &known);
