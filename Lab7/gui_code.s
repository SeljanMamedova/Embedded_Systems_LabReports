import sys
import sqlite3
from datetime import datetime

import serial
import serial.tools.list_ports

from PyQt6.QtCore import QThread, pyqtSignal, Qt
from PyQt6.QtWidgets import (
    QApplication,
    QComboBox,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMainWindow,
    QMessageBox,
    QPushButton,
    QTableWidget,
    QTableWidgetItem,
    QTextEdit,
    QVBoxLayout,
    QWidget,
    QHeaderView,
    QGroupBox,
)

DATABASE_FILE = "rfid_database.db"
BAUD_RATE = 9600
DATA_PREFIX = "DATA_PACKET:"

class DatabaseManager:

    def __init__(self, db_file=DATABASE_FILE):

        self.db_file = db_file

        # Creates database and table if they do not exist
        
        self.initialize_database()

    def connect(self):

        # Opens SQLite database connection
        
        return sqlite3.connect(self.db_file)

    def initialize_database(self):

        conn = self.connect()
        cursor = conn.cursor()

        # Creates RFID tags table
        
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS tags (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                tag_id TEXT UNIQUE,
                rfid_uid TEXT UNIQUE NOT NULL,
                scan_count INTEGER NOT NULL DEFAULT 1,
                first_seen TEXT NOT NULL,
                last_seen TEXT NOT NULL
            )
        """)

        conn.commit()
        conn.close()

    def add_or_update_tag(self, rfid_uid):

        # Stores current date and time
        
        now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

        conn = self.connect()
        cursor = conn.cursor()

        # Checks whether RFID already exists
        
        cursor.execute(
            "SELECT id, tag_id, scan_count FROM tags WHERE rfid_uid = ?",
            (rfid_uid,)
        )

        existing_tag = cursor.fetchone()

        # If RFID already exists in database
        
        if existing_tag:

            db_id, tag_id, scan_count = existing_tag

            new_count = scan_count + 1

            # Updates scan count and last scan time
            
            cursor.execute("""
                UPDATE tags
                SET scan_count = ?, last_seen = ?
                WHERE rfid_uid = ?
            """, (new_count, now, rfid_uid))

            conn.commit()
            conn.close()

            return {
                "status": "existing",
                "tag_id": tag_id,
                "rfid_uid": rfid_uid,
                "scan_count": new_count
            }

        else:
            # Inserts new RFID tag into database
            
            cursor.execute("""
                INSERT INTO tags (tag_id, rfid_uid, scan_count, first_seen, last_seen)
                VALUES (?, ?, ?, ?, ?)
            """, ("TEMP", rfid_uid, 1, now, now))

            # Gets automatically generated database ID
            
            new_db_id = cursor.lastrowid

            # Creates formatted tag ID
            
            tag_id = f"TAG-{new_db_id:03d}"

            # Updates temporary ID with real tag ID
            
            cursor.execute("""
                UPDATE tags
                SET tag_id = ?
                WHERE id = ?
            """, (tag_id, new_db_id))

            conn.commit()
            conn.close()

            return {
                "status": "new",
                "tag_id": tag_id,
                "rfid_uid": rfid_uid,
                "scan_count": 1
            }

    def get_all_tags(self, search_text=""):

        conn = self.connect()
        cursor = conn.cursor()

        # Searches database if search text entered
        
        if search_text:

            search_pattern = f"%{search_text}%"

            cursor.execute("""
                SELECT tag_id, rfid_uid, scan_count, first_seen, last_seen
                FROM tags
                WHERE tag_id LIKE ? OR rfid_uid LIKE ?
                ORDER BY id ASC
            """, (search_pattern, search_pattern))

        else:
            # Loads all RFID records
            
            cursor.execute("""
                SELECT tag_id, rfid_uid, scan_count, first_seen, last_seen
                FROM tags
                ORDER BY id ASC
            """)

        rows = cursor.fetchall()

        conn.close()

        return rows

    def clear_database(self):

        conn = self.connect()
        cursor = conn.cursor()

        # Deletes all RFID records
        
        cursor.execute("DELETE FROM tags")

        # Resets auto increment counter
        
        cursor.execute("DELETE FROM sqlite_sequence WHERE name='tags'")

        conn.commit()
        conn.close()

class SerialReaderThread(QThread):

    # Signals used for communication with GUI
    
    tag_scanned = pyqtSignal(str)
    serial_message = pyqtSignal(str)
    connection_error = pyqtSignal(str)

    def __init__(self, port_name, baud_rate=BAUD_RATE):

        super().__init__()

        self.port_name = port_name
        self.baud_rate = baud_rate

        self.running = False

        self.serial_connection = None

    def run(self):

        try:
            # Opens serial connection with Arduino
            
            self.serial_connection = serial.Serial(
                self.port_name,
                self.baud_rate,
                timeout=1
            )

            self.running = True

            self.serial_message.emit(
                f"Connected to {self.port_name} at {self.baud_rate} baud."
            )

            # Continuously reads serial data
            
            while self.running:

                try:
                
                    # Reads serial line from Arduino
                    
                    line = self.serial_connection.readline().decode(errors="ignore").strip()

                    if not line:
                        continue

                    self.serial_message.emit(f"Arduino: {line}")

                    # Detects RFID data packet
                    
                    if line.startswith(DATA_PREFIX):

                        uid = line.replace(DATA_PREFIX, "").strip().upper()

                        # Sends scanned UID to GUI
                        
                        if uid:
                            self.tag_scanned.emit(uid)

                except Exception as e:

                    self.connection_error.emit(f"Serial read error: {e}")

                    break

        except Exception as e:

            self.connection_error.emit(f"Could not open serial port: {e}")

        finally:
            # Closes serial connection safely
            
            if self.serial_connection and self.serial_connection.is_open:

                self.serial_connection.close()

            self.serial_message.emit("Serial connection closed.")

    def stop(self):

        # Stops serial reading thread
        
        self.running = False

        self.wait()

class RFIDDatabaseGUI(QMainWindow):

    def __init__(self):

        super().__init__()

        self.db = DatabaseManager()

        self.serial_thread = None

        self.setWindowTitle("RFID Tag Database Viewer")

        self.setMinimumSize(950, 650)
        
        self.setup_ui()

        # Loads available COM ports
        
        self.load_ports()

        # Loads RFID records into table
        
        self.refresh_table()

    def setup_ui(self):

        main_widget = QWidget()

        main_layout = QVBoxLayout()

        serial_group = QGroupBox("Serial Connection")

        serial_layout = QHBoxLayout()

        self.port_combo = QComboBox()

        self.refresh_ports_button = QPushButton("Refresh Ports")

        self.refresh_ports_button.clicked.connect(self.load_ports)

        self.connect_button = QPushButton("Connect")

        # Connect button starts serial communication
        
        self.connect_button.clicked.connect(self.connect_serial)

        self.disconnect_button = QPushButton("Disconnect")

        # Disconnect button stops serial communication
        
        self.disconnect_button.clicked.connect(self.disconnect_serial)

        self.disconnect_button.setEnabled(False)

        self.status_label = QLabel("Status: Disconnected")

        serial_layout.addWidget(QLabel("Port:"))
        serial_layout.addWidget(self.port_combo)
        serial_layout.addWidget(self.refresh_ports_button)
        serial_layout.addWidget(self.connect_button)
        serial_layout.addWidget(self.disconnect_button)
        serial_layout.addWidget(self.status_label)

        serial_group.setLayout(serial_layout)
        search_group = QGroupBox("Database Navigation")

        search_layout = QHBoxLayout()

        self.search_input = QLineEdit()

        self.search_input.setPlaceholderText("Search by Tag ID or RFID UID...")
        self.search_input.textChanged.connect(self.refresh_table)

        self.refresh_table_button = QPushButton("Refresh Table")

        self.refresh_table_button.clicked.connect(self.refresh_table)

        self.clear_button = QPushButton("Clear Database")

        # Clears all database records
        
        self.clear_button.clicked.connect(self.clear_database)

        search_layout.addWidget(QLabel("Search:"))
        search_layout.addWidget(self.search_input)
        search_layout.addWidget(self.refresh_table_button)
        search_layout.addWidget(self.clear_button)

        search_group.setLayout(search_layout)

        self.table = QTableWidget()

        self.table.setColumnCount(5)

        # Table column titles
        
        self.table.setHorizontalHeaderLabels([
            "Tag ID",
            "RFID UID",
            "Scan Count",
            "First Seen",
            "Last Seen"
        ])

        self.table.horizontalHeader().setSectionResizeMode(QHeaderView.ResizeMode.Stretch)

        # Prevents table editing
        
        self.table.setEditTriggers(QTableWidget.EditTrigger.NoEditTriggers)

        # Allows selecting entire rows
        
        self.table.setSelectionBehavior(QTableWidget.SelectionBehavior.SelectRows)

        self.table.setAlternatingRowColors(True)

        latest_group = QGroupBox("Latest Scan")

        latest_layout = QHBoxLayout()

        self.latest_scan_label = QLabel("No tag scanned yet.")

        latest_layout.addWidget(self.latest_scan_label)

        latest_group.setLayout(latest_layout)

        log_group = QGroupBox("Serial Log")

        log_layout = QVBoxLayout()

        self.log_output = QTextEdit()

        # Makes log output read-only
        
        self.log_output.setReadOnly(True)

        self.log_output.setMinimumHeight(140)

        log_layout.addWidget(self.log_output)

        log_group.setLayout(log_layout)

        main_layout.addWidget(serial_group)
        main_layout.addWidget(search_group)
        main_layout.addWidget(self.table)
        main_layout.addWidget(latest_group)
        main_layout.addWidget(log_group)

        main_widget.setLayout(main_layout)

        self.setCentralWidget(main_widget)

    def load_ports(self):

        # Clears old COM port list
        
        self.port_combo.clear()

        # Gets available serial ports
        
        ports = serial.tools.list_ports.comports()

        # If no ports found
        
        if not ports:

            self.port_combo.addItem("No ports found")

            self.connect_button.setEnabled(False)

            return

        # Adds detected ports into combo box
        
        for port in ports:

            display_text = f"{port.device} - {port.description}"

            self.port_combo.addItem(display_text, port.device)

        self.connect_button.setEnabled(True)

    def connect_serial(self):

        # Gets selected COM port
        
        port_name = self.port_combo.currentData()

        if not port_name:

            QMessageBox.warning(
                self,
                "No Port Selected",
                "Please select a valid serial port."
            )

            return

        # Creates serial reader thread
        
        self.serial_thread = SerialReaderThread(port_name)

        # Connects thread signals to GUI functions
        
        self.serial_thread.tag_scanned.connect(self.handle_tag_scanned)

        self.serial_thread.serial_message.connect(self.add_log)

        self.serial_thread.connection_error.connect(self.handle_serial_error)

        self.serial_thread.start()

        self.connect_button.setEnabled(False)

        self.disconnect_button.setEnabled(True)

        self.port_combo.setEnabled(False)

        self.status_label.setText(f"Status: Connected to {port_name}")

    def disconnect_serial(self):

        if self.serial_thread:

            self.serial_thread.stop()

            self.serial_thread = None

        self.connect_button.setEnabled(True)

        self.disconnect_button.setEnabled(False)

        self.port_combo.setEnabled(True)

        self.status_label.setText("Status: Disconnected")

    def handle_tag_scanned(self, uid):

        # Adds or updates RFID tag in database
        
        result = self.db.add_or_update_tag(uid)

        # Creates different messages for new and existing tags
        
        if result["status"] == "new":

            message = (
                f"New tag saved: {result['tag_id']} | "
                f"UID: {result['rfid_uid']} | "
                f"Count: {result['scan_count']}"
            )

        else:

            message = (
                f"Existing tag updated: {result['tag_id']} | "
                f"UID: {result['rfid_uid']} | "
                f"Count: {result['scan_count']}"
            )

        self.latest_scan_label.setText(message)

        self.add_log(message)

        self.refresh_table()

    def refresh_table(self):

        search_text = self.search_input.text().strip()

        # Loads matching RFID records
        
        rows = self.db.get_all_tags(search_text)

        self.table.setRowCount(len(rows))

        # Inserts database data into table
        
        for row_index, row_data in enumerate(rows):

            for column_index, value in enumerate(row_data):

                item = QTableWidgetItem(str(value))

                item.setTextAlignment(Qt.AlignmentFlag.AlignCenter)

                self.table.setItem(row_index, column_index, item)

    def clear_database(self):

        # Confirmation dialog before deleting database
        
        confirm = QMessageBox.question(
            self,
            "Clear Database",
            "Are you sure you want to delete all saved RFID records?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
        )

        # Clears database if user confirms
        
        if confirm == QMessageBox.StandardButton.Yes:

            self.db.clear_database()

            self.refresh_table()

            self.latest_scan_label.setText("Database cleared.")

            self.add_log("Database cleared.")

    def add_log(self, message):

        # Adds timestamp to log messages
        
        timestamp = datetime.now().strftime("%H:%M:%S")

        self.log_output.append(f"[{timestamp}] {message}")

    def handle_serial_error(self, error_message):

        self.add_log(error_message)

        QMessageBox.critical(self, "Serial Error", error_message)

        self.disconnect_serial()

    def closeEvent(self, event):

        self.disconnect_serial()

        event.accept()

def main():

    # Creates PyQt application
    
    app = QApplication(sys.argv)

    # Creates main window
    
    window = RFIDDatabaseGUI()

    window.show()

    # Starts GUI event loop
    
    sys.exit(app.exec())


if __name__ == "__main__":

    main()
