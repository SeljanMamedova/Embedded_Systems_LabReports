#include <Wire.h>           // Enables I2C communication (used to talk to DS1307 RTC)
#include <uRTCLib.h>       // Library for RTC modules like DS1307 (works over I2C)

uRTCLib rtc(0x68);       // Create RTC object at I2C address 0x68 (fixed for DS1307)

// Digit control pins (D1 D2 D3 D4) -> which 7-seg digit is ON
int digitPins[4] = {5, 4, 3, 2};

// Segment pins: A B C D E F G DP(decimal point) -> which LED segment is ON
int segmentPins[8] = {8, 9, 10, 11, 12, 6, 7, 1};

// Segment patterns for numbers 0–9 (1=segment ON, 0=segment OFF)
byte numbers[10][8] = {
  {1,1,1,1,1,1,0,0}, // 0 -> A B C D E F ON, G OFF, DP OFF
  {0,1,1,0,0,0,0,0}, // 1
  {1,1,0,1,1,0,1,0}, // 2
  {1,1,1,1,0,0,1,0}, // 3
  {0,1,1,0,0,1,1,0}, // 4
  {1,0,1,1,0,1,1,0}, // 5
  {1,0,1,1,1,1,1,0}, // 6
  {1,1,1,0,0,0,0,0}, // 7
  {1,1,1,1,1,1,1,0}, // 8
  {1,1,1,1,0,1,1,0}  // 9
};

int counter = 0;          // Counter value that will be displayed (0..10)
byte lastSecond = 0;      // Stores last RTC "seconds" value to detect 1-second changes

const int buttonPin = A0; // Button connected to A0
bool paused = false;      // If true, counter stops increasing

const int greenLedPin = 13; // Green LED pin (success indicator)
const int redLed = 5;       // Red LED pin (fail indicator)

bool gameStarted = false; // Before first press, game is idle (no counting)

// Function returns true ONLY once per real button press (debounced + edge-detected)
bool buttonPressedEvent() {
  static bool last = HIGH;               // Previous stable button state (INPUT_PULLUP -> idle is HIGH)
  static unsigned long tLastChange = 0;  // Time when the signal last changed (for debouncing)
  static bool armed = true;              // Allows 1 event per press (prevents repeat while held)

  bool now = digitalRead(buttonPin);     // Read current raw button state

  // If signal changed, reset debounce timer and update last read state
  if (now != last) {
    tLastChange = millis();              // remember when change happened
    last = now;                          // update stored state
  }

  if ((millis() - tLastChange) > 30) {   // debounce
    
    // Detect the press event
  
    
    if (last == LOW && armed) {
      armed = false;                     // disarm so holding doesn't create multiple presses
      return true;                       // report a single "press" event
    }
    // When button is released (HIGH), re-arm for next press
    if (last == HIGH) armed = true;
  }
  return false;                          // no new press event
}

void setup() {
  Wire.begin();              // Start I2C bus (needed for DS1307 communication)
  Serial.begin(9600);        // Start serial monitor output

  pinMode(buttonPin, INPUT_PULLUP); // Use internal pull-up: not pressed=HIGH, pressed=LOW

  pinMode(greenLedPin, OUTPUT); // Green LED output
  pinMode(redLed, OUTPUT);      // Red LED output

  for (int i = 0; i < 8; i++)
    pinMode(segmentPins[i], OUTPUT);

  // Configure digit select pins as outputs and initially disable all digits
  for (int i = 0; i < 4; i++) {
    pinMode(digitPins[i], OUTPUT);       // digit control pin output
    digitalWrite(digitPins[i], LOW);     // LOW = digit OFF (depends on wiring, here LOW means disable)
  }

  counter = 0; // Start counter at 0
}

void loop() {

  bool pressed = buttonPressedEvent();   // detect press ONCE (debounced event)

  if (!gameStarted) {
    counter = 0;                         // keep display at 0
    digitalWrite(greenLedPin, LOW);      // LEDs off in idle
    digitalWrite(redLed, LOW);

    // First press starts the game and syncs RTC seconds
    if (pressed) {
      gameStarted = true;                // start the game
      rtc.refresh();                     // read latest time from RTC into library
      lastSecond = rtc.second();         // store current second to avoid instant increment
    }

    displayTwoDigits(counter);           // keep refreshing the 7-seg display (multiplexing)
    return;                              // exit loop early (do nothing else until started)
  }

  // Refresh RTC data each loop
  rtc.refresh();
  byte currentSecond = rtc.second();     // current RTC second (0..59)

  // If button pressed during game: toggle pause state
  if (pressed) {
    paused = !paused;                    // pause/unpause
    lastSecond = currentSecond;          // resync seconds so it doesn't immediately increment
  }

  // If not paused and second changed -> one second passed -> increment counter
  if (!paused && currentSecond != lastSecond) {
    lastSecond = currentSecond;          // update last second
    counter++;                           // increment counter each second
    if (counter > 10) counter = 0;       // wrap around after 10 back to 0
  }

  if (pressed) {

    Serial.print("Button pressed! Counter = "); // print message to Serial Monitor
    Serial.println(counter);                     // print current counter value

    // If counter is exactly 10 -> success (green ON), else fail (red ON)
    if (counter == 10) {
      digitalWrite(greenLedPin, HIGH); // success
      digitalWrite(redLed, LOW);
      delay(1000);                    // keep LED on for 1 second
    }
    else {
      digitalWrite(redLed, HIGH);     // fail
      digitalWrite(greenLedPin, LOW);
      delay(1000);                    // keep LED on for 1 second
    }

    // Turn both OFF after 1 second
    digitalWrite(greenLedPin, LOW);
    digitalWrite(redLed, LOW);
  }

  displayTwoDigits(counter);           // continuously refresh display
}

// Show one digit on selected 7-segment (multiplexing step)
void showDigit(int value, int digitIndex) {

  // Turn OFF all digits first so only one digit is active at a time
  for (int i = 0; i < 4; i++)
    digitalWrite(digitPins[i], LOW);

  // Output segment pattern for the requested number (0..9)
  for (int i = 0; i < 8; i++)
    digitalWrite(segmentPins[i], numbers[value][i]);

  // Enable the chosen digit (2 or 3 in your usage)
  digitalWrite(digitPins[digitIndex], HIGH);

  delay(5); // short delay so the digit stays visible before switching to next digit
}

// Display number only on 3rd & 4th digits (digitIndex 2 and 3)
void displayTwoDigits(int num) {
  int tens = num / 10; // tens digit
  int ones = num % 10; // ones digit

  // Only show tens if it's not zero (so "05" becomes "5")
  if (tens > 0) showDigit(tens, 2); // show tens on 3rd digit (index 2)

  showDigit(ones, 3);               // show ones on 4th digit (index 3)
}
