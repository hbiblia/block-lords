<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAuthStore } from '@/stores/auth';
import { getPrepaidCards, getPlayerCards, buyPrepaidCard, redeemPrepaidCard } from '@/utils/api';

const { t } = useI18n();
const authStore = useAuthStore();

// Translation helpers for card names
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

const props = defineProps<{
  show: boolean;
}>();

const emit = defineEmits<{
  close: [];
  redeemed: [type: string, amount: number];
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
const activeTab = ref<'my-cards' | 'buy'>('my-cards');

// Tarjetas disponibles para comprar
const availableCards = ref<Array<{
  id: string;
  name: string;
  description: string;
  card_type: 'energy' | 'internet';
  amount: number;
  base_price: number;
  tier: string;
  currency: 'gamecoin' | 'crypto';
}>>([]);

// Tarjetas del jugador
const playerCards = ref<Array<{
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
}>>([]);

// Para canjear tarjeta
const redeemCode = ref('');
const redeemError = ref('');
const redeemSuccess = ref('');
const redeeming = ref(false);

// Para comprar tarjeta
const buying = ref(false);

const unredeemedCards = computed(() => playerCards.value.filter(c => !c.is_redeemed));

const energyCards = computed(() => availableCards.value.filter(c => c.card_type === 'energy'));
const internetCards = computed(() => availableCards.value.filter(c => c.card_type === 'internet'));

async function loadData() {
  loading.value = true;
  try {
    const [cards, myCards] = await Promise.all([
      getPrepaidCards(),
      getPlayerCards(authStore.player!.id),
    ]);
    availableCards.value = cards ?? [];
    playerCards.value = myCards ?? [];
  } catch (e) {
    console.error('Error loading cards:', e);
  } finally {
    loading.value = false;
  }
}

async function handleBuyCard(cardId: string) {
  buying.value = true;
  try {
    const result = await buyPrepaidCard(authStore.player!.id, cardId);
    if (result.success) {
      // Recargar datos
      await loadData();
      await authStore.fetchPlayer();
      // Cambiar a pestaña de mis tarjetas
      activeTab.value = 'my-cards';
    } else {
      alert(result.error ?? 'Error al comprar tarjeta');
    }
  } catch (e) {
    console.error('Error buying card:', e);
    alert('Error al comprar tarjeta');
  } finally {
    buying.value = false;
  }
}

async function handleRedeem() {
  if (!redeemCode.value.trim()) {
    redeemError.value = 'Ingresa un código';
    return;
  }

  redeemError.value = '';
  redeemSuccess.value = '';
  redeeming.value = true;

  try {
    const result = await redeemPrepaidCard(authStore.player!.id, redeemCode.value);
    if (result.success) {
      redeemSuccess.value = `+${result.amount} ${result.card_type === 'energy' ? 'Energía' : 'Internet'}`;
      redeemCode.value = '';
      await loadData();
      await authStore.fetchPlayer();
      emit('redeemed', result.card_type, result.amount);

      // Limpiar mensaje después de 3 segundos
      setTimeout(() => {
        redeemSuccess.value = '';
      }, 3000);
    } else {
      redeemError.value = result.error ?? 'Código inválido';
    }
  } catch (e) {
    redeemError.value = 'Error al canjear tarjeta';
  } finally {
    redeeming.value = false;
  }
}

function copyCode(code: string) {
  navigator.clipboard.writeText(code);
}

function formatCode(code: string): string {
  return code; // Ya viene formateado XXXX-XXXX-XXXX
}

onMounted(() => {
  if (props.show) {
    loadData();
  }
});

// Recargar cuando se muestra
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
      <div class="relative w-full max-w-2xl max-h-[85vh] overflow-hidden card animate-fade-in">
        <!-- Header -->
        <div class="flex items-center justify-between p-4 border-b border-border/50">
          <h2 class="text-xl font-display font-bold">
            <span class="gradient-text">Tarjetas Prepago</span>
          </h2>
          <button
            @click="emit('close')"
            class="w-8 h-8 rounded-lg bg-bg-tertiary hover:bg-bg-secondary flex items-center justify-center transition-colors"
          >
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        <!-- Tabs -->
        <div class="flex border-b border-border/50">
          <button
            @click="activeTab = 'my-cards'"
            class="flex-1 px-4 py-3 text-sm font-medium transition-colors"
            :class="activeTab === 'my-cards'
              ? 'text-accent-primary border-b-2 border-accent-primary'
              : 'text-text-muted hover:text-white'"
          >
            Mis Tarjetas ({{ unredeemedCards.length }})
          </button>
          <button
            @click="activeTab = 'buy'"
            class="flex-1 px-4 py-3 text-sm font-medium transition-colors"
            :class="activeTab === 'buy'
              ? 'text-accent-primary border-b-2 border-accent-primary'
              : 'text-text-muted hover:text-white'"
          >
            Comprar Tarjetas
          </button>
        </div>

        <!-- Content -->
        <div class="p-4 overflow-y-auto max-h-[60vh]">
          <!-- Loading -->
          <div v-if="loading" class="text-center py-12 text-text-muted">
            Cargando...
          </div>

          <!-- My Cards Tab -->
          <div v-else-if="activeTab === 'my-cards'" class="space-y-4">
            <!-- Redeem Form -->
            <div class="bg-bg-secondary rounded-xl p-4">
              <h3 class="text-sm font-medium mb-3">Canjear Código</h3>
              <div class="flex gap-2">
                <input
                  v-model="redeemCode"
                  type="text"
                  placeholder="XXXX-XXXX-XXXX"
                  class="input flex-1 font-mono text-center uppercase tracking-wider"
                  maxlength="14"
                  :disabled="redeeming"
                  @keyup.enter="handleRedeem"
                />
                <button
                  @click="handleRedeem"
                  class="btn-primary px-6"
                  :disabled="redeeming"
                >
                  {{ redeeming ? '...' : 'Canjear' }}
                </button>
              </div>
              <p v-if="redeemError" class="text-status-danger text-sm mt-2">{{ redeemError }}</p>
              <p v-if="redeemSuccess" class="text-status-success text-sm mt-2 font-bold">{{ redeemSuccess }}</p>
            </div>

            <!-- Unredeemed Cards -->
            <div v-if="unredeemedCards.length > 0">
              <h3 class="text-sm font-medium text-text-muted mb-3">Tarjetas Disponibles</h3>
              <div class="grid gap-3">
                <div
                  v-for="card in unredeemedCards"
                  :key="card.id"
                  class="bg-bg-secondary rounded-xl p-4 border-l-4"
                  :class="card.card_type === 'energy' ? 'border-status-warning' : 'border-accent-tertiary'"
                >
                  <div class="flex items-center justify-between mb-2">
                    <div class="flex items-center gap-2">
                      <span class="text-xl">{{ card.card_type === 'energy' ? '⚡' : '📡' }}</span>
                      <span class="font-medium">{{ getCardName(card.card_id) }}</span>
                    </div>
                    <span
                      class="text-lg font-bold"
                      :class="card.card_type === 'energy' ? 'text-status-warning' : 'text-accent-tertiary'"
                    >
                      +{{ card.amount }}
                    </span>
                  </div>
                  <div class="flex items-center justify-between">
                    <div
                      class="font-mono text-sm bg-bg-primary px-3 py-1.5 rounded-lg select-all cursor-pointer"
                      @click="copyCode(card.code)"
                      title="Click para copiar"
                    >
                      {{ formatCode(card.code) }}
                    </div>
                    <button
                      @click="redeemCode = card.code; handleRedeem()"
                      class="text-xs px-3 py-1.5 rounded-lg bg-status-success/20 text-status-success hover:bg-status-success/30 transition-colors"
                    >
                      Usar Ahora
                    </button>
                  </div>
                </div>
              </div>
            </div>

            <div v-else class="text-center py-8 text-text-muted">
              <div class="text-4xl mb-3">🎴</div>
              <p>No tienes tarjetas disponibles</p>
              <button
                @click="activeTab = 'buy'"
                class="text-accent-primary hover:underline mt-2"
              >
                Comprar tarjetas
              </button>
            </div>
          </div>

          <!-- Buy Cards Tab -->
          <div v-else-if="activeTab === 'buy'" class="space-y-6">
            <!-- Energy Cards -->
            <div>
              <h3 class="text-sm font-medium text-text-muted mb-3 flex items-center gap-2">
                <span class="text-status-warning">⚡</span> Tarjetas de Energía
              </h3>
              <div class="grid sm:grid-cols-2 gap-3">
                <div
                  v-for="card in energyCards"
                  :key="card.id"
                  class="bg-bg-secondary rounded-xl p-4 border border-border/50 hover:border-status-warning/50 transition-colors"
                  :class="card.tier === 'elite' ? 'ring-1 ring-accent-primary/50' : ''"
                >
                  <div class="flex items-center justify-between mb-2">
                    <div class="flex items-center gap-2">
                      <span class="font-medium">{{ getCardName(card.id) }}</span>
                      <span v-if="card.tier === 'elite'" class="text-xs px-1.5 py-0.5 rounded bg-accent-primary/20 text-accent-primary">ELITE</span>
                    </div>
                    <span class="text-status-warning font-bold">+{{ card.amount }}</span>
                  </div>
                  <p class="text-xs text-text-muted mb-3">{{ getCardDescription(card.id) }}</p>
                  <button
                    @click="handleBuyCard(card.id)"
                    class="w-full py-2 rounded-lg bg-status-warning/20 text-status-warning hover:bg-status-warning/30 transition-colors font-medium"
                    :disabled="buying || (card.currency === 'crypto' ? (authStore.player?.crypto_balance ?? 0) < card.base_price : (authStore.player?.gamecoin_balance ?? 0) < card.base_price)"
                  >
                    {{ buying ? '...' : `${card.base_price} ${card.currency === 'crypto' ? '💎' : '🪙'}` }}
                  </button>
                </div>
              </div>
            </div>

            <!-- Internet Cards -->
            <div>
              <h3 class="text-sm font-medium text-text-muted mb-3 flex items-center gap-2">
                <span class="text-accent-tertiary">📡</span> Tarjetas de Internet
              </h3>
              <div class="grid sm:grid-cols-2 gap-3">
                <div
                  v-for="card in internetCards"
                  :key="card.id"
                  class="bg-bg-secondary rounded-xl p-4 border border-border/50 hover:border-accent-tertiary/50 transition-colors"
                  :class="card.tier === 'elite' ? 'ring-1 ring-accent-primary/50' : ''"
                >
                  <div class="flex items-center justify-between mb-2">
                    <div class="flex items-center gap-2">
                      <span class="font-medium">{{ getCardName(card.id) }}</span>
                      <span v-if="card.tier === 'elite'" class="text-xs px-1.5 py-0.5 rounded bg-accent-primary/20 text-accent-primary">ELITE</span>
                    </div>
                    <span class="text-accent-tertiary font-bold">+{{ card.amount }}</span>
                  </div>
                  <p class="text-xs text-text-muted mb-3">{{ getCardDescription(card.id) }}</p>
                  <button
                    @click="handleBuyCard(card.id)"
                    class="w-full py-2 rounded-lg bg-accent-tertiary/20 text-accent-tertiary hover:bg-accent-tertiary/30 transition-colors font-medium"
                    :disabled="buying || (card.currency === 'crypto' ? (authStore.player?.crypto_balance ?? 0) < card.base_price : (authStore.player?.gamecoin_balance ?? 0) < card.base_price)"
                  >
                    {{ buying ? '...' : `${card.base_price} ${card.currency === 'crypto' ? '💎' : '🪙'}` }}
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Footer -->
        <div class="p-4 border-t border-border/50 bg-bg-secondary">
          <div class="flex items-center justify-between text-sm">
            <span class="text-text-muted">Tu balance:</span>
            <div class="flex items-center gap-4">
              <span class="font-bold text-status-warning">
                {{ authStore.player?.gamecoin_balance?.toFixed(0) ?? 0 }} 🪙
              </span>
              <span class="font-bold text-accent-primary">
                {{ authStore.player?.crypto_balance?.toFixed(2) ?? 0 }} 💎
              </span>
            </div>
          </div>
        </div>
      </div>
    </div>
  </Teleport>
</template>
