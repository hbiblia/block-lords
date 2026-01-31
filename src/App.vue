<script setup lang="ts">
import { watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAuthStore } from '@/stores/auth';
import { useRealtimeStore } from '@/stores/realtime';
import MainLayout from '@/layouts/MainLayout.vue';

const { t } = useI18n();
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
  <!-- Loading mientras auth se inicializa -->
  <div v-if="!authStore.initialized" class="min-h-screen bg-bg-primary flex items-center justify-center">
    <div class="text-center">
      <div class="w-16 h-16 mx-auto mb-4 rounded-xl bg-gradient-primary flex items-center justify-center text-3xl animate-pulse">
        ⛏️
      </div>
      <p class="text-text-muted">{{ t('common.loading') }}</p>
    </div>
  </div>

  <!-- App cuando está listo -->
  <MainLayout v-else>
    <RouterView />
  </MainLayout>
</template>
