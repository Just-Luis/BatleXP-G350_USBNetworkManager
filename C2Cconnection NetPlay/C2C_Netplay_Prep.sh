#!/bin/bash
# ==============================================================================
# Script: C2C_Netplay_Prep.sh
# Directory: C2Cconnection NetPlay/
# Device: Battle XP G350 & Rockchip RK3326 Handhelds (ArkOS / dArkOS)
# Layout: Tailored for 3.5" Handhelds (Max 42 cols x 16 rows, zero overflow)
# Purpose: All-in-One 1-Click RetroArch Netplay Initializer, Role Switcher & Monitor
# Controls: [A] Retest, [X] Switch Role, HOLD [START + SELECT] to exit.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROLE_FILE="/home/ark/.config/c2c_role"
[ ! -d "/home/ark" ] && ROLE_FILE="/etc/c2c_role"
sudo mkdir -p "$(dirname "$ROLE_FILE")" 2>/dev/null

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

STATE_DIR="/tmp/c2c_netplay"
EXIT_FLAG="$STATE_DIR/exit"
RETEST_FLAG="$STATE_DIR/retest"
WATCH_PID_FILE="$STATE_DIR/watch.pid"

mkdir -p "$STATE_DIR" 2>/dev/null
rm -f "$EXIT_FLAG" "$RETEST_FLAG" "$STATE_DIR"/btn_* 2>/dev/null

cleanup() {
    if [ -f "$WATCH_PID_FILE" ]; then
        sudo kill -9 "$(cat "$WATCH_PID_FILE" 2>/dev/null)" 2>/dev/null
    fi
    sudo pkill -f "c2c_btn_watch.py" 2>/dev/null
    rm -rf "$STATE_DIR" 2>/dev/null
    printf "\033[?25h" 2>/dev/null
    clear 2>/dev/null
}
trap cleanup EXIT INT TERM

