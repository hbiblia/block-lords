# 🤖 CÓMO EL BOT IMPLEMENTA EL HASHRATE

## 📊 FLUJO COMPLETO (Paso a Paso)

### **PASO 1: Calcular Hashrate de Jugadores Reales**

Cada tick (30 segundos), el sistema calcula el hashrate de **todos los jugadores reales**:

```sql
-- Se actualiza en network_stats.hashrate
UPDATE network_stats
SET hashrate = (
  SELECT COALESCE(SUM(
    r.hashrate *                          -- Hashrate base del rig
    GREATEST(0.3, pr.condition / 100.0) * -- Penalización por condición
    [reputación multiplier] *             -- Bonus por reputación
    [temperatura penalty] *               -- Penalización por temperatura
    [upgrade bonus] *                     -- Bonus por upgrades
    [warm-up multiplier]                  -- Multiplicador de calentamiento
  ), 0)
  FROM player_rigs pr
  JOIN rigs r ON r.id = pr.rig_id
  JOIN players p ON p.id = pr.player_id
  WHERE pr.is_active = true
    AND p.energy > 0
    AND p.internet > 0
    -- ❗ INCLUYE AL BOT en este cálculo
)
```

**Ejemplo:**
- Jugador A: 1000 hashrate
- Jugador B: 1500 hashrate
- Bot: 100 hashrate (del rig básico que tiene)
- **Total en network_stats = 2600**

---

### **PASO 2: Bot Calcula SU Hashrate como % del Total**

```sql
-- 🤖 Sección del bot en generate_shares_tick()

-- 1. Obtener hashrate TOTAL de la red
SELECT COALESCE(hashrate, 0) INTO v_total_hashrate
FROM network_stats WHERE id = 'current';
-- v_total_hashrate = 2600

-- 2. Determinar porcentaje del bot según mineros activos
IF v_active_miners < 3 THEN
  v_bot_percentage := 0.45;  -- 45% si hay 1-2 jugadores
ELSE
  v_bot_percentage := 0.10;  -- 10% si hay 3+ jugadores
END IF;

-- 3. ⚠️ PROBLEMA: El bot calcula su hashrate sobre el total
--    que YA incluye al bot mismo
v_bot_hashrate := v_total_hashrate * v_bot_percentage;
-- v_bot_hashrate = 2600 * 0.45 = 1170
```

---

### **PASO 3: Bot Genera Shares**

```sql
-- Usar MISMA fórmula que jugadores reales
v_bot_shares_probability := (v_bot_hashrate / v_difficulty) * v_tick_duration;
-- v_bot_shares_probability = (1170 / 15000) * 0.5 = 0.039

v_bot_shares := FLOOR(v_bot_shares_probability);
-- v_bot_shares = 0 (redondeado hacia abajo)
```

---

### **PASO 4: Registrar Shares del Bot**

```sql
INSERT INTO player_shares (mining_block_id, player_id, shares_count)
VALUES (v_mining_block_id, '00000000-0000-0000-0000-000000000001', v_bot_shares)
ON CONFLICT (mining_block_id, player_id)
DO UPDATE SET shares_count = player_shares.shares_count + v_bot_shares;
```

---

## 🔴 **PROBLEMA IDENTIFICADO: Efecto Amplificador**

### **Escenario Actual (INCORRECTO):**

```
Tick 1:
  Jugadores: 2000 hashrate
  Bot rig: 100 hashrate (ignorado en cálculo posterior)
  Total network_stats: 2100

  Bot calcula: 2100 * 45% = 945 hashrate
  Bot genera shares basado en 945

Resultado:
  - El bot usa 945 hashrate (mucho más que su rig de 100)
  - El 945 se basa en el 2100 que incluye al bot mismo
  - Esto crea un loop de amplificación
```

### **Escenario Correcto (DEBERÍA SER):**

```
Tick 1:
  Jugadores REALES: 2000 hashrate
  Total network_stats: 2000 (sin bot)

  Bot calcula: 2000 * 45% = 900 hashrate
  Bot genera shares basado en 900

  Nuevo total REAL: 2000 + 900 = 2900
  (actualizar network_stats a 2900)

Resultado:
  - El bot usa 900 hashrate (45% de jugadores)
  - No hay amplificación
  - El hashrate total es correcto
```

---

## 🎯 **CÓMO DEBERÍA FUNCIONAR**

### **Opción A: Hashrate Sintético (Actual, pero corregido)**

El bot NO usa su rig para calcular hashrate, sino un **hashrate sintético**:

