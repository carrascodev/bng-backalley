-- blackMarket.lua
-- Underground car marketplace - Buy/sell vehicles with no documentation

local M = {}

-- Logger module
local logger = require("carTheft/logger")
local LOG_TAG = "carTheft_blackMarket"

local function log(level, msg)
  logger.log(LOG_TAG, level, msg)
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

local listings = {}           -- NPC vehicle listings for sale
local playerListings = {}     -- Player's vehicles listed for sale
local cart = {}               -- Shopping cart
local nextListingId = 1
local lastRefreshTime = 0
local REFRESH_INTERVAL = 3600 -- Refresh listings every hour
local MAX_LISTING_ID = 100000 -- Reset ID counter to prevent unbounded growth

-- Seller names for flavor
local SELLER_NAMES = {
  "Shadow Mike", "Dusty", "The Mechanic", "Big Tony", "Slim",
  "Chrome", "Wheels", "Ghost", "Rusty", "Speed Demon",
  "Midnight Joe", "Grease", "Turbo", "The Fixer", "Snake"
}

---------------------------------------------------------------------------
-- Helper Functions
---------------------------------------------------------------------------

local function getCarTheftMain()
  return extensions.carTheft_main or carTheft_main
end

local function getRandomSellerName()
  return SELLER_NAMES[math.random(1, #SELLER_NAMES)]
end

local function randomRange(min, max)
  return min + math.random() * (max - min)
end

local function roundToNearest(value, nearest)
  return math.floor(value / nearest + 0.5) * nearest
end

-- Format number with commas (Lua doesn't support %,)
local function formatMoney(amount)
  local formatted = tostring(math.floor(amount))
  local k
  while true do
    formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
    if k == 0 then break end
  end
  return formatted
end

---------------------------------------------------------------------------
-- Listing Generation
---------------------------------------------------------------------------

local function generateListing(vehicle, id)
  -- Random reputation (affects scam probability)
  local reputation = randomRange(0.2, 0.95)

  -- Price varies based on reputation
  -- Sketchy sellers have lower prices (too good to be true)
  -- Trusted sellers have fair prices
  local priceMultiplier
  if reputation < 0.4 then
    priceMultiplier = randomRange(0.4, 0.6)  -- Very cheap (probably scam)
  elseif reputation < 0.7 then
    priceMultiplier = randomRange(0.6, 0.8)  -- Good deal
  else
    priceMultiplier = randomRange(0.75, 0.95) -- Fair price
  end

  local price = roundToNearest(vehicle.value * priceMultiplier, 100)

  return {
    id = id,
    vehicleName = vehicle.name,
    model = vehicle.model,
    configKey = vehicle.configKey,
    baseValue = vehicle.value,
    price = price,
    reputation = reputation,
    sellerName = getRandomSellerName(),
    description = reputation < 0.4 and "Quick sale, no questions" or
                  reputation < 0.7 and "Good condition, papers lost" or
                  "Clean vehicle, reliable seller",
    listedTime = os.time(),
    expiresTime = os.time() + 86400 + math.random(0, 43200) -- 24-36 hours
  }
end

function M.generateListings(count)
  count = count or 8

  -- Use the same vehicle loading as job manager
  if not util_configListGenerator then
    log("E", "util_configListGenerator not available")
    return
  end

  local allVehicles = util_configListGenerator.getEligibleVehicles()
  if not allVehicles then
    log("E", "Failed to get vehicles")
    return
  end

  -- Build list of eligible vehicles
  local eligibleVehicles = {}
  for _, vehInfo in pairs(allVehicles) do
    if vehInfo.Value and vehInfo.Value > 1000 and vehInfo.Value < 500000 then
      table.insert(eligibleVehicles, {
        model = vehInfo.model_key,
        configKey = vehInfo.key,
        name = vehInfo.Name or vehInfo.model_key,
        value = vehInfo.Value
      })
    end
  end

  if #eligibleVehicles == 0 then
    log("E", "No eligible vehicles found")
    return
  end

  -- Generate random listings
  listings = {}
  for i = 1, count do
    local vehicle = eligibleVehicles[math.random(1, #eligibleVehicles)]
    local listing = generateListing(vehicle, nextListingId)
    listings[nextListingId] = listing
    nextListingId = nextListingId + 1
    -- Reset ID counter if it gets too high
    if nextListingId > MAX_LISTING_ID then
      nextListingId = 1
    end
  end

  lastRefreshTime = os.time()
  log("I", "Generated " .. count .. " black market listings")
end

-- Remove expired listings
local function cleanExpiredListings()
  local now = os.time()
  local expired = {}

  for id, listing in pairs(listings) do
    if listing.expiresTime < now then
      table.insert(expired, id)
    end
  end

  for _, id in ipairs(expired) do
    listings[id] = nil
    log("I", "Removed expired listing: " .. id)
  end

  return #expired
end

---------------------------------------------------------------------------
-- Listings API
---------------------------------------------------------------------------

function M.getListingsForUI()
  -- Clean expired and refresh if needed
  cleanExpiredListings()

  if not next(listings) or (os.time() - lastRefreshTime) > REFRESH_INTERVAL then
    M.generateListings(8)
  end

  local result = {}
  for _, listing in pairs(listings) do
    table.insert(result, {
      id = listing.id,
      vehicleName = listing.vehicleName,
      price = listing.price,
      reputation = listing.reputation,
      sellerName = listing.sellerName,
      description = listing.description,
      expiresIn = listing.expiresTime - os.time()
    })
  end

  -- Sort by price
  table.sort(result, function(a, b) return a.price < b.price end)

  return result
end

function M.getListing(listingId)
  return listings[listingId]
end

---------------------------------------------------------------------------
-- Cart API
---------------------------------------------------------------------------

function M.addToCart(listingId)
  local listing = listings[listingId]
  if not listing then
    return false, "Listing not found"
  end

  -- Check if already in cart
  for _, item in ipairs(cart) do
    if item.listingId == listingId then
      return false, "Already in cart"
    end
  end

  table.insert(cart, {
    listingId = listingId,
    vehicleName = listing.vehicleName,
    price = listing.price
  })

  log("I", "Added to cart: " .. listing.vehicleName)

  -- Show feedback
  guihooks.trigger("toastrMsg", {
    type = "info",
    title = "Added to Cart",
    msg = listing.vehicleName .. " - $" .. formatMoney(listing.price)
  })

  return true
end

function M.removeFromCart(listingId)
  for i, item in ipairs(cart) do
    if item.listingId == listingId then
      table.remove(cart, i)
      log("I", "Removed from cart: " .. item.vehicleName)
      return true
    end
  end
  return false, "Item not in cart"
end

function M.clearCart()
  cart = {}
  return true
end

function M.getCartForUI()
  local result = {}
  local total = 0

  for _, item in ipairs(cart) do
    table.insert(result, {
      listingId = item.listingId,
      vehicleName = item.vehicleName,
      price = item.price
    })
    total = total + item.price
  end

  return {
    items = result,
    total = total
  }
end

---------------------------------------------------------------------------
-- Purchase / Checkout
---------------------------------------------------------------------------

local function determineOutcome(listing)
  local roll = math.random()

  -- Reputation affects outcome probability
  if listing.reputation < 0.3 then
    -- Very sketchy seller - high scam chance
    if roll < 0.40 then return "scam"
    elseif roll < 0.70 then return "clunker"
    else return "legit" end
  elseif listing.reputation < 0.6 then
    -- Somewhat sketchy
    if roll < 0.20 then return "scam"
    elseif roll < 0.45 then return "clunker"
    else return "legit" end
  else
    -- Trusted seller
    if roll < 0.05 then return "scam"
    elseif roll < 0.20 then return "clunker"
    else return "legit" end
  end
end

-- Mileage settings for black market vehicles (in miles)
local BLACK_MARKET_MILEAGE = {
  legit = { min = 10000, max = 80000 },      -- 10k-80k miles for legit cars
  clunker = { min = 100000, max = 200000 }   -- 100k-200k miles for clunkers
}
local METERS_PER_MILE = 1609.344

local function addVehicleToInventory(model, configKey, isClunker, vehicleName)
  -- Add vehicle directly to player's inventory (like buying from dealership)

  if not career_modules_inventory then
    log("E", "Inventory system not available")
    return nil
  end

  local actualModel = model
  local actualConfig = configKey

  if isClunker then
    -- Clunker = cheap random car
    actualModel = "covet"
    actualConfig = "base"
  end

  -- Find a garage to put it in
  local garageId = nil
  if career_modules_garageManager and career_modules_garageManager.getPurchasedGarages then
    local garages = career_modules_garageManager.getPurchasedGarages()
    if garages and #garages > 0 then
      garageId = garages[1]
    end
  end

  if not garageId then
    log("E", "No garage available to store vehicle")
    guihooks.trigger("toastrMsg", {
      type = "error",
      title = "No Garage!",
      msg = "You need a garage to store this vehicle"
    })
    return nil
  end

  -- Spawn the vehicle
  local spawnOptions = {
    config = actualConfig,
    autoEnterVehicle = false
  }

  local vehObj = core_vehicles.spawnNewVehicle(actualModel, spawnOptions)
  if not vehObj then
    log("E", "Failed to spawn vehicle for inventory")
    return nil
  end

  local vehId = vehObj:getID()
  log("I", "Spawned vehicle for black market purchase: " .. actualModel .. " (vehId: " .. vehId .. ")")

  -- Set realistic mileage for used black market car
  local mileageRange = isClunker and BLACK_MARKET_MILEAGE.clunker or BLACK_MARKET_MILEAGE.legit
  local milesMiles = mileageRange.min + math.random() * (mileageRange.max - mileageRange.min)
  local mileageMeters = math.floor(milesMiles * METERS_PER_MILE)

  -- Set part integrity (clunkers are more worn)
  local integrityValue = isClunker and randomRange(0.4, 0.6) or randomRange(0.7, 0.95)

  -- Initialize part conditions with mileage and wear
  vehObj:queueLuaCommand(string.format("partCondition.initConditions(nil, %d, nil, %f)", mileageMeters, integrityValue))
  log("I", string.format("Set vehicle mileage: %d miles, integrity: %.2f", math.floor(milesMiles), integrityValue))

  -- Add to inventory - the vehicle needs to stay spawned for this to work properly
  local inventoryId = career_modules_inventory.addVehicle(vehId, nil, {owned = true})

  if inventoryId then
    -- Mark as stolen (came from black market)
    local vehicles = career_modules_inventory.getVehicles()
    if vehicles and vehicles[inventoryId] then
      vehicles[inventoryId].isStolen = true
      vehicles[inventoryId].hasDocuments = false
      vehicles[inventoryId].stolenDate = os.time()
    end

    -- Initialize heat for the stolen vehicle
    local main = extensions.carTheft_main or carTheft_main
    if main and main.initVehicleHeat then
      main.initVehicleHeat(inventoryId)
    end

    log("I", "Added vehicle to inventory: " .. actualModel .. " (inventoryId: " .. tostring(inventoryId) .. ")")

    -- Move to garage - this should handle removing it from the world
    if career_modules_inventory.moveVehicleToGarage then
      career_modules_inventory.moveVehicleToGarage(inventoryId, garageId)
      log("I", "Moved vehicle to garage: " .. garageId)
    end
  else
    log("E", "Failed to add vehicle to inventory")
    -- Clean up the spawned vehicle
    vehObj:delete()
  end

  return inventoryId
end

function M.checkout()
  if #cart == 0 then
    return { success = false, message = "Cart is empty" }
  end

  -- Calculate total
  local total = 0
  for _, item in ipairs(cart) do
    total = total + item.price
  end

  -- Check player has enough money
  if not career_modules_playerAttributes then
    return { success = false, message = "Career system not available" }
  end

  local playerMoney = career_modules_playerAttributes.getAttributeValue("money") or 0
  if playerMoney < total then
    return { success = false, message = "Not enough money" }
  end

  -- Process each item
  local results = {}
  local actualTotal = 0

  for _, item in ipairs(cart) do
    local listing = listings[item.listingId]
    if listing then
      local outcome = determineOutcome(listing)
      actualTotal = actualTotal + item.price

      local result = {
        vehicleName = item.vehicleName,
        outcome = outcome,
        price = item.price
      }

      if outcome == "scam" then
        result.message = "The seller vanished with your money!"
        log("I", "SCAM: Player lost " .. item.price .. " on " .. item.vehicleName)
        -- Show scam feedback
        guihooks.trigger("toastrMsg", {
          type = "error",
          title = "SCAMMED!",
          msg = "The seller disappeared with your $" .. formatMoney(item.price) .. "!"
        })
      elseif outcome == "clunker" then
        result.message = "You got a junker instead of what you paid for!"
        result.actualVehicle = "Old Covet"
        log("I", "CLUNKER: Player got cheap car instead of " .. item.vehicleName)
        -- Add clunker to inventory
        addVehicleToInventory(listing.model, listing.configKey, true, item.vehicleName)
        -- Show clunker feedback
        guihooks.trigger("toastrMsg", {
          type = "warning",
          title = "Bait and Switch!",
          msg = "You got a beat-up Covet instead of " .. item.vehicleName
        })
      else
        result.message = "Vehicle delivered successfully!"
        log("I", "LEGIT: Player received " .. item.vehicleName)
        -- Add legitimate vehicle to inventory
        addVehicleToInventory(listing.model, listing.configKey, false, item.vehicleName)
        -- Show success feedback
        guihooks.trigger("toastrMsg", {
          type = "success",
          title = "Vehicle Delivered!",
          msg = item.vehicleName .. " is waiting in your garage"
        })
      end

      -- Remove from listings
      listings[item.listingId] = nil

      table.insert(results, result)
    end
  end

  -- Deduct money
  if career_modules_payment and career_modules_payment.pay then
    career_modules_payment.pay({
      money = {amount = actualTotal, canBeNegative = true}
    }, {
      label = "Black Market Purchase",
      tags = {"gameplay", "carTheft", "blackmarket"}
    })
  end

  -- Clear cart
  cart = {}

  log("I", "Checkout complete: " .. #results .. " items, total $" .. actualTotal)

  return {
    success = true,
    results = results,
    totalPaid = actualTotal
  }
end

---------------------------------------------------------------------------
-- Player Selling
---------------------------------------------------------------------------

-- Get player's stolen vehicles available for black market sale
function M.getPlayerListingsForUI()
  local main = getCarTheftMain()
  if not main or not main.getStolenVehicles then
    log("E", "carTheft_main not available")
    return {}
  end

  -- Generate buyer offers each time the UI is viewed
  M.generateBuyerOffers()

  local stolenVehicles = main.getStolenVehicles()
  local result = {}

  for _, veh in ipairs(stolenVehicles) do
    -- Check if already listed
    local alreadyListed = false
    for _, listing in pairs(playerListings) do
      if listing.inventoryId == veh.inventoryId then
        alreadyListed = true
        -- Include the active listing
        table.insert(result, {
          inventoryId = veh.inventoryId,
          vehicleName = veh.niceName,
          value = veh.value,
          askingPrice = listing.askingPrice,
          hasDocuments = veh.hasDocuments,
          offers = listing.offers or {},
          listedTime = listing.listedTime,
          isListed = true
        })
        break
      end
    end

    if not alreadyListed then
      -- Vehicle available to list
      table.insert(result, {
        inventoryId = veh.inventoryId,
        vehicleName = veh.niceName,
        value = veh.value,
        hasDocuments = veh.hasDocuments,
        offers = {},
        isListed = false
      })
    end
  end

  return result
end

function M.listVehicleForSale(inventoryId, askingPrice)
  -- Validate vehicle exists and is stolen
  local main = getCarTheftMain()
  if not main then
    return false, "System not available"
  end

  if not career_modules_inventory then
    return false, "Inventory not available"
  end

  local vehicles = career_modules_inventory.getVehicles()
  if not vehicles or not vehicles[inventoryId] then
    return false, "Vehicle not found"
  end

  local veh = vehicles[inventoryId]
  if not veh.isStolen then
    return false, "Only stolen vehicles can be sold here"
  end

  -- Check if already listed
  for id, listing in pairs(playerListings) do
    if listing.inventoryId == inventoryId then
      return false, "Vehicle already listed"
    end
  end

  -- Create listing
  local listingId = nextListingId
  nextListingId = nextListingId + 1

  -- Use actual vehicle value (accounts for stripped parts, mileage, damage)
  -- Try multiple sources in order of preference:
  -- 1. valueCalculator (most accurate but may fail for stolen vehicles without partConditions)
  -- 2. veh.value (maintained by career system)
  -- 3. configBaseValue (original base price)
  -- 4. askingPrice (fallback)
  local actualValue = nil

  -- Try valueCalculator first (wrapped in pcall to catch partCondition errors)
  if career_modules_valueCalculator and career_modules_valueCalculator.getInventoryVehicleValue then
    local success, calcValue = pcall(function()
      return career_modules_valueCalculator.getInventoryVehicleValue(inventoryId)
    end)
    if success and calcValue then
      actualValue = calcValue
    end
  end

  -- Fallback to inventory value or configBaseValue
  if not actualValue then
    actualValue = veh.value or veh.configBaseValue or askingPrice
  end

  playerListings[listingId] = {
    id = listingId,
    inventoryId = inventoryId,
    vehicleName = veh.niceName or "Unknown Vehicle",
    value = actualValue,
    askingPrice = askingPrice,
    hasDocuments = veh.hasDocuments or false,
    offers = {},
    listedTime = os.time()
  }

  log("I", "Listed stolen vehicle for sale: " .. (veh.niceName or "Unknown") .. " for $" .. askingPrice)

  -- Show feedback
  guihooks.trigger("toastrMsg", {
    type = "info",
    title = "Vehicle Listed",
    msg = (veh.niceName or "Vehicle") .. " listed for $" .. formatMoney(askingPrice)
  })

  return true
end

function M.unlistVehicle(inventoryId)
  for id, listing in pairs(playerListings) do
    if listing.inventoryId == inventoryId then
      local vehicleName = listing.vehicleName
      playerListings[id] = nil
      log("I", "Unlisted vehicle: " .. vehicleName)

      -- Show feedback
      guihooks.trigger("toastrMsg", {
        type = "info",
        title = "Listing Removed",
        msg = vehicleName .. " is no longer for sale"
      })

      return true
    end
  end
  return false, "Listing not found"
end

-- Clean up expired offers from all player listings
local function cleanExpiredOffers()
  local now = os.time()
  local totalRemoved = 0

  for listingId, listing in pairs(playerListings) do
    if listing.offers then
      local validOffers = {}
      for _, offer in ipairs(listing.offers) do
        if offer.expiresTime and offer.expiresTime > now then
          table.insert(validOffers, offer)
        else
          totalRemoved = totalRemoved + 1
        end
      end
      listing.offers = validOffers
    end
  end

  if totalRemoved > 0 then
    log("I", "Cleaned up " .. totalRemoved .. " expired offers")
  end
end

-- Clean up player listings for vehicles that no longer exist
local function cleanOrphanedListings()
  if not career_modules_inventory then return end

  local vehicles = career_modules_inventory.getVehicles()
  if not vehicles then return end

  local toRemove = {}
  for listingId, listing in pairs(playerListings) do
    if not vehicles[listing.inventoryId] then
      table.insert(toRemove, listingId)
    end
  end

  for _, listingId in ipairs(toRemove) do
    log("I", "Removed orphaned listing: " .. (playerListings[listingId].vehicleName or "unknown"))
    playerListings[listingId] = nil
  end
end

-- Generate NPC buyer offers for player listings
function M.generateBuyerOffers()
  local now = os.time()

  -- Clean up expired offers first
  cleanExpiredOffers()

  -- Clean up listings for vehicles that no longer exist
  cleanOrphanedListings()

  for listingId, listing in pairs(playerListings) do
    -- Generate offers after a short delay (10 seconds minimum)
    local timeSinceListed = now - listing.listedTime
    if timeSinceListed > 10 and #listing.offers < 3 then
      -- 50% chance per check to get an offer (each time you view listings)
      -- First offer comes faster (70% chance if no offers yet)
      local chance = #listing.offers == 0 and 0.70 or 0.50
      if math.random() < chance then
        -- Offer based on value and documents
        local baseOffer = listing.value
        local docMultiplier = listing.hasDocuments and 1.0 or 0.6  -- 40% less without docs

        -- Random buyer offers 50-90% of value
        local offerPercent = randomRange(0.50, 0.90)
        local offerAmount = roundToNearest(baseOffer * docMultiplier * offerPercent, 50)

        local offer = {
          buyerName = getRandomSellerName(),  -- Reuse seller names as buyer names
          amount = offerAmount,
          timestamp = now,
          expiresTime = now + 3600 + math.random(0, 3600)  -- 1-2 hours
        }

        table.insert(listing.offers, offer)
        log("I", "New offer for " .. listing.vehicleName .. ": $" .. offerAmount .. " from " .. offer.buyerName)

        -- Show feedback for new offer
        guihooks.trigger("toastrMsg", {
          type = "success",
          title = "New Offer!",
          msg = offer.buyerName .. " offers $" .. formatMoney(offerAmount) .. " for " .. listing.vehicleName
        })
      end
    end
  end
end

-- Accept an offer on a player listing
function M.acceptPlayerOffer(inventoryId, offerIndex)
  for listingId, listing in pairs(playerListings) do
    if listing.inventoryId == inventoryId then
      local offer = listing.offers[offerIndex]
      if not offer then
        return false, "Offer not found"
      end

      -- Check if offer expired
      if offer.expiresTime < os.time() then
        return false, "Offer has expired"
      end

      -- Give player money
      if career_modules_payment and career_modules_payment.pay then
        career_modules_payment.pay({
          money = {amount = -offer.amount, canBeNegative = false}  -- Negative = receive money
        }, {
          label = "Black Market Vehicle Sale",
          tags = {"gameplay", "carTheft", "blackmarket", "sale"}
        })
      end

      -- Remove vehicle from inventory
      if career_modules_inventory and career_modules_inventory.removeVehicle then
        career_modules_inventory.removeVehicle(inventoryId)
      end

      log("I", "Sold " .. listing.vehicleName .. " for $" .. offer.amount .. " to " .. offer.buyerName)

      -- Show feedback
      guihooks.trigger("toastrMsg", {
        type = "success",
        title = "Vehicle Sold!",
        msg = listing.vehicleName .. " sold to " .. offer.buyerName .. " for $" .. formatMoney(offer.amount)
      })

      -- Remove listing
      playerListings[listingId] = nil

      return true, offer.amount
    end
  end

  return false, "Listing not found"
end

---------------------------------------------------------------------------
-- Save/Load
---------------------------------------------------------------------------

function M.getSaveData()
  -- Clean up expired data before saving
  cleanExpiredListings()
  cleanExpiredOffers()
  cleanOrphanedListings()

  return {
    listings = listings,
    playerListings = playerListings,
    cart = cart,
    nextListingId = nextListingId,
    lastRefreshTime = lastRefreshTime
  }
end

function M.loadSaveData(data)
  if data then
    listings = data.listings or {}
    playerListings = data.playerListings or {}
    cart = data.cart or {}
    nextListingId = data.nextListingId or 1
    lastRefreshTime = data.lastRefreshTime or 0
  end
end

---------------------------------------------------------------------------
-- Module Lifecycle
---------------------------------------------------------------------------

function M.onExtensionLoaded()
  -- Skip initialization if not in career mode
  if not career_career or not career_career.isActive() then
    log("I", "Black Market skipped - not in career mode")
    return
  end
  log("I", "Black Market loaded")
  -- Don't generate listings on load - wait until UI requests them
  -- This avoids issues with util_configListGenerator not being ready
end

-- Called when career mode starts or ends
function M.onCareerActive(active)
  if active then
    log("I", "Career activated - Black Market ready")
  else
    log("I", "Career deactivated - clearing Black Market data")
    listings = {}
    playerListings = {}
    cart = {}
  end
end

return M
