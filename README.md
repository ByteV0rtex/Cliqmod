# Cliqmod ⌨️

> A fully modular, magnetically connected macro pad system built from CNC-machined aluminum.

Cliqmod is built around the idea that your tools should adapt to you — not the other way around. Snap on the modules you need, leave off the ones you don’t, and reconfigure everything from a browser (or the companion app) without touching a line of code. No cables between modules. No adapters. No reflashing.

Every module is a self-contained device with its own co-processor, power regulation, and RGB accent lighting. The brain discovers what’s attached at boot, assigns I²C addresses automatically based on position, and starts talking to everything in seconds.

> [!NOTE]
> Cliqmod is currently in the prototyping stage. Hardware specs, pinouts, and firmware interfaces may change before the first full build.

-----

## What makes it different

Most macro pads are a fixed grid of keys. You buy what exists and live with it. Cliqmod treats the macro pad as a platform — a brain with expansion slots. The brain handles USB HID output, WiFi configuration, and module discovery. The modules handle their own inputs locally and only interrupt the brain when something actually happens.

The result is a system that scales. Add a knob and slider module on the left for your DAW. Add a button matrix on the right for your stream deck shortcuts. Dock your iPhone in front and let it act as another surface entirely. Rearrange them. Swap them out mid-session. The brain figures out what’s there.

-----

## Modules

Every module in the Cliqmod ecosystem shares the same physical and electrical interface — a 7-pin gold-plated P75 pogo connector on each side, 6×2mm neodymium magnets for alignment and hold, an ATtiny85 or CH32V003 co-processor, AMS1117 3.3V LDO, and a WS2812B RGB strip running along the bottom edge of the enclosure behind a frosted acrylic diffuser.

The RGB strip wraps around the front corners so every exposed face glows. Connected sides are flush and hidden — only the outer edges light up. Each module controls its own LEDs independently.

-----

### Brain

> The core of the system. Required.

**Enclosure:** ~90×90×35mm CNC-machined aluminum, square footprint  
**MCU:** ESP32-S3 DevKit C (240MHz dual-core, native USB HID, WiFi)  
**Display:** 1.3” SH1106 OLED (128×64)  
**Controls:** 1× EC11 rotary encoder with click, 2× tactile buttons  
**Connectivity:** USB-C (native HID to host computer), pogo connectors left and right  
**Back panel:** USB-C port, WS2812B status LED

The brain runs two independent I²C buses — one for the left module chain, one for the right. This gives each side a fresh 400pF capacitance budget and means a fault on one side can’t bring down the other. A PCA9515 I²C buffer sits at each connector port for hot-plug protection and bus isolation.

