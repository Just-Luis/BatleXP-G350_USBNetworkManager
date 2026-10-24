#!/bin/bash
# ==============================================================================
# Script: Switch_USB_Mode.sh
# Device: Battle XP G350 / RK3326 Handhelds (dArkOS / ArkOS)
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

ensure_dtb_profiles() {
    if [ -s /boot/rk3326-g350-peripheral.dtb ] && [ -s /boot/rk3326-g350-host.dtb ]; then
        return 0
    fi

    if [ ! -f /boot/rk3326-g350-linux.dtb ]; then
        return 1
    fi

    if [ ! -s /boot/rk3326-g350-linux.dtb.original ]; then
        sudo cp /boot/rk3326-g350-linux.dtb /boot/rk3326-g350-linux.dtb.original 2>/dev/null
        sync
    fi

    for dir in "$SCRIPT_DIR" "$(dirname "$SCRIPT_DIR")"; do
        if [ -s "$dir/rk3326-g350-peripheral.dtb" ] && [ ! -s /boot/rk3326-g350-peripheral.dtb ]; then
            sudo cp "$dir/rk3326-g350-peripheral.dtb" /boot/rk3326-g350-peripheral.dtb 2>/dev/null
        fi
        if [ -s "$dir/rk3326-g350-host.dtb" ] && [ ! -s /boot/rk3326-g350-host.dtb ]; then
            sudo cp "$dir/rk3326-g350-host.dtb" /boot/rk3326-g350-host.dtb 2>/dev/null
        fi
    done

    if [ -s /boot/rk3326-g350-peripheral.dtb ] && [ -s /boot/rk3326-g350-host.dtb ]; then
        sync
        return 0
    fi

    if command -v python3 >/dev/null 2>&1; then
        sudo python3 -c "
import struct, os

class FdtNode:
    def __init__(self, name):
        self.name = name; self.props = {}; self.children = []

def parse_fdt(data):
    magic, totalsize, off_struct, off_strings, off_memrsv, version, last_comp, boot_cpuid, sz_strings, sz_struct = struct.unpack('>10I', data[:40])
    assert magic == 0xd00dfeed
    def get_str(offset):
        s = data[off_strings + offset:]; return s[:s.find(b'\0')].decode('latin1')
    pos = off_struct; root = None; stack = []
    while pos < off_struct + sz_struct:
        token = struct.unpack('>I', data[pos:pos+4])[0]; pos += 4
        if token == 1:
            name_end = data.find(b'\0', pos)
            node = FdtNode(data[pos:name_end].decode('latin1'))
            pos = (name_end + 1 + 3) & ~3
            if stack: stack[-1].children.append(node)
            else: root = node
            stack.append(node)
        elif token == 2: stack.pop()
        elif token == 3:
            val_len, name_off = struct.unpack('>II', data[pos:pos+8]); pos += 8
            val = data[pos:pos+val_len]; pos = (pos + val_len + 3) & ~3
            stack[-1].props[get_str(name_off)] = val
        elif token == 4: continue
        elif token == 9: break
    return root, data[off_memrsv:off_struct]

def serialize_fdt(root, memrsv):
    strings_map = {}; strings_data = bytearray()
    def add_string(s):
        if s not in strings_map:
            strings_map[s] = len(strings_data)
            strings_data.extend(s.encode('latin1') + b'\0')
        return strings_map[s]
    struct_data = bytearray()
    def write_node(node):
        struct_data.extend(struct.pack('>I', 1))
        struct_data.extend(node.name.encode('latin1') + b'\0')
        while len(struct_data) % 4 != 0: struct_data.append(0)
        for k, v in node.props.items():
            name_off = add_string(k)
            struct_data.extend(struct.pack('>III', 3, len(v), name_off))
            struct_data.extend(v)
            while len(struct_data) % 4 != 0: struct_data.append(0)
        for ch in node.children: write_node(ch)
        struct_data.extend(struct.pack('>I', 2))
    write_node(root); struct_data.extend(struct.pack('>I', 9))
    off_memrsv = 48
    off_struct = (off_memrsv + len(memrsv) + 7) & ~7
    off_strings = (off_struct + len(struct_data) + 7) & ~7
    totalsize = off_strings + len(strings_data)
    hdr = struct.pack('>10I', 0xd00dfeed, totalsize, off_struct, off_strings, off_memrsv, 17, 16, 0, len(strings_data), len(struct_data)) + b'\0' * (off_memrsv - 40)
    res = bytearray(totalsize)
    res[:len(hdr)] = hdr
    res[off_memrsv:off_memrsv+len(memrsv)] = memrsv
    res[off_struct:off_struct+len(struct_data)] = struct_data
    res[off_strings:off_strings+len(strings_data)] = strings_data
    return bytes(res)

def find_node(node, path):
    curr = node
    for part in [p for p in path.split('/') if p]:
        found = next((ch for ch in curr.children if ch.name == part), None)
        if not found: return None
        curr = found
    return curr

src = '/boot/rk3326-g350-linux.dtb.original' if os.path.exists('/boot/rk3326-g350-linux.dtb.original') else '/boot/rk3326-g350-linux.dtb'
orig_data = open(src, 'rb').read()
for mode, out_path in [('peripheral', '/boot/rk3326-g350-peripheral.dtb'), ('host', '/boot/rk3326-g350-host.dtb')]:
    root, memrsv = parse_fdt(orig_data)
    usb_node = find_node(root, '/usb@ff300000')
    otg_port = find_node(root, '/syscon@ff2c0000/usb2-phy@100/otg-port')
    if usb_node and otg_port:
        usb_node.props['dr_mode'] = mode.encode('latin1') + b'\x00'
        otg_port.props['status'] = b'okay\x00'
        open(out_path, 'wb').write(serialize_fdt(root, memrsv))
" 2>/dev/null
        sync
    fi

    [ -s /boot/rk3326-g350-peripheral.dtb ] && [ -s /boot/rk3326-g350-host.dtb ]
    return $?
}

