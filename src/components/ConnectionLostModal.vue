<script setup lang="ts">
import { watch, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useGameTickStore } from '@/stores/game-tick';
import { playSound } from '@/utils/sounds';

const { t } = useI18n();
const gameTickStore = useGameTickStore();

const showDisconnected = computed(() =>
  gameTickStore.tickCount > 0 && !gameTickStore.isHealthy
);

watch(showDisconnected, (show) => {
  if (show) playSound('warning');
});

function handleReconnect() {
  gameTickStore.start();
}

function handleRefresh() {
  window.location.reload();
}
</script>

<template>
  <Teleport to="body">
    <Transition name="toast">
      <div
        v-if="showDisconnected"
        class="fixed bottom-20 left-1/2 -translate-x-1/2 z-[9999] w-[calc(100%-2rem)] max-w-sm"
      >
        <div class="relative overflow-hidden rounded-xl bg-slate-900/95 border border-red-500/30 shadow-lg shadow-red-500/10 backdrop-blur-sm">
          <!-- Barra de acento superior -->
          <div class="absolute top-0 left-0 right-0 h-[2px] bg-gradient-to-r from-red-500 via-amber-500 to-red-500 animate-shimmer"></div>

          <div class="flex items-center gap-3 px-4 py-3">
            <!-- Icono con pulso -->
            <div class="relative flex-shrink-0">
              <span class="text-lg">&#9888;</span>
              <span class="absolute -top-0.5 -right-0.5 w-2 h-2 rounded-full bg-red-400 animate-pulse"></span>
            </div>

            <!-- Mensaje -->
            <div class="flex-1 min-w-0">
              <p class="text-[11px] font-bold text-red-300/60 uppercase tracking-wider mb-0.5">{{ t('connection.label', 'Offline') }}</p>
              <p class="text-xs font-semibold text-white/90 truncate">{{ t('connection.title') }}</p>
            </div>

            <!-- Botón reconectar -->
            <button
              @click="handleReconnect"
              class="flex-shrink-0 px-3 py-1.5 rounded-lg text-[11px] font-bold bg-amber-500/20 text-amber-300 hover:bg-amber-500/30 border border-amber-500/20 hover:border-amber-500/40 transition-all"
            >
              {{ t('connection.reconnect', 'Reconnect') }}
            </button>

            <!-- Botón recargar -->
            <button
              @click="handleRefresh"
              class="flex-shrink-0 px-3 py-1.5 rounded-lg text-[11px] font-bold bg-red-500/20 text-red-300 hover:bg-red-500/30 border border-red-500/20 hover:border-red-500/40 transition-all"
            >
              {{ t('connection.reloadPage') }}
            </button>
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
@keyframes shimmer {
  0% { background-position: -200% 0; }
  100% { background-position: 200% 0; }
}

.animate-shimmer {
  background-size: 200% 100%;
  animation: shimmer 3s linear infinite;
}

.toast-enter-active {
  transition: all 0.3s ease-out;
}

.toast-leave-active {
  transition: all 0.2s ease-in;
}

.toast-enter-from {
  opacity: 0;
  transform: translate(-50%, 20px);
}

.toast-leave-to {
  opacity: 0;
  transform: translate(-50%, 20px);
}
</style>
