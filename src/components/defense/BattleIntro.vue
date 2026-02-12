<script setup lang="ts">
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { playBattleSound } from '@/utils/sounds';

defineProps<{
  myUsername: string;
  enemyUsername: string;
  betAmount: number;
  betCurrency: string;
}>();

const emit = defineEmits<{
  done: [];
}>();

const { t } = useI18n();

const phase = ref<'enter' | 'vs' | 'fight' | 'exit'>('enter');

onMounted(() => {
  playBattleSound('battle_start');

  // Phase 1: Players slide in (0 -> 1200ms)
  setTimeout(() => {
    phase.value = 'vs';
  }, 1200);

  // Phase 2: VS appears (1200ms -> 3200ms)
  setTimeout(() => {
    phase.value = 'fight';
  }, 3200);

  // Phase 3: FIGHT! flash (3200ms -> 5200ms)
  setTimeout(() => {
    phase.value = 'exit';
  }, 5200);

  // Phase 4: Exit and start battle (5200ms -> 6000ms)
  setTimeout(() => {
    emit('done');
  }, 6000);
});
</script>

<template>
  <div class="flex-1 flex flex-col items-center justify-center relative overflow-hidden bg-gradient-to-b from-slate-950 via-slate-900 to-slate-950">
    <!-- Animated background lines -->
    <div class="absolute inset-0 overflow-hidden">
      <div class="intro-bg-line intro-bg-line-1" />
      <div class="intro-bg-line intro-bg-line-2" />
      <div class="intro-bg-line intro-bg-line-3" />
    </div>

    <!-- Prize pool -->
    <div
      class="absolute top-6 text-center transition-all duration-500"
      :class="phase === 'enter' ? 'opacity-0 -translate-y-4' : 'opacity-100 translate-y-0'"
    >
      <div class="text-[10px] text-slate-500 uppercase tracking-widest font-semibold">{{ t('battle.intro.prizePool', 'Prize Pool') }}</div>
      <div class="text-lg font-black text-yellow-400">{{ betAmount * 2 }} {{ betCurrency }}</div>
    </div>

    <!-- Player 1 (You) - slides from left -->
    <div
      class="flex items-center gap-4 transition-all duration-700 ease-out"
      :class="phase === 'enter' ? '-translate-x-[120%] opacity-0' : 'translate-x-0 opacity-100'"
      :style="phase === 'exit' ? 'opacity: 0; transform: scale(0.8); transition: all 0.5s ease-in' : ''"
    >
      <div class="flex items-center gap-3">
        <div class="w-14 h-14 rounded-full bg-gradient-to-br from-blue-500 to-cyan-500 flex items-center justify-center text-xl font-black text-white shadow-lg shadow-blue-500/30 border-2 border-blue-400/50">
          {{ myUsername.charAt(0).toUpperCase() }}
        </div>
        <div class="text-right">
          <div class="text-xs text-blue-400 uppercase tracking-wider font-semibold">{{ t('battle.intro.you', 'You') }}</div>
          <div class="text-lg font-black text-white">{{ myUsername }}</div>
        </div>
      </div>
    </div>

    <!-- VS Badge -->
    <div
      class="my-6 relative transition-all duration-500"
      :class="{
        'scale-0 opacity-0': phase === 'enter',
        'scale-100 opacity-100': phase === 'vs' || phase === 'fight',
        'scale-150 opacity-0': phase === 'exit',
      }"
    >
      <div class="w-20 h-20 rounded-full bg-gradient-to-br from-red-600 to-orange-600 flex items-center justify-center shadow-2xl shadow-red-500/40 border-2 border-red-400/50">
        <span class="text-2xl font-black text-white italic tracking-tighter">VS</span>
      </div>
      <!-- Pulse ring -->
      <div
        v-if="phase === 'vs' || phase === 'fight'"
        class="absolute inset-0 rounded-full border-2 border-red-400/50 animate-ping"
      />
    </div>

    <!-- Player 2 (Enemy) - slides from right -->
    <div
      class="flex items-center gap-4 transition-all duration-700 ease-out"
      :class="phase === 'enter' ? 'translate-x-[120%] opacity-0' : 'translate-x-0 opacity-100'"
      :style="phase === 'exit' ? 'opacity: 0; transform: scale(0.8); transition: all 0.5s ease-in' : ''"
    >
      <div class="flex items-center gap-3">
        <div class="text-left">
          <div class="text-xs text-red-400 uppercase tracking-wider font-semibold">{{ t('battle.intro.enemy', 'Opponent') }}</div>
          <div class="text-lg font-black text-white">{{ enemyUsername }}</div>
        </div>
        <div class="w-14 h-14 rounded-full bg-gradient-to-br from-red-500 to-orange-500 flex items-center justify-center text-xl font-black text-white shadow-lg shadow-red-500/30 border-2 border-red-400/50">
          {{ enemyUsername.charAt(0).toUpperCase() }}
        </div>
      </div>
    </div>

    <!-- FIGHT! text -->
    <div
      class="absolute bottom-16 transition-all duration-300"
      :class="{
        'scale-0 opacity-0': phase !== 'fight',
        'scale-100 opacity-100': phase === 'fight',
      }"
    >
      <div class="text-3xl font-black text-transparent bg-clip-text bg-gradient-to-r from-yellow-300 via-orange-400 to-red-500 uppercase tracking-widest intro-fight-pulse">
        {{ t('battle.intro.fight', 'FIGHT!') }}
      </div>
    </div>
  </div>
</template>

<style scoped>
.intro-bg-line {
  position: absolute;
  height: 1px;
  width: 200%;
  left: -50%;
  background: linear-gradient(90deg, transparent, rgba(239, 68, 68, 0.2), transparent);
  animation: intro-line-sweep 3s ease-in-out;
}

.intro-bg-line-1 { top: 30%; animation-delay: 0.3s; }
.intro-bg-line-2 { top: 50%; animation-delay: 0.8s; }
.intro-bg-line-3 { top: 70%; animation-delay: 1.3s; }

@keyframes intro-line-sweep {
  0% { transform: translateX(-50%); opacity: 0; }
  50% { opacity: 1; }
  100% { transform: translateX(50%); opacity: 0; }
}

.intro-fight-pulse {
  animation: fight-pulse 0.4s ease-in-out infinite alternate;
}

@keyframes fight-pulse {
  0% { transform: scale(1); }
  100% { transform: scale(1.1); }
}
</style>
