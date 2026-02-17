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

-- =====================================================
-- Cooling mod slots por tier
-- =====================================================
UPDATE cooling_items SET max_mod_slots = 1 WHERE tier = 'basic';
UPDATE cooling_items SET max_mod_slots = 2 WHERE tier = 'standard';
UPDATE cooling_items SET max_mod_slots = 3 WHERE tier = 'advanced';
UPDATE cooling_items SET max_mod_slots = 4 WHERE tier = 'elite';

-- =====================================================
-- Cooling Components (15 componentes RPG-style)
-- Rangos: min/max para cada stat. Al instalar, se sortea un valor aleatorio.
-- cooling_power: % cambio en potencia (positivo = mejor)
-- energy_cost: % cambio en consumo (positivo = más caro = peor)
-- durability: % cambio en velocidad de desgaste (positivo = más lento = mejor)
-- =====================================================
INSERT INTO cooling_components (id, name, description, tier, base_price, cooling_power_min, cooling_power_max, energy_cost_min, energy_cost_max, durability_min, durability_max)
VALUES
  -- Performance: mejoran cooling_power
  ('thermal_paste', 'thermal_paste', 'thermal_paste_desc', 'basic', 100, 5, 20, 0, 0, 0, 0),
  ('copper_heat_pipes', 'copper_heat_pipes', 'copper_heat_pipes_desc', 'standard', 350, 10, 30, 0, 15, 0, 0),
  ('liquid_metal_compound', 'liquid_metal_compound', 'liquid_metal_compound_desc', 'advanced', 1200, 20, 45, 0, 0, -30, -10),
  ('cryo_catalyst', 'cryo_catalyst', 'cryo_catalyst_desc', 'elite', 4500, 30, 70, 10, 35, -40, -15),
  -- Efficiency: reducen energy_cost
  ('wire_harness', 'wire_harness', 'wire_harness_desc', 'basic', 80, 0, 0, -20, -5, 0, 0),
  ('voltage_regulator', 'voltage_regulator', 'voltage_regulator_desc', 'standard', 400, -5, 5, -30, -10, 0, 0),
  ('silent_bearings', 'silent_bearings', 'silent_bearings_desc', 'advanced', 1000, -10, 5, -40, -15, 0, 0),
  ('power_optimizer', 'power_optimizer', 'power_optimizer_desc', 'elite', 3500, 0, 0, -50, -25, -5, 10),
  -- Durability: mejoran durabilidad
  ('rubber_gaskets', 'rubber_gaskets', 'rubber_gaskets_desc', 'basic', 80, 0, 0, 0, 0, 5, 25),
  ('insulation_wrap', 'insulation_wrap', 'insulation_wrap_desc', 'standard', 300, -15, -5, 0, 0, 10, 35),
  ('ceramic_coating', 'ceramic_coating', 'ceramic_coating_desc', 'advanced', 900, 0, 0, 5, 15, 20, 45),
  ('diamond_shell', 'diamond_shell', 'diamond_shell_desc', 'elite', 5000, -5, 10, 5, 20, 30, 60),
  -- Hybrid / Gamble: múltiples stats, rangos amplios
  ('nano_coolant_fluid', 'nano_coolant_fluid', 'nano_coolant_fluid_desc', 'advanced', 1500, 5, 30, -5, 20, 5, 20),
  ('overclocked_motor', 'overclocked_motor', 'overclocked_motor_desc', 'elite', 6000, 25, 55, 15, 40, -40, -20),
  ('quantum_heatsink', 'quantum_heatsink', 'quantum_heatsink_desc', 'elite', 8000, -15, 60, -25, 30, -30, 40)
ON CONFLICT (id) DO UPDATE SET
  tier = EXCLUDED.tier,
  base_price = EXCLUDED.base_price,
  cooling_power_min = EXCLUDED.cooling_power_min,
  cooling_power_max = EXCLUDED.cooling_power_max,
  energy_cost_min = EXCLUDED.energy_cost_min,
  energy_cost_max = EXCLUDED.energy_cost_max,
  durability_min = EXCLUDED.durability_min,
  durability_max = EXCLUDED.durability_max;

