<script setup lang="ts">
import { watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useDefenseStore } from '@/stores/defense';
import { useAuthStore } from '@/stores/auth';
import { useCardBattle } from '@/composables/useCardBattle';
import BattleLobby from './defense/BattleLobby.vue';
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

const {
  lobbyEntries,
  inLobby,
  lobbyLoading,
  loadLobby,
  enterLobby,
  exitLobby,
  challengePlayer,
  subscribeToLobby,
  // Battle
  myHp,
  myShield,
  myEnergy,
  enemyHp,
  enemyShield,
  isMyTurn,
  turnTimer,
  handCards,
  battleLog,
  cardsPlayedThisTurn,
  result,
  battleLoading,
  errorMessage,
  session,
  playCard,
  undoLastCard,
  endTurn,
  doForfeit,
  resetBattle,
  cleanup,
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

// Switch to battle view when session starts
watch(session, (s) => {
  if (s && s.status === 'active') {
    defenseStore.setView('battle');
  }
});

function handleClose() {
  if (session.value && session.value.status === 'active') {
    // Don't close during active battle
    return;
  }
  cleanup();
  emit('close');
}

async function handleEnterLobby() {
  try {
    await enterLobby();
    // Refresh balance
    await authStore.refreshPlayer();
  } catch {
    // error handled in composable
  }
}

async function handleLeaveLobby() {
  await exitLobby();
  await authStore.refreshPlayer();
}

async function handleChallenge(lobbyId: string) {
  try {
    await challengePlayer(lobbyId);
  } catch {
    // error handled in composable
  }
}

function handleResultClose() {
  resetBattle();
  defenseStore.setView('lobby');
  loadLobby();
  authStore.refreshPlayer();
}

// Get enemy username from lobby entries or session
function getEnemyUsername(): string {
  if (!session.value || !authStore.player) return '???';
  const isP1 = session.value.player1_id === authStore.player.id;
  // Try to find from lobby entries
  const enemyId = isP1 ? session.value.player2_id : session.value.player1_id;
  const entry = lobbyEntries.value.find((e) => e.player_id === enemyId);
  return entry?.username || 'Opponent';
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
        <div class="flex items-center justify-between p-3 border-b border-border/50">
          <div class="flex items-center gap-2">
            <span class="text-xl">&#9876;</span>
            <h2 class="text-base font-bold bg-gradient-to-r from-red-400 to-orange-500 bg-clip-text text-transparent">
              {{ t('battle.title', 'Card Battle') }}
            </h2>
          </div>
          <button
            v-if="!session || session.status !== 'active'"
            @click="handleClose"
            class="p-1.5 text-slate-400 hover:text-slate-200 hover:bg-slate-700/50 rounded-lg transition-colors"
          >
            <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
              <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
          <span v-else class="text-xs text-yellow-400 font-mono">
            T{{ session.turn_number }}
          </span>
        </div>

        <!-- Lobby View -->
        <BattleLobby
          v-if="defenseStore.gameView === 'lobby'"
          :entries="lobbyEntries"
          :in-lobby="inLobby"
          :loading="lobbyLoading"
          :error="errorMessage"
          @enter="handleEnterLobby"
          @leave="handleLeaveLobby"
          @challenge="handleChallenge"
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
          :turn-timer="turnTimer"
          :hand-cards="handCards"
          :battle-log="battleLog"
          :cards-played="cardsPlayedThisTurn"
          :result="result"
          :loading="battleLoading"
          @play-card="playCard"
          @end-turn="endTurn"
          @undo="undoLastCard"
          @forfeit="doForfeit"
          @result-close="handleResultClose"
        />
      </div>
    </div>
  </Teleport>
</template>
