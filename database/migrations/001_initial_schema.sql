-- =====================================================
-- CRYPTO ARCADE MMO - Schema de Base de Datos
-- =====================================================

-- Habilitar extensiones necesarias
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =====================================================
-- TABLAS PRINCIPALES
-- =====================================================

-- Jugadores
CREATE TABLE IF NOT EXISTS players (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT UNIQUE NOT NULL,
  username TEXT UNIQUE NOT NULL CHECK (length(username) >= 3 AND length(username) <= 20),
  gamecoin_balance DECIMAL(18, 4) DEFAULT 1000 NOT NULL CHECK (gamecoin_balance >= 0),
  crypto_balance DECIMAL(18, 8) DEFAULT 0 NOT NULL CHECK (crypto_balance >= 0),
  energy DECIMAL(5, 2) DEFAULT 100 NOT NULL CHECK (energy >= 0 AND energy <= 100),
  internet DECIMAL(5, 2) DEFAULT 100 NOT NULL CHECK (internet >= 0 AND internet <= 100),
  reputation_score DECIMAL(5, 2) DEFAULT 50 NOT NULL CHECK (reputation_score >= 0 AND reputation_score <= 100),
  region TEXT DEFAULT 'global',
  ron_wallet TEXT DEFAULT NULL,
  is_online BOOLEAN DEFAULT false,
  last_seen TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Rigs (catálogo de equipos de minería)
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
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Rigs de jugadores
CREATE TABLE IF NOT EXISTS player_rigs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  rig_id TEXT NOT NULL REFERENCES rigs(id),
  is_active BOOLEAN DEFAULT false,
  condition DECIMAL(5, 2) DEFAULT 100 CHECK (condition >= 0 AND condition <= 100),
  acquired_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(player_id, rig_id)
);

-- Bloques minados
CREATE TABLE IF NOT EXISTS blocks (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  height INTEGER UNIQUE NOT NULL,
  hash TEXT UNIQUE NOT NULL,
  previous_hash TEXT NOT NULL,
  miner_id UUID NOT NULL REFERENCES players(id),
  difficulty DECIMAL(15, 2) NOT NULL,
  network_hashrate DECIMAL(15, 2) NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Órdenes del mercado
CREATE TABLE IF NOT EXISTS market_orders (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  type TEXT NOT NULL CHECK (type IN ('buy', 'sell')),
  item_type TEXT NOT NULL CHECK (item_type IN ('crypto', 'rig', 'energy', 'internet')),
  item_id TEXT,
  quantity DECIMAL(18, 8) NOT NULL CHECK (quantity > 0),
  price_per_unit DECIMAL(18, 8) NOT NULL CHECK (price_per_unit > 0),
  remaining_quantity DECIMAL(18, 8) NOT NULL CHECK (remaining_quantity >= 0),
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'filled', 'cancelled', 'partially_filled')),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Trades ejecutados
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

-- Transacciones (historial)
CREATE TABLE IF NOT EXISTS transactions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  amount DECIMAL(18, 8) NOT NULL,
  currency TEXT NOT NULL CHECK (currency IN ('gamecoin', 'crypto')),
  description TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Eventos de reputación
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

