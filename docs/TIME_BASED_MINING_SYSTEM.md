# Sistema de Minería por Bloques de Tiempo Fijo

## Resumen Ejecutivo

Sistema de minería donde los bloques se cierran **siempre por tiempo** (30 minutos), no por alcanzar un objetivo. Los mineros generan "semillas" (shares) que representan su contribución, y la recompensa del bloque se reparte proporcionalmente entre todos los contribuyentes.

---

## 1. Conceptos Clave

### 1.1 Bloques de Tiempo Fijo
- **Duración:** 30 minutos (configurable)
- **Cierre:** SIEMPRE por tiempo, nunca por alcanzar objetivo de semillas
- **Recompensa:** Fija por bloque (ej. 100 ₿)
- **Objetivo de semillas:** Meta ideal (ej. 100 semillas/bloque) para ajustar dificultad

### 1.2 Semillas (Shares)
- **Propósito:** Medir contribución de trabajo de cada minero
- **Generación:** Probabilística basada en hashrate y dificultad
- **No acumulables:** Se resetean al cerrar cada bloque
- **No cierran bloques:** Solo miden el trabajo total realizado

### 1.3 Dificultad
- **Propósito:** Controlar la tasa de generación de semillas
- **Ajuste:** Dinámico para mantener ~objetivo de semillas por bloque
- **Independiente del tiempo:** Mantiene producción estable sin importar número de mineros

---

## 2. Flujo Completo del Sistema

### 2.1 Inicio de Bloque
```
Al iniciar bloque N:
├─ timestamp_inicio = NOW()
├─ semillas_totales = 0
├─ contribuciones = {} (map: player_id → semillas_aportadas)
├─ dificultad_actual = dificultad_del_sistema
└─ recompensa_total = calcular_recompensa_base(N)
```

### 2.2 Durante el Bloque (Cada Tick de Minería)
```
Cada 10 segundos:
├─ Para cada rig activo:
│  ├─ hashrate_efectivo = calcular_hashrate_efectivo(rig)
│  ├─ probabilidad_semilla = (hashrate_efectivo / dificultad_actual) * tick_duration
│  ├─ Si random() < probabilidad_semilla:
│  │  ├─ semillas_generadas = 1
│  │  ├─ contribuciones[player_id] += semillas_generadas
│  │  └─ semillas_totales += semillas_generadas
│  └─ consumir_recursos(player_id, rig)
│
├─ Si (semillas_totales > semillas_objetivo):
│  └─ marcar_para_reajuste_dificultad = true
│
├─ Si (tiempo_desde_ultimo_reajuste > 60 minutos):
│  └─ reajustar_dificultad_ahora()
│
└─ Si (NOW() - timestamp_inicio >= 30 minutos):
   └─ cerrar_bloque()
```

### 2.3 Cierre de Bloque
```
Al cerrar bloque N (después de 30 minutos):
├─ timestamp_cierre = NOW()
├─ duracion_real = timestamp_cierre - timestamp_inicio
│
├─ Para cada player_id en contribuciones:
│  ├─ porcentaje = contribuciones[player_id] / semillas_totales
│  ├─ recompensa = recompensa_total * porcentaje
│  ├─ crear_pending_reward(player_id, recompensa, N)
│  └─ actualizar_estadisticas(player_id)
│
├─ guardar_bloque_historico(N, semillas_totales, duracion_real)
│
├─ Si marcar_para_reajuste_dificultad:
│  └─ reajustar_dificultad(semillas_totales, semillas_objetivo)
│
└─ iniciar_bloque(N + 1)
```

---

## 3. Ajuste de Dificultad

### 3.1 Pseudocódigo de Reajuste

