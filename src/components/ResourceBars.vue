<script setup lang="ts">
import { computed } from 'vue';
import { useAuthStore } from '@/stores/auth';

const authStore = useAuthStore();

const energy = computed(() => authStore.player?.energy ?? 0);
const internet = computed(() => authStore.player?.internet ?? 0);

const energyClass = computed(() => {
  if (energy.value > 50) return 'bg-gradient-to-r from-green-500 to-green-300';
  if (energy.value > 20) return 'bg-gradient-to-r from-yellow-500 to-yellow-300';
  return 'bg-gradient-to-r from-red-500 to-red-300';
});

const internetClass = computed(() => {
  if (internet.value > 50) return 'bg-gradient-to-r from-blue-500 to-blue-300';
  if (internet.value > 20) return 'bg-gradient-to-r from-yellow-500 to-yellow-300';
  return 'bg-gradient-to-r from-red-500 to-red-300';
});
</script>

<template>
  <div class="flex items-center gap-6">
    <!-- Energy Bar -->
    <div class="flex-1 max-w-xs">
      <div class="flex items-center justify-between mb-1 text-xs">
        <span class="flex items-center gap-1">
          <span>⚡</span>
          <span>Energía</span>
        </span>
        <span :class="energy <= 20 ? 'text-arcade-danger animate-pulse' : 'text-gray-400'">
          {{ energy.toFixed(1) }}%
        </span>
      </div>
      <div class="resource-bar">
        <div
          class="resource-bar-fill"
          :class="energyClass"
          :style="{ width: `${energy}%` }"
        ></div>
      </div>
    </div>

    <!-- Internet Bar -->
    <div class="flex-1 max-w-xs">
      <div class="flex items-center justify-between mb-1 text-xs">
        <span class="flex items-center gap-1">
          <span>📡</span>
          <span>Internet</span>
        </span>
        <span :class="internet <= 20 ? 'text-arcade-danger animate-pulse' : 'text-gray-400'">
          {{ internet.toFixed(1) }}%
        </span>
      </div>
      <div class="resource-bar">
        <div
          class="resource-bar-fill"
          :class="internetClass"
          :style="{ width: `${internet}%` }"
        ></div>
      </div>
    </div>

    <!-- Recharge Buttons -->
    <div class="flex items-center gap-2">
      <button
        class="px-3 py-1 text-xs bg-arcade-warning/20 text-arcade-warning rounded hover:bg-arcade-warning/30 transition-colors"
        :disabled="energy >= 100"
      >
        Recargar ⚡
      </button>
      <button
        class="px-3 py-1 text-xs bg-arcade-secondary/20 text-arcade-secondary rounded hover:bg-arcade-secondary/30 transition-colors"
        :disabled="internet >= 100"
      >
        Recargar 📡
      </button>
    </div>
  </div>
</template>
