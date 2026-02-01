-- =====================================================
-- SISTEMA DE SUSCRIPCIÓN PREMIUM
-- Premium da +50% crypto por bloque y 10% fee de retiro
-- =====================================================

-- Configuración del premium
-- PREMIUM_PRICE: 2.5 RON/mes
-- PREMIUM_BLOCK_BONUS: 1.5 (50% más crypto)
-- PREMIUM_WITHDRAWAL_FEE: 0.10 (10% vs 25% normal)

-- Tabla de suscripciones premium
CREATE TABLE IF NOT EXISTS premium_subscriptions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  starts_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL,
  amount_paid DECIMAL(18, 8) NOT NULL,
  tx_type TEXT DEFAULT 'ron_balance', -- 'ron_balance' o 'direct_payment'
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Índices
CREATE INDEX IF NOT EXISTS idx_premium_player ON premium_subscriptions(player_id);
CREATE INDEX IF NOT EXISTS idx_premium_expires ON premium_subscriptions(expires_at);
CREATE INDEX IF NOT EXISTS idx_premium_active ON premium_subscriptions(player_id, expires_at);

-- Agregar columna is_premium a players para cache rápido
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'players' AND column_name = 'premium_until') THEN
    ALTER TABLE players ADD COLUMN premium_until TIMESTAMPTZ;
  END IF;
END $$;

