-- =====================================================
-- SISTEMA DE CLAIM PARA BLOQUES
-- Los bloques minados quedan pendientes hasta que el usuario los reclama
-- =====================================================

-- Agregar columnas necesarias a players si no existen
ALTER TABLE players ADD COLUMN IF NOT EXISTS blocks_mined INTEGER DEFAULT 0;
ALTER TABLE players ADD COLUMN IF NOT EXISTS total_crypto_earned DECIMAL(18, 8) DEFAULT 0;

-- Tabla para bloques pendientes de claim
CREATE TABLE IF NOT EXISTS pending_blocks (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  block_id UUID NOT NULL REFERENCES blocks(id) ON DELETE CASCADE,
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  reward DECIMAL(18, 8) NOT NULL,
  claimed BOOLEAN DEFAULT FALSE,
  claimed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(block_id)
);

-- Índices
CREATE INDEX IF NOT EXISTS idx_pending_blocks_player ON pending_blocks(player_id);
CREATE INDEX IF NOT EXISTS idx_pending_blocks_unclaimed ON pending_blocks(player_id) WHERE claimed = false;

-- Función para obtener bloques pendientes de un jugador
CREATE OR REPLACE FUNCTION get_pending_blocks(p_player_id UUID)
RETURNS TABLE(
  id UUID,
  block_id UUID,
  block_height INTEGER,
  reward DECIMAL,
  created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT
    pb.id,
    pb.block_id,
    b.height as block_height,
    pb.reward,
    pb.created_at
  FROM pending_blocks pb
  JOIN blocks b ON b.id = pb.block_id
  WHERE pb.player_id = p_player_id AND pb.claimed = false
  ORDER BY pb.created_at DESC;
END;
$$;

-- Función para reclamar un bloque
CREATE OR REPLACE FUNCTION claim_block(p_pending_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_pending pending_blocks%ROWTYPE;
  v_player_id UUID;
BEGIN
  -- Obtener el usuario actual
  v_player_id := auth.uid();

  IF v_player_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'No autenticado');
  END IF;

  -- Obtener el bloque pendiente
  SELECT * INTO v_pending FROM pending_blocks
  WHERE id = p_pending_id AND player_id = v_player_id AND claimed = false;

  IF v_pending.id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Bloque no encontrado o ya reclamado');
  END IF;

  -- Marcar como reclamado
  UPDATE pending_blocks
  SET claimed = true, claimed_at = NOW()
  WHERE id = p_pending_id;

  -- Acreditar la recompensa
  UPDATE players
  SET crypto_balance = crypto_balance + v_pending.reward,
      blocks_mined = COALESCE(blocks_mined, 0) + 1,
      total_crypto_earned = COALESCE(total_crypto_earned, 0) + v_pending.reward
  WHERE id = v_player_id;

  -- Registrar transacción
  INSERT INTO transactions (player_id, type, amount, currency, description)
  VALUES (v_player_id, 'block_claim', v_pending.reward, 'crypto',
          'Bloque reclamado');

  RETURN json_build_object(
    'success', true,
    'reward', v_pending.reward,
    'block_id', v_pending.block_id
  );
END;
$$;

-- Función para reclamar todos los bloques pendientes
CREATE OR REPLACE FUNCTION claim_all_blocks()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id UUID;
  v_total_reward DECIMAL := 0;
  v_count INTEGER := 0;
  v_pending RECORD;
BEGIN
  v_player_id := auth.uid();

  IF v_player_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'No autenticado');
  END IF;

  -- Sumar todas las recompensas pendientes
  FOR v_pending IN
    SELECT id, reward FROM pending_blocks
    WHERE player_id = v_player_id AND claimed = false
  LOOP
    v_total_reward := v_total_reward + v_pending.reward;
    v_count := v_count + 1;

    UPDATE pending_blocks
    SET claimed = true, claimed_at = NOW()
    WHERE id = v_pending.id;
  END LOOP;

  IF v_count = 0 THEN
    RETURN json_build_object('success', false, 'error', 'No hay bloques pendientes');
  END IF;

  -- Acreditar todas las recompensas
  UPDATE players
  SET crypto_balance = crypto_balance + v_total_reward,
      blocks_mined = COALESCE(blocks_mined, 0) + v_count,
      total_crypto_earned = COALESCE(total_crypto_earned, 0) + v_total_reward
  WHERE id = v_player_id;

  -- Registrar transacción
  INSERT INTO transactions (player_id, type, amount, currency, description)
  VALUES (v_player_id, 'block_claim_all', v_total_reward, 'crypto',
          'Reclamados ' || v_count || ' bloques');

  RETURN json_build_object(
    'success', true,
    'total_reward', v_total_reward,
    'blocks_claimed', v_count
  );
END;
$$;

-- Función para contar bloques pendientes
CREATE OR REPLACE FUNCTION get_pending_blocks_count(p_player_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_count INTEGER;
  v_total_reward DECIMAL;
BEGIN
  SELECT COUNT(*), COALESCE(SUM(reward), 0)
  INTO v_count, v_total_reward
  FROM pending_blocks
  WHERE player_id = p_player_id AND claimed = false;

  RETURN json_build_object(
    'count', v_count,
    'total_reward', v_total_reward
  );
END;
$$;

-- RLS Policies
ALTER TABLE pending_blocks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own pending blocks" ON pending_blocks;
CREATE POLICY "Users can view own pending blocks" ON pending_blocks
  FOR SELECT USING (auth.uid() = player_id);

DROP POLICY IF EXISTS "System can insert pending blocks" ON pending_blocks;
CREATE POLICY "System can insert pending blocks" ON pending_blocks
  FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "Users can update own pending blocks" ON pending_blocks;
CREATE POLICY "Users can update own pending blocks" ON pending_blocks
  FOR UPDATE USING (auth.uid() = player_id);