# ------------------------------------------------------------------------------
# Autonomous Device Tree (DTB) Generator
# Ensures peripheral and host DTBs exist on /boot without internet or extra files.
# ------------------------------------------------------------------------------
ensure_dtb_profiles() {
    if [ -s /boot/rk3326-g350-peripheral.dtb ] && [ -s /boot/rk3326-g350-host.dtb ]; then
        return 0
    fi

    if [ ! -f /boot/rk3326-g350-linux.dtb ]; then
        return 1
    fi

    # 1. Preserve original factory DTB backup
    if [ ! -s /boot/rk3326-g350-linux.dtb.original ]; then
        sudo cp /boot/rk3326-g350-linux.dtb /boot/rk3326-g350-linux.dtb.original 2>/dev/null
        sync
    fi

    # 2. Copy prebuilt DTB profiles if bundled alongside the script
    if [ -s "$SCRIPT_DIR/rk3326-g350-peripheral.dtb" ] && [ ! -s /boot/rk3326-g350-peripheral.dtb ]; then
        sudo cp "$SCRIPT_DIR/rk3326-g350-peripheral.dtb" /boot/rk3326-g350-peripheral.dtb 2>/dev/null
    fi
    if [ -s "$SCRIPT_DIR/rk3326-g350-host.dtb" ] && [ ! -s /boot/rk3326-g350-host.dtb ]; then
        sudo cp "$SCRIPT_DIR/rk3326-g350-host.dtb" /boot/rk3326-g350-host.dtb 2>/dev/null
    fi

    if [ -s /boot/rk3326-g350-peripheral.dtb ] && [ -s /boot/rk3326-g350-host.dtb ]; then
        sync
        return 0
    fi

    # 3. Auto-generate peripheral and host DTBs directly from factory DTB via Python3
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

# ------------------------------------------------------------------------------
# Button Watcher: reads /dev/input/js* and /dev/input/event*
# START(9/15)+SELECT(8/10) -> exit, A(1) -> retest, X(3) -> switch, B(0) -> cancel
# ------------------------------------------------------------------------------
start_button_watcher() {
    cat << 'EOF' > "$STATE_DIR/c2c_btn_watch.py"
import os, struct, time, glob

D = "/tmp/c2c_netplay"
EV_FMT = "llHHi"
EV_SIZE = struct.calcsize(EV_FMT)

def opened(patterns):
    out = []
    for pat in patterns:
        for p in sorted(glob.glob(pat)):
            try:
                f = open(p, "rb", buffering=0)
                os.set_blocking(f.fileno(), False)
                out.append((p, f))
            except Exception:
                pass
    return out

js_devs = opened(["/dev/input/js*"])
ev_devs = opened(["/dev/input/event*"])

# Button mappings
JS_SEL, JS_STA = {8, 10}, {9, 15}
JS_A, JS_B, JS_X = {1}, {0}, {3}
EV_SEL, EV_STA = {314, 704}, {315, 705}
EV_A, EV_B, EV_X = {304}, {305}, {307}

sel = 0
sta = 0

def touch(name):
    try:
        open(D + "/" + name, "w").write("1")
    except Exception:
        pass

while True:
    for path, f in js_devs:
        while True:
            try:
                data = f.read(8)
            except Exception:
                break
            if not data or len(data) < 8:
                break
            _, val, t, n = struct.unpack("IhBB", data)
            t &= ~0x80
            if t == 1:
                down = 1 if val != 0 else 0
                if n in JS_SEL: sel = down
                elif n in JS_STA: sta = down
                elif n in JS_A and down: touch("btn_a"); touch("retest")
                elif n in JS_B and down: touch("btn_b")
                elif n in JS_X and down: touch("btn_x")
    for path, f in ev_devs:
        while True:
            try:
                data = f.read(EV_SIZE)
            except Exception:
                break
            if not data or len(data) < EV_SIZE:
                break
            _, _, t, code, val = struct.unpack(EV_FMT, data)
            if t == 1 and val in (0, 1):
                if code in EV_SEL: sel = val
                elif code in EV_STA: sta = val
                elif code in EV_A and val: touch("btn_a"); touch("retest")
                elif code in EV_B and val: touch("btn_b")
                elif code in EV_X and val: touch("btn_x")
    if sel and sta:
        touch("exit")
    time.sleep(0.02)
EOF
    if command -v python3 >/dev/null 2>&1; then
        sudo python3 "$STATE_DIR/c2c_btn_watch.py" >/dev/null 2>&1 &
        echo $! > "$WATCH_PID_FILE"
    fi
}

check_exit_combo() {
    [ -f "$EXIT_FLAG" ] && return 0
    if type Test_Button_Start >/dev/null 2>&1 && type Test_Button_Select >/dev/null 2>&1; then
        Test_Button_Start
        local s_code=$?
        Test_Button_Select
        local sel_code=$?
        [ "$s_code" -eq "10" ] && [ "$sel_code" -eq "10" ] && return 0
    fi
    return 1
}

# ------------------------------------------------------------------------------
# 1. Role Detection
# ------------------------------------------------------------------------------
detect_role() {
    if [ -f /proc/device-tree/usb@ff300000/dr_mode ] && grep -aq "peripheral" /proc/device-tree/usb@ff300000/dr_mode 2>/dev/null; then
        ROLE="peripheral"
    elif [ -f /sys/firmware/devicetree/base/usb@ff300000/dr_mode ] && grep -aq "peripheral" /sys/firmware/devicetree/base/usb@ff300000/dr_mode 2>/dev/null; then
        ROLE="peripheral"
    elif [ -f /boot/rk3326-g350-peripheral.dtb ] && cmp -s /boot/rk3326-g350-linux.dtb /boot/rk3326-g350-peripheral.dtb 2>/dev/null; then
        ROLE="peripheral"
    elif [ -f /proc/device-tree/usb@ff300000/dr_mode ] && grep -aq "host" /proc/device-tree/usb@ff300000/dr_mode 2>/dev/null; then
        ROLE="host"
    elif [ -f /boot/rk3326-g350-host.dtb ] && cmp -s /boot/rk3326-g350-linux.dtb /boot/rk3326-g350-host.dtb 2>/dev/null; then
        ROLE="host"
    else
        # Factory stock DTB (dr_mode="otg") defaults to Host mode physically
        ROLE="host"
    fi

    if [ "$ROLE" == "host" ]; then
        MY_IP="192.168.10.1"
        PEER_IP="192.168.10.2"
        LOCAL_ROLE_STR="${C_YELLOW}[HOST]${C_RESET} ${C_WHITE}(192.168.10.1)${C_RESET}"
        PEER_ROLE_STR="${C_GREEN}[CLIENT]${C_RESET} ${C_GRAY}(192.168.10.2)${C_RESET}"
        SWITCH_ACTION_STR="${C_YELLOW}[X]${C_RESET} Make P2"
        [ -f "$ROLE_FILE" ] && echo "host" | sudo tee "$ROLE_FILE" >/dev/null 2>&1
    else
        MY_IP="192.168.10.2"
        PEER_IP="192.168.10.1"
        LOCAL_ROLE_STR="${C_GREEN}[CLIENT]${C_RESET} ${C_WHITE}(192.168.10.2)${C_RESET}"
        PEER_ROLE_STR="${C_YELLOW}[HOST]${C_RESET} ${C_GRAY}(192.168.10.1)${C_RESET}"
        SWITCH_ACTION_STR="${C_YELLOW}[X]${C_RESET} Make P1"
        [ -f "$ROLE_FILE" ] && echo "client" | sudo tee "$ROLE_FILE" >/dev/null 2>&1
    fi
}

# ------------------------------------------------------------------------------
# First-Launch Interactive Role Wizard
# Asks whether this console will be Player 1 (Host) or Player 2 (Client).
# ------------------------------------------------------------------------------
first_launch_wizard() {
    [ -f "$ROLE_FILE" ] && return 0

    ensure_dtb_profiles

    clear 2>/dev/null
    printf "\033[H" 2>/dev/null

    echo -e "${C_CYAN}==========================================${C_RESET}"
    echo -e "${C_WHITE}   C2C NETPLAY — FIRST TIME SETUP         ${C_RESET}"
    echo -e "${C_CYAN}==========================================${C_RESET}"
    echo -e " ${C_WHITE}Choose the role for this console:${C_RESET}"
    echo -e ""
    echo -e " ${C_GREEN}[A] PLAYER 1${C_RESET}  ${C_WHITE}(Host / Room Creator)${C_RESET}"
    echo -e "     • Starts Netplay room in RetroArch"
    echo -e "     • Uses USB-C OTG Host adapter"
    echo -e ""
    echo -e " ${C_YELLOW}[X] PLAYER 2${C_RESET}  ${C_WHITE}(Client / Joiner)${C_RESET}"
    echo -e "     • Connects to Player 1 directly"
    echo -e "     • Reboots to activate Client mode"
    echo -e ""
    echo -e " ${C_RED}[B]${C_RESET} ${C_GRAY}Exit to EmulationStation${C_RESET}"
    echo -e "${C_CYAN}==========================================${C_RESET}"

    rm -f "$STATE_DIR/btn_a" "$STATE_DIR/btn_x" "$STATE_DIR/btn_b" "$STATE_DIR/exit" "$STATE_DIR/retest" 2>/dev/null

    while true; do
        local chosen=""

        if [ -f "$STATE_DIR/btn_a" ]; then
            rm -f "$STATE_DIR/btn_a" "$STATE_DIR/retest" 2>/dev/null
            chosen="host"
        elif [ -f "$STATE_DIR/btn_x" ]; then
            rm -f "$STATE_DIR/btn_x" 2>/dev/null
            chosen="client"
        elif [ -f "$STATE_DIR/btn_b" ] || [ -f "$STATE_DIR/exit" ]; then
            rm -f "$STATE_DIR/btn_b" "$STATE_DIR/exit" 2>/dev/null
            exit 0
        fi

        if [ -z "$chosen" ] && type Test_Button_A >/dev/null 2>&1; then
            Test_Button_A; [ "$?" -eq "10" ] && chosen="host"
        fi
        if [ -z "$chosen" ] && type Test_Button_X >/dev/null 2>&1; then
            Test_Button_X; [ "$?" -eq "10" ] && chosen="client"
        fi
        if [ -z "$chosen" ] && type Test_Button_B >/dev/null 2>&1; then
            Test_Button_B; [ "$?" -eq "10" ] && exit 0
        fi

        if [ -z "$chosen" ]; then
            read -t 0.05 -n 1 k 2>/dev/null
            case "$k" in
                [aA]|1) chosen="host" ;;
                [xX]|3) chosen="client" ;;
                [bB]|4|$'\x03'|$'\x04') exit 0 ;;
            esac
        fi

        if [ "$chosen" == "host" ]; then
            echo "host" | sudo tee "$ROLE_FILE" >/dev/null 2>&1
            sudo chown ark:ark "$ROLE_FILE" 2>/dev/null
            detect_role
            if [ "$ROLE" == "peripheral" ]; then
                sudo cp /boot/rk3326-g350-host.dtb /boot/rk3326-g350-linux.dtb 2>/dev/null
                sync
                clear 2>/dev/null
                echo -e "${C_CYAN}==========================================${C_RESET}"
                echo -e "${C_GREEN} Configured as PLAYER 1 (HOST)!           ${C_RESET}"
                echo -e " Rebooting into Host Mode in 3s...        "
                echo -e "${C_CYAN}==========================================${C_RESET}"
                sleep 3
                sudo reboot
            else
                sudo cp /boot/rk3326-g350-host.dtb /boot/rk3326-g350-linux.dtb 2>/dev/null
                sync
                clear 2>/dev/null
                echo -e "${C_CYAN}==========================================${C_RESET}"
                echo -e "${C_GREEN} Configured as PLAYER 1 (HOST)!           ${C_RESET}"
                echo -e " Starting Netplay Prep...                 "
                echo -e "${C_CYAN}==========================================${C_RESET}"
                sleep 1.5
                break
            fi
        elif [ "$chosen" == "client" ]; then
            echo "client" | sudo tee "$ROLE_FILE" >/dev/null 2>&1
            sudo chown ark:ark "$ROLE_FILE" 2>/dev/null
            detect_role
            if [ "$ROLE" == "host" ]; then
                sudo cp /boot/rk3326-g350-peripheral.dtb /boot/rk3326-g350-linux.dtb 2>/dev/null
                sync
                clear 2>/dev/null
                echo -e "${C_CYAN}==========================================${C_RESET}"
                echo -e "${C_GREEN} Configured as PLAYER 2 (CLIENT)!         ${C_RESET}"
                echo -e " Rebooting into Client Mode in 3s...      "
                echo -e "${C_CYAN}==========================================${C_RESET}"
                sleep 3
                sudo reboot
            else
                sudo cp /boot/rk3326-g350-peripheral.dtb /boot/rk3326-g350-linux.dtb 2>/dev/null
                sync
                clear 2>/dev/null
                echo -e "${C_CYAN}==========================================${C_RESET}"
                echo -e "${C_GREEN} Configured as PLAYER 2 (CLIENT)!         ${C_RESET}"
                echo -e " Starting Netplay Prep...                 "
                echo -e "${C_CYAN}==========================================${C_RESET}"
                sleep 1.5
                break
            fi
        fi

        sleep 0.05
    done
}

