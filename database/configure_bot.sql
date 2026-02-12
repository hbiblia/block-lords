-- =====================================================
-- CONFIGURACIÓN COMPLETA DEL BOT DE BALANCEO
-- =====================================================
-- Bot: Richart
-- ID: 00000000-0000-0000-0000-000000000001
-- Rig: Antminer S9 (1000 hashrate)
--
-- El bot funciona como un jugador real:
-- ✅ Genera shares con su rig S9 (1000 hashrate)
-- ✅ Recibe recompensas proporcionales
-- ✅ Las recompensas quedan en pending_blocks (no las reclama)
-- ✅ Nunca en cooldown
-- ✅ Siempre con rig activo
-- =====================================================

BEGIN;

-- =====================================================
-- PASO 1: CREAR BOT (SI NO EXISTE)
-- =====================================================

-- Crear usuario en auth.users
INSERT INTO auth.users (
  id,
  instance_id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  created_at,
  updated_at,
  raw_app_meta_data,
  raw_user_meta_data,
  is_super_admin,
  confirmation_token,
  email_change_token_new,
  recovery_token
) VALUES (
  '00000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated',
  'authenticated',
  'bot@system.local',
  '$2a$10$AAAAAAAAAAAAAAAAAAAAAA',  -- Password hash inválido (el bot nunca inicia sesión)
  NOW(),
  NOW(),
  NOW(),
  '{"provider":"system","providers":["system"]}',
  '{"username":"Richart","is_bot":true}',
  false,
  '',
  '',
  ''
)
ON CONFLICT (id) DO NOTHING;

-- Crear jugador bot
INSERT INTO players (
  id,
  username,
  email,
  gamecoin_balance,
  crypto_balance,
  ron_balance,
  energy,
  internet,
  max_energy,
  max_internet,
  reputation_score,
  is_online,
  created_at
) VALUES (
  '00000000-0000-0000-0000-000000000001',
  'Richart',
  'bot@system.local',
  0,                 -- Sin balance GameCoin
  0,                 -- Sin balance BLC (recibe rewards pero no las reclama)
  0,                 -- Sin balance RON
  100,               -- Energía máxima
  100,               -- Internet máximo
  100,               -- Max energía
  100,               -- Max internet
  100,               -- Reputación perfecta
  true,              -- Siempre online
  NOW()
)
ON CONFLICT (id) DO UPDATE SET
  energy = 100,
  internet = 100,
  is_online = true;

-- =====================================================
-- PASO 2: CREAR/ACTUALIZAR RIG S9
-- =====================================================

INSERT INTO rigs (
  id,
  name,
  description,
  hashrate,
  power_consumption,
  internet_consumption,
  tier,
  base_price,
  currency,
  repair_cost,
  max_upgrade_level
) VALUES (
  's9',
  'Antminer S9',
  'Rig profesional con 1000 TH/s de potencia',
  1000,              -- ✅ 1000 hashrate
  15,
  8,
  'advanced',
  50000,
  'gamecoin',
  25000,
  5
)
ON CONFLICT (id) DO UPDATE SET
  hashrate = 1000,
  power_consumption = 15,
  internet_consumption = 8,
  tier = 'advanced',
  description = 'Rig profesional con 1000 TH/s de potencia';

-- =====================================================
-- PASO 3: ASIGNAR RIG S9 AL BOT
-- =====================================================

-- Eliminar rigs anteriores del bot
DELETE FROM player_rigs
WHERE player_id = '00000000-0000-0000-0000-000000000001';

-- Asignar rig S9 al bot
INSERT INTO player_rigs (
  player_id,
  rig_id,
  condition,
  max_condition,
  is_active,
  temperature,
  hashrate_level,
  efficiency_level,
  thermal_level,
  times_repaired,
  acquired_at,
  activated_at
) VALUES (
  '00000000-0000-0000-0000-000000000001',
  's9',              -- ✅ Rig S9 con 1000 hashrate
  100,               -- Condición perfecta
  100,
  true,              -- Activo
  40,                -- Temperatura normal
  1,                 -- Nivel hashrate base
  1,
  1,
  0,
  NOW(),
  NOW()
);

-- =====================================================
-- PASO 4: PROTEGER RIG DEL BOT
-- =====================================================

