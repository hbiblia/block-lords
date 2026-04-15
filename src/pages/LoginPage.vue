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
  const pendingRefCode = localStorage.getItem('pendingReferralCode');
  const tourCompleted = localStorage.getItem('miningTourCompleted');
  const lastSeenVersion = localStorage.getItem('lootmine-last-seen-version');
  localStorage.clear();
  if (pendingRefCode) localStorage.setItem('pendingReferralCode', pendingRefCode);
  if (tourCompleted) localStorage.setItem('miningTourCompleted', tourCompleted);
  if (lastSeenVersion) localStorage.setItem('lootmine-last-seen-version', lastSeenVersion);
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
  <div class="login-page">
    <div class="login-card">
      <div class="login-icon">⛏️</div>
      <h1 class="login-title">{{ t('login.title') }}</h1>
      <p class="login-sub">{{ t('login.subtitle') }}</p>

      <div v-if="error" class="login-error">{{ error }}</div>

      <button class="login-google" :disabled="loading" @click="handleGoogleLogin">
        <svg width="20" height="20" viewBox="0 0 24 24">
          <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/>
          <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/>
          <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"/>
          <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"/>
        </svg>
        {{ loading ? t('login.connecting') : t('login.continueGoogle') }}
      </button>

      <p class="login-terms">{{ t('login.terms') }}</p>
    </div>
  </div>
</template>

<style scoped>
@import url('https://fonts.googleapis.com/css2?family=Nunito:wght@400;600;700;800;900&display=swap');

.login-page {
  min-height: 100vh; display: flex; align-items: center; justify-content: center;
  background: #1a1528;
  background-image: radial-gradient(circle, #2d2545 1.5px, transparent 1.5px);
  background-size: 20px 20px;
  padding: 2rem;
  font-family: 'Nunito', 'Trebuchet MS', sans-serif;
}
.login-card {
  background: #1f1833; border: 2px solid #4a3660; border-radius: 16px;
  box-shadow: 4px 4px 0 rgba(74,54,96,0.3); padding: 2.5rem 2rem;
  max-width: 400px; width: 100%; text-align: center;
}
.login-icon { font-size: 3rem; margin-bottom: 0.8rem; }
.login-title { font-size: 1.6rem; font-weight: 900; color: #f0e4ff; margin: 0 0 0.4rem; }
.login-sub { font-size: 0.85rem; color: #8a70a8; margin: 0 0 1.5rem; }
.login-error {
  background: #fff0f0; border: 2px solid #ff7b7b; border-radius: 8px;
  padding: 8px 14px; margin-bottom: 1rem;
  font-size: 0.75rem; font-weight: 700; color: #c04040;
}
.login-google {
  width: 100%; display: flex; align-items: center; justify-content: center; gap: 10px;
  padding: 14px; background: #1f1833; border: 2px solid #5c4578;
  color: #f0e4ff; font-size: 0.9rem; font-weight: 800;
  font-family: 'Nunito', sans-serif; cursor: pointer;
  transition: 0.2s; border-radius: 10px; box-shadow: 2px 2px 0 rgba(74,54,96,0.3);
}
.login-google:hover { border-color: #b088d0; box-shadow: 3px 3px 0 #d8c0ee; transform: translateY(-2px); }
.login-google:disabled { opacity: 0.5; cursor: not-allowed; transform: none; }
.login-terms { font-size: 0.65rem; color: #8a70a8; margin-top: 1.2rem; }
</style>
