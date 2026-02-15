<script setup lang="ts">
import { watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useDefenseStore } from '@/stores/defense';
import { useAuthStore } from '@/stores/auth';
import { useCardBattle } from '@/composables/useCardBattle';
import { useBattleSound } from '@/composables/useSound';
import BattleLobby from './defense/BattleLobby.vue';
import BattleReadyRoom from './defense/BattleReadyRoom.vue';
import BattleIntro from './defense/BattleIntro.vue';
import BattleArena from './defense/BattleArena.vue';

const props = defineProps<{
  show: boolean;
}>();

const emit = defineEmits<{
  close: [];
}>();

const { t } = useI18n();
const defenseStore = useDefenseStore();
const authStore = useAuthStore();
const { battleSoundEnabled, toggle: toggleBattleSound } = useBattleSound();

const {
  lobbyLoading,
  myBalances,
  readyRoom,
  loadLobby,
  subscribeToLobby,
  // Ready Room
  selectBattleBet,
  cancelReadyRoom,
  cancelReadyRoomAndSearch,
  enemyUsername,
  lobbyCount,
  playingCount,
  // Quick match
  quickMatchSearching,
  quickMatch,
  cancelQuickMatch,
  // Battle
  errorMessage,
  myHp,
  myShield,
  myEnergy,
  enemyHp,
  enemyShield,
  isMyTurn,
  myWeakened,
  myBoosted,
  enemyWeakened,
  enemyBoosted,
  myPoison,
  enemyPoison,
  myDeckCount,
  myDiscardCount,
  enemyDeckCount,
  enemyDiscardCount,
  enemyHandCount,
  turnTimer,
  handCards,
  battleLog,
  cardsPlayedThisTurn,
  result,
  battleLoading,
  animatingEffects,
  session,
  playCard,
  undoLastCard,
  endTurn,
  doForfeit,
  resetBattle,
  cleanup,
  // Recall
  myDiscard,
  showRecallPicker,
  selectRecallTarget,
  cancelRecall,
} = useCardBattle();

// Load lobby when modal opens (watch the prop, not store)
watch(
  () => props.show,
  async (open) => {
    if (open) {
      defenseStore.setView('lobby');
      await loadLobby();
      subscribeToLobby();
    } else {
      cleanup();
    }
  }
);

// Switch to intro view when session starts, then battle after intro
watch(session, (s) => {
  if (s && s.status === 'active' && defenseStore.gameView === 'lobby') {
    defenseStore.setView('intro');
  }
});

function handleClose() {
  if (session.value && session.value.status === 'active') {
    // Minimize — hide modal without leaving battle
    emit('close');
    return;
  }
  cleanup();
  emit('close');
}

async function handleSelectBet(betAmount: number, betCurrency: string) {
  try {
    await selectBattleBet(betAmount, betCurrency as 'GC' | 'BLC' | 'RON');
    await authStore.refreshPlayer();
  } catch {
    // error handled in composable
  }
}

async function handleCancelReadyRoom() {
  try {
    await cancelReadyRoom();
    await authStore.refreshPlayer(); // Refund the bet
  } catch {
    // error handled in composable
  }
}

async function handleFindAnother() {
  try {
    await cancelReadyRoomAndSearch();
    await authStore.refreshPlayer();
  } catch {
    // error handled in composable
  }
}

async function handleQuickMatch() {
  try {
    await quickMatch();
    await authStore.refreshPlayer();
  } catch {
    // error handled in composable
  }
}

async function handleCancelQuickMatch() {
  await cancelQuickMatch();
  await authStore.refreshPlayer();
}

function handleIntroDone() {
  defenseStore.setView('battle');
}

function handleResultClose() {
  resetBattle();
  defenseStore.setView('lobby');
  loadLobby();
  authStore.refreshPlayer();
}

// Get enemy username (cached in composable when battle starts)
function getEnemyUsername(): string {
  if (enemyUsername.value) return enemyUsername.value;
  return 'Opponent';
}
</script>

