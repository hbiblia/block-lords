<script setup lang="ts">
import { computed, watch, ref } from 'vue';
import { Line } from 'vue-chartjs';
import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Title,
  Tooltip,
  Legend,
  Filler,
} from 'chart.js';
import { useRigStats, type RigSnapshot } from '@/composables/useRigStats';
import { useI18n } from 'vue-i18n';

ChartJS.register(CategoryScale, LinearScale, PointElement, LineElement, Title, Tooltip, Legend, Filler);

interface RigData {
  id: string;
  is_active: boolean;
  condition: number;
  temperature: number;
  activated_at: string | null;
  rig: {
    id: string;
    name: string;
    hashrate: number;
    power_consumption: number;
    internet_consumption: number;
    tier: string;
  };
}

const props = defineProps<{
  show: boolean;
  rig: RigData | null;
}>();

const emit = defineEmits<{
  close: [];
}>();

const { t } = useI18n();
const { getSnapshots, getSummary, rigSnapshots } = useRigStats();

// Force reactivity when rigSnapshots changes
const updateKey = ref(0);
watch(rigSnapshots, () => { updateKey.value++; }, { deep: true });

const snapshots = computed<RigSnapshot[]>(() => {
  // eslint-disable-next-line @typescript-eslint/no-unused-expressions
  updateKey.value; // dependency for reactivity
  if (!props.rig) return [];
  return getSnapshots(props.rig.id);
});

const summary = computed(() => {
  // eslint-disable-next-line @typescript-eslint/no-unused-expressions
  updateKey.value;
  if (!props.rig) return null;
  return getSummary(props.rig.id);
});

const hasData = computed(() => snapshots.value.length >= 2);

// Time labels relative to first snapshot
const timeLabels = computed(() => {
  const snaps = snapshots.value;
  if (snaps.length === 0) return [];
  const first = snaps[0].timestamp;
  return snaps.map(s => {
    const diffSec = Math.floor((s.timestamp - first) / 1000);
    const mins = Math.floor(diffSec / 60);
    const secs = diffSec % 60;
    return `${mins}:${secs.toString().padStart(2, '0')}`;
  });
});

// Chart theme defaults
const gridColor = 'rgba(63, 63, 92, 0.3)';
const tickColor = '#71717a';
const tooltipBg = '#252640';
const tooltipBorder = '#3f3f5c';

const baseOptions = {
  responsive: true,
  maintainAspectRatio: false,
  animation: { duration: 300 } as const,
  interaction: { mode: 'index' as const, intersect: false },
  plugins: {
    legend: {
      labels: { color: '#a1a1aa', boxWidth: 12, padding: 12 },
    },
    tooltip: {
      backgroundColor: tooltipBg,
      titleColor: '#ffffff',
      bodyColor: '#a1a1aa',
      borderColor: tooltipBorder,
      borderWidth: 1,
    },
  },
  scales: {
    x: {
      grid: { color: gridColor },
      ticks: { color: tickColor, maxTicksLimit: 8 },
    },
  },
};

// Chart 1: Temperature & Condition
const tempConditionData = computed(() => ({
  labels: timeLabels.value,
  datasets: [
    {
      label: '🌡️ Temperatura (°C)',
      data: snapshots.value.map(s => Number(s.temperature.toFixed(1))),
      borderColor: '#ef4444',
      backgroundColor: 'rgba(239, 68, 68, 0.08)',
      fill: true,
      tension: 0.3,
      pointRadius: 2,
      borderWidth: 2,
      yAxisID: 'y',
    },
    {
      label: '🔧 Condición (%)',
      data: snapshots.value.map(s => Number(s.condition.toFixed(1))),
      borderColor: '#22c55e',
      backgroundColor: 'rgba(34, 197, 94, 0.08)',
      fill: true,
      tension: 0.3,
      pointRadius: 2,
      borderWidth: 2,
      yAxisID: 'y1',
    },
  ],
}));

const tempConditionOptions = computed(() => ({
  ...baseOptions,
  scales: {
    ...baseOptions.scales,
    y: {
      position: 'left' as const,
      min: 0,
      max: 100,
      grid: { color: gridColor },
      ticks: { color: '#ef4444' },
      title: { display: true, text: '°C', color: '#ef4444' },
    },
    y1: {
      position: 'right' as const,
      min: 0,
      max: 100,
      grid: { drawOnChartArea: false },
      ticks: { color: '#22c55e' },
      title: { display: true, text: '%', color: '#22c55e' },
    },
  },
}));

