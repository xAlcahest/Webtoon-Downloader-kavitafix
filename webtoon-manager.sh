#!/bin/bash

# Webtoon Manager - Intermediario per download e monitoraggio automatico
# Versione: 1.0
# Author: xAlcahest

set -e

# Configurazioni di default
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/webtoon-config.conf"
DOWNLOADS_DIR="${SCRIPT_DIR}/downloads"
LOG_FILE="${SCRIPT_DIR}/webtoon-manager.log"
CRON_CHECK_FILE="${SCRIPT_DIR}/.cron_urls"

# Colori per output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Funzione di logging
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

# Funzione per stampare help
show_help() {
    echo -e "${BLUE}Webtoon Manager - Download e monitoraggio automatico${NC}"
    echo ""
    echo "Utilizzo:"
    echo "  $0 download <URL> [opzioni]     - Scarica webtoon (aggiunge automaticamente al monitoraggio)"
    echo "  $0 list-monitored               - Lista URLs monitorati automaticamente"
    echo "  $0 remove-monitor <URL>         - Rimuove URL dal monitoraggio automatico"
    echo "  $0 setup-cron                   - Configura il cron job di sistema (ogni 6 ore)"
    echo "  $0 remove-cron                  - Rimuove il cron job di sistema"
    echo "  $0 check-updates                - Controlla aggiornamenti manualmente (solo --latest)"
    echo "  $0 config                       - Configura Kavita e altre impostazioni"
    echo ""
    echo "Opzioni download:"
    echo "  --start <num>                   - Capitolo di inizio"
    echo "  --end <num>                     - Capitolo di fine"
    echo "  --format <cbz|pdf|images>       - Formato output (default: cbz)"
    echo "  --quality <40-100>              - Qualità immagini (default: 100)"
    echo "  --concurrent-chapters <num>     - Capitoli scaricati contemporaneamente (default: 3)"
    echo "  --concurrent-images <num>       - Immagini/pagine per capitolo contemporaneamente (default: 10)"
    echo ""
    echo "Logica:"
    echo "  - Il download manuale scarica TUTTI gli episodi e aggiunge la serie al monitoraggio"
    echo "  - Il monitoraggio automatico (cron) scarica solo gli episodi NUOVI (--latest)"
    echo ""
    echo \"Esempi:\"\n    echo \"  $0 download 'https://www.webtoons.com/en/fantasy/tower-of-god/list?title_no=95' --format cbz\"\n    echo \"  $0 download 'URL' --concurrent-chapters 5 --concurrent-images 20 --quality 90\"\n    echo \"  $0 setup-cron  # Configura controllo automatico ogni 6 ore\"\n    echo \"  $0 list-monitored  # Vedi quali serie sono monitorate\"\n    echo \"\"\n    echo \"Performance Tips:\"\n    echo \"  • --concurrent-chapters 1-3: Sicuro per la maggior parte dei server\"\n    echo \"  • --concurrent-images 5-15: Bilanciamento velocità/stabilità\"\n    echo \"  • Valori troppo alti possono causare ban temporanei\"\n}"
}

# Funzione per creare config di default
create_default_config() {
    cat > "${CONFIG_FILE}" << EOF
# Configurazione Webtoon Manager

# Kavita Settings
KAVITA_URL="http://localhost:5000"
KAVITA_API_KEY=""
KAVITA_LIBRARY_ID=1

# Download Settings
DEFAULT_FORMAT="cbz"
DEFAULT_QUALITY=100
CONCURRENT_CHAPTERS=3
CONCURRENT_IMAGES=10

# Directories
DOWNLOADS_DIR="${DOWNLOADS_DIR}"

# Notification Settings (opzionale)
DISCORD_WEBHOOK_URL=""
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""
EOF
    log "File di configurazione creato: ${CONFIG_FILE}"
    echo -e "${YELLOW}Modifica ${CONFIG_FILE} per configurare Kavita e altre impostazioni${NC}"
}

# Carica configurazione
load_config() {
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        create_default_config
        return 1
    fi
    source "${CONFIG_FILE}"
    return 0
}

