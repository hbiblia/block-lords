<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAuthStore } from '@/stores/auth';
import { getHomeStats } from '@/utils/api';
import { supabase } from '@/utils/supabase';

const { t } = useI18n();

const authStore = useAuthStore();
const isAuthenticated = computed(() => authStore.isAuthenticated);

const stats = ref<{
  totalPlayers: number;
  onlinePlayers: number;
  totalBlocks: number;
  totalCryptoEmitted: number;
  difficulty: number;
} | null>(null);

const loadingStats = ref(true);

async function loadStats() {
  try {
    const data = await getHomeStats();
    if (data) {
      stats.value = data;
    }
  } catch (e) {
    console.error('Error loading home stats:', e);
  } finally {
    loadingStats.value = false;
  }
}

function formatNumber(num: number | undefined | null): string {
  if (num == null) return '0';
  if (num >= 1000000) {
    return (num / 1000000).toFixed(1) + 'M';
  } else if (num >= 1000) {
    return (num / 1000).toFixed(1) + 'K';
  }
  return num.toLocaleString();
}

function formatCryptoStat(num: number | undefined | null): string {
  if (num == null) return '0 ₿';
  if (num >= 1000000) {
    return (num / 1000000).toFixed(1) + 'M ₿';
  } else if (num >= 1000) {
    return (num / 1000).toFixed(1) + 'K ₿';
  }
  return num.toFixed(2) + ' ₿';
}

// Listen to global channel events (avoids duplicate realtime subscriptions)
function handleNetworkStats(e: Event) {
  const detail = (e as CustomEvent).detail;
  if (stats.value && detail) {
    stats.value.difficulty = detail.difficulty ?? stats.value.difficulty;
  }
}

function handleBlockMined() {
  if (stats.value) {
    stats.value.totalBlocks++;
  }
}

// Realtime subscription para players (nuevos jugadores) — no global equivalent
const playersChannel = supabase
  .channel('home_players')
  .on(
    'postgres_changes',
    {
      event: 'INSERT',
      schema: 'public',
      table: 'players',
    },
    () => {
      if (stats.value) {
        stats.value.totalPlayers++;
      }
    }
  )
  .on(
    'postgres_changes',
    {
      event: 'UPDATE',
      schema: 'public',
      table: 'players',
      filter: 'is_online=eq.true',
    },
    () => {
      // Recargar stats cuando cambia el estado online
      loadStats();
    }
  );

onMounted(() => {
  loadStats();
  window.addEventListener('network-stats-updated', handleNetworkStats);
  window.addEventListener('block-mined', handleBlockMined);
  playersChannel.subscribe();
});

onUnmounted(() => {
  window.removeEventListener('network-stats-updated', handleNetworkStats);
  window.removeEventListener('block-mined', handleBlockMined);
  supabase.removeChannel(playersChannel);
});
</script>

