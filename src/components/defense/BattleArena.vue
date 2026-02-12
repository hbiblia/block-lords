<script setup lang="ts">
import { computed, ref, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import PlayerStatus from './PlayerStatus.vue';
import BattleLog from './BattleLog.vue';
import CardHand from './CardHand.vue';
import BattleResult from './BattleResult.vue';
import type { CardDefinition } from '@/utils/battleCards';
import { getCard, getCardTextClass, getCardBorderClass } from '@/utils/battleCards';
import type { LogEntry } from '@/composables/useCardBattle';
import { playBattleSound } from '@/utils/sounds';

const props = defineProps<{
  myUsername: string;
  enemyUsername: string;
  myHp: number;
  myShield: number;
  myEnergy: number;
  enemyHp: number;
  enemyShield: number;
  isMyTurn: boolean;
  animatingEffects: boolean;
  myWeakened?: boolean;
  myBoosted?: boolean;
  enemyWeakened?: boolean;
  enemyBoosted?: boolean;
  myPoison?: number;
  enemyPoison?: number;
  turnTimer: number;
  handCards: (CardDefinition | null)[];
  battleLog: LogEntry[];
  cardsPlayed: string[];
  result: { won: boolean; reward: number; betAmount: number; betCurrency: string } | null;
  loading: boolean;
  myDiscard: string[];
  showRecallPicker: boolean;
}>();

const emit = defineEmits<{
  playCard: [cardId: string];
  endTurn: [];
  undo: [];
  forfeit: [];
  resultClose: [];
  selectRecallTarget: [cardId: string];
  cancelRecall: [];
}>();

const { t } = useI18n();

const queuedCards = computed(() => {
  return props.cardsPlayed.map((id) => {
    // Handle "recall:target_id" format
    if (id.startsWith('recall:')) return getCard('recall');
    return getCard(id);
  });
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
  cardName: string;
  xPos: number; // horizontal position in %
}

const combatEffects = ref<CombatEffect[]>([]);
let effectCounter = 0;

// Taunt overlay
const showTaunt = ref(false);

// Screen flash for big hits
const screenFlash = ref<'red' | 'green' | null>(null);

watch(() => props.myHp, (newVal, oldVal) => {
  if (oldVal === undefined) return;
  const delta = oldVal - newVal;
  if (delta > 30) {
    screenFlash.value = 'red';
    setTimeout(() => { screenFlash.value = null; }, 300);
  }
});

watch(() => props.enemyHp, (newVal, oldVal) => {
  if (oldVal === undefined) return;
  if (newVal > oldVal) {
    screenFlash.value = 'green';
    setTimeout(() => { screenFlash.value = null; }, 300);
  }
  const delta = oldVal - newVal;
  if (delta > 30) {
    screenFlash.value = 'red';
    setTimeout(() => { screenFlash.value = null; }, 300);
  }
});

function spawnEffect(entry: LogEntry, fromEnemy: boolean) {
  let icon = '';
  let value = '';
  let color = '';

  switch (entry.type) {
    case 'attack':
      icon = entry.poison ? '\u2620' : '\u2694';
      value = `-${entry.damage}`;
      color = entry.poison ? 'text-green-400' : 'text-red-400';
      break;
    case 'defense':
      icon = '\uD83D\uDEE1';
      value = `+${entry.shield}`;
      color = 'text-blue-400';
      break;
    case 'special':
      if (entry.poisonTick) {
        icon = '\u2620';
        value = `-${entry.poisonTick}`;
        color = 'text-green-400';
      } else if (entry.boost) {
        icon = '\u2B06';
        value = `+${entry.boost}`;
        color = 'text-yellow-400';
      } else if (entry.draw) {
        icon = '\uD83C\uDCCF';
        value = `+${entry.draw}`;
        color = 'text-cyan-400';
      } else if (entry.damage && entry.heal) {
        icon = '\u2728';
        value = `-${entry.damage}`;
        color = 'text-purple-400';
      } else if (entry.heal) {
        icon = '\u2764';
        value = `+${entry.heal}`;
        color = 'text-green-400';
      } else if (entry.weaken) {
        icon = '\u2B07';
        value = `-${entry.weaken}`;
        color = 'text-purple-400';
      } else if (entry.energyDrain) {
        icon = '\u26A1';
        value = `-${entry.energyDrain}`;
        color = 'text-yellow-400';
      } else if (entry.curePoison) {
        icon = '\uD83E\uDDEA';
        value = '\u2713';
        color = 'text-emerald-400';
      } else if (entry.taunt) {
        icon = '\uD83D\uDE1C';
        value = '!!!';
        color = 'text-orange-400';
      } else if (entry.recall) {
        icon = '\uD83D\uDD04';
        value = '+1';
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
    case 'attack': playBattleSound('card_attack'); break;
    case 'defense': playBattleSound('card_defense'); break;
    case 'special': entry.heal ? playBattleSound('card_heal') : playBattleSound('card_special'); break;
  }

  // Show big taunt overlay when opponent taunts you
  if (entry.taunt && fromEnemy) {
    showTaunt.value = true;
    setTimeout(() => { showTaunt.value = false; }, 2000);
  }

  // Determine if effect targets the opponent (offensive) or self (defensive)
  let isOffensive = false;
  switch (entry.type) {
    case 'attack':
      isOffensive = true;
      break;
    case 'defense':
      isOffensive = false;
      break;
    case 'special':
      isOffensive = !!(entry.damage || entry.weaken || entry.energyDrain || entry.taunt);
      break;
  }

  // Offensive → show target's name; Self → show caster's name
  const label = isOffensive
    ? (fromEnemy ? props.myUsername : props.enemyUsername)
    : (fromEnemy ? props.enemyUsername : props.myUsername);

  const cardDef = entry.card ? getCard(entry.card) : null;
  const cardName = cardDef ? t(cardDef.nameKey, cardDef.name) : '';

  const id = ++effectCounter;
  // Cycle through horizontal positions so effects don't stack
  const positions = [30, 50, 70, 20, 80];
  const xPos = positions[id % positions.length];
  combatEffects.value.push({ id, type: entry.type, icon, value, color, fromEnemy, label, cardName, xPos });
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

// Clear combat effects when battle result appears
watch(
  () => props.result,
  (res) => {
    if (res) {
      combatEffects.value = [];
    }
  }
);

// Game title splash on mount
const showSplash = ref(true);
onMounted(() => {
  setTimeout(() => {
    showSplash.value = false;
  }, 2200);
});
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
      :weakened="enemyWeakened"
      :boosted="enemyBoosted"
      :poison="enemyPoison"
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
      :weakened="myWeakened"
      :boosted="myBoosted"
      :poison="myPoison"
    />

    <!-- Card hand + Action buttons -->
    <div class="flex flex-col">
      <div class="h-[240px] overflow-y-auto">
        <CardHand
          :cards="handCards"
          :energy="myEnergy"
          :is-my-turn="isMyTurn"
          :animating-effects="animatingEffects"
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
            :disabled="!isMyTurn || animatingEffects || loading"
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

    <!-- Screen flash overlay for big hits -->
    <div
      v-if="screenFlash"
      class="absolute inset-0 pointer-events-none z-[15] screen-flash"
      :class="screenFlash === 'red' ? 'bg-red-500/15' : 'bg-green-500/15'"
    />

    <!-- Combat effects overlay -->
    <div class="absolute inset-0 pointer-events-none z-20 overflow-hidden">
      <TransitionGroup name="combat-fx">
        <div
          v-for="fx in combatEffects"
          :key="fx.id"
          class="absolute -translate-x-1/2 flex flex-col items-center"
          :class="fx.fromEnemy ? 'bottom-[45%] combat-effect-up' : 'top-[15%] combat-effect-down'"
          :style="{ left: fx.xPos + '%' }"
        >
          <!-- Card-styled effect -->
          <div
            class="flex flex-col items-center rounded-xl border px-3 py-2 min-w-[80px] backdrop-blur-sm shadow-lg"
            :class="{
              'bg-gradient-to-b from-red-950/90 to-slate-950/90 border-red-500/50 shadow-red-500/20': fx.type === 'attack',
              'bg-gradient-to-b from-blue-950/90 to-slate-950/90 border-blue-500/50 shadow-blue-500/20': fx.type === 'defense',
              'bg-gradient-to-b from-purple-950/90 to-slate-950/90 border-purple-500/50 shadow-purple-500/20': fx.type === 'special',
            }"
          >
            <!-- Top glow line -->
            <div
              class="absolute top-0 left-2 right-2 h-[2px] rounded-full"
              :class="{
                'bg-gradient-to-r from-transparent via-red-400 to-transparent': fx.type === 'attack',
                'bg-gradient-to-r from-transparent via-blue-400 to-transparent': fx.type === 'defense',
                'bg-gradient-to-r from-transparent via-purple-400 to-transparent': fx.type === 'special',
              }"
            />
            <!-- Player label -->
            <span
              class="text-[9px] font-black uppercase tracking-wider px-1.5 py-0.5 rounded mb-1"
              :class="fx.fromEnemy
                ? 'bg-red-500/20 text-red-300'
                : 'bg-emerald-500/20 text-emerald-300'"
            >
              {{ fx.label }}
            </span>
            <!-- Icon -->
            <span class="text-2xl drop-shadow-[0_0_8px_currentColor]" :class="fx.color">
              {{ fx.icon }}
            </span>
            <!-- Card name -->
            <span v-if="fx.cardName" class="text-[9px] font-bold text-slate-300 mt-0.5 text-center leading-tight">
              {{ fx.cardName }}
            </span>
            <!-- Value -->
            <span class="text-xl font-black drop-shadow-[0_0_6px_currentColor] mt-0.5" :class="fx.color">
              {{ fx.value }}
            </span>
          </div>
        </div>
      </TransitionGroup>
    </div>

    <!-- Taunt overlay (when opponent taunts you) -->
    <div
      v-if="showTaunt"
      class="absolute inset-0 z-[25] flex items-center justify-center pointer-events-none"
    >
      <div class="absolute inset-0 bg-orange-950/20" />
      <div class="taunt-animation flex flex-col items-center">
        <span class="text-7xl taunt-bounce">&#128540;</span>
        <div class="mt-2 px-4 py-1.5 rounded-full bg-orange-500/20 border border-orange-500/40 backdrop-blur-sm">
          <span class="text-sm font-black text-orange-300 uppercase tracking-wider">{{ t('battle.cards.taunt', 'Taunt') }}!</span>
        </div>
      </div>
    </div>

    <!-- Recall: Discard Picker Overlay -->
    <div
      v-if="showRecallPicker"
      class="absolute inset-0 z-[30] flex flex-col items-center justify-center"
    >
      <div class="absolute inset-0 bg-black/60 backdrop-blur-sm" @click="emit('cancelRecall')" />
      <div class="relative z-10 bg-slate-900 border border-purple-500/40 rounded-xl p-4 mx-4 max-h-[60vh] overflow-y-auto w-[90%] max-w-sm shadow-2xl shadow-purple-500/10">
        <h3 class="text-sm font-bold text-purple-300 mb-3 text-center">
          {{ t('battle.recallPickTitle', 'Select a card from discard') }}
        </h3>
        <div v-if="myDiscard.length > 0" class="grid grid-cols-3 gap-2">
          <button
            v-for="(cardId, i) in myDiscard"
            :key="i"
            @click="emit('selectRecallTarget', cardId)"
            class="flex flex-col items-center gap-1 p-2 rounded-lg border transition-all hover:scale-105 active:scale-95"
            :class="[
              getCardBorderClass(getCard(cardId).type),
              'bg-slate-800/80 hover:bg-slate-700/80',
            ]"
          >
            <span class="text-lg">
              <span v-if="getCard(cardId).type === 'attack'">&#9876;</span>
              <span v-else-if="getCard(cardId).type === 'defense'">&#128737;</span>
              <span v-else>&#10024;</span>
            </span>
            <span class="text-[10px] font-bold text-center leading-tight" :class="getCardTextClass(getCard(cardId).type)">
              {{ t(getCard(cardId).nameKey, getCard(cardId).name) }}
            </span>
            <span class="text-[9px] text-slate-500">
              &#9889;{{ getCard(cardId).cost }}
            </span>
          </button>
        </div>
        <div v-else class="text-center text-xs text-slate-500 py-4">
          {{ t('battle.recallEmpty', 'No cards in discard pile') }}
        </div>
        <button
          @click="emit('cancelRecall')"
          class="mt-3 w-full py-2 bg-slate-800 hover:bg-slate-700 text-slate-400 rounded-lg text-xs font-medium transition-colors border border-slate-700/50"
        >
          {{ t('common.cancel', 'Cancel') }}
        </button>
      </div>
    </div>

    <!-- Game title splash -->
    <div
      v-if="showSplash"
      class="absolute inset-0 z-[50] flex items-center justify-center pointer-events-none"
    >
      <div class="absolute inset-0 bg-slate-950/90 backdrop-blur-sm splash-bg" />
      <div class="relative flex flex-col items-center splash-content">
        <span class="text-5xl block mb-2">&#9876;</span>
        <h1 class="text-2xl font-bold text-slate-100">{{ t('battle.title', 'Card Battle') }}</h1>
        <p class="text-xs text-slate-400 mt-1">{{ t('battle.gameSubtitle', '1v1 PvP Turn-Based Card Game') }}</p>
      </div>
    </div>

    <!-- Result overlay -->
    <BattleResult
      v-if="result"
      :won="result.won"
      :reward="result.reward"
      :bet-amount="result.betAmount"
      :bet-currency="result.betCurrency"
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

/* Screen flash for big hits */
@keyframes screen-flash {
  0% { opacity: 1; }
  100% { opacity: 0; }
}
.screen-flash {
  animation: screen-flash 300ms ease-out forwards;
}

/* Game title splash */
.splash-content {
  animation: splash-in 400ms ease-out forwards, splash-out 400ms ease-in 1800ms forwards;
}
.splash-bg {
  animation: splash-bg-in 300ms ease-out forwards, splash-bg-out 300ms ease-in 1900ms forwards;
}
@keyframes splash-in {
  0% { opacity: 0; transform: scale(0.7); }
  100% { opacity: 1; transform: scale(1); }
}
@keyframes splash-out {
  0% { opacity: 1; transform: scale(1); }
  100% { opacity: 0; transform: scale(1.1); }
}
@keyframes splash-bg-in {
  0% { opacity: 0; }
  100% { opacity: 1; }
}
@keyframes splash-bg-out {
  0% { opacity: 1; }
  100% { opacity: 0; }
}

/* Taunt overlay */
.taunt-animation {
  animation: taunt-in 300ms ease-out forwards, taunt-out 400ms ease-in 1600ms forwards;
}
@keyframes taunt-in {
  0% { opacity: 0; transform: scale(0.3) rotate(-10deg); }
  60% { opacity: 1; transform: scale(1.15) rotate(3deg); }
  100% { opacity: 1; transform: scale(1) rotate(0deg); }
}
@keyframes taunt-out {
  0% { opacity: 1; transform: scale(1); }
  100% { opacity: 0; transform: scale(0.5) rotate(10deg); }
}
.taunt-bounce {
  animation: taunt-bounce 400ms ease-in-out infinite alternate;
}
@keyframes taunt-bounce {
  0% { transform: scale(1) rotate(-5deg); }
  100% { transform: scale(1.15) rotate(5deg); }
}
</style>
