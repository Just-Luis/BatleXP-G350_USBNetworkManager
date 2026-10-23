#!/bin/bash
# ==============================================================================
# Script: USB_Network_Manager.sh
# Device: BatleXP G350 / RK3326 Handhelds (dArkOS / ArkOS)
# Layout: Tailored for 3.5" Handhelds (Max 44 cols x 16 rows, zero overflow)
# ==============================================================================

# Direct output to physical display if launched from EmulationStation
if [ -z "$SSH_CONNECTION" ]; then
    for tty in /dev/tty0 /dev/tty1; do
        if [ -e "$tty" ]; then
            sudo chmod 666 "$tty" 2>/dev/null
            exec > "$tty" 2>&1
            break
        fi
    done
fi

# Set clean console font if available
if [ -f /usr/share/consolefonts/Lat7-TerminusBold28x14.psf.gz ]; then
    sudo setfont /usr/share/consolefonts/Lat7-TerminusBold28x14.psf.gz 2>/dev/null
fi

# Source ArkOS gamepad button monitor
if [ -f /usr/local/bin/buttonmon.sh ]; then
    . /usr/local/bin/buttonmon.sh
fi

C_RESET="\033[0m"
C_CYAN="\033[1;36m"
C_GREEN="\033[1;32m"
C_YELLOW="\033[1;33m"
C_RED="\033[1;31m"
C_WHITE="\033[1;37m"
C_GRAY="\033[0;37m"

# ------------------------------------------------------------------------------
# Helper: Detect Current USB & Network Status
# ------------------------------------------------------------------------------
detect_status() {
    # 1. Detect Running Kernel Hardware Mode
    if [ -d /sys/class/udc ] && [ -n "$(ls -A /sys/class/udc 2>/dev/null)" ]; then
        RUN_MODE="peripheral"
    elif [ -f /proc/device-tree/usb@ff300000/dr_mode ] && grep -q "peripheral" /proc/device-tree/usb@ff300000/dr_mode 2>/dev/null; then
        RUN_MODE="peripheral"
    else
        RUN_MODE="host"
    fi

    # 2. Detect Configured Next Boot DTB Mode
    if [ -f /boot/rk3326-g350-peripheral.dtb ] && cmp -s /boot/rk3326-g350-linux.dtb /boot/rk3326-g350-peripheral.dtb; then
        BOOT_MODE="peripheral"
    elif [ -f /boot/rk3326-g350-host.dtb ] && cmp -s /boot/rk3326-g350-linux.dtb /boot/rk3326-g350-host.dtb; then
        BOOT_MODE="host"
    else
        BOOT_MODE="$RUN_MODE"
    fi

    # Format Status Mode (strictly <= 42 chars per line)
    if [ "$RUN_MODE" == "peripheral" ] && [ "$BOOT_MODE" == "peripheral" ]; then
        STATUS_MODE="${C_GREEN}WIRED PC (Peripheral)${C_RESET}"
        IS_PERIPHERAL=1
        SWITCH_TEXT="Switch to USB HOST Mode     [Reboots]"
        START_TEXT="${C_GREEN}[A]${C_RESET} ${C_WHITE}Start Services (SSH & Net)  [Instant]${C_RESET}"
    elif [ "$RUN_MODE" == "host" ] && [ "$BOOT_MODE" == "host" ]; then
        STATUS_MODE="${C_YELLOW}USB HOST (OTG Pendrives)${C_RESET}"
        IS_PERIPHERAL=0
        SWITCH_TEXT="Switch to WIRED PC Mode     [Reboots]"
        START_TEXT="${C_GRAY}[A] Start Services (Need PC Mode)${C_RESET}"
    elif [ "$RUN_MODE" == "peripheral" ] && [ "$BOOT_MODE" == "host" ]; then
        STATUS_MODE="${C_CYAN}WIRED PC ${C_RED}[REBOOT PENDING]${C_RESET}"
        IS_PERIPHERAL=1
        SWITCH_TEXT="Reboot into USB HOST Mode   [Reboots]"
        START_TEXT="${C_GREEN}[A]${C_RESET} ${C_WHITE}Start Services (Until reboot)[Instant]${C_RESET}"
    else
        STATUS_MODE="${C_CYAN}USB HOST ${C_GREEN}[REBOOT PENDING]${C_RESET}"
        IS_PERIPHERAL=0
        SWITCH_TEXT="Reboot into WIRED PC Mode   [Reboots]"
        START_TEXT="${C_GRAY}[A] Start Services (Restart first)${C_RESET}"
    fi

    # Check Active IPs (concise to prevent wrapping)
    STATUS_IP=$(ip -4 addr show dev usb0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1)
    if [ -z "$STATUS_IP" ]; then
        STATUS_IP="${C_GRAY}Disconnected${C_RESET}"
    else
        STATUS_IP="${C_GREEN}$STATUS_IP (usb0)${C_RESET}"
    fi

    # Check Default Gateway
    STATUS_GW=$(ip route 2>/dev/null | awk '/default/ {print $3}' | head -n 1)
    if [ -z "$STATUS_GW" ]; then
        STATUS_GW="${C_GRAY}None${C_RESET}"
    else
        STATUS_GW="${C_WHITE}$STATUS_GW (Online)${C_RESET}"
    fi

    # Check SSH Server
    if pgrep sshd >/dev/null 2>&1; then
        STATUS_SSH="${C_GREEN}Port 22 (ark/ark) [RUNNING]${C_RESET}"
    else
        STATUS_SSH="${C_RED}STOPPED${C_RESET}"
    fi

    # Check Samba Server
    if pgrep smbd >/dev/null 2>&1; then
        STATUS_SAMBA="${C_GREEN}\\\\192.168.137.2/roms [OK]${C_RESET}"
    else
        STATUS_SAMBA="${C_GRAY}INACTIVE${C_RESET}"
    fi

    # Check Internet Connectivity
    if ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1; then
        STATUS_NET="${C_GREEN}ONLINE (PortMaster Ready)${C_RESET}"
    else
        STATUS_NET="${C_GRAY}OFFLINE${C_RESET}"
    fi
}

