// Unified Cornhole Controller Sketch

//corbholeLEDs.ino

#include <WiFi.h>
#include <FastLED.h>
#include <LEDEffects.h>
#include <OneButton.h>
#include <Preferences.h>

#include <esp_now.h>
#include <esp_mac.h>
#include <esp_wifi.h>


#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

#include <SPIFFS.h>
#include <Update.h>
#include <esp_partition.h>
#include <esp_ota_ops.h>

#ifndef ARDUINO_FW_VERSION
#define ARDUINO_FW_VERSION "1.1.0"
#endif

// ---------------------- ESP-NOW Configuration ----------------------

// Define Roles
#define MAX_PEERS 6
enum DeviceRole { PRIMARY,
                  SECONDARY };

DeviceRole deviceRole;

// MAC Addresses
const uint8_t broadcastMAC[6] = { 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF };

uint8_t deviceMAC[6];
uint8_t hostMAC[6];
uint8_t peerMAC[6];
uint8_t knownPeers[MAX_PEERS][6];

int peerCount = 0;
bool roleMessageSeen = false;

// ---------------------- LED Setup ----------------------
#define RING_LED_PIN 2
#define BOARD_LED_PIN 4
#define NUM_LEDS_RING 60
#define NUM_LEDS_BOARD 216
#define LED_TYPE WS2812B
#define COLOR_ORDER GRB
#define VOLTS 5
#define MAX_AMPS 2500

CRGB ringLeds[NUM_LEDS_RING];
CRGB boardLeds[NUM_LEDS_BOARD];

// ---------------------- Button and Sensors ----------------------
#define BUTTON_PIN 12
#define SENSOR_PIN 14
#define BATTERY_PIN 35

// Button Setup
OneButton button(BUTTON_PIN, true);

// IR Trigger variables
bool irTriggered = false;

// ---------------------- Configurable Variables ----------------------
Preferences preferences;

// WiFi Credentials for AP mode
String ssid = "CornholeAP";
String password = "Funforall";

// Board LED Setup
String savedRole;
String boardName = "Board 1";
// String board2Name = "Board 2";
int brightness = 25;
unsigned long blockSize = 10;
unsigned long effectSpeed = 25;
int inactivityTimeout = 30;
int deepSleepTimeout = 60;
unsigned long irTriggerDuration = 4000;
unsigned long lastUserActivityTime = 0;    // real user interaction
unsigned long lastSystemActivityTime = 0;  // any data received or sent
bool inactivityHandled = false;

// Color Definitions
#define BURNT_ORANGE CRGB(191, 87, 0)
CRGB sportsEffectColor1 = CRGB(12, 35, 64);
CRGB sportsEffectColor2 = CRGB(241, 90, 34);
CRGB colors[] = { CRGB::Blue, CRGB::Green, CRGB::Red, CRGB::White, BURNT_ORANGE, CRGB::Aqua, CRGB::Purple, CRGB::Pink };
int colorIndex = 0;              // Index for colors array
CRGB currentColor;               // Current color in use
CRGB initialColor = CRGB::Blue;  // Set your desired initial color

// Effect Variables
String effects[] = { "Solid", "Twinkle", "Chase", "Wipe", "Bounce", "Breathing", "Gradient", "Rainbow", "America", "Sports" };
int effectIndex = 0;
bool lightsOn = true;
unsigned long previousMillis = 0;
int chasePosition = 0;
String currentEffect = "Solid";

LEDEffects ledEffects(
  ringLeds, NUM_LEDS_RING,
  boardLeds, NUM_LEDS_BOARD,
  brightness,
  effectSpeed,
  blockSize,
  initialColor,
  sportsEffectColor1,
  sportsEffectColor2);

// --------------- Bluetooth Setup (only for PRIMARY) --------------
#define SERVICE_UUID "baf6443e-a714-4114-8612-8fc18d1326f7"
#define CHARACTERISTIC_UUID "5d650eb7-c41b-44f0-9704-3710f21e1c8e"
#define OTA_SERVICE_UUID "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define OTA_CHARACTERISTIC_UUID "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#define OTA_VERSION_UUID "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"


BLEServer *pServer = NULL;
BLECharacteristic *pCharacteristic = NULL;
BLECharacteristic *pOtaCharacteristic;
BLECharacteristic *pVersionCharacteristic;
bool deviceConnected = false;
bool oldDeviceConnected = false;
uint32_t previousMillisBT = 0;
const uint32_t intervalBT = 10000;  // 10 seconds
String rxValueStdStr;
volatile bool bleDataReceived = false;
String bleCommandBuffer = "";

bool espNowEnabled = true;  // ESP-NOW synchronization is enabled by default

// OTA
bool otaInProgress = false;
int totalBytesReceived = 0;
bool updateStarted = false;
int firmwareSize = 0;


// ---------------  Battery Charger and Monitoring --------------
#define SDA_PIN 8
#define SCL_PIN 9
#define INT_PIN 10
#define SYS_PIN 13
#define SYS_RAW_PIN 15
#define ALERT_PIN 21

// Global declarations
String setupRole;
String lastEspNowMessage = "";
String lastAppMessage = "";
String espNowDataBuffer = "";
bool espNowDataReceived = false;

// Structure to receive data
#pragma pack(1)
typedef struct struct_message {
  char device[10];
  char name[15];
  uint8_t macAddr[6];
  int batteryLevel;
  int batteryVoltage;
} struct_message;
#pragma pack()

// Create a struct_message called board2
struct_message board2;

struct BoardInfo {
  int boardNumber;
  String role;
  String name;
  uint8_t mac[6];
  int batteryLevel;
  int batteryVoltage;
  String version;
};

std::vector<BoardInfo> secondaryBoards;

// Pairing Variables
CRGB previousColor;
String previousEffect;
int previousBrightness;

// ---------------------- Function Declarations ----------------------

void setupEspNow();
void setupBT();
void initializePreferences();
void defaultPreferences();
void handleBluetoothData(String data);
void updateBluetoothData(String data);
void onDataRecv(const esp_now_recv_info *info, const uint8_t *incomingData, int len);
void onDataSent(const uint8_t *mac_addr, esp_now_send_status_t status);
String macToString(const uint8_t *mac);
void sendSettings();
void sendBoardInfo();
void singleClick();
void doubleClick();
void longPress();
void toggleLights(bool status);
void toggleWiFi(bool status);
void toggleEspNow(bool status);
void btPairing();
void handleIRSensor();
void sendData(const String &device, const String &type, const String &data);
void setColor(CRGB color);
void applyEffect(String effect);
int getEffectIndex(String effect);
void powerOnEffect();
float readBatteryVoltage();
int readBatteryLevel();
void processCommand(String command);
void resolveRole();
void printPeers();
void deepSleep();
size_t getOtaPartitionSize();
void otaLog(const String &msg);
const char *getFirmwareVersion();

// Callback class for handling BLE connection events
class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *pServer) {
    deviceConnected = true;
    Serial.println("BLE Device paired");
    btPairing();
  };

  void onDisconnect(BLEServer *pServer) {
    deviceConnected = false;
  }
};