# ------------------------------------------------------------------------------
# Action [X]: Switch Hardware Role (Player 1 <-> Player 2) with Safe Reboot
# ------------------------------------------------------------------------------
switch_hardware_mode() {
    clear 2>/dev/null
    printf "\033[H" 2>/dev/null

    ensure_dtb_profiles

    if [ "$ROLE" == "peripheral" ]; then
        TARGET="host"
        TARGET_LABEL="PLAYER 1 (Netplay HOST)"
        TARGET_DTB="/boot/rk3326-g350-host.dtb"
        ROLE_VAL="host"
    else
        TARGET="peripheral"
        TARGET_LABEL="PLAYER 2 (Netplay CLIENT)"
        TARGET_DTB="/boot/rk3326-g350-peripheral.dtb"
        ROLE_VAL="client"
    fi

    echo -e "${C_CYAN}==========================================${C_RESET}"
    echo -e "${C_WHITE}       SWITCHING HARDWARE ROLE            ${C_RESET}"
    echo -e "${C_CYAN}==========================================${C_RESET}"
    echo -e " Target Role: ${C_YELLOW}$TARGET_LABEL${C_RESET}"
    echo -e ""
    echo -e " [1/2] Writing Device Tree to /boot..."

    if [ -s "$TARGET_DTB" ] && sudo cp "$TARGET_DTB" /boot/rk3326-g350-linux.dtb 2>/dev/null; then
        sync
        echo -e "       ${C_GREEN}-> Hardware profile applied.${C_RESET}"
    else
        echo -e "       ${C_RED}-> ERROR writing DTB to /boot!${C_RESET}"
        sleep 3
        return 1
    fi

    echo "$ROLE_VAL" | sudo tee "$ROLE_FILE" >/dev/null 2>&1
    sudo chown ark:ark "$ROLE_FILE" 2>/dev/null
    sync

    echo -e " [2/2] Preparing hardware restart..."
    echo -e "${C_CYAN}------------------------------------------${C_RESET}"
    echo -e " ${C_WHITE}Hardware reboot required to activate.${C_RESET}"
    echo -e " Press ${C_RED}[B]${C_RESET} to cancel, or wait 5 seconds:"
    echo -e "${C_CYAN}------------------------------------------${C_RESET}"

    rm -f "$STATE_DIR/btn_b" 2>/dev/null

    for i in 5 4 3 2 1; do
        echo -ne " Rebooting in $i seconds... (Press B to cancel)\r"
        if [ -f "$STATE_DIR/btn_b" ]; then
            rm -f "$STATE_DIR/btn_b" 2>/dev/null
            echo -e "\n${C_YELLOW}Reboot canceled. Returning to menu...${C_RESET}"
            sleep 1.5
            return 0
        fi
        if type Test_Button_B >/dev/null 2>&1; then
            Test_Button_B
            if [ "$?" -eq "10" ]; then
                echo -e "\n${C_YELLOW}Reboot canceled. Returning to menu...${C_RESET}"
                sleep 1.5
                return 0
            fi
        fi
        read -t 1 -n 1 bk 2>/dev/null
        case "$bk" in
            [bB]|4)
                echo -e "\n${C_YELLOW}Reboot canceled. Returning to menu...${C_RESET}"
                sleep 1.5
                return 0
                ;;
        esac
    done

    echo -e "\n${C_GREEN}Rebooting now...${C_RESET}"
    sleep 0.5
    sudo reboot
}

