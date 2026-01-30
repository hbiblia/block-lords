<script setup lang="ts">
import { computed } from 'vue';
import { useAuthStore } from '@/stores/auth';

const authStore = useAuthStore();

const energy = computed(() => authStore.player?.energy ?? 0);
const internet = computed(() => authStore.player?.internet ?? 0);
</script>

<template>
  <div class="flex items-center gap-6">
    <!-- Energy Bar -->
    <div class="flex-1 max-w-xs">
      <div class="flex items-center justify-between mb-1.5 text-xs">
        <span class="flex items-center gap-1.5 text-text-muted">
          <span>⚡</span>
          <span>Energía</span>
        </span>
        <span
          class="font-medium"
          :class="energy <= 20 ? 'text-status-danger animate-pulse' : 'text-status-warning'"
        >
          {{ energy.toFixed(1) }}%
        </span>
      </div>
      <div class="progress-bar progress-energy">
        <div
          class="progress-bar-fill"
          :style="{ width: `${energy}%` }"
        ></div>
      </div>
    </div>

    <!-- Internet Bar -->
    <div class="flex-1 max-w-xs">
      <div class="flex items-center justify-between mb-1.5 text-xs">
        <span class="flex items-center gap-1.5 text-text-muted">
          <span>📡</span>
          <span>Internet</span>
        </span>
        <span
          class="font-medium"
          :class="internet <= 20 ? 'text-status-danger animate-pulse' : 'text-accent-tertiary'"
        >
          {{ internet.toFixed(1) }}%
        </span>
      </div>
      <div class="progress-bar progress-internet">
        <div
          class="progress-bar-fill"
          :style="{ width: `${internet}%` }"
        ></div>
      </div>
    </div>

    <!-- Recharge Buttons -->
    <div class="flex items-center gap-2">
      <button
        class="px-3 py-1.5 text-xs font-medium bg-status-warning/20 text-status-warning rounded-lg hover:bg-status-warning/30 transition-colors disabled:opacity-50"
        :disabled="energy >= 100"
      >
        Recargar ⚡
      </button>
      <button
        class="px-3 py-1.5 text-xs font-medium bg-accent-tertiary/20 text-accent-tertiary rounded-lg hover:bg-accent-tertiary/30 transition-colors disabled:opacity-50"
        :disabled="internet >= 100"
      >
        Recargar 📡
      </button>
    </div>
  </div>
</template>