// Callback class for handling incoming BLE data
class MyCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pCharacteristic) {
    rxValueStdStr = pCharacteristic->getValue();

    if (rxValueStdStr.length() > 0) {
      // Protect shared variables with a critical section
      noInterrupts();  // Disable interrupts
      bleCommandBuffer += String(rxValueStdStr.c_str());
      bleDataReceived = true;
      interrupts();  // Re-enable interrupts
    }
  }
};

// Callback class for handling incoming OTA data
class OTAWriteCallback : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pCharacteristic) override {
    const uint8_t *data = pCharacteristic->getData();
    size_t length = pCharacteristic->getLength();

    if (length == 0) return;

    // BEGIN: Receive firmware size
    if (!otaInProgress && strncmp((char *)data, "BEGIN:", 6) == 0) {
      firmwareSize = atoi((char *)data + 6);
      size_t available = getOtaPartitionSize();
      otaLog("📥 OTA Start: expecting " + String(firmwareSize) + " bytes");
      otaLog("📦 OTA Partition space: " + String(available) + " bytes");

      if (firmwareSize <= 0 || firmwareSize > available) {
        otaLog("❌ Invalid or too large firmware size");
        return;
      }

      otaInProgress = true;
      totalBytesReceived = 0;
      FastLED.clear();
      fill_solid(boardLeds, NUM_LEDS_BOARD, CRGB::Yellow);
      FastLED.show();

      if (!Update.begin(firmwareSize)) {
        otaLog("❌ Update.begin() failed");
        otaInProgress = false;
        return;
      }

      otaLog("✅ Update.begin() successful");
      return;
    }

    // END: finalize
    if (length == 3 && memcmp(data, "END", 3) == 0) {
      otaInProgress = false;
      fill_solid(boardLeds, NUM_LEDS_BOARD, CRGB::Green);
      FastLED.show();
      delay(500);
      FastLED.clear(true);
      otaLog("📦 Firmware write complete (" + String(totalBytesReceived) + " bytes)");
      otaLog("🔍 Validating firmware...");

      if (Update.end(true)) {
        otaLog("✅ OTA Success — restarting...");
        ESP.restart();
      } else {
        otaLog("❌ OTA Write failed (validation)");
      }
      return;
    }

    // CHUNK write
    if (otaInProgress) {
      size_t written = Update.write((uint8_t *)data, length);
      if (written != length) {
        otaLog("❌ Chunk write failed at " + String(totalBytesReceived));
        Update.abort();
        otaInProgress = false;
      } else {
        totalBytesReceived += written;
        if (totalBytesReceived % 10240 < length) {  // every ~10KB
          int percent = (totalBytesReceived * 100) / firmwareSize;
          otaLog("📶 OTA progress: " + String(percent) + "%");
        }
      }
    }
  }
};

// ---------------------- Setup ----------------------
void setup() {
  Serial.begin(115200);
  delay(1000);

  esp_sleep_wakeup_cause_t wakeup_reason = esp_sleep_get_wakeup_cause();

  switch (wakeup_reason) {
    case ESP_SLEEP_WAKEUP_EXT1:
      Serial.println("⚡ Wakeup from EXT1 (Button or IR Sensor)");
      break;
    case ESP_SLEEP_WAKEUP_TIMER:
      Serial.println("⏰ Wakeup from Timer");
      break;
    case ESP_SLEEP_WAKEUP_UNDEFINED:
      Serial.println("❓ Wakeup reason undefined");
      break;
    default:
      Serial.printf("📌 Wakeup reason code: %d\n", wakeup_reason);
      break;
  }
  Serial.println("Starting setup...");

  esp_read_mac(deviceMAC, ESP_MAC_WIFI_STA);
  memcpy(hostMAC, deviceMAC, 6);

  initializePreferences();
  defaultPreferences();

  setupEspNow();
  resolveRole();

  Serial.print("📡 This Device MAC: ");
  Serial.println(macToString(deviceMAC));
  printPeers();

  Serial.println("Device Role: " + savedRole);

  if (savedRole == "PRIMARY") {
    setupBT();
  }

  SPIFFS.begin(true);

  currentColor = initialColor;

  FastLED.addLeds<LED_TYPE, RING_LED_PIN, COLOR_ORDER>(ringLeds, NUM_LEDS_RING).setCorrection(TypicalLEDStrip);
  FastLED.addLeds<LED_TYPE, BOARD_LED_PIN, COLOR_ORDER>(boardLeds, NUM_LEDS_BOARD).setCorrection(TypicalLEDStrip);
  FastLED.setMaxPowerInVoltsAndMilliamps(VOLTS, MAX_AMPS);
  FastLED.setBrightness(brightness);
  FastLED.clear();
  FastLED.show();

  pinMode(SENSOR_PIN, INPUT_PULLUP);
  pinMode(BATTERY_PIN, INPUT);
  button.attachClick(singleClick);
  button.attachDoubleClick(doubleClick);
  button.attachLongPressStop(longPress);
  ledEffects.powerOnEffect();
  effectIndex = getEffectIndex("Solid");  // or any default effect
  ledEffects.applyEffect(effects[effectIndex]);

  lastUserActivityTime = millis();
  lastSystemActivityTime = millis();
  inactivityHandled = false;

  esp_sleep_enable_ext1_wakeup((1ULL << BUTTON_PIN) | (1ULL << SENSOR_PIN), ESP_EXT1_WAKEUP_ANY_HIGH);

  if (savedRole == "PRIMARY") {
    fill_solid(ringLeds, NUM_LEDS_RING, CRGB::Blue);  // Blue = primary
    FastLED.show();
  } else {
    fill_solid(ringLeds, NUM_LEDS_RING, CRGB::Red);  // Red = secondary
    FastLED.show();
  }
  Serial.println("Setup completed.");
}

// ---------------------- Loop ----------------------
void loop() {
  unsigned long currentMillis = millis();
  button.tick();
  handleIRSensor();

  // Process BLE data if new data has been received (PRIMARY only)
  if (deviceRole == PRIMARY) {
    if (!deviceConnected && currentMillis - previousMillisBT >= intervalBT) {
      previousMillisBT = currentMillis;
      btPairing();
    } else {
      if (bleDataReceived) {
        // Copy the command buffer to a local variable safely
        noInterrupts();
        String dataToProcess = bleCommandBuffer;
        bleCommandBuffer = "";
        bleDataReceived = false;
        interrupts();

        // Now process the command outside of the critical section
        handleBluetoothData(dataToProcess);
      }
    }
  }

  if (otaInProgress && Update.isFinished()) {
    if (Update.end(true)) {
      Serial.println("✅ OTA Update completed. Rebooting...");
      delay(1000);
      ESP.restart();
    } else {
      Serial.println("❌ OTA Update failed");
    }
    otaInProgress = false;
  }

  // Process ESP-NOW data
  if (espNowDataReceived) {
    espNowDataReceived = false;        // Reset the flag
    processCommand(espNowDataBuffer);  // Process the received String data
  }

  // Apply effect at defined intervals
  if (lightsOn) {
    ledEffects.applyEffect(effects[effectIndex]);
  }

  // Handle OTA updates (PRIMARY only)
  if (deviceRole == PRIMARY) {
    //ArduinoOTA.handle();
  }
  if (!otaInProgress && millis() - lastSystemActivityTime > (unsigned long)inactivityTimeout * 1000UL && !inactivityHandled) {
    Serial.println("Inactivity timeout reached. Turning off all lights...");
    lightsOn = false;
    toggleLights(false);
    sendData("espNow", "toggleLights", "off");
    inactivityHandled = true;  // ✅ prevent re-execution
  }

  if (!otaInProgress && millis() - lastUserActivityTime > (unsigned long)deepSleepTimeout * 1000UL) {
    Serial.println("Deep Sleep timeout reached. Entering deep sleep...");
    Serial.printf("Deep Sleep Timeout: %d\n", deepSleepTimeout);
    sendData("espNow", "toggle", "SLEEP");
    FastLED.clear(true);  // Clears all LEDs and shows black
    delay(100);           // Ensure it gets shown before sleeping    delay(100);  // allow message to print
    deepSleep();
    return;
  }
}

