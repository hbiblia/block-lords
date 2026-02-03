import { supabase } from './supabase';
import { withRetry, isRetryableError } from './retry';

// =====================================================
// WRAPPER FUNCTIONS PARA SUPABASE RPC
// =====================================================

/**
 * Helper para llamadas RPC con retry automático
 * Reintenta en errores de red/timeout, no en errores de lógica de negocio
 */
async function rpcWithRetry<T>(
  fnName: string,
  params: Record<string, unknown> = {},
  options: { maxRetries?: number; critical?: boolean } = {}
): Promise<T> {
  const { maxRetries = 3, critical = false } = options;

  const executeRpc = async () => {
    const { data, error } = await supabase.rpc(fnName, params);
    if (error) throw error;
    return data as T;
  };

  // For critical operations, always retry
  // For non-critical, only retry on network errors
  if (critical) {
    return withRetry(executeRpc, {
      maxRetries,
      onRetry: (attempt, error) => {
        console.warn(`[API] Retry ${attempt}/${maxRetries} for ${fnName}:`, error);
      },
    });
  }

  // Standard call with retry only for retryable errors
  return withRetry(executeRpc, {
    maxRetries,
    isRetryable: (error) => {
      // Don't retry business logic errors (insufficient funds, etc.)
      const errorObj = error as Record<string, unknown>;
      const message = String(errorObj?.message || '').toLowerCase();

      // These are NOT retryable (business logic errors)
      const nonRetryablePatterns = [
        'insufficient',
        'insuficiente',
        'not found',
        'no encontrado',
        'already',
        'ya existe',
        'invalid',
        'invalido',
        'unauthorized',
        'permission',
      ];

      if (nonRetryablePatterns.some(p => message.includes(p))) {
        return false;
      }

      return isRetryableError(error);
    },
    onRetry: (attempt, error) => {
      console.warn(`[API] Retry ${attempt}/${maxRetries} for ${fnName}:`, error);
    },
  });
}

// === AUTH ===

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function createPlayerProfile(userId: string, email: string, username: string): Promise<any> {
  return rpcWithRetry('create_player_profile', {
    p_user_id: userId,
    p_email: email,
    p_username: username,
  });
}

