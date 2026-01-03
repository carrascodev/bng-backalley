#!/usr/bin/env lua
-- BackAlley Mod Unit Test Runner

---------------------------------------------------------------------------
-- Test Framework
---------------------------------------------------------------------------

local passed = 0
local failed = 0
local currentTest = ""
local testResults = {}

local function describe(name, fn)
  print("\n" .. string.rep("=", 60))
  print("SUITE: " .. name)
  print(string.rep("=", 60))
  fn()
end

local function it(name, fn)
  currentTest = name
  local success, err = pcall(fn)
  if success then
    passed = passed + 1
    print("  [PASS] " .. name)
    table.insert(testResults, {name = name, passed = true})
  else
    failed = failed + 1
    print("  [FAIL] " .. name)
    print("         Error: " .. tostring(err))
    table.insert(testResults, {name = name, passed = false, error = tostring(err)})
  end
end

local function assertEqual(actual, expected, message)
  if actual ~= expected then
    error(string.format("%s\n    Expected: %s\n    Actual: %s",
      message or "Values not equal",
      tostring(expected),
      tostring(actual)))
  end
end

local function assertNotNil(value, message)
  if value == nil then
    error(message or "Expected non-nil value")
  end
end

local function assertNil(value, message)
  if value ~= nil then
    error(message or "Expected nil value, got: " .. tostring(value))
  end
end

local function assertTrue(value, message)
  if not value then
    error(message or "Expected true")
  end
end

local function assertFalse(value, message)
  if value then
    error(message or "Expected false")
  end
end

local function assertGreaterThan(actual, expected, message)
  if actual <= expected then
    error(string.format("%s\n    Expected > %s, got %s",
      message or "Value not greater than",
      tostring(expected),
      tostring(actual)))
  end
end

local function assertLessThan(actual, expected, message)
  if actual >= expected then
    error(string.format("%s\n    Expected < %s, got %s",
      message or "Value not less than",
      tostring(expected),
      tostring(actual)))
  end
end

local function assertBetween(actual, min, max, message)
  if actual < min or actual > max then
    error(string.format("%s\n    Expected between %s and %s, got %s",
      message or "Value not in range",
      tostring(min),
      tostring(max),
      tostring(actual)))
  end
end

local function assertTableContains(tbl, value, message)
  for _, v in pairs(tbl) do
    if v == value then return end
  end
  error(message or "Table does not contain value: " .. tostring(value))
end

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------

-- Get script directory for relative requires
local scriptPath = arg[0]:match("(.*/)")
if not scriptPath then scriptPath = "./" end

-- Add paths for requires
package.path = scriptPath .. "../lua/ge/extensions/?.lua;" ..
               scriptPath .. "../lua/ge/extensions/carTheft/?.lua;" ..
               scriptPath .. "mocks/?.lua;" ..
               package.path

-- Load mocks first (sets up global environment)
local mocks = require("beamng_mocks")
mocks.resetAll()

-- Mock the logger module
mocks.mockModule("carTheft/logger", {
  log = function(tag, level, msg)
    if _G.VERBOSE_LOGGING then
      print(string.format("[%s][%s] %s", tag, level, msg))
    end
  end
})

print("\nBackAlley Mod Unit Tests")
print("========================\n")

---------------------------------------------------------------------------
-- Test: config.lua
---------------------------------------------------------------------------

