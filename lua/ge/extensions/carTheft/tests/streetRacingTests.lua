-- Car Theft Career - Street Racing Unit Tests
-- Run from console: extensions.carTheft_streetRacingTests.runAll()

local M = {}

local logger = require("carTheft/logger")
local LOG_TAG = "streetRacingTests"

local testsPassed = 0
local testsFailed = 0
local testResults = {}

---------------------------------------------------------------------------
-- Test Framework
---------------------------------------------------------------------------

local function log(level, msg)
  logger.log(LOG_TAG, level, msg)
end

local function assertEquals(expected, actual, testName)
  if expected == actual then
    testsPassed = testsPassed + 1
    table.insert(testResults, {name = testName, passed = true})
    log("I", "[PASS] " .. testName)
    return true
  else
    testsFailed = testsFailed + 1
    table.insert(testResults, {name = testName, passed = false, expected = expected, actual = actual})
    log("E", "[FAIL] " .. testName .. " - Expected: " .. tostring(expected) .. ", Got: " .. tostring(actual))
    return false
  end
end

local function assertNotNil(value, testName)
  if value ~= nil then
    testsPassed = testsPassed + 1
    table.insert(testResults, {name = testName, passed = true})
    log("I", "[PASS] " .. testName)
    return true
  else
    testsFailed = testsFailed + 1
    table.insert(testResults, {name = testName, passed = false, expected = "not nil", actual = "nil"})
    log("E", "[FAIL] " .. testName .. " - Expected: not nil, Got: nil")
    return false
  end
end

local function assertNil(value, testName)
  if value == nil then
    testsPassed = testsPassed + 1
    table.insert(testResults, {name = testName, passed = true})
    log("I", "[PASS] " .. testName)
    return true
  else
    testsFailed = testsFailed + 1
    table.insert(testResults, {name = testName, passed = false, expected = "nil", actual = tostring(value)})
    log("E", "[FAIL] " .. testName .. " - Expected: nil, Got: " .. tostring(value))
    return false
  end
end

local function assertTrue(value, testName)
  return assertEquals(true, value, testName)
end

local function assertFalse(value, testName)
  return assertEquals(false, value, testName)
end

local function assertGreaterThan(expected, actual, testName)
  if actual > expected then
    testsPassed = testsPassed + 1
    table.insert(testResults, {name = testName, passed = true})
    log("I", "[PASS] " .. testName)
    return true
  else
    testsFailed = testsFailed + 1
    table.insert(testResults, {name = testName, passed = false, expected = ">" .. tostring(expected), actual = tostring(actual)})
    log("E", "[FAIL] " .. testName .. " - Expected: > " .. tostring(expected) .. ", Got: " .. tostring(actual))
    return false
  end
end

local function resetTestState()
  testsPassed = 0
  testsFailed = 0
  testResults = {}
end

---------------------------------------------------------------------------
-- Street Racing Tests
---------------------------------------------------------------------------

local function testModuleLoaded()
  log("I", "=== Testing Module Loading ===")

  local streetRacing = extensions.carTheft_streetRacing
  assertNotNil(streetRacing, "streetRacing module loaded")

  if streetRacing then
    assertNotNil(streetRacing.getRacesForUI, "getRacesForUI function exists")
    assertNotNil(streetRacing.getActiveEncounter, "getActiveEncounter function exists")
    assertNotNil(streetRacing.isNearAdversary, "isNearAdversary function exists")
    assertNotNil(streetRacing.getDistanceToAdversary, "getDistanceToAdversary function exists")
    assertNotNil(streetRacing.generateRandomRace, "generateRandomRace function exists")
    assertNotNil(streetRacing.setNavigationToStart, "setNavigationToStart function exists")
    assertNotNil(streetRacing.clearNavigation, "clearNavigation function exists")
    assertNotNil(streetRacing.getStats, "getStats function exists")
    assertNotNil(streetRacing.getLostVehicles, "getLostVehicles function exists")
    assertNotNil(streetRacing.RACE_STATE, "RACE_STATE constant exists")
    assertNotNil(streetRacing.ENCOUNTER_STATE, "ENCOUNTER_STATE constant exists")
  end
