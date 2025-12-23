-- overrides.lua
-- Hooks into RLS Career functions to add stolen vehicle restrictions
-- This is standalone and doesn't modify the RLS mod files

local M = {}

-- Logger module
local logger = require("carTheft/logger")
local LOG_TAG = "carTheft_overrides"
local overridesApplied = false

local function log(level, msg)
  logger.log(LOG_TAG, level, msg)
end

---------------------------------------------------------------------------
-- Original function references (stored before wrapping)
---------------------------------------------------------------------------

local original_changeInvVehInsurance = nil
local original_listVehiclesForSale = nil
local original_getInvVehRepairTime = nil
local original_getVehInsuranceInfo = nil

---------------------------------------------------------------------------
-- Helper: Check if vehicle is undocumented stolen
---------------------------------------------------------------------------

-- RLS Career uses "overrides/" folder prefix, so modules are overrides_career_modules_*
local function getInsuranceModule()
  return overrides_career_modules_insurance_insurance or career_modules_insurance_insurance
end

local function getInventoryModule()
  return overrides_career_modules_inventory or career_modules_inventory
end

local function getMarketplaceModule()
  return overrides_career_modules_marketplace or career_modules_marketplace
end

local function getInsuranceMainModule()
  return overrides_career_modules_insurance or career_modules_insurance
end

local function isUndocumentedStolen(invVehId)
  local inventory = getInventoryModule()
  if not inventory then return false end
  local vehicles = inventory.getVehicles()
  if not vehicles then return false end
  local veh = vehicles[invVehId]
  if veh and veh.isStolen and not veh.hasDocuments then
    return true
  end
  return false
end

-- Check if a vehicle has any insurance (for repair time check)
local function vehicleHasInsurance(invVehId)
  local insurance = getInsuranceModule()
  if not insurance then return false end
  if not insurance.getVehInsuranceInfo then return false end

  local success, info = pcall(function()
    return insurance.getVehInsuranceInfo(invVehId)
  end)

  if success and info and info.isInsured then
    return true
  end
  return false
end

---------------------------------------------------------------------------
-- Insurance Override
---------------------------------------------------------------------------

local function wrapped_changeInvVehInsurance(invVehId, newInsuranceId, forFree)
  -- Block undocumented stolen vehicles from getting insurance
  if newInsuranceId and newInsuranceId > 0 then
    if isUndocumentedStolen(invVehId) then
      guihooks.trigger("toastrMsg", {
        type = "error",
        title = "Insurance Denied",
        msg = "Cannot insure a vehicle without proper documentation"
      })
      return
    end
  end

  -- Call original function
  if original_changeInvVehInsurance then
    return original_changeInvVehInsurance(invVehId, newInsuranceId, forFree)
  end
end

---------------------------------------------------------------------------
-- Marketplace Override
---------------------------------------------------------------------------

local function wrapped_listVehiclesForSale(vehicles)
  -- Filter out undocumented stolen vehicles
  local filteredVehicles = {}
  local blocked = false

  for _, entry in ipairs(vehicles) do
    if isUndocumentedStolen(entry.inventoryId) then
      blocked = true
    else
      table.insert(filteredVehicles, entry)
    end
  end

  if blocked then
    guihooks.trigger("toastrMsg", {
      type = "error",
      title = "Cannot List Vehicle",
      msg = "Some vehicles lack proper documentation. Visit LegitDocs on BackAlley to acquire documents first."
    })
  end

  -- Call original with filtered list
  if original_listVehiclesForSale and #filteredVehicles > 0 then
    return original_listVehiclesForSale(filteredVehicles)
  end
end

---------------------------------------------------------------------------
-- Insurance Info Override (fixes crash on uninsured vehicles)
---------------------------------------------------------------------------

