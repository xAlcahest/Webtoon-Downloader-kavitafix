#!/bin/bash

# Webtoon Manager - Intermediario per download e monitoraggio automatico
# Versione: 1.1
# Author: xAlcahest

# Configurazioni di default
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/webtoon-config.conf"
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

# Funzione per verificare integrità CBZ
verify_cbz_integrity() {
    local cbz_dir="$1"
    
    if [[ ! -d "${cbz_dir}" ]]; then
        log "WARN: Directory non trovata per verifica CBZ: ${cbz_dir}"
        return 0
    fi
    
    log "🔍 Verifica integrità CBZ in: ${cbz_dir}"
    
    # Conta prima i file totali per la progress bar
    local total_files=$(find "${cbz_dir}" -maxdepth 1 -type f -name "*.cbz" 2>/dev/null | wc -l)
    
    if [[ ${total_files} -eq 0 ]]; then
        log "Nessun file CBZ trovato per verifica"
        return 0
    fi
    
    echo -e "${BLUE}Trovati ${total_files} file CBZ da verificare...${NC}"
    
    # Crea file temporaneo per i risultati
    local temp_result=$(mktemp)
    
    # Usa Python per verifica con progress bar (output diretto a terminale)
    CBZ_DIR="${cbz_dir}" python3 << 'PYTHON_SCRIPT' > "${temp_result}"
import zipfile
import sys
import os
from pathlib import Path

cbz_dir = os.environ['CBZ_DIR']
cbz_files = sorted(Path(cbz_dir).glob("*.cbz"))
total = len(cbz_files)

corrupted = []
ok_count = 0

for idx, cbz_file in enumerate(cbz_files, 1):
    # Progress bar su stderr (così va al terminale, non in result)
    percent = int((idx / total) * 100)
    bar_length = 40
    filled = int((percent / 100) * bar_length)
    bar = '█' * filled + '░' * (bar_length - filled)
    
    # Stampa progress su stderr (usa \r per sovrascrivere la stessa riga)
    print(f'\r[{bar}] {percent}% ({idx}/{total}) - Verificando: {cbz_file.name[:50]:<50}', end='', flush=True, file=sys.stderr)
    
    # Verifica integrità
    try:
        with zipfile.ZipFile(str(cbz_file), 'r') as zf:
            result = zf.testzip()
            if result is not None:
                corrupted.append(str(cbz_file))
            else:
                ok_count += 1
    except Exception:
        corrupted.append(str(cbz_file))

# Nuova riga dopo progress bar su stderr
print(file=sys.stderr)

# Output risultati su stdout (per bash)
print(f"OK_COUNT={ok_count}")
print(f"TOTAL_COUNT={total}")
for c in corrupted:
    print(f"CORRUPTED:{c}")

sys.exit(0)
PYTHON_SCRIPT
    
    # Leggi risultati dal file temporaneo
    local result=$(cat "${temp_result}")
    rm -f "${temp_result}"
    
    # Parse risultati Python
    local corrupted_files=()
    local ok_count=0
    local cbz_count=0
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^OK_COUNT=([0-9]+)$ ]]; then
            ok_count="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^TOTAL_COUNT=([0-9]+)$ ]]; then
            cbz_count="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^CORRUPTED:(.+)$ ]]; then
            corrupted_files+=("${BASH_REMATCH[1]}")
        fi
    done <<< "$result"
    
    if [[ ${cbz_count} -eq 0 ]]; then
        log "Nessun file CBZ trovato per verifica"
        return 0
    fi
    
    log "Verifica completata: ${ok_count}/${cbz_count} CBZ validi"
    
    if [[ ${#corrupted_files[@]} -gt 0 ]]; then
        echo -e "${RED}⚠️  ATTENZIONE: ${#corrupted_files[@]} file CBZ corrotti trovati!${NC}"
        log "File CBZ corrotti trovati: ${#corrupted_files[@]}"
        
        for corrupted in "${corrupted_files[@]}"; do
            local basename=$(basename "$corrupted")
            log "  - ${basename}"
            echo -e "${RED}  ✗ ${basename}${NC}"
        done
        
        echo -e "${YELLOW}💡 File corrotti NON spostati automaticamente${NC}"
        echo -e "${YELLOW}   Per ripararli, riscaricarli manualmente con --start e --end${NC}"
        
        return 1
    else
        echo -e "${GREEN}✓ Tutti i ${cbz_count} file CBZ sono integri e leggibili${NC}"
        return 0
    fi
}

# Funzione per scan globale di tutte le cartelle manga
scan_all_manga() {
    local base_dir="$1"
    
    if [[ -z "${base_dir}" ]]; then
        load_config
        if [[ -z "${DOWNLOADS_DIR}" ]]; then
            echo -e "${RED}Errore: Cartella base non specificata e DOWNLOADS_DIR non configurato${NC}"
            echo "Uso: $0 scan-all <cartella_base>"
            return 1
        fi
        base_dir="${DOWNLOADS_DIR}"
    fi
    
    if [[ ! -d "${base_dir}" ]]; then
        echo -e "${RED}Errore: Directory non trovata: ${base_dir}${NC}"
        return 1
    fi
    
    log "📚 Inizio scan globale di: ${base_dir}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}          SCAN GLOBALE INTEGRITÀ MANGA/WEBTOON${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Crea file temporaneo per i risultati
    local temp_result=$(mktemp)
    
    # Usa Python per scan completo con progress bar
    CBZ_BASE_DIR="${base_dir}" python3 << 'PYTHON_SCRIPT' > "${temp_result}"
import zipfile
import sys
import os
from pathlib import Path

# Funzione per riconoscere tipo immagine da magic bytes (sostituisce imghdr deprecato)
def detect_image_type(file_path):
    """Rileva il tipo di immagine dai magic bytes (primi byte del file)"""
    try:
        with open(file_path, 'rb') as f:
            header = f.read(32)  # Leggi primi 32 bytes
        
        # Magic bytes per formati comuni
        if header.startswith(b'\xff\xd8\xff'):
            return 'jpeg'
        elif header.startswith(b'\x89PNG\r\n\x1a\n'):
            return 'png'
        elif header.startswith(b'GIF87a') or header.startswith(b'GIF89a'):
            return 'gif'
        elif header.startswith(b'RIFF') and header[8:12] == b'WEBP':
            return 'webp'
        elif header.startswith(b'BM'):
            return 'bmp'
        elif header.startswith(b'\x00\x00\x01\x00') or header.startswith(b'\x00\x00\x02\x00'):
            return 'ico'
        else:
            return None
    except Exception:
        return None

base_dir = Path(os.environ['CBZ_BASE_DIR'])

# Trova tutte le sottocartelle (ogni manga/webtoon)
manga_folders = sorted([d for d in base_dir.iterdir() if d.is_dir()])
total_folders = len(manga_folders)

# Stampa numero totale cartelle
print(f"\nTOTAL_FOLDERS={total_folders}", file=sys.stderr, flush=True)

global_stats = {
    'total_cbz': 0,
    'ok_cbz': 0,
    'corrupted_cbz': 0,
    'total_images': 0,
    'ok_images': 0,
    'corrupted_images': 0,
    'folders_with_issues': []
}

for folder_idx, manga_folder in enumerate(manga_folders, 1):
    manga_name = manga_folder.name
    
    # Trova CBZ e immagini PRIMA per sapere il totale
    cbz_files = list(manga_folder.glob("*.cbz"))
    image_files = []
    for ext in ['*.jpg', '*.jpeg', '*.png', '*.gif', '*.webp']:
        image_files.extend(manga_folder.glob(ext))
    
    total_files_in_folder = len(cbz_files) + len(image_files)
    
    # Progress LIVELLO 1: Cartelle totali
    folder_percent = int((folder_idx / total_folders) * 100)
    folder_bar_length = 50
    folder_filled = int((folder_percent / 100) * folder_bar_length)
    folder_bar = '█' * folder_filled + '░' * (folder_bar_length - folder_filled)
    
    print(f'\r[{folder_bar}] {folder_percent}% - Scansionando: {manga_name[:40]:<40}', end='', flush=True, file=sys.stderr)
    print(file=sys.stderr)  # Nuova riga per la seconda barra
    
    # Stampa info cartella
    print(f"{manga_name}_FILES={total_files_in_folder}", file=sys.stderr, flush=True)
    
    folder_corrupted = []
    folder_ok_cbz = 0
    folder_ok_images = 0
    
    current_file_idx = 0
    
    # Verifica CBZ
    for cbz_file in cbz_files:
        current_file_idx += 1
        global_stats['total_cbz'] += 1
        
        # Progress LIVELLO 2: File nella cartella corrente
        file_percent = int((current_file_idx / total_files_in_folder) * 100)
        file_bar_length = 50
        file_filled = int((file_percent / 100) * file_bar_length)
        file_bar = '█' * file_filled + '░' * (file_bar_length - file_filled)
        
        # Nome file troncato
        file_display = cbz_file.name[:50]
        print(f'\r  [{file_bar}] {file_percent}% - {file_display:<50}', end='', flush=True, file=sys.stderr)
        
        try:
            with zipfile.ZipFile(str(cbz_file), 'r') as zf:
                result = zf.testzip()
                if result is not None:
                    global_stats['corrupted_cbz'] += 1
                    folder_corrupted.append(('CBZ', str(cbz_file)))
                else:
                    global_stats['ok_cbz'] += 1
                    folder_ok_cbz += 1
        except Exception:
            global_stats['corrupted_cbz'] += 1
            folder_corrupted.append(('CBZ', str(cbz_file)))
    
    # Verifica immagini (solo che siano file validi non vuoti)
    for img_file in image_files:
        current_file_idx += 1
        global_stats['total_images'] += 1
        
        # Progress LIVELLO 2: File nella cartella corrente
        file_percent = int((current_file_idx / total_files_in_folder) * 100)
        file_bar_length = 50
        file_filled = int((file_percent / 100) * file_bar_length)
        file_bar = '█' * file_filled + '░' * (file_bar_length - file_filled)
        
        # Nome file troncato
        file_display = img_file.name[:50]
        print(f'\r  [{file_bar}] {file_percent}% - {file_display:<50}', end='', flush=True, file=sys.stderr)
        
        try:
            # Controlla che il file esista, non sia vuoto e abbia un formato immagine valido
            if img_file.stat().st_size > 0:
                # Usa detect_image_type invece di imghdr.what
                img_type = detect_image_type(str(img_file))
                if img_type is not None:
                    global_stats['ok_images'] += 1
                    folder_ok_images += 1
                else:
                    # File non riconosciuto come immagine valida
                    global_stats['corrupted_images'] += 1
                    folder_corrupted.append(('IMAGE', str(img_file)))
            else:
                # File vuoto
                global_stats['corrupted_images'] += 1
                folder_corrupted.append(('IMAGE', str(img_file)))
        except Exception:
            global_stats['corrupted_images'] += 1
            folder_corrupted.append(('IMAGE', str(img_file)))
    
    # Cancella la seconda barra e vai a nuova riga
    print(f'\r{" " * 120}', end='', file=sys.stderr)  # Pulisci riga
    print('\r', end='', file=sys.stderr)  # Torna a inizio
    
    # Se ci sono problemi, segna la cartella
    if folder_corrupted:
        global_stats['folders_with_issues'].append(manga_name)
        # Output per bash
        print(f"FOLDER_ISSUE:{manga_name}")
        for ftype, fpath in folder_corrupted:
            print(f"CORRUPTED:{ftype}:{fpath}")

# Nuova riga dopo progress
print(file=sys.stderr)

# Output statistiche globali
print(f"TOTAL_CBZ={global_stats['total_cbz']}")
print(f"OK_CBZ={global_stats['ok_cbz']}")
print(f"CORRUPTED_CBZ={global_stats['corrupted_cbz']}")
print(f"TOTAL_IMAGES={global_stats['total_images']}")
print(f"OK_IMAGES={global_stats['ok_images']}")
print(f"CORRUPTED_IMAGES={global_stats['corrupted_images']}")

sys.exit(0)
PYTHON_SCRIPT
    
    # Leggi risultati dal file temporaneo
    local result=$(cat "${temp_result}")
    rm -f "${temp_result}"
    
    # Parse risultati
    local total_cbz=0
    local ok_cbz=0
    local corrupted_cbz=0
    local total_images=0
    local ok_images=0
    local corrupted_images=0
    local current_folder=""
    declare -A folder_issues
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^TOTAL_CBZ=([0-9]+)$ ]]; then
            total_cbz="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^OK_CBZ=([0-9]+)$ ]]; then
            ok_cbz="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^CORRUPTED_CBZ=([0-9]+)$ ]]; then
            corrupted_cbz="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^TOTAL_IMAGES=([0-9]+)$ ]]; then
            total_images="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^OK_IMAGES=([0-9]+)$ ]]; then
            ok_images="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^CORRUPTED_IMAGES=([0-9]+)$ ]]; then
            corrupted_images="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^FOLDER_ISSUE:(.+)$ ]]; then
            current_folder="${BASH_REMATCH[1]}"
            folder_issues["${current_folder}"]=""
        elif [[ "$line" =~ ^CORRUPTED:(CBZ|IMAGE):(.+)$ ]]; then
            local ftype="${BASH_REMATCH[1]}"
            local fpath="${BASH_REMATCH[2]}"
            if [[ -n "${current_folder}" ]]; then
                folder_issues["${current_folder}"]+="  ${ftype}: $(basename "${fpath}")"$'\n'
            fi
        fi
    done <<< "$result"
    
    # Mostra risultati
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}                    RISULTATI SCAN GLOBALE${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Statistiche CBZ
    if [[ ${total_cbz} -gt 0 ]]; then
        echo -e "${BLUE}📦 File CBZ:${NC}"
        echo -e "   Totali:    ${total_cbz}"
        echo -e "   ${GREEN}✓ Validi:   ${ok_cbz}${NC}"
        if [[ ${corrupted_cbz} -gt 0 ]]; then
            echo -e "   ${RED}✗ Corrotti: ${corrupted_cbz}${NC}"
        else
            echo -e "   ${GREEN}✓ Corrotti: 0${NC}"
        fi
        echo ""
    fi
    
    # Statistiche immagini
    if [[ ${total_images} -gt 0 ]]; then
        echo -e "${BLUE}🖼️  File Immagine:${NC}"
        echo -e "   Totali:    ${total_images}"
        echo -e "   ${GREEN}✓ Validi:   ${ok_images}${NC}"
        if [[ ${corrupted_images} -gt 0 ]]; then
            echo -e "   ${RED}✗ Corrotti: ${corrupted_images}${NC}"
        else
            echo -e "   ${GREEN}✓ Corrotti: 0${NC}"
        fi
        echo ""
    fi
    
    # Cartelle con problemi
    local issues_count=${#folder_issues[@]}
    if [[ ${issues_count} -gt 0 ]]; then
        echo -e "${RED}⚠️  CARTELLE CON PROBLEMI: ${issues_count}${NC}"
        echo ""
        for folder in "${!folder_issues[@]}"; do
            echo -e "${YELLOW}📁 ${folder}${NC}"
            echo -e "${folder_issues[${folder}]}"
        done
        log "Scan globale completato: ${issues_count} cartelle con problemi"
        return 1
    else
        echo -e "${GREEN}✓ NESSUN PROBLEMA TROVATO!${NC}"
        echo -e "${GREEN}  Tutti i file sono integri e leggibili${NC}"
        log "Scan globale completato: nessun problema trovato"
        return 0
    fi
}

# Funzione per stampare help
show_help() {
    echo -e "${BLUE}Webtoon Manager - Download e monitoraggio automatico${NC}"
    echo ""
    echo "Utilizzo:"
    echo "  $0 download <URL> [opzioni]     - Scarica webtoon (aggiunge automaticamente al monitoraggio)"
    echo "  $0 list-monitored               - Lista URLs monitorati automaticamente"
    echo "  $0 remove-monitor <URL>         - Rimuove URL dal monitoraggio automatico"
    echo "  $0 verify-cbz <cartella>        - Verifica integrità file CBZ in una cartella"
    echo "  $0 scan-all [cartella]          - Scan globale di tutte le cartelle manga/webtoon (CBZ + immagini)"
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
    echo "  --concurrent-pages <num>        - Immagini/pagine per capitolo contemporaneamente (default: 10)"
    echo ""
    echo "Logica:"
    echo "  - Il download manuale scarica TUTTI gli episodi e aggiunge la serie al monitoraggio"
    echo "  - Il monitoraggio automatico (cron) scarica solo gli episodi NUOVI (--latest)"
    echo "  - Dopo ogni download viene verificata l'integrità dei CBZ"
    echo ""
    echo "Esempi:"
    echo "  $0 download 'https://www.webtoons.com/en/fantasy/tower-of-god/list?title_no=95' --format cbz"
    echo "  $0 download 'URL' --concurrent-chapters 5 --concurrent-images 20 --quality 90"
    echo "  $0 verify-cbz './downloads/Down To Earth'  # Verifica CBZ in una cartella"
    echo "  $0 scan-all '/root/docker-conf/kavita/manga'  # Scan globale di tutte le cartelle"
    echo "  $0 scan-all  # Usa DOWNLOADS_DIR configurato"
    echo "  $0 setup-cron  # Configura controllo automatico ogni 6 ore"
    echo "  $0 list-monitored  # Vedi quali serie sono monitorate"
    echo ""
    echo "Scan Globale:"
    echo "  • Verifica tutte le sottocartelle manga/webtoon"
    echo "  • Controlla integrità file CBZ (archivi ZIP)"
    echo "  • Controlla validità file immagine (jpg, png, gif, webp)"
    echo "  • Progress bar in tempo reale"
    echo "  • Report dettagliato con statistiche"
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
    echo "Directory Downloads:"
    read -p "Percorso directory downloads [./downloads]: " downloads_dir
    downloads_dir=${downloads_dir:-"./downloads"}
    
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
    sed -i "s|DOWNLOADS_DIR=.*|DOWNLOADS_DIR=\"${downloads_dir}\"|" "${CONFIG_FILE}"
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
        log "WARN: Kavita non configurato (URL o API_KEY mancanti)" >&2
        return 1
    fi
    
    local auth_endpoint="${KAVITA_URL}/api/Plugin/authenticate"
    local plugin_name="webtoon-manager"
    
    log "Ottenendo JWT token da Kavita..." >&2
    
    local response=$(curl -s -w "%{http_code}" -o /tmp/kavita_auth.json \
        -X POST "${auth_endpoint}?apiKey=${KAVITA_API_KEY}&pluginName=${plugin_name}" \
        -H "Content-Type: application/json" \
        -d '{}')
    
    local http_code="${response}"
    
    if [[ "${http_code}" == "200" ]]; then
        # Estrai il token dalla risposta JSON
        local jwt_token=$(grep -o '"token":"[^"]*"' /tmp/kavita_auth.json | cut -d'"' -f4)
        
        if [[ -n "${jwt_token}" ]]; then
            log "✓ JWT token ottenuto con successo" >&2
            echo "${jwt_token}"
            rm -f /tmp/kavita_auth.json
            return 0
        else
            log "✗ Errore: Token non trovato nella risposta" >&2
            rm -f /tmp/kavita_auth.json
            return 1
        fi
    else
        log "✗ Errore autenticazione Kavita (HTTP ${http_code})" >&2
        log "Controlla KAVITA_URL e KAVITA_API_KEY nella configurazione" >&2
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
        -H "Content-Type: application/json" \
        -d '{}')
    
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
    
    load_config
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}Configurazione non trovata. Esegui prima: $0 config${NC}"
        return 1
    fi
    
    # Fallback se DOWNLOADS_DIR non è definito
    if [[ -z "${DOWNLOADS_DIR}" ]]; then
        DOWNLOADS_DIR="${SCRIPT_DIR}/downloads"
    fi
    
    # Estrai nome serie dall'URL per creare sottocartella
    local series_name=$(echo "${url}" | sed 's/.*\/\([^/]*\)\/list.*/\1/' | sed 's/-/ /g' | sed 's/\b\w/\U&/g')
    if [[ -z "${series_name}" || "${series_name}" == "${url}" ]]; then
        # Fallback: usa parte dell'URL
        series_name=$(echo "${url}" | sed 's/.*\/\([^/?]*\).*/\1/' | sed 's/-/_/g')
        [[ -z "${series_name}" ]] && series_name="Unknown_Series"
    fi
    
    # Directory specifica per la serie
    local series_dir="${DOWNLOADS_DIR}/${series_name}"
    
    # Crea directory downloads e sottocartella serie
    mkdir -p "${series_dir}"
    
    log "Downloading '${series_name}' to: ${series_dir}"
    
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
            "--concurrent-pages") has_concurrent_images=true ;;
            "--save-as"|"--format") has_format=true ;;
            "--quality") has_quality=true ;;
        esac
    done
    
    # Aggiungi defaults se non specificati
    if [[ "$has_concurrent_chapters" == "false" ]] && [[ -n "${CONCURRENT_CHAPTERS}" ]]; then
        download_args+=("--concurrent-chapters" "${CONCURRENT_CHAPTERS}")
    fi
    
    if [[ "$has_concurrent_images" == "false" ]] && [[ -n "${CONCURRENT_IMAGES}" ]]; then
        download_args+=("--concurrent-pages" "${CONCURRENT_IMAGES}")
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
    if /root/.local/bin/poetry run webtoon-downloader "${url}" --out "${series_dir}" "${all_args[@]}"; then
        log "✓ Download completato: ${url}"
        
        # Verifica integrità dei CBZ scaricati
        verify_cbz_integrity "${series_dir}"
        
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