ensure_dtb_profiles

printf "\033c" 2>/dev/null
clear 2>/dev/null

echo -e "${C_CYAN}============================================${C_RESET}"
echo -e "${C_WHITE}   BATTLE XP G350 - SWITCH USB MODE         ${C_RESET}"
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
    if [ -s /boot/rk3326-g350-peripheral.dtb ] && sudo cp /boot/rk3326-g350-peripheral.dtb /boot/rk3326-g350-linux.dtb 2>/dev/null; then
        sync
        echo -e "${C_CYAN}============================================${C_RESET}"
        echo -e " ${C_GREEN}Peripheral DTB applied to /boot!${C_RESET}"
        echo -e " Hardware reboot required to activate."
        echo -e " ${C_YELLOW}Run 'Start Services' after reboot!${C_RESET}"
    else
        echo -e "${C_CYAN}============================================${C_RESET}"
        echo -e " ${C_RED}ERROR: Could not apply Peripheral DTB!${C_RESET}"
        sleep 3
        exit 1
    fi
else
    echo -e "${C_YELLOW}   SETTING USB HOST MODE...                 ${C_RESET}"
    if [ -s /boot/rk3326-g350-host.dtb ] && sudo cp /boot/rk3326-g350-host.dtb /boot/rk3326-g350-linux.dtb 2>/dev/null; then
        sync
        echo -e "${C_CYAN}============================================${C_RESET}"
        echo -e " ${C_YELLOW}Host OTG DTB applied to /boot!${C_RESET}"
        echo -e " Hardware reboot required to activate."
        echo -e " USB-C port will accept flash drives."
    else
        echo -e "${C_CYAN}============================================${C_RESET}"
        echo -e " ${C_RED}ERROR: Could not apply Host DTB!${C_RESET}"
        sleep 3
        exit 1
    fi
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
