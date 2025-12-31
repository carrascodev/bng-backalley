-- Car Theft Career - Race Editor UI Backend
-- Provides UI interface for the Race Editor app

local M = {}

-- Logger module
local logger = require("carTheft/logger")
local LOG_TAG = "carTheft_raceEditorUI"

---------------------------------------------------------------------------
-- Configuration
---------------------------------------------------------------------------

local DEFAULT_CHECKPOINT_WIDTH = 12
local DEFAULT_START_WIDTH = 15
local DEFAULT_FINISH_WIDTH = 15

-- Race tracks filename (used for both user and default paths)
local RACES_FILENAME = "backAlley_raceTracks.json"

---------------------------------------------------------------------------
-- Editor State
---------------------------------------------------------------------------

local editorState = {
  active = false,
  currentTrackId = nil,
  trackData = nil,
  allRaces = {},
  mapName = nil
}

---------------------------------------------------------------------------
-- Utility Functions
---------------------------------------------------------------------------

local function log(level, msg)
  logger.log(LOG_TAG, level, msg)
end

local function uiMessage(msg, msgType)
  msgType = msgType or "info"
  guihooks.trigger('toastrMsg', {
    type = msgType,
    title = "Race Editor",
    msg = msg
  })
  log("I", msg)
end

local function sendToUI(event, data)
  guihooks.trigger(event, data)
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
  return nil
end

local function getPlayerRot()
  -- Use camera quaternion for accurate facing direction
  local camQuat = core_camera.getQuat()
  if camQuat then
    return camQuat
  end

  -- Fallback to vehicle direction
  local playerVehId = be:getPlayerVehicleID(0)
  if playerVehId then
    local veh = be:getObjectByID(playerVehId)
    if veh then
      local rot = quatFromDir(veh:getDirectionVector(), veh:getDirectionVectorUp())
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

local function teleportVehicle(pos, rot)
  local playerVehId = be:getPlayerVehicleID(0)
  if not playerVehId then
    uiMessage("No player vehicle", "error")
    return false
  end

  local veh = be:getObjectByID(playerVehId)
  if not veh then
    uiMessage("Vehicle not found", "error")
    return false
  end

  local position = vec3(pos.x, pos.y, pos.z + 0.5)
  local rotation = rot and quat(rot.x, rot.y, rot.z, rot.w) or quat(0, 0, 0, 1)

  -- safeTeleport multiplies by quat(0,0,1,0), so we pre-multiply by inverse to cancel it
  local correction = quat(0, 0, 1, 0):inversed()
  rotation = correction * rotation

  spawn.safeTeleport(veh, position, rotation, nil, nil, nil, true)
  return true
end

---------------------------------------------------------------------------
-- File Operations
---------------------------------------------------------------------------

local function getUserRacesPath()
  -- User's BeamNG settings folder (persists across mod updates)
  return "settings/" .. RACES_FILENAME
end

local function getDefaultRacesPath()
  -- Bundled default in mod folder (deployed with mod)
  return "car_theft_career/settings/" .. RACES_FILENAME
end

local function copyDefaultToUserIfNeeded()
  local userPath = getUserRacesPath()
  local defaultPath = getDefaultRacesPath()
  log("I", "DefaultPath:".. defaultPath .. " UserPath: " .. userPath)

  -- Check if user file already exists
  if readFile(userPath) then
    log("I", "User has file in settings!")
    return -- User already has a file, don't override
  end

  -- Read default from mod
  local defaultContent = readFile(defaultPath)
  log("I", "Default content:".. dump(defaultContent))
  if not defaultContent then
    return
  end

  -- Copy default to user path
  writeFile(userPath, defaultContent)
  log("I", "Copied default races to user settings")
end

local function loadRacesFile()
  -- Ensure user has a copy of default races
  copyDefaultToUserIfNeeded()

  -- Load from user path
  local userPath = getUserRacesPath()
  local content = readFile(userPath)

  if content then
    local success, data = pcall(jsonDecode, content)
    if success and data then
      log("I", "Loaded races from: " .. userPath)
      return data
    end
  end

  -- Return empty structure if no file exists
  log("I", "No races file found, starting with empty structure")
  return {
    version = "1.0",
    map = editorState.mapName or "unknown",
    races = {},
    encounters = {
      spawnChance = 0.003,
      cooldownMinutes = 10,
      finishDistance = 2000
    }
  }
