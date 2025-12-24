/**
 * BeamNG API Mock for Standalone UI Testing
 * This mocks bngApi.engineLua() to return realistic test data
 */

// Mock data store
const MockData = {
  playerMoney: 75000,

  // Hot Wheels jobs
  jobs: [
    { id: 1, state: 'available', vehicleName: '???', tier: 1, area: 'Downtown', fee: 8500, expiresIn: 3200 },
    { id: 2, state: 'available', vehicleName: '???', tier: 2, area: 'Industrial', fee: 22000, expiresIn: 2800 },
    { id: 3, state: 'unlocked', vehicleName: 'ETK 800 Sport', vehicleValue: 45000, tier: 2, area: 'Suburbs', fee: 38000, expiresIn: 1500 },
    { id: 4, state: 'available', vehicleName: '???', tier: 3, area: 'Coast', fee: 85000, expiresIn: 3500 },
    { id: 5, state: 'spawned', vehicleName: 'Hirochi Sunburst', vehicleValue: 22000, tier: 1, area: 'Highway', fee: 18500, expiresIn: 900 },
  ],

  // My Rides vehicles
  stolenVehicles: [
    { inventoryId: 101, name: 'Bruckell LeGran', value: 18000, heat: 85, hasDocuments: false, pendingDoc: false },
    { inventoryId: 102, name: 'ETK 800', value: 35000, heat: 45, hasDocuments: false, pendingDoc: true, pendingHoursLeft: 4.5, documentTier: 'standard' },
    { inventoryId: 103, name: 'Ibishu Covet', value: 8000, heat: 10, hasDocuments: true, documentTier: 'budget', detectChance: 0.40 },
    { inventoryId: 104, name: 'Civetta Bolide', value: 75000, heat: 100, hasDocuments: false, pendingDoc: false },
  ],

  // Black Market listings
  listings: [
    { id: 201, vehicleName: 'Gavril Barstow', price: 19200, reputation: 0.25, sellerName: 'Shadow Mike', description: 'Quick sale, no questions' },
    { id: 202, vehicleName: 'Cherrier Vivace', price: 8800, reputation: 0.55, sellerName: 'Dusty', description: 'Good condition, papers lost' },
    { id: 203, vehicleName: 'Hirochi Pessima', price: 13500, reputation: 0.82, sellerName: 'The Mechanic', description: 'Clean vehicle, reliable seller' },
    { id: 204, vehicleName: 'ETK I-Series', price: 42000, reputation: 0.35, sellerName: 'Ghost', description: 'Quick sale, no questions' },
    { id: 205, vehicleName: 'Bruckell Bluebuck', price: 24500, reputation: 0.78, sellerName: 'Chrome', description: 'Clean vehicle, reliable seller' },
  ],

  // Player listings for selling
  playerListings: [
    {
      inventoryId: 101, vehicleName: 'Bruckell LeGran', value: 18000, hasDocuments: false, isListed: true,
      askingPrice: 15000,
      offers: [
        { buyerName: 'Slim', amount: 9500 },
        { buyerName: 'Wheels', amount: 11200 }
      ]
    },
    { inventoryId: 104, vehicleName: 'Civetta Bolide', value: 75000, hasDocuments: false, isListed: false, offers: [] }
  ],

  // Shopping cart
  cart: { items: [], total: 0 },

  // Documentation tiers
  tiers: {
    budget: { name: 'Budget', costPercent: 0.15, costMin: 5000, hours: 8, detectChance: 0.40 },
    standard: { name: 'Standard', costPercent: 0.25, costMin: 10000, hours: 16, detectChance: 0.15 },
    premium: { name: 'Premium', cost: 100000, detectChance: 0.02 }
  },

  // Undocumented vehicles for docs service
  undocumentedVehicles: [
    { inventoryId: 101, name: 'Bruckell LeGran', value: 18000, fees: { budget: 5000, standard: 10000, premium: 100000 }, pending: false },
    { inventoryId: 104, name: 'Civetta Bolide', value: 75000, fees: { budget: 11250, standard: 18750, premium: 100000 }, pending: false },
    { inventoryId: 102, name: 'ETK 800', value: 35000, fees: {}, pending: true, ready: false, tier: 'standard', remainingHours: 4.5 },
  ]
};

// API call log for debugging
const apiLog = [];

/**
 * Parse Lua function call string and extract function name and arguments
 */
