# Changelog

All notable changes to Back Alley will be documented in this file.

## [alpha/0.0.1] - 2025-12-28

### Added
- **Car Theft System**: Steal parked vehicles with hotwire mechanic (hold E near vehicle)
- **Job System**: Accept intel-based theft contracts with 3 tiers
  - Tier 1 (Economy): Vehicles under $15,000 - 50% spawn chance
  - Tier 2 (Mid-range): $15,000-$40,000 - 35% spawn chance
  - Tier 3 (Premium): Over $40,000 - 15% spawn chance
- **Black Market**: Buy and sell vehicles through shady dealers
  - Seller reputation system (Very Sketchy / Sketchy / Trusted)
  - Risk of scams, clunkers, or legit deals based on reputation
  - Sell stolen vehicles with or without documentation
- **Document Forgery**: Legitimize stolen vehicles with 3 service tiers
  - Budget: 15% cost, 8 hours, 40% detection risk
  - Standard: 25% cost, 16 hours, 15% detection risk
  - Premium: $100k flat, instant, 2% detection risk
- **Heat System**: Vehicle heat that decays over time (10 per in-game hour)
- **Police System**: 3-level escalation during theft, pursuits, arrests with fines
- **Back Alley UI**: Custom interface to manage jobs, black market, and documents

## [alpha/0.2.1] - 2025-01-03

### Fixed
- **Stripped Car Value Exploit**: Cars listed in Alley Bazar now use actual vehicle value (accounting for removed parts, mileage, damage) instead of original base value - prevents double-dipping by selling parts then listing stripped car at full price
- **valueCalculator Errors**: Fixed "Couldn't find partCondition" error spam by wrapping calls in pcall with fallback chain (valueCalculator → veh.value → configBaseValue)
- **RLS Market Override**: Fixed stolen vehicles appearing in RLS career market listings - wrapper now correctly handles both array formats (IDs and objects)
- **Document Timer Bug**: Fixed timer increasing instead of decreasing when game time goes backwards (save reload, time warp) - now uses session-only lastUpdate tracking that resets on game restart

### Added
- Unit tests for document timer system (8 new tests covering all edge cases)

## [Unreleased]
- Improvements and bug fixes

<!-- Format for releases:
## [alpha/x.x.x] - YYYY-MM-DD
## [beta/x.x.x] - YYYY-MM-DD
## [release/x.x.x] - YYYY-MM-DD
-->
