// ============================================================
//  CLIQMOD — Brain Module Firmware v0.3
//  ESP32-S3 DevKit C — Arduino IDE
// ============================================================
//
//  LIBRARIES (install via Library Manager):
//    - hd44780          by Bill Perry
//    - ArduinoJson      by Benoit Blanchon
//    - ESP32 core       by Espressif (includes WiFi, WebServer, USB HID)
//
//  BOARD SETTINGS:
//    Board:             ESP32S3 Dev Module
//    USB Mode:          USB-OTG
//    USB CDC On Boot:   Enabled
//    Partition Scheme:  Huge APP (3MB No OTA)
//
// ============================================================
//  WIRING
// ============================================================
//
//  1602A LCD (I2C backpack PCF8574)
//    VCC → 5V
//    GND → GND
//    SDA → GPIO 8
//    SCL → GPIO 9
//
//  Rotary Encoder EC11
//    CLK → GPIO 4
//    DT  → GPIO 5
//    SW  → GPIO 6
//    VCC → 3.3V
//    GND → GND
//
//  Left button  → GPIO 7  + GND
//  Right button → GPIO 15 + GND
//
//  Left module pogo pins
//    VCC 5V → 5V
//    GND    → GND
//    SDA    → GPIO 35  (+ 4.7k to 3.3V)
//    SCL    → GPIO 36  (+ 4.7k to 3.3V)
//    INT    → GPIO 16
//    RGB    → not connected yet
//    ADDR   → GPIO 18
//
//  Right module pogo pins
//    VCC 5V → 5V
//    GND    → GND
//    SDA    → GPIO 37  (+ 4.7k to 3.3V)
//    SCL    → GPIO 38  (+ 4.7k to 3.3V)
//    INT    → GPIO 17
//    RGB    → not connected yet
//    ADDR   → GPIO 21
//
//  USB-C: use the UPPER port (native USB) for HID to PC
//         use the LOWER port for flashing only
//
// ============================================================

#include <Wire.h>
#include <hd44780.h>
#include <hd44780ioClass/hd44780_I2Cexp.h>
#include <WiFi.h>
#include <WebServer.h>
#include <Preferences.h>
#include <ArduinoJson.h>
#include <USB.h>
#include <USBHIDKeyboard.h>

// ── Version ──────────────────────────────────────────────────
#define FW_VERSION "0.3.0"

// ── LCD ──────────────────────────────────────────────────────
#define LCD_COLS 16
#define LCD_ROWS 2

// ── Pins ─────────────────────────────────────────────────────
#define ENC_CLK    4
#define ENC_DT     5
#define ENC_SW     6
#define BTN_LEFT   7
#define BTN_RIGHT  15
#define SDA_LCD    8
#define SCL_LCD    9
#define SDA_LEFT   35
#define SCL_LEFT   36
#define SDA_RIGHT  37
#define SCL_RIGHT  38
#define INT_LEFT   16
#define INT_RIGHT  17
#define ADDR_LEFT  18
#define ADDR_RIGHT 21

// ── I2C module addresses ──────────────────────────────────────
#define ADDR_L1 0x10
#define ADDR_L2 0x11
#define ADDR_L3 0x12
#define ADDR_R1 0x20
#define ADDR_R2 0x21
#define ADDR_R3 0x22

// ── Timing ───────────────────────────────────────────────────
#define HEARTBEAT_MS     500
#define LONG_PRESS_MS    700
#define DEBOUNCE_MS      25
#define DISPLAY_PERIOD   120
#define EVENT_DISPLAY_MS 2000

// ── WiFi ─────────────────────────────────────────────────────
#define AP_SSID "Cliqmod"
#define AP_PASS "cliqmod1"
#define AP_IP   IPAddress(192, 168, 4, 1)

// ── HID action types ─────────────────────────────────────────
#define ACTION_NONE   0
#define ACTION_KEY    1   // single key
#define ACTION_COMBO  2   // modifier + key  e.g. CTRL+Z
#define ACTION_STRING 3   // type a string

// ── HID modifier flags (match USB HID spec) ──────────────────
#define MOD_CTRL  0x01
#define MOD_SHIFT 0x02
#define MOD_ALT   0x04
#define MOD_GUI   0x08

// ── Module types ─────────────────────────────────────────────
#define MODULE_UNKNOWN     0x00
#define MODULE_KNOB_SLIDER 0x01
#define MODULE_BUTTONS     0x02

// ── Module event types ───────────────────────────────────────
#define EVT_ENC_TURN      0x01
#define EVT_ENC_CLICK     0x02
#define EVT_ENC_HOLD_TURN 0x03
#define EVT_FADER         0x04
#define EVT_BUTTON        0x05

// ── Brain encoder click sources ──────────────────────────────
// Brain encoder click can also trigger a macro
#define SRC_BRAIN_ENC_CLICK 0xF0
#define SRC_BRAIN_BTN_LEFT  0xF1
#define SRC_BRAIN_BTN_RIGHT 0xF2

// ── Limits ───────────────────────────────────────────────────
#define MAX_PROFILES 8
#define MAX_MAPPINGS 48  // per profile

// ============================================================
//  DATA STRUCTURES
// ============================================================

struct HIDAction {
  uint8_t type;        // ACTION_*
  uint8_t modifier;    // MOD_* flags combined
  uint8_t keycode;     // raw HID keycode
  char    str[20];     // for ACTION_STRING
};

// A mapping binds a source event to a HID action
struct Mapping {
  uint8_t   source;      // module address OR SRC_BRAIN_*
  uint8_t   controlId;   // which control on that module (0 for brain)
  uint8_t   eventType;   // EVT_* or 0 for brain click
  HIDAction action;
  char      label[20];   // shown on LCD and web UI
  bool      active;      // slot in use
};

struct Profile {
  char    name[20];
  Mapping mappings[MAX_MAPPINGS];
};

struct Module {
  bool    present;
  uint8_t address;
  uint8_t type;
  char    label[16];
  int     encValues[4];
  int     faderValues[4];
};

// ============================================================
//  GLOBALS
// ============================================================

TwoWire        WireLeft  = TwoWire(1);
TwoWire        WireRight = TwoWire(2);
hd44780_I2Cexp lcd;
USBHIDKeyboard Keyboard;
WebServer      server(80);
Preferences    prefs;

Profile profiles[MAX_PROFILES];
int     profileCount  = 0;
int     activeProfile = 0;

Module leftModules[3];
Module rightModules[3];

// Encoder state machine
volatile bool intLeftFlag  = false;
volatile bool intRightFlag = false;

// Button debounce
bool          encBtnState  = false;
bool          encBtnLast   = false;
unsigned long encBtnTime   = 0;
bool          encLongFired = false;

bool          btnLState  = false;
bool          btnLLast   = false;
unsigned long btnLTime   = 0;

