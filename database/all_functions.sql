-- =====================================================
-- BLOCK LORDS - TODAS LAS FUNCIONES DEL JUEGO
-- =====================================================
-- Archivo consolidado con todas las funciones
-- Ejecutar después del schema inicial (001_initial_schema.sql)
-- =====================================================

-- Agregar columna blocks_mined si no existe
ALTER TABLE players ADD COLUMN IF NOT EXISTS blocks_mined INTEGER DEFAULT 0;

-- Crear tabla de inventario si no existe
CREATE TABLE IF NOT EXISTS player_inventory (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  item_type TEXT NOT NULL, -- 'cooling', 'rig', etc.
  item_id TEXT NOT NULL,
  quantity INTEGER DEFAULT 1,
  purchased_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(player_id, item_type, item_id)
);

-- Índice para búsquedas
CREATE INDEX IF NOT EXISTS idx_player_inventory_player ON player_inventory(player_id);

-- Crear tabla de refrigeración de rigs (cooling instalado en rigs específicos)
CREATE TABLE IF NOT EXISTS rig_cooling (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  player_rig_id UUID NOT NULL REFERENCES player_rigs(id) ON DELETE CASCADE,
  cooling_item_id TEXT NOT NULL REFERENCES cooling_items(id),
  durability NUMERIC DEFAULT 100, -- 0-100, se consume con uso
  installed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(player_rig_id, cooling_item_id)
);

-- Índice para búsquedas
CREATE INDEX IF NOT EXISTS idx_rig_cooling_rig ON rig_cooling(player_rig_id);

-- Agregar columna de consumo de energía extra a cooling_items si no existe
ALTER TABLE cooling_items ADD COLUMN IF NOT EXISTS energy_cost NUMERIC DEFAULT 0.5;

-- Agregar columna para rastrear cuando se encendió el rig
ALTER TABLE player_rigs ADD COLUMN IF NOT EXISTS activated_at TIMESTAMP WITH TIME ZONE DEFAULT NULL;

-- Agregar columnas de capacidad máxima de recursos
ALTER TABLE players ADD COLUMN IF NOT EXISTS max_energy NUMERIC DEFAULT 100;
ALTER TABLE players ADD COLUMN IF NOT EXISTS max_internet NUMERIC DEFAULT 100;

-- Agregar columnas para degradación de rigs
ALTER TABLE player_rigs ADD COLUMN IF NOT EXISTS max_condition NUMERIC DEFAULT 100;
ALTER TABLE player_rigs ADD COLUMN IF NOT EXISTS times_repaired INTEGER DEFAULT 0;

-- =====================================================
-- ELIMINAR FUNCIONES EXISTENTES
-- =====================================================

DROP FUNCTION IF EXISTS create_player_profile(UUID, TEXT, TEXT) CASCADE;
DROP FUNCTION IF EXISTS get_player_profile(UUID) CASCADE;
DROP FUNCTION IF EXISTS get_rank_for_score(NUMERIC) CASCADE;
DROP FUNCTION IF EXISTS get_player_rigs(UUID) CASCADE;
DROP FUNCTION IF EXISTS toggle_rig(UUID, UUID) CASCADE;
DROP FUNCTION IF EXISTS repair_rig(UUID, UUID) CASCADE;
DROP FUNCTION IF EXISTS delete_rig(UUID, UUID) CASCADE;
DROP FUNCTION IF EXISTS recharge_energy(UUID, NUMERIC) CASCADE;
DROP FUNCTION IF EXISTS recharge_internet(UUID, NUMERIC) CASCADE;
DROP FUNCTION IF EXISTS get_player_transactions(UUID, INTEGER) CASCADE;
DROP FUNCTION IF EXISTS get_network_stats() CASCADE;
DROP FUNCTION IF EXISTS get_home_stats() CASCADE;
DROP FUNCTION IF EXISTS get_recent_blocks(INTEGER) CASCADE;
DROP FUNCTION IF EXISTS get_recent_blocks() CASCADE;
DROP FUNCTION IF EXISTS get_player_mining_stats(UUID) CASCADE;
DROP FUNCTION IF EXISTS process_mining_tick() CASCADE;
DROP FUNCTION IF EXISTS game_tick() CASCADE;
DROP FUNCTION IF EXISTS process_resource_decay() CASCADE;
DROP FUNCTION IF EXISTS create_new_block(UUID, NUMERIC, NUMERIC) CASCADE;
DROP FUNCTION IF EXISTS calculate_block_reward(INTEGER) CASCADE;
DROP FUNCTION IF EXISTS check_difficulty_adjustment(INTEGER) CASCADE;
DROP FUNCTION IF EXISTS adjust_difficulty() CASCADE;
DROP FUNCTION IF EXISTS get_order_book(TEXT) CASCADE;
DROP FUNCTION IF EXISTS create_market_order(UUID, TEXT, TEXT, NUMERIC, NUMERIC, TEXT) CASCADE;
DROP FUNCTION IF EXISTS match_market_orders(UUID) CASCADE;
DROP FUNCTION IF EXISTS execute_trade(market_orders, market_orders, NUMERIC, NUMERIC) CASCADE;
DROP FUNCTION IF EXISTS cancel_market_order(UUID, UUID) CASCADE;
DROP FUNCTION IF EXISTS get_player_orders(UUID) CASCADE;
DROP FUNCTION IF EXISTS get_player_trades(UUID, INTEGER) CASCADE;
DROP FUNCTION IF EXISTS get_market_stats() CASCADE;
DROP FUNCTION IF EXISTS get_item_stats(TEXT) CASCADE;
DROP FUNCTION IF EXISTS get_reputation_leaderboard(INTEGER) CASCADE;
DROP FUNCTION IF EXISTS get_mining_leaderboard(INTEGER) CASCADE;
DROP FUNCTION IF EXISTS increment_balance(UUID, DECIMAL, TEXT) CASCADE;
DROP FUNCTION IF EXISTS transfer_gamecoin(UUID, UUID, DECIMAL) CASCADE;
DROP FUNCTION IF EXISTS transfer_crypto(UUID, UUID, DECIMAL) CASCADE;
DROP FUNCTION IF EXISTS transfer_energy(UUID, UUID, DECIMAL) CASCADE;
DROP FUNCTION IF EXISTS transfer_internet(UUID, UUID, DECIMAL) CASCADE;
DROP FUNCTION IF EXISTS update_reputation(UUID, DECIMAL, TEXT) CASCADE;
DROP FUNCTION IF EXISTS get_cooling_items() CASCADE;
DROP FUNCTION IF EXISTS get_player_cooling(UUID) CASCADE;
DROP FUNCTION IF EXISTS install_cooling(UUID, TEXT) CASCADE;
DROP FUNCTION IF EXISTS buy_cooling(UUID, TEXT) CASCADE;
DROP FUNCTION IF EXISTS buy_rig(UUID, TEXT) CASCADE;
DROP FUNCTION IF EXISTS get_prepaid_cards() CASCADE;
DROP FUNCTION IF EXISTS get_player_cards(UUID) CASCADE;
DROP FUNCTION IF EXISTS buy_prepaid_card(UUID, TEXT) CASCADE;
DROP FUNCTION IF EXISTS redeem_prepaid_card(UUID, TEXT) CASCADE;
DROP FUNCTION IF EXISTS get_player_inventory(UUID) CASCADE;
DROP FUNCTION IF EXISTS install_cooling_from_inventory(UUID, UUID) CASCADE;
DROP FUNCTION IF EXISTS install_cooling_to_rig(UUID, UUID, TEXT) CASCADE;
DROP FUNCTION IF EXISTS get_rig_cooling(UUID) CASCADE;
DROP FUNCTION IF EXISTS exchange_crypto_to_gamecoin(UUID, NUMERIC) CASCADE;
DROP FUNCTION IF EXISTS exchange_crypto_to_ron(UUID, NUMERIC) CASCADE;
DROP FUNCTION IF EXISTS get_exchange_rates() CASCADE;

-- =====================================================
-- 1. FUNCIONES DE UTILIDAD
-- =====================================================

-- Incrementar balance
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
    SET gamecoin_balance = gamecoin_balance + p_amount, updated_at = NOW()
    WHERE id = p_player_id
    RETURNING gamecoin_balance INTO new_balance;
  ELSIF p_currency = 'crypto' THEN
    UPDATE players
    SET crypto_balance = crypto_balance + p_amount, updated_at = NOW()
    WHERE id = p_player_id
    RETURNING crypto_balance INTO new_balance;
  END IF;
  RETURN new_balance;
END;
$$;

-- Transferir GameCoin
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
  IF (SELECT gamecoin_balance FROM players WHERE id = p_from_player) < p_amount THEN
    RAISE EXCEPTION 'Balance insuficiente';
  END IF;
  UPDATE players SET gamecoin_balance = gamecoin_balance - p_amount WHERE id = p_from_player;
  UPDATE players SET gamecoin_balance = gamecoin_balance + p_amount WHERE id = p_to_player;
