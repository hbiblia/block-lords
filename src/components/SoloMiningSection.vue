<script setup lang="ts">
import { ref, computed, watch, onMounted, onUnmounted } from 'vue';
import { useSoloMiningStore } from '@/stores/solo-mining';
import { useAuthStore } from '@/stores/auth';
import { useMiningStore } from '@/stores/mining';
import SoloMiningActivateModal from './SoloMiningActivateModal.vue';

const props = defineProps<{ attachedToTabs?: boolean }>();

const soloStore = useSoloMiningStore();
const authStore = useAuthStore();
const miningStore = useMiningStore();

const showActivateModal = ref(false);

// Scanning animation: random numbers spinning on unfound seeds
const scanningNumbers = ref<Record<number, string>>({});
let scanInterval: number | null = null;

function startScanAnimation() {
  if (scanInterval) return;
  scanInterval = window.setInterval(() => {
    const newNums: Record<number, string> = {};
    for (const seed of soloStore.seeds) {
      if (!seed.found) {
        newNums[seed.index] = String(Math.floor(Math.random() * 10000)).padStart(4, '0');
      }
    }
    scanningNumbers.value = newNums;
  }, 150);
}

function stopScanAnimation() {
  if (scanInterval) { clearInterval(scanInterval); scanInterval = null; }
}

const isMining = computed(() =>
  soloStore.currentBlock && miningStore.soloEffectiveHashrate > 0 && soloStore.blockTimeRemaining > 0
);

const scansPerSecond = computed(() => Math.floor(miningStore.soloEffectiveHashrate / 100));

onMounted(() => { if (isMining.value) startScanAnimation(); });
onUnmounted(() => stopScanAnimation());

// Watch mining state to start/stop animation
watch(isMining, (mining) => {
  if (mining) startScanAnimation();
  else stopScanAnimation();
});

// Track recently found seeds for animation
const recentlyFoundSeeds = ref<Set<number>>(new Set());
const prevFoundSet = ref<Set<number>>(new Set());

watch(() => soloStore.seeds, (newSeeds) => {
  const currentFound = new Set(newSeeds.filter(s => s.found).map(s => s.index));
  for (const idx of currentFound) {
    if (!prevFoundSet.value.has(idx)) {
      recentlyFoundSeeds.value.add(idx);
      // Clear animation after it plays
      setTimeout(() => {
        recentlyFoundSeeds.value.delete(idx);
      }, 2000);
    }
  }
  prevFoundSet.value = currentFound;
}, { deep: true });

// Reset when block changes
watch(() => soloStore.currentBlock?.block_number, () => {
  recentlyFoundSeeds.value.clear();
  prevFoundSet.value.clear();
});

const blockTypeConfig: Record<string, { color: string; icon: string; label: string; border: string; gradient: string }> = {
  bronze: { color: 'text-amber-600', icon: '🥉', label: 'Bronze', border: 'border-amber-600/30', gradient: 'from-amber-600/10' },
  silver: { color: 'text-gray-300', icon: '🥈', label: 'Silver', border: 'border-gray-300/30', gradient: 'from-gray-300/10' },
  gold: { color: 'text-yellow-400', icon: '🥇', label: 'Gold', border: 'border-yellow-400/30', gradient: 'from-yellow-400/10' },
  diamond: { color: 'text-cyan-400', icon: '💎', label: 'Diamond', border: 'border-cyan-400/30', gradient: 'from-cyan-400/10' },
};

const currentBlockConfig = computed(() => {
  const type = soloStore.blockType ?? 'bronze';
  return blockTypeConfig[type] ?? blockTypeConfig.bronze;
});

