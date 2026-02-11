<script setup lang="ts">
import { ref, onMounted, onUnmounted, computed, nextTick, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAuthStore } from '@/stores/auth';
import { useMiningStore } from '@/stores/mining';
import { buyRigSlot } from '@/utils/api';
import { playSound } from '@/utils/sounds';
import { useRigSound } from '@/composables/useSound';
import { useWakeLock } from '@/composables/useWakeLock';
import { useMiningEstimate } from '@/composables/useMiningEstimate';
import RigEnhanceModal from '@/components/RigEnhanceModal.vue';

// Wake Lock to keep screen on while mining
const { requestWakeLock, releaseWakeLock } = useWakeLock();

// Rig sound loop (fan sound while mining)
const { updateRigSound, stopRigSound } = useRigSound();

const { t } = useI18n();
const authStore = useAuthStore();
const miningStore = useMiningStore();

// Mining estimate
const {
  refresh: refreshEstimate
} = useMiningEstimate(authStore.player?.id ?? '', 60000);

// Modals
const showRigManage = ref(false);
const selectedRigForManage = ref<typeof miningStore.rigs[0] | null>(null);

// Slot purchase
const buyingSlot = ref(false);
const showConfirmSlotPurchase = ref(false);

// Stop rig confirmation
const showConfirmStopRig = ref(false);
const rigToStop = ref<typeof miningStore.rigs[0] | null>(null);
const stoppingRig = ref(false);
const stopRigError = ref<string | null>(null);

// Mining simulation (visual only)
const miningProgress = ref(0);
const hashesCalculated = ref(0);
const miningInterval = ref<number | null>(null);
const lastBlockFound = ref<any>(null);
const showBlockFound = ref(false);

// Uptime timer
const uptimeKey = ref(0);
let uptimeInterval: number | null = null;

// Computed from store
const rigs = computed(() => miningStore.rigs);
const networkStats = computed(() => miningStore.networkStats);
const recentBlocks = computed(() => miningStore.recentBlocks);
const rigCooling = computed(() => miningStore.rigCooling);
const rigBoosts = computed(() => miningStore.rigBoosts);
const activeBoosts = computed(() => miningStore.activeBoosts);
const slotInfo = computed(() => miningStore.slotInfo);
const loading = computed(() => miningStore.loading);
const dataLoaded = computed(() => miningStore.dataLoaded);
const totalHashrate = computed(() => miningStore.totalHashrate);
const effectiveHashrate = computed(() => miningStore.effectiveHashrate);
const activeRigsCount = computed(() => miningStore.activeRigsCount);

// Nuevo sistema de shares
const currentMiningBlock = computed(() => miningStore.currentMiningBlock);
const blockTimeRemaining = computed(() => miningStore.blockTimeRemaining);
const sharesProgress = computed(() => miningStore.sharesProgress);
const playerSharePercentage = computed(() => miningStore.playerSharePercentage);
const estimatedReward = computed(() => miningStore.estimatedReward);
const sharesRate = computed(() => miningStore.sharesRate);
const sharesEfficiency = computed(() => miningStore.sharesEfficiency);
const timeRemainingAlert = computed(() => miningStore.timeRemainingAlert);

// Premium status
const isPremium = computed(() => {
  const premiumUntil = authStore.player?.premium_until;
  if (!premiumUntil) return false;
  return new Date(premiumUntil) > new Date();
});

// Block type helpers
const blockTypeEmoji = computed(() => {
  const type = currentMiningBlock.value?.block_type || 'bronze';
  return type === 'gold' ? '🥇' : type === 'silver' ? '🥈' : '🥉';
});

const blockTypeLabel = computed(() => {
  const type = currentMiningBlock.value?.block_type || 'bronze';
  return type === 'gold' ? 'Bloque Oro' : type === 'silver' ? 'Bloque Plata' : 'Bloque Bronce';
});

// Watch active rigs to control fan sound
watch(activeRigsCount, (newCount) => {
  updateRigSound(newCount);
});

// Iniciar sonido de rigs en la primera interacción del usuario (si hay rigs activos)
// Esto es necesario porque el navegador bloquea audio sin interacción
const initRigSoundOnInteraction = () => {
  if (activeRigsCount.value > 0) {
    updateRigSound(activeRigsCount.value);
  }
  document.removeEventListener('click', initRigSoundOnInteraction);
  document.removeEventListener('keydown', initRigSoundOnInteraction);
};
document.addEventListener('click', initRigSoundOnInteraction, { once: true });
document.addEventListener('keydown', initRigSoundOnInteraction, { once: true });

// Slot functions
function openSlotPurchaseConfirm() {
  if (!canAffordSlot()) return;
  showConfirmSlotPurchase.value = true;
}

async function confirmBuySlot() {
  if (!authStore.player || !slotInfo.value?.next_upgrade || buyingSlot.value) return;

  buyingSlot.value = true;

  try {
    const result = await buyRigSlot(authStore.player.id);
    if (result?.success) {
      playSound('purchase');
      showConfirmSlotPurchase.value = false;
      await authStore.fetchPlayer();
      await miningStore.loadData();
    } else {
      playSound('error');
      alert(result?.error ?? 'Error comprando slot');
    }
  } catch (e) {
    console.error('Error buying slot:', e);
    playSound('error');
    alert('Error de conexión');
  } finally {
    buyingSlot.value = false;
  }
}

function canAffordSlot(): boolean {
  if (!slotInfo.value?.next_upgrade) return false;
  const upgrade = slotInfo.value.next_upgrade;
  if (upgrade.currency === 'gamecoin') {
    return (authStore.player?.gamecoin_balance ?? 0) >= upgrade.price;
  } else if (upgrade.currency === 'ron') {
    return (authStore.player?.ron_balance ?? 0) >= upgrade.price;
  }
  return (authStore.player?.crypto_balance ?? 0) >= upgrade.price;
}

function getSlotCurrencyIcon(currency: string): string {
  if (currency === 'ron') return '🔷';
  if (currency === 'crypto') return '💎';
  return '🪙';
}

function getSlotCurrencyName(currency: string): string {
  if (currency === 'ron') return 'RON';
  if (currency === 'crypto') return 'BLC';
  return 'GC';
}

// Open market modal via global event
function openMarket() {
  window.dispatchEvent(new CustomEvent('open-market'));
}

// Rig manage modal
function openRigManage(rig: typeof miningStore.rigs[0]) {
  selectedRigForManage.value = rig;
  showRigManage.value = true;
}

function closeRigManage() {
  showRigManage.value = false;
  selectedRigForManage.value = null;
}

async function handleRigUpdated() {
  await miningStore.loadData();
  refreshEstimate();
  // Update selected rig reference with fresh data
  if (selectedRigForManage.value) {
    const updatedRig = miningStore.rigs.find(r => r.id === selectedRigForManage.value?.id);
    if (updatedRig) {
      selectedRigForManage.value = updatedRig;
    }
  }
}

// Boost helpers
function getBoostIcon(boostType: string): string {
  switch (boostType) {
    case 'hashrate': return '⚡';
    case 'energy_saver': return '🔋';
    case 'bandwidth_optimizer': return '📶';
    case 'lucky_charm': return '🍀';
    case 'overclock': return '🚀';
    case 'coolant_injection': return '❄️';
    case 'durability_shield': return '🛡️';
    default: return '✨';
  }
}

