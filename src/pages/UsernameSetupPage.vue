<script setup lang="ts">
import { ref, onMounted, computed } from 'vue';
import { useRouter } from 'vue-router';
import { useAuthStore } from '@/stores/auth';
import { useRealtimeStore } from '@/stores/realtime';

const router = useRouter();
const authStore = useAuthStore();
const realtimeStore = useRealtimeStore();

const username = ref('');
const loading = ref(false);
const error = ref('');
const step = ref(1);
const showContent = ref(false);

// Preview del avatar basado en el nombre
const avatarLetter = computed(() => {
  return username.value.trim() ? username.value.charAt(0).toUpperCase() : '?';
});

// Validación en tiempo real
const validation = computed(() => {
  const name = username.value.trim();
  if (!name) return { valid: false, message: '' };
  if (name.length < 3) return { valid: false, message: 'Mínimo 3 caracteres' };
  if (name.length > 20) return { valid: false, message: 'Máximo 20 caracteres' };
  if (!/^[a-zA-Z0-9_]+$/.test(name)) return { valid: false, message: 'Solo letras, números y _' };
  return { valid: true, message: '¡Nombre válido!' };
});

onMounted(() => {
  if (!authStore.user) {
    router.push('/login');
    return;
  }

  if (authStore.isAuthenticated) {
    router.push('/mining');
    return;
  }

  setTimeout(() => {
    showContent.value = true;
  }, 100);
});

async function handleSubmit() {
  if (!validation.value.valid) {
    error.value = validation.value.message || 'Nombre inválido';
    return;
  }

  error.value = '';
  loading.value = true;
  step.value = 2;

  try {
    // Simular proceso de creación
    await new Promise(resolve => setTimeout(resolve, 1500));

    const success = await authStore.completeProfile(username.value);

    if (success) {
      step.value = 3;
      await new Promise(resolve => setTimeout(resolve, 1000));
      realtimeStore.connect();
      router.push('/welcome');
    } else {
      step.value = 1;
      error.value = authStore.error ?? 'Error al crear perfil';
    }
  } catch (e) {
    step.value = 1;
    error.value = 'Error inesperado. Intenta de nuevo.';
  } finally {
    loading.value = false;
  }
}
</script>

