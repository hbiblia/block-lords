<script setup lang="ts">
import { useI18n } from 'vue-i18n';

defineProps<{
  won: boolean;
  reward: number;
}>();

const emit = defineEmits<{
  close: [];
}>();

const { t } = useI18n();
</script>

<template>
  <div class="absolute inset-0 z-10 flex items-center justify-center bg-black/80 backdrop-blur-sm animate-fade-in">
    <div class="text-center px-6 py-8">
      <!-- Result icon -->
      <div class="text-6xl mb-4">
        {{ won ? '&#127942;' : '&#128128;' }}
      </div>

      <!-- Title -->
      <h2
        class="text-2xl font-bold mb-2"
        :class="won ? 'text-yellow-400' : 'text-red-400'"
      >
        {{ won ? t('battle.victory', 'Victory!') : t('battle.defeat', 'Defeat') }}
      </h2>

      <!-- Reward -->
      <div v-if="won" class="text-lg text-green-400 mb-1">
        +{{ reward }} GC
      </div>
      <div v-else class="text-sm text-slate-400 mb-1">
        {{ t('battle.betLost', 'Better luck next time!') }}
      </div>

      <!-- Close button -->
      <button
        @click="emit('close')"
        class="mt-6 px-6 py-2 rounded-lg font-semibold transition-colors"
        :class="won
          ? 'bg-yellow-500 hover:bg-yellow-400 text-black'
          : 'bg-slate-600 hover:bg-slate-500 text-white'"
      >
        {{ t('battle.backToLobby', 'Back to Lobby') }}
      </button>
    </div>
  </div>
</template>
