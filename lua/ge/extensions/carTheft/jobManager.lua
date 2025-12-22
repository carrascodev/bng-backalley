-- Car Theft Career - Job Manager
-- Manages theft job offers, proximity spawning, and job state tracking

local M = {}

-- Logger module
local logger = require("carTheft/logger")
local LOG_TAG = "carTheft_jobManager"

-- Dependencies - use base game modules
M.dependencies = {
  'gameplay_city',
  'gameplay_parking',
  'gameplay_sites_sitesManager',
  'util_configListGenerator'
}

local config = require("carTheft/config") or {}

-- Vehicle pool cache (loaded from game configs)
local cachedEligibleVehicles = nil

-- Variety tracking (must be declared before getRandomVehicleForTier)
local recentCategories = {}
local MAX_RECENT_CATEGORIES = 3

---------------------------------------------------------------------------
-- Job States
---------------------------------------------------------------------------

local JOB_STATE = {
  AVAILABLE = "available",   -- Job offer visible in app, location not unlocked
  UNLOCKED = "unlocked",     -- Player paid fee, location revealed
  SPAWNED = "spawned",       -- Vehicle spawned (player nearby)
  ACTIVE = "active",         -- Player is stealing/delivering this car
  COMPLETED = "completed",   -- Successfully delivered
  FAILED = "failed",         -- Player was caught or job expired
  EXPIRED = "expired"        -- Job timed out before player accepted
}

---------------------------------------------------------------------------
-- Parking Spots (loaded dynamically from map data)
---------------------------------------------------------------------------

local cachedParkingSpots = nil
local usedSpotNames = {}  -- Track which spots are being used by active jobs

-- Area name mapping based on position (approximate zones)
local function getAreaFromPosition(pos)
  if not pos then return "Unknown" end
  local x, y = pos.x, pos.y

  -- Downtown (central city area)
  if x > -900 and x < -600 and y > -100 and y < 300 then
    return "Downtown"
  -- Industrial (port/warehouse area)
  elseif x > -600 and x < -200 and y < -100 then
    return "Industrial"
  -- Suburbs (residential hills)
  elseif x < -900 and y > 200 then
    return "Suburbs"
  -- Coast (beach area)
  elseif y > 400 then
    return "Coast"
  -- Highway (eastern areas)
  elseif x > 200 then
    return "Highway"
  else
    return "City"
  end
end

