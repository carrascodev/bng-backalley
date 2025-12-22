'use strict'

angular.module('beamng.stuff')
.controller('BackAlleyBrowserController', ['$scope', '$state', function($scope, $state) {

  // =========================================================================
  // Browser State
  // =========================================================================
  $scope.currentSite = 'hotwheels';
  $scope.currentUrl = 'hotwheels.bally';
  $scope.browserTitle = 'BackAlley.help';
  $scope.playerMoney = 0;

  $scope.bookmarks = [
    { name: 'Hot Wheels', site: 'hotwheels', url: 'hotwheels.bally', icon: 'fire' },
    { name: 'Black Market', site: 'blackmarket', url: 'blackmarket.bally', icon: 'cart' },
    { name: 'Legit Docs', site: 'legitdocs', url: 'legitdocs.bally', icon: 'file' }
  ];

  // Navigation
  $scope.navigateTo = function(site) {
    $scope.currentSite = site;
    var bookmark = $scope.bookmarks.find(function(b) { return b.site === site; });
    $scope.currentUrl = bookmark ? bookmark.url : site + '.bally';
    $scope.refreshCurrentSite();
  };

  $scope.refreshCurrentSite = function() {
    if ($scope.currentSite === 'hotwheels') {
      $scope.loadHotWheelsData();
    } else if ($scope.currentSite === 'blackmarket') {
      $scope.loadBlackMarketData();
    } else if ($scope.currentSite === 'legitdocs') {
      $scope.loadLegitDocsData();
    }
  };

  // Close browser
  $scope.closeBrowser = function() {
    bngApi.engineLua("career_career.closeAllMenus()");
  };

  // Load player money
  $scope.loadPlayerMoney = function() {
    bngApi.engineLua("career_modules_playerAttributes.getAttributeValue('money')", function(result) {
      $scope.$evalAsync(function() {
        $scope.playerMoney = result || 0;
      });
    });
  };

  // Format money display
  $scope.formatMoney = function(amount) {
    if (amount === null || amount === undefined) return '$0';
    return '$' + Number(amount).toLocaleString();
  };

  // =========================================================================
  // HotWheels Site (Car Theft Jobs)
  // =========================================================================
  $scope.hotWheelsData = {
    jobs: [],
    loading: true
  };

  $scope.loadHotWheelsData = function() {
    $scope.hotWheelsData.loading = true;
    bngApi.engineLua("carTheft_jobManager.getJobsForUI()", function(result) {
      $scope.$evalAsync(function() {
        $scope.hotWheelsData.jobs = result || [];
        $scope.hotWheelsData.loading = false;
      });
    });
    $scope.loadPlayerMoney();
  };

  // Get tier stars
  $scope.getTierStars = function(tier) {
    if (tier === 1) return '\u2605';
    if (tier === 2) return '\u2605\u2605';
    if (tier === 3) return '\u2605\u2605\u2605';
    return '\u2605';
  };

  // Get tier class for styling
  $scope.getTierClass = function(tier) {
    if (tier === 1) return 'tier-economy';
    if (tier === 2) return 'tier-midrange';
    if (tier === 3) return 'tier-premium';
    return 'tier-economy';
  };

  // Get state class for styling
  $scope.getStateClass = function(state) {
    if (state === 'available') return 'state-available';
    if (state === 'unlocked' || state === 'spawned') return 'state-unlocked';
    if (state === 'active') return 'state-active';
    return '';
  };

  // Check if player can afford unlock fee
  $scope.canAfford = function(fee) {
    return $scope.playerMoney >= fee;
  };

  // Unlock job (pay fee)
  $scope.unlockJob = function(job) {
    if (!$scope.canAfford(job.fee)) {
      return;
    }
    bngApi.engineLua('carTheft_jobManager.unlockJob(' + job.id + ')', function(result) {
      $scope.loadHotWheelsData();
    });
  };

  // Set GPS to job location
  $scope.setGPS = function(job) {
    bngApi.engineLua('carTheft_jobManager.setJobGPS(' + job.id + ')');
    $scope.closeBrowser();
  };

  // =========================================================================
  // Black Market Site (Buy/Sell Undocumented Cars)
  // =========================================================================
  $scope.blackMarketData = {
    listings: [],
    playerListings: [],
    cart: [],
    loading: true,
    view: 'browse', // 'browse' or 'sell'
    checkoutResult: null
  };

  $scope.loadBlackMarketData = function() {
    $scope.blackMarketData.loading = true;
    $scope.blackMarketData.checkoutResult = null;

    // Load NPC listings
    bngApi.engineLua("carTheft_blackMarket.getListingsForUI()", function(result) {
      $scope.$evalAsync(function() {
        $scope.blackMarketData.listings = result || [];
      });
    });

    // Load cart
    bngApi.engineLua("carTheft_blackMarket.getCartForUI()", function(result) {
      $scope.$evalAsync(function() {
        if (result) {
          $scope.blackMarketData.cart = result.items || [];
        }
        $scope.blackMarketData.loading = false;
      });
    });

    // Load player listings (for sell view)
    bngApi.engineLua("carTheft_blackMarket.getPlayerListingsForUI()", function(result) {
      $scope.$evalAsync(function() {
        $scope.blackMarketData.playerListings = result || [];
      });
    });

    $scope.loadPlayerMoney();
  };

  $scope.setBlackMarketView = function(view) {
    $scope.blackMarketData.view = view;
    $scope.blackMarketData.checkoutResult = null;
  };

  $scope.addToCart = function(listing) {
    bngApi.engineLua('carTheft_blackMarket.addToCart(' + listing.id + ')', function(result) {
      $scope.loadBlackMarketData();
    });
  };

  $scope.removeFromCart = function(item) {
    bngApi.engineLua('carTheft_blackMarket.removeFromCart(' + item.listingId + ')', function(result) {
      $scope.loadBlackMarketData();
    });
  };

  $scope.isInCart = function(listing) {
    for (var i = 0; i < $scope.blackMarketData.cart.length; i++) {
      if ($scope.blackMarketData.cart[i].listingId === listing.id) {
        return true;
      }
    }
    return false;
  };

  $scope.checkout = function() {
    if ($scope.blackMarketData.cart.length === 0) return;

    bngApi.engineLua('carTheft_blackMarket.checkout()', function(result) {
      $scope.$evalAsync(function() {
        if (result && result.success) {
          $scope.blackMarketData.checkoutResult = result;
          $scope.blackMarketData.cart = [];
        } else {
          $scope.blackMarketData.checkoutResult = {
            success: false,
            message: result ? result.message : 'Checkout failed'
          };
        }
        $scope.loadBlackMarketData();
      });
    });
  };

  $scope.getCartTotal = function() {
    var total = 0;
    for (var i = 0; i < $scope.blackMarketData.cart.length; i++) {
      total += $scope.blackMarketData.cart[i].price;
    }
    return total;
  };

  $scope.getOutcomeClass = function(outcome) {
    if (outcome === 'legit') return 'outcome-success';
    if (outcome === 'clunker') return 'outcome-warning';
    if (outcome === 'scam') return 'outcome-danger';
    return '';
  };

  // List a stolen vehicle for sale
  $scope.listForSale = function(listing) {
    var price = listing.inputPrice || listing.value;
    bngApi.engineLua('carTheft_blackMarket.listVehicleForSale(' + listing.inventoryId + ', ' + price + ')', function(result) {
      $scope.loadBlackMarketData();
    });
  };

  // Remove a listing
  $scope.unlistVehicle = function(listing) {
    bngApi.engineLua('carTheft_blackMarket.unlistVehicle(' + listing.inventoryId + ')', function(result) {
      $scope.loadBlackMarketData();
    });
  };

  // Accept an offer on a player listing
  $scope.acceptOffer = function(listing, offerIndex) {
    bngApi.engineLua('carTheft_blackMarket.acceptPlayerOffer(' + listing.inventoryId + ', ' + (offerIndex + 1) + ')', function(result) {
      $scope.$evalAsync(function() {
        if (result && result[0]) {
          // Success - show message
          $scope.blackMarketData.saleResult = {
            success: true,
            vehicleName: listing.vehicleName,
            amount: result[1]
          };
        }
        $scope.loadBlackMarketData();
      });
    });
  };

  // =========================================================================
  // LegitDocs Site (Documentation Service) - Tiered System
  // =========================================================================
  $scope.legitDocsData = {
    vehicles: [],
    tiers: {},
    loading: true,
    message: null,
    selectedTier: 'standard'
  };

  $scope.loadLegitDocsData = function() {
    $scope.legitDocsData.loading = true;
    $scope.legitDocsData.message = null;

    // Get tier info
    bngApi.engineLua("carTheft_documentation.getTierInfo()", function(result) {
      $scope.$evalAsync(function() {
        $scope.legitDocsData.tiers = result || {};
      });
    });

    // Load vehicles with their status
    bngApi.engineLua("carTheft_documentation.getVehiclesForUI()", function(result) {
      $scope.$evalAsync(function() {
        $scope.legitDocsData.vehicles = result || [];
        $scope.legitDocsData.loading = false;
      });
    });

    $scope.loadPlayerMoney();
  };

  $scope.getTierFee = function(vehicle, tierName) {
    if (!vehicle.fees) return 0;
    return vehicle.fees[tierName] || 0;
  };

  $scope.formatTime = function(seconds) {
    if (!seconds || seconds <= 0) return 'Ready!';
    var hours = Math.floor(seconds / 3600);
    var mins = Math.floor((seconds % 3600) / 60);
    if (hours > 0) {
      return hours + 'h ' + mins + 'm';
    }
    return mins + 'm';
  };

  $scope.orderDocuments = function(vehicle, tierName) {
    var fee = $scope.getTierFee(vehicle, tierName);
    if (!$scope.canAfford(fee)) {
      return;
    }

    bngApi.engineLua('carTheft_documentation.orderDocuments(' + vehicle.inventoryId + ', "' + tierName + '")', function(result) {
      $scope.$evalAsync(function() {
        if (result && result[0]) {
          $scope.legitDocsData.message = { type: 'success', text: 'Documents ordered! Processing...' };
        } else {
          $scope.legitDocsData.message = { type: 'error', text: result ? result[1] : 'Failed to order documents.' };
        }
        $scope.loadLegitDocsData();
      });
    });
  };

  $scope.collectDocuments = function(vehicle) {
    bngApi.engineLua('carTheft_documentation.collectDocuments(' + vehicle.inventoryId + ')', function(result) {
      $scope.$evalAsync(function() {
        if (result && result[0]) {
          $scope.legitDocsData.message = { type: 'success', text: 'Documents collected! Vehicle is now legal.' };
        } else {
          $scope.legitDocsData.message = { type: 'error', text: result ? result[1] : 'Failed to collect documents.' };
        }
        $scope.loadLegitDocsData();
      });
    });
  };

  $scope.getTierClass = function(tierName) {
    if (tierName === 'budget') return 'tier-budget';
    if (tierName === 'standard') return 'tier-standard';
    if (tierName === 'premium') return 'tier-premium';
    return '';
  };

  $scope.getDetectRisk = function(tierName) {
    var tier = $scope.legitDocsData.tiers[tierName];
    if (!tier) return '?%';
    return Math.round(tier.detectChance * 100) + '%';
  };

  // =========================================================================
  // Initialization
  // =========================================================================
  $scope.loadPlayerMoney();
  $scope.loadHotWheelsData();

}])

// Register the state with ui-router
.config(['$stateProvider', function($stateProvider) {
  $stateProvider.state('menu.backalley', {
    url: '/backalley',
    templateUrl: '/ui/modModules/backalley/backalley.html',
    controller: 'BackAlleyBrowserController',
  })
}])

// Export the module for BeamNG's modModule system
angular.module('backalley', ['ui.router'])
