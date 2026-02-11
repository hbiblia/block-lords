<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import PlayerStatus from './PlayerStatus.vue';
import BattleLog from './BattleLog.vue';
import CardHand from './CardHand.vue';
import BattleResult from './BattleResult.vue';
import type { CardDefinition } from '@/utils/battleCards';
import type { LogEntry } from '@/composables/useCardBattle';

defineProps<{
  myUsername: string;
  enemyUsername: string;
  myHp: number;
  myShield: number;
  myEnergy: number;
  enemyHp: number;
  enemyShield: number;
  isMyTurn: boolean;
  turnTimer: number;
  handCards: CardDefinition[];
  battleLog: LogEntry[];
  cardsPlayed: string[];
  result: { won: boolean; reward: number } | null;
  loading: boolean;
}>();

const emit = defineEmits<{
  playCard: [cardId: string];
  endTurn: [];
  undo: [];
  forfeit: [];
  resultClose: [];
}>();

const { t } = useI18n();
</script>

<template>
  <div class="flex-1 flex flex-col overflow-hidden relative">
    <!-- Enemy status -->
    <PlayerStatus
      :username="enemyUsername"
      :hp="enemyHp"
      :shield="enemyShield"
      :is-current-turn="!isMyTurn"
      :is-enemy="true"
    />

    <!-- Battle log -->
    <BattleLog
      :entries="battleLog"
      :is-my-turn="isMyTurn"
      :turn-timer="turnTimer"
    />

    <!-- My status -->
    <PlayerStatus
      :username="myUsername"
      :hp="myHp"
      :shield="myShield"
      :energy="myEnergy"
      :is-current-turn="isMyTurn"
    />

    <!-- Card hand -->
    <div class="flex-1 overflow-y-auto bg-slate-900/30">
      <CardHand
        :cards="handCards"
        :energy="myEnergy"
        :is-my-turn="isMyTurn"
        @play="emit('playCard', $event)"
      />
    </div>

    <!-- Action buttons -->
    <div class="p-2 border-t border-border/30 flex gap-2">
      <!-- Undo -->
      <button
        v-if="cardsPlayed.length > 0"
        @click="emit('undo')"
        class="px-3 py-2 bg-slate-700 hover:bg-slate-600 text-slate-300 rounded-lg text-xs transition-colors"
      >
        {{ t('battle.undo', 'Undo') }}
      </button>

      <!-- End Turn / Waiting -->
      <button
        @click="emit('endTurn')"
        :disabled="!isMyTurn || loading"
        class="flex-1 py-2.5 rounded-lg font-semibold text-sm transition-all disabled:opacity-50"
        :class="isMyTurn
          ? 'bg-green-600 hover:bg-green-500 text-white'
          : 'bg-slate-700 text-slate-400 cursor-not-allowed'"
      >
        <span v-if="loading">...</span>
        <span v-else-if="isMyTurn">
          {{ t('battle.endTurn', 'End Turn') }} ({{ turnTimer }}s)
        </span>
        <span v-else>
          {{ t('battle.enemyTurn', 'Enemy Turn') }} ({{ turnTimer }}s)
        </span>
      </button>

      <!-- Forfeit -->
      <button
        @click="emit('forfeit')"
        class="px-3 py-2 bg-red-500/20 hover:bg-red-500/30 text-red-400 rounded-lg text-xs transition-colors"
      >
        &#9873;
      </button>
    </div>

    <!-- Result overlay -->
    <BattleResult
      v-if="result"
      :won="result.won"
      :reward="result.reward"
      @close="emit('resultClose')"
    />
  </div>
</template>