-- Función para asegurar que el bot siempre tenga rig activo
CREATE OR REPLACE FUNCTION ensure_bot_rig_active()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_bot_id UUID := '00000000-0000-0000-0000-000000000001';
  v_rig_count INTEGER;
BEGIN
  -- Contar rigs activos del bot
  SELECT COUNT(*) INTO v_rig_count
  FROM player_rigs
  WHERE player_id = v_bot_id AND is_active = true;

  -- Si no tiene rig activo, activar el S9
  IF v_rig_count = 0 THEN
    UPDATE player_rigs
    SET is_active = true,
        condition = 100,
        temperature = 40,
        activated_at = NOW()
    WHERE player_id = v_bot_id
      AND rig_id = 's9';

    -- Si no existía el S9, crearlo
    IF NOT FOUND THEN
      INSERT INTO player_rigs (
        player_id, rig_id, condition, max_condition,
        is_active, temperature, activated_at
      ) VALUES (
        v_bot_id, 's9', 100, 100,
        true, 40, NOW()
      );
    END IF;

    RETURN true;
  END IF;

  RETURN false;
END;
$$;

-- Trigger para prevenir desactivación del rig del bot
CREATE OR REPLACE FUNCTION auto_activate_bot_rig()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  -- Si intentan desactivar rig del bot, reactivarlo
  IF NEW.player_id = '00000000-0000-0000-0000-000000000001'
     AND NEW.is_active = false THEN
    NEW.is_active := true;
    NEW.condition := 100;
    NEW.temperature := 40;
    NEW.activated_at := NOW();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_bot_rig_always_active ON player_rigs;
CREATE TRIGGER trigger_bot_rig_always_active
  BEFORE UPDATE ON player_rigs
  FOR EACH ROW
  EXECUTE FUNCTION auto_activate_bot_rig();

-- =====================================================
-- PASO 5: EXCLUIR BOT DEL COOLDOWN
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
  v_bot_id UUID := '00000000-0000-0000-0000-000000000001';
BEGIN
  -- ✅ Bot NUNCA está en cooldown
  IF p_player_id = v_bot_id THEN
    RETURN false;
  END IF;

  -- Calcular umbral consistente por jugador usando hash del UUID
  v_hash_value := abs(('x' || substr(p_player_id::TEXT, 1, 8))::BIT(32)::INTEGER);
  v_threshold := p_min_threshold + (v_hash_value % (p_max_threshold - p_min_threshold + 1));

  v_time_window := (p_time_window_minutes || ' minutes')::INTERVAL;

  -- Contar bloques ganados en la ventana de tiempo
  SELECT COUNT(*) INTO v_recent_blocks
  FROM blocks
  WHERE miner_id = p_player_id
    AND created_at >= NOW() - v_time_window;

  RETURN v_recent_blocks > v_threshold;
END;
$$;

-- =====================================================
-- PASO 6: FUNCIONES DE MONITOREO
-- =====================================================

-- Dashboard completo del bot
CREATE OR REPLACE FUNCTION get_bot_status()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_bot_id UUID := '00000000-0000-0000-0000-000000000001';
  v_player RECORD;
  v_rigs JSON;
  v_shares JSON;
  v_pending_blocks INTEGER;
  v_network_stats RECORD;
