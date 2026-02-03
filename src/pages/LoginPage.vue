<script setup lang="ts">
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAuthStore } from '@/stores/auth';

const { t } = useI18n();
const authStore = useAuthStore();

const loading = ref(false);
const error = ref('');

async function handleGoogleLogin() {
  error.value = '';
  loading.value = true;

  // Preservar código de referido antes de limpiar
  const pendingRefCode = localStorage.getItem('pendingReferralCode');

  // Limpiar localStorage al iniciar sesión para evitar datos obsoletos de sesiones anteriores
  localStorage.clear();

  // Restaurar código de referido si existía
  if (pendingRefCode) {
    localStorage.setItem('pendingReferralCode', pendingRefCode);
  }

  try {
    const success = await authStore.loginWithGoogle();

    if (!success) {
      error.value = authStore.error ?? t('login.googleError');
      loading.value = false;
    }
  } catch (e) {
    error.value = t('login.unexpectedError');
    loading.value = false;
  }
}
</script>

<template>
  <div class="max-w-md mx-auto mt-12">
    <div class="card">
      <div class="text-center mb-8">
        <div class="w-16 h-16 mx-auto rounded-2xl bg-gradient-primary flex items-center justify-center text-3xl mb-4">
          ⛏️
        </div>
        <h1 class="text-2xl font-display font-bold gradient-text">{{ t('login.title') }}</h1>
        <p class="text-text-muted mt-2">
          {{ t('login.subtitle') }}
        </p>
      </div>

      <div class="space-y-4">
        <div v-if="error" class="p-3 rounded-lg bg-status-danger/10 border border-status-danger/30 text-status-danger text-sm text-center">
          {{ error }}
        </div>

        <button
          @click="handleGoogleLogin"
          class="w-full flex items-center justify-center gap-3 bg-white text-gray-800 font-medium py-3.5 px-4 rounded-xl hover:bg-gray-100 transition-all hover:scale-[1.02] active:scale-[0.98] disabled:opacity-50 disabled:cursor-not-allowed disabled:hover:scale-100"
          :disabled="loading"
        >
          <svg class="w-5 h-5" viewBox="0 0 24 24">
            <path
              fill="#4285F4"
              d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"
            />
            <path
              fill="#34A853"
              d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"
            />
            <path
              fill="#FBBC05"
              d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"
            />
            <path
              fill="#EA4335"
              d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"
            />
          </svg>
          {{ loading ? t('login.connecting') : t('login.continueGoogle') }}
        </button>

        <div class="text-center text-text-muted text-xs mt-6">
          {{ t('login.terms') }}
        </div>
      </div>
    </div>
  </div>
</template>
