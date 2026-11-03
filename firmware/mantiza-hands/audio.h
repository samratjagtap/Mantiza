// Push-to-talk: hold A, the stick records 16 kHz speech, IMA-ADPCM encodes it (4:1) and streams it to the app,
// which transcribes it on the phone. Each recording ("utterance") is kept in PSRAM until the next one, so the app
// can ask for lost packets again.
//
// Packet (plain): seq u16 LE | predictor i16 LE | step index u8 | 0 | ADPCM bytes (low nibble first, 512 samples
// in a full packet). Over BLE everything after seq is AES-128-CTR encrypted with the session's audio key
// (session_auth.h) and IV = utterance u32 LE | seq u16 LE | 10 zero bytes. Nothing is sent before the app has
// authenticated. Events: "talk_start UTT", "talk_end UTT PACKETS" (also "talk_short" for a too-short press).
#pragma once
#include <Arduino.h>

const uint32_t AUDIO_RATE = 16000;
const size_t AUDIO_SAMPLES_PER_PACKET = 512;  // 32 ms
const size_t AUDIO_HEADER = 6;

void audio_begin();
void audio_start();       // A held: start recording (no-op if already recording)
void audio_stop();        // A released: finish the utterance
bool audio_recording();
int audio_level();        // 0..100, for the "Listening" screen
// Resend packet SEQ of utterance UTT. Over BLE: encrypted notify again. Over USB: returns "ok <hex of plain packet>".
String audio_command(const String &arg, bool usb);
