<script setup lang="ts">
import { ref, watch, computed, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAuthStore } from '@/stores/auth';
import { useMiningStore } from '@/stores/mining';
import { useToastStore } from '@/stores/toast';
import { getPlayerInventory, installCoolingToRig, repairRig, deleteRig, getRigCooling, getPlayerBoosts, installBoostToRig, getRigBoosts, getRigUpgrades, upgradeRig, removeCoolingFromRig, removeBoostFromRig } from '@/utils/api';
import { formatCrypto } from '@/utils/format';
import { playSound } from '@/utils/sounds';

const { t } = useI18n();
const authStore = useAuthStore();
const miningStore = useMiningStore();
const toastStore = useToastStore();

interface RigData {
  id: string;
  is_active: boolean;
  condition: number;
  temperature: number;
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
}

interface CoolingItem {
  inventory_id: string;
  quantity: number;
  id: string;
  name: string;
  cooling_power: number;
  energy_cost: number;
  tier: string;
}

interface InstalledCooling {
  id: string;
  cooling_item_id: string;
  durability: number;
  name: string;
  cooling_power: number;
  energy_cost: number;
}

interface BoostItem {
  boost_id: string;
  quantity: number;
  name: string;
  description: string;
  boost_type: string;
  effect_value: number;
  secondary_value: number;
  duration_minutes: number;
  tier: string;
}

interface InstalledBoost {
  id: string;
  boost_item_id: string;
  remaining_seconds: number;
  stack_count: number;
  name: string;
  boost_type: string;
  effect_value: number;
  secondary_value: number;
  tier: string;
}

interface UpgradeInfo {
  current_level: number;
  can_upgrade: boolean;
  next_cost: number;
  next_bonus: number;
  current_bonus: number;
}

interface RigUpgrades {
  success: boolean;
  max_level: number;
  hashrate: UpgradeInfo;
  efficiency: UpgradeInfo;
  thermal: UpgradeInfo;
}

const props = defineProps<{
  show: boolean;
  rig: RigData | null;
}>();

const emit = defineEmits<{
  close: [];
  updated: [];
}>();

const loading = ref(false);
const processing = ref(false);
const activeTab = ref<'install' | 'repair' | 'upgrade'>('install');

// Inventory cooling items
const coolingItems = ref<CoolingItem[]>([]);
// Installed cooling on this rig
const installedCooling = ref<InstalledCooling[]>([]);

// Inventory boost items
const boostItems = ref<BoostItem[]>([]);
// Installed boosts on this rig
const installedBoosts = ref<InstalledBoost[]>([]);

// Rig upgrades
const rigUpgrades = ref<RigUpgrades | null>(null);

// Confirmation dialog
const showConfirm = ref(false);
const confirmAction = ref<{
  type: 'install' | 'repair' | 'delete' | 'boost' | 'upgrade' | 'destroy_cooling' | 'destroy_boost';
  data: {
    coolingId?: string;
    coolingName?: string;
    coolingPower?: number;
    coolingDurability?: number;
    boostId?: string;
    boostName?: string;
    boostEffect?: string;
    boostDuration?: number;
    boostRemainingSeconds?: number;
    upgradeType?: 'hashrate' | 'efficiency' | 'thermal';
    upgradeCost?: number;
    upgradeBonus?: number;
    upgradeNewLevel?: number;
  };
} | null>(null);

// Processing modal
const showProcessingModal = ref(false);
const processingStatus = ref<'processing' | 'success' | 'error'>('processing');
const processingError = ref('');

// Timer for smooth countdown interpolation between server updates
let boostTimer: number | null = null;

function startBoostTimer() {
  stopBoostTimer();
  boostTimer = window.setInterval(() => {
    // Only decrement if rig is active (mining) - interpolate between server updates
    if (props.rig?.is_active && installedBoosts.value.length > 0) {
      installedBoosts.value = installedBoosts.value
        .map(boost => ({
          ...boost,
          remaining_seconds: Math.max(0, boost.remaining_seconds - 1),
        }))
        .filter(boost => boost.remaining_seconds > 0);
    }
  }, 1000);
}

function stopBoostTimer() {
  if (boostTimer) {
    clearInterval(boostTimer);
    boostTimer = null;
  }
}

onUnmounted(() => {
  stopBoostTimer();
});

// Sync boosts from store when updated via realtime (server is source of truth)
watch(
  () => props.rig?.id ? miningStore.rigBoosts[props.rig.id] : null,
  (storeBoosts) => {
    if (storeBoosts && props.show) {
      // Server update received - sync with authoritative data
      installedBoosts.value = storeBoosts.map(b => ({ ...b }));
    }
  },
  { deep: true }
);

// Load data when modal opens
watch(() => props.show, async (isOpen) => {
  if (isOpen && props.rig) {
    document.body.style.overflow = 'hidden';
    await loadData();
    startBoostTimer();
  } else {
    document.body.style.overflow = '';
    stopBoostTimer();
  }
});

async function loadData() {
  if (!authStore.player || !props.rig) return;
  loading.value = true;

  try {
    const [inventory, cooling, playerBoosts, rigBoosts, upgrades] = await Promise.all([
      getPlayerInventory(authStore.player.id),
      getRigCooling(props.rig.id),
      getPlayerBoosts(authStore.player.id),
      getRigBoosts(props.rig.id),
      getRigUpgrades(props.rig.id),
    ]);

    coolingItems.value = inventory.cooling || [];
    installedCooling.value = cooling || [];
    boostItems.value = playerBoosts?.inventory || [];
    installedBoosts.value = rigBoosts || [];
    rigUpgrades.value = upgrades?.success ? upgrades : null;
  } catch (e) {
    console.error('Error loading rig data:', e);
  } finally {
    loading.value = false;
  }
}