```javascript
function reajustar_dificultad(semillas_actuales, semillas_objetivo) {
  // Constantes de ajuste
  const MAX_CAMBIO = 0.25;          // ±25% máximo por ajuste
  const MIN_DIFICULTAD = 1000;
  const MAX_DIFICULTAD = 10000000;
  const SUAVIZADO = 0.7;             // Factor de suavizado (0-1)

  // Calcular ratio de desviación
  // Si semillas_actuales > objetivo → ratio > 1 → subir dificultad
  // Si semillas_actuales < objetivo → ratio < 1 → bajar dificultad
  let ratio = semillas_actuales / semillas_objetivo;

  // Aplicar suavizado para evitar cambios bruscos
  // Un SUAVIZADO de 0.7 significa que solo ajustamos 70% de la desviación
  ratio = 1 + (ratio - 1) * SUAVIZADO;

  // Limitar cambio máximo a ±25%
  ratio = Math.max(1 - MAX_CAMBIO, Math.min(1 + MAX_CAMBIO, ratio));

  // Calcular nueva dificultad
  let nueva_dificultad = dificultad_actual * ratio;

  // Aplicar límites absolutos
  nueva_dificultad = Math.max(MIN_DIFICULTAD,
                              Math.min(MAX_DIFICULTAD, nueva_dificultad));

  // Redondear para evitar decimales innecesarios
  nueva_dificultad = Math.round(nueva_dificultad);

  // Guardar histórico para análisis
  registrar_ajuste_dificultad({
    bloque: numero_bloque_actual,
    dificultad_anterior: dificultad_actual,
    dificultad_nueva: nueva_dificultad,
    semillas_actuales: semillas_actuales,
    semillas_objetivo: semillas_objetivo,
    ratio_ajuste: ratio,
    timestamp: NOW()
  });

  // Actualizar dificultad del sistema
  dificultad_actual = nueva_dificultad;
  timestamp_ultimo_reajuste = NOW();

  return nueva_dificultad;
}
```

### 3.2 Reajuste por Tiempo Máximo

```javascript
function verificar_reajuste_por_tiempo() {
  const TIEMPO_MAX_SIN_REAJUSTE = 60 * 60; // 60 minutos en segundos

  let tiempo_transcurrido = NOW() - timestamp_ultimo_reajuste;

  if (tiempo_transcurrido >= TIEMPO_MAX_SIN_REAJUSTE) {
    // Reajustar basándose en semillas actuales del bloque en curso
    // Esto previene que la dificultad quede estancada si hay poca actividad
    reajustar_dificultad(semillas_totales_bloque_actual, semillas_objetivo);
  }
}
```

---

## 4. Generación de Semillas

### 4.1 Fórmula de Probabilidad

```javascript
function generar_semillas(rig, dificultad, tick_duration_seconds) {
  // Calcular hashrate efectivo del rig (con penalizaciones)
  let hashrate_efectivo = calcular_hashrate_efectivo(rig);

  // Probabilidad por segundo de generar 1 semilla
  // Normalizada para que con el hashrate objetivo se generen
  // las semillas objetivo en el tiempo del bloque
  let prob_por_segundo = hashrate_efectivo / dificultad;

  // Probabilidad en este tick (ej. 10 segundos)
  let prob_tick = prob_por_segundo * tick_duration_seconds;

  // Limitar probabilidad máxima a 1 (100%)
  prob_tick = Math.min(1.0, prob_tick);

  // Generar semillas de forma probabilística
  let semillas = 0;
  if (Math.random() < prob_tick) {
    semillas = 1;

    // OPCIONAL: Permitir múltiples semillas si la prob es muy alta
    // (solo si prob_tick > 1.0 antes de limitar)
    // let semillas_extra = Math.floor(prob_tick);
    // semillas += semillas_extra;
  }

  return semillas;
}
```

### 4.2 Cálculo de Hashrate Efectivo

