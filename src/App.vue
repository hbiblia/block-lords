<script setup lang="ts">
import { watch, onMounted, ref } from 'vue';
import { useAuthStore } from '@/stores/auth';
import { useRealtimeStore } from '@/stores/realtime';
import { useI18n } from 'vue-i18n';
import MainLayout from '@/layouts/MainLayout.vue';
import UpdateModal from '@/components/UpdateModal.vue';

const { t } = useI18n();
const authStore = useAuthStore();
const realtimeStore = useRealtimeStore();
const isRetrying = ref(false);

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

  <!-- Error de conexión overlay -->
  <Transition name="fade">
  <div v-if="authStore.connectionError || !authStore.isServerOnline" class="fixed inset-0 z-[100] bg-black/50 backdrop-blur-sm flex items-center justify-center p-4">
    <div class="card p-8 max-w-md w-full text-center border border-border/50 shadow-2xl">
      <!-- Icono de error -->
      <div class="w-20 h-20 mx-auto mb-6 rounded-full bg-red-500/10 flex items-center justify-center">
        <svg class="w-10 h-10 text-red-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
        </svg>
      </div>

      <!-- Título y mensaje -->
      <h2 class="text-xl font-bold text-text-primary mb-2">{{ t('connection.error.title') }}</h2>
      <p class="text-text-secondary mb-6">{{ t('connection.error.message') }}</p>

      <!-- Detalles del error (colapsable) -->
      <details v-if="authStore.connectionError" class="mb-6 text-left">
        <summary class="text-sm text-text-muted cursor-pointer hover:text-text-secondary">
          {{ t('connection.error.details') }}
        </summary>
        <pre class="mt-2 p-3 bg-bg-tertiary rounded-lg text-xs text-text-muted overflow-auto max-h-24">{{ authStore.connectionError }}</pre>
      </details>

      <!-- Botón de reintentar -->
      <button
        @click="handleRetry"
        :disabled="isRetrying"
        class="btn btn-primary w-full flex items-center justify-center gap-2"
      >
        <svg v-if="isRetrying" class="w-5 h-5 animate-spin" fill="none" viewBox="0 0 24 24">
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
        </svg>
        <svg v-else class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
        </svg>
        {{ isRetrying ? t('connection.error.retrying') : t('connection.error.retry') }}
      </button>

      <!-- Sugerencias -->
      <p class="text-xs text-text-muted mt-4">{{ t('connection.error.suggestions') }}</p>
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

/* Fade transition for connection error */
.fade-enter-active,
.fade-leave-active {
  transition: opacity 0.3s ease;
}

.fade-enter-from,
.fade-leave-to {
  opacity: 0;
}
</style>
