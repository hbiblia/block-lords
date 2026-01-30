<script setup lang="ts">
import { computed } from 'vue';
import { useAuthStore } from '@/stores/auth';
import { useRealtimeStore } from '@/stores/realtime';
import NavBar from '@/components/NavBar.vue';
import ResourceBars from '@/components/ResourceBars.vue';

const authStore = useAuthStore();
const realtimeStore = useRealtimeStore();

const showResourceBars = computed(() => authStore.isAuthenticated);
</script>

<template>
  <div class="min-h-screen flex flex-col">
    <NavBar />

    <!-- Resource Bars (solo si está autenticado) -->
    <div v-if="showResourceBars" class="fixed top-16 left-0 right-0 z-40 bg-arcade-bg/90 backdrop-blur-sm border-b border-arcade-border">
      <div class="container mx-auto px-4 py-2">
        <ResourceBars />
      </div>
    </div>

    <!-- Main Content -->
    <main class="flex-1 container mx-auto px-4 py-6" :class="{ 'mt-24': showResourceBars, 'mt-16': !showResourceBars }">
      <slot />
    </main>

    <!-- Connection Status -->
    <div
      v-if="authStore.isAuthenticated"
      class="fixed bottom-4 left-4 flex items-center gap-2 text-xs"
    >
      <span
        class="w-2 h-2 rounded-full"
        :class="realtimeStore.isConnected ? 'bg-arcade-success animate-pulse' : 'bg-arcade-danger'"
      ></span>
      <span class="text-gray-400">
        {{ realtimeStore.isConnected ? 'Conectado' : 'Desconectado' }}
      </span>
    </div>

    <!-- Footer -->
    <footer class="border-t border-arcade-border py-4 text-center text-gray-500 text-sm">
      <p>Crypto Arcade MMO &copy; 2024 - Economía Zero-Sum</p>
    </footer>
  </div>
</template>
