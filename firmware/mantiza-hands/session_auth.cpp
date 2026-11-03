#include "session_auth.h"
#include <Preferences.h>
#include <esp_random.h>
#include <mbedtls/md.h>
#include <mbedtls/sha256.h>
#include "ble_link.h"
#include "ui.h"

static uint8_t secret[32];
static bool hasSecret = false;
static uint8_t nonce[16];
static bool nonceValid = false;
static bool authed = false;
static uint8_t sessionNonce[16];  // the challenge of the authenticated session, keys the line tags

static String hex(const uint8_t *b, size_t n) {
  static const char *digits = "0123456789abcdef";
  String s;
  s.reserve(n * 2);
  for (size_t i = 0; i < n; i++) { s += digits[b[i] >> 4]; s += digits[b[i] & 15]; }
  return s;
}

static bool unhex(const String &s, uint8_t *out, size_t n) {
  if (s.length() != n * 2) return false;
  for (size_t i = 0; i < n; i++) {
    char hi = tolower(s[2 * i]), lo = tolower(s[2 * i + 1]);
    auto v = [](char c) -> int { return c >= '0' && c <= '9' ? c - '0' : c >= 'a' && c <= 'f' ? c - 'a' + 10 : -1; };
    if (v(hi) < 0 || v(lo) < 0) return false;
    out[i] = (uint8_t)(v(hi) << 4 | v(lo));
  }
  return true;
}

void auth_begin() {
  Preferences p;
  p.begin("mantiza", true);
  hasSecret = p.getBytes("secret", secret, sizeof secret) == sizeof secret;
  p.end();
}

const char *auth_state() { return !hasSecret ? "none" : authed ? "ok" : "locked"; }

static long lastId = 0;

bool auth_exempt(const String &cmd) {
  return cmd == "ping" || cmd == "version" || cmd == "status" || cmd == "hello" || cmd == "auth" || cmd == "secret";
}

bool auth_line(String &line) {
  int tagAt = line.lastIndexOf(" ~");
  String tag = tagAt >= 0 ? line.substring(tagAt + 2) : "";
  String body = tagAt >= 0 && tag.length() == 16 ? line.substring(0, tagAt) : line;
  int sp = body.indexOf(' ');
  String rest = sp < 0 ? "" : body.substring(sp + 1);
  int sp2 = rest.indexOf(' ');
  String cmd = sp2 < 0 ? rest : rest.substring(0, sp2);
  line = body;
  if (!hasSecret || auth_exempt(cmd)) return true;
  if (!authed || tag.length() != 16) return false;
  long id = body.toInt();
  if (id <= lastId) return false;  // replayed or reordered
  uint8_t mac[32], got[8];
  if (!unhex(tag, got, sizeof got)) return false;
  const mbedtls_md_info_t *md = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
  mbedtls_md_context_t ctx;
  mbedtls_md_init(&ctx);
  mbedtls_md_setup(&ctx, md, 1);
  mbedtls_md_hmac_starts(&ctx, secret, sizeof secret);
  mbedtls_md_hmac_update(&ctx, sessionNonce, sizeof sessionNonce);
  mbedtls_md_hmac_update(&ctx, (const uint8_t *)body.c_str(), body.length());
  mbedtls_md_hmac_finish(&ctx, mac);
  mbedtls_md_free(&ctx);
  uint8_t diff = 0;
  for (size_t i = 0; i < sizeof got; i++) diff |= got[i] ^ mac[i];
  if (diff) return false;
  lastId = id;
  return true;
}

String auth_hello() {
  esp_fill_random(nonce, sizeof nonce);
  nonceValid = true;
  authed = false;
  return hex(nonce, sizeof nonce);
}

bool auth_check(const String &mac_hex) {
  uint8_t got[32], want[32];
  if (!hasSecret || !nonceValid || !unhex(mac_hex, got, sizeof got)) return false;
  nonceValid = false;  // one try per challenge
  mbedtls_md_hmac(mbedtls_md_info_from_type(MBEDTLS_MD_SHA256), secret, sizeof secret, nonce, sizeof nonce, want);
  uint8_t diff = 0;
  for (size_t i = 0; i < sizeof want; i++) diff |= got[i] ^ want[i];
  authed = diff == 0;
  if (authed) { memcpy(sessionNonce, nonce, sizeof nonce); lastId = 0; }
  return authed;
}

void auth_reset() {
  authed = false;
  nonceValid = false;
  lastId = 0;
}

String auth_code(const uint8_t *s, size_t n) {
  uint8_t h[32];
  mbedtls_sha256(s, n, h, 0);
  char code[5];
  snprintf(code, sizeof code, "%04u", (unsigned)(((h[0] << 8) | h[1]) % 10000));
  return code;
}

String auth_set(const String &secret_hex) {
  uint8_t s[32];
  if (!unhex(secret_hex, s, sizeof s)) return "err secret needs 64 hex characters";
  if (hasSecret && !ble_pairing_open()) return "err locked: hold A for 3 s on the stick to allow a new phone";
  int answer = ui_ask("Pair code " + auth_code(s, sizeof s) + "|Same on phone?|A = yes", 60000);
  if (answer != 1) return "err code not confirmed on the stick";
  Preferences p;
  p.begin("mantiza", false);
  p.putBytes("secret", s, sizeof s);
  p.end();
  memcpy(secret, s, sizeof secret);
  hasSecret = true;
  authed = false;  // the app authenticates with hello/auth next
  return "ok";
}

void auth_clear() {
  Preferences p;
  p.begin("mantiza", false);
  p.remove("secret");
  p.end();
  hasSecret = false;
  auth_reset();
}
