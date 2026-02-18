import { ref } from 'vue';
import { useMiningStore } from '@/stores/mining';

export interface RigSnapshot {
  timestamp: number;
  temperature: number;
  condition: number;
  effectiveHashrate: number;
  baseHashrate: number;
  energyConsumption: number;
  internetConsumption: number;
  isActive: boolean;
}

export interface RigStatsSummary {
  avgTemperature: number;
  maxTemperature: number;
  avgCondition: number;
  conditionDelta: number;
  avgEffectiveHashrate: number;
  peakEffectiveHashrate: number;
  avgEnergy: number;
  totalSnapshots: number;
  durationMinutes: number;
  uptimePercent: number;
}

const MAX_SNAPSHOTS = 120; // ~1 hour at 30s ticks
const STORAGE_KEY = 'lootmine_rig_stats';

// --- localStorage persistence ---
function loadSnapshots(): Map<string, RigSnapshot[]> {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (raw) {
      const obj = JSON.parse(raw) as Record<string, RigSnapshot[]>;
      return new Map(Object.entries(obj));
    }
  } catch (e) {
    console.error('Error loading rig stats cache:', e);
  }
  return new Map();
}

function saveSnapshots(data: Map<string, RigSnapshot[]>) {
  try {
    const obj: Record<string, RigSnapshot[]> = {};
    data.forEach((snaps, id) => { obj[id] = snaps; });
    localStorage.setItem(STORAGE_KEY, JSON.stringify(obj));
  } catch (e) {
    console.error('Error saving rig stats cache:', e);
  }
}

// Module-level singleton: shared across all component instances, persists via localStorage
const rigSnapshots = ref<Map<string, RigSnapshot[]>>(loadSnapshots());

export function useRigStats() {
  const miningStore = useMiningStore();

  function captureSnapshots() {
    const now = Date.now();
    for (const rig of miningStore.rigs) {
      // If rig has no durability, clear its snapshots and skip
      if (rig.condition <= 0) {
        if (rigSnapshots.value.has(rig.id)) {
          rigSnapshots.value.delete(rig.id);
        }
        continue;
      }

      const snapshots = rigSnapshots.value.get(rig.id) ?? [];

      snapshots.push({
        timestamp: now,
        temperature: rig.temperature ?? 0,
        condition: rig.condition ?? 100,
        effectiveHashrate: rig.is_active && rig.condition > 0
          ? miningStore.getRigEffectiveHashrate(rig)
          : 0,
        baseHashrate: rig.rig.hashrate,
        energyConsumption: rig.is_active
          ? miningStore.getRigEffectivePower(rig)
          : 0,
        internetConsumption: rig.is_active
          ? rig.rig.internet_consumption * (1 - (rig.efficiency_bonus ?? 0) / 100)
          : 0,
        isActive: rig.is_active,
      });

      if (snapshots.length > MAX_SNAPSHOTS) {
        snapshots.splice(0, snapshots.length - MAX_SNAPSHOTS);
      }

      rigSnapshots.value.set(rig.id, snapshots);
    }

    // Persist to localStorage after each capture
    saveSnapshots(rigSnapshots.value);
  }

  function getSnapshots(rigId: string): RigSnapshot[] {
    return rigSnapshots.value.get(rigId) ?? [];
  }

  function getSummary(rigId: string): RigStatsSummary {
    const snaps = getSnapshots(rigId);
    if (snaps.length === 0) {
      return {
        avgTemperature: 0, maxTemperature: 0,
        avgCondition: 0, conditionDelta: 0,
        avgEffectiveHashrate: 0, peakEffectiveHashrate: 0,
        avgEnergy: 0, totalSnapshots: 0,
        durationMinutes: 0, uptimePercent: 0,
      };
    }

    const temps = snaps.map(s => s.temperature);
    const conditions = snaps.map(s => s.condition);
    const hashrates = snaps.map(s => s.effectiveHashrate);
    const energies = snaps.map(s => s.energyConsumption);
    const activeCount = snaps.filter(s => s.isActive).length;

    const sum = (arr: number[]) => arr.reduce((a, b) => a + b, 0);

    return {
      avgTemperature: sum(temps) / snaps.length,
      maxTemperature: Math.max(...temps),
      avgCondition: sum(conditions) / snaps.length,
      conditionDelta: snaps[0].condition - snaps[snaps.length - 1].condition,
      avgEffectiveHashrate: sum(hashrates) / snaps.length,
      peakEffectiveHashrate: Math.max(...hashrates),
      avgEnergy: sum(energies) / snaps.length,
      totalSnapshots: snaps.length,
      durationMinutes: (snaps[snaps.length - 1].timestamp - snaps[0].timestamp) / 60000,
      uptimePercent: (activeCount / snaps.length) * 100,
    };
  }

  return {
    rigSnapshots,
    captureSnapshots,
    getSnapshots,
    getSummary,
  };
}
