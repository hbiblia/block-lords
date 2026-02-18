import { supabase } from './supabase';
import { withRetry, isRetryableError } from './retry';
import { isTabLocked } from '@/composables/useTabLock';

// =====================================================
// WRAPPER FUNCTIONS PARA SUPABASE RPC
// =====================================================

/**
 * Estado de conexión global
 */
export const connectionState = {
  isOnline: true,
  lastError: null as string | null,
  lastErrorTime: 0,
  failureCount: 0,
  listeners: new Set<(online: boolean, error?: string) => void>(),

  setOnline(online: boolean, error?: string) {
    const wasOnline = this.isOnline;
    this.isOnline = online;
    this.lastError = error || null;
    this.lastErrorTime = Date.now();
    if (!online) {
      this.failureCount++;
    } else {
      this.failureCount = 0;
    }
    // Notificar listeners solo si cambió el estado
    if (wasOnline !== online || error) {
      this.listeners.forEach(fn => fn(online, error));
    }
  },

  subscribe(fn: (online: boolean, error?: string) => void) {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  },
};

/**
 * Timeout para promesas
 */
function withTimeout<T>(promise: Promise<T>, ms: number, operation: string): Promise<T> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      reject(new Error(`Timeout: ${operation} tardó más de ${ms / 1000}s`));
    }, ms);

    promise
      .then((result) => {
        clearTimeout(timer);
        resolve(result);
      })
      .catch((error) => {
        clearTimeout(timer);
        reject(error);
      });
  });
}

// Timeout por defecto: 15 segundos
const DEFAULT_TIMEOUT = 15000;
// Timeout para operaciones críticas: 30 segundos
const CRITICAL_TIMEOUT = 30000;

// Request deduplication: reuse in-flight promises for the same RPC call
const inflightRequests = new Map<string, Promise<unknown>>();

function getDedupeKey(fnName: string, params: Record<string, unknown>): string {
  const paramStr = Object.keys(params).length > 0 ? JSON.stringify(params) : '';
  return `${fnName}:${paramStr}`;
}

/**
 * Helper para llamadas RPC con retry automático y timeout
 * Reintenta en errores de red/timeout, no en errores de lógica de negocio
 */
async function rpcWithRetry<T>(
  fnName: string,
  params: Record<string, unknown> = {},
  options: { maxRetries?: number; critical?: boolean; timeout?: number; dedupe?: boolean } = {}
): Promise<T> {
  const { maxRetries: maxRetriesOpt, critical = false, timeout, dedupe = true } = options;

  // Fast-fail: si la conexión está caída y la operación no es crítica, intentar solo 1 vez
  let maxRetries = maxRetriesOpt ?? (isTabLocked.value ? 0 : 3);
  if (!connectionState.isOnline && !critical) {
    maxRetries = Math.min(maxRetries, 1);
  }

  const timeoutMs = timeout ?? (critical ? CRITICAL_TIMEOUT : DEFAULT_TIMEOUT);

  // Deduplication: if the same RPC is already in flight, reuse its promise
  const dedupeKey = getDedupeKey(fnName, params);
  if (dedupe) {
    const existing = inflightRequests.get(dedupeKey);
    if (existing) {
      return existing as Promise<T>;
    }
  }

  const executeRpc = async () => {
    const rpcPromise = Promise.resolve(supabase.rpc(fnName, params));
    const { data, error } = await withTimeout(rpcPromise, timeoutMs, fnName);
    if (error) throw error;
    // Conexión exitosa
    if (!connectionState.isOnline) {
      connectionState.setOnline(true);
    }
    return data as T;
  };

  // Helper para marcar conexión como lenta/offline en el primer retry
  const markConnectionIssue = (error: unknown) => {
    const errorObj = error as Record<string, unknown>;
    const message = String(errorObj?.message || '').toLowerCase();
    if (
      message.includes('timeout') ||
      message.includes('network') ||
      message.includes('fetch') ||
      message.includes('abort') ||
      message.includes('connection')
    ) {
      // Marcar inmediatamente al primer error de conexión
      connectionState.setOnline(false, message);
    }
  };

  const promise = (async () => {
    try {
      // For critical operations, always retry
      // For non-critical, only retry on network errors
      if (critical) {
        return await withRetry(executeRpc, {
          maxRetries,
          onRetry: (attempt, error) => {
            console.warn(`[API] Retry ${attempt}/${maxRetries} for ${fnName}:`, error);
            markConnectionIssue(error);
          },
        });
      }

      // Standard call with retry only for retryable errors
      return await withRetry(executeRpc, {
        maxRetries,
        isRetryable: (error) => {
          const errorObj = error as Record<string, unknown>;
          const message = String(errorObj?.message || '').toLowerCase();

          const nonRetryablePatterns = [
            'insufficient', 'insuficiente', 'not found', 'no encontrado',
            'already', 'ya existe', 'invalid', 'invalido', 'unauthorized', 'permission',
          ];

          if (nonRetryablePatterns.some(p => message.includes(p))) {
            return false;
          }

          return isRetryableError(error);
        },
        onRetry: (attempt, error) => {
          console.warn(`[API] Retry ${attempt}/${maxRetries} for ${fnName}:`, error);
          markConnectionIssue(error);
        },
      });
    } catch (error) {
      const errorObj = error as Record<string, unknown>;
      const message = String(errorObj?.message || '').toLowerCase();
      if (
        message.includes('timeout') ||
        message.includes('network') ||
        message.includes('fetch') ||
        message.includes('connection')
      ) {
        connectionState.setOnline(false, message);
      }
      throw error;
    } finally {
      inflightRequests.delete(dedupeKey);
    }
  })();

  if (dedupe) {
    inflightRequests.set(dedupeKey, promise);
  }

  return promise;
}

