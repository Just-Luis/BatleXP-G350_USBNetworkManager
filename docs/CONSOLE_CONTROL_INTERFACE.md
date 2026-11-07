# Console control interface

How `USB_Network_Manager.sh` can be driven from a PC, so a host application can
ask the console to re-apply its network settings over SSH.

---

## 1. Why this exists

Windows Internet Connection Sharing assigns `192.168.137.1` to the shared
adapter. The direct setup uses `192.168.7.1`. When sharing is toggled on the PC,
the console's default route has to follow the address that now answers.

The script already resolves this: it adds both addresses to the USB interface
and routes through whichever gateway responds. That logic originally ran only
when the user pressed **[A] Start Services** on the console's own dashboard, so
a PC-driven change meant going to the console and pressing a button.

The non-interactive modes below expose that logic to a remote caller.

---

## 2. Interface

```bash
USB_Network_Manager.sh --start-services      # equivalent to pressing [A]
USB_Network_Manager.sh --refresh-net         # addressing and route only
USB_Network_Manager.sh --set-gateway <ip>    # force the route through <ip>
```

With no argument the interactive dashboard starts exactly as before, so
launching from EmulationStation is unaffected.

| Mode | Touches `g_ether` | Restarts services | Rewrites `resolv.conf` | Output |
| :--- | :---: | :---: | :---: | :--- |
| `--refresh-net` | no | no | no | `gateway=<ip> ip=<ip>` |
| `--set-gateway` | no | no | no | `gateway=<ip> ip=<iface>` |
| `--start-services` | loads if absent | yes | yes | status lines |

### `--refresh-net`

Finds the interface that carries the link (`usb*`, `eth*` or `en*`) rather than
assuming `usb0`, brings it up, adds both addresses, then pings
`192.168.137.1` and falls back to `192.168.7.1` before installing the default
route. If neither answers it reports the route that is actually in force.

It does not touch `sshd`, Samba, `g_ether` or `/etc/resolv.conf`. That is what
makes it safe to call over the connection it is repairing: flushing the
interface or unloading the gadget would end the SSH session making the request.

Both addresses are re-added and the route is replaced rather than added, so a
second call on an already-correct link changes nothing.

### `--set-gateway <ip>`

Validates the argument against a dotted-quad pattern before it reaches
`ip route`, then replaces the default route. A malformed value is rejected with
exit code 2 and no routing change.

### `--start-services`

`start_services()` itself cannot be called remotely: it clears the screen, prints
a banner, sleeps, and refuses to run unless the interactive status detection has
set `IS_PERIPHERAL`. `start_services_cli()` performs the same steps without any
of that — re-address the interface, load the gadget if it is absent, probe for
the gateway, restore `resolv.conf`, restart `sshd` and Samba.

It never unloads `g_ether`, so the link survives the call.

### TUI setup is skipped for these modes

```bash
G350_CLI_MODE=0
case "${1:-}" in
    --refresh-net|--set-gateway|--start-services) G350_CLI_MODE=1 ;;
esac
```

This is detected before anything else, because three statements would otherwise
interfere:

| Statement | Why it is guarded |
| :--- | :--- |
| `exec > /dev/tty1` | would take over the physical display and send output away from the caller |
| `setfont` | pointless for a machine call, and touches the console |
| the cursor-restore escape in `cleanup()` | would print an escape sequence into stdout |

### PATH

An SSH session is given `PATH=/usr/local/bin:/usr/bin:/bin:/usr/games`, and
`sudo` on this image sets no `secure_path`. `lsmod`, `modprobe`, `killall` and
several `iproute2` helpers therefore are not found when the script is invoked
remotely. The system directories are prepended once at the top of the script, so
the fix covers calls inside subshells and command substitutions too.

---

## 3. Calling it from a PC

The script does not need to be re-uploaded. A host application runs the copy
already on the console, over the SSH session it already holds:

```bash
bash /opt/system/Tools/USB_Network_Manager.sh --refresh-net
```

Reading `gateway=` from the output tells the caller which gateway the console
settled on, which can be reported instead of guessed.

`/opt/system/Tools/USB_Network_Manager.sh` is the copy that runs. The copy in
`/roms/tools/` is the one visible in the Tools menu. Both must hold the same
build, or launching from Tools reverts to older code.

---

## 4. Approaches that do not work

| Approach | Why it is rejected |
| :--- | :--- |
| Call `stop_services` then `start_services` | unloads `g_ether` and flushes the interface, which kills the SSH session making the call |
| Run the script with no arguments and send `a` | it would draw the dashboard onto `/dev/tty1` and fight the running instance |
| Change the route from the host application | duplicates logic the script owns; the next Start Services overwrites it and the two drift apart |
| Replace the whole script on every call | the script is the only way back onto the device; a failed overwrite is unrecoverable |
| Install a systemd unit or daemon on the console | permanent install and version drift; console payloads stay transient |

---

## 5. Verifying a change

Static checks:

```bash
bash -n USB_Network_Manager.sh
grep -c $'\r' USB_Network_Manager.sh   # must be 0
```

Behavioural checks with stub `sudo`, `ip` and `ping` on `PATH` capture the exact
command sequence without a console attached:

| Test | Expected |
| :--- | :--- |
| `--refresh-net` | `link set up`, `addr add .7.2`, `addr add .137.2`, `route replace via .137.1` |
| `--refresh-net` output | exactly `gateway=192.168.137.1 ip=192.168.137.2`, no escape codes |
| `--set-gateway 192.168.7.1` | route replaced, prints `gateway=192.168.7.1` |
| `--set-gateway abc` | rejected, exit 2, no `ip` calls made |
| no argument | falls through to the interactive dashboard unchanged |

Checks that require hardware:

1. `--refresh-net` over SSH while services are running changes the route and the
   console gains internet, without dropping the session.
2. The dashboard still draws correctly when launched from EmulationStation.
3. Both installed copies report the same hash.

---

## 6. Related

- [README](../README.md) — installation and daily use
- [CONTRIBUTING](../CONTRIBUTING.md) — commit convention and test procedure
- [G350 Companion](https://github.com/Just-Luis/G350ConnectionManager) — the host
  application that calls these modes
