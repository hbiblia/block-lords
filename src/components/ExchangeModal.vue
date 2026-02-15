<script setup lang="ts">
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAuthStore } from '@/stores/auth';
import { exchangeCryptoToGamecoin, exchangeCryptoToRon, getExchangeRates } from '@/utils/api';
import { playSound } from '@/utils/sounds';
import { formatCrypto, formatRon, formatNumber } from '@/utils/format';

const { t } = useI18n();

const props = defineProps<{
  show: boolean;
}>();

const emit = defineEmits<{
  close: [];
  exchanged: [];
}>();

const authStore = useAuthStore();

const exchanging = ref(false);
const loadingRates = ref(false);
const activeTab = ref<'gamecoin' | 'ron'>('gamecoin');
const amount = ref('');

const rates = ref<{
  crypto_to_gamecoin: number;
  crypto_to_gamecoin_previous: number;
  crypto_to_ron: number;
  min_crypto_for_ron: number;
  rate_updated_at: string;
} | null>(null);

const cryptoBalance = computed(() => authStore.player?.crypto_balance ?? 0);
const ronBalance = computed(() => authStore.player?.ron_balance ?? 0);

const rateTrend = computed(() => {
  if (!rates.value) return 'neutral';
  const current = rates.value.crypto_to_gamecoin;
  const previous = rates.value.crypto_to_gamecoin_previous;
  if (current > previous) return 'up';
  if (current < previous) return 'down';
  return 'neutral';
});

const rateChangePercent = computed(() => {
  if (!rates.value || !rates.value.crypto_to_gamecoin_previous) return 0;
  const current = rates.value.crypto_to_gamecoin;
  const previous = rates.value.crypto_to_gamecoin_previous;
  return ((current - previous) / previous * 100);
});

function formatRate(rate: number): string {
  if (rate >= 1) return rate.toFixed(2);
  if (rate >= 0.01) return rate.toFixed(3);
  return rate.toFixed(4);
}

const numericAmount = computed(() => {
  const val = parseFloat(amount.value);
  return isNaN(val) ? 0 : val;
});

const estimatedReceive = computed(() => {
  if (!rates.value) return 0;
  if (activeTab.value === 'gamecoin') {
    return numericAmount.value * rates.value.crypto_to_gamecoin;
  } else {
    return numericAmount.value * rates.value.crypto_to_ron;
  }
});

const canExchange = computed(() => {
  if (!rates.value) return false;
  if (numericAmount.value <= 0) return false;
  if (numericAmount.value > cryptoBalance.value) return false;
  if (activeTab.value === 'ron' && numericAmount.value < rates.value.min_crypto_for_ron) return false;
  return true;
});

const errorMessage = computed(() => {
  if (!rates.value) return '';
  if (numericAmount.value <= 0) return '';
  if (numericAmount.value > cryptoBalance.value) return t('exchange.insufficientCrypto');
  if (activeTab.value === 'ron' && numericAmount.value < rates.value.min_crypto_for_ron) {
    return t('exchange.minCryptoForRon', { amount: formatNumber(rates.value.min_crypto_for_ron) });
  }
  return '';
});

async function loadRates() {
  loadingRates.value = true;
  try {
    const data = await getExchangeRates();
    if (data) {
      rates.value = data;
    }
  } catch (e) {
    console.error('Error loading rates:', e);
  } finally {
    loadingRates.value = false;
  }
}

async function handleExchange() {
  if (!canExchange.value || !authStore.player) return;

  exchanging.value = true;

  try {
    let result;
    if (activeTab.value === 'gamecoin') {
      result = await exchangeCryptoToGamecoin(authStore.player.id, numericAmount.value);
    } else {
      result = await exchangeCryptoToRon(authStore.player.id, numericAmount.value);
    }

    if (result?.success) {
      playSound('purchase');
      await authStore.fetchPlayer();
      amount.value = '';
      emit('exchanged');
    } else {
      playSound('error');
      alert(result?.error ?? 'Error en el exchange');
    }
  } catch (e) {
    console.error('Error exchanging:', e);
    playSound('error');
    alert('Error al realizar el exchange');
  } finally {
    exchanging.value = false;
  }
}

