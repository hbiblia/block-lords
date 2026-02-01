# Process Withdrawals Edge Function

Función Edge de Supabase que procesa automáticamente los retiros de RON.

## Configuración

### 1. Variables de Entorno (Supabase Dashboard)

Ve a **Project Settings > Edge Functions** y agrega:

```
HOT_WALLET_PRIVATE_KEY=0x...  # Clave privada de la wallet que envía RON
```

### 2. Hot Wallet

1. Crea una wallet dedicada para pagos (NO uses tu wallet personal)
2. Transfiere RON a esta wallet para pagos
3. Guarda la clave privada de forma segura

### 3. Deploy de la función

```bash
supabase functions deploy process-withdrawals
```

### 4. Configurar Cron Job (pg_cron)

```sql
-- En el SQL Editor de Supabase
-- Reemplaza TU_PROYECTO y TU_SERVICE_ROLE_KEY con tus valores
-- (Project Settings > API > service_role secret)

SELECT cron.schedule(
  'process-withdrawals',
  '*/5 * * * *',
  $$
  SELECT net.http_post(
    url := 'https://TU_PROYECTO.supabase.co/functions/v1/process-withdrawals',
    headers := '{"Authorization": "Bearer TU_SERVICE_ROLE_KEY"}'::jsonb
  );
  $$
);
```

### 5. Llamar manualmente (desde admin)

```typescript
import { adminTriggerWithdrawalProcessing } from '@/utils/api';

const result = await adminTriggerWithdrawalProcessing();
console.log(result);
// { success: true, processed: 3, failed: 0, hotWalletBalance: 10.5, results: [...] }
```

## Flujo de Procesamiento

1. Obtiene todos los retiros con status `pending` o `processing`
2. Para cada retiro:
   - Verifica que el hot wallet tenga suficiente balance
   - Marca como `processing`
   - Envía la transacción RON
   - Espera confirmación
   - Marca como `completed` con tx_hash
   - Si falla: marca como `failed` y devuelve fondos al usuario

## Seguridad

- La clave privada NUNCA se expone al frontend
- Solo la Edge Function tiene acceso
- El hot wallet solo debe tener el RON necesario para pagos
- Los usuarios reciben notificación cuando el pago se completa

## Monitoreo

Revisa los logs en Supabase Dashboard > Edge Functions > Logs

```bash
supabase functions logs process-withdrawals
```
