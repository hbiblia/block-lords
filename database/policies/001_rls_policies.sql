-- =====================================================
-- CRYPTO ARCADE MMO - Políticas RLS
-- Script idempotente (puede ejecutarse múltiples veces)
-- =====================================================

-- Habilitar RLS en todas las tablas
ALTER TABLE players ENABLE ROW LEVEL SECURITY;
ALTER TABLE player_rigs ENABLE ROW LEVEL SECURITY;
ALTER TABLE blocks ENABLE ROW LEVEL SECURITY;
ALTER TABLE market_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE trades ENABLE ROW LEVEL SECURITY;
ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE reputation_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE badges ENABLE ROW LEVEL SECURITY;
ALTER TABLE player_badges ENABLE ROW LEVEL SECURITY;
ALTER TABLE player_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE player_penalties ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE rigs ENABLE ROW LEVEL SECURITY;
ALTER TABLE network_stats ENABLE ROW LEVEL SECURITY;
ALTER TABLE player_inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE rig_cooling ENABLE ROW LEVEL SECURITY;
ALTER TABLE cooling_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE player_cooling ENABLE ROW LEVEL SECURITY;
ALTER TABLE prepaid_cards ENABLE ROW LEVEL SECURITY;
ALTER TABLE player_cards ENABLE ROW LEVEL SECURITY;
ALTER TABLE player_streaks ENABLE ROW LEVEL SECURITY;
ALTER TABLE streak_rewards ENABLE ROW LEVEL SECURITY;
ALTER TABLE streak_claims ENABLE ROW LEVEL SECURITY;
ALTER TABLE missions ENABLE ROW LEVEL SECURITY;
ALTER TABLE player_missions ENABLE ROW LEVEL SECURITY;
ALTER TABLE player_online_tracking ENABLE ROW LEVEL SECURITY;

-- =====================================================
-- POLÍTICAS PARA PLAYERS
-- =====================================================

DROP POLICY IF EXISTS "Perfiles públicos visibles" ON players;
CREATE POLICY "Perfiles públicos visibles"
  ON players FOR SELECT
  USING (true);

DROP POLICY IF EXISTS "Usuarios actualizan su propio perfil" ON players;
CREATE POLICY "Usuarios actualizan su propio perfil"
  ON players FOR UPDATE
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- =====================================================
-- POLÍTICAS PARA RIGS (catálogo)
-- =====================================================

DROP POLICY IF EXISTS "Catálogo de rigs público" ON rigs;
CREATE POLICY "Catálogo de rigs público"
  ON rigs FOR SELECT
  USING (true);

-- =====================================================
-- POLÍTICAS PARA PLAYER_RIGS
-- =====================================================

DROP POLICY IF EXISTS "Ver propios rigs" ON player_rigs;
CREATE POLICY "Ver propios rigs"
  ON player_rigs FOR SELECT
  USING (auth.uid() = player_id);

DROP POLICY IF EXISTS "Actualizar propios rigs" ON player_rigs;
CREATE POLICY "Actualizar propios rigs"
  ON player_rigs FOR UPDATE
  USING (auth.uid() = player_id);

-- =====================================================
-- POLÍTICAS PARA BLOCKS
-- =====================================================

DROP POLICY IF EXISTS "Bloques públicos" ON blocks;
CREATE POLICY "Bloques públicos"
  ON blocks FOR SELECT
  USING (true);

-- =====================================================
-- POLÍTICAS PARA MARKET_ORDERS
-- =====================================================

DROP POLICY IF EXISTS "Órdenes activas públicas" ON market_orders;
CREATE POLICY "Órdenes activas públicas"
  ON market_orders FOR SELECT
  USING (status = 'active' OR auth.uid() = player_id);

DROP POLICY IF EXISTS "Crear propias órdenes" ON market_orders;
CREATE POLICY "Crear propias órdenes"
  ON market_orders FOR INSERT
  WITH CHECK (auth.uid() = player_id);

DROP POLICY IF EXISTS "Actualizar propias órdenes" ON market_orders;
CREATE POLICY "Actualizar propias órdenes"
  ON market_orders FOR UPDATE
  USING (auth.uid() = player_id);

-- =====================================================
-- POLÍTICAS PARA TRADES
-- =====================================================