BEGIN
  -- Info del jugador bot
  SELECT * INTO v_player FROM players WHERE id = v_bot_id;

  -- Info de rigs
  SELECT json_agg(json_build_object(
    'rig_id', pr.rig_id,
    'is_active', pr.is_active,
    'condition', pr.condition,
    'temperature', pr.temperature,
    'hashrate', r.hashrate
  )) INTO v_rigs
  FROM player_rigs pr
  JOIN rigs r ON r.id = pr.rig_id
  WHERE pr.player_id = v_bot_id;

  -- Shares en bloque actual
  SELECT json_build_object(
    'shares_count', ps.shares_count,
    'last_share_at', ps.last_share_at
  ) INTO v_shares
  FROM player_shares ps
  JOIN mining_blocks mb ON mb.id = ps.mining_block_id
  WHERE ps.player_id = v_bot_id
    AND mb.status = 'active'
  LIMIT 1;

  -- Bloques pendientes (recompensas que no ha reclamado)
  SELECT COUNT(*) INTO v_pending_blocks
  FROM pending_blocks
  WHERE player_id = v_bot_id;

  -- Stats de red
  SELECT difficulty, hashrate, active_miners
  INTO v_network_stats
  FROM network_stats WHERE id = 'current';

  RETURN json_build_object(
    'bot_id', v_bot_id,
    'username', v_player.username,
    'is_online', v_player.is_online,
    'energy', v_player.energy,
    'internet', v_player.internet,
    'rigs', v_rigs,
    'current_shares', v_shares,
    'pending_blocks_unclaimed', v_pending_blocks,
    'network', json_build_object(
      'difficulty', v_network_stats.difficulty,
      'total_hashrate', v_network_stats.hashrate,
      'active_miners', v_network_stats.active_miners
    ),
    'health_checks', json_build_object(
      'has_active_rig', EXISTS(
        SELECT 1 FROM player_rigs
        WHERE player_id = v_bot_id AND is_active = true
      ),
      'infinite_resources', v_player.energy = 100 AND v_player.internet = 100,
      'is_online', v_player.is_online,
      'not_in_cooldown', NOT is_player_in_mining_cooldown(v_bot_id)
    )
  );
END;
$$;

-- Verificar distribución de shares (últimos 100 bloques)
CREATE OR REPLACE FUNCTION get_bot_participation_stats()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_bot_id UUID := '00000000-0000-0000-0000-000000000001';
  v_bot_shares_total INTEGER;
  v_player_shares_total INTEGER;
  v_bot_rewards NUMERIC;
BEGIN
  -- Total shares del bot (últimos 100 bloques)
  SELECT COALESCE(SUM(shares_count), 0) INTO v_bot_shares_total
  FROM player_shares
  WHERE player_id = v_bot_id
    AND mining_block_id IN (
      SELECT id FROM mining_blocks
      WHERE status = 'distributed'
      ORDER BY block_number DESC
      LIMIT 100
    );

  -- Total shares de jugadores (últimos 100 bloques)
  SELECT COALESCE(SUM(shares_count), 0) INTO v_player_shares_total
  FROM player_shares
  WHERE player_id != v_bot_id
    AND mining_block_id IN (
      SELECT id FROM mining_blocks
      WHERE status = 'distributed'
      ORDER BY block_number DESC
      LIMIT 100
    );

  -- Recompensas pendientes del bot
  SELECT COALESCE(SUM(reward), 0) INTO v_bot_rewards
  FROM pending_blocks
  WHERE player_id = v_bot_id;

  RETURN json_build_object(
    'last_100_blocks', json_build_object(
      'bot_shares', v_bot_shares_total,
      'player_shares', v_player_shares_total,
      'bot_percentage', CASE
        WHEN (v_bot_shares_total + v_player_shares_total) > 0
        THEN ROUND((v_bot_shares_total::NUMERIC / (v_bot_shares_total + v_player_shares_total)) * 100, 2)
        ELSE 0
      END
    ),
    'bot_unclaimed_rewards', v_bot_rewards
  );
END;
$$;

GRANT EXECUTE ON FUNCTION get_bot_status TO authenticated;
GRANT EXECUTE ON FUNCTION get_bot_participation_stats TO authenticated;

-- =====================================================
-- PASO 7: VERIFICACIÓN FINAL
-- =====================================================

DO $$
DECLARE
  v_bot_record RECORD;
