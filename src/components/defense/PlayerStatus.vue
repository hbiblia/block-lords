<script setup lang="ts">
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps<{
  username: string;
  hp: number;
  maxHp?: number;
  shield: number;
  energy?: number;
  maxEnergy?: number;
  isCurrentTurn?: boolean;
  isEnemy?: boolean;
  weakened?: boolean;
}>();

const { t } = useI18n();
const maxHpVal = computed(() => props.maxHp || 100);
const maxEnergyVal = computed(() => props.maxEnergy || 3);
const hpPercent = computed(() => Math.max(0, (props.hp / maxHpVal.value) * 100));
</script>

<template>
  <div
    class="px-3 py-2 relative overflow-hidden"
    :class="[
      isEnemy ? 'border-b border-red-500/20' : 'border-t border-green-500/20',
    ]"
  >
    <!-- Subtle background glow -->
    <div
      class="absolute inset-0 opacity-[0.07]"
      :class="isEnemy
        ? 'bg-gradient-to-r from-red-500 via-transparent to-transparent'
        : 'bg-gradient-to-l from-green-500 via-transparent to-transparent'"
    />

    <!-- Turn highlight border -->
    <div
      v-if="isCurrentTurn"
      class="absolute inset-0 border-l-2 animate-pulse"
      :class="isEnemy ? 'border-red-400/60' : 'border-green-400/60'"
    />

    <div class="relative z-[1]">
      <!-- Row 1: Avatar + Name + Energy -->
      <div class="flex items-center justify-between mb-1.5">
        <div class="flex items-center gap-2">
          <!-- Avatar -->
          <div
            class="w-7 h-7 rounded-lg flex items-center justify-center text-[11px] font-black text-white shadow-md"
            :class="isEnemy
              ? 'bg-gradient-to-br from-red-500 to-rose-600 shadow-red-500/30'
              : 'bg-gradient-to-br from-emerald-500 to-green-600 shadow-green-500/30'"
          >
            {{ username.charAt(0).toUpperCase() }}
          </div>
          <div class="flex flex-col">
            <div class="flex items-center gap-1.5">
              <span v-if="isCurrentTurn" class="relative flex h-2 w-2">
                <span class="animate-ping absolute inline-flex h-full w-full rounded-full opacity-75"
                  :class="isEnemy ? 'bg-red-400' : 'bg-green-400'" />
                <span class="relative inline-flex rounded-full h-2 w-2"
                  :class="isEnemy ? 'bg-red-400' : 'bg-green-400'" />
              </span>
              <span class="text-xs font-bold" :class="isEnemy ? 'text-red-200' : 'text-emerald-200'">
                {{ username }}
              </span>
              <span v-if="isCurrentTurn" class="text-[9px] font-medium"
                :class="isEnemy ? 'text-red-400/80' : 'text-green-400/80'">
                {{ isEnemy ? t('battle.theirTurn', '(playing)') : t('battle.yourTurnShort', '(your turn)') }}
              </span>
            </div>
            <!-- Debuffs -->
            <div v-if="weakened" class="flex items-center gap-1 mt-0.5">
              <span class="w-1 h-1 rounded-full bg-purple-400 animate-pulse" />
              <span class="text-[8px] text-purple-300 font-medium">
                {{ t('battle.weakenedStatus', 'Weakened: next attack -8 dmg') }}
              </span>
            </div>
          </div>
        </div>

        <!-- Energy orbs (only for self) -->
        <div v-if="energy !== undefined" class="flex items-center gap-1.5">
          <div class="flex gap-0.5">
            <div
              v-for="i in maxEnergyVal"
              :key="i"
              class="w-4 h-4 rounded-md text-[9px] flex items-center justify-center font-bold transition-all duration-300"
              :class="i <= (energy ?? 0)
                ? 'bg-gradient-to-b from-yellow-400 to-amber-500 text-black shadow-sm shadow-yellow-400/40 scale-100'
                : 'bg-slate-800 text-slate-600 border border-slate-700/50 scale-90'"
            >&#9889;</div>
          </div>
        </div>
      </div>

      <!-- Row 2: HP bar -->
      <div class="flex items-center gap-2 mb-1">
        <div class="flex items-center gap-1 w-8 justify-end">
          <span class="text-[9px] font-black" :class="hpPercent > 30 ? 'text-red-400' : 'text-red-500 animate-pulse'">HP</span>
        </div>
        <div class="flex-1 h-4 bg-slate-900 rounded-full overflow-hidden border border-slate-700/60 shadow-inner relative">
          <!-- HP fill -->
          <div
            class="h-full rounded-full transition-all duration-700 ease-out relative overflow-hidden"
            :class="{
              'bg-gradient-to-r from-green-500 to-emerald-400': hpPercent > 60,
              'bg-gradient-to-r from-yellow-500 to-amber-400': hpPercent > 30 && hpPercent <= 60,
              'bg-gradient-to-r from-red-600 to-red-400': hpPercent <= 30,
            }"
            :style="{ width: hpPercent + '%' }"
          >
            <!-- Shimmer effect -->
            <div class="absolute inset-0 bg-gradient-to-r from-transparent via-white/20 to-transparent animate-[shimmer_2s_infinite]" />
          </div>
          <!-- HP text overlay -->
          <div class="absolute inset-0 flex items-center justify-center">
            <span class="text-[10px] font-bold text-white drop-shadow-[0_1px_2px_rgba(0,0,0,0.8)]">
              {{ hp }}/{{ maxHpVal }}
            </span>
          </div>
        </div>
      </div>

      <!-- Row 3: Shield bar -->
      <div v-if="shield > 0 || !isEnemy" class="flex items-center gap-2">
        <div class="flex items-center gap-1 w-8 justify-end">
          <span class="text-[9px] text-blue-400 font-bold">{{ t('battle.shieldLabel', 'SH') }}</span>
        </div>
        <div class="flex-1 h-2.5 bg-slate-900 rounded-full overflow-hidden border border-slate-700/60 shadow-inner relative">
          <div
            class="h-full rounded-full bg-gradient-to-r from-blue-500 to-cyan-400 transition-all duration-500 relative overflow-hidden"
            :style="{ width: Math.min(shield, 50) * 2 + '%' }"
          >
            <div class="absolute inset-0 bg-gradient-to-r from-transparent via-white/15 to-transparent animate-[shimmer_2s_infinite]" />
          </div>
        </div>
        <span class="text-[10px] text-blue-300 w-6 text-right font-mono font-bold">{{ shield }}</span>
      </div>
    </div>
  </div>
</template>

<style scoped>
@keyframes shimmer {
  0% { transform: translateX(-100%); }
  100% { transform: translateX(100%); }
}
</style>
