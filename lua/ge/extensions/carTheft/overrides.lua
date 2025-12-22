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

---------------------------------------------------------------------------
-- Helper: Check if vehicle is undocumented stolen
---------------------------------------------------------------------------

local function isUndocumentedStolen(invVehId)
  if not career_modules_inventory then return false end
  local vehicles = career_modules_inventory.getVehicles()
  if not vehicles then return false end
  local veh = vehicles[invVehId]
  if veh and veh.isStolen and not veh.hasDocuments then
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
-- Apply Overrides
---------------------------------------------------------------------------

local function applyOverrides()
  if overridesApplied then return end

  -- Override insurance function
  if career_modules_insurance and career_modules_insurance.changeInvVehInsurance then
    original_changeInvVehInsurance = career_modules_insurance.changeInvVehInsurance
    career_modules_insurance.changeInvVehInsurance = wrapped_changeInvVehInsurance
    log("I", "Wrapped insurance.changeInvVehInsurance")
  end

  -- Override marketplace function
  if career_modules_marketplace and career_modules_marketplace.listVehiclesForSale then
    original_listVehiclesForSale = career_modules_marketplace.listVehiclesForSale
    career_modules_marketplace.listVehiclesForSale = wrapped_listVehiclesForSale
    log("I", "Wrapped marketplace.listVehiclesForSale")
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
    if career_modules_insurance and career_modules_marketplace then
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
