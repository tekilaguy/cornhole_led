#include <LEDEffects.h>

// Unified Cornhole Controller Sketch
#include <WiFi.h>
#include <FastLED.h>
#include <OneButton.h>
#include <esp_now.h>
#include <esp_mac.h>
#include <esp_wifi.h>
#include <Preferences.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <ArduinoOTA.h>
#include <HTTPUpdate.h>
#include <ESPAsyncWebServer.h>

// ---------------------- Configuration ----------------------

// Define Roles
enum DeviceRole { MASTER, SLAVE };

String savedRole = "MASTER";

DeviceRole deviceRole;

// MAC Addresses
uint8_t masterMAC[] = {0x24, 0x6F, 0x28, 0x88, 0xB4, 0xC8}; // MAC address of the master board
uint8_t slaveMAC[] = {0x24, 0x6F, 0x28, 0x88, 0xB4, 0xC9};  // MAC address of the slave board
const uint8_t broadcastMAC[] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};

String ipAddress;

uint8_t deviceMAC[6];
uint8_t *hostMAC;
uint8_t *peerMAC;

// Web Server (only for MASTER)
AsyncWebServer server(80);

// ---------------------- LED Setup ----------------------
#define RING_LED_PIN    32
#define BOARD_LED_PIN   33
#define NUM_LEDS_RING   60
#define NUM_LEDS_BOARD  216
#define LED_TYPE        WS2812B
#define COLOR_ORDER     GRB
#define VOLTS           5
#define MAX_AMPS        2500

CRGB ringLeds[NUM_LEDS_RING];
CRGB boardLeds[NUM_LEDS_BOARD];

// ---------------------- Button and Sensors ----------------------
#define BUTTON_PIN 14
#define SENSOR_PIN 12
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
String board1Name = "Board 1";
String board2Name = "Board 2";
int brightness = 25;
unsigned long blockSize = 10;
unsigned long effectSpeed = 25;
int inactivityTimeout = 30;
unsigned long irTriggerDuration = 4000;
unsigned long lastActivityTime = 0;

// Color Definitions
#define BURNT_ORANGE    CRGB(191, 87, 0)
CRGB sportsEffectColor1 = CRGB(12,35,64);
CRGB sportsEffectColor2 = CRGB(241,90,34);
CRGB colors[] = {CRGB::Blue, CRGB::Green, CRGB::Red, CRGB::White, BURNT_ORANGE, CRGB::Aqua, CRGB::Purple, CRGB::Pink};
int colorIndex = 0;          // Index for colors array
CRGB currentColor;           // Current color in use
CRGB initialColor = CRGB::Blue;  // Set your desired initial color

// Effect Variables
String effects[] = {"Solid", "Twinkle", "Chase", "Wipe", "Bounce", "Breathing", "Gradient", "Rainbow",  "America", "Sports"};
int effectIndex = 0;
bool lightsOn = true;
unsigned long previousMillis = 0;
int chasePosition = 0;
String currentEffect = "Solid";

LEDEffects ledEffects(
  ringLeds, 
  boardLeds, 
  brightness,     
  effectSpeed,    
  blockSize,      
  initialColor,   
  sportsEffectColor1,
  sportsEffectColor2
);

// Bluetooth Setup (only for MASTER)
#define SERVICE_UUID        "baf6443e-a714-4114-8612-8fc18d1326f7"
#define CHARACTERISTIC_UUID "5d650eb7-c41b-44f0-9704-3710f21e1c8e"

BLEServer* pServer = NULL;
BLECharacteristic* pCharacteristic = NULL;
bool deviceConnected = false;
bool oldDeviceConnected = false;
uint32_t previousMillisBT = 0;
const uint32_t intervalBT = 10000; // 10 seconds
String rxValueStdStr;
volatile bool bleDataReceived = false;
String bleCommandBuffer = "";

bool espNowEnabled = true; // ESP-NOW synchronization is enabled by default
bool wifiConnected = false;
bool usingFallbackAP = false;
bool wifiEnabled = true; // Variable to toggle WiFi on and off

// Global declarations
String lastEspNowMessage = "";
String lastAppMessage = "";
String espNowDataBuffer = "";
bool espNowDataReceived = false;
bool board2DataReceived = false; // Add this at the top with your global variables

// Structure to receive data
#pragma pack(1)
typedef struct struct_message {
    char device[10];
    char name[15];
    uint8_t macAddr[6];
    char ipAddr[16];
    int batteryLevel;
    int batteryVoltage;
} struct_message;
#pragma pack()

// Create a struct_message called board2
struct_message board2;