// === PLAYER ===

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function getPlayerProfile(playerId: string): Promise<any> {
  // Critical: player data is essential for the app
  return rpcWithRetry('get_player_profile', {
    p_player_id: playerId,
  }, { critical: true });
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function getPlayerRigs(playerId: string): Promise<any> {
  // Critical: rig data is essential for mining
  return rpcWithRetry('get_player_rigs', {
    p_player_id: playerId,
  }, { critical: true });
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

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function getNetworkStats(): Promise<any> {
  return rpcWithRetry('get_network_stats', {}, { critical: true });
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function getHomeStats(): Promise<any> {
  return rpcWithRetry('get_home_stats');
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function getRecentBlocks(limit = 20): Promise<any> {
  return rpcWithRetry('get_recent_blocks', { p_limit: limit });
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function getPlayerMiningStats(playerId: string): Promise<any> {
  return rpcWithRetry('get_player_mining_stats', {
    p_player_id: playerId,
  }, { critical: true });
}

// === MINING ESTIMATE ===

export interface MiningEstimate {
  success: boolean;
  mining: boolean;
  reason?: 'no_active_rigs' | 'offline';
  // Hashrate info
  playerHashrate: number;
  networkHashrate: number;
  networkShare: number;  // Porcentaje de la red
  // Probabilidades
  difficulty: number;
  probabilityPerTick: number;  // % por minuto
  // Estimaciones de tiempo
  estimatedMinutes: number;
  estimatedHours: number;
  minMinutes: number;  // Percentil 25
  maxMinutes: number;  // Percentil 75
  // Bloques esperados
  blocksPerHour: number;
  blocksPerDay: number;
  // Info adicional
  activeRigs: number;
  activeMiners: number;
  reputationMultiplier: number;
  error?: string;
}

export async function getMiningEstimate(playerId: string): Promise<MiningEstimate> {
  const { data, error } = await supabase.rpc('get_mining_estimate', {
    p_player_id: playerId,
  });

  if (error) throw error;
  return data as MiningEstimate;
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

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function getPlayerInventory(playerId: string): Promise<any> {
  return rpcWithRetry('get_player_inventory', {
    p_player_id: playerId,
  }, { critical: true });
}

export async function installCoolingFromInventory(playerId: string, coolingId: string) {
  const { data, error } = await supabase.rpc('install_cooling_from_inventory', {
    p_player_id: playerId,
    p_cooling_id: coolingId,
  });

  if (error) throw error;
  return data;
}

// === RIG INVENTORY ===

// Obtener rigs en inventario del jugador
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function getPlayerRigInventory(playerId: string): Promise<any> {
  return rpcWithRetry('get_player_rig_inventory', {
    p_player_id: playerId,
  });
}

// Instalar rig desde inventario
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function installRigFromInventory(playerId: string, rigId: string): Promise<any> {
  return rpcWithRetry('install_rig_from_inventory', {
    p_player_id: playerId,
    p_rig_id: rigId,
  }, { critical: true });
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

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function getStreakStatus(playerId: string): Promise<any> {
  return rpcWithRetry('get_streak_status', {
    p_player_id: playerId,
  }, { critical: true });
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function claimDailyStreak(playerId: string): Promise<any> {
  // Critical: claiming streak affects rewards
  return rpcWithRetry('claim_daily_streak', {
    p_player_id: playerId,
  }, { critical: true, maxRetries: 5 });
}

// === MISIONES DIARIAS ===

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function getDailyMissions(playerId: string): Promise<any> {
  return rpcWithRetry('get_daily_missions', {
    p_player_id: playerId,
  }, { critical: true });
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function claimMissionReward(playerId: string, missionUuid: string): Promise<any> {
  // Critical: claiming rewards is a financial operation
  return rpcWithRetry('claim_mission_reward', {
    p_player_id: playerId,
    p_mission_uuid: missionUuid,
  }, { critical: true, maxRetries: 5 });
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

// === DESTROY INSTALLED ITEMS ===

// Destruir cooling instalado en un rig
export async function removeCoolingFromRig(playerId: string, rigId: string, coolingId: string) {
  const { data, error } = await supabase.rpc('remove_cooling_from_rig', {
    p_player_id: playerId,
    p_rig_id: rigId,
    p_cooling_id: coolingId,
  });

  if (error) throw error;
  return data;
}

// Destruir boost instalado en un rig
export async function removeBoostFromRig(playerId: string, rigId: string, boostId: string) {
  const { data, error } = await supabase.rpc('remove_boost_from_rig', {
    p_player_id: playerId,
    p_rig_id: rigId,
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

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function getPendingBlocks(playerId: string): Promise<any> {
  // Critical: losing pending blocks means losing rewards
  return rpcWithRetry('get_pending_blocks', {
    p_player_id: playerId,
  }, { critical: true });
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function getPendingBlocksCount(playerId: string): Promise<any> {
  return rpcWithRetry('get_pending_blocks_count', {
    p_player_id: playerId,
  });
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function claimBlock(playerId: string, pendingId: string): Promise<any> {
  // Critical: claiming blocks is a financial operation
  return rpcWithRetry('claim_block', {
    p_player_id: playerId,
    p_pending_id: pendingId,
  }, { critical: true, maxRetries: 5 });
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function claimAllBlocks(playerId: string): Promise<any> {
  // Critical: claiming blocks is a financial operation
  return rpcWithRetry('claim_all_blocks', {
    p_player_id: playerId,
  }, { critical: true, maxRetries: 5 });
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function claimAllBlocksWithRon(playerId: string): Promise<any> {
  // Critical: claiming blocks with RON payment is a financial operation
  return rpcWithRetry('claim_all_blocks_with_ron', {
    p_player_id: playerId,
  }, { critical: true, maxRetries: 5 });
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function getPlayerPityStats(playerId: string): Promise<any> {
  return rpcWithRetry('get_player_pity_stats', {
    p_player_id: playerId,
  });
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

// === RON DEPOSITS ===

export async function depositRon(playerId: string, amount: number, txHash: string) {
  const { data, error } = await supabase.rpc('deposit_ron', {
    p_player_id: playerId,
    p_amount: amount,
    p_tx_hash: txHash,
  });

  if (error) throw error;
  return data;
}

export async function getRonDepositHistory(playerId: string, limit: number = 10) {
  const { data, error } = await supabase.rpc('get_ron_deposit_history', {
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

// === REFERRAL SYSTEM ===

export interface ReferralInfo {
  success: boolean;
  referralCode: string;
  referralCount: number;
  referredBy: string | null;
  recentReferrals: Array<{ username: string; joinedAt: string }>;
  error?: string;
}

export interface ApplyReferralResult {
  success: boolean;
  referrerUsername?: string;
  referrerBonus?: number;
  playerBonus?: number;
  error?: string;
}

// Obtener información de referidos del jugador
export async function getReferralInfo(playerId: string): Promise<ReferralInfo> {
  const { data, error } = await supabase.rpc('get_referral_info', {
    p_player_id: playerId,
  });

  if (error) throw error;
  return data as ReferralInfo;
}

// Aplicar código de referido
export async function applyReferralCode(playerId: string, referralCode: string): Promise<ApplyReferralResult> {
  const { data, error } = await supabase.rpc('apply_referral_code', {
    p_player_id: playerId,
    p_referral_code: referralCode,
  });

  if (error) throw error;
  return data as ApplyReferralResult;
}

export interface UpdateReferralCodeResult {
  success: boolean;
  newCode?: string;
  cost?: number;
  error?: string;
}

// Referral list interfaces
export interface ReferralListItem {
  id: string;
  username: string;
  joinedAt: string;
  isOnline: boolean;
  lastSeen: string | null;
  blocksMined: number;
  cryptoEarned: number;
  reputation: number;
  daysAgo: number;
  isActive: boolean;
  activeRigs: number;
}

export interface ReferralListPagination {
  total: number;
  limit: number;
  offset: number;
  hasMore: boolean;
}

export interface ReferralListStats {
  totalReferrals: number;
  activeReferrals: number;
  totalBlocksByReferrals: number;
  totalCryptoByReferrals: number;
}

export interface ReferralListResponse {
  success: boolean;
  referrals: ReferralListItem[];
  pagination: ReferralListPagination;
  stats: ReferralListStats;
  error?: string;
}

// Actualizar código de referido (cuesta 500 crypto)
export async function updateReferralCode(playerId: string, newCode: string): Promise<UpdateReferralCodeResult> {
  const { data, error } = await supabase.rpc('update_referral_code', {
    p_player_id: playerId,
    p_new_code: newCode,
  });

  if (error) throw error;
  return data as UpdateReferralCodeResult;
}

// Obtener lista completa de referidos con paginación
export async function getReferralList(
  playerId: string,
  limit: number = 50,
  offset: number = 0
): Promise<ReferralListResponse> {
  const { data, error } = await supabase.rpc('get_referral_list', {
    p_player_id: playerId,
    p_limit: limit,
    p_offset: offset,
  });

  if (error) throw error;
  return data as ReferralListResponse;
}

// === RONIN WALLET PAYMENTS ===

export interface VerifyRoninPaymentResult {
  success: boolean;
  cryptoReceived?: number;
  txVerified?: boolean;
  error?: string;
}

// Verify a Ronin blockchain transaction for crypto package purchase
export async function verifyRoninPayment(
  txHash: string,
  packageId: string,
  playerId: string,
  expectedAmount: number
): Promise<VerifyRoninPaymentResult> {
  const { data, error } = await supabase.functions.invoke('verify-ronin-tx', {
    body: {
      txHash,
      packageId,
      playerId,
      expectedAmount,
    },
  });

  if (error) {
    console.error('Error verifying Ronin payment:', error);
    return { success: false, error: error.message || 'Error verifying payment' };
  }

  return data as VerifyRoninPaymentResult;
}

