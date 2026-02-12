<script setup lang="ts">
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import type { LobbyEntry, LeaderboardEntry } from '@/composables/useCardBattle';
import { BET_OPTIONS, type BetOption, MAX_HP, MAX_ENERGY, TURN_DURATION } from '@/utils/battleCards';

defineProps<{
  entries: LobbyEntry[];
  inLobby: boolean;
  loading: boolean;
  error: string | null;
  quickMatchSearching: boolean;
  leaderboard: LeaderboardEntry[];
  leaderboardLoading: boolean;
  myBalances?: { gamecoin: number; blockcoin: number; ronin: number };
  pendingChallenges?: any[];
  myChallenges?: any[];
}>();

const emit = defineEmits<{
  enter: [];
  leave: [];
  challenge: [lobbyId: string, betAmount: number, betCurrency: string];
  acceptChallenge: [challengerId: string];
  rejectChallenge: [challengerId: string];
  quickMatch: [];
  cancelQuickMatch: [];
}>();

const { t } = useI18n();

const selectedBet = ref<BetOption>(BET_OPTIONS[0]);
const selectedOpponent = ref<LobbyEntry | null>(null);
const showBetModal = ref(false);

function openBetModal(opponent: LobbyEntry) {
  selectedOpponent.value = opponent;
  showBetModal.value = true;
}

function closeBetModal() {
  selectedOpponent.value = null;
  showBetModal.value = false;
}

function challengeWithBet(bet: { amount: number; currency: string; enabled: boolean }) {
  if (selectedOpponent.value) {
    emit('challenge', selectedOpponent.value.id, bet.amount, bet.currency);
    closeBetModal();
  }
}
</script>

