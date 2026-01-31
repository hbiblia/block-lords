<script setup lang="ts">
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAuthStore } from '@/stores/auth';

const { t } = useI18n();
const authStore = useAuthStore();

const loading = ref(true);
const activeTab = ref<'miners' | 'reputation' | 'traders'>('miners');

const leaderboard = ref<Array<{
  id: string;
  username: string;
  value: number;
  rank?: { name: string; color: string };
}>>([]);

async function loadData() {
  loading.value = true;

  try {
    let endpoint = '/api/mining/leaderboard';

    if (activeTab.value === 'reputation') {
      endpoint = '/api/player/leaderboard/reputation';
    }

    const response = await fetch(endpoint);
    if (response.ok) {
      const data = await response.json();

      if (activeTab.value === 'miners') {
        leaderboard.value = data.map((m: any) => ({
          id: m.id,
          username: m.username,
          value: m.blocksMined,
          hashrate: m.hashrate,
        }));
      } else if (activeTab.value === 'reputation') {
        leaderboard.value = data.map((p: any) => ({
          id: p.playerId,
          username: p.username,
          value: p.score,
          rank: p.rank,
        }));
      }
    }
  } catch (e) {
    console.error('Error loading leaderboard:', e);
  } finally {
    loading.value = false;
  }
}

function changeTab(tab: 'miners' | 'reputation' | 'traders') {
  activeTab.value = tab;
  loadData();
}

function getRankColor(position: number): string {
  if (position === 0) return 'text-yellow-400';
  if (position === 1) return 'text-gray-300';
  if (position === 2) return 'text-amber-600';
  return 'text-gray-400';
}

onMounted(loadData);
</script>

<template>
  <div>
    <h1 class="text-2xl text-arcade-primary mb-6">{{ t('leaderboard.title') }}</h1>

    <!-- Tabs -->
    <div class="flex gap-4 mb-6 border-b border-arcade-border">
      <button
        @click="changeTab('miners')"
        class="pb-2 px-4 transition-colors"
        :class="activeTab === 'miners' ? 'text-arcade-primary border-b-2 border-arcade-primary' : 'text-gray-400 hover:text-white'"
      >
        ⛏️ {{ t('leaderboard.topMiners') }}
      </button>
      <button
        @click="changeTab('reputation')"
        class="pb-2 px-4 transition-colors"
        :class="activeTab === 'reputation' ? 'text-arcade-primary border-b-2 border-arcade-primary' : 'text-gray-400 hover:text-white'"
      >
        ⭐ {{ t('leaderboard.reputation') }}
      </button>
      <button
        @click="changeTab('traders')"
        class="pb-2 px-4 transition-colors"
        :class="activeTab === 'traders' ? 'text-arcade-primary border-b-2 border-arcade-primary' : 'text-gray-400 hover:text-white'"
      >
        💰 {{ t('leaderboard.topTraders') }}
      </button>
    </div>

    <div v-if="loading" class="text-center py-12 text-gray-400">
      {{ t('common.loading') }}
    </div>

    <div v-else class="max-w-4xl mx-auto">
      <!-- Top 3 Podium -->
      <div class="grid grid-cols-3 gap-4 mb-8">
        <!-- 2nd Place -->
        <div v-if="leaderboard[1]" class="arcade-panel text-center mt-8">
          <div class="text-4xl mb-2">🥈</div>
          <div class="text-lg font-bold text-gray-300">{{ leaderboard[1].username }}</div>
          <div class="text-2xl font-bold text-arcade-secondary">
            {{ activeTab === 'reputation' ? leaderboard[1].value : leaderboard[1].value }}
          </div>
          <div class="text-xs text-gray-400">
            {{ activeTab === 'miners' ? t('leaderboard.blocks') : activeTab === 'reputation' ? t('leaderboard.points') : 'GC' }}
          </div>
        </div>

        <!-- 1st Place -->
        <div v-if="leaderboard[0]" class="arcade-panel text-center border-arcade-primary">
          <div class="text-5xl mb-2">🥇</div>
          <div class="text-xl font-bold text-yellow-400">{{ leaderboard[0].username }}</div>
          <div class="text-3xl font-bold text-arcade-primary">
            {{ leaderboard[0].value }}
          </div>
          <div class="text-xs text-gray-400">
            {{ activeTab === 'miners' ? t('leaderboard.blocks') : activeTab === 'reputation' ? t('leaderboard.points') : 'GC' }}
          </div>
        </div>

        <!-- 3rd Place -->
        <div v-if="leaderboard[2]" class="arcade-panel text-center mt-12">
          <div class="text-4xl mb-2">🥉</div>
          <div class="text-lg font-bold text-amber-600">{{ leaderboard[2].username }}</div>
          <div class="text-2xl font-bold text-arcade-warning">
            {{ leaderboard[2].value }}
          </div>
          <div class="text-xs text-gray-400">
            {{ activeTab === 'miners' ? t('leaderboard.blocks') : activeTab === 'reputation' ? t('leaderboard.points') : 'GC' }}
          </div>
        </div>
      </div>

      <!-- Rest of leaderboard -->
      <div class="arcade-panel">
        <table class="w-full">
          <thead>
            <tr class="text-left text-gray-400 text-sm border-b border-arcade-border">
              <th class="pb-3 w-16">#</th>
              <th class="pb-3">{{ t('leaderboard.player') }}</th>
              <th class="pb-3 text-right">
                {{ activeTab === 'miners' ? t('leaderboard.blocks') : activeTab === 'reputation' ? t('leaderboard.points') : t('leaderboard.volume') }}
              </th>
              <th v-if="activeTab === 'reputation'" class="pb-3 text-right">{{ t('leaderboard.rank') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="(player, index) in leaderboard.slice(3)"
              :key="player.id"
              class="border-b border-arcade-border/50 last:border-0"
              :class="{ 'bg-arcade-primary/10': player.id === authStore.player?.id }"
            >
              <td class="py-3" :class="getRankColor(index + 3)">
                {{ index + 4 }}
              </td>
              <td class="py-3">
                <span :class="{ 'text-arcade-primary': player.id === authStore.player?.id }">
                  {{ player.username }}
                </span>
                <span v-if="player.id === authStore.player?.id" class="text-xs text-gray-400 ml-2">
                  ({{ t('leaderboard.you') }})
                </span>
              </td>
              <td class="py-3 text-right font-mono">
                {{ player.value.toLocaleString() }}
              </td>
              <td v-if="activeTab === 'reputation'" class="py-3 text-right">
                <span
                  class="px-2 py-1 rounded text-xs"
                  :style="{ backgroundColor: player.rank?.color + '20', color: player.rank?.color }"
                >
                  {{ player.rank?.name }}
                </span>
              </td>
            </tr>
          </tbody>
        </table>

        <div v-if="leaderboard.length === 0" class="text-center py-8 text-gray-400">
          {{ t('leaderboard.noData') }}
        </div>
      </div>
    </div>
  </div>
</template>
