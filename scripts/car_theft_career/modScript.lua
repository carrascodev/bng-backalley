-- Car Theft Career Mod
-- Loads all carTheft extensions when mod is activated

-- Safely load the main extension
local success, err = pcall(function()
  load("carTheft_main")
  setExtensionUnloadMode("carTheft_main", "manual")
end)

if not success then
  print("[CarTheft] Failed to load main extension: " .. tostring(err))
end

-- Load job manager extension
local success2, err2 = pcall(function()
  load("carTheft_jobManager")
  setExtensionUnloadMode("carTheft_jobManager", "manual")
end)

if not success2 then
  print("[CarTheft] Failed to load job manager: " .. tostring(err2))
end

-- Load street racing extension
local success3, err3 = pcall(function()
  load("carTheft_streetRacing")
  setExtensionUnloadMode("carTheft_streetRacing", "manual")
end)

if not success3 then
  print("[CarTheft] Failed to load street racing: " .. tostring(err3))
end

-- Load race editor extension
local success4, err4 = pcall(function()
  load("carTheft_raceEditor")
  setExtensionUnloadMode("carTheft_raceEditor", "manual")
end)

if not success4 then
  print("[CarTheft] Failed to load race editor: " .. tostring(err4))
end