function formatTimeRemaining(seconds: number): string {
  if (seconds <= 0) return t('inventory.boosts.expired', 'Expired');
  const mins = Math.floor(seconds / 60);
  const hrs = Math.floor(mins / 60);
  if (hrs > 0) {
    return `${hrs}h ${mins % 60}m`;
  }
  return `${mins}m`;
}

function getBoostName(id: string): string {
  const key = `market.items.boosts.${id}.name`;
  const translated = t(key);
  return translated !== key ? translated : id;
}

// Mining simulation (visual)
function startMiningSimulation() {
  if (miningInterval.value) return;

  miningInterval.value = window.setInterval(() => {
    if (totalHashrate.value > 0) {
      const progressIncrement = (totalHashrate.value / networkStats.value.difficulty) * 2;
      miningProgress.value = Math.min(100, miningProgress.value + progressIncrement);
      hashesCalculated.value += totalHashrate.value / 60;

      if (miningProgress.value >= 100) {
        miningProgress.value = 0;
      }
    } else {
      miningProgress.value = 0;
      hashesCalculated.value = 0;
    }
  }, 100);
}

function stopMiningSimulation() {
  if (miningInterval.value) {
    clearInterval(miningInterval.value);
    miningInterval.value = null;
  }
}

// Toggle rig
async function handleToggleRig(rigId: string) {
  const rig = rigs.value.find(r => r.id === rigId);
  if (!rig) return;

  // If rig is active, show confirmation modal
  if (rig.is_active) {
    rigToStop.value = rig;
    stopRigError.value = null;
    showConfirmStopRig.value = true;
    return;
  }

  // Turn on - handled by store
  await miningStore.toggleRig(rigId);
  refreshEstimate();
}

async function confirmStopRig() {
  if (!rigToStop.value || stoppingRig.value) return;

  stoppingRig.value = true;
  stopRigError.value = null;

  const result = await miningStore.toggleRig(rigToStop.value.id);

  if (!result.success) {
    stopRigError.value = result.error || t('mining.toggleError');
  } else {
    playSound('click');
    showConfirmStopRig.value = false;
    rigToStop.value = null;
    refreshEstimate();
  }

  stoppingRig.value = false;
}

function cancelStopRig() {
  showConfirmStopRig.value = false;
  rigToStop.value = null;
  stopRigError.value = null;
}

// Block mined handler
function handleBlockMined(event: CustomEvent) {
  const { block, winner } = event.detail;
  miningStore.handleBlockMined(block, winner);

  if (winner?.id === authStore.player?.id) {
    lastBlockFound.value = block;
    showBlockFound.value = true;
    miningProgress.value = 100;

    setTimeout(() => {
      showBlockFound.value = false;
      miningProgress.value = 0;
    }, 3000);
  }
}

// UI Helpers
function getTierColor(tier: string): string {
  switch (tier) {
    case 'elite': return 'text-rank-diamond';
    case 'advanced': return 'text-rank-gold';
    case 'standard': return 'text-rank-silver';
    default: return 'text-rank-bronze';
  }
}

function getRigName(id: string): string {
  const key = `market.items.rigs.${id}.name`;
  const translated = t(key);
  if (translated !== key) return translated;
  // Fallback to rig name from store data
  const playerRig = rigs.value.find(r => r.rig.id === id);
  return playerRig?.rig.name ?? id;
}

// Get upgraded hashrate using bonus from backend (base * (1 + bonus%))
function getUpgradedHashrate(playerRig: typeof miningStore.rigs[0]): number {
  const bonus = playerRig.hashrate_bonus ?? 0;
  return Math.round(playerRig.rig.hashrate * (1 + bonus / 100));
}

// Get upgraded power consumption using bonus from backend (base * (1 - bonus%))
function getUpgradedPower(playerRig: typeof miningStore.rigs[0]): number {
  const bonus = playerRig.efficiency_bonus ?? 0;
  return playerRig.rig.power_consumption * (1 - bonus / 100);
}

// Get thermal bonus (°C reduction) from backend
function getThermalBonus(playerRig: typeof miningStore.rigs[0]): number {
  return playerRig.thermal_bonus ?? 0;
}

// Get hashrate bonus percentage for display
function getHashrateBonus(playerRig: typeof miningStore.rigs[0]): number {
  return playerRig.hashrate_bonus ?? 0;
}

// Get efficiency bonus percentage for display
function getEfficiencyBonus(playerRig: typeof miningStore.rigs[0]): number {
  return playerRig.efficiency_bonus ?? 0;
}

function getTempColor(temp: number): string {
  if (temp >= 80) return 'text-status-danger';
  if (temp >= 60) return 'text-status-warning';
  if (temp >= 40) return 'text-yellow-400';
  return 'text-status-success';
}

// Get total cooling energy cost for a rig (weighted by durability)
function getRigCoolingEnergy(rigId: string): number {
  const cooling = rigCooling.value[rigId];
  if (!cooling || cooling.length === 0) return 0;
  return cooling.reduce((sum: number, c: any) => sum + (c.energy_cost * c.durability / 100), 0);
}

// Get total cooling power for a rig (sum of all cooling items, weighted by durability)
function getRigTotalCoolingPower(rigId: string): number {
  const cooling = rigCooling.value[rigId];
  if (!cooling || cooling.length === 0) return 0;
  return cooling.reduce((sum: number, c: any) => sum + (c.cooling_power * c.durability / 100), 0);
}

// Check if any cooling is degraded
function isAnyCoolingDegraded(rigId: string): boolean {
  const cooling = rigCooling.value[rigId];
  if (!cooling || cooling.length === 0) return false;
  return cooling.some((c: any) => miningStore.isCoolingDegraded(c.durability));
}

function getTempBarColor(temp: number): string {
  if (temp >= 80) return 'bg-status-danger';
  if (temp >= 60) return 'bg-status-warning';
  if (temp >= 40) return 'bg-yellow-400';
  return 'bg-status-success';
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

function formatTimeAgo(dateStr: string): string {
  const date = new Date(dateStr).getTime();
  const now = Date.now();
  const diff = Math.max(0, now - date);

  const seconds = Math.floor(diff / 1000);
  const minutes = Math.floor(seconds / 60);
  const hours = Math.floor(minutes / 60);

  if (hours > 0) return `${hours}h`;
  if (minutes > 0) return `${minutes}m`;
  return `${seconds}s`;
}

// Uptime timer
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
  miningStore.loadData();
  miningStore.subscribeToRealtime();
  startMiningSimulation();
  startUptimeTimer();
  requestWakeLock();

  // Nuevo sistema de shares
  miningStore.loadMiningBlockInfo();
  miningStore.loadPlayerShares();
  miningStore.subscribeToMiningBlocks();

  // Actualizar bloque info cada segundo para countdown
  setInterval(() => {
    miningStore.loadMiningBlockInfo();
  }, 1000);

  // Actualizar shares del jugador cada 30 segundos (respaldo por si realtime falla)
  setInterval(() => {
    miningStore.loadPlayerShares();
  }, 30000);

  window.addEventListener('block-mined', handleBlockMined as EventListener);

  // Initialize AdSense
  nextTick(() => {
    try {
      ((window as any).adsbygoogle = (window as any).adsbygoogle || []).push({});
    } catch (e) {
      console.error('AdSense error:', e);
    }
  });
});

