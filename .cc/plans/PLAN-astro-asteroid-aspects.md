# Implementation Plan: Manual Aspect Calculations for Asteroids

## Overview

Add manual aspect calculation for asteroids (Ceres, Pallas, Juno, Vesta) in the astro tool. Currently, asteroids are skipped in aspect detection because kerykeion's `SynastryAspects` class only handles standard planets. We'll implement angular difference calculations directly to enable asteroid-to-natal-planet aspects.

## Critical Files

- **bin/astro** (lines 817-865): Main implementation location
  - Modify `_get_planet_aspects()` at lines 820-822
  - Add new `_calculate_manual_aspects()` method after line 864

## Implementation Steps

### 1. Create `_calculate_manual_aspects()` Method

Add new method after line 864 (approximately 85 lines):

```python
def _calculate_manual_aspects(
    self,
    planet_name: str,
    date,
    transit_abs_pos: float,  # Asteroid's ecliptic position (0-360°)
    transit_sign: str,
    natal_subj,
    orb_limit: float,
    natal_cusps: dict[int, float],
    asteroid_orb_multiplier: float = 0.5  # Tighter orbs for asteroids
) -> list[PlanetTrackingEvent]:
    """
    Calculate aspects manually for asteroids using angular differences.

    Asteroids aren't included in kerykeion's SynastryAspects, so we calculate
    aspects by measuring angular differences and matching to aspect angles.
    """
    events = []

    # Define aspect types with their angles and base orbs from config
    aspects_to_check = [
        ('conjunction', 0, self.config.orb_settings.get('conjunction', 8)),
        ('sextile', 60, self.config.orb_settings.get('sextile', 4)),
        ('square', 90, self.config.orb_settings.get('square', 6)),
        ('trine', 120, self.config.orb_settings.get('trine', 6)),
        ('opposition', 180, self.config.orb_settings.get('opposition', 8)),
    ]

    # Check aspects against all major natal planets
    for natal_planet_name in self.MAJOR_PLANETS:
        natal_planet = self._get_planet_obj(natal_subj, natal_planet_name)
        if not natal_planet:
            continue

        natal_abs_pos = natal_planet.abs_pos

        # Calculate angular difference with zodiac wraparound
        # (e.g., 355° and 5° are 10° apart, not 350°)
        diff = abs(transit_abs_pos - natal_abs_pos)
        if diff > 180:
            diff = 360 - diff

        # Check each aspect type
        for aspect_name, target_angle, base_orb in aspects_to_check:
            # Apply asteroid multiplier to tighten orbs
            adjusted_orb = base_orb * asteroid_orb_multiplier

            # Calculate how far we are from the exact aspect
            aspect_diff = abs(diff - target_angle)

            # Check if within adjusted orb
            if aspect_diff <= adjusted_orb:
                # Calculate signed orb (positive = applying, negative = separating)
                # For now, keep it positive for consistency with existing code
                signed_orb = aspect_diff

                # Apply orb_limit parameter filter
                if abs(signed_orb) <= orb_limit:
                    # Calculate transit house position
                    t_house = self._planet_in_natal_house(transit_abs_pos, natal_cusps)

                    # Get natal planet position
                    n_sign, n_house = self._get_planet_position(natal_subj, natal_planet_name)

                    # Create PlanetTrackingEvent
                    events.append(PlanetTrackingEvent(
                        date=date.isoformat(),
                        planet=planet_name,
                        event_type='aspect',
                        sign=transit_sign,
                        house=t_house,
                        natal_planet=natal_planet_name,
                        aspect=aspect_name,
                        orb=signed_orb,
                        natal_sign=n_sign,
                        natal_house=n_house,
                        degree=transit_abs_pos
                    ))

    return events
```

**Key Algorithm Details:**

1. **Wraparound Handling** (lines 511-521 reference): Use the pattern from `get_lunar_phase()`
   - Calculate `diff = abs(transit_abs_pos - natal_abs_pos)`
   - If `diff > 180`, correct to `360 - diff` to handle zodiac wraparound

2. **Aspect Matching**: For each aspect type, check if the angular difference matches the target angle within the adjusted orb tolerance

3. **Orb Tightening**: Apply `asteroid_orb_multiplier = 0.5` to reduce orb ranges:
   - Conjunction: 8° → 4°
   - Opposition: 8° → 4°
   - Trine: 6° → 3°
   - Square: 6° → 3°
   - Sextile: 4° → 2°

4. **Filtering**: Only include aspects that pass both the adjusted orb check AND the `orb_limit` parameter

### 2. Modify `_get_planet_aspects()` Method

Replace lines 820-822 in `_get_planet_aspects()`:

**Current Code (lines 820-822):**
```python
# Skip aspects for asteroids (kerykeion's SynastryAspects doesn't include them)
if planet_name.lower() in self.ASTEROIDS:
    return []
```

**New Code:**
```python
# Use manual calculation for asteroids (kerykeion's SynastryAspects doesn't include them)
if planet_name.lower() in self.ASTEROIDS:
    asteroid = self._get_planet_obj(transit_subj, planet_name)
    if not asteroid:
        return []

    return self._calculate_manual_aspects(
        planet_name=planet_name,
        date=date,
        transit_abs_pos=asteroid.abs_pos,
        transit_sign=asteroid.sign,
        natal_subj=natal_subj,
        orb_limit=orb_limit,
        natal_cusps=natal_cusps,
        asteroid_orb_multiplier=0.5  # Use 50% of standard orbs for asteroids
    )
```

