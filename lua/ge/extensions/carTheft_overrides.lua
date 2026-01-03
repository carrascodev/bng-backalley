-- carTheft_overrides.lua
-- Extension wrapper for carTheft/overrides.lua

local M = {}

local overrides = require("carTheft/overrides")

-- Forward all functions
M.applyOverrides = overrides.applyOverrides
M.onUpdate = overrides.onUpdate

return M