# Funzione per configurare interattivamente
configure() {
    echo -e "${BLUE}Configurazione Webtoon Manager${NC}"
    
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        create_default_config
    fi
    
    # Backup della config esistente
    cp "${CONFIG_FILE}" "${CONFIG_FILE}.backup"
    
    echo ""
    echo "Configurazione Kavita:"
    read -p "URL Kavita (default: http://localhost:5000): " kavita_url
    kavita_url=${kavita_url:-"http://localhost:5000"}
    
    read -p "API Key Kavita: " kavita_api_key
    
    read -p "Library ID Kavita (default: 1): " kavita_library_id
    kavita_library_id=${kavita_library_id:-1}
    
    echo ""
    echo "Impostazioni Download:"
    read -p "Formato di default (cbz/pdf/images) [cbz]: " default_format
    default_format=${default_format:-"cbz"}
    
    read -p "Qualità di default (40-100) [100]: " default_quality
    default_quality=${default_quality:-100}
    
    read -p "Capitoli contemporanei (1-10) [3]: " concurrent_chapters
    concurrent_chapters=${concurrent_chapters:-3}
    
    read -p "Immagini contemporanee per capitolo (1-50) [10]: " concurrent_images
    concurrent_images=${concurrent_images:-10}
    
    # Aggiorna il file di config
    sed -i "s|KAVITA_URL=.*|KAVITA_URL=\"${kavita_url}\"|" "${CONFIG_FILE}"
    sed -i "s|KAVITA_API_KEY=.*|KAVITA_API_KEY=\"${kavita_api_key}\"|" "${CONFIG_FILE}"
    sed -i "s|KAVITA_LIBRARY_ID=.*|KAVITA_LIBRARY_ID=${kavita_library_id}|" "${CONFIG_FILE}"
    sed -i "s|DEFAULT_FORMAT=.*|DEFAULT_FORMAT=\"${default_format}\"|" "${CONFIG_FILE}"
    sed -i "s|DEFAULT_QUALITY=.*|DEFAULT_QUALITY=${default_quality}|" "${CONFIG_FILE}"
    sed -i "s|CONCURRENT_CHAPTERS=.*|CONCURRENT_CHAPTERS=${concurrent_chapters}|" "${CONFIG_FILE}"
    sed -i "s|CONCURRENT_IMAGES=.*|CONCURRENT_IMAGES=${concurrent_images}|" "${CONFIG_FILE}"
    
    echo -e "${GREEN}Configurazione salvata!${NC}"
    
    # Test connessione Kavita
    if [[ -n "${kavita_api_key}" ]]; then
        echo "Testando connessione a Kavita..."
        test_kavita_connection "${kavita_url}" "${kavita_api_key}"
    fi
}

# Funzione per ottenere JWT token da API key di Kavita
get_kavita_jwt_token() {
    if [[ -z "${KAVITA_URL}" ]] || [[ -z "${KAVITA_API_KEY}" ]]; then
        log "WARN: Kavita non configurato (URL o API_KEY mancanti)"
        return 1
    fi
    
    local auth_endpoint="${KAVITA_URL}/api/Plugin/authenticate"
    local plugin_name="webtoon-manager"
    
    log "Ottenendo JWT token da Kavita..."
    
    local response=$(curl -s -w "%{http_code}" -o /tmp/kavita_auth.json \
        -X POST "${auth_endpoint}?apiKey=${KAVITA_API_KEY}&pluginName=${plugin_name}" \
        -H "Content-Type: application/json")
    
    local http_code="${response}"
    
    if [[ "${http_code}" == "200" ]]; then
        # Estrai il token dalla risposta JSON
        local jwt_token=$(grep -o '"token":"[^"]*"' /tmp/kavita_auth.json | cut -d'"' -f4)
        
        if [[ -n "${jwt_token}" ]]; then
            log "✓ JWT token ottenuto con successo"
            echo "${jwt_token}"
            rm -f /tmp/kavita_auth.json
            return 0
        else
            log "✗ Errore: Token non trovato nella risposta"
            rm -f /tmp/kavita_auth.json
            return 1
        fi
    else
        log "✗ Errore autenticazione Kavita (HTTP ${http_code})"
        log "Controlla KAVITA_URL e KAVITA_API_KEY nella configurazione"
        rm -f /tmp/kavita_auth.json
        return 1
    fi
}