DROP POLICY IF EXISTS "Ver propios trades" ON trades;
CREATE POLICY "Ver propios trades"
  ON trades FOR SELECT
  USING (auth.uid() = buyer_id OR auth.uid() = seller_id);

-- =====================================================
-- POLÍTICAS PARA TRANSACTIONS
-- =====================================================

DROP POLICY IF EXISTS "Ver propias transacciones" ON transactions;
CREATE POLICY "Ver propias transacciones"
  ON transactions FOR SELECT
  USING (auth.uid() = player_id);

-- =====================================================
-- POLÍTICAS PARA REPUTATION_EVENTS
-- =====================================================

DROP POLICY IF EXISTS "Ver propios eventos de reputación" ON reputation_events;
CREATE POLICY "Ver propios eventos de reputación"
  ON reputation_events FOR SELECT
  USING (auth.uid() = player_id);

-- =====================================================
-- POLÍTICAS PARA BADGES
-- =====================================================

DROP POLICY IF EXISTS "Badges públicos" ON badges;
CREATE POLICY "Badges públicos"
  ON badges FOR SELECT
  USING (true);

-- =====================================================
-- POLÍTICAS PARA PLAYER_BADGES
-- =====================================================

DROP POLICY IF EXISTS "Badges de jugadores públicos" ON player_badges;
CREATE POLICY "Badges de jugadores públicos"
  ON player_badges FOR SELECT
  USING (true);

-- =====================================================
-- POLÍTICAS PARA PLAYER_EVENTS
-- =====================================================

DROP POLICY IF EXISTS "Ver propios eventos" ON player_events;
CREATE POLICY "Ver propios eventos"
  ON player_events FOR SELECT
  USING (auth.uid() = player_id);

-- =====================================================
-- POLÍTICAS PARA PLAYER_PENALTIES
-- =====================================================

DROP POLICY IF EXISTS "Ver propias penalizaciones" ON player_penalties;
CREATE POLICY "Ver propias penalizaciones"
  ON player_penalties FOR SELECT
  USING (auth.uid() = player_id);

-- =====================================================
-- POLÍTICAS PARA CHAT_MESSAGES
-- =====================================================

DROP POLICY IF EXISTS "Chat global público" ON chat_messages;
CREATE POLICY "Chat global público"
  ON chat_messages FOR SELECT
  USING (channel = 'global' OR auth.uid() = player_id);

DROP POLICY IF EXISTS "Enviar mensajes" ON chat_messages;
CREATE POLICY "Enviar mensajes"
  ON chat_messages FOR INSERT
  WITH CHECK (auth.uid() = player_id);

-- =====================================================
-- POLÍTICAS PARA NETWORK_STATS
-- =====================================================

DROP POLICY IF EXISTS "Stats de red públicas" ON network_stats;
CREATE POLICY "Stats de red públicas"
  ON network_stats FOR SELECT
  USING (true);

-- =====================================================
-- POLÍTICAS PARA PLAYER_INVENTORY
-- =====================================================

DROP POLICY IF EXISTS "Ver propio inventario" ON player_inventory;
CREATE POLICY "Ver propio inventario"
  ON player_inventory FOR SELECT
  USING (auth.uid() = player_id);

DROP POLICY IF EXISTS "Insertar en inventario" ON player_inventory;
CREATE POLICY "Insertar en inventario"
  ON player_inventory FOR INSERT
  WITH CHECK (auth.uid() = player_id);

DROP POLICY IF EXISTS "Actualizar inventario" ON player_inventory;
CREATE POLICY "Actualizar inventario"
  ON player_inventory FOR UPDATE
  USING (auth.uid() = player_id);

DROP POLICY IF EXISTS "Eliminar de inventario" ON player_inventory;
CREATE POLICY "Eliminar de inventario"
  ON player_inventory FOR DELETE
  USING (auth.uid() = player_id);

-- =====================================================
-- POLÍTICAS PARA RIG_COOLING
-- =====================================================

DROP POLICY IF EXISTS "Ver cooling de propios rigs" ON rig_cooling;
CREATE POLICY "Ver cooling de propios rigs"
  ON rig_cooling FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM player_rigs pr
      WHERE pr.id = rig_cooling.player_rig_id
      AND pr.player_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Insertar cooling en propios rigs" ON rig_cooling;
