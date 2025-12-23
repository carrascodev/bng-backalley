-- documentation.lua
-- LegitDocs service - Purchase fake documentation for stolen vehicles
-- Features: tiered pricing (budget/standard/premium), game-time based processing

local M = {}

-- Logger module
local logger = require("carTheft/logger")
local LOG_TAG = "carTheft_documentation"

---------------------------------------------------------------------------
-- Dependencies
---------------------------------------------------------------------------

local config = nil

local function getConfig()
  if not config then
    local success, mod = pcall(require, "carTheft/config")
    if success then config = mod end
  end
  return config
end

local function getCarTheftMain()
  return extensions.carTheft_main or carTheft_main
end

local function log(level, msg)
  logger.log(LOG_TAG, level, msg)
end

---------------------------------------------------------------------------
-- Tier Helpers
---------------------------------------------------------------------------

local function getTierConfig(tierName)
  local cfg = getConfig()
  if not cfg then return nil end

  if tierName == "budget" then
    return cfg.DOC_TIER_BUDGET
  elseif tierName == "standard" then
    return cfg.DOC_TIER_STANDARD
  elseif tierName == "premium" then
    return cfg.DOC_TIER_PREMIUM
  end
  return nil
end

-- Get all tier info for UI display
function M.getTierInfo()
  local cfg = getConfig()
  if not cfg then return {} end

  -- Defensive access to tier configs
  local budget = cfg.DOC_TIER_BUDGET or {}
  local standard = cfg.DOC_TIER_STANDARD or {}
  local premium = cfg.DOC_TIER_PREMIUM or {}

  return {
    budget = {
      name = "Budget",
      description = "Cheap but slow (" .. (budget.hours or 8) .. " game hours)",
      costPercent = budget.costPercent or 0.15,
      costMin = budget.costMin or 5000,
      hours = budget.hours or 8,
      detectChance = budget.detectChance or 0.40
    },
    standard = {
      name = "Standard",
      description = "Better quality (" .. (standard.hours or 16) .. " game hours)",
      costPercent = standard.costPercent or 0.25,
      costMin = standard.costMin or 10000,
      hours = standard.hours or 16,
      detectChance = standard.detectChance or 0.15
    },
    premium = {
      name = "Premium",
      description = "Instant, nearly undetectable ($" .. (premium.cost or 100000) .. ")",
      cost = premium.cost or 100000,
      detectChance = premium.detectChance or 0.02
    }
  }
end

---------------------------------------------------------------------------
-- Fee Calculation
---------------------------------------------------------------------------

-- Get vehicle value from inventory
local function getVehicleValue(inventoryId)
  local main = getCarTheftMain()
  if not main or not main.getStolenVehicles then return 10000 end

  local success, vehicles = pcall(function() return main.getStolenVehicles() end)
  if not success or not vehicles then return 10000 end

  for _, veh in ipairs(vehicles) do
    if veh and tostring(veh.inventoryId) == tostring(inventoryId) then
      return veh.value or 10000
    end
  end
  return 10000
end

-- Calculate documentation fee for a vehicle and tier
function M.getDocumentFee(inventoryId, tierName)
  local cfg = getConfig()
  if not cfg then return nil end

  local value = getVehicleValue(inventoryId)

  if tierName == "budget" then
    local tierCfg = cfg.DOC_TIER_BUDGET or {}
    local costPercent = tierCfg.costPercent or 0.15
    local costMin = tierCfg.costMin or 5000
    return math.max(costMin, math.floor(value * costPercent))

  elseif tierName == "standard" then
    local tierCfg = cfg.DOC_TIER_STANDARD or {}
    local costPercent = tierCfg.costPercent or 0.25
    local costMin = tierCfg.costMin or 10000
    return math.max(costMin, math.floor(value * costPercent))

  elseif tierName == "premium" then
    local tierCfg = cfg.DOC_TIER_PREMIUM or {}
    return tierCfg.cost or 100000
  end

  return nil
end

-- Get all fees for a vehicle (for UI)
function M.getAllFees(inventoryId)
  local fees = {
    budget = nil,
    standard = nil,
    premium = nil
  }

  -- Get fees with pcall to prevent errors
  pcall(function() fees.budget = M.getDocumentFee(inventoryId, "budget") end)
  pcall(function() fees.standard = M.getDocumentFee(inventoryId, "standard") end)
  pcall(function() fees.premium = M.getDocumentFee(inventoryId, "premium") end)

  return fees
