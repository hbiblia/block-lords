<script setup lang="ts">
import { ref, onMounted, onUnmounted, watch } from 'vue';
import { useAuthStore } from '@/stores/auth';
import { getPlayerInventory, installCoolingToRig, redeemPrepaidCard, toggleRig, repairRig, deleteRig } from '@/utils/api';

const authStore = useAuthStore();

const props = defineProps<{
  show: boolean;
}>();

const emit = defineEmits<{
  close: [];
  used: [];
}>();

// Bloquear scroll del body cuando el modal está abierto
watch(() => props.show, (isOpen) => {
  if (isOpen) {
    document.body.style.overflow = 'hidden';
    loadInventory();
    startUptimeTimer();
  } else {
    document.body.style.overflow = '';
    selectedRigForCooling.value = null;
    stopUptimeTimer();
  }
});

onUnmounted(() => {
  document.body.style.overflow = '';
  stopUptimeTimer();
});

const loading = ref(false);
const using = ref(false);
const activeTab = ref<'rigs' | 'cooling' | 'cards'>('rigs');
const selectedRigForCooling = ref<string | null>(null);

// Confirmation dialog state
const showConfirm = ref(false);
const confirmAction = ref<{
  type: 'redeem' | 'install' | 'toggle' | 'repair' | 'delete';
  data: {
    rigId?: string;
    rigName?: string;
    rigCondition?: number;
    rigMaxCondition?: number;
    repairCost?: number;
    coolingId?: string;
    coolingName?: string;
    coolingPower?: number;
    cardCode?: string;
    cardName?: string;
    cardType?: 'energy' | 'internet';
    cardAmount?: number;
    isActive?: boolean;
  };
} | null>(null);

interface InstalledCoolingItem {
  id: string;
  durability: number;
  installed_at: string;
  item_id: string;
  name: string;
  cooling_power: number;
  energy_cost: number;
  tier: string;
}

interface CoolingItem {
  inventory_id: string;
  quantity: number;
  purchased_at: string;
  id: string;
  name: string;
  description: string;
  cooling_power: number;
  energy_cost: number;
  base_price: number;
  tier: string;
}

interface CardItem {
  id: string;
  code: string;
  is_redeemed: boolean;
  purchased_at: string;
  card_id: string;
  name: string;
  description: string;
  card_type: 'energy' | 'internet';
  amount: number;
  tier: string;
}

interface RigItem {
  id: string;
  is_active: boolean;
  condition: number;
  temperature: number;
  acquired_at: string;
  activated_at: string | null;
  max_condition: number;
  times_repaired: number;
  rig_id: string;
  name: string;
  description: string;
  hashrate: number;
  power_consumption: number;
  internet_consumption: number;
  tier: string;
  repair_cost: number;
  installed_cooling: InstalledCoolingItem[];
}

const coolingItems = ref<CoolingItem[]>([]);
const cardItems = ref<CardItem[]>([]);
const rigItems = ref<RigItem[]>([]);

async function loadInventory() {
  if (!authStore.player) return;
  loading.value = true;

  try {
    const data = await getPlayerInventory(authStore.player.id);
    coolingItems.value = data.cooling || [];
    cardItems.value = data.cards || [];
    rigItems.value = data.rigs || [];
  } catch (e) {
    console.error('Error loading inventory:', e);
  } finally {
    loading.value = false;
  }
}

function requestInstallCooling(rig: RigItem, cooling: CoolingItem) {
  confirmAction.value = {
    type: 'install',
    data: {
      rigId: rig.id,
      rigName: rig.name,
      coolingId: cooling.id,
      coolingName: cooling.name,
      coolingPower: cooling.cooling_power,
    },
  };
  showConfirm.value = true;
}

async function handleInstallCooling(rigId: string, coolingId: string) {
  if (!authStore.player || using.value) return;
  using.value = true;

  try {
    const result = await installCoolingToRig(authStore.player.id, rigId, coolingId);
    if (result.success) {
      await loadInventory();
      await authStore.fetchPlayer();
      selectedRigForCooling.value = null;
      emit('used');
    } else {
      alert(result.error || 'Error al instalar');
    }
  } catch (e) {
    console.error('Error installing cooling:', e);
    alert('Error al instalar refrigeración');
  } finally {
    using.value = false;
  }
}

