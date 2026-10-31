#!/usr/bin/env python3
"""
G350 USB Screen Streamer (PC side)

Uploads .usb_network/g350_grabber.py to the console over SFTP, runs it via SSH
and shows the raw BGRA frames it emits in a live window.

Requirements (PC):  pip install paramiko pillow     (tkinter ships with Python)
Console:            USB network services running (Start_Wired_Services.sh / USB_Network_Manager.sh)

Usage:
    python Stream_Screen.py                 # auto-detect 192.168.137.2 / 192.168.7.2
    python Stream_Screen.py --host 192.168.7.2 --fps 20 --scale 1.5
Keys: S = save screenshot (PNG), Q / Esc = quit
"""

import argparse
import os
import socket
import sys
import threading
import time
import tkinter as tk
from tkinter import messagebox

import paramiko
from PIL import Image, ImageTk

HERE = os.path.dirname(os.path.abspath(__file__))
GRABBER_LOCAL = os.path.join(HERE, ".usb_network", "g350_grabber.py")
GRABBER_REMOTE = "/tmp/g350_grabber.py"
CANDIDATE_HOSTS = ["192.168.137.2", "192.168.7.2"]


def find_host(port=22, timeout=1.5):
    for h in CANDIDATE_HOSTS:
        try:
            with socket.create_connection((h, port), timeout=timeout):
                return h
        except OSError:
            continue
    return None


class Streamer:
    def __init__(self, args):
        self.args = args
        self.w, self.h = args.width, args.height
        self.frame_bytes = self.w * self.h * 4
        self.latest = None          # newest raw frame
        self.lock = threading.Lock()
        self.stop = threading.Event()
        self.error = None
        self.client = None
        self.frames = 0

    def connect(self):
        c = paramiko.SSHClient()
        c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        c.connect(self.args.host, username=self.args.user, password=self.args.password,
                  timeout=10, allow_agent=False, look_for_keys=False)
        c.get_transport().set_keepalive(5)
        sftp = c.open_sftp()
        sftp.put(GRABBER_LOCAL, GRABBER_REMOTE)
        sftp.close()
        self.client = c

    def reader(self):
        try:
            cmd = (f"echo {self.args.password} | sudo -S -p '' python3 {GRABBER_REMOTE} "
                   f"--fps {self.args.fps} --width {self.w} --height {self.h}")
            chan = self.client.get_transport().open_session()
            chan.exec_command(cmd)
            while not self.stop.is_set():
                buf = bytearray()
                while len(buf) < self.frame_bytes:
                    chunk = chan.recv(self.frame_bytes - len(buf))
                    if not chunk:
                        err = chan.recv_stderr(4096).decode(errors="ignore") if chan.recv_stderr_ready() else ""
                        raise ConnectionError("Stream ended. " + err.strip())
                    buf += chunk
                with self.lock:
                    self.latest = bytes(buf)
                self.frames += 1
        except Exception as e:
            if not self.stop.is_set():
                self.error = str(e)

    def run(self):
        self.connect()
        threading.Thread(target=self.reader, daemon=True).start()

        root = tk.Tk()
        root.title(f"G350 Screen - {self.args.host}")
        sw, sh = int(self.w * self.args.scale), int(self.h * self.args.scale)
        label = tk.Label(root, bg="black")
        label.pack()
        root.geometry(f"{sw}x{sh}")
        state = {"img": None, "raw": None, "t": time.time(), "n": 0}

        def save(_=None):
            if state["raw"]:
                name = time.strftime("g350_%Y%m%d_%H%M%S.png")
                state["raw"].save(os.path.join(HERE, name))
                root.title(f"Saved {name}")

        def close(_=None):
            self.stop.set()
            root.destroy()

        def tick():
            if self.error:
                messagebox.showerror("Stream error", self.error)
                return close()
            with self.lock:
                data, self.latest = self.latest, None
            if data:
                img = Image.frombuffer("RGB", (self.w, self.h), data, "raw", "BGRX", 0, 1)
                state["raw"] = img
                if self.args.scale != 1:
                    img = img.resize((sw, sh), Image.BILINEAR)
                state["img"] = ImageTk.PhotoImage(img)
                label.configure(image=state["img"])
                state["n"] += 1
                if time.time() - state["t"] >= 1:
                    root.title(f"G350 Screen - {self.args.host} - {state['n']} fps")
                    state["n"], state["t"] = 0, time.time()
            root.after(5, tick)

        root.bind("s", save)
        root.bind("q", close)
        root.bind("<Escape>", close)
        root.protocol("WM_DELETE_WINDOW", close)
        tick()
        root.mainloop()

        self.stop.set()
        try:
            self.client.exec_command("sudo pkill -f g350_grabber.py")
            self.client.close()
        except Exception:
            pass


def main():
    p = argparse.ArgumentParser(description="Stream the G350 screen over USB")
    p.add_argument("--host", help="Console IP (default: auto-detect)")
    p.add_argument("--user", default="ark")
    p.add_argument("--password", default="ark")
    p.add_argument("--fps", type=float, default=30)
    p.add_argument("--width", type=int, default=640)
    p.add_argument("--height", type=int, default=480)
    p.add_argument("--scale", type=float, default=1.0, help="Window scale factor")
    args = p.parse_args()

    if not os.path.isfile(GRABBER_LOCAL):
        sys.exit(f"Missing {GRABBER_LOCAL}")
    args.host = args.host or find_host()
    if not args.host:
        sys.exit("Console not reachable on 192.168.137.2 / 192.168.7.2. "
                 "Start the USB network services on the console first.")
    print(f"Connecting to {args.host} ...")
    try:
        Streamer(args).run()
    except Exception as e:
        sys.exit(f"Failed: {e}")


if __name__ == "__main__":
    main()
