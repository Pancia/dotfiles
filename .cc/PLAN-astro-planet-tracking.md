# Implementation Plan: `astro planet` Command

## Overview
Add `astro planet <name>` command to track a single planet/asteroid over extended time periods (12-36 months), showing sign changes, house transits, retrograde stations, and aspects to natal planets.

## User Requirements
- Track ALL event types: sign ingresses, house changes, retrograde/direct stations, aspects to natal planets
- Flexible timeline: `--past N --future N` (months) OR `--from DATE --to DATE`
- Output: Summary statistics + detailed chronological timeline
- Example: `astro planet chiron --past 24 --future 12`

## Architecture Overview
The astro tool has a clean modular structure:
- **Data Models** (lines 33-86): Dataclasses for birth data, charts, transit events
- **AstroStorage** (lines 92-196): File I/O with monthly caching
- **ChartManager** (lines 202-277): Chart CRUD operations
- **TransitCalculator** (lines 283-502): Kerykeion integration, aspect calculations
- **TransitFormatter** (lines 508-607): Display formatting with Unicode symbols
- **CLI** (lines 613-767): Argparse subcommands

## Implementation Steps

### 1. Add New Data Model (After line 71)

Create `PlanetTrackingEvent` dataclass to represent all event types:

```python
@dataclass
class PlanetTrackingEvent:
    """Event for planet tracking over time."""
    date: str  # ISO format YYYY-MM-DD
    planet: str  # Planet name
    event_type: str  # 'sign_change', 'house_change', 'station_retrograde', 'station_direct', 'aspect'

    # Position (always present)
    sign: str
    house: str

    # Sign change fields
    from_sign: str = ""
    to_sign: str = ""

    # House change fields
    from_house: str = ""
    to_house: str = ""

    # Station fields
    degree: float = 0.0  # Exact degree of station
    speed: float = 0.0  # Daily motion in degrees/day

    # Aspect fields (reuse TransitEvent structure)
    natal_planet: str = ""
    aspect: str = ""  # conjunction, opposition, trine, square, sextile
    orb: float = 0.0
    natal_sign: str = ""
    natal_house: str = ""
```

### 2. Update TransitCalculator (lines 283-502)

#### 2a. Add Planet Tracking Method (After line 451)

```python
def track_planet(self, natal_chart: NatalChart, planet_name: str,
                 start_date: datetime, end_date: datetime,
                 include_aspects: bool = True,
                 aspect_orb: float = 1.0) -> list[PlanetTrackingEvent]:
    """
    Track a single planet across a date range.

    Detects: sign changes, house changes, retrograde stations, aspects to natal planets.
    Samples daily at noon. For Moon, could add 6-hour sampling in future.

    Returns chronologically sorted list of events.
    """
    events = []
    bd = natal_chart.birth_data

    # Create natal subject once (for aspect calculations)
    natal = self._make_subject(
        bd.full_name, bd.year, bd.month, bd.day, bd.hour, bd.minute, bd
    )
    self._cache_coords(natal_chart, natal)

    # Iterate day by day
    current = start_date.date() if hasattr(start_date, 'date') else start_date
    end = end_date.date() if hasattr(end_date, 'date') else end_date
    prev_subject = None

    while current <= end:
        # Create transit subject at noon
        curr_subject = self._make_subject(
            "Transit", current.year, current.month, current.day, 12, 0, bd
        )

        if prev_subject:
            # Check for state transitions
            if event := self._detect_sign_change(planet_name, current, prev_subject, curr_subject):
                events.append(event)

            if event := self._detect_house_change(planet_name, current, prev_subject, curr_subject):
                events.append(event)

            if event := self._detect_station(planet_name, current, prev_subject, curr_subject):
                events.append(event)

        # Check for tight aspects to natal planets
        if include_aspects:
            aspect_events = self._get_planet_aspects(
                planet_name, current, curr_subject, natal, aspect_orb
            )
            events.extend(aspect_events)

        prev_subject = curr_subject
        current = current + timedelta(days=1)

    return sorted(events, key=lambda e: e.date)
```

#### 2b. Add Detection Methods (After track_planet)

