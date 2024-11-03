//conrnhole_master.ino
#include <WiFi.h>
#include <FastLED.h>
#include <OneButton.h>
#include <esp_now.h>
#include <esp_wifi.h>
#include <BLEDevice.h>

#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <Preferences.h>
#include <ArduinoOTA.h>
#include <HTTPUpdate.h>

// LED Setup
#define NUM_LEDS_RING   120
#define NUM_LEDS_BOARD  216
#define RING_LED_PIN    32
#define BOARD_LED_PIN   33
#define LED_TYPE        WS2812B
#define COLOR_ORDER     GRB
#define VOLTS           5
#define MAX_AMPS        2500

// Button and Sensor Pins
#define BUTTON_PIN 14
#define SENSOR_PIN 12
#define BATTERY_PIN 35

//  Configurable Varibales
Preferences preferences;

// WiFi Credentials for AP mode
String ssid = "CornholeAP";
String password = "Funforall";

// LED Setup
String board1Name = "Board 1";
String board2Name = "Board 2";
int brightness = 25;
unsigned long blockSize = 15;
unsigned long effectSpeed = 25; // Replace effectSpeed
int inactivityTimeout = 30;    // Variable for inactivity timeout
unsigned long irTriggerDuration = 4000;
CRGB initialColor = CRGB::Blue;
CRGB sportsEffectColor1 = CRGB(12,35,64);
CRGB sportsEffectColor2 = CRGB(241,90,34);

unsigned long lastActivityTime = 0;
    
// MAC Addresses for ESP-NOW
uint8_t masterMAC[] = {0x24, 0x6F, 0x28, 0x88, 0xB4, 0xC8}; // MAC address of the master board
uint8_t slaveMAC[] = {0x24, 0x6F, 0x28, 0x88, 0xB4, 0xC9};  // MAC address of the slave board
String ipAddress;

#define ADC_MAX 4095
#define V_REF 3.3
#define R1 10000.0
#define R2 3900.0

CRGB ringLeds[NUM_LEDS_RING];
CRGB boardLeds[NUM_LEDS_BOARD];

// Color Definitions
#define BURNT_ORANGE    CRGB(191, 87, 0)
unsigned long colorChangeInterval = 5000; // Change color every 5 seconds
unsigned long lastColorChangeTime = 0;
int currentColorIndex = 0;
CRGB colors[] = {CRGB::Blue, CRGB::Green, CRGB::Red, CRGB::White, BURNT_ORANGE, CRGB::Aqua, CRGB::Purple, CRGB::Pink}; // Define your colors
int colorIndex = 0;
CRGB startColor;
CRGB endColor;
float blendAmount = 0.0;
float blendStep = 0.01; // Adjust this value for smoother transitions
CRGB currentColor = CRGB::Blue;

// Effect Variables
String effects[] = {"Solid", "Twinkle", "Chase", "Wipe", "Bounce", "Breathing", "Gradient", "Rainbow",  "America", "Sports"};
int effectIndex = 0;
bool lightsOn = true;
unsigned long previousMillis = 0;
int chasePosition = 0;
String currentEffect = "Solid";

// Button Setup
OneButton button(BUTTON_PIN, true);

// IR Trigger variables
bool irTriggered = false;

//Bluetooth Setup
#define SERVICE_UUID        "baf6443e-a714-4114-8612-8fc18d1326f7"
#define CHARACTERISTIC_UUID "5d650eb7-c41b-44f0-9704-3710f21e1c8e"

BLEServer* pServer = NULL;
BLECharacteristic* pCharacteristic = NULL;
bool deviceConnected = false;
bool oldDeviceConnected = false;
String rxValue;
uint32_t previousMillisBT = 0;
const uint32_t intervalBT = 10000; // 10 seconds

bool espNowEnabled = true; // ESP-NOW synchronization is enabled by default
bool wifiConnected = false;
bool usingFallbackAP = false;
bool wifiEnabled = true; // Variable to toggle WiFi on and off

// Add these declarations
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

//Pairing Variables
CRGB previousColor;
String previousEffect;
int previousBrightness;

// Function declarations
void setupWiFi();
void setupEspNow();
void setupBT();
void setupOta();
void handleBluetoothData(String data);
void updateBluetoothData(String data);
void onDataRecv(const esp_now_recv_info *info, const uint8_t *incomingData, int len);
void onDataSent(const uint8_t *mac_addr, esp_now_send_status_t status);
String macToString(const uint8_t *mac);
void sendSettings();
void sendBoard1Info();
void sendBoard2Info(struct_message board2);
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
void solidChase(CRGB color);
void bounceEffect(CRGB color);
void gradientChaseEffect(CRGB color);
void rainbowChase();
void redWhiteBlueChase();
void sportsChase();
void colorWipe(CRGB color);
void twinkle(CRGB color);
void breathing(CRGB color);
void celebrationEffect();
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
    rxValue = pCharacteristic->getValue();

    if (rxValue.length() > 0) {
      handleBluetoothData(rxValue);
      rxValue = ""; // Clear the value after processing
    }
  }
};

