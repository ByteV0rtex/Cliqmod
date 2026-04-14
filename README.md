# Cliqmod ⌨️

A fully modular, ultra customizable macro pad system built around a CNC-machined aluminum core and a family of hot-swap I²C modules that snap in magnetically with a click. Each module is a self-contained device with its own co-processor, power regulation, and RGB — the host brain just discovers what’s plugged in and talks to it. Fully customizable via its own Acces Point and website, the built in OLED screen or the iOS and Android app(Coming Soon)

Reconfigures itself for whatever you’re doing. No cables, no adapters, no reflashing.

-----
> [!NOTE]
> This project is still in the protoyping stage, details may change in the future.

## Modules

Every module ships with an ATtiny85 or CH32V003 co-processor, AMS1117 LDO (5V→3.3V), magnetic pogo pins on the sides and a WS2812B RGB strip in a machined aluminum channel behind frosted acrylic that goes along the bottom.

**Brain** - 1.3” OLED SH1106 + 1x EC11 encoder + 2x Tactile Buttons and a USB-C connector. Powered by the ESP-32 S3 DevkitC.It controls and connects every module. It has a OLED screen and knobs and buttons for controlling the settings of the device. The features include changing keybinds, profiles, RGB and more. 

**Knob + Slider** — 2× EC11 rotary encoders + 2× 75mm B10K linear faders with LED position strips. Allows for infinite customization possibilities. For example using the knobs at the top for switching what the faders under them do, or giving each one a completely diffrent control. Good for volume-brightness controls, MIDI CC, timeline scrubbing and color correction.

**Button Matrix** — 4×4 hot-swap MX grid (Gateron Yellow/Red), 74HC165 shift register, full NKRO. Your classic macro pad with premium features and high customizability. Good for macros, layers, stream deck replacement.

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

## Status 🚧

- [x] System architecture
- [x] Pogo pin interface + magnet placement
- [x] I²C addressing scheme
- [x] Heartbeat/watchdog protocol
- [x] Brain Protoype
- [x] Control Site Protoype
- [ ] Brain PCB layout
- [ ] Module PCB layouts
- [ ] CNC enclosure drawings
- [ ] Firmware (ESP32-S3 host + module co-processors)
- [ ] Mobile app (In Progress)
- [ ] First prototype

-----

*Inspired by Ocreeb MK2, Modue, k.no.b.less, and Monogram Creative Console.*
