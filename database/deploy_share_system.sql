-- =====================================================
-- DEPLOYMENT: SISTEMA DE MINERÍA POR BLOQUES DE TIEMPO FIJO
-- =====================================================
-- Ejecutar este archivo completo en Supabase SQL Editor
-- Fecha: 2026-02-10
-- =====================================================

-- =====================================================
-- PASO 1: CREAR NUEVAS TABLAS
-- =====================================================

-- Tabla principal: Bloques de minería por tiempo
CREATE TABLE IF NOT EXISTS mining_blocks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  block_number INTEGER NOT NULL,
  started_at TIMESTAMPTZ NOT NULL,
  target_close_at TIMESTAMPTZ NOT NULL,
  closed_at TIMESTAMPTZ,
  total_shares NUMERIC DEFAULT 0,
  target_shares NUMERIC DEFAULT 100,
  reward NUMERIC NOT NULL,
  status TEXT DEFAULT 'active',  -- 'active', 'closed', 'distributed'
  difficulty_at_start NUMERIC NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_mining_blocks_status ON mining_blocks(status);
CREATE INDEX IF NOT EXISTS idx_mining_blocks_target_close ON mining_blocks(target_close_at);
CREATE INDEX IF NOT EXISTS idx_mining_blocks_number ON mining_blocks(block_number DESC);

-- Tabla de contribuciones: Shares por jugador por bloque
CREATE TABLE IF NOT EXISTS player_shares (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  mining_block_id UUID NOT NULL REFERENCES mining_blocks(id) ON DELETE CASCADE,
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  shares_count NUMERIC DEFAULT 0,
  last_share_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(mining_block_id, player_id)
);

CREATE INDEX IF NOT EXISTS idx_player_shares_block ON player_shares(mining_block_id);
CREATE INDEX IF NOT EXISTS idx_player_shares_player ON player_shares(player_id);

-- Tabla de historial (opcional, para análisis)
CREATE TABLE IF NOT EXISTS share_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  mining_block_id UUID NOT NULL REFERENCES mining_blocks(id) ON DELETE CASCADE,
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  player_rig_id UUID REFERENCES player_rigs(id) ON DELETE SET NULL,
  shares_generated NUMERIC NOT NULL,
  hashrate_at_generation NUMERIC NOT NULL,
  difficulty NUMERIC NOT NULL,
  generated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_share_history_block ON share_history(mining_block_id);
CREATE INDEX IF NOT EXISTS idx_share_history_player ON share_history(player_id, generated_at DESC);

-- =====================================================
-- PASO 2: MODIFICAR TABLAS EXISTENTES
-- =====================================================

-- Modificaciones a network_stats
ALTER TABLE network_stats ADD COLUMN IF NOT EXISTS current_mining_block_id UUID REFERENCES mining_blocks(id);
ALTER TABLE network_stats ADD COLUMN IF NOT EXISTS last_block_closed_at TIMESTAMPTZ;
ALTER TABLE network_stats ADD COLUMN IF NOT EXISTS target_shares_per_block NUMERIC DEFAULT 100;

-- Modificaciones a blocks
ALTER TABLE blocks ADD COLUMN IF NOT EXISTS is_share_based BOOLEAN DEFAULT false;
ALTER TABLE blocks ADD COLUMN IF NOT EXISTS total_shares NUMERIC;

-- Modificaciones a pending_blocks
ALTER TABLE pending_blocks ADD COLUMN IF NOT EXISTS shares_contributed NUMERIC;
ALTER TABLE pending_blocks ADD COLUMN IF NOT EXISTS total_block_shares NUMERIC;
ALTER TABLE pending_blocks ADD COLUMN IF NOT EXISTS share_percentage NUMERIC;