end

local function saveRacesFile(data)
  -- Always save to user path (persists across mod updates)
  local userPath = getUserRacesPath()

  local jsonContent = jsonEncode(data)
  if not jsonContent then
    uiMessage("Failed to encode JSON", "error")
    return false
  end

  local success = writeFile(userPath, jsonContent)
  if success then
    log("I", "Saved races to: " .. userPath)
    return true
  else
    uiMessage("Failed to save file to: " .. userPath, "error")
    return false
  end
end

---------------------------------------------------------------------------
-- Track Management
---------------------------------------------------------------------------

function M.getTrackList()
  editorState.mapName = getCurrentMapName()
  if not editorState.mapName then
    sendToUI('RaceEditorError', {message = "Could not determine current map"})
    return
  end

  local data = loadRacesFile()
  editorState.allRaces = data

  local trackList = {}
  if data and data.races then
    for id, race in pairs(data.races) do
      table.insert(trackList, {
        id = id,
        name = race.name or id,
        checkpointCount = race.checkpoints and #race.checkpoints or 0
      })
    end
  end

  -- Sort by name
  table.sort(trackList, function(a, b) return a.name < b.name end)

  sendToUI('RaceEditorTrackList', trackList)
end

function M.loadTrack(trackId)
  if not trackId or trackId == "" then
    sendToUI('RaceEditorError', {message = "No track ID provided"})
    return
  end

  local data = loadRacesFile()
  if not data or not data.races or not data.races[trackId] then
    sendToUI('RaceEditorError', {message = "Track not found: " .. trackId})
    return
  end

  local race = data.races[trackId]

  -- Convert to UI format, ensuring spawns structure exists
  editorState.currentTrackId = trackId
  editorState.trackData = {
    id = trackId,
    name = race.name or trackId,
    spawns = race.spawns or {
      player = race.start and {pos = race.start.pos, rot = race.start.rot} or nil,
      adversaries = {}
    },
    checkpoints = race.checkpoints or {},
    finish = race.finish or nil,
    minBet = race.minBet or 1000,
    maxBet = race.maxBet or 50000,
    difficulty = race.difficulty or 2
  }

  -- Migrate old format: if spawns.player is nil but start exists, use start
  if not editorState.trackData.spawns.player and race.start then
    editorState.trackData.spawns.player = {
      pos = race.start.pos,
      rot = race.start.rot
    }
  end

  sendToUI('RaceEditorTrackLoaded', editorState.trackData)
  log("I", "Loaded track: " .. trackId)
end

function M.createNewTrack(name)
  -- Require a valid track name
  if not name or name == "" or name:match("^%s*$") then
    uiMessage("Track name is required", "error")
    return
  end

  -- Trim whitespace
  name = name:match("^%s*(.-)%s*$")

  -- Generate unique ID
  local id = string.lower(name):gsub("%s+", "_"):gsub("[^%w_]", "")
  local baseId = id
  local counter = 1

  local data = loadRacesFile()
  while data.races[id] do
    id = baseId .. "_" .. counter
    counter = counter + 1
  end

  -- Create new track
  editorState.currentTrackId = id
  editorState.trackData = {
    id = id,
    name = name,
    spawns = {
      player = nil,
      adversaries = {}
    },
    checkpoints = {},
    finish = nil,
    minBet = 1000,
    maxBet = 50000,
    difficulty = 2
  }

  sendToUI('RaceEditorNewTrack', {id = id, name = name})
  uiMessage("Created new track: " .. name, "success")
end

