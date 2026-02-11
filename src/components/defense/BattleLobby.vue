<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import type { LobbyEntry } from '@/composables/useCardBattle';
import { BET_AMOUNT } from '@/utils/battleCards';

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
      <div v-if="!inLobby" class="flex-1 flex flex-col items-center justify-center py-8">
        <span class="text-3xl mb-3">&#9876;</span>
        <p class="text-sm text-slate-400 mb-4 text-center px-4">
          {{ t('battle.enterLobbyDesc', { amount: BET_AMOUNT }) }}
        </p>
        <button
          @click="emit('enter')"
          :disabled="loading"
          class="px-6 py-2.5 bg-accent-primary hover:bg-accent-primary/80 text-white rounded-lg font-semibold transition-colors disabled:opacity-50"
        >
          <span v-if="loading">{{ t('common.loading') }}</span>
          <span v-else>{{ t('battle.enterLobby', 'Enter Lobby') }} ({{ BET_AMOUNT }} GC)</span>
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