find_interface() {
    IFACE=""
    if [ -d "/sys/class/net/usb0" ]; then
        IFACE="usb0"
    else
        for dev in /sys/class/net/*; do
            [ ! -d "$dev" ] && continue
            dname=$(basename "$dev")
            case "$dname" in
                lo|wlan*|dummy*|sit*|ip6tnl*)
                    continue
                    ;;
                usb*|eth*|en*)
                    IFACE="$dname"
                    break
                    ;;
            esac
        done
    fi
    [ -z "$IFACE" ] && IFACE="usb0"
    sudo ip link set "$IFACE" up 2>/dev/null
}

# Stop DHCP / link-local daemons and purge stale default routes on C2C interface
claim_interface() {
    command -v nmcli >/dev/null 2>&1 && sudo nmcli dev set "$IFACE" managed no 2>/dev/null
    sudo pkill -f "dhclient.*$IFACE" 2>/dev/null
    sudo pkill -f "avahi-autoipd.*$IFACE" 2>/dev/null
    command -v dhcpcd >/dev/null 2>&1 && sudo dhcpcd -k "$IFACE" 2>/dev/null
    sudo sysctl -qw "net.ipv4.conf.all.rp_filter=0" "net.ipv4.conf.${IFACE}.rp_filter=0" 2>/dev/null
    sudo ip route del default dev "$IFACE" 2>/dev/null
}

ensure_ip() {
    local a
    for a in $(ip -4 -o addr show dev "$IFACE" 2>/dev/null | awk '{print $4}' | grep '^169\.254\.'); do
        sudo ip addr del "$a" dev "$IFACE" 2>/dev/null
    done
    ip -4 addr show dev "$IFACE" 2>/dev/null | grep -q "inet ${MY_IP}/" \
        || sudo ip addr add "${MY_IP}/24" dev "$IFACE" 2>/dev/null
    ip route 2>/dev/null | grep -q "^192.168.10.0/24 dev $IFACE" \
        || sudo ip route replace 192.168.10.0/24 dev "$IFACE" 2>/dev/null
}

init_network() {
    detect_role
    if [ "$ROLE" == "peripheral" ]; then
        if ! lsmod | grep -q "g_ether"; then
            sudo modprobe g_ether 2>/dev/null
            sleep 0.3
        fi
    else
        sudo modprobe cdc_ether 2>/dev/null
        sudo modprobe rndis_host 2>/dev/null
        sudo modprobe cdc_eem 2>/dev/null
        sudo modprobe usbnet 2>/dev/null
        sleep 0.3
    fi

    find_interface

    for _i in 1 2 3 4 5 6; do
        [ "$(cat "/sys/class/net/$IFACE/carrier" 2>/dev/null)" = "1" ] && break
        sleep 0.5
        find_interface
    done

    claim_interface
    sleep 0.2
    ensure_ip
}

# ------------------------------------------------------------------------------
# 3. Patch All RetroArch Configs (Disable Relay & NAT Traversal)
# ------------------------------------------------------------------------------
patch_configs() {
    local target_ip="192.168.10.1"
    local my_nick="Player1"
    [ "$ROLE" == "peripheral" ] && my_nick="Player2"

    for cfg in \
        /home/ark/.config/retroarch/retroarch.cfg \
        /home/ark/.config/retroarch32/retroarch.cfg \
        /opt/retroarch/config/retroarch.cfg \
        /opt/retroarch/retroarch.cfg \
        /etc/retroarch.cfg; do

        if [ -f "$cfg" ]; then
            grep -q "^netplay_use_relay_server" "$cfg" \
                && sudo sed -i 's/^netplay_use_relay_server.*/netplay_use_relay_server = "false"/' "$cfg" \
                || echo 'netplay_use_relay_server = "false"' | sudo tee -a "$cfg" >/dev/null
            grep -q "^netplay_nat_traversal" "$cfg" \
                && sudo sed -i 's/^netplay_nat_traversal.*/netplay_nat_traversal = "false"/' "$cfg" \
                || echo 'netplay_nat_traversal = "false"' | sudo tee -a "$cfg" >/dev/null
            grep -q "^netplay_public_announce" "$cfg" \
                && sudo sed -i 's/^netplay_public_announce.*/netplay_public_announce = "false"/' "$cfg" \
                || echo 'netplay_public_announce = "false"' | sudo tee -a "$cfg" >/dev/null
            grep -q "^netplay_ip_port" "$cfg" \
                && sudo sed -i 's/^netplay_ip_port.*/netplay_ip_port = "55435"/' "$cfg" \
                || echo 'netplay_ip_port = "55435"' | sudo tee -a "$cfg" >/dev/null
            grep -q "^netplay_nickname" "$cfg" \
                && sudo sed -i 's/^netplay_nickname.*/netplay_nickname = "'"$my_nick"'"/' "$cfg" \
                || echo 'netplay_nickname = "'"$my_nick"'"' | sudo tee -a "$cfg" >/dev/null
            if [ "$ROLE" == "peripheral" ]; then
                grep -q "^netplay_ip_address" "$cfg" \
                    && sudo sed -i 's/^netplay_ip_address.*/netplay_ip_address = "'"$target_ip"'"/' "$cfg" \
                    || echo 'netplay_ip_address = "'"$target_ip"'"' | sudo tee -a "$cfg" >/dev/null
            fi
            sudo chown ark:ark "$cfg" 2>/dev/null
        fi
    done
}

