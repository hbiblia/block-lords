-- =====================================================
-- BLOCK LORDS - Initial Data
-- =====================================================
-- Safe to run multiple times (uses ON CONFLICT)
-- Translations handled in frontend: t(`data.rigs.${id}.name`)

-- Rigs (internet = 80% of power consumption)
-- Currency: gamecoin (basic/standard), crypto (asic_s9), ron (advanced/elite)
INSERT INTO rigs (id, name, description, hashrate, power_consumption, internet_consumption, repair_cost, tier, base_price, currency)
VALUES
  ('basic_miner', 'basic_miner', 'basic_miner', 100, 2.5, 2.0, 80, 'basic', 0, 'gamecoin'),
  ('home_miner', 'home_miner', 'home_miner', 250, 5.0, 4.0, 500, 'basic', 600, 'gamecoin'),
  ('gpu_rig', 'gpu_rig', 'gpu_rig', 500, 8.0, 6.4, 1200, 'standard', 1800, 'gamecoin'),
  ('asic_s9', 'asic_s9', 'asic_s9', 1000, 12.0, 9.6, 2500, 'standard', 1000, 'crypto'),
  ('asic_s19', 'asic_s19', 'asic_s19', 2500, 18.0, 14.4, 5000, 'advanced', 5, 'ron'),
  ('mining_farm_small', 'mining_farm_small', 'mining_farm_small', 5000, 28.0, 22.4, 12000, 'advanced', 10, 'ron'),
  ('mining_farm_large', 'mining_farm_large', 'mining_farm_large', 10000, 40.0, 32.0, 25000, 'elite', 20, 'ron'),
  ('quantum_miner', 'quantum_miner', 'quantum_miner', 25000, 55.0, 44.0, 50000, 'elite', 50, 'ron')
ON CONFLICT (id) DO UPDATE SET
  hashrate = EXCLUDED.hashrate,
  power_consumption = EXCLUDED.power_consumption,
  internet_consumption = EXCLUDED.internet_consumption,
  repair_cost = EXCLUDED.repair_cost,
  tier = EXCLUDED.tier,
  base_price = EXCLUDED.base_price,
  currency = EXCLUDED.currency;

-- Badges
INSERT INTO badges (id, name, description, icon)
VALUES
  ('rising_star', 'rising_star', 'rising_star', '⭐'),
  ('trusted_miner', 'trusted_miner', 'trusted_miner', '🏆'),
  ('elite_trader', 'elite_trader', 'elite_trader', '💎'),
  ('crypto_legend', 'crypto_legend', 'crypto_legend', '👑'),
  ('first_block', 'first_block', 'first_block', '⛏️'),
  ('block_master', 'block_master', 'block_master', '🎯'),
  ('trade_master', 'trade_master', 'trade_master', '💰'),
  ('community_helper', 'community_helper', 'community_helper', '🤝'),
  ('event_champion', 'event_champion', 'event_champion', '🏅'),
  ('early_adopter', 'early_adopter', 'early_adopter', '🚀')
ON CONFLICT (id) DO UPDATE SET
  icon = EXCLUDED.icon;

-- Cooling items
-- cooling_power >= power_consumption * 0.8 to keep rig cool
INSERT INTO cooling_items (id, name, description, cooling_power, energy_cost, base_price, tier)
VALUES
  ('fan_basic', 'fan_basic', 'fan_basic', 4, 1, 120, 'basic'),
  ('fan_dual', 'fan_dual', 'fan_dual', 8, 2, 280, 'basic'),
  ('heatsink', 'heatsink', 'heatsink', 12, 3, 550, 'standard'),
  ('liquid_cooler', 'liquid_cooler', 'liquid_cooler', 18, 5, 1400, 'standard'),
  ('aio_cooler', 'aio_cooler', 'aio_cooler', 28, 8, 2800, 'advanced'),
  ('custom_loop', 'custom_loop', 'custom_loop', 40, 12, 5500, 'advanced'),
  ('industrial_ac', 'industrial_ac', 'industrial_ac', 55, 18, 14000, 'elite'),
  ('cryo_system', 'cryo_system', 'cryo_system', 75, 25, 28000, 'elite')
ON CONFLICT (id) DO UPDATE SET
  cooling_power = EXCLUDED.cooling_power,
  energy_cost = EXCLUDED.energy_cost,
  base_price = EXCLUDED.base_price,
  tier = EXCLUDED.tier;

-- Prepaid cards - Energy (1 Crypto = 50 GC, ~8 GC/unit base, crypto gives better value)
-- Free max 100, Premium max 500
-- Value progression: larger cards = better value per unit
INSERT INTO prepaid_cards (id, name, description, card_type, amount, base_price, tier, currency)
VALUES
  -- GameCoin cards (basic tier)
  ('energy_small', 'energy_small', 'energy_small', 'energy', 25, 200, 'basic', 'gamecoin'),
  ('energy_medium', 'energy_medium', 'energy_medium', 'energy', 50, 380, 'basic', 'gamecoin'),
  ('energy_large', 'energy_large', 'energy_large', 'energy', 100, 700, 'standard', 'gamecoin'),
  -- Crypto cards (premium tier, better value)
  ('energy_premium', 'energy_premium', 'energy_premium', 'energy', 50, 4, 'advanced', 'crypto'),
  ('energy_ultra', 'energy_ultra', 'energy_ultra', 'energy', 100, 7, 'advanced', 'crypto'),
  ('energy_mega', 'energy_mega', 'energy_mega', 'energy', 200, 12, 'elite', 'crypto'),
  ('energy_max', 'energy_max', 'energy_max', 'energy', 500, 25, 'elite', 'crypto')