```javascript
function calcular_hashrate_efectivo(rig) {
  let hashrate_base = rig.hashrate;

  // Penalización por condición
  let condition_penalty = rig.condition < 80
    ? 0.3 + (rig.condition / 80.0) * 0.7
    : 1.0;

  // Penalización por temperatura
  let temp_penalty = 1.0;
  if (rig.temperature > 60) {
    temp_penalty = Math.max(0.5, 1 - (rig.temperature - 60) * 0.0125);
  }

  // Multiplicadores de boosts
  let boost_multiplier = obtener_multiplicador_boosts(rig.id);

  // Multiplicador de reputación
  let rep_multiplier = calcular_multiplicador_reputacion(rig.player.reputation);

  return hashrate_base * condition_penalty * temp_penalty *
         boost_multiplier * rep_multiplier;
}
```

---

## 5. Reparto de Recompensas

### 5.1 Distribución Proporcional

```javascript
function repartir_recompensas_bloque(bloque) {
  const recompensa_total = calcular_recompensa_bloque(bloque.numero);
  const semillas_totales = bloque.semillas_totales;

  // Si no hubo contribuciones, no repartir nada
  if (semillas_totales === 0) {
    return;
  }

  // Crear mapa de recompensas por jugador
  let recompensas = {};

  for (let [player_id, semillas] of Object.entries(bloque.contribuciones)) {
    // Calcular porcentaje de contribución
    let porcentaje = semillas / semillas_totales;

    // Calcular recompensa (con bonus premium si aplica)
    let recompensa_base = recompensa_total * porcentaje;
    let es_premium = verificar_premium(player_id);
    let recompensa_final = es_premium ? recompensa_base * 1.5 : recompensa_base;

    recompensas[player_id] = {
      semillas: semillas,
      porcentaje: porcentaje * 100,
      recompensa: recompensa_final,
      es_premium: es_premium
    };
  }

  // Guardar recompensas pendientes
  for (let [player_id, data] of Object.entries(recompensas)) {
    crear_pending_reward({
      player_id: player_id,
      bloque_numero: bloque.numero,
      semillas_aportadas: data.semillas,
      porcentaje: data.porcentaje,
      recompensa: data.recompensa,
      es_premium: data.es_premium,
      created_at: NOW()
    });

    // Notificar al jugador
    notificar_recompensa_bloque(player_id, data);
  }

  return recompensas;
}
```

### 5.2 Cálculo de Recompensa Base

```javascript
function calcular_recompensa_bloque(numero_bloque) {
  const RECOMPENSA_INICIAL = 100;
  const HALVING_INTERVAL = 10000;  // Halving cada 10,000 bloques

  let halvings = Math.floor(numero_bloque / HALVING_INTERVAL);
  let recompensa = RECOMPENSA_INICIAL / Math.pow(2, halvings);

  return recompensa;
}
```

---

## 6. Valores Recomendados

### 6.1 Parámetros del Bloque
```javascript
const CONFIG_BLOQUE = {
  // Temporización
  duracion_bloque: 30 * 60,           // 30 minutos en segundos
  tick_mineria: 10,                    // Verificar minería cada 10 segundos

  // Semillas
  semillas_objetivo: 100,              // Target de semillas por bloque

  // Recompensas
  recompensa_inicial: 100,             // 100 ₿ por bloque
  halving_interval: 10000,             // Halving cada 10k bloques
  bonus_premium: 1.5,                  // +50% para premium

  // Dificultad
  dificultad_inicial: 50000,           // Ajustar según hashrate promedio
  dificultad_min: 1000,
  dificultad_max: 10000000,

  // Ajuste de dificultad
  max_cambio_dificultad: 0.25,        // ±25% máximo
  suavizado_ajuste: 0.7,               // 70% de la corrección
  tiempo_max_sin_reajuste: 60 * 60,   // 60 minutos
};
```

### 6.2 Balanceo Inicial

Para calcular la dificultad inicial óptima:

```
dificultad_inicial = (hashrate_promedio_red * duracion_bloque) / semillas_objetivo

Ejemplo:
- Hashrate promedio de red: 10,000 H/s
- Duración del bloque: 1,800 segundos (30 min)
- Semillas objetivo: 100

dificultad_inicial = (10,000 * 1,800) / 100 = 180,000
```

