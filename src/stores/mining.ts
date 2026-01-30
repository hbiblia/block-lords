import { defineStore } from 'pinia';
import { ref, computed } from 'vue';

export const useMiningStore = defineStore('mining', () => {
  const activeRigs = ref<Array<{
    id: string;
    hashrate: number;
    powerConsumption: number;
    internetConsumption: number;
  }>>([]);

  const isMining = computed(() => activeRigs.value.length > 0);

  const totalHashrate = computed(() =>
    activeRigs.value.reduce((sum, rig) => sum + rig.hashrate, 0)
  );

  const totalEnergyConsumption = computed(() =>
    activeRigs.value.reduce((sum, rig) => sum + rig.powerConsumption, 0)
  );

  const totalInternetConsumption = computed(() =>
    activeRigs.value.reduce((sum, rig) => sum + rig.internetConsumption, 0)
  );

  function setActiveRigs(rigs: Array<{
    id: string;
    hashrate: number;
    powerConsumption: number;
    internetConsumption: number;
  }>) {
    activeRigs.value = rigs;
  }

  function addRig(rig: {
    id: string;
    hashrate: number;
    powerConsumption: number;
    internetConsumption: number;
  }) {
    if (!activeRigs.value.find(r => r.id === rig.id)) {
      activeRigs.value.push(rig);
    }
  }

  function removeRig(rigId: string) {
    activeRigs.value = activeRigs.value.filter(r => r.id !== rigId);
  }

  function clearRigs() {
    activeRigs.value = [];
  }

  return {
    activeRigs,
    isMining,
    totalHashrate,
    totalEnergyConsumption,
    totalInternetConsumption,
    setActiveRigs,
    addRig,
    removeRig,
    clearRigs,
  };
});
