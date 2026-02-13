<script setup lang="ts">
import { watch, ref, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useGiftsStore } from '@/stores/gifts';
import { useToastStore } from '@/stores/toast';
import { playSound } from '@/utils/sounds';

const { t } = useI18n();
const giftsStore = useGiftsStore();
const toastStore = useToastStore();

// Confetti state
const showConfetti = ref(false);
const confettiPieces = ref<{ id: number; left: number; color: string; delay: number; size: number }[]>([]);

function triggerConfetti() {
  const colors = ['#f59e0b', '#10b981', '#3b82f6', '#ec4899', '#8b5cf6', '#ef4444', '#fbbf24', '#34d399'];
  confettiPieces.value = Array.from({ length: 60 }, (_, i) => ({
    id: i,
    left: Math.random() * 100,
    color: colors[Math.floor(Math.random() * colors.length)],
    delay: Math.random() * 0.5,
    size: Math.random() * 8 + 6,
  }));
  showConfetti.value = true;

  setTimeout(() => {
    showConfetti.value = false;
    confettiPieces.value = [];
  }, 3000);
}

// Particles for showing phase
const particles = ref<{ id: number; x: number; y: number; delay: number; size: number }[]>([]);

function generateParticles() {
  particles.value = Array.from({ length: 12 }, (_, i) => ({
    id: i,
    x: Math.random() * 200 - 100,
    y: Math.random() * 200 - 100,
    delay: Math.random() * 2,
    size: Math.random() * 6 + 3,
  }));
}

// Lock body scroll when modal is showing
watch(() => giftsStore.phase, (phase) => {
  if (phase !== 'idle') {
    document.body.style.overflow = 'hidden';
    if (phase === 'showing') {
      generateParticles();
    }
    if (phase === 'revealed') {
      initAd();
    }
  } else {
    document.body.style.overflow = '';
  }
});

onUnmounted(() => {
  document.body.style.overflow = '';
});

// Handle gift click -> start opening
function handleGiftClick() {
  if (giftsStore.phase !== 'showing') return;
  giftsStore.startOpening();
  playSound('click');

  // After shake animation, claim the gift
  setTimeout(async () => {
    const result = await giftsStore.claimCurrentGift();
    if (result) {
      playSound('reward');
      triggerConfetti();
    }
  }, 800);
}

// Handle collect -> show toast + move to next or close
function handleCollect() {
  playSound('click');

  // Build reward summary for the toast
  const lines = getRewardLines();
  if (lines.length > 0) {
    const summary = lines.map(l => `${l.emoji} ${l.text}`).join('  ');
    toastStore.giftReceived(summary);
  }

  giftsStore.collectAndNext();
}

// Format reward display
function getRewardLines() {
  const result = giftsStore.claimResult;
  if (!result) return [];

  const lines: { emoji: string; text: string }[] = [];

  if (result.gamecoin > 0) {
    lines.push({ emoji: '🪙', text: t('gifts.gamecoin', { amount: result.gamecoin }) });
  }
  if (result.crypto > 0) {
    lines.push({ emoji: '₿', text: t('gifts.crypto', { amount: result.crypto }) });
  }
  if (result.energy > 0) {
    lines.push({ emoji: '⚡', text: t('gifts.energy', { amount: result.energy }) });
  }
  if (result.internet > 0) {
    lines.push({ emoji: '📡', text: t('gifts.internet', { amount: result.internet }) });
  }
  if (result.itemType && result.itemQuantity > 0) {
    const itemName = getItemName(result.itemType, result.itemId);
    lines.push({ emoji: getItemEmoji(result.itemType), text: t('gifts.item', { name: itemName, quantity: result.itemQuantity }) });
  }

  return lines;
}

function getItemEmoji(type: string | null): string {
  switch (type) {
    case 'cooling': return '❄️';
    case 'boost': return '🚀';
    case 'rig': return '🖥️';
    case 'prepaid_card': return '💳';
    default: return '📦';
  }
}

function getItemName(type: string | null, id: string | null): string {
  if (!type) return t('gifts.itemGeneric', 'Item');
  const names: Record<string, string> = {
    cooling: t('gifts.itemCooling', 'Cooling'),
    boost: t('gifts.itemBoost', 'Boost'),
    rig: t('gifts.itemRig', 'Rig'),
    prepaid_card: t('gifts.itemPrepaidCard', 'Prepaid Card'),
  };
  return names[type] || id || t('gifts.itemGeneric', 'Item');
}

function initAd() {
  setTimeout(() => {
    try {
      document.querySelectorAll('ins.adsbygoogle').forEach((el) => {
        if (el.clientWidth > 0 && !el.hasAttribute('data-adsbygoogle-status')) {
          ((window as any).adsbygoogle = (window as any).adsbygoogle || []).push({});
        }
      });
    } catch (e) {
      // AdSense not available
    }
  }, 500);
}
</script>

