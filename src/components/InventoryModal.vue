<script setup lang="ts">
import { ref, onMounted, onUnmounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAuthStore } from '@/stores/auth';
import { getPlayerInventory, redeemPrepaidCard, getPlayerBoosts, activateBoost } from '@/utils/api';
import { playSound } from '@/utils/sounds';

const { t } = useI18n();

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
  } else {
    document.body.style.overflow = '';
  }
});

onUnmounted(() => {
  document.body.style.overflow = '';
});

const loading = ref(false);
const using = ref(false);

// Confirmation dialog state
const showConfirm = ref(false);
const confirmAction = ref<{
  type: 'redeem' | 'activate';
  data: {
    cardCode?: string;
    cardName?: string;
    cardType?: 'energy' | 'internet';
    cardAmount?: number;
    boostId?: string;
    boostName?: string;
    boostEffect?: string;
    boostDuration?: number;
  };
} | null>(null);

// Processing modal state
const showProcessingModal = ref(false);
const processingStatus = ref<'processing' | 'success' | 'error'>('processing');
const processingError = ref<string>('');

function closeProcessingModal() {
  showProcessingModal.value = false;
  processingStatus.value = 'processing';
  processingError.value = '';
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

interface BoostItem {
  id: string;
  quantity: number;
  purchased_at: string;
  boost_id: string;
  name: string;
  description: string;
  boost_type: string;
  effect_value: number;
  secondary_value: number;
  duration_minutes: number;
  tier: string;
}

const coolingItems = ref<CoolingItem[]>([]);
const cardItems = ref<CardItem[]>([]);
const boostItems = ref<BoostItem[]>([]);
const activeBoosts = ref<Array<{
  id: string;
  boost_id: string;
  boost_type: string;
  name: string;
  expires_at: string;
  seconds_remaining: number;
}>>([]);

async function loadInventory() {
  if (!authStore.player) return;
  loading.value = true;

  try {
    const data = await getPlayerInventory(authStore.player.id);
    coolingItems.value = data.cooling || [];
    cardItems.value = data.cards || [];

    // Load boosts
    const boostData = await getPlayerBoosts(authStore.player.id);
    boostItems.value = boostData.inventory || [];
    activeBoosts.value = boostData.active || [];
  } catch (e) {
    console.error('Error loading inventory:', e);
  } finally {
    loading.value = false;
  }
}

function requestRedeemCard(card: CardItem) {
  confirmAction.value = {
    type: 'redeem',
    data: {
      cardCode: card.code,
      cardName: getCardName(card.card_id),
      cardType: card.card_type,
      cardAmount: card.amount,
    },
  };
  showConfirm.value = true;
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
      await loadInventory();
      await authStore.fetchPlayer();
      processingStatus.value = 'success';
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

function requestActivateBoost(boost: BoostItem) {
  confirmAction.value = {
    type: 'activate',
    data: {
      boostId: boost.boost_id,
      boostName: getBoostName(boost.boost_id),
      boostEffect: formatBoostEffect(boost),
      boostDuration: boost.duration_minutes,
    },
  };
  showConfirm.value = true;
}

async function handleActivateBoost(boostId: string) {
  if (!authStore.player || using.value) return;
  using.value = true;
  showProcessingModal.value = true;
  processingStatus.value = 'processing';
  processingError.value = '';

  try {
    const result = await activateBoost(authStore.player.id, boostId);
    if (result.success) {
      await loadInventory();
      processingStatus.value = 'success';
      playSound('success');
      emit('used');
    } else {
      processingStatus.value = 'error';
      processingError.value = result.error || t('inventory.processing.errorActivatingBoost');
      playSound('error');
    }
  } catch (e) {
    console.error('Error activating boost:', e);
    processingStatus.value = 'error';
    processingError.value = t('inventory.processing.errorActivatingBoost');
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
  } else if (type === 'activate' && data.boostId) {
    await handleActivateBoost(data.boostId);
  }

  confirmAction.value = null;
}

function cancelUse() {
  showConfirm.value = false;
  confirmAction.value = null;
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

// Translation helpers for inventory items
function getCoolingName(id: string): string {
  const key = `market.items.cooling.${id}.name`;
  const translated = t(key);
  return translated !== key ? translated : id;
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

function formatBoostEffect(boost: BoostItem): string {
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
      <div class="relative w-full max-w-4xl h-[85vh] flex flex-col bg-bg-secondary border border-border rounded-xl overflow-hidden">
        <!-- Header -->
        <div class="flex items-center justify-between p-4 border-b border-border">
          <h2 class="text-lg font-semibold flex items-center gap-2">
            <span>🎒</span>
            <span>{{ t('inventory.title') }}</span>
          </h2>
          <button
            @click="emit('close')"
            class="p-2 hover:bg-bg-tertiary rounded-lg transition-colors text-text-muted hover:text-white"
          >
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        <!-- Content -->
        <div class="flex-1 overflow-y-auto p-4 space-y-6">
          <!-- Loading -->
          <div v-if="loading" class="text-center py-16">
            <div class="w-8 h-8 mx-auto mb-4 border-2 border-accent-primary border-t-transparent rounded-full animate-spin"></div>
            <p class="text-text-muted text-sm">{{ t('inventory.loading') }}</p>
          </div>

          <!-- Empty State -->
          <div v-else-if="coolingItems.length === 0 && cardItems.length === 0 && boostItems.length === 0" class="text-center py-16">
            <div class="text-5xl mb-4 opacity-50">🎒</div>
            <p class="text-text-muted">{{ t('inventory.empty', 'Tu inventario esta vacio') }}</p>
            <p class="text-text-muted/70 text-sm mt-1">{{ t('inventory.emptyHint', 'Compra items en el mercado') }}</p>
          </div>

          <!-- Unified Grid - All items together -->
          <div v-else class="grid sm:grid-cols-2 lg:grid-cols-3 gap-3">
            <!-- Prepaid Cards -->
            <div
              v-for="card in cardItems"
              :key="card.id"
              class="rounded-lg border p-4 flex flex-col h-full min-h-[160px]"
              :class="card.card_type === 'energy'
                ? 'bg-amber-500/10 border-amber-500/30'
                : 'bg-cyan-500/10 border-cyan-500/30'"
            >
              <div class="flex items-start justify-between mb-3">
                <div>
                  <h4 class="font-medium" :class="card.card_type === 'energy' ? 'text-amber-400' : 'text-cyan-400'">{{ getCardName(card.card_id) }}</h4>
                  <p class="text-xs text-text-muted uppercase">{{ card.tier }}</p>
                </div>
                <span class="text-2xl">{{ card.card_type === 'energy' ? '⚡' : '📡' }}</span>
              </div>

              <div class="flex items-center justify-between mb-3">
                <span class="text-xs text-text-muted font-mono">{{ card.code }}</span>
                <span class="font-mono font-bold text-lg" :class="card.card_type === 'energy' ? 'text-amber-400' : 'text-cyan-400'">
                  +{{ card.amount }}%
                </span>
              </div>

              <div class="mt-auto">
                <button
                  @click="requestRedeemCard(card)"
                  :disabled="using"
                  class="w-full py-2 rounded text-sm font-medium transition-colors disabled:opacity-50"
                  :class="card.card_type === 'energy'
                    ? 'bg-amber-500 text-white hover:bg-amber-400'
                    : 'bg-cyan-500 text-white hover:bg-cyan-400'"
                >
                  {{ using ? t('common.processing') : t('inventory.cards.recharge') }}
                </button>
              </div>
            </div>

            <!-- Cooling Items -->
            <div
              v-for="item in coolingItems"
              :key="item.inventory_id"
              class="rounded-lg border p-4 flex flex-col h-full min-h-[160px]"
              :class="[getTierBorder(item.tier), getTierBg(item.tier)]"
            >
              <div class="flex items-start justify-between mb-3">
                <div>
                  <h4 class="font-medium" :class="getTierColor(item.tier)">{{ getCoolingName(item.id) }}</h4>
                  <p class="text-xs text-text-muted uppercase">{{ item.tier }}</p>
                </div>
                <span class="text-2xl">❄️</span>
              </div>

              <div class="flex items-center justify-between mb-2">
                <span class="text-xs text-text-muted">{{ t('inventory.cooling.power', 'Potencia') }}</span>
                <span class="font-mono font-bold text-lg text-cyan-400">-{{ item.cooling_power }}°</span>
              </div>

              <div class="flex items-center justify-between text-xs text-text-muted mb-2">
                <span>⚡ +{{ item.energy_cost }}/t</span>
                <span class="font-medium">x{{ item.quantity }}</span>
              </div>

              <div class="mt-auto">
                <p class="text-xs text-text-muted/70 italic text-center py-2">
                  {{ t('inventory.cooling.installHint', 'Instalar desde gestion de rig') }}
                </p>
              </div>
            </div>

            <!-- Boost Items -->
            <div
              v-for="boost in boostItems"
              :key="boost.id"
              class="rounded-lg border p-4 flex flex-col h-full min-h-[160px] bg-purple-500/10 border-purple-500/30"
            >
              <div class="flex items-start justify-between mb-3">
                <div>
                  <h4 class="font-medium text-purple-400">{{ getBoostName(boost.boost_id) }}</h4>
                  <p class="text-xs text-text-muted uppercase">{{ boost.tier }}</p>
                </div>
                <span class="text-2xl">{{ getBoostIcon(boost.boost_type) }}</span>
              </div>

              <div class="flex items-center justify-between mb-2">
                <span class="text-xs text-text-muted">{{ t('market.boosts.effect') }}</span>
                <span class="font-mono font-bold text-purple-400">{{ formatBoostEffect(boost) }}</span>
              </div>

              <div class="flex items-center justify-between text-xs text-text-muted mb-2">
                <span>{{ formatDuration(boost.duration_minutes) }}</span>
                <span class="font-medium">x{{ boost.quantity }}</span>
              </div>

              <div class="mt-auto">
                <button
                  @click="requestActivateBoost(boost)"
                  :disabled="using"
                  class="w-full py-2 rounded text-sm font-medium transition-colors disabled:opacity-50 bg-purple-500 text-white hover:bg-purple-400"
                >
                  {{ using ? t('common.processing') : t('inventory.boosts.activate') }}
                </button>
              </div>
            </div>
          </div>

          <!-- Active Boosts Bar -->
          <div v-if="activeBoosts.length > 0" class="mt-4">
            <h3 class="text-sm font-medium text-text-muted mb-2">{{ t('inventory.boosts.active') }}</h3>
            <div class="flex flex-wrap gap-2">
              <div
                v-for="boost in activeBoosts"
                :key="boost.id"
                class="flex items-center gap-2 px-3 py-1.5 rounded-lg bg-purple-500/20 border border-purple-500/30"
              >
                <span class="text-sm font-medium text-purple-400">{{ getBoostName(boost.boost_id) }}</span>
                <span class="text-xs text-text-muted">{{ formatTimeRemaining(boost.seconds_remaining) }}</span>
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
          </template>

          <!-- Boost Activate Confirmation -->
          <template v-else-if="confirmAction.type === 'activate'">
            <div class="text-center mb-4">
              <div class="text-4xl mb-3">🚀</div>
              <h3 class="text-lg font-bold mb-1">{{ t('inventory.confirm.activateBoost') }}</h3>
              <p class="text-text-muted text-sm">{{ t('inventory.confirm.areYouSure') }}</p>
            </div>

            <div class="bg-bg-primary rounded-lg p-4 mb-4">
              <div class="flex items-center justify-between mb-2">
                <span class="text-text-muted text-sm">{{ t('inventory.confirm.boost') }}</span>
                <span class="font-medium text-white">{{ confirmAction.data.boostName }}</span>
              </div>
              <div class="flex items-center justify-between mb-2">
                <span class="text-text-muted text-sm">{{ t('market.boosts.effect') }}</span>
                <span class="font-bold text-purple-400">{{ confirmAction.data.boostEffect }}</span>
              </div>
              <div class="flex items-center justify-between">
                <span class="text-text-muted text-sm">{{ t('market.boosts.duration') }}</span>
                <span class="font-medium text-white">{{ confirmAction.data.boostDuration }}m</span>
              </div>
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
              :disabled="using"
              class="flex-1 py-2.5 rounded-lg font-medium transition-colors disabled:opacity-50"
              :class="confirmAction.type === 'activate' ? 'bg-purple-500 text-white hover:bg-purple-400' : 'bg-accent-primary text-white hover:bg-accent-primary/80'"
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

          <!-- Success State -->
          <div v-else-if="processingStatus === 'success'" class="text-center">
            <div class="w-16 h-16 mx-auto mb-4 bg-status-success/20 rounded-full flex items-center justify-center">
              <svg class="w-8 h-8 text-status-success" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
              </svg>
            </div>
            <h3 class="text-lg font-bold text-status-success mb-2">{{ t('inventory.processing.success') }}</h3>
            <p class="text-text-muted text-sm mb-4">{{ t('inventory.processing.actionComplete') }}</p>
            <button
              @click="closeProcessingModal"
              class="w-full py-2.5 rounded-lg font-medium bg-status-success/20 text-status-success hover:bg-status-success/30 transition-colors"
            >
              {{ t('common.close') }}
            </button>
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
  </Teleport>
</template>
