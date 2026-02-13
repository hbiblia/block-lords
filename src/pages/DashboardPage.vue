<script setup lang="ts">
import { ref, onMounted, onUnmounted, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAuthStore } from '@/stores/auth';
import { getPlayerMiningStats, getPlayerTransactions, getNetworkStats } from '@/utils/api';

const { t } = useI18n();
const authStore = useAuthStore();

const player = computed(() => authStore.player);
const loading = ref(true);

// Intervalo de actualización: cada 1 minuto (igual que heartbeat)
const REFRESH_INTERVAL = 60 * 1000;
let refreshInterval: ReturnType<typeof setInterval> | null = null;

const miningStats = ref({
  blocksMined: 0,
  totalCryptoMined: 0,
  currentHashrate: 0,
  activeRigs: 0,
});

const networkStats = ref({
  difficulty: 0,
  hashrate: 0,
  latestBlock: null as any,
});

const recentActivity = ref<Array<{
  type: string;
  description: string;
  time: string;
}>>([]);

// Función para cargar/actualizar estadísticas
async function loadStats() {
  try {
    const [statsData, transactionsData, networkData] = await Promise.all([
      getPlayerMiningStats(authStore.player!.id),
      getPlayerTransactions(authStore.player!.id, 5),
      getNetworkStats(),
    ]);

    miningStats.value = statsData;
    networkStats.value = networkData;

    recentActivity.value = (transactionsData ?? []).map((tx: any) => ({
      type: tx.type,
      description: tx.description,
      time: new Date(tx.created_at).toLocaleString(),
    }));
  } catch (e) {
    console.error('Error loading dashboard:', e);
  }
}

// Iniciar actualización periódica
function startRefresh() {
  if (refreshInterval) return;
  refreshInterval = setInterval(() => {
    if (authStore.isAuthenticated) {
      loadStats();
    }
  }, REFRESH_INTERVAL);
}

// Detener actualización periódica
function stopRefresh() {
  if (refreshInterval) {
    clearInterval(refreshInterval);
    refreshInterval = null;
  }
}

onMounted(async () => {
  await loadStats();
  loading.value = false;
  startRefresh();
});

onUnmounted(() => {
  stopRefresh();
});

function getRankColor(score: number): string {
  if (score >= 85) return 'text-rank-diamond';
  if (score >= 70) return 'text-rank-platinum';
  if (score >= 50) return 'text-rank-gold';
  if (score >= 30) return 'text-rank-silver';
  return 'text-rank-bronze';
}

function getRankName(score: number): string {
  if (score >= 85) return t('dashboard.ranks.diamond');
  if (score >= 70) return t('dashboard.ranks.platinum');
  if (score >= 50) return t('dashboard.ranks.gold');
  if (score >= 30) return t('dashboard.ranks.silver');
  return t('dashboard.ranks.bronze');
}
</script>

