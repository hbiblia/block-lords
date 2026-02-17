<script setup lang="ts">
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAuthStore } from '@/stores/auth';
import { useInventoryStore, type CoolingItem, type ModdedCoolingItem } from '@/stores/inventory';
import { redeemPrepaidCard } from '@/utils/api';
import { playSound } from '@/utils/sounds';
import CoolingWorkshopModal from './CoolingWorkshopModal.vue';

const { t } = useI18n();

const authStore = useAuthStore();
const inventoryStore = useInventoryStore();

const props = defineProps<{
  show: boolean;
}>();

const emit = defineEmits<{
  close: [];
  used: [];
}>();

const using = ref(false);

// Workshop modal state
const showWorkshop = ref(false);
const workshopItem = ref<CoolingItem | ModdedCoolingItem | null>(null);

function openWorkshop(item: CoolingItem | ModdedCoolingItem) {
  workshopItem.value = item;
  showWorkshop.value = true;
  playSound('click');
}

function closeWorkshop() {
  showWorkshop.value = false;
  workshopItem.value = null;
}

function onModded() {
  // Refresh inventory after modding
  inventoryStore.refresh();
}

// Group cards by card_id (same type + same value)
const groupedCards = computed(() => {
  const groups = new Map<string, { card_id: string; card_type: 'energy' | 'internet' | 'combo'; amount: number; tier: string; codes: { id: string; code: string }[]; }>();
  for (const card of inventoryStore.cardItems) {
    const existing = groups.get(card.card_id);
    if (existing) {
      existing.codes.push({ id: card.id, code: card.code });
    } else {
      groups.set(card.card_id, {
        card_id: card.card_id,
        card_type: card.card_type,
        amount: card.amount,
        tier: card.tier,
        codes: [{ id: card.id, code: card.code }],
      });
    }
  }
  return Array.from(groups.values());
});

// Fetch inventory when modal opens
watch(() => props.show, (isOpen) => {
  if (isOpen) {
    // Fetch inventory (will use cache if available)
    inventoryStore.fetchInventory();
  }
});

function handleClose() {
  playSound('click');
  emit('close');
}

// Confirmation dialog state
const showConfirm = ref(false);
const confirmAction = ref<{
  type: 'redeem' | 'install_rig';
  data: {
    cardCode?: string;
    cardName?: string;
    cardType?: 'energy' | 'internet' | 'combo';
    cardAmount?: number;
    rigId?: string;
    rigName?: string;
  };
} | null>(null);

// 4-digit confirmation code for card redemption
const generatedCode = ref('');
const inputCode = ref('');

function generateConfirmCode(): string {
  return Math.floor(1000 + Math.random() * 9000).toString();
}

// Processing modal state
const showProcessingModal = ref(false);
const processingStatus = ref<'processing' | 'error'>('processing');
const processingError = ref<string>('');

function closeProcessingModal() {
  showProcessingModal.value = false;
  processingStatus.value = 'processing';
  processingError.value = '';
}

function requestRedeemCard(group: { card_id: string; card_type: 'energy' | 'internet' | 'combo'; amount: number; codes: { id: string; code: string }[] }) {
  confirmAction.value = {
    type: 'redeem',
    data: {
      cardCode: group.codes[0].code,
      cardName: getCardName(group.card_id),
      cardType: group.card_type,
      cardAmount: group.amount,
    },
  };
  generatedCode.value = generateConfirmCode();
  inputCode.value = '';
  showConfirm.value = true;
}

function requestInstallRig(rig: { rig_id: string; name: string }) {
  confirmAction.value = {
    type: 'install_rig',
    data: {
      rigId: rig.rig_id,
      rigName: rig.name,
    },
  };
  showConfirm.value = true;
}

async function handleInstallRig(rigId: string) {
  if (!authStore.player || using.value) return;
  using.value = true;
  showProcessingModal.value = true;
  processingStatus.value = 'processing';
  processingError.value = '';

  const result = await inventoryStore.installRig(rigId);

  if (result.success) {
    closeProcessingModal();
    emit('used');
  } else {
    processingStatus.value = 'error';
    processingError.value = result.error || t('inventory.processing.errorInstallRig', 'Error instalando rig');
  }

  using.value = false;
}

async function handleRedeemCard(code: string) {
  if (!authStore.player || using.value) return;
  using.value = true;
  showProcessingModal.value = true;
  processingStatus.value = 'processing';
  processingError.value = '';

  try {
    const result = await redeemPrepaidCard(authStore.player.id, code);
    if (result.success) {
      await inventoryStore.refresh();
      await authStore.fetchPlayer();
      closeProcessingModal();
      playSound('success');
      emit('used');
    } else {
      processingStatus.value = 'error';
      processingError.value = result.error || t('inventory.processing.errorRedeemCard');
      playSound('error');
    }
  } catch (e) {
    console.error('Error redeeming card:', e);
    processingStatus.value = 'error';
    processingError.value = t('inventory.processing.errorRedeemCard');
    playSound('error');
  } finally {
    using.value = false;
  }
}