-- =====================================================
-- Materials (4 tipos de materiales dropeables al minar)
-- =====================================================
INSERT INTO materials (id, name, rarity, drop_chance, icon) VALUES
  ('copper_fragment', 'copper_fragment', 'common', 0.35, '🔩'),
  ('silicon_chip', 'silicon_chip', 'uncommon', 0.18, '💾'),
  ('carbon_fiber', 'carbon_fiber', 'rare', 0.07, '🧬'),
  ('quantum_shard', 'quantum_shard', 'epic', 0.02, '💠')
ON CONFLICT (id) DO UPDATE SET
  rarity = EXCLUDED.rarity,
  drop_chance = EXCLUDED.drop_chance,
  icon = EXCLUDED.icon;

-- =====================================================
-- Forge Recipes
-- =====================================================

-- A) Tier Kits (aceleran progresión XP de slots)
INSERT INTO forge_recipes (id, name, category, result_type, result_value, tier, icon) VALUES
  ('tier_kit_standard', 'tier_kit_standard', 'tier_kit', 'xp_grant', 200, 'standard', '📦'),
  ('tier_kit_advanced', 'tier_kit_advanced', 'tier_kit', 'xp_grant', 500, 'advanced', '📦'),
  ('tier_kit_elite', 'tier_kit_elite', 'tier_kit', 'xp_grant', 1500, 'elite', '📦')
ON CONFLICT (id) DO UPDATE SET
  result_value = EXCLUDED.result_value,
  tier = EXCLUDED.tier;

-- B) Rig Enhancements (mejoras permanentes al rig)
INSERT INTO forge_recipes (id, name, category, result_type, result_value, tier, icon) VALUES
  ('hashrate_booster', 'hashrate_booster', 'rig_enhancement', 'rig_boost', 3, 'basic', '⚡'),
  ('efficiency_module', 'efficiency_module', 'rig_enhancement', 'rig_boost', 5, 'standard', '🔋'),
  ('thermal_paste_pro', 'thermal_paste_pro', 'rig_enhancement', 'rig_boost', 5, 'standard', '🌡️')
ON CONFLICT (id) DO UPDATE SET
  result_value = EXCLUDED.result_value,
  tier = EXCLUDED.tier;

-- C) Cooling Components (los 15 del market, crafteables)
INSERT INTO forge_recipes (id, name, category, result_type, result_id, tier, icon) VALUES
  -- Basic
  ('craft_thermal_paste', 'craft_thermal_paste', 'cooling', 'cooling_component', 'thermal_paste', 'basic', '🧪'),
  ('craft_wire_harness', 'craft_wire_harness', 'cooling', 'cooling_component', 'wire_harness', 'basic', '🔌'),
  ('craft_rubber_gaskets', 'craft_rubber_gaskets', 'cooling', 'cooling_component', 'rubber_gaskets', 'basic', '⭕'),
  -- Standard
  ('craft_copper_heat_pipes', 'craft_copper_heat_pipes', 'cooling', 'cooling_component', 'copper_heat_pipes', 'standard', '🔧'),
  ('craft_voltage_regulator', 'craft_voltage_regulator', 'cooling', 'cooling_component', 'voltage_regulator', 'standard', '🔌'),
  ('craft_insulation_wrap', 'craft_insulation_wrap', 'cooling', 'cooling_component', 'insulation_wrap', 'standard', '🧱'),
  -- Advanced
  ('craft_liquid_metal_compound', 'craft_liquid_metal_compound', 'cooling', 'cooling_component', 'liquid_metal_compound', 'advanced', '💧'),
  ('craft_silent_bearings', 'craft_silent_bearings', 'cooling', 'cooling_component', 'silent_bearings', 'advanced', '⚙️'),
  ('craft_ceramic_coating', 'craft_ceramic_coating', 'cooling', 'cooling_component', 'ceramic_coating', 'advanced', '🛡️'),
  ('craft_nano_coolant_fluid', 'craft_nano_coolant_fluid', 'cooling', 'cooling_component', 'nano_coolant_fluid', 'advanced', '🧊'),
  -- Elite
  ('craft_cryo_catalyst', 'craft_cryo_catalyst', 'cooling', 'cooling_component', 'cryo_catalyst', 'elite', '❄️'),
  ('craft_power_optimizer', 'craft_power_optimizer', 'cooling', 'cooling_component', 'power_optimizer', 'elite', '⚡'),
  ('craft_diamond_shell', 'craft_diamond_shell', 'cooling', 'cooling_component', 'diamond_shell', 'elite', '💎'),
  ('craft_overclocked_motor', 'craft_overclocked_motor', 'cooling', 'cooling_component', 'overclocked_motor', 'elite', '🔥'),
  ('craft_quantum_heatsink', 'craft_quantum_heatsink', 'cooling', 'cooling_component', 'quantum_heatsink', 'elite', '💠')