// Chart 2: Hashrate
const hashrateData = computed(() => ({
  labels: timeLabels.value,
  datasets: [
    {
      label: '⚡ Hashrate Efectivo',
      data: snapshots.value.map(s => Math.round(s.effectiveHashrate)),
      borderColor: '#f59e0b',
      backgroundColor: 'rgba(245, 158, 11, 0.08)',
      fill: true,
      tension: 0.3,
      pointRadius: 2,
      borderWidth: 2,
    },
    {
      label: '📊 Hashrate Base',
      data: snapshots.value.map(s => s.baseHashrate),
      borderColor: 'rgba(245, 158, 11, 0.3)',
      borderDash: [5, 5],
      pointRadius: 0,
      borderWidth: 1,
      fill: false,
    },
  ],
}));

const hashrateOptions = computed(() => ({
  ...baseOptions,
  scales: {
    ...baseOptions.scales,
    y: {
      min: 0,
      grid: { color: gridColor },
      ticks: { color: tickColor },
      title: { display: true, text: 'H/s', color: '#f59e0b' },
    },
  },
}));

// Chart 3: Energy & Internet
const resourceData = computed(() => ({
  labels: timeLabels.value,
  datasets: [
    {
      label: '⚡ Energía/tick',
      data: snapshots.value.map(s => Number(s.energyConsumption.toFixed(1))),
      borderColor: '#eab308',
      backgroundColor: 'rgba(234, 179, 8, 0.08)',
      fill: true,
      tension: 0.3,
      pointRadius: 2,
      borderWidth: 2,
    },
    {
      label: '📡 Internet/tick',
      data: snapshots.value.map(s => Number(s.internetConsumption.toFixed(1))),
      borderColor: '#3b82f6',
      backgroundColor: 'rgba(59, 130, 246, 0.08)',
      fill: true,
      tension: 0.3,
      pointRadius: 2,
      borderWidth: 2,
    },
  ],
}));

const resourceOptions = computed(() => ({
  ...baseOptions,
  scales: {
    ...baseOptions.scales,
    y: {
      min: 0,
      grid: { color: gridColor },
      ticks: { color: tickColor },
      title: { display: true, text: '/tick', color: tickColor },
    },
  },
}));

function getTempColor(temp: number): string {
  if (temp >= 80) return 'text-status-danger';
  if (temp >= 60) return 'text-status-warning';
  if (temp >= 40) return 'text-yellow-400';
  return 'text-status-success';
}

function getConditionColor(cond: number): string {
  if (cond < 30) return 'text-status-danger';
  if (cond < 80) return 'text-status-warning';
  return 'text-status-success';
}
</script>

