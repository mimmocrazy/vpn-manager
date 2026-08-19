#!/usr/bin/env bash
# ==============================================================================
# :: Universal VPN Modern Manager CLI (OpenVPN & WireGuard)
# ==============================================================================

SCRIPT_NAME="$(basename "$0")"
REAL_SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$REAL_SCRIPT_PATH")" && pwd)"

# Detect real user & home directory even when executed via sudo
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME="$(getent passwd "$REAL_USER" 2>/dev/null | cut -d: -f6)"
[ -z "$REAL_HOME" ] && REAL_HOME="${HOME:-/home/$REAL_USER}"

# Automatically locate VPN directory (~/VPNs, ~/vpns, ~/vpn, etc.)
VPN_DIR=""
for candidate in "$REAL_HOME/VPNs" "$REAL_HOME/vpns" "$REAL_HOME/vpn" "$REAL_HOME/VPN" "$REAL_HOME/OpenVPN" "$REAL_HOME/wireguard" "$REAL_HOME/WireGuard"; do
    if [ -d "$candidate" ]; then
        VPN_DIR="$candidate"
        break
    fi
done
[ -z "$VPN_DIR" ] && VPN_DIR="$REAL_HOME/VPNs"

LOG_FILE="/tmp/openvpn.log"
PID_FILE="/tmp/openvpn.pid"
CONF_FILE="/tmp/vpn_manager.conf"
TYPE_FILE="/tmp/vpn_manager.type"
IFACE_FILE="/tmp/vpn_manager.iface"

# Palette inspired by command-not-found / modern terminal aesthetics
RESET='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
ITALIC='\033[3m'

# Colors
C_PREFIX='\033[1;38;5;111m'    # Pastel Periwinkle Blue (::)
C_ACCENT='\033[1;38;5;141m'    # Soft Lavender (indexes [1], arrows ➜, badges)
C_TITLE='\033[1;38;5;255m'     # Crisp White Bold
C_TEXT='\033[38;5;189m'        # Soft Ice Lavender text
C_SUCCESS='\033[38;5;150m'     # Soft Mint Green (✔, online)
C_WARN='\033[38;5;222m'        # Warm Amber (configs, highlights)
C_DANGER='\033[38;5;203m'      # Pastel Coral / Rose (✖, offline, alerts)
C_MUTED='\033[38;5;60m'        # Deep Slate (brackets, hints, meta)
C_SUBTLE='\033[38;5;103m'      # Medium Slate (labels)
C_DIM='\033[38;5;241m'         # Dim Slate / Gray (paths, secondary)

format_path() {
    local p="$1"
    if [ -n "$REAL_HOME" ] && [[ "$p" == "$REAL_HOME"* ]]; then
        echo "~${p#"$REAL_HOME"}"
    elif [ -n "$HOME" ] && [[ "$p" == "$HOME"* ]]; then
        echo "~${p#"$HOME"}"
    else
        echo "$p"
    fi
}

wait_key() {
    echo ""
    read -rsn1 -p "  Press any key to continue..." _
    echo ""
}

print_banner() {
    echo -e "\n ${C_PREFIX}::${RESET} ${C_TITLE}VPN Manager${RESET} ${C_MUTED}(control hub)${RESET}\n"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        exec sudo bash "$0" "$@"
    fi
}

# Ensure root privileges for operations that need it, preserving original CLI arguments
if [ "$EUID" -ne 0 ]; then
    case "$1" in
        status|info|logs|log|help|--help|-h)
            # Read-only operations do not need root
            ;;
        *)
            check_root "$@"
            ;;
    esac
fi

is_wireguard_file() {
    local f="$1"
    if [[ "$f" == *.conf ]]; then
        if grep -qiE '^\s*\[(Interface|Peer)\]' "$f" 2>/dev/null; then
            return 0
        fi
        # If inside /etc/wireguard
        if [[ "$f" == *"/wireguard/"* ]] || [[ "$f" == *"/WireGuard/"* ]]; then
            return 0
        fi
    fi
    return 1
}

get_file_protocol() {
    local f="$1"
    if is_wireguard_file "$f" || [[ "$f" == *.conf ]]; then
        echo "WireGuard"
    else
        echo "OpenVPN"
    fi
}