-- Load parking spots from map data using base game APIs
local function loadParkingSpots()
  if cachedParkingSpots then
    return cachedParkingSpots
  end

  log("I", "Loading parking spots from map data...")

  -- Method 1: Use gameplay_parking module (uses gameplay_city internally)
  if gameplay_parking and gameplay_parking.getParkingSpots then
    log("D", "Trying gameplay_parking.getParkingSpots()...")
    local spots = gameplay_parking.getParkingSpots()
    if spots and spots.sorted and #spots.sorted > 0 then
      cachedParkingSpots = spots.sorted
      log("I", "Loaded " .. #cachedParkingSpots .. " parking spots from gameplay_parking")
      return cachedParkingSpots
    elseif spots and spots.objects and #spots.objects > 0 then
      cachedParkingSpots = spots.objects
      log("I", "Loaded " .. #cachedParkingSpots .. " parking spots from gameplay_parking.objects")
      return cachedParkingSpots
    end
    log("D", "gameplay_parking returned no spots")
  end

  -- Method 2: Use gameplay_city directly
  if gameplay_city then
    log("D", "Trying gameplay_city...")
    gameplay_city.loadSites()
    local sites = gameplay_city.getSites()
    if sites and sites.parkingSpots then
      if sites.parkingSpots.sorted and #sites.parkingSpots.sorted > 0 then
        cachedParkingSpots = sites.parkingSpots.sorted
        log("I", "Loaded " .. #cachedParkingSpots .. " parking spots from gameplay_city")
        return cachedParkingSpots
      elseif sites.parkingSpots.objects and #sites.parkingSpots.objects > 0 then
        cachedParkingSpots = sites.parkingSpots.objects
        log("I", "Loaded " .. #cachedParkingSpots .. " parking spots from gameplay_city.objects")
        return cachedParkingSpots
      end
    end
    log("D", "gameplay_city returned no spots")
  end

  -- Method 3: Use sites manager to find city.sites.json
  if gameplay_sites_sitesManager then
    log("D", "Trying gameplay_sites_sitesManager...")
    local sitePath = gameplay_sites_sitesManager.getCurrentLevelSitesFileByName('city')
    if sitePath then
      log("D", "Found site path: " .. sitePath)
      local siteData = gameplay_sites_sitesManager.loadSites(sitePath, true, true)
      if siteData and siteData.parkingSpots then
        local spots = siteData.parkingSpots.sorted or siteData.parkingSpots.objects
        if spots and #spots > 0 then
          cachedParkingSpots = spots
          log("I", "Loaded " .. #cachedParkingSpots .. " parking spots from sitesManager")
          return cachedParkingSpots
        end
      end
    end
  end

  log("W", "No parking spots found! Make sure a city.sites.json exists for this level.")
  return {}
end

-- Filter valid parking spots for spawning
local function getValidParkingSpots(minDistanceFromPlayer)
  minDistanceFromPlayer = minDistanceFromPlayer or 300

  local spots = loadParkingSpots()
  if not spots or #spots == 0 then
    return {}
  end

  local playerPos = nil
  local playerVehId = be:getPlayerVehicleID(0)
  if playerVehId then
    local veh = be:getObjectByID(playerVehId)
    if veh then
      playerPos = veh:getPosition()
    end
  end
  if not playerPos and gameplay_walk and gameplay_walk.isWalking() then
    local unicycle = scenetree.findObject("unicycle")
    if unicycle then
      playerPos = unicycle:getPosition()
    end
  end

  local validSpots = {}
  for _, spot in ipairs(spots) do
    -- Check spot has position and is not occupied
    if spot.pos and not spot.vehicle then
      -- Check not already used by another job
      if not usedSpotNames[spot.name] then
        -- Check distance from player
        local distOk = true
        if playerPos then
          local dist = playerPos:distance(spot.pos)
          if dist < minDistanceFromPlayer then
            distOk = false
          end
        end

        if distOk then
          table.insert(validSpots, spot)
        end
      end
    end
  end

  return validSpots
end

-- Get a random valid parking spot
local function getRandomParkingSpot()
  local validSpots = getValidParkingSpots(300)
  if #validSpots == 0 then
    log("W", "No valid parking spots available!")
    return nil
  end

  local spot = validSpots[math.random(1, #validSpots)]
  return spot
end

-- Clear parking cache (call when level changes)
local function clearParkingCache()
  cachedParkingSpots = nil
  usedSpotNames = {}
  log("I", "Parking spots cache cleared")
end

---------------------------------------------------------------------------
-- Vehicle Pool (loaded dynamically from game configs)
---------------------------------------------------------------------------

-- Tier thresholds based on vehicle value
local TIER_THRESHOLDS = {
  {maxValue = 15000, tier = 1},   -- Economy: $0 - $15,000
  {maxValue = 40000, tier = 2},   -- Mid-range: $15,001 - $40,000
  {maxValue = math.huge, tier = 3} -- Premium: $40,001+
}

-- Get tier based on vehicle value
local function getTierForValue(value)
  for _, threshold in ipairs(TIER_THRESHOLDS) do
    if value <= threshold.maxValue then
      return threshold.tier
    end
  end
  return 3
end

-- Check if a vehicle config should be excluded
local function shouldExcludeVehicle(vehInfo)
  if not vehInfo then return true end

  -- Exclude if no value or too cheap
  if not vehInfo.Value or vehInfo.Value < 1000 then
    return true
  end

  -- Exclude undriveable configs by name patterns
  local configName = vehInfo.key or ""
  local excludePatterns = {"frame", "stripped", "damaged", "wrecked", "chassis"}
  for _, pattern in ipairs(excludePatterns) do
    if string.find(string.lower(configName), pattern) then
      return true
    end
  end

  -- Check aggregates for exclusions
  local agg = vehInfo.aggregates
  if not agg then return true end

  -- Exclude by Type
  if agg.Type then
    if agg.Type.Trailer or agg.Type.Prop or agg.Type.Utility then
      return true
    end
  end

  -- Exclude by Config Type
  local configType = agg["Config Type"]
  if configType then
    if configType.Frame or configType.Loaner or configType.Service or configType.Police or configType.Taxi then
      return true
    end
  end

  return false
end

-- Get vehicle category for variety tracking
local function getVehicleCategory(vehInfo)
  -- Check aggregates for Type
  local agg = vehInfo.aggregates
  if agg and agg.Type then
    for cat, _ in pairs(agg.Type) do
      return cat
    end
  end
  -- Fallback: check config name for category hints
  local configName = string.lower(vehInfo.key or "")
  if string.find(configName, "drift") then return "Drift"
  elseif string.find(configName, "race") or string.find(configName, "track") then return "Racing"
  elseif string.find(configName, "offroad") then return "Offroad"
  end
  return "Standard"
end

-- Load eligible vehicles from game configs
local function loadEligibleVehicles()
  if cachedEligibleVehicles then
    return cachedEligibleVehicles
  end

  log("I", "Loading eligible vehicles from game configs...")

  if not util_configListGenerator then
    log("E", "util_configListGenerator not available!")
    return {}
  end

  local allVehicles = util_configListGenerator.getEligibleVehicles()
  if not allVehicles then
    log("E", "Failed to get eligible vehicles")
    return {}
  end

  cachedEligibleVehicles = {}

  for _, vehInfo in pairs(allVehicles) do
    if not shouldExcludeVehicle(vehInfo) then
      -- Use core_vehicles.getConfig() to get the same value that inventory.addVehicle() uses
      -- This ensures the fee calculation matches the actual sell price
      local vehicleValue = vehInfo.Value
      if core_vehicles and core_vehicles.getConfig then
        local baseConfig = core_vehicles.getConfig(vehInfo.model_key, vehInfo.key)
        if baseConfig and baseConfig.Value then
          vehicleValue = baseConfig.Value
        end
      end

      local tier = getTierForValue(vehicleValue)
      local category = getVehicleCategory(vehInfo)
      table.insert(cachedEligibleVehicles, {
        model = vehInfo.model_key,
        configKey = vehInfo.key,
        name = vehInfo.Name or vehInfo.model_key,
        value = vehicleValue,
        tier = tier,
        category = category
      })
    end
  end

  log("I", "Loaded " .. #cachedEligibleVehicles .. " eligible vehicles")
  return cachedEligibleVehicles
end

-- Get a random vehicle for a given tier (with variety preference)
local function getRandomVehicleForTier(targetTier)
  local vehicles = loadEligibleVehicles()
  if #vehicles == 0 then
    log("E", "No eligible vehicles available!")
    return nil
  end

  -- Filter by tier
  local tierVehicles = {}
  for _, veh in ipairs(vehicles) do
    if veh.tier == targetTier then
      table.insert(tierVehicles, veh)
    end
  end

  -- Fallback to any tier if none found
  if #tierVehicles == 0 then
    log("W", "No vehicles for tier " .. targetTier .. ", using random vehicle")
    tierVehicles = vehicles
  end

  -- Favor variety: filter out recent categories (soft preference)
  local diverseVehicles = {}
  for _, veh in ipairs(tierVehicles) do
    local isDuplicate = false
    for _, recentCat in ipairs(recentCategories) do
      if veh.category == recentCat then
        isDuplicate = true
        break
      end
    end
    if not isDuplicate then
      table.insert(diverseVehicles, veh)
    end
  end

  -- Use diverse list if available, otherwise fall back to tier list
  local pool = #diverseVehicles > 0 and diverseVehicles or tierVehicles
  local selected = pool[math.random(1, #pool)]

  -- Track this category for variety
  table.insert(recentCategories, 1, selected.category)
  if #recentCategories > MAX_RECENT_CATEGORIES then
    table.remove(recentCategories)
  end

  return selected
end

-- Clear vehicle cache (e.g., on mod reload)
local function clearVehicleCache()
  cachedEligibleVehicles = nil
  log("I", "Vehicle cache cleared")
end

---------------------------------------------------------------------------
-- Job Management State
---------------------------------------------------------------------------

local activeJobs = {}           -- All current job offers
local completedJobIds = {}      -- Track completed jobs for stats (limited size)
local MAX_COMPLETED_JOBS = 50   -- Limit to prevent memory leak
local nextJobId = 1
local lastJobGenerationTime = 0
local JOB_GENERATION_INTERVAL = 120  -- Generate new jobs every 2 minutes
local MAX_ACTIVE_JOBS = 5            -- Maximum jobs available at once

---------------------------------------------------------------------------
-- Utility Functions
---------------------------------------------------------------------------

local function log(level, msg)
  logger.log(LOG_TAG, level, msg)
end

local function getPlayerPos()
  local playerVehId = be:getPlayerVehicleID(0)
  if playerVehId then
    local veh = be:getObjectByID(playerVehId)
    if veh then
      return veh:getPosition()
    end
  end
  if gameplay_walk and gameplay_walk.isWalking() then
    local unicycle = scenetree.findObject("unicycle")
    if unicycle then
      return unicycle:getPosition()
    end
  end
  return nil
end

local function randomRange(min, max)
  return min + math.random() * (max - min)
end

local function roundToNearest(value, nearest)
  return math.floor(value / nearest + 0.5) * nearest
end

---------------------------------------------------------------------------
-- Job Generation
---------------------------------------------------------------------------

local function generateFee(vehicleValue)
  -- Fee is 70-115% of vehicle value (high risk/reward)
  local feePercent = randomRange(0.70, 1.15)
  return roundToNearest(vehicleValue * feePercent, 50)
end

local function generateJob()
  -- Count active jobs
  local jobCount = 0
  for _ in pairs(activeJobs) do
    jobCount = jobCount + 1
  end

  if jobCount >= MAX_ACTIVE_JOBS then
    log("D", "Max active jobs reached, skipping generation")
    return nil
  end

  -- Get a random valid parking spot
  local parkingSpot = getRandomParkingSpot()
  if not parkingSpot then
    log("W", "No valid parking spots available for job generation")
    return nil
  end

  -- Mark this spot as used
  if parkingSpot.name then
    usedSpotNames[parkingSpot.name] = true
  end

  -- Determine area from position
  local area = getAreaFromPosition(parkingSpot.pos)

  -- Pick random vehicle based on weighted tiers
  local tierRoll = math.random()
  local targetTier
  if tierRoll < 0.5 then
    targetTier = 1  -- 50% economy
  elseif tierRoll < 0.85 then
    targetTier = 2  -- 35% mid-range
  else
    targetTier = 3  -- 15% high-end
  end

  -- Get random vehicle from dynamic pool
  local vehicle = getRandomVehicleForTier(targetTier)
  if not vehicle then
    log("E", "No eligible vehicles available")
    -- Release spot
    if parkingSpot.name then
      usedSpotNames[parkingSpot.name] = nil
    end
    return nil
  end

  local vehicleValue = vehicle.value
  local fee = generateFee(vehicleValue)

  local job = {
    id = nextJobId,
    state = JOB_STATE.AVAILABLE,

    -- Vehicle info
    model = vehicle.model,
    configKey = vehicle.configKey,  -- Config key for spawning specific variant
    vehicleName = vehicle.name,
    vehicleValue = vehicleValue,
    tier = vehicle.tier,

    -- Location info (from parking spot)
    spotName = parkingSpot.name,
    area = area,
    description = parkingSpot.name or ("Parking in " .. area),
    exactPos = parkingSpot.pos,
    exactRot = parkingSpot.rot or quat(0, 0, 0, 1),

    -- Fee info (scam potential!)
    fee = fee,
    isScam = fee > vehicleValue,

    -- State tracking
    spawnedVehId = nil,
    createdTime = os.time(),
    expiresTime = os.time() + 3600,  -- Jobs expire after 1 hour

    -- Contact message flavor
    contactMessage = nil  -- Will be set by phoneApp
  }

  nextJobId = nextJobId + 1
  activeJobs[job.id] = job

  log("I", string.format("Generated job #%d: %s in %s (value: $%d, fee: $%d%s)",
    job.id, vehicle.name, area, vehicleValue, fee, job.isScam and " SCAM!" or ""))

  return job
end

---------------------------------------------------------------------------
-- Job State Management
---------------------------------------------------------------------------

local function unlockJob(jobId)
  local job = activeJobs[jobId]
  if not job then
    log("E", "Job not found: " .. tostring(jobId))
    return false, "Job not found"
  end

  if job.state ~= JOB_STATE.AVAILABLE then
    log("E", "Job not available: " .. tostring(jobId))
    return false, "Job not available"
  end

  -- Check if player already has an active job (prevent accepting two jobs)
  for _, existingJob in pairs(activeJobs) do
    if existingJob.id ~= jobId and
       (existingJob.state == JOB_STATE.UNLOCKED or
        existingJob.state == JOB_STATE.SPAWNED or
        existingJob.state == JOB_STATE.ACTIVE) then
      log("E", "Already have an active job: #" .. existingJob.id)
      return false, "Complete your current job first"
    end
  end

  -- Check player has enough money
  if career_modules_playerAttributes then
    local money = career_modules_playerAttributes.getAttribute("money")
    if money and money.value < job.fee then
      log("E", "Not enough money for job: " .. tostring(jobId))
      return false, "Not enough money"
    end
  end

  -- Deduct fee
  if career_modules_payment and career_modules_payment.pay then
    career_modules_payment.pay({
      money = {amount = job.fee, canBeNegative = false}
    }, {
      label = "Hot Wheels - Location Info",
      tags = {"gameplay", "carTheft", "fee"}
    })
  end

  job.state = JOB_STATE.UNLOCKED
  log("I", string.format("Job #%d unlocked. Fee paid: $%d", jobId, job.fee))

  -- Send update to UI
  M.sendJobsUpdate()

  return true, "Location unlocked"
end

local function startJob(jobId)
  local job = activeJobs[jobId]
  if not job then return false end

  if job.state ~= JOB_STATE.SPAWNED then
    log("E", "Job vehicle not spawned yet")
    return false
  end

  job.state = JOB_STATE.ACTIVE
  log("I", "Job #" .. jobId .. " is now active (player stealing)")

  M.sendJobsUpdate()
  return true
end

local function completeJob(jobId, success)
  local job = activeJobs[jobId]
  if not job then return end

  if success then
    job.state = JOB_STATE.COMPLETED
    table.insert(completedJobIds, jobId)
    -- Prune old entries to prevent memory leak
    while #completedJobIds > MAX_COMPLETED_JOBS do
      table.remove(completedJobIds, 1)
    end
    log("I", "Job #" .. jobId .. " completed successfully!")
  else
    job.state = JOB_STATE.FAILED
    log("I", "Job #" .. jobId .. " failed")
  end

  -- Release the parking spot
  if job.spotName then
    usedSpotNames[job.spotName] = nil
  end

  -- Clean up spawned vehicle reference
  job.spawnedVehId = nil

  -- Remove from active jobs immediately to prevent memory issues
  activeJobs[jobId] = nil

  M.sendJobsUpdate()
end

local function expireJob(jobId)
  local job = activeJobs[jobId]
  if not job then return end

  -- Only expire if not already in progress
  if job.state == JOB_STATE.AVAILABLE or job.state == JOB_STATE.UNLOCKED then
    job.state = JOB_STATE.EXPIRED
    log("I", "Job #" .. jobId .. " expired")

    -- Release the parking spot
    if job.spotName then
      usedSpotNames[job.spotName] = nil
    end

    -- Despawn vehicle if it was spawned
    if job.spawnedVehId then
      local vehObj = be:getObjectByID(job.spawnedVehId)
      if vehObj then
        vehObj:delete()
      end
      job.spawnedVehId = nil
    end

    -- Remove immediately to prevent memory issues
    activeJobs[jobId] = nil

    M.sendJobsUpdate()
  end
end

---------------------------------------------------------------------------
-- Proximity-Based Spawning
---------------------------------------------------------------------------

local SPAWN_DISTANCE = 500    -- Spawn when player within 500m
local DESPAWN_DISTANCE = 600  -- Despawn when player beyond 600m (hysteresis)

local function spawnJobVehicle(job)
  if job.spawnedVehId then
    log("D", "Vehicle already spawned for job #" .. job.id)
    return
  end

  local spawnOptions = {
    pos = job.exactPos,
    rot = job.exactRot or quat(0, 0, 0, 1),
    autoEnterVehicle = false,
    vehicleName = "theft_job_" .. job.id
  }

  -- Use specific config if available
  if job.configKey then
    spawnOptions.config = job.configKey
  end

  log("I", string.format("Spawning job vehicle: %s (%s) at %s", job.model, job.configKey or "default", tostring(job.exactPos)))

  local vehObj = core_vehicles.spawnNewVehicle(job.model, spawnOptions)
  if vehObj then
    local vehId = vehObj:getID()
    job.spawnedVehId = vehId
    job.state = JOB_STATE.SPAWNED

    -- Lock the vehicle and turn off engine
    vehObj:queueLuaCommand('controller.mainController.setEngineIgnition(false)')
    vehObj.playerUsable = false

    -- Register with main module as stealable
    if extensions.carTheft_main then
      -- The main module will detect this via our hook
    end

    log("I", "Job vehicle spawned: ID " .. vehId)
  else
    log("E", "Failed to spawn job vehicle")
  end
end

local function despawnJobVehicle(job)
  if not job.spawnedVehId then return end

  local vehObj = be:getObjectByID(job.spawnedVehId)
  if vehObj then
    vehObj:delete()
    log("I", "Despawned job vehicle for job #" .. job.id)
  end

  job.spawnedVehId = nil
  job.state = JOB_STATE.UNLOCKED  -- Back to unlocked, can spawn again
end

local function updateProximitySpawning()
  local playerPos = getPlayerPos()
  if not playerPos then return end

  for jobId, job in pairs(activeJobs) do
    -- Only handle unlocked/spawned jobs
    if job.state == JOB_STATE.UNLOCKED then
      -- Check if player is close enough to spawn
      local dist = playerPos:distance(job.exactPos)
      if dist < SPAWN_DISTANCE then
        spawnJobVehicle(job)
      end

    elseif job.state == JOB_STATE.SPAWNED then
      -- Check if player moved too far (despawn)
      local dist = playerPos:distance(job.exactPos)
      if dist > DESPAWN_DISTANCE then
        despawnJobVehicle(job)
      end
    end
  end
end

---------------------------------------------------------------------------
-- Job Expiration Check
---------------------------------------------------------------------------

local function checkJobExpiration()
  local currentTime = os.time()

  for jobId, job in pairs(activeJobs) do
    if job.expiresTime and currentTime > job.expiresTime then
      expireJob(jobId)
    end
  end
end

---------------------------------------------------------------------------
-- Update Loop (called from main.lua)
---------------------------------------------------------------------------

local function onUpdate(dtReal, dtSim, dtRaw)
  -- Only run in career mode
  if not career_career or not career_career.isActive() then
    return
  end

  -- Generate new jobs periodically
  local currentTime = os.time()
  if currentTime - lastJobGenerationTime > JOB_GENERATION_INTERVAL then
    lastJobGenerationTime = currentTime
    generateJob()
  end

  -- Update proximity spawning
  updateProximitySpawning()

  -- Check for expired jobs
  checkJobExpiration()
end

---------------------------------------------------------------------------
-- UI Integration
---------------------------------------------------------------------------

function M.sendJobsUpdate()
  local jobList = {}

  for jobId, job in pairs(activeJobs) do
    -- Hide vehicle details until job is unlocked
    local isLocked = job.state == JOB_STATE.AVAILABLE
    table.insert(jobList, {
      id = job.id,
      state = job.state,
      vehicleName = isLocked and "???" or job.vehicleName,
      vehicleValue = isLocked and nil or job.vehicleValue,
      tier = job.tier,
      area = job.area,
      description = job.description,
      fee = job.fee,
      -- Only include exact location if unlocked
      exactPos = (not isLocked) and job.exactPos or nil,
      expiresIn = job.expiresTime - os.time(),
      contactMessage = job.contactMessage
    })
  end

  guihooks.trigger('hotWheelsJobsUpdate', {
    jobs = jobList,
    completedCount = #completedJobIds
  })
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

-- Get all active jobs (for phone app)
function M.getActiveJobs()
  return activeJobs
end

-- Get a specific job
function M.getJob(jobId)
  return activeJobs[jobId]
end

-- Unlock a job (pay fee, reveal location)
function M.unlockJob(jobId)
  return unlockJob(jobId)
end

-- Set GPS to job location
function M.setJobGPS(jobId)
  local job = activeJobs[jobId]
  if job and job.exactPos then
    if core_groundMarkers and core_groundMarkers.setPath then
      core_groundMarkers.setPath(job.exactPos)
      if ui_message then
        ui_message("GPS set to " .. (job.vehicleName or "target"), 2, "info")
      end
      return true
    end
  end
  return false
end

-- Mark job as being stolen (called from main.lua)
function M.startJob(jobId)
  return startJob(jobId)
end

-- Mark job complete (called from main.lua)
function M.completeJob(jobId, success)
  return completeJob(jobId, success)
end

-- Get job by spawned vehicle ID
function M.getJobByVehicleId(vehId)
  for _, job in pairs(activeJobs) do
    if job.spawnedVehId == vehId then
      return job
    end
  end
  return nil
end

-- Check if a vehicle belongs to a job
function M.isJobVehicle(vehId)
  return M.getJobByVehicleId(vehId) ~= nil
end

-- Generate initial jobs when app is installed
function M.generateInitialJobs(count)
  count = count or 3
  log("I", "Generating " .. count .. " initial jobs")
  for i = 1, count do
    generateJob()
  end
  M.sendJobsUpdate()
end

-- Force generate a job (for testing)
function M.forceGenerateJob()
  local job = generateJob()
  M.sendJobsUpdate()
  return job
end

-- Get stats
function M.getStats()
  local available = 0
  local unlocked = 0
  local spawned = 0
  local active = 0

  for _, job in pairs(activeJobs) do
    if job.state == JOB_STATE.AVAILABLE then available = available + 1
    elseif job.state == JOB_STATE.UNLOCKED then unlocked = unlocked + 1
    elseif job.state == JOB_STATE.SPAWNED then spawned = spawned + 1
    elseif job.state == JOB_STATE.ACTIVE then active = active + 1
    end
  end

  return {
    available = available,
    unlocked = unlocked,
    spawned = spawned,
    active = active,
    completed = #completedJobIds
  }
end

-- Get jobs formatted for AngularJS UI (returns array, not table)
function M.getJobsForUI()
  local jobList = {}

  for jobId, job in pairs(activeJobs) do
    -- Hide vehicle details until job is unlocked
    local isLocked = job.state == JOB_STATE.AVAILABLE
    table.insert(jobList, {
      id = job.id,
      state = job.state,
      vehicleName = isLocked and "???" or job.vehicleName,
      vehicleValue = isLocked and nil or job.vehicleValue,
      tier = job.tier,
      area = job.area,
      description = job.description,
      fee = job.fee,
      expiresIn = job.expiresTime - os.time()
    })
  end

  -- Sort by tier (highest first)
  table.sort(jobList, function(a, b)
    return (a.tier or 1) > (b.tier or 1)
  end)

  return jobList
end

---------------------------------------------------------------------------
-- Save/Load State
---------------------------------------------------------------------------

function M.getSaveData()
  -- Save active jobs that are in progress (so player doesn't lose money on crash)
  local savedJobs = {}
  for jobId, job in pairs(activeJobs) do
    if job.state == JOB_STATE.UNLOCKED or
       job.state == JOB_STATE.SPAWNED or
       job.state == JOB_STATE.ACTIVE then
      -- Save job data (without runtime-only fields)
      savedJobs[jobId] = {
        id = job.id,
        state = job.state,
        model = job.model,
        configKey = job.configKey,
        vehicleName = job.vehicleName,
        vehicleValue = job.vehicleValue,
        tier = job.tier,
        spotName = job.spotName,
        area = job.area,
        description = job.description,
        exactPos = job.exactPos and {x = job.exactPos.x, y = job.exactPos.y, z = job.exactPos.z} or nil,
        exactRot = job.exactRot and {x = job.exactRot.x, y = job.exactRot.y, z = job.exactRot.z, w = job.exactRot.w} or nil,
        fee = job.fee,
        createdTime = job.createdTime,
        expiresTime = job.expiresTime,
      }
    end
  end

  return {
    nextJobId = nextJobId,
    completedJobIds = completedJobIds,
    savedJobs = savedJobs,
    usedSpotNames = usedSpotNames,
  }
end

function M.loadSaveData(data)
  if data then
    nextJobId = data.nextJobId or 1
    completedJobIds = data.completedJobIds or {}
    usedSpotNames = data.usedSpotNames or {}

    -- Restore saved jobs
    if data.savedJobs then
      for jobId, savedJob in pairs(data.savedJobs) do
        -- Reconstruct position and rotation
        local pos = savedJob.exactPos and vec3(savedJob.exactPos.x, savedJob.exactPos.y, savedJob.exactPos.z) or nil
        local rot = savedJob.exactRot and quat(savedJob.exactRot.x, savedJob.exactRot.y, savedJob.exactRot.z, savedJob.exactRot.w) or nil

        activeJobs[tonumber(jobId)] = {
          id = savedJob.id,
          state = savedJob.state,
          model = savedJob.model,
          configKey = savedJob.configKey,
          vehicleName = savedJob.vehicleName,
          vehicleValue = savedJob.vehicleValue,
          tier = savedJob.tier,
          spotName = savedJob.spotName,
          area = savedJob.area,
          description = savedJob.description,
          exactPos = pos,
          exactRot = rot,
          fee = savedJob.fee,
          createdTime = savedJob.createdTime,
          expiresTime = savedJob.expiresTime,
          spawnedVehId = nil,  -- Will be re-spawned when player approaches
        }
        log("I", "Restored saved job #" .. savedJob.id .. ": " .. savedJob.vehicleName)
      end
    end
  end
end

-- Get the current active job (for main.lua to restore)
function M.getActiveInProgressJob()
  for _, job in pairs(activeJobs) do
    if job.state == JOB_STATE.UNLOCKED or
       job.state == JOB_STATE.SPAWNED or
       job.state == JOB_STATE.ACTIVE then
      return job
    end
  end
  return nil
end

---------------------------------------------------------------------------
-- Extension Hooks
---------------------------------------------------------------------------

function M.onExtensionLoaded()
  log("I", "Job Manager loaded")
end

function M.onExtensionUnloaded()
  -- Clean up all spawned vehicles
  for _, job in pairs(activeJobs) do
    if job.spawnedVehId then
      local vehObj = be:getObjectByID(job.spawnedVehId)
      if vehObj then
        vehObj:delete()
      end
    end
  end
  activeJobs = {}
  clearParkingCache()
  log("I", "Job Manager unloaded")
end

-- Called when level/mission starts
function M.onClientStartMission()
  log("I", "Level started, clearing parking cache")
  clearParkingCache()
end

-- Called when level/mission ends
function M.onClientEndMission()
  log("I", "Level ended, clearing jobs and cache")
  -- Clean up all spawned vehicles
  for _, job in pairs(activeJobs) do
    if job.spawnedVehId then
      local vehObj = be:getObjectByID(job.spawnedVehId)
      if vehObj then
        vehObj:delete()
      end
    end
  end
  activeJobs = {}
  clearParkingCache()
  clearVehicleCache()
end

M.onUpdate = onUpdate
M.JOB_STATE = JOB_STATE

return M
