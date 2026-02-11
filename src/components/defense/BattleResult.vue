<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import { BET_AMOUNT } from '@/utils/battleCards';

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
  <div class="absolute inset-0 z-10 flex items-center justify-center overflow-hidden">
    <!-- Dark overlay with blur -->
    <div class="absolute inset-0 bg-black/85 backdrop-blur-md" />

    <!-- Animated radial glow -->
    <div
      class="absolute w-80 h-80 rounded-full opacity-30 animate-pulse"
      :class="won
        ? 'bg-gradient-radial from-yellow-500/50 via-amber-500/20 to-transparent'
        : 'bg-gradient-radial from-red-500/30 via-red-500/10 to-transparent'"
    />

    <!-- Content -->
    <div class="relative text-center px-8 py-10 max-w-xs z-[1]">
      <!-- Decorative top line -->
      <div
        class="w-16 h-[2px] mx-auto mb-6 rounded-full"
        :class="won
          ? 'bg-gradient-to-r from-transparent via-yellow-400 to-transparent'
          : 'bg-gradient-to-r from-transparent via-red-500 to-transparent'"
      />

      <!-- Result icon with glow ring -->
      <div class="relative mx-auto w-24 h-24 mb-5">
        <div
          class="absolute inset-0 rounded-full animate-ping opacity-20"
          :class="won ? 'bg-yellow-400' : 'bg-red-500'"
        />
        <div
          class="absolute inset-1 rounded-full animate-pulse"
          :class="won
            ? 'bg-gradient-to-br from-yellow-400/20 to-amber-500/10 border-2 border-yellow-400/40'
            : 'bg-gradient-to-br from-red-500/20 to-rose-500/10 border-2 border-red-500/30'"
        />
        <div class="absolute inset-0 flex items-center justify-center">
          <span class="text-5xl" :class="won ? 'animate-bounce' : ''">
            {{ won ? '&#127942;' : '&#128128;' }}
          </span>
        </div>
      </div>

      <!-- Title -->
      <h2
        class="text-3xl font-black mb-1 tracking-tight"
        :class="won ? 'text-yellow-400' : 'text-red-400'"
      >
        {{ won ? t('battle.victory', 'Victory!') : t('battle.defeat', 'Defeat') }}
      </h2>

      <!-- Subtitle -->
      <p class="text-xs text-slate-500 mb-5 font-medium">
        {{ won ? t('battle.rewardDesc', 'Prize pool collected') : t('battle.betLost', 'Better luck next time!') }}
      </p>

      <!-- Reward card -->
      <div
        class="mx-auto max-w-[180px] rounded-xl px-5 py-3 mb-6 border"
        :class="won
          ? 'bg-gradient-to-b from-yellow-500/15 to-amber-500/5 border-yellow-500/25'
          : 'bg-gradient-to-b from-red-500/10 to-slate-900/50 border-red-500/20'"
      >
        <div
          class="text-2xl font-black mb-0.5"
          :class="won ? 'text-green-400' : 'text-red-400/80'"
        >
          {{ won ? '+' : '-' }}{{ won ? reward : BET_AMOUNT }} GC
        </div>
        <div class="text-[10px] font-medium" :class="won ? 'text-yellow-400/60' : 'text-red-400/40'">
          {{ won ? t('battle.netGain', 'Net gain') : t('battle.entryFeeLost', 'Entry fee lost') }}
        </div>
      </div>

      <!-- Decorative bottom line -->
      <div
        class="w-16 h-[2px] mx-auto mb-5 rounded-full"
        :class="won
          ? 'bg-gradient-to-r from-transparent via-yellow-400 to-transparent'
          : 'bg-gradient-to-r from-transparent via-red-500 to-transparent'"
      />

      <!-- Close button -->
      <button
        @click="emit('close')"
        class="px-10 py-3 rounded-xl font-bold text-sm transition-all shadow-lg border"
        :class="won
          ? 'bg-gradient-to-r from-yellow-500 to-amber-500 hover:from-yellow-400 hover:to-amber-400 text-black shadow-yellow-500/25 border-yellow-400/30 hover:shadow-yellow-500/40'
          : 'bg-gradient-to-r from-slate-700 to-slate-600 hover:from-slate-600 hover:to-slate-500 text-white shadow-slate-500/20 border-slate-500/30'"
      >
        {{ t('battle.backToLobby', 'Back to Lobby') }}
      </button>
    </div>
  </div>
</template>