async function confirmUse() {
  if (!confirmAction.value) return;

  const { type, data } = confirmAction.value;
  showConfirm.value = false;

  if (type === 'redeem' && data.cardCode) {
    await handleRedeemCard(data.cardCode);
  } else if (type === 'install_rig' && data.rigId) {
    await handleInstallRig(data.rigId);
  }

  confirmAction.value = null;
}

function cancelUse() {
  showConfirm.value = false;
  confirmAction.value = null;
  generatedCode.value = '';
  inputCode.value = '';
}

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
    case 'elite': return 'bg-amber-500/10';
    case 'advanced': return 'bg-fuchsia-500/10';
    case 'standard': return 'bg-sky-500/10';
    case 'basic': return 'bg-emerald-500/10';
    default: return 'bg-bg-tertiary';
  }
}

function getTierBorder(tier: string) {
  switch (tier) {
    case 'elite': return 'border-amber-500/40';
    case 'advanced': return 'border-fuchsia-500/40';
    case 'standard': return 'border-sky-500/40';
    case 'basic': return 'border-emerald-500/40';
    default: return 'border-border';
  }
}

// Translation helpers for inventory items - fallback to DB name
function getCoolingName(id: string, fallbackName?: string): string {
  const isUUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id);
  if (isUUID) {
    if (fallbackName) return fallbackName;
    const item = inventoryStore.coolingItems.find(c => c.id === id);
    return item?.name ?? id;
  }

  const key = `market.items.cooling.${id}.name`;
  const translated = t(key);
  if (translated !== key) return translated;
  if (fallbackName) return fallbackName;
  const item = inventoryStore.coolingItems.find(c => c.id === id);
  return item?.name ?? id;
}

function getCardName(id: string): string {
  const key = `market.items.cards.${id}.name`;
  const translated = t(key);
  return translated !== key ? translated : id;
}

function getBoostName(id: string): string {
  const key = `market.items.boosts.${id}.name`;
  const translated = t(key);
  return translated !== key ? translated : id;
}

function getComponentName(id: string, fallback?: string): string {
  const key = `market.items.components.${id}.name`;
  const translated = t(key);
  if (translated !== key) return translated;
  return fallback || id;
}

function getRarityColor(rarity: string): string {
  switch (rarity) {
    case 'epic': return 'text-fuchsia-400';
    case 'rare': return 'text-amber-400';
    case 'uncommon': return 'text-sky-400';
    case 'common': return 'text-emerald-400';
    default: return 'text-text-muted';
  }
}

function getMaterialName(name: string): string {
  const key = `materials.${name}.name`;
  const translated = t(key);
  return translated !== key ? translated : name.replace(/_/g, ' ');
}

function getRigName(id: string, fallbackName?: string): string {
  const key = `market.items.rigs.${id}.name`;
  const translated = t(key);
  if (translated !== key) return translated;
  if (fallbackName) return fallbackName;
  return id;
}

function formatNumber(num: number): string {
  if (num >= 1000000) return (num / 1000000).toFixed(1) + 'M';
  if (num >= 1000) return (num / 1000).toFixed(1) + 'K';
  return num.toString();
}

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

function getBoostTypeDescription(boostType: string): string {
  const key = `market.boosts.types.${boostType}`;
  const translated = t(key);
  return translated !== key ? translated : '';
}

function formatBoostEffect(boost: { boost_type: string; effect_value: number; secondary_value: number }): string {
  const sign = boost.boost_type === 'energy_saver' || boost.boost_type === 'bandwidth_optimizer' ||
               boost.boost_type === 'coolant_injection' || boost.boost_type === 'durability_shield' ? '-' : '+';
  let effect = `${sign}${boost.effect_value}%`;
  if (boost.boost_type === 'overclock' && boost.secondary_value > 0) {
    effect += ` / +${boost.secondary_value}% ⚡`;
  }
  return effect;
}

