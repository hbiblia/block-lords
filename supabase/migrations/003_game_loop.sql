-- =====================================================
-- CRYPTO ARCADE MMO - Game Loop
-- Ejecutado por pg_cron cada minuto
-- =====================================================

-- Habilitar pg_cron (requiere permisos de superuser en Supabase)
-- CREATE EXTENSION IF NOT EXISTS pg_cron;

-- =====================================================
-- FUNCIÓN PRINCIPAL DEL GAME TICK
-- =====================================================

CREATE OR REPLACE FUNCTION game_tick()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_resources_processed INT := 0;
  v_block_mined BOOLEAN := false;
  v_block_height INT;
BEGIN
  -- 1. Procesar decay de recursos
  v_resources_processed := process_resource_decay();

  -- 2. Procesar minería (intentar minar bloque)
  SELECT * INTO v_block_mined, v_block_height FROM process_mining_tick();

  -- 3. Si se minó bloque, verificar ajuste de dificultad
  IF v_block_mined AND v_block_height IS NOT NULL THEN
    PERFORM check_difficulty_adjustment(v_block_height);
  END IF;

  RETURN json_build_object(
    'success', true,
    'resourcesProcessed', v_resources_processed,
    'blockMined', v_block_mined,
    'blockHeight', v_block_height,
    'timestamp', NOW()
  );
END;
$$;

-- =====================================================
-- PROCESAR DECAY DE RECURSOS
-- =====================================================

CREATE OR REPLACE FUNCTION process_resource_decay()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player RECORD;
  v_total_power NUMERIC;
  v_total_internet NUMERIC;
  v_energy_decay NUMERIC;
  v_internet_decay NUMERIC;
  v_new_energy NUMERIC;
  v_new_internet NUMERIC;
  v_processed INT := 0;
  v_decay_rate_energy NUMERIC := 0.1;
  v_decay_rate_internet NUMERIC := 0.05;
BEGIN
  -- Obtener jugadores con rigs activos
  FOR v_player IN
    SELECT p.id, p.energy, p.internet
    FROM players p
    WHERE EXISTS (
      SELECT 1 FROM player_rigs pr WHERE pr.player_id = p.id AND pr.is_active = true
    )
  LOOP
    -- Calcular consumo total
    SELECT
      COALESCE(SUM(r.power_consumption), 0),
      COALESCE(SUM(r.internet_consumption), 0)
    INTO v_total_power, v_total_internet
    FROM player_rigs pr
    JOIN rigs r ON r.id = pr.rig_id
    WHERE pr.player_id = v_player.id AND pr.is_active = true;

    -- Calcular decay
    v_energy_decay := v_total_power * v_decay_rate_energy;
    v_internet_decay := v_total_internet * v_decay_rate_internet;

    v_new_energy := GREATEST(0, v_player.energy - v_energy_decay);
    v_new_internet := GREATEST(0, v_player.internet - v_internet_decay);

    -- Actualizar recursos
    UPDATE players
    SET energy = v_new_energy, internet = v_new_internet
    WHERE id = v_player.id;

    -- Si algún recurso llegó a 0, apagar rigs
    IF v_new_energy = 0 OR v_new_internet = 0 THEN
      UPDATE player_rigs SET is_active = false WHERE player_id = v_player.id;

      INSERT INTO player_events (player_id, type, data)
      VALUES (v_player.id, 'rigs_shutdown', json_build_object(
        'reason', CASE WHEN v_new_energy = 0 THEN 'energy' ELSE 'internet' END
      ));
    END IF;

    v_processed := v_processed + 1;
  END LOOP;

  RETURN v_processed;
END;
$$;

-- =====================================================
-- PROCESAR TICK DE MINERÍA
-- =====================================================