void setup() {
  Serial.begin(115200);
  Serial.println("Starting setup...");

  preferences.begin("cornhole", false);
  bool tpInit = preferences.isKey("nvsInit");   

  if (tpInit == false) {
      preferences.end();                           // close the namespace in RO mode and...
      preferences.begin("cornhole", false);
        preferences.putString("ssid", "CornholeAP");
        preferences.putString("password", "Funforall");
        preferences.putString("board1Name", "Board 1");
        preferences.putString("board2Name", "Board 2");
        CRGB(preferences.putInt("initialColorR", 0),
             preferences.putInt("initialColorG", 0),
             preferences.putInt("initialColorB", 255));
        CRGB(preferences.putInt("sportsColor1R", 191),
             preferences.putInt("sportsColor1G", 87),
             preferences.putInt("sportsColor1B", 0));
        CRGB(preferences.putInt("sportsColor2R", 255),
             preferences.putInt("sportsColor2G", 255),
              preferences.putInt("sportsColor2B", 255));
        preferences.putInt("brightness", 50);
        preferences.putULong("blockSize", 15);
        preferences.putULong("effectSpeed", 25);
        preferences.putInt("inactivityTimeout", 30);
        preferences.putBool("nvsInit", true); 

        }

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
        brightness = preferences.getInt("brightness");
        blockSize = preferences.getULong("blockSize");
        effectSpeed = preferences.getULong("effectSpeed");
        inactivityTimeout = preferences.getInt("inactivityTimeout");
      preferences.end();

  currentColor = initialColor;
  
  setupWiFi();
  esp_wifi_set_mac(WIFI_IF_STA, masterMAC);
  setupEspNow();
  setupBT();
  setupOta();

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
  button.attachLongPressStart(longPressStart);
  button.attachLongPressStop(longPressStop);
  powerOnEffect();

  strcpy(board2.device, "Board 2");
  strcpy(board2.name, board2Name.c_str());
  memcpy(board2.macAddr, slaveMAC, sizeof(slaveMAC));
  strcpy(board2.ipAddr, WiFi.localIP().toString().c_str());

  Serial.println("Setup completed.");
}

void loop() {
  unsigned long currentMillis = millis();
  button.tick();
  handleIRSensor();
  
  if (!deviceConnected && currentMillis - previousMillisBT >= intervalBT) {
    previousMillisBT = currentMillis;
    btPairing();
  } else {
    if (rxValue.length() > 0) {
      handleBluetoothData(rxValue);
      rxValue = ""; // Clear the value after processing
    }
  }
  
  // Process ESP-NOW data
  if (espNowDataReceived) {
    espNowDataReceived = false; // Reset the flag
    processEspNowData(espNowDataBuffer); // Process the received String data
  }
  
  if (board2DataReceived) {
    board2DataReceived = false; // Reset the flag
    sendBoard2Info(board2); // Send the board2 info via BLE
  }
  
  if (lightsOn) {
    applyEffect(effects[effectIndex]);
  }
  
  ArduinoOTA.handle();
}

void setupWiFi() {
  Serial.println("Connecting to WiFi...");
    WiFi.mode(WIFI_STA);
    WiFi.begin(ssid, password);

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
  ipAddress = WiFi.localIP().toString().c_str();
  usingFallbackAP = "false";
  Serial.println("WiFi connected");
  Serial.print("IP address: ");
  Serial.println(WiFi.localIP());
}

void setupEspNow() {
  if (esp_now_init() != ESP_OK) {
    return;
  }
  esp_now_register_recv_cb(onDataRecv);
  esp_now_register_send_cb(onDataSent);

  esp_now_peer_info_t peerInfo;
  memset(&peerInfo, 0, sizeof(peerInfo));
  memcpy(peerInfo.peer_addr, slaveMAC, 6);
  peerInfo.channel = 0;
  peerInfo.encrypt = false;
  peerInfo.ifidx = WIFI_IF_STA;

  if (esp_now_is_peer_exist(slaveMAC)) {
    esp_now_del_peer(slaveMAC);
  }

  if (esp_now_add_peer(&peerInfo) != ESP_OK) {
  } else {
    sendData("espNow","Color", String(currentColor.r) + "," + String(currentColor.g) + "," + String(currentColor.b));
    sendData("espNow","Effect",effects[effectIndex]);
    Serial.println("Peer added successfully");
  }
}

void onDataRecv(const esp_now_recv_info *info, const uint8_t *incomingData, int len) {
  if (len == sizeof(struct_message)) {
    // Received data is a struct_message
    memcpy(&board2, incomingData, sizeof(board2));
    board2DataReceived = true; // Set the flag
  } else {
    // Received data is a String message
    espNowDataBuffer = String((char*)incomingData).substring(0, len);
    espNowDataReceived = true; // Set the flag
  }
}

