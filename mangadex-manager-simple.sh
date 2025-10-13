#!/bin/bash

# MangaDex Manager - Download e monitoraggio automatico per MangaDex
# Versione: 1.0
# Author: xAlcahest
# Basato su: webtoon-manager-simple.sh

# Configurazioni di default
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/webtoon-config.conf"  # Condivide config con webtoon
LOG_FILE="${SCRIPT_DIR}/mangadex-manager.log"
CRON_CHECK_FILE="${SCRIPT_DIR}/.cron_mangadex_urls"
MANGADEX_BIN="${SCRIPT_DIR}/mangadex-dl"

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
    echo -e "${BLUE}MangaDex Manager - Download e monitoraggio automatico${NC}"
    echo ""
    echo "Utilizzo:"
    echo "  $0 download <URL> [opzioni]     - Scarica manga (aggiunge automaticamente al monitoraggio)"
    echo "  $0 list-monitored               - Lista URLs monitorati automaticamente"
    echo "  $0 remove-monitor <URL>         - Rimuove URL dal monitoraggio automatico"
    echo "  $0 fix-volumeless <cartella>    - Fixa capitoli volumeless in una cartella manga"
    echo "  $0 setup-cron                   - Configura il cron job di sistema (ogni 6 ore)"
    echo "  $0 remove-cron                  - Rimuove il cron job di sistema"
    echo "  $0 check-updates                - Controlla aggiornamenti manualmente"
    echo "  $0 config                       - Configura Kavita e altre impostazioni"
    echo ""
    echo "Opzioni download:"
    echo "  --only-download                 - Solo download nella cartella script (NO Kavita, NO monitoraggio)"
    echo "  --start-chapter <num>           - Capitolo di inizio"
    echo "  --end-chapter <num>             - Capitolo di fine"
    echo "  --save-as <format>              - Formato: raw, cbz, cbz-volume, pdf, epub (default: cbz)"
    echo "  --language <lang>               - Lingua: en, it, es, etc. (default: en)"
    echo "  --cover <quality>               - Cover: original, 512px, 256px, none (default: original)"
    echo "  --use-chapter-title             - Usa titolo capitolo nelle cartelle"
    echo "  --no-group-name                 - Non includere nome gruppo scanlator"
    echo "  --folder <path>                 - Cartella custom (usa {manga.title} come placeholder)"
    echo ""
    echo "Logica:"
    echo "  - Download normale: scarica in cartella Kavita + monitoraggio + scan Kavita"
    echo "  - Download con --only-download: scarica nella cartella script (per test/preview)"
    echo "  - Monitoraggio automatico (cron): scarica solo capitoli NUOVI in cartella Kavita"
    echo ""
    echo "Esempi:"
    echo "  $0 download 'https://mangadex.org/title/MANGA_ID' --save-as cbz-volume"
    echo "  $0 download 'MANGA_ID' --language it --cover 512px"
    echo "  $0 download 'MANGA_ID' --only-download  # Test download nella cartella script"
    echo "  $0 fix-volumeless './Mahou Shoujo ni Akogarete'  # Fixa capitoli senza volume"
    echo "  $0 setup-cron  # Configura controllo automatico ogni 6 ore"
    echo "  $0 list-monitored  # Vedi quali manga sono monitorati"
    echo ""
    echo "Note:"
    echo "  • Usa 'cbz' o 'cbz-volume' per compatibilità Kavita"
    echo "  • Supporta URL completi o solo ID manga"
    echo "  • Condivide configurazione Kavita con webtoon-manager"
    echo "  • Capitoli volumeless (Ch. X senza Vol.): gestiti automaticamente da mangadex-dl"
    echo ""
    echo "Documentazione completa: MANGADEX_DL_REFERENCE.md"
}

# Carica configurazione (condivisa con webtoon)
load_config() {
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        echo -e "${YELLOW}Configurazione non trovata. Usa 'webtoon-manager-simple.sh config' per configurare${NC}"
        return 1
    fi
    source "${CONFIG_FILE}"
    return 0
}

# Funzione per configurare (rimanda a webtoon manager)
configure() {
    echo -e "${BLUE}MangaDex Manager usa la stessa configurazione di Webtoon Manager${NC}"
    echo ""
    echo "Per configurare Kavita e altre impostazioni, esegui:"
    echo -e "${GREEN}  ./webtoon-manager-simple.sh config${NC}"
    echo ""
    echo "Le impostazioni verranno condivise tra i due manager."
}

