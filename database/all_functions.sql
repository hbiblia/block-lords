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
DROP FUNCTION IF EXISTS apply_passive_regeneration(UUID) CASCADE;
DROP FUNCTION IF EXISTS get_streak_status(UUID) CASCADE;
DROP FUNCTION IF EXISTS claim_daily_streak(UUID) CASCADE;
DROP FUNCTION IF EXISTS get_daily_missions(UUID) CASCADE;
DROP FUNCTION IF EXISTS assign_daily_missions(UUID) CASCADE;
DROP FUNCTION IF EXISTS update_mission_progress(UUID, TEXT, NUMERIC) CASCADE;
DROP FUNCTION IF EXISTS claim_mission_reward(UUID, UUID) CASCADE;
DROP FUNCTION IF EXISTS record_online_heartbeat(UUID) CASCADE;
DROP FUNCTION IF EXISTS get_player_slot_info(UUID) CASCADE;
DROP FUNCTION IF EXISTS buy_rig_slot(UUID) CASCADE;
DROP FUNCTION IF EXISTS get_rig_slot_upgrades() CASCADE;
DROP FUNCTION IF EXISTS get_crypto_packages() CASCADE;
DROP FUNCTION IF EXISTS buy_crypto_package(UUID, TEXT, TEXT) CASCADE;
DROP FUNCTION IF EXISTS get_player_crypto_purchases(UUID, INTEGER) CASCADE;

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

