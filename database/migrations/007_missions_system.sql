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
  difficulty TEXT NOT NULL CHECK (difficulty IN ('easy', 'medium', 'hard', 'epic')),
  icon TEXT DEFAULT '🎯',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Actualizar constraint para incluir 'epic' si la tabla ya existe
ALTER TABLE missions DROP CONSTRAINT IF EXISTS missions_difficulty_check;
ALTER TABLE missions ADD CONSTRAINT missions_difficulty_check CHECK (difficulty IN ('easy', 'medium', 'hard', 'epic'));

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
-- DATOS INICIALES DE MISIONES - FÁCILES
-- =====================================================

INSERT INTO missions (id, name, description, mission_type, target_value, reward_type, reward_amount, difficulty, icon)
VALUES
  ('mine_1_block', 'Primer Bloque', 'Mina al menos 1 bloque', 'mine_blocks', 1, 'gamecoin', 25, 'easy', '⛏️'),
  ('online_5_min', 'Presencia', 'Permanece online 5 minutos', 'online_time', 5, 'gamecoin', 15, 'easy', '⏱️'),
  ('online_10_min', 'Calentando Motores', 'Permanece online 10 minutos', 'online_time', 10, 'gamecoin', 25, 'easy', '🔥'),
  ('recharge_once', 'Recarga', 'Usa una tarjeta prepago', 'recharge_resource', 1, 'gamecoin', 20, 'easy', '🔋'),
  ('use_cooling_1', 'Manten la Calma', 'Instala refrigeracion en un rig', 'use_cooling', 1, 'gamecoin', 30, 'easy', '❄️'),
  ('earn_crypto_small', 'Primeras Ganancias', 'Gana al menos 0.005 crypto', 'earn_crypto', 0.005, 'gamecoin', 20, 'easy', '✨')
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
-- DATOS INICIALES DE MISIONES - MEDIAS
-- =====================================================

INSERT INTO missions (id, name, description, mission_type, target_value, reward_type, reward_amount, difficulty, icon)
VALUES
  ('mine_3_blocks', 'Minero Activo', 'Mina 3 bloques', 'mine_blocks', 3, 'gamecoin', 50, 'medium', '⛏️'),
  ('mine_5_blocks', 'Cadena de Bloques', 'Mina 5 bloques', 'mine_blocks', 5, 'gamecoin', 75, 'medium', '🔗'),
  ('mine_7_blocks', 'Racha Minera', 'Mina 7 bloques', 'mine_blocks', 7, 'gamecoin', 85, 'medium', '🎯'),
  ('online_15_min', 'Dedicacion', 'Permanece online 15 minutos', 'online_time', 15, 'gamecoin', 40, 'medium', '⏱️'),
  ('online_20_min', 'Sesion Productiva', 'Permanece online 20 minutos', 'online_time', 20, 'gamecoin', 55, 'medium', '📊'),
  ('earn_crypto_1', 'Primer Crypto', 'Gana al menos 0.01 crypto', 'earn_crypto', 0.01, 'gamecoin', 60, 'medium', '💎'),
  ('earn_crypto_2', 'Creciendo', 'Gana al menos 0.02 crypto', 'earn_crypto', 0.02, 'crypto', 5, 'medium', '📈'),
  ('repair_1_rig', 'Mantenimiento', 'Repara un rig', 'repair_rig', 1, 'gamecoin', 35, 'medium', '🔧'),
  ('repair_2_rigs', 'Mecanico', 'Repara 2 rigs', 'repair_rig', 2, 'gamecoin', 60, 'medium', '🛠️'),
  ('use_cooling_2', 'Tecnico de Refrigeracion', 'Instala refrigeracion 2 veces', 'use_cooling', 2, 'gamecoin', 50, 'medium', '🧊'),
  ('recharge_2', 'Abastecimiento', 'Usa 2 tarjetas prepago', 'recharge_resource', 2, 'gamecoin', 45, 'medium', '⚡')
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
-- DATOS INICIALES DE MISIONES - DIFÍCILES
-- =====================================================

INSERT INTO missions (id, name, description, mission_type, target_value, reward_type, reward_amount, difficulty, icon)
VALUES
  ('mine_10_blocks', 'Maestro Minero', 'Mina 10 bloques', 'mine_blocks', 10, 'crypto', 5, 'hard', '👑'),
  ('mine_15_blocks', 'Minero Veterano', 'Mina 15 bloques', 'mine_blocks', 15, 'crypto', 10, 'hard', '⚔️'),
  ('mine_25_blocks', 'Leyenda Minera', 'Mina 25 bloques', 'mine_blocks', 25, 'crypto', 25, 'hard', '🏆'),
  ('online_30_min', 'Maraton', 'Permanece online 30 minutos', 'online_time', 30, 'gamecoin', 100, 'hard', '🏃'),
  ('online_45_min', 'Dedicacion Total', 'Permanece online 45 minutos', 'online_time', 45, 'gamecoin', 120, 'hard', '💪'),
  ('online_60_min', 'Hora Completa', 'Permanece online 60 minutos', 'online_time', 60, 'crypto', 15, 'hard', '🕐'),
  ('earn_crypto_5', 'Acumulador', 'Gana al menos 0.05 crypto', 'earn_crypto', 0.05, 'gamecoin', 150, 'hard', '💰'),
  ('earn_crypto_10', 'Magnate', 'Gana al menos 0.1 crypto', 'earn_crypto', 0.1, 'gamecoin', 200, 'hard', '💎'),
  ('earn_crypto_25', 'Ballena', 'Gana al menos 0.25 crypto', 'earn_crypto', 0.25, 'crypto', 50, 'hard', '🐋'),
  ('repair_3_rigs', 'Ingeniero', 'Repara 3 rigs', 'repair_rig', 3, 'gamecoin', 100, 'hard', '🔩'),
  ('use_cooling_3', 'Experto en Refrigeracion', 'Instala refrigeracion 3 veces', 'use_cooling', 3, 'gamecoin', 80, 'hard', '🌡️'),
  ('recharge_3', 'Proveedor', 'Usa 3 tarjetas prepago', 'recharge_resource', 3, 'gamecoin', 70, 'hard', '🔌')
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
-- DATOS INICIALES DE MISIONES - ÉPICAS
-- =====================================================

INSERT INTO missions (id, name, description, mission_type, target_value, reward_type, reward_amount, difficulty, icon)
VALUES
  ('mine_50_blocks', 'Rey de los Bloques', 'Mina 50 bloques en un dia', 'mine_blocks', 50, 'crypto', 100, 'epic', '👑'),
  ('online_120_min', 'Maratonista', 'Permanece online 2 horas', 'online_time', 120, 'crypto', 75, 'epic', '🏅'),
  ('earn_crypto_50', 'El Magnate', 'Gana al menos 0.5 crypto', 'earn_crypto', 0.5, 'crypto', 100, 'epic', '💰')
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