ON CONFLICT (id) DO UPDATE SET
  result_id = EXCLUDED.result_id,
  tier = EXCLUDED.tier;

-- D) Utility Items
INSERT INTO forge_recipes (id, name, category, result_type, result_value, tier, icon) VALUES
  ('durability_shield', 'durability_shield', 'utility', 'slot_buff', 1, 'advanced', '🛡️'),
  ('slot_protector', 'slot_protector', 'utility', 'slot_buff', 0, 'standard', '🔒')
ON CONFLICT (id) DO UPDATE SET
  result_value = EXCLUDED.result_value,
  tier = EXCLUDED.tier;

-- =====================================================
-- Forge Recipe Ingredients
-- =====================================================

-- Limpiar ingredientes existentes para re-insertar
DELETE FROM forge_recipe_ingredients WHERE recipe_id IN (
  SELECT id FROM forge_recipes
);

INSERT INTO forge_recipe_ingredients (recipe_id, material_id, quantity) VALUES
  -- Tier Kits
  ('tier_kit_standard', 'copper_fragment', 5),
  ('tier_kit_standard', 'silicon_chip', 2),
  ('tier_kit_advanced', 'silicon_chip', 3),
  ('tier_kit_advanced', 'carbon_fiber', 2),
  ('tier_kit_elite', 'carbon_fiber', 2),
  ('tier_kit_elite', 'quantum_shard', 1),
  -- Rig Enhancements
  ('hashrate_booster', 'copper_fragment', 4),
  ('hashrate_booster', 'silicon_chip', 1),
  ('efficiency_module', 'silicon_chip', 3),
  ('efficiency_module', 'carbon_fiber', 1),
  ('thermal_paste_pro', 'copper_fragment', 2),
  ('thermal_paste_pro', 'silicon_chip', 2),
  -- Cooling Components - Basic (3 Copper each)
  ('craft_thermal_paste', 'copper_fragment', 3),
  ('craft_wire_harness', 'copper_fragment', 3),
  ('craft_rubber_gaskets', 'copper_fragment', 3),
  -- Cooling Components - Standard
  ('craft_copper_heat_pipes', 'copper_fragment', 5),
  ('craft_copper_heat_pipes', 'silicon_chip', 2),
  ('craft_voltage_regulator', 'copper_fragment', 4),
  ('craft_voltage_regulator', 'silicon_chip', 3),
  ('craft_insulation_wrap', 'copper_fragment', 4),
  ('craft_insulation_wrap', 'silicon_chip', 2),
  -- Cooling Components - Advanced
  ('craft_liquid_metal_compound', 'silicon_chip', 3),
  ('craft_liquid_metal_compound', 'carbon_fiber', 2),
  ('craft_silent_bearings', 'silicon_chip', 3),
  ('craft_silent_bearings', 'carbon_fiber', 2),
  ('craft_ceramic_coating', 'silicon_chip', 2),
  ('craft_ceramic_coating', 'carbon_fiber', 3),
  ('craft_nano_coolant_fluid', 'silicon_chip', 4),
  ('craft_nano_coolant_fluid', 'carbon_fiber', 2),
  -- Cooling Components - Elite
  ('craft_cryo_catalyst', 'carbon_fiber', 2),
  ('craft_cryo_catalyst', 'quantum_shard', 1),
  ('craft_power_optimizer', 'carbon_fiber', 2),
  ('craft_power_optimizer', 'quantum_shard', 1),
  ('craft_diamond_shell', 'carbon_fiber', 3),
  ('craft_diamond_shell', 'quantum_shard', 1),
  ('craft_overclocked_motor', 'carbon_fiber', 2),
  ('craft_overclocked_motor', 'quantum_shard', 2),
  ('craft_quantum_heatsink', 'carbon_fiber', 3),
  ('craft_quantum_heatsink', 'quantum_shard', 3),
  -- Utility
  ('durability_shield', 'carbon_fiber', 1),
  ('durability_shield', 'quantum_shard', 1),
  ('slot_protector', 'copper_fragment', 5),
  ('slot_protector', 'silicon_chip', 3);
