import { supabase } from './supabase';

// =====================================================
// WRAPPER FUNCTIONS PARA SUPABASE RPC
// =====================================================

// === AUTH ===

export async function createPlayerProfile(userId: string, email: string, username: string) {
  const { data, error } = await supabase.rpc('create_player_profile', {
    p_user_id: userId,
    p_email: email,
    p_username: username,
  });

  if (error) throw error;
  return data;
}

// === PLAYER ===

export async function getPlayerProfile(playerId: string) {
  const { data, error } = await supabase.rpc('get_player_profile', {
    p_player_id: playerId,
  });

  if (error) throw error;
  return data;
}

export async function getPlayerRigs(playerId: string) {
  const { data, error } = await supabase.rpc('get_player_rigs', {
    p_player_id: playerId,
  });

  if (error) throw error;
  return data;
}

export async function toggleRig(playerId: string, rigId: string) {
  const { data, error } = await supabase.rpc('toggle_rig', {
    p_player_id: playerId,
    p_rig_id: rigId,
  });

  if (error) throw error;
  return data;
}

export async function repairRig(playerId: string, rigId: string) {
  const { data, error } = await supabase.rpc('repair_rig', {
    p_player_id: playerId,
    p_rig_id: rigId,
  });

  if (error) throw error;
  return data;
}

export async function rechargeEnergy(playerId: string, amount: number) {
  const { data, error } = await supabase.rpc('recharge_energy', {
    p_player_id: playerId,
    p_amount: amount,
  });

  if (error) throw error;
  return data;
}

export async function rechargeInternet(playerId: string, amount: number) {
  const { data, error } = await supabase.rpc('recharge_internet', {
    p_player_id: playerId,
    p_amount: amount,
  });

  if (error) throw error;
  return data;
}

export async function getPlayerTransactions(playerId: string, limit = 50) {
  const { data, error } = await supabase.rpc('get_player_transactions', {
    p_player_id: playerId,
    p_limit: limit,
  });

  if (error) throw error;
  return data;
}

// === MINING ===

export async function getNetworkStats() {
  const { data, error } = await supabase.rpc('get_network_stats');

  if (error) throw error;
  return data;
}

export async function getRecentBlocks(limit = 20) {
  const { data, error } = await supabase.rpc('get_recent_blocks', {
    p_limit: limit,
  });

  if (error) throw error;
  return data;
}

export async function getPlayerMiningStats(playerId: string) {
  const { data, error } = await supabase.rpc('get_player_mining_stats', {
    p_player_id: playerId,
  });

  if (error) throw error;
  return data;
}

// Procesar tick de minería (normalmente llamado por cron/scheduler)
export async function processMiningTick() {
  const { data, error } = await supabase.rpc('process_mining_tick');

  if (error) throw error;
  return data;
}

// === MARKET ===

export async function getOrderBook(itemType: string) {
  const { data, error } = await supabase.rpc('get_order_book', {
    p_item_type: itemType,
  });

  if (error) throw error;
  return data;
}

export async function createMarketOrder(
  playerId: string,
  type: 'buy' | 'sell',
  itemType: string,
  quantity: number,
  pricePerUnit: number,
  itemId?: string
) {
  const { data, error } = await supabase.rpc('create_market_order', {
    p_player_id: playerId,
    p_type: type,
    p_item_type: itemType,
    p_quantity: quantity,
    p_price_per_unit: pricePerUnit,
    p_item_id: itemId ?? null,
  });

  if (error) throw error;
  return data;
}

export async function cancelMarketOrder(playerId: string, orderId: string) {
  const { data, error } = await supabase.rpc('cancel_market_order', {
    p_player_id: playerId,
    p_order_id: orderId,
  });

  if (error) throw error;
  return data;
}

export async function getPlayerOrders(playerId: string) {
  const { data, error } = await supabase.rpc('get_player_orders', {
    p_player_id: playerId,
  });

  if (error) throw error;
  return data;
}

export async function getPlayerTrades(playerId: string, limit = 50) {
  const { data, error } = await supabase.rpc('get_player_trades', {
    p_player_id: playerId,
    p_limit: limit,
  });

  if (error) throw error;
  return data;
}

export async function getMarketStats() {
  const { data, error } = await supabase.rpc('get_market_stats');

  if (error) throw error;
  return data;
}

// === LEADERBOARD ===

