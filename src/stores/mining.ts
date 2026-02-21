import { defineStore } from 'pinia';
import { ref, computed, watch } from 'vue';
import { supabase } from '@/utils/supabase';
import { getPlayerRigs, getNetworkStats, getRecentMiningBlocks, getRigCooling, getRigBoosts, getPlayerSlotInfo, getPlayerBoosts, toggleRig as apiToggleRig, getPendingBlocks } from '@/utils/api';
import { useAuthStore } from './auth';
import { useNotificationsStore } from './notifications';
import { useToastStore } from './toast';
import { playSound } from '@/utils/sounds';
import { i18n } from '@/plugins/i18n';
import { isTabLocked } from '@/composables/useTabLock';

// Types
interface Rig {
  id: string;
  name: string;
  hashrate: number;
  power_consumption: number;
  internet_consumption: number;
  tier: string;
  repair_cost: number;
  base_price: number;
  currency: 'gamecoin' | 'crypto' | 'ron';
  max_upgrade_level?: number;
}

interface PlayerRig {
  id: string;
  is_active: boolean;
  condition: number;
  temperature: number;
  activated_at: string | null;
  max_condition?: number;
  times_repaired?: number;
  hashrate_level?: number;
  efficiency_level?: number;
  thermal_level?: number;
  hashrate_bonus?: number;
  efficiency_bonus?: number;
  thermal_bonus?: number;
  patch_count?: number;
  mining_mode?: 'pool' | 'solo';
  rig: Rig;
}

interface NetworkStats {
  difficulty: number;
  hashrate: number;
  latestBlock: any;
  activeMiners: number;
  onlinePlayers: number;
}

interface Block {
  id: string;
  height: number;
  block_number?: number; // Para bloques del nuevo sistema
  created_at: string;
  miner_id?: string; // Opcional para bloques del nuevo sistema
  miner?: {
    id: string;
    username: string;
  };
  reward?: number;
  is_premium?: boolean;
  // Nuevo sistema de shares
  total_shares?: number;
  total_distributed?: number;
  premium_bonus?: number;
  contributors_count?: number;
  top_contributor?: {
    username: string;
    percentage: number;
    shares: number;
  };
  player_participation?: {
    participated: boolean;
    shares: number;
    percentage: number;
    reward: number;
    is_premium: boolean;
  };
}

interface CoolingItem {
  id: string;
  durability: number;
  name: string;
  cooling_power: number;
  energy_cost: number;
  // Modding system
  player_cooling_item_id?: string;
  mods?: Array<{ component_id: string; slot: number; cooling_power_mod: number; energy_cost_mod: number; durability_mod: number }>;
  mod_slots_used?: number;
  max_mod_slots?: number;
  effective_cooling_power?: number;
  effective_energy_cost?: number;
  total_durability_mod?: number;
}

interface ActiveBoost {
  id: string;
  boost_id: string;
  boost_type: string;
  name: string;
  effect_value: number;
  expires_at: string;
  seconds_remaining: number;
}

interface RigBoost {
  id: string;
  boost_item_id: string;
  remaining_seconds: number;
  stack_count: number;
  name: string;
  boost_type: string;
  effect_value: number;
  secondary_value: number;
  tier: string;
}

interface SlotData {
  id: string;
  slot_number: number;
  max_uses: number;
  uses_remaining: number;
  is_destroyed: boolean;
  has_rig: boolean;
  player_rig_id: string | null;
  rig_name: string | null;
  tier: string;
  xp: number;
}

interface SlotInfo {
  current_slots: number;
  used_slots: number;
  available_slots: number;
  max_slots: number;
  slots: SlotData[];
  next_upgrade: {
    slot_number: number;
    price: number;
    currency: string;
    name: string;
    description: string;
  } | null;
}

// Interfaces para sistema de shares
interface MiningBlockInfo {
  active: boolean;
  block_number: number;
  started_at: string;
  target_close_at: string;
  time_remaining_seconds: number;
  total_shares: number;
  target_shares: number;
  progress_percent: number;
  reward: number;
  difficulty: number;
  block_type?: string;
}