bool          btnRState  = false;
bool          btnRLast   = false;
unsigned long btnRTime   = 0;

// Display
unsigned long lastDisplayUpdate = 0;
bool          displayDirty      = true;
bool          lcdNeedsClear     = false;

// Heartbeat
unsigned long lastHeartbeat = 0;

// Menu
enum Screen {
  SCR_HOME,
  SCR_MENU,
  SCR_PROFILES,
  SCR_MAPPINGS,
  SCR_MAPPING_DETAIL,
  SCR_WIFI,
  SCR_ABOUT
};
Screen  currentScreen  = SCR_HOME;
Screen  prevScreen     = SCR_HOME;
int     menuIndex      = 0;
int     mappingIndex   = 0;  // which mapping is selected

// Home screen page (0=profile/modules, 1=last event)
int homePage = 0;

// Event feedback
String        lastEventLabel = "";
unsigned long lastEventTime  = 0;

// Startup
bool          startupDone = false;
unsigned long startupTime = 0;
int           startupDots = 0;

// Menu items on SCR_MENU
const char* menuItems[] = { "Profiles", "Mappings", "Modules", "WiFi", "About" };
const int   MENU_COUNT  = 5;

// ============================================================
//  CUSTOM LCD CHARS
// ============================================================

byte charRight[8] = {0x00,0x08,0x0C,0x0E,0x0C,0x08,0x00,0x00};
byte charFull[8]  = {0x00,0x1F,0x1F,0x1F,0x1F,0x1F,0x00,0x00};
byte charEmpty[8] = {0x00,0x1F,0x11,0x11,0x11,0x1F,0x00,0x00};
byte charCheck[8] = {0x00,0x01,0x03,0x16,0x1C,0x08,0x00,0x00};

#define C_RIGHT 0
#define C_FULL  1
#define C_EMPTY 2
#define C_CHECK 3

// ============================================================
//  FLASH STORAGE
// ============================================================

void initDefaultProfiles() {
  profileCount = 5;
  const char* names[] = { "Default", "DAW", "Video Edit", "Gaming", "Custom" };
  for (int i = 0; i < profileCount; i++) {
    strncpy(profiles[i].name, names[i], 19);
    for (int j = 0; j < MAX_MAPPINGS; j++) {
      profiles[i].mappings[j].active = false;
    }
  }

  // Add a default brain encoder click macro to profile 0
  // Ctrl+Z (undo) as an example
  profiles[0].mappings[0].active     = true;
  profiles[0].mappings[0].source     = SRC_BRAIN_ENC_CLICK;
  profiles[0].mappings[0].controlId  = 0;
  profiles[0].mappings[0].eventType  = 0;
  profiles[0].mappings[0].action     = { ACTION_COMBO, MOD_CTRL, 'z', "" };
  strncpy(profiles[0].mappings[0].label, "Undo", 19);

  // Left button = Ctrl+Y (redo)
  profiles[0].mappings[1].active     = true;
  profiles[0].mappings[1].source     = SRC_BRAIN_BTN_LEFT;
  profiles[0].mappings[1].controlId  = 0;
  profiles[0].mappings[1].eventType  = 0;
  profiles[0].mappings[1].action     = { ACTION_COMBO, MOD_CTRL, 'y', "" };
  strncpy(profiles[0].mappings[1].label, "Redo", 19);

  // Right button = Ctrl+S (save)
  profiles[0].mappings[2].active     = true;
  profiles[0].mappings[2].source     = SRC_BRAIN_BTN_RIGHT;
  profiles[0].mappings[2].controlId  = 0;
  profiles[0].mappings[2].eventType  = 0;
  profiles[0].mappings[2].action     = { ACTION_COMBO, MOD_CTRL, 's', "" };
  strncpy(profiles[0].mappings[2].label, "Save", 19);
}

void saveProfiles() {
  prefs.begin("cliqmod", false);
  prefs.putInt("pCount", profileCount);
  prefs.putInt("pActive", activeProfile);
  for (int i = 0; i < profileCount; i++) {
    char key[12]; sprintf(key, "p%d", i);
    prefs.putBytes(key, &profiles[i], sizeof(Profile));
  }
  prefs.end();
  Serial.println("[NVS] Saved");
}

void loadProfiles() {
  prefs.begin("cliqmod", true);
  int count = prefs.getInt("pCount", 0);
  if (count == 0) {
    prefs.end();
    initDefaultProfiles();
    return;
  }
  profileCount  = count;
  activeProfile = prefs.getInt("pActive", 0);
  for (int i = 0; i < profileCount; i++) {
    char key[12]; sprintf(key, "p%d", i);
    prefs.getBytes(key, &profiles[i], sizeof(Profile));
  }
  prefs.end();
  Serial.printf("[NVS] Loaded %d profiles\n", profileCount);
}

// ============================================================
//  HID OUTPUT
// ============================================================

// Parse a keycombo string like "CTRL+Z" or "SHIFT+ALT+F4" into HIDAction
HIDAction parseKeyCombo(const char* combo) {
  HIDAction a = {ACTION_NONE, 0, 0, ""};
  if (strlen(combo) == 0) return a;

  char buf[64];
  strncpy(buf, combo, 63);
  buf[63] = '\0';

  // Convert to uppercase for parsing
  for (int i = 0; buf[i]; i++) buf[i] = toupper(buf[i]);

  uint8_t mod = 0;
  char *token = strtok(buf, "+");
  char *lastToken = nullptr;

  while (token != nullptr) {
    if      (strcmp(token, "CTRL")  == 0) mod |= MOD_CTRL;
    else if (strcmp(token, "SHIFT") == 0) mod |= MOD_SHIFT;
    else if (strcmp(token, "ALT")   == 0) mod |= MOD_ALT;
    else if (strcmp(token, "GUI")   == 0) mod |= MOD_GUI;
    else if (strcmp(token, "WIN")   == 0) mod |= MOD_GUI;
    else lastToken = token;
    token = strtok(nullptr, "+");
  }

  if (lastToken == nullptr) return a;

  a.modifier = mod;

  // Single character key
  if (strlen(lastToken) == 1) {
    a.type    = (mod > 0) ? ACTION_COMBO : ACTION_KEY;
    a.keycode = tolower(lastToken[0]);
    return a;
  }

  // Special keys
  if      (strcmp(lastToken, "SPACE")  == 0) { a.type = ACTION_KEY; a.keycode = ' '; }
  else if (strcmp(lastToken, "ENTER")  == 0) { a.type = ACTION_KEY; a.keycode = KEY_RETURN; }
  else if (strcmp(lastToken, "ESC")    == 0) { a.type = ACTION_KEY; a.keycode = KEY_ESC; }
  else if (strcmp(lastToken, "TAB")    == 0) { a.type = ACTION_KEY; a.keycode = KEY_TAB; }
  else if (strcmp(lastToken, "DELETE") == 0) { a.type = ACTION_KEY; a.keycode = KEY_DELETE; }
  else if (strcmp(lastToken, "BKSP")   == 0) { a.type = ACTION_KEY; a.keycode = KEY_BACKSPACE; }
  else if (strcmp(lastToken, "UP")     == 0) { a.type = ACTION_KEY; a.keycode = KEY_UP_ARROW; }
  else if (strcmp(lastToken, "DOWN")   == 0) { a.type = ACTION_KEY; a.keycode = KEY_DOWN_ARROW; }
  else if (strcmp(lastToken, "LEFT")   == 0) { a.type = ACTION_KEY; a.keycode = KEY_LEFT_ARROW; }
  else if (strcmp(lastToken, "RIGHT")  == 0) { a.type = ACTION_KEY; a.keycode = KEY_RIGHT_ARROW; }
  else if (lastToken[0] == 'F' && strlen(lastToken) <= 3) {
    int fn = atoi(lastToken + 1);
    if (fn >= 1 && fn <= 12) {
      a.type    = ACTION_KEY;
      a.keycode = KEY_F1 + (fn - 1);
    }
  }

  if (mod > 0 && a.type == ACTION_KEY) a.type = ACTION_COMBO;
  return a;
}

