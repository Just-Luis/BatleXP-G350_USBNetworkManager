#!/bin/bash
# ==============================================================================
# Script: C2C_Connection_Test.sh
# Directory: C2Cconnection/
# Device: Battle XP G350 & Rockchip RK3326 Handhelds (ArkOS / dArkOS)
# Layout: Tailored for 3.5" Handhelds (Max 42 cols x 16 rows, zero overflow)
# Purpose: Direct Console-to-Console (C2C) USB Connection Verification &
#          Real-Time Peer Gamepad Input Mirroring (Zero-Flicker Architecture)
# Controls: Only HOLD [START + SELECT] exits the script.
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

# ------------------------------------------------------------------------------
# ANSI Color Palette (Raw literals for pure bash compatibility)
# ------------------------------------------------------------------------------
C_RESET="\033[0m"
C_CYAN="\033[1;36m"
C_GREEN="\033[1;32m"
C_YELLOW="\033[1;33m"
C_RED="\033[1;31m"
C_WHITE="\033[1;37m"
C_GRAY="\033[0;37m"

STATE_DIR="/tmp/c2c_state"
INPUT_PIPE="$STATE_DIR/remote_input.txt"
DAEMON_PID_FILE="$STATE_DIR/input_daemon.pid"
EXIT_FLAG="$STATE_DIR/exit_flag"

mkdir -p "$STATE_DIR" 2>/dev/null
rm -f "$EXIT_FLAG" 2>/dev/null

# ------------------------------------------------------------------------------
# Cleanup on Exit
# ------------------------------------------------------------------------------
cleanup() {
    if [ -f "$DAEMON_PID_FILE" ]; then
        sudo kill -9 "$(cat "$DAEMON_PID_FILE" 2>/dev/null)" 2>/dev/null
        rm -f "$DAEMON_PID_FILE" 2>/dev/null
    fi
    sudo pkill -f "c2c_input_daemon.py" 2>/dev/null
    rm -rf "$STATE_DIR" 2>/dev/null
    printf "\033[?25h" 2>/dev/null # Restore cursor
    clear 2>/dev/null
}
trap cleanup EXIT INT TERM

# ------------------------------------------------------------------------------
# Helper: Detect Local Console Role (Host vs Peripheral)
# ------------------------------------------------------------------------------
detect_role() {
    if [ -f /proc/device-tree/usb@ff300000/dr_mode ] && grep -q "host" /proc/device-tree/usb@ff300000/dr_mode 2>/dev/null; then
        RUN_MODE="host"
    elif [ -f /proc/device-tree/usb@ff300000/dr_mode ] && grep -q "peripheral" /proc/device-tree/usb@ff300000/dr_mode 2>/dev/null; then
        RUN_MODE="peripheral"
    elif [ -f /boot/rk3326-g350-host.dtb ] && cmp -s /boot/rk3326-g350-linux.dtb /boot/rk3326-g350-host.dtb; then
        RUN_MODE="host"
    else
        RUN_MODE="peripheral"
    fi

    if [ "$RUN_MODE" == "host" ]; then
        LOCAL_ROLE="HOST"
        LOCAL_IP="192.168.10.1"
        PEER_ROLE="PERIPHERAL"
        PEER_IP="192.168.10.2"
        TARGET_ROLE_STR="${C_YELLOW}[HOST]${C_RESET} ${C_WHITE}(192.168.10.1)${C_RESET}"
        PEER_ROLE_STR="${C_GREEN}[PERIPHERAL]${C_RESET} ${C_GRAY}(192.168.10.2)${C_RESET}"
    else
        LOCAL_ROLE="PERIPHERAL"
        LOCAL_IP="192.168.10.2"
        PEER_ROLE="HOST"
        PEER_IP="192.168.10.1"
        TARGET_ROLE_STR="${C_GREEN}[PERIPHERAL]${C_RESET} ${C_WHITE}(192.168.10.2)${C_RESET}"
        PEER_ROLE_STR="${C_YELLOW}[HOST]${C_RESET} ${C_GRAY}(192.168.10.1)${C_RESET}"
    fi
}

