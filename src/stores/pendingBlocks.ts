import { defineStore } from 'pinia';
import { ref, computed } from 'vue';
import { getPendingBlocks, getPendingBlocksCount, claimBlock, claimAllBlocks } from '@/utils/api';
import { useAuthStore } from './auth';
import { useToastStore } from './toast';

export interface PendingBlock {
  id: string;
  block_id: string;
  block_height: number;
  reward: number;
  is_premium: boolean;
  created_at: string;
}

export const usePendingBlocksStore = defineStore('pendingBlocks', () => {
  const pendingBlocks = ref<PendingBlock[]>([]);
  const loading = ref(false);
  const claiming = ref(false);
  const error = ref<string | null>(null);
  const showModal = ref(false);

  const count = computed(() => pendingBlocks.value.length);
  const totalReward = computed(() =>
    pendingBlocks.value.reduce((sum, block) => sum + Number(block.reward), 0)
  );
  const hasPending = computed(() => count.value > 0);

  async function fetchPendingBlocks() {
    const authStore = useAuthStore();
    if (!authStore.player?.id) return;

    loading.value = true;
    error.value = null;

    try {
      const data = await getPendingBlocks(authStore.player.id);
      pendingBlocks.value = data ?? [];
    } catch (e) {
      error.value = 'Error al cargar bloques pendientes';
      console.error('Error fetching pending blocks:', e);
    } finally {
      loading.value = false;
    }
  }

  async function fetchCount() {
    const authStore = useAuthStore();
    if (!authStore.player?.id) return;

    try {
      const data = await getPendingBlocksCount(authStore.player.id);
      // Si tenemos datos, actualizar
      if (data && data.count > 0 && pendingBlocks.value.length !== data.count) {
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

    try {
      const result = await claimBlock(authStore.player.id, pendingId);

      if (result.success) {
        // Remove from local list AFTER successful API call
        pendingBlocks.value = pendingBlocks.value.filter(b => b.id !== pendingId);

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

    try {
      const result = await claimAllBlocks(authStore.player.id);

      if (result.success) {
        // Clear local list AFTER successful API call
        pendingBlocks.value = [];

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
      error.value = 'Error de conexión. Intenta de nuevo.';
      console.error('Error claiming all blocks:', e);
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
    }
  }

  return {
    pendingBlocks,
    loading,
    claiming,
    error,
    showModal,
    count,
    totalReward,
    hasPending,
    fetchPendingBlocks,
    fetchCount,
    claim,
    claimAll,
    openModal,
    closeModal,
    addPendingBlock,
  };
});
