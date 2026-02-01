# Process Withdrawals Edge Function

Función Edge de Supabase que procesa automáticamente los retiros de RON.

## Configuración

### 1. Variables de Entorno (Supabase Dashboard)

Ve a **Project Settings > Edge Functions > Secrets** y agrega:

```
HOT_WALLET_PRIVATE_KEY=0x...  # Clave privada de la wallet que envía RON
```

**Nota:** `SUPABASE_SERVICE_ROLE_KEY` ya está disponible automáticamente en las Edge Functions.

### 2. Hot Wallet

1. Crea una wallet dedicada para pagos (NO uses tu wallet personal)
2. Transfiere RON a esta wallet para pagos
3. Guarda la clave privada de forma segura

### 3. Deploy de la función

```bash
supabase functions deploy process-withdrawals --no-verify-jwt
```

**IMPORTANTE:** El flag `--no-verify-jwt` es necesario porque la función es llamada por pg_cron (interno de Supabase) que no envía un JWT válido.

### 4. Configurar Cron Job (pg_cron)

```sql
-- En el SQL Editor de Supabase
-- Reemplaza TU_PROYECTO con tu ID de proyecto
-- Reemplaza TU_SERVICE_ROLE_KEY con tu service role key (Project Settings > API)

-- NOTA: La función procesa hasta 5 retiros por llamada (BATCH_SIZE).
-- Con cron cada minuto = ~7,200 retiros/dia.

SELECT cron.schedule(
  'process-withdrawals',
  '* * * * *',
  $$
  SELECT net.http_post(
    url := 'https://TU_PROYECTO.supabase.co/functions/v1/process-withdrawals',
    headers := '{"Authorization": "Bearer TU_SERVICE_ROLE_KEY"}'::jsonb,
    timeout_milliseconds := 30000
  );
  $$
);
```

**IMPORTANTE:** Usa el `service_role` key (NO el anon key). Lo encuentras en Project Settings > API.

### 5. Llamar manualmente (desde admin)

```typescript
import { adminTriggerWithdrawalProcessing } from '@/utils/api';

const result = await adminTriggerWithdrawalProcessing();
console.log(result);
// { success: true, processed: 3, failed: 0, hotWalletBalance: 10.5, results: [...] }
```

## Flujo de Procesamiento

1. Obtiene los retiros con status `pending` o `processing`
2. Procesa un batch de hasta 5 retiros (configurable via `BATCH_SIZE`):
   - Verifica que el hot wallet tenga suficiente balance
   - Marca como `processing`
   - Envía la transacción RON
   - Espera confirmación
   - Marca como `completed` con tx_hash
   - Si falla: marca como `failed` y devuelve fondos al usuario
3. El cron se ejecuta cada minuto (~7,200 retiros/dia con batch de 5)

## Seguridad

- La clave privada NUNCA se expone al frontend
- Solo la Edge Function tiene acceso
- El hot wallet solo debe tener el RON necesario para pagos
- Los usuarios reciben notificación cuando el pago se completa
- **Protección DDoS:** La función verifica el `service_role` key en el header Authorization
- Sin el key correcto, la función retorna 401 Unauthorized

## Monitoreo

Revisa los logs en Supabase Dashboard > Edge Functions > Logs

```bash
supabase functions logs process-withdrawals
```
