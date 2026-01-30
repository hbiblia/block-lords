<script setup lang="ts">
import { computed } from 'vue';
import { useAuthStore } from '@/stores/auth';
import { useRealtimeStore } from '@/stores/realtime';
import { useMiningStore } from '@/stores/mining';
import NavBar from '@/components/NavBar.vue';
import ResourceBars from '@/components/ResourceBars.vue';

const authStore = useAuthStore();
const realtimeStore = useRealtimeStore();
const miningStore = useMiningStore();

const showResourceBars = computed(() => authStore.isAuthenticated);
</script>

<template>
  <div class="min-h-screen flex flex-col bg-bg-primary">
    <NavBar />

    <!-- Resource Bars (solo si está autenticado) -->
    <div v-if="showResourceBars" class="fixed top-16 left-0 right-0 z-40 glass border-b border-border/30">
      <div class="container mx-auto px-4 py-3">
        <ResourceBars
          :show-consumption="miningStore.isMining"
          :energy-consumption="miningStore.totalEnergyConsumption"
          :internet-consumption="miningStore.totalInternetConsumption"
        />
      </div>
    </div>

    <!-- Main Content -->
    <main class="flex-1 container mx-auto px-4 py-6" :class="{ 'mt-32': showResourceBars, 'mt-16': !showResourceBars }">
      <slot />
    </main>

    <!-- Connection Status -->
    <div
      v-if="authStore.isAuthenticated"
      class="fixed bottom-4 left-4 flex items-center gap-2 px-3 py-2 card text-xs"
    >
      <span
        class="w-2 h-2 rounded-full"
        :class="realtimeStore.isConnected ? 'bg-status-success animate-pulse' : 'bg-status-danger'"
      ></span>
      <span class="text-text-muted">
        {{ realtimeStore.isConnected ? 'Conectado' : 'Desconectado' }}
      </span>
    </div>

    <!-- Footer -->
    <footer class="border-t border-border/30 py-6 text-center">
      <p class="text-text-muted text-sm">Block Lords &copy; 2025</p>
    </footer>
  </div>
</template>
