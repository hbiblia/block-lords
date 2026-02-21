import { defineStore } from 'pinia';
import { ref, computed } from 'vue';
import { supabase } from '@/utils/supabase';
import { useAuthStore } from './auth';
import { useMiningStore } from './mining';
import { useSoloMiningStore } from './solo-mining';
import { usePendingBlocksStore } from './pendingBlocks';
import { useToastStore } from './toast';
import { isTabLocked } from '@/composables/useTabLock';
import {
  getPlayerRigs,
  getNetworkStats,
  getRecentMiningBlocks,
  getSoloMiningStatus,
  getPendingBlocksCount,
  getRigCooling,
  getRigBoosts,
  updatePlayerHeartbeat,
} from '@/utils/api';

const TICK_INTERVAL = 30000; // 30s — matches backend game_tick

export const useGameTickStore = defineStore('gameTick', () => {
  // Tick state
  const tickCount = ref(0);
  const lastTickAt = ref(0);
  const tickRunning = ref(false);
  const tickError = ref<string | null>(null);

  // Intervals
  let mainTickInterval: number | null = null;
  let secondTickInterval: number | null = null;
  let visibilityHandler: (() => void) | null = null;

  // Snapshot tracking for diff detection
  const previousPendingCount = ref(0);
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const previousCoolingSnapshot = ref<Record<string, any[]>>({});
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const previousBoostsSnapshot = ref<Record<string, any[]>>({});

  const isHealthy = computed(() =>
    !tickError.value && lastTickAt.value > 0 && (Date.now() - lastTickAt.value) < 60000
  );

  // === Core tick: fetch all mining data ===
  async function executeTick() {
    if (isTabLocked.value) return;
    if (tickRunning.value) return; // prevent overlap

    const authStore = useAuthStore();
    if (!authStore.player?.id) return;

    tickRunning.value = true;
    tickError.value = null;
    const playerId = authStore.player.id;

    try {
      // Parallel fetch of all tick data
      const [rigsData, networkData, recentBlocksData, soloData, pendingCount, resourcesData] =
        await Promise.all([
          getPlayerRigs(playerId),
          getNetworkStats(),
          getRecentMiningBlocks(playerId, 10),
          getSoloMiningStatus(playerId).catch(() => null),
          getPendingBlocksCount(playerId).catch(() => null),
          supabase.from('players').select('energy, internet').eq('id', playerId).single(),
        ]);

      // Per-rig cooling + boosts (parallel)
      const rigs = rigsData ?? [];
      const rigCooling: Record<string, any[]> = {};
      const rigBoosts: Record<string, any[]> = {};
      await Promise.all(
        rigs.map(async (rig: any) => {
          const [cooling, boosts] = await Promise.all([
            getRigCooling(rig.id).catch(() => []),
            getRigBoosts(rig.id).catch(() => []),
          ]);
          rigCooling[rig.id] = cooling ?? [];
          rigBoosts[rig.id] = boosts ?? [];
        })
      );

      // Mining block info + player shares (parallel)
      const [blockInfoRes, sharesRes] = await Promise.all([
        Promise.resolve(supabase.rpc('get_current_mining_block_info')).catch(() => ({ data: null })),
        Promise.resolve(supabase.rpc('get_player_shares_info', { p_player_id: playerId })).catch(() => ({ data: null })),
      ]);

      // Save snapshots BEFORE applying (for diff detection)
      const prevPendingCount = previousPendingCount.value;
      const prevCooling = { ...previousCoolingSnapshot.value };
      const prevBoosts = { ...previousBoostsSnapshot.value };

      // 1. Update energy/internet (with notification checks via updatePlayer)
      if (!resourcesData.error && resourcesData.data) {
        authStore.updatePlayer({
          energy: resourcesData.data.energy,
          internet: resourcesData.data.internet,
        });
      }

      // 2. Apply mining data
      const miningStore = useMiningStore();
      miningStore.applyTickData({
        rigs,
        networkStats: networkData,
        rigCooling,
        rigBoosts,
        recentBlocks: recentBlocksData ?? [],
        currentMiningBlock: blockInfoRes?.data ?? null,
        playerShares: sharesRes?.data ?? null,
      });

      // 3. Apply solo mining data
      if (soloData) {
        const soloStore = useSoloMiningStore();
        soloStore.applyTickData(soloData);
      }

      // 4. Diff: pending blocks (new block reward?)
      const newPendingCount = pendingCount?.count ?? pendingCount ?? 0;
      if (newPendingCount > prevPendingCount && prevPendingCount >= 0 && tickCount.value > 0) {
        // New pending block detected — trigger reward celebration
        const pendingStore = usePendingBlocksStore();
        pendingStore.fetchPendingBlocks();
        window.dispatchEvent(new CustomEvent('pending-block-created', { detail: {} }));
      }
      previousPendingCount.value = typeof newPendingCount === 'number' ? newPendingCount : 0;

      // 5. Diff: cooling expiry
      detectCoolingExpiry(prevCooling, rigCooling, rigs);
      previousCoolingSnapshot.value = rigCooling;

      // 6. Diff: boost expiry
      detectBoostExpiry(prevBoosts, rigBoosts, rigs);
      previousBoostsSnapshot.value = rigBoosts;

      // 7. Heartbeat (mark player online)
      updatePlayerHeartbeat(playerId).catch(() => {});

      lastTickAt.value = Date.now();
      tickCount.value++;
    } catch (e) {
      console.error('Game tick error:', e);
      tickError.value = e instanceof Error ? e.message : 'Tick error';
    } finally {
      tickRunning.value = false;
    }
  }

  // === Client-side 1s interpolation (no API calls) ===
  function clientSecondTick() {
    const miningStore = useMiningStore();
    const soloStore = useSoloMiningStore();

    // Decrement mining block time
    if (miningStore.currentMiningBlock?.active && miningStore.currentMiningBlock.time_remaining_seconds > 0) {
      miningStore.currentMiningBlock.time_remaining_seconds = Math.max(
        0, miningStore.currentMiningBlock.time_remaining_seconds - 1
      );
    }

    // Solo mining countdowns
    if (soloStore.status.current_block?.time_remaining_seconds) {
      soloStore.status.current_block.time_remaining_seconds = Math.max(
        0, soloStore.status.current_block.time_remaining_seconds - 1
      );
      // Block expired — force tick to get result
      if (soloStore.status.current_block.time_remaining_seconds <= 0) {
        executeTick();
      }
    }
    if (soloStore.status.rental?.time_remaining_seconds) {
      soloStore.status.rental.time_remaining_seconds = Math.max(
        0, soloStore.status.rental.time_remaining_seconds - 1
      );
    }
  }

  // === Diff detection helpers ===
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  function detectCoolingExpiry(oldCooling: Record<string, any[]>, newCooling: Record<string, any[]>, rigs: any[]) {
    if (tickCount.value === 0) return; // skip first tick
    const toastStore = useToastStore();
    for (const rigId of Object.keys(oldCooling)) {
      const oldItems = oldCooling[rigId] || [];
      const newItems = newCooling[rigId] || [];
      const rig = rigs.find((r: any) => r.id === rigId);
      const rigName = rig?.rig?.name || 'Rig';

      for (const oldItem of oldItems) {
        const stillExists = newItems.find((n: any) => n.id === oldItem.id);
        if (!stillExists && oldItem.durability <= 5) {
          toastStore.warning(`${oldItem.cooling_item_id || 'Cooling'} agotado en ${rigName}`, '❄️');
        }
      }
    }
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  function detectBoostExpiry(oldBoosts: Record<string, any[]>, newBoosts: Record<string, any[]>, rigs: any[]) {
    if (tickCount.value === 0) return; // skip first tick
    const toastStore = useToastStore();
    for (const rigId of Object.keys(oldBoosts)) {
      const oldItems = oldBoosts[rigId] || [];
      const newItems = newBoosts[rigId] || [];
      const rig = rigs.find((r: any) => r.id === rigId);
      const rigName = rig?.rig?.name || 'Rig';

      for (const oldItem of oldItems) {
        const stillExists = newItems.find((n: any) => n.id === oldItem.id);
        if (!stillExists && oldItem.remaining_seconds <= 60) {
          toastStore.warning(`Boost ${oldItem.name || ''} expirado en ${rigName}`, '⚡');
        }
      }
    }
  }

  // === Lifecycle ===
  function start() {
    stop(); // cleanup any existing
    executeTick(); // immediate first tick
    mainTickInterval = window.setInterval(executeTick, TICK_INTERVAL);
    secondTickInterval = window.setInterval(clientSecondTick, 1000);

    // Immediate tick on tab return
    visibilityHandler = () => {
      if (document.visibilityState === 'visible' && !isTabLocked.value) {
        executeTick();
      }
    };
    document.addEventListener('visibilitychange', visibilityHandler);
  }

  function stop() {
    if (mainTickInterval) { clearInterval(mainTickInterval); mainTickInterval = null; }
    if (secondTickInterval) { clearInterval(secondTickInterval); secondTickInterval = null; }
    if (visibilityHandler) {
      document.removeEventListener('visibilitychange', visibilityHandler);
      visibilityHandler = null;
    }
    tickCount.value = 0;
    lastTickAt.value = 0;
    previousPendingCount.value = 0;
    previousCoolingSnapshot.value = {};
    previousBoostsSnapshot.value = {};
  }

  return {
    tickCount,
    lastTickAt,
    tickRunning,
    tickError,
    isHealthy,
    start,
    stop,
    executeTick,
  };
});
