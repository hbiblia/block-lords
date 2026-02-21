<script setup lang="ts">
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAuthStore } from '@/stores/auth';
import { MAX_HP, MAX_ENERGY, TURN_DURATION, CARD_DEFINITIONS } from '@/utils/battleCards';
import { getBattleLeaderboard } from '@/utils/api';

const attackCount = CARD_DEFINITIONS.filter(c => c.type === 'attack').length;
const defenseCount = CARD_DEFINITIONS.filter(c => c.type === 'defense').length;
const specialCount = CARD_DEFINITIONS.filter(c => c.type === 'special').length;
const totalCards = CARD_DEFINITIONS.length;

defineProps<{
  loading: boolean;
  error: string | null;
  quickMatchSearching: boolean;
  lobbyCount: number;
  playingCount: number;
}>();

const emit = defineEmits<{
  quickMatch: [];
  cancelQuickMatch: [];
}>();

const { t } = useI18n();
const authStore = useAuthStore();

// Leaderboard state
const showLeaderboard = ref(false);
const leaderboardData = ref<any[]>([]);
const leaderboardLoading = ref(false);

async function toggleLeaderboard() {
  showLeaderboard.value = !showLeaderboard.value;
  if (showLeaderboard.value && leaderboardData.value.length === 0) {
    leaderboardLoading.value = true;
    try {
      const data = await getBattleLeaderboard(20);
      leaderboardData.value = data ?? [];
    } catch {
      leaderboardData.value = [];
    } finally {
      leaderboardLoading.value = false;
    }
  }
}
</script>

