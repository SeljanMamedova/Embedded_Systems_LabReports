// LED pin definitions
int yellow = 2;
int red = 11;
int blue = 6;
int green = 4;

// Joystick analog pins
int xPin = A0;
int yPin = A1;

// Joystick push button pin (not used in this task)
int sw = 8;

// Dead-zone threshold values around joystick center
int centerMax = 530;
int centerMin = 490;

void setup() {
  // Start serial communication for monitoring joystick values
  Serial.begin(9600);

  // Set joystick axes as input
  pinMode(xPin, INPUT);
  pinMode(yPin, INPUT);

  // Set LED pins as output
  pinMode(yellow, OUTPUT);
  pinMode(red, OUTPUT);
  pinMode(blue, OUTPUT);
  pinMode(green, OUTPUT);
}

void loop() {

  // Read analog values from joystick
  int xVal = analogRead(xPin);
  int yVal = analogRead(yPin);

  // Print X and Y values to Serial Monitor
  Serial.print(xVal);
  Serial.print(" | ");
  Serial.println(yVal);

  // Joystick moved LEFT (X below center, Y inside dead-zone)
  if ((xVal < centerMin) && (centerMin < yVal && yVal < centerMax)) {
    digitalWrite(green, HIGH);
    digitalWrite(red, LOW);
    digitalWrite(blue, LOW);
    digitalWrite(yellow, LOW);
  }

  // Joystick moved RIGHT (X above center, Y inside dead-zone)
  else if ((xVal > centerMax) && (centerMin < yVal && yVal < centerMax)) {
    digitalWrite(green, LOW);
    digitalWrite(red, LOW);
    digitalWrite(blue, HIGH);
    digitalWrite(yellow, LOW);
  }

  // Joystick moved DOWN (Y below center, X inside dead-zone)
  else if ((yVal < centerMin) && (centerMin < xVal && xVal < centerMax)) {
    digitalWrite(green, LOW);
    digitalWrite(red, LOW);
    digitalWrite(blue, LOW);
    digitalWrite(yellow, HIGH);
  }

  // Joystick moved UP (Y above center, X inside dead-zone)
  else if ((yVal > centerMax) && (centerMin < xVal && xVal < centerMax)) {
    digitalWrite(green, LOW);
    digitalWrite(red, HIGH);
    digitalWrite(blue, LOW);
    digitalWrite(yellow, LOW);
  }

  // Joystick in dead-zone → turn all LEDs off
  else {
    digitalWrite(green, LOW);
    digitalWrite(red, LOW);
    digitalWrite(blue, LOW);
    digitalWrite(yellow, LOW);
  }
}