function requestRedeemCard(card: CardItem) {
  confirmAction.value = {
    type: 'redeem',
    data: {
      cardCode: card.code,
      cardName: card.name,
      cardType: card.card_type,
      cardAmount: card.amount,
    },
  };
  showConfirm.value = true;
}

async function handleRedeemCard(code: string) {
  if (!authStore.player || using.value) return;
  using.value = true;

  try {
    const result = await redeemPrepaidCard(authStore.player.id, code);
    if (result.success) {
      await loadInventory();
      await authStore.fetchPlayer();
      emit('used');
    } else {
      alert(result.error || 'Error al canjear');
    }
  } catch (e) {
    console.error('Error redeeming card:', e);
    alert('Error al canjear tarjeta');
  } finally {
    using.value = false;
  }
}

function requestToggleRig(rig: RigItem) {
  confirmAction.value = {
    type: 'toggle',
    data: {
      rigId: rig.id,
      rigName: rig.name,
      isActive: rig.is_active,
    },
  };
  showConfirm.value = true;
}

async function handleToggleRig(rigId: string) {
  if (!authStore.player || using.value) return;
  using.value = true;

  try {
    const result = await toggleRig(authStore.player.id, rigId);
    if (result.success) {
      await loadInventory();
      emit('used');
    } else {
      alert(result.error || 'Error al cambiar estado del rig');
    }
  } catch (e) {
    console.error('Error toggling rig:', e);
    alert('Error al cambiar estado del rig');
  } finally {
    using.value = false;
  }
}

function requestRepairRig(rig: RigItem) {
  confirmAction.value = {
    type: 'repair',
    data: {
      rigId: rig.id,
      rigName: rig.name,
      rigCondition: rig.condition,
      rigMaxCondition: rig.max_condition,
      repairCost: rig.repair_cost,
    },
  };
  showConfirm.value = true;
}

async function handleRepairRig(rigId: string) {
  if (!authStore.player || using.value) return;
  using.value = true;

  try {
    const result = await repairRig(authStore.player.id, rigId);
    if (result.success) {
      await loadInventory();
      await authStore.fetchPlayer();
      emit('used');
    } else {
      alert(result.error || 'Error al reparar rig');
    }
  } catch (e) {
    console.error('Error repairing rig:', e);
    alert('Error al reparar rig');
  } finally {
    using.value = false;
  }
}

function requestDeleteRig(rig: RigItem) {
  confirmAction.value = {
    type: 'delete',
    data: {
      rigId: rig.id,
      rigName: rig.name,
      rigCondition: rig.condition,
      rigMaxCondition: rig.max_condition,
    },
  };
  showConfirm.value = true;
}

async function handleDeleteRig(rigId: string) {
  if (!authStore.player || using.value) return;
  using.value = true;

  try {
    const result = await deleteRig(authStore.player.id, rigId);
    if (result.success) {
      await loadInventory();
      emit('used');
    } else {
      alert(result.error || 'Error al eliminar rig');
    }
  } catch (e) {
    console.error('Error deleting rig:', e);
    alert('Error al eliminar rig');
  } finally {
    using.value = false;
  }
}

async function confirmUse() {
  if (!confirmAction.value) return;

  const { type, data } = confirmAction.value;
  showConfirm.value = false;

  if (type === 'install' && data.rigId && data.coolingId) {
    await handleInstallCooling(data.rigId, data.coolingId);
  } else if (type === 'redeem' && data.cardCode) {
    await handleRedeemCard(data.cardCode);
  } else if (type === 'toggle' && data.rigId) {
    await handleToggleRig(data.rigId);
  } else if (type === 'repair' && data.rigId) {
    await handleRepairRig(data.rigId);
  } else if (type === 'delete' && data.rigId) {
    await handleDeleteRig(data.rigId);
  }

  confirmAction.value = null;
}

function cancelUse() {
  showConfirm.value = false;
  confirmAction.value = null;
}