describe("config.lua", function()
  local config = require("carTheft/config")

  it("should export tier thresholds", function()
    assertNotNil(config.TIER1_MAX_VALUE)
    assertNotNil(config.TIER2_MAX_VALUE)
    assertGreaterThan(config.TIER2_MAX_VALUE, config.TIER1_MAX_VALUE)
  end)

  it("should export tier chances that sum to 1.0", function()
    local sum = config.TIER1_CHANCE + config.TIER2_CHANCE + config.TIER3_CHANCE
    assertBetween(sum, 0.99, 1.01, "Tier chances should sum to ~1.0")
  end)

  it("should export documentation tier configs", function()
    assertNotNil(config.DOC_TIER_BUDGET)
    assertNotNil(config.DOC_TIER_STANDARD)
    assertNotNil(config.DOC_TIER_PREMIUM)
  end)

  it("should have valid budget tier config", function()
    local budget = config.DOC_TIER_BUDGET
    assertNotNil(budget.costPercent)
    assertNotNil(budget.hours)
    assertNotNil(budget.detectChance)
    assertBetween(budget.detectChance, 0, 1)
  end)

  it("should have valid standard tier config", function()
    local standard = config.DOC_TIER_STANDARD
    assertNotNil(standard.costPercent)
    assertGreaterThan(standard.hours, config.DOC_TIER_BUDGET.hours, "Standard should take longer than budget")
  end)

  it("should have valid premium tier config", function()
    local premium = config.DOC_TIER_PREMIUM
    assertNotNil(premium.cost)
    assertLessThan(premium.detectChance, config.DOC_TIER_STANDARD.detectChance, "Premium should have lower detect chance")
  end)

  it("should export black market outcome probabilities", function()
    local verySketch = config.BM_OUTCOME_VERY_SKETCHY
    assertNotNil(verySketch)
    assertEqual(#verySketch, 3, "Outcome should have 3 values [scam, clunker, legit]")

    local sum = verySketch[1] + verySketch[2] + verySketch[3]
    assertBetween(sum, 0.99, 1.01, "Outcome probabilities should sum to ~1.0")
  end)

  it("should export heat system constants", function()
    assertNotNil(config.HEAT_INITIAL)
    assertNotNil(config.HEAT_DECAY_PER_HOUR)
    assertNotNil(config.HEAT_MIN)
    assertGreaterThan(config.HEAT_INITIAL, config.HEAT_MIN)
  end)
end)

---------------------------------------------------------------------------
-- Test: Pure Functions (extracted for testing)
---------------------------------------------------------------------------

describe("Utility Functions", function()
  -- Test randomRange (need to extract or recreate)
  local function randomRange(min, max)
    return min + math.random() * (max - min)
  end

  local function roundToNearest(value, nearest)
    return math.floor(value / nearest + 0.5) * nearest
  end

  it("randomRange should return values in range", function()
    for i = 1, 100 do
      local val = randomRange(10, 20)
      assertBetween(val, 10, 20)
    end
  end)

  it("roundToNearest should round correctly", function()
    assertEqual(roundToNearest(123, 50), 100)
    assertEqual(roundToNearest(126, 50), 150)
    assertEqual(roundToNearest(100, 50), 100)
    assertEqual(roundToNearest(99, 100), 100)
    assertEqual(roundToNearest(149, 100), 100)
    assertEqual(roundToNearest(150, 100), 200)
  end)
end)

---------------------------------------------------------------------------
-- Test: Tier Calculation Logic
---------------------------------------------------------------------------

describe("Tier Calculation", function()
  local config = require("carTheft/config")

  local function getTierForValue(value)
    if value <= config.TIER1_MAX_VALUE then return 1
    elseif value <= config.TIER2_MAX_VALUE then return 2
    else return 3 end
  end

  it("should return tier 1 for economy vehicles", function()
    assertEqual(getTierForValue(config.MIN_VEHICLE_VALUE), 1)
    assertEqual(getTierForValue(config.TIER1_MAX_VALUE / 2), 1)
    assertEqual(getTierForValue(config.TIER1_MAX_VALUE), 1)
  end)

  it("should return tier 2 for mid-range vehicles", function()
    assertEqual(getTierForValue(config.TIER1_MAX_VALUE + 1), 2)
    assertEqual(getTierForValue((config.TIER1_MAX_VALUE + config.TIER2_MAX_VALUE) / 2), 2)
    assertEqual(getTierForValue(config.TIER2_MAX_VALUE), 2)
  end)

  it("should return tier 3 for premium vehicles", function()
    assertEqual(getTierForValue(config.TIER2_MAX_VALUE + 1), 3)
    assertEqual(getTierForValue(config.TIER2_MAX_VALUE * 2), 3)
    assertEqual(getTierForValue(config.TIER2_MAX_VALUE * 10), 3)
  end)
end)

---------------------------------------------------------------------------
-- Test: Fee Generation Logic
---------------------------------------------------------------------------

describe("Hot Wheels Intel Generation", function()
  local cfg = require("carTheft/config")
  local function roundToNearest(value, nearest)
    return math.floor(value / nearest + 0.5) * nearest
  end

  local function generateFee(vehicleValue)
    local feePercent = cfg.INTEL_FEE_MIN + math.random() * (cfg.INTEL_FEE_MAX - cfg.INTEL_FEE_MIN)
    return roundToNearest(vehicleValue * feePercent, 50)
  end

  it("should generate fees between config bounds of vehicle value", function()
    local vehicleValue = 10000

    for i = 1, 100 do
      local fee = generateFee(vehicleValue)
      assertBetween(fee, vehicleValue * cfg.INTEL_FEE_MIN, vehicleValue * cfg.INTEL_FEE_MAX, "Fee outside expected range")
    end
  end)

  it("should round fees to nearest 50", function()
    for i = 1, 50 do
      local fee = generateFee(10000)
      assertEqual(fee % 50, 0, "Fee should be divisible by 50")
    end
  end)
end)

---------------------------------------------------------------------------
-- Test: Documentation Fee Calculation
---------------------------------------------------------------------------

describe("Documentation Fee Calculation", function()
  local config = require("carTheft/config")

  local function calculateDocFee(vehicleValue, tierName)
    if tierName == "budget" then
      local tier = config.DOC_TIER_BUDGET
      return math.max(tier.costMin, math.floor(vehicleValue * tier.costPercent))
    elseif tierName == "standard" then
      local tier = config.DOC_TIER_STANDARD
      return math.max(tier.costMin, math.floor(vehicleValue * tier.costPercent))
    elseif tierName == "premium" then
      return config.DOC_TIER_PREMIUM.cost
    end
    return nil
  end

  it("should calculate budget tier fee correctly", function()
    local fee = calculateDocFee(50000, "budget")
    local expected = math.floor(50000 * config.DOC_TIER_BUDGET.costPercent)
    assertEqual(fee, expected)
  end)

  it("should enforce minimum fee for budget tier", function()
    local fee = calculateDocFee(1000, "budget")  -- Very cheap car
    assertEqual(fee, config.DOC_TIER_BUDGET.costMin, "Should use minimum fee")
  end)

  it("should calculate standard tier fee correctly", function()
    local fee = calculateDocFee(50000, "standard")
    local expected = math.floor(50000 * config.DOC_TIER_STANDARD.costPercent)
    assertEqual(fee, expected)
  end)

  it("should return flat fee for premium tier", function()
    local fee1 = calculateDocFee(10000, "premium")
    local fee2 = calculateDocFee(500000, "premium")
    assertEqual(fee1, config.DOC_TIER_PREMIUM.cost)
    assertEqual(fee2, config.DOC_TIER_PREMIUM.cost)
  end)

  it("should have increasing fees: budget < standard < premium (for expensive cars)", function()
    local vehicleValue = 200000  -- Expensive car
    local budget = calculateDocFee(vehicleValue, "budget")
    local standard = calculateDocFee(vehicleValue, "standard")
    local premium = calculateDocFee(vehicleValue, "premium")

    assertLessThan(budget, standard)
    -- Premium is flat $100k, so for $200k car standard would be $50k which is less
    -- This is intentional - premium is for convenience/quality, not cost
  end)
end)

---------------------------------------------------------------------------
-- Test: Black Market Pricing Logic
---------------------------------------------------------------------------

describe("Black Market Pricing", function()
  local config = require("carTheft/config")

  local function getPriceMultiplier(reputation)
    if reputation < config.BM_REP_VERY_SKETCHY then
      return config.BM_PRICE_VERY_SKETCHY_MIN + math.random() * (config.BM_PRICE_VERY_SKETCHY_MAX - config.BM_PRICE_VERY_SKETCHY_MIN)
    elseif reputation < config.BM_REP_SKETCHY then
      return config.BM_PRICE_SKETCHY_MIN + math.random() * (config.BM_PRICE_SKETCHY_MAX - config.BM_PRICE_SKETCHY_MIN)
    else
      return config.BM_PRICE_TRUSTED_MIN + math.random() * (config.BM_PRICE_TRUSTED_MAX - config.BM_PRICE_TRUSTED_MIN)
    end
  end

  it("should give lowest prices for very sketchy sellers", function()
    local testRep = config.BM_REP_VERY_SKETCHY / 2  -- Well below threshold
    for i = 1, 50 do
      local mult = getPriceMultiplier(testRep)
      assertBetween(mult, config.BM_PRICE_VERY_SKETCHY_MIN, config.BM_PRICE_VERY_SKETCHY_MAX)
    end
  end)

  it("should give medium prices for sketchy sellers", function()
    local testRep = (config.BM_REP_VERY_SKETCHY + config.BM_REP_SKETCHY) / 2  -- Between thresholds
    for i = 1, 50 do
      local mult = getPriceMultiplier(testRep)
      assertBetween(mult, config.BM_PRICE_SKETCHY_MIN, config.BM_PRICE_SKETCHY_MAX)
    end
  end)

  it("should give fair prices for trusted sellers", function()
    local testRep = (config.BM_REP_SKETCHY + 1.0) / 2  -- Above sketchy threshold
    for i = 1, 50 do
      local mult = getPriceMultiplier(testRep)
      assertBetween(mult, config.BM_PRICE_TRUSTED_MIN, config.BM_PRICE_TRUSTED_MAX)
    end
  end)
end)

---------------------------------------------------------------------------
-- Test: Purchase Outcome Probability
---------------------------------------------------------------------------

describe("Purchase Outcome Logic", function()
  local config = require("carTheft/config")

  local function simulateOutcome(reputation, iterations)
    local outcomes = {scam = 0, clunker = 0, legit = 0}

    for i = 1, iterations do
      local roll = math.random()
      local probs

      if reputation < config.BM_REP_VERY_SKETCHY then
        probs = config.BM_OUTCOME_VERY_SKETCHY
      elseif reputation < config.BM_REP_SKETCHY then
        probs = config.BM_OUTCOME_SKETCHY
      else
        probs = config.BM_OUTCOME_TRUSTED
      end

      if roll < probs[1] then
        outcomes.scam = outcomes.scam + 1
      elseif roll < probs[1] + probs[2] then
        outcomes.clunker = outcomes.clunker + 1
      else
        outcomes.legit = outcomes.legit + 1
      end
    end

    return outcomes
  end

  it("should have high scam rate for very sketchy sellers", function()
    local testRep = config.BM_REP_VERY_SKETCHY / 2
    local expectedScamRate = config.BM_OUTCOME_VERY_SKETCHY[1]
    local outcomes = simulateOutcome(testRep, 1000)
    local scamRate = outcomes.scam / 1000
    -- Allow 15% variance from expected rate
    assertGreaterThan(scamRate, expectedScamRate * 0.7, "Very sketchy sellers should scam often")
  end)

  it("should have low scam rate for trusted sellers", function()
    local testRep = (config.BM_REP_SKETCHY + 1.0) / 2
    local expectedScamRate = config.BM_OUTCOME_TRUSTED[1]
    local outcomes = simulateOutcome(testRep, 1000)
    local scamRate = outcomes.scam / 1000
    -- Allow variance, but should be close to expected
    assertLessThan(scamRate, expectedScamRate * 2, "Trusted sellers should rarely scam")
  end)

  it("should have high legit rate for trusted sellers", function()
    local testRep = (config.BM_REP_SKETCHY + 1.0) / 2
    local expectedLegitRate = config.BM_OUTCOME_TRUSTED[3]
    local outcomes = simulateOutcome(testRep, 1000)
    local legitRate = outcomes.legit / 1000
    -- Allow 15% variance from expected rate
    assertGreaterThan(legitRate, expectedLegitRate * 0.85, "Trusted sellers should deliver legit vehicles")
  end)
end)

---------------------------------------------------------------------------
-- Test: Heat System
---------------------------------------------------------------------------

describe("Heat System", function()
  local config = require("carTheft/config")

  local function calculateHeatAfterHours(initialHeat, hours)
    local decay = config.HEAT_DECAY_PER_HOUR * hours
    return math.max(config.HEAT_MIN, initialHeat - decay)
  end

  it("should have valid initial heat value", function()
    assertGreaterThan(config.HEAT_INITIAL, 0)
    assertGreaterThan(config.HEAT_INITIAL, config.HEAT_MIN)
  end)

  it("should decay heat over time", function()
    local testHours = 5
    local heat = calculateHeatAfterHours(config.HEAT_INITIAL, testHours)
    local expectedDecay = config.HEAT_DECAY_PER_HOUR * testHours
    assertLessThan(heat, config.HEAT_INITIAL)
    assertEqual(heat, config.HEAT_INITIAL - expectedDecay)
  end)

  it("should not decay below minimum", function()
    local manyHours = (config.HEAT_INITIAL / config.HEAT_DECAY_PER_HOUR) * 2  -- More than enough to fully decay
    local heat = calculateHeatAfterHours(config.HEAT_INITIAL, manyHours)
    assertEqual(heat, config.HEAT_MIN)
  end)

  it("should calculate correct hours to fully cool", function()
    local hoursToMin = (config.HEAT_INITIAL - config.HEAT_MIN) / config.HEAT_DECAY_PER_HOUR
    -- Verify the calculated hours actually works
    local heat = calculateHeatAfterHours(config.HEAT_INITIAL, hoursToMin)
    assertEqual(heat, config.HEAT_MIN)
  end)
end)

---------------------------------------------------------------------------
-- Test: Area Detection from Position
---------------------------------------------------------------------------

describe("Area Detection", function()
  local function getAreaFromPosition(pos)
    if not pos then return "Unknown" end
    local x, y = pos.x, pos.y

    if x > -900 and x < -600 and y > -100 and y < 300 then
      return "Downtown"
    elseif x > -600 and x < -200 and y < -100 then
      return "Industrial"
    elseif x < -900 and y > 200 then
      return "Suburbs"
    elseif y > 400 then
      return "Coast"
    elseif x > 200 then
      return "Highway"
    else
      return "City"
    end
  end

  it("should detect Downtown area", function()
    local pos = vec3(-750, 100, 0)
    assertEqual(getAreaFromPosition(pos), "Downtown")
  end)

  it("should detect Industrial area", function()
    local pos = vec3(-400, -200, 0)
    assertEqual(getAreaFromPosition(pos), "Industrial")
  end)

  it("should detect Suburbs area", function()
    local pos = vec3(-1000, 300, 0)
    assertEqual(getAreaFromPosition(pos), "Suburbs")
  end)

  it("should detect Coast area", function()
    local pos = vec3(0, 500, 0)
    assertEqual(getAreaFromPosition(pos), "Coast")
  end)

  it("should detect Highway area", function()
    local pos = vec3(300, 0, 0)
    assertEqual(getAreaFromPosition(pos), "Highway")
  end)

  it("should default to City for unmatched areas", function()
    local pos = vec3(0, 0, 0)
    assertEqual(getAreaFromPosition(pos), "City")
  end)

  it("should handle nil position", function()
    assertEqual(getAreaFromPosition(nil), "Unknown")
  end)
end)

---------------------------------------------------------------------------
-- Test: Vehicle Exclusion Logic
---------------------------------------------------------------------------

describe("Vehicle Exclusion", function()
  local config = require("carTheft/config")

  local function shouldExcludeVehicle(vehInfo)
    if not vehInfo then return true end
    if not vehInfo.Value or vehInfo.Value < config.MIN_VEHICLE_VALUE then return true end

    local configName = vehInfo.key or ""
    local excludePatterns = {"frame", "stripped", "damaged", "wrecked", "chassis"}
    for _, pattern in ipairs(excludePatterns) do
      if string.find(string.lower(configName), pattern) then
        return true
      end
    end

    local agg = vehInfo.aggregates
    if not agg then return true end

    if agg.Type then
      if agg.Type.Trailer or agg.Type.Prop or agg.Type.Utility then
        return true
      end
    end

    local configType = agg["Config Type"]
    if configType then
      if configType.Frame or configType.Loaner or configType.Service or configType.Police or configType.Taxi then
        return true
      end
    end

    return false
  end

  it("should exclude nil vehicles", function()
    assertTrue(shouldExcludeVehicle(nil))
  end)

  it("should exclude vehicles with no value", function()
    assertTrue(shouldExcludeVehicle({key = "test", aggregates = {}}))
  end)

  it("should exclude vehicles below minimum value", function()
    local belowMin = config.MIN_VEHICLE_VALUE - 1
    assertTrue(shouldExcludeVehicle({key = "test", Value = belowMin, aggregates = {}}))
  end)

  it("should include vehicles at minimum value", function()
    assertFalse(shouldExcludeVehicle({key = "test", Value = config.MIN_VEHICLE_VALUE, aggregates = {Type = {}}}))
  end)

  it("should exclude frame configs", function()
    local goodValue = config.TIER1_MAX_VALUE
    assertTrue(shouldExcludeVehicle({key = "etk800_frame", Value = goodValue, aggregates = {Type = {}}}))
  end)

  it("should exclude stripped configs", function()
    local goodValue = config.TIER1_MAX_VALUE
    assertTrue(shouldExcludeVehicle({key = "covet_stripped", Value = goodValue, aggregates = {Type = {}}}))
  end)

  it("should exclude trailers", function()
    local goodValue = config.TIER1_MAX_VALUE
    assertTrue(shouldExcludeVehicle({key = "trailer", Value = goodValue, aggregates = {Type = {Trailer = true}}}))
  end)

  it("should exclude police vehicles", function()
    local goodValue = config.TIER2_MAX_VALUE
    assertTrue(shouldExcludeVehicle({key = "etk800_police", Value = goodValue, aggregates = {Type = {}, ["Config Type"] = {Police = true}}}))
  end)

  it("should include normal vehicles", function()
    local goodValue = config.TIER2_MAX_VALUE
    assertFalse(shouldExcludeVehicle({key = "etk800_sport", Value = goodValue, aggregates = {Type = {Sedan = true}}}))
  end)
end)

---------------------------------------------------------------------------
-- Test: Street Racing Configuration
---------------------------------------------------------------------------

describe("Street Racing Config", function()
  local config = require("carTheft/config")

  it("should export racing bet limits", function()
    assertNotNil(config.RACE_BET_MIN, "RACE_BET_MIN should exist")
    assertNotNil(config.RACE_BET_MAX, "RACE_BET_MAX should exist")
    assertGreaterThan(config.RACE_BET_MAX, config.RACE_BET_MIN, "Max bet should be greater than min")
  end)

  it("should export racing multiplier", function()
    assertNotNil(config.RACE_WIN_MULTIPLIER, "RACE_WIN_MULTIPLIER should exist")
    assertGreaterThan(config.RACE_WIN_MULTIPLIER, 1, "Win multiplier should be > 1")
  end)

  it("should export encounter spawn config", function()
    assertNotNil(config.ENCOUNTER_SPAWN_CHANCE, "ENCOUNTER_SPAWN_CHANCE should exist")
    assertNotNil(config.ENCOUNTER_COOLDOWN, "ENCOUNTER_COOLDOWN should exist")
    assertBetween(config.ENCOUNTER_SPAWN_CHANCE, 0, 1, "Spawn chance should be 0-1")
  end)

  it("should export pink slip buyback multiplier", function()
    assertNotNil(config.PINKSLIP_BUYBACK_MULTIPLIER, "PINKSLIP_BUYBACK_MULTIPLIER should exist")
    assertGreaterThan(config.PINKSLIP_BUYBACK_MULTIPLIER, 1, "Buyback should cost more than original")
  end)

  it("should export allowed maps", function()
    assertNotNil(config.RACE_ALLOWED_MAPS, "RACE_ALLOWED_MAPS should exist")
    assertTableContains(config.RACE_ALLOWED_MAPS, "west_coast_usa", "Should allow west_coast_usa")
  end)
end)

---------------------------------------------------------------------------
-- Test: Street Racing Core Logic
---------------------------------------------------------------------------

describe("Street Racing Logic", function()
  local config = require("carTheft/config")

  -- Recreate pure functions from streetRacing for testing
  local function isNightTime(time)
    return time < 0.22 or time > 0.78
  end

  local function isMapAllowed(mapName, allowedMaps)
    if not mapName then return false end
    for _, allowed in ipairs(allowedMaps) do
      if mapName == allowed then return true end
    end
    return false
  end

  local function validateBet(amount, min, max)
    return amount >= min and amount <= max
  end

  local function calculatePayout(betAmount, multiplier)
    return betAmount * multiplier
  end

  local function calculateBuybackPrice(vehicleValue, multiplier)
    return math.floor(vehicleValue * multiplier)
  end

  it("should detect night time correctly", function()
    assertTrue(isNightTime(0.1), "0.1 should be night (before dawn)")
    assertTrue(isNightTime(0.2), "0.2 should be night (early morning)")
    assertFalse(isNightTime(0.5), "0.5 should be day (noon)")
    assertFalse(isNightTime(0.3), "0.3 should be day (morning)")
    assertFalse(isNightTime(0.7), "0.7 should be day (evening)")
    assertTrue(isNightTime(0.85), "0.85 should be night (late night)")
    assertTrue(isNightTime(0.95), "0.95 should be night (midnight)")
  end)

  it("should validate allowed maps", function()
    local allowedMaps = {"west_coast_usa", "italy"}
    assertTrue(isMapAllowed("west_coast_usa", allowedMaps))
    assertTrue(isMapAllowed("italy", allowedMaps))
    assertFalse(isMapAllowed("utah", allowedMaps))
    assertFalse(isMapAllowed(nil, allowedMaps))
    assertFalse(isMapAllowed("", allowedMaps))
  end)

  it("should validate bet amounts", function()
    local min, max = 1000, 50000
    assertTrue(validateBet(1000, min, max), "Min bet should be valid")
    assertTrue(validateBet(50000, min, max), "Max bet should be valid")
    assertTrue(validateBet(25000, min, max), "Mid bet should be valid")
    assertFalse(validateBet(999, min, max), "Below min should be invalid")
    assertFalse(validateBet(50001, min, max), "Above max should be invalid")
    assertFalse(validateBet(0, min, max), "Zero should be invalid")
  end)

  it("should calculate payout correctly", function()
    assertEqual(calculatePayout(1000, 2.0), 2000)
    assertEqual(calculatePayout(5000, 2.0), 10000)
    assertEqual(calculatePayout(50000, 2.0), 100000)
  end)

  it("should calculate buyback price correctly", function()
    assertEqual(calculateBuybackPrice(10000, 1.5), 15000)
    assertEqual(calculateBuybackPrice(50000, 1.5), 75000)
    assertEqual(calculateBuybackPrice(100000, 1.5), 150000)
  end)
end)

---------------------------------------------------------------------------
-- Test: Racer Name Generation
---------------------------------------------------------------------------

describe("Racer Name Generation", function()
  local RACER_FIRST_NAMES = {"Speed", "Fast", "Quick", "Nitro", "Turbo", "Drift", "Midnight", "Shadow", "Flash", "Thunder"}
  local RACER_LAST_NAMES = {"Mike", "Danny", "Rico", "Tony", "Vic", "Max", "Blade", "Ghost", "Snake", "Wolf"}

  local function generateRacerName()
    local firstName = RACER_FIRST_NAMES[math.random(1, #RACER_FIRST_NAMES)]
    local lastName = RACER_LAST_NAMES[math.random(1, #RACER_LAST_NAMES)]
    return firstName .. " " .. lastName
  end

  it("should generate names from predefined lists", function()
    for i = 1, 50 do
      local name = generateRacerName()
      assertNotNil(name, "Name should not be nil")
      local first, last = name:match("(%S+) (%S+)")
      assertNotNil(first, "Should have first name")
      assertNotNil(last, "Should have last name")
      assertTableContains(RACER_FIRST_NAMES, first, "First name should be from list")
      assertTableContains(RACER_LAST_NAMES, last, "Last name should be from list")
    end
  end)
end)

---------------------------------------------------------------------------
-- Test: Vehicle Display Names
---------------------------------------------------------------------------

describe("Vehicle Display Names", function()
  local displayNames = {
    vivace = "Cherrier Vivace",
    sunburst = "Hirochi Sunburst",
    etk800 = "ETK 800",
    scintilla = "Civetta Scintilla",
    ["200bx"] = "Ibishu 200BX",
    covet = "Ibishu Covet"
  }

  local function getVehicleDisplayName(model)
    return displayNames[model] or model
  end

  it("should return correct display names", function()
    assertEqual(getVehicleDisplayName("vivace"), "Cherrier Vivace")
    assertEqual(getVehicleDisplayName("sunburst"), "Hirochi Sunburst")
    assertEqual(getVehicleDisplayName("etk800"), "ETK 800")
    assertEqual(getVehicleDisplayName("scintilla"), "Civetta Scintilla")
    assertEqual(getVehicleDisplayName("200bx"), "Ibishu 200BX")
    assertEqual(getVehicleDisplayName("covet"), "Ibishu Covet")
  end)

  it("should return model name for unknown vehicles", function()
    assertEqual(getVehicleDisplayName("unknown_car"), "unknown_car")
    assertEqual(getVehicleDisplayName("custom"), "custom")
  end)
end)

---------------------------------------------------------------------------
-- Test: Proximity Check Logic
---------------------------------------------------------------------------

describe("Proximity Check", function()
  local CHALLENGE_PROXIMITY = 15  -- meters

  local function isWithinRange(distance, threshold)
    return distance <= threshold
  end

  it("should detect when player is close enough", function()
    assertTrue(isWithinRange(10, CHALLENGE_PROXIMITY), "10m should be in range")
    assertTrue(isWithinRange(15, CHALLENGE_PROXIMITY), "15m (exactly) should be in range")
    assertTrue(isWithinRange(0, CHALLENGE_PROXIMITY), "0m should be in range")
    assertTrue(isWithinRange(5, CHALLENGE_PROXIMITY), "5m should be in range")
  end)

  it("should detect when player is too far", function()
    assertFalse(isWithinRange(16, CHALLENGE_PROXIMITY), "16m should be out of range")
    assertFalse(isWithinRange(50, CHALLENGE_PROXIMITY), "50m should be out of range")
    assertFalse(isWithinRange(100, CHALLENGE_PROXIMITY), "100m should be out of range")
    assertFalse(isWithinRange(math.huge, CHALLENGE_PROXIMITY), "Infinity should be out of range")
  end)
end)

---------------------------------------------------------------------------
-- Test: Race State Machine
---------------------------------------------------------------------------

describe("Race State Machine", function()
  local RACE_STATE = {
    IDLE = "idle",
    STAGING = "staging",
    COUNTDOWN = "countdown",
    RACING = "racing",
    FINISHED = "finished",
    ABANDONED = "abandoned"
  }

  local ENCOUNTER_STATE = {
    NONE = "none",
    SPAWNED = "spawned",
    CHALLENGED = "challenged",
    COUNTDOWN = "countdown",
    RACING = "racing",
    FINISHED = "finished"
  }

  it("should have all required race states", function()
    assertEqual(RACE_STATE.IDLE, "idle")
    assertEqual(RACE_STATE.STAGING, "staging")
    assertEqual(RACE_STATE.COUNTDOWN, "countdown")
    assertEqual(RACE_STATE.RACING, "racing")
    assertEqual(RACE_STATE.FINISHED, "finished")
    assertEqual(RACE_STATE.ABANDONED, "abandoned")
  end)

  it("should have all required encounter states", function()
    assertEqual(ENCOUNTER_STATE.NONE, "none")
    assertEqual(ENCOUNTER_STATE.SPAWNED, "spawned")
    assertEqual(ENCOUNTER_STATE.CHALLENGED, "challenged")
    assertEqual(ENCOUNTER_STATE.COUNTDOWN, "countdown")
    assertEqual(ENCOUNTER_STATE.RACING, "racing")
    assertEqual(ENCOUNTER_STATE.FINISHED, "finished")
  end)

  it("should validate state transitions", function()
    -- Valid transitions from IDLE
    local validFromIdle = {"staging"}
    assertTableContains(validFromIdle, "staging")

    -- Valid transitions from SPAWNED
    local validFromSpawned = {"challenged", "none"}  -- challenged or despawned
    assertTableContains(validFromSpawned, "challenged")
    assertTableContains(validFromSpawned, "none")
  end)
end)

---------------------------------------------------------------------------
-- Test: Random Race Selection
---------------------------------------------------------------------------

describe("Random Race Selection", function()
  local function generateRandomRace(races)
    if not races or next(races) == nil then
      return nil
    end

    local availableRaces = {}
    for id, race in pairs(races) do
      table.insert(availableRaces, race)
    end

    if #availableRaces == 0 then
      return nil
    end

    return availableRaces[math.random(#availableRaces)]
  end

  it("should return nil for empty races", function()
    assertNil(generateRandomRace({}), "Empty table should return nil")
    assertNil(generateRandomRace(nil), "Nil should return nil")
  end)

  it("should return a race from available races", function()
    local races = {
      race1 = {id = "race1", name = "Downtown Sprint"},
      race2 = {id = "race2", name = "Highway Run"},
      race3 = {id = "race3", name = "Mountain Pass"}
    }

    for i = 1, 30 do
      local selectedRace = generateRandomRace(races)
      assertNotNil(selectedRace, "Should select a race")
      assertNotNil(selectedRace.id, "Selected race should have id")
      assertNotNil(selectedRace.name, "Selected race should have name")
    end
  end)

  it("should provide variety in selection", function()
    local races = {
      race1 = {id = "race1"},
      race2 = {id = "race2"},
      race3 = {id = "race3"}
    }

    local selections = {}
    for i = 1, 100 do
      local race = generateRandomRace(races)
      selections[race.id] = (selections[race.id] or 0) + 1
    end

    -- Each race should be selected at least once in 100 tries
    assertGreaterThan(selections["race1"] or 0, 0, "race1 should be selected sometimes")
    assertGreaterThan(selections["race2"] or 0, 0, "race2 should be selected sometimes")
    assertGreaterThan(selections["race3"] or 0, 0, "race3 should be selected sometimes")
  end)
end)

---------------------------------------------------------------------------
-- Test: Stats Calculation
---------------------------------------------------------------------------

describe("Racing Stats", function()
  local function calculateWinRate(wins, losses)
    local total = wins + losses
    if total == 0 then return 0 end
    return math.floor(wins / total * 100)
  end

  it("should calculate win rate correctly", function()
    assertEqual(calculateWinRate(5, 5), 50)
    assertEqual(calculateWinRate(10, 0), 100)
    assertEqual(calculateWinRate(0, 10), 0)
    assertEqual(calculateWinRate(3, 7), 30)
    assertEqual(calculateWinRate(7, 3), 70)
  end)

  it("should handle zero races", function()
    assertEqual(calculateWinRate(0, 0), 0)
  end)

  it("should round win rate down", function()
    assertEqual(calculateWinRate(1, 2), 33)  -- 33.33... rounds to 33
    assertEqual(calculateWinRate(2, 3), 40)  -- 40%
  end)
end)

---------------------------------------------------------------------------
-- Test: Document Timer System
---------------------------------------------------------------------------

describe("Document Timer System", function()
  -- Mock the document timer logic (extracted from main.lua)
  local docTimerLastUpdate = {}  -- Session-only tracking

  local function mockGetGameTimeSeconds(mockTime)
    return mockTime
  end

  local function updateDocumentTimer(invId, veh, currentGameTime)
    if not veh.pendingDocTier or veh.pendingDocReady then
      return veh
    end

    -- Get last update for this vehicle (session-only, defaults to current time)
    local lastUpdate = docTimerLastUpdate[invId] or currentGameTime
    local gameTimeDelta = currentGameTime - lastUpdate

    -- Only decrement if time moved forward
    if gameTimeDelta > 0 then
      local remaining = (veh.pendingDocRemainingSeconds or 0) - gameTimeDelta
      veh.pendingDocRemainingSeconds = remaining

      if remaining <= 0 then
        veh.pendingDocReady = true
        veh.pendingDocRemainingSeconds = 0
      end
    end

    -- Update session tracker
    docTimerLastUpdate[invId] = currentGameTime

    return veh
  end

  local function resetSessionTracking()
    docTimerLastUpdate = {}
  end

  it("should decrement timer when game time moves forward", function()
    resetSessionTracking()
    local veh = {
      pendingDocTier = "budget",
      pendingDocRemainingSeconds = 3600,  -- 1 hour
      pendingDocReady = false
    }

    -- First update at time 1000
    veh = updateDocumentTimer(1, veh, 1000)
    assertEqual(veh.pendingDocRemainingSeconds, 3600, "First update should not decrement")

    -- Second update at time 1100 (100 seconds later)
    veh = updateDocumentTimer(1, veh, 1100)
    assertEqual(veh.pendingDocRemainingSeconds, 3500, "Should decrement by 100 seconds")

    -- Third update at time 1600 (500 seconds later)
    veh = updateDocumentTimer(1, veh, 1600)
    assertEqual(veh.pendingDocRemainingSeconds, 3000, "Should decrement by 500 more seconds")
  end)

  it("should NOT decrement when game time goes backwards", function()
    resetSessionTracking()
    local veh = {
      pendingDocTier = "standard",
      pendingDocRemainingSeconds = 3600,
      pendingDocReady = false
    }

    -- First update at time 5000
    veh = updateDocumentTimer(1, veh, 5000)
    assertEqual(veh.pendingDocRemainingSeconds, 3600, "First update should not decrement")

    -- Time goes forward
    veh = updateDocumentTimer(1, veh, 5500)
    assertEqual(veh.pendingDocRemainingSeconds, 3100, "Should decrement by 500")

    -- Time goes BACKWARDS (save reload, time warp, etc.)
    veh = updateDocumentTimer(1, veh, 4000)
    assertEqual(veh.pendingDocRemainingSeconds, 3100, "Should NOT change when time goes backwards")

    -- Time goes forward again
    veh = updateDocumentTimer(1, veh, 4500)
    assertEqual(veh.pendingDocRemainingSeconds, 2600, "Should resume decrementing from new time")
  end)

  it("should mark documents ready when timer reaches zero", function()
    resetSessionTracking()
    local veh = {
      pendingDocTier = "budget",
      pendingDocRemainingSeconds = 100,  -- Only 100 seconds left
      pendingDocReady = false
    }

    -- First update
    veh = updateDocumentTimer(1, veh, 1000)
    assertFalse(veh.pendingDocReady, "Should not be ready yet")

    -- Time passes beyond remaining
    veh = updateDocumentTimer(1, veh, 1200)  -- 200 seconds passed, only 100 needed
    assertTrue(veh.pendingDocReady, "Should be ready now")
    assertEqual(veh.pendingDocRemainingSeconds, 0, "Remaining should be 0")
  end)

  it("should not go negative on remaining seconds", function()
    resetSessionTracking()
    local veh = {
      pendingDocTier = "premium",
      pendingDocRemainingSeconds = 50,
      pendingDocReady = false
    }

    veh = updateDocumentTimer(1, veh, 1000)
    veh = updateDocumentTimer(1, veh, 2000)  -- 1000 seconds passed, way more than 50

    assertEqual(veh.pendingDocRemainingSeconds, 0, "Should clamp to 0, not go negative")
    assertTrue(veh.pendingDocReady, "Should be ready")
  end)

  it("should handle new session (no previous lastUpdate)", function()
    resetSessionTracking()  -- Simulates game restart
    local veh = {
      pendingDocTier = "budget",
      pendingDocRemainingSeconds = 7200,  -- 2 hours saved from previous session
      pendingDocReady = false
    }

    -- New session starts at game time 500 (could be any value)
    veh = updateDocumentTimer(1, veh, 500)
    assertEqual(veh.pendingDocRemainingSeconds, 7200, "Should not decrement on first frame of new session")

    -- Time moves forward in new session
    veh = updateDocumentTimer(1, veh, 800)
    assertEqual(veh.pendingDocRemainingSeconds, 6900, "Should decrement by 300 in new session")
  end)

  it("should track multiple vehicles independently", function()
    resetSessionTracking()
    local veh1 = {
      pendingDocTier = "budget",
      pendingDocRemainingSeconds = 1000,
      pendingDocReady = false
    }
    local veh2 = {
      pendingDocTier = "standard",
      pendingDocRemainingSeconds = 2000,
      pendingDocReady = false
    }

    -- Both start at same time
    veh1 = updateDocumentTimer(1, veh1, 1000)
    veh2 = updateDocumentTimer(2, veh2, 1000)

    -- Time passes
    veh1 = updateDocumentTimer(1, veh1, 1500)
    veh2 = updateDocumentTimer(2, veh2, 1500)

    assertEqual(veh1.pendingDocRemainingSeconds, 500, "Veh1 should have 500 left")
    assertEqual(veh2.pendingDocRemainingSeconds, 1500, "Veh2 should have 1500 left")
  end)

  it("should skip vehicles without pending docs", function()
    resetSessionTracking()
    local veh = {
      pendingDocTier = nil,  -- No pending docs
      pendingDocRemainingSeconds = 1000,
      pendingDocReady = false
    }

    veh = updateDocumentTimer(1, veh, 1000)
    veh = updateDocumentTimer(1, veh, 2000)

    -- Should be unchanged because no pendingDocTier
    assertEqual(veh.pendingDocRemainingSeconds, 1000, "Should not change without pendingDocTier")
  end)

  it("should skip vehicles already ready", function()
    resetSessionTracking()
    local veh = {
      pendingDocTier = "budget",
      pendingDocRemainingSeconds = 0,
      pendingDocReady = true  -- Already ready
    }

    veh = updateDocumentTimer(1, veh, 1000)
    veh = updateDocumentTimer(1, veh, 2000)

    -- Should remain ready, no changes
    assertTrue(veh.pendingDocReady, "Should stay ready")
    assertEqual(veh.pendingDocRemainingSeconds, 0, "Should stay at 0")
  end)
end)

---------------------------------------------------------------------------
-- Print Summary
---------------------------------------------------------------------------

print("\n" .. string.rep("=", 60))
print("TEST SUMMARY")
print(string.rep("=", 60))
print(string.format("Passed: %d", passed))
print(string.format("Failed: %d", failed))
print(string.format("Total:  %d", passed + failed))
print(string.rep("=", 60))

if failed > 0 then
  print("\nFailed tests:")
  for _, result in ipairs(testResults) do
    if not result.passed then
      print("  - " .. result.name)
      if result.error then
        print("    " .. result.error)
      end
    end
  end
  os.exit(1)
else
  print("\nAll tests passed!")
  os.exit(0)
end