void onDataSent(const uint8_t *mac_addr, esp_now_send_status_t status) {
  Serial.print(" Status: ");
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
  snprintf(macStr, sizeof(macStr), "%02x:%02x:%02x:%02x:%02x:%02x", mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
  return String(macStr);
}

void setupBT() {
  Serial.println("Waiting for a client connection to notify...");
  
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

  // Start advertising after setting up services and characteristics
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);  // helps with iPhone connection issues
  pAdvertising->setMinPreferred(0x12);
  
  BLEDevice::startAdvertising();
  Serial.println("BLE Device is now advertising");
}

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
}

String accumulatedData = ""; // Global variable to store accumulated data

void handleBluetoothData(String command) {
  accumulatedData += command;  // Accumulate the incoming command

  // Check if the accumulated data contains a full command (terminated by ';')
  int endIndex = accumulatedData.indexOf(';');
  
  while (endIndex != -1) {
    String completeCommand = accumulatedData.substring(0, endIndex);
    
    // Process the complete command
    processCommand(completeCommand);
    Serial.println("Received full data: " + completeCommand);

    // Remove the processed command from accumulated data
    accumulatedData = accumulatedData.substring(endIndex + 1);
    
    // Check for the next command in the remaining data
    endIndex = accumulatedData.indexOf(';');
  }
}

void processCommand(String command) {
  preferences.begin("cornhole",false);
  if (command == "CLEAR_ALL") {
    preferences.clear(); // Clear all preferences
    const char* message = command.c_str();
    esp_err_t result = esp_now_send(slaveMAC, (uint8_t *)message, strlen(message));
    Serial.println("All saved variables cleared.");
    delay(3000);
    sendRestartCommand();
  } else  if  (command.startsWith("SSID:")) {
        ssid = command.substring(5);
        preferences.putString("ssid", ssid);
        Serial.print("SSID set to: ");
        Serial.println(ssid);

  } else if  (command.startsWith("PW:")) {
        password = command.substring(3);
        preferences.putString("password", password);
        Serial.print("Password set to: ");
        Serial.println(password);

  } else if (command.startsWith("INITIALCOLOR:")) {
    int r, g, b;
    sscanf(command.c_str(), "INITIALCOLOR:%d,%d,%d", &r, &g, &b);
    initialColor = CRGB(r, g, b);
    preferences.putInt("initialColorR", r);
    preferences.putInt("initialColorG", g);
    preferences.putInt("initialColorB", b);
    Serial.printf("Initial color set to R:%d, G:%d, B:%d\n", r, g, b);

  } else if (command.startsWith("SPORTCOLOR1:")) {
    int r, g, b;
    sscanf(command.c_str(), "SPORTCOLOR1:%d,%d,%d", &r, &g, &b);
    sportsEffectColor1 = CRGB(r, g, b);
    preferences.putInt("sportsColor1R", r);
    preferences.putInt("sportsColor1G", g);
    preferences.putInt("sportsColor1B", b);
    Serial.printf("Sport Color 1 set to R:%d, G:%d, B:%d\n", r, g, b);

  } else if (command.startsWith("SPORTCOLOR2:")) {
    int r, g, b;
    sscanf(command.c_str(), "SPORTCOLOR2:%d,%d,%d", &r, &g, &b);
    sportsEffectColor2 = CRGB(r, g, b);
    preferences.putInt("sportsColor2R", r);
    preferences.putInt("sportsColor2G", g);
    preferences.putInt("sportsColor2B", b);
    Serial.printf("Sport Color 2 set to R:%d, G:%d, B:%d\n", r, g, b);

  } else if  (command.startsWith("B1:")) {
        board1Name = command.substring(3);
        preferences.putString("board1Name", board1Name);
        Serial.print("Board 1 Name set to: ");
        Serial.println(board1Name);

   } else if  (command.startsWith("B2:")) {
        board2Name = command.substring(3);
        preferences.putString("board1Name", board1Name);
        Serial.print("Board 2 Name set to: ");
        Serial.println(board2Name);
        sendData("espNow","B2",String(board2Name));

    } else if  (command.startsWith("BRIGHT:")) {
        sscanf(command.c_str(), "BRIGHT:%d", &brightness);
        preferences.putInt("brightness", brightness);
        FastLED.setBrightness(brightness);
        FastLED.show();
        Serial.print("Brightness set to: ");
        Serial.println(brightness);
        sendData("espNow","brightness", String(brightness));

    } else if (command.startsWith("SIZE:")) {
        sscanf(command.c_str(), "SIZE%lu", &blockSize);
        preferences.putULong("blockSize", blockSize);
        Serial.print("Effect size set to: ");
        Serial.println(blockSize);

    } else if (command.startsWith("SPEED:")) {
        sscanf(command.c_str(), "SPEED:%lu", &effectSpeed);
        preferences.putULong("effectSpeed", effectSpeed);
        Serial.print("Effect speed set to: ");
        Serial.println(effectSpeed);
        sendData("espNow","SPEED",String(effectSpeed));


    } else if (command.startsWith("CELEB:")) {
        sscanf(command.c_str(), "CELEB:%lu", &irTriggerDuration);
        preferences.putULong("irTriggerDuration", irTriggerDuration);
        Serial.print("Celebration duration set to: ");
        Serial.println(irTriggerDuration);

    } else if (command.startsWith("TIMEOUT:")) {
        sscanf(command.c_str(), "TIMEOUT:%d", &inactivityTimeout);
        preferences.putInt("inactivityTimeout", inactivityTimeout);
        Serial.print("Inactivity timeout set to: ");
        Serial.println(inactivityTimeout);

    } else if (command.startsWith("Effect:")) {
        String effect = command.substring(7);
        effectIndex = getEffectIndex(effect); // Set the effect index based on received effect
        applyEffect(effect);
        sendData("espNow","Effect", effect);

    } else if (command.startsWith("colorIndex:")) {
        int index;
        sscanf(command.c_str(), "colorIndex:%d", &index);
        if (index >= 0 && index < sizeof(colors) / sizeof(colors[0])) {
            currentColor = colors[index];
            setColor(currentColor);
            sendData("espNow","Color", String(currentColor.r) + "," + String(currentColor.g) + "," + String(currentColor.b));
            colorIndex = index; // Update the color index
            Serial.print("Color set to index: ");
            Serial.println(index);
        } else {
            Serial.println("Invalid color index");
        }

  } else if (command.startsWith("brightness:") && sscanf(command.c_str(), "brightness:%d", &brightness) == 1) {
    FastLED.setBrightness(brightness);
    FastLED.show();
    Serial.printf("Received brightness: %d\n", brightness);
    sendData("espNow","brightness", String(brightness));

    } else if (command.startsWith("toggleWiFi")) {
        String status = command.substring(11);
        bool wifiStatus = (status == "on");
        toggleWiFi(wifiStatus);

    } else if (command.startsWith("toggleLights")) {
        String status = command.substring(13);
        bool lightsStatus = (status == "on");
        toggleLights(lightsStatus);

    } else if (command.startsWith("toggleEspNow")) {
        String status = command.substring(13);
        bool espNowStatus = (status == "on");
        toggleEspNow(espNowStatus);

    } else if (command.startsWith("sendRestart")) {
        sendRestartCommand();

    } else if (command.startsWith("GET_SETTINGS")) {
        sendSettings();
        sendData("app","Color", String(currentColor.r) + "," + String(currentColor.g) + "," + String(currentColor.b));
        sendData("app","Effect",effects[effectIndex]);

    } else if (command =="GET_INFO") {
        const char* message = command.c_str();
        esp_err_t result = esp_now_send(slaveMAC, (uint8_t *)message, strlen(message));
        sendBoard1Info();
        

    } else if (command.startsWith("UPDATE")) {
        //sendBoard1Info();
        sendData("espNow","OTA","UPDATE");

    } else {
        Serial.println("Unknown BLE command");
    }
  preferences.end();
}

