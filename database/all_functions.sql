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
ALTER TABLE players ADD COLUMN IF NOT EXISTS max_energy NUMERIC DEFAULT 300;
ALTER TABLE players ADD COLUMN IF NOT EXISTS max_internet NUMERIC DEFAULT 300;

-- Agregar columnas para degradación de rigs
ALTER TABLE player_rigs ADD COLUMN IF NOT EXISTS max_condition NUMERIC DEFAULT 100;
ALTER TABLE player_rigs ADD COLUMN IF NOT EXISTS times_repaired INTEGER DEFAULT 0;

-- Permitir múltiples rigs del mismo tipo por jugador (eliminar constraint único)
ALTER TABLE player_rigs DROP CONSTRAINT IF EXISTS player_rigs_player_id_rig_id_key;

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
DROP FUNCTION IF EXISTS create_new_block(UUID, NUMERIC, NUMERIC, NUMERIC, BOOLEAN) CASCADE;
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
DROP FUNCTION IF EXISTS confirm_ron_rig_purchase(UUID, TEXT, TEXT) CASCADE;
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
  UPDATE players SET energy = LEAST(max_energy, energy + p_amount) WHERE id = p_to_player;
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
  UPDATE players SET internet = LEAST(max_internet, internet + p_amount) WHERE id = p_to_player;
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
      v_max_energy_cap := COALESCE(v_player.max_energy, 300) * 0.5;
      v_max_internet_cap := COALESCE(v_player.max_internet, 300) * 0.5;

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
  VALUES (p_user_id, p_email, p_username, 1000, 0, 300, 300, 50, 'global')
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
             COALESCE(pr.hashrate_level, 1) as hashrate_level,
             COALESCE(pr.efficiency_level, 1) as efficiency_level,
             COALESCE(pr.thermal_level, 1) as thermal_level,
             json_build_object(
               'id', r.id, 'name', r.name, 'description', r.description,
               'hashrate', r.hashrate, 'power_consumption', r.power_consumption,
               'internet_consumption', r.internet_consumption,
               'tier', r.tier, 'repair_cost', r.repair_cost,
               'max_upgrade_level', COALESCE(r.max_upgrade_level, 3)
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
-- Anti-exploit: Si el usuario apaga y enciende muy rápido (<60s), la temperatura se multiplica x10
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
  v_new_temperature NUMERIC;
  v_seconds_since_off NUMERIC;
  v_quick_toggle_penalty BOOLEAN := false;
  v_quick_toggle_threshold NUMERIC := 60; -- segundos
  v_temperature_multiplier NUMERIC := 10; -- penalización x10
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

    -- Calcular nueva temperatura al encender
    -- Si fue apagado hace menos de 60 segundos Y no hubo modificaciones, aplicar penalización
    IF v_rig.deactivated_at IS NOT NULL THEN
      v_seconds_since_off := EXTRACT(EPOCH FROM (NOW() - v_rig.deactivated_at));

      IF v_seconds_since_off < v_quick_toggle_threshold THEN
        -- Solo penalizar si NO hubo modificaciones después de apagar
        -- (last_modified_at es NULL o anterior a deactivated_at)
        IF v_rig.last_modified_at IS NULL OR v_rig.last_modified_at < v_rig.deactivated_at THEN
          -- Penalización: temperatura x10 (pero mínimo 50°C para que duela)
          v_new_temperature := LEAST(100, GREATEST(50, v_rig.temperature * v_temperature_multiplier));
          v_quick_toggle_penalty := true;
        ELSE
          -- Hubo modificaciones (cooling, boost, reparación, upgrade), no penalizar
          -- Enfriamiento gradual normal
          v_new_temperature := GREATEST(0, v_rig.temperature - (v_seconds_since_off / 60) * 15);
        END IF;
      ELSE
        -- Enfriamiento gradual basado en tiempo apagado
        -- Cada 60 segundos reduce 15 grados, mínimo 0°C
        v_new_temperature := GREATEST(0, v_rig.temperature - (v_seconds_since_off / 60) * 15);
      END IF;
    ELSE
      -- Primera vez que se enciende, temperatura 0
      v_new_temperature := 0;
    END IF;

    -- Encender el rig
    UPDATE player_rigs
    SET is_active = true,
        activated_at = NOW(),
        deactivated_at = NULL,
        temperature = v_new_temperature
    WHERE id = p_rig_id
    RETURNING * INTO v_rig;

    -- Actualizar misiones de encender rig
    PERFORM update_mission_progress(p_player_id, 'tutorial_mine', 1);
    PERFORM update_mission_progress(p_player_id, 'start_rig', 1);

    RETURN json_build_object(
      'success', true,
      'isActive', true,
      'activatedAt', v_rig.activated_at,
      'temperature', v_rig.temperature,
      'quickTogglePenalty', v_quick_toggle_penalty,
      'message', CASE
        WHEN v_quick_toggle_penalty THEN 'Rig activado con penalización por toggle rápido'
        ELSE 'Rig activado'
      END
    );
  ELSE
    -- Apagar el rig (conservar temperatura para anti-exploit)
    UPDATE player_rigs
    SET is_active = false,
        activated_at = NULL,
        deactivated_at = NOW()
    WHERE id = p_rig_id
    RETURNING * INTO v_rig;

    RETURN json_build_object(
      'success', true,
      'isActive', false,
      'deactivatedAt', v_rig.deactivated_at,
      'temperature', v_rig.temperature,
      'message', 'Rig desactivado'
    );
  END IF;
END;
$$;

-- Reparar rig (con degradación permanente)
-- Cada reparación reduce max_condition en 30%
-- Cuando max_condition <= 10%, el rig ya no se puede reparar (máximo 3 reparaciones)
CREATE OR REPLACE FUNCTION repair_rig(p_player_id UUID, p_rig_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_rig RECORD;
  v_player players%ROWTYPE;
  v_repair_cost NUMERIC;
  v_times_repaired INTEGER;
  v_target_condition NUMERIC;
  v_max_repairs INTEGER := 3;
BEGIN
  SELECT pr.*, r.repair_cost as base_repair_cost, r.name as rig_name
  INTO v_rig
  FROM player_rigs pr
  JOIN rigs r ON r.id = pr.rig_id
  WHERE pr.id = p_rig_id AND pr.player_id = p_player_id;

  IF v_rig IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Rig no encontrado');
  END IF;

  v_times_repaired := COALESCE(v_rig.times_repaired, 0);

  -- Verificar si ya alcanzó el máximo de reparaciones
  IF v_times_repaired >= v_max_repairs THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Este rig ya alcanzó el máximo de reparaciones (3). Debes eliminarlo.',
      'times_repaired', v_times_repaired
    );
  END IF;

  -- Determinar a qué porcentaje se restaura según número de reparación
  -- Reparación 1 (times_repaired pasará de 0 a 1) -> 90%
  -- Reparación 2 (times_repaired pasará de 1 a 2) -> 70%
  -- Reparación 3 (times_repaired pasará de 2 a 3) -> 50%
  v_target_condition := CASE v_times_repaired
    WHEN 0 THEN 90
    WHEN 1 THEN 70
    WHEN 2 THEN 50
    ELSE 50
  END;

  -- Verificar si ya está en o por encima de la condición objetivo
  IF v_rig.condition >= v_target_condition THEN
    RETURN json_build_object(
      'success', false,
      'error', 'El rig debe estar por debajo del ' || v_target_condition || '% para reparar',
      'current_condition', v_rig.condition,
      'repair_target', v_target_condition
    );
  END IF;

  -- Calcular costo basado en la diferencia hasta el objetivo
  v_repair_cost := ((v_target_condition - v_rig.condition) / 100.0) * v_rig.base_repair_cost;

  SELECT * INTO v_player FROM players WHERE id = p_player_id;

  IF v_player.gamecoin_balance < v_repair_cost THEN
    RETURN json_build_object('success', false, 'error', 'GameCoin insuficiente', 'cost', v_repair_cost);
  END IF;

  -- Aplicar reparación
  UPDATE players SET gamecoin_balance = gamecoin_balance - v_repair_cost WHERE id = p_player_id;
  UPDATE player_rigs
  SET condition = v_target_condition,
      max_condition = v_target_condition,
      times_repaired = v_times_repaired + 1,
      last_modified_at = NOW()
  WHERE id = p_rig_id;

  INSERT INTO transactions (player_id, type, amount, currency, description)
  VALUES (p_player_id, 'rig_repair', -v_repair_cost, 'gamecoin',
          'Reparación #' || (v_times_repaired + 1) || ' de ' || v_rig.rig_name || ' (' || v_target_condition || '%)');

  -- Actualizar misión de reparar rig
  PERFORM update_mission_progress(p_player_id, 'repair_rig', 1);

  RETURN json_build_object(
    'success', true,
    'cost', v_repair_cost,
    'new_condition', v_target_condition,
    'new_max_condition', v_target_condition,
    'times_repaired', v_times_repaired + 1,
    'repairs_remaining', v_max_repairs - (v_times_repaired + 1),
    'warning', CASE
      WHEN v_times_repaired + 1 = 3 THEN 'Esta fue la última reparación posible. El rig deberá ser eliminado cuando falle.'
      WHEN v_times_repaired + 1 = 2 THEN 'Solo queda 1 reparación disponible.'
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

-- Comprar rig (soporta gamecoin, crypto, ron)
-- Comprar rig (va al inventario, permite duplicados)
CREATE OR REPLACE FUNCTION buy_rig(p_player_id UUID, p_rig_id TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player players%ROWTYPE;
  v_rig rigs%ROWTYPE;
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

  -- SIN RESTRICCIÓN DE DUPLICADOS - puede comprar múltiples del mismo tipo

  -- Manejar según la moneda del rig
  IF v_rig.currency = 'gamecoin' THEN
    IF v_player.gamecoin_balance < v_rig.base_price THEN
      RETURN json_build_object('success', false, 'error', 'GameCoin insuficiente');
    END IF;

    UPDATE players
    SET gamecoin_balance = gamecoin_balance - v_rig.base_price
    WHERE id = p_player_id;

    INSERT INTO transactions (player_id, type, amount, currency, description)
    VALUES (p_player_id, 'rig_purchase', -v_rig.base_price, 'gamecoin',
            'Compra de rig: ' || v_rig.name);

  ELSIF v_rig.currency = 'crypto' THEN
    IF v_player.crypto_balance < v_rig.base_price THEN
      RETURN json_build_object('success', false, 'error', 'Crypto insuficiente');
    END IF;

    UPDATE players
    SET crypto_balance = crypto_balance - v_rig.base_price
    WHERE id = p_player_id;

    INSERT INTO transactions (player_id, type, amount, currency, description)
    VALUES (p_player_id, 'rig_purchase', -v_rig.base_price, 'crypto',
            'Compra de rig: ' || v_rig.name);

  ELSIF v_rig.currency = 'ron' THEN
    IF COALESCE(v_player.ron_balance, 0) < v_rig.base_price THEN
      RETURN json_build_object(
        'success', false,
        'error', 'RON insuficiente',
        'required', v_rig.base_price,
        'current', COALESCE(v_player.ron_balance, 0)
      );
    END IF;

    UPDATE players
    SET ron_balance = ron_balance - v_rig.base_price
    WHERE id = p_player_id;

    INSERT INTO transactions (player_id, type, amount, currency, description)
    VALUES (p_player_id, 'rig_purchase', -v_rig.base_price, 'ron',
            'Compra de rig: ' || v_rig.name);
  END IF;

  -- AGREGAR AL INVENTARIO (no instalar directamente)
  INSERT INTO player_rig_inventory (player_id, rig_id, quantity)
  VALUES (p_player_id, p_rig_id, 1)
  ON CONFLICT (player_id, rig_id)
  DO UPDATE SET quantity = player_rig_inventory.quantity + 1;

  -- Actualizar misiones de comprar rig
  PERFORM update_mission_progress(p_player_id, 'buy_rig', 1);

  RETURN json_build_object(
    'success', true,
    'rig', row_to_json(v_rig),
    'message', 'Rig agregado al inventario'
  );
END;
$$;

-- Instalar rig desde inventario
CREATE OR REPLACE FUNCTION install_rig_from_inventory(p_player_id UUID, p_rig_id TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player players%ROWTYPE;
  v_rig rigs%ROWTYPE;
  v_inventory player_rig_inventory%ROWTYPE;
  v_total_rigs INT;
  v_new_rig_id UUID;
BEGIN
  -- Verificar jugador
  SELECT * INTO v_player FROM players WHERE id = p_player_id;
  IF v_player IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Jugador no encontrado');
  END IF;

  -- Verificar que tiene el rig en inventario
  SELECT * INTO v_inventory
  FROM player_rig_inventory
  WHERE player_id = p_player_id AND rig_id = p_rig_id;

  IF v_inventory IS NULL OR v_inventory.quantity <= 0 THEN
    RETURN json_build_object('success', false, 'error', 'No tienes este rig en el inventario');
  END IF;

  -- Verificar rig info
  SELECT * INTO v_rig FROM rigs WHERE id = p_rig_id;
  IF v_rig IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Rig no encontrado');
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

  -- Descontar del inventario
  IF v_inventory.quantity = 1 THEN
    DELETE FROM player_rig_inventory
    WHERE player_id = p_player_id AND rig_id = p_rig_id;
  ELSE
    UPDATE player_rig_inventory
    SET quantity = quantity - 1
    WHERE player_id = p_player_id AND rig_id = p_rig_id;
  END IF;

  -- Crear el rig instalado
  INSERT INTO player_rigs (
    player_id,
    rig_id,
    condition,
    max_condition,
    is_active,
    times_repaired
  )
  VALUES (
    p_player_id,
    p_rig_id,
    100,
    100,
    false,
    0
  )
  RETURNING id INTO v_new_rig_id;

  -- Actualizar misión de cantidad de rigs (v_total_rigs + 1 porque acabamos de agregar uno)
  PERFORM update_mission_progress(p_player_id, 'own_rigs', 1);

  RETURN json_build_object(
    'success', true,
    'rig_instance_id', v_new_rig_id,
    'rig', row_to_json(v_rig),
    'message', 'Rig instalado correctamente'
  );
END;
$$;

-- Obtener rigs en inventario del jugador
CREATE OR REPLACE FUNCTION get_player_rig_inventory(p_player_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN (
    SELECT COALESCE(json_agg(
      json_build_object(
        'rig_id', pri.rig_id,
        'quantity', pri.quantity,
        'name', r.name,
        'description', r.description,
        'hashrate', r.hashrate,
        'power_consumption', r.power_consumption,
        'internet_consumption', r.internet_consumption,
        'tier', r.tier
      )
    ), '[]'::json)
    FROM player_rig_inventory pri
    JOIN rigs r ON r.id = pri.rig_id
    WHERE pri.player_id = p_player_id
  );
END;
$$;

-- Confirmar compra de rig con RON (llamar después de verificar tx blockchain)
CREATE OR REPLACE FUNCTION confirm_ron_rig_purchase(
  p_player_id UUID,
  p_rig_id TEXT,
  p_tx_hash TEXT
)
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

  -- Verificar que sea un rig de RON
  IF v_rig.currency != 'ron' THEN
    RETURN json_build_object('success', false, 'error', 'Este rig no se compra con RON');
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
      'error', 'No tienes slots disponibles',
      'slots_used', v_total_rigs,
      'slots_total', v_player.rig_slots
    );
  END IF;

  -- Registrar transacción con hash de blockchain
  INSERT INTO transactions (player_id, type, amount, currency, description, metadata)
  VALUES (p_player_id, 'rig_purchase', -v_rig.base_price, 'ron',
          'Compra de rig: ' || v_rig.name,
          json_build_object('tx_hash', p_tx_hash));

  -- Dar el rig al jugador
  INSERT INTO player_rigs (player_id, rig_id, condition, is_active, temperature)
  VALUES (p_player_id, p_rig_id, 100, false, 0);

  RETURN json_build_object(
    'success', true,
    'rig', row_to_json(v_rig),
    'tx_hash', p_tx_hash,
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

  ELSIF v_upgrade.currency = 'ron' THEN
    IF COALESCE(v_player.ron_balance, 0) < v_upgrade.price THEN
      RETURN json_build_object(
        'success', false,
        'error', 'RON insuficiente',
        'required', v_upgrade.price,
        'current', COALESCE(v_player.ron_balance, 0)
      );
    END IF;

    -- Descontar RON
    UPDATE players
    SET ron_balance = ron_balance - v_upgrade.price
    WHERE id = p_player_id;

    -- Registrar transacción
    INSERT INTO transactions (player_id, type, amount, currency, description)
    VALUES (p_player_id, 'slot_purchase', -v_upgrade.price, 'ron',
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

-- Bloques recientes (reward e is_premium se guardan en blocks)
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
             json_build_object('id', p.id, 'username', p.username) as miner,
             COALESCE(b.reward, calculate_block_reward(b.height)) as reward,
             COALESCE(b.is_premium, false) as is_premium
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

-- Crear nuevo bloque (con reward e is_premium para historial público)
CREATE OR REPLACE FUNCTION create_new_block(
  p_miner_id UUID,
  p_difficulty NUMERIC,
  p_network_hashrate NUMERIC,
  p_reward NUMERIC DEFAULT NULL,
  p_is_premium BOOLEAN DEFAULT false
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

  INSERT INTO blocks (height, hash, previous_hash, miner_id, difficulty, network_hashrate, reward, is_premium)
  VALUES (v_new_height, v_new_hash, v_previous_hash, p_miner_id, p_difficulty, p_network_hashrate, p_reward, p_is_premium)
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
  v_ambient_temp NUMERIC := 0;  -- Temperatura base cuando rig está apagado
  -- Boost multipliers
  v_boosts JSON;
  v_energy_mult NUMERIC;
  v_internet_mult NUMERIC;
  v_temp_mult NUMERIC;
  v_durability_mult NUMERIC;
BEGIN
  -- Procesar jugadores que están ONLINE o tienen rigs con autonomous mining boost
  FOR v_player IN
    SELECT p.id, p.energy, p.internet
    FROM players p
    WHERE EXISTS (SELECT 1 FROM player_rigs pr WHERE pr.player_id = p.id AND pr.is_active = true)
      AND (
        p.is_online = true
        OR EXISTS (
          SELECT 1 FROM player_rigs pr2
          WHERE pr2.player_id = p.id AND pr2.is_active = true
            AND rig_has_autonomous_boost(pr2.id)
        )
      )
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
      -- Calentamiento más notorio para que el jugador note el efecto
      -- Sin cooling: temperatura sube rápidamente
      -- Con cooling apropiado: temperatura se estabiliza
      -- Aplicar multiplicador de boost de coolant_injection
      IF v_rig_cooling_power <= 0 THEN
        -- Sin cooling: calentamiento significativo (max 15°C por tick)
        -- Minero Básico (2.5): +2.5°C/tick → peligro en ~4 min
        -- ASIC S19 (18): +15°C/tick → peligro en ~40s
        -- Quantum (55): +15°C/tick (cap) → peligro en ~40s
        v_temp_increase := LEAST(v_rig.power_consumption * 1.0, 15) * v_temp_mult;
      ELSE
        -- Con cooling: calentamiento reducido por poder de refrigeración
        v_temp_increase := v_rig.power_consumption * 0.8;
        v_temp_increase := GREATEST(0, v_temp_increase - v_rig_cooling_power) * v_temp_mult;
      END IF;

      -- Calcular nueva temperatura
      v_new_temp := v_rig.temperature + v_temp_increase;

      -- Enfriamiento pasivo (solo con cooling instalado)
      IF v_new_temp > v_ambient_temp AND v_rig_cooling_power > 0 THEN
        -- Con cooling: enfriamiento basado en poder de refrigeración
        v_new_temp := v_new_temp - (v_rig_cooling_power * 0.15);
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
      -- Se decrementa 60 segundos porque cron corre cada minuto
      UPDATE rig_boosts
      SET remaining_seconds = GREATEST(0, remaining_seconds - 60)
      WHERE player_rig_id = v_rig.id AND remaining_seconds > 0;

      -- Eliminar boosts expirados
      DELETE FROM rig_boosts WHERE player_rig_id = v_rig.id AND remaining_seconds <= 0;

      -- Si condición llega a 0, apagar el rig (conservar temperatura para anti-exploit)
      IF (v_rig.condition - v_deterioration) <= 0 THEN
        UPDATE player_rigs
        SET is_active = false,
            deactivated_at = NOW(),
            activated_at = NULL
        WHERE id = v_rig.id;
        INSERT INTO player_events (player_id, type, data)
        VALUES (v_player.id, 'rig_broken', json_build_object(
          'rig_id', v_rig.id,
          'reason', 'wear_and_tear'
        ));
      END IF;
    END LOOP;

    -- Actualizar misiones de tiempo activo con rigs
    DECLARE
      v_active_rig_count INT;
    BEGIN
      SELECT COUNT(*) INTO v_active_rig_count
      FROM player_rigs WHERE player_id = v_player.id AND is_active = true;

      IF v_active_rig_count > 0 THEN
        -- rig_active_time: 1 minuto por cada tick con al menos 1 rig activo
        PERFORM update_mission_progress(v_player.id, 'rig_active_time', 1);

        -- multi_rig: si tiene 2+ rigs activos simultáneamente
        IF v_active_rig_count >= 2 THEN
          PERFORM update_mission_progress(v_player.id, 'multi_rig', 1);
          -- multi_rig_time: minutos con múltiples rigs activos
          PERFORM update_mission_progress(v_player.id, 'multi_rig_time', 1);
        END IF;
      END IF;
    END;

    -- Calcular nuevo nivel de energía e internet
    -- Ambos bajan proporcionalmente a su consumo real (mismo multiplicador)
    -- Los multiplicadores de boost ya fueron aplicados por rig en el loop anterior
    v_new_energy := GREATEST(0, v_player.energy - (v_total_power * 0.1));
    v_new_internet := GREATEST(0, v_player.internet - (v_total_internet * 0.1));

    -- Actualizar recursos del jugador
    UPDATE players
    SET energy = v_new_energy,
        internet = v_new_internet
    WHERE id = v_player.id;

    -- Apagar rigs si no hay energía o internet (conservar temperatura para anti-exploit)
    IF v_new_energy = 0 OR v_new_internet = 0 THEN
      UPDATE player_rigs
      SET is_active = false,
          deactivated_at = NOW(),
          activated_at = NULL
      WHERE player_id = v_player.id AND is_active = true;
      INSERT INTO player_events (player_id, type, data)
      VALUES (v_player.id, 'rigs_shutdown', json_build_object(
        'reason', CASE WHEN v_new_energy = 0 THEN 'energy' ELSE 'internet' END
      ));
    END IF;

    v_processed := v_processed + 1;
  END LOOP;

  -- Enfriar rigs inactivos hacia 0°C (más rápido que antes)
  UPDATE player_rigs
  SET temperature = GREATEST(0, temperature - 5)
  WHERE is_active = false AND temperature > 0;

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
  -- Incluye jugadores online O rigs con autonomous mining boost
  FOR v_rig IN
    SELECT pr.id as rig_id, pr.player_id, pr.condition, pr.temperature, r.hashrate, p.reputation_score
    FROM player_rigs pr
    JOIN rigs r ON r.id = pr.rig_id
    JOIN players p ON p.id = pr.player_id
    WHERE pr.is_active = true AND p.energy > 0 AND p.internet > 0
      AND (p.is_online = true OR rig_has_autonomous_boost(pr.id))
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

    -- Penalización por condición: proporcional directo
    -- 100% condición = 100% hashrate, 50% = 50%, mínimo 10%
    v_condition_penalty := GREATEST(0.1, v_rig.condition / 100.0);

    -- Aplicar multiplicador de boost de hashrate
    v_effective_hashrate := v_rig.hashrate * v_condition_penalty * v_rep_multiplier * v_temp_penalty * v_hashrate_mult;
    v_network_hashrate := v_network_hashrate + v_effective_hashrate;
  END LOOP;

  -- Actualizar hashrate de red y mineros activos
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
  -- Incluye jugadores online O rigs con autonomous mining boost
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

    IF v_rig.condition >= 80 THEN
      v_condition_penalty := 1.0;
    ELSE
      v_condition_penalty := 0.3 + (v_rig.condition / 80.0) * 0.7;
    END IF;

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

  -- Calcular altura del siguiente bloque y recompensa ANTES de crear
  DECLARE
    v_next_height INT;
    v_is_premium BOOLEAN;
    v_base_reward NUMERIC;
  BEGIN
    SELECT COALESCE(MAX(height), 0) + 1 INTO v_next_height FROM blocks;
    v_base_reward := calculate_block_reward(v_next_height);
    v_is_premium := is_player_premium(v_winner_player_id);

    -- Aplicar bonus premium (+50%)
    IF v_is_premium THEN
      v_reward := v_base_reward * 1.5;
    ELSE
      v_reward := v_base_reward;
    END IF;

    -- Crear bloque con reward e is_premium guardados
    v_block := create_new_block(v_winner_player_id, v_difficulty, v_network_hashrate, v_reward, v_is_premium);

    IF v_block.id IS NULL THEN
      RETURN QUERY SELECT false, NULL::INT;
      RETURN;
    END IF;

    -- Crear pending_block para que el jugador lo reclame
    INSERT INTO pending_blocks (block_id, player_id, reward, is_premium)
    VALUES (v_block.id, v_winner_player_id, v_reward, v_is_premium);

    -- Actualizar contador de bloques minados (para leaderboard)
    -- Resetear pity accumulator (encontró bloque real, no necesita pity)
    UPDATE players
    SET blocks_mined = COALESCE(blocks_mined, 0) + 1,
        mining_bonus_accumulated = 0
    WHERE id = v_winner_player_id;

    PERFORM update_reputation(v_winner_player_id, 0.1, 'block_mined');

    -- Actualizar progreso de misiones de minado
    PERFORM update_mission_progress(v_winner_player_id, 'mine_blocks', 1);
    PERFORM update_mission_progress(v_winner_player_id, 'first_block', 1);
    PERFORM update_mission_progress(v_winner_player_id, 'total_blocks', 1);

    RETURN QUERY SELECT true, v_block.height;
  END;
END;
$$;

-- =====================================================
-- AJUSTE DE DIFICULTAD ESTILO BITCOIN (TARGET DINÁMICO)
-- Cada 6 horas, basado en bloques reales minados vs esperados
-- Máximo ±25% de cambio por ajuste
-- TARGET DINÁMICO: bloques esperados escalan con hashrate de red
-- Fórmula: (hashrate/1000) * 6 bloques/hora * 6 horas
-- Esto hace que más jugadores generen más bloques, no solo más rápido
-- =====================================================

-- Agregar columnas para rastrear ajustes de dificultad
ALTER TABLE network_stats ADD COLUMN IF NOT EXISTS last_difficulty_adjustment TIMESTAMPTZ DEFAULT NOW();
ALTER TABLE network_stats ADD COLUMN IF NOT EXISTS last_adjustment_block INTEGER DEFAULT 0;

-- =====================================================
-- AJUSTE DE DIFICULTAD ESTILO BITCOIN
-- Objetivo: 1 bloque cada 10 minutos
-- Ajusta cada 10 bloques basándose en tiempo real vs esperado
-- =====================================================
CREATE OR REPLACE FUNCTION adjust_difficulty()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_current_difficulty NUMERIC;
  v_current_hashrate NUMERIC;
  v_last_adjustment_block INTEGER;
  v_latest_block_height INTEGER;
  v_adjustment_period INTEGER := 10;        -- Ajustar cada 10 bloques
  v_target_block_time INTEGER := 600;       -- 10 minutos en segundos
  v_max_change NUMERIC := 0.25;             -- ±25% máximo por ajuste
  v_min_difficulty NUMERIC := 100;          -- Dificultad mínima
  v_max_difficulty NUMERIC := 1000000;      -- Dificultad máxima
  v_time_expected NUMERIC;
  v_time_actual NUMERIC;
  v_first_block_time TIMESTAMPTZ;
  v_last_block_time TIMESTAMPTZ;
  v_adjustment_ratio NUMERIC;
  v_new_difficulty NUMERIC;
  v_blocks_in_period INTEGER;
BEGIN
  -- Obtener estado actual de la red
  SELECT difficulty, hashrate, COALESCE(last_adjustment_block, 0)
  INTO v_current_difficulty, v_current_hashrate, v_last_adjustment_block
  FROM network_stats WHERE id = 'current';

  -- Valor por defecto si no existe
  IF v_current_difficulty IS NULL THEN
    v_current_difficulty := 1000;
  END IF;

  -- Obtener altura del bloque más reciente
  SELECT MAX(height) INTO v_latest_block_height FROM blocks;

  -- Si no hay bloques aún, no ajustar
  IF v_latest_block_height IS NULL THEN
    RETURN json_build_object(
      'adjusted', false,
      'reason', 'No blocks mined yet',
      'current_difficulty', v_current_difficulty
    );
  END IF;

  -- Calcular cuántos bloques han pasado desde el último ajuste
  v_blocks_in_period := v_latest_block_height - v_last_adjustment_block;

  -- Solo ajustar cada N bloques
  IF v_blocks_in_period < v_adjustment_period THEN
    RETURN json_build_object(
      'adjusted', false,
      'reason', 'Waiting for more blocks',
      'blocks_since_adjustment', v_blocks_in_period,
      'blocks_needed', v_adjustment_period,
      'blocks_remaining', v_adjustment_period - v_blocks_in_period,
      'current_difficulty', v_current_difficulty,
      'current_block_height', v_latest_block_height
    );
  END IF;

  -- Obtener timestamp del primer bloque del período de ajuste
  SELECT created_at INTO v_first_block_time
  FROM blocks WHERE height = v_last_adjustment_block + 1;

  -- Obtener timestamp del último bloque (el más reciente)
  SELECT created_at INTO v_last_block_time
  FROM blocks WHERE height = v_latest_block_height;

  -- Si es el primer período (no hay bloque anterior), usar el primer bloque existente
  IF v_first_block_time IS NULL THEN
    SELECT MIN(created_at) INTO v_first_block_time FROM blocks;
  END IF;

  -- Calcular tiempo real transcurrido vs tiempo esperado
  -- Para 10 bloques, esperamos 9 intervalos de 10 minutos = 90 minutos = 5400 segundos
  v_time_actual := EXTRACT(EPOCH FROM (v_last_block_time - v_first_block_time));
  v_time_expected := (v_adjustment_period - 1) * v_target_block_time;

  -- Evitar división por cero (si todos los bloques tienen el mismo timestamp)
  IF v_time_actual <= 0 THEN
    v_time_actual := 1;
  END IF;

  -- Calcular ratio de ajuste
  -- Si bloques fueron muy rápidos (time_actual < expected): ratio > 1 → subir dificultad
  -- Si bloques fueron muy lentos (time_actual > expected): ratio < 1 → bajar dificultad
  v_adjustment_ratio := v_time_expected / v_time_actual;

  -- Limitar cambio a ±25%
  v_adjustment_ratio := GREATEST(1 - v_max_change, LEAST(1 + v_max_change, v_adjustment_ratio));

  -- Calcular nueva dificultad
  v_new_difficulty := ROUND(v_current_difficulty * v_adjustment_ratio);

  -- Aplicar límites de dificultad
  v_new_difficulty := GREATEST(v_min_difficulty, LEAST(v_max_difficulty, v_new_difficulty));

  -- Actualizar network_stats con nueva dificultad y bloque de referencia
  UPDATE network_stats
  SET difficulty = v_new_difficulty,
      last_adjustment_block = v_latest_block_height,
      last_difficulty_adjustment = NOW(),
      updated_at = NOW()
  WHERE id = 'current';

  -- Retornar información detallada del ajuste
  RETURN json_build_object(
    'adjusted', true,
    'period_blocks', v_adjustment_period,
    'target_block_time_seconds', v_target_block_time,
    'time_expected_seconds', v_time_expected,
    'time_actual_seconds', ROUND(v_time_actual),
    'avg_block_time_seconds', ROUND(v_time_actual / GREATEST(1, v_adjustment_period - 1)),
    'target_vs_actual', CONCAT(ROUND(v_time_expected/60), 'min vs ', ROUND(v_time_actual/60), 'min'),
    'old_difficulty', v_current_difficulty,
    'new_difficulty', v_new_difficulty,
    'change_percent', ROUND((v_adjustment_ratio - 1) * 100, 2),
    'blocks_analyzed', v_blocks_in_period,
    'adjustment_block', v_latest_block_height,
    'network_hashrate', v_current_hashrate
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
  v_pity_result JSON;
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
  -- EXCEPTO los que tienen boost de autonomous_mining activo
  -- Conservar temperatura para anti-exploit de toggle rápido
  IF v_inactive_marked > 0 THEN
    UPDATE player_rigs
    SET is_active = false,
        deactivated_at = NOW(),
        activated_at = NULL
    WHERE player_id IN (
      SELECT id FROM players
      WHERE is_online = false
        AND last_seen < NOW() - INTERVAL '5 minutes'
        AND last_seen > NOW() - INTERVAL '6 minutes'
    ) AND is_active = true
    AND NOT rig_has_autonomous_boost(id);
    GET DIAGNOSTICS v_rigs_shutdown = ROW_COUNT;
  END IF;

  -- Procesar decay de recursos (solo jugadores online)
  v_resources_processed := process_resource_decay();

  -- Ajustar dificultad antes de intentar minar
  v_difficulty_result := adjust_difficulty();

  -- Intentar minar bloque
  SELECT * INTO v_block_mined, v_block_height FROM process_mining_tick();

  -- Procesar bonus de tiempo de minado (Pity Timer)
  v_pity_result := process_mining_time_bonus();

  RETURN json_build_object(
    'success', true,
    'resourcesProcessed', v_resources_processed,
    'blockMined', v_block_mined,
    'blockHeight', v_block_height,
    'difficultyAdjusted', (v_difficulty_result->>'adjusted')::BOOLEAN,
    'playersMarkedOffline', v_inactive_marked,
    'rigsShutdown', v_rigs_shutdown,
    'pityBlocksCreated', (v_pity_result->>'pityBlocksCreated')::INT,
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
      UPDATE players SET energy = LEAST(max_energy, energy + p_quantity) WHERE id = v_buyer_id;
    WHEN 'internet' THEN
      UPDATE players SET internet = GREATEST(0, internet - p_quantity) WHERE id = v_seller_id;
      UPDATE players SET internet = LEAST(max_internet, internet + p_quantity) WHERE id = v_buyer_id;
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

  -- Actualizar misiones de trading
  PERFORM update_mission_progress(v_buyer_id, 'market_trade', 1);
  PERFORM update_mission_progress(v_seller_id, 'market_trade', 1);
  PERFORM update_mission_progress(v_buyer_id, 'first_trade', 1);
  PERFORM update_mission_progress(v_seller_id, 'first_trade', 1);
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
      SELECT id, name, description, cooling_power, energy_cost, base_price, tier
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
  v_existing rig_cooling%ROWTYPE;
  v_new_durability NUMERIC;
  v_max_durability NUMERIC := 200;  -- Cap máximo de durabilidad stackeada
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

  -- Obtener datos del item
  SELECT * INTO v_cooling FROM cooling_items WHERE id = p_cooling_id;

  -- Verificar si este cooling ya está instalado en el rig
  SELECT * INTO v_existing
  FROM rig_cooling
  WHERE player_rig_id = p_rig_id AND cooling_item_id = p_cooling_id;

  -- Remover del inventario
  IF v_inventory_item.quantity > 1 THEN
    UPDATE player_inventory
    SET quantity = quantity - 1
    WHERE id = v_inventory_item.id;
  ELSE
    DELETE FROM player_inventory WHERE id = v_inventory_item.id;
  END IF;

  IF v_existing IS NOT NULL THEN
    -- Ya está instalado: stackear durabilidad (máximo 200%)
    v_new_durability := LEAST(v_max_durability, v_existing.durability + 100);

    UPDATE rig_cooling
    SET durability = v_new_durability
    WHERE id = v_existing.id;

    -- Marcar el rig como modificado
    UPDATE player_rigs SET last_modified_at = NOW() WHERE id = p_rig_id;

    RETURN json_build_object(
      'success', true,
      'message', 'Durabilidad de refrigeración recargada',
      'item', row_to_json(v_cooling),
      'new_durability', v_new_durability,
      'stacked', true
    );
  ELSE
    -- No está instalado: insertar nuevo
    INSERT INTO rig_cooling (player_rig_id, cooling_item_id, durability)
    VALUES (p_rig_id, p_cooling_id, 100);

    -- Marcar el rig como modificado (evita penalización por quick toggle)
    UPDATE player_rigs SET last_modified_at = NOW() WHERE id = p_rig_id;

    RETURN json_build_object(
      'success', true,
      'message', 'Refrigeración instalada en el rig',
      'item', row_to_json(v_cooling),
      'new_durability', 100,
      'stacked', false
    );
  END IF;
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

-- Tasa de cambio: 1 crypto = 50 GameCoin
-- Tasa de conversión RON: 100,000 crypto = 1 RON

-- Exchange: Crypto → GameCoin
CREATE OR REPLACE FUNCTION exchange_crypto_to_gamecoin(p_player_id UUID, p_crypto_amount NUMERIC)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player players%ROWTYPE;
  v_exchange_rate NUMERIC := 50;  -- 1 crypto = 50 GameCoin
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
    'crypto_to_gamecoin', 50,  -- 1 crypto = 50 GameCoin
    'crypto_to_ron', 0.00001,  -- 100,000 crypto = 1 RON
    'min_crypto_for_ron', 100000  -- Mínimo para convertir a RON
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

-- Función que ejecuta el decay una vez por minuto (llamada por pg_cron)
CREATE OR REPLACE FUNCTION run_decay_cycle()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
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
  v_actual_card_id TEXT;
  v_card_type TEXT;
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
      crypto_balance = crypto_balance + v_crypto_reward,
      total_crypto_earned = COALESCE(total_crypto_earned, 0) + v_crypto_reward
  WHERE id = p_player_id;

  -- Dar item si corresponde
  IF v_item_type = 'prepaid_card' AND v_item_id IS NOT NULL THEN
    -- Primero intentar con la tarjeta exacta
    SELECT id INTO v_actual_card_id
    FROM prepaid_cards
    WHERE id = v_item_id
    LIMIT 1;

    -- Si no existe, buscar la tarjeta más pequeña del mismo tipo
    IF v_actual_card_id IS NULL THEN
      -- Extraer el tipo de tarjeta del item_id (ej: 'energy' de 'energy_10')
      v_card_type := split_part(v_item_id, '_', 1);

      SELECT id INTO v_actual_card_id
      FROM prepaid_cards
      WHERE card_type = v_card_type
      ORDER BY amount ASC
      LIMIT 1;
    END IF;

    -- Si encontramos una tarjeta válida, darla al jugador
    IF v_actual_card_id IS NOT NULL THEN
      INSERT INTO player_cards (player_id, card_id, code)
      VALUES (p_player_id, v_actual_card_id, generate_card_code());
      v_item_id := v_actual_card_id;
    ELSE
      -- No hay ninguna tarjeta de ese tipo, dar compensación en gamecoin
      UPDATE players
      SET gamecoin_balance = gamecoin_balance + 100
      WHERE id = p_player_id;
      v_gamecoin_reward := v_gamecoin_reward + 100;
      v_item_id := NULL;
      v_item_type := NULL;
    END IF;
  ELSIF v_item_type = 'cooling' AND v_item_id IS NOT NULL THEN
    -- Verificar si el cooling existe
    IF EXISTS (SELECT 1 FROM cooling_items WHERE id = v_item_id) THEN
      INSERT INTO player_inventory (player_id, item_type, item_id, quantity)
      VALUES (p_player_id, 'cooling', v_item_id, 1)
      ON CONFLICT (player_id, item_type, item_id)
      DO UPDATE SET quantity = player_inventory.quantity + 1;
    ELSE
      -- Buscar el cooling más barato que exista
      SELECT id INTO v_item_id FROM cooling_items ORDER BY base_price ASC LIMIT 1;
      IF v_item_id IS NOT NULL THEN
        INSERT INTO player_inventory (player_id, item_type, item_id, quantity)
        VALUES (p_player_id, 'cooling', v_item_id, 1)
        ON CONFLICT (player_id, item_type, item_id)
        DO UPDATE SET quantity = player_inventory.quantity + 1;
      ELSE
        -- No hay cooling, dar gamecoin
        UPDATE players SET gamecoin_balance = gamecoin_balance + 100 WHERE id = p_player_id;
        v_gamecoin_reward := v_gamecoin_reward + 100;
        v_item_id := NULL;
        v_item_type := NULL;
      END IF;
    END IF;
  ELSIF v_item_type = 'rig' AND v_item_id IS NOT NULL THEN
    -- Verificar si el rig existe
    IF EXISTS (SELECT 1 FROM rigs WHERE id = v_item_id) THEN
      INSERT INTO player_inventory (player_id, item_type, item_id, quantity)
      VALUES (p_player_id, 'rig', v_item_id, 1)
      ON CONFLICT (player_id, item_type, item_id)
      DO UPDATE SET quantity = player_inventory.quantity + 1;
    ELSE
      -- Buscar el rig más barato que exista
      SELECT id INTO v_item_id FROM rigs ORDER BY base_price ASC LIMIT 1;
      IF v_item_id IS NOT NULL THEN
        INSERT INTO player_inventory (player_id, item_type, item_id, quantity)
        VALUES (p_player_id, 'rig', v_item_id, 1)
        ON CONFLICT (player_id, item_type, item_id)
        DO UPDATE SET quantity = player_inventory.quantity + 1;
      ELSE
        -- No hay rig, dar gamecoin
        UPDATE players SET gamecoin_balance = gamecoin_balance + 100 WHERE id = p_player_id;
        v_gamecoin_reward := v_gamecoin_reward + 100;
        v_item_id := NULL;
        v_item_type := NULL;
      END IF;
    END IF;
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

  -- Actualizar misiones de racha de login
  PERFORM update_mission_progress(p_player_id, 'login_streak', 1);
  PERFORM update_mission_progress(p_player_id, 'daily_login', 1);

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
    SET crypto_balance = crypto_balance + v_mission.reward_amount,
        total_crypto_earned = COALESCE(total_crypto_earned, 0) + v_mission.reward_amount
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
  v_player players%ROWTYPE;
  v_free_max INTEGER := 300;
  v_premium_expired BOOLEAN := false;
BEGIN
  -- Verificar si el premium acaba de expirar
  SELECT * INTO v_player FROM players WHERE id = p_player_id;
  IF v_player.premium_until IS NOT NULL AND v_player.premium_until <= NOW() THEN
    -- Premium expiró: llenar energía e internet al máximo free (300) y limpiar premium_until
    UPDATE players SET
      energy = v_free_max,
      internet = v_free_max,
      premium_until = NULL  -- Marcar como procesado
    WHERE id = p_player_id AND premium_until IS NOT NULL AND premium_until <= NOW();

    IF FOUND THEN
      v_premium_expired := true;
    END IF;
  END IF;

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

    RETURN json_build_object('success', true, 'minutesOnline', 1, 'premiumExpired', v_premium_expired);
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

    RETURN json_build_object('success', true, 'minutesOnline', v_new_minutes, 'added', v_minutes_since_last, 'premiumExpired', v_premium_expired);
  END IF;

  RETURN json_build_object('success', true, 'minutesOnline', v_tracking.minutes_online, 'added', 0, 'premiumExpired', v_premium_expired);
END;
$$;

-- =====================================================
-- BOOST ITEMS SYSTEM
-- Temporary power-ups for mining performance
-- =====================================================

-- Update CHECK constraints for existing tables
DO $$
BEGIN
  -- Update boost_type constraint
  IF EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE table_name = 'boost_items' AND constraint_type = 'CHECK'
  ) THEN
    ALTER TABLE boost_items DROP CONSTRAINT IF EXISTS boost_items_boost_type_check;
    ALTER TABLE boost_items ADD CONSTRAINT boost_items_boost_type_check CHECK (boost_type IN (
      'hashrate', 'energy_saver', 'bandwidth_optimizer', 'lucky_charm',
      'overclock', 'coolant_injection', 'durability_shield', 'autonomous_mining'
    ));

    -- Update currency constraint to include 'ron'
    ALTER TABLE boost_items DROP CONSTRAINT IF EXISTS boost_items_currency_check;
    ALTER TABLE boost_items ADD CONSTRAINT boost_items_currency_check CHECK (currency IN ('gamecoin', 'crypto', 'ron'));
  END IF;
END $$;

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
    'durability_shield',  -- -X% condition deterioration
    'autonomous_mining'   -- Keeps rig mining when player offline
  )),
  effect_value NUMERIC NOT NULL,          -- Primary effect percentage
  secondary_value NUMERIC DEFAULT 0,      -- Secondary effect for overclock
  duration_minutes INTEGER NOT NULL,       -- Duration in minutes
  base_price DECIMAL(10, 2) NOT NULL CHECK (base_price >= 0),
  currency TEXT NOT NULL DEFAULT 'gamecoin' CHECK (currency IN ('gamecoin', 'crypto', 'ron')),
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

-- Seed data para boost items
-- Durations: basic=15min, standard=30min, elite=60min (per-rig boosts)
-- Autonomous Mining: pagado en RON (dinero real)
-- Uses ON CONFLICT DO UPDATE to safely update existing items without foreign key issues

-- Eliminar IDs antiguos de autonomous mining (limpiar referencias primero)
DELETE FROM rig_boosts WHERE boost_item_id IN ('autonomous_1h', 'autonomous_4h', 'autonomous_12h', 'autonomous_24h', 'autonomous_72h');
DELETE FROM player_boosts WHERE boost_id IN ('autonomous_1h', 'autonomous_4h', 'autonomous_12h', 'autonomous_24h', 'autonomous_72h');
DELETE FROM boost_items WHERE id IN ('autonomous_1h', 'autonomous_4h', 'autonomous_12h', 'autonomous_24h', 'autonomous_72h');

INSERT INTO boost_items (id, name, description, boost_type, effect_value, secondary_value, duration_minutes, base_price, currency, tier, is_stackable, max_stack) VALUES
-- Hashrate Boosters (crypto)
('hashrate_small', 'Minor Hash Boost', '+15% hashrate for 1 hour', 'hashrate', 15, 0, 60, 500, 'crypto', 'basic', false, 1),
('hashrate_medium', 'Hash Boost', '+30% hashrate for 12 hours', 'hashrate', 30, 0, 720, 1500, 'crypto', 'standard', false, 1),
('hashrate_large', 'Mega Hash Boost', '+50% hashrate for 24 hours', 'hashrate', 50, 0, 1440, 4000, 'crypto', 'elite', false, 1),

-- Energy Savers (crypto)
('energy_saver_small', 'Power Saver', '-20% energy consumption for 1 hour', 'energy_saver', 20, 0, 60, 400, 'crypto', 'basic', false, 1),
('energy_saver_medium', 'Eco Mode', '-35% energy consumption for 12 hours', 'energy_saver', 35, 0, 720, 1200, 'crypto', 'standard', false, 1),
('energy_saver_large', 'Green Mining', '-50% energy consumption for 24 hours', 'energy_saver', 50, 0, 1440, 3500, 'crypto', 'elite', false, 1),

-- Bandwidth Optimizers (crypto)
('bandwidth_small', 'Data Optimizer', '-20% internet consumption for 1 hour', 'bandwidth_optimizer', 20, 0, 60, 400, 'crypto', 'basic', false, 1),
('bandwidth_medium', 'Network Boost', '-35% internet consumption for 12 hours', 'bandwidth_optimizer', 35, 0, 720, 1200, 'crypto', 'standard', false, 1),
('bandwidth_large', 'Fiber Mode', '-50% internet consumption for 24 hours', 'bandwidth_optimizer', 50, 0, 1440, 3500, 'crypto', 'elite', false, 1),

-- Lucky Charms (crypto - more expensive, affects block probability)
('lucky_small', 'Lucky Coin', '+8% block probability for 1 hour', 'lucky_charm', 8, 0, 60, 800, 'crypto', 'basic', false, 1),
('lucky_medium', 'Fortune Token', '+15% block probability for 12 hours', 'lucky_charm', 15, 0, 720, 2500, 'crypto', 'standard', false, 1),
('lucky_large', 'Jackpot Charm', '+25% block probability for 24 hours', 'lucky_charm', 25, 0, 1440, 7000, 'crypto', 'elite', false, 1),

-- Overclock Mode (crypto - hashrate boost + energy penalty)
('overclock_small', 'Overclock Lite', '+30% hashrate, +15% energy for 1 hour', 'overclock', 30, 15, 60, 600, 'crypto', 'basic', false, 1),
('overclock_medium', 'Overclock Pro', '+50% hashrate, +25% energy for 12 hours', 'overclock', 50, 25, 720, 1800, 'crypto', 'standard', false, 1),
('overclock_large', 'Overclock Max', '+75% hashrate, +35% energy for 24 hours', 'overclock', 75, 35, 1440, 5000, 'crypto', 'elite', false, 1),

-- Coolant Injection (crypto)
('coolant_small', 'Cooling Gel', '-25% temperature gain for 1 hour', 'coolant_injection', 25, 0, 60, 500, 'crypto', 'basic', false, 1),
('coolant_medium', 'Cryo Fluid', '-40% temperature gain for 12 hours', 'coolant_injection', 40, 0, 720, 1500, 'crypto', 'standard', false, 1),
('coolant_large', 'Liquid Nitrogen', '-60% temperature gain for 24 hours', 'coolant_injection', 60, 0, 1440, 4000, 'crypto', 'elite', false, 1),

-- Durability Shield (crypto)
('durability_small', 'Wear Guard', '-25% condition deterioration for 1 hour', 'durability_shield', 25, 0, 60, 500, 'crypto', 'basic', false, 1),
('durability_medium', 'Shield Coat', '-40% condition deterioration for 12 hours', 'durability_shield', 40, 0, 720, 1500, 'crypto', 'standard', false, 1),
('durability_large', 'Diamond Shell', '-60% condition deterioration for 24 hours', 'durability_shield', 60, 0, 1440, 4000, 'crypto', 'elite', false, 1),

-- Autonomous Mining (RON - keeps rig mining when offline)
('autonomous_day', 'Auto-Pilot Module', 'Keeps rig mining for 1 day while offline', 'autonomous_mining', 100, 0, 1440, 0.5, 'ron', 'standard', false, 1),
('autonomous_week', 'Night Shift Protocol', 'Keeps rig mining for 1 week while offline', 'autonomous_mining', 100, 0, 10080, 1, 'ron', 'advanced', false, 1),
('autonomous_month', 'Full Automation System', 'Keeps rig mining for 1 month while offline', 'autonomous_mining', 100, 0, 43200, 5, 'ron', 'elite', false, 1)
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
  IF v_boost.currency = 'ron' THEN
    IF COALESCE(v_player.ron_balance, 0) < v_boost.base_price THEN
      RETURN json_build_object('success', false, 'error', 'Insufficient RON', 'required', v_boost.base_price, 'current', COALESCE(v_player.ron_balance, 0));
    END IF;

    UPDATE players
    SET ron_balance = ron_balance - v_boost.base_price
    WHERE id = p_player_id;
  ELSIF v_boost.currency = 'crypto' THEN
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
    -- Siempre permitir stackear: agregar tiempo
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

  -- Marcar el rig como modificado (evita penalización por quick toggle)
  UPDATE player_rigs SET last_modified_at = NOW() WHERE id = p_rig_id;

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
  v_autonomous BOOLEAN := false;
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
      WHEN 'autonomous_mining' THEN
        v_autonomous := true;
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
    'durability', v_durability_mult,
    'autonomous', v_autonomous
  );
END;
$$;

-- Helper function to check if rig has autonomous mining boost
DROP FUNCTION IF EXISTS rig_has_autonomous_boost(UUID) CASCADE;
CREATE OR REPLACE FUNCTION rig_has_autonomous_boost(p_rig_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM rig_boosts rb
    JOIN boost_items bi ON bi.id = rb.boost_item_id
    WHERE rb.player_rig_id = p_rig_id
      AND rb.remaining_seconds > 0
      AND bi.boost_type = 'autonomous_mining'
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
    energy = 300,
    internet = 300,
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
  v_existing_tx UUID;
BEGIN
  -- Verificar que tx_hash no haya sido usado antes (previene doble gasto)
  IF p_tx_hash IS NOT NULL THEN
    SELECT id INTO v_existing_tx
    FROM crypto_purchases
    WHERE tx_hash = p_tx_hash
    LIMIT 1;

    IF v_existing_tx IS NOT NULL THEN
      RETURN json_build_object(
        'success', false,
        'error', 'Transacción ya utilizada'
      );
    END IF;
  END IF;

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

-- =====================================================
-- FUNCIONES BASICAS (desde migrations)
-- =====================================================

CREATE OR REPLACE FUNCTION increment_balance(p_player_id UUID, p_amount DECIMAL, p_currency TEXT)
RETURNS DECIMAL
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE new_balance DECIMAL;
BEGIN
  IF p_currency = 'gamecoin' THEN
    UPDATE players SET gamecoin_balance = gamecoin_balance + p_amount, updated_at = NOW()
    WHERE id = p_player_id RETURNING gamecoin_balance INTO new_balance;
  ELSIF p_currency = 'crypto' THEN
    UPDATE players SET crypto_balance = crypto_balance + p_amount, updated_at = NOW()
    WHERE id = p_player_id RETURNING crypto_balance INTO new_balance;
  END IF;
  RETURN new_balance;
END;
$$;

CREATE OR REPLACE FUNCTION update_reputation(p_player_id UUID, p_delta DECIMAL, p_reason TEXT)
RETURNS DECIMAL
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE old_score DECIMAL; new_score DECIMAL;
BEGIN
  SELECT reputation_score INTO old_score FROM players WHERE id = p_player_id;
  new_score := GREATEST(0, LEAST(100, old_score + p_delta));
  UPDATE players SET reputation_score = new_score, updated_at = NOW() WHERE id = p_player_id;
  INSERT INTO reputation_events (player_id, delta, reason, old_score, new_score)
  VALUES (p_player_id, p_delta, p_reason, old_score, new_score);
  RETURN new_score;
END;
$$;

CREATE OR REPLACE FUNCTION generate_card_code()
RETURNS TEXT LANGUAGE plpgsql AS $$
DECLARE v_code TEXT; v_exists BOOLEAN;
BEGIN
  LOOP
    v_code := UPPER(SUBSTRING(MD5(RANDOM()::TEXT || NOW()::TEXT) FROM 1 FOR 4) || '-' ||
      SUBSTRING(MD5(RANDOM()::TEXT || NOW()::TEXT) FROM 5 FOR 4) || '-' ||
      SUBSTRING(MD5(RANDOM()::TEXT || NOW()::TEXT) FROM 9 FOR 4));
    SELECT EXISTS(SELECT 1 FROM player_cards WHERE code = v_code) INTO v_exists;
    IF NOT v_exists THEN RETURN v_code; END IF;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_players_updated_at ON players;
CREATE TRIGGER update_players_updated_at BEFORE UPDATE ON players
FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- =====================================================
-- FUNCIONES PREMIUM
-- =====================================================

CREATE OR REPLACE FUNCTION is_player_premium(p_player_id UUID)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_premium_until TIMESTAMPTZ;
BEGIN
  SELECT premium_until INTO v_premium_until FROM players WHERE id = p_player_id;
  RETURN COALESCE(v_premium_until > NOW(), false);
END;
$$;

CREATE OR REPLACE FUNCTION get_block_reward_multiplier(p_player_id UUID)
RETURNS DECIMAL LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF is_player_premium(p_player_id) THEN RETURN 1.5; ELSE RETURN 1.0; END IF;
END;
$$;

CREATE OR REPLACE FUNCTION get_withdrawal_fee_rate(p_player_id UUID)
RETURNS DECIMAL LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF is_player_premium(p_player_id) THEN RETURN 0.10; ELSE RETURN 0.25; END IF;
END;
$$;

CREATE OR REPLACE FUNCTION get_premium_resource_bonus()
RETURNS INTEGER LANGUAGE plpgsql AS $$
BEGIN RETURN 700; END;  -- 300 base + 700 bonus = 1000 max para premium
$$;

CREATE OR REPLACE FUNCTION get_effective_max_energy(p_player_id UUID)
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_base_max INTEGER; v_bonus INTEGER := 0;
BEGIN
  SELECT max_energy INTO v_base_max FROM players WHERE id = p_player_id;
  IF is_player_premium(p_player_id) THEN v_bonus := get_premium_resource_bonus(); END IF;
  RETURN COALESCE(v_base_max, 300) + v_bonus;
END;
$$;

CREATE OR REPLACE FUNCTION get_effective_max_internet(p_player_id UUID)
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_base_max INTEGER; v_bonus INTEGER := 0;
BEGIN
  SELECT max_internet INTO v_base_max FROM players WHERE id = p_player_id;
  IF is_player_premium(p_player_id) THEN v_bonus := get_premium_resource_bonus(); END IF;
  RETURN COALESCE(v_base_max, 300) + v_bonus;
END;
$$;

-- =====================================================
-- FUNCIONES DE BLOQUES
-- =====================================================

-- Drop old function signatures (necesario si cambia el tipo de retorno)
DROP FUNCTION IF EXISTS get_pending_blocks(UUID) CASCADE;
DROP FUNCTION IF EXISTS claim_block(UUID) CASCADE;
DROP FUNCTION IF EXISTS claim_block(UUID, UUID) CASCADE;
DROP FUNCTION IF EXISTS claim_all_blocks() CASCADE;
DROP FUNCTION IF EXISTS claim_all_blocks(UUID) CASCADE;

CREATE OR REPLACE FUNCTION get_pending_blocks(p_player_id UUID)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_max_height INT;
BEGIN
  -- Get current max block height for pity blocks display
  SELECT COALESCE(MAX(height), 1) INTO v_max_height FROM blocks;

  RETURN (
    SELECT COALESCE(json_agg(row_to_json(t)), '[]'::JSON)
    FROM (
      SELECT pb.id,
             -- Pity blocks: generate fake block_id from pending id
             COALESCE(pb.block_id, pb.id) as block_id,
             -- Pity blocks: use realistic height near current max
             COALESCE(b.height, v_max_height) as block_height,
             pb.reward, pb.is_premium, pb.created_at
      FROM pending_blocks pb
      LEFT JOIN blocks b ON b.id = pb.block_id
      WHERE pb.player_id = p_player_id AND pb.claimed = false
      ORDER BY pb.created_at DESC
    ) t
  );
END;
$$;

CREATE OR REPLACE FUNCTION claim_block(p_player_id UUID, p_pending_id UUID)
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_pending pending_blocks%ROWTYPE; v_description TEXT; v_height INT;
BEGIN
  IF p_player_id IS NULL THEN RETURN json_build_object('success', false, 'error', 'Player ID requerido'); END IF;
  SELECT * INTO v_pending FROM pending_blocks WHERE id = p_pending_id AND player_id = p_player_id AND claimed = false;
  IF v_pending.id IS NULL THEN RETURN json_build_object('success', false, 'error', 'Bloque no encontrado'); END IF;
  UPDATE pending_blocks SET claimed = true, claimed_at = NOW() WHERE id = p_pending_id;
  UPDATE players SET crypto_balance = crypto_balance + v_pending.reward,
    total_crypto_earned = COALESCE(total_crypto_earned, 0) + v_pending.reward WHERE id = p_player_id;
  -- Get block height (real or simulated for pity)
  IF COALESCE(v_pending.is_pity, false) THEN
    SELECT COALESCE(MAX(height), 1) INTO v_height FROM blocks;
  ELSE
    SELECT height INTO v_height FROM blocks WHERE id = v_pending.block_id;
  END IF;
  v_description := 'Bloque reclamado #' || v_height;
  INSERT INTO transactions (player_id, type, amount, currency, description)
  VALUES (p_player_id, 'block_claim', v_pending.reward, 'crypto', v_description);
  -- Actualizar misiones de ganar crypto
  PERFORM update_mission_progress(p_player_id, 'earn_crypto', v_pending.reward);
  PERFORM update_mission_progress(p_player_id, 'total_crypto', v_pending.reward);
  RETURN json_build_object('success', true, 'reward', v_pending.reward, 'block_id', COALESCE(v_pending.block_id, v_pending.id));
END;
$$;

CREATE OR REPLACE FUNCTION claim_all_blocks(p_player_id UUID)
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_total_reward DECIMAL := 0; v_count INTEGER := 0; v_pending RECORD;
BEGIN
  IF p_player_id IS NULL THEN RETURN json_build_object('success', false, 'error', 'Player ID requerido'); END IF;
  FOR v_pending IN SELECT id, reward FROM pending_blocks WHERE player_id = p_player_id AND claimed = false LOOP
    v_total_reward := v_total_reward + v_pending.reward; v_count := v_count + 1;
    UPDATE pending_blocks SET claimed = true, claimed_at = NOW() WHERE id = v_pending.id;
  END LOOP;
  IF v_count = 0 THEN RETURN json_build_object('success', false, 'error', 'No hay bloques pendientes'); END IF;
  UPDATE players SET crypto_balance = crypto_balance + v_total_reward,
    total_crypto_earned = COALESCE(total_crypto_earned, 0) + v_total_reward WHERE id = p_player_id;
  INSERT INTO transactions (player_id, type, amount, currency, description)
  VALUES (p_player_id, 'block_claim_all', v_total_reward, 'crypto', 'Reclamados ' || v_count || ' bloques');
  -- Actualizar misiones de ganar crypto
  PERFORM update_mission_progress(p_player_id, 'earn_crypto', v_total_reward);
  PERFORM update_mission_progress(p_player_id, 'total_crypto', v_total_reward);
  RETURN json_build_object('success', true, 'total_reward', v_total_reward, 'blocks_claimed', v_count);
END;
$$;

CREATE OR REPLACE FUNCTION get_pending_blocks_count(p_player_id UUID)
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_count INTEGER; v_total_reward DECIMAL;
BEGIN
  SELECT COUNT(*), COALESCE(SUM(reward), 0) INTO v_count, v_total_reward
  FROM pending_blocks WHERE player_id = p_player_id AND claimed = false;
  RETURN json_build_object('count', v_count, 'total_reward', v_total_reward);
END;
$$;

CREATE OR REPLACE FUNCTION get_recent_blocks(p_limit INT DEFAULT 20)
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN (SELECT COALESCE(json_agg(row_to_json(t)), '[]'::JSON) FROM (
    SELECT b.id, b.height, b.hash, b.difficulty, b.network_hashrate, b.created_at,
      json_build_object('id', p.id, 'username', p.username) as miner,
      COALESCE(b.reward, calculate_block_reward(b.height)) as reward,
      COALESCE(b.is_premium, false) as is_premium
    FROM blocks b JOIN players p ON p.id = b.miner_id
    ORDER BY b.height DESC LIMIT p_limit
  ) t);
END;
$$;

-- =====================================================
-- FUNCIONES DE COMPRA PREMIUM
-- =====================================================

CREATE OR REPLACE FUNCTION purchase_premium(p_player_id UUID)
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_player players%ROWTYPE; v_price DECIMAL := 5; v_new_expires TIMESTAMPTZ; v_subscription_id UUID;
  v_premium_max INTEGER := 1000;  -- Max recursos para premium
BEGIN
  SELECT * INTO v_player FROM players WHERE id = p_player_id;
  IF v_player.id IS NULL THEN RETURN json_build_object('success', false, 'error', 'Jugador no encontrado'); END IF;
  IF v_player.premium_until IS NOT NULL AND v_player.premium_until > NOW() THEN
    RETURN json_build_object('success', false, 'error', 'Ya tienes Premium activo', 'expires_at', v_player.premium_until);
  END IF;
  IF COALESCE(v_player.ron_balance, 0) < v_price THEN
    RETURN json_build_object('success', false, 'error', 'Balance insuficiente', 'required', v_price, 'current', COALESCE(v_player.ron_balance, 0));
  END IF;
  v_new_expires := NOW() + INTERVAL '30 days';
  -- Al activar premium: llenar energía e internet al máximo premium (1000)
  UPDATE players SET
    ron_balance = ron_balance - v_price,
    premium_until = v_new_expires,
    energy = v_premium_max,
    internet = v_premium_max
  WHERE id = p_player_id;
  INSERT INTO premium_subscriptions (player_id, expires_at, amount_paid) VALUES (p_player_id, v_new_expires, v_price) RETURNING id INTO v_subscription_id;
  INSERT INTO transactions (player_id, type, amount, currency, description)
  VALUES (p_player_id, 'premium_purchase', -v_price, 'ron', 'Suscripcion Premium (30 dias)');
  -- Actualizar misión de primer premium
  PERFORM update_mission_progress(p_player_id, 'first_premium', 1);
  RETURN json_build_object('success', true, 'subscription_id', v_subscription_id, 'expires_at', v_new_expires, 'price', v_price, 'energy', v_premium_max, 'internet', v_premium_max);
END;
$$;

CREATE OR REPLACE FUNCTION get_premium_status(p_player_id UUID)
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_player players%ROWTYPE; v_is_premium BOOLEAN; v_days_remaining INTEGER;
BEGIN
  SELECT * INTO v_player FROM players WHERE id = p_player_id;
  IF v_player.id IS NULL THEN RETURN json_build_object('success', false, 'error', 'Jugador no encontrado'); END IF;
  v_is_premium := COALESCE(v_player.premium_until > NOW(), false);
  v_days_remaining := CASE WHEN v_is_premium THEN EXTRACT(DAY FROM (v_player.premium_until - NOW()))::INTEGER ELSE 0 END;
  RETURN json_build_object('success', true, 'is_premium', v_is_premium, 'expires_at', v_player.premium_until,
    'days_remaining', v_days_remaining, 'price', 5, 'benefits', json_build_object('block_bonus', '+50%', 'withdrawal_fee', '10%', 'resource_bonus', '+700'));
END;
$$;

-- =====================================================
-- FUNCIONES DE RON
-- =====================================================

CREATE OR REPLACE FUNCTION deposit_ron(p_player_id UUID, p_amount DECIMAL, p_tx_hash TEXT)
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_existing_id UUID; v_new_balance DECIMAL;
BEGIN
  IF p_amount <= 0 THEN RETURN json_build_object('success', false, 'error', 'Cantidad invalida'); END IF;
  IF p_tx_hash IS NULL OR p_tx_hash = '' THEN RETURN json_build_object('success', false, 'error', 'Hash requerido'); END IF;
  SELECT id INTO v_existing_id FROM ron_deposits WHERE tx_hash = p_tx_hash LIMIT 1;
  IF v_existing_id IS NOT NULL THEN RETURN json_build_object('success', false, 'error', 'Transaccion ya procesada'); END IF;
  INSERT INTO ron_deposits (player_id, amount, tx_hash, status) VALUES (p_player_id, p_amount, p_tx_hash, 'completed');
  UPDATE players SET ron_balance = ron_balance + p_amount, updated_at = NOW() WHERE id = p_player_id RETURNING ron_balance INTO v_new_balance;
  INSERT INTO transactions (player_id, type, amount, currency, description) VALUES (p_player_id, 'ron_deposit', p_amount, 'ron', 'Deposito de RON');
  RETURN json_build_object('success', true, 'amount', p_amount, 'new_balance', v_new_balance);
END;
$$;

CREATE OR REPLACE FUNCTION request_ron_withdrawal(p_player_id UUID)
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_player players%ROWTYPE; v_pending_count INTEGER; v_withdrawal_id UUID;
  v_min_withdrawal DECIMAL := 0.01; v_fee_rate DECIMAL; v_fee DECIMAL; v_net_amount DECIMAL; v_is_premium BOOLEAN;
BEGIN
  SELECT * INTO v_player FROM players WHERE id = p_player_id;
  IF v_player.id IS NULL THEN RETURN json_build_object('success', false, 'error', 'Jugador no encontrado'); END IF;
  IF v_player.ron_wallet IS NULL OR v_player.ron_wallet = '' THEN RETURN json_build_object('success', false, 'error', 'No tienes wallet'); END IF;
  IF COALESCE(v_player.ron_balance, 0) < v_min_withdrawal THEN RETURN json_build_object('success', false, 'error', 'Balance insuficiente'); END IF;
  v_is_premium := is_player_premium(p_player_id);
  v_fee_rate := get_withdrawal_fee_rate(p_player_id);
  v_fee := ROUND(v_player.ron_balance * v_fee_rate, 8);
  v_net_amount := v_player.ron_balance - v_fee;
  SELECT COUNT(*) INTO v_pending_count FROM ron_withdrawals WHERE player_id = p_player_id AND status IN ('pending', 'processing');
  IF v_pending_count > 0 THEN RETURN json_build_object('success', false, 'error', 'Ya tienes un retiro en proceso'); END IF;
  INSERT INTO ron_withdrawals (player_id, amount, fee, net_amount, wallet_address, status)
  VALUES (p_player_id, v_player.ron_balance, v_fee, v_net_amount, v_player.ron_wallet, 'pending') RETURNING id INTO v_withdrawal_id;
  UPDATE players SET ron_balance = 0 WHERE id = p_player_id;
  INSERT INTO transactions (player_id, type, amount, currency, description)
  VALUES (p_player_id, 'ron_withdrawal', -v_player.ron_balance, 'ron', 'Retiro de ' || v_net_amount || ' RON');
  RETURN json_build_object('success', true, 'withdrawal_id', v_withdrawal_id, 'amount', v_player.ron_balance,
    'fee', v_fee, 'fee_rate', v_fee_rate, 'net_amount', v_net_amount, 'wallet', v_player.ron_wallet, 'is_premium', v_is_premium);
END;
$$;

CREATE OR REPLACE FUNCTION get_withdrawal_history(p_player_id UUID, p_limit INTEGER DEFAULT 10)
RETURNS TABLE(id UUID, amount DECIMAL, fee DECIMAL, net_amount DECIMAL, wallet_address TEXT, status TEXT, tx_hash TEXT, created_at TIMESTAMPTZ, processed_at TIMESTAMPTZ)
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN QUERY SELECT w.id, w.amount, w.fee, w.net_amount, w.wallet_address, w.status, w.tx_hash, w.created_at, w.processed_at
  FROM ron_withdrawals w WHERE w.player_id = p_player_id ORDER BY w.created_at DESC LIMIT p_limit;
END;
$$;

CREATE OR REPLACE FUNCTION cancel_withdrawal(p_player_id UUID, p_withdrawal_id UUID)
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_withdrawal ron_withdrawals%ROWTYPE;
BEGIN
  SELECT * INTO v_withdrawal FROM ron_withdrawals WHERE id = p_withdrawal_id AND player_id = p_player_id;
  IF v_withdrawal.id IS NULL THEN RETURN json_build_object('success', false, 'error', 'Retiro no encontrado'); END IF;
  IF v_withdrawal.status != 'pending' THEN RETURN json_build_object('success', false, 'error', 'Solo se pueden cancelar retiros pendientes'); END IF;
  UPDATE ron_withdrawals SET status = 'cancelled' WHERE id = p_withdrawal_id;
  UPDATE players SET ron_balance = COALESCE(ron_balance, 0) + v_withdrawal.amount WHERE id = p_player_id;
  INSERT INTO transactions (player_id, type, amount, currency, description) VALUES (p_player_id, 'withdrawal_cancelled', v_withdrawal.amount, 'ron', 'Retiro cancelado');
  RETURN json_build_object('success', true, 'refunded', v_withdrawal.amount);
END;
$$;

-- =====================================================
-- FUNCIONES DE COMPRA
-- =====================================================

CREATE OR REPLACE FUNCTION buy_crypto_package(p_player_id UUID, p_package_id TEXT, p_tx_hash TEXT DEFAULT NULL)
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_player players%ROWTYPE; v_package crypto_packages%ROWTYPE; v_total_crypto NUMERIC; v_purchase_id UUID;
BEGIN
  SELECT * INTO v_player FROM players WHERE id = p_player_id;
  IF v_player.id IS NULL THEN RETURN json_build_object('success', false, 'error', 'Jugador no encontrado'); END IF;
  SELECT * INTO v_package FROM crypto_packages WHERE id = p_package_id AND is_active = true;
  IF v_package IS NULL THEN RETURN json_build_object('success', false, 'error', 'Paquete no disponible'); END IF;
  IF COALESCE(v_player.ron_balance, 0) < v_package.ron_price THEN
    RETURN json_build_object('success', false, 'error', 'Balance insuficiente', 'required', v_package.ron_price, 'current', v_player.ron_balance);
  END IF;
  v_total_crypto := v_package.crypto_amount * (1 + v_package.bonus_percent::NUMERIC / 100);
  UPDATE players SET ron_balance = ron_balance - v_package.ron_price, crypto_balance = crypto_balance + v_total_crypto, updated_at = NOW() WHERE id = p_player_id;
  INSERT INTO crypto_purchases (player_id, package_id, crypto_amount, ron_paid, tx_hash, status, completed_at)
  VALUES (p_player_id, p_package_id, v_total_crypto, v_package.ron_price, NULL, 'completed', NOW()) RETURNING id INTO v_purchase_id;
  INSERT INTO transactions (player_id, type, amount, currency, description) VALUES (p_player_id, 'crypto_purchase', -v_package.ron_price, 'ron', 'Compra de ' || v_package.name);
  INSERT INTO transactions (player_id, type, amount, currency, description) VALUES (p_player_id, 'crypto_purchase', v_total_crypto, 'crypto', 'Compra de ' || v_package.name);
  RETURN json_build_object('success', true, 'purchase_id', v_purchase_id, 'crypto_received', v_total_crypto, 'ron_paid', v_package.ron_price);
END;
$$;

CREATE OR REPLACE FUNCTION redeem_prepaid_card(p_player_id UUID, p_code TEXT)
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_player_card player_cards%ROWTYPE; v_card prepaid_cards%ROWTYPE; v_new_value NUMERIC; v_effective_max NUMERIC;
BEGIN
  SELECT * INTO v_player_card FROM player_cards WHERE code = UPPER(TRIM(p_code)) AND player_id = p_player_id;
  IF v_player_card IS NULL THEN RETURN json_build_object('success', false, 'error', 'Codigo invalido'); END IF;
  IF v_player_card.is_redeemed THEN RETURN json_build_object('success', false, 'error', 'Ya canjeada'); END IF;
  SELECT * INTO v_card FROM prepaid_cards WHERE id = v_player_card.card_id;
  IF v_card.card_type = 'energy' THEN
    v_effective_max := get_effective_max_energy(p_player_id);
    UPDATE players SET energy = LEAST(v_effective_max, energy + v_card.amount) WHERE id = p_player_id RETURNING energy INTO v_new_value;
  ELSE
    v_effective_max := get_effective_max_internet(p_player_id);
    UPDATE players SET internet = LEAST(v_effective_max, internet + v_card.amount) WHERE id = p_player_id RETURNING internet INTO v_new_value;
  END IF;
  UPDATE player_cards SET is_redeemed = true, redeemed_at = NOW() WHERE id = v_player_card.id;
  INSERT INTO transactions (player_id, type, amount, currency, description) VALUES (p_player_id, v_card.card_type || '_recharge', v_card.amount, 'gamecoin', 'Recarga: ' || v_card.name);
  -- Actualizar progreso de misiones de tarjetas prepago
  PERFORM update_mission_progress(p_player_id, 'use_prepaid_card', 1);
  RETURN json_build_object('success', true, 'card_type', v_card.card_type, 'amount', v_card.amount, 'new_value', v_new_value);
END;
$$;

CREATE OR REPLACE FUNCTION claim_mission_reward(p_player_id UUID, p_mission_uuid UUID)
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_pm player_missions%ROWTYPE; v_mission missions%ROWTYPE; v_effective_max NUMERIC;
BEGIN
  SELECT * INTO v_pm FROM player_missions WHERE id = p_mission_uuid AND player_id = p_player_id;
  IF v_pm IS NULL THEN RETURN json_build_object('success', false, 'error', 'Mision no encontrada'); END IF;
  IF NOT v_pm.is_completed THEN RETURN json_build_object('success', false, 'error', 'No completada'); END IF;
  IF v_pm.is_claimed THEN RETURN json_build_object('success', false, 'error', 'Ya reclamada'); END IF;
  SELECT * INTO v_mission FROM missions WHERE id = v_pm.mission_id;
  IF v_mission.reward_type = 'gamecoin' THEN
    UPDATE players SET gamecoin_balance = gamecoin_balance + v_mission.reward_amount WHERE id = p_player_id;
  ELSIF v_mission.reward_type = 'crypto' THEN
    UPDATE players SET crypto_balance = crypto_balance + v_mission.reward_amount, total_crypto_earned = COALESCE(total_crypto_earned, 0) + v_mission.reward_amount WHERE id = p_player_id;
  ELSIF v_mission.reward_type = 'energy' THEN
    v_effective_max := get_effective_max_energy(p_player_id);
    UPDATE players SET energy = LEAST(v_effective_max, energy + v_mission.reward_amount) WHERE id = p_player_id;
  ELSIF v_mission.reward_type = 'internet' THEN
    v_effective_max := get_effective_max_internet(p_player_id);
    UPDATE players SET internet = LEAST(v_effective_max, internet + v_mission.reward_amount) WHERE id = p_player_id;
  END IF;
  UPDATE player_missions SET is_claimed = true, claimed_at = NOW() WHERE id = p_mission_uuid;
  INSERT INTO transactions (player_id, type, amount, currency, description) VALUES (p_player_id, 'mission_reward', v_mission.reward_amount, v_mission.reward_type, 'Mision: ' || v_mission.name);
  RETURN json_build_object('success', true, 'rewardType', v_mission.reward_type, 'rewardAmount', v_mission.reward_amount, 'missionName', v_mission.name);
END;
$$;

CREATE OR REPLACE FUNCTION apply_passive_regeneration(p_player_id UUID)
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_player players%ROWTYPE; v_hours_offline NUMERIC; v_regen_rate NUMERIC := 5;
  v_energy_regen NUMERIC := 0; v_internet_regen NUMERIC := 0; v_new_energy NUMERIC; v_new_internet NUMERIC;
  v_max_energy_cap NUMERIC; v_max_internet_cap NUMERIC; v_effective_max_energy NUMERIC; v_effective_max_internet NUMERIC;
  v_premium_expired BOOLEAN := false; v_free_max INTEGER := 300;
BEGIN
  SELECT * INTO v_player FROM players WHERE id = p_player_id;
  IF v_player IS NULL THEN RETURN json_build_object('success', false, 'error', 'Jugador no encontrado'); END IF;

  -- Verificar si el premium expiró mientras estaba offline
  IF v_player.premium_until IS NOT NULL AND v_player.premium_until <= NOW() THEN
    -- Premium expiró: llenar energía e internet al máximo free (300) y limpiar premium_until
    UPDATE players SET energy = v_free_max, internet = v_free_max, premium_until = NULL, last_seen = NOW()
    WHERE id = p_player_id;
    v_premium_expired := true;
    RETURN json_build_object('success', true, 'energyGained', 0, 'internetGained', 0,
      'premiumExpired', true, 'energy', v_free_max, 'internet', v_free_max);
  END IF;

  IF v_player.last_seen IS NULL THEN RETURN json_build_object('success', true, 'energyGained', 0, 'internetGained', 0); END IF;
  v_hours_offline := LEAST(24, EXTRACT(EPOCH FROM (NOW() - v_player.last_seen)) / 3600);
  IF v_hours_offline < 0.0833 THEN RETURN json_build_object('success', true, 'energyGained', 0, 'internetGained', 0); END IF;
  v_effective_max_energy := get_effective_max_energy(p_player_id);
  v_effective_max_internet := get_effective_max_internet(p_player_id);
  v_max_energy_cap := v_effective_max_energy * 0.5;
  v_max_internet_cap := v_effective_max_internet * 0.5;
  IF v_player.energy < v_max_energy_cap THEN
    v_energy_regen := LEAST(v_max_energy_cap - v_player.energy, v_hours_offline * v_regen_rate);
    v_new_energy := LEAST(v_max_energy_cap, v_player.energy + v_energy_regen);
  ELSE v_new_energy := v_player.energy; END IF;
  IF v_player.internet < v_max_internet_cap THEN
    v_internet_regen := LEAST(v_max_internet_cap - v_player.internet, v_hours_offline * v_regen_rate);
    v_new_internet := LEAST(v_max_internet_cap, v_player.internet + v_internet_regen);
  ELSE v_new_internet := v_player.internet; END IF;
  IF v_energy_regen > 0 OR v_internet_regen > 0 THEN
    UPDATE players SET energy = v_new_energy, internet = v_new_internet, last_seen = NOW() WHERE id = p_player_id;
  ELSE UPDATE players SET last_seen = NOW() WHERE id = p_player_id; END IF;
  RETURN json_build_object('success', true, 'energyGained', ROUND(v_energy_regen, 1), 'internetGained', ROUND(v_internet_regen, 1),
    'hoursOffline', ROUND(v_hours_offline, 2), 'effectiveMaxEnergy', v_effective_max_energy, 'effectiveMaxInternet', v_effective_max_internet);
END;
$$;

-- =====================================================
-- FUNCIONES DE PERFIL
-- =====================================================

CREATE OR REPLACE FUNCTION update_ron_wallet(p_player_id UUID, p_wallet_address TEXT)
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_clean_wallet TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM players WHERE id = p_player_id) THEN RETURN json_build_object('success', false, 'error', 'Jugador no encontrado'); END IF;
  v_clean_wallet := TRIM(p_wallet_address);
  IF v_clean_wallet IS NULL OR v_clean_wallet = '' THEN
    UPDATE players SET ron_wallet = NULL, updated_at = NOW() WHERE id = p_player_id;
    RETURN json_build_object('success', true, 'wallet', NULL);
  END IF;
  IF NOT (v_clean_wallet ~* '^0x[a-fA-F0-9]{40}$') THEN RETURN json_build_object('success', false, 'error', 'Formato invalido'); END IF;
  UPDATE players SET ron_wallet = v_clean_wallet, updated_at = NOW() WHERE id = p_player_id;
  RETURN json_build_object('success', true, 'wallet', v_clean_wallet);
END;
$$;

CREATE OR REPLACE FUNCTION reset_player_account(p_player_id UUID)
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM players WHERE id = p_player_id) THEN RETURN json_build_object('success', false, 'error', 'Jugador no encontrado'); END IF;
  DELETE FROM player_rigs WHERE player_id = p_player_id;
  DELETE FROM player_cooling WHERE player_id = p_player_id;
  DELETE FROM player_inventory WHERE player_id = p_player_id;
  DELETE FROM player_cards WHERE player_id = p_player_id;
  DELETE FROM player_boosts WHERE player_id = p_player_id;
  DELETE FROM player_missions WHERE player_id = p_player_id;
  DELETE FROM player_streaks WHERE player_id = p_player_id;
  DELETE FROM streak_claims WHERE player_id = p_player_id;
  DELETE FROM market_orders WHERE player_id = p_player_id;
  DELETE FROM transactions WHERE player_id = p_player_id;
  UPDATE players SET gamecoin_balance = 1000, crypto_balance = 0, energy = 300, internet = 300, reputation_score = 50, rig_slots = 1, blocks_mined = 0, updated_at = NOW() WHERE id = p_player_id;
  INSERT INTO player_rigs (player_id, rig_id, condition, is_active) VALUES (p_player_id, 'basic_miner', 100, false);
  INSERT INTO transactions (player_id, type, amount, currency, description) VALUES (p_player_id, 'account_reset', 1000, 'gamecoin', 'Cuenta reiniciada');
  RETURN json_build_object('success', true, 'message', 'Cuenta reiniciada');
END;
$$;

-- =====================================================
-- FUNCIONES DE UPGRADES
-- =====================================================

CREATE OR REPLACE FUNCTION upgrade_rig(p_player_id UUID, p_player_rig_id UUID, p_upgrade_type TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_player RECORD; v_player_rig RECORD; v_current_level INTEGER; v_next_level INTEGER; v_upgrade_cost RECORD;
BEGIN
  IF p_upgrade_type NOT IN ('hashrate', 'efficiency', 'thermal') THEN RETURN jsonb_build_object('success', false, 'error', 'Tipo invalido'); END IF;
  SELECT * INTO v_player FROM players WHERE id = p_player_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'Jugador no encontrado'); END IF;
  SELECT pr.*, r.max_upgrade_level INTO v_player_rig FROM player_rigs pr JOIN rigs r ON pr.rig_id = r.id WHERE pr.id = p_player_rig_id AND pr.player_id = p_player_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'Rig no encontrado'); END IF;
  IF v_player_rig.is_active THEN RETURN jsonb_build_object('success', false, 'error', 'Deten el rig primero'); END IF;
  CASE p_upgrade_type WHEN 'hashrate' THEN v_current_level := v_player_rig.hashrate_level;
    WHEN 'efficiency' THEN v_current_level := v_player_rig.efficiency_level;
    WHEN 'thermal' THEN v_current_level := v_player_rig.thermal_level; END CASE;
  v_next_level := v_current_level + 1;
  IF v_next_level > v_player_rig.max_upgrade_level THEN RETURN jsonb_build_object('success', false, 'error', 'Nivel maximo alcanzado'); END IF;
  SELECT * INTO v_upgrade_cost FROM upgrade_costs WHERE level = v_next_level;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'Nivel no valido'); END IF;
  IF v_player.crypto_balance < v_upgrade_cost.crypto_cost THEN RETURN jsonb_build_object('success', false, 'error', 'Crypto insuficiente', 'required', v_upgrade_cost.crypto_cost); END IF;
  UPDATE players SET crypto_balance = crypto_balance - v_upgrade_cost.crypto_cost WHERE id = p_player_id;
  CASE p_upgrade_type WHEN 'hashrate' THEN UPDATE player_rigs SET hashrate_level = v_next_level, last_modified_at = NOW() WHERE id = p_player_rig_id;
    WHEN 'efficiency' THEN UPDATE player_rigs SET efficiency_level = v_next_level, last_modified_at = NOW() WHERE id = p_player_rig_id;
    WHEN 'thermal' THEN UPDATE player_rigs SET thermal_level = v_next_level, last_modified_at = NOW() WHERE id = p_player_rig_id; END CASE;
  -- Actualizar misiones de upgrade
  PERFORM update_mission_progress(p_player_id, 'upgrade_rig', 1);
  PERFORM update_mission_progress(p_player_id, 'first_upgrade', 1);
  RETURN jsonb_build_object('success', true, 'upgrade_type', p_upgrade_type, 'new_level', v_next_level, 'crypto_spent', v_upgrade_cost.crypto_cost);
END;
$$;

-- =====================================================
-- FUNCIONES ADMIN PARA RETIROS
-- =====================================================

CREATE OR REPLACE FUNCTION admin_get_pending_withdrawals()
RETURNS TABLE(id UUID, player_id UUID, username TEXT, email TEXT, amount DECIMAL, fee DECIMAL, net_amount DECIMAL, wallet_address TEXT, status TEXT, created_at TIMESTAMPTZ)
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN QUERY SELECT w.id, w.player_id, p.username, p.email, w.amount, w.fee, w.net_amount, w.wallet_address, w.status, w.created_at
  FROM ron_withdrawals w JOIN players p ON p.id = w.player_id WHERE w.status IN ('pending', 'processing') ORDER BY w.created_at ASC;
END;
$$;

CREATE OR REPLACE FUNCTION admin_complete_withdrawal(p_withdrawal_id UUID, p_tx_hash TEXT)
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_withdrawal ron_withdrawals%ROWTYPE;
BEGIN
  SELECT * INTO v_withdrawal FROM ron_withdrawals WHERE id = p_withdrawal_id;
  IF v_withdrawal.id IS NULL THEN RETURN json_build_object('success', false, 'error', 'Retiro no encontrado'); END IF;
  IF v_withdrawal.status NOT IN ('pending', 'processing') THEN RETURN json_build_object('success', false, 'error', 'Ya procesado'); END IF;
  UPDATE ron_withdrawals SET status = 'completed', tx_hash = p_tx_hash, processed_at = NOW() WHERE id = p_withdrawal_id;
  RETURN json_build_object('success', true);
END;
$$;

CREATE OR REPLACE FUNCTION admin_fail_withdrawal(p_withdrawal_id UUID, p_error_message TEXT)
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_withdrawal ron_withdrawals%ROWTYPE;
BEGIN
  SELECT * INTO v_withdrawal FROM ron_withdrawals WHERE id = p_withdrawal_id;
  IF v_withdrawal.id IS NULL THEN RETURN json_build_object('success', false, 'error', 'Retiro no encontrado'); END IF;
  IF v_withdrawal.status NOT IN ('pending', 'processing') THEN RETURN json_build_object('success', false, 'error', 'Ya procesado'); END IF;
  UPDATE ron_withdrawals SET status = 'failed', error_message = p_error_message, processed_at = NOW() WHERE id = p_withdrawal_id;
  UPDATE players SET ron_balance = COALESCE(ron_balance, 0) + v_withdrawal.amount WHERE id = v_withdrawal.player_id;
  INSERT INTO transactions (player_id, type, amount, currency, description) VALUES (v_withdrawal.player_id, 'withdrawal_failed', v_withdrawal.amount, 'ron', 'Retiro fallido - devuelto');
  RETURN json_build_object('success', true, 'refunded', v_withdrawal.amount);
END;
$$;

-- =====================================================
-- FUNCIONES DEL SISTEMA DE REFERIDOS
-- =====================================================

-- Función para generar código único de referido
CREATE OR REPLACE FUNCTION generate_referral_code()
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
  v_code TEXT;
  v_exists BOOLEAN;
BEGIN
  LOOP
    -- Generar código aleatorio de 8 caracteres
    v_code := UPPER(SUBSTRING(MD5(RANDOM()::text || NOW()::text), 1, 8));
    -- Verificar si ya existe
    SELECT EXISTS(SELECT 1 FROM players WHERE referral_code = v_code) INTO v_exists;
    IF NOT v_exists THEN
      RETURN v_code;
    END IF;
  END LOOP;
END;
$$;

-- Trigger para asignar código al crear jugador
CREATE OR REPLACE FUNCTION assign_referral_code()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.referral_code IS NULL THEN
    NEW.referral_code := generate_referral_code();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_assign_referral_code ON players;
CREATE TRIGGER trigger_assign_referral_code
  BEFORE INSERT ON players
  FOR EACH ROW
  EXECUTE FUNCTION assign_referral_code();

-- Generar códigos para jugadores existentes que no tienen
UPDATE players
SET referral_code = UPPER(SUBSTRING(MD5(id::text || COALESCE(created_at::text, NOW()::text)), 1, 8))
WHERE referral_code IS NULL;

-- Función para obtener info de referidos
DROP FUNCTION IF EXISTS get_referral_info(UUID);
CREATE OR REPLACE FUNCTION get_referral_info(p_player_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player RECORD;
  v_referrer_username TEXT;
  v_recent_referrals JSON;
BEGIN
  -- Obtener datos del jugador
  SELECT referral_code, referred_by, referral_count
  INTO v_player
  FROM players
  WHERE id = p_player_id;

  IF v_player IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Jugador no encontrado');
  END IF;

  -- Obtener username del referrer si existe
  IF v_player.referred_by IS NOT NULL THEN
    SELECT username INTO v_referrer_username
    FROM players WHERE id = v_player.referred_by;
  END IF;

  -- Obtener últimos 5 referidos
  SELECT json_agg(json_build_object(
    'username', p.username,
    'joinedAt', p.created_at
  ) ORDER BY p.created_at DESC)
  INTO v_recent_referrals
  FROM (
    SELECT username, created_at
    FROM players
    WHERE referred_by = p_player_id
    ORDER BY created_at DESC
    LIMIT 5
  ) p;

  RETURN json_build_object(
    'success', true,
    'referralCode', v_player.referral_code,
    'referralCount', COALESCE(v_player.referral_count, 0),
    'referredBy', v_referrer_username,
    'recentReferrals', COALESCE(v_recent_referrals, '[]'::json)
  );
END;
$$;

-- Función para aplicar código de referido
DROP FUNCTION IF EXISTS apply_referral_code(UUID, TEXT);
CREATE OR REPLACE FUNCTION apply_referral_code(p_player_id UUID, p_referral_code TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_referrer_id UUID;
  v_referrer_username TEXT;
  v_player_referred_by UUID;
  v_player_created_at TIMESTAMPTZ;
  v_referrer_referred_by UUID;
  v_referrer_bonus INTEGER := 500;  -- GameCoin para quien refiere
  v_player_bonus INTEGER := 200;    -- GameCoin para el nuevo jugador
BEGIN
  -- SEGURIDAD: Verificar que el usuario solo puede aplicar código a su propia cuenta
  IF p_player_id != auth.uid() THEN
    RETURN json_build_object('success', false, 'error', 'unauthorized');
  END IF;

  -- Normalizar código
  p_referral_code := UPPER(TRIM(p_referral_code));

  -- Buscar quien tiene ese código
  SELECT id, username, referred_by INTO v_referrer_id, v_referrer_username, v_referrer_referred_by
  FROM players
  WHERE referral_code = p_referral_code;

  IF v_referrer_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'invalid_code');
  END IF;

  -- No puede usar su propio código
  IF v_referrer_id = p_player_id THEN
    RETURN json_build_object('success', false, 'error', 'own_code');
  END IF;

  -- SEGURIDAD: Evitar referencia circular (mi referido no puede ser mi referrer)
  IF v_referrer_referred_by = p_player_id THEN
    RETURN json_build_object('success', false, 'error', 'circular_reference');
  END IF;

  -- Verificar que el jugador no tenga ya un referrer
  SELECT referred_by, created_at INTO v_player_referred_by, v_player_created_at
  FROM players WHERE id = p_player_id;

  IF v_player_referred_by IS NOT NULL THEN
    RETURN json_build_object('success', false, 'error', 'already_referred');
  END IF;

  -- Solo se puede aplicar código en los primeros 7 días
  IF v_player_created_at < NOW() - INTERVAL '7 days' THEN
    RETURN json_build_object('success', false, 'error', 'too_late');
  END IF;

  -- Aplicar referido
  UPDATE players SET referred_by = v_referrer_id WHERE id = p_player_id;

  -- Incrementar contador del referrer
  UPDATE players SET referral_count = COALESCE(referral_count, 0) + 1 WHERE id = v_referrer_id;

  -- Dar bonus de GameCoin
  UPDATE players SET gamecoin_balance = gamecoin_balance + v_referrer_bonus WHERE id = v_referrer_id;
  UPDATE players SET gamecoin_balance = gamecoin_balance + v_player_bonus WHERE id = p_player_id;

  -- Registrar transacciones
  INSERT INTO transactions (player_id, type, amount, currency, description)
  VALUES
    (v_referrer_id, 'referral_bonus', v_referrer_bonus, 'gamecoin', 'Bonus por referir un amigo'),
    (p_player_id, 'referral_bonus', v_player_bonus, 'gamecoin', 'Bonus por usar código de referido');

  -- Actualizar progreso de misiones de referidos
  PERFORM update_mission_progress(v_referrer_id, 'referrals', 1);

  RETURN json_build_object(
    'success', true,
    'referrerUsername', v_referrer_username,
    'referrerBonus', v_referrer_bonus,
    'playerBonus', v_player_bonus
  );
END;
$$;

-- Función para actualizar código de referido (cuesta 500 crypto)
DROP FUNCTION IF EXISTS update_referral_code(UUID, TEXT);
CREATE OR REPLACE FUNCTION update_referral_code(p_player_id UUID, p_new_code TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player RECORD;
  v_cost INTEGER := 500;  -- Costo en crypto
  v_code_exists BOOLEAN;
  v_clean_code TEXT;
BEGIN
  -- Normalizar y validar código
  v_clean_code := UPPER(TRIM(p_new_code));

  -- Validar longitud (6-10 caracteres)
  IF LENGTH(v_clean_code) < 6 OR LENGTH(v_clean_code) > 10 THEN
    RETURN json_build_object('success', false, 'error', 'invalid_length');
  END IF;

  -- Validar que solo contenga letras y números
  IF v_clean_code !~ '^[A-Z0-9]+$' THEN
    RETURN json_build_object('success', false, 'error', 'invalid_characters');
  END IF;

  -- Obtener datos del jugador
  SELECT id, crypto_balance, referral_code
  INTO v_player
  FROM players
  WHERE id = p_player_id;

  IF v_player IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'player_not_found');
  END IF;

  -- Verificar si el código es el mismo
  IF v_player.referral_code = v_clean_code THEN
    RETURN json_build_object('success', false, 'error', 'same_code');
  END IF;

  -- Verificar si el código ya existe
  SELECT EXISTS(
    SELECT 1 FROM players WHERE referral_code = v_clean_code AND id != p_player_id
  ) INTO v_code_exists;

  IF v_code_exists THEN
    RETURN json_build_object('success', false, 'error', 'code_taken');
  END IF;

  -- Verificar balance de crypto
  IF v_player.crypto_balance < v_cost THEN
    RETURN json_build_object('success', false, 'error', 'insufficient_balance');
  END IF;

  -- Descontar crypto y actualizar código
  UPDATE players
  SET
    crypto_balance = crypto_balance - v_cost,
    referral_code = v_clean_code
  WHERE id = p_player_id;

  -- Registrar transacción
  INSERT INTO transactions (player_id, type, amount, currency, description)
  VALUES (p_player_id, 'referral_code_change', -v_cost, 'crypto', 'Cambio de código de referido');

  RETURN json_build_object(
    'success', true,
    'newCode', v_clean_code,
    'cost', v_cost
  );
END;
$$;

GRANT EXECUTE ON FUNCTION update_referral_code TO authenticated;

-- =====================================================
-- FUNCIÓN DE ESTIMACIÓN DE MINERÍA
-- Calcula tiempo estimado hasta próximo bloque
-- =====================================================

DROP FUNCTION IF EXISTS get_mining_estimate(UUID) CASCADE;

CREATE OR REPLACE FUNCTION get_mining_estimate(p_player_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player players%ROWTYPE;
  v_network_stats network_stats%ROWTYPE;
  v_rig RECORD;
  v_player_hashrate NUMERIC := 0;
  v_network_hashrate NUMERIC := 0;
  v_difficulty NUMERIC;
  v_rep_multiplier NUMERIC;
  v_temp_penalty NUMERIC;
  v_condition_penalty NUMERIC;
  v_effective_hashrate NUMERIC;
  v_boosts JSON;
  v_hashrate_mult NUMERIC;
  v_probability_per_tick NUMERIC;
  v_player_probability NUMERIC;
  v_estimated_minutes NUMERIC;
  v_blocks_per_hour NUMERIC;
  v_blocks_per_day NUMERIC;
  v_network_share NUMERIC;
  v_active_rigs INTEGER := 0;
  v_total_active_miners INTEGER;
  -- Para rango de confianza (distribución geométrica)
  v_min_minutes NUMERIC;  -- percentil 25
  v_max_minutes NUMERIC;  -- percentil 75
BEGIN
  -- Obtener jugador
  SELECT * INTO v_player FROM players WHERE id = p_player_id;
  IF v_player IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Jugador no encontrado');
  END IF;

  -- Obtener stats de red
  SELECT * INTO v_network_stats FROM network_stats WHERE id = 'current';
  v_difficulty := COALESCE(v_network_stats.difficulty, 1000);
  v_network_hashrate := COALESCE(v_network_stats.hashrate, 0);
  v_total_active_miners := COALESCE(v_network_stats.active_miners, 0);

  -- Calcular hashrate efectivo del jugador (mismo cálculo que process_mining_tick)
  FOR v_rig IN
    SELECT pr.id as rig_id, pr.condition, pr.temperature, r.hashrate,
           pr.hashrate_level, pr.efficiency_level, pr.thermal_level
    FROM player_rigs pr
    JOIN rigs r ON r.id = pr.rig_id
    WHERE pr.player_id = p_player_id AND pr.is_active = true
  LOOP
    v_active_rigs := v_active_rigs + 1;

    -- Obtener multiplicadores de boost del rig
    v_boosts := get_rig_boost_multipliers(v_rig.rig_id);
    v_hashrate_mult := COALESCE((v_boosts->>'hashrate')::NUMERIC, 1.0);

    -- Multiplicador de reputación
    IF v_player.reputation_score >= 80 THEN
      v_rep_multiplier := 1 + (v_player.reputation_score - 80) * 0.01;
    ELSIF v_player.reputation_score < 50 THEN
      v_rep_multiplier := 0.5 + (v_player.reputation_score / 100.0);
    ELSE
      v_rep_multiplier := 1;
    END IF;

    -- Penalización por temperatura (>50°C reduce hashrate)
    v_temp_penalty := 1;
    IF v_rig.temperature > 50 THEN
      v_temp_penalty := 1 - ((v_rig.temperature - 50) * 0.014);
      v_temp_penalty := GREATEST(0.3, v_temp_penalty);
    END IF;

    -- Penalización por condición: solo penaliza bajo 70%
    IF v_rig.condition >= 80 THEN
      v_condition_penalty := 1.0;
    ELSE
      v_condition_penalty := 0.3 + (v_rig.condition / 80.0) * 0.7;
    END IF;

    -- Bonus por nivel de hashrate upgrade (10% por nivel extra)
    v_hashrate_mult := v_hashrate_mult * (1 + (COALESCE(v_rig.hashrate_level, 1) - 1) * 0.10);

    -- Hashrate efectivo de este rig
    v_effective_hashrate := v_rig.hashrate * v_condition_penalty * v_rep_multiplier * v_temp_penalty * v_hashrate_mult;
    v_player_hashrate := v_player_hashrate + v_effective_hashrate;
  END LOOP;

  -- Si no tiene rigs activos o no está online
  IF v_active_rigs = 0 OR NOT v_player.is_online THEN
    RETURN json_build_object(
      'success', true,
      'mining', false,
      'reason', CASE
        WHEN v_active_rigs = 0 THEN 'no_active_rigs'
        ELSE 'offline'
      END,
      'playerHashrate', 0,
      'networkHashrate', v_network_hashrate,
      'difficulty', v_difficulty,
      'activeMiners', v_total_active_miners
    );
  END IF;

  -- Si no hay hashrate en la red (solo este jugador)
  IF v_network_hashrate = 0 THEN
    v_network_hashrate := v_player_hashrate;
  END IF;

  -- Calcular probabilidades
  -- Probabilidad de que se mine un bloque por tick
  v_probability_per_tick := v_network_hashrate / v_difficulty;

  -- Probabilidad de que ESTE jugador gane el bloque (dado que se mina uno)
  v_network_share := v_player_hashrate / v_network_hashrate;

  -- Probabilidad combinada: que se mine un bloque Y lo gane este jugador
  v_player_probability := v_probability_per_tick * v_network_share;

  -- Tiempo esperado (en minutos, ya que cada tick es 1 minuto)
  -- E[X] para distribución geométrica = 1/p
  IF v_player_probability > 0 THEN
    v_estimated_minutes := 1 / v_player_probability;

    -- Rango de confianza usando percentiles de distribución geométrica
    -- P(X <= k) = 1 - (1-p)^k
    -- Para encontrar k dado percentil: k = log(1-percentil) / log(1-p)
    -- Percentil 25 (25% de chance de encontrar antes)
    v_min_minutes := LN(1 - 0.25) / LN(1 - v_player_probability);
    -- Percentil 75 (75% de chance de encontrar antes)
    v_max_minutes := LN(1 - 0.75) / LN(1 - v_player_probability);
  ELSE
    v_estimated_minutes := 999999;
    v_min_minutes := 999999;
    v_max_minutes := 999999;
  END IF;

  -- Bloques esperados por hora y día
  v_blocks_per_hour := v_player_probability * 60;
  v_blocks_per_day := v_player_probability * 60 * 24;

  RETURN json_build_object(
    'success', true,
    'mining', true,
    -- Hashrate info
    'playerHashrate', ROUND(v_player_hashrate, 2),
    'networkHashrate', ROUND(v_network_hashrate, 2),
    'networkShare', ROUND(v_network_share * 100, 4),  -- Porcentaje de la red
    -- Probabilidades
    'difficulty', v_difficulty,
    'probabilityPerTick', ROUND(v_player_probability * 100, 6),  -- % por minuto
    -- Estimaciones de tiempo
    'estimatedMinutes', ROUND(v_estimated_minutes, 1),
    'estimatedHours', ROUND(v_estimated_minutes / 60, 2),
    'minMinutes', ROUND(v_min_minutes, 1),  -- Percentil 25
    'maxMinutes', ROUND(v_max_minutes, 1),  -- Percentil 75
    -- Bloques esperados
    'blocksPerHour', ROUND(v_blocks_per_hour, 4),
    'blocksPerDay', ROUND(v_blocks_per_day, 2),
    -- Info adicional
    'activeRigs', v_active_rigs,
    'activeMiners', v_total_active_miners,
    'reputationMultiplier', ROUND(v_rep_multiplier, 2)
  );
END;
$$;

-- =====================================================
-- FUNCIÓN PARA LISTAR REFERIDOS
-- =====================================================

DROP FUNCTION IF EXISTS get_referral_list(UUID, INTEGER, INTEGER);

CREATE OR REPLACE FUNCTION get_referral_list(
  p_player_id UUID,
  p_limit INTEGER DEFAULT 50,
  p_offset INTEGER DEFAULT 0
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_total_count INTEGER;
  v_referrals JSON;
  v_total_blocks_by_referrals INTEGER;
  v_total_crypto_by_referrals NUMERIC;
  v_active_referrals INTEGER;
BEGIN
  -- Verificar jugador
  IF NOT EXISTS (SELECT 1 FROM players WHERE id = p_player_id) THEN
    RETURN json_build_object('success', false, 'error', 'Jugador no encontrado');
  END IF;

  -- Contar total de referidos
  SELECT COUNT(*) INTO v_total_count
  FROM players WHERE referred_by = p_player_id;

  -- Contar referidos activos (online en últimas 24h)
  SELECT COUNT(*) INTO v_active_referrals
  FROM players
  WHERE referred_by = p_player_id
    AND last_seen > NOW() - INTERVAL '24 hours';

  -- Total de bloques minados por referidos
  SELECT COALESCE(SUM(blocks_mined), 0) INTO v_total_blocks_by_referrals
  FROM players WHERE referred_by = p_player_id;

  -- Total de crypto generado por referidos
  SELECT COALESCE(SUM(total_crypto_earned), 0) INTO v_total_crypto_by_referrals
  FROM players WHERE referred_by = p_player_id;

  -- Obtener lista de referidos con info detallada
  SELECT json_agg(row_to_json(t))
  INTO v_referrals
  FROM (
    SELECT
      p.id,
      p.username,
      p.created_at as "joinedAt",
      p.is_online as "isOnline",
      p.last_seen as "lastSeen",
      COALESCE(p.blocks_mined, 0) as "blocksMined",
      COALESCE(p.total_crypto_earned, 0) as "cryptoEarned",
      p.reputation_score as "reputation",
      -- Calcular días desde que se unió
      EXTRACT(DAY FROM (NOW() - p.created_at))::INTEGER as "daysAgo",
      -- Verificar si está activo (conectado en últimas 24h)
      (p.last_seen > NOW() - INTERVAL '24 hours') as "isActive",
      -- Contar rigs activos
      (SELECT COUNT(*) FROM player_rigs pr WHERE pr.player_id = p.id AND pr.is_active = true) as "activeRigs"
    FROM players p
    WHERE p.referred_by = p_player_id
    ORDER BY p.created_at DESC
    LIMIT p_limit
    OFFSET p_offset
  ) t;

  RETURN json_build_object(
    'success', true,
    'referrals', COALESCE(v_referrals, '[]'::json),
    'pagination', json_build_object(
      'total', v_total_count,
      'limit', p_limit,
      'offset', p_offset,
      'hasMore', (p_offset + p_limit) < v_total_count
    ),
    'stats', json_build_object(
      'totalReferrals', v_total_count,
      'activeReferrals', v_active_referrals,
      'totalBlocksByReferrals', v_total_blocks_by_referrals,
      'totalCryptoByReferrals', ROUND(v_total_crypto_by_referrals, 2)
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION get_referral_list TO authenticated;

-- =====================================================
-- FUNCIONES PARA DESTRUIR ITEMS INSTALADOS EN RIGS
-- =====================================================

-- Destruir/remover cooling instalado en un rig
DROP FUNCTION IF EXISTS remove_cooling_from_rig(UUID, UUID, UUID) CASCADE;
CREATE OR REPLACE FUNCTION remove_cooling_from_rig(
  p_player_id UUID,
  p_rig_id UUID,
  p_cooling_id UUID  -- ID del registro en rig_cooling (no el cooling_item_id)
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_rig player_rigs%ROWTYPE;
  v_cooling RECORD;
BEGIN
  -- Verificar que el rig pertenece al jugador
  SELECT * INTO v_rig
  FROM player_rigs
  WHERE id = p_rig_id AND player_id = p_player_id;

  IF v_rig IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Rig no encontrado');
  END IF;

  -- Verificar que el cooling está instalado en este rig
  SELECT rc.id, rc.cooling_item_id, rc.durability, ci.name
  INTO v_cooling
  FROM rig_cooling rc
  JOIN cooling_items ci ON ci.id = rc.cooling_item_id
  WHERE rc.id = p_cooling_id AND rc.player_rig_id = p_rig_id;

  IF v_cooling IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Refrigeración no encontrada en este rig');
  END IF;

  -- Eliminar el cooling (destruir - no se devuelve al inventario)
  DELETE FROM rig_cooling WHERE id = p_cooling_id;

  -- Marcar el rig como modificado (evita penalización por quick toggle)
  UPDATE player_rigs SET last_modified_at = NOW() WHERE id = p_rig_id;

  RETURN json_build_object(
    'success', true,
    'message', 'Refrigeración destruida',
    'destroyed', json_build_object(
      'name', v_cooling.name,
      'durability', v_cooling.durability
    )
  );
END;
$$;

-- Destruir/remover boost instalado en un rig
DROP FUNCTION IF EXISTS remove_boost_from_rig(UUID, UUID, UUID) CASCADE;
CREATE OR REPLACE FUNCTION remove_boost_from_rig(
  p_player_id UUID,
  p_rig_id UUID,
  p_boost_id UUID  -- ID del registro en rig_boosts (no el boost_item_id)
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_rig player_rigs%ROWTYPE;
  v_boost RECORD;
BEGIN
  -- Verificar que el rig pertenece al jugador
  SELECT * INTO v_rig
  FROM player_rigs
  WHERE id = p_rig_id AND player_id = p_player_id;

  IF v_rig IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Rig no encontrado');
  END IF;

  -- Verificar que el boost está instalado en este rig
  SELECT rb.id, rb.boost_item_id, rb.remaining_seconds, bi.name
  INTO v_boost
  FROM rig_boosts rb
  JOIN boost_items bi ON bi.id = rb.boost_item_id
  WHERE rb.id = p_boost_id AND rb.player_rig_id = p_rig_id;

  IF v_boost IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Boost no encontrado en este rig');
  END IF;

  -- Eliminar el boost (destruir - no se devuelve al inventario)
  DELETE FROM rig_boosts WHERE id = p_boost_id;

  -- Marcar el rig como modificado (evita penalización por quick toggle)
  UPDATE player_rigs SET last_modified_at = NOW() WHERE id = p_rig_id;

  RETURN json_build_object(
    'success', true,
    'message', 'Boost destruido',
    'destroyed', json_build_object(
      'name', v_boost.name,
      'remaining_seconds', v_boost.remaining_seconds
    )
  );
END;
$$;

-- Destruir TODOS los coolings de un rig
DROP FUNCTION IF EXISTS remove_all_cooling_from_rig(UUID, UUID) CASCADE;
CREATE OR REPLACE FUNCTION remove_all_cooling_from_rig(
  p_player_id UUID,
  p_rig_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_rig player_rigs%ROWTYPE;
  v_count INTEGER;
BEGIN
  -- Verificar que el rig pertenece al jugador
  SELECT * INTO v_rig
  FROM player_rigs
  WHERE id = p_rig_id AND player_id = p_player_id;

  IF v_rig IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Rig no encontrado');
  END IF;

  -- Contar cuántos hay
  SELECT COUNT(*) INTO v_count FROM rig_cooling WHERE player_rig_id = p_rig_id;

  IF v_count = 0 THEN
    RETURN json_build_object('success', false, 'error', 'No hay refrigeración instalada');
  END IF;

  -- Eliminar todos
  DELETE FROM rig_cooling WHERE player_rig_id = p_rig_id;

  -- Marcar el rig como modificado
  UPDATE player_rigs SET last_modified_at = NOW() WHERE id = p_rig_id;

  RETURN json_build_object(
    'success', true,
    'message', 'Toda la refrigeración destruida',
    'destroyed_count', v_count
  );
END;
$$;

-- Destruir TODOS los boosts de un rig
DROP FUNCTION IF EXISTS remove_all_boosts_from_rig(UUID, UUID) CASCADE;
CREATE OR REPLACE FUNCTION remove_all_boosts_from_rig(
  p_player_id UUID,
  p_rig_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_rig player_rigs%ROWTYPE;
  v_count INTEGER;
BEGIN
  -- Verificar que el rig pertenece al jugador
  SELECT * INTO v_rig
  FROM player_rigs
  WHERE id = p_rig_id AND player_id = p_player_id;

  IF v_rig IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Rig no encontrado');
  END IF;

  -- Contar cuántos hay
  SELECT COUNT(*) INTO v_count FROM rig_boosts WHERE player_rig_id = p_rig_id;

  IF v_count = 0 THEN
    RETURN json_build_object('success', false, 'error', 'No hay boosts instalados');
  END IF;

  -- Eliminar todos
  DELETE FROM rig_boosts WHERE player_rig_id = p_rig_id;

  -- Marcar el rig como modificado
  UPDATE player_rigs SET last_modified_at = NOW() WHERE id = p_rig_id;

  RETURN json_build_object(
    'success', true,
    'message', 'Todos los boosts destruidos',
    'destroyed_count', v_count
  );
END;
$$;

GRANT EXECUTE ON FUNCTION remove_cooling_from_rig TO authenticated;
GRANT EXECUTE ON FUNCTION remove_boost_from_rig TO authenticated;
GRANT EXECUTE ON FUNCTION remove_all_cooling_from_rig TO authenticated;
GRANT EXECUTE ON FUNCTION remove_all_boosts_from_rig TO authenticated;

-- =====================================================
-- PITY TIMER SYSTEM - Mining Time Bonus
-- =====================================================
-- Garantiza mínimo de RON por mes para usuarios que minan 24/7:
-- - Free users: 100 RON/mes
-- - Premium users: 500 RON/mes
-- =====================================================

-- Procesar bonus de tiempo de minado (llamado cada tick desde game_tick)
-- El pity reward es proporcional al hashrate efectivo del jugador
-- IMPORTANTE: El reward es en CRYPTO (₿), siempre menor al bloque normal
-- Los pity blocks ahora se registran como bloques reales en la blockchain
DROP FUNCTION IF EXISTS process_mining_time_bonus() CASCADE;
CREATE OR REPLACE FUNCTION process_mining_time_bonus()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_rig RECORD;
  v_player_hashrates RECORD;
  v_bonus_rate DECIMAL;
  -- Threshold para pity blocks
  -- Cálculo: hashrate × rate × 1440 min / threshold = bloques/día
  -- Free:    1000 × 0.00000926 × 1440 / 0.1667 = 80 bloques/día
  -- Premium: 1000 × 0.00001736 × 1440 / 0.1667 = 150 bloques/día
  v_pity_threshold DECIMAL := 0.1667;
  v_pity_blocks_created INT := 0;
  v_total_bonus_distributed DECIMAL := 0;
  v_is_premium BOOLEAN;
  v_effective_hashrate DECIMAL;
  v_pity_reward DECIMAL;
  v_current_block_reward DECIMAL;
  v_current_height INT;
  v_hashrate_ratio DECIMAL;
  v_max_pity_percent DECIMAL := 0.5;  -- Máximo 50% del bloque normal
  -- Rate por hashrate por tick para acumulación
  -- Más hashrate = acumula más rápido
  v_free_rate_per_hash DECIMAL := 0.00000926;
  v_premium_rate_per_hash DECIMAL := 0.00001736;
  -- Para crear bloque real
  v_pity_block blocks%ROWTYPE;
  v_network_difficulty DECIMAL;
  v_network_hashrate DECIMAL;
BEGIN
  -- Obtener stats de la red para crear bloques
  SELECT difficulty, hashrate INTO v_network_difficulty, v_network_hashrate
  FROM network_stats WHERE id = 'current';

  -- Obtener el reward actual de un bloque normal
  SELECT COALESCE(MAX(height), 0) INTO v_current_height FROM blocks;
  v_current_block_reward := calculate_block_reward(v_current_height + 1);
  -- Calcular hashrate efectivo por jugador (suma de todos sus rigs activos)
  FOR v_player_hashrates IN
    WITH player_effective_hashrates AS (
      SELECT
        p.id as player_id,
        p.premium_until,
        SUM(
          r.hashrate *
          GREATEST(0.1, pr.condition / 100.0) *  -- Condition penalty
          CASE
            WHEN p.reputation_score >= 80 THEN 1 + (p.reputation_score - 80) * 0.01
            WHEN p.reputation_score < 50 THEN 0.5 + (p.reputation_score / 100.0)
            ELSE 1.0
          END *  -- Reputation multiplier
          CASE
            WHEN pr.temperature > 50 THEN GREATEST(0.3, 1 - ((pr.temperature - 50) * 0.014))
            ELSE 1.0
          END *  -- Temperature penalty
          COALESCE((get_active_boost_multipliers(p.id)->>'hashrate')::NUMERIC, 1.0)  -- Boost multiplier
        ) as total_effective_hashrate
      FROM players p
      JOIN player_rigs pr ON pr.player_id = p.id
      JOIN rigs r ON r.id = pr.rig_id
      WHERE pr.is_active = true
        AND p.energy > 0
        AND p.internet > 0
        AND (p.is_online = true OR rig_has_autonomous_boost(pr.id))
      GROUP BY p.id, p.premium_until
    )
    SELECT * FROM player_effective_hashrates WHERE total_effective_hashrate > 0
  LOOP
    -- Determinar si es premium
    v_is_premium := v_player_hashrates.premium_until IS NOT NULL AND v_player_hashrates.premium_until > NOW();
    v_effective_hashrate := v_player_hashrates.total_effective_hashrate;

    -- Calcular rate basado en hashrate
    -- Más hashrate = más rápido acumula pity
    IF v_is_premium THEN
      v_bonus_rate := v_effective_hashrate * v_premium_rate_per_hash;
    ELSE
      v_bonus_rate := v_effective_hashrate * v_free_rate_per_hash;
    END IF;

    -- Acumular bonus
    UPDATE players
    SET mining_bonus_accumulated = COALESCE(mining_bonus_accumulated, 0) + v_bonus_rate
    WHERE id = v_player_hashrates.player_id;

    v_total_bonus_distributed := v_total_bonus_distributed + v_bonus_rate;

    -- Verificar si alcanzó el threshold para pity block
    IF (SELECT mining_bonus_accumulated FROM players WHERE id = v_player_hashrates.player_id) >= v_pity_threshold THEN
      -- Calcular reward proporcional al hashrate, siempre menor al bloque normal
      -- Fórmula: block_reward * min(max_percent, hashrate/10000)
      -- Ejemplo con block_reward=100:
      --   500 hashrate  → 100 * min(0.5, 0.05)  = 5 ₿
      --   1000 hashrate → 100 * min(0.5, 0.1)   = 10 ₿
      --   2500 hashrate → 100 * min(0.5, 0.25)  = 25 ₿
      --   5000 hashrate → 100 * min(0.5, 0.5)   = 50 ₿ (max)
      --   10000 hashrate→ 100 * min(0.5, 1.0)   = 50 ₿ (capped)
      v_hashrate_ratio := LEAST(v_max_pity_percent, v_effective_hashrate / 10000.0);
      v_pity_reward := GREATEST(1.0, v_current_block_reward * v_hashrate_ratio);

      -- Premium bonus (+50% al pity reward también)
      IF v_is_premium THEN
        v_pity_reward := v_pity_reward * 1.5;
      END IF;

      -- Crear bloque real en la blockchain (igual que bloques normales)
      v_pity_block := create_new_block(
        v_player_hashrates.player_id,
        COALESCE(v_network_difficulty, 1000),
        COALESCE(v_network_hashrate, 0),
        v_pity_reward,
        v_is_premium
      );

      -- Crear entrada en pending_blocks vinculada al bloque real
      INSERT INTO pending_blocks (
        block_id,
        player_id,
        reward,
        is_premium,
        is_pity,
        created_at
      ) VALUES (
        v_pity_block.id,
        v_player_hashrates.player_id,
        v_pity_reward,
        v_is_premium,
        TRUE,
        NOW()
      );

      -- Restar el threshold del acumulador
      UPDATE players
      SET mining_bonus_accumulated = mining_bonus_accumulated - v_pity_threshold
      WHERE id = v_player_hashrates.player_id;

      v_pity_blocks_created := v_pity_blocks_created + 1;
    END IF;
  END LOOP;

  RETURN json_build_object(
    'success', true,
    'pityBlocksCreated', v_pity_blocks_created,
    'totalBonusDistributed', ROUND(v_total_bonus_distributed, 6)
  );
END;
$$;

-- Obtener estadísticas de pity timer de un jugador
DROP FUNCTION IF EXISTS get_player_pity_stats(UUID) CASCADE;
CREATE OR REPLACE FUNCTION get_player_pity_stats(p_player_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_accumulated DECIMAL;
  v_pending_pity_count INT;
  v_total_pity_claimed DECIMAL;
  v_is_premium BOOLEAN;
  v_rate_per_hour DECIMAL;
  v_hours_to_next DECIMAL;
BEGIN
  -- Obtener datos del jugador
  SELECT
    COALESCE(mining_bonus_accumulated, 0),
    premium_until IS NOT NULL AND premium_until > NOW()
  INTO v_accumulated, v_is_premium
  FROM players WHERE id = p_player_id;

  -- Calcular rate por hora (basado en 1000 hashrate)
  -- Free: 80 bloques/día, Premium: 150 bloques/día
  IF v_is_premium THEN
    v_rate_per_hour := 0.01736 * 60;  -- ~1.04/hora
  ELSE
    v_rate_per_hour := 0.00926 * 60;  -- ~0.56/hora
  END IF;

  -- Calcular horas hasta próximo pity block
  v_hours_to_next := (5.0 - v_accumulated) / v_rate_per_hour;
  IF v_hours_to_next < 0 THEN v_hours_to_next := 0; END IF;

  -- Contar pity blocks pendientes
  SELECT COUNT(*) INTO v_pending_pity_count
  FROM pending_blocks
  WHERE player_id = p_player_id AND is_pity = true AND claimed = false;

  -- Total RON reclamado de pity blocks
  SELECT COALESCE(SUM(reward), 0) INTO v_total_pity_claimed
  FROM pending_blocks
  WHERE player_id = p_player_id AND is_pity = true AND claimed = true;

  RETURN json_build_object(
    'success', true,
    'accumulated', ROUND(v_accumulated, 4),
    'threshold', 5.0,
    'progressPercent', ROUND((v_accumulated / 5.0) * 100, 1),
    'hoursToNextPityBlock', ROUND(v_hours_to_next, 1),
    'pendingPityBlocks', v_pending_pity_count,
    'totalPityClaimed', ROUND(v_total_pity_claimed, 2),
    'isPremium', v_is_premium,
    'ratePerHour', ROUND(v_rate_per_hour, 4),
    'guaranteedPerMonth', CASE WHEN v_is_premium THEN 4500 ELSE 2400 END
  );
END;
$$;

GRANT EXECUTE ON FUNCTION get_player_pity_stats TO authenticated;

-- =====================================================
-- CLAIM ALL BLOCKS WITH RON (Instant Claim)
-- Permite reclamar todos los bloques pendientes pagando RON
-- Costo: 0.01 RON por bloque
-- =====================================================

DROP FUNCTION IF EXISTS claim_all_blocks_with_ron(UUID) CASCADE;
CREATE OR REPLACE FUNCTION claim_all_blocks_with_ron(p_player_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player players%ROWTYPE;
  v_pending_count INTEGER;
  v_total_reward DECIMAL := 0;
  v_ron_cost_per_block DECIMAL := 0.001;
  v_total_ron_cost DECIMAL;
  v_pending RECORD;
BEGIN
  -- Verificar jugador
  SELECT * INTO v_player FROM players WHERE id = p_player_id;
  IF v_player IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Jugador no encontrado');
  END IF;

  -- Contar bloques pendientes y calcular reward total
  SELECT COUNT(*), COALESCE(SUM(reward), 0)
  INTO v_pending_count, v_total_reward
  FROM pending_blocks
  WHERE player_id = p_player_id AND claimed = false;

  -- Verificar que hay bloques pendientes
  IF v_pending_count = 0 THEN
    RETURN json_build_object('success', false, 'error', 'No hay bloques pendientes');
  END IF;

  -- Calcular costo total en RON
  v_total_ron_cost := v_pending_count * v_ron_cost_per_block;

  -- Verificar balance de RON
  IF COALESCE(v_player.ron_balance, 0) < v_total_ron_cost THEN
    RETURN json_build_object(
      'success', false,
      'error', 'RON insuficiente',
      'required', v_total_ron_cost,
      'current', COALESCE(v_player.ron_balance, 0),
      'blocks_count', v_pending_count,
      'cost_per_block', v_ron_cost_per_block
    );
  END IF;

  -- Descontar RON
  UPDATE players
  SET ron_balance = ron_balance - v_total_ron_cost
  WHERE id = p_player_id;

  -- Marcar todos los bloques como reclamados
  UPDATE pending_blocks
  SET claimed = true, claimed_at = NOW()
  WHERE player_id = p_player_id AND claimed = false;

  -- Dar crypto al jugador
  UPDATE players
  SET crypto_balance = crypto_balance + v_total_reward,
      total_crypto_earned = COALESCE(total_crypto_earned, 0) + v_total_reward
  WHERE id = p_player_id;

  -- Registrar transacción de RON gastado
  INSERT INTO transactions (player_id, type, amount, currency, description)
  VALUES (p_player_id, 'instant_claim_fee', -v_total_ron_cost, 'ron',
          'Claim instantáneo de ' || v_pending_count || ' bloques');

  -- Registrar transacción de crypto recibido
  INSERT INTO transactions (player_id, type, amount, currency, description)
  VALUES (p_player_id, 'block_claim_instant', v_total_reward, 'crypto',
          'Reclamados ' || v_pending_count || ' bloques (instant)');

  RETURN json_build_object(
    'success', true,
    'blocks_claimed', v_pending_count,
    'total_reward', v_total_reward,
    'ron_spent', v_total_ron_cost,
    'cost_per_block', v_ron_cost_per_block
  );
END;
$$;

GRANT EXECUTE ON FUNCTION claim_all_blocks_with_ron TO authenticated;

-- =====================================================
-- GRANTS PARA FUNCIONES
-- =====================================================

GRANT EXECUTE ON FUNCTION get_referral_info TO authenticated;
GRANT EXECUTE ON FUNCTION apply_referral_code TO authenticated;
GRANT EXECUTE ON FUNCTION upgrade_rig TO authenticated;
GRANT EXECUTE ON FUNCTION get_pending_blocks TO authenticated;
GRANT EXECUTE ON FUNCTION get_pending_blocks_count TO authenticated;
GRANT EXECUTE ON FUNCTION claim_block TO authenticated;
GRANT EXECUTE ON FUNCTION claim_all_blocks TO authenticated;
GRANT EXECUTE ON FUNCTION claim_all_blocks_with_ron TO authenticated;
GRANT EXECUTE ON FUNCTION get_mining_estimate TO authenticated;
