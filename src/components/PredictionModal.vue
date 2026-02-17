<script setup lang="ts">
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAuthStore } from '@/stores/auth';
import { usePredictionStore } from '@/stores/prediction';
import type { PredictionBet, PredictionHistory } from '@/stores/prediction';

const props = defineProps<{ show: boolean }>();
const emit = defineEmits<{ close: [] }>();

const { t } = useI18n();
const authStore = useAuthStore();
const predictionStore = usePredictionStore();

const activeTab = ref<'place' | 'active' | 'history'>('place');
const direction = ref<'up' | 'down'>('up');
const targetPercent = ref<number>(10);
const betAmount = ref('');

watch(direction, (dir) => {
  if (dir === 'down' && targetPercent.value >= 100) targetPercent.value = 60;
});
const showConfirmPlace = ref(false);
const showConfirmCancel = ref<string | null>(null);

const TARGET_OPTIONS = [5, 10, 20, 40, 60, 100];
const availableTargets = computed(() =>
  direction.value === 'down'
    ? TARGET_OPTIONS.filter(p => p < 100)
    : TARGET_OPTIONS
);

const numericAmount = computed(() => {
  const n = parseFloat(betAmount.value);
  return isNaN(n) ? 0 : n;
});

const SWAP_FRICTION_PCT = 3; // Estimated roundtrip swap cost for DOWN bets
const effectivePercent = computed(() =>
  direction.value === 'down'
    ? Math.max(targetPercent.value - SWAP_FRICTION_PCT, 1)
    : targetPercent.value
);
const estimatedYield = computed(() => numericAmount.value * effectivePercent.value / 100);
const yieldFee = computed(() => estimatedYield.value * 0.05);
const netYield = computed(() => estimatedYield.value - yieldFee.value);
const totalReturn = computed(() => numericAmount.value + netYield.value);
const playerBalance = computed(() => authStore.player?.crypto_balance ?? 0);

const errorMessage = computed(() => {
  if (!predictionStore.canPlaceBet) return t('prediction.errors.max_active_bets');
  if (numericAmount.value > 0 && numericAmount.value < 50000) return t('prediction.bet.min');
  if (numericAmount.value > playerBalance.value) return t('prediction.errors.insufficient_balance');
  if (predictionStore.currentPrice === null) return t('prediction.errors.price_unavailable');
  return '';
});

const canSubmit = computed(() =>
  numericAmount.value >= 50000 &&
  numericAmount.value <= playerBalance.value &&
  predictionStore.canPlaceBet &&
  predictionStore.currentPrice !== null &&
  !predictionStore.placing
);

const targetPrice = computed(() => {
  if (predictionStore.currentPrice === null) return null;
  if (direction.value === 'up') {
    return predictionStore.currentPrice * (1 + targetPercent.value / 100);
  }
  return predictionStore.currentPrice * (1 - targetPercent.value / 100);
});

watch(() => props.show, (open) => {
  if (open) {
    predictionStore.loadData();
    predictionStore.startPricePolling();
    predictionStore.subscribeToRealtime();
    betAmount.value = '';
    showConfirmPlace.value = false;
    showConfirmCancel.value = null;
  } else {
    predictionStore.stopPricePolling();
    predictionStore.unsubscribeFromRealtime();
  }
});

function setPercentAmount(pct: number) {
  const amount = Math.floor(playerBalance.value * pct / 100);
  betAmount.value = amount > 0 ? String(amount) : '';
}

async function handlePlaceBet() {
  showConfirmPlace.value = false;
  const result = await predictionStore.placeBet(direction.value, targetPercent.value, numericAmount.value);
  if (result.success) {
    betAmount.value = '';
    activeTab.value = 'active';
  }
}

async function handleCancelBet(betId: string) {
  showConfirmCancel.value = null;
  await predictionStore.cancelBet(betId);
}

function formatPrice(price: number | null | undefined): string {
  if (price == null) return '—';
  return '$' + Number(price).toFixed(4);
}

function formatLw(amount: number | null | undefined): string {
  if (amount == null) return '0';
  return Number(amount).toLocaleString('en-US', { maximumFractionDigits: 0 });
}

function formatProgress(bet: PredictionBet): string {
  return Number(bet.progress_percent || 0).toFixed(1);
}

function timeAgo(dateStr: string): string {
  const diff = Date.now() - new Date(dateStr).getTime();
  const mins = Math.floor(diff / 60000);
  if (mins < 60) return `${mins}m`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `${hours}h`;
  return `${Math.floor(hours / 24)}d`;
}
</script>

