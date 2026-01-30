-- =====================================================
-- BLOCK LORDS - Sistema de Temperatura y Refrigeración
-- =====================================================
-- Ejecutar después de 001_initial_schema.sql

-- =====================================================
-- MODIFICAR TABLAS EXISTENTES
-- =====================================================

-- Agregar temperatura a player_rigs
ALTER TABLE player_rigs
ADD COLUMN IF NOT EXISTS temperature DECIMAL(5, 2) DEFAULT 25
CHECK (temperature >= 0 AND temperature <= 100);

-- Agregar nivel de refrigeración a players
ALTER TABLE players
ADD COLUMN IF NOT EXISTS cooling_level DECIMAL(5, 2) DEFAULT 0
CHECK (cooling_level >= 0 AND cooling_level <= 100);

-- =====================================================
-- TABLA DE ITEMS DE REFRIGERACIÓN
-- =====================================================

CREATE TABLE IF NOT EXISTS cooling_items (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  cooling_power DECIMAL(5, 2) NOT NULL CHECK (cooling_power > 0),  -- Cuánto reduce la temperatura
  base_price DECIMAL(10, 2) NOT NULL CHECK (base_price >= 0),
  tier TEXT NOT NULL CHECK (tier IN ('basic', 'standard', 'advanced', 'elite')),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- =====================================================
-- TABLA DE REFRIGERACIÓN INSTALADA POR JUGADOR
-- =====================================================

CREATE TABLE IF NOT EXISTS player_cooling (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  cooling_item_id TEXT NOT NULL REFERENCES cooling_items(id),
  installed_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(player_id, cooling_item_id)
);

-- Índice para buscar refrigeración de jugador
CREATE INDEX IF NOT EXISTS idx_player_cooling_player ON player_cooling(player_id);

-- =====================================================
-- ACTUALIZAR item_type EN market_orders PARA INCLUIR cooling
-- =====================================================

-- Primero eliminar el constraint existente
ALTER TABLE market_orders DROP CONSTRAINT IF EXISTS market_orders_item_type_check;

-- Agregar el nuevo constraint con 'cooling' incluido
ALTER TABLE market_orders ADD CONSTRAINT market_orders_item_type_check
CHECK (item_type IN ('crypto', 'rig', 'energy', 'internet', 'cooling'));
