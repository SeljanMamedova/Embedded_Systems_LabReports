#include "Servo.h"                                            // Library for controlling servo motor
#include <Stepper.h>                                          // Library for controlling stepper motor

const int stepsPerRevolution = 2048;                        // Total steps for one full rotation of 28BYJ-48 stepper motor

Stepper myStepper(stepsPerRevolution, 11, 9, 10, 8);      // Stepper motor pins connection and object creation


Servo myservo;                                           // Servo motor object creation

int servoPin = 12;                                      // Servo motor connected to pin 12
int buzzer = 3;                                        // Buzzer connected to pin 3
int buttonPlayer1 = 6;                                // Player 1 button connected to pin 6
int buttonPlayer2 = 5;                               // Player 2 button connected to pin 5

int score1 = 0;                                     // Stores Player 1 score
int score2 = 0;                                    // Stores Player 2 score

unsigned long startTime;                         // Stores start time after buzzer
unsigned long reactionTime1;                     // Stores Player 1 reaction time
unsigned long reactionTime2;                     // Stores Player 2 reaction time

int stepperPosition = 0;                       // current stepper motor position

void setup() {

  Serial.begin(9600);   

  myStepper.setSpeed(10);                    // Sets stepper motor speed to 10 RPM

  myservo.attach(servoPin);                 // Attaches servo motor to defined pin

  pinMode(buttonPlayer1, INPUT_PULLUP);
  pinMode(buttonPlayer2, INPUT_PULLUP);

  pinMode(buzzer, OUTPUT); 

  randomSeed(analogRead(A0));                              // Generates random seed using analog pin noise

  myservo.write(90);                                      // Sets servo motor to neutral middle position

  Serial.println("GAME STARTS AUTOMATICALLY"); 
}

void loop() {

  resetGame();  

  playGame();   

  delay(5000);                                            // Waits 5 seconds before restarting game
}

void playGame() {
  
  myservo.write(90);  

  while (score1 < 3 && score2 < 3) {     // Continue game until one player reaches score 3

    Serial.println("NEW ROUND");   

    int delayTime = random(1000, 20001);      // Generate random waiting time between 1 and 20 seconds

    unsigned long waitStart = millis();              // Stores waiting start time

    while (millis() - waitStart < delayTime) {        // WAIT PHASE for false start detection

      if (digitalRead(buttonPlayer1) == LOW) {           // Check if Player 1 pressed button too early

        Serial.println("FALSE START P1"); 

        score2++;     // Player 2 gets point

        updateStepper(2);                              // Move stepper toward Player 2 side

        delay(1000);  

        return;                                        // End current round
      }

      if (digitalRead(buttonPlayer2) == LOW) {                           // Check if Player 2 pressed button too early

        Serial.println("FALSE START P2"); 

        score1++;                                                   // Player 1 gets point

        updateStepper(1);                                          // Move stepper toward Player 1 side

        delay(1000); 

        return;      
      }
    }

    
    tone(buzzer, 1000);            // Generate 1000 Hz sound on buzzer

    delay(200);                     // Keep buzzer active for 200 ms

    noTone(buzzer);                    // Stop buzzer sound

    startTime = millis();                   // Store reaction start time

    bool p1Pressed = false; 
    bool p2Pressed = false; 


    while (!p1Pressed || !p2Pressed) {

      // Detect Player 1 button press
      
      if (!p1Pressed && digitalRead(buttonPlayer1) == LOW) {

        reactionTime1 = millis() - startTime;                // Calculate Player 1 reaction time

        p1Pressed = true;                                   // Mark Player 1 as pressed
      }

      // Detect Player 2 button press
      
      if (!p2Pressed && digitalRead(buttonPlayer2) == LOW) {

        reactionTime2 = millis() - startTime;                    // Calculate Player 2 reaction time

        p2Pressed = true;                                      // Mark Player 2 as pressed
      }
    }

    
    if (reactionTime1 < reactionTime2) {

      score1++;                                // Increase Player 1 score

      Serial.print("P1 WIN: "); 

      Serial.println(reactionTime1); 

      moveServo(1);                     // Move servo toward Player 1 side

      updateStepper(1);               // Move stepper toward Player 1 side
    } 
    else {

      score2++; 

      Serial.print("P2 WIN: ");

      Serial.println(reactionTime2); 

      moveServo(2);                            // Move servo toward Player 2 side

      updateStepper(2);                      // Move stepper toward Player 2 side
    }

    delay(1500);                          // Delay before next round
  }

  
  if (score1 == 3) {

    Serial.println("GAME WINNER: P1");       // Print Player 1 as winner
  } 
  else {

    Serial.println("GAME WINNER: P2");       // Print Player 2 as winner
  }

  victorySpin();                          // Perform victory spin with stepper motor
}


void moveServo(int player) {

  if (player == 1) {

    myservo.write(0);                    // Rotate servo to Player 1 side
  } 
  else {

    myservo.write(180);                   // Rotate servo to Player 2 side
  }
}


void updateStepper(int player) {

  if (player == 1) {

    myStepper.step(50);                         // Rotate stepper forward 50 steps

    stepperPosition += 50;                    // Update current position
  } 
  else {

    myStepper.step(-50);                      // Rotate stepper backward 50 steps

    stepperPosition -= 50;                  // Update current position
  }
}

// Function for final victory rotation

void victorySpin() {

  myStepper.step(stepsPerRevolution);           // Rotate stepper one full revolution
}

// Function to reset game values

void resetGame() {

  score1 = 0;                          // Reset Player 1 score

  score2 = 0;                         // Reset Player 2 score

  myStepper.step(-stepperPosition);         // Return stepper to original position

  stepperPosition = 0;                    // Reset stepper position tracker

  myservo.write(90);                     // Return servo to center position
}
