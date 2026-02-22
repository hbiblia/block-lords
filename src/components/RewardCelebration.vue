<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { playSound } from '@/utils/sounds';

const { t } = useI18n();

interface MaterialDrop {
  id?: string;
  name: string;
  icon: string;
}

interface RewardEvent {
  reward: number;
  is_premium: boolean;
  materials_dropped: MaterialDrop[];
}

interface FloatingParticle {
  id: number;
  left: number;
  delay: number;
  duration: number;
}

const showCelebration = ref(false);
const rewardAmount = ref(0);
const displayedAmount = ref(0);
const isPremium = ref(false);
const materialsDropped = ref<MaterialDrop[]>([]);
const floatingParticles = ref<FloatingParticle[]>([]);

const rewardQueue: RewardEvent[] = [];
let isShowing = false;
let dismissTimer: ReturnType<typeof setTimeout> | null = null;
let countUpFrame: number | null = null;
let lastRewardTime = 0;
let lastRewardAmount = 0;

function generateParticles(): FloatingParticle[] {
  return Array.from({ length: 12 }, (_, i) => ({
    id: i,
    left: Math.random() * 100,
    delay: i * 0.15,
    duration: 1.5 + Math.random(),
  }));
}

function startCountUp(target: number, duration = 1500) {
  displayedAmount.value = 0;
  const startTime = performance.now();

  function tick(now: number) {
    const elapsed = now - startTime;
    const progress = Math.min(elapsed / duration, 1);
    const eased = 1 - Math.pow(1 - progress, 3);
    displayedAmount.value = target * eased;
    if (progress < 1) {
      countUpFrame = requestAnimationFrame(tick);
    }
  }

  countUpFrame = requestAnimationFrame(tick);
}

function showNextReward() {
  if (rewardQueue.length === 0) {
    isShowing = false;
    return;
  }

  isShowing = true;
  const reward = rewardQueue.shift()!;

  rewardAmount.value = reward.reward;
  isPremium.value = reward.is_premium;
  materialsDropped.value = reward.materials_dropped || [];
  floatingParticles.value = generateParticles();
  showCelebration.value = true;

  playSound('achievement');
  startCountUp(reward.reward);

  // Más tiempo si hay materiales para que el jugador los vea
  const displayTime = materialsDropped.value.length > 0 ? 5000 : 4000;

  dismissTimer = setTimeout(() => {
    showCelebration.value = false;
    floatingParticles.value = [];
    materialsDropped.value = [];
    if (countUpFrame) cancelAnimationFrame(countUpFrame);
    setTimeout(showNextReward, 500);
  }, displayTime);
}

function handlePendingBlockCreated(event: Event) {
  const { reward, is_premium, materials_dropped } = (event as CustomEvent).detail;
  if (!reward) return;

  // Dedup: ignore duplicate events for same reward within 5 seconds
  const now = Date.now();
  const amount = Number(reward);
  if (amount === lastRewardAmount && now - lastRewardTime < 5000) return;
  lastRewardTime = now;
  lastRewardAmount = amount;

  rewardQueue.push({
    reward: amount,
    is_premium: !!is_premium,
    materials_dropped: Array.isArray(materials_dropped) ? materials_dropped : [],
  });

  if (!isShowing) {
    showNextReward();
  }
}

onMounted(() => {
  window.addEventListener('pending-block-created', handlePendingBlockCreated);
});

onUnmounted(() => {
  window.removeEventListener('pending-block-created', handlePendingBlockCreated);
  if (dismissTimer) clearTimeout(dismissTimer);
  if (countUpFrame) cancelAnimationFrame(countUpFrame);
});
</script>