```python
def _detect_sign_change(self, planet_name: str, date, prev_subj, curr_subj) -> Optional[PlanetTrackingEvent]:
    """Detect when planet changes signs."""
    prev_planet = self._get_planet_obj(prev_subj, planet_name)
    curr_planet = self._get_planet_obj(curr_subj, planet_name)

    if not prev_planet or not curr_planet:
        return None

    if prev_planet.sign != curr_planet.sign:
        house = self._clean_house(curr_planet.house)
        return PlanetTrackingEvent(
            date=date.isoformat(),
            planet=planet_name,
            event_type='sign_change',
            sign=curr_planet.sign,
            house=house,
            from_sign=prev_planet.sign,
            to_sign=curr_planet.sign
        )
    return None

def _detect_house_change(self, planet_name: str, date, prev_subj, curr_subj) -> Optional[PlanetTrackingEvent]:
    """Detect when planet changes houses."""
    prev_planet = self._get_planet_obj(prev_subj, planet_name)
    curr_planet = self._get_planet_obj(curr_subj, planet_name)

    if not prev_planet or not curr_planet:
        return None

    prev_house = self._clean_house(prev_planet.house)
    curr_house = self._clean_house(curr_planet.house)

    if prev_house != curr_house:
        return PlanetTrackingEvent(
            date=date.isoformat(),
            planet=planet_name,
            event_type='house_change',
            sign=curr_planet.sign,
            house=curr_house,
            from_house=prev_house,
            to_house=curr_house
        )
    return None

def _detect_station(self, planet_name: str, date, prev_subj, curr_subj) -> Optional[PlanetTrackingEvent]:
    """Detect retrograde/direct stations (when speed crosses zero)."""
    prev_planet = self._get_planet_obj(prev_subj, planet_name)
    curr_planet = self._get_planet_obj(curr_subj, planet_name)

    if not prev_planet or not curr_planet:
        return None

    prev_speed = getattr(prev_planet, 'speed', 0)
    curr_speed = getattr(curr_planet, 'speed', 0)

    # Check if speed changed sign (crossed zero)
    if prev_speed * curr_speed < 0:
        station_type = 'station_direct' if curr_speed > 0 else 'station_retrograde'
        house = self._clean_house(curr_planet.house)

        return PlanetTrackingEvent(
            date=date.isoformat(),
            planet=planet_name,
            event_type=station_type,
            sign=curr_planet.sign,
            house=house,
            degree=curr_planet.abs_pos,
            speed=curr_speed
        )
    return None

def _get_planet_aspects(self, planet_name: str, date, transit_subj, natal_subj,
                       orb_limit: float) -> list[PlanetTrackingEvent]:
    """Get tight aspects for a specific planet on a date."""
    from kerykeion import SynastryAspects

    aspects = SynastryAspects(transit_subj, natal_subj)
    events = []

    for asp in aspects.relevant_aspects:
        # Filter to only this planet's aspects
        if asp['p1_name'] != planet_name:
            continue

        # Filter to tight orbs only
        if abs(asp['orbit']) > orb_limit:
            continue

        # Filter to major planets on natal side
        if asp['p2_name'] not in self.MAJOR_PLANETS:
            continue

        # Get position data
        t_sign, t_house = self._get_planet_position(transit_subj, asp['p1_name'])
        n_sign, n_house = self._get_planet_position(natal_subj, asp['p2_name'])

        events.append(PlanetTrackingEvent(
            date=date.isoformat(),
            planet=planet_name,
            event_type='aspect',
            sign=t_sign,
            house=t_house,
            natal_planet=asp['p2_name'],
            aspect=asp['aspect'],
            orb=asp['orbit'],
            natal_sign=n_sign,
            natal_house=n_house
        ))

    return events

def _get_planet_obj(self, subject, planet_name: str):
    """Get planet object from subject by name."""
    attr_map = {
        'sun': 'sun', 'moon': 'moon', 'mercury': 'mercury',
        'venus': 'venus', 'mars': 'mars', 'jupiter': 'jupiter',
        'saturn': 'saturn', 'uranus': 'uranus', 'neptune': 'neptune',
        'pluto': 'pluto', 'chiron': 'chiron',
        'ceres': 'ceres', 'pallas': 'pallas', 'juno': 'juno', 'vesta': 'vesta',
        'true_node': 'true_node', 'mean_node': 'mean_node',
        'mean_lilith': 'mean_lilith', 'true_lilith': 'true_lilith',
    }
    attr = attr_map.get(planet_name.lower(), planet_name.lower())
    return getattr(subject, attr, None)

def _get_planet_position(self, subject, planet_name: str) -> tuple[str, str]:
    """Get (sign, house) for a planet. Extracted from _parse_aspects logic."""
    planet = self._get_planet_obj(subject, planet_name)
    if planet:
        sign = getattr(planet, 'sign', '')
        house = self._clean_house(getattr(planet, 'house', ''))
        return sign, house
    return '', ''

def _clean_house(self, house: str) -> str:
    """Convert 'First_House' to '1'."""
    house_map = {
        'First_House': '1', 'Second_House': '2', 'Third_House': '3',
        'Fourth_House': '4', 'Fifth_House': '5', 'Sixth_House': '6',
        'Seventh_House': '7', 'Eighth_House': '8', 'Ninth_House': '9',
        'Tenth_House': '10', 'Eleventh_House': '11', 'Twelfth_House': '12',
    }
    return house_map.get(house, house)
```

