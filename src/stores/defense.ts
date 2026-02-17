import { defineStore } from 'pinia';
import { ref } from 'vue';
import { supabase } from '@/utils/supabase';

export type BattleView = 'lobby' | 'intro' | 'battle' | 'result';

export const useDefenseStore = defineStore('defense', () => {
  const showModal = ref(false);
  const loading = ref(false);
  const gameView = ref<BattleView>('lobby');
  const lobbyCount = ref(0);

  let lobbyPollingInterval: number | null = null;

  function openModal() {
    showModal.value = true;
  }

  function closeModal() {
    showModal.value = false;
  }

  function setView(view: BattleView) {
    gameView.value = view;
  }

  async function fetchLobbyCount() {
    try {
      const { count } = await supabase
        .from('battle_lobby')
        .select('*', { count: 'exact', head: true })
        .eq('status', 'waiting');
      lobbyCount.value = count || 0;
    } catch {
      // ignore
    }
  }

  function subscribeLobbyCount() {
    if (lobbyPollingInterval) return;
    fetchLobbyCount();
    lobbyPollingInterval = window.setInterval(fetchLobbyCount, 30000);
  }

  function unsubscribeLobbyCount() {
    if (lobbyPollingInterval) {
      clearInterval(lobbyPollingInterval);
      lobbyPollingInterval = null;
    }
  }

  function clear() {
    showModal.value = false;
    loading.value = false;
    gameView.value = 'lobby';
  }

  return {
    showModal,
    loading,
    gameView,
    lobbyCount,
    openModal,
    closeModal,
    setView,
    fetchLobbyCount,
    subscribeLobbyCount,
    unsubscribeLobbyCount,
    clear,
  };
});
