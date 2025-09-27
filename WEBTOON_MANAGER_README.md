# Webtoon Manager

Script di gestione avanzato per il Webtoon Downloader con integrazione Kavita.

## Caratteristiche

- **Download automatico** con monitoraggio ogni 6 ore
- **Integrazione Kavita** con trigger automatico per la scansione della libreria
- **Notifiche opzionali** (Discord/Telegram)
- **Gestione configurazione** interattiva
- **Logging completo** delle operazioni

## Setup Iniziale

1. **Configurazione iniziale:**
   ```bash
   ./webtoon-manager.sh config
   ```
   Questo ti guiderà nella configurazione di:
   - URL e API key di Kavita
   - Library ID di Kavita
   - Formati di download predefiniti
   - Impostazioni di qualità

2. **Setup del monitoraggio automatico:**
   ```bash
   ./webtoon-manager.sh setup-cron
   ```

## Utilizzo

### Download Manuale
```bash
# Download completo di una serie
./webtoon-manager.sh download "https://www.webtoons.com/en/fantasy/tower-of-god/list?title_no=95"

# Download con opzioni
./webtoon-manager.sh download "URL" --format cbz --quality 90 --start 1 --end 10
```

### Monitoraggio Automatico
```bash
# Aggiungi una serie al monitoraggio
./webtoon-manager.sh monitor "https://www.webtoons.com/en/fantasy/tower-of-god/list?title_no=95" --format cbz

# Lista serie monitorate
./webtoon-manager.sh list-monitored

# Rimuovi dal monitoraggio
./webtoon-manager.sh remove-monitor "URL"
```

### Gestione Cron Job
```bash
# Configura controllo automatico ogni 6 ore
./webtoon-manager.sh setup-cron

# Rimuovi il controllo automatico
./webtoon-manager.sh remove-cron

# Controllo manuale degli aggiornamenti
./webtoon-manager.sh check-updates
```

## File di Configurazione

Il file `webtoon-config.conf` contiene:

```bash
# Kavita Settings
KAVITA_URL="http://localhost:5000"
KAVITA_API_KEY="your-api-key"
KAVITA_LIBRARY_ID=1

# Download Settings
DEFAULT_FORMAT="cbz"
DEFAULT_QUALITY=100
CONCURRENT_DOWNLOADS=3

# Notification Settings (opzionale)
DISCORD_WEBHOOK_URL=""
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""
```

## Formati Supportati

- **CBZ**: Raccomandato per Kavita (formato comic book zip)
- **PDF**: Formato PDF standard
- **Images**: Immagini singole in cartelle

## Integrazione Kavita

Lo script automaticamente:
1. Scarica i nuovi episodi nel formato Kavita-compatibile
2. Triggera una scansione della libreria Kavita
3. Organizza i file secondo il pattern: `Series Vol.X Ch.Y - Episode Title`

## Notifiche (Opzionale)

Supporta notifiche via:
- **Discord**: Configura `DISCORD_WEBHOOK_URL` 
- **Telegram**: Configura `TELEGRAM_BOT_TOKEN` e `TELEGRAM_CHAT_ID`

## Log

Tutte le operazioni vengono loggate in `webtoon-manager.log` per tracciamento e debug.

## Esempi Pratici

```bash
# Setup completo
./webtoon-manager.sh config
./webtoon-manager.sh setup-cron

# Aggiungi serie popolari al monitoraggio
./webtoon-manager.sh monitor "https://www.webtoons.com/en/fantasy/tower-of-god/list?title_no=95" --format cbz
./webtoon-manager.sh monitor "https://www.webtoons.com/en/romance/down-to-earth/list?title_no=1817" --format cbz

# Controllo manuale
./webtoon-manager.sh check-updates
```

Lo script controllerà automaticamente ogni 6 ore se ci sono nuovi episodi e li scaricherà in formato Kavita-compatibile!