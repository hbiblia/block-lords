<script setup lang="ts">
import { onMounted, ref } from 'vue';
import { useRouter } from 'vue-router';
import { useAuthStore } from '@/stores/auth';
import { useRealtimeStore } from '@/stores/realtime';

const router = useRouter();
const authStore = useAuthStore();
const realtimeStore = useRealtimeStore();

const error = ref('');
const loadingStep = ref(0);
const loadingMessages = [
  'Conectando con la blockchain...',
  'Verificando identidad...',
  'Sincronizando datos...',
  'Preparando tu estación de minería...',
];

onMounted(async () => {
  // Animación de carga progresiva
  const stepInterval = setInterval(() => {
    if (loadingStep.value < loadingMessages.length - 1) {
      loadingStep.value++;
    }
  }, 600);

  await new Promise(resolve => setTimeout(resolve, 800));
  await authStore.checkAuth();

  clearInterval(stepInterval);

  if (authStore.user) {
    loadingStep.value = loadingMessages.length - 1;
    await new Promise(resolve => setTimeout(resolve, 500));

    if (authStore.needsUsername) {
      router.push('/setup-username');
    } else if (authStore.isAuthenticated) {
      realtimeStore.connect();
      router.push('/welcome');
    } else {
      router.push('/setup-username');
    }
  } else {
    error.value = 'Error al procesar la autenticación';
  }
});
</script>

<template>
  <div class="min-h-[80vh] flex items-center justify-center">
    <div class="text-center">
      <div v-if="!error">
        <!-- Logo animado -->
        <div class="relative mb-8">
          <div class="w-24 h-24 mx-auto rounded-2xl bg-gradient-primary flex items-center justify-center text-5xl animate-pulse">
            ⛏️
          </div>
          <!-- Partículas/efectos alrededor -->
          <div class="absolute inset-0 flex items-center justify-center">
            <div class="w-32 h-32 border-2 border-accent-primary/30 rounded-full animate-ping"></div>
          </div>
          <div class="absolute inset-0 flex items-center justify-center">
            <div class="w-40 h-40 border border-accent-secondary/20 rounded-full animate-[ping_2s_ease-in-out_infinite]"></div>
          </div>
        </div>

        <!-- Título -->
        <h1 class="text-3xl font-display font-bold mb-2">
          <span class="gradient-text">BLOCK LORDS</span>
        </h1>

        <!-- Barra de progreso -->
        <div class="w-64 mx-auto mb-4">
          <div class="progress-bar h-2">
            <div
              class="progress-bar-fill transition-all duration-500"
              style="background: linear-gradient(90deg, #8b5cf6 0%, #ec4899 100%);"
              :style="{ width: `${((loadingStep + 1) / loadingMessages.length) * 100}%` }"
            ></div>
          </div>
        </div>

        <!-- Mensaje de carga -->
        <p class="text-text-secondary text-sm h-6 transition-all">
          {{ loadingMessages[loadingStep] }}
        </p>

        <!-- Indicadores de paso -->
        <div class="flex justify-center gap-2 mt-4">
          <div
            v-for="(_, index) in loadingMessages"
            :key="index"
            class="w-2 h-2 rounded-full transition-all duration-300"
            :class="index <= loadingStep ? 'bg-accent-primary' : 'bg-bg-tertiary'"
          ></div>
        </div>
      </div>

      <!-- Error -->
      <div v-else class="card max-w-sm mx-auto">
        <div class="w-16 h-16 mx-auto rounded-2xl bg-status-danger/20 flex items-center justify-center text-3xl mb-4">
          ❌
        </div>
        <h1 class="text-xl font-semibold text-status-danger mb-2">Error de Conexión</h1>
        <p class="text-text-muted text-sm mb-6">{{ error }}</p>
        <RouterLink to="/login" class="btn-primary inline-block">
          Reintentar
        </RouterLink>
      </div>
    </div>
  </div>
</template>