# Funzione per ottenere JWT token da API key di Kavita
get_kavita_jwt_token() {
    if [[ -z "${KAVITA_URL}" ]] || [[ -z "${KAVITA_API_KEY}" ]]; then
        log "WARN: Kavita non configurato (URL o API_KEY mancanti)" >&2
        return 1
    fi
    
    local auth_endpoint="${KAVITA_URL}/api/Plugin/authenticate"
    local plugin_name="mangadex-manager"
    
    log "Ottenendo JWT token da Kavita..." >&2
    
    local response=$(curl -s -w "%{http_code}" -o /tmp/kavita_auth_mangadex.json \
        -X POST "${auth_endpoint}?apiKey=${KAVITA_API_KEY}&pluginName=${plugin_name}" \
        -H "Content-Type: application/json" \
        -d '{}')
    
    local http_code="${response}"
    
    if [[ "${http_code}" == "200" ]]; then
        local jwt_token=$(grep -o '"token":"[^"]*"' /tmp/kavita_auth_mangadex.json | cut -d'"' -f4)
        
        if [[ -n "${jwt_token}" ]]; then
            log "✓ JWT token ottenuto con successo" >&2
            echo "${jwt_token}"
            rm -f /tmp/kavita_auth_mangadex.json
            return 0
        else
            log "✗ Errore: Token non trovato nella risposta" >&2
            rm -f /tmp/kavita_auth_mangadex.json
            return 1
        fi
    else
        log "✗ Errore autenticazione Kavita (HTTP ${http_code})" >&2
        rm -f /tmp/kavita_auth_mangadex.json
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
    
    local jwt_token
    if ! jwt_token=$(get_kavita_jwt_token); then
        log "✗ Impossibile ottenere JWT token, scan annullato"
        return 1
    fi
    
    local scan_endpoint="${KAVITA_URL}/api/Library"
    
    local response=$(curl -s -w "%{http_code}" -o /dev/null \
        -X POST "${scan_endpoint}/scan-all" \
        -H "Authorization: Bearer ${jwt_token}" \
        -H "Content-Type: application/json" \
        -d '{}')
    
    if [[ "${response}" == "200" ]] || [[ "${response}" == "204" ]]; then
        log "✓ Kavita library scan triggered successfully (all libraries)"
        return 0
    elif [[ -n "${KAVITA_LIBRARY_ID}" ]]; then
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
    
    if [[ -n "${DISCORD_WEBHOOK_URL}" ]]; then
        curl -s -X POST "${DISCORD_WEBHOOK_URL}" \
            -H "Content-Type: application/json" \
            -d "{\"content\":\"**${title}**\n${message}\"}" > /dev/null
    fi
    
    if [[ -n "${TELEGRAM_BOT_TOKEN}" ]] && [[ -n "${TELEGRAM_CHAT_ID}" ]]; then
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            -d "chat_id=${TELEGRAM_CHAT_ID}" \
            -d "text=*${title}*%0A${message}" \
            -d "parse_mode=Markdown" > /dev/null
    fi
}

# Funzione per estrarre manga ID dall'URL o usare ID diretto
extract_manga_id() {
    local input="$1"
    
    # Se è un URL MangaDex, estrai l'ID
    if [[ "${input}" =~ mangadex\.org/title/([a-f0-9\-]+) ]]; then
        echo "${BASH_REMATCH[1]}"
    # Se è già un UUID valido
    elif [[ "${input}" =~ ^[a-f0-9\-]{36}$ ]]; then
        echo "${input}"
    else
        # Ritorna input originale (potrebbe essere chapter, list, etc.)
        echo "${input}"
    fi
}

