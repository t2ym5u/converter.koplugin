# Changelog

All notable changes to this project will be documented in this file.

## [1.0.3] - 2026-11-12

### Changed
- Picks up game-common 1.16.0: games for two readers (new Two readers
  category) and the shared Start / Join dialog.

## [1.0.2] - 2026-11-04

### Fixed
- The tool no longer crashes when an outdated plugin is installed alongside:
  shared modules left behind by an older plugin are replaced by this
  plugin's own copy instead of being used as they are.

## [1.0.1] - 2026-11-04

### Changed
- Uses less memory: the tool loads when you open it, not when KOReader
  starts, so it no longer takes memory or startup time while unused.

## [1.0.0] - 2026-11-03

### Added
- First release: a unit converter on one screen. Pick a category and two
  units (⇄ swaps them), type the value on the on-screen keypad; the result
  and the value in every unit of the category update as you type. Tap a
  line of the table to make that unit the target.
- Length, mass, volume, temperature, area, speed, duration, fuel
  consumption (L/100 km ↔ km/L ↔ mpg US/UK), energy, pressure, data size
  (SI and binary prefixes) and angle, with the exact SI/NIST factors.
- Cooking: metric and US spoons, cups and fluid ounces ↔ grams for 25
  ingredients (King Arthur Baking and USDA weights); oven temperatures
  °C ↔ °F ↔ gas mark ↔ French thermostat.
- Currencies: ECB euro reference rates, bundled (2026-11-03) so it works
  offline, updated on request over Wi-Fi; the rate date is always shown.
- Time zones: the time in 55 cities with their daylight saving rules
  (EU, US/Canada, Australia, New Zealand, Egypt), now or at a typed time,
  relative to the reader's clock or to a chosen home city.
- Roman numerals (1–3999, strict) and number bases (bin/oct/dec/hex).
- Remembers the category, units and value of each category; recent
  conversions and favourite unit pairs in the ☰ menu.
- Decimal comma and thousands separators follow the UI language; English,
  French, Spanish and German.
