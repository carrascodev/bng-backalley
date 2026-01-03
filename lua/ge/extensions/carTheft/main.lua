-- Car Theft Career - Main Extension
-- Spawns stealable parked cars that players can steal and deliver to their garage

local M = {}

-- Logger module
local logger = require("carTheft/logger")
local LOG_TAG = "carTheft_main"

-- Reference to job manager (loaded lazily)
local jobManager = nil

local function getJobManager()
  if not jobManager then
    local success, mod = pcall(require, "carTheft/jobManager")
    if success then jobManager = mod end
  end
  return jobManager
end

-- Load configuration (use pcall in case it fails)
local configLoaded, config = pcall(require, "ge/extensions/carTheft/config")
if not configLoaded then
  log("E", "Failed to load carTheft config module")
end

-- State constants
local STATE = {
  IDLE = "idle",
  STEALING = "stealing",
  HOT = "hot",
  REPORTED = "reported",
  SUCCESS = "success",
  ARRESTED = "arrested"
}

-- Active theft job state
local theftJob = {
  state = STATE.IDLE,
  targetVehId = nil,
  originalVehId = nil,
  hotwireTimer = 0,
  reportTimer = 0,
  escalationTimer = 0,
  escalationLevel = 0,
  targetGarageId = nil,
  targetGaragePos = nil,
  vehicleValue = 0,
  marker = nil,
  activeJobId = nil  -- Job ID from jobManager if this is a job vehicle
}

-- Track spawned stealable vehicles (our own cars, not traffic)
local spawnedStealableVehicles = {}

-- Note: Document processing and heat are now stored on vehicle inventory data
-- See: veh.pendingDocTier, veh.pendingDocRemainingSeconds, veh.pendingDocRequiredHours, veh.pendingDocReady
-- See: veh.heatLevel, veh.heatLastUpdate

-- Police inspection cooldown
local lastInspectionTime = 0

-- Debug: multiplier for police detection (1 = normal, 100 = 100x more likely)
local debugDetectionMultiplier = 1

-- Track inventory ID of vehicle detected by police inspection
local inspectedVehicleInventoryId = nil
local confiscationInProgress = false

-- Cached references
local nearbyVehicle = nil
local nearbyVehicleDistance = math.huge

-- Forward declarations
local resetTheftJob
local sendUIUpdate

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
  -- If in walking mode, get unicycle position
  if gameplay_walk and gameplay_walk.isWalking() then
    local unicycle = scenetree.findObject("unicycle")
    if unicycle then
      return unicycle:getPosition()
    end
  end
  return nil
end

local function getVehicleValue(vehId)
  local vehicleData = core_vehicle_manager.getVehicleData(vehId)
  if vehicleData and vehicleData.config then
    local vehicle = be:getObjectByID(vehId)
    if vehicle and vehicle.JBeam and vehicleData.config.partConfigFilename then
      local dir, configName, ext = path.splitWithoutExt(vehicleData.config.partConfigFilename)
      local baseConfig = core_vehicles.getConfig(vehicle.JBeam, configName)
      if baseConfig and baseConfig.Value then
        return baseConfig.Value
      end
    end
  end
  return 10000
end

local function calculateReportTime(vehicleValue)
  local valueFactor = math.min(1, vehicleValue / 100000) * config.REPORT_TIME_VALUE_FACTOR
  local reportTime = config.REPORT_TIME_MAX - (config.REPORT_TIME_MAX - config.REPORT_TIME_MIN) * valueFactor
  return reportTime
end

---------------------------------------------------------------------------
-- Spawned Vehicle Management
---------------------------------------------------------------------------

