import { defineStore } from 'pinia';
import { ref, computed } from 'vue';
import { supabase } from '@/utils/supabase';
import { useAuthStore } from './auth';
import { useToastStore } from './toast';
import { playSound } from '@/utils/sounds';
import {
  getPlayerPredictions,
  getPredictionPrice,
  placePredictionBet as apiPlaceBet,
  cancelPredictionBet as apiCancelBet,
} from '@/utils/api';

// ===== TYPES =====

export interface PredictionBet {
  id: string;
  direction: 'up' | 'down';
  target_percent: number;
  bet_amount_lw: number;
  bet_amount_ron: number;
  entry_price: number;
  target_price: number;
  current_price: number;
  progress_percent: number;
  potential_yield: number;
  created_at: string;
}

export interface PredictionHistory {
  id: string;
  direction: 'up' | 'down';
  target_percent: number;
  bet_amount_lw: number;
  entry_price: number;
  target_price: number;
  exit_price: number | null;
  status: 'won' | 'cancelled';
  yield_earned_lw: number;
  fee_amount_lw: number;
  created_at: string;
  settled_at: string;
}

export interface PredictionStats {
  total_bets: number;
  total_won: number;
  total_cancelled: number;
  total_yield_earned: number;
  total_fees_paid: number;
  active_count: number;
}

// ===== STORE =====

