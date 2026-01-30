<script setup lang="ts">
import { computed, ref, watch, onUnmounted } from 'vue';
import { useAuthStore } from '@/stores/auth';

const props = defineProps<{
  showConsumption?: boolean;
  energyConsumption?: number;
  internetConsumption?: number;
}>();

const authStore = useAuthStore();

const energy = computed(() => authStore.player?.energy ?? 100);
const internet = computed(() => authStore.player?.internet ?? 100);

// Simulación visual de consumo
const displayEnergy = ref(energy.value);
const displayInternet = ref(internet.value);
const isConsuming = ref(false);
const consumptionInterval = ref<number | null>(null);

// Sincronizar con valores reales
watch(energy, (val) => {
  displayEnergy.value = val;
});

watch(internet, (val) => {
  displayInternet.value = val;
});

// Simular consumo visual cuando hay consumo activo
watch(() => props.energyConsumption, (consumption) => {
  if (consumption && consumption > 0) {
    startConsumptionAnimation();
  } else {
    stopConsumptionAnimation();
  }
}, { immediate: true });

function startConsumptionAnimation() {
  if (consumptionInterval.value) return;
  isConsuming.value = true;

  consumptionInterval.value = window.setInterval(() => {
    // Pequeñas fluctuaciones visuales para mostrar actividad
    if (props.energyConsumption && props.energyConsumption > 0) {
      const energyDrain = props.energyConsumption / 600; // Por tick visual (100ms)
      displayEnergy.value = Math.max(0, displayEnergy.value - energyDrain);
    }
    if (props.internetConsumption && props.internetConsumption > 0) {
      const internetDrain = props.internetConsumption / 600;
      displayInternet.value = Math.max(0, displayInternet.value - internetDrain);
    }
  }, 100);
}

function stopConsumptionAnimation() {
  if (consumptionInterval.value) {
    clearInterval(consumptionInterval.value);
    consumptionInterval.value = null;
  }
  isConsuming.value = false;
  displayEnergy.value = energy.value;
  displayInternet.value = internet.value;
}

onUnmounted(() => {
  stopConsumptionAnimation();
});

// Estados de alerta
const energyStatus = computed(() => {
  if (displayEnergy.value <= 10) return 'critical';
  if (displayEnergy.value <= 25) return 'warning';
  return 'normal';
});

const internetStatus = computed(() => {
  if (displayInternet.value <= 10) return 'critical';
  if (displayInternet.value <= 25) return 'warning';
  return 'normal';
});
</script>