end

local function testRaceStates()
  log("I", "=== Testing Race States ===")

  local streetRacing = extensions.carTheft_streetRacing
  if not streetRacing then
    log("E", "streetRacing module not loaded, skipping tests")
    return
  end

  local RACE_STATE = streetRacing.RACE_STATE
  assertEquals("idle", RACE_STATE.IDLE, "RACE_STATE.IDLE value")
  assertEquals("staging", RACE_STATE.STAGING, "RACE_STATE.STAGING value")
  assertEquals("countdown", RACE_STATE.COUNTDOWN, "RACE_STATE.COUNTDOWN value")
  assertEquals("racing", RACE_STATE.RACING, "RACE_STATE.RACING value")
  assertEquals("finished", RACE_STATE.FINISHED, "RACE_STATE.FINISHED value")
  assertEquals("abandoned", RACE_STATE.ABANDONED, "RACE_STATE.ABANDONED value")
end

local function testEncounterStates()
  log("I", "=== Testing Encounter States ===")

  local streetRacing = extensions.carTheft_streetRacing
  if not streetRacing then
    log("E", "streetRacing module not loaded, skipping tests")
    return
  end

  local ENCOUNTER_STATE = streetRacing.ENCOUNTER_STATE
  assertEquals("none", ENCOUNTER_STATE.NONE, "ENCOUNTER_STATE.NONE value")
  assertEquals("spawned", ENCOUNTER_STATE.SPAWNED, "ENCOUNTER_STATE.SPAWNED value")
  assertEquals("challenged", ENCOUNTER_STATE.CHALLENGED, "ENCOUNTER_STATE.CHALLENGED value")
  assertEquals("countdown", ENCOUNTER_STATE.COUNTDOWN, "ENCOUNTER_STATE.COUNTDOWN value")
  assertEquals("racing", ENCOUNTER_STATE.RACING, "ENCOUNTER_STATE.RACING value")
  assertEquals("finished", ENCOUNTER_STATE.FINISHED, "ENCOUNTER_STATE.FINISHED value")
end

local function testGetRacesForUI()
  log("I", "=== Testing getRacesForUI ===")

  local streetRacing = extensions.carTheft_streetRacing
  if not streetRacing then
    log("E", "streetRacing module not loaded, skipping tests")
    return
  end

  local races = streetRacing.getRacesForUI()
  assertNotNil(races, "getRacesForUI returns a value")
  assertEquals("table", type(races), "getRacesForUI returns a table")
end

local function testGetActiveEncounter()
  log("I", "=== Testing getActiveEncounter ===")

  local streetRacing = extensions.carTheft_streetRacing
  if not streetRacing then
    log("E", "streetRacing module not loaded, skipping tests")
    return
  end

  -- When no encounter is active, should return nil
  local encounter = streetRacing.getActiveEncounter()
  -- Note: This may or may not be nil depending on game state
  -- Just test that the function returns without error
  log("I", "[INFO] getActiveEncounter returned: " .. tostring(encounter ~= nil and "encounter data" or "nil"))
  testsPassed = testsPassed + 1
  table.insert(testResults, {name = "getActiveEncounter executes without error", passed = true})
end

local function testIsNearAdversary()
  log("I", "=== Testing isNearAdversary ===")

  local streetRacing = extensions.carTheft_streetRacing
  if not streetRacing then
    log("E", "streetRacing module not loaded, skipping tests")
    return
  end

  local isNear = streetRacing.isNearAdversary()
  assertEquals("boolean", type(isNear), "isNearAdversary returns boolean")
end

local function testGetDistanceToAdversary()
  log("I", "=== Testing getDistanceToAdversary ===")

  local streetRacing = extensions.carTheft_streetRacing
  if not streetRacing then
    log("E", "streetRacing module not loaded, skipping tests")
    return
  end

  local distance = streetRacing.getDistanceToAdversary()
  assertEquals("number", type(distance), "getDistanceToAdversary returns number")
