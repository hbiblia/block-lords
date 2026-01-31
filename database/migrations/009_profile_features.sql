-- =====================================================
-- PROFILE FEATURES - Wallet y Reset Account
-- =====================================================

-- Add RON wallet column to players if not exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'players' AND column_name = 'ron_wallet'
  ) THEN
    ALTER TABLE players ADD COLUMN ron_wallet TEXT DEFAULT NULL;
  END IF;
END $$;

-- =====================================================
-- FUNCIÓN: Actualizar wallet RON
-- =====================================================

CREATE OR REPLACE FUNCTION update_ron_wallet(
  p_player_id UUID,
  p_wallet_address TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_clean_wallet TEXT;
BEGIN
  -- Validate player exists
  IF NOT EXISTS (SELECT 1 FROM players WHERE id = p_player_id) THEN
    RETURN json_build_object('success', false, 'error', 'Jugador no encontrado');
  END IF;

  -- Clean and validate wallet address (basic RON/Ethereum format validation)
  v_clean_wallet := TRIM(p_wallet_address);

  -- Allow null/empty to clear wallet
  IF v_clean_wallet IS NULL OR v_clean_wallet = '' THEN
    UPDATE players SET ron_wallet = NULL, updated_at = NOW() WHERE id = p_player_id;
    RETURN json_build_object('success', true, 'wallet', NULL);
  END IF;

  -- Basic validation: starts with 0x and is 42 chars (Ethereum/RON format)
  IF NOT (v_clean_wallet ~* '^0x[a-fA-F0-9]{40}$') THEN
    RETURN json_build_object('success', false, 'error', 'Formato de wallet inválido. Debe ser una dirección válida (0x...)');
  END IF;

  -- Update wallet
  UPDATE players
  SET ron_wallet = v_clean_wallet, updated_at = NOW()
  WHERE id = p_player_id;

  RETURN json_build_object('success', true, 'wallet', v_clean_wallet);
END;
$$;

-- =====================================================
-- FUNCIÓN: Reiniciar cuenta (soft reset)
-- =====================================================

CREATE OR REPLACE FUNCTION reset_player_account(
  p_player_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player RECORD;
BEGIN
  -- Get player
  SELECT * INTO v_player FROM players WHERE id = p_player_id;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'Jugador no encontrado');
  END IF;

  -- Delete all player rigs
  DELETE FROM player_rigs WHERE player_id = p_player_id;

  -- Delete all player inventory (cooling items)
  DELETE FROM player_cooling WHERE player_id = p_player_id;

  -- Delete player prepaid cards
  DELETE FROM player_cards WHERE player_id = p_player_id;

  -- Delete player boosts
  DELETE FROM player_boosts WHERE player_id = p_player_id;
  DELETE FROM active_boosts WHERE player_id = p_player_id;

  -- Delete player missions progress
  DELETE FROM player_missions WHERE player_id = p_player_id;

  -- Delete streak data
  DELETE FROM player_streaks WHERE player_id = p_player_id;
  DELETE FROM streak_claims WHERE player_id = p_player_id;

  -- Delete market listings
  DELETE FROM market_listings WHERE seller_id = p_player_id;

  -- Delete transactions history
  DELETE FROM transactions WHERE player_id = p_player_id;

  -- Reset player stats to initial values
  UPDATE players SET
    gamecoin_balance = 1000,
    crypto_balance = 0,
    energy = 100,
    internet = 100,
    reputation_score = 50,
    rig_slots = 1,
    blocks_mined = 0,
    total_crypto_earned = 0,
    updated_at = NOW()
  WHERE id = p_player_id;

  -- Give starter rig
  INSERT INTO player_rigs (player_id, rig_id, condition, is_active)
  VALUES (p_player_id, 'basic_miner', 100, false);

  -- Log the reset
  INSERT INTO transactions (player_id, type, amount, currency, description)
  VALUES (p_player_id, 'account_reset', 1000, 'gamecoin', 'Cuenta reiniciada - Balance inicial');

  RETURN json_build_object(
    'success', true,
    'message', 'Cuenta reiniciada exitosamente'
  );
END;
$$;
