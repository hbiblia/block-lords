<script setup lang="ts">
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { usePlayerStore } from '@/stores/player';
import { getPremiumStatus, purchasePremium, type PremiumStatus } from '@/utils/api';
import { playSound } from '@/utils/audio';

const { t } = useI18n();
const playerStore = usePlayerStore();

const loading = ref(true);
const purchasing = ref(false);
const premiumStatus = ref<PremiumStatus | null>(null);
const error = ref('');

const isPremium = computed(() => premiumStatus.value?.is_premium ?? false);
const daysRemaining = computed(() => premiumStatus.value?.days_remaining ?? 0);
const price = computed(() => premiumStatus.value?.price ?? 2.5);
const canAfford = computed(() => (playerStore.ronBalance ?? 0) >= price.value);

const expiresDate = computed(() => {
  if (!premiumStatus.value?.expires_at) return '';
  return new Date(premiumStatus.value.expires_at).toLocaleDateString();
});

async function loadStatus() {
  if (!playerStore.player?.id) return;

  try {
    loading.value = true;
    premiumStatus.value = await getPremiumStatus(playerStore.player.id);
  } catch (e) {
    console.error('Error loading premium status:', e);
  } finally {
    loading.value = false;
  }
}

async function handlePurchase() {
  if (!playerStore.player?.id || purchasing.value) return;

  error.value = '';
  purchasing.value = true;

  try {
    const result = await purchasePremium(playerStore.player.id);

    if (result.success) {
      playSound('success');
      await playerStore.refreshPlayer();
      await loadStatus();
    } else {
      error.value = result.error || t('premium.error');
      playSound('error');
    }
  } catch (e: any) {
    console.error('Error purchasing premium:', e);
    error.value = e.message || t('premium.error');
    playSound('error');
  } finally {
    purchasing.value = false;
  }
}

onMounted(() => {
  loadStatus();
});
</script>

<template>
  <div class="card p-4">
    <!-- Header -->
    <div class="flex items-center justify-between mb-4">
      <div class="flex items-center gap-2">
        <span class="text-2xl">&#x1F451;</span>
        <div>
          <h3 class="font-bold text-lg">{{ t('premium.title') }}</h3>
          <p class="text-xs text-text-muted">{{ t('premium.subtitle') }}</p>
        </div>
      </div>

      <!-- Status Badge -->
      <div
        :class="[
          'px-3 py-1 rounded-full text-sm font-medium',
          isPremium
            ? 'bg-amber-500/20 text-amber-400 border border-amber-500/30'
            : 'bg-bg-tertiary text-text-muted'
        ]"
      >
        {{ isPremium ? t('premium.active') : t('premium.inactive') }}
      </div>
    </div>

    <!-- Loading State -->
    <div v-if="loading" class="flex justify-center py-8">
      <div class="animate-spin w-8 h-8 border-2 border-accent-primary border-t-transparent rounded-full"></div>
    </div>

    <template v-else>
      <!-- Premium Active Info -->
      <div v-if="isPremium" class="bg-amber-500/10 border border-amber-500/30 rounded-xl p-4 mb-4">
        <div class="flex items-center gap-2 text-amber-400 mb-2">
          <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd" />
          </svg>
          <span class="font-medium">{{ t('premium.daysRemaining', { days: daysRemaining }) }}</span>
        </div>
        <p class="text-sm text-text-muted">
          {{ t('premium.expiresOn', { date: expiresDate }) }}
        </p>
      </div>

      <!-- Benefits -->
      <div class="space-y-3 mb-4">
        <h4 class="text-sm font-medium text-text-muted">{{ t('premium.benefits.title') }}</h4>

        <div class="flex items-center gap-3 bg-bg-tertiary rounded-lg p-3">
          <div class="w-10 h-10 rounded-lg bg-status-success/20 flex items-center justify-center text-status-success">
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 7h8m0 0v8m0-8l-8 8-4-4-6 6" />
            </svg>
          </div>
          <div>
            <p class="font-medium">{{ t('premium.benefits.blockBonus') }}</p>
            <p class="text-xs text-text-muted">150 crypto vs 100 crypto</p>
          </div>
        </div>

        <div class="flex items-center gap-3 bg-bg-tertiary rounded-lg p-3">
          <div class="w-10 h-10 rounded-lg bg-purple-500/20 flex items-center justify-center text-purple-400">
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8c1.11 0 2.08.402 2.599 1M12 8V7m0 1v8m0 0v1m0-1c-1.11 0-2.08-.402-2.599-1M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
          </div>
          <div>
            <p class="font-medium">{{ t('premium.benefits.withdrawalFee') }}</p>
            <p class="text-xs text-text-muted">10% vs 25%</p>
          </div>
        </div>
      </div>

      <!-- Comparison Table -->
      <div class="bg-bg-tertiary rounded-xl p-3 mb-4">
        <h4 class="text-sm font-medium text-center mb-3">{{ t('premium.comparison.title') }}</h4>
        <div class="grid grid-cols-3 gap-2 text-sm">
          <div></div>
          <div class="text-center text-text-muted">{{ t('premium.comparison.free') }}</div>
          <div class="text-center text-amber-400 font-medium">{{ t('premium.comparison.premium') }}</div>

          <div class="text-text-muted">{{ t('premium.comparison.blockReward') }}</div>
          <div class="text-center">100</div>
          <div class="text-center text-status-success font-medium">150</div>

          <div class="text-text-muted">{{ t('premium.comparison.withdrawalFee') }}</div>
          <div class="text-center text-status-danger">25%</div>
          <div class="text-center text-status-success font-medium">10%</div>
        </div>
      </div>

      <!-- Error -->
      <div v-if="error" class="bg-status-danger/10 border border-status-danger/30 rounded-lg p-3 mb-4 text-sm text-status-danger">
        {{ error }}
      </div>

      <!-- Price & Buy Button -->
      <div class="flex items-center justify-between">
        <div>
          <p class="text-2xl font-bold text-amber-400">{{ price }} RON</p>
          <p class="text-xs text-text-muted">{{ t('premium.price', { price }) }}</p>
        </div>

        <button
          @click="handlePurchase"
          :disabled="purchasing || !canAfford"
          :class="[
            'px-6 py-3 rounded-xl font-medium transition-all',
            canAfford
              ? 'bg-gradient-to-r from-amber-500 to-orange-500 text-white hover:from-amber-600 hover:to-orange-600'
              : 'bg-bg-tertiary text-text-muted cursor-not-allowed'
          ]"
        >
          <span v-if="purchasing" class="flex items-center gap-2">
            <span class="animate-spin w-4 h-4 border-2 border-white border-t-transparent rounded-full"></span>
            {{ t('premium.subscribing') }}
          </span>
          <span v-else>
            {{ isPremium ? t('premium.extend') : t('premium.subscribe') }}
          </span>
        </button>
      </div>

      <!-- Balance Warning -->
      <p v-if="!canAfford" class="text-xs text-status-warning mt-2 text-center">
        {{ t('premium.insufficientBalance', { required: price }) }}
        <br>
        {{ t('premium.currentBalance', { balance: (playerStore.ronBalance ?? 0).toFixed(4) }) }}
      </p>
    </template>
  </div>
</template>