function M.saveTrack()
  if not editorState.currentTrackId or not editorState.trackData then
    uiMessage("No track to save", "error")
    return
  end

  -- Validate
  if not editorState.trackData.spawns or not editorState.trackData.spawns.player then
    uiMessage("Set player spawn position first", "error")
    return
  end

  if not editorState.trackData.finish then
    uiMessage("Set finish line first", "error")
    return
  end

  local data = loadRacesFile()

  -- Build race data with new spawn format
  local raceData = {
    id = editorState.currentTrackId,
    name = editorState.trackData.name,
    description = "Custom street race",
    type = "point_to_point",
    difficulty = editorState.trackData.difficulty or 2,
    minBet = editorState.trackData.minBet or 1000,
    maxBet = editorState.trackData.maxBet or 50000,
    -- Keep old start format for backward compatibility
    start = {
      pos = editorState.trackData.spawns.player.pos,
      rot = editorState.trackData.spawns.player.rot,
      width = DEFAULT_START_WIDTH
    },
    -- New spawns format
    spawns = editorState.trackData.spawns,
    checkpoints = editorState.trackData.checkpoints,
    finish = editorState.trackData.finish
  }

  data.races[editorState.currentTrackId] = raceData

  if saveRacesFile(data) then
    sendToUI('RaceEditorSaved', {success = true, id = editorState.currentTrackId})
    uiMessage("Track saved: " .. editorState.trackData.name, "success")

    -- Reload races in streetRacing module
    if extensions.carTheft_streetRacing then
      extensions.carTheft_streetRacing.loadRaces()
    end
  end
end

function M.deleteTrack(trackId)
  if not trackId or trackId == "" then
    uiMessage("No track ID provided", "error")
    return
  end

  local data = loadRacesFile()
  if not data.races[trackId] then
    uiMessage("Track not found", "error")
    return
  end

  data.races[trackId] = nil

  if saveRacesFile(data) then
    editorState.currentTrackId = nil
    editorState.trackData = nil
    sendToUI('RaceEditorDeleted', {id = trackId})
    uiMessage("Track deleted", "success")

    -- Reload races
    if extensions.carTheft_streetRacing then
      extensions.carTheft_streetRacing.loadRaces()
    end
  end
end

function M.updateTrackName(name)
  if not editorState.trackData then
    return
  end

  if name and name ~= "" then
    editorState.trackData.name = name
    log("I", "Track name updated to: " .. name)
  end
end

---------------------------------------------------------------------------
-- Spawn Position Management
---------------------------------------------------------------------------

function M.setPlayerSpawn()
  if not editorState.trackData then
    uiMessage("Load or create a track first", "error")
    return
  end

  local pos = getPlayerPos()
  if not pos then
    uiMessage("Could not get player position", "error")
    return
  end

  local rot = getPlayerRot()

  editorState.trackData.spawns.player = {
    pos = posToTable(pos),
    rot = quatToTable(rot)
  }

  sendToUI('RaceEditorSpawnsUpdated', editorState.trackData.spawns)
  uiMessage("Player spawn set", "success")
end

function M.clearPlayerSpawn()
  if not editorState.trackData then return end

  editorState.trackData.spawns.player = nil
  sendToUI('RaceEditorSpawnsUpdated', editorState.trackData.spawns)
end