void executeAction(HIDAction &action) {
  switch (action.type) {
    case ACTION_NONE: break;
    case ACTION_KEY:
      Keyboard.press(action.keycode);
      delay(15);
      Keyboard.release(action.keycode);
      break;
    case ACTION_COMBO: {
      // Map modifier flags to actual modifier keycodes
      if (action.modifier & MOD_CTRL)  Keyboard.press(KEY_LEFT_CTRL);
      if (action.modifier & MOD_SHIFT) Keyboard.press(KEY_LEFT_SHIFT);
      if (action.modifier & MOD_ALT)   Keyboard.press(KEY_LEFT_ALT);
      if (action.modifier & MOD_GUI)   Keyboard.press(KEY_LEFT_GUI);
      delay(5);
      Keyboard.press(action.keycode);
      delay(15);
      Keyboard.releaseAll();
      break;
    }
    case ACTION_STRING:
      Keyboard.print(action.str);
      break;
  }
}

void fireMappingForSource(uint8_t source, uint8_t controlId, uint8_t eventType) {
  Profile &p = profiles[activeProfile];
  for (int i = 0; i < MAX_MAPPINGS; i++) {
    Mapping &m = p.mappings[i];
    if (!m.active) continue;
    if (m.source == source &&
        m.controlId == controlId &&
        m.eventType == eventType) {
      executeAction(m.action);
      lastEventLabel = String(m.label);
      lastEventTime  = millis();
      displayDirty   = true;
      Serial.printf("[MACRO] Fired: %s\n", m.label);
      return;
    }
  }
  Serial.printf("[MACRO] No mapping for src=0x%02X ctrl=%d evt=0x%02X\n",
                source, controlId, eventType);
}

// ============================================================
//  I2C / MODULES
// ============================================================

void recoverI2CBus(TwoWire &bus, int sda, int scl) {
  pinMode(scl, OUTPUT);
  for (int i = 0; i < 9; i++) {
    digitalWrite(scl, HIGH); delayMicroseconds(5);
    digitalWrite(scl, LOW);  delayMicroseconds(5);
  }
  pinMode(sda, OUTPUT);
  digitalWrite(sda, LOW);  delayMicroseconds(5);
  digitalWrite(scl, HIGH); delayMicroseconds(5);
  digitalWrite(sda, HIGH); delayMicroseconds(5);
  bus.begin(sda, scl, 100000);
  Serial.println("[I2C] Recovered");
}

void assignAddresses(int addrPin, TwoWire &bus,
                     int sda, int scl, Module *mods) {
  for (int pos = 0; pos < 3; pos++) {
    digitalWrite(addrPin, HIGH); delayMicroseconds(500);
    digitalWrite(addrPin, LOW);
    delay(10);

    uint8_t addr = (addrPin == ADDR_LEFT) ? (0x10 + pos) : (0x20 + pos);
    bus.beginTransmission(addr);
    uint8_t err = bus.endTransmission();

    if (err == 0) {
      mods[pos].present = true;
      mods[pos].address = addr;

      bus.beginTransmission(addr);
      bus.write(0x01);
      bus.endTransmission(false);
      bus.requestFrom(addr, (uint8_t)1);
      mods[pos].type = bus.available() ? bus.read() : MODULE_UNKNOWN;

      bus.beginTransmission(addr);
      bus.write(0x02);
      bus.endTransmission(false);
      bus.requestFrom(addr, (uint8_t)15);
      int li = 0;
      while (bus.available() && li < 15) mods[pos].label[li++] = bus.read();
      mods[pos].label[li] = '\0';
      if (li == 0) {
        switch (mods[pos].type) {
          case MODULE_KNOB_SLIDER: strcpy(mods[pos].label, "K+Slide"); break;
          case MODULE_BUTTONS:     strcpy(mods[pos].label, "Buttons"); break;
          default:                 strcpy(mods[pos].label, "Unknown"); break;
        }
      }
      Serial.printf("[MOD] %s pos=%d addr=0x%02X\n",
                    mods[pos].label, pos, addr);
    } else {
      mods[pos].present = false;
      mods[pos].address = 0;
      mods[pos].type    = MODULE_UNKNOWN;
      strcpy(mods[pos].label, "");
    }
  }
  displayDirty = true;
}

void pingModules() {
  bool changed = false;
  for (int i = 0; i < 3; i++) {
    if (leftModules[i].present) {
      WireLeft.beginTransmission(leftModules[i].address);
      if (WireLeft.endTransmission() != 0) {
        leftModules[i].present = false; changed = true;
        Serial.printf("[PING] L%d lost\n", i);
      }
    }
    if (rightModules[i].present) {
      WireRight.beginTransmission(rightModules[i].address);
      if (WireRight.endTransmission() != 0) {
        rightModules[i].present = false; changed = true;
        Serial.printf("[PING] R%d lost\n", i);
      }
    }
  }
  if (changed) displayDirty = true;
}

void pollModuleData(TwoWire &bus, Module *mods) {
  for (int i = 0; i < 3; i++) {
    if (!mods[i].present) continue;
    bus.beginTransmission(mods[i].address);
    bus.write(0x00);
    if (bus.endTransmission(false) != 0) continue;
    bus.requestFrom(mods[i].address, (uint8_t)4);
    if (bus.available() < 4) continue;

    uint8_t evtType  = bus.read();
    uint8_t ctrlId   = bus.read();
    int8_t  delta    = (int8_t)bus.read();
    uint8_t value    = bus.read();
    if (evtType == 0) continue;

    if (evtType == EVT_ENC_TURN || evtType == EVT_ENC_HOLD_TURN) {
      if (ctrlId < 4)
        mods[i].encValues[ctrlId] = constrain(mods[i].encValues[ctrlId] + delta, 0, 100);
    } else if (evtType == EVT_FADER && ctrlId < 4) {
      mods[i].faderValues[ctrlId] = value;
    }

    fireMappingForSource(mods[i].address, ctrlId, evtType);
  }
}