// Computed: max condition (decreases with repairs)
const maxCondition = computed(() => props.rig?.max_condition ?? 100);
const timesRepaired = computed(() => props.rig?.times_repaired ?? 0);
const canRepair = computed(() => {
  if (!props.rig) return false;
  return props.rig.condition < maxCondition.value && maxCondition.value > 10 && !props.rig.is_active;
});
const repairCost = computed(() => props.rig?.rig.repair_cost ?? 0);
const canAffordRepair = computed(() => (authStore.player?.gamecoin_balance ?? 0) >= repairCost.value);

// Total cooling power installed
const totalCoolingPower = computed(() => {
  return installedCooling.value.reduce((sum, c) => sum + (c.cooling_power * c.durability / 100), 0);
});

// Total energy consumed by cooling systems
const totalCoolingEnergy = computed(() => {
  return installedCooling.value.reduce((sum, c) => sum + ((c.energy_cost || 0) * c.durability / 100), 0);
});

function getTierColor(tier: string) {
  switch (tier) {
    case 'elite': return 'text-amber-400';
    case 'advanced': return 'text-fuchsia-400';
    case 'standard': return 'text-sky-400';
    case 'basic': return 'text-emerald-400';
    default: return 'text-text-muted';
  }
}

function getTierBg(tier: string) {
  switch (tier) {
    case 'elite': return 'bg-amber-500/10 border-amber-500/30';
    case 'advanced': return 'bg-fuchsia-500/10 border-fuchsia-500/30';
    case 'standard': return 'bg-sky-500/10 border-sky-500/30';
    case 'basic': return 'bg-emerald-500/10 border-emerald-500/30';
    default: return 'bg-bg-tertiary border-border';
  }
}

function getBoostIcon(type: string): string {
  const icons: Record<string, string> = {
    hashrate: '⚡',
    energy_saver: '🔋',
    bandwidth_optimizer: '📡',
    lucky_charm: '🍀',
    overclock: '🔥',
    coolant_injection: '❄️',
    durability_shield: '🛡️',
  };
  return icons[type] || '🚀';
}

function getBoostEffectText(boost: BoostItem | InstalledBoost): string {
  const sign = boost.boost_type === 'overclock' ? '+' : (boost.boost_type.includes('saver') || boost.boost_type.includes('optimizer') || boost.boost_type.includes('coolant') || boost.boost_type.includes('durability') ? '-' : '+');
  let text = `${sign}${boost.effect_value}%`;
  if (boost.boost_type === 'overclock' && boost.secondary_value) {
    text += ` / +${boost.secondary_value}%`;
  }
  return text;
}

function getBoostTypeDescription(boostType: string): string {
  const key = `market.boosts.types.${boostType}`;
  const translated = t(key);
  return translated !== key ? translated : '';
}

function formatTime(seconds: number): string {
  const mins = Math.floor(seconds / 60);
  const secs = seconds % 60;
  return `${mins}:${secs.toString().padStart(2, '0')}`;
}

// Translation helpers
function getRigName(id: string): string {
  const key = `market.items.rigs.${id}.name`;
  const translated = t(key);
  return translated !== key ? translated : id;
}

function getCoolingName(id: string, fallbackName?: string): string {
  const isUUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id);
  if (isUUID) {
    if (fallbackName) return fallbackName;
    const item = coolingItems.value.find(c => c.id === id);
    return item?.name ?? id;
  }

  const key = `market.items.cooling.${id}.name`;
  const translated = t(key);
  if (translated !== key) return translated;
  if (fallbackName) return fallbackName;
  const item = coolingItems.value.find(c => c.id === id);
  return item?.name ?? id;
}

function getBoostName(id: string, fallbackName?: string): string {
  const key = `market.items.boosts.${id}.name`;
  const translated = t(key);
  if (translated !== key) return translated;
  return fallbackName ?? id;
}

// Request actions
function requestInstallCooling(cooling: CoolingItem) {
  confirmAction.value = {
    type: 'install',
    data: {
      coolingId: cooling.id,
      coolingName: getCoolingName(cooling.id),
      coolingPower: cooling.cooling_power,
    },
  };
  showConfirm.value = true;
}

function requestInstallBoost(boost: BoostItem) {
  confirmAction.value = {
    type: 'boost',
    data: {
      boostId: boost.boost_id,
      boostName: getBoostName(boost.boost_id, boost.name),
      boostEffect: getBoostEffectText(boost),
      boostDuration: boost.duration_minutes,
    },
  };
  showConfirm.value = true;
}

function requestRepair() {
  confirmAction.value = {
    type: 'repair',
    data: {},
  };
  showConfirm.value = true;
}

function requestDelete() {
  confirmAction.value = {
    type: 'delete',
    data: {},
  };
  showConfirm.value = true;
}

function requestUpgrade(upgradeType: 'hashrate' | 'efficiency' | 'thermal') {
  if (!rigUpgrades.value) return;

  const info = rigUpgrades.value[upgradeType];
  if (!info.can_upgrade) return;

  confirmAction.value = {
    type: 'upgrade',
    data: {
      upgradeType,
      upgradeCost: info.next_cost,
      upgradeBonus: info.next_bonus,
      upgradeNewLevel: info.current_level + 1,
    },
  };
  showConfirm.value = true;
}

function requestDestroyCooling(cooling: InstalledCooling) {
  confirmAction.value = {
    type: 'destroy_cooling',
    data: {
      coolingId: cooling.id,
      coolingName: getCoolingName(cooling.cooling_item_id, cooling.name),
      coolingPower: cooling.cooling_power,
      coolingDurability: cooling.durability,
    },
  };
  showConfirm.value = true;
}

function requestDestroyBoost(boost: InstalledBoost) {
  confirmAction.value = {
    type: 'destroy_boost',
    data: {
      boostId: boost.id,
      boostName: getBoostName(boost.boost_item_id, boost.name),
      boostEffect: getBoostEffectText(boost),
      boostRemainingSeconds: boost.remaining_seconds,
    },
  };
  showConfirm.value = true;
}