interface PlayerSharesInfo {
  has_shares: boolean;
  shares: number;
  total_shares: number;
  share_percentage: number;
  estimated_reward: number;
  mining_block_id: string;
}

// LocalStorage cache
const STORAGE_KEY = 'lootmine_mining_cache';

// Default data for new accounts
const DEFAULT_NETWORK_STATS: NetworkStats = {
  difficulty: 1000,
  hashrate: 50000,
  latestBlock: null,
  activeMiners: 25,
  onlinePlayers: 0,
};

const DEFAULT_SLOT_INFO: SlotInfo = {
  current_slots: 1,
  used_slots: 0,
  available_slots: 1,
  max_slots: 10,
  slots: [],
  next_upgrade: {
    slot_number: 2,
    price: 1000,
    currency: 'gamecoin',
    name: 'Slot 2',
    description: 'Unlock your second rig slot',
  },
};

function loadFromCache(): { rigs: PlayerRig[]; networkStats: NetworkStats; slotInfo: SlotInfo | null } | null {
  try {
    const cached = localStorage.getItem(STORAGE_KEY);
    if (cached) {
      return JSON.parse(cached);
    }
  } catch (e) {
    console.error('Error loading mining cache:', e);
  }
  return null;
}

function saveToCache(data: { rigs: PlayerRig[]; networkStats: NetworkStats; slotInfo: SlotInfo | null }) {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(data));
  } catch (e) {
    console.error('Error saving mining cache:', e);
  }
}

