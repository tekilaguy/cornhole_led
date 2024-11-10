//conrnhole_slave.ino
#include <WiFi.h>
#include <FastLED.h>

#include <OneButton.h>
#include <esp_now.h>
#include <esp_wifi.h>
#include <Preferences.h>

// LED Setup
#define NUM_LEDS_RING   60
#define NUM_LEDS_BOARD  216
#define RING_LED_PIN    32
#define BOARD_LED_PIN   33
#define LED_TYPE        WS2812B
#define COLOR_ORDER     GRB
#define VOLTS           5
#define MAX_AMPS        2500

//  Configurable Varibales
Preferences preferences;

// WiFi Credentials for AP mode
String ssid = "CornholeAP";
String password = "Funforall";

// LED Setup
String board2Name = "Board 2";
int brightness = 25;
int blockSize = 15;
unsigned long effectSpeed = 25; // Replace effectSpeed
int inactivityTimeout = 30;    // Variable for inactivity timeout
unsigned long irTriggerDuration = 4000;
CRGB initialColor = CRGB::Blue;
CRGB sportsEffectColor1 = CRGB(12,35,64);
CRGB sportsEffectColor2 = CRGB(241,90,34);

// Button and Sensor Pins
#define BUTTON_PIN 14
#define SENSOR_PIN 12
#define BATTERY_PIN 35

// MAC Addresses for ESP-NOW
uint8_t masterMAC[] = {0x24, 0x6F, 0x28, 0x88, 0xB4, 0xC8}; // MAC address of the master board
uint8_t slaveMAC[] = {0x24, 0x6F, 0x28, 0x88, 0xB4, 0xC9};  // MAC address of the slave board

#define ADC_MAX 4095
#define V_REF 3.3
#define R1 10000.0
#define R2 3900.0

CRGB ringLeds[NUM_LEDS_RING];
CRGB boardLeds[NUM_LEDS_BOARD];

// Color Definitions
#define BURNT_ORANGE    CRGB(191, 87, 0)
unsigned long colorChangeInterval = 5000; 
unsigned long lastColorChangeTime = 0;
int currentColorIndex = 0;
CRGB colors[] = {CRGB::Blue, CRGB::Green, CRGB::Red, CRGB::White, BURNT_ORANGE, CRGB::Aqua, CRGB::Purple, CRGB::Pink}; 
int colorIndex = 0;
CRGB startColor;
CRGB endColor;
float blendAmount = 0.0;
float blendStep = 0.01; 
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

// Structure to send data
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

// Function declarations
void setupWiFi();
void setupEspNow();
void onDataRecv(const esp_now_recv_info *info, const uint8_t *incomingData, int len);
void onDataSent(const uint8_t *mac_addr, esp_now_send_status_t status);
String macToString(const uint8_t *mac);
void sendSettings();
void sendBoard1Info();
void sendBoard2Info(struct_message board2);
void singleClick();
void doubleClick();
void longPressStart();
void longPressStop();
void toggleLights(bool status);
void toggleWiFi(bool status);
void toggleEspNow(bool status);
void handleIRSensor();
void setColor(CRGB color);
void applyEffect(String effect);
void powerOnEffect();
void solidChase(CRGB color);
void bounceEffect(CRGB color);
void gradientChaseEffect(CRGB color);
void rainbowChase();
void redWhiteBlueChase();
void sportsChase();
void colorWipe(CRGB color);
void twinkle(CRGB color);
void breathing();
void celebrationEffect();
float readBatteryVoltage();
int readBatteryLevel();
void sendData(const String& device, const String& type, const String& data);
void sendEffectToPeer(const String& effect);
void sendColorToPeer(int r, int g, int b);
void sendbrightnessToPeer(int brightness);