-- Función para verificar si un jugador tiene premium activo
CREATE OR REPLACE FUNCTION is_player_premium(p_player_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_premium_until TIMESTAMPTZ;
BEGIN
  SELECT premium_until INTO v_premium_until
  FROM players WHERE id = p_player_id;

  RETURN COALESCE(v_premium_until > NOW(), false);
END;
$$;

-- Función para obtener el multiplicador de recompensa de bloque
-- Premium: 1.5 (50% más), Normal: 1.0
CREATE OR REPLACE FUNCTION get_block_reward_multiplier(p_player_id UUID)
RETURNS DECIMAL
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF is_player_premium(p_player_id) THEN
    RETURN 1.5; -- +50% crypto
  ELSE
    RETURN 1.0;
  END IF;
END;
$$;

-- Función para obtener la tasa de comisión de retiro
-- Premium: 0.10 (10%), Normal: 0.25 (25%)
CREATE OR REPLACE FUNCTION get_withdrawal_fee_rate(p_player_id UUID)
RETURNS DECIMAL
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF is_player_premium(p_player_id) THEN
    RETURN 0.10; -- 10% fee
  ELSE
    RETURN 0.25; -- 25% fee
  END IF;
END;
$$;

-- Función para comprar suscripción premium
CREATE OR REPLACE FUNCTION purchase_premium(p_player_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player players%ROWTYPE;
  v_price DECIMAL := 2.5; -- 2.5 RON/mes
  v_duration INTERVAL := '30 days';
  v_new_expires TIMESTAMPTZ;
  v_subscription_id UUID;
BEGIN
  -- Obtener jugador
  SELECT * INTO v_player FROM players WHERE id = p_player_id;

  IF v_player.id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Jugador no encontrado');
  END IF;

  -- Verificar balance
  IF COALESCE(v_player.ron_balance, 0) < v_price THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Balance insuficiente. Necesitas ' || v_price || ' RON',
      'required', v_price,
      'current', COALESCE(v_player.ron_balance, 0)
    );
  END IF;

  -- Calcular nueva fecha de expiración
  -- Si ya tiene premium activo, extender desde la fecha actual de expiración
  IF v_player.premium_until IS NOT NULL AND v_player.premium_until > NOW() THEN
    v_new_expires := v_player.premium_until + v_duration;
  ELSE
    v_new_expires := NOW() + v_duration;
  END IF;

  -- Descontar RON
  UPDATE players
  SET ron_balance = ron_balance - v_price,
      premium_until = v_new_expires
  WHERE id = p_player_id;

  -- Registrar suscripción
  INSERT INTO premium_subscriptions (player_id, expires_at, amount_paid)
  VALUES (p_player_id, v_new_expires, v_price)
  RETURNING id INTO v_subscription_id;

  -- Registrar transacción
  INSERT INTO transactions (player_id, type, amount, currency, description)
  VALUES (p_player_id, 'premium_purchase', -v_price, 'ron',
          'Suscripción Premium (30 días) - +50% crypto, 10% fee retiro');

  RETURN json_build_object(
    'success', true,
    'subscription_id', v_subscription_id,
    'expires_at', v_new_expires,
    'price', v_price,
    'new_balance', v_player.ron_balance - v_price
  );
END;
$$;

-- Función para obtener estado premium del jugador
CREATE OR REPLACE FUNCTION get_premium_status(p_player_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player players%ROWTYPE;
  v_is_premium BOOLEAN;
  v_days_remaining INTEGER;
  v_price DECIMAL := 2.5;
BEGIN
  SELECT * INTO v_player FROM players WHERE id = p_player_id;

  IF v_player.id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Jugador no encontrado');
  END IF;

  v_is_premium := COALESCE(v_player.premium_until > NOW(), false);

  IF v_is_premium THEN
    v_days_remaining := EXTRACT(DAY FROM (v_player.premium_until - NOW()))::INTEGER;
  ELSE
    v_days_remaining := 0;
  END IF;

  RETURN json_build_object(
    'success', true,
    'is_premium', v_is_premium,
    'expires_at', v_player.premium_until,
    'days_remaining', v_days_remaining,
    'price', v_price,
    'benefits', json_build_object(
      'block_bonus', '+50%',
      'withdrawal_fee', '10%'
    )
  );
END;
$$;

-- Función para obtener historial de suscripciones
CREATE OR REPLACE FUNCTION get_premium_history(p_player_id UUID, p_limit INTEGER DEFAULT 10)
RETURNS TABLE(
  id UUID,
  starts_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ,
  amount_paid DECIMAL,
  created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT
    ps.id,
    ps.starts_at,
    ps.expires_at,
    ps.amount_paid,
    ps.created_at
  FROM premium_subscriptions ps
  WHERE ps.player_id = p_player_id
  ORDER BY ps.created_at DESC
  LIMIT p_limit;
END;
$$;

-- Actualizar request_ron_withdrawal para usar fee dinámico según premium
CREATE OR REPLACE FUNCTION request_ron_withdrawal(p_player_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player players%ROWTYPE;
  v_pending_count INTEGER;
  v_withdrawal_id UUID;
  v_min_withdrawal DECIMAL := 0.01;
  v_fee_rate DECIMAL;
  v_fee DECIMAL;
  v_net_amount DECIMAL;
  v_is_premium BOOLEAN;
BEGIN
  -- Verificar jugador
  SELECT * INTO v_player FROM players WHERE id = p_player_id;

  IF v_player.id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Jugador no encontrado');
  END IF;

  -- Verificar wallet
  IF v_player.ron_wallet IS NULL OR v_player.ron_wallet = '' THEN
    RETURN json_build_object('success', false, 'error', 'No tienes una wallet configurada');
  END IF;

  -- Verificar balance
  IF COALESCE(v_player.ron_balance, 0) < v_min_withdrawal THEN
    RETURN json_build_object('success', false, 'error', 'Balance insuficiente. Minimo: ' || v_min_withdrawal || ' RON');
  END IF;

  -- Obtener fee rate según premium
  v_is_premium := is_player_premium(p_player_id);
  v_fee_rate := get_withdrawal_fee_rate(p_player_id);

  -- Calcular comisión y monto neto
  v_fee := ROUND(v_player.ron_balance * v_fee_rate, 8);
  v_net_amount := v_player.ron_balance - v_fee;

  -- Verificar que no tenga retiros pendientes
  SELECT COUNT(*) INTO v_pending_count
  FROM ron_withdrawals
  WHERE player_id = p_player_id AND status IN ('pending', 'processing');

  IF v_pending_count > 0 THEN
    RETURN json_build_object('success', false, 'error', 'Ya tienes un retiro en proceso');
  END IF;

  -- Crear solicitud de retiro con comisión
  INSERT INTO ron_withdrawals (player_id, amount, fee, net_amount, wallet_address, status)
  VALUES (p_player_id, v_player.ron_balance, v_fee, v_net_amount, v_player.ron_wallet, 'pending')
  RETURNING id INTO v_withdrawal_id;

  -- Descontar balance (reservar fondos)
  UPDATE players
  SET ron_balance = 0
  WHERE id = p_player_id;

  -- Registrar transacción
  INSERT INTO transactions (player_id, type, amount, currency, description)
  VALUES (p_player_id, 'ron_withdrawal', -v_player.ron_balance, 'ron',
          'Retiro de ' || v_net_amount || ' RON (comision ' || (v_fee_rate * 100)::INTEGER || '%: ' || v_fee || ') a ' ||
          SUBSTRING(v_player.ron_wallet FROM 1 FOR 6) || '...' ||
          SUBSTRING(v_player.ron_wallet FROM LENGTH(v_player.ron_wallet) - 3));

  RETURN json_build_object(
    'success', true,
    'withdrawal_id', v_withdrawal_id,
    'amount', v_player.ron_balance,
    'fee', v_fee,
    'fee_rate', v_fee_rate,
    'net_amount', v_net_amount,
    'wallet', v_player.ron_wallet,
    'is_premium', v_is_premium
  );
END;
$$;

-- RLS para premium_subscriptions
ALTER TABLE premium_subscriptions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Ver propias suscripciones" ON premium_subscriptions;
CREATE POLICY "Ver propias suscripciones"
  ON premium_subscriptions FOR SELECT
  USING (auth.uid() = player_id);

-- =====================================================
-- ACTUALIZAR process_mining_tick PARA APLICAR BONUS PREMIUM
-- =====================================================
CREATE OR REPLACE FUNCTION process_mining_tick()
RETURNS TABLE(block_mined BOOLEAN, block_height INT)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_network_hashrate NUMERIC := 0;
  v_difficulty NUMERIC;
  v_block_probability NUMERIC;
  v_roll NUMERIC;
  v_winner_player_id UUID;
  v_block blocks%ROWTYPE;
  v_reward NUMERIC;
  v_premium_multiplier NUMERIC;
  v_rig RECORD;
  v_effective_hashrate NUMERIC;
  v_rep_multiplier NUMERIC;
  v_hashrate_sum NUMERIC := 0;
  v_random_pick NUMERIC;
  v_temp_penalty NUMERIC;
  v_condition_penalty NUMERIC;
  v_boosts JSON;
  v_hashrate_mult NUMERIC;
  v_luck_mult NUMERIC;
  v_current_player_id UUID := NULL;
  v_total_luck_mult NUMERIC := 1.0;
  v_luck_count INTEGER := 0;
BEGIN
  SELECT COALESCE(ns.difficulty, 1000) INTO v_difficulty FROM network_stats ns WHERE ns.id = 'current';
  IF v_difficulty IS NULL THEN v_difficulty := 1000; END IF;

  -- Calcular hashrate total
  FOR v_rig IN
    SELECT pr.id as rig_id, pr.player_id, pr.condition, pr.temperature, r.hashrate, p.reputation_score
    FROM player_rigs pr
    JOIN rigs r ON r.id = pr.rig_id
    JOIN players p ON p.id = pr.player_id
    WHERE pr.is_active = true AND p.energy > 0 AND p.internet > 0
      AND (p.is_online = true OR rig_has_autonomous_boost(pr.id))
  LOOP
    IF v_current_player_id IS DISTINCT FROM v_rig.player_id THEN
      v_boosts := get_active_boost_multipliers(v_rig.player_id);
      v_hashrate_mult := COALESCE((v_boosts->>'hashrate')::NUMERIC, 1.0);
      v_luck_mult := COALESCE((v_boosts->>'luck')::NUMERIC, 1.0);
      v_current_player_id := v_rig.player_id;
      IF v_luck_mult > 1.0 THEN
        v_total_luck_mult := v_total_luck_mult + (v_luck_mult - 1.0);
        v_luck_count := v_luck_count + 1;
      END IF;
    END IF;

    IF v_rig.reputation_score >= 80 THEN
      v_rep_multiplier := 1 + (v_rig.reputation_score - 80) * 0.01;
    ELSIF v_rig.reputation_score < 50 THEN
      v_rep_multiplier := 0.5 + (v_rig.reputation_score / 100.0);
    ELSE
      v_rep_multiplier := 1;
    END IF;

    v_temp_penalty := 1;
    IF v_rig.temperature > 50 THEN
      v_temp_penalty := 1 - ((v_rig.temperature - 50) * 0.014);
      v_temp_penalty := GREATEST(0.3, v_temp_penalty);
    END IF;

    v_condition_penalty := 0.2 + (v_rig.condition / 100.0) * 0.8;

    v_effective_hashrate := v_rig.hashrate * v_condition_penalty * v_rep_multiplier * v_temp_penalty * v_hashrate_mult;
    v_network_hashrate := v_network_hashrate + v_effective_hashrate;
  END LOOP;

  -- Actualizar hashrate de red
  INSERT INTO network_stats (id, difficulty, hashrate, active_miners, updated_at)
  VALUES ('current', v_difficulty, v_network_hashrate,
          (SELECT COUNT(DISTINCT player_id) FROM player_rigs WHERE is_active = true),
          NOW())
  ON CONFLICT (id) DO UPDATE SET
    hashrate = v_network_hashrate,
    active_miners = (SELECT COUNT(DISTINCT player_id) FROM player_rigs WHERE is_active = true),
    updated_at = NOW();

  IF v_network_hashrate = 0 THEN
    RETURN QUERY SELECT false, NULL::INT;
    RETURN;
  END IF;

  -- Probabilidad de minar
  IF v_luck_count > 0 THEN
    v_total_luck_mult := v_total_luck_mult / v_luck_count;
  END IF;
  v_block_probability := (v_network_hashrate / v_difficulty) * v_total_luck_mult;
  v_roll := random();

  IF v_roll > v_block_probability THEN
    RETURN QUERY SELECT false, NULL::INT;
    RETURN;
  END IF;

  -- Seleccionar ganador
  v_random_pick := random() * v_network_hashrate;
  v_hashrate_sum := 0;
  v_current_player_id := NULL;

  FOR v_rig IN
    SELECT pr.id as rig_id, pr.player_id, pr.condition, pr.temperature, r.hashrate, p.reputation_score
    FROM player_rigs pr
    JOIN rigs r ON r.id = pr.rig_id
    JOIN players p ON p.id = pr.player_id
    WHERE pr.is_active = true AND p.energy > 0 AND p.internet > 0
      AND (p.is_online = true OR rig_has_autonomous_boost(pr.id))
  LOOP
    IF v_current_player_id IS DISTINCT FROM v_rig.player_id THEN
      v_boosts := get_active_boost_multipliers(v_rig.player_id);
      v_hashrate_mult := COALESCE((v_boosts->>'hashrate')::NUMERIC, 1.0);
      v_current_player_id := v_rig.player_id;
    END IF;

    IF v_rig.reputation_score >= 80 THEN
      v_rep_multiplier := 1 + (v_rig.reputation_score - 80) * 0.01;
    ELSIF v_rig.reputation_score < 50 THEN
      v_rep_multiplier := 0.5 + (v_rig.reputation_score / 100.0);
    ELSE
      v_rep_multiplier := 1;
    END IF;

    v_temp_penalty := 1;
    IF v_rig.temperature > 50 THEN
      v_temp_penalty := 1 - ((v_rig.temperature - 50) * 0.014);
      v_temp_penalty := GREATEST(0.3, v_temp_penalty);
    END IF;

    v_condition_penalty := 0.2 + (v_rig.condition / 100.0) * 0.8;

    v_effective_hashrate := v_rig.hashrate * v_condition_penalty * v_rep_multiplier * v_temp_penalty * v_hashrate_mult;
    v_hashrate_sum := v_hashrate_sum + v_effective_hashrate;

    IF v_hashrate_sum >= v_random_pick THEN
      v_winner_player_id := v_rig.player_id;
      EXIT;
    END IF;
  END LOOP;

  IF v_winner_player_id IS NULL THEN
    RETURN QUERY SELECT false, NULL::INT;
    RETURN;
  END IF;

  -- Crear bloque
  v_block := create_new_block(v_winner_player_id, v_difficulty, v_network_hashrate);

  IF v_block.id IS NULL THEN
    RETURN QUERY SELECT false, NULL::INT;
    RETURN;
  END IF;

  -- Calcular recompensa base
  v_reward := calculate_block_reward(v_block.height);

  -- ============================================
  -- APLICAR BONUS PREMIUM (+50% si es premium)
  -- ============================================
  v_premium_multiplier := get_block_reward_multiplier(v_winner_player_id);
  v_reward := v_reward * v_premium_multiplier;

  -- Guardar en pending_blocks con recompensa ya multiplicada
  INSERT INTO pending_blocks (block_id, player_id, reward)
  VALUES (v_block.id, v_winner_player_id, v_reward);

  -- Actualizar reputación
  PERFORM update_reputation(v_winner_player_id, 0.1, 'block_mined');

  RETURN QUERY SELECT true, v_block.height;
END;
$$;
