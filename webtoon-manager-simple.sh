#!/bin/bash

# Webtoon Manager - Intermediario per download e monitoraggio automatico
# Versione: 1.1
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
    echo "Esempi:"
    echo "  $0 download 'https://www.webtoons.com/en/fantasy/tower-of-god/list?title_no=95' --format cbz"
    echo "  $0 download 'URL' --concurrent-chapters 5 --concurrent-images 20 --quality 90"
    echo "  $0 setup-cron  # Configura controllo automatico ogni 6 ore"
    echo "  $0 list-monitored  # Vedi quali serie sono monitorate"
    echo ""
    echo "Performance Tips:"
    echo "  • --concurrent-chapters 1-3: Sicuro per la maggior parte dei server"
    echo "  • --concurrent-images 5-15: Bilanciamento velocità/stabilità"
    echo "  • Valori troppo alti possono causare ban temporanei"
}

# Funzione per creare config di default
create_default_config() {
    cat > "${CONFIG_FILE}" << 'EOF'
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
DOWNLOADS_DIR="./downloads"

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
    
    # Test connessione Kavita se API key fornita
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

# Test connessione Kavita
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

# Funzione per triggare scan Kavita
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
    
    # Prova prima scan-all
    local response=$(curl -s -w "%{http_code}" -o /dev/null \
        -X POST "${scan_endpoint}/scan-all" \
        -H "Authorization: Bearer ${jwt_token}" \
        -H "Content-Type: application/json")
    
    if [[ "${response}" == "200" ]] || [[ "${response}" == "204" ]]; then
        log "✓ Kavita library scan triggered successfully (all libraries)"
        return 0
    elif [[ -n "${KAVITA_LIBRARY_ID}" ]]; then
        # Fallback: scan libreria specifica
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

# Main
main() {
    local command="$1"
    
    if [[ -z "${command}" ]]; then
        show_help
        exit 1
    fi
    
    # Carica configurazione
    load_config || echo -e "${YELLOW}Usa '$0 config' per configurare${NC}"
    
    case "${command}" in
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