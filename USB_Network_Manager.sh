#!/bin/bash
# ==============================================================================
# Script: USB_Network_Manager.sh
# Device: Battle XP G350 / RK3326 Handhelds (dArkOS / ArkOS)
# Layout: Tailored for 3.5" Handhelds (Max 44 cols x 16 rows, zero overflow)
# ==============================================================================

# Machine-callable modes (--refresh-net / --set-gateway) must not touch the
# console TTY or emit TUI escape codes. Detect them before anything else runs.
G350_CLI_MODE=0
case "${1:-}" in
    --refresh-net|--set-gateway) G350_CLI_MODE=1 ;;
esac

# Direct output to physical display if launched from EmulationStation
if [ -z "$SSH_CONNECTION" ] && [ "$G350_CLI_MODE" -ne 1 ]; then
    for tty in /dev/tty0 /dev/tty1; do
        if [ -e "$tty" ]; then
            sudo chmod 666 "$tty" 2>/dev/null
            exec > "$tty" 2>&1
            break
        fi
    done
fi

# Set clean console font if available (TUI only)
if [ "$G350_CLI_MODE" -ne 1 ] && [ -f /usr/share/consolefonts/Lat7-TerminusBold28x14.psf.gz ]; then
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

# Persistent state for DNS preservation (survives reboot until explicitly restored)
STATE_DIR="/var/lib/usb_network_manager"
RESOLV_CONF="/etc/resolv.conf"
RESOLV_BAK="$STATE_DIR/resolv.conf.bak"
RESOLV_LINK="$STATE_DIR/resolv.conf.symlink"
RESOLV_ABSENT="$STATE_DIR/resolv.conf.absent"

# Non-blocking cached probe files (keep the menu responsive)
PROBE_FILE="/tmp/usb_net_mgr_probe"
PROBE_LOCK="/tmp/usb_net_mgr_probe.lock"

# Populated by detect_status() and refresh_usb_network()
ACTIVE_IP="${ACTIVE_IP:-}"
ACTIVE_GW="${ACTIVE_GW:-}"

cleanup() {
    sudo pkill -f "usb_mgr_btn_watch.py" 2>/dev/null
    rm -rf /tmp/usb_net_mgr 2>/dev/null
    rm -f "$PROBE_LOCK" 2>/dev/null
    # Cursor-restore is for the on-device TUI only; a machine caller
    # (--refresh-net) wants clean, parseable output.
    [ "${G350_CLI_MODE:-0}" -eq 1 ] || printf "\033[?25h" 2>/dev/null
}
trap cleanup EXIT INT TERM

# ------------------------------------------------------------------------------
# Helper: Preserve the user's original DNS configuration exactly once per session
# Handles all three real-world cases: regular file, symlink, or absent file.
# ------------------------------------------------------------------------------
backup_resolv_conf() {
    # Already backed up -> never overwrite the pristine copy
    if sudo test -f "$RESOLV_BAK" 2>/dev/null \
        || sudo test -f "$RESOLV_LINK" 2>/dev/null \
        || sudo test -f "$RESOLV_ABSENT" 2>/dev/null; then
        return 0
    fi

    sudo mkdir -p "$STATE_DIR" 2>/dev/null

    if [ -L "$RESOLV_CONF" ]; then
        # Preserve the symlink target so we can recreate it on restore
        readlink "$RESOLV_CONF" 2>/dev/null | sudo tee "$RESOLV_LINK" >/dev/null 2>&1
    elif [ -f "$RESOLV_CONF" ]; then
        sudo cp -p "$RESOLV_CONF" "$RESOLV_BAK" 2>/dev/null
    else
        # File did not exist at all: remember that so restore removes ours
        sudo touch "$RESOLV_ABSENT" 2>/dev/null
    fi
}