function getTierColor(tier: string) {
  switch (tier) {
    case 'elite': return 'text-yellow-400';
    case 'advanced': return 'text-purple-400';
    case 'standard': return 'text-blue-400';
    case 'basic': return 'text-green-400';
    default: return 'text-text-muted';
  }
}

function getTierBorder(tier: string) {
  switch (tier) {
    case 'elite': return 'border-yellow-400/50';
    case 'advanced': return 'border-purple-400/50';
    case 'standard': return 'border-blue-400/50';
    case 'basic': return 'border-green-400/50';
    default: return 'border-border';
  }
}

function getDurabilityColor(durability: number) {
  if (durability > 60) return 'text-status-success';
  if (durability > 30) return 'text-status-warning';
  return 'text-status-danger';
}

function getTotalCoolingPower(rig: RigItem) {
  return rig.installed_cooling?.reduce((sum, c) => sum + (c.cooling_power * c.durability / 100), 0) || 0;
}

function getRigEffectiveHashrate(rig: RigItem): number {
  const temp = rig.temperature ?? 25;
  const condition = rig.condition ?? 100;
  // Penalización por temperatura: >50°C reduce hashrate (hasta 70% a 100°C)
  let tempPenalty = 1;
  if (temp > 50) {
    tempPenalty = 1 - ((temp - 50) * 0.014);
    tempPenalty = Math.max(0.3, tempPenalty);
  }
  // Penalización por condición: 0-100% condición = 20-100% hashrate
  const conditionPenalty = 0.2 + (condition / 100) * 0.8;
  return rig.hashrate * conditionPenalty * tempPenalty;
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
  if (props.show) {
    loadInventory();
  }
});
</script>

