<script setup lang="ts">
import { ref, onMounted, onUnmounted, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAuthStore } from '@/stores/auth';
import { useMiningStore } from '@/stores/mining';
import { buyRigSlot, getExchangeRateHistory, getExchangeRates } from '@/utils/api';
import { playSound } from '@/utils/sounds';
import { useRigSound } from '@/composables/useSound';
import { useWakeLock } from '@/composables/useWakeLock';
import { isTabLocked } from '@/composables/useTabLock';
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

// Slot durability info modal
const showSlotDurabilityInfo = ref(false);
const slotDurabilityModalData = ref<{ uses_remaining: number; max_uses: number; slot_number: number } | null>(null);

function openSlotDurabilityInfo(slot: { uses_remaining: number; max_uses: number; slot_number: number }) {
  slotDurabilityModalData.value = slot;
  showSlotDurabilityInfo.value = true;
}

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

// Recent blocks panel
const recentBlocksCollapsed = ref(localStorage.getItem('recentBlocksCollapsed') !== 'false');
function toggleRecentBlocks() {
  recentBlocksCollapsed.value = !recentBlocksCollapsed.value;
  localStorage.setItem('recentBlocksCollapsed', String(recentBlocksCollapsed.value));
}

// Exchange rate chart
const rateHistory = ref<{ rate: number; recorded_at: string }[]>([]);
const currentRate = ref<number | null>(null);
const previousRate = ref<number | null>(null);
const loadingChart = ref(false);

const rateTrend = computed(() => {
  if (currentRate.value === null || previousRate.value === null) return 'neutral';
  if (currentRate.value > previousRate.value) return 'up';
  if (currentRate.value < previousRate.value) return 'down';
  return 'neutral';
});

const rateChangePercent = computed(() => {
  if (!currentRate.value || !previousRate.value) return 0;
  return ((currentRate.value - previousRate.value) / previousRate.value * 100);
});

const chartPath = computed(() => {
  if (rateHistory.value.length < 2) return '';
  const points = [...rateHistory.value].reverse();
  const rates = points.map(p => p.rate);
  const min = Math.min(...rates);
  const max = Math.max(...rates);
  const range = max - min || 1;
  const w = 280;
  const h = 80;
  const pad = 4;

  return points.map((p, i) => {
    const x = pad + (i / (points.length - 1)) * (w - pad * 2);
    const y = pad + (1 - (p.rate - min) / range) * (h - pad * 2);
    return `${i === 0 ? 'M' : 'L'}${x.toFixed(1)},${y.toFixed(1)}`;
  }).join(' ');
});

const chartAreaPath = computed(() => {
  if (!chartPath.value) return '';
  const points = [...rateHistory.value].reverse();
  const w = 280;
  const h = 80;
  const pad = 4;
  const lastX = pad + ((points.length - 1) / (points.length - 1)) * (w - pad * 2);
  const firstX = pad;
  return `${chartPath.value} L${lastX.toFixed(1)},${h} L${firstX.toFixed(1)},${h} Z`;
});

const chartMinMax = computed(() => {
  if (rateHistory.value.length < 2) return { min: 0, max: 0 };
  const rates = rateHistory.value.map(p => p.rate);
  return { min: Math.min(...rates), max: Math.max(...rates) };
});

function formatRate(rate: number): string {
  if (rate >= 1) return rate.toFixed(2);
  if (rate >= 0.01) return rate.toFixed(3);
  return rate.toFixed(4);
}

async function loadRateChart() {
  loadingChart.value = true;
  try {
    const [history, rates] = await Promise.all([
      getExchangeRateHistory(50),
      getExchangeRates(),
    ]);
    if (history) rateHistory.value = history;
    if (rates) {
      currentRate.value = rates.crypto_to_gamecoin;
      previousRate.value = rates.crypto_to_gamecoin_previous;
    }
  } catch (e) {
    console.error('Error loading rate chart:', e);
  } finally {
    loadingChart.value = false;
  }
}

// Uptime timer
const uptimeKey = ref(0);
let uptimeInterval: number | null = null;

// Polling intervals (stored for cleanup)
let blockInfoInterval: number | null = null;
let playerSharesInterval: number | null = null;

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
  return type === 'gold' ? t('mining.blockType.gold') : type === 'silver' ? t('mining.blockType.silver') : t('mining.blockType.bronze');
});

// Watch active rigs to control fan sound
watch(activeRigsCount, (newCount) => {
  if (!isTabLocked.value) {
    updateRigSound(newCount);
  }
});

// Stop sound when tab is locked, resume when unlocked
watch(isTabLocked, (locked) => {
  if (locked) {
    stopRigSound();
  } else {
    updateRigSound(activeRigsCount.value);
  }
}, { immediate: true });

