-- =====================================================
-- BLOCK LORDS - ALL MIGRATIONS CONSOLIDATED
-- =====================================================
-- Este archivo contiene TODAS las migraciones del juego
-- Ejecutar en Supabase SQL Editor para configurar la base de datos
-- =====================================================

-- Habilitar extensiones necesarias
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =====================================================
-- 1. TABLAS PRINCIPALES
-- =====================================================

CREATE TABLE IF NOT EXISTS players (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT UNIQUE NOT NULL,
  username TEXT UNIQUE NOT NULL CHECK (length(username) >= 3 AND length(username) <= 20),
  gamecoin_balance DECIMAL(18, 4) DEFAULT 1000 NOT NULL CHECK (gamecoin_balance >= 0),
  crypto_balance DECIMAL(18, 8) DEFAULT 0 NOT NULL CHECK (crypto_balance >= 0),
  energy DECIMAL(5, 2) DEFAULT 300 NOT NULL,
  internet DECIMAL(5, 2) DEFAULT 300 NOT NULL,
  max_energy INTEGER DEFAULT 300,
  max_internet INTEGER DEFAULT 300,
  reputation_score DECIMAL(5, 2) DEFAULT 50 NOT NULL CHECK (reputation_score >= 0 AND reputation_score <= 100),
  region TEXT DEFAULT 'global',
  ron_wallet TEXT DEFAULT NULL,
  ron_balance DECIMAL(18, 8) DEFAULT 0,
  is_online BOOLEAN DEFAULT false,
  last_seen TIMESTAMPTZ DEFAULT NOW(),
  cooling_level DECIMAL(5, 2) DEFAULT 0 CHECK (cooling_level >= 0 AND cooling_level <= 100),
  rig_slots INTEGER DEFAULT 1 NOT NULL CHECK (rig_slots >= 1 AND rig_slots <= 20),
  blocks_mined INTEGER DEFAULT 0,
  total_crypto_earned DECIMAL(18, 8) DEFAULT 0,
  premium_until TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Constraints de energia/internet (premium puede tener hasta 1000)
ALTER TABLE players DROP CONSTRAINT IF EXISTS players_energy_check;
ALTER TABLE players DROP CONSTRAINT IF EXISTS players_internet_check;
ALTER TABLE players ADD CONSTRAINT players_energy_check CHECK (energy >= 0 AND energy <= 1000);
ALTER TABLE players ADD CONSTRAINT players_internet_check CHECK (internet >= 0 AND internet <= 1000);

CREATE TABLE IF NOT EXISTS rigs (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  hashrate INTEGER NOT NULL CHECK (hashrate > 0),
  power_consumption DECIMAL(5, 2) NOT NULL CHECK (power_consumption > 0),
  internet_consumption DECIMAL(5, 2) NOT NULL CHECK (internet_consumption > 0),
  repair_cost DECIMAL(10, 2) NOT NULL CHECK (repair_cost >= 0),
  tier TEXT NOT NULL CHECK (tier IN ('basic', 'standard', 'advanced', 'elite')),
  base_price DECIMAL(10, 2) NOT NULL CHECK (base_price >= 0),
  currency TEXT NOT NULL DEFAULT 'gamecoin' CHECK (currency IN ('gamecoin', 'crypto', 'ron')),
  max_upgrade_level INTEGER DEFAULT 3,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Add currency column for existing databases
ALTER TABLE rigs ADD COLUMN IF NOT EXISTS currency TEXT NOT NULL DEFAULT 'gamecoin';
DO $$ BEGIN
  ALTER TABLE rigs ADD CONSTRAINT rigs_currency_check CHECK (currency IN ('gamecoin', 'crypto', 'ron'));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS player_rigs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  rig_id TEXT NOT NULL REFERENCES rigs(id),
  is_active BOOLEAN DEFAULT false,
  condition DECIMAL(5, 2) DEFAULT 100 CHECK (condition >= 0 AND condition <= 100),
  temperature DECIMAL(5, 2) DEFAULT 25 CHECK (temperature >= 0 AND temperature <= 100),
  hashrate_level INTEGER DEFAULT 1,
  efficiency_level INTEGER DEFAULT 1,
  thermal_level INTEGER DEFAULT 1,
  acquired_at TIMESTAMPTZ DEFAULT NOW(),
  activated_at TIMESTAMPTZ,
  deactivated_at TIMESTAMPTZ,
  UNIQUE(player_id, rig_id)
);

-- Add columns if they don't exist (for existing databases)
ALTER TABLE player_rigs ADD COLUMN IF NOT EXISTS activated_at TIMESTAMPTZ;
ALTER TABLE player_rigs ADD COLUMN IF NOT EXISTS deactivated_at TIMESTAMPTZ;
ALTER TABLE player_rigs ADD COLUMN IF NOT EXISTS last_modified_at TIMESTAMPTZ;

ALTER TABLE player_rigs DROP CONSTRAINT IF EXISTS hashrate_level_valid;
ALTER TABLE player_rigs DROP CONSTRAINT IF EXISTS efficiency_level_valid;
ALTER TABLE player_rigs DROP CONSTRAINT IF EXISTS thermal_level_valid;
ALTER TABLE player_rigs ADD CONSTRAINT hashrate_level_valid CHECK (hashrate_level >= 1 AND hashrate_level <= 5);
ALTER TABLE player_rigs ADD CONSTRAINT efficiency_level_valid CHECK (efficiency_level >= 1 AND efficiency_level <= 5);
ALTER TABLE player_rigs ADD CONSTRAINT thermal_level_valid CHECK (thermal_level >= 1 AND thermal_level <= 5);

CREATE TABLE IF NOT EXISTS blocks (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  height INTEGER UNIQUE NOT NULL,
  hash TEXT UNIQUE NOT NULL,
  previous_hash TEXT NOT NULL,
  miner_id UUID NOT NULL REFERENCES players(id),
  difficulty DECIMAL(15, 2) NOT NULL,
  network_hashrate DECIMAL(15, 2) NOT NULL,
  reward DECIMAL(18, 8),
  is_premium BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Add columns if they don't exist (for existing databases)
ALTER TABLE blocks ADD COLUMN IF NOT EXISTS reward DECIMAL(18, 8);
ALTER TABLE blocks ADD COLUMN IF NOT EXISTS is_premium BOOLEAN DEFAULT false;

CREATE TABLE IF NOT EXISTS pending_blocks (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  block_id UUID REFERENCES blocks(id) ON DELETE CASCADE,  -- Nullable for pity blocks
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  reward DECIMAL(18, 8) NOT NULL,
  claimed BOOLEAN DEFAULT FALSE,
  claimed_at TIMESTAMPTZ,
  is_premium BOOLEAN DEFAULT false,
  is_pity BOOLEAN DEFAULT false,  -- TRUE for pity timer blocks (no real block_id)
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Pity Timer System: column for accumulating mining time bonus
ALTER TABLE players ADD COLUMN IF NOT EXISTS mining_bonus_accumulated DECIMAL(18, 8) DEFAULT 0;

-- Pity blocks column (for existing databases)
ALTER TABLE pending_blocks ADD COLUMN IF NOT EXISTS is_pity BOOLEAN DEFAULT false;

-- Make block_id nullable for pity blocks (for existing databases)
ALTER TABLE pending_blocks ALTER COLUMN block_id DROP NOT NULL;

-- Index for pity blocks queries
CREATE INDEX IF NOT EXISTS idx_pending_blocks_is_pity ON pending_blocks(is_pity) WHERE is_pity = true;

CREATE TABLE IF NOT EXISTS market_orders (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  type TEXT NOT NULL CHECK (type IN ('buy', 'sell')),
  item_type TEXT NOT NULL CHECK (item_type IN ('crypto', 'rig', 'energy', 'internet', 'cooling')),
  item_id TEXT,
  quantity DECIMAL(18, 8) NOT NULL CHECK (quantity > 0),
  price_per_unit DECIMAL(18, 8) NOT NULL CHECK (price_per_unit > 0),
  remaining_quantity DECIMAL(18, 8) NOT NULL CHECK (remaining_quantity >= 0),
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'filled', 'cancelled', 'partially_filled')),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS trades (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  buyer_id UUID NOT NULL REFERENCES players(id),
  seller_id UUID NOT NULL REFERENCES players(id),
  item_type TEXT NOT NULL,
  item_id TEXT,
  quantity DECIMAL(18, 8) NOT NULL,
  price_per_unit DECIMAL(18, 8) NOT NULL,
  total_value DECIMAL(18, 8) NOT NULL,
  taker_order_id UUID REFERENCES market_orders(id),
  maker_order_id UUID REFERENCES market_orders(id),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Actualizar constraint de currency para transactions
DO $$
BEGIN
  ALTER TABLE transactions DROP CONSTRAINT IF EXISTS transactions_currency_check;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS transactions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  amount DECIMAL(18, 8) NOT NULL,
  currency TEXT NOT NULL CHECK (currency IN ('gamecoin', 'crypto', 'ron', 'energy', 'internet')),
  description TEXT,
  metadata JSONB DEFAULT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Add metadata column for existing databases
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS metadata JSONB DEFAULT NULL;

CREATE TABLE IF NOT EXISTS reputation_events (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  delta DECIMAL(5, 2) NOT NULL,
  reason TEXT NOT NULL,
  old_score DECIMAL(5, 2) NOT NULL,
  new_score DECIMAL(5, 2) NOT NULL,
  details JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS badges (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  icon TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS player_badges (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  badge_id TEXT NOT NULL REFERENCES badges(id),
  awarded_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(player_id, badge_id)
);

CREATE TABLE IF NOT EXISTS player_events (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  data JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS player_penalties (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  reason TEXT NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS chat_messages (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  channel TEXT NOT NULL,
  message TEXT NOT NULL CHECK (length(message) <= 500),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS network_stats (
  id TEXT PRIMARY KEY DEFAULT 'current',
  difficulty DECIMAL(15, 2) DEFAULT 1000,
  hashrate DECIMAL(15, 2) DEFAULT 0,
  active_miners INTEGER DEFAULT 0,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- =====================================================
-- 2. COOLING SYSTEM
-- =====================================================

CREATE TABLE IF NOT EXISTS cooling_items (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  cooling_power DECIMAL(5, 2) NOT NULL CHECK (cooling_power > 0),
  energy_cost DECIMAL(5, 2) NOT NULL DEFAULT 0 CHECK (energy_cost >= 0),
  base_price DECIMAL(10, 2) NOT NULL CHECK (base_price >= 0),
  tier TEXT NOT NULL CHECK (tier IN ('basic', 'standard', 'advanced', 'elite')),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS player_cooling (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  cooling_item_id TEXT NOT NULL REFERENCES cooling_items(id),
  installed_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(player_id, cooling_item_id)
);

CREATE TABLE IF NOT EXISTS player_inventory (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  item_type TEXT NOT NULL,
  item_id TEXT NOT NULL,
  quantity INTEGER DEFAULT 1,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(player_id, item_type, item_id)
);

-- =====================================================
-- 3. PREPAID CARDS
-- =====================================================

CREATE TABLE IF NOT EXISTS prepaid_cards (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  card_type TEXT NOT NULL CHECK (card_type IN ('energy', 'internet')),
  amount DECIMAL(5, 2) NOT NULL CHECK (amount > 0),
  base_price DECIMAL(10, 2) NOT NULL CHECK (base_price >= 0),
  tier TEXT NOT NULL CHECK (tier IN ('basic', 'standard', 'advanced', 'elite')),
  currency TEXT NOT NULL DEFAULT 'gamecoin' CHECK (currency IN ('gamecoin', 'crypto')),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS player_cards (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  card_id TEXT NOT NULL REFERENCES prepaid_cards(id),
  code TEXT NOT NULL UNIQUE,
  is_redeemed BOOLEAN DEFAULT false,
  purchased_at TIMESTAMPTZ DEFAULT NOW(),
  redeemed_at TIMESTAMPTZ
);

-- =====================================================
-- 4. CRYPTO PACKAGES
-- =====================================================

CREATE TABLE IF NOT EXISTS crypto_packages (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  crypto_amount DECIMAL(10, 2) NOT NULL CHECK (crypto_amount > 0),
  ron_price DECIMAL(10, 4) NOT NULL CHECK (ron_price > 0),
  bonus_percent INTEGER DEFAULT 0 CHECK (bonus_percent >= 0),
  tier TEXT NOT NULL CHECK (tier IN ('basic', 'standard', 'premium', 'elite')),
  is_featured BOOLEAN DEFAULT FALSE,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS crypto_purchases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  package_id TEXT NOT NULL REFERENCES crypto_packages(id),
  crypto_amount DECIMAL(10, 2) NOT NULL,
  ron_paid DECIMAL(10, 4) NOT NULL,
  tx_hash TEXT,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'failed', 'refunded')),
  purchased_at TIMESTAMPTZ DEFAULT NOW(),
  completed_at TIMESTAMPTZ
);

-- =====================================================
-- 5. STREAK SYSTEM
-- =====================================================

CREATE TABLE IF NOT EXISTS player_streaks (
  player_id UUID PRIMARY KEY REFERENCES players(id) ON DELETE CASCADE,
  current_streak INTEGER DEFAULT 0,
  longest_streak INTEGER DEFAULT 0,
  last_claim_date DATE,
  next_claim_available TIMESTAMPTZ,
  streak_expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS streak_rewards (
  id TEXT PRIMARY KEY,
  day_number INTEGER UNIQUE NOT NULL,
  gamecoin_reward DECIMAL(10, 2) DEFAULT 0,
  crypto_reward DECIMAL(10, 4) DEFAULT 0,
  item_type TEXT,
  item_id TEXT,
  description TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS streak_claims (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  day_number INTEGER NOT NULL,
  gamecoin_earned DECIMAL(10, 2) DEFAULT 0,
  crypto_earned DECIMAL(10, 4) DEFAULT 0,
  item_type TEXT,
  item_id TEXT,
  claimed_at TIMESTAMPTZ DEFAULT NOW()
);

-- =====================================================
-- 6. MISSIONS SYSTEM
-- =====================================================

CREATE TABLE IF NOT EXISTS missions (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT NOT NULL,
  mission_type TEXT NOT NULL,
  target_value NUMERIC NOT NULL,
  reward_type TEXT NOT NULL,
  reward_amount NUMERIC NOT NULL,
  difficulty TEXT NOT NULL CHECK (difficulty IN ('easy', 'medium', 'hard', 'epic')),
  icon TEXT DEFAULT '🎯',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS player_missions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  mission_id TEXT NOT NULL REFERENCES missions(id),
  progress NUMERIC DEFAULT 0,
  is_completed BOOLEAN DEFAULT false,
  is_claimed BOOLEAN DEFAULT false,
  assigned_date DATE NOT NULL DEFAULT CURRENT_DATE,
  completed_at TIMESTAMPTZ,
  claimed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(player_id, mission_id, assigned_date)
);

CREATE TABLE IF NOT EXISTS player_online_tracking (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  tracking_date DATE NOT NULL DEFAULT CURRENT_DATE,
  minutes_online INTEGER DEFAULT 0,
  last_heartbeat TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(player_id, tracking_date)
);

-- =====================================================
-- 7. RIG SLOTS UPGRADES
-- =====================================================

DROP TABLE IF EXISTS rig_slot_upgrades;
CREATE TABLE rig_slot_upgrades (
  slot_number INTEGER PRIMARY KEY CHECK (slot_number >= 2 AND slot_number <= 20),
  price DECIMAL(18, 8) NOT NULL CHECK (price > 0),
  currency TEXT NOT NULL DEFAULT 'gamecoin' CHECK (currency IN ('gamecoin', 'crypto', 'ron')),
  name TEXT NOT NULL,
  description TEXT
);

-- Slot prices: #2-#3 Crypto, #4+ RON (2 RON fixed)
INSERT INTO rig_slot_upgrades (slot_number, price, currency, name, description) VALUES
  (2, 10000, 'crypto', 'Slot #2', 'slot2'),
  (3, 10000, 'crypto', 'Slot #3', 'slot3'),
  (4, 2, 'ron', 'Slot #4', 'slot4'),
  (5, 2, 'ron', 'Slot #5', 'slot5'),
  (6, 2, 'ron', 'Slot #6', 'expansion'),
  (7, 2, 'ron', 'Slot #7', 'expansion'),
  (8, 2, 'ron', 'Slot #8', 'medium'),
  (9, 2, 'ron', 'Slot #9', 'medium'),
  (10, 2, 'ron', 'Slot #10', 'large'),
  (11, 2, 'ron', 'Slot #11', 'smallFarm'),
  (12, 2, 'ron', 'Slot #12', 'smallFarm'),
  (13, 2, 'ron', 'Slot #13', 'mediumFarm'),
  (14, 2, 'ron', 'Slot #14', 'mediumFarm'),
  (15, 2, 'ron', 'Slot #15', 'largeFarm'),
  (16, 2, 'ron', 'Slot #16', 'largeFarm'),
  (17, 2, 'ron', 'Slot #17', 'megaFarm'),
  (18, 2, 'ron', 'Slot #18', 'megaFarm'),
  (19, 2, 'ron', 'Slot #19', 'industrial'),
  (20, 2, 'ron', 'Slot #20', 'maxPower')
ON CONFLICT (slot_number) DO UPDATE SET
  price = EXCLUDED.price,
  currency = EXCLUDED.currency;

-- =====================================================
-- 8. BOOSTS SYSTEM
-- =====================================================

CREATE TABLE IF NOT EXISTS boost_items (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  boost_type TEXT NOT NULL,
  boost_value DECIMAL(5, 2) NOT NULL,
  duration_seconds INTEGER NOT NULL,
  base_price DECIMAL(10, 2) NOT NULL,
  tier TEXT NOT NULL CHECK (tier IN ('basic', 'standard', 'advanced', 'elite')),
  is_stackable BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS player_boosts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  boost_item_id TEXT NOT NULL REFERENCES boost_items(id),
  quantity INTEGER DEFAULT 1,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(player_id, boost_item_id)
);

CREATE TABLE IF NOT EXISTS rig_boosts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  player_rig_id UUID NOT NULL REFERENCES player_rigs(id) ON DELETE CASCADE,
  boost_item_id TEXT NOT NULL REFERENCES boost_items(id),
  activated_at TIMESTAMPTZ DEFAULT NOW(),
  remaining_seconds INTEGER NOT NULL CHECK (remaining_seconds >= 0),
  stack_count INTEGER DEFAULT 1 CHECK (stack_count >= 1),
  UNIQUE(player_rig_id, boost_item_id)
);

-- =====================================================
-- 9. UPGRADE COSTS
-- =====================================================

CREATE TABLE IF NOT EXISTS upgrade_costs (
  level INTEGER PRIMARY KEY,
  crypto_cost NUMERIC NOT NULL,
  hashrate_bonus NUMERIC NOT NULL,
  efficiency_bonus NUMERIC NOT NULL,
  thermal_bonus NUMERIC NOT NULL
);

INSERT INTO upgrade_costs (level, crypto_cost, hashrate_bonus, efficiency_bonus, thermal_bonus)
VALUES
  (2, 100, 15, 10, 10),
  (3, 300, 35, 20, 20),
  (4, 700, 45, 35, 30),
  (5, 1500, 50, 50, 50)
ON CONFLICT (level) DO UPDATE SET
  hashrate_bonus = EXCLUDED.hashrate_bonus,
  efficiency_bonus = EXCLUDED.efficiency_bonus,
  thermal_bonus = EXCLUDED.thermal_bonus;

-- Fix upgrade costs to cap bonuses at 50%
UPDATE upgrade_costs SET hashrate_bonus = 50 WHERE hashrate_bonus > 50;
UPDATE upgrade_costs SET efficiency_bonus = 50 WHERE efficiency_bonus > 50;
UPDATE upgrade_costs SET thermal_bonus = 50 WHERE thermal_bonus > 50;

-- =====================================================
-- 9b. PLAYER SLOTS (Durabilidad de slots)
-- =====================================================

CREATE TABLE IF NOT EXISTS player_slots (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  slot_number INTEGER NOT NULL CHECK (slot_number >= 1 AND slot_number <= 20),
  max_uses INTEGER NOT NULL CHECK (max_uses IN (2, 3)),
  uses_remaining INTEGER NOT NULL CHECK (uses_remaining >= 0),
  player_rig_id UUID REFERENCES player_rigs(id) ON DELETE SET NULL,
  is_destroyed BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(player_id, slot_number)
);

CREATE INDEX IF NOT EXISTS idx_player_slots_player ON player_slots(player_id);

-- Migración: Poblar player_slots para jugadores existentes
DO $$
DECLARE
  v_player RECORD;
  v_rig RECORD;
  v_slot_num INTEGER;
  v_is_premium BOOLEAN;
  v_max_uses INTEGER;
BEGIN
  -- Solo ejecutar si la tabla está vacía (primera vez)
  IF EXISTS (SELECT 1 FROM player_slots LIMIT 1) THEN
    RETURN;
  END IF;

  FOR v_player IN SELECT * FROM players LOOP
    v_is_premium := COALESCE(v_player.premium_until > NOW(), false);
    v_max_uses := CASE WHEN v_is_premium THEN 3 ELSE 2 END;
    v_slot_num := 1;

    -- Asignar slots a rigs instalados
    FOR v_rig IN
      SELECT id FROM player_rigs
      WHERE player_id = v_player.id
      ORDER BY acquired_at ASC
    LOOP
      INSERT INTO player_slots (player_id, slot_number, max_uses, uses_remaining, player_rig_id)
      VALUES (v_player.id, v_slot_num, v_max_uses, v_max_uses, v_rig.id)
      ON CONFLICT (player_id, slot_number) DO NOTHING;
      v_slot_num := v_slot_num + 1;
    END LOOP;

    -- Crear slots vacíos restantes
    WHILE v_slot_num <= v_player.rig_slots LOOP
      INSERT INTO player_slots (player_id, slot_number, max_uses, uses_remaining)
      VALUES (v_player.id, v_slot_num, v_max_uses, v_max_uses)
      ON CONFLICT (player_id, slot_number) DO NOTHING;
      v_slot_num := v_slot_num + 1;
    END LOOP;
  END LOOP;
END $$;

-- Migración: Primero eliminar constraint viejo, luego corregir datos, luego agregar nuevo constraint
ALTER TABLE player_slots DROP CONSTRAINT IF EXISTS player_slots_max_uses_check;
UPDATE player_slots SET uses_remaining = 3 WHERE uses_remaining > 3;
UPDATE player_slots SET max_uses = 3 WHERE max_uses > 3;
ALTER TABLE player_slots ADD CONSTRAINT player_slots_max_uses_check CHECK (max_uses IN (2, 3));

-- =====================================================
-- 10. RON WITHDRAWALS
-- =====================================================

CREATE TABLE IF NOT EXISTS ron_withdrawals (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  amount DECIMAL(18, 8) NOT NULL,
  fee DECIMAL(18, 8) NOT NULL DEFAULT 0,
  net_amount DECIMAL(18, 8) NOT NULL,
  wallet_address TEXT NOT NULL,
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'cancelled')),
  tx_hash TEXT,
  error_message TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  processed_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS withdrawal_processing_logs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  processed_count INTEGER DEFAULT 0,
  failed_count INTEGER DEFAULT 0,
  hot_wallet_balance DECIMAL(18, 8),
  details JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- =====================================================
-- 11. RON DEPOSITS
-- =====================================================

CREATE TABLE IF NOT EXISTS ron_deposits (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  amount DECIMAL(18, 8) NOT NULL CHECK (amount > 0),
  tx_hash TEXT NOT NULL UNIQUE,
  status TEXT NOT NULL DEFAULT 'completed' CHECK (status IN ('pending', 'completed', 'failed')),
  deposited_at TIMESTAMPTZ DEFAULT NOW()
);

-- =====================================================
-- 12. PREMIUM SUBSCRIPTIONS
-- =====================================================

CREATE TABLE IF NOT EXISTS premium_subscriptions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  starts_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL,
  amount_paid DECIMAL(18, 8) NOT NULL,
  tx_type TEXT DEFAULT 'ron_balance',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- =====================================================
-- INDICES
-- =====================================================

CREATE INDEX IF NOT EXISTS idx_players_username ON players(username);
CREATE INDEX IF NOT EXISTS idx_players_reputation ON players(reputation_score DESC);
CREATE INDEX IF NOT EXISTS idx_players_online ON players(is_online) WHERE is_online = true;
CREATE INDEX IF NOT EXISTS idx_players_rig_slots ON players(rig_slots);

CREATE INDEX IF NOT EXISTS idx_player_rigs_player ON player_rigs(player_id);
CREATE INDEX IF NOT EXISTS idx_player_rigs_active ON player_rigs(player_id) WHERE is_active = true;

CREATE INDEX IF NOT EXISTS idx_blocks_height ON blocks(height DESC);
CREATE INDEX IF NOT EXISTS idx_blocks_miner ON blocks(miner_id);

CREATE INDEX IF NOT EXISTS idx_pending_blocks_player ON pending_blocks(player_id);
CREATE INDEX IF NOT EXISTS idx_pending_blocks_unclaimed ON pending_blocks(player_id) WHERE claimed = false;

CREATE INDEX IF NOT EXISTS idx_market_orders_type ON market_orders(item_type, type, status);
CREATE INDEX IF NOT EXISTS idx_market_orders_player ON market_orders(player_id);
CREATE INDEX IF NOT EXISTS idx_market_orders_active ON market_orders(item_type) WHERE status = 'active';

CREATE INDEX IF NOT EXISTS idx_trades_buyer ON trades(buyer_id);
CREATE INDEX IF NOT EXISTS idx_trades_seller ON trades(seller_id);
CREATE INDEX IF NOT EXISTS idx_trades_created ON trades(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_transactions_player ON transactions(player_id);
CREATE INDEX IF NOT EXISTS idx_transactions_created ON transactions(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_reputation_events_player ON reputation_events(player_id);
CREATE INDEX IF NOT EXISTS idx_chat_messages_channel ON chat_messages(channel, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_player_cooling_player ON player_cooling(player_id);
CREATE INDEX IF NOT EXISTS idx_player_cards_player ON player_cards(player_id);
CREATE INDEX IF NOT EXISTS idx_player_cards_code ON player_cards(code);
CREATE INDEX IF NOT EXISTS idx_player_cards_unredeemed ON player_cards(player_id) WHERE is_redeemed = false;

CREATE INDEX IF NOT EXISTS idx_crypto_purchases_player ON crypto_purchases(player_id);
CREATE INDEX IF NOT EXISTS idx_crypto_purchases_status ON crypto_purchases(status);

CREATE INDEX IF NOT EXISTS idx_streak_claims_player ON streak_claims(player_id);
CREATE INDEX IF NOT EXISTS idx_player_missions_player ON player_missions(player_id);
CREATE INDEX IF NOT EXISTS idx_player_missions_date ON player_missions(assigned_date);

CREATE INDEX IF NOT EXISTS idx_online_tracking_player ON player_online_tracking(player_id);
CREATE INDEX IF NOT EXISTS idx_rig_boosts_rig ON rig_boosts(player_rig_id);

CREATE INDEX IF NOT EXISTS idx_withdrawals_player ON ron_withdrawals(player_id);
CREATE INDEX IF NOT EXISTS idx_withdrawals_status ON ron_withdrawals(status);
CREATE INDEX IF NOT EXISTS idx_withdrawals_created ON ron_withdrawals(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ron_deposits_player ON ron_deposits(player_id);
CREATE INDEX IF NOT EXISTS idx_ron_deposits_tx ON ron_deposits(tx_hash);

CREATE INDEX IF NOT EXISTS idx_premium_player ON premium_subscriptions(player_id);
CREATE INDEX IF NOT EXISTS idx_premium_expires ON premium_subscriptions(expires_at);

-- =====================================================
-- 13. REFERRAL SYSTEM
-- =====================================================

-- Columnas para sistema de referidos
ALTER TABLE players ADD COLUMN IF NOT EXISTS referral_code TEXT UNIQUE;
ALTER TABLE players ADD COLUMN IF NOT EXISTS referred_by UUID REFERENCES players(id);
ALTER TABLE players ADD COLUMN IF NOT EXISTS referral_count INTEGER DEFAULT 0;

-- Índice para búsqueda rápida de códigos
CREATE INDEX IF NOT EXISTS idx_players_referral_code ON players(referral_code);

-- =====================================================
-- 14. RIG INVENTORY (compras van al inventario primero)
-- =====================================================

CREATE TABLE IF NOT EXISTS player_rig_inventory (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  rig_id TEXT NOT NULL REFERENCES rigs(id),
  quantity INT NOT NULL DEFAULT 1,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(player_id, rig_id)
);

CREATE INDEX IF NOT EXISTS idx_player_rig_inventory_player ON player_rig_inventory(player_id);

-- =====================================================
-- 15. SISTEMA DE BLOQUES DE TIEMPO FIJO CON SHARES
-- =====================================================

-- Tabla principal: Bloques de minería por tiempo
CREATE TABLE IF NOT EXISTS mining_blocks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  block_number INTEGER NOT NULL,
  started_at TIMESTAMPTZ NOT NULL,
  target_close_at TIMESTAMPTZ NOT NULL,
  closed_at TIMESTAMPTZ,
  total_shares NUMERIC DEFAULT 0,
  target_shares NUMERIC DEFAULT 100,
  reward NUMERIC NOT NULL,
  block_type TEXT DEFAULT 'bronze' CHECK (block_type IN ('bronze', 'silver', 'gold')),  -- 🥉 Bronze: 1000, 🥈 Silver: 1500, 🥇 Gold: 2000
  status TEXT DEFAULT 'active',  -- 'active', 'closed', 'distributed'
  difficulty_at_start NUMERIC NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_mining_blocks_status ON mining_blocks(status);
CREATE INDEX IF NOT EXISTS idx_mining_blocks_target_close ON mining_blocks(target_close_at);
CREATE INDEX IF NOT EXISTS idx_mining_blocks_number ON mining_blocks(block_number DESC);

-- Tabla de contribuciones: Shares por jugador por bloque
CREATE TABLE IF NOT EXISTS player_shares (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  mining_block_id UUID NOT NULL REFERENCES mining_blocks(id) ON DELETE CASCADE,
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  shares_count NUMERIC DEFAULT 0,
  fractional_accumulator NUMERIC DEFAULT 0,  -- ⚙️ Acumulador para suavizar generación en baja actividad
  last_share_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(mining_block_id, player_id)
);

CREATE INDEX IF NOT EXISTS idx_player_shares_block ON player_shares(mining_block_id);
CREATE INDEX IF NOT EXISTS idx_player_shares_player ON player_shares(player_id);

-- ⚙️ Agregar columna de acumulador fraccional para suavizar generación
ALTER TABLE player_shares ADD COLUMN IF NOT EXISTS fractional_accumulator NUMERIC DEFAULT 0;

-- 🥇 Agregar tipo de bloque (Bronce, Plata, Oro) para recompensas variables
ALTER TABLE mining_blocks ADD COLUMN IF NOT EXISTS block_type TEXT DEFAULT 'bronze';
DO $$ BEGIN
  ALTER TABLE mining_blocks ADD CONSTRAINT mining_blocks_block_type_check CHECK (block_type IN ('bronze', 'silver', 'gold'));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Tabla de historial (opcional, para análisis)
CREATE TABLE IF NOT EXISTS share_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  mining_block_id UUID NOT NULL REFERENCES mining_blocks(id) ON DELETE CASCADE,
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  player_rig_id UUID REFERENCES player_rigs(id) ON DELETE SET NULL,
  shares_generated NUMERIC NOT NULL,
  hashrate_at_generation NUMERIC NOT NULL,
  difficulty NUMERIC NOT NULL,
  generated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_share_history_block ON share_history(mining_block_id);
CREATE INDEX IF NOT EXISTS idx_share_history_player ON share_history(player_id, generated_at DESC);

-- Modificaciones a tablas existentes para soportar shares
ALTER TABLE network_stats ADD COLUMN IF NOT EXISTS current_mining_block_id UUID REFERENCES mining_blocks(id);
ALTER TABLE network_stats ADD COLUMN IF NOT EXISTS last_block_closed_at TIMESTAMPTZ;
ALTER TABLE network_stats ADD COLUMN IF NOT EXISTS target_shares_per_block NUMERIC DEFAULT 100;

ALTER TABLE blocks ADD COLUMN IF NOT EXISTS is_share_based BOOLEAN DEFAULT false;
ALTER TABLE blocks ADD COLUMN IF NOT EXISTS total_shares NUMERIC;

ALTER TABLE pending_blocks ADD COLUMN IF NOT EXISTS shares_contributed NUMERIC;
ALTER TABLE pending_blocks ADD COLUMN IF NOT EXISTS total_block_shares NUMERIC;
ALTER TABLE pending_blocks ADD COLUMN IF NOT EXISTS share_percentage NUMERIC;
ALTER TABLE pending_blocks ADD COLUMN IF NOT EXISTS block_number INTEGER;

-- =====================================================
-- GRANTS PARA FUNCIONES DEL SISTEMA DE SHARES
-- =====================================================
-- Nota: Ejecutar después de crear las funciones en all_functions.sql

-- GRANT EXECUTE ON FUNCTION initialize_mining_block TO authenticated;
-- GRANT EXECUTE ON FUNCTION generate_shares_tick TO authenticated;
-- GRANT EXECUTE ON FUNCTION close_mining_block TO authenticated;
-- GRANT EXECUTE ON FUNCTION adjust_share_difficulty TO authenticated;
-- GRANT EXECUTE ON FUNCTION check_and_close_blocks TO authenticated;
-- GRANT EXECUTE ON FUNCTION get_current_mining_block_info TO authenticated;
-- GRANT EXECUTE ON FUNCTION get_player_shares_info TO authenticated;
-- GRANT EXECUTE ON FUNCTION game_tick_share_system TO authenticated;

-- =====================================================
-- CONFIGURAR DIFICULTAD INICIAL
-- =====================================================

-- Calcular dificultad inicial basándose en hashrate promedio
DO $$
DECLARE
  v_avg_hashrate NUMERIC;
  v_initial_difficulty NUMERIC;
BEGIN
  -- Obtener hashrate promedio de los últimos registros
  SELECT AVG(hashrate) INTO v_avg_hashrate FROM network_stats;

  -- Si no hay datos, usar un valor por defecto
  IF v_avg_hashrate IS NULL OR v_avg_hashrate = 0 THEN
    v_avg_hashrate := 50000;  -- Valor por defecto
  END IF;

  -- Calcular dificultad: (hashrate_promedio * 30 minutos) / 100 shares objetivo
  v_initial_difficulty := (v_avg_hashrate * 30) / 100;

  -- Asegurar mínimo de 1000
  v_initial_difficulty := GREATEST(1000, v_initial_difficulty);

  -- Actualizar network_stats
  UPDATE network_stats
  SET difficulty = v_initial_difficulty,
      target_shares_per_block = 100,
      last_difficulty_adjustment = NOW()
  WHERE id = 'current';

  RAISE NOTICE 'Dificultad inicial configurada: %', v_initial_difficulty;
END $$;

-- =====================================================
-- INICIALIZAR PRIMER BLOQUE
-- =====================================================
-- Nota: Ejecutar después de crear las funciones en all_functions.sql

-- SELECT initialize_mining_block();

-- =====================================================
-- VERIFICACIÓN DEL DEPLOYMENT
-- =====================================================
-- Ejecutar para verificar que todo está correcto:
--
-- SELECT
--   'Tablas creadas' as paso,
--   EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'mining_blocks') as completado
-- UNION ALL
-- SELECT
--   'Funciones creadas',
--   EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'game_tick_share_system')
-- UNION ALL
-- SELECT
--   'Bloque inicial creado',
--   EXISTS(SELECT 1 FROM mining_blocks WHERE status = 'active');

-- =====================================================
-- CONFIGURAR CRON JOB (PASO MANUAL)
-- =====================================================
-- Ejecutar en Supabase SQL Editor después del deployment:
--
-- 1. Desactivar cron antiguo:
-- SELECT cron.unschedule('game_tick_job');
--
-- 2. Activar nuevo cron (cada 30 segundos):
-- SELECT cron.schedule(
--   'game_tick_share_system_job',
--   '30 seconds',
--   'SELECT game_tick_share_system()'
-- );
--
-- 3. Verificar:
-- SELECT * FROM cron.job;

-- =====================================================
-- SUPABASE REALTIME - Habilitar para tablas que necesitan eventos en tiempo real
-- =====================================================
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE blocks;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE pending_blocks;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE player_rigs;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- =====================================================
-- EXCHANGE RATE DINÁMICO
-- =====================================================
ALTER TABLE network_stats ADD COLUMN IF NOT EXISTS exchange_rate_crypto_gamecoin NUMERIC DEFAULT 25.0;
ALTER TABLE network_stats ADD COLUMN IF NOT EXISTS exchange_rate_previous NUMERIC DEFAULT 25.0;
ALTER TABLE network_stats ADD COLUMN IF NOT EXISTS exchange_rate_updated_at TIMESTAMPTZ DEFAULT NOW();

-- =====================================================
-- HISTORIAL DE EXCHANGE RATE (para gráfico)
-- =====================================================
CREATE TABLE IF NOT EXISTS exchange_rate_history (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  rate NUMERIC NOT NULL,
  block_height INTEGER,
  recorded_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_exchange_rate_history_recorded
  ON exchange_rate_history(recorded_at DESC);

ALTER TABLE exchange_rate_history ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "exchange_rate_history_select"
    ON exchange_rate_history FOR SELECT TO authenticated
    USING (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- =====================================================
-- COOLING MODDING SYSTEM (RPG Enchanting con Gacha)
-- =====================================================

-- Tabla de componentes de cooling (items que se instalan en cooling)
CREATE TABLE IF NOT EXISTS cooling_components (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  tier TEXT NOT NULL CHECK (tier IN ('basic', 'standard', 'advanced', 'elite')),
  base_price NUMERIC NOT NULL CHECK (base_price > 0),
  cooling_power_min NUMERIC DEFAULT 0,
  cooling_power_max NUMERIC DEFAULT 0,
  energy_cost_min NUMERIC DEFAULT 0,
  energy_cost_max NUMERIC DEFAULT 0,
  durability_min NUMERIC DEFAULT 0,
  durability_max NUMERIC DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Mod slots por tier en cooling_items
ALTER TABLE cooling_items ADD COLUMN IF NOT EXISTS max_mod_slots INTEGER DEFAULT 1;

-- Items de cooling individuales con mods instalados
-- Se crean cuando un cooling del inventario recibe su primer mod
CREATE TABLE IF NOT EXISTS player_cooling_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  cooling_item_id TEXT NOT NULL REFERENCES cooling_items(id),
  mods JSONB DEFAULT '[]'::jsonb,
  mod_slots_used INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_player_cooling_items_player ON player_cooling_items(player_id);

-- Referencia en rig_cooling para cooling items modded
ALTER TABLE rig_cooling ADD COLUMN IF NOT EXISTS player_cooling_item_id UUID REFERENCES player_cooling_items(id) ON DELETE SET NULL;

-- RLS para cooling_components (lectura pública para autenticados)
ALTER TABLE cooling_components ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "cooling_components_select"
    ON cooling_components FOR SELECT TO authenticated
    USING (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- RLS para player_cooling_items (solo dueño)
ALTER TABLE player_cooling_items ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "player_cooling_items_select"
    ON player_cooling_items FOR SELECT TO authenticated
    USING (player_id = auth.uid());
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- =====================================================
-- 12. SLOT TIER & XP SYSTEM
-- =====================================================

-- Agregar tier y xp a player_slots
ALTER TABLE player_slots ADD COLUMN IF NOT EXISTS tier TEXT DEFAULT 'basic'
  CHECK (tier IN ('basic', 'standard', 'advanced', 'elite'));
ALTER TABLE player_slots ADD COLUMN IF NOT EXISTS xp INTEGER DEFAULT 0;

-- Migración: Sincronizar tier del slot con el tier del rig instalado
-- Para jugadores existentes cuyo rig tiene un tier superior al slot
UPDATE player_slots ps
SET tier = r.tier
FROM player_rigs pr
JOIN rigs r ON r.id = pr.rig_id
WHERE ps.player_rig_id = pr.id
  AND ps.is_destroyed = false
  AND array_position(ARRAY['basic','standard','advanced','elite'], r.tier)
    > array_position(ARRAY['basic','standard','advanced','elite'], ps.tier);

-- =====================================================
-- 13. MATERIALS & FORGE SYSTEM
-- =====================================================

-- Tabla de materiales base
CREATE TABLE IF NOT EXISTS materials (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  rarity TEXT NOT NULL CHECK (rarity IN ('common', 'uncommon', 'rare', 'epic')),
  drop_chance NUMERIC NOT NULL CHECK (drop_chance > 0 AND drop_chance <= 1),
  icon TEXT DEFAULT '🔩',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Materiales del jugador (inventario de materiales)
CREATE TABLE IF NOT EXISTS player_materials (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  material_id TEXT NOT NULL REFERENCES materials(id),
  quantity INTEGER DEFAULT 0 CHECK (quantity >= 0),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(player_id, material_id)
);

CREATE INDEX IF NOT EXISTS idx_player_materials_player ON player_materials(player_id);

-- Recetas de la forja
CREATE TABLE IF NOT EXISTS forge_recipes (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  category TEXT NOT NULL CHECK (category IN ('tier_kit', 'rig_enhancement', 'cooling', 'utility')),
  result_type TEXT NOT NULL,
  result_id TEXT,
  result_value NUMERIC DEFAULT 0,
  tier TEXT DEFAULT 'basic' CHECK (tier IN ('basic', 'standard', 'advanced', 'elite')),
  icon TEXT DEFAULT '🔨',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Ingredientes de recetas
CREATE TABLE IF NOT EXISTS forge_recipe_ingredients (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recipe_id TEXT NOT NULL REFERENCES forge_recipes(id) ON DELETE CASCADE,
  material_id TEXT NOT NULL REFERENCES materials(id),
  quantity INTEGER NOT NULL CHECK (quantity > 0)
);

CREATE INDEX IF NOT EXISTS idx_forge_recipe_ingredients_recipe ON forge_recipe_ingredients(recipe_id);

-- Materiales dropeados en pending_blocks (para notificaciones)
ALTER TABLE pending_blocks ADD COLUMN IF NOT EXISTS materials_dropped JSONB DEFAULT '[]';

-- RLS para materials (lectura pública)
ALTER TABLE materials ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "materials_select"
    ON materials FOR SELECT TO authenticated
    USING (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- RLS para player_materials (solo dueño)
ALTER TABLE player_materials ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "player_materials_select"
    ON player_materials FOR SELECT TO authenticated
    USING (player_id = auth.uid());
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- RLS para forge_recipes (lectura pública)
ALTER TABLE forge_recipes ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "forge_recipes_select"
    ON forge_recipes FOR SELECT TO authenticated
    USING (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- RLS para forge_recipe_ingredients (lectura pública)
ALTER TABLE forge_recipe_ingredients ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "forge_recipe_ingredients_select"
    ON forge_recipe_ingredients FOR SELECT TO authenticated
    USING (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- =====================================================
-- NOTA: Las funciones están en all_functions.sql
-- NOTA: Las políticas RLS están en all_rls_policies.sql
-- =====================================================
