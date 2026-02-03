<script setup lang="ts">
import { ref, onMounted, computed } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAuthStore } from '@/stores/auth';

const { t } = useI18n();
const router = useRouter();
const authStore = useAuthStore();

const player = computed(() => authStore.player);
const showContent = ref(false);
const showStats = ref(false);
const showButton = ref(false);

onMounted(async () => {
  // Secuencia de animación
  await new Promise(resolve => setTimeout(resolve, 300));
  showContent.value = true;

  await new Promise(resolve => setTimeout(resolve, 600));
  showStats.value = true;

  await new Promise(resolve => setTimeout(resolve, 400));
  showButton.value = true;
});

function enterGame() {
  router.push('/mining');
}

function getRankName(score: number): string {
  if (score >= 85) return t('welcome.ranks.diamond');
  if (score >= 70) return t('welcome.ranks.platinum');
  if (score >= 50) return t('welcome.ranks.gold');
  if (score >= 30) return t('welcome.ranks.silver');
  return t('welcome.ranks.bronze');
}

function getRankIcon(score: number): string {
  if (score >= 85) return '💎';
  if (score >= 70) return '⚜️';
  if (score >= 50) return '🏆';
  if (score >= 30) return '🥈';
  return '🥉';
}

function formatCurrency(value: number | undefined, decimals: number = 0): string {
  if (value === undefined || value === null) return decimals > 0 ? '0.00' : '0';
  return value.toLocaleString('en-US', {
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals,
  });
}
</script>

<template>
  <div class="min-h-[80vh] flex items-center justify-center py-12">
    <div class="text-center max-w-lg mx-auto px-4">
      <!-- Avatar animado -->
      <div
        class="transition-all duration-700 transform"
        :class="showContent ? 'opacity-100 translate-y-0' : 'opacity-0 -translate-y-8'"
      >
        <div class="relative inline-block mb-6">
          <div class="w-28 h-28 rounded-2xl bg-gradient-primary flex items-center justify-center text-5xl shadow-glow">
            {{ player?.username?.charAt(0).toUpperCase() ?? '?' }}
          </div>
          <!-- Rango badge -->
          <div class="absolute -bottom-2 -right-2 w-10 h-10 rounded-xl bg-bg-card border-2 border-accent-primary flex items-center justify-center text-xl">
            {{ getRankIcon(player?.reputation_score ?? 50) }}
          </div>
        </div>

        <!-- Saludo -->
        <h1 class="text-3xl font-display font-bold mb-2">
          {{ t('welcome.greeting') }}
        </h1>
        <h2 class="text-4xl font-display font-bold mb-4">
          <span class="gradient-text">{{ player?.username ?? t('welcome.defaultName') }}</span>!
        </h2>
        <p class="text-text-secondary mb-8">
          {{ t('welcome.stationReady') }}
        </p>
      </div>

      <!-- Stats rápidas -->
      <div
        class="grid grid-cols-3 gap-4 mb-8 transition-all duration-700 delay-300"
        :class="showStats ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-4'"
      >
        <div class="card py-4">
          <div class="text-2xl font-bold text-status-warning">
            {{ formatCurrency(player?.gamecoin_balance, 0) }}
          </div>
          <div class="text-xs text-text-muted mt-1">🪙 GameCoin</div>
        </div>
        <div class="card py-4">
          <div class="text-2xl font-bold text-accent-tertiary">
            {{ formatCurrency(player?.crypto_balance, 2) }}
          </div>
          <div class="text-xs text-text-muted mt-1">💎 Crypto</div>
        </div>
        <div class="card py-4">
          <div class="text-2xl font-bold text-accent-primary">
            {{ getRankName(player?.reputation_score ?? 50) }}
          </div>
          <div class="text-xs text-text-muted mt-1">⭐ {{ t('welcome.rank') }}</div>
        </div>
      </div>

      <!-- Recursos -->
      <div
        class="card mb-8 transition-all duration-700 delay-500"
        :class="showStats ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-4'"
      >
        <div class="grid grid-cols-2 gap-6">
          <div>
            <div class="flex justify-between text-sm mb-2">
              <span class="text-text-muted">⚡ {{ t('welcome.energy') }}</span>
              <span class="text-status-warning font-medium">{{ player?.energy?.toFixed(0) ?? 100 }}</span>
            </div>
            <div class="progress-bar progress-energy">
              <div class="progress-bar-fill" :style="{ width: `${player?.energy ?? 100}%` }"></div>
            </div>
          </div>
          <div>
            <div class="flex justify-between text-sm mb-2">
              <span class="text-text-muted">📡 {{ t('welcome.internet') }}</span>
              <span class="text-accent-tertiary font-medium">{{ player?.internet?.toFixed(0) ?? 100 }}</span>
            </div>
            <div class="progress-bar progress-internet">
              <div class="progress-bar-fill" :style="{ width: `${player?.internet ?? 100}%` }"></div>
            </div>
          </div>
        </div>
      </div>

      <!-- Botón de entrada -->
      <div
        class="transition-all duration-700 delay-700"
        :class="showButton ? 'opacity-100 scale-100' : 'opacity-0 scale-90'"
      >
        <button
          @click="enterGame"
          class="btn-primary text-lg px-12 py-4 relative overflow-hidden group"
        >
          <span class="relative z-10">⛏️ {{ t('welcome.enterGame') }}</span>
          <div class="absolute inset-0 bg-white/20 transform -skew-x-12 -translate-x-full group-hover:translate-x-full transition-transform duration-500"></div>
        </button>

        <p class="text-text-muted text-xs mt-4">
          {{ t('welcome.pressContinue') }}
        </p>
      </div>
    </div>
  </div>
</template>