-- =====================================================
-- PASO 3: CREAR FUNCIONES
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
BEGIN
  -- Obtener configuración actual
  SELECT difficulty, target_shares_per_block
  INTO v_difficulty, v_target_shares
  FROM network_stats WHERE id = 'current';

  IF v_difficulty IS NULL THEN v_difficulty := 15000; END IF;
  IF v_target_shares IS NULL THEN v_target_shares := 100; END IF;

  -- Calcular número de bloque
  SELECT COALESCE(MAX(block_number), 0) + 1 INTO v_block_number FROM mining_blocks;

  -- Calcular recompensa (con halving)
  v_reward := calculate_block_reward(v_block_number);

  -- Calcular tiempo objetivo (30 minutos)
  v_target_close_at := NOW() + INTERVAL '30 minutes';

  -- Crear nuevo bloque de minería
  INSERT INTO mining_blocks (
    block_number,
    started_at,
    target_close_at,
    target_shares,
    reward,
    difficulty_at_start,
    status
  ) VALUES (
    v_block_number,
    NOW(),
    v_target_close_at,
    v_target_shares,
    v_reward,
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
           COALESCE(pr.hashrate_level, 1) as hashrate_level
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

    -- Penalización por condición
    IF v_rig.condition >= 80 THEN
      v_condition_penalty := 1.0;
    ELSE
      v_condition_penalty := 0.3 + (v_rig.condition / 80.0) * 0.7;
    END IF;

    -- Calcular hashrate efectivo
    v_effective_hashrate := v_rig.hashrate * v_condition_penalty * v_rep_multiplier *
                           v_temp_penalty * v_hashrate_mult;

    -- Calcular probabilidad de generar shares
    v_shares_probability := (v_effective_hashrate / v_difficulty) * v_tick_duration * v_luck_mult;

    -- Generar shares (modelo probabilístico con redondeo)
    v_base_shares := FLOOR(v_shares_probability);
    v_fractional := v_shares_probability - v_base_shares;
    v_random := random();

    IF v_random < v_fractional THEN
      v_shares_generated := v_base_shares + 1;
    ELSE
      v_shares_generated := v_base_shares;
    END IF;

    -- Registrar shares si se generaron
    IF v_shares_generated > 0 THEN
      -- Actualizar o insertar en player_shares
      INSERT INTO player_shares (mining_block_id, player_id, shares_count, last_share_at)
      VALUES (v_mining_block_id, v_rig.player_id, v_shares_generated, NOW())
      ON CONFLICT (mining_block_id, player_id)
      DO UPDATE SET
        shares_count = player_shares.shares_count + v_shares_generated,
        last_share_at = NOW();

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

  -- Actualizar total de shares del bloque
  UPDATE mining_blocks
  SET total_shares = COALESCE(total_shares, 0) + v_total_shares_generated
  WHERE id = v_mining_block_id;

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
    PERFORM initialize_mining_block();

    RETURN json_build_object(
      'success', true,
      'participants', 0,
      'total_shares', 0,
      'rewards_distributed', 0,
      'difficulty_adjusted', false
    );
  END IF;

  -- Distribuir recompensas proporcionalmente
  FOR v_participant IN
    SELECT player_id, shares_count
    FROM player_shares
    WHERE mining_block_id = p_mining_block_id
    ORDER BY shares_count DESC
  LOOP
    v_participants_count := v_participants_count + 1;

    -- Calcular porcentaje de shares
    v_share_percentage := (v_participant.shares_count / v_mining_block.total_shares) * 100;

    -- Calcular recompensa
    v_player_reward := v_mining_block.reward * (v_participant.shares_count / v_mining_block.total_shares);

    -- Aplicar bonus premium (+50%)
    IF is_player_premium(v_participant.player_id) THEN
      v_player_reward := v_player_reward * 1.5;
    END IF;

    -- Mínimo 0.01 crypto si contribuyó
    v_player_reward := GREATEST(0.01, v_player_reward);

    -- Crear entrada en pending_blocks
    INSERT INTO pending_blocks (
      block_id,
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
    SET blocks_mined = COALESCE(blocks_mined, 0) + 1,
        pity_minutes_accumulated = 0
    WHERE id = v_participant.player_id;

    -- Actualizar misiones
    PERFORM update_mission_progress(v_participant.player_id, 'mine_blocks', 1);
  END LOOP;

  -- Marcar como distribuido
  UPDATE mining_blocks SET status = 'distributed' WHERE id = p_mining_block_id;

  -- Ajustar dificultad
  PERFORM adjust_share_difficulty(p_mining_block_id);

  -- Crear nuevo bloque
  PERFORM initialize_mining_block();

  -- Actualizar network_stats
  UPDATE network_stats SET last_block_closed_at = NOW() WHERE id = 'current';

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
  v_smoothing_factor NUMERIC := 0.7;
  v_max_change NUMERIC := 0.25;
  v_min_difficulty NUMERIC := 100;
  v_max_difficulty NUMERIC := 1000000;
  v_should_adjust BOOLEAN := false;
BEGIN
  SELECT * INTO v_mining_block FROM mining_blocks WHERE id = p_mining_block_id;

  IF v_mining_block IS NULL THEN
    RETURN json_build_object('adjusted', false, 'error', 'Block not found');
  END IF;

  SELECT difficulty, target_shares_per_block, last_difficulty_adjustment
  INTO v_current_difficulty, v_target_shares, v_last_adjustment
  FROM network_stats WHERE id = 'current';

  v_actual_shares := COALESCE(v_mining_block.total_shares, 0);

  IF v_last_adjustment IS NOT NULL THEN
    v_time_since_adjustment := NOW() - v_last_adjustment;
  ELSE
    v_time_since_adjustment := INTERVAL '0';
  END IF;

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
      'target_shares', v_target_shares
    );
  END IF;

  IF v_actual_shares > 0 THEN
    v_adjustment_ratio := v_actual_shares / v_target_shares;
  ELSE
    v_adjustment_ratio := 0.5;
  END IF;

  v_new_difficulty := v_current_difficulty * (1 + v_smoothing_factor * (v_adjustment_ratio - 1));
  v_new_difficulty := GREATEST(v_new_difficulty, v_current_difficulty * (1 - v_max_change));
  v_new_difficulty := LEAST(v_new_difficulty, v_current_difficulty * (1 + v_max_change));
  v_new_difficulty := GREATEST(v_min_difficulty, LEAST(v_max_difficulty, v_new_difficulty));

  UPDATE network_stats
  SET difficulty = v_new_difficulty, last_difficulty_adjustment = NOW()
  WHERE id = 'current';

  RETURN json_build_object(
    'adjusted', true,
    'old_difficulty', v_current_difficulty,
    'new_difficulty', v_new_difficulty,
    'actual_shares', v_actual_shares,
    'target_shares', v_target_shares
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
  FOR v_block IN
    SELECT id FROM mining_blocks
    WHERE status = 'active' AND target_close_at <= NOW()
  LOOP
    v_close_result := close_mining_block(v_block.id);
    v_blocks_closed := v_blocks_closed + 1;
  END LOOP;

  RETURN json_build_object('success', true, 'blocks_closed', v_blocks_closed);
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
    RETURN json_build_object('active', false, 'block_number', NULL);
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
    'difficulty', v_mining_block.difficulty_at_start
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
BEGIN
  SELECT id, total_shares, reward INTO v_mining_block_id, v_total_shares, v_block_reward
  FROM mining_blocks WHERE status = 'active' ORDER BY started_at DESC LIMIT 1;

  IF v_mining_block_id IS NULL THEN
    RETURN json_build_object('has_shares', false, 'shares', 0);
  END IF;

  SELECT COALESCE(shares_count, 0) INTO v_player_shares
  FROM player_shares
  WHERE mining_block_id = v_mining_block_id AND player_id = p_player_id;

  IF v_player_shares IS NULL OR v_player_shares = 0 THEN
    RETURN json_build_object('has_shares', false, 'shares', 0, 'mining_block_id', v_mining_block_id);
  END IF;

  IF v_total_shares > 0 THEN
    v_share_percentage := (v_player_shares / v_total_shares) * 100;
    v_estimated_reward := v_block_reward * (v_player_shares / v_total_shares);

    IF is_player_premium(p_player_id) THEN
      v_estimated_reward := v_estimated_reward * 1.5;
    END IF;
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

-- Función principal: Ejecuta el tick del sistema de shares
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
BEGIN
  -- Marcar jugadores offline
  WITH inactive_players AS (
    UPDATE players SET is_online = false
    WHERE is_online = true AND last_seen < NOW() - INTERVAL '5 minutes'
    RETURNING id
  )
  SELECT COUNT(*) INTO v_inactive_marked FROM inactive_players;

  IF v_inactive_marked > 0 THEN
    UPDATE player_rigs
    SET is_active = false, deactivated_at = NOW(), activated_at = NULL
    WHERE player_id IN (
      SELECT id FROM players
      WHERE is_online = false
        AND last_seen < NOW() - INTERVAL '5 minutes'
        AND last_seen > NOW() - INTERVAL '6 minutes'
    ) AND is_active = true AND NOT rig_has_autonomous_boost(id);
    GET DIAGNOSTICS v_rigs_shutdown = ROW_COUNT;
  END IF;

  -- Procesar decay de recursos
  v_resources_result := process_resource_decay();

  -- Generar shares
  v_shares_result := generate_shares_tick();

  -- Verificar y cerrar bloques
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
-- PASO 4: GRANTS PARA FUNCIONES
-- =====================================================

GRANT EXECUTE ON FUNCTION initialize_mining_block TO authenticated;
GRANT EXECUTE ON FUNCTION generate_shares_tick TO authenticated;
GRANT EXECUTE ON FUNCTION close_mining_block TO authenticated;
GRANT EXECUTE ON FUNCTION adjust_share_difficulty TO authenticated;
GRANT EXECUTE ON FUNCTION check_and_close_blocks TO authenticated;
GRANT EXECUTE ON FUNCTION get_current_mining_block_info TO authenticated;
GRANT EXECUTE ON FUNCTION get_player_shares_info TO authenticated;
GRANT EXECUTE ON FUNCTION game_tick_share_system TO authenticated;

-- =====================================================
-- PASO 5: CONFIGURAR DIFICULTAD INICIAL
-- =====================================================

-- Calcular dificultad inicial basándose en hashrate promedio
DO $$
DECLARE
  v_avg_hashrate NUMERIC;
  v_initial_difficulty NUMERIC;
BEGIN
  -- Obtener hashrate promedio de los últimos registros
  SELECT AVG(hashrate) INTO v_avg_hashrate FROM network_stats;

  -- Si no hay datos, usar un valor por defecto
  IF v_avg_hashrate IS NULL OR v_avg_hashrate = 0 THEN
    v_avg_hashrate := 50000;  -- Valor por defecto
  END IF;

  -- Calcular dificultad: (hashrate_promedio * 30 minutos) / 100 shares objetivo
  v_initial_difficulty := (v_avg_hashrate * 30) / 100;

  -- Asegurar mínimo de 1000
  v_initial_difficulty := GREATEST(1000, v_initial_difficulty);

  -- Actualizar network_stats
  UPDATE network_stats
  SET difficulty = v_initial_difficulty,
      target_shares_per_block = 100,
      last_difficulty_adjustment = NOW()
  WHERE id = 'current';

  RAISE NOTICE 'Dificultad inicial configurada: %', v_initial_difficulty;
END $$;

-- =====================================================
-- PASO 6: INICIALIZAR PRIMER BLOQUE
-- =====================================================

SELECT initialize_mining_block();

-- =====================================================
-- DEPLOYMENT COMPLETADO
-- =====================================================

-- Verificar que todo está correcto
SELECT
  'Tablas creadas' as paso,
  EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'mining_blocks') as completado
UNION ALL
SELECT
  'Funciones creadas',
  EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'game_tick_share_system')
UNION ALL
SELECT
  'Bloque inicial creado',
  EXISTS(SELECT 1 FROM mining_blocks WHERE status = 'active');

-- =====================================================
-- SIGUIENTE PASO MANUAL: CONFIGURAR CRON JOB
-- =====================================================
-- Ejecutar en Supabase SQL Editor:
--
-- 1. Desactivar cron antiguo:
-- SELECT cron.unschedule('game_tick_job');
--
-- 2. Activar nuevo cron (cada 30 segundos):
-- SELECT cron.schedule(
--   'game_tick_share_system_job',
--   '30 seconds',
--   'SELECT game_tick_share_system()'
-- );
--
-- 3. Verificar:
-- SELECT * FROM cron.job;
-- =====================================================
