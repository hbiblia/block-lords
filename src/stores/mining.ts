import { defineStore } from 'pinia';
import { ref, computed } from 'vue';
import { supabase } from '@/utils/supabase';
import { getPlayerRigs, getNetworkStats, getRecentBlocks, getRigCooling, getPlayerSlotInfo, getPlayerBoosts, toggleRig as apiToggleRig } from '@/utils/api';
import { useAuthStore } from './auth';
import { useNotificationsStore } from './notifications';
import { useToastStore } from './toast';
import { playSound } from '@/utils/sounds';

// Types
interface Rig {
  id: string;
  name: string;
  hashrate: number;
  power_consumption: number;
  internet_consumption: number;
  tier: string;
  repair_cost: number;
}

interface PlayerRig {
  id: string;
  is_active: boolean;
  condition: number;
  temperature: number;
  activated_at: string | null;
  max_condition?: number;
  times_repaired?: number;
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
}

interface CoolingItem {
  id: string;
  durability: number;
  name: string;
  cooling_power: number;
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

export const useMiningStore = defineStore('mining', () => {
  // State
  const rigs = ref<PlayerRig[]>([]);
  const networkStats = ref<NetworkStats>({
    difficulty: 1000,
    hashrate: 0,
    latestBlock: null,
    activeMiners: 0,
  });
  const recentBlocks = ref<Block[]>([]);
  const rigCooling = ref<Record<string, CoolingItem[]>>({});
  const activeBoosts = ref<ActiveBoost[]>([]);
  const slotInfo = ref<SlotInfo | null>(null);

  // Loading states
  const loading = ref(true);
  const togglingRig = ref<string | null>(null);

  // Realtime channel
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let rigsChannel: any = null;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let coolingChannel: any = null;

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
      .reduce((sum, r) => {
        const temp = r.temperature ?? 25;
        const condition = r.condition ?? 100;
        let tempPenalty = 1;
        if (temp > 60) {
          tempPenalty = Math.max(0.5, 1 - ((temp - 60) * 0.0125));
        }
        return sum + (r.rig.hashrate * (condition / 100) * tempPenalty);
      }, 0)
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
  function getRigEffectiveHashrate(rig: PlayerRig): number {
    const temp = rig.temperature ?? 25;
    const condition = rig.condition ?? 100;
    let tempPenalty = 1;
    if (temp > 60) {
      tempPenalty = Math.max(0.5, 1 - ((temp - 60) * 0.0125));
    }
    return rig.rig.hashrate * (condition / 100) * tempPenalty;
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

      // Load cooling and boosts in background
      loadRigsCooling();
      loadActiveBoosts();
    } catch (e) {
      console.error('Error loading mining data:', e);
    } finally {
      loading.value = false;
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
  function handleRigUpdate(payload: { eventType: string; new: any; old: any }) {
    const { eventType, new: newData } = payload;

    if (eventType === 'INSERT' || eventType === 'DELETE') {
      loadData();
      return;
    }

    if (eventType === 'UPDATE' && newData) {
      const rigIndex = rigs.value.findIndex(r => r.id === newData.id);
      if (rigIndex !== -1) {
        const currentRig = rigs.value[rigIndex];
        rigs.value[rigIndex] = {
          ...currentRig,
          is_active: newData.is_active ?? currentRig.is_active,
          condition: newData.condition ?? currentRig.condition,
          temperature: newData.temperature ?? currentRig.temperature,
          activated_at: newData.activated_at ?? currentRig.activated_at,
        };
      }
    }
  }

  // Debounce for cooling updates
  let coolingDebounceTimer: number | null = null;

  function handleCoolingUpdate() {
    if (coolingDebounceTimer) {
      clearTimeout(coolingDebounceTimer);
    }
    coolingDebounceTimer = window.setTimeout(() => {
      loadRigsCooling();
      coolingDebounceTimer = null;
    }, 500);
  }

  function handleBlockMined(block: any, winner: any) {
    const authStore = useAuthStore();
    const toastStore = useToastStore();

    recentBlocks.value.unshift({
      ...block,
      miner: winner,
    });
    recentBlocks.value = recentBlocks.value.slice(0, 5);

    if (winner?.id === authStore.player?.id) {
      playSound('block_mined');
      authStore.fetchPlayer();
      // Show toast with reward
      const reward = block.reward ?? 0.0001;
      toastStore.blockMined(reward, true);
    }
  }

  // Toggle rig
  async function toggleRig(rigId: string) {
    const authStore = useAuthStore();
    const notificationsStore = useNotificationsStore();

    if (!authStore.player) return { success: false, error: 'No player' };

    const rig = rigs.value.find(r => r.id === rigId);
    if (!rig) return { success: false, error: 'Rig not found' };

    // Pre-check resources if turning ON
    if (!rig.is_active) {
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
        notificationsStore.addNotification({
          type: 'rig_broken',
          title: 'common.error',
          message: 'mining.toggleError',
          icon: '⚠️',
          severity: 'error',
          data: { error: result.error },
        });
        return result;
      }

      if (!rig.is_active) {
        // Was turning OFF
        playSound('click');
      } else {
        playSound('success');
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
    if (coolingDebounceTimer) {
      clearTimeout(coolingDebounceTimer);
      coolingDebounceTimer = null;
    }
  }

  function clearState() {
    rigs.value = [];
    networkStats.value = {
      difficulty: 1000,
      hashrate: 0,
      latestBlock: null,
      activeMiners: 0,
    };
    recentBlocks.value = [];
    rigCooling.value = {};
    activeBoosts.value = [];
    slotInfo.value = null;
    loading.value = true;
  }

  return {
    // State
    rigs,
    networkStats,
    recentBlocks,
    rigCooling,
    activeBoosts,
    slotInfo,
    loading,
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

    // Cooling helpers
    getCoolingEfficiency,
    getCoolingEfficiencyPercent,
    isCoolingDegraded,

    // Actions
    loadData,
    loadRigsCooling,
    loadActiveBoosts,
    toggleRig,
    handleBlockMined,

    // Realtime
    subscribeToRealtime,
    unsubscribeFromRealtime,
    clearState,
  };
});
