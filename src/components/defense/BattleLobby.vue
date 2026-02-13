<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import { MAX_HP, MAX_ENERGY, TURN_DURATION, CARD_DEFINITIONS } from '@/utils/battleCards';

const attackCount = CARD_DEFINITIONS.filter(c => c.type === 'attack').length;
const defenseCount = CARD_DEFINITIONS.filter(c => c.type === 'defense').length;
const specialCount = CARD_DEFINITIONS.filter(c => c.type === 'special').length;
const totalCards = CARD_DEFINITIONS.length;

defineProps<{
  loading: boolean;
  error: string | null;
  quickMatchSearching: boolean;
  lobbyCount: number;
  playingCount: number;
}>();

const emit = defineEmits<{
  quickMatch: [];
  cancelQuickMatch: [];
}>();

const { t } = useI18n();
</script>

<template>
  <div class="flex-1 flex flex-col overflow-hidden">
    <!-- Error display -->
    <div v-if="error" class="mx-2 mt-2 px-3 py-2 bg-red-500/20 border border-red-500/40 rounded-lg">
      <p class="text-xs text-red-400">{{ error }}</p>
    </div>

    <div class="flex-1 overflow-y-auto p-2 relative">
      <!-- Searching notification banner -->
      <Transition name="search-toast">
        <div v-if="quickMatchSearching" class="sticky top-0 z-10 mb-2">
          <div class="relative overflow-hidden rounded-xl bg-slate-900/95 border border-emerald-500/30 shadow-lg shadow-emerald-500/10 backdrop-blur-sm">
            <div class="absolute top-0 left-0 right-0 h-[2px] bg-gradient-to-r from-emerald-400 via-cyan-400 to-emerald-400 animate-shimmer"></div>
            <div class="flex items-center gap-3 px-4 py-3">
              <div class="relative flex-shrink-0">
                <div class="w-5 h-5 border-2 border-emerald-400 border-t-transparent rounded-full animate-spin" />
              </div>
              <div class="flex-1 min-w-0">
                <p class="text-[11px] font-bold text-emerald-300/60 uppercase tracking-wider mb-0.5">{{ t('battle.quickMatch', 'Quick Match') }}</p>
                <p class="text-xs font-semibold text-white/90">{{ t('battle.quickMatchSearching', 'Waiting for opponent...') }}</p>
              </div>
              <button
                @click="emit('cancelQuickMatch')"
                :disabled="loading"
                class="flex-shrink-0 px-3 py-1.5 rounded-lg text-[11px] font-bold bg-yellow-500/20 text-yellow-300 hover:bg-yellow-500/30 border border-yellow-500/20 hover:border-yellow-500/40 transition-all disabled:opacity-50"
              >
                {{ t('battle.cancelQuickMatch', 'Cancel Search') }}
              </button>
            </div>
          </div>
        </div>
      </Transition>

      <!-- Welcome screen (always visible) -->
      <div class="flex-1 flex flex-col items-center py-4 px-3 space-y-3">
        <!-- Title -->
        <div class="text-center">
          <span class="text-4xl block mb-1">&#9876;</span>
          <h3 class="text-lg font-bold text-slate-100">{{ t('battle.title', 'Card Battle') }}</h3>
          <p class="text-[11px] text-slate-400 mt-0.5">{{ t('battle.gameSubtitle', '1v1 PvP Turn-Based Card Game') }}</p>
        </div>

        <!-- Game rules grid -->
        <div class="w-full grid grid-cols-2 gap-2">
          <div class="bg-slate-800/40 rounded-lg p-2 border border-border/20">
            <div class="text-[10px] text-slate-500 uppercase tracking-wider font-semibold mb-0.5">{{ t('battle.info.hp', 'Health') }}</div>
            <div class="text-sm font-bold text-red-400">{{ MAX_HP }} HP</div>
            <div class="text-[9px] text-slate-500">{{ t('battle.info.hpDesc', 'Each player starts with') }}</div>
          </div>
          <div class="bg-slate-800/40 rounded-lg p-2 border border-border/20">
            <div class="text-[10px] text-slate-500 uppercase tracking-wider font-semibold mb-0.5">{{ t('battle.info.energy', 'Energy') }}</div>
            <div class="text-sm font-bold text-yellow-400">{{ MAX_ENERGY }} &#9889;</div>
            <div class="text-[9px] text-slate-500">{{ t('battle.info.energyDesc', 'Per turn to play cards') }}</div>
          </div>
          <div class="bg-slate-800/40 rounded-lg p-2 border border-border/20">
            <div class="text-[10px] text-slate-500 uppercase tracking-wider font-semibold mb-0.5">{{ t('battle.info.timer', 'Turn Timer') }}</div>
            <div class="text-sm font-bold text-green-400">{{ TURN_DURATION }}s</div>
            <div class="text-[9px] text-slate-500">{{ t('battle.info.timerDesc', 'Seconds per turn') }}</div>
          </div>
          <div class="bg-slate-800/40 rounded-lg p-2 border border-border/20">
            <div class="text-[10px] text-slate-500 uppercase tracking-wider font-semibold mb-0.5">{{ t('battle.info.prize', 'Prize') }}</div>
            <div class="text-sm font-bold text-green-400">2x</div>
            <div class="text-[9px] text-slate-500">{{ t('battle.info.prizeDesc', 'Winner takes all') }}</div>
          </div>
        </div>

        <!-- Card types info -->
        <div class="w-full bg-slate-800/30 rounded-lg p-2.5 border border-border/20">
          <div class="text-[10px] text-slate-500 uppercase tracking-wider font-semibold mb-1.5">{{ t('battle.info.cardTypes', 'Card Types') }}</div>
          <div class="flex gap-3 justify-center">
            <div class="flex items-center gap-1">
              <span class="w-2 h-2 rounded-full bg-red-500" />
              <span class="text-[10px] text-red-400 font-medium">{{ t('battle.info.attack', 'Attack') }} ({{ attackCount }})</span>
            </div>
            <div class="flex items-center gap-1">
              <span class="w-2 h-2 rounded-full bg-blue-500" />
              <span class="text-[10px] text-blue-400 font-medium">{{ t('battle.info.defense', 'Defense') }} ({{ defenseCount }})</span>
            </div>
            <div class="flex items-center gap-1">
              <span class="w-2 h-2 rounded-full bg-purple-500" />
              <span class="text-[10px] text-purple-400 font-medium">{{ t('battle.info.special', 'Special') }} ({{ specialCount }})</span>
            </div>
          </div>
          <p class="text-[9px] text-slate-500 text-center mt-1">{{ t('battle.info.deckInfo', { count: totalCards }, `${totalCards} cards total. Both players get the same deck, shuffled randomly.`) }}</p>
        </div>

        <!-- Live stats -->
        <div class="flex gap-4">
          <div class="flex items-center gap-1.5 bg-slate-800/50 rounded-lg px-3 py-1.5 border border-border/20">
            <span class="w-2 h-2 rounded-full bg-green-400 animate-pulse" />
            <span class="text-xs text-slate-300 font-medium">{{ lobbyCount }}</span>
            <span class="text-[10px] text-slate-500">{{ t('battle.inLobby', 'in lobby') }}</span>
          </div>
          <div class="flex items-center gap-1.5 bg-slate-800/50 rounded-lg px-3 py-1.5 border border-border/20">
            <span class="w-2 h-2 rounded-full bg-red-400" />
            <span class="text-xs text-slate-300 font-medium">{{ playingCount }}</span>
            <span class="text-[10px] text-slate-500">{{ t('battle.inBattle', 'in battle') }}</span>
          </div>
        </div>

        <!-- Quick Match / Cancel button -->
        <button
          v-if="!quickMatchSearching"
          @click="emit('quickMatch')"
          :disabled="loading"
          class="w-full py-3 bg-gradient-to-r from-green-500 to-emerald-600 hover:from-green-400 hover:to-emerald-500 text-white rounded-lg font-bold text-sm transition-all disabled:opacity-50 shadow-lg shadow-green-500/20"
        >
          <span v-if="loading" class="flex items-center justify-center gap-2">
            <span class="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin" />
            {{ t('common.loading') }}
          </span>
          <span v-else class="flex items-center justify-center gap-2">
            &#9876; {{ t('battle.quickMatch', 'Quick Match') }}
          </span>
        </button>
        <button
          v-else
          @click="emit('cancelQuickMatch')"
          :disabled="loading"
          class="w-full py-3 bg-yellow-500/20 hover:bg-yellow-500/30 text-yellow-400 rounded-lg font-bold text-sm transition-all disabled:opacity-50 border border-yellow-500/30"
        >
          {{ t('battle.cancelQuickMatch', 'Cancel Search') }}
        </button>
      </div>
    </div>
  </div>
</template>

<style scoped>
@keyframes shimmer {
  0% { background-position: -200% 0; }
  100% { background-position: 200% 0; }
}

.animate-shimmer {
  background-size: 200% 100%;
  animation: shimmer 3s linear infinite;
}

.search-toast-enter-active {
  transition: all 0.3s ease-out;
}

.search-toast-leave-active {
  transition: all 0.2s ease-in;
}

.search-toast-enter-from {
  opacity: 0;
  transform: translateY(-10px);
}

.search-toast-leave-to {
  opacity: 0;
  transform: translateY(-10px);
}
</style>
