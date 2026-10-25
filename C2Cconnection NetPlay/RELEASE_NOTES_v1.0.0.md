# 🎮 RK3326-USB-Netplay v1.0.0 — Initial Release

> **Wired, Zero-Lag 2-Player RetroArch Netplay directly between two Battle XP G350 and RK3326 handhelds using a single USB cable.**

We are excited to announce the first official release of **RK3326-USB-Netplay**! This release brings true plug-and-play, offline 2-player multiplayer to Rockchip RK3326 retro handhelds running ArkOS / dArkOS with **sub-millisecond (< 0.5ms) latency** and zero Wi-Fi or router requirements.

---

## 🌟 Key Highlights & Features

### ⚡ Sub-Millisecond Wired Latency ($< 0.5\text{ ms}$)
* Establishes a direct private Ethernet subnet (`192.168.10.x`) over physical USB.
* Eliminates packet jitter, frame drops, and input lag common to budget handheld Wi-Fi chips.

### 🕹️ 100% Self-Contained (1 Single File)
* You only need **one single file** on your MicroSD card: **`C2C_Netplay_Prep.sh`**.
* No external helper scripts, dependencies, or PC tethering tools required.

### 🧙‍♂️ First-Launch Interactive Role Wizard
* On first launch, the script asks which console will be:
  * **`[A] PLAYER 1 (Netplay Host)`** — Uses USB-C OTG Host adapter, runs immediately with **no reboot required** on stock consoles!
  * **`[X] PLAYER 2 (Netplay Client)`** — Connects directly to Player 1; automatically configures the hardware and reboots once.
* Remembers your choice on subsequent launches, booting directly into the live connection dashboard.
* **In-Dashboard Role Switching:** Simply tap **`[X]`** anytime on the dashboard (`[X] Make P2` / `[X] Make P1`) to switch roles and reboot safely.

### 🧬 Autonomous Device Tree (DTB) Engine
* Embedded zero-dependency Python Flattened Device Tree (FDT) parser/serializer.
* Autonomously generates `rk3326-g350-peripheral.dtb` and `rk3326-g350-host.dtb` directly from the console's factory kernel binary offline—no internet or extra files needed.

### 🎮 Automated Offline RetroArch Configuration
* Automatically patches `retroarch.cfg` and `retroarch32.cfg`:
  * Disables online relay server searches and NAT traversal timeouts offline.
  * Pre-configures port `55435`.
  * Pre-fills Player 2's target IP to `192.168.10.1` (no manual IP typing with a D-Pad!).
  * Enforces `ark:ark` file permissions so RetroArch can save in-game configs on exit.

### 📺 Tailored 3.5" Handheld Dashboard
* Rendered strictly within 16 rows and 42 columns for 3.5" (480px) handheld screens.
* Flicker-free in-place redraw via ANSI home positioning.
* Real-time monitoring of cable carrier link, peer ping, and RetroArch port 55435 status.
* Accidental-exit protection: Requires firmly holding **`[START + SELECT]`** to exit.

### 🧪 Safe Netplay Reversion Helper (`Revert_Netplay.sh`)
* Included 1-click helper script to revert the console back to clean factory stock state for testing.
* **100% Safe:** Does **NOT** erase or touch your ROMs, save files, BIOS, or system configurations—it strictly restores the factory USB hardware mode (`dr_mode = "otg"`), clears the Netplay role memory, and restores RetroArch's online relay flags.

---

## 🔌 Hardware Cable Rule & Battery Safety

> [!CAUTION]
> **Avoid Direct Symmetrical USB-C to USB-C Cables!**  
> Because budget handheld motherboards lack CC pull-down resistors, direct C-to-C cables can cause both consoles to feed 5V reverse voltage into each other simultaneously, risking battery or charging IC damage.  
> **⭐ Safe Cabling Method:** Always plug a **USB-C Male to USB-A Female OTG adapter** into **Console 1 (Host)**, and connect a standard **USB-A to USB-C data cable** to **Console 2 (Client)**. This mechanically locks power and data in one direction.

---

## 💾 Quick Installation

1. Download **`C2C_Netplay_Prep.sh`** from this release.
2. Insert your console's MicroSD card into your PC.
3. Copy **`C2C_Netplay_Prep.sh`** into:
   ```text
   EASYROMS/tools/
   ```
   *(Or `ports/` if your EmulationStation theme lacks a Tools section).*
4. Repeat for Console 2.

---

## 🚀 How to Play

1. **First Run Setup:** Launch **`C2C Netplay Prep`** from **TOOLS** on both consoles. Select **`[A]`** on Console 1 (Player 1) and **`[X]`** on Console 2 (Player 2).
2. **Link Consoles:** Plug the USB cable between both consoles' OTG ports. Both screens will show **`PING TEST: ONLINE [OK]`**.
3. **Exit Tool:** Hold **`[START + SELECT]`** together on both consoles to return to EmulationStation *(keep cable connected!)*.
4. **Launch Game (Same ROM & Same Emulator Core):**
   * **Console 1 (Host):** Launch game ➔ `[Select] + [X]` ➔ **Netplay** ➔ **Host** ➔ **`Start Netplay Host`**.
   * **Console 2 (Client):** Launch game ➔ `[Select] + [X]` ➔ **Netplay** ➔ **`Connect to Netplay Host`**.
5. Both screens synchronize in real-time. Enjoy lag-free wired 2-player gaming!

---

## 📦 Release Assets
* **`C2C_Netplay_Prep.sh`** — Main all-in-one Netplay tool.
* **`Revert_Netplay.sh`** — Safe Netplay reversion & testing utility (does not touch games/saves).
* **`NETPLAY_GUIDE.md`** — Complete technical documentation & troubleshooting guide.
