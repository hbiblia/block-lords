// =====================================================
// BLOCK LORDS - Mining Estimate Composable
// Hook para mostrar estimación de minería al usuario
// =====================================================

import { ref, computed, onMounted, onUnmounted } from 'vue';
import { getMiningEstimate, type MiningEstimate } from '@/utils/api';

export function useMiningEstimate(playerId: string, autoRefreshMs: number = 60000) {
  const estimate = ref<MiningEstimate | null>(null);
  const loading = ref(false);
  const error = ref<string | null>(null);
  let refreshInterval: ReturnType<typeof setInterval> | null = null;

  // Computed helpers para el UI
  const isMining = computed(() => estimate.value?.mining ?? false);

  const estimatedTimeText = computed(() => {
    if (!estimate.value?.mining) return null;

    const mins = estimate.value.estimatedMinutes;
    if (mins >= 60) {
      const hours = Math.floor(mins / 60);
      const remainingMins = Math.round(mins % 60);
      if (remainingMins === 0) return `~${hours}h`;
      return `~${hours}h ${remainingMins}m`;
    }
    return `~${Math.round(mins)} min`;
  });

  const timeRangeText = computed(() => {
    if (!estimate.value?.mining) return null;

    const min = estimate.value.minMinutes;
    const max = estimate.value.maxMinutes;

    const formatTime = (mins: number) => {
      if (mins >= 60) {
        const hours = Math.floor(mins / 60);
        const m = Math.round(mins % 60);
        if (m === 0) return `${hours}h`;
        return `${hours}h ${m}m`;
      }
      return `${Math.round(mins)}m`;
    };

    return `${formatTime(min)} - ${formatTime(max)}`;
  });

  const networkShareText = computed(() => {
    if (!estimate.value?.mining) return null;
    return `${estimate.value.networkShare.toFixed(2)}%`;
  });

  const blocksPerDayText = computed(() => {
    if (!estimate.value?.mining) return null;
    const blocks = estimate.value.blocksPerDay;
    if (blocks < 0.01) return '<0.01/día';
    if (blocks >= 1) return `${blocks.toFixed(1)}/día`;
    return `${blocks.toFixed(2)}/día`;
  });

  const notMiningReason = computed(() => {
    if (!estimate.value || estimate.value.mining) return null;

    switch (estimate.value.reason) {
      case 'no_active_rigs':
        return 'No hay rigs activos';
      case 'offline':
        return 'Desconectado';
      default:
        return 'No está minando';
    }
  });

  async function refresh() {
    if (!playerId) return;

    loading.value = true;
    error.value = null;

    try {
      estimate.value = await getMiningEstimate(playerId);
      if (!estimate.value.success) {
        error.value = estimate.value.error || 'Error desconocido';
      }
    } catch (e: any) {
      console.error('Error fetching mining estimate:', e);
      error.value = e.message || 'Error al obtener estimación';
    } finally {
      loading.value = false;
    }
  }

  function startAutoRefresh() {
    if (refreshInterval) return;
    if (autoRefreshMs > 0) {
      refreshInterval = setInterval(refresh, autoRefreshMs);
    }
  }

  function stopAutoRefresh() {
    if (refreshInterval) {
      clearInterval(refreshInterval);
      refreshInterval = null;
    }
  }

  onMounted(() => {
    refresh();
    startAutoRefresh();
  });

  onUnmounted(() => {
    stopAutoRefresh();
  });

  return {
    // Raw data
    estimate,
    loading,
    error,

    // Computed helpers
    isMining,
    estimatedTimeText,
    timeRangeText,
    networkShareText,
    blocksPerDayText,
    notMiningReason,

    // Actions
    refresh,
    startAutoRefresh,
    stopAutoRefresh,
  };
}
