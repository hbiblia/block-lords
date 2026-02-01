-- =====================================================
-- BLOCK LORDS - RON Deposit System
-- =====================================================
-- Permite a los usuarios recargar RON en su cuenta
-- usando la wallet de Ronin

-- =====================================================
-- TABLA DE DEPOSITOS DE RON (HISTORIAL)
-- =====================================================

CREATE TABLE IF NOT EXISTS ron_deposits (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  amount DECIMAL(18, 8) NOT NULL CHECK (amount > 0),
  tx_hash TEXT NOT NULL UNIQUE, -- Hash de transaccion en Ronin
  status TEXT NOT NULL DEFAULT 'completed' CHECK (status IN ('pending', 'completed', 'failed')),
  deposited_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indices
CREATE INDEX IF NOT EXISTS idx_ron_deposits_player ON ron_deposits(player_id);
CREATE INDEX IF NOT EXISTS idx_ron_deposits_tx ON ron_deposits(tx_hash);
CREATE INDEX IF NOT EXISTS idx_ron_deposits_status ON ron_deposits(status);

-- =====================================================
-- FUNCION: deposit_ron
-- =====================================================
-- Deposita RON en la cuenta del jugador despues de
-- verificar la transaccion en la blockchain

CREATE OR REPLACE FUNCTION deposit_ron(
  p_player_id UUID,
  p_amount DECIMAL,
  p_tx_hash TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_existing_id UUID;
  v_new_balance DECIMAL;
BEGIN
  -- Validar parametros
  IF p_amount <= 0 THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Cantidad invalida'
    );
  END IF;

  IF p_tx_hash IS NULL OR p_tx_hash = '' THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Hash de transaccion requerido'
    );
  END IF;

  -- Verificar que tx_hash no haya sido usado antes (previene doble deposito)
  SELECT id INTO v_existing_id
  FROM ron_deposits
  WHERE tx_hash = p_tx_hash
  LIMIT 1;

  IF v_existing_id IS NOT NULL THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Transaccion ya procesada'
    );
  END IF;

  -- Tambien verificar en crypto_purchases (por si acaso)
  SELECT id INTO v_existing_id
  FROM crypto_purchases
  WHERE tx_hash = p_tx_hash
  LIMIT 1;

  IF v_existing_id IS NOT NULL THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Transaccion ya utilizada para otra compra'
    );
  END IF;

  -- Registrar el deposito
  INSERT INTO ron_deposits (
    player_id,
    amount,
    tx_hash,
    status
  ) VALUES (
    p_player_id,
    p_amount,
    p_tx_hash,
    'completed'
  );

  -- Acreditar RON al jugador
  UPDATE players
  SET ron_balance = ron_balance + p_amount,
      updated_at = NOW()
  WHERE id = p_player_id
  RETURNING ron_balance INTO v_new_balance;

  -- Registrar transaccion
  INSERT INTO transactions (
    player_id,
    type,
    amount,
    currency,
    description
  ) VALUES (
    p_player_id,
    'ron_deposit',
    p_amount,
    'ron',
    'Deposito de RON via Ronin Wallet'
  );

  RETURN json_build_object(
    'success', true,
    'amount', p_amount,
    'new_balance', v_new_balance
  );
END;
$$;

-- =====================================================
-- FUNCION: get_ron_deposit_history
-- =====================================================
-- Obtiene el historial de depositos de un jugador

CREATE OR REPLACE FUNCTION get_ron_deposit_history(
  p_player_id UUID,
  p_limit INTEGER DEFAULT 10
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN (
    SELECT COALESCE(json_agg(d ORDER BY d.deposited_at DESC), '[]'::json)
    FROM (
      SELECT
        id,
        amount,
        tx_hash,
        status,
        deposited_at
      FROM ron_deposits
      WHERE player_id = p_player_id
      ORDER BY deposited_at DESC
      LIMIT p_limit
    ) d
  );
END;
$$;
