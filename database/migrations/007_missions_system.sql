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
  mission_type TEXT NOT NULL, -- 'mine_blocks', 'online_time', 'earn_crypto', 'repair_rig', 'use_cooling', 'recharge_resource', 'use_boost', 'exchange_crypto', 'buy_item', 'buy_rig', 'activate_rig', 'buy_crypto'
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
  ('earn_crypto_small', 'Primeras Ganancias', 'Gana al menos 200 crypto', 'earn_crypto', 200, 'gamecoin', 20, 'easy', '✨')
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
  ('earn_crypto_1', 'Primer Crypto', 'Gana al menos 500 crypto', 'earn_crypto', 500, 'gamecoin', 60, 'medium', '💎'),
  ('earn_crypto_2', 'Creciendo', 'Gana al menos 1000 crypto', 'earn_crypto', 1000, 'crypto', 5, 'medium', '📈'),
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
  ('earn_crypto_5', 'Acumulador', 'Gana al menos 2000 crypto', 'earn_crypto', 2000, 'gamecoin', 150, 'hard', '💰'),
  ('earn_crypto_10', 'Magnate', 'Gana al menos 3500 crypto', 'earn_crypto', 3500, 'gamecoin', 200, 'hard', '💎'),
  ('earn_crypto_25', 'Ballena', 'Gana al menos 5000 crypto', 'earn_crypto', 5000, 'crypto', 50, 'hard', '🐋'),
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
  ('earn_crypto_50', 'El Magnate', 'Gana al menos 10000 crypto', 'earn_crypto', 10000, 'crypto', 100, 'epic', '💰')
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
-- MISIONES DE BOOSTS - FÁCILES A ÉPICAS
-- =====================================================

INSERT INTO missions (id, name, description, mission_type, target_value, reward_type, reward_amount, difficulty, icon)
VALUES
  -- Fáciles
  ('use_boost_1', 'Potenciado', 'Usa un boost en un rig', 'use_boost', 1, 'gamecoin', 30, 'easy', '🚀'),
  -- Medias
  ('use_boost_2', 'Doble Boost', 'Usa 2 boosts', 'use_boost', 2, 'gamecoin', 55, 'medium', '⚡'),
  ('use_boost_3', 'Triple Poder', 'Usa 3 boosts', 'use_boost', 3, 'gamecoin', 75, 'medium', '💥'),
  -- Difíciles
  ('use_boost_5', 'Adicto a los Boosts', 'Usa 5 boosts', 'use_boost', 5, 'gamecoin', 120, 'hard', '🔥'),
  -- Épicas
  ('use_boost_10', 'Maestro del Poder', 'Usa 10 boosts en un dia', 'use_boost', 10, 'crypto', 50, 'epic', '⭐')
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
-- MISIONES DE EXCHANGE - FÁCILES A ÉPICAS
-- =====================================================

INSERT INTO missions (id, name, description, mission_type, target_value, reward_type, reward_amount, difficulty, icon)
VALUES
  -- Fáciles
  ('exchange_1', 'Primer Exchange', 'Realiza tu primer intercambio', 'exchange_crypto', 1, 'gamecoin', 25, 'easy', '💱'),
  -- Medias
  ('exchange_2', 'Trader Novato', 'Realiza 2 intercambios', 'exchange_crypto', 2, 'gamecoin', 50, 'medium', '📊'),
  ('exchange_3', 'Comerciante', 'Realiza 3 intercambios', 'exchange_crypto', 3, 'gamecoin', 70, 'medium', '💹'),
  -- Difíciles
  ('exchange_5', 'Trader Activo', 'Realiza 5 intercambios', 'exchange_crypto', 5, 'gamecoin', 100, 'hard', '📈'),
  -- Épicas
  ('exchange_10', 'Lobo de Wall Street', 'Realiza 10 intercambios en un dia', 'exchange_crypto', 10, 'crypto', 75, 'epic', '🐺')
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
-- MISIONES DE COMPRAS EN MARKET - FÁCILES A ÉPICAS
-- =====================================================

