-- documentation.lua
-- LegitDocs service - Purchase fake documentation for stolen vehicles
-- Features: tiered pricing, processing time, quality-based detection risk

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
      description = "Quick and cheap, but risky",
      costMult = budget.costMult or 0.15,
      hours = budget.hours or 1,
      detectChance = budget.detectChance or 0.40
    },
    standard = {
      name = "Standard",
      description = "Balanced quality and price",
      costMult = standard.costMult or 0.20,
      hours = standard.hours or 4,
      detectChance = standard.detectChance or 0.15
    },
    premium = {
      name = "Premium",
      description = "Top quality, nearly undetectable",
      costMult = premium.costMult or 0.30,
      hours = premium.hours or 12,
      detectChance = premium.detectChance or 0.02
    }
  }
end

---------------------------------------------------------------------------
-- Fee Calculation
---------------------------------------------------------------------------

-- Calculate documentation fee for a vehicle and tier
function M.getDocumentFee(inventoryId, tierName)
  local tierCfg = getTierConfig(tierName)
  if not tierCfg then
    return nil
  end

  local main = getCarTheftMain()
  if not main or not main.getStolenVehicles then return nil end

  -- Get vehicle value (wrapped in pcall for safety)
  local success, vehicles = pcall(function() return main.getStolenVehicles() end)
  if not success or not vehicles then return nil end

  for _, veh in ipairs(vehicles) do
    if veh and tostring(veh.inventoryId) == tostring(inventoryId) then
      local value = veh.value or 10000
      local costMult = tierCfg.costMult or 0.20
      return math.floor(value * costMult)
    end
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

-- Order documents for a vehicle (pay upfront, wait for processing)
function M.orderDocuments(inventoryId, tierName)
  log("I", "Ordering " .. tierName .. " documents for vehicle: " .. tostring(inventoryId))

  local tierCfg = getTierConfig(tierName)
  if not tierCfg then
    return false, "Invalid tier"
  end

  -- Check if player has enough money
  if not career_modules_playerAttributes then
    log("E", "Career system not available")
    return false, "Career system not available"
  end

  local fee = M.getDocumentFee(inventoryId, tierName)
  if not fee then
    return false, "Could not calculate fee"
  end

  local playerMoney = career_modules_playerAttributes.getAttributeValue("money") or 0
  if playerMoney < fee then
    log("W", "Player cannot afford documents: " .. playerMoney .. " < " .. fee)
    return false, "Not enough money ($" .. fee .. " required)"
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

  -- Deduct money
  if career_modules_payment and career_modules_payment.pay then
    career_modules_payment.pay({
      money = { amount = fee, canBeNegative = false }
    }, {
      label = "Document Processing Fee (" .. tierName .. ")",
      tags = { "gameplay", "carTheft", "documentation" }
    })
  else
    log("E", "Payment system not available")
    return false, "Payment system error"
  end

  -- Calculate ready time (hours to seconds)
  local processingSeconds = tierCfg.hours * 3600
  local readyTime = os.time() + processingSeconds

  -- Mark documents as pending
  if main.startDocumentProcessing then
    local success = main.startDocumentProcessing(inventoryId, tierName, readyTime)
    if not success then
      log("E", "Failed to start document processing")
      return false, "Failed to process order"
    end
  else
    log("E", "startDocumentProcessing not available")
    return false, "System error"
  end

  log("I", "Documents ordered. Ready in " .. tierCfg.hours .. " hours")

  if ui_message then
    ui_message("Documents ordered! Ready in " .. tierCfg.hours .. " hour(s).", 5, "info")
  end

  return true, "Documents ordered successfully"
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
    local remaining = status.readyTime - os.time()
    local hours = math.ceil(remaining / 3600)
    return false, "Documents not ready yet (" .. hours .. " hour(s) remaining)"
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
        readyTime = status and status.readyTime or nil,
        remainingSeconds = status and status.readyTime and (status.readyTime - os.time()) or nil
      }
      table.insert(result, entry)
    end
  end

  return result
end

---------------------------------------------------------------------------
-- Legacy API (backwards compatibility)
---------------------------------------------------------------------------

-- Old flat-fee API - now orders standard tier
function M.purchaseDocuments(inventoryId)
  return M.orderDocuments(inventoryId, "standard")
end

function M.getDocumentFee()
  -- Return average fee for legacy code
  return 5000
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