-- Regeneración pasiva de recursos (se aplica al login)
-- Energía: +1 cada 10 minutos offline
-- Internet: +1 cada 15 minutos offline
-- Cap: 50% de max_energy/max_internet
CREATE OR REPLACE FUNCTION apply_passive_regeneration(p_player_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player players%ROWTYPE;
  v_minutes_offline NUMERIC;
  v_energy_regen NUMERIC;
  v_internet_regen NUMERIC;
  v_max_energy_cap NUMERIC;
  v_max_internet_cap NUMERIC;
  v_new_energy NUMERIC;
  v_new_internet NUMERIC;
  v_energy_gained NUMERIC := 0;
  v_internet_gained NUMERIC := 0;
  v_was_offline BOOLEAN;
BEGIN
  -- LOCK: Seleccionar con FOR UPDATE para evitar race conditions
  SELECT * INTO v_player FROM players WHERE id = p_player_id FOR UPDATE;

  IF v_player IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Player not found');
  END IF;

  -- Guardar estado offline ANTES de marcarlo online
  v_was_offline := (v_player.is_online = false AND v_player.last_seen IS NOT NULL);

  -- Marcar como online INMEDIATAMENTE para evitar múltiples regeneraciones
  UPDATE players
  SET is_online = true, last_seen = NOW()
  WHERE id = p_player_id;

  -- Calcular minutos offline (solo si estaba offline)
  IF v_was_offline THEN
    v_minutes_offline := EXTRACT(EPOCH FROM (NOW() - v_player.last_seen)) / 60.0;

    -- Cap a 24 horas (1440 minutos) para evitar regeneración masiva
    v_minutes_offline := LEAST(v_minutes_offline, 1440);

    -- Solo regenerar si estuvo offline al menos 10 minutos
    IF v_minutes_offline >= 10 THEN
      -- Calcular regeneración: +1 energía por 10 min, +1 internet por 15 min
      v_energy_regen := FLOOR(v_minutes_offline / 10.0);
      v_internet_regen := FLOOR(v_minutes_offline / 15.0);

      -- Calcular cap de 50%
      v_max_energy_cap := COALESCE(v_player.max_energy, 100) * 0.5;
      v_max_internet_cap := COALESCE(v_player.max_internet, 100) * 0.5;

      -- Aplicar regeneración con cap
      v_new_energy := LEAST(v_max_energy_cap, v_player.energy + v_energy_regen);
      v_new_internet := LEAST(v_max_internet_cap, v_player.internet + v_internet_regen);

      -- Calcular ganancia real
      v_energy_gained := GREATEST(0, v_new_energy - v_player.energy);
      v_internet_gained := GREATEST(0, v_new_internet - v_player.internet);

      -- Solo actualizar si hay algo que ganar
      IF v_energy_gained > 0 OR v_internet_gained > 0 THEN
        UPDATE players
        SET energy = v_new_energy,
            internet = v_new_internet
        WHERE id = p_player_id;
      END IF;
    END IF;
  END IF; -- v_was_offline

  RETURN json_build_object(
    'success', true,
    'energyGained', COALESCE(v_energy_gained, 0),
    'internetGained', COALESCE(v_internet_gained, 0),
    'minutesOffline', COALESCE(v_minutes_offline, 0),
    'currentEnergy', COALESCE(v_new_energy, v_player.energy),
    'currentInternet', COALESCE(v_new_internet, v_player.internet),
    'energyCap', v_max_energy_cap,
    'internetCap', v_max_internet_cap
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
  VALUES (p_user_id, p_email, p_username, 1000, 0, 100, 100, 50, 'global')
  RETURNING * INTO v_player;

  -- Dar rig inicial
  INSERT INTO player_rigs (player_id, rig_id, condition, is_active)
  VALUES (p_user_id, 'basic_miner', 100, false);

  -- Registrar transacción de bienvenida
  INSERT INTO transactions (player_id, type, amount, currency, description)
  VALUES (p_user_id, 'welcome_bonus', 1000, 'gamecoin', 'Bonus de bienvenida');

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
  v_power_consumption NUMERIC;
  v_internet_consumption NUMERIC;
  v_player_energy NUMERIC;
  v_player_internet NUMERIC;
BEGIN
  -- Obtener el rig (sin lock explícito - el UPDATE es atómico)
  SELECT * INTO v_rig
  FROM player_rigs
  WHERE id = p_rig_id AND player_id = p_player_id;

  IF v_rig IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Rig no encontrado');
  END IF;

  -- Verificar si se quiere encender un rig
  IF NOT v_rig.is_active THEN
    -- No permitir encender si condición es 0
    IF v_rig.condition <= 0 THEN
      RETURN json_build_object('success', false, 'error', 'El rig está roto. Debes repararlo o eliminarlo.');
    END IF;

    -- Obtener información del rig y jugador
    SELECT r.power_consumption, r.internet_consumption, p.energy, p.internet
    INTO v_power_consumption, v_internet_consumption, v_player_energy, v_player_internet
    FROM rigs r, players p
    WHERE r.id = v_rig.rig_id AND p.id = p_player_id;

    -- Verificar que hay suficientes recursos para al menos un tick
    IF v_player_energy < v_power_consumption THEN
      RETURN json_build_object('success', false, 'error', 'Energía insuficiente. Necesitas al menos ' || v_power_consumption || ' para este rig.');
    END IF;

    IF v_player_internet < v_internet_consumption THEN
      RETURN json_build_object('success', false, 'error', 'Internet insuficiente. Necesitas al menos ' || v_internet_consumption || ' para este rig.');
    END IF;
  END IF;

  UPDATE player_rigs
  SET is_active = NOT is_active,
      activated_at = CASE WHEN NOT is_active THEN NOW() ELSE NULL END,
      temperature = 0
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
  v_total_rigs INT;
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

  -- Verificar slots disponibles
  SELECT COUNT(*) INTO v_total_rigs
  FROM player_rigs
  WHERE player_id = p_player_id;

  IF v_total_rigs >= v_player.rig_slots THEN
    RETURN json_build_object(
      'success', false,
      'error', 'No tienes slots disponibles. Compra más slots para agregar rigs.',
      'slots_used', v_total_rigs,
      'slots_total', v_player.rig_slots
    );
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
    'rig', row_to_json(v_rig),
    'slots_used', v_total_rigs + 1,
    'slots_total', v_player.rig_slots
  );
END;
$$;

-- =====================================================
-- FUNCIONES DE SLOTS DE RIGS
-- =====================================================

-- Obtener lista de upgrades de slots disponibles
CREATE OR REPLACE FUNCTION get_rig_slot_upgrades()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN (
    SELECT COALESCE(json_agg(row_to_json(u) ORDER BY u.slot_number), '[]'::JSON)
    FROM rig_slot_upgrades u
  );
END;
$$;

-- Obtener información de slots del jugador
CREATE OR REPLACE FUNCTION get_player_slot_info(p_player_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player players%ROWTYPE;
  v_rigs_count INT;
  v_next_upgrade rig_slot_upgrades%ROWTYPE;
BEGIN
  -- Obtener jugador
  SELECT * INTO v_player FROM players WHERE id = p_player_id;
  IF v_player IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Jugador no encontrado');
  END IF;

  -- Contar rigs actuales
  SELECT COUNT(*) INTO v_rigs_count
  FROM player_rigs
  WHERE player_id = p_player_id;

  -- Obtener siguiente upgrade disponible
  SELECT * INTO v_next_upgrade
  FROM rig_slot_upgrades
  WHERE slot_number = v_player.rig_slots + 1;

  RETURN json_build_object(
    'success', true,
    'current_slots', v_player.rig_slots,
    'used_slots', v_rigs_count,
    'available_slots', v_player.rig_slots - v_rigs_count,
    'max_slots', 20,
    'next_upgrade', CASE
      WHEN v_next_upgrade IS NOT NULL THEN json_build_object(
        'slot_number', v_next_upgrade.slot_number,
        'price', v_next_upgrade.price,
        'currency', v_next_upgrade.currency,
        'name', v_next_upgrade.name,
        'description', v_next_upgrade.description
      )
      ELSE NULL
    END
  );
END;
$$;

-- Comprar un slot adicional
CREATE OR REPLACE FUNCTION buy_rig_slot(p_player_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player players%ROWTYPE;
  v_upgrade rig_slot_upgrades%ROWTYPE;
  v_new_slots INT;
BEGIN
  -- Obtener jugador
  SELECT * INTO v_player FROM players WHERE id = p_player_id;
  IF v_player IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Jugador no encontrado');
  END IF;

  -- Verificar si ya tiene el máximo
  IF v_player.rig_slots >= 20 THEN
    RETURN json_build_object('success', false, 'error', 'Ya tienes el máximo de slots (20)');
  END IF;

  -- Obtener el precio del siguiente slot
  SELECT * INTO v_upgrade
  FROM rig_slot_upgrades
  WHERE slot_number = v_player.rig_slots + 1;

  IF v_upgrade IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Upgrade no disponible');
  END IF;

  -- Verificar balance según la moneda requerida
  IF v_upgrade.currency = 'gamecoin' THEN
    IF v_player.gamecoin_balance < v_upgrade.price THEN
      RETURN json_build_object(
        'success', false,
        'error', 'GameCoin insuficiente',
        'required', v_upgrade.price,
        'current', v_player.gamecoin_balance
      );
    END IF;

    -- Descontar GameCoin
    UPDATE players
    SET gamecoin_balance = gamecoin_balance - v_upgrade.price
    WHERE id = p_player_id;

    -- Registrar transacción
    INSERT INTO transactions (player_id, type, amount, currency, description)
    VALUES (p_player_id, 'slot_purchase', -v_upgrade.price, 'gamecoin',
            'Compra de ' || v_upgrade.name);

  ELSIF v_upgrade.currency = 'crypto' THEN
    IF v_player.crypto_balance < v_upgrade.price THEN
      RETURN json_build_object(
        'success', false,
        'error', 'Crypto insuficiente',
        'required', v_upgrade.price,
        'current', v_player.crypto_balance
      );
    END IF;

    -- Descontar Crypto
    UPDATE players
    SET crypto_balance = crypto_balance - v_upgrade.price
    WHERE id = p_player_id;

    -- Registrar transacción
    INSERT INTO transactions (player_id, type, amount, currency, description)
    VALUES (p_player_id, 'slot_purchase', -v_upgrade.price, 'crypto',
            'Compra de ' || v_upgrade.name);
  END IF;

  -- Aumentar slots
  v_new_slots := v_player.rig_slots + 1;
  UPDATE players
  SET rig_slots = v_new_slots
  WHERE id = p_player_id;

  RETURN json_build_object(
    'success', true,
    'new_slots', v_new_slots,
    'purchased', v_upgrade.name,
    'price_paid', v_upgrade.price,
    'currency', v_upgrade.currency
  );
END;
$$;

-- =====================================================
-- 4. FUNCIONES DE RECURSOS
-- =====================================================

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
  -- Boost multipliers
  v_boosts JSON;
  v_energy_mult NUMERIC;
  v_internet_mult NUMERIC;
  v_temp_mult NUMERIC;
  v_durability_mult NUMERIC;
BEGIN
  -- Solo procesar jugadores que están ONLINE (en el juego)
  FOR v_player IN
    SELECT p.id, p.energy, p.internet
    FROM players p
    WHERE p.is_online = true
      AND EXISTS (SELECT 1 FROM player_rigs pr WHERE pr.player_id = p.id AND pr.is_active = true)
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
      -- Obtener multiplicadores de boosts específicos de ESTE rig
      v_boosts := get_rig_boost_multipliers(v_rig.id);
      v_energy_mult := COALESCE((v_boosts->>'energy')::NUMERIC, 1.0);
      v_internet_mult := COALESCE((v_boosts->>'internet')::NUMERIC, 1.0);
      v_temp_mult := COALESCE((v_boosts->>'temperature')::NUMERIC, 1.0);
      v_durability_mult := COALESCE((v_boosts->>'durability')::NUMERIC, 1.0);
      -- Obtener refrigeración instalada en este rig específico
      -- Eficiencia del cooling basada en durabilidad:
      -- >= 50%: eficiencia lineal (durability/100)
      -- < 50%: penalización adicional (durability/100 * durability/50)
      -- Esto hace que cooling degradado sea menos efectivo
      SELECT
        COALESCE(SUM(ci.cooling_power * (
          CASE WHEN rc.durability >= 50 THEN rc.durability / 100.0
               ELSE (rc.durability / 100.0) * (rc.durability / 50.0)
          END
        )), 0),
        COALESCE(SUM(ci.energy_cost * (
          CASE WHEN rc.durability >= 50 THEN rc.durability / 100.0
               ELSE (rc.durability / 100.0) * (rc.durability / 50.0)
          END
        )), 0)
      INTO v_rig_cooling_power, v_rig_cooling_energy
      FROM rig_cooling rc
      JOIN cooling_items ci ON ci.id = rc.cooling_item_id
      WHERE rc.player_rig_id = v_rig.id AND rc.durability > 0;

      -- Calcular consumo de energía del rig:
      -- Base + penalización por temperatura + consumo de refrigeración
      -- Temperatura > 40°C aumenta consumo hasta 50% extra a 100°C
      -- Aplicar multiplicador de boost de energy_saver (por rig)
      v_total_power := v_total_power +
        ((v_rig.power_consumption * (1 + GREATEST(0, (v_rig.temperature - 40)) * 0.0083)) +
        v_rig_cooling_energy) * v_energy_mult;

      -- Aplicar multiplicador de boost de bandwidth_optimizer (por rig)
      v_total_internet := v_total_internet + (v_rig.internet_consumption * v_internet_mult);

      -- Calcular aumento de temperatura basado en consumo de energía
      -- Calentamiento GRADUAL para que no sea abrupto
      -- Sin cooling: 1-2 min para llegar a temperatura peligrosa
      -- Con cooling apropiado: se mantiene estable
      -- Aplicar multiplicador de boost de coolant_injection
      IF v_rig_cooling_power <= 0 THEN
        -- Sin cooling: calentamiento gradual (max 10°C por tick)
        -- Minero Básico (2.5): +1.25°C/tick → peligro en ~8 min
        -- ASIC S19 (18): +9°C/tick → peligro en ~1 min
        -- Quantum (55): +10°C/tick (cap) → peligro en ~1 min
        v_temp_increase := LEAST(v_rig.power_consumption * 0.5, 10) * v_temp_mult;
      ELSE
        -- Con cooling: calentamiento reducido menos poder de refrigeración
        v_temp_increase := v_rig.power_consumption * 0.3;
        v_temp_increase := GREATEST(0, v_temp_increase - v_rig_cooling_power) * v_temp_mult;
      END IF;

      -- Calcular nueva temperatura
      v_new_temp := v_rig.temperature + v_temp_increase;

      -- Enfriamiento pasivo hacia temperatura ambiente
      IF v_new_temp > v_ambient_temp THEN
        IF v_rig_cooling_power <= 0 THEN
          -- Sin cooling: enfriamiento pasivo mínimo (1°C por tick)
          v_new_temp := v_new_temp - 1.0;
        ELSE
          -- Con cooling: enfriamiento basado en poder de refrigeración
          -- Cooling fuerte = enfriamiento rápido hacia temp ambiente
          v_new_temp := v_new_temp - (1.0 + (v_rig_cooling_power * 0.1));
        END IF;
        v_new_temp := GREATEST(v_ambient_temp, v_new_temp);
      END IF;

      -- Limitar temperatura máxima a 100
      v_new_temp := LEAST(100, v_new_temp);

      -- Calcular deterioro BASADO EN TEMPERATURA
      -- Si temperatura = 0: SIN deterioro
      -- El deterioro escala con la temperatura de forma progresiva
      -- 0°C: 0% deterioro
      -- 1-50°C: deterioro bajo (0.02% por °C)
      -- 50-70°C: deterioro moderado (0.05% por °C extra)
      -- 70-85°C: deterioro severo (0.1% por °C extra)
      -- 85-100°C: deterioro crítico exponencial

      IF v_new_temp <= 0 THEN
        -- Sin temperatura, sin deterioro
        v_deterioration := 0;
      ELSIF v_new_temp <= 50 THEN
        -- Deterioro bajo: 0.02% por cada °C
        v_deterioration := v_new_temp * 0.02;
      ELSIF v_new_temp <= 70 THEN
        -- Deterioro moderado: base de 50°C + extra por cada °C sobre 50
        v_deterioration := (50 * 0.02) + ((v_new_temp - 50) * 0.05);
      ELSIF v_new_temp <= 85 THEN
        -- Deterioro severo: base hasta 70°C + extra por cada °C sobre 70
        v_deterioration := (50 * 0.02) + (20 * 0.05) + ((v_new_temp - 70) * 0.1);
      ELSE
        -- Deterioro crítico: base hasta 85°C + escala exponencial
        v_deterioration := (50 * 0.02) + (20 * 0.05) + (15 * 0.1) +
                          POWER((v_new_temp - 85) / 15.0, 2) * 3.0;
      END IF;

      -- Con cooling instalado: reducir desgaste (2x menos)
      IF v_rig_cooling_power > 0 AND v_deterioration > 0 THEN
        v_deterioration := v_deterioration / 2.0;
      END IF;

      -- Aplicar multiplicador de boost de durability_shield
      v_deterioration := v_deterioration * v_durability_mult;

      -- Aplicar deterioro y actualizar temperatura
      UPDATE player_rigs
      SET temperature = v_new_temp,
          condition = GREATEST(0, condition - v_deterioration)
      WHERE id = v_rig.id;

      -- Consumir durabilidad de la refrigeración instalada en este rig
      -- La refrigeración se desgasta más rápido si:
      -- 1. La temperatura es alta (>40°C)
      -- 2. El rig genera más calor del que el cooling puede manejar (exceso de calor)
      -- ~30 min de duración a temperatura normal (0.5% base = ~33 min)
      -- Exceso de calor = (power_consumption * 0.3) - cooling_power
      UPDATE rig_cooling
      SET durability = GREATEST(0, durability - (
        0.5 +  -- Base
        (GREATEST(0, v_new_temp - 40) * 0.02) +  -- Por temperatura alta
        (GREATEST(0, (v_rig.power_consumption * 0.3) - v_rig_cooling_power) * 0.15)  -- Por exceso de calor
      ))
      WHERE player_rig_id = v_rig.id AND durability > 0;

      -- Eliminar refrigeración agotada
      DELETE FROM rig_cooling WHERE player_rig_id = v_rig.id AND durability <= 0;

      -- Decrementar tiempo restante de boosts activos de este rig
      -- El boost solo cuenta tiempo cuando el rig está minando (is_active = true)
      UPDATE rig_boosts
      SET remaining_seconds = remaining_seconds - 1
      WHERE player_rig_id = v_rig.id AND remaining_seconds > 0;

      -- Eliminar boosts expirados
      DELETE FROM rig_boosts WHERE player_rig_id = v_rig.id AND remaining_seconds <= 0;

      -- Si condición llega a 0, apagar el rig y resetear temperatura
      IF (v_rig.condition - v_deterioration) <= 0 THEN
        UPDATE player_rigs SET is_active = false, temperature = 0 WHERE id = v_rig.id;
        INSERT INTO player_events (player_id, type, data)
        VALUES (v_player.id, 'rig_broken', json_build_object(
          'rig_id', v_rig.id,
          'reason', 'wear_and_tear'
        ));
      END IF;
    END LOOP;

    -- Calcular nuevo nivel de energía e internet
    -- Internet consume más rápido que energía (incentiva comprar tarjetas de internet)
    -- Los multiplicadores de boost ya fueron aplicados por rig en el loop anterior
    v_new_energy := GREATEST(0, v_player.energy - (v_total_power * 0.1));
    v_new_internet := GREATEST(0, v_player.internet - (v_total_internet * 0.15));

    -- Actualizar recursos del jugador
    UPDATE players
    SET energy = v_new_energy,
        internet = v_new_internet
    WHERE id = v_player.id;

    -- Apagar rigs si no hay energía o internet y resetear temperatura
    IF v_new_energy = 0 OR v_new_internet = 0 THEN
      UPDATE player_rigs SET is_active = false, temperature = 0 WHERE player_id = v_player.id;
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
  -- Boost multipliers
  v_boosts JSON;
  v_hashrate_mult NUMERIC;
  v_luck_mult NUMERIC;
  v_current_player_id UUID := NULL;
  v_total_luck_mult NUMERIC := 1.0;
  v_luck_count INTEGER := 0;
BEGIN
  SELECT COALESCE(ns.difficulty, 1000) INTO v_difficulty FROM network_stats ns WHERE ns.id = 'current';
  IF v_difficulty IS NULL THEN v_difficulty := 1000; END IF;

  -- Calcular hashrate total con penalizaciones por temperatura y condición
  FOR v_rig IN
    SELECT pr.id as rig_id, pr.player_id, pr.condition, pr.temperature, r.hashrate, p.reputation_score
    FROM player_rigs pr
    JOIN rigs r ON r.id = pr.rig_id
    JOIN players p ON p.id = pr.player_id
    WHERE pr.is_active = true AND p.is_online = true AND p.energy > 0 AND p.internet > 0
  LOOP
    -- Obtener multiplicadores de boost (caché por jugador)
    IF v_current_player_id IS DISTINCT FROM v_rig.player_id THEN
      v_boosts := get_active_boost_multipliers(v_rig.player_id);
      v_hashrate_mult := COALESCE((v_boosts->>'hashrate')::NUMERIC, 1.0);
      v_luck_mult := COALESCE((v_boosts->>'luck')::NUMERIC, 1.0);
      v_current_player_id := v_rig.player_id;
      -- Acumular luck multiplier para probabilidad de bloque
      IF v_luck_mult > 1.0 THEN
        v_total_luck_mult := v_total_luck_mult + (v_luck_mult - 1.0);
        v_luck_count := v_luck_count + 1;
      END IF;
    END IF;

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

    -- Aplicar multiplicador de boost de hashrate
    v_effective_hashrate := v_rig.hashrate * v_condition_penalty * v_rep_multiplier * v_temp_penalty * v_hashrate_mult;
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

  -- Probabilidad de minar (aplicar multiplicador de luck promedio si hay boosts activos)
  -- El luck multiplier aumenta la probabilidad global de encontrar un bloque
  IF v_luck_count > 0 THEN
    v_total_luck_mult := v_total_luck_mult / v_luck_count;
  END IF;
  v_block_probability := (v_network_hashrate / v_difficulty) * v_total_luck_mult;
  v_roll := random();

  IF v_roll > v_block_probability THEN
    RETURN QUERY SELECT false, NULL::INT;
    RETURN;
  END IF;

  -- Seleccionar ganador (con mismas penalizaciones y boosts)
  v_random_pick := random() * v_network_hashrate;
  v_hashrate_sum := 0;
  v_current_player_id := NULL;

  FOR v_rig IN
    SELECT pr.id as rig_id, pr.player_id, pr.condition, pr.temperature, r.hashrate, p.reputation_score
    FROM player_rigs pr
    JOIN rigs r ON r.id = pr.rig_id
    JOIN players p ON p.id = pr.player_id
    WHERE pr.is_active = true AND p.is_online = true AND p.energy > 0 AND p.internet > 0
  LOOP
    -- Obtener multiplicador de hashrate del boost (caché por jugador)
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

    -- Aplicar multiplicador de boost de hashrate
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
  v_inactive_marked INT := 0;
  v_rigs_shutdown INT := 0;
BEGIN
  -- Marcar como offline a usuarios inactivos (sin heartbeat por más de 5 minutos)
  -- Y apagar sus rigs automáticamente
  WITH inactive_players AS (
    UPDATE players
    SET is_online = false
    WHERE is_online = true
      AND last_seen < NOW() - INTERVAL '5 minutes'
    RETURNING id
  )
  SELECT COUNT(*) INTO v_inactive_marked FROM inactive_players;

  -- Apagar rigs de jugadores que acaban de ser marcados offline
  IF v_inactive_marked > 0 THEN
    UPDATE player_rigs
    SET is_active = false, temperature = 25, activated_at = NULL
    WHERE player_id IN (
      SELECT id FROM players
      WHERE is_online = false
        AND last_seen < NOW() - INTERVAL '5 minutes'
        AND last_seen > NOW() - INTERVAL '6 minutes'
    ) AND is_active = true;
    GET DIAGNOSTICS v_rigs_shutdown = ROW_COUNT;
  END IF;

  -- Procesar decay de recursos (solo jugadores online)
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
    'playersMarkedOffline', v_inactive_marked,
    'rigsShutdown', v_rigs_shutdown,
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
      SELECT rc.id, rc.cooling_item_id, rc.durability, rc.installed_at,
             ci.name, ci.description, ci.cooling_power, ci.energy_cost, ci.tier
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
  v_currency TEXT;
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

  -- Obtener moneda (default gamecoin para compatibilidad)
  v_currency := COALESCE(v_card.currency, 'gamecoin');

  -- Verificar balance según la moneda
  IF v_currency = 'crypto' THEN
    IF v_player.crypto_balance < v_card.base_price THEN
      RETURN json_build_object('success', false, 'error', 'Crypto insuficiente');
    END IF;
  ELSE
    IF v_player.gamecoin_balance < v_card.base_price THEN
      RETURN json_build_object('success', false, 'error', 'GameCoin insuficiente');
    END IF;
  END IF;

  -- Generar código único
  v_code := generate_card_code();

  -- Descontar según la moneda
  IF v_currency = 'crypto' THEN
    UPDATE players
    SET crypto_balance = crypto_balance - v_card.base_price
    WHERE id = p_player_id;
  ELSE
    UPDATE players
    SET gamecoin_balance = gamecoin_balance - v_card.base_price
    WHERE id = p_player_id;
  END IF;

  -- Registrar transacción
  INSERT INTO transactions (player_id, type, amount, currency, description)
  VALUES (p_player_id, 'card_purchase', -v_card.base_price, v_currency,
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
  v_exchange_rate NUMERIC := 0.5;  -- 1 crypto = 10 GameCoin
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
    'crypto_to_gamecoin', 0.5,  -- 1 crypto = 10 GameCoin
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

-- =====================================================
-- 11. SISTEMA DE RACHA (STREAK)
-- =====================================================

-- Obtener estado de racha del jugador
CREATE OR REPLACE FUNCTION get_streak_status(p_player_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_streak player_streaks%ROWTYPE;
  v_reward streak_rewards%ROWTYPE;
  v_can_claim BOOLEAN := false;
  v_is_expired BOOLEAN := false;
  v_next_day INTEGER;
  v_all_rewards JSON;
BEGIN
  -- Obtener o crear registro de streak
  SELECT * INTO v_streak FROM player_streaks WHERE player_id = p_player_id;

  IF v_streak IS NULL THEN
    -- Crear registro inicial
    INSERT INTO player_streaks (player_id, current_streak, longest_streak)
    VALUES (p_player_id, 0, 0)
    RETURNING * INTO v_streak;
  END IF;

  -- Verificar si la racha expiró (más de 48h sin claim)
  IF v_streak.streak_expires_at IS NOT NULL AND NOW() > v_streak.streak_expires_at THEN
    v_is_expired := true;
    -- Resetear racha
    UPDATE player_streaks
    SET current_streak = 0,
        next_claim_available = NULL,
        streak_expires_at = NULL,
        updated_at = NOW()
    WHERE player_id = p_player_id
    RETURNING * INTO v_streak;
  END IF;

  -- Verificar si puede reclamar (pasaron 20h desde el último claim o nunca ha reclamado)
  IF v_streak.next_claim_available IS NULL OR NOW() >= v_streak.next_claim_available THEN
    v_can_claim := true;
  END IF;

  -- Calcular siguiente día de recompensa
  v_next_day := COALESCE(v_streak.current_streak, 0) + 1;

  -- Obtener recompensa del siguiente día (o la más cercana disponible)
  SELECT * INTO v_reward
  FROM streak_rewards
  WHERE day_number <= v_next_day
  ORDER BY day_number DESC
  LIMIT 1;

  -- Si no hay recompensa específica, usar día 1 como base y escalar
  IF v_reward IS NULL THEN
    v_reward.gamecoin_reward := 10 * v_next_day; -- 10 por día base
    v_reward.crypto_reward := 0;
    v_reward.item_type := NULL;
    v_reward.item_id := NULL;
  END IF;

  -- Obtener todas las recompensas para mostrar calendario
  SELECT json_agg(
    json_build_object(
      'day', day_number,
      'gamecoin', gamecoin_reward,
      'crypto', crypto_reward,
      'itemType', item_type,
      'itemId', item_id,
      'description', description
    ) ORDER BY day_number
  ) INTO v_all_rewards
  FROM streak_rewards;

  RETURN json_build_object(
    'success', true,
    'currentStreak', v_streak.current_streak,
    'longestStreak', v_streak.longest_streak,
    'canClaim', v_can_claim,
    'isExpired', v_is_expired,
    'nextDay', v_next_day,
    'nextReward', json_build_object(
      'gamecoin', COALESCE(v_reward.gamecoin_reward, 10 * v_next_day),
      'crypto', COALESCE(v_reward.crypto_reward, 0),
      'itemType', v_reward.item_type,
      'itemId', v_reward.item_id
    ),
    'lastClaimDate', v_streak.last_claim_date,
    'nextClaimAvailable', v_streak.next_claim_available,
    'streakExpiresAt', v_streak.streak_expires_at,
    'allRewards', v_all_rewards
  );
END;
$$;

-- Reclamar recompensa diaria de racha
CREATE OR REPLACE FUNCTION claim_daily_streak(p_player_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_streak player_streaks%ROWTYPE;
  v_reward streak_rewards%ROWTYPE;
  v_new_streak INTEGER;
  v_gamecoin_reward DECIMAL(10, 2);
  v_crypto_reward DECIMAL(10, 4);
  v_item_type TEXT;
  v_item_id TEXT;
BEGIN
  -- Obtener streak actual
  SELECT * INTO v_streak FROM player_streaks WHERE player_id = p_player_id;

  IF v_streak IS NULL THEN
    -- Crear registro inicial
    INSERT INTO player_streaks (player_id, current_streak, longest_streak)
    VALUES (p_player_id, 0, 0)
    RETURNING * INTO v_streak;
  END IF;

  -- Verificar si la racha expiró
  IF v_streak.streak_expires_at IS NOT NULL AND NOW() > v_streak.streak_expires_at THEN
    -- Resetear racha
    UPDATE player_streaks
    SET current_streak = 0,
        next_claim_available = NULL,
        streak_expires_at = NULL,
        updated_at = NOW()
    WHERE player_id = p_player_id
    RETURNING * INTO v_streak;
  END IF;

  -- Verificar si puede reclamar
  IF v_streak.next_claim_available IS NOT NULL AND NOW() < v_streak.next_claim_available THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Debes esperar para reclamar la siguiente recompensa',
      'nextClaimAvailable', v_streak.next_claim_available
    );
  END IF;

  -- Calcular nuevo streak
  v_new_streak := COALESCE(v_streak.current_streak, 0) + 1;

  -- Obtener recompensa del día
  SELECT * INTO v_reward
  FROM streak_rewards
  WHERE day_number = v_new_streak;

  -- Si no hay recompensa específica, calcular basado en día
  IF v_reward IS NULL THEN
    -- Buscar la recompensa más cercana menor
    SELECT * INTO v_reward
    FROM streak_rewards
    WHERE day_number < v_new_streak
    ORDER BY day_number DESC
    LIMIT 1;

    -- Escalar recompensa base
    v_gamecoin_reward := 10 * v_new_streak;
    v_crypto_reward := 0;
    v_item_type := NULL;
    v_item_id := NULL;
  ELSE
    v_gamecoin_reward := v_reward.gamecoin_reward;
    v_crypto_reward := v_reward.crypto_reward;
    v_item_type := v_reward.item_type;
    v_item_id := v_reward.item_id;
  END IF;

  -- Dar recompensas
  UPDATE players
  SET gamecoin_balance = gamecoin_balance + v_gamecoin_reward,
      crypto_balance = crypto_balance + v_crypto_reward
  WHERE id = p_player_id;

  -- Dar item si corresponde
  IF v_item_type = 'prepaid_card' AND v_item_id IS NOT NULL THEN
    -- Crear tarjeta prepago para el jugador
    INSERT INTO player_cards (player_id, card_id, code)
    VALUES (p_player_id, v_item_id, generate_card_code());
  ELSIF v_item_type = 'cooling' AND v_item_id IS NOT NULL THEN
    -- Agregar cooling al inventario
    INSERT INTO player_inventory (player_id, item_type, item_id, quantity)
    VALUES (p_player_id, 'cooling', v_item_id, 1)
    ON CONFLICT (player_id, item_type, item_id)
    DO UPDATE SET quantity = player_inventory.quantity + 1;
  ELSIF v_item_type = 'rig' AND v_item_id IS NOT NULL THEN
    -- Agregar rig al inventario
    INSERT INTO player_inventory (player_id, item_type, item_id, quantity)
    VALUES (p_player_id, 'rig', v_item_id, 1)
    ON CONFLICT (player_id, item_type, item_id)
    DO UPDATE SET quantity = player_inventory.quantity + 1;
  END IF;

  -- Actualizar streak
  UPDATE player_streaks
  SET current_streak = v_new_streak,
      longest_streak = GREATEST(COALESCE(longest_streak, 0), v_new_streak),
      last_claim_date = CURRENT_DATE,
      next_claim_available = NOW() + INTERVAL '20 hours', -- Puede reclamar en 20h
      streak_expires_at = NOW() + INTERVAL '48 hours',    -- Racha expira en 48h
      updated_at = NOW()
  WHERE player_id = p_player_id;

  -- Registrar claim
  INSERT INTO streak_claims (player_id, day_number, gamecoin_earned, crypto_earned, item_type, item_id)
  VALUES (p_player_id, v_new_streak, v_gamecoin_reward, v_crypto_reward, v_item_type, v_item_id);

  -- Registrar transacción
  INSERT INTO transactions (player_id, type, amount, currency, description)
  VALUES (p_player_id, 'streak_reward', v_gamecoin_reward, 'gamecoin',
          'Recompensa de racha día ' || v_new_streak);

  IF v_crypto_reward > 0 THEN
    INSERT INTO transactions (player_id, type, amount, currency, description)
    VALUES (p_player_id, 'streak_reward', v_crypto_reward, 'crypto',
            'Bonus crypto racha día ' || v_new_streak);
  END IF;

  RETURN json_build_object(
    'success', true,
    'newStreak', v_new_streak,
    'gamecoinEarned', v_gamecoin_reward,
    'cryptoEarned', v_crypto_reward,
    'itemType', v_item_type,
    'itemId', v_item_id,
    'nextClaimAvailable', NOW() + INTERVAL '20 hours',
    'streakExpiresAt', NOW() + INTERVAL '48 hours'
  );
END;
$$;

-- =====================================================
-- 12. SISTEMA DE MISIONES DIARIAS
-- =====================================================

-- Asignar misiones diarias a un jugador
-- Asigna: 1 fácil + 2 medias + 1 difícil + 25% chance de 1 épica
CREATE OR REPLACE FUNCTION assign_daily_missions(p_player_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_today DATE := CURRENT_DATE;
  v_existing_count INTEGER;
  v_easy_mission missions%ROWTYPE;
  v_hard_mission missions%ROWTYPE;
  v_epic_mission missions%ROWTYPE;
  v_mission missions%ROWTYPE;
  v_assigned_count INTEGER := 0;
  v_epic_chance FLOAT := 0.25; -- 25% de probabilidad de misión épica
BEGIN
  -- Verificar si ya tiene misiones asignadas hoy
  SELECT COUNT(*) INTO v_existing_count
  FROM player_missions
  WHERE player_id = p_player_id AND assigned_date = v_today;

  IF v_existing_count >= 4 THEN
    RETURN json_build_object('success', true, 'message', 'Ya tienes misiones asignadas hoy', 'count', v_existing_count);
  END IF;

  -- Eliminar misiones anteriores no completadas (limpieza)
  DELETE FROM player_missions
  WHERE player_id = p_player_id
    AND assigned_date < v_today
    AND is_claimed = false;

  -- Seleccionar 1 misión fácil aleatoria
  SELECT * INTO v_easy_mission
  FROM missions
  WHERE difficulty = 'easy'
  ORDER BY RANDOM()
  LIMIT 1;

  IF v_easy_mission.id IS NOT NULL THEN
    INSERT INTO player_missions (player_id, mission_id, assigned_date)
    VALUES (p_player_id, v_easy_mission.id, v_today)
    ON CONFLICT (player_id, mission_id, assigned_date) DO NOTHING;
    v_assigned_count := v_assigned_count + 1;
  END IF;

  -- Seleccionar 2 misiones medias aleatorias
  FOR v_mission IN
    SELECT * FROM missions
    WHERE difficulty = 'medium'
    ORDER BY RANDOM()
    LIMIT 2
  LOOP
    INSERT INTO player_missions (player_id, mission_id, assigned_date)
    VALUES (p_player_id, v_mission.id, v_today)
    ON CONFLICT (player_id, mission_id, assigned_date) DO NOTHING;
    v_assigned_count := v_assigned_count + 1;
  END LOOP;

  -- Seleccionar 1 misión difícil aleatoria
  SELECT * INTO v_hard_mission
  FROM missions
  WHERE difficulty = 'hard'
  ORDER BY RANDOM()
  LIMIT 1;

  IF v_hard_mission.id IS NOT NULL THEN
    INSERT INTO player_missions (player_id, mission_id, assigned_date)
    VALUES (p_player_id, v_hard_mission.id, v_today)
    ON CONFLICT (player_id, mission_id, assigned_date) DO NOTHING;
    v_assigned_count := v_assigned_count + 1;
  END IF;

  -- 25% de probabilidad de obtener una misión ÉPICA como bonus
  IF RANDOM() < v_epic_chance THEN
    SELECT * INTO v_epic_mission
    FROM missions
    WHERE difficulty = 'epic'
    ORDER BY RANDOM()
    LIMIT 1;

    IF v_epic_mission.id IS NOT NULL THEN
      INSERT INTO player_missions (player_id, mission_id, assigned_date)
      VALUES (p_player_id, v_epic_mission.id, v_today)
      ON CONFLICT (player_id, mission_id, assigned_date) DO NOTHING;
      v_assigned_count := v_assigned_count + 1;
    END IF;
  END IF;

  RETURN json_build_object('success', true, 'assigned', v_assigned_count);
END;
$$;

-- Obtener misiones diarias del jugador
CREATE OR REPLACE FUNCTION get_daily_missions(p_player_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_today DATE := CURRENT_DATE;
  v_missions JSON;
  v_online_minutes INTEGER := 0;
BEGIN
  -- Primero asegurarse de que tenga misiones asignadas
  PERFORM assign_daily_missions(p_player_id);

  -- Obtener minutos online de hoy
  SELECT COALESCE(minutes_online, 0) INTO v_online_minutes
  FROM player_online_tracking
  WHERE player_id = p_player_id AND tracking_date = v_today;

  -- Obtener misiones con detalles
  SELECT json_agg(
    json_build_object(
      'id', pm.id,
      'missionId', m.id,
      'name', m.name,
      'description', m.description,
      'missionType', m.mission_type,
      'targetValue', m.target_value,
      'progress', pm.progress,
      'isCompleted', pm.is_completed,
      'isClaimed', pm.is_claimed,
      'rewardType', m.reward_type,
      'rewardAmount', m.reward_amount,
      'difficulty', m.difficulty,
      'icon', m.icon,
      'progressPercent', LEAST(100, ROUND((pm.progress / m.target_value) * 100))
    ) ORDER BY
      CASE m.difficulty WHEN 'easy' THEN 1 WHEN 'medium' THEN 2 WHEN 'hard' THEN 3 END,
      m.name
  ) INTO v_missions
  FROM player_missions pm
  JOIN missions m ON m.id = pm.mission_id
  WHERE pm.player_id = p_player_id AND pm.assigned_date = v_today;

  RETURN json_build_object(
    'success', true,
    'missions', COALESCE(v_missions, '[]'::json),
    'date', v_today,
    'onlineMinutes', v_online_minutes
  );
END;
$$;

-- Actualizar progreso de misión
CREATE OR REPLACE FUNCTION update_mission_progress(
  p_player_id UUID,
  p_mission_type TEXT,
  p_increment NUMERIC
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_today DATE := CURRENT_DATE;
  v_mission RECORD;
  v_updated_count INTEGER := 0;
BEGIN
  -- Actualizar todas las misiones del tipo especificado
  FOR v_mission IN
    SELECT pm.id, pm.progress, m.target_value
    FROM player_missions pm
    JOIN missions m ON m.id = pm.mission_id
    WHERE pm.player_id = p_player_id
      AND pm.assigned_date = v_today
      AND pm.is_completed = false
      AND m.mission_type = p_mission_type
  LOOP
    -- Actualizar progreso
    UPDATE player_missions
    SET progress = LEAST(v_mission.target_value, progress + p_increment),
        is_completed = (LEAST(v_mission.target_value, progress + p_increment) >= v_mission.target_value),
        completed_at = CASE
          WHEN LEAST(v_mission.target_value, progress + p_increment) >= v_mission.target_value THEN NOW()
          ELSE completed_at
        END
    WHERE id = v_mission.id;

    v_updated_count := v_updated_count + 1;
  END LOOP;

  RETURN json_build_object('success', true, 'updated', v_updated_count);
END;
$$;

-- Reclamar recompensa de misión
CREATE OR REPLACE FUNCTION claim_mission_reward(p_player_id UUID, p_mission_uuid UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_pm player_missions%ROWTYPE;
  v_mission missions%ROWTYPE;
BEGIN
  -- Obtener misión del jugador
  SELECT * INTO v_pm
  FROM player_missions
  WHERE id = p_mission_uuid AND player_id = p_player_id;

  IF v_pm IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Misión no encontrada');
  END IF;

  IF NOT v_pm.is_completed THEN
    RETURN json_build_object('success', false, 'error', 'La misión no está completada');
  END IF;

  IF v_pm.is_claimed THEN
    RETURN json_build_object('success', false, 'error', 'Ya reclamaste esta recompensa');
  END IF;

  -- Obtener detalles de la misión
  SELECT * INTO v_mission FROM missions WHERE id = v_pm.mission_id;

  -- Dar recompensa
  IF v_mission.reward_type = 'gamecoin' THEN
    UPDATE players
    SET gamecoin_balance = gamecoin_balance + v_mission.reward_amount
    WHERE id = p_player_id;
  ELSIF v_mission.reward_type = 'crypto' THEN
    UPDATE players
    SET crypto_balance = crypto_balance + v_mission.reward_amount
    WHERE id = p_player_id;
  ELSIF v_mission.reward_type = 'energy' THEN
    UPDATE players
    SET energy = LEAST(max_energy, energy + v_mission.reward_amount)
    WHERE id = p_player_id;
  ELSIF v_mission.reward_type = 'internet' THEN
    UPDATE players
    SET internet = LEAST(max_internet, internet + v_mission.reward_amount)
    WHERE id = p_player_id;
  END IF;

  -- Marcar como reclamada
  UPDATE player_missions
  SET is_claimed = true, claimed_at = NOW()
  WHERE id = p_mission_uuid;

  -- Registrar transacción
  INSERT INTO transactions (player_id, type, amount, currency, description)
  VALUES (p_player_id, 'mission_reward', v_mission.reward_amount, v_mission.reward_type,
          'Recompensa de misión: ' || v_mission.name);

  RETURN json_build_object(
    'success', true,
    'rewardType', v_mission.reward_type,
    'rewardAmount', v_mission.reward_amount,
    'missionName', v_mission.name
  );
END;
$$;

-- Registrar heartbeat de tiempo online
CREATE OR REPLACE FUNCTION record_online_heartbeat(p_player_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_today DATE := CURRENT_DATE;
  v_tracking player_online_tracking%ROWTYPE;
  v_minutes_since_last INTEGER;
  v_new_minutes INTEGER;
BEGIN
  -- Obtener o crear registro de tracking
  SELECT * INTO v_tracking
  FROM player_online_tracking
  WHERE player_id = p_player_id AND tracking_date = v_today;

  IF v_tracking IS NULL THEN
    -- Crear nuevo registro
    INSERT INTO player_online_tracking (player_id, tracking_date, minutes_online, last_heartbeat)
    VALUES (p_player_id, v_today, 1, NOW())
    RETURNING * INTO v_tracking;

    -- Actualizar progreso de misiones de tiempo online
    PERFORM update_mission_progress(p_player_id, 'online_time', 1);

    RETURN json_build_object('success', true, 'minutesOnline', 1);
  END IF;

  -- Calcular minutos desde el último heartbeat (máximo 5 para evitar trampas)
  v_minutes_since_last := LEAST(5, EXTRACT(EPOCH FROM (NOW() - v_tracking.last_heartbeat)) / 60);

  -- Actualizar is_online y last_seen en players (siempre con cada heartbeat)
  UPDATE players
  SET is_online = true,
      last_seen = NOW()
  WHERE id = p_player_id;

  -- Solo contar si pasó al menos 1 minuto
  IF v_minutes_since_last >= 1 THEN
    v_new_minutes := v_tracking.minutes_online + v_minutes_since_last;

    UPDATE player_online_tracking
    SET minutes_online = v_new_minutes,
        last_heartbeat = NOW()
    WHERE id = v_tracking.id;

    -- Actualizar progreso de misiones de tiempo online
    PERFORM update_mission_progress(p_player_id, 'online_time', v_minutes_since_last);

    RETURN json_build_object('success', true, 'minutesOnline', v_new_minutes, 'added', v_minutes_since_last);
  END IF;

  RETURN json_build_object('success', true, 'minutesOnline', v_tracking.minutes_online, 'added', 0);
END;
$$;

-- =====================================================
-- BOOST ITEMS SYSTEM
-- Temporary power-ups for mining performance
-- =====================================================

-- Catálogo de boost items disponibles
CREATE TABLE IF NOT EXISTS boost_items (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  boost_type TEXT NOT NULL CHECK (boost_type IN (
    'hashrate',           -- +X% hashrate
    'energy_saver',       -- -X% energy consumption
    'bandwidth_optimizer',-- -X% internet consumption
    'lucky_charm',        -- +X% block probability
    'overclock',          -- +X% hashrate, +Y% energy consumption
    'coolant_injection',  -- -X% temperature gain
    'durability_shield'   -- -X% condition deterioration
  )),
  effect_value NUMERIC NOT NULL,          -- Primary effect percentage
  secondary_value NUMERIC DEFAULT 0,      -- Secondary effect for overclock
  duration_minutes INTEGER NOT NULL,       -- Duration in minutes
  base_price DECIMAL(10, 2) NOT NULL CHECK (base_price >= 0),
  currency TEXT NOT NULL DEFAULT 'gamecoin' CHECK (currency IN ('gamecoin', 'crypto')),
  tier TEXT NOT NULL CHECK (tier IN ('basic', 'standard', 'advanced', 'elite')),
  is_stackable BOOLEAN DEFAULT false,
  max_stack INTEGER DEFAULT 1,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Boosts en inventario del jugador
CREATE TABLE IF NOT EXISTS player_boosts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  boost_id TEXT NOT NULL REFERENCES boost_items(id),
  quantity INTEGER DEFAULT 1,
  purchased_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(player_id, boost_id)
);

CREATE INDEX IF NOT EXISTS idx_player_boosts_player ON player_boosts(player_id);

-- Boosts activos
CREATE TABLE IF NOT EXISTS active_boosts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  boost_id TEXT NOT NULL REFERENCES boost_items(id),
  activated_at TIMESTAMPTZ DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL,
  stack_count INTEGER DEFAULT 1,
  UNIQUE(player_id, boost_id)
);

CREATE INDEX IF NOT EXISTS idx_active_boosts_player ON active_boosts(player_id);
CREATE INDEX IF NOT EXISTS idx_active_boosts_expires ON active_boosts(expires_at);

-- Seed data para boost items (all crypto, prices 1000+)
-- Durations: basic=5min, standard=10min, elite=20min (per-rig boosts)
-- Uses ON CONFLICT DO UPDATE to safely update existing items without foreign key issues

INSERT INTO boost_items (id, name, description, boost_type, effect_value, secondary_value, duration_minutes, base_price, currency, tier, is_stackable, max_stack) VALUES
-- Hashrate Boosters
('hashrate_small', 'Minor Hash Boost', '+10% hashrate for 5 minutes', 'hashrate', 10, 0, 5, 1200, 'crypto', 'basic', false, 1),
('hashrate_medium', 'Hash Boost', '+25% hashrate for 10 minutes', 'hashrate', 25, 0, 10, 3000, 'crypto', 'standard', false, 1),
('hashrate_large', 'Mega Hash Boost', '+50% hashrate for 20 minutes', 'hashrate', 50, 0, 20, 6500, 'crypto', 'elite', false, 1),

-- Energy Savers
('energy_saver_small', 'Power Saver', '-15% energy consumption for 5 minutes', 'energy_saver', 15, 0, 5, 1000, 'crypto', 'basic', false, 1),
('energy_saver_medium', 'Eco Mode', '-25% energy consumption for 10 minutes', 'energy_saver', 25, 0, 10, 2500, 'crypto', 'standard', false, 1),
('energy_saver_large', 'Green Mining', '-40% energy consumption for 20 minutes', 'energy_saver', 40, 0, 20, 5500, 'crypto', 'elite', false, 1),

-- Bandwidth Optimizers
('bandwidth_small', 'Data Optimizer', '-15% internet consumption for 5 minutes', 'bandwidth_optimizer', 15, 0, 5, 1000, 'crypto', 'basic', false, 1),
('bandwidth_medium', 'Network Boost', '-25% internet consumption for 10 minutes', 'bandwidth_optimizer', 25, 0, 10, 2500, 'crypto', 'standard', false, 1),
('bandwidth_large', 'Fiber Mode', '-40% internet consumption for 20 minutes', 'bandwidth_optimizer', 40, 0, 20, 5500, 'crypto', 'elite', false, 1),

-- Lucky Charms (more expensive - affects block probability)
('lucky_small', 'Lucky Coin', '+5% block probability for 5 minutes', 'lucky_charm', 5, 0, 5, 2000, 'crypto', 'basic', false, 1),
('lucky_medium', 'Fortune Token', '+10% block probability for 10 minutes', 'lucky_charm', 10, 0, 10, 5000, 'crypto', 'standard', false, 1),
('lucky_large', 'Jackpot Charm', '+20% block probability for 20 minutes', 'lucky_charm', 20, 0, 20, 12000, 'crypto', 'elite', false, 1),

-- Overclock Mode (hashrate boost + energy penalty)
('overclock_small', 'Overclock Lite', '+25% hashrate, +15% energy for 5 minutes', 'overclock', 25, 15, 5, 1500, 'crypto', 'basic', false, 1),
('overclock_medium', 'Overclock Pro', '+40% hashrate, +25% energy for 10 minutes', 'overclock', 40, 25, 10, 3500, 'crypto', 'standard', false, 1),
('overclock_large', 'Overclock Max', '+60% hashrate, +35% energy for 20 minutes', 'overclock', 60, 35, 20, 7500, 'crypto', 'elite', false, 1),

-- Coolant Injection
('coolant_small', 'Cooling Gel', '-20% temperature gain for 5 minutes', 'coolant_injection', 20, 0, 5, 1200, 'crypto', 'basic', false, 1),
('coolant_medium', 'Cryo Fluid', '-35% temperature gain for 10 minutes', 'coolant_injection', 35, 0, 10, 3000, 'crypto', 'standard', false, 1),
('coolant_large', 'Liquid Nitrogen', '-50% temperature gain for 20 minutes', 'coolant_injection', 50, 0, 20, 6500, 'crypto', 'elite', false, 1),

-- Durability Shield
('durability_small', 'Wear Guard', '-20% condition deterioration for 5 minutes', 'durability_shield', 20, 0, 5, 1200, 'crypto', 'basic', false, 1),
('durability_medium', 'Shield Coat', '-35% condition deterioration for 10 minutes', 'durability_shield', 35, 0, 10, 3000, 'crypto', 'standard', false, 1),
('durability_large', 'Diamond Shell', '-50% condition deterioration for 20 minutes', 'durability_shield', 50, 0, 20, 6500, 'crypto', 'elite', false, 1)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  boost_type = EXCLUDED.boost_type,
  effect_value = EXCLUDED.effect_value,
  secondary_value = EXCLUDED.secondary_value,
  duration_minutes = EXCLUDED.duration_minutes,
  base_price = EXCLUDED.base_price,
  currency = EXCLUDED.currency,
  tier = EXCLUDED.tier;

-- Obtener todos los boost items disponibles
DROP FUNCTION IF EXISTS get_boost_items() CASCADE;
CREATE OR REPLACE FUNCTION get_boost_items()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN (
    SELECT COALESCE(json_agg(row_to_json(t) ORDER BY t.boost_type, t.base_price), '[]'::JSON)
    FROM (
      SELECT id, name, description, boost_type, effect_value, secondary_value,
             duration_minutes, base_price, currency, tier, is_stackable, max_stack
      FROM boost_items
      ORDER BY boost_type, base_price ASC
    ) t
  );
END;
$$;

-- Obtener boosts del jugador (inventario y activos)
DROP FUNCTION IF EXISTS get_player_boosts(UUID) CASCADE;
CREATE OR REPLACE FUNCTION get_player_boosts(p_player_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Limpiar boosts expirados
  DELETE FROM active_boosts WHERE expires_at <= NOW();

  RETURN json_build_object(
    'inventory', (
      SELECT COALESCE(json_agg(row_to_json(t)), '[]'::JSON)
      FROM (
        SELECT pb.id, pb.quantity, pb.purchased_at,
               bi.id as boost_id, bi.name, bi.description, bi.boost_type,
               bi.effect_value, bi.secondary_value, bi.duration_minutes, bi.tier
        FROM player_boosts pb
        JOIN boost_items bi ON bi.id = pb.boost_id
        WHERE pb.player_id = p_player_id AND pb.quantity > 0
        ORDER BY bi.boost_type, bi.tier
      ) t
    ),
    'active', (
      SELECT COALESCE(json_agg(row_to_json(t)), '[]'::JSON)
      FROM (
        SELECT ab.id, ab.activated_at, ab.expires_at, ab.stack_count,
               bi.id as boost_id, bi.name, bi.description, bi.boost_type,
               bi.effect_value, bi.secondary_value, bi.duration_minutes, bi.tier,
               EXTRACT(EPOCH FROM (ab.expires_at - NOW())) as seconds_remaining
        FROM active_boosts ab
        JOIN boost_items bi ON bi.id = ab.boost_id
        WHERE ab.player_id = p_player_id AND ab.expires_at > NOW()
        ORDER BY ab.expires_at ASC
      ) t
    )
  );
END;
$$;

-- Comprar boost (agregar al inventario)
DROP FUNCTION IF EXISTS buy_boost(UUID, TEXT) CASCADE;
CREATE OR REPLACE FUNCTION buy_boost(p_player_id UUID, p_boost_id TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player players%ROWTYPE;
  v_boost boost_items%ROWTYPE;
BEGIN
  -- Verificar jugador
  SELECT * INTO v_player FROM players WHERE id = p_player_id;
  IF v_player IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Player not found');
  END IF;

  -- Verificar boost
  SELECT * INTO v_boost FROM boost_items WHERE id = p_boost_id;
  IF v_boost IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Boost not found');
  END IF;

  -- Verificar balance según moneda
  IF v_boost.currency = 'crypto' THEN
    IF v_player.crypto_balance < v_boost.base_price THEN
      RETURN json_build_object('success', false, 'error', 'Insufficient Crypto');
    END IF;

    UPDATE players
    SET crypto_balance = crypto_balance - v_boost.base_price
    WHERE id = p_player_id;
  ELSE
    IF v_player.gamecoin_balance < v_boost.base_price THEN
      RETURN json_build_object('success', false, 'error', 'Insufficient GameCoin');
    END IF;

    UPDATE players
    SET gamecoin_balance = gamecoin_balance - v_boost.base_price
    WHERE id = p_player_id;
  END IF;

  -- Registrar transacción
  INSERT INTO transactions (player_id, type, amount, currency, description)
  VALUES (p_player_id, 'boost_purchase', -v_boost.base_price, v_boost.currency,
          'Boost purchase: ' || v_boost.name);

  -- Agregar al inventario
  INSERT INTO player_boosts (player_id, boost_id, quantity)
  VALUES (p_player_id, p_boost_id, 1)
  ON CONFLICT (player_id, boost_id)
  DO UPDATE SET quantity = player_boosts.quantity + 1;

  RETURN json_build_object(
    'success', true,
    'boost', row_to_json(v_boost),
    'message', 'Boost added to inventory'
  );
END;
$$;

-- Activar boost (usar del inventario)
DROP FUNCTION IF EXISTS activate_boost(UUID, TEXT) CASCADE;
CREATE OR REPLACE FUNCTION activate_boost(p_player_id UUID, p_boost_id TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_inventory player_boosts%ROWTYPE;
  v_boost boost_items%ROWTYPE;
  v_existing active_boosts%ROWTYPE;
  v_expires_at TIMESTAMPTZ;
BEGIN
  -- Verificar inventario
  SELECT * INTO v_inventory
  FROM player_boosts
  WHERE player_id = p_player_id AND boost_id = p_boost_id;

  IF v_inventory IS NULL OR v_inventory.quantity <= 0 THEN
    RETURN json_build_object('success', false, 'error', 'Boost not in inventory');
  END IF;

  -- Obtener detalles del boost
  SELECT * INTO v_boost FROM boost_items WHERE id = p_boost_id;

  -- Verificar si ya está activo
  SELECT * INTO v_existing
  FROM active_boosts
  WHERE player_id = p_player_id AND boost_id = p_boost_id AND expires_at > NOW();

  IF v_existing IS NOT NULL THEN
    IF NOT v_boost.is_stackable OR v_existing.stack_count >= v_boost.max_stack THEN
      RETURN json_build_object('success', false, 'error', 'Boost already active');
    END IF;

    -- Stackear: extender duración
    UPDATE active_boosts
    SET expires_at = expires_at + (v_boost.duration_minutes || ' minutes')::INTERVAL,
        stack_count = stack_count + 1
    WHERE id = v_existing.id;

    v_expires_at := v_existing.expires_at + (v_boost.duration_minutes || ' minutes')::INTERVAL;
  ELSE
    -- Calcular expiración
    v_expires_at := NOW() + (v_boost.duration_minutes || ' minutes')::INTERVAL;

    -- Crear nuevo boost activo
    INSERT INTO active_boosts (player_id, boost_id, activated_at, expires_at, stack_count)
    VALUES (p_player_id, p_boost_id, NOW(), v_expires_at, 1);
  END IF;

  -- Remover del inventario
  IF v_inventory.quantity > 1 THEN
    UPDATE player_boosts
    SET quantity = quantity - 1
    WHERE id = v_inventory.id;
  ELSE
    DELETE FROM player_boosts WHERE id = v_inventory.id;
  END IF;

  RETURN json_build_object(
    'success', true,
    'boost', row_to_json(v_boost),
    'expires_at', v_expires_at,
    'message', 'Boost activated!'
  );
END;
$$;

-- Obtener multiplicadores de boosts activos (para game tick)
DROP FUNCTION IF EXISTS get_active_boost_multipliers(UUID) CASCADE;
CREATE OR REPLACE FUNCTION get_active_boost_multipliers(p_player_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_hashrate_mult NUMERIC := 1.0;
  v_energy_mult NUMERIC := 1.0;
  v_internet_mult NUMERIC := 1.0;
  v_luck_mult NUMERIC := 1.0;
  v_temp_mult NUMERIC := 1.0;
  v_durability_mult NUMERIC := 1.0;
  v_boost RECORD;
BEGIN
  -- Limpiar boosts expirados
  DELETE FROM active_boosts WHERE expires_at <= NOW();

  -- Calcular multiplicadores de todos los boosts activos
  FOR v_boost IN
    SELECT bi.boost_type, bi.effect_value, bi.secondary_value, ab.stack_count
    FROM active_boosts ab
    JOIN boost_items bi ON bi.id = ab.boost_id
    WHERE ab.player_id = p_player_id AND ab.expires_at > NOW()
  LOOP
    CASE v_boost.boost_type
      WHEN 'hashrate' THEN
        v_hashrate_mult := v_hashrate_mult + (v_boost.effect_value / 100.0) * v_boost.stack_count;
      WHEN 'energy_saver' THEN
        v_energy_mult := v_energy_mult - (v_boost.effect_value / 100.0) * v_boost.stack_count;
      WHEN 'bandwidth_optimizer' THEN
        v_internet_mult := v_internet_mult - (v_boost.effect_value / 100.0) * v_boost.stack_count;
      WHEN 'lucky_charm' THEN
        v_luck_mult := v_luck_mult + (v_boost.effect_value / 100.0) * v_boost.stack_count;
      WHEN 'overclock' THEN
        v_hashrate_mult := v_hashrate_mult + (v_boost.effect_value / 100.0) * v_boost.stack_count;
        v_energy_mult := v_energy_mult + (v_boost.secondary_value / 100.0) * v_boost.stack_count;
      WHEN 'coolant_injection' THEN
        v_temp_mult := v_temp_mult - (v_boost.effect_value / 100.0) * v_boost.stack_count;
      WHEN 'durability_shield' THEN
        v_durability_mult := v_durability_mult - (v_boost.effect_value / 100.0) * v_boost.stack_count;
    END CASE;
  END LOOP;

  -- Asegurar que los multiplicadores no bajen demasiado
  v_energy_mult := GREATEST(0.1, v_energy_mult);
  v_internet_mult := GREATEST(0.1, v_internet_mult);
  v_temp_mult := GREATEST(0.1, v_temp_mult);
  v_durability_mult := GREATEST(0.1, v_durability_mult);

  RETURN json_build_object(
    'hashrate', v_hashrate_mult,
    'energy', v_energy_mult,
    'internet', v_internet_mult,
    'luck', v_luck_mult,
    'temperature', v_temp_mult,
    'durability', v_durability_mult
  );
END;
$$;

-- =====================================================
-- RIG-SPECIFIC BOOST FUNCTIONS
-- =====================================================

-- Instalar boost en un rig específico (similar a install_cooling_to_rig)
DROP FUNCTION IF EXISTS install_boost_to_rig(UUID, UUID, TEXT) CASCADE;
CREATE OR REPLACE FUNCTION install_boost_to_rig(p_player_id UUID, p_rig_id UUID, p_boost_id TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_inventory player_boosts%ROWTYPE;
  v_boost boost_items%ROWTYPE;
  v_rig player_rigs%ROWTYPE;
  v_existing rig_boosts%ROWTYPE;
  v_remaining_seconds INTEGER;
BEGIN
  -- Verificar que el rig pertenece al jugador
  SELECT * INTO v_rig
  FROM player_rigs
  WHERE id = p_rig_id AND player_id = p_player_id;

  IF v_rig IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Rig no encontrado');
  END IF;

  -- Verificar que el rig NO está activo (debe estar apagado para aplicar boost)
  IF v_rig.is_active THEN
    RETURN json_build_object('success', false, 'error', 'Detén el rig antes de aplicar el boost');
  END IF;

  -- Verificar inventario
  SELECT * INTO v_inventory
  FROM player_boosts
  WHERE player_id = p_player_id AND boost_id = p_boost_id;

  IF v_inventory IS NULL OR v_inventory.quantity <= 0 THEN
    RETURN json_build_object('success', false, 'error', 'No tienes este boost en tu inventario');
  END IF;

  -- Obtener detalles del boost
  SELECT * INTO v_boost FROM boost_items WHERE id = p_boost_id;

  IF v_boost IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Boost no encontrado');
  END IF;

  -- Verificar si ya está instalado en este rig
  SELECT * INTO v_existing
  FROM rig_boosts
  WHERE player_rig_id = p_rig_id AND boost_item_id = p_boost_id AND remaining_seconds > 0;

  IF v_existing IS NOT NULL THEN
    IF NOT v_boost.is_stackable OR v_existing.stack_count >= v_boost.max_stack THEN
      RETURN json_build_object('success', false, 'error', 'Este boost ya está activo en este rig');
    END IF;

    -- Stackear: agregar tiempo
    UPDATE rig_boosts
    SET remaining_seconds = remaining_seconds + (v_boost.duration_minutes * 60),
        stack_count = stack_count + 1
    WHERE id = v_existing.id;

    v_remaining_seconds := v_existing.remaining_seconds + (v_boost.duration_minutes * 60);
  ELSE
    -- Calcular segundos totales
    v_remaining_seconds := v_boost.duration_minutes * 60;

    -- Crear nuevo boost en el rig
    INSERT INTO rig_boosts (player_rig_id, boost_item_id, remaining_seconds, stack_count)
    VALUES (p_rig_id, p_boost_id, v_remaining_seconds, 1);
  END IF;

  -- Remover del inventario
  IF v_inventory.quantity > 1 THEN
    UPDATE player_boosts
    SET quantity = quantity - 1
    WHERE id = v_inventory.id;
  ELSE
    DELETE FROM player_boosts WHERE id = v_inventory.id;
  END IF;

  RETURN json_build_object(
    'success', true,
    'boost', row_to_json(v_boost),
    'remaining_seconds', v_remaining_seconds,
    'message', 'Boost aplicado al rig'
  );
END;
$$;

-- Obtener boosts instalados en un rig específico
DROP FUNCTION IF EXISTS get_rig_boosts(UUID) CASCADE;
CREATE OR REPLACE FUNCTION get_rig_boosts(p_rig_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Limpiar boosts expirados (remaining_seconds <= 0)
  DELETE FROM rig_boosts WHERE player_rig_id = p_rig_id AND remaining_seconds <= 0;

  RETURN (
    SELECT COALESCE(json_agg(row_to_json(t) ORDER BY t.activated_at), '[]'::JSON)
    FROM (
      SELECT rb.id, rb.boost_item_id, rb.remaining_seconds, rb.stack_count, rb.activated_at,
             bi.name, bi.description, bi.boost_type, bi.effect_value, bi.secondary_value, bi.tier
      FROM rig_boosts rb
      JOIN boost_items bi ON bi.id = rb.boost_item_id
      WHERE rb.player_rig_id = p_rig_id AND rb.remaining_seconds > 0
    ) t
  );
END;
$$;

-- Obtener multiplicadores de boosts de un rig específico (para game tick)
DROP FUNCTION IF EXISTS get_rig_boost_multipliers(UUID) CASCADE;
CREATE OR REPLACE FUNCTION get_rig_boost_multipliers(p_rig_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_hashrate_mult NUMERIC := 1.0;
  v_energy_mult NUMERIC := 1.0;
  v_internet_mult NUMERIC := 1.0;
  v_luck_mult NUMERIC := 1.0;
  v_temp_mult NUMERIC := 1.0;
  v_durability_mult NUMERIC := 1.0;
  v_boost RECORD;
BEGIN
  -- Calcular multiplicadores de todos los boosts activos en este rig
  FOR v_boost IN
    SELECT bi.boost_type, bi.effect_value, bi.secondary_value, rb.stack_count
    FROM rig_boosts rb
    JOIN boost_items bi ON bi.id = rb.boost_item_id
    WHERE rb.player_rig_id = p_rig_id AND rb.remaining_seconds > 0
  LOOP
    CASE v_boost.boost_type
      WHEN 'hashrate' THEN
        v_hashrate_mult := v_hashrate_mult + (v_boost.effect_value / 100.0) * v_boost.stack_count;
      WHEN 'energy_saver' THEN
        v_energy_mult := v_energy_mult - (v_boost.effect_value / 100.0) * v_boost.stack_count;
      WHEN 'bandwidth_optimizer' THEN
        v_internet_mult := v_internet_mult - (v_boost.effect_value / 100.0) * v_boost.stack_count;
      WHEN 'lucky_charm' THEN
        v_luck_mult := v_luck_mult + (v_boost.effect_value / 100.0) * v_boost.stack_count;
      WHEN 'overclock' THEN
        v_hashrate_mult := v_hashrate_mult + (v_boost.effect_value / 100.0) * v_boost.stack_count;
        v_energy_mult := v_energy_mult + (v_boost.secondary_value / 100.0) * v_boost.stack_count;
      WHEN 'coolant_injection' THEN
        v_temp_mult := v_temp_mult - (v_boost.effect_value / 100.0) * v_boost.stack_count;
      WHEN 'durability_shield' THEN
        v_durability_mult := v_durability_mult - (v_boost.effect_value / 100.0) * v_boost.stack_count;
    END CASE;
  END LOOP;

  -- Asegurar que los multiplicadores no bajen demasiado
  v_energy_mult := GREATEST(0.1, v_energy_mult);
  v_internet_mult := GREATEST(0.1, v_internet_mult);
  v_temp_mult := GREATEST(0.1, v_temp_mult);
  v_durability_mult := GREATEST(0.1, v_durability_mult);

  RETURN json_build_object(
    'hashrate', v_hashrate_mult,
    'energy', v_energy_mult,
    'internet', v_internet_mult,
    'luck', v_luck_mult,
    'temperature', v_temp_mult,
    'durability', v_durability_mult
  );
END;
$$;

-- =====================================================
-- PROFILE FUNCTIONS
-- =====================================================

-- Actualizar wallet RON
DROP FUNCTION IF EXISTS update_ron_wallet(UUID, TEXT) CASCADE;
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

  -- Clean and validate wallet address
  v_clean_wallet := TRIM(p_wallet_address);

  -- Allow null/empty to clear wallet
  IF v_clean_wallet IS NULL OR v_clean_wallet = '' THEN
    UPDATE players SET ron_wallet = NULL, updated_at = NOW() WHERE id = p_player_id;
    RETURN json_build_object('success', true, 'wallet', NULL);
  END IF;

  -- Basic validation: starts with 0x and is 42 chars (Ethereum/RON format)
  IF NOT (v_clean_wallet ~* '^0x[a-fA-F0-9]{40}$') THEN
    RETURN json_build_object('success', false, 'error', 'Formato de wallet invalido. Debe ser una direccion valida (0x...)');
  END IF;

  -- Update wallet
  UPDATE players
  SET ron_wallet = v_clean_wallet, updated_at = NOW()
  WHERE id = p_player_id;

  RETURN json_build_object('success', true, 'wallet', v_clean_wallet);
END;
$$;

-- Reiniciar cuenta (soft reset)
DROP FUNCTION IF EXISTS reset_player_account(UUID) CASCADE;
CREATE OR REPLACE FUNCTION reset_player_account(p_player_id UUID)
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

  -- Delete all player cooling and inventory
  DELETE FROM player_cooling WHERE player_id = p_player_id;
  DELETE FROM player_inventory WHERE player_id = p_player_id;

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

  -- Delete market orders
  DELETE FROM market_orders WHERE player_id = p_player_id;

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

-- =====================================================
-- FUNCIONES DE PAQUETES DE CRYPTO (RON)
-- =====================================================

-- Obtener paquetes de crypto disponibles
CREATE OR REPLACE FUNCTION get_crypto_packages()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN (
    SELECT COALESCE(json_agg(row_to_json(t) ORDER BY t.ron_price ASC), '[]'::JSON)
    FROM (
      SELECT
        id,
        name,
        description,
        crypto_amount,
        ron_price,
        bonus_percent,
        tier,
        is_featured,
        -- Calcular total con bonus
        ROUND(crypto_amount * (1 + bonus_percent::NUMERIC / 100), 2) as total_crypto
      FROM crypto_packages
      WHERE is_active = true
      ORDER BY ron_price ASC
    ) t
  );
END;
$$;

-- Comprar paquete de crypto con RON
-- tx_hash es el hash de la transacción en Ronin para verificación
CREATE OR REPLACE FUNCTION buy_crypto_package(
  p_player_id UUID,
  p_package_id TEXT,
  p_tx_hash TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_package crypto_packages%ROWTYPE;
  v_total_crypto NUMERIC;
  v_purchase_id UUID;
BEGIN
  -- Obtener el paquete
  SELECT * INTO v_package
  FROM crypto_packages
  WHERE id = p_package_id AND is_active = true;

  IF v_package IS NULL THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Paquete no encontrado o no disponible'
    );
  END IF;

  -- Calcular crypto total (con bonus)
  v_total_crypto := v_package.crypto_amount * (1 + v_package.bonus_percent::NUMERIC / 100);

  -- Registrar la compra
  INSERT INTO crypto_purchases (
    player_id,
    package_id,
    crypto_amount,
    ron_paid,
    tx_hash,
    status,
    completed_at
  ) VALUES (
    p_player_id,
    p_package_id,
    v_total_crypto,
    v_package.ron_price,
    p_tx_hash,
    'completed',
    NOW()
  )
  RETURNING id INTO v_purchase_id;

  -- Dar el crypto al jugador
  UPDATE players
  SET crypto_balance = crypto_balance + v_total_crypto,
      updated_at = NOW()
  WHERE id = p_player_id;

  -- Registrar transacción
  INSERT INTO transactions (player_id, type, amount, currency, description)
  VALUES (
    p_player_id,
    'crypto_purchase',
    v_total_crypto,
    'crypto',
    'Compra de ' || v_package.name || ' por ' || v_package.ron_price || ' RON'
  );

  RETURN json_build_object(
    'success', true,
    'purchase_id', v_purchase_id,
    'crypto_received', v_total_crypto,
    'ron_paid', v_package.ron_price,
    'bonus_percent', v_package.bonus_percent
  );
END;
$$;

-- Obtener historial de compras de crypto del jugador
CREATE OR REPLACE FUNCTION get_player_crypto_purchases(
  p_player_id UUID,
  p_limit INTEGER DEFAULT 20
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN (
    SELECT COALESCE(json_agg(row_to_json(t)), '[]'::JSON)
    FROM (
      SELECT
        cp.id,
        cp.package_id,
        pkg.name as package_name,
        cp.crypto_amount,
        cp.ron_paid,
        cp.status,
        cp.purchased_at,
        cp.completed_at
      FROM crypto_purchases cp
      JOIN crypto_packages pkg ON pkg.id = cp.package_id
      WHERE cp.player_id = p_player_id
      ORDER BY cp.purchased_at DESC
      LIMIT p_limit
    ) t
  );
END;
$$;

-- =====================================================
-- SISTEMA DE ANUNCIOS (INFO BAR)
-- =====================================================

-- Tabla de anuncios
CREATE TABLE IF NOT EXISTS announcements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  message TEXT NOT NULL,
  message_es TEXT,  -- Mensaje en español (opcional)
  type TEXT NOT NULL DEFAULT 'info' CHECK (type IN ('info', 'warning', 'success', 'error', 'maintenance')),
  icon TEXT DEFAULT '📢',
  link_url TEXT,
  link_text TEXT,
  is_active BOOLEAN DEFAULT true,
  priority INTEGER DEFAULT 0,  -- Mayor prioridad = se muestra primero
  starts_at TIMESTAMPTZ DEFAULT NOW(),
  ends_at TIMESTAMPTZ,  -- NULL = sin fecha de fin
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_announcements_active ON announcements(is_active, starts_at, ends_at);

-- Función para obtener anuncios activos
DROP FUNCTION IF EXISTS get_active_announcements() CASCADE;
CREATE OR REPLACE FUNCTION get_active_announcements()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN (
    SELECT COALESCE(json_agg(row_to_json(t)), '[]'::JSON)
    FROM (
      SELECT
        id,
        message,
        message_es,
        type,
        icon,
        link_url,
        link_text,
        priority,
        starts_at,
        ends_at
      FROM announcements
      WHERE is_active = true
        AND starts_at <= NOW()
        AND (ends_at IS NULL OR ends_at > NOW())
      ORDER BY priority DESC, created_at DESC
      LIMIT 5
    ) t
  );
END;
$$;
