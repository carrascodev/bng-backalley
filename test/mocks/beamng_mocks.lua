-- BeamNG API Mocks for Unit Testing
-- Run Lua tests outside of BeamNG game environment

local M = {}

---------------------------------------------------------------------------
-- Logging
---------------------------------------------------------------------------

_G.log = function(level, msg)
  -- Silent by default, set _G.VERBOSE_LOGGING = true to see logs
  if _G.VERBOSE_LOGGING then
    print(string.format("[%s] %s", level, msg))
  end
end

---------------------------------------------------------------------------
-- Math Types (vec3, quat)
---------------------------------------------------------------------------

local function createVec3(x, y, z)
  local v = {x = x or 0, y = y or 0, z = z or 0}

  function v:distance(other)
    local dx = self.x - other.x
    local dy = self.y - other.y
    local dz = self.z - other.z
    return math.sqrt(dx*dx + dy*dy + dz*dz)
  end

  function v:__tostring()
    return string.format("vec3(%.2f, %.2f, %.2f)", self.x, self.y, self.z)
  end

  setmetatable(v, {__tostring = v.__tostring})
  return v
end

local function createQuat(x, y, z, w)
  return {x = x or 0, y = y or 0, z = z or 0, w = w or 1}
end

_G.vec3 = createVec3
_G.quat = createQuat

---------------------------------------------------------------------------
-- Vehicle System (be:*)
---------------------------------------------------------------------------

local mockVehicles = {}
local nextVehicleId = 1000

_G.be = {
  getPlayerVehicleID = function(index)
    return 1  -- Return mock player vehicle ID
  end,

  getObjectByID = function(id)
    return mockVehicles[id] or {
      getID = function() return id end,
      getPosition = function() return createVec3(0, 0, 0) end,
      delete = function() mockVehicles[id] = nil end,
      queueLuaCommand = function() end,
      playerUsable = true
    }
  end,

  enterVehicle = function() end,
  exitVehicle = function() end
}

-- Helper to create mock vehicle
M.createMockVehicle = function(pos)
  local id = nextVehicleId
  nextVehicleId = nextVehicleId + 1
  mockVehicles[id] = {
    getID = function() return id end,
    getPosition = function() return pos or createVec3(0, 0, 0) end,
    delete = function() mockVehicles[id] = nil end,
    queueLuaCommand = function() end,
    playerUsable = true
  }
  return id, mockVehicles[id]
end

---------------------------------------------------------------------------
-- Scene Tree
---------------------------------------------------------------------------

_G.scenetree = {
  findObject = function(name)
    return nil  -- No objects by default
  end
}

---------------------------------------------------------------------------
-- Core Vehicles
---------------------------------------------------------------------------

_G.core_vehicles = {
  spawnNewVehicle = function(model, options)
    local id, veh = M.createMockVehicle(options and options.pos)
    return veh
  end,

  getConfig = function(model, configKey)
    return {
      Value = 25000,  -- Default mock value
      Name = model .. " " .. (configKey or "default")
    }
  end
}

---------------------------------------------------------------------------
-- Core Ground Markers (GPS)
---------------------------------------------------------------------------

_G.core_groundMarkers = {
  setPath = function(pos)
    return true
  end
}

---------------------------------------------------------------------------
-- Gameplay Modules
---------------------------------------------------------------------------

-- Mock parking spots
local mockParkingSpots = {}
for i = 1, 20 do
  table.insert(mockParkingSpots, {
    name = "parking_spot_" .. i,
    pos = createVec3(-800 + i * 50, 100 + i * 20, 0),
    rot = createQuat(0, 0, 0, 1),
    vehicle = nil
  })
end

_G.gameplay_parking = {
  getParkingSpots = function()
    return { sorted = mockParkingSpots, objects = mockParkingSpots }
  end
}

_G.gameplay_city = {
  loadSites = function() end,
  getSites = function()
    return { parkingSpots = { sorted = mockParkingSpots } }
  end
}

_G.gameplay_sites_sitesManager = {
  getCurrentLevelSitesFileByName = function(name)
    return "/mock/path/city.sites.json"
  end,
  loadSites = function(path, a, b)
    return { parkingSpots = { sorted = mockParkingSpots } }
  end
}

_G.gameplay_walk = {
  isWalking = function() return false end,
  getInVehicle = function() end,
  setWalkingMode = function() end
}

---------------------------------------------------------------------------
-- Vehicle Config Generator
---------------------------------------------------------------------------