BEGIN
  SELECT
    p.username,
    p.is_online,
    p.energy,
    p.internet,
    r.name as rig_name,
    r.hashrate,
    pr.is_active,
    pr.condition,
    pr.temperature
  INTO v_bot_record
  FROM players p
  JOIN player_rigs pr ON pr.player_id = p.id
  JOIN rigs r ON r.id = pr.rig_id
  WHERE p.id = '00000000-0000-0000-0000-000000000001';

  IF NOT FOUND THEN
    RAISE EXCEPTION '❌ Bot no encontrado o no tiene rig asignado';
  END IF;

  IF v_bot_record.rig_name != 'Antminer S9' THEN
    RAISE EXCEPTION '❌ Bot no tiene rig S9 asignado: %', v_bot_record.rig_name;
  END IF;

  IF v_bot_record.hashrate != 1000 THEN
    RAISE EXCEPTION '❌ Hashrate del S9 incorrecto. Esperado: 1000, Actual: %', v_bot_record.hashrate;
  END IF;

  IF NOT v_bot_record.is_active THEN
    RAISE EXCEPTION '❌ Rig del bot no está activo';
  END IF;

  RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
  RAISE NOTICE '✅ CONFIGURACIÓN EXITOSA';
  RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
  RAISE NOTICE 'Bot: %', v_bot_record.username;
  RAISE NOTICE 'Rig: %', v_bot_record.rig_name;
  RAISE NOTICE 'Hashrate: %', v_bot_record.hashrate;
  RAISE NOTICE 'Online: %', v_bot_record.is_online;
  RAISE NOTICE 'Activo: %', v_bot_record.is_active;
  RAISE NOTICE 'Condición: %%%', v_bot_record.condition;
  RAISE NOTICE 'Temperatura: %°C', v_bot_record.temperature;
  RAISE NOTICE 'Energía: %', v_bot_record.energy;
  RAISE NOTICE 'Internet: %', v_bot_record.internet;
  RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;

COMMIT;

-- =====================================================
-- RESUMEN DE FUNCIONAMIENTO
-- =====================================================

/*
✅ CÓMO FUNCIONA EL BOT AHORA:

1. GENERACIÓN DE SHARES:
   • Bot se procesa en el loop principal de generate_shares_tick()
   • Usa el hashrate real de su rig S9 (1000)
   • Genera shares cada 30 segundos como cualquier jugador
   • Sufre las mismas penalizaciones (temperatura, condición, etc.)

2. DISTRIBUCIÓN DE RECOMPENSAS:
   • Bot incluido en close_mining_block()
   • Recibe su porcentaje proporcional de recompensas
   • Las recompensas se guardan en pending_blocks
   • El bot nunca las reclama (no tiene acceso a UI)

3. VENTAJAS:
   • Simple: Bot = jugador normal con rig S9
   • Predecible: Siempre 1000 hashrate
   • Realista: Sufre penalizaciones como jugadores
   • Justo: Toda la recompensa se distribuye (nada se pierde)

EJEMPLO CON 2 JUGADORES DE 1000 C/U:

Bloque: 5000 crypto total
- Jugador A: 40 shares (40%) → 2000 crypto ✅
- Jugador B: 30 shares (30%) → 1500 crypto ✅
- Bot: 30 shares (30%) → 1500 crypto ✅ (en pending_blocks)

Total distribuido: 5000 crypto (100% correcto)

AJUSTAR FUERZA DEL BOT:

Más fuerte:
  UPDATE rigs SET hashrate = 1500 WHERE id = 's9';

Más débil:
  UPDATE rigs SET hashrate = 500 WHERE id = 's9';

MONITOREO:

Ver estado del bot:
  SELECT * FROM get_bot_status();

Ver participación (últimos 100 bloques):
  SELECT * FROM get_bot_participation_stats();

Ver shares en bloque actual:
  SELECT ps.shares_count, mb.total_shares,
         ROUND((ps.shares_count::NUMERIC / mb.total_shares) * 100, 2) as bot_percentage
  FROM player_shares ps
  JOIN mining_blocks mb ON mb.id = ps.mining_block_id
  WHERE ps.player_id = '00000000-0000-0000-0000-000000000001'
    AND mb.status = 'active';
*/

-- =====================================================
-- DEPLOYMENT NOTES
-- =====================================================

/*
IMPORTANTE:

1. Este script es idempotente (se puede ejecutar múltiples veces)

2. Ya aplicaste los cambios en all_functions.sql para:
   • Eliminar lógica sintética del bot en generate_shares_tick()
   • Permitir que bot reciba recompensas en close_mining_block()

3. Para aplicar este script:
   psql -d block_lords -f database/configure_bot.sql

4. Archivos que DEBES MANTENER:
   • all_functions.sql (YA MODIFICADO)
   • configure_bot.sql (ESTE ARCHIVO)

5. Archivos obsoletos (puedes eliminarlos):
   • upgrade_bot_to_s9.sql
   • fix_bot_use_real_hashrate.sql
   • deploy_bot_real_hashrate.sql
   • fix_balance_bot.sql
   • fix_bot_cooldown.sql
   • monitor_balance_bot.sql
   • fix_bot_hashrate_calculation.sql
   • create_balance_bot.sql
*/
