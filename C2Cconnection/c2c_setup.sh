#!/bin/bash
# ==============================================================================
# Script: c2c_setup.sh
# Directory: C2Cconnection/
# Device: Battle XP G350 & RK3326 Handhelds (ArkOS / dArkOS)
# Purpose: Headless C2C Network Interface & Static IP Setup Helper
# Usage: sudo ./c2c_setup.sh [--host | --peripheral | --status | --down]
# ==============================================================================

# Parse command line flags
FORCE_ROLE=""
ACTION="up"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --host|-h)
            FORCE_ROLE="host"
            shift
            ;;
        --peripheral|-p)
            FORCE_ROLE="peripheral"
            shift
            ;;
        --status|-s)
            ACTION="status"
            shift
            ;;
        --down|-d)
            ACTION="down"
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# Detect role if not forced
if [ -n "$FORCE_ROLE" ]; then
    ROLE="$FORCE_ROLE"
else
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
        ROLE="host"
    fi
fi

# Determine IP and target
if [ "$ROLE" == "host" ]; then
    MY_IP="192.168.10.1"
    PEER_IP="192.168.10.2"
else
    MY_IP="192.168.10.2"
    PEER_IP="192.168.10.1"
fi

# Find USB network interface
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

find_interface

# Handle Action: Tear Down
if [ "$ACTION" == "down" ]; then
    echo "[C2C] Tearing down C2C link on $IFACE..."
    sudo ip route del 192.168.10.0/24 dev "$IFACE" 2>/dev/null
    sudo ip addr del "$MY_IP/24" dev "$IFACE" 2>/dev/null
    echo "[C2C] Done."
    exit 0
fi

# Handle Action: Status Check
if [ "$ACTION" == "status" ]; then
    echo "[C2C Status]"
    echo "  Role      : $ROLE"
    echo "  Interface : $IFACE"
    echo "  Local IP  : $MY_IP"
    echo "  Peer IP   : $PEER_IP"
    if [ -f "/sys/class/net/$IFACE/carrier" ]; then
        CARRIER=$(cat "/sys/class/net/$IFACE/carrier" 2>/dev/null)
        echo "  Carrier   : $([ "$CARRIER" = "1" ] && echo "UP" || echo "DOWN")"
    fi
    if ping -c 1 -W 1 "$PEER_IP" >/dev/null 2>&1; then
        echo "  Ping      : ONLINE (Peer responding)"
        exit 0
    else
        echo "  Ping      : OFFLINE (Peer not responding)"
        exit 1
    fi
fi

# Action: Bring Up Network
echo "[C2C Setup] Configuring console as: ${ROLE^^} ($MY_IP)..."

# Ensure appropriate modules are loaded
if [ "$ROLE" == "peripheral" ]; then
    if ! lsmod | grep -q "g_ether"; then
        sudo modprobe g_ether 2>/dev/null
        sleep 0.5
        find_interface
    fi
else
    sudo modprobe cdc_ether 2>/dev/null
    sudo modprobe rndis_host 2>/dev/null
    sudo modprobe cdc_eem 2>/dev/null
    sudo modprobe usbnet 2>/dev/null
    sleep 0.3
    find_interface
fi

# Enable interface
sudo ip link set "$IFACE" up 2>/dev/null

# Assign IP if not already assigned
if ! ip -4 addr show dev "$IFACE" 2>/dev/null | grep -q "inet $MY_IP/"; then
    sudo ip addr add "$MY_IP/24" dev "$IFACE" 2>/dev/null
fi

# Add direct subnet route
sudo ip route replace 192.168.10.0/24 dev "$IFACE" 2>/dev/null

echo "[C2C Setup] Interface $IFACE ready ($MY_IP/24)."

# Quick Ping Test to Peer
echo -n "[C2C Setup] Probing peer ($PEER_IP)... "
if ping -c 1 -W 1 "$PEER_IP" >/dev/null 2>&1; then
    echo "SUCCESS! Peer is connected and responding."
    exit 0
else
    echo "WARNING: Peer ($PEER_IP) not reachable yet."
    echo "         Check that the USB cable is firmly in the OTG port on both consoles."
    exit 1
fi
