# 🤖 Cambios: Bot con Hashrate Real (S9 - 1000 TH/s)

## 📋 Resumen

Se ha modificado el sistema del bot de balanceo para usar **hashrate real del rig** en lugar de hashrate sintético basado en porcentajes de la red.

### Cambio Principal

| Aspecto | Antes (Sintético) | Ahora (Real) |
|---------|-------------------|--------------|
| **Sistema** | Bot calcula hashrate como % del total de red | Bot usa hashrate de su rig (S9) |
| **Hashrate** | Variable según red (45% o 10%) | Fijo: 1000 TH/s |
| **Procesamiento** | Bloque separado con lógica especial | Loop principal como jugador normal |
| **Complejidad** | Alta (múltiples cálculos, amplificación) | Baja (procesa como cualquier jugador) |

---

## 🔧 Archivos Modificados

### 1. `all_functions.sql`

**Función modificada:** `generate_shares_tick()`

**Líneas 7167-7220 ELIMINADAS:**
```sql
-- 🤖 BOT DE BALANCEO: Sistema escalonado según número de mineros
DECLARE
  v_active_miners INTEGER;
  v_total_hashrate NUMERIC;
  v_bot_hashrate NUMERIC;
  v_bot_shares_probability NUMERIC;
  v_bot_shares NUMERIC;
  v_bot_percentage NUMERIC;
  v_bot_player_id UUID := '00000000-0000-0000-0000-000000000001';
BEGIN
  [... lógica de hashrate sintético ...]
END;
```

**Reemplazado con:**
```sql
-- ✅ El bot ahora se procesa como cualquier jugador en el loop principal
-- Su rig S9 (1000 hashrate) se incluye automáticamente en el procesamiento
-- NO necesita lógica especial para generar shares
```

**Líneas 7228-7270 ACTUALIZADAS:**
- Agregados comentarios para clarificar que el bot está incluido en:
  - Cálculo de hashrate total de la red
  - Conteo de mineros activos

---

## 📦 Archivos de Deployment

### `deploy_bot_real_hashrate.sql`

Script de deployment completo que:

1. **Crea/actualiza el rig S9:**
   - ID: `'s9'`
   - Nombre: `'Antminer S9'`
   - Hashrate: `1000`
   - Tier: `'advanced'`
   - Precio: `50000` GameCoin

2. **Actualiza el bot:**
   - Elimina rig anterior (`basic_miner`)
   - Asigna rig S9
   - Condición: 100%
   - Temperatura: 40°C
   - Activo: `true`

3. **Verifica configuración:**
   - Confirma que el bot tiene S9 asignado
   - Verifica hashrate = 1000
   - Verifica que está activo
   - Muestra dashboard de estado

---

## 📊 Comparación de Sistemas

### Escenario: 2 jugadores con 1000 hashrate cada uno

#### ❌ Sistema Anterior (Sintético)

```
Jugadores: 2000
Bot rig:   100 (ignorado)
─────────────
Total DB:  2100  ← network_stats

Bot calcula: 2100 * 45% = 945  ← ⚠️ PROBLEMA: Amplificación

Shares generadas por tick:
  Jugador A: ~0.033 shares/tick
  Jugador B: ~0.033 shares/tick
  Bot:       ~0.032 shares/tick  ← Casi igual a cada jugador

Distribución de bloques:
  Jugador A: 33%
  Jugador B: 33%
  Bot:       32%  ← ⚠️ Bot gana casi 1/3 de bloques
```

**Problemas identificados:**
- Loop de amplificación: Bot calcula sobre total que lo incluye
- Hashrate variable e impredecible
- Lógica compleja propensa a bugs
- Difícil de balancear

#### ✅ Sistema Nuevo (Real)

```
Jugadores: 2000
Bot S9:    1000
─────────────
Total:     3000

Bot usa: 1000 (hashrate real del S9)  ← ✅ CORRECTO

Shares generadas por tick:
  Jugador A: ~0.033 shares/tick
  Jugador B: ~0.033 shares/tick
  Bot:       ~0.033 shares/tick

Distribución de bloques:
  Jugador A: 33%
  Jugador B: 33%
  Bot:       33%  ← ✅ Equilibrio perfecto 1:1:1
```

