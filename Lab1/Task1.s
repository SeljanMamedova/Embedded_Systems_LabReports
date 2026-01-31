const int LED1 = 8;   // LED1 is connected to digital pin 8
const int LED2 = 9;   // LED2 is connected to digital pin 9
const int LED3 = 10;  // LED3 is connected to digital pin 10

void setup() {
  // Set all LED pins as output pins
  pinMode(LED1, OUTPUT);
  pinMode(LED2, OUTPUT);
  pinMode(LED3, OUTPUT);
}

void loop() {
  // Turn ON LED1 and turn OFF LED2 and LED3
  digitalWrite(LED1, HIGH);
  digitalWrite(LED2, LOW);
  digitalWrite(LED3, LOW);
  delay(250); // Wait for 250 milliseconds

  // Turn ON LED2 and turn OFF LED1 and LED3
  digitalWrite(LED1, LOW);
  digitalWrite(LED2, HIGH);
  digitalWrite(LED3, LOW);
  delay(250); // Wait for 250 milliseconds

  // Turn ON LED3 and turn OFF LED1 and LED2
  digitalWrite(LED1, LOW);
  digitalWrite(LED2, LOW);
  digitalWrite(LED3, HIGH);
  delay(250); // Wait for 250 milliseconds
}