get_openvpn_pid() {
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null; then
        cat "$PID_FILE"
    else
        pgrep -x openvpn | head -n 1
    fi
}

get_openvpn_config() {
    local pid="$1"
    if [ -f "$CONF_FILE" ]; then
        local saved_cfg
        saved_cfg=$(cat "$CONF_FILE" 2>/dev/null)
        if [ -n "$saved_cfg" ] && [[ "$saved_cfg" == *.ovpn ]]; then
            echo "$saved_cfg"
            return
        fi
    fi
    
    if [ -n "$pid" ] && [ -d "/proc/$pid" ]; then
        local cmdline
        cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)
        local cfg
        cfg=$(echo "$cmdline" | grep -oP '\S+\.ovpn' | head -n 1)
        if [ -n "$cfg" ]; then
            echo "$cfg"
            return
        fi
    fi
    echo ""
}

get_wireguard_interfaces() {
    if command -v wg >/dev/null 2>&1; then
        wg show interfaces 2>/dev/null
    else
        ip -br link show type wireguard 2>/dev/null | awk '{print $1}'
    fi
}

get_iface_ip() {
    local iface="$1"
    if [ -n "$iface" ]; then
        ip -4 addr show dev "$iface" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1
    fi
}

get_active_status() {
    # Check WireGuard first
    local wg_ifaces
    wg_ifaces=$(get_wireguard_interfaces)
    if [ -n "$wg_ifaces" ]; then
        local first_wg
        first_wg=$(echo "$wg_ifaces" | awk '{print $1}')
        local wg_ip
        wg_ip=$(get_iface_ip "$first_wg")
        [ -z "$wg_ip" ] && wg_ip="active"
        
        local cfg_path
        if [ -f "$CONF_FILE" ] && [[ "$(cat "$TYPE_FILE" 2>/dev/null)" == "wireguard" ]]; then
            cfg_path=$(cat "$CONF_FILE" 2>/dev/null)
        fi
        [ -z "$cfg_path" ] && cfg_path="$first_wg.conf"

        echo "WIREGUARD|$first_wg|$wg_ip|$cfg_path"
        return
    fi

    # Check OpenVPN
    local ovpn_pid
    ovpn_pid=$(get_openvpn_pid)
    if [ -n "$ovpn_pid" ]; then
        local ovpn_ip
        ovpn_ip=$(ip -4 addr show dev tun0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
        if [ -z "$ovpn_ip" ]; then
            ovpn_ip=$(ip -4 addr 2>/dev/null | grep -B2 'tun' | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1)
        fi
        [ -z "$ovpn_ip" ] && ovpn_ip="waiting for IP..."
        
        local ovpn_cfg
        ovpn_cfg=$(get_openvpn_config "$ovpn_pid")
        echo "OPENVPN|tun0|$ovpn_ip|$ovpn_cfg|$ovpn_pid"
        return
    fi

    echo "OFFLINE"
}

status_vpn() {
    local status_info
    status_info=$(get_active_status)
    
    local proto="${status_info%%|*}"
    if [ "$proto" = "WIREGUARD" ]; then
        local iface ip cfg
        IFS='|' read -r _ iface ip cfg <<< "$status_info"
        local pretty_cfg
        pretty_cfg=$(format_path "$cfg")
        
        echo -e "   ${C_SUBTLE}Status${RESET}        ${C_SUCCESS}● online${RESET} ${C_MUTED}(WireGuard)${RESET}"
        echo -e "   ${C_SUBTLE}Config${RESET}        ${C_WARN}$(basename "$cfg")${RESET} ${C_DIM}($pretty_cfg)${RESET}"
        echo -e "   ${C_SUBTLE}Tunnel IP${RESET}     ${C_PREFIX}${BOLD}$ip${RESET} ${C_MUTED}($iface)${RESET}"
        echo -e "   ${C_SUBTLE}Interface${RESET}     ${C_DIM}$iface${RESET}"
    elif [ "$proto" = "OPENVPN" ]; then
        local iface ip cfg pid
        IFS='|' read -r _ iface ip cfg pid <<< "$status_info"
        local pretty_cfg
        pretty_cfg=$(format_path "$cfg")

        echo -e "   ${C_SUBTLE}Status${RESET}        ${C_SUCCESS}● online${RESET} ${C_MUTED}(OpenVPN)${RESET}"
        if [ -n "$cfg" ]; then
            echo -e "   ${C_SUBTLE}Config${RESET}        ${C_WARN}$(basename "$cfg")${RESET} ${C_DIM}($pretty_cfg)${RESET}"
        fi
        echo -e "   ${C_SUBTLE}Tunnel IP${RESET}     ${C_PREFIX}${BOLD}$ip${RESET} ${C_MUTED}($iface)${RESET}"
        echo -e "   ${C_SUBTLE}Process${RESET}       ${C_DIM}PID $pid${RESET}"
    else
        echo -e "   ${C_SUBTLE}Status${RESET}        ${C_DANGER}○ offline${RESET} ${C_MUTED}(no active tunnel)${RESET}"
    fi
}

stop_vpn() {
    local any_stopped=false

    # 1. Stop WireGuard tunnels
    local wg_ifaces
    wg_ifaces=$(get_wireguard_interfaces)
    if [ -n "$wg_ifaces" ]; then
        for iface in $wg_ifaces; do
            echo -e "  ${C_ACCENT}➜${RESET} Disconnecting WireGuard ${C_MUTED}($iface)${RESET}..."
            local cfg_to_down="$iface"
            if [ -f "$CONF_FILE" ] && [[ "$(cat "$TYPE_FILE" 2>/dev/null)" == "wireguard" ]]; then
                cfg_to_down="$(cat "$CONF_FILE" 2>/dev/null)"
            fi
            wg-quick down "$cfg_to_down" 2>/dev/null || wg-quick down "$iface" 2>/dev/null || ip link del dev "$iface" 2>/dev/null
        done
        any_stopped=true
    fi

    # 2. Stop OpenVPN tunnel
    local pid
    pid=$(get_openvpn_pid)
    if [ -n "$pid" ]; then
        echo -e "  ${C_ACCENT}➜${RESET} Disconnecting OpenVPN ${C_MUTED}(PID: $pid)${RESET}..."
        kill "$pid" 2>/dev/null || pkill -x openvpn
        sleep 0.5
        if pgrep -x openvpn >/dev/null; then
            killall -9 openvpn 2>/dev/null
        fi
        any_stopped=true
    fi

    # Cleanup state
    rm -f "$PID_FILE" "$CONF_FILE" "$TYPE_FILE" "$IFACE_FILE"

    if [ "$any_stopped" = true ]; then
        echo -e "  ${C_SUCCESS}✔${RESET} VPN disconnected successfully."
    else
        echo -e "  ${C_MUTED}○ No active VPN to disconnect.${RESET}"
    fi
}

start_vpn() {
    local config_arg="$1"
    local config_file=""

    local search_dirs=()
    for d in "$REAL_HOME/VPNs" "$REAL_HOME/vpns" "$REAL_HOME/vpn" "$REAL_HOME/VPN" "$REAL_HOME/OpenVPN" "$REAL_HOME/wireguard" "$REAL_HOME/WireGuard" "$VPN_DIR" "/etc/wireguard" "$(pwd)" "$SCRIPT_DIR"; do
        if [ -d "$d" ]; then
            search_dirs+=("$d")
        fi
    done

    mapfile -t all_files < <(
        for d in "${search_dirs[@]}"; do
            find "$d" -maxdepth 2 \( -name "*.ovpn" -o -name "*.conf" \) -printf "%p\n" 2>/dev/null
        done | sort -u
    )

    # Filter valid VPN config files
    local valid_files=()
    for f in "${all_files[@]}"; do
        if [[ "$f" == *.ovpn ]]; then
            valid_files+=("$f")
        elif is_wireguard_file "$f"; then
            valid_files+=("$f")
        fi
    done

    if [ ${#valid_files[@]} -eq 0 ]; then
        echo -e "\n  ${C_DANGER}✖${RESET} No VPN files (.ovpn / .conf) found in: ${BOLD}$(format_path "$VPN_DIR")${RESET}\n"
        return 1
    fi

    # 1. Direct index matching (e.g. `vpn connect 3`)
    if [[ "$config_arg" =~ ^[0-9]+$ ]]; then
        local idx=$((config_arg - 1))
        if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#valid_files[@]}" ]; then
            config_file="${valid_files[$idx]}"
        fi
    fi

    # 2. File / pattern / substring matching (e.g. `vpn connect machines`)
    if [ -z "$config_file" ] && [ -n "$config_arg" ]; then
        if [ -f "$config_arg" ]; then
            config_file="$config_arg"
        else
            for f in "${valid_files[@]}"; do
                local fname
                fname="$(basename "$f")"
                if [[ "$fname" == "$config_arg" || "$fname" == "$config_arg.ovpn" || "$fname" == "$config_arg.conf" || "$fname" == *"$config_arg"* ]]; then
                    config_file="$f"
                    break
                fi
            done
        fi
    fi

    # 3. If no config provided or match not found, show interactive menu
    if [ -z "$config_file" ]; then
        if [ -n "$config_arg" ]; then
            echo -e "\n  ${C_DANGER}✖${RESET} Configuration '${config_arg}' not found. Select from list:"
        fi
        echo -e "\n ${C_PREFIX}::${RESET} ${BOLD}Available configurations${RESET} ${C_MUTED}($(format_path "$VPN_DIR"))${RESET}:\n"
        for i in "${!valid_files[@]}"; do
            local fn proto_badge
            fn="$(basename "${valid_files[$i]}")"
            proto_badge="$(get_file_protocol "${valid_files[$i]}")"
            printf "   ${C_ACCENT}[$((i+1))]${RESET}  ${C_WARN}%-36s${RESET} ${C_MUTED}(%s)${RESET}\n" "$fn" "$proto_badge"
        done
        echo -e "   ${C_ACCENT}[q]${RESET}  ${C_MUTED}Cancel${RESET}\n"
        
        local choice
        if [ "${#valid_files[@]}" -le 9 ]; then
            read -rn1 -p " ➜ Select configuration [1-${#valid_files[@]}, q]: " choice
            echo ""
        else
            read -rp " ➜ Select configuration [1-${#valid_files[@]}, q]: " choice
        fi

        # Allow q, Q, 0, empty, or ESC key to cancel
        if [[ "$choice" =~ ^[qQ]$ ]] || [ -z "$choice" ] || [ "$choice" = "0" ] || [[ "$choice" == $'\e'* ]]; then
            return 0
        fi

        if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#valid_files[@]}" ]; then
            echo -e "\n  ${C_DANGER}✖${RESET} Invalid selection."
            return 1
        fi

        config_file="${valid_files[$((choice-1))]}"
    fi

    local proto
    proto="$(get_file_protocol "$config_file")"

    # Stop any existing VPN
    local current_status
    current_status=$(get_active_status)
    if [ "$current_status" != "OFFLINE" ]; then
        echo -e "\n  ${C_WARN}➜${RESET} Active tunnel detected. Restarting..."
        stop_vpn
        sleep 1
    fi

    if [ "$proto" = "WireGuard" ]; then
        # ----------------- WIREGUARD LAUNCH -----------------
        if ! command -v wg-quick >/dev/null 2>&1; then
            echo -e "\n  ${C_DANGER}✖${RESET} 'wg-quick' not found. Install wireguard-tools."
            return 1
        fi

        local iface_name
        iface_name="$(basename "$config_file" .conf)"

        echo -e "\n  ${C_ACCENT}➜${RESET} Starting WireGuard tunnel: ${C_WARN}${BOLD}$(basename "$config_file")${RESET}"
        
        echo "$config_file" > "$CONF_FILE"
        chmod 666 "$CONF_FILE" 2>/dev/null
        echo "wireguard" > "$TYPE_FILE"
        chmod 666 "$TYPE_FILE" 2>/dev/null
        echo "$iface_name" > "$IFACE_FILE"
        chmod 666 "$IFACE_FILE" 2>/dev/null

        local wg_out
        if wg_out=$(wg-quick up "$config_file" 2>&1); then
            sleep 0.5
            local wg_ip
            wg_ip=$(get_iface_ip "$iface_name")
            [ -z "$wg_ip" ] && wg_ip="connected"
            echo -e "  ${C_SUCCESS}✔${RESET} ${C_SUCCESS}${BOLD}WireGuard connected successfully!${RESET} ${C_MUTED}($wg_ip)${RESET}\n"
            status_vpn
        else
            echo -e "  ${C_DANGER}✖${RESET} ${C_DANGER}${BOLD}WireGuard connection failed.${RESET}\n"
            echo -e "   ${C_SUBTLE}Error output:${RESET}"
            echo -e "   ${C_DIM}──────────────────────────────────────────────────${RESET}"
            echo "$wg_out" | while IFS= read -r l; do echo -e "     ${C_MUTED}$l${RESET}"; done
            echo -e "   ${C_DIM}──────────────────────────────────────────────────${RESET}"
            rm -f "$CONF_FILE" "$TYPE_FILE" "$IFACE_FILE"
            return 1
        fi

    else
        # ------------------ OPENVPN LAUNCH ------------------
        if ! command -v openvpn >/dev/null 2>&1; then
            echo -e "\n  ${C_DANGER}✖${RESET} 'openvpn' binary not found."
            return 1
        fi

        echo -e "\n  ${C_ACCENT}➜${RESET} Starting OpenVPN tunnel: ${C_WARN}${BOLD}$(basename "$config_file")${RESET}"
        > "$LOG_FILE"
        chmod 666 "$LOG_FILE" 2>/dev/null
        echo "$config_file" > "$CONF_FILE"
        chmod 666 "$CONF_FILE" 2>/dev/null
        echo "openvpn" > "$TYPE_FILE"
        chmod 666 "$TYPE_FILE" 2>/dev/null

        openvpn --config "$config_file" \
                --daemon \
                --writepid "$PID_FILE" \
                --log "$LOG_FILE"

        echo -ne "  ${C_MUTED}⏳ Connecting... ${RESET}"
        local count=0
        local connected=false
        local spinner=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')

        while [ $count -lt 18 ]; do
            local spin_idx=$((count % ${#spinner[@]}))
            echo -ne "\b${C_PREFIX}${spinner[$spin_idx]}${RESET}"
            sleep 1
            ((count++))
            if grep -q "Initialization Sequence Completed" "$LOG_FILE" 2>/dev/null; then
                connected=true
                break
            fi
            if ! pgrep -x openvpn >/dev/null; then
                break
            fi
        done
        echo -ne "\b \b\n"

        if [ "$connected" = true ]; then
            local ip
            ip=$(get_iface_ip "tun0")
            [ -z "$ip" ] && ip=$(ip -4 addr 2>/dev/null | grep -B2 'tun' | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1)
            echo -e "  ${C_SUCCESS}✔${RESET} ${C_SUCCESS}${BOLD}OpenVPN connected successfully!${RESET} ${C_MUTED}($ip)${RESET}\n"
            status_vpn
        else
            echo -e "  ${C_DANGER}✖${RESET} ${C_DANGER}${BOLD}Connection failed or timed out.${RESET}\n"
            echo -e "   ${C_SUBTLE}Recent log entries (${LOG_FILE}):${RESET}"
            echo -e "   ${C_DIM}──────────────────────────────────────────────────${RESET}"
            while IFS= read -r line; do
                echo -e "     ${C_MUTED}$line${RESET}"
            done < <(tail -n 8 "$LOG_FILE" 2>/dev/null)
            echo -e "   ${C_DIM}──────────────────────────────────────────────────${RESET}"
        fi
    fi
}

show_logs() {
    local status_info
    status_info=$(get_active_status)
    local proto="${status_info%%|*}"

    if [ "$proto" = "WIREGUARD" ]; then
        local iface ip cfg
        IFS='|' read -r _ iface ip cfg <<< "$status_info"
        echo -e "\n ${C_PREFIX}::${RESET} ${BOLD}WireGuard Interface Status${RESET} ${C_MUTED}($iface)${RESET}"
        echo -e "    ${C_MUTED}Press any key or [Ctrl+C] to return${RESET}\n"
        
        if command -v wg >/dev/null 2>&1; then
            wg show "$iface" 2>/dev/null | while IFS= read -r line; do
                echo -e "   ${C_TEXT}$line${RESET}"
            done
        else
            ip -d link show "$iface" 2>/dev/null
        fi
        wait_key
        return
    fi

    if [ ! -f "$LOG_FILE" ]; then
        echo -e "\n  ${C_MUTED}○ No logs found in $LOG_FILE${RESET}"
        wait_key
        return
    fi

    echo -e "\n ${C_PREFIX}::${RESET} ${BOLD}Live log stream${RESET} ${C_MUTED}($LOG_FILE)${RESET}"
    echo -e "    ${C_MUTED}Press [Enter], [q] or [Ctrl+C] to return${RESET}\n"

    # Start tail in background
    tail -n 30 -f "$LOG_FILE" &
    local tail_pid=$!

    # Trap Ctrl+C so it gracefully kills tail and returns to menu
    trap 'kill "$tail_pid" 2>/dev/null; trap - INT; sleep 0.2; return 0' INT

    # Single keypress or Enter to exit log view
    read -rsn1 _ < /dev/tty 2>/dev/null || wait "$tail_pid" 2>/dev/null

    kill "$tail_pid" 2>/dev/null
    trap - INT
}

interactive_menu() {
    while true; do
        clear
        print_banner
        status_vpn
        echo ""
        echo -e "   ${C_ACCENT}[1]${RESET}  ${BOLD}Connect VPN${RESET}        ${C_MUTED}(select .ovpn / .conf profile)${RESET}"
        echo -e "   ${C_ACCENT}[2]${RESET}  ${BOLD}Disconnect${RESET}         ${C_MUTED}(terminate active tunnel)${RESET}"
        echo -e "   ${C_ACCENT}[3]${RESET}  ${BOLD}Refresh status${RESET}"
        echo -e "   ${C_ACCENT}[4]${RESET}  ${BOLD}Live logs${RESET}          ${C_MUTED}(stream / view tunnel logs)${RESET}"
        echo -e "   ${C_ACCENT}[q]${RESET}  ${BOLD}Quit${RESET}"
        echo ""
        read -rsn1 -p " ➜ Select option [1-4, q]: " opt
        # Read any remaining escape sequence characters if ESC was pressed
        if [[ "$opt" == $'\e' ]]; then
            read -rsn2 -t 0.01 _ 2>/dev/null
        fi
        echo ""
        case "$opt" in
            1)
                start_vpn
                wait_key
                ;;
            2)
                echo ""
                stop_vpn
                wait_key
                ;;
            3)
                # Loop will refresh and display updated status immediately
                ;;
            4)
                show_logs
                ;;
            5|[qQ]|x|X|$'\e'*)
                exit 0
                ;;
            "")
                # Enter pressed without character, refresh
                ;;
            *)
                echo -e "\n  ${C_DANGER}Invalid option!${RESET}"
                sleep 0.6
                ;;
        esac
    done
}

