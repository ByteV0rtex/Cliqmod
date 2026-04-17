#include <WiFi.h>
#include <WebServer.h>
#include <DHT.h>
#include <Wire.h>
#include <LiquidCrystal_I2C.h>

// ===== LCD SETUP =====
// Address usually 0x27 or 0x3F
LiquidCrystal_I2C lcd(0x27, 16, 2);

// ===== WiFi Credentials =====
const char* ssid = "TURKSAT-KABLONET-2.4G-aBfh";
const char* password = "ghjA12345";

// ===== ESP32 Server =====
WebServer server(80);

// ===== Sensor Pins =====
const int lm35Pin = 3;
const int ldrPin  = 1;
#define DHTPIN 4
#define DHTTYPE DHT11
DHT dht(DHTPIN, DHTTYPE);

// ===== Variables =====
float humidity = 0;
unsigned long lastDHTRead = 0;
const unsigned long dhtInterval = 2000;

// ===== Functions =====
float readTemperature() {
  int raw = analogRead(lm35Pin);
  float voltage = raw * (3.3 / 4095.0);
  return voltage * 100.0;
}

String readLightLevel() {
  int raw = analogRead(ldrPin);
  int inverted = 4095 - raw;

  if (inverted < 1000) return "Dark";
  else if (inverted < 2500) return "Normal";
  else return "Bright";
}

// ===== LCD UPDATE =====
void updateLCD(float temp, float hum, String light) {
  lcd.clear();

  // Line 1: Temp + Humidity
  lcd.setCursor(0, 0);
  lcd.print("T:");
  lcd.print(temp, 1);
  lcd.print("C ");

  lcd.print("H:");
  lcd.print(hum, 0);
  lcd.print("%");

  // Line 2: Light
  lcd.setCursor(0, 1);
  lcd.print("Light: ");
  lcd.print(light);
}

// ===== Web Handlers =====
void handleRoot() {
  // (unchanged)
  String html = "..."; // keep your HTML here
  server.send(200, "text/html", html);
}

void handleData() {
  if (millis() - lastDHTRead > dhtInterval) {
    float h = dht.readHumidity();
    if (!isnan(h)) humidity = h;
    lastDHTRead = millis();
  }

  float temp = readTemperature();
  String light = readLightLevel();

  // 🔥 UPDATE LCD HERE
  updateLCD(temp, humidity, light);

  String json = "{";
  json += "\"temp\":" + String(temp, 2) + ",";
  json += "\"humidity\":" + String(humidity, 2) + ",";
  json += "\"light\":\"" + light + "\"";
  json += "}";

  server.send(200, "application/json", json);
}

// ===== Setup =====
void setup() {
  Serial.begin(115200);
  analogReadResolution(12);
  dht.begin();

  // LCD init
  Wire.begin(8, 9);
  lcd.init();
  lcd.backlight();
  lcd.print("Starting...");

  WiFi.begin(ssid, password);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
  }

  lcd.clear();
  lcd.print("Connected!");

  server.on("/", handleRoot);
  server.on("/data", handleData);
  server.begin();
}
void updateSensorsAndLCD() {
  if (millis() - lastDHTRead > dhtInterval) {
    float h = dht.readHumidity();
    if (!isnan(h)) humidity = h;
    lastDHTRead = millis();
  }

  float temp = readTemperature();
  String light = readLightLevel();

  updateLCD(temp, humidity, light);
}
// ===== Loop =====
void loop() {
  server.handleClient();
  updateSensorsAndLCD();
  delay(1000);
}