// Iniciar sonido de rigs en la primera interacción del usuario (si hay rigs activos)
// Esto es necesario porque el navegador bloquea audio sin interacción
const initRigSoundOnInteraction = () => {
  if (activeRigsCount.value > 0 && !isTabLocked.value) {
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
  if (currency === 'crypto') return 'Landwork';
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

// Get slot data for a given rig
function getSlotForRig(rigId: string) {
  return slotInfo.value?.slots?.find(s => s.player_rig_id === rigId) ?? null;
}

// Get slot data for empty slots (no rig assigned)
const emptySlots = computed(() => {
  return slotInfo.value?.slots?.filter(s => !s.has_rig && !s.is_destroyed) ?? [];
});

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

  // Exchange rate chart
  loadRateChart();

  // Nuevo sistema de shares
  miningStore.loadMiningBlockInfo();
  miningStore.loadPlayerShares();
  miningStore.subscribeToMiningBlocks();

  // Actualizar bloque info cada segundo para countdown
  blockInfoInterval = setInterval(() => {
    miningStore.loadMiningBlockInfo();
  }, 1000) as unknown as number;

  // Actualizar shares del jugador cada 30 segundos (respaldo por si realtime falla)
  playerSharesInterval = setInterval(() => {
    miningStore.loadPlayerShares();
  }, 30000) as unknown as number;

  window.addEventListener('block-mined', handleBlockMined as EventListener);

  // Initialize AdSense (delay to ensure container has width)
  setTimeout(() => {
    try {
      const adEl = document.querySelector('.adsbygoogle[data-ad-slot="6463255272"]');
      if (adEl && adEl.clientWidth > 0) {
        ((window as any).adsbygoogle = (window as any).adsbygoogle || []).push({});
      }
    } catch (e) {
      // AdSense not available
    }
  }, 1500);
});