CREATE POLICY "Insertar cooling en propios rigs"
  ON rig_cooling FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM player_rigs pr
      WHERE pr.id = rig_cooling.player_rig_id
      AND pr.player_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Actualizar cooling de propios rigs" ON rig_cooling;
CREATE POLICY "Actualizar cooling de propios rigs"
  ON rig_cooling FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM player_rigs pr
      WHERE pr.id = rig_cooling.player_rig_id
      AND pr.player_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Eliminar cooling de propios rigs" ON rig_cooling;
CREATE POLICY "Eliminar cooling de propios rigs"
  ON rig_cooling FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM player_rigs pr
      WHERE pr.id = rig_cooling.player_rig_id
      AND pr.player_id = auth.uid()
    )
  );

-- =====================================================
-- POLÍTICAS PARA COOLING_ITEMS (catálogo)
-- =====================================================

DROP POLICY IF EXISTS "Catálogo de cooling público" ON cooling_items;
CREATE POLICY "Catálogo de cooling público"
  ON cooling_items FOR SELECT
  USING (true);

-- =====================================================
-- POLÍTICAS PARA PLAYER_COOLING
-- =====================================================

DROP POLICY IF EXISTS "Ver propio cooling" ON player_cooling;
CREATE POLICY "Ver propio cooling"
  ON player_cooling FOR SELECT
  USING (auth.uid() = player_id);

DROP POLICY IF EXISTS "Insertar propio cooling" ON player_cooling;
CREATE POLICY "Insertar propio cooling"
  ON player_cooling FOR INSERT
  WITH CHECK (auth.uid() = player_id);

DROP POLICY IF EXISTS "Actualizar propio cooling" ON player_cooling;
CREATE POLICY "Actualizar propio cooling"
  ON player_cooling FOR UPDATE
  USING (auth.uid() = player_id);

DROP POLICY IF EXISTS "Eliminar propio cooling" ON player_cooling;
CREATE POLICY "Eliminar propio cooling"
  ON player_cooling FOR DELETE
  USING (auth.uid() = player_id);

-- =====================================================
-- POLÍTICAS PARA PREPAID_CARDS (catálogo)
-- =====================================================

DROP POLICY IF EXISTS "Catálogo de tarjetas público" ON prepaid_cards;
CREATE POLICY "Catálogo de tarjetas público"
  ON prepaid_cards FOR SELECT
  USING (true);

-- =====================================================
-- POLÍTICAS PARA PLAYER_CARDS
-- =====================================================

DROP POLICY IF EXISTS "Ver propias tarjetas" ON player_cards;
CREATE POLICY "Ver propias tarjetas"
  ON player_cards FOR SELECT
  USING (auth.uid() = player_id);

DROP POLICY IF EXISTS "Insertar propias tarjetas" ON player_cards;
CREATE POLICY "Insertar propias tarjetas"
  ON player_cards FOR INSERT
  WITH CHECK (auth.uid() = player_id);

DROP POLICY IF EXISTS "Actualizar propias tarjetas" ON player_cards;
CREATE POLICY "Actualizar propias tarjetas"
  ON player_cards FOR UPDATE
  USING (auth.uid() = player_id);

-- =====================================================
-- POLÍTICAS PARA PLAYER_STREAKS (Rachas de login)
-- =====================================================

DROP POLICY IF EXISTS "Ver propia racha" ON player_streaks;
CREATE POLICY "Ver propia racha"
  ON player_streaks FOR SELECT
  USING (auth.uid() = player_id);

DROP POLICY IF EXISTS "Insertar propia racha" ON player_streaks;
CREATE POLICY "Insertar propia racha"
  ON player_streaks FOR INSERT
  WITH CHECK (auth.uid() = player_id);

DROP POLICY IF EXISTS "Actualizar propia racha" ON player_streaks;
CREATE POLICY "Actualizar propia racha"
  ON player_streaks FOR UPDATE
  USING (auth.uid() = player_id);

-- =====================================================
-- POLÍTICAS PARA STREAK_REWARDS (catálogo público)
-- =====================================================

