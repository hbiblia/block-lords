<script setup lang="ts">
import { computed, ref, watch } from 'vue';
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
  boosted?: boolean;
  poison?: number;
  deckCount?: number;
  discardCount?: number;
  handCount?: number;
}>();

const { t } = useI18n();
const maxHpVal = computed(() => props.maxHp || 200);
const maxEnergyVal = computed(() => Math.max(props.maxEnergy || 3, props.energy ?? 0));
const hpPercent = computed(() => Math.max(0, (props.hp / maxHpVal.value) * 100));
const shieldPercent = computed(() => Math.max(0, Math.min(100, (props.shield / 50) * 100)));

// Damage trail: ghost bar that shows previous HP/Shield and shrinks with delay
const trailPercent = ref(hpPercent.value);
let trailTimeout: number | null = null;
const shieldTrailPercent = ref(shieldPercent.value);
let shieldTrailTimeout: number | null = null;
const shieldGain = ref(false);

// Animation states
const shaking = ref(false);
const healGlow = ref(false);
const shieldFlash = ref(false);
const shieldBreak = ref(false);
const energyPop = ref(false);
const weakenedFlash = ref(false);
const boostedFlash = ref(false);

function triggerAnim(animRef: typeof shaking, duration: number) {
  animRef.value = true;
  setTimeout(() => { animRef.value = false; }, duration);
}

watch(() => props.hp, (newVal, oldVal) => {
  if (oldVal === undefined || oldVal === newVal) return;
  if (newVal < oldVal) {
    // Damage: freeze trail at old value, then shrink after delay
    if (trailTimeout) clearTimeout(trailTimeout);
    const oldPercent = Math.max(0, (oldVal / maxHpVal.value) * 100);
    trailPercent.value = oldPercent;
    trailTimeout = window.setTimeout(() => {
      trailPercent.value = hpPercent.value;
    }, 800);
    triggerAnim(shaking, 500);
  } else {
    // Heal: snap trail to new value immediately
    trailPercent.value = hpPercent.value;
    triggerAnim(healGlow, 600);
  }
});

watch(() => props.shield, (newVal, oldVal) => {
  if (oldVal === undefined || oldVal === newVal) return;
  if (newVal > oldVal) {
    // Shield gained: snap trail, then animate fill up with glow
    shieldTrailPercent.value = shieldPercent.value;
    triggerAnim(shieldFlash, 500);
    triggerAnim(shieldGain, 600);
  } else {
    // Shield lost: freeze trail at old value, then shrink after delay
    if (shieldTrailTimeout) clearTimeout(shieldTrailTimeout);
    const oldPercent = Math.max(0, Math.min(100, (oldVal / 50) * 100));
    shieldTrailPercent.value = oldPercent;
    shieldTrailTimeout = window.setTimeout(() => {
      shieldTrailPercent.value = shieldPercent.value;
    }, 800);
    if (newVal <= 0 && oldVal > 0) triggerAnim(shieldBreak, 400);
  }
});

watch(() => props.energy, (newVal, oldVal) => {
  if (oldVal === undefined || oldVal === newVal) return;
  triggerAnim(energyPop, 300);
});

watch(() => props.weakened, (newVal, oldVal) => {
  if (newVal && !oldVal) triggerAnim(weakenedFlash, 400);
});

watch(() => props.boosted, (newVal, oldVal) => {
  if (newVal && !oldVal) triggerAnim(boostedFlash, 400);
});
</script>

