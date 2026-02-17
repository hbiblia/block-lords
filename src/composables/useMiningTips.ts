import { computed, ref } from 'vue';
import { useAuthStore } from '@/stores/auth';
import { useMiningStore } from '@/stores/mining';

export type TipSeverity = 'warning' | 'danger' | 'info';

export interface MiningTip {
  id: string;
  severity: TipSeverity;
  icon: string;
  messageKey: string;
  messageParams?: Record<string, unknown>;
  actionKey?: string;
  actionEvent?: string;
}

export function useMiningTips() {
  const authStore = useAuthStore();
  const miningStore = useMiningStore();

  const dismissedIds = ref<Set<string>>(new Set());

  function dismiss(id: string) {
    dismissedIds.value = new Set([...dismissedIds.value, id]);
  }

  const energyPercent = computed(() => {
    const max = authStore.effectiveMaxEnergy;
    if (!max) return 100;
    return ((authStore.player?.energy ?? 0) / max) * 100;
  });

  const internetPercent = computed(() => {
    const max = authStore.effectiveMaxInternet;
    if (!max) return 100;
    return ((authStore.player?.internet ?? 0) / max) * 100;
  });

  const activeTips = computed<MiningTip[]>(() => {
    const tips: MiningTip[] = [];

    // Energy
    if (energyPercent.value <= 10) {
      tips.push({
        id: 'energy-critical',
        severity: 'danger',
        icon: '⚡',
        messageKey: 'tips.energyCritical',
        messageParams: { percent: Math.round(energyPercent.value) },
        actionKey: 'tips.action.goToMarket',
        actionEvent: 'open-market',
      });
    } else if (energyPercent.value <= 25) {
      tips.push({
        id: 'energy-warning',
        severity: 'warning',
        icon: '⚡',
        messageKey: 'tips.energyWarning',
        messageParams: { percent: Math.round(energyPercent.value) },
        actionKey: 'tips.action.goToMarket',
        actionEvent: 'open-market',
      });
    }

    // Internet
    if (internetPercent.value <= 10) {
      tips.push({
        id: 'internet-critical',
        severity: 'danger',
        icon: '📡',
        messageKey: 'tips.internetCritical',
        messageParams: { percent: Math.round(internetPercent.value) },
        actionKey: 'tips.action.goToMarket',
        actionEvent: 'open-market',
      });
    } else if (internetPercent.value <= 25) {
      tips.push({
        id: 'internet-warning',
        severity: 'warning',
        icon: '📡',
        messageKey: 'tips.internetWarning',
        messageParams: { percent: Math.round(internetPercent.value) },
        actionKey: 'tips.action.goToMarket',
        actionEvent: 'open-market',
      });
    }

    // Rig overheating
    const overheatingCritical = miningStore.rigs.filter(r => (r.temperature ?? 0) >= 80);
    const overheatingWarn = miningStore.rigs.filter(r => (r.temperature ?? 0) >= 60 && (r.temperature ?? 0) < 80);

    if (overheatingCritical.length > 0) {
      const worst = overheatingCritical.reduce((a, b) => (a.temperature > b.temperature ? a : b));
      tips.push({
        id: 'rig-overheat-critical',
        severity: 'danger',
        icon: '🔥',
        messageKey: 'tips.rigOverheatCritical',
        messageParams: { count: overheatingCritical.length, temp: Math.round(worst.temperature) },
      });
    } else if (overheatingWarn.length > 0) {
      tips.push({
        id: 'rig-overheat-warning',
        severity: 'warning',
        icon: '🌡️',
        messageKey: 'tips.rigOverheatWarning',
        messageParams: { count: overheatingWarn.length },
      });
    }

    // Rig broken
    const brokenRigs = miningStore.rigs.filter(r => r.condition <= 0);
    if (brokenRigs.length > 0) {
      tips.push({
        id: 'rig-broken',
        severity: 'danger',
        icon: '💀',
        messageKey: 'tips.rigBroken',
        messageParams: { count: brokenRigs.length },
      });
    }

    // Rig condition low
    const lowCondition = miningStore.rigs.filter(r => r.condition > 0 && r.condition < 30);
    if (lowCondition.length > 0) {
      tips.push({
        id: 'rig-condition-low',
        severity: 'warning',
        icon: '🔧',
        messageKey: 'tips.rigConditionLow',
        messageParams: { count: lowCondition.length },
      });
    }

    // Cooling degraded
    const degradedCooling = miningStore.rigs.filter(r => {
      if (!r.is_active) return false;
      const coolingItems = miningStore.rigCooling[r.id] ?? [];
      return coolingItems.some(c => c.durability < 50);
    });
    if (degradedCooling.length > 0) {
      tips.push({
        id: 'cooling-degraded',
        severity: 'warning',
        icon: '❄️',
        messageKey: 'tips.coolingDegraded',
        messageParams: { count: degradedCooling.length },
      });
    }

    // No active rigs
    if (miningStore.rigs.length > 0 && miningStore.activeRigsCount === 0) {
      tips.push({
        id: 'no-active-rigs',
        severity: 'info',
        icon: '💡',
        messageKey: 'tips.noActiveRigs',
      });
    }

    return tips.filter(tip => !dismissedIds.value.has(tip.id));
  });

  return { activeTips, dismiss };
}