```sql
-- ✅ CORRECTO
DECLARE
  v_players_hashrate NUMERIC;  -- Solo jugadores reales
  v_bot_hashrate NUMERIC;      -- Calculado como %
  v_total_hashrate NUMERIC;    -- Suma de ambos

BEGIN
  -- 1. Calcular hashrate de jugadores SIN bot
  SELECT COALESCE(SUM([fórmula compleja]), 0)
  INTO v_players_hashrate
  FROM player_rigs pr
  WHERE [...condiciones...]
    AND p.id != '00000000-0000-0000-0000-000000000001';  -- ✅ Excluir bot

  -- 2. Bot = % de jugadores
  v_bot_hashrate := v_players_hashrate * v_bot_percentage;

  -- 3. Total = jugadores + bot
  v_total_hashrate := v_players_hashrate + v_bot_hashrate;

  -- 4. Actualizar network_stats con total correcto
  UPDATE network_stats SET hashrate = v_total_hashrate;
END;
```

### **Opción B: Hashrate del Rig del Bot (Alternativa)**

Usar el hashrate REAL del rig del bot (100 base):

```sql
-- Calcular hashrate del bot igual que jugadores
SELECT r.hashrate * pr.condition / 100.0
INTO v_bot_hashrate
FROM player_rigs pr
JOIN rigs r ON r.id = pr.rig_id
WHERE pr.player_id = '00000000-0000-0000-0000-000000000001';

-- v_bot_hashrate = 100 (fijo)
```

**Ventaja:** Simple, predecible
**Desventaja:** No escala con el número de jugadores

---

## 📈 **COMPARACIÓN DE HASHRATE**

### Escenario: 2 jugadores con 1000 hashrate c/u

| Sistema | Jugadores | Bot | Total Red | Bot % Real |
|---------|-----------|-----|-----------|------------|
| **Actual (MALO)** | 2000 | 2000*0.45=900 | 2900* | 31%* |
| **Corregido** | 2000 | 2000*0.45=900 | 2900 | 31% |
| **Rig Fijo** | 2000 | 100 | 2100 | 4.7% |

\* El actual es INCORRECTO porque calcula sobre un total que ya incluye al bot

---

## 🛠️ **IMPLEMENTACIÓN ACTUAL DEL BOT**

### **Características:**

1. **Bot tiene un rig básico** (100 hashrate base)
   - El rig siempre tiene condition = 100
   - Temperatura = 40°C
   - Nunca consume recursos

2. **El rig del bot se IGNORA** en el cálculo de shares
   - El bot NO usa la fórmula de jugadores
   - El bot usa hashrate sintético = % del total

3. **Bot genera shares con fórmula estándar:**
   ```sql
   shares = (hashrate / difficulty) * tick_duration
   ```

4. **Bot NUNCA recibe recompensas:**
   - Excluido en `close_mining_block()`
   - Sus shares solo sirven para competencia

---

## 🎮 **PROPÓSITO DEL BOT**

### **Por qué existe:**

1. **Evitar minería solitaria dominante**
   - Si solo hay 1 jugador, ganaría TODOS los bloques
   - El bot crea competencia artificial

2. **Mantener consistencia de recompensas**
   - Con bot: jugador gana ~50-60% de bloques
   - Sin bot: jugador gana ~100% de bloques

3. **Escalar según actividad:**
   - Pocos jugadores: bot fuerte (45%)
   - Muchos jugadores: bot débil (10%)

---

## 🔍 **VERIFICAR HASHRATE DEL BOT**

```sql
-- Ver hashrate actual del bot
SELECT
  'Bot' as type,
  COALESCE(SUM(r.hashrate * pr.condition / 100.0), 0) as rig_hashrate,
  (SELECT hashrate FROM network_stats WHERE id = 'current') as network_hashrate,
  (SELECT hashrate FROM network_stats WHERE id = 'current') *
    CASE WHEN (SELECT COUNT(DISTINCT player_id) FROM player_rigs WHERE is_active = true) < 3
    THEN 0.45 ELSE 0.10 END as synthetic_hashrate
FROM player_rigs pr
JOIN rigs r ON r.id = pr.rig_id
WHERE pr.player_id = '00000000-0000-0000-0000-000000000001'
  AND pr.is_active = true;

-- Resultado:
-- rig_hashrate: 100 (del rig básico)
-- network_hashrate: 2600 (total de todos)
-- synthetic_hashrate: 1170 (45% del total) ← ESTE es el que usa
```

---

## ✅ **RESUMEN**

### **Cómo el bot implementa hashrate:**

1. ❌ **NO** usa el hashrate de su rig (100)
2. ✅ **SÍ** calcula hashrate sintético = % del total de la red
3. ⚠️ **PROBLEMA**: Calcula sobre un total que incluye al bot mismo
4. 🎯 **SOLUCIÓN**: Calcular sobre hashrate de jugadores REALES únicamente

### **Fórmula Actual:**
```
bot_hashrate = network_total * percentage
               ↑
               Incluye al bot → MALO
```

### **Fórmula Correcta:**
```
bot_hashrate = players_only_hashrate * percentage
               ↑
               Solo jugadores → BUENO
```