<template>
  <div class="flex-1 flex flex-col overflow-hidden">
    <!-- Error display -->
    <div v-if="error" class="mx-2 mt-2 px-3 py-2 bg-red-500/20 border border-red-500/40 rounded-lg">
      <p class="text-xs text-red-400">{{ error }}</p>
    </div>

    <div class="flex-1 overflow-y-auto p-2 relative">
      <!-- Searching notification banner -->
      <Transition name="search-toast">
        <div v-if="quickMatchSearching" class="sticky top-0 z-10 mb-2">
          <div class="relative overflow-hidden rounded-xl bg-slate-900/95 border border-emerald-500/30 shadow-lg shadow-emerald-500/10 backdrop-blur-sm">
            <div class="absolute top-0 left-0 right-0 h-[2px] bg-gradient-to-r from-emerald-400 via-cyan-400 to-emerald-400 animate-shimmer"></div>
            <div class="flex items-center gap-3 px-4 py-3">
              <div class="relative flex-shrink-0">
                <div class="w-5 h-5 border-2 border-emerald-400 border-t-transparent rounded-full animate-spin" />
              </div>
              <div class="flex-1 min-w-0">
                <p class="text-[11px] font-bold text-emerald-300/60 uppercase tracking-wider mb-0.5">{{ t('battle.quickMatch', 'Quick Match') }}</p>
                <p class="text-xs font-semibold text-white/90">{{ t('battle.quickMatchSearching', 'Waiting for opponent...') }}</p>
              </div>
              <button
                @click="emit('cancelQuickMatch')"
                :disabled="loading"
                class="flex-shrink-0 px-3 py-1.5 rounded-lg text-[11px] font-bold bg-yellow-500/20 text-yellow-300 hover:bg-yellow-500/30 border border-yellow-500/20 hover:border-yellow-500/40 transition-all disabled:opacity-50"
              >
                {{ t('battle.cancelQuickMatch', 'Cancel Search') }}
              </button>
            </div>
          </div>
        </div>
      </Transition>

      <!-- Welcome screen (always visible) -->
      <div class="flex-1 flex flex-col items-center py-4 px-3 space-y-3">
        <!-- Title -->
        <div class="text-center">
          <span class="text-4xl block mb-1">&#9876;</span>
          <h3 class="text-lg font-bold text-slate-100">{{ t('battle.title', 'Card Battle') }}</h3>
          <p class="text-[11px] text-slate-400 mt-0.5">{{ t('battle.gameSubtitle', '1v1 PvP Turn-Based Card Game') }}</p>
        </div>

        <!-- Game rules -->
        <div class="w-full flex items-center justify-center gap-3 bg-slate-800/30 rounded-lg px-3 py-2 border border-border/20">
          <div class="flex items-center gap-1">
            <span class="text-red-400 font-bold text-xs">{{ MAX_HP }}</span>
            <span class="text-[10px] text-slate-500">HP</span>
          </div>
          <span class="text-slate-700">|</span>
          <div class="flex items-center gap-1">
            <span class="text-yellow-400 font-bold text-xs">{{ MAX_ENERGY }}&#9889;</span>
            <span class="text-[10px] text-slate-500">{{ t('battle.info.energy', 'Energy') }}</span>
          </div>
          <span class="text-slate-700">|</span>
          <div class="flex items-center gap-1">
            <span class="text-green-400 font-bold text-xs">{{ TURN_DURATION }}s</span>
            <span class="text-[10px] text-slate-500">{{ t('battle.info.timer', 'Turn Timer') }}</span>
          </div>
          <span class="text-slate-700">|</span>
          <div class="flex items-center gap-1">
            <span class="text-green-400 font-bold text-xs">2x</span>
            <span class="text-[10px] text-slate-500">{{ t('battle.info.prize', 'Prize') }}</span>
          </div>
        </div>

        <!-- Card types info -->
        <div class="w-full bg-slate-800/30 rounded-lg p-2.5 border border-border/20">
          <div class="text-[10px] text-slate-500 uppercase tracking-wider font-semibold mb-1.5">{{ t('battle.info.cardTypes', 'Card Types') }}</div>
          <div class="flex gap-3 justify-center">
            <div class="flex items-center gap-1">
              <span class="w-2 h-2 rounded-full bg-red-500" />
              <span class="text-[10px] text-red-400 font-medium">{{ t('battle.info.attack', 'Attack') }} ({{ attackCount }})</span>
            </div>
            <div class="flex items-center gap-1">
              <span class="w-2 h-2 rounded-full bg-blue-500" />
              <span class="text-[10px] text-blue-400 font-medium">{{ t('battle.info.defense', 'Defense') }} ({{ defenseCount }})</span>
            </div>
            <div class="flex items-center gap-1">
              <span class="w-2 h-2 rounded-full bg-purple-500" />
              <span class="text-[10px] text-purple-400 font-medium">{{ t('battle.info.special', 'Special') }} ({{ specialCount }})</span>
            </div>
          </div>
          <p class="text-[9px] text-slate-500 text-center mt-1">{{ t('battle.info.deckInfo', { count: totalCards }, `${totalCards} cards total. Both players get the same deck, shuffled randomly.`) }}</p>
        </div>

        <!-- Leaderboard toggle button -->
        <button
          @click="toggleLeaderboard"
          class="w-full py-2 rounded-lg text-xs font-bold transition-all border"
          :class="showLeaderboard
            ? 'bg-amber-500/20 text-amber-300 border-amber-500/30 hover:bg-amber-500/30'
            : 'bg-slate-800/40 text-slate-400 border-border/20 hover:bg-slate-800/60 hover:text-slate-300'"
        >
          <span class="flex items-center justify-center gap-1.5">
            &#127942; {{ t('battle.leaderboard.title', 'Top Fighters') }}
            <svg class="w-3 h-3 transition-transform" :class="{ 'rotate-180': showLeaderboard }" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.5">
              <path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7" />
            </svg>
          </span>
        </button>

        <!-- Leaderboard section -->
        <Transition name="lb">
          <div v-if="showLeaderboard" class="w-full bg-slate-800/30 rounded-lg border border-amber-500/20 overflow-hidden">
            <!-- Loading -->
            <div v-if="leaderboardLoading" class="flex justify-center py-6">
              <div class="w-5 h-5 border-2 border-amber-400 border-t-transparent rounded-full animate-spin" />
            </div>

            <!-- Empty -->
            <div v-else-if="leaderboardData.length === 0" class="py-6 text-center">
              <p class="text-xs text-slate-500">{{ t('battle.leaderboard.empty', 'No battles yet. Be the first!') }}</p>
            </div>

            <!-- Table -->
            <div v-else class="max-h-52 overflow-y-auto">
              <table class="w-full text-xs">
                <thead class="sticky top-0 bg-slate-800/90 backdrop-blur-sm">
                  <tr class="text-slate-500 uppercase tracking-wider">
                    <th class="py-1.5 px-2 text-left font-semibold">#</th>
                    <th class="py-1.5 px-2 text-left font-semibold">{{ t('battle.leaderboard.player', 'Player') }}</th>
                    <th class="py-1.5 px-2 text-center font-semibold">{{ t('battle.leaderboard.wins', 'W') }}</th>
                    <th class="py-1.5 px-2 text-center font-semibold">{{ t('battle.leaderboard.losses', 'L') }}</th>
                    <th class="py-1.5 px-2 text-right font-semibold">{{ t('battle.leaderboard.winRate', 'Win%') }}</th>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    v-for="(entry, idx) in leaderboardData"
                    :key="entry.player_id || idx"
                    class="border-t border-border/10 transition-colors"
                    :class="entry.player_id === authStore.player?.id ? 'bg-amber-500/10' : 'hover:bg-slate-700/20'"
                  >
                    <td class="py-1.5 px-2 font-bold" :class="idx < 3 ? 'text-amber-400' : 'text-slate-500'">
                      {{ idx === 0 ? '&#129351;' : idx === 1 ? '&#129352;' : idx === 2 ? '&#129353;' : idx + 1 }}
                    </td>
                    <td class="py-1.5 px-2 font-medium truncate max-w-[120px]" :class="entry.player_id === authStore.player?.id ? 'text-amber-300' : 'text-slate-300'">
                      {{ entry.username }}
                      <span v-if="entry.player_id === authStore.player?.id" class="text-[9px] text-amber-400/60 ml-1">({{ t('leaderboard.you', 'you') }})</span>
                    </td>
                    <td class="py-1.5 px-2 text-center text-green-400 font-medium">{{ entry.wins ?? 0 }}</td>
                    <td class="py-1.5 px-2 text-center text-red-400 font-medium">{{ entry.losses ?? 0 }}</td>
                    <td class="py-1.5 px-2 text-right font-bold" :class="(entry.win_rate ?? 0) >= 50 ? 'text-green-400' : 'text-slate-400'">
                      {{ ((entry.win_rate ?? 0)).toFixed(0) }}%
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </Transition>

        <!-- Live stats -->
        <div class="flex gap-4">
          <div class="flex items-center gap-1.5 bg-slate-800/50 rounded-lg px-3 py-1.5 border border-border/20">
            <span class="w-2 h-2 rounded-full bg-green-400 animate-pulse" />
            <span class="text-xs text-slate-300 font-medium">{{ lobbyCount }}</span>
            <span class="text-[10px] text-slate-500">{{ t('battle.inLobby', 'in lobby') }}</span>
          </div>
          <div class="flex items-center gap-1.5 bg-slate-800/50 rounded-lg px-3 py-1.5 border border-border/20">
            <span class="w-2 h-2 rounded-full bg-red-400" />
            <span class="text-xs text-slate-300 font-medium">{{ playingCount }}</span>
            <span class="text-[10px] text-slate-500">{{ t('battle.inBattle', 'in battle') }}</span>
          </div>
        </div>

        <!-- Responsible gambling notice -->
        <p class="text-[9px] text-slate-500 text-center">{{ t('gambling.lobbyNotice') }}</p>

        <!-- Quick Match / Cancel button -->
        <button
          v-if="!quickMatchSearching"
          @click="emit('quickMatch')"
          :disabled="loading"
          class="w-full py-3 bg-gradient-to-r from-green-500 to-emerald-600 hover:from-green-400 hover:to-emerald-500 text-white rounded-lg font-bold text-sm transition-all disabled:opacity-50 shadow-lg shadow-green-500/20"
        >
          <span v-if="loading" class="flex items-center justify-center gap-2">
            <span class="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin" />
            {{ t('common.loading') }}
          </span>
          <span v-else class="flex items-center justify-center gap-2">
            &#9876; {{ t('battle.quickMatch', 'Quick Match') }}
          </span>
        </button>
        <button
          v-else
          @click="emit('cancelQuickMatch')"
          :disabled="loading"
          class="w-full py-3 bg-yellow-500/20 hover:bg-yellow-500/30 text-yellow-400 rounded-lg font-bold text-sm transition-all disabled:opacity-50 border border-yellow-500/30"
        >
          {{ t('battle.cancelQuickMatch', 'Cancel Search') }}
        </button>
      </div>
    </div>
  </div>
</template>

<style scoped>
@keyframes shimmer {
  0% { background-position: -200% 0; }
  100% { background-position: 200% 0; }
}

.animate-shimmer {
  background-size: 200% 100%;
  animation: shimmer 3s linear infinite;
}

.search-toast-enter-active {
  transition: all 0.3s ease-out;
}

.search-toast-leave-active {
  transition: all 0.2s ease-in;
}

.search-toast-enter-from {
  opacity: 0;
  transform: translateY(-10px);
}

.search-toast-leave-to {
  opacity: 0;
  transform: translateY(-10px);
}

.lb-enter-active {
  transition: all 0.3s ease-out;
}

.lb-leave-active {
  transition: all 0.2s ease-in;
}

.lb-enter-from,
.lb-leave-to {
  opacity: 0;
  max-height: 0;
  overflow: hidden;
}

.lb-enter-to,
.lb-leave-from {
  opacity: 1;
  max-height: 300px;
}
</style>