# ------------------------------------------------------------------------------
# 4. Status Check & Host Port 55435 Monitoring
# ------------------------------------------------------------------------------
check_status() {
    find_interface
    ensure_ip

    CARRIER_STR="${C_RED}NO LINK (Check OTG Cable)${C_RESET}"
    PING_STR="${C_GRAY}OFFLINE${C_RESET}"
    NETPLAY_STATUS="${C_GRAY}WAITING FOR LINK...${C_RESET}"
    LOCAL_IP_STR="${C_GRAY}none${C_RESET}"

    CUR_IPS=$(ip -4 -o addr show dev "$IFACE" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | grep '^192\.168\.10\.' | head -n 1)
    [ -n "$CUR_IPS" ] && LOCAL_IP_STR="${C_WHITE}${CUR_IPS}${C_RESET}"

    if [ "$(cat "/sys/class/net/$IFACE/carrier" 2>/dev/null)" = "1" ]; then
        CARRIER_STR="${C_GREEN}CONNECTED [CARRIER OK]${C_RESET}"

        if ping -c 1 -W 1 -I "$MY_IP" "$PEER_IP" >/dev/null 2>&1; then
            PING_STR="${C_GREEN}ONLINE [OK]${C_RESET}"

            if [ "$ROLE" == "peripheral" ]; then
                if timeout 0.35 bash -c '(exec 3<>/dev/tcp/192.168.10.1/55435) 2>/dev/null'; then
                    NETPLAY_STATUS="${C_GREEN}> HOST ACTIVE! READY TO CONNECT!${C_RESET}"
                else
                    NETPLAY_STATUS="${C_YELLOW}> WAITING FOR HOST TO START NETPLAY${C_RESET}"
                fi
            else
                if (exec 3<>/dev/tcp/127.0.0.1/55435) 2>/dev/null; then
                    NETPLAY_STATUS="${C_GREEN}> HOSTING ON PORT 55435 [ACTIVE]${C_RESET}"
                else
                    NETPLAY_STATUS="${C_CYAN}> READY (Will open when you host)${C_RESET}"
                fi
            fi
        else
            PING_STR="${C_RED}UNREACHABLE (Check Peer)${C_RESET}"
            NETPLAY_STATUS="${C_RED}> PEER NOT RESPONDING TO PING${C_RESET}"
        fi
    fi
}