function setMaxAmount() {
  amount.value = cryptoBalance.value.toString();
}

function setPercentAmount(percent: number) {
  amount.value = (cryptoBalance.value * percent).toFixed(4);
}

watch(() => props.show, (newVal) => {
  if (newVal) {
    loadRates();
    amount.value = '';
  }
});

onMounted(() => {
  if (props.show) {
    loadRates();
  }
});
</script>

<template>
  <Teleport to="body">
    <div
      v-if="show"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/70"
    >
      <div class="bg-bg-secondary rounded-2xl w-full max-w-md mx-4 border border-border overflow-hidden">
        <!-- Header -->
        <div class="flex items-center justify-between p-4 border-b border-border">
          <h2 class="text-lg font-bold flex items-center gap-2">
            <span class="text-2xl">💱</span>
            {{ t('exchange.title') }}
          </h2>
          <button
            @click="emit('close')"
            class="p-2 hover:bg-bg-tertiary rounded-lg transition-colors"
          >
            ✕
          </button>
        </div>

        <!-- Balance Display -->
        <div class="p-4 bg-bg-primary/50">
          <div class="grid grid-cols-2 gap-4">
            <div class="text-center">
              <div class="text-xs text-text-muted mb-1">{{ t('exchange.yourCrypto') }}</div>
              <div class="text-xl font-bold text-accent-tertiary font-mono">
                {{ formatCrypto(cryptoBalance) }} ₿
              </div>
            </div>
            <div class="text-center">
              <div class="text-xs text-text-muted mb-1">{{ t('exchange.yourRon') }}</div>
              <div class="text-xl font-bold text-amber-400 font-mono">
                {{ formatRon(ronBalance) }} RON
              </div>
            </div>
          </div>
        </div>

        <!-- Tabs -->
        <div class="flex border-b border-border">
          <button
            @click="activeTab = 'gamecoin'"
            class="flex-1 py-3 flex flex-col items-center gap-1 transition-colors"
            :class="activeTab === 'gamecoin'
              ? 'bg-status-warning/10 text-status-warning border-b-2 border-status-warning'
              : 'text-text-muted hover:bg-bg-tertiary'"
          >
            <span class="text-2xl">🪙</span>
            <span class="text-xs font-medium">{{ t('exchange.tabs.gamecoin') }}</span>
          </button>
          <button
            @click="activeTab = 'ron'"
            class="flex-1 py-3 flex flex-col items-center gap-1 transition-colors"
            :class="activeTab === 'ron'
              ? 'bg-amber-500/10 text-amber-400 border-b-2 border-amber-400'
              : 'text-text-muted hover:bg-bg-tertiary'"
          >
            <span class="text-2xl">💎</span>
            <span class="text-xs font-medium">{{ t('exchange.tabs.ron') }}</span>
          </button>
        </div>

        <!-- Content -->
        <div class="p-4 space-y-4">
          <!-- Rate Info (con loading inline) -->
          <div class="bg-bg-tertiary rounded-lg p-3 text-center text-sm">
            <span class="text-text-muted">{{ t('exchange.rate') }} </span>
            <span v-if="loadingRates" class="inline-flex items-center gap-2">
              <span class="animate-spin w-4 h-4 border-2 border-accent-primary border-t-transparent rounded-full"></span>
            </span>
            <span v-else-if="rates && activeTab === 'gamecoin'" class="font-medium">
              <span class="text-status-warning">1 ₿ = {{ formatRate(rates.crypto_to_gamecoin) }} 🪙</span>
              <span
                v-if="rateTrend !== 'neutral'"
                class="ml-2 text-xs font-bold"
                :class="rateTrend === 'up' ? 'text-green-400' : 'text-red-400'"
              >
                {{ rateTrend === 'up' ? '▲' : '▼' }} {{ Math.abs(rateChangePercent).toFixed(1) }}%
              </span>
            </span>
            <span v-else-if="rates" class="text-amber-400 font-medium">
              1,000 ₿ = {{ formatRon(1000 * rates.crypto_to_ron) }} RON
            </span>
            <span v-else class="text-status-danger">{{ t('common.error') }}</span>
          </div>

          <!-- Amount Input -->
          <div>
            <label class="text-xs text-text-muted mb-2 block">{{ t('exchange.cryptoAmount') }}</label>
            <div class="relative">
              <input
                v-model="amount"
                type="number"
                step="0.0001"
                min="0"
                :max="cryptoBalance"
                placeholder="0.0000"
                class="w-full bg-bg-tertiary border border-border rounded-lg px-4 py-3 pr-16 font-mono text-lg focus:outline-none focus:border-accent-primary"
              />
              <span class="absolute right-4 top-1/2 -translate-y-1/2 text-text-muted">₿</span>
            </div>
          </div>

          <!-- Quick Amount Buttons -->
          <div class="flex gap-2">
            <button
              @click="setPercentAmount(0.25)"
              class="flex-1 py-2 text-xs font-medium bg-bg-tertiary hover:bg-bg-tertiary/80 rounded-lg transition-colors"
            >
              25%
            </button>
            <button
              @click="setPercentAmount(0.5)"
              class="flex-1 py-2 text-xs font-medium bg-bg-tertiary hover:bg-bg-tertiary/80 rounded-lg transition-colors"
            >
              50%
            </button>
            <button
              @click="setPercentAmount(0.75)"
              class="flex-1 py-2 text-xs font-medium bg-bg-tertiary hover:bg-bg-tertiary/80 rounded-lg transition-colors"
            >
              75%
            </button>
            <button
              @click="setMaxAmount"
              class="flex-1 py-2 text-xs font-medium bg-accent-primary/20 text-accent-primary hover:bg-accent-primary/30 rounded-lg transition-colors"
            >
              MAX
            </button>
          </div>

          <!-- Error Message -->
          <div v-if="errorMessage" class="text-status-danger text-sm text-center">
            {{ errorMessage }}
          </div>

          <!-- Estimated Receive -->
          <div class="bg-bg-primary rounded-xl p-4">
            <div class="text-xs text-text-muted mb-2 text-center">{{ t('exchange.youWillReceive') }}</div>
            <div class="text-3xl font-bold text-center font-mono" :class="activeTab === 'gamecoin' ? 'text-status-warning' : 'text-amber-400'">
              {{ activeTab === 'gamecoin' ? formatRate(estimatedReceive) : formatRon(estimatedReceive) }}
              <span class="text-lg">{{ activeTab === 'gamecoin' ? '🪙' : 'RON' }}</span>
            </div>
          </div>

          <!-- Min Amount Warning for RON -->
          <div v-if="activeTab === 'ron' && rates" class="text-xs text-text-muted text-center">
            {{ t('exchange.minAmountWarning', { amount: formatNumber(rates.min_crypto_for_ron) }) }}
          </div>

          <!-- Exchange Button -->
          <button
            @click="handleExchange"
            :disabled="!canExchange || exchanging || loadingRates"
            class="w-full py-3 rounded-xl font-bold text-lg transition-all"
            :class="canExchange && !exchanging && !loadingRates
              ? (activeTab === 'gamecoin'
                  ? 'bg-gradient-to-r from-status-warning to-yellow-500 text-black hover:opacity-90'
                  : 'bg-gradient-to-r from-amber-500 to-yellow-500 text-black hover:opacity-90')
              : 'bg-bg-tertiary text-text-muted cursor-not-allowed'"
          >
            {{ exchanging ? t('common.processing') : (activeTab === 'gamecoin' ? t('exchange.convertToGamecoin') : t('exchange.convertToRon')) }}
          </button>
        </div>
      </div>
    </div>
  </Teleport>
</template>
