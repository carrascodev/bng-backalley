-- Car Theft Career - Race Checkpoint Manager
-- Handles visual checkpoints and trigger detection for street racing
-- Based on rls_career checkpointManager

local M = {}

local logger = require("carTheft/logger")
local LOG_TAG = "carTheft_raceCheckpoints"

-- State
local checkpoints = {}
local currentCheckpointIndex = 0
local totalCheckpoints = 0
local raceName = nil
local onCheckpointHitCallback = nil

---------------------------------------------------------------------------
-- Utility
---------------------------------------------------------------------------

local function log(level, msg)
  logger.log(LOG_TAG, level, msg)
end

---------------------------------------------------------------------------
-- Checkpoint Creation
---------------------------------------------------------------------------

-- Create a BeamNGTrigger for collision detection
local function createTrigger(index, node)
  local position = vec3(node.x, node.y, node.z)
  local radius = node.width or 12

  local trigger = createObject('BeamNGTrigger')
  trigger:setPosition(position)
  trigger:setScale(vec3(radius, radius, radius))
  trigger.triggerType = 0  -- Sphere type

  local triggerName = string.format("streetrace_cp_%s_%d", raceName or "race", index)

  -- Remove existing trigger with same name
  local existing = scenetree.findObject(triggerName)
  if existing then
    existing:delete()
  end

  trigger:registerObject(triggerName)
  log("D", "Created trigger: " .. triggerName)

  return trigger
end

-- Create a visual marker (TSStatic mesh)
local function createMarker(index, node, color)
  local marker = createObject('TSStatic')
  marker.shapeName = "art/shapes/interface/checkpoint_marker.dae"

  marker:setPosRot(node.x, node.y, node.z, 0, 0, 0, 0)
  marker.scale = vec3(node.width or 12, node.width or 12, node.width or 12)
  marker.useInstanceRenderData = true

  -- Set color
  if color == "green" then
    marker.instanceColor = ColorF(0, 1, 0, 0.7):asLinear4F()
  elseif color == "blue" then
    marker.instanceColor = ColorF(0, 0, 1, 0.7):asLinear4F()
  else
    marker.instanceColor = ColorF(1, 0, 0, 0.5):asLinear4F()  -- Red default
  end

  local markerName = string.format("streetrace_marker_%s_%d", raceName or "race", index)

  -- Remove existing marker with same name
  local existing = scenetree.findObject(markerName)
  if existing then
    existing:delete()
  end

  marker:registerObject(markerName)
  log("D", "Created marker: " .. markerName)

  return marker
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

-- Initialize checkpoints for a race
-- raceData should have: start, finish, checkpoints[]
function M.setupRace(raceData, name)
  M.cleanup()

  raceName = name or "streetrace"
  checkpoints = {}
  currentCheckpointIndex = 0

  if not raceData then
    log("W", "No race data provided")
    return false
  end

  -- Add start as first checkpoint
  if raceData.start and raceData.start.pos then
    table.insert(checkpoints, {
      node = {
        x = raceData.start.pos.x,
        y = raceData.start.pos.y,
        z = raceData.start.pos.z,
        width = raceData.start.width or 15
      },
      isStart = true
    })
  end

  -- Add intermediate checkpoints
  if raceData.checkpoints then
    for _, cp in ipairs(raceData.checkpoints) do
      if cp.node then
        table.insert(checkpoints, {
          node = cp.node,
          isCheckpoint = true
        })
      end
    end
  end

  -- Add finish as last checkpoint
  if raceData.finish and raceData.finish.pos then
    table.insert(checkpoints, {
      node = {
        x = raceData.finish.pos.x,
        y = raceData.finish.pos.y,
        z = raceData.finish.pos.z,
        width = raceData.finish.width or 15
      },
      isFinish = true
    })
  end

  totalCheckpoints = #checkpoints
  log("I", "Race setup with " .. totalCheckpoints .. " checkpoints")

  -- Create triggers for all checkpoints
  for i, cp in ipairs(checkpoints) do
    cp.trigger = createTrigger(i, cp.node)
  end

  return true
end

-- Show visual markers for current and next checkpoint
function M.showCheckpoints(currentIndex)
  currentCheckpointIndex = currentIndex or 0

  -- Remove old markers
  for i, cp in ipairs(checkpoints) do
    if cp.marker then
      cp.marker:delete()
      cp.marker = nil
    end
  end

  -- Show current checkpoint (green)
  local currentIdx = currentCheckpointIndex + 1
  if checkpoints[currentIdx] then
    checkpoints[currentIdx].marker = createMarker(currentIdx, checkpoints[currentIdx].node, "green")
  end

  -- Show next checkpoint (red)
  local nextIdx = currentIdx + 1
  if checkpoints[nextIdx] then
    checkpoints[nextIdx].marker = createMarker(nextIdx, checkpoints[nextIdx].node, "red")
  end
end

-- Get waypoint list for AI to follow
function M.getAIPath()
  local path = {}
  for i, cp in ipairs(checkpoints) do
    table.insert(path, {
      x = cp.node.x,
      y = cp.node.y,
      z = cp.node.z
    })
  end
  return path
end

-- Set callback for when checkpoint is hit
function M.setCheckpointCallback(callback)
  onCheckpointHitCallback = callback
end

-- Handle trigger event (called from onBeamNGTrigger)
function M.onTrigger(data)
  if not data or not data.triggerName then return end

  -- Check if this is our checkpoint trigger
  local prefix = "streetrace_cp_" .. (raceName or "race") .. "_"
  if not string.find(data.triggerName, prefix, 1, true) then
    return
  end

  -- Extract checkpoint index
  local indexStr = string.match(data.triggerName, "_(%d+)$")
  local index = tonumber(indexStr)
  if not index then return end

  -- Check if player vehicle
  local playerVehId = be:getPlayerVehicleID(0)
  if data.subjectID ~= playerVehId then return end

  -- Check if this is the expected checkpoint
  local expectedIndex = currentCheckpointIndex + 1
  if index ~= expectedIndex then
    log("D", "Wrong checkpoint hit: " .. index .. " expected: " .. expectedIndex)
    return
  end

  log("I", "Checkpoint " .. index .. " hit!")

  -- Update current checkpoint
  currentCheckpointIndex = index

  -- Update visual markers
  M.showCheckpoints(currentCheckpointIndex)

  -- Call callback
  if onCheckpointHitCallback then
    local isFinish = checkpoints[index] and checkpoints[index].isFinish
    onCheckpointHitCallback(index, totalCheckpoints, isFinish)
  end
end

-- Get current progress
function M.getProgress()
  return {
    current = currentCheckpointIndex,
    total = totalCheckpoints
  }
end

-- Cleanup all checkpoints
function M.cleanup()
  for i, cp in ipairs(checkpoints) do
    if cp.trigger then
      cp.trigger:delete()
      cp.trigger = nil
    end
    if cp.marker then
      cp.marker:delete()
      cp.marker = nil
    end
  end

  checkpoints = {}
  currentCheckpointIndex = 0
  totalCheckpoints = 0
  raceName = nil
  onCheckpointHitCallback = nil

  log("I", "Checkpoints cleaned up")
end

return M