END;
$$;

-- Transferir Crypto
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

-- Transferir Energía
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

-- Transferir Internet
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

-- Actualizar reputación
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
  SET reputation_score = new_score, updated_at = NOW()
  WHERE id = p_player_id;

  INSERT INTO reputation_events (player_id, delta, reason, old_score, new_score)
  VALUES (p_player_id, p_delta, p_reason, old_score, new_score);

  RETURN new_score;
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
-- 2. FUNCIONES DE AUTENTICACIÓN Y PERFIL
-- =====================================================

-- Crear perfil de jugador
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

  -- Registrar transacción de bienvenida
  INSERT INTO transactions (player_id, type, amount, currency, description)
  VALUES (p_user_id, 'welcome_bonus', 100, 'gamecoin', 'Bonus de bienvenida');

  RETURN json_build_object(
    'success', true,
    'player', row_to_json(v_player)
  );
END;
$$;

-- Obtener perfil completo
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
  SELECT row_to_json(p) INTO v_player FROM players p WHERE p.id = p_player_id;

  IF v_player IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Jugador no encontrado');
  END IF;

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

  SELECT json_agg(b.name) INTO v_badges
  FROM player_badges pb
  JOIN badges b ON b.id = pb.badge_id
  WHERE pb.player_id = p_player_id;

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

-- =====================================================
-- 3. FUNCIONES DE RIGS
-- =====================================================