# Test connessione Kavita con autenticazione corretta (protocollo ufficiale)
test_kavita_connection() {
    local url="$1"
    local api_key="$2"
    
    echo "Testando autenticazione API Kavita..."
    
    # Salva temporaneamente i valori globali
    local old_url="${KAVITA_URL}"
    local old_key="${KAVITA_API_KEY}"
    
    # Imposta temporaneamente per il test
    KAVITA_URL="${url}"
    KAVITA_API_KEY="${api_key}"
    
    # Prova a ottenere JWT token
    local jwt_token
    if jwt_token=$(get_kavita_jwt_token); then
        echo -e "${GREEN}✓ Autenticazione Kavita riuscita!${NC}"
        echo -e "${BLUE}  → API Key valida${NC}"
        echo -e "${BLUE}  → JWT Token ottenuto${NC}"
        
        # Ripristina i valori originali
        KAVITA_URL="${old_url}"
        KAVITA_API_KEY="${old_key}"
        return 0
    else
        echo -e "${RED}✗ Errore autenticazione Kavita${NC}"
        echo -e "${YELLOW}  → Controlla URL e API Key${NC}"
        
        # Ripristina i valori originali
        KAVITA_URL="${old_url}"
        KAVITA_API_KEY="${old_key}"
        return 1
    fi
}
        echo -e "${GREEN}✓ Autenticazione Kavita riuscita!${NC}"
        echo -e "${BLUE}  → API Key valida${NC}"
        echo -e "${BLUE}  → JWT Token ottenuto${NC}"
        
        # Ripristina i valori originali
        KAVITA_URL="${old_url}"
        KAVITA_API_KEY="${old_key}"
        return 0
    else
        echo -e "${RED}✗ Errore autenticazione Kavita${NC}"
        echo -e "${YELLOW}  → Controlla URL e API Key${NC}"
        
        # Ripristina i valori originali
        KAVITA_URL="${old_url}"
        KAVITA_API_KEY="${old_key}"
        return 1
    fi
}

# Funzione per notificare Kavita di fare scan (con autenticazione corretta)
trigger_kavita_scan() {
    if [[ -z "${KAVITA_URL}" ]] || [[ -z "${KAVITA_API_KEY}" ]]; then
        log "WARN: Kavita non configurato, skip scan"
        return 0
    fi
    
    log "Triggering Kavita library scan..."
    
    # Ottieni JWT token
    local jwt_token
    if ! jwt_token=$(get_kavita_jwt_token); then
        log "✗ Impossibile ottenere JWT token, scan annullato"
        return 1
    fi
    
    # Usa il JWT token per triggare il scan
    local scan_endpoint="${KAVITA_URL}/api/Library"
    
    # Prova prima scan-all (tutti le librerie)
    local response=$(curl -s -w "%{http_code}" -o /dev/null \
        -X POST "${scan_endpoint}/scan-all" \
        -H "Authorization: Bearer ${jwt_token}" \
        -H "Content-Type: application/json")
    
    if [[ "${response}" == "200" ]] || [[ "${response}" == "204" ]]; then
        log "✓ Kavita library scan triggered successfully (all libraries)"
        return 0
    elif [[ -n "${KAVITA_LIBRARY_ID}" ]]; then
        # Fallback: prova scan di libreria specifica
        log "Tentando scan di libreria specifica ID: ${KAVITA_LIBRARY_ID}"
        
        response=$(curl -s -w "%{http_code}" -o /dev/null \
            -X POST "${scan_endpoint}/${KAVITA_LIBRARY_ID}/scan" \
            -H "Authorization: Bearer ${jwt_token}" \
            -H "Content-Type: application/json")
        
        if [[ "${response}" == "200" ]] || [[ "${response}" == "204" ]]; then
            log "✓ Kavita library scan triggered successfully (library ${KAVITA_LIBRARY_ID})"
            return 0
        else
            log "✗ Errore triggering Kavita scan (HTTP ${response})"
            return 1
        fi
    else
        log "✗ Errore triggering Kavita scan (HTTP ${response})"
        return 1
    fi
}

