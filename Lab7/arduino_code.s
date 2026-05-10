#include <SPI.h>          // Library for SPI communication (used by RFID)
#include <MFRC522.h>      // Library for RFID module
#include <Keypad.h>       // Library for keypad
#include <IRremote.hpp>   // Library for IR remote receiver

#define RST_PIN         9    // RFID reset pin
#define SS_PIN          10   // RFID slave select pin
#define IR_RECEIVE_PIN  A1   // IR receiver pin
#define LED_RED         A2   // Red LED pin
#define LED_GREEN       A3   // Green LED pin


enum State {
  WAITING_FOR_PASSCODE,            // User enters password using keypad
  LOCKED,                                     // System locked, waiting for IR password
  UNLOCKED                     // System unlocked, RFID enabled
};

State currentState = WAITING_FOR_PASSCODE;              // Initial system state

String masterCode = "";                           // Stores final 4-digit password
String currentInput = "";                 // Temporary input storage

const byte ROWS = 4;  
const byte COLS = 4;  

// Keypad button layout

char keys[ROWS][COLS] = {
  {'1','2','3','A'},
  {'4','5','6','B'},
  {'7','8','9','C'},
  {'*','0','#','D'}
};

byte rowPins[ROWS] = {8, 7, 6, 5};      // Arduino pins connected to keypad rows

byte colPins[COLS] = {4, 3, 2, A0};     // Arduino pins connected to keypad columns

Keypad keypad = Keypad(makeKeymap(keys), rowPins, colPins, ROWS, COLS);    // Creates keypad object

MFRC522 mfrc522(SS_PIN, RST_PIN);  // Creates RFID object using SS and RST pins

const unsigned long IR_COOLDOWN_MS = 450;             // Delay to prevent double IR input
const unsigned long RFID_COOLDOWN_MS = 3000;        // Delay to prevent repeated RFID scans

void setup() {

  Serial.begin(9600); 

  SPI.begin();        // Starts SPI communication for RFID

  mfrc522.PCD_Init();                 // Initializes RFID reader

  // Starts IR receiver
  
  IrReceiver.begin(IR_RECEIVE_PIN, ENABLE_LED_FEEDBACK);

  pinMode(LED_RED, OUTPUT);   
  pinMode(LED_GREEN, OUTPUT); 

  Serial.println("--- SECURITY SYSTEM INITIALIZED ---");

  Serial.println("Step 1: Enter a 4-digit code on the KEYPAD to lock.");
}

void loop() {

  // Updates LEDs depending on current state
  
  updateLEDs(); 
  
  // Executes function depending on current system mode
  
  switch (currentState) {

    case WAITING_FOR_PASSCODE:

      handleKeypad();              // Wait for keypad password

      break;

    case LOCKED:

      handleIR();              // Wait for IR remote password

      break;

    case UNLOCKED:

      handleRFID();                // Enable RFID scanning

      break;
  }
}

void handleKeypad() {

  // Reads pressed keypad button
  
  char key = keypad.getKey();

  // If no key pressed, exit function
  
  if (!key) {
    return;
  }

  // Accepts only numeric digits
  
  if (key >= '0' && key <= '9') {

    currentInput += key;                     // Adds digit to password

    Serial.print("*");                       // Hides real password digit

    // When 4 digits entered
    
    if (currentInput.length() == 4) {

      masterCode = currentInput;                // Saves password

      currentInput = "";                         // Clears temporary input

      currentState = LOCKED;               // Changes state to LOCKED

      Serial.println();

      Serial.print("[CODE SAVED] Master code length: ");

      Serial.println(masterCode.length());

      Serial.println("[SYSTEM LOCKED] Use IR remote to unlock.");
    }
  }

  // Clears entered password if '*' pressed
  if (key == '*') {

    currentInput = "";

    Serial.println();

    Serial.println("[KEYPAD INPUT CLEARED]");
  }
}

