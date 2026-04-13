# Cliqmod ⌨️

A fully modular macro pad built around a CNC-machined aluminum core and a family of hot-swap I²C modules that snap in magnetically. Each module is a self-contained device with its own co-processor, power regulation, and RGB — the host brain just discovers what’s plugged in and talks to it.

Reconfigures itself for whatever you’re doing. No cables, no adapters, no reflashing.

-----

## How it works

The brain unit (ESP32-S3 DevKit C, ~90×90×35mm aluminum enclosure) runs two independent I²C buses — one for the left module chain, one for the right. Modules attach via 7-pin gold-plated P75 pogo pins and 6×2mm magnets. The host pings each slot on a heartbeat timer and runs a 9-pulse recovery sequence if a bus locks up.

Position determines I²C address — no DIP switches, no config jumpers.

|Chain        |Slot 1|Slot 2|Slot 3|
|-------------|------|------|------|
|Left (Bus 0) |`0x10`|`0x11`|`0x12`|
|Right (Bus 1)|`0x20`|`0x21`|`0x22`|

-----

## Module connector (7-pin pogo) 🔌

|Pin|Signal  |
|---|--------|
|1  |VCC 5V  |
|2  |GND     |
|3  |SDA     |
|4  |SCL     |
|5  |INT     |
|6  |RGB data|
|7  |ADDR    |

-----

## Modules

Every module ships with an ATtiny85 or CH32V003 co-processor, AMS1117 LDO (5V→3.3V), and a WS2812B RGB strip in a machined aluminum channel behind frosted acrylic.

**Knob + Slider** — 2× EC11 rotary encoders + 2× 75mm B10K linear faders with LED position strips. Good for volume, MIDI CC, timeline scrubbing.

**Button Matrix** — 4×4 hot-swap MX grid (Gateron Yellow/Red), 74HC165 shift register, full NKRO. Good for macros, layers, stream deck replacement.

-----

## Status 🚧

- [x] System architecture
- [x] Pogo pin interface + magnet placement
- [x] I²C addressing scheme
- [x] Heartbeat/watchdog protocol
- [ ] Brain PCB layout
- [ ] Module PCB layouts
- [ ] CNC enclosure drawings
- [ ] Firmware (ESP32-S3 host + module co-processors)
- [ ] First prototype

-----

*Inspired by Ocreeb MK2, Modue, k.no.b.less, and Monogram Creative Console.*