# ------------------------------------------------------------------------------
# Helper: Put the user's DNS configuration back the way we found it
# ------------------------------------------------------------------------------
restore_resolv_conf() {
    local restored=1

    if sudo test -f "$RESOLV_LINK" 2>/dev/null; then
        local target
        target=$(sudo cat "$RESOLV_LINK" 2>/dev/null)
        sudo rm -f "$RESOLV_CONF" 2>/dev/null
        [ -n "$target" ] && sudo ln -sfn "$target" "$RESOLV_CONF" 2>/dev/null
        restored=0
    elif sudo test -f "$RESOLV_BAK" 2>/dev/null; then
        sudo cp -p "$RESOLV_BAK" "$RESOLV_CONF" 2>/dev/null
        restored=0
    elif sudo test -f "$RESOLV_ABSENT" 2>/dev/null; then
        sudo rm -f "$RESOLV_CONF" 2>/dev/null
        restored=0
    fi

    sudo rm -f "$RESOLV_LINK" "$RESOLV_BAK" "$RESOLV_ABSENT" 2>/dev/null
    return $restored
}

# ------------------------------------------------------------------------------
# Helper: Non-blocking cached reachability probe
# The ping runs in the background so the UI never stalls waiting on a dead link.
# ------------------------------------------------------------------------------
probe_start() {
    [ -f "$PROBE_LOCK" ] && return 0
    : > "$PROBE_LOCK" 2>/dev/null
    (
        res="FAIL"
        if ping -c 1 -W 1 "$1" >/dev/null 2>&1; then
            res="OK"
        fi
        printf '%s %s\n' "$res" "$(date +%s)" > "$PROBE_FILE.tmp" 2>/dev/null
        mv -f "$PROBE_FILE.tmp" "$PROBE_FILE" 2>/dev/null
        rm -f "$PROBE_LOCK" 2>/dev/null
    ) &
}

probe_read() {
    local res ts now
    res=""
    ts=0
    if [ -f "$PROBE_FILE" ]; then
        read -r res ts _ < "$PROBE_FILE" 2>/dev/null
    fi
    now=$(date +%s)
    case "$ts" in ''|*[!0-9]*) ts=0 ;; esac

    # Refresh in the background when the cached result is missing or stale
    if [ -z "$res" ] || [ $((now - ts)) -gt 3 ]; then
        probe_start "$1"
    fi

    printf '%s' "$res"
}

# ------------------------------------------------------------------------------
# Helper: Auto-Generate / Ensure DTB Hardware Profiles on First Run
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