<template>
  <div
    class="px-3 py-2 relative overflow-hidden"
    :class="[
      isEnemy ? 'border-b border-red-500/20' : 'border-t border-green-500/20',
      shaking ? 'damage-shake' : '',
      healGlow ? 'heal-glow' : '',
    ]"
  >
    <!-- Damage flash overlay -->
    <div
      v-if="shaking"
      class="absolute inset-0 z-10 pointer-events-none bg-red-500/20 damage-flash"
    />
    <!-- Heal flash overlay -->
    <div
      v-if="healGlow"
      class="absolute inset-0 z-10 pointer-events-none bg-green-500/20 heal-flash"
    />
    <!-- Weakened flash overlay -->
    <div
      v-if="weakenedFlash"
      class="absolute inset-0 z-10 pointer-events-none bg-purple-500/25 status-flash"
    />
    <!-- Boosted flash overlay -->
    <div
      v-if="boostedFlash"
      class="absolute inset-0 z-10 pointer-events-none bg-yellow-500/25 status-flash"
    />

    <!-- Poison bubbles overlay -->
    <div v-if="poison && poison > 0" class="absolute inset-0 z-[5] pointer-events-none overflow-hidden">
      <div class="poison-bubble" style="left: 8%; animation-delay: 0s; animation-duration: 2.2s;" />
      <div class="poison-bubble poison-bubble-sm" style="left: 22%; animation-delay: 0.4s; animation-duration: 1.8s;" />
      <div class="poison-bubble" style="left: 38%; animation-delay: 0.9s; animation-duration: 2.5s;" />
      <div class="poison-bubble poison-bubble-sm" style="left: 55%; animation-delay: 0.2s; animation-duration: 2s;" />
      <div class="poison-bubble" style="left: 70%; animation-delay: 1.2s; animation-duration: 2.3s;" />
      <div class="poison-bubble poison-bubble-sm" style="left: 85%; animation-delay: 0.6s; animation-duration: 1.9s;" />
    </div>

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
            <div v-if="boosted" class="flex items-center gap-1 mt-0.5">
              <span class="w-1 h-1 rounded-full bg-yellow-400 animate-pulse" />
              <span class="text-[8px] text-yellow-300 font-medium">
                {{ t('battle.boostedStatus', 'Boosted: next attack +10 dmg') }}
              </span>
            </div>
            <div v-if="poison && poison > 0" class="flex items-center gap-1 mt-0.5">
              <span class="w-1 h-1 rounded-full bg-green-400 animate-pulse" />
              <span class="text-[8px] text-green-300 font-medium">
                &#9760; {{ t('battle.poisonedStatus', { turns: poison }, `Poison: ${poison} turns`) }}
              </span>
            </div>
          </div>
        </div>

        <!-- Energy orbs (only for self) -->
        <div v-if="energy !== undefined" class="flex items-center gap-2">
          <div class="flex gap-1">
            <div
              v-for="i in maxEnergyVal"
              :key="i"
              class="w-6 h-6 rounded-lg text-sm flex items-center justify-center font-bold transition-all duration-300"
              :class="[
                i <= (energy ?? 0)
                  ? 'bg-slate-900 border border-yellow-500/60 text-yellow-400 shadow-sm shadow-yellow-500/15 scale-100'
                  : 'bg-slate-800 text-slate-600 border border-slate-700/50 scale-90 opacity-40',
                energyPop ? 'energy-bounce' : '',
              ]"
            >&#9889;</div>
          </div>
          <span
            class="text-xs font-black font-mono px-1.5 py-0.5 rounded-md"
            :class="(energy ?? 0) > 0
              ? 'bg-yellow-500/15 text-yellow-300'
              : 'bg-slate-800 text-slate-500'"
          >{{ energy }}</span>
        </div>
      </div>

      <!-- Card counts row -->
      <div v-if="deckCount !== undefined" class="flex items-center gap-3 mb-1.5 text-[9px] font-bold">
        <span class="flex items-center gap-0.5 text-amber-400/80" :title="t('battle.deckCount', 'Deck')">
          &#127183; {{ deckCount }}
        </span>
        <span class="flex items-center gap-0.5 text-cyan-400/80" :title="t('battle.handCount', 'Hand')">
          &#9995; {{ handCount ?? 0 }}
        </span>
        <span class="flex items-center gap-0.5 text-slate-400/80" :title="t('battle.discardCount', 'Discard')">
          &#128465; {{ discardCount ?? 0 }}
        </span>
      </div>

      <!-- Row 2: HP bar -->
      <div class="flex items-center gap-2 mb-1.5">
        <div class="flex items-center gap-1 w-8 justify-end">
          <span class="text-[10px]">&#10084;</span>
          <span
            class="text-[10px] font-black uppercase tracking-wide"
            :class="hpPercent > 30 ? 'text-red-400' : 'text-red-500 animate-pulse'"
          >HP</span>
        </div>
        <div
          class="flex-1 h-5 rounded-lg overflow-hidden relative"
          :class="{
            'bg-slate-900/80 border border-green-500/20': hpPercent > 60,
            'bg-slate-900/80 border border-yellow-500/20': hpPercent > 30 && hpPercent <= 60,
            'bg-slate-900/80 border border-red-500/30': hpPercent <= 30,
          }"
        >
          <!-- Damage trail (ghost bar behind HP) -->
          <div
            v-if="trailPercent > hpPercent"
            class="absolute inset-y-0 left-0 rounded-lg bg-red-400/50 transition-all duration-700 ease-in"
            :style="{ width: trailPercent + '%' }"
          />
          <!-- HP fill -->
          <div
            class="h-full rounded-lg transition-all duration-700 ease-out relative overflow-hidden"
            :class="{
              'bg-gradient-to-r from-green-600 via-emerald-500 to-green-400': hpPercent > 60,
              'bg-gradient-to-r from-yellow-600 via-amber-500 to-yellow-400': hpPercent > 30 && hpPercent <= 60,
              'bg-gradient-to-r from-red-700 via-red-500 to-red-400': hpPercent <= 30,
            }"
            :style="{ width: hpPercent + '%' }"
          >
            <!-- Shimmer effect -->
            <div class="absolute inset-0 bg-gradient-to-r from-transparent via-white/15 to-transparent animate-[shimmer_3s_infinite]" />
            <!-- Inner highlight -->
            <div class="absolute inset-x-0 top-0 h-[40%] bg-gradient-to-b from-white/20 to-transparent rounded-t-lg" />
          </div>
          <!-- HP text overlay -->
          <div class="absolute inset-0 flex items-center justify-center">
            <span class="text-[11px] font-black text-white drop-shadow-[0_1px_3px_rgba(0,0,0,0.9)] tracking-wide">
              {{ hp }} / {{ maxHpVal }}
            </span>
          </div>
        </div>
      </div>

      <!-- Row 3: Shield bar -->
      <div v-if="shield > 0 || !isEnemy" class="flex items-center gap-2">
        <div class="flex items-center gap-1 w-8 justify-end">
          <span class="text-[10px]">&#128737;</span>
          <span class="text-[10px] text-blue-400 font-black uppercase tracking-wide">{{ t('battle.shieldLabel', 'SH') }}</span>
        </div>
        <div
          class="flex-1 h-4 rounded-lg overflow-hidden relative bg-slate-900/80 border transition-colors duration-300"
          :class="{
            'shield-break-anim': shieldBreak,
            'border-cyan-400/40': shieldGain,
            'border-blue-500/20': !shieldGain,
          }"
        >
          <!-- Shield damage trail -->
          <div
            v-if="shieldTrailPercent > shieldPercent"
            class="absolute inset-y-0 left-0 rounded-lg bg-blue-300/40 transition-all duration-700 ease-in"
            :style="{ width: shieldTrailPercent + '%' }"
          />
          <div
            class="h-full rounded-lg bg-gradient-to-r from-blue-600 via-blue-500 to-cyan-400 transition-all duration-500 relative overflow-hidden"
            :class="{
              'shield-flash-anim': shieldFlash,
              'shield-gain-anim': shieldGain,
            }"
            :style="{ width: shieldPercent + '%' }"
          >
            <div class="absolute inset-0 bg-gradient-to-r from-transparent via-white/15 to-transparent animate-[shimmer_3s_infinite]" />
            <div class="absolute inset-x-0 top-0 h-[40%] bg-gradient-to-b from-white/20 to-transparent rounded-t-lg" />
          </div>
          <!-- Shield text overlay -->
          <div class="absolute inset-0 flex items-center justify-center">
            <span class="text-[10px] font-black text-white drop-shadow-[0_1px_3px_rgba(0,0,0,0.9)] tracking-wide">
              {{ shield }}
            </span>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
