// Per-stick secret shared with the owner's app, an HMAC-SHA256 challenge per session, and a tag on every command
// line, so other apps on the phone (which share the phone's one BLE connection to the stick) or other bonded
// centrals cannot drive the pointer. USB serial is not gated (the Mac harness).
//
// After `hello` -> nonce and `auth HMAC(secret, nonce)`, each BLE line is "<id> <command> ~<tag>" with
// tag = hex of the first 8 bytes of HMAC(secret, nonce || "<id> <command>") and ids strictly increasing.
#pragma once
#include <Arduino.h>

void auth_begin();                    // load the secret from NVS
const char *auth_state();             // none (no secret yet) | locked | ok
bool auth_exempt(const String &cmd); // ping, version, status, hello, auth, secret need no tag
// Check and strip the tag of a BLE line ("<id> <command> ~<tag>"). Without a secret every line passes.
bool auth_line(String &line);
String auth_hello();                  // new challenge (32 hex chars)
bool auth_check(const String &mac_hex);  // HMAC-SHA256(secret, challenge) as hex
void auth_reset();                    // connection changed: authenticate again
// Store a new secret (64 hex chars). Allowed when there is none yet or the pairing window is open, and only after
// the user confirms the 4-digit code on the stick with A. Returns "ok", or an error text.
String auth_set(const String &secret_hex);
void auth_clear();                    // forget the secret (unpair)
String auth_code(const uint8_t *secret, size_t n);  // 4 digits shown on the stick and in the app
