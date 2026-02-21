import { defineStore } from 'pinia';
import { ref, computed } from 'vue';
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

interface SoloConfig {
  pool_size: number;
  scan_divisor: number;
  block_time_minutes: number;
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
  config: SoloConfig;
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

const DEFAULT_CONFIG: SoloConfig = { pool_size: 10000, scan_divisor: 100, block_time_minutes: 30 };

const DEFAULT_STATE: SoloMiningState = {
  active: false,
  has_rental: false,
  mining_mode: 'pool',
  rental: null,
  current_block: null,
  seeds: [],
  session_stats: { blocks_completed: 0, blocks_failed: 0, total_earned: 0 },
  recent_blocks: [],
  config: { ...DEFAULT_CONFIG },
};

export const useSoloMiningStore = defineStore('soloMining', () => {
  const cached = loadFromCache();

  // State
  const status = ref<SoloMiningState>(cached ?? { ...DEFAULT_STATE });
  const loading = ref(false);
  const activating = ref(false);
  const deactivating = ref(false);


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
  const config = computed(() => status.value.config ?? DEFAULT_CONFIG);

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
        config: raw.config ?? status.value.config ?? { ...DEFAULT_CONFIG },
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

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  function applyTickData(raw: any) {
    if (!raw) return;

    const prevSeedsFound = (status.value.seeds ?? []).filter(s => s.found).length;
    const hadBlock = status.value.current_block !== null;
    const prevBlockNumber = status.value.current_block?.block_number;

    const data: SoloMiningState = {
      active: raw.active ?? false,
      has_rental: raw.has_rental ?? false,
      mining_mode: raw.mining_mode ?? 'pool',
      rental: raw.rental ?? null,
      current_block: raw.current_block ?? null,
      seeds: raw.seeds ?? [],
      session_stats: raw.session_stats ?? { blocks_completed: 0, blocks_failed: 0, total_earned: 0 },
      recent_blocks: raw.recent_blocks ?? [],
      config: raw.config ?? status.value.config ?? { ...DEFAULT_CONFIG },
    };

    status.value = data;
    saveToCache(data);

    // Detect seed found
    const newSeedsFound = data.seeds?.filter((s: SoloSeed) => s.found).length ?? 0;
    if (newSeedsFound > prevSeedsFound && prevSeedsFound > 0) {
      const toastStore = useToastStore();
      playSound('collect');
      toastStore.info(`Seed encontrado! ${newSeedsFound}/${data.current_block?.total_seeds ?? '?'}`, '🔑');
    }

    // Detect block completed
    if (hadBlock && data.current_block?.block_number !== prevBlockNumber) {
      const lastCompleted = data.recent_blocks?.find((b: SoloRecentBlock) => b.status === 'completed');
      if (lastCompleted) {
        playSound('collect');
        const toastStore = useToastStore();
        toastStore.info(`Bloque ${lastCompleted.block_type.toUpperCase()} completado! +${lastCompleted.reward.toLocaleString()} crypto`, '💎');
      }
    }

    // Detect block failed
    const lastFailed = data.recent_blocks?.[0];
    if (hadBlock && lastFailed?.status === 'failed' && data.current_block?.block_number !== prevBlockNumber) {
      const toastStore = useToastStore();
      toastStore.error(`Bloque fallido - no encontraste todos los seeds a tiempo`, '⏰');
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

  function clearState() {
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
    sessionStats, recentBlocks, totalScans, config,
    // Actions
    loadStatus, applyTickData, activate, deactivate, toggleMode,
    clearState,
  };
});