-- Insignias
CREATE TABLE IF NOT EXISTS badges (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  icon TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Insignias de jugadores
CREATE TABLE IF NOT EXISTS player_badges (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  badge_id TEXT NOT NULL REFERENCES badges(id),
  awarded_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(player_id, badge_id)
);

-- Eventos de jugadores (logs)
CREATE TABLE IF NOT EXISTS player_events (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  data JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Penalizaciones
CREATE TABLE IF NOT EXISTS player_penalties (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  reason TEXT NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Mensajes de chat
CREATE TABLE IF NOT EXISTS chat_messages (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  channel TEXT NOT NULL,
  message TEXT NOT NULL CHECK (length(message) <= 500),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Estadísticas de la red
CREATE TABLE IF NOT EXISTS network_stats (
  id TEXT PRIMARY KEY DEFAULT 'current',
  difficulty DECIMAL(15, 2) DEFAULT 1000,
  hashrate DECIMAL(15, 2) DEFAULT 0,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- =====================================================
-- ÍNDICES
-- =====================================================

CREATE INDEX IF NOT EXISTS idx_players_username ON players(username);
CREATE INDEX IF NOT EXISTS idx_players_reputation ON players(reputation_score DESC);
CREATE INDEX IF NOT EXISTS idx_players_online ON players(is_online) WHERE is_online = true;

CREATE INDEX IF NOT EXISTS idx_player_rigs_player ON player_rigs(player_id);
CREATE INDEX IF NOT EXISTS idx_player_rigs_active ON player_rigs(player_id) WHERE is_active = true;

CREATE INDEX IF NOT EXISTS idx_blocks_height ON blocks(height DESC);
CREATE INDEX IF NOT EXISTS idx_blocks_miner ON blocks(miner_id);

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

-- =====================================================
-- FUNCIONES
-- =====================================================

-- Función para incrementar balance
CREATE OR REPLACE FUNCTION increment_balance(
  p_player_id UUID,
  p_amount DECIMAL,
  p_currency TEXT
)
RETURNS DECIMAL
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  new_balance DECIMAL;
BEGIN
  IF p_currency = 'gamecoin' THEN
    UPDATE players
    SET gamecoin_balance = gamecoin_balance + p_amount,
        updated_at = NOW()
    WHERE id = p_player_id
    RETURNING gamecoin_balance INTO new_balance;
  ELSIF p_currency = 'crypto' THEN
    UPDATE players
    SET crypto_balance = crypto_balance + p_amount,
        updated_at = NOW()
    WHERE id = p_player_id
    RETURNING crypto_balance INTO new_balance;
  END IF;

  RETURN new_balance;
END;
$$;

-- Función para transferir GameCoin
CREATE OR REPLACE FUNCTION transfer_gamecoin(
  p_from_player UUID,
  p_to_player UUID,
  p_amount DECIMAL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Verificar balance suficiente
  IF (SELECT gamecoin_balance FROM players WHERE id = p_from_player) < p_amount THEN
    RAISE EXCEPTION 'Balance insuficiente';
  END IF;

  -- Transferir
  UPDATE players SET gamecoin_balance = gamecoin_balance - p_amount WHERE id = p_from_player;
  UPDATE players SET gamecoin_balance = gamecoin_balance + p_amount WHERE id = p_to_player;
END;
$$;

-- Función para transferir Crypto
CREATE OR REPLACE FUNCTION transfer_crypto(
  p_from_player UUID,
  p_to_player UUID,
  p_amount DECIMAL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF (SELECT crypto_balance FROM players WHERE id = p_from_player) < p_amount THEN
    RAISE EXCEPTION 'Balance insuficiente';
  END IF;

  UPDATE players SET crypto_balance = crypto_balance - p_amount WHERE id = p_from_player;
  UPDATE players SET crypto_balance = crypto_balance + p_amount WHERE id = p_to_player;
END;
$$;

-- Función para transferir Energía
CREATE OR REPLACE FUNCTION transfer_energy(
  p_from_player UUID,
  p_to_player UUID,
  p_amount DECIMAL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF (SELECT energy FROM players WHERE id = p_from_player) < p_amount THEN
    RAISE EXCEPTION 'Energía insuficiente';
  END IF;

  UPDATE players SET energy = GREATEST(0, energy - p_amount) WHERE id = p_from_player;
  UPDATE players SET energy = LEAST(100, energy + p_amount) WHERE id = p_to_player;
END;
$$;

-- Función para transferir Internet
CREATE OR REPLACE FUNCTION transfer_internet(
  p_from_player UUID,
  p_to_player UUID,
  p_amount DECIMAL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF (SELECT internet FROM players WHERE id = p_from_player) < p_amount THEN
    RAISE EXCEPTION 'Internet insuficiente';
  END IF;

  UPDATE players SET internet = GREATEST(0, internet - p_amount) WHERE id = p_from_player;
  UPDATE players SET internet = LEAST(100, internet + p_amount) WHERE id = p_to_player;
END;
$$;

-- Función para actualizar reputación
CREATE OR REPLACE FUNCTION update_reputation(
  p_player_id UUID,
  p_delta DECIMAL,
  p_reason TEXT
)
RETURNS DECIMAL
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  old_score DECIMAL;
  new_score DECIMAL;
BEGIN
  SELECT reputation_score INTO old_score FROM players WHERE id = p_player_id;

  new_score := GREATEST(0, LEAST(100, old_score + p_delta));

  UPDATE players
  SET reputation_score = new_score,
      updated_at = NOW()
  WHERE id = p_player_id;

  -- Registrar evento
  INSERT INTO reputation_events (player_id, delta, reason, old_score, new_score)
  VALUES (p_player_id, p_delta, p_reason, old_score, new_score);

  RETURN new_score;
END;
$$;

-- Trigger para actualizar updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_players_updated_at ON players;
CREATE TRIGGER update_players_updated_at
  BEFORE UPDATE ON players
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_market_orders_updated_at ON market_orders;
CREATE TRIGGER update_market_orders_updated_at
  BEFORE UPDATE ON market_orders
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();
