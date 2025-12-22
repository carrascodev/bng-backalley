-- carTheft_overrides.lua
-- Extension wrapper for carTheft/overrides.lua

local M = {}

local overrides = require("carTheft/overrides")

-- Forward all functions
M.applyOverrides = overrides.applyOverrides
M.onExtensionLoaded = overrides.onExtensionLoaded
M.onCareerModulesActivated = overrides.onCareerModulesActivated
M.onUpdate = overrides.onUpdate

return M
