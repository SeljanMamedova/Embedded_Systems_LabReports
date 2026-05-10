import csv
import os
import queue
import threading
import time
import tkinter as tk
from collections import defaultdict
from datetime import datetime
from tkinter import messagebox, ttk

import matplotlib
matplotlib.use("TkAgg")

from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg
from matplotlib.figure import Figure

import serial
import serial.tools.list_ports

DATA_DIR = "players"

# Creates players folder automatically
os.makedirs(DATA_DIR, exist_ok=True)

# CSV file for storing overall victories
VICTORY_LOG = os.path.join(DATA_DIR, "_victories.csv")

class SerialManager:

    def __init__(self):

        self.ser = None

        # Queue used for storing incoming serial messages
        self.rx_queue = queue.Queue()

        self._running = False
        self._thread = None

    @staticmethod
    def list_ports():

        # Returns all available COM ports
        return [p.device for p in serial.tools.list_ports.comports()]

    def connect(self, port, baud=9600):

        # Opens serial connection with Arduino
        self.ser = serial.Serial(port, baud, timeout=0.1)

        # Waits for Arduino auto reset
        time.sleep(2.0)

        self.ser.reset_input_buffer()

        self._running = True

        # Starts background thread for reading serial data
        self._thread = threading.Thread(target=self._reader, daemon=True)

        self._thread.start()

    def disconnect(self):

        self._running = False

        try:
            if self.ser:

                # Closes serial connection
                self.ser.close()

        except Exception:
            pass

        self.ser = None

    def is_open(self):

        # Checks whether serial port is connected
        return self.ser is not None and self.ser.is_open

    def _reader(self):

        buf = b""

        # Continuously reads serial data from Arduino
        
        while self._running and self.ser:

            try:
                chunk = self.ser.read(128)

                if chunk:

                    buf += chunk

                    # Processes incoming lines
                    
                    while b"\n" in buf:

                        line, buf = buf.split(b"\n", 1)

                        try:
                            text = line.decode("utf-8", errors="ignore").strip()

                        except Exception:
                            text = ""

                        # Stores received message into queue
                        if text:
                            self.rx_queue.put(text)

            except Exception:
                break

    def poll(self):

        # Returns newest serial message if available
        try:
            return self.rx_queue.get_nowait()

        except queue.Empty:
            return None

class PlayerData:

    @staticmethod
    def safe_name(name):

        # Removes invalid filename characters
        
        clean = "".join(c for c in name if c.isalnum() or c in ("-", "_", " ")).strip()

        return clean or "unnamed"

    @classmethod
    def path_for(cls, name):

        # Creates CSV path for each player
        return os.path.join(DATA_DIR, f"{cls.safe_name(name)}.csv")

    @classmethod
    def record_round(cls, player, opponent, rt_ms, won, false_start,
                     session_id, round_num):

        path = cls.path_for(player)

        # Checks whether CSV file already exists
        is_new = not os.path.exists(path)

        with open(path, "a", newline="") as f:

            w = csv.writer(f)

            # Writes headers only for new CSV files
            if is_new:

                w.writerow([
                    "timestamp", "session_id", "round", "opponent",
                    "reaction_time_ms", "won", "false_start"
                ])

            # Saves round information into CSV
            w.writerow([
                datetime.now().isoformat(timespec="seconds"),
                session_id, round_num, opponent,
                rt_ms if rt_ms is not None else "",
                int(bool(won)), int(bool(false_start))
            ])

    @staticmethod
    def record_victory(winner, loser, session_id, final_score):

        is_new = not os.path.exists(VICTORY_LOG)

        with open(VICTORY_LOG, "a", newline="") as f:

            w = csv.writer(f)

            # Adds headers for new victory file
            if is_new:

                w.writerow(["timestamp", "session_id", "winner", "loser", "final_score"])

            # Saves final match result
            w.writerow([
                datetime.now().isoformat(timespec="seconds"),
                session_id, winner, loser, final_score
            ])