# Funzione interna per aggiungere URL al monitoraggio
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
    if ! crontab -l 2>/dev/null | grep -q "webtoon-manager"; then
        echo -e "${YELLOW}💡 Esegui '$0 setup-cron' per attivare il monitoraggio automatico ogni 6 ore${NC}"
    fi
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

# Funzione per controllare aggiornamenti (usata dal cron)
check_updates() {
    # Carica configurazione per avere DOWNLOADS_DIR
    load_config
    
    # Fallback se DOWNLOADS_DIR non è definito
    if [[ -z "${DOWNLOADS_DIR}" ]]; then
        DOWNLOADS_DIR="${SCRIPT_DIR}/downloads"
    fi
    
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
            local args=""
            # Prendi solo gli argomenti DOPO l'URL (se esistono)
            if echo "${line}" | grep -q ' '; then
                args=$(echo "${line}" | cut -d' ' -f2-)
            fi
            ((series_count++))
            
            log "Controllo nuovi episodi per serie #${series_count}: ${url}"
            
            cd "${SCRIPT_DIR}"
            # SEMPRE usa --latest per il monitoraggio automatico
            # Estrai nome serie per directory specifica
            local series_name=$(echo "${url}" | sed 's/.*\/\([^/]*\)\/list.*/\1/' | sed 's/-/ /g' | sed 's/\b\w/\U&/g')
            if [[ -z "${series_name}" || "${series_name}" == "${url}" ]]; then
                series_name="Unknown_Series"
            fi
            local series_dir="${DOWNLOADS_DIR}/${series_name}"
            mkdir -p "${series_dir}"
            
            local update_args=("--latest" "--out" "${series_dir}")
            
            # Aggiungi formato CBZ (CRITICO per Kavita!)
            if [[ -n "${DEFAULT_FORMAT}" ]]; then
                update_args+=("--save-as" "${DEFAULT_FORMAT}")
            else
                update_args+=("--save-as" "cbz")
            fi
            
            # Aggiungi parametri di concorrenza se configurati
            if [[ -n "${CONCURRENT_CHAPTERS}" ]]; then
                update_args+=("--concurrent-chapters" "${CONCURRENT_CHAPTERS}")
            fi
            if [[ -n "${CONCURRENT_IMAGES}" ]]; then
                update_args+=("--concurrent-pages" "${CONCURRENT_IMAGES}")
            fi
            
            # Aggiungi qualità se configurata
            if [[ -n "${DEFAULT_QUALITY}" ]]; then
                update_args+=("--quality" "${DEFAULT_QUALITY}")
            fi
            
            # IMPORTANTE: L'URL deve essere quotato per gestire i query params (es: ?title_no=XXX)
            # Deve essere l'ULTIMO argomento, dopo tutti i flag
            if /root/.local/bin/poetry run webtoon-downloader "${update_args[@]}" ${args} "${url}"; then
                log "✓ Controllo episodi completato per serie #${series_count}"
                
                # Verifica integrità CBZ scaricati nel monitoraggio automatico
                verify_cbz_integrity "${series_dir}"
                
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

# Funzione per configurare cron job di sistema
setup_cron() {
    local cron_line="0 */6 * * * cd \"${SCRIPT_DIR}\" && ./webtoon-manager-simple.sh check-updates >> \"${LOG_FILE}\" 2>&1"
    
    # Controlla se il cron job esiste già
    if ! crontab -l 2>/dev/null | grep -q "webtoon-manager"; then
        # Aggiungi al crontab di sistema
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

# Funzione per rimuovere cron job di sistema
remove_cron() {
    if crontab -l 2>/dev/null | grep -q "webtoon-manager"; then
        crontab -l 2>/dev/null | grep -v "webtoon-manager" | crontab -
        log "Cron job di sistema rimosso"
        echo -e "${GREEN}✓ Cron job di sistema rimosso${NC}"
        echo -e "${BLUE}Le serie rimangono in monitoraggio, ma non verranno più controllate automaticamente${NC}"
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
        "verify-cbz")
            shift
            local folder_path="$1"
            if [[ -z "${folder_path}" ]]; then
                echo -e "${RED}Errore: Specifica la cartella da verificare${NC}"
                echo "Esempio: $0 verify-cbz './downloads/Down To Earth'"
                exit 1
            fi
            verify_cbz_integrity "${folder_path}"
            ;;
        "scan-all")
            shift
            local base_path="$1"
            scan_all_manga "${base_path}"
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