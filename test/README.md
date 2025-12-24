# BackAlley Mod - Testing & Development

This directory contains unit tests and a standalone UI preview for developing the BackAlley car theft mod without needing to run BeamNG.

## Standalone UI Preview

Preview and debug the Angular UI in your browser:

### Option 1: Using Node.js (recommended)
```bash
cd car_theft_career/test
npm run serve
```
Or from the mod root:
```bash
cd car_theft_career
npx http-server . -p 8080 -o ui-preview.html
```

### Option 2: Direct file access
Open `ui-preview.html` (in mod root) directly in your browser. Note: Some browsers may block local file loading - use a local server if you encounter issues.

### Features
- Full UI rendering with mock data
- Add/remove money to test affordability states
- Debug panel shows all API calls
- Reset button restores initial state

## Lua Unit Tests

Test the mod's game logic outside of BeamNG:

### Requirements
- Lua 5.1+ interpreter (or LuaJIT)

### Running Tests
```bash
cd test
lua run_tests.lua
```

### What's Tested
- **config.lua**: Tier thresholds, pricing formulas, documentation tier configs
- **Tier calculation**: Vehicle value → tier mapping
- **Fee generation**: Intel fee calculations (70-115% of value)
- **Documentation fees**: Budget/standard/premium tier costs
- **Black market pricing**: Reputation-based price multipliers
- **Purchase outcomes**: Scam/clunker/legit probability distribution
- **Heat system**: Initial heat, decay rates, minimum values
- **Area detection**: Position → area name mapping
- **Vehicle exclusion**: Filter out frames, trailers, police cars, etc.

## File Structure

```
car_theft_career/
├── ui-preview.html        # Standalone UI preview (in mod root)
└── test/
    ├── README.md          # This file
    ├── package.json       # npm scripts for convenience
    ├── run_tests.lua      # Lua test runner
    ├── mock-beamng-api.js # JavaScript API mock for UI
    └── mocks/
        └── beamng_mocks.lua   # Lua API mocks for tests
```

## Mock API Coverage

### Lua Mocks (beamng_mocks.lua)
- `be:getPlayerVehicleID()`, `be:getObjectByID()`
- `core_vehicles.spawnNewVehicle()`, `core_vehicles.getConfig()`
- `gameplay_parking.getParkingSpots()`
- `career_modules_playerAttributes`, `career_modules_payment`
- `career_modules_inventory`
- `guihooks.trigger()`
- `vec3()`, `quat()` math types

### JavaScript Mocks (mock-beamng-api.js)
- `bngApi.engineLua()` - intercepts all Lua calls and returns mock data
- Supports: jobs, vehicles, black market, documentation, cart, money

## Adding New Tests

Edit `run_tests.lua` and add new test suites:

```lua
describe("My New Feature", function()
  it("should do something", function()
    assertEqual(actual, expected, "Error message")
  end)
end)
```

Available assertions:
- `assertEqual(actual, expected, message)`
- `assertNotNil(value, message)`
- `assertNil(value, message)`
- `assertTrue(value, message)`
- `assertFalse(value, message)`
- `assertGreaterThan(actual, expected, message)`
- `assertLessThan(actual, expected, message)`
- `assertBetween(actual, min, max, message)`