# ------------------------------------------------------------------------------
# Helper: Detect Current USB & Network Status
# ------------------------------------------------------------------------------
detect_status() {
    # Only ensure the profiles once per run: the DTB comparison is cheap but this
    # runs on every ~4s auto-refresh, and a missing-python regeneration attempt
    # would otherwise be repeated on each redraw.
    if [ "${DTB_PROFILES_OK:-0}" -ne 1 ]; then
        ensure_dtb_profiles && DTB_PROFILES_OK=1
    fi

    # 1. Detect Running Kernel Hardware Mode
    # On factory firmware, dr_mode="otg" and DWC2 creates /sys/class/udc, but physical
    # default is Host mode. Hardware is ONLY peripheral if dr_mode is explicitly "peripheral".
    if [ -f /proc/device-tree/usb@ff300000/dr_mode ] && grep -aq "peripheral" /proc/device-tree/usb@ff300000/dr_mode 2>/dev/null; then
        RUN_MODE="peripheral"
    elif [ -f /sys/firmware/devicetree/base/usb@ff300000/dr_mode ] && grep -aq "peripheral" /sys/firmware/devicetree/base/usb@ff300000/dr_mode 2>/dev/null; then
        RUN_MODE="peripheral"
    elif [ ! -f /proc/device-tree/usb@ff300000/dr_mode ] && [ -f /boot/rk3326-g350-peripheral.dtb ] && cmp -s /boot/rk3326-g350-linux.dtb /boot/rk3326-g350-peripheral.dtb; then
        # Fallback if procfs devicetree is unavailable: check if active boot DTB is peripheral
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
        # Factory stock DTB (dr_mode="otg") or unconfigured defaults to Host mode
        BOOT_MODE="host"
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

    # Check Default Gateway & Active Subnet IP (pure-bash, immune to Broken Pipe)
    RAW_GW=$(ip route 2>/dev/null | awk '/default/ {print $3; exit}')
    ALL_IPS=$(ip -4 addr show dev usb0 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | grep -v '^169\.254\.')
    ALL_IPS=$(printf '%s\n' "$ALL_IPS" | tr '\n' ' ')

    if [ "$RAW_GW" = "192.168.137.1" ] && [[ "$ALL_IPS" =~ (^|[[:space:]])192\.168\.137\.2($|[[:space:]]) ]]; then
        ACTIVE_IP="192.168.137.2"
    elif [ "$RAW_GW" = "192.168.7.1" ] && [[ "$ALL_IPS" =~ (^|[[:space:]])192\.168\.7\.2($|[[:space:]]) ]]; then
        ACTIVE_IP="192.168.7.2"
    elif [[ "$ALL_IPS" =~ (^|[[:space:]])192\.168\.137\.2($|[[:space:]]) ]]; then
        ACTIVE_IP="192.168.137.2"
    elif [[ "$ALL_IPS" =~ (^|[[:space:]])192\.168\.7\.2($|[[:space:]]) ]]; then
        ACTIVE_IP="192.168.7.2"
    else
        read -r ACTIVE_IP <<< "$ALL_IPS"
    fi

    if [ -z "$ACTIVE_IP" ]; then
        STATUS_IP="${C_GRAY}Disconnected${C_RESET}"
    else
        STATUS_IP="${C_GREEN}$ACTIVE_IP (usb0)${C_RESET}"
    fi

    if [ -z "$RAW_GW" ]; then
        STATUS_GW="${C_GRAY}None${C_RESET}"
    else
        STATUS_GW="${C_WHITE}$RAW_GW (Online)${C_RESET}"
    fi

    # Check SSH Server
    if ssh_listening; then
        STATUS_SSH="${C_GREEN}Port 22 (ark/ark) [RUNNING]${C_RESET}"
    else
        STATUS_SSH="${C_RED}STOPPED${C_RESET}"
    fi

    # Check Samba Server (matched to active console IP)
    if pgrep smbd >/dev/null 2>&1; then
        SAMBA_IP="${ACTIVE_IP:-192.168.7.2}"
        STATUS_SAMBA="${C_GREEN}\\\\${SAMBA_IP}\\roms [OK]${C_RESET}"
    else
        STATUS_SAMBA="${C_GRAY}INACTIVE${C_RESET}"
    fi

    # Check Internet Connectivity without ever blocking the menu:
    # the ping is fired in the background and the last cached verdict is shown.
    if [ -n "$RAW_GW" ] && [ -n "$ACTIVE_IP" ] && [ "$(probe_read 8.8.8.8)" = "OK" ]; then
        STATUS_NET="${C_GREEN}ONLINE (PortMaster Ready)${C_RESET}"
    else
        STATUS_NET="${C_GRAY}OFFLINE${C_RESET}"
    fi
}

# ------------------------------------------------------------------------------
# Helper: Draw Main Interactive Menu (strictly 14 rows, max 42 cols)
# ------------------------------------------------------------------------------
draw_menu() {
    if [ "$1" == "refresh" ]; then
        printf "\033[H" 2>/dev/null
    else
        printf "\033c" 2>/dev/null
        clear 2>/dev/null
    fi
    detect_status

    echo -e "${C_CYAN}==========================================${C_RESET}\033[K"
    echo -e "${C_WHITE} BATTLE XP G350 - USB NETWORK MANAGER ${C_RESET}\033[K"
    echo -e "${C_CYAN}==========================================${C_RESET}\033[K"
    echo -e " ${C_WHITE}USB MODE :${C_RESET} $STATUS_MODE\033[K"
    echo -e " ${C_WHITE}IP ADDR  :${C_RESET} $STATUS_IP\033[K"
    echo -e " ${C_WHITE}GATEWAY  :${C_RESET} $STATUS_GW\033[K"
    echo -e " ${C_WHITE}SSH/SFTP :${C_RESET} $STATUS_SSH\033[K"
    echo -e " ${C_WHITE}SAMBA    :${C_RESET} $STATUS_SAMBA\033[K"
    echo -e " ${C_WHITE}INTERNET :${C_RESET} $STATUS_NET\033[K"
    echo -e "${C_CYAN}------------------------------------------${C_RESET}\033[K"
    echo -e " $START_TEXT\033[K"
    echo -e " ${C_RED}[Y]${C_RESET} ${C_WHITE}Stop Services (Save Battery)[Instant]${C_RESET}\033[K"
    echo -e " ${C_YELLOW}[X]${C_RESET} ${C_WHITE}$SWITCH_TEXT${C_RESET}\033[K"
    echo -e " ${C_CYAN}[B]${C_RESET} ${C_WHITE}Exit to EmulationStation${C_RESET}\033[K"
}

