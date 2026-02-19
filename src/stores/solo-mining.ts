import { defineStore } from 'pinia';
import { ref, computed } from 'vue';
import { supabase } from '@/utils/supabase';
import { getSoloMiningStatus, activateSoloMining, deactivateSoloMining, toggleMiningMode } from '@/utils/api';
import { useAuthStore } from './auth';
import { useToastStore } from './toast';
import { useMiningStore } from './mining';
import { playSound } from '@/utils/sounds';
import { isTabLocked } from '@/composables/useTabLock';

// Types
interface SoloRental {
  id: string;
  expires_at: string;
  activated_at: string;
  time_remaining_seconds: number;
}

interface SoloSeed {
  index: number;
  found: boolean;
  seed_number: number | null;
  found_at: string | null;
}

interface SoloBlock {
  id: string;
  block_number: number;
  block_type: 'bronze' | 'silver' | 'gold' | 'diamond';
  total_seeds: number;
  seeds_found: number;
  reward: number;
  started_at: string;
  target_close_at: string;
  time_remaining_seconds: number;
  total_scans: number;
}

interface SoloSessionStats {
  blocks_completed: number;
  blocks_failed: number;
  total_earned: number;
}

interface SoloRecentBlock {
  block_number: number;
  block_type: string;
  total_seeds: number;
  seeds_found: number;
  reward: number;
  status: string;
  started_at: string;
  completed_at: string | null;
  total_scans: number;
}

interface SoloMiningState {
  active: boolean;
  has_rental: boolean;
  mining_mode: 'pool' | 'solo';
  rental: SoloRental | null;
  current_block: SoloBlock | null;
  seeds: SoloSeed[];
  session_stats: SoloSessionStats;
  recent_blocks: SoloRecentBlock[];
}

const STORAGE_KEY = 'lootmine_solo_mining_cache';

function loadFromCache(): SoloMiningState | null {
  try {
    const cached = localStorage.getItem(STORAGE_KEY);
    if (cached) return JSON.parse(cached);
  } catch { /* ignore */ }
  return null;
}

function saveToCache(data: SoloMiningState) {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(data));
  } catch { /* ignore */ }
}

const DEFAULT_STATE: SoloMiningState = {
  active: false,
  has_rental: false,
  mining_mode: 'pool',
  rental: null,
  current_block: null,
  seeds: [],
  session_stats: { blocks_completed: 0, blocks_failed: 0, total_earned: 0 },
  recent_blocks: [],
};

