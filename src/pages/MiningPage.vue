<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue';
import { useAuthStore } from '@/stores/auth';
import { getPlayerRigs, getNetworkStats, getRecentBlocks, toggleRig } from '@/utils/api';

const authStore = useAuthStore();

const loading = ref(true);
const rigs = ref<Array<{
  id: string;
  is_active: boolean;
  condition: number;
  rig: {
    id: string;
    name: string;
    hashrate: number;
    power_consumption: number;
    internet_consumption: number;
    tier: string;
  };
}>>([]);

const networkStats = ref({
  difficulty: 0,
  hashrate: 0,
  latestBlock: null as any,
  activeMiners: 0,
});

const recentBlocks = ref<any[]>([]);

async function loadData() {
  try {
    const [rigsData, networkData, blocksData] = await Promise.all([
      getPlayerRigs(authStore.player!.id),
      getNetworkStats(),
      getRecentBlocks(5),
    ]);

    rigs.value = rigsData ?? [];
    networkStats.value = networkData;
    recentBlocks.value = blocksData ?? [];
  } catch (e) {
    console.error('Error loading mining data:', e);
  } finally {
    loading.value = false;
  }
}

async function handleToggleRig(rigId: string) {
  // Optimistic update
  const rig = rigs.value.find(r => r.id === rigId);
  if (rig) {
    rig.is_active = !rig.is_active;
  }

  try {
    const result = await toggleRig(authStore.player!.id, rigId);

    if (!result.success) {
      // Revert on error
      if (rig) rig.is_active = !rig.is_active;
      alert(result.error ?? 'Error al cambiar estado del rig');
    }
  } catch (e) {
    // Revert on error
    if (rig) rig.is_active = !rig.is_active;
    console.error('Error toggling rig:', e);
  }
}

function handleBlockMined(event: CustomEvent) {
  const { block, winner } = event.detail;
  recentBlocks.value.unshift({
    ...block,
    miner: winner,
  });
  recentBlocks.value = recentBlocks.value.slice(0, 5);

  if (winner?.id === authStore.player?.id) {
    alert(`¡Minaste el bloque #${block.height}!`);
    // Recargar datos del jugador
    authStore.fetchPlayer();
  }
}

onMounted(() => {
  loadData();
  window.addEventListener('block-mined', handleBlockMined as EventListener);
});

onUnmounted(() => {
  window.removeEventListener('block-mined', handleBlockMined as EventListener);
});

function getTierColor(tier: string): string {
  switch (tier) {
    case 'elite': return 'text-rank-diamond';
    case 'advanced': return 'text-rank-gold';
    case 'standard': return 'text-rank-silver';
    default: return 'text-rank-bronze';
  }
}
</script>