// Pairing Variables
CRGB previousColor;
String previousEffect;
int previousBrightness;

// ---------------------- Function Declarations ----------------------
void setupWiFi();
void setupEspNow();
void setupBT();
void setupOta();
void setupWebServer();
void handleBluetoothData(String data);
void updateBluetoothData(String data);
void onDataRecv(const esp_now_recv_info *info, const uint8_t *incomingData, int len);
void onDataSent(const uint8_t *mac_addr, esp_now_send_status_t status);
String macToString(const uint8_t *mac);
void sendSettings();
void sendBoardInfo();
void startOtaUpdate(String firmwareUrl);
void singleClick();
void doubleClick();
void longPressStart();
void longPressStop();
void toggleLights(bool status);
void toggleWiFi(bool status);
void toggleEspNow(bool status);
void btPairing();
void handleIRSensor();
void sendData(const String& device, const String& type, const String& data);
void setColor(CRGB color);
void applyEffect(String effect);
int getEffectIndex(String effect);
void powerOnEffect();
float readBatteryVoltage();
int readBatteryLevel();

// Callback class for handling BLE connection events
class MyServerCallbacks: public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) {
    deviceConnected = true;
    Serial.println("BLE Device paired");
    btPairing();
  };

  void onDisconnect(BLEServer* pServer) {
    deviceConnected = false;
  }
};

// Callback class for handling incoming BLE data
class MyCallbacks: public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pCharacteristic) {
    rxValueStdStr = pCharacteristic->getValue();

    if (rxValueStdStr.length() > 0) {
      // Protect shared variables with a critical section
      noInterrupts(); // Disable interrupts
      bleCommandBuffer += String(rxValueStdStr.c_str());
      bleDataReceived = true;
      interrupts(); // Re-enable interrupts
    }
  }
};

// ---------------------- Setup ----------------------
void setup() {
  delay(5000);
  Serial.begin(115200);
  Serial.println("Starting setup...");

  // Initialize Preferences
  initializePreferences(); // Initialize preferences if not already done
  defaultPreferences();
  deviceRole = (savedRole == "MASTER") ? MASTER : SLAVE;

  // Assign Device Role
  if (deviceRole == MASTER){
    peerMAC = slaveMAC;
    hostMAC = masterMAC;
  } else {
    peerMAC = masterMAC;
    hostMAC = slaveMAC;
  }

  Serial.println(deviceRole == MASTER ? "Device Role: MASTER" : "Device Role: SLAVE");

  currentColor = initialColor;

  setupWiFi();
  esp_wifi_set_mac(WIFI_IF_STA, hostMAC);
  esp_read_mac(deviceMAC, ESP_MAC_WIFI_STA);
  printMacAddress();
  setupEspNow();

  // Initialize additional services for MASTER
  if (deviceRole == MASTER) {
    setupBT();
    setupOta();
    setupWebServer();
  }

  // Initialize LEDs
  FastLED.addLeds<LED_TYPE, RING_LED_PIN, COLOR_ORDER>(ringLeds, NUM_LEDS_RING).setCorrection(TypicalLEDStrip);
  FastLED.addLeds<LED_TYPE, BOARD_LED_PIN, COLOR_ORDER>(boardLeds, NUM_LEDS_BOARD).setCorrection(TypicalLEDStrip);
  FastLED.setMaxPowerInVoltsAndMilliamps(VOLTS, MAX_AMPS);
  FastLED.setBrightness(brightness);
  FastLED.clear();
  FastLED.show();

  // Initialize Sensors and Buttons
  pinMode(SENSOR_PIN, INPUT_PULLUP);
  pinMode(BATTERY_PIN, INPUT);
  button.attachClick(singleClick);
  button.attachDoubleClick(doubleClick);
  button.attachLongPressStart(longPressStart);
  button.attachLongPressStop(longPressStop);
  ledEffects.powerOnEffect();

  // Initialize board2 structure
  strcpy(board2.device, "Board 2");
  strcpy(board2.name, board2Name.c_str());
  memcpy(board2.macAddr, broadcastMAC, 6); // Set to broadcast MAC
  strcpy(board2.ipAddr, WiFi.localIP().toString().c_str());

  Serial.println("Setup completed.");
}

