<script setup lang="ts">
import { ref, watch, onUnmounted, nextTick, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { usePendingBlocksStore } from '@/stores/pendingBlocks';
import { useAuthStore } from '@/stores/auth';
import { playSound } from '@/utils/sounds';

const { t } = useI18n();
const pendingStore = usePendingBlocksStore();
const authStore = useAuthStore();

// RON balance check
const ronBalance = computed(() => authStore.player?.ron_balance ?? 0);
const canAffordRonClaim = computed(() => ronBalance.value >= pendingStore.totalRonCost);

const props = defineProps<{
  show: boolean;
}>();

const emit = defineEmits<{
  close: [];
}>();

// Confetti state
const showConfetti = ref(false);
const confettiPieces = ref<{ id: number; left: number; color: string; delay: number; size: number }[]>([]);

function triggerConfetti() {
  const colors = ['#f59e0b', '#10b981', '#3b82f6', '#ec4899', '#8b5cf6', '#ef4444'];
  confettiPieces.value = Array.from({ length: 50 }, (_, i) => ({
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

// Estado del captcha
const selectedBlockId = ref<string | null>(null);
const captchaVerified = ref(false);
const captchaWidgetId = ref<number | null>(null);
const captchaContainer = ref<HTMLElement | null>(null);

// Bloquear scroll del body cuando el modal está abierto
watch(() => props.show, (isOpen) => {
  if (isOpen) {
    document.body.style.overflow = 'hidden';
    pendingStore.fetchPendingBlocks();
    // Reset captcha state
    selectedBlockId.value = null;
    captchaVerified.value = false;
  } else {
    document.body.style.overflow = '';
    resetCaptcha();
  }
});

onUnmounted(() => {
  document.body.style.overflow = '';
});

function formatTimeAgo(dateStr: string) {
  const date = new Date(dateStr);
  const now = new Date();
  const diff = now.getTime() - date.getTime();

  const minutes = Math.floor(diff / (1000 * 60));
  const hours = Math.floor(diff / (1000 * 60 * 60));

  if (minutes < 1) return 'Ahora';
  if (minutes < 60) return `${minutes}m`;
  if (hours < 24) return `${hours}h`;
  return `${Math.floor(hours / 24)}d`;
}

// Seleccionar bloque para claim (muestra captcha)
function selectBlockForClaim(blockId: string) {
  selectedBlockId.value = blockId;
  captchaVerified.value = false;

  // Renderizar captcha después de que el DOM se actualice
  nextTick(() => {
    renderCaptcha();
  });
}

// Renderizar hCaptcha
function renderCaptcha() {
  if (typeof (window as any).hcaptcha !== 'undefined' && captchaContainer.value) {
    // Reset si ya existe
    if (captchaWidgetId.value !== null) {
      (window as any).hcaptcha.reset(captchaWidgetId.value);
    }

    captchaWidgetId.value = (window as any).hcaptcha.render(captchaContainer.value, {
      sitekey: '330e8d5c-9428-4450-869c-b638d490da2e',
      callback: onCaptchaSuccess,
      'expired-callback': onCaptchaExpired,
      'error-callback': onCaptchaError,
      theme: 'dark',
    });
  }
}

function onCaptchaSuccess(_token: string) {
  console.log('Captcha verified');
  captchaVerified.value = true;
}

function onCaptchaExpired() {
  captchaVerified.value = false;
}

function onCaptchaError() {
  captchaVerified.value = false;
}

function resetCaptcha() {
  if (captchaWidgetId.value !== null && typeof (window as any).hcaptcha !== 'undefined') {
    try {
      (window as any).hcaptcha.reset(captchaWidgetId.value);
    } catch (e) {
      // Ignore errors on reset
    }
  }
  selectedBlockId.value = null;
  captchaVerified.value = false;
}

// Ejecutar claim después de verificar captcha
async function handleClaimAfterCaptcha() {
  if (!selectedBlockId.value || !captchaVerified.value) return;

  const result = await pendingStore.claim(selectedBlockId.value);
  if (result) {
    playSound('reward');
    triggerConfetti();
    // Reset para el siguiente bloque
    resetCaptcha();
  }
}

function cancelClaim() {
  resetCaptcha();
}

function handleClose() {
  playSound('click');
  pendingStore.closeModal();
  emit('close');
}

// Claim all blocks with RON payment
async function handleClaimAllWithRon() {
  if (!canAffordRonClaim.value) return;

  const result = await pendingStore.claimAllWithRon();
  if (result) {
    playSound('reward');
    triggerConfetti();
  }
}

function getSelectedBlock() {
  return pendingStore.pendingBlocks.find(b => b.id === selectedBlockId.value);
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

    <div
      v-if="show"
      class="fixed inset-0 z-50 flex items-center justify-center p-4"
    >
      <!-- Backdrop -->
      <div
        class="absolute inset-0 bg-black/70 backdrop-blur-sm"
        @click="handleClose"
      ></div>

      <!-- Modal -->
      <div class="relative w-full max-w-lg max-h-[85vh] overflow-hidden card animate-fade-in p-0">
        <!-- Header -->
        <div class="flex items-center justify-between p-4 border-b border-border/50">
          <div class="flex items-center gap-3">
            <div class="text-3xl">⛏️</div>
            <div>
              <h2 class="text-xl font-display font-bold">
                <span class="gradient-text">{{ t('blocks.claimTitle') }}</span>
              </h2>
              <p class="text-sm text-text-muted">
                {{ pendingStore.count }} {{ t('blocks.pendingBlocks') }}
              </p>
            </div>
          </div>
          <button
            @click="handleClose"
            class="w-8 h-8 rounded-lg bg-bg-tertiary hover:bg-bg-secondary flex items-center justify-center transition-colors"
          >
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        <!-- Content -->
        <div class="p-4 overflow-y-auto max-h-[60vh]">
          <!-- Empty State -->
          <div v-if="!pendingStore.loading && !pendingStore.hasPending" class="text-center py-12">
            <div class="text-5xl mb-4">✨</div>
            <h3 class="text-lg font-medium mb-2">{{ t('blocks.noPending') }}</h3>
            <p class="text-text-muted text-sm">{{ t('blocks.noPendingDesc') }}</p>
          </div>

          <!-- Captcha Verification Screen -->
          <div v-else-if="selectedBlockId" class="text-center">
            <div class="mb-4">
              <div class="text-5xl mb-2">🔐</div>
              <h3 class="text-lg font-bold mb-1">{{ t('blocks.verifyMiner') }}</h3>
              <p class="text-text-muted text-sm">{{ t('blocks.verifyCaptcha') }}</p>
            </div>

            <!-- Block Info -->
            <div class="bg-bg-secondary rounded-xl p-4 mb-4">
              <div class="text-sm text-text-muted">Block #{{ getSelectedBlock()?.block_height }}</div>
              <div class="text-2xl font-bold text-accent-primary">
                +{{ Number(getSelectedBlock()?.reward ?? 0).toFixed(2) }} ₿
              </div>
            </div>

            <!-- hCaptcha Container -->
            <div class="flex justify-center mb-4">
              <div ref="captchaContainer" class="h-captcha"></div>
            </div>

            <!-- Claim Button (solo visible después de verificar) -->
            <button
              v-if="captchaVerified"
              @click="handleClaimAfterCaptcha"
              :disabled="pendingStore.claiming"
              class="w-full py-4 rounded-xl bg-gradient-primary text-white font-bold text-lg hover:opacity-90 transition-opacity disabled:opacity-50 mb-3"
            >
              <span v-if="pendingStore.claiming">{{ t('blocks.claiming') }}</span>
              <span v-else class="flex items-center justify-center gap-2">
                ✅ {{ t('blocks.claimVerified') }}
              </span>
            </button>

            <!-- Cancel Button -->
            <button
              @click="cancelClaim"
              class="w-full py-3 rounded-xl bg-bg-tertiary text-text-muted hover:bg-bg-secondary transition-colors"
            >
              {{ t('common.cancel') }}
            </button>
          </div>

          <!-- Pending Blocks List -->
          <div v-else>
            <!-- Summary -->
            <div class="bg-gradient-to-r from-accent-primary/20 to-accent-secondary/20 rounded-xl p-4 mb-4">
              <div class="text-center">
                <div class="text-sm text-text-muted mb-1">{{ t('blocks.totalReward') }}</div>
                <div v-if="pendingStore.loading && pendingStore.pendingBlocks.length === 0" class="flex justify-center py-2">
                  <span class="animate-spin w-6 h-6 border-2 border-accent-primary border-t-transparent rounded-full"></span>
                </div>
                <div v-else class="text-3xl font-bold text-accent-primary">
                  {{ pendingStore.totalReward.toFixed(2) }} ₿
                </div>
              </div>
            </div>

            <!-- Claim All with RON Button -->
            <div v-if="pendingStore.hasPending" class="mb-4">
              <button
                @click="handleClaimAllWithRon"
                :disabled="pendingStore.claiming || !canAffordRonClaim"
                class="w-full py-3 rounded-xl bg-gradient-to-r from-blue-500 to-purple-600 text-white font-bold hover:opacity-90 transition-opacity disabled:opacity-50 flex items-center justify-center gap-2"
              >
                <span v-if="pendingStore.claiming" class="flex items-center gap-2">
                  <span class="animate-spin w-4 h-4 border-2 border-white border-t-transparent rounded-full"></span>
                  Reclamando...
                </span>
                <span v-else class="flex items-center gap-2">
                  ⚡ Reclamar Todo ({{ pendingStore.totalRonCost.toFixed(3) }} RON)
                </span>
              </button>
              <div class="text-center mt-2 text-xs">
                <span v-if="canAffordRonClaim" class="text-text-muted">
                  Tu balance: {{ ronBalance.toFixed(3) }} RON • {{ pendingStore.RON_COST_PER_BLOCK }} RON/bloque
                </span>
                <span v-else class="text-status-error">
                  RON insuficiente (necesitas {{ pendingStore.totalRonCost.toFixed(3) }} RON, tienes {{ ronBalance.toFixed(3) }})
                </span>
              </div>
            </div>

            <!-- Separator -->
            <div class="flex items-center gap-3 mb-4">
              <div class="flex-1 h-px bg-border/50"></div>
              <span class="text-xs text-text-muted">o reclama gratis uno a uno</span>
              <div class="flex-1 h-px bg-border/50"></div>
            </div>

            <!-- Info about verification -->
            <div class="bg-status-warning/10 border border-status-warning/30 rounded-xl p-3 mb-4 text-sm">
              <p class="flex items-center gap-2 text-status-warning">
                <span>🔐</span>
                {{ t('blocks.captchaRequired') }}
              </p>
            </div>

            <!-- Blocks List -->
            <div class="space-y-2">
              <h3 class="text-sm font-medium text-text-muted mb-2">{{ t('blocks.pendingList') }}</h3>

              <!-- Skeleton Loading -->
              <template v-if="pendingStore.loading && pendingStore.pendingBlocks.length === 0">
                <div
                  v-for="i in 3"
                  :key="i"
                  class="flex items-center justify-between p-3 bg-bg-secondary rounded-lg animate-pulse"
                >
                  <div class="flex items-center gap-3">
                    <div class="w-10 h-10 rounded-lg bg-bg-tertiary"></div>
                    <div>
                      <div class="h-4 bg-bg-tertiary rounded w-24 mb-2"></div>
                      <div class="h-3 bg-bg-tertiary rounded w-12"></div>
                    </div>
                  </div>
                  <div class="flex items-center gap-3">
                    <div class="h-5 bg-bg-tertiary rounded w-16"></div>
                    <div class="h-8 bg-bg-tertiary rounded w-16"></div>
                  </div>
                </div>
              </template>

              <!-- Actual Blocks -->
              <div
                v-for="block in pendingStore.pendingBlocks"
                :key="block.id"
                class="flex items-center justify-between p-3 bg-bg-secondary rounded-lg hover:bg-bg-tertiary transition-colors"
              >
                <div class="flex items-center gap-3">
                  <div class="w-10 h-10 rounded-lg bg-accent-primary/20 flex items-center justify-center">
                    <span class="text-lg">📦</span>
                  </div>
                  <div>
                    <div class="font-medium">Block #{{ block.block_height }}</div>
                    <div class="text-xs text-text-muted">{{ formatTimeAgo(block.created_at) }}</div>
                  </div>
                </div>

                <div class="flex items-center gap-3">
                  <div class="text-right">
                    <div class="font-bold text-accent-primary">+{{ Number(block.reward).toFixed(2) }} ₿</div>
                  </div>
                  <button
                    @click="selectBlockForClaim(block.id)"
                    :disabled="pendingStore.claiming"
                    class="px-3 py-1.5 rounded-lg bg-accent-primary/20 text-accent-primary hover:bg-accent-primary/30 transition-colors disabled:opacity-50 text-sm font-medium"
                  >
                    {{ t('blocks.claim') }}
                  </button>
                </div>
              </div>
            </div>

            <!-- AdSense Banner -->
            <div class="mt-4 bg-bg-secondary rounded-xl p-4 text-center">
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
    </div>
  </Teleport>
</template>

<style scoped>
.confetti-piece {
  position: absolute;
  top: -20px;
  border-radius: 2px;
  animation: confetti-fall 3s ease-out forwards;
  transform-origin: center;
}

@keyframes confetti-fall {
  0% {
    transform: translateY(0) rotate(0deg) scale(1);
    opacity: 1;
  }
  25% {
    transform: translateY(25vh) rotate(180deg) scale(0.9);
    opacity: 1;
  }
  50% {
    transform: translateY(50vh) rotate(360deg) scale(0.8);
    opacity: 0.9;
  }
  75% {
    transform: translateY(75vh) rotate(540deg) scale(0.7);
    opacity: 0.6;
  }
  100% {
    transform: translateY(100vh) rotate(720deg) scale(0.5);
    opacity: 0;
  }
}

.confetti-piece:nth-child(odd) {
  animation-name: confetti-fall-wobble;
}

@keyframes confetti-fall-wobble {
  0% {
    transform: translateY(0) translateX(0) rotate(0deg) scale(1);
    opacity: 1;
  }
  25% {
    transform: translateY(25vh) translateX(20px) rotate(180deg) scale(0.9);
    opacity: 1;
  }
  50% {
    transform: translateY(50vh) translateX(-15px) rotate(360deg) scale(0.8);
    opacity: 0.9;
  }
  75% {
    transform: translateY(75vh) translateX(10px) rotate(540deg) scale(0.7);
    opacity: 0.6;
  }
  100% {
    transform: translateY(100vh) translateX(-5px) rotate(720deg) scale(0.5);
    opacity: 0;
  }
}

.confetti-piece:nth-child(3n) {
  border-radius: 50%;
}

.confetti-piece:nth-child(4n) {
  border-radius: 0;
  transform: rotate(45deg);
}
</style>
