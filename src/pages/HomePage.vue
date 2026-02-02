<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAuthStore } from '@/stores/auth';
import { getHomeStats, getRecentBlocks, getMiningLeaderboard } from '@/utils/api';
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

// Top miners and recent blocks
interface TopMiner {
  username: string;
  total_blocks: number;
  total_crypto: number;
}

interface RecentBlock {
  id: string;
  miner_username: string;
  reward: number;
  created_at: string;
}

const topMiners = ref<TopMiner[]>([]);
const recentBlocks = ref<RecentBlock[]>([]);
const loadingMiners = ref(true);
const loadingBlocks = ref(true);

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

async function loadTopMiners() {
  try {
    const data = await getMiningLeaderboard(5);
    if (data) {
      topMiners.value = data;
    }
  } catch (e) {
    console.error('Error loading top miners:', e);
  } finally {
    loadingMiners.value = false;
  }
}

async function loadRecentBlocks() {
  try {
    const data = await getRecentBlocks(5);
    if (data) {
      recentBlocks.value = data;
    }
  } catch (e) {
    console.error('Error loading recent blocks:', e);
  } finally {
    loadingBlocks.value = false;
  }
}

function formatTimeAgo(dateStr: string): string {
  const date = new Date(dateStr);
  const now = new Date();
  const seconds = Math.floor((now.getTime() - date.getTime()) / 1000);

  if (seconds < 60) return t('home.timeAgo.seconds', { n: seconds });
  if (seconds < 3600) return t('home.timeAgo.minutes', { n: Math.floor(seconds / 60) });
  if (seconds < 86400) return t('home.timeAgo.hours', { n: Math.floor(seconds / 3600) });
  return t('home.timeAgo.days', { n: Math.floor(seconds / 86400) });
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
  loadTopMiners();
  loadRecentBlocks();
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
    <div class="grid md:grid-cols-4 gap-4 max-w-4xl mx-auto mb-20">
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

    <!-- Live Activity Section -->
    <div class="grid md:grid-cols-2 gap-6 max-w-5xl mx-auto">
      <!-- Top Miners -->
      <div class="card">
        <div class="flex items-center gap-3 mb-4">
          <div class="w-10 h-10 rounded-xl bg-gradient-primary flex items-center justify-center text-xl">
            🏆
          </div>
          <h3 class="text-lg font-display font-bold">{{ t('home.topMiners.title') }}</h3>
        </div>

        <div v-if="loadingMiners" class="space-y-3">
          <div v-for="i in 5" :key="i" class="h-12 bg-bg-secondary rounded-lg animate-pulse"></div>
        </div>

        <div v-else-if="topMiners.length === 0" class="text-center py-8 text-text-muted">
          {{ t('home.topMiners.noData') }}
        </div>

        <div v-else class="space-y-2">
          <div
            v-for="(miner, index) in topMiners"
            :key="miner.username"
            class="flex items-center gap-3 p-3 rounded-lg bg-bg-secondary hover:bg-bg-tertiary transition-colors"
          >
            <div
              class="w-8 h-8 rounded-lg flex items-center justify-center text-sm font-bold"
              :class="{
                'bg-gradient-to-br from-yellow-400 to-amber-500 text-black': index === 0,
                'bg-gradient-to-br from-gray-300 to-gray-400 text-black': index === 1,
                'bg-gradient-to-br from-orange-400 to-orange-600 text-black': index === 2,
                'bg-bg-tertiary text-text-muted': index > 2
              }"
            >
              {{ index + 1 }}
            </div>
            <div class="flex-1 min-w-0">
              <div class="font-medium text-white truncate">{{ miner.username }}</div>
              <div class="text-xs text-text-muted">{{ formatNumber(miner.total_blocks) }} {{ t('home.topMiners.blocks') }}</div>
            </div>
            <div class="text-right">
              <div class="text-sm font-bold text-accent-primary">💎 {{ miner.total_crypto?.toFixed(2) ?? '0.00' }}</div>
            </div>
          </div>
        </div>

        <RouterLink
          to="/leaderboard"
          class="block text-center text-sm text-accent-primary hover:text-accent-primary/80 mt-4 py-2"
        >
          {{ t('home.topMiners.viewAll') }} →
        </RouterLink>
      </div>

      <!-- Recent Blocks -->
      <div class="card">
        <div class="flex items-center gap-3 mb-4">
          <div class="w-10 h-10 rounded-xl bg-gradient-secondary flex items-center justify-center text-xl">
            ⛏️
          </div>
          <h3 class="text-lg font-display font-bold">{{ t('home.recentBlocks.title') }}</h3>
        </div>

        <div v-if="loadingBlocks" class="space-y-3">
          <div v-for="i in 5" :key="i" class="h-12 bg-bg-secondary rounded-lg animate-pulse"></div>
        </div>

        <div v-else-if="recentBlocks.length === 0" class="text-center py-8 text-text-muted">
          {{ t('home.recentBlocks.noData') }}
        </div>

        <div v-else class="space-y-2">
          <div
            v-for="block in recentBlocks"
            :key="block.id"
            class="flex items-center gap-3 p-3 rounded-lg bg-bg-secondary hover:bg-bg-tertiary transition-colors"
          >
            <div class="w-8 h-8 rounded-lg bg-accent-tertiary/20 flex items-center justify-center text-accent-tertiary">
              #
            </div>
            <div class="flex-1 min-w-0">
              <div class="font-medium text-white truncate">{{ block.miner_username }}</div>
              <div class="text-xs text-text-muted">{{ formatTimeAgo(block.created_at) }}</div>
            </div>
            <div class="text-right">
              <div class="text-sm font-bold text-status-warning">+{{ block.reward?.toFixed(4) ?? '0.0000' }} 💎</div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
