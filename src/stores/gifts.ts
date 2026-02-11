import { defineStore } from 'pinia';
import { ref, computed } from 'vue';
import { getPendingGifts, claimGift as apiClaimGift } from '@/utils/api';
import { useAuthStore } from './auth';

export interface Gift {
  id: string;
  title: string;
  description: string | null;
  icon: string;
  reward_gamecoin: number;
  reward_crypto: number;
  reward_energy: number;
  reward_internet: number;
  reward_item_type: string | null;
  reward_item_id: string | null;
  reward_item_quantity: number;
  expires_at: string | null;
  created_at: string;
}

export interface GiftClaimResult {
  success: boolean;
  title: string;
  description: string | null;
  icon: string;
  gamecoin: number;
  crypto: number;
  energy: number;
  internet: number;
  itemType: string | null;
  itemId: string | null;
  itemQuantity: number;
}

export type GiftPhase = 'idle' | 'showing' | 'opening' | 'revealed';

export const useGiftsStore = defineStore('gifts', () => {
  const pendingGifts = ref<Gift[]>([]);
  const currentGift = ref<Gift | null>(null);
  const claimResult = ref<GiftClaimResult | null>(null);
  const phase = ref<GiftPhase>('idle');
  const loading = ref(false);
  const claiming = ref(false);

  const hasPendingGifts = computed(() => pendingGifts.value.length > 0);

  let pollInterval: ReturnType<typeof setInterval> | null = null;

  async function fetchGifts() {
    const authStore = useAuthStore();
    if (!authStore.player?.id) return;

    loading.value = true;
    try {
      const result = await getPendingGifts(authStore.player.id);
      if (Array.isArray(result)) {
        pendingGifts.value = result;
        // Auto-show first gift if idle
        if (pendingGifts.value.length > 0 && phase.value === 'idle') {
          showNextGift();
        }
      }
    } catch (e) {
      console.error('Error fetching gifts:', e);
    } finally {
      loading.value = false;
    }
  }

  function showNextGift() {
    if (pendingGifts.value.length === 0) {
      phase.value = 'idle';
      currentGift.value = null;
      return;
    }
    currentGift.value = pendingGifts.value[0];
    phase.value = 'showing';
  }

  function startOpening() {
    if (phase.value !== 'showing') return;
    phase.value = 'opening';
  }

  async function claimCurrentGift() {
    const authStore = useAuthStore();
    if (!authStore.player?.id || !currentGift.value) return null;

    claiming.value = true;
    try {
      const result = await apiClaimGift(authStore.player.id, currentGift.value.id);

      if (result.success) {
        claimResult.value = result as GiftClaimResult;
        phase.value = 'revealed';

        // Remove from pending list
        pendingGifts.value = pendingGifts.value.filter(g => g.id !== currentGift.value?.id);

        // Refresh player balances
        await authStore.fetchPlayer();

        return claimResult.value;
      } else {
        // Gift expired or already claimed - remove and show next
        pendingGifts.value = pendingGifts.value.filter(g => g.id !== currentGift.value?.id);
        showNextGift();
        return null;
      }
    } catch (e) {
      console.error('Error claiming gift:', e);
      return null;
    } finally {
      claiming.value = false;
    }
  }

  function collectAndNext() {
    claimResult.value = null;
    currentGift.value = null;
    // Show next gift or go idle
    showNextGift();
  }

  function startPolling() {
    if (pollInterval) return;
    pollInterval = setInterval(() => {
      if (phase.value === 'idle') {
        fetchGifts();
      }
    }, 5 * 60 * 1000); // Every 5 minutes
  }

  function stopPolling() {
    if (pollInterval) {
      clearInterval(pollInterval);
      pollInterval = null;
    }
  }

  return {
    pendingGifts,
    currentGift,
    claimResult,
    phase,
    loading,
    claiming,
    hasPendingGifts,
    fetchGifts,
    showNextGift,
    startOpening,
    claimCurrentGift,
    collectAndNext,
    startPolling,
    stopPolling,
  };
});
