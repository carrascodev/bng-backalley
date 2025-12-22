-- Car Theft Career - UI Integration
-- Handles UI updates and displays for the car theft system

local M = {}

local config = require("carTheft/config")

-- UI state
local lastState = nil
local showingPrompt = false

---------------------------------------------------------------------------
-- UI Message Helpers
---------------------------------------------------------------------------

local function formatTime(seconds)
  if seconds <= 0 then return "0:00" end
  local mins = math.floor(seconds / 60)
  local secs = math.floor(seconds % 60)
  return string.format("%d:%02d", mins, secs)
end

local function getWantedLevelText(level)
  if level == 0 then return "" end
  if level == 1 then return "WANTED" end
  if level == 2 then return "WANTED - BACKUP CALLED" end
  if level == 3 then return "WANTED - ROADBLOCKS" end
  return "WANTED"
end

local function getWantedLevelColor(level)
  if level == 0 then return {1, 1, 1, 1} end
  if level == 1 then return {1, 0.8, 0, 1} end  -- Yellow
  if level == 2 then return {1, 0.5, 0, 1} end  -- Orange
  if level == 3 then return {1, 0, 0, 1} end    -- Red
  return {1, 1, 1, 1}
end

---------------------------------------------------------------------------
-- UI Update Handler
---------------------------------------------------------------------------

local function onCarTheftUpdate(data)
  if not data then return end

  -- Handle steal prompt while walking near vehicle
  if data.state == "idle" and data.nearbyVehicle and config.SHOW_STEAL_PROMPT then
    if not showingPrompt then
      showingPrompt = true
      -- Note: The actual prompt is shown via ui_message in main.lua
      -- This hook can be extended for custom UI if needed
    end
  else
    showingPrompt = false
  end

  -- Update UI state for timer display
  if data.state == "hot" and config.SHOW_TIMER_UI then
    local timeStr = formatTime(data.reportTimer)
    -- Timer is displayed via guihooks which the game UI listens to
  end

  -- Update wanted level display
  if data.state == "reported" and config.SHOW_WANTED_LEVEL then
    local wantedText = getWantedLevelText(data.escalationLevel)
    local wantedColor = getWantedLevelColor(data.escalationLevel)
    -- Wanted level is displayed via guihooks
  end

  lastState = data.state
end

---------------------------------------------------------------------------
-- Extension Registration
---------------------------------------------------------------------------

-- Register for carTheft UI updates
local function onExtensionLoaded()
  -- Subscribe to carTheftUpdate events
end

M.onCarTheftUpdate = onCarTheftUpdate
M.onExtensionLoaded = onExtensionLoaded

return M
