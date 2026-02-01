-- =====================================================
-- BLOCK LORDS - Datos Iniciales
-- =====================================================
-- Este archivo es seguro de ejecutar múltiples veces
-- Usa ON CONFLICT para evitar duplicados

-- Insertar rigs base
-- Internet consume más que energía para incentivar mejoras
INSERT INTO rigs (id, name, description, hashrate, power_consumption, internet_consumption, repair_cost, tier, base_price)
VALUES
  ('basic_miner', 'Minero Básico', 'Un rig simple para empezar. Bajo consumo, bajo rendimiento.', 100, 2.5, 3.5, 80, 'basic', 0),
  ('home_miner', 'Minero Casero', 'Rig mejorado para minería doméstica.', 250, 5.0, 7.0, 500, 'basic', 600),
  ('gpu_rig', 'Rig GPU', 'Múltiples GPUs para mayor hashrate.', 500, 8.0, 12.0, 1200, 'standard', 1800),
  ('asic_s9', 'ASIC S9', 'Hardware especializado de minería.', 1000, 12.0, 18.0, 2500, 'standard', 5000),
  ('asic_s19', 'ASIC S19', 'ASIC de última generación.', 2500, 18.0, 28.0, 5000, 'advanced', 15000),
  ('mining_farm_small', 'Mini Granja', 'Pequeña granja de minería.', 5000, 28.0, 42.0, 12000, 'advanced', 45000),
  ('mining_farm_large', 'Gran Granja', 'Granja de minería industrial.', 10000, 40.0, 60.0, 25000, 'elite', 120000),
  ('quantum_miner', 'Minero Cuántico', 'Tecnología experimental de minería.', 25000, 55.0, 85.0, 50000, 'elite', 350000)
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
-- cooling_power debe ser >= power_consumption * 0.8 para mantener rig frío
-- Basic rigs: 2.5-5.0 power → necesitan 2-4 cooling
-- Standard rigs: 8.0-12.0 power → necesitan 6.4-9.6 cooling
-- Advanced rigs: 18.0-28.0 power → necesitan 14.4-22.4 cooling
-- Elite rigs: 40.0-55.0 power → necesitan 32-44 cooling
INSERT INTO cooling_items (id, name, description, cooling_power, base_price, tier)
VALUES
  ('fan_basic', 'Ventilador Básico', 'Ideal para Minero Básico. Insuficiente para rigs mayores.', 4, 120, 'basic'),
  ('fan_dual', 'Ventilador Dual', 'Ideal para Minero Casero. Apenas enfría GPU Rig.', 8, 280, 'basic'),
  ('heatsink', 'Disipador de Calor', 'Ideal para GPU Rig. Insuficiente para ASICs.', 12, 550, 'standard'),
  ('liquid_cooler', 'Refrigeración Líquida', 'Ideal para ASIC S9. Mantiene frío hasta ASIC S19.', 18, 1400, 'standard'),
  ('aio_cooler', 'AIO Premium', 'Ideal para ASIC S19. Necesario para granjas pequeñas.', 28, 2800, 'advanced'),
  ('custom_loop', 'Loop Personalizado', 'Ideal para Mini Granja. Enfría cualquier rig avanzado.', 40, 5500, 'advanced'),
  ('industrial_ac', 'A/C Industrial', 'Ideal para Gran Granja. Overkill para rigs menores.', 55, 14000, 'elite'),
  ('cryo_system', 'Sistema Criogénico', 'Ideal para Minero Cuántico. Refrigeración extrema.', 75, 28000, 'elite')
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  cooling_power = EXCLUDED.cooling_power,
  base_price = EXCLUDED.base_price,
  tier = EXCLUDED.tier;