<template>
  <Teleport to="body">
    <div
      v-if="show"
      class="fixed inset-0 z-50 flex items-center justify-center p-4"
    >
      <!-- Overlay -->
      <div
        class="absolute inset-0 bg-black/70 backdrop-blur-sm"
        @click="emit('close')"
      ></div>

      <!-- Modal -->
      <div class="relative w-full max-w-4xl max-h-[85vh] flex flex-col card overflow-hidden">
        <!-- Header -->
        <div class="flex items-center justify-between p-4 border-b border-border">
          <h2 class="text-xl font-display font-bold flex items-center gap-2">
            <span>🎒</span>
            <span class="gradient-text">Inventario</span>
          </h2>
          <button
            @click="emit('close')"
            class="p-2 hover:bg-bg-tertiary rounded-lg transition-colors"
          >
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        <!-- Tabs -->
        <div class="flex gap-2 p-4 border-b border-border bg-bg-secondary/50">
          <button
            @click="activeTab = 'rigs'"
            class="px-4 py-2 rounded-lg font-medium transition-all"
            :class="activeTab === 'rigs'
              ? 'bg-accent-primary text-white'
              : 'bg-bg-tertiary hover:bg-bg-tertiary/80'"
          >
            <span class="mr-2">🖥️</span>
            Rigs ({{ rigItems.length }})
          </button>
          <button
            @click="activeTab = 'cooling'"
            class="px-4 py-2 rounded-lg font-medium transition-all"
            :class="activeTab === 'cooling'
              ? 'bg-accent-secondary text-white'
              : 'bg-bg-tertiary hover:bg-bg-tertiary/80'"
          >
            <span class="mr-2">❄️</span>
            Refrigeración ({{ coolingItems.length }})
          </button>
          <button
            @click="activeTab = 'cards'"
            class="px-4 py-2 rounded-lg font-medium transition-all"
            :class="activeTab === 'cards'
              ? 'bg-accent-tertiary text-white'
              : 'bg-bg-tertiary hover:bg-bg-tertiary/80'"
          >
            <span class="mr-2">💳</span>
            Tarjetas ({{ cardItems.length }})
          </button>
        </div>

        <!-- Content -->
        <div class="flex-1 overflow-y-auto p-4">
          <!-- Loading -->
          <div v-if="loading" class="text-center py-12 text-text-muted">
            <div class="animate-spin w-8 h-8 border-2 border-accent-primary border-t-transparent rounded-full mx-auto mb-4"></div>
            Cargando inventario...
          </div>

          <!-- Rigs Tab -->
          <div v-else-if="activeTab === 'rigs'">
            <p class="text-sm text-text-muted mb-4">
              Gestiona tus rigs y la refrigeración instalada. La condición baja con el uso y la temperatura afecta el rendimiento.
            </p>
            <div v-if="rigItems.length === 0" class="text-center py-12 text-text-muted">
              <div class="text-4xl mb-4">🖥️</div>
              <p>No tienes rigs. Compra uno en el mercado.</p>
            </div>
            <div v-else class="space-y-4">
              <div
                v-for="rig in rigItems"
                :key="rig.id"
                class="p-4 rounded-xl border-2 transition-all"
                :class="[
                  getTierBorder(rig.tier),
                  rig.is_active ? 'bg-status-success/5' : 'bg-bg-secondary'
                ]"
              >
                <div class="flex items-start justify-between mb-3">
                  <div>
                    <h3 class="font-bold text-lg" :class="getTierColor(rig.tier)">{{ rig.name }}</h3>
                    <p class="text-xs text-text-muted capitalize">{{ rig.tier }}</p>
                  </div>
                  <span
                    class="px-2 py-1 text-xs font-medium rounded-full"
                    :class="rig.is_active ? 'bg-status-success/20 text-status-success' : 'bg-bg-tertiary text-text-muted'"
                  >
                    {{ rig.is_active ? 'Minando' : 'Inactivo' }}
                  </span>
                </div>

                <!-- Stats Grid -->
                <div class="grid grid-cols-2 md:grid-cols-6 gap-3 mb-4" :key="uptimeKey">
                  <div class="bg-bg-primary/50 rounded-lg p-2 text-center">
                    <div class="text-xs text-text-muted mb-1">Hashrate</div>
                    <div class="font-mono font-bold">
                      <span :class="getRigEffectiveHashrate(rig) < rig.hashrate ? 'text-status-warning' : 'text-accent-primary'">
                        {{ Math.round(getRigEffectiveHashrate(rig)) }}
                      </span>
                      <span class="text-text-muted text-xs">/{{ rig.hashrate }}</span>
                    </div>
                  </div>
                  <div class="bg-bg-primary/50 rounded-lg p-2 text-center">
                    <div class="text-xs text-text-muted mb-1">Temperatura</div>
                    <div class="font-mono font-bold" :class="Number(rig.temperature ?? 25) > 50 ? (Number(rig.temperature ?? 25) > 70 ? 'text-status-danger' : 'text-status-warning') : 'text-status-success'">
                      {{ Number(rig.temperature ?? 25).toFixed(1) }}°C
                    </div>
                  </div>
                  <div class="bg-bg-primary/50 rounded-lg p-2 text-center">
                    <div class="text-xs text-text-muted mb-1">Condicion</div>
                    <div class="font-mono font-bold" :class="Number(rig.condition ?? 0) < 30 ? 'text-status-danger' : (Number(rig.condition ?? 0) < 60 ? 'text-status-warning' : 'text-status-success')">
                      {{ Number(rig.condition ?? 0).toFixed(0) }}%
                    </div>
                  </div>
                  <div class="bg-bg-primary/50 rounded-lg p-2 text-center">
                    <div class="text-xs text-text-muted mb-1">Max Cond.</div>
                    <div class="font-mono font-bold" :class="Number(rig.max_condition ?? 100) <= 10 ? 'text-status-danger' : (Number(rig.max_condition ?? 100) < 50 ? 'text-status-warning' : 'text-text-primary')">
                      {{ Number(rig.max_condition ?? 100).toFixed(0) }}%
                    </div>
                  </div>
                  <div class="bg-bg-primary/50 rounded-lg p-2 text-center">
                    <div class="text-xs text-text-muted mb-1">Refrigeracion</div>
                    <div class="font-mono font-bold text-cyan-400">
                      {{ getTotalCoolingPower(rig).toFixed(0) }}
                    </div>
                  </div>
                  <div class="bg-bg-primary/50 rounded-lg p-2 text-center">
                    <div class="text-xs text-text-muted mb-1">Encendido</div>
                    <div class="font-mono font-bold" :class="rig.is_active ? 'text-accent-primary' : 'text-text-muted'">
                      {{ rig.is_active && rig.activated_at ? formatUptime(rig.activated_at) : '--' }}
                    </div>
                  </div>
                </div>

                <!-- Degradation Warning -->
                <div
                  v-if="Number(rig.max_condition ?? 100) <= 10"
                  class="mb-3 p-2 rounded-lg bg-status-danger/20 border border-status-danger/50 text-status-danger text-sm"
                >
                  ⚠️ Este rig está muy degradado y no puede repararse. Debes eliminarlo.
                </div>
                <div
                  v-else-if="Number(rig.max_condition ?? 100) < 50"
                  class="mb-3 p-2 rounded-lg bg-status-warning/20 border border-status-warning/50 text-status-warning text-xs"
                >
                  ⚠️ Rig degradado ({{ rig.times_repaired || 0 }} reparaciones). Max condición: {{ Number(rig.max_condition ?? 100).toFixed(0) }}%
                </div>

                <!-- Installed Cooling -->
                <div v-if="rig.installed_cooling && rig.installed_cooling.length > 0" class="mb-4">
                  <h4 class="text-xs font-medium text-text-muted mb-2 flex items-center gap-1">
                    <span>❄️</span> Refrigeracion Instalada
                  </h4>
                  <div class="flex flex-wrap gap-2">
                    <div
                      v-for="cooling in rig.installed_cooling"
                      :key="cooling.id"
                      class="flex items-center gap-2 px-3 py-1.5 bg-cyan-500/10 rounded-lg border border-cyan-500/30"
                    >
                      <span class="text-sm" :class="getTierColor(cooling.tier)">{{ cooling.name }}</span>
                      <span class="text-xs text-cyan-400">+{{ cooling.cooling_power }}</span>
                      <div class="flex items-center gap-1">
                        <div class="w-12 h-1.5 bg-bg-tertiary rounded-full overflow-hidden">
                          <div
                            class="h-full rounded-full transition-all"
                            :class="cooling.durability > 60 ? 'bg-status-success' : (cooling.durability > 30 ? 'bg-status-warning' : 'bg-status-danger')"
                            :style="{ width: `${cooling.durability}%` }"
                          ></div>
                        </div>
                        <span class="text-xs" :class="getDurabilityColor(cooling.durability)">{{ cooling.durability.toFixed(0) }}%</span>
                      </div>
                    </div>
                  </div>
                </div>

                <!-- Install Cooling Button -->
                <div v-if="coolingItems.length > 0" class="mb-3">
                  <button
                    v-if="selectedRigForCooling !== rig.id"
                    @click="selectedRigForCooling = rig.id"
                    class="text-xs px-3 py-1.5 rounded-lg bg-cyan-500/20 text-cyan-400 hover:bg-cyan-500/30 transition-all"
                  >
                    + Instalar Refrigeracion
                  </button>
                  <div v-else class="space-y-2">
                    <p class="text-xs text-text-muted">Selecciona refrigeracion a instalar:</p>
                    <div class="flex flex-wrap gap-2">
                      <button
                        v-for="cooling in coolingItems"
                        :key="cooling.id"
                        @click="requestInstallCooling(rig, cooling)"
                        :disabled="using"
                        class="px-3 py-1.5 text-xs rounded-lg bg-cyan-500/20 text-cyan-400 hover:bg-cyan-500/30 transition-all disabled:opacity-50"
                      >
                        {{ cooling.name }} (+{{ cooling.cooling_power }})
                      </button>
                      <button
                        @click="selectedRigForCooling = null"
                        class="px-3 py-1.5 text-xs rounded-lg bg-bg-tertiary text-text-muted hover:bg-bg-tertiary/80"
                      >
                        Cancelar
                      </button>
                    </div>
                  </div>
                </div>

                <!-- Action Buttons -->
                <div class="flex gap-2">
                  <!-- Toggle Button -->
                  <button
                    @click="requestToggleRig(rig)"
                    :disabled="using || rig.condition <= 0"
                    class="flex-1 py-2 rounded-lg font-medium transition-all disabled:opacity-50"
                    :class="rig.is_active
                      ? 'bg-status-danger/20 text-status-danger hover:bg-status-danger/30'
                      : 'bg-status-success/20 text-status-success hover:bg-status-success/30'"
                  >
                    {{ rig.condition <= 0 ? 'Roto' : (rig.is_active ? 'Apagar' : 'Encender') }}
                  </button>

                  <!-- Repair Button -->
                  <button
                    v-if="rig.condition < (rig.max_condition ?? 100) && Number(rig.max_condition ?? 100) > 10"
                    @click="requestRepairRig(rig)"
                    :disabled="using || rig.is_active"
                    class="px-4 py-2 rounded-lg font-medium transition-all bg-status-warning/20 text-status-warning hover:bg-status-warning/30 disabled:opacity-50"
                    :title="rig.is_active ? 'Apaga el rig primero' : `Reparar por ${rig.repair_cost} GC`"
                  >
                    🔧 Reparar
                  </button>

                  <!-- Delete Button -->
                  <button
                    @click="requestDeleteRig(rig)"
                    :disabled="using || rig.is_active"
                    class="px-4 py-2 rounded-lg font-medium transition-all bg-red-500/20 text-red-400 hover:bg-red-500/30 disabled:opacity-50"
                    :title="rig.is_active ? 'Apaga el rig primero' : 'Eliminar rig'"
                  >
                    🗑️
                  </button>
                </div>
              </div>
            </div>
          </div>

          <!-- Cooling Tab -->
          <div v-else-if="activeTab === 'cooling'">
            <p class="text-sm text-text-muted mb-4">
              Los items de refrigeracion se instalan en rigs especificos. La durabilidad se consume mientras el rig esta activo.
            </p>
            <div v-if="coolingItems.length === 0" class="text-center py-12 text-text-muted bg-bg-secondary rounded-lg">
              <div class="text-4xl mb-4">❄️</div>
              <p>No tienes items de refrigeracion en el inventario.</p>
              <p class="text-xs mt-2">Compra en el mercado y vuelve para instalarlos en tus rigs.</p>
            </div>
            <div v-else class="grid sm:grid-cols-2 gap-4">
              <div
                v-for="item in coolingItems"
                :key="item.inventory_id"
                class="p-4 rounded-xl border-2 bg-bg-secondary"
                :class="getTierBorder(item.tier)"
              >
                <div class="flex items-start justify-between mb-2">
                  <div>
                    <h4 class="font-bold" :class="getTierColor(item.tier)">{{ item.name }}</h4>
                    <p class="text-xs text-text-muted capitalize">{{ item.tier }}</p>
                  </div>
                  <div class="text-right">
                    <div class="text-lg font-mono text-cyan-400">+{{ item.cooling_power }}</div>
                    <div class="text-xs text-text-muted">poder</div>
                  </div>
                </div>
                <p class="text-xs text-text-muted mb-2">{{ item.description }}</p>
                <div class="flex items-center gap-2 text-xs mb-3">
                  <span class="text-status-warning">+{{ item.energy_cost }} energia/tick</span>
                  <span class="text-text-muted">|</span>
                  <span class="text-text-muted">Cantidad: {{ item.quantity }}</span>
                </div>
                <p class="text-xs text-accent-primary">
                  Ve a la pestana de Rigs para instalar en un rig especifico
                </p>
              </div>
            </div>
          </div>

          <!-- Cards Tab -->
          <div v-else-if="activeTab === 'cards'">
            <div v-if="cardItems.length === 0" class="text-center py-12 text-text-muted">
              <div class="text-4xl mb-4">💳</div>
              <p>No tienes tarjetas prepago. Compra una en el mercado.</p>
            </div>
            <div v-else class="grid sm:grid-cols-2 gap-4">
              <div
                v-for="card in cardItems"
                :key="card.id"
                class="p-4 rounded-xl border-2 bg-bg-secondary"
                :class="getTierBorder(card.tier)"
              >
                <div class="flex items-start justify-between mb-3">
                  <div>
                    <h3 class="font-bold" :class="getTierColor(card.tier)">{{ card.name }}</h3>
                    <p class="text-xs text-text-muted capitalize">{{ card.tier }}</p>
                  </div>
                  <div class="text-2xl">
                    {{ card.card_type === 'energy' ? '⚡' : '📡' }}
                  </div>
                </div>

                <p class="text-xs text-text-muted mb-3">{{ card.description }}</p>

                <div class="flex items-center justify-between mb-3 p-2 bg-bg-tertiary rounded-lg">
                  <span class="text-xs text-text-muted">Codigo:</span>
                  <span class="font-mono font-bold text-accent-primary">{{ card.code }}</span>
                </div>

                <div class="flex items-center justify-between mb-3 text-sm">
                  <span class="text-text-muted">Recarga:</span>
                  <span class="font-bold" :class="card.card_type === 'energy' ? 'text-status-warning' : 'text-accent-tertiary'">
                    +{{ card.amount }}% {{ card.card_type === 'energy' ? 'Energia' : 'Internet' }}
                  </span>
                </div>

                <button
                  @click="requestRedeemCard(card)"
                  :disabled="using"
                  class="w-full py-2 rounded-lg font-medium transition-all"
                  :class="card.card_type === 'energy'
                    ? 'bg-status-warning/20 text-status-warning hover:bg-status-warning/30'
                    : 'bg-accent-tertiary/20 text-accent-tertiary hover:bg-accent-tertiary/30'"
                >
                  {{ using ? 'Canjeando...' : 'Canjear Ahora' }}
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Confirmation Dialog -->
      <div
        v-if="showConfirm && confirmAction"
        class="absolute inset-0 flex items-center justify-center bg-black/50 z-10"
      >
        <div class="bg-bg-secondary rounded-xl p-6 max-w-sm w-full mx-4 border border-border animate-fade-in">
          <div class="text-center mb-4">
            <div class="text-4xl mb-3">
              {{ confirmAction.type === 'install' ? '❄️' : confirmAction.type === 'redeem' ? '💳' : confirmAction.type === 'repair' ? '🔧' : confirmAction.type === 'delete' ? '🗑️' : '🖥️' }}
            </div>
            <h3 class="text-lg font-bold mb-1">
              {{ confirmAction.type === 'install' ? 'Instalar Refrigeracion' : confirmAction.type === 'redeem' ? 'Canjear Tarjeta' : confirmAction.type === 'repair' ? 'Reparar Rig' : confirmAction.type === 'delete' ? 'Eliminar Rig' : (confirmAction.data.isActive ? 'Apagar Rig' : 'Encender Rig') }}
            </h3>
            <p class="text-text-muted text-sm">¿Estas seguro de realizar esta accion?</p>
          </div>

          <div class="bg-bg-primary rounded-lg p-4 mb-4">
            <!-- Install cooling details -->
            <template v-if="confirmAction.type === 'install'">
              <div class="flex items-center justify-between mb-2">
                <span class="text-text-muted text-sm">Rig:</span>
                <span class="font-medium text-white">{{ confirmAction.data.rigName }}</span>
              </div>
              <div class="flex items-center justify-between mb-2">
                <span class="text-text-muted text-sm">Refrigeracion:</span>
                <span class="font-medium text-cyan-400">{{ confirmAction.data.coolingName }}</span>
              </div>
              <div class="flex items-center justify-between">
                <span class="text-text-muted text-sm">Poder:</span>
                <span class="font-bold text-cyan-400">+{{ confirmAction.data.coolingPower }}</span>
              </div>
            </template>

            <!-- Redeem card details -->
            <template v-else-if="confirmAction.type === 'redeem'">
              <div class="flex items-center justify-between mb-2">
                <span class="text-text-muted text-sm">Tarjeta:</span>
                <span class="font-medium text-white">{{ confirmAction.data.cardName }}</span>
              </div>
              <div class="flex items-center justify-between">
                <span class="text-text-muted text-sm">Recarga:</span>
                <span class="font-bold" :class="confirmAction.data.cardType === 'energy' ? 'text-status-warning' : 'text-accent-tertiary'">
                  +{{ confirmAction.data.cardAmount }}% {{ confirmAction.data.cardType === 'energy' ? 'Energia' : 'Internet' }}
                </span>
              </div>
            </template>

            <!-- Toggle rig details -->
            <template v-else-if="confirmAction.type === 'toggle'">
              <div class="flex items-center justify-between mb-2">
                <span class="text-text-muted text-sm">Rig:</span>
                <span class="font-medium text-white">{{ confirmAction.data.rigName }}</span>
              </div>
              <div class="flex items-center justify-between">
                <span class="text-text-muted text-sm">Accion:</span>
                <span class="font-bold" :class="confirmAction.data.isActive ? 'text-status-danger' : 'text-status-success'">
                  {{ confirmAction.data.isActive ? 'Apagar mineria' : 'Iniciar mineria' }}
                </span>
              </div>
            </template>

            <!-- Repair rig details -->
            <template v-else-if="confirmAction.type === 'repair'">
              <div class="flex items-center justify-between mb-2">
                <span class="text-text-muted text-sm">Rig:</span>
                <span class="font-medium text-white">{{ confirmAction.data.rigName }}</span>
              </div>
              <div class="flex items-center justify-between mb-2">
                <span class="text-text-muted text-sm">Condicion actual:</span>
                <span class="font-bold text-status-danger">{{ Number(confirmAction.data.rigCondition ?? 0).toFixed(0) }}%</span>
              </div>
              <div class="flex items-center justify-between mb-2">
                <span class="text-text-muted text-sm">Reparar a:</span>
                <span class="font-bold text-status-warning">{{ Number((confirmAction.data.rigMaxCondition ?? 100) - 5).toFixed(0) }}%</span>
              </div>
              <div class="flex items-center justify-between">
                <span class="text-text-muted text-sm">Costo:</span>
                <span class="font-bold text-accent-primary">{{ confirmAction.data.repairCost }} GC</span>
              </div>
              <p class="text-xs text-status-warning mt-2">
                ⚠️ La condicion maxima se reducira en 5% despues de cada reparacion.
              </p>
            </template>

            <!-- Delete rig details -->
            <template v-else-if="confirmAction.type === 'delete'">
              <div class="flex items-center justify-between mb-2">
                <span class="text-text-muted text-sm">Rig:</span>
                <span class="font-medium text-white">{{ confirmAction.data.rigName }}</span>
              </div>
              <div class="flex items-center justify-between mb-2">
                <span class="text-text-muted text-sm">Condicion actual:</span>
                <span class="font-bold text-status-danger">{{ Number(confirmAction.data.rigCondition ?? 0).toFixed(0) }}%</span>
              </div>
              <div class="flex items-center justify-between">
                <span class="text-text-muted text-sm">Max condicion:</span>
                <span class="font-bold text-status-danger">{{ Number(confirmAction.data.rigMaxCondition ?? 100).toFixed(0) }}%</span>
              </div>
              <p class="text-xs text-status-danger mt-2">
                ⚠️ Esta accion no se puede deshacer. El rig sera eliminado permanentemente.
              </p>
            </template>
          </div>

          <div class="flex gap-3">
            <button
              @click="cancelUse"
              class="flex-1 py-2.5 rounded-lg font-medium bg-bg-tertiary hover:bg-bg-tertiary/80 transition-colors"
            >
              Cancelar
            </button>
            <button
              @click="confirmUse"
              :disabled="using"
              class="flex-1 py-2.5 rounded-lg font-medium transition-colors disabled:opacity-50"
              :class="(confirmAction.type === 'toggle' && confirmAction.data.isActive) || confirmAction.type === 'delete'
                ? 'bg-status-danger text-white hover:bg-status-danger/80'
                : confirmAction.type === 'repair'
                  ? 'bg-status-warning text-white hover:bg-status-warning/80'
                  : 'bg-accent-primary text-white hover:bg-accent-primary/80'"
            >
              {{ using ? 'Procesando...' : (confirmAction.type === 'delete' ? 'Eliminar' : 'Confirmar') }}
            </button>
          </div>
        </div>
      </div>
    </div>
  </Teleport>
</template>
