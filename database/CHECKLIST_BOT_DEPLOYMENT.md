# ✅ Checklist: Deployment Bot con Hashrate Real

## 📋 Estado de Archivos

### ✅ COMPLETADO

| Archivo | Estado | Descripción |
|---------|--------|-------------|
| `all_functions.sql` | ✅ MODIFICADO | Eliminada lógica sintética del bot en `generate_shares_tick()` |
| `upgrade_bot_to_s9.sql` | ✅ CREADO | Script para asignar rig S9 al bot |
| `fix_bot_use_real_hashrate.sql` | ✅ CREADO | Versión completa de `generate_shares_tick()` nueva |
| `deploy_bot_real_hashrate.sql` | ✅ CREADO | Script de deployment completo con verificación |
| `CAMBIOS_BOT_HASHRATE_REAL.md` | ✅ CREADO | Documentación completa de cambios |
| `bot_hashrate_flow.txt` | ✅ CREADO | Diagrama del problema de amplificación |
| `BOT_HASHRATE_EXPLAINED.md` | ✅ CREADO | Explicación detallada del sistema anterior |
| `fix_balance_bot.sql` | ✅ CREADO | Asegurar que bot siempre tenga rig activo |
| `fix_bot_cooldown.sql` | ✅ CREADO | Excluir bot de cooldown |
| `monitor_balance_bot.sql` | ✅ CREADO | Funciones de monitoreo del bot |

---

## 🚀 Pasos de Deployment

### Paso 1: Backup (CRÍTICO)

```bash
# Hacer backup completo de la base de datos
pg_dump -d block_lords -F c -f backup_before_bot_changes_$(date +%Y%m%d_%H%M%S).dump

# Verificar que el backup se creó
ls -lh backup_before_bot_changes_*.dump
```

**⚠️ NO CONTINUAR SIN BACKUP**

---

### Paso 2: Aplicar Cambios a all_functions.sql

**Estado:** ✅ YA COMPLETADO

Los cambios ya están aplicados en `all_functions.sql`:
- Líneas 7167-7220: Eliminado bloque de bot sintético
- Líneas 7227-7270: Agregados comentarios sobre inclusión del bot

**Para aplicar a la base de datos:**

```bash
# Opción A: Aplicar todo el archivo
psql -d block_lords -f database/all_functions.sql

# Opción B: Aplicar solo la función modificada
psql -d block_lords -f database/fix_bot_use_real_hashrate.sql
```

---

### Paso 3: Ejecutar Deployment del Bot

```bash
# Ejecutar script de deployment principal
psql -d block_lords -f database/deploy_bot_real_hashrate.sql
```

**Debe mostrar:**
```
NOTICE:  ✅ Rig S9 creado/actualizado
NOTICE:  ✅ Rig anterior del bot eliminado
NOTICE:  ✅ Rig S9 asignado al bot
NOTICE:  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
NOTICE:  ✅ VERIFICACIÓN EXITOSA
NOTICE:  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
NOTICE:  Bot: BalanceBot
NOTICE:  Rig: Antminer S9
NOTICE:  Hashrate: 1000
...
COMMIT
```

**Si hay errores:** Restaurar backup y revisar logs

---

### Paso 4: Aplicar Fixes Adicionales (Recomendado)

#### 4.1 Asegurar que bot siempre tenga rig activo

```bash
psql -d block_lords -f database/fix_balance_bot.sql
```

**Qué hace:**
- Crea función `ensure_bot_rig_active()`
- Crea trigger para prevenir desactivación del rig del bot

#### 4.2 Excluir bot de cooldown

```bash
psql -d block_lords -f database/fix_bot_cooldown.sql
```

**Qué hace:**
- Modifica `is_player_in_mining_cooldown()` para excluir al bot

#### 4.3 Instalar funciones de monitoreo

```bash
psql -d block_lords -f database/monitor_balance_bot.sql
```

**Qué hace:**
- Crea `get_bot_status()`: Dashboard del bot
- Crea `verify_bot_no_rewards()`: Verificar que bot no recibe recompensas
- Crea `get_bot_participation_stats()`: Estadísticas de participación

---

### Paso 5: Verificación Post-Deployment

#### 5.1 Verificar estado del bot

