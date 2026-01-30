-- =====================================================
-- BLOCK LORDS - Sistema de Tarjetas Prepago
-- =====================================================
-- Ejecutar después de 002_temperature_cooling.sql

-- =====================================================
-- TABLA DE TIPOS DE TARJETAS PREPAGO
-- =====================================================

CREATE TABLE IF NOT EXISTS prepaid_cards (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  card_type TEXT NOT NULL CHECK (card_type IN ('energy', 'internet')),
  amount DECIMAL(5, 2) NOT NULL CHECK (amount > 0),  -- Cantidad que recarga
  base_price DECIMAL(10, 2) NOT NULL CHECK (base_price >= 0),
  tier TEXT NOT NULL CHECK (tier IN ('basic', 'standard', 'advanced', 'elite')),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- =====================================================
-- TABLA DE TARJETAS COMPRADAS POR JUGADORES
-- =====================================================

CREATE TABLE IF NOT EXISTS player_cards (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  card_id TEXT NOT NULL REFERENCES prepaid_cards(id),
  code TEXT NOT NULL UNIQUE,  -- Código único de 12 dígitos
  is_redeemed BOOLEAN DEFAULT false,
  purchased_at TIMESTAMPTZ DEFAULT NOW(),
  redeemed_at TIMESTAMPTZ
);

-- Índices
CREATE INDEX IF NOT EXISTS idx_player_cards_player ON player_cards(player_id);
CREATE INDEX IF NOT EXISTS idx_player_cards_code ON player_cards(code);
CREATE INDEX IF NOT EXISTS idx_player_cards_unredeemed ON player_cards(player_id) WHERE is_redeemed = false;

-- =====================================================
-- FUNCIÓN PARA GENERAR CÓDIGO DE TARJETA
-- =====================================================

CREATE OR REPLACE FUNCTION generate_card_code()
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
  v_code TEXT;
  v_exists BOOLEAN;
BEGIN
  LOOP
    -- Generar código de 12 dígitos en formato XXXX-XXXX-XXXX
    v_code := UPPER(
      SUBSTRING(MD5(RANDOM()::TEXT || NOW()::TEXT) FROM 1 FOR 4) || '-' ||
      SUBSTRING(MD5(RANDOM()::TEXT || NOW()::TEXT) FROM 5 FOR 4) || '-' ||
      SUBSTRING(MD5(RANDOM()::TEXT || NOW()::TEXT) FROM 9 FOR 4)
    );

    -- Verificar que no existe
    SELECT EXISTS(SELECT 1 FROM player_cards WHERE code = v_code) INTO v_exists;

    IF NOT v_exists THEN
      RETURN v_code;
    END IF;
  END LOOP;
END;
$$;
