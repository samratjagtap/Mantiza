#include "audio.h"
#include <M5Unified.h>
#include <esp_heap_caps.h>
#include <mbedtls/aes.h>
#include "ble_link.h"
#include "session_auth.h"
#include "ui.h"

const uint32_t MAX_SECONDS = 30;
const size_t PACKET_MAX = AUDIO_HEADER + AUDIO_SAMPLES_PER_PACKET / 2;
const size_t MAX_PACKETS = MAX_SECONDS * AUDIO_RATE / AUDIO_SAMPLES_PER_PACKET;
const uint32_t MIN_MS = 400;  // shorter presses are a slip, not speech

static uint8_t *store;       // MAX_PACKETS x PACKET_MAX in PSRAM
static uint16_t lengths[MAX_PACKETS];
static volatile size_t count;
static volatile uint32_t utterance;
static volatile bool wanted, recording;
static volatile int level;
static TaskHandle_t task;

// IMA ADPCM, the standard tables.
static const int16_t STEPS[89] = {
    7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88, 97,
    107, 118, 130, 143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658, 724, 796,
    876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428,
    4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899, 15289, 16818, 18500, 20350,
    22385, 24623, 27086, 29794, 32767};
static const int8_t INDEX_ADJUST[16] = {-1, -1, -1, -1, 2, 4, 6, 8, -1, -1, -1, -1, 2, 4, 6, 8};

struct Adpcm {
  int predictor = 0;
  int index = 0;
  uint8_t encode(int16_t sample) {
    int step = STEPS[index];
    int diff = sample - predictor;
    uint8_t code = 0;
    if (diff < 0) { code = 8; diff = -diff; }
    int delta = step >> 3;
    if (diff >= step) { code |= 4; diff -= step; delta += step; }
    if (diff >= step >> 1) { code |= 2; diff -= step >> 1; delta += step >> 1; }
    if (diff >= step >> 2) { code |= 1; delta += step >> 2; }
    predictor += (code & 8) ? -delta : delta;
    predictor = constrain(predictor, -32768, 32767);
    index = constrain(index + INDEX_ADJUST[code], 0, 88);
    return code;
  }
};

static uint8_t *packet(size_t seq) { return store + seq * PACKET_MAX; }

// Encrypt everything after seq with the session's audio key; false when the app has not authenticated.
static bool seal(const uint8_t *plain, size_t n, uint32_t utt, uint8_t *out) {
  uint8_t key[16];
  if (!auth_audio_key(key)) return false;
  uint8_t iv[16] = {0}, block[16];
  memcpy(iv, &utt, 4);
  memcpy(iv + 4, plain, 2);
  size_t off = 0;
  mbedtls_aes_context aes;
  mbedtls_aes_init(&aes);
  mbedtls_aes_setkey_enc(&aes, key, 128);
  memcpy(out, plain, 2);
  mbedtls_aes_crypt_ctr(&aes, n - 2, &off, iv, block, plain + 2, out + 2);
  mbedtls_aes_free(&aes);
  return true;
}

static void send(size_t seq) {
  uint8_t sealed[PACKET_MAX];
  if (seal(packet(seq), lengths[seq], utterance, sealed)) ble_audio(sealed, lengths[seq]);
}

static void audioTask(void *) {
  static int16_t buf[2][AUDIO_SAMPLES_PER_PACKET];
  for (;;) {
    ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
    if (!wanted) continue;
    uint32_t started = millis();
    utterance++;
    count = 0;
    recording = true;
    M5.Speaker.end();  // the speaker and the mic share the codec
    M5.Mic.begin();
    char e[24];
    snprintf(e, sizeof e, "talk_start %lu", (unsigned long)utterance);
    ui_event(e);
    Adpcm adpcm;
    int b = 0;
    M5.Mic.record(buf[0], AUDIO_SAMPLES_PER_PACKET, AUDIO_RATE);
    M5.Mic.record(buf[1], AUDIO_SAMPLES_PER_PACKET, AUDIO_RATE);
    while (wanted && count < MAX_PACKETS) {
      while (M5.Mic.isRecording() > 1) vTaskDelay(1);  // buf[b] is full once only one record is still queued
      uint8_t *p = packet(count);
      p[0] = count & 0xFF;
      p[1] = count >> 8;
      int16_t pred = adpcm.predictor;
      memcpy(p + 2, &pred, 2);
      p[4] = adpcm.index;
      p[5] = 0;
      uint32_t energy = 0;
      for (size_t i = 0; i < AUDIO_SAMPLES_PER_PACKET; i += 2) {
        p[AUDIO_HEADER + i / 2] = adpcm.encode(buf[b][i]) | adpcm.encode(buf[b][i + 1]) << 4;
        energy += abs(buf[b][i]);
      }
      level = min(100, (int)(energy / (AUDIO_SAMPLES_PER_PACKET / 2) / 40));
      lengths[count] = PACKET_MAX;
      send(count++);
      M5.Mic.record(buf[b], AUDIO_SAMPLES_PER_PACKET, AUDIO_RATE);
      b ^= 1;
    }
    while (M5.Mic.isRecording()) vTaskDelay(1);
    M5.Mic.end();
    M5.Speaker.begin();
    recording = false;
    level = 0;
    if (millis() - started < MIN_MS) snprintf(e, sizeof e, "talk_short %lu", (unsigned long)utterance);
    else snprintf(e, sizeof e, "talk_end %lu %u", (unsigned long)utterance, (unsigned)count);
    ui_event(e);
  }
}

void audio_begin() {
  store = (uint8_t *)heap_caps_malloc(MAX_PACKETS * PACKET_MAX, MALLOC_CAP_SPIRAM);
  auto cfg = M5.Mic.config();
  cfg.sample_rate = AUDIO_RATE;
  cfg.noise_filter_level = 0;
  M5.Mic.config(cfg);
  xTaskCreatePinnedToCore(audioTask, "audio", 6144, NULL, 2, &task, 1);
}

void audio_start() {
  if (!store || recording) return;
  wanted = true;
  xTaskNotifyGive(task);
}

void audio_stop() { wanted = false; }
bool audio_recording() { return recording; }
int audio_level() { return level; }

String audio_command(const String &arg, bool usb) {
  uint32_t utt = 0, seq = 0;
  if (sscanf(arg.c_str(), "%lu %lu", (unsigned long *)&utt, (unsigned long *)&seq) != 2) return "err audio needs UTT SEQ";
  if (utt != utterance || seq >= count) return "err gone";
  if (!usb) { send(seq); return "ok"; }
  static const char *digits = "0123456789abcdef";
  String hex;
  hex.reserve(lengths[seq] * 2);
  for (size_t i = 0; i < lengths[seq]; i++) { hex += digits[packet(seq)[i] >> 4]; hex += digits[packet(seq)[i] & 15]; }
  return "ok " + hex;
}
