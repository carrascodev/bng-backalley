-- Car Theft Career - Centralized File Logging
-- Logs all mod activity to beamng_backalley.log in the career save folder

local M = {}

local logBuffer = {}
local LOG_FILE = "beamng_backalley.log"
local BUFFER_SIZE = 10  -- Flush after N entries
local MAX_LOG_SIZE = 1048576  -- 1MB max file size

---------------------------------------------------------------------------
-- Path Helpers
---------------------------------------------------------------------------

-- Get current save path (like RLS does)
local function getSavePath()
  if career_saveSystem and career_saveSystem.getCurrentSaveSlot then
    local _, savePath = career_saveSystem.getCurrentSaveSlot()
    return savePath
  end
  return nil
end

---------------------------------------------------------------------------
-- Timestamp
---------------------------------------------------------------------------

local function getTimestamp()
  return os.date("%Y-%m-%d %H:%M:%S")
end

---------------------------------------------------------------------------
-- File Operations
---------------------------------------------------------------------------

-- Write buffer to file
local function flushBuffer()
  local savePath = getSavePath()
  if not savePath or #logBuffer == 0 then return end

  local filePath = savePath .. "/" .. LOG_FILE
  local content = table.concat(logBuffer, "\n") .. "\n"

  -- Read existing content to append
  local existingContent = readFile(filePath) or ""

  -- Rotate if too large (keep last half)
  if #existingContent > MAX_LOG_SIZE then
    existingContent = existingContent:sub(-MAX_LOG_SIZE/2)
    -- Find first newline to start on clean line
    local firstNewline = existingContent:find("\n")
    if firstNewline then
      existingContent = "[...log truncated...]\n" .. existingContent:sub(firstNewline + 1)
    end
  end

  writeFile(filePath, existingContent .. content)
  logBuffer = {}
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

-- Main log function
-- source: module name (e.g., "carTheft_main")
-- level: "I" (info), "W" (warn), "E" (error)
-- message: log message
function M.log(source, level, message)
  local timestamp = getTimestamp()
  local entry = string.format("[%s] [%s] %s: %s", timestamp, source, level, tostring(message))

  -- Always print to console
  print(entry)

  -- Add to buffer
  table.insert(logBuffer, entry)

  -- Flush if buffer full or on error
  if #logBuffer >= BUFFER_SIZE or level == "E" then
    flushBuffer()
  end
end

-- Force flush (call on extension unload or critical events)
function M.flush()
  flushBuffer()
end

-- Convenience functions
function M.info(source, msg)
  M.log(source, "I", msg)
end

function M.warn(source, msg)
  M.log(source, "W", msg)
end

function M.error(source, msg)
  M.log(source, "E", msg)
end

-- Log with formatted string
function M.logf(source, level, fmt, ...)
  M.log(source, level, string.format(fmt, ...))
end

return M
