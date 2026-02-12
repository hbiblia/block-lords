-- =====================================================
-- FIX: Battle Lobby Orphaned States
-- =====================================================
-- This migration fixes players stuck in "matched" status
-- without an active ready room or battle session.
-- =====================================================

-- 1) Update cleanup function to handle orphaned "matched" entries
CREATE OR REPLACE FUNCTION cleanup_expired_battle_challenges()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_cleaned_challenges INTEGER;
  v_cleaned_orphans INTEGER;
BEGIN
  -- Cleanup expired challenges
  UPDATE battle_lobby
  SET status = 'waiting',
      challenged_by = NULL,
      proposed_bet = NULL,
      proposed_currency = NULL,
      challenge_expires_at = NULL,
      challenger_username = NULL
  WHERE status = 'challenged'
    AND challenge_expires_at < NOW();

  GET DIAGNOSTICS v_cleaned_challenges = ROW_COUNT;

  -- Cleanup orphaned 'matched' entries (no ready room or active session)
  UPDATE battle_lobby bl
  SET status = 'waiting',
      challenged_by = NULL,
      proposed_bet = NULL,
      proposed_currency = NULL,
      challenge_expires_at = NULL,
      challenger_username = NULL
  WHERE bl.status = 'matched'
    AND NOT EXISTS (
      SELECT 1 FROM battle_ready_rooms brr
      WHERE (brr.player1_id = bl.player_id OR brr.player2_id = bl.player_id)
        AND brr.expires_at > NOW()
    )
    AND NOT EXISTS (
      SELECT 1 FROM battle_sessions bs
      WHERE (bs.player1_id = bl.player_id OR bs.player2_id = bl.player_id)
        AND bs.status = 'active'
    );

  GET DIAGNOSTICS v_cleaned_orphans = ROW_COUNT;

  -- Delete expired ready rooms (older than 5 minutes)
  DELETE FROM battle_ready_rooms WHERE expires_at < NOW();

  RETURN json_build_object(
    'success', true,
    'cleaned_challenges', v_cleaned_challenges,
    'cleaned_orphans', v_cleaned_orphans
  );
END;
$$;