void updateBluetoothData(String data) {
    // Ensure the message ends with a delimiter
    if (!data.endsWith("#")) {
        data += "#"; 
    }

    const int maxChunkSize = 20;  // Maximum BLE payload size is 20 bytes
    String message = data;  // Full message to send
    int totalChunks = (message.length() + maxChunkSize - 1) / maxChunkSize;  // Total number of chunks

    for (int i = 0; i < totalChunks; i++) {
        int startIdx = i * maxChunkSize;
        int endIdx = min(startIdx + maxChunkSize, (int)message.length());  // Cast message.length() to int

        String chunk = message.substring(startIdx, endIdx);

        Serial.print("BLE Activity updated with chunk: ");
        Serial.println(chunk);  // Log the chunk that is being sent

        // Send the chunk instead of the entire message
        pCharacteristic->setValue(chunk.c_str());  // Convert String to C-string for BLE transmission
        pCharacteristic->notify();  // Send the chunk via BLE notification
        delay(20);  // Delay to avoid congestion
    }
}

void processEspNowData(String receivedData) {
  int r, g, b, brightness;

   if (receivedData.startsWith("Color:")) {
        String colorData = receivedData.substring(6); 
        
        if (sscanf(colorData.c_str(), "%d,%d,%d", &r, &g, &b) == 3) {
            currentColor = CRGB(r, g, b);
            setColor(currentColor);
            sendData("app", "Color", String(currentColor.r) + "," + String(currentColor.g) + "," + String(currentColor.b));
            Serial.printf("Received color: R=%d, G=%d, B=%d\n", r, g, b);
        } else {
            Serial.println("Failed to parse color data.");
        }

  } else if (receivedData.startsWith("Effect:")) {
    String effect = receivedData.substring(7);
    Serial.println("ESP-NOW effect: " + effect);
    effectIndex = getEffectIndex(effect);
    applyEffect(effect);
    sendData("app", "Effect", effects[effectIndex]);

  // } else if (sscanf(receivedData.c_str(), "%d,%d,%d", &r, &g, &b) == 3) {
  //   currentColor = CRGB(r, g, b);
  //   setColor(currentColor);
  //   sendData("app", "Color", String(currentColor.r) + "," + String(currentColor.g) + "," + String(currentColor.b));
  //   Serial.printf("Received color: R=%d, G=%d, B=%d\n", r, g, b);

  } else if (receivedData.startsWith("brightness:") && sscanf(receivedData.c_str(), "brightness:%d", &brightness) == 1) {
    FastLED.setBrightness(brightness);
    FastLED.show();
    Serial.printf("Received brightness: %d\n", brightness);
    sendData("app", "brightness", String(brightness));

  } else if (receivedData == "Board 2") {
    // Handle struct_message data if necessary
    // sendBoard1Info();
    // sendBoard2Info(receivedData);

  } else if (receivedData.startsWith("toggleLights:")) {
    String status = receivedData.substring(13);
    bool lightsStatus = (status == "on");
    toggleLights(lightsStatus);
    sendData("app", "toggleLights:", status);

  } else {
    Serial.print("Unknown data received:");
    Serial.println(receivedData);
  }
}

