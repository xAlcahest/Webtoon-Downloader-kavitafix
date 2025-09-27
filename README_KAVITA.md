# Webtoon-Downloader with Kavita Integration

This is a fork of [Webtoon-Downloader](https://github.com/Zehina/Webtoon-Downloader) that adds **Kavita-compatible naming support** for manga library organization.

## 🎯 New Features

### Kavita-Compatible File Naming
- **CBZ Files**: `Down To Earth Vol.2 Ch.247 - (S2) Episode 247.cbz`
- **PDF Files**: `Tower of God Vol.1 Ch.50 - Episode 50.pdf`
- **Images**: `Series Vol.X Ch.Y - Episode Title_01.jpg`

### Automatic Season Detection
- Recognizes patterns like `[Season 2]`, `(S3)`, `Season 1`
- Maps seasons to volumes for proper Kavita organization
- Maintains original episode titles in filenames

## 📋 Supported Formats

| Pattern | Volume | Chapter | Example |
|---------|--------|---------|---------|
| `Episode 01` | 1 | 1 | `Series Vol.1 Ch.1 - Episode 01` |
| `[Season 2] Ep. 201` | 2 | 201 | `Series Vol.2 Ch.201 - [Season 2] Ep. 201` |
| `(S3) Episode 234` | 3 | 234 | `Series Vol.3 Ch.234 - (S3) Episode 234` |

## 🚀 Usage

Same as the original downloader, but with automatic Kavita naming:

```bash
# Install dependencies
poetry install

# Download CBZ files (recommended for Kavita)
poetry run webtoon-downloader "WEBTOON_URL" --save-as cbz --latest

# Download range of episodes  
poetry run webtoon-downloader "WEBTOON_URL" --start 1 --end 10 --save-as cbz

# Download PDF files
poetry run webtoon-downloader "WEBTOON_URL" --save-as pdf --latest
```

## 📊 Perfect Kavita Integration

Files created by this fork will be automatically recognized by Kavita manga scanner with correct:
- **Series name**
- **Volume number** (from season)  
- **Chapter number** (episode)
- **Chapter title** (original episode title)

## 🔧 Technical Changes

- **Added**: `season_parser.py` - Automatic season/episode detection
- **Extended**: `ChapterInfo` model with `volume_number` field  
- **Created**: `KavitaFileNameGenerator` classes for Kavita naming
- **Updated**: Downloaders to support CBZ/PDF Kavita naming
- **Maintained**: Full backward compatibility

## 🏆 Benefits

✅ **No manual file renaming required**  
✅ **Perfect Kavita manga scanner compatibility**  
✅ **Supports multi-season webtoons**  
✅ **All original features preserved**  
✅ **CBZ, PDF, ZIP, and image support**

## 📝 Original Project

This fork is based on the excellent [Webtoon-Downloader](https://github.com/Zehina/Webtoon-Downloader) by Zehina.

All original features and functionality are preserved - this fork only adds the Kavita naming system on top of the existing codebase.

## 🎉 Ready for Production

Tested with popular webtoons like "Down to Earth" and works perfectly with multi-season content. The naming system handles all edge cases and provides consistent Kavita-compatible files.