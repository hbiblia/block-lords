-- =====================================================
-- CRYPTO ARCADE MMO - Funciones del Juego
-- Toda la lógica de backend en SQL
-- =====================================================

-- =====================================================
-- FUNCIONES DE AUTENTICACIÓN Y REGISTRO
-- =====================================================

-- Crear perfil de jugador después del registro
CREATE OR REPLACE FUNCTION create_player_profile(
  p_user_id UUID,
  p_email TEXT,
  p_username TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player players%ROWTYPE;
BEGIN
  -- Validar username
  IF LENGTH(p_username) < 3 OR LENGTH(p_username) > 20 THEN
    RETURN json_build_object('success', false, 'error', 'El username debe tener entre 3 y 20 caracteres');
  END IF;

  IF p_username !~ '^[a-zA-Z0-9_]+$' THEN
    RETURN json_build_object('success', false, 'error', 'El username solo puede contener letras, números y guiones bajos');
  END IF;

  -- Verificar username único
  IF EXISTS (SELECT 1 FROM players WHERE username = p_username) THEN
    RETURN json_build_object('success', false, 'error', 'El nombre de usuario ya está en uso');
  END IF;

  -- Crear jugador
  INSERT INTO players (id, email, username, gamecoin_balance, crypto_balance, energy, internet, reputation_score, region)
  VALUES (p_user_id, p_email, p_username, 100, 0, 100, 100, 50, 'global')
  RETURNING * INTO v_player;

  -- Dar rig inicial
  INSERT INTO player_rigs (player_id, rig_id, condition, is_active)
  VALUES (p_user_id, 'basic_miner', 100, false);

  RETURN json_build_object(
    'success', true,
    'player', row_to_json(v_player)
  );
END;
$$;

-- =====================================================
-- FUNCIONES DE JUGADOR
-- =====================================================

-- Obtener perfil completo del jugador
CREATE OR REPLACE FUNCTION get_player_profile(p_player_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player JSON;
  v_rigs JSON;
  v_badges JSON;
  v_rank JSON;
BEGIN
  -- Obtener datos del jugador
  SELECT row_to_json(p) INTO v_player
  FROM players p WHERE p.id = p_player_id;

  IF v_player IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Jugador no encontrado');
  END IF;

  -- Obtener rigs
  SELECT json_agg(row_to_json(pr)) INTO v_rigs
  FROM (
    SELECT pr.id, pr.is_active, pr.condition, pr.acquired_at,
           json_build_object(
             'id', r.id, 'name', r.name, 'hashrate', r.hashrate,
             'power_consumption', r.power_consumption,
             'internet_consumption', r.internet_consumption,
             'tier', r.tier, 'repair_cost', r.repair_cost
           ) as rig
    FROM player_rigs pr
    JOIN rigs r ON r.id = pr.rig_id
    WHERE pr.player_id = p_player_id
  ) pr;

  -- Obtener badges
  SELECT json_agg(b.name) INTO v_badges
  FROM player_badges pb
  JOIN badges b ON b.id = pb.badge_id
  WHERE pb.player_id = p_player_id;

  -- Calcular rango
  v_rank := get_rank_for_score((v_player->>'reputation_score')::NUMERIC);

  RETURN json_build_object(
    'success', true,
    'player', v_player,
    'rigs', COALESCE(v_rigs, '[]'::JSON),
    'badges', COALESCE(v_badges, '[]'::JSON),
    'rank', v_rank
  );
END;
$$;

-- Obtener rango basado en score
CREATE OR REPLACE FUNCTION get_rank_for_score(p_score NUMERIC)
RETURNS JSON
LANGUAGE plpgsql
AS $$
BEGIN
  IF p_score >= 85 THEN
    RETURN json_build_object('name', 'Diamante', 'color', '#B9F2FF', 'minScore', 85, 'maxScore', 100,
      'benefits', ARRAY['20% bonus hashrate', 'Acceso a pools élite', 'Insignias exclusivas']);
  ELSIF p_score >= 70 THEN
    RETURN json_build_object('name', 'Platino', 'color', '#E5E4E2', 'minScore', 70, 'maxScore', 84,
      'benefits', ARRAY['15% bonus hashrate', 'Acceso a pools premium']);
  ELSIF p_score >= 50 THEN
    RETURN json_build_object('name', 'Oro', 'color', '#FFD700', 'minScore', 50, 'maxScore', 69,
      'benefits', ARRAY['10% bonus hashrate', 'Acceso a pools básicos']);
  ELSIF p_score >= 30 THEN
    RETURN json_build_object('name', 'Plata', 'color', '#C0C0C0', 'minScore', 30, 'maxScore', 49,
      'benefits', ARRAY['5% bonus hashrate']);
  ELSE
    RETURN json_build_object('name', 'Bronce', 'color', '#CD7F32', 'minScore', 0, 'maxScore', 29,
      'benefits', ARRAY[]::TEXT[]);
  END IF;
END;
$$;

-- =====================================================
-- FUNCIONES DE RECURSOS
-- =====================================================

-- Recargar energía
CREATE OR REPLACE FUNCTION recharge_energy(p_player_id UUID, p_amount NUMERIC)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_cost NUMERIC;
  v_player players%ROWTYPE;
  v_new_energy NUMERIC;
BEGIN
  v_cost := p_amount * 0.5; -- 0.5 GameCoin por unidad

  SELECT * INTO v_player FROM players WHERE id = p_player_id;

  IF v_player IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Jugador no encontrado');
  END IF;

  IF v_player.gamecoin_balance < v_cost THEN
    RETURN json_build_object('success', false, 'error', 'GameCoin insuficiente', 'cost', v_cost);
  END IF;

  v_new_energy := LEAST(100, v_player.energy + p_amount);

  UPDATE players
  SET gamecoin_balance = gamecoin_balance - v_cost,
      energy = v_new_energy
  WHERE id = p_player_id;

  -- Registrar transacción
  INSERT INTO transactions (player_id, type, amount, currency, description)
  VALUES (p_player_id, 'energy_recharge', -v_cost, 'gamecoin', 'Recarga de ' || p_amount || ' unidades de energía');

  RETURN json_build_object('success', true, 'newEnergy', v_new_energy, 'cost', v_cost);
END;
$$;

-- Recargar internet
CREATE OR REPLACE FUNCTION recharge_internet(p_player_id UUID, p_amount NUMERIC)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_cost NUMERIC;
  v_player players%ROWTYPE;
  v_new_internet NUMERIC;
BEGIN
  v_cost := p_amount * 0.3; -- 0.3 GameCoin por unidad

  SELECT * INTO v_player FROM players WHERE id = p_player_id;

  IF v_player IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Jugador no encontrado');
  END IF;

  IF v_player.gamecoin_balance < v_cost THEN
    RETURN json_build_object('success', false, 'error', 'GameCoin insuficiente', 'cost', v_cost);
  END IF;

  v_new_internet := LEAST(100, v_player.internet + p_amount);

  UPDATE players
  SET gamecoin_balance = gamecoin_balance - v_cost,
      internet = v_new_internet
  WHERE id = p_player_id;

  INSERT INTO transactions (player_id, type, amount, currency, description)
  VALUES (p_player_id, 'internet_recharge', -v_cost, 'gamecoin', 'Recarga de ' || p_amount || ' unidades de internet');

  RETURN json_build_object('success', true, 'newInternet', v_new_internet, 'cost', v_cost);
END;
$$;

-- =====================================================
-- FUNCIONES DE RIGS
-- =====================================================

-- Toggle rig (encender/apagar)
CREATE OR REPLACE FUNCTION toggle_rig(p_player_id UUID, p_rig_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_rig player_rigs%ROWTYPE;
  v_player players%ROWTYPE;
BEGIN
  SELECT * INTO v_rig FROM player_rigs WHERE id = p_rig_id AND player_id = p_player_id;

  IF v_rig IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Rig no encontrado');
  END IF;

  -- Si se va a activar, verificar recursos
  IF NOT v_rig.is_active THEN
    SELECT * INTO v_player FROM players WHERE id = p_player_id;
    IF v_player.energy <= 0 OR v_player.internet <= 0 THEN
      RETURN json_build_object('success', false, 'error', 'Recursos insuficientes para activar el rig');
    END IF;
  END IF;

  UPDATE player_rigs
  SET is_active = NOT is_active
  WHERE id = p_rig_id
  RETURNING * INTO v_rig;

  RETURN json_build_object(
    'success', true,
    'isActive', v_rig.is_active,
    'message', CASE WHEN v_rig.is_active THEN 'Rig activado' ELSE 'Rig desactivado' END
  );
END;
$$;

-- Reparar rig
CREATE OR REPLACE FUNCTION repair_rig(p_player_id UUID, p_rig_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_rig RECORD;
  v_player players%ROWTYPE;
  v_repair_cost NUMERIC;
BEGIN
  SELECT pr.*, r.repair_cost as base_repair_cost
  INTO v_rig
  FROM player_rigs pr
  JOIN rigs r ON r.id = pr.rig_id
  WHERE pr.id = p_rig_id AND pr.player_id = p_player_id;

  IF v_rig IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Rig no encontrado');
  END IF;

  IF v_rig.condition >= 100 THEN
    RETURN json_build_object('success', false, 'error', 'El rig ya está en condición perfecta');
  END IF;

  v_repair_cost := ((100 - v_rig.condition) / 100.0) * v_rig.base_repair_cost;

  SELECT * INTO v_player FROM players WHERE id = p_player_id;

  IF v_player.gamecoin_balance < v_repair_cost THEN
    RETURN json_build_object('success', false, 'error', 'GameCoin insuficiente', 'cost', v_repair_cost);
  END IF;

  UPDATE players SET gamecoin_balance = gamecoin_balance - v_repair_cost WHERE id = p_player_id;
  UPDATE player_rigs SET condition = 100 WHERE id = p_rig_id;

  INSERT INTO transactions (player_id, type, amount, currency, description)
  VALUES (p_player_id, 'rig_repair', -v_repair_cost, 'gamecoin', 'Reparación de rig');

  RETURN json_build_object('success', true, 'cost', v_repair_cost);
END;
$$;

-- Obtener rigs del jugador
CREATE OR REPLACE FUNCTION get_player_rigs(p_player_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_rigs JSON;
BEGIN
  SELECT json_agg(row_to_json(t)) INTO v_rigs
  FROM (
    SELECT pr.id, pr.is_active, pr.condition, pr.acquired_at,
           json_build_object(
             'id', r.id, 'name', r.name, 'description', r.description,
             'hashrate', r.hashrate, 'power_consumption', r.power_consumption,
             'internet_consumption', r.internet_consumption,
             'tier', r.tier, 'repair_cost', r.repair_cost
           ) as rig
    FROM player_rigs pr
    JOIN rigs r ON r.id = pr.rig_id
    WHERE pr.player_id = p_player_id
    ORDER BY pr.acquired_at DESC
  ) t;

  RETURN COALESCE(v_rigs, '[]'::JSON);
END;
$$;

-- =====================================================
-- FUNCIONES DE MINERÍA
-- =====================================================

-- Obtener estadísticas de la red
CREATE OR REPLACE FUNCTION get_network_stats()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_stats network_stats%ROWTYPE;
  v_latest_block JSON;
  v_active_miners BIGINT;
BEGIN
  SELECT * INTO v_stats FROM network_stats WHERE id = 'current';

  SELECT json_build_object(
    'height', b.height,
    'hash', b.hash,
    'created_at', b.created_at,
    'miner', json_build_object('id', p.id, 'username', p.username)
  ) INTO v_latest_block
  FROM blocks b
  JOIN players p ON p.id = b.miner_id
  ORDER BY b.height DESC
  LIMIT 1;

  SELECT COUNT(DISTINCT player_id) INTO v_active_miners
  FROM player_rigs WHERE is_active = true;

  RETURN json_build_object(
    'difficulty', COALESCE(v_stats.difficulty, 1000),
    'hashrate', COALESCE(v_stats.hashrate, 0),
    'latestBlock', v_latest_block,
    'activeMiners', v_active_miners
  );
END;
$$;

-- Obtener bloques recientes
CREATE OR REPLACE FUNCTION get_recent_blocks(p_limit INT DEFAULT 20)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_blocks JSON;
BEGIN
  SELECT json_agg(row_to_json(t)) INTO v_blocks
  FROM (
    SELECT b.id, b.height, b.hash, b.difficulty, b.network_hashrate, b.created_at,
           json_build_object('id', p.id, 'username', p.username) as miner
    FROM blocks b
    JOIN players p ON p.id = b.miner_id
    ORDER BY b.height DESC
    LIMIT p_limit
  ) t;

  RETURN COALESCE(v_blocks, '[]'::JSON);
END;
$$;

-- Obtener estadísticas de minería del jugador
CREATE OR REPLACE FUNCTION get_player_mining_stats(p_player_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_blocks_mined BIGINT;
  v_total_crypto NUMERIC;
  v_current_hashrate NUMERIC := 0;
  v_active_rigs BIGINT;
  v_rep_score NUMERIC;
  v_rep_multiplier NUMERIC;
BEGIN
  -- Bloques minados
  SELECT COUNT(*) INTO v_blocks_mined FROM blocks WHERE miner_id = p_player_id;

  -- Total crypto minado
  SELECT COALESCE(SUM(amount), 0) INTO v_total_crypto
  FROM transactions
  WHERE player_id = p_player_id AND type = 'mining_reward';

  -- Obtener reputación
  SELECT reputation_score INTO v_rep_score FROM players WHERE id = p_player_id;

  -- Calcular multiplicador de reputación
  IF v_rep_score >= 80 THEN
    v_rep_multiplier := 1 + (v_rep_score - 80) * 0.01;
  ELSIF v_rep_score < 50 THEN
    v_rep_multiplier := 0.5 + (v_rep_score / 100.0);
  ELSE
    v_rep_multiplier := 1;
  END IF;

  -- Calcular hashrate actual
  SELECT COUNT(*), COALESCE(SUM(r.hashrate * (pr.condition / 100.0) * v_rep_multiplier), 0)
  INTO v_active_rigs, v_current_hashrate
  FROM player_rigs pr
  JOIN rigs r ON r.id = pr.rig_id
  WHERE pr.player_id = p_player_id AND pr.is_active = true;

  RETURN json_build_object(
    'blocksMined', v_blocks_mined,
    'totalCryptoMined', v_total_crypto,
    'currentHashrate', v_current_hashrate,
    'activeRigs', v_active_rigs,
    'reputationBonus', v_rep_multiplier
  );
END;
$$;

-- =====================================================
-- FUNCIONES DEL MERCADO
-- =====================================================

-- Crear orden de mercado
CREATE OR REPLACE FUNCTION create_market_order(
  p_player_id UUID,
  p_type TEXT,
  p_item_type TEXT,
  p_quantity NUMERIC,
  p_price_per_unit NUMERIC,
  p_item_id TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player players%ROWTYPE;
  v_total_cost NUMERIC;
  v_order market_orders%ROWTYPE;
BEGIN
  SELECT * INTO v_player FROM players WHERE id = p_player_id;

  IF v_player IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Jugador no encontrado');
  END IF;

  v_total_cost := p_quantity * p_price_per_unit;

  -- Validar recursos según tipo de orden
  IF p_type = 'buy' THEN
    IF v_player.gamecoin_balance < v_total_cost THEN
      RETURN json_build_object('success', false, 'error', 'GameCoin insuficiente');
    END IF;
    -- Reservar GameCoin
    UPDATE players SET gamecoin_balance = gamecoin_balance - v_total_cost WHERE id = p_player_id;
  ELSE -- sell
    IF p_item_type = 'crypto' AND v_player.crypto_balance < p_quantity THEN
      RETURN json_build_object('success', false, 'error', 'Crypto insuficiente');
    ELSIF p_item_type = 'energy' AND v_player.energy < p_quantity THEN
      RETURN json_build_object('success', false, 'error', 'Energía insuficiente');
    ELSIF p_item_type = 'internet' AND v_player.internet < p_quantity THEN
      RETURN json_build_object('success', false, 'error', 'Internet insuficiente');
    END IF;
  END IF;

  -- Crear orden
  INSERT INTO market_orders (player_id, type, item_type, item_id, quantity, price_per_unit, remaining_quantity, status)
  VALUES (p_player_id, p_type, p_item_type, p_item_id, p_quantity, p_price_per_unit, p_quantity, 'active')
  RETURNING * INTO v_order;

  -- Intentar matchear
  PERFORM match_market_orders(v_order.id);

  RETURN json_build_object('success', true, 'order', row_to_json(v_order));
END;
$$;

-- Matchear órdenes del mercado
CREATE OR REPLACE FUNCTION match_market_orders(p_order_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_order market_orders%ROWTYPE;
  v_match market_orders%ROWTYPE;
  v_trade_quantity NUMERIC;
  v_trade_price NUMERIC;
BEGIN
  SELECT * INTO v_order FROM market_orders WHERE id = p_order_id;

  IF v_order IS NULL OR v_order.status != 'active' THEN
    RETURN;
  END IF;

  -- Buscar órdenes que hagan match
  FOR v_match IN
    SELECT * FROM market_orders
    WHERE item_type = v_order.item_type
      AND type != v_order.type
      AND status = 'active'
      AND remaining_quantity > 0
      AND player_id != v_order.player_id
      AND (
        (v_order.type = 'buy' AND price_per_unit <= v_order.price_per_unit) OR
        (v_order.type = 'sell' AND price_per_unit >= v_order.price_per_unit)
      )
    ORDER BY
      CASE WHEN v_order.type = 'buy' THEN price_per_unit END ASC,
      CASE WHEN v_order.type = 'sell' THEN price_per_unit END DESC,
      created_at ASC
  LOOP
    IF v_order.remaining_quantity <= 0 THEN
      EXIT;
    END IF;

    v_trade_quantity := LEAST(v_order.remaining_quantity, v_match.remaining_quantity);
    v_trade_price := v_match.price_per_unit; -- Precio del maker

    -- Ejecutar trade
    PERFORM execute_trade(v_order, v_match, v_trade_quantity, v_trade_price);

    -- Actualizar remaining de la orden actual
    v_order.remaining_quantity := v_order.remaining_quantity - v_trade_quantity;
  END LOOP;

  -- Actualizar estado de la orden
  UPDATE market_orders
  SET remaining_quantity = v_order.remaining_quantity,
      status = CASE WHEN v_order.remaining_quantity <= 0 THEN 'filled' ELSE 'active' END
  WHERE id = p_order_id;
END;
$$;

-- Ejecutar trade
CREATE OR REPLACE FUNCTION execute_trade(
  p_taker market_orders,
  p_maker market_orders,
  p_quantity NUMERIC,
  p_price NUMERIC
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_buyer_id UUID;
  v_seller_id UUID;
  v_total_value NUMERIC;
BEGIN
  v_total_value := p_quantity * p_price;

  IF p_taker.type = 'buy' THEN
    v_buyer_id := p_taker.player_id;
    v_seller_id := p_maker.player_id;
  ELSE
    v_buyer_id := p_maker.player_id;
    v_seller_id := p_taker.player_id;
  END IF;

  -- Transferir items
  CASE p_taker.item_type
    WHEN 'crypto' THEN
      UPDATE players SET crypto_balance = crypto_balance - p_quantity WHERE id = v_seller_id;
      UPDATE players SET crypto_balance = crypto_balance + p_quantity WHERE id = v_buyer_id;
    WHEN 'energy' THEN
      UPDATE players SET energy = GREATEST(0, energy - p_quantity) WHERE id = v_seller_id;
      UPDATE players SET energy = LEAST(100, energy + p_quantity) WHERE id = v_buyer_id;
    WHEN 'internet' THEN
      UPDATE players SET internet = GREATEST(0, internet - p_quantity) WHERE id = v_seller_id;
      UPDATE players SET internet = LEAST(100, internet + p_quantity) WHERE id = v_buyer_id;
    ELSE NULL;
  END CASE;

  -- Transferir GameCoin al vendedor
  UPDATE players SET gamecoin_balance = gamecoin_balance + v_total_value WHERE id = v_seller_id;

  -- Registrar trade
  INSERT INTO trades (buyer_id, seller_id, item_type, item_id, quantity, price_per_unit, total_value, taker_order_id, maker_order_id)
  VALUES (v_buyer_id, v_seller_id, p_taker.item_type, p_maker.item_id, p_quantity, p_price, v_total_value, p_taker.id, p_maker.id);

  -- Actualizar orden del maker
  UPDATE market_orders
  SET remaining_quantity = remaining_quantity - p_quantity,
      status = CASE WHEN remaining_quantity - p_quantity <= 0 THEN 'filled' ELSE 'active' END
  WHERE id = p_maker.id;

  -- Actualizar reputación de ambos
  PERFORM update_reputation(v_buyer_id, 0.05, 'successful_trade');
  PERFORM update_reputation(v_seller_id, 0.05, 'successful_trade');
END;
$$;

-- Cancelar orden
CREATE OR REPLACE FUNCTION cancel_market_order(p_player_id UUID, p_order_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_order market_orders%ROWTYPE;
  v_refund NUMERIC;
BEGIN
  SELECT * INTO v_order FROM market_orders WHERE id = p_order_id AND player_id = p_player_id;

  IF v_order IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Orden no encontrada');
  END IF;

  IF v_order.status != 'active' THEN
    RETURN json_build_object('success', false, 'error', 'La orden ya no está activa');
  END IF;

  -- Devolver recursos si era orden de compra
  IF v_order.type = 'buy' THEN
    v_refund := v_order.remaining_quantity * v_order.price_per_unit;
    UPDATE players SET gamecoin_balance = gamecoin_balance + v_refund WHERE id = p_player_id;
  END IF;

  UPDATE market_orders SET status = 'cancelled' WHERE id = p_order_id;

  RETURN json_build_object('success', true, 'refund', COALESCE(v_refund, 0));
END;
$$;

-- Obtener order book
CREATE OR REPLACE FUNCTION get_order_book(p_item_type TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_bids JSON;
  v_asks JSON;
BEGIN
  SELECT json_agg(row_to_json(t) ORDER BY price_per_unit DESC) INTO v_bids
  FROM (
    SELECT id, player_id, quantity, price_per_unit, remaining_quantity, created_at
    FROM market_orders
    WHERE item_type = p_item_type AND type = 'buy' AND status = 'active' AND remaining_quantity > 0
    LIMIT 50
  ) t;

  SELECT json_agg(row_to_json(t) ORDER BY price_per_unit ASC) INTO v_asks
  FROM (
    SELECT id, player_id, quantity, price_per_unit, remaining_quantity, created_at
    FROM market_orders
    WHERE item_type = p_item_type AND type = 'sell' AND status = 'active' AND remaining_quantity > 0
    LIMIT 50
  ) t;

  RETURN json_build_object(
    'bids', COALESCE(v_bids, '[]'::JSON),
    'asks', COALESCE(v_asks, '[]'::JSON)
  );
END;
$$;

-- Obtener órdenes del jugador
CREATE OR REPLACE FUNCTION get_player_orders(p_player_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_orders JSON;
BEGIN
  SELECT json_agg(row_to_json(t)) INTO v_orders
  FROM (
    SELECT * FROM market_orders
    WHERE player_id = p_player_id AND status IN ('active', 'partially_filled')
    ORDER BY created_at DESC
  ) t;

  RETURN COALESCE(v_orders, '[]'::JSON);
END;
$$;

-- Obtener historial de trades
CREATE OR REPLACE FUNCTION get_player_trades(p_player_id UUID, p_limit INT DEFAULT 50)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_trades JSON;
BEGIN
  SELECT json_agg(row_to_json(t)) INTO v_trades
  FROM (
    SELECT * FROM trades
    WHERE buyer_id = p_player_id OR seller_id = p_player_id
    ORDER BY created_at DESC
    LIMIT p_limit
  ) t;

  RETURN COALESCE(v_trades, '[]'::JSON);
END;
$$;

-- Estadísticas del mercado 24h
CREATE OR REPLACE FUNCTION get_market_stats()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_stats JSON;
BEGIN
  SELECT json_build_object(
    'crypto', get_item_stats('crypto'),
    'energy', get_item_stats('energy'),
    'internet', get_item_stats('internet'),
    'rig', get_item_stats('rig')
  ) INTO v_stats;

  RETURN v_stats;
END;
$$;

CREATE OR REPLACE FUNCTION get_item_stats(p_item_type TEXT)
RETURNS JSON
LANGUAGE plpgsql
AS $$
DECLARE
  v_volume NUMERIC;
  v_last_price NUMERIC;
  v_high NUMERIC;
  v_low NUMERIC;
  v_trades BIGINT;
BEGIN
  SELECT
    COALESCE(SUM(total_value), 0),
    (SELECT price_per_unit FROM trades WHERE item_type = p_item_type ORDER BY created_at DESC LIMIT 1),
    COALESCE(MAX(price_per_unit), 0),
    COALESCE(MIN(price_per_unit), 0),
    COUNT(*)
  INTO v_volume, v_last_price, v_high, v_low, v_trades
  FROM trades
  WHERE item_type = p_item_type
    AND created_at > NOW() - INTERVAL '24 hours';

  RETURN json_build_object(
    'volume', v_volume,
    'lastPrice', COALESCE(v_last_price, 0),
    'high', v_high,
    'low', CASE WHEN v_low = 0 AND v_trades = 0 THEN 0 ELSE v_low END,
    'trades', v_trades
  );
END;
$$;

-- =====================================================
-- FUNCIONES DE LEADERBOARD
-- =====================================================

-- Leaderboard de reputación
CREATE OR REPLACE FUNCTION get_reputation_leaderboard(p_limit INT DEFAULT 100)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_leaderboard JSON;
BEGIN
  SELECT json_agg(row_to_json(t)) INTO v_leaderboard
  FROM (
    SELECT
      id as "playerId",
      username,
      reputation_score as score,
      get_rank_for_score(reputation_score) as rank
    FROM players
    ORDER BY reputation_score DESC
    LIMIT p_limit
  ) t;

  RETURN COALESCE(v_leaderboard, '[]'::JSON);
END;
$$;

-- Leaderboard de mineros
CREATE OR REPLACE FUNCTION get_mining_leaderboard(p_limit INT DEFAULT 100)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_leaderboard JSON;
BEGIN
  SELECT json_agg(row_to_json(t)) INTO v_leaderboard
  FROM (
    SELECT
      p.id,
      p.username,
      p.reputation_score as reputation,
      COUNT(b.id) as "blocksMined",
      COALESCE((
        SELECT SUM(r.hashrate * (pr.condition / 100.0))
        FROM player_rigs pr
        JOIN rigs r ON r.id = pr.rig_id
        WHERE pr.player_id = p.id AND pr.is_active = true
      ), 0) as hashrate
    FROM players p
    LEFT JOIN blocks b ON b.miner_id = p.id
    GROUP BY p.id, p.username, p.reputation_score
    ORDER BY COUNT(b.id) DESC
    LIMIT p_limit
  ) t;

  RETURN COALESCE(v_leaderboard, '[]'::JSON);
END;
$$;

-- =====================================================
-- FUNCIONES DE TRANSACCIONES
-- =====================================================

CREATE OR REPLACE FUNCTION get_player_transactions(p_player_id UUID, p_limit INT DEFAULT 50)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_transactions JSON;
BEGIN
  SELECT json_agg(row_to_json(t)) INTO v_transactions
  FROM (
    SELECT * FROM transactions
    WHERE player_id = p_player_id
    ORDER BY created_at DESC
    LIMIT p_limit
  ) t;

  RETURN COALESCE(v_transactions, '[]'::JSON);
END;
$$;
