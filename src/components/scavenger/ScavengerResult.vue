<script setup lang="ts">
import { inject, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useScavengerStore } from '@/stores/scavenger';

const { t } = useI18n();
const store = useScavengerStore();
const scavenger = inject<ReturnType<typeof import('@/composables/useScavenger').useScavenger>>('scavenger')!;

const isSuccess = computed(() => scavenger.result.value === 'success');

const resultTitle = computed(() => {
  switch (scavenger.result.value) {
    case 'success': return t('scavenger.result.success', 'Escaped Successfully!');
    case 'caught': return t('scavenger.result.caught', 'Caught by Antivirus!');
    case 'no_moves': return t('scavenger.result.noMoves', 'Out of Moves!');
    case 'abandoned': return t('scavenger.result.abandoned', 'Run Abandoned');
    default: return '';
  }
});

const resultIcon = computed(() => {
  switch (scavenger.result.value) {
    case 'success': return '🏆';
    case 'caught': return '👾';
    case 'no_moves': return '⏱️';
    case 'abandoned': return '🏳️';
    default: return '';
  }
});

function playAgain() {
  scavenger.cleanup();
  store.setPhase('select');
}
</script>

<template>
  <div class="p-6 text-center space-y-4">
    <!-- Result icon & title -->
    <div>
      <div class="text-4xl mb-2">{{ resultIcon }}</div>
      <h2
        class="text-lg font-bold"
        :class="isSuccess ? 'text-green-400' : 'text-red-400'"
      >
        {{ resultTitle }}
      </h2>
      <p class="text-xs text-slate-400 mt-1">
        {{ t('scavenger.turn', 'Turn') }} {{ scavenger.turnCount.value }} · {{ scavenger.serverName.value }}
      </p>
    </div>

    <!-- Loot summary (success only) -->
    <div v-if="isSuccess && scavenger.collectedLoot.value.length > 0" class="space-y-2">
      <div class="border border-green-500/20 rounded-lg bg-green-500/5 p-3">
        <div class="text-[10px] text-green-400/60 uppercase tracking-wider mb-2">
          {{ t('scavenger.result.lootBanked', 'Loot Banked') }}
        </div>

        <!-- GC total -->
        <div class="text-2xl font-bold text-amber-400 mb-2">
          +{{ scavenger.gcCollected.value }} 🪙
        </div>

        <!-- Loot items list -->
        <div class="space-y-1">
          <div
            v-for="(item, i) in scavenger.collectedLoot.value"
            :key="i"
            class="flex items-center justify-between text-xs px-2 py-1 rounded bg-black/20"
          >
            <span class="text-slate-300">{{ item.name }}</span>
            <span
              :class="{
                'text-amber-400': item.type === 'gc' || item.type === 'terminal_bonus',
                'text-cyan-400': item.type === 'material',
                'text-purple-400': item.type === 'data_fragment',
              }"
            >
              {{ item.type === 'gc' || item.type === 'terminal_bonus' ? `+${item.value} GC` : item.rarity || '×1' }}
            </span>
          </div>
        </div>

        <!-- Data fragment bonus -->
        <div
          v-if="scavenger.dataFragments.value >= 3"
          class="mt-2 text-xs text-purple-400 font-semibold"
        >
          📡 {{ t('scavenger.result.dataBonus', 'Data Fragment Bonus!') }}
        </div>
      </div>
    </div>

    <!-- Failure message -->
    <div v-if="!isSuccess" class="text-xs text-slate-400">
      {{ t('scavenger.result.lootLost', 'All collected loot has been lost.') }}
    </div>

    <!-- Buttons -->
    <div class="flex items-center justify-center gap-3 pt-2">
      <button
        @click="playAgain"
        class="px-4 py-2 rounded-lg text-sm font-semibold transition-all"
        :class="isSuccess
          ? 'bg-green-500/20 text-green-400 hover:bg-green-500/30 border border-green-500/30'
          : 'bg-amber-500/20 text-amber-400 hover:bg-amber-500/30 border border-amber-500/30'"
      >
        {{ t('scavenger.result.playAgain', 'Play Again') }}
      </button>
    </div>
  </div>
</template>
