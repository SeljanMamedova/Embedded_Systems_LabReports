
import sys                                             # Gives access to system-specific parameters (sys.argv, sys.exit)
import time                                            # Used for time measurement and delays
import serial                                          # pyserial library for serial communication with Arduino
import serial.tools.list_ports                         # Used to automatically detect available COM ports

                                                       # PyQt6 modules for GUI
from PyQt6.QtCore import QTimer                        # Timer used to repeatedly call a function
from PyQt6.QtWidgets import (
    QApplication, QWidget, QVBoxLayout, QHBoxLayout,
    QPushButton, QLabel, QFrame, QProgressBar
)


BAUD = 9600                                             # Serial communication speed (must match Arduino Serial.begin)

def auto_detect_port():
    ports = list(serial.tools.list_ports.comports())                    # Get list of all COM ports

    for p in ports:                                                     # Loop through each detected port
                                                                        # Check if the port description contains Arduino or CH340 (Arduino clone chip)
        if "Arduino" in p.description or "CH340" in p.description:
            print(f"Auto-detected Arduino on {p.device}")               # Print detected port
            return p.device  # Return port name (example: COM7)

    print("No Arduino found!")                                         # If nothing found
    return None                                                        # Return None if no Arduino detected


def parse_arduino_line(line: str):
    """
    Expected Arduino format:
    X=2.53,Y=2.49,DIR=UP
    """

    line = line.strip()                                                   # Remove spaces and newline characters

                                                                          # Ignore empty lines or system/debug messages
    if not line or line.startswith("SYSTEM") or line.startswith("STATE"):
        return None

    try:
        parts = line.split(",")               # Split by comma

                                              # Ensure correct format (must have exactly 3 parts)
        if len(parts) != 3:
            return None

                                              # Extract numeric X value
        x_v = float(parts[0].split("=", 1)[1])

                                              # Extract numeric Y value
        y_v = float(parts[1].split("=", 1)[1])

                                              # Extract direction string and convert to uppercase
        direction = parts[2].split("=", 1)[1].strip().upper()

        return x_v, y_v, direction            # Return tuple

    except Exception:
        return None                           # If parsing fails, ignore line


