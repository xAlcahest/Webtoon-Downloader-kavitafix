# mangadex-dl - Reference Documentation

Documentazione di riferimento per il tool `mangadex-dl` presente nel progetto.

## Panoramica

`mangadex-dl` è un downloader per manga da MangaDex che supporta:
- Download di manga completi
- Download di singoli capitoli
- Download di liste pubbliche/private
- Batch download da file
- Supporto formati multipli (raw, CBZ, PDF, EPUB, CB7)
- Login e autenticazione OAuth2

---

## 📥 Download Base

### Tipi di contenuto supportati

```bash
# Manga completo
mangadex-dl "https://mangadex.org/title/..."

# Cover manga
mangadex-dl "https://mangadex.org/covers/..."

# Singolo capitolo
mangadex-dl "https://mangadex.org/chapter/..."

# Lista (pubblica o privata)
mangadex-dl "https://mangadex.org/list/..."

# Solo ID (senza URL completo)
mangadex-dl "a96676e5-8ae2-425e-b549-7f15dd34a6d8"
```

### Batch download

Crea un file di testo con lista di URL (uno per riga):

```bash
# File: urls.txt
https://mangadex.org/title/manga_id
https://mangadex.org/chapter/chapter_id
https://mangadex.org/list/list_id
```

Esegui il download:

```bash
mangadex-dl "urls.txt"
```

---

## 💾 Formati di Output

### Formato RAW (default)

Immagini separate in cartelle per capitolo.

```bash
# Default
mangadex-dl "URL"

# Explicit
mangadex-dl "URL" --save-as raw
```

**Struttura:**
```
📦Manga title
 ┣ 📂Volume. 1 Chapter. 1
 ┃ ┣ 🖼️images
 ┣ 📂Volume. 1 Chapter. 2
 ┃ ┣ 🖼️images
 ┗ 🖼️cover.jpg
```

#### Varianti RAW

- **raw-volume**: Tutte le immagini raggruppate per volume
  ```bash
  mangadex-dl "URL" --save-as raw-volume
  ```

- **raw-single**: Tutte le immagini in un'unica cartella
  ```bash
  mangadex-dl "URL" --save-as raw-single
  ```

---

### Formato CBZ (Comic Book Archive - ZIP)

**⭐ CONSIGLIATO PER KAVITA**

File .cbz con metadati ComicInfo.xml per lettori di fumetti.

```bash
# Un file CBZ per capitolo
mangadex-dl "URL" --save-as cbz

# Un file CBZ per volume (tutti i capitoli del volume insieme)
mangadex-dl "URL" --save-as cbz-volume

# Un singolo file CBZ con tutto il manga
mangadex-dl "URL" --save-as cbz-single
```

**Struttura CBZ:**
```
📦Manga title
 ┣ 📜cover.jpg
 ┣ 📜Volume. 1 Chapter. 1.cbz
 ┗ 📜Volume. 1 Chapter. 2.cbz
```

**Struttura CBZ-Volume:**
```
📦Manga title
 ┣ 📜cover.jpg
 ┣ 📜Volume. 1.cbz
 ┗ 📜Volume. 2.cbz
```

---

### Formato PDF

```bash
# Un PDF per capitolo
mangadex-dl "URL" --save-as pdf

# Un PDF per volume
mangadex-dl "URL" --save-as pdf-volume

# Un singolo PDF con tutto
mangadex-dl "URL" --save-as pdf-single
```

**Struttura:**
```
📦Manga title
 ┣ 📜cover.jpg
 ┣ 📜Volume. 1 Chapter. 1.pdf
 ┗ 📜Volume. 1 Chapter. 2.pdf
```

---

### Formato CB7 (Comic Book Archive - 7-Zip)

Come CBZ ma basato su 7z invece di ZIP.

```bash
mangadex-dl "URL" --save-as cb7
mangadex-dl "URL" --save-as cb7-volume
mangadex-dl "URL" --save-as cb7-single
```

---

### Formato EPUB

Per e-readers.

```bash
# Un EPUB per capitolo
mangadex-dl "URL" --save-as epub

# Un EPUB per volume
mangadex-dl "URL" --save-as epub-volume

# Un singolo EPUB
mangadex-dl "URL" --save-as epub-single
```

⚠️ **Nota**: `epub-volume` e `epub-single` NON creano chapter info/cover separati.

---

## 🗂️ Gestione File

### Percorso di output

```bash
# Percorso assoluto
mangadex-dl "URL" --folder "/path/to/manga"
mangadex-dl "URL" --path "/path/to/manga"
mangadex-dl "URL" -d "/path/to/manga"

# Con placeholders
mangadex-dl "URL" -d "./mymanga/{manga.title}"
```

**Struttura con percorso custom:**
```
📂mymanga
 ┗ 📂some_kawaii_manga
   ┣ 📂Vol. 1 Ch. 1
   ┃ ┣ 📜00.png
   ┃ ┗ 📜01.png
   ┣ 📜cover.jpg
   ┗ 📜download.db
```

### Opzioni naming

```bash
# Sostituisci file esistenti
mangadex-dl "URL" --replace

# Aggiungi titolo capitolo nelle cartelle
mangadex-dl "URL" --use-chapter-title

# Rimuovi nome gruppo scanlator
mangadex-dl "URL" --no-group-name
```

---

## 📖 Range e Filtri

### Range capitoli

```bash
# Capitoli da 20 a 69
mangadex-dl "URL" --start-chapter 20 --end-chapter 69

# Con range pagine (applica a TUTTI i capitoli)
mangadex-dl "URL" --start-chapter 20 --end-chapter 69 --start-page 5 --end-page 20

# Range pagine per singolo capitolo
mangadex-dl "https://mangadex.org/chapter/..." --start-page 5 --end-page 20
```

