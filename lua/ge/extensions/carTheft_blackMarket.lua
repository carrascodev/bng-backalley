-- Car Theft Career - Black Market Extension Wrapper
-- This file wraps the black market module for BeamNG's extension system

local M = {}

-- Load the actual implementation
local blackMarket = nil

local function ensureLoaded()
  if not blackMarket then
    local success, mod = pcall(require, "carTheft/blackMarket")
    if success then
      blackMarket = mod
    else
      print("[carTheft_blackMarket] ERROR: Failed to load blackMarket module: " .. tostring(mod))
    end
  end
  return blackMarket
end

-- Forward all function calls to the underlying module
function M.generateListings(count)
  local bm = ensureLoaded()
  if bm and bm.generateListings then return bm.generateListings(count) end
end

function M.getListingsForUI()
  local bm = ensureLoaded()
  if bm and bm.getListingsForUI then return bm.getListingsForUI() end
  return {}
end

function M.getListing(listingId)
  local bm = ensureLoaded()
  if bm and bm.getListing then return bm.getListing(listingId) end
end

function M.addToCart(listingId)
  local bm = ensureLoaded()
  if bm and bm.addToCart then return bm.addToCart(listingId) end
  return false, "Module not loaded"
end

function M.removeFromCart(listingId)
  local bm = ensureLoaded()
  if bm and bm.removeFromCart then return bm.removeFromCart(listingId) end
  return false, "Module not loaded"
end

function M.clearCart()
  local bm = ensureLoaded()
  if bm and bm.clearCart then return bm.clearCart() end
  return false
end

function M.getCartForUI()
  local bm = ensureLoaded()
  if bm and bm.getCartForUI then return bm.getCartForUI() end
  return {items = {}, total = 0}
end

function M.checkout()
  local bm = ensureLoaded()
  if bm and bm.checkout then return bm.checkout() end
  return {success = false, message = "Module not loaded"}
end

function M.getPlayerListingsForUI()
  local bm = ensureLoaded()
  if bm and bm.getPlayerListingsForUI then return bm.getPlayerListingsForUI() end
  return {}
end

function M.listVehicleForSale(inventoryId, askingPrice)
  local bm = ensureLoaded()
  if bm and bm.listVehicleForSale then return bm.listVehicleForSale(inventoryId, askingPrice) end
  return false, "Not implemented"
end

function M.unlistVehicle(inventoryId)
  local bm = ensureLoaded()
  if bm and bm.unlistVehicle then return bm.unlistVehicle(inventoryId) end
  return false, "Not implemented"
end

function M.generateBuyerOffers()
  local bm = ensureLoaded()
  if bm and bm.generateBuyerOffers then return bm.generateBuyerOffers() end
end

function M.acceptPlayerOffer(inventoryId, offerIndex)
  local bm = ensureLoaded()
  if bm and bm.acceptPlayerOffer then return bm.acceptPlayerOffer(inventoryId, offerIndex) end
  return false, "Not implemented"
end

function M.getSaveData()
  local bm = ensureLoaded()
  if bm and bm.getSaveData then return bm.getSaveData() end
  return {}
end

function M.loadSaveData(data)
  local bm = ensureLoaded()
  if bm and bm.loadSaveData then return bm.loadSaveData(data) end
end

-- Extension lifecycle
function M.onExtensionLoaded()
  print("[carTheft_blackMarket] Extension loaded")
  ensureLoaded()
end

return M
