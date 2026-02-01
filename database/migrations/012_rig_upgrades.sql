-- =====================================================
-- MIGRACIÓN: Sistema de Mejoras de Rigs con Crypto
-- =====================================================

-- Agregar nivel máximo de upgrade a la tabla rigs (basado en tier)
ALTER TABLE rigs
ADD COLUMN IF NOT EXISTS max_upgrade_level INTEGER DEFAULT 3;

-- Actualizar niveles máximos según tier
UPDATE rigs SET max_upgrade_level = CASE tier
  WHEN 'basic' THEN 2
  WHEN 'standard' THEN 3
  WHEN 'advanced' THEN 4
  WHEN 'elite' THEN 5
  ELSE 3
END;

-- Agregar columnas de nivel de mejora a player_rigs
ALTER TABLE player_rigs
ADD COLUMN IF NOT EXISTS hashrate_level INTEGER DEFAULT 1,
ADD COLUMN IF NOT EXISTS efficiency_level INTEGER DEFAULT 1,
ADD COLUMN IF NOT EXISTS thermal_level INTEGER DEFAULT 1;

-- Agregar constraints para niveles válidos
ALTER TABLE player_rigs
ADD CONSTRAINT hashrate_level_valid CHECK (hashrate_level >= 1 AND hashrate_level <= 5),
ADD CONSTRAINT efficiency_level_valid CHECK (efficiency_level >= 1 AND efficiency_level <= 5),
ADD CONSTRAINT thermal_level_valid CHECK (thermal_level >= 1 AND thermal_level <= 5);

-- Tabla de costos de upgrade por nivel
CREATE TABLE IF NOT EXISTS upgrade_costs (
  level INTEGER PRIMARY KEY,
  crypto_cost NUMERIC NOT NULL,
  hashrate_bonus NUMERIC NOT NULL,  -- % adicional de hashrate
  efficiency_bonus NUMERIC NOT NULL, -- % reducción de consumo energético
  thermal_bonus NUMERIC NOT NULL     -- reducción de temperatura base en grados
);

-- Insertar costos y bonificaciones por nivel
INSERT INTO upgrade_costs (level, crypto_cost, hashrate_bonus, efficiency_bonus, thermal_bonus)
VALUES
  (2, 100, 10, 5, 2),   -- Nivel 2: 100 crypto, +10% hash, -5% energy, -2°C
  (3, 300, 20, 10, 4),  -- Nivel 3: 300 crypto, +20% hash, -10% energy, -4°C
  (4, 700, 35, 15, 6),  -- Nivel 4: 700 crypto, +35% hash, -15% energy, -6°C
  (5, 1500, 50, 20, 8)  -- Nivel 5: 1500 crypto, +50% hash, -20% energy, -8°C
ON CONFLICT (level) DO UPDATE SET
  crypto_cost = EXCLUDED.crypto_cost,
  hashrate_bonus = EXCLUDED.hashrate_bonus,
  efficiency_bonus = EXCLUDED.efficiency_bonus,
  thermal_bonus = EXCLUDED.thermal_bonus;

-- Comentarios
COMMENT ON COLUMN player_rigs.hashrate_level IS 'Nivel de mejora de hashrate (1-5)';
COMMENT ON COLUMN player_rigs.efficiency_level IS 'Nivel de mejora de eficiencia energética (1-5)';
COMMENT ON COLUMN player_rigs.thermal_level IS 'Nivel de mejora térmica (1-5)';
COMMENT ON COLUMN rigs.max_upgrade_level IS 'Nivel máximo de mejora permitido según tier';

