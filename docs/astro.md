# Astro - Astrological Transit Tracker

CLI tool for tracking astrological transits against natal charts. Uses kerykeion for calculations.

## Quick Start

```bash
astro add-chart              # Create natal chart interactively
astro now                    # Current transits
astro forecast -d 30         # 30-day forecast
```

## Commands

| Command | Description |
|---------|-------------|
| `astro add-chart [NAME]` | Create natal chart interactively |
| `astro list-charts` | List saved charts |
| `astro show-chart [NAME]` | Display chart details |
| `astro remove-chart NAME` | Delete a chart |
| `astro now [NAME]` | Show current transits |
| `astro forecast [NAME]` | Forecast upcoming transits |
| `astro clear-cache` | Clear transit cache |
| `astro config` | Show configuration |

### Forecast Options

| Flag | Description |
|------|-------------|
| `-d, --days N` | Days to forecast (default: 30) |
| `--date YYYY-MM-DD` | Start date (default: today) |
| `-a, --all` | Include all transit-side objects (asteroids, transit nodes/Chiron/Lilith, angles) |
| `-o, --orb N` | Max orb in degrees for the per-day feed (default: 0.5) |
| `--sustained-orb N` | Max orb for the Sustained Aspects section (default: 2.0; `0` disables) |

```bash
astro forecast -d 7              # 7-day highlights
astro forecast --date 2025-06-01 -d 30  # 30-day forecast from June 1st
astro forecast -d 30 --all       # Include transit-side asteroids, angles, transit Chiron/Lilith
astro forecast -d 30 --orb 2     # Wider orb on the per-day feed
astro forecast -d 30 --sustained-orb 0   # Hide the Sustained Aspects section
```

The default forecast already includes transits to natal Nodes / Chiron / Lilith on the **natal side** — `--all` only widens the **transit side** (asteroids, transit Chiron, etc.).

Forecast output has two parts:

1. **Per-day feed**: aspects at exact orb (default `--orb 0.5°`), plus ingresses, stations, and lunar phases.
2. **Sustained Aspects**: slow-moving aspects that hold inside `--sustained-orb` (default `2.0°`) for at least 5 days (or any duration for outer planets, Jupiter+). Surfaces transits whose peak orb stays > 0.5° but which sit inside ~2° for weeks (Pluto-Venus, Neptune-NN). Each entry shows `in-orb FROM → TO (peak DATE, ±N°)`.

## Architecture

### File Structure

```
bin/astro                              # Main executable (~700 lines)
~/.local/share/astro/                  # Data directory
├── charts/                            # Natal chart JSON files
│   └── {name}.json
├── transits/                          # Transit cache by month
│   └── YYYY-MM/
│       └── YYYY-MM-DD_{chart}.json
├── ephemeris_cache/                   # Swiss Ephemeris data
└── config.json                        # User configuration
fish/completions/astro.fish            # Shell completions
```

### Internal Modules

The script is organized into modular classes for future API/MCP extraction:

| Class | Purpose |
|-------|---------|
| `AstroStorage` | File I/O, caching, config management |
| `ChartManager` | Natal chart CRUD operations |
| `TransitCalculator` | Transit computation via kerykeion |
| `TransitFormatter` | Display formatting with symbols |

### Data Models

```python
@dataclass
class BirthData:
    full_name: str
    year, month, day, hour, minute: int
    city, nation: str
    lat, lng: float          # Cached after first geocode
    tz_str: str

@dataclass
class NatalChart:
    name: str
    birth_data: BirthData
    created_at: str

@dataclass
class TransitEvent:
    transit_planet: str      # e.g., "Mars"
    natal_planet: str        # e.g., "Jupiter"
    aspect: str              # e.g., "trine"
    orb: float               # Degrees from exact
    transit_sign: str        # e.g., "Cap"
    transit_house: str       # e.g., "11"
    natal_sign: str
    natal_house: str
```

### Configuration

`~/.local/share/astro/config.json`:

```json
{
  "default_chart": "anthony",
  "geonames_username": "pancia",
  "orb_settings": {
    "conjunction": 8,
    "opposition": 8,
    "trine": 6,
    "square": 6,
    "sextile": 4
  },
  "display_format": "compact"
}
```

## Features

### Transit Display

Shows transiting planet, sign/house, aspect, and natal position:

```
♂ Mars     ♑11   △ trine      ♃ natal Jupiter  ♎9   (+0.35°)
│          │     │            │                │     └─ orb
│          │     │            │                └─ natal sign/house
│          │     │            └─ natal planet
│          │     └─ aspect symbol
│          └─ transit sign + house
└─ transit planet
```

### Lunar Phases

Forecasts include new/full moons:

```
🌑 New Moon in ♑ Cap
🌕 Full Moon in ♌ Leo
```

### Coordinate Caching

Birth location coordinates are geocoded via geonames on first use, then cached in the chart file to avoid repeated API calls.

## Dependencies

- `kerykeion` - Astrology calculations
- `pyswisseph` - Swiss Ephemeris (via kerykeion)

Runs via uv shebang - no manual installation needed:

```bash
#!/usr/bin/env -S uv run --with kerykeion python3
```

## Future Extraction

The modular class design enables easy extraction for:

1. **REST API** (`services/astro-api/`)
   - Move classes to `lib/python/astro/`
   - Create FastAPI server importing shared modules

2. **MCP Server**
   - Expose tools: `get_transits`, `forecast`, `add_chart`
   - Reuse core classes from lib