<template>
  <Teleport to="body">
    <div v-if="show && rig" class="fixed inset-0 z-50 flex items-center justify-center p-4">
      <!-- Overlay -->
      <div class="absolute inset-0 bg-black/70 backdrop-blur-sm" @click="emit('close')"></div>

      <!-- Modal -->
      <div class="relative w-full max-w-2xl lg:max-w-3xl h-[85vh] flex flex-col bg-bg-secondary border border-border rounded-xl overflow-hidden">
        <!-- Header -->
        <div class="flex items-center justify-between p-4 border-b border-border shrink-0">
          <div>
            <h2 class="text-lg font-semibold flex items-center gap-2">
              <span>📊</span>
              <span>{{ t('mining.stats') || 'Rig Stats' }}</span>
            </h2>
            <p class="text-sm text-text-muted">{{ rig.rig.name }}</p>
          </div>
          <button @click="emit('close')"
            class="p-2 hover:bg-bg-tertiary rounded-lg transition-colors text-text-muted hover:text-white">
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        <!-- Current Status Bar -->
        <div class="grid grid-cols-4 gap-2 p-3 border-b border-border/50 bg-bg-primary/50 shrink-0">
          <div class="text-center">
            <div class="text-[10px] text-text-muted">Temp</div>
            <div class="text-sm font-bold font-mono" :class="getTempColor(rig.temperature ?? 0)">
              {{ (rig.temperature ?? 0).toFixed(0) }}°C
            </div>
          </div>
          <div class="text-center">
            <div class="text-[10px] text-text-muted">Condición</div>
            <div class="text-sm font-bold font-mono" :class="getConditionColor(rig.condition)">
              {{ rig.condition.toFixed(0) }}%
            </div>
          </div>
          <div class="text-center">
            <div class="text-[10px] text-text-muted">Hashrate</div>
            <div class="text-sm font-bold font-mono text-accent-primary">
              {{ rig.rig.hashrate }} H/s
            </div>
          </div>
          <div class="text-center">
            <div class="text-[10px] text-text-muted">Estado</div>
            <div class="text-sm font-bold" :class="rig.is_active && rig.condition > 0 ? 'text-status-success' : 'text-text-muted'">
              {{ rig.condition <= 0 ? 'Roto' : rig.is_active ? 'Activo' : 'Apagado' }}
            </div>
          </div>
        </div>

        <!-- Content -->
        <div class="flex-1 overflow-y-auto p-4 space-y-5">
          <!-- Empty state -->
          <div v-if="!hasData" class="flex flex-col items-center justify-center h-full text-center px-4">
            <div class="text-4xl mb-3">📈</div>
            <h3 class="text-lg font-semibold mb-2">Recolectando datos...</h3>
            <p class="text-sm text-text-muted max-w-sm">
              Las estadísticas aparecerán después de algunos ticks de minería (cada 30s).
              Mantené el rig encendido para ver las tendencias.
            </p>
            <div class="mt-4 flex items-center gap-2 text-xs text-text-muted">
              <div class="w-2 h-2 rounded-full bg-status-success animate-pulse"></div>
              {{ snapshots.length }} snapshot{{ snapshots.length !== 1 ? 's' : '' }} recolectado{{ snapshots.length !== 1 ? 's' : '' }}
            </div>
          </div>

          <template v-else>
            <!-- Chart 1: Temperature & Condition -->
            <div class="bg-bg-primary/50 rounded-xl p-3 border border-border/30">
              <h3 class="text-sm font-semibold mb-2 text-text-secondary">🌡️ Temperatura & Condición</h3>
              <div class="h-48">
                <Line :data="tempConditionData" :options="tempConditionOptions" />
              </div>
            </div>

            <!-- Chart 2: Hashrate -->
            <div class="bg-bg-primary/50 rounded-xl p-3 border border-border/30">
              <h3 class="text-sm font-semibold mb-2 text-text-secondary">⚡ Hashrate</h3>
              <div class="h-48">
                <Line :data="hashrateData" :options="hashrateOptions" />
              </div>
            </div>

            <!-- Chart 3: Resources -->
            <div class="bg-bg-primary/50 rounded-xl p-3 border border-border/30">
              <h3 class="text-sm font-semibold mb-2 text-text-secondary">🔋 Consumo de Recursos</h3>
              <div class="h-48">
                <Line :data="resourceData" :options="resourceOptions" />
              </div>
            </div>

            <!-- Summary Stats -->
            <div v-if="summary" class="grid grid-cols-2 sm:grid-cols-3 gap-3">
              <div class="bg-bg-primary/50 rounded-xl p-3 text-center border border-border/30">
                <div class="text-[10px] text-text-muted mb-1">Temp Promedio</div>
                <div class="text-lg font-bold font-mono" :class="getTempColor(summary.avgTemperature)">
                  {{ summary.avgTemperature.toFixed(1) }}°C
                </div>
              </div>
              <div class="bg-bg-primary/50 rounded-xl p-3 text-center border border-border/30">
                <div class="text-[10px] text-text-muted mb-1">Temp Máxima</div>
                <div class="text-lg font-bold font-mono" :class="getTempColor(summary.maxTemperature)">
                  {{ summary.maxTemperature.toFixed(1) }}°C
                </div>
              </div>
              <div class="bg-bg-primary/50 rounded-xl p-3 text-center border border-border/30">
                <div class="text-[10px] text-text-muted mb-1">Degradación</div>
                <div class="text-lg font-bold font-mono" :class="summary.conditionDelta > 0 ? 'text-status-danger' : 'text-status-success'">
                  {{ summary.conditionDelta > 0 ? '-' : '' }}{{ summary.conditionDelta.toFixed(1) }}%
                </div>
              </div>
              <div class="bg-bg-primary/50 rounded-xl p-3 text-center border border-border/30">
                <div class="text-[10px] text-text-muted mb-1">Hashrate Prom.</div>
                <div class="text-lg font-bold font-mono text-accent-primary">
                  {{ Math.round(summary.avgEffectiveHashrate).toLocaleString() }}
                </div>
              </div>
              <div class="bg-bg-primary/50 rounded-xl p-3 text-center border border-border/30">
                <div class="text-[10px] text-text-muted mb-1">Hashrate Pico</div>
                <div class="text-lg font-bold font-mono text-accent-primary">
                  {{ Math.round(summary.peakEffectiveHashrate).toLocaleString() }}
                </div>
              </div>
              <div class="bg-bg-primary/50 rounded-xl p-3 text-center border border-border/30">
                <div class="text-[10px] text-text-muted mb-1">Uptime</div>
                <div class="text-lg font-bold font-mono" :class="summary.uptimePercent >= 80 ? 'text-status-success' : 'text-status-warning'">
                  {{ summary.uptimePercent.toFixed(0) }}%
                </div>
              </div>
            </div>

            <!-- Collection info -->
            <div v-if="summary" class="text-center text-xs text-text-muted pb-2">
              {{ summary.totalSnapshots }} muestras en {{ summary.durationMinutes.toFixed(1) }} min
            </div>
          </template>
        </div>
      </div>
    </div>
  </Teleport>
</template>