# ------------------------------------------------------------------------------
# Helper: Draw Main Interactive Menu (strictly 14 rows, max 42 cols)
# ------------------------------------------------------------------------------
draw_menu() {
    printf "\033c" 2>/dev/null
    clear 2>/dev/null
    detect_status

    echo -e "${C_CYAN}==========================================${C_RESET}"
    echo -e "${C_WHITE}   BATLEXP G350 - USB NETWORK MANAGER     ${C_RESET}"
    echo -e "${C_CYAN}==========================================${C_RESET}"
    echo -e " ${C_WHITE}USB MODE :${C_RESET} $STATUS_MODE"
    echo -e " ${C_WHITE}IP ADDR  :${C_RESET} $STATUS_IP"
    echo -e " ${C_WHITE}GATEWAY  :${C_RESET} $STATUS_GW"
    echo -e " ${C_WHITE}SSH/SFTP :${C_RESET} $STATUS_SSH"
    echo -e " ${C_WHITE}SAMBA    :${C_RESET} $STATUS_SAMBA"
    echo -e " ${C_WHITE}INTERNET :${C_RESET} $STATUS_NET"
    echo -e "${C_CYAN}------------------------------------------${C_RESET}"
    echo -e " $START_TEXT"
    echo -e " ${C_RED}[Y]${C_RESET} ${C_WHITE}Stop Services (Save Battery)[Instant]${C_RESET}"
    echo -e " ${C_YELLOW}[X]${C_RESET} ${C_WHITE}$SWITCH_TEXT${C_RESET}"
    echo -e " ${C_CYAN}[B]${C_RESET} ${C_WHITE}Exit to EmulationStation${C_RESET}"
}

