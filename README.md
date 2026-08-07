# 🛡️ VPN Manager (OpenVPN Modern Manager CLI)

A modern, fast, and interactive CLI manager for OpenVPN connections on Linux.

## ✨ Features

- **Interactive Menu**: Manage connections, view live status, and inspect logs with ease.
- **Fast CLI Mode**: Direct subcommands (`start`, `stop`, `status`, `logs`, `restart`).
- **Interactive Configuration Picker**: Auto-detects `.ovpn` profiles in `~/VPNs` and the current directory.
- **Real-Time Tunnel Status**: Checks `tun0` interface, assigned IP address, PID, and active config.
- **Live Log Streaming**: View OpenVPN connection logs in real-time.

---

## 🚀 Quick Start

### Installation / Linking
The script is linked to `~/.local/bin/vpn`:
```bash
./install.sh
```

### Usage

```bash
# Open the interactive hub
vpn

# Start a connection (shows interactive profile selector if file is omitted)
vpn start
vpn start hackthebox.ovpn

# Check tunnel status and assigned IP
vpn status

# View live connection logs
vpn logs

# Disconnect
vpn stop

# Restart VPN tunnel
vpn restart
```

---

## 📁 Directory Structure

- `~/VPNs/`: Place your `.ovpn` configuration files here.
- `~/Projects/vpn-manager/`: Source repository and executable script.