<template>
  <Teleport to="body">
    <div v-if="show" class="fixed inset-0 z-50 flex items-center justify-center p-2 sm:p-4">
      <!-- Backdrop -->
      <div class="absolute inset-0 bg-black/70 backdrop-blur-sm" @click="handleClose" />

      <!-- Modal card -->
      <div class="relative w-full max-w-lg h-[90vh] flex flex-col bg-bg-primary border border-border rounded-xl shadow-2xl animate-fade-in overflow-hidden">
        <!-- Header -->
        <div
          class="flex items-center justify-between px-3 py-2.5 border-b relative overflow-hidden"
          :class="session && session.status === 'active'
            ? 'border-red-500/20 bg-gradient-to-r from-slate-900 via-slate-950 to-slate-900'
            : 'border-border/50'"
        >
          <!-- Battle mode background accent -->
          <div
            v-if="session && session.status === 'active'"
            class="absolute inset-0 bg-gradient-to-r from-red-500/5 via-transparent to-orange-500/5"
          />

          <div class="relative flex items-center gap-2">
            <div
              class="w-7 h-7 rounded-lg flex items-center justify-center text-sm shadow-md"
              :class="session && session.status === 'active'
                ? 'bg-gradient-to-br from-red-500 to-orange-600 shadow-red-500/30'
                : 'bg-gradient-to-br from-slate-700 to-slate-600 shadow-slate-500/20'"
            >
              &#9876;
            </div>
            <div class="flex flex-col">
              <h2
                class="text-sm font-black tracking-tight bg-gradient-to-r bg-clip-text text-transparent"
                :class="session && session.status === 'active'
                  ? 'from-red-400 via-orange-400 to-amber-400'
                  : 'from-red-400 to-orange-500'"
              >
                {{ t('battle.title', 'Card Battle') }}
              </h2>
              <span
                v-if="session && session.status === 'active'"
                class="text-[9px] font-bold text-slate-500 uppercase tracking-widest"
              >
                {{ t('battle.turnLabel', 'Turn') }} {{ session.turn_number }}
              </span>
            </div>
          </div>

          <!-- Close / minimize button -->
          <div class="relative flex items-center gap-2">
            <div v-if="session && session.status === 'active'" class="flex items-center gap-1.5">
              <span class="relative flex h-2 w-2">
                <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-red-400 opacity-75" />
                <span class="relative inline-flex rounded-full h-2 w-2 bg-red-400" />
              </span>
              <span class="text-[10px] font-bold text-red-400 uppercase tracking-wider">
                {{ t('battle.live', 'LIVE') }}
              </span>
            </div>
            <!-- Battle sound toggle -->
            <button
              @click="toggleBattleSound"
              class="p-1.5 rounded-lg transition-colors"
              :class="battleSoundEnabled ? 'text-slate-300 hover:text-white hover:bg-slate-700/50' : 'text-slate-600 hover:text-slate-400 hover:bg-slate-700/50'"
              :title="battleSoundEnabled ? t('battle.soundOn', 'Sound ON') : t('battle.soundOff', 'Sound OFF')"
            >
              <svg v-if="battleSoundEnabled" class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                <path stroke-linecap="round" stroke-linejoin="round" d="M15.536 8.464a5 5 0 010 7.072M17.95 6.05a8 8 0 010 11.9M11 5L6 9H2v6h4l5 4V5z" />
              </svg>
              <svg v-else class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                <path stroke-linecap="round" stroke-linejoin="round" d="M5.586 15H4a1 1 0 01-1-1v-4a1 1 0 011-1h1.586l4.707-4.707A1 1 0 0112 5v14a1 1 0 01-1.707.707L5.586 15z" />
                <path stroke-linecap="round" stroke-linejoin="round" d="M17 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2" />
              </svg>
            </button>
            <button
              @click="handleClose"
              class="p-1.5 text-slate-400 hover:text-slate-200 hover:bg-slate-700/50 rounded-lg transition-colors"
              :title="session && session.status === 'active'
                ? t('battle.minimize', 'Minimize (battle continues)')
                : t('common.close', 'Close')"
            >
              <svg v-if="session && session.status === 'active'" class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                <path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7" />
              </svg>
              <svg v-else class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>
        </div>

        <!-- Ready Room View -->
        <BattleReadyRoom
          v-if="defenseStore.gameView === 'lobby' && readyRoom"
          :ready-room="readyRoom"
          :my-player-id="authStore.player?.id || ''"
          :loading="battleLoading"
          :my-balances="myBalances"
          :error="errorMessage"
          @select-bet="handleSelectBet"
          @cancel="handleCancelReadyRoom"
          @find-another="handleFindAnother"
        />

        <!-- Lobby View -->
        <BattleLobby
          v-else-if="defenseStore.gameView === 'lobby'"
          :loading="lobbyLoading"
          :error="errorMessage"
          :quick-match-searching="quickMatchSearching"
          :lobby-count="lobbyCount"
          :playing-count="playingCount"
          @quick-match="handleQuickMatch"
          @cancel-quick-match="handleCancelQuickMatch"
        />

        <!-- Intro View (VS screen) -->
        <BattleIntro
          v-else-if="defenseStore.gameView === 'intro'"
          :my-username="authStore.player?.username || '???'"
          :enemy-username="getEnemyUsername()"
          :bet-amount="session?.bet_amount || 0"
          :bet-currency="session?.bet_currency || 'GC'"
          @done="handleIntroDone"
        />

        <!-- Battle View -->
        <BattleArena
          v-else-if="defenseStore.gameView === 'battle'"
          :my-username="authStore.player?.username || '???'"
          :enemy-username="getEnemyUsername()"
          :my-hp="myHp"
          :my-shield="myShield"
          :my-energy="myEnergy"
          :enemy-hp="enemyHp"
          :enemy-shield="enemyShield"
          :is-my-turn="isMyTurn"
          :animating-effects="animatingEffects"
          :my-weakened="myWeakened"
          :my-boosted="myBoosted"
          :enemy-weakened="enemyWeakened"
          :enemy-boosted="enemyBoosted"
          :my-poison="myPoison"
          :enemy-poison="enemyPoison"
          :my-deck-count="myDeckCount"
          :my-discard-count="myDiscardCount"
          :enemy-deck-count="enemyDeckCount"
          :enemy-discard-count="enemyDiscardCount"
          :enemy-hand-count="enemyHandCount"
          :turn-timer="turnTimer"
          :hand-cards="handCards"
          :battle-log="battleLog"
          :cards-played="cardsPlayedThisTurn"
          :result="result"
          :loading="battleLoading"
          :my-discard="myDiscard"
          :show-recall-picker="showRecallPicker"
          @play-card="playCard"
          @end-turn="endTurn"
          @undo="undoLastCard"
          @forfeit="doForfeit"
          @result-close="handleResultClose"
          @select-recall-target="selectRecallTarget"
          @cancel-recall="cancelRecall"
        />
      </div>
    </div>
  </Teleport>
</template>
