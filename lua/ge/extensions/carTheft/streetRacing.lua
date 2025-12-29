-- Car Theft Career - Street Racing Extension
-- Handles organized races, street encounters, and betting

local M = {}

-- Logger module
local logger = require("carTheft/logger")
local LOG_TAG = "carTheft_streetRacing"

-- Dependencies
M.dependencies = {
  'gameplay_city',
  'career_career',
  'career_modules_playerAttributes'
}

-- Load configuration
local configLoaded, config = pcall(require, "ge/extensions/carTheft/config")
if not configLoaded then
  config = {}
end

-- Configuration defaults (will be moved to config.lua)
local RACE_CONFIG = {
  BET_MIN = config.RACE_BET_MIN or 1000,
  BET_MAX = config.RACE_BET_MAX or 50000,
  WIN_MULTIPLIER = config.RACE_WIN_MULTIPLIER or 2.0,
  ENCOUNTER_SPAWN_CHANCE = config.ENCOUNTER_SPAWN_CHANCE or 0.003,
  ENCOUNTER_SPAWN_RANGE_MIN = config.ENCOUNTER_SPAWN_RANGE_MIN or 100,
  ENCOUNTER_SPAWN_RANGE_MAX = config.ENCOUNTER_SPAWN_RANGE_MAX or 200,
  ENCOUNTER_COOLDOWN = config.ENCOUNTER_COOLDOWN or 600,
  ENCOUNTER_FINISH_DISTANCE = config.ENCOUNTER_FINISH_DISTANCE or 2000,
  ENCOUNTER_DESPAWN_DISTANCE = config.ENCOUNTER_DESPAWN_DISTANCE or 500,
  AI_SKILL_MIN = config.AI_SKILL_MIN or 0.70,
  AI_SKILL_MAX = config.AI_SKILL_MAX or 0.95,
  AI_AGGRESSION_MIN = config.AI_AGGRESSION_MIN or 0.5,
  AI_AGGRESSION_MAX = config.AI_AGGRESSION_MAX or 0.8,
  PINKSLIP_BUYBACK_MULTIPLIER = config.PINKSLIP_BUYBACK_MULTIPLIER or 1.5,
  COUNTDOWN_SECONDS = config.RACE_COUNTDOWN_SECONDS or 3,
  CHECKPOINT_WIDTH_DEFAULT = config.CHECKPOINT_WIDTH_DEFAULT or 12,
  ALLOWED_MAPS = config.RACE_ALLOWED_MAPS or {"west_coast_usa"}
}

-- AI racer vehicles
local RACER_VEHICLES = {"vivace", "sunburst", "etk800", "scintilla", "200bx", "covet"}

-- Racer name generation
local RACER_FIRST_NAMES = {"Speed", "Fast", "Quick", "Nitro", "Turbo", "Drift", "Midnight", "Shadow", "Flash", "Thunder"}
local RACER_LAST_NAMES = {"Mike", "Danny", "Rico", "Tony", "Vic", "Max", "Blade", "Ghost", "Snake", "Wolf"}

-- Proximity threshold for challenge option (meters)
local CHALLENGE_PROXIMITY = 15

---------------------------------------------------------------------------
-- Race State Constants
---------------------------------------------------------------------------

local RACE_STATE = {
  IDLE = "idle",           -- No active race
  STAGING = "staging",     -- Race accepted, driving to start
  COUNTDOWN = "countdown", -- 3-2-1 GO countdown
  RACING = "racing",       -- Active race in progress
  FINISHED = "finished",   -- Race completed (win or lose)
  ABANDONED = "abandoned"  -- Player quit/crashed
}

local ENCOUNTER_STATE = {
  NONE = "none",           -- No encounter active
  SPAWNED = "spawned",     -- AI racer nearby (night only)
  CHALLENGED = "challenged", -- Player challenged via radial
  COUNTDOWN = "countdown", -- Race starting
  RACING = "racing",       -- Active encounter race
  FINISHED = "finished"    -- Race ended
}

---------------------------------------------------------------------------
-- Module State
---------------------------------------------------------------------------

