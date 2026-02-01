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
      <!-- Header -->
      <div class="flex items-center justify-between mb-6">
        <div class="h-8 w-48 bg-bg-tertiary rounded animate-pulse"></div>
        <div class="flex items-center gap-3">
          <div class="h-7 w-24 bg-bg-tertiary rounded-full animate-pulse"></div>
          <div class="flex items-center gap-1 px-1 py-1 bg-bg-secondary/50 rounded-lg">
            <div class="h-9 w-20 bg-accent-primary/20 rounded-md animate-pulse"></div>
            <div class="h-9 w-20 bg-purple-500/20 rounded-md animate-pulse"></div>
            <div class="h-9 w-16 bg-bg-tertiary rounded-md animate-pulse"></div>
          </div>
        </div>
      </div>

      <!-- Mining Status Panel -->
      <div class="card relative overflow-hidden mb-6">
        <div class="absolute inset-0 bg-gradient-to-r from-accent-primary/5 via-accent-secondary/5 to-accent-primary/5 animate-pulse"></div>
        <div class="relative z-10">
          <!-- Header -->
          <div class="flex items-center justify-between mb-6">
            <div class="flex items-center gap-3">
              <div class="w-14 h-14 rounded-xl bg-gradient-primary flex items-center justify-center text-3xl animate-pulse">
                ⛏️
              </div>
              <div>
                <div class="h-5 w-36 bg-bg-tertiary rounded animate-pulse mb-2"></div>
                <div class="h-4 w-28 bg-bg-tertiary rounded animate-pulse"></div>
              </div>
            </div>
            <div class="text-right">
              <div class="h-9 w-32 bg-bg-tertiary rounded animate-pulse mb-1"></div>
              <div class="h-3 w-24 bg-bg-tertiary rounded animate-pulse ml-auto"></div>
            </div>
          </div>

          <!-- Progress Bar -->
          <div class="mb-4">
            <div class="flex justify-between text-sm mb-2">
              <div class="h-4 w-24 bg-bg-tertiary rounded animate-pulse"></div>
              <div class="h-4 w-20 bg-bg-tertiary rounded animate-pulse"></div>
            </div>
            <div class="h-4 bg-bg-tertiary rounded-full overflow-hidden">
              <div class="h-full w-1/3 bg-gradient-to-r from-accent-primary to-accent-secondary rounded-full animate-pulse"></div>
            </div>
          </div>

          <!-- Stats Grid -->
          <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
            <div class="bg-accent-primary/10 border border-accent-primary/30 rounded-xl p-3 text-center">
              <div class="h-6 w-16 bg-bg-tertiary rounded animate-pulse mx-auto mb-1"></div>
              <div class="h-3 w-20 bg-bg-tertiary rounded animate-pulse mx-auto"></div>
            </div>
            <div class="bg-bg-secondary rounded-xl p-3 text-center">
              <div class="h-6 w-16 bg-bg-tertiary rounded animate-pulse mx-auto mb-1"></div>
              <div class="h-3 w-16 bg-bg-tertiary rounded animate-pulse mx-auto"></div>
            </div>
            <div class="bg-bg-secondary rounded-xl p-3 text-center">
              <div class="h-6 w-12 bg-bg-tertiary rounded animate-pulse mx-auto mb-1"></div>
              <div class="h-3 w-14 bg-bg-tertiary rounded animate-pulse mx-auto"></div>
            </div>
            <div class="bg-bg-secondary rounded-xl p-3 text-center">
              <div class="h-6 w-16 bg-bg-tertiary rounded animate-pulse mx-auto mb-1"></div>
              <div class="h-3 w-18 bg-bg-tertiary rounded animate-pulse mx-auto"></div>
            </div>
          </div>
        </div>
      </div>

      <!-- Grid: Rigs + Sidebar -->
      <div class="grid lg:grid-cols-3 gap-6">
        <!-- Rigs Column -->
        <div class="lg:col-span-2 space-y-4">
          <div class="flex items-center gap-2 mb-2">
            <div class="h-6 w-32 bg-bg-tertiary rounded animate-pulse"></div>
            <div class="h-5 w-12 bg-accent-primary/20 rounded-full animate-pulse"></div>
          </div>

          <!-- Rig Cards -->
          <div class="card p-4">
            <div class="flex items-start justify-between mb-4">
              <div class="flex items-center gap-3">
                <div class="w-12 h-12 bg-bg-tertiary rounded-lg animate-pulse"></div>
                <div>
                  <div class="h-5 w-28 bg-bg-tertiary rounded animate-pulse mb-2"></div>
                  <div class="h-4 w-20 bg-bg-tertiary rounded animate-pulse"></div>
                </div>
              </div>
              <div class="h-10 w-24 bg-accent-primary/20 rounded-lg animate-pulse"></div>
            </div>
            <div class="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-4">
              <div class="h-16 bg-bg-tertiary rounded-lg animate-pulse"></div>
              <div class="h-16 bg-bg-tertiary rounded-lg animate-pulse"></div>
              <div class="h-16 bg-bg-tertiary rounded-lg animate-pulse"></div>
              <div class="h-16 bg-bg-tertiary rounded-lg animate-pulse"></div>
            </div>
            <div class="h-2 bg-bg-tertiary rounded-full animate-pulse"></div>
          </div>

          <!-- Empty slot card -->
          <div class="card p-4 border-dashed border-2 border-border/50">
            <div class="flex items-center justify-center py-6">
              <div class="text-center">
                <div class="h-12 w-12 bg-bg-tertiary rounded-lg animate-pulse mx-auto mb-3"></div>
                <div class="h-4 w-32 bg-bg-tertiary rounded animate-pulse mx-auto mb-2"></div>
                <div class="h-8 w-28 bg-accent-primary/20 rounded-lg animate-pulse mx-auto"></div>
              </div>
            </div>
          </div>
        </div>

        <!-- Sidebar -->
        <div class="space-y-4">
          <div class="h-6 w-32 bg-bg-tertiary rounded animate-pulse mb-2"></div>
          <div class="card p-4">
            <div class="space-y-3">
              <div class="h-12 bg-bg-tertiary rounded-lg animate-pulse"></div>
              <div class="h-12 bg-bg-tertiary rounded-lg animate-pulse"></div>
              <div class="h-12 bg-bg-tertiary rounded-lg animate-pulse"></div>
            </div>
          </div>
        </div>
      </div>
    </main>
  </div>

  <!-- App cuando está listo -->
  <MainLayout v-else>
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
</style>