function M.addAdversarySpawn()
  if not editorState.trackData then
    uiMessage("Load or create a track first", "error")
    return
  end

  local pos = getPlayerPos()
  if not pos then
    uiMessage("Could not get player position", "error")
    return
  end

  local rot = getPlayerRot()

  table.insert(editorState.trackData.spawns.adversaries, {
    pos = posToTable(pos),
    rot = quatToTable(rot)
  })

  sendToUI('RaceEditorSpawnsUpdated', editorState.trackData.spawns)
  uiMessage("Adversary spawn #" .. #editorState.trackData.spawns.adversaries .. " added", "success")
end

function M.removeAdversarySpawn(index)
  if not editorState.trackData then return end

  -- Lua is 1-indexed, JS is 0-indexed
  local luaIndex = index + 1

  if luaIndex > 0 and luaIndex <= #editorState.trackData.spawns.adversaries then
    table.remove(editorState.trackData.spawns.adversaries, luaIndex)
    sendToUI('RaceEditorSpawnsUpdated', editorState.trackData.spawns)
  end
end

function M.teleportToPlayerSpawn()
  if not editorState.trackData or not editorState.trackData.spawns.player then
    uiMessage("No player spawn set", "error")
    return
  end

  teleportVehicle(editorState.trackData.spawns.player.pos, editorState.trackData.spawns.player.rot)
end

function M.teleportToAdversarySpawn(index)
  if not editorState.trackData then return end

  local luaIndex = index + 1
  local adv = editorState.trackData.spawns.adversaries[luaIndex]
  if adv then
    teleportVehicle(adv.pos, adv.rot)
  end
end

---------------------------------------------------------------------------
-- Checkpoint Management
---------------------------------------------------------------------------

function M.addCheckpoint()
  if not editorState.trackData then
    uiMessage("Load or create a track first", "error")
    return
  end

  local pos = getPlayerPos()
  if not pos then
    uiMessage("Could not get player position", "error")
    return
  end

  local checkpoint = {
    index = #editorState.trackData.checkpoints + 1,
    node = {
      x = pos.x,
      y = pos.y,
      z = pos.z,
      width = DEFAULT_CHECKPOINT_WIDTH
    }
  }

  table.insert(editorState.trackData.checkpoints, checkpoint)
  sendToUI('RaceEditorCheckpointsUpdated', editorState.trackData.checkpoints)
  uiMessage("Checkpoint " .. #editorState.trackData.checkpoints .. " added", "success")
end

function M.removeCheckpoint(index)
  if not editorState.trackData then return end

  local luaIndex = index + 1
  if luaIndex > 0 and luaIndex <= #editorState.trackData.checkpoints then
    table.remove(editorState.trackData.checkpoints, luaIndex)

    -- Re-index remaining checkpoints
    for i, cp in ipairs(editorState.trackData.checkpoints) do
      cp.index = i
    end

    sendToUI('RaceEditorCheckpointsUpdated', editorState.trackData.checkpoints)
  end
end

function M.teleportToCheckpoint(index)
  if not editorState.trackData then return end

  local luaIndex = index + 1
  local cp = editorState.trackData.checkpoints[luaIndex]
  if cp and cp.node then
    teleportVehicle(cp.node, nil)
  end
end

function M.setCheckpointWidth(index, width)
  if not editorState.trackData then return end

  local luaIndex = index + 1
  local cp = editorState.trackData.checkpoints[luaIndex]
  if cp and cp.node then
    cp.node.width = width or DEFAULT_CHECKPOINT_WIDTH
  end
end

---------------------------------------------------------------------------
-- Finish Line Management
---------------------------------------------------------------------------

function M.setFinishLine()
  if not editorState.trackData then
    uiMessage("Load or create a track first", "error")
    return
  end

  local pos = getPlayerPos()
  if not pos then
    uiMessage("Could not get player position", "error")
    return
  end

  local rot = getPlayerRot()

  editorState.trackData.finish = {
    pos = posToTable(pos),
    rot = quatToTable(rot),
    width = DEFAULT_FINISH_WIDTH
  }

  sendToUI('RaceEditorFinishUpdated', editorState.trackData.finish)
  uiMessage("Finish line set", "success")
end

function M.clearFinishLine()
  if not editorState.trackData then return end

  editorState.trackData.finish = nil
  sendToUI('RaceEditorFinishUpdated', nil)
end

function M.teleportToFinish()
  if not editorState.trackData or not editorState.trackData.finish then
    uiMessage("No finish line set", "error")
    return
  end

  teleportVehicle(editorState.trackData.finish.pos, editorState.trackData.finish.rot)
end

---------------------------------------------------------------------------
-- Settings Management
---------------------------------------------------------------------------

function M.updateSettings(settings)
  if not editorState.trackData then return end

  if settings.minBet then editorState.trackData.minBet = settings.minBet end
  if settings.maxBet then editorState.trackData.maxBet = settings.maxBet end
  if settings.difficulty then editorState.trackData.difficulty = settings.difficulty end
end

---------------------------------------------------------------------------
-- Simulation & Preview
---------------------------------------------------------------------------

function M.simulate()
  if not editorState.trackData then
    uiMessage("Load a track first", "error")
    return
  end

  if not editorState.trackData.spawns or not editorState.trackData.spawns.player then
    uiMessage("Set player spawn first", "error")
    return
  end

  -- Save track first
  M.saveTrack()

  -- Use debugStartRace from streetRacing
  if extensions.carTheft_streetRacing and extensions.carTheft_streetRacing.debugStartRace then
    extensions.carTheft_streetRacing.debugStartRace(editorState.currentTrackId, "covet")
    sendToUI('RaceEditorSimulating', {started = true})
  else
    uiMessage("Street racing module not available", "error")
  end
end

-- Store created preview markers
local previewMarkers = {}

-- Create a visual marker at position with color
local function createPreviewMarker(name, pos, color, scale)
  scale = scale or 3

  local marker = createObject('TSStatic')
  marker.shapeName = "art/shapes/interface/checkpoint_marker.dae"
  marker:setPosRot(pos.x, pos.y, pos.z + 1, 0, 0, 0, 1)
  marker.scale = vec3(scale, scale, scale)
  marker.useInstanceRenderData = true

  -- Set color (RGBA)
  if color == "green" then
    marker.instanceColor = ColorF(0, 1, 0, 0.8):asLinear4F()
  elseif color == "red" then
    marker.instanceColor = ColorF(1, 0, 0, 0.8):asLinear4F()
  elseif color == "yellow" then
    marker.instanceColor = ColorF(1, 1, 0, 0.8):asLinear4F()
  elseif color == "blue" then
    marker.instanceColor = ColorF(0, 0.5, 1, 0.8):asLinear4F()
  else
    marker.instanceColor = ColorF(1, 1, 1, 0.8):asLinear4F()
  end

  -- Remove existing marker with same name
  local existing = scenetree.findObject(name)
  if existing then
    existing:delete()
  end

  marker:registerObject(name)
  table.insert(previewMarkers, marker)

  return marker
end

function M.previewRoute()
  if not editorState.trackData then
    uiMessage("Load a track first", "error")
    return
  end

  -- Clear existing markers first
  M.clearMarkers()

  local markerCount = 0

  -- Start line marker (green)
  if editorState.trackData.spawns and editorState.trackData.spawns.player then
    local pos = editorState.trackData.spawns.player.pos
    createPreviewMarker("re_preview_start", pos, "green", 5)
    markerCount = markerCount + 1
  end

  -- Adversary spawn markers (red)
  if editorState.trackData.spawns and editorState.trackData.spawns.adversaries then
    for i, adv in ipairs(editorState.trackData.spawns.adversaries) do
      createPreviewMarker("re_preview_adv_" .. i, adv.pos, "red", 4)
      markerCount = markerCount + 1
    end
  end

  -- Checkpoint markers (yellow)
  if editorState.trackData.checkpoints then
    for i, cp in ipairs(editorState.trackData.checkpoints) do
      if cp.node then
        createPreviewMarker("re_preview_cp_" .. i, cp.node, "yellow", cp.node.width or 12)
        markerCount = markerCount + 1
      end
    end
  end

  -- Finish marker (blue)
  if editorState.trackData.finish and editorState.trackData.finish.pos then
    createPreviewMarker("re_preview_finish", editorState.trackData.finish.pos, "blue", 5)
    markerCount = markerCount + 1
  end

  uiMessage("Preview: " .. markerCount .. " markers shown", "success")
  log("I", "Preview showing " .. markerCount .. " markers")
end

function M.clearMarkers()
  -- Delete all preview markers
  for _, marker in ipairs(previewMarkers) do
    if marker and marker:isValid() then
      marker:delete()
    end
  end
  previewMarkers = {}

  -- Also clean up by name pattern in case of orphaned markers
  local names = {"re_preview_start", "re_preview_finish"}
  for i = 1, 10 do
    table.insert(names, "re_preview_adv_" .. i)
    table.insert(names, "re_preview_cp_" .. i)
  end

  for _, name in ipairs(names) do
    local obj = scenetree.findObject(name)
    if obj then
      obj:delete()
    end
  end

  log("I", "Preview markers cleared")
end

---------------------------------------------------------------------------
-- Editing State
---------------------------------------------------------------------------

function M.startEditing()
  editorState.active = true
  editorState.mapName = getCurrentMapName()

  if not editorState.mapName then
    uiMessage("Could not determine current map", "error")
    return
  end

  log("I", "Race Editor UI started for map: " .. editorState.mapName)
end

function M.stopEditing()
  editorState.active = false
  M.clearMarkers()
  log("I", "Race Editor UI stopped")
end

---------------------------------------------------------------------------
-- Extension Hooks
---------------------------------------------------------------------------

local function onExtensionLoaded()
  log("I", "Race Editor UI extension loaded")
end

local function onExtensionUnloaded()
  log("I", "Race Editor UI extension unloaded")
  M.stopEditing()
end

---------------------------------------------------------------------------
-- Module Exports
---------------------------------------------------------------------------

M.onExtensionLoaded = onExtensionLoaded
M.onExtensionUnloaded = onExtensionUnloaded

return M