-- Obtener rigs del jugador
CREATE OR REPLACE FUNCTION get_player_rigs(p_player_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN (
    SELECT COALESCE(json_agg(row_to_json(t)), '[]'::JSON)
    FROM (
      SELECT pr.id, pr.is_active, pr.condition, pr.temperature, pr.acquired_at, pr.activated_at,
             COALESCE(pr.max_condition, 100) as max_condition,
             COALESCE(pr.times_repaired, 0) as times_repaired,
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
    ) t
  );
END;
$$;

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

  -- Verificar si se quiere encender un rig roto
  IF NOT v_rig.is_active THEN
    -- No permitir encender si condición es 0
    IF v_rig.condition <= 0 THEN
      RETURN json_build_object('success', false, 'error', 'El rig está roto. Debes repararlo o eliminarlo.');
    END IF;

    SELECT * INTO v_player FROM players WHERE id = p_player_id;
    IF v_player.energy <= 0 OR v_player.internet <= 0 THEN
      RETURN json_build_object('success', false, 'error', 'Recursos insuficientes para activar el rig');
    END IF;
  END IF;

  UPDATE player_rigs
  SET is_active = NOT is_active,
      activated_at = CASE WHEN NOT is_active THEN NOW() ELSE NULL END
  WHERE id = p_rig_id
  RETURNING * INTO v_rig;

  RETURN json_build_object(
    'success', true,
    'isActive', v_rig.is_active,
    'activatedAt', v_rig.activated_at,
    'message', CASE WHEN v_rig.is_active THEN 'Rig activado' ELSE 'Rig desactivado' END
  );
END;
$$;

-- Reparar rig (con degradación permanente)
-- Cada reparación reduce max_condition en 5%
-- Cuando max_condition <= 10%, el rig ya no se puede reparar
CREATE OR REPLACE FUNCTION repair_rig(p_player_id UUID, p_rig_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_rig RECORD;
  v_player players%ROWTYPE;
  v_repair_cost NUMERIC;
  v_current_max NUMERIC;
  v_new_max NUMERIC;
  v_degradation NUMERIC := 5;  -- 5% de degradación por reparación
BEGIN
  SELECT pr.*, r.repair_cost as base_repair_cost, r.name as rig_name
  INTO v_rig
  FROM player_rigs pr
  JOIN rigs r ON r.id = pr.rig_id
  WHERE pr.id = p_rig_id AND pr.player_id = p_player_id;

  IF v_rig IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Rig no encontrado');
  END IF;

  -- Obtener max_condition actual (default 100 si es NULL)
  v_current_max := COALESCE(v_rig.max_condition, 100);

  -- Verificar si el rig ya no se puede reparar
  IF v_current_max <= 10 THEN
    RETURN json_build_object('success', false, 'error', 'Este rig está demasiado dañado para reparar. Debes eliminarlo.');
  END IF;

  -- Verificar si ya está en su máxima condición posible
  IF v_rig.condition >= v_current_max THEN
    RETURN json_build_object('success', false, 'error', 'El rig ya está en su máxima condición posible');
  END IF;

  -- Calcular costo basado en max_condition actual
  v_repair_cost := ((v_current_max - v_rig.condition) / 100.0) * v_rig.base_repair_cost;

  SELECT * INTO v_player FROM players WHERE id = p_player_id;

  IF v_player.gamecoin_balance < v_repair_cost THEN
    RETURN json_build_object('success', false, 'error', 'GameCoin insuficiente', 'cost', v_repair_cost);
  END IF;

  -- Calcular nueva max_condition (se reduce con cada reparación)
  v_new_max := GREATEST(10, v_current_max - v_degradation);

  -- Aplicar reparación
  UPDATE players SET gamecoin_balance = gamecoin_balance - v_repair_cost WHERE id = p_player_id;
  UPDATE player_rigs
  SET condition = v_current_max,  -- Repara hasta el máximo actual
      max_condition = v_new_max,  -- Reduce el máximo para futuras reparaciones
      times_repaired = COALESCE(times_repaired, 0) + 1
  WHERE id = p_rig_id;

  INSERT INTO transactions (player_id, type, amount, currency, description)
  VALUES (p_player_id, 'rig_repair', -v_repair_cost, 'gamecoin',
          'Reparación de ' || v_rig.rig_name || ' (max: ' || v_new_max || '%)');

  RETURN json_build_object(
    'success', true,
    'cost', v_repair_cost,
    'new_condition', v_current_max,
    'new_max_condition', v_new_max,
    'times_repaired', COALESCE(v_rig.times_repaired, 0) + 1,
    'warning', CASE
      WHEN v_new_max <= 30 THEN 'El rig está muy desgastado. Considera reemplazarlo pronto.'
      WHEN v_new_max <= 50 THEN 'El rig muestra signos de desgaste permanente.'
      ELSE NULL
    END
  );
END;
$$;

-- Eliminar/Descartar rig (cuando ya no sirve)
CREATE OR REPLACE FUNCTION delete_rig(p_player_id UUID, p_rig_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_rig RECORD;
BEGIN
  SELECT pr.*, r.name as rig_name
  INTO v_rig
  FROM player_rigs pr
  JOIN rigs r ON r.id = pr.rig_id
  WHERE pr.id = p_rig_id AND pr.player_id = p_player_id;

  IF v_rig IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Rig no encontrado');
  END IF;

  -- No permitir eliminar si está activo
  IF v_rig.is_active THEN
    RETURN json_build_object('success', false, 'error', 'Debes apagar el rig antes de eliminarlo');
  END IF;

  -- Eliminar cooling instalado en el rig
  DELETE FROM rig_cooling WHERE player_rig_id = p_rig_id;

  -- Eliminar el rig
  DELETE FROM player_rigs WHERE id = p_rig_id;

  -- Registrar en transacciones
  INSERT INTO transactions (player_id, type, amount, currency, description)
  VALUES (p_player_id, 'rig_deleted', 0, 'gamecoin', 'Rig descartado: ' || v_rig.rig_name);

  RETURN json_build_object(
    'success', true,
    'message', 'Rig eliminado correctamente',
    'rig_name', v_rig.rig_name
  );
END;
$$;

-- Comprar rig
CREATE OR REPLACE FUNCTION buy_rig(p_player_id UUID, p_rig_id TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player players%ROWTYPE;
  v_rig rigs%ROWTYPE;
  v_existing_count INT;
BEGIN
  -- Verificar jugador
  SELECT * INTO v_player FROM players WHERE id = p_player_id;
  IF v_player IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Jugador no encontrado');
  END IF;

  -- Verificar rig
  SELECT * INTO v_rig FROM rigs WHERE id = p_rig_id;
  IF v_rig IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Rig no encontrado');
  END IF;

  -- Verificar que no sea el rig gratuito
  IF v_rig.base_price <= 0 THEN
    RETURN json_build_object('success', false, 'error', 'Este rig no está a la venta');
  END IF;

  -- Verificar si ya lo tiene
  SELECT COUNT(*) INTO v_existing_count
  FROM player_rigs
  WHERE player_id = p_player_id AND rig_id = p_rig_id;

  IF v_existing_count > 0 THEN
    RETURN json_build_object('success', false, 'error', 'Ya tienes este rig');
  END IF;

  -- Verificar balance
  IF v_player.gamecoin_balance < v_rig.base_price THEN
    RETURN json_build_object('success', false, 'error', 'GameCoin insuficiente');
  END IF;

  -- Descontar GameCoin
  UPDATE players
  SET gamecoin_balance = gamecoin_balance - v_rig.base_price
  WHERE id = p_player_id;

  -- Registrar transacción
  INSERT INTO transactions (player_id, type, amount, currency, description)
  VALUES (p_player_id, 'rig_purchase', -v_rig.base_price, 'gamecoin',
          'Compra de rig: ' || v_rig.name);

  -- Dar el rig al jugador
  INSERT INTO player_rigs (player_id, rig_id, condition, is_active, temperature)
  VALUES (p_player_id, p_rig_id, 100, false, 25);

  RETURN json_build_object(
    'success', true,
    'rig', row_to_json(v_rig)
  );
END;
$$;

-- =====================================================
-- 4. FUNCIONES DE RECURSOS
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
  v_cost := p_amount * 0.5;
  SELECT * INTO v_player FROM players WHERE id = p_player_id;

  IF v_player IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Jugador no encontrado');
  END IF;

  IF v_player.gamecoin_balance < v_cost THEN
    RETURN json_build_object('success', false, 'error', 'GameCoin insuficiente', 'cost', v_cost);
  END IF;

  v_new_energy := LEAST(v_player.max_energy, v_player.energy + p_amount);

  UPDATE players
  SET gamecoin_balance = gamecoin_balance - v_cost, energy = v_new_energy
  WHERE id = p_player_id;

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
  v_cost := p_amount * 0.3;
  SELECT * INTO v_player FROM players WHERE id = p_player_id;

  IF v_player IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Jugador no encontrado');
  END IF;

  IF v_player.gamecoin_balance < v_cost THEN
    RETURN json_build_object('success', false, 'error', 'GameCoin insuficiente', 'cost', v_cost);
  END IF;

  v_new_internet := LEAST(v_player.max_internet, v_player.internet + p_amount);

  UPDATE players
  SET gamecoin_balance = gamecoin_balance - v_cost, internet = v_new_internet
  WHERE id = p_player_id;

  INSERT INTO transactions (player_id, type, amount, currency, description)
  VALUES (p_player_id, 'internet_recharge', -v_cost, 'gamecoin', 'Recarga de ' || p_amount || ' unidades de internet');

  RETURN json_build_object('success', true, 'newInternet', v_new_internet, 'cost', v_cost);
END;
$$;

-- Obtener transacciones
CREATE OR REPLACE FUNCTION get_player_transactions(p_player_id UUID, p_limit INT DEFAULT 50)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN (
    SELECT COALESCE(json_agg(row_to_json(t)), '[]'::JSON)
    FROM (
      SELECT * FROM transactions
      WHERE player_id = p_player_id
      ORDER BY created_at DESC
      LIMIT p_limit
    ) t
  );
END;
$$;

-- =====================================================
-- 5. FUNCIONES DE MINERÍA
-- =====================================================

-- Estadísticas de red
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

-- Estadísticas para el Home Page
CREATE OR REPLACE FUNCTION get_home_stats()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_total_players BIGINT;
  v_online_players BIGINT;
  v_total_blocks BIGINT;
  v_volume_24h NUMERIC;
  v_difficulty NUMERIC;
BEGIN
  -- Total de jugadores registrados
  SELECT COUNT(*) INTO v_total_players FROM players;

  -- Jugadores online
  SELECT COUNT(*) INTO v_online_players FROM players WHERE is_online = true;

  -- Total de bloques minados
  SELECT COUNT(*) INTO v_total_blocks FROM blocks;

  -- Volumen de trades en 24h (suma de todo el valor comerciado)
  SELECT COALESCE(SUM(total_value), 0) INTO v_volume_24h
  FROM trades
  WHERE created_at > NOW() - INTERVAL '24 hours';

  -- Dificultad actual
  SELECT COALESCE(difficulty, 1000) INTO v_difficulty
  FROM network_stats WHERE id = 'current';

  RETURN json_build_object(
    'totalPlayers', v_total_players,
    'onlinePlayers', v_online_players,
    'totalBlocks', v_total_blocks,
    'volume24h', v_volume_24h,
    'difficulty', v_difficulty
  );
END;
$$;

-- Bloques recientes
CREATE OR REPLACE FUNCTION get_recent_blocks(p_limit INT DEFAULT 20)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN (
    SELECT COALESCE(json_agg(row_to_json(t)), '[]'::JSON)
    FROM (
      SELECT b.id, b.height, b.hash, b.difficulty, b.network_hashrate, b.created_at,
             json_build_object('id', p.id, 'username', p.username) as miner
      FROM blocks b
      JOIN players p ON p.id = b.miner_id
      ORDER BY b.height DESC
      LIMIT p_limit
    ) t
  );
END;
$$;

-- Estadísticas de minería del jugador
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
  SELECT COUNT(*) INTO v_blocks_mined FROM blocks WHERE miner_id = p_player_id;

  SELECT COALESCE(SUM(amount), 0) INTO v_total_crypto
  FROM transactions
  WHERE player_id = p_player_id AND type = 'mining_reward';

  SELECT reputation_score INTO v_rep_score FROM players WHERE id = p_player_id;

  IF v_rep_score >= 80 THEN
    v_rep_multiplier := 1 + (v_rep_score - 80) * 0.01;
  ELSIF v_rep_score < 50 THEN
    v_rep_multiplier := 0.5 + (v_rep_score / 100.0);
  ELSE
    v_rep_multiplier := 1;
  END IF;

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

-- Calcular recompensa de bloque (halving cada 10000 bloques)
CREATE OR REPLACE FUNCTION calculate_block_reward(p_block_height INT)
RETURNS NUMERIC
LANGUAGE plpgsql
AS $$
DECLARE
  v_base_reward NUMERIC := 100;
  v_halving_interval INT := 10000;
  v_halvings INT;
BEGIN
  v_halvings := p_block_height / v_halving_interval;
  RETURN v_base_reward / POWER(2, v_halvings);
END;
$$;

-- Crear nuevo bloque
CREATE OR REPLACE FUNCTION create_new_block(
  p_miner_id UUID,
  p_difficulty NUMERIC,
  p_network_hashrate NUMERIC
)
RETURNS blocks
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_last_block RECORD;
  v_new_height INT;
  v_previous_hash TEXT;
  v_new_hash TEXT;
  v_block blocks%ROWTYPE;
BEGIN
  SELECT height, hash INTO v_last_block FROM blocks ORDER BY height DESC LIMIT 1;

  v_new_height := COALESCE(v_last_block.height, 0) + 1;
  v_previous_hash := COALESCE(v_last_block.hash, REPEAT('0', 64));

  v_new_hash := encode(sha256(
    (v_new_height::TEXT || v_previous_hash || p_miner_id::TEXT || NOW()::TEXT || random()::TEXT)::BYTEA
  ), 'hex');

  INSERT INTO blocks (height, hash, previous_hash, miner_id, difficulty, network_hashrate)
  VALUES (v_new_height, v_new_hash, v_previous_hash, p_miner_id, p_difficulty, p_network_hashrate)
  RETURNING * INTO v_block;

  RETURN v_block;
END;
$$;

-- Procesar decay de recursos, temperatura y deterioro
CREATE OR REPLACE FUNCTION process_resource_decay()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player RECORD;
  v_rig RECORD;
  v_total_power NUMERIC;
  v_total_internet NUMERIC;
  v_new_energy NUMERIC;
  v_new_internet NUMERIC;
  v_processed INT := 0;
  v_rig_cooling_power NUMERIC;
  v_rig_cooling_energy NUMERIC;
  v_temp_increase NUMERIC;
  v_new_temp NUMERIC;
  v_deterioration NUMERIC;
  v_base_deterioration NUMERIC;
  v_ambient_temp NUMERIC := 25;  -- Temperatura ambiente base
BEGIN
  FOR v_player IN
    SELECT p.id, p.energy, p.internet
    FROM players p
    WHERE EXISTS (SELECT 1 FROM player_rigs pr WHERE pr.player_id = p.id AND pr.is_active = true)
  LOOP
    v_total_power := 0;
    v_total_internet := 0;

    -- Procesar cada rig activo individualmente
    FOR v_rig IN
      SELECT pr.id, pr.temperature, pr.condition, r.power_consumption, r.internet_consumption, r.hashrate
      FROM player_rigs pr
      JOIN rigs r ON r.id = pr.rig_id
      WHERE pr.player_id = v_player.id AND pr.is_active = true
    LOOP
      -- Obtener refrigeración instalada en este rig específico
      SELECT
        COALESCE(SUM(ci.cooling_power * (rc.durability / 100.0)), 0),
        COALESCE(SUM(ci.energy_cost * (rc.durability / 100.0)), 0)
      INTO v_rig_cooling_power, v_rig_cooling_energy
      FROM rig_cooling rc
      JOIN cooling_items ci ON ci.id = rc.cooling_item_id
      WHERE rc.player_rig_id = v_rig.id AND rc.durability > 0;

      -- Calcular consumo de energía del rig:
      -- Base + penalización por temperatura + consumo de refrigeración
      -- Temperatura > 40°C aumenta consumo hasta 50% extra a 100°C
      v_total_power := v_total_power +
        (v_rig.power_consumption * (1 + GREATEST(0, (v_rig.temperature - 40)) * 0.0083)) +
        v_rig_cooling_energy;

      v_total_internet := v_total_internet + v_rig.internet_consumption;

      -- Calcular aumento de temperatura basado en consumo de energía
      -- Más consumo = más calor generado
      -- SIN REFRIGERACIÓN: el rig se calienta MUCHO más rápido (3x)
      IF v_rig_cooling_power <= 0 THEN
        -- Sin cooling: calentamiento agresivo
        v_temp_increase := v_rig.power_consumption * 2.5;
      ELSE
        -- Con cooling: calentamiento normal menos el poder de refrigeración
        v_temp_increase := v_rig.power_consumption * 0.8;
        v_temp_increase := GREATEST(0, v_temp_increase - v_rig_cooling_power);
      END IF;

      -- Calcular nueva temperatura
      v_new_temp := v_rig.temperature + v_temp_increase;

      -- Enfriamiento pasivo hacia temperatura ambiente
      -- Sin refrigeración: enfriamiento pasivo muy reducido
      IF v_new_temp > v_ambient_temp THEN
        IF v_rig_cooling_power <= 0 THEN
          -- Sin cooling: enfriamiento pasivo mínimo (0.2 por tick)
          v_new_temp := v_new_temp - 0.2;
        ELSE
          -- Con cooling: enfriamiento pasivo normal + bonus por refrigeración
          v_new_temp := v_new_temp - (0.5 + (v_rig_cooling_power * 0.2));
        END IF;
        v_new_temp := GREATEST(v_ambient_temp, v_new_temp);
      END IF;

      -- Limitar temperatura máxima a 100
      v_new_temp := LEAST(100, v_new_temp);

      -- Calcular deterioro BASE por uso (siempre hay un poco de desgaste)
      v_base_deterioration := 0.02;  -- 0.02% por tick base

      -- Deterioro EXTRA basado en temperatura (ESCALADO AGRESIVO)
      -- Cuanto más caliente, exponencialmente más daño
      -- < 50°C: solo desgaste base (0.02%)
      -- 50-70°C: daño moderado que escala (hasta ~0.5%)
      -- 70-85°C: daño severo (hasta ~2%)
      -- 85-100°C: daño CRÍTICO exponencial (hasta ~7% a 100°C)
      IF v_new_temp >= 85 THEN
        -- Daño crítico: escala exponencialmente - a 100°C = ~7% por tick
        v_deterioration := v_base_deterioration + 2.0 + POWER((v_new_temp - 85) / 15.0, 2) * 5.0;
      ELSIF v_new_temp >= 70 THEN
        -- Daño severo: escala rápidamente
        v_deterioration := v_base_deterioration + 0.5 + ((v_new_temp - 70) * 0.1);
      ELSIF v_new_temp >= 50 THEN
        -- Daño moderado
        v_deterioration := v_base_deterioration + 0.05 + ((v_new_temp - 50) * 0.02);
      ELSE
        v_deterioration := v_base_deterioration;  -- Solo desgaste base
      END IF;

      -- Aplicar deterioro y actualizar temperatura
      UPDATE player_rigs
      SET temperature = v_new_temp,
          condition = GREATEST(0, condition - v_deterioration)
      WHERE id = v_rig.id;

      -- Consumir durabilidad de la refrigeración instalada en este rig
      -- La refrigeración se desgasta más rápido si la temperatura es alta
      UPDATE rig_cooling
      SET durability = GREATEST(0, durability - (0.1 + (GREATEST(0, v_new_temp - 40) * 0.005)))
      WHERE player_rig_id = v_rig.id AND durability > 0;

      -- Eliminar refrigeración agotada
      DELETE FROM rig_cooling WHERE player_rig_id = v_rig.id AND durability <= 0;

      -- Si condición llega a 0, apagar el rig
      IF (v_rig.condition - v_deterioration) <= 0 THEN
        UPDATE player_rigs SET is_active = false WHERE id = v_rig.id;
        INSERT INTO player_events (player_id, type, data)
        VALUES (v_player.id, 'rig_broken', json_build_object(
          'rig_id', v_rig.id,
          'reason', 'wear_and_tear'
        ));
      END IF;
    END LOOP;

    -- Calcular nuevo nivel de energía e internet
    v_new_energy := GREATEST(0, v_player.energy - (v_total_power * 0.1));
    v_new_internet := GREATEST(0, v_player.internet - (v_total_internet * 0.05));

    -- Actualizar recursos del jugador
    UPDATE players
    SET energy = v_new_energy,
        internet = v_new_internet
    WHERE id = v_player.id;

    -- Apagar rigs si no hay energía o internet
    IF v_new_energy = 0 OR v_new_internet = 0 THEN
      UPDATE player_rigs SET is_active = false WHERE player_id = v_player.id;
      INSERT INTO player_events (player_id, type, data)
      VALUES (v_player.id, 'rigs_shutdown', json_build_object(
        'reason', CASE WHEN v_new_energy = 0 THEN 'energy' ELSE 'internet' END
      ));
    END IF;

    v_processed := v_processed + 1;
  END LOOP;

  -- Enfriar rigs inactivos hacia temperatura ambiente
  UPDATE player_rigs
  SET temperature = GREATEST(v_ambient_temp, temperature - 2)
  WHERE is_active = false AND temperature > v_ambient_temp;

  RETURN v_processed;
END;
$$;

-- Tick de minería (selección de ganador)
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
  v_rig RECORD;
  v_effective_hashrate NUMERIC;
  v_rep_multiplier NUMERIC;
  v_hashrate_sum NUMERIC := 0;
  v_random_pick NUMERIC;
  v_temp_penalty NUMERIC;
  v_condition_penalty NUMERIC;
BEGIN
  SELECT COALESCE(ns.difficulty, 1000) INTO v_difficulty FROM network_stats ns WHERE ns.id = 'current';
  IF v_difficulty IS NULL THEN v_difficulty := 1000; END IF;

  -- Calcular hashrate total con penalizaciones por temperatura y condición
  FOR v_rig IN
    SELECT pr.id as rig_id, pr.player_id, pr.condition, pr.temperature, r.hashrate, p.reputation_score
    FROM player_rigs pr
    JOIN rigs r ON r.id = pr.rig_id
    JOIN players p ON p.id = pr.player_id
    WHERE pr.is_active = true AND p.energy > 0 AND p.internet > 0
  LOOP
    -- Multiplicador de reputación
    IF v_rig.reputation_score >= 80 THEN
      v_rep_multiplier := 1 + (v_rig.reputation_score - 80) * 0.01;
    ELSIF v_rig.reputation_score < 50 THEN
      v_rep_multiplier := 0.5 + (v_rig.reputation_score / 100.0);
    ELSE
      v_rep_multiplier := 1;
    END IF;

    -- Penalización por temperatura: reduce hashrate cuando temp > 50°C
    -- A 50°C: 100% hashrate, a 100°C: 30% hashrate
    v_temp_penalty := 1;
    IF v_rig.temperature > 50 THEN
      v_temp_penalty := 1 - ((v_rig.temperature - 50) * 0.014);
      v_temp_penalty := GREATEST(0.3, v_temp_penalty);  -- Mínimo 30% hashrate
    END IF;

    -- Penalización por condición: condición baja reduce hashrate
    -- 100% condición = 100% hashrate, 0% condición = 20% hashrate
    v_condition_penalty := 0.2 + (v_rig.condition / 100.0) * 0.8;

    v_effective_hashrate := v_rig.hashrate * v_condition_penalty * v_rep_multiplier * v_temp_penalty;
    v_network_hashrate := v_network_hashrate + v_effective_hashrate;
  END LOOP;

  -- Actualizar hashrate de red
  INSERT INTO network_stats (id, difficulty, hashrate, updated_at)
  VALUES ('current', v_difficulty, v_network_hashrate, NOW())
  ON CONFLICT (id) DO UPDATE SET hashrate = v_network_hashrate, updated_at = NOW();

  IF v_network_hashrate = 0 THEN
    RETURN QUERY SELECT false, NULL::INT;
    RETURN;
  END IF;

  -- Probabilidad de minar
  v_block_probability := v_network_hashrate / v_difficulty;
  v_roll := random();

  IF v_roll > v_block_probability THEN
    RETURN QUERY SELECT false, NULL::INT;
    RETURN;
  END IF;

  -- Seleccionar ganador (con mismas penalizaciones)
  v_random_pick := random() * v_network_hashrate;
  v_hashrate_sum := 0;

  FOR v_rig IN
    SELECT pr.id as rig_id, pr.player_id, pr.condition, pr.temperature, r.hashrate, p.reputation_score
    FROM player_rigs pr
    JOIN rigs r ON r.id = pr.rig_id
    JOIN players p ON p.id = pr.player_id
    WHERE pr.is_active = true AND p.energy > 0 AND p.internet > 0
  LOOP
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

    v_effective_hashrate := v_rig.hashrate * v_condition_penalty * v_rep_multiplier * v_temp_penalty;
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

  -- Recompensa
  v_reward := calculate_block_reward(v_block.height);

  UPDATE players
  SET crypto_balance = crypto_balance + v_reward, blocks_mined = COALESCE(blocks_mined, 0) + 1
  WHERE id = v_winner_player_id;

  INSERT INTO transactions (player_id, type, amount, currency, description)
  VALUES (v_winner_player_id, 'mining_reward', v_reward, 'crypto', 'Recompensa por minar bloque #' || v_block.height);

  PERFORM update_reputation(v_winner_player_id, 0.1, 'block_mined');

  RETURN QUERY SELECT true, v_block.height;
END;
$$;

-- Ajustar dificultad dinámicamente basado en hashrate de red
-- La dificultad se ajusta para mantener ~10% probabilidad de bloque por tick
-- Fórmula: nueva_dificultad = hashrate / target_probability
CREATE OR REPLACE FUNCTION adjust_difficulty()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_current_difficulty NUMERIC;
  v_current_hashrate NUMERIC;
  v_new_difficulty NUMERIC;
  v_target_probability NUMERIC := 0.10; -- 10% chance per tick
  v_min_difficulty NUMERIC := 100;      -- Mínimo para evitar bloques muy fáciles
  v_max_adjustment NUMERIC := 0.25;     -- Máximo 25% de cambio por ajuste
  v_adjustment_factor NUMERIC;
BEGIN
  -- Obtener valores actuales
  SELECT difficulty, hashrate INTO v_current_difficulty, v_current_hashrate
  FROM network_stats WHERE id = 'current';

  IF v_current_difficulty IS NULL THEN v_current_difficulty := 1000; END IF;
  IF v_current_hashrate IS NULL OR v_current_hashrate = 0 THEN
    -- Sin hashrate, mantener dificultad mínima
    RETURN json_build_object(
      'adjusted', false,
      'reason', 'No hashrate',
      'difficulty', v_current_difficulty
    );
  END IF;

  -- Calcular dificultad ideal para el target de probabilidad
  -- Probabilidad = hashrate / dificultad
  -- Dificultad ideal = hashrate / target_probability
  v_new_difficulty := v_current_hashrate / v_target_probability;

  -- Aplicar límites de ajuste suave (máx 25% de cambio)
  v_adjustment_factor := v_new_difficulty / v_current_difficulty;

  IF v_adjustment_factor > (1 + v_max_adjustment) THEN
    v_new_difficulty := v_current_difficulty * (1 + v_max_adjustment);
  ELSIF v_adjustment_factor < (1 - v_max_adjustment) THEN
    v_new_difficulty := v_current_difficulty * (1 - v_max_adjustment);
  END IF;

  -- Aplicar dificultad mínima
  v_new_difficulty := GREATEST(v_new_difficulty, v_min_difficulty);

  -- Redondear para evitar decimales excesivos
  v_new_difficulty := ROUND(v_new_difficulty);

  -- Actualizar si hay cambio significativo (>1%)
  IF ABS(v_new_difficulty - v_current_difficulty) / v_current_difficulty > 0.01 THEN
    UPDATE network_stats
    SET difficulty = v_new_difficulty, updated_at = NOW()
    WHERE id = 'current';

    RETURN json_build_object(
      'adjusted', true,
      'old_difficulty', v_current_difficulty,
      'new_difficulty', v_new_difficulty,
      'hashrate', v_current_hashrate,
      'change_percent', ROUND(((v_new_difficulty - v_current_difficulty) / v_current_difficulty) * 100, 2)
    );
  END IF;

  RETURN json_build_object(
    'adjusted', false,
    'reason', 'No significant change needed',
    'difficulty', v_current_difficulty
  );
END;
$$;

-- Game tick principal (ejecutar cada minuto)
CREATE OR REPLACE FUNCTION game_tick()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_resources_processed INT := 0;
  v_block_mined BOOLEAN := false;
  v_block_height INT;
  v_difficulty_result JSON;
BEGIN
  -- Procesar decay de recursos
  v_resources_processed := process_resource_decay();

  -- Ajustar dificultad antes de intentar minar
  v_difficulty_result := adjust_difficulty();

  -- Intentar minar bloque
  SELECT * INTO v_block_mined, v_block_height FROM process_mining_tick();

  RETURN json_build_object(
    'success', true,
    'resourcesProcessed', v_resources_processed,
    'blockMined', v_block_mined,
    'blockHeight', v_block_height,
    'difficultyAdjusted', (v_difficulty_result->>'adjusted')::BOOLEAN,
    'timestamp', NOW()
  );
END;
$$;

-- =====================================================
-- 6. FUNCIONES DE MERCADO
-- =====================================================

-- Order book
CREATE OR REPLACE FUNCTION get_order_book(p_item_type TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN json_build_object(
    'bids', (
      SELECT COALESCE(json_agg(row_to_json(t) ORDER BY price_per_unit DESC), '[]'::JSON)
      FROM (
        SELECT id, player_id, quantity, price_per_unit, remaining_quantity, created_at
        FROM market_orders
        WHERE item_type = p_item_type AND type = 'buy' AND status = 'active' AND remaining_quantity > 0
        LIMIT 50
      ) t
    ),
    'asks', (
      SELECT COALESCE(json_agg(row_to_json(t) ORDER BY price_per_unit ASC), '[]'::JSON)
      FROM (
        SELECT id, player_id, quantity, price_per_unit, remaining_quantity, created_at
        FROM market_orders
        WHERE item_type = p_item_type AND type = 'sell' AND status = 'active' AND remaining_quantity > 0
        LIMIT 50
      ) t
    )
  );
END;
$$;

-- Crear orden
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

  IF p_type = 'buy' THEN
    IF v_player.gamecoin_balance < v_total_cost THEN
      RETURN json_build_object('success', false, 'error', 'GameCoin insuficiente');
    END IF;
    UPDATE players SET gamecoin_balance = gamecoin_balance - v_total_cost WHERE id = p_player_id;
  ELSE
    IF p_item_type = 'crypto' AND v_player.crypto_balance < p_quantity THEN
      RETURN json_build_object('success', false, 'error', 'Crypto insuficiente');
    ELSIF p_item_type = 'energy' AND v_player.energy < p_quantity THEN
      RETURN json_build_object('success', false, 'error', 'Energía insuficiente');
    ELSIF p_item_type = 'internet' AND v_player.internet < p_quantity THEN
      RETURN json_build_object('success', false, 'error', 'Internet insuficiente');
    END IF;
  END IF;

  INSERT INTO market_orders (player_id, type, item_type, item_id, quantity, price_per_unit, remaining_quantity, status)
  VALUES (p_player_id, p_type, p_item_type, p_item_id, p_quantity, p_price_per_unit, p_quantity, 'active')
  RETURNING * INTO v_order;

  PERFORM match_market_orders(v_order.id);

  RETURN json_build_object('success', true, 'order', row_to_json(v_order));
END;
$$;

-- Match de órdenes
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
  IF v_order IS NULL OR v_order.status != 'active' THEN RETURN; END IF;

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
    IF v_order.remaining_quantity <= 0 THEN EXIT; END IF;

    v_trade_quantity := LEAST(v_order.remaining_quantity, v_match.remaining_quantity);
    v_trade_price := v_match.price_per_unit;

    PERFORM execute_trade(v_order, v_match, v_trade_quantity, v_trade_price);
    v_order.remaining_quantity := v_order.remaining_quantity - v_trade_quantity;
  END LOOP;

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

  UPDATE players SET gamecoin_balance = gamecoin_balance + v_total_value WHERE id = v_seller_id;

  INSERT INTO trades (buyer_id, seller_id, item_type, item_id, quantity, price_per_unit, total_value, taker_order_id, maker_order_id)
  VALUES (v_buyer_id, v_seller_id, p_taker.item_type, p_maker.item_id, p_quantity, p_price, v_total_value, p_taker.id, p_maker.id);

  UPDATE market_orders
  SET remaining_quantity = remaining_quantity - p_quantity,
      status = CASE WHEN remaining_quantity - p_quantity <= 0 THEN 'filled' ELSE 'active' END
  WHERE id = p_maker.id;

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

  IF v_order.type = 'buy' THEN
    v_refund := v_order.remaining_quantity * v_order.price_per_unit;
    UPDATE players SET gamecoin_balance = gamecoin_balance + v_refund WHERE id = p_player_id;
  END IF;

  UPDATE market_orders SET status = 'cancelled' WHERE id = p_order_id;

  RETURN json_build_object('success', true, 'refund', COALESCE(v_refund, 0));
END;
$$;

-- Órdenes del jugador
CREATE OR REPLACE FUNCTION get_player_orders(p_player_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN (
    SELECT COALESCE(json_agg(row_to_json(t)), '[]'::JSON)
    FROM (
      SELECT * FROM market_orders
      WHERE player_id = p_player_id AND status IN ('active', 'partially_filled')
      ORDER BY created_at DESC
    ) t
  );
END;
$$;

-- Trades del jugador
CREATE OR REPLACE FUNCTION get_player_trades(p_player_id UUID, p_limit INT DEFAULT 50)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN (
    SELECT COALESCE(json_agg(row_to_json(t)), '[]'::JSON)
    FROM (
      SELECT * FROM trades
      WHERE buyer_id = p_player_id OR seller_id = p_player_id
      ORDER BY created_at DESC
      LIMIT p_limit
    ) t
  );
END;
$$;

-- Estadísticas por item
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
  WHERE item_type = p_item_type AND created_at > NOW() - INTERVAL '24 hours';

  RETURN json_build_object(
    'volume', v_volume,
    'lastPrice', COALESCE(v_last_price, 0),
    'high', v_high,
    'low', CASE WHEN v_low = 0 AND v_trades = 0 THEN 0 ELSE v_low END,
    'trades', v_trades
  );
END;
$$;

-- Estadísticas del mercado
CREATE OR REPLACE FUNCTION get_market_stats()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN json_build_object(
    'crypto', get_item_stats('crypto'),
    'energy', get_item_stats('energy'),
    'internet', get_item_stats('internet'),
    'rig', get_item_stats('rig')
  );
END;
$$;

-- =====================================================
-- 7. FUNCIONES DE REFRIGERACIÓN
-- =====================================================

-- Obtener items de refrigeración disponibles
CREATE OR REPLACE FUNCTION get_cooling_items()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN (
    SELECT COALESCE(json_agg(row_to_json(t)), '[]'::JSON)
    FROM (
      SELECT id, name, description, cooling_power, base_price, tier
      FROM cooling_items
      ORDER BY base_price ASC
    ) t
  );
END;
$$;

-- Obtener refrigeración instalada del jugador
CREATE OR REPLACE FUNCTION get_player_cooling(p_player_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN json_build_object(
    'cooling_level', (SELECT COALESCE(cooling_level, 0) FROM players WHERE id = p_player_id),
    'items', (
      SELECT COALESCE(json_agg(row_to_json(t)), '[]'::JSON)
      FROM (
        SELECT pc.id, pc.installed_at,
               ci.id as item_id, ci.name, ci.description, ci.cooling_power, ci.tier
        FROM player_cooling pc
        JOIN cooling_items ci ON ci.id = pc.cooling_item_id
        WHERE pc.player_id = p_player_id
      ) t
    )
  );
END;
$$;

-- Instalar refrigeración (comprar e instalar)
CREATE OR REPLACE FUNCTION install_cooling(p_player_id UUID, p_cooling_id TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player players%ROWTYPE;
  v_cooling cooling_items%ROWTYPE;
  v_existing_count INT;
  v_new_cooling_level NUMERIC;
BEGIN
  -- Verificar jugador
  SELECT * INTO v_player FROM players WHERE id = p_player_id;
  IF v_player IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Jugador no encontrado');
  END IF;

  -- Verificar item de refrigeración
  SELECT * INTO v_cooling FROM cooling_items WHERE id = p_cooling_id;
  IF v_cooling IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Item de refrigeración no encontrado');
  END IF;

  -- Verificar si ya lo tiene instalado
  SELECT COUNT(*) INTO v_existing_count
  FROM player_cooling
  WHERE player_id = p_player_id AND cooling_item_id = p_cooling_id;

  IF v_existing_count > 0 THEN
    RETURN json_build_object('success', false, 'error', 'Ya tienes este item instalado');
  END IF;

  -- Verificar balance
  IF v_player.gamecoin_balance < v_cooling.base_price THEN
    RETURN json_build_object('success', false, 'error', 'GameCoin insuficiente');
  END IF;

  -- Descontar GameCoin
  UPDATE players
  SET gamecoin_balance = gamecoin_balance - v_cooling.base_price
  WHERE id = p_player_id;

  -- Registrar transacción
  INSERT INTO transactions (player_id, type, amount, currency, description)
  VALUES (p_player_id, 'cooling_purchase', -v_cooling.base_price, 'gamecoin',
          'Compra de refrigeración: ' || v_cooling.name);

  -- Instalar refrigeración
  INSERT INTO player_cooling (player_id, cooling_item_id)
  VALUES (p_player_id, p_cooling_id);

  -- Calcular nuevo nivel de refrigeración
  SELECT COALESCE(SUM(ci.cooling_power), 0) INTO v_new_cooling_level
  FROM player_cooling pc
  JOIN cooling_items ci ON ci.id = pc.cooling_item_id
  WHERE pc.player_id = p_player_id;

  -- Actualizar cooling_level del jugador
  UPDATE players SET cooling_level = v_new_cooling_level WHERE id = p_player_id;

  RETURN json_build_object(
    'success', true,
    'cooling_level', v_new_cooling_level,
    'item', row_to_json(v_cooling)
  );
END;
$$;

-- Comprar refrigeración (va al inventario)
CREATE OR REPLACE FUNCTION buy_cooling(p_player_id UUID, p_cooling_id TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player players%ROWTYPE;
  v_cooling cooling_items%ROWTYPE;
  v_existing_installed INT;
BEGIN
  -- Verificar jugador
  SELECT * INTO v_player FROM players WHERE id = p_player_id;
  IF v_player IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Jugador no encontrado');
  END IF;

  -- Verificar item de refrigeración
  SELECT * INTO v_cooling FROM cooling_items WHERE id = p_cooling_id;
  IF v_cooling IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Item de refrigeración no encontrado');
  END IF;

  -- Verificar si ya lo tiene instalado
  SELECT COUNT(*) INTO v_existing_installed
  FROM player_cooling
  WHERE player_id = p_player_id AND cooling_item_id = p_cooling_id;

  IF v_existing_installed > 0 THEN
    RETURN json_build_object('success', false, 'error', 'Ya tienes este item instalado');
  END IF;

  -- Verificar balance
  IF v_player.gamecoin_balance < v_cooling.base_price THEN
    RETURN json_build_object('success', false, 'error', 'GameCoin insuficiente');
  END IF;

  -- Descontar GameCoin
  UPDATE players
  SET gamecoin_balance = gamecoin_balance - v_cooling.base_price
  WHERE id = p_player_id;

  -- Registrar transacción
  INSERT INTO transactions (player_id, type, amount, currency, description)
  VALUES (p_player_id, 'cooling_purchase', -v_cooling.base_price, 'gamecoin',
          'Compra de refrigeración: ' || v_cooling.name);

  -- Agregar al inventario
  INSERT INTO player_inventory (player_id, item_type, item_id)
  VALUES (p_player_id, 'cooling', p_cooling_id)
  ON CONFLICT (player_id, item_type, item_id)
  DO UPDATE SET quantity = player_inventory.quantity + 1;

  RETURN json_build_object(
    'success', true,
    'item', row_to_json(v_cooling),
    'message', 'Item agregado al inventario'
  );
END;
$$;

-- Instalar refrigeración desde inventario (DEPRECADO - usar install_cooling_to_rig)
CREATE OR REPLACE FUNCTION install_cooling_from_inventory(p_player_id UUID, p_cooling_id TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN json_build_object('success', false, 'error', 'Usa install_cooling_to_rig para instalar refrigeración en un rig específico');
END;
$$;

-- Instalar refrigeración en un rig específico
CREATE OR REPLACE FUNCTION install_cooling_to_rig(p_player_id UUID, p_rig_id UUID, p_cooling_id TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_inventory_item player_inventory%ROWTYPE;
  v_cooling cooling_items%ROWTYPE;
  v_rig player_rigs%ROWTYPE;
  v_existing_cooling INT;
BEGIN
  -- Verificar que el rig pertenece al jugador
  SELECT * INTO v_rig
  FROM player_rigs
  WHERE id = p_rig_id AND player_id = p_player_id;

  IF v_rig IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Rig no encontrado');
  END IF;

  -- Verificar que el item está en inventario
  SELECT * INTO v_inventory_item
  FROM player_inventory
  WHERE player_id = p_player_id AND item_type = 'cooling' AND item_id = p_cooling_id;

  IF v_inventory_item IS NULL OR v_inventory_item.quantity <= 0 THEN
    RETURN json_build_object('success', false, 'error', 'No tienes este item en tu inventario');
  END IF;

  -- Verificar si este tipo de cooling ya está instalado en este rig
  SELECT COUNT(*) INTO v_existing_cooling
  FROM rig_cooling
  WHERE player_rig_id = p_rig_id AND cooling_item_id = p_cooling_id;

  IF v_existing_cooling > 0 THEN
    RETURN json_build_object('success', false, 'error', 'Este rig ya tiene este tipo de refrigeración instalado');
  END IF;

  -- Obtener datos del item
  SELECT * INTO v_cooling FROM cooling_items WHERE id = p_cooling_id;

  -- Remover del inventario
  IF v_inventory_item.quantity > 1 THEN
    UPDATE player_inventory
    SET quantity = quantity - 1
    WHERE id = v_inventory_item.id;
  ELSE
    DELETE FROM player_inventory WHERE id = v_inventory_item.id;
  END IF;

  -- Instalar refrigeración en el rig
  INSERT INTO rig_cooling (player_rig_id, cooling_item_id, durability)
  VALUES (p_rig_id, p_cooling_id, 100);

  RETURN json_build_object(
    'success', true,
    'message', 'Refrigeración instalada en el rig',
    'item', row_to_json(v_cooling)
  );
END;
$$;

-- Obtener refrigeración instalada en un rig
CREATE OR REPLACE FUNCTION get_rig_cooling(p_rig_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN (
    SELECT COALESCE(json_agg(row_to_json(t)), '[]'::JSON)
    FROM (
      SELECT rc.id, rc.durability, rc.installed_at,
             ci.id as item_id, ci.name, ci.description, ci.cooling_power, ci.energy_cost, ci.tier
      FROM rig_cooling rc
      JOIN cooling_items ci ON ci.id = rc.cooling_item_id
      WHERE rc.player_rig_id = p_rig_id
      ORDER BY rc.installed_at DESC
    ) t
  );
END;
$$;

-- =====================================================
-- 8. FUNCIONES DE INVENTARIO
-- =====================================================

-- Obtener inventario del jugador
CREATE OR REPLACE FUNCTION get_player_inventory(p_player_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN json_build_object(
    'cooling', (
      SELECT COALESCE(json_agg(row_to_json(t)), '[]'::JSON)
      FROM (
        SELECT pi.id as inventory_id, pi.quantity, pi.purchased_at,
               ci.id, ci.name, ci.description, ci.cooling_power, ci.energy_cost, ci.base_price, ci.tier
        FROM player_inventory pi
        JOIN cooling_items ci ON ci.id = pi.item_id
        WHERE pi.player_id = p_player_id AND pi.item_type = 'cooling'
        ORDER BY pi.purchased_at DESC
      ) t
    ),
    'cards', (
      SELECT COALESCE(json_agg(row_to_json(t)), '[]'::JSON)
      FROM (
        SELECT pc.id, pc.code, pc.is_redeemed, pc.purchased_at,
               p.id as card_id, p.name, p.description, p.card_type, p.amount, p.tier
        FROM player_cards pc
        JOIN prepaid_cards p ON p.id = pc.card_id
        WHERE pc.player_id = p_player_id AND pc.is_redeemed = false
        ORDER BY pc.purchased_at DESC
      ) t
    ),
    'rigs', (
      SELECT COALESCE(json_agg(row_to_json(rig_data)), '[]'::JSON)
      FROM (
        SELECT
          pr.id,
          pr.is_active,
          pr.condition,
          pr.temperature,
          pr.acquired_at,
          pr.activated_at,
          COALESCE(pr.max_condition, 100) as max_condition,
          COALESCE(pr.times_repaired, 0) as times_repaired,
          r.id as rig_id,
          r.name,
          r.description,
          r.hashrate,
          r.power_consumption,
          r.internet_consumption,
          r.tier,
          r.repair_cost,
          (
            SELECT COALESCE(json_agg(json_build_object(
              'id', rc.id,
              'durability', rc.durability,
              'installed_at', rc.installed_at,
              'item_id', ci.id,
              'name', ci.name,
              'cooling_power', ci.cooling_power,
              'energy_cost', ci.energy_cost,
              'tier', ci.tier
            )), '[]'::JSON)
            FROM rig_cooling rc
            JOIN cooling_items ci ON ci.id = rc.cooling_item_id
            WHERE rc.player_rig_id = pr.id
          ) as installed_cooling
        FROM player_rigs pr
        JOIN rigs r ON r.id = pr.rig_id
        WHERE pr.player_id = p_player_id
        ORDER BY pr.acquired_at DESC
      ) rig_data
    )
  );
END;
$$;

-- =====================================================
-- 9. FUNCIONES DE TARJETAS PREPAGO
-- =====================================================

-- Obtener tarjetas prepago disponibles
CREATE OR REPLACE FUNCTION get_prepaid_cards()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN (
    SELECT COALESCE(json_agg(row_to_json(t)), '[]'::JSON)
    FROM (
      SELECT id, name, description, card_type, amount, base_price, tier
      FROM prepaid_cards
      ORDER BY card_type, base_price ASC
    ) t
  );
END;
$$;

-- Obtener tarjetas del jugador (no canjeadas)
CREATE OR REPLACE FUNCTION get_player_cards(p_player_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN (
    SELECT COALESCE(json_agg(row_to_json(t)), '[]'::JSON)
    FROM (
      SELECT pc.id, pc.code, pc.is_redeemed, pc.purchased_at, pc.redeemed_at,
             p.id as card_id, p.name, p.description, p.card_type, p.amount, p.tier
      FROM player_cards pc
      JOIN prepaid_cards p ON p.id = pc.card_id
      WHERE pc.player_id = p_player_id
      ORDER BY pc.is_redeemed ASC, pc.purchased_at DESC
    ) t
  );
END;
$$;

-- Comprar tarjeta prepago
CREATE OR REPLACE FUNCTION buy_prepaid_card(p_player_id UUID, p_card_id TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player players%ROWTYPE;
  v_card prepaid_cards%ROWTYPE;
  v_code TEXT;
  v_new_card_id UUID;
BEGIN
  -- Verificar jugador
  SELECT * INTO v_player FROM players WHERE id = p_player_id;
  IF v_player IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Jugador no encontrado');
  END IF;

  -- Verificar tarjeta
  SELECT * INTO v_card FROM prepaid_cards WHERE id = p_card_id;
  IF v_card IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Tarjeta no encontrada');
  END IF;

  -- Verificar balance
  IF v_player.gamecoin_balance < v_card.base_price THEN
    RETURN json_build_object('success', false, 'error', 'GameCoin insuficiente');
  END IF;

  -- Generar código único
  v_code := generate_card_code();

  -- Descontar GameCoin
  UPDATE players
  SET gamecoin_balance = gamecoin_balance - v_card.base_price
  WHERE id = p_player_id;

  -- Registrar transacción
  INSERT INTO transactions (player_id, type, amount, currency, description)
  VALUES (p_player_id, 'card_purchase', -v_card.base_price, 'gamecoin',
          'Compra de tarjeta: ' || v_card.name);

  -- Crear tarjeta para el jugador
  INSERT INTO player_cards (player_id, card_id, code)
  VALUES (p_player_id, p_card_id, v_code)
  RETURNING id INTO v_new_card_id;

  RETURN json_build_object(
    'success', true,
    'card', json_build_object(
      'id', v_new_card_id,
      'code', v_code,
      'name', v_card.name,
      'card_type', v_card.card_type,
      'amount', v_card.amount
    )
  );
END;
$$;

-- Canjear tarjeta prepago
CREATE OR REPLACE FUNCTION redeem_prepaid_card(p_player_id UUID, p_code TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_card player_cards%ROWTYPE;
  v_card prepaid_cards%ROWTYPE;
  v_new_value NUMERIC;
BEGIN
  -- Buscar tarjeta por código
  SELECT * INTO v_player_card
  FROM player_cards
  WHERE code = UPPER(TRIM(p_code)) AND player_id = p_player_id;

  IF v_player_card IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Código inválido o no te pertenece');
  END IF;

  IF v_player_card.is_redeemed THEN
    RETURN json_build_object('success', false, 'error', 'Esta tarjeta ya fue canjeada');
  END IF;

  -- Obtener datos de la tarjeta
  SELECT * INTO v_card FROM prepaid_cards WHERE id = v_player_card.card_id;

  -- Aplicar recarga según tipo (respetando máximo del jugador)
  IF v_card.card_type = 'energy' THEN
    UPDATE players
    SET energy = LEAST(max_energy, energy + v_card.amount)
    WHERE id = p_player_id
    RETURNING energy INTO v_new_value;

    INSERT INTO transactions (player_id, type, amount, currency, description)
    VALUES (p_player_id, 'energy_recharge', v_card.amount, 'gamecoin',
            'Recarga de energía: ' || v_card.name);
  ELSE
    UPDATE players
    SET internet = LEAST(max_internet, internet + v_card.amount)
    WHERE id = p_player_id
    RETURNING internet INTO v_new_value;

    INSERT INTO transactions (player_id, type, amount, currency, description)
    VALUES (p_player_id, 'internet_recharge', v_card.amount, 'gamecoin',
            'Recarga de internet: ' || v_card.name);
  END IF;

  -- Marcar tarjeta como canjeada
  UPDATE player_cards
  SET is_redeemed = true, redeemed_at = NOW()
  WHERE id = v_player_card.id;

  RETURN json_build_object(
    'success', true,
    'card_type', v_card.card_type,
    'amount', v_card.amount,
    'new_value', v_new_value
  );
END;
$$;

-- =====================================================
-- 9. FUNCIONES DE LEADERBOARD
-- =====================================================

-- Leaderboard de reputación
CREATE OR REPLACE FUNCTION get_reputation_leaderboard(p_limit INT DEFAULT 100)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN (
    SELECT COALESCE(json_agg(row_to_json(t)), '[]'::JSON)
    FROM (
      SELECT
        id as "playerId",
        username,
        reputation_score as score,
        get_rank_for_score(reputation_score) as rank
      FROM players
      ORDER BY reputation_score DESC
      LIMIT p_limit
    ) t
  );
END;
$$;

-- Leaderboard de minería
CREATE OR REPLACE FUNCTION get_mining_leaderboard(p_limit INT DEFAULT 100)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN (
    SELECT COALESCE(json_agg(row_to_json(t)), '[]'::JSON)
    FROM (
      SELECT
        p.id,
        p.username,
        p.reputation_score as reputation,
        COALESCE(p.blocks_mined, 0) as "blocksMined",
        COALESCE((
          SELECT SUM(r.hashrate * (pr.condition / 100.0))
          FROM player_rigs pr
          JOIN rigs r ON r.id = pr.rig_id
          WHERE pr.player_id = p.id AND pr.is_active = true
        ), 0) as hashrate
      FROM players p
      ORDER BY COALESCE(p.blocks_mined, 0) DESC
      LIMIT p_limit
    ) t
  );
END;
$$;

-- =====================================================
-- 10. FUNCIONES DE EXCHANGE (CRYPTO)
-- =====================================================

-- Agregar columna ron_balance si no existe
ALTER TABLE players ADD COLUMN IF NOT EXISTS ron_balance NUMERIC DEFAULT 0;

-- Tasa de cambio: 1 crypto = 10 GameCoin (ajustable)
-- Tasa de conversión RON: 100 crypto = 1 RON (ajustable)

-- Exchange: Crypto → GameCoin
CREATE OR REPLACE FUNCTION exchange_crypto_to_gamecoin(p_player_id UUID, p_crypto_amount NUMERIC)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player players%ROWTYPE;
  v_exchange_rate NUMERIC := 10;  -- 1 crypto = 10 GameCoin
  v_gamecoin_received NUMERIC;
BEGIN
  -- Validar cantidad
  IF p_crypto_amount <= 0 THEN
    RETURN json_build_object('success', false, 'error', 'La cantidad debe ser mayor a 0');
  END IF;

  -- Verificar jugador
  SELECT * INTO v_player FROM players WHERE id = p_player_id;
  IF v_player IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Jugador no encontrado');
  END IF;

  -- Verificar balance de crypto
  IF v_player.crypto_balance < p_crypto_amount THEN
    RETURN json_build_object('success', false, 'error', 'Crypto insuficiente', 'balance', v_player.crypto_balance);
  END IF;

  -- Calcular GameCoin a recibir
  v_gamecoin_received := p_crypto_amount * v_exchange_rate;

  -- Realizar el exchange
  UPDATE players
  SET crypto_balance = crypto_balance - p_crypto_amount,
      gamecoin_balance = gamecoin_balance + v_gamecoin_received
  WHERE id = p_player_id;

  -- Registrar transacción
  INSERT INTO transactions (player_id, type, amount, currency, description)
  VALUES (p_player_id, 'crypto_to_gamecoin', -p_crypto_amount, 'crypto',
          'Exchange: ' || p_crypto_amount || ' crypto → ' || v_gamecoin_received || ' GameCoin');

  RETURN json_build_object(
    'success', true,
    'crypto_spent', p_crypto_amount,
    'gamecoin_received', v_gamecoin_received,
    'exchange_rate', v_exchange_rate
  );
END;
$$;

-- Exchange: Crypto → RON (retiro)
CREATE OR REPLACE FUNCTION exchange_crypto_to_ron(p_player_id UUID, p_crypto_amount NUMERIC)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player players%ROWTYPE;
  v_exchange_rate NUMERIC := 0.00001;  -- 1000 crypto = 0.01 RON
  v_min_amount NUMERIC := 100000;  -- Mínimo 100000 crypto para convertir (= 1 RON)
  v_ron_received NUMERIC;
BEGIN
  -- Validar cantidad mínima
  IF p_crypto_amount < v_min_amount THEN
    RETURN json_build_object('success', false, 'error', 'Mínimo ' || v_min_amount || ' crypto para convertir a RON');
  END IF;

  -- Verificar jugador
  SELECT * INTO v_player FROM players WHERE id = p_player_id;
  IF v_player IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Jugador no encontrado');
  END IF;

  -- Verificar balance de crypto
  IF v_player.crypto_balance < p_crypto_amount THEN
    RETURN json_build_object('success', false, 'error', 'Crypto insuficiente', 'balance', v_player.crypto_balance);
  END IF;

  -- Calcular RON a recibir
  v_ron_received := p_crypto_amount * v_exchange_rate;

  -- Realizar el exchange
  UPDATE players
  SET crypto_balance = crypto_balance - p_crypto_amount,
      ron_balance = COALESCE(ron_balance, 0) + v_ron_received
  WHERE id = p_player_id;

  -- Registrar transacción
  INSERT INTO transactions (player_id, type, amount, currency, description)
  VALUES (p_player_id, 'crypto_to_ron', -p_crypto_amount, 'crypto',
          'Exchange: ' || p_crypto_amount || ' crypto → ' || v_ron_received || ' RON');

  RETURN json_build_object(
    'success', true,
    'crypto_spent', p_crypto_amount,
    'ron_received', v_ron_received,
    'exchange_rate', v_exchange_rate
  );
END;
$$;

-- Obtener tasas de exchange actuales
CREATE OR REPLACE FUNCTION get_exchange_rates()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN json_build_object(
    'crypto_to_gamecoin', 10,  -- 1 crypto = 10 GameCoin
    'crypto_to_ron', 0.00001,  -- 1000 crypto = 0.01 RON
    'min_crypto_for_ron', 100000  -- Mínimo para convertir a RON (= 1 RON)
  );
END;
$$;

-- =====================================================
-- INICIALIZACIÓN
-- =====================================================

INSERT INTO network_stats (id, difficulty, hashrate)
VALUES ('current', 1000, 0)
ON CONFLICT (id) DO NOTHING;

-- =====================================================
-- 10. CRON JOBS (pg_cron)
-- =====================================================
-- NOTA: En Supabase, pg_cron ya está habilitado.
-- Configurar el cron job manualmente desde Supabase Dashboard:
-- 1. Ir a Database -> Extensions -> Verificar que pg_cron esté habilitado
-- 2. Ir a SQL Editor y ejecutar:
--    SELECT cron.schedule('game_tick_job', '* * * * *', 'SELECT run_decay_cycle()');
-- 3. Para verificar: SELECT * FROM cron.job;
-- 4. Para eliminar: SELECT cron.unschedule('game_tick_job');

-- Función que ejecuta el decay 6 veces por minuto (cada ~10 segundos)
CREATE OR REPLACE FUNCTION run_decay_cycle()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  PERFORM process_resource_decay();
  PERFORM pg_sleep(10);
  PERFORM process_resource_decay();
  PERFORM pg_sleep(10);
  PERFORM process_resource_decay();
  PERFORM pg_sleep(10);
  PERFORM process_resource_decay();
  PERFORM pg_sleep(10);
  PERFORM process_resource_decay();
  PERFORM pg_sleep(10);
  PERFORM process_resource_decay();
END;
$$;