onUnmounted(() => {
  stopMiningSimulation();
  stopUptimeTimer();
  stopRigSound();
  miningStore.unsubscribeFromRealtime();
  releaseWakeLock();

  // Limpiar listeners de inicialización de sonido (si aún no se ejecutaron)
  document.removeEventListener('click', initRigSoundOnInteraction);
  document.removeEventListener('keydown', initRigSoundOnInteraction);

  window.removeEventListener('block-mined', handleBlockMined as EventListener);
});
</script>

<template>
  <div>
    <!-- Header -->
    <div class="flex items-center justify-between mb-6">
      <h1 class="text-2xl font-display font-bold">
        <span class="gradient-text">{{ t('mining.title') }}</span>
      </h1>
      <div class="flex items-center gap-3">
        <span class="badge" :class="activeRigsCount > 0 ? 'badge-success' : 'badge-warning'">
          {{ t('mining.activeRigs', { count: activeRigsCount }) }}
        </span>
      </div>
    </div>

    <!-- Active Boosts Bar -->
    <div v-if="activeBoosts.length > 0" class="mb-4">
      <div class="flex flex-wrap gap-2">
        <div v-for="boost in activeBoosts" :key="boost.id"
          class="flex items-center gap-2 px-3 py-1.5 rounded-lg bg-purple-500/20 border border-purple-500/30">
          <span>{{ getBoostIcon(boost.boost_type) }}</span>
          <span class="text-sm font-medium text-purple-400">{{ getBoostName(boost.boost_id) }}</span>
          <span class="text-xs text-text-muted">{{ formatTimeRemaining(boost.seconds_remaining) }}</span>
        </div>
      </div>
    </div>

    <!-- Primera carga - solo si no hay datos en cache -->
    <div v-if="loading && !dataLoaded" class="text-center py-20 text-text-muted">
      <div
        class="w-12 h-12 mx-auto rounded-xl bg-gradient-primary flex items-center justify-center text-2xl animate-pulse mb-4">
        ⛏️
      </div>
      {{ t('mining.loadingStation') }}
    </div>

    <!-- Contenido (con datos en cache o cargados) -->
    <div v-else class="space-y-6">
      <!-- Bloque Actual - Dashboard Unificado -->
      <div class="card relative overflow-hidden">
        <div v-if="totalHashrate > 0"
          class="absolute inset-0 bg-gradient-to-r from-accent-primary/5 via-accent-secondary/5 to-accent-primary/5 animate-pulse">
        </div>

        <div class="relative z-10">
          <!-- Header -->
          <div class="flex items-center justify-between mb-4">
            <div class="flex items-center gap-3">
              <div class="w-14 h-14 rounded-xl flex items-center justify-center text-3xl"
                :class="totalHashrate > 0 ? 'bg-gradient-primary animate-pulse' : 'bg-bg-tertiary'">
                ⛏️
              </div>
              <div>
                <div class="flex items-center gap-2">
                  <h2 class="text-lg font-semibold">
                    <span v-if="currentMiningBlock?.active" v-tooltip="'Número secuencial del bloque que se está minando ahora. Cada bloque dura ~30 minutos.'" class="cursor-help">Bloque Actual #{{ currentMiningBlock.block_number }}</span>
                    <span v-else>Centro de Minería</span>
                  </h2>
                  <span v-if="isPremium"
                    class="px-2 py-0.5 text-xs font-medium bg-amber-500/20 text-amber-400 border border-amber-500/30 rounded-full flex items-center gap-1 cursor-help"
                    v-tooltip="'Como usuario Premium, recibes +50% extra en cada recompensa de bloque'">
                    <span>👑</span>
                    <span>+50% Bonus</span>
                  </span>
                  <!-- Tooltip educativo -->
                  <button
                    class="text-text-muted hover:text-accent-primary transition-colors"
                    v-tooltip="'Sistema de minería por shares: Tu recompensa es proporcional a las shares que generas. Más hashrate = más shares = más recompensa.'"
                  >
                    <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                      <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clip-rule="evenodd"/>
                    </svg>
                  </button>
                </div>
                <p class="text-sm text-text-muted cursor-help"
                  v-tooltip="totalHashrate > 0
                    ? 'Tus rigs están activos generando shares que se convierten en recompensas al cierre del bloque'
                    : 'Necesitas encender al menos un rig para empezar a minar y generar shares'">
                  {{ totalHashrate > 0 ? 'Generando shares' : 'Activa tus rigs para empezar' }}
                </p>
              </div>
            </div>

            <div class="text-right cursor-help"
              v-tooltip="effectiveHashrate < totalHashrate
                ? `Tu hashrate real después de penalizaciones. Base: ${totalHashrate.toLocaleString()} H/s, reducido por temperatura o condición de tus rigs.`
                : 'Tu hashrate total combinado de todos los rigs activos. Determina cuántas shares generas por minuto.'">
              <div class="text-3xl font-bold font-mono"
                :class="effectiveHashrate > 0 ? 'gradient-text' : 'text-text-muted'">
                {{ Math.round(effectiveHashrate).toLocaleString() }}
              </div>
              <div class="text-xs text-text-muted flex items-center justify-end gap-1">
                <span>H/s efectivo</span>
                <span v-if="effectiveHashrate < totalHashrate" class="text-status-danger">
                  (↓{{ Math.round(((totalHashrate - effectiveHashrate) / totalHashrate) * 100) }}%)
                </span>
              </div>
            </div>
          </div>

          <!-- Estado: Sin bloque activo -->
          <div v-if="!currentMiningBlock?.active" class="text-center py-8 text-text-muted">
            <div class="text-4xl mb-3">⏳</div>
            <div class="text-lg font-medium mb-1">Esperando nuevo bloque...</div>
            <div class="text-sm">El próximo bloque se iniciará automáticamente</div>
          </div>

          <!-- Estado: Con bloque activo -->
          <div v-else>
            <!-- Info de Red (Dificultad, etc) -->
            <div class="grid grid-cols-2 md:grid-cols-4 gap-2 mb-4 p-3 bg-bg-tertiary/50 rounded-lg">
              <div v-tooltip="'Mayor dificultad = menos shares por H/s. Se ajusta automáticamente cada bloque.'" class="text-center cursor-help">
                <div class="text-xs text-text-muted mb-1">🎯 Dificultad</div>
                <div class="text-base font-bold font-mono text-cyan-400">
                  {{ (currentMiningBlock.difficulty / 1000).toFixed(1) }}K
                </div>
              </div>
              <div v-tooltip="'Hashrate combinado de todos los mineros activos en la red'" class="text-center cursor-help">
                <div class="text-xs text-text-muted mb-1">🌐 Hashrate Red</div>
                <div class="text-base font-bold font-mono text-purple-400">
                  {{ (networkStats.hashrate / 1000).toFixed(1) }}K
                </div>
              </div>
              <div v-tooltip="'Número de mineros con rigs activos en este momento'" class="text-center cursor-help">
                <div class="text-xs text-text-muted mb-1">👥 Mineros</div>
                <div class="text-base font-bold font-mono text-emerald-400">
                  {{ networkStats.activeMiners }}
                </div>
              </div>
              <div v-tooltip="'Tu hashrate efectivo como % del total de la red. Mayor % = más shares'" class="text-center cursor-help">
                <div class="text-xs text-text-muted mb-1">⚡ Tu Potencia</div>
                <div class="text-base font-bold font-mono text-amber-400">
                  {{ networkStats.hashrate > 0 ? ((effectiveHashrate / networkStats.hashrate) * 100).toFixed(2) : '0.00' }}%
                </div>
              </div>
            </div>

            <!-- Indicador Dual: Tiempo + Actividad de Red -->
            <div class="mb-4 p-4 bg-bg-secondary rounded-xl border border-border/30"
              :class="{
                'border-status-danger': timeRemainingAlert === 'critical',
                'border-status-warning': timeRemainingAlert === 'warning'
              }">
              <!-- Header con tiempo restante -->
              <div class="flex items-center justify-between mb-3">
                <div class="flex items-center gap-2 cursor-help"
                  v-tooltip="'Tiempo restante para que este bloque se cierre y se repartan las recompensas. Cada bloque dura 30 minutos.'">
                  <span class="text-2xl">⏰</span>
                  <div>
                    <div class="text-sm text-text-muted">Cierre del Bloque</div>
                    <div class="text-2xl font-bold font-mono"
                      :class="{
                        'text-status-danger': timeRemainingAlert === 'critical',
                        'text-status-warning': timeRemainingAlert === 'warning',
                        'text-blue-400': timeRemainingAlert === 'normal'
                      }">
                      {{ blockTimeRemaining }}
                    </div>
                  </div>
                </div>
                <div v-if="timeRemainingAlert === 'critical'"
                  class="px-3 py-1 bg-status-danger/20 border border-status-danger/50 rounded-lg animate-pulse">
                  <span class="text-status-danger font-semibold text-sm">⚠️ ¡Cierra pronto!</span>
                </div>
              </div>

              <!-- Barra de progreso del tiempo -->
              <div class="h-3 bg-bg-tertiary rounded-full overflow-hidden relative mb-3">
                <div
                  class="h-full transition-all duration-1000"
                  :class="{
                    'bg-gradient-to-r from-status-danger to-red-400': timeRemainingAlert === 'critical',
                    'bg-gradient-to-r from-status-warning to-amber-400': timeRemainingAlert === 'warning',
                    'bg-gradient-to-r from-accent-primary to-purple-500': timeRemainingAlert === 'normal'
                  }"
                  :style="{ width: `${Math.max(0, 100 - (currentMiningBlock.time_remaining_seconds / 1800 * 100))}%` }"
                ></div>
                <div v-if="totalHashrate > 0"
                  class="absolute inset-0 bg-gradient-to-r from-transparent via-white/10 to-transparent"
                  style="animation: shimmer 2s linear infinite;">
                </div>
              </div>

              <!-- Info secundaria: actividad de red -->
              <div class="flex items-center justify-between text-xs">
                <div class="flex items-center gap-4">
                  <span class="text-text-muted cursor-help"
                    v-tooltip="'Shares generadas por todos los mineros vs el objetivo del bloque. El objetivo es una meta de referencia para medir la actividad de la red.'">
                    📊 Actividad: <span class="font-mono text-text-secondary">{{ currentMiningBlock.total_shares.toFixed(0) }} / {{ currentMiningBlock.target_shares }}</span> shares ({{ sharesProgress.toFixed(0) }}%)
                  </span>
                  <span class="text-text-muted cursor-help"
                    v-tooltip="'Velocidad a la que la red está generando shares. Alto = muchos mineros activos, Bajo = pocos mineros.'">
                    ⚡ Ritmo: <span class="font-mono"
                      :class="{
                        'text-status-success': sharesProgress > 90,
                        'text-status-warning': sharesProgress >= 70 && sharesProgress <= 90,
                        'text-status-danger': sharesProgress < 70
                      }">
                      {{ sharesProgress > 90 ? 'Alto' : sharesProgress >= 70 ? 'Normal' : 'Bajo' }}
                    </span>
                  </span>
                </div>
                <span class="text-text-muted cursor-help"
                  v-tooltip="'Jugadores con al menos un rig encendido minando en este momento'">
                  👥 {{ networkStats.activeMiners }} mineros activos
                </span>
              </div>
            </div>

            <!-- Grid de 5 Stats -->
            <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-5 gap-3">
              <!-- Velocidad -->
              <div v-tooltip="'Velocidad a la que generas tu porción del bloque. Basada en tu hashrate efectivo y la dificultad actual.'"
                class="bg-bg-secondary rounded-xl p-3 border-l-4 border-accent-primary cursor-help">
                <div class="flex items-center gap-1 mb-1">
                  <span class="text-base">⚡</span>
                  <div class="text-[10px] text-text-muted">Velocidad</div>
                </div>
                <div class="text-xl font-bold font-mono text-accent-primary">
                  {{ sharesRate < 1 ? '🐌 Lento' : sharesRate < 3 ? '🚶 Normal' : '🚀 Rápido' }}
                </div>
                <div class="text-[10px] text-text-muted">{{ sharesRate.toFixed(1) }}/min</div>
                <div v-if="sharesEfficiency !== 100" class="mt-0.5 text-[10px]"
                  :class="sharesEfficiency > 100 ? 'text-status-success' : 'text-status-warning'">
                  {{ sharesEfficiency > 100 ? '↑' : '↓' }}{{ Math.abs(sharesEfficiency - 100) }}%
                </div>
              </div>

              <!-- % del Bloque -->
              <div v-tooltip="'Tu participación en el bloque actual. Más % = mayor recompensa al cierre.'"
                class="bg-bg-secondary rounded-xl p-3 border-l-4 border-purple-500 cursor-help">
                <div class="flex items-center gap-1 mb-1">
                  <span class="text-base">📊</span>
                  <div class="text-[10px] text-text-muted">% del Bloque</div>
                </div>
                <div class="text-xl font-bold font-mono text-purple-400">
                  {{ playerSharePercentage.toFixed(1) }}%
                </div>
                <div class="text-[10px] text-text-muted">tu participación</div>
                <div v-if="playerSharePercentage > 0" class="mt-0.5 text-[10px] text-status-info">
                  Top {{ Math.min(100, Math.round((100 - playerSharePercentage) + playerSharePercentage / 2)) }}%
                </div>
              </div>

              <!-- Contribución Relativa -->
              <div v-tooltip="'Tu posición relativa respecto al promedio. Verde = por encima, Amarillo = promedio, Rojo = por debajo.'"
                class="bg-bg-secondary rounded-xl p-3 border-l-4 border-emerald-500 cursor-help">
                <div class="flex items-center gap-1 mb-1">
                  <span class="text-base">📈</span>
                  <div class="text-[10px] text-text-muted">Contribución</div>
                </div>
                <div class="text-xl font-bold font-mono"
                  :class="{
                    'text-status-success': playerSharePercentage > (100 / Math.max(1, networkStats.activeMiners)) * 1.5,
                    'text-status-warning': playerSharePercentage > (100 / Math.max(1, networkStats.activeMiners)) * 0.5,
                    'text-status-danger': playerSharePercentage <= (100 / Math.max(1, networkStats.activeMiners)) * 0.5
                  }">
                  {{ playerSharePercentage > (100 / Math.max(1, networkStats.activeMiners)) * 1.5 ? '🔥 Alta' :
                     playerSharePercentage > (100 / Math.max(1, networkStats.activeMiners)) * 0.5 ? '✓ Media' : '📉 Baja' }}
                </div>
                <div class="text-[10px] text-text-muted">vs promedio</div>
                <div class="mt-0.5 text-[10px] text-text-muted">
                  {{ (100 / Math.max(1, networkStats.activeMiners)).toFixed(1) }}% base
                </div>
              </div>

              <!-- Tu Recompensa -->
              <div v-tooltip="'Tu recompensa estimada al cierre del bloque. Basada en tu % actual de participación.'"
                class="bg-bg-secondary rounded-xl p-3 border-l-4 border-amber-500 cursor-help">
                <div class="flex items-center gap-1 mb-1">
                  <span class="text-base">💰</span>
                  <div class="text-[10px] text-text-muted">Tu Recompensa</div>
                </div>
                <div class="text-xl font-bold font-mono text-amber-400">
                  {{ estimatedReward.toFixed(3) }}
                </div>
                <div class="text-[10px] text-text-muted">₿ estimado</div>
                <div class="mt-0.5 text-[10px] text-text-muted">
                  {{ playerSharePercentage.toFixed(1) }}% del pool
                </div>
              </div>

              <!-- Pool Total con Tipo de Bloque -->
              <div v-tooltip="`Recompensa total del bloque que se repartirá proporcionalmente. ${blockTypeLabel}: ${currentMiningBlock.reward} BLC. Premium players reciben +50% bonus en su parte.`"
                class="bg-bg-secondary rounded-xl p-3 border-l-4 cursor-help"
                :class="{
                  'border-amber-600': currentMiningBlock.block_type === 'bronze',
                  'border-gray-400': currentMiningBlock.block_type === 'silver',
                  'border-yellow-400': currentMiningBlock.block_type === 'gold'
                }">
                <div class="flex items-center gap-1 mb-1">
                  <span class="text-base">{{ blockTypeEmoji }}</span>
                  <div class="text-[10px] text-text-muted">{{ blockTypeLabel }}</div>
                </div>
                <div class="text-xl font-bold font-mono"
                  :class="{
                    'text-amber-600': currentMiningBlock.block_type === 'bronze',
                    'text-gray-300': currentMiningBlock.block_type === 'silver',
                    'text-yellow-400': currentMiningBlock.block_type === 'gold'
                  }">
                  {{ currentMiningBlock.reward.toFixed(1) }}
                </div>
                <div class="text-[10px] text-text-muted">₿ a repartir</div>
                <div class="mt-0.5 text-[10px] text-text-muted">
                  {{ networkStats.activeMiners }} mineros
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Block Found Celebration -->
        <div v-if="showBlockFound"
          class="absolute inset-0 bg-status-success/20 flex items-center justify-center z-20 animate-fade-in">
          <div class="text-center">
            <div class="text-6xl mb-4 animate-bounce">🎉</div>
            <div class="text-2xl font-bold text-status-success">{{ t('mining.blockMined') }}</div>
            <div class="text-lg text-white">#{{ lastBlockFound?.height }}</div>
          </div>
        </div>
      </div>

      <div class="grid lg:grid-cols-3 gap-6">
        <!-- Rigs Column -->
        <div class="lg:col-span-2 space-y-4">
          <h2 class="text-lg font-semibold flex items-center gap-2">
            <span>🖥️</span> {{ t('mining.yourRigs') }}
            <span v-if="slotInfo" class="text-sm font-normal px-2 py-0.5 rounded-full"
              :class="slotInfo.available_slots === 0 ? 'bg-status-warning/20 text-status-warning' : 'bg-accent-primary/20 text-accent-primary'">
              {{ slotInfo.used_slots }}/{{ slotInfo.current_slots }}
            </span>
          </h2>

          <div v-if="rigs.length === 0" class="card text-center py-12">
            <div class="text-4xl mb-4">🛒</div>
            <p class="text-text-muted mb-4">{{ t('mining.noRigs') }}</p>
            <button @click="openMarket" class="btn-primary">
              {{ t('mining.goToMarket') }}
            </button>
          </div>

          <div v-else class="grid sm:grid-cols-2 gap-4">
            <div v-for="playerRig in rigs" :key="playerRig.id"
              class="bg-bg-secondary/80 rounded-xl border p-4 relative overflow-hidden"
              :class="playerRig.condition <= 0 ? 'border-status-danger/70' : playerRig.condition < 30 ? 'border-status-warning/50' : 'border-border/30'">
              <!-- Mining indicator dot -->
              <div v-if="playerRig.is_active" class="absolute top-3 right-3">
                <span class="relative flex h-2.5 w-2.5">
                  <span
                    class="animate-ping absolute inline-flex h-full w-full rounded-full bg-status-success opacity-75"></span>
                  <span class="relative inline-flex rounded-full h-2.5 w-2.5 bg-status-success"></span>
                </span>
              </div>

              <!-- Header -->
              <div class="flex items-center justify-between mb-3">
                <div class="flex items-center gap-2">
                  <h3 class="font-semibold" :class="getTierColor(playerRig.rig.tier)">
                    {{ getRigName(playerRig.rig.id) }}
                  </h3>
                </div>
                <div class="flex items-center gap-2">
                  <!-- Upgrade levels indicator -->
                  <div
                    v-if="(playerRig.hashrate_level ?? 1) > 1 || (playerRig.efficiency_level ?? 1) > 1 || (playerRig.thermal_level ?? 1) > 1"
                    v-tooltip="t('mining.tooltips.upgrades') + ` - ⚡${playerRig.hashrate_level ?? 1} 💡${playerRig.efficiency_level ?? 1} ❄️${playerRig.thermal_level ?? 1}`"
                    class="flex items-center gap-1 text-[10px] px-1.5 py-0.5 bg-purple-500/20 rounded cursor-help">
                    <span v-if="(playerRig.hashrate_level ?? 1) > 1" class="text-yellow-400">⚡{{
                      playerRig.hashrate_level }}</span>
                    <span v-if="(playerRig.efficiency_level ?? 1) > 1" class="text-green-400">💡{{
                      playerRig.efficiency_level }}</span>
                    <span v-if="(playerRig.thermal_level ?? 1) > 1" class="text-cyan-400">❄️{{ playerRig.thermal_level
                      }}</span>
                  </div>
                  <span v-tooltip="t('mining.tooltips.tier')"
                    class="text-[11px] text-text-muted uppercase px-2 py-0.5 bg-bg-tertiary/50 rounded cursor-help">
                    {{ playerRig.rig.tier }}
                  </span>
                </div>
              </div>

              <!-- Hashrate -->
              <div v-tooltip="t('mining.tooltips.hashrate')" class="flex items-baseline gap-1.5 mb-3 cursor-help">
                <span class="text-xl font-bold font-mono" :class="playerRig.is_active
                  ? (miningStore.getRigHashrateBoostPercent(playerRig) > 0
                    ? 'text-status-success'
                    : miningStore.getRigPenaltyPercent(playerRig) > 0
                      ? 'text-status-warning'
                      : 'text-white')
                  : 'text-text-muted'" :key="uptimeKey">
                  {{ playerRig.is_active ? Math.round(miningStore.getRigEffectiveHashrate(playerRig)).toLocaleString() :
                  '0' }}
                </span>
                <span class="text-sm text-text-muted">
                  / {{ getUpgradedHashrate(playerRig).toLocaleString() }} H/s
                  <span v-if="(playerRig.hashrate_level ?? 1) > 1" class="text-yellow-400 text-xs">(+{{
                    getHashrateBonus(playerRig) }}%)</span>
                </span>
                <span v-if="playerRig.is_active && miningStore.getRigHashrateBoostPercent(playerRig) > 0"
                  class="text-xs text-status-success font-medium">
                  (+{{ miningStore.getRigHashrateBoostPercent(playerRig) }}% ⚡)
                </span>
              </div>

              <!-- Stats row -->
              <div class="flex items-center gap-4 text-xs text-text-muted mb-3">
                <span v-tooltip="t('mining.tooltips.energy')" class="flex items-center gap-1 cursor-help">
                  <span class="text-status-warning">⚡</span>{{ (getUpgradedPower(playerRig) +
                    getRigCoolingEnergy(playerRig.id)).toFixed(0) }}/t
                  <span v-if="(playerRig.efficiency_level ?? 1) > 1" class="text-green-400">(-{{
                    getEfficiencyBonus(playerRig) }}%)</span>
                  <span v-if="miningStore.getPowerPenaltyPercent(playerRig) > 0" class="text-status-danger">(+{{
                    miningStore.getPowerPenaltyPercent(playerRig) }}%)</span>
                </span>
                <span v-tooltip="t('mining.tooltips.internet')" class="flex items-center gap-1 cursor-help">
                  <span class="text-accent-tertiary">📡</span>{{ (playerRig.rig.internet_consumption * (1 - (playerRig.efficiency_bonus ?? 0) / 100)).toFixed(0) }}/t
                  <span v-if="(playerRig.efficiency_level ?? 1) > 1" class="text-green-400">(-{{
                    getEfficiencyBonus(playerRig) }}%)</span>
                </span>
                <span v-if="rigCooling[playerRig.id]?.length > 0 || getThermalBonus(playerRig) > 0"
                  v-tooltip="t('mining.tooltips.cooling')" class="flex items-center gap-1 cursor-help">
                  <span :class="isAnyCoolingDegraded(playerRig.id) ? 'text-status-warning' : 'text-cyan-400'">❄️</span>
                  <span :class="isAnyCoolingDegraded(playerRig.id) ? 'text-status-warning' : 'text-cyan-400'">
                    -{{ (getRigTotalCoolingPower(playerRig.id) + getThermalBonus(playerRig)).toFixed(0) }}°
                  </span>
                  <span v-if="getThermalBonus(playerRig) > 0" class="text-cyan-300 text-[10px]">(⬆{{
                    getThermalBonus(playerRig) }}°)</span>
                  <span v-if="isAnyCoolingDegraded(playerRig.id)" class="text-status-warning text-[10px]">
                    ⚠️
                  </span>
                </span>
                <span v-if="rigBoosts[playerRig.id]?.length > 0"
                  v-tooltip="t('mining.tooltips.boosts') + ': ' + rigBoosts[playerRig.id].map((b: any) => b.name).join(', ')"
                  class="flex items-center gap-1 cursor-help">
                  <span class="text-purple-400">🚀</span>
                  <span class="text-purple-400">{{ rigBoosts[playerRig.id].length }}</span>
                </span>
                <span v-if="playerRig.is_active && playerRig.activated_at" v-tooltip="t('mining.tooltips.uptime')"
                  class="flex items-center gap-1 ml-auto cursor-help" :key="uptimeKey">
                  ⏱️ {{ formatUptime(playerRig.activated_at) }}
                </span>
              </div>

              <!-- Bars -->
              <div class="space-y-2 mb-3">
                <!-- Temperature -->
                <div v-tooltip="t('mining.tooltips.temperature')" class="flex items-center gap-2 cursor-help">
                  <span class="text-xs text-text-muted w-6">🌡️</span>
                  <div class="flex-1 h-2 bg-bg-tertiary rounded-full overflow-hidden">
                    <div class="h-full rounded-full transition-all"
                      :class="getTempBarColor(playerRig.temperature ?? 25)"
                      :style="{ width: `${playerRig.temperature ?? 25}%` }"></div>
                  </div>
                  <span class="text-xs w-14 text-right" :class="getTempColor(playerRig.temperature ?? 25)">
                    {{ (playerRig.temperature ?? 25).toFixed(0) }}°C
                  </span>
                </div>
                <!-- Condition -->
                <div v-tooltip="t('mining.tooltips.condition')" class="flex items-center gap-2 cursor-help">
                  <span class="text-xs text-text-muted w-6">🔧</span>
                  <div class="flex-1 h-2 bg-bg-tertiary rounded-full overflow-hidden relative">
                    <!-- 80% threshold marker -->
                    <div class="absolute top-0 bottom-0 w-px bg-white/30 z-10" style="left: 80%"></div>
                    <div class="h-full rounded-full"
                      :class="playerRig.condition >= 80 ? 'bg-status-success' : playerRig.condition > 20 ? 'bg-status-warning' : 'bg-status-danger'"
                      :style="{ width: `${playerRig.condition}%` }"></div>
                  </div>
                  <span class="text-xs w-14 text-right"
                    :class="playerRig.condition < 80 ? (playerRig.condition < 30 ? 'text-status-danger' : 'text-status-warning') : 'text-text-muted'">
                    {{ playerRig.condition }}%
                  </span>
                </div>
              </div>

              <!-- Action buttons -->
              <div class="flex gap-2">
                <button @click="handleToggleRig(playerRig.id)" :disabled="playerRig.condition <= 0"
                  class="flex-1 py-2 rounded-lg text-sm font-medium transition-all disabled:opacity-50" :class="playerRig.condition <= 0
                    ? 'bg-status-danger/10 text-status-danger cursor-not-allowed'
                    : playerRig.is_active
                      ? 'bg-status-danger/10 text-status-danger hover:bg-status-danger/20'
                      : 'bg-status-success/10 text-status-success hover:bg-status-success/20'">
                  {{ playerRig.condition <= 0 ? '🔧 ' + t('mining.repairInInventory') : (playerRig.is_active ? '⏹ ' +
                    t('mining.stop') : '▶ ' + t('mining.start')) }} </button>
                    <button @click="openRigManage(playerRig)"
                      class="px-3 py-2 rounded-lg text-sm font-medium transition-all bg-bg-tertiary hover:bg-bg-tertiary/80 text-text-muted hover:text-white"
                      :title="t('mining.manage')">
                      ⚙️
                    </button>
              </div>
            </div>

            <!-- Empty Available Slots -->
            <div v-for="n in (slotInfo?.available_slots ?? 0)" :key="'empty-slot-' + n"
              class="bg-bg-secondary/50 rounded-xl border border-dashed border-border/50 p-4 flex flex-col items-center justify-center min-h-[200px]">
              <div
                class="w-12 h-12 rounded-lg bg-bg-tertiary/50 flex items-center justify-center text-2xl mb-3 opacity-50">
                🖥️
              </div>
              <div class="text-text-muted font-medium">{{ t('slots.available', 'Disponible') }}</div>
              <p class="text-xs text-text-muted/70 mt-1">{{ t('slots.buyRigToUse', 'Compra un rig en el mercado') }}</p>
            </div>

            <!-- Slot Purchase Card -->
            <div v-if="slotInfo?.next_upgrade"
              class="bg-bg-secondary/80 rounded-xl border border-dashed border-accent-primary/50 p-4 flex flex-col justify-between min-h-[200px]">
              <div>
                <div class="flex items-center gap-2 mb-3">
                  <div class="w-10 h-10 rounded-lg bg-accent-primary/20 flex items-center justify-center text-xl">
                    ➕
                  </div>
                  <div>
                    <h3 class="font-semibold text-accent-primary">{{ slotInfo.next_upgrade.name }}</h3>
                    <p class="text-xs text-text-muted">{{ t('slots.unlockNewSlot', 'Desbloquea un nuevo slot') }}</p>
                  </div>
                </div>

                <div class="text-center py-3">
                  <div class="text-2xl font-bold" :class="canAffordSlot() ? 'text-status-success' : 'text-text-muted'">
                    <span>{{ getSlotCurrencyIcon(slotInfo.next_upgrade.currency) }}</span>
                    {{ slotInfo.next_upgrade.price.toLocaleString() }}
                    <span class="text-sm">{{ getSlotCurrencyName(slotInfo.next_upgrade.currency) }}</span>
                  </div>
                </div>
              </div>

              <button @click="openSlotPurchaseConfirm" :disabled="!canAffordSlot()"
                class="w-full py-2.5 rounded-lg text-sm font-semibold transition-all" :class="canAffordSlot()
                  ? 'bg-gradient-primary hover:opacity-90'
                  : 'bg-bg-tertiary text-text-muted cursor-not-allowed'">
                <span v-if="!canAffordSlot()">
                  {{ t('slots.insufficientFunds', 'Fondos insuficientes') }}
                </span>
                <span v-else>
                  {{ t('slots.buySlot', 'Comprar Slot') }}
                </span>
              </button>
            </div>

            <!-- Max slots reached card -->
            <div v-else-if="slotInfo && !slotInfo.next_upgrade"
              class="bg-status-success/10 rounded-xl border border-status-success/30 p-4 flex flex-col items-center justify-center min-h-[200px]">
              <div class="text-4xl mb-2">🏆</div>
              <div class="text-status-success font-semibold text-center">{{ t('slots.maxReached', '¡Máximo alcanzado!')
                }}</div>
              <div class="text-sm text-text-muted">{{ slotInfo.max_slots }} slots</div>
            </div>
          </div>
        </div>

        <!-- Sidebar -->
        <div class="space-y-4">
          <!-- Recent Blocks -->
          <div class="card p-3">
            <h3 class="text-sm font-semibold mb-2 flex items-center gap-1.5 text-text-muted">
              <span>📦</span> Bloques Recientes
            </h3>

            <div v-if="recentBlocks.length === 0" class="text-center py-4 text-text-muted text-xs">
              No hay bloques recientes
            </div>

            <div v-else class="space-y-1.5">
              <div v-for="(block, index) in recentBlocks" :key="block.id" class="px-2.5 py-2 rounded-lg" :class="[
                block.player_participation?.participated
                  ? 'bg-status-success/10 border border-status-success/20'
                  : 'bg-bg-secondary/50'
              ]">
                <!-- Row 1: Block number + Time -->
                <div class="flex items-center justify-between mb-1">
                  <div class="flex items-center gap-1.5">
                    <span v-if="index === 0" class="text-xs" v-tooltip="'Bloque más reciente'">🆕</span>
                    <span v-if="block.player_participation?.participated" class="text-xs cursor-help" v-tooltip="'Participaste en este bloque'">⭐</span>
                    <span v-if="block.player_participation?.is_premium" class="text-xs cursor-help" v-tooltip="'Eras Premium - Recibiste +50% de bonus'">👑</span>
                    <span class="text-sm font-medium cursor-help"
                      :class="block.player_participation?.participated ? 'text-status-success' : 'text-accent-primary'"
                      v-tooltip="block.player_participation?.participated
                        ? 'Participaste en este bloque y recibiste recompensa proporcional a tus shares'
                        : 'No participaste en este bloque. Mantén tus rigs encendidos para contribuir shares y ganar recompensas'">Bloque <span class="font-mono">#{{
                      block.block_number || block.height }}</span></span>
                  </div>
                  <span class="text-[10px] text-text-muted cursor-help" :key="uptimeKey"
                    v-tooltip="'Tiempo desde que se cerró este bloque y se distribuyeron las recompensas'">{{ formatTimeAgo(block.created_at)
                    }}</span>
                </div>

                <!-- Row 2: Si participaste -->
                <div v-if="block.player_participation?.participated" class="space-y-0.5">
                  <div class="flex items-center justify-between text-xs">
                    <span class="text-text-muted cursor-help" v-tooltip="'Tu porcentaje de shares respecto al total del bloque. Más shares = mayor recompensa'">Tu contribución</span>
                    <span class="font-mono text-status-success cursor-help" v-tooltip="'Aportaste el ' + block.player_participation.percentage.toFixed(1) + '% de las shares totales del bloque'">
                      {{ block.player_participation.percentage.toFixed(1) }}%
                    </span>
                  </div>
                  <div class="flex items-center justify-between text-xs">
                    <span class="text-text-muted cursor-help" v-tooltip="'El BLC que tú ganaste en este bloque, proporcional a tus shares'">Tu recompensa</span>
                    <span class="font-mono text-status-warning cursor-help" v-tooltip="block.player_participation.reward.toFixed(6) + ' BLC ganados en este bloque'">
                      +{{ block.player_participation.reward.toFixed(3) }} ₿
                    </span>
                  </div>
                  <div class="flex items-center justify-between text-xs">
                    <span class="text-text-muted cursor-help" v-tooltip="'Total de BLC distribuido a todos los participantes (incluye bonos premium)'">Total del bloque</span>
                    <span class="font-mono text-text-secondary cursor-help" v-tooltip="(block.total_distributed || block.reward || 0).toFixed(3) + ' BLC repartidos entre ' + (block.contributors_count || 0) + ' participantes'">
                      {{ (block.total_distributed || block.reward || 0).toFixed(1) }} ₿
                    </span>
                  </div>
                  <!-- Top contributor -->
                  <div v-if="block.top_contributor" class="flex items-center justify-between text-xs pt-0.5 border-t border-border/20">
                    <span class="text-text-muted flex items-center gap-1 cursor-help" v-tooltip="'El jugador que más shares aportó a este bloque'">
                      <span>🥇</span>
                      <span>{{ block.top_contributor.username }}</span>
                    </span>
                    <span class="font-mono text-amber-400 cursor-help" v-tooltip="block.top_contributor.username + ' aportó el ' + block.top_contributor.percentage.toFixed(1) + '% de las shares totales'">
                      {{ block.top_contributor.percentage.toFixed(1) }}%
                    </span>
                  </div>
                </div>

                <!-- Row 2: Si NO participaste -->
                <div v-else class="space-y-0.5">
                  <div class="flex items-center justify-between text-xs">
                    <span class="text-text-muted cursor-help" v-tooltip="'Cantidad de jugadores que minaron y aportaron shares a este bloque'">Contribuyentes</span>
                    <span class="font-mono" v-tooltip="(block.contributors_count || 0) + ' jugadores participaron en este bloque'">{{ block.contributors_count || 0 }}</span>
                  </div>
                  <div class="flex items-center justify-between text-xs">
                    <span class="text-text-muted cursor-help" v-tooltip="'Total de BLC repartido entre todos los participantes de este bloque (incluye bonos premium)'">Total distribuido</span>
                    <span class="font-mono text-status-warning" v-tooltip="'Recompensa total: ' + (block.total_distributed || block.reward || 0).toFixed(3) + ' BLC'">
                      {{ (block.total_distributed || block.reward || 0).toFixed(1) }} ₿
                    </span>
                  </div>
                  <!-- Top contributor -->
                  <div v-if="block.top_contributor" class="flex items-center justify-between text-xs pt-0.5 border-t border-border/20">
                    <span class="text-text-muted flex items-center gap-1 cursor-help" v-tooltip="'El jugador que más shares aportó a este bloque'">
                      <span>🥇</span>
                      <span>{{ block.top_contributor.username }}</span>
                    </span>
                    <span class="font-mono text-amber-400 cursor-help" v-tooltip="block.top_contributor.username + ' aportó el ' + block.top_contributor.percentage.toFixed(1) + '% de las shares totales'">
                      {{ block.top_contributor.percentage.toFixed(1) }}%
                    </span>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <!-- AdSense Banner -->
          <div class="card p-3 text-center">
            <div class="text-xs text-text-muted mb-2">{{ t('blocks.sponsoredBy') }}</div>
            <div class="flex justify-center">
              <ins class="adsbygoogle" style="display:block" data-ad-client="ca-pub-7500429866047477"
                data-ad-slot="6463255272" data-ad-format="auto" data-full-width-responsive="true"></ins>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Rig Enhance Modal -->
    <RigEnhanceModal :show="showRigManage" :rig="selectedRigForManage" @close="closeRigManage"
      @updated="handleRigUpdated" />

    <!-- Slot Purchase Confirmation Modal -->
    <Teleport to="body">
      <Transition name="modal">
        <div v-if="showConfirmSlotPurchase && slotInfo?.next_upgrade"
          class="fixed inset-0 z-50 flex items-center justify-center p-4" @click.self="showConfirmSlotPurchase = false">
          <div class="absolute inset-0 bg-black/70 backdrop-blur-sm"></div>
          <div class="relative bg-bg-primary border border-border rounded-2xl w-full max-w-sm p-6 shadow-2xl">
            <h3 class="text-lg font-bold mb-4 text-center">{{ t('slots.confirmPurchase', 'Confirmar compra') }}</h3>

            <div class="bg-bg-secondary rounded-xl p-4 mb-4">
              <div class="text-center mb-3">
                <div class="text-3xl mb-2">🖥️</div>
                <div class="font-semibold">{{ slotInfo.next_upgrade.name }}</div>
              </div>
              <div class="text-center text-2xl font-bold">
                <span>{{ slotInfo.next_upgrade.currency === 'crypto' ? '💎' : '🪙' }}</span>
                {{ slotInfo.next_upgrade.price.toLocaleString() }}
                <span class="text-sm">{{ slotInfo.next_upgrade.currency === 'crypto' ? 'BLC' : 'GC' }}</span>
              </div>
            </div>

            <p class="text-sm text-text-muted text-center mb-4">
              {{ t('slots.confirmMessage', '¿Estás seguro de que deseas comprar este slot?') }}
            </p>

            <div class="flex gap-3">
              <button @click="showConfirmSlotPurchase = false" :disabled="buyingSlot"
                class="flex-1 py-2.5 rounded-lg font-medium bg-bg-tertiary hover:bg-bg-tertiary/80 transition-colors">
                {{ t('common.cancel', 'Cancelar') }}
              </button>
              <button @click="confirmBuySlot" :disabled="buyingSlot"
                class="flex-1 py-2.5 rounded-lg font-semibold bg-gradient-primary hover:opacity-90 transition-opacity">
                <span v-if="buyingSlot" class="flex items-center justify-center gap-2">
                  <span class="animate-spin">⏳</span>
                </span>
                <span v-else>{{ t('common.confirm', 'Confirmar') }}</span>
              </button>
            </div>
          </div>
        </div>
      </Transition>
    </Teleport>

    <!-- Stop Rig Confirmation Modal -->
    <Teleport to="body">
      <Transition name="modal">
        <div v-if="showConfirmStopRig && rigToStop" class="fixed inset-0 z-50 flex items-center justify-center p-4"
          @click.self="cancelStopRig">
          <div class="absolute inset-0 bg-black/70 backdrop-blur-sm"></div>
          <div class="relative bg-bg-primary border border-border rounded-2xl w-full max-w-sm p-6 shadow-2xl">
            <h3 class="text-lg font-bold mb-4 text-center">{{ t('mining.confirmStop', '¿Detener rig?') }}</h3>

            <div class="bg-bg-secondary rounded-xl p-4 mb-4">
              <div class="text-center mb-3">
                <div class="text-3xl mb-2">⏹️</div>
                <div class="font-semibold" :class="getTierColor(rigToStop.rig.tier)">{{ getRigName(rigToStop.rig.id) }}
                </div>
              </div>
              <div class="flex justify-center gap-4 text-sm text-text-muted">
                <span>⚡ {{ rigToStop.rig.hashrate.toLocaleString() }} H/s</span>
                <span>🌡️ {{ (rigToStop.temperature ?? 0).toFixed(0) }}°C</span>
              </div>
            </div>

            <!-- Error message -->
            <div v-if="stopRigError" class="mb-4 p-3 rounded-lg bg-status-danger/20 border border-status-danger/30">
              <p class="text-sm text-status-danger text-center">{{ stopRigError }}</p>
            </div>

            <p class="text-sm text-text-muted text-center mb-4">
              {{ t('mining.confirmStopMessage', '¿Estás seguro de que deseas detener este rig?') }}
            </p>

            <div class="flex gap-3">
              <button @click="cancelStopRig" :disabled="stoppingRig"
                class="flex-1 py-2.5 rounded-lg font-medium bg-bg-tertiary hover:bg-bg-tertiary/80 transition-colors">
                {{ t('common.cancel', 'Cancelar') }}
              </button>
              <button @click="confirmStopRig" :disabled="stoppingRig"
                class="flex-1 py-2.5 rounded-lg font-semibold bg-status-danger/20 text-status-danger hover:bg-status-danger/30 transition-colors">
                <span v-if="stoppingRig" class="flex items-center justify-center gap-2">
                  <span class="animate-spin">⏳</span>
                </span>
                <span v-else>{{ t('mining.stop', 'Detener') }}</span>
              </button>
            </div>
          </div>
        </div>
      </Transition>
    </Teleport>
  </div>
</template>

<style scoped>
@keyframes shimmer {
  0% {
    transform: translateX(-100%);
  }

  100% {
    transform: translateX(100%);
  }
}

.modal-enter-active,
.modal-leave-active {
  transition: all 0.3s ease;
}

.modal-enter-from,
.modal-leave-to {
  opacity: 0;
}

.modal-enter-from .relative,
.modal-leave-to .relative {
  transform: scale(0.95);
}
</style>
