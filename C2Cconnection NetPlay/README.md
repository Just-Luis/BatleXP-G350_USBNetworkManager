# 🎮 RK3326-USB-Netplay — Direct Wired 2-Player RetroArch Netplay

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Rockchip%20RK3326%20%7C%20Battle%20XP%20G350-blue.svg)]()
[![OS](https://img.shields.io/badge/OS-ArkOS%20%7C%20dArkOS-green.svg)]()
[![Latency](https://img.shields.io/badge/Latency-%3C%200.5ms%20(Sub--millisecond)-brightgreen.svg)]()

> **Zero-Lag, Offline 2-Player RetroArch Netplay directly between two Battle XP G350 (or Rockchip RK3326) handhelds using a single USB cable. No Wi-Fi, no router, no internet required.**

---

> 💡 **Looking for PC File Transfers & Internet Tethering?**  
> If you want to connect your handheld to a Windows PC for fast ROM transfers (SFTP/Samba) or Wi-Fi internet sharing for PortMaster, check out our companion project:  
> 🔗 **[Battle XP G350 USB Network Manager](https://github.com/Just-Luis/BatleXP-G350_USBNetworkManager)**

---

## 📑 Table of Contents
1. [Why Wired USB Netplay?](#-why-wired-usb-netplay)
2. [Supported Devices](#-supported-devices)
3. [Physical Cable Setup & Battery Safety](#-physical-cable-setup--battery-safety)
4. [Installation (1 Single File)](#-installation-1-single-file)
5. [Quickstart: 3-Phase Guide](#-quickstart-3-phase-guide)
   * [Phase 1: First-Launch Role Setup](#phase-1-first-launch-role-setup-one-time)
   * [Phase 2: Live Connection & Port Monitoring](#phase-2-live-connection--port-monitoring)
   * [Phase 3: In-Game RetroArch Hosting & Joining](#phase-3-in-game-retroarch-hosting--joining)
6. [Testing & Returning to Stock](#-testing--returning-to-stock)
7. [Troubleshooting Matrix](#-troubleshooting-matrix)
8. [License](#-license)

---

## ⚡ Why Wired USB Netplay?

Wi-Fi netplay on budget retro handhelds often suffers from packet loss, high ping spikes, and the need to carry a portable Wi-Fi hotspot when gaming on the go.

**RK3326-USB-Netplay** creates an isolated, point-to-point wired Ethernet link directly between two handhelds over USB:
* **Sub-Millisecond Latency:** Consistently under **$0.5\text{ ms}$** response times.
* **100% Offline:** Play on the couch, in a car, or on an airplane without any router.
* **Single-Script Architecture:** You only need **one script** (`C2C_Netplay_Prep.sh`) on your SD card.
* **Autonomous Device Tree Patching:** Generates required hardware profiles directly on the console with zero dependencies.
* **Zero RetroArch Friction:** Automatically configures offline ports and target IPs—no manual IP typing on a handheld d-pad!

```
[ Console 1: PLAYER 1 (HOST) ]                         [ Console 2: PLAYER 2 (CLIENT) ]
+----------------------------+                        +------------------------------+
| Device Tree: HOST Mode     |=== USB OTG Data Cable ===| Device Tree: PERIPHERAL Mode  |
| Static IP: 192.168.10.1    |                        | Static IP: 192.168.10.2      |
| RetroArch: Netplay Host    |                        | RetroArch: Netplay Client    |
+----------------------------+                        +------------------------------+
```

---

## 🎮 Supported Devices

Optimized for **Battle XP G350** and compatible with any **Rockchip RK3326** handheld running **ArkOS** or **dArkOS**:
* **Battle XP G350**
* **Anbernic RG351P / RG351M / RG351V**
* **Powkiddy RGB20S / RGB10**
* **RK2020 / Odroid Go Advance (OGA)**

---

## 🔌 Physical Cable Setup & Battery Safety

```
[ Console 1: PLAYER 1 (HOST) ]                         [ Console 2: PLAYER 2 (CLIENT) ]
+----------------------------+                        +------------------------------+
| USB-C Male to USB-A Female |==== USB-A to USB-C ====| Standard USB-C OTG Port      |
| OTG Adapter                |     Data Cable         | (Client / Peripheral)        |
+----------------------------+                        +------------------------------+
```

> [!CAUTION]
> ### ⚠️ Risk of Battery Damage with Direct C-to-C Cables
> Connecting two handhelds directly with a standard **symmetrical USB-C to USB-C cable** is **strongly discouraged**:
> * Budget handheld boards omit CC pull-down resistors. Both units may attempt to push 5V over VBUS at the same time, risking permanent damage to the charging IC or battery.
> * **⭐ The Best & Safest Solution:** Plug a **USB-C Male to USB-A Female OTG adapter** into **Console 1 (Host)**, and connect a standard **USB-A to USB-C data cable** to **Console 2 (Client)**. This mechanically locks power and data flow in one direction.

---

## 💾 Installation (1 Single File)

You only need to copy **[`C2C_Netplay_Prep.sh`](C2C_Netplay_Prep.sh)** to both handhelds' MicroSD cards:

```text
EASYROMS/ (or roms/)
└── tools/                         <-- ⭐ STRONGLY RECOMMENDED LOCATION
    └── C2C_Netplay_Prep.sh        (Appears under the "TOOLS" menu in EmulationStation)
```
*(If your ArkOS theme lacks a Tools section, copy it into `ports/` instead).*

---

## 🚀 Quickstart: 3-Phase Guide

### Phase 1: First-Launch Role Setup (One-Time)

Launch **`C2C Netplay Prep`** from **TOOLS** on **both consoles**.

On first run, the interactive wizard will ask:
```text
==========================================
   C2C NETPLAY — FIRST TIME SETUP         
==========================================
 Choose the role for this console:

 [A] PLAYER 1  (Host / Room Creator)
     • Starts Netplay room in RetroArch
     • Uses USB-C OTG Host adapter

 [X] PLAYER 2  (Client / Joiner)
     • Connects to Player 1 directly
     • Reboots to activate Client mode

 [B] Exit to EmulationStation
==========================================
```

1. **On Console 1 (Host):** Press **`[A]`**. Factory consoles already run in Host mode physically, so **no reboot is required!** It enters the dashboard immediately.
2. **On Console 2 (Client):** Press **`[X]`**. The script automatically generates the Peripheral Device Tree and reboots the console in 3 seconds. After reboot, launch `C2C Netplay Prep` again—it will load directly as Player 2.

> [!TIP]
> **Switching Roles Later:** On the main dashboard, simply tap **`[X]`** anytime (`[X] Make P2` / `[X] Make P1`) to switch roles and reboot safely.

---

### Phase 2: Live Connection & Port Monitoring

Connect your USB cable between both consoles.

Both screens will update in real time:
```text
==========================================
   C2C RETROARCH NETPLAY SETUP & TEST     
==========================================
 LOCAL ROLE : [HOST] Player 1 (192.168.10.1)
 PEER ROLE  : [CLIENT] Player 2 (192.168.10.2)
 IFACE / IP : usb0  192.168.10.1
 CABLE LINK : CONNECTED [CARRIER OK]
 PING TEST  : ONLINE [OK]
------------------------------------------
 NETPLAY STATUS (Host Port 55435):
 > READY (Will open when you host)
 NEXT: Launch game, [Select]+[X],
       Netplay > Start Netplay Host
------------------------------------------
 [A] Retest  [X] Make P2   [STA+SEL] Exit
==========================================
```

Once **`PING TEST : ONLINE [OK]`** appears:
* **Hold `[START + SELECT]`** simultaneously to exit back to EmulationStation.
* *(Keep the USB cable connected and do not reboot the consoles).*

---

### Phase 3: In-Game RetroArch Hosting & Joining

> [!IMPORTANT]
> Both consoles must load the **exact same ROM file** (identical hash) using the **exact same emulator core** (e.g. Genesis Plus GX, Snes9x, Gambatte).

1. **On Console 1 (Player 1 / Host):**
   * Launch the game.
   * Press **`[Select] + [X]`** to open the RetroArch Quick Menu.
   * Go to **Netplay** ➔ **Host** ➔ **`Start Netplay Host`**.
   * Resume the game.
2. **On Console 2 (Player 2 / Client):**
   * Launch the same game with the same core.
   * Press **`[Select] + [X]`** to open the RetroArch Quick Menu.
   * Go to **Netplay** ➔ **`Connect to Netplay Host`**.
   * *(No IP entry needed—the prep script already configured `192.168.10.1`!)*
   * RetroArch connects immediately (`Player 2 connected`). Resume the game and enjoy 2-player gaming!

---

## 🧪 Testing & Reverting Netplay Settings

Want to test the clean install experience or return your console to factory state without reflashing your MicroSD card?

Run [`Revert_Netplay.sh`](Revert_Netplay.sh) from **TOOLS** (or via SSH terminal: `sudo bash Revert_Netplay.sh`). It will:
1. Restore the original factory Device Tree (`dr_mode = "otg"`).
2. Wipe generated `.dtb` profiles and role state files.
3. Reset RetroArch Netplay settings back to default.
4. Reboot the console into clean factory state.

> [!NOTE]
> ### 🛡️ 100% Safe — Games & Saves Are Untouched!
> `Revert_Netplay.sh` does **NOT** format your SD card or erase any files.
> * Your ROMs, saves, savestates, box art, BIOS files, and emulator settings are **completely untouched**.
> * It strictly reverts the USB hardware mode and clears the Netplay setup memory.

---

## 🛠️ Troubleshooting Matrix

| Issue | Cause | Solution |
| :--- | :--- | :--- |
| **`"Failed to initialize network"`** | RetroArch tried to contact online relay servers. | Launch `C2C_Netplay_Prep.sh` on both consoles to disable relay servers offline. |
| **Client says `"Netplay host not found"`** | Host has not yet started hosting in RetroArch. | Ensure Player 1 selects **Start Netplay Host** before Player 2 selects **Connect to Netplay Host**. |
| **`CABLE LINK: NO LINK`** | 1. Using a charge-only DC port.<br>2. Cable disconnected. | Use the `OTG` port on dual-port handhelds. Check cable connection. |
| **Game desyncs or freezes** | ROM or emulator core mismatch. | Verify both handhelds use the exact same ROM dump and same emulator core. Disable cheats. |
| **Cannot exit `C2C_Netplay_Prep.sh`** | Accidental button press protection. | Firmly **hold `[START + SELECT]`** together for 1 second. |

---

## 📄 Detailed Guide
For the complete technical breakdown, port monitoring mechanics, and core compatibility tips, see the **[NETPLAY_GUIDE.md](NETPLAY_GUIDE.md)**.

---

## 📜 License

Licensed under the [MIT License](LICENSE). Contributions, bug reports, and community testing are welcome!
