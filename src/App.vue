<script setup lang="ts">
import { watch, onMounted, ref } from 'vue';
import { useAuthStore } from '@/stores/auth';
import { useRealtimeStore } from '@/stores/realtime';
import { useGameTickStore } from '@/stores/game-tick';
import { useI18n } from 'vue-i18n';
import MainLayout from '@/layouts/MainLayout.vue';
import UpdateModal from '@/components/UpdateModal.vue';
import { useTabLock } from '@/composables/useTabLock';
import { Pickaxe, AppWindow } from 'lucide-vue-next';

const { t } = useI18n();
const authStore = useAuthStore();
const realtimeStore = useRealtimeStore();
const gameTickStore = useGameTickStore();
const isRetrying = ref(false);
const { isSuperseded } = useTabLock();

// Pause/resume DB activity based on tab lock state
watch(isSuperseded, (locked) => {
  if (locked) {
    realtimeStore.disconnect();
    gameTickStore.stop();
  } else if (authStore.isAuthenticated) {
    realtimeStore.connect();
    gameTickStore.start();
  }
});

// Inicializar auth al montar la app
onMounted(async () => {
  await authStore.waitForInit();
});

// Conectar realtime y game tick cuando el usuario esté autenticado
watch(
  () => authStore.isAuthenticated,
  (isAuth) => {
    if (isAuth) {
      realtimeStore.connect();
      gameTickStore.start();
    } else {
      realtimeStore.disconnect();
      gameTickStore.stop();
    }
  },
  { immediate: true }
);

function handleRefresh() {
  window.location.reload();
}

// Reintentar conexión
async function handleRetry() {
  isRetrying.value = true;
  try {
    await authStore.retryConnection();
  } finally {
    isRetrying.value = false;
  }
}
</script>

<template>
  <!-- Skeleton overlay mientras auth se inicializa -->
  <Transition name="slide-down">
  <div v-if="!authStore.initialized && !authStore.connectionError" class="app-skel">
    <!-- Top bar skeleton -->
    <div class="app-skel-topbar">
      <div class="app-skel-brand">
        <Pickaxe :size="18" color="#c4a0e8" />
        <div class="app-skel-block" style="width:80px;height:14px"></div>
      </div>
      <div style="display:flex;gap:8px">
        <div class="app-skel-block" style="width:50px;height:28px;border-radius:8px"></div>
        <div class="app-skel-block" style="width:60px;height:28px;border-radius:8px"></div>
      </div>
    </div>
    <!-- Content skeleton -->
    <div class="app-skel-body">
      <div class="app-skel-card">
        <div class="app-skel-block" style="width:40%;height:12px;margin-bottom:12px"></div>
        <div class="app-skel-block" style="width:100%;height:8px;margin-bottom:16px"></div>
        <div style="display:grid;grid-template-columns:repeat(3,1fr);gap:10px">
          <div class="app-skel-block" style="height:50px;border-radius:10px"></div>
          <div class="app-skel-block" style="height:50px;border-radius:10px"></div>
          <div class="app-skel-block" style="height:50px;border-radius:10px"></div>
        </div>
      </div>
      <div class="app-skel-card">
        <div class="app-skel-block" style="width:30%;height:12px;margin-bottom:12px"></div>
        <div style="display:grid;grid-template-columns:repeat(2,1fr);gap:10px">
          <div class="app-skel-block" style="height:70px;border-radius:10px"></div>
          <div class="app-skel-block" style="height:70px;border-radius:10px"></div>
        </div>
      </div>
    </div>
  </div>
  </Transition>

  <!-- Error de conexión toast -->
  <Teleport to="body">
    <Transition name="toast">
      <div
        v-if="!isSuperseded && (authStore.connectionError || !authStore.isServerOnline)"
        class="fixed bottom-20 left-1/2 -translate-x-1/2 z-[100] w-[calc(100%-2rem)] max-w-sm"
      >
        <div class="flex items-center gap-2.5 px-3.5 py-2.5 rounded-xl bg-slate-900/95 border border-red-500/40 shadow-lg shadow-red-500/10 backdrop-blur-sm">
          <span class="text-lg flex-shrink-0">&#9888;</span>

          <p class="flex-1 min-w-0 text-xs font-semibold text-red-300 truncate">
            {{ t('connection.error.title') }}
          </p>

          <button
            @click="handleRetry"
            :disabled="isRetrying"
            class="flex-shrink-0 px-2.5 py-1 rounded-lg text-[11px] font-bold bg-amber-500/20 text-amber-300 hover:bg-amber-500/30 transition-colors disabled:opacity-50"
          >
            {{ isRetrying ? t('connection.error.retrying') : t('connection.error.retry') }}
          </button>

          <button
            @click="handleRefresh"
            class="flex-shrink-0 px-2.5 py-1 rounded-lg text-[11px] font-bold bg-red-500/20 text-red-300 hover:bg-red-500/30 transition-colors"
          >
            {{ t('connection.reloadPage') }}
          </button>
        </div>
      </div>
    </Transition>
  </Teleport>

  <!-- Duplicate tab overlay -->
  <Transition name="fade">
  <div v-if="isSuperseded" class="fixed inset-0 z-[200] bg-black/80 backdrop-blur-sm flex items-center justify-center p-4">
    <div class="card p-8 max-w-sm w-full text-center border border-border/50 shadow-2xl">
      <div class="w-16 h-16 mx-auto mb-5 rounded-full bg-amber-500/10 flex items-center justify-center">
        <AppWindow :size="28" color="#f59e0b" />
      </div>
      <h2 class="text-xl font-bold text-text-primary mb-2">{{ t('tabLock.title') }}</h2>
      <p class="text-text-secondary text-sm mb-2">{{ t('tabLock.message') }}</p>
      <p class="text-text-muted text-xs">{{ t('tabLock.hint') }}</p>
    </div>
  </div>
  </Transition>

  <!-- Modal de actualización (se muestra una sola vez por versión) -->
  <UpdateModal />

  <!-- App siempre renderizado (skeleton lo cubre inicialmente) -->
  <MainLayout>
    <RouterView v-slot="{ Component }">
      <Transition name="page" mode="out-in">
        <component :is="Component" />
      </Transition>
    </RouterView>
  </MainLayout>