<template>
  <div class="flex-1 flex flex-col overflow-hidden">
    <!-- Info banner -->
    <div class="px-3 py-2 bg-purple-500/10 border-b border-border/30">
      <p class="text-[11px] text-slate-300">
        {{ t('battle.lobbyInfo', 'Challenge players to a card battle and win their bet!') }}
      </p>
    </div>

    <!-- Error display -->
    <div v-if="error" class="mx-2 mt-2 px-3 py-2 bg-red-500/20 border border-red-500/40 rounded-lg">
      <p class="text-xs text-red-400">{{ error }}</p>
    </div>

    <!-- Player list -->
    <div class="flex-1 overflow-y-auto p-2 space-y-1.5">
      <div v-if="!inLobby" class="flex-1 flex flex-col items-center py-4 px-3 space-y-3">
        <!-- Title -->
        <div class="text-center">
          <span class="text-4xl block mb-1">&#9876;</span>
          <h3 class="text-lg font-bold text-slate-100">{{ t('battle.title', 'Card Battle') }}</h3>
          <p class="text-[11px] text-slate-400 mt-0.5">{{ t('battle.gameSubtitle', '1v1 PvP Turn-Based Card Game') }}</p>
        </div>

        <!-- Game rules grid -->
        <div class="w-full grid grid-cols-2 gap-2">
          <div class="bg-slate-800/40 rounded-lg p-2 border border-border/20">
            <div class="text-[10px] text-slate-500 uppercase tracking-wider font-semibold mb-0.5">{{ t('battle.info.hp', 'Health') }}</div>
            <div class="text-sm font-bold text-red-400">{{ MAX_HP }} HP</div>
            <div class="text-[9px] text-slate-500">{{ t('battle.info.hpDesc', 'Each player starts with') }}</div>
          </div>
          <div class="bg-slate-800/40 rounded-lg p-2 border border-border/20">
            <div class="text-[10px] text-slate-500 uppercase tracking-wider font-semibold mb-0.5">{{ t('battle.info.energy', 'Energy') }}</div>
            <div class="text-sm font-bold text-yellow-400">{{ MAX_ENERGY }} &#9889;</div>
            <div class="text-[9px] text-slate-500">{{ t('battle.info.energyDesc', 'Per turn to play cards') }}</div>
          </div>
          <div class="bg-slate-800/40 rounded-lg p-2 border border-border/20">
            <div class="text-[10px] text-slate-500 uppercase tracking-wider font-semibold mb-0.5">{{ t('battle.info.timer', 'Turn Timer') }}</div>
            <div class="text-sm font-bold text-green-400">{{ TURN_DURATION }}s</div>
            <div class="text-[9px] text-slate-500">{{ t('battle.info.timerDesc', 'Seconds per turn') }}</div>
          </div>
          <div class="bg-slate-800/40 rounded-lg p-2 border border-border/20">
            <div class="text-[10px] text-slate-500 uppercase tracking-wider font-semibold mb-0.5">{{ t('battle.info.prize', 'Prize') }}</div>
            <div class="text-sm font-bold text-green-400">{{ selectedBet.amount * 2 }} {{ selectedBet.currency }}</div>
            <div class="text-[9px] text-slate-500">{{ t('battle.info.prizeDesc', 'Winner takes all') }}</div>
          </div>
        </div>

        <!-- Card types info -->
        <div class="w-full bg-slate-800/30 rounded-lg p-2.5 border border-border/20">
          <div class="text-[10px] text-slate-500 uppercase tracking-wider font-semibold mb-1.5">{{ t('battle.info.cardTypes', 'Card Types') }}</div>
          <div class="flex gap-3 justify-center">
            <div class="flex items-center gap-1">
              <span class="w-2 h-2 rounded-full bg-red-500" />
              <span class="text-[10px] text-red-400 font-medium">{{ t('battle.info.attack', 'Attack') }} (6)</span>
            </div>
            <div class="flex items-center gap-1">
              <span class="w-2 h-2 rounded-full bg-blue-500" />
              <span class="text-[10px] text-blue-400 font-medium">{{ t('battle.info.defense', 'Defense') }} (6)</span>
            </div>
            <div class="flex items-center gap-1">
              <span class="w-2 h-2 rounded-full bg-purple-500" />
              <span class="text-[10px] text-purple-400 font-medium">{{ t('battle.info.special', 'Special') }} (6)</span>
            </div>
          </div>
          <p class="text-[9px] text-slate-500 text-center mt-1">{{ t('battle.info.deckInfo', '18 cards total. Both players get the same deck, shuffled randomly.') }}</p>
        </div>

        <!-- Action buttons -->
        <div class="w-full flex items-center gap-2">
          <!-- Quick Match button (primary) -->
          <button
            @click="emit('quickMatch')"
            :disabled="loading"
            class="flex-1 py-3 bg-gradient-to-r from-green-500 to-emerald-600 hover:from-green-400 hover:to-emerald-500 text-white rounded-lg font-bold text-sm transition-all disabled:opacity-50 shadow-lg shadow-green-500/20"
          >
            <span v-if="loading" class="flex items-center justify-center gap-2">
              <span class="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin" />
              {{ t('common.loading') }}
            </span>
            <span v-else class="flex items-center justify-center gap-2">
              &#9876; {{ t('battle.quickMatch', 'Quick Match') }}
            </span>
          </button>

          <!-- Enter Lobby button (secondary) -->
          <button
            @click="emit('enter')"
            :disabled="loading"
            class="py-3 px-3 bg-slate-700/50 hover:bg-slate-600/50 text-slate-400 rounded-lg font-medium text-[10px] transition-colors disabled:opacity-50 border border-border/30 whitespace-nowrap"
          >
            <span v-if="loading">
              <span class="w-3 h-3 border-2 border-white/30 border-t-white rounded-full animate-spin inline-block" />
            </span>
            <span v-else>
              {{ t('battle.enterLobby', 'Lobby') }}
            </span>
          </button>
        </div>
      </div>

      <template v-else>
        <!-- Pending Challenges (incoming) -->
        <div v-if="pendingChallenges && pendingChallenges.length > 0" class="mb-2">
          <div class="text-[10px] text-yellow-400 uppercase tracking-wider font-semibold mb-1.5 flex items-center gap-1">
            &#9888; {{ t('battle.pendingChallenges', 'Incoming Challenges') }}
          </div>

          <div
            v-for="challenge in pendingChallenges"
            :key="challenge.challenger_id"
            class="bg-yellow-500/10 border border-yellow-500/40 rounded-lg p-3 mb-2"
          >
            <div class="flex items-center justify-between mb-2">
              <div class="flex items-center gap-2">
                <div class="w-8 h-8 rounded-full bg-gradient-to-br from-yellow-500 to-orange-500 flex items-center justify-center text-xs font-bold text-white">
                  {{ challenge.challenger_username?.charAt(0).toUpperCase() }}
                </div>
                <div>
                  <div class="text-sm font-semibold text-yellow-300">{{ challenge.challenger_username }}</div>
                  <div class="text-[10px] text-slate-400">{{ t('battle.challengesYou', 'challenges you!') }}</div>
                </div>
              </div>
              <div class="text-right">
                <div class="text-lg font-bold text-yellow-400">{{ challenge.proposed_bet }} {{ challenge.proposed_currency }}</div>
                <div class="text-[9px] text-slate-500">{{ t('battle.betAmount', 'Bet') }}</div>
              </div>
            </div>

            <div class="flex gap-2">
              <button
                @click="emit('acceptChallenge', challenge.challenger_id)"
                :disabled="loading"
                class="flex-1 py-2 bg-green-500/20 hover:bg-green-500/30 border border-green-500/60 text-green-400 rounded-lg text-sm font-bold transition-all disabled:opacity-50"
              >
                &#10003; {{ t('battle.accept', 'Accept') }}
              </button>
              <button
                @click="emit('rejectChallenge', challenge.challenger_id)"
                :disabled="loading"
                class="flex-1 py-2 bg-red-500/20 hover:bg-red-500/30 border border-red-500/60 text-red-400 rounded-lg text-sm font-bold transition-all disabled:opacity-50"
              >
                &#10005; {{ t('battle.reject', 'Reject') }}
              </button>
            </div>

            <div class="mt-2 text-center text-[9px] text-slate-500">
              {{ t('battle.winPot', 'Win') }}: {{ challenge.proposed_bet * 2 }} {{ challenge.proposed_currency }}
            </div>
          </div>
        </div>

        <!-- My Outgoing Challenges -->
        <div v-if="myChallenges && myChallenges.length > 0" class="mb-2">
          <div class="text-[10px] text-blue-400 uppercase tracking-wider font-semibold mb-1.5 flex items-center gap-1">
            &#128228; {{ t('battle.myChallenges', 'Challenges Sent') }}
          </div>

          <div
            v-for="challenge in myChallenges"
            :key="challenge.opponent_id"
            class="bg-blue-500/10 border border-blue-500/40 rounded-lg p-2.5 mb-2"
          >
            <div class="flex items-center justify-between">
              <div class="flex items-center gap-2">
                <div class="w-6 h-6 rounded-full bg-gradient-to-br from-blue-500 to-indigo-500 flex items-center justify-center text-[10px] font-bold text-white">
                  {{ challenge.opponent_username?.charAt(0).toUpperCase() }}
                </div>
                <div>
                  <div class="text-xs font-semibold text-blue-300">{{ challenge.opponent_username }}</div>
                  <div class="text-[9px] text-slate-500">{{ challenge.proposed_bet }} {{ challenge.proposed_currency }}</div>
                </div>
              </div>
              <div class="text-[10px] text-yellow-400 flex items-center gap-1">
                <span class="w-2 h-2 bg-yellow-400 rounded-full animate-pulse"></span>
                {{ t('battle.waiting', 'Waiting...') }}
              </div>
            </div>
          </div>
        </div>

        <!-- Leaderboard (top) -->
        <div class="mb-2">
          <div class="text-[10px] text-slate-500 uppercase tracking-wider font-semibold mb-1.5 flex items-center gap-1">
            &#127942; {{ t('battle.leaderboard.title', 'Top Fighters') }}
          </div>

          <div v-if="leaderboardLoading && leaderboard.length === 0" class="flex items-center justify-center py-4">
            <div class="w-4 h-4 border-2 border-accent-primary border-t-transparent rounded-full animate-spin" />
          </div>

          <div v-else-if="leaderboard.length === 0" class="text-center py-3 bg-slate-800/30 rounded-lg border border-border/20">
            <p class="text-[10px] text-slate-500">{{ t('battle.leaderboard.empty', 'No battles yet. Be the first!') }}</p>
          </div>

          <div v-else class="bg-slate-800/30 rounded-lg border border-border/20 overflow-hidden">
            <div class="grid grid-cols-[24px_1fr_40px_40px_44px] gap-1 px-2 py-1 border-b border-border/20 text-[9px] text-slate-500 uppercase tracking-wider font-semibold">
              <span>#</span>
              <span>{{ t('battle.leaderboard.player', 'Player') }}</span>
              <span class="text-center">{{ t('battle.leaderboard.wins', 'W') }}</span>
              <span class="text-center">{{ t('battle.leaderboard.losses', 'L') }}</span>
              <span class="text-center">{{ t('battle.leaderboard.winRate', 'Win%') }}</span>
            </div>
            <div
              v-for="(entry, index) in leaderboard"
              :key="entry.playerId"
              class="grid grid-cols-[24px_1fr_40px_40px_44px] gap-1 px-2 py-1 items-center"
              :class="index % 2 === 0 ? 'bg-slate-800/20' : ''"
            >
              <span class="text-[10px] font-bold" :class="index === 0 ? 'text-yellow-400' : index === 1 ? 'text-slate-300' : index === 2 ? 'text-amber-600' : 'text-slate-500'">
                {{ index + 1 }}
              </span>
              <span class="text-[11px] text-slate-200 truncate font-medium">{{ entry.username }}</span>
              <span class="text-[10px] text-green-400 text-center font-semibold">{{ entry.wins }}</span>
              <span class="text-[10px] text-red-400 text-center">{{ entry.losses }}</span>
              <span class="text-[10px] text-slate-300 text-center">{{ entry.winRate }}%</span>
            </div>
          </div>
        </div>

        <!-- Waiting message -->
        <div v-if="entries.length === 0" class="flex flex-col items-center justify-center py-8">
          <div class="w-6 h-6 border-2 border-accent-primary border-t-transparent rounded-full animate-spin mb-3" />
          <p class="text-sm text-slate-400 text-center">
            <template v-if="quickMatchSearching">
              {{ t('battle.quickMatchSearching', 'Searching for opponent...') }}
            </template>
            <template v-else>
              {{ t('battle.waitingPlayers', 'Waiting for opponents...') }}
            </template>
          </p>
        </div>

        <!-- Opponent entries -->
        <button
          v-for="entry in entries"
          :key="entry.id"
          @click="openBetModal(entry)"
          :disabled="loading"
          class="w-full flex items-center justify-between p-3 bg-slate-800/50 hover:bg-slate-700/50 rounded-lg border border-border/30 transition-colors disabled:opacity-50"
        >
          <div class="flex items-center gap-2">
            <div class="w-8 h-8 rounded-full bg-gradient-to-br from-purple-500 to-blue-500 flex items-center justify-center text-xs font-bold text-white">
              {{ entry.username.charAt(0).toUpperCase() }}
            </div>
            <div class="text-left">
              <div class="text-sm font-semibold text-slate-200">{{ entry.username }}</div>
              <div class="text-[10px] text-slate-500">
                <span v-if="entry.wins !== undefined">
                  <span class="text-green-400">{{ entry.wins }}W</span>
                  <span class="text-slate-600">/</span>
                  <span class="text-red-400">{{ entry.losses }}L</span>
                </span>
              </div>
            </div>
          </div>
          <span class="text-xs text-accent-primary font-semibold">
            {{ t('battle.fight', 'Fight!') }} &#9876;
          </span>
        </button>
      </template>
    </div>

    <!-- Footer buttons (when in lobby) -->
    <div v-if="inLobby" class="p-3 border-t border-border/30 space-y-2">
      <button
        v-if="quickMatchSearching"
        @click="emit('cancelQuickMatch')"
        :disabled="loading"
        class="w-full py-2 bg-yellow-500/20 hover:bg-yellow-500/30 text-yellow-400 rounded-lg text-sm font-medium transition-colors disabled:opacity-50"
      >
        {{ t('battle.cancelQuickMatch', 'Cancel Search') }}
      </button>
      <button
        @click="emit('leave')"
        :disabled="loading"
        class="w-full py-2 bg-red-500/20 hover:bg-red-500/30 text-red-400 rounded-lg text-sm font-medium transition-colors disabled:opacity-50"
      >
        {{ t('battle.leaveLobby', 'Leave Lobby') }}
      </button>
    </div>

    <!-- Bet Selection Modal -->
    <div
      v-if="showBetModal && selectedOpponent"
      class="fixed inset-0 bg-black/60 flex items-center justify-center z-50 p-4"
      @click.self="closeBetModal"
    >
      <div class="bg-slate-900 rounded-xl border border-border/40 p-4 max-w-sm w-full">
        <div class="flex items-center justify-between mb-3">
          <h3 class="text-lg font-bold text-slate-100">{{ t('battle.selectBet', 'Select Bet') }}</h3>
          <button
            @click="closeBetModal"
            class="text-slate-400 hover:text-slate-300 text-xl leading-none"
          >
            &times;
          </button>
        </div>

        <div class="mb-3">
          <p class="text-sm text-slate-400">
            {{ t('battle.challengeOpponent', 'Challenge') }}
            <span class="font-semibold text-slate-200">{{ selectedOpponent.username }}</span>
          </p>
        </div>

        <div class="space-y-2">
          <button
            v-for="bet in selectedOpponent.available_bets"
            :key="`${bet.amount}-${bet.currency}`"
            @click="challengeWithBet(bet)"
            :disabled="!bet.enabled || loading"
            class="w-full px-4 py-3 rounded-lg text-sm font-bold transition-all border"
            :class="bet.enabled
              ? 'bg-green-500/20 border-green-500/60 text-green-400 hover:bg-green-500/30 shadow-sm shadow-green-500/10'
              : 'bg-slate-800/50 border-border/30 text-slate-600 cursor-not-allowed opacity-50'"
          >
            <div class="flex items-center justify-between">
              <span>{{ bet.amount }} {{ bet.currency }}</span>
              <span v-if="!bet.enabled" class="text-[10px] text-red-400">
                {{ t('battle.insufficientFunds', 'Insufficient funds') }}
              </span>
              <span v-else class="text-[10px] text-green-400">
                {{ t('battle.winPot', 'Win') }} {{ bet.amount * 2 }} {{ bet.currency }}
              </span>
            </div>
          </button>
        </div>

        <div class="mt-3 text-center">
          <button
            @click="closeBetModal"
            class="text-xs text-slate-500 hover:text-slate-400"
          >
            {{ t('common.cancel', 'Cancel') }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