// ---------------------- Initialization Functions ----------------------
void initializePreferences() {
  preferences.begin("cornhole", false);

  if (!preferences.getBool("nvsInit", false)) {
    Serial.println("📦 First-time setup: initializing preferences");
    preferences.putString("deviceRole", "PRIMARY");

    preferences.putString("ssid", "CornholeAP");
    preferences.putString("password", "Funforall");
    preferences.putString("boardName", "Board 1");

    preferences.putInt("initialColorR", 0);
    preferences.putInt("initialColorG", 0);
    preferences.putInt("initialColorB", 255);

    preferences.putInt("sportsColor1R", 191);
    preferences.putInt("sportsColor1G", 87);
    preferences.putInt("sportsColor1B", 0);

    preferences.putInt("sportsColor2R", 255);
    preferences.putInt("sportsColor2G", 255);
    preferences.putInt("sportsColor2B", 255);

    preferences.putInt("brightness", 50);
    preferences.putULong("blockSize", 15);
    preferences.putULong("effectSpeed", 25);
    preferences.putInt("inactivityTimeout", 30000);
    preferences.putInt("deepSleepTimeout", 60000);
    preferences.putULong("irTriggerDuration", 4000);

    preferences.putBool("nvsInit", true);
  }
  preferences.end();
}

void defaultPreferences() {
  preferences.begin("cornhole", false);

  savedRole = preferences.getString("deviceRole", "PRIMARY");  // Default PRIMARY if not set

  ssid = preferences.getString("ssid");
  password = preferences.getString("password");
  boardName = preferences.getString("boardName");

  initialColor = CRGB(preferences.getInt("initialColorR"),
                      preferences.getInt("initialColorG"),
                      preferences.getInt("initialColorB"));

  sportsEffectColor1 = CRGB(preferences.getInt("sportsColor1R"),
                            preferences.getInt("sportsColor1G"),
                            preferences.getInt("sportsColor1B"));

  sportsEffectColor2 = CRGB(preferences.getInt("sportsColor2R"),
                            preferences.getInt("sportsColor2G"),
                            preferences.getInt("sportsColor2B"));

  brightness = preferences.getInt("brightness", 50);
  blockSize = preferences.getULong("blockSize", 15);
  effectSpeed = preferences.getULong("effectSpeed", 25);
  inactivityTimeout = preferences.getInt("inactivityTimeout", 600);
  deepSleepTimeout = preferences.getInt("deepSleepTimeout", 900);
  irTriggerDuration = preferences.getULong("irTriggerDuration", 4000);

  Serial.println("Preferences loaded into in-memory variables:");
  Serial.println("Role: " + savedRole);
  Serial.println("SSID: " + ssid);
  Serial.println("Password: " + password);
  Serial.println("Primary Name: " + boardName);

  Serial.printf("Initial Color: R=%d, G=%d, B=%d\n", initialColor.r, initialColor.g, initialColor.b);
  Serial.printf("Sports Effect Color1: R=%d, G=%d, B=%d\n", sportsEffectColor1.r, sportsEffectColor1.g, sportsEffectColor1.b);
  Serial.printf("Sports Effect Color2: R=%d, G=%d, B=%d\n", sportsEffectColor2.r, sportsEffectColor2.g, sportsEffectColor2.b);
  Serial.printf("Brightness: %d\n", brightness);
  Serial.printf("Block Size: %lu\n", blockSize);
  Serial.printf("Effect Speed: %lu\n", effectSpeed);
  Serial.printf("Inactivity Timeout: %d\n", inactivityTimeout);
  Serial.printf("Deep Sleep Timeout: %d\n", deepSleepTimeout);
  Serial.printf("IR Trigger Duration: %lu\n", irTriggerDuration);

  // Update the LEDEffects object with the new values
  ledEffects.setBrightness(brightness);
  ledEffects.setBlockSize(blockSize);
  ledEffects.setEffectSpeed(effectSpeed);
  ledEffects.setColor(initialColor);
  ledEffects.setSportsEffectColors(sportsEffectColor1, sportsEffectColor2);

  preferences.end();
  deviceRole = (savedRole == "PRIMARY") ? PRIMARY : SECONDARY;
}

// ---------------------- Setup ESP-NOW ----------------------
void setupEspNow() {
  WiFi.disconnect(true);

  delay(100);
  WiFi.mode(WIFI_AP_STA);
  esp_wifi_set_promiscuous(true);  // <-- Required before setting channel
  esp_wifi_set_channel(1, WIFI_SECOND_CHAN_NONE);
  esp_wifi_set_promiscuous(false);  // <-- Restore normal state
  delay(random(300, 2000));         // Helps stagger role elections

  if (esp_now_init() != ESP_OK) {
    Serial.println("❌ ESP-NOW init failed");
    //return;
  }
  Serial.println("✅ ESP-NOW initialized");

  // Always register callbacks after init
  esp_now_register_recv_cb(onDataRecv);
  esp_now_register_send_cb(onDataSent);

  // Add broadcast peer if needed
  esp_now_peer_info_t broadcastInfo = {};
  //memset(&broadcastInfo, 0, sizeof(broadcastInfo));
  memcpy(broadcastInfo.peer_addr, broadcastMAC, 6);
  broadcastInfo.channel = 0;
  broadcastInfo.encrypt = false;
  broadcastInfo.ifidx = WIFI_IF_STA;
  if (!esp_now_is_peer_exist(broadcastMAC)) {
    if (esp_now_add_peer(&broadcastInfo) == ESP_OK) {
      Serial.println("Broadcast peer added");
    } else {
      Serial.println("❌ Failed to add broadcast peer");
    }
  }
}

// ---------------------- Role Resolution ----------------------
void saveNewRole(const String &role) {
  preferences.begin("cornhole", false);
  preferences.putString("deviceRole", role);
  preferences.end();
  Serial.println("Saved Role: " + role);
  deviceRole = (savedRole == "PRIMARY") ? PRIMARY : SECONDARY;
}