async function confirmUse() {
  if (!confirmAction.value || !authStore.player || !props.rig) return;

  const { type, data } = confirmAction.value;
  showConfirm.value = false;
  showProcessingModal.value = true;
  processingStatus.value = 'processing';
  processingError.value = '';

  try {
    let result;

    if (type === 'install' && data.coolingId) {
      result = await installCoolingToRig(authStore.player.id, props.rig.id, data.coolingId);
    } else if (type === 'boost' && data.boostId) {
      result = await installBoostToRig(authStore.player.id, props.rig.id, data.boostId);
    } else if (type === 'repair') {
      result = await repairRig(authStore.player.id, props.rig.id);
    } else if (type === 'delete') {
      result = await deleteRig(authStore.player.id, props.rig.id);
    } else if (type === 'upgrade' && data.upgradeType) {
      result = await upgradeRig(authStore.player.id, props.rig.id, data.upgradeType);
    } else if (type === 'destroy_cooling' && data.coolingId) {
      result = await removeCoolingFromRig(authStore.player.id, props.rig.id, data.coolingId);
    } else if (type === 'destroy_boost' && data.boostId) {
      result = await removeBoostFromRig(authStore.player.id, props.rig.id, data.boostId);
    }

    if (result?.success) {
      processingStatus.value = 'success';
      playSound('success');
      await loadData();
      await authStore.fetchPlayer();
      await miningStore.reloadRigs();
      emit('updated');

      // Show toast notification based on action type
      const rigName = props.rig.rig?.name || 'Rig';
      if (type === 'install' && data.coolingName) {
        toastStore.boostInstalled(data.coolingName, rigName);
      } else if (type === 'boost' && data.boostName) {
        toastStore.boostInstalled(data.boostName, rigName);
      } else if (type === 'repair') {
        toastStore.success(`${rigName} reparado`);
      } else if (type === 'upgrade' && data.upgradeType) {
        const upgradeName = data.upgradeType === 'hashrate' ? 'Hashrate' :
          data.upgradeType === 'efficiency' ? 'Eficiencia' : 'Térmica';
        toastStore.success(`${rigName}: ${upgradeName} mejorado a Lv${data.upgradeNewLevel}`);
      } else if (type === 'destroy_cooling' && data.coolingName) {
        toastStore.success(`${data.coolingName} destruido`);
      } else if (type === 'destroy_boost' && data.boostName) {
        toastStore.success(`${data.boostName} destruido`);
      }

      // Close modal after delete
      if (type === 'delete') {
        setTimeout(() => {
          closeProcessingModal();
          emit('close');
        }, 1500);
      }
    } else {
      processingStatus.value = 'error';
      processingError.value = result?.error || t('common.error');
      playSound('error');
    }
  } catch (e) {
    console.error('Error:', e);
    processingStatus.value = 'error';
    processingError.value = t('common.error');
    playSound('error');
  }

  confirmAction.value = null;
}

function cancelConfirm() {
  showConfirm.value = false;
  confirmAction.value = null;
}

function closeProcessingModal() {
  showProcessingModal.value = false;
  processingStatus.value = 'processing';
  processingError.value = '';
}
</script>