void IRAM_ATTR onIntLeft()  { intLeftFlag  = true; }
void IRAM_ATTR onIntRight() { intRightFlag = true; }

// ============================================================
//  INPUT
// ============================================================

void readEncoder() {
  static uint8_t lastState = 0b11;
  uint8_t clk   = digitalRead(ENC_CLK);
  uint8_t dt    = digitalRead(ENC_DT);
  uint8_t state = (clk << 1) | dt;

  if (state == lastState) return;

  if (lastState == 0b11) {
    bool cw = (state == 0b10);
    bool ccw = (state == 0b01);

    if (cw || ccw) {
      int dir = cw ? 1 : -1;

      switch (currentScreen) {
        case SCR_HOME:
          activeProfile = (activeProfile + dir + profileCount) % profileCount;
          displayDirty  = true;
          break;
        case SCR_MENU:
          menuIndex    = (menuIndex + dir + MENU_COUNT) % MENU_COUNT;
          displayDirty = true;
          break;
        case SCR_PROFILES:
          menuIndex    = constrain(menuIndex + dir, 0, profileCount - 1);
          displayDirty = true;
          break;
        case SCR_MAPPINGS:
          mappingIndex = constrain(mappingIndex + dir, 0, MAX_MAPPINGS - 1);
          displayDirty = true;
          break;
        default:
          break;
      }
    }
  }
  lastState = state;
}

void goToScreen(Screen s) {
  prevScreen    = currentScreen;
  currentScreen = s;
  menuIndex     = 0;
  lcdNeedsClear = true;
  displayDirty  = true;
}

void readButtons() {
  unsigned long now = millis();

  // ── Encoder button ────────────────────────────────────────
  bool encRaw = !digitalRead(ENC_SW);
  if (encRaw != encBtnLast) { encBtnTime = now; encBtnLast = encRaw; }
  if ((now - encBtnTime) > DEBOUNCE_MS) {
    if (encRaw != encBtnState) {
      encBtnState = encRaw;
      if (encBtnState) {
        encLongFired = false;
      } else {
        if (!encLongFired) {
          // Short click — context action
          switch (currentScreen) {
            case SCR_HOME:
              goToScreen(SCR_MENU);
              break;
            case SCR_MENU:
              switch (menuIndex) {
                case 0: goToScreen(SCR_PROFILES); break;
                case 1: goToScreen(SCR_MAPPINGS); break;
                case 2: goToScreen(SCR_ABOUT);    break; // modules shown in about for now
                case 3: goToScreen(SCR_WIFI);     break;
                case 4: goToScreen(SCR_ABOUT);    break;
              }
              break;
            case SCR_PROFILES:
              activeProfile = menuIndex;
              saveProfiles();
              goToScreen(SCR_HOME);
              break;
            case SCR_MAPPINGS:
              goToScreen(SCR_MAPPING_DETAIL);
              break;
            default:
              goToScreen(SCR_HOME);
              break;
          }
        }
      }
    }
    // Long press → fire brain encoder macro OR go home
    if (encBtnState && !encLongFired && (now - encBtnTime) > LONG_PRESS_MS) {
      encLongFired = true;
      if (currentScreen == SCR_HOME) {
        // Long press on home fires the brain encoder click macro
        fireMappingForSource(SRC_BRAIN_ENC_CLICK, 0, 0);
      } else {
        goToScreen(SCR_HOME);
      }
    }
  }

  // ── Left button ───────────────────────────────────────────
  bool lRaw = !digitalRead(BTN_LEFT);
  if (lRaw != btnLLast) { btnLTime = now; btnLLast = lRaw; }
  if ((now - btnLTime) > DEBOUNCE_MS && lRaw != btnLState) {
    btnLState = lRaw;
    if (btnLState) {
      if (currentScreen == SCR_HOME) {
        // Short click on home fires left button macro
        fireMappingForSource(SRC_BRAIN_BTN_LEFT, 0, 0);
      } else {
        goToScreen(SCR_HOME);
      }
    }
  }

  // ── Right button ──────────────────────────────────────────
  bool rRaw = !digitalRead(BTN_RIGHT);
  if (rRaw != btnRLast) { btnRTime = now; btnRLast = rRaw; }
  if ((now - btnRTime) > DEBOUNCE_MS && rRaw != btnRState) {
    btnRState = rRaw;
    if (btnRState) {
      if (currentScreen == SCR_HOME) {
        // Short click on home fires right button macro
        fireMappingForSource(SRC_BRAIN_BTN_RIGHT, 0, 0);
      } else {
        // In menus, right goes forward/next
        menuIndex = constrain(menuIndex + 1, 0, 20);
        displayDirty = true;
      }
    }
  }
}

// ============================================================
//  LCD DISPLAY
// ============================================================

// Helper: print exactly n chars, padding with spaces
void lcdPrint(const char *str, int maxLen) {
  int len = strlen(str);
  for (int i = 0; i < maxLen; i++) {
    if (i < len) lcd.print(str[i]);
    else         lcd.print(' ');
  }
}

void drawStartup() {
  lcd.setCursor(0, 0);
  lcdPrint("  CLIQMOD v" FW_VERSION, 16);
  lcd.setCursor(0, 1);
  lcd.print("Starting");
  for (int i = 0; i < min(startupDots, 8); i++) lcd.print('.');
  for (int i = startupDots; i < 8; i++) lcd.print(' ');
}

void drawHome() {
  // Row 0: profile name centered with arrows
  lcd.setCursor(0, 0);
  lcd.write(C_RIGHT);
  lcd.print(' ');
  // Center profile name in 12 chars
  char name[13];
  strncpy(name, profiles[activeProfile].name, 12);
  name[12] = '\0';
  int pad  = (12 - strlen(name)) / 2;
  for (int i = 0; i < pad; i++) lcd.print(' ');
  lcd.print(name);
  for (int i = pad + strlen(name); i < 12; i++) lcd.print(' ');
  lcd.print(' ');
  lcd.write(C_RIGHT);

  // Row 1: module slots + profile index
  if (lastEventLabel.length() > 0 &&
      (millis() - lastEventTime) < EVENT_DISPLAY_MS) {
    lcd.setCursor(0, 1);
    lcdPrint(lastEventLabel.c_str(), 16);
  } else {
    lcd.setCursor(0, 1);
    lcd.print("L:");
    for (int i = 0; i < 3; i++) lcd.write(leftModules[i].present  ? C_FULL : C_EMPTY);
    lcd.print(" R:");
    for (int i = 0; i < 3; i++) lcd.write(rightModules[i].present ? C_FULL : C_EMPTY);
    char pnum[5]; sprintf(pnum, " %d/%d", activeProfile + 1, profileCount);
    lcd.print(pnum);
  }
}

