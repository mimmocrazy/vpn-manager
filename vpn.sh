#!/usr/bin/env bash
# ==============================================================================
# 🛡️ OpenVPN Modern Manager CLI
# ==============================================================================

SCRIPT_NAME="$(basename "$0")"
REAL_SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$REAL_SCRIPT_PATH")" && pwd)"
VPN_DIR="/home/mimmo/VPNs"
[ ! -d "$VPN_DIR" ] && VPN_DIR="$SCRIPT_DIR"

LOG_FILE="/tmp/openvpn.log"
PID_FILE="/tmp/openvpn.pid"
CONF_FILE="/tmp/openvpn.conf"

# ANSI Color Palette (Modern 256-color & Styled)
RESET='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
ITALIC='\033[3m'

# Colors
C_PRIMARY='\033[38;5;39m'     # Electric Blue / Cyan
C_ACCENT='\033[38;5;141m'     # Soft Purple
C_SUCCESS='\033[38;5;48m'     # Emerald Green
C_WARN='\033[38;5;214m'       # Amber Orange
C_DANGER='\033[38;5;203m'     # Coral Red
C_MUTED='\033[38;5;244m'      # Dim Gray
C_BG_DARK='\033[48;5;236m'    # Dark gray background
C_WHITE='\033[38;5;255m'      # Bright White