end

---------------------------------------------------------------------------
-- Document Ordering
---------------------------------------------------------------------------

-- Order documents for a vehicle (behavior depends on tier)
function M.orderDocuments(inventoryId, tierName)
  log("I", "Ordering " .. tierName .. " documents for vehicle: " .. tostring(inventoryId))

  local cfg = getConfig()
  if not cfg then
    return false, "Config not loaded"
  end

  -- Check if vehicle exists and is undocumented
  local main = getCarTheftMain()
  if not main or not main.isVehicleUndocumented then
    log("E", "carTheft_main not available")
    return false, "System error"
  end

  if not main.isVehicleUndocumented(inventoryId) then
    log("W", "Vehicle is not undocumented or doesn't exist")
    return false, "Vehicle already has documents or is not stolen"
  end

  -- Check if already pending
  if main.isDocumentsPending and main.isDocumentsPending(inventoryId) then
    return false, "Documents already being processed"
  end

  -----------------------------------------------------------------
  -- BUDGET TIER: Pay fee, wait for processing (game time)
  -----------------------------------------------------------------
  if tierName == "budget" then
    local fee = M.getDocumentFee(inventoryId, "budget")
    if not fee then
      return false, "Could not calculate fee"
    end

    -- Check money
    if not career_modules_playerAttributes then
      return false, "Career system not available"
    end
    local playerMoney = career_modules_playerAttributes.getAttributeValue("money") or 0
    if playerMoney < fee then
      return false, "Not enough money ($" .. fee .. " required)"
    end

    -- Deduct money
    if career_modules_payment and career_modules_payment.pay then
      career_modules_payment.pay({
        money = { amount = fee, canBeNegative = false }
      }, {
        label = "Document Processing Fee (Budget)",
        tags = { "gameplay", "carTheft", "documentation" }
      })
    else
      return false, "Payment system error"
    end

    -- Start processing (game-time based)
    local tierCfg = cfg.DOC_TIER_BUDGET or {}
    local hours = tierCfg.hours or 8

    if main.startDocumentProcessing then
      local success = main.startDocumentProcessing(inventoryId, tierName, hours)
      if not success then
        return false, "Failed to process order"
      end
    else
      return false, "System error"
    end

    log("I", "Budget documents ordered. Ready in " .. hours .. " game hours")
    if ui_message then
      ui_message("Documents ordered! Ready in " .. hours .. " game hour(s).", 5, "info")
    end

    return true, "Documents ordered successfully"

  -----------------------------------------------------------------
  -- STANDARD TIER: Pay higher fee, wait longer (game time)
  -----------------------------------------------------------------
  elseif tierName == "standard" then
    local fee = M.getDocumentFee(inventoryId, "standard")
    if not fee then
      return false, "Could not calculate fee"
    end

    -- Check money
    if not career_modules_playerAttributes then
      return false, "Career system not available"
    end
    local playerMoney = career_modules_playerAttributes.getAttributeValue("money") or 0
    if playerMoney < fee then
      return false, "Not enough money ($" .. fee .. " required)"
    end

    -- Deduct money
    if career_modules_payment and career_modules_payment.pay then
      career_modules_payment.pay({
        money = { amount = fee, canBeNegative = false }
      }, {
        label = "Document Processing Fee (Standard)",
        tags = { "gameplay", "carTheft", "documentation" }
      })
    else
      return false, "Payment system error"
    end

    -- Start processing (game-time based)
    local tierCfg = cfg.DOC_TIER_STANDARD or {}
    local hours = tierCfg.hours or 16

    if main.startDocumentProcessing then
      local success = main.startDocumentProcessing(inventoryId, tierName, hours)
      if not success then
        return false, "Failed to process order"
      end
    else
      return false, "System error"
    end

    log("I", "Standard documents ordered. Ready in " .. hours .. " game hours")
    if ui_message then
      ui_message("Documents ordered! Ready in " .. hours .. " game hour(s).", 5, "info")
    end

    return true, "Documents ordered successfully"

  -----------------------------------------------------------------
  -- PREMIUM TIER: Pay flat fee, instant documents
  -----------------------------------------------------------------
  elseif tierName == "premium" then
    local fee = M.getDocumentFee(inventoryId, "premium")
    if not fee then
      return false, "Could not calculate fee"
    end

    -- Check money
    if not career_modules_playerAttributes then
      return false, "Career system not available"
    end
    local playerMoney = career_modules_playerAttributes.getAttributeValue("money") or 0
    if playerMoney < fee then
      return false, "Not enough money ($" .. fee .. " required)"
    end

    -- Deduct money
    if career_modules_payment and career_modules_payment.pay then
      career_modules_payment.pay({
        money = { amount = fee, canBeNegative = false }
      }, {
        label = "Premium Document Fee",
        tags = { "gameplay", "carTheft", "documentation" }
      })
    else
      return false, "Payment system error"
    end

    -- Instant documentation
    if main.finalizeDocumentation then
      -- First set pending then immediately finalize
      main.startDocumentProcessing(inventoryId, tierName, 0)
      main.finalizeDocumentation(inventoryId)

      log("I", "Premium documents acquired instantly")
      if ui_message then
        ui_message("Premium documents acquired! Vehicle is now legal.", 5, "success")
      end

      return true, "Documents acquired"
    else
      return false, "System error"
    end
  end

  return false, "Invalid tier"