**Ventajas:**
- ✅ No hay amplificación
- ✅ Hashrate predecible y fijo
- ✅ Lógica simple: bot = jugador normal
- ✅ Fácil de ajustar (cambiar rig)

---

## 🎯 Cómo Funciona Ahora

### Cada 30 segundos (1 tick):

1. **Loop principal procesa TODOS los rigs activos** (incluye bot):
   ```sql
   FOR v_rig IN
     SELECT pr.id, pr.player_id, pr.condition, r.hashrate, ...
     FROM player_rigs pr
     WHERE pr.is_active = true
       AND p.energy > 0
       AND p.internet > 0
       -- ✅ YA NO excluye al bot
   LOOP
     -- Calcular hashrate efectivo
     v_effective_hashrate := v_rig.hashrate * penalties * bonuses;

     -- Generar shares
     v_shares_probability := (v_effective_hashrate / difficulty) * tick_duration;
     v_shares_generated := FLOOR(v_shares_probability + accumulator);

     -- Registrar shares
     INSERT INTO player_shares ...
   END LOOP;
   ```

2. **El bot se beneficia de:**
   - Hashrate base del S9: `1000`
   - Condición perfecta: `100%` (mantenida automáticamente)
   - Temperatura normal: `40°C`
   - Recursos infinitos: `energy=999999`, `internet=999999`

3. **El bot sufre penalizaciones como jugadores:**
   - Temperatura (si sube de 40°C)
   - Condición (mantenida en 100% por `process_resource_decay()`)
   - Reputación (tiene 100)
   - Warm-up (si se reactiva)

4. **El bot NO recibe recompensas:**
   - Excluido en `close_mining_block()` (línea 7297)
   - Sus shares solo sirven para competencia

---

## ⚙️ Configuración del Bot

### Estado del Bot Después del Deployment:

```json
{
  "player_id": "00000000-0000-0000-0000-000000000001",
  "username": "BalanceBot",
  "rig": {
    "id": "s9",
    "name": "Antminer S9",
    "hashrate": 1000,
    "condition": 100,
    "temperature": 40,
    "is_active": true
  },
  "resources": {
    "energy": 999999,
    "internet": 999999
  },
  "is_online": true,
  "reputation_score": 100
}
```

### Características Especiales del Bot:

1. **Condición siempre 100%** (`process_resource_decay()` línea 1641):
   ```sql
   SET condition = CASE
     WHEN v_player.id = '00000000-0000-0000-0000-000000000001' THEN 100
     ELSE GREATEST(0, condition - v_deterioration)
   END
   ```

2. **Recursos infinitos** (`process_resource_decay()` línea 1714):
   ```sql
   IF v_player.id = '00000000-0000-0000-0000-000000000001' THEN
     v_new_energy := 999999;
     v_new_internet := 999999;
   ```

3. **Sin cooldown** (`fix_bot_cooldown.sql`):
   ```sql
   IF p_player_id = '00000000-0000-0000-0000-000000000001' THEN
     RETURN false;
   END IF;
   ```

4. **No recibe recompensas** (`close_mining_block()` línea 7324):
   ```sql
   WHERE player_id != '00000000-0000-0000-0000-000000000001'
   ```

---

## 🔄 Ajustar Fuerza del Bot

### Opciones para cambiar la competencia:

#### Opción 1: Cambiar el rig del bot

```sql
-- Bot más fuerte: Usar rig de 2000 hashrate
UPDATE player_rigs
SET rig_id = 'rig_mas_potente'
WHERE player_id = '00000000-0000-0000-0000-000000000001';

-- Bot más débil: Usar rig de 500 hashrate
UPDATE player_rigs
SET rig_id = 'basic_miner'
WHERE player_id = '00000000-0000-0000-0000-000000000001';
```

#### Opción 2: Ajustar condición del bot

