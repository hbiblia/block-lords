<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import type { LobbyEntry } from '@/composables/useCardBattle';
import { BET_AMOUNT, MAX_HP, MAX_ENERGY, TURN_DURATION } from '@/utils/battleCards';

defineProps<{
  entries: LobbyEntry[];
  inLobby: boolean;
  loading: boolean;
  error: string | null;
}>();

const emit = defineEmits<{
  enter: [];
  leave: [];
  challenge: [lobbyId: string];
}>();

const { t } = useI18n();
</script>

<template>
  <div class="flex-1 flex flex-col overflow-hidden">
    <!-- Info banner -->
    <div class="px-3 py-2 bg-purple-500/10 border-b border-border/30">
      <p class="text-[11px] text-slate-300">
        {{ t('battle.lobbyInfo', { amount: BET_AMOUNT }) }}
      </p>
    </div>

    <!-- Error display -->
    <div v-if="error" class="mx-2 mt-2 px-3 py-2 bg-red-500/20 border border-red-500/40 rounded-lg">
      <p class="text-xs text-red-400">{{ error }}</p>
    </div>

    <!-- Player list -->
    <div class="flex-1 overflow-y-auto p-2 space-y-1.5">
      <div v-if="!inLobby" class="flex-1 flex flex-col items-center py-4 px-3 space-y-3">
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
            <div class="text-sm font-bold text-green-400">{{ BET_AMOUNT * 2 }} GC</div>
            <div class="text-[9px] text-slate-500">{{ t('battle.info.prizeDesc', 'Winner takes all') }}</div>
          </div>
        </div>

        <!-- Card types info -->
        <div class="w-full bg-slate-800/30 rounded-lg p-2.5 border border-border/20">
          <div class="text-[10px] text-slate-500 uppercase tracking-wider font-semibold mb-1.5">{{ t('battle.info.cardTypes', 'Card Types') }}</div>
          <div class="flex gap-3 justify-center">
            <div class="flex items-center gap-1">
              <span class="w-2 h-2 rounded-full bg-red-500" />
              <span class="text-[10px] text-red-400 font-medium">{{ t('battle.info.attack', 'Attack') }} (5)</span>
            </div>
            <div class="flex items-center gap-1">
              <span class="w-2 h-2 rounded-full bg-blue-500" />
              <span class="text-[10px] text-blue-400 font-medium">{{ t('battle.info.defense', 'Defense') }} (4)</span>
            </div>
            <div class="flex items-center gap-1">
              <span class="w-2 h-2 rounded-full bg-purple-500" />
              <span class="text-[10px] text-purple-400 font-medium">{{ t('battle.info.special', 'Special') }} (3)</span>
            </div>
          </div>
          <p class="text-[9px] text-slate-500 text-center mt-1">{{ t('battle.info.deckInfo', '12 cards total. Both players get the same deck, shuffled randomly.') }}</p>
        </div>

        <!-- Enter button -->
        <button
          @click="emit('enter')"
          :disabled="loading"
          class="w-full py-3 bg-accent-primary hover:bg-accent-primary/80 text-white rounded-lg font-bold text-sm transition-colors disabled:opacity-50 shadow-lg shadow-accent-primary/20"
        >
          <span v-if="loading" class="flex items-center justify-center gap-2">
            <span class="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin" />
            {{ t('common.loading') }}
          </span>
          <span v-else class="flex items-center justify-center gap-2">
            &#9876; {{ t('battle.enterLobby', 'Enter Lobby') }} ({{ BET_AMOUNT }} GC)
          </span>
        </button>
      </div>

      <template v-else>
        <!-- Waiting message -->
        <div v-if="entries.length === 0" class="flex flex-col items-center justify-center py-8">
          <div class="w-6 h-6 border-2 border-accent-primary border-t-transparent rounded-full animate-spin mb-3" />
          <p class="text-sm text-slate-400 text-center">
            {{ t('battle.waitingPlayers', 'Waiting for opponents...') }}
          </p>
        </div>

        <!-- Opponent entries -->
        <button
          v-for="entry in entries"
          :key="entry.id"
          @click="emit('challenge', entry.id)"
          :disabled="loading"
          class="w-full flex items-center justify-between p-3 bg-slate-800/50 hover:bg-slate-700/50 rounded-lg border border-border/30 transition-colors disabled:opacity-50"
        >
          <div class="flex items-center gap-2">
            <div class="w-8 h-8 rounded-full bg-gradient-to-br from-purple-500 to-blue-500 flex items-center justify-center text-xs font-bold text-white">
              {{ entry.username.charAt(0).toUpperCase() }}
            </div>
            <div class="text-left">
              <div class="text-sm font-semibold text-slate-200">{{ entry.username }}</div>
              <div class="text-[10px] text-slate-500">{{ BET_AMOUNT }} GC</div>
            </div>
          </div>
          <span class="text-xs text-accent-primary font-semibold">
            {{ t('battle.fight', 'Fight!') }} &#9876;
          </span>
        </button>
      </template>
    </div>

    <!-- Leave button (when in lobby) -->
    <div v-if="inLobby" class="p-3 border-t border-border/30">
      <button
        @click="emit('leave')"
        :disabled="loading"
        class="w-full py-2 bg-red-500/20 hover:bg-red-500/30 text-red-400 rounded-lg text-sm font-medium transition-colors disabled:opacity-50"
      >
        {{ t('battle.leaveLobby', 'Leave Lobby') }} (+{{ BET_AMOUNT }} GC)
      </button>
    </div>
  </div>
</template>