end

local function testGetStats()
  log("I", "=== Testing getStats ===")

  local streetRacing = extensions.carTheft_streetRacing
  if not streetRacing then
    log("E", "streetRacing module not loaded, skipping tests")
    return
  end

  local stats = streetRacing.getStats()
  assertNotNil(stats, "getStats returns a value")
  assertEquals("table", type(stats), "getStats returns a table")

  if stats then
    assertNotNil(stats.racesWon, "stats.racesWon exists")
    assertNotNil(stats.racesLost, "stats.racesLost exists")
    assertNotNil(stats.totalWinnings, "stats.totalWinnings exists")
    assertNotNil(stats.totalLosses, "stats.totalLosses exists")
    assertNotNil(stats.winRate, "stats.winRate exists")
  end
end

local function testGetLostVehicles()
  log("I", "=== Testing getLostVehicles ===")

  local streetRacing = extensions.carTheft_streetRacing
  if not streetRacing then
    log("E", "streetRacing module not loaded, skipping tests")
    return
  end

  local lostVehicles = streetRacing.getLostVehicles()
  assertNotNil(lostVehicles, "getLostVehicles returns a value")
  assertEquals("table", type(lostVehicles), "getLostVehicles returns a table")
end

local function testGenerateRandomRace()
  log("I", "=== Testing generateRandomRace ===")

  local streetRacing = extensions.carTheft_streetRacing
  if not streetRacing then
    log("E", "streetRacing module not loaded, skipping tests")
    return
  end

  -- This may return nil if no races are loaded
  local race = streetRacing.generateRandomRace()
  log("I", "[INFO] generateRandomRace returned: " .. tostring(race ~= nil and "race data" or "nil (no races loaded)"))
  testsPassed = testsPassed + 1
  table.insert(testResults, {name = "generateRandomRace executes without error", passed = true})
end

local function testNavigationFunctions()
  log("I", "=== Testing Navigation Functions ===")

  local streetRacing = extensions.carTheft_streetRacing
  if not streetRacing then
    log("E", "streetRacing module not loaded, skipping tests")
    return
  end

  -- Test clearNavigation
  local cleared = streetRacing.clearNavigation()
  assertEquals("boolean", type(cleared), "clearNavigation returns boolean")

  -- Test setNavigationToStart with invalid race
  local result, err = streetRacing.setNavigationToStart("nonexistent_race")
  assertFalse(result, "setNavigationToStart returns false for invalid race")
end

---------------------------------------------------------------------------
-- Race Editor Tests
---------------------------------------------------------------------------

local function testRaceEditorModuleLoaded()
  log("I", "=== Testing Race Editor Module Loading ===")

  local raceEditor = extensions.carTheft_raceEditor
  assertNotNil(raceEditor, "raceEditor module loaded")

  if raceEditor then
    assertNotNil(raceEditor.start, "start function exists")
    assertNotNil(raceEditor.setstart, "setstart function exists")
    assertNotNil(raceEditor.addcheckpoint, "addcheckpoint function exists")
    assertNotNil(raceEditor.removecheckpoint, "removecheckpoint function exists")
    assertNotNil(raceEditor.setfinish, "setfinish function exists")
    assertNotNil(raceEditor.preview, "preview function exists")
    assertNotNil(raceEditor.status, "status function exists")
    assertNotNil(raceEditor.save, "save function exists")
    assertNotNil(raceEditor.cancel, "cancel function exists")
    assertNotNil(raceEditor.list, "list function exists")
    assertNotNil(raceEditor.delete, "delete function exists")
    assertNotNil(raceEditor.help, "help function exists")
  end
end

