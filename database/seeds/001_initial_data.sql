-- =====================================================
-- BLOCK LORDS - Datos Iniciales
-- =====================================================
-- Este archivo es seguro de ejecutar múltiples veces
-- Usa ON CONFLICT para evitar duplicados

-- Insertar rigs base
INSERT INTO rigs (id, name, description, hashrate, power_consumption, internet_consumption, repair_cost, tier, base_price)
VALUES
  ('basic_miner', 'Minero Básico', 'Un rig simple para empezar. Bajo consumo, bajo rendimiento.', 100, 0.5, 0.2, 10, 'basic', 0),
  ('home_miner', 'Minero Casero', 'Rig mejorado para minería doméstica.', 250, 1.0, 0.4, 25, 'basic', 50),
  ('gpu_rig', 'Rig GPU', 'Múltiples GPUs para mayor hashrate.', 500, 2.0, 0.8, 50, 'standard', 150),
  ('asic_s9', 'ASIC S9', 'Hardware especializado de minería.', 1000, 3.5, 1.2, 100, 'standard', 400),
  ('asic_s19', 'ASIC S19', 'ASIC de última generación.', 2500, 5.0, 1.5, 200, 'advanced', 1000),
  ('mining_farm_small', 'Mini Granja', 'Pequeña granja de minería.', 5000, 8.0, 2.0, 400, 'advanced', 2500),
  ('mining_farm_large', 'Gran Granja', 'Granja de minería industrial.', 10000, 12.0, 3.0, 750, 'elite', 5000),
  ('quantum_miner', 'Minero Cuántico', 'Tecnología experimental de minería.', 25000, 15.0, 4.0, 1500, 'elite', 15000)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  hashrate = EXCLUDED.hashrate,
  power_consumption = EXCLUDED.power_consumption,
  internet_consumption = EXCLUDED.internet_consumption,
  repair_cost = EXCLUDED.repair_cost,
  tier = EXCLUDED.tier,
  base_price = EXCLUDED.base_price;

-- Insertar insignias
INSERT INTO badges (id, name, description, icon)
VALUES
  ('rising_star', 'Estrella Naciente', 'Alcanzaste rango Plata', '⭐'),
  ('trusted_miner', 'Minero Confiable', 'Alcanzaste rango Oro', '🏆'),
  ('elite_trader', 'Trader Élite', 'Alcanzaste rango Platino', '💎'),
  ('crypto_legend', 'Leyenda Crypto', 'Alcanzaste rango Diamante', '👑'),
  ('first_block', 'Primer Bloque', 'Minaste tu primer bloque', '⛏️'),
  ('block_master', 'Maestro de Bloques', 'Minaste 100 bloques', '🎯'),
  ('trade_master', 'Maestro del Comercio', 'Completaste 100 trades', '💰'),
  ('community_helper', 'Ayudante Comunitario', 'Ayudaste a 10 jugadores nuevos', '🤝'),
  ('event_champion', 'Campeón de Eventos', 'Ganaste un evento global', '🏅'),
  ('early_adopter', 'Pionero', 'Te uniste durante la beta', '🚀')
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  icon = EXCLUDED.icon;

-- Insertar items de refrigeración
INSERT INTO cooling_items (id, name, description, cooling_power, base_price, tier)
VALUES
  ('fan_basic', 'Ventilador Básico', 'Un ventilador simple para reducir la temperatura.', 5, 20, 'basic'),
  ('fan_dual', 'Ventilador Dual', 'Dos ventiladores para mejor circulación de aire.', 10, 50, 'basic'),
  ('heatsink', 'Disipador de Calor', 'Disipador de aluminio para transferir calor.', 15, 100, 'standard'),
  ('liquid_cooler', 'Refrigeración Líquida', 'Sistema de refrigeración líquida cerrado.', 25, 250, 'standard'),
  ('aio_cooler', 'AIO Premium', 'All-in-one de alta gama con radiador de 240mm.', 35, 500, 'advanced'),
  ('custom_loop', 'Loop Personalizado', 'Sistema de refrigeración líquida custom.', 50, 1000, 'advanced'),
  ('industrial_ac', 'A/C Industrial', 'Sistema de aire acondicionado industrial.', 70, 2500, 'elite'),
  ('cryo_system', 'Sistema Criogénico', 'Refrigeración criogénica de última generación.', 90, 5000, 'elite')
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  cooling_power = EXCLUDED.cooling_power,
  base_price = EXCLUDED.base_price,
  tier = EXCLUDED.tier;

-- Insertar tarjetas prepago de energía
INSERT INTO prepaid_cards (id, name, description, card_type, amount, base_price, tier)
VALUES
  ('energy_10', 'Energía +10', 'Recarga básica de energía.', 'energy', 10, 15, 'basic'),
  ('energy_25', 'Energía +25', 'Recarga estándar de energía.', 'energy', 25, 35, 'basic'),
  ('energy_50', 'Energía +50', 'Recarga premium de energía.', 'energy', 50, 65, 'standard'),
  ('energy_full', 'Energía MAX', 'Recarga completa de energía al 100%.', 'energy', 100, 120, 'standard')
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  card_type = EXCLUDED.card_type,
  amount = EXCLUDED.amount,
  base_price = EXCLUDED.base_price,
  tier = EXCLUDED.tier;

-- Insertar tarjetas prepago de internet
INSERT INTO prepaid_cards (id, name, description, card_type, amount, base_price, tier)
VALUES
  ('internet_10', 'Internet +10', 'Recarga básica de datos.', 'internet', 10, 12, 'basic'),
  ('internet_25', 'Internet +25', 'Recarga estándar de datos.', 'internet', 25, 28, 'basic'),
  ('internet_50', 'Internet +50', 'Recarga premium de datos.', 'internet', 50, 52, 'standard'),
  ('internet_full', 'Internet MAX', 'Recarga completa de internet al 100%.', 'internet', 100, 95, 'standard')
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  card_type = EXCLUDED.card_type,
  amount = EXCLUDED.amount,
  base_price = EXCLUDED.base_price,
  tier = EXCLUDED.tier;

-- Insertar estadísticas iniciales de la red
INSERT INTO network_stats (id, difficulty, hashrate)
VALUES ('current', 1000, 0)
ON CONFLICT (id) DO NOTHING;

-- Insertar bloque génesis (solo si no existe y hay jugadores)
-- Nota: El bloque génesis se crea automáticamente cuando el primer jugador mina
-- o puedes ejecutar esto después de que exista al menos un jugador en 'players'
INSERT INTO blocks (height, hash, previous_hash, miner_id, difficulty, network_hashrate)
SELECT
  0,
  '0000000000000000000000000000000000000000000000000000000000000000',
  '0000000000000000000000000000000000000000000000000000000000000000',
  (SELECT id FROM players LIMIT 1),
  1000,
  0
WHERE EXISTS (SELECT 1 FROM players LIMIT 1)
  AND NOT EXISTS (SELECT 1 FROM blocks WHERE height = 0);
