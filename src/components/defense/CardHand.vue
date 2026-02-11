<script setup lang="ts">
import type { CardDefinition } from '@/utils/battleCards';
import BattleCard from './BattleCard.vue';

defineProps<{
  cards: CardDefinition[];
  energy: number;
  isMyTurn: boolean;
}>();

const emit = defineEmits<{
  play: [cardId: string];
}>();

function handlePlay(cardId: string) {
  emit('play', cardId);
}
</script>

<template>
  <div class="grid grid-cols-3 gap-1.5 p-2">
    <BattleCard
      v-for="(card, index) in cards"
      :key="`${card.id}-${index}`"
      :card="card"
      :disabled="!isMyTurn || energy < card.cost"
      @play="handlePlay"
    />
    <!-- Empty slots -->
    <div
      v-for="i in Math.max(0, 3 - (cards.length % 3 === 0 ? 3 : cards.length % 3))"
      :key="`empty-${i}`"
      class="rounded-lg border border-border/30 bg-slate-800/20 min-h-[70px]"
      v-show="cards.length % 3 !== 0"
    />
  </div>
</template>
