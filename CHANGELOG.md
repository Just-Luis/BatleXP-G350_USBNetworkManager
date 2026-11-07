# Changelog

All notable changes to Battle XP G350 USB Network Manager are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.7.1] - 2026-11-07

### Fixed
- Remote invocations no longer fail silently. An SSH session is given a `PATH`
  without `/sbin` or `/usr/sbin`, and `sudo` on this image sets no
  `secure_path`, so `lsmod`, `modprobe`, `killall`, `sshd` and several
  `iproute2` helpers were not found when the script was driven from a PC. Every
  such call suppressed its own error, so the script appeared to succeed while
  doing nothing. The system paths are now exported at the top of the script,
  which fixes the calls inside subshells and command substitutions too.

## [1.7.0] - 2026-11-07

### Fixed
- Internet sharing survives the console being moved to a different USB port. The
  RNDIS gadget reported no USB serial number, so Windows keyed the device on the
  physical path to it (`USB\VID_0525&PID_A4A2\5&<hash>&0&<port>`). Each port was
  a distinct device with its own adapter name, GUID and network configuration,
  and moving the cable orphaned the shared adapter and left a ghost behind.
  The gadget now reports the console's factory-burned SoC serial, so the identity
  follows the device rather than the port. Each console derives its own identity
  from its own hardware, so several consoles on one PC stay distinct.

### Changed
- The console presents one identity to Windows on every USB port, so the adapter
  keeps its name and address and needs no reconfiguration after a port change.

## [1.6.0] - 2026-11-07

### Added
- `--start-services`, the non-interactive equivalent of pressing **[A]**. It
  re-addresses the interface, probes for the gateway, restores `resolv.conf` and
  restarts SSH and Samba, without clearing the display or requiring TUI state.

## [1.5.0] - 2026-11-07

### Added
- `--refresh-net`: re-applies interface addresses and the default route without
  restarting services, so a PC can move the console between the direct and
  ICS setups over SSH without dropping the session.
- `--set-gateway <ip>`: forces the default route through a validated IPv4
  address.
- `--refresh-net` output is a single machine-readable line,
  `gateway=<ip> ip=<ip>`, with no terminal escape sequences.

## [1.4.0] - 2026-11-06

### Added
- DNS configuration is preserved across a service stop and restart, and restored
  on demand.
- Guarded gamepad input, so an unavailable button monitor no longer blocks the
  dashboard.
- A non-blocking dashboard that keeps redrawing while network work runs.

### Fixed
- The SSH session driving the script is no longer interrupted by its own
  network changes.
- Button **[A]** no longer cross-triggers other actions, and a canceled reboot
  no longer leaves the menu in a contradictory state.

## [1.3.1] - 2026-11-06

### Fixed
- Unintended script exit on start and on mode switch, caused by a conflicting
  button watcher.
- Menu loop exit and mode-switch handling.

## [1.3] - 2026-11-06

### Added
- Real-time auto-refresh dashboard showing route, address and service state.
- Direct console-to-console (C2C) netplay support, with the netplay suite split
  into a standalone repository.

### Changed
- The dashboard renders offline without blocking, so the UI stays responsive
  while network operations run.

### Fixed
- DNS resolution is restored after the network is reconfigured.

## [1.2] - 2026-11-06

### Added
- Console-to-console netplay suite, with role detection and host driver loading.
- First-launch role wizard for the C2C suite.

## [1.1] - 2026-11-06

### Added
- First-run device-tree generation.
- Reliable SSH startup.
- Full service teardown.

### Fixed
- Dual-IP configuration, so both the direct and ICS address ranges are assigned.

## [1.0] - 2026-11-06

### Added
- Initial release: USB tethering, SSH and SFTP access, and Samba file sharing
  driven by an on-console gamepad dashboard.

[Unreleased]: https://github.com/Just-Luis/BatleXP-G350_USBNetworkManager/compare/v1.7.1...HEAD
[1.7.1]: https://github.com/Just-Luis/BatleXP-G350_USBNetworkManager/compare/v1.7.0...v1.7.1
[1.7.0]: https://github.com/Just-Luis/BatleXP-G350_USBNetworkManager/compare/v1.6.0...v1.7.0
[1.6.0]: https://github.com/Just-Luis/BatleXP-G350_USBNetworkManager/compare/v1.5.0...v1.6.0
[1.5.0]: https://github.com/Just-Luis/BatleXP-G350_USBNetworkManager/compare/v1.4.0...v1.5.0
[1.4.0]: https://github.com/Just-Luis/BatleXP-G350_USBNetworkManager/compare/v1.3.1...v1.4.0
[1.3.1]: https://github.com/Just-Luis/BatleXP-G350_USBNetworkManager/compare/v1.3...v1.3.1
[1.3]: https://github.com/Just-Luis/BatleXP-G350_USBNetworkManager/compare/v1.2...v1.3
[1.2]: https://github.com/Just-Luis/BatleXP-G350_USBNetworkManager/compare/v1.1...v1.2
[1.1]: https://github.com/Just-Luis/BatleXP-G350_USBNetworkManager/compare/v1.0...v1.1
[1.0]: https://github.com/Just-Luis/BatleXP-G350_USBNetworkManager/releases/tag/v1.0