</template>

<style>
/* Page transitions */
.page-enter-active,
.page-leave-active {
  transition: opacity 0.2s ease, transform 0.2s ease;
}

.page-enter-from {
  opacity: 0;
  transform: translateY(10px);
}

.page-leave-to {
  opacity: 0;
  transform: translateY(-10px);
}

/* Kawaii Skeleton */
@import url('https://fonts.googleapis.com/css2?family=Nunito:wght@400;600;700;800;900&display=swap');

.app-skel {
  position: fixed; inset: 0; z-index: 50;
  background: #f8e8f0;
  background-image: radial-gradient(circle, #e8c8d8 1.5px, transparent 1.5px);
  background-size: 20px 20px;
  font-family: 'Nunito', 'Trebuchet MS', sans-serif;
  overflow: hidden;
}
.app-skel-topbar {
  display: flex; align-items: center; justify-content: space-between;
  padding: 0.8rem 1.5rem;
  background: #fff; border-bottom: 2px solid #c4a0e8;
}
.app-skel-brand { display: flex; align-items: center; gap: 8px; }
.app-skel-body {
  max-width: 800px; margin: 2rem auto; padding: 0 1rem;
  display: flex; flex-direction: column; gap: 1rem;
}
.app-skel-card {
  background: #fff; border: 2px solid #d0b8e8; border-radius: 14px;
  padding: 1.2rem; box-shadow: 2px 2px 0 #e8d0f0;
}
.app-skel-block {
  background: linear-gradient(90deg, #e8d8f4 25%, #f0e4fa 50%, #e8d8f4 75%);
  background-size: 200% 100%;
  animation: app-skel-shimmer 1.5s ease infinite;
  border-radius: 6px; height: 12px;
}
@keyframes app-skel-shimmer {
  0% { background-position: 200% 0; }
  100% { background-position: -200% 0; }
}

/* Skeleton slide down animation */
.slide-down-leave-active {
  transition: transform 0.4s ease-in, opacity 0.3s ease;
}

.slide-down-leave-to {
  transform: translateY(100%);
  opacity: 0;
}

/* Fade transition */
.fade-enter-active,
.fade-leave-active {
  transition: opacity 0.3s ease;
}

.fade-enter-from,
.fade-leave-to {
  opacity: 0;
}

/* Toast transition for connection error */
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
