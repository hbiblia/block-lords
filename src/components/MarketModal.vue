<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAuthStore } from '@/stores/auth';
import { useMarketStore } from '@/stores/market';
import { useRoninWallet } from '@/composables/useRoninWallet';
import { formatGamecoin, formatCrypto, formatNumber } from '@/utils/format';

// Types for items
interface RigItem {
  id: string;
  hashrate: number;
  tier: string;
  base_price: number;
  power_consumption: number;
  internet_consumption: number;
}

interface CoolingItemType {
  id: string;
  cooling_power: number;
  tier: string;
  base_price: number;
}

interface CardItem {
  id: string;
  card_type: 'energy' | 'internet';
  amount: number;
  base_price: number;
  tier: string;
  currency: 'gamecoin' | 'crypto';
}

interface BoostItemType {
  id: string;
  boost_type: string;
  effect_value: number;
  secondary_value: number;
  duration_minutes: number;
  base_price: number;
  currency: 'gamecoin' | 'crypto';
  tier: string;
}

interface CryptoPackageType {
  id: string;
  name: string;
  description: string;
  crypto_amount: number;
  ron_price: number;
  bonus_percent: number;
  tier: string;
  is_featured: boolean;
  total_crypto: number;
}

const { t } = useI18n();

const authStore = useAuthStore();
const marketStore = useMarketStore();
const roninWallet = useRoninWallet();

const props = defineProps<{
  show: boolean;
}>();

const emit = defineEmits<{
  close: [];
  purchased: [];
}>();

// Bloquear scroll del body cuando el modal está abierto
watch(() => props.show, (isOpen) => {
  if (isOpen) {
    document.body.style.overflow = 'hidden';
  } else {
    document.body.style.overflow = '';
  }
});

// Limpiar al desmontar
onUnmounted(() => {
  document.body.style.overflow = '';
});

const activeFilter = ref<'all' | 'rigs' | 'cooling' | 'energy' | 'internet' | 'boosts' | 'crypto'>('all');

// Mobile category popup
const showMobileCategories = ref(false);

function selectCategory(category: typeof activeFilter.value) {
  activeFilter.value = category;
  showMobileCategories.value = false;
}

function getCategoryIcon(category: typeof activeFilter.value): string {
  switch (category) {
    case 'all': return '🏪';
    case 'rigs': return '⛏️';
    case 'cooling': return '❄️';
    case 'energy': return '⚡';
    case 'internet': return '📡';
    case 'boosts': return '🚀';
    case 'crypto': return '💎';
    default: return '🏪';
  }
}

// Confirmation dialog state
const showConfirm = ref(false);
const confirmAction = ref<{
  type: 'rig' | 'cooling' | 'card' | 'boost' | 'crypto_package';
  id: string;
  name: string;
  price: number;
  description: string;
  currency: 'gamecoin' | 'crypto' | 'ron';
} | null>(null);

// Processing modal state
const showProcessingModal = ref(false);
const processingStatus = ref<'processing' | 'success' | 'error'>('processing');
const processingError = ref<string>('');
const processingStep = ref<'connecting' | 'sending' | 'confirming' | 'crediting' | ''>('');

// Use store data
const loading = computed(() => marketStore.loading);
const buying = computed(() => marketStore.buying);
const rigsForSale = computed(() => marketStore.rigsForSale);
const coolingItems = computed(() => marketStore.coolingItems);
const energyCards = computed(() => marketStore.energyCards);
const internetCards = computed(() => marketStore.internetCards);
const boostItems = computed(() => marketStore.boostItems);
const cryptoPackages = computed(() => marketStore.cryptoPackages);

const balance = computed(() => authStore.player?.gamecoin_balance ?? 0);
const cryptoBalance = computed(() => authStore.player?.crypto_balance ?? 0);

function getRigOwned(id: string): number {
  return marketStore.getRigOwned(id);
}

function getTierColor(tier: string) {
  switch (tier) {
    case 'basic': return 'text-gray-400';
    case 'standard': return 'text-blue-400';
    case 'advanced': return 'text-purple-400';
    case 'elite': return 'text-yellow-400';
    default: return 'text-white';
  }
}

function getTierBorder(tier: string) {
  switch (tier) {
    case 'basic': return 'border-gray-500/30';
    case 'standard': return 'border-blue-500/30';
    case 'advanced': return 'border-purple-500/30';
    case 'elite': return 'border-yellow-500/30';
    default: return 'border-border/50';
  }
}

// Translation helpers for market items - fallback to DB name if no translation
function getRigName(id: string): string {
  const key = `market.items.rigs.${id}.name`;
  const translated = t(key);
  if (translated !== key) return translated;
  // Fallback to DB name
  const rig = rigsForSale.value.find(r => r.id === id);
  return rig?.name ?? id;
}

function getCoolingName(id: string): string {
  const key = `market.items.cooling.${id}.name`;
  const translated = t(key);
  if (translated !== key) return translated;
  // Fallback to DB name
  const item = coolingItems.value.find(c => c.id === id);
  return item?.name ?? id;
}

function getCoolingDescription(id: string): string {
  const key = `market.items.cooling.${id}.description`;
  const translated = t(key);
  if (translated !== key) return translated;
  // Fallback to DB description
  const item = coolingItems.value.find(c => c.id === id);
  return item?.description ?? '';
}

function getCoolingOwned(id: string): { installed: number; inventory: number; total: number } {
  return marketStore.getCoolingOwned(id);
}

function getCardOwned(id: string): number {
  return marketStore.getCardOwned(id);
}

function getCardName(id: string): string {
  const key = `market.items.cards.${id}.name`;
  const translated = t(key);
  return translated !== key ? translated : id;
}