**Recomendación:** Empezar con una dificultad conservadora y dejar que el sistema se auto-ajuste en los primeros bloques.

---

## 7. Consideraciones Anti-Exploit

### 7.1 Prevención de Explotación de Semillas

**Problema:** Un jugador podría intentar activar/desactivar rigs rápidamente para generar más semillas.

**Solución:**
```javascript
// Cooldown de toggle rápido
const QUICK_TOGGLE_COOLDOWN = 5 * 60; // 5 minutos

function toggle_rig(rig_id, activar) {
  let rig = obtener_rig(rig_id);

  // Si se desactivó hace menos de 5 min, penalizar reactivación
  if (activar && rig.ultima_desactivacion) {
    let tiempo_desde_toggle = NOW() - rig.ultima_desactivacion;
    if (tiempo_desde_toggle < QUICK_TOGGLE_COOLDOWN) {
      // Aplicar penalización temporal de temperatura o condición
      rig.temperatura += 20; // Sobrecalentamiento por toggle rápido
    }
  }

  // Continuar con toggle normal...
}
```

### 7.2 Prevención de Farming con Múltiples Cuentas

**Problema:** Un usuario podría crear múltiples cuentas para acumular más semillas.

**Solución:**
```javascript
// Sistema de detección de Sybil
function verificar_patron_sospechoso(player_id) {
  // 1. Verificar IP duplicadas
  let cuentas_misma_ip = contar_cuentas_por_ip(get_ip(player_id));
  if (cuentas_misma_ip > 3) {
    marcar_para_revision(player_id, 'multiple_accounts_same_ip');
  }

  // 2. Verificar patrones de actividad idénticos
  let patron_actividad = obtener_patron_mineria(player_id);
  let cuentas_similares = buscar_patrones_identicos(patron_actividad);
  if (cuentas_similares.length > 2) {
    marcar_para_revision(player_id, 'identical_mining_patterns');
  }

  // 3. Verificar wallet de retiro
  // Si múltiples cuentas retiran a la misma wallet externa
  let wallet = obtener_wallet_retiro(player_id);
  if (wallet) {
    let cuentas_misma_wallet = contar_cuentas_por_wallet(wallet);
    if (cuentas_misma_wallet > 5) {
      marcar_para_revision(player_id, 'shared_withdrawal_wallet');
    }
  }
}
```

### 7.3 Límite de Semillas por Jugador

**Problema:** Un jugador con muchísimo hashrate podría dominar completamente un bloque.

**Solución (Opcional):**
```javascript
const MAX_PORCENTAJE_POR_JUGADOR = 0.5; // 50% máximo

function generar_semilla_con_limite(player_id, rig) {
  let semillas_actuales_jugador = bloque_actual.contribuciones[player_id] || 0;
  let semillas_totales = bloque_actual.semillas_totales;

  // Verificar si ya alcanzó el límite
  if (semillas_totales > 0) {
    let porcentaje_actual = semillas_actuales_jugador / semillas_totales;
    if (porcentaje_actual >= MAX_PORCENTAJE_POR_JUGADOR) {
      return 0; // No generar más semillas
    }
  }

  // Generar semillas normalmente
  return generar_semillas(rig, dificultad_actual, tick_duration);
}
```

⚠️ **Nota:** Este límite es opcional y puede afectar la percepción de justicia. Evaluar si es necesario.

### 7.4 Prevención de Time Manipulation

**Problema:** Un usuario no puede manipular el tiempo del servidor, pero podría intentar explotar desincronización.

