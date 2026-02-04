import { defineStore } from 'pinia';
import { ref, computed } from 'vue';
import { supabase } from '@/utils/supabase';
import { getPlayerRigs, getNetworkStats, getRecentBlocks, getRigCooling, getRigBoosts, getPlayerSlotInfo, getPlayerBoosts, toggleRig as apiToggleRig } from '@/utils/api';
import { useAuthStore } from './auth';
import { useNotificationsStore } from './notifications';
import { useToastStore } from './toast';
import { playSound } from '@/utils/sounds';
import { i18n } from '@/plugins/i18n';

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
  rig: Rig;
}

interface NetworkStats {
  difficulty: number;
  hashrate: number;
  latestBlock: any;
  activeMiners: number;
}

interface Block {
  id: string;
  height: number;
  created_at: string;
  miner_id: string;
  miner?: {
    id: string;
    username: string;
  };
  reward?: number;
  is_premium?: boolean;
}

// Calculate block reward based on height (mirrors database calculate_block_reward function)
function calculateBlockReward(blockHeight: number): number {
  const BASE_REWARD = 100;
  const HALVING_INTERVAL = 10000;
  const halvings = Math.floor(blockHeight / HALVING_INTERVAL);
  return BASE_REWARD / Math.pow(2, halvings);
}