On boot the brain pulses the ADDR line to assign each module its position-based address, scans both chains, loads the last-used profile from flash, and brings up networking (see [Connectivity](#connectivity) below). The whole process takes under two seconds.

The encoder and buttons on the top face are fully mappable — they fire HID shortcuts just like any module control. Hold the encoder to navigate the on-device menu. Press the buttons on the home screen to trigger their assigned macros.

-----

### Knob + Slider

> Analog control for DAWs, color grading, and anything that benefits from physical faders.

**Enclosure:** ~90×130mm CNC-machined aluminum (taller than the brain, aligns flush at the bottom)  
**Controls:** 2× EC11 rotary encoders with click, 2× 75mm B10K linear fader potentiometers  
**Fader feedback:** Vertical WS2812B LED strips on both sides of each fader — acts as a level meter (green → yellow → red)

Each encoder and fader is independently mappable. The encoder above a fader doesn’t have to control the same thing — they’re treated as six separate controls. A common setup is encoders for fine-tuning and faders for broad sweeps of different parameters entirely.

Faders use **pickup mode** — when a module connects, the fader won’t jump the parameter to its current physical position. It waits until the fader passes through the last known value, then takes control. The brain’s display shows the gap so you know when to expect the takeover.

Hold an encoder and turn it to switch what its paired fader controls — without changing any global settings.

**Example uses**

- Volume / pan per channel in a DAW
- Lift / gamma / gain in DaVinci Resolve color grading
- Layer opacity / brush size / flow in Photoshop
- OBS source volumes
- Game audio mixing (master / music / SFX)

-----

### Button Matrix

> A 4×4 mechanical macro pad with hot-swap switches and full NKRO.

**Enclosure:** ~90×90×25mm CNC-machined aluminum (same footprint as the brain, shallower profile)  
**Switches:** 4×4 hot-swap MX sockets — compatible with any Cherry MX-style switch  
**Recommended switches:** Gateron Yellow (linear, smooth) or Gateron Red (linear, light)  
**Matrix scanning:** 74HC165 shift register, diodes per switch for full N-key rollover

Keycaps are standard MX spacing (19.05mm) so any MX keycap set works. The hot-swap sockets mean you can change switches without soldering — try different tactile, linear, or clicky options and swap them out any time.

Every key is independently mappable per profile. Layer support means 16 physical keys can cover far more than 16 functions.

**Example uses**

- Application shortcut grid (cut, copy, paste, undo, redo, save…)
- Stream deck replacement (scene switching, mic mute, clip creation)
- Gaming macro panel
- Numpad

-----

### iPhone Dock

> A stand that turns your iPhone into another Cliqmod surface. Comes in two variants — with or without wireless charging.

**Enclosure:** ~90×90×100mm CNC-machined aluminum base + angled stand (matches the brain/matrix footprint, sits at phone-viewing angle)  
**Phone presence:** NFC tag (NTAG213/215) behind a non-metal window, plus coil-based placement detection on the charging variant  
**Window insert:** acrylic or nylon cutout behind the coil/NFC tag — CNC aluminum blocks NFC reads and induces eddy-current losses in a Qi coil, so this section can't be solid metal like the rest of the enclosure

**No-charging variant** — fully cable-free. The NFC tag is passive (powered by the phone's own NFC field, needs nothing from the module), and the co-processor's placement-detection draws so little current it runs fine off the shared pogo VCC bus like every other module. Nothing exits the enclosure at all.

**Charging variant** — the Qi coil needs more current than the pogo bus is budgeted for, so it gets its own USB-C input. That cable exits low on the **back** edge through a small machined channel, the same way the Brain module's USB-C port already sits on its back panel — flat against the desk, not visible from the front or sides, but still technically a cable if you look from behind. Charging current never touches the shared pogo bus regardless.

Both variants use the standard 7-pin pogo connector for I²C status reporting — "phone placed" / "phone removed" fires as a normal INT event to the brain, the same way a button press does.

Placing the phone on the dock triggers the NFC tag, which opens the Cliqmod app directly to a chosen profile — no unlock required, works straight from the lock screen. The app then renders that profile as a virtual deck (see [Companion App](#companion-app)) or hands control to Config mode.

**Example uses**

- Drop your phone on the desk and have it auto-launch into Deck mode
- Use the phone as a temporary extra 8-button surface without adding hardware modules
- Charge passively while it doubles as a secondary macro screen

-----

## Companion App

One SwiftUI app, two modes, talking to the same brain the physical modules talk to.

**Deck mode** — renders the current profile as a virtual grid of buttons on the phone, matching the same static layout and backlight-style visual feedback as the physical modules. It's a second surface for the same profile data, not a separate app with its own state.

**Config mode** — the mobile equivalent of the `192.168.4.1` web UI: assign mappings, switch profiles, check connected modules, rescan the chain. The web UI stays available as a zero-install fallback; the app is the richer, faster path when you have it installed.

The app talks to the brain over the local network, not to a desktop companion app — so pairing works the same way regardless of what computer (or none) is plugged in via USB.

-----

## How it works

### Architecture

Each module runs its own co-processor (ATtiny85 or CH32V003). When a control changes — a key press, an encoder turn, a fader move, a phone placed on the dock — the co-processor sends its I²C address to the brain as an interrupt. The brain goes directly to that module for the event data. No polling. No shared interrupt line. No Ocreeb MK2-style cascade failure.

The brain regenerates the WS2812B RGB signal at each module rather than passing it through raw, so signal quality stays clean regardless of chain length.

### Connectivity

The brain tries to join a saved home WiFi network (STA mode) at boot. If no credentials are saved, or the join fails, it automatically falls back to broadcasting its own access point — so the device always works, even on an unfamiliar network, and initial setup never requires typing in a password blind.

For app pairing, the brain doesn't rely on network discovery alone (mDNS/Bonjour-style discovery is unreliable across routers and OS versions). Instead the OLED can display a QR code — IP, port, and pairing token — for a one-scan pair from the app, regardless of what the network topology looks like that day.

### I²C addressing

Position on the chain determines address. At boot the brain pulses the ADDR line — each module counts pulses and latches its address automatically.

|Chain        |Position 1|Position 2|Position 3|
|-------------|----------|----------|----------|
|Left (I²C 0) |`0x10`    |`0x11`    |`0x12`    |
|Right (I²C 1)|`0x20`    |`0x21`    |`0x22`    |

No solder jumpers. No DIP switches. Plug in anywhere.

### Fault tolerance

- **Heartbeat:** Brain pings all known module addresses every 500ms. Missing module is flagged on the OLED immediately.
- **Hot-plug:** Reconnecting a module triggers re-enumeration of that side’s chain.
- **Bus lockup recovery:** If an I²C bus gets stuck (SDA held low), the brain sends 9 clock pulses to force a STOP condition and re-initializes the bus. Runs automatically.
- **Bus isolation:** PCA9515 buffer on each connector port prevents a hot-plug event from corrupting communication with already-connected modules.

-----

## Module connector (7-pin pogo)

All modules use the same connector on both sides. 2.54mm pitch, ~18mm wide, gold-plated P75 spring-loaded pins.

|Pin|Signal|Notes                                             |
|---|------|--------------------------------------------------|
|1  |VCC 5V|Regulated to 3.3V locally on each module (AMS1117)|
|2  |GND   |                                                  |
|3  |SDA   |4.7kΩ pull-up on brain side only                  |
|4  |SCL   |4.7kΩ pull-up on brain side only                  |
|5  |INT   |Active-low interrupt from module co-processor     |
|6  |RGB   |WS2812B data, regenerated per module              |
|7  |ADDR  |Position-assignment pulse line from brain         |

Power budget: safe for 2–3 modules per side at full RGB brightness. Beyond that, voltage drop across pogo pin resistance becomes a factor. The iPhone Dock's charging variant doesn't count against this budget since its coil runs off its own back-panel USB-C input; the no-charging variant runs entirely off the shared bus like any other module.

-----

## Configuration

### Web interface

Cliqmod broadcasts a WiFi access point called **Cliqmod** (password: `cliqmod1`) when not joined to a home network. Open `192.168.4.1` in any browser — no app, no drivers, no install.

From the web UI you can:

- Switch between profiles instantly
- Add, edit, and remove control mappings
- Assign any key combo (`CTRL+Z`, `SHIFT+ALT+F4`, `F5`, etc.) or typed string to any control
- See which modules are currently connected
- Trigger a module rescan

Supported key combo format: `CTRL+Z`, `SHIFT+ALT+F4`, `F5`, `ENTER`, `ESC`, `TAB`, `DELETE`, `BKSP`, `UP`, `DOWN`, `LEFT`, `RIGHT`

### Companion app

Same capabilities as the web UI (Config mode), plus Deck mode for using an iPhone as a virtual surface. See [Companion App](#companion-app) above for how it connects.

### On-device menu

Navigate with the encoder on the brain module. Click to enter, hold to go back to the home screen.

```
Home screen
  └── Menu
        ├── Profiles    — select active profile
        ├── Mappings    — browse mappings in current profile
        ├── Modules     — show connected module info
        ├── WiFi        — show SSID, password, and IP
        └── About       — firmware version and system info
```

### Profiles

Up to 8 profiles stored in flash. Each profile is a complete set of mappings — every control on every module can be remapped per profile. Switching profiles takes effect immediately. The last active profile is restored on power-up.

-----

## Physical design

All enclosures are CNC-machined aluminum. The RGB strip runs along the bottom edge of each module, wraps around the front face corners, and diffuses through a frosted acrylic insert. Connected sides are flush — only exposed faces glow.

**Alignment:** All modules align flush at the bottom edge. The knob+slider module is taller than the brain and sits higher, and the iPhone Dock sits highest of all at its viewing angle — this is intentional, creating a stepped skyline layout rather than forcing everything to the same height.

**Magnets:** 6×2mm neodymium magnets, minimum 5mm clearance from all PCB components.

**Enclosure sizes:**

|Module       |Dimensions (W×D×H)|
|-------------|------------------|
|Brain        |~90 × 90 × 35mm   |
|Knob+Slider  |~90 × 90 × 130mm  |
|Button Matrix|~90 × 90 × 25mm   |
|iPhone Dock  |~90 × 90 × 100mm  |

-----

## Build status

- [x] System architecture
- [x] Pogo pin connector spec
- [x] I²C addressing scheme
- [x] Fault tolerance design (heartbeat, recovery, hot-plug)
- [x] Brain prototype (ESP32-S3 + 1602A LCD test build)
- [x] Web configuration interface (prototype)
- [x] HID key mapping with combo parser
- [x] Profile system with flash storage
- [ ] Companion app — Deck mode + Config mode (in progress)
- [ ] Brain PCB layout (KiCad)
- [ ] Knob+Slider PCB layout
- [ ] Button Matrix PCB layout
- [ ] iPhone Dock design (Qi coil placement, NFC window, independent power input)
- [ ] Module co-processor firmware (ATtiny85 / CH32V003)
- [ ] CNC enclosure drawings (Fusion 360)
- [ ] Full prototype build
- [ ] STA/AP auto-fallback WiFi + QR pairing firmware

-----

## Tech stack

|Layer     |Technology                                     |
|----------|-----------------------------------------------|
|Brain MCU |ESP32-S3 DevKit C, Arduino framework           |
|Module MCU|ATtiny85 or CH32V003                           |
|Display   |SH1106 OLED 128×64 (production) / 1602A (proto)|
|RGB       |WS2812B addressable LEDs                       |
|ADC       |ADS1115 (fader reading on Knob+Slider)         |
|Bus buffer|PCA9515 per connector port                     |
|Shift reg |74HC165 (Button Matrix)                        |
|Power reg |AMS1117 3.3V LDO per module                    |
|Charging  |Qi wireless TX coil + IC (iPhone Dock, charging variant only — own back-panel USB-C supply)|
|NFC       |NTAG213/215 (iPhone Dock auto-launch)           |
|USB HID   |ESP32-S3 native USB (no USB bridge chip)       |
|Networking|WiFi STA with AP fallback, mDNS + QR pairing    |
|Config UI |Vanilla JS served from ESP32 over WiFi (web), SwiftUI (app)|
|Storage   |ESP32 NVS (non-volatile flash)                 |

-----

## Inspirations

- [Ocreeb MK2](https://www.instructables.com/Modular-Macro-Keyboard-System-Ocreeb-MK2/) — DIY modular macro pad with magnetic I²C connectors
- [Modue](https://modue.com) — commercial modular control deck with CNC aluminum and motorized faders
- [k.no.b.less by Work Louder](https://knob.design) — magnetic numpad + knob + slider system
- [Monogram Creative Console](https://monogramcc.com) — the original inspiration for magnetic modular control surfaces

-----

*Built by ByteVortex*
