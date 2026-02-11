import { defineStore } from 'pinia';
import { ref } from 'vue';

export type BattleView = 'lobby' | 'battle' | 'result';

export const useDefenseStore = defineStore('defense', () => {
  const showModal = ref(false);
  const loading = ref(false);
  const gameView = ref<BattleView>('lobby');

  function openModal() {
    showModal.value = true;
  }

  function closeModal() {
    showModal.value = false;
  }

  function setView(view: BattleView) {
    gameView.value = view;
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
    openModal,
    closeModal,
    setView,
    clear,
  };
});
