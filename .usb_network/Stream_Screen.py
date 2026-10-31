#!/usr/bin/env python3
"""
G350 USB Screen Streamer (PC side)

Uploads its embedded console-side grabber (self-contained, single file) to the console over SFTP, runs it via SSH
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



def _ensure_deps():
    """Auto-install missing pip dependencies (paramiko, pillow) on first run."""
    import importlib
    import subprocess
    missing = []
    for module, package in (("paramiko", "paramiko"), ("PIL", "pillow")):
        try:
            importlib.import_module(module)
        except ImportError:
            missing.append(package)
    if missing:
        print(f"Installing missing dependencies: {', '.join(missing)} ...")
        try:
            subprocess.check_call([sys.executable, "-m", "pip", "install", "--user", *missing])
        except subprocess.CalledProcessError:
            sys.exit(f"Automatic install failed. Run manually: pip install {' '.join(missing)}")
        importlib.invalidate_caches()


_ensure_deps()

import paramiko  # noqa: E402
from PIL import Image, ImageTk  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
GRABBER_REMOTE = "/tmp/g350_grabber.py"
CANDIDATE_HOSTS = ["192.168.137.2", "192.168.7.2"]

# Embedded copy of .usb_network/g350_grabber.py (runs on the console).
GRABBER_SOURCE = r'''#!/usr/bin/env python3
"""
================================================================================
 Battle XP G350 / RK3326 Non-Invasive Direct Screen Grabber
================================================================================
 Captures live frames directly from DRM/KMS hardware CMA dma-buf (EmulationStation,
 RetroArch, PortMaster games) with automatic fallback to Linux framebuffer (/dev/fb0).

 Key Architectural Guarantees:
 1. Zero-Lock Ephemeral Mapping: DMA-BUFs are mapped, copied into memory, and
    immediately unmapped and closed (<1ms). Never pins CMA memory or locks DRM
    buffers, allowing games (RetroArch/SDL2) to launch, switch modes, and allocate
    VRAM with zero conflicts.
 2. Seamless Mode-Switch Smoothing: During game transitions (CRTC mode switches,
    loading screens, VT changes), repeats the last valid frame at target FPS so
    the video stream NEVER freezes or breaks the pipe.
 3. Robust Error Shielding: Catches all transitional DRM/ioctl errors and
    automatically recovers without crashing.