local function testRaceEditorInactiveState()
  log("I", "=== Testing Race Editor Inactive State ===")

  local raceEditor = extensions.carTheft_raceEditor
  if not raceEditor then
    log("E", "raceEditor module not loaded, skipping tests")
    return
  end

  -- Cancel any active editing first
  raceEditor.cancel()

  -- These should fail when editor is not active
  local result = raceEditor.setstart()
  assertFalse(result, "setstart fails when editor inactive")

  result = raceEditor.addcheckpoint()
  assertFalse(result, "addcheckpoint fails when editor inactive")

  result = raceEditor.setfinish()
  assertFalse(result, "setfinish fails when editor inactive")

  result = raceEditor.save()
  assertFalse(result, "save fails when editor inactive")
end

local function testRaceEditorStartCommand()
  log("I", "=== Testing Race Editor Start Command ===")

  local raceEditor = extensions.carTheft_raceEditor
  if not raceEditor then
    log("E", "raceEditor module not loaded, skipping tests")
    return
  end

  -- Cancel any active editing
  raceEditor.cancel()

  -- Start with empty name should fail
  local result = raceEditor.start("")
  assertFalse(result, "start fails with empty name")

  result = raceEditor.start(nil)
  assertFalse(result, "start fails with nil name")

  -- Start with valid name should succeed
  result = raceEditor.start("test_race_123")
  assertTrue(result, "start succeeds with valid name")

  -- Starting again should fail (already active)
  result = raceEditor.start("another_race")
  assertFalse(result, "start fails when already active")

  -- Clean up
  raceEditor.cancel()
end

---------------------------------------------------------------------------
-- Run All Tests
---------------------------------------------------------------------------

function M.runAll()
  resetTestState()

  log("I", "")
  log("I", "========================================")
  log("I", "  STREET RACING UNIT TESTS")
  log("I", "========================================")
  log("I", "")

  -- Street Racing Tests
  testModuleLoaded()
  testRaceStates()
  testEncounterStates()
  testGetRacesForUI()
  testGetActiveEncounter()
  testIsNearAdversary()
  testGetDistanceToAdversary()
  testGetStats()
  testGetLostVehicles()
  testGenerateRandomRace()
  testNavigationFunctions()

  -- Race Editor Tests
  testRaceEditorModuleLoaded()
  testRaceEditorInactiveState()
  testRaceEditorStartCommand()

  -- Summary
  log("I", "")
  log("I", "========================================")
  log("I", "  TEST RESULTS")
  log("I", "========================================")
  log("I", string.format("  Passed: %d", testsPassed))
  log("I", string.format("  Failed: %d", testsFailed))
  log("I", string.format("  Total:  %d", testsPassed + testsFailed))
  log("I", "========================================")
  log("I", "")

  if testsFailed == 0 then
    log("I", "ALL TESTS PASSED!")
  else
    log("E", "SOME TESTS FAILED!")
    log("E", "Failed tests:")
    for _, result in ipairs(testResults) do
      if not result.passed then
        log("E", "  - " .. result.name)
      end
    end
  end

  -- Show toast notification
  guihooks.trigger('toastrMsg', {
    type = testsFailed == 0 and "success" or "error",
    title = "Unit Tests Complete",
    msg = string.format("%d passed, %d failed", testsPassed, testsFailed)
  })

  return {
    passed = testsPassed,
    failed = testsFailed,
    results = testResults
  }
end

-- Run specific test suite
function M.runStreetRacingTests()
  resetTestState()

  testModuleLoaded()
  testRaceStates()
  testEncounterStates()
  testGetRacesForUI()
  testGetActiveEncounter()
  testIsNearAdversary()
  testGetDistanceToAdversary()
  testGetStats()
  testGetLostVehicles()
  testGenerateRandomRace()
  testNavigationFunctions()

  return {passed = testsPassed, failed = testsFailed}
end

function M.runRaceEditorTests()
  resetTestState()

  testRaceEditorModuleLoaded()
  testRaceEditorInactiveState()
  testRaceEditorStartCommand()

  return {passed = testsPassed, failed = testsFailed}
end

-- Extension hooks
local function onExtensionLoaded()
  log("I", "Street Racing Tests extension loaded")
  log("I", "Run tests with: extensions.carTheft_streetRacingTests.runAll()")
end

M.onExtensionLoaded = onExtensionLoaded

return M
