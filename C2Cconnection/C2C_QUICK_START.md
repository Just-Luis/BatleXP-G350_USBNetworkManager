# 🎮 C2C Quick Start Guide: Direct Handheld-to-Handheld USB Wired Connection

> **Connect two Battle XP G350 (or RK3326 ArkOS handhelds) directly together with a USB cable for zero-latency wired multiplayer, real-time controller testing, and instant ROM/save transfers!**

---

## ⚡ 1. What You Need

1. **Two Handheld Consoles:**
   * Handheld A running ArkOS / dArkOS.
   * Handheld B running ArkOS / dArkOS.
2. **Cabling Setup:**
   * **⭐ Best & Most Compatible:** A **USB-C Male to USB-A Female OTG adapter** plugged into **Console A (Host)** + a standard **USB-A to USB-C cable** connecting to **Console B (Peripheral)**.

> [!CAUTION]
> ### ⚠️ Risk of Battery Damage with Direct USB-C to USB-C Cables
> Connecting two handhelds directly using a standard **USB-C to USB-C cable** is **strongly discouraged**:
> * If not properly negotiated by both consoles, both devices may attempt to supply 5V power to each other over VBUS at the same time, which **can permanently damage the battery, charging circuitry, or motherboard**.
> * Furthermore, because most budget RK3326 handhelds omit CC pull-down resistors, pure C-to-C cables **most likely will not work at all** (showing `NO LINK`).
> * **⭐ The Best & Safest Option:** Always use a standard **USB-A to USB-C cable** connected to a **USB-C Male to USB-A Female OTG adapter** on **Console A (Host)**. This mechanically locks the power and data flow in one direction and safely prevents reverse voltage or battery damage.

> [!IMPORTANT]
> ### 🔌 USB Port Notes: Single-Port vs. Dual-Port Handhelds
> * **Battle XP G350:** Has a single USB-C port that handles **both OTG and DC** (charging and data on the same port). Simply plug the cable directly into this port.
> * **Dual-Port Handhelds (e.g. RG351 series, RGB20S, OGA):** These devices have two separate USB-C ports: **`OTG`** (data + power) and **`DC`** (charge-only). On dual-port devices, you must connect to the **`OTG`** port, as the `DC` port has no data lines.

---

## 🕹️ 2. Step-by-Step Setup

```
[Console A: USB HOST]                                 [Console B: PERIPHERAL]
+-------------------------+                           +-------------------------+
| Mode: USB HOST Mode     |=== USB-C to USB-C Cable ==| Mode: WIRED PC Mode     |
| Port: OTG Port          |   (or OTG Adapter + A-to-C)| Port: OTG Port          |
| IP: 192.168.10.1        |                           | IP: 192.168.10.2        |
+-------------------------+                           +-------------------------+
```

### Step 1: Set Console Modes
1. **On Console A (Host):**
   * Launch **`USB Network Manager`** from **TOOLS** (or **PORTS**).
   * Look at **`USB MODE`**:
     * If it says **`USB HOST (OTG Pendrives)`**, you are ready!
     * If it says **`WIRED PC (Peripheral)`**, press **`[X]`** to switch and allow the console to reboot into Host mode.
2. **On Console B (Peripheral):**
   * Launch **`USB Network Manager`**.
   * Look at **`USB MODE`**:
     * If it says **`WIRED PC (Peripheral)`**, you are ready!
     * If it says **`USB HOST`**, press **`[X]`** to switch and reboot into Peripheral mode.

---

### Step 2: Connect the Cable
* Connect the cable between the **`OTG`** port on Console A and the **`OTG`** port on Console B.

---

### Step 3: Launch Connection Test & Live Input Visualizer
1. Copy `C2C_Connection_Test.sh` to `tools/` or `ports/` on both consoles (or run via terminal).
2. Launch **`C2C Connection Test`** on **Console A**, then launch it on **Console B**.
3. Within 2 seconds, both dashboards will illuminate:
   * **`CABLE LINK`**: `CONNECTED [CARRIER OK]`
   * **`PING / RTT`**: `0% LOSS (0.35 ms) [OK]`
   * **`PEER GAMEPAD INPUT`**: Real-time display of the other console's buttons!

---

## 🎮 3. Testing the Live Peer Input Mirroring

With **`C2C Connection Test`** running on both screens:
1. **Mash buttons on Console B:**
   * Watch **Console A's screen**!
   * **Face Buttons:** `[A]`, `[B]`, `[X]`, `[Y]` light up in real time.
   * **Physical D-Pad:** `[U]`, `[D]`, `[L]`, `[R]` illuminate when pressing the D-pad.
   * **Shoulder & Triggers:** `[L1]`, `[R1]`, `[L2]`, `[R2]` illuminate when pressing the shoulder buttons.
   * **Analog Joystick:** `[U]`, `[D]`, `[L]`, `[R]` illuminate on the `JOY` line when moving the thumbstick.
   * **Options:** `[SEL]` and `[STA]` illuminate when pressed.
