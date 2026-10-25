#!/bin/bash
# ==============================================================================
# Script: C2C_Netplay_Prep.sh
# Directory: C2Cconnection/
# Device: Battle XP G350 & Rockchip RK3326 Handhelds (ArkOS / dArkOS)
# Layout: Tailored for 3.5" Handhelds (Max 42 cols x 16 rows, zero overflow)
# Purpose: Interactive RetroArch Netplay Initializer & Port 55435 Monitor
# Controls: HOLD [START + SELECT] to exit, [A] to retest.
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

STATE_DIR="/tmp/c2c_netplay"
EXIT_FLAG="$STATE_DIR/exit"
RETEST_FLAG="$STATE_DIR/retest"
WATCH_PID_FILE="$STATE_DIR/watch.pid"

mkdir -p "$STATE_DIR" 2>/dev/null
rm -f "$EXIT_FLAG" "$RETEST_FLAG" 2>/dev/null

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
# Button watcher: reads /dev/input/js* directly (same method that already works
# in C2C_Connection_Test.sh). START(15)+SELECT(10) -> exit flag, A(1) -> retest.
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

# SELECT / START identifiers (joydev button numbers and evdev key codes)
JS_SEL, JS_STA, JS_A = {8, 10}, {9, 15}, {0, 1}
EV_SEL, EV_STA, EV_A = {314, 704}, {315, 705}, {304, 305}

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
                elif n in JS_A and down: touch("retest")
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
                elif code in EV_A and val: touch("retest")
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
if [ -f /proc/device-tree/usb@ff300000/dr_mode ] && grep -q "host" /proc/device-tree/usb@ff300000/dr_mode 2>/dev/null; then
    ROLE="host"
    MY_IP="192.168.10.1"
    PEER_IP="192.168.10.2"
    LOCAL_ROLE_STR="${C_YELLOW}[HOST]${C_RESET} ${C_WHITE}(192.168.10.1)${C_RESET}"
    PEER_ROLE_STR="${C_GREEN}[PERIPHERAL]${C_RESET} ${C_GRAY}(192.168.10.2)${C_RESET}"
else
    ROLE="peripheral"
    MY_IP="192.168.10.2"
    PEER_IP="192.168.10.1"
    LOCAL_ROLE_STR="${C_GREEN}[PERIPHERAL]${C_RESET} ${C_WHITE}(192.168.10.2)${C_RESET}"
    PEER_ROLE_STR="${C_YELLOW}[HOST]${C_RESET} ${C_GRAY}(192.168.10.1)${C_RESET}"
fi

find_interface() {
    IFACE="usb0"
    if [ ! -d "/sys/class/net/usb0" ]; then
        for dev in /sys/class/net/*; do
            dname=$(basename "$dev")
            if [ "$dname" != "lo" ] && [ "$dname" != "wlan0" ] && [ "$dname" != "eth0" ]; then
                IFACE="$dname"
                break
            fi
        done
    fi
}

# ------------------------------------------------------------------------------
# Stop network managers / DHCP clients from fighting over the C2C interface.
# (They assign 169.254.x.x link-local and wipe our static 192.168.10.x IP.)
# ------------------------------------------------------------------------------
claim_interface() {
    command -v nmcli >/dev/null 2>&1 && sudo nmcli dev set "$IFACE" managed no 2>/dev/null
    sudo pkill -f "dhclient.*$IFACE" 2>/dev/null
    sudo pkill -f "avahi-autoipd.*$IFACE" 2>/dev/null
    command -v dhcpcd >/dev/null 2>&1 && sudo dhcpcd -k "$IFACE" 2>/dev/null
    sudo sysctl -qw "net.ipv4.conf.all.rp_filter=0" "net.ipv4.conf.${IFACE}.rp_filter=0" 2>/dev/null
}

# Remove 169.254.x.x, make sure our IP + route exist (cheap, safe to repeat)
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
    if [ "$ROLE" == "peripheral" ]; then
        if ! lsmod | grep -q "g_ether"; then
            sudo modprobe g_ether 2>/dev/null
            sleep 0.3
        fi
    fi

    find_interface
    sudo ip link set "$IFACE" up 2>/dev/null

    # Wait up to 3s for physical link carrier
    for _i in 1 2 3 4 5 6; do
        [ "$(cat "/sys/class/net/$IFACE/carrier" 2>/dev/null)" = "1" ] && break
        sleep 0.5
    done

    claim_interface
    sleep 0.3
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

    # Show only the C2C address (usb0 may also hold 192.168.7.2/137.2 from USB Network Manager)
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
# 5. Render Screen (In-place redraw via ANSI Home)
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
    echo -e "${C_CYAN}------------------------------------------${C_RESET}\033[K"
    if [ "$ROLE" == "host" ]; then
        echo -e " ${C_WHITE}NEXT:${C_RESET} Launch game, [Select]+[X],\033[K"
        echo -e "       Netplay > ${C_GREEN}Start Netplay Host${C_RESET}\033[K"
    else
        echo -e " ${C_WHITE}NEXT:${C_RESET} Wait for 'HOST ACTIVE', launch\033[K"
        echo -e "       game > ${C_GREEN}Connect to Netplay Host${C_RESET}\033[K"
    fi
    echo -e "${C_CYAN}------------------------------------------${C_RESET}\033[K"
    echo -e " ${C_GREEN}[A]${C_RESET} Retest   ${C_RED}HOLD [START+SELECT] Exit${C_RESET}\033[K"
    echo -e "${C_CYAN}==========================================${C_RESET}\033[K"
}

# ------------------------------------------------------------------------------
# Main Execution Loop
# ------------------------------------------------------------------------------
clear 2>/dev/null
printf "\033[?25l" 2>/dev/null

start_button_watcher
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

    read -t 0.05 -n 1 k 2>/dev/null
    rc=$?
    case "$k" in
        $'\x03'|$'\x04') exit 0 ;;
        [aA]|1)
            init_network
            check_status
            draw_screen
            ;;
    esac
    # stdin is not a TTY when launched from EmulationStation: avoid a hot loop
    [ "$rc" -ne 0 ] && [ "$rc" -le 128 ] && sleep 0.05

    # Periodic re-check every ~2 seconds
    if [ "$LOOP_COUNT" -ge 40 ]; then
        LOOP_COUNT=0
        check_status
        draw_screen
    fi
done
