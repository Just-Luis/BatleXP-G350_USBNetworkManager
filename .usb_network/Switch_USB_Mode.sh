#!/bin/bash
# ==============================================================================
# Script: Switch_USB_Mode.sh
# Device: BatleXP G350 / RK3326 Handhelds (dArkOS / ArkOS)
# Layout: Tailored for 3.5" Handhelds (Max 44 cols x 16 rows, zero overflow)
# ==============================================================================

# Output directly to physical handheld display if launched from EmulationStation
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

printf "\033c" 2>/dev/null
clear 2>/dev/null

echo -e "${C_CYAN}============================================${C_RESET}"
echo -e "${C_WHITE}    BATLEXP G350 - SWITCH USB MODE          ${C_RESET}"
echo -e "${C_CYAN}============================================${C_RESET}"

if [ -d /sys/class/udc ] && [ -n "$(ls -A /sys/class/udc 2>/dev/null)" ]; then
    RUN_MODE="${C_GREEN}WIRED PC (Peripheral)${C_RESET}"
else
    RUN_MODE="${C_YELLOW}USB HOST (OTG Pendrives)${C_RESET}"
fi

if [ -f /boot/rk3326-g350-peripheral.dtb ] && cmp -s /boot/rk3326-g350-linux.dtb /boot/rk3326-g350-peripheral.dtb; then
    CONFIG_MODE="${C_GREEN}WIRED PC (Peripheral)${C_RESET}"
elif [ -f /boot/rk3326-g350-host.dtb ] && cmp -s /boot/rk3326-g350-linux.dtb /boot/rk3326-g350-host.dtb; then
    CONFIG_MODE="${C_YELLOW}USB HOST (OTG Pendrives)${C_RESET}"
else
    CONFIG_MODE="${C_WHITE}Default / Custom${C_RESET}"
fi

echo -e " ${C_WHITE}ACTIVE MODE:${C_RESET} $RUN_MODE"
echo -e " ${C_WHITE}NEXT BOOT  :${C_RESET} $CONFIG_MODE"
echo -e "${C_CYAN}--------------------------------------------${C_RESET}"
echo -e " ${C_GREEN}[A]${C_RESET} ${C_WHITE}Set WIRED PC Mode (Connect to PC)${C_RESET}"
echo -e " ${C_YELLOW}[X]${C_RESET} ${C_WHITE}Set USB HOST Mode (Pendrives/OTG)${C_RESET}"
echo -e " ${C_RED}[B]${C_RESET} ${C_WHITE}Cancel and Return${C_RESET}"
echo -e "${C_CYAN}--------------------------------------------${C_RESET}"
echo -e " ${C_GRAY}Gamepad: Press [A], [X], or [B]${C_RESET}"

TARGET=""

while true; do
    if type Test_Button_A >/dev/null 2>&1; then
        Test_Button_A; [ "$?" -eq "10" ] && TARGET="peripheral" && break
        Test_Button_X; [ "$?" -eq "10" ] && TARGET="host" && break
        Test_Button_B; [ "$?" -eq "10" ] && TARGET="exit" && break
    fi

    read -t 0.1 -n 1 key 2>/dev/null
    case "$key" in
        1|[aA]) TARGET="peripheral"; break ;;
        2|[xX]) TARGET="host"; break ;;
        3|[bB]|[qQ]) TARGET="exit"; break ;;
    esac
    sleep 0.05
done

if [ "$TARGET" == "exit" ]; then
    printf "\033c" 2>/dev/null
    clear 2>/dev/null
    exit 0
fi

printf "\033c" 2>/dev/null
clear 2>/dev/null

echo -e "${C_CYAN}============================================${C_RESET}"
if [ "$TARGET" == "peripheral" ]; then
    echo -e "${C_GREEN}   SETTING WIRED PC MODE...                 ${C_RESET}"
    if [ -f /boot/rk3326-g350-peripheral.dtb ]; then
        sudo cp /boot/rk3326-g350-peripheral.dtb /boot/rk3326-g350-linux.dtb
        sync
    fi
    echo -e "${C_CYAN}============================================${C_RESET}"
    echo -e " ${C_GREEN}Peripheral DTB applied to /boot!${C_RESET}"
    echo -e " Hardware reboot required to activate."
    echo -e " ${C_YELLOW}Run 'Start Services' after reboot!${C_RESET}"
else
    echo -e "${C_YELLOW}   SETTING USB HOST MODE...                 ${C_RESET}"
    if [ -f /boot/rk3326-g350-host.dtb ]; then
        sudo cp /boot/rk3326-g350-host.dtb /boot/rk3326-g350-linux.dtb
        sync
    fi
    echo -e "${C_CYAN}============================================${C_RESET}"
    echo -e " ${C_YELLOW}Host OTG DTB applied to /boot!${C_RESET}"
    echo -e " Hardware reboot required to activate."
    echo -e " USB-C port will accept flash drives."
fi
echo -e "${C_CYAN}--------------------------------------------${C_RESET}"
echo -e " Press ${C_RED}[B]${C_RESET} to cancel, or wait 5s..."

for i in 5 4 3 2 1; do
    echo -ne " Rebooting in $i seconds... (Press B)\r"
    if type Test_Button_B >/dev/null 2>&1; then
        Test_Button_B
        if [ "$?" -eq "10" ]; then
            echo -e "\n${C_YELLOW}Reboot canceled. Restart manually.${C_RESET}"
            sleep 2
            exit 0
        fi
    fi
    read -t 1 -n 1 key 2>/dev/null
    if [[ "$key" == "b" || "$key" == "B" || "$key" == "q" ]]; then
        echo -e "\n${C_YELLOW}Reboot canceled. Restart manually.${C_RESET}"
        sleep 2
        exit 0
    fi
done

echo -e "\n${C_GREEN}Rebooting now...${C_RESET}"
sync
sudo reboot
exit 0
