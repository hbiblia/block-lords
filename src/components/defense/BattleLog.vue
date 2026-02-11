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
  switch (entry.type) {
    case 'attack':
      if (entry.selfDamage) {
        return `${card.name}: ${entry.damage} dmg, -${entry.selfDamage} self`;
      }
      return `${card.name}: ${entry.damage} dmg`;
    case 'defense':
      if (entry.counterDamage) {
        return `${card.name}: +${entry.shield} shield, ${entry.counterDamage} counter`;
      }
      if (entry.draw) {
        return `${card.name}: +${entry.shield} shield, +${entry.draw} card`;
      }
      return `${card.name}: +${entry.shield} shield`;
    case 'special':
      if (entry.damage && entry.heal) {
        return `${card.name}: ${entry.damage} dmg, +${entry.heal} HP`;
      }
      if (entry.heal) {
        return `${card.name}: +${entry.heal} HP`;
      }
      if (entry.weaken) {
        return `${card.name}: enemy -${entry.weaken} dmg next`;
      }
      return card.name;
    default:
      return card.name;
  }
}

function getEntryColor(entry: LogEntry): string {
  switch (entry.type) {
    case 'attack': return 'text-red-400';
    case 'defense': return 'text-blue-400';
    case 'special': return 'text-purple-400';
    default: return 'text-slate-400';
  }
}
</script>

<template>
  <div
    ref="logContainer"
    class="h-16 overflow-y-auto px-3 py-1 border-y border-border/30 bg-slate-900/50 text-[10px] space-y-0.5 scrollbar-thin"
  >
    <div
      v-for="(entry, i) in entries"
      :key="i"
      class="flex items-center gap-1"
    >
      <span class="text-slate-600">&gt;</span>
      <span :class="getEntryColor(entry)">{{ formatEntry(entry) }}</span>
    </div>

    <!-- Turn indicator -->
    <div v-if="entries.length === 0 && isMyTurn" class="text-yellow-400 animate-pulse">
      &gt; {{ t('battle.yourTurn', 'Your turn!') }} ({{ turnTimer }}s)
    </div>
    <div v-else-if="entries.length === 0" class="text-slate-500">
      &gt; {{ t('battle.waitingTurn', 'Waiting for opponent...') }} ({{ turnTimer }}s)
    </div>
    <div v-else-if="isMyTurn" class="text-yellow-400 animate-pulse">
      &gt; {{ t('battle.yourTurn', 'Your turn!') }} ({{ turnTimer }}s)
    </div>
    <div v-else class="text-slate-500">
      &gt; {{ t('battle.waitingTurn', 'Waiting...') }} ({{ turnTimer }}s)
    </div>
  </div>
</template>
