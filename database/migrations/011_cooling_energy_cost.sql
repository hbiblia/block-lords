-- =====================================================
-- MIGRACIÓN: Agregar costo de energía a cooling items
-- =====================================================

-- Agregar columna energy_cost a cooling_items
ALTER TABLE cooling_items
ADD COLUMN IF NOT EXISTS energy_cost DECIMAL(5, 2) DEFAULT 0;

-- Actualizar los valores de energy_cost basados en el poder de enfriamiento
-- Fórmula: mayor cooling_power = mayor consumo de energía
UPDATE cooling_items SET energy_cost = CASE id
  WHEN 'fan_basic' THEN 1          -- 4 cooling, 1 energy
  WHEN 'fan_dual' THEN 2           -- 8 cooling, 2 energy
  WHEN 'heatsink' THEN 3           -- 12 cooling, 3 energy
  WHEN 'liquid_cooler' THEN 5      -- 18 cooling, 5 energy
  WHEN 'aio_cooler' THEN 8         -- 28 cooling, 8 energy
  WHEN 'custom_loop' THEN 12       -- 40 cooling, 12 energy
  WHEN 'industrial_ac' THEN 18     -- 55 cooling, 18 energy
  WHEN 'cryo_system' THEN 25       -- 75 cooling, 25 energy
  ELSE ROUND(cooling_power / 3, 1)  -- Fallback para nuevos items
END;

-- Hacer la columna NOT NULL después de popular los datos
ALTER TABLE cooling_items
ALTER COLUMN energy_cost SET NOT NULL;

-- Agregar constraint para valores positivos
ALTER TABLE cooling_items
ADD CONSTRAINT energy_cost_positive CHECK (energy_cost >= 0);

COMMENT ON COLUMN cooling_items.energy_cost IS 'Consumo adicional de energía por tick cuando está instalado';