// ---------------------- Loop ----------------------
void loop() {
  unsigned long currentMillis = millis();
  button.tick();
  handleIRSensor();

  // Process BLE data if new data has been received (MASTER only)
  if (deviceRole == MASTER) {
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
  // Process ESP-NOW data
  if (espNowDataReceived) {
    espNowDataReceived = false; // Reset the flag
    processCommand(espNowDataBuffer); // Process the received String data
  }

  // Apply effect at defined intervals
  if (lightsOn) {
    ledEffects.applyEffect(effects[effectIndex]);
  }
  
  // Handle OTA updates (MASTER only)
  if (deviceRole == MASTER) {
    ArduinoOTA.handle();
  }
}

// ---------------------- Initialization Functions ----------------------
void initializePreferences() {
    preferences.begin("cornhole", false);
    if (!preferences.getBool("nvsInit", false)) {

        preferences.putString("deviceRole", "MASTER");

        preferences.putString("ssid", "CornholeAP");
        preferences.putString("password", "Funforall");
        preferences.putString("board1Name", "Board 1");
        preferences.putString("board2Name", "Board 2");

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
        preferences.putInt("inactivityTimeout", 30);
        preferences.putULong("irTriggerDuration", 4000);

        preferences.putBool("nvsInit", true);
        Serial.println("Preferences initialized with default values.");
    }
    preferences.end();
}

void defaultPreferences(){
  preferences.begin("cornhole", false);

  savedRole = preferences.getString("deviceRole"); // Default MASTER if not set

  ssid = preferences.getString("ssid");
  password = preferences.getString("password");
  board1Name = preferences.getString("board1Name");
  board2Name = preferences.getString("board2Name");

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
  inactivityTimeout = preferences.getInt("inactivityTimeout", 30);
  irTriggerDuration = preferences.getULong("irTriggerDuration", 4000);
  
  Serial.println("Preferences loaded into in-memory variables:");
  Serial.println("Role: " + savedRole);
  Serial.println("SSID: " + ssid);
  Serial.println("Password: " + password);
  Serial.println("Board1 Name: " + board1Name);
  Serial.println("Board2 Name: " + board2Name);
  Serial.printf("Initial Color: R=%d, G=%d, B=%d\n", initialColor.r, initialColor.g, initialColor.b);
  Serial.printf("Sports Effect Color1: R=%d, G=%d, B=%d\n", sportsEffectColor1.r, sportsEffectColor1.g, sportsEffectColor1.b);
  Serial.printf("Sports Effect Color2: R=%d, G=%d, B=%d\n", sportsEffectColor2.r, sportsEffectColor2.g, sportsEffectColor2.b);
  Serial.printf("Brightness: %d\n", brightness);
  Serial.printf("Block Size: %lu\n", blockSize);
  Serial.printf("Effect Speed: %lu\n", effectSpeed);
  Serial.printf("Inactivity Timeout: %d\n", inactivityTimeout);
  Serial.printf("IR Trigger Duration: %lu\n", irTriggerDuration);
  
    // Update the LEDEffects object with the new values
    ledEffects.setBrightness(brightness);
    ledEffects.setBlockSize(blockSize);
    ledEffects.setEffectSpeed(effectSpeed);
    ledEffects.setColor(initialColor);
    ledEffects.setSportsEffectColors(sportsEffectColor1, sportsEffectColor2);

  preferences.end();
}

// ---------------------- Setup WiFi ----------------------
void setupWiFi() {
  Serial.print("Setting up WiFi...");
  WiFi.mode(WIFI_STA); // Set Wi-Fi to station mode
  WiFi.begin(ssid, password);

    if (deviceRole == MASTER){
      int attempts = 0;
      while (WiFi.status() != WL_CONNECTED) {
        delay(500);
        attempts++;
        Serial.print(".");
        if (attempts > 20) {
        Serial.println("");
          Serial.println("Switching to AP mode...");
          WiFi.mode(WIFI_AP_STA);
          WiFi.softAP(ssid, password);
          Serial.println("Soft Access Point started");
          Serial.print("Soft IP Address: ");
          Serial.println(WiFi.softAPIP());
          Serial.print("Soft SSID: ");
          Serial.println(ssid);
          ipAddress = WiFi.softAPIP().toString().c_str();
          usingFallbackAP = "true";
          return;
        }
      }
    } else {
            while (WiFi.status() != WL_CONNECTED) {
            delay(1000);
            Serial.print(".");
        // No need to call WiFi.begin() again here
      }
    }
  ipAddress = WiFi.localIP().toString().c_str();
  Serial.println();
  Serial.println("Connected to WiFi");
  Serial.println("IP Address: ");
  Serial.println(WiFi.localIP());
  Serial.print("Soft SSID: ");
  Serial.println(ssid);
}

// ---------------------- Setup ESP-NOW ----------------------
void printMacAddress() {
    esp_read_mac(deviceMAC, ESP_MAC_WIFI_STA); // Retrieve MAC address using esp_read_mac

    Serial.print("Device MAC Address: ");
    for(int i = 0; i < 6; i++) {
        Serial.printf("%02X", deviceMAC[i]);
        if(i < 5) Serial.print(":");
    }
    Serial.println();
}

void setupEspNow() {
  if (esp_now_init() != ESP_OK) {
    return;
  }
  esp_now_register_recv_cb(onDataRecv);
  esp_now_register_send_cb(onDataSent);

    esp_now_peer_info_t peerInfo;
    memset(&peerInfo, 0, sizeof(peerInfo));
    memcpy(peerInfo.peer_addr, peerMAC, 6);
    peerInfo.channel = 0;
    peerInfo.encrypt = false;
    peerInfo.ifidx = WIFI_IF_STA;

    if (esp_now_is_peer_exist(peerMAC)) {
    esp_now_del_peer(peerMAC);
  }
  if (esp_now_add_peer(&peerInfo) != ESP_OK) {
  } else {
     Serial.println("Peer added successfully");
  }
}

// ---------------------- Setup BLE (MASTER only) ----------------------
void setupBT() {
  Serial.println("Initializing BLE...");
  
  // Initialize BLE Device
  BLEDevice::init("CornholeBT");

  // Create the BLE Server
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  // Create the BLE Service
  BLEService *pService = pServer->createService(SERVICE_UUID);

  // Create a BLE Characteristic
  pCharacteristic = pService->createCharacteristic(
                      CHARACTERISTIC_UUID,
                      BLECharacteristic::PROPERTY_READ |
                      BLECharacteristic::PROPERTY_WRITE |
                      BLECharacteristic::PROPERTY_NOTIFY
                    );

  // Add a Descriptor for the Characteristic (Client Characteristic Configuration Descriptor (CCCD))
  pCharacteristic->addDescriptor(new BLE2902());

  // Set characteristic callback to handle incoming data
  pCharacteristic->setCallbacks(new MyCallbacks());

  // Start the service
  pService->start();
  pServer->startAdvertising();

  // Start advertising after setting up services and characteristics
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);  // Helps with iPhone connection issues
  pAdvertising->setMinPreferred(0x12);
  
  Serial.println("BLE Device is now advertising");
}