DROP POLICY IF EXISTS "Recompensas de racha públicas" ON streak_rewards;
CREATE POLICY "Recompensas de racha públicas"
  ON streak_rewards FOR SELECT
  USING (true);

-- =====================================================
-- POLÍTICAS PARA STREAK_CLAIMS (Historial de claims)
-- =====================================================

DROP POLICY IF EXISTS "Ver propios claims de racha" ON streak_claims;
CREATE POLICY "Ver propios claims de racha"
  ON streak_claims FOR SELECT
  USING (auth.uid() = player_id);

DROP POLICY IF EXISTS "Insertar propios claims de racha" ON streak_claims;
CREATE POLICY "Insertar propios claims de racha"
  ON streak_claims FOR INSERT
  WITH CHECK (auth.uid() = player_id);

-- =====================================================
-- POLÍTICAS PARA MISSIONS (catálogo público)
-- =====================================================

DROP POLICY IF EXISTS "Misiones públicas" ON missions;
CREATE POLICY "Misiones públicas"
  ON missions FOR SELECT
  USING (true);

-- =====================================================
-- POLÍTICAS PARA PLAYER_MISSIONS (Misiones del jugador)
-- =====================================================

DROP POLICY IF EXISTS "Ver propias misiones" ON player_missions;
CREATE POLICY "Ver propias misiones"
  ON player_missions FOR SELECT
  USING (auth.uid() = player_id);

DROP POLICY IF EXISTS "Insertar propias misiones" ON player_missions;
CREATE POLICY "Insertar propias misiones"
  ON player_missions FOR INSERT
  WITH CHECK (auth.uid() = player_id);

DROP POLICY IF EXISTS "Actualizar propias misiones" ON player_missions;
CREATE POLICY "Actualizar propias misiones"
  ON player_missions FOR UPDATE
  USING (auth.uid() = player_id);

DROP POLICY IF EXISTS "Eliminar propias misiones" ON player_missions;
CREATE POLICY "Eliminar propias misiones"
  ON player_missions FOR DELETE
  USING (auth.uid() = player_id);

-- =====================================================
-- POLÍTICAS PARA PLAYER_ONLINE_TRACKING (Tiempo online)
-- =====================================================

DROP POLICY IF EXISTS "Ver propio tracking online" ON player_online_tracking;
CREATE POLICY "Ver propio tracking online"
  ON player_online_tracking FOR SELECT
  USING (auth.uid() = player_id);

DROP POLICY IF EXISTS "Insertar propio tracking online" ON player_online_tracking;
CREATE POLICY "Insertar propio tracking online"
  ON player_online_tracking FOR INSERT
  WITH CHECK (auth.uid() = player_id);

DROP POLICY IF EXISTS "Actualizar propio tracking online" ON player_online_tracking;
CREATE POLICY "Actualizar propio tracking online"
  ON player_online_tracking FOR UPDATE
  USING (auth.uid() = player_id);

-- =====================================================
-- POLÍTICAS PARA BOOST_ITEMS (catálogo público)
-- =====================================================

ALTER TABLE boost_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Catálogo de boosts público" ON boost_items;
CREATE POLICY "Catálogo de boosts público"
  ON boost_items FOR SELECT
  USING (true);

-- =====================================================
-- POLÍTICAS PARA PLAYER_BOOSTS (Boosts del jugador)
-- =====================================================

ALTER TABLE player_boosts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Ver propios boosts" ON player_boosts;
CREATE POLICY "Ver propios boosts"
  ON player_boosts FOR SELECT
  USING (auth.uid() = player_id);

DROP POLICY IF EXISTS "Insertar propios boosts" ON player_boosts;
CREATE POLICY "Insertar propios boosts"
  ON player_boosts FOR INSERT
  WITH CHECK (auth.uid() = player_id);

DROP POLICY IF EXISTS "Actualizar propios boosts" ON player_boosts;
CREATE POLICY "Actualizar propios boosts"
  ON player_boosts FOR UPDATE
  USING (auth.uid() = player_id);

DROP POLICY IF EXISTS "Eliminar propios boosts" ON player_boosts;
CREATE POLICY "Eliminar propios boosts"
  ON player_boosts FOR DELETE
  USING (auth.uid() = player_id);

-- =====================================================
-- POLÍTICAS PARA ACTIVE_BOOSTS (Boosts activos)
-- =====================================================

