<script setup lang="ts">
import { ref, onMounted, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();

// Versión actual de la app (actualizar esto cuando haya cambios importantes)
const CURRENT_VERSION = '2.0.1';
const STORAGE_KEY = 'lootmine-last-seen-version';

const route = useRoute();
const showModal = ref(false);
const shouldShow = ref(false);

onMounted(() => {
  const lastSeenVersion = localStorage.getItem(STORAGE_KEY);
  if (!lastSeenVersion || lastSeenVersion !== CURRENT_VERSION) {
    shouldShow.value = true;
    // Si ya estamos en /mining, mostrar inmediatamente
    if (route.path === '/mining') {
      showModal.value = true;
    }
  }
});

// Mostrar cuando el usuario navegue a /mining
watch(() => route.path, (path) => {
  if (path === '/mining' && shouldShow.value) {
    showModal.value = true;
  }
});

// Prevenir scroll del body cuando el modal está abierto
watch(showModal, (isOpen) => {
  if (isOpen) {
    document.body.style.overflow = 'hidden';
  } else {
    document.body.style.overflow = '';
  }
});

function closeModal() {
  localStorage.setItem(STORAGE_KEY, CURRENT_VERSION);
  shouldShow.value = false;
  showModal.value = false;
}
</script>

<template>
  <!-- Modal overlay -->
  <Transition name="fade">
    <div
      v-if="showModal"
      class="fixed inset-0 z-[150] bg-black/50 backdrop-blur-sm flex items-center justify-center p-4"
      @click.self="closeModal"
    >
      <!-- Modal content -->
      <div class="card p-6 max-w-lg w-full border border-border/50 shadow-2xl relative animate-scale-in flex flex-col max-h-[85vh]">
        <!-- Header -->
        <div class="flex items-start justify-between mb-4 flex-shrink-0">
          <div class="flex items-center gap-3">
            <div class="w-10 h-10 rounded-xl bg-gradient-primary flex items-center justify-center text-xl">
              ✨
            </div>
            <div>
              <h2 class="text-xl font-bold text-text-primary">{{ t('updateModal.title') }}</h2>
              <p class="text-xs text-text-muted">{{ t('updateModal.version', { version: CURRENT_VERSION }) }}</p>
            </div>
          </div>
        </div>

        <!-- Contenido scrollable -->
        <div class="space-y-4 overflow-y-auto flex-1 pr-2 custom-scrollbar">
          <!-- Rebranding -->
          <div class="p-3 bg-gradient-to-r from-amber-500/20 to-yellow-500/20 border border-amber-500/30 rounded-lg">
            <h3 class="text-lg font-bold text-text-primary mb-2 flex items-center gap-2">
              <img src="/favicon.svg" class="w-6 h-6" alt="" /> {{ t('updateModal.rebranding.title') }}
            </h3>
            <p class="text-text-secondary text-sm" v-html="t('updateModal.rebranding.description')"></p>
          </div>

          <!-- Battle Arena mejoras -->
          <div class="p-3 bg-gradient-to-r from-blue-500/20 to-cyan-500/20 border border-blue-500/30 rounded-lg">
            <h3 class="text-lg font-bold text-text-primary mb-2 flex items-center gap-2">
              ⚔️ {{ t('updateModal.battleArena.title') }}
            </h3>
            <ul class="space-y-2 text-sm">
              <li class="flex items-start gap-2 text-text-secondary">
                <span class="text-blue-400 mt-0.5">🏆</span>
                <span v-html="t('updateModal.battleArena.leaderboard')"></span>
              </li>
              <li class="flex items-start gap-2 text-text-secondary">
                <span class="text-blue-400 mt-0.5">🔍</span>
                <span v-html="t('updateModal.battleArena.persistentSearch')"></span>
              </li>
              <li class="flex items-start gap-2 text-text-secondary">
                <span class="text-blue-400 mt-0.5">🃏</span>
                <span v-html="t('updateModal.battleArena.cards')"></span>
              </li>
            </ul>
          </div>

          <!-- Sistema de Regalos -->
          <div class="p-3 bg-gradient-to-r from-emerald-500/20 to-green-500/20 border border-emerald-500/30 rounded-lg">
            <h3 class="text-lg font-bold text-text-primary mb-2 flex items-center gap-2">
              🎁 {{ t('updateModal.gifts.title') }}
            </h3>
            <p class="text-text-secondary text-sm">
              {{ t('updateModal.gifts.description') }}
            </p>
          </div>

          <!-- Correcciones y Mejoras -->
          <div>
            <h3 class="text-base font-semibold text-text-primary mb-2 flex items-center gap-2">
              🔧 {{ t('updateModal.fixes.title') }}
            </h3>
            <ul class="space-y-2">
              <li class="flex items-start gap-2 text-text-secondary">
                <span class="text-green-500 mt-1">✓</span>
                <span v-html="t('updateModal.fixes.newLook')"></span>
              </li>
              <li class="flex items-start gap-2 text-text-secondary">
                <span class="text-green-500 mt-1">✓</span>
                <span v-html="t('updateModal.fixes.notifications')"></span>
              </li>
              <li class="flex items-start gap-2 text-text-secondary">
                <span class="text-green-500 mt-1">✓</span>
                <span v-html="t('updateModal.fixes.sounds')"></span>
              </li>
              <li class="flex items-start gap-2 text-text-secondary">
                <span class="text-green-500 mt-1">✓</span>
                <span v-html="t('updateModal.fixes.ronWallet')"></span>
              </li>
              <li class="flex items-start gap-2 text-text-secondary">
                <span class="text-green-500 mt-1">✓</span>
                <span v-html="t('updateModal.fixes.reputation')"></span>
              </li>
              <li class="flex items-start gap-2 text-text-secondary">
                <span class="text-green-500 mt-1">✓</span>
                <span v-html="t('updateModal.fixes.translations')"></span>
              </li>
              <li class="flex items-start gap-2 text-text-secondary">
                <span class="text-green-500 mt-1">✓</span>
                <span v-html="t('updateModal.fixes.rigUpgrade')"></span>
              </li>
            </ul>
          </div>

        </div>

        <!-- Footer con botón -->
        <div class="flex justify-end mt-4 pt-4 border-t border-border/30 flex-shrink-0">
          <button
            @click="closeModal"
            class="btn btn-primary px-6 py-2 font-semibold"
          >
            {{ t('updateModal.button') }} 🚀
          </button>
        </div>
      </div>
    </div>
  </Transition>
</template>

<style scoped>
/* Fade transition */
.fade-enter-active,
.fade-leave-active {
  transition: opacity 0.3s ease;
}

.fade-enter-from,
.fade-leave-to {
  opacity: 0;
}

/* Scale in animation para el modal */
@keyframes scale-in {
  from {
    opacity: 0;
    transform: scale(0.9);
  }
  to {
    opacity: 1;
    transform: scale(1);
  }
}

.animate-scale-in {
  animation: scale-in 0.3s ease-out;
}

/* Custom scrollbar */
.custom-scrollbar::-webkit-scrollbar {
  width: 8px;
}

.custom-scrollbar::-webkit-scrollbar-track {
  background: rgba(255, 255, 255, 0.05);
  border-radius: 4px;
}

.custom-scrollbar::-webkit-scrollbar-thumb {
  background: rgba(245, 158, 11, 0.3);
  border-radius: 4px;
}

.custom-scrollbar::-webkit-scrollbar-thumb:hover {
  background: rgba(245, 158, 11, 0.5);
}
</style>