// ---------------------- Setup OTA (MASTER only) ----------------------
void setupOta(){
  ArduinoOTA.onStart([]() {
    String type;
    if (ArduinoOTA.getCommand() == U_FLASH) {
      type = "sketch";
    } else {  // U_SPIFFS
      type = "filesystem";
    }
    Serial.println("Start updating " + type);
  });
  ArduinoOTA.onEnd([]() {
    Serial.println("\nEnd");
  });
  ArduinoOTA.onProgress([](unsigned int progress, unsigned int total) {
    Serial.printf("Progress: %u%%\r", (progress / (total / 100)));
  });
  ArduinoOTA.onError([](ota_error_t error) {
    Serial.printf("Error[%u]: ", error);
    if (error == OTA_AUTH_ERROR) {
      Serial.println("Auth Failed");
    } else if (error == OTA_BEGIN_ERROR) {
      Serial.println("Begin Failed");
    } else if (error == OTA_CONNECT_ERROR) {
      Serial.println("Connect Failed");
    } else if (error == OTA_RECEIVE_ERROR) {
      Serial.println("Receive Failed");
    } else if (error == OTA_END_ERROR) {
      Serial.println("End Failed");
    }
  });

  ArduinoOTA.begin();  
  Serial.println("OTA Ready");
}

