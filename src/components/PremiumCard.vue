<script setup lang="ts">
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAuthStore } from '@/stores/auth';
import { getPremiumStatus, purchasePremium, type PremiumStatus } from '@/utils/api';
import { playSound } from '@/utils/sounds';

const { t } = useI18n();
const authStore = useAuthStore();

const loading = ref(true);
const purchasing = ref(false);
const premiumStatus = ref<PremiumStatus | null>(null);
const error = ref('');
const showConfirm = ref(false);
const hasLoaded = ref(false);
const isLoadingInProgress = ref(false);

const isPremium = computed(() => premiumStatus.value?.is_premium ?? false);
const daysRemaining = computed(() => premiumStatus.value?.days_remaining ?? 0);
const price = computed(() => premiumStatus.value?.price ?? 2.5);
const canAfford = computed(() => (authStore.player?.ron_balance ?? 0) >= price.value);
const ronBalance = computed(() => authStore.player?.ron_balance ?? 0);

const expiresDate = computed(() => {
  if (!premiumStatus.value?.expires_at) return '';
  return new Date(premiumStatus.value.expires_at).toLocaleDateString();
});

async function loadStatus(force = false) {
  // Prevent concurrent loads
  if (isLoadingInProgress.value) {
    return;
  }

  if (hasLoaded.value && !force) {
    loading.value = false;
    return;
  }

  if (!authStore.player?.id) {
    loading.value = false;
    return;
  }

  isLoadingInProgress.value = true;

  try {
    premiumStatus.value = await getPremiumStatus(authStore.player.id);
    hasLoaded.value = true;
  } catch (e) {
    console.error('[PremiumCard] Error loading premium status:', e);
  } finally {
    loading.value = false;
    isLoadingInProgress.value = false;
  }
}

// Watch for player to become available (handles race condition on mount)
watch(() => authStore.player?.id, (newId) => {
  if (newId && !hasLoaded.value) {
    loading.value = true;
    loadStatus();
  }
}, { immediate: true });

function requestPurchase() {
  playSound('click');
  showConfirm.value = true;
}

function cancelPurchase() {
  playSound('click');
  showConfirm.value = false;
}

