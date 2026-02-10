# Guía de Deployment - Sistema de Minería por Shares

## 🚀 Deployment Paso a Paso

### Preparativos

1. **Hacer backup de la base de datos** (recomendado)
2. **Anunciar mantenimiento** a los usuarios (24h antes)
3. **Pedir a usuarios que reclamen todos los bloques pendientes**

---

## Paso 1: Ejecutar Migrations

1. Abre **Supabase Dashboard** → Tu proyecto
2. Ve a **SQL Editor**
3. Abre el archivo: `database/deploy_share_system.sql`
4. **Copia y pega TODO el contenido** en el SQL Editor
5. Click en **Run** ▶️

**Tiempo estimado:** 2-3 minutos

### ✅ Verificación:
Deberías ver al final:
```
paso                      | completado
--------------------------|------------
Tablas creadas           | true
Funciones creadas        | true
Bloque inicial creado    | true
```

---

## Paso 2: Configurar Cron Job

### 2.1 Desactivar Cron Antiguo

Ejecuta en SQL Editor:
```sql
SELECT cron.unschedule('game_tick_job');
```

### 2.2 Activar Nuevo Cron (30 segundos)

```sql
SELECT cron.schedule(
  'game_tick_share_system_job',
  '30 seconds',
  'SELECT game_tick_share_system()'
);
```

### 2.3 Verificar

```sql
SELECT * FROM cron.job;
```

Deberías ver `game_tick_share_system_job` en la lista.

---

## Paso 3: Testing Manual

### 3.1 Verificar Bloque Activo

```sql
SELECT * FROM mining_blocks WHERE status = 'active';
```

Deberías ver 1 bloque con:
- `status`: 'active'
- `target_close_at`: ~30 minutos en el futuro
- `total_shares`: 0 (inicialmente)

### 3.2 Ejecutar Tick Manual

```sql
SELECT game_tick_share_system();
```

Resultado esperado:
```json
{
  "success": true,
  "shares_generated": X,
  "players_processed": Y,
  "blocks_closed": 0,
  ...
}
```

### 3.3 Verificar Generación de Shares

```sql
-- Ver shares generadas
SELECT * FROM player_shares;

-- Ver bloque actual con shares
SELECT
  block_number,
  total_shares,
  target_shares,
  status,
  target_close_at,
  EXTRACT(EPOCH FROM (target_close_at - NOW())) / 60 as minutes_remaining
FROM mining_blocks
WHERE status = 'active';
```

---

## Paso 4: Monitoreo Inicial

### Durante las primeras 2 horas:

#### 4.1 Verificar Generación de Shares

```sql
-- Cada 5 minutos, ejecutar:
SELECT
  mb.block_number,
  mb.total_shares,
  mb.target_shares,
  COUNT(DISTINCT ps.player_id) as unique_contributors,
  ROUND(EXTRACT(EPOCH FROM (mb.target_close_at - NOW())) / 60, 1) as minutes_remaining
FROM mining_blocks mb
LEFT JOIN player_shares ps ON ps.mining_block_id = mb.id
WHERE mb.status = 'active'
GROUP BY mb.id;
```

**Esperado:**
- `total_shares` aumenta cada 30 segundos
- Debería llegar a ~100 shares en 30 minutos

#### 4.2 Verificar Cierre de Bloques

Después de 30 minutos:

```sql
SELECT
  block_number,
  total_shares,
  status,
  closed_at,
  (SELECT COUNT(*) FROM pending_blocks WHERE shares_contributed IS NOT NULL AND created_at > closed_at) as pending_created
FROM mining_blocks
WHERE status = 'distributed'
ORDER BY block_number DESC
LIMIT 3;
```

**Esperado:**
- Bloque cerrado automáticamente
- `pending_blocks` creados para cada contribuyente
- Nuevo bloque activo iniciado

#### 4.3 Verificar Ajuste de Dificultad

```sql
SELECT
  difficulty,
  target_shares_per_block,
  last_difficulty_adjustment,
  EXTRACT(EPOCH FROM (NOW() - last_difficulty_adjustment)) / 60 as minutes_since_adjustment
FROM network_stats
WHERE id = 'current';
```

---

## Paso 5: Deploy de Frontend

### 5.1 Commit y Push

Los cambios ya están en:
- `src/stores/mining.ts`
- `src/stores/pendingBlocks.ts`
- `src/pages/MiningPage.vue`

```bash
git add .
git commit -m "feat: implementar sistema de minería por bloques de tiempo fijo con shares"
git push
```

### 5.2 Verificar Deploy Automático

Si tienes CI/CD configurado, el deploy debería ser automático.

### 5.3 Verificar Frontend

1. Abre la aplicación en el navegador
2. Ve a la página de Mining
3. Deberías ver la nueva sección **"Bloque Actual"** con:
   - Tiempo restante (cuenta regresiva)
   - Progreso de shares (barra)
   - Tus shares y porcentaje
   - Recompensa estimada

---

## Paso 6: Monitoreo Post-Deployment

### Primeras 24 horas:

#### Verificar estabilidad del sistema

```sql
-- Dashboard de monitoreo
WITH recent_blocks AS (
  SELECT
    block_number,
    total_shares,
    target_shares,
    EXTRACT(EPOCH FROM (closed_at - started_at)) / 60 as duration_minutes,
    (SELECT COUNT(*) FROM player_shares WHERE mining_block_id = mb.id) as contributors
  FROM mining_blocks mb
  WHERE status = 'distributed'
  ORDER BY block_number DESC
  LIMIT 10
)
SELECT
  AVG(total_shares) as avg_shares,
  AVG(duration_minutes) as avg_duration_min,
  AVG(contributors) as avg_contributors,
  MAX(total_shares) as max_shares,
  MIN(total_shares) as min_shares
FROM recent_blocks;
```

