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
  <!-- Skeleton Layout mientras auth se inicializa -->
  <div v-if="!authStore.initialized" class="min-h-screen bg-bg-primary">
    <!-- Skeleton NavBar -->
    <nav class="fixed left-0 right-0 top-0 z-50 glass border-b border-border/50">
      <div class="container mx-auto px-4 h-16 flex items-center justify-between">
        <!-- Logo -->
        <div class="flex items-center gap-3">
          <div class="w-10 h-10 rounded-xl bg-gradient-primary flex items-center justify-center text-xl">
            ⛏️
          </div>
          <div class="hidden sm:block h-5 w-28 bg-bg-tertiary rounded animate-pulse"></div>
        </div>

        <!-- Skeleton balances -->
        <div class="flex items-center gap-4">
          <div class="hidden md:flex items-center gap-3">
            <div class="h-8 w-24 bg-bg-tertiary rounded-lg animate-pulse"></div>
            <div class="h-8 w-24 bg-bg-tertiary rounded-lg animate-pulse"></div>
            <div class="h-8 w-20 bg-bg-tertiary rounded-lg animate-pulse"></div>
          </div>
          <div class="md:hidden h-8 w-20 bg-bg-tertiary rounded-lg animate-pulse"></div>
          <div class="w-10 h-10 bg-bg-tertiary rounded-full animate-pulse"></div>
        </div>
      </div>
    </nav>

    <!-- Skeleton Main Content -->
    <main class="container mx-auto px-4 py-6 mt-16">
      <!-- Skeleton Mining Status Panel -->
      <div class="card p-6 mb-6">
        <div class="flex items-center justify-between mb-4">
          <div class="h-6 w-40 bg-bg-tertiary rounded animate-pulse"></div>
          <div class="h-8 w-24 bg-bg-tertiary rounded-lg animate-pulse"></div>
        </div>
        <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
          <div class="h-20 bg-bg-tertiary rounded-lg animate-pulse"></div>
          <div class="h-20 bg-bg-tertiary rounded-lg animate-pulse"></div>
          <div class="h-20 bg-bg-tertiary rounded-lg animate-pulse"></div>
          <div class="h-20 bg-bg-tertiary rounded-lg animate-pulse"></div>
        </div>
      </div>

      <!-- Skeleton Rigs Grid -->
      <div class="grid sm:grid-cols-2 lg:grid-cols-3 gap-4">
        <div class="card p-4 h-48 animate-pulse">
          <div class="h-6 w-32 bg-bg-tertiary rounded mb-3"></div>
          <div class="h-4 w-full bg-bg-tertiary rounded mb-2"></div>
          <div class="h-4 w-3/4 bg-bg-tertiary rounded mb-4"></div>
          <div class="mt-auto h-10 bg-bg-tertiary rounded-lg"></div>
        </div>
        <div class="card p-4 h-48 animate-pulse">
          <div class="h-6 w-32 bg-bg-tertiary rounded mb-3"></div>
          <div class="h-4 w-full bg-bg-tertiary rounded mb-2"></div>
          <div class="h-4 w-3/4 bg-bg-tertiary rounded mb-4"></div>
          <div class="mt-auto h-10 bg-bg-tertiary rounded-lg"></div>
        </div>
        <div class="card p-4 h-48 animate-pulse hidden lg:block">
          <div class="h-6 w-32 bg-bg-tertiary rounded mb-3"></div>
          <div class="h-4 w-full bg-bg-tertiary rounded mb-2"></div>
          <div class="h-4 w-3/4 bg-bg-tertiary rounded mb-4"></div>
          <div class="mt-auto h-10 bg-bg-tertiary rounded-lg"></div>
        </div>
      </div>
    </main>
  </div>

  <!-- App cuando está listo -->
  <MainLayout v-else>
    <RouterView />
  </MainLayout>
</template>