### 3. Integration with Existing Infrastructure

**No Changes Required** - The following components will automatically work:

1. **Data Flow** (line 597): `track_planet()` calls `_get_planet_aspects()` for each day
2. **Filtering** (line 659): `_filter_aspect_transitions()` post-processes aspect events to show entering/exact/leaving
3. **Formatting** (line 1140): `TransitFormatter.format_planet_timeline()` displays results
4. **Data Structure** (line 75): `PlanetTrackingEvent` already has all required aspect fields

## Testing Strategy

### Manual Testing Commands

```bash
# Track Ceres for 2 months
astro planet ceres --past 1 --future 1

# Track all asteroids to see aspect patterns
astro planet ceres --past 1 --future 1
astro planet pallas --past 1 --future 1
astro planet juno --past 1 --future 1
astro planet vesta --past 1 --future 1

# Test with tight orb filter (only exact aspects)
astro planet ceres --past 1 --future 1 --aspect-orb 0.5
```

### Test Cases to Verify

1. **Zodiac Wraparound**: Asteroid at 355° conjunct natal planet at 5° should detect as 10° conjunction
2. **Exact Aspects**: Asteroid exactly 90° from natal planet should show square at 0.0° orb
3. **Tight Orbs**: Asteroid 2° from exact trine should be included (within 3° asteroid orb)
4. **Out of Orb**: Asteroid 4° from exact square should be excluded (exceeds 3° asteroid orb)
5. **Multiple Aspects**: Asteroid aspecting multiple natal planets on same day should show all
6. **Retrograde Passes**: Asteroid making multiple passes should show entering/exact/leaving for each pass
7. **Aspect Types**: Verify all 5 aspect types (conjunction, sextile, square, trine, opposition) are detected

### Expected Output Format

```
Ceres Timeline (2025-12 to 2026-02)
════════════════════════════════════

2025-12-15  ♐︎ 12° (H3)  △ ☉ (entering, orb 2.3°) [☉ in ♌︎ H9]
2025-12-18  ♐︎ 15° (H3)  △ ☉ (exact, orb 0.1°) [☉ in ♌︎ H9]
2025-12-22  ♐︎ 18° (H3)  △ ☉ (leaving, orb 2.5°) [☉ in ♌︎ H9]
```

## Edge Cases & Considerations

### 1. Applying vs Separating Aspects
**Current Decision**: Use positive orb values for consistency with existing code. The `_filter_aspect_transitions()` method doesn't rely on orb sign - it uses the minimum orb to find the exact point.

**Future Enhancement**: Calculate applying/separating based on daily motion direction (requires speed comparison).

### 2. Orb Configuration
**Current Decision**: Hardcode `asteroid_orb_multiplier = 0.5` to use 50% of standard orb settings.

**Future Enhancement**: Add `asteroid_orb_multiplier` to the Config class for user customization.

### 3. Performance
**Impact**: Adds ~10 comparisons per asteroid per day (1 asteroid × 10 natal planets × 5 aspect types = 50 checks per day). For a 60-day range, that's 3000 checks per asteroid - negligible.

**Optimization**: Early exit if `aspect_diff > adjusted_orb` before creating event object (already implemented in algorithm).

### 4. Consistency with Standard Planets
**Verification**: Manual calculation should produce same results as kerykeion's `SynastryAspects` for standard planets. We can validate this by temporarily applying the manual calculator to a standard planet and comparing outputs.

## Verification Steps

After implementation:

1. **Run with known aspect**: Find a date when an asteroid makes an exact aspect to a natal planet (use ephemeris or online calculator to verify)
2. **Compare orb values**: Ensure calculated orbs match expected values
3. **Check wraparound**: Test with asteroid position near 0°/360° boundary
4. **Verify filtering**: Confirm `_filter_aspect_transitions()` correctly identifies entering/exact/leaving
5. **Test retrograde**: Track asteroid through a retrograde period to ensure multiple passes are handled

## Alternative Approaches Considered

### Option A: Extend kerykeion (REJECTED)
**Pros**: More maintainable long-term, would benefit from kerykeion's aspect engine
**Cons**: Requires forking/contributing to external library, slower deployment, out of scope

### Option B: Separate manual calculator (CHOSEN)
**Pros**: Clean separation, no impact on existing functionality, easy to test
**Cons**: Minor code duplication with aspect logic (but minimal)

### Option C: Unified manual calculator for all planets (OVERKILL)
**Pros**: Single code path for all aspect calculations
**Cons**: Unnecessary complexity, risk of breaking existing functionality, no clear benefit

## Success Criteria

- [ ] Asteroid aspects are detected and displayed in planet tracking output
- [ ] Angular difference calculation correctly handles zodiac wraparound
- [ ] Orb values are appropriate (tighter than standard planets)
- [ ] Filtering produces entering/exact/leaving transitions
- [ ] Multiple passes (retrograde) are handled correctly
- [ ] All 5 major aspect types are detected (conjunction, sextile, square, trine, opposition)
- [ ] Performance is acceptable for typical date ranges (60-90 days)
