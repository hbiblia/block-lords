<script setup lang="ts">
import { computed } from 'vue';

const props = defineProps<{
  username: string;
  hp: number;
  maxHp?: number;
  shield: number;
  energy?: number;
  maxEnergy?: number;
  isCurrentTurn?: boolean;
  isEnemy?: boolean;
}>();

const maxHpVal = computed(() => props.maxHp || 100);
const maxEnergyVal = computed(() => props.maxEnergy || 3);
const hpPercent = computed(() => Math.max(0, (props.hp / maxHpVal.value) * 100));
const hpColor = computed(() => {
  if (hpPercent.value > 60) return 'bg-green-500';
  if (hpPercent.value > 30) return 'bg-yellow-500';
  return 'bg-red-500';
});
</script>

<template>
  <div class="px-3 py-2" :class="isEnemy ? 'border-b border-border/30' : 'border-t border-border/30'">
    <!-- Username + turn indicator -->
    <div class="flex items-center justify-between mb-1">
      <div class="flex items-center gap-1.5">
        <span v-if="isCurrentTurn" class="w-2 h-2 rounded-full bg-green-400 animate-pulse" />
        <span class="text-xs font-semibold" :class="isEnemy ? 'text-red-300' : 'text-green-300'">
          {{ username }}
        </span>
      </div>
      <!-- Energy (only for self) -->
      <div v-if="energy !== undefined" class="flex items-center gap-0.5">
        <span
          v-for="i in maxEnergyVal"
          :key="i"
          class="w-3 h-3 rounded-sm text-[8px] flex items-center justify-center"
          :class="i <= energy ? 'bg-yellow-500/80 text-black' : 'bg-slate-700 text-slate-500'"
        >&#9889;</span>
      </div>
    </div>

    <!-- HP bar -->
    <div class="flex items-center gap-2 mb-1">
      <span class="text-[10px] text-red-400 w-4">&#9829;</span>
      <div class="flex-1 h-3 bg-slate-800 rounded-full overflow-hidden border border-slate-600/50">
        <div
          class="h-full rounded-full transition-all duration-500"
          :class="hpColor"
          :style="{ width: hpPercent + '%' }"
        />
      </div>
      <span class="text-[10px] text-slate-300 w-14 text-right font-mono">{{ hp }}/{{ maxHpVal }}</span>
    </div>

    <!-- Shield bar -->
    <div class="flex items-center gap-2">
      <span class="text-[10px] text-blue-400 w-4">&#9876;</span>
      <div class="flex-1 h-2 bg-slate-800 rounded-full overflow-hidden border border-slate-600/50">
        <div
          class="h-full rounded-full bg-blue-500 transition-all duration-500"
          :style="{ width: Math.min(shield, 50) * 2 + '%' }"
        />
      </div>
      <span class="text-[10px] text-slate-300 w-14 text-right font-mono">{{ shield }}</span>
    </div>
  </div>
</template>
