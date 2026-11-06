# USB_Network_Manager.sh — control interface for G350 Companion

How the console-side script was extended so the Windows app can tell the console
to re-apply its network settings, and why it was done this way.

Related: app release `v0.4.3`, plan `docs/PLAN.md` §6b.

---

## 1. Why this was needed

When Windows Internet Connection Sharing is switched on, the PC's USB adapter
moves from `192.168.7.1` to `192.168.137.1`. The console must then re-point its
default route at the new gateway.

The console script already knows how to do this — it probes for `192.168.137.1`
and picks the matching route. But that logic only ran when the user pressed
**[A] Start Services** on the console's own TUI. Nothing on the PC could trigger
it, so after turning sharing on the user had to go to the console and press a
button.

**Goal:** the app asks the console to re-apply its networking, automatically,
after sharing is turned on or off.

---

## 2. What the script already did (read before changing anything)

824 lines. The parts that matter:

| Function | Line (orig) | What it does |
| :--- | :--- | :--- |
| `start_services()` | 515 | Adds both IPs, waits for carrier, **probes `192.168.137.1`**, sets route, starts sshd + samba |
| `stop_services()` | 613 | Stops sshd, samba, then `stop_usb_network()` |
| `stop_usb_network()` | 488 | `ip addr flush`, `ip link down`, **`modprobe -r g_ether`** |
| `detect_status()` | 280 | Reads route + IPs, sets `ACTIVE_IP`; runs on every 4 s auto-refresh |
| `draw_menu()` | 391 | Renders the TUI |
| Main loop | 745 | Draws menu, polls gamepad + keyboard, refreshes every ~4 s |

The relevant part of `start_services()`:

```bash
sudo ip addr add 192.168.7.2/24   dev usb0
sudo ip addr add 192.168.137.2/24 dev usb0
...
if ping -c 1 -W 1 192.168.137.1; then
    sudo ip route replace default via 192.168.137.1 dev usb0
else
    sudo ip route replace default via 192.168.7.1 dev usb0
fi
```

So the knowledge was already there. It just could not be triggered remotely.

### Constraints discovered while reading it

1. **`stop_services()` cannot be used remotely.** It calls `stop_usb_network()`,
   which runs `modprobe -r g_ether` and flushes `usb0`. Doing that over SSH
   destroys the very connection being used to ask for the restart. A remote
   "restart" must therefore be a *refresh*, not a stop+start.

2. **The script is a long-running TUI.** It starts at boot
   (`/opt/system/Tools/USB_Network_Manager.sh` → `/dev/tty1`) and owns `/dev/tty0`
   and `/dev/tty1` via `exec > /dev/tty1`. A second instance would fight the
   first one for the display.

3. **`cleanup()` is on an `EXIT` trap** and prints a cursor-restore escape
   (`\033[?25h`). Harmless on a TTY, noise in machine-readable output.

4. **Two copies exist on the console**, identical builds:
   * `/roms/tools/USB_Network_Manager.sh` (visible in the Tools menu)
   * `/opt/system/Tools/USB_Network_Manager.sh` (the one that runs)

   Both must be updated together or the next launch from Tools reverts.

---

## 3. What was added

Two non-interactive modes. When no argument is given nothing changes, so
launching from EmulationStation behaves exactly as before.

```bash
USB_Network_Manager.sh --start-services       # same as pressing [A]
USB_Network_Manager.sh --refresh-net          # addressing + route only, no restarts
USB_Network_Manager.sh --set-gateway <ip>     # force the route via <ip>
```

### 3.0 `start_services_cli()` — the [A] equivalent

`start_services()` itself cannot be called remotely: it clears the screen, prints
a banner, sleeps, and refuses to run unless `IS_PERIPHERAL` was set by the TUI's
status detection.

`start_services_cli()` performs the same steps with none of that: re-address
`usb0`, probe for the gateway, restore/rewrite `resolv.conf`, restart sshd and
samba. Measured at **3.9 s** on hardware, with SSH staying up throughout.

It never unloads `g_ether`, so the link survives the call.

### 3.1 `refresh_usb_network()`

New function (inserted before `stop_usb_network()`). It:

* finds the interface that actually carries the link (`usb*`/`eth*`/`en*`),
  rather than assuming `usb0`
* brings it up and adds **both** addresses
* pings `192.168.137.1`, then `192.168.7.1`, and installs the matching default
  route
* clears the cached probe file so the TUI redraws a real verdict
* prints one line: `gateway=<ip> ip=<ip>`

It deliberately does **not** touch sshd, samba, `g_ether`, or `/etc/resolv.conf`.
That is what makes it safe to call over the connection it is repairing.

Because both addresses are re-added and the route is *replaced* (not added), a
second call on an already-correct link is a no-op.

### 3.2 The control interface