# Funzione per fixare capitoli volumeless
fix_volumeless_chapters() {
    local manga_dir="$1"
    
    if [[ ! -d "${manga_dir}" ]]; then
        log "WARN: Directory manga non trovata: ${manga_dir}"
        return 1
    fi
    
    local db_file="${manga_dir}/download.db"
    
    # Controlla se esiste database
    if [[ ! -f "${db_file}" ]]; then
        log "WARN: Database non trovato in: ${manga_dir}"
        return 0
    fi
    
    # Trova capitoli volumeless (formato: "Ch. X.cbz" senza "Vol.")
    local volumeless_files=()
    while IFS= read -r file; do
        volumeless_files+=("$file")
    done < <(find "${manga_dir}" -maxdepth 1 -type f -name "Ch. *.cbz" | sort -V)
    
    if [[ ${#volumeless_files[@]} -eq 0 ]]; then
        log "Nessun capitolo volumeless trovato"
        return 0
    fi
    
    log "Trovati ${#volumeless_files[@]} capitoli volumeless da processare"
    
    # Trova l'ultimo volume numerato
    local last_volume=0
    while IFS= read -r file; do
        if [[ "$file" =~ Vol\.\ ([0-9]+)\ Ch\. ]]; then
            local vol_num="${BASH_REMATCH[1]}"
            if [[ $vol_num -gt $last_volume ]]; then
                last_volume=$vol_num
            fi
        fi
    done < <(find "${manga_dir}" -maxdepth 1 -type f -name "Vol. *.cbz")
    
    # Calcola volume successivo
    local next_volume=$((last_volume + 1))
    
    if [[ $last_volume -eq 0 ]]; then
        log "Nessun volume trovato, assegno volumeless a Vol. 1"
        next_volume=1
    else
        log "Ultimo volume trovato: Vol. ${last_volume}, assegno volumeless a Vol. ${next_volume}"
    fi
    
    # Processa ogni capitolo volumeless
    local fixed_count=0
    for old_file in "${volumeless_files[@]}"; do
        local basename=$(basename "$old_file")
        
        # Estrai numero capitolo (supporta decimali: Ch. 56.cbz, Ch. 56.5.cbz)
        if [[ "$basename" =~ Ch\.\ ([0-9]+(\.[0-9]+)?)\.cbz ]]; then
            local ch_num="${BASH_REMATCH[1]}"
            local new_basename="Vol. ${next_volume} Ch. ${ch_num}.cbz"
            local new_file="${manga_dir}/${new_basename}"
            
            # Rinomina file fisico
            if mv "$old_file" "$new_file"; then
                log "✓ Rinominato: ${basename} → ${new_basename}"
                
                # Aggiorna database SQLite
                if sqlite3 "$db_file" "UPDATE file_info_cbz SET name='${new_basename}' WHERE name='${basename}';" 2>/dev/null; then
                    log "✓ Database aggiornato per: ${new_basename}"
                    ((fixed_count++))
                else
                    log "✗ Errore aggiornamento database per: ${basename}"
                    # Rollback: ripristina nome file originale
                    mv "$new_file" "$old_file" 2>/dev/null
                fi
            else
                log "✗ Errore rinominando: ${basename}"
            fi
        fi
    done
    
    if [[ $fixed_count -gt 0 ]]; then
        echo -e "${GREEN}✓ ${fixed_count} capitoli volumeless fixati e assegnati a Vol. ${next_volume}${NC}"
        log "Fix volumeless completato: ${fixed_count} capitoli processati"
        return 0
    else
        log "Nessun capitolo volumeless fixato"
        return 1
    fi
}

# Funzione per download manga
download_manga() {
    local url="$1"
    shift
    local extra_args=("$@")
    
    if [[ -z "${url}" ]]; then
        echo -e "${RED}Errore: URL o ID manga richiesto${NC}"
        exit 1
    fi
    
    # Controlla flag --only-download
    local only_download=false
    local filtered_args=()
    
    for arg in "${extra_args[@]}"; do
        if [[ "${arg}" == "--only-download" ]]; then
            only_download=true
        else
            filtered_args+=("${arg}")
        fi
    done
    
    # Controlla che mangadex-dl esista
    if [[ ! -x "${MANGADEX_BIN}" ]]; then
        echo -e "${RED}Errore: mangadex-dl non trovato in: ${MANGADEX_BIN}${NC}"
        echo -e "${YELLOW}Assicurati che l'eseguibile sia presente e eseguibile${NC}"
        exit 1
    fi
    
    load_config
    if [[ $? -ne 0 ]]; then
        echo -e "${YELLOW}Configurazione non trovata, uso defaults${NC}"
    fi
    
    # Fallback se DOWNLOADS_DIR non è definito
    if [[ -z "${DOWNLOADS_DIR}" ]]; then
        DOWNLOADS_DIR="${SCRIPT_DIR}/downloads"
    fi
    
    # Prepara argomenti mangadex-dl
    local download_args=()
    local has_format=false
    local has_cover=false
    local has_folder=false
    local manga_dir_placeholder=false
    
    # Controlla argomenti già specificati
    for arg in "${filtered_args[@]}"; do
        case "$arg" in
            "--save-as") has_format=true ;;
            "--cover") has_cover=true ;;
            "--folder") has_folder=true ;;
        esac
    done
    
    # Aggiungi defaults se non specificati
    if [[ "$has_format" == "false" ]]; then
        # Default: cbz (Kavita-friendly)
        download_args+=("--save-as" "${DEFAULT_FORMAT:-cbz}")
    fi
    
    if [[ "$has_cover" == "false" ]]; then
        # Default: original quality
        download_args+=("--cover" "original")
    fi
    
    # Usa placeholder per directory organizzata (solo se non già specificato)
    if [[ "$has_folder" == "false" ]]; then
        # Se è only-download, scarica nella cartella dello script per test
        # Altrimenti usa la cartella Kavita configurata
        if [[ "${only_download}" == "true" ]]; then
            download_args+=("--folder" "${SCRIPT_DIR}/{manga.title}")
        else
            download_args+=("--folder" "${DOWNLOADS_DIR}/{manga.title}")
        fi
    fi
    
    # Combina argomenti utente + defaults
    local all_args=("${filtered_args[@]}" "${download_args[@]}")
    
    if [[ "${only_download}" == "true" ]]; then
        log "Avvio download SOLO (no monitoraggio, no Kavita): ${url}"
        echo -e "${YELLOW}⚠️  Modalità ONLY-DOWNLOAD: nessun monitoraggio o Kavita scan${NC}"
    else
        log "Avvio download completo: ${url}"
        echo -e "${BLUE}Scaricando tutti i capitoli e aggiungendo al monitoraggio automatico...${NC}"
    fi
    
    log "Formato: ${DEFAULT_FORMAT:-cbz}, Cover: original"
    
    # Esegui il download con mangadex-dl
    cd "${SCRIPT_DIR}"
    
    if "${MANGADEX_BIN}" "${url}" "${all_args[@]}"; then
        log "✓ Download completato: ${url}"
        
        # mangadex-dl ha finito il cleanup, ora cerchiamo il database
        # Attendi un momento per essere sicuri che il filesystem sia sincronizzato
        sleep 2
        
        # Trova la cartella manga appena scaricata cercando download.db
        local manga_folder_pattern
        
        # Estrai la cartella di destinazione dagli argomenti
        local folder_arg=""
        for ((i=0; i<${#all_args[@]}; i++)); do
            if [[ "${all_args[i]}" == "--folder" ]]; then
                folder_arg="${all_args[i+1]}"
                # Rimuovi placeholder {manga.title} per ottenere la cartella base
                folder_arg="${folder_arg/\/\{manga.title\}/}"
                break
            fi
        done
        
        # Se non c'è folder_arg negli argomenti, usa default
        if [[ -z "${folder_arg}" ]]; then
            if [[ "${only_download}" == "true" ]]; then
                manga_folder_pattern="${SCRIPT_DIR}"
            else
                manga_folder_pattern="${DOWNLOADS_DIR}"
            fi
        else
            # Usa la cartella specificata (può essere relativa o assoluta)
            if [[ "${folder_arg}" =~ ^/ ]]; then
                # Path assoluto
                manga_folder_pattern="${folder_arg}"
            else
                # Path relativo, rendi assoluto
                manga_folder_pattern="${SCRIPT_DIR}/${folder_arg}"
            fi
        fi
        
        log "Cerco database manga in: ${manga_folder_pattern}"
        
        # Cerca tutte le cartelle con download.db (maxdepth 2 per gestire sottocartelle)
        local manga_folders=()
        while IFS= read -r db_path; do
            if [[ -f "${db_path}" ]]; then
                local folder=$(dirname "${db_path}")
                manga_folders+=("${folder}")
                log "Database trovato: ${db_path}"
            fi
        done < <(find "${manga_folder_pattern}" -maxdepth 2 -type f -name "download.db" 2>/dev/null)
        
        # Se abbiamo trovato almeno un database, processiamo il più recente
        if [[ ${#manga_folders[@]} -gt 0 ]]; then
            # Ordina per data di modifica e prendi il più recente
            local most_recent_folder=""
            local most_recent_time=0
            
            for folder in "${manga_folders[@]}"; do
                local db_file="${folder}/download.db"
                if [[ -f "${db_file}" ]]; then
                    local mod_time=$(stat -c %Y "${db_file}" 2>/dev/null || stat -f %m "${db_file}" 2>/dev/null)
                    if [[ ${mod_time} -gt ${most_recent_time} ]]; then
                        most_recent_time=${mod_time}
                        most_recent_folder="${folder}"
                    fi
                fi
            done
            
            if [[ -n "${most_recent_folder}" ]]; then
                log "Database più recente trovato in: ${most_recent_folder}"
                log "Controllo capitoli volumeless..."
                fix_volumeless_chapters "${most_recent_folder}"
            fi
        else
            log "WARN: Nessun database trovato in ${manga_folder_pattern}"
        fi
        
        # Solo se NON è only-download
        if [[ "${only_download}" == "false" ]]; then
            # Aggiungi automaticamente al monitoraggio
            add_to_monitoring_internal "${url}" "${filtered_args[@]}"
            
            # Trigger Kavita scan
            trigger_kavita_scan
            
            # Notifica
            send_notification "MangaDex Download" "Download completato e aggiunto al monitoraggio: ${url}"
            
            echo -e "${GREEN}✓ Manga scaricato e aggiunto al monitoraggio automatico!${NC}"
        else
            echo -e "${GREEN}✓ Manga scaricato (solo download, nessun monitoraggio)${NC}"
        fi
        
        return 0
    else
        log "✗ Errore durante download: ${url}"
        send_notification "MangaDex Error" "Errore download: ${url}"
        return 1
    fi
}

# Funzione interna per aggiungere URL al monitoraggio
add_to_monitoring_internal() {
    local url="$1"
    shift
    local extra_args=("$@")
    
    touch "${CRON_CHECK_FILE}"
    
    # Controlla se URL già presente
    if grep -Fxq "${url}" "${CRON_CHECK_FILE}"; then
        log "URL già in monitoraggio: ${url}"
        return 0
    fi
    
    # Aggiungi URL con opzioni
    echo "${url} ${extra_args[*]}" >> "${CRON_CHECK_FILE}"
    log "URL aggiunto automaticamente al monitoraggio: ${url}"
    
    if ! crontab -l 2>/dev/null | grep -q "mangadex-manager"; then
        echo -e "${YELLOW}💡 Esegui '$0 setup-cron' per attivare il monitoraggio automatico ogni 6 ore${NC}"
    fi
}

# Funzione per listare URLs monitorati
list_monitored() {
    if [[ ! -f "${CRON_CHECK_FILE}" ]] || [[ ! -s "${CRON_CHECK_FILE}" ]]; then
        echo -e "${YELLOW}Nessun manga in monitoraggio${NC}"
        return 0
    fi
    
    echo -e "${BLUE}Manga in monitoraggio automatico:${NC}"
    echo ""
    local count=1
    while IFS= read -r line; do
        echo "${count}. ${line}"
        ((count++))
    done < "${CRON_CHECK_FILE}"
}

# Funzione per rimuovere URL dal monitoraggio
remove_from_monitoring() {
    local url="$1"
    
    if [[ -z "${url}" ]]; then
        echo -e "${RED}Errore: URL richiesto${NC}"
        exit 1
    fi
    
    if [[ ! -f "${CRON_CHECK_FILE}" ]]; then
        echo -e "${YELLOW}Nessun manga in monitoraggio${NC}"
        return 0
    fi
    
    local temp_file="${CRON_CHECK_FILE}.tmp"
    grep -v -F "${url}" "${CRON_CHECK_FILE}" > "${temp_file}" || true
    mv "${temp_file}" "${CRON_CHECK_FILE}"
    
    log "URL rimosso dal monitoraggio: ${url}"
    echo -e "${GREEN}✓ URL rimosso dal monitoraggio${NC}"
}

# Funzione per controllare aggiornamenti (usata dal cron)
check_updates() {
    load_config
    
    if [[ -z "${DOWNLOADS_DIR}" ]]; then
        DOWNLOADS_DIR="${SCRIPT_DIR}/downloads"
    fi
    
    if [[ ! -f "${CRON_CHECK_FILE}" ]] || [[ ! -s "${CRON_CHECK_FILE}" ]]; then
        log "Nessun manga in monitoraggio"
        return 0
    fi
    
    # Controlla che mangadex-dl esista
    if [[ ! -x "${MANGADEX_BIN}" ]]; then
        log "✗ Errore: mangadex-dl non trovato in: ${MANGADEX_BIN}"
        return 1
    fi
    
    log "Inizio controllo automatico nuovi capitoli"
    local new_chapters_found=false
    local manga_count=0
    
    while IFS= read -r line; do
        if [[ -n "${line}" ]]; then
            local url=$(echo "${line}" | awk '{print $1}')
            local args=""
            if echo "${line}" | grep -q ' '; then
                args=$(echo "${line}" | cut -d' ' -f2-)
            fi
            ((manga_count++))
            
            log "Controllo nuovi capitoli per manga #${manga_count}: ${url}"
            
            cd "${SCRIPT_DIR}"
            
            # Prepara argomenti per update
            local update_args=()
            
            # Formato CBZ per Kavita
            update_args+=("--save-as" "${DEFAULT_FORMAT:-cbz}")
            update_args+=("--cover" "original")
            update_args+=("--folder" "${DOWNLOADS_DIR}/{manga.title}")
            
            # mangadex-dl scarica automaticamente solo capitoli nuovi se il manga esiste già
            if "${MANGADEX_BIN}" "${url}" "${update_args[@]}" ${args}; then
                log "✓ Controllo capitoli completato per manga #${manga_count}"
                new_chapters_found=true
            else
                log "✗ Errore durante controllo manga #${manga_count}: ${url}"
            fi
        fi
    done < "${CRON_CHECK_FILE}"
    
    if [[ "${new_chapters_found}" == "true" ]]; then
        log "Nuovi capitoli trovati! Triggering Kavita scan..."
        trigger_kavita_scan
        send_notification "MangaDex Updates" "Nuovi capitoli scaricati automaticamente da ${manga_count} manga monitorati"
    else
        log "Nessun nuovo capitolo trovato nei ${manga_count} manga monitorati"
    fi
    
    log "Controllo automatico completato"
}

# Funzione per configurare cron job di sistema
setup_cron() {
    local cron_line="0 */6 * * * cd \"${SCRIPT_DIR}\" && ./mangadex-manager-simple.sh check-updates >> \"${LOG_FILE}\" 2>&1"
    
    if ! crontab -l 2>/dev/null | grep -q "mangadex-manager"; then
        (crontab -l 2>/dev/null; echo "${cron_line}") | crontab -
        log "Cron job di sistema configurato: controllo automatico ogni 6 ore"
        echo -e "${GREEN}✓ Cron job di sistema configurato!${NC}"
        echo -e "${BLUE}  → Controllo automatico ogni 6 ore alle: 00:00, 06:00, 12:00, 18:00${NC}"
        echo -e "${BLUE}  → Scarica automaticamente solo nuovi capitoli${NC}"
        echo -e "${YELLOW}💡 Controlla con 'crontab -l' per verificare${NC}"
    else
        echo -e "${YELLOW}Cron job già configurato${NC}"
        echo -e "${BLUE}Controlla con: crontab -l${NC}"
    fi
}

# Funzione per rimuovere cron job di sistema
remove_cron() {
    if crontab -l 2>/dev/null | grep -q "mangadex-manager"; then
        crontab -l 2>/dev/null | grep -v "mangadex-manager" | crontab -
        log "Cron job di sistema rimosso"
        echo -e "${GREEN}✓ Cron job di sistema rimosso${NC}"
        echo -e "${BLUE}I manga rimangono in monitoraggio, ma non verranno più controllati automaticamente${NC}"
    else
        echo -e "${YELLOW}Nessun cron job trovato nel sistema${NC}"
    fi
}

main() {
    local command="$1"
    
    if [[ -z "${command}" ]]; then
        show_help
        exit 1
    fi
    
    # Carica configurazione
    load_config || echo -e "${YELLOW}Usa 'webtoon-manager-simple.sh config' per configurare${NC}"
    
    case "${command}" in
        "download")
            shift
            local url="$1"
            shift
            download_manga "${url}" "$@"
            ;;
        "list-monitored")
            list_monitored
            ;;
        "remove-monitor")
            shift
            remove_from_monitoring "$1"
            ;;
        "fix-volumeless")
            shift
            local manga_folder="$1"
            if [[ -z "${manga_folder}" ]]; then
                echo -e "${RED}Errore: Specifica la cartella del manga${NC}"
                echo "Esempio: $0 fix-volumeless './Mahou Shoujo ni Akogarete'"
                exit 1
            fi
            fix_volumeless_chapters "${manga_folder}"
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
        "kavita-scan")
            load_config
            trigger_kavita_scan
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