@keyframes shimmer {
  0% { transform: translateX(-100%); }
  100% { transform: translateX(100%); }
}

/* Damage shake */
@keyframes damage-shake {
  0%, 100% { transform: translateX(0); }
  10%, 50%, 90% { transform: translateX(-4px); }
  30%, 70% { transform: translateX(4px); }
}
.damage-shake {
  animation: damage-shake 500ms ease-out;
}

/* Damage red flash overlay */
@keyframes damage-flash {
  0% { opacity: 0.6; }
  100% { opacity: 0; }
}
.damage-flash {
  animation: damage-flash 500ms ease-out forwards;
}

/* Heal green glow */
@keyframes heal-glow-anim {
  0% { box-shadow: inset 0 0 0 rgba(34, 197, 94, 0); }
  30% { box-shadow: inset 0 0 20px rgba(34, 197, 94, 0.3); }
  100% { box-shadow: inset 0 0 0 rgba(34, 197, 94, 0); }
}
.heal-glow {
  animation: heal-glow-anim 600ms ease-out;
}

/* Heal flash overlay */
@keyframes heal-flash {
  0% { opacity: 0.5; }
  100% { opacity: 0; }
}
.heal-flash {
  animation: heal-flash 600ms ease-out forwards;
}

/* Shield flash pulse */
@keyframes shield-flash {
  0%, 100% { filter: brightness(1); }
  50% { filter: brightness(1.8); }
}
.shield-flash-anim {
  animation: shield-flash 500ms ease-out;
}

