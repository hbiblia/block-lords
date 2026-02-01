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
  <Transition name="fade">
  <div v-if="!authStore.initialized" key="skeleton" class="min-h-screen bg-bg-primary absolute inset-0 z-50">
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
      <!-- Header (igual al real) -->
      <div class="flex items-center justify-between mb-6">
        <h1 class="text-2xl font-display font-bold">
          <span class="gradient-text">Mining</span>
        </h1>
        <div class="flex items-center gap-3">
          <span class="badge badge-warning">0 rigs activos</span>
          <div class="flex items-center gap-1 px-1 py-1 bg-bg-secondary/50 rounded-lg">
            <button class="px-3 py-1.5 text-sm font-medium rounded-md bg-accent-primary/20 text-accent-primary flex items-center gap-1.5">
              <span>🛒</span>
              <span class="hidden sm:inline">Market</span>
            </button>
            <button class="px-3 py-1.5 text-sm font-medium rounded-md bg-purple-500/20 text-purple-400 flex items-center gap-1.5">
              <span>💱</span>
              <span class="hidden sm:inline">Exchange</span>
            </button>
            <button class="px-3 py-1.5 text-sm font-medium rounded-md bg-bg-tertiary flex items-center gap-1.5">
              <span>🎒</span>
              <span class="hidden sm:inline">Inventory</span>
            </button>
          </div>
        </div>
      </div>

      <!-- Mining Status Panel -->
      <div class="card relative overflow-hidden mb-6">
        <div class="relative z-10">
          <!-- Header -->
          <div class="flex items-center justify-between mb-6">
            <div class="flex items-center gap-3">
              <div class="w-14 h-14 rounded-xl bg-bg-tertiary flex items-center justify-center text-3xl">
                ⛏️
              </div>
              <div>
                <h2 class="text-lg font-semibold">Centro de Minería</h2>
                <p class="text-sm text-text-muted">Rigs inactivos</p>
              </div>
            </div>
            <div class="text-right">
              <div class="text-3xl font-bold font-mono text-text-muted">0</div>
              <div class="text-xs text-text-muted">Hashrate efectivo</div>
            </div>
          </div>

          <!-- Progress Bar -->
          <div class="mb-4">
            <div class="flex justify-between text-sm mb-2">
              <span class="text-text-muted">Progreso de hash</span>
              <span class="font-mono text-accent-primary">0 hashes</span>
            </div>
            <div class="h-4 bg-bg-tertiary rounded-full overflow-hidden"></div>
          </div>

          <!-- Stats Grid -->
          <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
            <div class="bg-accent-primary/10 border border-accent-primary/30 rounded-xl p-3 text-center relative">
              <div class="absolute top-1 right-1.5 text-[10px] text-accent-primary/70">👤</div>
              <div class="text-lg font-bold text-status-warning">0.00%</div>
              <div class="text-[10px] text-text-muted">Probabilidad</div>
            </div>
            <div class="bg-bg-secondary rounded-xl p-3 text-center relative">
              <div class="absolute top-1 right-1.5 text-[10px] text-text-muted/50">🌐</div>
              <div class="text-lg font-bold text-accent-tertiary">1,000</div>
              <div class="text-[10px] text-text-muted">Dificultad</div>
            </div>
            <div class="bg-bg-secondary rounded-xl p-3 text-center relative">
              <div class="absolute top-1 right-1.5 text-[10px] text-text-muted/50">🌐</div>
              <div class="text-lg font-bold text-accent-primary">25</div>
              <div class="text-[10px] text-text-muted">Mineros</div>
            </div>
            <div class="bg-bg-secondary rounded-xl p-3 text-center relative">
              <div class="absolute top-1 right-1.5 text-[10px] text-text-muted/50">🌐</div>
              <div class="text-lg font-bold text-status-success">#0</div>
              <div class="text-[10px] text-text-muted">Último bloque</div>
            </div>
          </div>
        </div>
      </div>

      <!-- Grid: Rigs + Sidebar -->
      <div class="grid lg:grid-cols-3 gap-6">
        <!-- Rigs Column -->
        <div class="lg:col-span-2 space-y-4">
          <h2 class="text-lg font-semibold flex items-center gap-2">
            <span>🖥️</span> Tus Rigs
            <span class="text-sm font-normal px-2 py-0.5 rounded-full bg-accent-primary/20 text-accent-primary">0/1</span>
          </h2>

          <!-- Empty slot card -->
          <div class="card p-4 border-dashed border-2 border-border/50">
            <div class="flex items-center justify-center py-8">
              <div class="text-center">
                <div class="w-16 h-16 mx-auto mb-4 rounded-xl bg-bg-tertiary flex items-center justify-center text-3xl">
                  ➕
                </div>
                <p class="text-text-muted mb-3">Slot disponible</p>
                <button class="btn-primary text-sm px-4 py-2">
                  🛒 Comprar Rig
                </button>
              </div>
            </div>
          </div>
        </div>

        <!-- Sidebar -->
        <div class="space-y-4">
          <h2 class="text-lg font-semibold flex items-center gap-2">
            <span>📦</span> Bloques Recientes
          </h2>
          <div class="card p-4">
            <p class="text-center text-text-muted py-4">Sin bloques recientes</p>
          </div>
        </div>
      </div>
    </main>
  </div>

  </Transition>

  <!-- App siempre renderizado (skeleton lo cubre inicialmente) -->
  <MainLayout>
    <RouterView />
  </MainLayout>
</template>

<style>
/* Skeleton overlay fades out to reveal app underneath */
.fade-leave-active {
  transition: opacity 0.3s ease;
}

.fade-leave-to {
  opacity: 0;
}
</style>
