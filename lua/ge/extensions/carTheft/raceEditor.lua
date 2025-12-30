-- Car Theft Career - Race Editor
-- Console tool for creating street race tracks

local M = {}

-- Logger module
local logger = require("carTheft/logger")
local LOG_TAG = "carTheft_raceEditor"

---------------------------------------------------------------------------
-- Configuration
---------------------------------------------------------------------------

local DEFAULT_CHECKPOINT_WIDTH = 12
local DEFAULT_START_WIDTH = 15
local DEFAULT_FINISH_WIDTH = 15

-- Marker colors (RGBA)
local COLORS = {
  start = {0, 1, 0, 0.8},      -- Green
  checkpoint = {1, 1, 0, 0.8}, -- Yellow
  finish = {1, 0, 0, 0.8},     -- Red
  preview = {0, 0.5, 1, 0.6}   -- Blue (preview mode)
}

---------------------------------------------------------------------------
-- Editor State
---------------------------------------------------------------------------

local editorState = {
  active = false,
  raceName = nil,
  startPos = nil,
  startRot = nil,
  startWidth = DEFAULT_START_WIDTH,
  finishPos = nil,
  finishRot = nil,
  finishWidth = DEFAULT_FINISH_WIDTH,
  checkpoints = {},
  markers = {}
}

---------------------------------------------------------------------------
-- Utility Functions
---------------------------------------------------------------------------

local function log(level, msg)
  logger.log(LOG_TAG, level, msg)
end

local function uiMessage(msg, duration, msgType)
  duration = duration or 5
  msgType = msgType or "info"

  guihooks.trigger('toastrMsg', {
    type = msgType,
    title = "Race Editor",
    msg = msg
  })

  -- Also log it
  log("I", msg)
end

local function getCurrentMapName()
  local levelPath = getMissionFilename()
  if levelPath then
    local mapName = string.match(levelPath, "levels/([^/]+)/")
    return mapName
  end
  return nil
end

local function getPlayerPos()
  local playerVehId = be:getPlayerVehicleID(0)
  if playerVehId then
    local veh = be:getObjectByID(playerVehId)
    if veh then
      return veh:getPosition()
    end
  end

  -- Try walking mode (unicycle)
  local unicycle = scenetree.findObject("unicycle")
  if unicycle then
    return unicycle:getPosition()
  end

  return nil
end

local function getPlayerRot()
  local playerVehId = be:getPlayerVehicleID(0)
  if playerVehId then
    local veh = be:getObjectByID(playerVehId)
    if veh then
      -- Get rotation directly from vehicle
      local rot = veh:getRotation()
      if rot then
        return rot
      end
    end
  end
  return quat(0, 0, 0, 1)
end

local function posToTable(pos)
  if not pos then return nil end
  return {x = pos.x, y = pos.y, z = pos.z}
end

local function quatToTable(q)
  if not q then return nil end
  return {x = q.x, y = q.y, z = q.z, w = q.w}
end

---------------------------------------------------------------------------
-- Marker Management
---------------------------------------------------------------------------

local function clearMarkers()
  for _, marker in ipairs(editorState.markers) do
    if marker and marker:isValid() then
      marker:delete()
    end
  end
  editorState.markers = {}
end

local function createMarker(pos, color, width, name)
  if not pos then return nil end

  -- For now, just log the marker position (visual markers can be added later)
  log("D", "Marker: " .. name .. " at (" .. pos.x .. ", " .. pos.y .. ", " .. pos.z .. ") width: " .. width)

  -- TODO: Add visual marker creation using TSStatic or debug drawing
  return nil
end

local function updateMarkers()
  clearMarkers()

  -- Create start marker
  if editorState.startPos then
    local pos = vec3(editorState.startPos.x, editorState.startPos.y, editorState.startPos.z)
    createMarker(pos, COLORS.start, editorState.startWidth, "start")
  end

  -- Create checkpoint markers
  for i, cp in ipairs(editorState.checkpoints) do
    local pos = vec3(cp.node.x, cp.node.y, cp.node.z)
    createMarker(pos, COLORS.checkpoint, cp.node.width or DEFAULT_CHECKPOINT_WIDTH, "cp" .. i)
  end

  -- Create finish marker
  if editorState.finishPos then
    local pos = vec3(editorState.finishPos.x, editorState.finishPos.y, editorState.finishPos.z)
    createMarker(pos, COLORS.finish, editorState.finishWidth, "finish")
  end
end

---------------------------------------------------------------------------
-- Console Commands
---------------------------------------------------------------------------

