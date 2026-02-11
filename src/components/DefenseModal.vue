<script setup lang="ts">
import { watch, onUnmounted } from 'vue';
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

// Lock body scroll when modal is open
watch(
  () => props.show,
  (open) => {
    document.body.style.overflow = open ? 'hidden' : '';
  },
  { immediate: true }
);

onUnmounted(() => {
  document.body.style.overflow = '';
});

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
    // Minimize — hide modal without leaving battle
    emit('close');
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
