-- =====================================================
-- BLOCK LORDS - TODAS LAS FUNCIONES DEL JUEGO
-- =====================================================
-- Archivo consolidado con todas las funciones
-- Ejecutar después del schema inicial (001_initial_schema.sql)
-- =====================================================

-- Borrar TODAS las funciones existentes del schema public
DO $$
DECLARE
  func_record RECORD;
BEGIN
  FOR func_record IN
    SELECT p.oid::regprocedure::text AS func_signature
    FROM pg_proc p
    JOIN pg_namespace ns ON p.pronamespace = ns.oid
    WHERE ns.nspname = 'public'
    AND p.prokind = 'f'
  LOOP
    EXECUTE 'DROP FUNCTION IF EXISTS ' || func_record.func_signature || ' CASCADE';
  END LOOP;
END $$;

-- Agregar columna blocks_mined si no existe
ALTER TABLE players ADD COLUMN IF NOT EXISTS blocks_mined INTEGER DEFAULT 0;

-- Agregar columna role para admin (default 'user')
ALTER TABLE players ADD COLUMN IF NOT EXISTS role TEXT DEFAULT 'user';

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

-- Fix: corregir jugadores no-premium con max_energy/max_internet incorrecto
UPDATE players SET max_energy = 300, max_internet = 300
WHERE (max_energy != 300 OR max_internet != 300)
  AND (premium_until IS NULL OR premium_until <= NOW());

-- Agregar columnas para degradación de rigs
ALTER TABLE player_rigs ADD COLUMN IF NOT EXISTS max_condition NUMERIC DEFAULT 100;
ALTER TABLE player_rigs ADD COLUMN IF NOT EXISTS times_repaired INTEGER DEFAULT 0;

-- Permitir múltiples rigs del mismo tipo por jugador (eliminar constraint único)
ALTER TABLE player_rigs DROP CONSTRAINT IF EXISTS player_rigs_player_id_rig_id_key;

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

-- Función ligera para actualizar heartbeat del jugador
-- Se llama periódicamente para mantener al jugador como "online"
-- y prevenir desconexión cuando el tab pierde foco
CREATE OR REPLACE FUNCTION update_player_heartbeat(p_player_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE players
  SET is_online = true,
      last_seen = NOW()
  WHERE id = p_player_id;

  RETURN FOUND;
END;
$$;

GRANT EXECUTE ON FUNCTION update_player_heartbeat TO authenticated;

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
  INSERT INTO players (id, email, username, gamecoin_balance, crypto_balance, energy, internet, max_energy, max_internet, reputation_score, region)
  VALUES (p_user_id, p_email, p_username, 1000, 0, 300, 300, 300, 300, 50, 'global')
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
             COALESCE(uc_h.hashrate_bonus, 0) as hashrate_bonus,
             COALESCE(uc_e.efficiency_bonus, 0) as efficiency_bonus,
             COALESCE(uc_t.thermal_bonus, 0) as thermal_bonus,
             json_build_object(
               'id', r.id, 'name', r.name, 'description', r.description,
               'hashrate', r.hashrate, 'power_consumption', r.power_consumption,
               'internet_consumption', r.internet_consumption,
               'tier', r.tier, 'repair_cost', r.repair_cost,
               'base_price', r.base_price, 'currency', r.currency,
               'max_upgrade_level', COALESCE(r.max_upgrade_level, 3)
             ) as rig
      FROM player_rigs pr
      JOIN rigs r ON r.id = pr.rig_id
      LEFT JOIN upgrade_costs uc_h ON uc_h.level = COALESCE(pr.hashrate_level, 1)
      LEFT JOIN upgrade_costs uc_e ON uc_e.level = COALESCE(pr.efficiency_level, 1)
      LEFT JOIN upgrade_costs uc_t ON uc_t.level = COALESCE(pr.thermal_level, 1)
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
-- Cada reparación restaura menos condición:
--   1ra: +90% (max_condition = 90%)
--   2da: +70% (max_condition = 70%)
--   3ra: +50% (max_condition = 50%)
CREATE OR REPLACE FUNCTION repair_rig(p_player_id UUID, p_rig_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_rig RECORD;
  v_player players%ROWTYPE;
  v_repair_cost NUMERIC;
  v_price_in_gc NUMERIC;
  v_times_repaired INTEGER;
  v_repair_bonus NUMERIC;
  v_new_max_condition NUMERIC;
  v_new_condition NUMERIC;
  v_condition_restored NUMERIC;
BEGIN
  SELECT pr.*, r.base_price as base_repair_cost, r.name as rig_name, r.currency as rig_currency
  INTO v_rig
  FROM player_rigs pr
  JOIN rigs r ON r.id = pr.rig_id
  WHERE pr.id = p_rig_id AND pr.player_id = p_player_id;

  IF v_rig IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Rig no encontrado');
  END IF;

  v_times_repaired := COALESCE(v_rig.times_repaired, 0);

  -- Verificar límite de reparaciones (máximo 3)
  IF v_times_repaired >= 3 THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Máximo de reparaciones alcanzado (3/3)',
      'times_repaired', v_times_repaired
    );
  END IF;

  -- Determinar bonus de reparación según número de reparaciones
  -- 1ra: +90%, 2da: +70%, 3ra: +50%
  CASE v_times_repaired
    WHEN 0 THEN
      v_repair_bonus := 90;
      v_new_max_condition := 90;
    WHEN 1 THEN
      v_repair_bonus := 70;
      v_new_max_condition := 70;
    WHEN 2 THEN
      v_repair_bonus := 50;
      v_new_max_condition := 50;
    ELSE
      v_repair_bonus := 0;
      v_new_max_condition := v_rig.max_condition;
  END CASE;

  -- Calcular nueva condición: condición actual + bonus, tope SIEMPRE en 100%
  -- Ejemplo: condición 70% + bonus 70% = 140% -> tope en 100% = 100%
  v_new_condition := LEAST(v_rig.condition + v_repair_bonus, 100);
  v_condition_restored := v_new_condition - v_rig.condition;

  -- Convertir precio del rig a GameCoin según su moneda
  -- Tasas: 1 Crypto = 50 GC, 1 RON = 5,000,000 GC
  CASE COALESCE(v_rig.rig_currency, 'gamecoin')
    WHEN 'crypto' THEN
      v_price_in_gc := v_rig.base_repair_cost * 50;
    WHEN 'ron' THEN
      v_price_in_gc := v_rig.base_repair_cost * 5000000;
    ELSE
      v_price_in_gc := v_rig.base_repair_cost;
  END CASE;

  -- Calcular costo basado en la condición restaurada (30% del precio en GC)
  -- Descuento del 70% para que no sea tan caro
  v_repair_cost := (v_condition_restored / 100.0) * v_price_in_gc * 0.30;

  SELECT * INTO v_player FROM players WHERE id = p_player_id;

  -- Siempre cobrar en GameCoin
  IF v_player.gamecoin_balance < v_repair_cost THEN
    RETURN json_build_object('success', false, 'error', 'GameCoin insuficiente', 'cost', v_repair_cost);
  END IF;
  UPDATE players SET gamecoin_balance = gamecoin_balance - v_repair_cost WHERE id = p_player_id;

  -- Aplicar reparación al rig
  UPDATE player_rigs
  SET condition = v_new_condition,
      max_condition = v_new_max_condition,
      times_repaired = v_times_repaired + 1,
      last_modified_at = NOW()
  WHERE id = p_rig_id;

  INSERT INTO transactions (player_id, type, amount, currency, description)
  VALUES (p_player_id, 'rig_repair', -v_repair_cost, 'gamecoin',
          'Reparación #' || (v_times_repaired + 1) || ' de ' || v_rig.rig_name ||
          CASE WHEN v_condition_restored > 0 THEN ' (+' || v_condition_restored || '%)' ELSE ' (nuevo máx: ' || v_new_max_condition || '%)' END);

  -- Actualizar misión de reparar rig
  PERFORM update_mission_progress(p_player_id, 'repair_rig', 1);

  RETURN json_build_object(
    'success', true,
    'cost', v_repair_cost,
    'old_condition', v_rig.condition,
    'new_condition', v_new_condition,
    'new_max_condition', v_new_max_condition,
    'times_repaired', v_times_repaired + 1,
    'condition_restored', v_condition_restored,
    'repair_bonus', v_repair_bonus
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
  -- Upgrade bonuses
  v_efficiency_bonus NUMERIC;
  v_thermal_bonus NUMERIC;
  -- Hashrate calculation variables
  v_temp_penalty NUMERIC;
  v_condition_penalty NUMERIC;
  v_hashrate_ratio NUMERIC;
  v_active_rig_count INT;
BEGIN
  -- Procesar jugadores que están ONLINE o tienen rigs con autonomous mining boost
  FOR v_player IN
    SELECT p.id, p.energy, p.internet, is_player_premium(p.id) as is_premium
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
      SELECT pr.id, pr.temperature, pr.condition, r.power_consumption, r.internet_consumption, r.hashrate,
             COALESCE(pr.efficiency_level, 1) as efficiency_level,
             COALESCE(pr.thermal_level, 1) as thermal_level
      FROM player_rigs pr
      JOIN rigs r ON r.id = pr.rig_id
      WHERE pr.player_id = v_player.id AND pr.is_active = true
    LOOP
      -- Obtener bonus de eficiencia del nivel de upgrade
      SELECT COALESCE(efficiency_bonus, 0) INTO v_efficiency_bonus
      FROM upgrade_costs WHERE level = v_rig.efficiency_level;
      IF v_efficiency_bonus IS NULL THEN v_efficiency_bonus := 0; END IF;

      -- Obtener bonus térmico del nivel de upgrade
      SELECT COALESCE(thermal_bonus, 0) INTO v_thermal_bonus
      FROM upgrade_costs WHERE level = v_rig.thermal_level;
      IF v_thermal_bonus IS NULL THEN v_thermal_bonus := 0; END IF;
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
      -- Aplicar bonus de eficiencia del upgrade (reduce consumo)
      v_total_power := v_total_power +
        ((v_rig.power_consumption * (1 + GREATEST(0, (v_rig.temperature - 40)) * 0.0083)) +
        v_rig_cooling_energy) * v_energy_mult * (1 - v_efficiency_bonus / 100.0);

      -- Aplicar multiplicador de boost de bandwidth_optimizer (por rig)
      -- Aplicar bonus de eficiencia del upgrade (reduce consumo)
      v_total_internet := v_total_internet + (v_rig.internet_consumption * v_internet_mult * (1 - v_efficiency_bonus / 100.0));

      -- Calcular hashrate efectivo para determinar generación de calor
      -- Solo genera calor si está minando efectivamente

      -- Penalización por temperatura (misma lógica que generate_shares_tick)
      IF v_rig.temperature <= 50 THEN
        v_temp_penalty := 1;
      ELSE
        v_temp_penalty := GREATEST(0.3, 1 - ((v_rig.temperature - 50) * 0.014));
      END IF;

      -- Penalización por condición
      v_condition_penalty := v_rig.condition / 100.0;

      -- Ratio de trabajo real (0 a 1): cuánto está trabajando el rig realmente
      v_hashrate_ratio := v_temp_penalty * v_condition_penalty;

      -- Calcular aumento de temperatura basado en hashrate efectivo
      -- Solo se calienta si está trabajando (hashrate_ratio > 0)
      -- Sin cooling: temperatura sube rápidamente
      -- Con cooling apropiado: temperatura se estabiliza
      -- Aplicar multiplicador de boost de coolant_injection
      -- Aplicar bonus térmico del upgrade (reduce generación de calor)
      IF v_rig_cooling_power <= 0 THEN
        -- Sin cooling: calentamiento significativo (max 15°C por tick)
        -- Solo si está trabajando (v_hashrate_ratio > 0)
        v_temp_increase := LEAST(v_rig.power_consumption * v_hashrate_ratio * 1.0, 15) * v_temp_mult;
        -- Reducción directa por upgrade térmico (en °C)
        v_temp_increase := GREATEST(0, v_temp_increase - v_thermal_bonus);
      ELSE
        -- Con cooling: calentamiento reducido por poder de refrigeración
        v_temp_increase := v_rig.power_consumption * v_hashrate_ratio * 0.8;
        -- Reducción adicional por upgrade térmico (en °C)
        v_temp_increase := GREATEST(0, v_temp_increase - v_rig_cooling_power - v_thermal_bonus) * v_temp_mult;
      END IF;

      -- Calcular nueva temperatura
      v_new_temp := v_rig.temperature + v_temp_increase;

      -- Enfriamiento pasivo
      IF v_new_temp > v_ambient_temp THEN
        IF v_rig_cooling_power > 0 THEN
          -- Con cooling: enfriamiento basado en poder de refrigeración
          -- Premium: 25% más rápido (multiplicador 1.25)
          v_new_temp := v_new_temp - (v_rig_cooling_power * 0.15 * CASE WHEN v_player.is_premium THEN 1.25 ELSE 1.0 END);
        ELSE
          -- Sin cooling pero sin trabajar (hashrate_ratio bajo): enfriamiento natural
          -- Si no está minando efectivamente, se enfría lentamente hacia 0°C
          IF v_hashrate_ratio < 0.5 THEN
            v_new_temp := v_new_temp - (2.0 * (1 - v_hashrate_ratio));  -- hasta -2°C por tick
          END IF;
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

      -- Premium: -25% desgaste (multiplicador 0.75)
      IF v_player.is_premium THEN
        v_deterioration := v_deterioration * 0.75;
      END IF;

      -- Aplicar deterioro y actualizar temperatura
      -- El bot (BalanceBot) nunca pierde condición
      UPDATE player_rigs
      SET temperature = v_new_temp,
          condition = CASE
            WHEN v_player.id = '00000000-0000-0000-0000-000000000001' THEN 100  -- Bot siempre al 100%
            ELSE GREATEST(0, condition - v_deterioration)
          END
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

    -- Actualizar misiones de tiempo activo con rigs y manejar streak
    SELECT COUNT(*) INTO v_active_rig_count
    FROM player_rigs WHERE player_id = v_player.id AND is_active = true;

    IF v_active_rig_count > 0 THEN
      -- rig_active_time: 0.5 minutos (30 segundos) por cada tick con al menos 1 rig activo
      PERFORM update_mission_progress(v_player.id, 'rig_active_time', 0.5);

      -- multi_rig: si tiene 2+ rigs activos simultáneamente
      IF v_active_rig_count >= 2 THEN
        PERFORM update_mission_progress(v_player.id, 'multi_rig', 1);
        -- multi_rig_time: minutos con múltiples rigs activos (0.5 = 30 segundos)
        PERFORM update_mission_progress(v_player.id, 'multi_rig_time', 0.5);
      END IF;
    END IF;

    -- Calcular nuevo nivel de energía e internet
    -- Ambos bajan proporcionalmente a su consumo real (mismo multiplicador)
    -- Los multiplicadores de boost ya fueron aplicados por rig en el loop anterior
    -- Multiplicador 0.05 = tick cada 30 segundos (antes 0.1 para ticks de 60 segundos)
    -- Premium: -20% consumo (multiplicador 0.8)
    -- El bot (BalanceBot) nunca consume recursos
    IF v_player.id = '00000000-0000-0000-0000-000000000001' THEN
      -- Bot: mantener recursos infinitos (999.99 es el máximo para DECIMAL(5,2))
      v_new_energy := 999.99;
      v_new_internet := 999.99;
    ELSE
      -- Jugadores normales: consumir recursos
      v_new_energy := GREATEST(0, v_player.energy - (v_total_power * 0.05 * CASE WHEN v_player.is_premium THEN 0.8 ELSE 1.0 END));
      v_new_internet := GREATEST(0, v_player.internet - (v_total_internet * 0.05 * CASE WHEN v_player.is_premium THEN 0.8 ELSE 1.0 END));
    END IF;

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

-- =====================================================
-- MINING COOLDOWN
-- Si un jugador gana más de X bloques en menos de Y minutos,
-- entra en cooldown
-- Parámetros configurables:
--   p_min_threshold: mínimo de bloques permitidos (default: 10)
--   p_max_threshold: máximo de bloques permitidos (default: 20)
--   p_time_window_minutes: ventana de tiempo en minutos (default: 2)
-- El umbral es consistente por jugador (basado en hash del player_id)
-- =====================================================
CREATE OR REPLACE FUNCTION is_player_in_mining_cooldown(
  p_player_id UUID,
  p_min_threshold INTEGER DEFAULT 10,
  p_max_threshold INTEGER DEFAULT 20,
  p_time_window_minutes INTEGER DEFAULT 2
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_recent_blocks INTEGER;
  v_time_window INTERVAL;
  v_threshold INTEGER;
  v_hash_value INTEGER;
BEGIN
  -- Calcular umbral consistente por jugador usando hash del UUID
  -- Esto genera un número entre min y max que es siempre el mismo para cada jugador
  v_hash_value := abs(('x' || substr(p_player_id::TEXT, 1, 8))::BIT(32)::INTEGER);
  v_threshold := p_min_threshold + (v_hash_value % (p_max_threshold - p_min_threshold + 1));

  -- Convertir minutos a intervalo
  v_time_window := (p_time_window_minutes || ' minutes')::INTERVAL;

  -- Contar bloques ganados por este jugador en la ventana de tiempo
  SELECT COUNT(*) INTO v_recent_blocks
  FROM blocks
  WHERE miner_id = p_player_id
    AND created_at >= NOW() - v_time_window;

  -- Si ganó más de X bloques en la ventana, está en cooldown
  RETURN v_recent_blocks > v_threshold;
END;
$$;

-- Tick de minería (selección de ganador)
-- =====================================================
-- NOTA: La función process_mining_tick() fue eliminada.
-- El sistema ahora usa exclusivamente el sistema de shares
-- para distribución de recompensas de bloques compartidos.
-- =====================================================

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
-- Ajusta cada 1000 bloques basándose en tiempo real vs esperado
-- TAMBIÉN ajusta si pasa 1 hora sin recalcular (evita dificultad estancada)
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
  v_last_adjustment_time TIMESTAMPTZ;
  v_latest_block_height INTEGER;
  v_adjustment_period INTEGER := 1000;      -- Ajustar cada 1000 bloques
  v_target_block_time INTEGER := 600;       -- 10 minutos en segundos
  v_max_change NUMERIC := 0.25;             -- ±25% máximo por ajuste
  v_min_difficulty NUMERIC := 1000;         -- Dificultad mínima
  v_max_difficulty NUMERIC := 1000000;      -- Dificultad máxima
  v_time_since_adjustment NUMERIC;          -- Tiempo desde último ajuste
  v_time_based_adjustment BOOLEAN := FALSE; -- Flag para ajuste por tiempo
  v_time_expected NUMERIC;
  v_time_actual NUMERIC;
  v_first_block_time TIMESTAMPTZ;
  v_last_block_time TIMESTAMPTZ;
  v_adjustment_ratio NUMERIC;
  v_new_difficulty NUMERIC;
  v_blocks_in_period INTEGER;
BEGIN
  -- Obtener estado actual de la red
  SELECT difficulty, hashrate, COALESCE(last_adjustment_block, 0), last_difficulty_adjustment
  INTO v_current_difficulty, v_current_hashrate, v_last_adjustment_block, v_last_adjustment_time
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

  -- Calcular tiempo desde último ajuste (en segundos)
  IF v_last_adjustment_time IS NOT NULL THEN
    v_time_since_adjustment := EXTRACT(EPOCH FROM (NOW() - v_last_adjustment_time));
  ELSE
    v_time_since_adjustment := 0;
  END IF;

  -- Verificar si debemos hacer ajuste por tiempo (1 hora = 3600 segundos sin ajuste)
  -- Esto evita que la dificultad quede estancada cuando no hay suficiente actividad de minería
  IF v_blocks_in_period < v_adjustment_period THEN
    -- Si pasó más de 1 hora sin ajuste, hacer ajuste basado en tiempo
    IF v_time_since_adjustment >= 3600 THEN
      v_time_based_adjustment := TRUE;
      -- Continuar con el ajuste basado en tiempo
    ELSE
      RETURN json_build_object(
        'adjusted', false,
        'reason', 'Waiting for more blocks',
        'blocks_since_adjustment', v_blocks_in_period,
        'blocks_needed', v_adjustment_period,
        'blocks_remaining', v_adjustment_period - v_blocks_in_period,
        'current_difficulty', v_current_difficulty,
        'current_block_height', v_latest_block_height,
        'time_since_last_adjustment_minutes', ROUND(v_time_since_adjustment / 60),
        'next_time_adjustment_minutes', ROUND((3600 - v_time_since_adjustment) / 60)
      );
    END IF;
  END IF;

  -- Lógica diferente si es ajuste por tiempo vs por bloques
  IF v_time_based_adjustment THEN
    -- AJUSTE BASADO EN TIEMPO: Pasó 1+ hora sin suficientes bloques
    -- Usamos el tiempo real transcurrido desde el último ajuste
    v_time_actual := v_time_since_adjustment;

    -- Esperábamos minar v_blocks_in_period bloques en ese tiempo
    -- Pero el tiempo real para esos bloques fue v_time_actual
    -- Lo que esperábamos era v_blocks_in_period * v_target_block_time segundos
    IF v_blocks_in_period > 0 THEN
      v_time_expected := v_blocks_in_period * v_target_block_time;
    ELSE
      -- Si no hubo bloques, esperábamos al menos 1 en v_target_block_time
      -- Pero pasó mucho más tiempo, así que reducir dificultad al máximo
      v_time_expected := v_target_block_time;
    END IF;
  ELSE
    -- AJUSTE NORMAL: Por cantidad de bloques
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
  END IF;

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
    'adjustment_type', CASE WHEN v_time_based_adjustment THEN 'time_based' ELSE 'block_based' END,
    'period_blocks', v_adjustment_period,
    'target_block_time_seconds', v_target_block_time,
    'time_expected_seconds', v_time_expected,
    'time_actual_seconds', ROUND(v_time_actual),
    'avg_block_time_seconds', ROUND(v_time_actual / GREATEST(1, CASE WHEN v_time_based_adjustment THEN v_blocks_in_period ELSE v_adjustment_period - 1 END, 1)),
    'target_vs_actual', CONCAT(ROUND(v_time_expected/60), 'min vs ', ROUND(v_time_actual/60), 'min'),
    'old_difficulty', v_current_difficulty,
    'new_difficulty', v_new_difficulty,
    'change_percent', ROUND((v_adjustment_ratio - 1) * 100, 2),
    'blocks_analyzed', v_blocks_in_period,
    'adjustment_block', v_latest_block_height,
    'network_hashrate', v_current_hashrate,
    'time_based_trigger', v_time_based_adjustment
  );
END;
$$;

-- Game tick principal (ejecutar cada minuto)
-- =====================================================
-- NOTA: La función game_tick() fue eliminada ya que el cron
-- ahora solo llama a game_tick_share_system().
-- El sistema de minería usa exclusivamente shares.
-- =====================================================

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
  PERFORM update_mission_progress(v_buyer_id, 'market_trades_weekly', 1);
  PERFORM update_mission_progress(v_seller_id, 'market_trades_weekly', 1);
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

    -- Mission tracking
    PERFORM update_mission_progress(p_player_id, 'install_cooling', 1);

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

    -- Mission tracking
    PERFORM update_mission_progress(p_player_id, 'install_cooling', 1);

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

  -- Track complete_easy_missions: count easy missions completed today
  IF v_mission.difficulty = 'easy' THEN
    PERFORM update_mission_progress(p_player_id, 'complete_easy_missions', 1);
  END IF;

  RETURN json_build_object(
    'success', true,
    'rewardType', v_mission.reward_type,
    'rewardAmount', v_mission.reward_amount,
    'missionName', v_mission.name
  );
END;
$$;

-- Actualizar estado online del jugador (login/logout)
CREATE OR REPLACE FUNCTION update_online_status(p_player_id UUID, p_is_online BOOLEAN)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE players
  SET is_online = p_is_online,
      last_seen = NOW()
  WHERE id = p_player_id;
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
      max_energy = v_free_max,
      max_internet = v_free_max,
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
    PERFORM update_mission_progress(p_player_id, 'online_time_weekly', 1);

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
    PERFORM update_mission_progress(p_player_id, 'online_time_weekly', v_minutes_since_last);

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

  -- Mission tracking
  PERFORM update_mission_progress(p_player_id, 'use_boost', 1);

  RETURN json_build_object(
    'success', true,
    'boost', row_to_json(v_boost),
    'expires_at', v_expires_at,
    'message', 'Boost activated!'
  );
END;
$$;

-- Obtener multiplicadores de boosts activos (para game tick)
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

  -- Mission tracking
  PERFORM update_mission_progress(p_player_id, 'use_boost', 1);

  RETURN json_build_object(
    'success', true,
    'boost', row_to_json(v_boost),
    'remaining_seconds', v_remaining_seconds,
    'message', 'Boost aplicado al rig'
  );
END;
$$;

-- Obtener boosts instalados en un rig específico
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
    max_energy = 300,
    max_internet = 300,
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
  type TEXT NOT NULL DEFAULT 'info' CHECK (type IN ('info', 'warning', 'success', 'error', 'maintenance', 'update')),
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

-- Actualizar constraint para incluir 'update' (para bases de datos existentes)
DO $$
BEGIN
  -- Eliminar constraint viejo si existe
  ALTER TABLE announcements DROP CONSTRAINT IF EXISTS announcements_type_check;

  -- Agregar constraint actualizado con 'update' incluido
  ALTER TABLE announcements ADD CONSTRAINT announcements_type_check
    CHECK (type IN ('info', 'warning', 'success', 'error', 'maintenance', 'update'));
EXCEPTION
  WHEN OTHERS THEN
    -- Ignorar si hay errores (constraint ya correcto)
    NULL;
END $$;

-- Función para obtener anuncios activos
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

-- Función para obtener TODOS los anuncios (admin)
CREATE OR REPLACE FUNCTION admin_get_all_announcements()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_role TEXT;
BEGIN
  -- Verificar que el usuario sea admin
  SELECT role INTO v_player_role
  FROM players
  WHERE id = auth.uid();

  IF v_player_role IS NULL OR v_player_role != 'admin' THEN
    RAISE EXCEPTION 'Unauthorized: Admin access required';
  END IF;

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
        is_active,
        priority,
        starts_at,
        ends_at,
        created_at,
        updated_at
      FROM announcements
      ORDER BY created_at DESC
    ) t
  );
END;
$$;