⚠️ **Limitazioni:**
- `--start-chapter`/`--end-chapter` NON funzionano con liste
- `--start-page`/`--end-page` su manga scarica TUTTI i capitoli con quel range

### Oneshot

```bash
# Escludi capitoli oneshot
mangadex-dl "URL" --no-oneshot-chapter
```

---

## 🎨 Cover

```bash
# Qualità originale (default)
mangadex-dl "URL" --cover original

# 512px
mangadex-dl "URL" --cover 512px

# 256px
mangadex-dl "URL" --cover 256px

# Nessuna cover
mangadex-dl "URL" --cover none
```

---

## 🌐 Lingue

```bash
# Lista tutte le lingue disponibili
mangadex-dl --list-languages

# Download in lingua specifica
mangadex-dl "URL" --language "it"
mangadex-dl "URL" --language "Italian"
mangadex-dl "URL" --language "id"  # Indonesian
```

---

## 🔐 Autenticazione

### Login base

```bash
# Login interattivo (richiede username/password)
mangadex-dl "URL" --login

# Login non interattivo
mangadex-dl "URL" --login --login-username "user" --login-password "pass"
```

### OAuth2 (nuovo sistema)

```bash
mangadex-dl "URL" \
  --login \
  --login-method oauth2 \
  --login-username "username" \
  --login-password "password" \
  --login-api-id "API_CLIENT_ID" \
  --login-api-secret "API_CLIENT_SECRET"
```

⚠️ **Necessario per:**
- Liste private
- Manga nella tua library personale

---

## 🔍 Ricerca

```bash
# Cerca e scarica interattivamente
mangadex-dl "komi san" --search

# Output interattivo con paginazione:
# (1). Risultato 1
# (2). Risultato 2
# ...
# (10). Risultato 10
# 
# type "next" per risultati successivi
# type "previous" per risultati precedenti
```

---

## 🎲 Feature Speciali

### Random manga

```bash
# Manga casuale
mangadex-dl "random"

# Con filtri
mangadex-dl "random" --filter "content_rating=safe, suggestive"
```

### Seasonal manga

```bash
# Manga della stagione corrente
mangadex-dl "seasonal"
```

### Forum threads

```bash
# Download da thread forum
mangadex-dl "https://forums.mangadex.org/threads/..."
```

---

## ⚙️ Update

```bash
# Aggiorna mangadex-dl all'ultima versione
mangadex-dl --update
```

---

## 🎯 Use Cases Comuni

### Download per Kavita (CONSIGLIATO)

```bash
# CBZ per capitolo con qualità massima
mangadex-dl "https://mangadex.org/title/MANGA_ID" \
  --save-as cbz \
  --cover original \
  -d "./downloads/{manga.title}"

# CBZ per volume (struttura più pulita)
mangadex-dl "https://mangadex.org/title/MANGA_ID" \
  --save-as cbz-volume \
  --cover original \
  -d "./downloads/{manga.title}"
```

### Batch download ottimizzato

```bash
# File: batch.txt con lista URL
mangadex-dl "batch.txt" \
  --save-as cbz \
  --cover 512px \
  --no-oneshot-chapter \
  -d "./manga_library/{manga.title}"
```

### Download manga privato

```bash
mangadex-dl "https://mangadex.org/list/PRIVATE_LIST_ID" \
  --login \
  --login-username "myuser" \
  --login-password "mypass" \
  --save-as cbz-volume \
  -d "./private_collection/{manga.title}"
```

### Download selettivo

```bash
# Solo capitoli 50-100, senza oneshot
mangadex-dl "URL" \
  --start-chapter 50 \
  --end-chapter 100 \
  --no-oneshot-chapter \
  --save-as cbz \
  -d "./manga/{manga.title}"
```

---

## 📊 Formati - Riepilogo Veloce

| Formato | Descrizione | Kavita-Compatible | Comando |
|---------|-------------|-------------------|---------|
| **raw** | Immagini separate | ✅ Sì | `--save-as raw` |
| **cbz** | ZIP + ComicInfo.xml | ✅✅ **MIGLIORE** | `--save-as cbz` |
| **cbz-volume** | CBZ per volume | ✅✅ **OTTIMO** | `--save-as cbz-volume` |
| **pdf** | PDF standard | ⚠️ Limitato | `--save-as pdf` |
| **cb7** | 7-Zip archive | ✅ Sì | `--save-as cb7` |
| **epub** | E-reader format | ❌ No | `--save-as epub` |

---

## 🔗 Link Utili

- [Documentazione ufficiale](https://mangadex-dl.mansuf.link/en/stable/)
- [GitHub Repository](https://github.com/mansuf/mangadex-downloader)
- [Path placeholders](https://mangadex-dl.mansuf.link/en/stable/cli_ref/path_placeholders.html)
- [OAuth2 setup](https://mangadex-dl.mansuf.link/en/stable/cli_ref/oauth.html)

---

## 💡 Tips & Best Practices

1. **Per Kavita**: Usa sempre `--save-as cbz` o `cbz-volume`
2. **Cover**: Usa `original` per qualità massima, `512px` per bilanciare dimensione/qualità
3. **Naming**: Usa placeholders come `{manga.title}` per organizzazione automatica
4. **Batch**: Crea file .txt con URL per download multipli efficienti
5. **Login**: Necessario solo per contenuti privati o library personale
6. **Lingue**: Controlla `--list-languages` prima di scaricare in lingue non-inglesi
