import { defineStore } from 'pinia';
import { ref, computed } from 'vue';
import { getDailyMissions, claimMissionReward, recordOnlineHeartbeat } from '@/utils/api';
import { useAuthStore } from './auth';

export interface Mission {
  id: string;
  missionId: string;
  name: string;
  description: string;
  missionType: string;
  targetValue: number;
  progress: number;
  isCompleted: boolean;
  isClaimed: boolean;
  rewardType: string;
  rewardAmount: number;
  difficulty: 'easy' | 'medium' | 'hard';
  icon: string;
  progressPercent: number;
}

export const useMissionsStore = defineStore('missions', () => {
  const missions = ref<Mission[]>([]);
  const loading = ref(false);
  const claiming = ref(false);
  const error = ref<string | null>(null);
  const showPanel = ref(false);
  const onlineMinutes = ref(0);
  const heartbeatInterval = ref<ReturnType<typeof setInterval> | null>(null);

  const completedCount = computed(() => missions.value.filter(m => m.isCompleted).length);
  const claimableCount = computed(() => missions.value.filter(m => m.isCompleted && !m.isClaimed).length);
  const totalCount = computed(() => missions.value.length);

  const easyMissions = computed(() => missions.value.filter(m => m.difficulty === 'easy'));
  const mediumMissions = computed(() => missions.value.filter(m => m.difficulty === 'medium'));
  const hardMissions = computed(() => missions.value.filter(m => m.difficulty === 'hard'));

  async function fetchMissions(silent = false) {
    const authStore = useAuthStore();
    if (!authStore.player?.id) return;

    if (!silent) {
      loading.value = true;
    }
    error.value = null;

    try {
      const result = await getDailyMissions(authStore.player.id);
      if (result.success) {
        missions.value = result.missions ?? [];
        onlineMinutes.value = result.onlineMinutes ?? 0;
      } else {
        error.value = result.error ?? 'errors.fetchMissions';
      }
    } catch (e) {
      error.value = 'errors.serverConnection';
      console.error('Error fetching missions:', e);
    } finally {
      loading.value = false;
    }
  }

  async function claimReward(missionUuid: string) {
    const authStore = useAuthStore();
    if (!authStore.player?.id) return null;

    claiming.value = true;
    error.value = null;

    try {
      const result = await claimMissionReward(authStore.player.id, missionUuid);

      if (result.success) {
        // Actualizar balances del jugador
        await authStore.fetchPlayer();
        // Recargar misiones (silencioso para evitar parpadeo)
        await fetchMissions(true);
        return result;
      } else {
        error.value = result.error ?? 'errors.claimReward';
        return null;
      }
    } catch (e) {
      error.value = 'errors.serverConnection';
      console.error('Error claiming mission reward:', e);
      return null;
    } finally {
      claiming.value = false;
    }
  }

  async function sendHeartbeat() {
    const authStore = useAuthStore();
    if (!authStore.player?.id || !authStore.isAuthenticated) return;

    try {
      const result = await recordOnlineHeartbeat(authStore.player.id);
      if (result.success) {
        onlineMinutes.value = result.minutesOnline ?? onlineMinutes.value;
        // Si se agregaron minutos, refrescar misiones para actualizar progreso (silencioso)
        if (result.added > 0) {
          await fetchMissions(true);
        }
      }
    } catch (e: any) {
      // Ignorar AbortError (el navegador cancela requests al cambiar de pestaña)
      if (e?.message?.includes('AbortError') || e?.name === 'AbortError') return;
      console.warn('Error sending heartbeat:', e);
    }
  }

  function startHeartbeat() {
    if (heartbeatInterval.value) return;

    // Enviar heartbeat cada 1 minuto
    heartbeatInterval.value = setInterval(() => {
      sendHeartbeat();
    }, 60000);

    // Enviar primer heartbeat inmediatamente
    sendHeartbeat();
  }

  function stopHeartbeat() {
    if (heartbeatInterval.value) {
      clearInterval(heartbeatInterval.value);
      heartbeatInterval.value = null;
    }
  }

  function openPanel() {
    showPanel.value = true;
    fetchMissions();
  }

  function closePanel() {
    showPanel.value = false;
  }

  function getDifficultyColor(difficulty: string) {
    switch (difficulty) {
      case 'easy': return 'text-status-success';
      case 'medium': return 'text-status-warning';
      case 'hard': return 'text-status-danger';
      default: return 'text-text-muted';
    }
  }

  function getDifficultyBg(difficulty: string) {
    switch (difficulty) {
      case 'easy': return 'bg-status-success/20';
      case 'medium': return 'bg-status-warning/20';
      case 'hard': return 'bg-status-danger/20';
      default: return 'bg-bg-tertiary';
    }
  }

  function getRewardIcon(rewardType: string) {
    switch (rewardType) {
      case 'gamecoin': return '🪙';
      case 'crypto': return '💎';
      case 'energy': return '⚡';
      case 'internet': return '📡';
      default: return '🎁';
    }
  }

  return {
    missions,
    loading,
    claiming,
    error,
    showPanel,
    onlineMinutes,
    completedCount,
    claimableCount,
    totalCount,
    easyMissions,
    mediumMissions,
    hardMissions,
    fetchMissions,
    claimReward,
    sendHeartbeat,
    startHeartbeat,
    stopHeartbeat,
    openPanel,
    closePanel,
    getDifficultyColor,
    getDifficultyBg,
    getRewardIcon,
  };
});