void drawMenu() {
  // Row 0: title
  lcd.setCursor(0, 0);
  lcdPrint("-- MENU --      ", 16);
  // Row 1: current item with arrow
  lcd.setCursor(0, 1);
  lcd.write(C_RIGHT);
  lcd.print(' ');
  lcdPrint(menuItems[menuIndex], 13);
  // Show index
  char idx[4]; sprintf(idx, "%d/%d", menuIndex + 1, MENU_COUNT);
  lcd.setCursor(13, 1);
  lcd.print(idx);
}

void drawProfiles() {
  lcd.setCursor(0, 0);
  lcdPrint("SELECT PROFILE  ", 16);
  lcd.setCursor(0, 1);
  if (menuIndex == activeProfile) lcd.write(C_CHECK);
  else                            lcd.write(C_RIGHT);
  lcd.print(' ');
  char buf[13]; sprintf(buf, "%-12s", profiles[menuIndex].name);
  lcdPrint(buf, 12);
  char idx[4]; sprintf(idx, "%d/%d", menuIndex + 1, profileCount);
  lcd.setCursor(13, 1);
  lcd.print(idx);
}

// Count active mappings
int activeMappingCount() {
  int n = 0;
  for (int i = 0; i < MAX_MAPPINGS; i++)
    if (profiles[activeProfile].mappings[i].active) n++;
  return n;
}

// Get Nth active mapping index
int nthActiveMapping(int n) {
  int count = 0;
  for (int i = 0; i < MAX_MAPPINGS; i++) {
    if (profiles[activeProfile].mappings[i].active) {
      if (count == n) return i;
      count++;
    }
  }
  return -1;
}

void drawMappings() {
  int total = activeMappingCount();
  lcd.setCursor(0, 0);
  char hdr[17]; sprintf(hdr, "MAPPINGS [%d]    ", total);
  lcdPrint(hdr, 16);

  lcd.setCursor(0, 1);
  if (total == 0) {
    lcdPrint("None configured ", 16);
    return;
  }
  int idx = nthActiveMapping(menuIndex % total);
  if (idx < 0) return;
  Mapping &m = profiles[activeProfile].mappings[idx];
  lcd.write(C_RIGHT);
  lcd.print(' ');
  lcdPrint(m.label, 11);
  char num[4]; sprintf(num, "%d/%d", (menuIndex % total) + 1, total);
  lcd.setCursor(13, 1);
  lcd.print(num);
}

void drawMappingDetail() {
  int total = activeMappingCount();
  int idx   = nthActiveMapping(menuIndex % max(total, 1));
  if (idx < 0 || !profiles[activeProfile].mappings[idx].active) {
    lcd.setCursor(0, 0); lcdPrint("No mapping here ", 16);
    lcd.setCursor(0, 1); lcdPrint("Hold=back       ", 16);
    return;
  }
  Mapping &m = profiles[activeProfile].mappings[idx];
  lcd.setCursor(0, 0);
  lcdPrint(m.label, 16);
  lcd.setCursor(0, 1);

  // Show source description
  char src[17];
  if      (m.source == SRC_BRAIN_ENC_CLICK) strcpy(src, "Brain Enc Click ");
  else if (m.source == SRC_BRAIN_BTN_LEFT)  strcpy(src, "Brain Btn Left  ");
  else if (m.source == SRC_BRAIN_BTN_RIGHT) strcpy(src, "Brain Btn Right ");
  else                                      sprintf(src, "Mod 0x%02X       ", m.source);
  lcdPrint(src, 16);
}

void drawWifi() {
  if (menuIndex == 0) {
    lcd.setCursor(0, 0); lcdPrint("SSID: Cliqmod   ", 16);
    lcd.setCursor(0, 1); lcdPrint("Pass: cliqmod1  ", 16);
  } else {
    lcd.setCursor(0, 0); lcdPrint("Open browser:   ", 16);
    lcd.setCursor(0, 1); lcdPrint("192.168.4.1     ", 16);
  }
}

void drawAbout() {
  lcd.setCursor(0, 0);
  char r0[17]; sprintf(r0, "CLIQMOD v%-7s", FW_VERSION);
  lcdPrint(r0, 16);
  lcd.setCursor(0, 1);
  int lMods = 0, rMods = 0;
  for (int i = 0; i < 3; i++) {
    if (leftModules[i].present)  lMods++;
    if (rightModules[i].present) rMods++;
  }
  char r1[17]; sprintf(r1, "L:%d R:%d Prof:%d  ", lMods, rMods, profileCount);
  lcdPrint(r1, 16);
}

void updateDisplay() {
  if (!displayDirty) return;
  unsigned long now = millis();
  if ((now - lastDisplayUpdate) < DISPLAY_PERIOD) return;
  lastDisplayUpdate = millis();
  displayDirty = false;

  if (lcdNeedsClear) {
    lcd.clear();
    lcdNeedsClear = false;
    delay(5);
  }

  if (!startupDone) { drawStartup(); return; }

  switch (currentScreen) {
    case SCR_HOME:           drawHome();          break;
    case SCR_MENU:           drawMenu();          break;
    case SCR_PROFILES:       drawProfiles();      break;
    case SCR_MAPPINGS:       drawMappings();      break;
    case SCR_MAPPING_DETAIL: drawMappingDetail(); break;
    case SCR_WIFI:           drawWifi();          break;
    case SCR_ABOUT:          drawAbout();         break;
  }
}

// ============================================================
//  WEB SERVER
// ============================================================

// Helper: modifier byte → string like "CTRL+SHIFT"
String modToString(uint8_t mod) {
  String s = "";
  if (mod & MOD_CTRL)  { if (s.length()) s += "+"; s += "CTRL";  }
  if (mod & MOD_SHIFT) { if (s.length()) s += "+"; s += "SHIFT"; }
  if (mod & MOD_ALT)   { if (s.length()) s += "+"; s += "ALT";   }
  if (mod & MOD_GUI)   { if (s.length()) s += "+"; s += "GUI";   }
  return s;
}

// Helper: HIDAction → keycombo string like "CTRL+Z"
String actionToComboString(HIDAction &a) {
  if (a.type == ACTION_STRING) return String(a.str);
  if (a.type == ACTION_NONE)   return "";
  String s = modToString(a.modifier);
  if (a.keycode >= 32 && a.keycode < 127) {
    if (s.length()) s += "+";
    s += (char)toupper(a.keycode);
  } else if (a.keycode >= KEY_F1 && a.keycode <= KEY_F12) {
    if (s.length()) s += "+";
    s += "F"; s += String(a.keycode - KEY_F1 + 1);
  }
  return s;
}