<template>
  <Teleport to="body">
    <div
      v-if="show && rig"
      class="fixed inset-0 z-50 flex items-center justify-center p-4"
    >
      <!-- Overlay -->
      <div
        class="absolute inset-0 bg-black/70 backdrop-blur-sm"
        @click="emit('close')"
      ></div>

      <!-- Modal -->
      <div class="relative w-full max-w-lg h-[600px] flex flex-col bg-bg-secondary border border-border rounded-xl overflow-hidden">
        <!-- Header -->
        <div class="flex items-center justify-between p-4 border-b border-border">
          <div>
            <h2 class="text-lg font-semibold flex items-center gap-2">
              <span>⚙️</span>
              <span>{{ t('rigManage.title') }}</span>
            </h2>
            <p class="text-sm text-text-muted">{{ getRigName(rig.rig.id) }}</p>
          </div>
          <button
            @click="emit('close')"
            class="p-2 hover:bg-bg-tertiary rounded-lg transition-colors text-text-muted hover:text-white"
          >
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        <!-- Rig Status Summary -->
        <div class="p-4 border-b border-border bg-bg-primary/50">
          <div class="grid grid-cols-4 gap-3 text-center text-sm">
            <div>
              <div class="text-text-muted text-xs mb-1">{{ t('rigManage.condition') }}</div>
              <div class="font-mono font-bold" :class="rig.condition < 30 ? 'text-status-danger' : rig.condition < 60 ? 'text-status-warning' : 'text-white'">
                {{ rig.condition }}%
              </div>
            </div>
            <div>
              <div class="text-text-muted text-xs mb-1">{{ t('rigManage.temperature') }}</div>
              <div class="font-mono font-bold" :class="rig.temperature > 80 ? 'text-status-danger' : rig.temperature > 60 ? 'text-status-warning' : 'text-white'">
                {{ rig.temperature.toFixed(0) }}°C
              </div>
            </div>
            <div>
              <div class="text-text-muted text-xs mb-1">{{ t('rigManage.cooling') }}</div>
              <div class="font-mono font-bold text-cyan-400">
                ❄️ -{{ totalCoolingPower.toFixed(0) }}°
              </div>
              <div v-if="totalCoolingEnergy > 0" class="font-mono text-xs text-status-warning">
                ⚡ +{{ totalCoolingEnergy.toFixed(1) }}/t
              </div>
            </div>
            <div>
              <div class="text-text-muted text-xs mb-1">{{ t('rigManage.maxCond') }}</div>
              <div class="font-mono font-bold" :class="maxCondition <= 50 ? 'text-status-warning' : 'text-white'">
                {{ maxCondition }}%
              </div>
            </div>
          </div>
        </div>

        <!-- Tabs -->
        <div class="flex gap-1 p-2 border-b border-border bg-bg-primary">
          <button
            @click="activeTab = 'install'"
            class="flex-1 px-3 py-2 rounded-lg text-sm font-medium transition-colors flex items-center justify-center gap-1.5"
            :class="activeTab === 'install'
              ? 'bg-accent-primary/20 text-accent-primary'
              : 'text-text-muted hover:text-white hover:bg-bg-tertiary'"
          >
            <span>📦</span>
            <span>{{ t('rigManage.installTab', 'Install') }}</span>
            <span v-if="installedCooling.length + installedBoosts.length > 0" class="px-1.5 py-0.5 rounded-full text-xs bg-purple-500/30 text-purple-400">
              {{ installedCooling.length + installedBoosts.length }}
            </span>
          </button>
          <button
            @click="activeTab = 'repair'"
            class="flex-1 px-3 py-2 rounded-lg text-sm font-medium transition-colors flex items-center justify-center gap-1.5"
            :class="activeTab === 'repair'
              ? 'bg-status-warning/20 text-status-warning'
              : 'text-text-muted hover:text-white hover:bg-bg-tertiary'"
          >
            <span>🔧</span>
            <span>{{ t('rigManage.repairTab') }}</span>
          </button>
          <button
            @click="activeTab = 'upgrade'"
            class="flex-1 px-3 py-2 rounded-lg text-sm font-medium transition-colors flex items-center justify-center gap-1.5"
            :class="activeTab === 'upgrade'
              ? 'bg-amber-500/20 text-amber-400'
              : 'text-text-muted hover:text-white hover:bg-bg-tertiary'"
          >
            <span>⬆️</span>
            <span>{{ t('rigManage.upgradeTab', 'Mejorar') }}</span>
          </button>
        </div>

        <!-- Content -->
        <div class="flex-1 overflow-y-auto p-4">
          <!-- Loading -->
          <div v-if="loading" class="text-center py-12">
            <div class="w-8 h-8 mx-auto mb-4 border-2 border-accent-primary border-t-transparent rounded-full animate-spin"></div>
            <p class="text-text-muted text-sm">{{ t('common.loading') }}</p>
          </div>

          <template v-else>
            <!-- Install Tab (Cooling + Boosts) -->
            <div v-show="activeTab === 'install'" class="space-y-4">
              <!-- Warning if rig is active -->
              <div v-if="rig.is_active" class="p-3 rounded-lg bg-status-warning/10 border border-status-warning/30 text-status-warning text-sm">
                {{ t('rigManage.stopToInstall') }}
              </div>

              <!-- Installed Items Section -->
              <div v-if="installedCooling.length > 0 || installedBoosts.length > 0" class="space-y-3">
                <h4 class="text-sm font-medium text-text-muted">{{ t('rigManage.installedItems', 'Instalados') }}</h4>

                <!-- Installed Cooling -->
                <div v-if="installedCooling.length > 0" class="space-y-2">
                  <div
                    v-for="cooling in installedCooling"
                    :key="cooling.id"
                    class="flex items-center justify-between w-full px-3 py-2 bg-cyan-500/10 border border-cyan-500/30 rounded-lg"
                  >
                    <div class="flex items-center gap-2">
                      <span class="text-lg">❄️</span>
                      <div>
                        <div class="font-medium text-cyan-400 text-sm">{{ getCoolingName(cooling.cooling_item_id, cooling.name) }}</div>
                        <div class="text-xs text-text-muted">❄️ -{{ cooling.cooling_power }}° • ⚡ +{{ (cooling.energy_cost || 0).toFixed(1) }}/t</div>
                      </div>
                    </div>
                    <div class="flex items-center gap-2">
                      <div class="text-right">
                        <div class="font-mono text-sm text-cyan-400">{{ cooling.durability.toFixed(0) }}%</div>
                        <div class="text-xs text-text-muted">durabilidad</div>
                      </div>
                      <button
                        @click="requestDestroyCooling(cooling)"
                        :disabled="rig.is_active || processing"
                        class="p-1.5 rounded-lg text-status-danger/70 hover:text-status-danger hover:bg-status-danger/10 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
                        :title="t('rigManage.destroyItem', 'Destruir')"
                      >
                        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                        </svg>
                      </button>
                    </div>
                  </div>
                </div>

                <!-- Installed Boosts -->
                <div v-if="installedBoosts.length > 0" class="space-y-2">
                  <div
                    v-for="boost in installedBoosts"
                    :key="boost.id"
                    class="flex items-center justify-between w-full px-3 py-2 bg-purple-500/10 border border-purple-500/30 rounded-lg"
                  >
                    <div class="flex items-center gap-2">
                      <span class="text-lg">{{ getBoostIcon(boost.boost_type) }}</span>
                      <div>
                        <div class="font-medium text-purple-400 text-sm">{{ getBoostName(boost.boost_item_id, boost.name) }}</div>
                        <div class="text-xs text-text-muted/70">{{ getBoostTypeDescription(boost.boost_type) }}</div>
                        <div class="text-xs text-text-muted">{{ getBoostEffectText(boost) }}</div>
                      </div>
                    </div>
                    <div class="flex items-center gap-2">
                      <div class="text-right">
                        <div class="font-mono text-sm text-purple-400">{{ formatTime(boost.remaining_seconds) }}</div>
                        <div v-if="boost.stack_count > 1" class="text-xs text-text-muted">x{{ boost.stack_count }}</div>
                      </div>
                      <button
                        @click="requestDestroyBoost(boost)"
                        :disabled="rig.is_active || processing"
                        class="p-1.5 rounded-lg text-status-danger/70 hover:text-status-danger hover:bg-status-danger/10 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
                        :title="t('rigManage.destroyItem', 'Destruir')"
                      >
                        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                        </svg>
                      </button>
                    </div>
                  </div>
                </div>
              </div>

              <!-- Divider -->
              <div v-if="(installedCooling.length > 0 || installedBoosts.length > 0) && (coolingItems.length > 0 || boostItems.length > 0)" class="border-t border-border"></div>

              <!-- Available Items Section -->
              <div v-if="coolingItems.length === 0 && boostItems.length === 0" class="text-center py-8">
                <div class="text-4xl mb-3 opacity-50">📦</div>
                <p class="text-text-muted text-sm">{{ t('rigManage.noItemsInInventory', 'No tienes items para instalar') }}</p>
                <p class="text-text-muted text-xs mt-1">{{ t('rigManage.buyInMarket', 'Compra en el Market') }}</p>
              </div>

              <div v-else class="space-y-4">
                <!-- Available Cooling -->
                <div v-if="coolingItems.length > 0" class="space-y-2">
                  <h4 class="text-sm font-medium text-text-muted flex items-center gap-2">
                    <span>❄️</span> {{ t('rigManage.availableCooling') }}
                  </h4>
                  <div
                    v-for="item in coolingItems"
                    :key="item.id"
                    class="flex items-center justify-between w-full p-3 rounded-lg border"
                    :class="getTierBg(item.tier)"
                  >
                    <div class="flex items-center gap-3">
                      <span class="text-2xl">❄️</span>
                      <div>
                        <div class="font-medium" :class="getTierColor(item.tier)">{{ getCoolingName(item.id) }}</div>
                        <div class="text-xs text-text-muted">
                          ❄️ -{{ item.cooling_power }}° • ⚡ +{{ item.energy_cost }}/t • x{{ item.quantity }}
                        </div>
                      </div>
                    </div>
                    <button
                      @click="requestInstallCooling(item)"
                      :disabled="rig.is_active || processing"
                      class="px-3 py-1.5 rounded-lg text-sm font-medium transition-colors disabled:opacity-50 bg-cyan-500 text-white hover:bg-cyan-400 shrink-0"
                    >
                      {{ t('rigManage.install') }}
                    </button>
                  </div>
                </div>

                <!-- Available Boosts -->
                <div v-if="boostItems.length > 0" class="space-y-2">
                  <h4 class="text-sm font-medium text-text-muted flex items-center gap-2">
                    <span>🚀</span> {{ t('rigManage.availableBoosts', 'Boosts Disponibles') }}
                  </h4>
                  <div
                    v-for="boost in boostItems"
                    :key="boost.boost_id"
                    class="flex items-center justify-between w-full p-3 rounded-lg border"
                    :class="getTierBg(boost.tier)"
                  >
                    <div class="flex items-center gap-3">
                      <span class="text-2xl">{{ getBoostIcon(boost.boost_type) }}</span>
                      <div>
                        <div class="font-medium" :class="getTierColor(boost.tier)">{{ getBoostName(boost.boost_id, boost.name) }}</div>
                        <div class="text-xs text-text-muted/70">{{ getBoostTypeDescription(boost.boost_type) }}</div>
                        <div class="text-xs text-text-muted">
                          {{ getBoostEffectText(boost) }} • {{ boost.duration_minutes }}min • x{{ boost.quantity }}
                        </div>
                      </div>
                    </div>
                    <button
                      @click="requestInstallBoost(boost)"
                      :disabled="rig.is_active || processing"
                      class="px-3 py-1.5 rounded-lg text-sm font-medium transition-colors disabled:opacity-50 bg-purple-500 text-white hover:bg-purple-400 shrink-0"
                    >
                      {{ t('rigManage.install') }}
                    </button>
                  </div>
                </div>
              </div>
            </div>

            <!-- Repair Tab -->
            <div v-show="activeTab === 'repair'" class="space-y-4">
              <!-- Repair Section -->
              <div class="p-4 rounded-lg border border-border bg-bg-primary/50">
                <h4 class="font-medium mb-3 flex items-center gap-2">
                  <span>🔧</span> {{ t('rigManage.repairRig') }}
                </h4>

                <div class="space-y-2 text-sm mb-4">
                  <div class="flex justify-between">
                    <span class="text-text-muted">{{ t('rigManage.currentCondition') }}</span>
                    <span class="font-mono" :class="rig.condition < 30 ? 'text-status-danger' : ''">{{ rig.condition }}%</span>
                  </div>
                  <div class="flex justify-between">
                    <span class="text-text-muted">{{ t('rigManage.repairTo') }}</span>
                    <span class="font-mono text-status-success">{{ Math.max(0, maxCondition - 5) }}%</span>
                  </div>
                  <div class="flex justify-between">
                    <span class="text-text-muted">{{ t('rigManage.cost') }}</span>
                    <span class="font-mono text-status-warning">{{ repairCost }} GC</span>
                  </div>
                  <div class="flex justify-between">
                    <span class="text-text-muted">{{ t('rigManage.timesRepaired') }}</span>
                    <span class="font-mono">{{ timesRepaired }}</span>
                  </div>
                </div>

                <p v-if="maxCondition <= 50" class="text-xs text-status-warning mb-3">
                  {{ t('rigManage.degradationWarning') }}
                </p>

                <button
                  v-if="canRepair"
                  @click="requestRepair"
                  :disabled="!canAffordRepair || processing"
                  class="w-full py-2 rounded-lg text-sm font-medium transition-colors disabled:opacity-50 bg-status-warning text-white hover:bg-status-warning/80"
                >
                  {{ !canAffordRepair ? t('rigManage.insufficientFunds') : t('rigManage.repair') }}
                </button>
                <p v-else-if="rig.is_active" class="text-sm text-text-muted text-center">
                  {{ t('rigManage.stopToRepair') }}
                </p>
                <p v-else-if="rig.condition >= maxCondition" class="text-sm text-status-success text-center">
                  {{ t('rigManage.atMaxCondition') }}
                </p>
                <p v-else-if="maxCondition <= 10" class="text-sm text-status-danger text-center">
                  {{ t('rigManage.tooDegrade') }}
                </p>
              </div>

              <!-- Delete Section -->
              <div class="p-4 rounded-lg border border-status-danger/30 bg-status-danger/5">
                <h4 class="font-medium mb-2 flex items-center gap-2 text-status-danger">
                  <span>🗑️</span> {{ t('rigManage.deleteRig') }}
                </h4>
                <p class="text-xs text-text-muted mb-3">{{ t('rigManage.deleteWarning') }}</p>
                <button
                  @click="requestDelete"
                  :disabled="rig.is_active || processing"
                  class="w-full py-2 rounded-lg text-sm font-medium transition-colors disabled:opacity-50 bg-status-danger/20 text-status-danger hover:bg-status-danger/30"
                >
                  {{ rig.is_active ? t('rigManage.stopToDelete') : t('rigManage.delete') }}
                </button>
              </div>
            </div>

            <!-- Upgrade Tab -->
            <div v-show="activeTab === 'upgrade'" class="space-y-4">
              <!-- Warning if rig is active -->
              <div v-if="rig.is_active" class="p-3 rounded-lg bg-status-warning/10 border border-status-warning/30 text-status-warning text-sm">
                {{ t('rigManage.stopToUpgrade', 'Detén el rig para mejorarlo') }}
              </div>

              <!-- No upgrades available -->
              <div v-if="!rigUpgrades" class="text-center py-8">
                <div class="text-4xl mb-3 opacity-50">⬆️</div>
                <p class="text-text-muted text-sm">{{ t('rigManage.upgradesNotAvailable', 'Mejoras no disponibles') }}</p>
              </div>

              <!-- Upgrades available (shown even when rig is active, but buttons disabled) -->
              <template v-if="rigUpgrades">
                <div class="text-center mb-4">
                  <p class="text-text-muted text-sm">{{ t('rigManage.upgradeDescription', 'Mejora tu rig con crypto para aumentar su rendimiento') }}</p>
                  <p class="text-xs text-amber-400 mt-1">Max nivel: {{ rigUpgrades.max_level }}</p>
                </div>

                <!-- Hashrate Upgrade -->
                <div class="p-4 rounded-lg border border-amber-500/30 bg-amber-500/5">
                  <div class="flex items-center justify-between mb-3">
                    <div class="flex items-center gap-2">
                      <span class="text-2xl">⚡</span>
                      <div>
                        <h4 class="font-medium text-amber-400">{{ t('rigManage.upgradeHashrate', 'Hashrate') }}</h4>
                        <p class="text-xs text-text-muted">{{ t('rigManage.upgradeHashrateDesc', 'Aumenta la velocidad de minado') }}</p>
                      </div>
                    </div>
                    <div class="text-right">
                      <div class="font-mono text-amber-400">Lv {{ rigUpgrades.hashrate.current_level }}</div>
                      <div v-if="rigUpgrades.hashrate.current_bonus > 0" class="text-xs text-status-success">+{{ rigUpgrades.hashrate.current_bonus }}%</div>
                    </div>
                  </div>
                  <div v-if="rigUpgrades.hashrate.can_upgrade" class="flex items-center justify-between">
                    <div class="text-sm text-text-muted">
                      → Lv {{ rigUpgrades.hashrate.current_level + 1 }}: <span class="text-status-success">+{{ rigUpgrades.hashrate.next_bonus }}%</span>
                    </div>
                    <button
                      @click="requestUpgrade('hashrate')"
                      :disabled="rig.is_active || processing || (authStore.player?.crypto_balance ?? 0) < rigUpgrades.hashrate.next_cost"
                      class="px-3 py-1.5 rounded-lg text-sm font-medium transition-colors disabled:opacity-50 bg-amber-500 text-black hover:bg-amber-400 flex items-center gap-1"
                    >
                      <span>💎</span> {{ formatCrypto(rigUpgrades.hashrate.next_cost) }}
                    </button>
                  </div>
                  <div v-else class="text-center text-xs text-text-muted">{{ t('rigManage.maxLevelReached', 'Nivel máximo alcanzado') }}</div>
                </div>

                <!-- Efficiency Upgrade -->
                <div class="p-4 rounded-lg border border-emerald-500/30 bg-emerald-500/5">
                  <div class="flex items-center justify-between mb-3">
                    <div class="flex items-center gap-2">
                      <span class="text-2xl">🔋</span>
                      <div>
                        <h4 class="font-medium text-emerald-400">{{ t('rigManage.upgradeEfficiency', 'Eficiencia') }}</h4>
                        <p class="text-xs text-text-muted">{{ t('rigManage.upgradeEfficiencyDesc', 'Reduce el consumo de energía') }}</p>
                      </div>
                    </div>
                    <div class="text-right">
                      <div class="font-mono text-emerald-400">Lv {{ rigUpgrades.efficiency.current_level }}</div>
                      <div v-if="rigUpgrades.efficiency.current_bonus > 0" class="text-xs text-status-success">-{{ rigUpgrades.efficiency.current_bonus }}%</div>
                    </div>
                  </div>
                  <div v-if="rigUpgrades.efficiency.can_upgrade" class="flex items-center justify-between">
                    <div class="text-sm text-text-muted">
                      → Lv {{ rigUpgrades.efficiency.current_level + 1 }}: <span class="text-status-success">-{{ rigUpgrades.efficiency.next_bonus }}%</span>
                    </div>
                    <button
                      @click="requestUpgrade('efficiency')"
                      :disabled="rig.is_active || processing || (authStore.player?.crypto_balance ?? 0) < rigUpgrades.efficiency.next_cost"
                      class="px-3 py-1.5 rounded-lg text-sm font-medium transition-colors disabled:opacity-50 bg-emerald-500 text-black hover:bg-emerald-400 flex items-center gap-1"
                    >
                      <span>💎</span> {{ formatCrypto(rigUpgrades.efficiency.next_cost) }}
                    </button>
                  </div>
                  <div v-else class="text-center text-xs text-text-muted">{{ t('rigManage.maxLevelReached', 'Nivel máximo alcanzado') }}</div>
                </div>

                <!-- Thermal Upgrade -->
                <div class="p-4 rounded-lg border border-cyan-500/30 bg-cyan-500/5">
                  <div class="flex items-center justify-between mb-3">
                    <div class="flex items-center gap-2">
                      <span class="text-2xl">❄️</span>
                      <div>
                        <h4 class="font-medium text-cyan-400">{{ t('rigManage.upgradeThermal', 'Térmica') }}</h4>
                        <p class="text-xs text-text-muted">{{ t('rigManage.upgradeThermalDesc', 'Reduce la temperatura base') }}</p>
                      </div>
                    </div>
                    <div class="text-right">
                      <div class="font-mono text-cyan-400">Lv {{ rigUpgrades.thermal.current_level }}</div>
                      <div v-if="rigUpgrades.thermal.current_bonus > 0" class="text-xs text-status-success">-{{ rigUpgrades.thermal.current_bonus }}°C</div>
                    </div>
                  </div>
                  <div v-if="rigUpgrades.thermal.can_upgrade" class="flex items-center justify-between">
                    <div class="text-sm text-text-muted">
                      → Lv {{ rigUpgrades.thermal.current_level + 1 }}: <span class="text-status-success">-{{ rigUpgrades.thermal.next_bonus }}°C</span>
                    </div>
                    <button
                      @click="requestUpgrade('thermal')"
                      :disabled="rig.is_active || processing || (authStore.player?.crypto_balance ?? 0) < rigUpgrades.thermal.next_cost"
                      class="px-3 py-1.5 rounded-lg text-sm font-medium transition-colors disabled:opacity-50 bg-cyan-500 text-black hover:bg-cyan-400 flex items-center gap-1"
                    >
                      <span>💎</span> {{ formatCrypto(rigUpgrades.thermal.next_cost) }}
                    </button>
                  </div>
                  <div v-else class="text-center text-xs text-text-muted">{{ t('rigManage.maxLevelReached', 'Nivel máximo alcanzado') }}</div>
                </div>

                <!-- Current crypto balance -->
                <div class="text-center text-sm text-text-muted mt-4">
                  {{ t('rigManage.yourCrypto', 'Tu crypto') }}: <span class="text-amber-400 font-mono">💎 {{ formatCrypto(authStore.player?.crypto_balance ?? 0) }}</span>
                </div>
              </template>
            </div>
          </template>
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
              {{ confirmAction.type === 'install' ? '❄️' : confirmAction.type === 'boost' ? '🚀' : confirmAction.type === 'repair' ? '🔧' : confirmAction.type === 'upgrade' ? '⬆️' : confirmAction.type === 'destroy_cooling' ? '❄️' : confirmAction.type === 'destroy_boost' ? '🚀' : '🗑️' }}
            </div>
            <h3 class="text-lg font-bold mb-1">
              {{ confirmAction.type === 'install' ? t('rigManage.confirmInstall') : confirmAction.type === 'boost' ? t('rigManage.confirmApplyBoost', 'Aplicar Boost') : confirmAction.type === 'repair' ? t('rigManage.confirmRepair') : confirmAction.type === 'upgrade' ? t('rigManage.confirmUpgrade', 'Confirmar Mejora') : (confirmAction.type === 'destroy_cooling' || confirmAction.type === 'destroy_boost') ? t('rigManage.confirmDestroy', 'Destruir Item') : t('rigManage.confirmDelete') }}
            </h3>
            <p class="text-text-muted text-sm">{{ t('inventory.confirm.areYouSure') }}</p>
          </div>

          <div class="bg-bg-primary rounded-lg p-4 mb-4">
            <template v-if="confirmAction.type === 'install'">
              <div class="flex items-center justify-between mb-2">
                <span class="text-text-muted text-sm">{{ t('rigManage.cooling') }}</span>
                <span class="font-medium text-cyan-400">{{ confirmAction.data.coolingName }}</span>
              </div>
              <div class="flex items-center justify-between">
                <span class="text-text-muted text-sm">{{ t('rigManage.power') }}</span>
                <span class="font-bold text-cyan-400">-{{ confirmAction.data.coolingPower }}°</span>
              </div>
            </template>
            <template v-else-if="confirmAction.type === 'boost'">
              <div class="flex items-center justify-between mb-2">
                <span class="text-text-muted text-sm">Boost</span>
                <span class="font-medium text-purple-400">{{ confirmAction.data.boostName }}</span>
              </div>
              <div class="flex items-center justify-between mb-2">
                <span class="text-text-muted text-sm">{{ t('rigManage.effect', 'Efecto') }}</span>
                <span class="font-bold text-purple-400">{{ confirmAction.data.boostEffect }}</span>
              </div>
              <div class="flex items-center justify-between">
                <span class="text-text-muted text-sm">{{ t('rigManage.duration', 'Duración') }}</span>
                <span class="font-bold text-purple-400">{{ confirmAction.data.boostDuration }} min</span>
              </div>
            </template>
            <template v-else-if="confirmAction.type === 'repair'">
              <div class="flex items-center justify-between mb-2">
                <span class="text-text-muted text-sm">{{ t('rigManage.cost') }}</span>
                <span class="font-bold text-status-warning">{{ repairCost }} GC</span>
              </div>
              <div class="flex items-center justify-between">
                <span class="text-text-muted text-sm">{{ t('rigManage.repairTo') }}</span>
                <span class="font-bold text-status-success">{{ Math.max(0, maxCondition - 5) }}%</span>
              </div>
            </template>
            <template v-else-if="confirmAction.type === 'upgrade'">
              <div class="flex items-center justify-between mb-2">
                <span class="text-text-muted text-sm">{{ t('rigManage.upgradeType', 'Mejora') }}</span>
                <span class="font-medium text-amber-400">
                  {{ confirmAction.data.upgradeType === 'hashrate' ? 'Hashrate' : confirmAction.data.upgradeType === 'efficiency' ? 'Eficiencia' : 'Térmica' }}
                </span>
              </div>
              <div class="flex items-center justify-between mb-2">
                <span class="text-text-muted text-sm">{{ t('rigManage.newLevel', 'Nuevo nivel') }}</span>
                <span class="font-bold text-amber-400">Lv {{ confirmAction.data.upgradeNewLevel }}</span>
              </div>
              <div class="flex items-center justify-between">
                <span class="text-text-muted text-sm">{{ t('rigManage.cost') }}</span>
                <span class="font-bold text-amber-400">💎 {{ formatCrypto(confirmAction.data.upgradeCost ?? 0) }}</span>
              </div>
            </template>
            <template v-else-if="confirmAction.type === 'destroy_cooling'">
              <p class="text-sm text-status-danger mb-3">{{ t('rigManage.destroyWarning', 'Este item será destruido permanentemente y no podrá recuperarse.') }}</p>
              <div class="flex items-center justify-between mb-2">
                <span class="text-text-muted text-sm">{{ t('rigManage.cooling') }}</span>
                <span class="font-medium text-cyan-400">{{ confirmAction.data.coolingName }}</span>
              </div>
              <div class="flex items-center justify-between mb-2">
                <span class="text-text-muted text-sm">{{ t('rigManage.power') }}</span>
                <span class="font-bold text-cyan-400">-{{ confirmAction.data.coolingPower }}°</span>
              </div>
              <div class="flex items-center justify-between">
                <span class="text-text-muted text-sm">{{ t('rigManage.durability', 'Durabilidad') }}</span>
                <span class="font-bold text-cyan-400">{{ confirmAction.data.coolingDurability?.toFixed(0) }}%</span>
              </div>
            </template>
            <template v-else-if="confirmAction.type === 'destroy_boost'">
              <p class="text-sm text-status-danger mb-3">{{ t('rigManage.destroyWarning', 'Este item será destruido permanentemente y no podrá recuperarse.') }}</p>
              <div class="flex items-center justify-between mb-2">
                <span class="text-text-muted text-sm">Boost</span>
                <span class="font-medium text-purple-400">{{ confirmAction.data.boostName }}</span>
              </div>
              <div class="flex items-center justify-between mb-2">
                <span class="text-text-muted text-sm">{{ t('rigManage.effect', 'Efecto') }}</span>
                <span class="font-bold text-purple-400">{{ confirmAction.data.boostEffect }}</span>
              </div>
              <div class="flex items-center justify-between">
                <span class="text-text-muted text-sm">{{ t('rigManage.remaining', 'Restante') }}</span>
                <span class="font-bold text-purple-400">{{ formatTime(confirmAction.data.boostRemainingSeconds ?? 0) }}</span>
              </div>
            </template>
            <template v-else-if="confirmAction.type === 'delete'">
              <p class="text-sm text-status-danger">{{ t('rigManage.deleteConfirmText') }}</p>
            </template>
          </div>

          <div class="flex gap-3">
            <button
              @click="cancelConfirm"
              class="flex-1 py-2.5 rounded-lg font-medium bg-bg-tertiary hover:bg-bg-tertiary/80 transition-colors"
            >
              {{ t('common.cancel') }}
            </button>
            <button
              @click="confirmUse"
              :disabled="processing"
              class="flex-1 py-2.5 rounded-lg font-medium transition-colors disabled:opacity-50"
              :class="confirmAction.type === 'delete' || confirmAction.type === 'destroy_cooling' || confirmAction.type === 'destroy_boost'
                ? 'bg-status-danger text-white hover:bg-status-danger/80'
                : confirmAction.type === 'repair'
                  ? 'bg-status-warning text-white hover:bg-status-warning/80'
                  : confirmAction.type === 'boost'
                    ? 'bg-purple-500 text-white hover:bg-purple-400'
                    : confirmAction.type === 'upgrade'
                      ? 'bg-amber-500 text-black hover:bg-amber-400'
                      : 'bg-cyan-500 text-white hover:bg-cyan-400'"
            >
              {{ (confirmAction.type === 'destroy_cooling' || confirmAction.type === 'destroy_boost') ? t('rigManage.destroy', 'Destruir') : t('common.confirm') }}
            </button>
          </div>
        </div>
      </div>

      <!-- Processing Modal -->
      <div
        v-if="showProcessingModal"
        class="absolute inset-0 flex items-center justify-center bg-black/70 z-20"
      >
        <div class="bg-bg-secondary rounded-xl p-6 max-w-sm w-full mx-4 border border-border animate-fade-in">
          <div v-if="processingStatus === 'processing'" class="text-center">
            <div class="w-12 h-12 mx-auto mb-4 border-2 border-accent-primary border-t-transparent rounded-full animate-spin"></div>
            <p class="text-text-muted">{{ t('common.processing') }}</p>
          </div>

          <div v-else-if="processingStatus === 'success'" class="text-center">
            <div class="w-12 h-12 mx-auto mb-4 bg-status-success/20 rounded-full flex items-center justify-center">
              <svg class="w-6 h-6 text-status-success" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
              </svg>
            </div>
            <p class="text-status-success font-medium mb-4">{{ t('common.success') }}</p>
            <button
              @click="closeProcessingModal"
              class="w-full py-2 rounded-lg font-medium bg-status-success/20 text-status-success hover:bg-status-success/30 transition-colors"
            >
              {{ t('common.close') }}
            </button>
          </div>

          <div v-else-if="processingStatus === 'error'" class="text-center">
            <div class="w-12 h-12 mx-auto mb-4 bg-status-danger/20 rounded-full flex items-center justify-center">
              <svg class="w-6 h-6 text-status-danger" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </div>
            <p class="text-status-danger font-medium mb-2">{{ t('common.error') }}</p>
            <p class="text-text-muted text-sm mb-4">{{ processingError }}</p>
            <button
              @click="closeProcessingModal"
              class="w-full py-2 rounded-lg font-medium bg-bg-tertiary hover:bg-bg-tertiary/80 transition-colors"
            >
              {{ t('common.close') }}
            </button>
          </div>
        </div>
      </div>
    </div>
  </Teleport>
</template>