void resolveRole() {
  //delay(1000);
  String announce = "ROLE: " + savedRole;
  esp_err_t result = esp_now_send(broadcastMAC, (uint8_t *)announce.c_str(), announce.length());
  Serial.println("📣 Broadcasting role: " + announce);
  if (result != ESP_OK) {
    Serial.println("❌ Failed to send ESP-NOW broadcast!");
  }

  unsigned long startTime = millis();

  while (millis() - startTime < 2000) {
    if (espNowDataReceived) {
      espNowDataReceived = false;
      String msg = espNowDataBuffer;
      espNowDataBuffer = "";

      if (msg.startsWith("ROLE: ")) {
        roleMessageSeen = true;
        setupRole = msg.substring(6);

        if (setupRole == savedRole) {
          String response = "We are both: " + savedRole;
          Serial.println("⚠️ Conflict detected. Responding with: " + response);
          esp_now_send(broadcastMAC, (uint8_t *)response.c_str(), response.length());
        } else {
          String response = "We are different roles: ";
          esp_now_send(broadcastMAC, (uint8_t *)response.c_str(), response.length());
          Serial.println("👋 The other board is: " + setupRole);
        }
      } else if (msg.startsWith("We are both:")) {
        roleMessageSeen = true;
        setupRole = msg.substring(13);
        Serial.println("🤝 Conflict detected: both boards are " + setupRole);

        if (setupRole == "PRIMARY") {
          savedRole = "SECONDARY";
        } else {
          savedRole = "PRIMARY";
        }
        saveNewRole(savedRole);

      } else if (msg.startsWith("We are different roles")) {
        roleMessageSeen = true;  // Prevent fallback promotion
        Serial.println("🤝 Role resolution completed with: " + msg);
      }
    }
  }
  // ⏰ Fallback if no one responded and we're a SECONDARY
  if (!roleMessageSeen && savedRole == "SECONDARY") {
    Serial.println("⏰ No PRIMARY found, promoting to PRIMARY");
    savedRole = "PRIMARY";
    saveNewRole(savedRole);
  }
}

void printPeers() {
  Serial.println("🧩 Known peers:");
  for (int i = 0; i < peerCount; i++) {
    Serial.println("  → " + macToString(knownPeers[i]));
  }
}

// ---------------------- Setup BLE (PRIMARY only) ----------------------
void setupBT() {
  Serial.println("Initializing BLE...");

  // Initialize BLE Device
  BLEDevice::init("CornholeBT");
  BLEDevice::setMTU(512);

  // Create the BLE Server
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  // Create the BLE Service
  BLEService *pService = pServer->createService(SERVICE_UUID);
  BLEService *otaService = pServer->createService(OTA_SERVICE_UUID);

  // Create a BLE Characteristic
  pCharacteristic = pService->createCharacteristic(
    CHARACTERISTIC_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_NOTIFY);

  // Add a Descriptor for the Characteristic (Client Characteristic Configuration Descriptor (CCCD))
  pCharacteristic->addDescriptor(new BLE2902());

  // Set characteristic callback to handle incoming data
  pCharacteristic->setCallbacks(new MyCallbacks());

  pVersionCharacteristic = pService->createCharacteristic(
    OTA_VERSION_UUID,
    BLECharacteristic::PROPERTY_READ);
const char* firmwareVersion = getFirmwareVersion();

  pVersionCharacteristic->setValue(firmwareVersion);

  pOtaCharacteristic = pService->createCharacteristic(
    OTA_CHARACTERISTIC_UUID,
    BLECharacteristic::PROPERTY_WRITE);

  pOtaCharacteristic->addDescriptor(new BLE2902());
  pOtaCharacteristic->setCallbacks(new OTAWriteCallback());  // Start the service

  pService->start();
  otaService->start();

  //pServer->startAdvertising();
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);  // Helps with iPhone connection issues
  pAdvertising->setMinPreferred(0x12);

  BLEAdvertising *adv = pServer->getAdvertising();
  adv->addServiceUUID(OTA_SERVICE_UUID);
  //adv->start();

  Serial.print("BLE reports version: ");
  Serial.println(firmwareVersion);

  Serial.println("BLE Device is now advertising");
}


// ---------------------- Data Handling Functions ----------------------
void handleBluetoothData(String command) {
  String accumulatedData = command;  // Accumulate the incoming command

  // Check if the accumulated data contains a full command (terminated by ';')
  int endIndex = accumulatedData.indexOf(';');

  while (endIndex != -1) {
    String completeCommand = accumulatedData.substring(0, endIndex);

    // Process the complete command
    Serial.println("Received full data: " + completeCommand);
    processCommand(completeCommand);
    esp_err_t result = esp_now_send(broadcastMAC, (uint8_t *)completeCommand.c_str(), completeCommand.length());
    Serial.printf("📤ESP-NOW Sending by %s: %s %s\n", macToString(hostMAC).c_str(), completeCommand.c_str(),
                  result == ESP_OK ? "✅" : "❌");
    //sendData("espNow", completeCommand, "");
    if (result != ESP_OK) {
      setupEspNow();
    }
    // Remove the processed command from accumulated data
    accumulatedData = accumulatedData.substring(endIndex + 1);

    // Check for the next command in the remaining data
    endIndex = accumulatedData.indexOf(';');
  }
  lastSystemActivityTime = millis();
  inactivityHandled = false;
}

