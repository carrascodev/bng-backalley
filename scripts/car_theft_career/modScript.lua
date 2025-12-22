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
