-- =====================================================
-- SISTEMA DE SLOTS PARA RIGS
-- Los jugadores deben comprar slots adicionales para tener más rigs
-- =====================================================

-- Agregar columna rig_slots a players (default 1 slot gratis)
ALTER TABLE players ADD COLUMN IF NOT EXISTS rig_slots INTEGER DEFAULT 1 NOT NULL CHECK (rig_slots >= 1 AND rig_slots <= 20);

-- Eliminar tabla existente para recrear con datos actualizados
DROP TABLE IF EXISTS rig_slot_upgrades;

-- Tabla de upgrades de slots (catálogo de precios)
CREATE TABLE rig_slot_upgrades (
  slot_number INTEGER PRIMARY KEY CHECK (slot_number >= 2 AND slot_number <= 20),
  price DECIMAL(18, 8) NOT NULL CHECK (price > 0),
  currency TEXT NOT NULL DEFAULT 'gamecoin' CHECK (currency IN ('gamecoin', 'crypto')),
  name TEXT NOT NULL,
  description TEXT
);

-- Precios de slots (progresivo - todos en Crypto excepto #2)
INSERT INTO rig_slot_upgrades (slot_number, price, currency, name, description) VALUES
  (2, 500, 'gamecoin', 'Slot #2', 'slot2'),
  (3, 1000, 'crypto', 'Slot #3', 'slot3'),
  (4, 2500, 'crypto', 'Slot #4', 'slot4'),
  (5, 5000, 'crypto', 'Slot #5', 'slot5'),
  (6, 10000, 'crypto', 'Slot #6', 'expansion'),
  (7, 25000, 'crypto', 'Slot #7', 'expansion'),
  (8, 50000, 'crypto', 'Slot #8', 'medium'),
  (9, 100000, 'crypto', 'Slot #9', 'medium'),
  (10, 200000, 'crypto', 'Slot #10', 'large'),
  (11, 350000, 'crypto', 'Slot #11', 'smallFarm'),
  (12, 500000, 'crypto', 'Slot #12', 'smallFarm'),
  (13, 750000, 'crypto', 'Slot #13', 'mediumFarm'),
  (14, 1000000, 'crypto', 'Slot #14', 'mediumFarm'),
  (15, 1500000, 'crypto', 'Slot #15', 'largeFarm'),
  (16, 2000000, 'crypto', 'Slot #16', 'largeFarm'),
  (17, 3000000, 'crypto', 'Slot #17', 'megaFarm'),
  (18, 5000000, 'crypto', 'Slot #18', 'megaFarm'),
  (19, 7500000, 'crypto', 'Slot #19', 'industrial'),
  (20, 10000000, 'crypto', 'Slot #20', 'maxPower')
;

-- Índice para búsquedas rápidas
CREATE INDEX IF NOT EXISTS idx_players_rig_slots ON players(rig_slots);