<template>
  <Teleport to="body">
    <!-- Confetti Overlay -->
    <div v-if="showConfetti" class="fixed inset-0 z-[100] pointer-events-none overflow-hidden">
      <div
        v-for="piece in confettiPieces"
        :key="piece.id"
        class="confetti-piece"
        :style="{
          left: `${piece.left}%`,
          backgroundColor: piece.color,
          width: `${piece.size}px`,
          height: `${piece.size}px`,
          animationDelay: `${piece.delay}s`,
        }"
      ></div>
    </div>

    <!-- Phase: SHOWING - Gift floating animated -->
    <div
      v-if="giftsStore.phase === 'showing'"
      class="fixed inset-0 z-50 flex items-center justify-center"
    >
      <!-- Backdrop -->
      <div class="absolute inset-0 bg-black/70 backdrop-blur-sm animate-fade-in"></div>

      <!-- Content -->
      <div class="relative flex flex-col items-center gap-3 animate-fade-in">
        <!-- Floating particles -->
        <div class="absolute inset-0 pointer-events-none">
          <div
            v-for="p in particles"
            :key="p.id"
            class="gift-particle"
            :style="{
              left: `calc(50% + ${p.x}px)`,
              top: `calc(50% + ${p.y}px)`,
              width: `${p.size}px`,
              height: `${p.size}px`,
              animationDelay: `${p.delay}s`,
            }"
          ></div>
        </div>

        <!-- Title -->
        <div class="text-center z-10">
          <p class="text-sm text-amber-300 font-medium animate-pulse-slow">
            {{ t('gifts.surprise') }}
          </p>
          <p v-if="giftsStore.currentGift?.title" class="text-[11px] text-text-muted mt-0.5">
            {{ giftsStore.currentGift.title }}
          </p>
        </div>

        <!-- Gift Box -->
        <button
          @click="handleGiftClick"
          class="relative z-10 gift-box-btn focus:outline-none"
        >
          <div class="gift-box">
            <span class="text-5xl gift-float gift-glow select-none">
              {{ giftsStore.currentGift?.icon || '🎁' }}
            </span>
          </div>
        </button>

        <!-- Tap to open -->
        <p class="text-[11px] text-text-muted z-10 animate-pulse-slow">
          {{ t('gifts.tapToOpen') }}
        </p>
      </div>
    </div>

    <!-- Phase: OPENING - Shake + explode animation -->
    <div
      v-if="giftsStore.phase === 'opening'"
      class="fixed inset-0 z-50 flex items-center justify-center"
    >
      <div class="absolute inset-0 bg-black/70 backdrop-blur-sm"></div>

      <div class="relative flex flex-col items-center gap-2">
        <!-- Shaking gift -->
        <div class="gift-shake">
          <span class="text-6xl select-none">
            {{ giftsStore.currentGift?.icon || '🎁' }}
          </span>
        </div>

        <p class="text-xs text-amber-300 z-10 animate-pulse">
          {{ t('gifts.opening') }}
        </p>
      </div>
    </div>

    <!-- Phase: REVEALED - Show reward -->
    <div
      v-if="giftsStore.phase === 'revealed'"
      class="fixed inset-0 z-50 flex items-center justify-center p-4"
    >
      <div class="absolute inset-0 bg-black/70 backdrop-blur-sm"></div>

      <div class="relative w-full max-w-sm animate-fade-in">
        <div class="bg-bg-secondary border border-border/50 rounded-2xl p-6 text-center shadow-2xl">
          <!-- Title + Icon -->
          <div class="mb-4">
            <div class="text-5xl mb-3 gift-reveal-bounce">
              {{ giftsStore.currentGift?.icon || '🎁' }}
            </div>
            <h2 class="text-xl font-display font-bold">
              <span class="gradient-text">{{ t('gifts.received') }}</span>
            </h2>
            <p v-if="giftsStore.currentGift?.description" class="text-sm text-text-muted mt-1">
              {{ giftsStore.currentGift.description }}
            </p>
          </div>

          <!-- Rewards -->
          <div class="space-y-2 mb-5">
            <div
              v-for="(line, idx) in getRewardLines()"
              :key="idx"
              class="flex items-center justify-center gap-3 px-4 py-3 bg-bg-tertiary rounded-xl reward-line-appear"
              :style="{ animationDelay: `${idx * 0.15}s` }"
            >
              <span class="text-2xl">{{ line.emoji }}</span>
              <span class="text-base font-bold text-accent-primary">{{ line.text }}</span>
            </div>
          </div>

          <!-- Collect Button -->
          <button
            @click="handleCollect"
            class="w-full py-3 rounded-xl bg-gradient-primary text-white font-bold text-lg hover:opacity-90 transition-opacity"
          >
            {{ t('gifts.collect') }}
          </button>

          <!-- AdSense Banner -->
          <div class="mt-4 bg-bg-tertiary rounded-xl p-4 text-center max-h-28 h-28">
            <div class="text-xs text-text-muted mb-2">{{ t('blocks.sponsoredBy') }}</div>
            <ins class="adsbygoogle"
              style="display:block"
              data-ad-format="autorelaxed"
              data-ad-client="ca-pub-7500429866047477"
              data-ad-slot="7767935377"></ins>
          </div>
        </div>
      </div>
    </div>
  </Teleport>
