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

const updateKey = ref(0);
watch(rigSnapshots, () => { updateKey.value++; }, { deep: true });

const snapshots = computed<RigSnapshot[]>(() => {
  // eslint-disable-next-line @typescript-eslint/no-unused-expressions
  updateKey.value;
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

const gridColor = 'rgba(47, 48, 82, 0.4)';
const tooltipBg = '#1a1b2e';
const tooltipBorder = '#3f3f5c';

const baseOptions = {
  responsive: true,
  maintainAspectRatio: false,
  animation: { duration: 300 } as const,
  interaction: { mode: 'index' as const, intersect: false },
  plugins: {
    legend: {
      labels: { color: '#a1a1aa', boxWidth: 10, padding: 10, font: { size: 10, family: "'JetBrains Mono', monospace" } },
    },
    tooltip: {
      backgroundColor: tooltipBg,
      titleColor: '#f59e0b',
      bodyColor: '#a1a1aa',
      borderColor: tooltipBorder,
      borderWidth: 1,
      titleFont: { family: "'JetBrains Mono', monospace" },
      bodyFont: { family: "'JetBrains Mono', monospace" },
    },
  },
  scales: {
    x: {
      grid: { color: gridColor },
      ticks: { color: '#4f4f6f', font: { size: 9, family: "'JetBrains Mono', monospace" }, maxTicksLimit: 8 },
    },
  },
};

const tempConditionData = computed(() => ({
  labels: timeLabels.value,
  datasets: [
    {
      label: 'TEMP °C',
      data: snapshots.value.map(s => Number(s.temperature.toFixed(1))),
      borderColor: '#ef4444',
      backgroundColor: 'rgba(239, 68, 68, 0.06)',
      fill: true,
      tension: 0.3,
      pointRadius: 1,
      borderWidth: 1.5,
      yAxisID: 'y',
    },
    {
      label: 'COND %',
      data: snapshots.value.map(s => Number(s.condition.toFixed(1))),
      borderColor: '#22c55e',
      backgroundColor: 'rgba(34, 197, 94, 0.06)',
      fill: true,
      tension: 0.3,
      pointRadius: 1,
      borderWidth: 1.5,
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
      min: 0, max: 100,
      grid: { color: gridColor },
      ticks: { color: '#ef4444', font: { size: 9, family: "'JetBrains Mono', monospace" } },
      title: { display: true, text: '°C', color: '#ef444480', font: { size: 9 } },
    },
    y1: {
      position: 'right' as const,
      min: 0, max: 100,
      grid: { drawOnChartArea: false },
      ticks: { color: '#22c55e', font: { size: 9, family: "'JetBrains Mono', monospace" } },
      title: { display: true, text: '%', color: '#22c55e80', font: { size: 9 } },
    },
  },
}));

const hashrateResourceData = computed(() => ({
  labels: timeLabels.value,
  datasets: [
    {
      label: 'HASH EFF',
      data: snapshots.value.map(s => Math.round(s.effectiveHashrate)),
      borderColor: '#f59e0b',
      backgroundColor: 'rgba(245, 158, 11, 0.06)',
      fill: true,
      tension: 0.3,
      pointRadius: 1,
      borderWidth: 1.5,
      yAxisID: 'y',
    },
    {
      label: 'HASH BASE',
      data: snapshots.value.map(s => s.baseHashrate),
      borderColor: 'rgba(245, 158, 11, 0.25)',
      borderDash: [4, 4],
      pointRadius: 0,
      borderWidth: 1,
      fill: false,
      yAxisID: 'y',
    },
    {
      label: 'ENERGY',
      data: snapshots.value.map(s => Number(s.energyConsumption.toFixed(1))),
      borderColor: '#22c55e',
      fill: false,
      tension: 0.3,
      pointRadius: 1,
      borderWidth: 1.5,
      yAxisID: 'y1',
    },
    {
      label: 'NET',
      data: snapshots.value.map(s => Number(s.internetConsumption.toFixed(1))),
      borderColor: '#06b6d4',
      fill: false,
      tension: 0.3,
      pointRadius: 1,
      borderWidth: 1.5,
      yAxisID: 'y1',
    },
  ],
}));

const hashrateResourceOptions = computed(() => ({
  ...baseOptions,
  scales: {
    ...baseOptions.scales,
    y: {
      position: 'left' as const,
      min: 0,
      grid: { color: gridColor },
      ticks: { color: '#f59e0b', font: { size: 9, family: "'JetBrains Mono', monospace" } },
      title: { display: true, text: 'H/s', color: '#f59e0b80', font: { size: 9 } },
    },
    y1: {
      position: 'right' as const,
      min: 0,
      grid: { drawOnChartArea: false },
      ticks: { color: '#06b6d4', font: { size: 9, family: "'JetBrains Mono', monospace" } },
      title: { display: true, text: '/tick', color: '#06b6d480', font: { size: 9 } },
    },
  },
}));

function getTempStatus(temp: number) {
  if (temp >= 80) return { color: '#ef4444', label: 'CRITICAL' };
  if (temp >= 60) return { color: '#f59e0b', label: 'ELEVATED' };
  return { color: '#22c55e', label: 'NOMINAL' };
}

function getCondStatus(cond: number) {
  if (cond < 30) return { color: '#ef4444', label: 'FAILING' };
  if (cond < 80) return { color: '#f59e0b', label: 'DEGRADED' };
  return { color: '#22c55e', label: 'SOLID' };
}
</script>

<template>
  <Teleport to="body">
    <div v-if="show && rig" class="rsm-overlay" @click.self="emit('close')">
      <div class="rsm-modal">
        <!-- HUD Corners -->
        <div class="rsm-c rsm-tl"></div>
        <div class="rsm-c rsm-tr"></div>
        <div class="rsm-c rsm-bl"></div>
        <div class="rsm-c rsm-br"></div>
        <div class="rsm-scan"></div>

        <!-- Header -->
        <div class="rsm-header">
          <div class="rsm-header-left">
            <span class="rsm-ind"></span>
            <span class="rsm-tag">NODE_TELEMETRY</span>
          </div>
          <span class="rsm-rig-name">{{ rig.rig.name }}</span>
          <button class="rsm-close" @click="emit('close')">✕</button>
        </div>

        <!-- Status Bar -->
        <div class="rsm-status-bar">
          <div class="rsm-stat">
            <span class="rsm-stat-label">THR.CORE</span>
            <span class="rsm-stat-val" :style="{ color: getTempStatus(rig.temperature ?? 0).color }">{{ (rig.temperature ?? 0).toFixed(0) }}°C</span>
            <span class="rsm-stat-tag" :style="{ color: getTempStatus(rig.temperature ?? 0).color }">{{ getTempStatus(rig.temperature ?? 0).label }}</span>
          </div>
          <div class="rsm-stat">
            <span class="rsm-stat-label">INT.INDEX</span>
            <span class="rsm-stat-val" :style="{ color: getCondStatus(rig.condition).color }">{{ rig.condition.toFixed(0) }}%</span>
            <span class="rsm-stat-tag" :style="{ color: getCondStatus(rig.condition).color }">{{ getCondStatus(rig.condition).label }}</span>
          </div>
          <div class="rsm-stat">
            <span class="rsm-stat-label">HASH.EFF</span>
            <span class="rsm-stat-val rsm-amber">{{ snapshots.length > 0 ? Math.round(snapshots[snapshots.length - 1].effectiveHashrate) : rig.rig.hashrate }} H/s</span>
          </div>
          <div class="rsm-stat">
            <span class="rsm-stat-label">SYS.STATE</span>
            <span class="rsm-stat-val" :style="{ color: rig.is_active && rig.condition > 0 ? '#22c55e' : '#ef4444' }">
              {{ rig.condition <= 0 ? 'DESTROYED' : rig.is_active ? 'ONLINE' : 'OFFLINE' }}
            </span>
          </div>
        </div>

        <!-- Content -->
        <div class="rsm-body">
          <!-- Empty state -->
          <div v-if="!hasData" class="rsm-empty">
            <span class="rsm-empty-icon">◇</span>
            <span class="rsm-empty-title">COLLECTING_DATA</span>
            <span class="rsm-empty-sub">Telemetry will appear after mining ticks (~30s). Keep node online.</span>
            <div class="rsm-empty-count">
              <span class="rsm-ind-sm"></span>
              {{ snapshots.length }} SNAPSHOT{{ snapshots.length !== 1 ? 'S' : '' }}
            </div>
          </div>

          <template v-else>
            <!-- Chart 1: Temp & Condition -->
            <div class="rsm-chart-card">
              <div class="rsm-chart-head">
                <span class="rsm-chart-dot" style="background:#ef4444;"></span>
                <span class="rsm-chart-title">THERMAL & INTEGRITY</span>
              </div>
              <div class="rsm-chart-wrap">
                <Line :data="tempConditionData" :options="tempConditionOptions" />
              </div>
            </div>

            <!-- Chart 2: Hashrate & Resources -->
            <div class="rsm-chart-card">
              <div class="rsm-chart-head">
                <span class="rsm-chart-dot" style="background:#f59e0b;"></span>
                <span class="rsm-chart-title">HASHRATE & CONSUMPTION</span>
              </div>
              <div class="rsm-chart-wrap">
                <Line :data="hashrateResourceData" :options="hashrateResourceOptions" />
              </div>
            </div>

            <!-- Summary Grid -->
            <div v-if="summary" class="rsm-summary">
              <div class="rsm-sum-title">
                <span class="rsm-sum-line"></span>
                <span>SESSION_SUMMARY</span>
                <span class="rsm-sum-line"></span>
              </div>
              <div class="rsm-sum-grid">
                <div class="rsm-sum-card">
                  <span class="rsm-sum-label">AVG_TEMP</span>
                  <span class="rsm-sum-val" :style="{ color: getTempStatus(summary.avgTemperature).color }">{{ summary.avgTemperature.toFixed(1) }}°C</span>
                </div>
                <div class="rsm-sum-card">
                  <span class="rsm-sum-label">PEAK_TEMP</span>
                  <span class="rsm-sum-val" :style="{ color: getTempStatus(summary.maxTemperature).color }">{{ summary.maxTemperature.toFixed(1) }}°C</span>
                </div>
                <div class="rsm-sum-card">
                  <span class="rsm-sum-label">DEGRADATION</span>
                  <span class="rsm-sum-val" :style="{ color: summary.conditionDelta > 0 ? '#ef4444' : '#22c55e' }">{{ summary.conditionDelta > 0 ? '-' : '' }}{{ summary.conditionDelta.toFixed(1) }}%</span>
                </div>
                <div class="rsm-sum-card">
                  <span class="rsm-sum-label">AVG_HASH</span>
                  <span class="rsm-sum-val rsm-amber">{{ Math.round(summary.avgEffectiveHashrate).toLocaleString() }}</span>
                </div>
                <div class="rsm-sum-card">
                  <span class="rsm-sum-label">PEAK_HASH</span>
                  <span class="rsm-sum-val rsm-amber">{{ Math.round(summary.peakEffectiveHashrate).toLocaleString() }}</span>
                </div>
                <div class="rsm-sum-card">
                  <span class="rsm-sum-label">UPTIME</span>
                  <span class="rsm-sum-val" :style="{ color: summary.uptimePercent >= 80 ? '#22c55e' : '#f59e0b' }">{{ summary.uptimePercent.toFixed(0) }}%</span>
                </div>
              </div>
              <div class="rsm-sum-footer">
                {{ summary.totalSnapshots }} SAMPLES // {{ summary.durationMinutes.toFixed(1) }} MIN
              </div>
            </div>
          </template>
        </div>
      </div>
    </div>
  </Teleport>
</template>

<style scoped>
.rsm-overlay {
  position: fixed; inset: 0; z-index: 50; display: flex; align-items: center; justify-content: center;
  background: rgba(0,0,0,0.75); backdrop-filter: blur(2px); padding: 1rem;
}

.rsm-modal {
  position: relative; width: 100%; max-width: 720px; height: 85vh; display: flex; flex-direction: column;
  background: linear-gradient(135deg, rgba(20,21,40,0.98) 0%, rgba(30,31,54,0.96) 100%);
  border: 1px solid #2f3052; overflow: hidden;
  animation: rsm-enter 0.3s cubic-bezier(0.16,1,0.3,1);
}
.rsm-modal::before {
  content: ''; position: absolute; inset: 0; pointer-events: none;
  background: repeating-linear-gradient(0deg, transparent, transparent 3px, rgba(255,255,255,0.006) 3px, rgba(255,255,255,0.006) 4px);
}
@keyframes rsm-enter { from { opacity: 0; transform: scale(0.95); } to { opacity: 1; transform: scale(1); } }

/* HUD Corners */
.rsm-c { position: absolute; width: 12px; height: 12px; pointer-events: none; z-index: 3; }
.rsm-tl { top: 0; left: 0; border-top: 2px solid #f59e0b; border-left: 2px solid #f59e0b; }
.rsm-tr { top: 0; right: 0; border-top: 2px solid #f59e0b; border-right: 2px solid #f59e0b; }
.rsm-bl { bottom: 0; left: 0; border-bottom: 2px solid #f59e0b; border-left: 2px solid #f59e0b; }
.rsm-br { bottom: 0; right: 0; border-bottom: 2px solid #f59e0b; border-right: 2px solid #f59e0b; }

/* Scanline */
.rsm-scan {
  position: absolute; top: 0; left: -100%; width: 100%; height: 100%; pointer-events: none; z-index: 1;
  background: linear-gradient(90deg, transparent 0%, rgba(245,158,11,0.02) 45%, rgba(245,158,11,0.05) 50%, rgba(245,158,11,0.02) 55%, transparent 100%);
  animation: rsm-scanmove 5s linear infinite;
}
@keyframes rsm-scanmove { 0% { left: -100%; } 100% { left: 100%; } }

/* Header */
.rsm-header {
  display: flex; align-items: center; gap: 8px; padding: 0.7rem 0.8rem;
  border-bottom: 1px solid #2f3052; position: relative; z-index: 2; flex-shrink: 0;
  background: linear-gradient(180deg, rgba(26,27,46,0.9) 0%, transparent 100%);
}
.rsm-header-left { display: flex; align-items: center; gap: 6px; }
.rsm-ind { width: 6px; height: 6px; border-radius: 50%; background: #22c55e; box-shadow: 0 0 6px rgba(34,197,94,0.6); animation: rsm-pulse 2s infinite; }
@keyframes rsm-pulse { 0%,100% { opacity: 1; } 50% { opacity: 0.3; } }
.rsm-tag { font-size: 0.45rem; font-weight: 900; color: #71717a; letter-spacing: 2.5px; }
.rsm-rig-name { flex: 1; font-size: 0.85rem; font-weight: 900; color: #e5e7eb; letter-spacing: 1px; }
.rsm-close {
  background: transparent; border: 1px solid #2f3052; color: #71717a; width: 28px; height: 28px;
  display: flex; align-items: center; justify-content: center; cursor: pointer; font-size: 0.7rem;
  transition: all 0.2s; font-family: inherit;
}
.rsm-close:hover { border-color: #ef4444; color: #ef4444; }

/* Status Bar */
.rsm-status-bar {
  display: grid; grid-template-columns: repeat(4, 1fr); gap: 1px; flex-shrink: 0;
  border-bottom: 1px solid #2f3052; background: #2f3052; position: relative; z-index: 2;
}
.rsm-stat {
  display: flex; flex-direction: column; align-items: center; gap: 2px; padding: 8px 4px;
  background: rgba(26,27,46,0.95);
}
.rsm-stat-label { font-size: 0.4rem; font-weight: 900; color: #4f4f6f; letter-spacing: 2px; }
.rsm-stat-val { font-size: 0.8rem; font-weight: 900; font-family: 'JetBrains Mono', monospace; }
.rsm-stat-tag { font-size: 0.35rem; font-weight: 900; letter-spacing: 1.5px; }
.rsm-amber { color: #f59e0b; text-shadow: 0 0 6px rgba(245,158,11,0.3); }

/* Body */
.rsm-body {
  flex: 1; overflow-y: auto; padding: 0.8rem; display: flex; flex-direction: column; gap: 0.7rem;
  position: relative; z-index: 2;
}
.rsm-body::-webkit-scrollbar { width: 3px; }
.rsm-body::-webkit-scrollbar-thumb { background: #3f3f5c; }

/* Empty state */
.rsm-empty {
  flex: 1; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 8px;
}
.rsm-empty-icon { font-size: 2rem; color: #4f4f6f; animation: rsm-pulse 3s infinite; }
.rsm-empty-title { font-size: 0.7rem; font-weight: 900; color: #a1a1aa; letter-spacing: 3px; }
.rsm-empty-sub { font-size: 0.5rem; color: #71717a; text-align: center; max-width: 280px; letter-spacing: 0.5px; }
.rsm-empty-count { display: flex; align-items: center; gap: 6px; margin-top: 8px; font-size: 0.45rem; font-weight: 900; color: #4f4f6f; letter-spacing: 1.5px; }
.rsm-ind-sm { width: 4px; height: 4px; border-radius: 50%; background: #22c55e; box-shadow: 0 0 4px rgba(34,197,94,0.5); animation: rsm-pulse 2s infinite; }

/* Chart cards */
.rsm-chart-card {
  background: rgba(26,27,46,0.6); border: 1px solid #2f3052; padding: 0.6rem;
  border-left: 2px solid #f59e0b30; position: relative;
}
.rsm-chart-head { display: flex; align-items: center; gap: 6px; margin-bottom: 6px; }
.rsm-chart-dot { width: 5px; height: 5px; border-radius: 50%; flex-shrink: 0; }
.rsm-chart-title { font-size: 0.45rem; font-weight: 900; color: #71717a; letter-spacing: 2px; }
.rsm-chart-wrap { height: 160px; position: relative; }

/* Summary */
.rsm-summary { margin-top: 0.25rem; }
.rsm-sum-title {
  display: flex; align-items: center; gap: 8px; margin-bottom: 0.5rem;
  font-size: 0.4rem; font-weight: 900; color: #71717a; letter-spacing: 2.5px;
}
.rsm-sum-line { flex: 1; height: 1px; background: linear-gradient(90deg, transparent, #3f3f5c, transparent); }
.rsm-sum-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 4px; }
.rsm-sum-card {
  background: rgba(26,27,46,0.8); border: 1px solid #2f3052; padding: 8px 6px;
  display: flex; flex-direction: column; align-items: center; gap: 3px;
  border-left: 2px solid #f59e0b20;
}
.rsm-sum-label { font-size: 0.4rem; font-weight: 900; color: #4f4f6f; letter-spacing: 2px; }
.rsm-sum-val { font-size: 0.85rem; font-weight: 900; font-family: 'JetBrains Mono', monospace; }
.rsm-sum-footer { text-align: center; font-size: 0.4rem; font-weight: 900; color: #4f4f6f; letter-spacing: 2px; margin-top: 8px; }

/* Mobile */
@media (max-width: 600px) {
  .rsm-modal { height: 95vh; max-width: none; }
  .rsm-status-bar { grid-template-columns: repeat(2, 1fr); }
  .rsm-sum-grid { grid-template-columns: repeat(2, 1fr); }
  .rsm-chart-wrap { height: 130px; }
  .rsm-rig-name { font-size: 0.7rem; }
}
</style>