function parseLuaCall(luaCode) {
  // Match patterns like: moduleName.functionName(args)
  const match = luaCode.match(/^([a-zA-Z_][a-zA-Z0-9_]*(?:\.[a-zA-Z_][a-zA-Z0-9_]*)*)\s*\(([^)]*)\)$/);
  if (match) {
    return {
      func: match[1],
      args: match[2] ? match[2].split(',').map(a => a.trim().replace(/^["']|["']$/g, '')) : []
    };
  }
  return { func: luaCode, args: [] };
}

/**
 * Mock bngApi object
 */
window.bngApi = {
  engineLua: function(luaCode, callback) {
    const parsed = parseLuaCall(luaCode);
    apiLog.push({ time: new Date().toISOString(), call: luaCode, parsed });

    console.log('[Mock API]', luaCode);

    // Simulate async behavior
    setTimeout(() => {
      let result = null;

      switch (parsed.func) {
        // Player attributes
        case "career_modules_playerAttributes.getAttributeValue":
          if (parsed.args[0] === 'money') {
            result = MockData.playerMoney;
          }
          break;

        // Job Manager
        case "carTheft_jobManager.getJobsForUI":
          result = MockData.jobs;
          break;

        case "carTheft_jobManager.unlockJob":
          const jobId = parseInt(parsed.args[0]);
          const job = MockData.jobs.find(j => j.id === jobId);
          if (job && job.state === 'available') {
            MockData.playerMoney -= job.fee;
            job.state = 'unlocked';
            job.vehicleName = 'ETK 800 Sport';  // Reveal name
            job.vehicleValue = 45000;
            result = true;
          }
          break;

        case "carTheft_jobManager.setJobGPS":
          result = true;
          break;

        // Vehicle Status (My Rides)
        case "carTheft_main.getVehicleStatusForUI":
          result = MockData.stolenVehicles;
          break;

        // Black Market
        case "carTheft_blackMarket.getListingsForUI":
          result = MockData.listings;
          break;

        case "carTheft_blackMarket.getCartForUI":
          result = MockData.cart;
          break;

        case "carTheft_blackMarket.getPlayerListingsForUI":
          result = MockData.playerListings;
          break;

        case "carTheft_blackMarket.addToCart":
          const listingId = parseInt(parsed.args[0]);
          const listing = MockData.listings.find(l => l.id === listingId);
          if (listing && !MockData.cart.items.find(i => i.listingId === listingId)) {
            MockData.cart.items.push({
              listingId: listing.id,
              vehicleName: listing.vehicleName,
              price: listing.price
            });
            MockData.cart.total += listing.price;
            result = true;
          }
          break;

        case "carTheft_blackMarket.removeFromCart":
          const removeId = parseInt(parsed.args[0]);
          const idx = MockData.cart.items.findIndex(i => i.listingId === removeId);
          if (idx >= 0) {
            MockData.cart.total -= MockData.cart.items[idx].price;
            MockData.cart.items.splice(idx, 1);
            result = true;
          }
          break;

        case "carTheft_blackMarket.checkout":
          if (MockData.cart.items.length > 0 && MockData.playerMoney >= MockData.cart.total) {
            MockData.playerMoney -= MockData.cart.total;
            const results = MockData.cart.items.map(item => {
              const outcomes = ['legit', 'clunker', 'scam'];
              const outcome = outcomes[Math.floor(Math.random() * outcomes.length)];
              return {
                vehicleName: item.vehicleName,
                outcome: outcome,
                message: outcome === 'legit' ? 'Vehicle delivered!' :
                         outcome === 'clunker' ? 'You got a junker!' : 'SCAMMED!'
              };
            });
            const totalPaid = MockData.cart.total;
            MockData.cart = { items: [], total: 0 };
            result = { success: true, results, totalPaid };
          } else {
            result = { success: false, message: 'Not enough money' };
          }
          break;

        case "carTheft_blackMarket.listVehicleForSale":
          result = true;
          break;

        case "carTheft_blackMarket.unlistVehicle":
          result = true;
          break;

        case "carTheft_blackMarket.acceptPlayerOffer":
          result = [true, 11200];  // [success, amount]
          break;

        // Documentation
        case "carTheft_documentation.getTierInfo":
          result = MockData.tiers;
          break;

        case "carTheft_documentation.getVehiclesForUI":
          result = MockData.undocumentedVehicles;
          break;

        case "carTheft_documentation.orderDocuments":
          const invId = parseInt(parsed.args[0]);
          const tier = parsed.args[1];
          const vehicle = MockData.undocumentedVehicles.find(v => v.inventoryId === invId);
          if (vehicle && !vehicle.pending) {
            const fee = vehicle.fees[tier];
            if (MockData.playerMoney >= fee) {
              MockData.playerMoney -= fee;
              vehicle.pending = true;
              vehicle.tier = tier;
              vehicle.remainingHours = tier === 'premium' ? 0 : (tier === 'standard' ? 16 : 8);
              vehicle.ready = tier === 'premium';
              result = [true, 'Documents ordered'];
            } else {
              result = [false, 'Not enough money'];
            }
          }
          break;

        case "carTheft_documentation.collectDocuments":
          const collectId = parseInt(parsed.args[0]);
          const docVeh = MockData.undocumentedVehicles.find(v => v.inventoryId === collectId);
          if (docVeh && docVeh.ready) {
            // Remove from undocumented list
            const docIdx = MockData.undocumentedVehicles.indexOf(docVeh);
            MockData.undocumentedVehicles.splice(docIdx, 1);
            // Update stolen vehicles
            const stolen = MockData.stolenVehicles.find(v => v.inventoryId === collectId);
            if (stolen) {
              stolen.hasDocuments = true;
              stolen.pendingDoc = false;
            }
            result = [true, 'Documents collected'];
          } else {
            result = [false, 'Documents not ready'];
          }
          break;

        // Close menu
        case "career_career.closeAllMenus":
          console.log('[Mock] Close menus called');
          break;

        default:
          console.warn('[Mock] Unhandled API call:', parsed.func);
      }

      if (callback) {
        callback(result);
      }
    }, 50);  // 50ms delay to simulate async
  }
};

// Expose mock data for debugging
window.MockData = MockData;
window.apiLog = apiLog;

console.log('BeamNG API Mock loaded. Access MockData and apiLog in console for debugging.');