<template>
  <div class="pt-6 pb-4">
    <!-- Hero Section -->
    <div class="text-center mb-10">
      <div class="inline-block mb-3">
        <span class="badge-primary text-sm">{{ t('home.badge') }}</span>
      </div>
      <h1 class="font-display text-3xl md:text-5xl font-bold mb-4">
        <span class="gradient-text">{{ t('home.title') }}</span>
      </h1>
      <p class="text-lg text-text-secondary max-w-2xl mx-auto mb-6">
        {{ t('home.subtitle') }}
      </p>

      <div v-if="!isAuthenticated">
        <div v-if="!loadingStats && stats" class="flex justify-center items-center gap-2 mb-3">
          <span class="inline-block w-2 h-2 rounded-full bg-emerald-400 animate-pulse"></span>
          <span class="text-sm text-emerald-400 font-medium">
            {{ formatNumber(stats.onlinePlayers) }} {{ t('home.stats.onlinePlayers').toLowerCase() }}
          </span>
        </div>
        <div class="flex justify-center mb-6">
          <RouterLink to="/login" class="btn-primary px-6 py-3">
            {{ t('home.startMining') }}
          </RouterLink>
        </div>
      </div>
      <div v-else class="mb-6">
        <RouterLink to="/mining" class="btn-primary px-6 py-3">
          {{ t('home.startMining') }}
        </RouterLink>
      </div>

      <!-- Live Stats -->
      <div class="grid grid-cols-2 md:grid-cols-4 gap-3 max-w-3xl mx-auto">
        <div class="stat-card">
          <div class="stat-value gradient-text">
            <template v-if="loadingStats">...</template>
            <template v-else>{{ formatNumber(stats?.onlinePlayers ?? 0) }}</template>
          </div>
          <div class="stat-label">{{ t('home.stats.onlinePlayers') }}</div>
        </div>
        <div class="stat-card">
          <div class="stat-value text-accent-tertiary">
            <template v-if="loadingStats">...</template>
            <template v-else>{{ formatNumber(stats?.totalBlocks ?? 0) }}</template>
          </div>
          <div class="stat-label">{{ t('home.stats.blocksMined') }}</div>
        </div>
        <div class="stat-card">
          <div class="stat-value text-status-warning">
            <template v-if="loadingStats">...</template>
            <template v-else>{{ formatCryptoStat(stats?.totalCryptoEmitted ?? 0) }}</template>
          </div>
          <div class="stat-label">{{ t('home.stats.totalCryptoEmitted') }}</div>
        </div>
        <div class="stat-card">
          <div class="stat-value text-accent-secondary">
            <template v-if="loadingStats">...</template>
            <template v-else>{{ formatNumber(stats?.difficulty ?? 0) }}</template>
          </div>
          <div class="stat-label">{{ t('home.stats.difficulty') }}</div>
        </div>
      </div>
    </div>

    <!-- Features -->
    <div class="grid md:grid-cols-3 gap-4 mb-10">
      <div class="card-hover group p-4">
        <div class="w-10 h-10 rounded-lg bg-gradient-primary flex items-center justify-center text-xl mb-3 group-hover:scale-110 transition-transform">
          ⛏️
        </div>
        <h3 class="text-lg font-semibold text-white mb-2">{{ t('home.features.mining.title') }}</h3>
        <p class="text-sm text-text-secondary">
          {{ t('home.features.mining.description') }}
        </p>
      </div>

      <div class="card-hover group p-4">
        <div class="w-10 h-10 rounded-lg bg-gradient-secondary flex items-center justify-center text-xl mb-3 group-hover:scale-110 transition-transform">
          💰
        </div>
        <h3 class="text-lg font-semibold text-white mb-2">{{ t('home.features.economy.title') }}</h3>
        <p class="text-sm text-text-secondary">
          {{ t('home.features.economy.description') }}
        </p>
      </div>

      <div class="card-hover group p-4">
        <div class="w-10 h-10 rounded-lg bg-gradient-to-br from-status-warning to-orange-500 flex items-center justify-center text-xl mb-3 group-hover:scale-110 transition-transform">
          ⭐
        </div>
        <h3 class="text-lg font-semibold text-white mb-2">{{ t('home.features.reputation.title') }}</h3>
        <p class="text-sm text-text-secondary">
          {{ t('home.features.reputation.description') }}
        </p>
      </div>
    </div>

    <!-- How it Works -->
    <div class="card max-w-4xl mx-auto mb-10 p-5">
      <h2 class="text-xl font-display font-bold text-center mb-5">
        <span class="gradient-text">{{ t('home.howItWorks.title') }}</span>
      </h2>

      <div class="grid md:grid-cols-4 gap-3">
        <div class="relative p-4 rounded-lg bg-bg-secondary border border-border/50">
          <div class="absolute -top-2 -left-2 w-6 h-6 rounded-md bg-gradient-primary flex items-center justify-center text-xs font-bold">
            1
          </div>
          <h4 class="font-semibold text-white text-sm mt-1 mb-1">{{ t('home.howItWorks.step1.title') }}</h4>
          <p class="text-xs text-text-muted">
            {{ t('home.howItWorks.step1.description') }}
          </p>
        </div>

        <div class="relative p-4 rounded-lg bg-bg-secondary border border-border/50">
          <div class="absolute -top-2 -left-2 w-6 h-6 rounded-md bg-gradient-primary flex items-center justify-center text-xs font-bold">
            2
          </div>
          <h4 class="font-semibold text-white text-sm mt-1 mb-1">{{ t('home.howItWorks.step2.title') }}</h4>
          <p class="text-xs text-text-muted">
            {{ t('home.howItWorks.step2.description') }}
          </p>
        </div>

        <div class="relative p-4 rounded-lg bg-bg-secondary border border-border/50">
          <div class="absolute -top-2 -left-2 w-6 h-6 rounded-md bg-gradient-primary flex items-center justify-center text-xs font-bold">
            3
          </div>
          <h4 class="font-semibold text-white text-sm mt-1 mb-1">{{ t('home.howItWorks.step3.title') }}</h4>
          <p class="text-xs text-text-muted">
            {{ t('home.howItWorks.step3.description') }}
          </p>
        </div>

        <div class="relative p-4 rounded-lg bg-bg-secondary border border-border/50">
          <div class="absolute -top-2 -left-2 w-6 h-6 rounded-md bg-gradient-primary flex items-center justify-center text-xs font-bold">
            4
          </div>
          <h4 class="font-semibold text-white text-sm mt-1 mb-1">{{ t('home.howItWorks.step4.title') }}</h4>
          <p class="text-xs text-text-muted">
            {{ t('home.howItWorks.step4.description') }}
          </p>
        </div>
      </div>
    </div>
  </div>
</template>
