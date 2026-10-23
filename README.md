# 🎮 BatleXP G350 USB Network Manager

> **Direct USB wired tethering, PortMaster downloads, high-speed SFTP transfers, and Samba file sharing for the BatleXP G350 and Rockchip RK3326 handhelds running ArkOS / dArkOS.**

[![Platform](https://img.shields.io/badge/Platform-Rockchip%20RK3326-blue.svg)](https://en.wikipedia.org/wiki/Rockchip)
[![OS](https://img.shields.io/badge/OS-dArkOS%20%2F%20ArkOS-red.svg)](https://github.com/christianhaitian/arkos)
[![Interface](https://img.shields.io/badge/UI-3.5%22%20Gamepad%20Calibrated-green.svg)](https://github.com)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Tested On](https://img.shields.io/badge/Tested%20Device-BatleXP%20G350-purple.svg)](https://github.com)

---

### 📋 GitHub Repository Setup (For Maintainers)
If you are publishing or cloning this repository, here is the recommended metadata:
* **Repository Name:** `BatleXP-G350-USB-Network-Manager`
* **Short Description (About box):**  
  `Direct USB PC tethering, PortMaster internet access, high-speed SFTP/Samba transfers, and hardware USB mode switcher for BatleXP G350 (RK3326) on ArkOS.`
* **Topics / Tags:**  
  `arkos`, `rk3326`, `batlexp-g350`, `portmaster`, `retro-handheld`, `rndis`, `usb-ethernet`, `sftp`, `retrogaming`, `emulationstation`

---

## 💡 Why This Project?

The **BatleXP G350** is an incredible budget retro gaming handheld powered by the Rockchip RK3326 SoC, but it suffers from one major limitation: **it has no internal Wi-Fi chip**.

Traditionally, this forced owners to:
* 🛑 **Repeatedly remove the MicroSD card** to add games, risking card corruption and wearing out the spring-loaded slot.
* 🛑 **Carry bulky external Wi-Fi dongles** and OTG adapters that drain battery and protrude awkwardly.
* 🛑 **Miss out on PortMaster**, box-art scraping, and RetroArch core updates due to lack of network connectivity.

**USB Network Manager** solves this completely. By converting the console's physical USB-C port into a bidirectional USB Ethernet network gadget, you get:
* 🌐 **Full Internet on your Handheld** via your PC's Wi-Fi connection (Windows Internet Sharing).
* ⚡ **Blazing Fast Game Transfers** up to 25–35 MB/s via SFTP (WinSCP, FileZilla) and Windows File Explorer (`\\192.168.137.2\roms`).
* 🕹️ **Zero Clutter:** A single, self-contained interactive script (`USB_Network_Manager.sh`) driven entirely by your console's gamepad.

---

## 🌟 Key Features

* 🚀 **PortMaster Without Wi-Fi:** Download, install, and update native ports (*Celeste, Stardew Valley, TMNT, Half-Life*, etc.) directly on your handheld.
* 🖼️ **Box-Art & Metadata Scraping:** Scrape covers, screenshots, and descriptions directly inside EmulationStation.
* 📁 **Windows File Explorer Integration:** Drag and drop ROMs directly into `\\192.168.137.2\roms` as if it were a local network drive.
* 🔒 **Instant-Login OpenSSH Server:** Custom PAM and entropy patches eliminate the 15-second SSH hangs common on RK3326 devices.
* 📺 **Tailored 3.5" Handheld Layout:** Strictly formatted for 42 columns × 14 lines with 3 lines of safety headroom—no text wrapping, no top header cutoff.
* 🔄 **Hardware Mode Switcher:** Toggle between **Wired PC (Peripheral)** and **USB Host (OTG)** mode on the fly to support USB flash drives and external gamepads.
* 🔋 **Battery-Friendly:** Network services only run on-demand when you explicitly press `[A]`. Offline gaming consumes zero background power.

---

## 🕹️ The Handheld Dashboard

Launch **`USB Network Manager`** from **TOOLS** (or **PORTS**) on your console:

```text
==========================================
   BATLEXP G350 - USB NETWORK MANAGER     
==========================================
 USB MODE : WIRED PC (Peripheral)
 IP ADDR  : 192.168.137.2 (usb0)
 GATEWAY  : 192.168.137.1 (Online)
 SSH/SFTP : Port 22 (ark/ark) [RUNNING]
 SAMBA    : \\192.168.137.2\roms [OK]
 INTERNET : ONLINE (PortMaster Ready)
------------------------------------------
 [A] Start Services (SSH & Net)  [Instant]
 [Y] Stop Services (Save Battery)[Instant]
 [X] Switch to USB HOST Mode     [Reboots]
 [B] Exit to EmulationStation
```

### Gamepad Controls:

| Button | Function | Execution | Description |
| :---: | :--- | :---: | :--- |
| **[A]** | **Start Services** | Instant (~2s) | Binds IPs, sets gateway, and launches OpenSSH & Samba. |
| **[Y]** | **Stop Services** | Instant (~1s) | Turns off background daemons to conserve battery during gaming. |
| **[X]** | **Switch USB Mode** | Reboots (5s) | Toggles physical hardware between Wired PC and USB Host (OTG). |
| **[B]** | **Exit** | Instant | Returns cleanly to EmulationStation. |

---

## ⚡ Quick Start Guide (3 Simple Steps)

### Step 1: Copy the Script to Your Console First!
> [!IMPORTANT]
> `USB_Network_Manager.sh` is **100% self-contained**. You only need this single file!

1. Shut down your console safely (`Start` -> `Quit` -> `Shutdown`).
2. Insert your MicroSD card (the ROMs/Game card) into your PC.
3. Open the **`EASYROMS`** (or `roms`) partition in File Explorer.
4. Copy **`USB_Network_Manager.sh`** and paste it into:
   * **`tools/` (⭐ STRONGLY RECOMMENDED):** Appears under **TOOLS** alongside PortMaster and ThemeMaster.
   * **`ports/` (Alternative):** Appears under **PORTS** alongside port games.
5. Reinsert the card into your console and turn it on.

---

### Step 2: Connect Cable & Start Services on Handheld
> [!WARNING]
> **Use a USB-A to USB-C cable!** Avoid USB-C to USB-C cables as budget handhelds lack CC pull-down resistors.

1. Connect the USB cable between your PC and the console's **OTG / DC** port.
2. On your console, navigate to **TOOLS** (or **PORTS**) and launch **`USB Network Manager`**.
3. Verify **`USB MODE`**:
   * If it says **`WIRED PC (Peripheral)`**, proceed.
   * If it says **`USB HOST`**, press **`[X]`** to switch and let the console reboot.
4. Press **`[A]`** (*Start Services*). In 2 seconds, the virtual USB Ethernet adapter will initialize!

---

### Step 3: Enable Windows Internet Connection Sharing (One-Time)

1. On your Windows PC, press `Win + R`, type `ncpa.cpl`, and press **Enter**.
2. Locate your active **Wi-Fi** adapter and the newly created console adapter (typically **`Ethernet 2`** / *Remote NDIS Compatible Device*).
3. Right-click your **Wi-Fi** adapter -> Select **Properties** -> **Sharing** tab.
4. Check **"Allow other network users to connect through this computer's Internet connection"**.
5. Select your console's adapter (**`Ethernet 2`**) from the dropdown and click **OK**.
6. Check your console screen: **`GATEWAY`** will show `192.168.137.1 (Online)` and **`INTERNET`** will say `ONLINE (PortMaster Ready)`!

---

## ⚠️ Important Pro-Tips & Workarounds

> [!CAUTION]
> **Internet Sharing vs. Direct File Transfers (SFTP / SSH):**  
> When transferring files, **Windows cannot be sharing Wi-Fi**, otherwise SSH will fail to connect with the console.  
> * **When downloading on console (PortMaster / Scraper / Updates):** Wi-Fi sharing should be **ON** in `ncpa.cpl`.  
> * **When transferring ROMs via WinSCP / FileZilla / SSH:** Wi-Fi sharing must be **OFF** (uncheck sharing in `ncpa.cpl`).  
> *(We are investigating a permanent fix to allow both simultaneous internet sharing and direct file transfers in an upcoming update).*

---

## 📁 Repository Contents

| File | Purpose |
| :--- | :--- |
| **[`USB_Network_Manager.sh`](USB_Network_Manager.sh)** | **The main console tool.** Single self-contained script to paste into `tools/` or `ports/`. |
| **[`COMMUNITY_TUTORIAL.md`](COMMUNITY_TUTORIAL.md)** | **Complete Community Guide.** In-depth tutorial with detailed walkthroughs, diagrams, and FAQs. |
| **[`PROJECT_DOCUMENTATION.md`](PROJECT_DOCUMENTATION.md)** | **Deep Technical Architecture.** Kernel DTB patcher, PAM patches, and low-level specifications. |
| **[`Test_Internet_On_G350.bat`](Test_Internet_On_G350.bat)** | 1-Click Windows batch tool to test physical link, remote ping (8.8.8.8), and DNS resolution. |
| **[`Test_Internet_On_G350.ps1`](Test_Internet_On_G350.ps1)** | Native PowerShell diagnostic utility for Internet connection testing. |
| **[`Test_Connection_G350.bat`](Test_Connection_G350.bat)** | 1-Click Windows batch script to test local USB connection and SSH port 22 response. |
| **[`Test_Connection_G350.ps1`](Test_Connection_G350.ps1)** | Native PowerShell SSH connectivity tester. |
| **[`.usb_network/`](.usb_network/)** | *(Optional)* Standalone modular sub-scripts for advanced users running headless commands over SSH. |

---

## 🖥️ Connecting from PC (Credentials & Paths)

* **SFTP / SSH Connection:**
  * **Host:** `192.168.137.2` *(or `192.168.7.2`)*
  * **Port:** `22`
  * **Username:** `ark`
  * **Password:** `ark`
  * **ROMs Directory:** `/roms/`
* **Windows File Explorer (Samba):**
  * Type `\\192.168.137.2\roms` in the File Explorer address bar.

---

## 🛠️ Hardware & OS Compatibility

* **Primary Target:** BatleXP G350 (Rockchip RK3326) running dArkOS / ArkOS.
* **Compatible Devices:** Other RK3326-based handhelds running ArkOS (e.g. Anbernic RG351P/M/V, Powkiddy RGB20S, RK2020) with single USB-C OTG ports.

---

## 📖 In-Depth Documentation

For the full, beginner-friendly community guide with screenshots and advanced troubleshooting, please see **[COMMUNITY_TUTORIAL.md](COMMUNITY_TUTORIAL.md)**.

---

## 📜 License & Acknowledgments

* Licensed under the [MIT License](LICENSE).
* Special thanks to the **ArkOS** development team, the **PortMaster** community, and all retro handheld enthusiasts pushing budget devices to their fullest potential!