```sql
-- Reducir competencia: Bajar condición a 80%
-- (Esto requiere modificar process_resource_decay para no forzar 100%)
UPDATE player_rigs
SET condition = 80
WHERE player_id = '00000000-0000-0000-0000-000000000001';
```

#### Opción 3: Múltiples bots

```sql
-- Crear un segundo bot con rig diferente
INSERT INTO players (id, username, ...)
VALUES ('00000000-0000-0000-0000-000000000002', 'BalanceBot2', ...);

INSERT INTO player_rigs (player_id, rig_id, ...)
VALUES ('00000000-0000-0000-0000-000000000002', 'basic_miner', ...);
```

---

## 📈 Monitoreo del Bot

### Ver estado actual:

```sql
SELECT
  p.username,
  r.name as rig_name,
  r.hashrate,
  pr.is_active,
  pr.condition,
  pr.temperature,
  p.energy,
  p.internet
FROM players p
JOIN player_rigs pr ON pr.player_id = p.id
JOIN rigs r ON r.id = pr.rig_id
WHERE p.id = '00000000-0000-0000-0000-000000000001';
```

### Ver shares del bot en bloque actual:

```sql
SELECT
  ps.shares_count,
  ps.last_share_at,
  mb.total_shares,
  ROUND((ps.shares_count::NUMERIC / NULLIF(mb.total_shares, 0)) * 100, 2) as bot_percentage
FROM player_shares ps
JOIN mining_blocks mb ON mb.id = ps.mining_block_id
WHERE ps.player_id = '00000000-0000-0000-0000-000000000001'
  AND mb.status = 'active';
```

### Verificar que bot NO recibe recompensas:

```sql
-- Debe retornar 0 en todos los casos
SELECT COUNT(*) as pending_blocks
FROM pending_blocks
WHERE player_id = '00000000-0000-0000-0000-000000000001';

SELECT COUNT(*) as mining_transactions
FROM transactions
WHERE player_id = '00000000-0000-0000-0000-000000000001'
  AND type IN ('mining_reward', 'block_claim');
```

### Ver participación del bot (últimos 10 bloques):

```sql
SELECT
  mb.block_number,
  mb.total_shares,
  ps.shares_count as bot_shares,
  ROUND((ps.shares_count::NUMERIC / mb.total_shares) * 100, 2) as bot_percentage
FROM mining_blocks mb
JOIN player_shares ps ON ps.mining_block_id = mb.id
WHERE ps.player_id = '00000000-0000-0000-0000-000000000001'
  AND mb.status = 'distributed'
ORDER BY mb.block_number DESC
LIMIT 10;
```

---

## 🚀 Deployment

### Orden de ejecución:

1. **Aplicar cambios a `all_functions.sql`** ✅ YA HECHO
   - Eliminar bloque sintético del bot
   - Actualizar comentarios

2. **Ejecutar `deploy_bot_real_hashrate.sql`**
   ```sql
   psql -d block_lords -f database/deploy_bot_real_hashrate.sql
   ```

3. **Ejecutar otros fixes (opcional pero recomendado):**
   ```sql
   -- Asegurar que bot siempre tenga rig activo
   psql -d block_lords -f database/fix_balance_bot.sql

   -- Excluir bot de cooldown
   psql -d block_lords -f database/fix_bot_cooldown.sql

   -- Crear funciones de monitoreo
   psql -d block_lords -f database/monitor_balance_bot.sql
   ```

4. **Verificar deployment:**
   ```sql
   SELECT * FROM get_bot_status();  -- Si ejecutaste monitor_balance_bot.sql
   ```

---

## ✅ Ventajas del Nuevo Sistema

### 1. **Simplicidad**
- ❌ Antes: ~50 líneas de lógica especial para el bot
- ✅ Ahora: Bot procesado en loop principal (0 líneas extra)

### 2. **Predecibilidad**
- ❌ Antes: Hashrate variable (945 con 2 jugadores, 300 con 3+)
- ✅ Ahora: Hashrate fijo (1000 siempre)

### 3. **Sin Amplificación**
- ❌ Antes: Bot calculaba sobre total que lo incluía (loop)
- ✅ Ahora: Bot usa su hashrate real (sin loop)