// ---------------------- Setup Web Server (MASTER only) ----------------------
void setupWebServer() {
    server.on("/", HTTP_GET, [](AsyncWebServerRequest *request){
    Serial.println("Root page accessed");
        String html = "<html><body><h1>Cornhole Admin Panel</h1>";
        html += "<form action='/setColor' method='GET'>";
        html += "Color (RGB): <input type='text' name='r' placeholder='Red'> ";
        html += "<input type='text' name='g' placeholder='Green'> ";
        html += "<input type='text' name='b' placeholder='Blue'><br>";
        html += "<button type='submit'>Set Color</button></form><br>";

        html += "<form action='/setEffect' method='GET'>";
        html += "Effect: <select name='effect'>";
        for (int i = 0; i < (sizeof(effects) / sizeof(effects[0])); i++) {
            html += "<option value='" + String(i) + "'>" + effects[i] + "</option>";
        }
        html += "</select><br>";
        html += "<button type='submit'>Set Effect</button></form><br>";

        html += "<form action='/setBrightness' method='GET'>";
        html += "Brightness (0-255): <input type='text' name='brightness'><br>";
        html += "<button type='submit'>Set Brightness</button></form><br>";

        html += "</body></html>";
        request->send(200, "text/html", html);
    });

    // Set Color Handler
    server.on("/setColor", HTTP_GET, [](AsyncWebServerRequest *request){
        if (request->hasParam("r") && request->hasParam("g") && request->hasParam("b")) {
            int r = request->getParam("r")->value().toInt();
            int g = request->getParam("g")->value().toInt();
            int b = request->getParam("b")->value().toInt();
            currentColor = CRGB(constrain(r, 0, 255), constrain(g, 0, 255), constrain(b, 0, 255));
            ledEffects.setColor(currentColor);
            sendData("espNow", "COLOR", String(r) + "," + String(g) + "," + String(b));
            if (deviceRole == MASTER) {
              sendData("app", "COLOR", String(r) + "," + String(g) + "," + String(b));
            }
            request->send(200, "text/plain", "Color updated to: R=" + String(r) + " G=" + String(g) + " B=" + String(b));
        } else {
            request->send(400, "text/plain", "Missing parameters");
        }
    });

    // Set Effect Handler
    server.on("/setEffect", HTTP_GET, [](AsyncWebServerRequest *request){
        if (request->hasParam("effect")) {
            int effectIdx = request->getParam("effect")->value().toInt();
            if (effectIdx >= 0 && effectIdx < (sizeof(effects) / sizeof(effects[0]))) {
                effectIndex = effectIdx;
                ledEffects.applyEffect(effects[effectIndex]);
                sendData("espNow","Effect",effects[effectIndex]);
                if (deviceRole == MASTER) {
                  sendData("app","Effect",effects[effectIndex]);
                }
                request->send(200, "text/plain", "Effect updated to: " + effects[effectIdx]);
            } else {
                request->send(400, "text/plain", "Invalid effect index");
            }
        } else {
            request->send(400, "text/plain", "Missing effect parameter");
        }
    });

    // Set Brightness Handler
    server.on("/setBrightness", HTTP_GET, [](AsyncWebServerRequest *request){
        if (request->hasParam("brightness")) {
            int brightnessValue = request->getParam("brightness")->value().toInt();
            brightness = constrain(brightnessValue, 0, 255);
            FastLED.setBrightness(brightness);
            FastLED.show();
            sendData("espNow","BRIGHTNESS",String(brightness));
            if (deviceRole == MASTER) {
              sendData("app","BRIGHTNESS",String(brightness));
            }
            request->send(200, "text/plain", "Brightness updated to: " + String(brightness));
        } else {
            request->send(400, "text/plain", "Missing brightness parameter");
        }
    });

    server.begin();
    Serial.println("HTTP Server started");
}

// ---------------------- Data Handling Functions ----------------------
void handleBluetoothData(String command) {
  String accumulatedData = command;  // Accumulate the incoming command

  // Check if the accumulated data contains a full command (terminated by ';')
  int endIndex = accumulatedData.indexOf(';');
  
  while (endIndex != -1) {
    String completeCommand = accumulatedData.substring(0, endIndex);
    
    // Process the complete command
    processCommand(completeCommand);
    esp_err_t result = esp_now_send(peerMAC, (uint8_t *)completeCommand.c_str(), completeCommand.length());
    //sendData("espNow", completeCommand, "");
    Serial.println("Received full data: " + completeCommand);

    // Remove the processed command from accumulated data
    accumulatedData = accumulatedData.substring(endIndex + 1);
    
    // Check for the next command in the remaining data
    endIndex = accumulatedData.indexOf(';');
  }
}

