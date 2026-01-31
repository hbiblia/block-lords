-- =====================================================
-- BLOCK LORDS - Sistema de Misiones Diarias
-- =====================================================
-- Ejecutar después de 006_streak_system.sql

-- =====================================================
-- TABLA DE DEFINICIONES DE MISIONES
-- =====================================================

CREATE TABLE IF NOT EXISTS missions (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT NOT NULL,
  mission_type TEXT NOT NULL, -- 'mine_blocks', 'online_time', 'earn_crypto', 'repair_rig', 'use_cooling', 'recharge_resource'
  target_value NUMERIC NOT NULL,
  reward_type TEXT NOT NULL, -- 'gamecoin', 'crypto', 'energy', 'internet'
  reward_amount NUMERIC NOT NULL,
  difficulty TEXT NOT NULL CHECK (difficulty IN ('easy', 'medium', 'hard')),
  icon TEXT DEFAULT '🎯',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- =====================================================
-- TABLA DE MISIONES ASIGNADAS A JUGADORES
-- =====================================================

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

-- Índices
CREATE INDEX IF NOT EXISTS idx_player_missions_player ON player_missions(player_id);
CREATE INDEX IF NOT EXISTS idx_player_missions_date ON player_missions(assigned_date);
CREATE INDEX IF NOT EXISTS idx_player_missions_unclaimed ON player_missions(player_id) WHERE is_completed = true AND is_claimed = false;

-- =====================================================
-- DATOS INICIALES DE MISIONES
-- =====================================================

-- Misiones fáciles (1 por día)
INSERT INTO missions (id, name, description, mission_type, target_value, reward_type, reward_amount, difficulty, icon)
VALUES
  ('mine_1_block', 'Primer Bloque', 'Mina al menos 1 bloque', 'mine_blocks', 1, 'gamecoin', 25, 'easy', '⛏️'),
  ('online_5_min', 'Presencia', 'Permanece online 5 minutos', 'online_time', 5, 'gamecoin', 15, 'easy', '⏱️'),
  ('recharge_once', 'Recarga', 'Usa una tarjeta prepago', 'recharge_resource', 1, 'gamecoin', 20, 'easy', '🔋')
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  mission_type = EXCLUDED.mission_type,
  target_value = EXCLUDED.target_value,
  reward_type = EXCLUDED.reward_type,
  reward_amount = EXCLUDED.reward_amount,
  difficulty = EXCLUDED.difficulty,
  icon = EXCLUDED.icon;

-- Misiones medias (2 por día)
INSERT INTO missions (id, name, description, mission_type, target_value, reward_type, reward_amount, difficulty, icon)
VALUES
  ('mine_3_blocks', 'Minero Activo', 'Mina 3 bloques', 'mine_blocks', 3, 'gamecoin', 50, 'medium', '⛏️'),
  ('mine_5_blocks', 'Cadena de Bloques', 'Mina 5 bloques', 'mine_blocks', 5, 'gamecoin', 75, 'medium', '🔗'),
  ('online_15_min', 'Dedicación', 'Permanece online 15 minutos', 'online_time', 15, 'gamecoin', 40, 'medium', '⏱️'),
  ('earn_crypto_1', 'Primer Crypto', 'Gana al menos 0.01 crypto', 'earn_crypto', 0.01, 'gamecoin', 60, 'medium', '💎'),
  ('repair_1_rig', 'Mantenimiento', 'Repara un rig', 'repair_rig', 1, 'gamecoin', 35, 'medium', '🔧')
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  mission_type = EXCLUDED.mission_type,
  target_value = EXCLUDED.target_value,
  reward_type = EXCLUDED.reward_type,
  reward_amount = EXCLUDED.reward_amount,
  difficulty = EXCLUDED.difficulty,
  icon = EXCLUDED.icon;

-- Misiones difíciles (1 por día)
INSERT INTO missions (id, name, description, mission_type, target_value, reward_type, reward_amount, difficulty, icon)
VALUES
  ('mine_10_blocks', 'Maestro Minero', 'Mina 10 bloques', 'mine_blocks', 10, 'crypto', 0.05, 'hard', '👑'),
  ('online_30_min', 'Maratón', 'Permanece online 30 minutos', 'online_time', 30, 'gamecoin', 100, 'hard', '🏃'),
  ('earn_crypto_5', 'Acumulador', 'Gana al menos 0.05 crypto', 'earn_crypto', 0.05, 'gamecoin', 150, 'hard', '💰')
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  mission_type = EXCLUDED.mission_type,
  target_value = EXCLUDED.target_value,
  reward_type = EXCLUDED.reward_type,
  reward_amount = EXCLUDED.reward_amount,
  difficulty = EXCLUDED.difficulty,
  icon = EXCLUDED.icon;

-- =====================================================
-- TABLA DE TRACKING DE TIEMPO ONLINE
-- =====================================================

CREATE TABLE IF NOT EXISTS player_online_tracking (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  tracking_date DATE NOT NULL DEFAULT CURRENT_DATE,
  minutes_online INTEGER DEFAULT 0,
  last_heartbeat TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(player_id, tracking_date)
);

CREATE INDEX IF NOT EXISTS idx_online_tracking_player ON player_online_tracking(player_id);
CREATE INDEX IF NOT EXISTS idx_online_tracking_date ON player_online_tracking(tracking_date);
