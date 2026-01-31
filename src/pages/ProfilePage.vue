<script setup lang="ts">
import { ref, onMounted, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAuthStore } from '@/stores/auth';

const { t } = useI18n();
const authStore = useAuthStore();

const loading = ref(true);
const reputation = ref<{
  score: number;
  rank: { name: string; color: string; benefits: string[] };
  badges: string[];
  recentEvents: any[];
}>({
  score: 50,
  rank: { name: 'Oro', color: '#FFD700', benefits: [] },
  badges: [],
  recentEvents: [],
});

const tradeHistory = ref<any[]>([]);

const player = computed(() => authStore.player);

async function loadData() {
  try {
    // Load reputation
    const repResponse = await fetch('/api/player/reputation', {
      headers: { 'Authorization': `Bearer ${authStore.token}` },
    });
    if (repResponse.ok) {
      reputation.value = await repResponse.json();
    }

    // Load trade history
    const tradesResponse = await fetch('/api/market/trades?limit=10', {
      headers: { 'Authorization': `Bearer ${authStore.token}` },
    });
    if (tradesResponse.ok) {
      tradeHistory.value = await tradesResponse.json();
    }
  } catch (e) {
    console.error('Error loading profile:', e);
  } finally {
    loading.value = false;
  }
}

onMounted(loadData);
</script>

<template>
  <div>
    <h1 class="text-2xl text-arcade-primary mb-6">{{ t('profile.title') }}</h1>

    <div v-if="loading" class="text-center py-12 text-gray-400">
      {{ t('common.loading') }}
    </div>

    <div v-else class="grid lg:grid-cols-3 gap-6">
      <!-- Profile Info -->
      <div class="lg:col-span-2 space-y-6">
        <!-- Basic Info -->
        <div class="arcade-panel">
          <h2 class="text-lg text-arcade-primary mb-4">{{ t('profile.information') }}</h2>
          <div class="grid sm:grid-cols-2 gap-4">
            <div>
              <div class="text-sm text-gray-400">{{ t('profile.username') }}</div>
              <div class="text-xl font-bold">{{ player?.username }}</div>
            </div>
            <div>
              <div class="text-sm text-gray-400">{{ t('profile.email') }}</div>
              <div>{{ player?.email }}</div>
            </div>
            <div>
              <div class="text-sm text-gray-400">{{ t('profile.region') }}</div>
              <div>{{ player?.region ?? 'Global' }}</div>
            </div>
            <div>
              <div class="text-sm text-gray-400">{{ t('profile.memberSince') }}</div>
              <div>{{ t('profile.january2024') }}</div>
            </div>
          </div>
        </div>

        <!-- Balances -->
        <div class="arcade-panel">
          <h2 class="text-lg text-arcade-primary mb-4">{{ t('profile.balances') }}</h2>
          <div class="grid sm:grid-cols-2 gap-4">
            <div class="p-4 bg-arcade-bg rounded">
              <div class="text-sm text-gray-400">GameCoin</div>
              <div class="text-2xl text-arcade-warning font-bold">
                🪙 {{ player?.gamecoin_balance?.toFixed(2) }}
              </div>
            </div>
            <div class="p-4 bg-arcade-bg rounded">
              <div class="text-sm text-gray-400">CryptoCoin</div>
              <div class="text-2xl text-arcade-secondary font-bold">
                ₿ {{ player?.crypto_balance?.toFixed(4) }}
              </div>
            </div>
          </div>
        </div>

        <!-- Trade History -->
        <div class="arcade-panel">
          <h2 class="text-lg text-arcade-primary mb-4">{{ t('profile.tradeHistory') }}</h2>

          <div v-if="tradeHistory.length === 0" class="text-center py-4 text-gray-400">
            {{ t('profile.noTrades') }}
          </div>

          <div v-else class="space-y-2">
            <div
              v-for="trade in tradeHistory"
              :key="trade.id"
              class="flex items-center justify-between py-2 border-b border-arcade-border last:border-0 text-sm"
            >
              <div>
                <span
                  :class="trade.buyer_id === player?.id ? 'text-arcade-success' : 'text-arcade-danger'"
                >
                  {{ trade.buyer_id === player?.id ? t('profile.buy') : t('profile.sell') }}
                </span>
                <span class="text-gray-400 ml-2">
                  {{ trade.quantity }} {{ trade.item_type }}
                </span>
              </div>
              <div class="text-right">
                <div>{{ trade.total_value.toFixed(4) }} GC</div>
                <div class="text-xs text-gray-500">
                  {{ new Date(trade.created_at).toLocaleDateString() }}
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Reputation Sidebar -->
      <div class="space-y-6">
        <!-- Reputation Card -->
        <div class="arcade-panel text-center">
          <h2 class="text-lg text-arcade-primary mb-4">{{ t('profile.reputation') }}</h2>

          <div
            class="text-6xl font-bold mb-2"
            :style="{ color: reputation.rank.color }"
          >
            {{ reputation.score }}
          </div>

          <div
            class="text-xl font-bold mb-4"
            :style="{ color: reputation.rank.color }"
          >
            {{ reputation.rank.name }}
          </div>

          <!-- Progress to next rank -->
          <div class="mb-4">
            <div class="h-3 bg-arcade-bg rounded-full overflow-hidden">
              <div
                class="h-full transition-all bg-gradient-to-r from-arcade-primary to-arcade-secondary"
                :style="{ width: `${reputation.score}%` }"
              ></div>
            </div>
          </div>

          <!-- Benefits -->
          <div v-if="reputation.rank.benefits.length > 0" class="text-left">
            <div class="text-sm text-gray-400 mb-2">{{ t('profile.activeBenefits') }}</div>
            <ul class="text-xs space-y-1">
              <li
                v-for="benefit in reputation.rank.benefits"
                :key="benefit"
                class="text-arcade-success"
              >
                ✓ {{ benefit }}
              </li>
            </ul>
          </div>
        </div>

        <!-- Badges -->
        <div class="arcade-panel">
          <h2 class="text-lg text-arcade-primary mb-4">{{ t('profile.badges') }}</h2>

          <div v-if="reputation.badges.length === 0" class="text-center text-gray-400 text-sm">
            {{ t('profile.noBadges') }}
          </div>

          <div v-else class="flex flex-wrap gap-2">
            <span
              v-for="badge in reputation.badges"
              :key="badge"
              class="px-3 py-1 bg-arcade-bg rounded text-sm"
            >
              {{ badge }}
            </span>
          </div>
        </div>

        <!-- Recent Reputation Events -->
        <div class="arcade-panel">
          <h2 class="text-lg text-arcade-primary mb-4">{{ t('profile.recentEvents') }}</h2>

          <div v-if="reputation.recentEvents.length === 0" class="text-center text-gray-400 text-sm">
            {{ t('profile.noEvents') }}
          </div>

          <div v-else class="space-y-2 text-sm">
            <div
              v-for="event in reputation.recentEvents.slice(0, 5)"
              :key="event.id"
              class="flex items-center justify-between"
            >
              <span class="text-gray-400">{{ event.reason }}</span>
              <span :class="event.delta > 0 ? 'text-arcade-success' : 'text-arcade-danger'">
                {{ event.delta > 0 ? '+' : '' }}{{ event.delta }}
              </span>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
