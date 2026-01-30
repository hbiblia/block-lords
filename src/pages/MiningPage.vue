<script setup lang="ts">
import { ref, onMounted, onUnmounted, computed } from 'vue';
import { useAuthStore } from '@/stores/auth';
import { useMiningStore } from '@/stores/mining';
import { getPlayerRigs, getNetworkStats, getRecentBlocks, toggleRig } from '@/utils/api';
import MarketModal from '@/components/MarketModal.vue';

const authStore = useAuthStore();
const miningStore = useMiningStore();

const showMarket = ref(false);

const loading = ref(true);
const rigs = ref<Array<{
  id: string;
  is_active: boolean;
  condition: number;
  temperature: number;
  activated_at: string | null;
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
  difficulty: 1000,
  hashrate: 0,
  latestBlock: null as any,
  activeMiners: 0,
});

const recentBlocks = ref<any[]>([]);

// Mining simulation
const miningProgress = ref(0);
const hashesCalculated = ref(0);
const miningInterval = ref<number | null>(null);
const lastBlockFound = ref<any>(null);
const showBlockFound = ref(false);

// Calcular hashrate base del jugador (sin penalizaciones)
const totalHashrate = computed(() => {
  return rigs.value
    .filter(r => r.is_active)
    .reduce((sum, r) => sum + r.rig.hashrate, 0);
});

// Calcular hashrate efectivo (con penalización por temperatura y condición)
const effectiveHashrate = computed(() => {
  return rigs.value
    .filter(r => r.is_active)
    .reduce((sum, r) => {
      const temp = r.temperature ?? 25;
      const condition = r.condition ?? 100;
      // Penalización por temperatura: >60°C reduce hashrate (hasta -50% a 100°C)
      let tempPenalty = 1;
      if (temp > 60) {
        tempPenalty = Math.max(0.5, 1 - ((temp - 60) * 0.0125));
      }
      return sum + (r.rig.hashrate * (condition / 100) * tempPenalty);
    }, 0);
});

// Calcular probabilidad de minar (usa hashrate efectivo)
const miningChance = computed(() => {
  if (networkStats.value.hashrate === 0) return 0;
  return (effectiveHashrate.value / networkStats.value.hashrate) * 100;
});

// Número de rigs activos
const activeRigsCount = computed(() => rigs.value.filter(r => r.is_active).length);

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

    // Sync active rigs to mining store for resource consumption display
    syncMiningStore();
  } catch (e) {
    console.error('Error loading mining data:', e);
  } finally {
    loading.value = false;
  }
}

// Sync active rigs to the mining store
function syncMiningStore() {
  const activeRigsList = rigs.value
    .filter(r => r.is_active)
    .map(r => ({
      id: r.id,
      hashrate: r.rig.hashrate,
      powerConsumption: r.rig.power_consumption,
      internetConsumption: r.rig.internet_consumption,
    }));
  miningStore.setActiveRigs(activeRigsList);
}

// Simulación visual de minería
function startMiningSimulation() {
  if (miningInterval.value) return;

  miningInterval.value = window.setInterval(() => {
    if (totalHashrate.value > 0) {
      // Incrementar progreso basado en hashrate
      const progressIncrement = (totalHashrate.value / networkStats.value.difficulty) * 2;
      miningProgress.value = Math.min(100, miningProgress.value + progressIncrement);
      hashesCalculated.value += totalHashrate.value / 60; // Aproximación por segundo

      // Reset cuando llega a 100 (simula intento de bloque)
      if (miningProgress.value >= 100) {
        miningProgress.value = 0;
      }
    } else {
      miningProgress.value = 0;
    }
  }, 100);
}

function stopMiningSimulation() {
  if (miningInterval.value) {
    clearInterval(miningInterval.value);
    miningInterval.value = null;
  }
}