void handleIR() {

  // Stores previous IR input time
  
  static unsigned long lastIRTime = 0;

  // Stores previous IR command
  
  static uint16_t lastCommand = 0;

  // If no IR signal received
  
  if (!IrReceiver.decode()) {
    return;
  }

  uint16_t command = IrReceiver.decodedIRData.command;

  // Stores current Arduino running time
  
  unsigned long now = millis();

  // Ignores repeated signals when button held down
  
  if (IrReceiver.decodedIRData.flags & IRDATA_FLAGS_IS_REPEAT) {

    IrReceiver.resume();

    return;
  }

  // Prevents duplicate commands too quickly
  
  if (command == lastCommand && now - lastIRTime < IR_COOLDOWN_MS) {

    IrReceiver.resume();

    return;
  }

  // Converts IR command into digit
  
  char digit = decodeIRDigit(command);

  // If valid digit received
  
  if (digit != 'X') {

    currentInput += digit;

    Serial.print("IR Digit Recorded: ");

    Serial.print(digit);

    Serial.print(" (");

    Serial.print(currentInput.length());

    Serial.println("/4)");

    // Saves current command and time
    
    lastCommand = command;

    lastIRTime = now;

    // When 4 digits entered
    
    if (currentInput.length() == 4) {

      // Checks entered code with stored password
      
      if (currentInput == masterCode) {

        currentState = UNLOCKED;

        Serial.println("[ACCESS GRANTED] RFID Reader Enabled.");
      }

      else {

        Serial.println("[DENIED] Incorrect Code. Try again.");
      }

      // Clears temporary IR input
      
      currentInput = "";
    }
  }

  // Prepares receiver for next IR signal
  
  IrReceiver.resume();
}

void handleRFID() {

  // Stores previously scanned RFID UID
  
  static String lastUid = "";

  // Stores previous scan time
  
  static unsigned long lastReadTime = 0;

  // Checks whether RFID card exists
  
  if (!mfrc522.PICC_IsNewCardPresent()) return;

  // Reads RFID card data
  
  if (!mfrc522.PICC_ReadCardSerial()) return;

  String uid = "";

  // Converts RFID UID bytes into HEX string
  
  for (byte i = 0; i < mfrc522.uid.size; i++) {

    // Adds leading zero for single digit HEX values
    
    if (mfrc522.uid.uidByte[i] < 0x10) {

      uid += "0";
    }

    uid += String(mfrc522.uid.uidByte[i], HEX);
  }

  // Converts UID letters to uppercase
  
  uid.toUpperCase();

  unsigned long now = millis();

  // Prevents duplicate scans within cooldown time
  
  if (uid == lastUid && now - lastReadTime < RFID_COOLDOWN_MS) {

    mfrc522.PICC_HaltA();

    mfrc522.PCD_StopCrypto1();

    return;
  }

  // Stores current scan information
  
  lastUid = uid;

  lastReadTime = now;

  
  flashSuccessLED();

  // Sends RFID UID to serial monitor
  
  Serial.print("DATA_PACKET:");

  Serial.println(uid);

  // Stops RFID communication
  
  mfrc522.PICC_HaltA();

  mfrc522.PCD_StopCrypto1();
}

void updateLEDs() {

  // Stores previous LED update time
  
  static unsigned long lastMillis = 0;

  // Stores blinking state
  
  static bool blinkState = false;

  if (currentState == WAITING_FOR_PASSCODE) {

    // Toggle LEDs every 500 ms
    
    if (millis() - lastMillis > 500) {

      lastMillis = millis();

      blinkState = !blinkState;

      digitalWrite(LED_RED, blinkState);

      digitalWrite(LED_GREEN, blinkState);
    }
  }


  else if (currentState == LOCKED) {

    digitalWrite(LED_RED, HIGH);

    digitalWrite(LED_GREEN, LOW);
  }

 
  else if (currentState == UNLOCKED) {

    digitalWrite(LED_RED, LOW);

    digitalWrite(LED_GREEN, HIGH);
  }
}

void flashSuccessLED() {

  // Turns both LEDs ON briefly
  digitalWrite(LED_RED, HIGH);

  digitalWrite(LED_GREEN, HIGH);

  delay(150);

  // Leaves only green LED ON
  
  digitalWrite(LED_RED, LOW);

  digitalWrite(LED_GREEN, HIGH);
}

char decodeIRDigit(uint16_t cmd) {

  // Converts IR remote HEX commands into digits
  
  switch (cmd) {

    case 0x16: return '0';

    case 0x0C: return '1';

    case 0x18: return '2';

    case 0x5E: return '3';

    case 0x08: return '4';

    case 0x1C: return '5';

    case 0x5A: return '6';

    case 0x42: return '7';

    case 0x52: return '8';

    case 0x4A: return '9';

    default:

      // Returns X for invalid IR commands
      
      return 'X';
  }
}