# Funzione per inviare notifiche (opzionale)
send_notification() {
    local title="$1"
    local message="$2"
    
    # Discord webhook (se configurato)
    if [[ -n "${DISCORD_WEBHOOK_URL}" ]]; then
        curl -s -X POST "${DISCORD_WEBHOOK_URL}" \
            -H "Content-Type: application/json" \
            -d "{\"content\":\"**${title}**\n${message}\"}" > /dev/null
    fi
    
    # Telegram (se configurato)
    if [[ -n "${TELEGRAM_BOT_TOKEN}" ]] && [[ -n "${TELEGRAM_CHAT_ID}" ]]; then
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            -d "chat_id=${TELEGRAM_CHAT_ID}" \
            -d "text=*${title}*%0A${message}" \
            -d "parse_mode=Markdown" > /dev/null
    fi
}

# Funzione per download
download_webtoon() {
    local url="$1"
    shift
    local extra_args=("$@")
    
    if [[ -z "${url}" ]]; then
        echo -e "${RED}Errore: URL richiesto${NC}"
        exit 1
    fi
    
    # Crea directory downloads se non esiste
    mkdir -p "${DOWNLOADS_DIR}"
    
    # Prepara argomenti con defaults dalla configurazione
    local download_args=()
    local has_concurrent_chapters=false
    local has_concurrent_images=false
    local has_format=false
    local has_quality=false
    
    # Controlla se gli argomenti sono già specificati
    for arg in "${extra_args[@]}"; do
        case "$arg" in
            "--concurrent-chapters") has_concurrent_chapters=true ;;
            "--concurrent-images") has_concurrent_images=true ;;
            "--save-as"|"--format") has_format=true ;;
            "--quality") has_quality=true ;;
        esac
    done
    
    # Aggiungi defaults se non specificati
    if [[ "$has_concurrent_chapters" == "false" ]] && [[ -n "${CONCURRENT_CHAPTERS}" ]]; then
        download_args+=("--concurrent-chapters" "${CONCURRENT_CHAPTERS}")
    fi
    
    if [[ "$has_concurrent_images" == "false" ]] && [[ -n "${CONCURRENT_IMAGES}" ]]; then
        download_args+=("--concurrent-images" "${CONCURRENT_IMAGES}")
    fi
    
    if [[ "$has_format" == "false" ]] && [[ -n "${DEFAULT_FORMAT}" ]]; then
        download_args+=("--save-as" "${DEFAULT_FORMAT}")
    fi
    
    if [[ "$has_quality" == "false" ]] && [[ -n "${DEFAULT_QUALITY}" ]]; then
        download_args+=("--quality" "${DEFAULT_QUALITY}")
    fi
    
    # Combina argomenti utente + defaults
    local all_args=("${extra_args[@]}" "${download_args[@]}")
    
    log "Avvio download completo: ${url}"
    log "Parametri: Capitoli contemporanei=${CONCURRENT_CHAPTERS:-"default"}, Immagini contemporanee=${CONCURRENT_IMAGES:-"default"}"
    echo -e "${BLUE}Scaricando tutti gli episodi e aggiungendo al monitoraggio automatico...${NC}"
    echo -e "${YELLOW}🚀 Concorrenza: ${CONCURRENT_CHAPTERS:-"default"} capitoli, ${CONCURRENT_IMAGES:-"default"} immagini per capitolo${NC}"
    
    # Esegui il download con poetry
    cd "${SCRIPT_DIR}"
    if poetry run webtoon-downloader "${url}" --output "${DOWNLOADS_DIR}" "${all_args[@]}"; then
        log "✓ Download completato: ${url}"
        
        # Aggiungi automaticamente al monitoraggio per futuri --latest
        add_to_monitoring_internal "${url}" "${extra_args[@]}"
        
        # Trigger Kavita scan
        trigger_kavita_scan
        
        # Notifica (se configurato)
        send_notification "Webtoon Download" "Download completato e aggiunto al monitoraggio: ${url}"
        
        echo -e "${GREEN}✓ Serie scaricata e aggiunta al monitoraggio automatico!${NC}"
        
        return 0
    else
        log "✗ Errore durante download: ${url}"
        send_notification "Webtoon Error" "Errore download: ${url}"
        return 1
    fi
}