-- Loaded races from JSON
local loadedRaces = {}
local racesLoaded = false

-- Active race state
local activeRace = {
  state = RACE_STATE.IDLE,
  raceId = nil,
  raceName = nil,
  raceData = nil,
  betAmount = 0,
  isPinkSlip = false,
  playerCarInventoryId = nil,

  -- Checkpoints
  checkpoints = {},
  currentCheckpoint = 0,
  totalCheckpoints = 0,

  -- Timing
  startTime = 0,
  lastCheckpointTime = 0,
  splitTimes = {},

  -- Triggers (BeamNGTrigger objects)
  triggers = {},
  startTrigger = nil,
  finishTrigger = nil
}

-- Street encounter state
local encounter = {
  state = ENCOUNTER_STATE.NONE,
  racerVehId = nil,
  racerModel = nil,
  racerName = nil,
  distanceToPlayer = math.huge,
  currentBet = 5000,
  isPinkSlip = false,
  finishPos = nil,
  finishTrigger = nil,
  countdownTime = 0,
  raceStartTime = 0,
  selectedRace = nil  -- Random race from available tracks
}

-- Statistics and lost vehicles
local stats = {
  racesWon = 0,
  racesLost = 0,
  totalWinnings = 0,
  totalLosses = 0,
  bestTimes = {}
}

local lostVehicles = {}

-- Cooldowns and timers
local lastEncounterTime = 0

---------------------------------------------------------------------------
-- Utility Functions
---------------------------------------------------------------------------

local function log(level, msg)
  logger.log(LOG_TAG, level, msg)
end

local function isNightTime()
  local tod = scenetree.tod
  if tod then
    local time = tod.time
    return time < 0.22 or time > 0.78
  end
  return false
end

local function getCurrentMapName()
  local levelPath = getMissionFilename()
  if levelPath then
    local mapName = string.match(levelPath, "levels/([^/]+)/")
    return mapName
  end
  return nil
end

local function isMapAllowed()
  local mapName = getCurrentMapName()
  if not mapName then return false end

  for _, allowed in ipairs(RACE_CONFIG.ALLOWED_MAPS) do
    if mapName == allowed then
      return true
    end
  end
  return false
end

local function getPlayerPos()
  local playerVehId = be:getPlayerVehicleID(0)
  if playerVehId then
    local veh = be:getObjectByID(playerVehId)
    if veh then
      return veh:getPosition()
    end
  end
  return nil
end

local function getPlayerMoney()
  if career_modules_playerAttributes and career_modules_playerAttributes.getAttributeValue then
    return career_modules_playerAttributes.getAttributeValue("money") or 0
  end
  return 0
end

local function formatMoney(amount)
  return string.format("$%d", amount)
end