# ------------------------------------------------------------------------------
# Helper: Kill every sshd EXCEPT the process that owns our own SSH session.
# Killing our own sshd detaches the session with 'Broken pipe' whenever this tool
# is driven over SSH while tethered.
# ------------------------------------------------------------------------------
kill_sshd_except_self() {
    local keep=""
    if [ -n "$SSH_CONNECTION" ] && [ -n "$PPID" ]; then
        # Walk up from our parent shell to the sshd that spawned the session
        local p="$PPID"
        local depth=0
        while [ -n "$p" ] && [ "$p" -gt 1 ] && [ "$depth" -lt 10 ]; do
            if [ "$(cat "/proc/$p/comm" 2>/dev/null)" = "sshd" ]; then
                keep="$p"
                break
            fi
            p=$(awk '{print $4}' "/proc/$p/stat" 2>/dev/null)
            depth=$((depth + 1))
        done
    fi

    if [ -z "$keep" ]; then
        sudo killall -9 sshd 2>/dev/null
        return 0
    fi

    local pid
    for pid in $(pgrep -x sshd 2>/dev/null); do
        [ "$pid" = "$keep" ] && continue
        sudo kill -9 "$pid" 2>/dev/null
    done
}

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
    kill_sshd_except_self
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

# ------------------------------------------------------------------------------
# Helper: Re-apply usb0 addressing and default route WITHOUT tearing anything down
#
# Used when the PC end changes address while we are running, most importantly when
# Windows Internet Connection Sharing is switched on or off, which moves the PC
# between 192.168.7.1 and 192.168.137.1.
#
# Deliberately does NOT touch sshd or the g_ether gadget. stop_services() unloads
# g_ether and flushes usb0, which would destroy the very SSH session a remote
# caller is using to ask for the refresh.
#
# Safe to run repeatedly: both addresses are (re)added and the default route is
# replaced, so a second run on an already-correct link is a no-op.
# ------------------------------------------------------------------------------
refresh_usb_network() {
    local ifc="usb0"
    local dev
    for dev in /sys/class/net/*; do
        [ ! -d "$dev" ] && continue
        case "$(basename "$dev")" in
            lo|wlan*|dummy*|sit*|ip6tnl*) continue ;;
            usb*|eth*|en*) ifc=$(basename "$dev"); break ;;
        esac
    done

    # Keep the gadget up; only re-apply addressing.
    sudo ip link set "$ifc" up 2>/dev/null
    sudo ip addr add 192.168.7.2/24 dev "$ifc" 2>/dev/null
    sudo ip addr add 192.168.137.2/24 dev "$ifc" 2>/dev/null

    # Pick the gateway that is actually answering. ICS answers on 192.168.137.1;
    # the direct-PC link answers on 192.168.7.1.
    if ping -c 1 -W 1 192.168.137.1 >/dev/null 2>&1; then
        sudo ip route replace default via 192.168.137.1 dev "$ifc" 2>/dev/null
        ACTIVE_GW="192.168.137.1"
        ACTIVE_IP="192.168.137.2"
    elif ping -c 1 -W 1 192.168.7.1 >/dev/null 2>&1; then
        sudo ip route replace default via 192.168.7.1 dev "$ifc" 2>/dev/null
        ACTIVE_GW="192.168.7.1"
        ACTIVE_IP="192.168.7.2"
    else
        # Neither answers; report whatever route is actually in force.
        ACTIVE_GW=$(ip route 2>/dev/null | awk '/default/ {print $3; exit}')
    fi

    # Drop the cached probe verdict so the next menu draws a real result.
    rm -f "$PROBE_FILE" "$PROBE_LOCK" 2>/dev/null

    printf 'gateway=%s ip=%s
' "${ACTIVE_GW:-unknown}" "${ACTIVE_IP:-unknown}"
}

# ------------------------------------------------------------------------------
# Helper: Fully tear down the USB network link (IPs, route, interface, gadget)
# ------------------------------------------------------------------------------
stop_usb_network() {
    # Operate on the interface that actually carries the wired link instead of
    # assuming usb0 (the gadget may enumerate under a different name).
    local ifc="usb0"
    local dev
    for dev in /sys/class/net/*; do
        [ ! -d "$dev" ] && continue
        case "$(basename "$dev")" in
            lo|wlan*|dummy*|sit*|ip6tnl*) continue ;;
            usb*|eth*|en*) ifc=$(basename "$dev"); break ;;
        esac
    done

    sudo ip route del default dev "$ifc" 2>/dev/null
    sudo ip addr flush dev "$ifc" 2>/dev/null
    sudo ip link set "$ifc" down 2>/dev/null
    # usb0 may still exist from an earlier gadget load even if another name won
    [ "$ifc" != "usb0" ] && sudo ip link set usb0 down 2>/dev/null
    sudo modprobe -r g_ether 2>/dev/null

    # Drop any cached probe verdict so the next start tests the real link
    rm -f "$PROBE_FILE" "$PROBE_LOCK" 2>/dev/null
}

# ------------------------------------------------------------------------------
# Action [A]: Start Wired Services (Instant, No Reboot)
# ------------------------------------------------------------------------------
start_services() {
    if [ "${IS_PERIPHERAL:-0}" -ne 1 ]; then
        printf "\033c" 2>/dev/null
        clear 2>/dev/null
        echo -e "${C_CYAN}============================================${C_RESET}"
        echo -e "${C_RED}   CANNOT START SERVICES IN USB HOST MODE   ${C_RESET}"
        echo -e "${C_CYAN}============================================${C_RESET}"
        echo -e " ${C_YELLOW}Press [X] to switch to WIRED PC Mode first.${C_RESET}"
        echo -e " (A quick reboot is required to activate.)  "
        echo -e "${C_CYAN}============================================${C_RESET}"
        echo -e " Returning to menu in 3 seconds...          "
        sleep 3
        return
    fi

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

    # Preserve the pristine DNS config before we replace it (idempotent)
    backup_resolv_conf
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

    echo -e "${C_YELLOW}[3/4] Starting Samba file sharing...${C_RESET}"
    sudo systemctl --no-block start smbd 2>/dev/null
    echo -e "      ${C_GREEN}-> Samba: \\\\${ACTIVE_IP}\\roms${C_RESET}"

    echo -e "${C_YELLOW}[4/4] Verifying connection...${C_RESET}"
    # One bounded probe here (2s max) with the cache primed afterwards, so the
    # menu that follows always has a fresh verdict to display.
    rm -f "$PROBE_FILE" 2>/dev/null
    if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
        printf 'OK %s\n' "$(date +%s)" > "$PROBE_FILE" 2>/dev/null
        echo -e "      ${C_GREEN}-> Internet: ONLINE (PortMaster Ready)${C_RESET}"
    else
        printf 'FAIL %s\n' "$(date +%s)" > "$PROBE_FILE" 2>/dev/null
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

    echo -e "${C_YELLOW}[1/4] Stopping OpenSSH server...${C_RESET}"
    sudo systemctl stop ssh.socket 2>/dev/null
    sudo systemctl stop ssh 2>/dev/null
    kill_sshd_except_self
    echo -e "      ${C_GREEN}-> SSH server stopped.${C_RESET}"

    echo -e "${C_YELLOW}[2/4] Stopping Samba server...${C_RESET}"
    sudo systemctl stop smbd 2>/dev/null
    sudo killall -9 smbd 2>/dev/null
    echo -e "      ${C_GREEN}-> Samba server stopped.${C_RESET}"

    echo -e "${C_YELLOW}[3/4] Shutting down USB network...${C_RESET}"
    stop_usb_network
    echo -e "      ${C_GREEN}-> Wired link down, gadget unloaded.${C_RESET}"

    echo -e "${C_YELLOW}[4/4] Restoring original DNS configuration...${C_RESET}"
    if restore_resolv_conf; then
        echo -e "      ${C_GREEN}-> /etc/resolv.conf restored.${C_RESET}"
    else
        echo -e "      ${C_GRAY}-> Nothing to restore (no backup on record).${C_RESET}"
    fi

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

    ensure_dtb_profiles

    # Switch relative to currently active hardware mode
    if [ "$RUN_MODE" == "peripheral" ]; then
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
        if [ -s /boot/rk3326-g350-host.dtb ] && sudo cp /boot/rk3326-g350-host.dtb /boot/rk3326-g350-linux.dtb 2>/dev/null; then
            sync
            echo -e "      ${C_GREEN}-> Host DTB applied.${C_RESET}"
        else
            echo -e "      ${C_RED}-> ERROR: Could not write Host DTB to /boot!${C_RESET}"
            sleep 3
            return 1
        fi
        echo -e "${C_YELLOW}[2/2] Preparing hardware restart...${C_RESET}"
        # NOTE: Do NOT kill sshd here! Prematurely killing sshd disconnects active
        # SSH sessions with 'Broken pipe'. A clean reboot halts services gracefully.
        echo -e "${C_CYAN}============================================${C_RESET}"
        echo -e "${C_WHITE} SWITCHED TO USB HOST MODE! (OTG)           ${C_RESET}"
        echo -e " Hardware reboot required to switch.        ${C_RESET}"
        echo -e " Press ${C_RED}[B]${C_RESET} to cancel, or wait 5 seconds... "
        echo -e "${C_CYAN}============================================${C_RESET}"
    else
        echo -e "${C_GREEN}[1/2] Applying Wired PC DTB to /boot...${C_RESET}"
        if [ -s /boot/rk3326-g350-peripheral.dtb ] && sudo cp /boot/rk3326-g350-peripheral.dtb /boot/rk3326-g350-linux.dtb 2>/dev/null; then
            sync
            echo -e "      ${C_GREEN}-> Peripheral DTB applied.${C_RESET}"
        else
            echo -e "      ${C_RED}-> ERROR: Could not write Peripheral DTB to /boot!${C_RESET}"
            sleep 3
            return 1
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
        for _slice in {1..10}; do
            if type Test_Button_B >/dev/null 2>&1; then
                Test_Button_B
                if [ "$?" -eq "10" ]; then
                    echo -e "\n${C_YELLOW}Reboot canceled. Returning to menu...${C_RESET}"
                    sleep 1.5
                    return 0
                fi
            fi
            read -t 0.1 -n 1 key 2>/dev/null
            if [[ "$key" == "b" || "$key" == "B" || "$key" == "q" || "$key" == "4" ]]; then
                echo -e "\n${C_YELLOW}Reboot canceled. Returning to menu...${C_RESET}"
                sleep 1.5
                return 0
            fi
            sleep 0.1
        done
    done

    echo -e "\n${C_GREEN}Rebooting now...${C_RESET}"
    sync
    sudo reboot
    exit 0
}

#===============================================================================
# CONTROL INTERFACE (used by the G350 Companion desktop app)
#===============================================================================
# Lets the PC ask the console to re-apply its network settings after the PC end
# changes address (e.g. Windows ICS switching 192.168.7.1 to 192.168.137.1).
#
# Strictly non-interactive and non-destructive: no TUI, no waits, no gadget
# unload. With no arguments the normal menu runs exactly as before, so launching
# from EmulationStation is unaffected.
#
# Usage:
#   USB_Network_Manager.sh --refresh-net        re-apply IPs + default route
#   USB_Network_Manager.sh --set-gateway <ip>   force the default route via <ip>
#===============================================================================
case "${1:-}" in
    --refresh-net)
        refresh_usb_network
        exit 0
        ;;
    --set-gateway)
        GW="${2:-}"
        if [ -n "$GW" ] && [[ "$GW" =~ ^[0-9]+[.][0-9]+[.][0-9]+[.][0-9]+$ ]]; then
            ifc="usb0"
            for dev in /sys/class/net/*; do
                [ ! -d "$dev" ] && continue
                case "$(basename "$dev")" in
                    lo|wlan*|dummy*|sit*|ip6tnl*) continue ;;
                    usb*|eth*|en*) ifc=$(basename "$dev"); break ;;
                esac
            done
            sudo ip link set "$ifc" up 2>/dev/null
            sudo ip addr add 192.168.7.2/24 dev "$ifc" 2>/dev/null
            sudo ip addr add 192.168.137.2/24 dev "$ifc" 2>/dev/null
            sudo ip route replace default via "$GW" dev "$ifc" 2>/dev/null
            rm -f "$PROBE_FILE" "$PROBE_LOCK" 2>/dev/null
            echo "gateway=$GW ip=$ifc"
        else
            echo "invalid gateway" >&2
            exit 2
        fi
        exit 0
        ;;
esac

# ------------------------------------------------------------------------------
# Main Application Loop
# ------------------------------------------------------------------------------
# Ensure no lingering watcher processes or stale state files exist
sudo pkill -f "usb_mgr_btn_watch.py" 2>/dev/null
rm -rf /tmp/usb_net_mgr 2>/dev/null

REFRESH_MODE=""
while true; do
    draw_menu "$REFRESH_MODE"
    REFRESH_MODE=""
    LAST_REFRESH=$SECONDS

    # Polling loop for Gamepad and Keyboard input
    while true; do
        # 1. Gamepad Input via ArkOS buttonmon
        # Every helper is existence-checked: some ArkOS builds ship a
        # buttonmon.sh without Test_Button_Y/X/B, and an unguarded call there
        # would silently disable those buttons entirely.
        if type Test_Button_A >/dev/null 2>&1; then
            Test_Button_A
            if [ "$?" -eq "10" ]; then
                start_services
                while read -t 0.05 -n 1 _; do :; done 2>/dev/null
                break
            fi
        fi

        if type Test_Button_Y >/dev/null 2>&1; then
            Test_Button_Y
            if [ "$?" -eq "10" ]; then
                stop_services
                while read -t 0.05 -n 1 _; do :; done 2>/dev/null
                break
            fi
        fi

        if type Test_Button_X >/dev/null 2>&1; then
            Test_Button_X
            if [ "$?" -eq "10" ]; then
                switch_hardware_mode
                while read -t 0.05 -n 1 _; do :; done 2>/dev/null
                break
            fi
        fi

        if type Test_Button_B >/dev/null 2>&1; then
            Test_Button_B
            if [ "$?" -eq "10" ]; then
                printf "\033c" 2>/dev/null
                clear 2>/dev/null
                exit 0
            fi
        fi

        # 2. Keyboard / SSH / TTY Input
        read -t 0.05 -n 1 key 2>/dev/null
        case "$key" in
            1|[aA])
                start_services
                while read -t 0.05 -n 1 _; do :; done 2>/dev/null
                break
                ;;
            2|[yY])
                stop_services
                while read -t 0.05 -n 1 _; do :; done 2>/dev/null
                break
                ;;
            3|[xX])
                switch_hardware_mode
                while read -t 0.05 -n 1 _; do :; done 2>/dev/null
                break
                ;;
            4|[bB]|[qQ])
                printf "\033c" 2>/dev/null
                clear 2>/dev/null
                exit 0
                ;;
        esac

        # 3. Periodic Auto-Refresh (every ~4 seconds while idle)
        if [ $((SECONDS - LAST_REFRESH)) -ge 4 ]; then
            REFRESH_MODE="refresh"
            break
        fi

        sleep 0.05
    done
done