async function confirmPurchase() {
  if (!authStore.player?.id || purchasing.value) return;

  showConfirm.value = false;
  error.value = '';
  purchasing.value = true;

  try {
    const result = await purchasePremium(authStore.player.id);

    if (result.success) {
      playSound('success');
      await authStore.refreshPlayer();
      await loadStatus(true);
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

// loadStatus is called by the watcher with immediate: true
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
            <p class="text-xs text-text-muted">Tus shares × 1.5</p>
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

        <div class="flex items-center gap-3 bg-bg-tertiary rounded-lg p-3">
          <div class="w-10 h-10 rounded-lg bg-cyan-500/20 flex items-center justify-center text-cyan-400">
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z" />
            </svg>
          </div>
          <div>
            <p class="font-medium">{{ t('premium.benefits.resourceBonus') }}</p>
            <p class="text-xs text-text-muted">+1000 max energy & internet</p>
          </div>
        </div>

        <div class="flex items-center gap-3 bg-bg-tertiary rounded-lg p-3">
          <div class="w-10 h-10 rounded-lg bg-orange-500/20 flex items-center justify-center text-orange-400">
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
            </svg>
          </div>
          <div>
            <p class="font-medium">{{ t('premium.benefits.rigDurability') }}</p>
            <p class="text-xs text-text-muted">🔥 Tus rigs duran más</p>
          </div>
        </div>

        <div class="flex items-center gap-3 bg-bg-tertiary rounded-lg p-3">
          <div class="w-10 h-10 rounded-lg bg-emerald-500/20 flex items-center justify-center text-emerald-400">
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 17h8m0 0V9m0 8l-8-8-4 4-6-6" />
            </svg>
          </div>
          <div>
            <p class="font-medium">{{ t('premium.benefits.reducedConsumption') }}</p>
            <p class="text-xs text-text-muted">⚡ Ahorra energía e internet</p>
          </div>
        </div>

        <div class="flex items-center gap-3 bg-bg-tertiary rounded-lg p-3">
          <div class="w-10 h-10 rounded-lg bg-blue-500/20 flex items-center justify-center text-blue-400">
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14 10l-2 1m0 0l-2-1m2 1v2.5M20 7l-2 1m2-1l-2-1m2 1v2.5M14 4l-2-1-2 1M4 7l2-1M4 7l2 1M4 7v2.5M12 21l-2-1m2 1l2-1m-2 1v-2.5M6 18l-2-1v-2.5M18 18l2-1v-2.5" />
            </svg>
          </div>
          <div>
            <p class="font-medium">{{ t('premium.benefits.improvedCooling') }}</p>
            <p class="text-xs text-text-muted">🧊 Recuperación rápida</p>
          </div>
        </div>
      </div>

      <!-- Error -->
      <div v-if="error" class="bg-status-danger/10 border border-status-danger/30 rounded-lg p-3 mb-4 text-sm text-status-danger">
        {{ error }}
      </div>

      <!-- Price & Buy Button (solo si NO tiene premium) -->
      <template v-if="!isPremium">
        <div class="flex items-center justify-between">
          <div>
            <p class="text-2xl font-bold text-amber-400">{{ price }} RON</p>
            <p class="text-xs text-text-muted">{{ t('premium.price', { price }) }}</p>
          </div>

          <button
            @click="requestPurchase"
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
              {{ t('premium.subscribe') }}
            </span>
          </button>
        </div>

        <!-- Balance Warning -->
        <p v-if="!canAfford" class="text-xs text-status-warning mt-2 text-center">
          {{ t('premium.insufficientBalance', { required: price }) }}
          <br>
          {{ t('premium.currentBalance', { balance: (authStore.player?.ron_balance ?? 0).toFixed(4) }) }}
        </p>
      </template>
    </template>

    <!-- Confirmation Modal -->
    <Teleport to="body">
      <div
        v-if="showConfirm"
        class="fixed inset-0 z-50 flex items-center justify-center p-4"
      >
        <div class="absolute inset-0 bg-black/70 backdrop-blur-sm" @click="cancelPurchase"></div>

        <div class="relative bg-bg-secondary rounded-xl p-6 max-w-sm w-full border border-border animate-fade-in">
          <div class="text-center mb-4">
            <div class="text-4xl mb-3">&#x1F451;</div>
            <h3 class="text-lg font-bold mb-1">{{ t('premium.confirmTitle', 'Activar Premium') }}</h3>
            <p class="text-text-muted text-sm">{{ t('premium.confirmQuestion', '¿Deseas activar el plan premium?') }}</p>
          </div>

          <div class="bg-bg-primary rounded-lg p-4 mb-4">
            <div class="font-medium text-amber-400 mb-2 text-center">{{ t('premium.title') }}</div>
            <div class="text-xs text-text-muted mb-3 space-y-1">
              <p>✓ {{ t('premium.benefits.blockBonus') }}</p>
              <p>✓ {{ t('premium.benefits.withdrawalFee') }}</p>
              <p>✓ {{ t('premium.benefits.resourceBonus') }}</p>
              <p>✓ {{ t('premium.benefits.rigDurability') }}</p>
              <p>✓ {{ t('premium.benefits.reducedConsumption') }}</p>
              <p>✓ {{ t('premium.benefits.improvedCooling') }}</p>
            </div>
            <div class="flex items-center justify-between border-t border-border/50 pt-3">
              <span class="text-text-muted text-sm">{{ t('market.confirmPurchase.price', 'Precio') }}</span>
              <span class="font-bold text-amber-400">{{ price }} RON</span>
            </div>
            <div class="flex items-center justify-between mt-1">
              <span class="text-text-muted text-sm">{{ t('market.confirmPurchase.yourBalance', 'Tu balance') }}</span>
              <span class="font-mono" :class="canAfford ? 'text-status-success' : 'text-status-danger'">
                {{ ronBalance.toFixed(4) }} RON
              </span>
            </div>
            <div class="flex items-center justify-between mt-1 pt-2 border-t border-border/50">
              <span class="text-text-muted text-sm">{{ t('market.confirmPurchase.after', 'Después') }}</span>
              <span class="font-mono text-white">{{ (ronBalance - price).toFixed(4) }} RON</span>
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
              :disabled="purchasing"
              class="flex-1 py-2.5 rounded-lg font-medium bg-gradient-to-r from-amber-500 to-orange-500 text-white hover:from-amber-600 hover:to-orange-600 transition-colors disabled:opacity-50"
            >
              {{ purchasing ? '...' : t('common.confirm') }}
            </button>
          </div>
        </div>
      </div>
    </Teleport>
  </div>
</template>
