# Webtoon Manager

Script di gestione avanzato per il Webtoon Downloader con integrazione Kavita completa.

## 🎯 Caratteristiche

- **Download automatico** con monitoraggio ogni 6 ore
- **Integrazione Kavita** con autenticazione JWT ufficiale e trigger automatico per la scansione
- **Gestione concorrenza** ottimizzabile (capitoli e pagine contemporanei)
- **Notifiche opzionali** (Discord/Telegram)
- **Configurazione interattiva** guidata
- **Logging completo** delle operazioni
- **Cron di sistema** per esecuzione come root

## 📋 Setup Iniziale

### 1. Installazione Poetry
```bash
# Installa Poetry
curl -sSL https://install.python-poetry.org | python3 -

# Aggiungi al PATH
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc

# Installa dipendenze del progetto
poetry install
```

### 2. Configurazione iniziale
```bash
# Configurazione interattiva completa
./webtoon-manager-simple.sh config
```

Questo ti guiderà nella configurazione di:
- **URL e API key di Kavita** (con test di connessione)
- **Library ID di Kavita**
- **Formati di download predefiniti** (CBZ raccomandato)
- **Impostazioni di qualità e concorrenza**

### 3. Setup del monitoraggio automatico
```bash
# Configura cron di sistema (ogni 6 ore)
./webtoon-manager-simple.sh setup-cron
```

## 🚀 Utilizzo

### Download Manuale (+ Monitoraggio Automatico)
```bash
# Download completo di una serie + aggiunta automatica al monitoraggio
./webtoon-manager-simple.sh download "https://www.webtoons.com/en/fantasy/tower-of-god/list?title_no=95"

# Download con opzioni personalizzate
./webtoon-manager-simple.sh download "URL" \\
  --format cbz \\
  --quality 90 \\
  --concurrent-chapters 3 \\
  --concurrent-pages 15 \\
  --start 1 --end 10
```

### Gestione Monitoraggio
```bash
# Lista serie monitorate
./webtoon-manager-simple.sh list-monitored

# Rimuovi dal monitoraggio
./webtoon-manager-simple.sh remove-monitor "URL"

# Controllo manuale aggiornamenti (--latest)
./webtoon-manager-simple.sh check-updates
```

### Gestione Cron Job
```bash
# Configura controllo automatico ogni 6 ore (sistema)
./webtoon-manager-simple.sh setup-cron

# Rimuovi il controllo automatico
./webtoon-manager-simple.sh remove-cron

# Verifica cron attivo
crontab -l | grep webtoon
```

## ⚙️ File di Configurazione

Il file `webtoon-config.conf` contiene:

```bash
# Kavita Settings (Autenticazione JWT ufficiale)
KAVITA_URL="http://localhost:5000"
KAVITA_API_KEY="your-api-key"
KAVITA_LIBRARY_ID=1

# Download Settings
DEFAULT_FORMAT="cbz"                    # cbz, pdf, images
DEFAULT_QUALITY=100                     # 40-100
CONCURRENT_CHAPTERS=3                   # 1-10 (sicuro: 1-3)
CONCURRENT_IMAGES=10                    # 1-50 (sicuro: 5-15)

# Notification Settings (opzionale)
DISCORD_WEBHOOK_URL=""
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""
```

## 🎛️ Parametri di Performance

### Impostazioni Conservative (Sicure)
```bash
--concurrent-chapters 2 --concurrent-pages 8 --quality 90
```

### Impostazioni Aggressive (Veloci)
```bash
--concurrent-chapters 5 --concurrent-pages 20 --quality 100
```

### Impostazioni per Connessioni Lente
```bash
--concurrent-chapters 1 --concurrent-pages 5 --quality 80
```

## 🔐 Integrazione Kavita

Lo script implementa il **protocollo di autenticazione ufficiale Kavita**:

### Processo Automatico:
1. **API Key** → Richiesta JWT Token a `/api/Plugin/authenticate`
2. **JWT Token** → Utilizzato per chiamate API con `Authorization: Bearer`
3. **Scan Trigger** → `/api/Library/scan-all` (o libreria specifica)

### Pattern di Naming Kavita:
- **CBZ Files**: `Down To Earth Vol.2 Ch.247 - (S2) Episode 247.cbz`
- **PDF Files**: `Tower of God Vol.1 Ch.50 - Episode 50.pdf`
- **Images**: `Series Vol.X Ch.Y - Episode Title_01.jpg`

## 📊 Workflow Automatico

1. **Download Manuale** → Scarica tutta la serie + aggiunge al monitoraggio
2. **Cron Sistema** → Ogni 6 ore controlla `--latest` per serie monitorate  
3. **Nuovi Episodi** → Download automatico + trigger scan Kavita
4. **Notifiche** → Discord/Telegram (se configurato)

## 🗂️ Struttura File

```
~/Webtoon-Downloader-kavitafix/
├── webtoon-manager-simple.sh      # Script principale
├── webtoon-config.conf             # Configurazione
├── webtoon-manager.log             # Log operazioni
├── .cron_urls                      # URLs monitorati (auto)
└── downloads/                      # Directory download
    ├── Tower of God Vol.1 Ch.1 - Episode 01.cbz
    ├── Tower of God Vol.1 Ch.2 - Episode 02.cbz
    └── ...
```

## 🎉 Esempi Pratici

### Setup Completo da Zero
```bash
# 1. Configurazione
./webtoon-manager-simple.sh config

# 2. Download prima serie
./webtoon-manager-simple.sh download \\
  "https://www.webtoons.com/en/fantasy/tower-of-god/list?title_no=95" \\
  --format cbz

# 3. Aggiungi altre serie
./webtoon-manager-simple.sh download \\
  "https://www.webtoons.com/en/romance/down-to-earth/list?title_no=1817" \\
  --format cbz

# 4. Attiva monitoraggio automatico
./webtoon-manager-simple.sh setup-cron

# 5. Verifica
./webtoon-manager-simple.sh list-monitored
crontab -l
```

### Gestione Avanzata
```bash
# Controllo manuale con parametri custom
./webtoon-manager-simple.sh download "URL" \\
  --concurrent-chapters 6 \\
  --concurrent-pages 35 \\
  --quality 100 \\
  --format cbz

# Monitoraggio stato
tail -f webtoon-manager.log

# Test Kavita manuale
curl -X POST "http://localhost:5000/api/Plugin/authenticate?apiKey=YOUR_KEY&pluginName=test"
```

## 🏆 Vantaggi

- ✅ **Zero configurazione manuale** dopo setup iniziale
- ✅ **Compatibilità Kavita perfetta** con naming automatico
- ✅ **Performance ottimizzabile** in base alla connessione  
- ✅ **Esecuzione come root** con cron di sistema
- ✅ **Autenticazione sicura** con JWT token
- ✅ **Monitoraggio intelligente** solo per nuovi episodi
- ✅ **Logging completo** per debug e tracciamento

## 📝 Note Tecniche

- **Basato su Poetry** per gestione dipendenze pulita
- **Protocollo Kavita ufficiale** per integrazione API
- **Cron di sistema** per affidabilità enterprise
- **Gestione errori robusta** con retry automatici
- **Formato Kavita-compatibile** per perfect matching

Il sistema è progettato per funzionare 24/7 in produzione con intervento manuale minimo! 🚀