```sql
-- Verificar rig del bot
SELECT
  p.username,
  r.name as rig_name,
  r.hashrate,
  pr.is_active,
  pr.condition,
  pr.temperature
FROM players p
JOIN player_rigs pr ON pr.player_id = p.id
JOIN rigs r ON r.id = pr.rig_id
WHERE p.id = '00000000-0000-0000-0000-000000000001';
```

**Resultado esperado:**
```
 username   |   rig_name    | hashrate | is_active | condition | temperature
------------+---------------+----------+-----------+-----------+-------------
 BalanceBot | Antminer S9   |     1000 | t         |       100 |          40
```

#### 5.2 Verificar que bot NO recibe recompensas

```sql
-- Debe retornar 0
SELECT COUNT(*) FROM pending_blocks
WHERE player_id = '00000000-0000-0000-0000-000000000001';

SELECT COUNT(*) FROM transactions
WHERE player_id = '00000000-0000-0000-0000-000000000001'
  AND type IN ('mining_reward', 'block_claim');
```

**Resultado esperado:** `0` en ambos casos

#### 5.3 Verificar generación de shares (después de 1-2 minutos)

```sql
-- Ver shares del bot en bloque actual
SELECT
  ps.shares_count,
  mb.total_shares,
  ROUND((ps.shares_count::NUMERIC / NULLIF(mb.total_shares, 0)) * 100, 2) as bot_percentage
FROM player_shares ps
JOIN mining_blocks mb ON mb.id = ps.mining_block_id
WHERE ps.player_id = '00000000-0000-0000-0000-000000000001'
  AND mb.status = 'active';
```

**Resultado esperado:**
- `shares_count > 0` (bot está generando shares)
- `bot_percentage` entre 20-50% dependiendo de jugadores activos

#### 5.4 Verificar hashrate de red

```sql
-- Ver hashrate total incluyendo bot
SELECT hashrate, active_miners, difficulty
FROM network_stats WHERE id = 'current';
```

**Resultado esperado:**
- `hashrate` debe incluir los 1000 del bot
- `active_miners` debe incluir al bot en el conteo

---

### Paso 6: Monitoreo Continuo (Primeros 30 minutos)

#### Cada 5 minutos, ejecutar:

```sql
-- Dashboard completo (si instalaste monitor_balance_bot.sql)
SELECT * FROM get_bot_status();

-- O manualmente:
SELECT
  (SELECT COUNT(*) FROM player_shares
   WHERE player_id = '00000000-0000-0000-0000-000000000001') as total_shares,
  (SELECT is_active FROM player_rigs
   WHERE player_id = '00000000-0000-0000-0000-000000000001') as bot_active,
  (SELECT hashrate FROM network_stats WHERE id = 'current') as network_hashrate;
```

#### Verificar logs del servidor:

```bash
# Ver logs de PostgreSQL para errores
tail -f /var/log/postgresql/postgresql-*.log | grep -i error

# O en Docker:
docker logs -f block-lords-db | grep -i error
```

---

## 🎯 Criterios de Éxito

### ✅ Deployment exitoso si:

1. **Bot tiene rig S9 asignado**
   ```sql
   SELECT rig_id FROM player_rigs
   WHERE player_id = '00000000-0000-0000-0000-000000000001';
   -- Resultado: 's9'
   ```

2. **Hashrate del S9 es 1000**
   ```sql
   SELECT hashrate FROM rigs WHERE id = 's9';
   -- Resultado: 1000
   ```

3. **Bot está activo**
   ```sql
   SELECT is_active FROM player_rigs
   WHERE player_id = '00000000-0000-0000-0000-000000000001';
   -- Resultado: true
   ```

4. **Bot genera shares**
   ```sql
   SELECT shares_count FROM player_shares
   WHERE player_id = '00000000-0000-0000-0000-000000000001'
     AND mining_block_id = (SELECT current_mining_block_id FROM network_stats WHERE id = 'current');
   -- Resultado: > 0 (después de 1-2 minutos)
   ```

5. **Bot NO recibe recompensas**
   ```sql
   SELECT COUNT(*) FROM pending_blocks
   WHERE player_id = '00000000-0000-0000-0000-000000000001';
   -- Resultado: 0
   ```

