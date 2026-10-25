# 🎮 Complete Guide: Direct USB Netplay for Battle XP G350 & RK3326 Handhelds

> **Step-by-step guide to setting up and playing 2-player wired RetroArch Netplay directly between two G350 (or RK3326 ArkOS/dArkOS) handhelds with sub-millisecond latency and zero Wi-Fi lag.**

---

## 📑 Table of Contents
1. [Core Architecture & Requirements](#1-core-architecture--requirements)
2. [Installing the Scripts on Both Consoles (Where to Put Them)](#2-installing-the-scripts-on-both-consoles-where-to-put-them)
3. [Why USB Network Manager is Mandatory](#3-why-usb-network-manager-is-mandatory)
4. [Physical Cable & Port Setup](#4-physical-cable--port-setup)
5. [Phase 1: Hardware Mode Setup (USB Network Manager)](#5-phase-1-hardware-mode-setup-usb-network-manager)
6. [Phase 2: Netplay Preparation (`C2C_Netplay_Prep.sh`)](#6-phase-2-netplay-preparation-c2c_netplay_prepsh)
7. [Phase 3: Launching the 2-Player Game in RetroArch](#7-phase-3-launching-the-2-player-game-in-retroarch)
8. [Phase 4: In-Game Verification & Netplay Controls](#8-phase-4-in-game-verification--netplay-controls)
9. [Troubleshooting Matrix](#9-troubleshooting-matrix)

---

## 1. Core Architecture & Requirements

Two handhelds connected directly together over USB communicate using an isolated, private wired subnet:

```
[ Console 1: PLAYER 1 ]                                [ Console 2: PLAYER 2 ]
+-------------------------+                           +-------------------------+
| Device Tree: HOST Mode  |=== USB OTG Data Cable ====| Device Tree: PERIPHERAL |
| Static IP: 192.168.10.1 |                           | Static IP: 192.168.10.2 |
| Port: OTG Port          |                           | Port: OTG Port          |
| RetroArch: Netplay Host |                           | RetroArch: Client (P2)  |
+-------------------------+                           +-------------------------+
```

### What You Need:
1. **Two G350 Handhelds** running ArkOS / dArkOS.
2. **One USB Connection Setup:**
   * **Recommended:** A **USB-C Male to USB-A Female OTG adapter** plugged into **Console 1** + a standard **USB-A to USB-C cable** plugged into **Console 2**.
   * **Alternative:** A bi-directional USB-C to USB-C cable that supports OTG Host mode.
3. **The Same Game & Core:**
   * Both consoles must launch the **exact same ROM file** (identical file and checksum).
   * Both consoles must use the **exact same emulator core** (e.g., Genesis Plus GX, Gambatte, Snes9x).

---

## 2. Installing the Script on Both Consoles (Where to Put It)

To use wired C2C Netplay, you only need **a single script** copied onto the MicroSD cards of **both consoles**:
* **[`C2C_Netplay_Prep.sh`](C2C_Netplay_Prep.sh):** The complete all-in-one Netplay initializer, first-launch role wizard, and diagnostic monitor.

*(Note: [`USB_Network_Manager.sh`](../USB_Network_Manager.sh) is only needed if you also want PC file transfers or Wi-Fi internet tethering; pure Netplay players only need `C2C_Netplay_Prep.sh`!)*

---

### 📁 Where to Put the File on Your SD Card

When you insert your console's MicroSD card (the ROMs / `EASYROMS` partition) into your computer, copy the script into the following location:

```text
EASYROMS/ (or roms/)
├── tools/                         <-- ⭐ STRONGLY RECOMMENDED LOCATION
│   └── C2C_Netplay_Prep.sh        (Appears under the "TOOLS" menu in EmulationStation)
└── ports/                         <-- Alternative location if your theme lacks a Tools menu
    └── C2C_Netplay_Prep.sh
```

> [!TIP]
> **Recommended Folder:** Paste `C2C_Netplay_Prep.sh` into the **`tools/`** folder.  
> When placed in `tools/`, it appears directly under the **TOOLS** system in EmulationStation (alongside *PortMaster* and *ThemeMaster*).  
> If your ArkOS theme does not show a Tools menu, paste it into the **`ports/`** folder instead (it will appear in the **PORTS** section).

---

### 💾 Step-by-Step Installation

#### Method A: Direct SD Card Copy (Easiest & Recommended)
1. Safely shut down **Console 1** (`Start` ➔ `Quit` ➔ `Shutdown System`).
2. Remove the MicroSD card and connect it to your PC.
3. Open the **`EASYROMS`** (or `roms`) partition in Windows File Explorer or Mac Finder.
4. Copy `C2C_Netplay_Prep.sh` into the **`tools/`** folder.
5. Safely eject the card, insert it back into Console 1, and turn it on.
6. **Repeat steps 1 through 5 for Console 2.**

#### Method B: Over the Network via SFTP (If already tethered to PC)
* Connect to `192.168.137.2` (port `22`, username `ark`, password `ark`) and transfer `C2C_Netplay_Prep.sh` into `/roms/tools/`.

---

## 3. The Golden Rule of Hardware Roles

The Rockchip RK3326 SoC inside the Battle XP G350 features **a single USB 2.0 OTG controller**. 

For two consoles to link directly over a USB cable:
* **Console 1 (Player 1 / Host):** MUST be set to **USB HOST Mode**.
* **Console 2 (Player 2 / Client):** MUST be set to **WIRED PC Mode (Peripheral)**.

> [!IMPORTANT]
> **You do NOT need external tools to configure this!**  
> `C2C_Netplay_Prep.sh` features a built-in **First-Launch Setup Wizard** and an embedded Device Tree generator. On first run, it will directly ask which console is Player 1 and which is Player 2, and automatically configure the hardware for you.

---

## 4. Physical Cable & Port Setup

USB-C port configurations vary across RK3326 handheld devices:
* **Battle XP G350:** Has a single USB-C port that handles **both OTG and DC** (power and data on the same port). Simply plug the cable directly into this port.
* **Dual-Port Handhelds (e.g., RG351P/M/V, RGB20S, OGA):** Some handhelds feature two separate USB-C ports:
  * **`OTG` Port:** Data + Power (Networking, controllers, USB storage).
  * **`DC` Port:** Power only (Charge only; data pins are physically disconnected).
  * *On dual-port handhelds, always connect to the `OTG` port.* Plugging into a charge-only `DC` port will show `CABLE LINK: NO LINK`.

> [!CAUTION]
> ### ⚠️ Risk of Battery Damage with Direct USB-C to USB-C Cables
> Connecting two handhelds directly with a standard **USB-C to USB-C cable** is **strongly discouraged**:
> * If not properly negotiated by both devices, both consoles may attempt to supply 5V power to each other over VBUS at the same time, which **can permanently damage the battery, charging IC, or motherboard**.
> * Furthermore, because many RK3326 handheld boards omit CC pull-down resistors, a standard C-to-C cable **most likely will not work at all** (stuck at `NO LINK`).
> * **⭐ The Best & Safest Option:** Always use a **USB-A to USB-C cable** connected to a **USB-C Male to USB-A Female OTG adapter** on **Console 1 (Host)**. This mechanically locks the power and data flow in one direction and safely prevents reverse voltage or battery damage.

### Cable Setup:
* **Best Option:** A **USB-C Male to USB-A Female OTG adapter** plugged into **Console 1 (Host)** + a standard **USB-A to USB-C cable** plugged into **Console 2 (Client)**.
* **Avoid:** Direct C-to-C cables unless certified with explicit one-way OTG host switching.

---

## 5. Phase 1: First-Launch Setup Wizard (Automatic Role Assignment)

You only need to do this step **once** when first launching the tool.

Launch **`C2C Netplay Prep`** (`C2C_Netplay_Prep.sh`) from **TOOLS** on **both consoles**.

### What you will see on First Launch:
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

### Action for Each Console:
1. **On Console 1 (Player 1 / Host):**
   * Press **`[A]`** *(PLAYER 1)*.
   * Factory handhelds already default physically to Host mode, so **no reboot is required!**
   * Console 1 immediately enters the active Netplay dashboard.
2. **On Console 2 (Player 2 / Client):**
   * Press **`[X]`** *(PLAYER 2)*.
   * The script automatically generates the Peripheral Device Tree profile and safely reboots the console in 3 seconds.
   * After reboot, launch **`C2C Netplay Prep`** again. It will automatically load as **Player 2** without asking again!

> [!TIP]
> **Need to switch roles later?**  
> On the main Netplay dashboard, you can simply press **`[X]`** anytime to switch roles (`[X] Make P2` or `[X] Make P1`).

---

## 6. Phase 2: Live Connection & Port Monitoring

Now connect your USB cable (with OTG Host adapter on Console 1). Both consoles should be running **`C2C Netplay Prep`**.

### What the Prep Script Does Automatically:
1. **Assigns Static IPs:**
   * Console 1 (Host) gets `192.168.10.1`.
   * Console 2 (Client) gets `192.168.10.2`.
2. **Claims Interface & Eliminates Conflicts:**
   * Kills background DHCP clients and Avahi daemons that assign `169.254.x.x` link-local addresses.
   * Disables reverse-path filtering (`rp_filter = 0`).
3. **Patches All RetroArch Configs (`retroarch.cfg`, `retroarch32.cfg`):**
   * Sets `netplay_use_relay_server = "false"` *(Fixes "Failed to initialize network")*.
   * Sets `netplay_nat_traversal = "false"` *(Stops offline UPnP search timeouts)*.
   * Sets `netplay_public_announce = "false"`.
   * Sets `netplay_ip_port = "55435"`.
   * On Console 2, automatically pre-configures `netplay_ip_address = "192.168.10.1"`.
   * Restores `ark:ark` file permissions so RetroArch can save configurations on quit.

### Check the Screen on Both Consoles:
* **Console 1 Screen:**
  ```text
  LOCAL ROLE : [HOST] Player 1 (192.168.10.1)
  PEER ROLE  : [CLIENT] Player 2 (192.168.10.2)
  CABLE LINK : CONNECTED [CARRIER OK]
  PING TEST  : ONLINE [OK]
  ```
* **Console 2 Screen:**
  ```text
  LOCAL ROLE : [CLIENT] Player 2 (192.168.10.2)
  PEER ROLE  : [HOST] Player 1 (192.168.10.1)
  CABLE LINK : CONNECTED [CARRIER OK]
  PING TEST  : ONLINE [OK]
  ```

### Exiting the Tool:
Once you see `ONLINE [OK]`, **HOLD `[START + SELECT]`** together on both consoles to exit back to EmulationStation.
*(The network settings and RetroArch configuration remain active in memory and on disk!)*

> [!IMPORTANT]
> ### ⚠️ Do Not Disconnect the Cable or Restart the Consoles!
> * **Keep the USB cable connected:** Unplugging the cable drops the physical carrier and tears down the active `usb0` network link.
> * **Do not reboot either console:** System reboot resets transient IP configurations and routes.
> * **If the cable is accidentally disconnected or a console restarts**, you must plug it back in and run **`C2C_Netplay_Prep.sh`** again on both consoles before launching Netplay.

---

## 7. Phase 3: Launching the 2-Player Game in RetroArch

Follow this exact sequence to ensure the host port is open before the client connects:

### Step 1: Start the Game on Console 1 (Host / Player 1)
1. In EmulationStation, launch the 2-player game (e.g. *Street Fighter II*, *Mario Kart*, *Contra*).
2. Once the game reaches the title screen, open the RetroArch Quick Menu by pressing:
   $$\text{[Select]} + \text{[X]}$$
3. Navigate down to **`Netplay`** and select it.
4. Navigate to **`Host`** and select **`Start Netplay Host`**.
5. RetroArch will display an on-screen yellow message:
   > *"Waiting for client..."* or *"You have joined as Player 1"*
6. Select **`Resume`** to go back into the game. Console 1 is now listening on port `55435`.

---

### Step 2: Join the Game on Console 2 (Client / Player 2)
1. In EmulationStation, launch the **exact same game with the exact same emulator core**.
2. Once the game reaches the title screen, open the RetroArch Quick Menu by pressing:
   $$\text{[Select]} + \text{[X]}$$
3. Navigate down to **`Netplay`** and select it.
4. Select **`Connect to Netplay Host`**.
   *(No IP entry is required—`C2C_Netplay_Prep.sh` already pre-configured `192.168.10.1`!)*
5. RetroArch will immediately connect over the USB cable and display:
   > *"Player 2 connected"*
6. Select **`Resume`**! Both consoles are now synchronized in real-time. Player 2 controls Controller 2.

---

## 8. Phase 4: In-Game Verification & Netplay Controls

* **Latency Check:** Because this connection runs over physical USB Ethernet, latency is sub-millisecond ($< 0.5\text{ ms}$). There is zero frame delay or Wi-Fi packet drops.
* **Pausing / Menu:** If either player opens the RetroArch Quick Menu (`[Select] + [X]`), Netplay pauses execution on both screens to keep emulation deterministic.
* **Saving States:** Only Player 1 (Host) controls save states during active Netplay.
* **Ending the Session:** 
  * Either player can press `[Select] + [X]` ➔ **Netplay** ➔ **`Disconnect from Netplay Host`** to leave without crashing the game.
  * Or simply exit the game normally using your standard ArkOS exit combo (`[Select] + [Start]` twice).

---

## 9. Troubleshooting Matrix

| Problem | Cause | Solution |
| :--- | :--- | :--- |
| **`"Failed to initialize network"`** | RetroArch tried to use the internet Relay Server or NAT Traversal while offline. | Run `C2C_Netplay_Prep.sh` on both consoles to disable relay servers and NAT traversal in `retroarch.cfg`. |
| **Client says `"Netplay host not found"`** | Host had not yet pressed `Start Netplay Host` when Client tried to connect. | Make sure Player 1 starts the Netplay Host **first**, then Player 2 connects. |
| **Console shows IP `169.254.x.x`** | A background network daemon overwrote the static C2C IP address. | Run `C2C_Netplay_Prep.sh` and press `[A]` (Retest). The script will automatically delete `169.254.x.x` and re-assert `192.168.10.x`. |
| **`CABLE LINK: NO LINK`** | 1. On dual-port consoles, cable is in the charge-only (`DC`) port.<br>2. Both consoles are in Host mode or both in Peripheral mode. | 1. Ensure dual-port handhelds use the `OTG` port (G350 has a single combined port).<br>2. Verify in `USB_Network_Manager.sh` that one console is Host and one is Peripheral. |
| **Game desyncs or freezes immediately** | 1. ROM file hash mismatch.<br>2. Different emulator cores used.<br>3. Savestate or cheat enabled. | Ensure both consoles use identical ROM dumps from the same source, the same emulator core (check EmulationStation core settings), and disable all cheats. |
| **Cannot exit `C2C_Netplay_Prep.sh`** | Single buttons like `[B]` do not exit to prevent accidental drops. | Firmly hold **`[START + SELECT]`** simultaneously for 1 second. |
| **Switching modes did not change USB status** | Hardware mode requires a full reboot to reload the kernel Device Tree (`.dtb`). | When pressing `[X]` in `USB_Network_Manager.sh`, wait for the 5-second countdown to finish and let the console reboot completely. |
