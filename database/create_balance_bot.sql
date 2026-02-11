-- Script para crear el jugador "bot" de balanceo
-- Este bot participa con un sistema escalonado según el número de mineros:
--   < 3 mineros: Bot al 45% del hashrate total (competencia fuerte)
--   >= 3 mineros: Bot al 10% del hashrate total (competencia de fondo)
-- El bot NUNCA recibe recompensas, solo participa para mantener competencia justa

-- Insertar jugador bot (solo si no existe)
INSERT INTO players (
  id,
  username,
  email,
  blc_balance,
  ron_balance,
  energy,
  internet,
  max_energy,
  max_internet,
  reputation_score,
  is_online,
  created_at
) VALUES (
  '00000000-0000-0000-0000-000000000001',  -- ID fijo del bot
  'BalanceBot',                             -- Username visible
  'bot@system.local',                       -- Email (no usado)
  0,                                        -- Sin balance BLC
  0,                                        -- Sin balance RON
  0,                                        -- Sin energía
  0,                                        -- Sin internet
  0,                                        -- Sin max energía
  0,                                        -- Sin max internet
  0,                                        -- Sin reputación
  false,                                    -- Nunca "online"
  NOW()
)
ON CONFLICT (id) DO NOTHING;  -- No sobrescribir si ya existe

-- Verificar que se creó correctamente
SELECT
  id,
  username,
  'Bot de balanceo creado exitosamente' as status
FROM players
WHERE id = '00000000-0000-0000-0000-000000000001';
