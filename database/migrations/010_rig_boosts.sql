-- =====================================================
-- BLOCK LORDS - Sistema de Boosts por Rig
-- =====================================================
-- Este archivo reemplaza el sistema de boosts globales
-- por un sistema de boosts específicos por rig

-- =====================================================
-- ELIMINAR SISTEMA ANTIGUO
-- =====================================================
DROP TABLE IF EXISTS active_boosts CASCADE;

-- =====================================================
-- NUEVA TABLA: BOOSTS INSTALADOS EN RIGS
-- =====================================================
CREATE TABLE IF NOT EXISTS rig_boosts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  player_rig_id UUID NOT NULL REFERENCES player_rigs(id) ON DELETE CASCADE,
  boost_item_id TEXT NOT NULL REFERENCES boost_items(id),
  activated_at TIMESTAMPTZ DEFAULT NOW(),
  remaining_seconds INTEGER NOT NULL CHECK (remaining_seconds >= 0),
  stack_count INTEGER DEFAULT 1 CHECK (stack_count >= 1),
  UNIQUE(player_rig_id, boost_item_id)
);

-- Índice para consultas por rig
CREATE INDEX IF NOT EXISTS idx_rig_boosts_rig ON rig_boosts(player_rig_id);

-- =====================================================
-- COMENTARIOS
-- =====================================================
COMMENT ON TABLE rig_boosts IS 'Boosts activos instalados en rigs específicos. El tiempo solo cuenta cuando el rig está minando.';
COMMENT ON COLUMN rig_boosts.remaining_seconds IS 'Segundos restantes del boost. Solo se decrementa cuando el rig está activo minando.';
COMMENT ON COLUMN rig_boosts.stack_count IS 'Cantidad de stacks del boost (si es stackable).';
