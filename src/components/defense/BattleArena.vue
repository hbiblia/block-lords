<script setup lang="ts">
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import PlayerStatus from './PlayerStatus.vue';
import BattleLog from './BattleLog.vue';
import CardHand from './CardHand.vue';
import BattleResult from './BattleResult.vue';
import type { CardDefinition } from '@/utils/battleCards';
import { getCard } from '@/utils/battleCards';
import type { LogEntry } from '@/composables/useCardBattle';
import { playSound } from '@/utils/sounds';

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

// Combat effects
interface CombatEffect {
  id: number;
  type: string;
  icon: string;
  value: string;
  color: string;
  fromEnemy: boolean;
  label: string;
}

const combatEffects = ref<CombatEffect[]>([]);
let effectCounter = 0;

function spawnEffect(entry: LogEntry, fromEnemy: boolean) {
  let icon = '';
  let value = '';
  let color = '';

  switch (entry.type) {
    case 'attack':
      icon = '\u2694';
      value = `-${entry.damage}`;
      color = 'text-red-400';
      break;
    case 'defense':
      icon = '\uD83D\uDEE1';
      value = `+${entry.shield}`;
      color = 'text-blue-400';
      break;
    case 'special':
      if (entry.heal) {
        icon = '\u2764';
        value = `+${entry.heal}`;
        color = 'text-green-400';
      } else if (entry.weaken) {
        icon = '\u2B07';
        value = `-${entry.weaken}`;
        color = 'text-purple-400';
      } else if (entry.damage) {
        icon = '\u2728';
        value = `-${entry.damage}`;
        color = 'text-purple-400';
      }
      break;
  }

  if (!icon) return;

  // Play sound based on type
  switch (entry.type) {
    case 'attack': playSound('card_attack'); break;
    case 'defense': playSound('card_defense'); break;
    case 'special': entry.heal ? playSound('card_heal') : playSound('card_special'); break;
  }

  const label = fromEnemy
    ? props.enemyUsername
    : props.myUsername;

  const id = ++effectCounter;
  combatEffects.value.push({ id, type: entry.type, icon, value, color, fromEnemy, label });
  setTimeout(() => {
    combatEffects.value = combatEffects.value.filter((e) => e.id !== id);
  }, 3000);
}

watch(
  () => props.battleLog.length,
  (newLen, oldLen) => {
    if (newLen > (oldLen ?? 0)) {
      const latest = props.battleLog[newLen - 1];
      // If it's now my turn, the entries are from the enemy's turn
      const fromEnemy = props.isMyTurn;
      if (latest) spawnEffect(latest, fromEnemy);
    }
  }
);
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
    <div class="relative flex-1 flex flex-col min-h-0 max-h-[30vh]">
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

    <!-- Queued cards preview (always visible) -->
    <div
      class="px-2.5 py-1.5 border-y transition-colors duration-300"
      :class="cardsPlayed.length > 0
        ? 'bg-gradient-to-r from-yellow-500/10 via-amber-500/5 to-yellow-500/10 border-yellow-500/15'
        : 'bg-slate-900/40 border-slate-800/50'"
    >
      <div class="flex items-center justify-between mb-1">
        <span
          class="text-[10px] font-bold uppercase tracking-wider flex items-center gap-1"
          :class="cardsPlayed.length > 0 ? 'text-yellow-300' : 'text-slate-500'"
        >
          &#9889; {{ t('battle.queuedCards', 'Queued') }} ({{ cardsPlayed.length }})
        </span>
        <span class="text-[10px] font-mono" :class="cardsPlayed.length > 0 ? 'text-yellow-400/50' : 'text-slate-600'">
          {{ totalQueuedCost }} {{ t('battle.energyUsed', 'energy used') }}
        </span>
      </div>
      <div v-if="cardsPlayed.length > 0" class="flex gap-1 flex-wrap">
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
      <div v-else class="text-[10px] text-slate-600 italic">
        {{ t('battle.noCardsQueued', 'No cards queued — play cards from your hand') }}
      </div>
    </div>

    <!-- My status (always visible) -->
    <PlayerStatus
      :username="myUsername"
      :hp="myHp"
      :shield="myShield"
      :energy="myEnergy"
      :is-current-turn="isMyTurn"
    />

    <!-- Card hand + Action buttons -->
    <div class="flex flex-col">
      <div class="h-[240px] overflow-y-auto">
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

    <!-- Combat effects overlay -->
    <div class="absolute inset-0 pointer-events-none z-20 overflow-hidden">
      <TransitionGroup name="combat-fx">
        <div
          v-for="fx in combatEffects"
          :key="fx.id"
          class="absolute left-1/2 -translate-x-1/2 flex flex-col items-center"
          :class="fx.fromEnemy ? 'bottom-[45%] combat-effect-up' : 'top-[15%] combat-effect-down'"
        >
          <!-- Label -->
          <span
            class="text-[10px] font-black uppercase tracking-wider px-2 py-0.5 rounded-full mb-1"
            :class="fx.fromEnemy
              ? 'bg-red-500/20 text-red-300 border border-red-500/30'
              : 'bg-emerald-500/20 text-emerald-300 border border-emerald-500/30'"
          >
            {{ fx.label }}
          </span>
          <span class="text-4xl drop-shadow-[0_0_12px_currentColor]" :class="fx.color">
            {{ fx.icon }}
          </span>
          <span class="text-2xl font-black drop-shadow-[0_0_8px_currentColor] mt-1" :class="fx.color">
            {{ fx.value }}
          </span>
        </div>
      </TransitionGroup>
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

<style scoped>
/* Enemy effect: appears near bottom, floats up */
.combat-effect-up {
  animation: combat-pop-up 3s ease-out forwards;
}
@keyframes combat-pop-up {
  0% {
    opacity: 0;
    transform: translateX(-50%) scale(0.3) translateY(30px);
  }
  8% {
    opacity: 1;
    transform: translateX(-50%) scale(1.2) translateY(0);
  }
  15% {
    transform: translateX(-50%) scale(1) translateY(0);
  }
  75% {
    opacity: 1;
    transform: translateX(-50%) scale(1) translateY(-15px);
  }
  100% {
    opacity: 0;
    transform: translateX(-50%) scale(0.8) translateY(-50px);
  }
}
/* My effect: appears near top, floats down */
.combat-effect-down {
  animation: combat-pop-down 3s ease-out forwards;
}
@keyframes combat-pop-down {
  0% {
    opacity: 0;
    transform: translateX(-50%) scale(0.3) translateY(-30px);
  }
  8% {
    opacity: 1;
    transform: translateX(-50%) scale(1.2) translateY(0);
  }
  15% {
    transform: translateX(-50%) scale(1) translateY(0);
  }
  75% {
    opacity: 1;
    transform: translateX(-50%) scale(1) translateY(15px);
  }
  100% {
    opacity: 0;
    transform: translateX(-50%) scale(0.8) translateY(50px);
  }
}
.combat-fx-enter-active {
  transition: all 0.2s ease-out;
}
.combat-fx-leave-active {
  transition: all 0.4s ease-in;
}
.combat-fx-enter-from {
  opacity: 0;
  transform: scale(0.5);
}
.combat-fx-leave-to {
  opacity: 0;
  transform: scale(0.5) translateY(-30px);
}
</style>