# ------------------------------------------------------------------------------
# 5. Render Screen (In-place redraw via ANSI Home - strictly 16 lines)
# ------------------------------------------------------------------------------
draw_screen() {
    printf "\033[H" 2>/dev/null

    echo -e "${C_CYAN}==========================================${C_RESET}\033[K"
    echo -e "${C_WHITE}   C2C RETROARCH NETPLAY SETUP & TEST     ${C_RESET}\033[K"
    echo -e "${C_CYAN}==========================================${C_RESET}\033[K"
    echo -e " ${C_WHITE}LOCAL ROLE :${C_RESET} $LOCAL_ROLE_STR\033[K"
    echo -e " ${C_WHITE}PEER ROLE  :${C_RESET} $PEER_ROLE_STR\033[K"
    echo -e " ${C_WHITE}IFACE / IP :${C_RESET} ${IFACE}  $LOCAL_IP_STR\033[K"
    echo -e " ${C_WHITE}CABLE LINK :${C_RESET} $CARRIER_STR\033[K"
    echo -e " ${C_WHITE}PING TEST  :${C_RESET} $PING_STR\033[K"
    echo -e "${C_CYAN}------------------------------------------${C_RESET}\033[K"
    echo -e " ${C_WHITE}NETPLAY STATUS (Host Port 55435):${C_RESET}\033[K"
    echo -e " $NETPLAY_STATUS\033[K"
    if [ "$ROLE" == "host" ]; then
        echo -e " ${C_WHITE}NEXT:${C_RESET} Launch game, [Select]+[X],\033[K"
        echo -e "       Netplay > ${C_GREEN}Start Netplay Host${C_RESET}\033[K"
    else
        echo -e " ${C_WHITE}NEXT:${C_RESET} Wait for 'HOST ACTIVE', launch\033[K"
        echo -e "       game > ${C_GREEN}Connect to Netplay Host${C_RESET}\033[K"
    fi
    echo -e "${C_CYAN}------------------------------------------${C_RESET}\033[K"
    echo -e " ${C_GREEN}[A]${C_RESET} Retest  $SWITCH_ACTION_STR   ${C_RED}[STA+SEL]${C_RESET} Exit\033[K"
    echo -e "${C_CYAN}==========================================${C_RESET}\033[K"
}