local function wrapped_getVehInsuranceInfo(invVehId)
  -- Try original function with pcall to catch nil comparison errors
  if original_getVehInsuranceInfo then
    local success, result = pcall(function()
      return original_getVehInsuranceInfo(invVehId)
    end)
    if success then
      return result
    else
      -- Original function crashed - return safe default for uninsured vehicle
      log("W", "getVehInsuranceInfo failed for vehicle " .. tostring(invVehId) .. ", returning uninsured default")
      return {
        isInsured = false,
        currentPolicy = nil,
        policies = {}
      }
    end
  end

  -- No original function, return uninsured default
  return {
    isInsured = false,
    currentPolicy = nil,
    policies = {}
  }
end

---------------------------------------------------------------------------
-- Insurance Repair Time Override (fixes crash on uninsured vehicles)
---------------------------------------------------------------------------

local function wrapped_getInvVehRepairTime(invVehId)
  -- Check if the vehicle has insurance before calling original
  -- If no insurance, return 0 to avoid nil comparison crash
  if not vehicleHasInsurance(invVehId) then
    return 0
  end

  -- Call original function for insured vehicles
  if original_getInvVehRepairTime then
    local success, result = pcall(function()
      return original_getInvVehRepairTime(invVehId)
    end)
    if success then
      return result
    else
      log("W", "getInvVehRepairTime failed for vehicle " .. tostring(invVehId) .. ", returning 0")
      return 0
    end
  end

  return 0
end

---------------------------------------------------------------------------
-- Apply Overrides
---------------------------------------------------------------------------

local function applyOverrides()
  if overridesApplied then return end

  local insuranceMain = getInsuranceMainModule()
  local marketplace = getMarketplaceModule()
  local insurance = getInsuranceModule()

  -- Override insurance function
  if insuranceMain and insuranceMain.changeInvVehInsurance then
    original_changeInvVehInsurance = insuranceMain.changeInvVehInsurance
    insuranceMain.changeInvVehInsurance = wrapped_changeInvVehInsurance
    log("I", "Wrapped insurance.changeInvVehInsurance")
  end

  -- Override marketplace function
  if marketplace and marketplace.listVehiclesForSale then
    original_listVehiclesForSale = marketplace.listVehiclesForSale
    marketplace.listVehiclesForSale = wrapped_listVehiclesForSale
    log("I", "Wrapped marketplace.listVehiclesForSale")
  end

  -- Override insurance info function (fixes crash on uninsured stolen vehicles)
  if insurance and insurance.getVehInsuranceInfo then
    original_getVehInsuranceInfo = insurance.getVehInsuranceInfo
    insurance.getVehInsuranceInfo = wrapped_getVehInsuranceInfo
    log("I", "Wrapped insurance.getVehInsuranceInfo")
  end

  -- Override insurance repair time function (fixes crash on uninsured stolen vehicles)
  if insurance and insurance.getInvVehRepairTime then
    original_getInvVehRepairTime = insurance.getInvVehRepairTime
    insurance.getInvVehRepairTime = wrapped_getInvVehRepairTime
    log("I", "Wrapped insurance.getInvVehRepairTime")
  end

  overridesApplied = true
  log("I", "All overrides applied successfully")
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

local function onExtensionLoaded()
  log("I", "Overrides extension loaded - waiting for career modules")
end

-- Try to apply overrides when career modules are activated
local function onCareerModulesActivated()
  log("I", "Career modules activated - applying overrides")
  applyOverrides()
end

-- Also try on extension loaded in case career is already active
local function onUpdate(dtReal, dtSim, dtRaw)
  if not overridesApplied then
    local insurance = getInsuranceModule()
    local marketplace = getMarketplaceModule()
    local insuranceMain = getInsuranceMainModule()
    if insurance and marketplace and insuranceMain then
      applyOverrides()
    end
  end
end

-- Expose for manual triggering if needed
M.applyOverrides = applyOverrides

M.onExtensionLoaded = onExtensionLoaded
M.onCareerModulesActivated = onCareerModulesActivated
M.onUpdate = onUpdate

return M