# ------------------------------------------------------------------------------
# Helper: Locate Network Interface (usb0 or host ethernet adapter)
# ------------------------------------------------------------------------------
find_interface() {
    IFACE=""
    if [ -d "/sys/class/net/usb0" ]; then
        IFACE="usb0"
    else
        for dev in /sys/class/net/*; do
            dname=$(basename "$dev")
            if [ "$dname" != "lo" ] && [ "$dname" != "wlan0" ] && [ "$dname" != "eth0" ]; then
                IFACE="$dname"
                break
            fi
        done
    fi
    [ -z "$IFACE" ] && IFACE="usb0"
}

# ------------------------------------------------------------------------------
# Helper: Ensure Network Interface and C2C Static IP are Bound
# ------------------------------------------------------------------------------
setup_network() {
    find_interface

    if [ "$LOCAL_ROLE" == "PERIPHERAL" ]; then
        if ! lsmod | grep -q "g_ether"; then
            sudo modprobe g_ether 2>/dev/null
            sleep 0.2
            find_interface
        fi
    fi

    sudo ip link set "$IFACE" up 2>/dev/null

    claim_interface
    ensure_ip
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
    ip -4 addr show dev "$IFACE" 2>/dev/null | grep -q "inet ${LOCAL_IP}/" \
        || sudo ip addr add "${LOCAL_IP}/24" dev "$IFACE" 2>/dev/null
    ip route 2>/dev/null | grep -q "^192.168.10.0/24 dev $IFACE" \
        || sudo ip route replace 192.168.10.0/24 dev "$IFACE" 2>/dev/null
}

# ------------------------------------------------------------------------------
# Helper: Check Physical Carrier Link (Instant, Non-blocking)
# ------------------------------------------------------------------------------
check_carrier() {
    find_interface
    CARRIER="0"
    if [ -f "/sys/class/net/$IFACE/carrier" ]; then
        CARRIER=$(cat "/sys/class/net/$IFACE/carrier" 2>/dev/null)
    fi

    if [ "$CARRIER" = "1" ]; then
        STATUS_LINK="${C_GREEN}CONNECTED [CARRIER OK]${C_RESET}"
        IS_LINK_UP=1
    else
        STATUS_LINK="${C_RED}NO LINK (Check OTG Cable)${C_RESET}"
        IS_LINK_UP=0
    fi
}

# ------------------------------------------------------------------------------
# Helper: Fast ICMP Ping Test (Strictly Capped Timeout: Max 350ms)
# ------------------------------------------------------------------------------
check_ping() {
    if [ "$IS_LINK_UP" -ne 1 ]; then
        STATUS_PING="${C_GRAY}OFFLINE (Cable disconnected)${C_RESET}"
        STATUS_RTT="${C_GRAY}N/A (No Link)${C_RESET}"
        IS_PING_OK=0
        return
    fi

    if command -v timeout >/dev/null 2>&1; then
        PING_OUT=$(timeout 0.35 ping -c 1 -W 1 "$PEER_IP" 2>&1)
        PING_CODE=$?
    else
        PING_OUT=$(ping -c 1 -W 1 "$PEER_IP" 2>&1)
        PING_CODE=$?
    fi

    if [ "$PING_CODE" -eq 0 ]; then
        AVG_RTT=$(echo "$PING_OUT" | awk -F '/' '/rtt|round-trip/ {print $5}')
        STATUS_PING="${C_GREEN}0% LOSS [LINK OK]${C_RESET}"
        STATUS_RTT="${C_GREEN}${AVG_RTT:-0.35} ms (Sub-ms Wired)${C_RESET}"
        IS_PING_OK=1
    else
        STATUS_PING="${C_RED}UNREACHABLE (100% loss)${C_RESET}"
        STATUS_RTT="${C_GRAY}N/A (Peer offline)${C_RESET}"
        IS_PING_OK=0
    fi
}

# ------------------------------------------------------------------------------
# Helper: Fast Probe of TCP Services (Strictly Capped Timeout: Max 200ms)
# ------------------------------------------------------------------------------
check_services() {
    if [ "$IS_PING_OK" -ne 1 ]; then
        STATUS_SSH="${C_GRAY}OFFLINE${C_RESET}"
        STATUS_NETPLAY="${C_GRAY}OFFLINE${C_RESET}"
        return
    fi

    if command -v timeout >/dev/null 2>&1; then
        timeout 0.2 bash -c '(exec 3<>/dev/tcp/'"$PEER_IP"'/22) 2>/dev/null'
        [ "$?" -eq 0 ] && STATUS_SSH="${C_GREEN}Port 22 (ark/ark) [READY]${C_RESET}" || STATUS_SSH="${C_YELLOW}Port 22 [NOT STARTED]${C_RESET}"
    else
        (exec 3<>/dev/tcp/$PEER_IP/22) 2>/dev/null && STATUS_SSH="${C_GREEN}Port 22 (ark/ark) [READY]${C_RESET}" || STATUS_SSH="${C_YELLOW}Port 22 [NOT STARTED]${C_RESET}"
        exec 3<&- 2>/dev/null
        exec 3>&- 2>/dev/null
    fi

    if command -v timeout >/dev/null 2>&1; then
        timeout 0.2 bash -c '(exec 3<>/dev/tcp/'"$PEER_IP"'/55435) 2>/dev/null'
        [ "$?" -eq 0 ] && STATUS_NETPLAY="${C_GREEN}Port 55435 [READY]${C_RESET}" || STATUS_NETPLAY="${C_GRAY}Port 55435 [IDLE/READY]${C_RESET}"
    else
        (exec 3<>/dev/tcp/$PEER_IP/55435) 2>/dev/null && STATUS_NETPLAY="${C_GREEN}Port 55435 [READY]${C_RESET}" || STATUS_NETPLAY="${C_GRAY}Port 55435 [IDLE/READY]${C_RESET}"
        exec 3<&- 2>/dev/null
        exec 3>&- 2>/dev/null
    fi
}

# ------------------------------------------------------------------------------
# Helper: Embedded Python Background Input Streamer & Receiver Daemon
# - Precise RK3326 odroidgo2-joypad mapping (D-Pad = buttons 6-9, Joy = axes 0-1)
# - Shoulder buttons (L1=4, R1=5, L2=11, R2=14)
# - Pure ASCII string formatting with literal ANSI ESC bytes (Zero Sed / Zero mangling)
# - Only HOLD [START + SELECT] creates the exit flag
# ------------------------------------------------------------------------------
start_input_daemon() {
    if pgrep -f "c2c_input_daemon.py" >/dev/null 2>&1; then
        return
    fi

    cat << 'EOF' > "$STATE_DIR/c2c_input_daemon.py"
import sys, os, time, socket, select, struct, glob

PEER_IP = sys.argv[1] if len(sys.argv) > 1 else "192.168.10.1"
LOCAL_IP = sys.argv[2] if len(sys.argv) > 2 else "0.0.0.0"
UDP_PORT = 5005
OUT_FILE = "/tmp/c2c_state/remote_input.txt"
EXIT_FILE = "/tmp/c2c_state/exit_flag"

# Raw ANSI escape literals (0x1B) for clean terminal rendering
C_RESET = "\x1b[0m"
C_GREEN = "\x1b[1;32m"
C_RED   = "\x1b[1;31m"
C_CYAN  = "\x1b[1;36m"
C_YEL   = "\x1b[1;33m"
C_GRAY  = "\x1b[0;37m"

EV_FMT = "llHHi"
EV_SIZE = struct.calcsize(EV_FMT)

js_dev = None
for path in ["/dev/input/js0", "/dev/input/js1"]:
    if os.path.exists(path):
        try:
            js_dev = open(path, "rb")
            os.set_blocking(js_dev.fileno(), False)
            break
        except:
            pass

ev_devs = []
for p in sorted(glob.glob("/dev/input/event*")):
    try:
        f = open(p, "rb", buffering=0)
        os.set_blocking(f.fileno(), False)
        ev_devs.append((p, f))
    except Exception:
        pass

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
try:
    sock.bind((LOCAL_IP, UDP_PORT))
except:
    sock.bind(("0.0.0.0", UDP_PORT))
sock.setblocking(False)

# Button State Tracking (ODROID-GO Advance / RK3326 standard)
# Face buttons: b0=B, b1=A, b2=Y, b3=X
# Shoulders   : b4=L1, b5=R1, b11=L2, b14=R2
# D-Pad       : b6=Up, b7=Down, b8=Left, b9=Right
# Options     : b10=Select, b15=Start
# Joystick    : a0=LeftX, a1=LeftY
buttons = {
    "A": 0, "B": 0, "X": 0, "Y": 0,
    "DP_U": 0, "DP_D": 0, "DP_L": 0, "DP_R": 0,
    "L1": 0, "R1": 0, "L2": 0, "R2": 0,
    "SEL": 0, "STA": 0,
    "JOY_U": 0, "JOY_D": 0, "JOY_L": 0, "JOY_R": 0
}

last_send = 0
last_write = 0
peer_pulse = 0

while True:
    now = time.time()

    # 1. Read local hardware gamepad events
    if js_dev:
        try:
            while True:
                data = js_dev.read(8) # 8-byte JS struct: time(4), value(2), type(1), number(1)
                if not data or len(data) < 8:
                    break
                _, val, ev_type, num = struct.unpack("IhBB", data)
                clean_type = ev_type & ~0x80 # strip JS_EVENT_INIT

                # Button Events
                if clean_type == 0x01:
                    is_down = 1 if val != 0 else 0
                    if num == 0: buttons["B"] = is_down
                    elif num == 1: buttons["A"] = is_down
                    elif num == 2: buttons["Y"] = is_down
                    elif num == 3: buttons["X"] = is_down
                    elif num == 4: buttons["L1"] = is_down
                    elif num == 5: buttons["R1"] = is_down
                    elif num == 6: buttons["DP_U"] = is_down
                    elif num == 7: buttons["DP_D"] = is_down
                    elif num == 8: buttons["DP_L"] = is_down
                    elif num == 9: buttons["DP_R"] = is_down
                    elif num == 10: buttons["SEL"] = is_down
                    elif num == 11: buttons["L2"] = is_down
                    elif num == 14: buttons["R2"] = is_down
                    elif num == 15: buttons["STA"] = is_down

                # Axis Events (Analog Joystick and optional analog triggers)
                elif clean_type == 0x02:
                    if num == 0: # Left Stick X
                        buttons["JOY_L"] = 1 if val < -12000 else 0
                        buttons["JOY_R"] = 1 if val > 12000 else 0
                    elif num == 1: # Left Stick Y
                        buttons["JOY_U"] = 1 if val < -12000 else 0
                        buttons["JOY_D"] = 1 if val > 12000 else 0
                    elif num == 2: # L2 if analog
                        if val > 12000: buttons["L2"] = 1
                        elif val < 4000 and num != 11: buttons["L2"] = 0
                    elif num == 5: # R2 if analog
                        if val > 12000: buttons["R2"] = 1
                        elif val < 4000 and num != 14: buttons["R2"] = 0
        except:
            pass

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
                if code in (314, 704): buttons["SEL"] = val
                elif code in (315, 705): buttons["STA"] = val

    # 2. ONLY [START + SELECT] triggers exit
    if buttons["SEL"] == 1 and buttons["STA"] == 1:
        try:
            with open(EXIT_FILE, "w") as f:
                f.write("1\n")
        except:
            pass

    # 3. Transmit button bitmask at ~30Hz (every 33ms)
    if now - last_send >= 0.033:
        mask = 0
        if buttons["A"]:     mask |= (1 << 0)
        if buttons["B"]:     mask |= (1 << 1)
        if buttons["X"]:     mask |= (1 << 2)
        if buttons["Y"]:     mask |= (1 << 3)
        if buttons["DP_U"]:  mask |= (1 << 4)
        if buttons["DP_D"]:  mask |= (1 << 5)
        if buttons["DP_L"]:  mask |= (1 << 6)
        if buttons["DP_R"]:  mask |= (1 << 7)
        if buttons["L1"]:    mask |= (1 << 8)
        if buttons["R1"]:    mask |= (1 << 9)
        if buttons["L2"]:    mask |= (1 << 10)
        if buttons["R2"]:    mask |= (1 << 11)
        if buttons["SEL"]:   mask |= (1 << 12)
        if buttons["STA"]:   mask |= (1 << 13)
        if buttons["JOY_U"]: mask |= (1 << 14)
        if buttons["JOY_D"]: mask |= (1 << 15)
        if buttons["JOY_L"]: mask |= (1 << 16)
        if buttons["JOY_R"]: mask |= (1 << 17)

        payload = f"C2C:{mask}".encode("ascii")
        try:
            sock.sendto(payload, (PEER_IP, UDP_PORT))
        except:
            pass
        last_send = now

    # 4. Receive incoming packets from peer
    r, _, _ = select.select([sock], [], [], 0.015)
    if r:
        try:
            raw, addr = sock.recvfrom(64)
            msg = raw.decode("ascii", errors="ignore").strip()
            if msg.startswith("C2C:"):
                pmask = int(msg.split(":")[1])
                peer_pulse = (peer_pulse + 1) % 2

                # Format Row 1: DPAD and BTNS (Length <= 40 chars)
                d_u = f"{C_GREEN}[U]{C_RESET}" if (pmask & (1 << 4)) else "[ ]"
                d_d = f"{C_GREEN}[D]{C_RESET}" if (pmask & (1 << 5)) else "[ ]"
                d_l = f"{C_GREEN}[L]{C_RESET}" if (pmask & (1 << 6)) else "[ ]"
                d_r = f"{C_GREEN}[R]{C_RESET}" if (pmask & (1 << 7)) else "[ ]"

                b_a = f"{C_GREEN}[A]{C_RESET}" if (pmask & (1 << 0)) else "[ ]"
                b_b = f"{C_RED}[B]{C_RESET}"   if (pmask & (1 << 1)) else "[ ]"
                b_x = f"{C_CYAN}[X]{C_RESET}"  if (pmask & (1 << 2)) else "[ ]"
                b_y = f"{C_YEL}[Y]{C_RESET}"   if (pmask & (1 << 3)) else "[ ]"

                line1 = f"DPAD: {d_u}{d_d}{d_l}{d_r}   BTNS: {b_a}{b_b}{b_x}{b_y}"

                # Format Row 2: TRIGGERS and OPTIONS
                t_l1 = f"{C_CYAN}[L1]{C_RESET}" if (pmask & (1 << 8)) else "[  ]"
                t_r1 = f"{C_CYAN}[R1]{C_RESET}" if (pmask & (1 << 9)) else "[  ]"
                t_l2 = f"{C_CYAN}[L2]{C_RESET}" if (pmask & (1 << 10)) else "[  ]"
                t_r2 = f"{C_CYAN}[R2]{C_RESET}" if (pmask & (1 << 11)) else "[  ]"

                o_sel = f"{C_YEL}[SEL]{C_RESET}" if (pmask & (1 << 12)) else "[   ]"
                o_sta = f"{C_GREEN}[STA]{C_RESET}" if (pmask & (1 << 13)) else "[   ]"

                line2 = f"TRIG: {t_l1}{t_r1}{t_l2}{t_r2}  OPTS: {o_sel}{o_sta}"

                # Format Row 3: JOYSTICK and STREAM
                j_u = f"{C_YEL}[U]{C_RESET}" if (pmask & (1 << 14)) else "[ ]"
                j_d = f"{C_YEL}[D]{C_RESET}" if (pmask & (1 << 15)) else "[ ]"
                j_l = f"{C_YEL}[L]{C_RESET}" if (pmask & (1 << 16)) else "[ ]"
                j_r = f"{C_YEL}[R]{C_RESET}" if (pmask & (1 << 17)) else "[ ]"

                pulse_icon = "*" if peer_pulse else "o"
                line3 = f"JOY : {j_u}{j_d}{j_l}{j_r}   STREAM: {C_GREEN}LIVE ({pulse_icon}){C_RESET}"

                with open(OUT_FILE + ".tmp", "w", encoding="utf-8") as f:
                    f.write(f"{line1}\n{line2}\n{line3}\n")
                os.replace(OUT_FILE + ".tmp", OUT_FILE)
                last_write = now
        except:
            pass

    # Clear display if peer has disconnected for > 1.5s
    if now - last_write > 1.5:
        line1 = "DPAD: [ ][ ][ ][ ]   BTNS: [ ][ ][ ][ ]"
        line2 = "TRIG: [  ][  ][  ][  ]  OPTS: [   ][   ]"
        line3 = f"JOY : [ ][ ][ ][ ]   STREAM: {C_GRAY}WAITING FOR PEER...{C_RESET}"
        try:
            with open(OUT_FILE, "w", encoding="utf-8") as f:
                f.write(f"{line1}\n{line2}\n{line3}\n")
        except:
            pass

    time.sleep(0.01)
EOF

    if command -v python3 >/dev/null 2>&1; then
        sudo python3 "$STATE_DIR/c2c_input_daemon.py" "$PEER_IP" "$LOCAL_IP" >/dev/null 2>&1 &
        echo $! > "$DAEMON_PID_FILE"
    fi
}

# ------------------------------------------------------------------------------
# Helper: Fast Pure-Bash Input Reader (Zero Sed / Zero Character Distortion)
# ------------------------------------------------------------------------------
read_peer_input_display() {
    INPUT_LINE_1="DPAD: [ ][ ][ ][ ]   BTNS: [ ][ ][ ][ ]"
    INPUT_LINE_2="TRIG: [  ][  ][  ][  ]  OPTS: [   ][   ]"
    INPUT_LINE_3="JOY : [ ][ ][ ][ ]   STREAM: WAITING FOR PEER..."

    if [ -s "$INPUT_PIPE" ]; then
        {
            read -r INPUT_LINE_1
            read -r INPUT_LINE_2
            read -r INPUT_LINE_3
        } < "$INPUT_PIPE" 2>/dev/null
    fi
}

# ------------------------------------------------------------------------------
# Helper: Check Exit Combinations
# ONLY [START + SELECT] triggers exit. No single button press exits.
# ------------------------------------------------------------------------------
check_exit_combo() {
    # 1. Check Python daemon hardware flag (START + SELECT held together)
    if [ -f "$EXIT_FLAG" ]; then
        return 0
    fi

    # 2. Check ArkOS buttonmon Start + Select Combo
    if type Test_Button_Start >/dev/null 2>&1 && type Test_Button_Select >/dev/null 2>&1; then
        Test_Button_Start
        local s_code=$?
        Test_Button_Select
        local sel_code=$?
        if [ "$s_code" -eq "10" ] && [ "$sel_code" -eq "10" ]; then
            return 0
        fi
    fi

    return 1
}

# ------------------------------------------------------------------------------
# Helper: Render Full Dashboard (Zero-Flicker in-place redraw via ANSI Home)
# Strictly 16 lines, max 42 columns
# ------------------------------------------------------------------------------
draw_dashboard() {
    printf "\033[H" 2>/dev/null # Move cursor to row 1, col 1
    read_peer_input_display

    echo -e "${C_CYAN}==========================================${C_RESET}\033[K"
    echo -e "${C_WHITE}   C2C DIRECT USB CONNECTION CHECKER      ${C_RESET}\033[K"
    echo -e "${C_CYAN}==========================================${C_RESET}\033[K"
    echo -e " ${C_WHITE}LOCAL ROLE :${C_RESET} $TARGET_ROLE_STR\033[K"
    echo -e " ${C_WHITE}PEER ROLE  :${C_RESET} $PEER_ROLE_STR\033[K"
    echo -e " ${C_WHITE}CABLE LINK :${C_RESET} $STATUS_LINK\033[K"
    echo -e " ${C_WHITE}PING / RTT :${C_RESET} $STATUS_RTT\033[K"
    echo -e " ${C_WHITE}SSH / SFTP :${C_RESET} $STATUS_SSH\033[K"
    echo -e "${C_CYAN}------------------------------------------${C_RESET}\033[K"
    echo -e " ${C_WHITE}PEER GAMEPAD INPUT (Live from Remote):${C_RESET}\033[K"
    printf " %s\033[K\n" "$INPUT_LINE_1"
    printf " %s\033[K\n" "$INPUT_LINE_2"
    printf " %s\033[K\n" "$INPUT_LINE_3"
    echo -e "${C_CYAN}------------------------------------------${C_RESET}\033[K"
    echo -e " ${C_RED}EXIT COMBO: HOLD [START + SELECT]${C_RESET}\033[K"
    echo -e "${C_CYAN}==========================================${C_RESET}\033[K"
}

# ------------------------------------------------------------------------------
# Helper: Run Full Diagnostics Update (Non-blocking)
# ------------------------------------------------------------------------------
refresh_diagnostics() {
    detect_role
    setup_network
    check_carrier
    check_ping
    check_services
    start_input_daemon
    draw_dashboard
}

# ------------------------------------------------------------------------------
# Main Application Initialization
# ------------------------------------------------------------------------------
clear 2>/dev/null
printf "\033[?25l" 2>/dev/null # Hide cursor

# Initial Diagnostics Check
refresh_diagnostics

# ------------------------------------------------------------------------------
# Continuous Interactive Loop (Zero-flicker 25-30Hz input polling)
# ------------------------------------------------------------------------------
FRAME_COUNT=0
LAST_CARRIER="$IS_LINK_UP"

while true; do
    FRAME_COUNT=$((FRAME_COUNT + 1))

    # 1. Check Exit: ONLY [START + SELECT] triggers exit
    if check_exit_combo; then
        cleanup
        exit 0
    fi

    # 2. Check Terminal Input (Only Ctrl+C / Ctrl+D signals break)
    read -t 0.035 -n 1 key 2>/dev/null
    case "$key" in
        $'\x03'|$'\x04')
            cleanup
            exit 0
            ;;
    esac

    # 3. Refresh Peer Input In-Place (Lines 11, 12, 13) with zero sed
    read_peer_input_display
    printf "\033[11;1H %s\033[K\n %s\033[K\n %s\033[K\n" "$INPUT_LINE_1" "$INPUT_LINE_2" "$INPUT_LINE_3"

    # 4. Periodic Link Check (Every ~5 seconds without screen wipe)
    if [ "$FRAME_COUNT" -ge 140 ]; then
        FRAME_COUNT=0
        find_interface
        ensure_ip
        CURR_CARRIER="0"
        [ -f "/sys/class/net/$IFACE/carrier" ] && CURR_CARRIER=$(cat "/sys/class/net/$IFACE/carrier" 2>/dev/null)
        LAST_CARRIER="$CURR_CARRIER"
        refresh_diagnostics
    fi
done