-- Start editing a new race
-- Usage: carTheft_raceEditor.start("my_race_name")
function M.start(raceName)
  if not raceName or raceName == "" then
    uiMessage("Usage: carTheft_raceEditor.start(\"race_name\")", 5, "error")
    return false
  end

  -- Sanitize race name (lowercase, underscores)
  raceName = string.lower(raceName):gsub("%s+", "_"):gsub("[^%w_]", "")

  if editorState.active then
    uiMessage("Editor already active. Use cancel() to discard or save() to finish.", 5, "warning")
    return false
  end

  editorState = {
    active = true,
    raceName = raceName,
    startPos = nil,
    startRot = nil,
    startWidth = DEFAULT_START_WIDTH,
    finishPos = nil,
    finishRot = nil,
    finishWidth = DEFAULT_FINISH_WIDTH,
    checkpoints = {},
    markers = {}
  }

  uiMessage("Race Editor started for: " .. raceName, 5, "success")
  uiMessage("Commands: setstart(), addcheckpoint(), setfinish(), preview(), save(), cancel()", 10, "info")

  return true
end

-- Set start line at current position
-- Usage: carTheft_raceEditor.setstart() or carTheft_raceEditor.setstart(15)
function M.setstart(width)
  if not editorState.active then
    uiMessage("Editor not active. Use start(\"name\") first.", 5, "error")
    return false
  end

  local pos = getPlayerPos()
  if not pos then
    uiMessage("Could not get player position", 5, "error")
    return false
  end

  local rot = getPlayerRot()

  editorState.startPos = posToTable(pos)
  editorState.startRot = quatToTable(rot)
  editorState.startWidth = width or DEFAULT_START_WIDTH

  updateMarkers()
  uiMessage("Start line set at current position (width: " .. editorState.startWidth .. ")", 3, "success")

  return true
end