void processCommand(String command) {
  preferences.begin("cornhole", false);
  if (command == "CLEAR_ALL") {
    preferences.clear(); // Clear all preferences
    const char* message = "CLEAR_ALL";
    esp_err_t result = esp_now_send(peerMAC, (uint8_t *)message, strlen(message));
    Serial.println("All saved variables cleared.");
    delay(3000);
    sendRestartCommand();
    lastEspNowMessage = "";
    lastAppMessage = "";

  } else if (command.startsWith("n2:")) {
      board2Name = command.substring(3);
      //Serial.println("Sending Board 2 info to App: " + command);

  } else if (command.startsWith("SSID:")) {
      ssid = command.substring(5);
      preferences.putString("ssid", ssid);
      Serial.println("SSID updated to: " + ssid);

  } else if (command.startsWith("PW:")) {
      password = command.substring(3);
      preferences.putString("password", password);
      Serial.println("Password updated.");

  } else if (command.startsWith("INITIALCOLOR:")) {
      int r, g, b;
      sscanf(command.c_str(), "INITIALCOLOR:%d,%d,%d", &r, &g, &b);
      initialColor = CRGB(constrain(r, 0, 255), constrain(g, 0, 255), constrain(b, 0, 255));
      preferences.putInt("initialColorR", r);
      preferences.putInt("initialColorG", g);
      preferences.putInt("initialColorB", b);
      ledEffects.setColor(initialColor);
      ledEffects.setInitialColor(initialColor);
      Serial.println("Initial color updated.");

  } else if (command.startsWith("SPORTCOLOR1:")) {
      int r, g, b;
      sscanf(command.c_str(), "SPORTCOLOR1:%d,%d,%d", &r, &g, &b);
      CRGB newColor1 = CRGB(constrain(r, 0, 255), constrain(g, 0, 255), constrain(b, 0, 255));
      preferences.putInt("sportsColor1R", r);
      preferences.putInt("sportsColor1G", g);
      preferences.putInt("sportsColor1B", b);
      ledEffects.setSportsEffectColors(newColor1, sportsEffectColor2);
      Serial.println("Sports Effect Color1 updated.");

  } else if (command.startsWith("SPORTCOLOR2:")) {
    int r, g, b;
    sscanf(command.c_str(), "SPORTCOLOR2:%d,%d,%d", &r, &g, &b);
    CRGB newColor2 = CRGB(constrain(r, 0, 255), constrain(g, 0, 255), constrain(b, 0, 255));
    preferences.putInt("sportsColor2R", r);
    preferences.putInt("sportsColor2G", g);
    preferences.putInt("sportsColor2B", b);
    ledEffects.setSportsEffectColors(sportsEffectColor1, newColor2);
    Serial.println("Sports Effect Color2 updated.");

  } else if (command.startsWith("B1:")) {
      board1Name = command.substring(3);
      preferences.putString("board1Name", board1Name);
      Serial.println("Board1 Name updated to: " + board1Name);


  } else if (command.startsWith("B2:")) {
      board2Name = command.substring(3);
      preferences.putString("board2Name", board2Name);
      Serial.println("Board2 Name updated to: " + board2Name);

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

  } else if (command.startsWith("Effect:")) { 
        String effect = command.substring(7);
        effectIndex = getEffectIndex(effect); // Set the effect index based on received effect
        ledEffects.applyEffect(effect);
        Serial.println("Effect set to: " + effects[effectIndex]);

  } else if (command.startsWith("ColorIndex:")) {
       int index = command.substring(11).toInt();
       if (index >= 0 && index < (sizeof(colors) / sizeof(colors[0]))) {
        colorIndex = index;
        currentColor = colors[colorIndex];
         ledEffects.setColor(currentColor);
//      sendData("espNow", "ColorIndex", String(colorIndex));
      if (deviceRole == MASTER) {
          sendData("app", "ColorIndex", String(colorIndex));
      }

      // Set effect to "Solid" to maintain the color
      // effectIndex = getEffectIndex("Solid");
      // Serial.println("EffectIndex set to Solid");
  } else {
      Serial.println("Invalid color index");
  } 
  } else if (command.startsWith("brightness:")) { // Not sure if needed
      sscanf(command.c_str(), "brightness:%d", &brightness);
      ledEffects.setBrightness(brightness); // Use library's method if available
      Serial.println("Brightness set to: " + String(brightness));

  } else if (command.startsWith("toggleWiFi")) {
        String status = command.substring(11);
        bool wifiStatus = (status == "on");
        toggleWiFi(wifiStatus);
        Serial.println("WiFi toggled to: " + String(status));

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

  } else if (command.startsWith("Restart")) {
        sendRestartCommand();

  } else if (command.startsWith("GET_SETTINGS")) {
        sendSettings();
        Serial.println("Settings sent.");

  } else if (command == "GET_INFO") {
    sendBoardInfo();

  } else if (command.startsWith("SET_ROLE:")) {
      String newRole = command.substring(9);
      if (newRole == "MASTER" || newRole == "SLAVE") {
          preferences.begin("cornhole", false);
          preferences.putString("deviceRole", newRole);
          preferences.end();
          Serial.println("Role updated to: " + newRole);
          sendData("app", "RoleUpdated", newRole);
          sendRestartCommand();
      } else {
          Serial.println("Invalid role specified.");
      }

  } else if (command.startsWith("UPDATE")) {
        // Handle OTA updates or other update commands
        // Example: startOtaUpdate(command.substring(7));
        Serial.println("Update command received.");
  } else {
        Serial.println("Unknown command: " + command);
  }



  preferences.end();
}

