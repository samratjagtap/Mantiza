# Third-party notices

Mantiza reuses code from the open-source projects below. Each is used under its license; the license text is reproduced here as those licenses require.

## ESP32 iPhone Agent

Based on ESP32 iPhone Agent by Henry Yuan.

- Sources: [onehumanbeing/esp32-iphone-agent](https://github.com/onehumanbeing/esp32-iphone-agent), and the forks [await-ovo/esp32-iphone-agent](https://github.com/await-ovo/esp32-iphone-agent) and [jinwon-int/esp32-iphone-agent](https://github.com/jinwon-int/esp32-iphone-agent).
- Used in: `firmware/mantiza-hands/` (`ble_link.*`, `nimble_cfg.h`, `hands.*`, `src/hid/report.*` are adapted from the await-ovo firmware; the absolute pointer descriptor and iOS timing rules come from the jinwon-int fork); `ios/Mantiza/` (`Board/BoardLink.swift`, `Board/BoardProtocol.swift`, `Board/CommandChannel.swift`, `Calibration/TouchProbe.swift` and the screen capture code in `Eyes/` are adapted from the await-ovo iOS app).
- Not used: the GPL-3.0 AirPlay receiver (`hardware/hid_bridge/src/airplay/`) in the original project.

```
MIT License

Copyright (c) 2026 Henry Yuan

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
