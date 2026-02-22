import { defineStore } from 'pinia';
import { ref } from 'vue';

export type GamePhase = 'select' | 'playing' | 'result';

export const useScavengerStore = defineStore('scavenger', () => {
  const gamePhase = ref<GamePhase>('select');

  // Persistent stats (localStorage)
  const totalRuns = ref(0);
  const totalGcEarned = ref(0);
  const bestHaul = ref(0);
  const successfulRuns = ref(0);

  function setPhase(phase: GamePhase) {
    gamePhase.value = phase;
  }

  function recordRun(gc: number, success: boolean) {
    totalRuns.value++;
    if (success) {
      successfulRuns.value++;
      totalGcEarned.value += gc;
      if (gc > bestHaul.value) bestHaul.value = gc;
    }
    saveStats();
  }

  function loadStats() {
    try {
      const data = JSON.parse(localStorage.getItem('scavenger_stats') || '{}');
      totalRuns.value = data.totalRuns || 0;
      totalGcEarned.value = data.totalGcEarned || 0;
      bestHaul.value = data.bestHaul || 0;
      successfulRuns.value = data.successfulRuns || 0;
    } catch { /* ignore */ }
  }

  function saveStats() {
    localStorage.setItem('scavenger_stats', JSON.stringify({
      totalRuns: totalRuns.value,
      totalGcEarned: totalGcEarned.value,
      bestHaul: bestHaul.value,
      successfulRuns: successfulRuns.value,
    }));
  }

  function reset() {
    gamePhase.value = 'select';
  }

  return {
    gamePhase,
    totalRuns, totalGcEarned, bestHaul, successfulRuns,
    setPhase, recordRun, loadStats, saveStats, reset,
  };
});