async function handleToggleRig(rigId: string) {
  const rig = rigs.value.find(r => r.id === rigId);
  if (rig) {
    rig.is_active = !rig.is_active;
    // Immediately update mining store for visual feedback
    syncMiningStore();
  }

  try {
    const result = await toggleRig(authStore.player!.id, rigId);

    if (!result.success) {
      if (rig) rig.is_active = !rig.is_active;
      // Revert mining store on failure
      syncMiningStore();
      alert(result.error ?? 'Error al cambiar estado del rig');
    }
  } catch (e) {
    if (rig) rig.is_active = !rig.is_active;
    // Revert mining store on error
    syncMiningStore();
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
    lastBlockFound.value = block;
    showBlockFound.value = true;
    miningProgress.value = 100;

    setTimeout(() => {
      showBlockFound.value = false;
      miningProgress.value = 0;
    }, 3000);

    authStore.fetchPlayer();
  }
}

function getTierColor(tier: string): string {
  switch (tier) {
    case 'elite': return 'text-rank-diamond';
    case 'advanced': return 'text-rank-gold';
    case 'standard': return 'text-rank-silver';
    default: return 'text-rank-bronze';
  }
}

function getTierBg(tier: string): string {
  switch (tier) {
    case 'elite': return 'from-purple-500/20 to-cyan-500/20';
    case 'advanced': return 'from-yellow-500/20 to-orange-500/20';
    case 'standard': return 'from-gray-400/20 to-gray-500/20';
    default: return 'from-amber-600/20 to-amber-700/20';
  }
}

function getTempColor(temp: number): string {
  if (temp >= 80) return 'text-status-danger';
  if (temp >= 60) return 'text-status-warning';
  if (temp >= 40) return 'text-yellow-400';
  return 'text-status-success';
}

function getTempStatus(temp: number): string {
  if (temp >= 80) return 'CRÍTICO';
  if (temp >= 60) return 'Alto';
  if (temp >= 40) return 'Normal';
  return 'Óptimo';
}

function getTempBarColor(temp: number): string {
  if (temp >= 80) return 'bg-status-danger';
  if (temp >= 60) return 'bg-status-warning';
  if (temp >= 40) return 'bg-yellow-400';
  return 'bg-status-success';
}

function getRigEffectiveHashrate(rig: typeof rigs.value[0]): number {
  const temp = rig.temperature ?? 25;
  const condition = rig.condition ?? 100;
  let tempPenalty = 1;
  if (temp > 60) {
    tempPenalty = Math.max(0.5, 1 - ((temp - 60) * 0.0125));
  }
  return rig.rig.hashrate * (condition / 100) * tempPenalty;
}

function getRigPenaltyPercent(rig: typeof rigs.value[0]): number {
  const effective = getRigEffectiveHashrate(rig);
  const base = rig.rig.hashrate;
  if (base === 0) return 0;
  return Math.round(((base - effective) / base) * 100);
}

function formatUptime(activatedAt: string | null): string {
  if (!activatedAt) return '0s';

  const start = new Date(activatedAt).getTime();
  const now = Date.now();
  const diff = Math.max(0, now - start);

  const seconds = Math.floor(diff / 1000);
  const minutes = Math.floor(seconds / 60);
  const hours = Math.floor(minutes / 60);
  const days = Math.floor(hours / 24);

  if (days > 0) {
    return `${days}d ${hours % 24}h`;
  } else if (hours > 0) {
    return `${hours}h ${minutes % 60}m`;
  } else if (minutes > 0) {
    return `${minutes}m ${seconds % 60}s`;
  } else {
    return `${seconds}s`;
  }
}

// Reactive uptime - update every second
const uptimeKey = ref(0);
let uptimeInterval: number | null = null;

function startUptimeTimer() {
  if (uptimeInterval) return;
  uptimeInterval = window.setInterval(() => {
    uptimeKey.value++;
  }, 1000);
}

function stopUptimeTimer() {
  if (uptimeInterval) {
    clearInterval(uptimeInterval);
    uptimeInterval = null;
  }
}

