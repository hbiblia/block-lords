<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAuthStore } from '@/stores/auth';
import { supabase } from '@/utils/supabase';
import { playSound } from '@/utils/sounds';

const { t } = useI18n();

const authStore = useAuthStore();

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

const loading = ref(false);
const buying = ref(false);
const activeFilter = ref<'all' | 'rigs' | 'cooling' | 'energy' | 'internet' | 'boosts'>('all');

// Confirmation dialog state
const showConfirm = ref(false);
const confirmAction = ref<{
  type: 'rig' | 'cooling' | 'card' | 'boost';
  id: string;
  name: string;
  price: number;
  description: string;
  currency: 'gamecoin' | 'crypto';
} | null>(null);

// Processing modal state
const showProcessingModal = ref(false);
const processingStatus = ref<'processing' | 'success' | 'error'>('processing');
const processingError = ref<string>('');

// Catálogos
const availableRigs = ref<Array<{
  id: string;
  name: string;
  description: string;
  hashrate: number;
  power_consumption: number;
  internet_consumption: number;
  repair_cost: number;
  tier: string;
  base_price: number;
}>>([]);

const coolingItems = ref<Array<{
  id: string;
  name: string;
  description: string;
  cooling_power: number;
  base_price: number;
  tier: string;
}>>([]);

const prepaidCards = ref<Array<{
  id: string;
  name: string;
  description: string;
  card_type: 'energy' | 'internet';
  amount: number;
  base_price: number;
  tier: string;
  currency: 'gamecoin' | 'crypto';
}>>([]);

// Rig quantities owned
const rigQuantities = ref<Record<string, number>>({});
// Cooling quantities: { item_id: { installed: number, inventory: number } }
const coolingQuantities = ref<Record<string, { installed: number; inventory: number }>>({});
// Card quantities in inventory
const cardQuantities = ref<Record<string, number>>({});
// Boost quantities in inventory
const boostQuantities = ref<Record<string, number>>({});

// Boost items catalog
const boostItems = ref<Array<{
  id: string;
  name: string;
  description: string;
  boost_type: string;
  effect_value: number;
  secondary_value: number;
  duration_minutes: number;
  base_price: number;
  currency: 'gamecoin' | 'crypto';
  tier: string;
}>>([]);

const balance = computed(() => authStore.player?.gamecoin_balance ?? 0);
const cryptoBalance = computed(() => authStore.player?.crypto_balance ?? 0);

// Rigs disponibles para mostrar (todos con precio > 0)
const rigsForSale = computed(() =>
  availableRigs.value.filter(r => r.base_price > 0)
);

function getRigOwned(id: string): number {
  return rigQuantities.value[id] || 0;
}

const energyCards = computed(() => prepaidCards.value.filter(c => c.card_type === 'energy'));
const internetCards = computed(() => prepaidCards.value.filter(c => c.card_type === 'internet'));

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

// Translation helpers for market items
function getRigName(id: string): string {
  const key = `market.items.rigs.${id}.name`;
  const translated = t(key);
  return translated !== key ? translated : id;
}

function getRigDescription(id: string): string {
  const key = `market.items.rigs.${id}.description`;
  const translated = t(key);
  return translated !== key ? translated : '';
}

function getCoolingName(id: string): string {
  const key = `market.items.cooling.${id}.name`;
  const translated = t(key);
  return translated !== key ? translated : id;
}

function getCoolingDescription(id: string): string {
  const key = `market.items.cooling.${id}.description`;
  const translated = t(key);
  return translated !== key ? translated : '';
}

function getCoolingOwned(id: string): { installed: number; inventory: number; total: number } {
  const q = coolingQuantities.value[id] || { installed: 0, inventory: 0 };
  return { ...q, total: q.installed + q.inventory };
}