function formatDuration(minutes: number): string {
  if (minutes >= 60) {
    const hours = minutes / 60;
    return `${hours}h`;
  }
  return `${minutes}m`;
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
        @click="handleClose"
      ></div>

      <!-- Modal -->
      <div class="relative w-full max-w-4xl h-[85vh] flex flex-col bg-bg-secondary border border-border rounded-xl overflow-hidden">
        <!-- Header -->
        <div class="p-2 border-b border-border">
          <div class="flex items-center justify-between">
            <h2 class="text-lg font-semibold flex items-center gap-2">
              <span>🎒</span>
              <span>{{ t('inventory.title') }}</span>
            </h2>
            <button
              @click="handleClose"
              class="p-2 hover:bg-bg-tertiary rounded-lg transition-colors text-text-muted hover:text-white"
            >
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>
          <div v-if="authStore.player" class="flex items-center gap-2 text-xs mt-2">
            <span class="flex items-center gap-1 px-2 py-1 rounded-md bg-amber-500/10 border border-amber-500/20">
              <span>⚡</span>
              <span class="font-mono font-medium text-amber-400">{{ Math.floor(authStore.player.energy) }}/{{ authStore.player.max_energy }}</span>
            </span>
            <span class="flex items-center gap-1 px-2 py-1 rounded-md bg-cyan-500/10 border border-cyan-500/20">
              <span>📡</span>
              <span class="font-mono font-medium text-cyan-400">{{ Math.floor(authStore.player.internet) }}/{{ authStore.player.max_internet }}</span>
            </span>
          </div>
        </div>

        <!-- Content -->
        <div class="flex-1 overflow-y-auto p-4 space-y-6">
          <!-- Loading (only on first load) -->
          <div v-if="inventoryStore.loading && !inventoryStore.loaded" class="text-center py-16">
            <div class="w-8 h-8 mx-auto mb-4 border-2 border-accent-primary border-t-transparent rounded-full animate-spin"></div>
            <p class="text-text-muted text-sm">{{ t('inventory.loading') }}</p>
          </div>

          <template v-else>
            <!-- Empty state -->
            <div v-if="inventoryStore.totalItems === 0" class="text-center py-16">
              <div class="text-5xl mb-4 opacity-50">🎒</div>
              <p class="text-text-muted">{{ t('inventory.empty', 'Tu inventario está vacío') }}</p>
              <p class="text-text-muted/70 text-sm mt-1">{{ t('inventory.emptyHint', 'Compra items en el mercado') }}</p>
            </div>

            <template v-else>
              <!-- Active Boosts Bar -->
              <div v-if="inventoryStore.activeBoosts.length > 0" class="mb-4">
                <h3 class="text-xs sm:text-sm font-medium text-text-muted mb-1.5 sm:mb-2">{{ t('inventory.boosts.active') }}</h3>
                <div class="flex flex-wrap gap-1.5 sm:gap-2">
                  <div
                    v-for="boost in inventoryStore.activeBoosts"
                    :key="boost.id"
                    class="flex items-center gap-1 sm:gap-2 px-2 sm:px-3 py-1 sm:py-1.5 rounded-lg bg-amber-500/20 border border-amber-500/30"
                  >
                    <span class="text-xs sm:text-sm font-medium text-amber-400">{{ getBoostName(boost.boost_id) }}</span>
                    <span class="text-[10px] sm:text-xs text-text-muted">{{ formatTimeRemaining(boost.seconds_remaining) }}</span>
                  </div>
                </div>
              </div>

              <!-- Rigs Section -->
              <div v-if="inventoryStore.rigItems.length > 0">
                <h3 class="text-sm font-medium text-text-muted mb-3 flex items-center gap-2">
                  <span>⛏️</span>
                  {{ t('inventory.tabs.rigs', 'Rigs') }}
                  <span class="px-1.5 py-0.5 rounded-full text-xs bg-accent-primary/30 text-accent-primary">
                    {{ inventoryStore.rigItems.reduce((sum, r) => sum + r.quantity, 0) }}
                  </span>
                </h3>
                <div class="grid grid-cols-2 sm:grid-cols-2 lg:grid-cols-3 gap-2 sm:gap-3">
                  <div
                    v-for="rig in inventoryStore.rigItems"
                    :key="rig.rig_id"
                    class="rounded-lg border p-2.5 sm:p-4 flex flex-col h-full"
                    :class="[getTierBorder(rig.tier), getTierBg(rig.tier)]"
                  >
                    <div class="flex items-start justify-between mb-2 sm:mb-3">
                      <div class="min-w-0 flex-1">
                        <h4 class="font-medium text-xs sm:text-sm truncate" :class="getTierColor(rig.tier)">{{ getRigName(rig.rig_id, rig.name) }}</h4>
                        <p class="text-[10px] sm:text-xs text-text-muted uppercase">{{ rig.tier }}</p>
                      </div>
                      <span class="text-lg sm:text-2xl ml-1">⛏️</span>
                    </div>

                    <div class="flex items-center justify-between mb-1 sm:mb-2">
                      <span class="text-[10px] sm:text-xs text-text-muted">Hashrate</span>
                      <span class="font-mono font-bold text-sm sm:text-lg text-accent-primary">{{ formatNumber(rig.hashrate) }} H/s</span>
                    </div>

                    <div class="flex items-center gap-1 sm:gap-2 text-[10px] sm:text-xs text-text-muted mb-1 sm:mb-2">
                      <span>⚡{{ rig.power_consumption }}/t</span>
                      <span>•</span>
                      <span>📡{{ rig.internet_consumption }}/t</span>
                      <span class="ml-auto font-medium">x{{ rig.quantity }}</span>
                    </div>

                    <div class="mt-auto">
                      <button
                        @click="requestInstallRig(rig)"
                        :disabled="using || inventoryStore.installing"
                        class="w-full py-1.5 sm:py-2 rounded text-xs sm:text-sm font-medium transition-colors disabled:opacity-50 bg-accent-primary text-white hover:bg-accent-primary/80"
                      >
                        {{ inventoryStore.installing ? '...' : t('inventory.rigs.install', 'Instalar') }}
                      </button>
                    </div>
                  </div>
                </div>
              </div>

              <!-- Prepaid Cards Section -->
              <div v-if="groupedCards.length > 0">
                <h3 class="text-sm font-medium text-text-muted mb-3 flex items-center gap-2">
                  <span>💳</span>
                  {{ t('inventory.tabs.cards', 'Tarjetas') }}
                  <span class="px-1.5 py-0.5 rounded-full text-xs bg-amber-500/30 text-amber-400">
                    {{ inventoryStore.cardItems.length }}
                  </span>
                </h3>
                <div class="grid grid-cols-2 sm:grid-cols-2 lg:grid-cols-3 gap-2 sm:gap-3">
                  <div
                    v-for="group in groupedCards"
                    :key="group.card_id"
                    class="rounded-lg border p-2.5 sm:p-4 flex flex-col h-full"
                    :class="group.card_type === 'combo'
                      ? 'bg-gradient-to-br from-amber-500/10 to-cyan-500/10 border-amber-500/20'
                      : group.card_type === 'energy'
                        ? 'bg-amber-500/10 border-amber-500/30'
                        : 'bg-cyan-500/10 border-cyan-500/30'"
                  >
                    <div class="flex items-start justify-between mb-2 sm:mb-3">
                      <div class="min-w-0 flex-1">
                        <h4 class="font-medium text-xs sm:text-sm truncate" :class="group.card_type === 'combo' ? 'text-white' : group.card_type === 'energy' ? 'text-amber-400' : 'text-cyan-400'">{{ getCardName(group.card_id) }}</h4>
                        <p class="text-[10px] sm:text-xs text-text-muted uppercase">{{ group.tier }}</p>
                      </div>
                      <span class="text-lg sm:text-2xl ml-1">{{ group.card_type === 'combo' ? '⚡📡' : group.card_type === 'energy' ? '⚡' : '📡' }}</span>
                    </div>

                    <!-- Combo: show both resources -->
                    <template v-if="group.card_type === 'combo'">
                      <div class="space-y-1 mb-1 sm:mb-2">
                        <div class="flex items-center justify-between">
                          <span class="text-[10px] sm:text-xs text-text-muted">⚡ {{ t('welcome.energy', 'Energía') }}</span>
                          <span class="font-mono font-bold text-xs sm:text-sm text-amber-400">+{{ group.amount }}</span>
                        </div>
                        <div class="flex items-center justify-between">
                          <span class="text-[10px] sm:text-xs text-text-muted">📡 {{ t('welcome.internet', 'Internet') }}</span>
                          <span class="font-mono font-bold text-xs sm:text-sm text-cyan-400">+{{ group.amount }}</span>
                        </div>
                      </div>
                    </template>
                    <!-- Single resource -->
                    <template v-else>
                      <div class="flex items-center justify-between mb-1 sm:mb-2">
                        <span class="text-[10px] sm:text-xs text-text-muted">{{ group.card_type === 'energy' ? t('welcome.energy', 'Energía') : t('welcome.internet', 'Internet') }}</span>
                        <span class="font-mono font-bold text-sm sm:text-lg" :class="group.card_type === 'energy' ? 'text-amber-400' : 'text-cyan-400'">
                          +{{ group.amount }}%
                        </span>
                      </div>
                    </template>

                    <div class="flex items-center justify-between text-[10px] sm:text-xs text-text-muted mb-1 sm:mb-2">
                      <span>{{ group.card_type === 'combo' ? '⚡📡' : group.card_type === 'energy' ? '⚡' : '📡' }} {{ t('inventory.tabs.cards', 'Tarjetas') }}</span>
                      <span class="font-medium">x{{ group.codes.length }}</span>
                    </div>

                    <div class="mt-auto">
                      <button
                        @click="requestRedeemCard(group)"
                        :disabled="using"
                        class="w-full py-1.5 sm:py-2 rounded text-xs sm:text-sm font-medium transition-colors disabled:opacity-50"
                        :class="group.card_type === 'combo'
                          ? 'bg-gradient-to-r from-amber-500 to-cyan-500 text-white hover:from-amber-400 hover:to-cyan-400'
                          : group.card_type === 'energy'
                            ? 'bg-amber-500 text-white hover:bg-amber-400'
                            : 'bg-cyan-500 text-white hover:bg-cyan-400'"
                      >
                        {{ using ? '...' : t('inventory.cards.recharge') }}
                      </button>
                    </div>
                  </div>
                </div>
              </div>

              <!-- Cooling Section -->
              <div v-if="inventoryStore.coolingItems.length > 0 || inventoryStore.moddedCoolingItems.length > 0">
                <h3 class="text-sm font-medium text-text-muted mb-3 flex items-center gap-2">
                  <span>❄️</span>
                  {{ t('inventory.tabs.cooling', 'Enfriamiento') }}
                  <span class="px-1.5 py-0.5 rounded-full text-xs bg-cyan-500/30 text-cyan-400">
                    {{ inventoryStore.coolingItems.length + inventoryStore.moddedCoolingItems.length }}
                  </span>
                </h3>
                <div class="grid grid-cols-2 sm:grid-cols-2 lg:grid-cols-3 gap-2 sm:gap-3">
                  <!-- Unmodded Cooling Items -->
                  <div
                    v-for="item in inventoryStore.coolingItems"
                    :key="item.inventory_id"
                    class="rounded-lg border p-2.5 sm:p-4 flex flex-col h-full"
                    :class="[getTierBorder(item.tier), getTierBg(item.tier)]"
                  >
                    <div class="flex items-start justify-between mb-2 sm:mb-3">
                      <div class="min-w-0 flex-1">
                        <h4 class="font-medium text-xs sm:text-sm truncate" :class="getTierColor(item.tier)">{{ getCoolingName(item.id) }}</h4>
                        <p class="text-[10px] sm:text-xs text-text-muted uppercase">{{ item.tier }} · {{ item.max_mod_slots || 1 }} slots</p>
                      </div>
                      <span class="text-lg sm:text-2xl ml-1">❄️</span>
                    </div>

                    <div class="flex items-center justify-between mb-1 sm:mb-2">
                      <span class="text-[10px] sm:text-xs text-text-muted">{{ t('inventory.cooling.power', 'Potencia') }}</span>
                      <span class="font-mono font-bold text-sm sm:text-lg text-cyan-400">-{{ item.cooling_power }}°</span>
                    </div>

                    <div class="flex items-center justify-between text-[10px] sm:text-xs text-text-muted mb-1 sm:mb-2">
                      <span>⚡ +{{ item.energy_cost }}/t</span>
                      <span class="font-medium">x{{ item.quantity }}</span>
                    </div>

                    <div class="mt-auto flex gap-1.5">
                      <button
                        @click="openWorkshop(item)"
                        class="flex-1 py-1.5 sm:py-2 rounded text-xs sm:text-sm font-medium transition-colors bg-fuchsia-600 hover:bg-fuchsia-500 text-white"
                      >
                        🔧 {{ t('inventory.cooling.modify') }}
                      </button>
                    </div>
                  </div>

                  <!-- Modded Cooling Items -->
                  <div
                    v-for="item in inventoryStore.moddedCoolingItems"
                    :key="item.player_cooling_item_id"
                    class="rounded-lg border p-2.5 sm:p-4 flex flex-col h-full relative"
                    :class="[getTierBorder(item.tier), getTierBg(item.tier)]"
                  >
                    <!-- Modded badge -->
                    <div class="absolute top-1 right-1 px-1.5 py-0.5 rounded-full text-[9px] bg-fuchsia-500/30 text-fuchsia-300 border border-fuchsia-500/40">
                      🧩 {{ item.mod_slots_used }}/{{ item.max_mod_slots }}
                    </div>

                    <div class="flex items-start justify-between mb-2 sm:mb-3">
                      <div class="min-w-0 flex-1">
                        <h4 class="font-medium text-xs sm:text-sm truncate" :class="getTierColor(item.tier)">{{ getCoolingName(item.cooling_item_id, item.name) }}</h4>
                        <p class="text-[10px] sm:text-xs text-fuchsia-400 uppercase">{{ t('inventory.cooling.modded') }}</p>
                      </div>
                      <span class="text-lg sm:text-2xl ml-1">❄️</span>
                    </div>

                    <div class="flex items-center justify-between mb-0.5">
                      <span class="text-[10px] sm:text-xs text-text-muted">{{ t('inventory.cooling.power', 'Potencia') }}</span>
                      <span class="font-mono font-bold text-sm sm:text-lg text-cyan-400">-{{ item.effective_cooling_power.toFixed(1) }}°</span>
                    </div>
                    <div v-if="item.effective_cooling_power !== item.cooling_power" class="text-right text-[9px] text-emerald-400 mb-1">
                      {{ item.effective_cooling_power > item.cooling_power ? '+' : '' }}{{ (((item.effective_cooling_power - item.cooling_power) / item.cooling_power) * 100).toFixed(1) }}%
                    </div>

                    <div class="flex items-center justify-between text-[10px] sm:text-xs text-text-muted mb-1 sm:mb-2">
                      <span>⚡ +{{ item.effective_energy_cost.toFixed(1) }}/t</span>
                      <span v-if="item.total_durability_mod !== 0" class="font-medium" :class="item.total_durability_mod > 0 ? 'text-emerald-400' : 'text-rose-400'">
                        🔧 {{ item.total_durability_mod > 0 ? '+' : '' }}{{ item.total_durability_mod.toFixed(1) }}%
                      </span>
                    </div>

                    <div class="mt-auto flex gap-1.5">
                      <button
                        @click="openWorkshop(item)"
                        :disabled="item.mod_slots_used >= item.max_mod_slots"
                        class="flex-1 py-1.5 sm:py-2 rounded text-xs sm:text-sm font-medium transition-colors disabled:opacity-50"
                        :class="item.mod_slots_used < item.max_mod_slots
                          ? 'bg-fuchsia-600 hover:bg-fuchsia-500 text-white'
                          : 'bg-bg-tertiary text-text-muted cursor-not-allowed'"
                      >
                        🔧 {{ item.mod_slots_used < item.max_mod_slots ? t('inventory.cooling.modify') : t('workshop.slotsFull') }}
                      </button>
                    </div>
                  </div>
                </div>
              </div>

              <!-- Materials Section -->
              <div v-if="inventoryStore.materialItems.length > 0">
                <h3 class="text-sm font-medium text-text-muted mb-3 flex items-center gap-2">
                  <span>⛏️</span>
                  {{ t('inventory.materials.title') }}
                  <span class="px-1.5 py-0.5 rounded-full text-xs bg-orange-500/30 text-orange-400">
                    {{ inventoryStore.materialItems.reduce((sum, m) => sum + m.quantity, 0) }}
                  </span>
                </h3>
                <div class="grid grid-cols-2 sm:grid-cols-4 gap-2">
                  <div
                    v-for="mat in inventoryStore.materialItems"
                    :key="mat.material_id"
                    class="rounded-lg border p-2.5 bg-white/5 border-border/30"
                  >
                    <div class="flex items-center gap-2 mb-1">
                      <span class="text-lg">{{ mat.icon }}</span>
                      <div class="min-w-0 flex-1">
                        <h4 class="font-medium text-xs truncate" :class="getRarityColor(mat.rarity)">{{ getMaterialName(mat.name) }}</h4>
                        <span class="text-[10px] uppercase text-text-muted">{{ mat.rarity }}</span>
                      </div>
                    </div>
                    <div class="text-right font-mono font-bold text-sm text-text-primary">x{{ mat.quantity }}</div>
                  </div>
                </div>
                <p class="text-[10px] sm:text-xs text-text-muted/70 italic mt-2">
                  {{ t('inventory.materials.description') }}
                </p>
              </div>

              <!-- Components Section -->
              <div v-if="inventoryStore.componentItems.length > 0">
                <h3 class="text-sm font-medium text-text-muted mb-3 flex items-center gap-2">
                  <span>🧩</span>
                  {{ t('inventory.components.title') }}
                  <span class="px-1.5 py-0.5 rounded-full text-xs bg-fuchsia-500/30 text-fuchsia-400">
                    {{ inventoryStore.componentItems.reduce((sum, c) => sum + c.quantity, 0) }}
                  </span>
                </h3>
                <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-2 sm:gap-3">
                  <div
                    v-for="comp in inventoryStore.componentItems"
                    :key="comp.id"
                    class="rounded-lg border p-2.5 sm:p-3"
                    :class="[getTierBorder(comp.tier), getTierBg(comp.tier)]"
                  >
                    <div class="flex items-start justify-between mb-1">
                      <h4 class="font-medium text-xs truncate" :class="getTierColor(comp.tier)">{{ getComponentName(comp.id, comp.name) }}</h4>
                      <span class="text-sm ml-1">🧩</span>
                    </div>
                    <div class="flex items-center justify-between text-[10px] text-text-muted">
                      <span class="uppercase">{{ comp.tier }}</span>
                      <span class="font-medium">x{{ comp.quantity }}</span>
                    </div>
                  </div>
                </div>
                <p class="text-[10px] sm:text-xs text-text-muted/70 italic mt-2">
                  {{ t('inventory.components.description') }}
                </p>
              </div>

              <!-- Boosts Section -->
              <div v-if="inventoryStore.boostItems.length > 0">
                <h3 class="text-sm font-medium text-text-muted mb-3 flex items-center gap-2">
                  <span>🚀</span>
                  Boosts
                  <span class="px-1.5 py-0.5 rounded-full text-xs bg-amber-500/30 text-amber-400">
                    {{ inventoryStore.boostItems.length }}
                  </span>
                </h3>
                <div class="grid grid-cols-2 sm:grid-cols-2 lg:grid-cols-3 gap-2 sm:gap-3">
                  <div
                    v-for="boost in inventoryStore.boostItems"
                    :key="boost.id"
                    class="rounded-lg border p-2.5 sm:p-4 flex flex-col h-full bg-amber-500/10 border-amber-500/30"
                  >
                    <div class="flex items-start justify-between mb-1 sm:mb-2">
                      <div class="min-w-0 flex-1">
                        <h4 class="font-medium text-xs sm:text-sm text-amber-400 truncate">{{ getBoostName(boost.boost_id) }}</h4>
                        <p class="text-[10px] sm:text-xs text-text-muted uppercase">{{ boost.tier }}</p>
                      </div>
                      <span class="text-lg sm:text-2xl ml-1">{{ getBoostIcon(boost.boost_type) }}</span>
                    </div>

                    <!-- Boost type description (hidden on mobile) -->
                    <p class="hidden sm:block text-xs text-text-muted mb-2">{{ getBoostTypeDescription(boost.boost_type) }}</p>

                    <div class="flex items-center justify-between mb-0.5 sm:mb-1">
                      <span class="text-[10px] sm:text-xs text-text-muted">{{ t('market.boosts.effect') }}</span>
                      <span class="font-mono font-bold text-xs sm:text-sm text-amber-400">{{ formatBoostEffect(boost) }}</span>
                    </div>

                    <div class="flex items-center justify-between text-[10px] sm:text-xs text-text-muted mb-1 sm:mb-2">
                      <span>{{ formatDuration(boost.duration_minutes) }}</span>
                      <span class="font-medium">x{{ boost.quantity }}</span>
                    </div>

                    <div class="mt-auto">
                      <p class="text-[10px] sm:text-xs text-text-muted/70 italic text-center py-1 sm:py-2">
                        {{ t('inventory.boosts.installHint', 'Instalar desde gestion de rig') }}
                      </p>
                    </div>
                  </div>
                </div>
              </div>
            </template>
          </template>
        </div>
      </div>

      <!-- Confirmation Dialog -->
      <div
        v-if="showConfirm && confirmAction"
        class="absolute inset-0 flex items-center justify-center bg-black/50 z-10"
      >
        <div class="bg-bg-secondary rounded-xl p-6 max-w-sm w-full mx-4 border border-border animate-fade-in">
          <!-- Card Redeem Confirmation -->
          <template v-if="confirmAction.type === 'redeem'">
            <div class="text-center mb-4">
              <div class="text-4xl mb-3">💳</div>
              <h3 class="text-lg font-bold mb-1">{{ t('inventory.confirm.redeemCard') }}</h3>
              <p class="text-text-muted text-sm">{{ t('inventory.confirm.areYouSure') }}</p>
            </div>

            <div class="bg-bg-primary rounded-lg p-4 mb-4">
              <div class="flex items-center justify-between mb-2">
                <span class="text-text-muted text-sm">{{ t('inventory.confirm.card') }}</span>
                <span class="font-medium text-white">{{ confirmAction.data.cardName }}</span>
              </div>
              <div class="flex items-center justify-between">
                <span class="text-text-muted text-sm">{{ t('inventory.confirm.rechargeAmount') }}</span>
                <span class="font-bold" :class="confirmAction.data.cardType === 'energy' ? 'text-status-warning' : 'text-accent-tertiary'">
                  +{{ confirmAction.data.cardAmount }}% {{ confirmAction.data.cardType === 'energy' ? t('welcome.energy') : t('welcome.internet') }}
                </span>
              </div>
            </div>

            <!-- 4-digit confirmation code -->
            <div class="bg-bg-primary rounded-lg p-4 mb-4">
              <p class="text-text-muted text-xs text-center mb-2">{{ t('inventory.confirm.enterCode', 'Ingresa el código para confirmar') }}</p>
              <div class="text-center mb-3">
                <span class="font-mono text-2xl font-bold tracking-[0.3em] text-accent-primary">{{ generatedCode }}</span>
              </div>
              <input
                v-model="inputCode"
                type="text"
                inputmode="numeric"
                maxlength="4"
                :placeholder="t('inventory.confirm.codePlaceholder', '----')"
                class="w-full text-center font-mono text-xl tracking-[0.3em] py-2 px-3 rounded-lg bg-bg-secondary border transition-colors outline-none"
                :class="inputCode.length === 4 && inputCode !== generatedCode
                  ? 'border-status-danger focus:border-status-danger'
                  : inputCode === generatedCode
                    ? 'border-status-success focus:border-status-success'
                    : 'border-border focus:border-accent-primary'"
                @keyup.enter="inputCode === generatedCode && confirmUse()"
              />
              <p v-if="inputCode.length === 4 && inputCode !== generatedCode" class="text-status-danger text-xs text-center mt-1">
                {{ t('inventory.confirm.codeError', 'Código incorrecto') }}
              </p>
            </div>
          </template>

          <!-- Rig Install Confirmation -->
          <template v-else-if="confirmAction.type === 'install_rig'">
            <div class="text-center mb-4">
              <div class="text-4xl mb-3">⛏️</div>
              <h3 class="text-lg font-bold mb-1">{{ t('inventory.confirm.installRig', 'Instalar Rig') }}</h3>
              <p class="text-text-muted text-sm">{{ t('inventory.confirm.areYouSure') }}</p>
            </div>

            <div class="bg-bg-primary rounded-lg p-4 mb-4">
              <div class="flex items-center justify-between mb-2">
                <span class="text-text-muted text-sm">Rig</span>
                <span class="font-medium text-white">{{ confirmAction.data.rigName }}</span>
              </div>
              <p class="text-xs text-text-muted/70 mt-2">
                {{ t('inventory.confirm.installRigNote', 'El rig se instalará en un slot disponible y comenzará a minar.') }}
              </p>
            </div>
          </template>

          <div class="flex gap-3">
            <button
              @click="cancelUse"
              class="flex-1 py-2.5 rounded-lg font-medium bg-bg-tertiary hover:bg-bg-tertiary/80 transition-colors"
            >
              {{ t('common.cancel') }}
            </button>
            <button
              @click="confirmUse"
              :disabled="using || (confirmAction?.type === 'redeem' && inputCode !== generatedCode)"
              class="flex-1 py-2.5 rounded-lg font-medium transition-colors disabled:opacity-50 bg-accent-primary text-white hover:bg-accent-primary/80"
            >
              {{ using ? t('common.processing') : t('common.confirm') }}
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
          <!-- Processing State -->
          <div v-if="processingStatus === 'processing'" class="text-center">
            <div class="relative w-16 h-16 mx-auto mb-4">
              <div class="absolute inset-0 border-4 border-accent-primary/20 rounded-full"></div>
              <div class="absolute inset-0 border-4 border-accent-primary border-t-transparent rounded-full animate-spin"></div>
            </div>
            <h3 class="text-lg font-bold mb-2">{{ t('inventory.processing.title') }}</h3>
            <p class="text-text-muted text-sm">{{ t('inventory.processing.wait') }}</p>
          </div>

          <!-- Error State -->
          <div v-else-if="processingStatus === 'error'" class="text-center">
            <div class="w-16 h-16 mx-auto mb-4 bg-status-danger/20 rounded-full flex items-center justify-center">
              <svg class="w-8 h-8 text-status-danger" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </div>
            <h3 class="text-lg font-bold text-status-danger mb-2">{{ t('inventory.processing.error') }}</h3>
            <p class="text-text-muted text-sm mb-4">{{ processingError }}</p>
            <button
              @click="closeProcessingModal"
              class="w-full py-2.5 rounded-lg font-medium bg-bg-tertiary hover:bg-bg-tertiary/80 transition-colors"
            >
              {{ t('common.close') }}
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- Cooling Workshop Modal -->
    <CoolingWorkshopModal
      :show="showWorkshop"
      :cooling-item="workshopItem"
      @close="closeWorkshop"
      @modded="onModded"
    />
  </Teleport>
</template>