ALTER TABLE active_boosts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Ver propios boosts activos" ON active_boosts;
CREATE POLICY "Ver propios boosts activos"
  ON active_boosts FOR SELECT
  USING (auth.uid() = player_id);

DROP POLICY IF EXISTS "Insertar propios boosts activos" ON active_boosts;
CREATE POLICY "Insertar propios boosts activos"
  ON active_boosts FOR INSERT
  WITH CHECK (auth.uid() = player_id);

DROP POLICY IF EXISTS "Actualizar propios boosts activos" ON active_boosts;
CREATE POLICY "Actualizar propios boosts activos"
  ON active_boosts FOR UPDATE
  USING (auth.uid() = player_id);

DROP POLICY IF EXISTS "Eliminar propios boosts activos" ON active_boosts;
CREATE POLICY "Eliminar propios boosts activos"
  ON active_boosts FOR DELETE
  USING (auth.uid() = player_id);

-- =====================================================
-- POLÍTICAS PARA RIG_SLOT_UPGRADES (catálogo público)
-- =====================================================

ALTER TABLE rig_slot_upgrades ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Catálogo de upgrades de slots público" ON rig_slot_upgrades;
CREATE POLICY "Catálogo de upgrades de slots público"
  ON rig_slot_upgrades FOR SELECT
  USING (true);

-- =====================================================
-- POLÍTICAS PARA RIG_BOOSTS (Boosts instalados en rigs)
-- =====================================================

ALTER TABLE rig_boosts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Ver boosts de propios rigs" ON rig_boosts;
CREATE POLICY "Ver boosts de propios rigs"
  ON rig_boosts FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM player_rigs pr
      WHERE pr.id = rig_boosts.player_rig_id
      AND pr.player_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Insertar boosts en propios rigs" ON rig_boosts;
CREATE POLICY "Insertar boosts en propios rigs"
  ON rig_boosts FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM player_rigs pr
      WHERE pr.id = rig_boosts.player_rig_id
      AND pr.player_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Actualizar boosts de propios rigs" ON rig_boosts;
CREATE POLICY "Actualizar boosts de propios rigs"
  ON rig_boosts FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM player_rigs pr
      WHERE pr.id = rig_boosts.player_rig_id
      AND pr.player_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Eliminar boosts de propios rigs" ON rig_boosts;
CREATE POLICY "Eliminar boosts de propios rigs"
  ON rig_boosts FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM player_rigs pr
      WHERE pr.id = rig_boosts.player_rig_id
      AND pr.player_id = auth.uid()
    )
  );

-- =====================================================
-- POLÍTICAS PARA CRYPTO_PACKAGES (catálogo público)
-- =====================================================

ALTER TABLE crypto_packages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Catálogo de paquetes crypto público" ON crypto_packages;
CREATE POLICY "Catálogo de paquetes crypto público"
  ON crypto_packages FOR SELECT
  USING (true);

-- =====================================================
-- POLÍTICAS PARA CRYPTO_PURCHASES (Compras del jugador)
-- =====================================================

ALTER TABLE crypto_purchases ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Ver propias compras de crypto" ON crypto_purchases;
CREATE POLICY "Ver propias compras de crypto"
  ON crypto_purchases FOR SELECT
  USING (auth.uid() = player_id);

DROP POLICY IF EXISTS "Insertar propias compras de crypto" ON crypto_purchases;
CREATE POLICY "Insertar propias compras de crypto"
  ON crypto_purchases FOR INSERT
  WITH CHECK (auth.uid() = player_id);

DROP POLICY IF EXISTS "Actualizar propias compras de crypto" ON crypto_purchases;
CREATE POLICY "Actualizar propias compras de crypto"
  ON crypto_purchases FOR UPDATE
  USING (auth.uid() = player_id);

-- =====================================================
-- POLÍTICAS PARA ANNOUNCEMENTS (Anuncios públicos)
-- =====================================================

ALTER TABLE announcements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anuncios públicos visibles" ON announcements;
CREATE POLICY "Anuncios públicos visibles"
  ON announcements FOR SELECT
  USING (is_active = true AND starts_at <= NOW() AND (ends_at IS NULL OR ends_at > NOW()));