onUnmounted(() => {
  stopMiningSimulation();
  stopUptimeTimer();
  stopRigSound();
  miningStore.unsubscribeFromRealtime();
  releaseWakeLock();

  // Limpiar intervalos de polling
  if (blockInfoInterval) clearInterval(blockInfoInterval);
  if (playerSharesInterval) clearInterval(playerSharesInterval);

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
          class="flex items-center gap-2 px-3 py-1.5 rounded-lg bg-amber-500/20 border border-amber-500/30">
          <span>{{ getBoostIcon(boost.boost_type) }}</span>
          <span class="text-sm font-medium text-amber-400">{{ getBoostName(boost.boost_id) }}</span>
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
      <div class="card relative overflow-hidden p-3 sm:p-6">
        <div v-if="totalHashrate > 0"
          class="absolute inset-0 bg-gradient-to-r from-accent-primary/5 via-accent-secondary/5 to-accent-primary/5 animate-pulse">
        </div>

        <div class="relative z-10">
          <!-- Header -->
          <div class="flex items-center justify-between mb-3 sm:mb-4">
            <div class="flex items-center gap-2 sm:gap-3">
              <div class="w-10 h-10 sm:w-14 sm:h-14 rounded-xl flex items-center justify-center text-2xl sm:text-3xl"
                :class="totalHashrate > 0 ? 'bg-gradient-primary animate-pulse' : 'bg-bg-tertiary'">
                ⛏️
              </div>
              <div>
                <div class="flex items-center gap-1.5 sm:gap-2">
                  <h2 class="text-base sm:text-lg font-semibold">
                    <span v-if="currentMiningBlock?.active" v-tooltip="t('mining.tooltip.blockNumber')" class="cursor-help">{{ t('mining.currentBlock') }} #{{ currentMiningBlock.block_number }}</span>
                    <span v-else>{{ t('mining.miningCenter') }}</span>
                  </h2>
                  <!-- Tooltip educativo -->
                  <button
                    class="text-text-muted hover:text-accent-primary transition-colors"
                    v-tooltip="t('mining.tooltip.sharesSystem')"
                  >
                    <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                      <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clip-rule="evenodd"/>
                    </svg>
                  </button>
                </div>
                <p class="text-sm text-text-muted cursor-help"
                  v-tooltip="totalHashrate > 0 ? t('mining.tooltip.rigActive') : t('mining.tooltip.rigInactive')">
                  {{ totalHashrate > 0 ? t('mining.generatingShares') : t('mining.activateRigs') }}
                </p>
              </div>
            </div>

            <div class="text-right cursor-help"
              v-tooltip="effectiveHashrate < totalHashrate ? t('mining.tooltip.effectiveHashrate', { base: totalHashrate.toLocaleString() }) : t('mining.tooltip.totalHashrate')">
              <div class="text-xl sm:text-3xl font-bold font-mono"
                :class="effectiveHashrate > 0 ? 'gradient-text' : 'text-text-muted'">
                {{ Math.round(effectiveHashrate).toLocaleString() }}
              </div>
              <div class="text-[10px] sm:text-xs text-text-muted flex items-center justify-end gap-1">
                <span>{{ t('mining.effectiveHs') }}</span>
                <span v-if="effectiveHashrate < totalHashrate" class="text-status-danger">
                  (↓{{ Math.round(((totalHashrate - effectiveHashrate) / totalHashrate) * 100) }}%)
                </span>
              </div>
            </div>
          </div>

          <!-- Estado: Sin bloque activo -->
          <div v-if="!currentMiningBlock?.active" class="text-center py-8 text-text-muted">
            <div class="text-4xl mb-3">⏳</div>
            <div class="text-lg font-medium mb-1">{{ t('mining.waitingBlock') }}</div>
            <div class="text-sm">{{ t('mining.nextBlockAuto') }}</div>
          </div>

          <!-- Estado: Con bloque activo -->
          <div v-else>
            <!-- Info de Red (Dificultad, etc) -->
            <div class="grid grid-cols-2 md:grid-cols-4 gap-2 mb-3 sm:mb-4 p-2 sm:p-3 bg-bg-tertiary/50 rounded-lg">
              <div v-tooltip="t('mining.tooltip.difficulty')" class="text-center cursor-help">
                <div class="text-[10px] sm:text-xs text-text-muted mb-0.5 sm:mb-1">🎯 {{ t('mining.difficulty') }}</div>
                <div class="text-sm sm:text-base font-bold font-mono text-cyan-400">
                  {{ (currentMiningBlock.difficulty / 1000).toFixed(1) }}K
                </div>
              </div>
              <div v-tooltip="t('mining.tooltip.networkHashrate')" class="text-center cursor-help">
                <div class="text-[10px] sm:text-xs text-text-muted mb-0.5 sm:mb-1">🌐 {{ t('mining.networkHashrateLabel') }}</div>
                <div class="text-sm sm:text-base font-bold font-mono text-amber-400">
                  {{ (networkStats.hashrate / 1000).toFixed(1) }}K
                </div>
              </div>
              <div v-tooltip="t('mining.tooltip.activeMiners')" class="text-center cursor-help">
                <div class="text-[10px] sm:text-xs text-text-muted mb-0.5 sm:mb-1">👥 {{ t('mining.minersLabel') }}</div>
                <div class="text-sm sm:text-base font-bold font-mono text-emerald-400">
                  {{ networkStats.activeMiners }}
                </div>
              </div>
              <div v-tooltip="t('mining.tooltip.yourPower')" class="text-center cursor-help">
                <div class="text-[10px] sm:text-xs text-text-muted mb-0.5 sm:mb-1">⚡ {{ t('mining.yourPower') }}</div>
                <div class="text-sm sm:text-base font-bold font-mono text-amber-400">
                  {{ networkStats.hashrate > 0 ? ((effectiveHashrate / networkStats.hashrate) * 100).toFixed(2) : '0.00' }}%
                </div>
              </div>
            </div>

            <!-- Indicador Dual: Tiempo + Actividad de Red -->
            <div class="mb-3 sm:mb-4 p-3 sm:p-4 bg-bg-secondary rounded-xl border border-border/30"
              :class="{
                'border-status-danger': timeRemainingAlert === 'critical',
                'border-status-warning': timeRemainingAlert === 'warning'
              }">
              <!-- Header con tiempo restante -->
              <div class="flex items-center justify-between mb-2 sm:mb-3">
                <div class="flex items-center gap-1.5 sm:gap-2 cursor-help"
                  v-tooltip="t('mining.tooltip.blockCloseTime')">
                  <span class="text-xl sm:text-2xl">⏰</span>
                  <div>
                    <div class="text-xs sm:text-sm text-text-muted">{{ t('mining.blockClose') }}</div>
                    <div class="text-xl sm:text-2xl font-bold font-mono"
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
                  class="px-2 sm:px-3 py-0.5 sm:py-1 bg-status-danger/20 border border-status-danger/50 rounded-lg animate-pulse">
                  <span class="text-status-danger font-semibold text-xs sm:text-sm">⚠️ {{ t('mining.closingSoon') }}</span>
                </div>
              </div>

              <!-- Barra de progreso del tiempo -->
              <div class="h-2 sm:h-3 bg-bg-tertiary rounded-full overflow-hidden relative mb-2 sm:mb-3">
                <div
                  class="h-full transition-all duration-1000"
                  :class="{
                    'bg-gradient-to-r from-status-danger to-red-400': timeRemainingAlert === 'critical',
                    'bg-gradient-to-r from-status-warning to-amber-400': timeRemainingAlert === 'warning',
                    'bg-gradient-to-r from-accent-primary to-amber-500': timeRemainingAlert === 'normal'
                  }"
                  :style="{ width: `${Math.max(0, 100 - (currentMiningBlock.time_remaining_seconds / 1800 * 100))}%` }"
                ></div>
                <div v-if="totalHashrate > 0"
                  class="absolute inset-0 bg-gradient-to-r from-transparent via-white/10 to-transparent"
                  style="animation: shimmer 2s linear infinite;">
                </div>
              </div>

              <!-- Info secundaria: actividad de red -->
              <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-1 sm:gap-0 text-[10px] sm:text-xs">
                <div class="flex items-center gap-2 sm:gap-4">
                  <span class="text-text-muted cursor-help"
                    v-tooltip="t('mining.tooltip.sharesActivity')">
                    📊 <span class="hidden sm:inline">{{ t('mining.activityLabel') }}:</span> <span class="font-mono text-text-secondary">{{ currentMiningBlock.total_shares.toFixed(0) }} / {{ currentMiningBlock.target_shares }}</span> <span class="hidden sm:inline">shares</span> ({{ sharesProgress.toFixed(0) }}%)
                  </span>
                  <span class="hidden sm:inline text-text-muted cursor-help"
                    v-tooltip="t('mining.tooltip.sharesRhythm')">
                    ⚡ {{ t('mining.rhythmLabel') }}: <span class="font-mono"
                      :class="{
                        'text-status-success': sharesProgress > 90,
                        'text-status-warning': sharesProgress >= 70 && sharesProgress <= 90,
                        'text-status-danger': sharesProgress < 70
                      }">
                      {{ sharesProgress > 90 ? t('mining.rhythmHigh') : sharesProgress >= 70 ? t('mining.rhythmNormal') : t('mining.rhythmLow') }}
                    </span>
                  </span>
                </div>
                <span class="text-text-muted cursor-help"
                  v-tooltip="t('mining.tooltip.activeMinersList')">
                  👥 {{ networkStats.activeMiners }} {{ t('mining.activeMinersLabel') }}
                </span>
              </div>
            </div>

            <!-- Grid de 5 Stats -->
            <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-5 gap-2 sm:gap-3">
              <!-- Velocidad -->
              <div v-tooltip="t('mining.tooltip.blockSpeed')"
                class="bg-bg-secondary rounded-xl p-2 sm:p-3 border-l-4 border-accent-primary cursor-help">
                <div class="flex items-center gap-1 mb-0.5 sm:mb-1">
                  <span class="text-sm sm:text-base">⚡</span>
                  <div class="text-[10px] text-text-muted">{{ t('mining.speedLabel') }}</div>
                </div>
                <div class="text-lg sm:text-xl font-bold font-mono text-accent-primary">
                  {{ sharesRate < 1 ? t('mining.speedSlow') : sharesRate < 3 ? t('mining.speedNormal') : t('mining.speedFast') }}
                </div>
                <div class="text-[10px] text-text-muted">{{ sharesRate.toFixed(1) }}/min</div>
                <div v-if="sharesEfficiency !== 100" class="mt-0.5 text-[10px]"
                  :class="sharesEfficiency > 100 ? 'text-status-success' : 'text-status-warning'">
                  {{ sharesEfficiency > 100 ? '↑' : '↓' }}{{ Math.abs(sharesEfficiency - 100) }}%
                </div>
              </div>

              <!-- % del Bloque -->
              <div v-tooltip="t('mining.tooltip.blockParticipation')"
                class="bg-bg-secondary rounded-xl p-2 sm:p-3 border-l-4 border-amber-500 cursor-help">
                <div class="flex items-center gap-1 mb-0.5 sm:mb-1">
                  <span class="text-sm sm:text-base">📊</span>
                  <div class="text-[10px] text-text-muted">{{ t('mining.blockPercent') }}</div>
                </div>
                <div class="text-lg sm:text-xl font-bold font-mono text-amber-400">
                  {{ playerSharePercentage.toFixed(1) }}%
                </div>
                <div class="text-[10px] text-text-muted">{{ t('mining.yourParticipation') }}</div>
                <div v-if="playerSharePercentage > 0" class="mt-0.5 text-[10px] text-status-info">
                  Top {{ Math.min(100, Math.round((100 - playerSharePercentage) + playerSharePercentage / 2)) }}%
                </div>
              </div>

              <!-- Contribución Relativa -->
              <div v-tooltip="t('mining.tooltip.relativeContribution')"
                class="bg-bg-secondary rounded-xl p-2 sm:p-3 border-l-4 border-emerald-500 cursor-help">
                <div class="flex items-center gap-1 mb-0.5 sm:mb-1">
                  <span class="text-sm sm:text-base">📈</span>
                  <div class="text-[10px] text-text-muted">{{ t('mining.contributionLabel') }}</div>
                </div>
                <div class="text-lg sm:text-xl font-bold font-mono"
                  :class="{
                    'text-status-success': playerSharePercentage > (100 / Math.max(1, networkStats.activeMiners)) * 1.5,
                    'text-status-warning': playerSharePercentage > (100 / Math.max(1, networkStats.activeMiners)) * 0.5,
                    'text-status-danger': playerSharePercentage <= (100 / Math.max(1, networkStats.activeMiners)) * 0.5
                  }">
                  {{ playerSharePercentage > (100 / Math.max(1, networkStats.activeMiners)) * 1.5 ? t('mining.contributionHigh') :
                     playerSharePercentage > (100 / Math.max(1, networkStats.activeMiners)) * 0.5 ? t('mining.contributionMedium') : t('mining.contributionLow') }}
                </div>
                <div class="text-[10px] text-text-muted">{{ t('mining.vsAverage') }}</div>
                <div class="mt-0.5 text-[10px] text-text-muted">
                  {{ (100 / Math.max(1, networkStats.activeMiners)).toFixed(1) }}{{ t('mining.basePercent') }}
                </div>
              </div>

              <!-- Tu Recompensa -->
              <div v-tooltip="t('mining.tooltip.estimatedReward')"
                class="bg-bg-secondary rounded-xl p-2 sm:p-3 border-l-4 cursor-help"
                :class="isPremium ? 'border-amber-400 bg-gradient-to-br from-amber-500/5 via-bg-secondary to-bg-secondary' : 'border-amber-500'">
                <div class="flex items-center gap-1 mb-0.5 sm:mb-1">
                  <span class="text-sm sm:text-base">💰</span>
                  <div class="text-[10px] text-text-muted">{{ t('mining.yourReward') }}</div>
                </div>
                <div class="flex items-center gap-1.5">
                  <div class="text-lg sm:text-xl font-bold font-mono"
                    :class="isPremium ? 'text-amber-400' : 'text-amber-400'">
                    {{ estimatedReward.toFixed(3) }}
                  </div>
                  <!-- Premium Badge -->
                  <span v-if="isPremium"
                    class="px-1.5 py-0.5 text-[11px] font-bold bg-slate-800 text-amber-400 rounded-full shadow-md flex items-center gap-0.5 border border-amber-400/50"
                    v-tooltip="t('mining.tooltip.premiumBonus')">
                    <span>👑</span>
                    <span class="hidden sm:inline">+50%</span>
                  </span>
                </div>
                <div class="text-[10px] text-text-muted">{{ t('mining.estimatedBtc') }}</div>
                <div class="mt-0.5 text-[10px] text-text-muted">
                  {{ playerSharePercentage.toFixed(1) }}{{ t('mining.ofPool') }}
                </div>
              </div>

              <!-- Pool Total con Tipo de Bloque -->
              <div v-tooltip="t('mining.tooltip.blockRewardPool', { blockType: blockTypeLabel, reward: currentMiningBlock.reward })"
                class="bg-bg-secondary rounded-xl p-2 sm:p-3 border-l-4 cursor-help col-span-2 md:col-span-1"
                :class="{
                  'border-amber-600': currentMiningBlock.block_type === 'bronze',
                  'border-gray-400': currentMiningBlock.block_type === 'silver',
                  'border-yellow-400': currentMiningBlock.block_type === 'gold'
                }">
                <div class="flex items-center gap-1 mb-0.5 sm:mb-1">
                  <span class="text-sm sm:text-base">{{ blockTypeEmoji }}</span>
                  <div class="text-[10px] text-text-muted">{{ blockTypeLabel }}</div>
                </div>
                <div class="text-lg sm:text-xl font-bold font-mono"
                  :class="{
                    'text-amber-600': currentMiningBlock.block_type === 'bronze',
                    'text-gray-300': currentMiningBlock.block_type === 'silver',
                    'text-yellow-400': currentMiningBlock.block_type === 'gold'
                  }">
                  {{ currentMiningBlock.reward.toFixed(1) }}
                </div>
                <div class="text-[10px] text-text-muted">{{ t('mining.toDistribute') }}</div>
                <div class="mt-0.5 text-[10px] text-text-muted">
                  {{ networkStats.activeMiners }} {{ t('mining.networkMiners') }}
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
              class="bg-bg-secondary/80 rounded-xl border relative overflow-hidden"
              :class="playerRig.condition <= 0 ? 'border-status-danger/70' : playerRig.condition < 30 ? 'border-status-warning/50' : 'border-border/30'">
              <!-- Slot Durability Bar (top border) -->
              <div v-if="getSlotForRig(playerRig.id)" class="flex w-full h-2.5 cursor-pointer hover:brightness-110"
                :class="getSlotForRig(playerRig.id)!.max_uses > 1 ? 'gap-px' : ''"
                @click="openSlotDurabilityInfo(getSlotForRig(playerRig.id)!)">
                <div v-for="i in getSlotForRig(playerRig.id)!.max_uses" :key="i"
                  class="flex-1 h-full transition-colors"
                  :class="i <= getSlotForRig(playerRig.id)!.uses_remaining ? 'bg-cyan-500' : 'bg-gray-700/60'">
                </div>
              </div>
              <div class="p-4">
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
                <div class="flex flex-col gap-1" v-tooltip="playerRig.is_active && playerRig.activated_at ? t('mining.tooltips.uptime') : ''">
                  <h3 class="font-semibold" :class="getTierColor(playerRig.rig.tier)">
                    {{ getRigName(playerRig.rig.id) }}
                  </h3>
                  <!-- Uptime badge (moved from stats row) -->
                  <span v-if="playerRig.is_active && playerRig.activated_at"
                    class="flex items-center gap-1 text-[10px] text-text-secondary px-1.5 py-0.5 bg-bg-tertiary/80 rounded w-fit pointer-events-none" :key="uptimeKey">
                    ⏱️ {{ formatUptime(playerRig.activated_at) }}
                  </span>
                </div>
                <div class="flex items-center gap-2">
                  <!-- Upgrade levels indicator -->
                  <div
                    v-if="(playerRig.hashrate_level ?? 1) > 1 || (playerRig.efficiency_level ?? 1) > 1 || (playerRig.thermal_level ?? 1) > 1"
                    v-tooltip="t('mining.tooltips.upgrades') + ` - ⚡${playerRig.hashrate_level ?? 1} 💡${playerRig.efficiency_level ?? 1} ❄️${playerRig.thermal_level ?? 1}`"
                    class="flex items-center gap-1 text-[10px] px-1.5 py-0.5 bg-amber-500/20 rounded cursor-help">
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
                  <span class="text-amber-400">🚀</span>
                  <span class="text-amber-400">{{ rigBoosts[playerRig.id].length }}</span>
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
            </div>

            <!-- Empty Available Slots -->
            <div v-for="slot in emptySlots" :key="'empty-slot-' + slot.slot_number"
              class="bg-bg-secondary/50 rounded-xl border border-dashed border-border/50 overflow-hidden min-h-[200px]">
              <!-- Slot Durability Bar (top border) -->
              <div class="flex w-full h-2.5 cursor-pointer hover:brightness-110"
                :class="slot.max_uses > 1 ? 'gap-px' : ''"
                @click="openSlotDurabilityInfo(slot)">
                <div v-for="i in slot.max_uses" :key="i"
                  class="flex-1 h-full transition-colors"
                  :class="i <= slot.uses_remaining ? 'bg-cyan-500' : 'bg-gray-700/60'">
                </div>
              </div>
              <div class="p-4 flex flex-col items-center justify-center h-full">
                <div
                  class="w-12 h-12 rounded-lg bg-bg-tertiary/50 flex items-center justify-center text-2xl mb-3 opacity-50">
                  🖥️
                </div>
                <div class="text-text-muted font-medium">{{ t('slots.available', 'Disponible') }}</div>
                <p class="text-xs text-text-muted/70 mt-1">{{ t('slots.buyRigToUse', 'Compra un rig en el mercado') }}</p>
              </div>
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
            <div class="flex items-center justify-between mb-2">
              <h3 class="text-sm font-semibold flex items-center gap-1.5 text-text-muted">
                <span>📦</span> {{ t('mining.recentBlocks') }}
                <span v-if="recentBlocks.length > 0" class="text-xs bg-bg-secondary text-text-muted px-1.5 py-0.5 rounded-full font-mono">{{ recentBlocks.length }}</span>
              </h3>
              <button
                @click="toggleRecentBlocks"
                class="text-text-muted hover:text-white transition-colors p-0.5 rounded"
                :title="recentBlocksCollapsed ? t('mining.showBlocks') : t('mining.hideBlocks')"
              >
                <span class="text-xs transition-transform duration-200 inline-block" :class="recentBlocksCollapsed ? 'rotate-180' : 'rotate-0'">▲</span>
              </button>
            </div>

            <div v-if="recentBlocks.length === 0" class="text-center py-4 text-text-muted text-xs">
              {{ t('mining.noRecentBlocks') }}
            </div>

            <div v-else class="space-y-1.5">
              <div v-for="(block, index) in (recentBlocksCollapsed ? recentBlocks.slice(0, 2) : recentBlocks)" :key="block.id" class="px-2.5 py-2 rounded-lg" :class="[
                block.player_participation?.participated
                  ? 'bg-status-success/10 border border-status-success/20'
                  : 'bg-bg-secondary/50'
              ]">
                <!-- Row 1: Block number + Time -->
                <div class="flex items-center justify-between mb-1">
                  <div class="flex items-center gap-1.5">
                    <span v-if="index === 0" class="text-xs" v-tooltip="t('mining.tooltip.latestBlock')">🆕</span>
                    <span v-if="block.player_participation?.participated" class="text-xs cursor-help" v-tooltip="t('mining.tooltip.participatedBlock')">⭐</span>
                    <span v-if="block.player_participation?.is_premium" class="text-xs cursor-help" v-tooltip="t('mining.tooltip.premiumBlock')">👑</span>
                    <span class="text-sm font-medium cursor-help"
                      :class="block.player_participation?.participated ? 'text-status-success' : 'text-accent-primary'"
                      v-tooltip="block.player_participation?.participated ? t('mining.tooltip.participatedDetail') : t('mining.tooltip.notParticipated')">{{ t('mining.recentBlock.blockLabel') }} <span class="font-mono">#{{
                      block.block_number || block.height }}</span></span>
                  </div>
                  <span class="text-[10px] text-text-muted cursor-help" :key="uptimeKey"
                    v-tooltip="t('mining.tooltip.blockClosedTime')">{{ formatTimeAgo(block.created_at)
                    }}</span>
                </div>

                <!-- Row 2: Si participaste -->
                <div v-if="block.player_participation?.participated" class="space-y-0.5">
                  <div class="flex items-center justify-between text-xs">
                    <span class="text-text-muted cursor-help" v-tooltip="t('mining.tooltip.contributionPct')">{{ t('mining.recentBlock.yourContribution') }}</span>
                    <span class="font-mono text-status-success cursor-help" v-tooltip="t('mining.tooltip.contributionPctValue', { pct: block.player_participation.percentage.toFixed(1) })">
                      {{ block.player_participation.percentage.toFixed(1) }}%
                    </span>
                  </div>
                  <div class="flex items-center justify-between text-xs">
                    <span class="text-text-muted cursor-help" v-tooltip="t('mining.tooltip.yourBlockReward')">{{ t('mining.recentBlock.yourReward') }}</span>
                    <span class="font-mono text-status-warning cursor-help" v-tooltip="t('mining.tooltip.yourBlockRewardValue', { reward: block.player_participation.reward.toFixed(6) })">
                      +{{ block.player_participation.reward.toFixed(3) }} ₿
                    </span>
                  </div>
                  <div class="flex items-center justify-between text-xs">
                    <span class="text-text-muted cursor-help" v-tooltip="t('mining.tooltip.blockTotal')">{{ t('mining.recentBlock.blockTotal') }}</span>
                    <span class="font-mono text-text-secondary cursor-help" v-tooltip="t('mining.tooltip.blockTotalValue', { total: (block.total_distributed || block.reward || 0).toFixed(3), count: block.contributors_count || 0 })">
                      {{ (block.total_distributed || block.reward || 0).toFixed(1) }} ₿
                    </span>
                  </div>
                  <div v-if="block.premium_bonus && block.premium_bonus > 0" class="flex items-center justify-between text-xs">
                    <span class="text-text-muted cursor-help" v-tooltip="t('mining.tooltip.premiumBonusAmount')">👑 {{ t('mining.recentBlock.premiumBonus') }}</span>
                    <span class="font-mono text-purple-400 cursor-help" v-tooltip="t('mining.tooltip.premiumBonusAmountValue', { bonus: block.premium_bonus.toFixed(3) })">
                      +{{ block.premium_bonus.toFixed(1) }} ₿
                    </span>
                  </div>
                  <!-- Top contributor -->
                  <div v-if="block.top_contributor" class="flex items-center justify-between text-xs pt-0.5 border-t border-border/20">
                    <span class="text-text-muted flex items-center gap-1 cursor-help" v-tooltip="t('mining.tooltip.topContributor')">
                      <span>🥇</span>
                      <span>{{ block.top_contributor.username }}</span>
                    </span>
                    <span class="font-mono text-amber-400 cursor-help" v-tooltip="t('mining.tooltip.topContributorValue', { username: block.top_contributor.username, pct: block.top_contributor.percentage.toFixed(1) })">
                      {{ block.top_contributor.percentage.toFixed(1) }}%
                    </span>
                  </div>
                </div>

                <!-- Row 2: Si NO participaste -->
                <div v-else class="space-y-0.5">
                  <div class="flex items-center justify-between text-xs">
                    <span class="text-text-muted cursor-help" v-tooltip="t('mining.tooltip.contributors')">{{ t('mining.recentBlock.contributors') }}</span>
                    <span class="font-mono" v-tooltip="t('mining.tooltip.contributorsValue', { count: block.contributors_count || 0 })">{{ block.contributors_count || 0 }}</span>
                  </div>
                  <div class="flex items-center justify-between text-xs">
                    <span class="text-text-muted cursor-help" v-tooltip="t('mining.tooltip.totalDistributed')">{{ t('mining.recentBlock.totalDistributed') }}</span>
                    <span class="font-mono text-status-warning" v-tooltip="t('mining.tooltip.totalDistributedValue', { total: (block.total_distributed || block.reward || 0).toFixed(3) })">
                      {{ (block.total_distributed || block.reward || 0).toFixed(1) }} ₿
                    </span>
                  </div>
                  <div v-if="block.premium_bonus && block.premium_bonus > 0" class="flex items-center justify-between text-xs">
                    <span class="text-text-muted cursor-help" v-tooltip="t('mining.tooltip.premiumBonusAmount')">👑 {{ t('mining.recentBlock.premiumBonus') }}</span>
                    <span class="font-mono text-purple-400 cursor-help" v-tooltip="t('mining.tooltip.premiumBonusAmountValue', { bonus: block.premium_bonus.toFixed(3) })">
                      +{{ block.premium_bonus.toFixed(1) }} ₿
                    </span>
                  </div>
                  <!-- Top contributor -->
                  <div v-if="block.top_contributor" class="flex items-center justify-between text-xs pt-0.5 border-t border-border/20">
                    <span class="text-text-muted flex items-center gap-1 cursor-help" v-tooltip="t('mining.tooltip.topContributor')">
                      <span>🥇</span>
                      <span>{{ block.top_contributor.username }}</span>
                    </span>
                    <span class="font-mono text-amber-400 cursor-help" v-tooltip="t('mining.tooltip.topContributorValue', { username: block.top_contributor.username, pct: block.top_contributor.percentage.toFixed(1) })">
                      {{ block.top_contributor.percentage.toFixed(1) }}%
                    </span>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <!-- Exchange Rate Chart -->
          <div class="card p-3">
            <div class="flex items-center justify-between mb-2">
              <h3 class="text-sm font-semibold flex items-center gap-1.5 text-text-muted">
                <span>📈</span> {{ t('mining.rateChart.title') }}
                <span v-if="currentRate !== null" class="font-mono text-status-warning">{{ formatRate(currentRate) }} 🪙</span>
                <span
                  v-if="rateTrend !== 'neutral'"
                  class="text-[10px] font-bold px-1 py-0.5 rounded"
                  :class="rateTrend === 'up' ? 'text-green-400 bg-green-400/10' : 'text-red-400 bg-red-400/10'"
                >{{ rateTrend === 'up' ? '▲' : '▼' }} {{ Math.abs(rateChangePercent).toFixed(1) }}%</span>
              </h3>
              <button @click="loadRateChart" class="text-text-muted hover:text-white transition-colors p-0.5 rounded" :title="t('mining.rateChart.refresh')">
                <span class="text-xs" :class="loadingChart ? 'animate-spin inline-block' : ''">🔄</span>
              </button>
            </div>

            <!-- SVG Chart -->
            <div v-if="loadingChart" class="flex items-center justify-center py-6">
              <span class="animate-spin w-5 h-5 border-2 border-accent-primary border-t-transparent rounded-full"></span>
            </div>
            <div v-else-if="rateHistory.length >= 2" class="relative">
              <svg viewBox="0 0 280 80" class="w-full h-auto" preserveAspectRatio="none">
                <!-- Grid lines -->
                <line x1="4" y1="4" x2="276" y2="4" stroke="currentColor" class="text-border" stroke-width="0.5" stroke-dasharray="4 4" />
                <line x1="4" y1="40" x2="276" y2="40" stroke="currentColor" class="text-border" stroke-width="0.5" stroke-dasharray="4 4" />
                <line x1="4" y1="76" x2="276" y2="76" stroke="currentColor" class="text-border" stroke-width="0.5" stroke-dasharray="4 4" />
                <!-- Area fill -->
                <path
                  :d="chartAreaPath"
                  :fill="rateTrend === 'down' ? 'rgba(248,113,113,0.1)' : 'rgba(74,222,128,0.1)'"
                />
                <!-- Line -->
                <path
                  :d="chartPath"
                  fill="none"
                  :stroke="rateTrend === 'down' ? '#f87171' : '#4ade80'"
                  stroke-width="2"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                />
              </svg>
              <!-- Min/Max labels -->
              <div class="flex justify-between text-[10px] text-text-muted font-mono mt-0.5 px-1">
                <span>{{ formatRate(chartMinMax.min) }}</span>
                <span class="text-text-muted/50">{{ rateHistory.length }} {{ t('mining.rateChart.blocks') }}</span>
                <span>{{ formatRate(chartMinMax.max) }}</span>
              </div>
            </div>
            <div v-else class="text-center py-4 text-text-muted text-xs">
              {{ t('mining.rateChart.noData') }}
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
                <span class="text-sm">{{ slotInfo.next_upgrade.currency === 'crypto' ? 'Landwork' : 'GC' }}</span>
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

    <!-- Slot Durability Info Modal -->
    <Teleport to="body">
      <Transition name="modal">
        <div v-if="showSlotDurabilityInfo && slotDurabilityModalData"
          class="fixed inset-0 z-50 flex items-center justify-center p-4" @click.self="showSlotDurabilityInfo = false">
          <div class="absolute inset-0 bg-black/70 backdrop-blur-sm"></div>
          <div class="relative bg-bg-primary border border-border rounded-2xl w-full max-w-sm p-6 shadow-2xl">
            <h3 class="text-lg font-bold mb-4 text-center">{{ t('slots.durabilityTitle') }}</h3>

            <!-- Visual bar -->
            <div class="flex gap-px w-full h-3 rounded-lg overflow-hidden mb-3">
              <div v-for="i in slotDurabilityModalData.max_uses" :key="i"
                class="flex-1 h-full transition-colors"
                :class="i <= slotDurabilityModalData.uses_remaining ? 'bg-cyan-500' : 'bg-gray-700/60'">
              </div>
            </div>
            <p class="text-center text-sm font-semibold mb-4"
              :class="slotDurabilityModalData.uses_remaining <= 1 ? 'text-status-danger' : 'text-cyan-400'">
              {{ t('slots.usesRemaining', { uses: slotDurabilityModalData.uses_remaining, max: slotDurabilityModalData.max_uses }) }}
            </p>

            <!-- Info sections -->
            <div class="space-y-3 mb-5">
              <div class="bg-bg-secondary rounded-xl p-3">
                <div class="flex items-center gap-2 mb-1">
                  <span class="text-base">📋</span>
                  <span class="text-sm font-semibold">{{ t('slots.durabilityInfo.whatIsTitle') }}</span>
                </div>
                <p class="text-xs text-text-muted leading-relaxed">{{ t('slots.durabilityInfo.whatIsDesc') }}</p>
              </div>

              <div class="bg-bg-secondary rounded-xl p-3">
                <div class="flex items-center gap-2 mb-1">
                  <span class="text-base">📉</span>
                  <span class="text-sm font-semibold">{{ t('slots.durabilityInfo.howDecreasesTitle') }}</span>
                </div>
                <p class="text-xs text-text-muted leading-relaxed">{{ t('slots.durabilityInfo.howDecreasesDesc') }}</p>
              </div>

              <div class="bg-status-danger/10 border border-status-danger/20 rounded-xl p-3">
                <div class="flex items-center gap-2 mb-1">
                  <span class="text-base">⚠️</span>
                  <span class="text-sm font-semibold text-status-danger">{{ t('slots.durabilityInfo.whenEmptyTitle') }}</span>
                </div>
                <p class="text-xs text-text-muted leading-relaxed">{{ t('slots.durabilityInfo.whenEmptyDesc') }}</p>
              </div>
            </div>

            <button @click="showSlotDurabilityInfo = false"
              class="w-full py-2.5 rounded-lg font-medium bg-bg-tertiary hover:bg-bg-tertiary/80 transition-colors">
              {{ t('common.close') }}
            </button>
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