<template>
  <Teleport to="body">
    <transition name="fade">
      <div v-if="show" class="fixed inset-0 z-50 flex items-center justify-center p-2">
        <div class="absolute inset-0 bg-black/70 backdrop-blur-sm" @click="emit('close')" />

        <!-- Modal: fixed 420px wide, 600px tall -->
        <div class="relative w-[420px] h-[600px] bg-bg-primary border border-border rounded-xl shadow-2xl overflow-hidden flex flex-col">

          <!-- Header compact -->
          <div class="px-3 py-2 border-b border-border bg-gradient-to-r from-bg-primary via-bg-secondary to-bg-primary shrink-0">
            <div class="flex items-center justify-between">
              <div class="flex items-center gap-1.5">
                <span class="text-lg">📊</span>
                <h2 class="text-sm font-bold text-white">{{ t('prediction.title') }}</h2>
              </div>
              <button @click="emit('close')" class="p-1 hover:bg-bg-tertiary rounded transition-colors text-text-muted hover:text-white">
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>
            <!-- Price Ticker -->
            <div class="mt-1.5 glass rounded-lg px-3 py-2 flex items-center justify-between">
              <div>
                <p class="text-[10px] text-text-muted leading-none">{{ t('prediction.price.ronUsdc') }}</p>
                <p class="text-lg font-bold font-mono text-white leading-tight">
                  {{ predictionStore.currentPrice !== null ? formatPrice(predictionStore.currentPrice) : t('prediction.price.loading') }}
                </p>
              </div>
              <div class="text-right">
                <span v-if="predictionStore.priceTrend === 'up'" class="text-status-success text-xs font-bold">
                  ▲ +{{ Math.abs(predictionStore.priceChangePercent).toFixed(2) }}%
                </span>
                <span v-else-if="predictionStore.priceTrend === 'down'" class="text-status-danger text-xs font-bold">
                  ▼ -{{ Math.abs(predictionStore.priceChangePercent).toFixed(2) }}%
                </span>
                <span v-else class="text-text-muted text-xs">—</span>
                <div class="text-[10px] text-text-muted font-mono leading-tight">
                  <span v-if="predictionStore.high24h">H: {{ formatPrice(predictionStore.high24h) }}</span>
                  <span v-if="predictionStore.low24h" class="ml-1">L: {{ formatPrice(predictionStore.low24h) }}</span>
                </div>
              </div>
            </div>
          </div>

          <!-- Tabs -->
          <div class="flex border-b border-border shrink-0">
            <button
              v-for="tab in (['place', 'active', 'history'] as const)" :key="tab"
              @click="activeTab = tab"
              class="flex-1 py-2 text-xs font-medium transition-colors relative"
              :class="activeTab === tab
                ? 'text-accent-primary border-b-2 border-accent-primary'
                : 'text-text-muted hover:text-text-secondary'">
              {{ t(`prediction.tabs.${tab}`) }}
              <span v-if="tab === 'active' && predictionStore.activeCount > 0"
                class="ml-0.5 inline-flex items-center justify-center w-4 h-4 text-[10px] font-bold bg-accent-primary text-black rounded-full">
                {{ predictionStore.activeCount }}
              </span>
            </button>
          </div>

          <!-- Content -->
          <div class="flex-1 overflow-y-auto min-h-0">

            <!-- TAB: PLACE BET -->
            <div v-if="activeTab === 'place'" class="p-3 space-y-2.5">
              <!-- Direction -->
              <div>
                <label class="text-[10px] text-text-muted mb-1 block">{{ t('prediction.direction.label') }}</label>
                <div class="grid grid-cols-2 gap-2">
                  <button
                    @click="direction = 'up'"
                    class="py-2 rounded-lg border-2 font-bold text-sm transition-all"
                    :class="direction === 'up'
                      ? 'border-status-success bg-status-success/15 text-status-success'
                      : 'border-border bg-bg-tertiary text-text-muted hover:border-status-success/50'">
                    📈 {{ t('prediction.direction.up') }}
                  </button>
                  <button
                    @click="direction = 'down'"
                    class="py-2 rounded-lg border-2 font-bold text-sm transition-all"
                    :class="direction === 'down'
                      ? 'border-status-danger bg-status-danger/15 text-status-danger'
                      : 'border-border bg-bg-tertiary text-text-muted hover:border-status-danger/50'">
                    📉 {{ t('prediction.direction.down') }}
                  </button>
                </div>
              </div>

              <!-- Target % -->
              <div>
                <label class="text-[10px] text-text-muted mb-1 block">{{ t('prediction.target.label') }}</label>
                <div class="grid grid-cols-6 gap-1">
                  <button
                    v-for="pct in availableTargets" :key="pct"
                    @click="targetPercent = pct"
                    class="py-1.5 rounded border font-bold text-xs transition-all"
                    :class="targetPercent === pct
                      ? 'border-accent-primary bg-accent-primary/15 text-accent-primary'
                      : 'border-border bg-bg-tertiary text-text-muted hover:border-accent-primary/50'">
                    {{ pct }}%
                  </button>
                </div>
              </div>

              <!-- Bet Amount -->
              <div>
                <label class="text-[10px] text-text-muted mb-1 block">{{ t('prediction.bet.label') }}</label>
                <div class="relative">
                  <input
                    v-model="betAmount"
                    type="number"
                    min="50000"
                    :max="playerBalance"
                    class="input pr-16 font-mono text-sm"
                    :placeholder="t('prediction.bet.min')"
                  />
                  <button
                    @click="setPercentAmount(100)"
                    class="absolute right-1.5 top-1/2 -translate-y-1/2 text-[10px] font-bold text-accent-primary hover:text-accent-secondary transition-colors px-1.5 py-0.5 rounded bg-accent-primary/10">
                    MAX
                  </button>
                </div>
                <div class="flex gap-1.5 mt-1">
                  <button v-for="pct in [25, 50, 75]" :key="pct"
                    @click="setPercentAmount(pct)"
                    class="flex-1 py-1 text-[10px] font-medium rounded border border-border bg-bg-tertiary text-text-muted hover:border-accent-primary/50 hover:text-accent-primary transition-colors">
                    {{ pct }}%
                  </button>
                </div>
                <div class="flex items-center justify-between mt-1">
                  <p class="text-[10px] text-text-muted font-mono">{{ formatLw(playerBalance) }} LW</p>
                  <p v-if="errorMessage" class="text-[10px] text-status-danger">{{ errorMessage }}</p>
                </div>
              </div>

              <!-- Summary -->
              <div v-if="numericAmount >= 50000" class="glass rounded-lg px-2.5 py-2 space-y-1 text-xs">
                <div class="flex justify-between">
                  <span class="text-text-muted">{{ t('prediction.summary.direction') }}</span>
                  <span :class="direction === 'up' ? 'text-status-success' : 'text-status-danger'" class="font-bold">
                    {{ direction === 'up' ? '📈' : '📉' }} {{ direction === 'up' ? t('prediction.direction.up') : t('prediction.direction.down') }} {{ targetPercent }}%
                  </span>
                </div>
                <div class="flex justify-between">
                  <span class="text-text-muted">{{ t('prediction.summary.entryPrice') }} → {{ t('prediction.summary.targetPrice') }}</span>
                  <span class="text-white font-mono">{{ formatPrice(predictionStore.currentPrice) }} → <span class="text-accent-primary font-bold">{{ formatPrice(targetPrice) }}</span></span>
                </div>
                <div class="border-t border-border pt-1 mt-1 flex justify-between">
                  <span class="text-text-muted">{{ t('prediction.summary.potentialYield') }} <span class="text-text-muted/50">(- 5% fee)</span></span>
                  <span class="text-status-success font-bold">+{{ formatLw(netYield) }} LW</span>
                </div>
                <div class="flex justify-between font-bold">
                  <span class="text-white">{{ t('prediction.summary.totalReturn') }}</span>
                  <span class="text-accent-primary">{{ formatLw(totalReturn) }} LW</span>
                </div>
              </div>

              <!-- No-loss notice -->
              <p class="text-[10px] text-accent-primary/70 leading-tight">
                {{ t('prediction.info.noLoss') }}
              </p>

              <!-- Place Button -->
              <button
                @click="showConfirmPlace = true"
                :disabled="!canSubmit"
                class="btn-primary w-full py-2 text-sm">
                {{ predictionStore.placing ? t('prediction.actions.placing') : t('prediction.actions.placeBet') }}
              </button>
            </div>

            <!-- TAB: ACTIVE BETS -->
            <div v-if="activeTab === 'active'" class="p-3 space-y-2">
              <div v-if="predictionStore.loading" class="text-center py-6 text-text-muted text-xs">
                {{ t('common.loading') }}
              </div>

              <div v-else-if="predictionStore.activeCount === 0" class="text-center py-6">
                <span class="text-3xl block mb-2">🎯</span>
                <p class="text-text-muted text-xs">{{ t('prediction.active.noBets') }}</p>
              </div>

              <div v-for="bet in predictionStore.activeBets" :key="bet.id"
                class="glass rounded-lg p-2.5 space-y-2">
                <!-- Header -->
                <div class="flex items-center justify-between">
                  <div class="flex items-center gap-1.5">
                    <span :class="bet.direction === 'up'
                      ? 'bg-status-success/20 text-status-success'
                      : 'bg-status-danger/20 text-status-danger'"
                      class="px-2 py-0.5 rounded text-[10px] font-bold">
                      {{ bet.direction === 'up' ? '📈 ' + t('prediction.direction.up') : '📉 ' + t('prediction.direction.down') }} {{ bet.target_percent }}%
                    </span>
                    <span class="text-accent-primary font-bold text-xs">{{ formatLw(bet.bet_amount_lw) }} LW</span>
                  </div>
                  <span class="text-[10px] text-text-muted">{{ timeAgo(bet.created_at) }}</span>
                </div>

                <!-- Prices inline -->
                <div class="flex justify-between text-[10px] font-mono">
                  <span class="text-text-muted">{{ formatPrice(bet.entry_price) }}</span>
                  <span class="text-white font-bold">{{ formatPrice(bet.current_price) }}</span>
                  <span class="text-accent-primary font-bold">{{ formatPrice(bet.target_price) }}</span>
                </div>

                <!-- Progress Bar -->
                <div>
                  <div class="flex justify-between text-[10px] mb-0.5">
                    <span class="text-text-muted">{{ t('prediction.active.progress') }}</span>
                    <span class="text-white font-bold">{{ formatProgress(bet) }}%</span>
                  </div>
                  <div class="w-full bg-bg-tertiary rounded-full h-1.5 overflow-hidden">
                    <div
                      class="h-full rounded-full transition-all duration-1000"
                      :class="bet.direction === 'up'
                        ? 'bg-gradient-to-r from-status-success/70 to-status-success'
                        : 'bg-gradient-to-r from-status-danger/70 to-status-danger'"
                      :style="{ width: Math.min(100, Math.max(0, bet.progress_percent)) + '%' }">
                    </div>
                  </div>
                </div>

                <!-- Yield + Cancel -->
                <div class="flex items-center justify-between">
                  <span class="text-[10px] text-status-success font-bold">+{{ formatLw(bet.potential_yield) }} LW</span>
                  <button
                    @click="showConfirmCancel = bet.id"
                    :disabled="predictionStore.cancelling === bet.id"
                    class="text-[10px] text-status-danger/70 hover:text-status-danger transition-colors px-1.5 py-0.5 rounded hover:bg-status-danger/10">
                    {{ predictionStore.cancelling === bet.id ? t('prediction.actions.cancelling') : t('prediction.actions.cancel') }}
                  </button>
                </div>
              </div>
            </div>

            <!-- TAB: HISTORY -->
            <div v-if="activeTab === 'history'" class="p-3 space-y-2">
              <!-- Stats -->
              <div v-if="predictionStore.stats" class="glass rounded-lg px-2.5 py-2 grid grid-cols-4 gap-1 text-center">
                <div>
                  <p class="text-[10px] text-text-muted leading-none">{{ t('prediction.stats.totalBets') }}</p>
                  <p class="text-white font-bold text-sm">{{ predictionStore.stats.total_bets }}</p>
                </div>
                <div>
                  <p class="text-[10px] text-text-muted leading-none">{{ t('prediction.stats.wonBets') }}</p>
                  <p class="text-status-success font-bold text-sm">{{ predictionStore.stats.total_won }}</p>
                </div>
                <div>
                  <p class="text-[10px] text-text-muted leading-none">{{ t('prediction.stats.totalYield') }}</p>
                  <p class="text-accent-primary font-bold text-xs">{{ formatLw(predictionStore.stats.total_yield_earned) }}</p>
                </div>
                <div>
                  <p class="text-[10px] text-text-muted leading-none">{{ t('prediction.stats.totalFees') }}</p>
                  <p class="text-text-muted font-bold text-xs">{{ formatLw(predictionStore.stats.total_fees_paid) }}</p>
                </div>
              </div>

              <div v-if="predictionStore.history.length === 0" class="text-center py-6">
                <span class="text-3xl block mb-2">📜</span>
                <p class="text-text-muted text-xs">{{ t('prediction.history.noHistory') }}</p>
              </div>

              <div v-for="bet in predictionStore.history" :key="bet.id"
                class="flex items-center justify-between px-2.5 py-1.5 rounded-lg text-xs"
                :class="bet.status === 'won' ? 'bg-status-success/5 border border-status-success/20' : 'bg-bg-tertiary/50 border border-border'">
                <div class="flex items-center gap-2">
                  <span class="text-sm">{{ bet.status === 'won' ? '✅' : '↩️' }}</span>
                  <div>
                    <p class="text-xs font-medium text-white leading-tight">
                      {{ bet.direction === 'up' ? t('prediction.direction.up') : t('prediction.direction.down') }}
                      {{ bet.target_percent }}%
                      <span class="text-text-muted">· {{ formatLw(bet.bet_amount_lw) }} LW</span>
                    </p>
                    <p class="text-[10px] text-text-muted">{{ timeAgo(bet.settled_at) }}</p>
                  </div>
                </div>
                <div class="text-right">
                  <p v-if="bet.status === 'won'" class="text-xs font-bold text-status-success">+{{ formatLw(bet.yield_earned_lw) }} LW</p>
                  <p v-else class="text-xs text-text-muted">{{ t('prediction.history.cancelled') }}</p>
                  <p v-if="bet.fee_amount_lw > 0" class="text-[10px] text-text-muted">fee: {{ formatLw(bet.fee_amount_lw) }}</p>
                </div>
              </div>
            </div>
          </div>

          <!-- CONFIRM PLACE -->
          <div v-if="showConfirmPlace" class="absolute inset-0 z-[60] flex items-center justify-center p-3">
            <div class="absolute inset-0 bg-black/50" @click="showConfirmPlace = false" />
            <div class="relative bg-bg-secondary border border-border rounded-xl p-4 max-w-xs w-full space-y-3">
              <h3 class="text-sm font-bold text-white text-center">{{ t('prediction.actions.confirmPlace') }}</h3>
              <div class="glass rounded-lg px-2.5 py-2 space-y-1.5 text-xs">
                <div class="flex justify-between">
                  <span class="text-text-muted">{{ t('prediction.summary.direction') }}</span>
                  <span :class="direction === 'up' ? 'text-status-success' : 'text-status-danger'" class="font-bold">
                    {{ direction === 'up' ? t('prediction.direction.up') : t('prediction.direction.down') }} {{ targetPercent }}%
                  </span>
                </div>
                <div class="flex justify-between">
                  <span class="text-text-muted">{{ t('prediction.bet.label') }}</span>
                  <span class="text-white font-bold">{{ formatLw(numericAmount) }} LW</span>
                </div>
                <div class="flex justify-between">
                  <span class="text-text-muted">{{ t('prediction.summary.targetPrice') }}</span>
                  <span class="text-accent-primary font-mono">{{ formatPrice(targetPrice) }}</span>
                </div>
                <div class="flex justify-between border-t border-border pt-1.5">
                  <span class="text-text-muted">{{ t('prediction.summary.potentialYield') }}</span>
                  <span class="text-status-success font-bold">+{{ formatLw(netYield) }} LW</span>
                </div>
              </div>
              <div class="flex gap-2">
                <button @click="showConfirmPlace = false" class="btn-secondary flex-1 py-1.5 text-xs">
                  {{ t('common.cancel') }}
                </button>
                <button @click="handlePlaceBet" :disabled="predictionStore.placing" class="btn-primary flex-1 py-1.5 text-xs">
                  {{ predictionStore.placing ? t('prediction.actions.placing') : t('common.confirm') }}
                </button>
              </div>
            </div>
          </div>

          <!-- CONFIRM CANCEL -->
          <div v-if="showConfirmCancel" class="absolute inset-0 z-[60] flex items-center justify-center p-3">
            <div class="absolute inset-0 bg-black/50" @click="showConfirmCancel = null" />
            <div class="relative bg-bg-secondary border border-border rounded-xl p-4 max-w-xs w-full space-y-3">
              <h3 class="text-sm font-bold text-white text-center">{{ t('prediction.actions.cancel') }}</h3>
              <p class="text-xs text-text-secondary text-center">{{ t('prediction.actions.confirmCancel') }}</p>
              <div class="flex gap-2">
                <button @click="showConfirmCancel = null" class="btn-secondary flex-1 py-1.5 text-xs">
                  {{ t('common.close') }}
                </button>
                <button @click="handleCancelBet(showConfirmCancel!)" class="btn-danger flex-1 py-1.5 text-xs">
                  {{ t('prediction.actions.cancel') }}
                </button>
              </div>
            </div>
          </div>

        </div>
      </div>
    </transition>
  </Teleport>
</template>

<style scoped>
.fade-enter-active,
.fade-leave-active {
  transition: opacity 0.2s ease;
}

.fade-enter-from,
.fade-leave-to {
  opacity: 0;
}
</style>