local function generateRacerName()
  local firstName = RACER_FIRST_NAMES[math.random(1, #RACER_FIRST_NAMES)]
  local lastName = RACER_LAST_NAMES[math.random(1, #RACER_LAST_NAMES)]
  return firstName .. " " .. lastName
end

local function getVehicleDisplayName(model)
  -- Map model names to display names
  local displayNames = {
    vivace = "Cherrier Vivace",
    sunburst = "Hirochi Sunburst",
    etk800 = "ETK 800",
    scintilla = "Civetta Scintilla",
    ["200bx"] = "Ibishu 200BX",
    covet = "Ibishu Covet"
  }
  return displayNames[model] or model
end

local function getDistanceToEncounter()
  if not encounter.racerVehId then return math.huge end

  local playerPos = getPlayerPos()
  if not playerPos then return math.huge end

  local racerVeh = be:getObjectByID(encounter.racerVehId)
  if not racerVeh then return math.huge end

  return playerPos:distance(racerVeh:getPosition())
end

---------------------------------------------------------------------------
-- Race Data Loading
---------------------------------------------------------------------------

local function getRacesFilePath()
  local mapName = getCurrentMapName()
  if not mapName then return nil end
  -- Read from mod's settings folder (bundled with mod)
  return "/settings/races/" .. mapName .. ".json"
end

local function loadRaces()
  if not isMapAllowed() then
    log("I", "Map not in allowed list, skipping race loading")
    loadedRaces = {}
    racesLoaded = true
    return
  end

  local mapName = getCurrentMapName()
  if not mapName then
    log("W", "Could not determine current map")
    loadedRaces = {}
    racesLoaded = true
    return
  end

  -- Try multiple paths in order of priority:
  -- 1. Mod's settings folder (bundled with mod)
  -- 2. Mods folder (debugging location)
  -- 3. Unpacked mod folder
  local paths = {
    "/settings/races/" .. mapName .. ".json",
    "/mods/car_theft_career/settings/races/" .. mapName .. ".json",
    "/car_theft_career/settings/races/" .. mapName .. ".json"
  }

  local content = nil
  local loadedPath = nil

  for _, path in ipairs(paths) do
    content = readFile(path)
    if content then
      loadedPath = path
      break
    end
  end

  if content then
    log("I", "Loading races from: " .. loadedPath)
    local success, data = pcall(jsonDecode, content)
    if success and data and data.races then
      loadedRaces = data.races
      log("I", "Loaded " .. tableSize(loadedRaces) .. " races")
    else
      log("W", "Failed to parse races JSON")
      loadedRaces = {}
    end
  else
    log("I", "No races file found, starting with empty races")
    loadedRaces = {}
  end

  racesLoaded = true
end

function M.loadRaces()
  racesLoaded = false
  loadRaces()
end

---------------------------------------------------------------------------
-- Race Data for UI
---------------------------------------------------------------------------

function M.getRacesForUI()
  if not racesLoaded then
    loadRaces()
  end

  local result = {}

  for raceId, raceData in pairs(loadedRaces) do
    local entry = {
      id = raceId,
      name = raceData.name or raceId,
      description = raceData.description or "",
      type = raceData.type or "point_to_point",
      difficulty = raceData.difficulty or 1,
      minBet = raceData.minBet or RACE_CONFIG.BET_MIN,
      maxBet = raceData.maxBet or RACE_CONFIG.BET_MAX,
      checkpointCount = raceData.checkpoints and #raceData.checkpoints or 0,
      bestTime = stats.bestTimes[raceId] or nil
    }
    table.insert(result, entry)
  end

  -- Sort by difficulty
  table.sort(result, function(a, b) return a.difficulty < b.difficulty end)

  return result
end

---------------------------------------------------------------------------
-- Random Race Selection
---------------------------------------------------------------------------

local function generateRandomRace()
  if not racesLoaded then
    loadRaces()
  end

  local availableRaces = {}
  for id, race in pairs(loadedRaces) do
    table.insert(availableRaces, race)
  end

  if #availableRaces == 0 then
    return nil
  end

  return availableRaces[math.random(#availableRaces)]
end

function M.generateRandomRace()
  return generateRandomRace()
end

---------------------------------------------------------------------------
-- Navigation
---------------------------------------------------------------------------

local function setNavigationToStart(race)
  if not race then return false end

  local startPos = nil
  if race.start and race.start.pos then
    startPos = vec3(race.start.pos.x, race.start.pos.y, race.start.pos.z)
  end

  if not startPos then
    log("W", "Race has no start position for navigation")
    return false
  end

  -- Use BeamNG's ground markers / navigation system
  if core_groundMarkers then
    core_groundMarkers.setFocus(startPos)
    log("I", "Navigation set to race start: " .. (race.name or race.id))
    return true
  else
    log("W", "core_groundMarkers not available for navigation")
    return false
  end
end

function M.setNavigationToStart(raceId)
  if not racesLoaded then
    loadRaces()
  end

  local race = loadedRaces[raceId]
  if not race then
    return false, "Race not found"
  end

  return setNavigationToStart(race)
end

function M.clearNavigation()
  if core_groundMarkers then
    core_groundMarkers.setFocus(nil)
    return true
  end
  return false
end

---------------------------------------------------------------------------
-- Betting System
---------------------------------------------------------------------------

local function placeBet(amount, isPinkSlip, inventoryId)
  if amount < RACE_CONFIG.BET_MIN or amount > RACE_CONFIG.BET_MAX then
    return false, "Bet must be between " .. formatMoney(RACE_CONFIG.BET_MIN) .. " and " .. formatMoney(RACE_CONFIG.BET_MAX)
  end

  local playerMoney = getPlayerMoney()
  if playerMoney < amount then
    return false, "Not enough money"
  end

  -- Deduct bet
  if career_modules_playerAttributes and career_modules_playerAttributes.addAttribute then
    career_modules_playerAttributes.addAttribute("money", -amount, {
      label = "Street Racing Bet",
      tags = {"gameplay", "streetRacing", "bet"}
    })
  end

  activeRace.betAmount = amount
  activeRace.isPinkSlip = isPinkSlip or false
  activeRace.playerCarInventoryId = inventoryId

  log("I", "Bet placed: " .. formatMoney(amount))
  return true
end

local function payout(won, amount)
  if won then
    local winnings = amount or (activeRace.betAmount * RACE_CONFIG.WIN_MULTIPLIER)
    if career_modules_playerAttributes and career_modules_playerAttributes.addAttribute then
      career_modules_playerAttributes.addAttribute("money", winnings, {
        label = "Street Racing Winnings",
        tags = {"gameplay", "streetRacing", "winnings"}
      })
    end
    stats.racesWon = stats.racesWon + 1
    stats.totalWinnings = stats.totalWinnings + winnings
    log("I", "Race won! Payout: " .. formatMoney(winnings))
    return winnings
  else
    stats.racesLost = stats.racesLost + 1
    stats.totalLosses = stats.totalLosses + activeRace.betAmount
    log("I", "Race lost. Lost: " .. formatMoney(activeRace.betAmount))
    return 0
  end
end

---------------------------------------------------------------------------
-- Organized Race Management
---------------------------------------------------------------------------

function M.startRace(raceId, betAmount)
  if activeRace.state ~= RACE_STATE.IDLE then
    return false, "Already in a race"
  end

  if not racesLoaded then
    loadRaces()
  end

  local raceData = loadedRaces[raceId]
  if not raceData then
    return false, "Race not found"
  end

  -- Place bet
  local success, err = placeBet(betAmount, false, nil)
  if not success then
    return false, err
  end

  -- Set up race
  activeRace.state = RACE_STATE.STAGING
  activeRace.raceId = raceId
  activeRace.raceName = raceData.name or raceId
  activeRace.raceData = raceData
  activeRace.checkpoints = raceData.checkpoints or {}
  activeRace.currentCheckpoint = 0
  activeRace.totalCheckpoints = #activeRace.checkpoints
  activeRace.splitTimes = {}

  -- TODO: Create GPS waypoint to start line
  -- TODO: Create start line trigger

  log("I", "Race started: " .. activeRace.raceName .. " with bet " .. formatMoney(betAmount))

  -- Send UI update
  guihooks.trigger('toastrMsg', {
    type = "info",
    title = "Race Started",
    msg = "Drive to the starting line for " .. activeRace.raceName
  })

  return true
end

function M.abandonRace()
  if activeRace.state == RACE_STATE.IDLE then
    return false, "No active race"
  end

  log("I", "Race abandoned: " .. (activeRace.raceName or "encounter"))

  -- Bet is forfeited
  payout(false)

  -- Clean up
  cleanupRace()

  return true
end

local function cleanupRace()
  -- Remove triggers
  for _, trigger in ipairs(activeRace.triggers) do
    if trigger and trigger:isValid() then
      trigger:delete()
    end
  end

  -- Reset state
  activeRace = {
    state = RACE_STATE.IDLE,
    raceId = nil,
    raceName = nil,
    raceData = nil,
    betAmount = 0,
    isPinkSlip = false,
    playerCarInventoryId = nil,
    checkpoints = {},
    currentCheckpoint = 0,
    totalCheckpoints = 0,
    startTime = 0,
    lastCheckpointTime = 0,
    splitTimes = {},
    triggers = {},
    startTrigger = nil,
    finishTrigger = nil
  }
end

---------------------------------------------------------------------------
-- Street Encounter System
---------------------------------------------------------------------------

function M.getActiveEncounter()
  if encounter.state == ENCOUNTER_STATE.NONE then
    return nil
  end

  return {
    state = encounter.state,
    racerVehId = encounter.racerVehId,
    racerName = encounter.racerName,
    racerModel = encounter.racerModel,
    racerVehicle = getVehicleDisplayName(encounter.racerModel),
    distanceToPlayer = encounter.distanceToPlayer,
    currentBet = encounter.currentBet,
    isPinkSlip = encounter.isPinkSlip,
    allowPinkSlip = true,
    selectedRace = encounter.selectedRace
  }
end

-- Check if player is close enough to challenge
function M.isNearAdversary()
  if encounter.state ~= ENCOUNTER_STATE.SPAWNED then
    return false
  end
  return encounter.distanceToPlayer <= CHALLENGE_PROXIMITY
end

-- Get just the proximity distance (for UI display)
function M.getDistanceToAdversary()
  return encounter.distanceToPlayer
end

function M.challengeEncounter(betAmount, isPinkSlip)
  if encounter.state ~= ENCOUNTER_STATE.SPAWNED then
    return false, "No racer to challenge"
  end

  -- Validate bet
  if betAmount < RACE_CONFIG.BET_MIN or betAmount > RACE_CONFIG.BET_MAX then
    return false, "Invalid bet amount"
  end

  local playerMoney = getPlayerMoney()
  if playerMoney < betAmount then
    return false, "Not enough money"
  end

  -- Place bet
  local success, err = placeBet(betAmount, isPinkSlip, nil)
  if not success then
    return false, err
  end

  encounter.state = ENCOUNTER_STATE.CHALLENGED
  encounter.currentBet = betAmount
  encounter.isPinkSlip = isPinkSlip or false

  -- Generate random finish point
  encounter.finishPos = generateRandomFinish()

  -- Start countdown
  encounter.state = ENCOUNTER_STATE.COUNTDOWN
  encounter.countdownTime = RACE_CONFIG.COUNTDOWN_SECONDS

  log("I", "Challenge accepted! Bet: " .. formatMoney(betAmount))

  return true
end

local function generateRandomFinish()
  local playerPos = getPlayerPos()
  if not playerPos then return nil end

  -- Simple random point for now (will use road network later)
  local distance = RACE_CONFIG.ENCOUNTER_FINISH_DISTANCE
  local angle = math.random() * 2 * math.pi

  local finishPos = vec3(
    playerPos.x + math.cos(angle) * distance,
    playerPos.y + math.sin(angle) * distance,
    playerPos.z
  )

  return finishPos
end

local function spawnStreetRacer()
  if not isNightTime() then return end
  if not isMapAllowed() then return end
  if encounter.state ~= ENCOUNTER_STATE.NONE then return end

  -- Check cooldown
  local currentTime = os.time()
  if currentTime - lastEncounterTime < RACE_CONFIG.ENCOUNTER_COOLDOWN then
    return
  end

  -- Random spawn chance
  if math.random() > RACE_CONFIG.ENCOUNTER_SPAWN_CHANCE then
    return
  end

  local playerPos = getPlayerPos()
  if not playerPos then return end

  -- Select a random race from available tracks
  local selectedRace = generateRandomRace()

  -- Find spawn position
  local distance = RACE_CONFIG.ENCOUNTER_SPAWN_RANGE_MIN +
                   math.random() * (RACE_CONFIG.ENCOUNTER_SPAWN_RANGE_MAX - RACE_CONFIG.ENCOUNTER_SPAWN_RANGE_MIN)
  local angle = math.random() * 2 * math.pi

  local spawnPos = vec3(
    playerPos.x + math.cos(angle) * distance,
    playerPos.y + math.sin(angle) * distance,
    playerPos.z
  )

  -- Select random racer vehicle
  local model = RACER_VEHICLES[math.random(1, #RACER_VEHICLES)]

  -- Generate racer name
  local racerName = generateRacerName()

  -- Spawn vehicle
  local spawnOptions = {
    pos = spawnPos,
    autoEnterVehicle = false,
    vehicleName = "street_racer_" .. os.time()
  }

  local vehObj = core_vehicles.spawnNewVehicle(model, spawnOptions)
  if vehObj then
    encounter.racerVehId = vehObj:getID()
    encounter.racerModel = model
    encounter.racerName = racerName
    encounter.state = ENCOUNTER_STATE.SPAWNED
    encounter.currentBet = 5000  -- Default bet
    encounter.distanceToPlayer = distance
    encounter.selectedRace = selectedRace
    lastEncounterTime = currentTime

    local vehicleDisplay = getVehicleDisplayName(model)
    log("I", "Street racer spawned: " .. racerName .. " in " .. vehicleDisplay)

    guihooks.trigger('toastrMsg', {
      type = "info",
      title = "Street Racer Nearby",
      msg = racerName .. " in a " .. vehicleDisplay .. " wants to race! Get closer to challenge."
    })
  end
end

local function despawnEncounter()
  if encounter.racerVehId then
    local veh = be:getObjectByID(encounter.racerVehId)
    if veh then
      veh:delete()
    end
  end

  encounter = {
    state = ENCOUNTER_STATE.NONE,
    racerVehId = nil,
    racerModel = nil,
    racerName = nil,
    distanceToPlayer = math.huge,
    currentBet = 5000,
    isPinkSlip = false,
    finishPos = nil,
    finishTrigger = nil,
    countdownTime = 0,
    raceStartTime = 0,
    selectedRace = nil
  }
end

---------------------------------------------------------------------------
-- Pink Slip System
---------------------------------------------------------------------------

function M.getLostVehicles()
  local result = {}

  for i, veh in ipairs(lostVehicles) do
    local buybackPrice = math.floor(veh.value * RACE_CONFIG.PINKSLIP_BUYBACK_MULTIPLIER)
    table.insert(result, {
      id = veh.id,
      inventoryId = veh.inventoryId,
      name = veh.name,
      model = veh.model,
      value = veh.value,
      buybackPrice = buybackPrice,
      lostDate = veh.lostDate
    })
  end

  return result
end

function M.buyBackVehicle(vehicleId)
  for i, veh in ipairs(lostVehicles) do
    if veh.id == vehicleId then
      local buybackPrice = math.floor(veh.value * RACE_CONFIG.PINKSLIP_BUYBACK_MULTIPLIER)
      local playerMoney = getPlayerMoney()

      if playerMoney < buybackPrice then
        return false, "Not enough money"
      end

      -- Deduct money
      if career_modules_playerAttributes and career_modules_playerAttributes.addAttribute then
        career_modules_playerAttributes.addAttribute("money", -buybackPrice, {
          label = "Vehicle Buyback",
          tags = {"gameplay", "streetRacing", "buyback"}
        })
      end

      -- TODO: Add vehicle back to inventory
      -- This requires integration with RLS career inventory system

      -- Remove from lost list
      table.remove(lostVehicles, i)

      log("I", "Vehicle bought back: " .. veh.name .. " for " .. formatMoney(buybackPrice))
      return true
    end
  end

  return false, "Vehicle not found"
end

---------------------------------------------------------------------------
-- Statistics
---------------------------------------------------------------------------

function M.getStats()
  return {
    racesWon = stats.racesWon,
    racesLost = stats.racesLost,
    totalWinnings = stats.totalWinnings,
    totalLosses = stats.totalLosses,
    winRate = stats.racesWon + stats.racesLost > 0
              and math.floor(stats.racesWon / (stats.racesWon + stats.racesLost) * 100)
              or 0
  }
end

---------------------------------------------------------------------------
-- Save/Load
---------------------------------------------------------------------------

function M.getSaveData()
  return {
    stats = {
      racesWon = stats.racesWon,
      racesLost = stats.racesLost,
      totalWinnings = stats.totalWinnings,
      totalLosses = stats.totalLosses,
      bestTimes = stats.bestTimes
    },
    lostVehicles = lostVehicles,
    lastEncounterTime = lastEncounterTime
  }
end

function M.loadSaveData(data)
  if data then
    if data.stats then
      stats.racesWon = data.stats.racesWon or 0
      stats.racesLost = data.stats.racesLost or 0
      stats.totalWinnings = data.stats.totalWinnings or 0
      stats.totalLosses = data.stats.totalLosses or 0
      stats.bestTimes = data.stats.bestTimes or {}
    end
    lostVehicles = data.lostVehicles or {}
    lastEncounterTime = data.lastEncounterTime or 0
  end
end

---------------------------------------------------------------------------
-- Update Loop
---------------------------------------------------------------------------

local function onUpdate(dtReal, dtSim, dtRaw)
  -- Only run in career mode
  if not career_career or not career_career.isActive() then return end

  -- Try to spawn street encounter (night only)
  if encounter.state == ENCOUNTER_STATE.NONE and activeRace.state == RACE_STATE.IDLE then
    spawnStreetRacer()
  end

  -- Update encounter distance and check despawn
  if encounter.state == ENCOUNTER_STATE.SPAWNED then
    local playerPos = getPlayerPos()
    if playerPos and encounter.racerVehId then
      local racerVeh = be:getObjectByID(encounter.racerVehId)
      if racerVeh then
        local dist = playerPos:distance(racerVeh:getPosition())
        encounter.distanceToPlayer = dist

        -- Despawn if player drove too far away
        if dist > RACE_CONFIG.ENCOUNTER_DESPAWN_DISTANCE then
          log("I", "Encounter despawned - player too far")
          despawnEncounter()
        end
      else
        -- Vehicle no longer exists
        encounter.distanceToPlayer = math.huge
      end
    else
      encounter.distanceToPlayer = math.huge
    end
  end

  -- Handle countdown
  if encounter.state == ENCOUNTER_STATE.COUNTDOWN then
    encounter.countdownTime = encounter.countdownTime - dtSim
    if encounter.countdownTime <= 0 then
      encounter.state = ENCOUNTER_STATE.RACING
      encounter.raceStartTime = os.time()

      -- Start AI
      local racerVeh = be:getObjectByID(encounter.racerVehId)
      if racerVeh and encounter.finishPos then
        racerVeh:queueLuaCommand('ai.setMode("chase")')
        racerVeh:queueLuaCommand('ai.setSpeed(nil)')
      end

      guihooks.trigger('toastrMsg', {
        type = "info",
        title = "GO!",
        msg = "Race to the finish!"
      })
    end
  end
end

---------------------------------------------------------------------------
-- Event Hooks
---------------------------------------------------------------------------

local function onExtensionLoaded()
  log("I", "Street Racing extension loaded")
  loadRaces()
end

local function onExtensionUnloaded()
  log("I", "Street Racing extension unloaded")
  cleanupRace()
  despawnEncounter()
end

local function onCareerModulesActivated()
  log("I", "Career activated, loading races")
  loadRaces()
end

---------------------------------------------------------------------------
-- Module Exports
---------------------------------------------------------------------------

M.onUpdate = onUpdate
M.onExtensionLoaded = onExtensionLoaded
M.onExtensionUnloaded = onExtensionUnloaded
M.onCareerModulesActivated = onCareerModulesActivated

-- Public API
M.loadRaces = M.loadRaces
M.getRacesForUI = M.getRacesForUI
M.startRace = M.startRace
M.abandonRace = M.abandonRace
M.getActiveEncounter = M.getActiveEncounter
M.challengeEncounter = M.challengeEncounter
M.getLostVehicles = M.getLostVehicles
M.buyBackVehicle = M.buyBackVehicle
M.getStats = M.getStats
M.getSaveData = M.getSaveData
M.loadSaveData = M.loadSaveData

-- Constants for external access
M.RACE_STATE = RACE_STATE
M.ENCOUNTER_STATE = ENCOUNTER_STATE

return M