-- Función para crear anuncio (admin)
CREATE OR REPLACE FUNCTION admin_create_announcement(
  p_message TEXT,
  p_message_es TEXT DEFAULT NULL,
  p_type TEXT DEFAULT 'info',
  p_icon TEXT DEFAULT '📢',
  p_link_url TEXT DEFAULT NULL,
  p_link_text TEXT DEFAULT NULL,
  p_is_active BOOLEAN DEFAULT true,
  p_priority INTEGER DEFAULT 0,
  p_starts_at TIMESTAMPTZ DEFAULT NOW(),
  p_ends_at TIMESTAMPTZ DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_role TEXT;
  v_announcement_id UUID;
BEGIN
  -- Verificar que el usuario sea admin
  SELECT role INTO v_player_role
  FROM players
  WHERE id = auth.uid();

  IF v_player_role IS NULL OR v_player_role != 'admin' THEN
    RAISE EXCEPTION 'Unauthorized: Admin access required';
  END IF;

  -- Validar type
  IF p_type NOT IN ('info', 'warning', 'success', 'error', 'maintenance') THEN
    RAISE EXCEPTION 'Invalid announcement type';
  END IF;

  -- Crear anuncio
  INSERT INTO announcements (
    message,
    message_es,
    type,
    icon,
    link_url,
    link_text,
    is_active,
    priority,
    starts_at,
    ends_at
  ) VALUES (
    p_message,
    p_message_es,
    p_type,
    p_icon,
    p_link_url,
    p_link_text,
    p_is_active,
    p_priority,
    p_starts_at,
    p_ends_at
  ) RETURNING id INTO v_announcement_id;

  RETURN json_build_object(
    'success', true,
    'announcement_id', v_announcement_id
  );
END;
$$;

-- Función para actualizar anuncio (admin)
CREATE OR REPLACE FUNCTION admin_update_announcement(
  p_announcement_id UUID,
  p_message TEXT DEFAULT NULL,
  p_message_es TEXT DEFAULT NULL,
  p_type TEXT DEFAULT NULL,
  p_icon TEXT DEFAULT NULL,
  p_link_url TEXT DEFAULT NULL,
  p_link_text TEXT DEFAULT NULL,
  p_is_active BOOLEAN DEFAULT NULL,
  p_priority INTEGER DEFAULT NULL,
  p_starts_at TIMESTAMPTZ DEFAULT NULL,
  p_ends_at TIMESTAMPTZ DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_role TEXT;
BEGIN
  -- Verificar que el usuario sea admin
  SELECT role INTO v_player_role
  FROM players
  WHERE id = auth.uid();

  IF v_player_role IS NULL OR v_player_role != 'admin' THEN
    RAISE EXCEPTION 'Unauthorized: Admin access required';
  END IF;

  -- Validar type si se proporciona
  IF p_type IS NOT NULL AND p_type NOT IN ('info', 'warning', 'success', 'error', 'maintenance') THEN
    RAISE EXCEPTION 'Invalid announcement type';
  END IF;

  -- Actualizar solo los campos proporcionados
  UPDATE announcements
  SET
    message = COALESCE(p_message, message),
    message_es = CASE WHEN p_message_es IS NOT NULL THEN p_message_es ELSE message_es END,
    type = COALESCE(p_type, type),
    icon = COALESCE(p_icon, icon),
    link_url = CASE WHEN p_link_url IS NOT NULL THEN p_link_url ELSE link_url END,
    link_text = CASE WHEN p_link_text IS NOT NULL THEN p_link_text ELSE link_text END,
    is_active = COALESCE(p_is_active, is_active),
    priority = COALESCE(p_priority, priority),
    starts_at = COALESCE(p_starts_at, starts_at),
    ends_at = CASE WHEN p_ends_at IS NOT NULL THEN p_ends_at ELSE ends_at END,
    updated_at = NOW()
  WHERE id = p_announcement_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Announcement not found';
  END IF;

  RETURN json_build_object('success', true);
END;
$$;

-- Función para eliminar anuncio (admin)
CREATE OR REPLACE FUNCTION admin_delete_announcement(
  p_announcement_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_role TEXT;
BEGIN
  -- Verificar que el usuario sea admin
  SELECT role INTO v_player_role
  FROM players
  WHERE id = auth.uid();

  IF v_player_role IS NULL OR v_player_role != 'admin' THEN
    RAISE EXCEPTION 'Unauthorized: Admin access required';
  END IF;

  -- Eliminar anuncio
  DELETE FROM announcements
  WHERE id = p_announcement_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Announcement not found';
  END IF;

  RETURN json_build_object('success', true);
END;
$$;

-- Función para crear anuncio de actualización (admin only)
CREATE OR REPLACE FUNCTION admin_create_update_announcement(
  p_version TEXT,
  p_message TEXT DEFAULT NULL,
  p_message_es TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_role TEXT;
  v_announcement_id UUID;
  v_default_message TEXT;
  v_default_message_es TEXT;
BEGIN
  -- Verificar admin
  SELECT role INTO v_player_role FROM players WHERE id = auth.uid();

  IF v_player_role IS NULL OR v_player_role != 'admin' THEN
    RAISE EXCEPTION 'Unauthorized: Admin access required';
  END IF;

  -- Mensajes por defecto si no se proporcionan
  v_default_message := COALESCE(p_message,
    'A new version (' || p_version || ') is available! Please refresh to update.');
  v_default_message_es := COALESCE(p_message_es,
    'Una nueva versión (' || p_version || ') está disponible! Por favor actualiza la página.');

  -- Desactivar cualquier anuncio de actualización existente
  UPDATE announcements SET is_active = false WHERE type = 'update';

  -- Crear nuevo anuncio de actualización
  INSERT INTO announcements (
    message,
    message_es,
    type,
    icon,
    link_url,
    link_text,
    is_active,
    priority,
    starts_at,
    ends_at
  ) VALUES (
    v_default_message,
    v_default_message_es,
    'update',
    '🔄',
    NULL,
    NULL,
    true,
    999, -- Máxima prioridad
    NOW(),
    NULL -- Sin expiración hasta que se desactive manualmente
  ) RETURNING id INTO v_announcement_id;

  RETURN json_build_object(
    'success', true,
    'announcement_id', v_announcement_id,
    'version', p_version
  );
END;
$$;

GRANT EXECUTE ON FUNCTION admin_create_update_announcement TO authenticated;

-- Función para obtener información de usuarios (admin only)
-- Función para listar usuarios - INFORMACIÓN BÁSICA (admin only)
CREATE OR REPLACE FUNCTION admin_get_players(
  p_search TEXT DEFAULT NULL,
  p_limit INTEGER DEFAULT 50,
  p_offset INTEGER DEFAULT 0
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_role TEXT;
BEGIN
  -- Verificar admin
  SELECT role INTO v_player_role FROM players WHERE id = auth.uid();

  IF v_player_role IS NULL OR v_player_role != 'admin' THEN
    RAISE EXCEPTION 'Unauthorized: Admin access required';
  END IF;

  RETURN (
    SELECT COALESCE(json_agg(row_to_json(t)), '[]'::JSON)
    FROM (
      SELECT
        -- Información básica
        p.id,
        p.username,
        p.email,
        p.role,
        p.created_at as registered_at,
        p.last_seen as last_login_at,
        p.is_online,

        -- Balances resumen
        p.gamecoin_balance,
        p.crypto_balance,
        COALESCE(p.ron_balance, 0) as ron_balance,

        -- Estado
        p.reputation_score,
        (p.premium_until IS NOT NULL AND p.premium_until > NOW()) as is_premium,

        -- Minería básica
        COALESCE(p.blocks_mined, 0) as blocks_mined,
        (
          SELECT COALESCE(SUM(r.hashrate * (pr.condition / 100.0)), 0)
          FROM player_rigs pr
          JOIN rigs r ON r.id = pr.rig_id
          WHERE pr.player_id = p.id AND pr.is_active = true
        ) as total_hashrate,

        -- Contadores rápidos
        (SELECT COUNT(*) FROM player_rigs WHERE player_id = p.id AND is_active = true) as active_rigs,
        COALESCE(p.referral_count, 0) as referrals_count

      FROM players p
      WHERE
        (p_search IS NULL OR
         p.username ILIKE '%' || p_search || '%' OR
         p.email ILIKE '%' || p_search || '%' OR
         p.id::TEXT = p_search)
      ORDER BY p.created_at DESC
      LIMIT p_limit
      OFFSET p_offset
    ) t
  );
END;
$$;

-- Función para ver DETALLES COMPLETOS de un jugador específico (admin only)
CREATE OR REPLACE FUNCTION admin_get_player_detail(p_player_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_role TEXT;
  v_result JSON;
BEGIN
  -- Verificar admin
  SELECT role INTO v_player_role FROM players WHERE id = auth.uid();

  IF v_player_role IS NULL OR v_player_role != 'admin' THEN
    RAISE EXCEPTION 'Unauthorized: Admin access required';
  END IF;

  -- Construir respuesta detallada
  SELECT json_build_object(
    'success', true,
    'player', json_build_object(
      -- Información básica
      'id', p.id,
      'username', p.username,
      'email', p.email,
      'role', p.role,
      'registered_at', p.created_at,
      'last_login_at', p.last_seen,
      'is_online', p.is_online,

      -- Balances y economía
      'gamecoin_balance', p.gamecoin_balance,
      'crypto_balance', p.crypto_balance,
      'ron_balance', COALESCE(p.ron_balance, 0),
      'total_crypto_earned', COALESCE(p.total_crypto_earned, 0),
      'ron_wallet', p.ron_wallet,

      -- Recursos
      'energy', p.energy,
      'max_energy', p.max_energy,
      'internet', p.internet,
      'max_internet', p.max_internet,
      'reputation_score', p.reputation_score,

      -- Premium
      'is_premium', (p.premium_until IS NOT NULL AND p.premium_until > NOW()),
      'premium_until', p.premium_until,

      -- Minería
      'blocks_mined', COALESCE(p.blocks_mined, 0),
      'total_hashrate', (
        SELECT COALESCE(SUM(r.hashrate * (pr.condition / 100.0)), 0)
        FROM player_rigs pr
        JOIN rigs r ON r.id = pr.rig_id
        WHERE pr.player_id = p.id AND pr.is_active = true
      ),

      -- Shares (sistema actual de minería)
      'shares_stats', (
        SELECT json_build_object(
          'current_block_shares', COALESCE(ps.shares_count, 0),
          'last_share_at', ps.last_share_at,
          'total_shares_generated', (
            SELECT COALESCE(SUM(sh.shares_generated), 0)
            FROM share_history sh
            WHERE sh.player_id = p.id
          )
        )
        FROM player_shares ps
        WHERE ps.player_id = p.id
          AND ps.mining_block_id = (SELECT current_mining_block_id FROM network_stats WHERE id = 'current')
        LIMIT 1
      ),

      -- 🆕 Lista detallada de RIGS del jugador
      'rigs', (
        SELECT COALESCE(json_agg(json_build_object(
          'id', pr.id,
          'rig_id', r.id,
          'rig_name', r.name,
          'tier', r.tier,
          'hashrate', r.hashrate,
          'power_consumption', r.power_consumption,
          'internet_consumption', r.internet_consumption,
          'is_active', pr.is_active,
          'condition', pr.condition,
          'max_condition', COALESCE(pr.max_condition, 100),
          'temperature', pr.temperature,
          'times_repaired', COALESCE(pr.times_repaired, 0),
          'hashrate_level', COALESCE(pr.hashrate_level, 1),
          'efficiency_level', COALESCE(pr.efficiency_level, 1),
          'thermal_level', COALESCE(pr.thermal_level, 1),
          'acquired_at', pr.acquired_at,
          'activated_at', pr.activated_at,
          'deactivated_at', pr.deactivated_at,
          'cooling_installed', (
            SELECT COALESCE(json_agg(json_build_object(
              'id', rc.id,
              'cooling_id', ci.id,
              'cooling_name', ci.name,
              'cooling_power', ci.cooling_power,
              'durability', rc.durability,
              'installed_at', rc.installed_at
            )), '[]'::JSON)
            FROM rig_cooling rc
            JOIN cooling_items ci ON ci.id = rc.cooling_item_id
            WHERE rc.player_rig_id = pr.id
          ),
          'boosts_installed', (
            SELECT COALESCE(json_agg(json_build_object(
              'id', rb.id,
              'boost_id', bi.id,
              'boost_name', bi.name,
              'boost_type', bi.boost_type,
              'remaining_seconds', rb.remaining_seconds,
              'stack_count', rb.stack_count,
              'activated_at', rb.activated_at
            )), '[]'::JSON)
            FROM rig_boosts rb
            JOIN boost_items bi ON bi.id = rb.boost_item_id
            WHERE rb.player_rig_id = pr.id AND rb.remaining_seconds > 0
          )
        ) ORDER BY pr.acquired_at DESC), '[]'::JSON)
        FROM player_rigs pr
        JOIN rigs r ON r.id = pr.rig_id
        WHERE pr.player_id = p.id
      ),

      -- 🆕 COMPRAS (Crypto Packages)
      'crypto_purchases', (
        SELECT COALESCE(json_agg(json_build_object(
          'id', cp.id,
          'package_id', cp.package_id,
          'package_name', pkg.name,
          'crypto_amount', cp.crypto_amount,
          'ron_paid', cp.ron_paid,
          'status', cp.status,
          'purchased_at', cp.purchased_at,
          'completed_at', cp.completed_at,
          'tx_hash', cp.tx_hash
        ) ORDER BY cp.purchased_at DESC), '[]'::JSON)
        FROM crypto_purchases cp
        LEFT JOIN crypto_packages pkg ON pkg.id = cp.package_id
        WHERE cp.player_id = p.id
        LIMIT 20
      ),

      -- 🆕 BLOQUES - Pendientes (con detalle)
      'pending_blocks', (
        SELECT json_build_object(
          'pending_count', COUNT(*),
          'total_reward', COALESCE(SUM(reward), 0),
          'blocks', COALESCE(json_agg(json_build_object(
            'id', pb.id,
            'block_id', pb.block_id,
            'reward', pb.reward,
            'is_premium', pb.is_premium,
            'shares_contributed', pb.shares_contributed,
            'total_block_shares', pb.total_block_shares,
            'share_percentage', pb.share_percentage,
            'created_at', pb.created_at
          ) ORDER BY pb.created_at DESC), '[]'::JSON)
        )
        FROM pending_blocks pb
        WHERE pb.player_id = p.id AND pb.claimed = false
      ),

      -- 🆕 BLOQUES - Historial de claims (últimos 20)
      'claimed_blocks', (
        SELECT COALESCE(json_agg(json_build_object(
          'id', pb.id,
          'block_id', pb.block_id,
          'reward', pb.reward,
          'is_premium', pb.is_premium,
          'shares_contributed', pb.shares_contributed,
          'total_block_shares', pb.total_block_shares,
          'share_percentage', pb.share_percentage,
          'created_at', pb.created_at,
          'claimed_at', pb.claimed_at
        ) ORDER BY pb.claimed_at DESC), '[]'::JSON)
        FROM pending_blocks pb
        WHERE pb.player_id = p.id AND pb.claimed = true
        LIMIT 20
      ),

      -- Rigs (resumen)
      'total_rigs', (SELECT COUNT(*) FROM player_rigs WHERE player_id = p.id),
      'active_rigs', (SELECT COUNT(*) FROM player_rigs WHERE player_id = p.id AND is_active = true),
      'rig_slots', p.rig_slots,

      -- Inventario
      'inventory_stats', (
        SELECT json_build_object(
          'cooling_items', COALESCE((
            SELECT COUNT(DISTINCT item_id) FROM player_inventory WHERE player_id = p.id AND item_type = 'cooling'
          ), 0),
          'boost_items', COALESCE((
            SELECT COUNT(DISTINCT boost_id) FROM player_boosts WHERE player_id = p.id
          ), 0),
          'prepaid_cards', COALESCE((
            SELECT COUNT(*) FROM player_cards WHERE player_id = p.id AND is_redeemed = false
          ), 0),
          'crafting_elements', COALESCE((
            SELECT SUM(quantity) FROM player_crafting_inventory WHERE player_id = p.id
          ), 0)
        )
      ),

      -- Transacciones recientes (últimas 10)
      'recent_transactions', (
        SELECT COALESCE(json_agg(json_build_object(
          'type', t.type,
          'amount', t.amount,
          'currency', t.currency,
          'description', t.description,
          'created_at', t.created_at
        ) ORDER BY t.created_at DESC), '[]'::JSON)
        FROM (
          SELECT type, amount, currency, description, created_at
          FROM transactions
          WHERE player_id = p.id
          ORDER BY created_at DESC
          LIMIT 10
        ) t
      ),

      -- Referidos
      'referral_code', p.referral_code,
      'referrals_count', COALESCE(p.referral_count, 0),
      'referred_by_username', (
        SELECT username FROM players WHERE id = p.referred_by LIMIT 1
      ),

      -- Misiones completadas (hoy)
      'missions_completed_today', (
        SELECT COUNT(*)
        FROM player_missions pm
        WHERE pm.player_id = p.id
          AND pm.assigned_date = CURRENT_DATE
          AND pm.is_completed = true
      ),

      -- Racha de login
      'login_streak', (
        SELECT json_build_object(
          'current_streak', COALESCE(ps.current_streak, 0),
          'longest_streak', COALESCE(ps.longest_streak, 0),
          'last_claim_date', ps.last_claim_date
        )
        FROM player_streaks ps
        WHERE ps.player_id = p.id
        LIMIT 1
      ),

      -- Crafting
      'crafting_stats', (
        SELECT json_build_object(
          'sessions_completed', COALESCE(cooldown.sessions_completed, 0),
          'last_completed', cooldown.last_session_completed,
          'has_active_session', EXISTS(
            SELECT 1 FROM player_crafting_sessions
            WHERE player_id = p.id AND status = 'active'
          )
        )
        FROM player_crafting_cooldown cooldown
        WHERE cooldown.player_id = p.id
        LIMIT 1
      ),

      -- Defense (Tower Defense)
      'defense_stats', (
        SELECT json_build_object(
          'max_level', COALESCE(prog.max_level_completed, 0),
          'total_games', COALESCE(prog.total_games, 0),
          'total_wins', COALESCE(prog.total_wins, 0),
          'total_gc_earned', COALESCE(prog.total_gc_earned, 0)
        )
        FROM player_defense_progress prog
        WHERE prog.player_id = p.id
        LIMIT 1
      ),

      -- PVP Battles
      'battle_stats', (
        SELECT json_build_object(
          'total_battles', COUNT(*),
          'wins', COUNT(*) FILTER (WHERE bs.winner_id = p.id),
          'losses', COUNT(*) FILTER (WHERE bs.winner_id IS NOT NULL AND bs.winner_id != p.id AND bs.status IN ('completed', 'forfeited')),
          'in_lobby', EXISTS(SELECT 1 FROM battle_lobby WHERE player_id = p.id AND status = 'waiting'),
          'has_active_battle', EXISTS(SELECT 1 FROM battle_sessions WHERE (player1_id = p.id OR player2_id = p.id) AND status = 'active')
        )
        FROM battle_sessions bs
        WHERE (bs.player1_id = p.id OR bs.player2_id = p.id)
          AND bs.status IN ('completed', 'forfeited')
      ),

      -- RON movements
      'ron_movements', (
        SELECT json_build_object(
          'total_deposited', COALESCE((
            SELECT SUM(amount) FROM ron_deposits WHERE player_id = p.id AND status = 'completed'
          ), 0),
          'total_withdrawn', COALESCE((
            SELECT SUM(net_amount) FROM ron_withdrawals WHERE player_id = p.id AND status = 'completed'
          ), 0),
          'pending_withdrawals', COALESCE((
            SELECT COUNT(*) FROM ron_withdrawals WHERE player_id = p.id AND status IN ('pending', 'processing')
          ), 0)
        )
      ),

      -- Tiempo online hoy
      'minutes_online_today', (
        SELECT COALESCE(minutes_online, 0)
        FROM player_online_tracking
        WHERE player_id = p.id AND tracking_date = CURRENT_DATE
      ),

      -- Flags de seguridad/moderación
      'flags', (
        SELECT json_build_object(
          'is_in_cooldown', is_player_in_mining_cooldown(p.id),
          'has_pending_gifts', EXISTS(SELECT 1 FROM player_gifts WHERE player_id = p.id AND claimed = false)
        )
      )
    )
  ) INTO v_result
  FROM players p
  WHERE p.id = p_player_id;

  IF v_result IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Player not found');
  END IF;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_get_players TO authenticated;
GRANT EXECUTE ON FUNCTION admin_get_player_detail TO authenticated;

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
BEGIN RETURN 1000; END;  -- 300 base + 700 bonus = 1000 max para premium
$$;

CREATE OR REPLACE FUNCTION get_effective_max_energy(p_player_id UUID)
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_base_max INTEGER; v_bonus INTEGER := 0;
BEGIN
  SELECT max_energy INTO v_base_max FROM players WHERE id = p_player_id;
  RETURN v_base_max;
END;
$$;

CREATE OR REPLACE FUNCTION get_effective_max_internet(p_player_id UUID)
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_base_max INTEGER; v_bonus INTEGER := 0;
BEGIN
  SELECT max_internet INTO v_base_max FROM players WHERE id = p_player_id;
  RETURN v_base_max;
END;
$$;

-- =====================================================
-- FUNCIONES DE BLOQUES
-- =====================================================

-- Drop old function signatures (necesario si cambia el tipo de retorno)

CREATE OR REPLACE FUNCTION get_pending_blocks(p_player_id UUID, p_limit INT DEFAULT 20, p_offset INT DEFAULT 0)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_max_height INT;
  v_blocks JSON;
  v_total INT;
BEGIN
  -- Get current max block height for display
  SELECT COALESCE(MAX(height), 1) INTO v_max_height FROM blocks;

  -- Total count for pagination
  SELECT COUNT(*) INTO v_total FROM pending_blocks WHERE player_id = p_player_id AND claimed = false;

  SELECT COALESCE(json_agg(row_to_json(t)), '[]'::JSON) INTO v_blocks
  FROM (
    SELECT pb.id,
           COALESCE(pb.block_id, pb.id) as block_id,
           COALESCE(b.height, v_max_height) as block_height,
           pb.reward, pb.is_premium, pb.created_at
    FROM pending_blocks pb
    LEFT JOIN blocks b ON b.id = pb.block_id
    WHERE pb.player_id = p_player_id AND pb.claimed = false
    ORDER BY pb.created_at DESC
    LIMIT p_limit OFFSET p_offset
  ) t;

  RETURN json_build_object(
    'blocks', v_blocks,
    'total', v_total,
    'has_more', (p_offset + p_limit) < v_total
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
  -- Get block height
  SELECT height INTO v_height FROM blocks WHERE id = v_pending.block_id;
  v_description := 'Bloque reclamado #' || v_height;
  INSERT INTO transactions (player_id, type, amount, currency, description)
  VALUES (p_player_id, 'block_claim', v_pending.reward, 'crypto', v_description);
  -- Actualizar misiones de ganar crypto
  PERFORM update_mission_progress(p_player_id, 'earn_crypto', v_pending.reward);
  PERFORM update_mission_progress(p_player_id, 'earn_crypto_weekly', v_pending.reward);
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
  PERFORM update_mission_progress(p_player_id, 'earn_crypto_weekly', v_total_reward);
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
    internet = v_premium_max,
    max_energy = v_premium_max,
    max_internet = v_premium_max
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
  UPDATE players SET gamecoin_balance = 1000, crypto_balance = 0, energy = 300, internet = 300, max_energy = 300, max_internet = 300, reputation_score = 50, rig_slots = 1, blocks_mined = 0, updated_at = NOW() WHERE id = p_player_id;
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

  -- Check if upgrade reached max level
  IF v_next_level = v_player_rig.max_upgrade_level THEN
    PERFORM update_mission_progress(p_player_id, 'max_upgrade', 1);

    -- Check if ALL upgrades on this rig are maxed
    SELECT * INTO v_player_rig FROM player_rigs WHERE id = p_player_rig_id;
    IF v_player_rig.hashrate_level >= v_player_rig.max_upgrade_level
       AND v_player_rig.efficiency_level >= v_player_rig.max_upgrade_level
       AND v_player_rig.thermal_level >= v_player_rig.max_upgrade_level THEN
      PERFORM update_mission_progress(p_player_id, 'full_upgrades', 1);
    END IF;
  END IF;

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
  v_hashrate_bonus NUMERIC;
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

  -- Calcular hashrate efectivo del jugador (penalizaciones de temperatura y condición)
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

    -- Bonus por nivel de hashrate upgrade (usar valor de la tabla upgrade_costs)
    SELECT COALESCE(hashrate_bonus, 0) INTO v_hashrate_bonus
    FROM upgrade_costs WHERE level = v_rig.hashrate_level;
    IF v_hashrate_bonus IS NULL THEN v_hashrate_bonus := 0; END IF;
    v_hashrate_mult := v_hashrate_mult * (1 + v_hashrate_bonus / 100.0);

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
    -- Clamp probability to < 1 for LN calculations (avoid log of zero/negative)
    v_player_probability := LEAST(v_player_probability, 0.999);
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
      -- Contar rigs activos y totales
      (SELECT COUNT(*) FROM player_rigs pr WHERE pr.player_id = p.id AND pr.is_active = true) as "activeRigs",
      (SELECT COUNT(*) FROM player_rigs pr WHERE pr.player_id = p.id) as "totalRigs"
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
-- PITY TIMER SYSTEM V2 - Bad Luck Protection
-- =====================================================
-- =====================================================
-- NOTA: Sistema de pity timer eliminado.
-- Ya no es necesario con el sistema de shares compartidas,
-- donde todos los mineros reciben recompensa proporcional.
-- =====================================================

-- Función reset_mining_streak eliminada (ya no se usa con sistema de shares)

-- =====================================================
-- CLAIM ALL BLOCKS WITH RON (Instant Claim)
-- Permite reclamar todos los bloques pendientes pagando RON
-- Costo: 0.01 RON por bloque
-- =====================================================

CREATE OR REPLACE FUNCTION claim_all_blocks_with_ron(p_player_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player players%ROWTYPE;
  v_pending_count INTEGER;
  v_total_reward DECIMAL := 0;
  v_ron_cost_per_block DECIMAL := 0.0001;
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
-- GET RIG UPGRADES
-- =====================================================

CREATE OR REPLACE FUNCTION get_rig_upgrades(p_player_rig_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_rig RECORD;
  v_max_level INTEGER;
  v_hashrate_current RECORD;
  v_hashrate_next RECORD;
  v_efficiency_current RECORD;
  v_efficiency_next RECORD;
  v_thermal_current RECORD;
  v_thermal_next RECORD;
BEGIN
  -- Obtener información del rig
  SELECT pr.hashrate_level, pr.efficiency_level, pr.thermal_level, r.max_upgrade_level
  INTO v_rig
  FROM player_rigs pr
  JOIN rigs r ON r.id = pr.rig_id
  WHERE pr.id = p_player_rig_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Rig no encontrado');
  END IF;

  v_max_level := COALESCE(v_rig.max_upgrade_level, 5);

  -- Obtener bonus actual y siguiente para hashrate
  SELECT hashrate_bonus, crypto_cost INTO v_hashrate_current FROM upgrade_costs WHERE level = COALESCE(v_rig.hashrate_level, 1);
  SELECT hashrate_bonus, crypto_cost INTO v_hashrate_next FROM upgrade_costs WHERE level = COALESCE(v_rig.hashrate_level, 1) + 1;

  -- Obtener bonus actual y siguiente para efficiency
  SELECT efficiency_bonus, crypto_cost INTO v_efficiency_current FROM upgrade_costs WHERE level = COALESCE(v_rig.efficiency_level, 1);
  SELECT efficiency_bonus, crypto_cost INTO v_efficiency_next FROM upgrade_costs WHERE level = COALESCE(v_rig.efficiency_level, 1) + 1;

  -- Obtener bonus actual y siguiente para thermal
  SELECT thermal_bonus, crypto_cost INTO v_thermal_current FROM upgrade_costs WHERE level = COALESCE(v_rig.thermal_level, 1);
  SELECT thermal_bonus, crypto_cost INTO v_thermal_next FROM upgrade_costs WHERE level = COALESCE(v_rig.thermal_level, 1) + 1;

  RETURN jsonb_build_object(
    'success', true,
    'max_level', v_max_level,
    'hashrate', jsonb_build_object(
      'current_level', COALESCE(v_rig.hashrate_level, 1),
      'current_bonus', COALESCE(v_hashrate_current.hashrate_bonus, 0),
      'can_upgrade', COALESCE(v_rig.hashrate_level, 1) < v_max_level,
      'next_cost', COALESCE(v_hashrate_next.crypto_cost, 0),
      'next_bonus', COALESCE(v_hashrate_next.hashrate_bonus, 0)
    ),
    'efficiency', jsonb_build_object(
      'current_level', COALESCE(v_rig.efficiency_level, 1),
      'current_bonus', COALESCE(v_efficiency_current.efficiency_bonus, 0),
      'can_upgrade', COALESCE(v_rig.efficiency_level, 1) < v_max_level,
      'next_cost', COALESCE(v_efficiency_next.crypto_cost, 0),
      'next_bonus', COALESCE(v_efficiency_next.efficiency_bonus, 0)
    ),
    'thermal', jsonb_build_object(
      'current_level', COALESCE(v_rig.thermal_level, 1),
      'current_bonus', COALESCE(v_thermal_current.thermal_bonus, 0),
      'can_upgrade', COALESCE(v_rig.thermal_level, 1) < v_max_level,
      'next_cost', COALESCE(v_thermal_next.crypto_cost, 0),
      'next_bonus', COALESCE(v_thermal_next.thermal_bonus, 0)
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION get_rig_upgrades TO authenticated;

-- =====================================================
-- ADMIN: GAME STATUS (Estado del juego para admins)
-- =====================================================

CREATE OR REPLACE FUNCTION get_game_status()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_network_stats RECORD;
  v_total_players INTEGER;
  v_online_players INTEGER;
  v_total_rigs INTEGER;
  v_active_rigs INTEGER;
  v_total_blocks INTEGER;
  v_blocks_today INTEGER;
  v_total_crypto_mined NUMERIC;
  v_pending_withdrawals INTEGER;
  v_pending_withdrawals_amount NUMERIC;
  v_total_ron_deposited NUMERIC;
  v_total_ron_spent NUMERIC;
  v_total_ron_withdrawn NUMERIC;
  v_total_ron_balance NUMERIC;
  v_premium_players INTEGER;
BEGIN
  -- Network stats
  SELECT difficulty, hashrate, active_miners, updated_at
  INTO v_network_stats
  FROM network_stats WHERE id = 'current';

  -- Player counts
  SELECT COUNT(*) INTO v_total_players FROM players;
  SELECT COUNT(*) INTO v_online_players FROM players WHERE is_online = true;
  SELECT COUNT(*) INTO v_premium_players FROM players WHERE premium_until > NOW();

  -- Rig counts
  SELECT COUNT(*) INTO v_total_rigs FROM player_rigs;
  SELECT COUNT(*) INTO v_active_rigs FROM player_rigs WHERE is_active = true;

  -- Block stats
  SELECT COUNT(*) INTO v_total_blocks FROM blocks;
  SELECT COUNT(*) INTO v_blocks_today FROM blocks WHERE created_at > CURRENT_DATE;

  -- Total crypto mined
  SELECT COALESCE(SUM(total_crypto_earned), 0) INTO v_total_crypto_mined FROM players;

  -- Pending withdrawals
  SELECT COUNT(*), COALESCE(SUM(amount), 0)
  INTO v_pending_withdrawals, v_pending_withdrawals_amount
  FROM ron_withdrawals WHERE status IN ('pending', 'processing');

  -- Total RON deposited
  SELECT COALESCE(SUM(amount), 0) INTO v_total_ron_deposited
  FROM ron_deposits WHERE status = 'completed';

  -- Total RON withdrawn (retiros completados)
  SELECT COALESCE(SUM(net_amount), 0) INTO v_total_ron_withdrawn
  FROM ron_withdrawals
  WHERE status = 'completed';

  -- Total RON balance (saldo actual de todos los usuarios)
  SELECT COALESCE(SUM(ron_balance), 0) INTO v_total_ron_balance
  FROM players;

  -- Total RON spent = Depositado - Saldo actual - Retirado
  v_total_ron_spent := GREATEST(0, v_total_ron_deposited - v_total_ron_balance - v_total_ron_withdrawn);

  RETURN json_build_object(
    'success', true,
    'network', json_build_object(
      'difficulty', COALESCE(v_network_stats.difficulty, 1000),
      'hashrate', COALESCE(v_network_stats.hashrate, 0),
      'activeMiners', COALESCE(v_network_stats.active_miners, 0),
      'lastUpdate', v_network_stats.updated_at
    ),
    'players', json_build_object(
      'total', v_total_players,
      'online', v_online_players,
      'premium', v_premium_players
    ),
    'rigs', json_build_object(
      'total', v_total_rigs,
      'active', v_active_rigs
    ),
    'mining', json_build_object(
      'totalBlocks', v_total_blocks,
      'blocksToday', v_blocks_today,
      'totalCryptoMined', ROUND(v_total_crypto_mined, 2)
    ),
    'economy', json_build_object(
      'pendingWithdrawals', v_pending_withdrawals,
      'pendingWithdrawalsAmount', ROUND(v_pending_withdrawals_amount, 4),
      'totalRonDeposited', ROUND(v_total_ron_deposited, 4),
      'totalRonBalance', ROUND(v_total_ron_balance, 4),
      'totalRonSpent', ROUND(v_total_ron_spent, 4),
      'totalRonWithdrawn', ROUND(v_total_ron_withdrawn, 4),
      'balance', ROUND(v_total_ron_deposited + v_total_ron_spent - v_total_ron_withdrawn, 4)
    ),
    'timestamp', NOW()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION get_game_status TO authenticated;

-- =====================================================
-- 11. SISTEMA DE MINERÍA POR BLOQUES DE TIEMPO FIJO
-- =====================================================

-- Función: Inicializar nuevo bloque de minería de 30 minutos
CREATE OR REPLACE FUNCTION initialize_mining_block()
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_block_number INTEGER;
  v_difficulty NUMERIC;
  v_target_shares NUMERIC;
  v_reward NUMERIC;
  v_new_block_id UUID;
  v_target_close_at TIMESTAMPTZ;
  v_block_type TEXT;
  v_random NUMERIC;
  v_active_miners INTEGER;
  v_bronze_prob NUMERIC;
  v_silver_cutoff NUMERIC;
BEGIN
  -- Obtener configuración actual
  SELECT difficulty, target_shares_per_block, COALESCE(active_miners, 0)
  INTO v_difficulty, v_target_shares, v_active_miners
  FROM network_stats WHERE id = 'current';

  IF v_difficulty IS NULL THEN v_difficulty := 15000; END IF;
  IF v_target_shares IS NULL THEN v_target_shares := 100; END IF;

  -- Calcular número de bloque
  SELECT COALESCE(MAX(block_number), 0) + 1 INTO v_block_number FROM mining_blocks;

  -- 🎲 Probabilidades dinámicas según mineros activos
  -- Más mineros = mejor chance de bloques Silver/Gold
  IF v_active_miners <= 5 THEN
    v_bronze_prob := 0.75;    -- Bronze 75%, Silver 20%, Gold 5%
    v_silver_cutoff := 0.95;
  ELSIF v_active_miners <= 15 THEN
    v_bronze_prob := 0.65;    -- Bronze 65%, Silver 25%, Gold 10%
    v_silver_cutoff := 0.90;
  ELSIF v_active_miners <= 30 THEN
    v_bronze_prob := 0.55;    -- Bronze 55%, Silver 30%, Gold 15%
    v_silver_cutoff := 0.85;
  ELSE
    v_bronze_prob := 0.45;    -- Bronze 45%, Silver 35%, Gold 20%
    v_silver_cutoff := 0.80;
  END IF;

  v_random := RANDOM();

  IF v_random < v_bronze_prob THEN
    v_block_type := 'bronze';
    v_reward := 2000;  -- 🥉 Bronze
  ELSIF v_random < v_silver_cutoff THEN
    v_block_type := 'silver';
    v_reward := 3000;  -- 🥈 Silver
  ELSE
    v_block_type := 'gold';
    v_reward := 5000;  -- 🥇 Gold
  END IF;

  -- Calcular tiempo objetivo (30 minutos)
  v_target_close_at := NOW() + INTERVAL '30 minutes';

  -- Crear nuevo bloque de minería
  INSERT INTO mining_blocks (
    block_number,
    started_at,
    target_close_at,
    target_shares,
    reward,
    block_type,
    difficulty_at_start,
    status
  ) VALUES (
    v_block_number,
    NOW(),
    v_target_close_at,
    v_target_shares,
    v_reward,
    v_block_type,
    v_difficulty,
    'active'
  ) RETURNING id INTO v_new_block_id;

  -- Actualizar network_stats
  UPDATE network_stats
  SET current_mining_block_id = v_new_block_id
  WHERE id = 'current';

  RETURN v_new_block_id;
END;
$$;

-- Función: Generar shares para todos los mineros activos (llamada cada tick)
CREATE OR REPLACE FUNCTION generate_shares_tick()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_mining_block_id UUID;
  v_difficulty NUMERIC;
  v_rig RECORD;
  v_effective_hashrate NUMERIC;
  v_shares_probability NUMERIC;
  v_shares_generated NUMERIC;
  v_tick_duration NUMERIC := 0.5;  -- 30 segundos (30 / 60 = 0.5 minutos)
  v_total_shares_generated NUMERIC := 0;
  v_players_processed INTEGER := 0;
  v_rep_multiplier NUMERIC;
  v_temp_penalty NUMERIC;
  v_condition_penalty NUMERIC;
  v_boosts JSON;
  v_hashrate_mult NUMERIC;
  v_luck_mult NUMERIC;
  v_base_shares INTEGER;
  v_fractional NUMERIC;
  v_random NUMERIC;
  v_upgrade_hashrate_bonus NUMERIC;
  v_current_accumulator NUMERIC;  -- ⚙️ Acumulador actual del jugador
  v_new_accumulator NUMERIC;      -- ⚙️ Nuevo acumulador después de generación
  v_warmup_mult NUMERIC;          -- Multiplicador de calentamiento al encender rig
BEGIN
  -- Obtener bloque de minería actual
  SELECT current_mining_block_id, difficulty
  INTO v_mining_block_id, v_difficulty
  FROM network_stats WHERE id = 'current';

  IF v_mining_block_id IS NULL THEN
    -- No hay bloque activo, inicializar uno
    v_mining_block_id := initialize_mining_block();
    SELECT difficulty INTO v_difficulty FROM network_stats WHERE id = 'current';
  END IF;

  IF v_difficulty IS NULL THEN v_difficulty := 15000; END IF;

  -- Procesar cada rig activo
  FOR v_rig IN
    SELECT pr.id as rig_id, pr.player_id, pr.condition, pr.temperature,
           r.hashrate, p.reputation_score,
           COALESCE(pr.hashrate_level, 1) as hashrate_level,
           pr.activated_at
    FROM player_rigs pr
    JOIN rigs r ON r.id = pr.rig_id
    JOIN players p ON p.id = pr.player_id
    WHERE pr.is_active = true
      AND p.energy > 0
      AND p.internet > 0
      AND (p.is_online = true OR rig_has_autonomous_boost(pr.id))
      AND NOT is_player_in_mining_cooldown(pr.player_id)
  LOOP
    -- Calcular hashrate efectivo (igual que sistema actual)
    v_boosts := get_rig_boost_multipliers(v_rig.rig_id);
    v_hashrate_mult := COALESCE((v_boosts->>'hashrate')::NUMERIC, 1.0);
    v_luck_mult := COALESCE((v_boosts->>'luck')::NUMERIC, 1.0);

    -- Aplicar bonus de upgrade
    v_upgrade_hashrate_bonus := 0;
    SELECT COALESCE(hashrate_bonus, 0) INTO v_upgrade_hashrate_bonus
    FROM upgrade_costs WHERE level = v_rig.hashrate_level;
    IF v_upgrade_hashrate_bonus IS NULL THEN v_upgrade_hashrate_bonus := 0; END IF;
    v_hashrate_mult := v_hashrate_mult * (1 + v_upgrade_hashrate_bonus / 100.0);

    -- Multiplicador de reputación
    IF v_rig.reputation_score >= 80 THEN
      v_rep_multiplier := 1 + (v_rig.reputation_score - 80) * 0.01;
    ELSIF v_rig.reputation_score < 50 THEN
      v_rep_multiplier := 0.5 + (v_rig.reputation_score / 100.0);
    ELSE
      v_rep_multiplier := 1;
    END IF;

    -- Penalización por temperatura
    v_temp_penalty := 1;
    IF v_rig.temperature > 50 THEN
      v_temp_penalty := 1 - ((v_rig.temperature - 50) * 0.014);
      v_temp_penalty := GREATEST(0.3, v_temp_penalty);
    END IF;

    -- Penalización por condición: sin penalización >= 80%, gradual debajo
    IF v_rig.condition >= 80 THEN
      v_condition_penalty := 1.0;
    ELSE
      v_condition_penalty := 0.3 + (v_rig.condition / 80.0) * 0.7;
    END IF;

    -- Calcular hashrate efectivo
    v_effective_hashrate := v_rig.hashrate * v_condition_penalty * v_rep_multiplier *
                           v_temp_penalty * v_hashrate_mult;

    -- Warm-up: +20% por tick (30s), 100% en 5 ticks (120s)
    IF v_rig.activated_at IS NOT NULL THEN
      v_warmup_mult := LEAST(1.0, (1 + FLOOR(EXTRACT(EPOCH FROM (NOW() - v_rig.activated_at)) / 30.0)) * 0.20);
      v_warmup_mult := GREATEST(0.0, v_warmup_mult);
      v_effective_hashrate := v_effective_hashrate * v_warmup_mult;
    END IF;

    -- Calcular probabilidad de generar shares
    -- Fórmula: (hashrate_efectivo / dificultad) * tick_duration * luck_multiplier
    v_shares_probability := (v_effective_hashrate / v_difficulty) * v_tick_duration * v_luck_mult;

    -- ⚙️ Sistema de acumulador fraccional para suavizar generación en baja actividad
    -- Obtener acumulador actual del jugador
    SELECT COALESCE(fractional_accumulator, 0) INTO v_current_accumulator
    FROM player_shares
    WHERE mining_block_id = v_mining_block_id AND player_id = v_rig.player_id;

    IF v_current_accumulator IS NULL THEN
      v_current_accumulator := 0;
    END IF;

    -- Agregar probabilidad al acumulador
    v_new_accumulator := v_current_accumulator + v_shares_probability;

    -- Generar shares enteras del acumulador
    v_shares_generated := FLOOR(v_new_accumulator);

    -- Mantener la parte fraccional para el próximo tick
    v_new_accumulator := v_new_accumulator - v_shares_generated;

    -- Registrar shares (siempre actualizar para mantener el acumulador)
    INSERT INTO player_shares (mining_block_id, player_id, shares_count, fractional_accumulator, last_share_at)
    VALUES (v_mining_block_id, v_rig.player_id, v_shares_generated, v_new_accumulator, NOW())
    ON CONFLICT (mining_block_id, player_id)
    DO UPDATE SET
      shares_count = player_shares.shares_count + v_shares_generated,
      fractional_accumulator = v_new_accumulator,
      last_share_at = NOW();

    -- Solo registrar en historial si se generaron shares
    IF v_shares_generated > 0 THEN
      -- Guardar en historial
      INSERT INTO share_history (
        mining_block_id, player_id, player_rig_id,
        shares_generated, hashrate_at_generation, difficulty, generated_at
      ) VALUES (
        v_mining_block_id, v_rig.player_id, v_rig.rig_id,
        v_shares_generated, v_effective_hashrate, v_difficulty, NOW()
      );

      v_total_shares_generated := v_total_shares_generated + v_shares_generated;
    END IF;

    v_players_processed := v_players_processed + 1;
  END LOOP;

  -- ✅ El bot ahora se procesa como cualquier jugador en el loop principal
  -- Su rig S9 (1000 hashrate) se incluye automáticamente en el procesamiento
  -- NO necesita lógica especial para generar shares

  -- Actualizar total de shares del bloque
  UPDATE mining_blocks
  SET total_shares = COALESCE(total_shares, 0) + v_total_shares_generated
  WHERE id = v_mining_block_id;

  -- 🌐 Actualizar estadísticas de red (hashrate y mineros activos) en tiempo real
  -- ✅ Incluye al bot en el cálculo (ya no se procesa por separado)
  UPDATE network_stats
  SET
    hashrate = (
      SELECT COALESCE(SUM(
        r.hashrate *
        GREATEST(0.3, pr.condition / 100.0) *  -- condition penalty
        CASE
          WHEN p.reputation_score >= 80 THEN 1 + (p.reputation_score - 80) * 0.01
          WHEN p.reputation_score < 50 THEN 0.5 + (p.reputation_score / 100.0)
          ELSE 1
        END *  -- reputation multiplier
        CASE
          WHEN pr.temperature > 50 THEN GREATEST(0.3, 1 - ((pr.temperature - 50) * 0.014))
          ELSE 1
        END *  -- temperature penalty
        (1 + COALESCE((SELECT hashrate_bonus / 100.0 FROM upgrade_costs WHERE level = COALESCE(pr.hashrate_level, 1)), 0)) *  -- upgrade bonus
        -- warm-up: +25% por tick (30s), 100% en 4 ticks (90s)
        CASE
          WHEN pr.activated_at IS NOT NULL THEN GREATEST(0.0, LEAST(1.0, (1 + FLOOR(EXTRACT(EPOCH FROM (NOW() - pr.activated_at)) / 30.0)) * 0.20))
          ELSE 1
        END
      ), 0)
      FROM player_rigs pr
      JOIN rigs r ON r.id = pr.rig_id
      JOIN players p ON p.id = pr.player_id
      WHERE pr.is_active = true
        AND p.energy > 0
        AND p.internet > 0
        AND (p.is_online = true OR rig_has_autonomous_boost(pr.id))
        AND NOT is_player_in_mining_cooldown(pr.player_id)
        -- ✅ Incluye al bot (con su rig S9 de 1000 hashrate)
    ),
    active_miners = (
      SELECT COUNT(DISTINCT pr.player_id)
      FROM player_rigs pr
      JOIN players p ON p.id = pr.player_id
      WHERE pr.is_active = true
        AND p.energy > 0
        AND p.internet > 0
        AND (p.is_online = true OR rig_has_autonomous_boost(pr.id))
        AND NOT is_player_in_mining_cooldown(pr.player_id)
        -- ✅ Incluye al bot en el conteo de mineros activos
    ),
    updated_at = NOW()
  WHERE id = 'current';

  RETURN json_build_object(
    'success', true,
    'mining_block_id', v_mining_block_id,
    'shares_generated', v_total_shares_generated,
    'players_processed', v_players_processed,
    'difficulty', v_difficulty
  );
END;
$$;

-- Función: Cerrar bloque de minería y distribuir recompensas
CREATE OR REPLACE FUNCTION close_mining_block(p_mining_block_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_mining_block mining_blocks%ROWTYPE;
  v_participant RECORD;
  v_share_percentage NUMERIC;
  v_player_reward NUMERIC;
  v_participants_count INTEGER := 0;
  v_rewards_distributed NUMERIC := 0;
  v_total_effective_shares NUMERIC := 0;
  v_effective_shares NUMERIC;
BEGIN
  -- Obtener bloque de minería
  SELECT * INTO v_mining_block FROM mining_blocks WHERE id = p_mining_block_id;

  IF v_mining_block IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Mining block not found');
  END IF;

  IF v_mining_block.status != 'active' THEN
    RETURN json_build_object('success', false, 'error', 'Block already closed');
  END IF;

  -- Marcar como cerrado
  UPDATE mining_blocks
  SET status = 'closed', closed_at = NOW()
  WHERE id = p_mining_block_id;

  -- Si no hay shares, no distribuir nada
  IF COALESCE(v_mining_block.total_shares, 0) = 0 THEN
    UPDATE mining_blocks SET status = 'distributed' WHERE id = p_mining_block_id;

    -- Crear nuevo bloque
    PERFORM initialize_mining_block();

    RETURN json_build_object(
      'success', true,
      'participants', 0,
      'total_shares', 0,
      'rewards_distributed', 0,
      'difficulty_adjusted', false
    );
  END IF;

  -- Paso 1: Calcular total de shares efectivas (con bonus premium en el peso)
  BEGIN
    FOR v_participant IN
      SELECT player_id, shares_count
      FROM player_shares
      WHERE mining_block_id = p_mining_block_id
    LOOP
      -- Shares efectivas: multiplicar por 1.5 si es premium
      IF is_player_premium(v_participant.player_id) THEN
        v_total_effective_shares := v_total_effective_shares + (v_participant.shares_count * 1.5);
      ELSE
        v_total_effective_shares := v_total_effective_shares + v_participant.shares_count;
      END IF;
    END LOOP;
  END;

  -- Paso 2: Distribuir recompensas proporcionalmente basadas en shares efectivas
  FOR v_participant IN
    SELECT player_id, shares_count
    FROM player_shares
    WHERE mining_block_id = p_mining_block_id
    ORDER BY shares_count DESC
  LOOP
    v_participants_count := v_participants_count + 1;

    -- Calcular shares efectivas del jugador
    IF is_player_premium(v_participant.player_id) THEN
      v_effective_shares := v_participant.shares_count * 1.5;
    ELSE
      v_effective_shares := v_participant.shares_count;
    END IF;

    -- Calcular porcentaje basado en shares REALES (para registro)
    v_share_percentage := (v_participant.shares_count / v_mining_block.total_shares) * 100;

    -- Calcular recompensa basada en shares EFECTIVAS
    v_player_reward := v_mining_block.reward * (v_effective_shares / v_total_effective_shares);

    -- Mínimo 0.01 crypto si contribuyó
    v_player_reward := GREATEST(0.01, v_player_reward);

    -- Crear entrada en pending_blocks
    INSERT INTO pending_blocks (
      block_id,  -- NULL por ahora, se llenará cuando se cree el bloque real si es necesario
      player_id,
      reward,
      is_premium,
      shares_contributed,
      total_block_shares,
      share_percentage,
      created_at
    ) VALUES (
      NULL,
      v_participant.player_id,
      v_player_reward,
      is_player_premium(v_participant.player_id),
      v_participant.shares_count,
      v_mining_block.total_shares,
      v_share_percentage,
      NOW()
    );

    v_rewards_distributed := v_rewards_distributed + v_player_reward;

    -- Actualizar estadísticas del jugador
    UPDATE players
    SET blocks_mined = COALESCE(blocks_mined, 0) + 1
    WHERE id = v_participant.player_id;

    -- Actualizar progreso de misiones
    PERFORM update_mission_progress(v_participant.player_id, 'mine_blocks', 1);
    PERFORM update_mission_progress(v_participant.player_id, 'mine_blocks_weekly', 1);
    PERFORM update_mission_progress(v_participant.player_id, 'total_blocks', 1);
    PERFORM update_mission_progress(v_participant.player_id, 'first_block', 1);
  END LOOP;

  -- Marcar como distribuido
  UPDATE mining_blocks SET status = 'distributed' WHERE id = p_mining_block_id;

  -- Verificar si hay que ajustar dificultad
  PERFORM adjust_share_difficulty(p_mining_block_id);

  -- Crear nuevo bloque de minería
  PERFORM initialize_mining_block();

  -- Actualizar network_stats
  UPDATE network_stats
  SET last_block_closed_at = NOW()
  WHERE id = 'current';

  RETURN json_build_object(
    'success', true,
    'participants', v_participants_count,
    'total_shares', v_mining_block.total_shares,
    'rewards_distributed', v_rewards_distributed,
    'block_number', v_mining_block.block_number
  );
END;
$$;

-- Función: Ajustar dificultad basándose en shares generadas
CREATE OR REPLACE FUNCTION adjust_share_difficulty(p_mining_block_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_mining_block mining_blocks%ROWTYPE;
  v_current_difficulty NUMERIC;
  v_target_shares NUMERIC;
  v_actual_shares NUMERIC;
  v_last_adjustment TIMESTAMPTZ;
  v_time_since_adjustment INTERVAL;
  v_adjustment_ratio NUMERIC;
  v_new_difficulty NUMERIC;
  v_smoothing_factor NUMERIC := 0.7;  -- Suavizado
  v_max_change NUMERIC := 0.25;  -- ±25% máximo
  v_min_difficulty NUMERIC := 100;
  v_max_difficulty NUMERIC := 1000000;
  v_should_adjust BOOLEAN := false;
BEGIN
  -- Obtener bloque
  SELECT * INTO v_mining_block FROM mining_blocks WHERE id = p_mining_block_id;

  IF v_mining_block IS NULL THEN
    RETURN json_build_object('adjusted', false, 'error', 'Block not found');
  END IF;

  -- ❗ IMPORTANTE: No ajustar dificultad para bloques activos
  -- Solo ajustar después del cierre del bloque
  IF v_mining_block.status = 'active' THEN
    RETURN json_build_object(
      'adjusted', false,
      'reason', 'Cannot adjust difficulty for active blocks',
      'block_status', v_mining_block.status
    );
  END IF;

  -- Obtener configuración actual
  SELECT difficulty, target_shares_per_block, last_difficulty_adjustment
  INTO v_current_difficulty, v_target_shares, v_last_adjustment
  FROM network_stats WHERE id = 'current';

  v_actual_shares := COALESCE(v_mining_block.total_shares, 0);

  -- Calcular tiempo desde último ajuste
  IF v_last_adjustment IS NOT NULL THEN
    v_time_since_adjustment := NOW() - v_last_adjustment;
  ELSE
    v_time_since_adjustment := INTERVAL '0';
  END IF;

  -- Decidir si ajustar:
  -- Solo ajustar si el bloque está cerrado/distribuido
  -- 1. Si se superó el objetivo de shares
  -- 2. Si pasaron más de 60 minutos sin ajustar
  IF v_actual_shares > v_target_shares THEN
    v_should_adjust := true;
  ELSIF EXTRACT(EPOCH FROM v_time_since_adjustment) > 3600 THEN
    v_should_adjust := true;
  END IF;

  IF NOT v_should_adjust THEN
    RETURN json_build_object(
      'adjusted', false,
      'reason', 'No adjustment needed',
      'actual_shares', v_actual_shares,
      'target_shares', v_target_shares,
      'time_since_adjustment_minutes', ROUND(EXTRACT(EPOCH FROM v_time_since_adjustment) / 60)
    );
  END IF;

  -- Calcular ratio de ajuste
  IF v_actual_shares > 0 THEN
    v_adjustment_ratio := v_actual_shares / v_target_shares;
  ELSE
    -- Si no hubo shares, reducir dificultad significativamente
    v_adjustment_ratio := 0.5;
  END IF;

  -- Aplicar suavizado: nueva_dificultad = actual * (1 + smoothing * (ratio - 1))
  v_new_difficulty := v_current_difficulty * (1 + v_smoothing_factor * (v_adjustment_ratio - 1));

  -- Limitar cambio a ±25%
  v_new_difficulty := GREATEST(v_new_difficulty, v_current_difficulty * (1 - v_max_change));
  v_new_difficulty := LEAST(v_new_difficulty, v_current_difficulty * (1 + v_max_change));

  -- Aplicar límites absolutos
  v_new_difficulty := GREATEST(v_min_difficulty, LEAST(v_max_difficulty, v_new_difficulty));

  -- Actualizar dificultad
  UPDATE network_stats
  SET difficulty = v_new_difficulty,
      last_difficulty_adjustment = NOW()
  WHERE id = 'current';

  RETURN json_build_object(
    'adjusted', true,
    'old_difficulty', v_current_difficulty,
    'new_difficulty', v_new_difficulty,
    'actual_shares', v_actual_shares,
    'target_shares', v_target_shares,
    'adjustment_ratio', v_adjustment_ratio,
    'change_percent', ROUND((v_adjustment_ratio - 1) * 100, 2)
  );
END;
$$;

-- Función: Verificar y cerrar bloques que deben cerrarse
CREATE OR REPLACE FUNCTION check_and_close_blocks()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_block RECORD;
  v_close_result JSON;
  v_blocks_closed INTEGER := 0;
BEGIN
  -- Buscar bloques activos que debieran cerrarse
  FOR v_block IN
    SELECT id, block_number, target_close_at, total_shares
    FROM mining_blocks
    WHERE status = 'active' AND target_close_at <= NOW()
  LOOP
    -- Cerrar bloque
    v_close_result := close_mining_block(v_block.id);
    v_blocks_closed := v_blocks_closed + 1;
  END LOOP;

  RETURN json_build_object(
    'success', true,
    'blocks_closed', v_blocks_closed
  );
END;
$$;

-- Función: Obtener información del bloque actual para frontend
CREATE OR REPLACE FUNCTION get_current_mining_block_info()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_mining_block mining_blocks%ROWTYPE;
  v_time_remaining INTERVAL;
  v_progress_percent NUMERIC;
BEGIN
  SELECT * INTO v_mining_block
  FROM mining_blocks
  WHERE status = 'active'
  ORDER BY started_at DESC
  LIMIT 1;

  IF v_mining_block IS NULL THEN
    RETURN json_build_object(
      'active', false,
      'block_number', NULL
    );
  END IF;

  v_time_remaining := v_mining_block.target_close_at - NOW();
  v_progress_percent := (COALESCE(v_mining_block.total_shares, 0) /
                         NULLIF(v_mining_block.target_shares, 0)) * 100;

  RETURN json_build_object(
    'active', true,
    'block_number', v_mining_block.block_number,
    'started_at', v_mining_block.started_at,
    'target_close_at', v_mining_block.target_close_at,
    'time_remaining_seconds', GREATEST(0, EXTRACT(EPOCH FROM v_time_remaining)),
    'total_shares', COALESCE(v_mining_block.total_shares, 0),
    'target_shares', v_mining_block.target_shares,
    'progress_percent', LEAST(100, v_progress_percent),
    'reward', v_mining_block.reward,
    'difficulty', v_mining_block.difficulty_at_start,
    'block_type', COALESCE(v_mining_block.block_type, 'bronze')
  );
END;
$$;

-- Función: Obtener shares del jugador en el bloque actual
CREATE OR REPLACE FUNCTION get_player_shares_info(p_player_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_mining_block_id UUID;
  v_player_shares NUMERIC;
  v_total_shares NUMERIC;
  v_share_percentage NUMERIC;
  v_estimated_reward NUMERIC;
  v_block_reward NUMERIC;
  v_total_effective_shares NUMERIC;
  v_player_effective_shares NUMERIC;
  v_temp_shares NUMERIC;
  v_temp_player_id UUID;
  v_temp_is_premium BOOLEAN;
BEGIN
  -- Obtener bloque activo
  SELECT id, total_shares, reward INTO v_mining_block_id, v_total_shares, v_block_reward
  FROM mining_blocks
  WHERE status = 'active'
  ORDER BY started_at DESC
  LIMIT 1;

  IF v_mining_block_id IS NULL THEN
    RETURN json_build_object(
      'has_shares', false,
      'shares', 0
    );
  END IF;

  -- Obtener shares del jugador
  SELECT COALESCE(shares_count, 0) INTO v_player_shares
  FROM player_shares
  WHERE mining_block_id = v_mining_block_id AND player_id = p_player_id;

  IF v_player_shares IS NULL OR v_player_shares = 0 THEN
    RETURN json_build_object(
      'has_shares', false,
      'shares', 0,
      'mining_block_id', v_mining_block_id
    );
  END IF;

  -- Calcular porcentaje y recompensa estimada
  IF v_total_shares > 0 THEN
    -- Calcular total de shares efectivas (con bonus premium en el peso)
    v_total_effective_shares := 0;
    FOR v_temp_player_id, v_temp_shares IN
      SELECT player_id, shares_count
      FROM player_shares
      WHERE mining_block_id = v_mining_block_id
    LOOP
      v_temp_is_premium := is_player_premium(v_temp_player_id);
      IF v_temp_is_premium THEN
        v_total_effective_shares := v_total_effective_shares + (v_temp_shares * 1.5);
      ELSE
        v_total_effective_shares := v_total_effective_shares + v_temp_shares;
      END IF;
    END LOOP;

    -- Calcular shares efectivas del jugador
    IF is_player_premium(p_player_id) THEN
      v_player_effective_shares := v_player_shares * 1.5;
    ELSE
      v_player_effective_shares := v_player_shares;
    END IF;

    -- Porcentaje basado en shares reales
    v_share_percentage := (v_player_shares / v_total_shares) * 100;

    -- Recompensa basada en shares efectivas
    v_estimated_reward := v_block_reward * (v_player_effective_shares / v_total_effective_shares);
  ELSE
    v_share_percentage := 0;
    v_estimated_reward := 0;
  END IF;

  RETURN json_build_object(
    'has_shares', true,
    'shares', v_player_shares,
    'total_shares', v_total_shares,
    'share_percentage', v_share_percentage,
    'estimated_reward', v_estimated_reward,
    'mining_block_id', v_mining_block_id
  );
END;
$$;

-- Función principal: Ejecuta el tick del sistema de shares (llamada por cron cada minuto)
CREATE OR REPLACE FUNCTION game_tick_share_system()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_shares_result JSON;
  v_close_result JSON;
  v_resources_result INTEGER;
  v_inactive_marked INTEGER := 0;
  v_rigs_shutdown INTEGER := 0;
  v_bot_id UUID := '00000000-0000-0000-0000-000000000001';
BEGIN
  -- ✅ MANTENER AL BOT SIEMPRE ONLINE
  UPDATE players
  SET is_online = true, last_seen = NOW()
  WHERE id = v_bot_id;

  -- 1. Marcar jugadores offline y apagar rigs (cada tick)
  WITH inactive_players AS (
    UPDATE players
    SET is_online = false
    WHERE is_online = true
      AND last_seen < NOW() - INTERVAL '10 minutes'  -- ✅ Aumentado de 5 a 10 minutos
      AND id != v_bot_id  -- ✅ EXCLUIR AL BOT
    RETURNING id
  )
  SELECT COUNT(*) INTO v_inactive_marked FROM inactive_players;

  -- Apagar rigs de jugadores offline (sin ventana de tiempo)
  UPDATE player_rigs
  SET is_active = false,
      deactivated_at = NOW(),
      activated_at = NULL
  WHERE player_id IN (
    SELECT id FROM players
    WHERE is_online = false
      AND last_seen < NOW() - INTERVAL '10 minutes'
      AND id != v_bot_id  -- ✅ EXCLUIR AL BOT
  )
  AND is_active = true
  AND NOT rig_has_autonomous_boost(id);
  GET DIAGNOSTICS v_rigs_shutdown = ROW_COUNT;

  -- 2. Procesar decay de recursos (cada tick)
  v_resources_result := process_resource_decay();

  -- 3. Generar shares para mineros activos
  v_shares_result := generate_shares_tick();

  -- 4. Verificar y cerrar bloques si es necesario
  v_close_result := check_and_close_blocks();

  RETURN json_build_object(
    'success', true,
    'shares_generated', (v_shares_result->>'shares_generated')::NUMERIC,
    'players_processed', (v_shares_result->>'players_processed')::INTEGER,
    'blocks_closed', (v_close_result->>'blocks_closed')::INTEGER,
    'resources_processed', v_resources_result,
    'players_marked_offline', v_inactive_marked,
    'rigs_shutdown', v_rigs_shutdown,
    'timestamp', NOW()
  );
END;
$$;

-- =====================================================
-- OBTENER BLOQUES RECIENTES CON INFO DE SHARES
-- =====================================================

CREATE OR REPLACE FUNCTION get_recent_mining_blocks(p_player_id UUID DEFAULT NULL, p_limit INTEGER DEFAULT 10)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_result JSON;
BEGIN
  SELECT json_agg(block_info ORDER BY block_number DESC)
  INTO v_result
  FROM (
    SELECT
      mb.id,
      mb.block_number,
      mb.total_shares,
      mb.reward,
      mb.closed_at as created_at,
      -- Total real distribuido (incluye bonus premium)
      (SELECT COALESCE(SUM(pb.reward), 0) FROM pending_blocks pb
       WHERE pb.created_at >= mb.closed_at - INTERVAL '5 seconds'
         AND pb.created_at <= mb.closed_at + INTERVAL '5 seconds'
         AND pb.shares_contributed IS NOT NULL) as total_distributed,
      -- Contar contribuyentes únicos
      (SELECT COUNT(DISTINCT player_id) FROM pending_blocks
       WHERE created_at >= mb.closed_at - INTERVAL '5 seconds'
         AND created_at <= mb.closed_at + INTERVAL '5 seconds'
         AND shares_contributed IS NOT NULL) as contributors_count,
      -- Top contributor (jugador en primer lugar)
      (SELECT json_build_object(
        'username', p.username,
        'percentage', pb.share_percentage,
        'shares', pb.shares_contributed
      )
      FROM pending_blocks pb
      INNER JOIN players p ON p.id = pb.player_id
      WHERE pb.created_at >= mb.closed_at - INTERVAL '5 seconds'
        AND pb.created_at <= mb.closed_at + INTERVAL '5 seconds'
        AND pb.shares_contributed IS NOT NULL
      ORDER BY pb.share_percentage DESC
      LIMIT 1) as top_contributor,
      -- Información del jugador actual (si participó)
      CASE
        WHEN p_player_id IS NOT NULL THEN
          (SELECT json_build_object(
            'participated', true,
            'shares', pb.shares_contributed,
            'percentage', pb.share_percentage,
            'reward', pb.reward,
            'is_premium', pb.is_premium
          )
          FROM pending_blocks pb
          WHERE pb.player_id = p_player_id
            AND pb.created_at >= mb.closed_at - INTERVAL '5 seconds'
            AND pb.created_at <= mb.closed_at + INTERVAL '5 seconds'
            AND pb.shares_contributed IS NOT NULL
          LIMIT 1)
        ELSE NULL
      END as player_participation
    FROM mining_blocks mb
    WHERE mb.status = 'distributed'
    ORDER BY mb.block_number DESC
    LIMIT p_limit
  ) block_info;

  RETURN COALESCE(v_result, '[]'::JSON);
END;
$$;

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

-- Grants para sistema de shares
GRANT EXECUTE ON FUNCTION initialize_mining_block TO authenticated;
GRANT EXECUTE ON FUNCTION generate_shares_tick TO authenticated;
GRANT EXECUTE ON FUNCTION close_mining_block TO authenticated;
GRANT EXECUTE ON FUNCTION adjust_share_difficulty TO authenticated;
GRANT EXECUTE ON FUNCTION check_and_close_blocks TO authenticated;
GRANT EXECUTE ON FUNCTION get_current_mining_block_info TO authenticated;
GRANT EXECUTE ON FUNCTION get_player_shares_info TO authenticated;
GRANT EXECUTE ON FUNCTION game_tick_share_system TO authenticated;
GRANT EXECUTE ON FUNCTION get_recent_mining_blocks TO authenticated;

-- =====================================================
-- SISTEMA DE REGALOS (GIFTS)
-- El admin crea regalos para jugadores específicos o todos.
-- El jugador ve un regalo animado en pantalla y lo reclama.
-- =====================================================

CREATE TABLE IF NOT EXISTS player_gifts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  title TEXT NOT NULL DEFAULT 'Gift',
  description TEXT,
  icon TEXT DEFAULT '🎁',
  -- Reward fields (one or more can be set)
  reward_gamecoin DECIMAL(10,2) DEFAULT 0,
  reward_crypto DECIMAL(10,8) DEFAULT 0,
  reward_energy DECIMAL DEFAULT 0,
  reward_internet DECIMAL DEFAULT 0,
  reward_item_type TEXT,          -- 'cooling', 'boost', 'rig', 'prepaid_card'
  reward_item_id TEXT,            -- references the specific item id
  reward_item_quantity INTEGER DEFAULT 1,
  -- State
  claimed BOOLEAN DEFAULT FALSE,
  claimed_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ,         -- NULL = no expiration
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_player_gifts_pending ON player_gifts(player_id, claimed);

-- RLS
ALTER TABLE player_gifts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS player_gifts_select ON player_gifts;
CREATE POLICY player_gifts_select ON player_gifts FOR SELECT TO authenticated
  USING (player_id = auth.uid());

-- Obtener regalos pendientes de un jugador
CREATE OR REPLACE FUNCTION get_pending_gifts(p_player_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Limpiar regalos expirados
  UPDATE player_gifts
  SET claimed = true, claimed_at = NOW()
  WHERE player_id = p_player_id
    AND claimed = false
    AND expires_at IS NOT NULL
    AND expires_at <= NOW();

  RETURN (
    SELECT COALESCE(json_agg(row_to_json(t) ORDER BY t.created_at ASC), '[]'::JSON)
    FROM (
      SELECT id, title, description, icon,
             reward_gamecoin, reward_crypto, reward_energy, reward_internet,
             reward_item_type, reward_item_id, reward_item_quantity,
             expires_at, created_at
      FROM player_gifts
      WHERE player_id = p_player_id
        AND claimed = false
        AND (expires_at IS NULL OR expires_at > NOW())
    ) t
  );
END;
$$;

-- Reclamar un regalo
CREATE OR REPLACE FUNCTION claim_gift(p_player_id UUID, p_gift_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_gift player_gifts%ROWTYPE;
  v_rewards JSON;
  v_item_name TEXT;
  v_effective_max_energy NUMERIC;
  v_effective_max_internet NUMERIC;
BEGIN
  -- Obtener regalo
  SELECT * INTO v_gift
  FROM player_gifts
  WHERE id = p_gift_id AND player_id = p_player_id AND claimed = false;

  IF v_gift IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Regalo no encontrado o ya reclamado');
  END IF;

  -- Verificar expiración
  IF v_gift.expires_at IS NOT NULL AND v_gift.expires_at <= NOW() THEN
    UPDATE player_gifts SET claimed = true, claimed_at = NOW() WHERE id = p_gift_id;
    RETURN json_build_object('success', false, 'error', 'Este regalo ha expirado');
  END IF;

  -- Marcar como reclamado
  UPDATE player_gifts SET claimed = true, claimed_at = NOW() WHERE id = p_gift_id;

  -- Obtener máximos efectivos de recursos
  v_effective_max_energy := get_effective_max_energy(p_player_id);
  v_effective_max_internet := get_effective_max_internet(p_player_id);

  -- Acreditar recompensas de moneda/recursos
  UPDATE players
  SET gamecoin_balance = gamecoin_balance + COALESCE(v_gift.reward_gamecoin, 0),
      crypto_balance = crypto_balance + COALESCE(v_gift.reward_crypto, 0),
      total_crypto_earned = COALESCE(total_crypto_earned, 0) + COALESCE(v_gift.reward_crypto, 0),
      energy = LEAST(v_effective_max_energy, energy + COALESCE(v_gift.reward_energy, 0)),
      internet = LEAST(v_effective_max_internet, internet + COALESCE(v_gift.reward_internet, 0))
  WHERE id = p_player_id;

  -- Acreditar items si corresponde
  IF v_gift.reward_item_type IS NOT NULL AND v_gift.reward_item_id IS NOT NULL THEN
    IF v_gift.reward_item_type = 'prepaid_card' THEN
      -- Dar tarjeta prepago
      IF EXISTS (SELECT 1 FROM prepaid_cards WHERE id = v_gift.reward_item_id) THEN
        FOR i IN 1..COALESCE(v_gift.reward_item_quantity, 1) LOOP
          INSERT INTO player_cards (player_id, card_id, code)
          VALUES (p_player_id, v_gift.reward_item_id, generate_card_code());
        END LOOP;
      END IF;
    ELSIF v_gift.reward_item_type = 'cooling' THEN
      IF EXISTS (SELECT 1 FROM cooling_items WHERE id = v_gift.reward_item_id) THEN
        INSERT INTO player_inventory (player_id, item_type, item_id, quantity)
        VALUES (p_player_id, 'cooling', v_gift.reward_item_id, COALESCE(v_gift.reward_item_quantity, 1))
        ON CONFLICT (player_id, item_type, item_id)
        DO UPDATE SET quantity = player_inventory.quantity + COALESCE(v_gift.reward_item_quantity, 1);
      END IF;
    ELSIF v_gift.reward_item_type = 'boost' THEN
      IF EXISTS (SELECT 1 FROM boost_items WHERE id = v_gift.reward_item_id) THEN
        INSERT INTO player_boosts (player_id, boost_id, quantity)
        VALUES (p_player_id, v_gift.reward_item_id, COALESCE(v_gift.reward_item_quantity, 1))
        ON CONFLICT (player_id, boost_id)
        DO UPDATE SET quantity = player_boosts.quantity + COALESCE(v_gift.reward_item_quantity, 1);
      END IF;
    ELSIF v_gift.reward_item_type = 'rig' THEN
      IF EXISTS (SELECT 1 FROM rigs WHERE id = v_gift.reward_item_id) THEN
        INSERT INTO player_rig_inventory (player_id, rig_id, quantity)
        VALUES (p_player_id, v_gift.reward_item_id, COALESCE(v_gift.reward_item_quantity, 1))
        ON CONFLICT (player_id, rig_id)
        DO UPDATE SET quantity = player_rig_inventory.quantity + COALESCE(v_gift.reward_item_quantity, 1);
      END IF;
    END IF;
  END IF;

  -- Registrar transacción
  IF COALESCE(v_gift.reward_gamecoin, 0) > 0 THEN
    INSERT INTO transactions (player_id, type, amount, currency, description)
    VALUES (p_player_id, 'gift_claimed', v_gift.reward_gamecoin, 'gamecoin', 'Regalo: ' || v_gift.title);
  END IF;
  IF COALESCE(v_gift.reward_crypto, 0) > 0 THEN
    INSERT INTO transactions (player_id, type, amount, currency, description)
    VALUES (p_player_id, 'gift_claimed', v_gift.reward_crypto, 'crypto', 'Regalo: ' || v_gift.title);
  END IF;

  RETURN json_build_object(
    'success', true,
    'title', v_gift.title,
    'description', v_gift.description,
    'icon', v_gift.icon,
    'gamecoin', COALESCE(v_gift.reward_gamecoin, 0),
    'crypto', COALESCE(v_gift.reward_crypto, 0),
    'energy', COALESCE(v_gift.reward_energy, 0),
    'internet', COALESCE(v_gift.reward_internet, 0),
    'itemType', v_gift.reward_item_type,
    'itemId', v_gift.reward_item_id,
    'itemQuantity', COALESCE(v_gift.reward_item_quantity, 1)
  );
END;
$$;

-- Admin: Enviar regalo - usa @everyone para todos o un UUID para un jugador específico
CREATE OR REPLACE FUNCTION send_gift(
  p_target TEXT,              -- '@everyone' para todos o UUID del jugador
  p_title TEXT DEFAULT 'Gift',
  p_description TEXT DEFAULT NULL,
  p_icon TEXT DEFAULT '🎁',
  p_gamecoin DECIMAL DEFAULT 0,
  p_crypto DECIMAL DEFAULT 0,
  p_energy DECIMAL DEFAULT 0,
  p_internet DECIMAL DEFAULT 0,
  p_item_type TEXT DEFAULT NULL,
  p_item_id TEXT DEFAULT NULL,
  p_item_quantity INTEGER DEFAULT 1,
  p_expires_at TIMESTAMPTZ DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_count INTEGER;
  v_gift_id UUID;
  v_player_id UUID;
BEGIN
  IF LOWER(TRIM(p_target)) = '@everyone' THEN
    -- Enviar a todos los jugadores
    INSERT INTO player_gifts (
      player_id, title, description, icon,
      reward_gamecoin, reward_crypto, reward_energy, reward_internet,
      reward_item_type, reward_item_id, reward_item_quantity, expires_at
    )
    SELECT
      p.id, p_title, p_description, p_icon,
      p_gamecoin, p_crypto, p_energy, p_internet,
      p_item_type, p_item_id, p_item_quantity, p_expires_at
    FROM players p;

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN json_build_object('success', true, 'target', '@everyone', 'count', v_count);
  ELSE
    -- Enviar a un jugador específico
    BEGIN
      v_player_id := p_target::UUID;
    EXCEPTION WHEN OTHERS THEN
      RETURN json_build_object('success', false, 'error', 'Invalid target. Use @everyone or a valid UUID.');
    END;

    IF NOT EXISTS (SELECT 1 FROM players WHERE id = v_player_id) THEN
      RETURN json_build_object('success', false, 'error', 'Player not found');
    END IF;

    INSERT INTO player_gifts (
      player_id, title, description, icon,
      reward_gamecoin, reward_crypto, reward_energy, reward_internet,
      reward_item_type, reward_item_id, reward_item_quantity, expires_at
    ) VALUES (
      v_player_id, p_title, p_description, p_icon,
      p_gamecoin, p_crypto, p_energy, p_internet,
      p_item_type, p_item_id, p_item_quantity, p_expires_at
    ) RETURNING id INTO v_gift_id;

    RETURN json_build_object('success', true, 'target', v_player_id, 'gift_id', v_gift_id);
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION get_pending_gifts TO authenticated;
GRANT EXECUTE ON FUNCTION claim_gift TO authenticated;

-- =====================================================
-- CRAFTING LORDS - MINI-JUEGO DE RECOLECCIÓN Y CRAFTEO
-- =====================================================

-- Catálogo de elementos recolectables
CREATE TABLE IF NOT EXISTS crafting_elements (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  icon TEXT NOT NULL DEFAULT '',
  zone_type TEXT NOT NULL CHECK (zone_type IN ('forest', 'mine', 'meadow', 'swamp')),
  rarity TEXT NOT NULL DEFAULT 'common' CHECK (rarity IN ('common', 'uncommon', 'rare', 'epic')),
  taps_required INTEGER NOT NULL DEFAULT 1,
  base_gamecoin_value INTEGER DEFAULT 0,
  requires_element TEXT DEFAULT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE crafting_elements ADD COLUMN IF NOT EXISTS requires_element TEXT DEFAULT NULL;

CREATE INDEX IF NOT EXISTS idx_crafting_elements_zone ON crafting_elements(zone_type);

-- Recetas de crafteo
CREATE TABLE IF NOT EXISTS crafting_recipes (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT DEFAULT '',
  category TEXT NOT NULL CHECK (category IN ('cooling', 'boost', 'card', 'sellable')),
  output_item_type TEXT NOT NULL,
  output_item_id TEXT DEFAULT NULL,
  output_quantity INTEGER DEFAULT 1,
  gamecoin_reward INTEGER DEFAULT 0,
  rarity TEXT DEFAULT 'common',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Ingredientes de recetas
CREATE TABLE IF NOT EXISTS crafting_recipe_ingredients (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recipe_id TEXT NOT NULL REFERENCES crafting_recipes(id) ON DELETE CASCADE,
  element_id TEXT NOT NULL REFERENCES crafting_elements(id),
  quantity INTEGER NOT NULL DEFAULT 1
);

CREATE INDEX IF NOT EXISTS idx_recipe_ingredients_recipe ON crafting_recipe_ingredients(recipe_id);

-- Sesiones de crafting del jugador
CREATE TABLE IF NOT EXISTS player_crafting_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  zone_type TEXT NOT NULL,
  grid_config JSONB NOT NULL,
  elements_collected INTEGER DEFAULT 0,
  total_elements INTEGER DEFAULT 16,
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'completed', 'abandoned')),
  started_at TIMESTAMPTZ DEFAULT NOW(),
  completed_at TIMESTAMPTZ DEFAULT NULL,
  rewards_claimed BOOLEAN DEFAULT false,
  gamecoin_reward INTEGER DEFAULT 0,
  items_rewarded JSONB DEFAULT '[]'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_crafting_sessions_player ON player_crafting_sessions(player_id);
CREATE INDEX IF NOT EXISTS idx_crafting_sessions_status ON player_crafting_sessions(player_id, status);

-- Inventario de materiales de crafting
CREATE TABLE IF NOT EXISTS player_crafting_inventory (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  element_id TEXT NOT NULL REFERENCES crafting_elements(id),
  quantity INTEGER DEFAULT 1,
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(player_id, element_id)
);

CREATE INDEX IF NOT EXISTS idx_crafting_inventory_player ON player_crafting_inventory(player_id);

-- Cooldown entre sesiones
CREATE TABLE IF NOT EXISTS player_crafting_cooldown (
  player_id UUID PRIMARY KEY REFERENCES players(id) ON DELETE CASCADE,
  last_session_completed TIMESTAMPTZ DEFAULT NULL,
  cooldown_hours INTEGER DEFAULT 4,
  sessions_completed INTEGER DEFAULT 0
);

-- =====================================================
-- CRAFTING LORDS - SEED DATA
-- =====================================================

-- Elementos del Bosque
INSERT INTO crafting_elements (id, name, icon, zone_type, rarity, taps_required, base_gamecoin_value, requires_element) VALUES
('leaves', 'Leaves', '🍃', 'forest', 'common', 1, 2, NULL),
('fruits', 'Fruits', '🍎', 'forest', 'common', 1, 3, NULL),
('wood', 'Wood', '🪵', 'forest', 'common', 2, 5, 'leaves'),
('mushrooms', 'Mushrooms', '🍄', 'forest', 'uncommon', 1, 8, 'leaves'),
('vines', 'Vines', '🌿', 'forest', 'uncommon', 2, 7, 'wood'),
('bark', 'Bark', '🪵', 'forest', 'common', 3, 10, 'wood')
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name, icon = EXCLUDED.icon, zone_type = EXCLUDED.zone_type,
  rarity = EXCLUDED.rarity, taps_required = EXCLUDED.taps_required, base_gamecoin_value = EXCLUDED.base_gamecoin_value,
  requires_element = EXCLUDED.requires_element;

-- Elementos de la Mina
INSERT INTO crafting_elements (id, name, icon, zone_type, rarity, taps_required, base_gamecoin_value, requires_element) VALUES
('coal', 'Coal', '⬛', 'mine', 'common', 2, 4, NULL),
('ore', 'Ore', '⛏️', 'mine', 'common', 3, 8, NULL),
('rocks', 'Rocks', '🪨', 'mine', 'common', 3, 5, 'ore'),
('minerals', 'Minerals', '💎', 'mine', 'uncommon', 2, 10, 'rocks'),
('gems', 'Gems', '🔮', 'mine', 'rare', 4, 25, 'minerals'),
('crystite', 'Crystite', '✨', 'mine', 'epic', 5, 50, 'gems')
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name, icon = EXCLUDED.icon, zone_type = EXCLUDED.zone_type,
  rarity = EXCLUDED.rarity, taps_required = EXCLUDED.taps_required, base_gamecoin_value = EXCLUDED.base_gamecoin_value,
  requires_element = EXCLUDED.requires_element;

-- Elementos de la Pradera
INSERT INTO crafting_elements (id, name, icon, zone_type, rarity, taps_required, base_gamecoin_value, requires_element) VALUES
('seeds', 'Seeds', '🌱', 'meadow', 'common', 1, 2, NULL),
('flowers', 'Flowers', '🌸', 'meadow', 'common', 1, 3, NULL),
('berries', 'Berries', '🫐', 'meadow', 'common', 1, 4, 'seeds'),
('herbs', 'Herbs', '🌿', 'meadow', 'uncommon', 1, 8, 'flowers'),
('feathers', 'Feathers', '🪶', 'meadow', 'uncommon', 2, 12, 'herbs'),
('honey', 'Honey', '🍯', 'meadow', 'rare', 3, 20, 'flowers')
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name, icon = EXCLUDED.icon, zone_type = EXCLUDED.zone_type,
  rarity = EXCLUDED.rarity, taps_required = EXCLUDED.taps_required, base_gamecoin_value = EXCLUDED.base_gamecoin_value,
  requires_element = EXCLUDED.requires_element;

-- Elementos del Pantano
INSERT INTO crafting_elements (id, name, icon, zone_type, rarity, taps_required, base_gamecoin_value, requires_element) VALUES
('moss', 'Moss', '🧩', 'swamp', 'common', 1, 3, NULL),
('roots', 'Roots', '🌳', 'swamp', 'common', 2, 6, NULL),
('mud_clay', 'Mud Clay', '🟤', 'swamp', 'common', 2, 5, 'roots'),
('slime', 'Slime', '🟢', 'swamp', 'uncommon', 2, 10, 'moss'),
('crystals', 'Crystals', '💠', 'swamp', 'rare', 4, 30, 'mud_clay'),
('ancient_wood', 'Ancient Wood', '🪵', 'swamp', 'epic', 5, 45, 'crystals')
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name, icon = EXCLUDED.icon, zone_type = EXCLUDED.zone_type,
  rarity = EXCLUDED.rarity, taps_required = EXCLUDED.taps_required, base_gamecoin_value = EXCLUDED.base_gamecoin_value,
  requires_element = EXCLUDED.requires_element;

-- Recetas de Cooling
INSERT INTO crafting_recipes (id, name, description, category, output_item_type, output_item_id, output_quantity, gamecoin_reward, rarity) VALUES
('craft_fan_basic', 'Craft Basic Fan', 'A simple fan from forest materials', 'cooling', 'cooling_item', 'fan_basic', 1, 0, 'common'),
('craft_heatsink', 'Craft Heatsink', 'A heatsink from mined minerals', 'cooling', 'cooling_item', 'heatsink', 1, 0, 'uncommon')
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, description = EXCLUDED.description, category = EXCLUDED.category,
  output_item_type = EXCLUDED.output_item_type, output_item_id = EXCLUDED.output_item_id;

-- Recetas de Boost
INSERT INTO crafting_recipes (id, name, description, category, output_item_type, output_item_id, output_quantity, gamecoin_reward, rarity) VALUES
('craft_hashrate_small', 'Brew Hash Potion', 'Temporary hashrate boost', 'boost', 'boost_item', 'hashrate_small', 1, 0, 'uncommon'),
('craft_energy_saver', 'Energy Elixir', 'Reduces energy consumption', 'boost', 'boost_item', 'energy_saver_small', 1, 0, 'uncommon')
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, description = EXCLUDED.description, category = EXCLUDED.category,
  output_item_type = EXCLUDED.output_item_type, output_item_id = EXCLUDED.output_item_id;

-- Recetas de Tarjetas
INSERT INTO crafting_recipes (id, name, description, category, output_item_type, output_item_id, output_quantity, gamecoin_reward, rarity) VALUES
('craft_energy_card', 'Forge Energy Card', 'A basic energy recharge', 'card', 'prepaid_card', 'energy_small', 1, 0, 'rare'),
('craft_internet_card', 'Forge Internet Card', 'A basic internet recharge', 'card', 'prepaid_card', 'internet_small', 1, 0, 'rare')
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, description = EXCLUDED.description, category = EXCLUDED.category,
  output_item_type = EXCLUDED.output_item_type, output_item_id = EXCLUDED.output_item_id;

-- Recetas vendibles (GameCoin)
INSERT INTO crafting_recipes (id, name, description, category, output_item_type, output_item_id, output_quantity, gamecoin_reward, rarity) VALUES
('sell_forest_bundle', 'Forest Bundle', 'Sell a bundle of forest goods', 'sellable', 'gamecoin', NULL, 0, 100, 'common'),
('sell_mineral_pack', 'Mineral Pack', 'Sell a pack of minerals', 'sellable', 'gamecoin', NULL, 0, 150, 'uncommon'),
('sell_swamp_treasure', 'Swamp Treasure', 'Rare swamp materials', 'sellable', 'gamecoin', NULL, 0, 250, 'rare')
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, description = EXCLUDED.description, gamecoin_reward = EXCLUDED.gamecoin_reward;

-- Ingredientes de recetas (limpiar y reinsertar)
DELETE FROM crafting_recipe_ingredients;

INSERT INTO crafting_recipe_ingredients (recipe_id, element_id, quantity) VALUES
-- Cooling
('craft_fan_basic', 'wood', 3), ('craft_fan_basic', 'leaves', 2), ('craft_fan_basic', 'vines', 1),
('craft_heatsink', 'ore', 4), ('craft_heatsink', 'minerals', 2), ('craft_heatsink', 'coal', 2),
-- Boost
('craft_hashrate_small', 'crystite', 1), ('craft_hashrate_small', 'herbs', 3), ('craft_hashrate_small', 'honey', 1),
('craft_energy_saver', 'flowers', 4), ('craft_energy_saver', 'berries', 2), ('craft_energy_saver', 'moss', 2),
-- Cards
('craft_energy_card', 'crystals', 1), ('craft_energy_card', 'ancient_wood', 1), ('craft_energy_card', 'slime', 2),
('craft_internet_card', 'gems', 1), ('craft_internet_card', 'feathers', 3), ('craft_internet_card', 'seeds', 2),
-- Sellable
('sell_forest_bundle', 'wood', 2), ('sell_forest_bundle', 'fruits', 2), ('sell_forest_bundle', 'bark', 1),
('sell_mineral_pack', 'rocks', 2), ('sell_mineral_pack', 'ore', 2), ('sell_mineral_pack', 'minerals', 1),
('sell_swamp_treasure', 'roots', 2), ('sell_swamp_treasure', 'crystals', 1), ('sell_swamp_treasure', 'ancient_wood', 1);

-- =====================================================
-- CRAFTING LORDS - FUNCIONES RPC
-- =====================================================

-- Drop funciones existentes

-- Iniciar sesión de crafting
CREATE OR REPLACE FUNCTION start_crafting_session(p_player_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_cooldown player_crafting_cooldown%ROWTYPE;
  v_cooldown_remaining NUMERIC;
  v_zone_type TEXT;
  v_zone_types TEXT[] := ARRAY['forest', 'mine', 'meadow', 'swamp'];
  v_elements RECORD;
  v_grid JSONB := '[]'::JSONB;
  v_element_pool TEXT[];
  v_element_record RECORD;
  v_picked_id TEXT;
  v_session_id UUID;
  v_existing_session UUID;
  v_rarity_weights JSONB;
  v_element_ids TEXT[];
  v_element_icons TEXT[];
  v_element_names TEXT[];
  v_element_taps INTEGER[];
  v_element_rarities TEXT[];
  v_element_requires TEXT[];
  v_pool_size INTEGER;
  v_rand_idx INTEGER;
  v_has_free BOOLEAN;
  v_free_indices INTEGER[];
  v_existing_full player_crafting_sessions%ROWTYPE;
  i INTEGER;
BEGIN
  -- Verificar si tiene sesión activa (lock para evitar race conditions)
  SELECT * INTO v_existing_full
  FROM player_crafting_sessions
  WHERE player_id = p_player_id AND status = 'active'
  FOR UPDATE SKIP LOCKED
  LIMIT 1;

  IF v_existing_full IS NOT NULL THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Ya tienes una sesión activa',
      'session_id', v_existing_full.id,
      'session', json_build_object(
        'id', v_existing_full.id,
        'zone_type', v_existing_full.zone_type,
        'grid', v_existing_full.grid_config,
        'elements_collected', v_existing_full.elements_collected,
        'total_elements', v_existing_full.total_elements,
        'status', v_existing_full.status,
        'started_at', v_existing_full.started_at
      )
    );
  END IF;

  -- Verificar cooldown
  SELECT * INTO v_cooldown FROM player_crafting_cooldown WHERE player_id = p_player_id;

  IF v_cooldown IS NOT NULL AND v_cooldown.last_session_completed IS NOT NULL THEN
    v_cooldown_remaining := EXTRACT(EPOCH FROM (
      v_cooldown.last_session_completed + (COALESCE(v_cooldown.cooldown_hours, 4) || ' hours')::INTERVAL - NOW()
    ));

    IF v_cooldown_remaining > 0 THEN
      RETURN json_build_object(
        'success', false,
        'error', 'cooldown_active',
        'cooldown_remaining_seconds', CEIL(v_cooldown_remaining),
        'next_available_at', v_cooldown.last_session_completed + (COALESCE(v_cooldown.cooldown_hours, 4) || ' hours')::INTERVAL
      );
    END IF;
  END IF;

  -- Seleccionar zona aleatoria
  v_zone_type := v_zone_types[1 + FLOOR(RANDOM() * 4)];

  -- Obtener pool de elementos de esta zona
  SELECT
    array_agg(id ORDER BY rarity, id),
    array_agg(icon ORDER BY rarity, id),
    array_agg(name ORDER BY rarity, id),
    array_agg(taps_required ORDER BY rarity, id),
    array_agg(rarity ORDER BY rarity, id),
    array_agg(COALESCE(requires_element, '') ORDER BY rarity, id)
  INTO v_element_ids, v_element_icons, v_element_names, v_element_taps, v_element_rarities, v_element_requires
  FROM crafting_elements
  WHERE zone_type = v_zone_type;

  v_pool_size := array_length(v_element_ids, 1);

  IF v_pool_size IS NULL OR v_pool_size = 0 THEN
    RETURN json_build_object('success', false, 'error', 'No hay elementos para esta zona');
  END IF;

  -- Obtener indices de elementos libres (sin requisito)
  v_free_indices := ARRAY[]::INTEGER[];
  FOR i IN 1..v_pool_size LOOP
    IF v_element_requires[i] = '' THEN
      v_free_indices := v_free_indices || i;
    END IF;
  END LOOP;

  -- Generar grid de 16 celdas con elementos aleatorios del pool
  v_has_free := false;
  FOR i IN 0..15 LOOP
    v_rand_idx := 1 + FLOOR(RANDOM() * v_pool_size);
    IF v_element_requires[v_rand_idx] = '' THEN
      v_has_free := true;
    END IF;
    v_grid := v_grid || jsonb_build_object(
      'index', i,
      'element_id', v_element_ids[v_rand_idx],
      'icon', v_element_icons[v_rand_idx],
      'name', v_element_names[v_rand_idx],
      'taps_required', v_element_taps[v_rand_idx],
      'taps_done', 0,
      'collected', false,
      'rarity', v_element_rarities[v_rand_idx],
      'requires_element', CASE WHEN v_element_requires[v_rand_idx] = '' THEN NULL ELSE v_element_requires[v_rand_idx] END
    );
  END LOOP;

  -- Garantizar al menos un elemento libre en el grid
  IF NOT v_has_free AND array_length(v_free_indices, 1) > 0 THEN
    v_rand_idx := v_free_indices[1 + FLOOR(RANDOM() * array_length(v_free_indices, 1))];
    v_grid := jsonb_set(v_grid, ARRAY['0'], jsonb_build_object(
      'index', 0,
      'element_id', v_element_ids[v_rand_idx],
      'icon', v_element_icons[v_rand_idx],
      'name', v_element_names[v_rand_idx],
      'taps_required', v_element_taps[v_rand_idx],
      'taps_done', 0,
      'collected', false,
      'rarity', v_element_rarities[v_rand_idx],
      'requires_element', NULL
    ));
  END IF;

  -- Crear sesión
  INSERT INTO player_crafting_sessions (player_id, zone_type, grid_config, elements_collected, total_elements, status)
  VALUES (p_player_id, v_zone_type, v_grid, 0, 16, 'active')
  RETURNING id INTO v_session_id;

  RETURN json_build_object(
    'success', true,
    'session_id', v_session_id,
    'zone_type', v_zone_type,
    'grid', v_grid
  );
END;
$$;

-- Tap en un elemento del grid
CREATE OR REPLACE FUNCTION tap_crafting_element(p_player_id UUID, p_session_id UUID, p_cell_index INTEGER)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_session player_crafting_sessions%ROWTYPE;
  v_cell JSONB;
  v_taps_done INTEGER;
  v_taps_required INTEGER;
  v_element_id TEXT;
  v_collected BOOLEAN;
  v_new_grid JSONB;
  v_total_collected INTEGER;
  v_gamecoin_reward INTEGER := 0;
  v_bonus_items JSONB := '[]'::JSONB;
  v_element_value INTEGER;
  v_requires TEXT;
  v_dependency_met BOOLEAN;
BEGIN
  -- Validar índice
  IF p_cell_index < 0 OR p_cell_index > 15 THEN
    RETURN json_build_object('success', false, 'error', 'Índice de celda inválido');
  END IF;

  -- Obtener sesión
  SELECT * INTO v_session
  FROM player_crafting_sessions
  WHERE id = p_session_id AND player_id = p_player_id AND status = 'active';

  IF v_session IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Sesión no encontrada o no activa');
  END IF;

  -- Obtener celda
  v_cell := v_session.grid_config->p_cell_index;

  IF v_cell IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Celda no encontrada');
  END IF;

  -- Verificar si ya fue recolectada
  IF (v_cell->>'collected')::BOOLEAN THEN
    RETURN json_build_object('success', false, 'error', 'already_collected');
  END IF;

  -- Verificar dependencia de elemento
  v_requires := v_cell->>'requires_element';
  IF v_requires IS NOT NULL AND v_requires != '' THEN
    SELECT EXISTS (
      SELECT 1 FROM jsonb_array_elements(v_session.grid_config) AS c
      WHERE c->>'element_id' = v_requires AND (c->>'collected')::BOOLEAN = true
    ) INTO v_dependency_met;

    IF NOT v_dependency_met THEN
      RETURN json_build_object('success', false, 'error', 'element_locked', 'requires_element', v_requires);
    END IF;
  END IF;

  v_taps_done := (v_cell->>'taps_done')::INTEGER + 1;
  v_taps_required := (v_cell->>'taps_required')::INTEGER;
  v_element_id := v_cell->>'element_id';
  v_collected := v_taps_done >= v_taps_required;

  -- Actualizar celda en grid_config
  v_new_grid := jsonb_set(
    v_session.grid_config,
    ARRAY[p_cell_index::TEXT],
    jsonb_set(
      jsonb_set(v_cell, '{taps_done}', to_jsonb(v_taps_done)),
      '{collected}', to_jsonb(v_collected)
    )
  );

  -- Si se recolectó el elemento
  IF v_collected THEN
    -- Agregar al inventario de crafting
    INSERT INTO player_crafting_inventory (player_id, element_id, quantity)
    VALUES (p_player_id, v_element_id, 1)
    ON CONFLICT (player_id, element_id)
    DO UPDATE SET quantity = player_crafting_inventory.quantity + 1, updated_at = NOW();

    v_total_collected := v_session.elements_collected + 1;

    -- Verificar si completó la zona
    IF v_total_collected >= v_session.total_elements THEN
      -- Calcular recompensa base: suma de valores de todos los elementos recolectados
      SELECT COALESCE(SUM(ce.base_gamecoin_value), 50)
      INTO v_gamecoin_reward
      FROM jsonb_array_elements(v_new_grid) AS cell
      JOIN crafting_elements ce ON ce.id = cell->>'element_id';

      -- Bonus por zona completada
      v_gamecoin_reward := v_gamecoin_reward + 50;

      -- Marcar sesión como completada
      UPDATE player_crafting_sessions
      SET grid_config = v_new_grid,
          elements_collected = v_total_collected,
          status = 'completed',
          completed_at = NOW(),
          gamecoin_reward = v_gamecoin_reward
      WHERE id = p_session_id;

      -- Dar recompensa de GameCoin
      UPDATE players
      SET gamecoin_balance = gamecoin_balance + v_gamecoin_reward
      WHERE id = p_player_id;

      -- Registrar transacción
      INSERT INTO transactions (player_id, type, amount, currency, description)
      VALUES (p_player_id, 'crafting_reward', v_gamecoin_reward, 'gamecoin',
              'Zona completada: ' || v_session.zone_type);

      -- Actualizar cooldown
      INSERT INTO player_crafting_cooldown (player_id, last_session_completed, sessions_completed)
      VALUES (p_player_id, NOW(), 1)
      ON CONFLICT (player_id)
      DO UPDATE SET last_session_completed = NOW(),
                    sessions_completed = player_crafting_cooldown.sessions_completed + 1;

      -- Actualizar misiones
      PERFORM update_mission_progress(p_player_id, 'crafting_session', 1);

      RETURN json_build_object(
        'success', true,
        'cell_state', json_build_object('taps_done', v_taps_done, 'collected', true),
        'element_collected', true,
        'element_id', v_element_id,
        'session_completed', true,
        'rewards', json_build_object(
          'gamecoin', v_gamecoin_reward,
          'bonus_items', v_bonus_items
        )
      );
    ELSE
      -- Solo actualizar grid y contador
      UPDATE player_crafting_sessions
      SET grid_config = v_new_grid,
          elements_collected = v_total_collected
      WHERE id = p_session_id;

      RETURN json_build_object(
        'success', true,
        'cell_state', json_build_object('taps_done', v_taps_done, 'collected', true),
        'element_collected', true,
        'element_id', v_element_id,
        'session_completed', false
      );
    END IF;
  ELSE
    -- Solo tap, no recolectado aún
    UPDATE player_crafting_sessions
    SET grid_config = v_new_grid
    WHERE id = p_session_id;

    RETURN json_build_object(
      'success', true,
      'cell_state', json_build_object('taps_done', v_taps_done, 'collected', false),
      'element_collected', false,
      'session_completed', false
    );
  END IF;
END;
$$;

-- Obtener sesión activa o estado de cooldown
CREATE OR REPLACE FUNCTION get_crafting_session(p_player_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_session player_crafting_sessions%ROWTYPE;
  v_cooldown player_crafting_cooldown%ROWTYPE;
  v_cooldown_remaining NUMERIC := 0;
  v_can_start BOOLEAN := true;
BEGIN
  -- Buscar sesión activa (query simple sin ORDER BY para máxima compatibilidad)
  SELECT * INTO v_session
  FROM player_crafting_sessions
  WHERE player_id = p_player_id AND status = 'active'
  LIMIT 1;

  -- Verificar cooldown
  SELECT * INTO v_cooldown FROM player_crafting_cooldown WHERE player_id = p_player_id;

  IF v_cooldown IS NOT NULL AND v_cooldown.last_session_completed IS NOT NULL THEN
    v_cooldown_remaining := EXTRACT(EPOCH FROM (
      v_cooldown.last_session_completed + (COALESCE(v_cooldown.cooldown_hours, 4) || ' hours')::INTERVAL - NOW()
    ));

    IF v_cooldown_remaining > 0 THEN
      v_can_start := false;
    ELSE
      v_cooldown_remaining := 0;
    END IF;
  END IF;

  IF v_session IS NOT NULL THEN
    RETURN json_build_object(
      'success', true,
      'has_session', true,
      'session', json_build_object(
        'id', v_session.id,
        'zone_type', v_session.zone_type,
        'grid', v_session.grid_config,
        'elements_collected', v_session.elements_collected,
        'total_elements', v_session.total_elements,
        'status', v_session.status,
        'started_at', v_session.started_at
      ),
      'cooldown_remaining_seconds', 0,
      'can_start', false,
      'sessions_completed', COALESCE(v_cooldown.sessions_completed, 0)
    );
  ELSE
    RETURN json_build_object(
      'success', true,
      'has_session', false,
      'session', NULL,
      'cooldown_remaining_seconds', GREATEST(0, CEIL(v_cooldown_remaining)),
      'can_start', v_can_start,
      'sessions_completed', COALESCE(v_cooldown.sessions_completed, 0)
    );
  END IF;
END;
$$;

-- Obtener inventario de crafting
CREATE OR REPLACE FUNCTION get_crafting_inventory(p_player_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN json_build_object(
    'success', true,
    'items', (
      SELECT COALESCE(json_agg(row_to_json(t) ORDER BY t.zone_type, t.rarity, t.name), '[]'::JSON)
      FROM (
        SELECT pci.element_id, ce.name, ce.icon, ce.zone_type, ce.rarity,
               pci.quantity, ce.base_gamecoin_value, ce.taps_required
        FROM player_crafting_inventory pci
        JOIN crafting_elements ce ON ce.id = pci.element_id
        WHERE pci.player_id = p_player_id AND pci.quantity > 0
      ) t
    )
  );
END;
$$;

-- Obtener todas las recetas con ingredientes
CREATE OR REPLACE FUNCTION get_crafting_recipes()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN json_build_object(
    'success', true,
    'recipes', (
      SELECT COALESCE(json_agg(row_to_json(r) ORDER BY r.category, r.rarity, r.name), '[]'::JSON)
      FROM (
        SELECT cr.id, cr.name, cr.description, cr.category, cr.output_item_type,
               cr.output_item_id, cr.output_quantity, cr.gamecoin_reward, cr.rarity,
               (
                 SELECT json_agg(json_build_object(
                   'element_id', cri.element_id,
                   'name', ce.name,
                   'icon', ce.icon,
                   'quantity', cri.quantity
                 ))
                 FROM crafting_recipe_ingredients cri
                 JOIN crafting_elements ce ON ce.id = cri.element_id
                 WHERE cri.recipe_id = cr.id
               ) as ingredients
        FROM crafting_recipes cr
      ) r
    )
  );
END;
$$;

-- Craftear una receta
CREATE OR REPLACE FUNCTION craft_recipe(p_player_id UUID, p_recipe_id TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_recipe crafting_recipes%ROWTYPE;
  v_ingredient RECORD;
  v_owned_qty INTEGER;
  v_output_name TEXT;
BEGIN
  -- Obtener receta
  SELECT * INTO v_recipe FROM crafting_recipes WHERE id = p_recipe_id;
  IF v_recipe IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Receta no encontrada');
  END IF;

  -- Verificar que tiene todos los ingredientes
  FOR v_ingredient IN
    SELECT cri.element_id, cri.quantity, ce.name
    FROM crafting_recipe_ingredients cri
    JOIN crafting_elements ce ON ce.id = cri.element_id
    WHERE cri.recipe_id = p_recipe_id
  LOOP
    SELECT COALESCE(quantity, 0) INTO v_owned_qty
    FROM player_crafting_inventory
    WHERE player_id = p_player_id AND element_id = v_ingredient.element_id;

    IF v_owned_qty IS NULL OR v_owned_qty < v_ingredient.quantity THEN
      RETURN json_build_object(
        'success', false,
        'error', 'Materiales insuficientes',
        'missing', v_ingredient.name,
        'needed', v_ingredient.quantity,
        'owned', COALESCE(v_owned_qty, 0)
      );
    END IF;
  END LOOP;

  -- Descontar ingredientes
  FOR v_ingredient IN
    SELECT element_id, quantity
    FROM crafting_recipe_ingredients
    WHERE recipe_id = p_recipe_id
  LOOP
    UPDATE player_crafting_inventory
    SET quantity = quantity - v_ingredient.quantity, updated_at = NOW()
    WHERE player_id = p_player_id AND element_id = v_ingredient.element_id;

    -- Eliminar filas con cantidad 0
    DELETE FROM player_crafting_inventory
    WHERE player_id = p_player_id AND element_id = v_ingredient.element_id AND quantity <= 0;
  END LOOP;

  -- Crear output según tipo
  IF v_recipe.output_item_type = 'gamecoin' THEN
    -- Dar GameCoin
    UPDATE players
    SET gamecoin_balance = gamecoin_balance + v_recipe.gamecoin_reward
    WHERE id = p_player_id;

    INSERT INTO transactions (player_id, type, amount, currency, description)
    VALUES (p_player_id, 'crafting_sell', v_recipe.gamecoin_reward, 'gamecoin',
            'Venta de materiales: ' || v_recipe.name);

    v_output_name := v_recipe.gamecoin_reward || ' GameCoin';

  ELSIF v_recipe.output_item_type = 'cooling_item' THEN
    -- Agregar cooling al inventario principal
    INSERT INTO player_inventory (player_id, item_type, item_id, quantity)
    VALUES (p_player_id, 'cooling', v_recipe.output_item_id, v_recipe.output_quantity)
    ON CONFLICT (player_id, item_type, item_id)
    DO UPDATE SET quantity = player_inventory.quantity + v_recipe.output_quantity;

    v_output_name := v_recipe.name;

  ELSIF v_recipe.output_item_type = 'boost_item' THEN
    -- Agregar boost al inventario
    INSERT INTO player_boosts (player_id, boost_id, quantity)
    VALUES (p_player_id, v_recipe.output_item_id, v_recipe.output_quantity)
    ON CONFLICT (player_id, boost_id)
    DO UPDATE SET quantity = player_boosts.quantity + v_recipe.output_quantity;

    v_output_name := v_recipe.name;

  ELSIF v_recipe.output_item_type = 'prepaid_card' THEN
    -- Crear tarjeta prepago
    INSERT INTO player_cards (player_id, card_id, code)
    VALUES (p_player_id, v_recipe.output_item_id, generate_card_code());

    v_output_name := v_recipe.name;
  END IF;

  -- Registrar transacción de crafteo
  INSERT INTO transactions (player_id, type, amount, currency, description)
  VALUES (p_player_id, 'crafting_craft', 0, 'gamecoin', 'Crafted: ' || v_recipe.name);

  RETURN json_build_object(
    'success', true,
    'crafted_item', v_output_name,
    'recipe', v_recipe.name,
    'output_type', v_recipe.output_item_type,
    'output_id', v_recipe.output_item_id,
    'gamecoin_reward', v_recipe.gamecoin_reward
  );
END;
$$;

-- Eliminar elementos del inventario de crafting
CREATE OR REPLACE FUNCTION delete_crafting_element(p_player_id UUID, p_element_id TEXT, p_quantity INTEGER)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_current_qty INTEGER;
BEGIN
  SELECT quantity INTO v_current_qty
  FROM player_crafting_inventory
  WHERE player_id = p_player_id AND element_id = p_element_id;

  IF v_current_qty IS NULL OR v_current_qty <= 0 THEN
    RETURN json_build_object('success', false, 'error', 'No tienes este elemento');
  END IF;

  IF p_quantity >= v_current_qty THEN
    DELETE FROM player_crafting_inventory
    WHERE player_id = p_player_id AND element_id = p_element_id;
  ELSE
    UPDATE player_crafting_inventory
    SET quantity = quantity - p_quantity, updated_at = NOW()
    WHERE player_id = p_player_id AND element_id = p_element_id;
  END IF;

  RETURN json_build_object('success', true, 'deleted', LEAST(p_quantity, v_current_qty));
END;
$$;

-- Abandonar sesión de crafting
CREATE OR REPLACE FUNCTION abandon_crafting_session(p_player_id UUID, p_session_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_session player_crafting_sessions%ROWTYPE;
BEGIN
  SELECT * INTO v_session
  FROM player_crafting_sessions
  WHERE id = p_session_id AND player_id = p_player_id AND status = 'active';

  IF v_session IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Sesión no encontrada');
  END IF;

  UPDATE player_crafting_sessions
  SET status = 'abandoned', completed_at = NOW()
  WHERE id = p_session_id;

  RETURN json_build_object('success', true, 'message', 'Sesión abandonada');
END;
$$;

-- Grants
GRANT EXECUTE ON FUNCTION start_crafting_session TO authenticated;
GRANT EXECUTE ON FUNCTION tap_crafting_element TO authenticated;
GRANT EXECUTE ON FUNCTION get_crafting_session TO authenticated;
GRANT EXECUTE ON FUNCTION get_crafting_inventory TO authenticated;
GRANT EXECUTE ON FUNCTION get_crafting_recipes TO authenticated;
GRANT EXECUTE ON FUNCTION craft_recipe TO authenticated;
GRANT EXECUTE ON FUNCTION delete_crafting_element TO authenticated;
GRANT EXECUTE ON FUNCTION abandon_crafting_session TO authenticated;

-- =====================================================
-- TOWER DEFENSE - TABLES
-- =====================================================

CREATE TABLE IF NOT EXISTS player_defense_progress (
  player_id UUID PRIMARY KEY REFERENCES players(id) ON DELETE CASCADE,
  max_level_completed INTEGER DEFAULT 0,
  total_games INTEGER DEFAULT 0,
  total_wins INTEGER DEFAULT 0,
  total_gc_earned INTEGER DEFAULT 0,
  total_gc_spent INTEGER DEFAULT 0,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS player_defense_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  level_number INTEGER NOT NULL,
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'completed', 'abandoned')),
  gc_spent INTEGER DEFAULT 0,
  gc_earned INTEGER DEFAULT 0,
  waves_completed INTEGER DEFAULT 0,
  started_at TIMESTAMPTZ DEFAULT NOW(),
  completed_at TIMESTAMPTZ DEFAULT NULL
);

CREATE INDEX IF NOT EXISTS idx_defense_sessions_player ON player_defense_sessions(player_id);
CREATE INDEX IF NOT EXISTS idx_defense_sessions_status ON player_defense_sessions(player_id, status);

-- RLS
ALTER TABLE player_defense_progress ENABLE ROW LEVEL SECURITY;
ALTER TABLE player_defense_sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "defense_progress_select" ON player_defense_progress;
CREATE POLICY "defense_progress_select" ON player_defense_progress FOR SELECT USING (auth.uid() = player_id);
DROP POLICY IF EXISTS "defense_progress_insert" ON player_defense_progress;
CREATE POLICY "defense_progress_insert" ON player_defense_progress FOR INSERT WITH CHECK (auth.uid() = player_id);
DROP POLICY IF EXISTS "defense_progress_update" ON player_defense_progress;
CREATE POLICY "defense_progress_update" ON player_defense_progress FOR UPDATE USING (auth.uid() = player_id);

DROP POLICY IF EXISTS "defense_sessions_select" ON player_defense_sessions;
CREATE POLICY "defense_sessions_select" ON player_defense_sessions FOR SELECT USING (auth.uid() = player_id);
DROP POLICY IF EXISTS "defense_sessions_insert" ON player_defense_sessions;
CREATE POLICY "defense_sessions_insert" ON player_defense_sessions FOR INSERT WITH CHECK (auth.uid() = player_id);
DROP POLICY IF EXISTS "defense_sessions_update" ON player_defense_sessions;
CREATE POLICY "defense_sessions_update" ON player_defense_sessions FOR UPDATE USING (auth.uid() = player_id);

-- =====================================================
-- TOWER DEFENSE - FUNCTIONS
-- =====================================================

-- Start a defense game
CREATE OR REPLACE FUNCTION start_defense_game(p_player_id UUID, p_level INTEGER)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_progress player_defense_progress%ROWTYPE;
  v_existing UUID;
  v_session_id UUID;
BEGIN
  -- Check for existing active session
  SELECT id INTO v_existing
  FROM player_defense_sessions
  WHERE player_id = p_player_id AND status = 'active'
  LIMIT 1;

  IF v_existing IS NOT NULL THEN
    RETURN json_build_object('success', false, 'error', 'Ya tienes una partida activa', 'session_id', v_existing);
  END IF;

  -- Get or create progress
  INSERT INTO player_defense_progress (player_id)
  VALUES (p_player_id)
  ON CONFLICT (player_id) DO NOTHING;

  SELECT * INTO v_progress FROM player_defense_progress WHERE player_id = p_player_id;

  -- Check level is unlocked (level 1 always unlocked, others need previous completed)
  IF p_level > 1 AND v_progress.max_level_completed < (p_level - 1) THEN
    RETURN json_build_object('success', false, 'error', 'Nivel bloqueado', 'max_level', v_progress.max_level_completed + 1);
  END IF;

  -- Create session
  INSERT INTO player_defense_sessions (player_id, level_number, status)
  VALUES (p_player_id, p_level, 'active')
  RETURNING id INTO v_session_id;

  RETURN json_build_object(
    'success', true,
    'session_id', v_session_id,
    'level_number', p_level
  );
END;
$$;

-- Buy a tower (deduct GC)
CREATE OR REPLACE FUNCTION defense_buy_tower(p_player_id UUID, p_session_id UUID, p_cost INTEGER)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_session player_defense_sessions%ROWTYPE;
  v_balance INTEGER;
BEGIN
  -- Verify session
  SELECT * INTO v_session
  FROM player_defense_sessions
  WHERE id = p_session_id AND player_id = p_player_id AND status = 'active';

  IF v_session IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Sesion no activa');
  END IF;

  -- Check balance
  SELECT gamecoin_balance INTO v_balance FROM players WHERE id = p_player_id;

  IF v_balance < p_cost THEN
    RETURN json_build_object('success', false, 'error', 'Fondos insuficientes', 'balance', v_balance);
  END IF;

  -- Deduct GC
  UPDATE players SET gamecoin_balance = gamecoin_balance - p_cost WHERE id = p_player_id;
  UPDATE player_defense_sessions SET gc_spent = gc_spent + p_cost WHERE id = p_session_id;

  SELECT gamecoin_balance INTO v_balance FROM players WHERE id = p_player_id;

  RETURN json_build_object('success', true, 'new_balance', v_balance);
END;
$$;

-- Sell a tower (refund GC)
CREATE OR REPLACE FUNCTION defense_sell_tower(p_player_id UUID, p_session_id UUID, p_refund INTEGER)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_session player_defense_sessions%ROWTYPE;
  v_balance INTEGER;
BEGIN
  SELECT * INTO v_session
  FROM player_defense_sessions
  WHERE id = p_session_id AND player_id = p_player_id AND status = 'active';

  IF v_session IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Sesion no activa');
  END IF;

  UPDATE players SET gamecoin_balance = gamecoin_balance + p_refund WHERE id = p_player_id;
  UPDATE player_defense_sessions SET gc_spent = GREATEST(0, gc_spent - p_refund) WHERE id = p_session_id;

  SELECT gamecoin_balance INTO v_balance FROM players WHERE id = p_player_id;

  RETURN json_build_object('success', true, 'new_balance', v_balance);
END;
$$;

-- Enemy killed (add GC reward)
CREATE OR REPLACE FUNCTION defense_enemy_killed(p_player_id UUID, p_session_id UUID, p_reward INTEGER)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_balance INTEGER;
BEGIN
  UPDATE players SET gamecoin_balance = gamecoin_balance + p_reward WHERE id = p_player_id;
  UPDATE player_defense_sessions SET gc_earned = gc_earned + p_reward WHERE id = p_session_id AND status = 'active';

  SELECT gamecoin_balance INTO v_balance FROM players WHERE id = p_player_id;

  RETURN json_build_object('success', true, 'new_balance', v_balance);
END;
$$;

-- Complete defense game
CREATE OR REPLACE FUNCTION complete_defense_game(
  p_player_id UUID,
  p_session_id UUID,
  p_won BOOLEAN,
  p_waves INTEGER,
  p_bonus INTEGER
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_session player_defense_sessions%ROWTYPE;
  v_balance INTEGER;
  v_level_unlocked BOOLEAN := false;
BEGIN
  SELECT * INTO v_session
  FROM player_defense_sessions
  WHERE id = p_session_id AND player_id = p_player_id AND status = 'active';

  IF v_session IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Sesion no encontrada');
  END IF;

  -- Mark session completed
  UPDATE player_defense_sessions
  SET status = 'completed',
      completed_at = NOW(),
      waves_completed = p_waves
  WHERE id = p_session_id;

  -- If won, give bonus and update progress
  IF p_won AND p_bonus > 0 THEN
    UPDATE players SET gamecoin_balance = gamecoin_balance + p_bonus WHERE id = p_player_id;
  END IF;

  -- Update progress
  UPDATE player_defense_progress
  SET total_games = total_games + 1,
      total_wins = CASE WHEN p_won THEN total_wins + 1 ELSE total_wins END,
      max_level_completed = CASE WHEN p_won AND v_session.level_number > max_level_completed
                            THEN v_session.level_number ELSE max_level_completed END,
      total_gc_earned = total_gc_earned + v_session.gc_earned + CASE WHEN p_won THEN p_bonus ELSE 0 END,
      total_gc_spent = total_gc_spent + v_session.gc_spent,
      updated_at = NOW()
  WHERE player_id = p_player_id;

  -- Check if level was unlocked
  SELECT max_level_completed >= v_session.level_number INTO v_level_unlocked
  FROM player_defense_progress WHERE player_id = p_player_id;

  -- Log transaction
  IF p_won AND p_bonus > 0 THEN
    INSERT INTO transactions (player_id, type, amount, currency, description)
    VALUES (p_player_id, 'defense_reward', p_bonus, 'gamecoin',
            'Tower Defense Level ' || v_session.level_number || ' completado');
  END IF;

  -- Update missions
  IF p_won THEN
    PERFORM update_mission_progress(p_player_id, 'defense_win', 1);
  END IF;

  SELECT gamecoin_balance INTO v_balance FROM players WHERE id = p_player_id;

  RETURN json_build_object(
    'success', true,
    'won', p_won,
    'bonus', CASE WHEN p_won THEN p_bonus ELSE 0 END,
    'new_balance', v_balance,
    'level_unlocked', v_level_unlocked,
    'waves_completed', p_waves
  );
END;
$$;

-- Get defense progress
CREATE OR REPLACE FUNCTION get_defense_progress(p_player_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_progress player_defense_progress%ROWTYPE;
  v_active_session player_defense_sessions%ROWTYPE;
BEGIN
  -- Get or create progress
  INSERT INTO player_defense_progress (player_id)
  VALUES (p_player_id)
  ON CONFLICT (player_id) DO NOTHING;

  SELECT * INTO v_progress FROM player_defense_progress WHERE player_id = p_player_id;

  -- Check for active session
  SELECT * INTO v_active_session
  FROM player_defense_sessions
  WHERE player_id = p_player_id AND status = 'active'
  LIMIT 1;

  RETURN json_build_object(
    'success', true,
    'max_level_completed', v_progress.max_level_completed,
    'total_games', v_progress.total_games,
    'total_wins', v_progress.total_wins,
    'total_gc_earned', v_progress.total_gc_earned,
    'total_gc_spent', v_progress.total_gc_spent,
    'has_active_session', v_active_session IS NOT NULL,
    'active_session_id', v_active_session.id,
    'active_level', v_active_session.level_number
  );
END;
$$;

-- Grants
GRANT EXECUTE ON FUNCTION start_defense_game TO authenticated;
GRANT EXECUTE ON FUNCTION defense_buy_tower TO authenticated;
GRANT EXECUTE ON FUNCTION defense_sell_tower TO authenticated;
GRANT EXECUTE ON FUNCTION defense_enemy_killed TO authenticated;
GRANT EXECUTE ON FUNCTION complete_defense_game TO authenticated;
GRANT EXECUTE ON FUNCTION get_defense_progress TO authenticated;

-- =====================================================
-- CARD BATTLE PVP - TABLES
-- =====================================================

CREATE TABLE IF NOT EXISTS battle_lobby (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  username TEXT NOT NULL,
  bet_amount NUMERIC, -- Nullable - set only when both players agree
  bet_currency TEXT CHECK (bet_currency IN ('GC', 'BLC', 'RON')), -- Currency type
  proposed_bet NUMERIC, -- Proposed bet amount for current challenge
  proposed_currency TEXT CHECK (proposed_currency IN ('GC', 'BLC', 'RON')), -- Proposed currency type
  challenged_by UUID REFERENCES players(id), -- Who proposed the current challenge
  challenger_username TEXT, -- Username of the challenger
  challenge_expires_at TIMESTAMPTZ, -- When the challenge expires
  status TEXT DEFAULT 'waiting' CHECK (status IN ('waiting', 'matched', 'cancelled', 'challenged')),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_battle_lobby_status ON battle_lobby(status);
CREATE INDEX IF NOT EXISTS idx_battle_lobby_player ON battle_lobby(player_id);

-- Fix: Ensure battle_lobby has all required columns (for existing tables)
ALTER TABLE battle_lobby ADD COLUMN IF NOT EXISTS bet_amount NUMERIC;
ALTER TABLE battle_lobby ADD COLUMN IF NOT EXISTS bet_currency TEXT;
ALTER TABLE battle_lobby ADD COLUMN IF NOT EXISTS proposed_bet NUMERIC;
ALTER TABLE battle_lobby ADD COLUMN IF NOT EXISTS proposed_currency TEXT;
ALTER TABLE battle_lobby ADD COLUMN IF NOT EXISTS challenged_by UUID;
ALTER TABLE battle_lobby ADD COLUMN IF NOT EXISTS challenger_username TEXT;
ALTER TABLE battle_lobby ADD COLUMN IF NOT EXISTS challenge_expires_at TIMESTAMPTZ;

-- Add foreign key constraint if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'battle_lobby_challenged_by_fkey'
  ) THEN
    ALTER TABLE battle_lobby ADD CONSTRAINT battle_lobby_challenged_by_fkey
      FOREIGN KEY (challenged_by) REFERENCES players(id);
  END IF;
END $$;

-- Update status check constraint to include 'challenged'
ALTER TABLE battle_lobby DROP CONSTRAINT IF EXISTS battle_lobby_status_check;
ALTER TABLE battle_lobby ADD CONSTRAINT battle_lobby_status_check
  CHECK (status IN ('waiting', 'matched', 'cancelled', 'challenged'));

-- Update currency check constraints
ALTER TABLE battle_lobby DROP CONSTRAINT IF EXISTS battle_lobby_bet_currency_check;
ALTER TABLE battle_lobby ADD CONSTRAINT battle_lobby_bet_currency_check
  CHECK (bet_currency IN ('GC', 'BLC', 'RON'));

ALTER TABLE battle_lobby DROP CONSTRAINT IF EXISTS battle_lobby_proposed_currency_check;
ALTER TABLE battle_lobby ADD CONSTRAINT battle_lobby_proposed_currency_check
  CHECK (proposed_currency IN ('GC', 'BLC', 'RON'));

-- Ready Room: Both players accepted, waiting for both to press "Start"
CREATE TABLE IF NOT EXISTS battle_ready_rooms (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  player1_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  player2_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  player1_username TEXT NOT NULL,
  player2_username TEXT NOT NULL,
  bet_amount NUMERIC NOT NULL,
  bet_currency TEXT NOT NULL CHECK (bet_currency IN ('GC', 'BLC', 'RON')),
  player1_ready BOOLEAN DEFAULT false,
  player2_ready BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  expires_at TIMESTAMPTZ DEFAULT NOW() + INTERVAL '5 minutes'
);

CREATE INDEX IF NOT EXISTS idx_ready_rooms_players ON battle_ready_rooms(player1_id, player2_id);

CREATE TABLE IF NOT EXISTS battle_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  player1_id UUID NOT NULL REFERENCES players(id),
  player2_id UUID NOT NULL REFERENCES players(id),
  bet_amount NUMERIC NOT NULL,
  bet_currency TEXT NOT NULL CHECK (bet_currency IN ('GC', 'BLC', 'RON')),
  current_turn UUID NOT NULL,
  turn_number INTEGER DEFAULT 1,
  turn_deadline TIMESTAMPTZ,
  player1_hp INTEGER DEFAULT 200,
  player2_hp INTEGER DEFAULT 200,
  player1_shield INTEGER DEFAULT 0,
  player2_shield INTEGER DEFAULT 0,
  game_state JSONB NOT NULL,
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'completed', 'forfeited')),
  winner_id UUID REFERENCES players(id),
  started_at TIMESTAMPTZ DEFAULT NOW(),
  completed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_battle_sessions_players ON battle_sessions(player1_id, player2_id);
CREATE INDEX IF NOT EXISTS idx_battle_sessions_status ON battle_sessions(status);

-- Ensure HP defaults are 200 (in case table was created with old defaults)
ALTER TABLE battle_sessions ALTER COLUMN player1_hp SET DEFAULT 200;
ALTER TABLE battle_sessions ALTER COLUMN player2_hp SET DEFAULT 200;

-- Ensure bet_currency column exists (for existing tables)
ALTER TABLE battle_sessions ADD COLUMN IF NOT EXISTS bet_currency TEXT;

-- Ensure battle_ready_rooms has bet_currency column (for existing tables)
ALTER TABLE battle_ready_rooms ADD COLUMN IF NOT EXISTS bet_currency TEXT;

-- Add constraints for bet_currency columns
ALTER TABLE battle_sessions DROP CONSTRAINT IF EXISTS battle_sessions_bet_currency_check;
ALTER TABLE battle_sessions ADD CONSTRAINT battle_sessions_bet_currency_check
  CHECK (bet_currency IN ('GC', 'BLC', 'RON'));

ALTER TABLE battle_ready_rooms DROP CONSTRAINT IF EXISTS battle_ready_rooms_bet_currency_check;
ALTER TABLE battle_ready_rooms ADD CONSTRAINT battle_ready_rooms_bet_currency_check
  CHECK (bet_currency IN ('GC', 'BLC', 'RON'));

-- Per-player bet columns for independent bet selection
ALTER TABLE battle_ready_rooms ADD COLUMN IF NOT EXISTS player1_bet_amount NUMERIC DEFAULT 0;
ALTER TABLE battle_ready_rooms ADD COLUMN IF NOT EXISTS player1_bet_currency TEXT DEFAULT 'GC';
ALTER TABLE battle_ready_rooms ADD COLUMN IF NOT EXISTS player2_bet_amount NUMERIC DEFAULT 0;
ALTER TABLE battle_ready_rooms ADD COLUMN IF NOT EXISTS player2_bet_currency TEXT DEFAULT 'GC';

-- RLS: See all_rls_policies.sql

-- =====================================================
-- CARD BATTLE PVP - FUNCTIONS
-- =====================================================

-- 1) Join battle lobby (no bet required - negotiated later)
CREATE OR REPLACE FUNCTION join_battle_lobby(p_player_id UUID, p_bet_amount INTEGER DEFAULT NULL)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_username TEXT;
  v_existing UUID;
  v_lobby_id UUID;
BEGIN
  -- Check not already in lobby
  SELECT id INTO v_existing
  FROM battle_lobby
  WHERE player_id = p_player_id AND status IN ('waiting', 'challenged');

  IF v_existing IS NOT NULL THEN
    RETURN json_build_object('success', false, 'error', 'Already in lobby', 'lobby_id', v_existing);
  END IF;

  -- Check active session
  SELECT id INTO v_existing
  FROM battle_sessions
  WHERE (player1_id = p_player_id OR player2_id = p_player_id) AND status = 'active';

  IF v_existing IS NOT NULL THEN
    RETURN json_build_object('success', false, 'error', 'Already in a battle', 'session_id', v_existing);
  END IF;

  -- Get username
  SELECT username INTO v_username
  FROM players WHERE id = p_player_id;

  -- Insert into lobby (no money deducted yet)
  INSERT INTO battle_lobby (player_id, username, status)
  VALUES (p_player_id, v_username, 'waiting')
  RETURNING id INTO v_lobby_id;

  RETURN json_build_object('success', true, 'lobby_id', v_lobby_id);
END;
$$;

-- 2) Leave battle lobby
CREATE OR REPLACE FUNCTION leave_battle_lobby(p_player_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_lobby battle_lobby%ROWTYPE;
  v_room battle_ready_rooms%ROWTYPE;
BEGIN
  SELECT * INTO v_lobby
  FROM battle_lobby
  WHERE player_id = p_player_id;

  IF v_lobby.id IS NULL THEN
    RETURN json_build_object('success', true);
  END IF;

  -- Clean up any active ready room (with refund if needed)
  SELECT * INTO v_room
  FROM battle_ready_rooms
  WHERE (player1_id = p_player_id OR player2_id = p_player_id)
    AND expires_at > NOW()
  FOR UPDATE;

  IF v_room.id IS NOT NULL THEN
    -- Refund bets if both were ready
    IF v_room.player1_ready AND v_room.player2_ready AND v_room.bet_amount > 0 THEN
      IF v_room.bet_currency = 'GC' THEN
        UPDATE players SET gamecoin_balance = gamecoin_balance + v_room.bet_amount WHERE id = v_room.player1_id;
        UPDATE players SET gamecoin_balance = gamecoin_balance + v_room.bet_amount WHERE id = v_room.player2_id;
      ELSIF v_room.bet_currency = 'BLC' THEN
        UPDATE players SET crypto_balance = crypto_balance + v_room.bet_amount WHERE id = v_room.player1_id;
        UPDATE players SET crypto_balance = crypto_balance + v_room.bet_amount WHERE id = v_room.player2_id;
      ELSIF v_room.bet_currency = 'RON' THEN
        UPDATE players SET ron_balance = ron_balance + v_room.bet_amount WHERE id = v_room.player1_id;
        UPDATE players SET ron_balance = ron_balance + v_room.bet_amount WHERE id = v_room.player2_id;
      END IF;
    END IF;
    DELETE FROM battle_ready_rooms WHERE id = v_room.id;
    -- Also remove the other player from lobby
    DELETE FROM battle_lobby WHERE player_id IN (v_room.player1_id, v_room.player2_id);
  END IF;

  -- Clear any challenges from this player
  UPDATE battle_lobby
  SET status = 'waiting', challenged_by = NULL, proposed_bet = NULL,
      proposed_currency = NULL, challenge_expires_at = NULL, challenger_username = NULL
  WHERE challenged_by = p_player_id;

  -- Remove from lobby
  DELETE FROM battle_lobby WHERE player_id = p_player_id;

  RETURN json_build_object('success', true);
END;
$$;

-- 3) Propose battle challenge with bet amount
CREATE OR REPLACE FUNCTION propose_battle_challenge(p_challenger_id UUID, p_opponent_lobby_id UUID, p_bet_amount NUMERIC, p_bet_currency TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_opponent battle_lobby%ROWTYPE;
  v_my_lobby battle_lobby%ROWTYPE;
  v_my_balance NUMERIC;
  v_opp_balance NUMERIC;
  v_my_username TEXT;
BEGIN
  -- Validate bet amount and currency combination
  IF NOT (
    (p_bet_amount = 100 AND p_bet_currency = 'GC') OR
    (p_bet_amount = 2500 AND p_bet_currency = 'GC') OR
    (p_bet_amount = 1000 AND p_bet_currency = 'BLC') OR
    (p_bet_amount = 2500 AND p_bet_currency = 'BLC') OR
    (p_bet_amount = 0.2 AND p_bet_currency = 'RON') OR
    (p_bet_amount = 1 AND p_bet_currency = 'RON')
  ) THEN
    RETURN json_build_object('success', false, 'error', 'Invalid bet. Valid options: 100GC, 2500GC, 1000BLC, 2500BLC, 0.2RON, 1RON');
  END IF;

  -- Check I'm in lobby
  SELECT * INTO v_my_lobby
  FROM battle_lobby
  WHERE player_id = p_challenger_id AND status = 'waiting';

  IF v_my_lobby.id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'You must be in the lobby first');
  END IF;

  -- Get opponent lobby entry
  SELECT * INTO v_opponent
  FROM battle_lobby
  WHERE id = p_opponent_lobby_id AND status = 'waiting'
  FOR UPDATE;

  IF v_opponent.id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Opponent is not available');
  END IF;

  IF v_opponent.player_id = p_challenger_id THEN
    RETURN json_build_object('success', false, 'error', 'Cannot challenge yourself');
  END IF;

  -- Check both players have enough balance based on currency type
  IF p_bet_currency = 'GC' THEN
    SELECT gamecoin_balance, username INTO v_my_balance, v_my_username FROM players WHERE id = p_challenger_id;
    SELECT gamecoin_balance INTO v_opp_balance FROM players WHERE id = v_opponent.player_id;
  ELSIF p_bet_currency = 'BLC' THEN
    SELECT crypto_balance, username INTO v_my_balance, v_my_username FROM players WHERE id = p_challenger_id;
    SELECT crypto_balance INTO v_opp_balance FROM players WHERE id = v_opponent.player_id;
  ELSIF p_bet_currency = 'RON' THEN
    SELECT ron_balance, username INTO v_my_balance, v_my_username FROM players WHERE id = p_challenger_id;
    SELECT ron_balance INTO v_opp_balance FROM players WHERE id = v_opponent.player_id;
  END IF;

  IF v_my_balance < p_bet_amount THEN
    RETURN json_build_object('success', false, 'error', 'You have insufficient ' || p_bet_currency || ' balance for this bet');
  END IF;

  IF v_opp_balance < p_bet_amount THEN
    RETURN json_build_object('success', false, 'error', 'Opponent has insufficient ' || p_bet_currency || ' balance for this bet');
  END IF;

  -- Update opponent's lobby entry with the challenge
  UPDATE battle_lobby
  SET status = 'challenged',
      challenged_by = p_challenger_id,
      challenger_username = v_my_username,
      proposed_bet = p_bet_amount,
      proposed_currency = p_bet_currency,
      challenge_expires_at = NOW() + INTERVAL '2 minutes'
  WHERE id = p_opponent_lobby_id;

  RETURN json_build_object(
    'success', true,
    'message', 'Challenge sent',
    'opponent_id', v_opponent.player_id,
    'bet_amount', p_bet_amount,
    'bet_currency', p_bet_currency,
    'expires_at', NOW() + INTERVAL '2 minutes'
  );
END;
$$;

-- 5) Accept battle challenge (deducts bet from both players when accepted)
CREATE OR REPLACE FUNCTION accept_battle_challenge(p_player_id UUID, p_challenger_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_challenger_lobby battle_lobby%ROWTYPE;
  v_my_lobby battle_lobby%ROWTYPE;
  v_my_balance NUMERIC;
  v_challenger_balance NUMERIC;
  v_session_id UUID;
  v_first_turn UUID;
  v_deck1 JSONB;
  v_deck2 JSONB;
  v_hand1 JSONB;
  v_hand2 JSONB;
  v_remaining1 JSONB;
  v_remaining2 JSONB;
  v_all_cards JSONB;
  v_game_state JSONB;
  v_bet_amount NUMERIC;
  v_bet_currency TEXT;
BEGIN
  -- Lock my lobby entry (the one being challenged)
  SELECT * INTO v_my_lobby
  FROM battle_lobby
  WHERE player_id = p_player_id AND status = 'challenged' AND challenged_by = p_challenger_id
  FOR UPDATE;

  IF v_my_lobby.id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'No active challenge from this player');
  END IF;

  -- Check challenge hasn't expired
  IF v_my_lobby.challenge_expires_at < NOW() THEN
    UPDATE battle_lobby SET status = 'waiting', challenged_by = NULL, proposed_bet = NULL,
                             proposed_currency = NULL, challenge_expires_at = NULL, challenger_username = NULL
    WHERE id = v_my_lobby.id;
    RETURN json_build_object('success', false, 'error', 'Challenge has expired');
  END IF;

  v_bet_amount := v_my_lobby.proposed_bet;
  v_bet_currency := v_my_lobby.proposed_currency;

  -- Lock challenger lobby entry
  SELECT * INTO v_challenger_lobby
  FROM battle_lobby
  WHERE player_id = p_challenger_id AND status = 'waiting'
  FOR UPDATE;

  IF v_challenger_lobby.id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Challenger is no longer in the lobby');
  END IF;

  -- Check both players still have enough balance based on currency type
  IF v_bet_currency = 'GC' THEN
    SELECT gamecoin_balance INTO v_my_balance FROM players WHERE id = p_player_id;
    SELECT gamecoin_balance INTO v_challenger_balance FROM players WHERE id = p_challenger_id;
  ELSIF v_bet_currency = 'BLC' THEN
    SELECT crypto_balance INTO v_my_balance FROM players WHERE id = p_player_id;
    SELECT crypto_balance INTO v_challenger_balance FROM players WHERE id = p_challenger_id;
  ELSIF v_bet_currency = 'RON' THEN
    SELECT ron_balance INTO v_my_balance FROM players WHERE id = p_player_id;
    SELECT ron_balance INTO v_challenger_balance FROM players WHERE id = p_challenger_id;
  END IF;

  IF v_my_balance < v_bet_amount THEN
    RETURN json_build_object('success', false, 'error', 'You have insufficient ' || v_bet_currency || ' balance');
  END IF;

  IF v_challenger_balance < v_bet_amount THEN
    RETURN json_build_object('success', false, 'error', 'Challenger has insufficient ' || v_bet_currency || ' balance');
  END IF;

  -- Deduct bet from BOTH players now that they've agreed
  IF v_bet_currency = 'GC' THEN
    UPDATE players SET gamecoin_balance = gamecoin_balance - v_bet_amount WHERE id = p_player_id;
    UPDATE players SET gamecoin_balance = gamecoin_balance - v_bet_amount WHERE id = p_challenger_id;
  ELSIF v_bet_currency = 'BLC' THEN
    UPDATE players SET crypto_balance = crypto_balance - v_bet_amount WHERE id = p_player_id;
    UPDATE players SET crypto_balance = crypto_balance - v_bet_amount WHERE id = p_challenger_id;
  ELSIF v_bet_currency = 'RON' THEN
    UPDATE players SET ron_balance = ron_balance - v_bet_amount WHERE id = p_player_id;
    UPDATE players SET ron_balance = ron_balance - v_bet_amount WHERE id = p_challenger_id;
  END IF;

  -- Create Ready Room (both players must press "Start" to begin)
  INSERT INTO battle_ready_rooms (
    player1_id, player2_id, player1_username, player2_username, bet_amount, bet_currency
  ) VALUES (
    p_challenger_id, p_player_id, v_challenger_lobby.username, v_my_lobby.username, v_bet_amount, v_bet_currency
  ) RETURNING id INTO v_session_id;

  -- Remove both from lobby so no one else can pair with them
  DELETE FROM battle_lobby WHERE id IN (v_my_lobby.id, v_challenger_lobby.id);

  RETURN json_build_object(
    'success', true,
    'ready_room_id', v_session_id,
    'player1_id', p_challenger_id,
    'player2_id', p_player_id,
    'bet_amount', v_bet_amount,
    'bet_currency', v_bet_currency,
    'message', 'Challenge accepted! Both players must press Start to begin.'
  );
END;
$$;

-- 4) Set player ready in ready room
CREATE OR REPLACE FUNCTION set_player_ready(p_player_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_room battle_ready_rooms%ROWTYPE;
  v_is_p1 BOOLEAN;
BEGIN
  -- Get ready room for this player
  SELECT * INTO v_room
  FROM battle_ready_rooms
  WHERE (player1_id = p_player_id OR player2_id = p_player_id)
    AND expires_at > NOW()
  FOR UPDATE;

  IF v_room.id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'No active ready room found');
  END IF;

  -- Determine if player1 or player2
  v_is_p1 := (v_room.player1_id = p_player_id);

  -- Mark player as ready
  IF v_is_p1 THEN
    UPDATE battle_ready_rooms SET player1_ready = true WHERE id = v_room.id;
  ELSE
    UPDATE battle_ready_rooms SET player2_ready = true WHERE id = v_room.id;
  END IF;

  -- Get updated room status
  SELECT * INTO v_room FROM battle_ready_rooms WHERE id = v_room.id;

  RETURN json_build_object(
    'success', true,
    'ready_room_id', v_room.id,
    'player1_ready', v_room.player1_ready,
    'player2_ready', v_room.player2_ready,
    'both_ready', v_room.player1_ready AND v_room.player2_ready
  );
END;
$$;

-- Quick Match Pair: Directly create a ready room for two lobby players
CREATE OR REPLACE FUNCTION quick_match_pair(p_player_id UUID, p_opponent_lobby_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_opponent battle_lobby%ROWTYPE;
  v_my_lobby battle_lobby%ROWTYPE;
  v_room_id UUID;
  v_my_username TEXT;
  v_opp_username TEXT;
BEGIN
  -- Check I'm in lobby
  SELECT * INTO v_my_lobby
  FROM battle_lobby
  WHERE player_id = p_player_id AND status = 'waiting'
  FOR UPDATE;

  IF v_my_lobby.id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'You must be in the lobby first');
  END IF;

  -- Get opponent lobby entry
  SELECT * INTO v_opponent
  FROM battle_lobby
  WHERE id = p_opponent_lobby_id AND status = 'waiting'
  FOR UPDATE;

  IF v_opponent.id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Opponent is not available');
  END IF;

  IF v_opponent.player_id = p_player_id THEN
    RETURN json_build_object('success', false, 'error', 'Cannot match with yourself');
  END IF;

  -- Verify neither player is already in a ready room
  IF EXISTS (
    SELECT 1 FROM battle_ready_rooms
    WHERE (player1_id = p_player_id OR player2_id = p_player_id)
      AND expires_at > NOW()
  ) THEN
    RETURN json_build_object('success', false, 'error', 'You are already in a ready room');
  END IF;

  IF EXISTS (
    SELECT 1 FROM battle_ready_rooms
    WHERE (player1_id = v_opponent.player_id OR player2_id = v_opponent.player_id)
      AND expires_at > NOW()
  ) THEN
    RETURN json_build_object('success', false, 'error', 'Opponent is already in a ready room');
  END IF;

  -- Get usernames
  SELECT username INTO v_my_username FROM players WHERE id = p_player_id;
  SELECT username INTO v_opp_username FROM players WHERE id = v_opponent.player_id;

  -- Create ready room with all bets=0 (each player selects independently)
  INSERT INTO battle_ready_rooms (
    player1_id, player2_id, player1_username, player2_username,
    bet_amount, bet_currency,
    player1_bet_amount, player1_bet_currency,
    player2_bet_amount, player2_bet_currency,
    expires_at
  )
  VALUES (
    p_player_id, v_opponent.player_id, v_my_username, v_opp_username,
    0, 'GC',
    0, 'GC',
    0, 'GC',
    NOW() + INTERVAL '5 minutes'
  )
  RETURNING id INTO v_room_id;

  -- Remove both from lobby so no one else can pair with them
  DELETE FROM battle_lobby WHERE player_id IN (p_player_id, v_opponent.player_id);

  RETURN json_build_object(
    'success', true,
    'ready_room_id', v_room_id
  );
END;
$$;

-- Select Battle Bet: Player picks their bet independently
-- If both players pick the same bet → both auto-ready + money deducted
CREATE OR REPLACE FUNCTION select_battle_bet(p_player_id UUID, p_bet_amount NUMERIC, p_bet_currency TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_room battle_ready_rooms%ROWTYPE;
  v_is_p1 BOOLEAN;
  v_my_balance NUMERIC;
  v_opponent_bet_amount NUMERIC;
  v_opponent_bet_currency TEXT;
  v_bets_match BOOLEAN;
BEGIN
  -- Get ready room
  SELECT * INTO v_room
  FROM battle_ready_rooms
  WHERE (player1_id = p_player_id OR player2_id = p_player_id)
    AND expires_at > NOW()
  FOR UPDATE;

  IF v_room.id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'No active ready room found');
  END IF;

  v_is_p1 := (v_room.player1_id = p_player_id);

  -- Don't allow re-selection if already ready (bets matched)
  IF (v_is_p1 AND v_room.player1_ready) OR (NOT v_is_p1 AND v_room.player2_ready) THEN
    RETURN json_build_object('success', false, 'error', 'Already ready, bets matched');
  END IF;

  -- Validate bet amount and currency
  IF NOT (
    (p_bet_amount = 100 AND p_bet_currency = 'GC') OR
    (p_bet_amount = 2500 AND p_bet_currency = 'GC') OR
    (p_bet_amount = 1000 AND p_bet_currency = 'BLC') OR
    (p_bet_amount = 2500 AND p_bet_currency = 'BLC') OR
    (p_bet_amount = 0.2 AND p_bet_currency = 'RON') OR
    (p_bet_amount = 1 AND p_bet_currency = 'RON')
  ) THEN
    RETURN json_build_object('success', false, 'error', 'Invalid bet');
  END IF;

  -- Check balance
  IF p_bet_currency = 'GC' THEN
    SELECT gamecoin_balance INTO v_my_balance FROM players WHERE id = p_player_id;
  ELSIF p_bet_currency = 'BLC' THEN
    SELECT crypto_balance INTO v_my_balance FROM players WHERE id = p_player_id;
  ELSIF p_bet_currency = 'RON' THEN
    SELECT ron_balance INTO v_my_balance FROM players WHERE id = p_player_id;
  END IF;

  IF v_my_balance < p_bet_amount THEN
    RETURN json_build_object('success', false, 'error', 'Insufficient ' || p_bet_currency || ' balance');
  END IF;

  -- Store my bet choice
  IF v_is_p1 THEN
    UPDATE battle_ready_rooms
    SET player1_bet_amount = p_bet_amount, player1_bet_currency = p_bet_currency
    WHERE id = v_room.id;
    -- Get opponent's bet
    v_opponent_bet_amount := v_room.player2_bet_amount;
    v_opponent_bet_currency := v_room.player2_bet_currency;
  ELSE
    UPDATE battle_ready_rooms
    SET player2_bet_amount = p_bet_amount, player2_bet_currency = p_bet_currency
    WHERE id = v_room.id;
    -- Get opponent's bet
    v_opponent_bet_amount := v_room.player1_bet_amount;
    v_opponent_bet_currency := v_room.player1_bet_currency;
  END IF;

  -- Check if bets match (opponent must have selected a bet too, i.e. amount > 0)
  v_bets_match := (v_opponent_bet_amount > 0
    AND p_bet_amount = v_opponent_bet_amount
    AND p_bet_currency = v_opponent_bet_currency);

  IF v_bets_match THEN
    -- Both selected the same bet! Deduct from both players and mark both ready.

    -- Deduct from me
    IF p_bet_currency = 'GC' THEN
      UPDATE players SET gamecoin_balance = gamecoin_balance - p_bet_amount WHERE id = p_player_id;
    ELSIF p_bet_currency = 'BLC' THEN
      UPDATE players SET crypto_balance = crypto_balance - p_bet_amount WHERE id = p_player_id;
    ELSIF p_bet_currency = 'RON' THEN
      UPDATE players SET ron_balance = ron_balance - p_bet_amount WHERE id = p_player_id;
    END IF;

    -- Deduct from opponent
    DECLARE
      v_opponent_id UUID;
      v_opp_balance NUMERIC;
    BEGIN
      v_opponent_id := CASE WHEN v_is_p1 THEN v_room.player2_id ELSE v_room.player1_id END;

      -- Check opponent still has balance
      IF p_bet_currency = 'GC' THEN
        SELECT gamecoin_balance INTO v_opp_balance FROM players WHERE id = v_opponent_id;
      ELSIF p_bet_currency = 'BLC' THEN
        SELECT crypto_balance INTO v_opp_balance FROM players WHERE id = v_opponent_id;
      ELSIF p_bet_currency = 'RON' THEN
        SELECT ron_balance INTO v_opp_balance FROM players WHERE id = v_opponent_id;
      END IF;

      IF v_opp_balance < p_bet_amount THEN
        -- Opponent no longer has funds, can't match
        RETURN json_build_object('success', true, 'bet_selected', true, 'bets_match', false,
          'message', 'Opponent no longer has sufficient funds');
      END IF;

      IF p_bet_currency = 'GC' THEN
        UPDATE players SET gamecoin_balance = gamecoin_balance - p_bet_amount WHERE id = v_opponent_id;
      ELSIF p_bet_currency = 'BLC' THEN
        UPDATE players SET crypto_balance = crypto_balance - p_bet_amount WHERE id = v_opponent_id;
      ELSIF p_bet_currency = 'RON' THEN
        UPDATE players SET ron_balance = ron_balance - p_bet_amount WHERE id = v_opponent_id;
      END IF;
    END;

    -- Mark both ready and set the final bet
    UPDATE battle_ready_rooms
    SET player1_ready = true,
        player2_ready = true,
        bet_amount = p_bet_amount,
        bet_currency = p_bet_currency
    WHERE id = v_room.id;

    RETURN json_build_object(
      'success', true,
      'bet_selected', true,
      'bets_match', true,
      'both_ready', true,
      'bet_amount', p_bet_amount,
      'bet_currency', p_bet_currency
    );
  ELSE
    -- Bets don't match (yet). Just stored the selection.
    RETURN json_build_object(
      'success', true,
      'bet_selected', true,
      'bets_match', false,
      'both_ready', false,
      'my_bet_amount', p_bet_amount,
      'my_bet_currency', p_bet_currency
    );
  END IF;
END;
$$;

-- Cancel Battle Ready Room: Cancel with refund (for per-player bets)
CREATE OR REPLACE FUNCTION cancel_battle_ready_room(p_player_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_room battle_ready_rooms%ROWTYPE;
BEGIN
  -- Get ready room
  SELECT * INTO v_room
  FROM battle_ready_rooms
  WHERE (player1_id = p_player_id OR player2_id = p_player_id)
    AND expires_at > NOW()
  FOR UPDATE;

  IF v_room.id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'No active ready room found');
  END IF;

  -- Refund bets only if both were ready (money was actually deducted)
  IF v_room.player1_ready AND v_room.player2_ready AND v_room.bet_amount > 0 THEN
    -- Refund player 1
    IF v_room.bet_currency = 'GC' THEN
      UPDATE players SET gamecoin_balance = gamecoin_balance + v_room.bet_amount WHERE id = v_room.player1_id;
    ELSIF v_room.bet_currency = 'BLC' THEN
      UPDATE players SET crypto_balance = crypto_balance + v_room.bet_amount WHERE id = v_room.player1_id;
    ELSIF v_room.bet_currency = 'RON' THEN
      UPDATE players SET ron_balance = ron_balance + v_room.bet_amount WHERE id = v_room.player1_id;
    END IF;

    -- Refund player 2
    IF v_room.bet_currency = 'GC' THEN
      UPDATE players SET gamecoin_balance = gamecoin_balance + v_room.bet_amount WHERE id = v_room.player2_id;
    ELSIF v_room.bet_currency = 'BLC' THEN
      UPDATE players SET crypto_balance = crypto_balance + v_room.bet_amount WHERE id = v_room.player2_id;
    ELSIF v_room.bet_currency = 'RON' THEN
      UPDATE players SET ron_balance = ron_balance + v_room.bet_amount WHERE id = v_room.player2_id;
    END IF;
  END IF;

  -- Delete the ready room
  DELETE FROM battle_ready_rooms WHERE id = v_room.id;

  -- Remove both players from lobby (they must press Quick Match again to re-enter)
  DELETE FROM battle_lobby
  WHERE player_id IN (v_room.player1_id, v_room.player2_id);

  RETURN json_build_object('success', true);
END;
$$;

-- 5) Start battle from ready room (when both players are ready)
CREATE OR REPLACE FUNCTION start_battle_from_ready_room(p_room_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_room battle_ready_rooms%ROWTYPE;
  v_session_id UUID;
  v_first_turn UUID;
  v_deck1 JSONB;
  v_deck2 JSONB;
  v_hand1 JSONB;
  v_hand2 JSONB;
  v_remaining1 JSONB;
  v_remaining2 JSONB;
  v_all_cards JSONB;
  v_game_state JSONB;
BEGIN
  -- Get and lock ready room
  SELECT * INTO v_room
  FROM battle_ready_rooms
  WHERE id = p_room_id
  FOR UPDATE;

  IF v_room.id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Ready room not found');
  END IF;

  -- Verify both players are ready
  IF NOT (v_room.player1_ready AND v_room.player2_ready) THEN
    RETURN json_build_object('success', false, 'error', 'Both players must be ready');
  END IF;

  -- Card IDs for deck building
  v_all_cards := '["quick_strike","power_slash","fury_attack","double_hit","critical_blow","venom_strike","guard","fortify","counter","deflect","spike_armor","barrier","heal","weaken","drain","war_cry","recharge","execute","energy_siphon","antidote","taunt","recall"]'::JSONB;

  -- Shuffle decks (using random ordering)
  SELECT jsonb_agg(card ORDER BY random()) INTO v_deck1
  FROM jsonb_array_elements_text(v_all_cards) AS card;

  SELECT jsonb_agg(card ORDER BY random()) INTO v_deck2
  FROM jsonb_array_elements_text(v_all_cards) AS card;

  -- Draw 3 cards for each player from their deck
  SELECT jsonb_agg(c) INTO v_hand1
  FROM (SELECT c FROM jsonb_array_elements(v_deck1) c LIMIT 3) sub;

  SELECT jsonb_agg(c) INTO v_remaining1
  FROM (SELECT c FROM jsonb_array_elements(v_deck1) c OFFSET 3) sub;

  SELECT jsonb_agg(c) INTO v_hand2
  FROM (SELECT c FROM jsonb_array_elements(v_deck2) c LIMIT 3) sub;

  SELECT jsonb_agg(c) INTO v_remaining2
  FROM (SELECT c FROM jsonb_array_elements(v_deck2) c OFFSET 3) sub;

  -- Coin flip for first turn
  IF random() < 0.5 THEN
    v_first_turn := v_room.player1_id;
  ELSE
    v_first_turn := v_room.player2_id;
  END IF;

  -- Build game state
  v_game_state := jsonb_build_object(
    'player1Hand', v_hand1,
    'player2Hand', v_hand2,
    'player1Deck', COALESCE(v_remaining1, '[]'::JSONB),
    'player2Deck', COALESCE(v_remaining2, '[]'::JSONB),
    'player1Discard', '[]'::JSONB,
    'player2Discard', '[]'::JSONB,
    'player1Energy', 3,
    'player2Energy', 3,
    'player1Weakened', false,
    'player2Weakened', false,
    'player1Boosted', false,
    'player2Boosted', false,
    'player1Poison', 0,
    'player2Poison', 0,
    'player1HandCount', jsonb_array_length(v_hand1),
    'player2HandCount', jsonb_array_length(v_hand2),
    'player1DeckCount', jsonb_array_length(COALESCE(v_remaining1, '[]'::JSONB)),
    'player2DeckCount', jsonb_array_length(COALESCE(v_remaining2, '[]'::JSONB)),
    'player1DiscardCount', 0,
    'player2DiscardCount', 0,
    'totalCards', jsonb_array_length(v_all_cards),
    'lastAction', null
  );

  -- Create battle session
  INSERT INTO battle_sessions (
    player1_id, player2_id, bet_amount, bet_currency, current_turn, turn_deadline, player1_hp, player2_hp, player1_shield, player2_shield, game_state
  ) VALUES (
    v_room.player1_id, v_room.player2_id, v_room.bet_amount, v_room.bet_currency,
    v_first_turn, NOW() + INTERVAL '45 seconds', 200, 200, 0, 0, v_game_state
  ) RETURNING id INTO v_session_id;

  -- Delete ready room
  DELETE FROM battle_ready_rooms WHERE id = p_room_id;

  -- Delete lobby entries for both players
  DELETE FROM battle_lobby
  WHERE player_id IN (v_room.player1_id, v_room.player2_id);

  RETURN json_build_object(
    'success', true,
    'session_id', v_session_id,
    'first_turn', v_first_turn,
    'player1_id', v_room.player1_id,
    'player2_id', v_room.player2_id,
    'bet_amount', v_room.bet_amount,
    'bet_currency', v_room.bet_currency
  );
END;
$$;

-- 6) Play battle turn
CREATE OR REPLACE FUNCTION play_battle_turn(p_player_id UUID, p_session_id UUID, p_cards_played JSONB)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_session battle_sessions%ROWTYPE;
  v_state JSONB;
  v_is_p1 BOOLEAN;
  v_my_hand JSONB;
  v_my_deck JSONB;
  v_my_discard JSONB;
  v_opp_hand JSONB;
  v_opp_deck JSONB;
  v_energy INTEGER;
  v_my_hp INTEGER;
  v_my_shield INTEGER;
  v_opp_hp INTEGER;
  v_opp_shield INTEGER;
  v_opp_energy INTEGER;
  v_weakened BOOLEAN;
  v_opp_weakened BOOLEAN;
  v_boosted BOOLEAN;
  v_my_poison INTEGER;
  v_opp_poison INTEGER;
  v_card TEXT;
  v_card_cost INTEGER;
  v_card_type TEXT;
  v_damage INTEGER;
  v_shield_dmg INTEGER;
  v_remaining_dmg INTEGER;
  v_winner_id UUID;
  v_pot INTEGER;
  v_new_hand JSONB;
  v_draw_count INTEGER;
  v_cards_to_draw JSONB;
  v_new_deck JSONB;
  v_log_entries JSONB := '[]'::JSONB;
  v_total_cards INTEGER;
  v_recall_target TEXT;
BEGIN
  -- Lock session
  SELECT * INTO v_session
  FROM battle_sessions
  WHERE id = p_session_id AND status = 'active'
  FOR UPDATE;

  IF v_session.id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Session not found or ended');
  END IF;

  -- Validate turn
  IF v_session.current_turn != p_player_id THEN
    RETURN json_build_object('success', false, 'error', 'Not your turn');
  END IF;

  -- Determine player position
  v_is_p1 := (p_player_id = v_session.player1_id);
  v_state := v_session.game_state;

  IF v_is_p1 THEN
    v_my_hand := v_state->'player1Hand';
    v_my_deck := v_state->'player1Deck';
    v_my_discard := v_state->'player1Discard';
    v_opp_hand := v_state->'player2Hand';
    v_opp_deck := v_state->'player2Deck';
    v_energy := (v_state->>'player1Energy')::INTEGER;
    v_opp_energy := (v_state->>'player2Energy')::INTEGER;
    v_my_hp := v_session.player1_hp;
    v_my_shield := v_session.player1_shield;
    v_opp_hp := v_session.player2_hp;
    v_opp_shield := v_session.player2_shield;
    v_weakened := (v_state->>'player1Weakened')::BOOLEAN;
    v_opp_weakened := (v_state->>'player2Weakened')::BOOLEAN;
    v_boosted := COALESCE((v_state->>'player1Boosted')::BOOLEAN, false);
    v_my_poison := COALESCE((v_state->>'player1Poison')::INTEGER, 0);
    v_opp_poison := COALESCE((v_state->>'player2Poison')::INTEGER, 0);
  ELSE
    v_my_hand := v_state->'player2Hand';
    v_my_deck := v_state->'player2Deck';
    v_my_discard := v_state->'player2Discard';
    v_opp_hand := v_state->'player1Hand';
    v_opp_deck := v_state->'player1Deck';
    v_energy := (v_state->>'player2Energy')::INTEGER;
    v_opp_energy := (v_state->>'player1Energy')::INTEGER;
    v_my_hp := v_session.player2_hp;
    v_my_shield := v_session.player2_shield;
    v_opp_hp := v_session.player1_hp;
    v_opp_shield := v_session.player1_shield;
    v_weakened := (v_state->>'player2Weakened')::BOOLEAN;
    v_opp_weakened := (v_state->>'player1Weakened')::BOOLEAN;
    v_boosted := COALESCE((v_state->>'player2Boosted')::BOOLEAN, false);
    v_my_poison := COALESCE((v_state->>'player2Poison')::INTEGER, 0);
    v_opp_poison := COALESCE((v_state->>'player1Poison')::INTEGER, 0);
  END IF;

  -- Apply poison tick at start of turn (damages current player, ignores shield)
  IF v_my_poison > 0 THEN
    v_my_hp := GREATEST(v_my_hp - 3, 0);
    v_my_poison := v_my_poison - 1;
    v_log_entries := v_log_entries || jsonb_build_object('type', 'special', 'card', 'venom_strike', 'poisonTick', 3);
  END IF;

  -- Process each card played
  FOR v_card IN SELECT jsonb_array_elements_text(p_cards_played)
  LOOP
    -- Parse recall target (format: "recall:target_card_id")
    v_recall_target := NULL;
    IF v_card LIKE 'recall:%' THEN
      v_recall_target := substring(v_card from 8);
      v_card := 'recall';
    END IF;

    -- Determine card cost and type
    CASE v_card
      WHEN 'quick_strike' THEN v_card_cost := 1; v_card_type := 'attack';
      WHEN 'power_slash' THEN v_card_cost := 2; v_card_type := 'attack';
      WHEN 'fury_attack' THEN v_card_cost := 2; v_card_type := 'attack';
      WHEN 'double_hit' THEN v_card_cost := 1; v_card_type := 'attack';
      WHEN 'critical_blow' THEN v_card_cost := 2; v_card_type := 'attack';
      WHEN 'guard' THEN v_card_cost := 1; v_card_type := 'defense';
      WHEN 'fortify' THEN v_card_cost := 2; v_card_type := 'defense';
      WHEN 'counter' THEN v_card_cost := 1; v_card_type := 'defense';
      WHEN 'deflect' THEN v_card_cost := 1; v_card_type := 'defense';
      WHEN 'heal' THEN v_card_cost := 1; v_card_type := 'special';
      WHEN 'weaken' THEN v_card_cost := 1; v_card_type := 'special';
      WHEN 'drain' THEN v_card_cost := 2; v_card_type := 'special';
      WHEN 'venom_strike' THEN v_card_cost := 1; v_card_type := 'attack';
      WHEN 'spike_armor' THEN v_card_cost := 1; v_card_type := 'defense';
      WHEN 'barrier' THEN v_card_cost := 2; v_card_type := 'defense';
      WHEN 'war_cry' THEN v_card_cost := 1; v_card_type := 'special';
      WHEN 'recharge' THEN v_card_cost := 1; v_card_type := 'special';
      WHEN 'execute' THEN v_card_cost := 2; v_card_type := 'special';
      WHEN 'energy_siphon' THEN v_card_cost := 1; v_card_type := 'special';
      WHEN 'antidote' THEN v_card_cost := 1; v_card_type := 'special';
      WHEN 'taunt' THEN v_card_cost := 1; v_card_type := 'special';
      WHEN 'recall' THEN v_card_cost := 2; v_card_type := 'special';
      ELSE
        RETURN json_build_object('success', false, 'error', 'Unknown card: ' || v_card);
    END CASE;

    -- Check energy
    IF v_energy < v_card_cost THEN
      RETURN json_build_object('success', false, 'error', 'Not enough energy for ' || v_card);
    END IF;

    -- Deduct energy
    v_energy := v_energy - v_card_cost;

    -- Remove card from hand
    v_my_hand := v_my_hand - (
      SELECT i::INTEGER FROM generate_series(0, jsonb_array_length(v_my_hand) - 1) i
      WHERE v_my_hand->>i::INTEGER = v_card
      LIMIT 1
    );

    -- Add to discard
    v_my_discard := v_my_discard || to_jsonb(v_card);

    -- Apply card effects
    CASE v_card
      WHEN 'quick_strike' THEN
        v_damage := 12;
        IF v_boosted THEN v_damage := v_damage + 10; v_boosted := false; END IF;
        IF v_weakened THEN v_damage := GREATEST(v_damage - 8, 0); v_weakened := false; END IF;
        v_remaining_dmg := GREATEST(v_damage - v_opp_shield, 0);
        v_opp_shield := GREATEST(v_opp_shield - v_damage, 0);
        v_opp_hp := GREATEST(v_opp_hp - v_remaining_dmg, 0);
        v_log_entries := v_log_entries || jsonb_build_object('type', 'attack', 'card', v_card, 'damage', v_damage);

      WHEN 'power_slash' THEN
        v_damage := 25;
        IF v_boosted THEN v_damage := v_damage + 10; v_boosted := false; END IF;
        IF v_weakened THEN v_damage := GREATEST(v_damage - 8, 0); v_weakened := false; END IF;
        v_remaining_dmg := GREATEST(v_damage - v_opp_shield, 0);
        v_opp_shield := GREATEST(v_opp_shield - v_damage, 0);
        v_opp_hp := GREATEST(v_opp_hp - v_remaining_dmg, 0);
        v_log_entries := v_log_entries || jsonb_build_object('type', 'attack', 'card', v_card, 'damage', v_damage);

      WHEN 'fury_attack' THEN
        v_damage := 18;
        IF v_boosted THEN v_damage := v_damage + 10; v_boosted := false; END IF;
        IF v_weakened THEN v_damage := GREATEST(v_damage - 8, 0); v_weakened := false; END IF;
        -- Ignores 8 shield
        v_shield_dmg := GREATEST(v_opp_shield - 8, 0);
        v_remaining_dmg := GREATEST(v_damage - v_shield_dmg, 0);
        v_opp_shield := GREATEST(v_shield_dmg - v_damage, 0);
        v_opp_hp := GREATEST(v_opp_hp - v_remaining_dmg, 0);
        v_log_entries := v_log_entries || jsonb_build_object('type', 'attack', 'card', v_card, 'damage', v_damage);

      WHEN 'double_hit' THEN
        v_damage := 8;
        IF v_boosted THEN v_damage := v_damage + 10; v_boosted := false; END IF;
        IF v_weakened THEN v_damage := GREATEST(v_damage - 8, 0); v_weakened := false; END IF;
        -- Hit 1
        v_remaining_dmg := GREATEST(v_damage - v_opp_shield, 0);
        v_opp_shield := GREATEST(v_opp_shield - v_damage, 0);
        v_opp_hp := GREATEST(v_opp_hp - v_remaining_dmg, 0);
        -- Hit 2
        v_remaining_dmg := GREATEST(v_damage - v_opp_shield, 0);
        v_opp_shield := GREATEST(v_opp_shield - v_damage, 0);
        v_opp_hp := GREATEST(v_opp_hp - v_remaining_dmg, 0);
        v_log_entries := v_log_entries || jsonb_build_object('type', 'attack', 'card', v_card, 'damage', v_damage * 2);

      WHEN 'critical_blow' THEN
        v_damage := 35;
        IF v_boosted THEN v_damage := v_damage + 10; v_boosted := false; END IF;
        IF v_weakened THEN v_damage := GREATEST(v_damage - 8, 0); v_weakened := false; END IF;
        v_remaining_dmg := GREATEST(v_damage - v_opp_shield, 0);
        v_opp_shield := GREATEST(v_opp_shield - v_damage, 0);
        v_opp_hp := GREATEST(v_opp_hp - v_remaining_dmg, 0);
        -- Self damage
        v_my_hp := GREATEST(v_my_hp - 5, 0);
        v_log_entries := v_log_entries || jsonb_build_object('type', 'attack', 'card', v_card, 'damage', v_damage, 'selfDamage', 5);

      WHEN 'venom_strike' THEN
        -- 8 damage + apply poison (3 turns, 3 dmg/turn)
        v_damage := 8;
        IF v_boosted THEN v_damage := v_damage + 10; v_boosted := false; END IF;
        IF v_weakened THEN v_damage := GREATEST(v_damage - 8, 0); v_weakened := false; END IF;
        v_remaining_dmg := GREATEST(v_damage - v_opp_shield, 0);
        v_opp_shield := GREATEST(v_opp_shield - v_damage, 0);
        v_opp_hp := GREATEST(v_opp_hp - v_remaining_dmg, 0);
        -- Apply poison (stacks with existing)
        v_opp_poison := v_opp_poison + 3;
        v_log_entries := v_log_entries || jsonb_build_object('type', 'attack', 'card', v_card, 'damage', v_damage, 'poison', 3);

      WHEN 'guard' THEN
        v_my_shield := v_my_shield + 12;
        v_log_entries := v_log_entries || jsonb_build_object('type', 'defense', 'card', v_card, 'shield', 12);

      WHEN 'fortify' THEN
        v_my_shield := v_my_shield + 25;
        v_log_entries := v_log_entries || jsonb_build_object('type', 'defense', 'card', v_card, 'shield', 25);

      WHEN 'counter' THEN
        v_my_shield := v_my_shield + 8;
        -- Deal 5 damage back
        v_damage := 5;
        v_remaining_dmg := GREATEST(v_damage - v_opp_shield, 0);
        v_opp_shield := GREATEST(v_opp_shield - v_damage, 0);
        v_opp_hp := GREATEST(v_opp_hp - v_remaining_dmg, 0);
        v_log_entries := v_log_entries || jsonb_build_object('type', 'defense', 'card', v_card, 'shield', 8, 'counterDamage', 5);

      WHEN 'deflect' THEN
        v_my_shield := v_my_shield + 10;
        -- Draw 1 extra card
        IF jsonb_array_length(COALESCE(v_my_deck, '[]'::JSONB)) > 0 THEN
          v_my_hand := v_my_hand || jsonb_build_array(v_my_deck->0);
          v_my_deck := v_my_deck - 0;
        END IF;
        v_log_entries := v_log_entries || jsonb_build_object('type', 'defense', 'card', v_card, 'shield', 10, 'draw', 1);

      WHEN 'spike_armor' THEN
        v_my_shield := v_my_shield + 5;
        -- Deal 10 damage back
        v_damage := 10;
        v_remaining_dmg := GREATEST(v_damage - v_opp_shield, 0);
        v_opp_shield := GREATEST(v_opp_shield - v_damage, 0);
        v_opp_hp := GREATEST(v_opp_hp - v_remaining_dmg, 0);
        v_log_entries := v_log_entries || jsonb_build_object('type', 'defense', 'card', v_card, 'shield', 5, 'counterDamage', 10);

      WHEN 'barrier' THEN
        v_my_shield := v_my_shield + 18;
        v_my_hp := LEAST(v_my_hp + 5, 200);
        v_log_entries := v_log_entries || jsonb_build_object('type', 'defense', 'card', v_card, 'shield', 18, 'heal', 5);

      WHEN 'heal' THEN
        v_my_hp := LEAST(v_my_hp + 15, 200);
        v_log_entries := v_log_entries || jsonb_build_object('type', 'special', 'card', v_card, 'heal', 15);

      WHEN 'weaken' THEN
        v_opp_weakened := true;
        v_log_entries := v_log_entries || jsonb_build_object('type', 'special', 'card', v_card, 'weaken', 8);

      WHEN 'war_cry' THEN
        v_boosted := true;
        v_log_entries := v_log_entries || jsonb_build_object('type', 'special', 'card', v_card, 'boost', 10);

      WHEN 'recharge' THEN
        -- Draw 2 cards
        IF jsonb_array_length(COALESCE(v_my_deck, '[]'::JSONB)) > 0 THEN
          v_my_hand := v_my_hand || jsonb_build_array(v_my_deck->0);
          v_my_deck := v_my_deck - 0;
        END IF;
        IF jsonb_array_length(COALESCE(v_my_deck, '[]'::JSONB)) > 0 THEN
          v_my_hand := v_my_hand || jsonb_build_array(v_my_deck->0);
          v_my_deck := v_my_deck - 0;
        END IF;
        v_log_entries := v_log_entries || jsonb_build_object('type', 'special', 'card', v_card, 'draw', 2);

      WHEN 'execute' THEN
        -- 15 damage, +15 bonus if enemy HP <= 60
        v_damage := 15;
        IF v_opp_hp <= 60 THEN v_damage := 30; END IF;
        IF v_boosted THEN v_damage := v_damage + 10; v_boosted := false; END IF;
        IF v_weakened THEN v_damage := GREATEST(v_damage - 8, 0); v_weakened := false; END IF;
        v_remaining_dmg := GREATEST(v_damage - v_opp_shield, 0);
        v_opp_shield := GREATEST(v_opp_shield - v_damage, 0);
        v_opp_hp := GREATEST(v_opp_hp - v_remaining_dmg, 0);
        v_log_entries := v_log_entries || jsonb_build_object('type', 'special', 'card', v_card, 'damage', v_damage);

      WHEN 'drain' THEN
        v_damage := 12;
        IF v_boosted THEN v_damage := v_damage + 10; v_boosted := false; END IF;
        IF v_weakened THEN v_damage := GREATEST(v_damage - 8, 0); v_weakened := false; END IF;
        v_remaining_dmg := GREATEST(v_damage - v_opp_shield, 0);
        v_opp_shield := GREATEST(v_opp_shield - v_damage, 0);
        v_opp_hp := GREATEST(v_opp_hp - v_remaining_dmg, 0);
        v_my_hp := LEAST(v_my_hp + 6, 200);
        v_log_entries := v_log_entries || jsonb_build_object('type', 'special', 'card', v_card, 'damage', v_damage, 'heal', 6);

      WHEN 'energy_siphon' THEN
        -- Drain 2 energy from opponent
        v_opp_energy := GREATEST(v_opp_energy - 2, 0);
        v_log_entries := v_log_entries || jsonb_build_object('type', 'special', 'card', v_card, 'energyDrain', 2);

      WHEN 'antidote' THEN
        -- Remove all poison from self
        v_my_poison := 0;
        v_log_entries := v_log_entries || jsonb_build_object('type', 'special', 'card', v_card, 'curePoison', true);

      WHEN 'taunt' THEN
        -- Does nothing, just taunts the opponent
        v_log_entries := v_log_entries || jsonb_build_object('type', 'special', 'card', v_card, 'taunt', true);

      WHEN 'recall' THEN
        -- Retrieve a card from discard pile and add to hand
        IF v_recall_target IS NOT NULL AND v_my_discard @> to_jsonb(v_recall_target) THEN
          -- Remove target from discard (first occurrence)
          v_my_discard := v_my_discard - (
            SELECT i::INTEGER FROM generate_series(0, jsonb_array_length(v_my_discard) - 1) i
            WHERE v_my_discard->>i::INTEGER = v_recall_target
            LIMIT 1
          );
          -- Add target to hand
          v_my_hand := v_my_hand || to_jsonb(v_recall_target);
          v_log_entries := v_log_entries || jsonb_build_object('type', 'special', 'card', 'recall', 'recall', v_recall_target);
        ELSE
          -- No valid target, recall fizzles
          v_log_entries := v_log_entries || jsonb_build_object('type', 'special', 'card', 'recall', 'recall', null);
        END IF;
    END CASE;

    -- Check win condition after each card
    IF v_opp_hp <= 0 OR v_my_hp <= 0 THEN
      EXIT;
    END IF;
  END LOOP;

  -- Reset opponent's shield at start of their turn
  v_opp_shield := 0;

  -- Draw cards for opponent's next turn (up to 3, max hand 6)
  v_draw_count := 6 - jsonb_array_length(COALESCE(v_opp_hand, '[]'::JSONB));

  -- If opponent's deck is empty, reshuffle discard into deck
  IF jsonb_array_length(COALESCE(v_opp_deck, '[]'::JSONB)) < v_draw_count THEN
    -- Merge remaining deck + discard, reshuffle
    v_opp_deck := COALESCE(v_opp_deck, '[]'::JSONB);
    IF v_is_p1 THEN
      SELECT jsonb_agg(card ORDER BY random()) INTO v_opp_deck
      FROM jsonb_array_elements(v_opp_deck || COALESCE(v_state->'player2Discard', '[]'::JSONB)) AS card;
      -- Clear discard handled below
    ELSE
      SELECT jsonb_agg(card ORDER BY random()) INTO v_opp_deck
      FROM jsonb_array_elements(v_opp_deck || COALESCE(v_state->'player1Discard', '[]'::JSONB)) AS card;
    END IF;
    v_opp_deck := COALESCE(v_opp_deck, '[]'::JSONB);
  END IF;

  -- Draw cards
  IF v_draw_count > 0 AND jsonb_array_length(COALESCE(v_opp_deck, '[]'::JSONB)) > 0 THEN
    v_draw_count := LEAST(v_draw_count, jsonb_array_length(v_opp_deck));
    SELECT jsonb_agg(c) INTO v_cards_to_draw
    FROM (SELECT c FROM jsonb_array_elements(v_opp_deck) c LIMIT v_draw_count) sub;

    v_opp_hand := COALESCE(v_opp_hand, '[]'::JSONB) || COALESCE(v_cards_to_draw, '[]'::JSONB);

    SELECT COALESCE(jsonb_agg(c), '[]'::JSONB) INTO v_new_deck
    FROM (SELECT c FROM jsonb_array_elements(v_opp_deck) c OFFSET v_draw_count) sub;
    v_opp_deck := v_new_deck;
  END IF;

  -- Build new game state
  IF v_is_p1 THEN
    v_state := jsonb_build_object(
      'player1Hand', COALESCE(v_my_hand, '[]'::JSONB),
      'player2Hand', COALESCE(v_opp_hand, '[]'::JSONB),
      'player1Deck', COALESCE(v_my_deck, '[]'::JSONB),
      'player2Deck', COALESCE(v_opp_deck, '[]'::JSONB),
      'player1Discard', COALESCE(v_my_discard, '[]'::JSONB),
      'player2Discard', '[]'::JSONB,
      'player1Energy', v_energy,
      'player2Energy', v_opp_energy + CASE WHEN v_opp_energy <= 1 THEN 3 WHEN v_opp_energy <= 3 THEN 2 ELSE 1 END,
      'player1Weakened', v_weakened,
      'player2Weakened', v_opp_weakened,
      'player1Boosted', v_boosted,
      'player2Boosted', false,
      'player1Poison', v_my_poison,
      'player2Poison', v_opp_poison,
      'player1HandCount', jsonb_array_length(COALESCE(v_my_hand, '[]'::JSONB)),
      'player2HandCount', jsonb_array_length(COALESCE(v_opp_hand, '[]'::JSONB)),
      'player1DeckCount', jsonb_array_length(COALESCE(v_my_deck, '[]'::JSONB)),
      'player2DeckCount', jsonb_array_length(COALESCE(v_opp_deck, '[]'::JSONB)),
      'player1DiscardCount', jsonb_array_length(COALESCE(v_my_discard, '[]'::JSONB)),
      'player2DiscardCount', 0,
      'totalCards', 22,
      'lastAction', v_log_entries
    );
  ELSE
    v_state := jsonb_build_object(
      'player1Hand', COALESCE(v_opp_hand, '[]'::JSONB),
      'player2Hand', COALESCE(v_my_hand, '[]'::JSONB),
      'player1Deck', COALESCE(v_opp_deck, '[]'::JSONB),
      'player2Deck', COALESCE(v_my_deck, '[]'::JSONB),
      'player1Discard', '[]'::JSONB,
      'player2Discard', COALESCE(v_my_discard, '[]'::JSONB),
      'player1Energy', v_opp_energy + CASE WHEN v_opp_energy <= 1 THEN 3 WHEN v_opp_energy <= 3 THEN 2 ELSE 1 END,
      'player2Energy', v_energy,
      'player1Weakened', v_opp_weakened,
      'player2Weakened', v_weakened,
      'player1Boosted', false,
      'player2Boosted', v_boosted,
      'player1Poison', v_opp_poison,
      'player2Poison', v_my_poison,
      'player1HandCount', jsonb_array_length(COALESCE(v_opp_hand, '[]'::JSONB)),
      'player2HandCount', jsonb_array_length(COALESCE(v_my_hand, '[]'::JSONB)),
      'player1DeckCount', jsonb_array_length(COALESCE(v_opp_deck, '[]'::JSONB)),
      'player2DeckCount', jsonb_array_length(COALESCE(v_my_deck, '[]'::JSONB)),
      'player1DiscardCount', 0,
      'player2DiscardCount', jsonb_array_length(COALESCE(v_my_discard, '[]'::JSONB)),
      'totalCards', 22,
      'lastAction', v_log_entries
    );
  END IF;

  -- Determine winner
  v_winner_id := NULL;
  IF v_opp_hp <= 0 THEN
    v_winner_id := p_player_id;
  ELSIF v_my_hp <= 0 THEN
    IF v_is_p1 THEN v_winner_id := v_session.player2_id;
    ELSE v_winner_id := v_session.player1_id;
    END IF;
  END IF;

  -- Update session
  IF v_is_p1 THEN
    UPDATE battle_sessions SET
      player1_hp = v_my_hp,
      player2_hp = v_opp_hp,
      player1_shield = v_my_shield,
      player2_shield = v_opp_shield,
      current_turn = CASE WHEN v_winner_id IS NULL THEN v_session.player2_id ELSE current_turn END,
      turn_number = turn_number + 1,
      turn_deadline = CASE WHEN v_winner_id IS NULL THEN NOW() + INTERVAL '45 seconds' ELSE turn_deadline END,
      game_state = v_state,
      status = CASE WHEN v_winner_id IS NOT NULL THEN 'completed' ELSE 'active' END,
      winner_id = v_winner_id,
      completed_at = CASE WHEN v_winner_id IS NOT NULL THEN NOW() ELSE NULL END
    WHERE id = p_session_id;
  ELSE
    UPDATE battle_sessions SET
      player1_hp = v_opp_hp,
      player2_hp = v_my_hp,
      player1_shield = v_opp_shield,
      player2_shield = v_my_shield,
      current_turn = CASE WHEN v_winner_id IS NULL THEN v_session.player1_id ELSE current_turn END,
      turn_number = turn_number + 1,
      turn_deadline = CASE WHEN v_winner_id IS NULL THEN NOW() + INTERVAL '45 seconds' ELSE turn_deadline END,
      game_state = v_state,
      status = CASE WHEN v_winner_id IS NOT NULL THEN 'completed' ELSE 'active' END,
      winner_id = v_winner_id,
      completed_at = CASE WHEN v_winner_id IS NOT NULL THEN NOW() ELSE NULL END
    WHERE id = p_session_id;
  END IF;

  -- Award pot to winner in the correct currency
  IF v_winner_id IS NOT NULL THEN
    v_pot := v_session.bet_amount * 2;
    IF v_session.bet_currency = 'GC' THEN
      UPDATE players SET gamecoin_balance = gamecoin_balance + v_pot WHERE id = v_winner_id;
    ELSIF v_session.bet_currency = 'BLC' THEN
      UPDATE players SET crypto_balance = crypto_balance + v_pot WHERE id = v_winner_id;
    ELSIF v_session.bet_currency = 'RON' THEN
      UPDATE players SET ron_balance = ron_balance + v_pot WHERE id = v_winner_id;
    END IF;

    -- Track battle missions
    PERFORM update_mission_progress(v_winner_id, 'battle_win', 1);
    PERFORM update_mission_progress(v_winner_id, 'battle_play', 1);
    IF v_winner_id = v_session.player1_id THEN
      PERFORM update_mission_progress(v_session.player2_id, 'battle_play', 1);
    ELSE
      PERFORM update_mission_progress(v_session.player1_id, 'battle_play', 1);
    END IF;
  END IF;

  RETURN json_build_object(
    'success', true,
    'winner_id', v_winner_id,
    'player1_hp', CASE WHEN v_is_p1 THEN v_my_hp ELSE v_opp_hp END,
    'player2_hp', CASE WHEN v_is_p1 THEN v_opp_hp ELSE v_my_hp END,
    'player1_shield', CASE WHEN v_is_p1 THEN v_my_shield ELSE v_opp_shield END,
    'player2_shield', CASE WHEN v_is_p1 THEN v_opp_shield ELSE v_my_shield END,
    'turn_number', v_session.turn_number + 1,
    'log', v_log_entries
  );
END;
$$;

-- 5) Forfeit battle
CREATE OR REPLACE FUNCTION forfeit_battle(p_player_id UUID, p_session_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_session battle_sessions%ROWTYPE;
  v_winner_id UUID;
  v_pot NUMERIC;
BEGIN
  SELECT * INTO v_session
  FROM battle_sessions
  WHERE id = p_session_id AND status = 'active'
  FOR UPDATE;

  IF v_session.id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Session not found or already ended');
  END IF;

  IF p_player_id != v_session.player1_id AND p_player_id != v_session.player2_id THEN
    RETURN json_build_object('success', false, 'error', 'Not a participant');
  END IF;

  -- Winner is the other player
  IF p_player_id = v_session.player1_id THEN
    v_winner_id := v_session.player2_id;
  ELSE
    v_winner_id := v_session.player1_id;
  END IF;

  v_pot := v_session.bet_amount * 2;

  UPDATE battle_sessions SET
    status = 'forfeited',
    winner_id = v_winner_id,
    completed_at = NOW()
  WHERE id = p_session_id;

  -- Pay winner in the correct currency
  IF v_session.bet_currency = 'GC' THEN
    UPDATE players SET gamecoin_balance = gamecoin_balance + v_pot WHERE id = v_winner_id;
  ELSIF v_session.bet_currency = 'BLC' THEN
    UPDATE players SET crypto_balance = crypto_balance + v_pot WHERE id = v_winner_id;
  ELSIF v_session.bet_currency = 'RON' THEN
    UPDATE players SET ron_balance = ron_balance + v_pot WHERE id = v_winner_id;
  END IF;

  -- Track battle missions
  PERFORM update_mission_progress(v_winner_id, 'battle_win', 1);
  PERFORM update_mission_progress(v_winner_id, 'battle_play', 1);
  PERFORM update_mission_progress(p_player_id, 'battle_play', 1);

  RETURN json_build_object('success', true, 'winner_id', v_winner_id, 'pot', v_pot, 'currency', v_session.bet_currency);
END;
$$;

-- 6) Get battle lobby
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
  v_lobby_count INT;
  v_playing_count INT;
  v_my_ron_balance NUMERIC;
BEGIN
  -- Cleanup expired challenges and orphaned entries first
  PERFORM cleanup_expired_battle_challenges();

  -- Get my balances
  SELECT gamecoin_balance, crypto_balance, ron_balance
  INTO v_my_gc_balance, v_my_blc_balance, v_my_ron_balance
  FROM players WHERE id = p_player_id;
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
  WHERE bl.player_id != p_player_id AND bl.status IN ('waiting', 'challenged')
  ORDER BY bl.created_at ASC;

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

  -- Count players waiting in lobby (excluding self)
  SELECT COUNT(*) INTO v_lobby_count
  FROM battle_lobby WHERE status = 'waiting' AND player_id != p_player_id;

  -- Count active battles
  SELECT COUNT(*) INTO v_playing_count
  FROM battle_sessions WHERE status = 'active';

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
    ),
    'lobby_count', v_lobby_count,
    'playing_count', v_playing_count
  );
END;
$$;

-- 6) Reject battle challenge
CREATE OR REPLACE FUNCTION reject_battle_challenge(p_player_id UUID, p_challenger_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_my_lobby battle_lobby%ROWTYPE;
BEGIN
  -- Get my lobby entry
  SELECT * INTO v_my_lobby
  FROM battle_lobby
  WHERE player_id = p_player_id AND status = 'challenged' AND challenged_by = p_challenger_id;

  IF v_my_lobby.id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'No active challenge from this player');
  END IF;

  -- Clear the challenge
  UPDATE battle_lobby
  SET status = 'waiting',
      challenged_by = NULL,
      proposed_bet = NULL,
      proposed_currency = NULL,
      challenge_expires_at = NULL,
      challenger_username = NULL
  WHERE id = v_my_lobby.id;

  RETURN json_build_object('success', true, 'message', 'Challenge rejected');
END;
$$;

-- 7) Cleanup expired challenges and orphaned lobby entries
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

  -- Delete expired ready rooms FIRST (before orphan cleanup)
  DELETE FROM battle_ready_rooms WHERE expires_at < NOW();

  -- Cleanup orphaned 'matched' entries (no ready room or active session)
  -- Must run AFTER deleting expired ready rooms so the NOT EXISTS check is accurate
  DELETE FROM battle_lobby bl
  WHERE bl.status = 'matched'
    AND NOT EXISTS (
      SELECT 1 FROM battle_ready_rooms brr
      WHERE (brr.player1_id = bl.player_id OR brr.player2_id = bl.player_id)
    )
    AND NOT EXISTS (
      SELECT 1 FROM battle_sessions bs
      WHERE (bs.player1_id = bl.player_id OR bs.player2_id = bl.player_id)
        AND bs.status = 'active'
    );

  GET DIAGNOSTICS v_cleaned_orphans = ROW_COUNT;

  RETURN json_build_object(
    'success', true,
    'cleaned_challenges', v_cleaned_challenges,
    'cleaned_orphans', v_cleaned_orphans
  );
END;
$$;

-- Grants
GRANT EXECUTE ON FUNCTION join_battle_lobby TO authenticated;
GRANT EXECUTE ON FUNCTION leave_battle_lobby TO authenticated;
GRANT EXECUTE ON FUNCTION propose_battle_challenge TO authenticated;
GRANT EXECUTE ON FUNCTION accept_battle_challenge TO authenticated;
GRANT EXECUTE ON FUNCTION reject_battle_challenge TO authenticated;
GRANT EXECUTE ON FUNCTION set_player_ready TO authenticated;
GRANT EXECUTE ON FUNCTION quick_match_pair TO authenticated;
GRANT EXECUTE ON FUNCTION select_battle_bet TO authenticated;
GRANT EXECUTE ON FUNCTION cancel_battle_ready_room TO authenticated;
GRANT EXECUTE ON FUNCTION start_battle_from_ready_room TO authenticated;
GRANT EXECUTE ON FUNCTION play_battle_turn TO authenticated;
GRANT EXECUTE ON FUNCTION forfeit_battle TO authenticated;
GRANT EXECUTE ON FUNCTION get_battle_lobby TO authenticated;
GRANT EXECUTE ON FUNCTION cleanup_expired_battle_challenges TO authenticated;

-- =====================================================
-- BATTLE LEADERBOARD
-- =====================================================

CREATE OR REPLACE FUNCTION get_battle_leaderboard(p_limit INT DEFAULT 10)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN (
    SELECT COALESCE(json_agg(row_to_json(t)), '[]'::JSON)
    FROM (
      SELECT
        p.id AS "playerId",
        p.username,
        COUNT(*) FILTER (WHERE bs.status IN ('completed', 'forfeited')) AS "totalBattles",
        COUNT(*) FILTER (WHERE bs.winner_id = p.id) AS "wins",
        COUNT(*) FILTER (
          WHERE bs.status IN ('completed', 'forfeited')
            AND bs.winner_id IS NOT NULL
            AND bs.winner_id != p.id
        ) AS "losses",
        ROUND(
          (COUNT(*) FILTER (WHERE bs.winner_id = p.id))::NUMERIC /
          NULLIF(COUNT(*) FILTER (WHERE bs.status IN ('completed', 'forfeited')), 0) * 100
        , 0) AS "winRate"
      FROM players p
      INNER JOIN battle_sessions bs
        ON (bs.player1_id = p.id OR bs.player2_id = p.id)
      WHERE bs.status IN ('completed', 'forfeited')
      GROUP BY p.id, p.username
      HAVING COUNT(*) FILTER (WHERE bs.status IN ('completed', 'forfeited')) > 0
      ORDER BY "wins" DESC, "winRate" DESC
      LIMIT p_limit
    ) t
  );
END;
$$;

GRANT EXECUTE ON FUNCTION get_battle_leaderboard TO authenticated;

-- =====================================================
-- MIGRACIONES: LIMPIEZA DE COLUMNAS OBSOLETAS
-- =====================================================

-- Eliminar columnas del sistema de pity timer (ya no usado con shares)
-- Ejecutar en orden para evitar dependencias
ALTER TABLE players DROP COLUMN IF EXISTS pity_minutes_accumulated;
ALTER TABLE players DROP COLUMN IF EXISTS pity_blocks_today;
ALTER TABLE players DROP COLUMN IF EXISTS pity_last_reset_date;
ALTER TABLE players DROP COLUMN IF EXISTS mining_streak_minutes;

-- Eliminar columna is_pity de pending_blocks (ya no hay bloques pity)
ALTER TABLE pending_blocks DROP COLUMN IF EXISTS is_pity;

-- Eliminar función de reset de mining streak (ya no se usa)
DROP FUNCTION IF EXISTS reset_mining_streak(UUID);