onMounted(() => {
  loadData();
  startMiningSimulation();
  startUptimeTimer();
  window.addEventListener('block-mined', handleBlockMined as EventListener);
});

onUnmounted(() => {
  stopMiningSimulation();
  stopUptimeTimer();
  window.removeEventListener('block-mined', handleBlockMined as EventListener);
  // Clear mining store when leaving page
  miningStore.clearRigs();
});
</script>

<template>
  <div>
    <!-- Header -->
    <div class="flex items-center justify-between mb-6">
      <h1 class="text-2xl font-display font-bold">
        <span class="gradient-text">Minería</span>
      </h1>
      <div class="flex items-center gap-3">
        <span class="badge" :class="activeRigsCount > 0 ? 'badge-success' : 'badge-warning'">
          {{ activeRigsCount }} rig{{ activeRigsCount !== 1 ? 's' : '' }} activo{{ activeRigsCount !== 1 ? 's' : '' }}
        </span>
        <button @click="showMarket = true" class="btn-primary flex items-center gap-2">
          <span>🛒</span>
          <span>Mercado</span>
        </button>
      </div>
    </div>

    <div v-if="loading" class="text-center py-20 text-text-muted">
      <div class="w-12 h-12 mx-auto rounded-xl bg-gradient-primary flex items-center justify-center text-2xl animate-pulse mb-4">
        ⛏️
      </div>
      Cargando estación de minería...
    </div>

    <div v-else class="space-y-6">
      <!-- Mining Status Panel - PRINCIPAL -->
      <div class="card relative overflow-hidden">
        <!-- Background effect cuando está minando -->
        <div
          v-if="totalHashrate > 0"
          class="absolute inset-0 bg-gradient-to-r from-accent-primary/5 via-accent-secondary/5 to-accent-primary/5 animate-pulse"
        ></div>

        <div class="relative z-10">
          <div class="flex items-center justify-between mb-6">
            <div class="flex items-center gap-3">
              <div
                class="w-14 h-14 rounded-xl flex items-center justify-center text-3xl"
                :class="totalHashrate > 0 ? 'bg-gradient-primary animate-pulse' : 'bg-bg-tertiary'"
              >
                ⛏️
              </div>
              <div>
                <h2 class="text-lg font-semibold">Centro de Minería</h2>
                <p class="text-sm text-text-muted">
                  {{ totalHashrate > 0 ? 'Minando activamente...' : 'Rigs inactivos' }}
                </p>
              </div>
            </div>

            <div class="text-right">
              <div class="text-3xl font-bold font-mono" :class="effectiveHashrate > 0 ? 'gradient-text' : 'text-text-muted'">
                {{ Math.round(effectiveHashrate).toLocaleString() }}
              </div>
              <div class="text-xs text-text-muted flex items-center justify-end gap-1">
                <span>H/s Efectivo</span>
                <span
                  v-if="effectiveHashrate < totalHashrate"
                  class="text-status-danger"
                  :title="`Base: ${totalHashrate.toLocaleString()} H/s - Reducido por temperatura/condición`"
                >
                  (↓{{ Math.round(((totalHashrate - effectiveHashrate) / totalHashrate) * 100) }}%)
                </span>
              </div>
            </div>
          </div>

          <!-- Mining Progress Bar -->
          <div class="mb-4">
            <div class="flex justify-between text-sm mb-2">
              <span class="text-text-muted">Progreso de Hash</span>
              <span class="font-mono text-accent-primary">{{ hashesCalculated.toFixed(0) }} hashes</span>
            </div>
            <div class="h-4 bg-bg-tertiary rounded-full overflow-hidden relative">
              <div
                class="h-full rounded-full transition-all duration-100"
                :class="showBlockFound ? 'bg-status-success' : 'bg-gradient-to-r from-accent-primary to-accent-secondary'"
                :style="{ width: `${miningProgress}%` }"
              ></div>
              <!-- Efecto de brillo -->
              <div
                v-if="totalHashrate > 0"
                class="absolute inset-0 bg-gradient-to-r from-transparent via-white/20 to-transparent"
                style="animation: shimmer 2s linear infinite;"
              ></div>
            </div>
          </div>

          <!-- Stats Grid -->
          <div class="grid grid-cols-4 gap-4">
            <div class="bg-bg-secondary rounded-xl p-3 text-center">
              <div class="text-xl font-bold text-status-warning">{{ miningChance.toFixed(2) }}%</div>
              <div class="text-xs text-text-muted">Probabilidad</div>
            </div>
            <div class="bg-bg-secondary rounded-xl p-3 text-center">
              <div class="text-xl font-bold text-accent-tertiary">{{ networkStats.difficulty?.toLocaleString() ?? 0 }}</div>
              <div class="text-xs text-text-muted">Dificultad</div>
            </div>
            <div class="bg-bg-secondary rounded-xl p-3 text-center">
              <div class="text-xl font-bold text-accent-primary">{{ networkStats.activeMiners ?? 0 }}</div>
              <div class="text-xs text-text-muted">Mineros</div>
            </div>
            <div class="bg-bg-secondary rounded-xl p-3 text-center">
              <div class="text-xl font-bold text-status-success">#{{ networkStats.latestBlock?.height ?? 0 }}</div>
              <div class="text-xs text-text-muted">Último Bloque</div>
            </div>
          </div>
        </div>

        <!-- Block Found Celebration -->
        <div
          v-if="showBlockFound"
          class="absolute inset-0 bg-status-success/20 flex items-center justify-center z-20 animate-fade-in"
        >
          <div class="text-center">
            <div class="text-6xl mb-4 animate-bounce">🎉</div>
            <div class="text-2xl font-bold text-status-success">¡Bloque Minado!</div>
            <div class="text-lg text-white">#{{ lastBlockFound?.height }}</div>
          </div>
        </div>
      </div>

      <div class="grid lg:grid-cols-3 gap-6">
        <!-- Rigs Column -->
        <div class="lg:col-span-2 space-y-4">
          <h2 class="text-lg font-semibold flex items-center gap-2">
            <span>🖥️</span> Tus Rigs
          </h2>

          <div v-if="rigs.length === 0" class="card text-center py-12">
            <div class="text-4xl mb-4">🛒</div>
            <p class="text-text-muted mb-4">No tienes rigs. Compra uno en el mercado.</p>
            <button @click="showMarket = true" class="btn-primary">
              Ir al Mercado
            </button>
          </div>

          <div v-else class="grid sm:grid-cols-2 gap-4">
            <div
              v-for="playerRig in rigs"
              :key="playerRig.id"
              class="rig-card group"
              :class="{ 'mining': playerRig.is_active }"
            >
              <!-- Tier gradient background -->
              <div
                class="absolute inset-0 bg-gradient-to-br opacity-50"
                :class="getTierBg(playerRig.rig.tier)"
              ></div>

              <!-- Mining effect overlay -->
              <div v-if="playerRig.is_active" class="mining-effect"></div>

              <div class="relative z-10">
                <!-- Header -->
                <div class="flex items-start justify-between mb-4">
                  <div>
                    <h3 class="font-bold text-lg" :class="getTierColor(playerRig.rig.tier)">
                      {{ playerRig.rig.name }}
                    </h3>
                    <span class="text-xs text-text-muted uppercase">{{ playerRig.rig.tier }}</span>
                  </div>
                  <div
                    class="px-3 py-1 rounded-full text-xs font-bold"
                    :class="playerRig.is_active
                      ? 'bg-status-success/20 text-status-success'
                      : 'bg-bg-tertiary text-text-muted'"
                  >
                    {{ playerRig.is_active ? '● MINANDO' : '○ APAGADO' }}
                  </div>
                </div>

                <!-- Hashrate Display -->
                <div class="bg-bg-primary/50 rounded-xl p-4 mb-4">
                  <div class="text-center">
                    <div
                      class="text-2xl font-bold font-mono flex items-baseline justify-center gap-1"
                      :class="playerRig.is_active ? 'text-white' : 'text-text-muted'"
                      :key="uptimeKey"
                    >
                      <span :class="getRigPenaltyPercent(playerRig) > 0 ? 'text-status-warning' : ''">
                        {{ Math.round(getRigEffectiveHashrate(playerRig)).toLocaleString() }}
                      </span>
                      <span class="text-text-muted text-lg">/</span>
                      <span class="text-text-muted text-lg">{{ playerRig.rig.hashrate.toLocaleString() }}</span>
                    </div>
                    <div class="text-xs text-text-muted">HASHRATE (H/s)</div>
                  </div>

                  <!-- Uptime display when active -->
                  <div v-if="playerRig.is_active && playerRig.activated_at" class="mt-3 text-center" :key="uptimeKey">
                    <div class="text-xs text-text-muted mb-1">Tiempo encendido</div>
                    <div class="text-sm font-mono text-accent-primary">
                      ⏱️ {{ formatUptime(playerRig.activated_at) }}
                    </div>
                  </div>

                  <!-- Mini progress when active -->
                  <div v-if="playerRig.is_active" class="mt-3">
                    <div class="xp-bar">
                      <div class="xp-bar-fill" :style="{ width: `${miningProgress}%` }"></div>
                    </div>
                  </div>
                </div>

                <!-- Stats -->
                <div class="grid grid-cols-3 gap-2 mb-4 text-sm">
                  <div class="flex items-center gap-1">
                    <span class="text-status-warning">⚡</span>
                    <span class="text-text-muted text-xs">{{ playerRig.rig.power_consumption }}/t</span>
                  </div>
                  <div class="flex items-center gap-1">
                    <span class="text-accent-tertiary">📡</span>
                    <span class="text-text-muted text-xs">{{ playerRig.rig.internet_consumption }}/t</span>
                  </div>
                  <div class="flex items-center gap-1">
                    <span>🌡️</span>
                    <span
                      class="text-xs font-medium"
                      :class="getTempColor(playerRig.temperature ?? 25)"
                    >
                      {{ (playerRig.temperature ?? 25).toFixed(0) }}°C
                    </span>
                  </div>
                </div>

                <!-- Temperature Bar -->
                <div class="mb-3">
                  <div class="flex justify-between text-xs mb-1">
                    <span class="text-text-muted">Temperatura</span>
                    <span :class="getTempColor(playerRig.temperature ?? 25)">
                      {{ getTempStatus(playerRig.temperature ?? 25) }}
                    </span>
                  </div>
                  <div class="progress-bar h-2">
                    <div
                      class="progress-bar-fill transition-all"
                      :class="getTempBarColor(playerRig.temperature ?? 25)"
                      :style="{ width: `${playerRig.temperature ?? 25}%` }"
                    ></div>
                  </div>
                </div>

                <!-- Condition Bar -->
                <div class="mb-4">
                  <div class="flex justify-between text-xs mb-1">
                    <span class="text-text-muted">Condición</span>
                    <span :class="playerRig.condition < 30 ? 'text-status-danger' : 'text-white'">
                      {{ playerRig.condition }}%
                    </span>
                  </div>
                  <div class="progress-bar h-2">
                    <div
                      class="progress-bar-fill"
                      :class="playerRig.condition > 50 ? 'bg-status-success' : playerRig.condition > 20 ? 'bg-status-warning' : 'bg-status-danger'"
                      :style="{ width: `${playerRig.condition}%` }"
                    ></div>
                  </div>
                </div>

                <!-- Actions -->
                <div class="flex gap-2">
                  <button
                    @click="handleToggleRig(playerRig.id)"
                    class="flex-1 py-2.5 rounded-xl font-medium transition-all"
                    :class="playerRig.is_active
                      ? 'bg-status-danger/20 text-status-danger hover:bg-status-danger/30'
                      : 'bg-status-success/20 text-status-success hover:bg-status-success/30'"
                  >
                    {{ playerRig.is_active ? '⏹ Detener' : '▶ Iniciar' }}
                  </button>
                  <button
                    v-if="playerRig.condition < 100"
                    class="px-4 py-2.5 rounded-xl bg-status-warning/20 text-status-warning hover:bg-status-warning/30 transition-all"
                  >
                    🔧
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Sidebar -->
        <div class="space-y-4">
          <!-- Recent Blocks -->
          <div class="card">
            <h3 class="font-semibold mb-4 flex items-center gap-2">
              <span>📦</span> Bloques Recientes
            </h3>

            <div v-if="recentBlocks.length === 0" class="text-center py-6 text-text-muted text-sm">
              Sin bloques aún
            </div>

            <div v-else class="space-y-2">
              <div
                v-for="(block, index) in recentBlocks"
                :key="block.id"
                class="flex items-center justify-between p-3 rounded-lg transition-colors"
                :class="block.miner?.id === authStore.player?.id ? 'bg-status-success/10 border border-status-success/30' : 'bg-bg-secondary'"
              >
                <div class="flex items-center gap-3">
                  <div
                    class="w-8 h-8 rounded-lg flex items-center justify-center text-sm font-bold"
                    :class="index === 0 ? 'bg-gradient-primary text-white' : 'bg-bg-tertiary text-text-muted'"
                  >
                    {{ index === 0 ? '🆕' : index + 1 }}
                  </div>
                  <div>
                    <div class="font-mono font-medium text-accent-primary">#{{ block.height }}</div>
                    <div class="text-xs text-text-muted">
                      {{ block.miner?.id === authStore.player?.id ? '¡Tú!' : block.miner?.username ?? 'Desconocido' }}
                    </div>
                  </div>
                </div>
                <div v-if="block.miner?.id === authStore.player?.id" class="text-status-success text-xl">
                  ⭐
                </div>
              </div>
            </div>
          </div>

          <!-- Quick Stats -->
          <div class="card">
            <h3 class="font-semibold mb-4 flex items-center gap-2">
              <span>📊</span> Tus Estadísticas
            </h3>
            <div class="space-y-3">
              <div class="flex justify-between items-center">
                <span class="text-text-muted">Hashrate</span>
                <span class="font-mono font-medium">
                  <span :class="effectiveHashrate < totalHashrate ? 'text-status-warning' : ''">{{ Math.round(effectiveHashrate).toLocaleString() }}</span>
                  <span class="text-text-muted">/{{ totalHashrate.toLocaleString() }}</span>
                  <span class="text-xs text-text-muted ml-1">H/s</span>
                </span>
              </div>
              <div class="flex justify-between items-center">
                <span class="text-text-muted">Rigs Activos</span>
                <span class="font-mono font-medium">{{ activeRigsCount }} / {{ rigs.length }}</span>
              </div>
              <div class="flex justify-between items-center">
                <span class="text-text-muted">Prob. por Bloque</span>
                <span class="font-mono font-medium text-status-warning">{{ miningChance.toFixed(2) }}%</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Market Modal -->
    <MarketModal
      :show="showMarket"
      @close="showMarket = false"
      @purchased="loadData"
    />
  </div>
</template>

<style scoped>
@keyframes shimmer {
  0% { transform: translateX(-100%); }
  100% { transform: translateX(100%); }
}

.mining-effect {
  position: absolute;
  inset: 0;
  pointer-events: none;
  background: linear-gradient(
    180deg,
    transparent 0%,
    rgba(139, 92, 246, 0.08) 50%,
    transparent 100%
  );
  animation: mining-scan 2s ease-in-out infinite;
}

@keyframes mining-scan {
  0%, 100% { transform: translateY(-100%); }
  50% { transform: translateY(100%); }
}
</style>
