# Webtoon Downloader - Kavita Integration Changelog

## New Features: Kavita-Compatible Naming System

### Overview
This modification adds support for Kavita-compatible file naming conventions that properly handle webtoon seasons and episodes. The new system automatically detects season information from episode titles and creates proper volume/chapter mappings.

### Key Changes

#### 1. Season Parsing (`season_parser.py`)
- **New function**: `parse_season_from_title()` - Automatically detects seasons from episode titles
- **Supported patterns**:
  - `Episode 01` → Volume 1, Episode 1
  - `[Season 2] Ep. 201` → Volume 2, Episode 201  
  - `(S3) Episode 234` → Volume 3, Episode 234
  - Case-insensitive parsing

#### 2. Enhanced Models (`models.py`)
- **Added field**: `volume_number` to `ChapterInfo` class
- Maintains backward compatibility with default value of 1

#### 3. New Naming Generators (`namer.py`)
- **KavitaFileNameGenerator**: For separate chapter directories
- **KavitaNonSeparateFileNameGenerator**: For single directory storage
- **Format**: `Series Name Vol.X Ch.Y - Episode Title`

#### 4. Updated Fetcher (`fetchers.py`)
- Automatically parses season information during chapter fetching
- Populates `volume_number` based on episode title analysis

#### 5. Modified Downloader (`comic.py`)
- Uses new Kavita naming generators by default
- Maintains existing CLI options and behavior

### Examples

| Original Episode Title | Volume | Chapter | Generated Filename |
|----------------------|--------|---------|-------------------|
| `Episode 01` | 1 | 1 | `Tower of God Vol.1 Ch.1 - Episode 01` |
| `[Season 2] Ep. 201` | 2 | 201 | `Tower of God Vol.2 Ch.201 - [Season 2] Ep. 201` |
| `(S3) Episode 234` | 3 | 234 | `Tower of God Vol.3 Ch.234 - (S3) Episode 234` |

### Benefits

1. **Kavita Compatibility**: Files are named according to Kavita's manga scanner requirements
2. **Season Organization**: Proper volume mapping for multi-season webtoons
3. **Backward Compatibility**: No breaking changes to existing CLI options
4. **Metadata Preservation**: Original episode titles are maintained in filenames

### Technical Details

- **Volume Mapping**: Season number → Volume number (default 1 if no season detected)
- **Chapter Mapping**: Sequential episode number → Chapter number
- **File Safety**: Automatic sanitization of unsafe filename characters
- **Pattern Recognition**: Robust regex patterns for various season formats

### Testing

Comprehensive tests included for:
- Season parsing accuracy
- Filename generation
- Integration with existing downloader
- Edge cases and error handling

### Migration

No migration required - the changes are automatically applied and maintain full backward compatibility with existing functionality.