### 4. **Realismo**
- ❌ Antes: Bot no sufría penalizaciones reales
- ✅ Ahora: Bot sufre temperatura, condición, etc. (como jugadores)

### 5. **Configurabilidad**
- ❌ Antes: Cambiar % requiere modificar código SQL
- ✅ Ahora: Cambiar rig del bot en la base de datos

### 6. **Mantenibilidad**
- ❌ Antes: Lógica compleja, difícil de debuggear
- ✅ Ahora: Bot = jugador normal, fácil de entender

---

## 🎮 Balanceo de Juego

### Con 1 jugador (1000 hashrate):
```
Jugador: 1000 (50%)
Bot:     1000 (50%)
Total:   2000

Distribución: 50/50 ← Jugador no domina solo
```

### Con 2 jugadores (1000 c/u):
```
Jugador A: 1000 (33%)
Jugador B: 1000 (33%)
Bot:       1000 (33%)
Total:     3000

Distribución: 33/33/33 ← Equilibrio perfecto
```

### Con 3 jugadores (1000 c/u):
```
Jugador A: 1000 (25%)
Jugador B: 1000 (25%)
Jugador C: 1000 (25%)
Bot:       1000 (25%)
Total:     4000

Distribución: 25/25/25/25 ← Bot mantiene competencia
```

### Con 5 jugadores (1000 c/u):
```
Jugadores: 5000 (83%)
Bot:       1000 (17%)
Total:     6000

Distribución: Bot tiene menor impacto con más jugadores
```

---

## 📝 Notas Finales

### ¿Qué NO cambió?

1. **Bot sigue sin recibir recompensas** ✅
2. **Bot mantiene recursos infinitos** ✅
3. **Bot mantiene condición al 100%** ✅
4. **Bot no tiene cooldown** ✅
5. **Fórmula de shares sigue igual** ✅

### ¿Qué cambió?

1. **Bot usa hashrate real (1000) en vez de sintético** ✅
2. **Bot se procesa en loop principal** ✅
3. **Eliminada lógica especial de % escalonado** ✅
4. **Simplificado código en 50+ líneas** ✅

### ¿Cuándo usar este sistema?

- ✅ Quieres balanceo simple y predecible
- ✅ Quieres evitar amplificación de hashrate
- ✅ Quieres bot que se comporte como jugador normal
- ✅ Quieres poder ajustar fuerza cambiando rig

### ¿Cuándo NO usar este sistema?

- ❌ Necesitas escalado dinámico basado en # de jugadores
- ❌ Prefieres % del total de red (aceptando amplificación)
- ❌ Quieres múltiples tiers de competencia automática

---

## 🐛 Troubleshooting

### Problema: Bot no genera shares

**Verificar:**
```sql
-- 1. Bot tiene rig activo
SELECT is_active FROM player_rigs
WHERE player_id = '00000000-0000-0000-0000-000000000001';

-- 2. Bot está online
SELECT is_online, energy, internet FROM players
WHERE id = '00000000-0000-0000-0000-000000000001';

-- 3. Bot no está en cooldown
SELECT is_player_in_mining_cooldown('00000000-0000-0000-0000-000000000001');
```

### Problema: Bot domina demasiado

**Solución: Reducir hashrate del bot**
```sql
-- Opción 1: Cambiar a rig más débil
UPDATE player_rigs
SET rig_id = 'basic_miner'  -- 100 hashrate
WHERE player_id = '00000000-0000-0000-0000-000000000001';

-- Opción 2: Crear rig custom para bot
INSERT INTO rigs (id, name, hashrate, ...)
VALUES ('bot_rig_500', 'Bot Miner 500', 500, ...);

UPDATE player_rigs
SET rig_id = 'bot_rig_500'
WHERE player_id = '00000000-0000-0000-0000-000000000001';
```

### Problema: Bot recibió recompensas

**Verificar exclusión en close_mining_block:**
```sql
-- Debe tener esta línea en close_mining_block()
WHERE player_id != '00000000-0000-0000-0000-000000000001'
```

---

**Fin del documento**