export const useSoloMiningStore = defineStore('soloMining', () => {
  const cached = loadFromCache();

  // State
  const status = ref<SoloMiningState>(cached ?? { ...DEFAULT_STATE });
  const loading = ref(false);
  const activating = ref(false);
  const deactivating = ref(false);

  // Subscriptions & intervals
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let soloChannel: any = null;
  let pollInterval: number | null = null;
  let countdownInterval: number | null = null;

  // Computed
  const isActive = computed(() => status.value.active && status.value.has_rental);
  const miningMode = computed(() => status.value.mining_mode);
  const isSoloMode = computed(() => status.value.mining_mode === 'solo');
  const hasRental = computed(() => status.value.has_rental);
  const currentBlock = computed(() => status.value.current_block);
  const seeds = computed(() => status.value.seeds);
  const seedsFound = computed(() => status.value.seeds.filter(s => s.found).length);
  const seedsTotal = computed(() => status.value.current_block?.total_seeds ?? 0);
  const seedProgress = computed(() =>
    seedsTotal.value > 0 ? (seedsFound.value / seedsTotal.value) * 100 : 0
  );
  const blockType = computed(() => status.value.current_block?.block_type ?? null);
  const blockReward = computed(() => status.value.current_block?.reward ?? 0);
  const blockTimeRemaining = computed(() => status.value.current_block?.time_remaining_seconds ?? 0);
  const rentalTimeRemaining = computed(() => status.value.rental?.time_remaining_seconds ?? 0);
  const sessionStats = computed(() => status.value.session_stats);
  const recentBlocks = computed(() => status.value.recent_blocks);
  const totalScans = computed(() => status.value.current_block?.total_scans ?? 0);

  // Actions
  async function loadStatus() {
    if (isTabLocked.value) return;
    const authStore = useAuthStore();
    if (!authStore.player?.id) return;

    try {
      const raw = await getSoloMiningStatus(authStore.player.id);
      const prevSeedsFound = (status.value.seeds ?? []).filter(s => s.found).length;
      const hadBlock = status.value.current_block !== null;

      // Normalize response - server returns minimal object when no rental
      const data: SoloMiningState = {
        active: raw.active ?? false,
        has_rental: raw.has_rental ?? false,
        mining_mode: raw.mining_mode ?? 'pool',
        rental: raw.rental ?? null,
        current_block: raw.current_block ?? null,
        seeds: raw.seeds ?? [],
        session_stats: raw.session_stats ?? { blocks_completed: 0, blocks_failed: 0, total_earned: 0 },
        recent_blocks: raw.recent_blocks ?? [],
      };

      status.value = data;
      saveToCache(data);

      // Detectar seed encontrado
      const newSeedsFound = data.seeds?.filter((s: SoloSeed) => s.found).length ?? 0;
      if (newSeedsFound > prevSeedsFound && prevSeedsFound > 0) {
        const toastStore = useToastStore();
        playSound('collect');
        toastStore.info(`Seed encontrado! ${newSeedsFound}/${data.current_block?.total_seeds ?? '?'}`, '🔑');
      }

      // Detectar bloque completado
      if (hadBlock && data.current_block?.block_number !== status.value.current_block?.block_number) {
        const lastCompleted = data.recent_blocks?.find((b: SoloRecentBlock) => b.status === 'completed');
        if (lastCompleted) {
          playSound('collect');
          const toastStore = useToastStore();
          toastStore.info(`Bloque ${lastCompleted.block_type.toUpperCase()} completado! +${lastCompleted.reward.toLocaleString()} crypto`, '💎');
        }
      }

      // Detectar bloque fallido
      const lastFailed = data.recent_blocks?.[0];
      if (hadBlock && lastFailed?.status === 'failed' && data.current_block?.block_number !== currentBlock.value?.block_number) {
        const toastStore = useToastStore();
        toastStore.error(`Bloque fallido - no encontraste todos los seeds a tiempo`, '⏰');
      }
    } catch (e) {
      console.error('Error loading solo mining status:', e);
    }
  }

  async function activate() {
    const authStore = useAuthStore();
    const toastStore = useToastStore();
    if (!authStore.player?.id) return { success: false };

    activating.value = true;
    try {
      const result = await activateSoloMining(authStore.player.id);
      if (result.success) {
        playSound('collect');
        toastStore.info('Solo Mining activado! Buena suerte, minero.', '⛏️');
        await loadStatus();
        authStore.fetchPlayer();
        const miningStore = useMiningStore();
        await miningStore.loadData();
      } else {
        toastStore.error(result.error || 'Error al activar solo mining', '❌');
      }
      return result;
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : 'Error activando solo mining';
      toastStore.error(msg, '❌');
      return { success: false, error: msg };
    } finally {
      activating.value = false;
    }
  }

  async function deactivate() {
    const authStore = useAuthStore();
    const toastStore = useToastStore();
    if (!authStore.player?.id) return;

    deactivating.value = true;
    try {
      const result = await deactivateSoloMining(authStore.player.id);
      if (result.success) {
        toastStore.info('Solo Mining desactivado. Rigs volvieron al modo pool.', '🔄');
        await loadStatus();
        const miningStore = useMiningStore();
        await miningStore.loadData();
      }
    } catch (e) {
      console.error('Error deactivating:', e);
    } finally {
      deactivating.value = false;
    }
  }

  async function toggleMode(mode: 'pool' | 'solo') {
    const authStore = useAuthStore();
    const toastStore = useToastStore();
    if (!authStore.player?.id) return { success: false };

    try {
      const result = await toggleMiningMode(authStore.player.id, mode);
      if (result.success) {
        status.value.mining_mode = result.mining_mode;
        saveToCache(status.value);
        if (mode === 'solo') {
          await loadStatus();
        }
      } else {
        toastStore.error(result.error || 'Error al cambiar modo', '❌');
      }
      return result;
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : 'Error cambiando modo';
      toastStore.error(msg, '❌');
      return { success: false, error: msg };
    }
  }

  // Realtime + Polling
  function subscribe() {
    const authStore = useAuthStore();
    if (!authStore.player?.id) return;

    // Suscripcion a cambios en bloques solo
    soloChannel = supabase
      .channel(`solo_mining:${authStore.player.id}`)
      .on('postgres_changes', {
        event: '*',
        schema: 'public',
        table: 'solo_mining_blocks',
        filter: `player_id=eq.${authStore.player.id}`,
      }, () => { loadStatus(); })
      .on('postgres_changes', {
        event: 'UPDATE',
        schema: 'public',
        table: 'solo_mining_seeds',
      }, () => { loadStatus(); })
      .subscribe();

    // Polling fallback cada 10 segundos
    pollInterval = window.setInterval(() => {
      if (!isTabLocked.value && status.value.active) loadStatus();
    }, 10000);

    // Countdown cada segundo
    startCountdown();
  }

  function startCountdown() {
    if (countdownInterval) return;
    countdownInterval = window.setInterval(() => {
      // Countdown del bloque activo
      if (status.value.current_block?.time_remaining_seconds) {
        status.value.current_block.time_remaining_seconds = Math.max(0,
          status.value.current_block.time_remaining_seconds - 1);
        if (status.value.current_block.time_remaining_seconds <= 0) {
          loadStatus(); // Refrescar para obtener resultado (completado/fallido)
        }
      }
      // Countdown del alquiler
      if (status.value.rental?.time_remaining_seconds) {
        status.value.rental.time_remaining_seconds = Math.max(0,
          status.value.rental.time_remaining_seconds - 1);
      }
    }, 1000);
  }

  function unsubscribe() {
    if (soloChannel) { supabase.removeChannel(soloChannel); soloChannel = null; }
    if (pollInterval) { clearInterval(pollInterval); pollInterval = null; }
    if (countdownInterval) { clearInterval(countdownInterval); countdownInterval = null; }
  }

  function clearState() {
    unsubscribe();
    status.value = { ...DEFAULT_STATE };
    localStorage.removeItem(STORAGE_KEY);
  }

  return {
    // State
    status, loading, activating, deactivating,
    // Computed
    isActive, miningMode, isSoloMode, hasRental,
    currentBlock, seeds, seedsFound, seedsTotal, seedProgress,
    blockType, blockReward, blockTimeRemaining, rentalTimeRemaining,
    sessionStats, recentBlocks, totalScans,
    // Actions
    loadStatus, activate, deactivate, toggleMode,
    subscribe, unsubscribe, clearState,
  };
});