CREATE OR REPLACE FUNCTION process_mining_tick()
RETURNS TABLE(block_mined BOOLEAN, block_height INT)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_active_rigs RECORD;
  v_network_hashrate NUMERIC := 0;
  v_difficulty NUMERIC;
  v_block_probability NUMERIC;
  v_roll NUMERIC;
  v_winner_player_id UUID;
  v_winner_hashrate NUMERIC;
  v_block blocks%ROWTYPE;
  v_reward NUMERIC;
  v_rigs_cursor CURSOR FOR
    SELECT
      pr.id as rig_id,
      pr.player_id,
      pr.condition,
      r.hashrate,
      p.reputation_score
    FROM player_rigs pr
    JOIN rigs r ON r.id = pr.rig_id
    JOIN players p ON p.id = pr.player_id
    WHERE pr.is_active = true
      AND p.energy > 0
      AND p.internet > 0;
  v_rig RECORD;
  v_effective_hashrate NUMERIC;
  v_rep_multiplier NUMERIC;
  v_hashrate_sum NUMERIC := 0;
  v_random_pick NUMERIC;
BEGIN
  -- Obtener dificultad actual
  SELECT COALESCE(ns.difficulty, 1000) INTO v_difficulty
  FROM network_stats ns WHERE ns.id = 'current';

  IF v_difficulty IS NULL THEN
    v_difficulty := 1000;
  END IF;

  -- Calcular hashrate total de la red
  FOR v_rig IN v_rigs_cursor LOOP
    -- Calcular multiplicador de reputación
    IF v_rig.reputation_score >= 80 THEN
      v_rep_multiplier := 1 + (v_rig.reputation_score - 80) * 0.01;
    ELSIF v_rig.reputation_score < 50 THEN
      v_rep_multiplier := 0.5 + (v_rig.reputation_score / 100.0);
    ELSE
      v_rep_multiplier := 1;
    END IF;

    v_effective_hashrate := v_rig.hashrate * (v_rig.condition / 100.0) * v_rep_multiplier;
    v_network_hashrate := v_network_hashrate + v_effective_hashrate;
  END LOOP;

  -- Actualizar hashrate de la red
  INSERT INTO network_stats (id, difficulty, hashrate, updated_at)
  VALUES ('current', v_difficulty, v_network_hashrate, NOW())
  ON CONFLICT (id) DO UPDATE SET hashrate = v_network_hashrate, updated_at = NOW();

  -- Si no hay mineros activos, no hay bloque
  IF v_network_hashrate = 0 THEN
    RETURN QUERY SELECT false, NULL::INT;
    RETURN;
  END IF;

  -- Probabilidad de minar bloque
  v_block_probability := v_network_hashrate / v_difficulty;
  v_roll := random();

  -- Si no se mina bloque
  IF v_roll > v_block_probability THEN
    RETURN QUERY SELECT false, NULL::INT;
    RETURN;
  END IF;

  -- Seleccionar ganador proporcional a hashrate
  v_random_pick := random() * v_network_hashrate;

  FOR v_rig IN v_rigs_cursor LOOP
    IF v_rig.reputation_score >= 80 THEN
      v_rep_multiplier := 1 + (v_rig.reputation_score - 80) * 0.01;
    ELSIF v_rig.reputation_score < 50 THEN
      v_rep_multiplier := 0.5 + (v_rig.reputation_score / 100.0);
    ELSE
      v_rep_multiplier := 1;
    END IF;

    v_effective_hashrate := v_rig.hashrate * (v_rig.condition / 100.0) * v_rep_multiplier;
    v_hashrate_sum := v_hashrate_sum + v_effective_hashrate;

    IF v_hashrate_sum >= v_random_pick THEN
      v_winner_player_id := v_rig.player_id;
      EXIT;
    END IF;
  END LOOP;

  -- Si por alguna razón no hay ganador, salir
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

  -- Calcular y otorgar recompensa
  v_reward := calculate_block_reward(v_block.height);

  UPDATE players
  SET crypto_balance = crypto_balance + v_reward
  WHERE id = v_winner_player_id;

  -- Registrar transacción
  INSERT INTO transactions (player_id, type, amount, currency, description)
  VALUES (v_winner_player_id, 'mining_reward', v_reward, 'crypto',
    'Recompensa por minar bloque #' || v_block.height);

  -- Incrementar reputación
  PERFORM update_reputation(v_winner_player_id, 0.1, 'block_mined');

  RETURN QUERY SELECT true, v_block.height;