A `case "${1:-}"` block placed after all function definitions and immediately
before the main loop, so every function it calls exists at that point.

```bash
case "${1:-}" in
    --refresh-net)   refresh_usb_network; exit 0 ;;
    --set-gateway)   ...validates IPv4, applies, exit 0 / exit 2 ;;
esac
```

`--set-gateway` validates the argument with a dotted-quad regex before using it,
so a malformed value can never reach `ip route`.

### 3.3 TUI-only setup is now skipped for these modes

```bash
G350_CLI_MODE=0
case "${1:-}" in
    --refresh-net|--set-gateway) G350_CLI_MODE=1 ;;
esac
```

This is detected **before** anything else because two earlier statements would
otherwise interfere:

| Statement | Why it is guarded |
| :--- | :--- |
| `exec > /dev/tty1` | would hijack the physical display and send output away from the caller |
| `setfont` | pointless for a machine call, and touches the console |
| `printf "\033[?25h"` in `cleanup()` | prints an escape sequence into stdout |

---

## 4. How the app calls it

The app does **not** re-upload the script. It runs the copy already on the
console, over the SSH session it already uses:

```bash
bash /opt/system/Tools/USB_Network_Manager.sh --refresh-net
```

Reading `gateway=` from the output tells the app which gateway the console
settled on, which it can surface instead of guessing.

---

## 5. What was deliberately *not* done

| Rejected approach | Why |
| :--- | :--- |
| Call `stop_services` then `start_services` | unloads `g_ether` and flushes `usb0` — kills the SSH session mid-call |
| Run the script with no arguments and send `a` | it would draw the TUI onto `/dev/tty1` and fight the running instance |
| Edit the route directly from the app (`ip route replace`) | duplicates logic the script already owns; the next Start Services overwrites it, and a future script change would silently diverge |
| Replace the script with a new file on each run | the script is 38 KB of unrelated, working behaviour; a remote overwrite risks corrupting a script that is the only way back onto the device |
| A systemd unit / daemon on the console | permanent install, version drift; the project rule is that console payloads stay transient |

---

## 6. Verification performed

Executed on Windows with stub `sudo`/`ip`/`ping` on `PATH` to capture the exact
command sequence (the console was disconnected during development).

| Test | Result |
| :--- | :--- |
| `bash -n` syntax check | pass |
| File stays LF-only (no CRLF) | 0 CR bytes, 38,482 bytes |
| `--refresh-net` output | exactly `gateway=192.168.137.1 ip=192.168.137.2`, no escape codes |
| `--refresh-net` command sequence | `link set up`, `addr add .7.2`, `addr add .137.2`, `route replace via .137.1` |
| `--set-gateway 192.168.7.1` | route replaced via `.7.1`, prints `gateway=192.168.7.1` |
| `--set-gateway abc` | rejected, exit 2, no `ip` calls made |
| No arguments | falls through to the original TUI loop unchanged |

### ⚠️ Not yet verified on hardware

The console was unplugged for this work. Still to confirm on a real device:

1. `--refresh-net` over SSH **while services are running** changes the route and
   the console gains internet, without dropping the SSH session.
2. The TUI still draws correctly when launched from EmulationStation (no args).
3. Both copies (`/roms/tools`, `/opt/system/Tools`) stay in sync.

---

## 7. Installing the updated script

Copy to **both** locations so the Tools menu and the boot script agree:

```bash
scp USB_Network_Manager.sh ark@192.168.7.2:/tmp/
ssh ark@192.168.7.2
echo ark | sudo -S -p '' cp /tmp/USB_Network_Manager.sh /roms/tools/USB_Network_Manager.sh
echo ark | sudo -S -p '' cp /tmp/USB_Network_Manager.sh /opt/system/Tools/USB_Network_Manager.sh
echo ark | sudo -S -p '' chmod 755 /roms/tools/USB_Network_Manager.sh /opt/system/Tools/USB_Network_Manager.sh
md5sum /roms/tools/USB_Network_Manager.sh /opt/system/Tools/USB_Network_Manager.sh
```

Both hashes must match. The running TUI keeps the old code in memory until it is
exited with **[B]**, so restart it (or reboot) to pick up the change.

### Reverting

The previous script is byte-identical to release `v1.4.0` of this repo, so
`git checkout v1.4.0 -- USB_Network_Manager.sh` restores it.

---

## 8. Summary of the diff

```
 USB_Network_Manager.sh | 117 +++++++++++++++++++++++++++++++++++++++++++++++--
 1 file changed, 113 insertions(+), 4 deletions(-)
```

* `G350_CLI_MODE` detection + 2 guarded statements
* `refresh_usb_network()` — new, ~45 lines
* control-interface `case` block — new, ~40 lines
* `ACTIVE_GW` default alongside `ACTIVE_IP`
* no change to any existing code path when run without arguments
