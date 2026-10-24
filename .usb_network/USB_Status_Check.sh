#!/bin/bash
# ==============================================================================
# Script: USB_Status_Check.sh
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

if [ -f /usr/share/consolefonts/Lat7-TerminusBold28x14.psf.gz ]; then
    sudo setfont /usr/share/consolefonts/Lat7-TerminusBold28x14.psf.gz 2>/dev/null
fi

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
# Helper: True only if something is really LISTENING on TCP port 22
# (more reliable than pgrep, which also matches leftover/zombie sshd children)
# ------------------------------------------------------------------------------
ssh_listening() {
    if command -v ss >/dev/null 2>&1; then
        ss -ltn 2>/dev/null | grep -qE '[:.]22[[:space:]]'
    else
        (exec 3<>/dev/tcp/127.0.0.1/22) 2>/dev/null
    fi
}

printf "\033c" 2>/dev/null
clear 2>/dev/null

if [ -d /sys/class/udc ] && [ -n "$(ls -A /sys/class/udc 2>/dev/null)" ]; then
    RUN_MODE="peripheral"
else
    RUN_MODE="host"
fi

if [ -f /boot/rk3326-g350-peripheral.dtb ] && cmp -s /boot/rk3326-g350-linux.dtb /boot/rk3326-g350-peripheral.dtb; then
    BOOT_MODE="peripheral"
elif [ -f /boot/rk3326-g350-host.dtb ] && cmp -s /boot/rk3326-g350-linux.dtb /boot/rk3326-g350-host.dtb; then
    BOOT_MODE="host"
else
    BOOT_MODE="$RUN_MODE"
fi

if [ "$RUN_MODE" == "peripheral" ] && [ "$BOOT_MODE" == "peripheral" ]; then
    MODE_STR="${C_GREEN}WIRED PC (Peripheral)${C_RESET}"
elif [ "$RUN_MODE" == "host" ] && [ "$BOOT_MODE" == "host" ]; then
    MODE_STR="${C_YELLOW}USB HOST (OTG Pendrives)${C_RESET}"
elif [ "$RUN_MODE" == "peripheral" ] && [ "$BOOT_MODE" == "host" ]; then
    MODE_STR="${C_CYAN}WIRED PC ${C_RED}[REBOOT PENDING]${C_RESET}"
else
    MODE_STR="${C_CYAN}USB HOST ${C_GREEN}[REBOOT PENDING]${C_RESET}"
fi

RAW_GW=$(ip route 2>/dev/null | awk '/default/ {print $3}' | head -n 1)
ALL_IPS=$(ip -4 addr show dev usb0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')

if [ "$RAW_GW" == "192.168.137.1" ] && echo "$ALL_IPS" | grep -q "^192.168.137.2$"; then
    ACTIVE_IP="192.168.137.2"
elif [ "$RAW_GW" == "192.168.7.1" ] && echo "$ALL_IPS" | grep -q "^192.168.7.2$"; then
    ACTIVE_IP="192.168.7.2"
else
    ACTIVE_IP=$(echo "$ALL_IPS" | head -n 1)
fi

[ -z "$ACTIVE_IP" ] && IP_USB0="${C_GRAY}Disconnected${C_RESET}" || IP_USB0="${C_GREEN}$ACTIVE_IP (usb0)${C_RESET}"
[ -z "$RAW_GW" ] && GW="${C_GRAY}None${C_RESET}" || GW="${C_WHITE}$RAW_GW (Online)${C_RESET}"

if ssh_listening; then
    SSH_STATUS="${C_GREEN}Port 22 (ark/ark) [RUNNING]${C_RESET}"
else
    SSH_STATUS="${C_RED}STOPPED${C_RESET}"
fi

if pgrep smbd >/dev/null 2>&1; then
    SAMBA_IP="${ACTIVE_IP:-192.168.7.2}"
    SAMBA_STATUS="${C_GREEN}\\\\${SAMBA_IP}\\roms [OK]${C_RESET}"
else
    SAMBA_STATUS="${C_GRAY}INACTIVE${C_RESET}"
fi

if ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1; then
    NET_STATUS="${C_GREEN}ONLINE (PortMaster Ready)${C_RESET}"
else
    NET_STATUS="${C_GRAY}OFFLINE${C_RESET}"
fi

echo -e "${C_CYAN}============================================${C_RESET}"
echo -e "${C_WHITE}    BATLEXP G350 - USB STATUS CHECK         ${C_RESET}"
echo -e "${C_CYAN}============================================${C_RESET}"
echo -e " ${C_WHITE}USB MODE :${C_RESET} $MODE_STR"
echo -e "${C_CYAN}--------------------------------------------${C_RESET}"
echo -e " ${C_WHITE}IP ADDR  :${C_RESET} $IP_USB0"
echo -e " ${C_WHITE}GATEWAY  :${C_RESET} $GW"
echo -e " ${C_WHITE}SSH/SFTP :${C_RESET} $SSH_STATUS"
echo -e " ${C_WHITE}SAMBA    :${C_RESET} $SAMBA_STATUS"
echo -e " ${C_WHITE}INTERNET :${C_RESET} $NET_STATUS"
echo -e "${C_CYAN}============================================${C_RESET}"
echo -e " ${C_GRAY}Press [B] or any key to exit (or wait 8s)${C_RESET}"

for i in $(seq 8 -1 1); do
    if type Test_Button_B >/dev/null 2>&1; then
        Test_Button_B; [ "$?" -eq "10" ] && break
        Test_Button_A; [ "$?" -eq "10" ] && break
    fi
    read -t 1 -n 1 key 2>/dev/null
    if [ -n "$key" ]; then break; fi
done

printf "\033c" 2>/dev/null
clear 2>/dev/null
exit 0