6. **Network hashrate incluye al bot**
   ```sql
   SELECT hashrate FROM network_stats WHERE id = 'current';
   -- Debe ser >= 1000 (o más si hay jugadores)
   ```

7. **No hay errores en logs**

---

## ❌ Rollback (Si algo falla)

### Opción 1: Restaurar desde backup

```bash
# Detener aplicación
systemctl stop block-lords-api  # O docker-compose down

# Restaurar backup
pg_restore -d block_lords -c backup_before_bot_changes_*.dump

# Reiniciar aplicación
systemctl start block-lords-api  # O docker-compose up -d
```

### Opción 2: Revertir solo el bot (sin tocar all_functions.sql)

```sql
-- Volver bot a rig básico
DELETE FROM player_rigs
WHERE player_id = '00000000-0000-0000-0000-000000000001';

INSERT INTO player_rigs (player_id, rig_id, condition, is_active, temperature, acquired_at, activated_at)
VALUES (
  '00000000-0000-0000-0000-000000000001',
  'basic_miner',
  100,
  true,
  40,
  NOW(),
  NOW()
);
```

**⚠️ NOTA:** Si reviertes el bot pero dejaste los cambios en `all_functions.sql`, el bot usará el hashrate del `basic_miner` (100) en lugar de sintético. Esto es seguro pero el bot será muy débil.

---

## 📊 Comparación Antes/Después

### Antes del Deployment:

```
Bot: basic_miner (100 hashrate ignorado)
Sistema: Sintético (45% o 10% del total)
Procesamiento: Bloque separado
Código: ~50 líneas extra para bot
```

**Con 2 jugadores de 1000 c/u:**
```
Total network: 2100 (incluye bot)
Bot calcula: 2100 * 45% = 945
Bot compite con: 945 hashrate
Problema: Amplificación
```

### Después del Deployment:

```
Bot: Antminer S9 (1000 hashrate)
Sistema: Real (usa hashrate del rig)
Procesamiento: Loop principal (como jugadores)
Código: Sin líneas extra (comentarios)
```

**Con 2 jugadores de 1000 c/u:**
```
Total network: 3000 (jugadores + bot)
Bot usa: 1000 (del S9)
Bot compite con: 1000 hashrate
Ventaja: Sin amplificación, predecible
```

---

## 🔧 Ajustes Post-Deployment

### Si bot domina demasiado:

```sql
-- Reducir a 500 hashrate
UPDATE rigs SET hashrate = 500 WHERE id = 's9';

-- O cambiar a rig más débil
UPDATE player_rigs
SET rig_id = 'basic_miner'
WHERE player_id = '00000000-0000-0000-0000-000000000001';
```

### Si bot es muy débil:

```sql
-- Aumentar a 1500 hashrate
UPDATE rigs SET hashrate = 1500 WHERE id = 's9';

-- O crear rig custom más fuerte
INSERT INTO rigs (id, name, hashrate, ...)
VALUES ('bot_rig_strong', 'Bot Strong', 2000, ...);

UPDATE player_rigs
SET rig_id = 'bot_rig_strong'
WHERE player_id = '00000000-0000-0000-0000-000000000001';
```

---

## 📞 Contacto y Soporte

### En caso de problemas:

1. **Revisar logs:**
   ```bash
   tail -f /var/log/postgresql/postgresql-*.log
   docker logs -f block-lords-db
   ```

2. **Verificar estado del bot:**
   ```sql
   SELECT * FROM get_bot_status();  -- Si instalaste monitor_balance_bot.sql
   ```

3. **Restaurar backup si es necesario**

4. **Consultar documentación:**
   - `CAMBIOS_BOT_HASHRATE_REAL.md`: Documentación completa
   - `BOT_HASHRATE_EXPLAINED.md`: Explicación del sistema anterior
   - `bot_hashrate_flow.txt`: Diagramas del problema

---

## 🎉 Deployment Completado

Una vez que todos los checks pasen, el bot estará funcionando con hashrate real del rig S9.

**Próximos pasos:**
1. Monitorear durante las primeras 24 horas
2. Ajustar hashrate del bot según balanceo deseado
3. Verificar distribución de bloques entre jugadores y bot

---

**Última actualización:** 2026-02-11
**Versión:** 1.0
**Estado:** ✅ Listo para deployment
