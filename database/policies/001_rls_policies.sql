-- =====================================================
-- CRYPTO ARCADE MMO - Políticas RLS
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

-- =====================================================
-- POLÍTICAS PARA PLAYERS
-- =====================================================

-- Cualquiera puede ver perfiles públicos
CREATE POLICY "Perfiles públicos visibles"
  ON players FOR SELECT
  USING (true);

-- Solo el propio usuario puede actualizar su perfil
CREATE POLICY "Usuarios actualizan su propio perfil"
  ON players FOR UPDATE
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- =====================================================
-- POLÍTICAS PARA RIGS (catálogo)
-- =====================================================

-- Todos pueden ver el catálogo de rigs
CREATE POLICY "Catálogo de rigs público"
  ON rigs FOR SELECT
  USING (true);

-- =====================================================
-- POLÍTICAS PARA PLAYER_RIGS
-- =====================================================

-- Usuarios ven sus propios rigs
CREATE POLICY "Ver propios rigs"
  ON player_rigs FOR SELECT
  USING (auth.uid() = player_id);

-- Usuarios pueden actualizar sus propios rigs
CREATE POLICY "Actualizar propios rigs"
  ON player_rigs FOR UPDATE
  USING (auth.uid() = player_id);

-- =====================================================
-- POLÍTICAS PARA BLOCKS
-- =====================================================

-- Todos pueden ver bloques
CREATE POLICY "Bloques públicos"
  ON blocks FOR SELECT
  USING (true);

-- =====================================================
-- POLÍTICAS PARA MARKET_ORDERS
-- =====================================================

-- Todos pueden ver órdenes activas
CREATE POLICY "Órdenes activas públicas"
  ON market_orders FOR SELECT
  USING (status = 'active' OR auth.uid() = player_id);

-- Usuarios crean sus propias órdenes
CREATE POLICY "Crear propias órdenes"
  ON market_orders FOR INSERT
  WITH CHECK (auth.uid() = player_id);

-- Usuarios actualizan sus propias órdenes
CREATE POLICY "Actualizar propias órdenes"
  ON market_orders FOR UPDATE
  USING (auth.uid() = player_id);

-- =====================================================
-- POLÍTICAS PARA TRADES
-- =====================================================

-- Usuarios ven trades donde participaron
CREATE POLICY "Ver propios trades"
  ON trades FOR SELECT
  USING (auth.uid() = buyer_id OR auth.uid() = seller_id);

-- =====================================================
-- POLÍTICAS PARA TRANSACTIONS
-- =====================================================

-- Usuarios ven sus propias transacciones
CREATE POLICY "Ver propias transacciones"
  ON transactions FOR SELECT
  USING (auth.uid() = player_id);

-- =====================================================
-- POLÍTICAS PARA REPUTATION_EVENTS
-- =====================================================

-- Usuarios ven sus propios eventos de reputación
CREATE POLICY "Ver propios eventos de reputación"
  ON reputation_events FOR SELECT
  USING (auth.uid() = player_id);

-- =====================================================
-- POLÍTICAS PARA BADGES
-- =====================================================

-- Todos pueden ver badges
CREATE POLICY "Badges públicos"
  ON badges FOR SELECT
  USING (true);

-- =====================================================
-- POLÍTICAS PARA PLAYER_BADGES
-- =====================================================

-- Todos pueden ver badges de jugadores (para mostrar en perfiles)
CREATE POLICY "Badges de jugadores públicos"
  ON player_badges FOR SELECT
  USING (true);

-- =====================================================
-- POLÍTICAS PARA PLAYER_EVENTS
-- =====================================================

-- Usuarios ven sus propios eventos
CREATE POLICY "Ver propios eventos"
  ON player_events FOR SELECT
  USING (auth.uid() = player_id);

-- =====================================================
-- POLÍTICAS PARA PLAYER_PENALTIES
-- =====================================================

-- Usuarios ven sus propias penalizaciones
CREATE POLICY "Ver propias penalizaciones"
  ON player_penalties FOR SELECT
  USING (auth.uid() = player_id);

-- =====================================================
-- POLÍTICAS PARA CHAT_MESSAGES
-- =====================================================

-- Todos pueden ver mensajes del chat global
CREATE POLICY "Chat global público"
  ON chat_messages FOR SELECT
  USING (channel = 'global' OR auth.uid() = player_id);

-- Usuarios autenticados pueden enviar mensajes
CREATE POLICY "Enviar mensajes"
  ON chat_messages FOR INSERT
  WITH CHECK (auth.uid() = player_id);

-- =====================================================
-- POLÍTICAS PARA NETWORK_STATS
-- =====================================================

-- Todos pueden ver estadísticas de la red
CREATE POLICY "Stats de red públicas"
  ON network_stats FOR SELECT
  USING (true);
