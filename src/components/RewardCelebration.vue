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
  is_pity: boolean;
  materials_dropped: MaterialDrop[];
}

interface CoinParticle {
  id: number;
  left: number;
  delay: number;
  size: number;
  emoji: string;
}

const showCelebration = ref(false);
const rewardAmount = ref(0);
const displayedAmount = ref(0);
const isPremium = ref(false);
const isPity = ref(false);
const materialsDropped = ref<MaterialDrop[]>([]);
const coinParticles = ref<CoinParticle[]>([]);

const rewardQueue: RewardEvent[] = [];
let isShowing = false;
let dismissTimer: ReturnType<typeof setTimeout> | null = null;
let countUpFrame: number | null = null;
let lastRewardTime = 0;
let lastRewardAmount = 0;

function generateParticles(hasMaterials: boolean): CoinParticle[] {
  const baseEmojis = ['🪙', '💰', '✨', '⭐', '💎'];
  const materialEmojis = hasMaterials ? ['🔩', '💾', '🧬', '💠'] : [];
  const emojis = [...baseEmojis, ...materialEmojis];
  return Array.from({ length: 25 }, (_, i) => ({
    id: i,
    left: Math.random() * 100,
    delay: Math.random() * 0.8,
    size: Math.random() * 10 + 14,
    emoji: emojis[Math.floor(Math.random() * emojis.length)],
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
  isPity.value = reward.is_pity;
  materialsDropped.value = reward.materials_dropped || [];
  coinParticles.value = generateParticles(materialsDropped.value.length > 0);
  showCelebration.value = true;

  playSound('reward');
  startCountUp(reward.reward);

  // Más tiempo si hay materiales para que el jugador los vea
  const displayTime = materialsDropped.value.length > 0 ? 5000 : 4000;

  dismissTimer = setTimeout(() => {
    showCelebration.value = false;
    coinParticles.value = [];
    materialsDropped.value = [];
    if (countUpFrame) cancelAnimationFrame(countUpFrame);
    setTimeout(showNextReward, 500);
  }, displayTime);
}

function handlePendingBlockCreated(event: Event) {
  const { reward, is_premium, is_pity, materials_dropped } = (event as CustomEvent).detail;
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
    is_pity: !!is_pity,
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
    <!-- Coin Particles -->
    <div v-if="showCelebration" class="fixed inset-0 z-[89] pointer-events-none overflow-hidden">
      <div
        v-for="particle in coinParticles"
        :key="particle.id"
        class="coin-particle"
        :style="{
          left: `${particle.left}%`,
          animationDelay: `${particle.delay}s`,
          fontSize: `${particle.size}px`,
        }"
      >
        {{ particle.emoji }}
      </div>
    </div>

    <!-- Reward Card -->
    <Transition name="reward-celebration">
      <div
        v-if="showCelebration"
        class="fixed inset-x-0 top-0 z-[90] pointer-events-none flex justify-center pt-20"
      >
        <div class="pointer-events-auto relative">
          <!-- Glow -->
          <div
            class="absolute -inset-2 rounded-2xl blur-xl opacity-50"
            :class="isPremium ? 'bg-amber-500/30' : 'bg-emerald-500/20'"
          ></div>

          <!-- Card -->
          <div
            class="relative bg-bg-primary/95 backdrop-blur-xl border rounded-2xl p-6 text-center min-w-[260px]"
            :class="isPremium ? 'border-amber-500/50' : 'border-status-success/40'"
          >
            <!-- Icon -->
            <div class="text-4xl mb-2 animate-bounce">
              {{ isPity ? '🎁' : isPremium ? '👑' : '⛏️' }}
            </div>

            <!-- Title -->
            <div
              class="text-sm font-medium mb-1"
              :class="isPremium ? 'text-amber-400' : 'text-status-success'"
            >
              {{ isPity ? t('reward.pityTitle') : t('reward.blockReward') }}
            </div>

            <!-- Reward Amount -->
            <div
              class="text-3xl font-bold font-mono mb-1"
              :class="isPremium ? 'text-amber-400' : 'text-white'"
            >
              +{{ displayedAmount.toFixed(4) }} ₿
            </div>

            <!-- Premium Badge -->
            <div
              v-if="isPremium"
              class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full bg-amber-500/20 border border-amber-500/30 text-xs text-amber-400 mt-1"
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
.coin-particle {
  position: absolute;
  top: -20px;
  animation: coin-fall 2.5s ease-out forwards;
  pointer-events: none;
}

@keyframes coin-fall {
  0% {
    transform: translateY(0) rotate(0deg) scale(1);
    opacity: 1;
  }
  60% {
    opacity: 1;
  }
  100% {
    transform: translateY(60vh) rotate(720deg) scale(0.3);
    opacity: 0;
  }
}

.coin-particle:nth-child(odd) {
  animation-name: coin-fall-wobble;
}

@keyframes coin-fall-wobble {
  0% {
    transform: translateY(0) translateX(0) rotate(0deg);
    opacity: 1;
  }
  25% {
    transform: translateY(15vh) translateX(15px) rotate(180deg);
    opacity: 1;
  }
  50% {
    transform: translateY(30vh) translateX(-10px) rotate(360deg);
    opacity: 0.9;
  }
  100% {
    transform: translateY(60vh) translateX(5px) rotate(720deg);
    opacity: 0;
  }
}

.reward-celebration-enter-active {
  animation: reward-card-in 0.5s cubic-bezier(0.21, 1.02, 0.73, 1);
}

.reward-celebration-leave-active {
  animation: reward-card-out 0.4s ease-in forwards;
}

@keyframes reward-card-in {
  0% {
    opacity: 0;
    transform: translateY(-40px) scale(0.8);
  }
  50% {
    transform: translateY(10px) scale(1.02);
  }
  100% {
    opacity: 1;
    transform: translateY(0) scale(1);
  }
}

@keyframes reward-card-out {
  0% {
    opacity: 1;
    transform: translateY(0) scale(1);
  }
  100% {
    opacity: 0;
    transform: translateY(-20px) scale(0.9);
  }
}

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

/* Material drop items appear with a pop-in animation */
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