void processCommand(String command) {

  lastSystemActivityTime = millis();
  inactivityHandled = false;

  preferences.begin("cornhole", false);
  if (command.startsWith("CMD:CLEAR")) {
    preferences.clear();  // Clear all preferences
    preferences.end();    // Clear all preferences
    //const char *message = "CLEAR_ALL";
    //esp_err_t result = esp_now_send(peerMAC, (uint8_t *)message, strlen(message));
    Serial.println("All saved variables cleared.");
    sendData("espNow", "CMD", "CLEAR");
    sendRestartCommand();
    lastEspNowMessage = "";
    lastAppMessage = "";
    return;
  } else if (command.startsWith("n2:")) {
    //Serial.println("Sending Board 2 info to App: " + command);

  } else if (command.startsWith("IC:")) {
    int r, g, b;
    sscanf(command.c_str(), "IC:%d,%d,%d", &r, &g, &b);
    initialColor = CRGB(constrain(r, 0, 255), constrain(g, 0, 255), constrain(b, 0, 255));
    preferences.putInt("initialColorR", r);
    preferences.putInt("initialColorG", g);
    preferences.putInt("initialColorB", b);
    ledEffects.setColor(initialColor);
    ledEffects.setInitialColor(initialColor);
    Serial.println("Initial color updated.");

  } else if (command.startsWith("SC1:")) {
    int r, g, b;
    sscanf(command.c_str(), "SC1:%d,%d,%d", &r, &g, &b);
    CRGB newColor1 = CRGB(constrain(r, 0, 255), constrain(g, 0, 255), constrain(b, 0, 255));
    preferences.putInt("sportsColor1R", r);
    preferences.putInt("sportsColor1G", g);
    preferences.putInt("sportsColor1B", b);
    ledEffects.setSportsEffectColors(newColor1, sportsEffectColor2);
    Serial.println("Sports Effect Color1 updated.");

  } else if (command.startsWith("SC2:")) {
    int r, g, b;
    sscanf(command.c_str(), "SC2:%d,%d,%d", &r, &g, &b);
    CRGB newColor2 = CRGB(constrain(r, 0, 255), constrain(g, 0, 255), constrain(b, 0, 255));
    preferences.putInt("sportsColor2R", r);
    preferences.putInt("sportsColor2G", g);
    preferences.putInt("sportsColor2B", b);
    ledEffects.setSportsEffectColors(sportsEffectColor1, newColor2);
    Serial.println("Sports Effect Color2 updated.");

  } else if (command.startsWith("B1:")) {
    boardName = command.substring(3);
    preferences.putString("boardName", boardName);
    Serial.println("Board Name updated to: " + boardName);


  } else if (command.startsWith("B2:")) {

  } else if (command.startsWith("BRIGHT:")) {
    sscanf(command.c_str(), "BRIGHT:%d", &brightness);
    brightness = constrain(brightness, 0, 255);
    preferences.putInt("brightness", brightness);
    ledEffects.setBrightness(brightness);
    Serial.println("Brightness updated to: " + String(brightness));

  } else if (command.startsWith("SIZE:")) {
    sscanf(command.c_str(), "SIZE:%lu", &blockSize);
    preferences.putULong("blockSize", blockSize);
    ledEffects.setBlockSize(blockSize);
    Serial.println("Block Size updated to: " + String(blockSize));

  } else if (command.startsWith("SPEED:")) {
    sscanf(command.c_str(), "SPEED:%lu", &effectSpeed);
    preferences.putULong("effectSpeed", effectSpeed);
    ledEffects.setEffectSpeed(effectSpeed);
    Serial.println("Effect Speed updated to: " + String(effectSpeed));

  } else if (command.startsWith("CELEB:")) {
    sscanf(command.c_str(), "CELEB:%lu", &irTriggerDuration);
    preferences.putULong("irTriggerDuration", irTriggerDuration);
    Serial.println("IR Trigger Duration updated to: " + String(irTriggerDuration));

  } else if (command.startsWith("TIMEOUT:")) {
    sscanf(command.c_str(), "TIMEOUT:%d", &inactivityTimeout);
    preferences.putInt("inactivityTimeout", inactivityTimeout);
    Serial.println("Inactivity Timeout updated to: " + String(inactivityTimeout));

  } else if (command.startsWith("DEEPSLEEP:")) {
    sscanf(command.c_str(), "DEEPSLEEP:%d", &deepSleepTimeout);
    preferences.putInt("deepSleepTimeout", deepSleepTimeout);
    Serial.println("Deep Sleep Timeout updated to: " + String(deepSleepTimeout));

  } else if (command.startsWith("Effect:")) {
    String effect = command.substring(7);
    effectIndex = getEffectIndex(effect);  // Set the effect index based on received effect
    ledEffects.applyEffect(effect);
    Serial.println("Effect set to: " + effects[effectIndex]);

  } else if (command.startsWith("ColorIndex:")) {
    int index = command.substring(11).toInt();
    if (index >= 0 && index < (sizeof(colors) / sizeof(colors[0]))) {
      colorIndex = index;
      currentColor = colors[colorIndex];
      ledEffects.setColor(currentColor);
      //      sendData("espNow", "ColorIndex", String(colorIndex));
      if (deviceRole == PRIMARY) {
        sendData("app", "ColorIndex", String(colorIndex));
      }

    } else {
      Serial.println("Invalid color index");
    }
  } else if (command.startsWith("brightness:")) {  // Not sure if needed
    sscanf(command.c_str(), "brightness:%d", &brightness);
    ledEffects.setBrightness(brightness);  // Use library's method if available
    Serial.println("Brightness set to: " + String(brightness));


  } else if (command.startsWith("CMD:SLEEP")) {
    Serial.println("App Command: Entering deep sleep...");

    if (deviceRole == PRIMARY) {
      sendData("espNow", "CMD", "SLEEP");
    }

    FastLED.clear(true);  // Clears all LEDs and shows black
    delay(200);           // Ensure it gets shown before sleeping    delay(100);  // allow message to print
    deepSleep();
    return;

  } else if (command.startsWith("toggleLights")) {
    String status = command.substring(13);
    bool lightsStatus = (status == "on");
    toggleLights(lightsStatus);
    Serial.println("Lights toggled to: " + String(status));

  } else if (command.startsWith("toggleEspNow")) {
    String status = command.substring(13);
    bool espNowStatus = (status == "on");
    toggleEspNow(espNowStatus);
    Serial.println("ESP-NOW toggled to: " + String(status));

  } else if (command.startsWith("CMD:RESTART")) {
    sendRestartCommand();

  } else if (command.startsWith("CMD:SETTINGS")) {
    sendSettings();
    Serial.println("Settings sent.");

  } else if (command.startsWith("CMD:INFO")) {
    delay(random(300, 3000));
    if (savedRole == "SECONDARY") {
      struct_message outgoing;
      strncpy(outgoing.device, "SECONDARY", sizeof(outgoing.device));
      strncpy(outgoing.name, boardName.c_str(), sizeof(outgoing.name));
      memcpy(outgoing.macAddr, deviceMAC, 6);
      outgoing.batteryLevel = readBatteryLevel();
      outgoing.batteryVoltage = (int)readBatteryVoltage();

      esp_now_send(peerMAC, (uint8_t *)&outgoing, sizeof(outgoing));
      Serial.println("📡 Sent board info struct to PRIMARY in response to GET_INFO");
    } else {
      sendBoardInfo();
    }
  } else if (command.startsWith("SET_ROLE:SECONDARY")) {
    String newRole = command.substring(9);
    Serial.println("newRole extracted: " + newRole);
    preferences.begin("cornhole", false);
    preferences.putString("deviceRole", "SECONDARY");
    Serial.println("Wrote deviceRole: " + newRole);
    preferences.end();
    Serial.println("Role updated to: " + newRole);
    String currentMessage = "SET_ROLE:PRIMARY";
    esp_now_send(peerMAC, (uint8_t *)currentMessage.c_str(), currentMessage.length());
    delay(random(300, 3000));
    ESP.restart();

  } else if (command.startsWith("SET_ROLE:PRIMARY")) {
    String newRole = command.substring(9);
    preferences.begin("cornhole", false);
    preferences.putString("deviceRole", "PRIMARY");
    Serial.println("Wrote deviceRole: " + newRole);
    preferences.end();
    Serial.println("Role updated to: " + newRole);
    delay(random(300, 3000));
    ESP.restart();

  } else if (command.startsWith("r2:")) {
    Serial.println("Sending SECONDARY info to App.");

  } else if (command.startsWith("ACK:")) {
    Serial.println("OK!");
    return;

  } else if (command.startsWith("CMD:IDENTIFY:")) {
    String targetMacStr = command.substring(13);
    targetMacStr.replace("-", ":");
    String localMacStr = macToString(deviceMAC);

    Serial.printf("IDENTIFY check. Target: %s, Local: %s\n", targetMacStr.c_str(), localMacStr.c_str());

    if (targetMacStr.equalsIgnoreCase(localMacStr)) {
      Serial.println("🔍 IDENTIFY MATCH — flashing LEDs");
      for (int i = 0; i < 10; i++) {
        fill_solid(boardLeds, NUM_LEDS_BOARD, CRGB::White);
        fill_solid(ringLeds, NUM_LEDS_RING, CRGB::White);
        FastLED.show();
        delay(100);
        FastLED.clear();
        FastLED.show();
        delay(100);
      }
    } else {
      Serial.println("🔄 IDENTIFY not for this board — forwarding...");
      sendData("espNow", "CMD", "IDENTIFY:" + targetMacStr);
    }

  } else {
    Serial.println("Unknown command: " + command);
  }
  preferences.end();
}