<template>
  <Teleport to="body">
    <!-- Reward Celebration -->
    <Transition name="reward-celebration">
      <div
        v-if="showCelebration"
        class="fixed inset-x-0 top-0 z-[90] pointer-events-none flex justify-center pt-20"
      >
        <div class="pointer-events-auto relative rounded-xl overflow-hidden min-w-[280px]">
          <!-- Pulsing gradient background -->
          <div
            class="absolute inset-0 celebration-bg rounded-xl"
            :class="isPremium ? 'bg-amber-500/10' : 'bg-emerald-500/10'"
          ></div>

          <!-- Floating particles (upward, like solo mining) -->
          <div class="absolute inset-0 pointer-events-none overflow-hidden rounded-xl">
            <div
              v-for="particle in floatingParticles"
              :key="'fp-' + particle.id"
              class="celebration-particle absolute w-1.5 h-1.5 rounded-full"
              :class="isPremium ? 'bg-amber-400' : 'bg-emerald-400'"
              :style="{
                left: particle.left + '%',
                bottom: '-5%',
                animationDelay: particle.delay + 's',
                animationDuration: particle.duration + 's',
              }"
            ></div>
          </div>

          <!-- Card content -->
          <div
            class="relative z-10 bg-bg-primary/95 backdrop-blur-xl border rounded-xl p-6 text-center"
            :class="isPremium ? 'border-amber-500/50' : 'border-status-success/40'"
          >
            <!-- Emoji with bounce-in -->
            <div class="celebration-emoji text-4xl sm:text-5xl mb-2">
              {{ isPremium ? '👑' : '⛏️' }}
            </div>

            <!-- Title with slide-up -->
            <div
              class="celebration-title text-sm font-medium mb-1"
              :class="isPremium ? 'text-amber-400' : 'text-status-success'"
            >
              {{ t('reward.blockReward') }}
            </div>

            <!-- Reward Amount with slide-up -->
            <div
              class="celebration-reward text-3xl font-bold font-mono mb-1"
              :class="isPremium ? 'text-amber-400' : 'text-white'"
            >
              +{{ displayedAmount.toFixed(4) }} ₿
            </div>

            <!-- Premium Badge with slide-up -->
            <div
              v-if="isPremium"
              class="celebration-sub inline-flex items-center gap-1 px-2 py-0.5 rounded-full bg-amber-500/20 border border-amber-500/30 text-xs text-amber-400 mt-1"
            >
              👑 Premium +50%
            </div>

            <!-- Material Drops -->
            <div v-if="materialsDropped.length > 0" class="mt-3 pt-3 border-t border-white/10">
              <div class="text-xs text-text-muted mb-2">{{ t('reward.materialDrops') }}</div>
              <div class="flex items-center justify-center gap-2 flex-wrap">
                <div
                  v-for="(mat, idx) in materialsDropped"
                  :key="idx"
                  class="material-drop-item inline-flex items-center gap-1 px-2 py-1 rounded-lg bg-purple-500/15 border border-purple-500/30"
                  :style="{ animationDelay: `${0.3 + idx * 0.15}s` }"
                >
                  <span class="text-base">{{ mat.icon }}</span>
                  <span class="text-xs font-medium text-purple-300">{{ mat.name }}</span>
                </div>
              </div>
            </div>

            <!-- Auto-dismiss Progress Bar -->
            <div class="mt-3 h-1 bg-bg-tertiary rounded-full overflow-hidden">
              <div
                class="h-full rounded-full reward-progress"
                :class="isPremium ? 'bg-amber-500' : 'bg-status-success'"
                :style="{ animationDuration: materialsDropped.length > 0 ? '5s' : '4s' }"
              ></div>
            </div>
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
/* === Transition (same as seeds-complete in solo mining) === */
.reward-celebration-enter-active {
  transition: all 0.5s cubic-bezier(0.34, 1.56, 0.64, 1);
}

.reward-celebration-leave-active {
  transition: all 0.4s ease-in;
}

.reward-celebration-enter-from {
  opacity: 0;
  transform: scale(0.8) translateY(10px);
}

.reward-celebration-leave-to {
  opacity: 0;
  transform: scale(0.95) translateY(-5px);
}

/* === Pulsing background (same as completeBgPulse) === */
.celebration-bg {
  animation: celebrationBgPulse 1.5s ease-in-out infinite;
}

@keyframes celebrationBgPulse {
  0%, 100% {
    opacity: 0.6;
  }
  50% {
    opacity: 1;
  }
}

/* === Emoji bounce-in (same as completeEmojiBounce) === */
.celebration-emoji {
  animation: celebrationEmojiBounce 0.8s cubic-bezier(0.34, 1.56, 0.64, 1) both;
}

@keyframes celebrationEmojiBounce {
  0% {
    transform: scale(0) rotate(-15deg);
    opacity: 0;
  }
  60% {
    transform: scale(1.3) rotate(5deg);
  }
  100% {
    transform: scale(1) rotate(0deg);
    opacity: 1;
  }
}

/* === Text cascading slide-up (same as completeSlideUp) === */
.celebration-title {
  animation: celebrationSlideUp 0.5s ease-out 0.2s both;
}

.celebration-reward {
  animation: celebrationSlideUp 0.5s ease-out 0.35s both;
}

.celebration-sub {
  animation: celebrationSlideUp 0.5s ease-out 0.5s both;
}

@keyframes celebrationSlideUp {
  0% {
    transform: translateY(15px);
    opacity: 0;
  }
  100% {
    transform: translateY(0);
    opacity: 1;
  }
}

/* === Floating particles upward (same as particleFloat) === */
.celebration-particle {
  animation: celebrationParticleFloat 2s ease-out infinite;
}

@keyframes celebrationParticleFloat {
  0% {
    transform: translateY(0) scale(1);
    opacity: 0;
  }
  10% {
    opacity: 0.8;
  }
  100% {
    transform: translateY(-120px) scale(0);
    opacity: 0;
  }
}

/* === Progress bar === */
.reward-progress {
  width: 100%;
  animation: progress-shrink linear forwards;
}

@keyframes progress-shrink {
  from {
    width: 100%;
  }
  to {
    width: 0%;
  }
}

/* === Material drop pop-in === */
.material-drop-item {
  opacity: 0;
  animation: material-pop-in 0.4s cubic-bezier(0.21, 1.02, 0.73, 1) forwards;
}

@keyframes material-pop-in {
  0% {
    opacity: 0;
    transform: scale(0.5) translateY(8px);
  }
  100% {
    opacity: 1;
    transform: scale(1) translateY(0);
  }
}
</style>