end

---------------------------------------------------------------------------
-- Document Status
---------------------------------------------------------------------------

-- Check if documents are ready for collection
function M.checkDocumentStatus(inventoryId)
  local main = getCarTheftMain()
  if not main or not main.getDocumentStatus then
    return nil
  end

  return main.getDocumentStatus(inventoryId)
end

-- Collect ready documents (finalize)
function M.collectDocuments(inventoryId)
  log("I", "Collecting documents for vehicle: " .. tostring(inventoryId))

  local main = getCarTheftMain()
  if not main then
    return false, "System error"
  end

  local status = main.getDocumentStatus and main.getDocumentStatus(inventoryId)
  if not status then
    return false, "No pending documents"
  end

  if not status.ready then
    local hours = math.ceil(status.remainingHours or 0)
    return false, "Documents not ready yet (" .. hours .. " game hour(s) remaining)"
  end

  -- Finalize documentation
  if main.finalizeDocumentation then
    local success = main.finalizeDocumentation(inventoryId)
    if success then
      log("I", "Documents collected successfully")
      if ui_message then
        ui_message("Documents acquired! Vehicle is now legal.", 5, "success")
      end
      return true, "Documents collected"
    end
  end

  return false, "Failed to finalize documents"
end

---------------------------------------------------------------------------
-- UI Helpers
---------------------------------------------------------------------------

-- Get all undocumented vehicles with their status
function M.getVehiclesForUI()
  -- Safety check: ensure career is active
  if not career_career or not career_career.isActive() then
    return {}
  end

  local main = getCarTheftMain()
  if not main or not main.getStolenVehicles then
    return {}
  end

  local success, vehicles = pcall(function() return main.getStolenVehicles() end)
  if not success or not vehicles then
    return {}
  end

  local result = {}

  for _, veh in ipairs(vehicles) do
    if veh and not veh.hasDocuments then
      local status = nil
      if main.getDocumentStatus then
        local statusOk, statusResult = pcall(function() return main.getDocumentStatus(veh.inventoryId) end)
        if statusOk then status = statusResult end
      end

      local fees = {}
      local feesOk, feesResult = pcall(function() return M.getAllFees(veh.inventoryId) end)
      if feesOk then fees = feesResult or {} end

      local entry = {
        inventoryId = veh.inventoryId,
        name = veh.niceName or veh.model or "Unknown",
        value = veh.value or 0,
        fees = fees,
        pending = status ~= nil,
        ready = status and status.ready or false,
        tier = status and status.tier or nil,
        remainingHours = status and status.remainingHours or nil
      }
      table.insert(result, entry)
    end
  end

  return result
end

---------------------------------------------------------------------------
-- Legacy API (backwards compatibility)
---------------------------------------------------------------------------

-- Old flat-fee API - now orders budget tier
function M.purchaseDocuments(inventoryId)
  return M.orderDocuments(inventoryId, "budget")
end

function M.needsDocumentation(inventoryId)
  local main = getCarTheftMain()
  if not main or not main.isVehicleUndocumented then
    return false
  end
  return main.isVehicleUndocumented(inventoryId)
end

---------------------------------------------------------------------------
-- Module Lifecycle
---------------------------------------------------------------------------

function M.onExtensionLoaded()
  log("I", "Documentation service loaded (tiered system)")
end

return M
