-- Car Theft Career - Configuration

local M = {}

-- Detection
M.PROXIMITY_DISTANCE = 5
M.STEAL_KEY = "r"

-- Hotwire timing
M.HOTWIRE_TIME = 2.5

-- Report timer
M.REPORT_TIME_MIN = 3
M.REPORT_TIME_MAX = 8
M.REPORT_TIME_VALUE_FACTOR = 0.5

-- Police escalation (seconds after reported)
M.ESCALATION_LEVEL2_TIME = 30
M.ESCALATION_LEVEL3_TIME = 60

-- Pursuit scores
M.INITIAL_PURSUIT_SCORE = 1000
M.LEVEL2_PURSUIT_SCORE = 1500
M.LEVEL3_PURSUIT_SCORE = 2000

-- Police spawn
M.POLICE_SPAWN_COUNT = 2

-- Rewards
M.REWARD_PERCENT = 0.4
M.REWARD_MIN = 500
M.REWARD_MAX = 50000

-- Fines
M.FINE_BASE = 500
M.FINE_PERCENT = 0.4
M.FINE_MAX = 10000

-- UI
M.SHOW_STEAL_PROMPT = true
M.SHOW_TIMER_UI = true
M.SHOW_WANTED_LEVEL = true

---------------------------------------------------------------------------
-- Job Manager
---------------------------------------------------------------------------

-- Generation
M.JOB_GENERATION_INTERVAL = 120
M.MAX_CONCURRENT_JOBS = 5
M.INITIAL_JOBS_COUNT = 3
M.RECENT_CATEGORIES_AVOID = 3
M.MAX_COMPLETED_JOB_IDS = 50

-- Values and fees
M.MIN_VEHICLE_VALUE = 1000
M.INTEL_FEE_MIN = 0.45
M.INTEL_FEE_MAX = 1.15
M.JOB_EXPIRATION_TIME = 3600

-- Tier thresholds
M.TIER1_MAX_VALUE = 15000
M.TIER2_MAX_VALUE = 40000

-- Tier chances (should sum to 1.0)
M.TIER1_CHANCE = 0.50
M.TIER2_CHANCE = 0.35
M.TIER3_CHANCE = 0.15

-- Spawn distances
M.MIN_PARKING_DISTANCE = 300
M.VEHICLE_SPAWN_DISTANCE = 500
M.VEHICLE_DESPAWN_DISTANCE = 600

---------------------------------------------------------------------------
-- Black Market
---------------------------------------------------------------------------

-- Vehicle value range
M.BM_MIN_VEHICLE_VALUE = 1000
M.BM_MAX_VEHICLE_VALUE = 500000

-- Listings
M.BM_INITIAL_LISTINGS = 8
M.BM_LISTING_EXPIRY_MIN = 86400
M.BM_LISTING_EXPIRY_MAX = 129600
M.BM_MAX_LISTING_ID = 100000

-- Reputation thresholds
M.BM_REP_VERY_SKETCHY = 0.3
M.BM_REP_SKETCHY = 0.6

-- Pricing multipliers by reputation
M.BM_PRICE_VERY_SKETCHY_MIN = 0.40
M.BM_PRICE_VERY_SKETCHY_MAX = 0.60
M.BM_PRICE_SKETCHY_MIN = 0.60
M.BM_PRICE_SKETCHY_MAX = 0.80
M.BM_PRICE_TRUSTED_MIN = 0.75
M.BM_PRICE_TRUSTED_MAX = 0.95

-- Purchase outcomes {scam, clunker, legit} (should sum to 1.0)
M.BM_OUTCOME_VERY_SKETCHY = {0.40, 0.30, 0.30}
M.BM_OUTCOME_SKETCHY = {0.20, 0.25, 0.55}
M.BM_OUTCOME_TRUSTED = {0.05, 0.15, 0.80}

-- Legit vehicle condition
M.BM_LEGIT_MILEAGE_MIN = 10000
M.BM_LEGIT_MILEAGE_MAX = 80000
M.BM_LEGIT_INTEGRITY_MIN = 0.70
M.BM_LEGIT_INTEGRITY_MAX = 0.95

-- Clunker vehicle condition
M.BM_CLUNKER_MILEAGE_MIN = 100000
M.BM_CLUNKER_MILEAGE_MAX = 200000
M.BM_CLUNKER_INTEGRITY_MIN = 0.40
M.BM_CLUNKER_INTEGRITY_MAX = 0.60

-- Player selling
M.BM_UNDOCUMENTED_PENALTY = 0.60
M.BM_BUYER_OFFER_MIN = 0.50
M.BM_BUYER_OFFER_MAX = 0.90
M.BM_FIRST_OFFER_CHANCE = 0.70
M.BM_SUBSEQUENT_OFFER_CHANCE = 0.50
M.BM_MAX_OFFERS = 3
M.BM_MIN_OFFER_DELAY = 10
M.BM_OFFER_EXPIRY_MIN = 3600
M.BM_OFFER_EXPIRY_MAX = 7200

---------------------------------------------------------------------------
-- Documentation
---------------------------------------------------------------------------

-- Budget Tier: Cheap but slow and risky
M.DOC_TIER_BUDGET = {
  costPercent = 0.15,     -- 15% of vehicle value
  costMin = 5000,         -- Minimum $5,000
  hours = 8,              -- 8 in-game hours processing time
  detectChance = 0.40     -- 40% detection risk
}

-- Standard Tier: Better quality, higher cost, longer wait
M.DOC_TIER_STANDARD = {
  costPercent = 0.25,     -- 25% of vehicle value
  costMin = 10000,        -- Minimum $10,000
  hours = 16,             -- 16 in-game hours processing time
  detectChance = 0.15     -- 15% detection risk
}

-- Premium Tier: Pay flat fee, instant documents
M.DOC_TIER_PREMIUM = {
  cost = 100000,          -- Flat $100k
  detectChance = 0.02     -- 2% detection risk (nearly undetectable)
}

---------------------------------------------------------------------------
-- Heat System
---------------------------------------------------------------------------

M.HEAT_INITIAL = 100
M.HEAT_DECAY_PER_HOUR = 10
M.HEAT_MIN = 10

---------------------------------------------------------------------------
-- Police Inspection
---------------------------------------------------------------------------

M.INSPECTION_BASE_CHANCE = 0.0005
M.INSPECTION_POLICE_RANGE = 50
M.INSPECTION_COOLDOWN = 60

return M