void sendRestartCommand() {
  sendData("espNow", "CMD", "RESTART");
  delay(random(300, 3000));
  ESP.restart();
}

void sendBoardInfo() {
  char data[256];

  const char *firmwareVersion = getFirmwareVersion();

  if (savedRole == "PRIMARY") {
    sprintf(data, "r1:%s;n1:%s;m1:%02x-%02x-%02x-%02x-%02x-%02x;l1:%d;v1:%d;ver1:%s;",
            "PRIMARY",
            boardName.c_str(),
            hostMAC[0], hostMAC[1], hostMAC[2],
            hostMAC[3], hostMAC[4], hostMAC[5],
            readBatteryLevel(),
            (int)readBatteryVoltage(),
            firmwareVersion);
    updateBluetoothData(data);
    Serial.print("Sending Primary info to app: ");
    Serial.println(data);
  }
  for (const auto &b : secondaryBoards) {
    char data[256];
    sprintf(data, "r%d:%s;n%d:%s;m%d:%02x-%02x-%02x-%02x-%02x-%02x;l%d:%d;v%d:%d;ver%d:%s;",
            b.boardNumber, b.role.c_str(),
            b.boardNumber, b.name.c_str(),
            b.boardNumber, b.mac[0], b.mac[1], b.mac[2], b.mac[3], b.mac[4], b.mac[5],
            b.boardNumber, b.batteryLevel,
            b.boardNumber, b.batteryVoltage,
            b.boardNumber, firmwareVersion);

    Serial.print("Sending Secondary Board info to APP: ");
    Serial.println(String(data));
    updateBluetoothData(String(data));
  }
}


// ---------------------- BLE and ESP-NOW Callbacks ----------------------
void onDataRecv(const esp_now_recv_info_t *info, const uint8_t *incomingData, int len) {
  String receivedData = String((char *)incomingData).substring(0, len);
  memcpy(peerMAC, info->src_addr, 6);  // Always capture sender

  if (receivedData == lastEspNowMessage) return;
  lastEspNowMessage = receivedData;

  // ----- ROLE NEGOTIATION MESSAGES -----
  if (receivedData.startsWith("ROLE:")) {
    roleMessageSeen = true;
    setupRole = receivedData.substring(6);

    String response;
    if (setupRole == savedRole) {
      response = "We are both: " + savedRole;
      Serial.println("⚠️ Conflict detected. Responded with: " + response);
    } else {
      response = "We are different roles";
      Serial.println("👋 Received role broadcast from peer: " + setupRole);
    }
    esp_now_send(broadcastMAC, (uint8_t *)response.c_str(), response.length());
    return;
  }

  if (receivedData.startsWith("We are both: ")) {
    roleMessageSeen = true;
    setupRole = receivedData.substring(13);
    if (setupRole == "PRIMARY") {
      savedRole = "SECONDARY";
      saveNewRole(savedRole);
      Serial.println("🔧 Changed Role to: " + savedRole);
    }
    return;
  }

  if (receivedData.startsWith("We are different")) {
    roleMessageSeen = true;
    Serial.println("🛑 Role resolution complete.");
    return;
  }

  // ----- REGISTER NEW PEER -----
  bool known = false;
  for (int i = 0; i < peerCount; i++) {
    if (memcmp(info->src_addr, knownPeers[i], 6) == 0) {
      known = true;
      break;
    }
  }

  if (!known && peerCount < MAX_PEERS) {
    memcpy(knownPeers[peerCount], info->src_addr, 6);
    peerCount++;
    Serial.println("🔗 New peer: " + macToString(peerMAC));
    printPeers();

    esp_now_peer_info_t peerInfo = {};
    memcpy(peerInfo.peer_addr, peerMAC, 6);
    peerInfo.channel = 0;
    peerInfo.encrypt = false;
    esp_now_add_peer(&peerInfo);
  }

  // ----- STRUCTURED BOARD MESSAGE -----
  if (len == sizeof(struct_message)) {
    struct_message incoming;
    memcpy(&incoming, incomingData, sizeof(struct_message));

    Serial.println("📦 Received struct_message from SECONDARY:");
    Serial.printf("  Device: %s\n", incoming.device);
    Serial.printf("  Name: %s\n", incoming.name);
    Serial.printf("  MAC: %02X:%02X:%02X:%02X:%02X:%02X\n",
                  incoming.macAddr[0], incoming.macAddr[1], incoming.macAddr[2],
                  incoming.macAddr[3], incoming.macAddr[4], incoming.macAddr[5]);
    Serial.printf("  Battery Level: %d%%\n", incoming.batteryLevel);
    Serial.printf("  Battery Voltage: %dmV\n", incoming.batteryVoltage);

    bool found = false;
    for (auto &b : secondaryBoards) {
      if (memcmp(b.mac, incoming.macAddr, 6) == 0) {
        b.name = String(incoming.name);
        b.batteryLevel = incoming.batteryLevel;
        b.batteryVoltage = incoming.batteryVoltage;
        found = true;
        break;
      }
    }

    if (!found) {
      BoardInfo newBoard;
      String nameStr = String(incoming.name);
      int extractedNumber = 0;
      if (nameStr.startsWith("Board ")) {
        extractedNumber = nameStr.substring(6).toInt();
      }
      if (extractedNumber == 0) {
        extractedNumber = secondaryBoards.size() + 2;
      }
    const char* firmwareVersion = getFirmwareVersion();
      newBoard.boardNumber = extractedNumber;
      newBoard.role = "SECONDARY";
      newBoard.name = String(incoming.name);
      memcpy(newBoard.mac, incoming.macAddr, 6);
      newBoard.batteryLevel = incoming.batteryLevel;
      newBoard.batteryVoltage = incoming.batteryVoltage;
      newBoard.version = firmwareVersion;
      secondaryBoards.push_back(newBoard);
    }

    std::sort(secondaryBoards.begin(), secondaryBoards.end(),
              [](const BoardInfo &a, const BoardInfo &b) {
                return a.boardNumber < b.boardNumber;
              });

    Serial.println("📥 Updated board list:");
    for (const auto &b : secondaryBoards) {
      Serial.printf("  → r%d: %s [%02X:%02X:%02X:%02X:%02X:%02X], Batt: %d%%\n",
                    b.boardNumber,
                    b.name.c_str(),
                    b.mac[0], b.mac[1], b.mac[2], b.mac[3], b.mac[4], b.mac[5],
                    b.batteryLevel,
                    b.batteryVoltage);

      // Forward to app
      char data[256];
      sprintf(data, "r%d:%s;n%d:%s;m%d:%02x:%02x:%02x:%02x:%02x:%02x;l%d:%d;v%d:%d;ver%d:%s",
              b.boardNumber, b.role.c_str(),
              b.boardNumber, b.name.c_str(),
              b.boardNumber, b.mac[0], b.mac[1], b.mac[2],
              b.mac[3], b.mac[4], b.mac[5],
              b.boardNumber, b.batteryLevel,
              b.boardNumber, b.batteryVoltage,
              b.boardNumber, b.version.c_str());
      updateBluetoothData(String(data));
    }
    return;
  }

  // ----- ACK -----
  if (savedRole == "SECONDARY" && receivedData.startsWith("CMD:INFO")) {
    String ack = "ACK: " + savedRole;
    esp_now_send(info->src_addr, (uint8_t *)ack.c_str(), ack.length());
    Serial.println("🔁 Responded to PRIMARY with ACK");
  }

  // ----- PASS-THROUGH COMMAND -----
  espNowDataBuffer = receivedData;
  espNowDataReceived = true;
  Serial.println("Received data: " + receivedData);

  // Forward to app if PRIMARY and not ACK
  if (savedRole == "PRIMARY" && !receivedData.startsWith("ACK:")) {
    sendData("app", "INFO", receivedData);
  }
}