# Funzione interna per aggiungere URL al monitoraggio (usata dopo download completo)
add_to_monitoring_internal() {
    local url="$1"
    shift
    local extra_args=("$@")
    
    # Crea file cron se non esiste
    touch "${CRON_CHECK_FILE}"
    
    # Controlla se URL già presente
    if grep -Fxq "${url}" "${CRON_CHECK_FILE}"; then
        log "URL già in monitoraggio: ${url}"
        return 0
    fi
    
    # Aggiungi URL con opzioni
    echo "${url} ${extra_args[*]}" >> "${CRON_CHECK_FILE}"
    log "URL aggiunto automaticamente al monitoraggio: ${url}"
    
    # Suggerisci di configurare il cron se non già fatto
    if ! crontab -l 2>/dev/null | grep -q "webtoon-manager.sh"; then
        echo -e "${YELLOW}💡 Esegui '$0 setup-cron' per attivare il monitoraggio automatico ogni 6 ore${NC}"
    fi
}

# Funzione per rimuovere URL dal monitoraggio
remove_from_monitoring() {
    local url="$1"
    
    if [[ -z "${url}" ]]; then
        echo -e "${RED}Errore: URL richiesto${NC}"
        exit 1
    fi
    
    if [[ ! -f "${CRON_CHECK_FILE}" ]]; then
        echo -e "${YELLOW}Nessun URL in monitoraggio${NC}"
        return 0
    fi
    
    # Rimuovi URL dal file
    local temp_file="${CRON_CHECK_FILE}.tmp"
    grep -v -F "${url}" "${CRON_CHECK_FILE}" > "${temp_file}" || true
    mv "${temp_file}" "${CRON_CHECK_FILE}"
    
    log "URL rimosso dal monitoraggio: ${url}"
    echo -e "${GREEN}✓ URL rimosso dal monitoraggio${NC}"
}

# Funzione per listare URLs monitorati
list_monitored() {
    if [[ ! -f "${CRON_CHECK_FILE}" ]] || [[ ! -s "${CRON_CHECK_FILE}" ]]; then
        echo -e "${YELLOW}Nessun URL in monitoraggio${NC}"
        return 0
    fi
    
    echo -e "${BLUE}URLs in monitoraggio automatico:${NC}"
    echo ""
    local count=1
    while IFS= read -r line; do
        echo "${count}. ${line}"
        ((count++))
    done < "${CRON_CHECK_FILE}"
}