# ------------------------------------------------------------------------------
# Action [A]: Start Wired Services (Instant, No Reboot)
# ------------------------------------------------------------------------------
start_services() {
    printf "\033c" 2>/dev/null
    clear 2>/dev/null

    echo -e "${C_CYAN}============================================${C_RESET}"
    echo -e "${C_WHITE}   STARTING WIRED SERVICES (SSH & NET)...   ${C_RESET}"
    echo -e "${C_CYAN}============================================${C_RESET}"

    echo -e "${C_YELLOW}[1/4] Setting usb0 & IPs...${C_RESET}"
    if ! lsmod | grep -q "g_ether"; then
        sudo modprobe g_ether 2>/dev/null
    fi
    sudo ip addr flush dev usb0 2>/dev/null
    sudo ip addr add 192.168.7.2/24 dev usb0 2>/dev/null
    sudo ip addr add 192.168.137.2/24 dev usb0 2>/dev/null
    sudo ip link set usb0 up 2>/dev/null

    if ping -c 1 -W 1 192.168.137.1 >/dev/null 2>&1; then
        sudo ip route replace default via 192.168.137.1 dev usb0 2>/dev/null
        echo -e "      ${C_GREEN}-> Gateway: 192.168.137.1 (ICS Active)${C_RESET}"
    else
        sudo ip route replace default via 192.168.7.1 dev usb0 2>/dev/null
        echo -e "      ${C_GREEN}-> Gateway: 192.168.7.1 (Direct PC)${C_RESET}"
    fi

    echo -e "nameserver 1.1.1.1\nnameserver 8.8.8.8" | sudo tee /etc/resolv.conf >/dev/null

    echo -e "${C_YELLOW}[2/4] Starting fast OpenSSH server...${C_RESET}"
    for pamfile in /etc/pam.d/sshd /etc/pam.d/login /etc/pam.d/common-session; do
        if [ -f "$pamfile" ]; then
            sudo sed -i 's/.*pam_systemd.so/#&/' "$pamfile" 2>/dev/null
            sudo sed -i 's/.*pam_nologin.so/#&/' "$pamfile" 2>/dev/null
        fi
    done
    sudo rm -f /run/nologin /etc/nologin 2>/dev/null

    if [ -f /etc/ssh/sshd_config ]; then
        grep -q "^UsePAM" /etc/ssh/sshd_config && sudo sed -i 's/^UsePAM.*/UsePAM no/' /etc/ssh/sshd_config || echo "UsePAM no" | sudo tee -a /etc/ssh/sshd_config >/dev/null
        grep -q "Subsystem.*sftp" /etc/ssh/sshd_config && sudo sed -i 's/^#*Subsystem\s\+sftp.*/Subsystem sftp internal-sftp/' /etc/ssh/sshd_config || echo "Subsystem sftp internal-sftp" | sudo tee -a /etc/ssh/sshd_config >/dev/null
    fi

    sudo killall -9 sshd 2>/dev/null
    sleep 0.2
    sudo /usr/sbin/sshd 2>/dev/null &
    sudo systemctl --no-block restart ssh 2>/dev/null &
    echo -e "      ${C_GREEN}-> SSH / SFTP Port 22 (ark/ark)${C_RESET}"

    echo -e "${C_YELLOW}[3/4] Starting Samba file sharing...${C_RESET}"
    sudo systemctl --no-block start smbd 2>/dev/null
    echo -e "      ${C_GREEN}-> Samba: \\\\192.168.137.2\\roms${C_RESET}"

    echo -e "${C_YELLOW}[4/4] Verifying connection...${C_RESET}"
    if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
        echo -e "      ${C_GREEN}-> Internet: ONLINE (PortMaster Ready)${C_RESET}"
    else
        echo -e "      ${C_YELLOW}-> Local Link: CONNECTED${C_RESET}"
    fi

    echo -e "${C_CYAN}============================================${C_RESET}"
    echo -e "${C_WHITE} SERVICES LIVE! Returning in 2 seconds...   ${C_RESET}"
    echo -e "${C_CYAN}============================================${C_RESET}"
    sleep 2
}

# ------------------------------------------------------------------------------
# Action [Y]: Stop Wired Services (Instant, No Reboot)
# ------------------------------------------------------------------------------
stop_services() {
    printf "\033c" 2>/dev/null
    clear 2>/dev/null

    echo -e "${C_CYAN}============================================${C_RESET}"
    echo -e "${C_WHITE}   STOPPING WIRED SERVICES (BATTERY SAVER)  ${C_RESET}"
    echo -e "${C_CYAN}============================================${C_RESET}"

    echo -e "${C_YELLOW}[1/2] Stopping OpenSSH server...${C_RESET}"
    sudo killall -9 sshd 2>/dev/null
    sudo systemctl stop ssh 2>/dev/null
    echo -e "      ${C_GREEN}-> SSH server stopped.${C_RESET}"

    echo -e "${C_YELLOW}[2/2] Stopping Samba server...${C_RESET}"
    sudo systemctl stop smbd 2>/dev/null
    sudo killall -9 smbd 2>/dev/null
    echo -e "      ${C_GREEN}-> Samba server stopped.${C_RESET}"

    echo -e "${C_CYAN}============================================${C_RESET}"
    echo -e "${C_WHITE} SERVICES STOPPED! Returning in 2s...       ${C_RESET}"
    echo -e "${C_CYAN}============================================${C_RESET}"
    sleep 2
}

