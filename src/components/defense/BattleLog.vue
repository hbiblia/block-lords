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

watch(
  () => props.entries.length,
  async () => {
    await nextTick();
    if (logContainer.value) {
      logContainer.value.scrollTop = logContainer.value.scrollHeight;
    }
  }
);

function formatEntry(entry: LogEntry): string {
  const card = getCard(entry.card);
  const cardName = t(card.nameKey, card.name);

  switch (entry.type) {
    case 'attack':
      if (entry.selfDamage) {
        return t('battle.log.attackSelf', {
          card: cardName, dmg: entry.damage, self: entry.selfDamage
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
      return t('battle.log.defense', { card: cardName, shield: entry.shield });
    case 'special':
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
      return cardName;
    default:
      return cardName;
  }
}
</script>

<template>
  <div
    ref="logContainer"
    class="h-24 overflow-y-auto px-2 py-1.5 bg-slate-950/60 text-[10px] space-y-0.5 scrollbar-thin scrollbar-thumb-slate-700 scrollbar-track-transparent"
  >
    <!-- Log entries -->
    <div
      v-for="(entry, i) in entries"
      :key="i"
      class="flex items-center gap-1.5 px-2 py-1 rounded-lg transition-all duration-200"
      :class="{
        'bg-red-500/8 border-l-2 border-red-500/40': entry.type === 'attack',
        'bg-blue-500/8 border-l-2 border-blue-500/40': entry.type === 'defense',
        'bg-purple-500/8 border-l-2 border-purple-500/40': entry.type === 'special',
      }"
    >
      <!-- Type icon -->
      <span
        class="w-4 h-4 rounded flex items-center justify-center text-[9px] flex-shrink-0"
        :class="{
          'bg-red-500/20 text-red-400': entry.type === 'attack',
          'bg-blue-500/20 text-blue-400': entry.type === 'defense',
          'bg-purple-500/20 text-purple-400': entry.type === 'special',
        }"
      >
        <span v-if="entry.type === 'attack'">&#9876;</span>
        <span v-else-if="entry.type === 'defense'">&#128737;</span>
        <span v-else>&#10024;</span>
      </span>

      <!-- Entry text -->
      <span
        class="font-medium leading-tight"
        :class="{
          'text-red-300/90': entry.type === 'attack',
          'text-blue-300/90': entry.type === 'defense',
          'text-purple-300/90': entry.type === 'special',
        }"
      >
        {{ formatEntry(entry) }}
      </span>

      <!-- Damage/value badge -->
      <span
        v-if="entry.damage"
        class="ml-auto text-[9px] font-black px-1.5 py-0.5 rounded flex-shrink-0"
        :class="entry.type === 'attack'
          ? 'bg-red-500/20 text-red-300'
          : 'bg-purple-500/20 text-purple-300'"
      >
        -{{ entry.damage }}
      </span>
      <span
        v-else-if="entry.shield"
        class="ml-auto text-[9px] font-black px-1.5 py-0.5 rounded bg-blue-500/20 text-blue-300 flex-shrink-0"
      >
        +{{ entry.shield }}
      </span>
      <span
        v-else-if="entry.heal"
        class="ml-auto text-[9px] font-black px-1.5 py-0.5 rounded bg-green-500/20 text-green-300 flex-shrink-0"
      >
        +{{ entry.heal }}
      </span>
    </div>

    <!-- Turn status indicator (always at bottom) -->
    <div
      class="flex items-center gap-2 px-2 py-1.5 rounded-lg mt-1"
      :class="isMyTurn
        ? 'bg-gradient-to-r from-yellow-500/10 to-amber-500/5 border border-yellow-500/20'
        : 'bg-slate-800/40 border border-slate-700/30'"
    >
      <span v-if="isMyTurn" class="relative flex h-2 w-2 flex-shrink-0">
        <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-yellow-400 opacity-75" />
        <span class="relative inline-flex rounded-full h-2 w-2 bg-yellow-400" />
      </span>
      <span v-else class="w-2 h-2 rounded-full bg-slate-600 flex-shrink-0" />

      <span
        class="font-bold flex-1"
        :class="isMyTurn ? 'text-yellow-300' : 'text-slate-500'"
      >
        {{ isMyTurn ? t('battle.yourTurn', 'Your turn!') : t('battle.waitingTurn', 'Waiting...') }}
      </span>

      <span
        class="font-mono font-black text-[11px] px-1.5 py-0.5 rounded"
        :class="isMyTurn
          ? (turnTimer <= 10 ? 'bg-red-500/30 text-red-300 animate-pulse' : 'bg-yellow-500/20 text-yellow-300')
          : 'bg-slate-700/50 text-slate-500'"
      >
        {{ turnTimer }}s
      </span>
    </div>
  </div>
</template>