void setup() {
  Serial.begin(115200);
  Serial.println("Starting setup...");

preferences.begin("cornhole", false);
bool tpInit = preferences.isKey("nvsInit");   

if (tpInit == false) {
      preferences.end();           
      preferences.begin("cornhole", false);
        preferences.putString("ssid", "CornholeAP");
        preferences.putString("password", "Funforall");
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
  esp_wifi_set_mac(WIFI_IF_STA, slaveMAC);
  setupEspNow();
  
  strcpy(board2.device, "Board 2");
  strcpy(board2.name, board2Name.c_str());
  memcpy(board2.macAddr, slaveMAC, sizeof(slaveMAC));
  strcpy(board2.ipAddr, WiFi.localIP().toString().c_str());

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
  updateconnectioninfo();
  powerOnEffect();
  Serial.println("Setup completed.");
}

 void loop() {
  button.tick();
  handleIRSensor();
  if (lightsOn) {
    applyEffect(effects[effectIndex]);
  }

}void setupWiFi() {
    Serial.println("Connecting to WiFi...");
    WiFi.mode(WIFI_STA);
    WiFi.begin(ssid,password);
    while (WiFi.status() != WL_CONNECTED) {
        delay(1000);
        Serial.print(".");
    }

    Serial.println();
    Serial.println("Connected to WiFi");
    Serial.println("IP Address: ");
    Serial.println(WiFi.localIP());
      Serial.print("Soft SSID: ");
      Serial.println(ssid);
}

void setupEspNow() {
  if (esp_now_init() != ESP_OK) {
    Serial.println("Error initializing ESP-NOW");
    return;
  }
  esp_now_register_recv_cb(onDataRecv);
  esp_now_register_send_cb(onDataSent);

  esp_now_peer_info_t peerInfo;
  memset(&peerInfo, 0, sizeof(peerInfo));
  memcpy(peerInfo.peer_addr, masterMAC, 6);
  peerInfo.channel = 0;
  peerInfo.encrypt = false;
  peerInfo.ifidx = WIFI_IF_STA;

    if (esp_now_is_peer_exist(masterMAC)) {
    esp_now_del_peer(masterMAC);
  }

if (esp_now_add_peer(&peerInfo) != ESP_OK) {
    Serial.println("Failed to add peer");
  } else {
    Serial.println("Peer added successfully");
  }
}

void onDataRecv(const esp_now_recv_info *info, const uint8_t *incomingData, int len) {
  char msg[50];
  snprintf(msg, sizeof(msg), "Data received from: %02x:%02x:%02x:%02x:%02x:%02x", info->src_addr[0], info->src_addr[1], info->src_addr[2], info->src_addr[3], info->src_addr[4], info->src_addr[5]);
  Serial.println(msg);
  
  String receivedData = String((char*)incomingData).substring(0, len);
  Serial.println("Received data: " + receivedData);

  int r, g, b, brightness;

   if (receivedData.startsWith("Color:")) {
        String colorData = receivedData.substring(6); 
        
        if (sscanf(colorData.c_str(), "%d,%d,%d", &r, &g, &b) == 3) {
            currentColor = CRGB(r, g, b);
            setColor(currentColor);
            Serial.printf("Received color: R=%d, G=%d, B=%d\n", r, g, b);
        } else {
            Serial.println("Failed to parse color data.");
        }
    } else if (receivedData.startsWith("Effect:")) {
        // Handle effect data similarly
        String effect = receivedData.substring(7); // Start after "Effect:"
        effects[effectIndex] = effect;
        applyEffect(effects[effectIndex]);

  } else if (receivedData.startsWith("brightness:") && sscanf(receivedData.c_str(), "brightness:%d", &brightness) == 1) {
    FastLED.setBrightness(brightness);
    FastLED.show();
    Serial.printf("Received brightness: %d\n", brightness);

  } else if (receivedData.startsWith("toggleLights:")) {
    String status = receivedData.substring(13);
    bool lightsStatus = (status == "on");
    toggleLights(lightsStatus);

  } else if (receivedData == "Restart") {
    restartCommand();

  } else if (receivedData == "OTAStart") {
    otaStart();

  } else if (receivedData.startsWith("S:")) {
    String data = receivedData.substring(2);
    setDefaults(data);

  } else if (receivedData == "GET_INFO") {
    updateconnectioninfo();

  } else {
    processCommand(receivedData);
    Serial.println("Unknown data received");
  }
}

void onDataSent(const uint8_t *mac_addr, esp_now_send_status_t status) {
  Serial.print("Last Packet Sent to: "); 
  Serial.print(macToString(mac_addr));
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

void updateconnectioninfo(){
    board2.batteryLevel = readBatteryLevel();
    board2.batteryVoltage = readBatteryVoltage();

    esp_err_t result = esp_now_send(masterMAC, (uint8_t *) &board2, sizeof(board2));
    if (result == ESP_OK) {
        Serial.println("Sent with success");
      Serial.printf("Sending - Device: %s, Name: %s, MAC: %02x:%02x:%02x:%02x:%02x:%02x, IP: %s, Battery Level: %d, Voltage: %d\n",
      board2.device, board2.name, board2.macAddr[0], board2.macAddr[1], board2.macAddr[2], 
      board2.macAddr[3], board2.macAddr[4], board2.macAddr[5], 
      board2.ipAddr, board2.batteryLevel, board2.batteryVoltage);
    } else {
        Serial.println("Error sending the data");
    }
 }
 

void sendData(const String& device, const String& type, const String& data) {
  char message[512];

  if (device == "espNow" || device == "both") {
    snprintf(message, sizeof(message), "%s:%s", type.c_str(), data.c_str());
    esp_now_send(masterMAC, (uint8_t *)message, strlen(message));
    Serial.println("Sending to peer: " + String(message));
  }
  
  // if (device == "app" || device == "both") {
  //   String message = type + ":" + data + "#";
  //   updateBluetoothData(message);
  //   Serial.println("Sending to app: " + message);
  // }
}

void sendEffectToPeer(const String& effect) {
  char message[32];
  snprintf(message, sizeof(message), "Effect:%s", effect.c_str());
  esp_now_send(masterMAC, (uint8_t *)message, strlen(message));
  //updateconnectioninfo();
}

void sendColorToPeer(int r, int g, int b) {
  char message[16];
  snprintf(message, sizeof(message), "%d,%d,%d", r, g, b);
  esp_now_send(masterMAC, (uint8_t *)message, strlen(message));
  //updateconnectioninfo();
}

void sendBrightnessToPeer(int brightness) {
  if (!lightsOn) {
    Serial.println("Lights are off, skipping color application.");
    return;
  }
  char message[16];
  snprintf(message, sizeof(message), "brightness:%d", brightness);
  esp_now_send(masterMAC, (uint8_t *)message, strlen(message));
  //updateconnectioninfo();
}

void restartCommand() {
   delay(100);

   ESP.restart();
}

void singleClick() {
  if (!lightsOn) {
    Serial.println("Lights are off, skipping color change.");
    return;
  }
  colorIndex = (colorIndex + 1) % (sizeof(colors) / sizeof(colors[0]));
  currentColor = colors[colorIndex];
  setColor(currentColor);
  //sendColorToPeer(currentColor.r, currentColor.g, currentColor.b);
  sendData("espNow","Color", String(currentColor.r) + "," + String(currentColor.g) + "," + String(currentColor.b));
}

void doubleClick() {
  if (!lightsOn) {
    Serial.println("Lights are off, skipping effect application.");
    return;
  }
  effectIndex = (effectIndex + 1) % (sizeof(effects) / sizeof(effects[0]));
  applyEffect(effects[effectIndex]);
  //sendEffectToPeer(effects[effectIndex]);
  sendData("espNow","Effect",effects[effectIndex]);
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
  
  sendData("espNow","toggleLights",message);
}

void otaStart() {
  
}

void setDefaults(String data) {
  int start = 0;
  int end = data.indexOf(';');
  
  while (end != -1) {
    String subCommand = data.substring(start, end);
    processCommand(subCommand);  // Process each individual command
    start = end + 1;
    end = data.indexOf(';', start);
  }

  // Process the last command if there is no trailing ';'
  String lastCommand = data.substring(start);
  processCommand(lastCommand);
}

void processCommand(String command) {
  preferences.begin("cornhole",false);
  if (command == "CLEAR_ALL") {
    preferences.clear(); // Clear all preferences
    Serial.println("All saved variables cleared.");
  } else if  (command.startsWith("SSID:")) {
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

    } else if  (command.startsWith("B2:")) {
        String board2Name = command.substring(3);
        strncpy(board2.name, board2Name.c_str(), sizeof(board2.name) - 1);
        board2.name[sizeof(board2.name) - 1] = '\0'; // Ensure null-termination
        preferences.putString("board2Name", board2Name); 
        Serial.print("Board 2 Name set to: ");
        Serial.println(board2Name);

    } else if  (command.startsWith("BRIGHT:")) {
        sscanf(command.c_str(), "BRIGHT:%d", &brightness);
        preferences.putInt("brightness", brightness);
        FastLED.setBrightness(brightness);
        FastLED.show();
        Serial.print("Brightness set to: ");
        Serial.println(brightness);

    } else if (command.startsWith("SIZE:")) {
        sscanf(command.c_str(), "SIZE:%lu", &blockSize);
        preferences.putULong("blockSize", blockSize);
        Serial.print("Effect speed set to: ");
        Serial.println(blockSize);

    } else if (command.startsWith("SPEED:")) {
        int speed;
        sscanf(command.c_str(), "SPEED:%lu", &speed);
        preferences.putULong("effectSpeed", speed);
        Serial.print("Effect speed set to: ");
        Serial.println(speed);
        effectSpeed = speed;

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


    } else {
        Serial.print("Unknown command: ");
        Serial.println(command);
    }
  preferences.end();
}
  
void handleIRSensor() {
  int reading = digitalRead(SENSOR_PIN);
  static bool effectRunning = false;
  static unsigned long effectStartTime = 0;
  const unsigned long effectDuration = 4000;

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

void setColor(CRGB color) {
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
  setColor(currentColor);
}

void solidChase(CRGB color) {
  unsigned long currentMillis = millis();
  if (currentMillis - previousMillis >= brightness) {
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

  if (currentMillis - previousMillis >= brightness) {
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
  if (currentMillis - previousMillis >= brightness) {
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
  if (currentMillis - previousMillis >= brightness) {
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
  if (currentMillis - previousMillis >= brightness) {
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

  if (currentMillis - previousMillis >= brightness) {
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
  if (currentMillis - previousMillis >= brightness) {
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

  // Check if it's time to change the color
  if (currentMillis - lastColorChangeTime >= colorChangeInterval) {
    lastColorChangeTime = currentMillis;
    startColor = colors[currentColorIndex];
    currentColorIndex = (currentColorIndex + 1) % (sizeof(colors) / sizeof(colors[0])); // Cycle through the colors
    endColor = colors[currentColorIndex];
    blendAmount = 0.0; // Reset blend amount for the new color transition
  }

  CRGB currentColor = blend(startColor, endColor, blendAmount * 255);

  if (currentMillis - previousMillis >= brightness) {
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
