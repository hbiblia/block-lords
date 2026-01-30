<script setup lang="ts">
import { ref, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useAuthStore } from '@/stores/auth';
import { useRealtimeStore } from '@/stores/realtime';

const router = useRouter();
const authStore = useAuthStore();
const realtimeStore = useRealtimeStore();

const username = ref('');
const loading = ref(false);
const error = ref('');

onMounted(() => {
  // Si no hay usuario autenticado, redirigir al login
  if (!authStore.user) {
    router.push('/login');
    return;
  }

  // Si ya tiene perfil completo, ir al dashboard
  if (authStore.isAuthenticated) {
    router.push('/dashboard');
  }
});

async function handleSubmit() {
  if (!username.value.trim()) {
    error.value = 'El nombre de usuario es requerido';
    return;
  }

  if (username.value.length < 3) {
    error.value = 'El nombre debe tener al menos 3 caracteres';
    return;
  }

  if (username.value.length > 20) {
    error.value = 'El nombre no puede tener más de 20 caracteres';
    return;
  }

  if (!/^[a-zA-Z0-9_]+$/.test(username.value)) {
    error.value = 'Solo letras, números y guiones bajos permitidos';
    return;
  }

  error.value = '';
  loading.value = true;

  try {
    const success = await authStore.completeProfile(username.value);

    if (success) {
      realtimeStore.connect();
      router.push('/dashboard');
    } else {
      error.value = authStore.error ?? 'Error al crear perfil';
    }
  } catch (e) {
    error.value = 'Error inesperado. Intenta de nuevo.';
  } finally {
    loading.value = false;
  }
}
</script>

<template>
  <div class="max-w-md mx-auto mt-12">
    <div class="arcade-panel">
      <div class="text-center mb-6">
        <div class="text-4xl mb-4">🎮</div>
        <h1 class="text-2xl text-arcade-primary">¡Bienvenido!</h1>
        <p class="text-gray-400 text-sm mt-2">
          Elige tu nombre de minero para comenzar
        </p>
      </div>

      <form @submit.prevent="handleSubmit" class="space-y-4">
        <div>
          <label class="block text-sm text-gray-400 mb-1">Nombre de usuario</label>
          <input
            v-model="username"
            type="text"
            class="arcade-input"
            placeholder="TuNombreDeMinero"
            maxlength="20"
            required
            :disabled="loading"
          />
          <p class="text-xs text-gray-500 mt-1">
            3-20 caracteres. Solo letras, números y guiones bajos.
          </p>
        </div>

        <div v-if="error" class="text-arcade-danger text-sm text-center">
          {{ error }}
        </div>

        <button
          type="submit"
          class="arcade-button w-full"
          :disabled="loading || !username.trim()"
        >
          {{ loading ? 'Creando perfil...' : 'Comenzar a minar' }}
        </button>
      </form>

      <div class="text-center mt-6">
        <button
          @click="authStore.logout()"
          class="text-gray-500 text-sm hover:text-gray-400"
        >
          Usar otra cuenta
        </button>
      </div>
    </div>
  </div>
</template>