END;
$$;

-- =====================================================
-- CREAR NUEVO BLOQUE
-- =====================================================

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
  -- Obtener último bloque
  SELECT height, hash INTO v_last_block
  FROM blocks
  ORDER BY height DESC
  LIMIT 1;

  v_new_height := COALESCE(v_last_block.height, 0) + 1;
  v_previous_hash := COALESCE(v_last_block.hash, REPEAT('0', 64));

  -- Generar hash (simplificado para el juego)
  v_new_hash := encode(sha256(
    (v_new_height::TEXT || v_previous_hash || p_miner_id::TEXT || NOW()::TEXT || random()::TEXT)::BYTEA
  ), 'hex');

  -- Insertar bloque
  INSERT INTO blocks (height, hash, previous_hash, miner_id, difficulty, network_hashrate)
  VALUES (v_new_height, v_new_hash, v_previous_hash, p_miner_id, p_difficulty, p_network_hashrate)
  RETURNING * INTO v_block;

  RETURN v_block;
END;
$$;

-- =====================================================
-- CALCULAR RECOMPENSA DE BLOQUE
-- =====================================================

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

-- =====================================================
-- VERIFICAR AJUSTE DE DIFICULTAD
-- =====================================================

CREATE OR REPLACE FUNCTION check_difficulty_adjustment(p_current_height INT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_adjustment_blocks INT := 100;
  v_target_block_time NUMERIC := 10; -- segundos
  v_recent_blocks RECORD;
  v_actual_time NUMERIC;
  v_target_time NUMERIC;
  v_adjustment_factor NUMERIC;
  v_current_difficulty NUMERIC;
  v_new_difficulty NUMERIC;
BEGIN
  -- Solo ajustar cada N bloques
  IF p_current_height % v_adjustment_blocks != 0 THEN
    RETURN;
  END IF;

  -- Obtener tiempos de bloques recientes
  SELECT
    MIN(created_at) as oldest,
    MAX(created_at) as newest,
    COUNT(*) as count
  INTO v_recent_blocks
  FROM (
    SELECT created_at FROM blocks
    ORDER BY height DESC
    LIMIT v_adjustment_blocks
  ) sub;

  IF v_recent_blocks.count < 2 THEN
    RETURN;
  END IF;

  -- Calcular tiempo real vs objetivo
  v_actual_time := EXTRACT(EPOCH FROM (v_recent_blocks.newest - v_recent_blocks.oldest));
  v_target_time := (v_recent_blocks.count - 1) * v_target_block_time;

  -- Factor de ajuste
  v_adjustment_factor := v_actual_time / NULLIF(v_target_time, 0);

  IF v_adjustment_factor IS NULL OR v_adjustment_factor = 0 THEN
    v_adjustment_factor := 1;
  END IF;

  -- Limitar ajuste a 4x máximo
  v_adjustment_factor := GREATEST(0.25, LEAST(4, v_adjustment_factor));

  -- Obtener dificultad actual y calcular nueva
  SELECT difficulty INTO v_current_difficulty FROM network_stats WHERE id = 'current';
  v_current_difficulty := COALESCE(v_current_difficulty, 1000);
  v_new_difficulty := GREATEST(100, v_current_difficulty * v_adjustment_factor);

  -- Actualizar dificultad
  UPDATE network_stats
  SET difficulty = v_new_difficulty, updated_at = NOW()
  WHERE id = 'current';
END;
$$;

-- =====================================================
-- CONFIGURAR CRON JOB (ejecutar en Supabase Dashboard)
-- =====================================================

-- Nota: Esto se debe configurar manualmente en el Dashboard de Supabase
-- o ejecutar con permisos de superuser:

-- SELECT cron.schedule(
--   'game-tick',           -- nombre del job
--   '* * * * *',           -- cada minuto
--   'SELECT game_tick();'  -- función a ejecutar
-- );

-- Para ver jobs programados:
-- SELECT * FROM cron.job;

-- Para eliminar un job:
-- SELECT cron.unschedule('game-tick');
