<script setup lang="ts">
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import PlayerStatus from './PlayerStatus.vue';
import BattleLog from './BattleLog.vue';
import CardHand from './CardHand.vue';
import BattleResult from './BattleResult.vue';
import type { CardDefinition } from '@/utils/battleCards';
import { getCard } from '@/utils/battleCards';
import type { LogEntry } from '@/composables/useCardBattle';

const props = defineProps<{
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

const queuedCards = computed(() => {
  return props.cardsPlayed.map((id) => getCard(id));
});

const totalQueuedCost = computed(() => {
  return queuedCards.value.reduce((sum, c) => sum + c.cost, 0);
});

const timerUrgent = computed(() => props.turnTimer <= 10);
</script>

<template>
  <div class="flex-1 flex flex-col overflow-hidden relative bg-gradient-to-b from-slate-950 via-slate-900 to-slate-950">
    <!-- Enemy status -->
    <PlayerStatus
      :username="enemyUsername"
      :hp="enemyHp"
      :shield="enemyShield"
      :is-current-turn="!isMyTurn"
      :is-enemy="true"
    />

    <!-- Battle log with VS overlay -->
    <div class="relative">
      <!-- VS badge -->
      <div class="absolute -top-3 left-1/2 -translate-x-1/2 z-10">
        <div class="px-2 py-0.5 bg-slate-800 border border-slate-600/50 rounded-full shadow-lg">
          <span class="text-[10px] font-black text-slate-400 tracking-widest">VS</span>
        </div>
      </div>
      <BattleLog
        :entries="battleLog"
        :is-my-turn="isMyTurn"
        :turn-timer="turnTimer"
      />
    </div>

    <!-- Queued cards preview -->
    <div v-if="cardsPlayed.length > 0" class="px-2.5 py-1.5 bg-gradient-to-r from-yellow-500/10 via-amber-500/5 to-yellow-500/10 border-y border-yellow-500/15">
      <div class="flex items-center justify-between mb-1">
        <span class="text-[10px] text-yellow-300 font-bold uppercase tracking-wider flex items-center gap-1">
          &#9889; {{ t('battle.queuedCards', 'Queued') }} ({{ cardsPlayed.length }})
        </span>
        <span class="text-[10px] text-yellow-400/50 font-mono">
          {{ totalQueuedCost }} {{ t('battle.energyUsed', 'energy used') }}
        </span>
      </div>
      <div class="flex gap-1 flex-wrap">
        <span
          v-for="(card, i) in queuedCards"
          :key="i"
          class="inline-flex items-center gap-0.5 px-2 py-0.5 rounded-md text-[9px] font-bold border"
          :class="{
            'bg-red-500/15 text-red-300 border-red-500/20': card.type === 'attack',
            'bg-blue-500/15 text-blue-300 border-blue-500/20': card.type === 'defense',
            'bg-purple-500/15 text-purple-300 border-purple-500/20': card.type === 'special',
          }"
        >
          <span v-if="card.type === 'attack'">&#9876;</span>
          <span v-else-if="card.type === 'defense'">&#128737;</span>
          <span v-else>&#10024;</span>
          {{ t(card.nameKey, card.name) }}
        </span>
      </div>
    </div>

    <!-- Card hand + Action buttons -->
    <div class="flex-1 flex flex-col min-h-0">
      <div class="flex-1 overflow-y-auto flex flex-col">
        <div class="flex-1" />
        <!-- My status -->
        <PlayerStatus
          :username="myUsername"
          :hp="myHp"
          :shield="myShield"
          :energy="myEnergy"
          :is-current-turn="isMyTurn"
        />
        <CardHand
          :cards="handCards"
          :energy="myEnergy"
          :is-my-turn="isMyTurn"
          :cards-played-count="cardsPlayed.length"
          @play="emit('playCard', $event)"
        />
      </div>

      <!-- Action buttons (pinned bottom) -->
      <div class="px-2 py-2 border-t border-slate-800/50">
        <div class="flex gap-2">
          <!-- Undo -->
          <button
            v-if="cardsPlayed.length > 0"
            @click="emit('undo')"
            class="px-3 py-2.5 bg-slate-800 hover:bg-slate-700 text-slate-300 rounded-xl text-xs font-semibold transition-all flex items-center gap-1 border border-slate-700/50 hover:border-slate-600"
          >
            &#8630; {{ t('battle.undo', 'Undo') }}
          </button>

          <!-- End Turn / Waiting -->
          <button
            @click="emit('endTurn')"
            :disabled="!isMyTurn || loading"
            class="flex-1 py-2.5 rounded-xl font-bold text-sm transition-all disabled:opacity-40 border"
            :class="isMyTurn
              ? 'bg-gradient-to-r from-green-600 to-emerald-500 hover:from-green-500 hover:to-emerald-400 text-white shadow-lg shadow-green-500/25 border-green-400/30'
              : 'bg-slate-800 text-slate-500 cursor-not-allowed border-slate-700/50'"
          >
            <span v-if="loading" class="flex items-center justify-center gap-2">
              <span class="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin" />
            </span>
            <span v-else-if="isMyTurn" class="flex items-center justify-center gap-2">
              {{ t('battle.endTurn', 'End Turn') }}
              <span
                class="px-1.5 py-0.5 rounded text-[11px] font-mono font-black"
                :class="timerUrgent ? 'bg-red-500/40 text-red-200 animate-pulse' : 'bg-green-500/25 text-green-200'"
              >{{ turnTimer }}s</span>
            </span>
            <span v-else class="flex items-center justify-center gap-2">
              {{ t('battle.enemyTurn', 'Enemy Turn') }}
              <span class="px-1.5 py-0.5 bg-slate-700/50 rounded text-[11px] font-mono text-slate-400">{{ turnTimer }}s</span>
            </span>
          </button>

          <!-- Forfeit -->
          <button
            @click="emit('forfeit')"
            class="px-3 py-2.5 bg-slate-800 hover:bg-red-500/20 text-red-400 rounded-xl text-xs font-semibold transition-all border border-slate-700/50 hover:border-red-500/30"
            :title="t('battle.forfeit', 'Forfeit')"
          >
            &#9873;
          </button>
        </div>
      </div>
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