void sendRestartCommand() {
  const char* message = "Restart";
  esp_now_send(peerMAC, (uint8_t *)message, strlen(message));
  Serial.println("Restart command sent successfully.");
  delay(10000);
  ESP.restart();
}

void sendBoardInfo() {
  char data[256];

  if (deviceRole == MASTER) {
  sprintf(data, "n1:%s;m1:%02x:%02x:%02x:%02x:%02x:%02x;i1:%s;l1:%d;v1:%d",
            board1Name.c_str(),
            deviceMAC[0], deviceMAC[1], deviceMAC[2],
            deviceMAC[3], deviceMAC[4], deviceMAC[5],
            ipAddress.c_str(),
            readBatteryLevel(),
            (int)readBatteryVoltage());
  updateBluetoothData(data);
  Serial.print("Sending Board info to app: ");
  Serial.println(data);
  } else {
  sprintf(data, "n2:%s;m2:%02x:%02x:%02x:%02x:%02x:%02x;i2:%s;l2:%d;v2:%d;",
            board2Name.c_str(),
            deviceMAC[0], deviceMAC[1], deviceMAC[2],
            deviceMAC[3], deviceMAC[4], deviceMAC[5],
            ipAddress.c_str(),
            readBatteryLevel(),
            (int)readBatteryVoltage());
   esp_err_t result = esp_now_send(peerMAC, (uint8_t *)data, strlen(data));
  Serial.print("Sending Board info to ESP-NOW: ");
  Serial.println(data);
  }

}

