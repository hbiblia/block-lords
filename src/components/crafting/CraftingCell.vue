<script setup lang="ts">
import type { CraftingCell } from '@/stores/crafting';

const props = defineProps<{
  cell: CraftingCell;
  zoneType: string;
  disabled: boolean;
  locked: boolean;
  requiredName?: string;
}>();

const emit = defineEmits<{
  tap: [index: number];
}>();

const zoneColors: Record<string, { bg: string; border: string; glow: string }> = {
  forest: { bg: 'bg-emerald-500/10', border: 'border-emerald-500/30', glow: 'shadow-emerald-500/20' },
  mine: { bg: 'bg-amber-500/10', border: 'border-amber-500/30', glow: 'shadow-amber-500/20' },
  meadow: { bg: 'bg-pink-500/10', border: 'border-pink-500/30', glow: 'shadow-pink-500/20' },
  swamp: { bg: 'bg-purple-500/10', border: 'border-purple-500/30', glow: 'shadow-purple-500/20' },
};

function getColors() {
  return zoneColors[props.zoneType] || zoneColors.forest;
}

function handleTap() {
  if (props.disabled || props.cell.collected || props.locked) return;
  emit('tap', props.cell.index);
}

function getTapProgress() {
  if (props.cell.taps_required <= 1) return 100;
  return (props.cell.taps_done / props.cell.taps_required) * 100;
}
</script>

<template>
  <button
    @click="handleTap"
    class="aspect-square rounded-lg border-2 flex flex-col items-center justify-center relative transition-all duration-200 select-none"
    :class="[
      cell.collected
        ? 'bg-slate-800/50 border-slate-600/30 opacity-60'
        : locked
          ? 'bg-slate-900/60 border-slate-700/40 cursor-not-allowed'
          : [getColors().bg, getColors().border, 'hover:shadow-lg active:scale-95', getColors().glow],
      (disabled || locked) && !cell.collected ? 'pointer-events-none' : '',
    ]"
    :disabled="disabled || cell.collected || locked"
  >
    <!-- Collected state -->
    <template v-if="cell.collected">
      <span class="text-xs opacity-50">{{ cell.icon }}</span>
      <div class="absolute inset-0 flex items-center justify-center">
        <span class="text-green-400 text-xl">&#10003;</span>
      </div>
    </template>

    <!-- Locked state -->
    <template v-else-if="locked">
      <span class="text-2xl opacity-20">{{ cell.icon }}</span>
      <div class="absolute inset-0 flex flex-col items-center justify-center">
        <span class="text-lg">🔒</span>
        <span v-if="requiredName" class="text-[9px] text-slate-500 mt-0.5 leading-tight">{{ requiredName }}</span>
      </div>
    </template>

    <!-- Active state -->
    <template v-else>
      <span class="text-2xl sm:text-3xl" :class="{ 'animate-bounce-subtle': cell.taps_done > 0 && cell.taps_done < cell.taps_required }">
        {{ cell.icon }}
      </span>

      <!-- Tap progress indicator -->
      <div v-if="cell.taps_required > 1" class="mt-1 flex gap-0.5">
        <div
          v-for="i in cell.taps_required"
          :key="i"
          class="w-1.5 h-1.5 rounded-full transition-colors"
          :class="i <= cell.taps_done ? 'bg-green-400' : 'bg-slate-600'"
        />
      </div>

      <!-- Progress bar for many taps -->
      <div v-if="cell.taps_required > 4" class="absolute bottom-1 left-1 right-1 h-1 bg-slate-700 rounded-full overflow-hidden">
        <div
          class="h-full bg-green-400 rounded-full transition-all duration-300"
          :style="{ width: getTapProgress() + '%' }"
        />
      </div>
    </template>
  </button>
</template>

<style scoped>
@keyframes bounce-subtle {
  0%, 100% { transform: translateY(0); }
  50% { transform: translateY(-2px); }
}
.animate-bounce-subtle {
  animation: bounce-subtle 0.4s ease-in-out;
}
</style>
