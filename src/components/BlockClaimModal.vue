<script setup lang="ts">
import { ref, watch, onMounted, onUnmounted, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { usePendingBlocksStore } from '@/stores/pendingBlocks';
import { playSound } from '@/utils/sounds';

const { t } = useI18n();
const pendingStore = usePendingBlocksStore();

const props = defineProps<{
  show: boolean;
}>();

const emit = defineEmits<{
  close: [];
}>();

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

function onCaptchaSuccess(token: string) {
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
    // Reset para el siguiente bloque
    resetCaptcha();
  }
}

function cancelClaim() {
  resetCaptcha();
}

function handleClose() {
  pendingStore.closeModal();
  emit('close');
}

function getSelectedBlock() {
  return pendingStore.pendingBlocks.find(b => b.id === selectedBlockId.value);
}
</script>

<template>
  <Teleport to="body">
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
      <div class="relative w-full max-w-lg max-h-[85vh] overflow-hidden card animate-fade-in">
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
          <!-- Loading -->
          <div v-if="pendingStore.loading" class="text-center py-12 text-text-muted">
            {{ t('common.loading') }}
          </div>

          <!-- Empty State -->
          <div v-else-if="!pendingStore.hasPending" class="text-center py-12">
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
                <div class="text-3xl font-bold text-accent-primary">
                  {{ pendingStore.totalReward.toFixed(2) }} ₿
                </div>
              </div>
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