class ReactionGameApp:

    IDLE   = "idle"
    ACTIVE = "active"
    ENDED  = "ended"

    def __init__(self, root):

        self.root = root

        # Sets application title
        self.root.title("Lab Task 6 — Two-Player Reaction Game (Host)")

        # Sets GUI window size
        self.root.geometry("950x760")

        # Creates serial manager object
        self.link = SerialManager()

        self.pending_p1 = ""
        self.pending_p2 = ""

        self.armed = False

        self.p1_name = ""
        self.p2_name = ""

        # Game state variables
        self.state = self.IDLE

        self.p1_wins = 0
        self.p2_wins = 0

        self.round_num = 0

        self.session_id = ""

        # Builds graphical interface
        self._build_ui()

        # Starts serial monitoring
        self._pump_serial()

    def _build_ui(self):

        # Creates notebook tabs
        self.nb = ttk.Notebook(self.root)

        self.nb.pack(fill="both", expand=True)

        self.game_tab = ttk.Frame(self.nb)
        self.stats_tab = ttk.Frame(self.nb)

        self.nb.add(self.game_tab, text="Game")
        self.nb.add(self.stats_tab, text="Statistics")

        self._build_game_tab()

        self._build_stats_tab()

    def _refresh_ports(self):

        # Loads available COM ports
        ports = SerialManager.list_ports()

        self.port_combo["values"] = ports

        # Automatically selects first port
        if ports and not self.port_var.get():

            self.port_var.set(ports[0])

    def _toggle_connect(self):

        # Disconnects if already connected
        if self.link.is_open():

            self.link.disconnect()

            self.conn_status.config(text="Disconnected", foreground="red")

            self.connect_btn.config(text="Connect")

            self._log("Disconnected.", "info")

            return

        port = self.port_var.get().strip()

        # Warns user if no COM port selected
        if not port:

            messagebox.showwarning("No port", "Select a serial port first.")

            return

        try:
            # Connects GUI with Arduino
            self.link.connect(port)

            self.conn_status.config(text=f"Connected: {port}", foreground="green")

            self.connect_btn.config(text="Disconnect")

            self._log(f"Opened serial port {port}.", "info")

        except Exception as exc:

            messagebox.showerror("Serial error", f"Could not open {port}:\n{exc}")

    def _arm_names(self):

        # Reads player names from entry boxes
        p1 = self.p1_entry.get().strip()

        p2 = self.p2_entry.get().strip()

        # Ensures both names are entered
        if not p1 or not p2:

            messagebox.showwarning("Names", "Enter both player names first.")

            return

        # Prevents duplicate player names
        if p1.lower() == p2.lower():

            messagebox.showwarning("Names", "Player names must be different.")

            return

        # Stores names for next match
        self.pending_p1 = p1
        self.pending_p2 = p2

        self.armed = True

    def _pump_serial(self):

        # Continuously checks incoming Arduino messages
        while True:

            line = self.link.poll()

            if line is None:
                break

            self._handle_arduino_line(line)

        # Repeats every 30 milliseconds
        self.root.after(30, self._pump_serial)

    def _handle_arduino_line(self, line):

        # Displays incoming serial messages in log
        self._log(f"ARD> {line}", "ard")

        if line == "GAME STARTS AUTOMATICALLY":

            self.state = self.IDLE

            return

        # Detects new round
        if line == "NEW ROUND":

            self._on_new_round()

            return

        # Detects round winner
        if line.startswith("P1 WIN:") or line.startswith("P2 WIN:"):

            self._on_round_win(line)

            return

        # Detects false start
        if line.startswith("FALSE START"):

            self._on_false_start(line)

            return

        # Detects overall winner
        if line.startswith("GAME WINNER:"):

            self._on_game_winner(line)

            return

    def _begin_new_match(self):

        # Loads armed names into current game
        if self.armed and self.pending_p1 and self.pending_p2:

            self.p1_name = self.pending_p1
            self.p2_name = self.pending_p2

            self.armed = False

        # Resets match scores
        self.p1_wins = 0
        self.p2_wins = 0

        self.round_num = 0

        # Creates unique session ID
        self.session_id = datetime.now().strftime("%Y%m%dT%H%M%S")

        self.state = self.ACTIVE

        self._update_scoreboard()

    def _on_round_win(self, line):

        try:
            # Splits serial message into winner and reaction time
            prefix, rt_str = line.split(":", 1)

            winner = 1 if prefix.strip() == "P1 WIN" else 2

            rt = int(rt_str.strip())

        except ValueError:
            return

        # Updates score depending on winner
        if winner == 1:

            self.p1_wins += 1

        else:

            self.p2_wins += 1

        self._update_scoreboard()

        # Saves match data into CSV files
        if self.p1_name and self.p2_name:

            if winner == 1:

                PlayerData.record_round(
                    self.p1_name,
                    self.p2_name,
                    rt,
                    True,
                    False,
                    self.session_id,
                    self.round_num
                )

            else:

                PlayerData.record_round(
                    self.p2_name,
                    self.p1_name,
                    rt,
                    True,
                    False,
                    self.session_id,
                    self.round_num
                )

    def _on_false_start(self, line):

        # Detects which player pressed early
        
        who = line.split()[-1].upper()

        offender = 1 if who == "P1" else 2

        winner = 2 if offender == 1 else 1

        # Gives point to opposite player
        if winner == 1:

            self.p1_wins += 1

        else:

            self.p2_wins += 1

        self._update_scoreboard()

        # Ends current match after false start
        self.state = self.ENDED

    def _on_game_winner(self, line):

        # Extracts winner from Arduino message
        
        winner_str = line.split(":", 1)[1].strip().upper()

        winner = 1 if winner_str == "P1" else 2

        self.state = self.ENDED

        # Displays final winner on GUI
        self.status_label.config(
            text=f"🏆  MATCH WINNER: {self._name_for(winner)}",
            foreground="#060"
        )

    def _update_scoreboard(self):

        # Updates score label on screen
        self.score_label.config(
            text=f"{self._name_for(1)}: {self.p1_wins}    —    {self._name_for(2)}: {self.p2_wins}"
        )

if __name__ == "__main__":

    # Creates Tkinter window
    
    root = tk.Tk()

    try:
        # Sets GUI theme
        
        ttk.Style().theme_use("clam")

    except:
        pass

    # Creates application object
    
    app = ReactionGameApp(root)

    # Starts GUI event loop
    
    root.mainloop()