export const usePredictionStore = defineStore('prediction', () => {
  // State
  const activeBets = ref<PredictionBet[]>([]);
  const history = ref<PredictionHistory[]>([]);
  const stats = ref<PredictionStats | null>(null);
  const currentPrice = ref<number | null>(null);
  const previousPrice = ref<number | null>(null);
  const priceChangePercent = ref<number>(0);
  const high24h = ref<number | null>(null);
  const low24h = ref<number | null>(null);

  // Loading states
  const loading = ref(false);
  const refreshing = ref(false);
  const placing = ref(false);
  const cancelling = ref<string | null>(null);

  // Realtime
  let predictionChannel: ReturnType<typeof supabase.channel> | null = null;
  let pricePollingInterval: number | null = null;

  // ===== COMPUTED =====

  const activeCount = computed(() => activeBets.value.length);
  const canPlaceBet = computed(() => activeCount.value < 3);
  const totalActiveAmount = computed(() =>
    activeBets.value.reduce((sum, b) => sum + b.bet_amount_lw, 0)
  );
  const priceTrend = computed<'up' | 'down' | 'neutral'>(() => {
    if (currentPrice.value === null || previousPrice.value === null) return 'neutral';
    return currentPrice.value > previousPrice.value ? 'up' :
           currentPrice.value < previousPrice.value ? 'down' : 'neutral';
  });

  // ===== ACTIONS =====

  async function loadData() {
    const authStore = useAuthStore();
    if (!authStore.player?.id) return;

    if (activeBets.value.length > 0 || history.value.length > 0) {
      refreshing.value = true;
    } else {
      loading.value = true;
    }

    try {
      const data = await getPlayerPredictions(authStore.player.id);
      if (data?.success) {
        activeBets.value = data.active || [];
        history.value = data.history || [];
        stats.value = data.stats || null;
        if (data.current_price != null) {
          currentPrice.value = data.current_price;
        }
      }
    } catch (e) {
      console.error('Error loading predictions:', e);
    } finally {
      loading.value = false;
      refreshing.value = false;
    }
  }

  async function loadPrice() {
    try {
      const data = await getPredictionPrice();
      if (data) {
        currentPrice.value = data.price;
        previousPrice.value = data.previous_price;
        priceChangePercent.value = data.change_percent ?? 0;
        high24h.value = data.high_24h;
        low24h.value = data.low_24h;
      }
    } catch (e) {
      console.error('Error loading prediction price:', e);
    }
  }

  async function placeBet(
    direction: 'up' | 'down',
    targetPercent: number,
    betAmount: number
  ): Promise<{ success: boolean; error?: string }> {
    const authStore = useAuthStore();
    const toastStore = useToastStore();
    if (!authStore.player) return { success: false, error: 'No player' };

    placing.value = true;
    try {
      const result = await apiPlaceBet(
        authStore.player.id, direction, targetPercent, betAmount
      );

      if (result?.success) {
        playSound('purchase');
        toastStore.success(
          direction === 'up'
            ? `Predicción creada: SUBE ${targetPercent}%`
            : `Predicción creada: BAJA ${targetPercent}%`
        );
        await loadData();
        await authStore.fetchPlayer();
        return { success: true };
      }

      playSound('error');
      return { success: false, error: result?.error ?? 'Error placing bet' };
    } catch (e: unknown) {
      console.error('Error placing prediction bet:', e);
      playSound('error');
      const msg = e instanceof Error ? e.message : 'Connection error';
      return { success: false, error: msg };
    } finally {
      placing.value = false;
    }
  }

  async function cancelBet(betId: string): Promise<{ success: boolean; error?: string }> {
    const authStore = useAuthStore();
    const toastStore = useToastStore();
    if (!authStore.player) return { success: false, error: 'No player' };

    cancelling.value = betId;
    try {
      const result = await apiCancelBet(authStore.player.id, betId);

      if (result?.success) {
        playSound('click');
        toastStore.info(
          `Apuesta cancelada. Reembolso: ${Number(result.refund).toFixed(0)} Landwork (2% fee)`
        );
        await loadData();
        await authStore.fetchPlayer();
        return { success: true };
      }

      playSound('error');
      return { success: false, error: result?.error ?? 'Error cancelling bet' };
    } catch (e: unknown) {
      console.error('Error cancelling prediction:', e);
      playSound('error');
      const msg = e instanceof Error ? e.message : 'Connection error';
      return { success: false, error: msg };
    } finally {
      cancelling.value = null;
    }
  }

  // ===== PRICE POLLING =====

  function startPricePolling() {
    stopPricePolling();
    loadPrice();
    pricePollingInterval = window.setInterval(() => {
      loadPrice();
      if (activeBets.value.length > 0) {
        loadData();
      }
    }, 30000);
  }

  function stopPricePolling() {
    if (pricePollingInterval) {
      clearInterval(pricePollingInterval);
      pricePollingInterval = null;
    }
  }

  // ===== REALTIME =====

  function subscribeToRealtime() {
    const authStore = useAuthStore();
    if (!authStore.player?.id) return;

    predictionChannel = supabase
      .channel(`predictions:${authStore.player.id}`)
      .on('postgres_changes', {
        event: 'UPDATE',
        schema: 'public',
        table: 'prediction_bets',
        filter: `player_id=eq.${authStore.player.id}`,
      }, (payload) => {
        const newData = payload.new as Record<string, unknown>;
        if (newData.status === 'won') {
          playSound('reward');
          const toastStore = useToastStore();
          const yieldAmount = Number(newData.yield_earned_lw || 0).toFixed(0);
          toastStore.success(
            `Predicción ganada! +${yieldAmount} Landwork de yield`
          );
          loadData();
          const authStore = useAuthStore();
          authStore.fetchPlayer();
        }
      })
      .subscribe();
  }

  function unsubscribeFromRealtime() {
    if (predictionChannel) {
      supabase.removeChannel(predictionChannel);
      predictionChannel = null;
    }
    stopPricePolling();
  }

  function clearState() {
    unsubscribeFromRealtime();
    activeBets.value = [];
    history.value = [];
    stats.value = null;
    currentPrice.value = null;
    previousPrice.value = null;
    priceChangePercent.value = 0;
    high24h.value = null;
    low24h.value = null;
    loading.value = false;
    refreshing.value = false;
    placing.value = false;
    cancelling.value = null;
  }

  return {
    // State
    activeBets,
    history,
    stats,
    currentPrice,
    previousPrice,
    priceChangePercent,
    high24h,
    low24h,
    loading,
    refreshing,
    placing,
    cancelling,

    // Computed
    activeCount,
    canPlaceBet,
    totalActiveAmount,
    priceTrend,

    // Actions
    loadData,
    loadPrice,
    placeBet,
    cancelBet,

    // Polling & Realtime
    startPricePolling,
    stopPricePolling,
    subscribeToRealtime,
    unsubscribeFromRealtime,
    clearState,
  };
});