void sendSettings() {
    char data[512];
    sprintf(data, "S:SSID:%s;PW:%s;B1:%s;B2:%s;INITIALCOLOR:%d,%d,%d;SPORTCOLOR1:%d,%d,%d;SPORTCOLOR2:%d,%d,%d;BRIGHT:%d;SIZE:%d;SPEED:%d;CELEB:%d;TIMEOUT:%d;",
            ssid.c_str(),
            password.c_str(),
            board1Name.c_str(),
            board2Name.c_str(),
            initialColor.r, initialColor.g, initialColor.b,
            sportsEffectColor1.r, sportsEffectColor1.g, sportsEffectColor1.b,
            sportsEffectColor2.r, sportsEffectColor2.g, sportsEffectColor2.b,
            brightness,
            blockSize,
            effectSpeed,
            irTriggerDuration,
            inactivityTimeout);

    updateBluetoothData(data);
}

void sendData(const String& device, const String& type, const String& data) {
  char message[512];

  if (device == "espNow" || device == "both") {
    snprintf(message, sizeof(message), "%s:%s", type.c_str(), data.c_str());
    esp_now_send(slaveMAC, (uint8_t *)message, strlen(message));
    Serial.println("Sending to peer: " + String(message));
  }
  
  if (device == "app" || device == "both") {
    String message = type + ":" + data + "#";
    updateBluetoothData(message);
    Serial.println("Sending to app: " + message);
  }
}

void sendDefaults() {
    char message[512];
    sprintf(message, "S:SSID:%s;PW:%s;B2:%s;INITIALCOLOR:%d,%d,%d;SPORTCOLOR1:%d,%d,%d;SPORTCOLOR2:%d,%d,%d;BRIGHT:%d;SIZE:%d;SPEED:%d;CELEB:%d;TIMEOUT:%d;",
            ssid.c_str(),
            password.c_str(),
            board2Name.c_str(),
            initialColor.r, initialColor.g, initialColor.b,
            sportsEffectColor1.r, sportsEffectColor1.g, sportsEffectColor1.b,
            sportsEffectColor2.r, sportsEffectColor2.g, sportsEffectColor2.b,
            brightness,
            blockSize,
            effectSpeed,
            irTriggerDuration,
            inactivityTimeout);

  esp_now_send(slaveMAC, (uint8_t *)message, strlen(message));
  Serial.print("Default setting sent to Board 2");
}


void sendRestartCommand() {
  char message[8] = "Restart";
  esp_err_t result = esp_now_send(slaveMAC, (uint8_t *)message, strlen(message));

  if (result == ESP_OK) {
    Serial.println("Restart command sent successfully");
    delay(100);
    ESP.restart();
  } else {
    Serial.println("Error sending the restart command");
  }
}

void sendBoard1Info() {
  char data[512];

  sprintf(data, "1:n1:%s;m1:%02x:%02x:%02x:%02x:%02x:%02x;i1:%s;l1:%d;v1:%d;",
            board1Name,
            masterMAC[0], masterMAC[1], masterMAC[2],
            masterMAC[3], masterMAC[4], masterMAC[5],
            ipAddress,
            readBatteryLevel(),
            (int)readBatteryVoltage());

  updateBluetoothData(data);
    Serial.print("Sending Board 1 to app: ");
    Serial.println(data);
}

// Function to send board 2 information via BLE

void sendBoard2Info(struct_message board2){
  char data[512];

  sprintf(data, "2:n2:%s;m2:%02x:%02x:%02x:%02x:%02x:%02x;i2:%s;l2:%d;v2:%d;",
          board2.name,
          board2.macAddr[0], board2.macAddr[1], board2.macAddr[2],
          board2.macAddr[3], board2.macAddr[4], board2.macAddr[5],
          board2.ipAddr,
          board2.batteryLevel,
          board2.batteryVoltage);
  updateBluetoothData(data);
    // Serial.printf("Board 2 Info - Name: %s, MAC: %02x:%02x:%02x:%02x:%02x:%02x, IP: %s, Battery Level: %d%%, Voltage: %dV\n", 
    //               board2.name, 
    //               board2.macAddr[0], board2.macAddr[1], board2.macAddr[2], 
    //               board2.macAddr[3], board2.macAddr[4], board2.macAddr[5], 
    //               board2.ipAddr, 
    //               board2.batteryLevel, 
    //               board2.batteryVoltage);
    Serial.print("Sending Board 2 to app: ");
    Serial.println(data);
}

