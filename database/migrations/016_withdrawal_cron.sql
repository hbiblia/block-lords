-- =====================================================
-- CONFIGURACIÓN CRON PARA PROCESAR RETIROS AUTOMÁTICOS
-- =====================================================

-- NOTA: pg_cron y pg_net deben habilitarse desde el Dashboard de Supabase
-- Database > Extensions > Buscar "pg_cron" y "pg_net" > Enable

-- =====================================================
-- EJECUTAR MANUALMENTE DESPUÉS DE CONFIGURAR:
-- =====================================================
-- 1. Reemplaza TU_PROYECTO con tu ID de proyecto Supabase
-- 2. Reemplaza TU_SERVICE_ROLE_KEY con tu service role key
--    (Project Settings > API > service_role secret)
-- 3. Ejecuta el siguiente SQL en el SQL Editor:
--
-- SELECT cron.schedule(
--   'process-withdrawals',
--   '*/5 * * * *',
--   $$
--   SELECT net.http_post(
--     url := 'https://TU_PROYECTO.supabase.co/functions/v1/process-withdrawals',
--     headers := '{"Authorization": "Bearer TU_SERVICE_ROLE_KEY"}'::jsonb
--   );
--   $$
-- );
--
-- Para eliminar el cron job:
-- SELECT cron.unschedule('process-withdrawals');
--
-- Para ver jobs activos:
-- SELECT * FROM cron.job;
-- =====================================================

-- Tabla para logs de procesamiento automático
CREATE TABLE IF NOT EXISTS withdrawal_processing_logs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  processed_count INTEGER DEFAULT 0,
  failed_count INTEGER DEFAULT 0,
  hot_wallet_balance DECIMAL(18, 8),
  details JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Función para registrar resultado del procesamiento
CREATE OR REPLACE FUNCTION log_withdrawal_processing(
  p_processed INTEGER,
  p_failed INTEGER,
  p_balance DECIMAL,
  p_details JSONB DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO withdrawal_processing_logs (processed_count, failed_count, hot_wallet_balance, details)
  VALUES (p_processed, p_failed, p_balance, p_details);

  -- Mantener solo últimos 1000 logs
  DELETE FROM withdrawal_processing_logs
  WHERE id NOT IN (
    SELECT id FROM withdrawal_processing_logs
    ORDER BY created_at DESC
    LIMIT 1000
  );
END;
$$;

-- Función para obtener estado del sistema de retiros
CREATE OR REPLACE FUNCTION admin_get_withdrawal_system_status()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_stats JSON;
  v_last_processing TIMESTAMPTZ;
  v_last_log withdrawal_processing_logs%ROWTYPE;
  v_cron_active BOOLEAN := false;
BEGIN
  -- Obtener estadísticas
  SELECT admin_get_withdrawal_stats() INTO v_stats;

  -- Último procesamiento
  SELECT * INTO v_last_log
  FROM withdrawal_processing_logs
  ORDER BY created_at DESC
  LIMIT 1;

  -- Verificar si cron está activo
  BEGIN
    SELECT EXISTS (
      SELECT 1 FROM cron.job WHERE jobname = 'process-withdrawals'
    ) INTO v_cron_active;
  EXCEPTION WHEN OTHERS THEN
    v_cron_active := false;
  END;

  RETURN json_build_object(
    'stats', v_stats,
    'cron_active', v_cron_active,
    'last_processing', v_last_log.created_at,
    'last_processed', v_last_log.processed_count,
    'last_failed', v_last_log.failed_count,
    'last_hot_wallet_balance', v_last_log.hot_wallet_balance
  );
END;
$$;

-- Ver estado de cron jobs
-- SELECT * FROM cron.job;

-- Ver historial de ejecuciones
-- SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 20;