</template>

<style scoped>
/* Confetti */
.confetti-piece {
  position: absolute;
  top: -20px;
  border-radius: 2px;
  animation: confetti-fall 3s ease-out forwards;
  transform-origin: center;
}

@keyframes confetti-fall {
  0% { transform: translateY(0) rotate(0deg) scale(1); opacity: 1; }
  25% { transform: translateY(25vh) rotate(180deg) scale(0.9); opacity: 1; }
  50% { transform: translateY(50vh) rotate(360deg) scale(0.8); opacity: 0.9; }
  75% { transform: translateY(75vh) rotate(540deg) scale(0.7); opacity: 0.6; }
  100% { transform: translateY(100vh) rotate(720deg) scale(0.5); opacity: 0; }
}

.confetti-piece:nth-child(odd) {
  animation-name: confetti-fall-wobble;
}

@keyframes confetti-fall-wobble {
  0% { transform: translateY(0) translateX(0) rotate(0deg) scale(1); opacity: 1; }
  25% { transform: translateY(25vh) translateX(20px) rotate(180deg) scale(0.9); opacity: 1; }
  50% { transform: translateY(50vh) translateX(-15px) rotate(360deg) scale(0.8); opacity: 0.9; }
  75% { transform: translateY(75vh) translateX(10px) rotate(540deg) scale(0.7); opacity: 0.6; }
  100% { transform: translateY(100vh) translateX(-5px) rotate(720deg) scale(0.5); opacity: 0; }
}

.confetti-piece:nth-child(3n) { border-radius: 50%; }
.confetti-piece:nth-child(4n) { border-radius: 0; transform: rotate(45deg); }

/* Gift floating animation */
.gift-float {
  display: inline-block;
  animation: gift-float 3s ease-in-out infinite;
}

@keyframes gift-float {
  0%, 100% { transform: translateY(0); }
  50% { transform: translateY(-15px); }
}

/* Gift glow */
.gift-glow {
  filter: drop-shadow(0 0 20px rgba(251, 191, 36, 0.5));
  animation: gift-float 3s ease-in-out infinite, gift-glow-pulse 2s ease-in-out infinite;
}

@keyframes gift-glow-pulse {
  0%, 100% { filter: drop-shadow(0 0 20px rgba(251, 191, 36, 0.4)); }
  50% { filter: drop-shadow(0 0 40px rgba(251, 191, 36, 0.8)); }
}

/* Gift box button */
.gift-box-btn {
  transition: transform 0.2s ease;
}

.gift-box-btn:active {
  transform: scale(0.95);
}

/* Gift shake */
.gift-shake {
  animation: gift-shake 0.8s ease-in-out;
}

@keyframes gift-shake {
  0%, 100% { transform: rotate(0deg) scale(1); }
  10% { transform: rotate(-15deg) scale(1.05); }
  20% { transform: rotate(15deg) scale(1.1); }
  30% { transform: rotate(-15deg) scale(1.15); }
  40% { transform: rotate(15deg) scale(1.2); }
  50% { transform: rotate(-10deg) scale(1.25); }
  60% { transform: rotate(10deg) scale(1.3); }
  70% { transform: rotate(-5deg) scale(1.2); }
  80% { transform: scale(1.5); opacity: 0.8; }
  90% { transform: scale(2); opacity: 0.4; }
  100% { transform: scale(2.5); opacity: 0; }
}

/* Reveal bounce */
.gift-reveal-bounce {
  display: inline-block;
  animation: gift-reveal-bounce 0.6s ease-out;
}

@keyframes gift-reveal-bounce {
  0% { transform: scale(0); opacity: 0; }
  50% { transform: scale(1.3); }
  70% { transform: scale(0.9); }
  100% { transform: scale(1); opacity: 1; }
}

/* Reward line appear */
.reward-line-appear {
  opacity: 0;
  transform: translateY(10px);
  animation: reward-line-appear 0.4s ease-out forwards;
}

@keyframes reward-line-appear {
  0% { opacity: 0; transform: translateY(10px); }
  100% { opacity: 1; transform: translateY(0); }
}

/* Golden particles */
.gift-particle {
  position: absolute;
  background: #fbbf24;
  border-radius: 50%;
  opacity: 0;
  animation: gift-particle-float 3s ease-in-out infinite;
}

@keyframes gift-particle-float {
  0%, 100% { opacity: 0; transform: translateY(0) scale(0.5); }
  50% { opacity: 0.8; transform: translateY(-30px) scale(1); }
}

/* Fade in */
.animate-fade-in {
  animation: fade-in 0.3s ease-out;
}

@keyframes fade-in {
  0% { opacity: 0; }
  100% { opacity: 1; }
}

/* Slow pulse */
.animate-pulse-slow {
  animation: pulse-slow 2s ease-in-out infinite;
}

@keyframes pulse-slow {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.6; }
}
</style>