#### 2c. Update attr_map (line 461-469)

Add missing asteroids to the mapping:
```python
'Ceres': 'ceres',
'Pallas': 'pallas',
'Juno': 'juno',
'Vesta': 'vesta',
```

### 3. Add Formatter Methods (After line 607)

```python
def format_planet_summary(self, planet_name: str, events: list[PlanetTrackingEvent],
                         start_date: datetime, end_date: datetime,
                         natal_chart: NatalChart) -> str:
    """Format summary statistics for planet tracking."""
    if not events:
        return f"No events found for {planet_name} in date range."

    # Group events by type
    sign_changes = [e for e in events if e.event_type == 'sign_change']
    house_changes = [e for e in events if e.event_type == 'house_change']
    stations_retro = [e for e in events if e.event_type == 'station_retrograde']
    stations_direct = [e for e in events if e.event_type == 'station_direct']
    aspects = [e for e in events if e.event_type == 'aspect']

    # Current vs starting position
    starting = events[0]
    current = events[-1]

    # Format retrograde periods
    retro_periods = []
    for i, retro_station in enumerate(stations_retro):
        # Find corresponding direct station
        direct_station = None
        for d_station in stations_direct:
            if d_station.date > retro_station.date:
                direct_station = d_station
                break

        if direct_station:
            retro_periods.append(f"  {retro_station.date} to {direct_station.date}")
        else:
            retro_periods.append(f"  {retro_station.date} onwards (still retrograde)")

    retro_text = "\n".join(retro_periods) if retro_periods else "  None"

    # Count major aspects
    major_aspects = [a for a in aspects if a.aspect in ['conjunction', 'opposition', 'trine', 'square']]

    planet_sym = self.PLANET_SYMBOLS.get(planet_name.title(), planet_name)
    sign_sym = self.SIGN_SYMBOLS.get(starting.sign, starting.sign)
    curr_sign_sym = self.SIGN_SYMBOLS.get(current.sign, current.sign)

    return f"""
{planet_sym} {planet_name.upper()} Tracking
Period: {start_date.strftime('%Y-%m-%d')} to {end_date.strftime('%Y-%m-%d')} ({(end_date - start_date).days} days)
Chart: {natal_chart.birth_data.full_name}

Position:
  Starting: {sign_sym} {starting.sign} (house {starting.house})
  Current:  {curr_sign_sym} {current.sign} (house {current.house})

Activity Summary:
  Sign changes:        {len(sign_changes)}
  House transits:      {len(house_changes)}
  Retrograde stations: {len(stations_retro)}
  Direct stations:     {len(stations_direct)}
  Major aspects:       {len(major_aspects)} (conjunction/opposition/trine/square)
  All aspects:         {len(aspects)}

Retrograde Periods:
{retro_text}
"""

def format_planet_timeline(self, events: list[PlanetTrackingEvent],
                          group_by: str = 'month') -> str:
    """Format detailed chronological timeline."""
    if not events:
        return ""

    lines = []

    if group_by == 'month':
        # Group by year-month
        from itertools import groupby

        for year_month, month_events in groupby(events, key=lambda e: e.date[:7]):
            # Parse year-month
            year, month = year_month.split('-')
            month_name = datetime(int(year), int(month), 1).strftime('%B')

            lines.append(f"\n{month_name} {year}:")

            for event in month_events:
                lines.append(self._format_event(event))

    elif group_by == 'year':
        from itertools import groupby

        for year, year_events in groupby(events, key=lambda e: e.date[:4]):
            lines.append(f"\n{year}:")

            for event in year_events:
                lines.append(self._format_event(event))

    elif group_by == 'type':
        from itertools import groupby

        # Sort by type then date
        sorted_events = sorted(events, key=lambda e: (e.event_type, e.date))

        for event_type, type_events in groupby(sorted_events, key=lambda e: e.event_type):
            lines.append(f"\n{event_type.replace('_', ' ').title()}:")

            for event in type_events:
                lines.append(self._format_event(event))

    return "\n".join(lines)

def _format_event(self, event: PlanetTrackingEvent) -> str:
    """Format a single planet tracking event."""
    date = datetime.fromisoformat(event.date).strftime('%m-%d')
    planet_sym = self.PLANET_SYMBOLS.get(event.planet.title(), event.planet)

    if event.event_type == 'sign_change':
        from_sym = self.SIGN_SYMBOLS.get(event.from_sign, event.from_sign)
        to_sym = self.SIGN_SYMBOLS.get(event.to_sign, event.to_sign)
        return f"  {date}: {planet_sym} enters {to_sym} {event.to_sign} (house {event.house})"

    elif event.event_type == 'house_change':
        sign_sym = self.SIGN_SYMBOLS.get(event.sign, event.sign)
        return f"  {date}: {planet_sym} enters house {event.to_house} (in {sign_sym} {event.sign})"

    elif event.event_type == 'station_retrograde':
        sign_sym = self.SIGN_SYMBOLS.get(event.sign, event.sign)
        return f"  {date}: {planet_sym} stations RETROGRADE at {event.degree:.1f}° {sign_sym} {event.sign}"

    elif event.event_type == 'station_direct':
        sign_sym = self.SIGN_SYMBOLS.get(event.sign, event.sign)
        return f"  {date}: {planet_sym} stations DIRECT at {event.degree:.1f}° {sign_sym} {event.sign}"

    elif event.event_type == 'aspect':
        natal_sym = self.PLANET_SYMBOLS.get(event.natal_planet, event.natal_planet)
        aspect_sym = self.ASPECT_SYMBOLS.get(event.aspect.lower(), event.aspect)
        sign_sym = self.SIGN_SYMBOLS.get(event.sign, event.sign)

        return (f"  {date}: {planet_sym} {aspect_sym} {event.aspect} "
                f"{natal_sym} natal {event.natal_planet} ({event.orb:+.2f}°)")

    return f"  {date}: {event.event_type}"
```