interface CoolingItem {
  id: string;
  durability: number;
  name: string;
  cooling_power: number;
  energy_cost: number;
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

interface SlotInfo {
  current_slots: number;
  used_slots: number;
  available_slots: number;
  max_slots: number;
  next_upgrade: {
    slot_number: number;
    price: number;
    currency: string;
    name: string;
    description: string;
  } | null;
}

// LocalStorage cache
const STORAGE_KEY = 'blocklords_mining_cache';

// Default data for new accounts
const DEFAULT_NETWORK_STATS: NetworkStats = {
  difficulty: 1000,
  hashrate: 50000,
  latestBlock: null,
  activeMiners: 25,
};

const DEFAULT_SLOT_INFO: SlotInfo = {
  current_slots: 1,
  used_slots: 0,
  available_slots: 1,
  max_slots: 10,
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

  // Realtime channels
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let rigsChannel: any = null;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let coolingChannel: any = null;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let boostsChannel: any = null;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let networkStatsChannel: any = null;

  // Computed
  const activeRigsCount = computed(() => rigs.value.filter(r => r.is_active).length);

  const isMining = computed(() => activeRigsCount.value > 0);

  const totalHashrate = computed(() =>
    rigs.value
      .filter(r => r.is_active)
      .reduce((sum, r) => sum + r.rig.hashrate, 0)
  );

  const effectiveHashrate = computed(() =>
    rigs.value
      .filter(r => r.is_active)
      .reduce((sum, r) => sum + getRigEffectiveHashrate(r), 0)
  );

  const totalEnergyConsumption = computed(() =>
    rigs.value
      .filter(r => r.is_active)
      .reduce((sum, r) => sum + r.rig.power_consumption, 0)
  );

  const totalInternetConsumption = computed(() =>
    rigs.value
      .filter(r => r.is_active)
      .reduce((sum, r) => sum + r.rig.internet_consumption, 0)
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

  function getRigEffectiveHashrate(rig: PlayerRig): number {
    const temp = rig.temperature ?? 25;
    const condition = rig.condition ?? 100;
    let tempPenalty = 1;
    if (temp > 60) {
      tempPenalty = Math.max(0.5, 1 - ((temp - 60) * 0.0125));
    }
    // Apply boost multiplier
    const boostMultiplier = getRigBoostMultiplier(rig.id, 'hashrate');
    return rig.rig.hashrate * (condition / 100) * tempPenalty * boostMultiplier;
  }

  function getRigHashrateBoostPercent(rig: PlayerRig): number {
    const boostMultiplier = getRigBoostMultiplier(rig.id, 'hashrate');
    return Math.round((boostMultiplier - 1) * 100);
  }

  function getRigPenaltyPercent(rig: PlayerRig): number {
    const effective = getRigEffectiveHashrate(rig);
    const base = rig.rig.hashrate;
    if (base === 0) return 0;
    return Math.round(((base - effective) / base) * 100);
  }

  function getRigEffectivePower(rig: PlayerRig): number {
    const temp = rig.temperature ?? 25;
    const tempPenalty = 1 + Math.max(0, (temp - 40)) * 0.0083;
    return rig.rig.power_consumption * tempPenalty;
  }

  function getPowerPenaltyPercent(rig: PlayerRig): number {
    const effective = getRigEffectivePower(rig);
    const base = rig.rig.power_consumption;
    if (base === 0) return 0;
    return Math.round(((effective - base) / base) * 100);
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
        getRecentBlocks(5),
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

      dataLoaded.value = true;
    } catch (e) {
      console.error('Error loading mining data:', e);
    } finally {
      loading.value = false;
      refreshing.value = false;
    }
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
  }

  // Reload just the rigs data (used when boosts expire to update stats)
  async function reloadRigs() {
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

  // Realtime handlers
  // Debounce for network stats refresh (when rigs toggle)
  let networkStatsDebounceTimer: number | null = null;

  function handleRigUpdate(payload: { eventType: string; new: any; old: any }) {
    const { eventType, new: newData, old: oldData } = payload;

    if (eventType === 'INSERT' || eventType === 'DELETE') {
      loadData();
      return;
    }

    if (eventType === 'UPDATE' && newData) {
      const rigIndex = rigs.value.findIndex(r => r.id === newData.id);
      if (rigIndex !== -1) {
        const currentRig = rigs.value[rigIndex];
        // Use splice to ensure Vue reactivity triggers
        rigs.value.splice(rigIndex, 1, {
          ...currentRig,
          is_active: newData.is_active ?? currentRig.is_active,
          condition: newData.condition ?? currentRig.condition,
          temperature: newData.temperature ?? currentRig.temperature,
          activated_at: newData.activated_at ?? currentRig.activated_at,
          max_condition: newData.max_condition ?? currentRig.max_condition,
          times_repaired: newData.times_repaired ?? currentRig.times_repaired,
        });

        // If is_active changed, refresh network stats (activeMiners count)
        if (oldData && newData.is_active !== oldData.is_active) {
          refreshNetworkStats();
        }
      }
    }
  }

  // Debounced refresh of network stats
  function refreshNetworkStats() {
    if (networkStatsDebounceTimer) {
      clearTimeout(networkStatsDebounceTimer);
    }
    networkStatsDebounceTimer = window.setTimeout(async () => {
      try {
        const freshStats = await getNetworkStats();
        networkStats.value = freshStats;
      } catch (e) {
        console.warn('Error refreshing network stats:', e);
      }
      networkStatsDebounceTimer = null;
    }, 1000);
  }

  // Debounce for cooling updates
  let coolingDebounceTimer: number | null = null;

  function handleCoolingUpdate() {
    if (coolingDebounceTimer) {
      clearTimeout(coolingDebounceTimer);
    }
    coolingDebounceTimer = window.setTimeout(async () => {
      const toastStore = useToastStore();
      // Save old cooling to detect expired ones
      const oldCooling = { ...rigCooling.value };

      await loadRigsCooling();

      // Detect expired cooling (was present before, not present now or durability = 0)
      for (const rigId of Object.keys(oldCooling)) {
        const oldItems = oldCooling[rigId] || [];
        const newItems = rigCooling.value[rigId] || [];
        const rig = rigs.value.find(r => r.id === rigId);
        const rigName = rig?.rig?.name || 'Rig';

        for (const oldItem of oldItems) {
          const stillExists = newItems.find(n => n.id === oldItem.id);
          if (!stillExists && oldItem.durability <= 1) {
            toastStore.boostExpired(oldItem.name, rigName);
          }
        }
      }

      coolingDebounceTimer = null;
    }, 500);
  }

  // Debounce for boosts updates
  let boostsDebounceTimer: number | null = null;

  function handleBoostsUpdate() {
    if (boostsDebounceTimer) {
      clearTimeout(boostsDebounceTimer);
    }
    boostsDebounceTimer = window.setTimeout(async () => {
      const toastStore = useToastStore();
      // Save old boosts to detect expired ones
      const oldBoosts = { ...rigBoosts.value };

      await loadRigsBoosts();
      // Also reload rigs to update stats when boosts change/expire
      await reloadRigs();

      // Detect expired boosts (was present before, not present now)
      for (const rigId of Object.keys(oldBoosts)) {
        const oldItems = oldBoosts[rigId] || [];
        const newItems = rigBoosts.value[rigId] || [];
        const rig = rigs.value.find(r => r.id === rigId);
        const rigName = rig?.rig?.name || 'Rig';

        for (const oldItem of oldItems) {
          const stillExists = newItems.find(n => n.id === oldItem.id);
          if (!stillExists && oldItem.remaining_seconds <= 60) {
            toastStore.boostExpired(oldItem.name, rigName);
          }
        }
      }

      boostsDebounceTimer = null;
    }, 500);
  }

  async function handleBlockMined(block: any, winner: any) {
    const authStore = useAuthStore();
    const toastStore = useToastStore();

    // Calculate reward with premium bonus if applicable (only for current user)
    const baseReward = calculateBlockReward(block.height);
    const isOwnBlock = winner?.id === authStore.player?.id;
    const isPremiumBlock = isOwnBlock && authStore.isPremium;
    const reward = isPremiumBlock ? baseReward * 1.5 : baseReward;

    // Add block to recent list (with deduplication)
    // Note: For other users' blocks, is_premium will be undefined until data is refreshed from server
    const alreadyExists = recentBlocks.value.some(
      b => b.id === block.id || b.height === block.height
    );

    if (!alreadyExists) {
      recentBlocks.value.unshift({
        ...block,
        miner: winner,
        reward: isOwnBlock ? reward : undefined, // Only set reward for own blocks where we know premium status
        is_premium: isOwnBlock ? isPremiumBlock : undefined,
      });
      recentBlocks.value = recentBlocks.value.slice(0, 5);
    }

    // Update latestBlock in networkStats
    networkStats.value = {
      ...networkStats.value,
      latestBlock: {
        height: block.height,
        hash: block.hash,
        created_at: block.created_at,
        miner: winner,
      },
    };

    // Refresh full network stats to get updated activeMiners count
    try {
      const freshStats = await getNetworkStats();
      networkStats.value = freshStats;
    } catch (e) {
      console.warn('Error refreshing network stats:', e);
    }

    if (winner?.id === authStore.player?.id) {
      playSound('block_mined');
      authStore.fetchPlayer();
      // Show toast with actual reward from database (already includes premium bonus)
      // Fall back to calculated reward only if block.reward is not available
      const reward = block.reward ?? calculateBlockReward(block.height) * (authStore.isPremium ? 1.5 : 1);
      toastStore.blockMined(reward, true);
    }
  }

  // Toggle rig
  async function toggleRig(rigId: string) {
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
      const result = await apiToggleRig(authStore.player.id, rigId);

      if (!result.success) {
        await loadData();
        playSound('error');
        toastStore.error(result.error || i18n.global.t('toast.rigToggleError'), '⚠️');
        return result;
      }

      // Show toast notification for rig toggle
      if (wasTurningOn) {
        playSound('success');
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

  // Subscribe to realtime
  function subscribeToRealtime() {
    const authStore = useAuthStore();
    if (!authStore.player?.id) return;

    const playerId = authStore.player.id;

    // Subscribe to player_rigs changes
    rigsChannel = supabase
      .channel(`mining_rigs:${playerId}`)
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'player_rigs',
          filter: `player_id=eq.${playerId}`,
        },
        (payload) => {
          handleRigUpdate(payload as any);
        }
      )
      .subscribe();

    // Subscribe to rig_cooling changes
    coolingChannel = supabase
      .channel(`mining_cooling:${playerId}`)
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'rig_cooling',
        },
        () => {
          handleCoolingUpdate();
        }
      )
      .subscribe();

    // Subscribe to rig_boosts changes
    boostsChannel = supabase
      .channel(`mining_boosts:${playerId}`)
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'rig_boosts',
        },
        () => {
          handleBoostsUpdate();
        }
      )
      .subscribe();

    // Subscribe to network_stats changes (global)
    // Note: network_stats table only has difficulty and hashrate columns
    // latestBlock comes from block-mined events, activeMiners from player_rigs
    networkStatsChannel = supabase
      .channel('mining_network_stats')
      .on(
        'postgres_changes',
        {
          event: 'UPDATE',
          schema: 'public',
          table: 'network_stats',
        },
        (payload) => {
          const newStats = payload.new as any;
          networkStats.value = {
            ...networkStats.value,
            difficulty: newStats.difficulty ?? networkStats.value.difficulty,
            hashrate: newStats.hashrate ?? networkStats.value.hashrate,
            activeMiners: newStats.active_miners ?? networkStats.value.activeMiners,
          };
        }
      )
      .subscribe();
  }

  function unsubscribeFromRealtime() {
    if (rigsChannel) {
      supabase.removeChannel(rigsChannel);
      rigsChannel = null;
    }
    if (coolingChannel) {
      supabase.removeChannel(coolingChannel);
      coolingChannel = null;
    }
    if (boostsChannel) {
      supabase.removeChannel(boostsChannel);
      boostsChannel = null;
    }
    if (networkStatsChannel) {
      supabase.removeChannel(networkStatsChannel);
      networkStatsChannel = null;
    }
    if (coolingDebounceTimer) {
      clearTimeout(coolingDebounceTimer);
      coolingDebounceTimer = null;
    }
    if (boostsDebounceTimer) {
      clearTimeout(boostsDebounceTimer);
      boostsDebounceTimer = null;
    }
    if (networkStatsDebounceTimer) {
      clearTimeout(networkStatsDebounceTimer);
      networkStatsDebounceTimer = null;
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
  }

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
    totalEnergyConsumption,
    totalInternetConsumption,
    miningChance,

    // Rig helpers
    getRigEffectiveHashrate,
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
    loadRigsCooling,
    loadRigsBoosts,
    loadActiveBoosts,
    reloadRigs,
    toggleRig,
    handleBlockMined,

    // Realtime
    subscribeToRealtime,
    unsubscribeFromRealtime,
    clearState,
  };
});
