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
  volume24h: number;
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

function formatNumber(num: number): string {
  if (num >= 1000000) {
    return (num / 1000000).toFixed(1) + 'M';
  } else if (num >= 1000) {
    return (num / 1000).toFixed(1) + 'K';
  }
  return num.toLocaleString();
}

function formatVolume(num: number): string {
  if (num >= 1000000) {
    return '$' + (num / 1000000).toFixed(1) + 'M';
  } else if (num >= 1000) {
    return '$' + (num / 1000).toFixed(1) + 'K';
  }
  return '$' + num.toFixed(0);
}

// Realtime subscription para network_stats
const networkStatsChannel = supabase
  .channel('home_network_stats')
  .on(
    'postgres_changes',
    {
      event: 'UPDATE',
      schema: 'public',
      table: 'network_stats',
    },
    (payload: { new: { difficulty?: number } }) => {
      if (stats.value && payload.new) {
        stats.value.difficulty = payload.new.difficulty ?? stats.value.difficulty;
      }
    }
  );

// Realtime subscription para blocks (nuevos bloques)
const blocksChannel = supabase
  .channel('home_blocks')
  .on(
    'postgres_changes',
    {
      event: 'INSERT',
      schema: 'public',
      table: 'blocks',
    },
    () => {
      if (stats.value) {
        stats.value.totalBlocks++;
      }
    }
  );

// Realtime subscription para players (nuevos jugadores)
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
  networkStatsChannel.subscribe();
  blocksChannel.subscribe();
  playersChannel.subscribe();
});

onUnmounted(() => {
  supabase.removeChannel(networkStatsChannel);
  supabase.removeChannel(blocksChannel);
  supabase.removeChannel(playersChannel);
});
</script>

<template>
  <div class="py-12">
    <!-- Hero Section -->
    <div class="text-center mb-20">
      <div class="inline-block mb-6">
        <span class="badge-primary text-sm">{{ t('home.badge') }}</span>
      </div>
      <h1 class="font-display text-4xl md:text-6xl font-bold mb-6">
        <span class="gradient-text">{{ t('home.title') }}</span>
      </h1>
      <p class="text-xl text-text-secondary max-w-2xl mx-auto mb-10">
        {{ t('home.subtitle') }}
      </p>

      <div v-if="!isAuthenticated" class="flex justify-center">
        <RouterLink to="/login" class="btn-primary text-lg px-8 py-4">
          {{ t('home.startMining') }}
        </RouterLink>
      </div>
      <div v-else>
        <RouterLink to="/mining" class="btn-primary text-lg px-8 py-4">
          {{ t('home.startMining') }}
        </RouterLink>
      </div>
    </div>

    <!-- Features -->
    <div class="grid md:grid-cols-3 gap-6 mb-20">
      <div class="card-hover group">
        <div class="w-14 h-14 rounded-xl bg-gradient-primary flex items-center justify-center text-2xl mb-4 group-hover:scale-110 transition-transform">
          ⛏️
        </div>
        <h3 class="text-xl font-semibold text-white mb-3">{{ t('home.features.mining.title') }}</h3>
        <p class="text-text-secondary">
          {{ t('home.features.mining.description') }}
        </p>
      </div>

      <div class="card-hover group">
        <div class="w-14 h-14 rounded-xl bg-gradient-secondary flex items-center justify-center text-2xl mb-4 group-hover:scale-110 transition-transform">
          💰
        </div>
        <h3 class="text-xl font-semibold text-white mb-3">{{ t('home.features.economy.title') }}</h3>
        <p class="text-text-secondary">
          {{ t('home.features.economy.description') }}
        </p>
      </div>

      <div class="card-hover group">
        <div class="w-14 h-14 rounded-xl bg-gradient-to-br from-status-warning to-orange-500 flex items-center justify-center text-2xl mb-4 group-hover:scale-110 transition-transform">
          ⭐
        </div>
        <h3 class="text-xl font-semibold text-white mb-3">{{ t('home.features.reputation.title') }}</h3>
        <p class="text-text-secondary">
          {{ t('home.features.reputation.description') }}
        </p>
      </div>
    </div>

    <!-- How it Works -->
    <div class="card max-w-5xl mx-auto mb-20">
      <h2 class="text-2xl font-display font-bold text-center mb-8">
        <span class="gradient-text">{{ t('home.howItWorks.title') }}</span>
      </h2>

      <div class="grid md:grid-cols-4 gap-4">
        <div class="relative p-5 rounded-xl bg-bg-secondary border border-border/50">
          <div class="absolute -top-3 -left-3 w-8 h-8 rounded-lg bg-gradient-primary flex items-center justify-center text-sm font-bold">
            1
          </div>
          <h4 class="font-semibold text-white mt-2 mb-2">{{ t('home.howItWorks.step1.title') }}</h4>
          <p class="text-sm text-text-muted">
            {{ t('home.howItWorks.step1.description') }}
          </p>
        </div>

        <div class="relative p-5 rounded-xl bg-bg-secondary border border-border/50">
          <div class="absolute -top-3 -left-3 w-8 h-8 rounded-lg bg-gradient-primary flex items-center justify-center text-sm font-bold">
            2
          </div>
          <h4 class="font-semibold text-white mt-2 mb-2">{{ t('home.howItWorks.step2.title') }}</h4>
          <p class="text-sm text-text-muted">
            {{ t('home.howItWorks.step2.description') }}
          </p>
        </div>

        <div class="relative p-5 rounded-xl bg-bg-secondary border border-border/50">
          <div class="absolute -top-3 -left-3 w-8 h-8 rounded-lg bg-gradient-primary flex items-center justify-center text-sm font-bold">
            3
          </div>
          <h4 class="font-semibold text-white mt-2 mb-2">{{ t('home.howItWorks.step3.title') }}</h4>
          <p class="text-sm text-text-muted">
            {{ t('home.howItWorks.step3.description') }}
          </p>
        </div>

        <div class="relative p-5 rounded-xl bg-bg-secondary border border-border/50">
          <div class="absolute -top-3 -left-3 w-8 h-8 rounded-lg bg-gradient-primary flex items-center justify-center text-sm font-bold">
            4
          </div>
          <h4 class="font-semibold text-white mt-2 mb-2">{{ t('home.howItWorks.step4.title') }}</h4>
          <p class="text-sm text-text-muted">
            {{ t('home.howItWorks.step4.description') }}
          </p>
        </div>
      </div>
    </div>

    <!-- Live Stats Preview -->
    <div class="grid md:grid-cols-4 gap-4 max-w-4xl mx-auto">
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
          <template v-else>{{ formatVolume(stats?.volume24h ?? 0) }}</template>
        </div>
        <div class="stat-label">{{ t('home.stats.volume24h') }}</div>
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
</template>