-- Add checkpoint at current position
-- Usage: carTheft_raceEditor.addcheckpoint() or carTheft_raceEditor.addcheckpoint(12)
function M.addcheckpoint(width)
  if not editorState.active then
    uiMessage("Editor not active. Use start(\"name\") first.", 5, "error")
    return false
  end

  local pos = getPlayerPos()
  if not pos then
    uiMessage("Could not get player position", 5, "error")
    return false
  end

  width = width or DEFAULT_CHECKPOINT_WIDTH

  local checkpoint = {
    node = {
      x = pos.x,
      y = pos.y,
      z = pos.z,
      width = width
    },
    index = #editorState.checkpoints + 1
  }

  table.insert(editorState.checkpoints, checkpoint)
  updateMarkers()

  uiMessage("Checkpoint " .. #editorState.checkpoints .. " added (width: " .. width .. ")", 3, "success")

  return true
end

-- Remove last checkpoint
-- Usage: carTheft_raceEditor.removecheckpoint()
function M.removecheckpoint()
  if not editorState.active then
    uiMessage("Editor not active.", 5, "error")
    return false
  end

  if #editorState.checkpoints == 0 then
    uiMessage("No checkpoints to remove", 3, "warning")
    return false
  end

  table.remove(editorState.checkpoints)
  updateMarkers()

  uiMessage("Last checkpoint removed. " .. #editorState.checkpoints .. " remaining.", 3, "info")

  return true
end

-- Set finish line at current position
-- Usage: carTheft_raceEditor.setfinish() or carTheft_raceEditor.setfinish(15)
function M.setfinish(width)
  if not editorState.active then
    uiMessage("Editor not active. Use start(\"name\") first.", 5, "error")
    return false
  end

  local pos = getPlayerPos()
  if not pos then
    uiMessage("Could not get player position", 5, "error")
    return false
  end

  local rot = getPlayerRot()

  editorState.finishPos = posToTable(pos)
  editorState.finishRot = quatToTable(rot)
  editorState.finishWidth = width or DEFAULT_FINISH_WIDTH

  updateMarkers()
  uiMessage("Finish line set at current position (width: " .. editorState.finishWidth .. ")", 3, "success")

  return true
end

-- Preview the race with visual markers
-- Usage: carTheft_raceEditor.preview()
function M.preview()
  if not editorState.active then
    uiMessage("Editor not active.", 5, "error")
    return false
  end

  updateMarkers()

  local status = {}
  table.insert(status, "Race: " .. editorState.raceName)
  table.insert(status, "Start: " .. (editorState.startPos and "SET" or "NOT SET"))
  table.insert(status, "Checkpoints: " .. #editorState.checkpoints)
  table.insert(status, "Finish: " .. (editorState.finishPos and "SET" or "NOT SET"))

  uiMessage(table.concat(status, " | "), 10, "info")

  return true
end

-- Show current status
-- Usage: carTheft_raceEditor.status()
function M.status()
  if not editorState.active then
    uiMessage("Editor not active.", 3, "info")
    return
  end

  local lines = {
    "=== Race Editor Status ===",
    "Race Name: " .. editorState.raceName,
    "Start: " .. (editorState.startPos and string.format("(%.1f, %.1f, %.1f)", editorState.startPos.x, editorState.startPos.y, editorState.startPos.z) or "NOT SET"),
    "Checkpoints: " .. #editorState.checkpoints,
    "Finish: " .. (editorState.finishPos and string.format("(%.1f, %.1f, %.1f)", editorState.finishPos.x, editorState.finishPos.y, editorState.finishPos.z) or "NOT SET")
  }

  for _, line in ipairs(lines) do
    log("I", line)
  end

  uiMessage("Check console for detailed status", 3, "info")
end

-- Save race to JSON file
-- Usage: carTheft_raceEditor.save()
function M.save()
  if not editorState.active then
    uiMessage("Editor not active.", 5, "error")
    return false
  end

  -- Validate
  if not editorState.startPos then
    uiMessage("Error: No start position set! Use setstart()", 5, "error")
    return false
  end

  if not editorState.finishPos then
    uiMessage("Error: No finish position set! Use setfinish()", 5, "error")
    return false
  end

  -- Build race data
  local raceData = {
    id = editorState.raceName,
    name = editorState.raceName:gsub("_", " "):gsub("(%a)([%w_']*)", function(a, b) return string.upper(a) .. b end),
    description = "Custom street race",
    type = "point_to_point",
    difficulty = math.min(3, math.max(1, math.ceil(#editorState.checkpoints / 3))),
    minBet = 1000,
    maxBet = 50000,
    start = {
      pos = editorState.startPos,
      rot = editorState.startRot,
      width = editorState.startWidth
    },
    finish = {
      pos = editorState.finishPos,
      rot = editorState.finishRot,
      width = editorState.finishWidth
    },
    checkpoints = editorState.checkpoints,
    bestTime = nil
  }

  -- Get file path
  local mapName = getCurrentMapName()
  if not mapName then
    uiMessage("Error: Could not determine current map", 5, "error")
    return false
  end

  -- Save to source folder first (car_theft_career), fallback to mods folder
  local primaryPath = "/car_theft_career/settings/races/" .. mapName .. ".json"
  local fallbackPath = "/mods/car_theft_career/settings/races/" .. mapName .. ".json"

  -- Try to read from primary path first, then fallback
  local filePath = primaryPath
  local existingRaces = {}
  local content = readFile(primaryPath)
  if not content then
    content = readFile(fallbackPath)
    if content then
      filePath = fallbackPath
    end
  end

  if content then
    local success, data = pcall(jsonDecode, content)
    if success and data then
      existingRaces = data
    end
  end

  -- Initialize structure if needed
  if not existingRaces.version then
    existingRaces = {
      version = "1.0",
      map = mapName,
      races = {},
      encounters = {
        spawnChance = 0.003,
        cooldownMinutes = 10,
        finishDistance = 2000
      }
    }
  end

  -- Add/update race
  existingRaces.races[editorState.raceName] = raceData

  -- Ensure directory exists and save
  local jsonContent = jsonEncode(existingRaces)
  if not jsonContent then
    uiMessage("Error: Failed to encode JSON", 5, "error")
    return false
  end

  -- Write to source folder first (primary), then try fallback
  local success = writeFile(primaryPath, jsonContent)
  if success then
    filePath = primaryPath
    log("I", "Saved race to source folder: " .. primaryPath)
  else
    -- Try fallback path (mods folder)
    success = writeFile(fallbackPath, jsonContent)
    if success then
      filePath = fallbackPath
      log("I", "Saved race to mods folder: " .. fallbackPath)
    else
      uiMessage("Error: Failed to save file. Check console for details.", 5, "error")
      log("E", "Failed to write to: " .. primaryPath .. " or " .. fallbackPath)
      return false
    end
  end

  uiMessage("Race '" .. editorState.raceName .. "' saved successfully!", 5, "success")
  log("I", "Saved race to: " .. filePath)

  -- Clear editor state
  clearMarkers()
  editorState = {
    active = false,
    raceName = nil,
    startPos = nil,
    startRot = nil,
    startWidth = DEFAULT_START_WIDTH,
    finishPos = nil,
    finishRot = nil,
    finishWidth = DEFAULT_FINISH_WIDTH,
    checkpoints = {},
    markers = {}
  }

  -- Reload races in streetRacing module
  if extensions.carTheft_streetRacing then
    extensions.carTheft_streetRacing.loadRaces()
  end

  return true
end

-- Cancel editing and discard changes
-- Usage: carTheft_raceEditor.cancel()
function M.cancel()
  if not editorState.active then
    uiMessage("Editor not active.", 3, "info")
    return false
  end

  clearMarkers()
  editorState = {
    active = false,
    raceName = nil,
    startPos = nil,
    startRot = nil,
    startWidth = DEFAULT_START_WIDTH,
    finishPos = nil,
    finishRot = nil,
    finishWidth = DEFAULT_FINISH_WIDTH,
    checkpoints = {},
    markers = {}
  }

  uiMessage("Race editing cancelled.", 3, "info")
  return true
end

-- List all saved races for current map
-- Usage: carTheft_raceEditor.list()
function M.list()
  local mapName = getCurrentMapName()
  if not mapName then
    uiMessage("Could not determine current map", 5, "error")
    return
  end

  -- Try settings folder first, then fallback to mods folder
  local filePath = "/settings/races/" .. mapName .. ".json"
  local content = readFile(filePath)
  if not content then
    filePath = "/mods/car_theft_career/settings/races/" .. mapName .. ".json"
    content = readFile(filePath)
  end

  if not content then
    uiMessage("No races found for " .. mapName, 3, "info")
    return
  end

  local success, data = pcall(jsonDecode, content)
  if not success or not data or not data.races then
    uiMessage("Error reading races file", 5, "error")
    return
  end

  local count = 0
  log("I", "=== Races for " .. mapName .. " ===")
  for id, race in pairs(data.races) do
    count = count + 1
    log("I", string.format("%d. %s - %s (%d checkpoints)", count, id, race.name or id, race.checkpoints and #race.checkpoints or 0))
  end

  if count == 0 then
    uiMessage("No races found for " .. mapName, 3, "info")
  else
    uiMessage(count .. " race(s) found. Check console for list.", 5, "info")
  end
end

-- Delete a saved race
-- Usage: carTheft_raceEditor.delete("race_name")
function M.delete(raceName)
  if not raceName or raceName == "" then
    uiMessage("Usage: carTheft_raceEditor.delete(\"race_name\")", 5, "error")
    return false
  end

  local mapName = getCurrentMapName()
  if not mapName then
    uiMessage("Could not determine current map", 5, "error")
    return false
  end

  -- Try settings folder first, then fallback to mods folder
  local filePath = "/settings/races/" .. mapName .. ".json"
  local content = readFile(filePath)
  if not content then
    filePath = "/mods/car_theft_career/settings/races/" .. mapName .. ".json"
    content = readFile(filePath)
  end

  if not content then
    uiMessage("No races file found", 5, "error")
    return false
  end

  local success, data = pcall(jsonDecode, content)
  if not success or not data or not data.races then
    uiMessage("Error reading races file", 5, "error")
    return false
  end

  if not data.races[raceName] then
    uiMessage("Race not found: " .. raceName, 5, "error")
    return false
  end

  data.races[raceName] = nil

  local jsonContent = jsonEncode(data)
  writeFile(filePath, jsonContent)

  uiMessage("Race deleted: " .. raceName, 5, "success")

  -- Reload races
  if extensions.carTheft_streetRacing then
    extensions.carTheft_streetRacing.loadRaces()
  end

  return true
end

-- Help command
-- Usage: carTheft_raceEditor.help()
function M.help()
  local helpText = [[
=== Race Editor Commands ===

start("name")      - Start editing a new race
setstart(width)    - Set start line at current position
addcheckpoint(w)   - Add checkpoint at current position
removecheckpoint() - Remove last checkpoint
setfinish(width)   - Set finish line at current position
preview()          - Show visual markers for race
status()           - Show current editor status
save()             - Save race to JSON file
cancel()           - Discard changes and exit

list()             - List all saved races
delete("name")     - Delete a saved race
help()             - Show this help

Example workflow:
1. carTheft_raceEditor.start("downtown_run")
2. Drive to start, call setstart()
3. Drive through route, call addcheckpoint() at key points
4. Drive to finish, call setfinish()
5. Call preview() to verify
6. Call save() to save
]]

  log("I", helpText)
  uiMessage("Check console for help information", 5, "info")
end

---------------------------------------------------------------------------
-- Extension Hooks
---------------------------------------------------------------------------

local function onExtensionLoaded()
  log("I", "Race Editor extension loaded")
end

local function onExtensionUnloaded()
  log("I", "Race Editor extension unloaded")
  clearMarkers()
end

---------------------------------------------------------------------------
-- Module Exports
---------------------------------------------------------------------------

M.onExtensionLoaded = onExtensionLoaded
M.onExtensionUnloaded = onExtensionUnloaded

return M
