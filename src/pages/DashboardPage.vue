<script setup lang="ts">
import { ref, onMounted, computed } from 'vue';
import { useAuthStore } from '@/stores/auth';
import { getPlayerMiningStats, getPlayerTransactions, getNetworkStats } from '@/utils/api';

const authStore = useAuthStore();

const player = computed(() => authStore.player);
const loading = ref(true);

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

onMounted(async () => {
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
  } finally {
    loading.value = false;
  }
});

function getRankColor(score: number): string {
  if (score >= 85) return 'text-rank-diamond';
  if (score >= 70) return 'text-rank-platinum';
  if (score >= 50) return 'text-rank-gold';
  if (score >= 30) return 'text-rank-silver';
  return 'text-rank-bronze';
}

function getRankName(score: number): string {
  if (score >= 85) return 'Diamante';
  if (score >= 70) return 'Platino';
  if (score >= 50) return 'Oro';
  if (score >= 30) return 'Plata';
  return 'Bronce';
}
</script>

<template>
  <div>
    <h1 class="text-2xl text-arcade-primary mb-6">Dashboard</h1>

    <div v-if="loading" class="text-center py-12 text-gray-400">
      Cargando...
    </div>

    <div v-else class="grid lg:grid-cols-3 gap-6">
      <div class="lg:col-span-2 space-y-6">
        <!-- Balances -->
        <div class="grid sm:grid-cols-2 gap-4">
          <div class="arcade-panel">
            <div class="text-sm text-gray-400 mb-1">GameCoin</div>
            <div class="text-3xl text-arcade-warning font-bold">
              🪙 {{ player?.gamecoin_balance?.toFixed(2) ?? '0.00' }}
            </div>
          </div>
          <div class="arcade-panel">
            <div class="text-sm text-gray-400 mb-1">CryptoCoin</div>
            <div class="text-3xl text-arcade-secondary font-bold">
              ₿ {{ player?.crypto_balance?.toFixed(4) ?? '0.0000' }}
            </div>
          </div>
        </div>

        <!-- Mining Stats -->
        <div class="arcade-panel">
          <h2 class="text-lg text-arcade-primary mb-4">Estadísticas de Minería</h2>
          <div class="grid grid-cols-2 sm:grid-cols-4 gap-4">
            <div class="text-center">
              <div class="text-2xl font-bold">{{ miningStats.blocksMined ?? 0 }}</div>
              <div class="text-xs text-gray-400">Bloques Minados</div>
            </div>
            <div class="text-center">
              <div class="text-2xl font-bold">{{ (miningStats.totalCryptoMined ?? 0).toFixed(2) }}</div>
              <div class="text-xs text-gray-400">Total Crypto</div>
            </div>
            <div class="text-center">
              <div class="text-2xl font-bold">{{ (miningStats.currentHashrate ?? 0).toFixed(0) }}</div>
              <div class="text-xs text-gray-400">Hashrate</div>
            </div>
            <div class="text-center">
              <div class="text-2xl font-bold">{{ miningStats.activeRigs ?? 0 }}</div>
              <div class="text-xs text-gray-400">Rigs Activos</div>
            </div>
          </div>
        </div>

        <!-- Recent Activity -->
        <div class="arcade-panel">
          <h2 class="text-lg text-arcade-primary mb-4">Actividad Reciente</h2>
          <div v-if="recentActivity.length === 0" class="text-center text-gray-400 py-4">
            Sin actividad reciente
          </div>
          <div v-else class="space-y-3">
            <div
              v-for="(activity, index) in recentActivity"
              :key="index"
              class="flex items-center justify-between py-2 border-b border-arcade-border last:border-0"
            >
              <div>
                <div class="text-sm">{{ activity.description }}</div>
                <div class="text-xs text-gray-500">{{ activity.time }}</div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Sidebar -->
      <div class="space-y-6">
        <div class="arcade-panel">
          <h2 class="text-lg text-arcade-primary mb-4">Reputación</h2>
          <div class="text-center">
            <div
              class="text-4xl font-bold mb-2"
              :class="getRankColor(player?.reputation_score ?? 50)"
            >
              {{ player?.reputation_score ?? 50 }}
            </div>
            <div
              class="text-sm font-bold"
              :class="getRankColor(player?.reputation_score ?? 50)"
            >
              {{ getRankName(player?.reputation_score ?? 50) }}
            </div>
            <div class="mt-4 h-2 bg-arcade-bg rounded-full overflow-hidden">
              <div
                class="h-full bg-gradient-to-r from-arcade-primary to-arcade-secondary"
                :style="{ width: `${player?.reputation_score ?? 50}%` }"
              ></div>
            </div>
          </div>
        </div>

        <div class="arcade-panel">
          <h2 class="text-lg text-arcade-primary mb-4">Acciones Rápidas</h2>
          <div class="space-y-2">
            <RouterLink to="/mining" class="arcade-button w-full text-center block">
              ⛏️ Ir a Minería
            </RouterLink>
            <RouterLink to="/market" class="arcade-button-secondary w-full text-center block">
              💱 Ir al Mercado
            </RouterLink>
          </div>
        </div>

        <div class="arcade-panel">
          <h2 class="text-lg text-arcade-primary mb-4">Estado de la Red</h2>
          <div class="space-y-2 text-sm">
            <div class="flex justify-between">
              <span class="text-gray-400">Dificultad</span>
              <span>{{ (networkStats.difficulty ?? 0).toLocaleString() }}</span>
            </div>
            <div class="flex justify-between">
              <span class="text-gray-400">Hashrate Total</span>
              <span>{{ (networkStats.hashrate ?? 0).toLocaleString() }} H/s</span>
            </div>
            <div class="flex justify-between">
              <span class="text-gray-400">Último Bloque</span>
              <span>#{{ networkStats.latestBlock?.height ?? '-' }}</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