// === PING / HEALTH CHECK ===

/**
 * Ping the API to check if the server is responding
 * Uses a lightweight query with short timeout
 */
export async function pingApi(): Promise<{ success: boolean; latency: number }> {
  const startTime = Date.now();
  try {
    // Use a simple query with short timeout (5 seconds)
    const queryPromise = Promise.resolve(supabase.from('players').select('id').limit(1).single());
    const result = await withTimeout(queryPromise, 5000, 'ping');

    const latency = Date.now() - startTime;

    // PGRST116 = no rows returned, which is ok for ping
    if (result.error && result.error.code !== 'PGRST116') {
      connectionState.setOnline(false, result.error.message);
      return { success: false, latency };
    }

    // Connection successful
    if (!connectionState.isOnline) {
      connectionState.setOnline(true);
    }

    return { success: true, latency };
  } catch (error) {
    const latency = Date.now() - startTime;
    const message = error instanceof Error ? error.message : 'Unknown error';
    connectionState.setOnline(false, message);
    return { success: false, latency };
  }
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

/**
 * Update player heartbeat to keep them online
 * Lightweight function that only updates last_seen and is_online
 * Called periodically and when tab regains focus
 */
export async function updatePlayerHeartbeat(playerId: string): Promise<boolean> {
  try {
    const { data, error } = await supabase.rpc('update_player_heartbeat', {
      p_player_id: playerId,
    });

    if (error) {
      // AbortError is expected when tab loses/regains focus — silently ignore
      if (error.message?.includes('AbortError')) return false;
      console.warn('Heartbeat failed:', error.message);
      return false;
    }

    return data === true;
  } catch (error: unknown) {
    // AbortError from fetch when tab transitions — silently ignore
    if (error instanceof DOMException && error.name === 'AbortError') return false;
    console.warn('Heartbeat error:', error);
    return false;
  }
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

export async function applyRigPatch(playerId: string, rigId: string) {
  const { data, error } = await supabase.rpc('apply_rig_patch', {
    p_player_id: playerId,
    p_rig_id: rigId,
  });

  if (error) throw error;
  return data;
}

export async function buyRigPatch(playerId: string) {
  const { data, error } = await supabase.rpc('buy_rig_patch', {
    p_player_id: playerId,
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

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function getPlayerTransactions(playerId: string, limit = 50): Promise<any> {
  return rpcWithRetry('get_player_transactions', {
    p_player_id: playerId,
    p_limit: limit,
  });
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

// Obtener bloques recientes con info de shares (nuevo sistema)
export async function getRecentMiningBlocks(playerId: string, limit = 10): Promise<any> {
  return rpcWithRetry('get_recent_mining_blocks', {
    p_player_id: playerId,
    p_limit: limit
  });
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
  return rpcWithRetry('get_mining_estimate', {
    p_player_id: playerId,
  }) as Promise<MiningEstimate>;
}

// Procesar tick de minería (normalmente llamado por cron/scheduler)
export async function processMiningTick() {
  const { data, error } = await supabase.rpc('process_mining_tick');

  if (error) throw error;
  return data;
}

// === MARKET ===

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function getOrderBook(itemType: string): Promise<any> {
  return rpcWithRetry('get_order_book', {
    p_item_type: itemType,
  });
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

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function getPlayerOrders(playerId: string): Promise<any> {
  return rpcWithRetry('get_player_orders', {
    p_player_id: playerId,
  });
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function getPlayerTrades(playerId: string, limit = 50): Promise<any> {
  return rpcWithRetry('get_player_trades', {
    p_player_id: playerId,
    p_limit: limit,
  });
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function getMarketStats(): Promise<any> {
  return rpcWithRetry('get_market_stats');
}

// === LEADERBOARD ===

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function getReputationLeaderboard(limit = 100): Promise<any> {
  return rpcWithRetry('get_reputation_leaderboard', {
    p_limit: limit,
  });
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function getMiningLeaderboard(limit = 100): Promise<any> {
  return rpcWithRetry('get_mining_leaderboard', {
    p_limit: limit,
  });
}

// === COOLING (REFRIGERACIÓN) ===

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function getCoolingItems(): Promise<any> {
  return rpcWithRetry('get_cooling_items');
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function getPlayerCooling(playerId: string): Promise<any> {
  return rpcWithRetry('get_player_cooling', {
    p_player_id: playerId,
  });
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

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function getPrepaidCards(): Promise<any> {
  return rpcWithRetry('get_prepaid_cards');
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function getPlayerCards(playerId: string): Promise<any> {
  return rpcWithRetry('get_player_cards', {
    p_player_id: playerId,
  });
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

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function deleteInventoryItem(playerId: string, itemType: string, itemId: string, quantity: number = 1): Promise<any> {
  const { data, error } = await supabase.rpc('delete_inventory_item', {
    p_player_id: playerId,
    p_item_type: itemType,
    p_item_id: itemId,
    p_quantity: quantity,
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
export async function installCoolingToRig(playerId: string, rigId: string, coolingId: string, playerCoolingItemId?: string) {
  const params: Record<string, unknown> = {
    p_player_id: playerId,
    p_rig_id: rigId,
    p_cooling_id: coolingId,
  };
  if (playerCoolingItemId) {
    params.p_player_cooling_item_id = playerCoolingItemId;
  }
  const { data, error } = await supabase.rpc('install_cooling_to_rig', params);

  if (error) throw error;
  return data;
}

// Obtener cooling instalado en un rig
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function getRigCooling(rigId: string): Promise<any> {
  return rpcWithRetry('get_rig_cooling', {
    p_rig_id: rigId,
  });
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

// =====================================================
// COOLING MODDING SYSTEM
// =====================================================

// Obtener todos los componentes de cooling (para el Market)
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function getCoolingComponents(): Promise<any> {
  return rpcWithRetry('get_cooling_components', {});
}

// Comprar un componente de cooling
export async function buyCoolingComponent(playerId: string, componentId: string) {
  const { data, error } = await supabase.rpc('buy_cooling_component', {
    p_player_id: playerId,
    p_component_id: componentId,
  });

  if (error) throw error;
  return data;
}

// Obtener componentes del inventario del jugador
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function getCoolingComponentInventory(playerId: string): Promise<any> {
  return rpcWithRetry('get_cooling_component_inventory', {
    p_player_id: playerId,
  });
}

// Obtener cooling items modded del jugador
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function getPlayerCoolingItems(playerId: string): Promise<any> {
  return rpcWithRetry('get_player_cooling_items', {
    p_player_id: playerId,
  });
}

// Instalar un mod (componente) en un cooling item
export async function installCoolingMod(playerId: string, coolingItemId: string, componentId: string, sourceType: 'inventory' | 'modded') {
  const { data, error } = await supabase.rpc('install_cooling_mod', {
    p_player_id: playerId,
    p_cooling_item_id: coolingItemId,
    p_component_id: componentId,
    p_source_type: sourceType,
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
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function getPlayerSlotInfo(playerId: string): Promise<any> {
  return rpcWithRetry('get_player_slot_info', {
    p_player_id: playerId,
  });
}

// Obtener lista de upgrades de slots disponibles
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function getRigSlotUpgrades(): Promise<any> {
  return rpcWithRetry('get_rig_slot_upgrades');
}

// Comprar un slot adicional
export async function buyRigSlot(playerId: string) {
  const { data, error } = await supabase.rpc('buy_rig_slot', {
    p_player_id: playerId,
  });

  if (error) throw error;
  return data;
}

// === SLOT TIER ===

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function upgradeSlotTier(playerId: string, slotId: string): Promise<any> {
  const { data, error } = await supabase.rpc('upgrade_slot_tier', {
    p_player_id: playerId,
    p_slot_id: slotId,
  });
  if (error) throw error;
  return data;
}

// === MATERIALS & FORGE ===

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function getPlayerMaterials(playerId: string): Promise<any> {
  return rpcWithRetry('get_player_materials', {
    p_player_id: playerId,
  });
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function getForgeRecipes(): Promise<any> {
  return rpcWithRetry('get_forge_recipes');
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function forgeCraftItem(
  playerId: string,
  recipeId: string,
  targetSlotId?: string,
  targetRigId?: string
): Promise<any> {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const params: Record<string, any> = {
    p_player_id: playerId,
    p_recipe_id: recipeId,
  };
  if (targetSlotId) params.p_target_slot_id = targetSlotId;
  if (targetRigId) params.p_target_rig_id = targetRigId;

  const { data, error } = await supabase.rpc('forge_craft_item', params);
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

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function getExchangeRates(): Promise<any> {
  return rpcWithRetry('get_exchange_rates');
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function getExchangeRateHistory(limit = 50): Promise<any> {
  return rpcWithRetry('get_exchange_rate_history', { p_limit: limit });
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

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function getBoostItems(): Promise<any> {
  return rpcWithRetry('get_boost_items');
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function getPlayerBoosts(playerId: string): Promise<any> {
  return rpcWithRetry('get_player_boosts', {
    p_player_id: playerId,
  });
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
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function getRigBoosts(rigId: string): Promise<any> {
  return rpcWithRetry('get_rig_boosts', {
    p_rig_id: rigId,
  });
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

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function getRigUpgrades(playerRigId: string): Promise<any> {
  return rpcWithRetry('get_rig_upgrades', {
    p_player_rig_id: playerRigId,
  });
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

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function getActiveAnnouncements(): Promise<any> {
  return rpcWithRetry('get_active_announcements');
}

// Admin: Obtener todos los anuncios
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function adminGetAllAnnouncements(): Promise<any> {
  return rpcWithRetry('admin_get_all_announcements');
}

// Admin: Crear anuncio
export interface CreateAnnouncementParams {
  message: string;
  message_es?: string;
  type?: 'info' | 'warning' | 'success' | 'error' | 'maintenance' | 'update';
  icon?: string;
  link_url?: string;
  link_text?: string;
  is_active?: boolean;
  priority?: number;
  starts_at?: string;
  ends_at?: string;
}

export async function adminCreateAnnouncement(params: CreateAnnouncementParams) {
  return rpcWithRetry('admin_create_announcement', {
    p_message: params.message,
    p_message_es: params.message_es || null,
    p_type: params.type || 'info',
    p_icon: params.icon || '📢',
    p_link_url: params.link_url || null,
    p_link_text: params.link_text || null,
    p_is_active: params.is_active ?? true,
    p_priority: params.priority || 0,
    p_starts_at: params.starts_at || null,
    p_ends_at: params.ends_at || null,
  }, { critical: true });
}

// Admin: Actualizar anuncio
export interface UpdateAnnouncementParams {
  announcement_id: string;
  message?: string;
  message_es?: string;
  type?: 'info' | 'warning' | 'success' | 'error' | 'maintenance' | 'update';
  icon?: string;
  link_url?: string;
  link_text?: string;
  is_active?: boolean;
  priority?: number;
  starts_at?: string;
  ends_at?: string;
}

export async function adminUpdateAnnouncement(params: UpdateAnnouncementParams) {
  return rpcWithRetry('admin_update_announcement', {
    p_announcement_id: params.announcement_id,
    p_message: params.message || null,
    p_message_es: params.message_es || null,
    p_type: params.type || null,
    p_icon: params.icon || null,
    p_link_url: params.link_url || null,
    p_link_text: params.link_text || null,
    p_is_active: params.is_active ?? null,
    p_priority: params.priority ?? null,
    p_starts_at: params.starts_at || null,
    p_ends_at: params.ends_at || null,
  }, { critical: true });
}

// Admin: Eliminar anuncio
export async function adminDeleteAnnouncement(announcementId: string) {
  return rpcWithRetry('admin_delete_announcement', {
    p_announcement_id: announcementId,
  }, { critical: true });
}

// Admin: Crear anuncio de actualización (quick action)
export async function adminCreateUpdateAnnouncement(version: string, message?: string, messageEs?: string) {
  return rpcWithRetry('admin_create_update_announcement', {
    p_version: version,
    p_message: message || null,
    p_message_es: messageEs || null,
  }, { critical: true });
}

// Admin: Enviar regalo
export interface AdminSendGiftParams {
  target: string;           // '@everyone' or player UUID
  title?: string;
  description?: string;
  icon?: string;
  gamecoin?: number;
  crypto?: number;
  energy?: number;
  internet?: number;
  item_type?: string;
  item_id?: string;
  item_quantity?: number;
  expires_at?: string;
}

export async function adminSendGift(params: AdminSendGiftParams) {
  const { data, error } = await supabase.rpc('send_gift', {
    p_target: params.target,
    p_title: params.title || 'Gift',
    p_description: params.description || null,
    p_icon: params.icon || '🎁',
    p_gamecoin: params.gamecoin || 0,
    p_crypto: params.crypto || 0,
    p_energy: params.energy || 0,
    p_internet: params.internet || 0,
    p_item_type: params.item_type || null,
    p_item_id: params.item_id || null,
    p_item_quantity: params.item_quantity || 1,
    p_expires_at: params.expires_at || null,
  });

  if (error) throw error;
  return data;
}

// Admin: Obtener información de usuarios
export async function adminGetPlayers(search?: string, limit = 50, offset = 0) {
  const { data, error } = await supabase.rpc('admin_get_players', {
    p_search: search || null,
    p_limit: limit,
    p_offset: offset,
  });

  if (error) throw error;
  return data;
}

// Admin: Obtener detalle completo de un usuario
export async function adminGetPlayerDetail(playerId: string) {
  const { data, error } = await supabase.rpc('admin_get_player_detail', {
    p_player_id: playerId,
  });

  if (error) throw error;
  return data;
}

// === PENDING BLOCKS (CLAIM SYSTEM) ===

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function getPendingBlocks(playerId: string, limit = 20, offset = 0): Promise<any> {
  // Critical: losing pending blocks means losing rewards
  return rpcWithRetry('get_pending_blocks', {
    p_player_id: playerId,
    p_limit: limit,
    p_offset: offset,
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

export async function requestRonWithdrawal(playerId: string, amount?: number) {
  const { data, error } = await supabase.rpc('request_ron_withdrawal', {
    p_player_id: playerId,
    p_amount: amount ?? null,
  });

  if (error) throw error;
  return data;
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function getWithdrawalHistory(playerId: string, limit: number = 10): Promise<any> {
  return rpcWithRetry('get_withdrawal_history', {
    p_player_id: playerId,
    p_limit: limit,
  });
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

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function getRonDepositHistory(playerId: string, limit: number = 10): Promise<any> {
  return rpcWithRetry('get_ron_deposit_history', {
    p_player_id: playerId,
    p_limit: limit,
  });
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

// Obtener estado del juego (para admins)
export interface GameStatus {
  success: boolean;
  network: {
    difficulty: number;
    hashrate: number;
    activeMiners: number;
    lastUpdate: string;
  };
  players: {
    total: number;
    online: number;
    premium: number;
  };
  rigs: {
    total: number;
    active: number;
  };
  mining: {
    totalBlocks: number;
    blocksToday: number;
    totalCryptoMined: number;
  };
  economy: {
    pendingWithdrawals: number;
    pendingWithdrawalsAmount: number;
    totalRonDeposited: number;
    totalRonBalance: number;
    totalRonSpent: number;
    totalRonWithdrawn: number;
    balance: number;
  };
  timestamp: string;
}

export async function getGameStatus(): Promise<GameStatus | null> {
  const { data, error } = await supabase.rpc('get_game_status');

  if (error) {
    console.error('Error fetching game status:', error);
    return null;
  }
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
  return rpcWithRetry('get_premium_status', {
    p_player_id: playerId,
  }) as Promise<PremiumStatus>;
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
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function getPremiumHistory(playerId: string, limit: number = 10): Promise<any> {
  return rpcWithRetry('get_premium_history', {
    p_player_id: playerId,
    p_limit: limit,
  });
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
  return rpcWithRetry('get_referral_info', {
    p_player_id: playerId,
  }) as Promise<ReferralInfo>;
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
  totalRigs: number;
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
  return rpcWithRetry('get_referral_list', {
    p_player_id: playerId,
    p_limit: limit,
    p_offset: offset,
  }) as Promise<ReferralListResponse>;
}

// === RONIN WALLET PAYMENTS ===

export interface VerifyRoninPaymentResult {
  success: boolean;
  cryptoReceived?: number;
  txVerified?: boolean;
  error?: string;
}

// Verify a Ronin blockchain transaction for crypto package purchase
// === GIFTS (REGALOS) ===

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function getPendingGifts(playerId: string): Promise<any> {
  return rpcWithRetry('get_pending_gifts', {
    p_player_id: playerId,
  });
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function claimGift(playerId: string, giftId: string): Promise<any> {
  return rpcWithRetry('claim_gift', {
    p_player_id: playerId,
    p_gift_id: giftId,
  }, { critical: true, maxRetries: 5 });
}

// === RONIN WALLET PAYMENTS ===

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

// === CRAFTING LORDS ===

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function startCraftingSession(playerId: string): Promise<any> {
  const { data, error } = await supabase.rpc('start_crafting_session', {
    p_player_id: playerId,
  });
  if (error) throw error;
  return data;
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function tapCraftingElement(playerId: string, sessionId: string, cellIndex: number): Promise<any> {
  const { data, error } = await supabase.rpc('tap_crafting_element', {
    p_player_id: playerId,
    p_session_id: sessionId,
    p_cell_index: cellIndex,
  });
  if (error) throw error;
  return data;
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function getCraftingSession(playerId: string): Promise<any> {
  return rpcWithRetry('get_crafting_session', {
    p_player_id: playerId,
  });
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function getCraftingInventory(playerId: string): Promise<any> {
  return rpcWithRetry('get_crafting_inventory', {
    p_player_id: playerId,
  });
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function getCraftingRecipes(): Promise<any> {
  return rpcWithRetry('get_crafting_recipes', {});
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function craftRecipe(playerId: string, recipeId: string): Promise<any> {
  const { data, error } = await supabase.rpc('craft_recipe', {
    p_player_id: playerId,
    p_recipe_id: recipeId,
  });
  if (error) throw error;
  return data;
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function deleteCraftingElement(playerId: string, elementId: string, quantity: number): Promise<any> {
  const { data, error } = await supabase.rpc('delete_crafting_element', {
    p_player_id: playerId,
    p_element_id: elementId,
    p_quantity: quantity,
  });
  if (error) throw error;
  return data;
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function abandonCraftingSession(playerId: string, sessionId: string): Promise<any> {
  const { data, error } = await supabase.rpc('abandon_crafting_session', {
    p_player_id: playerId,
    p_session_id: sessionId,
  });
  if (error) throw error;
  return data;
}

// === CARD BATTLE PVP ===

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function joinBattleLobby(playerId: string): Promise<any> {
  return rpcWithRetry('join_battle_lobby', {
    p_player_id: playerId,
  });
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function leaveBattleLobby(playerId: string): Promise<any> {
  return rpcWithRetry('leave_battle_lobby', {
    p_player_id: playerId,
  });
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function proposeBattleChallenge(
  challengerId: string,
  opponentLobbyId: string,
  betAmount: number,
  betCurrency: 'GC' | 'BLC' | 'RON'
): Promise<any> {
  return rpcWithRetry('propose_battle_challenge', {
    p_challenger_id: challengerId,
    p_opponent_lobby_id: opponentLobbyId,
    p_bet_amount: betAmount,
    p_bet_currency: betCurrency,
  });
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function acceptBattleChallenge(playerId: string, challengerId: string): Promise<any> {
  return rpcWithRetry('accept_battle_challenge', {
    p_player_id: playerId,
    p_challenger_id: challengerId,
  });
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function rejectBattleChallenge(playerId: string, challengerId: string): Promise<any> {
  return rpcWithRetry('reject_battle_challenge', {
    p_player_id: playerId,
    p_challenger_id: challengerId,
  });
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function setPlayerReady(playerId: string): Promise<any> {
  return rpcWithRetry('set_player_ready', {
    p_player_id: playerId,
  });
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function startBattleFromReadyRoom(roomId: string): Promise<any> {
  return rpcWithRetry('start_battle_from_ready_room', {
    p_room_id: roomId,
  });
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function playBattleTurn(playerId: string, sessionId: string, cardsPlayed: string[]): Promise<any> {
  return rpcWithRetry('play_battle_turn', {
    p_player_id: playerId,
    p_session_id: sessionId,
    p_cards_played: cardsPlayed,
  }, { critical: true });
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function forfeitBattle(playerId: string, sessionId: string): Promise<any> {
  return rpcWithRetry('forfeit_battle', {
    p_player_id: playerId,
    p_session_id: sessionId,
  }, { critical: true });
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function getBattleLobby(playerId: string): Promise<any> {
  return rpcWithRetry('get_battle_lobby', {
    p_player_id: playerId,
  });
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function getBattleLeaderboard(limit = 10): Promise<any> {
  return rpcWithRetry('get_battle_leaderboard', {
    p_limit: limit,
  });
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function quickMatchPair(playerId: string, opponentLobbyId: string): Promise<any> {
  return rpcWithRetry('quick_match_pair', {
    p_player_id: playerId,
    p_opponent_lobby_id: opponentLobbyId,
  });
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function selectBattleBet(playerId: string, betAmount: number, betCurrency: 'GC' | 'BLC' | 'RON'): Promise<any> {
  return rpcWithRetry('select_battle_bet', {
    p_player_id: playerId,
    p_bet_amount: betAmount,
    p_bet_currency: betCurrency,
  });
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function cancelBattleReadyRoom(playerId: string): Promise<any> {
  return rpcWithRetry('cancel_battle_ready_room', {
    p_player_id: playerId,
  });
}

// === YIELD PREDICTION ===

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function getPlayerPredictions(playerId: string): Promise<any> {
  return rpcWithRetry('get_player_predictions', {
    p_player_id: playerId,
  });
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function getPredictionPrice(): Promise<any> {
  return rpcWithRetry('get_prediction_price');
}

export async function placePredictionBet(
  playerId: string,
  direction: 'up' | 'down',
  targetPercent: number,
  betAmount: number
) {
  const { data, error } = await supabase.rpc('place_prediction_bet', {
    p_player_id: playerId,
    p_direction: direction,
    p_target_percent: targetPercent,
    p_bet_amount: betAmount,
  });

  if (error) throw error;

  // Trigger RON→USDC hedge for DOWN bets (non-blocking)
  if (data?.success && direction === 'down' && data?.bet_id) {
    supabase.functions.invoke('hedge-swap', {
      body: { action: 'hedge', bet_id: data.bet_id },
    }).catch((err: unknown) => console.warn('Hedge trigger failed (worker will retry):', err));
  }

  return data;
}

export async function cancelPredictionBet(playerId: string, betId: string) {
  const { data, error } = await supabase.rpc('cancel_prediction_bet', {
    p_player_id: playerId,
    p_bet_id: betId,
  });

  if (error) throw error;

  // Trigger USDC→RON unhedge for cancelled DOWN bets (non-blocking)
  if (data?.success && data?.direction === 'down' && data?.hedge_status === 'hedged') {
    supabase.functions.invoke('hedge-swap', {
      body: { action: 'unhedge', bet_id: betId },
    }).catch((err: unknown) => console.warn('Unhedge trigger failed (worker will retry):', err));
  }

  return data;
}

// === MAIL SYSTEM ===

export async function getPlayerInbox(playerId: string): Promise<any> {
  return rpcWithRetry('get_player_inbox', {
    p_player_id: playerId,
  });
}

export async function getPlayerSent(playerId: string): Promise<any> {
  return rpcWithRetry('get_player_sent', {
    p_player_id: playerId,
  });
}

export async function getMailUnreadCount(playerId: string): Promise<any> {
  return rpcWithRetry('get_mail_unread_count', {
    p_player_id: playerId,
  });
}

export async function readMail(playerId: string, mailId: string): Promise<any> {
  return rpcWithRetry('read_mail', {
    p_player_id: playerId,
    p_mail_id: mailId,
  });
}

export async function sendPlayerMail(params: {
  senderId: string;
  recipientUsername: string;
  subject: string;
  body?: string;
  password?: string;
  gamecoin?: number;
  crypto?: number;
  energy?: number;
  internet?: number;
  itemType?: string;
  itemId?: string;
  itemQuantity?: number;
}): Promise<any> {
  const { data, error } = await supabase.rpc('send_player_mail', {
    p_sender_id: params.senderId,
    p_recipient_username: params.recipientUsername,
    p_subject: params.subject,
    p_body: params.body || null,
    p_password: params.password || null,
    p_gamecoin: params.gamecoin || 0,
    p_crypto: params.crypto || 0,
    p_energy: params.energy || 0,
    p_internet: params.internet || 0,
    p_item_type: params.itemType || null,
    p_item_id: params.itemId || null,
    p_item_quantity: params.itemQuantity || 0,
  });
  if (error) throw error;
  return data;
}

export async function claimMailAttachment(playerId: string, mailId: string, password?: string): Promise<any> {
  return rpcWithRetry('claim_mail_attachment', {
    p_player_id: playerId,
    p_mail_id: mailId,
    p_password: password || null,
  }, { critical: true, maxRetries: 5 });
}

export async function deletePlayerMail(playerId: string, mailId: string): Promise<any> {
  const { data, error } = await supabase.rpc('delete_mail', {
    p_player_id: playerId,
    p_mail_id: mailId,
  });
  if (error) throw error;
  return data;
}

export async function getMailStorage(playerId: string): Promise<any> {
  return rpcWithRetry('get_mail_storage', {
    p_player_id: playerId,
  });
}

export async function sendSupportTicket(senderId: string, subject: string, body?: string): Promise<any> {
  return rpcWithRetry('send_support_ticket', {
    p_sender_id: senderId,
    p_subject: subject,
    p_body: body || null,
  }, { critical: true, maxRetries: 3 });
}

export async function adminSendMail(params: {
  target: string;
  subject: string;
  body?: string;
  gamecoin?: number;
  crypto?: number;
  energy?: number;
  internet?: number;
}): Promise<any> {
  return rpcWithRetry('admin_send_mail', {
    p_target: params.target,
    p_subject: params.subject,
    p_body: params.body || null,
    p_gamecoin: params.gamecoin || 0,
    p_crypto: params.crypto || 0,
    p_energy: params.energy || 0,
    p_internet: params.internet || 0,
  }, { critical: true, maxRetries: 3 });
}

export async function adminGetTickets(): Promise<any> {
  return rpcWithRetry('admin_get_tickets', {});
}
