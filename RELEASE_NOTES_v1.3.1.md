# 🎮 Battle XP G350 USB Network Manager v1.3.1 — Release Notes

> **Direct USB wired tethering, PortMaster downloads, high-speed SFTP transfers, and Samba file sharing for the Battle XP G350 and Rockchip RK3326 handhelds running ArkOS / dArkOS.**

We are pleased to release **v1.3.1**, a critical hotfix for the **Battle XP G350 USB Network Manager** addressing menu loop behavior and button handling.

---

## 🐛 Bug Fixes & Polish

### 🛡️ Fixed Unintended Script Exit & Mode Switch
* **The Issue:** In v1.3 builds containing the experimental background watcher daemon, pressing **`[A]` (Start Services)** would execute services and then immediately exit back to EmulationStation, while pressing **`[Y]` (Stop Services)** would stop services and then immediately trigger **`[X]` (Switch to USB Host Mode)** and reboot the console.
* **Root Cause:** An experimental background input watcher (`usb_mgr_btn_watch.py`) concurrently monitored `/dev/input/js*` and `/dev/input/event*` with conflicting code assignments (`JS_A = 1`, `EV_A = 304`), causing single button presses to simultaneously generate phantom flag files (`btn_a` + `btn_b` on A; `btn_y` + `btn_x` on Y). When the action completed and returned to the menu loop, the leftover flag file was immediately consumed by the next menu check.
* **The Fix:**
  * Completely removed the background watcher daemon (`usb_mgr_btn_watch.py`) and state directory polling.
  * Restored ArkOS's official, hardware-tested [`buttonmon.sh`](buttonmon.sh) routines (`Test_Button_A`, `Test_Button_Y`, `Test_Button_X`, `Test_Button_B`), providing native, reliable input detection tailored specifically for Rockchip RK3326 handheld gamepads.
  * Added automated startup and exit cleanup (`sudo pkill -f usb_mgr_btn_watch.py` and `rm -rf /tmp/usb_net_mgr`) to purge any stale processes or flag files left behind by older versions.

### 🧹 Input Buffer Drain on Action Return
* Added non-blocking input flushes (`while read -t 0.05 -n 1 _; do :; done`) immediately after returning from `start_services()` and `stop_services()`.
* Guarantees that any held buttons or buffered keystrokes during service initialization never bleed into the main menu loop.

### ⚡ Responsive Mode-Switch Reboot Cancellation
* Retained fast 100ms polling slices (`for _slice in {1..10}`) in `switch_hardware_mode()` so pressing **`[B]`** during the 5-second countdown cancels the reboot instantaneously without needing a background daemon.

---

## 💾 Quick Installation

`USB_Network_Manager.sh` is **100% self-contained**. You only need this single file on your handheld!

1. Shut down your console safely (`Start` ➔ `Quit` ➔ `Shutdown System`).
2. Insert your MicroSD card into your PC.
3. Copy **`USB_Network_Manager.sh`** into the **`tools/`** folder (recommended) or **`ports/`** folder on the `EASYROMS` partition.
4. Reinsert the card into your handheld and boot up. Launch **USB Network Manager** from **TOOLS** and press **`[A]`** to start services!

---

## 🔗 Companion Projects & Links

* 🕹️ **2-Player Offline Wired Multiplayer:** [RK3326-USB-Netplay on GitHub](https://github.com/Just-Luis/RK3326-USB-Netplay)
* 📖 **Complete Step-by-Step Tutorial:** [COMMUNITY_TUTORIAL.md](COMMUNITY_TUTORIAL.md)
