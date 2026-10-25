#!/bin/bash
# ==============================================================================
# Script: Start_Wired_Services.sh
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
C_RED="\033[1;31m"
C_WHITE="\033[1;37m"

# ------------------------------------------------------------------------------
# Helper: Start SSH deterministically (no races) and verify port 22 is listening
# ------------------------------------------------------------------------------
start_ssh_server() {
    # sshd privilege-separation dir: only created by systemd's ssh.service, so it
    # is missing on the first run after every boot (caused first-attempt failure)
    sudo mkdir -p /run/sshd 2>/dev/null
    sudo chmod 755 /run/sshd 2>/dev/null

    # Stop every other owner of port 22 first (service, socket activation, strays)
    sudo systemctl stop ssh.socket 2>/dev/null
    sudo systemctl stop ssh 2>/dev/null
    sudo killall -9 sshd 2>/dev/null
    sleep 0.5

    # Single, sequential start (sshd daemonizes itself, no background race)
    sudo /usr/sbin/sshd 2>/dev/null

    # Wait up to ~6s for port 22 to really accept connections
    SSH_OK=0
    for _i in 1 2 3 4 5 6 7 8 9 10 11 12; do
        if (exec 3<>/dev/tcp/127.0.0.1/22) 2>/dev/null; then
            SSH_OK=1
            break
        fi
        sleep 0.5
    done

    # Fallback: let systemd start it (blocking) if the direct start failed
    if [ "$SSH_OK" -ne 1 ]; then
        sudo systemctl start ssh 2>/dev/null
        sleep 1
        (exec 3<>/dev/tcp/127.0.0.1/22) 2>/dev/null && SSH_OK=1
    fi
}

printf "\033c" 2>/dev/null
clear 2>/dev/null

echo -e "${C_CYAN}============================================${C_RESET}"
echo -e "${C_WHITE}   BATTLE XP G350 - STARTING SERVICES       ${C_RESET}"
echo -e "${C_CYAN}============================================${C_RESET}"

# Check Hardware Mode
IS_PERI=0
if [ -f /proc/device-tree/usb@ff300000/dr_mode ] && grep -aq "peripheral" /proc/device-tree/usb@ff300000/dr_mode 2>/dev/null; then
    IS_PERI=1
elif [ -f /sys/firmware/devicetree/base/usb@ff300000/dr_mode ] && grep -aq "peripheral" /sys/firmware/devicetree/base/usb@ff300000/dr_mode 2>/dev/null; then
    IS_PERI=1
fi

if [ "$IS_PERI" -eq 1 ]; then
    echo -e " Mode: ${C_GREEN}WIRED PC (Peripheral)${C_RESET} [READY]"
else
    echo -e " ${C_RED}[!] WARNING: Console is in USB HOST MODE!${C_RESET}"
    echo -e " Run 'Switch USB Mode' to switch to PC mode."
    echo -e " Returning to EmulationStation in 4s..."
    sleep 4
    clear 2>/dev/null
    exit 1
fi

echo -e "${C_YELLOW}[1/4] Setting up usb0 & IPs...${C_RESET}"
if ! lsmod | grep -q "g_ether"; then
    sudo modprobe g_ether 2>/dev/null
fi
sudo ip addr flush dev usb0 2>/dev/null
sudo ip addr add 192.168.7.2/24 dev usb0 2>/dev/null
sudo ip addr add 192.168.137.2/24 dev usb0 2>/dev/null
sudo ip link set usb0 up 2>/dev/null

# Wait up to ~6s for the PC to enumerate the gadget (carrier up)
for _i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    [ "$(cat /sys/class/net/usb0/carrier 2>/dev/null)" = "1" ] && break
    sleep 0.5
done

if ping -c 1 -W 1 192.168.137.1 >/dev/null 2>&1; then
    sudo ip route replace default via 192.168.137.1 dev usb0 2>/dev/null
    ACTIVE_IP="192.168.137.2"
    echo -e "      ${C_GREEN}-> Gateway: 192.168.137.1 (ICS Active)${C_RESET}"
else
    sudo ip route replace default via 192.168.7.1 dev usb0 2>/dev/null
    ACTIVE_IP="192.168.7.2"
    echo -e "      ${C_GREEN}-> Gateway: 192.168.7.1 (Direct PC)${C_RESET}"
fi

sudo rm -f /etc/resolv.conf 2>/dev/null
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

start_ssh_server
if [ "$SSH_OK" -eq 1 ]; then
    echo -e "      ${C_GREEN}-> SSH / SFTP Port 22 (ark/ark)${C_RESET}"
else
    echo -e "      ${C_RED}-> SSH FAILED to start! Press [A] again${C_RESET}"
fi

echo -e "${C_YELLOW}[3/4] Starting Samba Windows share...${C_RESET}"
sudo systemctl --no-block start smbd 2>/dev/null
echo -e "      ${C_GREEN}-> Samba active (\\\\${ACTIVE_IP}\\roms)${C_RESET}"

echo -e "${C_YELLOW}[4/4] Verifying connectivity...${C_RESET}"
if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
    echo -e "      ${C_GREEN}-> Internet: ONLINE (PortMaster Ready)${C_RESET}"
else
    echo -e "      ${C_YELLOW}-> Local Link: CONNECTED${C_RESET}"
fi

echo -e "${C_CYAN}============================================${C_RESET}"
echo -e "${C_WHITE} SERVICES LIVE! Returning in 2 seconds...   ${C_RESET}"
echo -e "${C_CYAN}============================================${C_RESET}"

sleep 2
printf "\033c" 2>/dev/null
clear 2>/dev/null
exit 0