function getCardDescription(id: string): string {
  const key = `market.items.cards.${id}.description`;
  const translated = t(key);
  return translated !== key ? translated : '';
}

function getBoostName(id: string): string {
  const key = `market.items.boosts.${id}.name`;
  const translated = t(key);
  return translated !== key ? translated : id;
}

function getBoostOwned(id: string): number {
  return marketStore.getBoostOwned(id);
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

function getBoostTypeDescription(boostType: string): string {
  const key = `market.boosts.types.${boostType}`;
  const translated = t(key);
  return translated !== key ? translated : '';
}

function formatBoostEffect(boost: BoostItemType): string {
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

function canAffordBoost(boost: BoostItemType): boolean {
  if (boost.currency === 'crypto') {
    return cryptoBalance.value >= boost.base_price;
  }
  return balance.value >= boost.base_price;
}

function getCryptoPackageName(id: string): string {
  const key = `market.items.crypto_packages.${id}.name`;
  const translated = t(key);
  if (translated !== key) return translated;
  const pkg = cryptoPackages.value.find(p => p.id === id);
  return pkg?.name ?? id;
}

function getCryptoPackageDescription(id: string): string {
  const key = `market.items.crypto_packages.${id}.description`;
  const translated = t(key);
  if (translated !== key) return translated;
  const pkg = cryptoPackages.value.find(p => p.id === id);
  return pkg?.description ?? '';
}

async function loadData() {
  await marketStore.loadData();
}

function requestBuyRig(rig: RigItem) {
  confirmAction.value = {
    type: 'rig',
    id: rig.id,
    name: getRigName(rig.id),
    price: rig.base_price,
    description: `${formatNumber(rig.hashrate)} H/s - ${rig.tier}`,
    currency: 'gamecoin',
  };
  showConfirm.value = true;
}

async function buyRig(rigId: string) {
  if (!authStore.player) return;
  showProcessingModal.value = true;
  processingStatus.value = 'processing';
  processingError.value = '';

  const result = await marketStore.buyRig(rigId);

  if (result.success) {
    processingStatus.value = 'success';
    emit('purchased');
  } else {
    processingStatus.value = 'error';
    processingError.value = result.error ?? t('market.processing.errorBuyingRig');
  }
}

function requestBuyCooling(item: CoolingItemType) {
  confirmAction.value = {
    type: 'cooling',
    id: item.id,
    name: getCoolingName(item.id),
    price: item.base_price,
    description: `-${item.cooling_power}°C ${t('market.cooling_suffix')} - ${item.tier}`,
    currency: 'gamecoin',
  };
  showConfirm.value = true;
}

async function buyCooling(coolingId: string) {
  if (!authStore.player) return;
  showProcessingModal.value = true;
  processingStatus.value = 'processing';
  processingError.value = '';

  const result = await marketStore.buyCooling(coolingId);

  if (result.success) {
    processingStatus.value = 'success';
    emit('purchased');
  } else {
    processingStatus.value = 'error';
    processingError.value = result.error ?? t('market.processing.errorBuyingCooling');
  }
}

function requestBuyCard(card: CardItem) {
  confirmAction.value = {
    type: 'card',
    id: card.id,
    name: getCardName(card.id),
    price: card.base_price,
    description: `+${card.amount}% ${card.card_type === 'energy' ? t('market.energy') : t('market.internet')}`,
    currency: card.currency || 'gamecoin',
  };
  showConfirm.value = true;
}

async function buyCard(cardId: string) {
  if (!authStore.player) return;
  showProcessingModal.value = true;
  processingStatus.value = 'processing';
  processingError.value = '';

  const result = await marketStore.buyCard(cardId);

  if (result.success) {
    processingStatus.value = 'success';
    emit('purchased');
  } else {
    processingStatus.value = 'error';
    processingError.value = result.error ?? t('market.processing.errorBuyingCard');
  }
}

function requestBuyBoost(boost: BoostItemType) {
  confirmAction.value = {
    type: 'boost',
    id: boost.id,
    name: getBoostName(boost.id),
    price: boost.base_price,
    description: `${formatBoostEffect(boost)} - ${formatDuration(boost.duration_minutes)}`,
    currency: boost.currency || 'gamecoin',
  };
  showConfirm.value = true;
}

async function buyBoost(boostId: string) {
  if (!authStore.player) return;
  showProcessingModal.value = true;
  processingStatus.value = 'processing';
  processingError.value = '';

  const result = await marketStore.buyBoost(boostId);

  if (result.success) {
    processingStatus.value = 'success';
    emit('purchased');
  } else {
    processingStatus.value = 'error';
    processingError.value = result.error ?? t('market.processing.errorBuyingBoost');
  }
}

function requestBuyCryptoPackage(pkg: CryptoPackageType) {
  const bonusText = pkg.bonus_percent > 0 ? ` (+${pkg.bonus_percent}% bonus)` : '';
  confirmAction.value = {
    type: 'crypto_package',
    id: pkg.id,
    name: getCryptoPackageName(pkg.id),
    price: pkg.ron_price,
    description: `${pkg.total_crypto} 💎 Crypto${bonusText}`,
    currency: 'ron',
  };
  showConfirm.value = true;
}

async function buyCryptoPackage(packageId: string) {
  if (!authStore.player) return;

  // Get package details for the price
  const pkg = cryptoPackages.value.find(p => p.id === packageId);
  if (!pkg) {
    processingStatus.value = 'error';
    processingError.value = t('market.processing.packageNotFound');
    showProcessingModal.value = true;
    return;
  }

  showProcessingModal.value = true;
  processingStatus.value = 'processing';
  processingError.value = '';

  // Step 1: Connect wallet if not connected
  if (!roninWallet.isConnected.value) {
    processingStep.value = 'connecting';

    if (!roninWallet.isInstalled.value) {
      processingStatus.value = 'error';
      processingError.value = t('market.wallet.notInstalled');
      processingStep.value = '';
      return;
    }

    const connected = await roninWallet.connect();
    if (!connected) {
      processingStatus.value = 'error';
      processingError.value = roninWallet.error.value ?? t('market.wallet.connectionFailed');
      processingStep.value = '';
      return;
    }
  }

  // Step 2: Send RON transaction
  processingStep.value = 'sending';
  const sendResult = await roninWallet.sendRON(pkg.ron_price);

  if (!sendResult.success || !sendResult.txHash) {
    processingStatus.value = 'error';
    processingError.value = sendResult.error ?? t('market.wallet.transactionFailed');
    processingStep.value = '';
    return;
  }

  // Step 3: Wait for transaction confirmation
  processingStep.value = 'confirming';
  const confirmResult = await roninWallet.waitForTransaction(sendResult.txHash);

  if (!confirmResult.confirmed) {
    processingStatus.value = 'error';
    processingError.value = confirmResult.error ?? t('market.wallet.confirmationFailed');
    processingStep.value = '';
    return;
  }

  // Step 4: Credit crypto to player account
  processingStep.value = 'crediting';
  const result = await marketStore.buyCryptoPackage(packageId, sendResult.txHash);

  processingStep.value = '';

  if (result.success) {
    processingStatus.value = 'success';
    emit('purchased');
  } else {
    processingStatus.value = 'error';
    processingError.value = result.error ?? t('market.processing.errorBuyingCrypto');
  }
}

function closeProcessingModal() {
  showProcessingModal.value = false;
  processingStatus.value = 'processing';
  processingError.value = '';
  processingStep.value = '';
}

async function confirmPurchase() {
  if (!confirmAction.value) return;

  const { type, id } = confirmAction.value;
  showConfirm.value = false;

  if (type === 'rig') {
    await buyRig(id);
  } else if (type === 'cooling') {
    await buyCooling(id);
  } else if (type === 'card') {
    await buyCard(id);
  } else if (type === 'boost') {
    await buyBoost(id);
  } else if (type === 'crypto_package') {
    await buyCryptoPackage(id);
  }

  confirmAction.value = null;
}

function cancelPurchase() {
  showConfirm.value = false;
  confirmAction.value = null;
}

onMounted(() => {
  if (props.show) {
    loadData();
  }
});

watch(() => props.show, (newVal) => {
  if (newVal) {
    loadData();
  }
});
</script>

<template>
  <Teleport to="body">
    <div
      v-if="show"
      class="fixed inset-0 z-50 flex items-center justify-center p-4"
    >
      <!-- Backdrop -->
      <div
        class="absolute inset-0 bg-black/70 backdrop-blur-sm"
        @click="emit('close')"
      ></div>

      <!-- Modal -->
      <div class="relative w-full max-w-5xl h-[90vh] overflow-hidden card animate-fade-in flex flex-col">
        <!-- Header -->
        <div class="flex items-center justify-between p-4 border-b border-border/50">
          <h2 class="text-xl font-display font-bold">
            <span class="gradient-text">{{ t('market.title') }}</span>
          </h2>
          <div class="flex items-center gap-4">
            <span class="text-sm text-text-muted flex items-center gap-3">
              {{ t('market.balance') }}
              <span class="font-bold text-status-warning">{{ formatGamecoin(balance) }} 🪙</span>
              <span class="font-bold text-accent-primary">{{ formatCrypto(cryptoBalance) }} 💎</span>
            </span>
            <button
              @click="emit('close')"
              class="w-8 h-8 rounded-lg bg-bg-tertiary hover:bg-bg-secondary flex items-center justify-center transition-colors"
            >
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>
        </div>

        <!-- Main Content with Sidebar -->
        <div class="flex flex-1 overflow-hidden">
          <!-- Sidebar Filters (hidden on mobile) -->
          <div class="hidden md:flex w-40 border-r border-border/50 p-2 flex-col gap-1 shrink-0">
            <button
              @click="activeFilter = 'all'"
              class="flex items-center gap-2 px-3 py-2 rounded-lg text-sm font-medium transition-colors text-left"
              :class="activeFilter === 'all'
                ? 'bg-accent-primary/20 text-accent-primary'
                : 'text-text-muted hover:bg-bg-tertiary hover:text-white'"
            >
              <span>🏪</span>
              <span>{{ t('market.filters.all', 'Todos') }}</span>
            </button>
            <button
              @click="activeFilter = 'rigs'"
              class="flex items-center gap-2 px-3 py-2 rounded-lg text-sm font-medium transition-colors text-left"
              :class="activeFilter === 'rigs'
                ? 'bg-accent-primary/20 text-accent-primary'
                : 'text-text-muted hover:bg-bg-tertiary hover:text-white'"
            >
              <span>⛏️</span>
              <span>{{ t('market.tabs.rigs') }}</span>
            </button>
            <button
              @click="activeFilter = 'cooling'"
              class="flex items-center gap-2 px-3 py-2 rounded-lg text-sm font-medium transition-colors text-left"
              :class="activeFilter === 'cooling'
                ? 'bg-cyan-500/20 text-cyan-400'
                : 'text-text-muted hover:bg-bg-tertiary hover:text-white'"
            >
              <span>❄️</span>
              <span>{{ t('market.tabs.cooling') }}</span>
            </button>
            <button
              @click="activeFilter = 'energy'"
              class="flex items-center gap-2 px-3 py-2 rounded-lg text-sm font-medium transition-colors text-left"
              :class="activeFilter === 'energy'
                ? 'bg-amber-500/20 text-amber-400'
                : 'text-text-muted hover:bg-bg-tertiary hover:text-white'"
            >
              <span>⚡</span>
              <span>{{ t('market.energy') }}</span>
            </button>
            <button
              @click="activeFilter = 'internet'"
              class="flex items-center gap-2 px-3 py-2 rounded-lg text-sm font-medium transition-colors text-left"
              :class="activeFilter === 'internet'
                ? 'bg-cyan-500/20 text-cyan-400'
                : 'text-text-muted hover:bg-bg-tertiary hover:text-white'"
            >
              <span>📡</span>
              <span>{{ t('market.internet') }}</span>
            </button>
            <button
              @click="activeFilter = 'boosts'"
              class="flex items-center gap-2 px-3 py-2 rounded-lg text-sm font-medium transition-colors text-left"
              :class="activeFilter === 'boosts'
                ? 'bg-purple-500/20 text-purple-400'
                : 'text-text-muted hover:bg-bg-tertiary hover:text-white'"
            >
              <span>🚀</span>
              <span>{{ t('market.tabs.boosts') }}</span>
            </button>
            <button
              @click="activeFilter = 'crypto'"
              class="flex items-center gap-2 px-3 py-2 rounded-lg text-sm font-medium transition-colors text-left"
              :class="activeFilter === 'crypto'
                ? 'bg-gradient-to-r from-blue-500/20 to-purple-500/20 text-blue-400'
                : 'text-text-muted hover:bg-bg-tertiary hover:text-white'"
            >
              <span>💎</span>
              <span>{{ t('market.tabs.crypto', 'Crypto') }}</span>
            </button>
          </div>

          <!-- Content Grid -->
          <div class="flex-1 p-4 overflow-y-auto">
            <!-- Loading -->
            <div v-if="loading" class="text-center py-12 text-text-muted">
              {{ t('common.loading') }}
            </div>

            <!-- Unified Grid -->
            <div v-else class="grid sm:grid-cols-2 lg:grid-cols-3 gap-3">
              <!-- Rigs -->
              <template v-if="activeFilter === 'all' || activeFilter === 'rigs'">
                <div
                  v-for="rig in rigsForSale"
                  :key="rig.id"
                  class="rounded-lg border p-4 flex flex-col min-h-[200px] bg-bg-secondary transition-all hover:scale-[1.01]"
                  :class="getTierBorder(rig.tier)"
                >
                  <div class="flex items-start justify-between mb-2">
                    <div>
                      <h4 class="font-medium">{{ getRigName(rig.id) }}</h4>
                      <p class="text-xs uppercase" :class="getTierColor(rig.tier)">{{ rig.tier }}</p>
                    </div>
                    <span class="text-2xl">⛏️</span>
                  </div>

                  <div class="flex items-center justify-between mb-2">
                    <span class="text-xs text-text-muted">Hashrate</span>
                    <span class="font-mono font-bold text-accent-primary">{{ formatNumber(rig.hashrate) }} H/s</span>
                  </div>

                  <div class="flex items-center gap-2 text-xs text-text-muted mb-2">
                    <span>⚡{{ rig.power_consumption }}/t</span>
                    <span>•</span>
                    <span>📡{{ rig.internet_consumption }}/t</span>
                  </div>

                  <!-- Show owned quantity if any -->
                  <div v-if="getRigOwned(rig.id) > 0" class="flex items-center gap-2 text-xs mb-2">
                    <span class="px-2 py-0.5 rounded bg-status-success/20 text-status-success">
                      {{ getRigOwned(rig.id) }} {{ t('market.rigs.owned', 'Adquirido') }}
                    </span>
                  </div>

                  <div class="mt-auto">
                    <button
                      @click="requestBuyRig(rig)"
                      class="w-full py-2 rounded text-sm font-medium transition-colors disabled:opacity-50"
                      :class="balance >= rig.base_price
                        ? 'bg-accent-primary text-white hover:bg-accent-primary/80'
                        : 'bg-bg-tertiary text-text-muted cursor-not-allowed'"
                      :disabled="buying || balance < rig.base_price"
                    >
                      {{ buying ? '...' : `${formatNumber(rig.base_price)} 🪙` }}
                    </button>
                  </div>
                </div>
              </template>

              <!-- Cooling -->
              <template v-if="activeFilter === 'all' || activeFilter === 'cooling'">
                <div
                  v-for="item in coolingItems"
                  :key="item.id"
                  class="rounded-lg border p-4 flex flex-col min-h-[200px] bg-bg-secondary transition-all hover:scale-[1.01]"
                  :class="getTierBorder(item.tier)"
                >
                  <div class="flex items-start justify-between mb-2">
                    <div>
                      <h4 class="font-medium">{{ getCoolingName(item.id) }}</h4>
                      <p class="text-xs uppercase" :class="getTierColor(item.tier)">{{ item.tier }}</p>
                    </div>
                    <span class="text-2xl">❄️</span>
                  </div>

                  <div class="flex items-center justify-between mb-2">
                    <span class="text-xs text-text-muted">{{ t('inventory.cooling.power', 'Potencia') }}</span>
                    <span class="font-mono font-bold text-cyan-400">-{{ item.cooling_power }}°C</span>
                  </div>

                  <!-- Show owned quantity if any -->
                  <div v-if="getCoolingOwned(item.id).total > 0" class="flex items-center gap-2 text-xs mb-2">
                    <span v-if="getCoolingOwned(item.id).installed > 0" class="px-2 py-0.5 rounded bg-status-success/20 text-status-success">
                      {{ getCoolingOwned(item.id).installed }} {{ t('market.cooling.installed') }}
                    </span>
                    <span v-if="getCoolingOwned(item.id).inventory > 0" class="px-2 py-0.5 rounded bg-accent-primary/20 text-accent-primary">
                      {{ getCoolingOwned(item.id).inventory }} {{ t('market.cooling.inventory') }}
                    </span>
                  </div>

                  <p v-else class="text-xs text-text-muted mb-2 line-clamp-2">{{ getCoolingDescription(item.id) }}</p>

                  <div class="mt-auto">
                    <button
                      @click="requestBuyCooling(item)"
                      class="w-full py-2 rounded text-sm font-medium transition-colors disabled:opacity-50"
                      :class="balance >= item.base_price
                        ? 'bg-cyan-500 text-white hover:bg-cyan-400'
                        : 'bg-bg-tertiary text-text-muted cursor-not-allowed'"
                      :disabled="buying || balance < item.base_price"
                    >
                      {{ buying ? '...' : `${formatNumber(item.base_price)} 🪙` }}
                    </button>
                  </div>
                </div>
              </template>

              <!-- Energy Cards -->
              <template v-if="activeFilter === 'all' || activeFilter === 'energy'">
                <div
                  v-for="card in energyCards"
                  :key="card.id"
                  class="rounded-lg border p-4 flex flex-col min-h-[200px] bg-amber-500/10 border-amber-500/30 transition-all hover:scale-[1.01]"
                >
                  <div class="flex items-start justify-between mb-2">
                    <div>
                      <h4 class="font-medium text-amber-400">{{ getCardName(card.id) }}</h4>
                      <p class="text-xs text-text-muted uppercase">{{ card.tier }}</p>
                    </div>
                    <span class="text-2xl">⚡</span>
                  </div>

                  <div class="flex items-center justify-between mb-2">
                    <span class="text-xs text-text-muted">{{ t('market.energy') }}</span>
                    <span class="font-mono font-bold text-lg text-amber-400">+{{ card.amount }}%</span>
                  </div>

                  <!-- Show owned quantity if any -->
                  <div v-if="getCardOwned(card.id) > 0" class="flex items-center gap-2 text-xs mb-2">
                    <span class="px-2 py-0.5 rounded bg-amber-500/20 text-amber-400">
                      {{ getCardOwned(card.id) }} {{ t('market.cooling.inventory') }}
                    </span>
                  </div>
                  <p v-else class="text-xs text-text-muted mb-2 line-clamp-2">{{ getCardDescription(card.id) }}</p>

                  <div class="mt-auto">
                    <button
                      @click="requestBuyCard(card)"
                      class="w-full py-2 rounded text-sm font-medium transition-colors disabled:opacity-50"
                      :class="(card.currency === 'crypto' ? cryptoBalance : balance) >= card.base_price
                        ? 'bg-amber-500 text-white hover:bg-amber-400'
                        : 'bg-bg-tertiary text-text-muted cursor-not-allowed'"
                      :disabled="buying || (card.currency === 'crypto' ? cryptoBalance : balance) < card.base_price"
                    >
                      {{ buying ? '...' : `${formatNumber(card.base_price)} ${card.currency === 'crypto' ? '💎' : '🪙'}` }}
                    </button>
                  </div>
                </div>
              </template>

              <!-- Internet Cards -->
              <template v-if="activeFilter === 'all' || activeFilter === 'internet'">
                <div
                  v-for="card in internetCards"
                  :key="card.id"
                  class="rounded-lg border p-4 flex flex-col min-h-[200px] bg-cyan-500/10 border-cyan-500/30 transition-all hover:scale-[1.01]"
                >
                  <div class="flex items-start justify-between mb-2">
                    <div>
                      <h4 class="font-medium text-cyan-400">{{ getCardName(card.id) }}</h4>
                      <p class="text-xs text-text-muted uppercase">{{ card.tier }}</p>
                    </div>
                    <span class="text-2xl">📡</span>
                  </div>

                  <div class="flex items-center justify-between mb-2">
                    <span class="text-xs text-text-muted">{{ t('market.internet') }}</span>
                    <span class="font-mono font-bold text-lg text-cyan-400">+{{ card.amount }}%</span>
                  </div>

                  <!-- Show owned quantity if any -->
                  <div v-if="getCardOwned(card.id) > 0" class="flex items-center gap-2 text-xs mb-2">
                    <span class="px-2 py-0.5 rounded bg-cyan-500/20 text-cyan-400">
                      {{ getCardOwned(card.id) }} {{ t('market.cooling.inventory') }}
                    </span>
                  </div>
                  <p v-else class="text-xs text-text-muted mb-2 line-clamp-2">{{ getCardDescription(card.id) }}</p>

                  <div class="mt-auto">
                    <button
                      @click="requestBuyCard(card)"
                      class="w-full py-2 rounded text-sm font-medium transition-colors disabled:opacity-50"
                      :class="(card.currency === 'crypto' ? cryptoBalance : balance) >= card.base_price
                        ? 'bg-cyan-500 text-white hover:bg-cyan-400'
                        : 'bg-bg-tertiary text-text-muted cursor-not-allowed'"
                      :disabled="buying || (card.currency === 'crypto' ? cryptoBalance : balance) < card.base_price"
                    >
                      {{ buying ? '...' : `${formatNumber(card.base_price)} ${card.currency === 'crypto' ? '💎' : '🪙'}` }}
                    </button>
                  </div>
                </div>
              </template>

              <!-- Boosts -->
              <template v-if="activeFilter === 'all' || activeFilter === 'boosts'">
                <div
                  v-for="boost in boostItems"
                  :key="boost.id"
                  class="rounded-lg border p-4 flex flex-col min-h-[200px] bg-purple-500/10 border-purple-500/30 transition-all hover:scale-[1.01]"
                >
                  <div class="flex items-start justify-between mb-2">
                    <div>
                      <h4 class="font-medium text-purple-400">{{ getBoostName(boost.id) }}</h4>
                      <p class="text-xs text-text-muted uppercase">{{ boost.tier }}</p>
                    </div>
                    <span class="text-2xl">{{ getBoostIcon(boost.boost_type) }}</span>
                  </div>

                  <!-- Boost type description -->
                  <p class="text-xs text-text-muted mb-2">{{ getBoostTypeDescription(boost.boost_type) }}</p>

                  <div class="flex items-center justify-between mb-1">
                    <span class="text-xs text-text-muted">{{ t('market.boosts.effect') }}</span>
                    <span class="font-mono font-bold text-purple-400">{{ formatBoostEffect(boost) }}</span>
                  </div>

                  <div class="flex items-center justify-between mb-2">
                    <span class="text-xs text-text-muted">{{ t('market.boosts.duration') }}</span>
                    <span class="font-mono text-sm">{{ formatDuration(boost.duration_minutes) }}</span>
                  </div>

                  <!-- Show owned quantity if any -->
                  <div v-if="getBoostOwned(boost.id) > 0" class="flex items-center gap-2 text-xs mb-2">
                    <span class="px-2 py-0.5 rounded bg-purple-500/20 text-purple-400">
                      {{ getBoostOwned(boost.id) }} {{ t('market.cooling.inventory') }}
                    </span>
                  </div>

                  <div class="mt-auto">
                    <button
                      @click="requestBuyBoost(boost)"
                      class="w-full py-2 rounded text-sm font-medium transition-colors disabled:opacity-50"
                      :class="canAffordBoost(boost)
                        ? 'bg-purple-500 text-white hover:bg-purple-400'
                        : 'bg-bg-tertiary text-text-muted cursor-not-allowed'"
                      :disabled="buying || !canAffordBoost(boost)"
                    >
                      {{ buying ? '...' : `${formatNumber(boost.base_price)} ${boost.currency === 'crypto' ? '💎' : '🪙'}` }}
                    </button>
                  </div>
                </div>
              </template>

              <!-- Crypto Packages (RON) -->
              <template v-if="activeFilter === 'all' || activeFilter === 'crypto'">
                <div
                  v-for="pkg in cryptoPackages"
                  :key="pkg.id"
                  class="rounded-lg border p-4 flex flex-col min-h-[200px] transition-all hover:scale-[1.01] relative overflow-hidden"
                  :class="[
                    pkg.is_featured
                      ? 'bg-gradient-to-br from-blue-500/20 via-purple-500/20 to-pink-500/20 border-blue-500/50'
                      : 'bg-gradient-to-br from-blue-500/10 to-purple-500/10 border-blue-500/30'
                  ]"
                >
                  <!-- Featured badge -->
                  <div
                    v-if="pkg.is_featured"
                    class="absolute top-0 right-0 bg-gradient-to-r from-blue-500 to-purple-500 text-white text-xs font-bold px-3 py-1 rounded-bl-lg"
                  >
                    {{ t('market.crypto.featured', 'Popular') }}
                  </div>

                  <div class="flex items-start justify-between mb-3">
                    <div>
                      <h4 class="font-medium text-blue-400">{{ getCryptoPackageName(pkg.id) }}</h4>
                      <p class="text-xs text-text-muted uppercase">{{ pkg.tier }}</p>
                    </div>
                    <span class="text-3xl">💎</span>
                  </div>

                  <div class="flex items-center justify-between mb-2">
                    <span class="text-xs text-text-muted">{{ t('market.crypto.amount', 'Cantidad') }}</span>
                    <div class="text-right">
                      <span class="font-mono font-bold text-xl text-blue-400">{{ pkg.total_crypto }}</span>
                      <span class="text-blue-400 ml-1">💎</span>
                    </div>
                  </div>

                  <!-- Bonus badge -->
                  <div v-if="pkg.bonus_percent > 0" class="flex items-center justify-center mb-2">
                    <span class="px-3 py-1 rounded-full bg-green-500/20 text-green-400 text-sm font-bold">
                      +{{ pkg.bonus_percent }}% BONUS
                    </span>
                  </div>

                  <p class="text-xs text-text-muted mb-3 line-clamp-2">{{ getCryptoPackageDescription(pkg.id) }}</p>

                  <div class="mt-auto">
                    <button
                      @click="requestBuyCryptoPackage(pkg)"
                      class="w-full py-2.5 rounded-lg text-sm font-bold transition-all disabled:opacity-50 bg-gradient-to-r from-blue-500 to-purple-500 text-white hover:from-blue-400 hover:to-purple-400 shadow-lg"
                      :disabled="buying"
                    >
                      {{ buying ? '...' : `${formatNumber(pkg.ron_price)} RON` }}
                    </button>
                  </div>
                </div>
              </template>
            </div>
          </div>
        </div>

      </div>

      <!-- Mobile Category Button (floating circle centered at bottom) -->
      <div class="md:hidden fixed bottom-6 left-1/2 -translate-x-1/2 z-[5]">
        <button
          @click="showMobileCategories = true"
          class="w-14 h-14 flex items-center justify-center bg-accent-primary rounded-full shadow-lg hover:bg-accent-primary/90 transition-all active:scale-95"
        >
          <span class="text-2xl">{{ getCategoryIcon(activeFilter) }}</span>
        </button>
      </div>

      <!-- Confirmation Dialog -->
      <div
        v-if="showConfirm && confirmAction"
        class="absolute inset-0 flex items-center justify-center bg-black/50 z-10"
      >
        <div class="bg-bg-secondary rounded-xl p-6 max-w-sm w-full mx-4 border border-border animate-fade-in">
          <div class="text-center mb-4">
            <div class="text-4xl mb-3">
              {{ confirmAction.type === 'rig' ? '⛏️' : confirmAction.type === 'cooling' ? '❄️' : confirmAction.type === 'boost' ? '🚀' : confirmAction.type === 'crypto_package' ? '💎' : '💳' }}
            </div>
            <h3 class="text-lg font-bold mb-1">{{ t('market.confirmPurchase.title') }}</h3>
            <p class="text-text-muted text-sm">{{ t('market.confirmPurchase.question') }}</p>
          </div>

          <div class="bg-bg-primary rounded-lg p-4 mb-4">
            <div class="font-medium text-white mb-1">{{ confirmAction.name }}</div>
            <div class="text-xs text-text-muted mb-2">{{ confirmAction.description }}</div>
            <div class="flex items-center justify-between">
              <span class="text-text-muted text-sm">{{ t('market.confirmPurchase.price') }}</span>
              <span class="font-bold" :class="confirmAction.currency === 'crypto' ? 'text-accent-primary' : confirmAction.currency === 'ron' ? 'text-blue-400' : 'text-status-warning'">
                {{ formatNumber(confirmAction.price) }} {{ confirmAction.currency === 'crypto' ? '💎' : confirmAction.currency === 'ron' ? 'RON' : '🪙' }}
              </span>
            </div>
            <template v-if="confirmAction.currency !== 'ron'">
              <div class="flex items-center justify-between mt-1">
                <span class="text-text-muted text-sm">{{ t('market.confirmPurchase.yourBalance') }}</span>
                <span
                  class="font-mono"
                  :class="(confirmAction.currency === 'crypto' ? cryptoBalance : balance) >= confirmAction.price ? 'text-status-success' : 'text-status-danger'"
                >
                  {{ confirmAction.currency === 'crypto' ? formatCrypto(cryptoBalance) : formatGamecoin(balance) }} {{ confirmAction.currency === 'crypto' ? '💎' : '🪙' }}
                </span>
              </div>
              <div class="flex items-center justify-between mt-1 pt-2 border-t border-border/50">
                <span class="text-text-muted text-sm">{{ t('market.confirmPurchase.after') }}</span>
                <span class="font-mono text-white">
                  {{ confirmAction.currency === 'crypto'
                    ? formatCrypto(cryptoBalance - confirmAction.price)
                    : formatGamecoin(balance - confirmAction.price) }} {{ confirmAction.currency === 'crypto' ? '💎' : '🪙' }}
                </span>
              </div>
            </template>
            <template v-else>
              <div class="mt-2 p-2 rounded bg-blue-500/10 border border-blue-500/30">
                <p class="text-xs text-blue-400 text-center">
                  {{ t('market.crypto.ronNote', 'Pago con RON en la red Ronin') }}
                </p>
              </div>
            </template>
          </div>

          <div class="flex gap-3">
            <button
              @click="cancelPurchase"
              class="flex-1 py-2.5 rounded-lg font-medium bg-bg-tertiary hover:bg-bg-tertiary/80 transition-colors"
            >
              {{ t('common.cancel') }}
            </button>
            <button
              @click="confirmPurchase"
              :disabled="buying"
              class="flex-1 py-2.5 rounded-lg font-medium bg-accent-primary text-white hover:bg-accent-primary/80 transition-colors disabled:opacity-50"
            >
              {{ buying ? t('market.confirmPurchase.buying') : t('common.confirm') }}
            </button>
          </div>
        </div>
      </div>

      <!-- Mobile Categories Popup -->
      <Transition name="modal">
        <div
          v-if="showMobileCategories"
          class="absolute inset-0 flex items-end justify-center bg-black/50 z-10 md:hidden"
          @click.self="showMobileCategories = false"
        >
          <div class="w-full bg-bg-secondary rounded-t-2xl p-4 animate-slide-up">
            <div class="flex items-center justify-between mb-4">
              <h3 class="font-bold">{{ t('market.filters.selectCategory', 'Categoría') }}</h3>
              <button
                @click="showMobileCategories = false"
                class="w-8 h-8 rounded-lg bg-bg-tertiary flex items-center justify-center"
              >
                <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>
            <div class="grid grid-cols-2 gap-2">
              <button
                @click="selectCategory('all')"
                class="flex items-center gap-3 px-4 py-3 rounded-xl text-left transition-colors"
                :class="activeFilter === 'all'
                  ? 'bg-accent-primary/20 text-accent-primary border border-accent-primary/30'
                  : 'bg-bg-tertiary hover:bg-bg-tertiary/80'"
              >
                <span class="text-xl">🏪</span>
                <span class="font-medium">{{ t('market.filters.all', 'Todos') }}</span>
              </button>
              <button
                @click="selectCategory('rigs')"
                class="flex items-center gap-3 px-4 py-3 rounded-xl text-left transition-colors"
                :class="activeFilter === 'rigs'
                  ? 'bg-accent-primary/20 text-accent-primary border border-accent-primary/30'
                  : 'bg-bg-tertiary hover:bg-bg-tertiary/80'"
              >
                <span class="text-xl">⛏️</span>
                <span class="font-medium">{{ t('market.tabs.rigs') }}</span>
              </button>
              <button
                @click="selectCategory('cooling')"
                class="flex items-center gap-3 px-4 py-3 rounded-xl text-left transition-colors"
                :class="activeFilter === 'cooling'
                  ? 'bg-cyan-500/20 text-cyan-400 border border-cyan-500/30'
                  : 'bg-bg-tertiary hover:bg-bg-tertiary/80'"
              >
                <span class="text-xl">❄️</span>
                <span class="font-medium">{{ t('market.tabs.cooling') }}</span>
              </button>
              <button
                @click="selectCategory('energy')"
                class="flex items-center gap-3 px-4 py-3 rounded-xl text-left transition-colors"
                :class="activeFilter === 'energy'
                  ? 'bg-amber-500/20 text-amber-400 border border-amber-500/30'
                  : 'bg-bg-tertiary hover:bg-bg-tertiary/80'"
              >
                <span class="text-xl">⚡</span>
                <span class="font-medium">{{ t('market.energy') }}</span>
              </button>
              <button
                @click="selectCategory('internet')"
                class="flex items-center gap-3 px-4 py-3 rounded-xl text-left transition-colors"
                :class="activeFilter === 'internet'
                  ? 'bg-cyan-500/20 text-cyan-400 border border-cyan-500/30'
                  : 'bg-bg-tertiary hover:bg-bg-tertiary/80'"
              >
                <span class="text-xl">📡</span>
                <span class="font-medium">{{ t('market.internet') }}</span>
              </button>
              <button
                @click="selectCategory('boosts')"
                class="flex items-center gap-3 px-4 py-3 rounded-xl text-left transition-colors"
                :class="activeFilter === 'boosts'
                  ? 'bg-purple-500/20 text-purple-400 border border-purple-500/30'
                  : 'bg-bg-tertiary hover:bg-bg-tertiary/80'"
              >
                <span class="text-xl">🚀</span>
                <span class="font-medium">{{ t('market.tabs.boosts') }}</span>
              </button>
              <button
                @click="selectCategory('crypto')"
                class="flex items-center gap-3 px-4 py-3 rounded-xl text-left transition-colors col-span-2"
                :class="activeFilter === 'crypto'
                  ? 'bg-gradient-to-r from-blue-500/20 to-purple-500/20 text-blue-400 border border-blue-500/30'
                  : 'bg-bg-tertiary hover:bg-bg-tertiary/80'"
              >
                <span class="text-xl">💎</span>
                <span class="font-medium">{{ t('market.tabs.crypto', 'Comprar Crypto') }}</span>
              </button>
            </div>
          </div>
        </div>
      </Transition>

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
            <h3 class="text-lg font-bold mb-2">
              {{ processingStep === 'connecting' ? t('market.wallet.connecting') :
                 processingStep === 'sending' ? t('market.wallet.sending') :
                 processingStep === 'confirming' ? t('market.wallet.confirming') :
                 processingStep === 'crediting' ? t('market.wallet.crediting') :
                 t('market.processing.title') }}
            </h3>
            <p class="text-text-muted text-sm">
              {{ processingStep === 'connecting' ? t('market.wallet.connectingDesc') :
                 processingStep === 'sending' ? t('market.wallet.sendingDesc') :
                 processingStep === 'confirming' ? t('market.wallet.confirmingDesc') :
                 processingStep === 'crediting' ? t('market.wallet.creditingDesc') :
                 t('market.processing.wait') }}
            </p>
            <!-- Wallet steps indicator -->
            <div v-if="processingStep" class="mt-4 flex justify-center gap-2">
              <div class="w-2 h-2 rounded-full" :class="processingStep ? 'bg-accent-primary' : 'bg-bg-tertiary'"></div>
              <div class="w-2 h-2 rounded-full" :class="['sending', 'confirming', 'crediting'].includes(processingStep) ? 'bg-accent-primary' : 'bg-bg-tertiary'"></div>
              <div class="w-2 h-2 rounded-full" :class="['confirming', 'crediting'].includes(processingStep) ? 'bg-accent-primary' : 'bg-bg-tertiary'"></div>
              <div class="w-2 h-2 rounded-full" :class="processingStep === 'crediting' ? 'bg-accent-primary' : 'bg-bg-tertiary'"></div>
            </div>
          </div>

          <!-- Success State -->
          <div v-else-if="processingStatus === 'success'" class="text-center">
            <div class="w-16 h-16 mx-auto mb-4 bg-status-success/20 rounded-full flex items-center justify-center">
              <svg class="w-8 h-8 text-status-success" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
              </svg>
            </div>
            <h3 class="text-lg font-bold text-status-success mb-2">{{ t('market.processing.success') }}</h3>
            <p class="text-text-muted text-sm mb-4">{{ t('market.processing.purchaseComplete') }}</p>
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
            <h3 class="text-lg font-bold text-status-danger mb-2">{{ t('market.processing.error') }}</h3>
            <p class="text-text-muted text-sm mb-4">{{ processingError }}</p>
            <div class="flex flex-col gap-2">
              <button
                v-if="processingError === t('market.wallet.notInstalled')"
                @click="roninWallet.openInstallPage()"
                class="w-full py-2.5 rounded-lg font-medium bg-blue-500/20 text-blue-400 hover:bg-blue-500/30 transition-colors"
              >
                {{ t('market.wallet.install') }}
              </button>
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
    </div>
  </Teleport>
</template>

<style scoped>
@keyframes slide-up {
  from {
    transform: translateY(100%);
  }
  to {
    transform: translateY(0);
  }
}

.animate-slide-up {
  animation: slide-up 0.3s ease-out;
}

.modal-enter-active,
.modal-leave-active {
  transition: opacity 0.3s ease;
}

.modal-enter-from,
.modal-leave-to {
  opacity: 0;
}
</style>
