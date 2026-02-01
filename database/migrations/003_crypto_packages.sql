-- =====================================================
-- BLOCK LORDS - Paquetes de Compra de Crypto con RON
-- =====================================================
-- Ejecutar después de las migraciones anteriores

-- =====================================================
-- LIMPIAR OBJETOS EXISTENTES SI HAY CONFLICTO
-- =====================================================
DROP TABLE IF EXISTS crypto_purchases CASCADE;
DROP TABLE IF EXISTS crypto_packages CASCADE;
DROP TYPE IF EXISTS crypto_packages CASCADE;

-- =====================================================
-- TABLA DE PAQUETES DE CRYPTO
-- =====================================================

CREATE TABLE crypto_packages (
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

-- =====================================================
-- TABLA DE COMPRAS DE CRYPTO (HISTORIAL)
-- =====================================================

CREATE TABLE IF NOT EXISTS crypto_purchases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  package_id TEXT NOT NULL REFERENCES crypto_packages(id),
  crypto_amount DECIMAL(10, 2) NOT NULL,
  ron_paid DECIMAL(10, 4) NOT NULL,
  tx_hash TEXT, -- Hash de transacción de RON (para verificación)
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'failed', 'refunded')),
  purchased_at TIMESTAMPTZ DEFAULT NOW(),
  completed_at TIMESTAMPTZ
);

-- Índices
CREATE INDEX IF NOT EXISTS idx_crypto_purchases_player ON crypto_purchases(player_id);
CREATE INDEX IF NOT EXISTS idx_crypto_purchases_status ON crypto_purchases(status);
CREATE INDEX IF NOT EXISTS idx_crypto_purchases_tx ON crypto_purchases(tx_hash);

-- =====================================================
-- AGREGAR COLUMNA ron_balance A PLAYERS SI NO EXISTE
-- =====================================================

ALTER TABLE players ADD COLUMN IF NOT EXISTS ron_balance DECIMAL(18, 8) DEFAULT 0;
