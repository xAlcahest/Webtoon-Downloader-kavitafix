import re
from typing import Tuple


def parse_season_from_title(title: str) -> Tuple[int, int]:
    """
    Parse season and episode information from webtoon chapter title.
    
    Args:
        title: The chapter title (e.g., "Episode 01", "[Season 2] Ep. 201", "(S3) Episode 234")
        
    Returns:
        Tuple of (volume_number, episode_number) where:
        - volume_number corresponds to season (default 1 if no season specified)
        - episode_number is the episode number from the title
        
    Examples:
        "Episode 01" -> (1, 1)
        "Ep. 45" -> (1, 45) 
        "[Season 2] Ep. 201" -> (2, 201)
        "(S3) Episode 234" -> (3, 234)
        "[Season 3] Ep. 234" -> (3, 234)
    """
    # Patterns to match season indicators
    season_patterns = [
        r'\[Season\s+(\d+)\]',  # [Season 2], [Season 3]
        r'\(S(\d+)\)',          # (S2), (S3)
        r'Season\s+(\d+)',      # Season 2, Season 3
        r'S(\d+)',              # S2, S3
    ]
    
    # Patterns to match episode numbers
    episode_patterns = [
        r'Ep\.?\s*(\d+)',       # Ep. 201, Ep 201, Ep.201
        r'Episode\s+(\d+)',     # Episode 01, Episode 201
    ]
    
    volume_number = 1  # Default to volume 1 if no season found
    episode_number = 1  # Default episode number
    
    # Try to find season information
    for pattern in season_patterns:
        match = re.search(pattern, title, re.IGNORECASE)
        if match:
            volume_number = int(match.group(1))
            break
    
    # Try to find episode number
    for pattern in episode_patterns:
        match = re.search(pattern, title, re.IGNORECASE)
        if match:
            episode_number = int(match.group(1))
            break
    
    return volume_number, episode_number


def generate_kavita_filename(series_title: str, volume: int, chapter: int, chapter_title: str) -> str:
    """
    Generate a Kavita-compatible filename for a webtoon chapter.
    
    Args:
        series_title: Name of the webtoon series
        volume: Volume number (corresponds to season)
        chapter: Chapter number (corresponds to episode)
        chapter_title: Original chapter title
        
    Returns:
        Kavita-compatible filename in format: "Series Name Vol.X Ch.Y - Chapter Title"
        
    Example:
        generate_kavita_filename("Tower of God", 2, 201, "[Season 2] Ep. 201")
        -> "Tower of God Vol.2 Ch.201 - [Season 2] Ep. 201"
    """
    # Sanitize series title for filename use
    safe_series_title = re.sub(r'[<>:"/\\|?*]', '_', series_title).strip()
    safe_chapter_title = re.sub(r'[<>:"/\\|?*]', '_', chapter_title).strip()
    
    return f"{safe_series_title} Vol.{volume} Ch.{chapter} - {safe_chapter_title}"