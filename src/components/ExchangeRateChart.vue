<script setup lang="ts">
import { computed, ref, onMounted, onUnmounted } from 'vue';
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
import { getExchangeRateHistory, getExchangeRates } from '@/utils/api';
import { useI18n } from 'vue-i18n';

ChartJS.register(CategoryScale, LinearScale, PointElement, LineElement, Title, Tooltip, Legend, Filler);

const { t } = useI18n();

const rateHistory = ref<{ rate: number; recorded_at: string }[]>([]);
const currentRate = ref<number | null>(null);
const previousRate = ref<number | null>(null);
const loading = ref(false);
let refreshInterval: number | null = null;

const rateTrend = computed(() => {
  if (currentRate.value === null || previousRate.value === null) return 'neutral';
  if (currentRate.value > previousRate.value) return 'up';
  if (currentRate.value < previousRate.value) return 'down';
  return 'neutral';
});

const rateChangePercent = computed(() => {
  if (!currentRate.value || !previousRate.value) return 0;
  return (currentRate.value - previousRate.value) / previousRate.value * 100;
});

function formatRate(rate: number): string {
  if (rate >= 1) return rate.toFixed(2);
  if (rate >= 0.01) return rate.toFixed(3);
  return rate.toFixed(4);
}

async function loadData() {
  loading.value = true;
  try {
    const [history, rates] = await Promise.all([
      getExchangeRateHistory(50),
      getExchangeRates(),
    ]);
    if (history) rateHistory.value = history;
    if (rates) {
      currentRate.value = rates.crypto_to_gamecoin;
      previousRate.value = rates.crypto_to_gamecoin_previous;
    }
  } catch (e) {
    console.error('Error loading rate chart:', e);
  } finally {
    loading.value = false;
  }
}

// Chart data
const points = computed(() => [...rateHistory.value].reverse());

const timeLabels = computed(() => {
  return points.value.map(p => {
    const d = new Date(p.recorded_at);
    return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  });
});

const rates = computed(() => points.value.map(p => p.rate));

const stats = computed(() => {
  if (rates.value.length < 2) return null;
  const r = rates.value;
  const min = Math.min(...r);
  const max = Math.max(...r);
  const avg = r.reduce((a, b) => a + b, 0) / r.length;
  const first = r[0];
  const last = r[r.length - 1];
  const totalChange = first > 0 ? ((last - first) / first) * 100 : 0;
  return { min, max, avg, totalChange };
});

const trendColor = computed(() => rateTrend.value === 'down' ? '#f87171' : '#4ade80');
const trendColorBg = computed(() => rateTrend.value === 'down' ? 'rgba(248,113,113,0.1)' : 'rgba(74,222,128,0.1)');

const gridColor = 'rgba(63, 63, 92, 0.3)';
const tickColor = '#71717a';
const tooltipBg = '#252640';
const tooltipBorder = '#3f3f5c';

const chartData = computed(() => ({
  labels: timeLabels.value,
  datasets: [
    {
      label: t('mining.rateChart.title'),
      data: rates.value,
      borderColor: trendColor.value,
      backgroundColor: trendColorBg.value,
      fill: true,
      tension: 0.35,
      pointRadius: 1,
      pointHoverRadius: 5,
      pointHoverBackgroundColor: trendColor.value,
      pointHoverBorderColor: '#fff',
      pointHoverBorderWidth: 2,
      borderWidth: 2,
    },
  ],
}));

const chartOptions = computed(() => ({
  responsive: true,
  maintainAspectRatio: false,
  animation: { duration: 400 },
  interaction: { mode: 'index' as const, intersect: false },
  plugins: {
    legend: { display: false },
    tooltip: {
      backgroundColor: tooltipBg,
      titleColor: '#ffffff',
      bodyColor: '#a1a1aa',
      borderColor: tooltipBorder,
      borderWidth: 1,
      displayColors: false,
      callbacks: {
        label: (ctx: any) => `${formatRate(ctx.parsed.y)} 🪙`,
      },
    },
  },
  scales: {
    x: {
      grid: { color: gridColor },
      ticks: { color: tickColor, maxTicksLimit: 6, maxRotation: 0, font: { size: 10 } },
    },
    y: {
      grid: { color: gridColor },
      ticks: {
        color: tickColor,
        font: { size: 10 },
        callback: (value: any) => formatRate(Number(value)),
      },
    },
  },
}));