<template>
  <div>
    <h1 class="text-2xl font-display font-bold mb-6">
      <span class="gradient-text">{{ t('dashboard.title') }}</span>
    </h1>

    <div v-if="loading" class="text-center py-12 text-text-muted">
      {{ t('common.loading') }}
    </div>

    <div v-else class="grid lg:grid-cols-3 gap-6">
      <div class="lg:col-span-2 space-y-6">
        <!-- Balances -->
        <div class="grid sm:grid-cols-2 gap-4">
          <div class="card">
            <div class="flex items-center gap-3 mb-3">
              <div class="w-10 h-10 rounded-xl bg-status-warning/20 flex items-center justify-center text-xl">
                🪙
              </div>
              <span class="text-text-muted">GameCoin</span>
            </div>
            <div class="text-3xl font-bold text-status-warning">
              {{ player?.gamecoin_balance?.toFixed(2) ?? '0.00' }}
            </div>
          </div>
          <div class="card">
            <div class="flex items-center gap-3 mb-3">
              <div class="w-10 h-10 rounded-xl bg-accent-tertiary/20 flex items-center justify-center text-xl">
                ₿
              </div>
              <span class="text-text-muted">BLC</span>
            </div>
            <div class="text-3xl font-bold text-accent-tertiary">
              {{ player?.crypto_balance?.toFixed(4) ?? '0.0000' }}
            </div>
          </div>
        </div>

        <!-- Mining Stats -->
        <div class="card">
          <h2 class="text-lg font-semibold mb-4">{{ t('dashboard.miningStats') }}</h2>
          <div class="grid grid-cols-2 sm:grid-cols-4 gap-4">
            <div class="text-center p-4 bg-bg-secondary rounded-xl">
              <div class="text-2xl font-bold text-white">{{ miningStats.blocksMined ?? 0 }}</div>
              <div class="text-xs text-text-muted mt-1">{{ t('dashboard.blocksMined') }}</div>
            </div>
            <div class="text-center p-4 bg-bg-secondary rounded-xl">
              <div class="text-2xl font-bold text-accent-tertiary">{{ (miningStats.totalCryptoMined ?? 0).toFixed(2) }}</div>
              <div class="text-xs text-text-muted mt-1">{{ t('dashboard.totalCrypto') }}</div>
            </div>
            <div class="text-center p-4 bg-bg-secondary rounded-xl">
              <div class="text-2xl font-bold text-accent-primary">{{ (miningStats.currentHashrate ?? 0).toFixed(0) }}</div>
              <div class="text-xs text-text-muted mt-1">{{ t('dashboard.hashrate') }}</div>
            </div>
            <div class="text-center p-4 bg-bg-secondary rounded-xl">
              <div class="text-2xl font-bold text-status-success">{{ miningStats.activeRigs ?? 0 }}</div>
              <div class="text-xs text-text-muted mt-1">{{ t('dashboard.activeRigs') }}</div>
            </div>
          </div>
        </div>

        <!-- Recent Activity -->
        <div class="card">
          <h2 class="text-lg font-semibold mb-4">{{ t('dashboard.recentActivity') }}</h2>
          <div v-if="recentActivity.length === 0" class="text-center text-text-muted py-8">
            {{ t('dashboard.noActivity') }}
          </div>
          <div v-else class="space-y-1">
            <div
              v-for="(activity, index) in recentActivity"
              :key="index"
              class="flex items-center justify-between p-3 rounded-lg hover:bg-bg-secondary transition-colors"
            >
              <div>
                <div class="text-sm text-white">{{ activity.description }}</div>
                <div class="text-xs text-text-muted">{{ activity.time }}</div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Sidebar -->
      <div class="space-y-6">
        <div class="card">
          <h2 class="text-lg font-semibold mb-4">{{ t('dashboard.reputation') }}</h2>
          <div class="text-center">
            <div
              class="text-5xl font-bold mb-2"
              :class="getRankColor(player?.reputation_score ?? 50)"
            >
              {{ player?.reputation_score ?? 50 }}
            </div>
            <div
              class="text-sm font-semibold mb-4"
              :class="getRankColor(player?.reputation_score ?? 50)"
            >
              {{ getRankName(player?.reputation_score ?? 50) }}
            </div>
            <div class="progress-bar">
              <div
                class="progress-bar-fill"
                style="background: linear-gradient(90deg, #f59e0b 0%, #d97706 100%);"
                :style="{ width: `${player?.reputation_score ?? 50}%` }"
              ></div>
            </div>
          </div>
        </div>

        <div class="card">
          <h2 class="text-lg font-semibold mb-4">{{ t('dashboard.quickActions') }}</h2>
          <div class="space-y-3">
            <RouterLink to="/mining" class="btn-primary w-full text-center block">
              ⛏️ {{ t('dashboard.goToMining') }}
            </RouterLink>
            <RouterLink to="/market" class="btn-secondary w-full text-center block">
              💱 {{ t('dashboard.goToMarket') }}
            </RouterLink>
          </div>
        </div>

        <div class="card">
          <h2 class="text-lg font-semibold mb-4">{{ t('dashboard.networkStatus') }}</h2>
          <div class="space-y-3">
            <div class="flex justify-between items-center p-3 bg-bg-secondary rounded-lg">
              <span class="text-text-muted text-sm">{{ t('dashboard.difficulty') }}</span>
              <span class="font-mono font-medium">{{ (networkStats.difficulty ?? 0).toLocaleString() }}</span>
            </div>
            <div class="flex justify-between items-center p-3 bg-bg-secondary rounded-lg">
              <span class="text-text-muted text-sm">{{ t('dashboard.totalHashrate') }}</span>
              <span class="font-mono font-medium">{{ (networkStats.hashrate ?? 0).toLocaleString() }} H/s</span>
            </div>
            <div class="flex justify-between items-center p-3 bg-bg-secondary rounded-lg">
              <span class="text-text-muted text-sm">{{ t('dashboard.lastBlock') }}</span>
              <span class="font-mono font-medium text-accent-primary">#{{ networkStats.latestBlock?.height ?? '-' }}</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