// ---------------------- BLE and ESP-NOW Callbacks ----------------------
void onDataRecv(const esp_now_recv_info_t *info, const uint8_t *incomingData, int len) {
    if (memcmp(info->src_addr, deviceMAC, 6) == 0) {
        // Message sent from self, ignore
        Serial.println("Received own message via ESP-NOW, ignoring.");
        return;
    }

  char msg[256];
  snprintf(msg, sizeof(msg), "Data received from: %02x:%02x:%02x:%02x:%02x:%02x", info->src_addr[0], info->src_addr[1], info->src_addr[2], info->src_addr[3], info->src_addr[4], info->src_addr[5]);
   
  String receivedData = String((char*)incomingData).substring(0, len);
  Serial.println("Received data: " + receivedData);

    if (len == sizeof(struct_message)) {
        // Received data is a struct_message
        memcpy(&board2, incomingData, sizeof(board2));
        board2DataReceived = true; // Set the flag
    } else {
        // Received data is a String message
        espNowDataBuffer = String((char*)incomingData).substring(0, len);
        espNowDataReceived = true; // Set the flag
        sendData("app", receivedData, "");
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

String macToString(const uint8_t *mac) {
  char macStr[18];
  snprintf(macStr, sizeof(macStr), "%02X:%02X:%02X:%02X:%02X:%02X", 
           mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
  return String(macStr);
}

// ---------------------- Communication Functions ----------------------
void sendSettings() {
    char data[512];
    sprintf(data, "S:SSID:%s;PW:%s;B1:%s;B2:%s;COLORINDEX:%d;SPORTCOLOR1:%d,%d,%d;SPORTCOLOR2:%d,%d,%d;BRIGHT:%d;SIZE:%lu;SPEED:%lu;CELEB:%lu;TIMEOUT:%d",
            ssid.c_str(),
            password.c_str(),
            board1Name.c_str(),
            board2Name.c_str(),
            colorIndex,
            sportsEffectColor1.r, sportsEffectColor1.g, sportsEffectColor1.b,
            sportsEffectColor2.r, sportsEffectColor2.g, sportsEffectColor2.b,
            brightness,
            blockSize,
            effectSpeed,
            irTriggerDuration,
            inactivityTimeout);

//   sendData("espNow", "SETTINGS", String(data));
    if (deviceRole == MASTER) {
      sendData("app", String(data),"");
    }
}

void sendData(const String& device, const String& type, const String& data) {
  char messageBuffer[250];
  String currentMessage;

  if (device == "espNow") {
    snprintf(messageBuffer, sizeof(messageBuffer), "%s:%s", type.c_str(), data.c_str());
    String currentMessage = String(messageBuffer);
    
    // Check if the current message is different from the last sent message
    if (currentMessage != lastEspNowMessage) {
      esp_now_send(peerMAC, (uint8_t *)currentMessage.c_str(), currentMessage.length());
      Serial.println("Sending to ESP-NOW: " + currentMessage);
      
      // Update the last sent message
      lastEspNowMessage = currentMessage;
    } else {
      Serial.println("Duplicate ESP-NOW message detected. Skipping send.");
    }
  }
  
  else if (device == "app" && deviceRole == MASTER) {
    if (data == "") {
      currentMessage = type;
    } else {
      currentMessage = type + ":" + data + ";";
    }
    
    // Check if the current message is different from the last sent message
    if (currentMessage != lastAppMessage) {
      updateBluetoothData(currentMessage);
      Serial.println("Sending to app: " + currentMessage);
      
      // Update the last sent message
      lastAppMessage = currentMessage;
    } else {
      Serial.println("Duplicate App message detected. Skipping send.");
    }
  }
}

void updateBluetoothData(String data) {
    if (deviceRole != MASTER) return; // Only MASTER handles BLE updates

    const int maxChunkSize = 20;  // Maximum BLE payload size is 20 bytes
    String message = data;  // Full message to send
    int totalChunks = (message.length() + maxChunkSize - 1) / maxChunkSize;  // Total number of chunks

    for (int i = 0; i < totalChunks; i++) {
        int startIdx = i * maxChunkSize;
        int endIdx = min(startIdx + maxChunkSize, (int)message.length());  // Cast message.length() to int

        String chunk = message.substring(startIdx, endIdx);
        // Send the chunk instead of the entire message
        pCharacteristic->setValue(chunk.c_str());  // Convert String to C-string for BLE transmission
        pCharacteristic->notify();  // Send the chunk via BLE notification
        delay(20);  // Delay to avoid congestion
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
  if (deviceRole == MASTER) {
    sendData("app", "ColorIndex", String(colorIndex));
  }
  Serial.println("Single Click: Color changed to index " + String(colorIndex));
}

void doubleClick() {
  if (!lightsOn) {
    Serial.println("Lights are off, skipping effect application.");
    return;
  }
  effectIndex = (effectIndex + 1) % (sizeof(effects) / sizeof(effects[0]));
  ledEffects.applyEffect(effects[effectIndex]);
  sendData("espNow","Effect",effects[effectIndex]);
  if (deviceRole == MASTER) {
    sendData("app","Effect",effects[effectIndex]);
  }
  Serial.println("Double Click: Effect changed to " + effects[effectIndex]);
}

void longPressStart() {
  toggleLights(!lightsOn);
 
  String message = String(lightsOn ? "on" : "off");
  sendData("espNow","toggleLights",lightsOn ? "on" : "off");
  if (deviceRole == MASTER) {
  }
  Serial.println("Long Press: Lights turned " + message);
}

void longPressStop() {
    // Log stop for debugging, if needed
    sendData("app","toggleLights",lightsOn ? "on" : "off");
    Serial.println("Long Press Released");
}

// ---------------------- Utility Functions ----------------------
void toggleLights(bool status) {
  lightsOn = status;
  ledEffects.setColor(lightsOn ? currentColor : CRGB::Black); // Set color if on, black if off
  String message = String(status ? "on" : "off");

  Serial.print("Lights are: ");
  Serial.println(message);
}

void toggleWiFi(bool status) {
  wifiEnabled = status;
  if (wifiEnabled) {
    Serial.println("WiFi enabled");
    setupWiFi();
  } else {
    Serial.println("WiFi disabled");
    WiFi.disconnect();
    WiFi.mode(WIFI_OFF);
  }
}

void toggleEspNow(bool status) {
  espNowEnabled = status;
  if (espNowEnabled) {
    Serial.println("ESP-NOW enabled");
    setupEspNow();
  } else {
    Serial.println("ESP-NOW disabled");
    esp_now_deinit();
  }
}

void btPairing(){
   if (!deviceConnected) {
    if (deviceRole == MASTER) {
      pServer->startAdvertising();  // restart advertising
      Serial.println("BLE in pairing mode");
    }
    oldDeviceConnected = deviceConnected;
    deviceConnected = false;
  } else {
    deviceConnected = true;

    //currentColor = colors[colorIndex];
    delay(1000);
    sendData("app", "ColorIndex", String(colorIndex));
    sendData("app","Effect",effects[effectIndex]);
    Serial.println("Bluetooth Device paired successfully");
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
    ledEffects.celebrationEffect();
    Serial.println("IR Sensor Triggered: Celebration Effect Started");
  }

  if (effectRunning && (millis() - effectStartTime >= effectDuration)) {
    effectRunning = false;
    irTriggered = false;
    ledEffects.setColor(currentColor);
    Serial.println("IR Sensor Triggered: Celebration Effect Ended");
  }
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
  int batteryLevel = map((int)(batteryVoltage * 100), 0, 1200, 0, 100); // Assuming 12V max
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