print_banner() {
    echo -e "${C_PRIMARY}${BOLD}🛡️  OPENVPN MANAGER${RESET}  ${C_MUTED}•  CLI Control Hub${RESET}"
    echo -e "${C_MUTED}─────────────────────────────────────────────────────────────${RESET}"
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

get_vpn_pid() {
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null; then
        cat "$PID_FILE"
    else
        pgrep -x openvpn | head -n 1
    fi
}

get_vpn_config() {
    local pid="$1"
    if [ -f "$CONF_FILE" ]; then
        local saved_cfg
        saved_cfg=$(cat "$CONF_FILE" 2>/dev/null)
        if [ -n "$saved_cfg" ]; then
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

get_vpn_ip() {
    ip -4 addr show dev tun0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || echo ""
}

status_vpn() {
    local pid
    pid=$(get_vpn_pid)
    
    echo -e "${C_ACCENT}${BOLD}STATO TUNNEL${RESET}"
    echo -e "${C_MUTED}─────────────────────────────────────────────────────────────${RESET}"
    if [ -n "$pid" ]; then
        local ip cfg
        ip=$(get_vpn_ip)
        cfg=$(get_vpn_config "$pid")
        [ -z "$ip" ] && ip="In attesa IP..."
        
        echo -e "  ${C_SUCCESS}${BOLD}● Stato${RESET}        : ${C_SUCCESS}${BOLD}ONLINE${RESET}"
        if [ -n "$cfg" ]; then
            echo -e "  ${C_WARN}⚙ Config${RESET}       : ${C_WARN}${BOLD}$(basename "$cfg")${RESET}"
            if [ "$(basename "$cfg")" != "$cfg" ]; then
                echo -e "  ${C_MUTED}📍 Percorso${RESET}    : ${C_MUTED}$cfg${RESET}"
            fi
        fi
        echo -e "  ${C_WHITE}🌐 Interfaccia${RESET} : ${BOLD}tun0${RESET}"
        echo -e "  ${C_PRIMARY}🎯 IP Tunnel${RESET}   : ${C_PRIMARY}${BOLD}$ip${RESET}"
        echo -e "  ${C_MUTED}🆔 Processo${RESET}    : ${C_MUTED}PID $pid${RESET}"
        echo -e "  ${C_MUTED}📜 File Log${RESET}    : ${C_MUTED}$LOG_FILE${RESET}"
    else
        echo -e "  ${C_DANGER}${BOLD}○ Stato${RESET}        : ${C_DANGER}${BOLD}OFFLINE${RESET} ${C_MUTED}(Nessuna connessione attiva)${RESET}"
    fi
    echo -e "${C_MUTED}─────────────────────────────────────────────────────────────${RESET}"
}

stop_vpn() {
    local pid
    pid=$(get_vpn_pid)
    
    if [ -n "$pid" ]; then
        echo -e "${C_WARN}⚡ Disconnessione in corso (PID: $pid)...${RESET}"
        kill "$pid" 2>/dev/null || pkill -x openvpn
        sleep 1
        
        # Force kill if still lingering
        if pgrep -x openvpn >/dev/null; then
            killall -9 openvpn 2>/dev/null
        fi
        
        rm -f "$PID_FILE" "$CONF_FILE"
        echo -e "${C_SUCCESS}✔ VPN disconnessa con successo.${RESET}"
    else
        rm -f "$PID_FILE" "$CONF_FILE"
        echo -e "${C_MUTED}○ Nessuna VPN attiva da disconnettere.${RESET}"
    fi
}

start_vpn() {
    local config_file="$1"

    # If no config provided, show a styled picker of .ovpn files
    if [ -z "$config_file" ]; then
        # Search in VPN_DIR and current dir
        local search_dirs=("$VPN_DIR")
        [ "$(pwd)" != "$VPN_DIR" ] && [ "$(pwd)" != "$SCRIPT_DIR" ] && search_dirs+=("$(pwd)")

        mapfile -t ovpn_files < <(
            for d in "${search_dirs[@]}"; do
                [ -d "$d" ] && find "$d" -maxdepth 1 -name "*.ovpn" -printf "%p\n"
            done | sort -u
        )
        
        if [ ${#ovpn_files[@]} -eq 0 ]; then
            echo -e "${C_DANGER}✖ Nessun file .ovpn trovato in: ${BOLD}$VPN_DIR${RESET}"
            return 1
        fi

        echo -e "\n${C_ACCENT}📁 Configurazioni disponibili in $VPN_DIR:${RESET}"
        echo -e "${C_MUTED}─────────────────────────────────────────────────────────────${RESET}"
        for i in "${!ovpn_files[@]}"; do
            echo -e "  ${C_PRIMARY}${BOLD}$((i+1))${RESET} ${C_MUTED}❯${RESET} ${C_WHITE}$(basename "${ovpn_files[$i]}")${RESET}"
        done
        echo -e "${C_MUTED}─────────────────────────────────────────────────────────────${RESET}"
        
        read -rp "👉 Seleziona numero [1-${#ovpn_files[@]}]: " choice

        if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#ovpn_files[@]}" ]; then
            echo -e "${C_DANGER}✖ Selezione non valida.${RESET}"
            return 1
        fi

        config_file="${ovpn_files[$((choice-1))]}"
    fi

    # Resolve file path with smart fallbacks (.ovpn extension, VPN_DIR, PWD)
    if [ ! -f "$config_file" ]; then
        if [ -f "$config_file.ovpn" ]; then
            config_file="$config_file.ovpn"
        elif [ -f "$VPN_DIR/$config_file" ]; then
            config_file="$VPN_DIR/$config_file"
        elif [ -f "$VPN_DIR/$config_file.ovpn" ]; then
            config_file="$VPN_DIR/$config_file.ovpn"
        elif [ -f "$(pwd)/$config_file" ]; then
            config_file="$(pwd)/$config_file"
        elif [ -f "$(pwd)/$config_file.ovpn" ]; then
            config_file="$(pwd)/$config_file.ovpn"
        elif [ -f "$SCRIPT_DIR/$config_file" ]; then
            config_file="$SCRIPT_DIR/$config_file"
        elif [ -f "$SCRIPT_DIR/$config_file.ovpn" ]; then
            config_file="$SCRIPT_DIR/$config_file.ovpn"
        else
            echo -e "${C_DANGER}✖ File di configurazione non trovato: ${BOLD}$config_file${RESET}"
            return 1
        fi
    fi

    # Auto-stop if currently connected
    local existing_pid
    existing_pid=$(get_vpn_pid)
    if [ -n "$existing_pid" ]; then
        echo -e "${C_WARN}⚡ VPN già in esecuzione. Riavvio in corso...${RESET}"
        stop_vpn
        sleep 1
    fi

    echo -e "\n${C_PRIMARY}🚀 Avvio tunnel con: ${BOLD}$(basename "$config_file")${RESET}"
    > "$LOG_FILE"
    chmod 666 "$LOG_FILE" 2>/dev/null
    echo "$config_file" > "$CONF_FILE"
    chmod 666 "$CONF_FILE" 2>/dev/null

    openvpn --config "$config_file" \
            --daemon \
            --writepid "$PID_FILE" \
            --log "$LOG_FILE"

    echo -ne "${C_MUTED}⏳ Connessione in corso... ${RESET}"
    local count=0
    local connected=false
    local spinner=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')

    while [ $count -lt 18 ]; do
        local spin_idx=$((count % ${#spinner[@]}))
        echo -ne "\b${C_PRIMARY}${spinner[$spin_idx]}${RESET}"
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
        ip=$(get_vpn_ip)
        echo -e "${C_SUCCESS}${BOLD}✔ Connessione stabilita con successo!${RESET}\n"
        status_vpn
    else
        echo -e "${C_DANGER}${BOLD}✖ Connessione fallita o timeout raggiunto.${RESET}"
        echo -e "${C_WARN}Ultime righe del file di log (${LOG_FILE}):${RESET}"
        echo -e "${C_MUTED}-------------------------------------------------------------${RESET}"
        tail -n 8 "$LOG_FILE" 2>/dev/null
        echo -e "${C_MUTED}-------------------------------------------------------------${RESET}"
    fi
}

show_logs() {
    if [ ! -f "$LOG_FILE" ]; then
        echo -e "${C_MUTED}○ Nessun log presente in $LOG_FILE${RESET}"
        read -rp "Premi INVIO per tornare..."
        return
    fi
    echo -e "${C_PRIMARY}📜 Streaming log in tempo reale (${LOG_FILE})${RESET}"
    echo -e "${C_MUTED}👉 Premi [INVIO] o [Ctrl+C] per tornare al menu${RESET}\n"

    # Start tail in background
    tail -n 30 -f "$LOG_FILE" &
    local tail_pid=$!

    # Trap Ctrl+C so it gracefully kills tail and returns to menu
    trap 'kill "$tail_pid" 2>/dev/null; trap - INT; echo -e "\n${C_SUCCESS}✔ Ritorno al menu in corso...${RESET}"; sleep 0.5; return 0' INT

    # Allow pressing Enter to return as well
    read -r _ < /dev/tty 2>/dev/null || wait "$tail_pid" 2>/dev/null

    kill "$tail_pid" 2>/dev/null
    trap - INT
}

interactive_menu() {
    while true; do
        clear
        print_banner
        echo ""
        status_vpn
        echo ""
        echo -e "${C_ACCENT}${BOLD}AZIONI DISPONIBILI${RESET}"
        echo -e "${C_MUTED}─────────────────────────────────────────────────────────────${RESET}"
        echo -e "  ${C_PRIMARY}${BOLD}1${RESET}  ${C_MUTED}❯${RESET}  ⚡ ${BOLD}Connetti VPN${RESET}        ${C_MUTED}(seleziona config .ovpn)${RESET}"
        echo -e "  ${C_PRIMARY}${BOLD}2${RESET}  ${C_MUTED}❯${RESET}  🔌 ${BOLD}Disconnetti VPN${RESET}     ${C_MUTED}(termina processo openvpn)${RESET}"
        echo -e "  ${C_PRIMARY}${BOLD}3${RESET}  ${C_MUTED}❯${RESET}  📊 ${BOLD}Aggiorna Stato${RESET}      ${C_MUTED}(mostra IP e tunnel)${RESET}"
        echo -e "  ${C_PRIMARY}${BOLD}4${RESET}  ${C_MUTED}❯${RESET}  📜 ${BOLD}Visualizza Log Live${RESET} ${C_MUTED}(tail -f openvpn.log)${RESET}"
        echo -e "  ${C_PRIMARY}${BOLD}5${RESET}  ${C_MUTED}❯${RESET}  🚪 ${BOLD}Esci${RESET}"
        echo -e "${C_MUTED}─────────────────────────────────────────────────────────────${RESET}"
        read -rp "👉 Seleziona un'opzione [1-5]: " opt
        case $opt in
            1)
                start_vpn
                echo ""
                read -rp "Premi INVIO per continuare..."
                ;;
            2)
                echo ""
                stop_vpn
                echo ""
                read -rp "Premi INVIO per continuare..."
                ;;
            3)
                # Loop will refresh and display status
                ;;
            4)
                echo ""
                show_logs
                ;;
            5)
                echo -e "\n${C_SUCCESS}Arrivederci! 👋${RESET}\n"
                exit 0
                ;;
            *)
                echo -e "${C_DANGER}Opzione non valida!${RESET}"
                sleep 1
                ;;
        esac
    done
}

# Main routing
case "$1" in
    start|up|connect)
        print_banner
        start_vpn "$2"
        ;;
    stop|down|disconnect)
        print_banner
        stop_vpn
        ;;
    status|info)
        print_banner
        echo ""
        status_vpn
        echo ""
        ;;
    logs|log)
        show_logs
        ;;
    restart)
        print_banner
        stop_vpn
        start_vpn "$2"
        ;;
    help|--help|-h)
        print_banner
        echo -e "${C_ACCENT}${BOLD}UTILIZZO RAPIDO${RESET}"
        echo -e "${C_MUTED}─────────────────────────────────────────────────────────────${RESET}"
        echo -e "  ${C_PRIMARY}${BOLD}$SCRIPT_NAME${RESET}                     ${C_MUTED}→ Menu interattivo completo${RESET}"
        echo -e "  ${C_PRIMARY}${BOLD}$SCRIPT_NAME start${RESET}               ${C_MUTED}→ Scegli e avvia un file .ovpn${RESET}"
        echo -e "  ${C_PRIMARY}${BOLD}$SCRIPT_NAME start file.ovpn${RESET}     ${C_MUTED}→ Avvia direttamente in background${RESET}"
        echo -e "  ${C_PRIMARY}${BOLD}$SCRIPT_NAME stop${RESET}                ${C_MUTED}→ Disconnette la VPN${RESET}"
        echo -e "  ${C_PRIMARY}${BOLD}$SCRIPT_NAME status${RESET}              ${C_MUTED}→ Mostra stato, IP tun0 e file attivo${RESET}"
        echo -e "  ${C_PRIMARY}${BOLD}$SCRIPT_NAME logs${RESET}                ${C_MUTED}→ Mostra i log live del tunnel${RESET}"
        echo -e "  ${C_PRIMARY}${BOLD}$SCRIPT_NAME restart [file]${RESET}      ${C_MUTED}→ Riavvia la VPN${RESET}"
        echo -e "${C_MUTED}─────────────────────────────────────────────────────────────${RESET}\n"
        ;;
    *)
        interactive_menu
        ;;
esac
