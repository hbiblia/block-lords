<script setup lang="ts">
import { watch, onMounted } from 'vue';
import { useAuthStore } from '@/stores/auth';
import { useRealtimeStore } from '@/stores/realtime';
import MainLayout from '@/layouts/MainLayout.vue';

const authStore = useAuthStore();
const realtimeStore = useRealtimeStore();

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
</script>

<template>
  <!-- Skeleton overlay mientras auth se inicializa -->
  <Transition name="slide-down">
  <div v-if="!authStore.initialized" class="fixed inset-0 z-50 bg-bg-primary overflow-hidden">
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
</style>