-- Insertar tarjetas prepago de energía
INSERT INTO prepaid_cards (id, name, description, card_type, amount, base_price, tier, currency)
VALUES
  ('energy_10', 'Energía +10', 'Recarga básica de energía.', 'energy', 10, 150, 'basic', 'gamecoin'),
  ('energy_25', 'Energía +25', 'Recarga estándar de energía.', 'energy', 25, 350, 'basic', 'gamecoin'),
  ('energy_50', 'Energía +50', 'Recarga premium de energía.', 'energy', 50, 650, 'standard', 'gamecoin'),
  ('energy_full', 'Energía MAX', 'Recarga completa de energía al 100%.', 'energy', 100, 1200, 'standard', 'gamecoin'),
  ('energy_ultra', 'Energía ULTRA', 'Recarga de energía premium. Incluye +25 capacidad máxima.', 'energy', 150, 5, 'elite', 'crypto')
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  card_type = EXCLUDED.card_type,
  amount = EXCLUDED.amount,
  base_price = EXCLUDED.base_price,
  tier = EXCLUDED.tier,
  currency = EXCLUDED.currency;

-- Insertar tarjetas prepago de internet
INSERT INTO prepaid_cards (id, name, description, card_type, amount, base_price, tier, currency)
VALUES
  ('internet_10', 'Internet +10', 'Recarga básica de datos.', 'internet', 10, 120, 'basic', 'gamecoin'),
  ('internet_25', 'Internet +25', 'Recarga estándar de datos.', 'internet', 25, 280, 'basic', 'gamecoin'),
  ('internet_50', 'Internet +50', 'Recarga premium de datos.', 'internet', 50, 520, 'standard', 'gamecoin'),
  ('internet_full', 'Internet MAX', 'Recarga completa de internet al 100%.', 'internet', 100, 950, 'standard', 'gamecoin'),
  ('internet_ultra', 'Internet ULTRA', 'Recarga de internet premium. Incluye +25 capacidad máxima.', 'internet', 150, 5, 'elite', 'crypto')
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  card_type = EXCLUDED.card_type,
  amount = EXCLUDED.amount,
  base_price = EXCLUDED.base_price,
  tier = EXCLUDED.tier,
  currency = EXCLUDED.currency;

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

-- Insertar paquetes de compra de Crypto con RON
-- Precios en RON (Ronin blockchain)
-- NOTA: Mínimo 1 RON para comprar. Tasa base: 1 RON = 5000 crypto
-- Paquetes más grandes tienen GRANDES bonus para motivar compras mayores
-- Vender: 100,000 crypto = 1 RON (spread 20x para mantener economía)
INSERT INTO crypto_packages (id, name, description, crypto_amount, ron_price, bonus_percent, tier, is_featured)
VALUES
  ('crypto_starter', 'Pack Inicial', 'Perfecto para empezar. ¡Gran valor!', 5000, 1.0, 0, 'basic', false),
  ('crypto_basic', 'Pack Básico', 'Impulso instantáneo para tu minería.', 12500, 2.5, 20, 'basic', false),
  ('crypto_standard', 'Pack Estándar', '¡El favorito de los mineros! Mejor valor.', 25000, 5.0, 25, 'standard', true),
  ('crypto_plus', 'Pack Plus', 'Poder real. Bonus increíble.', 50000, 10.0, 35, 'standard', false),
  ('crypto_premium', 'Pack Premium', 'Para mineros serios. ¡50% extra!', 125000, 25.0, 50, 'premium', true),
  ('crypto_elite', 'Pack Élite', 'Domina el juego. Bonus masivo.', 250000, 50.0, 75, 'premium', false),
  ('crypto_whale', 'Pack Ballena', '¡MÁXIMO VALOR! +100% bonus.', 500000, 100.0, 100, 'elite', true)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  crypto_amount = EXCLUDED.crypto_amount,
  ron_price = EXCLUDED.ron_price,
  bonus_percent = EXCLUDED.bonus_percent,
  tier = EXCLUDED.tier,
  is_featured = EXCLUDED.is_featured;