**Esperado:**
- `avg_duration_min`: ~30 minutos
- `avg_shares`: cercano a 100
- `avg_contributors`: depende de jugadores activos

#### Verificar distribución de recompensas

```sql
-- Últimas distribuciones
SELECT
  pb.player_id,
  p.username,
  pb.shares_contributed,
  pb.share_percentage,
  pb.reward,
  pb.is_premium
FROM pending_blocks pb
JOIN players p ON p.id = pb.player_id
WHERE pb.created_at > NOW() - INTERVAL '1 hour'
  AND pb.shares_contributed IS NOT NULL
ORDER BY pb.shares_contributed DESC
LIMIT 20;
```

---

## Ajustes de Dificultad (si es necesario)

Si después de los primeros bloques notas que:

### Caso 1: Demasiadas shares (>>100 por bloque)

```sql
-- Aumentar dificultad manualmente
UPDATE network_stats
SET difficulty = difficulty * 1.5  -- Aumentar 50%
WHERE id = 'current';
```

### Caso 2: Muy pocas shares (<<100 por bloque)

```sql
-- Reducir dificultad manualmente
UPDATE network_stats
SET difficulty = difficulty * 0.7  -- Reducir 30%
WHERE id = 'current';
```

### Caso 3: Recalcular dificultad desde cero

```sql
DO $$
DECLARE
  v_avg_hashrate NUMERIC;
  v_new_difficulty NUMERIC;
BEGIN
  -- Obtener hashrate promedio de jugadores activos
  SELECT AVG(hashrate) INTO v_avg_hashrate FROM network_stats;

  -- Calcular: (hashrate * 30 min) / 100 shares
  v_new_difficulty := (v_avg_hashrate * 30) / 100;

  UPDATE network_stats
  SET difficulty = GREATEST(1000, v_new_difficulty)
  WHERE id = 'current';

  RAISE NOTICE 'Nueva dificultad: %', v_new_difficulty;
END $$;
```

---

## Rollback (en caso de problemas)

Si necesitas volver al sistema anterior:

```sql
-- 1. Detener nuevo cron
SELECT cron.unschedule('game_tick_share_system_job');

-- 2. Reactivar cron antiguo
SELECT cron.schedule(
  'game_tick_job',
  '* * * * *',
  'SELECT run_decay_cycle()'
);

-- 3. Las tablas antiguas siguen intactas
-- El sistema volverá a funcionar como antes
```

**Nota:** Los bloques minados con el nuevo sistema quedarán en `pending_blocks` y podrán reclamarse normalmente.

---

## Queries Útiles para Debugging

### Ver estado actual del sistema

```sql
SELECT
  'Current Block' as info,
  mb.block_number,
  mb.total_shares,
  mb.target_shares,
  ROUND(EXTRACT(EPOCH FROM (mb.target_close_at - NOW())) / 60, 1) as minutes_remaining,
  ns.difficulty
FROM mining_blocks mb
CROSS JOIN network_stats ns
WHERE mb.status = 'active' AND ns.id = 'current';
```

### Ver últimas shares generadas

```sql
SELECT
  sh.generated_at,
  p.username,
  sh.shares_generated,
  ROUND(sh.hashrate_at_generation) as hashrate,
  sh.difficulty
FROM share_history sh
JOIN players p ON p.id = sh.player_id
ORDER BY sh.generated_at DESC
LIMIT 20;
```

### Ver progreso de jugadores en bloque actual

```sql
SELECT
  p.username,
  ps.shares_count,
  ROUND((ps.shares_count::NUMERIC / mb.total_shares) * 100, 2) as percentage,
  ROUND((mb.reward * ps.shares_count / mb.total_shares), 4) as estimated_reward
FROM player_shares ps
JOIN players p ON p.id = ps.player_id
JOIN mining_blocks mb ON mb.id = ps.mining_block_id
WHERE mb.status = 'active'
ORDER BY ps.shares_count DESC;
```

---

## Checklist Final

Antes de considerar el deployment exitoso:

- [ ] Tablas creadas correctamente
- [ ] Funciones creadas sin errores
- [ ] Bloque inicial creado y activo
- [ ] Cron job nuevo configurado y ejecutándose cada 30s
- [ ] Shares se generan cada 30 segundos
- [ ] Bloques se cierran automáticamente a los 30 minutos
- [ ] Recompensas se distribuyen proporcionalmente
- [ ] Pending_blocks se crean correctamente
- [ ] Dificultad se ajusta automáticamente
- [ ] Frontend muestra bloque actual
- [ ] Countdown funciona correctamente
- [ ] No hay errores en logs de Supabase
- [ ] Jugadores reportan que el sistema funciona

---

## Soporte

Si encuentras problemas:

1. Revisa logs de Supabase: Dashboard → Logs
2. Verifica que todas las funciones existan: `\df` en SQL Editor
3. Verifica cron jobs: `SELECT * FROM cron.job`
4. Contacta con el equipo de desarrollo

---

**Última actualización:** 2026-02-10
**Versión:** 1.0 - Sistema de Shares con tick de 30 segundos