INSERT INTO missions (id, name, description, mission_type, target_value, reward_type, reward_amount, difficulty, icon)
VALUES
  -- Fáciles
  ('buy_item_1', 'Primera Compra', 'Compra un item en el mercado', 'buy_item', 1, 'gamecoin', 20, 'easy', '🛒'),
  -- Medias
  ('buy_item_2', 'Comprador', 'Compra 2 items', 'buy_item', 2, 'gamecoin', 45, 'medium', '🛍️'),
  ('buy_item_3', 'Consumidor', 'Compra 3 items', 'buy_item', 3, 'gamecoin', 65, 'medium', '📦'),
  -- Difíciles
  ('buy_item_5', 'Adicto a las Compras', 'Compra 5 items', 'buy_item', 5, 'gamecoin', 90, 'hard', '💳'),
  -- Épicas
  ('buy_item_10', 'Shopaholic', 'Compra 10 items en un dia', 'buy_item', 10, 'crypto', 60, 'epic', '🏪')
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
-- MISIONES DE COMPRA DE RIGS - MEDIAS A ÉPICAS
-- =====================================================

INSERT INTO missions (id, name, description, mission_type, target_value, reward_type, reward_amount, difficulty, icon)
VALUES
  -- Medias
  ('buy_rig_1', 'Nuevo Equipo', 'Compra un rig nuevo', 'buy_rig', 1, 'gamecoin', 100, 'medium', '🖥️'),
  -- Difíciles
  ('buy_rig_2', 'Expansion', 'Compra 2 rigs', 'buy_rig', 2, 'gamecoin', 175, 'hard', '💻'),
  ('buy_rig_3', 'Granja Minera', 'Compra 3 rigs', 'buy_rig', 3, 'crypto', 50, 'hard', '🏭'),
  -- Épicas
  ('buy_rig_5', 'Magnate del Hardware', 'Compra 5 rigs en un dia', 'buy_rig', 5, 'crypto', 150, 'epic', '👑')
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
-- MISIONES DE ACTIVAR RIGS - FÁCILES A ÉPICAS
-- =====================================================

INSERT INTO missions (id, name, description, mission_type, target_value, reward_type, reward_amount, difficulty, icon)
VALUES
  -- Fáciles
  ('activate_rig_1', 'Encendido', 'Activa un rig', 'activate_rig', 1, 'gamecoin', 15, 'easy', '🔌'),
  -- Medias
  ('activate_rig_2', 'Doble Activacion', 'Activa 2 rigs', 'activate_rig', 2, 'gamecoin', 35, 'medium', '⚡'),
  ('activate_rig_3', 'Triple Activacion', 'Activa 3 rigs', 'activate_rig', 3, 'gamecoin', 55, 'medium', '🔋'),
  -- Difíciles
  ('activate_rig_5', 'Granja Activa', 'Activa 5 rigs', 'activate_rig', 5, 'gamecoin', 85, 'hard', '🏭'),
  -- Épicas
  ('activate_rig_10', 'Datacenter', 'Activa 10 rigs en un dia', 'activate_rig', 10, 'crypto', 80, 'epic', '🌐')
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
-- MISIONES DE COMPRA DE CRYPTO - MEDIAS A ÉPICAS
-- =====================================================

INSERT INTO missions (id, name, description, mission_type, target_value, reward_type, reward_amount, difficulty, icon)
VALUES
  -- Medias
  ('buy_crypto_1', 'Inversor', 'Compra un paquete de crypto', 'buy_crypto', 1, 'gamecoin', 75, 'medium', '💎'),
  -- Difíciles
  ('buy_crypto_2', 'Acumulador', 'Compra 2 paquetes de crypto', 'buy_crypto', 2, 'gamecoin', 125, 'hard', '💰'),
  -- Épicas
  ('buy_crypto_5', 'Whale', 'Compra 5 paquetes de crypto', 'buy_crypto', 5, 'crypto', 200, 'epic', '🐋')
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
