-- Car Theft Career - Documentation Service Extension Wrapper
-- This file wraps the documentation module for BeamNG's extension system

local M = {}

-- Load the actual implementation
local documentation = nil

local function ensureLoaded()
  if not documentation then
    local success, mod = pcall(require, "carTheft/documentation")
    if success then
      documentation = mod
    else
      print("[carTheft_documentation] ERROR: Failed to load documentation module: " .. tostring(mod))
    end
  end
  return documentation
end

---------------------------------------------------------------------------
-- Tiered Documentation System (New API)
---------------------------------------------------------------------------

-- Get tier options for UI display
function M.getTierInfo()
  local doc = ensureLoaded()
  if doc and doc.getTierInfo then return doc.getTierInfo() end
  return {}
end

-- Get all fees for a vehicle (budget/standard/premium)
function M.getAllFees(inventoryId)
  local doc = ensureLoaded()
  if doc and doc.getAllFees then return doc.getAllFees(inventoryId) end
  return {}
end

-- Order documents for a vehicle with specified tier
function M.orderDocuments(inventoryId, tierName)
  local doc = ensureLoaded()
  if doc and doc.orderDocuments then return doc.orderDocuments(inventoryId, tierName) end
  return false, "Module not loaded"
end

-- Check document processing status
function M.checkDocumentStatus(inventoryId)
  local doc = ensureLoaded()
  if doc and doc.checkDocumentStatus then return doc.checkDocumentStatus(inventoryId) end
  return nil
end

-- Collect ready documents
function M.collectDocuments(inventoryId)
  local doc = ensureLoaded()
  if doc and doc.collectDocuments then return doc.collectDocuments(inventoryId) end
  return false, "Module not loaded"
end

-- Get all undocumented vehicles with status for UI
function M.getVehiclesForUI()
  local doc = ensureLoaded()
  if doc and doc.getVehiclesForUI then return doc.getVehiclesForUI() end
  return {}
end

---------------------------------------------------------------------------
-- Legacy API (backwards compatibility)
---------------------------------------------------------------------------

function M.getDocumentFee()
  local doc = ensureLoaded()
  if doc and doc.getDocumentFee then return doc.getDocumentFee() end
  return 5000  -- Default fee
end

function M.purchaseDocuments(inventoryId)
  local doc = ensureLoaded()
  if doc and doc.purchaseDocuments then return doc.purchaseDocuments(inventoryId) end
  return false, "Module not loaded"
end

function M.needsDocumentation(inventoryId)
  local doc = ensureLoaded()
  if doc and doc.needsDocumentation then return doc.needsDocumentation(inventoryId) end
  return false
end

-- Extension lifecycle
function M.onExtensionLoaded()
  print("[carTheft_documentation] Extension loaded")
  ensureLoaded()
end

return M
