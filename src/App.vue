<script setup lang="ts">
import { watch, onMounted, ref } from 'vue';
import { useAuthStore } from '@/stores/auth';
import { useRealtimeStore } from '@/stores/realtime';
import { useMiningStore } from '@/stores/mining';
import { useI18n } from 'vue-i18n';
import MainLayout from '@/layouts/MainLayout.vue';
import UpdateModal from '@/components/UpdateModal.vue';
import { useTabLock } from '@/composables/useTabLock';

const { t } = useI18n();
const authStore = useAuthStore();
const realtimeStore = useRealtimeStore();
const miningStore = useMiningStore();
const isRetrying = ref(false);
const { isSuperseded } = useTabLock();

// Pause/resume DB activity based on tab lock state
watch(isSuperseded, (locked) => {
  if (locked) {
    realtimeStore.disconnect();
    miningStore.unsubscribeFromRealtime();
  } else if (authStore.isAuthenticated) {
    realtimeStore.connect();
    miningStore.subscribeToRealtime();
  }
});

// Inicializar auth al montar la app
onMounted(async () => {
  await authStore.waitForInit();
});

// Conectar realtime cuando el usuario esté autenticado
watch(
  () => authStore.isAuthenticated,
  (isAuth) => {
    if (isAuth) {
      realtimeStore.connect();
    } else {
      realtimeStore.disconnect();
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
  <div v-if="!authStore.initialized && !authStore.connectionError" class="fixed inset-0 z-50 bg-bg-primary overflow-hidden">
    <!-- Skeleton NavBar -->
    <nav class="fixed left-0 right-0 top-0 z-50 glass border-b border-border/50">
      <div class="container mx-auto px-4 h-16 flex items-center justify-between">
        <div class="flex items-center gap-3">
          <div class="w-10 h-10 rounded-xl bg-gradient-primary flex items-center justify-center text-xl">⛏️</div>
          <div class="hidden sm:block h-5 w-28 bg-bg-tertiary rounded animate-pulse"></div>
        </div>
        <div class="flex items-center gap-4">
          <div class="hidden md:flex items-center gap-3">
            <div class="h-8 w-24 bg-bg-tertiary rounded-lg animate-pulse"></div>
            <div class="h-8 w-24 bg-bg-tertiary rounded-lg animate-pulse"></div>
          </div>
          <div class="w-10 h-10 bg-bg-tertiary rounded-full animate-pulse"></div>
        </div>
      </div>
    </nav>

    <!-- Skeleton Content -->
    <main class="container mx-auto px-4 py-6 mt-16">
      <div class="flex items-center justify-between mb-6">
        <div class="h-8 w-32 bg-bg-tertiary rounded animate-pulse"></div>
        <div class="flex items-center gap-3">
          <div class="h-8 w-24 bg-bg-tertiary rounded-lg animate-pulse"></div>
          <div class="h-8 w-32 bg-bg-tertiary rounded-lg animate-pulse"></div>
        </div>
      </div>
      <div class="card p-6 mb-6">
        <div class="flex items-center justify-between mb-6">
          <div class="flex items-center gap-3">
            <div class="w-14 h-14 rounded-xl bg-bg-tertiary animate-pulse"></div>
            <div>
              <div class="h-5 w-40 bg-bg-tertiary rounded animate-pulse mb-2"></div>
              <div class="h-4 w-24 bg-bg-tertiary rounded animate-pulse"></div>
            </div>
          </div>
          <div class="text-right">
            <div class="h-8 w-20 bg-bg-tertiary rounded animate-pulse mb-1"></div>
            <div class="h-3 w-24 bg-bg-tertiary rounded animate-pulse"></div>
          </div>
        </div>
        <div class="h-4 bg-bg-tertiary rounded-full mb-4"></div>
        <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
          <div class="h-16 bg-bg-tertiary rounded-xl animate-pulse"></div>
          <div class="h-16 bg-bg-tertiary rounded-xl animate-pulse"></div>
          <div class="h-16 bg-bg-tertiary rounded-xl animate-pulse"></div>
          <div class="h-16 bg-bg-tertiary rounded-xl animate-pulse"></div>
        </div>
      </div>
    </main>
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
      <div class="w-16 h-16 mx-auto mb-5 rounded-full bg-amber-500/10 flex items-center justify-center text-3xl">
        🪟
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
