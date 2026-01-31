<script setup lang="ts">
import { ref, onMounted, onUnmounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAuthStore } from '@/stores/auth';
import { getPlayerInventory, redeemPrepaidCard } from '@/utils/api';

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
const activeTab = ref<'cooling' | 'cards'>('cooling');

// Confirmation dialog state
const showConfirm = ref(false);
const confirmAction = ref<{
  type: 'redeem';
  data: {
    cardCode?: string;
    cardName?: string;
    cardType?: 'energy' | 'internet';
    cardAmount?: number;
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

const coolingItems = ref<CoolingItem[]>([]);
const cardItems = ref<CardItem[]>([]);

async function loadInventory() {
  if (!authStore.player) return;
  loading.value = true;

  try {
    const data = await getPlayerInventory(authStore.player.id);
    coolingItems.value = data.cooling || [];
    cardItems.value = data.cards || [];
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
      emit('used');
    } else {
      processingStatus.value = 'error';
      processingError.value = result.error || t('inventory.processing.errorRedeemCard');
    }
  } catch (e) {
    console.error('Error redeeming card:', e);
    processingStatus.value = 'error';
    processingError.value = t('inventory.processing.errorRedeemCard');
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
      <div class="relative w-full max-w-4xl max-h-[85vh] flex flex-col bg-bg-secondary border border-border rounded-xl overflow-hidden">
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

        <!-- Tabs -->
        <div class="flex gap-1 p-2 border-b border-border bg-bg-primary">
          <button
            @click="activeTab = 'cooling'"
            class="flex-1 sm:flex-none px-4 py-2 rounded-lg text-sm font-medium transition-colors flex items-center justify-center gap-2"
            :class="activeTab === 'cooling'
              ? 'bg-accent-primary text-white'
              : 'text-text-muted hover:text-white hover:bg-bg-tertiary'"
          >
            <span>❄️</span>
            <span class="hidden sm:inline">{{ t('inventory.tabs.cooling') }}</span>
            <span class="px-1.5 py-0.5 text-xs rounded bg-black/20">{{ coolingItems.length }}</span>
          </button>
          <button
            @click="activeTab = 'cards'"
            class="flex-1 sm:flex-none px-4 py-2 rounded-lg text-sm font-medium transition-colors flex items-center justify-center gap-2"
            :class="activeTab === 'cards'
              ? 'bg-accent-primary text-white'
              : 'text-text-muted hover:text-white hover:bg-bg-tertiary'"
          >
            <span>💳</span>
            <span class="hidden sm:inline">{{ t('inventory.tabs.cards') }}</span>
            <span class="px-1.5 py-0.5 text-xs rounded bg-black/20">{{ cardItems.length }}</span>
          </button>
        </div>

        <!-- Content -->
        <div class="flex-1 overflow-y-auto p-4">
          <!-- Loading -->
          <div v-if="loading" class="text-center py-16">
            <div class="w-8 h-8 mx-auto mb-4 border-2 border-accent-primary border-t-transparent rounded-full animate-spin"></div>
            <p class="text-text-muted text-sm">{{ t('inventory.loading') }}</p>
          </div>

          <template v-else>
          <!-- Cooling Tab -->
          <div v-show="activeTab === 'cooling'">
            <div v-if="coolingItems.length === 0" class="text-center py-12">
              <div class="text-4xl mb-3 opacity-50">❄️</div>
              <p class="text-text-muted text-sm">{{ t('inventory.cooling.noItems') }}</p>
            </div>
            <div v-else class="grid sm:grid-cols-2 lg:grid-cols-3 gap-3">
              <div
                v-for="item in coolingItems"
                :key="item.inventory_id"
                class="rounded-lg border p-3"
                :class="[getTierBorder(item.tier), getTierBg(item.tier)]"
              >
                <div class="flex items-start justify-between mb-2">
                  <div>
                    <h4 class="font-medium" :class="getTierColor(item.tier)">{{ getCoolingName(item.id) }}</h4>
                    <p class="text-xs text-text-muted uppercase">{{ item.tier }}</p>
                  </div>
                  <div class="text-lg font-mono font-medium">-{{ item.cooling_power }}°</div>
                </div>

                <div class="flex items-center gap-2 text-xs text-text-muted">
                  <span>⚡ +{{ item.energy_cost }}/t</span>
                  <span>•</span>
                  <span>x{{ item.quantity }}</span>
                </div>
              </div>
            </div>
          </div>

          <!-- Cards Tab -->
          <div v-show="activeTab === 'cards'">
            <div v-if="cardItems.length === 0" class="text-center py-12">
              <div class="text-4xl mb-3 opacity-50">💳</div>
              <p class="text-text-muted text-sm">{{ t('inventory.cards.noCards') }}</p>
            </div>
            <div v-else class="grid sm:grid-cols-2 gap-3">
              <div
                v-for="card in cardItems"
                :key="card.id"
                class="rounded-lg border p-3"
                :class="card.card_type === 'energy'
                  ? 'bg-amber-500/10 border-amber-500/30'
                  : 'bg-cyan-500/10 border-cyan-500/30'"
              >
                <div class="flex items-start justify-between mb-2">
                  <div>
                    <h3 class="font-medium" :class="card.card_type === 'energy' ? 'text-amber-400' : 'text-cyan-400'">{{ getCardName(card.card_id) }}</h3>
                    <p class="text-xs text-text-muted uppercase">{{ card.tier }}</p>
                  </div>
                  <span class="text-2xl">{{ card.card_type === 'energy' ? '⚡' : '📡' }}</span>
                </div>

                <div class="flex items-center justify-between mb-3 text-xs">
                  <span class="text-text-muted">Code: <span class="font-mono">{{ card.code }}</span></span>
                  <span class="font-mono font-medium text-lg" :class="card.card_type === 'energy' ? 'text-amber-400' : 'text-cyan-400'">
                    +{{ card.amount }}%
                  </span>
                </div>

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