**Solución:**
```javascript
// Usar timestamps del servidor SIEMPRE
function cerrar_bloque() {
  let timestamp_cierre = obtener_timestamp_servidor(); // No del cliente

  // Verificar que no haya saltos temporales sospechosos
  let duracion_esperada = CONFIG_BLOQUE.duracion_bloque;
  let duracion_real = timestamp_cierre - bloque_actual.timestamp_inicio;

  if (Math.abs(duracion_real - duracion_esperada) > 60) {
    // Si hay más de 1 minuto de diferencia, loguear
    log_anomalia({
      tipo: 'desviacion_tiempo_bloque',
      esperado: duracion_esperada,
      real: duracion_real,
      diferencia: duracion_real - duracion_esperada
    });
  }

  // Continuar con cierre normal...
}
```

### 7.5 Rate Limiting de Contribuciones

**Problema:** Un bot podría intentar enviar contribuciones falsas.

**Solución:**
```javascript
// Validación server-side de generación de semillas
function validar_semilla(player_id, rig_id, timestamp) {
  // 1. Verificar que el rig existe y está activo
  let rig = obtener_rig(rig_id);
  if (!rig || !rig.is_active || rig.player_id !== player_id) {
    return false;
  }

  // 2. Verificar recursos suficientes
  if (!tiene_recursos(player_id, rig)) {
    return false;
  }

  // 3. Verificar que no exceda tasa máxima teórica
  // (un rig no puede generar más de 1 semilla por tick)
  let ultima_semilla = obtener_ultima_semilla(rig_id);
  if (ultima_semilla && timestamp - ultima_semilla.timestamp < tick_duration) {
    marcar_sospechoso(player_id, 'tasa_semillas_excesiva');
    return false;
  }

  return true;
}
```

---

## 8. Estructura de Base de Datos

### 8.1 Tabla: mining_blocks

```sql
CREATE TABLE mining_blocks (
  id BIGSERIAL PRIMARY KEY,
  block_number INTEGER UNIQUE NOT NULL,

  -- Temporización
  started_at TIMESTAMPTZ NOT NULL,
  closed_at TIMESTAMPTZ,
  duration_seconds INTEGER,

  -- Semillas y dificultad
  total_seeds INTEGER DEFAULT 0,
  target_seeds INTEGER NOT NULL,
  difficulty NUMERIC NOT NULL,

  -- Recompensas
  total_reward NUMERIC NOT NULL,

  -- Estado
  status TEXT DEFAULT 'active', -- 'active', 'closed'

  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_mining_blocks_status ON mining_blocks(status);
CREATE INDEX idx_mining_blocks_number ON mining_blocks(block_number DESC);
```

### 8.2 Tabla: block_contributions

```sql
CREATE TABLE block_contributions (
  id BIGSERIAL PRIMARY KEY,
  block_id BIGINT REFERENCES mining_blocks(id) ON DELETE CASCADE,
  player_id UUID REFERENCES players(id) ON DELETE CASCADE,

  -- Contribución
  seeds_contributed INTEGER DEFAULT 0,
  percentage NUMERIC, -- Porcentaje del total (calculado al cerrar)

  -- Recompensa
  reward NUMERIC, -- Calculado al cerrar bloque
  is_premium BOOLEAN DEFAULT false,
  claimed BOOLEAN DEFAULT false,
  claimed_at TIMESTAMPTZ,

  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE(block_id, player_id)
);

CREATE INDEX idx_block_contributions_player ON block_contributions(player_id);
CREATE INDEX idx_block_contributions_block ON block_contributions(block_id);
CREATE INDEX idx_block_contributions_unclaimed ON block_contributions(player_id, claimed) WHERE claimed = false;
```

### 8.3 Tabla: difficulty_adjustments

```sql
CREATE TABLE difficulty_adjustments (
  id BIGSERIAL PRIMARY KEY,
  block_number INTEGER NOT NULL,

  -- Ajuste
  old_difficulty NUMERIC NOT NULL,
  new_difficulty NUMERIC NOT NULL,
  adjustment_ratio NUMERIC NOT NULL,

  -- Contexto
  seeds_actual INTEGER NOT NULL,
  seeds_target INTEGER NOT NULL,
  trigger_type TEXT NOT NULL, -- 'seeds_exceeded', 'time_limit'

  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_difficulty_adjustments_block ON difficulty_adjustments(block_number DESC);
```