# Funzione per controllare aggiornamenti (usata dal cron) - SOLO --latest
check_updates() {
    if [[ ! -f "${CRON_CHECK_FILE}" ]] || [[ ! -s "${CRON_CHECK_FILE}" ]]; then
        log "Nessuna serie in monitoraggio"
        return 0
    fi
    
    log "Inizio controllo automatico nuovi episodi (--latest)"
    local new_episodes_found=false
    local series_count=0
    
    while IFS= read -r line; do
        if [[ -n "${line}" ]]; then
            local url=$(echo "${line}" | awk '{print $1}')
            local args=$(echo "${line}" | cut -d' ' -f2-)
            ((series_count++))
            
            log "Controllo nuovi episodi per serie #${series_count}: ${url}"
            
            cd "${SCRIPT_DIR}"
            # SEMPRE usa --latest per il monitoraggio automatico + parametri di concorrenza
            local update_args=("--latest" "--output" "${DOWNLOADS_DIR}")
            
            # Aggiungi parametri di concorrenza se configurati
            if [[ -n "${CONCURRENT_CHAPTERS}" ]]; then
                update_args+=("--concurrent-chapters" "${CONCURRENT_CHAPTERS}")
            fi
            if [[ -n "${CONCURRENT_IMAGES}" ]]; then
                update_args+=("--concurrent-images" "${CONCURRENT_IMAGES}")
            fi
            
            if poetry run webtoon-downloader "${url}" "${update_args[@]}" ${args}; then
                log "✓ Controllo episodi completato per serie #${series_count}"
                new_episodes_found=true
            else
                log "✗ Errore durante controllo serie #${series_count}: ${url}"
            fi
        fi
    done < "${CRON_CHECK_FILE}"
    
    if [[ "${new_episodes_found}" == "true" ]]; then
        log "Nuovi episodi trovati! Triggering Kavita scan..."
        trigger_kavita_scan
        send_notification "Webtoon Updates" "Nuovi episodi scaricati automaticamente da ${series_count} serie monitorate"
    else
        log "Nessun nuovo episodio trovato nelle ${series_count} serie monitorate"
    fi
    
    log "Controllo automatico completato"
}

# Funzione per configurare cron job di SISTEMA (perfetto per root)
setup_cron() {
    local cron_line="0 */6 * * * cd \"${SCRIPT_DIR}\" && ./webtoon-manager.sh check-updates >> \"${LOG_FILE}\" 2>&1"
    
    # Controlla se il cron job esiste già
    if ! crontab -l 2>/dev/null | grep -q "webtoon-manager.sh"; then\n        # Aggiungi al crontab di sistema
        (crontab -l 2>/dev/null; echo "${cron_line}") | crontab -
        log "Cron job di sistema configurato: controllo --latest ogni 6 ore"
        echo -e "${GREEN}✓ Cron job di sistema configurato!${NC}"
        echo -e "${BLUE}  → Controllo automatico ogni 6 ore alle: 00:00, 06:00, 12:00, 18:00${NC}"
        echo -e "${BLUE}  → Usa solo --latest per nuovi episodi delle serie già scaricate${NC}"
        
        # Mostra il prossimo run time
        echo -e "${YELLOW}💡 Controlla con 'crontab -l' per verificare${NC}"
    else
        echo -e "${YELLOW}Cron job già configurato${NC}"
        echo -e "${BLUE}Controlla con: crontab -l${NC}"
    fi
}

# Funzione per rimuovere cron job di SISTEMA
remove_cron() {
    if crontab -l 2>/dev/null | grep -q "webtoon-manager.sh"; then
        crontab -l 2>/dev/null | grep -v "webtoon-manager.sh" | crontab -
        log "Cron job di sistema rimosso"
        echo -e "${GREEN}✓ Cron job di sistema rimosso${NC}"
        echo -e "${BLUE}Le serie rimangono in monitoraggio, ma non verranno più controllate automaticamente${NC}"
    else
        echo -e "${YELLOW}Nessun cron job trovato nel sistema${NC}"
    fi
}

# Main
main() {
    local command="$1"
    
    if [[ -z "${command}" ]]; then
        show_help
        exit 1
    fi
    
    # Carica configurazione (se disponibile)
    load_config || echo -e "${YELLOW}Usa '$0 config' per configurare${NC}"
    
    case "${command}" in
        "download")
            shift
            local url="$1"
            shift
            download_webtoon "${url}" "$@"
            ;;
        "list-monitored")
            list_monitored
            ;;
        "remove-monitor")
            shift
            remove_from_monitoring "$1"
            ;;
        "check-updates")
            check_updates
            ;;
        "setup-cron")
            setup_cron
            ;;
        "remove-cron")
            remove_cron
            ;;
        "config")
            configure
            ;;
        "help"|"--help"|"-h")
            show_help
            ;;
        *)
            echo -e "${RED}Comando sconosciuto: ${command}${NC}"
            echo "Usa '$0 help' per vedere i comandi disponibili"
            exit 1
            ;;
    esac
}

# Esegui main con tutti gli argomenti
main "$@"