void onDataSent(const uint8_t *mac_addr, esp_now_send_status_t status) {
  Serial.print("Status of sent: ");
  Serial.println(status == ESP_NOW_SEND_SUCCESS ? "Delivery Success" : "Delivery Fail");

  if (status != ESP_NOW_SEND_SUCCESS) {
    Serial.println("ESP-NOW Send Failed. Checking peer status...");
    if (!esp_now_is_peer_exist(mac_addr)) {
      Serial.println("Peer not found. Re-adding peer...");
      esp_now_peer_info_t peerInfo;
      memcpy(peerInfo.peer_addr, mac_addr, 6);
      peerInfo.channel = 0;
      peerInfo.encrypt = false;

      if (esp_now_add_peer(&peerInfo) != ESP_OK) {
        Serial.println("Failed to re-add peer");
      } else {
        Serial.println("Peer re-added successfully");
      }
    }
  }
}
// ------------------------- Utility -----------------------------------
String macToString(const uint8_t *mac) {
  char macStr[18];
  snprintf(macStr, sizeof(macStr), "%02X:%02X:%02X:%02X:%02X:%02X",
           mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
  return String(macStr);
  Serial.print("📡 This device MAC: ");
  Serial.println(macToString(hostMAC));
}

// ---------------------- Communication Functions ----------------------
void sendSettings() {
  String data = "S:B1:" + boardName + ";COLORINDEX:" + String(colorIndex) + ";SPORTCOLOR1:" + String(sportsEffectColor1.r) + "," + String(sportsEffectColor1.g) + "," + String(sportsEffectColor1.b) + ";SPORTCOLOR2:" + String(sportsEffectColor2.r) + "," + String(sportsEffectColor2.g) + "," + String(sportsEffectColor2.b) + ";BRIGHT:" + String(brightness) + ";SIZE:" + String(blockSize) + ";SPEED:" + String(effectSpeed) + ";CELEB:" + String(irTriggerDuration) + ";TIMEOUT:" + String(inactivityTimeout) + ";DEEPSLEEP:" + String(deepSleepTimeout);

  // Append board names dynamically
  for (int i = 0; i < secondaryBoards.size(); i++) {
    data += ";B" + String(i + 2) + ":" + secondaryBoards[i].name;
  }

  if (savedRole == "PRIMARY") {
    sendData("app", "SETTINGS", data);
  }
}

void sendData(const String &device, const String &type, const String &data) {
  if (!espNowEnabled) {
    Serial.println("🚫 ESP-NOW not enabled! Cannot send.");
    return;
  }

  char messageBuffer[250];
  String currentMessage;

  if (device == "espNow") {
    Serial.println(data.c_str());
    snprintf(messageBuffer, sizeof(messageBuffer), "%s:%s", type.c_str(), data.c_str());
    currentMessage = String(messageBuffer);

    // Show what we're trying to send
    Serial.println("📤 sendData(espNow): " + currentMessage);
    Serial.println("🔎 Known Peers: " + String(peerCount));

    // If it's a duplicate, skip
    if (currentMessage == lastEspNowMessage) {
      Serial.println("⚠️ Duplicate ESP-NOW message detected. Skipping send.");
      return;
    }

    bool sent = false;

    // Send to all known peers
    for (int i = 0; i < peerCount; i++) {
      if (!esp_now_is_peer_exist(knownPeers[i])) {
        Serial.println("🔁 Peer not found. Trying to re-add: " + macToString(knownPeers[i]));
        esp_now_peer_info_t peerInfo = {};
        memcpy(peerInfo.peer_addr, knownPeers[i], 6);
        peerInfo.channel = 0;
        peerInfo.encrypt = false;
        esp_now_add_peer(&peerInfo);
      }

      esp_err_t result = esp_now_send(knownPeers[i], (uint8_t *)currentMessage.c_str(), currentMessage.length());
      Serial.printf("📡 Sent to %s: %s %s\n",
                    macToString(knownPeers[i]).c_str(),
                    currentMessage.c_str(),
                    result == ESP_OK ? "✅" : "❌");

      if (result == ESP_OK) sent = true;
    }

    // Fallback to broadcast if nothing was sent or no peers
    if (!sent || peerCount == 0) {
      Serial.println("📡 No peers or failed sends. Broadcasting message.");
      esp_now_send(broadcastMAC, (uint8_t *)currentMessage.c_str(), currentMessage.length());
    }

    lastEspNowMessage = currentMessage;
  }

  else if (device == "app" && deviceRole == PRIMARY) {
    if (data == "") {
      currentMessage = type;
    } else {
      currentMessage = type + ":" + data + ";";
    }

    if (currentMessage != lastAppMessage && savedRole == "PRIMARY") {
      updateBluetoothData(currentMessage);
      Serial.println("📱 Sending to app: " + currentMessage);
      lastAppMessage = currentMessage;
    } else {
      if (deviceRole == PRIMARY) {
        Serial.println("⚠️ Duplicate App message detected. Skipping send.");
      } else {
        Serial.println("⚠️ This is the SECONDARY. Skipping send.");
      }
    }
  }
}

void updateBluetoothData(String data) {
  if (deviceRole != PRIMARY || pCharacteristic == nullptr) return;  // Prevent crash

  const int maxChunkSize = 512;                                            // Maximum BLE payload size is 20 bytes
  String message = data;                                                   // Full message to send
  int totalChunks = (message.length() + maxChunkSize - 1) / maxChunkSize;  // Total number of chunks

  for (int i = 0; i < totalChunks; i++) {
    int startIdx = i * maxChunkSize;
    int endIdx = min(startIdx + maxChunkSize, (int)message.length());  // Cast message.length() to int

    String chunk = message.substring(startIdx, endIdx);
    // Send the chunk instead of the entire message
    pCharacteristic->setValue(chunk.c_str());  // Convert String to C-string for BLE transmission
    pCharacteristic->notify();                 // Send the chunk via BLE notification
    delay(20);                                 // Delay to avoid congestion
  }
}

// ---------------------- Button Callback Functions ----------------------
void singleClick() {
  if (!lightsOn) {
    Serial.println("Lights are off, skipping color change.");
    return;
  }
  colorIndex = (colorIndex + 1) % (sizeof(colors) / sizeof(colors[0]));
  currentColor = colors[colorIndex];
  ledEffects.setColor(currentColor);
  sendData("espNow", "ColorIndex", String(colorIndex));
  if (deviceRole == PRIMARY) {
    sendData("app", "ColorIndex", String(colorIndex));
  }
  Serial.println("Single Click: Color changed to index " + String(colorIndex));
  lastUserActivityTime = millis();
  lastSystemActivityTime = millis();
  inactivityHandled = false;
}

void doubleClick() {
  if (!lightsOn) {
    Serial.println("Lights are off, skipping effect application.");
    return;
  }
  effectIndex = (effectIndex + 1) % (sizeof(effects) / sizeof(effects[0]));
  ledEffects.applyEffect(effects[effectIndex]);
  sendData("espNow", "Effect", effects[effectIndex]);
  if (deviceRole == PRIMARY) {
    sendData("app", "Effect", effects[effectIndex]);
  }
  Serial.println("Double Click: Effect changed to " + effects[effectIndex]);
  lastUserActivityTime = millis();
  lastSystemActivityTime = millis();
  inactivityHandled = false;
}

void longPress() {
  Serial.println("Long Press: Entering deep sleep...");

  sendData("espNow", "CMD", "SLEEP");
  if (deviceRole == PRIMARY) {
    sendData("app", "CMD", "SLEEP");
  }

  FastLED.clear(true);  // Clears all LEDs and shows black
  delay(100);           // Ensure it gets shown before sleeping    delay(100);  // allow message to print
  deepSleep();
  return;
}

// ---------------------- Utility Functions ----------------------

void toggleLights(bool status) {
  lightsOn = status;
  if (status) lastUserActivityTime = millis();
  ledEffects.setColor(lightsOn ? currentColor : CRGB::Black);  // Set color if on, black if off
  String message = String(status ? "on" : "off");

  Serial.print("Lights are: ");
  Serial.println(message);
}

void toggleEspNow(bool status) {
  espNowEnabled = status;
  if (espNowEnabled) {
    Serial.println("ESP-NOW enabled");
    esp_now_deinit();  // Ensure clean reinit
    setupEspNow();
  } else {
    Serial.println("ESP-NOW disabled");
    esp_now_deinit();
  }
}

void btPairing() {
  if (!deviceConnected) {
    if (deviceRole == PRIMARY) {
      pServer->startAdvertising();  // restart advertising
    }
    oldDeviceConnected = deviceConnected;
    deviceConnected = false;
  } else {
    deviceConnected = true;

    if (pCharacteristic && pServer->getConnectedCount() > 0) {
      delay(1000);      // optional stability delay
      sendBoardInfo();  // ✅ Send board info to app on BLE connection
      Serial.println("Bluetooth Device paired successfully");
    } else {
      Serial.println("⚠️ BLE device connected, but characteristic not ready.");
    }
  }
}

void handleIRSensor() {
  int reading = digitalRead(SENSOR_PIN);
  static bool effectRunning = false;
  static unsigned long effectStartTime = 0;
  const unsigned long effectDuration = irTriggerDuration;

  if (reading == LOW && !effectRunning) {
    effectStartTime = millis();
    effectRunning = true;
    irTriggered = true;

    // Turn lights on if they were off
    if (!lightsOn) {
      lightsOn = true;
      toggleLights(true);
      sendData("espNow", "toggleLights", "on");
      if (deviceRole == PRIMARY) {
        sendData("app", "toggleLights", "on");
      }
      Serial.println("IR Trigger: Lights were off — turning on.");
    }

    ledEffects.celebrationEffect();
    Serial.println("IR Sensor Triggered: Celebration Effect Started");

    while (millis() - effectStartTime < effectDuration) {
      ledEffects.celebrationEffect();
      delay(20);  // adjust to match animation frame rate
    }
  }

  if (effectRunning && (millis() - effectStartTime >= effectDuration)) {
    effectRunning = false;
    irTriggered = false;
    ledEffects.setColor(currentColor);
    Serial.println("IR Sensor Triggered: Celebration Effect Ended");
  }
  lastUserActivityTime = millis();
}

void deepSleep() {
  WiFi.disconnect(true);
  //WiFi.mode(WIFI_OFF);

  //esp_wifi_stop();
  esp_deep_sleep_start();
  return;
}

// ---------------------- Battery Monitoring Functions ----------------------
float readBatteryVoltage() {
  int analogValue = analogRead(BATTERY_PIN);
  float voltage = analogValue * (3.3 / 4095.0);
  float batteryVoltage = voltage * (10000.0 + 3900.0) / 3900.0;
  return batteryVoltage;
}

int readBatteryLevel() {
  float batteryVoltage = readBatteryVoltage();
  int batteryLevel = map((int)(batteryVoltage * 100), 0, 1200, 0, 100);  // Assuming 12V max
  return constrain(batteryLevel, 0, 100);
}

// ---------------------- Effect Functions ----------------------
int getEffectIndex(String effect) {
  for (int i = 0; i < (sizeof(effects) / sizeof(effects[0])); i++) {
    if (effects[i] == effect) {
      return i;
    }
  }
  return 0;
}

// ------------------- Get Partition Information ----------------
size_t getOtaPartitionSize() {
  const esp_partition_t *configured = esp_ota_get_boot_partition();
  const esp_partition_t *running = esp_ota_get_running_partition();
  const esp_partition_t *next_update_partition = esp_ota_get_next_update_partition(NULL);

  if (next_update_partition == NULL || next_update_partition == running) {
    Serial.println("❌ Cannot perform OTA: No valid OTA partition or same as running partition");
    otaInProgress = false;
    return 0;
  }
  if (next_update_partition) {
    return next_update_partition->size;
  } else {
    Serial.println("❌ No OTA update partition found");
    return 0;
  }
}

void dumpPartitionInfo() {
  const esp_partition_t *running = esp_ota_get_running_partition();
  const esp_partition_t *update = esp_ota_get_next_update_partition(NULL);

  Serial.printf("🔎 Running Partition:  Label=%s, Addr=0x%08x, Size=%d\n",
                running->label, running->address, running->size);
  Serial.printf("📦 Update Partition:  Label=%s, Addr=0x%08x, Size=%d\n",
                update ? update->label : "NULL",
                update ? update->address : 0, update ? update->size : 0);
}

void otaLog(const String &msg) {
  updateBluetoothData("OTA_LOG:" + msg + ";");
  Serial.println(msg);  // keep existing serial behavior
}

const char *getFirmwareVersion() {
  return ARDUINO_FW_VERSION;
}