// void startOtaUpdate(String firmwareUrl) {
//   t_httpUpdate_return ret = ESPhttpUpdate.update(firmwareUrl);

//   switch (ret) {
//     case HTTP_UPDATE_FAILED:
//       Serial.printf("Update failed. Error (%d): %s\n", ESPhttpUpdate.getLastError(), ESPhttpUpdate.getLastErrorString().c_str());
//       break;

//     case HTTP_UPDATE_OK:
//       Serial.println("Update successful.");
//       break;
//   }
// }

void singleClick() {
  if (!lightsOn) {
    Serial.println("Lights are off, skipping color change.");
    return;
  }
  colorIndex = (colorIndex + 1) % (sizeof(colors) / sizeof(colors[0]));
  currentColor = colors[colorIndex];
  setColor(currentColor);
  sendData("both","Color", String(currentColor.r) + "," + String(currentColor.g) + "," + String(currentColor.b));
}

void doubleClick() {
  if (!lightsOn) {
    Serial.println("Lights are off, skipping effect application.");
    return;
  }
  effectIndex = (effectIndex + 1) % (sizeof(effects) / sizeof(effects[0]));
  applyEffect(effects[effectIndex]);
  sendData("both","Effect",effects[effectIndex]);
}

void longPressStart() {
    toggleLights(!lightsOn);
}

void longPressStop() {
    // Log stop for debugging, if needed
    Serial.println("Long Press Released");
}

void toggleLights(bool status) {
  lightsOn = status;
  setColor(lightsOn ? currentColor : CRGB::Black); // Set color if on, black if off
  String message = String(status ? "on" : "off");

  Serial.print("Lights are: ");
  Serial.println(message);
  
  sendData("both","toggleLights",message);
}

void toggleWiFi(bool status) {
  WiFi.mode(WIFI_STA);
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
    pServer->startAdvertising();  // restart advertising
    Serial.println("BLE in pairing mode");
    oldDeviceConnected = deviceConnected;
    deviceConnected = false;
  } else {
    deviceConnected = true;
    Serial.println("Bluetooth Device paired successfully");
    // delay(100);
    // currentColor = colors[colorIndex];
    // sendData("app","Color", String(currentColor.r) + "," + String(currentColor.g) + "," + String(currentColor.b));
    // sendData("app","Effect",effects[effectIndex]);
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
    celebrationEffect();
  }

  if (effectRunning && (millis() - effectStartTime >= effectDuration)) {
    effectRunning = false;
    irTriggered = false;
    setColor(currentColor);
  }
}

void applyEffect(String effect) {
  if (!lightsOn) {
    Serial.println("Lights are off, skipping effect application.");
        setColor(CRGB::Black); // Ensure all LEDs are off
   return;
  }
  if (effect == "Solid") {
    setColor(currentColor);
  } else if (effect == "Chase") {
    solidChase(currentColor);
  } else if (effect == "Bounce") {
    bounceEffect(currentColor);
  } else if (effect == "Gradient") {
    gradientChaseEffect(currentColor);
  } else if (effect == "Rainbow") {
    rainbowChase();
  } else if (effect == "America") {
    redWhiteBlueChase();
  } else if (effect == "Sports") {
    sportsChase();
  } else if (effect == "Wipe") {
    colorWipe(currentColor);
  } else if (effect == "Twinkle") {
    twinkle(currentColor);
  } else if (effect == "Breathing") {
    breathing();
  } else {
    Serial.println("Effect not recognized: " + effect);
  }
}

int getEffectIndex(String effect) {
  for (int i = 0; i < (sizeof(effects) / sizeof(effects[0])); i++) {
    if (effects[i] == effect) {
      return i;
    }
  }
  return 0;
}

void setColor(CRGB color) {
    if (!lightsOn) {
        color = CRGB::Black; // Ensure color is black if lights are off
    }
    fill_solid(ringLeds, NUM_LEDS_RING, color);
    fill_solid(boardLeds, NUM_LEDS_BOARD, color);
    FastLED.show();
}

void powerOnEffect() {
  for (int i = 0; i < NUM_LEDS_RING; i++) {
    ringLeds[i] = CHSV(i * 256 / NUM_LEDS_RING, 255, 255);
    FastLED.show();
    delay(5);
  }
  for (int i = 0; i < NUM_LEDS_BOARD; i++) {
    boardLeds[i] = CHSV(i * 256 / NUM_LEDS_BOARD, 255, 255);
    FastLED.show();
    delay(5);
  }
  setColor(initialColor);
}