### 8.4 Tabla: seed_events (Opcional - para análisis)

```sql
CREATE TABLE seed_events (
  id BIGSERIAL PRIMARY KEY,
  block_id BIGINT REFERENCES mining_blocks(id) ON DELETE CASCADE,
  player_id UUID REFERENCES players(id) ON DELETE CASCADE,
  rig_id UUID REFERENCES player_rigs(id) ON DELETE CASCADE,

  seeds_generated INTEGER DEFAULT 1,
  hashrate_effective NUMERIC,

  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Índice para análisis de patrones
CREATE INDEX idx_seed_events_player_time ON seed_events(player_id, created_at DESC);
```

---

## 9. Migración desde Sistema Actual

### 9.1 Estrategia de Transición

**Opción A: Corte Limpio (Hard Switch)**
- Establecer un bloque específico para el cambio
- Todos los pending_blocks actuales deben reclamarse antes
- El sistema nuevo inicia en bloque 0 con nueva lógica

**Opción B: Migración Gradual**
- Ejecutar ambos sistemas en paralelo por un período
- Permitir a los jugadores elegir cuál usar
- Deprecar gradualmente el sistema antiguo

### 9.2 Script de Migración (Opción A)

```sql
-- 1. Cerrar todos los bloques pendientes del sistema antiguo
UPDATE pending_blocks SET notification_sent = true;

-- 2. Crear bloque inicial del nuevo sistema
INSERT INTO mining_blocks (
  block_number,
  started_at,
  target_seeds,
  difficulty,
  total_reward,
  status
) VALUES (
  0,
  NOW(),
  100,
  50000, -- Ajustar según hashrate promedio
  100,
  'active'
);

-- 3. Inicializar dificultad en network_stats
UPDATE network_stats
SET difficulty = 50000,
    last_difficulty_adjustment = NOW()
WHERE id = 'current';

-- 4. Notificar a todos los jugadores del cambio
INSERT INTO notifications (player_id, type, title, message)
SELECT id, 'system', 'New Mining System',
       'The mining system has been upgraded to a time-based block system. Check the new Mining page!'
FROM players;
```

---

## 10. Testing y Balance

### 10.1 Casos de Prueba Clave

```javascript
// Test 1: Bloque con semillas exactas al objetivo
test_caso_1() {
  bloque.semillas_totales = 100;
  bloque.semillas_objetivo = 100;

  nueva_dif = reajustar_dificultad(100, 100);

  // Debería mantener dificultad similar (ratio ~1.0)
  assert(abs(nueva_dif - dificultad_actual) < dificultad_actual * 0.05);
}

// Test 2: Bloque con el doble de semillas
test_caso_2() {
  bloque.semillas_totales = 200;
  bloque.semillas_objetivo = 100;

  nueva_dif = reajustar_dificultad(200, 100);

  // Debería aumentar dificultad significativamente
  assert(nueva_dif > dificultad_actual * 1.2);
}

// Test 3: Bloque con muy pocas semillas
test_caso_3() {
  bloque.semillas_totales = 20;
  bloque.semillas_objetivo = 100;

  nueva_dif = reajustar_dificultad(20, 100);

  // Debería reducir dificultad
  assert(nueva_dif < dificultad_actual * 0.8);
}

// Test 4: Reparto proporcional de recompensas
test_caso_4() {
  bloque.contribuciones = {
    player_A: 50,  // 50%
    player_B: 30,  // 30%
    player_C: 20   // 20%
  };
  bloque.semillas_totales = 100;
  bloque.recompensa_total = 100;

  recompensas = repartir_recompensas_bloque(bloque);

  assert(recompensas.player_A.recompensa == 50);
  assert(recompensas.player_B.recompensa == 30);
  assert(recompensas.player_C.recompensa == 20);
}
```

