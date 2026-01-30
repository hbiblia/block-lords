<script setup lang="ts">
import { onMounted } from 'vue';
import { useAuthStore } from '@/stores/auth';
import { useRealtimeStore } from '@/stores/realtime';
import MainLayout from '@/layouts/MainLayout.vue';

const authStore = useAuthStore();
const realtimeStore = useRealtimeStore();

onMounted(async () => {
  await authStore.checkAuth();
  if (authStore.isAuthenticated) {
    realtimeStore.connect();
  }
});
</script>

<template>
  <MainLayout>
    <RouterView />
  </MainLayout>
</template>