-- 2) Update get_battle_lobby to auto-cleanup on load
CREATE OR REPLACE FUNCTION get_battle_lobby(p_player_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_lobby JSONB;
  v_active_session JSONB;
  v_ready_room JSONB;
  v_my_challenges JSONB;
  v_pending_challenges JSONB;
  v_my_status TEXT;
  v_my_gc_balance NUMERIC;
  v_my_blc_balance NUMERIC;
  v_my_ron_balance NUMERIC;
BEGIN
  -- Cleanup expired challenges and orphaned entries first
  PERFORM cleanup_expired_battle_challenges();

  -- Get my balances
  SELECT gamecoin_balance, crypto_balance, ron_balance
  INTO v_my_gc_balance, v_my_blc_balance, v_my_ron_balance
  FROM players WHERE id = p_player_id;

  -- (rest of function remains the same...)
  -- Get waiting lobby entries (exclude self) with battle stats, challenge info, and balances
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', bl.id,
    'player_id', bl.player_id,
    'username', bl.username,
    'status', bl.status,
    'challenged_by', bl.challenged_by,
    'challenger_username', bl.challenger_username,
    'proposed_bet', bl.proposed_bet,
    'proposed_currency', bl.proposed_currency,
    'challenge_expires_at', bl.challenge_expires_at,
    'created_at', bl.created_at,
    'wins', COALESCE(stats.wins, 0),
    'losses', COALESCE(stats.losses, 0),
    'gamecoin_balance', p.gamecoin_balance,
    'crypto_balance', p.crypto_balance,
    'ron_balance', p.ron_balance,
    'available_bets', jsonb_build_array(
      jsonb_build_object('amount', 100, 'currency', 'GC', 'enabled', v_my_gc_balance >= 100 AND p.gamecoin_balance >= 100),
      jsonb_build_object('amount', 2500, 'currency', 'GC', 'enabled', v_my_gc_balance >= 2500 AND p.gamecoin_balance >= 2500),
      jsonb_build_object('amount', 1000, 'currency', 'BLC', 'enabled', v_my_blc_balance >= 1000 AND p.crypto_balance >= 1000),
      jsonb_build_object('amount', 2500, 'currency', 'BLC', 'enabled', v_my_blc_balance >= 2500 AND p.crypto_balance >= 2500),
      jsonb_build_object('amount', 0.2, 'currency', 'RON', 'enabled', v_my_ron_balance >= 0.2 AND p.ron_balance >= 0.2),
      jsonb_build_object('amount', 1, 'currency', 'RON', 'enabled', v_my_ron_balance >= 1 AND p.ron_balance >= 1)
    )
  )), '[]'::JSONB) INTO v_lobby
  FROM battle_lobby bl
  LEFT JOIN players p ON p.id = bl.player_id
  LEFT JOIN LATERAL (
    SELECT
      COUNT(*) FILTER (WHERE bs.winner_id = bl.player_id) AS wins,
      COUNT(*) FILTER (
        WHERE bs.status IN ('completed', 'forfeited')
          AND bs.winner_id IS NOT NULL
          AND bs.winner_id != bl.player_id
      ) AS losses
    FROM battle_sessions bs
    WHERE (bs.player1_id = bl.player_id OR bs.player2_id = bl.player_id)
      AND bs.status IN ('completed', 'forfeited')
  ) stats ON true
  WHERE bl.player_id != p_player_id AND bl.status IN ('waiting', 'challenged');

  -- Get my outgoing challenges (challenges I sent)
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'opponent_id', bl.player_id,
    'opponent_username', bl.username,
    'proposed_bet', bl.proposed_bet,
    'proposed_currency', bl.proposed_currency,
    'expires_at', bl.challenge_expires_at
  )), '[]'::JSONB) INTO v_my_challenges
  FROM battle_lobby bl
  WHERE bl.challenged_by = p_player_id AND bl.status = 'challenged';

  -- Get challenges to me (incoming challenges)
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'challenger_id', bl.challenged_by,
    'challenger_username', bl.challenger_username,
    'proposed_bet', bl.proposed_bet,
    'proposed_currency', bl.proposed_currency,
    'expires_at', bl.challenge_expires_at
  )), '[]'::JSONB) INTO v_pending_challenges
  FROM battle_lobby bl
  WHERE bl.player_id = p_player_id AND bl.status = 'challenged';

  -- Get my lobby status
  SELECT status INTO v_my_status
  FROM battle_lobby
  WHERE player_id = p_player_id
  LIMIT 1;

  -- Check for active session
  SELECT jsonb_build_object(
    'id', id,
    'player1_id', player1_id,
    'player2_id', player2_id,
    'current_turn', current_turn,
    'turn_number', turn_number,
    'turn_deadline', turn_deadline,
    'player1_hp', player1_hp,
    'player2_hp', player2_hp,
    'player1_shield', player1_shield,
    'player2_shield', player2_shield,
    'game_state', game_state,
    'status', status,
    'winner_id', winner_id,
    'bet_amount', bet_amount,
    'bet_currency', bet_currency
  ) INTO v_active_session
  FROM battle_sessions
  WHERE (player1_id = p_player_id OR player2_id = p_player_id) AND status = 'active'
  ORDER BY started_at DESC
  LIMIT 1;

  -- Check for ready room (includes per-player bet selections)
  SELECT jsonb_build_object(
    'id', id,
    'player1_id', player1_id,
    'player2_id', player2_id,
    'player1_username', player1_username,
    'player2_username', player2_username,
    'player1_ready', player1_ready,
    'player2_ready', player2_ready,
    'bet_amount', bet_amount,
    'bet_currency', bet_currency,
    'player1_bet_amount', COALESCE(player1_bet_amount, 0),
    'player1_bet_currency', COALESCE(player1_bet_currency, 'GC'),
    'player2_bet_amount', COALESCE(player2_bet_amount, 0),
    'player2_bet_currency', COALESCE(player2_bet_currency, 'GC'),
    'expires_at', expires_at
  ) INTO v_ready_room
  FROM battle_ready_rooms
  WHERE (player1_id = p_player_id OR player2_id = p_player_id) AND expires_at > NOW()
  ORDER BY created_at DESC
  LIMIT 1;

  RETURN json_build_object(
    'success', true,
    'lobby', v_lobby,
    'active_session', v_active_session,
    'ready_room', v_ready_room,
    'my_challenges', v_my_challenges,
    'pending_challenges', v_pending_challenges,
    'in_lobby', EXISTS(SELECT 1 FROM battle_lobby WHERE player_id = p_player_id),
    'my_status', v_my_status,
    'my_balances', json_build_object(
      'gamecoin', v_my_gc_balance,
      'blockcoin', v_my_blc_balance,
      'ronin', v_my_ron_balance
    )
  );
END;
$$;

-- 3) Update leave_battle_lobby to allow leaving from any state (except active battle)
CREATE OR REPLACE FUNCTION leave_battle_lobby(p_player_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_lobby battle_lobby%ROWTYPE;
  v_has_active_battle BOOLEAN;
BEGIN
  SELECT * INTO v_lobby
  FROM battle_lobby
  WHERE player_id = p_player_id;

  IF v_lobby.id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not in lobby');
  END IF;

  -- Check if player has active battle or ready room (can't leave if in active game)
  SELECT EXISTS (
    SELECT 1 FROM battle_sessions
    WHERE (player1_id = p_player_id OR player2_id = p_player_id) AND status = 'active'
    UNION ALL
    SELECT 1 FROM battle_ready_rooms
    WHERE (player1_id = p_player_id OR player2_id = p_player_id) AND expires_at > NOW()
  ) INTO v_has_active_battle;

  IF v_has_active_battle THEN
    RETURN json_build_object('success', false, 'error', 'Cannot leave while in active battle or ready room');
  END IF;

  -- Clear any challenges to this player
  UPDATE battle_lobby
  SET status = 'waiting', challenged_by = NULL, proposed_bet = NULL,
      proposed_currency = NULL, challenge_expires_at = NULL, challenger_username = NULL
  WHERE challenged_by = p_player_id;

  -- Remove from lobby
  DELETE FROM battle_lobby WHERE id = v_lobby.id;

  RETURN json_build_object('success', true);
END;
$$;

-- 4) Grant execute permission
GRANT EXECUTE ON FUNCTION cleanup_expired_battle_challenges TO authenticated;

-- 5) Run immediate cleanup to fix any current orphaned entries
SELECT cleanup_expired_battle_challenges();
