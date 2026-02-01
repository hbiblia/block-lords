-- =====================================================
-- SISTEMA DE RETIRO DE RON
-- Los usuarios pueden solicitar retiros de RON a su wallet
-- =====================================================

-- Actualizar constraint de monedas en transactions para incluir 'ron'
DO $$
BEGIN
  -- Eliminar constraint existente
  ALTER TABLE transactions DROP CONSTRAINT IF EXISTS transactions_currency_check;

  -- Crear nuevo constraint que incluye 'ron'
  ALTER TABLE transactions ADD CONSTRAINT transactions_currency_check
    CHECK (currency IN ('gamecoin', 'crypto', 'ron'));
EXCEPTION WHEN OTHERS THEN
  -- Ignorar si ya existe o hay error
  NULL;
END $$;

-- Tabla para solicitudes de retiro
CREATE TABLE IF NOT EXISTS ron_withdrawals (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  amount DECIMAL(18, 8) NOT NULL,           -- Monto bruto (balance original)
  fee DECIMAL(18, 8) NOT NULL DEFAULT 0,    -- Comision (25%)
  net_amount DECIMAL(18, 8) NOT NULL,       -- Monto neto a recibir
  wallet_address TEXT NOT NULL,
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'cancelled')),
  tx_hash TEXT,
  error_message TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  processed_at TIMESTAMPTZ
);

-- Agregar columnas si no existen (para migraciones existentes)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'ron_withdrawals' AND column_name = 'fee') THEN
    ALTER TABLE ron_withdrawals ADD COLUMN fee DECIMAL(18, 8) NOT NULL DEFAULT 0;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'ron_withdrawals' AND column_name = 'net_amount') THEN
    ALTER TABLE ron_withdrawals ADD COLUMN net_amount DECIMAL(18, 8);
    UPDATE ron_withdrawals SET net_amount = amount WHERE net_amount IS NULL;
    ALTER TABLE ron_withdrawals ALTER COLUMN net_amount SET NOT NULL;
  END IF;
END $$;

-- Indices
CREATE INDEX IF NOT EXISTS idx_withdrawals_player ON ron_withdrawals(player_id);
CREATE INDEX IF NOT EXISTS idx_withdrawals_status ON ron_withdrawals(status);
CREATE INDEX IF NOT EXISTS idx_withdrawals_created ON ron_withdrawals(created_at DESC);

