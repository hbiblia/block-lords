<script setup lang="ts">
import { inject, computed } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const scavenger = inject<ReturnType<typeof import('@/composables/useScavenger').useScavenger>>('scavenger')!;

const movesPercent = computed(() => {
  if (scavenger.movePool.value === 0) return 0;
  return (scavenger.movesRemaining.value / scavenger.movePool.value) * 100;
});

const movesColor = computed(() => {
  if (movesPercent.value > 50) return 'bg-green-500';
  if (movesPercent.value > 25) return 'bg-amber-500';
  return 'bg-red-500';
});

const diffBadge = computed(() => {
  const d = scavenger.difficulty.value;
  if (d === 'easy') return 'bg-green-500/20 text-green-400';
  if (d === 'medium') return 'bg-amber-500/20 text-amber-400';
  return 'bg-red-500/20 text-red-400';
});
</script>

<template>
  <div class="px-3 py-2 border-b border-slate-700/50 bg-[#252640]/50 space-y-1.5">
    <!-- Top row: server name + difficulty + turn -->
    <div class="flex items-center justify-between">
      <div class="flex items-center gap-2">
        <span class="text-xs font-semibold text-white">{{ scavenger.serverName.value }}</span>
        <span class="text-[10px] font-bold px-1.5 py-0.5 rounded-full" :class="diffBadge">
          {{ t(`scavenger.difficulty.${scavenger.difficulty.value}`, scavenger.difficulty.value) }}
        </span>
      </div>
      <div class="flex items-center gap-3 text-[10px]">
        <span class="text-slate-400">
          {{ t('scavenger.turn', 'Turn') }} {{ scavenger.turnCount.value }}
        </span>
        <span class="text-amber-400 font-bold">
          🪙 {{ scavenger.gcCollected.value }}
        </span>
      </div>
    </div>

    <!-- Moves bar -->
    <div class="flex items-center gap-2">
      <span class="text-[10px] text-slate-400 w-10 shrink-0">
        👟 {{ scavenger.movesRemaining.value }}
      </span>
      <div class="flex-1 h-1.5 bg-slate-700/50 rounded-full overflow-hidden">
        <div
          class="h-full rounded-full transition-all duration-300"
          :class="movesColor"
          :style="{ width: movesPercent + '%' }"
        />
      </div>
    </div>

    <!-- Indicators -->
    <div class="flex items-center gap-3 text-[10px]">
      <span v-if="scavenger.hasKeycard.value" class="text-purple-400">🔑 {{ t('scavenger.hasKey', 'Keycard') }}</span>
      <span v-if="scavenger.dataFragments.value > 0" class="text-purple-400">
        📡 {{ scavenger.dataFragments.value }}/3
      </span>
    </div>
  </div>
</template>
