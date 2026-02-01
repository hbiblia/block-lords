-- =====================================================
-- ACTUALIZAR buy_crypto_package PARA USAR ron_balance
-- =====================================================
-- Ahora los paquetes de crypto se compran con el balance
-- de RON del juego, no directamente con la wallet.
-- El usuario primero recarga RON via "Recargar" en Perfil.

CREATE OR REPLACE FUNCTION buy_crypto_package(
  p_player_id UUID,
  p_package_id TEXT,
  p_tx_hash TEXT DEFAULT NULL -- Mantenemos el parametro por compatibilidad pero ya no se usa
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player players%ROWTYPE;
  v_package crypto_packages%ROWTYPE;
  v_total_crypto NUMERIC;
  v_purchase_id UUID;
BEGIN
  -- Obtener jugador
  SELECT * INTO v_player FROM players WHERE id = p_player_id;

  IF v_player.id IS NULL THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Jugador no encontrado'
    );
  END IF;

  -- Obtener el paquete
  SELECT * INTO v_package
  FROM crypto_packages
  WHERE id = p_package_id AND is_active = true;

  IF v_package IS NULL THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Paquete no encontrado o no disponible'
    );
  END IF;

  -- Verificar balance de RON
  IF COALESCE(v_player.ron_balance, 0) < v_package.ron_price THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Balance de RON insuficiente',
      'required', v_package.ron_price,
      'current', COALESCE(v_player.ron_balance, 0)
    );
  END IF;

  -- Calcular crypto total (con bonus)
  v_total_crypto := v_package.crypto_amount * (1 + v_package.bonus_percent::NUMERIC / 100);

  -- Descontar RON del balance
  UPDATE players
  SET ron_balance = ron_balance - v_package.ron_price,
      crypto_balance = crypto_balance + v_total_crypto,
      updated_at = NOW()
  WHERE id = p_player_id;

  -- Registrar la compra
  INSERT INTO crypto_purchases (
    player_id,
    package_id,
    crypto_amount,
    ron_paid,
    tx_hash,
    status,
    completed_at
  ) VALUES (
    p_player_id,
    p_package_id,
    v_total_crypto,
    v_package.ron_price,
    NULL, -- Ya no usamos tx_hash
    'completed',
    NOW()
  )
  RETURNING id INTO v_purchase_id;

  -- Registrar transaccion de RON gastado
  INSERT INTO transactions (player_id, type, amount, currency, description)
  VALUES (
    p_player_id,
    'crypto_purchase',
    -v_package.ron_price,
    'ron',
    'Compra de ' || v_package.name
  );

  -- Registrar transaccion de crypto recibido
  INSERT INTO transactions (player_id, type, amount, currency, description)
  VALUES (
    p_player_id,
    'crypto_purchase',
    v_total_crypto,
    'crypto',
    'Compra de ' || v_package.name || ' (+' || v_package.bonus_percent || '% bonus)'
  );

  RETURN json_build_object(
    'success', true,
    'purchase_id', v_purchase_id,
    'crypto_received', v_total_crypto,
    'ron_paid', v_package.ron_price,
    'new_ron_balance', v_player.ron_balance - v_package.ron_price,
    'new_crypto_balance', v_player.crypto_balance + v_total_crypto
  );
END;
$$;
