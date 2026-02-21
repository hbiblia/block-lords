<script setup lang="ts">
import { ref, onMounted, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();

// Versión actual de la app (actualizar esto cuando haya cambios importantes)
const CURRENT_VERSION = '2.9.0';
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

          <!-- Grupo: Solo Mining -->
          <div>
            <p class="text-[10px] font-bold uppercase tracking-widest text-amber-400/70 mb-2">⛏️ Solo Mining</p>
            <div class="space-y-2">
              <div class="p-2 bg-white/5 border border-border/30 rounded-lg">
                <h3 class="text-sm font-semibold text-text-primary mb-1 flex items-center gap-2">
                  <span>💰</span> {{ t('updateModal.soloRewardsUp.title') }}
                </h3>
                <p class="text-text-muted text-sm" v-html="t('updateModal.soloRewardsUp.description')"></p>
              </div>
              <div class="p-2 bg-white/5 border border-border/30 rounded-lg">
                <h3 class="text-sm font-semibold text-text-primary mb-1 flex items-center gap-2">
                  <span>📋</span> {{ t('updateModal.soloRecentBlocks.title') }}
                </h3>
                <p class="text-text-muted text-sm" v-html="t('updateModal.soloRecentBlocks.description')"></p>
              </div>
              <div class="p-2 bg-white/5 border border-border/30 rounded-lg">
                <h3 class="text-sm font-semibold text-text-primary mb-1 flex items-center gap-2">
                  <span>🚀</span> {{ t('updateModal.soloBeta.title') }}
                </h3>
                <p class="text-text-muted text-sm" v-html="t('updateModal.soloBeta.description')"></p>
              </div>
              <div class="p-2 bg-white/5 border border-border/30 rounded-lg">
                <h3 class="text-sm font-semibold text-text-primary mb-1 flex items-center gap-2">
                  <span>🔄</span> {{ t('updateModal.soloAutoClose.title') }}
                </h3>
                <p class="text-text-muted text-sm" v-html="t('updateModal.soloAutoClose.description')"></p>
              </div>
            </div>
          </div>

          <!-- Grupo: System & UX -->
          <div>
            <p class="text-[10px] font-bold uppercase tracking-widest text-cyan-400/70 mb-2">🔧 {{ t('updateModal.groupSystem') }}</p>
            <div class="space-y-2">
              <div class="p-2 bg-white/5 border border-border/30 rounded-lg">
                <h3 class="text-sm font-semibold text-text-primary mb-1 flex items-center gap-2">
                  <span>⚡</span> {{ t('updateModal.tickSystem.title') }}
                </h3>
                <p class="text-text-muted text-sm" v-html="t('updateModal.tickSystem.description')"></p>
              </div>
              <div class="p-2 bg-white/5 border border-border/30 rounded-lg">
                <h3 class="text-sm font-semibold text-text-primary mb-1 flex items-center gap-2">
                  <span>🖥️</span> {{ t('updateModal.rigToggleFeedback.title') }}
                </h3>
                <p class="text-text-muted text-sm" v-html="t('updateModal.rigToggleFeedback.description')"></p>
              </div>
            </div>
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