### 10.2 Simulación de Balance

```python
# Simulador para encontrar parámetros óptimos
import random

def simular_bloques(num_bloques, hashrate_promedio, num_jugadores):
    dificultad = 50000
    semillas_objetivo = 100

    for bloque in range(num_bloques):
        semillas_totales = 0
        tick_duration = 10  # segundos
        bloque_duration = 30 * 60  # 30 min

        for tick in range(bloque_duration // tick_duration):
            for jugador in range(num_jugadores):
                hashrate = hashrate_promedio + random.uniform(-1000, 1000)
                prob = (hashrate * tick_duration) / dificultad

                if random.random() < prob:
                    semillas_totales += 1

        # Ajustar dificultad
        ratio = semillas_totales / semillas_objetivo
        ratio = 1 + (ratio - 1) * 0.7  # Suavizado
        ratio = max(0.75, min(1.25, ratio))  # Límite ±25%

        dificultad *= ratio

        print(f"Bloque {bloque}: {semillas_totales} semillas, dif={dificultad:.0f}")

# Ejecutar simulación
simular_bloques(100, hashrate_promedio=5000, num_jugadores=10)
```

---

## 11. Métricas y Monitoreo

### 11.1 Dashboards Administrativos

Métricas clave a monitorear:

```javascript
// Estadísticas por bloque
{
  numero_bloque: 123,
  duracion_real: 1802, // segundos
  semillas_generadas: 98,
  semillas_objetivo: 100,
  desviacion: -2,
  contribuyentes_unicos: 15,
  recompensa_total_repartida: 100,
  dificultad_aplicada: 52000
}

// Estadísticas agregadas (últimos 100 bloques)
{
  semillas_promedio: 102.5,
  desviacion_estandar: 8.3,
  contribuyentes_promedio: 18,
  bloques_sobre_objetivo: 55,
  bloques_bajo_objetivo: 45,
  ajustes_dificultad: 12
}

// Alertas
{
  bloques_consecutivos_desviacion_alta: 5,
  jugadores_sospechosos: ['player_123'],
  anomalias_tiempo: 0
}
```

### 11.2 Endpoints de API para Monitoreo

```
GET /api/admin/mining/stats
  → Estadísticas generales del sistema

GET /api/admin/mining/current-block
  → Estado del bloque actual en tiempo real

GET /api/admin/mining/difficulty-history?limit=100
  → Histórico de ajustes de dificultad

GET /api/admin/mining/player-contributions?player_id=xxx
  → Contribuciones de un jugador específico

GET /api/admin/mining/suspicious-patterns
  → Jugadores con patrones sospechosos
```

---

## 12. Conclusión y Próximos Pasos

### Ventajas del Sistema
✅ Producción predecible y estable
✅ Resistente a inflación por aumento de jugadores
✅ Reparto justo basado en contribución real
✅ Auto-balanceo mediante ajuste de dificultad
✅ No requiere claim manual (se puede auto-acreditar)

### Desventajas a Considerar
⚠️ Menos "emocionante" que ganar un bloque completo
⚠️ Requiere más jugadores activos para ser viable
⚠️ Complejidad adicional en backend

### Implementación Recomendada

**Fase 1:** Diseño de DB y funciones backend (1 semana)
**Fase 2:** Lógica de generación de semillas y cierre de bloques (1 semana)
**Fase 3:** Sistema de ajuste de dificultad (3 días)
**Fase 4:** Frontend y UI para nuevo sistema (1 semana)
**Fase 5:** Testing y balance (1 semana)
**Fase 6:** Migración y deploy (2 días)

---

**Última actualización:** 2026-02-10
**Versión del documento:** 1.0
**Autor:** Diseño de Sistema - Block Lords Mining v2