class Lab4JoystickGUI(QWidget):

    def __init__(self):
        super().__init__()                    # Initialize parent QWidget

        self.setWindowTitle("Lab 4 — Joystick Monitor")  # Window title

                                               # Serial and state variables
        self.ser = None
        self.port = None
        self.is_running = False
        self.last_time = None                  # Used to calculate Hz

        main = QVBoxLayout()                   # Main vertical layout

        row1 = QHBoxLayout()                   # Horizontal layout for buttons

        self.start_btn = QPushButton("Start")
        self.stop_btn = QPushButton("Stop")

        self.stop_btn.setEnabled(False)         # Stop disabled initially

        row1.addWidget(self.start_btn)
        row1.addWidget(self.stop_btn)
        row1.addStretch(1)                     # Push buttons to left

        main.addLayout(row1)

        center = QHBoxLayout()                   # Main center area

        data_frame = QFrame()
        data_frame.setFrameShape(QFrame.Shape.Box)     # Add border box

        data_layout = QVBoxLayout()

        title = QLabel("Joystick Position")
        title.setStyleSheet("font-weight: bold;")
        data_layout.addWidget(title)

        # X progress bar
        self.bar_x = QProgressBar()
        self.bar_x.setRange(0, 500)  # Range 0–500
        self.bar_x.setFormat("X: %v / 500")  # Display format
        data_layout.addWidget(self.bar_x)

        # Y progress bar
        self.bar_y = QProgressBar()
        self.bar_y.setRange(0, 500)
        self.bar_y.setFormat("Y: %v / 500")
        data_layout.addWidget(self.bar_y)

        data_frame.setLayout(data_layout)
        center.addWidget(data_frame)
 
        cross = QVBoxLayout()

        self.up = self.block()  # Create square block
        cross.addWidget(self.up)

        mid = QHBoxLayout()

        self.left = self.block()
        self.center_block = self.block()
        self.right = self.block()

        mid.addWidget(self.left)
        mid.addWidget(self.center_block)
        mid.addWidget(self.right)

        cross.addLayout(mid)

        self.down = self.block()
        cross.addWidget(self.down)

        center.addLayout(cross)
        main.addLayout(center)

        bottom = QHBoxLayout()

        self.x_label = QLabel("X: -")
        self.y_label = QLabel("Y: -")
        self.rate_label = QLabel("Hz: -")  # Update frequency
        self.dir_label = QLabel("Dir: -")

        bottom.addWidget(self.x_label)
        bottom.addWidget(self.y_label)
        bottom.addWidget(self.rate_label)
        bottom.addWidget(self.dir_label)

        main.addLayout(bottom)

        self.setLayout(main)  # Apply layout to window

        self.start_btn.clicked.connect(self.start_test)
        self.stop_btn.clicked.connect(self.stop_test)

        self.timer = QTimer()
        self.timer.timeout.connect(self.tick)  # Call tick() every interval
        self.timer.start(20)  # 20 ms (~50 Hz)

    def block(self):
        f = QFrame()
        f.setFrameShape(QFrame.Shape.Box)
        f.setMinimumSize(40, 40)  # Square size
        return f
        
    def highlight(self, direction):

        off = ""  # Default style
        on = "background-color: lightgreen;"  # Highlight style

        # Reset all blocks
        self.up.setStyleSheet(off)
        self.down.setStyleSheet(off)
        self.left.setStyleSheet(off)
        self.right.setStyleSheet(off)
        self.center_block.setStyleSheet(off)

        # Highlight correct direction
        if direction == "UP":
            self.up.setStyleSheet(on)
        elif direction == "DOWN":
            self.down.setStyleSheet(on)
        elif direction == "LEFT":
            self.left.setStyleSheet(on)
        elif direction == "RIGHT":
            self.right.setStyleSheet(on)
        else:
            self.center_block.setStyleSheet(on)

        self.dir_label.setText(f"Dir: {direction}")

    def open_serial_and_start(self):

        self.port = auto_detect_port()  # Detect Arduino port

        if not self.port:
            print("Cannot start: Arduino port not found.")
            return False

        try:
            # Open serial connection
            self.ser = serial.Serial(self.port, BAUD, timeout=0.2)
            print(f"Connected to {self.port}")
        except Exception as e:
            print("Serial error:", e)
            return False

        time.sleep(2.0)  # Wait for Arduino reset
        self.ser.reset_input_buffer()  # Clear old data

        try:
            self.ser.write(b"START\n")  # Send START command
            self.ser.flush()
            print("START sent")
            return True
        except Exception as e:
            print("Failed to send START:", e)
            return False

    def close_serial(self):

        if self.ser and self.ser.is_open:
            try:
                self.ser.write(b"STOP\n")  # Tell Arduino to stop
                self.ser.close()           # Close port
            except Exception:
                pass

        self.ser = None

    def start_test(self):

        if not (self.ser and self.ser.is_open):
            if not self.open_serial_and_start():
                return

        self.is_running = True
        self.start_btn.setEnabled(False)
        self.stop_btn.setEnabled(True)
        self.last_time = None

    def stop_test(self):

        self.is_running = False
        self.close_serial()
        self.start_btn.setEnabled(True)
        self.stop_btn.setEnabled(False)

    def tick(self):

        if not self.is_running or not self.ser:
            return  # Do nothing if not running

        updated = False

        try:
            while self.ser.in_waiting:  # While data exists in buffer

                line = self.ser.readline().decode(errors="ignore")
                print("RAW:", repr(line))  # Debug print

                parsed = parse_arduino_line(line)

                if parsed:
                    x_v, y_v, direction = parsed
                    self.update_ui(x_v, y_v, direction)
                    updated = True

        except Exception:
            self.stop_test()
            return

        # Calculate frequency (Hz)
        if updated:
            now = time.time()
            if self.last_time:
                hz = 1.0 / (now - self.last_time)
                self.rate_label.setText(f"Hz: {hz:.1f}")
            self.last_time = now

    def update_ui(self, x_v, y_v, direction):

        self.x_label.setText(f"X: {x_v:.2f} V")
        self.y_label.setText(f"Y: {y_v:.2f} V")

        # Convert voltage to 0–500 scale
        self.bar_x.setValue(int(max(0, min(500, x_v * 100))))
        self.bar_y.setValue(int(max(0, min(500, y_v * 100))))

        self.highlight(direction)

    def closeEvent(self, e):
        self.stop_test()
        super().closeEvent(e)


if __name__ == "__main__":

    app = QApplication(sys.argv)  # Create Qt application
    w = Lab4JoystickGUI()         # Create main window
    w.resize(1000, 800)           # Set window size
    w.show()                      # Show window
    sys.exit(app.exec())          # Start event loop
