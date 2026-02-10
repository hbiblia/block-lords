import { defineStore } from 'pinia';
import { ref, computed } from 'vue';
import { getPendingBlocks, getPendingBlocksCount, claimBlock, claimAllBlocks, claimAllBlocksWithRon } from '@/utils/api';
import { useAuthStore } from './auth';
import { useToastStore } from './toast';

export interface PendingBlock {
  id: string;
  block_id: string;
  block_height: number;
  reward: number;
  is_premium: boolean;
  shares_contributed?: number;     // NUEVO: Shares aportadas por el jugador
  total_block_shares?: number;     // NUEVO: Total de shares del bloque
  share_percentage?: number;       // NUEVO: Porcentaje de contribución
  created_at: string;
}

const PAGE_SIZE = 20;

export const usePendingBlocksStore = defineStore('pendingBlocks', () => {
  const pendingBlocks = ref<PendingBlock[]>([]);
  const loading = ref(false);
  const loadingMore = ref(false);
  const claiming = ref(false);
  const error = ref<string | null>(null);
  const showModal = ref(false);

  // Pagination state
  const page = ref(0);
  const hasMore = ref(false);
  const totalCount = ref(0);
  const serverTotalReward = ref(0);

  const count = computed(() => totalCount.value);
  const totalReward = computed(() => {
    // Use server total if we haven't loaded all blocks
    if (hasMore.value && serverTotalReward.value > 0) return serverTotalReward.value;
    return pendingBlocks.value.reduce((sum, block) => sum + Number(block.reward), 0);
  });
  const hasPending = computed(() => count.value > 0);

  async function fetchPendingBlocks(reset = true) {
    const authStore = useAuthStore();
    if (!authStore.player?.id) return;

    if (reset) {
      page.value = 0;
      loading.value = true;
    } else {
      loadingMore.value = true;
    }
    error.value = null;

    try {
      const offset = page.value * PAGE_SIZE;
      const data = await getPendingBlocks(authStore.player.id, PAGE_SIZE, offset);

      const blocks: PendingBlock[] = data?.blocks ?? [];
      hasMore.value = data?.has_more ?? false;
      totalCount.value = data?.total ?? 0;

      if (reset) {
        pendingBlocks.value = blocks;
      } else {
        // Append, deduplicating
        const existingIds = new Set(pendingBlocks.value.map(b => b.id));
        const newBlocks = blocks.filter(b => !existingIds.has(b.id));
        pendingBlocks.value = [...pendingBlocks.value, ...newBlocks];
      }

      // Fetch server total reward if we have more pages
      if (hasMore.value && reset) {
        getPendingBlocksCount(authStore.player.id).then(countData => {
          if (countData) {
            serverTotalReward.value = countData.total_reward ?? 0;
          }
        }).catch(() => {});
      }
    } catch (e) {
      error.value = 'Error al cargar bloques pendientes';
      console.error('Error fetching pending blocks:', e);
    } finally {
      loading.value = false;
      loadingMore.value = false;
    }
  }

  async function loadMore() {
    if (loadingMore.value || loading.value || !hasMore.value) return;
    page.value++;
    await fetchPendingBlocks(false);
  }

  async function fetchCount() {
    const authStore = useAuthStore();
    if (!authStore.player?.id) return;

    try {
      const data = await getPendingBlocksCount(authStore.player.id);
      // Si tenemos datos, actualizar
      if (data && data.count > 0 && totalCount.value !== data.count) {
        totalCount.value = data.count;
        serverTotalReward.value = data.total_reward ?? 0;
        await fetchPendingBlocks();
      }
    } catch (e) {
      console.error('Error fetching pending blocks count:', e);
    }
  }

  async function claim(pendingId: string) {
    const authStore = useAuthStore();
    if (!authStore.player?.id) {
      error.value = 'No autenticado';
      return null;
    }

    claiming.value = true;
    error.value = null;

    // Save original state for rollback
    const originalBlocks = [...pendingBlocks.value];
    const originalCount = totalCount.value;

    try {
      const result = await claimBlock(authStore.player.id, pendingId);

      if (result.success) {
        // Remove from local list AFTER successful API call
        pendingBlocks.value = pendingBlocks.value.filter(b => b.id !== pendingId);
        totalCount.value = Math.max(0, totalCount.value - 1);

        // Update player balance - if this fails, block is still claimed on server
        try {
          await authStore.fetchPlayer();
        } catch (e) {
          console.warn('Error updating player after claim, will retry:', e);
          // Schedule a retry in background
          setTimeout(() => authStore.fetchPlayer().catch(() => {}), 2000);
        }

        // Toast de éxito
        const toastStore = useToastStore();
        toastStore.success(`¡Bloque reclamado! +${result.reward} ₿`);

        return result;
      } else {
        error.value = result.error ?? 'Error al reclamar bloque';
        return null;
      }
    } catch (e) {
      // Rollback on network error
      pendingBlocks.value = originalBlocks;
      totalCount.value = originalCount;
      error.value = 'Error de conexión. Intenta de nuevo.';
      console.error('Error claiming block:', e);
      return null;
    } finally {
      claiming.value = false;
    }
  }

  async function claimAll() {
    const authStore = useAuthStore();
    if (!authStore.player?.id) {
      error.value = 'No autenticado';
      return null;
    }

    claiming.value = true;
    error.value = null;

    // Save original state for rollback
    const originalBlocks = [...pendingBlocks.value];
    const originalCount = totalCount.value;

    try {
      const result = await claimAllBlocks(authStore.player.id);

      if (result.success) {
        // Clear local list AFTER successful API call
        pendingBlocks.value = [];
        totalCount.value = 0;
        hasMore.value = false;

        // Update player balance - if this fails, blocks are still claimed on server
        try {
          await authStore.fetchPlayer();
        } catch (e) {
          console.warn('Error updating player after claim all, will retry:', e);
          // Schedule a retry in background
          setTimeout(() => authStore.fetchPlayer().catch(() => {}), 2000);
        }

        // Toast de éxito
        const toastStore = useToastStore();
        toastStore.success(`¡${result.blocks_claimed} bloques reclamados! +${result.total_reward} ₿`);

        // Cerrar modal
        showModal.value = false;

        return result;
      } else {
        error.value = result.error ?? 'Error al reclamar bloques';
        return null;
      }
    } catch (e) {
      // Rollback on network error
      pendingBlocks.value = originalBlocks;
      totalCount.value = originalCount;
      error.value = 'Error de conexión. Intenta de nuevo.';
      console.error('Error claiming all blocks:', e);
      return null;
    } finally {
      claiming.value = false;
    }
  }

  // Claim all with RON payment (instant, 0.0001 RON per block)
  const RON_COST_PER_BLOCK = 0.0001;

  const totalRonCost = computed(() => count.value * RON_COST_PER_BLOCK);

  async function claimAllWithRon() {
    const authStore = useAuthStore();
    if (!authStore.player?.id) {
      error.value = 'No autenticado';
      return null;
    }

    claiming.value = true;
    error.value = null;

    // Save original state for rollback
    const originalBlocks = [...pendingBlocks.value];
    const originalCount = totalCount.value;

    try {
      const result = await claimAllBlocksWithRon(authStore.player.id);

      if (result.success) {
        // Clear local list AFTER successful API call
        pendingBlocks.value = [];
        totalCount.value = 0;
        hasMore.value = false;

        // Update player balance - if this fails, blocks are still claimed on server
        try {
          await authStore.fetchPlayer();
        } catch (e) {
          console.warn('Error updating player after claim all with RON, will retry:', e);
          // Schedule a retry in background
          setTimeout(() => authStore.fetchPlayer().catch(() => {}), 2000);
        }

        // Toast de éxito
        const toastStore = useToastStore();
        toastStore.success(`¡${result.blocks_claimed} bloques reclamados! +${result.total_reward} ₿ (-${result.ron_spent} RON)`);

        // Cerrar modal
        showModal.value = false;

        return result;
      } else {
        error.value = result.error ?? 'Error al reclamar bloques con RON';
        // Show specific error for insufficient RON
        if (result.error === 'RON insuficiente') {
          const toastStore = useToastStore();
          toastStore.error(`RON insuficiente. Necesitas ${result.required} RON (tienes ${result.current})`);
        }
        return null;
      }
    } catch (e) {
      // Rollback on network error
      pendingBlocks.value = originalBlocks;
      totalCount.value = originalCount;
      error.value = 'Error de conexión. Intenta de nuevo.';
      console.error('Error claiming all blocks with RON:', e);
      return null;
    } finally {
      claiming.value = false;
    }
  }

  function openModal() {
    showModal.value = true;
    fetchPendingBlocks();
  }

  function closeModal() {
    showModal.value = false;
  }

  // Llamado cuando se mina un nuevo bloque (desde realtime)
  // Incluye deduplicación para evitar duplicados de eventos realtime
  function addPendingBlock(block: PendingBlock) {
    // Check for duplicate by id or block_id
    const exists = pendingBlocks.value.some(
      b => b.id === block.id || b.block_id === block.block_id
    );

    if (!exists) {
      pendingBlocks.value.unshift(block);
      totalCount.value++;
    }
  }

  return {
    pendingBlocks,
    loading,
    loadingMore,
    claiming,
    error,
    showModal,
    count,
    totalReward,
    totalRonCost,
    RON_COST_PER_BLOCK,
    hasPending,
    hasMore,
    fetchPendingBlocks,
    fetchCount,
    loadMore,
    claim,
    claimAll,
    claimAllWithRon,
    openModal,
    closeModal,
    addPendingBlock,
  };
});