void solidChase(CRGB color) {
  unsigned long currentMillis = millis();
  if (currentMillis - previousMillis >= effectSpeed) {
    previousMillis = currentMillis;

    float ringPosition = (float)chasePosition * NUM_LEDS_RING / NUM_LEDS_BOARD;

    for (int i = 0; i < NUM_LEDS_BOARD; i++) {
      int index = (i + chasePosition) % NUM_LEDS_BOARD;
      boardLeds[index] = (i < blockSize) ? color : CRGB::Black;
    }

    for (int i = 0; i < NUM_LEDS_RING; i++) {
      int index = (int)(i + ringPosition) % NUM_LEDS_RING;
      ringLeds[index] = (i < blockSize * 2) ? color : CRGB::Black;
    }

    chasePosition++;
    if (chasePosition >= NUM_LEDS_BOARD) {
      chasePosition = 0;
    }
    FastLED.show();
  }
}

void bounceEffect(CRGB color) {
  static const byte fadeAmt = 128;
  static const int deltaHue = 4;
  static int iDirection = 1;
  static int iPos = 0;
  static unsigned long previousMillis = 0;
  unsigned long currentMillis = millis();

  if (currentMillis - previousMillis >= effectSpeed) {
    previousMillis = currentMillis;

    iPos += iDirection;
    if (iPos == (NUM_LEDS_BOARD - blockSize) || iPos == 0)
      iDirection *= -1;

    fill_solid(boardLeds, NUM_LEDS_BOARD, CRGB::Black);
    fill_solid(ringLeds, NUM_LEDS_RING, CRGB::Black);

    for (int i = 0; i < blockSize; i++) {
      boardLeds[iPos + i] = color;
    }

    int ringPos = (iPos * NUM_LEDS_RING) / NUM_LEDS_BOARD;
    for (int i = 0; i < blockSize; i++) {
      ringLeds[(ringPos + i) % NUM_LEDS_RING] = color;
    }

    for (int j = 0; j < NUM_LEDS_BOARD; j++) {
      if (random(10) > 5)
        boardLeds[j].fadeToBlackBy(fadeAmt);
    }
    for (int j = 0; j < NUM_LEDS_RING; j++) {
      if (random(10) > 5)
        ringLeds[j].fadeToBlackBy(fadeAmt);
    }

    FastLED.show();
  }
}

void gradientChaseEffect(CRGB color) {
  int nextColorIndex = (colorIndex + 1) % (sizeof(colors) / sizeof(colors[0]));
  CRGB nextColor = colors[nextColorIndex];

  unsigned long currentMillis = millis();
  if (currentMillis - previousMillis >= effectSpeed) {
    previousMillis = currentMillis;

    float ringPosition = (float)chasePosition * NUM_LEDS_RING / NUM_LEDS_BOARD;

    for (int i = 0; i < NUM_LEDS_BOARD; i++) {
      int index = (i + chasePosition) % NUM_LEDS_BOARD;
      boardLeds[index] = (i < NUM_LEDS_BOARD / 2) ? blend(nextColor, color, 2 * i * 255 / NUM_LEDS_BOARD) : CRGB::Black;
    }

    for (int i = 0; i < NUM_LEDS_RING; i++) {
      int index = (int)(i + ringPosition) % NUM_LEDS_RING;
      ringLeds[index] = (i < NUM_LEDS_RING / 2) ? blend(nextColor, color, 2 * i * 255 / NUM_LEDS_RING) : CRGB::Black;
    }

    chasePosition++;
    if (chasePosition >= NUM_LEDS_BOARD) {
      chasePosition = 0;
    }
    FastLED.show();
  }
}

void rainbowChase() {
  unsigned long currentMillis = millis();
  if (currentMillis - previousMillis >= effectSpeed) {
    previousMillis = currentMillis;

    float ringPosition = (float)chasePosition * NUM_LEDS_RING / NUM_LEDS_BOARD;

    for (int i = 0; i < NUM_LEDS_BOARD; i++) {
      boardLeds[i] = CHSV((i + chasePosition) * 256 / NUM_LEDS_BOARD, 255, 255);
    }

    for (int i = 0; i < NUM_LEDS_RING; i++) {
      ringLeds[i] = CHSV((int)(i + ringPosition) * 256 / NUM_LEDS_RING, 255, 255);
    }

    chasePosition++;
    if (chasePosition >= NUM_LEDS_BOARD) {
      chasePosition = 0;
    }
    FastLED.show();
  }
}

void redWhiteBlueChase() {
  unsigned long currentMillis = millis();
  if (currentMillis - previousMillis >= effectSpeed) {
    previousMillis = currentMillis;

    CRGB colors[] = {CRGB::Red, CRGB::White, CRGB::Blue};
    int numColors = sizeof(colors) / sizeof(colors[0]);

    for (int i = 0; i < NUM_LEDS_BOARD; i++) {
      boardLeds[i] = colors[((i + chasePosition) / blockSize) % numColors];
    }
    for (int i = 0; i < NUM_LEDS_RING; i++) {
      ringLeds[i] = colors[((i + chasePosition) / blockSize) % numColors];
    }

    chasePosition++;
    if (chasePosition >= blockSize * numColors) {
      chasePosition = 0;
    }
    FastLED.show();
  }
}