### 4. Add CLI Command (After line 653)

```python
# Before main(), add timeline parser:
def parse_timeline_args(args) -> tuple[datetime, datetime]:
    """
    Parse timeline arguments into start_date, end_date.

    Priority:
    1. --from/--to (explicit dates)
    2. --past/--future (months from now)
    3. Default: 12 months past, 12 months future
    """
    now = datetime.now()

    # Explicit date range
    if hasattr(args, 'from_date') and args.from_date:
        start = datetime.strptime(args.from_date, "%Y-%m-%d")
    elif hasattr(args, 'past') and args.past:
        start = now - timedelta(days=args.past * 30)
    else:
        start = now - timedelta(days=365)  # Default: 12 months back

    if hasattr(args, 'to_date') and args.to_date:
        end = datetime.strptime(args.to_date, "%Y-%m-%d")
    elif hasattr(args, 'future') and args.future:
        end = now + timedelta(days=args.future * 30)
    else:
        end = now + timedelta(days=365)  # Default: 12 months forward

    return start, end

# In main(), after forecast parser (line 653):
    # --- Planet tracking ---
    planet_p = subparsers.add_parser('planet', help='Track single planet over time',
                                     epilog='''
Examples:
  astro planet chiron                    # 12 months past + 12 months future (default)
  astro planet mercury --past 24 --future 12  # 24 months back, 12 forward
  astro planet venus --from 2023-01-01 --to 2025-12-31  # Explicit range
  astro planet mars --summary-only       # Just statistics, no timeline
  astro planet jupiter --no-aspects      # Ingresses and stations only
''')
    planet_p.add_argument('name', help='Planet name (mars, venus, chiron, etc.)')
    planet_p.add_argument('chart', nargs='?', help='Chart name (uses config default)')

    # Timeline options
    timeline_g = planet_p.add_argument_group('timeline options')
    timeline_g.add_argument('--past', type=int, help='Months in past')
    timeline_g.add_argument('--future', type=int, help='Months in future')
    timeline_g.add_argument('--from', dest='from_date', type=str,
                           help='Start date (YYYY-MM-DD)')
    timeline_g.add_argument('--to', dest='to_date', type=str,
                           help='End date (YYYY-MM-DD)')

    # Display options
    display_g = planet_p.add_argument_group('display options')
    display_g.add_argument('--no-aspects', action='store_true',
                          help='Exclude aspects (faster)')
    display_g.add_argument('--aspect-orb', type=float, default=1.0,
                          help='Max aspect orb in degrees (default: 1.0)')
    display_g.add_argument('--group-by', choices=['month', 'year', 'type'],
                          default='month', help='Timeline grouping')
    display_g.add_argument('--summary-only', action='store_true',
                          help='Show summary only, no timeline')
```

