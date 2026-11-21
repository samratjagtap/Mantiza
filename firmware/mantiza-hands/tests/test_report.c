// Host tests for the HID encoding: cc -I.. test_report.c ../src/hid/report.c -o /tmp/test_report && /tmp/test_report
#include <stdio.h>
#include <string.h>
#include "../src/hid/report.h"

static int failures;
#define CHECK(cond) do { if (!(cond)) { printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

static void test_ascii(void) {
  CHECK(hid_ascii('a') == 0x04);
  CHECK(hid_ascii('A') == 0x104);
  CHECK(hid_ascii('0') == 0x27);
  CHECK(hid_ascii('!') == 0x11E);
  CHECK(hid_ascii('?') == 0x138);
  CHECK(hid_ascii(' ') == 0x2C);
  CHECK(hid_ascii(0xE9) == 0);  // non-ASCII byte is rejected
}

static void test_combo(void) {
  uint8_t r[8];
  CHECK(hid_combo("cmd+v", r) && r[0] == 0x08 && r[2] == 0x19 && r[3] == 0);
  CHECK(hid_combo("shift+tab", r) && r[0] == 0x02 && r[2] == 0x2B);
  CHECK(hid_combo("enter", r) && r[0] == 0 && r[2] == 0x28);
  CHECK(!hid_combo("cmd+", r));
  CHECK(!hid_combo("hyper+x", r));
  CHECK(!hid_combo("", r));
}

static void test_consumer(void) {
  CHECK(hid_consumer("home") == 0x0040);
  CHECK(hid_consumer("achome") == 0x0223);
  CHECK(hid_consumer("0x01AE") == 0x01AE);
  CHECK(hid_consumer("0x400") == 0);
  CHECK(hid_consumer("0xZZ") == 0);
  CHECK(hid_consumer("nope") == 0);
}

static void test_mouse_report(void) {
  uint8_t r[HID_MOUSE_LEN];
  hid_mouse_report(r, 1, 0x1234, HID_ABS_MAX, -1, 2);
  CHECK(r[0] == 1 && r[1] == 0x34 && r[2] == 0x12 && r[3] == 0xFF && r[4] == 0x7F && r[5] == 0xFF && r[6] == 2);
  hid_mouse_report(r, 0, 40000, 40000, 0, 0);  // clamped
  CHECK(r[1] == 0xFF && r[2] == 0x7F && r[3] == 0xFF && r[4] == 0x7F);
}

int main(void) {
  test_ascii();
  test_combo();
  test_consumer();
  test_mouse_report();
  printf(failures ? "%d failure(s)\n" : "all report tests passed\n", failures);
  return failures != 0;
}