/* Shield gain glow */
@keyframes shield-gain {
  0% { box-shadow: 0 0 0 0 rgba(34, 211, 238, 0); filter: brightness(1); }
  30% { box-shadow: 0 0 12px 2px rgba(34, 211, 238, 0.5); filter: brightness(1.4); }
  100% { box-shadow: 0 0 0 0 rgba(34, 211, 238, 0); filter: brightness(1); }
}
.shield-gain-anim {
  animation: shield-gain 600ms ease-out;
}

/* Shield break burst */
@keyframes shield-break {
  0% { transform: scale(1); border-color: rgba(59, 130, 246, 0.5); }
  40% { transform: scale(1.05); border-color: rgba(59, 130, 246, 0.8); }
  100% { transform: scale(1); border-color: rgba(59, 130, 246, 0.2); }
}
.shield-break-anim {
  animation: shield-break 400ms ease-out;
}

/* Energy orb bounce */
@keyframes energy-bounce {
  0%, 100% { transform: scale(1); }
  50% { transform: scale(1.3); }
}
.energy-bounce {
  animation: energy-bounce 300ms ease-out;
}

/* Status effect flash (weakened/boosted) */
@keyframes status-flash-anim {
  0% { opacity: 0.7; }
  100% { opacity: 0; }
}
.status-flash {
  animation: status-flash-anim 400ms ease-out forwards;
}

/* Poison bubbles */
.poison-bubble {
  position: absolute;
  bottom: -4px;
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: radial-gradient(circle at 30% 30%, rgba(74, 222, 128, 0.7), rgba(22, 163, 74, 0.4));
  box-shadow: 0 0 4px rgba(74, 222, 128, 0.4);
  animation: poison-rise 2.2s ease-in infinite;
}
.poison-bubble-sm {
  width: 4px;
  height: 4px;
  opacity: 0.7;
}
@keyframes poison-rise {
  0% {
    transform: translateY(0) translateX(0) scale(1);
    opacity: 0;
  }
  10% {
    opacity: 0.8;
  }
  50% {
    transform: translateY(-30px) translateX(4px) scale(0.9);
    opacity: 0.6;
  }
  100% {
    transform: translateY(-60px) translateX(-3px) scale(0.4);
    opacity: 0;
  }
}
</style>