void sportsChase() {
  unsigned long currentMillis = millis();
  if (currentMillis - previousMillis >= effectSpeed) {
    previousMillis = currentMillis;

    CRGB colors[] = {sportsEffectColor2, sportsEffectColor1};
    int numColors = sizeof(colors) / sizeof(colors[0]);

    for (int i = 0; i < NUM_LEDS_BOARD; i++) {
      boardLeds[i] = colors[((i + chasePosition) / blockSize) % numColors];
    }
    for (int i = 0; i < NUM_LEDS_RING; i++) {
      ringLeds[i] = colors[((i + chasePosition) / blockSize) % numColors];
    }

    chasePosition++;
    if (chasePosition >= blockSize * numColors) {
      chasePosition = 0;
    }
    FastLED.show();
  }
}

void colorWipe(CRGB color) {
  static int i = 0;
  static bool isTurningOn = true;
  static unsigned long previousMillis = 0;
  unsigned long currentMillis = millis();

  if (currentMillis - previousMillis >= effectSpeed) {
    previousMillis = currentMillis;

    if (isTurningOn) {
      if (i < NUM_LEDS_RING) {
        ringLeds[i] = color;
      }
      if (i < NUM_LEDS_BOARD) {
        boardLeds[i] = color;
      }
      i++;
      if (i >= NUM_LEDS_RING && i >= NUM_LEDS_BOARD) {
        isTurningOn = false;
        i = 0;
      }
    } else {
      if (i < NUM_LEDS_RING) {
        ringLeds[i] = CRGB::Black;
      }
      if (i < NUM_LEDS_BOARD) {
        boardLeds[i] = CRGB::Black;
      }
      i++;
      if (i >= NUM_LEDS_RING && i >= NUM_LEDS_BOARD) {
        isTurningOn = true;
        i = 0;
      }
    }
    FastLED.show();
  }
}

void twinkle(CRGB color) {
  static unsigned long previousMillis = 0;
  unsigned long currentMillis = millis();
  if (currentMillis - previousMillis >= effectSpeed) {
    previousMillis = currentMillis;
    fill_solid(ringLeds, NUM_LEDS_RING, CRGB::Black);
    fill_solid(boardLeds, NUM_LEDS_BOARD, CRGB::Black);
    for (int i = 0; i < 2; i++) {
      ringLeds[random(NUM_LEDS_RING)] =color;
      boardLeds[random(NUM_LEDS_BOARD)] = color;
    }
    FastLED.show();
  }
}

void breathing() {
  static uint8_t brightness = 0;
  static int8_t delta = 5;
  static unsigned long previousMillis = 0;
  unsigned long currentMillis = millis();

  if (currentMillis - lastColorChangeTime >= colorChangeInterval) {
    lastColorChangeTime = currentMillis;
    startColor = colors[currentColorIndex];
    currentColorIndex = (currentColorIndex + 1) % (sizeof(colors) / sizeof(colors[0]));
    endColor = colors[currentColorIndex];
    blendAmount = 0.0;
  }

  CRGB currentColor = blend(startColor, endColor, blendAmount * 255);

  if (currentMillis - previousMillis >= effectSpeed) {
    previousMillis = currentMillis;

    brightness += delta;
    if (brightness == 0 || brightness == 255) delta = -delta;

    for (int i = 0; i < NUM_LEDS_RING; i++) {
      ringLeds[i] = currentColor;
      ringLeds[i].fadeLightBy(255 - brightness);
    }
    for (int i = 0; i < NUM_LEDS_BOARD; i++) {
      boardLeds[i] = currentColor;
      boardLeds[i].fadeLightBy(255 - brightness);
    }
    FastLED.show();
  }

  if (blendAmount < 1.0) {
    blendAmount += blendStep;
  }
}

void celebrationEffect() {
  for (int i = 0; i < NUM_LEDS_RING; i++) {
    ringLeds[i] = CRGB::Red;
  }
  for (int i = 0; i < NUM_LEDS_BOARD; i++) {
    boardLeds[i] = CRGB::Red;
  }
  FastLED.show();
  delay(100);

  for (int i = 0; i < NUM_LEDS_RING; i++) {
    ringLeds[i] = CRGB::Green;
  }
  for (int i = 0; i < NUM_LEDS_BOARD; i++) {
    boardLeds[i] = CRGB::Green;
  }
  FastLED.show();
  delay(100);

  for (int i = 0; i < NUM_LEDS_RING; i++) {
    ringLeds[i] = CRGB::Blue;
  }
  for (int i = 0; i < NUM_LEDS_BOARD; i++) {
    boardLeds[i] = CRGB::Blue;
  }
  FastLED.show();
  delay(100);
}

float readBatteryVoltage() {
  int analogValue = analogRead(BATTERY_PIN);
  float voltage = analogValue * (V_REF / ADC_MAX);
  float batteryVoltage = voltage * (R1 + R2) / R2;
  return batteryVoltage;
}

int readBatteryLevel() {
  float batteryVoltage = readBatteryVoltage();
  int batteryLevel = map(batteryVoltage * 100, 0, 12 * 100, 0, 100);
  return constrain(batteryLevel, 0, 100);
}