-- =====================================================
-- BLOCK LORDS - Initial Data
-- =====================================================
-- Safe to run multiple times (uses ON CONFLICT)
-- Translations handled in frontend: t(`data.rigs.${id}.name`)

-- Rigs (internet consumes more than energy to incentivize upgrades)
INSERT INTO rigs (id, name, description, hashrate, power_consumption, internet_consumption, repair_cost, tier, base_price)
VALUES
  ('basic_miner', 'basic_miner', 'basic_miner', 100, 2.5, 3.5, 80, 'basic', 0),
  ('home_miner', 'home_miner', 'home_miner', 250, 5.0, 7.0, 500, 'basic', 600),
  ('gpu_rig', 'gpu_rig', 'gpu_rig', 500, 8.0, 12.0, 1200, 'standard', 1800),
  ('asic_s9', 'asic_s9', 'asic_s9', 1000, 12.0, 18.0, 2500, 'standard', 5000),
  ('asic_s19', 'asic_s19', 'asic_s19', 2500, 18.0, 28.0, 5000, 'advanced', 15000),
  ('mining_farm_small', 'mining_farm_small', 'mining_farm_small', 5000, 28.0, 42.0, 12000, 'advanced', 45000),
  ('mining_farm_large', 'mining_farm_large', 'mining_farm_large', 10000, 40.0, 60.0, 25000, 'elite', 120000),
  ('quantum_miner', 'quantum_miner', 'quantum_miner', 25000, 55.0, 85.0, 50000, 'elite', 350000)
ON CONFLICT (id) DO UPDATE SET
  hashrate = EXCLUDED.hashrate,
  power_consumption = EXCLUDED.power_consumption,
  internet_consumption = EXCLUDED.internet_consumption,
  repair_cost = EXCLUDED.repair_cost,
  tier = EXCLUDED.tier,
  base_price = EXCLUDED.base_price;

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

-- Prepaid cards - Energy
INSERT INTO prepaid_cards (id, name, description, card_type, amount, base_price, tier, currency)
VALUES
  ('energy_10', 'energy_10', 'energy_10', 'energy', 10, 150, 'basic', 'gamecoin'),
  ('energy_25', 'energy_25', 'energy_25', 'energy', 25, 350, 'basic', 'gamecoin'),
  ('energy_50', 'energy_50', 'energy_50', 'energy', 50, 650, 'standard', 'gamecoin'),
  ('energy_full', 'energy_full', 'energy_full', 'energy', 100, 1200, 'standard', 'gamecoin'),
  ('energy_ultra', 'energy_ultra', 'energy_ultra', 'energy', 150, 5, 'elite', 'crypto')
ON CONFLICT (id) DO UPDATE SET
  card_type = EXCLUDED.card_type,
  amount = EXCLUDED.amount,
  base_price = EXCLUDED.base_price,
  tier = EXCLUDED.tier,
  currency = EXCLUDED.currency;

-- Prepaid cards - Internet
INSERT INTO prepaid_cards (id, name, description, card_type, amount, base_price, tier, currency)
VALUES
  ('internet_10', 'internet_10', 'internet_10', 'internet', 10, 120, 'basic', 'gamecoin'),
  ('internet_25', 'internet_25', 'internet_25', 'internet', 25, 280, 'basic', 'gamecoin'),
  ('internet_50', 'internet_50', 'internet_50', 'internet', 50, 520, 'standard', 'gamecoin'),
  ('internet_full', 'internet_full', 'internet_full', 'internet', 100, 950, 'standard', 'gamecoin'),
  ('internet_ultra', 'internet_ultra', 'internet_ultra', 'internet', 150, 5, 'elite', 'crypto')
ON CONFLICT (id) DO UPDATE SET
  card_type = EXCLUDED.card_type,
  amount = EXCLUDED.amount,
  base_price = EXCLUDED.base_price,
  tier = EXCLUDED.tier,
  currency = EXCLUDED.currency;

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