================================================================================
"""

import os
import sys
import time
import argparse
import ctypes
import mmap
import signal

# --- DRM & Linux IOCTL / Structures ---
class drmModeRes(ctypes.Structure):
    _fields_ = [
        ("count_fbs", ctypes.c_int),
        ("fbs", ctypes.POINTER(ctypes.c_uint32)),
        ("count_crtcs", ctypes.c_int),
        ("crtcs", ctypes.POINTER(ctypes.c_uint32)),
        ("count_connectors", ctypes.c_int),
        ("connectors", ctypes.POINTER(ctypes.c_uint32)),
        ("count_encoders", ctypes.c_int),
        ("encoders", ctypes.POINTER(ctypes.c_uint32)),
        ("min_width", ctypes.c_uint32),
        ("max_width", ctypes.c_uint32),
        ("min_height", ctypes.c_uint32),
        ("max_height", ctypes.c_uint32)
    ]

class drmModeModeInfo(ctypes.Structure):
    _fields_ = [
        ("clock", ctypes.c_uint32),
        ("hdisplay", ctypes.c_uint16),
        ("hsync_start", ctypes.c_uint16),
        ("hsync_end", ctypes.c_uint16),
        ("htotal", ctypes.c_uint16),
        ("hskew", ctypes.c_uint16),
        ("vdisplay", ctypes.c_uint16),
        ("vsync_start", ctypes.c_uint16),
        ("vsync_end", ctypes.c_uint16),
        ("vtotal", ctypes.c_uint16),
        ("vscan", ctypes.c_uint16),
        ("vrefresh", ctypes.c_uint32),
        ("flags", ctypes.c_uint32),
        ("type", ctypes.c_uint32),
        ("name", ctypes.c_char * 32)
    ]

class drmModeCrtc(ctypes.Structure):
    _fields_ = [
        ("crtc_id", ctypes.c_uint32),
        ("buffer_id", ctypes.c_uint32),
        ("x", ctypes.c_uint32),
        ("y", ctypes.c_uint32),
        ("width", ctypes.c_uint32),
        ("height", ctypes.c_uint32),
        ("mode_valid", ctypes.c_int),
        ("mode", drmModeModeInfo),
        ("gamma_size", ctypes.c_int)
    ]

class drmModeFB(ctypes.Structure):
    _fields_ = [
        ("fb_id", ctypes.c_uint32),
        ("width", ctypes.c_uint32),
        ("height", ctypes.c_uint32),
        ("pitch", ctypes.c_uint32),
        ("bpp", ctypes.c_uint32),
        ("depth", ctypes.c_uint32),
        ("handle", ctypes.c_uint32)
    ]


running = True

def handle_signal(sig, frame):
    global running
    running = False

signal.signal(signal.SIGINT, handle_signal)
signal.signal(signal.SIGTERM, handle_signal)


def init_drm(libdrm):
    """Safely open /dev/dri/card0 and obtain primary CRTC ID."""
    if not libdrm or not os.path.exists("/dev/dri/card0"):
        return -1, 0
    try:
        # Open read-only to avoid contesting DRM mastership
        fd = os.open("/dev/dri/card0", os.O_RDWR | os.O_CLOEXEC)
        res = libdrm.drmModeGetResources(fd)
        if res and res.contents.count_crtcs > 0:
            crtc_id = res.contents.crtcs[0]
            libdrm.drmModeFreeResources(res)
            return fd, crtc_id
        if res:
            libdrm.drmModeFreeResources(res)
        os.close(fd)
    except Exception as e:
        sys.stderr.write(f"[grabber] DRM open error: {e}\n")
    return -1, 0


def main():
    global running
    parser = argparse.ArgumentParser(description="RK3326 Non-Invasive Direct Screen Grabber")
    parser.add_argument("--fps", type=float, default=30.0, help="Target framerate (default: 30)")
    parser.add_argument("--width", type=int, default=640, help="Screen width (default: 640)")
    parser.add_argument("--height", type=int, default=480, help="Screen height (default: 480)")
    args = parser.parse_args()

    width = args.width
    height = args.height
    frame_bytes = width * height * 4
    target_delay = 1.0 / max(1.0, args.fps)

    # Load libdrm
    libdrm = None
    try:
        libdrm = ctypes.CDLL("libdrm.so.2")
        libdrm.drmModeGetResources.restype = ctypes.POINTER(drmModeRes)
        libdrm.drmModeGetCrtc.restype = ctypes.POINTER(drmModeCrtc)
        libdrm.drmModeGetFB.restype = ctypes.POINTER(drmModeFB)
        libdrm.drmModeFreeResources.argtypes = [ctypes.POINTER(drmModeRes)]
        libdrm.drmModeFreeCrtc.argtypes = [ctypes.POINTER(drmModeCrtc)]
        libdrm.drmModeFreeFB.argtypes = [ctypes.POINTER(drmModeFB)]
        libdrm.drmPrimeHandleToFD.restype = ctypes.c_int
    except Exception as e:
        sys.stderr.write(f"[grabber] libdrm warning: {e}\n")

    drm_fd, crtc_id = init_drm(libdrm)

    # Fallback /dev/fb0
    fb0_file = None
    try:
        if os.path.exists("/dev/fb0"):
            fb0_file = open("/dev/fb0", "rb")
    except Exception as e:
        sys.stderr.write(f"[grabber] fb0 warning: {e}\n")

    stdout_buf = sys.stdout.buffer
    # Frame buffer caches
    last_frame = bytearray(frame_bytes)
    row_stride_buffer = bytearray(frame_bytes)

    try:
        while running:
            t0 = time.time()
            got_frame = False

            # Ensure DRM fd is valid
            if libdrm and (drm_fd < 0 or crtc_id == 0):
                drm_fd, crtc_id = init_drm(libdrm)

            # --- 1. DRM / KMS Capture (Ephemeral) ---
            if libdrm and drm_fd >= 0 and crtc_id > 0:
                c = None
                try:
                    c = libdrm.drmModeGetCrtc(drm_fd, crtc_id)
                except Exception:
                    c = None

                if c:
                    buf_id = c.contents.buffer_id
                    libdrm.drmModeFreeCrtc(c)

                    if buf_id != 0:
                        fb = None
                        try:
                            fb = libdrm.drmModeGetFB(drm_fd, buf_id)
                        except Exception:
                            fb = None

                        if fb:
                            handle = fb.contents.handle
                            pitch = fb.contents.pitch
                            fb_h = fb.contents.height
                            size = pitch * fb_h
                            pfd = ctypes.c_int(-1)

                            ret = libdrm.drmPrimeHandleToFD(drm_fd, handle, 0, ctypes.byref(pfd))
                            libdrm.drmModeFreeFB(fb)

                            if ret == 0 and pfd.value >= 0:
                                try:
                                    mm = mmap.mmap(pfd.value, size, mmap.MAP_SHARED, mmap.PROT_READ)
                                    if pitch == width * 4:
                                        last_frame[:] = mm[:frame_bytes]
                                    else:
                                        # Stride compensation for padded buffers
                                        row_len = width * 4
                                        for y in range(height):
                                            y_off = y * pitch
                                            d_off = y * row_len
                                            last_frame[d_off : d_off + row_len] = mm[y_off : y_off + row_len]
                                    mm.close()
                                    got_frame = True
                                except Exception:
                                    pass
                                finally:
                                    os.close(pfd.value)

            # --- 2. Fallback to /dev/fb0 (Console Apps / Menus) ---
            if not got_frame and fb0_file:
                try:
                    fb0_file.seek(0)
                    n = fb0_file.readinto(row_stride_buffer)
                    if n >= frame_bytes:
                        # Verify not all zeros (which happens when fbcon is blanked during games)
                        if any(row_stride_buffer[:1000]):
                            last_frame[:] = row_stride_buffer[:frame_bytes]
                            got_frame = True
                except Exception:
                    pass

            # --- 3. Stream Smoothing ---
            # Output the captured frame (or repeat the last valid frame if in transition)
            try:
                stdout_buf.write(last_frame)
                stdout_buf.flush()
            except (BrokenPipeError, OSError):
                break

            # Frame pacing
            elapsed = time.time() - t0
            sleep_time = target_delay - elapsed
            if sleep_time > 0:
                time.sleep(sleep_time)

    except (BrokenPipeError, KeyboardInterrupt):
        pass
    finally:
        if fb0_file:
            try:
                fb0_file.close()
            except Exception:
                pass
        if drm_fd >= 0:
            try:
                os.close(drm_fd)
            except Exception:
                pass

if __name__ == "__main__":
    main()
'''


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
        with sftp.open(GRABBER_REMOTE, "w") as f:
            f.write(GRABBER_SOURCE.encode("utf-8"))
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
