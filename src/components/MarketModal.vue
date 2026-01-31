<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAuthStore } from '@/stores/auth';
import { supabase } from '@/utils/supabase';

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
const activeTab = ref<'rigs' | 'cooling' | 'cards'>('rigs');

// Confirmation dialog state
const showConfirm = ref(false);
const confirmAction = ref<{
  type: 'rig' | 'cooling' | 'card';
  id: string;
  name: string;
  price: number;
  description: string;
} | null>(null);

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
}>>([]);

// Rigs que ya tiene el jugador
const playerRigIds = ref<string[]>([]);
// Cooling que ya tiene el jugador (instalado)
const playerCoolingIds = ref<string[]>([]);
// Cooling en inventario (comprado pero no instalado)
const inventoryCoolingIds = ref<string[]>([]);

const balance = computed(() => authStore.player?.gamecoin_balance ?? 0);

// Filtrar rigs disponibles (que no tiene)
const rigsForSale = computed(() =>
  availableRigs.value.filter(r => r.base_price > 0 && !playerRigIds.value.includes(r.id))
);

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
      playerRigIds.value = (playerRigs ?? []).map(r => r.rig_id);

      // Cooling instalado
      const { data: playerCooling } = await supabase
        .from('player_cooling')
        .select('cooling_item_id')
        .eq('player_id', authStore.player.id);
      playerCoolingIds.value = (playerCooling ?? []).map(c => c.cooling_item_id);

      // Cooling en inventario
      const { data: inventoryCooling } = await supabase
        .from('player_inventory')
        .select('item_id')
        .eq('player_id', authStore.player.id)
        .eq('item_type', 'cooling');
      inventoryCoolingIds.value = (inventoryCooling ?? []).map(c => c.item_id);
    }
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
    name: rig.name,
    price: rig.base_price,
    description: `${rig.hashrate.toLocaleString()} H/s - ${rig.tier}`,
  };
  showConfirm.value = true;
}

async function buyRig(rigId: string) {
  if (!authStore.player) return;
  buying.value = true;

  try {
    const { data, error } = await supabase.rpc('buy_rig', {
      p_player_id: authStore.player.id,
      p_rig_id: rigId,
    });

    if (error) throw error;

    if (data?.success) {
      await loadData();
      await authStore.fetchPlayer();
      emit('purchased');
    } else {
      alert(data?.error ?? 'Error al comprar rig');
    }
  } catch (e) {
    console.error('Error buying rig:', e);
    alert('Error al comprar rig');
  } finally {
    buying.value = false;
  }
}

function requestBuyCooling(item: typeof coolingItems.value[0]) {
  confirmAction.value = {
    type: 'cooling',
    id: item.id,
    name: item.name,
    price: item.base_price,
    description: `-${item.cooling_power}°C refrigeracion - ${item.tier}`,
  };
  showConfirm.value = true;
}

async function buyCooling(coolingId: string) {
  if (!authStore.player) return;
  buying.value = true;

  try {
    const { data, error } = await supabase.rpc('buy_cooling', {
      p_player_id: authStore.player.id,
      p_cooling_id: coolingId,
    });

    if (error) throw error;

    if (data?.success) {
      await loadData();
      await authStore.fetchPlayer();
      emit('purchased');
    } else {
      alert(data?.error ?? 'Error al comprar refrigeración');
    }
  } catch (e) {
    console.error('Error buying cooling:', e);
    alert('Error al comprar refrigeración');
  } finally {
    buying.value = false;
  }
}

function requestBuyCard(card: typeof prepaidCards.value[0]) {
  confirmAction.value = {
    type: 'card',
    id: card.id,
    name: card.name,
    price: card.base_price,
    description: `+${card.amount}% ${card.card_type === 'energy' ? 'Energia' : 'Internet'}`,
  };
  showConfirm.value = true;
}

