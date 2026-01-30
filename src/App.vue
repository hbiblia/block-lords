<script setup lang="ts">
import { watch } from 'vue';
import { useAuthStore } from '@/stores/auth';
import { useRealtimeStore } from '@/stores/realtime';
import MainLayout from '@/layouts/MainLayout.vue';

const authStore = useAuthStore();
const realtimeStore = useRealtimeStore();

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
  <MainLayout>
    <RouterView />
  </MainLayout>
</template>