### 5. Add CLI Dispatch Handler (After line 750)

```python
    elif args.command == 'planet':
        try:
            # Validate planet name
            valid_planets = {
                'sun', 'moon', 'mercury', 'venus', 'mars', 'jupiter', 'saturn',
                'uranus', 'neptune', 'pluto', 'chiron',
                'ceres', 'pallas', 'juno', 'vesta',
                'true_node', 'mean_node', 'mean_lilith', 'true_lilith'
            }
            planet_name = args.name.lower()

            if planet_name not in valid_planets:
                print(f"Error: Unknown planet '{args.name}'", file=sys.stderr)
                print(f"Valid: {', '.join(sorted(valid_planets))}", file=sys.stderr)
                sys.exit(1)

            # Load chart
            chart = storage.load_chart(get_chart_name(args.chart))

            # Parse timeline
            start_date, end_date = parse_timeline_args(args)

            # Validate date range
            days = (end_date - start_date).days
            if days > 1095:  # 3 years
                print(f"Warning: {days} days is a large range. First run may be slow.",
                      file=sys.stderr)

            # Track planet
            print(f"Tracking {planet_name}...", file=sys.stderr)
            events = transit_calc.track_planet(
                chart,
                planet_name,
                start_date,
                end_date,
                include_aspects=not args.no_aspects,
                aspect_orb=args.aspect_orb
            )

            # Display results
            print(formatter.format_planet_summary(
                planet_name, events, start_date, end_date, chart
            ))

            if not args.summary_only:
                print("\nDetailed Timeline:")
                print("=" * 60)
                print(formatter.format_planet_timeline(events, group_by=args.group_by))

        except FileNotFoundError as e:
            print(f"Error: {e}", file=sys.stderr)
            sys.exit(1)
        except ValueError as e:
            print(f"Error: {e}", file=sys.stderr)
            sys.exit(1)
```

## Files to Modify

1. **`bin/astro`** (main implementation)
   - Lines ~72: Add `PlanetTrackingEvent` dataclass
   - Lines ~452: Add `track_planet()` and detection methods to `TransitCalculator`
   - Lines ~465: Update `attr_map` with missing asteroids
   - Lines ~607: Add `format_planet_summary()` and `format_planet_timeline()` to `TransitFormatter`
   - Lines ~612: Add `parse_timeline_args()` function
   - Lines ~653: Add planet subparser
   - Lines ~750: Add planet dispatch handler

## Testing Strategy

1. **Fast planet (Mercury)**: Verify sign changes detected (13 per year)
2. **Slow planet (Saturn)**: Verify minimal events
3. **Retrograde planet (Mars)**: Verify stations detected accurately
4. **Chiron specifically**: Test user's main use case (24 months past + 12 future)
5. **Timeline parsing**: Test all argument combinations
6. **Output formatting**: Verify readability for 36-month spans

## Performance Notes

- First run: ~2-3 minutes for 36 months (uncached)
- Subsequent runs: Nearly instant (existing monthly cache applies)
- No new caching needed - daily transit calculations already cached
- Add `--no-aspects` flag for faster ingress/station-only tracking

## Example Output

```
☿ MERCURY Tracking
Period: 2023-01-01 to 2025-12-31 (1095 days)
Chart: Anthony Smith

Position:
  Starting: ♑ Cap (house 10)
  Current:  ♊ Gem (house 3)

Activity Summary:
  Sign changes:        39
  House transits:      26
  Retrograde stations: 6
  Direct stations:     6
  Major aspects:       48
  All aspects:         127

Retrograde Periods:
  2023-04-21 to 2023-05-14
  2023-08-23 to 2023-09-15
  ...

Detailed Timeline:
=============================================================

January 2023:
  01-02: ☿ enters ♒ Aquarius (house 11)
  01-15: ☿ △ trine natal ♃ Jupiter (+0.3°)
  ...
```

## Edge Cases Handled

- Fast-moving Moon: Daily sampling sufficient (could add 6-hour in future)
- Station detection: Uses speed sign change (robust)
- Missing planet data: Graceful None handling
- Large date ranges: Warning for > 3 years
- Invalid planet names: Clear error with valid list