function getCardOwned(id: string): number {
  return cardQuantities.value[id] || 0;
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

function getBoostDescription(id: string): string {
  const key = `market.items.boosts.${id}.description`;
  const translated = t(key);
  return translated !== key ? translated : '';
}

function getBoostOwned(id: string): number {
  return boostQuantities.value[id] || 0;
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

function formatBoostEffect(boost: typeof boostItems.value[0]): string {
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

function canAffordBoost(boost: typeof boostItems.value[0]): boolean {
  if (boost.currency === 'crypto') {
    return cryptoBalance.value >= boost.base_price;
  }
  return balance.value >= boost.base_price;
}

async function loadData() {
  loading.value = true;
  try {
    // Cargar rigs disponibles
    const { data: rigs } = await supabase
      .from('rigs')
      .select('*')
      .order('base_price', { ascending: true });
    availableRigs.value = rigs ?? [];

    // Cargar cooling items
    const { data: cooling } = await supabase
      .from('cooling_items')
      .select('*')
      .order('base_price', { ascending: true });
    coolingItems.value = cooling ?? [];

    // Cargar tarjetas prepago
    const { data: cards } = await supabase
      .from('prepaid_cards')
      .select('*')
      .order('base_price', { ascending: true });
    prepaidCards.value = cards ?? [];

    // Cargar rigs del jugador
    if (authStore.player) {
      const { data: playerRigs } = await supabase
        .from('player_rigs')
        .select('rig_id')
        .eq('player_id', authStore.player.id);

      // Build rig quantities map
      const rigQty: Record<string, number> = {};
      for (const r of playerRigs ?? []) {
        rigQty[r.rig_id] = (rigQty[r.rig_id] || 0) + 1;
      }
      rigQuantities.value = rigQty;

      // Cooling instalado
      const { data: playerCooling } = await supabase
        .from('player_cooling')
        .select('cooling_item_id')
        .eq('player_id', authStore.player.id);

      // Cooling en inventario
      const { data: inventoryCooling } = await supabase
        .from('player_inventory')
        .select('item_id, quantity')
        .eq('player_id', authStore.player.id)
        .eq('item_type', 'cooling');

      // Build cooling quantities map
      const quantities: Record<string, { installed: number; inventory: number }> = {};
      for (const c of playerCooling ?? []) {
        if (!quantities[c.cooling_item_id]) {
          quantities[c.cooling_item_id] = { installed: 0, inventory: 0 };
        }
        quantities[c.cooling_item_id].installed++;
      }
      for (const c of inventoryCooling ?? []) {
        if (!quantities[c.item_id]) {
          quantities[c.item_id] = { installed: 0, inventory: 0 };
        }
        quantities[c.item_id].inventory += c.quantity || 1;
      }
      coolingQuantities.value = quantities;

      // Cards in inventory
      const { data: inventoryCards } = await supabase
        .from('player_prepaid_cards')
        .select('card_id')
        .eq('player_id', authStore.player.id)
        .eq('is_redeemed', false);

      const cardQty: Record<string, number> = {};
      for (const c of inventoryCards ?? []) {
        cardQty[c.card_id] = (cardQty[c.card_id] || 0) + 1;
      }
      cardQuantities.value = cardQty;

      // Boosts in inventory
      const { data: inventoryBoosts } = await supabase
        .from('player_boosts')
        .select('boost_id, quantity')
        .eq('player_id', authStore.player.id);

      const boostQty: Record<string, number> = {};
      for (const b of inventoryBoosts ?? []) {
        boostQty[b.boost_id] = (boostQty[b.boost_id] || 0) + (b.quantity || 1);
      }
      boostQuantities.value = boostQty;
    }

    // Load boost items catalog
    const { data: boosts } = await supabase
      .from('boost_items')
      .select('*')
      .order('boost_type', { ascending: true })
      .order('base_price', { ascending: true });
    boostItems.value = boosts ?? [];
  } catch (e) {
    console.error('Error loading market data:', e);
  } finally {
    loading.value = false;
  }
}

function requestBuyRig(rig: typeof availableRigs.value[0]) {
  confirmAction.value = {
    type: 'rig',
    id: rig.id,
    name: getRigName(rig.id),
    price: rig.base_price,
    description: `${rig.hashrate.toLocaleString()} H/s - ${rig.tier}`,
    currency: 'gamecoin',
  };
  showConfirm.value = true;
}

async function buyRig(rigId: string) {
  if (!authStore.player) return;
  buying.value = true;
  showProcessingModal.value = true;
  processingStatus.value = 'processing';
  processingError.value = '';

  try {
    const { data, error } = await supabase.rpc('buy_rig', {
      p_player_id: authStore.player.id,
      p_rig_id: rigId,
    });

    if (error) throw error;

    if (data?.success) {
      await loadData();
      await authStore.fetchPlayer();
      processingStatus.value = 'success';
      playSound('purchase');
      emit('purchased');
    } else {
      processingStatus.value = 'error';
      processingError.value = data?.error ?? t('market.processing.errorBuyingRig');
      playSound('error');
    }
  } catch (e) {
    console.error('Error buying rig:', e);
    processingStatus.value = 'error';
    processingError.value = t('market.processing.errorBuyingRig');
    playSound('error');
  } finally {
    buying.value = false;
  }
}

function requestBuyCooling(item: typeof coolingItems.value[0]) {
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
  buying.value = true;
  showProcessingModal.value = true;
  processingStatus.value = 'processing';
  processingError.value = '';

  try {
    const { data, error } = await supabase.rpc('buy_cooling', {
      p_player_id: authStore.player.id,
      p_cooling_id: coolingId,
    });

    if (error) throw error;

    if (data?.success) {
      await loadData();
      await authStore.fetchPlayer();
      processingStatus.value = 'success';
      playSound('purchase');
      emit('purchased');
    } else {
      processingStatus.value = 'error';
      processingError.value = data?.error ?? t('market.processing.errorBuyingCooling');
      playSound('error');
    }
  } catch (e) {
    console.error('Error buying cooling:', e);
    processingStatus.value = 'error';
    processingError.value = t('market.processing.errorBuyingCooling');
    playSound('error');
  } finally {
    buying.value = false;
  }
}

function requestBuyCard(card: typeof prepaidCards.value[0]) {
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
  buying.value = true;
  showProcessingModal.value = true;
  processingStatus.value = 'processing';
  processingError.value = '';

  try {
    const { data, error } = await supabase.rpc('buy_prepaid_card', {
      p_player_id: authStore.player.id,
      p_card_id: cardId,
    });

    if (error) throw error;

    if (data?.success) {
      await loadData();
      await authStore.fetchPlayer();
      processingStatus.value = 'success';
      playSound('purchase');
      emit('purchased');
    } else {
      processingStatus.value = 'error';
      processingError.value = data?.error ?? t('market.processing.errorBuyingCard');
      playSound('error');
    }
  } catch (e) {
    console.error('Error buying card:', e);
    processingStatus.value = 'error';
    processingError.value = t('market.processing.errorBuyingCard');
    playSound('error');
  } finally {
    buying.value = false;
  }
}

function requestBuyBoost(boost: typeof boostItems.value[0]) {
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
  buying.value = true;
  showProcessingModal.value = true;
  processingStatus.value = 'processing';
  processingError.value = '';

  try {
    const { data, error } = await supabase.rpc('buy_boost', {
      p_player_id: authStore.player.id,
      p_boost_id: boostId,
    });

    if (error) throw error;

    if (data?.success) {
      await loadData();
      await authStore.fetchPlayer();
      processingStatus.value = 'success';
      playSound('purchase');
      emit('purchased');
    } else {
      processingStatus.value = 'error';
      processingError.value = data?.error ?? t('market.processing.errorBuyingBoost');
      playSound('error');
    }
  } catch (e) {
    console.error('Error buying boost:', e);
    processingStatus.value = 'error';
    processingError.value = t('market.processing.errorBuyingBoost');
    playSound('error');
  } finally {
    buying.value = false;
  }
}

function closeProcessingModal() {
  showProcessingModal.value = false;
  processingStatus.value = 'processing';
  processingError.value = '';
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
              <span class="font-bold text-status-warning">{{ balance.toFixed(0) }} 🪙</span>
              <span class="font-bold text-accent-primary">{{ cryptoBalance.toFixed(2) }} 💎</span>
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
          <!-- Sidebar Filters -->
          <div class="w-40 border-r border-border/50 p-2 flex flex-col gap-1 shrink-0">
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
                    <span class="font-mono font-bold text-accent-primary">{{ rig.hashrate.toLocaleString() }} H/s</span>
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
                      {{ buying ? '...' : `${rig.base_price.toLocaleString()} 🪙` }}
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
                      {{ buying ? '...' : `${item.base_price.toLocaleString()} 🪙` }}
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
                      {{ buying ? '...' : `${card.base_price} ${card.currency === 'crypto' ? '💎' : '🪙'}` }}
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
                      {{ buying ? '...' : `${card.base_price} ${card.currency === 'crypto' ? '💎' : '🪙'}` }}
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

                  <div class="flex items-center justify-between mb-2">
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
                      {{ buying ? '...' : `${boost.base_price} ${boost.currency === 'crypto' ? '💎' : '🪙'}` }}
                    </button>
                  </div>
                </div>
              </template>
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
              {{ confirmAction.type === 'rig' ? '⛏️' : confirmAction.type === 'cooling' ? '❄️' : confirmAction.type === 'boost' ? '🚀' : '💳' }}
            </div>
            <h3 class="text-lg font-bold mb-1">{{ t('market.confirmPurchase.title') }}</h3>
            <p class="text-text-muted text-sm">{{ t('market.confirmPurchase.question') }}</p>
          </div>

          <div class="bg-bg-primary rounded-lg p-4 mb-4">
            <div class="font-medium text-white mb-1">{{ confirmAction.name }}</div>
            <div class="text-xs text-text-muted mb-2">{{ confirmAction.description }}</div>
            <div class="flex items-center justify-between">
              <span class="text-text-muted text-sm">{{ t('market.confirmPurchase.price') }}</span>
              <span class="font-bold" :class="confirmAction.currency === 'crypto' ? 'text-accent-primary' : 'text-status-warning'">
                {{ confirmAction.price.toLocaleString() }} {{ confirmAction.currency === 'crypto' ? '💎' : '🪙' }}
              </span>
            </div>
            <div class="flex items-center justify-between mt-1">
              <span class="text-text-muted text-sm">{{ t('market.confirmPurchase.yourBalance') }}</span>
              <span
                class="font-mono"
                :class="(confirmAction.currency === 'crypto' ? cryptoBalance : balance) >= confirmAction.price ? 'text-status-success' : 'text-status-danger'"
              >
                {{ confirmAction.currency === 'crypto' ? cryptoBalance.toFixed(2) : balance.toFixed(0) }} {{ confirmAction.currency === 'crypto' ? '💎' : '🪙' }}
              </span>
            </div>
            <div class="flex items-center justify-between mt-1 pt-2 border-t border-border/50">
              <span class="text-text-muted text-sm">{{ t('market.confirmPurchase.after') }}</span>
              <span class="font-mono text-white">
                {{ confirmAction.currency === 'crypto'
                  ? (cryptoBalance - confirmAction.price).toFixed(2)
                  : (balance - confirmAction.price).toFixed(0) }} {{ confirmAction.currency === 'crypto' ? '💎' : '🪙' }}
              </span>
            </div>
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
            <h3 class="text-lg font-bold mb-2">{{ t('market.processing.title') }}</h3>
            <p class="text-text-muted text-sm">{{ t('market.processing.wait') }}</p>
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