-- Spawn a stealable vehicle at a position
local function spawnStealableVehicle(model, configPath, pos, rot)
  model = model or "covet"
  pos = pos or getPlayerPos()
  if not pos then
    log("E", "Cannot spawn vehicle: no position")
    return nil
  end

  -- Offset position slightly in front if spawning near player
  if not rot then
    rot = quat(0, 0, 0, 1)
  end

  local spawnOptions = {
    pos = pos,
    rot = rot,
    autoEnterVehicle = false,
    vehicleName = "stealable_" .. tostring(os.time())
  }

  if configPath then
    spawnOptions.config = configPath
  end

  log("I", "Spawning stealable vehicle: " .. model .. " at " .. tostring(pos))

  local vehObj = core_vehicles.spawnNewVehicle(model, spawnOptions)
  if vehObj then
    local vehId = vehObj:getID()

    -- Track this as a stealable vehicle
    spawnedStealableVehicles[vehId] = {
      id = vehId,
      model = model,
      spawnTime = os.time(),
      value = 10000 -- Will be updated once vehicle is ready
    }

    -- Turn off engine and lock the vehicle (can't enter with F until stolen)
    vehObj:queueLuaCommand('controller.mainController.setEngineIgnition(false)')
    vehObj.playerUsable = false  -- LOCKED - must steal via radial menu

    log("I", "Spawned stealable vehicle ID: " .. tostring(vehId))
    ui_message("Stealable vehicle spawned: " .. model, 3, "info")

    return vehId
  else
    log("E", "Failed to spawn vehicle")
    return nil
  end
end

-- Remove a stealable vehicle from tracking
local function removeStealableVehicle(vehId)
  if spawnedStealableVehicles[vehId] then
    spawnedStealableVehicles[vehId] = nil
    log("I", "Removed stealable vehicle from tracking: " .. tostring(vehId))
  end
end

-- Check if a vehicle is one of our stealable vehicles (manual spawn OR job vehicle)
local function isStealableVehicle(vehId)
  -- Check manually spawned vehicles
  if spawnedStealableVehicles[vehId] then
    return true
  end
  -- Check job manager vehicles
  local jm = getJobManager()
  if jm and jm.isJobVehicle and jm.isJobVehicle(vehId) then
    return true
  end
  return false
end

-- Get all spawned stealable vehicles
local function getSpawnedStealableVehicles()
  return spawnedStealableVehicles
end

---------------------------------------------------------------------------
-- Garage Functions
---------------------------------------------------------------------------

local function getZoneCenter(zones)
  if not zones or #zones == 0 then return nil end

  local xMin, xMax = math.huge, -math.huge
  local yMin, yMax = math.huge, -math.huge
  local zMin, zMax = math.huge, -math.huge
  local hasVertices = false

  for _, zone in ipairs(zones) do
    if zone.vertices then
      for _, v in ipairs(zone.vertices) do
        if v.pos then
          xMin = math.min(xMin, v.pos.x)
          xMax = math.max(xMax, v.pos.x)
          yMin = math.min(yMin, v.pos.y)
          yMax = math.max(yMax, v.pos.y)
          zMin = math.min(zMin, v.pos.z)
          zMax = math.max(zMax, v.pos.z)
          hasVertices = true
        end
      end
    end
  end

  if hasVertices then
    return vec3((xMin + xMax)/2, (yMin + yMax)/2, (zMin + zMax)/2)
  end
  return nil
end

local function findNearestOwnedGarage()
  if not career_modules_garageManager then return nil, nil end

  local purchasedGarages = career_modules_garageManager.getPurchasedGarages()
  if not purchasedGarages or #purchasedGarages == 0 then
    return nil, nil
  end

  local playerPos = getPlayerPos()
  if not playerPos then return nil, nil end

  local nearestId = nil
  local nearestPos = nil
  local nearestDist = math.huge

  for _, garageId in ipairs(purchasedGarages) do
    local facility = freeroam_facilities.getFacility("garage", garageId)
    if facility then
      local zones = freeroam_facilities.getZonesForFacility(facility)
      local garagePos = getZoneCenter(zones)
      if garagePos then
        local dist = playerPos:distance(garagePos)
        if dist < nearestDist then
          nearestDist = dist
          nearestId = garageId
          nearestPos = garagePos
        end
      end
    end
  end

  return nearestId, nearestPos
end

local function isPlayerInGarage(garageId)
  if not garageId then return false end

  local playerPos = getPlayerPos()
  if not playerPos then return false end

  local facility = freeroam_facilities.getFacility("garage", garageId)
  if not facility then return false end

  local zones = freeroam_facilities.getZonesForFacility(facility)
  if zones then
    for _, zone in ipairs(zones) do
      if zone.containsPoint2D and zone:containsPoint2D(playerPos) then
        return true
      end
    end
  end

  return false
end

---------------------------------------------------------------------------
-- Marker Functions
---------------------------------------------------------------------------

local function createGarageMarker(position)
  if theftJob.marker then
    theftJob.marker:delete()
  end

  theftJob.marker = createObject('TSStatic')
  theftJob.marker.shapeName = "art/shapes/interface/checkpoint_marker.dae"
  theftJob.marker.scale = vec3(4, 4, 4)
  theftJob.marker.useInstanceRenderData = true
  theftJob.marker.instanceColor = ColorF(0, 0.8, 0.2, 0.7):asLinear4F()
  theftJob.marker:setPosition(position)
  theftJob.marker:registerObject("car_theft_garage_marker")
end

local function removeGarageMarker()
  if theftJob.marker then
    pcall(function()
      theftJob.marker:unregisterObject()
      theftJob.marker:delete()
    end)
    theftJob.marker = nil
  end
end

local function setNavigationPath(position)
  if core_groundMarkers then
    core_groundMarkers.setPath(position)
  end
end

local function clearNavigationPath()
  if core_groundMarkers then
    core_groundMarkers.resetAll()
  end
end

---------------------------------------------------------------------------
-- Vehicle Detection (Only our spawned stealable vehicles)
---------------------------------------------------------------------------

local function findNearbyStealableVehicle()
  if not gameplay_walk or not gameplay_walk.isWalking() then
    return nil, math.huge
  end

  local playerPos = getPlayerPos()
  if not playerPos then
    return nil, math.huge
  end

  local closestVehId = nil
  local closestDist = math.huge

  -- Check our spawned stealable vehicles
  for vehId, vehData in pairs(spawnedStealableVehicles) do
    local vehObj = be:getObjectByID(vehId)
    if vehObj then
      local vehPos = vehObj:getPosition()
      local dist = playerPos:distance(vehPos)

      if dist < config.PROXIMITY_DISTANCE and dist < closestDist then
        closestDist = dist
        closestVehId = vehId
      end
    else
      -- Vehicle was deleted externally, clean up
      spawnedStealableVehicles[vehId] = nil
    end
  end

  -- Also check job manager vehicles
  local jm = getJobManager()
  if jm and jm.getActiveJobs then
    local jobs = jm.getActiveJobs()
    for _, job in pairs(jobs) do
      if job.spawnedVehId and (job.state == "spawned" or job.state == "active") then
        local vehObj = be:getObjectByID(job.spawnedVehId)
        if vehObj then
          local vehPos = vehObj:getPosition()
          local dist = playerPos:distance(vehPos)

          if dist < config.PROXIMITY_DISTANCE and dist < closestDist then
            closestDist = dist
            closestVehId = job.spawnedVehId
          end
        end
      end
    end
  end

  return closestVehId, closestDist
end

---------------------------------------------------------------------------
-- Stealing Logic
---------------------------------------------------------------------------

local function startStealing(vehId)
  if theftJob.state ~= STATE.IDLE then
    return false
  end

  -- Check if it's one of our stealable vehicles
  if not isStealableVehicle(vehId) then
    log("E", "Vehicle " .. tostring(vehId) .. " is not a stealable vehicle")
    return false
  end

  local garageId, garagePos = findNearestOwnedGarage()
  if not garageId then
    ui_message("You need to own a garage first!", 5, "error")
    return false
  end

  log("I", "Starting to steal vehicle " .. tostring(vehId))

  -- Check if this is a job vehicle and get its value
  local jm = getJobManager()
  local job = jm and jm.getJobByVehicleId and jm.getJobByVehicleId(vehId)

  theftJob.state = STATE.STEALING
  theftJob.targetVehId = vehId
  theftJob.hotwireTimer = config.HOTWIRE_TIME
  theftJob.vehicleValue = job and job.vehicleValue or getVehicleValue(vehId)
  theftJob.targetGarageId = garageId
  theftJob.targetGaragePos = garagePos
  theftJob.activeJobId = job and job.id or nil  -- Track the job ID

  -- Notify job manager
  if job and jm.startJob then
    jm.startJob(job.id)
  end

  ui_message("Hotwiring vehicle...", config.HOTWIRE_TIME, "info")

  return true
end

local function completeStealing()
  log("I", "Completed stealing, entering vehicle")

  local vehObj = be:getObjectByID(theftJob.targetVehId)
  if not vehObj then
    log("E", "Vehicle disappeared during steal")
    resetTheftJob()
    return
  end

  -- Store original vehicle (unicycle when walking)
  theftJob.originalVehId = be:getPlayerVehicleID(0)

  -- UNLOCK the vehicle so player can enter/control it
  vehObj.playerUsable = true

  -- Enter the vehicle - use gameplay_walk.getInVehicle if walking
  if gameplay_walk and gameplay_walk.isWalking() then
    gameplay_walk.getInVehicle(vehObj)
  else
    be:enterVehicle(0, vehObj)
  end

  -- Remove from our stealable tracking (it's now being stolen)
  removeStealableVehicle(theftJob.targetVehId)

  -- Calculate report time
  local reportTime = calculateReportTime(theftJob.vehicleValue)

  -- Transition to HOT state
  theftJob.state = STATE.HOT
  theftJob.hotwireTimer = 0
  theftJob.reportTimer = reportTime
  theftJob.escalationTimer = 0
  theftJob.escalationLevel = 0

  -- Set up navigation
  if theftJob.targetGaragePos then
    createGarageMarker(theftJob.targetGaragePos)
    setNavigationPath(theftJob.targetGaragePos)
  end

  ui_message("Vehicle stolen!. Get to your garage before the police come", 5, "warning")

  sendUIUpdate()
end

---------------------------------------------------------------------------
-- Police Escalation
---------------------------------------------------------------------------

local function triggerPoliceResponse()
  log("I", "Vehicle reported! Police are responding IMMEDIATELY")

  theftJob.state = STATE.REPORTED
  theftJob.escalationLevel = 1

  local vehId = be:getPlayerVehicleID(0)
  if gameplay_traffic then
    -- Insert into traffic system for pursuit tracking
    gameplay_traffic.insertTraffic(vehId, true)

    local trafficData = gameplay_traffic.getTrafficData()
    if trafficData and trafficData[vehId] then
      trafficData[vehId].pursuit = trafficData[vehId].pursuit or {}
      trafficData[vehId].pursuit.mode = 1
      trafficData[vehId].pursuit.score = config.INITIAL_PURSUIT_SCORE
      trafficData[vehId].pursuit.timers = trafficData[vehId].pursuit.timers or {}
      trafficData[vehId].pursuit.timers.main = 0  -- Reset timer for immediate response
    end

    -- Try to trigger immediate police attention by setting high offenses
    if gameplay_traffic.setTrafficVars then
      gameplay_traffic.setTrafficVars({enableRandomEvents = true})
    end
  end

  ui_message("STOLEN VEHICLE REPORTED! Police responding!", 5, "error")
  sendUIUpdate()
end

local function escalatePoliceResponse()
  local vehId = be:getPlayerVehicleID(0)
  local trafficData = gameplay_traffic and gameplay_traffic.getTrafficData()

  if theftJob.escalationTimer >= config.ESCALATION_LEVEL3_TIME and theftJob.escalationLevel < 3 then
    theftJob.escalationLevel = 3
    log("I", "Escalation level 3: Roadblocks!")
    ui_message("Roadblocks are being set up!", 3, "error")

    if trafficData and trafficData[vehId] and trafficData[vehId].pursuit then
      trafficData[vehId].pursuit.score = config.LEVEL3_PURSUIT_SCORE
    end

  elseif theftJob.escalationTimer >= config.ESCALATION_LEVEL2_TIME and theftJob.escalationLevel < 2 then
    theftJob.escalationLevel = 2
    log("I", "Escalation level 2: More units responding")
    ui_message("Additional units responding!", 3, "warning")

    if trafficData and trafficData[vehId] and trafficData[vehId].pursuit then
      trafficData[vehId].pursuit.score = config.LEVEL2_PURSUIT_SCORE
    end
  end

  sendUIUpdate()
end

---------------------------------------------------------------------------
-- Success/Failure Handling
---------------------------------------------------------------------------

local function completeSuccess()
  log("I", "Theft successful! Vehicle delivered to garage")
  theftJob.state = STATE.SUCCESS

  local vehId = be:getPlayerVehicleID(0)

  -- Add vehicle to player's inventory (the car IS the reward, no cash)
  if career_modules_inventory then
    local inventoryId = career_modules_inventory.addVehicle(vehId, nil, {owned = true})
    if inventoryId then
      -- Mark vehicle as stolen (no documents = can't sell legit or insure)
      local vehicles = career_modules_inventory.getVehicles()
      if vehicles and vehicles[inventoryId] then
        vehicles[inventoryId].isStolen = true
        vehicles[inventoryId].hasDocuments = false
        vehicles[inventoryId].stolenDate = os.time()
        log("I", "Marked vehicle as stolen: inventoryId=" .. tostring(inventoryId))

        -- Initialize heat for this vehicle
        M.initVehicleHeat(inventoryId)
      end

      -- Ensure stolen vehicle has insuranceId set to -1 (uninsured) for rls_career compatibility
      -- This prevents nil errors in the insurance module
      if career_modules_insurance_insurance then
        -- Try to set insurance to uninsured (-1) - the insurance module will handle it
        local success = pcall(function()
          career_modules_insurance_insurance.changeInvVehInsurance(inventoryId, -1)
        end)
        if not success then
          log("W", "Could not set insurance for stolen vehicle, but continuing anyway")
        end
      end

      if career_modules_inventory.moveVehicleToGarage then
        career_modules_inventory.moveVehicleToGarage(inventoryId, theftJob.targetGarageId)
      end
    end
    log("I", "Vehicle added to inventory: " .. tostring(inventoryId))
  end

  -- Notify job manager and phone app
  if theftJob.activeJobId then
    local jm = getJobManager()
    if jm and jm.completeJob then
      jm.completeJob(theftJob.activeJobId, true)
    end
  end

  ui_message("Success Stealing, car is now yours!", 8, "success")

  removeGarageMarker()
  clearNavigationPath()

  theftJob.state = STATE.IDLE
  resetTheftJob()
end

-- Confiscate a stolen vehicle when caught by police (outside of active theft)
local function confiscateVehicle(inventoryId, reason)
  log("I", "Confiscating vehicle: " .. tostring(inventoryId))

  -- Get vehicle value for fine calculation
  local vehicles = career_modules_inventory and career_modules_inventory.getVehicles()
  local vehValue = 0
  if vehicles and vehicles[inventoryId] then
    vehValue = vehicles[inventoryId].value or 0
  end

  -- Calculate and charge fine
  local fine = math.min(config.FINE_BASE + math.floor(vehValue * config.FINE_PERCENT), config.FINE_MAX)
  if career_modules_payment and career_modules_payment.pay then
    career_modules_payment.pay({
      money = {amount = fine, canBeNegative = true}
    }, {
      label = "Police confiscation fine",
      tags = {"gameplay", "carTheft", "fine"}
    })
  end

  -- Remove from inventory (heat and pending docs are stored on vehicle, so they go with it)
  if career_modules_inventory and career_modules_inventory.removeVehicle then
    career_modules_inventory.removeVehicle(inventoryId)
    log("I", "Vehicle removed from inventory: " .. tostring(inventoryId))
  end

  -- Delete vehicle from world and put player on foot
  local playerVehId = be:getPlayerVehicleID(0)
  if playerVehId then
    local veh = be:getObjectByID(playerVehId)
    if veh then
      local exitPos = veh:getPosition()

      -- Properly sequence: exit vehicle, wait, then delete
      core_jobsystem.create(function(job)
        -- First exit the vehicle
        be:exitVehicle(0)
        job.sleep(0.3)

        -- Switch to walking mode
        gameplay_walk.setWalkingMode(true, exitPos)
        job.sleep(0.5)

        -- Now safe to delete the vehicle
        local vehToDelete = be:getObjectByID(playerVehId)
        if vehToDelete then
          vehToDelete:delete()
        end
      end)
    end
  end

  ui_message(reason .. " Fine: $" .. fine, 8, "error")
  inspectedVehicleInventoryId = nil
end

local function completeFailure(reason)
  log("I", "Theft failed: " .. reason)
  theftJob.state = STATE.ARRESTED

  local fine = config.FINE_BASE + math.floor(theftJob.vehicleValue * config.FINE_PERCENT)
  fine = math.min(config.FINE_MAX, fine)

  if career_modules_payment and career_modules_payment.pay then
    career_modules_payment.pay({
      money = {amount = fine, canBeNegative = true}
    }, {
      label = "Car theft fine",
      tags = {"gameplay", "carTheft", "fine"}
    })
  end

  -- Notify job manager and phone app
  if theftJob.activeJobId then
    local jm = getJobManager()
    if jm and jm.completeJob then
      jm.completeJob(theftJob.activeJobId, false)
    end
  end

  local vehId = be:getPlayerVehicleID(0)
  local stolenVehObj = vehId and be:getObjectByID(vehId)
  local originalVehObj = theftJob.originalVehId and be:getObjectByID(theftJob.originalVehId)

  -- Use job system to properly sequence the exit
  core_jobsystem.create(function(job)
    -- First, exit the current vehicle properly
    if stolenVehObj then
      -- Get position before exiting for walking spawn
      local exitPos = stolenVehObj:getPosition()

      -- Exit to walking mode first
      gameplay_walk.setWalkingMode(true, exitPos)
      job.sleep(0.5)

      -- Delete the stolen vehicle
      if stolenVehObj then
        stolenVehObj:delete()
      end
      job.sleep(0.3)
    end

    -- If player had an original vehicle, enter it
    if originalVehObj then
      be:enterVehicle(0, originalVehObj)
    end
  end)

  ui_message(reason .. " Fine: $" .. fine, 8, "error")

  removeGarageMarker()
  clearNavigationPath()

  -- Clear inspection tracking
  inspectedVehicleInventoryId = nil

  theftJob.state = STATE.IDLE
  resetTheftJob()
end

resetTheftJob = function()
  theftJob.state = STATE.IDLE
  theftJob.targetVehId = nil
  theftJob.originalVehId = nil
  theftJob.hotwireTimer = 0
  theftJob.reportTimer = 0
  theftJob.escalationTimer = 0
  theftJob.escalationLevel = 0
  theftJob.targetGarageId = nil
  theftJob.targetGaragePos = nil
  theftJob.vehicleValue = 0
  theftJob.activeJobId = nil

  removeGarageMarker()
  clearNavigationPath()
  sendUIUpdate()
end

---------------------------------------------------------------------------
-- UI Updates
---------------------------------------------------------------------------

sendUIUpdate = function()
  local uiData = {
    state = theftJob.state,
    reportTimer = theftJob.reportTimer,
    escalationLevel = theftJob.escalationLevel,
    vehicleValue = theftJob.vehicleValue,
    nearbyVehicle = nearbyVehicle,
    nearbyVehicleDistance = nearbyVehicleDistance,
    spawnedVehicleCount = 0
  }

  for _ in pairs(spawnedStealableVehicles) do
    uiData.spawnedVehicleCount = uiData.spawnedVehicleCount + 1
  end

  guihooks.trigger('carTheftUpdate', uiData)
end

---------------------------------------------------------------------------
-- Garage Computer Integration (onComputerAddFunctions hook)
---------------------------------------------------------------------------

local function onComputerAddFunctions(menuData, computerFunctions)
  -- Get job count for display
  local jm = getJobManager()
  local jobCount = 0
  if jm and jm.getActiveJobs then
    local jobs = jm.getActiveJobs()
    for _, job in pairs(jobs) do
      if job.state == "spawned" or job.state == "available" or job.state == "unlocked" then
        jobCount = jobCount + 1
      end
    end
  end

  -- Add "BackAlley.help" button that opens the browser-style UI
  local data = {
    id = "backalley",
    label = jobCount > 0 and ("BackAlley.help (" .. jobCount .. " jobs)") or "BackAlley.help",
    callback = function()
      -- Open the BackAlley Browser UI
      guihooks.trigger('ChangeState', {state = 'menu.backalley'})
    end,
    order = 50
  }

  computerFunctions.general[data.id] = data
end

---------------------------------------------------------------------------
-- Radial Menu Integration
---------------------------------------------------------------------------

local quickAccessInitialized = false
local pendingStealVehId = nil

local function onBeforeRadialOpened()
  if quickAccessInitialized then return end
  quickAccessInitialized = true

  -- Add "Steal Vehicle" option - only shows for our spawned stealable vehicles
  core_quickAccess.addEntry({
    level = "/root/sandbox/career/",
    generator = function(entries)
      if not career_career or not career_career.isActive() then return end
      if theftJob.state ~= STATE.IDLE then return end
      if not nearbyVehicle then return end

      -- Only show if it's one of our stealable vehicles
      if not isStealableVehicle(nearbyVehicle) then return end

      local vehValue = getVehicleValue(nearbyVehicle)
      local valueStr = string.format("$%d", vehValue)

      table.insert(entries, {
        title = "Steal Vehicle",
        icon = "radial_garage",
        priority = 50,
        subtitle = "Worth ~" .. valueStr,
        onSelect = function()
          pendingStealVehId = nearbyVehicle
          return {"hide"}
        end
      })
    end
  })

  -- Add "Challenge Racer" option for street encounters (from streetRacing module)
  core_quickAccess.addEntry({
    level = "/root/sandbox/career/",
    generator = function(entries)
      if not career_career or not career_career.isActive() then return end

      -- Check if streetRacing extension is loaded and has an active encounter
      local streetRacing = extensions.carTheft_streetRacing
      if not streetRacing then return end
      if not streetRacing.getActiveEncounter then return end
      if not streetRacing.isNearAdversary then return end

      local encounter = streetRacing.getActiveEncounter()
      if not encounter then return end

      -- Only show challenge option when player is close to adversary (within 15m)
      if not streetRacing.isNearAdversary() then return end

      -- Build subtitle with adversary info
      local subtitle = string.format("%s - %s", encounter.racerName or "Unknown", encounter.racerVehicle or "Unknown")

      -- Show challenge option with adversary info
      table.insert(entries, {
        title = "Challenge Racer",
        icon = "radial_flag",
        priority = 45,
        subtitle = subtitle,
        onSelect = function()
          return {"nested", "carTheft_racing_bet"}
        end
      })
    end
  })

  -- Add nested bet selection menu for street racing
  core_quickAccess.addEntry({
    level = "/root/sandbox/career/carTheft_racing_bet/",
    generator = function(entries)
      local streetRacing = extensions.carTheft_streetRacing
      if not streetRacing then return end

      local encounter = streetRacing.getActiveEncounter()
      if not encounter then return end

      local playerMoney = 0
      if career_modules_playerAttributes and career_modules_playerAttributes.getAttributeValue then
        playerMoney = career_modules_playerAttributes.getAttributeValue("money") or 0
      end

      -- Bet options
      local betOptions = {1000, 5000, 10000, 25000, 50000}

      for _, bet in ipairs(betOptions) do
        if bet <= playerMoney then
          table.insert(entries, {
            title = string.format("$%d", bet),
            icon = "radial_money",
            priority = 100 - bet/1000,
            subtitle = string.format("Win: $%d", bet * 2),
            onSelect = function()
              streetRacing.challengeEncounter(bet, false)
              return {"hide"}
            end
          })
        end
      end

      -- Pink slip option
      if encounter.allowPinkSlip then
        table.insert(entries, {
          title = "Pink Slip",
          icon = "radial_garage",
          priority = 10,
          subtitle = "Winner takes all!",
          onSelect = function()
            streetRacing.challengeEncounter(0, true)
            return {"hide"}
          end
        })
      end
    end
  })
end

local function onQuickAccessLoaded()
  quickAccessInitialized = false
end

---------------------------------------------------------------------------
-- Document Processing (game-time based)
---------------------------------------------------------------------------

-- Get current game time in seconds (uses BeamNG's time-of-day system)
local function getGameTimeSeconds()
  -- BeamNG tracks time as 0-1 representing 24 hours, plus a day counter
  if core_environment and core_environment.getTimeOfDay then
    local tod = core_environment.getTimeOfDay()
    if tod then
      local daySeconds = (tod.time or 0) * 86400  -- time is 0-1, convert to seconds in day
      local dayNumber = tod.day or 0
      return (dayNumber * 86400) + daySeconds
    end
  end
  -- Fallback to real time if game time unavailable
  return os.time()
end

-- Session-only tracking of last game time (not saved, resets each session)
local docTimerLastUpdate = {}

-- Update document processing timers using in-game time
local function updateDocumentTimers(dtSim)
  if not career_modules_inventory then return end
  local vehicles = career_modules_inventory.getVehicles()
  if not vehicles then return end

  local currentGameTime = getGameTimeSeconds()

  for invId, veh in pairs(vehicles) do
    -- Only process vehicles with pending documents
    if veh.isStolen and veh.pendingDocTier and not veh.pendingDocReady then
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
          log("I", "Documents ready for vehicle: " .. tostring(invId))
          if ui_message then
            ui_message("Your documents are ready for pickup!", 5, "success")
          end
        end
      end

      -- Update session tracker
      docTimerLastUpdate[invId] = currentGameTime
    end
  end
end

---------------------------------------------------------------------------
-- Heat & Police Systems (must be before onUpdate)
---------------------------------------------------------------------------

-- Update heat decay for all stolen vehicles (called from onUpdate)
local function updateVehicleHeat()
  if not career_modules_inventory then return end
  local vehicles = career_modules_inventory.getVehicles()
  if not vehicles then return end

  local cfg = config
  local currentGameTime = getGameTimeSeconds()
  local decayPerHour = cfg.HEAT_DECAY_PER_HOUR or 10
  local minHeat = cfg.HEAT_MIN or 10

  for invId, veh in pairs(vehicles) do
    -- Only process stolen vehicles with heat
    if veh.isStolen and veh.heatLevel and veh.heatLevel > 0 then
      local lastUpdate = veh.heatLastUpdate or currentGameTime
      local secondsPassed = currentGameTime - lastUpdate
      local hoursPassed = secondsPassed / 3600

      if hoursPassed > 0.01 then  -- Only update if meaningful time passed
        local decay = hoursPassed * decayPerHour
        veh.heatLevel = math.max(minHeat, veh.heatLevel - decay)
        veh.heatLastUpdate = currentGameTime
      end
    end
  end
end

-- Find nearby police vehicles
local function findNearbyPolice(range)
  local playerPos = getPlayerPos()
  if not playerPos then return nil end

  local playerVehId = be:getPlayerVehicleID(0)

  -- Check ALL vehicles for police-like ones
  for i = 0, be:getObjectCount() - 1 do
    local veh = be:getObject(i)
    if veh then
      local vehId = veh:getID()
      if vehId ~= playerVehId then  -- Not the player's vehicle
        local dist = (veh:getPosition() - playerPos):length()
        if dist < range then
          -- Check if it's a police vehicle by model name or traffic role
          local isPolice = false

          -- Check traffic data for police role
          if gameplay_traffic and gameplay_traffic.getTrafficData then
            local trafficData = gameplay_traffic.getTrafficData()
            if trafficData[vehId] and trafficData[vehId].role == "police" then
              isPolice = true
            end
          end

          -- Also check vehicle config for "police" keyword
          local vehData = core_vehicle_manager.getVehicleData(vehId)
          if vehData and vehData.config then
            local configFilename = vehData.config.partConfigFilename or ""
            local model = vehData.config.model or ""
            local checkStr = (configFilename .. " " .. model):lower()
            if checkStr:find("police") or checkStr:find("cop") or checkStr:find("patrol") then
              isPolice = true
            end
          end

          if isPolice then
            return vehId, dist
          end
        end
      end
    end
  end

  return nil
end

-- Get the current player's vehicle inventory ID (if driving a stolen car)
local function getPlayerStolenVehicleInfo()
  local playerVehId = be:getPlayerVehicleID(0)
  if not playerVehId then return nil end

  -- Check if this vehicle is in our inventory
  if not career_modules_inventory then return nil end

  -- Get inventory ID from the spawned vehicle ID
  local inventoryId = career_modules_inventory.getInventoryIdFromVehicleId(playerVehId)
  if not inventoryId then return nil end

  -- Check if this vehicle is stolen
  local vehicles = career_modules_inventory.getVehicles()
  if not vehicles then return nil end

  local veh = vehicles[inventoryId]
  if not veh or not veh.isStolen then return nil end

  return {
    inventoryId = inventoryId,
    hasDocuments = veh.hasDocuments or false,
    documentTier = veh.documentTier,
    documentDetectChance = veh.documentDetectChance,
    heat = M.getVehicleHeat(inventoryId)
  }
end

-- Check for police inspection (called from onUpdate)
local function checkPoliceInspection(dtReal)
  -- Don't check if already in a theft/pursuit
  if theftJob.state ~= STATE.IDLE then return end

  local cfg = config
  local now = os.time()

  -- Cooldown check
  local cooldown = cfg.INSPECTION_COOLDOWN or 60
  if (now - lastInspectionTime) < cooldown then return end

  -- Check if player is driving a stolen vehicle
  local stolenInfo = getPlayerStolenVehicleInfo()
  if not stolenInfo then return end

  -- Check for nearby police
  local policeRange = cfg.INSPECTION_POLICE_RANGE or 50
  local policeId, policeDist = findNearbyPolice(policeRange)
  if not policeId then return end

  -- Calculate detection chance
  local baseChance = cfg.INSPECTION_BASE_CHANCE or 0.0005
  local chance = baseChance

  if not stolenInfo.hasDocuments then
    -- Undocumented: use heat level (higher heat = higher chance)
    local heat = stolenInfo.heat or 0
    chance = chance * (heat / 100)
  else
    -- Documented: use persisted detect chance from vehicle data
    local detectChance = stolenInfo.documentDetectChance
    if detectChance then
      chance = chance * detectChance
    else
      -- Fallback: read from config based on tier (for older documented vehicles)
      local tierCfg = nil
      if stolenInfo.documentTier == "budget" then
        tierCfg = cfg.DOC_TIER_BUDGET
      elseif stolenInfo.documentTier == "standard" then
        tierCfg = cfg.DOC_TIER_STANDARD
      elseif stolenInfo.documentTier == "premium" then
        tierCfg = cfg.DOC_TIER_PREMIUM
      end
      if tierCfg then
        chance = chance * tierCfg.detectChance
      else
        chance = chance * 0.1 -- Ultimate fallback
      end
    end
  end

  -- Proximity modifier (closer = more likely)
  local proximityMod = 1 + (1 - (policeDist / policeRange))
  chance = chance * proximityMod

  -- Debug multiplier
  chance = chance * debugDetectionMultiplier

  -- Random check
  if math.random() < chance then
    lastInspectionTime = now
    inspectedVehicleInventoryId = stolenInfo.inventoryId  -- Track for confiscation
    log("I", "Police inspection triggered! Vehicle detected as stolen. InventoryId: " .. tostring(stolenInfo.inventoryId))

    -- Trigger pursuit
    ui_message("Police spotted your stolen vehicle!", 4, "warning")

    -- Start a pursuit on the player using proper API
    local playerVehId = be:getPlayerVehicleID(0)
    if playerVehId and gameplay_police and gameplay_police.setPursuitMode then
      gameplay_police.setPursuitMode(1, playerVehId)
    end
  end
end

---------------------------------------------------------------------------
-- Main Update Loop
---------------------------------------------------------------------------

local function onUpdate(dtReal, dtSim, dtRaw)
  if not career_career or not career_career.isActive() then
    return
  end

  -- Update job manager for proximity-based spawning
  local jm = getJobManager()
  if jm and jm.onUpdate then
    jm.onUpdate(dtReal, dtSim, dtRaw)
  end

  -- Update heat decay for stolen vehicles
  updateVehicleHeat()

  -- Update document processing timers (game time based)
  updateDocumentTimers(dtSim)

  -- Check for police inspection while driving stolen vehicles
  checkPoliceInspection(dtReal)

  -- Handle pending steal from radial menu
  if pendingStealVehId then
    local vehId = pendingStealVehId
    pendingStealVehId = nil
    startStealing(vehId)
  end

  -- Check for nearby stealable vehicles while walking
  if theftJob.state == STATE.IDLE then
    local prevNearby = nearbyVehicle
    nearbyVehicle, nearbyVehicleDistance = findNearbyStealableVehicle()

    if nearbyVehicle and config.SHOW_STEAL_PROMPT then
      if nearbyVehicle ~= prevNearby then
        local vehValue = getVehicleValue(nearbyVehicle)
        local valueStr = string.format("$%d", vehValue)
        ui_message("Press E to steal this vehicle.", 3, "info")
      end
      sendUIUpdate()
    end
  end

  -- Handle hotwire timer
  if theftJob.state == STATE.STEALING then
    theftJob.hotwireTimer = theftJob.hotwireTimer - dtSim

    if theftJob.hotwireTimer <= 0 then
      completeStealing()
    end
  end

  -- Handle report timer
  if theftJob.state == STATE.HOT then
    theftJob.reportTimer = theftJob.reportTimer - dtSim

    if isPlayerInGarage(theftJob.targetGarageId) then
      completeSuccess()
      return
    end

    if theftJob.reportTimer <= 0 then
      triggerPoliceResponse()
    end

    sendUIUpdate()
  end

  -- Handle police pursuit
  if theftJob.state == STATE.REPORTED then
    theftJob.escalationTimer = theftJob.escalationTimer + dtSim

    if isPlayerInGarage(theftJob.targetGarageId) then
      completeSuccess()
      return
    end

    escalatePoliceResponse()
    sendUIUpdate()
  end
end

---------------------------------------------------------------------------
-- Pursuit Action Hook
---------------------------------------------------------------------------

local function onPursuitAction(vehId, action, data)
  local playerVehId = be:getPlayerVehicleID(0)
  if vehId ~= playerVehId then
    return
  end

  -- Check if we're driving a stolen vehicle (from inventory)
  local stolenInfo = getPlayerStolenVehicleInfo()

  -- Check if we're in an active theft mission (vehicle not yet in inventory)
  local inActiveTheft = theftJob.state == STATE.STEALING or theftJob.state == STATE.HOT or theftJob.state == STATE.REPORTED

  -- If vehicle is not stolen and not in an active theft, car theft mod has no business here
  if not stolenInfo and not inActiveTheft then
    return
  end

  -- If vehicle has documents with 0 detect chance, it's "legit" - no car theft consequences
  if stolenInfo and stolenInfo.hasDocuments and stolenInfo.documentDetectChance <= 0 then
    log("I", "Pursuit action on documented vehicle - no car theft consequences")
    return
  end

  -- From here on, we're dealing with either an active theft or a stolen undocumented vehicle
  if action == "arrest" then
    if confiscationInProgress then
      return  -- Already handling confiscation
    end

    if inActiveTheft then
      -- Arrested during active theft (STEALING, HOT, or REPORTED states)
      completeFailure("Arrested by police!")
    elseif stolenInfo then
      -- Confiscate stolen undocumented vehicle from inventory
      confiscationInProgress = true
      confiscateVehicle(stolenInfo.inventoryId, "Vehicle confiscated by police!")
      confiscationInProgress = false
    end
    inspectedVehicleInventoryId = nil  -- Clear tracking after arrest
  elseif action == "evade" then
    log("I", "Evaded police pursuit")
    inspectedVehicleInventoryId = nil  -- Clear tracking on successful evasion
  end
end

---------------------------------------------------------------------------
-- Extension Lifecycle
---------------------------------------------------------------------------

local function onExtensionLoaded()
  log("I", "Car Theft Career mod loaded")
  log("I", "Use console command: carTheft_main.spawnCar() to spawn a stealable vehicle")

  -- Only load companion extensions if career is active
  if career_career and career_career.isActive() then
    extensions.load("carTheft_blackMarket")
    extensions.load("carTheft_documentation")
    extensions.load("carTheft_overrides")
    log("I", "Loaded companion extensions: blackMarket, documentation, overrides")
  end
end

-- Called when career mode starts or ends
local function onCareerActive(active)
  if active then
    log("I", "Career activated - loading companion extensions")
    extensions.load("carTheft_blackMarket")
    extensions.load("carTheft_documentation")
    extensions.load("carTheft_overrides")
  else
    log("I", "Career deactivated - unloading car theft extensions")
    resetTheftJob()
    extensions.unload("carTheft_blackMarket")
    extensions.unload("carTheft_documentation")
    extensions.unload("carTheft_overrides")
    extensions.unload("carTheft_streetRacing")
    extensions.unload("carTheft_jobManager")
  end
end

local function onExtensionUnloaded()
  log("I", "Car Theft Career mod unloaded")
  -- Clean up spawned vehicles
  for vehId, _ in pairs(spawnedStealableVehicles) do
    local vehObj = be:getObjectByID(vehId)
    if vehObj then
      vehObj:delete()
    end
  end
  spawnedStealableVehicles = {}
  resetTheftJob()
  -- Flush any remaining log entries to file
  logger.flush()
end

-- Load car theft data when career loads
-- NOTE: This must be defined BEFORE onCareerModulesActivated which calls it
local function loadCarTheftData()
  if not career_career or not career_career.isActive() then return end
  if not career_saveSystem or not career_saveSystem.getCurrentSavePath then return end

  local currentSavePath = career_saveSystem.getCurrentSavePath()
  if not currentSavePath then return end

  local filePath = currentSavePath .. "/carTheft.json"
  local success, saveData = pcall(jsonReadFile, filePath)
  if not success then
    log("W", "Failed to read save file: " .. tostring(saveData))
    return
  end

  if saveData then
    log("I", "Loading car theft data from " .. filePath)

    -- Load job manager data first
    local jm = getJobManager()
    if jm and jm.loadSaveData and saveData.jobManagerData then
      jm.loadSaveData(saveData.jobManagerData)
    end

    -- Restore theft job state if it was in progress
    if saveData.theftJob and saveData.theftJob.activeJobId then
      log("I", "Restoring in-progress theft job #" .. saveData.theftJob.activeJobId)
      theftJob.activeJobId = saveData.theftJob.activeJobId
      theftJob.vehicleValue = saveData.theftJob.vehicleValue or 0
      theftJob.targetGarageId = saveData.theftJob.targetGarageId
      theftJob.escalationLevel = saveData.theftJob.escalationLevel or 0

      if saveData.theftJob.targetGaragePos then
        theftJob.targetGaragePos = vec3(
          saveData.theftJob.targetGaragePos.x,
          saveData.theftJob.targetGaragePos.y,
          saveData.theftJob.targetGaragePos.z
        )
      end

      -- State will be restored based on what happens with the job vehicle
      -- For now, set to IDLE - the player will need to go back to the job location
      theftJob.state = STATE.IDLE
    end

    -- Note: pendingDocuments and vehicleHeat are now stored on vehicle inventory
    -- and are automatically persisted with the career save
  end
end

local function onCareerModulesActivated()
  log("I", "Career modules activated")
  resetTheftJob()

  -- Load saved data (wrapped in pcall to prevent crashes)
  local loadSuccess, loadErr = pcall(loadCarTheftData)
  if not loadSuccess then
    log("E", "Failed to load car theft data: " .. tostring(loadErr))
  end

  -- Restore any saved job state (also wrapped in pcall)
  local restoreSuccess, restoreErr = pcall(function()
    local jm = getJobManager()
    if jm then
      local savedJob = jm.getActiveInProgressJob and jm.getActiveInProgressJob()
      if savedJob then
        log("I", "Found saved active job #" .. savedJob.id .. ", restoring GPS...")
        -- Set GPS to the job location
        if savedJob.exactPos and core_groundMarkers and core_groundMarkers.setPath then
          core_groundMarkers.setPath(savedJob.exactPos)
          if ui_message then
            ui_message("Restored job: " .. savedJob.vehicleName .. " in " .. savedJob.area, 5, "info")
          end
        end
      end
    end
  end)
  if not restoreSuccess then
    log("E", "Failed to restore job state: " .. tostring(restoreErr))
  end
end

-- Save car theft data when career saves
local function onSaveCurrentSaveSlot(currentSavePath, oldSaveDate, freeroamSaveData)
  if not career_career or not career_career.isActive() then return end

  local saveData = {
    -- Save theftJob state if active
    theftJob = nil,
    jobManagerData = nil,
    -- Note: pendingDocuments and vehicleHeat are now stored on vehicle inventory
  }

  -- Save theft job if in progress
  if theftJob.state ~= STATE.IDLE and theftJob.activeJobId then
    saveData.theftJob = {
      state = theftJob.state,
      activeJobId = theftJob.activeJobId,
      vehicleValue = theftJob.vehicleValue,
      targetGarageId = theftJob.targetGarageId,
      targetGaragePos = theftJob.targetGaragePos and {
        x = theftJob.targetGaragePos.x,
        y = theftJob.targetGaragePos.y,
        z = theftJob.targetGaragePos.z
      } or nil,
      escalationLevel = theftJob.escalationLevel,
    }
  end

  -- Get job manager save data
  local jm = getJobManager()
  if jm and jm.getSaveData then
    saveData.jobManagerData = jm.getSaveData()
  end

  -- Save to file
  local filePath = currentSavePath .. "/carTheft.json"
  jsonWriteFile(filePath, saveData, true)
  log("I", "Saved car theft data to " .. filePath)
end

---------------------------------------------------------------------------
-- Console Commands / Public API
---------------------------------------------------------------------------

-- Spawn a stealable car (console command: carTheft_main.spawnCar())
M.spawnCar = function(model, offsetX, offsetY)
  model = model or "covet"
  offsetX = offsetX or 5
  offsetY = offsetY or 0

  local playerPos = getPlayerPos()
  if not playerPos then
    log("E", "Cannot get player position")
    return nil
  end

  -- Spawn offset from player
  local spawnPos = vec3(playerPos.x + offsetX, playerPos.y + offsetY, playerPos.z)

  return spawnStealableVehicle(model, nil, spawnPos, nil)
end

-- List available models (for reference)
M.listModels = function()
  log("I", "Common vehicle models: covet, vivace, etk800, sunburst, pessima, moonhawk, barstow, wendover, pickup")
end

-- Get spawned vehicles count
M.getSpawnedCount = function()
  local count = 0
  for _ in pairs(spawnedStealableVehicles) do
    count = count + 1
  end
  log("I", "Spawned stealable vehicles: " .. count)
  return count
end

-- Clear all spawned stealable vehicles
M.clearAllCars = function()
  for vehId, _ in pairs(spawnedStealableVehicles) do
    local vehObj = be:getObjectByID(vehId)
    if vehObj then
      vehObj:delete()
    end
  end
  spawnedStealableVehicles = {}
  log("I", "Cleared all stealable vehicles")
end

-- Standard API
M.attemptSteal = function()
  if nearbyVehicle and theftJob.state == STATE.IDLE then
    startStealing(nearbyVehicle)
  end
end

M.cancelSteal = function()
  if theftJob.state == STATE.STEALING then
    theftJob.state = STATE.IDLE
    theftJob.hotwireTimer = 0
    theftJob.targetVehId = nil
    ui_message("Steal cancelled", 2, "info")
  end
end

M.getState = function()
  return theftJob.state
end

M.getTheftData = function()
  return {
    state = theftJob.state,
    reportTimer = theftJob.reportTimer,
    escalationLevel = theftJob.escalationLevel,
    vehicleValue = theftJob.vehicleValue,
    targetGarageId = theftJob.targetGarageId
  }
end

M.reload = function()
  resetTheftJob()
  -- Reload all car theft modules
  extensions.reload("carTheft_streetRacing")
  extensions.reload("carTheft_raceEditorUI")
  extensions.reload("carTheft_jobManager")
  extensions.reload("carTheft_blackMarket")
  extensions.reload("carTheft_documentation")
  extensions.reload("carTheft_overrides")
  extensions.reload("carTheft_main")
end

---------------------------------------------------------------------------
-- Stolen Vehicle Helpers (for LegitDocs and Black Market)
---------------------------------------------------------------------------

-- Get all stolen vehicles from player's inventory
M.getStolenVehicles = function()
  if not career_modules_inventory then return {} end
  local vehicles = career_modules_inventory.getVehicles()
  if not vehicles then return {} end

  local stolen = {}
  for invId, veh in pairs(vehicles) do
    if veh.isStolen then
      -- Use actual vehicle value (accounts for stripped parts, mileage, damage)
      -- Try valueCalculator first, fall back to inventory value or configBaseValue
      local actualValue = nil

      if career_modules_valueCalculator and career_modules_valueCalculator.getInventoryVehicleValue then
        local success, calcValue = pcall(function()
          return career_modules_valueCalculator.getInventoryVehicleValue(invId)
        end)
        if success and calcValue then
          actualValue = calcValue
        end
      end

      -- Fallback chain: veh.value -> configBaseValue -> 0
      if not actualValue then
        actualValue = veh.value or veh.configBaseValue or 0
      end

      table.insert(stolen, {
        inventoryId = invId,
        niceName = veh.niceName or "Unknown Vehicle",
        model = veh.model,
        isStolen = true,
        hasDocuments = veh.hasDocuments or false,
        stolenDate = veh.stolenDate,
        value = actualValue
      })
    end
  end
  return stolen
end

-- Get only undocumented stolen vehicles
M.getUndocumentedVehicles = function()
  local stolen = M.getStolenVehicles()
  local undocumented = {}
  for _, veh in ipairs(stolen) do
    if not veh.hasDocuments then
      table.insert(undocumented, veh)
    end
  end
  return undocumented
end

-- Mark a stolen vehicle as documented
M.markVehicleDocumented = function(inventoryId)
  if not career_modules_inventory then return false end
  local vehicles = career_modules_inventory.getVehicles()
  if not vehicles or not vehicles[inventoryId] then return false end

  if not vehicles[inventoryId].isStolen then
    log("W", "Vehicle " .. tostring(inventoryId) .. " is not stolen, cannot document")
    return false
  end

  vehicles[inventoryId].hasDocuments = true
  vehicles[inventoryId].documentedDate = os.time()
  log("I", "Vehicle " .. tostring(inventoryId) .. " marked as documented")
  return true
end

-- Check if a vehicle is stolen and undocumented
M.isVehicleUndocumented = function(inventoryId)
  if not career_modules_inventory then return false end
  local vehicles = career_modules_inventory.getVehicles()
  if not vehicles or not vehicles[inventoryId] then return false end
  return vehicles[inventoryId].isStolen and not vehicles[inventoryId].hasDocuments
end

---------------------------------------------------------------------------
-- Document Processing (for tiered documentation system)
---------------------------------------------------------------------------

-- Start document processing for a vehicle
M.startDocumentProcessing = function(inventoryId, tier, requiredHours)
  if not career_modules_inventory then return false end
  local vehicles = career_modules_inventory.getVehicles()
  if not vehicles or not vehicles[inventoryId] then return false end

  local veh = vehicles[inventoryId]
  veh.pendingDocTier = tier
  veh.pendingDocRequiredHours = requiredHours or 8
  veh.pendingDocRemainingSeconds = (requiredHours or 8) * 3600  -- Countdown in seconds
  veh.pendingDocReady = false

  log("I", "Started document processing for " .. tostring(inventoryId) .. " (tier: " .. tier .. ", " .. requiredHours .. " game hours)")
  return true
end

-- Check if documents are pending for a vehicle
M.isDocumentsPending = function(inventoryId)
  if not career_modules_inventory then return false end
  local vehicles = career_modules_inventory.getVehicles()
  if not vehicles or not vehicles[inventoryId] then return false end

  return vehicles[inventoryId].pendingDocTier ~= nil
end

-- Get document status for a vehicle
M.getDocumentStatus = function(inventoryId)
  if not career_modules_inventory then return nil end
  local vehicles = career_modules_inventory.getVehicles()
  if not vehicles or not vehicles[inventoryId] then return nil end

  local veh = vehicles[inventoryId]
  if not veh.pendingDocTier then return nil end

  local requiredSeconds = (veh.pendingDocRequiredHours or 8) * 3600
  local remainingSeconds = math.max(0, veh.pendingDocRemainingSeconds or 0)
  local elapsedSeconds = requiredSeconds - remainingSeconds
  local remainingHours = remainingSeconds / 3600

  return {
    tier = veh.pendingDocTier,
    requiredHours = veh.pendingDocRequiredHours or 8,
    elapsedSeconds = elapsedSeconds,
    ready = veh.pendingDocReady or (remainingSeconds <= 0),
    remainingSeconds = remainingSeconds,
    remainingHours = remainingHours
  }
end

-- Finalize documentation (when documents are ready)
M.finalizeDocumentation = function(inventoryId)
  if not career_modules_inventory then return false end
  local vehicles = career_modules_inventory.getVehicles()
  if not vehicles or not vehicles[inventoryId] then return false end

  local veh = vehicles[inventoryId]

  -- Check if ready (use status check which handles game time)
  local status = M.getDocumentStatus(inventoryId)
  if not status or not status.ready then
    log("W", "Documents not ready yet for " .. tostring(inventoryId))
    return false
  end

  local tier = veh.pendingDocTier

  -- Get the detect chance for this tier
  local detectChance = 0.1  -- Default fallback
  local cfg = config
  if tier == "budget" and cfg.DOC_TIER_BUDGET then
    detectChance = cfg.DOC_TIER_BUDGET.detectChance or 0.40
  elseif tier == "standard" and cfg.DOC_TIER_STANDARD then
    detectChance = cfg.DOC_TIER_STANDARD.detectChance or 0.15
  elseif tier == "premium" and cfg.DOC_TIER_PREMIUM then
    detectChance = cfg.DOC_TIER_PREMIUM.detectChance or 0.02
  end

  -- Mark as documented with tier info and detect chance
  veh.hasDocuments = true
  veh.documentedDate = os.time()
  veh.documentTier = tier
  veh.documentDetectChance = detectChance

  -- Clear pending document data
  veh.pendingDocTier = nil
  veh.pendingDocRemainingSeconds = nil
  veh.pendingDocRequiredHours = nil
  veh.pendingDocReady = nil

  -- Clear heat for this vehicle
  veh.heatLevel = nil
  veh.heatLastUpdate = nil

  log("I", "Finalized documentation for " .. tostring(inventoryId) .. " (tier: " .. tostring(tier) .. ")")
  return true
end

---------------------------------------------------------------------------
-- Heat System (stored on vehicle inventory)
---------------------------------------------------------------------------

-- Initialize heat for a newly stolen vehicle
M.initVehicleHeat = function(inventoryId)
  if not career_modules_inventory then return end
  local vehicles = career_modules_inventory.getVehicles()
  if not vehicles or not vehicles[inventoryId] then return end

  local cfg = config
  local veh = vehicles[inventoryId]
  veh.heatLevel = cfg.HEAT_INITIAL or 100
  veh.heatLastUpdate = getGameTimeSeconds()
  log("I", "Initialized heat for vehicle " .. tostring(inventoryId) .. ": " .. veh.heatLevel)
end

-- Get heat level for a vehicle
M.getVehicleHeat = function(inventoryId)
  if not career_modules_inventory then return 0 end
  local vehicles = career_modules_inventory.getVehicles()
  if not vehicles or not vehicles[inventoryId] then return 0 end

  local veh = vehicles[inventoryId]
  return veh.heatLevel or 0
end

-- Set heat level for a vehicle
M.setVehicleHeat = function(inventoryId, level)
  if not career_modules_inventory then return end
  local vehicles = career_modules_inventory.getVehicles()
  if not vehicles or not vehicles[inventoryId] then return end

  local veh = vehicles[inventoryId]
  veh.heatLevel = level
  veh.heatLastUpdate = getGameTimeSeconds()
end

-- Clear heat for a vehicle (when documented or confiscated)
M.clearVehicleHeat = function(inventoryId)
  if not career_modules_inventory then return end
  local vehicles = career_modules_inventory.getVehicles()
  if not vehicles or not vehicles[inventoryId] then return end

  local veh = vehicles[inventoryId]
  veh.heatLevel = nil
  veh.heatLastUpdate = nil
end

---------------------------------------------------------------------------
-- Debug Functions
---------------------------------------------------------------------------

-- Set detection multiplier (1 = normal, 1000 = guaranteed detection near police)
-- Usage: carTheft_main.setDebugDetection(1000)
function M.setDebugDetection(multiplier)
  debugDetectionMultiplier = multiplier or 1
  log("I", "Debug detection multiplier set to: " .. tostring(debugDetectionMultiplier))
  if multiplier > 1 then
    ui_message("DEBUG: Police detection x" .. multiplier, 5, "warning")
  end
end

-- Get current detection multiplier
function M.getDebugDetection()
  return debugDetectionMultiplier
end

-- Debug: Check why police detection isn't working
-- Usage: carTheft_main.debugPoliceCheck()
function M.debugPoliceCheck()
  print("=== Police Detection Debug ===")

  -- Check player vehicle
  local playerVehId = be:getPlayerVehicleID(0)
  print("Player vehicle ID: " .. tostring(playerVehId))

  if not playerVehId then
    print("ERROR: No player vehicle!")
    return
  end

  -- Check inventory
  if not career_modules_inventory then
    print("ERROR: career_modules_inventory not available!")
    return
  end

  -- Get inventory ID from current vehicle
  local currentInvId = career_modules_inventory.getInventoryIdFromVehicleId(playerVehId)
  print("Current vehicle inventory ID: " .. tostring(currentInvId))

  local vehicles = career_modules_inventory.getVehicles()
  if currentInvId and vehicles and vehicles[currentInvId] then
    local veh = vehicles[currentInvId]
    print("Current vehicle info:")
    print("  isStolen: " .. tostring(veh.isStolen))
    print("  hasDocuments: " .. tostring(veh.hasDocuments))
  else
    print("Current vehicle NOT in inventory (not owned)")
  end

  -- Check for nearby police
  local policeId, policeDist = findNearbyPolice(100)
  if policeId then
    print("Police nearby: ID=" .. tostring(policeId) .. ", distance=" .. tostring(policeDist))
  else
    print("No police within 100 units")
  end

  -- Check stolen info
  local stolenInfo = getPlayerStolenVehicleInfo()
  if stolenInfo then
    print("DETECTION READY:")
    print("  inventoryId: " .. tostring(stolenInfo.inventoryId))
    print("  hasDocuments: " .. tostring(stolenInfo.hasDocuments))
    print("  heat: " .. tostring(stolenInfo.heat))
  else
    print("NOT DETECTED - vehicle either not stolen or not in inventory")
  end

  print("Debug multiplier: " .. tostring(debugDetectionMultiplier))
  print("=== End Debug ===")
end

-- Open the BackAlley UI from console
-- Usage: carTheft_main.openUI()
function M.openUI()
  guihooks.trigger('ChangeState', {state = 'menu.backalley'})
  log("I", "Opening BackAlley UI")
end

-- Set heat for current vehicle (for testing/fixing old vehicles)
-- Usage: carTheft_main.setCurrentVehicleHeat(100)
function M.setCurrentVehicleHeat(level)
  local playerVehId = be:getPlayerVehicleID(0)
  if not playerVehId then
    ui_message("Not in a vehicle!", 3, "error")
    return false
  end

  local inventoryId = career_modules_inventory.getInventoryIdFromVehicleId(playerVehId)
  if not inventoryId then
    ui_message("Vehicle not in inventory!", 3, "error")
    return false
  end

  -- Use the new vehicle inventory storage
  M.setVehicleHeat(inventoryId, level or 100)

  ui_message("Heat set to " .. tostring(level), 3, "info")
  log("I", "Heat set to " .. tostring(level) .. " for vehicle " .. tostring(inventoryId))
  return true
end

---------------------------------------------------------------------------
-- UI Data Functions
---------------------------------------------------------------------------

-- Get all stolen vehicles with their status for the My Rides UI
M.getVehicleStatusForUI = function()
  if not career_career or not career_career.isActive() then
    return {}
  end

  if not career_modules_inventory then
    return {}
  end

  local vehicles = career_modules_inventory.getVehicles()
  if not vehicles then return {} end

  local result = {}

  for inventoryId, veh in pairs(vehicles) do
    if veh.isStolen then
      local heat = M.getVehicleHeat(inventoryId) or 0
      local docStatus = M.getDocumentStatus(inventoryId)

      local entry = {
        inventoryId = inventoryId,
        name = veh.niceName or veh.model or "Unknown",
        value = veh.value or 0,
        heat = math.floor(heat),
        hasDocuments = veh.hasDocuments or false,
        documentTier = veh.documentTier,
        detectChance = veh.documentDetectChance or 0,
        pendingDoc = docStatus ~= nil and not docStatus.ready,
        pendingHoursLeft = docStatus and docStatus.remainingHours or 0
      }
      table.insert(result, entry)
    end
  end

  return result
end

---------------------------------------------------------------------------
-- Hook Registration
---------------------------------------------------------------------------

M.onUpdate = onUpdate
M.onExtensionLoaded = onExtensionLoaded
M.onExtensionUnloaded = onExtensionUnloaded
M.onCareerActive = onCareerActive
M.onCareerModulesActivated = onCareerModulesActivated
M.onSaveCurrentSaveSlot = onSaveCurrentSaveSlot
M.onPursuitAction = onPursuitAction
M.onBeforeRadialOpened = onBeforeRadialOpened
M.onQuickAccessLoaded = onQuickAccessLoaded
M.onComputerAddFunctions = onComputerAddFunctions

return M
