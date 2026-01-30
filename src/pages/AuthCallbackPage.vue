<script setup lang="ts">
import { onMounted, ref } from 'vue';
import { useRouter } from 'vue-router';
import { useAuthStore } from '@/stores/auth';
import { useRealtimeStore } from '@/stores/realtime';

const router = useRouter();
const authStore = useAuthStore();
const realtimeStore = useRealtimeStore();

const error = ref('');

onMounted(async () => {
  // Esperar a que Supabase procese el callback
  // El onAuthStateChange en el store maneja la sesión automáticamente

  // Dar tiempo para que se procese la autenticación
  await new Promise(resolve => setTimeout(resolve, 1000));

  // Verificar estado de autenticación
  await authStore.checkAuth();

  if (authStore.user) {
    if (authStore.needsUsername) {
      // Usuario nuevo de OAuth, necesita crear username
      router.push('/setup-username');
    } else if (authStore.isAuthenticated) {
      // Usuario existente con perfil completo
      realtimeStore.connect();
      router.push('/dashboard');
    } else {
      // Tiene user pero no player profile
      router.push('/setup-username');
    }
  } else {
    error.value = 'Error al procesar la autenticación';
  }
});
</script>

<template>
  <div class="max-w-md mx-auto mt-12">
    <div class="arcade-panel text-center">
      <div v-if="!error" class="space-y-4">
        <div class="animate-pulse">
          <div class="text-4xl mb-4">🔐</div>
          <h1 class="text-xl text-arcade-primary">Procesando autenticación...</h1>
          <p class="text-gray-400 text-sm mt-2">Por favor espera un momento</p>
        </div>
      </div>

      <div v-else class="space-y-4">
        <div class="text-4xl mb-4">❌</div>
        <h1 class="text-xl text-arcade-danger">Error de autenticación</h1>
        <p class="text-gray-400 text-sm">{{ error }}</p>
        <RouterLink to="/login" class="arcade-button inline-block mt-4">
          Volver al inicio
        </RouterLink>
      </div>
    </div>
  </div>
</template>
