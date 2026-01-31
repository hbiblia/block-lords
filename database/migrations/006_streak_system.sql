-- =====================================================
-- BLOCK LORDS - Sistema de Racha de Login (Streak)
-- =====================================================
-- Ejecutar después de las migraciones anteriores

-- =====================================================
-- TABLA DE RACHAS DE JUGADORES
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

-- =====================================================
-- TABLA DE RECOMPENSAS POR DÍA DE RACHA
-- =====================================================

CREATE TABLE IF NOT EXISTS streak_rewards (
  id TEXT PRIMARY KEY,
  day_number INTEGER UNIQUE NOT NULL,
  gamecoin_reward DECIMAL(10, 2) DEFAULT 0,
  crypto_reward DECIMAL(10, 4) DEFAULT 0,
  item_type TEXT, -- 'prepaid_card', 'rig', 'cooling', null
  item_id TEXT,   -- ID del item a dar
  description TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- =====================================================
-- TABLA DE HISTORIAL DE CLAIMS
-- =====================================================

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

-- Índices
CREATE INDEX IF NOT EXISTS idx_streak_claims_player ON streak_claims(player_id);
CREATE INDEX IF NOT EXISTS idx_streak_claims_date ON streak_claims(claimed_at);

-- =====================================================
-- DATOS INICIALES DE RECOMPENSAS
-- =====================================================

INSERT INTO streak_rewards (id, day_number, gamecoin_reward, crypto_reward, item_type, item_id, description)
VALUES
  ('streak_day_1', 1, 10, 0, NULL, NULL, 'Día 1: Bienvenida'),
  ('streak_day_2', 2, 20, 0, NULL, NULL, 'Día 2: Seguimos'),
  ('streak_day_3', 3, 30, 0, 'prepaid_card', 'energy_10', 'Día 3: Tarjeta Energía +10'),
  ('streak_day_4', 4, 40, 0, NULL, NULL, 'Día 4: Constancia'),
  ('streak_day_5', 5, 50, 0, 'prepaid_card', 'internet_10', 'Día 5: Tarjeta Internet +10'),
  ('streak_day_6', 6, 60, 0, NULL, NULL, 'Día 6: Casi una semana'),
  ('streak_day_7', 7, 100, 0.1, 'prepaid_card', 'energy_25', 'Día 7: ¡Una semana completa!'),
  ('streak_day_14', 14, 200, 0.25, 'prepaid_card', 'internet_25', 'Día 14: ¡Dos semanas!'),
  ('streak_day_21', 21, 300, 0.5, 'prepaid_card', 'energy_50', 'Día 21: ¡Tres semanas!'),
  ('streak_day_30', 30, 500, 1.0, 'cooling', 'liquid_cooler', 'Día 30: ¡Un mes! Refrigeración Líquida')
ON CONFLICT (id) DO UPDATE SET
  day_number = EXCLUDED.day_number,
  gamecoin_reward = EXCLUDED.gamecoin_reward,
  crypto_reward = EXCLUDED.crypto_reward,
  item_type = EXCLUDED.item_type,
  item_id = EXCLUDED.item_id,
  description = EXCLUDED.description;