ON CONFLICT (id) DO UPDATE SET
  card_type = EXCLUDED.card_type,
  amount = EXCLUDED.amount,
  base_price = EXCLUDED.base_price,
  tier = EXCLUDED.tier,
  currency = EXCLUDED.currency;

-- Prepaid cards - Internet (1 Crypto = 50 GC, ~7 GC/unit base, crypto gives better value)
-- Free max 100, Premium max 500
INSERT INTO prepaid_cards (id, name, description, card_type, amount, base_price, tier, currency)
VALUES
  -- GameCoin cards (basic tier)
  ('internet_small', 'internet_small', 'internet_small', 'internet', 25, 175, 'basic', 'gamecoin'),
  ('internet_medium', 'internet_medium', 'internet_medium', 'internet', 50, 330, 'basic', 'gamecoin'),
  ('internet_large', 'internet_large', 'internet_large', 'internet', 100, 600, 'standard', 'gamecoin'),
  -- Crypto cards (premium tier, better value)
  ('internet_premium', 'internet_premium', 'internet_premium', 'internet', 50, 4, 'advanced', 'crypto'),
  ('internet_ultra', 'internet_ultra', 'internet_ultra', 'internet', 100, 7, 'advanced', 'crypto'),
  ('internet_mega', 'internet_mega', 'internet_mega', 'internet', 200, 12, 'elite', 'crypto'),
  ('internet_max', 'internet_max', 'internet_max', 'internet', 500, 25, 'elite', 'crypto')
ON CONFLICT (id) DO UPDATE SET
  card_type = EXCLUDED.card_type,
  amount = EXCLUDED.amount,
  base_price = EXCLUDED.base_price,
  tier = EXCLUDED.tier,
  currency = EXCLUDED.currency;

-- Expand amount column to support values >= 1000 (was NUMERIC(5,2), max 999.99)
ALTER TABLE prepaid_cards ALTER COLUMN amount TYPE NUMERIC(7,2);

-- Allow 'combo' card_type and 'ron' currency (drop old check constraints and add new ones)
ALTER TABLE prepaid_cards DROP CONSTRAINT IF EXISTS prepaid_cards_card_type_check;
ALTER TABLE prepaid_cards ADD CONSTRAINT prepaid_cards_card_type_check CHECK (card_type IN ('energy', 'internet', 'combo'));
ALTER TABLE prepaid_cards DROP CONSTRAINT IF EXISTS prepaid_cards_currency_check;
ALTER TABLE prepaid_cards ADD CONSTRAINT prepaid_cards_currency_check CHECK (currency IN ('gamecoin', 'crypto', 'ron'));

-- Prepaid cards - Combo (Energy + Internet, RON)
INSERT INTO prepaid_cards (id, name, description, card_type, amount, base_price, tier, currency)
VALUES
  ('combo_basic', 'combo_basic', 'combo_basic', 'combo', 1100, 0.01, 'elite', 'ron')
ON CONFLICT (id) DO UPDATE SET
  card_type = EXCLUDED.card_type,
  amount = EXCLUDED.amount,
  base_price = EXCLUDED.base_price,
  tier = EXCLUDED.tier,
  currency = EXCLUDED.currency;

-- Delete old prepaid cards that no longer exist
-- First delete references in player_cards, then delete the prepaid cards
DELETE FROM player_cards WHERE card_id IN ('energy_10', 'energy_25', 'energy_50', 'energy_full', 'energy_medium', 'internet_10', 'internet_25', 'internet_50', 'internet_full', 'internet_medium');
DELETE FROM prepaid_cards WHERE id IN ('energy_10', 'energy_25', 'energy_50', 'energy_full', 'energy_medium', 'internet_10', 'internet_25', 'internet_50', 'internet_full', 'internet_medium');

-- Network stats
INSERT INTO network_stats (id, difficulty, hashrate)
VALUES ('current', 1000, 0)
ON CONFLICT (id) DO NOTHING;

-- Genesis block (only if players exist)
INSERT INTO blocks (height, hash, previous_hash, miner_id, difficulty, network_hashrate)
SELECT
  0,
  '0000000000000000000000000000000000000000000000000000000000000000',
  '0000000000000000000000000000000000000000000000000000000000000000',
  (SELECT id FROM players LIMIT 1),
  1000,
  0
WHERE EXISTS (SELECT 1 FROM players LIMIT 1)
  AND NOT EXISTS (SELECT 1 FROM blocks WHERE height = 0);

-- Crypto packages (RON prices)
-- Base rate: 1 RON = 5000 crypto | Sell: 100,000 crypto = 1 RON
INSERT INTO crypto_packages (id, name, description, crypto_amount, ron_price, bonus_percent, tier, is_featured)
VALUES
  ('crypto_starter', 'crypto_starter', 'crypto_starter', 5000, 1.0, 0, 'basic', false),
  ('crypto_basic', 'crypto_basic', 'crypto_basic', 12500, 2.5, 20, 'basic', false),
  ('crypto_standard', 'crypto_standard', 'crypto_standard', 25000, 5.0, 25, 'standard', true),
  ('crypto_plus', 'crypto_plus', 'crypto_plus', 50000, 10.0, 35, 'standard', false),
  ('crypto_premium', 'crypto_premium', 'crypto_premium', 125000, 25.0, 50, 'premium', true),
  ('crypto_elite', 'crypto_elite', 'crypto_elite', 250000, 50.0, 75, 'premium', false),
  ('crypto_whale', 'crypto_whale', 'crypto_whale', 500000, 100.0, 100, 'elite', true)
ON CONFLICT (id) DO UPDATE SET
  crypto_amount = EXCLUDED.crypto_amount,
  ron_price = EXCLUDED.ron_price,
  bonus_percent = EXCLUDED.bonus_percent,
  tier = EXCLUDED.tier,
  is_featured = EXCLUDED.is_featured;