export const useMiningStore = defineStore('mining', () => {
  // Load from cache on init
  const cached = loadFromCache();

  // State - use cached data if available, otherwise use defaults
  const rigs = ref<PlayerRig[]>(cached?.rigs ?? []);
  const networkStats = ref<NetworkStats>(cached?.networkStats ?? DEFAULT_NETWORK_STATS);
  const recentBlocks = ref<Block[]>([]);
  const rigCooling = ref<Record<string, CoolingItem[]>>({});
  const rigBoosts = ref<Record<string, RigBoost[]>>({});
  const activeBoosts = ref<ActiveBoost[]>([]);
  const slotInfo = ref<SlotInfo | null>(cached?.slotInfo ?? DEFAULT_SLOT_INFO);

  // Loading states - always have defaults, so show content immediately
  const loading = ref(false);
  const dataLoaded = ref(true); // Always true since we have defaults
  const refreshing = ref(false);
  const togglingRig = ref<string | null>(null);


  // Computed
  const activeRigsCount = computed(() => rigs.value.filter(r => r.is_active).length);

  const isMining = computed(() => activeRigsCount.value > 0);

  const totalHashrate = computed(() =>
    rigs.value
      .filter(r => r.is_active && (r.mining_mode ?? 'pool') === 'pool')
      .reduce((sum, r) => sum + r.rig.hashrate, 0)
  );

  const effectiveHashrate = computed(() => {
    // eslint-disable-next-line @typescript-eslint/no-unused-expressions
    warmupTick.value; // dependency to force recompute during warm-up
    return rigs.value
      .filter(r => r.is_active && (r.mining_mode ?? 'pool') === 'pool')
      .reduce((sum, r) => sum + getRigEffectiveHashrate(r), 0);
  });

  const soloEffectiveHashrate = computed(() => {
    // eslint-disable-next-line @typescript-eslint/no-unused-expressions
    warmupTick.value;
    return rigs.value
      .filter(r => r.is_active && r.mining_mode === 'solo')
      .reduce((sum, r) => sum + getRigEffectiveHashrate(r), 0);
  });

  const totalEnergyConsumption = computed(() =>
    rigs.value
      .filter(r => r.is_active)
      .reduce((sum, r) => sum + getRigEffectivePower(r), 0)
  );

  const totalInternetConsumption = computed(() =>
    rigs.value
      .filter(r => r.is_active)
      .reduce((sum, r) => {
        const efficiencyBonus = r.efficiency_bonus ?? 0;
        const patchMult = Math.pow(1.15, r.patch_count ?? 0);
        return sum + r.rig.internet_consumption * (1 - efficiencyBonus / 100) * patchMult;
      }, 0)
  );

  const miningChance = computed(() => {
    if (networkStats.value.hashrate === 0) return 0;
    return (effectiveHashrate.value / networkStats.value.hashrate) * 100;
  });

  // Rig helpers
  function getRigBoostMultiplier(rigId: string, boostType: string): number {
    const boosts = rigBoosts.value[rigId] ?? [];
    let multiplier = 1;
    for (const boost of boosts) {
      if (boost.boost_type === boostType) {
        multiplier += boost.effect_value / 100;
      }
      // Overclock also adds hashrate
      if (boostType === 'hashrate' && boost.boost_type === 'overclock') {
        multiplier += boost.effect_value / 100;
      }
    }
    return multiplier;
  }

  function getRigWarmupMultiplier(rig: PlayerRig): number {
    if (!rig.activated_at) return 1;
    const elapsedSec = (Date.now() - new Date(rig.activated_at).getTime()) / 1000;
    // +20% por tick (30s): 20% → 40% → 60% → 80% → 100% en 120s
    return Math.max(0, Math.min(1, (1 + Math.floor(elapsedSec / 30)) * 0.20));
  }

  function getRigEffectiveHashrate(rig: PlayerRig): number {
    const temp = rig.temperature ?? 25;
    const condition = rig.condition ?? 100;
    // Temperature penalty: matches backend (>50°C threshold)
    let tempPenalty = 1;
    if (temp > 50) {
      tempPenalty = Math.max(0.3, 1 - ((temp - 50) * 0.014));
    }
    // Condition penalty: no penalty >= 80%, gradual below
    const conditionPenalty = condition >= 80 ? 1.0 : 0.3 + (condition / 80) * 0.7;
    // Apply boost multiplier + hashrate upgrade bonus
    let boostMultiplier = getRigBoostMultiplier(rig.id, 'hashrate');
    const hashrateBonus = rig.hashrate_bonus ?? 0;
    boostMultiplier *= (1 + hashrateBonus / 100);
    // Warm-up: 0% → 100% en 5 minutos tras encender
    const warmup = getRigWarmupMultiplier(rig);
    // Patch penalty: -10% hashrate per patch (multiplicative)
    const patchPenalty = Math.pow(0.90, rig.patch_count ?? 0);
    return rig.rig.hashrate * conditionPenalty * tempPenalty * boostMultiplier * warmup * patchPenalty;
  }

  function getRigHashrateBoostPercent(rig: PlayerRig): number {
    const boostMultiplier = getRigBoostMultiplier(rig.id, 'hashrate');
    return Math.round((boostMultiplier - 1) * 100);
  }

  function getRigPenaltyPercent(rig: PlayerRig): number {
    const effective = getRigEffectiveHashrate(rig);
    // Compare against theoretical max (upgrades + boosts, no condition/temp penalties)
    const hashrateBonus = rig.hashrate_bonus ?? 0;
    const boostMult = getRigBoostMultiplier(rig.id, 'hashrate');
    const theoreticalMax = rig.rig.hashrate * (1 + hashrateBonus / 100) * boostMult;
    if (theoreticalMax === 0) return 0;
    return Math.max(0, Math.round(((theoreticalMax - effective) / theoreticalMax) * 100));
  }

  function getRigEffectivePower(rig: PlayerRig): number {
    const temp = rig.temperature ?? 25;
    const tempPenalty = 1 + Math.max(0, (temp - 40)) * 0.0083;
    // Apply efficiency upgrade bonus (reduces consumption)
    const efficiencyBonus = rig.efficiency_bonus ?? 0;
    // Patch penalty: +15% consumption per patch (multiplicative)
    const patchMult = Math.pow(1.15, rig.patch_count ?? 0);
    return rig.rig.power_consumption * tempPenalty * (1 - efficiencyBonus / 100) * patchMult;
  }

  function getPowerPenaltyPercent(rig: PlayerRig): number {
    const effective = getRigEffectivePower(rig);
    // Compare against efficiency-adjusted base to show temperature penalty only
    const efficiencyBonus = rig.efficiency_bonus ?? 0;
    const adjustedBase = rig.rig.power_consumption * (1 - efficiencyBonus / 100);
    if (adjustedBase === 0) return 0;
    return Math.round(((effective - adjustedBase) / adjustedBase) * 100);
  }

  // Cooling efficiency based on durability
  // >= 50%: linear efficiency (durability/100)
  // < 50%: additional penalty (durability/100 * durability/50)
  function getCoolingEfficiency(durability: number): number {
    if (durability >= 50) {
      return durability / 100;
    }
    return (durability / 100) * (durability / 50);
  }

  function getCoolingEfficiencyPercent(durability: number): number {
    return Math.round(getCoolingEfficiency(durability) * 100);
  }

  function isCoolingDegraded(durability: number): boolean {
    return durability < 50;
  }

  // Warm-up tick: forces reactive recomputation of effectiveHashrate
  // while any rig is in warm-up phase (< 120s since activated_at)
  const warmupTick = ref(0);
  let warmupInterval: number | null = null;
  const WARMUP_DURATION_SEC = 120; // 5 ticks × 30s = 120s, matches backend

  function startWarmupTick() {
    if (warmupInterval) return;
    warmupInterval = window.setInterval(() => {
      const hasWarmingRig = rigs.value.some(r => {
        if (!r.is_active || !r.activated_at) return false;
        const elapsed = (Date.now() - new Date(r.activated_at).getTime()) / 1000;
        return elapsed < WARMUP_DURATION_SEC;
      });
      if (hasWarmingRig) {
        warmupTick.value++;
      } else {
        stopWarmupTick();
      }
    }, 1000);
  }

  function stopWarmupTick() {
    if (warmupInterval) {
      clearInterval(warmupInterval);
      warmupInterval = null;
    }
  }

  // Boost countdown tick: interpolates remaining_seconds between server updates
  let boostCountdownInterval: number | null = null;

  function startBoostCountdown() {
    if (boostCountdownInterval) return;
    boostCountdownInterval = window.setInterval(() => {
      let hasActiveBoosts = false;
      for (const rigId of Object.keys(rigBoosts.value)) {
        const rig = rigs.value.find(r => r.id === rigId);
        if (!rig?.is_active) continue; // Only count down when rig is mining

        const boosts = rigBoosts.value[rigId];
        if (boosts && boosts.length > 0) {
          hasActiveBoosts = true;
          rigBoosts.value[rigId] = boosts
            .map(b => ({ ...b, remaining_seconds: Math.max(0, b.remaining_seconds - 1) }))
            .filter(b => b.remaining_seconds > 0);
        }
      }
      if (!hasActiveBoosts) {
        stopBoostCountdown();
      }
    }, 1000);
  }

  function stopBoostCountdown() {
    if (boostCountdownInterval) {
      clearInterval(boostCountdownInterval);
      boostCountdownInterval = null;
    }
  }

  // Actions
  async function loadData() {
    const authStore = useAuthStore();
    if (!authStore.player?.id) return;

    // Si ya se cargó antes, marcar como refreshing (muestra datos en cache)
    if (dataLoaded.value) {
      refreshing.value = true;
    }

    try {
      const [rigsData, networkData, blocksData, slotData] = await Promise.all([
        getPlayerRigs(authStore.player.id),
        getNetworkStats(),
        getRecentMiningBlocks(authStore.player.id, 10),
        getPlayerSlotInfo(authStore.player.id),
      ]);

      rigs.value = rigsData ?? [];
      networkStats.value = networkData;
      recentBlocks.value = blocksData ?? [];
      if (slotData?.success) {
        slotInfo.value = slotData;
      }

      // Save to localStorage cache
      saveToCache({
        rigs: rigs.value,
        networkStats: networkStats.value,
        slotInfo: slotInfo.value,
      });

      // Load cooling and boosts in background
      loadRigsCooling();
      loadRigsBoosts();
      loadActiveBoosts();

      // Start warm-up tick if any rig is still warming up
      const hasWarmingRig = rigs.value.some(r => {
        if (!r.is_active || !r.activated_at) return false;
        return (Date.now() - new Date(r.activated_at).getTime()) / 1000 < WARMUP_DURATION_SEC;
      });
      if (hasWarmingRig) startWarmupTick();

      dataLoaded.value = true;
    } catch (e) {
      console.error('Error loading mining data:', e);
    } finally {
      loading.value = false;
      refreshing.value = false;
    }
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  function applyTickData(data: {
    rigs: any[];
    networkStats: any;
    rigCooling: Record<string, CoolingItem[]>;
    rigBoosts: Record<string, RigBoost[]>;
    recentBlocks: Block[];
    currentMiningBlock: MiningBlockInfo | null;
    playerShares: PlayerSharesInfo | null;
  }) {
    rigs.value = data.rigs ?? [];
    networkStats.value = data.networkStats;
    rigCooling.value = data.rigCooling;
    rigBoosts.value = data.rigBoosts;
    recentBlocks.value = data.recentBlocks ?? [];
    currentMiningBlock.value = data.currentMiningBlock;
    playerShares.value = data.playerShares;

    // Save to localStorage cache
    saveToCache({
      rigs: rigs.value,
      networkStats: networkStats.value,
      slotInfo: slotInfo.value,
    });

    // Manage warmup tick
    const hasWarmingRig = rigs.value.some(r => {
      if (!r.is_active || !r.activated_at) return false;
      return (Date.now() - new Date(r.activated_at).getTime()) / 1000 < WARMUP_DURATION_SEC;
    });
    if (hasWarmingRig) startWarmupTick(); else stopWarmupTick();

    // Manage boost countdown
    const hasBoosts = Object.values(data.rigBoosts).some(b => b.length > 0);
    if (hasBoosts) startBoostCountdown(); else stopBoostCountdown();

    if (!dataLoaded.value) dataLoaded.value = true;
  }

  async function loadRigsCooling() {
    const coolingPromises = rigs.value.map(async (rig) => {
      try {
        const cooling = await getRigCooling(rig.id);
        return { rigId: rig.id, cooling: cooling ?? [] };
      } catch {
        return { rigId: rig.id, cooling: [] };
      }
    });

    const results = await Promise.all(coolingPromises);
    const coolingMap: Record<string, CoolingItem[]> = {};
    results.forEach(({ rigId, cooling }) => {
      coolingMap[rigId] = cooling;
    });
    rigCooling.value = coolingMap;
  }

  async function loadRigsBoosts() {
    const boostPromises = rigs.value.map(async (rig) => {
      try {
        const boosts = await getRigBoosts(rig.id);
        return { rigId: rig.id, boosts: boosts ?? [] };
      } catch {
        return { rigId: rig.id, boosts: [] };
      }
    });

    const results = await Promise.all(boostPromises);
    const boostsMap: Record<string, RigBoost[]> = {};
    results.forEach(({ rigId, boosts }) => {
      boostsMap[rigId] = boosts;
    });
    rigBoosts.value = boostsMap;

    // Start local countdown for boost timers
    const hasAny = Object.values(boostsMap).some(b => b.length > 0);
    if (hasAny) {
      startBoostCountdown();
    } else {
      stopBoostCountdown();
    }
  }

  // Reload just the rigs data (used when boosts expire and for periodic refresh)
  async function reloadRigs() {
    if (isTabLocked.value) return;
    const authStore = useAuthStore();
    if (!authStore.player?.id) return;

    try {
      const rigsData = await getPlayerRigs(authStore.player.id);
      rigs.value = rigsData ?? [];
    } catch (e) {
      console.error('Error reloading rigs:', e);
    }
  }

  async function loadActiveBoosts() {
    const authStore = useAuthStore();
    if (!authStore.player?.id) return;

    try {
      const boostData = await getPlayerBoosts(authStore.player.id);
      activeBoosts.value = boostData.active || [];
    } catch (e) {
      console.error('Error loading active boosts:', e);
    }
  }


  // Toggle rig
  async function toggleRig(rigId: string, miningMode: string = 'pool') {
    const authStore = useAuthStore();
    const notificationsStore = useNotificationsStore();
    const toastStore = useToastStore();

    if (!authStore.player) return { success: false, error: 'No player' };

    const rig = rigs.value.find(r => r.id === rigId);
    if (!rig) return { success: false, error: 'Rig not found' };

    // Save original state to know what action we're doing
    const wasTurningOn = !rig.is_active;

    // Pre-check resources if turning ON
    if (wasTurningOn) {
      if (authStore.player.energy < rig.rig.power_consumption) {
        notificationsStore.addNotification({
          type: 'energy_depleted',
          title: 'notifications.energyDepleted.title',
          message: 'notifications.energyDepleted.message',
          icon: '⚡',
          severity: 'error',
        });
        return { success: false, error: 'Insufficient energy' };
      }
      if (authStore.player.internet < rig.rig.internet_consumption) {
        notificationsStore.addNotification({
          type: 'internet_depleted',
          title: 'notifications.internetDepleted.title',
          message: 'notifications.internetDepleted.message',
          icon: '📡',
          severity: 'error',
        });
        return { success: false, error: 'Insufficient internet' };
      }

      // Optimistic update for turning ON
      rig.is_active = true;
      playSound('click');
    }

    togglingRig.value = rigId;

    try {
      const result = await apiToggleRig(authStore.player.id, rigId, miningMode);

      if (!result.success) {
        await loadData();
        playSound('error');
        toastStore.error(result.error || i18n.global.t('toast.rigToggleError'), '⚠️');
        return result;
      }

      // Show toast notification for rig toggle
      if (wasTurningOn) {
        playSound('success');
        startWarmupTick();
        // Check for quick toggle penalty
        if (result.quickTogglePenalty && result.temperature) {
          toastStore.quickTogglePenalty(result.temperature);
        } else {
          toastStore.rigToggled(rig.rig.id, true);
        }
      } else {
        playSound('click');
        toastStore.rigToggled(rig.rig.id, false);
      }

      return result;
    } catch (e) {
      await loadData();
      playSound('error');
      console.error('Error toggling rig:', e);
      return { success: false, error: 'Connection error' };
    } finally {
      togglingRig.value = null;
    }
  }


  function clearState() {
    rigs.value = [];
    networkStats.value = DEFAULT_NETWORK_STATS;
    recentBlocks.value = [];
    rigCooling.value = {};
    rigBoosts.value = {};
    activeBoosts.value = [];
    slotInfo.value = DEFAULT_SLOT_INFO;
    loading.value = false;
    dataLoaded.value = true;
    refreshing.value = false;
    stopBoostCountdown();
    currentMiningBlock.value = null;
    playerShares.value = null;
    stopWarmupTick();
  }

  // ===== NUEVO SISTEMA DE SHARES =====

  const currentMiningBlock = ref<MiningBlockInfo | null>(null);
  const playerShares = ref<PlayerSharesInfo | null>(null);

  async function loadRecentBlocks() {
    const authStore = useAuthStore();
    if (!authStore.player?.id) return;
    try {
      const blocksData = await getRecentMiningBlocks(authStore.player.id, 10);
      recentBlocks.value = blocksData ?? [];
    } catch (e) {
      console.error('Error loading recent blocks:', e);
    }
  }

  async function loadMiningBlockInfo() {
    if (isTabLocked.value) return;
    try {
      const wasActive = currentMiningBlock.value?.active;
      const prevBlockNumber = currentMiningBlock.value?.block_number;
      const { data, error } = await supabase.rpc('get_current_mining_block_info');
      if (error) throw error;
      currentMiningBlock.value = data;

      // Block just closed (was active, now inactive or different block number)
      if (wasActive && (!data?.active || data?.block_number !== prevBlockNumber)) {
        loadRecentBlocks();
        loadPlayerShares();

        // Fetch latest pending block and trigger reward animation (only if player contributed)
        const authStore = useAuthStore();
        if (authStore.player?.id && playerShares.value?.has_shares) {
          try {
            const pending = await getPendingBlocks(authStore.player.id, 1, 0);
            const latest = pending?.blocks?.[0];
            if (latest) {
              window.dispatchEvent(
                new CustomEvent('pending-block-created', {
                  detail: {
                    id: latest.id,
                    block_id: latest.block_id,
                    reward: latest.reward,
                    is_premium: latest.is_premium,
                    materials_dropped: latest.materials_dropped || [],
                    created_at: latest.created_at,
                  },
                })
              );
            }
          } catch (e) {
            // Non-critical: animation is nice-to-have
          }
        }
      }
    } catch (e: any) {
      if (e?.name !== 'AbortError' && !e?.message?.includes('AbortError')) console.error('Error loading mining block info:', e);
    }
  }

  async function loadPlayerShares() {
    if (isTabLocked.value) return;
    const authStore = useAuthStore();
    if (!authStore.player?.id) return;

    try {
      const { data, error } = await supabase.rpc('get_player_shares_info', {
        p_player_id: authStore.player.id
      });
      if (error) throw error;
      playerShares.value = data;
    } catch (e: any) {
      if (e?.name !== 'AbortError') console.error('Error loading player shares:', e);
    }
  }

  // Computed properties
  const blockTimeRemaining = computed(() => {
    if (!currentMiningBlock.value?.active) return '0:00';
    const seconds = currentMiningBlock.value.time_remaining_seconds;
    const minutes = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${minutes}:${secs.toString().padStart(2, '0')}`;
  });

  const sharesProgress = computed(() => {
    if (!currentMiningBlock.value?.active) return 0;
    return Math.min(100, currentMiningBlock.value.progress_percent);
  });

  const playerSharePercentage = computed(() => {
    if (!playerShares.value?.has_shares) return 0;
    // Recalculate locally using latest block data (updates every second)
    const totalShares = currentMiningBlock.value?.total_shares;
    if (totalShares && totalShares > 0) {
      return (playerShares.value.shares / totalShares) * 100;
    }
    return playerShares.value.share_percentage;
  });

  const estimatedReward = computed(() => {
    if (!playerShares.value?.has_shares) return 0;
    // Recalculate locally: player % of block reward (updates every second via block info)
    const blockReward = currentMiningBlock.value?.reward;
    if (blockReward && playerSharePercentage.value > 0) {
      return blockReward * (playerSharePercentage.value / 100);
    }
    return playerShares.value.estimated_reward;
  });

  // Tracking para calcular rate de shares
  const previousShares = ref(0);
  const lastSharesUpdate = ref(Date.now());

  // Rate de generación de shares (shares/minuto)
  const sharesRate = computed(() => {
    if (!playerShares.value?.has_shares || playerShares.value.shares === 0) return 0;

    const currentShares = playerShares.value.shares;
    const timeDiff = (Date.now() - lastSharesUpdate.value) / 1000 / 60; // en minutos

    if (timeDiff === 0 || currentShares === previousShares.value) return 0;

    const sharesDiff = currentShares - previousShares.value;
    return Math.max(0, sharesDiff / timeDiff);
  });

  // Eficiencia vs esperado (basado en hashrate y dificultad)
  const sharesEfficiency = computed(() => {
    if (!currentMiningBlock.value?.active || effectiveHashrate.value === 0) return 0;

    const difficulty = currentMiningBlock.value.difficulty;
    // Expected rate: (hashrate / difficulty) * 60 segundos * (30 segundos tick / 60) = (hashrate / difficulty) * 30
    // Pero como el tick es cada 30 segundos, la probabilidad por minuto es: (hashrate / difficulty) * 0.5 * 2 = (hashrate / difficulty)
    const expectedRate = (effectiveHashrate.value / difficulty) * 0.5; // shares por tick de 30 seg
    const expectedRatePerMinute = expectedRate * 2; // 2 ticks por minuto

    if (expectedRatePerMinute === 0 || sharesRate.value === 0) return 100;

    return Math.round((sharesRate.value / expectedRatePerMinute) * 100);
  });

  // Proyección de recompensa si mantienes el rate actual
  const projectedReward = computed(() => {
    if (!currentMiningBlock.value?.active || !playerShares.value?.has_shares || sharesRate.value === 0) {
      return estimatedReward.value;
    }

    const timeRemainingMinutes = currentMiningBlock.value.time_remaining_seconds / 60;
    const projectedAdditionalShares = sharesRate.value * timeRemainingMinutes;
    const projectedTotalShares = playerShares.value.shares + projectedAdditionalShares;

    // Asumiendo que el total de shares del bloque también crece
    const currentBlockShares = currentMiningBlock.value.total_shares;
    const otherMinersShares = currentBlockShares - playerShares.value.shares;
    const projectedBlockTotal = projectedTotalShares + otherMinersShares;

    if (projectedBlockTotal === 0) return estimatedReward.value;

    const projectedPercentage = (projectedTotalShares / projectedBlockTotal) * 100;
    const projectedRewardValue = currentMiningBlock.value.reward * (projectedPercentage / 100);

    return projectedRewardValue;
  });

  // Alerta de tiempo (para cambiar colores del countdown)
  const timeRemainingAlert = computed(() => {
    if (!currentMiningBlock.value?.active) return 'normal';
    const seconds = currentMiningBlock.value.time_remaining_seconds;
    if (seconds <= 120) return 'critical'; // Últimos 2 minutos
    if (seconds <= 300) return 'warning'; // Últimos 5 minutos
    return 'normal';
  });

  // Watch para actualizar previousShares cuando cambian las shares
  watch(() => playerShares.value?.shares, (newShares, oldShares) => {
    if (newShares !== oldShares && oldShares !== undefined) {
      previousShares.value = oldShares;
      lastSharesUpdate.value = Date.now();
    }
  });


  return {
    // State
    rigs,
    networkStats,
    recentBlocks,
    rigCooling,
    rigBoosts,
    activeBoosts,
    slotInfo,
    loading,
    dataLoaded,
    refreshing,
    togglingRig,

    // Computed
    activeRigsCount,
    isMining,
    totalHashrate,
    effectiveHashrate,
    soloEffectiveHashrate,
    totalEnergyConsumption,
    totalInternetConsumption,
    miningChance,

    // Rig helpers
    getRigEffectiveHashrate,
    getRigWarmupMultiplier,
    getRigPenaltyPercent,
    getRigEffectivePower,
    getPowerPenaltyPercent,
    getRigHashrateBoostPercent,

    // Cooling helpers
    getCoolingEfficiency,
    getCoolingEfficiencyPercent,
    isCoolingDegraded,

    // Actions
    loadData,
    applyTickData,
    loadRigsCooling,
    loadRigsBoosts,
    loadActiveBoosts,
    reloadRigs,
    toggleRig,
    clearState,

    // Nuevo sistema de shares
    currentMiningBlock,
    playerShares,
    blockTimeRemaining,
    sharesProgress,
    playerSharePercentage,
    estimatedReward,
    sharesRate,
    sharesEfficiency,
    projectedReward,
    timeRemainingAlert,
    loadMiningBlockInfo,
    loadPlayerShares,
    loadRecentBlocks,
  };
});
