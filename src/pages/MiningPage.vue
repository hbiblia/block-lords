<script setup lang="ts">
import { ref, onMounted, onUnmounted, computed, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAuthStore } from '@/stores/auth';
import { useMiningStore } from '@/stores/mining';
import { buyRigSlot } from '@/utils/api';
import { playSound } from '@/utils/sounds';
import { useWakeLock } from '@/composables/useWakeLock';
import { useMiningEstimate } from '@/composables/useMiningEstimate';
import RigEnhanceModal from '@/components/RigEnhanceModal.vue';

// Wake Lock to keep screen on while mining
const { requestWakeLock, releaseWakeLock } = useWakeLock();

const { t } = useI18n();
const authStore = useAuthStore();
const miningStore = useMiningStore();

// Mining estimate
const {
  isMining: isEstimateMining,
  estimatedTimeText,
  timeRangeText,
  blocksPerDayText,
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
const miningChance = computed(() => miningStore.miningChance);
const activeRigsCount = computed(() => miningStore.activeRigsCount);

// Premium status
const isPremium = computed(() => {
  const premiumUntil = authStore.player?.premium_until;
  if (!premiumUntil) return false;
  return new Date(premiumUntil) > new Date();
});

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
  if (currency === 'crypto') return 'Crypto';
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

// Upgrade bonus lookup tables (matching database upgrade_costs)
const UPGRADE_BONUSES = {
  hashrate: { 1: 0, 2: 10, 3: 20, 4: 35, 5: 50 },    // % increase
  efficiency: { 1: 0, 2: 5, 3: 10, 4: 15, 5: 20 },   // % decrease
  thermal: { 1: 0, 2: 2, 3: 4, 4: 6, 5: 8 },         // °C decrease
} as const;

// Get upgraded hashrate (base * (1 + bonus%))
function getUpgradedHashrate(playerRig: typeof miningStore.rigs[0]): number {
  const level = playerRig.hashrate_level ?? 1;
  const bonus = UPGRADE_BONUSES.hashrate[level as keyof typeof UPGRADE_BONUSES.hashrate] ?? 0;
  return Math.round(playerRig.rig.hashrate * (1 + bonus / 100));
}

// Get upgraded power consumption (base * (1 - bonus%))
function getUpgradedPower(playerRig: typeof miningStore.rigs[0]): number {
  const level = playerRig.efficiency_level ?? 1;
  const bonus = UPGRADE_BONUSES.efficiency[level as keyof typeof UPGRADE_BONUSES.efficiency] ?? 0;
  return playerRig.rig.power_consumption * (1 - bonus / 100);
}

// Get thermal bonus (°C reduction)
function getThermalBonus(playerRig: typeof miningStore.rigs[0]): number {
  const level = playerRig.thermal_level ?? 1;
  return UPGRADE_BONUSES.thermal[level as keyof typeof UPGRADE_BONUSES.thermal] ?? 0;
}

// Get hashrate bonus percentage for display
function getHashrateBonus(playerRig: typeof miningStore.rigs[0]): number {
  const level = playerRig.hashrate_level ?? 1;
  return UPGRADE_BONUSES.hashrate[level as keyof typeof UPGRADE_BONUSES.hashrate] ?? 0;
}

// Get efficiency bonus percentage for display
function getEfficiencyBonus(playerRig: typeof miningStore.rigs[0]): number {
  const level = playerRig.efficiency_level ?? 1;
  return UPGRADE_BONUSES.efficiency[level as keyof typeof UPGRADE_BONUSES.efficiency] ?? 0;
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

function getBlockReward(height: number): number {
  const baseReward = 100;
  const halvingInterval = 10000;
  const halvings = Math.floor(height / halvingInterval);
  return baseReward / Math.pow(2, halvings);
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
  miningStore.unsubscribeFromRealtime();
  releaseWakeLock();

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
        <div
          v-for="boost in activeBoosts"
          :key="boost.id"
          class="flex items-center gap-2 px-3 py-1.5 rounded-lg bg-purple-500/20 border border-purple-500/30"
        >
          <span>{{ getBoostIcon(boost.boost_type) }}</span>
          <span class="text-sm font-medium text-purple-400">{{ getBoostName(boost.boost_id) }}</span>
          <span class="text-xs text-text-muted">{{ formatTimeRemaining(boost.seconds_remaining) }}</span>
        </div>
      </div>
    </div>

    <!-- Primera carga - solo si no hay datos en cache -->
    <div v-if="loading && !dataLoaded" class="text-center py-20 text-text-muted">
      <div class="w-12 h-12 mx-auto rounded-xl bg-gradient-primary flex items-center justify-center text-2xl animate-pulse mb-4">
        ⛏️
      </div>
      {{ t('mining.loadingStation') }}
    </div>

    <!-- Contenido (con datos en cache o cargados) -->
    <div v-else class="space-y-6">
      <!-- Mining Status Panel -->
      <div class="card relative overflow-hidden">
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
                <div class="flex items-center gap-2">
                  <h2 class="text-lg font-semibold">{{ t('mining.miningCenter') }}</h2>
                  <span
                    v-if="isPremium"
                    class="px-2 py-0.5 text-xs font-medium bg-amber-500/20 text-amber-400 border border-amber-500/30 rounded-full flex items-center gap-1"
                  >
                    <span>👑</span>
                    <span>Premium</span>
                  </span>
                </div>
                <p class="text-sm text-text-muted">
                  {{ totalHashrate > 0 ? t('mining.activelyMining') : t('mining.rigsInactive') }}
                </p>
              </div>
            </div>

            <div class="text-right">
              <div class="text-3xl font-bold font-mono" :class="effectiveHashrate > 0 ? 'gradient-text' : 'text-text-muted'">
                {{ Math.round(effectiveHashrate).toLocaleString() }}
              </div>
              <div class="text-xs text-text-muted flex items-center justify-end gap-1">
                <span>{{ t('mining.effectiveHashrate') }}</span>
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
              <span class="text-text-muted">{{ t('mining.hashProgress') }}</span>
              <span class="font-mono text-accent-primary">{{ hashesCalculated.toFixed(0) }} hashes</span>
            </div>
            <div class="h-4 bg-bg-tertiary rounded-full overflow-hidden relative">
              <div
                class="h-full rounded-full transition-all duration-100"
                :class="showBlockFound ? 'bg-status-success' : 'bg-gradient-to-r from-accent-primary to-accent-secondary'"
                :style="{ width: `${miningProgress}%` }"
              ></div>
              <div
                v-if="totalHashrate > 0"
                class="absolute inset-0 bg-gradient-to-r from-transparent via-white/20 to-transparent"
                style="animation: shimmer 2s linear infinite;"
              ></div>
            </div>
          </div>

          <!-- Stats Grid (Network stats only) -->
          <div class="grid grid-cols-3 gap-3">
            <div class="bg-bg-secondary rounded-xl p-3 text-center relative">
              <div class="absolute top-1 right-1.5 text-[10px] text-text-muted/50">🌐</div>
              <div class="text-lg font-bold text-accent-tertiary">{{ networkStats.difficulty?.toLocaleString() ?? 0 }}</div>
              <div class="text-[10px] text-text-muted">{{ t('mining.difficulty') }}</div>
            </div>
            <div class="bg-bg-secondary rounded-xl p-3 text-center relative">
              <div class="absolute top-1 right-1.5 text-[10px] text-text-muted/50">🌐</div>
              <div class="text-lg font-bold text-accent-primary">{{ networkStats.activeMiners ?? 0 }}</div>
              <div class="text-[10px] text-text-muted">{{ t('mining.miners') }}</div>
            </div>
            <div class="bg-bg-secondary rounded-xl p-3 text-center relative">
              <div class="absolute top-1 right-1.5 text-[10px] text-text-muted/50">🌐</div>
              <div class="text-lg font-bold text-status-success">#{{ networkStats.latestBlock?.height ?? 0 }}</div>
              <div class="text-[10px] text-text-muted">{{ t('mining.lastBlock') }}</div>
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
            <div class="text-2xl font-bold text-status-success">{{ t('mining.blockMined') }}</div>
            <div class="text-lg text-white">#{{ lastBlockFound?.height }}</div>
          </div>
        </div>
      </div>

      <!-- Quick Stats - Above Rigs -->
      <div class="card mb-6">
        <h3 class="font-semibold mb-4 flex items-center gap-2">
          <span>📊</span> {{ t('mining.yourStats') }}
        </h3>
        <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-4">
          <div class="bg-bg-secondary rounded-xl p-3 text-center">
            <div class="text-lg font-bold font-mono">
              <span v-if="activeRigsCount > 0" :class="effectiveHashrate < totalHashrate ? 'text-status-warning' : ''">{{ Math.round(effectiveHashrate).toLocaleString() }}</span>
              <span v-else class="text-text-muted">--</span>
            </div>
            <div class="text-[10px] text-text-muted">{{ t('mining.hashrate') }}</div>
          </div>
          <div class="bg-bg-secondary rounded-xl p-3 text-center">
            <div class="text-lg font-bold font-mono">{{ activeRigsCount }} / {{ rigs.length }}</div>
            <div class="text-[10px] text-text-muted">{{ t('mining.activeRigsLabel') }}</div>
          </div>
          <div
            v-tooltip="t('mining.tooltips.probPerBlock')"
            class="bg-bg-secondary rounded-xl p-3 text-center cursor-help"
          >
            <div class="text-lg font-bold font-mono" :class="activeRigsCount > 0 ? 'text-status-warning' : 'text-text-muted'">
              {{ activeRigsCount > 0 ? miningChance.toFixed(2) + '%' : '--' }}
            </div>
            <div class="text-[10px] text-text-muted">{{ t('mining.probPerBlock') }}</div>
          </div>
          <!-- Mining Estimate Stats -->
          <div
            v-tooltip="t('mining.tooltips.nextBlock')"
            class="rounded-xl p-3 text-center cursor-help"
            :class="activeRigsCount > 0 && isEstimateMining ? 'bg-accent-primary/10 border border-accent-primary/30' : 'bg-bg-secondary'"
          >
            <div class="text-lg font-bold font-mono" :class="activeRigsCount > 0 && estimatedTimeText ? 'text-accent-primary' : 'text-text-muted'">
              {{ activeRigsCount > 0 && estimatedTimeText ? estimatedTimeText : '--' }}
            </div>
            <div class="text-[10px] text-text-muted flex items-center justify-center gap-1">
              <span>⏱️</span> {{ t('mining.nextBlock') }}
            </div>
          </div>
          <div
            v-tooltip="t('mining.tooltips.estimateRange')"
            class="bg-bg-secondary rounded-xl p-3 text-center cursor-help"
          >
            <div class="text-lg font-bold font-mono text-text-muted">
              {{ activeRigsCount > 0 && timeRangeText ? timeRangeText : '--' }}
            </div>
            <div class="text-[10px] text-text-muted">{{ t('mining.estimateRange') }}</div>
          </div>
          <div
            v-tooltip="t('mining.tooltips.blocksPerDay')"
            class="bg-bg-secondary rounded-xl p-3 text-center cursor-help"
          >
            <div class="text-lg font-bold font-mono" :class="activeRigsCount > 0 && blocksPerDayText ? 'text-status-success' : 'text-text-muted'">
              {{ activeRigsCount > 0 && blocksPerDayText ? blocksPerDayText : '--' }}
            </div>
            <div class="text-[10px] text-text-muted">{{ t('mining.blocksPerDay') }}</div>
          </div>
        </div>
      </div>

      <div class="grid lg:grid-cols-3 gap-6">
        <!-- Rigs Column -->
        <div class="lg:col-span-2 space-y-4">
          <h2 class="text-lg font-semibold flex items-center gap-2">
            <span>🖥️</span> {{ t('mining.yourRigs') }}
            <span
              v-if="slotInfo"
              class="text-sm font-normal px-2 py-0.5 rounded-full"
              :class="slotInfo.available_slots === 0 ? 'bg-status-warning/20 text-status-warning' : 'bg-accent-primary/20 text-accent-primary'"
            >
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
            <div
              v-for="playerRig in rigs"
              :key="playerRig.id"
              class="bg-bg-secondary/80 rounded-xl border p-4 relative overflow-hidden"
              :class="playerRig.condition <= 0 ? 'border-status-danger/70' : playerRig.condition < 30 ? 'border-status-warning/50' : 'border-border/30'"
            >
              <!-- Mining indicator dot -->
              <div v-if="playerRig.is_active" class="absolute top-3 right-3">
                <span class="relative flex h-2.5 w-2.5">
                  <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-status-success opacity-75"></span>
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
                  <div v-if="(playerRig.hashrate_level ?? 1) > 1 || (playerRig.efficiency_level ?? 1) > 1 || (playerRig.thermal_level ?? 1) > 1"
                       v-tooltip="t('mining.tooltips.upgrades') + ` - ⚡${playerRig.hashrate_level ?? 1} 💡${playerRig.efficiency_level ?? 1} ❄️${playerRig.thermal_level ?? 1}`"
                       class="flex items-center gap-1 text-[10px] px-1.5 py-0.5 bg-purple-500/20 rounded cursor-help">
                    <span v-if="(playerRig.hashrate_level ?? 1) > 1" class="text-yellow-400">⚡{{ playerRig.hashrate_level }}</span>
                    <span v-if="(playerRig.efficiency_level ?? 1) > 1" class="text-green-400">💡{{ playerRig.efficiency_level }}</span>
                    <span v-if="(playerRig.thermal_level ?? 1) > 1" class="text-cyan-400">❄️{{ playerRig.thermal_level }}</span>
                  </div>
                  <span v-tooltip="t('mining.tooltips.tier')" class="text-[11px] text-text-muted uppercase px-2 py-0.5 bg-bg-tertiary/50 rounded cursor-help">
                    {{ playerRig.rig.tier }}
                  </span>
                </div>
              </div>

              <!-- Hashrate -->
              <div v-tooltip="t('mining.tooltips.hashrate')" class="flex items-baseline gap-1.5 mb-3 cursor-help">
                <span
                  class="text-xl font-bold font-mono"
                  :class="playerRig.is_active
                    ? (miningStore.getRigHashrateBoostPercent(playerRig) > 0
                      ? 'text-status-success'
                      : miningStore.getRigPenaltyPercent(playerRig) > 0
                        ? 'text-status-warning'
                        : 'text-white')
                    : 'text-text-muted'"
                  :key="uptimeKey"
                >
                  {{ playerRig.is_active ? Math.round(miningStore.getRigEffectiveHashrate(playerRig)).toLocaleString() : '0' }}
                </span>
                <span class="text-sm text-text-muted">
                  / {{ getUpgradedHashrate(playerRig).toLocaleString() }} H/s
                  <span v-if="(playerRig.hashrate_level ?? 1) > 1" class="text-yellow-400 text-xs">(+{{ getHashrateBonus(playerRig) }}%)</span>
                </span>
                <span
                  v-if="playerRig.is_active && miningStore.getRigHashrateBoostPercent(playerRig) > 0"
                  class="text-xs text-status-success font-medium"
                >
                  (+{{ miningStore.getRigHashrateBoostPercent(playerRig) }}% ⚡)
                </span>
              </div>

              <!-- Stats row -->
              <div class="flex items-center gap-4 text-xs text-text-muted mb-3">
                <span v-tooltip="t('mining.tooltips.energy')" class="flex items-center gap-1 cursor-help">
                  <span class="text-status-warning">⚡</span>{{ (getUpgradedPower(playerRig) + getRigCoolingEnergy(playerRig.id)).toFixed(0) }}/t
                  <span v-if="(playerRig.efficiency_level ?? 1) > 1" class="text-green-400">(-{{ getEfficiencyBonus(playerRig) }}%)</span>
                  <span v-if="miningStore.getPowerPenaltyPercent(playerRig) > 0" class="text-status-danger">(+{{ miningStore.getPowerPenaltyPercent(playerRig) }}%)</span>
                </span>
                <span v-tooltip="t('mining.tooltips.internet')" class="flex items-center gap-1 cursor-help">
                  <span class="text-accent-tertiary">📡</span>{{ playerRig.rig.internet_consumption }}/t
                </span>
                <span v-if="rigCooling[playerRig.id]?.length > 0 || getThermalBonus(playerRig) > 0" v-tooltip="t('mining.tooltips.cooling')" class="flex items-center gap-1 cursor-help">
                  <span :class="isAnyCoolingDegraded(playerRig.id) ? 'text-status-warning' : 'text-cyan-400'">❄️</span>
                  <span :class="isAnyCoolingDegraded(playerRig.id) ? 'text-status-warning' : 'text-cyan-400'">
                    -{{ (getRigTotalCoolingPower(playerRig.id) + getThermalBonus(playerRig)).toFixed(0) }}°
                  </span>
                  <span v-if="getThermalBonus(playerRig) > 0" class="text-cyan-300 text-[10px]">(⬆{{ getThermalBonus(playerRig) }}°)</span>
                  <span v-if="isAnyCoolingDegraded(playerRig.id)" class="text-status-warning text-[10px]">
                    ⚠️
                  </span>
                </span>
                <span v-if="rigBoosts[playerRig.id]?.length > 0" v-tooltip="t('mining.tooltips.boosts') + ': ' + rigBoosts[playerRig.id].map((b: any) => b.name).join(', ')" class="flex items-center gap-1 cursor-help">
                  <span class="text-purple-400">🚀</span>
                  <span class="text-purple-400">{{ rigBoosts[playerRig.id].length }}</span>
                </span>
                <span v-if="playerRig.is_active && playerRig.activated_at" v-tooltip="t('mining.tooltips.uptime')" class="flex items-center gap-1 ml-auto cursor-help" :key="uptimeKey">
                  ⏱️ {{ formatUptime(playerRig.activated_at) }}
                </span>
              </div>

              <!-- Bars -->
              <div class="space-y-2 mb-3">
                <!-- Temperature -->
                <div v-tooltip="t('mining.tooltips.temperature')" class="flex items-center gap-2 cursor-help">
                  <span class="text-xs text-text-muted w-6">🌡️</span>
                  <div class="flex-1 h-2 bg-bg-tertiary rounded-full overflow-hidden">
                    <div
                      class="h-full rounded-full transition-all"
                      :class="getTempBarColor(playerRig.temperature ?? 25)"
                      :style="{ width: `${playerRig.temperature ?? 25}%` }"
                    ></div>
                  </div>
                  <span class="text-xs w-14 text-right" :class="getTempColor(playerRig.temperature ?? 25)">
                    {{ (playerRig.temperature ?? 25).toFixed(0) }}°C
                  </span>
                </div>
                <!-- Condition -->
                <div v-tooltip="t('mining.tooltips.condition')" class="flex items-center gap-2 cursor-help">
                  <span class="text-xs text-text-muted w-6">🔧</span>
                  <div class="flex-1 h-2 bg-bg-tertiary rounded-full overflow-hidden">
                    <div
                      class="h-full rounded-full"
                      :class="playerRig.condition > 50 ? 'bg-status-success' : playerRig.condition > 20 ? 'bg-status-warning' : 'bg-status-danger'"
                      :style="{ width: `${playerRig.condition}%` }"
                    ></div>
                  </div>
                  <span class="text-xs w-14 text-right" :class="playerRig.condition < 30 ? 'text-status-danger' : 'text-text-muted'">
                    {{ playerRig.condition }}%
                  </span>
                </div>
              </div>

              <!-- Action buttons -->
              <div class="flex gap-2">
                <button
                  @click="handleToggleRig(playerRig.id)"
                  :disabled="playerRig.condition <= 0"
                  class="flex-1 py-2 rounded-lg text-sm font-medium transition-all disabled:opacity-50"
                  :class="playerRig.condition <= 0
                    ? 'bg-status-danger/10 text-status-danger cursor-not-allowed'
                    : playerRig.is_active
                      ? 'bg-status-danger/10 text-status-danger hover:bg-status-danger/20'
                      : 'bg-status-success/10 text-status-success hover:bg-status-success/20'"
                >
                  {{ playerRig.condition <= 0 ? '🔧 ' + t('mining.repairInInventory') : (playerRig.is_active ? '⏹ ' + t('mining.stop') : '▶ ' + t('mining.start')) }}
                </button>
                <button
                  @click="openRigManage(playerRig)"
                  class="px-3 py-2 rounded-lg text-sm font-medium transition-all bg-bg-tertiary hover:bg-bg-tertiary/80 text-text-muted hover:text-white"
                  :title="t('mining.manage')"
                >
                  ⚙️
                </button>
              </div>
            </div>

            <!-- Empty Available Slots -->
            <div
              v-for="n in (slotInfo?.available_slots ?? 0)"
              :key="'empty-slot-' + n"
              class="bg-bg-secondary/50 rounded-xl border border-dashed border-border/50 p-4 flex flex-col items-center justify-center min-h-[200px]"
            >
              <div class="w-12 h-12 rounded-lg bg-bg-tertiary/50 flex items-center justify-center text-2xl mb-3 opacity-50">
                🖥️
              </div>
              <div class="text-text-muted font-medium">{{ t('slots.available', 'Disponible') }}</div>
              <p class="text-xs text-text-muted/70 mt-1">{{ t('slots.buyRigToUse', 'Compra un rig en el mercado') }}</p>
            </div>

            <!-- Slot Purchase Card -->
            <div
              v-if="slotInfo?.next_upgrade"
              class="bg-bg-secondary/80 rounded-xl border border-dashed border-accent-primary/50 p-4 flex flex-col justify-between min-h-[200px]"
            >
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

              <button
                @click="openSlotPurchaseConfirm"
                :disabled="!canAffordSlot()"
                class="w-full py-2.5 rounded-lg text-sm font-semibold transition-all"
                :class="canAffordSlot()
                  ? 'bg-gradient-primary hover:opacity-90'
                  : 'bg-bg-tertiary text-text-muted cursor-not-allowed'"
              >
                <span v-if="!canAffordSlot()">
                  {{ t('slots.insufficientFunds', 'Fondos insuficientes') }}
                </span>
                <span v-else>
                  {{ t('slots.buySlot', 'Comprar Slot') }}
                </span>
              </button>
            </div>

            <!-- Max slots reached card -->
            <div
              v-else-if="slotInfo && !slotInfo.next_upgrade"
              class="bg-status-success/10 rounded-xl border border-status-success/30 p-4 flex flex-col items-center justify-center min-h-[200px]"
            >
              <div class="text-4xl mb-2">🏆</div>
              <div class="text-status-success font-semibold text-center">{{ t('slots.maxReached', '¡Máximo alcanzado!') }}</div>
              <div class="text-sm text-text-muted">{{ slotInfo.max_slots }} slots</div>
            </div>
          </div>
        </div>

        <!-- Sidebar -->
        <div class="space-y-4">
          <!-- Recent Blocks -->
          <div class="card p-3">
            <h3 class="text-sm font-semibold mb-2 flex items-center gap-1.5 text-text-muted">
              <span>📦</span> {{ t('mining.recentBlocks') }}
            </h3>

            <div v-if="recentBlocks.length === 0" class="text-center py-4 text-text-muted text-xs">
              {{ t('mining.noBlocks') }}
            </div>

            <div v-else class="space-y-1.5">
              <div
                v-for="(block, index) in recentBlocks"
                :key="block.id"
                class="px-2.5 py-2 rounded-lg"
                :class="[
                  block.miner?.id === authStore.player?.id
                    ? 'bg-status-success/10 border border-status-success/20'
                    : block.is_premium
                      ? 'bg-amber-500/10 border border-amber-500/20'
                      : 'bg-bg-secondary/50'
                ]"
              >
                <!-- Row 1: Height + Time + Premium -->
                <div class="flex items-center justify-between mb-1">
                  <div class="flex items-center gap-1.5">
                    <span v-if="index === 0" class="text-xs">🆕</span>
                    <span v-if="block.is_premium" class="text-xs" title="Premium">👑</span>
                    <span class="font-mono text-sm font-medium" :class="block.miner?.id === authStore.player?.id ? 'text-status-success' : block.is_premium ? 'text-amber-400' : 'text-accent-primary'">#{{ block.height }}</span>
                  </div>
                  <span class="text-[10px] text-text-muted" :key="uptimeKey">{{ formatTimeAgo(block.created_at) }}</span>
                </div>
                <!-- Row 2: Miner + Reward -->
                <div class="flex items-center justify-between text-xs">
                  <span class="text-text-muted truncate max-w-[100px]">
                    {{ block.miner?.id === authStore.player?.id ? '⭐ ' + t('mining.you') : block.miner?.username ?? t('mining.unknown') }}
                  </span>
                  <span class="font-mono" :class="block.is_premium ? 'text-amber-400' : 'text-status-warning'">+{{ (block.reward ?? getBlockReward(block.height)).toFixed(0) }} ₿</span>
                </div>
              </div>
            </div>
          </div>

          <!-- AdSense Banner -->
          <div class="card p-3 text-center">
            <div class="text-xs text-text-muted mb-2">{{ t('blocks.sponsoredBy') }}</div>
            <div class="flex justify-center">
              <ins class="adsbygoogle"
                style="display:block; max-width:300px; width:100%; height:250px;"
                data-ad-format="rectangle"
                data-ad-client="ca-pub-7500429866047477"
                data-ad-slot="7767935377"></ins>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Rig Enhance Modal -->
    <RigEnhanceModal
      :show="showRigManage"
      :rig="selectedRigForManage"
      @close="closeRigManage"
      @updated="handleRigUpdated"
    />

    <!-- Slot Purchase Confirmation Modal -->
    <Teleport to="body">
      <Transition name="modal">
        <div
          v-if="showConfirmSlotPurchase && slotInfo?.next_upgrade"
          class="fixed inset-0 z-50 flex items-center justify-center p-4"
          @click.self="showConfirmSlotPurchase = false"
        >
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
                <span class="text-sm">{{ slotInfo.next_upgrade.currency === 'crypto' ? 'Crypto' : 'GC' }}</span>
              </div>
            </div>

            <p class="text-sm text-text-muted text-center mb-4">
              {{ t('slots.confirmMessage', '¿Estás seguro de que deseas comprar este slot?') }}
            </p>

            <div class="flex gap-3">
              <button
                @click="showConfirmSlotPurchase = false"
                :disabled="buyingSlot"
                class="flex-1 py-2.5 rounded-lg font-medium bg-bg-tertiary hover:bg-bg-tertiary/80 transition-colors"
              >
                {{ t('common.cancel', 'Cancelar') }}
              </button>
              <button
                @click="confirmBuySlot"
                :disabled="buyingSlot"
                class="flex-1 py-2.5 rounded-lg font-semibold bg-gradient-primary hover:opacity-90 transition-opacity"
              >
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
        <div
          v-if="showConfirmStopRig && rigToStop"
          class="fixed inset-0 z-50 flex items-center justify-center p-4"
          @click.self="cancelStopRig"
        >
          <div class="absolute inset-0 bg-black/70 backdrop-blur-sm"></div>
          <div class="relative bg-bg-primary border border-border rounded-2xl w-full max-w-sm p-6 shadow-2xl">
            <h3 class="text-lg font-bold mb-4 text-center">{{ t('mining.confirmStop', '¿Detener rig?') }}</h3>

            <div class="bg-bg-secondary rounded-xl p-4 mb-4">
              <div class="text-center mb-3">
                <div class="text-3xl mb-2">⏹️</div>
                <div class="font-semibold" :class="getTierColor(rigToStop.rig.tier)">{{ getRigName(rigToStop.rig.id) }}</div>
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
              <button
                @click="cancelStopRig"
                :disabled="stoppingRig"
                class="flex-1 py-2.5 rounded-lg font-medium bg-bg-tertiary hover:bg-bg-tertiary/80 transition-colors"
              >
                {{ t('common.cancel', 'Cancelar') }}
              </button>
              <button
                @click="confirmStopRig"
                :disabled="stoppingRig"
                class="flex-1 py-2.5 rounded-lg font-semibold bg-status-danger/20 text-status-danger hover:bg-status-danger/30 transition-colors"
              >
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
  0% { transform: translateX(-100%); }
  100% { transform: translateX(100%); }
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