local mockVehicleConfigs = {
  {model_key = "etk800", key = "base", Name = "ETK 800", Value = 35000, aggregates = {Type = {Sedan = true}}},
  {model_key = "etk800", key = "sport", Name = "ETK 800 Sport", Value = 45000, aggregates = {Type = {Sedan = true}}},
  {model_key = "covet", key = "base", Name = "Ibishu Covet", Value = 8000, aggregates = {Type = {Hatchback = true}}},
  {model_key = "vivace", key = "base", Name = "Cherrier Vivace", Value = 12000, aggregates = {Type = {Hatchback = true}}},
  {model_key = "bluebuck", key = "base", Name = "Bruckell Bluebuck", Value = 28000, aggregates = {Type = {Sedan = true}}},
  {model_key = "legran", key = "base", Name = "Bruckell LeGran", Value = 18000, aggregates = {Type = {Sedan = true}}},
  {model_key = "pessima", key = "base", Name = "Hirochi Pessima", Value = 15000, aggregates = {Type = {Sedan = true}}},
  {model_key = "sunburst", key = "base", Name = "Hirochi Sunburst", Value = 22000, aggregates = {Type = {Coupe = true}}},
  {model_key = "barstow", key = "base", Name = "Gavril Barstow", Value = 32000, aggregates = {Type = {Muscle = true}}},
  {model_key = "bolide", key = "base", Name = "Civetta Bolide", Value = 75000, aggregates = {Type = {Supercar = true}}},
}

_G.util_configListGenerator = {
  getEligibleVehicles = function()
    return mockVehicleConfigs
  end
}

---------------------------------------------------------------------------
-- Career System
---------------------------------------------------------------------------

local mockPlayerMoney = 50000
local mockInventory = {}
local nextInventoryId = 100

_G.career_career = {
  isActive = function() return true end,
  closeAllMenus = function() end
}

_G.career_modules_playerAttributes = {
  getAttribute = function(name)
    if name == "money" then
      return { value = mockPlayerMoney }
    end
    return nil
  end,
  getAttributeValue = function(name)
    if name == "money" then
      return mockPlayerMoney
    end
    return nil
  end
}

M.setPlayerMoney = function(amount)
  mockPlayerMoney = amount
end

M.getPlayerMoney = function()
  return mockPlayerMoney
end

_G.career_modules_payment = {
  pay = function(amounts, options)
    if amounts.money then
      mockPlayerMoney = mockPlayerMoney - amounts.money.amount
    end
    return true
  end
}

_G.career_modules_inventory = {
  addVehicle = function(vehId, data, options)
    local id = nextInventoryId
    nextInventoryId = nextInventoryId + 1
    mockInventory[id] = {
      id = id,
      vehId = vehId,
      isStolen = false,
      hasDocuments = true,
      niceName = "Mock Vehicle " .. id,
      configBaseValue = 25000
    }
    return id
  end,

  getVehicles = function()
    return mockInventory
  end,

  removeVehicle = function(inventoryId)
    mockInventory[inventoryId] = nil
    return true
  end,

  moveVehicleToGarage = function(inventoryId, garageId)
    return true
  end
}

M.addMockInventoryVehicle = function(data)
  local id = nextInventoryId
  nextInventoryId = nextInventoryId + 1
  mockInventory[id] = {
    id = id,
    vehId = 1,
    isStolen = data.isStolen or false,
    hasDocuments = data.hasDocuments or false,
    niceName = data.niceName or "Mock Vehicle " .. id,
    configBaseValue = data.value or 25000
  }
  return id
end

M.clearInventory = function()
  mockInventory = {}
end

_G.career_modules_garageManager = {
  getPurchasedGarages = function()
    return {"main_garage"}
  end
}

---------------------------------------------------------------------------
-- GUI Hooks
---------------------------------------------------------------------------

local triggeredHooks = {}

_G.guihooks = {
  trigger = function(hookName, data)
    table.insert(triggeredHooks, {name = hookName, data = data})
  end
}

M.getTriggeredHooks = function()
  return triggeredHooks
end

M.clearTriggeredHooks = function()
  triggeredHooks = {}
end

---------------------------------------------------------------------------
-- UI Message
---------------------------------------------------------------------------

_G.ui_message = function(msg, duration, type)
  if _G.VERBOSE_LOGGING then
    print(string.format("[UI] %s: %s", type or "info", msg))
  end
end

---------------------------------------------------------------------------
-- Extensions System
---------------------------------------------------------------------------

_G.extensions = {}

---------------------------------------------------------------------------
-- Traffic / Pursuit
---------------------------------------------------------------------------

_G.gameplay_traffic = {
  insertTraffic = function() end,
  getTrafficData = function() return {} end
}

---------------------------------------------------------------------------
-- Freeroam Facilities
---------------------------------------------------------------------------

_G.freeroam_facilities = {
  getFacility = function(type, name)
    if type == "garage" then
      return {
        pos = createVec3(-700, 200, 0)
      }
    end
    return nil
  end
}

---------------------------------------------------------------------------
-- Package/Require Override
---------------------------------------------------------------------------

-- Store original require
local originalRequire = require

-- Module cache for testing
local testModuleCache = {}

M.mockModule = function(name, module)
  testModuleCache[name] = module
end

M.clearModuleCache = function()
  testModuleCache = {}
end

-- Override require to use mocks when available
_G.require = function(modname)
  if testModuleCache[modname] then
    return testModuleCache[modname]
  end
  return originalRequire(modname)
end

---------------------------------------------------------------------------
-- Reset All Mocks
---------------------------------------------------------------------------

M.resetAll = function()
  mockVehicles = {}
  nextVehicleId = 1000
  mockPlayerMoney = 50000
  mockInventory = {}
  nextInventoryId = 100
  triggeredHooks = {}
  M.clearModuleCache()
end

return M
