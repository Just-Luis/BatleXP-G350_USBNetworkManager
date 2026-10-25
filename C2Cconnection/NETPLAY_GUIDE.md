# 🎮 Complete Guide: Direct USB Netplay for Battle XP G350 & RK3326 Handhelds

> **Step-by-step guide to setting up and playing 2-player wired RetroArch Netplay directly between two G350 (or RK3326 ArkOS/dArkOS) handhelds with sub-millisecond latency and zero Wi-Fi lag.**

---

## 📑 Table of Contents
1. [Core Architecture & Requirements](#1-core-architecture--requirements)
2. [Why USB Network Manager is Mandatory](#2-why-usb-network-manager-is-mandatory)
3. [Physical Cable & Port Setup](#3-physical-cable--port-setup)
4. [Phase 1: Hardware Mode Setup (USB Network Manager)](#phase-1-hardware-mode-setup-usb-network-manager)
5. [Phase 2: Netplay Preparation (`C2C_Netplay_Prep.sh`)](#phase-2-netplay-preparation-c2c_netplay_prepsh)
6. [Phase 3: Launching the 2-Player Game in RetroArch](#phase-3-launching-the-2-player-game-in-retroarch)
7. [Phase 4: In-Game Verification & Netplay Controls](#phase-4-in-game-verification--netplay-controls)
8. [Troubleshooting Matrix](#troubleshooting-matrix)

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

## 2. Why USB Network Manager is Mandatory

The Rockchip RK3326 SoC inside the Battle XP G350 features **a single USB 2.0 OTG controller**. 

By default from the factory:
* Handhelds run in **USB Host Mode** (`dr_mode = "host"`), designed for external USB drives, keyboards, or Wi-Fi dongles.
* If two consoles are connected together while **both** are in Host mode, neither acts as a USB device (gadget). No `usb0` network interface is created, and no communication can occur.
* Conversely, if both were in Peripheral mode, neither would power the bus or initialize the link.

> [!IMPORTANT]
> **The Golden Rule of Console-to-Console (C2C):**
> * **Console 1 (Player 1 / Host):** MUST be set to **USB HOST Mode**.
> * **Console 2 (Player 2 / Client):** MUST be set to **WIRED PC Mode (Peripheral)**.
> 
> You use **`USB_Network_Manager.sh`** on each console to switch and lock in these hardware modes.

---

## 3. Physical Cable & Port Setup

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

## 4. Phase 1: Hardware Mode Setup (USB Network Manager)

You only need to do this step once (or whenever switching roles).

### On Console 1 (Player 1 - Host):
1. In EmulationStation, go to **TOOLS** (or **PORTS**).
2. Launch **`USB Network Manager`** (`USB_Network_Manager.sh`).
3. Look at the **`USB MODE`** line:
   * If it says **`USB HOST (OTG Pendrives)`**: It is already in Host mode! Press **`[B]`** to exit.
   * If it says **`WIRED PC (Peripheral)`**: Press **`[X]`** (*Switch to USB HOST Mode*). Allow the console to reboot.
4. After rebooting, Console 1 is now permanently configured as **USB Host**.

### On Console 2 (Player 2 - Peripheral / Client):
1. In EmulationStation, launch **`USB Network Manager`**.
2. Look at the **`USB MODE`** line:
   * If it says **`WIRED PC (Peripheral)`**: It is already in Peripheral mode! Press **`[B]`** to exit.
   * If it says **`USB HOST`**: Press **`[X]`** (*Switch to WIRED PC Mode*). Allow the console to reboot.
3. After rebooting, Console 2 is now permanently configured as **Peripheral**.

> [!NOTE]
> You **do NOT** need to press `[A]` (Start Services) inside USB Network Manager for Netplay. 
> `C2C_Netplay_Prep.sh` will automatically configure and claim the network interface specifically for Netplay.

---

## 5. Phase 2: Netplay Preparation (`C2C_Netplay_Prep.sh`)

Once the hardware modes are set, connect the USB cable between both consoles' `OTG` ports.

Launch **`C2C Netplay Prep`** (`C2C_Netplay_Prep.sh`) from **TOOLS** on **both consoles**.

### What the Prep Script Does Automatically:
1. **Assigns Static IPs:**
   * Console 1 (Host) gets `192.168.10.1`.
   * Console 2 (Peripheral) gets `192.168.10.2`.
2. **Claims Interface & Eliminates Conflicts:**
   * Kills background DHCP clients and Avahi daemons that assign `169.254.x.x` link-local addresses.
   * Disables reverse-path filtering (`rp_filter = 0`).
3. **Patches All RetroArch Configs (`retroarch.cfg`, `retroarch32.cfg`):**
   * Sets `netplay_use_relay_server = "false"` *(Fixes "Failed to initialize network")*.
   * Sets `netplay_nat_traversal = "false"` *(Stops offline UPnP search timeouts)*.
   * Sets `netplay_public_announce = "false"`.
   * Sets `netplay_ip_port = "55435"`.
   * On Console 2, automatically pre-configures `netplay_ip_address = "192.168.10.1"`.

### Check the Screen on Both Consoles:
* **Console 1 Screen:**
  ```text
  LOCAL ROLE : [HOST] (192.168.10.1)
  PEER ROLE  : [PERIPHERAL] (192.168.10.2)
  CABLE LINK : CONNECTED [CARRIER OK]
  PING TEST  : ONLINE [OK]
  ```
* **Console 2 Screen:**
  ```text
  LOCAL ROLE : [PERIPHERAL] (192.168.10.2)
  PEER ROLE  : [HOST] (192.168.10.1)
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

## 6. Phase 3: Launching the 2-Player Game in RetroArch

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

## 7. Phase 4: In-Game Verification & Netplay Controls

* **Latency Check:** Because this connection runs over physical USB Ethernet, latency is sub-millisecond ($< 0.5\text{ ms}$). There is zero frame delay or Wi-Fi packet drops.
* **Pausing / Menu:** If either player opens the RetroArch Quick Menu (`[Select] + [X]`), Netplay pauses execution on both screens to keep emulation deterministic.
* **Saving States:** Only Player 1 (Host) controls save states during active Netplay.
* **Ending the Session:** 
  * Either player can press `[Select] + [X]` ➔ **Netplay** ➔ **`Disconnect from Netplay Host`** to leave without crashing the game.
  * Or simply exit the game normally using your standard ArkOS exit combo (`[Select] + [Start]` twice).

---

## 8. Troubleshooting Matrix

| Problem | Cause | Solution |
| :--- | :--- | :--- |
| **`"Failed to initialize network"`** | RetroArch tried to use the internet Relay Server or NAT Traversal while offline. | Run `C2C_Netplay_Prep.sh` on both consoles to disable relay servers and NAT traversal in `retroarch.cfg`. |
| **Client says `"Netplay host not found"`** | Host had not yet pressed `Start Netplay Host` when Client tried to connect. | Make sure Player 1 starts the Netplay Host **first**, then Player 2 connects. |
| **Console shows IP `169.254.x.x`** | A background network daemon overwrote the static C2C IP address. | Run `C2C_Netplay_Prep.sh` and press `[A]` (Retest). The script will automatically delete `169.254.x.x` and re-assert `192.168.10.x`. |
| **`CABLE LINK: NO LINK`** | 1. On dual-port consoles, cable is in the charge-only (`DC`) port.<br>2. Both consoles are in Host mode or both in Peripheral mode. | 1. Ensure dual-port handhelds use the `OTG` port (G350 has a single combined port).<br>2. Verify in `USB_Network_Manager.sh` that one console is Host and one is Peripheral. |
| **Game desyncs or freezes immediately** | 1. ROM file hash mismatch.<br>2. Different emulator cores used.<br>3. Savestate or cheat enabled. | Ensure both consoles use identical ROM dumps from the same source, the same emulator core (check EmulationStation core settings), and disable all cheats. |
| **Cannot exit `C2C_Netplay_Prep.sh`** | Single buttons like `[B]` do not exit to prevent accidental drops. | Firmly hold **`[START + SELECT]`** simultaneously for 1 second. |
| **Switching modes did not change USB status** | Hardware mode requires a full reboot to reload the kernel Device Tree (`.dtb`). | When pressing `[X]` in `USB_Network_Manager.sh`, wait for the 5-second countdown to finish and let the console reboot completely. |
