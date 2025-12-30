-- Car Theft Career - Street Racing Extension
-- Handles organized races, street encounters, and betting

local M = {}

-- Logger module
local logger = require("carTheft/logger")
local LOG_TAG = "carTheft_streetRacing"

-- Checkpoint manager
local raceCheckpoints = require("carTheft/raceCheckpoints")

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

-- AI racer vehicles (must match folder names in /vehicles/)
local RACER_VEHICLES = {"vivace", "sunburst2", "etk800", "bx", "covet", "etkc", "sbr"}

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
  trackId = nil,
  raceName = nil,
  raceData = nil,
  betAmount = 0,
  isPinkSlip = false,
  playerCarInventoryId = nil,

  -- Adversary info (from dynamic race generation)
  adversaryName = nil,
  adversaryModel = nil,
  adversaryVehId = nil,

  -- Checkpoints
  checkpoints = {},
  currentCheckpoint = 0,
  totalCheckpoints = 0,

  -- Timing
  startTime = 0,
  lastCheckpointTime = 0,
  splitTimes = {},

  -- Countdown
  countdownTime = 0,
  lastCountdown = 0,

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
    sunburst2 = "Hirochi Sunburst",
    etk800 = "ETK 800-Series",
    bx = "Ibishu 200BX",
    covet = "Ibishu Covet",
    etkc = "ETK-K Series",
    sbr = "Hirochi SBR4"
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
  -- 1. Source folder (for development)
  -- 2. Mod's settings folder (bundled with mod)
  -- 3. Mods folder (debugging location)
  local paths = {
    "/car_theft_career/settings/races/" .. mapName .. ".json",
    "/settings/races/" .. mapName .. ".json",
    "/mods/car_theft_career/settings/races/" .. mapName .. ".json"
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

  -- Collect available tracks
  local tracks = {}
  for id, track in pairs(loadedRaces) do
    table.insert(tracks, {id = id, data = track})
  end

  if #tracks == 0 then
    return {}
  end

  -- Generate 3 dynamic races with random adversaries
  local result = {}
  for i = 1, 3 do
    local trackInfo = tracks[math.random(#tracks)]
    local track = trackInfo.data

    -- Random adversary
    local advName = generateRacerName()
    local advModel = RACER_VEHICLES[math.random(#RACER_VEHICLES)]
    local advVehicle = getVehicleDisplayName(advModel)

    table.insert(result, {
      id = trackInfo.id .. "_" .. i,
      trackId = trackInfo.id,
      name = "vs " .. advName,
      description = "Racing a " .. advVehicle,
      adversaryName = advName,
      adversaryModel = advModel,
      adversaryVehicle = advVehicle,
      type = track.type or "point_to_point",
      difficulty = track.difficulty or 1,
      minBet = track.minBet or RACE_CONFIG.BET_MIN,
      maxBet = track.maxBet or RACE_CONFIG.BET_MAX,
      checkpointCount = track.checkpoints and #track.checkpoints or 0,
      bestTime = stats.bestTimes[trackInfo.id] or nil
    })
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

local function deductBet(amount)
  if career_modules_playerAttributes and career_modules_playerAttributes.addAttribute then
    career_modules_playerAttributes.addAttribute("money", -amount, {
      label = "Street Racing Bet",
      tags = {"gameplay", "streetRacing", "bet"}
    })
  end
  log("I", "Bet deducted: " .. formatMoney(amount))
end

local function spawnAdversary()
  if not activeRace.raceData then
    log("W", "Cannot spawn adversary - no race data")
    return false
  end

  local model = activeRace.adversaryModel or RACER_VEHICLES[math.random(#RACER_VEHICLES)]
  local spawnPos, rotation

  -- Check for new spawn format (from Race Editor UI)
  if activeRace.raceData.spawns and activeRace.raceData.spawns.adversaries and #activeRace.raceData.spawns.adversaries > 0 then
    -- Use first adversary spawn position from editor
    local advSpawn = activeRace.raceData.spawns.adversaries[1]
    spawnPos = vec3(advSpawn.pos.x, advSpawn.pos.y, advSpawn.pos.z)
    rotation = advSpawn.rot and quat(advSpawn.rot.x, advSpawn.rot.y, advSpawn.rot.z, advSpawn.rot.w) or quat(0, 0, 0, 1)
    log("I", "Using editor spawn position for adversary")
  elseif activeRace.raceData.start then
    -- Fallback: calculate position 4m to the right of start line (legacy behavior)
    local startPos = activeRace.raceData.start.pos
    local startRot = activeRace.raceData.start.rot
    rotation = startRot and quat(startRot.x, startRot.y, startRot.z, startRot.w) or quat(0, 0, 0, 1)
    local basePos = vec3(startPos.x, startPos.y, startPos.z)
    local rightVector = rotation * vec3(4, 0, 0)
    spawnPos = basePos + rightVector
    log("I", "Using calculated spawn position (4m offset)")
  else
    log("W", "Cannot spawn adversary - no spawn position available")
    return false
  end

  -- Build spawn options
  local spawnOptions = {
    pos = spawnPos,
    rot = rotation,
    autoEnterVehicle = false,
    vehicleName = "street_racer_adversary"
  }

  log("I", string.format("Spawning adversary model '%s' at (%.1f, %.1f, %.1f)", model, spawnPos.x, spawnPos.y, spawnPos.z))

  local success, vehObj = pcall(function()
    return core_vehicles.spawnNewVehicle(model, spawnOptions)
  end)

  if success and vehObj then
    activeRace.adversaryVehId = vehObj:getID()
    log("I", "Adversary spawned: " .. (activeRace.adversaryName or "Racer") .. " in " .. getVehicleDisplayName(model))

    -- Set AI to stop and wait for race start
    vehObj:queueLuaCommand('ai.setMode("stop")')

    return true
  else
    log("E", "Failed to spawn adversary vehicle: " .. tostring(vehObj))
    return false
  end
end

-- Forward declaration for fallback
local startAdversaryRacingFallback

-- Start AI racing towards finish line using road-aware pathfinding
local function startAdversaryRacing()
  if not activeRace.adversaryVehId then
    log("E", "No adversary vehicle to start racing")
    return
  end

  local advVeh = be:getObjectByID(activeRace.adversaryVehId)
  if not advVeh then return end

  -- Convert checkpoint coordinates to nearest road waypoint names
  -- This gives us proper road-aware AI pathfinding via BeamNG's navigation system
  local waypointNames = {}

  -- Add all checkpoints
  if activeRace.raceData.checkpoints then
    for _, cp in ipairs(activeRace.raceData.checkpoints) do
      if cp.node then
        local pos = vec3(cp.node.x, cp.node.y, cp.node.z)
        local wpName, _, dist = map.findClosestRoad(pos)
        if wpName and dist < 50 then  -- Only use if within 50m of a road
          table.insert(waypointNames, wpName)
          log("I", string.format("Checkpoint -> waypoint '%s' (%.1fm away)", wpName, dist))
        else
          log("W", string.format("No road found near checkpoint (%.1f, %.1f, %.1f)", cp.node.x, cp.node.y, cp.node.z))
        end
      end
    end
  end

  -- Add finish position
  if activeRace.raceData.finish and activeRace.raceData.finish.pos then
    local fp = activeRace.raceData.finish.pos
    local pos = vec3(fp.x, fp.y, fp.z)
    local wpName, _, dist = map.findClosestRoad(pos)
    if wpName and dist < 50 then
      table.insert(waypointNames, wpName)
      log("I", string.format("Finish -> waypoint '%s' (%.1fm away)", wpName, dist))
    end
  end

  if #waypointNames == 0 then
    log("W", "No road waypoints found for AI - falling back to direct coordinates")
    -- Fallback: try script mode with coordinates (will teleport but at least works)
    startAdversaryRacingFallback()
    return
  end

  -- Build waypoint list string for AI command
  local wpListStr = '{"' .. table.concat(waypointNames, '","') .. '"}'

  -- Set up AI for racing with road-aware pathfinding
  -- Uses wpTargetList which follows roads between waypoints
  advVeh:queueLuaCommand('ai.setMode("manual")')
  advVeh:queueLuaCommand('ai.setRacing(true)')
  advVeh:queueLuaCommand('ai.driveInLane("on")')
  advVeh:queueLuaCommand('ai.setAggression(0.8)')

  local aiCmd = string.format([[
    ai.driveUsingPath({
      wpTargetList = %s,
      driveInLane = "on",
      aggression = 0.8
    })
  ]], wpListStr)

  advVeh:queueLuaCommand(aiCmd)

  log("I", "Adversary AI started racing with " .. #waypointNames .. " road waypoints")
end

-- Fallback: Use script mode if no road waypoints found (will teleport to first point)
startAdversaryRacingFallback = function()
  local advVeh = be:getObjectByID(activeRace.adversaryVehId)
  if not advVeh then return end

  local scriptWaypoints = {}

  if activeRace.raceData.checkpoints then
    for _, cp in ipairs(activeRace.raceData.checkpoints) do
      if cp.node then
        table.insert(scriptWaypoints, {x = cp.node.x, y = cp.node.y, z = cp.node.z})
      end
    end
  end

  if activeRace.raceData.finish and activeRace.raceData.finish.pos then
    local fp = activeRace.raceData.finish.pos
    table.insert(scriptWaypoints, {x = fp.x, y = fp.y, z = fp.z})
  end

  if #scriptWaypoints == 0 then return end

  local wpStrings = {}
  for _, wp in ipairs(scriptWaypoints) do
    table.insert(wpStrings, string.format("{x=%f,y=%f,z=%f}", wp.x, wp.y, wp.z))
  end
  local scriptStr = "{" .. table.concat(wpStrings, ",") .. "}"

  advVeh:queueLuaCommand('ai.setMode("manual")')
  advVeh:queueLuaCommand(string.format('ai.driveUsingPath({script = %s, aggression = 0.7})', scriptStr))

  log("W", "Using fallback script mode (AI may teleport)")
end

local function placeBet(amount, isPinkSlip, inventoryId)
  if amount < RACE_CONFIG.BET_MIN or amount > RACE_CONFIG.BET_MAX then
    return false, "Bet must be between " .. formatMoney(RACE_CONFIG.BET_MIN) .. " and " .. formatMoney(RACE_CONFIG.BET_MAX)
  end

  local playerMoney = getPlayerMoney()
  if playerMoney < amount then
    return false, "Not enough money"
  end

  -- Deduct bet
  deductBet(amount)

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
-- Race Cleanup (defined early for forward references)
---------------------------------------------------------------------------

local function cleanupRace()
  -- Remove triggers
  for _, trigger in ipairs(activeRace.triggers) do
    if trigger and trigger:isValid() then
      trigger:delete()
    end
  end

  -- Remove adversary vehicle if spawned
  if activeRace.adversaryVehId then
    local veh = be:getObjectByID(activeRace.adversaryVehId)
    if veh then
      veh:delete()
    end
  end

  -- Clean up visual checkpoints
  raceCheckpoints.cleanup()

  -- Clear navigation
  M.clearNavigation()

  -- Reset state
  activeRace = {
    state = RACE_STATE.IDLE,
    raceId = nil,
    trackId = nil,
    raceName = nil,
    raceData = nil,
    betAmount = 0,
    isPinkSlip = false,
    playerCarInventoryId = nil,
    adversaryName = nil,
    adversaryModel = nil,
    adversaryVehId = nil,
    checkpoints = {},
    currentCheckpoint = 0,
    totalCheckpoints = 0,
    startTime = 0,
    lastCheckpointTime = 0,
    splitTimes = {},
    countdownTime = 0,
    lastCountdown = 0,
    triggers = {},
    startTrigger = nil,
    finishTrigger = nil
  }
end

---------------------------------------------------------------------------
-- Checkpoint Handling
---------------------------------------------------------------------------

-- Called when player hits a checkpoint
local function onCheckpointHit(checkpointIndex, totalCheckpoints, isFinish)
  if activeRace.state ~= RACE_STATE.RACING then
    return
  end

  activeRace.currentCheckpoint = checkpointIndex
  local currentTime = os.clock() - activeRace.startTime

  -- Record split time
  table.insert(activeRace.splitTimes, currentTime)

  log("I", string.format("Checkpoint %d/%d - Time: %.2fs", checkpointIndex, totalCheckpoints, currentTime))

  if isFinish then
    -- Race finished!
    activeRace.state = RACE_STATE.FINISHED
    local raceTime = currentTime

    -- Check if we beat the adversary (simple: player always wins for now)
    -- TODO: Actually track adversary position
    local won = true

    if won then
      payout(true)
      guihooks.trigger('toastrMsg', {
        type = "success",
        title = "You Won!",
        msg = string.format("Time: %.2fs - Winnings: %s", raceTime, formatMoney(activeRace.betAmount * RACE_CONFIG.WIN_MULTIPLIER))
      })

      -- Update best time
      if not stats.bestTimes[activeRace.trackId] or raceTime < stats.bestTimes[activeRace.trackId] then
        stats.bestTimes[activeRace.trackId] = raceTime
        log("I", "New best time: " .. raceTime)
      end
    else
      payout(false)
      guihooks.trigger('toastrMsg', {
        type = "error",
        title = "You Lost!",
        msg = string.format("Time: %.2fs - Lost: %s", raceTime, formatMoney(activeRace.betAmount))
      })
    end

    -- Cleanup after short delay
    -- TODO: Use timer instead of immediate cleanup
    cleanupRace()
  else
    -- Checkpoint passed
    guihooks.trigger('toastrMsg', {
      type = "info",
      title = string.format("Checkpoint %d/%d", checkpointIndex, totalCheckpoints - 1),
      msg = string.format("%.2fs", currentTime)
    })

    -- SET WAYPOINT TO NEXT CHECKPOINT
    local nextCheckpoint = activeRace.checkpoints[checkpointIndex + 1]
    if nextCheckpoint and nextCheckpoint.node then
      local nextPos = vec3(nextCheckpoint.node.x, nextCheckpoint.node.y, nextCheckpoint.node.z)
      core_groundMarkers.setFocus(nextPos)
      log("I", "Navigation set to checkpoint " .. (checkpointIndex + 1))
    elseif activeRace.raceData.finish then
      -- Next is finish line
      local finishPos = activeRace.raceData.finish.pos
      core_groundMarkers.setFocus(vec3(finishPos.x, finishPos.y, finishPos.z))
      log("I", "Navigation set to finish line")
    end
  end
end

---------------------------------------------------------------------------
-- Organized Race Management
---------------------------------------------------------------------------

-- acceptRace: Called when user accepts a race from UI
-- Spawns adversary and sets up checkpoints immediately
-- Money is deducted when player reaches start line
function M.acceptRace(raceId, betAmount, adversaryName, adversaryModel)
  if activeRace.state ~= RACE_STATE.IDLE then
    return false, "Already in a race"
  end

  if not racesLoaded then
    loadRaces()
  end

  -- Validate bet amount
  if betAmount < RACE_CONFIG.BET_MIN or betAmount > RACE_CONFIG.BET_MAX then
    return false, "Bet must be between " .. formatMoney(RACE_CONFIG.BET_MIN) .. " and " .. formatMoney(RACE_CONFIG.BET_MAX)
  end

  -- Check player has enough money (but don't deduct yet)
  local playerMoney = getPlayerMoney()
  if playerMoney < betAmount then
    return false, "Not enough money"
  end

  -- Find track from dynamic race ID (e.g., "race01_2" → "race01")
  local trackId = raceId:match("^(.+)_%d+$") or raceId
  local trackData = loadedRaces[trackId]
  if not trackData then
    return false, "Track not found: " .. tostring(trackId)
  end

  -- Set up race in staging mode
  activeRace.state = RACE_STATE.STAGING
  activeRace.raceId = raceId
  activeRace.trackId = trackId
  activeRace.raceName = "vs " .. (adversaryName or "Unknown Racer")
  activeRace.raceData = trackData
  activeRace.betAmount = betAmount  -- Reserved, not deducted yet
  activeRace.adversaryName = adversaryName
  activeRace.adversaryModel = adversaryModel
  activeRace.checkpoints = trackData.checkpoints or {}
  activeRace.currentCheckpoint = 0
  activeRace.totalCheckpoints = #activeRace.checkpoints
  activeRace.splitTimes = {}
  activeRace.countdownTime = 0
  activeRace.lastCountdown = 0

  -- Set up visual checkpoints and triggers
  raceCheckpoints.setupRace(trackData, trackId)
  raceCheckpoints.setCheckpointCallback(onCheckpointHit)
  raceCheckpoints.showCheckpoints(0)  -- Show first checkpoint (start line)

  -- Spawn adversary vehicle at start line (waiting)
  spawnAdversary()

  -- Set waypoint to start line
  setNavigationToStart(trackData)

  -- Close UI
  guihooks.trigger('MenuHide')

  log("I", "Race accepted: " .. activeRace.raceName .. " with bet " .. formatMoney(betAmount))

  -- Show message
  ui_message("Drive to the starting line! Your opponent is waiting.", 5, "info")

  return true
end

-- Legacy alias for backwards compatibility
function M.startRace(raceId, betAmount)
  return M.acceptRace(raceId, betAmount)
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

  ---------------------------------------------------------------------------
  -- Organized Race: Start line detection (STAGING state)
  ---------------------------------------------------------------------------
  if activeRace.state == RACE_STATE.STAGING then
    local playerPos = getPlayerPos()
    local startPos = activeRace.raceData and activeRace.raceData.start and activeRace.raceData.start.pos
    if playerPos and startPos then
      local dist = playerPos:distance(vec3(startPos.x, startPos.y, startPos.z))
      if dist < 15 then  -- Within 15m of start line
        -- NOW deduct money
        deductBet(activeRace.betAmount)

        -- Adversary already spawned at accept time
        -- Start countdown
        activeRace.state = RACE_STATE.COUNTDOWN
        activeRace.countdownTime = RACE_CONFIG.COUNTDOWN_SECONDS
        activeRace.lastCountdown = RACE_CONFIG.COUNTDOWN_SECONDS + 1

        -- Clear navigation waypoint
        M.clearNavigation()

        log("I", "Player reached start line - beginning countdown")
      end
    end
  end

  ---------------------------------------------------------------------------
  -- Organized Race: Countdown (COUNTDOWN state)
  ---------------------------------------------------------------------------
  if activeRace.state == RACE_STATE.COUNTDOWN then
    activeRace.countdownTime = activeRace.countdownTime - dtSim
    local countSec = math.ceil(activeRace.countdownTime)

    -- Display countdown numbers (3, 2, 1)
    if countSec > 0 and countSec ~= activeRace.lastCountdown then
      activeRace.lastCountdown = countSec
      guihooks.trigger('toastrMsg', {
        type = "warning",
        title = tostring(countSec),
        msg = ""
      })
      log("I", "Countdown: " .. countSec)
    elseif activeRace.countdownTime <= 0 then
      -- GO!
      activeRace.state = RACE_STATE.RACING
      activeRace.startTime = os.clock()

      guihooks.trigger('toastrMsg', {
        type = "success",
        title = "GO!",
        msg = "Race to the finish!"
      })

      -- Start AI adversary racing along the track
      startAdversaryRacing()

      -- Show first checkpoint after start
      raceCheckpoints.showCheckpoints(1)

      -- SET WAYPOINT TO FIRST CHECKPOINT
      if activeRace.checkpoints[1] and activeRace.checkpoints[1].node then
        local cp1 = activeRace.checkpoints[1].node
        core_groundMarkers.setFocus(vec3(cp1.x, cp1.y, cp1.z))
        log("I", "Navigation set to first checkpoint")
      end

      log("I", "Race started!")
    end
  end

  ---------------------------------------------------------------------------
  -- Street Encounters: Spawn (at night)
  ---------------------------------------------------------------------------
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

  -- Handle encounter countdown
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
-- Debug Functions
---------------------------------------------------------------------------

-- Teleport player vehicle to race start position
local function teleportPlayerToStart(raceData)
  local playerVeh = be:getPlayerVehicle(0)
  if not playerVeh then
    log("E", "No player vehicle for teleport")
    return false
  end

  local startPos, startRot

  -- Check for new spawn format (from Race Editor UI)
  if raceData.spawns and raceData.spawns.player then
    startPos = raceData.spawns.player.pos
    startRot = raceData.spawns.player.rot
    log("I", "Using editor spawn position for player")
  elseif raceData.start then
    -- Fallback to legacy format
    startPos = raceData.start.pos
    startRot = raceData.start.rot
    log("I", "Using legacy start position for player")
  end

  if not startPos then
    log("E", "Race has no start position")
    return false
  end

  -- Build position and rotation
  local pos = vec3(startPos.x, startPos.y, startPos.z)
  local rot = startRot and quat(startRot.x, startRot.y, startRot.z, startRot.w) or quat(0, 0, 0, 1)

  -- Use spawn.safeTeleport if available, otherwise direct set
  if spawn and spawn.safeTeleport then
    spawn.safeTeleport(playerVeh, pos, rot, nil, nil, nil, true)
  else
    playerVeh:setPositionRotation(pos.x, pos.y, pos.z, rot.x, rot.y, rot.z, rot.w)
  end

  log("I", string.format("Player teleported to start: (%.1f, %.1f, %.1f)", pos.x, pos.y, pos.z))
  return true
end

-- Debug function to start a race immediately (bypasses betting, teleports player)
-- Usage: carTheft_streetRacing.debugStartRace("race01", "covet")
function M.debugStartRace(trackId, vehicleModel)
  -- Default to covet if no model specified
  vehicleModel = vehicleModel or "covet"

  -- Ensure races are loaded
  if not racesLoaded then
    loadRaces()
  end

  -- Get track data
  local trackData = loadedRaces[trackId]
  if not trackData then
    log("E", "Track not found: " .. tostring(trackId))
    ui_message("Track not found: " .. tostring(trackId), 5, "error")
    return false, "Track not found"
  end

  -- Cleanup any existing race
  if activeRace.state ~= RACE_STATE.IDLE then
    cleanupRace()
  end

  -- Set up race state (bypassing betting)
  activeRace.state = RACE_STATE.STAGING
  activeRace.raceId = trackId .. "_debug"
  activeRace.trackId = trackId
  activeRace.raceName = "Debug Race"
  activeRace.raceData = trackData
  activeRace.betAmount = 0  -- No betting in debug mode
  activeRace.adversaryName = "Debug Opponent"
  activeRace.adversaryModel = vehicleModel
  activeRace.checkpoints = trackData.checkpoints or {}
  activeRace.currentCheckpoint = 0
  activeRace.totalCheckpoints = #activeRace.checkpoints
  activeRace.splitTimes = {}

  -- Set up visual checkpoints and triggers
  raceCheckpoints.setupRace(trackData, trackId)
  raceCheckpoints.setCheckpointCallback(onCheckpointHit)

  -- Teleport player to start line
  if not teleportPlayerToStart(trackData) then
    cleanupRace()
    return false, "Failed to teleport player"
  end

  -- Spawn adversary vehicle
  if not spawnAdversary() then
    log("W", "Failed to spawn adversary, continuing without opponent")
  end

  -- Skip staging, go directly to countdown
  activeRace.state = RACE_STATE.COUNTDOWN
  activeRace.countdownTime = RACE_CONFIG.COUNTDOWN_SECONDS
  activeRace.lastCountdown = RACE_CONFIG.COUNTDOWN_SECONDS + 1

  -- Show first checkpoint
  raceCheckpoints.showCheckpoints(0)

  log("I", "Debug race started: " .. trackId .. " with " .. vehicleModel)
  ui_message("Debug race starting! 3... 2... 1...", 3, "info")

  return true
end

-- List available tracks for debugging
function M.debugListTracks()
  if not racesLoaded then
    loadRaces()
  end

  log("I", "Available tracks:")
  for id, track in pairs(loadedRaces) do
    local checkpointCount = track.checkpoints and #track.checkpoints or 0
    log("I", string.format("  - %s: %s (%d checkpoints)", id, track.name or id, checkpointCount))
  end

  return loadedRaces
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

-- Handle trigger events for checkpoint detection
local function onBeamNGTrigger(data)
  -- Forward to checkpoint manager
  raceCheckpoints.onTrigger(data)
end

---------------------------------------------------------------------------
-- Module Exports
---------------------------------------------------------------------------

M.onUpdate = onUpdate
M.onExtensionLoaded = onExtensionLoaded
M.onExtensionUnloaded = onExtensionUnloaded
M.onCareerModulesActivated = onCareerModulesActivated
M.onBeamNGTrigger = onBeamNGTrigger

-- Public API
M.loadRaces = M.loadRaces
M.getRacesForUI = M.getRacesForUI
M.acceptRace = M.acceptRace
M.startRace = M.startRace  -- Legacy alias
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