# ------------------------------------------------------------------------------
# Action [X]: Switch Hardware Mode (Peripheral <-> Host)
# ------------------------------------------------------------------------------
switch_hardware_mode() {
    printf "\033c" 2>/dev/null
    clear 2>/dev/null

    # Detect current DTB mode
    if [ -f /boot/rk3326-g350-peripheral.dtb ] && cmp -s /boot/rk3326-g350-linux.dtb /boot/rk3326-g350-peripheral.dtb; then
        TARGET="host"
    else
        TARGET="peripheral"
    fi

    echo -e "${C_CYAN}============================================${C_RESET}"
    if [ "$TARGET" == "host" ]; then
        echo -e "${C_YELLOW}   SWITCHING TO USB HOST (OTG) MODE...      ${C_RESET}"
    else
        echo -e "${C_GREEN}   SWITCHING TO WIRED PC MODE...            ${C_RESET}"
    fi
    echo -e "${C_CYAN}============================================${C_RESET}"

    if [ "$TARGET" == "host" ]; then
        echo -e "${C_YELLOW}[1/2] Applying Host OTG DTB to /boot...${C_RESET}"
        if [ -f /boot/rk3326-g350-host.dtb ]; then
            sudo cp /boot/rk3326-g350-host.dtb /boot/rk3326-g350-linux.dtb
            sync
            echo -e "      ${C_GREEN}-> Host DTB applied.${C_RESET}"
        fi
        echo -e "${C_YELLOW}[2/2] Stopping wired services...${C_RESET}"
        sudo killall -9 sshd 2>/dev/null
        sudo systemctl stop ssh 2>/dev/null
        sudo systemctl stop smbd 2>/dev/null
        echo -e "${C_CYAN}============================================${C_RESET}"
        echo -e "${C_WHITE} SWITCHED TO USB HOST MODE! (OTG)           ${C_RESET}"
        echo -e " Hardware reboot required to switch.        ${C_RESET}"
        echo -e " Press ${C_RED}[B]${C_RESET} to cancel, or wait 5 seconds... "
        echo -e "${C_CYAN}============================================${C_RESET}"
    else
        echo -e "${C_GREEN}[1/2] Applying Wired PC DTB to /boot...${C_RESET}"
        if [ -f /boot/rk3326-g350-peripheral.dtb ]; then
            sudo cp /boot/rk3326-g350-peripheral.dtb /boot/rk3326-g350-linux.dtb
            sync
            echo -e "      ${C_GREEN}-> Peripheral DTB applied.${C_RESET}"
        fi
        echo -e "${C_CYAN}============================================${C_RESET}"
        echo -e "${C_WHITE} SWITCHED TO WIRED PC MODE!                 ${C_RESET}"
        echo -e " Hardware reboot required to switch.        ${C_RESET}"
        echo -e " ${C_YELLOW}Run 'Start Services' after reboot!         ${C_RESET}"
        echo -e " Press ${C_RED}[B]${C_RESET} to cancel, or wait 5 seconds... "
        echo -e "${C_CYAN}============================================${C_RESET}"
    fi

    for i in 5 4 3 2 1; do
        echo -ne " Rebooting in $i seconds... (Press B to cancel)\r"
        if type Test_Button_B >/dev/null 2>&1; then
            Test_Button_B
            if [ "$?" -eq "10" ]; then
                echo -e "\n${C_YELLOW}Reboot canceled. Returning to menu...${C_RESET}"
                sleep 2
                return
            fi
        fi
        read -t 1 -n 1 key 2>/dev/null
        if [[ "$key" == "b" || "$key" == "B" || "$key" == "q" ]]; then
            echo -e "\n${C_YELLOW}Reboot canceled. Returning to menu...${C_RESET}"
            sleep 2
            return
        fi
    done

    echo -e "\n${C_GREEN}Rebooting now...${C_RESET}"
    sudo reboot
    exit 0
}

# ------------------------------------------------------------------------------
# Main Application Loop
# ------------------------------------------------------------------------------
while true; do
    draw_menu

    # Polling loop for Gamepad and Keyboard input
    while true; do
        # 1. Gamepad Input via ArkOS buttonmon
        if type Test_Button_A >/dev/null 2>&1; then
            Test_Button_A
            if [ "$?" -eq "10" ]; then
                start_services
                break
            fi

            Test_Button_Y
            if [ "$?" -eq "10" ]; then
                stop_services
                break
            fi

            Test_Button_X
            if [ "$?" -eq "10" ]; then
                switch_hardware_mode
                break
            fi

            Test_Button_B
            if [ "$?" -eq "10" ]; then
                printf "\033c" 2>/dev/null
                clear 2>/dev/null
                exit 0
            fi
        fi

        # 2. Keyboard / SSH / TTY Input
        read -t 0.1 -n 1 key 2>/dev/null
        case "$key" in
            1|[aA])
                start_services
                break
                ;;
            2|[yY])
                stop_services
                break
                ;;
            3|[xX])
                switch_hardware_mode
                break
                ;;
            4|[bB]|[qQ])
                printf "\033c" 2>/dev/null
                clear 2>/dev/null
                exit 0
                ;;
        esac

        sleep 0.05
    done
done
