<script setup lang="ts">
import { ref, watch, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import type { LogEntry } from '@/composables/useCardBattle';
import { getCard } from '@/utils/battleCards';

const props = defineProps<{
  entries: LogEntry[];
  isMyTurn: boolean;
  turnTimer: number;
}>();

const { t } = useI18n();
const logContainer = ref<HTMLElement | null>(null);
const turnFlash = ref(false);

watch(
  () => props.entries.length,
  async () => {
    await nextTick();
    if (logContainer.value) {
      logContainer.value.scrollTop = logContainer.value.scrollHeight;
    }
  }
);

watch(
  () => props.isMyTurn,
  (myTurn) => {
    if (myTurn) {
      turnFlash.value = true;
      setTimeout(() => { turnFlash.value = false; }, 1500);
    }
  }
);

function formatEntry(entry: LogEntry): string {
  if (entry.type === 'storm') {
    return t('battle.log.bloodStorm', { dmg: entry.stormDamage });
  }
  const card = getCard(entry.card);
  const cardName = t(card.nameKey, card.name);

  switch (entry.type) {
    case 'attack':
      if (entry.selfDamage) {
        return t('battle.log.attackSelf', {
          card: cardName, dmg: entry.damage, self: entry.selfDamage
        });
      }
      if (entry.poison) {
        return t('battle.log.poison', {
          card: cardName, dmg: entry.damage, turns: entry.poison
        });
      }
      return t('battle.log.attack', { card: cardName, dmg: entry.damage });
    case 'defense':
      if (entry.counterDamage) {
        return t('battle.log.defenseCounter', {
          card: cardName, shield: entry.shield, dmg: entry.counterDamage
        });
      }
      if (entry.draw) {
        return t('battle.log.defenseDraw', {
          card: cardName, shield: entry.shield, draw: entry.draw
        });
      }
      if (entry.heal) {
        return t('battle.log.defenseHeal', {
          card: cardName, shield: entry.shield, heal: entry.heal
        });
      }
      return t('battle.log.defense', { card: cardName, shield: entry.shield });
    case 'special':
      if (entry.poisonTick) {
        return t('battle.log.poisonTick', { dmg: entry.poisonTick });
      }
      if (entry.energyDrain) {
        return t('battle.log.energyDrain', {
          card: cardName, amount: entry.energyDrain
        });
      }
      if (entry.damage && entry.heal) {
        return t('battle.log.drain', {
          card: cardName, dmg: entry.damage, heal: entry.heal
        });
      }
      if (entry.heal) {
        return t('battle.log.heal', { card: cardName, heal: entry.heal });
      }
      if (entry.weaken) {
        return t('battle.log.weaken', {
          card: cardName, reduction: entry.weaken
        });
      }
      if (entry.boost) {
        return t('battle.log.boost', {
          card: cardName, amount: entry.boost
        });
      }
      if (entry.draw) {
        return t('battle.log.draw', {
          card: cardName, amount: entry.draw
        });
      }
      if (entry.curePoison) {
        return t('battle.log.curePoison', { card: cardName });
      }
      if (entry.taunt) {
        return t('battle.log.taunt', { card: cardName });
      }
      if (entry.recall) {
        const targetCard = getCard(entry.recall);
        const targetName = t(targetCard.nameKey, targetCard.name);
        return t('battle.log.recall', { card: cardName, target: targetName });
      }
      if (entry.damage) {
        return t('battle.log.execute', {
          card: cardName, dmg: entry.damage
        });
      }
      return cardName;
    default:
      return cardName;
  }
}
</script>

<template>
  <div
    ref="logContainer"
    class="flex-1 overflow-y-auto px-2 py-2 bg-slate-950/60 text-xs space-y-1 scrollbar-thin scrollbar-thumb-slate-700 scrollbar-track-transparent"
  >
    <!-- Log entries -->
    <div
      v-for="(entry, i) in entries"
      :key="i"
      class="flex items-center gap-2 px-2.5 py-1.5 rounded-lg transition-all duration-200"
      :class="{
        'bg-red-500/8 border-l-2 border-red-500/40': entry.type === 'attack',
        'bg-blue-500/8 border-l-2 border-blue-500/40': entry.type === 'defense',
        'bg-purple-500/8 border-l-2 border-purple-500/40': entry.type === 'special',
        'bg-red-500/15 border-l-2 border-red-600/50': entry.type === 'storm',
      }"
    >
      <!-- Type icon -->
      <span
        class="w-5 h-5 rounded flex items-center justify-center text-[11px] flex-shrink-0"
        :class="{
          'bg-red-500/20 text-red-400': entry.type === 'attack',
          'bg-blue-500/20 text-blue-400': entry.type === 'defense',
          'bg-purple-500/20 text-purple-400': entry.type === 'special',
          'bg-red-600/20 text-red-500': entry.type === 'storm',
        }"
      >
        <span v-if="entry.type === 'attack'">&#9876;</span>
        <span v-else-if="entry.type === 'defense'">&#128737;</span>
        <span v-else-if="entry.type === 'storm'">&#9760;</span>
        <span v-else>&#10024;</span>
      </span>

      <!-- Entry text -->
      <span
        class="font-semibold leading-tight"
        :class="{
          'text-red-300/90': entry.type === 'attack',
          'text-blue-300/90': entry.type === 'defense',
          'text-purple-300/90': entry.type === 'special',
          'text-red-400/90': entry.type === 'storm',
        }"
      >
        {{ formatEntry(entry) }}
      </span>

      <!-- Damage/value badge -->
      <span
        v-if="entry.damage"
        class="ml-auto text-[11px] font-black px-2 py-0.5 rounded flex-shrink-0"
        :class="entry.type === 'attack'
          ? 'bg-red-500/20 text-red-300'
          : 'bg-purple-500/20 text-purple-300'"
      >
        -{{ entry.damage }}
      </span>
      <span
        v-else-if="entry.shield"
        class="ml-auto text-[11px] font-black px-2 py-0.5 rounded bg-blue-500/20 text-blue-300 flex-shrink-0"
      >
        +{{ entry.shield }}
      </span>
      <span
        v-else-if="entry.heal"
        class="ml-auto text-[11px] font-black px-2 py-0.5 rounded bg-green-500/20 text-green-300 flex-shrink-0"
      >
        +{{ entry.heal }}
      </span>
      <span
        v-else-if="entry.boost"
        class="ml-auto text-[11px] font-black px-2 py-0.5 rounded bg-yellow-500/20 text-yellow-300 flex-shrink-0"
      >
        +{{ entry.boost }}
      </span>
      <span
        v-else-if="entry.draw"
        class="ml-auto text-[11px] font-black px-2 py-0.5 rounded bg-cyan-500/20 text-cyan-300 flex-shrink-0"
      >
        +{{ entry.draw }}
      </span>
      <span
        v-else-if="entry.poisonTick"
        class="ml-auto text-[11px] font-black px-2 py-0.5 rounded bg-green-500/20 text-green-300 flex-shrink-0"
      >
        -{{ entry.poisonTick }}
      </span>
      <span
        v-else-if="entry.energyDrain"
        class="ml-auto text-[11px] font-black px-2 py-0.5 rounded bg-yellow-500/20 text-yellow-300 flex-shrink-0"
      >
        -{{ entry.energyDrain }}
      </span>
      <span
        v-else-if="entry.curePoison"
        class="ml-auto text-[11px] font-black px-2 py-0.5 rounded bg-emerald-500/20 text-emerald-300 flex-shrink-0"
      >
        &#10003;
      </span>
      <span
        v-else-if="entry.taunt"
        class="ml-auto text-[11px] font-black px-2 py-0.5 rounded bg-orange-500/20 text-orange-300 flex-shrink-0"
      >
        &#128540;
      </span>
      <span
        v-else-if="entry.recall"
        class="ml-auto text-[11px] font-black px-2 py-0.5 rounded bg-purple-500/20 text-purple-300 flex-shrink-0"
      >
        &#128260;
      </span>
      <span
        v-else-if="entry.stormDamage"
        class="ml-auto text-[11px] font-black px-2 py-0.5 rounded bg-red-600/20 text-red-300 flex-shrink-0"
      >
        -{{ entry.stormDamage }}
      </span>
    </div>

    <!-- Turn status indicator (always at bottom) -->
    <div
      class="flex items-center gap-2 px-3 py-2 rounded-xl mt-1.5 transition-all duration-500"
      :class="[
        isMyTurn
          ? 'bg-gradient-to-r from-yellow-500/15 via-amber-500/10 to-yellow-500/15 border border-yellow-500/30 shadow-lg shadow-yellow-500/10'
          : 'bg-slate-800/40 border border-slate-700/30',
        turnFlash ? 'animate-turn-flash scale-[1.02]' : '',
      ]"
    >
      <span v-if="isMyTurn" class="relative flex h-3 w-3 flex-shrink-0">
        <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-yellow-400 opacity-75" />
        <span class="relative inline-flex rounded-full h-3 w-3 bg-yellow-400" />
      </span>
      <span v-else class="w-3 h-3 rounded-full bg-slate-600 flex-shrink-0" />

      <span
        class="font-black flex-1 text-sm"
        :class="isMyTurn ? 'text-yellow-300' : 'text-slate-500'"
      >
        {{ isMyTurn ? t('battle.yourTurn', 'Your turn!') : t('battle.waitingTurn', 'Waiting...') }}
      </span>

      <span
        class="font-mono font-black text-sm px-2 py-0.5 rounded-lg"
        :class="isMyTurn
          ? (turnTimer <= 10 ? 'bg-red-500/30 text-red-300 animate-pulse' : 'bg-yellow-500/20 text-yellow-300')
          : 'bg-slate-700/50 text-slate-500'"
      >
        {{ turnTimer }}s
      </span>
    </div>
  </div>
</template>

<style scoped>
@keyframes turn-flash {
  0% { box-shadow: 0 0 0 0 rgba(234, 179, 8, 0.6); }
  30% { box-shadow: 0 0 20px 4px rgba(234, 179, 8, 0.4); }
  100% { box-shadow: 0 0 0 0 rgba(234, 179, 8, 0); }
}
.animate-turn-flash {
  animation: turn-flash 1.5s ease-out;
}
</style>
