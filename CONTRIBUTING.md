# Contributing

## Commit messages

Use a typed, imperative subject no longer than 72 characters, then a body that
explains what changed and why. No first person and no narrative.

```
<type>(<scope>): <imperative summary, <=72 chars>

<body: what changed and why, no first person, no narrative>
```

| Type | Use for |
| :--- | :--- |
| `feat` | A new user-visible capability |
| `fix` | A defect repair |
| `refactor` | Internal restructuring with no behaviour change |
| `docs` | Documentation only |
| `chore` | Housekeeping with no behaviour change |

`scope` is optional; use the area affected (`dashboard`, `net`, `dns`, `usb`,
`c2c`, `cli`).

Worked example:

```
fix(net): export the system paths so remote calls do not fail silently

An SSH session is given PATH=/usr/local/bin:/usr/bin:/bin:/usr/games and sudo on
this image sets no secure_path, so lsmod, modprobe, killall and several iproute2
helpers are not found when the script is driven remotely. Every such call
suppressed its own error, so the script appeared to succeed while doing nothing.
The real directories are prepended once at the top of the script, which covers
the calls inside subshells and command substitutions as well.
```

Keep the subject in the imperative mood: "Add", not "Added" or "Adds".

## Constraints to respect

The script runs on a 3.5" console display as the only way back onto the device.
Changes must not break that path.

- **Keep the TUI layout within 44 columns and 16 rows.** It is sized for the
  G350's panel and overflows are not readable.
- **Never unload `g_ether` in a mode that can be called remotely.** Flushing the
  interface ends the SSH session making the request.
- **Keep the script self-contained.** It is copied to the console as one file;
  no sourced installer assets beyond what ArkOS already provides.
- **Keep machine-readable modes clean.** `--refresh-net`, `--set-gateway` and
  `--start-services` must not write terminal escape sequences or TUI banners to
  stdout.
- **Keep LF line endings.** `.gitattributes` enforces this for `*.sh`; a CRLF
  copy fails on the console with `bad interpreter`.
- **Update both installed copies** when testing on hardware:
  `/roms/tools/USB_Network_Manager.sh` and `/opt/system/Tools/USB_Network_Manager.sh`.

## Branches and releases

- Work directly on `main`. Each commit should leave the script runnable.
- Tag releases as `vMAJOR.MINOR.PATCH` following [SemVer](https://semver.org/).
  Patch versions for fixes, minor versions for new capability.
- Add the release entry to `CHANGELOG.md` before tagging.
- Release titles follow `USB Network Manager vX.Y.Z — <summary>` in sentence
  case. The release body is the changelog entry for that version.
- Release notes are published on the GitHub release page. Do not commit release
  note files to the repository.

## Installing a build onto a console

Both copies must be updated together, or the next launch from TOOLS reverts to
the old script.

```bash
scp USB_Network_Manager.sh ark@192.168.7.2:/tmp/
ssh ark@192.168.7.2
echo ark | sudo -S -p '' cp /tmp/USB_Network_Manager.sh /roms/tools/USB_Network_Manager.sh
echo ark | sudo -S -p '' cp /tmp/USB_Network_Manager.sh /opt/system/Tools/USB_Network_Manager.sh
echo ark | sudo -S -p '' chmod 755 /roms/tools/USB_Network_Manager.sh /opt/system/Tools/USB_Network_Manager.sh
md5sum /roms/tools/USB_Network_Manager.sh /opt/system/Tools/USB_Network_Manager.sh
```

The two hashes must match. A running dashboard keeps the old code in memory
until it is exited with **[B]**, so restart it or reboot.

## Manual test procedure

Syntax and hygiene checks run anywhere:

```bash
bash -n USB_Network_Manager.sh
grep -c $'\r' USB_Network_Manager.sh   # must be 0
```

Hardware checks require a console with the script installed. Record pass or fail
per step; do not record port names, machine names or addresses beyond the two
documented ranges.

### Dashboard

1. Launch from **TOOLS**. The dashboard draws without overflowing the panel.
2. Press **[A]**. Addresses, gateway and services come up, and the status line
   reports `INTERNET : ONLINE` when the PC is sharing.
3. Press **[Y]**. Daemons stop and the status line reports services off.
4. Press **[X]**, confirm the reboot, and let the console restart. The USB mode
   has changed.
5. Press **[B]**. The script exits cleanly to EmulationStation.

### Addressing

1. With the PC adapter on `192.168.7.1` and no sharing, press **[A]**.
   The console answers on `192.168.7.2` and its route points at `192.168.7.1`.
2. Enable internet sharing on the PC. The adapter moves to `192.168.137.1`.
3. Run `--refresh-net` over SSH. It prints
   `gateway=192.168.137.1 ip=192.168.137.2` and the console gains internet
   without dropping the SSH session.
4. Disable sharing. Run `--refresh-net` again. The gateway returns to
   `192.168.7.1` and SSH stays up throughout.

### Services

1. With services running, confirm SSH answers on port 22 and the Samba share is
   reachable.
2. Stop services, then restart them. Confirm `resolv.conf` is restored, so
   name resolution works without a reboot.
3. Confirm no `g_ether` unload occurs during `--refresh-net` or
   `--start-services`.

### Remote modes

1. `bash /roms/tools/USB_Network_Manager.sh --refresh-net` prints one line with
   no escape sequences.
2. `--set-gateway 192.168.7.1` forces the route and prints
   `gateway=192.168.7.1`.
3. `--set-gateway not-an-ip` is rejected with a non-zero exit and makes no
   routing changes.
4. Running with no argument still starts the dashboard.

### USB identity

1. Plug the console into one USB port and press **[A]**.
2. Unplug, move the cable to a different USB port, replug. The PC keeps the same
   adapter name and address, and sharing resumes without reconfiguration.
3. Confirm the gadget reports a serial:

```bash
cat /sys/class/udc/*/device/../iSerialNumber 2>/dev/null
lsmod | grep g_ether
```

## Reporting a problem

Include the script version, the console model, the firmware and kernel version,
the USB mode shown by the dashboard, and whether internet sharing was on. Paste
the relevant section of the dashboard status rather than a full screenshot where
possible.