String sourceToString(uint8_t src) {
  if (src == SRC_BRAIN_ENC_CLICK) return "Brain Enc Click";
  if (src == SRC_BRAIN_BTN_LEFT)  return "Brain Btn Left";
  if (src == SRC_BRAIN_BTN_RIGHT) return "Brain Btn Right";
  char buf[16]; sprintf(buf, "Module 0x%02X", src);
  return String(buf);
}

String buildStateJson() {
  DynamicJsonDocument doc(8192);
  doc["activeProfile"] = activeProfile;
  doc["firmware"]      = FW_VERSION;

  JsonArray profArr = doc.createNestedArray("profiles");
  for (int i = 0; i < profileCount; i++) {
    JsonObject p = profArr.createNestedObject();
    p["name"] = profiles[i].name;
    JsonArray maps = p.createNestedArray("mappings");
    for (int j = 0; j < MAX_MAPPINGS; j++) {
      Mapping &m = profiles[i].mappings[j];
      if (!m.active) continue;
      JsonObject mo = maps.createNestedObject();
      mo["id"]      = j;
      mo["label"]   = m.label;
      mo["source"]  = sourceToString(m.source);
      mo["srcCode"] = m.source;
      mo["keycombo"] = actionToComboString(m.action);
      mo["isString"] = (m.action.type == ACTION_STRING);
    }
  }

  JsonArray modArr = doc.createNestedArray("modules");
  for (int i = 0; i < 3; i++) {
    JsonObject m = modArr.createNestedObject();
    m["present"] = leftModules[i].present;
    m["label"]   = leftModules[i].present ? leftModules[i].label : "";
    m["side"]    = "L"; m["pos"] = i + 1;
  }
  for (int i = 0; i < 3; i++) {
    JsonObject m = modArr.createNestedObject();
    m["present"] = rightModules[i].present;
    m["label"]   = rightModules[i].present ? rightModules[i].label : "";
    m["side"]    = "R"; m["pos"] = i + 1;
  }

  String out; serializeJson(doc, out); return out;
}

