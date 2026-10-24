#!/bin/bash
# ==============================================================================
# Script: Stop_Wired_Services.sh
# Device: Battle XP G350 / RK3326 Handhelds (dArkOS / ArkOS)
# Layout: Tailored for 3.5" Handhelds (Max 44 cols x 16 rows, zero overflow)
# ==============================================================================

# Output directly to physical display if launched from EmulationStation
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

C_RESET="\033[0m"
C_CYAN="\033[1;36m"
C_GREEN="\033[1;32m"
C_YELLOW="\033[1;33m"
C_WHITE="\033[1;37m"

printf "\033c" 2>/dev/null
clear 2>/dev/null

echo -e "${C_CYAN}============================================${C_RESET}"
echo -e "${C_WHITE}   BATTLE XP G350 - STOPPING SERVICES       ${C_RESET}"
echo -e "${C_CYAN}============================================${C_RESET}"

echo -e "${C_YELLOW}[1/3] Stopping OpenSSH server...${C_RESET}"
sudo systemctl stop ssh.socket 2>/dev/null
sudo systemctl stop ssh 2>/dev/null
sudo killall -9 sshd 2>/dev/null
echo -e "      ${C_GREEN}-> SSH server stopped.${C_RESET}"

echo -e "${C_YELLOW}[2/3] Stopping Samba server...${C_RESET}"
sudo systemctl stop smbd 2>/dev/null
sudo killall -9 smbd 2>/dev/null
echo -e "      ${C_GREEN}-> Samba server stopped.${C_RESET}"

echo -e "${C_YELLOW}[3/3] Shutting down USB network...${C_RESET}"
sudo ip route del default dev usb0 2>/dev/null
sudo ip addr flush dev usb0 2>/dev/null
sudo ip link set usb0 down 2>/dev/null
sudo modprobe -r g_ether 2>/dev/null
echo -e "      ${C_GREEN}-> usb0 down, gadget unloaded.${C_RESET}"

echo -e "${C_CYAN}============================================${C_RESET}"
echo -e "${C_WHITE} SERVICES STOPPED! Battery saved.           ${C_RESET}"
echo -e "${C_CYAN}============================================${C_RESET}"

sleep 2
printf "\033c" 2>/dev/null
clear 2>/dev/null
exit 0