# Main routing
case "$1" in
    start|up|connect)
        print_banner
        start_vpn "$2"
        echo ""
        ;;
    stop|down|disconnect)
        print_banner
        stop_vpn
        echo ""
        ;;
    status|info)
        print_banner
        status_vpn
        echo ""
        ;;
    logs|log)
        show_logs
        ;;
    restart)
        print_banner
        stop_vpn
        echo ""
        start_vpn "$2"
        echo ""
        ;;
    help|--help|-h)
        print_banner
        echo -e "   ${C_PREFIX}${BOLD}$SCRIPT_NAME${RESET}                     ${C_MUTED}→ Full interactive menu${RESET}"
        echo -e "   ${C_PREFIX}${BOLD}$SCRIPT_NAME start${RESET}               ${C_MUTED}→ Select and launch an .ovpn / .conf profile${RESET}"
        echo -e "   ${C_PREFIX}${BOLD}$SCRIPT_NAME start file.ovpn${RESET}     ${C_MUTED}→ Launch profile directly${RESET}"
        echo -e "   ${C_PREFIX}${BOLD}$SCRIPT_NAME stop${RESET}                ${C_MUTED}→ Disconnect active tunnel${RESET}"
        echo -e "   ${C_PREFIX}${BOLD}$SCRIPT_NAME status${RESET}              ${C_MUTED}→ Show status, IP and active configuration${RESET}"
        echo -e "   ${C_PREFIX}${BOLD}$SCRIPT_NAME logs${RESET}                ${C_MUTED}→ Stream or inspect tunnel logs${RESET}"
        echo -e "   ${C_PREFIX}${BOLD}$SCRIPT_NAME restart [file]${RESET}      ${C_MUTED}→ Restart the tunnel${RESET}\n"
        ;;
    *)
        interactive_menu
        ;;
esac
