# VPN Manager

> Lightweight, instant, and minimalist CLI manager for OpenVPN and WireGuard tunnels on Linux.

```text
 :: VPN Manager (control hub)

   Status        ● online (WireGuard)
   Config        my-server.conf (~/VPNs/my-server.conf)
   Tunnel IP     10.8.0.2 (wg0)
   Interface     wg0

   [1]  Connect VPN        (select .ovpn / .conf profile)
   [2]  Disconnect         (terminate active tunnel)
   [3]  Refresh status
   [4]  Live logs          (stream / view tunnel logs)
   [q]  Quit

 ➜ Select option [1-4, q]: 
```

`vpn-manager` provides a fast, zero-friction terminal interface to connect, monitor, and disconnect **OpenVPN** (`.ovpn`) and **WireGuard** (`.conf`) tunnels. Built with a refined 256-color palette, single-key navigation, and smart configuration discovery—no more memorizing daemon flags or dealing with dangling VPN processes.

---

## Table of Contents

- [Features](#features)
- [Comparison](#comparison)
- [Supported Protocols](#supported-protocols)
- [Installation](#installation)
- [Usage](#usage)
  - [Interactive Hub](#interactive-hub)
  - [Direct CLI Subcommands](#direct-cli-subcommands)
- [Directory Structure](#directory-structure)
- [License](#license)

---

## Features

- **Dual-Protocol Engine:** Automatically detects and manages both **OpenVPN** (`.ovpn`) and **WireGuard** (`.conf`) configurations.
- **Single-Key Navigation:** Instant keypress response for all actions (`1`–`4`, `q`, `ESC`) without waiting for Enter.
- **Smart Profile Discovery:** Auto-discovers `.ovpn` and `.conf` profiles across `~/VPNs`, `~/vpns`, `/etc/wireguard`, and the current working directory.
- **Real-Time Tunnel Telemetry:** Live detection of assigned tunnel IP addresses across `tun*` and `wg*` interfaces, active PIDs, and config paths.
- **Zero-Friction Sudo Elevation:** Seamless privilege escalation while preserving the user's home directory (`$SUDO_USER` aware).
- **Clean Disconnect & Cleanup:** Terminates active tunnels cleanly and purges lingering PIDs and temp files.
- **Live Log & State Streaming:** Background `tail -f` log streaming for OpenVPN and real-time interface telemetry (`wg show`) for WireGuard.
- **Tokyo Night Aesthetic:** Clean, distraction-free 256-color palette formatted with step-by-step indentation.

---

## Comparison

| Feature | Manual CLI (`openvpn` / `wg-quick`) | Heavy Network GUIs | `vpn-manager` |
| :--- | :--- | :--- | :--- |
| **Protocol Support** | Separate tools per protocol | Often requires plugins/bloat | Unified OpenVPN & WireGuard |
| **Profile Discovery** | Manual path typing | Nested dropdown menus | Auto-scans `~/VPNs` and subfolders |
| **Navigation** | Full command-line flags | Mouse-heavy clicks | Single keypress (`1`-`4`, `q`, `ESC`) |
| **IP & Tunnel Status** | Manual `ip a` / `curl ifconfig.me` | Hidden behind menus | Instant header status card |
| **Privilege Handling** | Fails or breaks `$HOME` paths | Polkit password prompts | Smart `$SUDO_USER` path preservation |
| **Log Inspection** | Manual `tail` / `journalctl` | Buried in system logs | Built-in streaming with one key exit |

---

## Supported Protocols

| Protocol | File Extension | Engine | Default Interfaces |
| :--- | :--- | :--- | :--- |
| **OpenVPN** | `*.ovpn` | `openvpn --daemon` | `tun0`, `tun1` |
| **WireGuard** | `*.conf` | `wg-quick` | `wg0`, `wg1`, `<name>` |

---

## Installation

### Prerequisites

Linux (Debian/Ubuntu, Arch, Fedora) with `bash`, `iproute2`, and at least one VPN backend:
- OpenVPN: `sudo apt install openvpn`
- WireGuard: `sudo apt install wireguard wireguard-tools`

### Quick Setup

```bash
git clone https://github.com/mimmocrazy/vpn-manager.git
cd vpn-manager
./install.sh
```

This links the executable directly to `~/.local/bin/vpn`.

---

## Usage

### Interactive Hub

Launch the interactive control hub:

```bash
vpn
```

```text
 :: Available configurations (~/VPNs):

   [1]  machines_eu-1.ovpn                     (OpenVPN)
   [2]  starting_points_eu-starting-point.ovpn (OpenVPN)
   [3]  my-vps.conf                            (WireGuard)
   [q]  Cancel

 ➜ Select configuration [1-3, q]: 
```

### Direct CLI Subcommands

Prefer fast command-line execution? Use direct subcommands:

```bash
# Start a connection (opens profile picker if omitted)
vpn start
vpn start hackthebox.ovpn
vpn start my-vps.conf

# Check tunnel status and assigned IP
vpn status

# Stream live connection logs
vpn logs

# Disconnect any active tunnel
vpn stop

# Restart active VPN connection
vpn restart
vpn restart hackthebox.ovpn

# Quick help reference
vpn --help
```

---

## Directory Structure

Place your configuration files in your preferred location:

```text
~/VPNs/
├── hackthebox.ovpn
├── tryhackme.ovpn
├── my-server.conf
└── work-lab/
    └── company.ovpn
```

`vpn-manager` automatically scans `~/VPNs`, `~/vpns`, `~/vpn`, `/etc/wireguard`, and the current directory up to 2 levels deep.

---

## License

Distributed under the [MIT License](LICENSE). Copyright © 2026 Mimmo.