export async function getReputationLeaderboard(limit = 100) {
  const { data, error } = await supabase.rpc('get_reputation_leaderboard', {
    p_limit: limit,
  });

  if (error) throw error;
  return data;
}

export async function getMiningLeaderboard(limit = 100) {
  const { data, error } = await supabase.rpc('get_mining_leaderboard', {
    p_limit: limit,
  });

  if (error) throw error;
  return data;
}

// === COOLING (REFRIGERACIÓN) ===

export async function getCoolingItems() {
  const { data, error } = await supabase.rpc('get_cooling_items');

  if (error) throw error;
  return data;
}

export async function getPlayerCooling(playerId: string) {
  const { data, error } = await supabase.rpc('get_player_cooling', {
    p_player_id: playerId,
  });

  if (error) throw error;
  return data;
}

export async function installCooling(playerId: string, coolingId: string) {
  const { data, error } = await supabase.rpc('install_cooling', {
    p_player_id: playerId,
    p_cooling_id: coolingId,
  });

  if (error) throw error;
  return data;
}

// === PREPAID CARDS (TARJETAS PREPAGO) ===

export async function getPrepaidCards() {
  const { data, error } = await supabase.rpc('get_prepaid_cards');

  if (error) throw error;
  return data;
}

export async function getPlayerCards(playerId: string) {
  const { data, error } = await supabase.rpc('get_player_cards', {
    p_player_id: playerId,
  });

  if (error) throw error;
  return data;
}

export async function buyPrepaidCard(playerId: string, cardId: string) {
  const { data, error } = await supabase.rpc('buy_prepaid_card', {
    p_player_id: playerId,
    p_card_id: cardId,
  });

  if (error) throw error;
  return data;
}

export async function redeemPrepaidCard(playerId: string, code: string) {
  const { data, error } = await supabase.rpc('redeem_prepaid_card', {
    p_player_id: playerId,
    p_code: code,
  });

  if (error) throw error;
  return data;
}

// === INVENTORY (INVENTARIO) ===

export async function getPlayerInventory(playerId: string) {
  const { data, error } = await supabase.rpc('get_player_inventory', {
    p_player_id: playerId,
  });

  if (error) throw error;
  return data;
}

export async function installCoolingFromInventory(playerId: string, coolingId: string) {
  const { data, error } = await supabase.rpc('install_cooling_from_inventory', {
    p_player_id: playerId,
    p_cooling_id: coolingId,
  });

  if (error) throw error;
  return data;
}

// Instalar cooling en un rig específico
export async function installCoolingToRig(playerId: string, rigId: string, coolingId: string) {
  const { data, error } = await supabase.rpc('install_cooling_to_rig', {
    p_player_id: playerId,
    p_rig_id: rigId,
    p_cooling_id: coolingId,
  });

  if (error) throw error;
  return data;
}

// Obtener cooling instalado en un rig
export async function getRigCooling(rigId: string) {
  const { data, error } = await supabase.rpc('get_rig_cooling', {
    p_rig_id: rigId,
  });

  if (error) throw error;
  return data;
}

// Comprar cooling (va al inventario)
export async function buyCooling(playerId: string, coolingId: string) {
  const { data, error } = await supabase.rpc('buy_cooling', {
    p_player_id: playerId,
    p_cooling_id: coolingId,
  });

  if (error) throw error;
  return data;
}

// Comprar rig
export async function buyRig(playerId: string, rigId: string) {
  const { data, error } = await supabase.rpc('buy_rig', {
    p_player_id: playerId,
    p_rig_id: rigId,
  });

  if (error) throw error;
  return data;
}

// === EXCHANGE (CRYPTO) ===

export async function exchangeCryptoToGamecoin(playerId: string, cryptoAmount: number) {
  const { data, error } = await supabase.rpc('exchange_crypto_to_gamecoin', {
    p_player_id: playerId,
    p_crypto_amount: cryptoAmount,
  });

  if (error) throw error;
  return data;
}

export async function exchangeCryptoToRon(playerId: string, cryptoAmount: number) {
  const { data, error } = await supabase.rpc('exchange_crypto_to_ron', {
    p_player_id: playerId,
    p_crypto_amount: cryptoAmount,
  });

  if (error) throw error;
  return data;
}

export async function getExchangeRates() {
  const { data, error } = await supabase.rpc('get_exchange_rates');

  if (error) throw error;
  return data;
}