2. **Exit at any time:**
   * **ONLY hold `[START + SELECT]` together** to exit back to EmulationStation.
   * *(Single button presses like `[B]` do not exit, so you can test all buttons freely!)*

---

## 🚀 4. Use Cases & Advanced Features

### 4.1 Offline 2-Player RetroArch Netplay (Sub-1ms Ping)
Wired USB peer-to-peer Netplay provides lower latency and zero packet jitter compared to Wi-Fi.

> 📖 **For the detailed setup guide, DTB hardware requirements, and troubleshooting, see [NETPLAY_GUIDE.md](NETPLAY_GUIDE.md).**

#### ⭐ 1-Click Netplay Fixer (`C2C_Netplay_Prep.sh`):
Before playing, run **`C2C_Netplay_Prep.sh`** on both handhelds. It automatically:
* Ensures `usb0` is up and assigned `192.168.10.x`.
* Patches RetroArch configs to turn **OFF** Relay Servers and NAT Traversal (the #1 cause of *"Failed to initialize network"*).
* Pre-fills the Host IP `192.168.10.1` on the Client console!

> [!IMPORTANT]
> **Do not disconnect the cable or restart the consoles** after running `C2C_Netplay_Prep.sh`. Disconnecting the cable drops the active `usb0` interface and restarting wipes dynamic IP routes. If the cable is unplugged or a console reboots, re-run `C2C_Netplay_Prep.sh` before launching the game.

#### Manual Connection Steps:
1. Ensure both consoles are connected via C2C.
2. In RetroArch on **both consoles**, go to **Settings** ➔ **Netplay**:
   * **`Use Relay Server`** ➔ **`OFF`** (Essential for offline cable play!)
   * **`NAT Traversal`** ➔ **`OFF`** (There is no router/UPnP on a direct USB cable!)
   * **`Publicly Announce Netplay`** ➔ **`OFF`**
3. On **Console A (Host)**:
   * Launch your game.
   * Press **`[Select] + [X]`** ➔ **Netplay** ➔ **Host** ➔ **`Start Netplay Host`**.
   * Wait until you see: *"Waiting for client..."* or *"You have joined as Player 1"*.
4. On **Console B (Client)**:
   * Launch the **exact same game and core**.
   * Press **`[Select] + [X]`** ➔ **Netplay** ➔ **`Connect to Netplay Host`**.
   * Enter Host IP: **`192.168.10.1`** (Port: `55435`).
5. Enjoy lag-free wired multiplayer!

---

### 4.2 Handheld-to-Handheld Save & ROM Sync (SFTP)
You can directly transfer ROMs and `.srm` save files between consoles without a PC:
* Open terminal / SSH on Console A:
  ```bash
  # Copy a save file directly from Console B to Console A:
  scp ark@192.168.10.2:/roms/snes/SuperMarioWorld.srm /roms/snes/
  ```
* Default login credentials for peer:
  * **User:** `ark`
  * **Password:** `ark`
  * **Port:** `22`

---

## ❓ 5. Troubleshooting Matrix

| Issue | Cause | Fix |
| :--- | :--- | :--- |
| **`CABLE LINK: NO LINK`** | On dual-port consoles, cable is in the charge-only (`DC`) port. | Move cable to the **OTG** port (G350 has a single combined port). |
| **`CABLE LINK: NO LINK`** *(using Type-C to Type-C)* | Missing CC pull-down resistors; potential 5V backfeed risk. | Use a **USB-C Male to USB-A Female OTG adapter** on Console A (Host), then connect via USB-A to USB-C cable. |
| **Both consoles show `[HOST]`** | Both consoles booted in Host mode. | On Console B, launch `USB Network Manager` and press `[X]` to switch to Peripheral mode, then restart. |
| **Ping 100% loss** | Network interface unassigned. | Run `c2c_setup.sh` or `C2C_Netplay_Prep.sh` to bind `192.168.10.x`. |
| **`"Failed to initialize network"` in RetroArch** | 1. `Use Relay Server` or `NAT Traversal` is ON.<br>2. Host has not started hosting yet.<br>3. `usb0` interface dropped. | 1. Run `C2C_Netplay_Prep.sh` to auto-fix configs.<br>2. In RetroArch: Turn **OFF** Relay Server & NAT Traversal.<br>3. Ensure Host selects **Start Netplay Host** *before* Client connects. |
| **SSH Port 22 shows `NOT STARTED`** | SSH daemon not running on peer. | On the peer console, launch `USB Network Manager` and press `[A]` (Start Services). |
