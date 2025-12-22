# Car Theft Career Mod - Balancing Table

> All hardcoded game design values with file locations for easy editing.

---

## Prices & Fees

| Value | Description | File | Line |
|-------|-------------|------|------|
| `$5,000` | Documentation fee (LegitDocs) | `documentation.lua` | 22 |
| `$500 + value × 0.2` | Arrest fine formula | `main.lua` | 43-45 |
| `max $10,000` | Maximum arrest fine | `main.lua` | 45 |
| `70-115%` of value | Intel fee range for jobs | `jobManager.lua` | 437 |
| `$1,000` | Minimum vehicle value for jobs | `jobManager.lua` | 228 |
| `$1,000 - $500,000` | Black market vehicle value range | `blackMarket.lua` | 113 |

---

## Black Market Purchase Outcomes

| Seller Reputation | Scam % | Clunker % | Legit % | File | Lines |
|-------------------|--------|-----------|---------|------|-------|
| Very Sketchy (<0.3) | 40% | 30% | 30% | `blackMarket.lua` | 273-277 |
| Sketchy (0.3-0.6) | 20% | 25% | 55% | `blackMarket.lua` | 279-282 |
| Trusted (>0.6) | 5% | 15% | 80% | `blackMarket.lua` | 284-287 |

---

## Black Market Pricing

| Seller Type | Price Multiplier | Description | File | Line |
|-------------|------------------|-------------|------|------|
| Very Sketchy (<0.4 rep) | 40-60% | Too good to be true | `blackMarket.lua` | 79-80 |
| Sketchy (0.4-0.7 rep) | 60-80% | Good deal | `blackMarket.lua` | 81-82 |
| Trusted (>0.7 rep) | 75-95% | Fair price | `blackMarket.lua` | 83-84 |

---

## Black Market Vehicle Condition

| Type | Mileage Range | Part Integrity | File | Lines |
|------|---------------|----------------|------|-------|
| Legit car | 10,000 - 80,000 miles | 70-95% | `blackMarket.lua` | 308-312 |
| Clunker | 100,000 - 200,000 miles | 40-60% | `blackMarket.lua` | 308-312 |

> Black market cars now come with realistic mileage and wear, affecting their actual value.

---

## Black Market Selling (Player)

| Value | Description | File | Line |
|-------|-------------|------|------|
| `0.6×` (40% less) | Penalty for undocumented vehicles | `blackMarket.lua` | 636 |
| `50-90%` of value | NPC buyer offer range | `blackMarket.lua` | 639 |
| `70%` | First offer generation chance | `blackMarket.lua` | 632 |
| `50%` | Subsequent offer generation chance | `blackMarket.lua` | 632 |
| `3 max` | Maximum offers per listing | `blackMarket.lua` | 629 |
| `10 sec` | Minimum time before first offer | `blackMarket.lua` | 628 |
| `1-2 hours` | Offer expiration time | `blackMarket.lua` | 646 |

---

## Job Tiers & Distribution

| Tier | Vehicle Value | Generation Chance | File | Line |
|------|---------------|-------------------|------|------|
| 1 (Economy) | < $15,000 | 50% | `jobManager.lua` | 208, 471-472 |
| 2 (Mid-range) | $15,000 - $40,000 | 35% | `jobManager.lua` | 209, 473-474 |
| 3 (Premium) | > $40,000 | 15% | `jobManager.lua` | 210, 475-476 |

---

## Time Durations

| Value | Description | File | Line |
|-------|-------------|------|------|
| `2.5 sec` | Hotwire time to steal | `main.lua` | 31 |
| `3-8 sec` | Report timer range | `config.lua` | 14-15 |
| `30 sec` | Time to police level 2 | `config.lua` | 19 |
| `60 sec` | Time to police level 3 | `config.lua` | 20 |
| `1 hour` | Job expiration time | `jobManager.lua` | 518 |
| `24-36 hours` | Black market listing expiration | `blackMarket.lua` | 91 |
| `2 min` | Job generation interval | `jobManager.lua` | 395 |

---

## Distances

| Value | Description | File | Line |
|-------|-------------|------|------|
| `5 meters` | Proximity to steal vehicle | `main.lua` | 30 |
| `300 meters` | Minimum parking spot distance from player | `jobManager.lua` | 136 |
| `500 meters` | Vehicle spawn trigger distance | `jobManager.lua` | 671 |
| `600 meters` | Vehicle despawn distance | `jobManager.lua` | 672 |

---

## Police Pursuit

| Value | Description | File | Line |
|-------|-------------|------|------|
| `500` | Initial pursuit score | `main.lua` | 37 |
| `800` | Level 2 pursuit score | `main.lua` | 38 |
| `1200` | Level 3 pursuit score | `main.lua` | 39 |

---

## Limits

| Value | Description | File | Line |
|-------|-------------|------|------|
| `5` | Maximum concurrent jobs | `jobManager.lua` | 396 |
| `3` | Initial jobs on unlock | `jobManager.lua` | 867 |
| `8` | Initial black market listings | `blackMarket.lua` | 96 |
| `3` | Recent categories to avoid (variety) | `jobManager.lua` | 21 |

---

## Memory Management

| Value | Description | File | Line |
|-------|-------------|------|------|
| `50` | Max completed job IDs stored | `jobManager.lua` | 22 |
| `100,000` | Max listing ID before reset | `blackMarket.lua` | 28 |
| `3` | Max offers per player listing | `blackMarket.lua` | 668 |
| `1-2 hours` | Offer expiration time | `blackMarket.lua` | 685 |

> These limits prevent memory leaks during extended play sessions.

---

## Controls

| Key | Action | File | Line |
|-----|--------|------|------|
| `E` | Steal vehicle | `config.lua` | 8 |

---

## Quick Reference - Most Impactful Values

### To make game easier:
- Increase hotwire time (`main.lua:31`)
- Increase report timer (`config.lua:14-15`)
- Lower scam percentages (`blackMarket.lua:273-287`)
- Reduce documentation fee (`documentation.lua:22`)

### To make game harder:
- Decrease hotwire time
- Decrease report timer
- Increase scam percentages
- Increase police pursuit scores

### To adjust economy:
- Modify intel fee range (`jobManager.lua:437`)
- Adjust buyer offer range (`blackMarket.lua:639`)
- Change documentation fee (`documentation.lua:22`)
- Modify undocumented penalty (`blackMarket.lua:636`)