-- =====================================================
-- FUNCIÓN: Mejorar un stat del rig
-- =====================================================
CREATE OR REPLACE FUNCTION upgrade_rig(
  p_player_id UUID,
  p_player_rig_id UUID,
  p_upgrade_type TEXT  -- 'hashrate', 'efficiency', 'thermal'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player RECORD;
  v_player_rig RECORD;
  v_rig RECORD;
  v_current_level INTEGER;
  v_next_level INTEGER;
  v_upgrade_cost RECORD;
  v_column_name TEXT;
BEGIN
  -- Validar tipo de upgrade
  IF p_upgrade_type NOT IN ('hashrate', 'efficiency', 'thermal') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Tipo de mejora inválido');
  END IF;

  -- Obtener jugador
  SELECT * INTO v_player FROM players WHERE id = p_player_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Jugador no encontrado');
  END IF;

  -- Obtener player_rig con datos del rig
  SELECT pr.*, r.max_upgrade_level, r.name as rig_name
  INTO v_player_rig
  FROM player_rigs pr
  JOIN rigs r ON pr.rig_id = r.id
  WHERE pr.id = p_player_rig_id AND pr.player_id = p_player_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Rig no encontrado');
  END IF;

  -- Verificar que el rig no esté activo
  IF v_player_rig.is_active THEN
    RETURN jsonb_build_object('success', false, 'error', 'Detén el rig antes de mejorarlo');
  END IF;

  -- Obtener nivel actual según tipo
  CASE p_upgrade_type
    WHEN 'hashrate' THEN v_current_level := v_player_rig.hashrate_level;
    WHEN 'efficiency' THEN v_current_level := v_player_rig.efficiency_level;
    WHEN 'thermal' THEN v_current_level := v_player_rig.thermal_level;
  END CASE;

  v_next_level := v_current_level + 1;

  -- Verificar que no exceda el nivel máximo del rig
  IF v_next_level > v_player_rig.max_upgrade_level THEN
    RETURN jsonb_build_object('success', false, 'error', 'Nivel máximo alcanzado para este rig');
  END IF;

  -- Obtener costo del upgrade
  SELECT * INTO v_upgrade_cost FROM upgrade_costs WHERE level = v_next_level;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Nivel de mejora no válido');
  END IF;

  -- Verificar que el jugador tiene suficiente crypto
  IF v_player.crypto_balance < v_upgrade_cost.crypto_cost THEN
    RETURN jsonb_build_object('success', false, 'error', 'Crypto insuficiente',
      'required', v_upgrade_cost.crypto_cost, 'current', v_player.crypto_balance);
  END IF;

  -- Descontar crypto
  UPDATE players
  SET crypto_balance = crypto_balance - v_upgrade_cost.crypto_cost
  WHERE id = p_player_id;

  -- Aplicar upgrade según tipo
  CASE p_upgrade_type
    WHEN 'hashrate' THEN
      UPDATE player_rigs SET hashrate_level = v_next_level WHERE id = p_player_rig_id;
    WHEN 'efficiency' THEN
      UPDATE player_rigs SET efficiency_level = v_next_level WHERE id = p_player_rig_id;
    WHEN 'thermal' THEN
      UPDATE player_rigs SET thermal_level = v_next_level WHERE id = p_player_rig_id;
  END CASE;

  -- Registrar para misiones (futuro)
  -- PERFORM track_mission_progress(p_player_id, 'upgrade_rig', 1);

  RETURN jsonb_build_object(
    'success', true,
    'upgrade_type', p_upgrade_type,
    'new_level', v_next_level,
    'crypto_spent', v_upgrade_cost.crypto_cost,
    'bonus', CASE p_upgrade_type
      WHEN 'hashrate' THEN v_upgrade_cost.hashrate_bonus
      WHEN 'efficiency' THEN v_upgrade_cost.efficiency_bonus
      WHEN 'thermal' THEN v_upgrade_cost.thermal_bonus
    END
  );
END;
$$;

-- =====================================================
-- FUNCIÓN: Obtener información de upgrades de un rig
-- =====================================================
CREATE OR REPLACE FUNCTION get_rig_upgrades(
  p_player_rig_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_rig RECORD;
  v_hashrate_next RECORD;
  v_efficiency_next RECORD;
  v_thermal_next RECORD;
BEGIN
  -- Obtener player_rig con datos del rig
  SELECT
    pr.hashrate_level,
    pr.efficiency_level,
    pr.thermal_level,
    r.max_upgrade_level,
    r.hashrate as base_hashrate,
    r.power_consumption as base_power
  INTO v_player_rig
  FROM player_rigs pr
  JOIN rigs r ON pr.rig_id = r.id
  WHERE pr.id = p_player_rig_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Rig no encontrado');
  END IF;

  -- Obtener costos del siguiente nivel para cada tipo
  SELECT * INTO v_hashrate_next FROM upgrade_costs WHERE level = v_player_rig.hashrate_level + 1;
  SELECT * INTO v_efficiency_next FROM upgrade_costs WHERE level = v_player_rig.efficiency_level + 1;
  SELECT * INTO v_thermal_next FROM upgrade_costs WHERE level = v_player_rig.thermal_level + 1;

  RETURN jsonb_build_object(
    'success', true,
    'max_level', v_player_rig.max_upgrade_level,
    'hashrate', jsonb_build_object(
      'current_level', v_player_rig.hashrate_level,
      'can_upgrade', v_player_rig.hashrate_level < v_player_rig.max_upgrade_level,
      'next_cost', COALESCE(v_hashrate_next.crypto_cost, 0),
      'next_bonus', COALESCE(v_hashrate_next.hashrate_bonus, 0),
      'current_bonus', COALESCE((SELECT hashrate_bonus FROM upgrade_costs WHERE level = v_player_rig.hashrate_level), 0)
    ),
    'efficiency', jsonb_build_object(
      'current_level', v_player_rig.efficiency_level,
      'can_upgrade', v_player_rig.efficiency_level < v_player_rig.max_upgrade_level,
      'next_cost', COALESCE(v_efficiency_next.crypto_cost, 0),
      'next_bonus', COALESCE(v_efficiency_next.efficiency_bonus, 0),
      'current_bonus', COALESCE((SELECT efficiency_bonus FROM upgrade_costs WHERE level = v_player_rig.efficiency_level), 0)
    ),
    'thermal', jsonb_build_object(
      'current_level', v_player_rig.thermal_level,
      'can_upgrade', v_player_rig.thermal_level < v_player_rig.max_upgrade_level,
      'next_cost', COALESCE(v_thermal_next.crypto_cost, 0),
      'next_bonus', COALESCE(v_thermal_next.thermal_bonus, 0),
      'current_bonus', COALESCE((SELECT thermal_bonus FROM upgrade_costs WHERE level = v_player_rig.thermal_level), 0)
    )
  );
END;
$$;

-- Grants
GRANT EXECUTE ON FUNCTION upgrade_rig TO authenticated;
GRANT EXECUTE ON FUNCTION get_rig_upgrades TO authenticated;