<template>
  <div class="flex items-center gap-4">
    <!-- Energy Bar -->
    <div class="flex-1 max-w-xs">
      <div class="flex items-center justify-between mb-1.5 text-xs">
        <span class="flex items-center gap-1.5">
          <span
            class="text-lg"
            :class="{ 'animate-pulse': isConsuming && energyConsumption }"
          >⚡</span>
          <span class="text-text-muted">Energía</span>
          <span
            v-if="isConsuming && energyConsumption"
            class="text-status-danger text-[10px] animate-pulse"
          >
            -{{ energyConsumption?.toFixed(1) }}/tick
          </span>
        </span>
        <span
          class="font-mono font-bold"
          :class="{
            'text-status-danger animate-pulse': energyStatus === 'critical',
            'text-status-warning': energyStatus !== 'critical'
          }"
        >
          {{ displayEnergy.toFixed(1) }}%
        </span>
      </div>
      <div class="relative">
        <div
          class="h-4 rounded-full overflow-hidden"
          :class="{
            'bg-status-danger/20': energyStatus === 'critical',
            'bg-status-warning/20': energyStatus === 'warning',
            'bg-bg-tertiary': energyStatus === 'normal'
          }"
        >
          <div
            class="h-full rounded-full transition-all duration-200 relative overflow-hidden"
            :class="{
              'bg-status-danger': energyStatus === 'critical',
              'bg-gradient-to-r from-status-warning to-yellow-400': energyStatus !== 'critical'
            }"
            :style="{ width: `${displayEnergy}%` }"
          >
            <!-- Efecto de brillo cuando consume -->
            <div
              v-if="isConsuming && energyConsumption"
              class="absolute inset-0 bg-gradient-to-r from-transparent via-white/30 to-transparent animate-shimmer"
            ></div>
          </div>
        </div>
        <!-- Indicador de consumo activo -->
        <div
          v-if="isConsuming && energyConsumption"
          class="absolute -right-1 top-1/2 -translate-y-1/2 w-2 h-2 rounded-full bg-status-danger animate-ping"
        ></div>
      </div>
      <!-- Alerta de bajo -->
      <div
        v-if="energyStatus === 'critical'"
        class="text-[10px] text-status-danger mt-1 animate-pulse"
      >
        ⚠️ ¡Energía crítica!
      </div>
    </div>

    <!-- Internet Bar -->
    <div class="flex-1 max-w-xs">
      <div class="flex items-center justify-between mb-1.5 text-xs">
        <span class="flex items-center gap-1.5">
          <span
            class="text-lg"
            :class="{ 'animate-pulse': isConsuming && internetConsumption }"
          >📡</span>
          <span class="text-text-muted">Internet</span>
          <span
            v-if="isConsuming && internetConsumption"
            class="text-status-danger text-[10px] animate-pulse"
          >
            -{{ internetConsumption?.toFixed(1) }}/tick
          </span>
        </span>
        <span
          class="font-mono font-bold"
          :class="{
            'text-status-danger animate-pulse': internetStatus === 'critical',
            'text-status-warning': internetStatus === 'warning',
            'text-accent-tertiary': internetStatus === 'normal'
          }"
        >
          {{ displayInternet.toFixed(1) }}%
        </span>
      </div>
      <div class="relative">
        <div
          class="h-4 rounded-full overflow-hidden"
          :class="{
            'bg-status-danger/20': internetStatus === 'critical',
            'bg-status-warning/20': internetStatus === 'warning',
            'bg-bg-tertiary': internetStatus === 'normal'
          }"
        >
          <div
            class="h-full rounded-full transition-all duration-200 relative overflow-hidden"
            :class="{
              'bg-status-danger': internetStatus === 'critical',
              'bg-gradient-to-r from-accent-tertiary to-cyan-400': internetStatus !== 'critical'
            }"
            :style="{ width: `${displayInternet}%` }"
          >
            <!-- Efecto de brillo cuando consume -->
            <div
              v-if="isConsuming && internetConsumption"
              class="absolute inset-0 bg-gradient-to-r from-transparent via-white/30 to-transparent animate-shimmer"
            ></div>
          </div>
        </div>
        <!-- Indicador de consumo activo -->
        <div
          v-if="isConsuming && internetConsumption"
          class="absolute -right-1 top-1/2 -translate-y-1/2 w-2 h-2 rounded-full bg-status-danger animate-ping"
        ></div>
      </div>
      <!-- Alerta de bajo -->
      <div
        v-if="internetStatus === 'critical'"
        class="text-[10px] text-status-danger mt-1 animate-pulse"
      >
        ⚠️ ¡Internet crítico!
      </div>
    </div>

    <!-- Recharge Buttons -->
    <div class="flex items-center gap-2">
      <button
        class="px-3 py-2 text-xs font-medium rounded-xl transition-all relative overflow-hidden group"
        :class="energyStatus === 'critical'
          ? 'bg-status-danger text-white animate-pulse'
          : 'bg-status-warning/20 text-status-warning hover:bg-status-warning/30'"
        :disabled="displayEnergy >= 100"
      >
        <span class="relative z-10">+ ⚡</span>
        <div v-if="energyStatus === 'critical'" class="absolute inset-0 bg-white/20 animate-ping"></div>
      </button>
      <button
        class="px-3 py-2 text-xs font-medium rounded-xl transition-all relative overflow-hidden"
        :class="internetStatus === 'critical'
          ? 'bg-status-danger text-white animate-pulse'
          : 'bg-accent-tertiary/20 text-accent-tertiary hover:bg-accent-tertiary/30'"
        :disabled="displayInternet >= 100"
      >
        <span class="relative z-10">+ 📡</span>
        <div v-if="internetStatus === 'critical'" class="absolute inset-0 bg-white/20 animate-ping"></div>
      </button>
    </div>
  </div>
</template>

<style scoped>
@keyframes shimmer {
  0% { transform: translateX(-100%); }
  100% { transform: translateX(100%); }
}

.animate-shimmer {
  animation: shimmer 1s ease-in-out infinite;
}
</style>
