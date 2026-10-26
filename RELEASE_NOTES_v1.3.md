# 🎮 Battle XP G350 USB Network Manager v1.3 — Release Notes

> **Direct USB wired tethering, PortMaster downloads, high-speed SFTP transfers, and Samba file sharing for the Battle XP G350 and Rockchip RK3326 handhelds running ArkOS / dArkOS.**

We are pleased to announce **v1.3** of the **Battle XP G350 USB Network Manager**! This minor update brings quality-of-life enhancements and polish to the handheld dashboard, eliminating offline menu lag, introducing real-time live auto-refreshing, bulletproofing DNS configuration for PortMaster, and formally decoupling the Console-to-Console (C2C) Netplay suite into its own dedicated companion repository.

---

## 🌟 What's New in v1.3

### 🔄 Real-Time Live Auto-Refresh (Flicker-Free)
* **Live Link & Gateway Monitoring:** The dashboard now automatically refreshes every ~4 seconds while sitting idle in the menu.
* **Plug & Play Awareness:** Plugging/unplugging the USB cable or toggling Windows Internet Connection Sharing (ICS) on your PC now updates on the handheld screen automatically with zero manual button presses required.
* **Flicker-Free In-Place Redraw:** Idle refreshes use ANSI cursor home positioning (`\033[H`) and line-clearing escapes (`\033[K`) rather than full terminal resets (`\033c`), completely eliminating screen flashing while preserving full resets for action transitions.

### ⚡ Zero-Lag Offline UI ($0\text{ ms}$ Menu Redraws)
* **Intelligent Gateway Gating:** The external internet check (`ping 8.8.8.8`) is now strictly gated behind an active IP and default route check (`[ -n "$RAW_GW" ] && [ -n "$ACTIVE_IP" ]`).
* **Instant Offline Responsiveness:** When offline, disconnected, or in Direct PC mode, the previous 1.0-second synchronous ping timeout is completely bypassed. The dashboard renders **instantly ($< 1\text{ ms}$)** with buttery-smooth gamepad navigation.

### 🌐 Bulletproof DNS Resolution for PortMaster
* **Dangling Symlink Cleanup:** In `USB_Network_Manager.sh` and standalone CLI helpers, the script now executes `sudo rm -f /etc/resolv.conf 2>/dev/null` immediately before setting nameservers (`1.1.1.1` and `8.8.8.8`).
* **Reliable PortMaster Downloads:** Resolves issues on ArkOS images where `/etc/resolv.conf` pointed to missing or uninitialized systemd-resolved stub directories in `/run/` on boot, ensuring domain names (`github.com`, `portmaster.games`) resolve reliably on the first attempt.

### 🛡️ Verified Windows Adapter Stability & C2C Netplay Safety
* **Windows 10/11 Plug-and-Play Binding:** Hardware testing confirmed that modern Windows binds network miniport adapters to the **USB Device Instance Path** (matching VID `0x0525` / PID `0xa4a2` on that physical USB port) rather than host MAC. Reconnects and reboots consistently maintain `Ethernet 2`, static IP assignments, and ICS sharing.
* **Collision-Free Architecture:** Retaining kernel-assigned dynamic MACs ensures full multi-device compatibility and prevents packet collisions and ARP loops during direct Console-to-Console (C2C) multiplayer links.

### 🎮 Dedicated C2C Netplay Companion Suite
* **Modular Ecosystem:** The 2-Player Console-to-Console USB Netplay suite is now packaged and maintained as an independent standalone project: **[RK3326-USB-Netplay](https://github.com/Just-Luis/RK3326-USB-Netplay) (v1.0.0)**.
* **Clean Separation:** PC tethering users enjoy a streamlined, clutter-free repository, while multiplayer enthusiasts have a dedicated single-script tool (`C2C_Netplay_Prep.sh`) with an interactive Role Wizard and automatic RetroArch port/IP pre-configuration.

### 🧹 Repository Polish & Windows Scripts Parity
* **Native Windows Batch Scripts:** Cleaned up `Test_Internet_On_G350.bat` to eliminate dead PowerShell fallback checks, running 100% natively with zero external dependencies.
* **Standard MIT License:** Added official `LICENSE` file matching the project repository badge and author attribution.
* **Checklist 100% Complete:** Fully resolved and closed out all items in `ISSUES_AND_POLISH_CHECKLIST.md`.
* **Line Ending Integrity:** Strict Unix `LF` line endings verified across all shell scripts and `CRLF` for Windows `.bat` tools.

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
* 🛠️ **Issues & Technical Audit:** [ISSUES_AND_POLISH_CHECKLIST.md](ISSUES_AND_POLISH_CHECKLIST.md)