function refresh() {
  loadData();
}

defineExpose({ refresh });

onMounted(() => {
  loadData();
  // Auto-refresh every 60 seconds
  refreshInterval = setInterval(loadData, 60000) as unknown as number;
});

onUnmounted(() => {
  if (refreshInterval) clearInterval(refreshInterval);
});
</script>

<template>
  <div class="card p-3">
    <!-- Header -->
    <div class="flex items-center justify-between mb-2">
      <h3 class="text-sm font-semibold flex items-center gap-1.5 text-text-muted">
        <span>📈</span> {{ t('mining.rateChart.title') }}
        <span v-if="currentRate !== null" class="font-mono text-status-warning">{{ formatRate(currentRate) }} 🪙</span>
        <span
          v-if="rateTrend !== 'neutral'"
          class="text-[10px] font-bold px-1 py-0.5 rounded"
          :class="rateTrend === 'up' ? 'text-green-400 bg-green-400/10' : 'text-red-400 bg-red-400/10'"
        >{{ rateTrend === 'up' ? '▲' : '▼' }} {{ Math.abs(rateChangePercent).toFixed(1) }}%</span>
      </h3>
      <button @click="loadData" class="text-text-muted hover:text-white transition-colors p-0.5 rounded" :title="t('mining.rateChart.refresh')">
        <span class="text-xs" :class="loading ? 'animate-spin inline-block' : ''">🔄</span>
      </button>
    </div>

    <!-- Loading -->
    <div v-if="loading && rateHistory.length === 0" class="flex items-center justify-center py-6">
      <span class="animate-spin w-5 h-5 border-2 border-accent-primary border-t-transparent rounded-full"></span>
    </div>

    <!-- Chart -->
    <div v-else-if="rateHistory.length >= 2">
      <div class="h-40">
        <Line :data="chartData" :options="chartOptions" />
      </div>

      <!-- Stats row -->
      <div v-if="stats" class="grid grid-cols-4 gap-1.5 mt-2">
        <div class="bg-bg-primary/50 rounded-lg p-1.5 text-center border border-border/30">
          <div class="text-[9px] text-text-muted">Min</div>
          <div class="text-xs font-bold font-mono text-red-400">{{ formatRate(stats.min) }}</div>
        </div>
        <div class="bg-bg-primary/50 rounded-lg p-1.5 text-center border border-border/30">
          <div class="text-[9px] text-text-muted">Max</div>
          <div class="text-xs font-bold font-mono text-green-400">{{ formatRate(stats.max) }}</div>
        </div>
        <div class="bg-bg-primary/50 rounded-lg p-1.5 text-center border border-border/30">
          <div class="text-[9px] text-text-muted">Avg</div>
          <div class="text-xs font-bold font-mono text-accent-primary">{{ formatRate(stats.avg) }}</div>
        </div>
        <div class="bg-bg-primary/50 rounded-lg p-1.5 text-center border border-border/30">
          <div class="text-[9px] text-text-muted">Δ Total</div>
          <div class="text-xs font-bold font-mono" :class="stats.totalChange >= 0 ? 'text-green-400' : 'text-red-400'">
            {{ stats.totalChange >= 0 ? '+' : '' }}{{ stats.totalChange.toFixed(1) }}%
          </div>
        </div>
      </div>

      <!-- Data count -->
      <div class="text-center text-[10px] text-text-muted mt-1.5">
        {{ rateHistory.length }} {{ t('mining.rateChart.blocks') }}
      </div>
    </div>

    <!-- No data -->
    <div v-else class="text-center py-4 text-text-muted text-xs">
      {{ t('mining.rateChart.noData') }}
    </div>
  </div>
</template>
