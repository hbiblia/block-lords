<script setup lang="ts">
import { ref, onMounted, onUnmounted, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAuthStore } from '@/stores/auth';
import { useMiningStore } from '@/stores/mining';
import { useNotificationsStore } from '@/stores/notifications';
import { getPlayerRigs, getNetworkStats, getRecentBlocks, toggleRig, getRigCooling, getPlayerSlotInfo, buyRigSlot, getPlayerBoosts } from '@/utils/api';
import { playSound } from '@/utils/sounds';
import MarketModal from '@/components/MarketModal.vue';
import InventoryModal from '@/components/InventoryModal.vue';
import ExchangeModal from '@/components/ExchangeModal.vue';
import RigManageModal from '@/components/RigManageModal.vue';

const { t } = useI18n();
const authStore = useAuthStore();
const miningStore = useMiningStore();
const notificationsStore = useNotificationsStore();

const showMarket = ref(false);
const showInventory = ref(false);
const showExchange = ref(false);
const showRigManage = ref(false);
const selectedRigForManage = ref<typeof rigs.value[0] | null>(null);

// Slot info
const slotInfo = ref<{
  current_slots: number;
  used_slots: number;
  available_slots: number;
  max_slots: number;
  next_upgrade: {
    slot_number: number;
    price: number;
    currency: string;
    name: string;
    description: string;
  } | null;
} | null>(null);

const buyingSlot = ref(false);
const showConfirmSlotPurchase = ref(false);

// Stop rig confirmation modal
const showConfirmStopRig = ref(false);
const rigToStop = ref<typeof rigs.value[0] | null>(null);
const stoppingRig = ref(false);
const stopRigError = ref<string | null>(null);

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
      await loadData();
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
  }
  return (authStore.player?.crypto_balance ?? 0) >= upgrade.price;
}

function openRigManage(rig: typeof rigs.value[0]) {
  selectedRigForManage.value = rig;
  showRigManage.value = true;
}

function closeRigManage() {
  showRigManage.value = false;
  selectedRigForManage.value = null;
}

const loading = ref(true);
const rigs = ref<Array<{
  id: string;
  is_active: boolean;
  condition: number;
  temperature: number;
  activated_at: string | null;
  max_condition?: number;
  times_repaired?: number;
  rig: {
    id: string;
    name: string;
    hashrate: number;
    power_consumption: number;
    internet_consumption: number;
    tier: string;
    repair_cost: number;
  };
}>>([]);

const networkStats = ref({
  difficulty: 1000,
  hashrate: 0,
  latestBlock: null as any,
  activeMiners: 0,
});

const recentBlocks = ref<any[]>([]);

// Cooling data per rig
const rigCooling = ref<Record<string, Array<{
  id: string;
  durability: number;
  name: string;
  cooling_power: number;
}>>>({});

// Active boosts
const activeBoosts = ref<Array<{
  id: string;
  boost_id: string;
  boost_type: string;
  name: string;
  effect_value: number;
  expires_at: string;
  seconds_remaining: number;
}>>([]);

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
    const [rigsData, networkData, blocksData, slotData] = await Promise.all([
      getPlayerRigs(authStore.player!.id),
      getNetworkStats(),
      getRecentBlocks(5),
      getPlayerSlotInfo(authStore.player!.id),
    ]);

    rigs.value = rigsData ?? [];
    networkStats.value = networkData;
    recentBlocks.value = blocksData ?? [];
    if (slotData?.success) {
      slotInfo.value = slotData;
    }

    // Sync active rigs to mining store for resource consumption display
    syncMiningStore();

    // Load cooling data in background (don't block initial render)
    loadRigsCooling();

    // Load active boosts
    loadActiveBoosts();
  } catch (e) {
    console.error('Error loading mining data:', e);
  } finally {
    loading.value = false;
  }
}

async function loadActiveBoosts() {
  try {
    const boostData = await getPlayerBoosts(authStore.player!.id);
    activeBoosts.value = boostData.active || [];
  } catch (e) {
    console.error('Error loading active boosts:', e);
  }
}

