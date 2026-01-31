import { defineStore } from 'pinia';
import { ref, computed } from 'vue';
import { getStreakStatus, claimDailyStreak } from '@/utils/api';
import { useAuthStore } from './auth';

export interface StreakReward {
  day: number;
  gamecoin: number;
  crypto: number;
  itemType: string | null;
  itemId: string | null;
  description: string;
}

export interface StreakStatus {
  currentStreak: number;
  longestStreak: number;
  canClaim: boolean;
  isExpired: boolean;
  nextDay: number;
  nextReward: {
    gamecoin: number;
    crypto: number;
    itemType: string | null;
    itemId: string | null;
  };
  lastClaimDate: string | null;
  nextClaimAvailable: string | null;
  streakExpiresAt: string | null;
  allRewards: StreakReward[];
}

export const useStreakStore = defineStore('streak', () => {
  const status = ref<StreakStatus | null>(null);
  const loading = ref(false);
  const claiming = ref(false);
  const error = ref<string | null>(null);
  const showModal = ref(false);
  const lastClaimResult = ref<{
    success: boolean;
    newStreak: number;
    gamecoinEarned: number;
    cryptoEarned: number;
    itemType: string | null;
    itemId: string | null;
  } | null>(null);

  const canClaim = computed(() => status.value?.canClaim ?? false);
  const currentStreak = computed(() => status.value?.currentStreak ?? 0);
  const longestStreak = computed(() => status.value?.longestStreak ?? 0);
  const nextDay = computed(() => status.value?.nextDay ?? 1);

  async function fetchStatus() {
    const authStore = useAuthStore();
    if (!authStore.player?.id) return;

    loading.value = true;
    error.value = null;

    try {
      const result = await getStreakStatus(authStore.player.id);
      if (result.success) {
        status.value = result as StreakStatus;
      } else {
        error.value = result.error ?? 'errors.fetchStreak';
      }
    } catch (e) {
      error.value = 'errors.serverConnection';
      console.error('Error fetching streak status:', e);
    } finally {
      loading.value = false;
    }
  }

  async function claim() {
    const authStore = useAuthStore();
    if (!authStore.player?.id) return null;

    claiming.value = true;
    error.value = null;
    lastClaimResult.value = null;

    try {
      const result = await claimDailyStreak(authStore.player.id);

      if (result.success) {
        lastClaimResult.value = {
          success: true,
          newStreak: result.newStreak,
          gamecoinEarned: result.gamecoinEarned,
          cryptoEarned: result.cryptoEarned,
          itemType: result.itemType,
          itemId: result.itemId,
        };

        // Actualizar balances del jugador
        await authStore.fetchPlayer();

        // Recargar status
        await fetchStatus();

        return lastClaimResult.value;
      } else {
        error.value = result.error ?? 'errors.claimReward';
        return null;
      }
    } catch (e) {
      error.value = 'errors.serverConnection';
      console.error('Error claiming streak:', e);
      return null;
    } finally {
      claiming.value = false;
    }
  }

  function openModal() {
    showModal.value = true;
    fetchStatus();
  }

  function closeModal() {
    showModal.value = false;
    lastClaimResult.value = null;
  }

  return {
    status,
    loading,
    claiming,
    error,
    showModal,
    lastClaimResult,
    canClaim,
    currentStreak,
    longestStreak,
    nextDay,
    fetchStatus,
    claim,
    openModal,
    closeModal,
  };
});