async function buyCard(cardId: string) {
  if (!authStore.player) return;
  buying.value = true;

  try {
    const { data, error } = await supabase.rpc('buy_prepaid_card', {
      p_player_id: authStore.player.id,
      p_card_id: cardId,
    });

    if (error) throw error;

    if (data?.success) {
      await loadData();
      await authStore.fetchPlayer();
      emit('purchased');
    } else {
      alert(data?.error ?? 'Error al comprar tarjeta');
    }
  } catch (e) {
    console.error('Error buying card:', e);
    alert('Error al comprar tarjeta');
  } finally {
    buying.value = false;
  }
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
      <div class="relative w-full max-w-4xl max-h-[90vh] overflow-hidden card animate-fade-in">
        <!-- Header -->
        <div class="flex items-center justify-between p-4 border-b border-border/50">
          <h2 class="text-xl font-display font-bold">
            <span class="gradient-text">{{ t('market.title') }}</span>
          </h2>
          <div class="flex items-center gap-4">
            <span class="text-sm text-text-muted">
              {{ t('market.balance') }} <span class="font-bold text-status-warning">{{ balance.toFixed(0) }} 🪙</span>
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

        <!-- Tabs -->
        <div class="flex border-b border-border/50">
          <button
            @click="activeTab = 'rigs'"
            class="flex-1 px-4 py-3 text-sm font-medium transition-colors flex items-center justify-center gap-2"
            :class="activeTab === 'rigs'
              ? 'text-accent-primary border-b-2 border-accent-primary'
              : 'text-text-muted hover:text-white'"
          >
            <span>⛏️</span> {{ t('market.tabs.rigs') }}
          </button>
          <button
            @click="activeTab = 'cooling'"
            class="flex-1 px-4 py-3 text-sm font-medium transition-colors flex items-center justify-center gap-2"
            :class="activeTab === 'cooling'
              ? 'text-accent-primary border-b-2 border-accent-primary'
              : 'text-text-muted hover:text-white'"
          >
            <span>❄️</span> {{ t('market.tabs.cooling') }}
          </button>
          <button
            @click="activeTab = 'cards'"
            class="flex-1 px-4 py-3 text-sm font-medium transition-colors flex items-center justify-center gap-2"
            :class="activeTab === 'cards'
              ? 'text-accent-primary border-b-2 border-accent-primary'
              : 'text-text-muted hover:text-white'"
          >
            <span>💳</span> {{ t('market.tabs.cards') }}
          </button>
        </div>

        <!-- Content -->
        <div class="p-4 overflow-y-auto max-h-[65vh]">
          <!-- Loading -->
          <div v-if="loading" class="text-center py-12 text-text-muted">
            {{ t('common.loading') }}
          </div>

          <!-- Rigs Tab -->
          <div v-else-if="activeTab === 'rigs'" class="space-y-4">
            <p class="text-sm text-text-muted mb-4">
              {{ t('market.rigs.description') }}
            </p>

            <div v-if="rigsForSale.length === 0" class="text-center py-8 text-text-muted">
              <div class="text-4xl mb-3">🎉</div>
              <p>{{ t('market.rigs.allOwned') }}</p>
            </div>

            <div v-else class="grid sm:grid-cols-2 gap-4">
              <div
                v-for="rig in rigsForSale"
                :key="rig.id"
                class="bg-bg-secondary rounded-xl p-4 border transition-all hover:scale-[1.02]"
                :class="getTierBorder(rig.tier)"
              >
                <div class="flex items-start justify-between mb-3">
                  <div>
                    <h3 class="font-medium flex items-center gap-2">
                      <span class="text-xl">⛏️</span>
                      {{ rig.name }}
                    </h3>
                    <span
                      class="text-xs uppercase tracking-wider"
                      :class="getTierColor(rig.tier)"
                    >
                      {{ rig.tier }}
                    </span>
                  </div>
                  <span class="text-lg font-bold text-accent-primary">
                    {{ rig.hashrate.toLocaleString() }} H/s
                  </span>
                </div>

                <p class="text-xs text-text-muted mb-3">{{ rig.description }}</p>

                <div class="grid grid-cols-3 gap-2 text-xs mb-4">
                  <div class="bg-bg-primary rounded-lg p-2 text-center">
                    <div class="text-status-warning">⚡ {{ rig.power_consumption }}</div>
                    <div class="text-text-muted">{{ t('market.rigs.energyTick') }}</div>
                  </div>
                  <div class="bg-bg-primary rounded-lg p-2 text-center">
                    <div class="text-accent-tertiary">📡 {{ rig.internet_consumption }}</div>
                    <div class="text-text-muted">{{ t('market.rigs.internetTick') }}</div>
                  </div>
                  <div class="bg-bg-primary rounded-lg p-2 text-center">
                    <div class="text-status-danger">🔧 {{ rig.repair_cost }}</div>
                    <div class="text-text-muted">{{ t('market.rigs.repair') }}</div>
                  </div>
                </div>

                <button
                  @click="requestBuyRig(rig)"
                  class="w-full py-2.5 rounded-lg font-medium transition-all"
                  :class="balance >= rig.base_price
                    ? 'bg-accent-primary/20 text-accent-primary hover:bg-accent-primary/30'
                    : 'bg-bg-tertiary text-text-muted cursor-not-allowed'"
                  :disabled="buying || balance < rig.base_price"
                >
                  {{ buying ? '...' : `${rig.base_price.toLocaleString()} 🪙` }}
                </button>
              </div>
            </div>
          </div>

          <!-- Cooling Tab -->
          <div v-else-if="activeTab === 'cooling'" class="space-y-4">
            <p class="text-sm text-text-muted mb-4">
              {{ t('market.cooling.description') }}
            </p>

            <div class="grid sm:grid-cols-2 gap-4">
              <div
                v-for="item in coolingItems"
                :key="item.id"
                class="bg-bg-secondary rounded-xl p-4 border transition-all hover:scale-[1.02]"
                :class="[
                  getTierBorder(item.tier),
                  playerCoolingIds.includes(item.id) ? 'opacity-50' : ''
                ]"
              >
                <div class="flex items-start justify-between mb-3">
                  <div>
                    <h3 class="font-medium flex items-center gap-2">
                      <span class="text-xl">❄️</span>
                      {{ item.name }}
                    </h3>
                    <span
                      class="text-xs uppercase tracking-wider"
                      :class="getTierColor(item.tier)"
                    >
                      {{ item.tier }}
                    </span>
                  </div>
                  <span class="text-lg font-bold text-cyan-400">
                    -{{ item.cooling_power }}°C
                  </span>
                </div>

                <p class="text-xs text-text-muted mb-4">{{ item.description }}</p>

                <button
                  v-if="playerCoolingIds.includes(item.id)"
                  class="w-full py-2.5 rounded-lg font-medium bg-status-success/20 text-status-success cursor-default"
                  disabled
                >
                  ✓ {{ t('market.cooling.installed') }}
                </button>
                <button
                  v-else-if="inventoryCoolingIds.includes(item.id)"
                  class="w-full py-2.5 rounded-lg font-medium bg-accent-primary/20 text-accent-primary cursor-default"
                  disabled
                >
                  🎒 {{ t('market.cooling.inInventory') }}
                </button>
                <button
                  v-else
                  @click="requestBuyCooling(item)"
                  class="w-full py-2.5 rounded-lg font-medium transition-all"
                  :class="balance >= item.base_price
                    ? 'bg-cyan-500/20 text-cyan-400 hover:bg-cyan-500/30'
                    : 'bg-bg-tertiary text-text-muted cursor-not-allowed'"
                  :disabled="buying || balance < item.base_price"
                >
                  {{ buying ? '...' : `${item.base_price.toLocaleString()} 🪙` }}
                </button>
              </div>
            </div>
          </div>

          <!-- Cards Tab -->
          <div v-else-if="activeTab === 'cards'" class="space-y-6">
            <p class="text-sm text-text-muted mb-4">
              {{ t('market.cards.description') }}
            </p>

            <!-- Energy Cards -->
            <div>
              <h3 class="text-sm font-medium text-text-muted mb-3 flex items-center gap-2">
                <span class="text-status-warning">⚡</span> {{ t('market.cards.energyCards') }}
              </h3>
              <div class="grid sm:grid-cols-2 gap-3">
                <div
                  v-for="card in energyCards"
                  :key="card.id"
                  class="bg-bg-secondary rounded-xl p-4 border border-border/50 hover:border-status-warning/50 transition-colors"
                >
                  <div class="flex items-center justify-between mb-2">
                    <span class="font-medium">{{ card.name }}</span>
                    <span class="text-status-warning font-bold">+{{ card.amount }}%</span>
                  </div>
                  <p class="text-xs text-text-muted mb-3">{{ card.description }}</p>
                  <button
                    @click="requestBuyCard(card)"
                    class="w-full py-2 rounded-lg font-medium transition-all"
                    :class="balance >= card.base_price
                      ? 'bg-status-warning/20 text-status-warning hover:bg-status-warning/30'
                      : 'bg-bg-tertiary text-text-muted cursor-not-allowed'"
                    :disabled="buying || balance < card.base_price"
                  >
                    {{ buying ? '...' : `${card.base_price} 🪙` }}
                  </button>
                </div>
              </div>
            </div>

            <!-- Internet Cards -->
            <div>
              <h3 class="text-sm font-medium text-text-muted mb-3 flex items-center gap-2">
                <span class="text-accent-tertiary">📡</span> {{ t('market.cards.internetCards') }}
              </h3>
              <div class="grid sm:grid-cols-2 gap-3">
                <div
                  v-for="card in internetCards"
                  :key="card.id"
                  class="bg-bg-secondary rounded-xl p-4 border border-border/50 hover:border-accent-tertiary/50 transition-colors"
                >
                  <div class="flex items-center justify-between mb-2">
                    <span class="font-medium">{{ card.name }}</span>
                    <span class="text-accent-tertiary font-bold">+{{ card.amount }}%</span>
                  </div>
                  <p class="text-xs text-text-muted mb-3">{{ card.description }}</p>
                  <button
                    @click="requestBuyCard(card)"
                    class="w-full py-2 rounded-lg font-medium transition-all"
                    :class="balance >= card.base_price
                      ? 'bg-accent-tertiary/20 text-accent-tertiary hover:bg-accent-tertiary/30'
                      : 'bg-bg-tertiary text-text-muted cursor-not-allowed'"
                    :disabled="buying || balance < card.base_price"
                  >
                    {{ buying ? '...' : `${card.base_price} 🪙` }}
                  </button>
                </div>
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
              {{ confirmAction.type === 'rig' ? '⛏️' : confirmAction.type === 'cooling' ? '❄️' : '💳' }}
            </div>
            <h3 class="text-lg font-bold mb-1">{{ t('market.confirmPurchase.title') }}</h3>
            <p class="text-text-muted text-sm">{{ t('market.confirmPurchase.question') }}</p>
          </div>

          <div class="bg-bg-primary rounded-lg p-4 mb-4">
            <div class="font-medium text-white mb-1">{{ confirmAction.name }}</div>
            <div class="text-xs text-text-muted mb-2">{{ confirmAction.description }}</div>
            <div class="flex items-center justify-between">
              <span class="text-text-muted text-sm">{{ t('market.confirmPurchase.price') }}</span>
              <span class="font-bold text-status-warning">{{ confirmAction.price.toLocaleString() }} 🪙</span>
            </div>
            <div class="flex items-center justify-between mt-1">
              <span class="text-text-muted text-sm">{{ t('market.confirmPurchase.yourBalance') }}</span>
              <span class="font-mono" :class="balance >= confirmAction.price ? 'text-status-success' : 'text-status-danger'">
                {{ balance.toFixed(0) }} 🪙
              </span>
            </div>
            <div class="flex items-center justify-between mt-1 pt-2 border-t border-border/50">
              <span class="text-text-muted text-sm">{{ t('market.confirmPurchase.after') }}</span>
              <span class="font-mono text-white">{{ (balance - confirmAction.price).toFixed(0) }} 🪙</span>
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
    </div>
  </Teleport>
</template>
