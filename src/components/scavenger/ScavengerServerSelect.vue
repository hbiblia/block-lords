<script setup lang="ts">
import { inject } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAuthStore } from '@/stores/auth';
import { useScavengerStore } from '@/stores/scavenger';
import { SERVER_CONFIGS, type Difficulty } from '@/composables/useScavenger';

const { t } = useI18n();
const authStore = useAuthStore();
const store = useScavengerStore();
const scavenger = inject<ReturnType<typeof import('@/composables/useScavenger').useScavenger>>('scavenger')!;

const difficulties: Difficulty[] = ['easy', 'medium', 'hard'];

const diffColors: Record<Difficulty, { badge: string; border: string; glow: string }> = {
  easy: {
    badge: 'bg-green-500/20 text-green-400 border-green-500/30',
    border: 'border-green-500/20 hover:border-green-500/40',
    glow: 'hover:shadow-[0_0_15px_rgba(34,197,94,0.15)]',
  },
  medium: {
    badge: 'bg-amber-500/20 text-amber-400 border-amber-500/30',
    border: 'border-amber-500/20 hover:border-amber-500/40',
    glow: 'hover:shadow-[0_0_15px_rgba(245,158,11,0.15)]',
  },
  hard: {
    badge: 'bg-red-500/20 text-red-400 border-red-500/30',
    border: 'border-red-500/20 hover:border-red-500/40',
    glow: 'hover:shadow-[0_0_15px_rgba(239,68,68,0.15)]',
  },
};

const diffIcons: Record<Difficulty, string> = {
  easy: '🟢',
  medium: '🟡',
  hard: '🔴',
};

function selectServer(diff: Difficulty) {
  scavenger.startRun(diff);
}

function playerEnergy(): number {
  return authStore.player?.energy ?? 0;
}

function successRate(): string {
  if (store.totalRuns === 0) return '—';
  return Math.round((store.successfulRuns / store.totalRuns) * 100) + '%';
}
</script>

<template>
  <div class="p-4 space-y-3">
    <!-- Title -->
    <div class="text-center mb-4">
      <p class="text-xs text-slate-400">{{ t('scavenger.subtitle', 'Explore abandoned servers for loot') }}</p>
    </div>

    <!-- Server Cards -->
    <div
      v-for="diff in difficulties"
      :key="diff"
      class="rounded-lg border p-3 transition-all cursor-pointer bg-[#252640]/60"
      :class="[
        diffColors[diff].border,
        diffColors[diff].glow,
        playerEnergy() < SERVER_CONFIGS[diff].energyCost ? 'opacity-50 cursor-not-allowed' : '',
      ]"
      @click="playerEnergy() >= SERVER_CONFIGS[diff].energyCost && selectServer(diff)"
    >
      <div class="flex items-center justify-between mb-2">
        <div class="flex items-center gap-2">
          <span class="text-sm">{{ diffIcons[diff] }}</span>
          <span class="text-sm font-semibold text-white">{{ t(`scavenger.serverNames.${diff}`, SERVER_CONFIGS[diff].name) }}</span>
        </div>
        <span
          class="text-[10px] font-bold px-2 py-0.5 rounded-full border"
          :class="diffColors[diff].badge"
        >
          {{ t(`scavenger.difficulty.${diff}`, diff.toUpperCase()) }}
        </span>
      </div>

      <div class="grid grid-cols-4 gap-2 text-[10px]">
        <div class="text-center">
          <div class="text-slate-400">⚡ {{ t('scavenger.cost', 'Cost') }}</div>
          <div class="text-white font-bold">{{ SERVER_CONFIGS[diff].energyCost }}</div>
        </div>
        <div class="text-center">
          <div class="text-slate-400">👟 {{ t('scavenger.movesLabel', 'Moves') }}</div>
          <div class="text-white font-bold">{{ SERVER_CONFIGS[diff].movePool }}</div>
        </div>
        <div class="text-center">
          <div class="text-slate-400">👾 {{ t('scavenger.threats', 'Threats') }}</div>
          <div class="text-white font-bold">{{ SERVER_CONFIGS[diff].enemyCount }}</div>
        </div>
        <div class="text-center">
          <div class="text-slate-400">🪙 {{ t('scavenger.reward', 'Reward') }}</div>
          <div class="text-amber-400 font-bold">{{ SERVER_CONFIGS[diff].gcRange[0] }}-{{ SERVER_CONFIGS[diff].gcRange[1] }}</div>
        </div>
      </div>

      <div v-if="playerEnergy() < SERVER_CONFIGS[diff].energyCost" class="mt-2 text-[10px] text-red-400 text-center">
        {{ t('scavenger.notEnoughEnergy', 'Not enough energy') }} ({{ playerEnergy() }}/{{ SERVER_CONFIGS[diff].energyCost }})
      </div>
    </div>

    <!-- Player Stats -->
    <div class="mt-4 pt-3 border-t border-slate-700/30">
      <div class="grid grid-cols-4 gap-2 text-center text-[10px]">
        <div>
          <div class="text-slate-500">{{ t('scavenger.stats.totalRuns', 'Runs') }}</div>
          <div class="text-white font-bold">{{ store.totalRuns }}</div>
        </div>
        <div>
          <div class="text-slate-500">{{ t('scavenger.stats.successRate', 'Success') }}</div>
          <div class="text-green-400 font-bold">{{ successRate() }}</div>
        </div>
        <div>
          <div class="text-slate-500">{{ t('scavenger.stats.bestHaul', 'Best') }}</div>
          <div class="text-amber-400 font-bold">{{ store.bestHaul }} 🪙</div>
        </div>
        <div>
          <div class="text-slate-500">{{ t('scavenger.stats.totalEarned', 'Earned') }}</div>
          <div class="text-amber-400 font-bold">{{ store.totalGcEarned }} 🪙</div>
        </div>
      </div>
    </div>

    <!-- Legend -->
    <div class="mt-3 pt-3 border-t border-slate-700/30">
      <div class="text-[10px] text-slate-500 mb-1.5">{{ t('scavenger.howToPlay', 'How to play') }}</div>
      <div class="text-[10px] text-slate-400 space-y-0.5">
        <p>{{ t('scavenger.howStep1', 'Click adjacent tiles to move. Each click = 1 turn.') }}</p>
        <p>{{ t('scavenger.howStep2', 'Collect loot and reach the exit to bank it.') }}</p>
        <p>{{ t('scavenger.howStep3', 'Avoid antivirus programs — they chase you each turn!') }}</p>
      </div>
    </div>
  </div>
</template>