<template>
  <div class="min-h-[80vh] flex items-center justify-center py-12">
    <div
      class="w-full max-w-md mx-auto px-4 transition-all duration-500"
      :class="showContent ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-4'"
    >
      <!-- Step 1: Crear personaje -->
      <div v-if="step === 1" class="card">
        <div class="text-center mb-8">
          <!-- Avatar preview -->
          <div class="relative inline-block mb-6">
            <div
              class="w-24 h-24 rounded-2xl bg-gradient-primary flex items-center justify-center text-4xl font-bold text-white shadow-glow transition-all duration-300"
              :class="{ 'scale-110': username.length > 0 }"
            >
              {{ avatarLetter }}
            </div>
            <div class="absolute -bottom-1 -right-1 w-8 h-8 rounded-lg bg-status-success flex items-center justify-center text-sm">
              ⛏️
            </div>
          </div>

          <h1 class="text-2xl font-display font-bold mb-2">
            <span class="gradient-text">Crea tu Minero</span>
          </h1>
          <p class="text-text-muted text-sm">
            Elige un nombre único para tu personaje
          </p>
        </div>

        <form @submit.prevent="handleSubmit" class="space-y-6">
          <div>
            <label class="block text-sm text-text-secondary mb-2 font-medium">
              Nombre de Minero
            </label>
            <input
              v-model="username"
              type="text"
              class="input text-center text-lg font-medium"
              placeholder="TuNombreÉpico"
              maxlength="20"
              required
              :disabled="loading"
              autocomplete="off"
            />

            <!-- Validación visual -->
            <div class="flex items-center justify-center gap-2 mt-3 h-6">
              <template v-if="username.trim()">
                <span
                  class="text-xs font-medium transition-colors"
                  :class="validation.valid ? 'text-status-success' : 'text-status-warning'"
                >
                  {{ validation.valid ? '✓' : '!' }} {{ validation.message }}
                </span>
              </template>
              <template v-else>
                <span class="text-xs text-text-muted">3-20 caracteres • letras, números, _</span>
              </template>
            </div>
          </div>

          <!-- Bonificaciones de nuevo jugador -->
          <div class="bg-bg-secondary rounded-xl p-4 border border-border/50">
            <div class="text-xs text-text-muted mb-3 text-center">🎁 Bonus de bienvenida</div>
            <div class="grid grid-cols-3 gap-3 text-center">
              <div>
                <div class="text-lg font-bold text-status-warning">100</div>
                <div class="text-xs text-text-muted">🪙 GameCoin</div>
              </div>
              <div>
                <div class="text-lg font-bold text-accent-primary">1</div>
                <div class="text-xs text-text-muted">⛏️ Rig Básico</div>
              </div>
              <div>
                <div class="text-lg font-bold text-status-success">100%</div>
                <div class="text-xs text-text-muted">⚡ Energía</div>
              </div>
            </div>
          </div>

          <div v-if="error" class="p-3 rounded-lg bg-status-danger/10 border border-status-danger/30 text-status-danger text-sm text-center">
            {{ error }}
          </div>

          <button
            type="submit"
            class="btn-primary w-full py-4 text-lg relative overflow-hidden group"
            :disabled="loading || !validation.valid"
          >
            <span class="relative z-10">🚀 Comenzar Aventura</span>
            <div class="absolute inset-0 bg-white/20 transform -skew-x-12 -translate-x-full group-hover:translate-x-full transition-transform duration-500"></div>
          </button>
        </form>

        <div class="text-center mt-6">
          <button
            @click="authStore.logout()"
            class="text-text-muted text-sm hover:text-white transition-colors"
          >
            ← Usar otra cuenta
          </button>
        </div>
      </div>

      <!-- Step 2: Creando perfil -->
      <div v-else-if="step === 2" class="text-center">
        <div class="relative mb-8">
          <div class="w-28 h-28 mx-auto rounded-2xl bg-gradient-primary flex items-center justify-center text-5xl font-bold text-white animate-pulse shadow-glow">
            {{ avatarLetter }}
          </div>
          <div class="absolute inset-0 flex items-center justify-center">
            <div class="w-36 h-36 border-2 border-accent-primary/30 rounded-full animate-spin" style="animation-duration: 3s;"></div>
          </div>
        </div>

        <h2 class="text-2xl font-display font-bold mb-2">
          <span class="gradient-text">Creando tu minero...</span>
        </h2>
        <p class="text-text-muted">{{ username }}</p>

        <div class="mt-8 space-y-3 text-sm text-text-secondary">
          <div class="flex items-center justify-center gap-2 animate-pulse">
            <span class="text-status-success">✓</span> Registrando en la blockchain
          </div>
          <div class="flex items-center justify-center gap-2 animate-pulse" style="animation-delay: 0.3s;">
            <span class="text-status-success">✓</span> Asignando recursos iniciales
          </div>
          <div class="flex items-center justify-center gap-2 animate-pulse" style="animation-delay: 0.6s;">
            <span class="text-status-warning">⏳</span> Configurando estación de minería
          </div>
        </div>
      </div>

      <!-- Step 3: Éxito -->
      <div v-else-if="step === 3" class="text-center">
        <div class="w-28 h-28 mx-auto rounded-2xl bg-status-success flex items-center justify-center text-5xl mb-6 animate-bounce">
          🎉
        </div>

        <h2 class="text-2xl font-display font-bold mb-2">
          <span class="gradient-text">¡Minero creado!</span>
        </h2>
        <p class="text-text-secondary">Bienvenido a Block Lords, {{ username }}</p>
      </div>
    </div>
  </div>
</template>