function formatTime(seconds: number): string {
  if (seconds <= 0) return '00:00';
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}`;
}

function formatNumber(n: number): string {
  return n.toLocaleString('en-US');
}

const timeAlertClass = computed(() => {
  const remaining = soloStore.blockTimeRemaining;
  if (remaining <= 60) return 'text-status-danger';
  if (remaining <= 300) return 'text-status-warning';
  return 'text-blue-400';
});

const timeAlertLevel = computed(() => {
  const remaining = soloStore.blockTimeRemaining;
  if (remaining <= 60) return 'critical';
  if (remaining <= 300) return 'warning';
  return 'normal';
});

const timeProgressPercent = computed(() => {
  const total = 1800; // 30 min
  const remaining = soloStore.blockTimeRemaining;
  return Math.max(0, 100 - (remaining / total * 100));
});
</script>

<template>
  <div>
    <!-- Sin alquiler activo: mostrar activacion -->
    <template v-if="!soloStore.isActive">
      <div class="card relative overflow-hidden p-4 sm:p-6 text-center mb-5">
        <div class="absolute inset-0 bg-gradient-to-r from-cyan-500/5 via-transparent to-cyan-500/5"></div>
        <div class="relative">
          <div class="text-4xl mb-3">⛏️</div>
          <h3 class="text-lg font-bold text-text-primary mb-2">Solo Mining</h3>
          <p class="text-text-muted text-sm mb-4">Mina tus propios bloques de forma independiente. Encuentra los seeds para completar cada bloque y llevarte toda la recompensa.</p>

          <div class="grid grid-cols-2 sm:grid-cols-4 gap-2 mb-4">
            <div v-for="(config, type) in blockTypeConfig" :key="type"
              class="bg-bg-secondary rounded-lg p-2 text-center">
              <div class="text-lg">{{ config.icon }}</div>
              <div class="text-[10px] font-medium" :class="config.color">{{ config.label }}</div>
            </div>
          </div>

          <button @click="showActivateModal = true"
            :disabled="!authStore.isPremium"
            class="px-6 py-3 rounded-xl font-bold text-sm transition-all"
            :class="authStore.isPremium
              ? 'bg-gradient-primary text-white hover:opacity-90'
              : 'bg-bg-tertiary text-text-muted cursor-not-allowed'">
            {{ authStore.isPremium ? 'Activar Solo Mining' : 'Requiere Premium' }}
          </button>
        </div>
      </div>
    </template>

    <!-- Alquiler activo: mostrar mining -->
    <template v-else>
      <div class="card relative overflow-hidden p-3 sm:p-6 mb-5"
        :class="props.attachedToTabs ? 'rounded-t-none border-t-0' : ''">
        <div v-if="soloStore.currentBlock"
          class="absolute inset-0 bg-gradient-to-r from-cyan-500/5 via-transparent to-cyan-500/5 animate-pulse"></div>

        <div class="relative z-10">
          <!-- Header (igual que pool) -->
          <div class="flex items-center justify-between mb-3 sm:mb-4">
            <div class="flex items-center gap-2 sm:gap-3">
              <div class="w-10 h-10 sm:w-14 sm:h-14 rounded-xl flex items-center justify-center text-2xl sm:text-3xl"
                :class="soloStore.currentBlock ? 'bg-gradient-to-br from-cyan-600 to-cyan-500 animate-pulse' : 'bg-bg-tertiary'">
                {{ soloStore.currentBlock ? currentBlockConfig.icon : '⛏️' }}
              </div>
              <div>
                <h2 class="text-base sm:text-lg font-semibold">
                  <span v-if="soloStore.currentBlock">
                    Bloque #{{ soloStore.currentBlock.block_number }}
                    <span :class="currentBlockConfig.color" class="ml-1 text-sm">{{ currentBlockConfig.label }}</span>
                  </span>
                  <span v-else class="text-text-muted">Esperando bloque...</span>
                </h2>
                <p class="text-sm text-text-muted">
                  {{ soloStore.currentBlock ? `Recompensa: ${formatNumber(soloStore.blockReward)} crypto` : 'El siguiente bloque se asignara pronto' }}
                </p>
              </div>
            </div>

            <div class="text-right">
              <div class="text-xl sm:text-3xl font-bold font-mono"
                :class="miningStore.soloEffectiveHashrate > 0 ? 'gradient-text' : 'text-text-muted'">
                {{ Math.round(miningStore.soloEffectiveHashrate).toLocaleString() }}
              </div>
              <div class="text-[10px] sm:text-xs text-text-muted">H/s efectivos</div>
            </div>
          </div>

          <!-- Bloque activo: contenido -->
          <template v-if="soloStore.currentBlock">
            <!-- Indicador de Tiempo (estilo pool) -->
            <div class="mb-3 sm:mb-4 p-3 sm:p-4 bg-bg-secondary rounded-xl border border-border/30"
              :class="{
                'border-status-danger': timeAlertLevel === 'critical',
                'border-status-warning': timeAlertLevel === 'warning'
              }">
              <div class="flex items-center justify-between mb-2 sm:mb-3">
                <div class="flex items-center gap-1.5 sm:gap-2">
                  <span class="text-xl sm:text-2xl">⏰</span>
                  <div>
                    <div class="text-xs sm:text-sm text-text-muted">Tiempo restante</div>
                    <div class="text-xl sm:text-2xl font-bold font-mono" :class="timeAlertClass">
                      {{ formatTime(soloStore.blockTimeRemaining) }}
                    </div>
                  </div>
                </div>
                <div v-if="timeAlertLevel === 'critical'"
                  class="px-2 sm:px-3 py-0.5 sm:py-1 bg-status-danger/20 border border-status-danger/50 rounded-lg animate-pulse">
                  <span class="text-status-danger font-semibold text-xs sm:text-sm">Cerrando!</span>
                </div>
                <div v-else class="text-right">
                  <div class="text-[10px] text-text-muted">Bloque</div>
                  <div class="text-xs font-mono text-text-secondary">#{{ soloStore.currentBlock?.block_number }}</div>
                </div>
              </div>

              <!-- Barra de progreso del tiempo -->
              <div class="h-2 sm:h-3 bg-bg-tertiary rounded-full overflow-hidden relative mb-2 sm:mb-3">
                <div class="h-full transition-all duration-1000"
                  :class="{
                    'bg-gradient-to-r from-status-danger to-red-400': timeAlertLevel === 'critical',
                    'bg-gradient-to-r from-status-warning to-amber-400': timeAlertLevel === 'warning',
                    'bg-gradient-to-r from-accent-primary to-cyan-400': timeAlertLevel === 'normal'
                  }"
                  :style="{ width: `${timeProgressPercent}%` }"></div>
                <div v-if="miningStore.soloEffectiveHashrate > 0"
                  class="absolute inset-0 bg-gradient-to-r from-transparent via-white/10 to-transparent"
                  style="animation: shimmer 2s linear infinite;"></div>
              </div>

              <!-- Info: Estado + Seeds + Scans -->
              <div class="flex items-center justify-between text-[10px] sm:text-xs">
                <span v-if="isMining" class="flex items-center gap-1.5">
                  <span class="relative flex h-2 w-2">
                    <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-cyan-400 opacity-75"></span>
                    <span class="relative inline-flex rounded-full h-2 w-2 bg-cyan-400"></span>
                  </span>
                  <span class="text-cyan-400 font-medium">Escaneando</span>
                  <span class="text-text-muted font-mono">{{ scansPerSecond }}/tick</span>
                </span>
                <span v-else class="text-status-warning flex items-center gap-1">
                  <span>⚠️</span> Sin hashrate activo
                </span>
                <span class="text-text-muted">
                  🔑 <span class="font-mono text-text-secondary">{{ soloStore.seedsFound }}/{{ soloStore.seedsTotal }}</span>
                  · 📊 <span class="font-mono text-text-secondary">{{ formatNumber(soloStore.totalScans) }}</span> scans
                </span>
              </div>
            </div>

            <!-- Grid de Seeds -->
            <div class="mb-3 sm:mb-4">
              <div class="text-[10px] text-text-muted mb-2 uppercase tracking-wider">Seeds del bloque</div>
              <div class="flex flex-wrap gap-2 justify-center">
                <div v-for="seed in soloStore.seeds" :key="seed.index"
                  class="relative bg-bg-secondary rounded-xl px-3 py-2 min-w-[72px] text-center border transition-all duration-500 overflow-hidden"
                  :class="[
                    seed.found
                      ? `${currentBlockConfig.border} bg-gradient-to-b ${currentBlockConfig.gradient} to-transparent`
                      : isMining ? 'border-cyan-500/20' : 'border-border/30',
                    recentlyFoundSeeds.has(seed.index) ? 'seed-found-flash' : ''
                  ]">
                  <!-- Found burst effect -->
                  <div v-if="recentlyFoundSeeds.has(seed.index)" class="absolute inset-0 pointer-events-none">
                    <div class="seed-ring absolute inset-0 rounded-xl border-2"
                      :class="soloStore.blockType === 'gold' ? 'border-yellow-400' : soloStore.blockType === 'silver' ? 'border-gray-300' : soloStore.blockType === 'diamond' ? 'border-cyan-400' : 'border-amber-500'"></div>
                    <div v-for="n in 6" :key="'spark-' + n"
                      class="seed-spark absolute w-1.5 h-1.5 rounded-full"
                      :class="soloStore.blockType === 'gold' ? 'bg-yellow-400' : soloStore.blockType === 'silver' ? 'bg-gray-300' : soloStore.blockType === 'diamond' ? 'bg-cyan-400' : 'bg-amber-500'"
                      :style="{
                        top: '50%', left: '50%',
                        animationDelay: (n * 0.05) + 's',
                        '--spark-angle': (n * 60) + 'deg',
                      }"></div>
                  </div>
                  <div class="relative font-mono text-lg font-bold tracking-wider"
                    :class="[
                      seed.found ? currentBlockConfig.color : isMining ? 'text-cyan-500/40' : 'text-text-muted/30',
                      recentlyFoundSeeds.has(seed.index) ? 'seed-number-pop' : ''
                    ]">
                    {{ seed.found ? String(seed.seed_number).padStart(4, '0') : (isMining ? (scanningNumbers[seed.index] ?? '0000') : '????') }}
                  </div>
                  <div class="relative text-[9px] mt-0.5"
                    :class="seed.found ? 'text-status-success' : isMining ? 'text-cyan-500/60' : 'text-text-muted'">
                    {{ seed.found ? 'FOUND' : isMining ? 'SCANNING...' : `Seed ${seed.index}` }}
                  </div>
                </div>
              </div>
            </div>

            <!-- Grid de Stats (estilo pool con border-left) -->
            <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-5 gap-2 sm:gap-3 mb-3">
              <!-- Hashrate -->
              <div class="bg-bg-secondary rounded-xl p-2 sm:p-3 border-l-4 border-accent-primary">
                <div class="flex items-center gap-1 mb-0.5 sm:mb-1">
                  <span class="text-sm sm:text-base">⚡</span>
                  <div class="text-[10px] text-text-muted">Hashrate</div>
                </div>
                <div class="text-lg sm:text-xl font-bold font-mono text-accent-primary">
                  {{ formatNumber(miningStore.soloEffectiveHashrate) }}
                </div>
                <div class="text-[10px] text-text-muted">H/s</div>
              </div>

              <!-- Scans/tick -->
              <div class="bg-bg-secondary rounded-xl p-2 sm:p-3 border-l-4 border-amber-500">
                <div class="flex items-center gap-1 mb-0.5 sm:mb-1">
                  <span class="text-sm sm:text-base">📊</span>
                  <div class="text-[10px] text-text-muted">Scans/tick</div>
                </div>
                <div class="text-lg sm:text-xl font-bold font-mono text-amber-400">
                  {{ Math.floor(miningStore.soloEffectiveHashrate / 100) }}
                </div>
                <div class="text-[10px] text-text-muted">por tick</div>
              </div>

              <!-- Recompensa -->
              <div class="bg-bg-secondary rounded-xl p-2 sm:p-3 border-l-4 border-cyan-500">
                <div class="flex items-center gap-1 mb-0.5 sm:mb-1">
                  <span class="text-sm sm:text-base">💰</span>
                  <div class="text-[10px] text-text-muted">Recompensa</div>
                </div>
                <div class="text-lg sm:text-xl font-bold font-mono text-cyan-400">
                  {{ formatNumber(soloStore.blockReward) }}
                </div>
                <div class="text-[10px] text-text-muted">crypto</div>
              </div>

              <!-- Completados -->
              <div class="bg-bg-secondary rounded-xl p-2 sm:p-3 border-l-4 border-emerald-500">
                <div class="flex items-center gap-1 mb-0.5 sm:mb-1">
                  <span class="text-sm sm:text-base">✅</span>
                  <div class="text-[10px] text-text-muted">Completados</div>
                </div>
                <div class="text-lg sm:text-xl font-bold font-mono text-status-success">
                  {{ soloStore.sessionStats.blocks_completed }}
                </div>
                <div class="text-[10px] text-text-muted">bloques</div>
              </div>

              <!-- Ganado -->
              <div class="bg-bg-secondary rounded-xl p-2 sm:p-3 border-l-4 border-purple-500">
                <div class="flex items-center gap-1 mb-0.5 sm:mb-1">
                  <span class="text-sm sm:text-base">💎</span>
                  <div class="text-[10px] text-text-muted">Total ganado</div>
                </div>
                <div class="text-lg sm:text-xl font-bold font-mono text-purple-400">
                  {{ formatNumber(soloStore.sessionStats.total_earned) }}
                </div>
                <div class="text-[10px] text-text-muted">crypto</div>
              </div>
            </div>
          </template>

          <!-- Sin bloque activo: esperando -->
          <div v-else class="text-center py-8 text-text-muted">
            <div class="text-4xl mb-3">⏳</div>
            <div class="text-lg font-medium mb-1">Esperando bloque...</div>
            <div class="text-sm">El siguiente bloque se asignara automaticamente</div>
            <div class="text-xs mt-2 text-text-muted">Tu alquiler esta activo</div>
          </div>
        </div>
      </div>
    </template>

    <!-- Modal de activacion -->
    <SoloMiningActivateModal
      :show="showActivateModal"
      @close="showActivateModal = false"
      @activated="showActivateModal = false"
    />
  </div>
</template>

<style scoped>
/* Seed found: card flash glow */
.seed-found-flash {
  animation: seedFlash 1.5s ease-out forwards;
}

@keyframes seedFlash {
  0% {
    box-shadow: 0 0 0 0 currentColor;
    transform: scale(1);
  }

  15% {
    box-shadow: 0 0 20px 4px currentColor;
    transform: scale(1.12);
  }

  30% {
    transform: scale(0.97);
  }

  45% {
    transform: scale(1.04);
  }

  100% {
    box-shadow: 0 0 6px 1px currentColor;
    transform: scale(1);
  }
}

/* Seed number pop-in */
.seed-number-pop {
  animation: numberPop 0.5s cubic-bezier(0.34, 1.56, 0.64, 1) 0.1s both;
}

@keyframes numberPop {
  0% {
    transform: scale(0);
    opacity: 0;
  }

  100% {
    transform: scale(1);
    opacity: 1;
  }
}

/* Expanding ring */
.seed-ring {
  animation: ringExpand 0.8s ease-out forwards;
}

@keyframes ringExpand {
  0% {
    transform: scale(0.8);
    opacity: 1;
  }

  100% {
    transform: scale(1.6);
    opacity: 0;
  }
}

/* Sparks flying outward */
.seed-spark {
  animation: sparkFly 0.7s ease-out both;
}

@keyframes sparkFly {
  0% {
    transform: translate(-50%, -50%) rotate(var(--spark-angle, 0deg)) translateY(0) scale(1);
    opacity: 1;
  }

  100% {
    transform: translate(-50%, -50%) rotate(var(--spark-angle, 0deg)) translateY(-30px) scale(0);
    opacity: 0;
  }
}
</style>