async function loadRigsCooling() {
  const coolingPromises = rigs.value.map(async (rig) => {
    try {
      const cooling = await getRigCooling(rig.id);
      return { rigId: rig.id, cooling: cooling ?? [] };
    } catch {
      return { rigId: rig.id, cooling: [] };
    }
  });

  const results = await Promise.all(coolingPromises);
  const coolingMap: Record<string, any[]> = {};
  results.forEach(({ rigId, cooling }) => {
    coolingMap[rigId] = cooling;
  });
  rigCooling.value = coolingMap;
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
      // Reset progress when all rigs are stopped
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

async function handleToggleRig(rigId: string) {
  const rig = rigs.value.find(r => r.id === rigId);

  if (!rig) return;

  // Si el rig está activo, mostrar modal de confirmación para parar
  if (rig.is_active) {
    rigToStop.value = rig;
    stopRigError.value = null;
    showConfirmStopRig.value = true;
    return;
  }

  // Pre-check: If trying to turn ON, verify resources are sufficient for at least one tick
  const player = authStore.player;
  if (player) {
    const requiredEnergy = rig.rig.power_consumption;
    const requiredInternet = rig.rig.internet_consumption;

    if (player.energy < requiredEnergy) {
      // Use addNotification directly to bypass deduplication (user-initiated action)
      notificationsStore.addNotification({
        type: 'energy_depleted',
        title: 'notifications.energyDepleted.title',
        message: 'notifications.energyDepleted.message',
        icon: '⚡',
        severity: 'error',
      });
      return;
    }
    if (player.internet < requiredInternet) {
      notificationsStore.addNotification({
        type: 'internet_depleted',
        title: 'notifications.internetDepleted.title',
        message: 'notifications.internetDepleted.message',
        icon: '📡',
        severity: 'error',
      });
      return;
    }
  }

  // Optimistic update for visual feedback (solo para encender)
  rig.is_active = true;
  syncMiningStore();
  playSound('click');

  try {
    const result = await toggleRig(authStore.player!.id, rigId);

    if (!result.success) {
      // Revert and resync from server to ensure UI matches DB state
      await loadData();
      playSound('error');
      notificationsStore.addNotification({
        type: 'rig_broken',
        title: 'common.error',
        message: 'mining.toggleError',
        icon: '⚠️',
        severity: 'error',
        data: { error: result.error },
      });
    } else {
      // Rig turned on successfully
      playSound('success');
    }
  } catch (e) {
    // Revert and resync from server on error
    await loadData();
    playSound('error');
    console.error('Error toggling rig:', e);
    notificationsStore.addNotification({
      type: 'rig_broken',
      title: 'common.error',
      message: 'mining.connectionError',
      icon: '⚠️',
      severity: 'error',
    });
  }
}

async function confirmStopRig() {
  if (!rigToStop.value || stoppingRig.value) return;

  stoppingRig.value = true;
  stopRigError.value = null;

  try {
    const result = await toggleRig(authStore.player!.id, rigToStop.value.id);

    if (!result.success) {
      playSound('error');
      stopRigError.value = result.error || t('mining.toggleError');
    } else {
      playSound('click');
      showConfirmStopRig.value = false;
      rigToStop.value = null;
      await loadData();
    }
  } catch (e) {
    console.error('Error stopping rig:', e);
    playSound('error');
    stopRigError.value = t('mining.connectionError');
  } finally {
    stoppingRig.value = false;
  }
}

function cancelStopRig() {
  showConfirmStopRig.value = false;
  rigToStop.value = null;
  stopRigError.value = null;
}

function handleBlockMined(event: CustomEvent) {
  const { block, winner } = event.detail;
  recentBlocks.value.unshift({
    ...block,
    miner: winner,
  });
  recentBlocks.value = recentBlocks.value.slice(0, 5);

  if (winner?.id === authStore.player?.id) {
    playSound('block_mined');
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

// Translation helper for rig names
function getRigName(id: string): string {
  const key = `market.items.rigs.${id}.name`;
  const translated = t(key);
  return translated !== key ? translated : id;
}

function getTempColor(temp: number): string {
  if (temp >= 80) return 'text-status-danger';
  if (temp >= 60) return 'text-status-warning';
  if (temp >= 40) return 'text-yellow-400';
  return 'text-status-success';
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

// Calcular consumo de energía efectivo (con penalización por temperatura)
// Fórmula: power_consumption * (1 + max(0, (temp - 40)) * 0.0083)
// A 100°C = +50% de consumo extra
function getRigEffectivePower(rig: typeof rigs.value[0]): number {
  const temp = rig.temperature ?? 25;
  const tempPenalty = 1 + Math.max(0, (temp - 40)) * 0.0083;
  return rig.rig.power_consumption * tempPenalty;
}

function getPowerPenaltyPercent(rig: typeof rigs.value[0]): number {
  const effective = getRigEffectivePower(rig);
  const base = rig.rig.power_consumption;
  if (base === 0) return 0;
  return Math.round(((effective - base) / base) * 100);
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

// Calculate block reward based on height (matches DB function)
function getBlockReward(height: number): number {
  const baseReward = 100;
  const halvingInterval = 10000;
  const halvings = Math.floor(height / halvingInterval);
  return baseReward / Math.pow(2, halvings);
}

// Format relative time
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

// Auto-refresh polling (cada 10 segundos)
let autoRefreshInterval: number | null = null;
const AUTO_REFRESH_INTERVAL = 10000; // 10 segundos

function startAutoRefresh() {
  if (autoRefreshInterval) return;
  autoRefreshInterval = window.setInterval(async () => {
    try {
      await loadData();
    } catch (e) {
      console.error('Auto-refresh error:', e);
    }
  }, AUTO_REFRESH_INTERVAL);
}

function stopAutoRefresh() {
  if (autoRefreshInterval) {
    clearInterval(autoRefreshInterval);
    autoRefreshInterval = null;
  }
}

function handleInventoryUsed() {
  // Refresh rig data when something is installed/used from inventory
  loadData();
}

// Debounce timer for cooling updates
let coolingDebounceTimer: number | null = null;

function handleRigsUpdated(event: CustomEvent) {
  const { eventType, new: newData, old: oldData } = event.detail;

  // Solo recargar todo si es INSERT o DELETE (rig nuevo o eliminado)
  if (eventType === 'INSERT' || eventType === 'DELETE') {
    loadData();
    return;
  }

  // Para UPDATE: actualizar directamente el rig específico sin llamar a la API
  if (eventType === 'UPDATE' && newData) {
    const rigIndex = rigs.value.findIndex(r => r.id === newData.id);
    if (rigIndex !== -1) {
      // Actualizar solo los campos que vienen del servidor
      const currentRig = rigs.value[rigIndex];
      rigs.value[rigIndex] = {
        ...currentRig,
        is_active: newData.is_active ?? currentRig.is_active,
        condition: newData.condition ?? currentRig.condition,
        temperature: newData.temperature ?? currentRig.temperature,
        activated_at: newData.activated_at ?? currentRig.activated_at,
      };
      // Sincronizar mining store si cambió el estado activo
      if (oldData && newData.is_active !== oldData.is_active) {
        syncMiningStore();
      }
    }
  }
}

function handleCoolingUpdated() {
  // Debounce: esperar 500ms de inactividad antes de recargar cooling
  if (coolingDebounceTimer) {
    clearTimeout(coolingDebounceTimer);
  }
  coolingDebounceTimer = window.setTimeout(() => {
    loadRigsCooling();
    coolingDebounceTimer = null;
  }, 500);
}

onMounted(() => {
  loadData();
  startMiningSimulation();
  startUptimeTimer();
  startAutoRefresh(); // Auto-refresh cada 10 segundos
  window.addEventListener('block-mined', handleBlockMined as EventListener);
  window.addEventListener('inventory-used', handleInventoryUsed as EventListener);
  window.addEventListener('player-rigs-updated', handleRigsUpdated as EventListener);
  window.addEventListener('rig-cooling-updated', handleCoolingUpdated as EventListener);
});

onUnmounted(() => {
  stopMiningSimulation();
  stopUptimeTimer();
  stopAutoRefresh(); // Detener auto-refresh
  // Limpiar debounce timer de cooling
  if (coolingDebounceTimer) {
    clearTimeout(coolingDebounceTimer);
    coolingDebounceTimer = null;
  }
  window.removeEventListener('block-mined', handleBlockMined as EventListener);
  window.removeEventListener('inventory-used', handleInventoryUsed as EventListener);
  window.removeEventListener('player-rigs-updated', handleRigsUpdated as EventListener);
  window.removeEventListener('rig-cooling-updated', handleCoolingUpdated as EventListener);
  // Clear mining store when leaving page
  miningStore.clearRigs();
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
        <div class="flex items-center gap-1 px-1 py-1 bg-bg-secondary/50 rounded-lg">
          <button @click="showMarket = true" class="px-3 py-1.5 text-sm font-medium rounded-md bg-accent-primary/20 text-accent-primary hover:bg-accent-primary/30 transition-all flex items-center gap-1.5">
            <span>🛒</span>
            <span class="hidden sm:inline">{{ t('mining.market') }}</span>
          </button>
          <button
            @click="showExchange = true"
            class="px-3 py-1.5 text-sm font-medium rounded-md bg-purple-500/20 text-purple-400 hover:bg-purple-500/30 transition-all flex items-center gap-1.5"
            :title="t('nav.exchange')"
          >
            <span>💱</span>
            <span class="hidden sm:inline">{{ t('nav.exchange') }}</span>
          </button>
          <button
            @click="showInventory = true"
            class="px-3 py-1.5 text-sm font-medium rounded-md bg-bg-tertiary hover:bg-bg-tertiary/80 transition-all flex items-center gap-1.5"
            :title="t('nav.inventory')"
          >
            <span>🎒</span>
            <span class="hidden sm:inline">{{ t('nav.inventory') }}</span>
          </button>
        </div>
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

    <div v-if="loading" class="text-center py-20 text-text-muted">
      <div class="w-12 h-12 mx-auto rounded-xl bg-gradient-primary flex items-center justify-center text-2xl animate-pulse mb-4">
        ⛏️
      </div>
      {{ t('mining.loadingStation') }}
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
                <h2 class="text-lg font-semibold">{{ t('mining.miningCenter') }}</h2>
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
              <!-- Efecto de brillo -->
              <div
                v-if="totalHashrate > 0"
                class="absolute inset-0 bg-gradient-to-r from-transparent via-white/20 to-transparent"
                style="animation: shimmer 2s linear infinite;"
              ></div>
            </div>
          </div>

          <!-- Stats Grid -->
          <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
            <!-- Private stat (user) -->
            <div class="bg-accent-primary/10 border border-accent-primary/30 rounded-xl p-3 text-center relative">
              <div class="absolute top-1 right-1.5 text-[10px] text-accent-primary/70">👤</div>
              <div class="text-lg font-bold text-status-warning">{{ miningChance.toFixed(2) }}%</div>
              <div class="text-[10px] text-text-muted">{{ t('mining.probability') }}</div>
            </div>
            <!-- Global stats (network) -->
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
            <button @click="showMarket = true" class="btn-primary">
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
                <span class="text-[11px] text-text-muted uppercase px-2 py-0.5 bg-bg-tertiary/50 rounded">
                  {{ playerRig.rig.tier }}
                </span>
              </div>

              <!-- Hashrate -->
              <div class="flex items-baseline gap-1.5 mb-3">
                <span
                  class="text-xl font-bold font-mono"
                  :class="playerRig.is_active ? (getRigPenaltyPercent(playerRig) > 0 ? 'text-status-warning' : 'text-white') : 'text-text-muted'"
                  :key="uptimeKey"
                >
                  {{ playerRig.is_active ? Math.round(getRigEffectiveHashrate(playerRig)).toLocaleString() : '0' }}
                </span>
                <span class="text-sm text-text-muted">/ {{ playerRig.rig.hashrate.toLocaleString() }} H/s</span>
              </div>

              <!-- Stats row -->
              <div class="flex items-center gap-4 text-xs text-text-muted mb-3">
                <span class="flex items-center gap-1">
                  <span class="text-status-warning">⚡</span>{{ playerRig.rig.power_consumption }}/t
                  <span v-if="getPowerPenaltyPercent(playerRig) > 0" class="text-status-danger">(+{{ getPowerPenaltyPercent(playerRig) }}%)</span>
                </span>
                <span class="flex items-center gap-1">
                  <span class="text-accent-tertiary">📡</span>{{ playerRig.rig.internet_consumption }}/t
                </span>
                <span v-if="rigCooling[playerRig.id]?.length > 0" class="flex items-center gap-1">
                  <span class="text-cyan-400">❄️</span>{{ rigCooling[playerRig.id][0].durability.toFixed(0) }}%
                </span>
                <span v-if="playerRig.is_active && playerRig.activated_at" class="flex items-center gap-1 ml-auto" :key="uptimeKey">
                  ⏱️ {{ formatUptime(playerRig.activated_at) }}
                </span>
              </div>

              <!-- Bars -->
              <div class="space-y-2 mb-3">
                <!-- Temperature -->
                <div class="flex items-center gap-2">
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
                <div class="flex items-center gap-2">
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
                    <span>{{ slotInfo.next_upgrade.currency === 'crypto' ? '💎' : '🪙' }}</span>
                    {{ slotInfo.next_upgrade.price.toLocaleString() }}
                    <span class="text-sm">{{ slotInfo.next_upgrade.currency === 'crypto' ? 'Crypto' : 'GC' }}</span>
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
                :class="block.miner?.id === authStore.player?.id ? 'bg-status-success/10 border border-status-success/20' : 'bg-bg-secondary/50'"
              >
                <!-- Row 1: Height + Time -->
                <div class="flex items-center justify-between mb-1">
                  <div class="flex items-center gap-1.5">
                    <span v-if="index === 0" class="text-xs">🆕</span>
                    <span class="font-mono text-sm font-medium" :class="block.miner?.id === authStore.player?.id ? 'text-status-success' : 'text-accent-primary'">#{{ block.height }}</span>
                  </div>
                  <span class="text-[10px] text-text-muted" :key="uptimeKey">{{ formatTimeAgo(block.created_at) }}</span>
                </div>
                <!-- Row 2: Miner + Reward -->
                <div class="flex items-center justify-between text-xs">
                  <span class="text-text-muted truncate max-w-[100px]">
                    {{ block.miner?.id === authStore.player?.id ? '⭐ ' + t('mining.you') : block.miner?.username ?? t('mining.unknown') }}
                  </span>
                  <span class="font-mono text-status-warning">+{{ getBlockReward(block.height).toFixed(0) }} ₿</span>
                </div>
              </div>
            </div>
          </div>

          <!-- Quick Stats -->
          <div class="card">
            <h3 class="font-semibold mb-4 flex items-center gap-2">
              <span>📊</span> {{ t('mining.yourStats') }}
            </h3>
            <div class="space-y-3">
              <div class="flex justify-between items-center">
                <span class="text-text-muted">{{ t('mining.hashrate') }}</span>
                <span class="font-mono font-medium">
                  <span :class="effectiveHashrate < totalHashrate ? 'text-status-warning' : ''">{{ Math.round(effectiveHashrate).toLocaleString() }}</span>
                  <span class="text-text-muted">/{{ totalHashrate.toLocaleString() }}</span>
                  <span class="text-xs text-text-muted ml-1">H/s</span>
                </span>
              </div>
              <div class="flex justify-between items-center">
                <span class="text-text-muted">{{ t('mining.activeRigsLabel') }}</span>
                <span class="font-mono font-medium">{{ activeRigsCount }} / {{ rigs.length }}</span>
              </div>
              <div class="flex justify-between items-center">
                <span class="text-text-muted">{{ t('mining.probPerBlock') }}</span>
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

    <!-- Inventory Modal -->
    <InventoryModal
      :show="showInventory"
      @close="showInventory = false"
      @used="loadData"
    />

    <!-- Exchange Modal -->
    <ExchangeModal
      :show="showExchange"
      @close="showExchange = false"
      @exchanged="authStore.fetchPlayer()"
    />

    <!-- Rig Manage Modal -->
    <RigManageModal
      :show="showRigManage"
      :rig="selectedRigForManage"
      @close="closeRigManage"
      @updated="loadData"
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