// Clean HTML — no emojis, no unicode, plain ASCII only
const char HTML_INDEX[] PROGMEM = R"rawhtml(<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Cliqmod</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;background:#0f0f0f;color:#e8e8e8;padding:20px;max-width:600px;margin:0 auto}
h1{font-size:22px;font-weight:700;letter-spacing:2px;margin-bottom:2px;color:#fff}
.sub{color:#555;font-size:12px;margin-bottom:24px;letter-spacing:1px}
.card{background:#181818;border:1px solid #252525;border-radius:10px;padding:16px;margin-bottom:14px}
.card-title{font-size:11px;font-weight:600;color:#555;text-transform:uppercase;letter-spacing:1.5px;margin-bottom:12px}
.profile-list{display:flex;flex-wrap:wrap;gap:8px}
.pbtn{padding:7px 14px;border-radius:7px;border:1px solid #2a2a2a;background:#202020;color:#ccc;cursor:pointer;font-size:13px;transition:all .15s}
.pbtn:hover{border-color:#444;color:#fff}
.pbtn.active{background:#fff;color:#111;border-color:#fff;font-weight:600}
.module-grid{display:grid;grid-template-columns:1fr 1fr;gap:8px}
.mod-item{display:flex;align-items:center;gap:8px;padding:8px 10px;border-radius:7px;background:#111;border:1px solid #1e1e1e}
.mod-badge{font-size:11px;font-weight:700;color:#555;min-width:24px}
.mod-badge.on{color:#4ade80}
.mod-name{font-size:12px;color:#888}
.mod-name.on{color:#ccc}
.dot{width:6px;height:6px;border-radius:50%;background:#4ade80;margin-left:auto}
.mapping-item{border:1px solid #1e1e1e;border-radius:8px;padding:12px;margin-bottom:8px;background:#111}
.mapping-header{display:flex;justify-content:space-between;align-items:center;margin-bottom:8px}
.mapping-label{font-size:13px;font-weight:600;color:#e8e8e8}
.mapping-src{font-size:11px;color:#555}
.mapping-fields{display:grid;grid-template-columns:1fr 1fr;gap:8px}
.field label{display:block;font-size:10px;color:#555;margin-bottom:4px;text-transform:uppercase;letter-spacing:1px}
input,select{width:100%;background:#1a1a1a;border:1px solid #2a2a2a;color:#e8e8e8;border-radius:6px;padding:7px 10px;font-size:13px;outline:none}
input:focus,select:focus{border-color:#444}
.btn{border:none;border-radius:7px;padding:9px 18px;font-size:13px;font-weight:600;cursor:pointer;transition:all .15s}
.btn-primary{background:#fff;color:#111}
.btn-primary:hover{background:#e8e8e8}
.btn-secondary{background:#1a1a1a;color:#888;border:1px solid #2a2a2a}
.btn-secondary:hover{color:#ccc;border-color:#444}
.btn-danger{background:#2a0a0a;color:#f87171;border:1px solid #3a1a1a}
.btn-danger:hover{background:#3a1010}
.btn-small{padding:5px 10px;font-size:12px}
.btn-row{display:flex;gap:8px;margin-top:12px;flex-wrap:wrap}
.src-select{display:grid;grid-template-columns:1fr 1fr 1fr;gap:6px;margin-bottom:8px}
.src-btn{padding:6px 8px;border-radius:6px;border:1px solid #2a2a2a;background:#1a1a1a;color:#888;cursor:pointer;font-size:11px;text-align:center;transition:all .15s}
.src-btn.active{border-color:#4ade80;color:#4ade80;background:#0a1a0a}
.empty-state{color:#444;font-size:13px;padding:16px 0;text-align:center}
.toast{position:fixed;bottom:20px;left:50%;transform:translateX(-50%);background:#fff;color:#111;padding:9px 20px;border-radius:8px;font-weight:600;font-size:13px;display:none;z-index:100;white-space:nowrap}
.sep{border:none;border-top:1px solid #1e1e1e;margin:12px 0}
.info-row{display:flex;justify-content:space-between;padding:5px 0;font-size:13px;border-bottom:1px solid #1a1a1a}
.info-row:last-child{border-bottom:none}
.info-val{color:#555}
</style>
</head>
<body>
<h1>CLIQMOD</h1>
<p class="sub" id="subline">connecting...</p>

<div class="card">
  <div class="card-title">Active Profile</div>
  <div class="profile-list" id="profileList"></div>
</div>

<div class="card">
  <div class="card-title">Modules</div>
  <div class="module-grid" id="moduleList"></div>
</div>

<div class="card">
  <div class="card-title">Mappings
    <span style="color:#333;margin-left:4px" id="profileNameBadge"></span>
  </div>
  <div id="mappingList"></div>
  <div class="btn-row">
    <button class="btn btn-secondary" onclick="addMapping()">+ Add Mapping</button>
    <button class="btn btn-primary"   onclick="saveAll()">Save</button>
    <button class="btn btn-secondary" onclick="rescan()">Rescan Modules</button>
  </div>
</div>

<div class="card">
  <div class="card-title">System</div>
  <div id="sysInfo"></div>
  <hr class="sep">
  <div class="card-title" style="margin-top:8px">WiFi</div>
  <div class="info-row"><span>SSID</span><span class="info-val">Cliqmod</span></div>
  <div class="info-row"><span>Password</span><span class="info-val">cliqmod1</span></div>
  <div class="info-row"><span>URL</span><span class="info-val">192.168.4.1</span></div>
</div>

<div class="toast" id="toast"></div>

<script>
const SOURCES = [
  {label:'Enc Click', code:0xF0},
  {label:'Btn Left',  code:0xF1},
  {label:'Btn Right', code:0xF2}
];

let state   = {profiles:[], activeProfile:0, modules:[], firmware:''};
let pending = null; // pending changes before save

async function load() {
  try {
    const r = await fetch('/api/state');
    const s = await r.json();
    state   = s;
    pending = JSON.parse(JSON.stringify(s.profiles)); // deep copy
    render();
  } catch(e) {
    document.getElementById('subline').textContent = 'Connection lost';
  }
}

function render() {
  document.getElementById('subline').textContent =
    'Firmware v' + state.firmware + '  |  ' + state.profiles.length + ' profiles';
  renderProfiles();
  renderModules();
  renderMappings();
  renderSys();
}

function renderProfiles() {
  document.getElementById('profileList').innerHTML =
    state.profiles.map((p,i) =>
      `<button class="pbtn ${i===state.activeProfile?'active':''}" onclick="setProfile(${i})">${p.name}</button>`
    ).join('');
  document.getElementById('profileNameBadge').textContent =
    '— ' + state.profiles[state.activeProfile].name;
}

async function setProfile(i) {
  await fetch('/api/profile',{
    method:'POST',
    headers:{'Content-Type':'application/json'},
    body:JSON.stringify({index:i})
  });
  state.activeProfile = i;
  renderProfiles();
  renderMappings();
  toast('Switched to ' + state.profiles[i].name);
}

function renderModules() {
  document.getElementById('moduleList').innerHTML =
    state.modules.map(m =>
      `<div class="mod-item">
        <span class="mod-badge ${m.present?'on':''}">${m.side}${m.pos}</span>
        <span class="mod-name ${m.present?'on':''}">${m.present?m.label:'Empty'}</span>
        ${m.present?'<span class="dot"></span>':''}
      </div>`
    ).join('');
}

function renderMappings() {
  const maps = pending[state.activeProfile].mappings;
  if (!maps || maps.length === 0) {
    document.getElementById('mappingList').innerHTML =
      '<div class="empty-state">No mappings yet. Add one below.</div>';
    return;
  }
  document.getElementById('mappingList').innerHTML = maps.map((m,i) => `
    <div class="mapping-item" id="map${i}">
      <div class="mapping-header">
        <span class="mapping-label">${m.label||'Unnamed'}</span>
        <button class="btn btn-danger btn-small" onclick="removeMapping(${i})">Remove</button>
      </div>
      <div class="card-title" style="margin-bottom:6px">Source</div>
      <div class="src-select">
        ${SOURCES.map(s =>
          `<div class="src-btn ${m.srcCode===s.code?'active':''}"
               onclick="setSource(${i},${s.code})">${s.label}</div>`
        ).join('')}
      </div>
      <div class="mapping-fields">
        <div class="field">
          <label>Label</label>
          <input id="lbl${i}" value="${m.label||''}" placeholder="e.g. Undo" oninput="updateField(${i})">
        </div>
        <div class="field">
          <label>Key Combo</label>
          <input id="key${i}" value="${m.keycombo||''}" placeholder="e.g. CTRL+Z" oninput="updateField(${i})">
        </div>
      </div>
    </div>
  `).join('');
}

function setSource(i, code) {
  pending[state.activeProfile].mappings[i].srcCode = code;
  renderMappings();
}

function updateField(i) {
  const maps = pending[state.activeProfile].mappings;
  maps[i].label    = document.getElementById('lbl'+i).value;
  maps[i].keycombo = document.getElementById('key'+i).value;
}

function addMapping() {
  pending[state.activeProfile].mappings.push({
    label:'', keycombo:'', srcCode:0xF0, source:'Brain Enc Click'
  });
  renderMappings();
  // Scroll to bottom
  window.scrollTo(0, document.body.scrollHeight);
}

function removeMapping(i) {
  pending[state.activeProfile].mappings.splice(i,1);
  renderMappings();
}

async function saveAll() {
  // Collect all current input values
  const maps = pending[state.activeProfile].mappings;
  maps.forEach((_,i) => {
    const lbl = document.getElementById('lbl'+i);
    const key = document.getElementById('key'+i);
    if (lbl) maps[i].label    = lbl.value;
    if (key) maps[i].keycombo = key.value;
  });

  const body = JSON.stringify({
    profile:  state.activeProfile,
    mappings: maps
  });

  const r = await fetch('/api/mappings',{
    method:'POST',
    headers:{'Content-Type':'application/json'},
    body
  });

  if (r.ok) {
    toast('Saved!');
    await load(); // reload to sync
  } else {
    toast('Save failed');
  }
}

async function rescan() {
  await fetch('/api/rescan',{method:'POST'});
  toast('Rescanning modules...');
  setTimeout(load, 1200);
}

function renderSys() {
  const lMods = state.modules.filter(m=>m.side==='L'&&m.present).length;
  const rMods = state.modules.filter(m=>m.side==='R'&&m.present).length;
  document.getElementById('sysInfo').innerHTML = `
    <div class="info-row"><span>Firmware</span><span class="info-val">v${state.firmware}</span></div>
    <div class="info-row"><span>Profiles</span><span class="info-val">${state.profiles.length}</span></div>
    <div class="info-row"><span>Active Profile</span><span class="info-val">${state.profiles[state.activeProfile].name}</span></div>
    <div class="info-row"><span>Modules Left</span><span class="info-val">${lMods} / 3</span></div>
    <div class="info-row"><span>Modules Right</span><span class="info-val">${rMods} / 3</span></div>
  `;
}

function toast(msg) {
  const t = document.getElementById('toast');
  t.textContent = msg;
  t.style.display = 'block';
  clearTimeout(t._timer);
  t._timer = setTimeout(()=>t.style.display='none', 2200);
}

load();
setInterval(load, 4000);
</script>
</body>
</html>)rawhtml";

void setupWebServer() {
  server.on("/", HTTP_GET, []() {
    server.send_P(200, "text/html", HTML_INDEX);
  });

  server.on("/api/state", HTTP_GET, []() {
    server.send(200, "application/json", buildStateJson());
  });

  server.on("/api/profile", HTTP_POST, []() {
    if (!server.hasArg("plain")) { server.send(400); return; }
    DynamicJsonDocument doc(128);
    deserializeJson(doc, server.arg("plain"));
    int idx = doc["index"] | 0;
    if (idx >= 0 && idx < profileCount) {
      activeProfile = idx;
      displayDirty  = true;
      lcdNeedsClear = true;
      saveProfiles();
    }
    server.send(200, "application/json", "{\"ok\":true}");
  });

  server.on("/api/mappings", HTTP_POST, []() {
    if (!server.hasArg("plain")) { server.send(400); return; }
    DynamicJsonDocument doc(4096);
    DeserializationError err = deserializeJson(doc, server.arg("plain"));
    if (err) { server.send(400, "application/json", "{\"error\":\"parse\"}"); return; }

    int profIdx = doc["profile"] | activeProfile;
    if (profIdx < 0 || profIdx >= profileCount) {
      server.send(400); return;
    }

    // Clear existing mappings for this profile
    for (int i = 0; i < MAX_MAPPINGS; i++)
      profiles[profIdx].mappings[i].active = false;

    JsonArray maps = doc["mappings"].as<JsonArray>();
    int slot = 0;
    for (JsonObject m : maps) {
      if (slot >= MAX_MAPPINGS) break;
      Mapping &mp = profiles[profIdx].mappings[slot];

      const char *label    = m["label"]    | "";
      const char *keycombo = m["keycombo"] | "";
      uint8_t     srcCode  = m["srcCode"]  | (uint8_t)SRC_BRAIN_ENC_CLICK;

      strncpy(mp.label, label, 19);
      mp.source    = srcCode;
      mp.controlId = 0;
      mp.eventType = 0;
      mp.action    = parseKeyCombo(keycombo);
      mp.active    = (strlen(label) > 0 || strlen(keycombo) > 0);
      slot++;
    }

    saveProfiles();
    displayDirty  = true;
    lcdNeedsClear = true;
    server.send(200, "application/json", "{\"ok\":true}");
  });

  server.on("/api/rescan", HTTP_POST, []() {
    assignAddresses(ADDR_LEFT,  WireLeft,  SDA_LEFT,  SCL_LEFT,  leftModules);
    assignAddresses(ADDR_RIGHT, WireRight, SDA_RIGHT, SCL_RIGHT, rightModules);
    server.send(200, "application/json", "{\"ok\":true}");
  });

  server.begin();
  Serial.println("[WEB] Started — 192.168.4.1");
}

// ============================================================
//  SETUP
// ============================================================

void setup() {
  Serial.begin(115200);
  delay(300);
  Serial.println("\n[CLIQMOD] v" FW_VERSION " booting");

  // Pins
  pinMode(ENC_CLK,   INPUT_PULLUP);
  pinMode(ENC_DT,    INPUT_PULLUP);
  pinMode(ENC_SW,    INPUT_PULLUP);
  pinMode(BTN_LEFT,  INPUT_PULLUP);
  pinMode(BTN_RIGHT, INPUT_PULLUP);

  pinMode(ADDR_LEFT,  OUTPUT); digitalWrite(ADDR_LEFT,  LOW);
  pinMode(ADDR_RIGHT, OUTPUT); digitalWrite(ADDR_RIGHT, LOW);
  pinMode(INT_LEFT,   INPUT_PULLUP);
  pinMode(INT_RIGHT,  INPUT_PULLUP);
  attachInterrupt(INT_LEFT,  onIntLeft,  FALLING);
  attachInterrupt(INT_RIGHT, onIntRight, FALLING);

  // USB HID
  Keyboard.begin();
  USB.begin();
  Serial.println("[HID] Ready");

  // LCD
  Wire.begin(SDA_LCD, SCL_LCD);
  int lcdSt = lcd.begin(LCD_COLS, LCD_ROWS);
  if (lcdSt) Serial.printf("[LCD] Error %d\n", lcdSt);
  else       Serial.println("[LCD] Ready");
  lcd.backlight();
  lcd.createChar(C_RIGHT, charRight);
  lcd.createChar(C_FULL,  charFull);
  lcd.createChar(C_EMPTY, charEmpty);
  lcd.createChar(C_CHECK, charCheck);

  // Module buses
  WireLeft.begin(SDA_LEFT,   SCL_LEFT,   100000);
  WireRight.begin(SDA_RIGHT, SCL_RIGHT,  100000);
  for (int i = 0; i < 3; i++) {
    leftModules[i]  = {false, 0, 0, "", {0,0,0,0}, {0,0,0,0}};
    rightModules[i] = {false, 0, 0, "", {0,0,0,0}, {0,0,0,0}};
  }

  // Storage
  loadProfiles();

  // WiFi + web
  WiFi.mode(WIFI_AP);
  WiFi.softAPConfig(AP_IP, AP_IP, IPAddress(255,255,255,0));
  WiFi.softAP(AP_SSID, AP_PASS);
  setupWebServer();

  // Startup
  startupTime  = millis();
  startupDone  = false;
  displayDirty = true;

  Serial.println("[CLIQMOD] Boot complete");
}

// ============================================================
//  LOOP
// ============================================================

void loop() {
  // Startup animation
  if (!startupDone) {
    if (millis() - startupTime > 250) {
      startupTime = millis();
      startupDots++;
      displayDirty = true;
    }
    if (startupDots >= 8) {
      startupDone   = true;
      lcdNeedsClear = true;
      displayDirty  = true;
    }
    updateDisplay();
    server.handleClient();
    return;
  }

  // First loop: scan modules
  static bool firstLoop = true;
  if (firstLoop) {
    firstLoop = false;
    assignAddresses(ADDR_LEFT,  WireLeft,  SDA_LEFT,  SCL_LEFT,  leftModules);
    assignAddresses(ADDR_RIGHT, WireRight, SDA_RIGHT, SCL_RIGHT, rightModules);
  }

  // Input
  readEncoder();
  readButtons();

  // Module interrupts
  if (intLeftFlag)  { intLeftFlag  = false; pollModuleData(WireLeft,  leftModules);  }
  if (intRightFlag) { intRightFlag = false; pollModuleData(WireRight, rightModules); }

  // Heartbeat
  if (millis() - lastHeartbeat > HEARTBEAT_MS) {
    lastHeartbeat = millis();
    pingModules();
  }

  // Clear event label after timeout
  if (lastEventLabel.length() > 0 &&
      (millis() - lastEventTime) > EVENT_DISPLAY_MS) {
    lastEventLabel = "";
    displayDirty   = true;
  }

  // Web
  server.handleClient();

  // Display
  updateDisplay();
}