# ------------------------------------------------------------------------------
# Main Application Flow
# ------------------------------------------------------------------------------
clear 2>/dev/null
printf "\033[?25l" 2>/dev/null

start_button_watcher
first_launch_wizard
init_network
patch_configs
check_status
draw_screen

LOOP_COUNT=0
while true; do
    LOOP_COUNT=$((LOOP_COUNT + 1))

    if check_exit_combo; then
        exit 0
    fi

    if [ -f "$RETEST_FLAG" ]; then
        rm -f "$RETEST_FLAG"
        init_network
        check_status
        draw_screen
    fi

    if [ -f "$STATE_DIR/btn_x" ]; then
        rm -f "$STATE_DIR/btn_x" 2>/dev/null
        switch_hardware_mode
        init_network
        check_status
        draw_screen
    fi

    if type Test_Button_X >/dev/null 2>&1; then
        Test_Button_X
        if [ "$?" -eq "10" ]; then
            switch_hardware_mode
            init_network
            check_status
            draw_screen
        fi
    fi

    read -t 0.05 -n 1 k 2>/dev/null
    rc=$?
    case "$k" in
        $'\x03'|$'\x04') exit 0 ;;
        [aA]|1)
            init_network
            check_status
            draw_screen
            ;;
        [xX]|3)
            switch_hardware_mode
            init_network
            check_status
            draw_screen
            ;;
    esac
    [ "$rc" -ne 0 ] && [ "$rc" -le 128 ] && sleep 0.05

    # Periodic re-check every ~2 seconds
    if [ "$LOOP_COUNT" -ge 40 ]; then
        LOOP_COUNT=0
        check_status
        draw_screen
    fi
done
