<script setup lang="ts">
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps<{
  readyRoom: {
    id: string;
    player1_id: string;
    player2_id: string;
    player1_username: string;
    player2_username: string;
    player1_ready: boolean;
    player2_ready: boolean;
    bet_amount: number;
    bet_currency: string;
  };
  myPlayerId: string;
  loading: boolean;
}>();

const emit = defineEmits<{
  setReady: [];
  cancel: [];
}>();

const { t } = useI18n();

const isPlayer1 = computed(() => props.myPlayerId === props.readyRoom.player1_id);
const myUsername = computed(() => isPlayer1.value ? props.readyRoom.player1_username : props.readyRoom.player2_username);
const opponentUsername = computed(() => isPlayer1.value ? props.readyRoom.player2_username : props.readyRoom.player1_username);
const imReady = computed(() => isPlayer1.value ? props.readyRoom.player1_ready : props.readyRoom.player2_ready);
const opponentReady = computed(() => isPlayer1.value ? props.readyRoom.player2_ready : props.readyRoom.player1_ready);
const bothReady = computed(() => props.readyRoom.player1_ready && props.readyRoom.player2_ready);
</script>

<template>
  <div class="flex-1 flex flex-col items-center justify-center p-6 bg-gradient-to-b from-slate-900 via-purple-900/20 to-slate-900">
    <!-- Title -->
    <div class="text-center mb-8">
      <h2 class="text-3xl font-bold text-transparent bg-clip-text bg-gradient-to-r from-purple-400 to-pink-400 mb-2">
        {{ t('battle.readyRoom.title', 'Battle Ready Room') }}
      </h2>
      <p class="text-sm text-slate-400">
        {{ t('battle.readyRoom.subtitle', 'Both players must be ready to start') }}
      </p>
    </div>

    <!-- Bet Info -->
    <div class="mb-8 px-6 py-3 bg-purple-500/10 border border-purple-500/30 rounded-xl">
      <div class="text-center">
        <div class="text-xs text-slate-500 uppercase tracking-wider mb-1">{{ t('battle.readyRoom.bet', 'Battle Bet') }}</div>
        <div class="text-2xl font-bold text-purple-400">{{ readyRoom.bet_amount }} {{ readyRoom.bet_currency }}</div>
        <div class="text-xs text-slate-500 mt-1">{{ t('battle.readyRoom.winner', 'Winner takes') }} {{ readyRoom.bet_amount * 2 }} {{ readyRoom.bet_currency }}</div>
      </div>
    </div>

    <!-- Players -->
    <div class="flex items-center gap-12 mb-8">
      <!-- Player 1 (You or Opponent) -->
      <div class="flex flex-col items-center">
        <div class="relative mb-3">
          <div
            class="w-24 h-24 rounded-full flex items-center justify-center text-3xl font-bold text-white transition-all duration-300"
            :class="(isPlayer1 && imReady) || (!isPlayer1 && opponentReady)
              ? 'bg-gradient-to-br from-green-500 to-emerald-600 shadow-lg shadow-green-500/50 scale-110'
              : 'bg-gradient-to-br from-purple-500 to-blue-500'"
          >
            {{ (isPlayer1 ? myUsername : opponentUsername).charAt(0).toUpperCase() }}
          </div>
          <!-- Ready Check -->
          <div
            v-if="(isPlayer1 && imReady) || (!isPlayer1 && opponentReady)"
            class="absolute -top-1 -right-1 w-8 h-8 bg-green-500 rounded-full flex items-center justify-center shadow-lg animate-bounce"
          >
            <span class="text-white text-lg">✓</span>
          </div>
        </div>
        <div class="text-center">
          <div class="text-lg font-bold text-slate-200">{{ isPlayer1 ? myUsername : opponentUsername }}</div>
          <div class="text-xs text-slate-500">{{ isPlayer1 ? t('battle.readyRoom.you', 'You') : t('battle.readyRoom.opponent', 'Opponent') }}</div>
          <div
            class="mt-2 px-3 py-1 rounded-full text-xs font-semibold"
            :class="(isPlayer1 && imReady) || (!isPlayer1 && opponentReady)
              ? 'bg-green-500/20 text-green-400'
              : 'bg-yellow-500/20 text-yellow-400'"
          >
            {{ (isPlayer1 && imReady) || (!isPlayer1 && opponentReady)
              ? t('battle.readyRoom.ready', 'READY ✓')
              : t('battle.readyRoom.waiting', 'Waiting...') }}
          </div>
        </div>
      </div>

      <!-- VS -->
      <div class="text-4xl font-bold text-slate-600">VS</div>

      <!-- Player 2 (Opponent or You) -->
      <div class="flex flex-col items-center">
        <div class="relative mb-3">
          <div
            class="w-24 h-24 rounded-full flex items-center justify-center text-3xl font-bold text-white transition-all duration-300"
            :class="(!isPlayer1 && imReady) || (isPlayer1 && opponentReady)
              ? 'bg-gradient-to-br from-green-500 to-emerald-600 shadow-lg shadow-green-500/50 scale-110'
              : 'bg-gradient-to-br from-pink-500 to-red-500'"
          >
            {{ (!isPlayer1 ? myUsername : opponentUsername).charAt(0).toUpperCase() }}
          </div>
          <!-- Ready Check -->
          <div
            v-if="(!isPlayer1 && imReady) || (isPlayer1 && opponentReady)"
            class="absolute -top-1 -right-1 w-8 h-8 bg-green-500 rounded-full flex items-center justify-center shadow-lg animate-bounce"
          >
            <span class="text-white text-lg">✓</span>
          </div>
        </div>
        <div class="text-center">
          <div class="text-lg font-bold text-slate-200">{{ !isPlayer1 ? myUsername : opponentUsername }}</div>
          <div class="text-xs text-slate-500">{{ !isPlayer1 ? t('battle.readyRoom.you', 'You') : t('battle.readyRoom.opponent', 'Opponent') }}</div>
          <div
            class="mt-2 px-3 py-1 rounded-full text-xs font-semibold"
            :class="(!isPlayer1 && imReady) || (isPlayer1 && opponentReady)
              ? 'bg-green-500/20 text-green-400'
              : 'bg-yellow-500/20 text-yellow-400'"
          >
            {{ (!isPlayer1 && imReady) || (isPlayer1 && opponentReady)
              ? t('battle.readyRoom.ready', 'READY ✓')
              : t('battle.readyRoom.waiting', 'Waiting...') }}
          </div>
        </div>
      </div>
    </div>

    <!-- Action Button -->
    <div class="w-full max-w-md">
      <button
        v-if="!imReady"
        @click="emit('setReady')"
        :disabled="loading"
        class="w-full py-4 bg-gradient-to-r from-green-500 to-emerald-600 hover:from-green-400 hover:to-emerald-500 text-white rounded-xl font-bold text-lg transition-all disabled:opacity-50 shadow-lg shadow-green-500/30 hover:scale-105"
      >
        <span v-if="loading" class="flex items-center justify-center gap-2">
          <span class="w-5 h-5 border-2 border-white/30 border-t-white rounded-full animate-spin" />
          {{ t('common.loading') }}
        </span>
        <span v-else class="flex items-center justify-center gap-2">
          ✓ {{ t('battle.readyRoom.imReady', "I'M READY!") }}
        </span>
      </button>

      <div v-else-if="!bothReady" class="text-center">
        <div class="py-4 px-6 bg-yellow-500/10 border border-yellow-500/30 rounded-xl">
          <div class="flex items-center justify-center gap-2 text-yellow-400 mb-2">
            <span class="w-3 h-3 bg-yellow-400 rounded-full animate-pulse"></span>
            <span class="font-semibold">{{ t('battle.readyRoom.waitingOpponent', 'Waiting for opponent...') }}</span>
          </div>
          <p class="text-xs text-slate-500">{{ t('battle.readyRoom.opponentMustReady', 'Your opponent must also press ready') }}</p>
        </div>
      </div>

      <div v-else class="text-center">
        <div class="py-4 px-6 bg-green-500/20 border border-green-500/50 rounded-xl animate-pulse">
          <div class="flex items-center justify-center gap-2 text-green-400 mb-2">
            <span class="text-2xl">🎮</span>
            <span class="font-bold text-lg">{{ t('battle.readyRoom.starting', 'STARTING BATTLE...') }}</span>
          </div>
          <p class="text-xs text-slate-400">{{ t('battle.readyRoom.getReady', 'Get ready for battle!') }}</p>
        </div>
      </div>
    </div>

    <!-- Cancel Button -->
    <button
      v-if="!bothReady"
      @click="emit('cancel')"
      :disabled="loading"
      class="mt-4 text-sm text-slate-500 hover:text-slate-400 transition-colors"
    >
      {{ t('battle.readyRoom.cancel', 'Cancel and Leave') }}
    </button>
  </div>
</template>