<template>
  <div>
    <h1 class="text-2xl text-arcade-primary mb-6">Minería</h1>

    <div v-if="loading" class="text-center py-12 text-gray-400">
      Cargando...
    </div>

    <div v-else class="grid lg:grid-cols-3 gap-6">
      <!-- Rigs -->
      <div class="lg:col-span-2">
        <h2 class="text-lg text-arcade-primary mb-4">Tus Rigs</h2>

        <div v-if="rigs.length === 0" class="arcade-panel text-center py-8 text-gray-400">
          No tienes rigs. Ve al mercado para comprar uno.
        </div>

        <div v-else class="grid sm:grid-cols-2 gap-4">
          <div
            v-for="playerRig in rigs"
            :key="playerRig.id"
            class="rig-card"
            :class="{ 'active': playerRig.is_active, 'inactive': !playerRig.is_active }"
          >
            <div v-if="playerRig.is_active" class="mining-animation"></div>

            <div class="relative z-10">
              <div class="flex items-center justify-between mb-3">
                <h3 class="font-bold" :class="getTierColor(playerRig.rig.tier)">
                  {{ playerRig.rig.name }}
                </h3>
                <span
                  class="text-xs px-2 py-1 rounded"
                  :class="playerRig.is_active ? 'bg-arcade-success/20 text-arcade-success' : 'bg-gray-500/20 text-gray-400'"
                >
                  {{ playerRig.is_active ? 'ACTIVO' : 'INACTIVO' }}
                </span>
              </div>

              <div class="grid grid-cols-3 gap-2 text-xs text-gray-400 mb-4">
                <div>
                  <div class="text-white font-bold">{{ playerRig.rig.hashrate }}</div>
                  <div>H/s</div>
                </div>
                <div>
                  <div class="text-arcade-warning font-bold">{{ playerRig.rig.power_consumption }}</div>
                  <div>⚡/tick</div>
                </div>
                <div>
                  <div class="text-arcade-secondary font-bold">{{ playerRig.rig.internet_consumption }}</div>
                  <div>📡/tick</div>
                </div>
              </div>

              <div class="mb-3">
                <div class="flex justify-between text-xs mb-1">
                  <span class="text-gray-400">Condición</span>
                  <span :class="playerRig.condition < 30 ? 'text-arcade-danger' : ''">
                    {{ playerRig.condition }}%
                  </span>
                </div>
                <div class="h-2 bg-arcade-bg rounded-full overflow-hidden">
                  <div
                    class="h-full transition-all"
                    :class="playerRig.condition > 50 ? 'bg-arcade-success' : playerRig.condition > 20 ? 'bg-arcade-warning' : 'bg-arcade-danger'"
                    :style="{ width: `${playerRig.condition}%` }"
                  ></div>
                </div>
              </div>

              <div class="flex gap-2">
                <button
                  @click="handleToggleRig(playerRig.id)"
                  class="flex-1 text-sm py-2 rounded transition-colors"
                  :class="playerRig.is_active
                    ? 'bg-arcade-danger/20 text-arcade-danger hover:bg-arcade-danger/30'
                    : 'bg-arcade-success/20 text-arcade-success hover:bg-arcade-success/30'"
                >
                  {{ playerRig.is_active ? 'Apagar' : 'Encender' }}
                </button>
                <button
                  v-if="playerRig.condition < 100"
                  class="px-4 text-sm py-2 rounded bg-arcade-warning/20 text-arcade-warning hover:bg-arcade-warning/30 transition-colors"
                >
                  Reparar
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Sidebar -->
      <div class="space-y-6">
        <div class="arcade-panel">
          <h2 class="text-lg text-arcade-primary mb-4">Estado de la Red</h2>
          <div class="space-y-3 text-sm">
            <div class="flex justify-between">
              <span class="text-gray-400">Dificultad</span>
              <span class="font-mono">{{ networkStats.difficulty?.toLocaleString() ?? 0 }}</span>
            </div>
            <div class="flex justify-between">
              <span class="text-gray-400">Hashrate Total</span>
              <span class="font-mono">{{ networkStats.hashrate?.toLocaleString() ?? 0 }} H/s</span>
            </div>
            <div class="flex justify-between">
              <span class="text-gray-400">Mineros Activos</span>
              <span class="font-mono">{{ networkStats.activeMiners ?? 0 }}</span>
            </div>
            <div class="flex justify-between">
              <span class="text-gray-400">Último Bloque</span>
              <span class="font-mono">#{{ networkStats.latestBlock?.height ?? '-' }}</span>
            </div>
          </div>
        </div>

        <div class="arcade-panel">
          <h2 class="text-lg text-arcade-primary mb-4">Bloques Recientes</h2>
          <div class="space-y-2">
            <div
              v-for="block in recentBlocks"
              :key="block.id"
              class="flex items-center justify-between py-2 border-b border-arcade-border last:border-0 text-sm"
            >
              <span class="text-arcade-secondary">#{{ block.height }}</span>
              <span class="text-gray-400 text-xs">{{ block.miner?.username ?? 'Desconocido' }}</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
