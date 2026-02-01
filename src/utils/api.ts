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

export async function deleteRig(playerId: string, rigId: string) {
  const { data, error } = await supabase.rpc('delete_rig', {
    p_player_id: playerId,
    p_rig_id: rigId,
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

export async function getHomeStats() {
  const { data, error } = await supabase.rpc('get_home_stats');

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

// === RIG SLOTS ===

// Obtener información de slots del jugador
export async function getPlayerSlotInfo(playerId: string) {
  const { data, error } = await supabase.rpc('get_player_slot_info', {
    p_player_id: playerId,
  });

  if (error) throw error;
  return data;
}

// Obtener lista de upgrades de slots disponibles
export async function getRigSlotUpgrades() {
  const { data, error } = await supabase.rpc('get_rig_slot_upgrades');

  if (error) throw error;
  return data;
}

// Comprar un slot adicional
export async function buyRigSlot(playerId: string) {
  const { data, error } = await supabase.rpc('buy_rig_slot', {
    p_player_id: playerId,
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

// === ENGAGEMENT (REGENERACIÓN PASIVA) ===

export async function applyPassiveRegeneration(playerId: string) {
  const { data, error } = await supabase.rpc('apply_passive_regeneration', {
    p_player_id: playerId,
  });

  if (error) throw error;
  return data;
}

// === STREAK (RACHA DIARIA) ===

export async function getStreakStatus(playerId: string) {
  const { data, error } = await supabase.rpc('get_streak_status', {
    p_player_id: playerId,
  });

  if (error) throw error;
  return data;
}

export async function claimDailyStreak(playerId: string) {
  const { data, error } = await supabase.rpc('claim_daily_streak', {
    p_player_id: playerId,
  });

  if (error) throw error;
  return data;
}

// === MISIONES DIARIAS ===

export async function getDailyMissions(playerId: string) {
  const { data, error } = await supabase.rpc('get_daily_missions', {
    p_player_id: playerId,
  });

  if (error) throw error;
  return data;
}

export async function claimMissionReward(playerId: string, missionUuid: string) {
  const { data, error } = await supabase.rpc('claim_mission_reward', {
    p_player_id: playerId,
    p_mission_uuid: missionUuid,
  });

  if (error) throw error;
  return data;
}

export async function recordOnlineHeartbeat(playerId: string) {
  const { data, error } = await supabase.rpc('record_online_heartbeat', {
    p_player_id: playerId,
  });

  if (error) throw error;
  return data;
}

export async function updateMissionProgress(playerId: string, missionType: string, increment: number) {
  const { data, error } = await supabase.rpc('update_mission_progress', {
    p_player_id: playerId,
    p_mission_type: missionType,
    p_increment: increment,
  });

  if (error) throw error;
  return data;
}

// === BOOSTS ===

export async function getBoostItems() {
  const { data, error } = await supabase.rpc('get_boost_items');

  if (error) throw error;
  return data;
}

export async function getPlayerBoosts(playerId: string) {
  const { data, error } = await supabase.rpc('get_player_boosts', {
    p_player_id: playerId,
  });

  if (error) throw error;
  return data;
}

export async function buyBoost(playerId: string, boostId: string) {
  const { data, error } = await supabase.rpc('buy_boost', {
    p_player_id: playerId,
    p_boost_id: boostId,
  });

  if (error) throw error;
  return data;
}

// === RIG-SPECIFIC BOOSTS ===

// Instalar boost en un rig específico
export async function installBoostToRig(playerId: string, rigId: string, boostId: string) {
  const { data, error } = await supabase.rpc('install_boost_to_rig', {
    p_player_id: playerId,
    p_rig_id: rigId,
    p_boost_id: boostId,
  });

  if (error) throw error;
  return data;
}

// Obtener boosts instalados en un rig
export async function getRigBoosts(rigId: string) {
  const { data, error } = await supabase.rpc('get_rig_boosts', {
    p_rig_id: rigId,
  });

  if (error) throw error;
  return data;
}

// === RIG UPGRADES ===

export async function upgradeRig(playerId: string, playerRigId: string, upgradeType: 'hashrate' | 'efficiency' | 'thermal') {
  const { data, error } = await supabase.rpc('upgrade_rig', {
    p_player_id: playerId,
    p_player_rig_id: playerRigId,
    p_upgrade_type: upgradeType,
  });

  if (error) throw error;
  return data;
}

export async function getRigUpgrades(playerRigId: string) {
  const { data, error } = await supabase.rpc('get_rig_upgrades', {
    p_player_rig_id: playerRigId,
  });

  if (error) throw error;
  return data;
}

// === PROFILE ===

export async function updateRonWallet(playerId: string, walletAddress: string | null) {
  const { data, error } = await supabase.rpc('update_ron_wallet', {
    p_player_id: playerId,
    p_wallet_address: walletAddress ?? '',
  });

  if (error) throw error;
  return data;
}

export async function resetPlayerAccount(playerId: string) {
  const { data, error } = await supabase.rpc('reset_player_account', {
    p_player_id: playerId,
  });

  if (error) throw error;
  return data;
}

// === ANNOUNCEMENTS ===

export async function getActiveAnnouncements() {
  const { data, error } = await supabase.rpc('get_active_announcements');

  if (error) throw error;
  return data;
}

// === PENDING BLOCKS (CLAIM SYSTEM) ===

export async function getPendingBlocks(playerId: string) {
  const { data, error } = await supabase.rpc('get_pending_blocks', {
    p_player_id: playerId,
  });

  if (error) throw error;
  return data;
}

export async function getPendingBlocksCount(playerId: string) {
  const { data, error } = await supabase.rpc('get_pending_blocks_count', {
    p_player_id: playerId,
  });

  if (error) throw error;
  return data;
}

export async function claimBlock(pendingId: string) {
  const { data, error } = await supabase.rpc('claim_block', {
    p_pending_id: pendingId,
  });

  if (error) throw error;
  return data;
}

export async function claimAllBlocks() {
  const { data, error } = await supabase.rpc('claim_all_blocks');

  if (error) throw error;
  return data;
}

// === RON WITHDRAWALS ===

export async function requestRonWithdrawal(playerId: string) {
  const { data, error } = await supabase.rpc('request_ron_withdrawal', {
    p_player_id: playerId,
  });

  if (error) throw error;
  return data;
}

export async function getWithdrawalHistory(playerId: string, limit: number = 10) {
  const { data, error } = await supabase.rpc('get_withdrawal_history', {
    p_player_id: playerId,
    p_limit: limit,
  });

  if (error) throw error;
  return data;
}

// === ADMIN: RON WITHDRAWALS ===

export async function adminGetPendingWithdrawals() {
  const { data, error } = await supabase.rpc('admin_get_pending_withdrawals');

  if (error) throw error;
  return data;
}

export async function adminStartProcessing(withdrawalId: string) {
  const { data, error } = await supabase.rpc('admin_start_processing', {
    p_withdrawal_id: withdrawalId,
  });

  if (error) throw error;
  return data;
}

export async function adminCompleteWithdrawal(withdrawalId: string, txHash: string) {
  const { data, error } = await supabase.rpc('admin_complete_withdrawal', {
    p_withdrawal_id: withdrawalId,
    p_tx_hash: txHash,
  });

  if (error) throw error;
  return data;
}

export async function adminFailWithdrawal(withdrawalId: string, errorMessage: string) {
  const { data, error } = await supabase.rpc('admin_fail_withdrawal', {
    p_withdrawal_id: withdrawalId,
    p_error_message: errorMessage,
  });

  if (error) throw error;
  return data;
}

export async function adminGetWithdrawalStats() {
  const { data, error } = await supabase.rpc('admin_get_withdrawal_stats');

  if (error) throw error;
  return data;
}

// Trigger manual del procesamiento de retiros (llama a la Edge Function)
export async function adminTriggerWithdrawalProcessing() {
  const { data, error } = await supabase.functions.invoke('process-withdrawals');

  if (error) throw error;
  return data;
}

// Obtener estado completo del sistema de retiros
export async function adminGetWithdrawalSystemStatus() {
  const { data, error } = await supabase.rpc('admin_get_withdrawal_system_status');

  if (error) throw error;
  return data;
}

// === PREMIUM SUBSCRIPTIONS ===

export interface PremiumStatus {
  success: boolean;
  is_premium: boolean;
  expires_at: string | null;
  days_remaining: number;
  price: number;
  benefits: {
    block_bonus: string;
    withdrawal_fee: string;
  };
  error?: string;
}

export interface PurchasePremiumResult {
  success: boolean;
  subscription_id?: string;
  expires_at?: string;
  price?: number;
  new_balance?: number;
  error?: string;
  required?: number;
  current?: number;
}

// Obtener estado premium del jugador actual
export async function getPremiumStatus(playerId: string): Promise<PremiumStatus> {
  const { data, error } = await supabase.rpc('get_premium_status', {
    p_player_id: playerId,
  });

  if (error) throw error;
  return data as PremiumStatus;
}

// Comprar suscripción premium
export async function purchasePremium(playerId: string): Promise<PurchasePremiumResult> {
  const { data, error } = await supabase.rpc('purchase_premium', {
    p_player_id: playerId,
  });

  if (error) throw error;
  return data as PurchasePremiumResult;
}

// Obtener historial de suscripciones premium
export async function getPremiumHistory(playerId: string, limit: number = 10) {
  const { data, error } = await supabase.rpc('get_premium_history', {
    p_player_id: playerId,
    p_limit: limit,
  });

  if (error) throw error;
  return data;
}