-- Funcion para solicitar retiro
CREATE OR REPLACE FUNCTION request_ron_withdrawal(p_player_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player players%ROWTYPE;
  v_pending_count INTEGER;
  v_withdrawal_id UUID;
  v_min_withdrawal DECIMAL := 0.01; -- Minimo 0.01 RON para retirar
  v_fee_rate DECIMAL := 0.25;       -- 25% de comision
  v_fee DECIMAL;
  v_net_amount DECIMAL;
BEGIN
  -- Verificar jugador
  SELECT * INTO v_player FROM players WHERE id = p_player_id;

  IF v_player.id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Jugador no encontrado');
  END IF;

  -- Verificar que tenga wallet configurada
  IF v_player.ron_wallet IS NULL OR v_player.ron_wallet = '' THEN
    RETURN json_build_object('success', false, 'error', 'No tienes una wallet configurada');
  END IF;

  -- Verificar balance
  IF COALESCE(v_player.ron_balance, 0) < v_min_withdrawal THEN
    RETURN json_build_object('success', false, 'error', 'Balance insuficiente. Minimo: ' || v_min_withdrawal || ' RON');
  END IF;

  -- Calcular comision y monto neto
  v_fee := ROUND(v_player.ron_balance * v_fee_rate, 8);
  v_net_amount := v_player.ron_balance - v_fee;

  -- Verificar que no tenga retiros pendientes
  SELECT COUNT(*) INTO v_pending_count
  FROM ron_withdrawals
  WHERE player_id = p_player_id AND status IN ('pending', 'processing');

  IF v_pending_count > 0 THEN
    RETURN json_build_object('success', false, 'error', 'Ya tienes un retiro en proceso');
  END IF;

  -- Crear solicitud de retiro con comision
  INSERT INTO ron_withdrawals (player_id, amount, fee, net_amount, wallet_address, status)
  VALUES (p_player_id, v_player.ron_balance, v_fee, v_net_amount, v_player.ron_wallet, 'pending')
  RETURNING id INTO v_withdrawal_id;

  -- Descontar balance (reservar fondos)
  UPDATE players
  SET ron_balance = 0
  WHERE id = p_player_id;

  -- Registrar transaccion
  INSERT INTO transactions (player_id, type, amount, currency, description)
  VALUES (p_player_id, 'ron_withdrawal', -v_player.ron_balance, 'ron',
          'Retiro de ' || v_net_amount || ' RON (comision: ' || v_fee || ') a ' ||
          SUBSTRING(v_player.ron_wallet FROM 1 FOR 6) || '...' ||
          SUBSTRING(v_player.ron_wallet FROM LENGTH(v_player.ron_wallet) - 3));

  RETURN json_build_object(
    'success', true,
    'withdrawal_id', v_withdrawal_id,
    'amount', v_player.ron_balance,
    'fee', v_fee,
    'net_amount', v_net_amount,
    'wallet', v_player.ron_wallet
  );
END;
$$;

-- Funcion para obtener historial de retiros
CREATE OR REPLACE FUNCTION get_withdrawal_history(p_player_id UUID, p_limit INTEGER DEFAULT 10)
RETURNS TABLE(
  id UUID,
  amount DECIMAL,
  fee DECIMAL,
  net_amount DECIMAL,
  wallet_address TEXT,
  status TEXT,
  tx_hash TEXT,
  created_at TIMESTAMPTZ,
  processed_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT
    w.id,
    w.amount,
    w.fee,
    w.net_amount,
    w.wallet_address,
    w.status,
    w.tx_hash,
    w.created_at,
    w.processed_at
  FROM ron_withdrawals w
  WHERE w.player_id = p_player_id
  ORDER BY w.created_at DESC
  LIMIT p_limit;
END;
$$;

-- Funcion para cancelar retiro pendiente
CREATE OR REPLACE FUNCTION cancel_withdrawal(p_player_id UUID, p_withdrawal_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_withdrawal ron_withdrawals%ROWTYPE;
BEGIN
  -- Obtener retiro
  SELECT * INTO v_withdrawal
  FROM ron_withdrawals
  WHERE id = p_withdrawal_id AND player_id = p_player_id;

  IF v_withdrawal.id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Retiro no encontrado');
  END IF;

  -- Solo se pueden cancelar retiros pendientes
  IF v_withdrawal.status != 'pending' THEN
    RETURN json_build_object('success', false, 'error', 'Solo se pueden cancelar retiros pendientes');
  END IF;

  -- Cancelar retiro
  UPDATE ron_withdrawals
  SET status = 'cancelled'
  WHERE id = p_withdrawal_id;

  -- Devolver fondos
  UPDATE players
  SET ron_balance = COALESCE(ron_balance, 0) + v_withdrawal.amount
  WHERE id = p_player_id;

  -- Registrar transaccion de devolucion
  INSERT INTO transactions (player_id, type, amount, currency, description)
  VALUES (p_player_id, 'withdrawal_cancelled', v_withdrawal.amount, 'ron',
          'Retiro cancelado - fondos devueltos');

  RETURN json_build_object('success', true, 'refunded', v_withdrawal.amount);
END;
$$;

-- =====================================================
-- FUNCIONES ADMIN PARA PROCESAR PAGOS
-- =====================================================

-- Obtener todos los retiros pendientes (para admin)
CREATE OR REPLACE FUNCTION admin_get_pending_withdrawals()
RETURNS TABLE(
  id UUID,
  player_id UUID,
  username TEXT,
  email TEXT,
  amount DECIMAL,
  fee DECIMAL,
  net_amount DECIMAL,
  wallet_address TEXT,
  status TEXT,
  created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT
    w.id,
    w.player_id,
    p.username,
    p.email,
    w.amount,
    w.fee,
    w.net_amount,
    w.wallet_address,
    w.status,
    w.created_at
  FROM ron_withdrawals w
  JOIN players p ON p.id = w.player_id
  WHERE w.status IN ('pending', 'processing')
  ORDER BY w.created_at ASC;
END;
$$;

-- Marcar retiro como "en proceso" (admin empieza a procesar)
CREATE OR REPLACE FUNCTION admin_start_processing(p_withdrawal_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_withdrawal ron_withdrawals%ROWTYPE;
BEGIN
  SELECT * INTO v_withdrawal FROM ron_withdrawals WHERE id = p_withdrawal_id;

  IF v_withdrawal.id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Retiro no encontrado');
  END IF;

  IF v_withdrawal.status != 'pending' THEN
    RETURN json_build_object('success', false, 'error', 'El retiro no está pendiente');
  END IF;

  UPDATE ron_withdrawals
  SET status = 'processing'
  WHERE id = p_withdrawal_id;

  RETURN json_build_object(
    'success', true,
    'wallet', v_withdrawal.wallet_address,
    'net_amount', v_withdrawal.net_amount
  );
END;
$$;

-- Marcar retiro como completado (despues de enviar RON)
CREATE OR REPLACE FUNCTION admin_complete_withdrawal(p_withdrawal_id UUID, p_tx_hash TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_withdrawal ron_withdrawals%ROWTYPE;
BEGIN
  SELECT * INTO v_withdrawal FROM ron_withdrawals WHERE id = p_withdrawal_id;

  IF v_withdrawal.id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Retiro no encontrado');
  END IF;

  IF v_withdrawal.status != 'pending' AND v_withdrawal.status != 'processing' THEN
    RETURN json_build_object('success', false, 'error', 'El retiro ya fue procesado');
  END IF;

  UPDATE ron_withdrawals
  SET status = 'completed',
      tx_hash = p_tx_hash,
      processed_at = NOW()
  WHERE id = p_withdrawal_id;

  RETURN json_build_object('success', true);
END;
$$;

-- Marcar retiro como fallido
CREATE OR REPLACE FUNCTION admin_fail_withdrawal(p_withdrawal_id UUID, p_error_message TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_withdrawal ron_withdrawals%ROWTYPE;
BEGIN
  SELECT * INTO v_withdrawal FROM ron_withdrawals WHERE id = p_withdrawal_id;

  IF v_withdrawal.id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Retiro no encontrado');
  END IF;

  IF v_withdrawal.status NOT IN ('pending', 'processing') THEN
    RETURN json_build_object('success', false, 'error', 'El retiro ya fue procesado');
  END IF;

  -- Marcar como fallido
  UPDATE ron_withdrawals
  SET status = 'failed',
      error_message = p_error_message,
      processed_at = NOW()
  WHERE id = p_withdrawal_id;

  -- Devolver el monto BRUTO al usuario (antes de comision)
  UPDATE players
  SET ron_balance = COALESCE(ron_balance, 0) + v_withdrawal.amount
  WHERE id = v_withdrawal.player_id;

  -- Registrar devolucion
  INSERT INTO transactions (player_id, type, amount, currency, description)
  VALUES (v_withdrawal.player_id, 'withdrawal_failed', v_withdrawal.amount, 'ron',
          'Retiro fallido - fondos devueltos: ' || p_error_message);

  RETURN json_build_object('success', true, 'refunded', v_withdrawal.amount);
END;
$$;

-- Obtener resumen de retiros (estadisticas para admin)
CREATE OR REPLACE FUNCTION admin_get_withdrawal_stats()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_pending_count INTEGER;
  v_pending_amount DECIMAL;
  v_processing_count INTEGER;
  v_processing_amount DECIMAL;
  v_completed_today INTEGER;
  v_completed_today_amount DECIMAL;
  v_total_fees_collected DECIMAL;
BEGIN
  -- Pendientes
  SELECT COUNT(*), COALESCE(SUM(net_amount), 0)
  INTO v_pending_count, v_pending_amount
  FROM ron_withdrawals WHERE status = 'pending';

  -- En proceso
  SELECT COUNT(*), COALESCE(SUM(net_amount), 0)
  INTO v_processing_count, v_processing_amount
  FROM ron_withdrawals WHERE status = 'processing';

  -- Completados hoy
  SELECT COUNT(*), COALESCE(SUM(net_amount), 0)
  INTO v_completed_today, v_completed_today_amount
  FROM ron_withdrawals
  WHERE status = 'completed' AND processed_at >= CURRENT_DATE;

  -- Total fees collected
  SELECT COALESCE(SUM(fee), 0)
  INTO v_total_fees_collected
  FROM ron_withdrawals WHERE status = 'completed';

  RETURN json_build_object(
    'pending_count', v_pending_count,
    'pending_amount', v_pending_amount,
    'processing_count', v_processing_count,
    'processing_amount', v_processing_amount,
    'completed_today', v_completed_today,
    'completed_today_amount', v_completed_today_amount,
    'total_fees_collected', v_total_fees_collected
  );
END;
$$;

-- Funcion legacy (mantener compatibilidad)
CREATE OR REPLACE FUNCTION process_withdrawal(p_withdrawal_id UUID, p_tx_hash TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN admin_complete_withdrawal(p_withdrawal_id, p_tx_hash);
END;
$$;

-- RLS: Ver database/policies/001_rls_policies.sql
