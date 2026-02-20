<script setup lang="ts">
import { ref, watch, computed, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAuthStore } from '@/stores/auth';
import { useMiningStore } from '@/stores/mining';
import { useToastStore } from '@/stores/toast';
import { useMarketStore } from '@/stores/market';
import { getPlayerInventory, installCoolingToRig, repairRig, deleteRig, getRigCooling, getPlayerBoosts, installBoostToRig, getRigBoosts, getRigUpgrades, upgradeRig, removeCoolingFromRig, removeBoostFromRig, applyRigPatch } from '@/utils/api';
import { formatCrypto } from '@/utils/format';
import { playSound } from '@/utils/sounds';
import RepairMinigame from '@/components/RepairMinigame.vue';

const { t } = useI18n();
const authStore = useAuthStore();
const miningStore = useMiningStore();
const toastStore = useToastStore();
const marketStore = useMarketStore();

interface RigData {
  id: string;
  is_active: boolean;
  condition: number;
  temperature: number;
  max_condition?: number;
  times_repaired?: number;
  patch_count?: number;
  rig: {
    id: string;
    name: string;
    hashrate: number;
    power_consumption: number;
    internet_consumption: number;
    tier: string;
    repair_cost: number;
    base_price: number;
    currency: 'gamecoin' | 'crypto' | 'ron';
  };
}

interface CoolingItem {
  inventory_id: string;
  quantity: number;
  id: string;
  name: string;
  cooling_power: number;
  energy_cost: number;
  tier: string;
}

interface ModdedCoolingItem {
  player_cooling_item_id: string;
  cooling_item_id: string;
  name: string;
  cooling_power: number;
  energy_cost: number;
  tier: string;
  mods: Array<{ component_id: string; slot: number; cooling_power_mod: number; energy_cost_mod: number; durability_mod: number }>;
  mod_slots_used: number;
  max_mod_slots: number;
  effective_cooling_power: number;
  effective_energy_cost: number;
  total_durability_mod: number;
}

interface InstalledCooling {
  id: string;
  cooling_item_id: string;
  durability: number;
  name: string;
  cooling_power: number;
  energy_cost: number;
  // Mod fields
  player_cooling_item_id?: string;
  mods?: Array<{ component_id: string; slot: number; cooling_power_mod: number; energy_cost_mod: number; durability_mod: number }>;
  mod_slots_used?: number;
  max_mod_slots?: number;
  effective_cooling_power?: number;
  effective_energy_cost?: number;
  total_durability_mod?: number;
}

interface BoostItem {
  boost_id: string;
  quantity: number;
  name: string;
  description: string;
  boost_type: string;
  effect_value: number;
  secondary_value: number;
  duration_minutes: number;
  tier: string;
}

interface InstalledBoost {
  id: string;
  boost_item_id: string;
  remaining_seconds: number;
  stack_count: number;
  name: string;
  boost_type: string;
  effect_value: number;
  secondary_value: number;
  tier: string;
}

interface UpgradeInfo {
  current_level: number;
  can_upgrade: boolean;
  next_cost: number;
  next_bonus: number;
  current_bonus: number;
}

interface RigUpgrades {
  success: boolean;
  max_level: number;
  hashrate: UpgradeInfo;
  efficiency: UpgradeInfo;
  thermal: UpgradeInfo;
}

const props = defineProps<{
  show: boolean;
  rig: RigData | null;
}>();

const emit = defineEmits<{
  close: [];
  updated: [];
}>();

const loading = ref(false);
const processing = ref(false);

// Inventory cooling items
const coolingItems = ref<CoolingItem[]>([]);
const moddedCoolingItems = ref<ModdedCoolingItem[]>([]);
// Installed cooling on this rig
const installedCooling = ref<InstalledCooling[]>([]);

// Inventory boost items
const boostItems = ref<BoostItem[]>([]);
// Installed boosts on this rig
const installedBoosts = ref<InstalledBoost[]>([]);

// Rig upgrades
const rigUpgrades = ref<RigUpgrades | null>(null);

// Expanded cooling detail (for inline tooltip)
const expandedCoolingId = ref<string | null>(null);

function toggleCoolingDetail(id: string) {
  expandedCoolingId.value = expandedCoolingId.value === id ? null : id;
}

// Confirmation dialog
const showConfirm = ref(false);
const confirmAction = ref<{
  type: 'install' | 'repair' | 'delete' | 'boost' | 'upgrade' | 'destroy_cooling' | 'destroy_boost' | 'patch';
  data: {
    coolingId?: string;
    coolingName?: string;
    coolingPower?: number;
    coolingDurability?: number;
    playerCoolingItemId?: string;
    boostId?: string;
    boostName?: string;
    boostEffect?: string;
    boostDuration?: number;
    boostRemainingSeconds?: number;
    upgradeType?: 'hashrate' | 'efficiency' | 'thermal';
    upgradeCost?: number;
    upgradeBonus?: number;
    upgradeNewLevel?: number;
  };
} | null>(null);

// Processing modal
const showProcessingModal = ref(false);
const processingStatus = ref<'processing' | 'error'>('processing');
const processingError = ref('');

// Repair minigame
const showMinigame = ref(false);

// Timer for smooth countdown interpolation between server updates
let boostTimer: number | null = null;

function startBoostTimer() {
  stopBoostTimer();
  boostTimer = window.setInterval(() => {
    // Only decrement if rig is active (mining) - interpolate between server updates
    if (props.rig?.is_active && installedBoosts.value.length > 0) {
      installedBoosts.value = installedBoosts.value
        .map(boost => ({
          ...boost,
          remaining_seconds: Math.max(0, boost.remaining_seconds - 1),
        }))
        .filter(boost => boost.remaining_seconds > 0);
    }
  }, 1000);
}

function stopBoostTimer() {
  if (boostTimer) {
    clearInterval(boostTimer);
    boostTimer = null;
  }
}

onUnmounted(() => {
  stopBoostTimer();
});

// Sync boosts from store when updated via realtime (server is source of truth)
watch(
  () => props.rig?.id ? miningStore.rigBoosts[props.rig.id] : null,
  (storeBoosts) => {
    if (storeBoosts && props.show) {
      // Server update received - sync with authoritative data
      installedBoosts.value = storeBoosts.map(b => ({ ...b }));
    }
  },
  { deep: true }
);

// Track if data has been loaded for install/upgrade tabs
const dataLoaded = ref(false);

// Load data when modal opens - only for install tab, repair tab doesn't need DB data
// Load data when modal opens
watch(() => props.show, async (isOpen) => {
  if (isOpen && props.rig) {
    dataLoaded.value = false;
    await loadData();
    startBoostTimer();
  } else {
    stopBoostTimer();
  }
});



async function loadData() {
  if (!authStore.player || !props.rig || dataLoaded.value) return;
  loading.value = true;

  try {
    const [inventory, cooling, playerBoosts, rigBoosts, upgrades] = await Promise.all([
      getPlayerInventory(authStore.player.id),
      getRigCooling(props.rig.id),
      getPlayerBoosts(authStore.player.id),
      getRigBoosts(props.rig.id),
      getRigUpgrades(props.rig.id),
    ]);

    coolingItems.value = inventory.cooling || [];
    moddedCoolingItems.value = inventory.modded_cooling || [];
    installedCooling.value = cooling || [];
    boostItems.value = playerBoosts?.inventory || [];
    installedBoosts.value = rigBoosts || [];
    
    if (upgrades?.success) {
      // Enforce 50% cap on hashrate bonus
      if (upgrades.hashrate.next_bonus > 50) upgrades.hashrate.next_bonus = 50;
      if (upgrades.hashrate.current_bonus >= 50) {
        upgrades.hashrate.can_upgrade = false;
        upgrades.hashrate.next_bonus = 50;
      }

      // Enforce 50% cap on efficiency bonus
      if (upgrades.efficiency.next_bonus > 50) upgrades.efficiency.next_bonus = 50;
      if (upgrades.efficiency.current_bonus >= 50) {
        upgrades.efficiency.can_upgrade = false;
        upgrades.efficiency.next_bonus = 50;
      }

      // Enforce 50% cap on thermal bonus
      if (upgrades.thermal.next_bonus > 50) upgrades.thermal.next_bonus = 50;
      if (upgrades.thermal.current_bonus >= 50) {
        upgrades.thermal.can_upgrade = false;
        upgrades.thermal.next_bonus = 50;
      }
    }

    rigUpgrades.value = upgrades?.success ? upgrades : null;
    dataLoaded.value = true;
  } catch (e) {
    console.error('Error loading rig data:', e);
  } finally {
    loading.value = false;
  }
}

// Computed: repair system - max 3 repairs with degradation
// 1st repair: +90%, max 90%
// 2nd repair: +70%, max 70%
// 3rd repair: +50%, max 50%
const MAX_REPAIRS = 3;
const timesRepaired = computed(() => props.rig?.times_repaired ?? 0);
const canStillRepair = computed(() => timesRepaired.value < MAX_REPAIRS);

// Get repair parameters based on times_repaired
const repairParams = computed(() => {
  switch (timesRepaired.value) {
    case 0: return { bonus: 90, newMax: 90 };
    case 1: return { bonus: 70, newMax: 70 };
    case 2: return { bonus: 50, newMax: 50 };
    default: return { bonus: 0, newMax: props.rig?.max_condition ?? 100 };
  }
});

// Repair bonus: actual condition that will be restored
const repairBonus = computed(() => {
  if (!props.rig) return 0;
  const currentCondition = props.rig.condition;
  const { bonus } = repairParams.value;
  // new_condition = min(current + bonus, 100) - tope SIEMPRE en 100%
  // Ejemplo: 70% + 70% = 140% -> tope en 100% = 100%
  const newCondition = Math.min(currentCondition + bonus, 100);
  // condition_restored = new_condition - current
  return Math.max(0, newCondition - currentCondition);
});

// Is rig at max condition? (100% es siempre el máximo)
const isAtMaxCondition = computed(() => {
  if (!props.rig) return true;
  return props.rig.condition >= 100;
});

// Can repair: rig is off and repairs remaining
const canRepair = computed(() => {
  if (!props.rig) return false;
  return !props.rig.is_active && canStillRepair.value;
});

// Cost based on how much will be restored (30% of repair_cost already in GC)
const repairCost = computed(() => {
  if (!props.rig) return 0;
  const repairCostGC = props.rig.rig.repair_cost ?? 0;
  const percentToRepair = repairBonus.value / 100;
  return Math.ceil(repairCostGC * percentToRepair * 0.30);
});

// Repairs are always paid in GameCoin
const repairCurrencySymbol = 'GC';

// Next repair info (the repair that will be done next)
const nextRepairInfo = computed(() => {
  if (timesRepaired.value >= MAX_REPAIRS) return null;
  if (!props.rig) return null;

  // Repair parameters based on how many repairs have been done
  let bonus: number;
  let newMax: number;
  switch (timesRepaired.value) {
    case 0: bonus = 90; newMax = 90; break; // First repair
    case 1: bonus = 70; newMax = 70; break; // Second repair
    case 2: bonus = 50; newMax = 50; break; // Third repair
    default: return null;
  }

  // Calculate actual condition after repair
  // El tope es SIEMPRE 100%
  const currentCondition = props.rig.condition;
  // Ejemplo: 70% + 70% = 140% -> tope en 100% = 100%
  const newCondition = Math.min(currentCondition + bonus, 100);
  const conditionRestored = newCondition - currentCondition;

  // If repair would not improve condition (current >= 100), mark as not beneficial
  const isBeneficial = conditionRestored > 0;

  const repairCostGC = props.rig.rig.repair_cost ?? 0;

  // Cost is based on condition restored, not bonus
  const maxCost = Math.ceil(repairCostGC * (Math.max(0, conditionRestored) / 100) * 0.30);

  return {
    number: timesRepaired.value + 1,
    bonus,
    newMax,
    maxCost,
    newCondition,
    conditionRestored,
    isBeneficial,
  };
});

const canAffordRepair = computed(() => {
  if (!authStore.player) return false;
  return (authStore.player.gamecoin_balance ?? 0) >= repairCost.value;
});

// Patch system computeds
const patchCount = computed(() => props.rig?.patch_count ?? 0);
const patchHashPenalty = computed(() =>
  Math.round((1 - Math.pow(0.90, patchCount.value)) * 1000) / 10
);
const patchConsumptionPenalty = computed(() =>
  Math.round((Math.pow(1.15, patchCount.value) - 1) * 1000) / 10
);
const nextPatchHashPenalty = computed(() =>
  Math.round((1 - Math.pow(0.90, patchCount.value + 1)) * 1000) / 10
);
const nextPatchConsumptionPenalty = computed(() =>
  Math.round((Math.pow(1.15, patchCount.value + 1) - 1) * 1000) / 10
);

// Total cooling power installed (considering durability and mods)
const totalCoolingPower = computed(() => {
  return installedCooling.value.reduce((sum, c) => {
    const power = c.effective_cooling_power ?? c.cooling_power;
    return sum + (power * c.durability / 100);
  }, 0);
});

// Coolant boost multiplier from active power-up (e.g. coolant_injection -60% => tempMult = 0.4)
const coolantBoostPercent = computed(() => {
  const coolantBoost = installedBoosts.value.find(b => b.boost_type === 'coolant_injection');
  return coolantBoost ? coolantBoost.effect_value : 0;
});
const coolantTempMult = computed(() => Math.max(0, 1 - coolantBoostPercent.value / 100));

// Upgrade bonuses (from store's full rig data)
const storeRig = computed(() => props.rig ? miningStore.rigs.find(r => r.id === props.rig!.id) : null);
const rigUpgradeHashBonus = computed(() => (storeRig.value as any)?.hashrate_bonus ?? 0);
const rigUpgradeEffBonus = computed(() => (storeRig.value as any)?.efficiency_bonus ?? 0);
const rigUpgradeThermalBonus = computed(() => (storeRig.value as any)?.thermal_bonus ?? 0);
const hasUpgradeBonuses = computed(() =>
  rigUpgradeHashBonus.value > 0 || rigUpgradeEffBonus.value > 0 || rigUpgradeThermalBonus.value > 0
);

// Base heat generated by the rig (power_consumption * 0.8, before any reductions)
const rigBaseHeat = computed(() => {
  return (props.rig?.rig.power_consumption ?? 0) * 0.8;
});

// Effective heat generation including ALL modifiers (cooling + thermal upgrade + coolant boost)
// Mirrors backend: GREATEST(0, base_heat * (1 - thermal_bonus/100) - cooling_power) * temp_mult
// Thermal bonus is now a PERCENTAGE reduction of base heat (e.g. 50%)
const rigHeatGeneration = computed(() => {
  const base = rigBaseHeat.value;
  const heatAfterUpgrade = base * (1 - rigUpgradeThermalBonus.value / 100);
  const afterCooling = Math.max(0, heatAfterUpgrade - totalCoolingPower.value);
  return afterCooling * coolantTempMult.value;
});

// Net heat is now the same as rigHeatGeneration since it already includes all reductions
const netHeat = computed(() => {
  return rigHeatGeneration.value;
});

// Is cooling sufficient? (effective heat ≈ 0)
const isCoolingSufficient = computed(() => {
  return rigHeatGeneration.value <= 0.1;
});

// Detailed heat breakdown for tooltip
const heatBreakdownTooltip = computed(() => {
  const base = rigBaseHeat.value;
  const thermalBonus = rigUpgradeThermalBonus.value;
  const heatAfterUpgrade = base * (1 - thermalBonus / 100);
  const cooling = totalCoolingPower.value;
  // const afterCooling = Math.max(0, heatAfterUpgrade - cooling);
  // const coolantPct = coolantBoostPercent.value;
  // const final = rigHeatGeneration.value;

  let content = `<div class="text-xs text-left space-y-1 min-w-[180px]">`;
  
  // Base Heat
  content += `<div class="flex justify-between gap-4"><span>🔥 ${t('rigManage.coolantTooltip.baseHeat')}:</span> <span class="font-mono">${base.toFixed(1)}°</span></div>`;
  
  // Thermal Upgrade
  if (thermalBonus > 0) {
    const reduction = base - heatAfterUpgrade;
    content += `<div class="flex justify-between gap-4 text-cyan-300"><span>🔧 Upgrade (${thermalBonus}%):</span> <span class="font-mono">-${reduction.toFixed(1)}°</span></div>`;
  }
  
  // Cooling
  if (cooling > 0) {
    content += `<div class="flex justify-between gap-4 text-cyan-400"><span>❄️ Cooling:</span> <span class="font-mono">-${cooling.toFixed(1)}°</span></div>`;
  }
  
  content += `<div class="my-1 border-t border-white/20"></div>`;
  
  const excess = cooling - heatAfterUpgrade;
  
  if (excess >= 0) {
    // Sufficient cooling
    content += `<div class="flex justify-between gap-4 font-bold text-emerald-400"><span>✅ Calor Final:</span> <span class="font-mono">0°</span></div>`;
    content += `<div class="flex justify-between gap-4 text-emerald-300/60 text-[10px]"><span>Exceso:</span> <span class="font-mono">+${excess.toFixed(1)}°</span></div>`;
  } else {
    // Insufficient
    // Final heat is basically abs(excess) (since heatAfterUpgrade > cooling)
    // or rigHeatGeneration which includes coolant mult.
    // Let's stick to simple math for tooltip display
    const visibleFinal = Math.abs(excess); 
    
    content += `<div class="flex justify-between gap-4 font-bold text-orange-400"><span>🌡️ Calor Final:</span> <span class="font-mono">${visibleFinal.toFixed(1)}°</span></div>`;
    content += `<div class="flex justify-between gap-4 text-status-danger text-[10px]"><span>Falta cooling:</span> <span class="font-mono">${excess.toFixed(1)}°</span></div>`;
  }
  
  content += `</div>`;

  return {
    content,
    html: true
  };
});

/**
 * Estimate remaining lifetime of a cooling item.
 * Replicates backend formula from process_resource_decay:
 * decay_per_tick = 0.5 + MAX(0, temp - 40) * 0.02 + MAX(0, power*0.3 - cooling) * 0.15
 * Each tick = 1 minute (cron runs every 60s)
 */
function estimateCoolingLife(cooling: InstalledCooling): string {
  const temp = props.rig?.temperature ?? 25;
  const power = props.rig?.rig.power_consumption ?? 0;
  const totalCool = totalCoolingPower.value;

  const baseLoss = 0.5;
  const tempPenalty = Math.max(0, temp - 40) * 0.02;
  const heatExcess = Math.max(0, (power * 0.3) - totalCool) * 0.15;
  const lossPerTick = baseLoss + tempPenalty + heatExcess;

  if (lossPerTick <= 0) return '∞';

  const remainingTicks = cooling.durability / lossPerTick;
  const minutes = Math.round(remainingTicks);

  if (minutes < 60) return `~${minutes}m`;
  const hrs = Math.floor(minutes / 60);
  const mins = minutes % 60;
  if (hrs >= 24) {
    const days = Math.floor(hrs / 24);
    const remainHrs = hrs % 24;
    return `~${days}d ${remainHrs}h`;
  }
  return `~${hrs}h ${mins.toString().padStart(2, '0')}m`;
}

// Internet consumption (with upgrades + boosts)
// Mirrors heat logic: base * (1 - upgrade%) * (1 - boost%)
const rigInternetConsumption = computed(() => {
  const base = props.rig?.rig.internet_consumption ?? 0;
  // 1. Efficiency upgrade (permanent reduction %)
  const afterUpgrade = base * (1 - rigUpgradeEffBonus.value / 100);
  // 2. Bandwidth optimizer boost (temporary reduction %)
  const boost = installedBoosts.value.find(b => b.boost_type === 'bandwidth_optimizer');
  const boostReduction = boost ? boost.effect_value : 0;
  const val = afterUpgrade * (1 - boostReduction / 100);
  return Math.round(val * 10) / 10;
});

const baseHashrate = computed(() => props.rig?.rig?.hashrate ?? 0);
const basePower = computed(() => props.rig?.rig?.power_consumption ?? 0);

// Power consumption (with upgrades + boosts)
const rigPowerConsumption = computed(() => {
  const base = props.rig?.rig.power_consumption ?? 0;
  // 1. Efficiency upgrade (permanent reduction %)
  const afterUpgrade = base * (1 - rigUpgradeEffBonus.value / 100);
  // 2. Energy saver boost (temporary reduction %)
  const boost = installedBoosts.value.find(b => b.boost_type === 'energy_saver');
  const boostReduction = boost ? boost.effect_value : 0;
  const val = afterUpgrade * (1 - boostReduction / 100);
  return Math.round(val * 10) / 10;
});

function getTierColor(tier: string) {
  switch (tier) {
    case 'elite': return 'text-amber-400';
    case 'advanced': return 'text-fuchsia-400';
    case 'standard': return 'text-sky-400';
    case 'basic': return 'text-emerald-400';
    default: return 'text-text-muted';
  }
}

function getTierBg(tier: string) {
  switch (tier) {
    case 'elite': return 'bg-amber-500/10 border-amber-500/30';
    case 'advanced': return 'bg-fuchsia-500/10 border-fuchsia-500/30';
    case 'standard': return 'bg-sky-500/10 border-sky-500/30';
    case 'basic': return 'bg-emerald-500/10 border-emerald-500/30';
    default: return 'bg-bg-tertiary border-border';
  }
}

function getBoostIcon(type: string): string {
  const icons: Record<string, string> = {
    hashrate: '⚡',
    energy_saver: '🔋',
    bandwidth_optimizer: '📡',
    overclock: '🔥',
    coolant_injection: '❄️',
    durability_shield: '🛡️',
  };
  return icons[type] || '🚀';
}

function getBoostEffectText(boost: BoostItem | InstalledBoost): string {
  const sign = boost.boost_type === 'overclock' ? '+' : (boost.boost_type.includes('saver') || boost.boost_type.includes('optimizer') || boost.boost_type.includes('coolant') || boost.boost_type.includes('durability') ? '-' : '+');
  let text = `${sign}${boost.effect_value}%`;
  if (boost.boost_type === 'overclock' && boost.secondary_value) {
    text += ` / +${boost.secondary_value}%`;
  }
  return text;
}



function formatTime(seconds: number): string {
  if (seconds <= 0) return '0:00';
  const hrs = Math.floor(seconds / 3600);
  const mins = Math.floor((seconds % 3600) / 60);
  const secs = Math.floor(seconds % 60);
  if (hrs > 0) {
    return `${hrs}h ${mins.toString().padStart(2, '0')}m`;
  }
  return `${mins}:${secs.toString().padStart(2, '0')}`;
}

function getBoostTierClasses(tier: string): { bg: string; border: string; text: string; glow: string } {
  switch (tier) {
    case 'elite': return { bg: 'bg-amber-500/10', border: 'border-amber-500/30', text: 'text-amber-400', glow: 'shadow-amber-500/10' };
    case 'advanced': return { bg: 'bg-fuchsia-500/10', border: 'border-fuchsia-500/30', text: 'text-fuchsia-400', glow: 'shadow-fuchsia-500/10' };
    case 'standard': return { bg: 'bg-sky-500/10', border: 'border-sky-500/30', text: 'text-sky-400', glow: 'shadow-sky-500/10' };
    default: return { bg: 'bg-emerald-500/10', border: 'border-emerald-500/30', text: 'text-emerald-400', glow: 'shadow-emerald-500/10' };
  }
}

function getBoostTimePercent(boost: InstalledBoost): number {
  // Estimate based on known durations: basic=60min, standard=720min, elite=1440min
  const maxSeconds = boost.tier === 'elite' ? 86400 : boost.tier === 'advanced' ? 43200 : boost.tier === 'standard' ? 43200 : 3600;
  return Math.min(100, (boost.remaining_seconds / maxSeconds) * 100);
}

function getTimeBarColor(percent: number): string {
  if (percent > 50) return 'bg-status-success';
  if (percent > 20) return 'bg-status-warning';
  return 'bg-status-danger';
}

/**
 * Calculate the real impact text for any boost type based on rig stats.
 * Shows what the percentage actually means in absolute numbers.
 */
function getBoostImpactText(boost: InstalledBoost): string {
  if (!props.rig) return '';
  const rig = props.rig;

  switch (boost.boost_type) {
    case 'hashrate': {
      // +X% hashrate → absolute increase
      const base = rig.rig.hashrate;
      const gain = (base * boost.effect_value / 100);
      return `⚡ +${gain.toFixed(1)} Hash (${base} base)`;
    }
    case 'energy_saver': {
      // -X% energy consumption
      const base = rig.rig.power_consumption;
      const saved = (base * boost.effect_value / 100);
      return `🔋 -${saved.toFixed(1)}/t energía (${base} base)`;
    }
    case 'bandwidth_optimizer': {
      // -X% internet consumption
      const base = rig.rig.internet_consumption;
      const saved = (base * boost.effect_value / 100);
      return `📡 -${saved.toFixed(1)}/t internet (${base} base)`;
    }
    case 'overclock': {
      // +X% hashrate / +Y% heat
      const baseHash = rig.rig.hashrate;
      const hashGain = (baseHash * boost.effect_value / 100);
      let text = `⚡ +${hashGain.toFixed(1)} Hash`;
      if (boost.secondary_value) {
        const baseHeat = rigBaseHeat.value;
        const heatIncrease = (baseHeat * boost.secondary_value / 100);
        text += ` | 🔥 +${heatIncrease.toFixed(1)}°/t`;
      }
      return text;
    }
    case 'durability_shield': {
      // -X% durability loss rate
      return `🛡️ -${boost.effect_value}% desgaste por tick`;
    }
    case 'coolant_injection': {
      // Handled by getCoolantImpactText (more detailed)
      return '';
    }
    default:
      return '';
  }
}

/**
 * Calculate the visual impact of a coolant boost on heat generation.
 * Replicates the backend formula from process_resource_decay.
 */
function getCoolantImpactText(boost: InstalledBoost): string {
  if (boost.boost_type !== 'coolant_injection' || !props.rig) return '';

  const pc = props.rig.rig.power_consumption;
  const temp = props.rig.temperature ?? 25;
  const condition = props.rig.condition ?? 100;

  // Replicate backend hashrate_ratio
  const tempPenalty = temp <= 50 ? 1 : Math.max(0.3, 1 - ((temp - 50) * 0.014));
  const conditionPenalty = condition / 100;
  const hashrateRatio = tempPenalty * conditionPenalty;

  // Total cooling power from installed cooling items (using effective values if modded)
  const totalCoolingPower = installedCooling.value.reduce((sum, c) => {
    const power = c.effective_cooling_power ?? c.cooling_power;
    const eff = c.durability >= 50 ? c.durability / 100 : (c.durability / 100) * (c.durability / 50);
    return sum + power * eff;
  }, 0);

  // Thermal bonus from rig upgrades (percentage)
  const thermalBonusPercent = props.rig ? (miningStore.rigs.find(r => r.id === props.rig!.id) as any)?.thermal_bonus ?? 0 : 0;

  // Calculate heat generation WITHOUT this coolant (temp_mult = 1.0)
  let heatWithout: number;
  let baseHeat: number;

  if (totalCoolingPower <= 0) {
    baseHeat = Math.min(pc * hashrateRatio * 1.0, 15);
  } else {
    baseHeat = pc * hashrateRatio * 0.8;
  }

  const heatAfterUpgrade = baseHeat * (1 - thermalBonusPercent / 100);
  heatWithout = Math.max(0, heatAfterUpgrade - totalCoolingPower);

  // Calculate heat WITH this coolant (temp_mult = 1 - effect/100)
  const tempMult = Math.max(0, 1 - boost.effect_value / 100);
  const heatWith = heatWithout * tempMult;

  return `🌡️ ${heatWithout.toFixed(1)} → ${heatWith.toFixed(1)}°/tick`;
}

/**
 * Returns a detailed tooltip explaining the coolant impact calculation.
 */
function getCoolantImpactTooltip(boost: InstalledBoost) {
  if (boost.boost_type !== 'coolant_injection' || !props.rig) return '';

  const pc = props.rig.rig.power_consumption;
  const temp = props.rig.temperature ?? 25;
  const condition = props.rig.condition ?? 100;

  const tempPenalty = temp <= 50 ? 1 : Math.max(0.3, 1 - ((temp - 50) * 0.014));
  const conditionPenalty = condition / 100;
  const hashrateRatio = tempPenalty * conditionPenalty;

  const coolingPower = installedCooling.value.reduce((sum, c) => {
    const power = c.effective_cooling_power ?? c.cooling_power;
    const eff = c.durability >= 50 ? c.durability / 100 : (c.durability / 100) * (c.durability / 50);
    return sum + power * eff;
  }, 0);

  // Thermal bonus from rig upgrades (percentage)
  const thermalBonusPercent = (miningStore.rigs.find(r => r.id === props.rig!.id) as any)?.thermal_bonus ?? 0;

  const baseHeat = coolingPower <= 0
    ? Math.min(pc * hashrateRatio, 15)
    : pc * hashrateRatio * 0.8;

  const heatAfterUpgrade = baseHeat * (1 - thermalBonusPercent / 100);
  const thermalReductionAmount = baseHeat - heatAfterUpgrade;

  const heatWithout = Math.max(0, heatAfterUpgrade - coolingPower);
  const tempMult = Math.max(0, 1 - boost.effect_value / 100);
  const heatWith = heatWithout * tempMult;

  const saved = heatWithout - heatWith;

  let content = `<div class="text-xs text-left space-y-1 min-w-[180px]">`;

  content += `<div class="flex justify-between gap-4"><span>⚡ ${t('rigManage.coolantTooltip.basePower')}:</span> <span class="font-mono">${pc}W</span></div>`;
  content += `<div class="flex justify-between gap-4"><span>📊 ${t('rigManage.coolantTooltip.workRatio')}:</span> <span class="font-mono">${(hashrateRatio * 100).toFixed(0)}%</span></div>`;
  content += `<div class="flex justify-between gap-4"><span>🔥 ${t('rigManage.coolantTooltip.baseHeat')}:</span> <span class="font-mono">${baseHeat.toFixed(1)}°</span></div>`;

  if (thermalBonusPercent > 0) {
    content += `<div class="flex justify-between gap-4 text-cyan-300"><span>🔧 ${t('rigManage.coolantTooltip.thermalUpgrade')}:</span> <span class="font-mono">-${thermalReductionAmount.toFixed(1)}° (${thermalBonusPercent}%)</span></div>`;
  }
  if (coolingPower > 0) {
    content += `<div class="flex justify-between gap-4 text-cyan-400"><span>❄️ ${t('rigManage.coolantTooltip.coolingReduction')}:</span> <span class="font-mono">-${coolingPower.toFixed(1)}°</span></div>`;
  }

  content += `<div class="my-1 border-t border-white/20"></div>`;
  content += `<div class="flex justify-between gap-4 text-orange-300"><span>🌡️ ${t('rigManage.coolantTooltip.without')}:</span> <span class="font-mono">+${heatWithout.toFixed(1)}°/tick</span></div>`;
  content += `<div class="flex justify-between gap-4 text-cyan-300"><span>❄️ ${t('rigManage.coolantTooltip.with')} (-${boost.effect_value}%):</span> <span class="font-mono">+${heatWith.toFixed(1)}°/tick</span></div>`;
  content += `<div class="flex justify-between gap-4 font-bold text-emerald-400"><span>✅ ${t('rigManage.coolantTooltip.saving')}:</span> <span class="font-mono">-${saved.toFixed(1)}°/tick</span></div>`;

  content += `</div>`;

  return { content, html: true };
}

// Translation helpers
function getRigName(id: string): string {
  const key = `market.items.rigs.${id}.name`;
  const translated = t(key);
  return translated !== key ? translated : id;
}

function getCoolingName(id: string, fallbackName?: string): string {
  const isUUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id);
  if (isUUID) {
    if (fallbackName) return fallbackName;
    const item = coolingItems.value.find(c => c.id === id);
    return item?.name ?? id;
  }

  const key = `market.items.cooling.${id}.name`;
  const translated = t(key);
  if (translated !== key) return translated;
  if (fallbackName) return fallbackName;
  const item = coolingItems.value.find(c => c.id === id);
  return item?.name ?? id;
}

function getBoostName(id: string, fallbackName?: string): string {
  const key = `market.items.boosts.${id}.name`;
  const translated = t(key);
  if (translated !== key) return translated;
  return fallbackName ?? id;
}

function getComponentName(id: string): string {
  const key = `market.items.components.${id}.name`;
  const translated = t(key);
  return translated !== key ? translated : id;
}

function getEffectiveCoolingPower(cooling: InstalledCooling): number {
  if (cooling.effective_cooling_power != null) {
    return cooling.effective_cooling_power;
  }
  return cooling.cooling_power;
}

function getEffectiveEnergyCost(cooling: InstalledCooling): number {
  if (cooling.effective_energy_cost != null) {
    return cooling.effective_energy_cost;
  }
  return cooling.energy_cost;
}

// === SLOT TIER SYSTEM ===

const currentSlot = computed(() => {
  if (!props.rig) return null;
  const slots = miningStore.slotInfo?.slots || [];
  return slots.find(s => s.player_rig_id === props.rig!.id) ?? null;
});

const TIER_ORDER = ['basic', 'standard', 'advanced', 'elite'];

function canInstallCoolingTier(coolingTier: string): boolean {
  const slotTier = currentSlot.value?.tier ?? 'basic';
  return TIER_ORDER.indexOf(coolingTier) <= TIER_ORDER.indexOf(slotTier);
}

// Request actions
function requestInstallCooling(cooling: CoolingItem) {
  confirmAction.value = {
    type: 'install',
    data: {
      coolingId: cooling.id,
      coolingName: getCoolingName(cooling.id),
      coolingPower: cooling.cooling_power,
    },
  };
  showConfirm.value = true;
}

function requestInstallModdedCooling(cooling: ModdedCoolingItem) {
  confirmAction.value = {
    type: 'install',
    data: {
      coolingId: cooling.cooling_item_id,
      coolingName: getCoolingName(cooling.cooling_item_id, cooling.name),
      coolingPower: cooling.effective_cooling_power,
      playerCoolingItemId: cooling.player_cooling_item_id,
    },
  };
  showConfirm.value = true;
}

function requestInstallBoost(boost: BoostItem) {
  confirmAction.value = {
    type: 'boost',
    data: {
      boostId: boost.boost_id,
      boostName: getBoostName(boost.boost_id, boost.name),
      boostEffect: getBoostEffectText(boost),
      boostDuration: boost.duration_minutes,
    },
  };
  showConfirm.value = true;
}

function requestRepair() {
  confirmAction.value = {
    type: 'repair',
    data: {},
  };
  showConfirm.value = true;
}

async function handleMinigameComplete(success: boolean) {
  showMinigame.value = false;

  if (!success) {
    // Player failed or cancelled - do nothing
    return;
  }

  // Player won - proceed with repair
  if (!authStore.player || !props.rig) return;

  processing.value = true;

  try {
    const result = await repairRig(authStore.player.id, props.rig.id);

    if (result?.success) {
      playSound('success');

      const rigName = props.rig.rig?.name || 'Rig';
      toastStore.success(`${rigName} reparado`);

      // Reload data
      dataLoaded.value = false;
      await loadData();
      await authStore.fetchPlayer();
      await miningStore.reloadRigs();
      emit('updated');
    } else {
      toastStore.error(result?.error || t('common.error'));
      playSound('error');
    }
  } catch (e) {
    console.error('Error repairing rig:', e);
    toastStore.error(t('common.error'));
    playSound('error');
  } finally {
    processing.value = false;
  }
}

function requestDelete() {
  confirmAction.value = {
    type: 'delete',
    data: {},
  };
  showConfirm.value = true;
}

function requestUpgrade(upgradeType: 'hashrate' | 'efficiency' | 'thermal') {
  if (!rigUpgrades.value) return;

  const info = rigUpgrades.value[upgradeType];
  if (!info.can_upgrade) return;

  confirmAction.value = {
    type: 'upgrade',
    data: {
      upgradeType,
      upgradeCost: info.next_cost,
      upgradeBonus: info.next_bonus,
      upgradeNewLevel: info.current_level + 1,
    },
  };
  showConfirm.value = true;
}

function requestDestroyCooling(cooling: InstalledCooling) {
  confirmAction.value = {
    type: 'destroy_cooling',
    data: {
      coolingId: cooling.id,
      coolingName: getCoolingName(cooling.cooling_item_id, cooling.name),
      coolingPower: cooling.cooling_power,
      coolingDurability: cooling.durability,
    },
  };
  showConfirm.value = true;
}

function requestDestroyBoost(boost: InstalledBoost) {
  confirmAction.value = {
    type: 'destroy_boost',
    data: {
      boostId: boost.id,
      boostName: getBoostName(boost.boost_item_id, boost.name),
      boostEffect: getBoostEffectText(boost),
      boostRemainingSeconds: boost.remaining_seconds,
    },
  };
  showConfirm.value = true;
}

async function confirmUse() {
  if (!confirmAction.value || !authStore.player || !props.rig) return;

  const { type, data } = confirmAction.value;
  showConfirm.value = false;

  // For repair, show minigame instead of processing modal
  if (type === 'repair') {
    showMinigame.value = true;
    confirmAction.value = null;
    return;
  }

  showProcessingModal.value = true;
  processingStatus.value = 'processing';
  processingError.value = '';

  try {
    let result;

    if (type === 'install' && data.coolingId) {
      result = await installCoolingToRig(authStore.player.id, props.rig.id, data.coolingId, data.playerCoolingItemId);
    } else if (type === 'boost' && data.boostId) {
      result = await installBoostToRig(authStore.player.id, props.rig.id, data.boostId);
    } else if (type === 'delete') {
      result = await deleteRig(authStore.player.id, props.rig.id);
    } else if (type === 'upgrade' && data.upgradeType) {
      result = await upgradeRig(authStore.player.id, props.rig.id, data.upgradeType);
    } else if (type === 'destroy_cooling' && data.coolingId) {
      result = await removeCoolingFromRig(authStore.player.id, props.rig.id, data.coolingId);
    } else if (type === 'destroy_boost' && data.boostId) {
      result = await removeBoostFromRig(authStore.player.id, props.rig.id, data.boostId);
    } else if (type === 'patch') {
      result = await applyRigPatch(authStore.player.id, props.rig.id);
    }

    if (result?.success) {
      playSound('success');

      const rigName = props.rig.rig?.name || 'Rig';

      // Handle delete separately - close modal immediately
      if (type === 'delete') {
        // Mostrar feedback de durabilidad del slot
        if (result.slot_destroyed) {
          toastStore.error(t('slots.slotDestroyed', { number: result.slot_number }));
        } else if (result.slot_uses_remaining !== undefined && result.slot_uses_remaining > 0) {
          toastStore.warning(t('slots.usesDecreased', { number: result.slot_number, uses: result.slot_uses_remaining }));
        }
        toastStore.success(`${rigName} eliminado`);
        closeProcessingModal();
        await authStore.fetchPlayer();
        await miningStore.loadData();
        emit('updated');
        emit('close');
        return;
      }

      // For non-delete actions, reload data and close modal
      closeProcessingModal();
      dataLoaded.value = false; // Reset to force reload
      await loadData();
      await authStore.fetchPlayer();
      await miningStore.reloadRigs();
      if (type === 'install' || type === 'destroy_cooling') {
        await miningStore.loadRigsCooling();
      } else if (type === 'boost' || type === 'destroy_boost') {
        await miningStore.loadRigsBoosts();
      }
      emit('updated');

      // Show toast notification based on action type
      if (type === 'install' && data.coolingName) {
        toastStore.boostInstalled(data.coolingName, rigName);
      } else if (type === 'boost' && data.boostName) {
        toastStore.boostInstalled(data.boostName, rigName);
      } else if (type === 'upgrade' && data.upgradeType) {
        const upgradeName = data.upgradeType === 'hashrate' ? 'Hashrate' :
          data.upgradeType === 'efficiency' ? 'Eficiencia' : 'Térmica';
        toastStore.success(`${rigName}: ${upgradeName} mejorado a Lv${data.upgradeNewLevel}`);
      } else if (type === 'destroy_cooling' && data.coolingName) {
        toastStore.success(`${data.coolingName} destruido`);
      } else if (type === 'destroy_boost' && data.boostName) {
        toastStore.success(`${data.boostName} destruido`);
      } else if (type === 'patch') {
        marketStore.loadPlayerQuantities();
        toastStore.success(`${rigName}: Patch #${result.patch_count} (+${result.condition_restored}%)`);
      }
    } else {
      processingStatus.value = 'error';
      processingError.value = result?.error || t('common.error');
      playSound('error');
    }
  } catch (e: unknown) {
    console.error('Error:', e);
    processingStatus.value = 'error';
    const err = e as Record<string, unknown>;
    processingError.value = (err?.message as string) || (err?.details as string) || t('common.error');
    playSound('error');
  } finally {
    confirmAction.value = null;
  }
}

function cancelConfirm() {
  showConfirm.value = false;
  confirmAction.value = null;
}

function closeProcessingModal() {
  showProcessingModal.value = false;
  processingStatus.value = 'processing';
  processingError.value = '';
}
</script>

<template>
  <Teleport to="body">
    <div
      v-if="show && rig"
      class="fixed inset-0 z-50 flex items-center justify-center p-4"
    >
      <!-- Overlay -->
      <div
        class="absolute inset-0 bg-black/70 backdrop-blur-sm"
        @click="emit('close')"
      ></div>

      <!-- Modal -->
      <div class="relative w-full max-w-lg lg:max-w-2xl h-[610px] lg:h-[750px] flex flex-col bg-bg-secondary border border-border rounded-xl overflow-hidden">
        <!-- Header -->
        <div class="flex items-center justify-between p-4 border-b border-border">
          <div>
            <h2 class="text-lg font-semibold flex items-center gap-2">
              <span>⚙️</span>
              <span>{{ t('rigManage.title') }}</span>
            </h2>
            <p class="text-sm text-text-muted">{{ getRigName(rig.rig.id) }}</p>
          </div>
          <button
            @click="emit('close')"
            class="p-2 hover:bg-bg-tertiary rounded-lg transition-colors text-text-muted hover:text-white"
          >
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        <!-- Rig Status Summary -->
        <div class="p-4 border-b border-border bg-bg-primary/50">
          <!-- Rig specs row -->
          <div class="flex items-center justify-center gap-3 text-xs text-text-muted mb-3 flex-wrap">
            <span
              v-tooltip="t('rigManage.tooltips.hashrate')"
              class="text-accent-primary font-mono cursor-help"
            >⚡{{ rig.rig.hashrate }} H/s</span>
            <span>•</span>
            <span
              v-tooltip="t('rigManage.tooltips.power')"
              class="text-yellow-400 cursor-help"
            ><template v-if="rig.rig.power_consumption !== rigPowerConsumption">⚡<span class="line-through text-yellow-400/50">{{ rig.rig.power_consumption }}</span> → {{ rigPowerConsumption.toFixed(1) }}/t</template><template v-else>⚡{{ rig.rig.power_consumption }}/t</template></span>
            <span>•</span>
            <span
              v-tooltip="t('rigManage.tooltips.internet')"
              class="text-blue-400 cursor-help"
            ><template v-if="rig.rig.internet_consumption !== rigInternetConsumption">📡<span class="line-through text-blue-400/50">{{ rig.rig.internet_consumption }}</span> → {{ rigInternetConsumption.toFixed(1) }}/t</template><template v-else>📡{{ rig.rig.internet_consumption }}/t</template></span>
            <span>•</span>
            <span
              v-tooltip="heatBreakdownTooltip"
              class="cursor-help"
              :class="rigBaseHeat !== rigHeatGeneration ? 'text-status-success' : 'text-orange-400'"
            ><template v-if="rigBaseHeat !== rigHeatGeneration">🔥<span class="line-through text-orange-400/50">{{ rigBaseHeat.toFixed(1) }}</span> → {{ rigHeatGeneration.toFixed(1) }}°/t</template><template v-else>🔥{{ rigHeatGeneration.toFixed(1) }}°/t</template></span>
            <span v-if="totalCoolingPower > 0" class="text-cyan-400/80 text-[10px] font-mono">(❄️-{{ totalCoolingPower.toFixed(1) }}°)</span>
          </div>
          <!-- Status grid -->
          <div class="grid grid-cols-4 gap-3 text-center text-sm">
            <div v-tooltip="t('rigManage.tooltips.condition')" class="cursor-help">
              <div class="text-text-muted text-xs mb-1">{{ t('rigManage.condition') }}</div>
              <div class="font-mono font-bold" :class="rig.condition < 30 ? 'text-status-danger' : rig.condition < 60 ? 'text-status-warning' : 'text-white'">
                {{ rig.condition }}%
              </div>
            </div>
            <div v-tooltip="t('rigManage.tooltips.temperature')" class="cursor-help">
              <div class="text-text-muted text-xs mb-1">{{ t('rigManage.temperature') }}</div>
              <div class="font-mono font-bold" :class="rig.temperature > 80 ? 'text-status-danger' : rig.temperature > 60 ? 'text-status-warning' : 'text-white'">
                {{ rig.temperature.toFixed(0) }}°C
              </div>
            </div>
            <div v-tooltip="t('rigManage.tooltips.coolingStatus')" class="cursor-help">
              <div class="text-text-muted text-xs mb-1">{{ t('rigManage.cooling') }}</div>
              <div class="font-mono font-bold text-cyan-400">
                ❄️ -{{ totalCoolingPower.toFixed(1) }}°
              </div>
              <div class="font-mono text-xs" :class="isCoolingSufficient ? 'text-status-success' : 'text-status-danger'">
                {{ isCoolingSufficient ? '✓' : '⚠' }} {{ netHeat.toFixed(1) }}° {{ isCoolingSufficient ? 'OK' : t('rigManage.excess', 'exceso') }}
              </div>
            </div>
            <div v-tooltip="t('rigManage.tooltips.maxCondition')" class="cursor-help">
              <div class="text-text-muted text-xs mb-1">{{ t('rigManage.maxCond') }}</div>
              <div class="font-mono font-bold text-white">
                {{ rig?.max_condition ?? 100 }}%
              </div>
            </div>
          </div>


        </div>

        <!-- Unified Dashboard Content -->
        <div class="flex-1 overflow-y-auto p-4 bg-bg-primary/50">
          <!-- Loading -->
          <div v-if="loading" class="text-center py-12">
            <div class="w-8 h-8 mx-auto mb-4 border-2 border-accent-primary border-t-transparent rounded-full animate-spin"></div>
            <p class="text-text-muted text-sm">{{ t('common.loading') }}</p>
          </div>

          <div v-else class="grid grid-cols-1 gap-6 pb-20">
            <!-- Active Effects Panel -->
            <div v-if="installedCooling.length > 0 || coolantBoostPercent > 0 || hasUpgradeBonuses || patchCount > 0"
              class="space-y-4">
              <div class="flex items-center justify-between border-b border-border pb-2 mb-2">
                <h3 class="text-xs font-bold text-text-muted uppercase tracking-wider flex items-center gap-2">
                  <span>✨</span> {{ t('rigManage.activeEffects') }}
                </h3>
              </div>
              <div class="space-y-1">
                <!-- Cooling effects -->
                <div v-for="cooling in installedCooling" :key="'eff-cool-' + cooling.id"
                  v-tooltip="t('rigManage.tooltips.coolingEffect', {
                    power: getEffectiveCoolingPower(cooling),
                    durability: cooling.durability.toFixed(0),
                    effective: (getEffectiveCoolingPower(cooling) * cooling.durability / 100).toFixed(1),
                    energy: getEffectiveEnergyCost(cooling)
                  })"
                  class="flex items-center justify-between text-xs px-2 py-1 rounded bg-cyan-500/5 cursor-help">
                  <div class="flex items-center gap-1.5">
                    <span class="text-cyan-400">❄️</span>
                    <span class="text-cyan-300">{{ getCoolingName(cooling.cooling_item_id) }}</span>
                    <span v-if="cooling.mods && cooling.mods.length > 0" class="text-[9px] text-fuchsia-400">🧩{{ cooling.mods.length }}</span>
                  </div>
                  <div class="flex items-center gap-2 font-mono">
                    <span class="text-cyan-400">-{{ (getEffectiveCoolingPower(cooling) * cooling.durability / 100).toFixed(1) }}°</span>
                    <span class="text-[10px]" :class="cooling.durability < 30 ? 'text-status-danger' : cooling.durability < 60 ? 'text-status-warning' : 'text-text-muted/60'">
                      {{ cooling.durability.toFixed(0) }}%
                    </span>
                  </div>
                </div>

                <!-- Coolant impact summary (if any coolant boost active and rig running) -->
                <div v-if="rig.is_active && installedBoosts.some(b => b.boost_type === 'coolant_injection')"
                  class="flex items-center justify-between text-xs px-2 py-1 rounded bg-cyan-500/5 border border-dashed border-cyan-500/20"
                  v-tooltip="getCoolantImpactTooltip(installedBoosts.find(b => b.boost_type === 'coolant_injection')!)"
                >
                  <span class="text-[10px] text-cyan-300/70 cursor-help">
                    {{ getCoolantImpactText(installedBoosts.find(b => b.boost_type === 'coolant_injection')!) }}
                  </span>
                </div>

                <!-- Upgrade bonuses -->
                <div v-if="hasUpgradeBonuses"
                  class="flex flex-col gap-2 text-xs px-2 py-2 rounded bg-amber-500/5 w-full">
                  <div v-if="rigUpgradeHashBonus > 0"
                    v-tooltip="t('rigManage.tooltips.upgradeHashBonus', { value: rigUpgradeHashBonus, abs: (baseHashrate * rigUpgradeHashBonus / 100).toFixed(1) })"
                    class="flex items-center justify-between w-full cursor-help border-b border-amber-500/10 pb-1 last:border-0 last:pb-0">
                    <div class="flex items-center gap-2">
                      <span>⚡</span>
                      <span class="text-text-muted">{{ t('rigManage.effectUpgradeHash') }}</span>
                    </div>
                    <span class="text-status-success font-mono">+{{ rigUpgradeHashBonus }}% <span class="text-xs opacity-70">(+{{ (baseHashrate * rigUpgradeHashBonus / 100).toFixed(1) }} Hash)</span></span>
                  </div>
                  <div v-if="rigUpgradeEffBonus > 0"
                    v-tooltip="t('rigManage.tooltips.upgradeEffBonus', { value: rigUpgradeEffBonus, abs: (basePower * rigUpgradeEffBonus / 100).toFixed(1) })"
                    class="flex items-center justify-between w-full cursor-help border-b border-amber-500/10 pb-1 last:border-0 last:pb-0">
                    <div class="flex items-center gap-2">
                      <span>🔋</span>
                      <span class="text-text-muted">{{ t('rigManage.effectUpgradeEff') }}</span>
                    </div>
                    <span class="text-green-400 font-mono">-{{ rigUpgradeEffBonus }}% <span class="text-xs opacity-70">(-{{ (basePower * rigUpgradeEffBonus / 100).toFixed(1) }} W)</span></span>
                  </div>
                  <div v-if="rigUpgradeThermalBonus > 0"
                    v-tooltip="t('rigManage.tooltips.upgradeThermalBonus', { value: rigUpgradeThermalBonus, abs: (rigBaseHeat * rigUpgradeThermalBonus / 100).toFixed(1) })"
                    class="flex items-center justify-between w-full cursor-help pb-1 last:pb-0">
                    <div class="flex items-center gap-2">
                      <span>🌡️</span>
                      <span class="text-text-muted">{{ t('rigManage.effectUpgradeThermal') }}</span>
                    </div>
                    <span class="text-cyan-400 font-mono">-{{ rigUpgradeThermalBonus }}% <span class="text-xs opacity-70">(-{{ (rigBaseHeat * rigUpgradeThermalBonus / 100).toFixed(1) }}°)</span></span>
                  </div>
                </div>

                <!-- Patch penalties -->
                <div v-if="patchCount > 0"
                  v-tooltip="t('rigManage.tooltips.patchPenalties', { count: patchCount, hash: patchHashPenalty, consumption: patchConsumptionPenalty })"
                  class="flex flex-col gap-1 text-xs px-2 py-2 rounded bg-fuchsia-500/5 w-full cursor-help">
                  <div class="flex items-center justify-between w-full">
                    <div class="flex items-center gap-2">
                      <span>🩹</span>
                      <span class="text-text-muted">{{ t('rigManage.patchPenalties') }}</span>
                      <span class="text-fuchsia-400 text-[10px]">x{{ patchCount }}</span>
                    </div>
                  </div>
                  <div class="flex gap-4 text-[10px] font-mono pl-6">
                    <span class="text-status-danger">Hash: -{{ patchHashPenalty }}%</span>
                    <span class="text-status-warning">{{ t('rigManage.consumption') }}: +{{ patchConsumptionPenalty }}%</span>
                  </div>
                </div>
              </div>
            </div>

            <!-- LEFT COLUMN: Hardware & Boosts -->
            <div class="space-y-4">
              <div class="flex items-center justify-between border-b border-border pb-2 mb-2">
                <h3 class="text-xs font-bold text-text-muted uppercase tracking-wider flex items-center gap-2">
                  <span>📦</span> {{ t('rigManage.hardwareItems') }}
                </h3>
                <span v-if="installedCooling.length + installedBoosts.length > 0" class="px-2 py-0.5 rounded-full text-[10px] uppercase font-bold bg-amber-500/20 text-amber-400">
                  {{ installedCooling.length + installedBoosts.length }} {{ t('rigManage.active') }}
                </span>
              </div>

              <!-- Warning if rig is active -->
              <div v-if="rig.is_active" class="p-3 rounded-lg bg-status-warning/10 border border-status-warning/30 text-status-warning text-sm">
                {{ t('rigManage.stopToInstall') }}
              </div>

              <!-- Installed Items -->
              <div v-if="installedCooling.length > 0 || installedBoosts.length > 0" class="space-y-3">
                <!-- Installed Cooling -->
                <div v-if="installedCooling.length > 0" class="space-y-2">
                  <div v-for="cooling in installedCooling" :key="cooling.id" class="bg-cyan-500/10 border border-cyan-500/30 rounded-lg overflow-hidden">
                    <div class="flex items-center justify-between w-full px-3 py-2">
                      <div class="flex items-center gap-2 cursor-pointer flex-1" @click="toggleCoolingDetail(cooling.id)">
                        <span class="text-lg">❄️</span>
                        <div class="flex-1 min-w-0">
                          <div class="font-medium text-cyan-400 text-sm flex items-center gap-1">
                            {{ getCoolingName(cooling.cooling_item_id, cooling.name) }}
                            <span v-if="cooling.mods && cooling.mods.length > 0" class="px-1 py-0.5 rounded text-[9px] bg-fuchsia-500/30 text-fuchsia-300 border border-fuchsia-500/40">🧩 {{ cooling.mod_slots_used }}/{{ cooling.max_mod_slots }}</span>
                            <svg class="w-3 h-3 text-text-muted transition-transform" :class="expandedCoolingId === cooling.id ? 'rotate-180' : ''" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" /></svg>
                          </div>
                          <div class="flex items-center gap-3 text-xs mt-0.5">
                            <span class="text-cyan-300 font-mono" v-tooltip="t('rigManage.coolingDetail.effectivePowerTip')">❄️ -{{ (getEffectiveCoolingPower(cooling) * cooling.durability / 100).toFixed(1) }}°</span>
                            <span class="text-yellow-400/70 font-mono" v-tooltip="t('rigManage.coolingDetail.energyCostTip')">⚡{{ (getEffectiveEnergyCost(cooling) * cooling.durability / 100).toFixed(1) }}/t</span>
                            <span v-if="cooling.total_durability_mod" class="font-mono text-[10px]" :class="cooling.total_durability_mod > 0 ? 'text-emerald-400/70' : 'text-rose-400/70'">🔧{{ cooling.total_durability_mod > 0 ? '+' : '' }}{{ cooling.total_durability_mod.toFixed(0) }}%</span>
                            <span v-if="rig?.is_active" class="text-text-muted/70 font-mono text-[10px]" v-tooltip="t('rigManage.coolingDetail.estimatedLifeTip')">⏱️{{ estimateCoolingLife(cooling) }}</span>
                          </div>
                        </div>
                      </div>
                      <div class="flex items-center gap-2">
                        <div class="text-right">
                          <div class="font-mono text-sm" :class="cooling.durability < 30 ? 'text-status-danger' : cooling.durability < 60 ? 'text-status-warning' : 'text-cyan-400'">{{ cooling.durability.toFixed(0) }}%</div>
                        </div>
                        <button @click="requestDestroyCooling(cooling)" :disabled="rig.is_active || processing" class="p-1.5 rounded-lg text-status-danger/70 hover:text-status-danger hover:bg-status-danger/10 transition-colors disabled:opacity-50" :title="t('rigManage.destroyItem', 'Destruir')">
                          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" /></svg>
                        </button>
                      </div>
                    </div>
                    <!-- Detail -->
                    <div v-if="expandedCoolingId === cooling.id" class="px-3 py-2.5 border-t border-cyan-500/20 bg-cyan-500/5 text-xs space-y-2">
                       <div class="grid grid-cols-2 gap-x-4 gap-y-1.5">
                         <div class="flex justify-between cursor-help" v-tooltip="t('rigManage.coolingDetail.effectivePowerTip')"><span class="text-text-muted">{{ t('rigManage.coolingDetail.effectivePower') }}</span><span class="text-cyan-400 font-mono">-{{ (getEffectiveCoolingPower(cooling) * cooling.durability / 100).toFixed(1) }}°</span></div>
                         <div class="flex justify-between cursor-help" v-tooltip="t('rigManage.coolantTooltip.basePower')"><span class="text-text-muted">{{ t('rigManage.coolingDetail.basePower') }}</span><span class="text-cyan-300/60 font-mono">-{{ cooling.cooling_power }}°</span></div>
                         <div class="flex justify-between cursor-help" v-tooltip="t('rigManage.coolingDetail.energyCostTip')"><span class="text-text-muted">{{ t('rigManage.coolingDetail.energyConsumption') }}</span><span class="text-yellow-400 font-mono">⚡{{ (getEffectiveEnergyCost(cooling) * cooling.durability / 100).toFixed(1) }}/t</span></div>
                         <div class="flex justify-between cursor-help" v-tooltip="t('rigManage.coolingDetail.efficiencyLabel')"><span class="text-text-muted">{{ t('rigManage.coolingDetail.efficiencyLabel') }}</span><span class="text-emerald-400 font-mono">{{ getEffectiveEnergyCost(cooling) > 0 ? (getEffectiveCoolingPower(cooling) / getEffectiveEnergyCost(cooling)).toFixed(2) : '∞' }} °/⚡</span></div>
                       </div>
                       <!-- Mods Section -->
                       <div v-if="cooling.mods && cooling.mods.length > 0" class="border-t border-cyan-500/15 pt-1.5">
                         <div class="text-[10px] text-fuchsia-400 font-semibold mb-1">🧩 Mods ({{ cooling.mod_slots_used }}/{{ cooling.max_mod_slots }})</div>
                         <div v-for="(mod, idx) in cooling.mods" :key="idx" class="flex items-center gap-2 py-0.5">
                           <span class="text-fuchsia-300 text-[10px]">{{ getComponentName(mod.component_id) }}</span>
                           <span v-if="mod.cooling_power_mod !== 0" class="font-mono text-[10px]" :class="mod.cooling_power_mod > 0 ? 'text-emerald-400' : 'text-rose-400'">❄️{{ mod.cooling_power_mod > 0 ? '+' : '' }}{{ mod.cooling_power_mod.toFixed(1) }}%</span>
                           <span v-if="mod.energy_cost_mod !== 0" class="font-mono text-[10px]" :class="mod.energy_cost_mod < 0 ? 'text-emerald-400' : 'text-rose-400'">⚡{{ mod.energy_cost_mod > 0 ? '+' : '' }}{{ mod.energy_cost_mod.toFixed(1) }}%</span>
                           <span v-if="mod.durability_mod !== 0" class="font-mono text-[10px]" :class="mod.durability_mod > 0 ? 'text-emerald-400' : 'text-rose-400'">🔧{{ mod.durability_mod > 0 ? '+' : '' }}{{ mod.durability_mod.toFixed(1) }}%</span>
                         </div>
                       </div>
                       <div v-if="totalCoolingPower > 0" class="flex justify-between border-t border-cyan-500/15 pt-1.5 cursor-help" v-tooltip="t('rigManage.coolingDetail.coolingShare')">
                         <span class="text-text-muted">{{ t('rigManage.coolingDetail.coolingShare') }}</span>
                         <span class="text-cyan-300 font-mono">{{ ((getEffectiveCoolingPower(cooling) * cooling.durability / 100) / totalCoolingPower * 100).toFixed(0) }}%</span>
                       </div>
                       <div class="flex items-center gap-2 border-t border-cyan-500/15 pt-1.5">
                         <span class="text-text-muted cursor-help" v-tooltip="t('rigManage.coolingDetail.durabilityTip')">{{ t('rigManage.coolingDetail.durabilityLabel') }}</span>
                         <div class="flex-1 h-1.5 bg-black/30 rounded-full overflow-hidden">
                           <div class="h-full rounded-full transition-all" :class="cooling.durability < 30 ? 'bg-status-danger' : cooling.durability < 60 ? 'bg-status-warning' : 'bg-cyan-400'" :style="{ width: `${cooling.durability}%` }"></div>
                         </div>
                         <span class="font-mono" :class="cooling.durability < 30 ? 'text-status-danger' : cooling.durability < 60 ? 'text-status-warning' : 'text-cyan-400'">{{ cooling.durability.toFixed(1) }}%</span>
                       </div>
                       <div v-if="rig?.is_active" class="flex justify-between border-t border-cyan-500/15 pt-1.5 cursor-help" v-tooltip="t('rigManage.coolingDetail.estimatedLifeDetail')">
                         <span class="text-text-muted">⏱️ {{ t('rigManage.coolingDetail.estimatedLife') }}</span>
                         <span class="font-mono" :class="cooling.durability < 30 ? 'text-status-danger' : 'text-cyan-300'">{{ estimateCoolingLife(cooling) }}</span>
                       </div>
                    </div>
                  </div>
                </div>
                <!-- Installed Boosts -->
                <div v-if="installedBoosts.length > 0" class="space-y-2">
                  <div v-for="boost in installedBoosts" :key="boost.id" class="relative overflow-hidden rounded-lg border shadow-sm transition-all" :class="[getBoostTierClasses(boost.tier).bg, getBoostTierClasses(boost.tier).border, getBoostTierClasses(boost.tier).glow]">
                    <div class="flex items-center justify-between px-3 py-2.5">
                      <div class="flex items-center gap-2.5 min-w-0 flex-1">
                        <span class="text-xl shrink-0">{{ getBoostIcon(boost.boost_type) }}</span>
                        <div class="min-w-0 flex-1">
                          <div class="font-semibold text-sm truncate" :class="getBoostTierClasses(boost.tier).text">{{ getBoostName(boost.boost_item_id, boost.name) }} <span v-if="boost.stack_count > 1" class="text-[10px] bg-white/10 px-1 rounded">x{{ boost.stack_count }}</span></div>
                          <div class="text-xs font-mono font-bold" :class="boost.boost_type === 'overclock' || boost.boost_type === 'hashrate' ? 'text-status-success' : 'text-cyan-400'">{{ getBoostEffectText(boost) }}</div>
                          <div v-if="boost.boost_type === 'coolant_injection' && rig?.is_active && getCoolantImpactText(boost)" v-tooltip="getCoolantImpactTooltip(boost)" class="text-[10px] font-mono text-cyan-300/80 mt-0.5 cursor-help">{{ getCoolantImpactText(boost) }}</div>
                          <div v-else-if="boost.boost_type !== 'coolant_injection' && getBoostImpactText(boost)" class="text-[10px] font-mono text-text-muted/70 mt-0.5">{{ getBoostImpactText(boost) }}</div>
                        </div>
                      </div>
                      <div class="flex items-center gap-2 shrink-0 ml-2">
                         <div class="text-right min-w-[60px]"><div class="font-mono text-sm font-bold" :class="boost.remaining_seconds < 300 ? 'text-status-danger' : getBoostTierClasses(boost.tier).text">{{ formatTime(boost.remaining_seconds) }}</div></div>
                         <button @click="requestDestroyBoost(boost)" :disabled="rig.is_active || processing" class="p-1.5 rounded-lg text-status-danger/50 hover:text-status-danger hover:bg-status-danger/10"><svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" /></svg></button>
                      </div>
                    </div>
                    <div class="h-1 w-full bg-black/20"><div class="h-full transition-all duration-1000 rounded-r-full" :class="getTimeBarColor(getBoostTimePercent(boost))" :style="{ width: `${getBoostTimePercent(boost)}%` }"></div></div>
                  </div>
                </div>
              </div>

              <!-- Available Inventory -->
              <div v-if="(installedCooling.length > 0 || installedBoosts.length > 0) && (coolingItems.length > 0 || moddedCoolingItems.length > 0 || boostItems.length > 0)" class="border-t border-border my-2"></div>
              
              <div v-if="coolingItems.length === 0 && moddedCoolingItems.length === 0 && boostItems.length === 0 && installedCooling.length === 0 && installedBoosts.length === 0" class="text-center py-8 border border-dashed border-border rounded-lg">
                <div class="text-4xl mb-3 opacity-50">📦</div>
                <p class="text-text-muted text-sm">{{ t('rigManage.noItemsInInventory', 'No tienes items') }}</p>
                <button class="mt-2 text-xs text-accent-primary hover:underline">{{ t('rigManage.buyInMarket', 'Ir al Market') }}</button>
              </div>

              <div v-else class="space-y-3">
                 <div v-if="coolingItems.length > 0 || moddedCoolingItems.length > 0" class="space-y-2">
                   <h4 class="text-xs font-bold text-text-muted uppercase tracking-wider">{{ t('rigManage.availableCooling') }}</h4>
                   <!-- Unmodded cooling -->
                   <div v-for="item in coolingItems" :key="item.id" class="flex items-center justify-between w-full p-2 rounded-lg border bg-bg-tertiary" :class="[getTierBg(item.tier), !canInstallCoolingTier(item.tier) ? 'opacity-50' : '']">
                     <div class="flex items-center gap-2">
                       <span class="text-xl">❄️</span>
                       <div>
                         <div class="font-medium text-sm" :class="getTierColor(item.tier)">{{ getCoolingName(item.id) }}</div>
                         <div class="text-[10px] text-text-muted">❄️-{{ item.cooling_power }}° • x{{ item.quantity }}</div>
                         <div v-if="!canInstallCoolingTier(item.tier)" class="text-[9px] text-rose-400">{{ t('slotTier.tierRequired', { tier: item.tier }) }}</div>
                       </div>
                     </div>
                     <button @click="requestInstallCooling(item)" :disabled="rig.is_active || processing || !canInstallCoolingTier(item.tier)" class="px-2 py-1 rounded text-xs font-medium bg-cyan-500 text-white hover:bg-cyan-400 disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:bg-cyan-500">{{ t('rigManage.install') }}</button>
                   </div>
                   <!-- Modded cooling -->
                   <div v-for="item in moddedCoolingItems" :key="'modded-' + item.player_cooling_item_id" class="flex items-center justify-between w-full p-2 rounded-lg border bg-bg-tertiary" :class="[getTierBg(item.tier), !canInstallCoolingTier(item.tier) ? 'opacity-50' : '']">
                     <div class="flex items-center gap-2">
                       <span class="text-xl">❄️</span>
                       <div>
                         <div class="font-medium text-sm flex items-center gap-1" :class="getTierColor(item.tier)">
                           {{ getCoolingName(item.cooling_item_id, item.name) }}
                           <span class="px-1 py-0.5 rounded text-[9px] bg-fuchsia-500/30 text-fuchsia-300">🧩{{ item.mod_slots_used }}</span>
                         </div>
                         <div class="text-[10px] text-text-muted">❄️-{{ item.effective_cooling_power.toFixed(1) }}° ⚡{{ item.effective_energy_cost.toFixed(1) }}/t</div>
                         <div v-if="!canInstallCoolingTier(item.tier)" class="text-[9px] text-rose-400">{{ t('slotTier.tierRequired', { tier: item.tier }) }}</div>
                       </div>
                     </div>
                     <button @click="requestInstallModdedCooling(item)" :disabled="rig.is_active || processing || !canInstallCoolingTier(item.tier)" class="px-2 py-1 rounded text-xs font-medium bg-fuchsia-500 text-white hover:bg-fuchsia-400 disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:bg-fuchsia-500">{{ t('rigManage.install') }}</button>
                   </div>
                 </div>
                 <div v-if="boostItems.length > 0" class="space-y-2">
                   <h4 class="text-xs font-bold text-text-muted uppercase tracking-wider">{{ t('rigManage.availableBoosts') }}</h4>
                   <div v-for="boost in boostItems" :key="boost.boost_id" class="flex items-center justify-between w-full p-2 rounded-lg border bg-bg-tertiary" :class="getTierBg(boost.tier)">
                     <div class="flex items-center gap-2">
                       <span class="text-xl">{{ getBoostIcon(boost.boost_type) }}</span>
                       <div>
                         <div class="font-medium text-sm" :class="getTierColor(boost.tier)">{{ getBoostName(boost.boost_id, boost.name) }}</div>
                         <div class="text-[10px] text-text-muted">{{ getBoostEffectText(boost) }} • x{{ boost.quantity }}</div>
                       </div>
                     </div>
                     <button @click="requestInstallBoost(boost)" :disabled="rig.is_active || processing" class="px-2 py-1 rounded text-xs font-medium bg-amber-500 text-white hover:bg-amber-400 disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:bg-amber-500">{{ t('rigManage.install') }}</button>
                   </div>
                 </div>
              </div>
            </div>

            <!-- RIGHT COLUMN: Firmware Upgrades -->
            <div class="space-y-4">
              <div class="flex items-center justify-between border-b border-border pb-2 mb-2">
                <h3 class="text-xs font-bold text-text-muted uppercase tracking-wider flex items-center gap-2">
                  <span>⬆️</span> {{ t('rigManage.systemFirmware') }}
                </h3>
                <span class="text-[10px] text-amber-400 font-mono" v-if="rigUpgrades">{{ t('rigManage.maxLv') }} {{ rigUpgrades.max_level }}</span>
              </div>

              <!-- Warning if rig is active -->
              <div v-if="rig.is_active" class="p-3 rounded-lg bg-status-warning/10 border border-status-warning/30 text-status-warning text-sm">
                {{ t('rigManage.stopToUpgrade') }}
              </div>

              <!-- Upgrades List -->
              <div v-if="rigUpgrades" class="space-y-3">
                 <!-- Hashrate -->
                 <div class="p-3 rounded-lg border border-amber-500/30 bg-amber-500/5">
                   <div class="flex items-center justify-between">
                     <div class="flex items-center gap-2"><span class="text-xl">⚡</span><div><h4 class="font-medium text-amber-400 text-sm">{{ t('rigManage.hashrate') }}</h4><div class="text-[10px] text-text-muted">{{ t('rigManage.miningSpeed') }}</div></div></div>
                     <div class="text-right">
                       <div class="font-mono text-amber-400 text-sm">{{ t('rigManage.lv') }} {{ rigUpgrades.hashrate.current_level }}</div>
                       <div class="font-mono text-xs text-status-success cursor-help" v-tooltip="t('rigManage.tooltips.upgradeHashBonus', { value: rigUpgrades.hashrate.current_bonus, abs: (baseHashrate * rigUpgrades.hashrate.current_bonus / 100).toFixed(1) })">+{{ rigUpgrades.hashrate.current_bonus }}% <span class="opacity-70">(+{{ (baseHashrate * rigUpgrades.hashrate.current_bonus / 100).toFixed(1) }} Hash)</span></div>
                     </div>
                   </div>
                   <div v-if="rigUpgrades.hashrate.can_upgrade" class="flex items-center justify-between mt-2 pt-2 border-t border-white/5">
                     <div class="text-xs text-text-muted">→ {{ t('rigManage.lv') }} {{ rigUpgrades.hashrate.current_level + 1 }}: <span class="text-status-success cursor-help" v-tooltip="t('rigManage.tooltips.upgradeHashBonus', { value: rigUpgrades.hashrate.next_bonus, abs: (baseHashrate * rigUpgrades.hashrate.next_bonus / 100).toFixed(1) })">+{{ rigUpgrades.hashrate.next_bonus }}% (+{{ (baseHashrate * rigUpgrades.hashrate.next_bonus / 100).toFixed(1) }} Hash)</span></div>
                     <button @click="requestUpgrade('hashrate')" :disabled="rig.is_active || processing || (authStore.player?.crypto_balance ?? 0) < rigUpgrades.hashrate.next_cost" class="px-2 py-1 rounded text-xs font-medium bg-amber-500 text-black hover:bg-amber-400 flex items-center gap-1 disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:bg-amber-500"><span>💎</span> {{ formatCrypto(rigUpgrades.hashrate.next_cost) }}</button>
                   </div>
                   <div v-else class="text-center text-xs text-text-muted mt-2">{{ t('rigManage.maxLevelReachedShort') }}</div>
                 </div>

                 <!-- Efficiency -->
                 <div class="p-3 rounded-lg border border-emerald-500/30 bg-emerald-500/5">
                   <div class="flex items-center justify-between">
                     <div class="flex items-center gap-2"><span class="text-xl">🔋</span><div><h4 class="font-medium text-emerald-400 text-sm">{{ t('rigManage.efficiency') }}</h4><div class="text-[10px] text-text-muted">{{ t('rigManage.powerUsage') }}</div></div></div>
                     <div class="text-right">
                       <div class="font-mono text-emerald-400 text-sm">{{ t('rigManage.lv') }} {{ rigUpgrades.efficiency.current_level }}</div>
                       <div class="font-mono text-xs text-status-success cursor-help" v-tooltip="t('rigManage.tooltips.upgradeEffBonus', { value: rigUpgrades.efficiency.current_bonus, abs: (basePower * rigUpgrades.efficiency.current_bonus / 100).toFixed(1) })">-{{ rigUpgrades.efficiency.current_bonus }}% <span class="opacity-70">(-{{ (basePower * rigUpgrades.efficiency.current_bonus / 100).toFixed(1) }} W)</span></div>
                     </div>
                   </div>
                   <div v-if="rigUpgrades.efficiency.can_upgrade" class="flex items-center justify-between mt-2 pt-2 border-t border-white/5">
                     <div class="text-xs text-text-muted">→ {{ t('rigManage.lv') }} {{ rigUpgrades.efficiency.current_level + 1 }}: <span class="text-status-success cursor-help" v-tooltip="t('rigManage.tooltips.upgradeEffBonus', { value: rigUpgrades.efficiency.next_bonus, abs: (basePower * rigUpgrades.efficiency.next_bonus / 100).toFixed(1) })">-{{ rigUpgrades.efficiency.next_bonus }}% (-{{ (basePower * rigUpgrades.efficiency.next_bonus / 100).toFixed(1) }} W)</span></div>
                     <button @click="requestUpgrade('efficiency')" :disabled="rig.is_active || processing || (authStore.player?.crypto_balance ?? 0) < rigUpgrades.efficiency.next_cost" class="px-2 py-1 rounded text-xs font-medium bg-emerald-500 text-black hover:bg-emerald-400 flex items-center gap-1 disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:bg-emerald-500"><span>💎</span> {{ formatCrypto(rigUpgrades.efficiency.next_cost) }}</button>
                   </div>
                   <div v-else class="text-center text-xs text-text-muted mt-2">{{ t('rigManage.maxLevelReachedShort') }}</div>
                 </div>

                 <!-- Thermal -->
                 <div class="p-3 rounded-lg border border-cyan-500/30 bg-cyan-500/5">
                   <div class="flex items-center justify-between">
                     <div class="flex items-center gap-2"><span class="text-xl">❄️</span><div><h4 class="font-medium text-cyan-400 text-sm">{{ t('rigManage.thermal') }}</h4><div class="text-[10px] text-text-muted">{{ t('rigManage.baseHeat') }}</div></div></div>
                     <div class="text-right">
                       <div class="font-mono text-cyan-400 text-sm">{{ t('rigManage.lv') }} {{ rigUpgrades.thermal.current_level }}</div>
                       <div v-if="rigUpgrades.thermal.current_bonus > 0" class="font-mono text-xs text-status-success cursor-help" v-tooltip="t('rigManage.tooltips.upgradeThermalBonus', { value: rigUpgrades.thermal.current_bonus, abs: (rigBaseHeat * rigUpgrades.thermal.current_bonus / 100).toFixed(1) })">-{{ rigUpgrades.thermal.current_bonus }}% <span class="opacity-70">(-{{ (rigBaseHeat * rigUpgrades.thermal.current_bonus / 100).toFixed(1) }}°)</span></div>
                     </div>
                   </div>
                   <div v-if="rigUpgrades.thermal.can_upgrade" class="flex items-center justify-between mt-2 pt-2 border-t border-white/5">
                     <div class="text-xs text-text-muted">→ {{ t('rigManage.lv') }} {{ rigUpgrades.thermal.current_level + 1 }}: <span class="text-status-success cursor-help" v-tooltip="t('rigManage.tooltips.upgradeThermalBonus', { value: rigUpgrades.thermal.next_bonus, abs: (rigBaseHeat * rigUpgrades.thermal.next_bonus / 100).toFixed(1) })">-{{ rigUpgrades.thermal.next_bonus }}% (-{{ (rigBaseHeat * rigUpgrades.thermal.next_bonus / 100).toFixed(1) }}°)</span></div>
                     <button @click="requestUpgrade('thermal')" :disabled="rig.is_active || processing || (authStore.player?.crypto_balance ?? 0) < rigUpgrades.thermal.next_cost" class="px-2 py-1 rounded text-xs font-medium bg-cyan-500 text-black hover:bg-cyan-400 flex items-center gap-1 disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:bg-cyan-500"><span>💎</span> {{ formatCrypto(rigUpgrades.thermal.next_cost) }}</button>
                   </div>
                   <div v-else class="text-center text-xs text-text-muted mt-2">{{ t('rigManage.maxLevelReachedShort') }}</div>
                 </div>
              </div>

              <!-- Available Crypto Balance -->
              <div v-if="rigUpgrades" class="text-center text-xs text-text-muted pt-2 border-t border-white/5">
                {{ t('rigManage.yourCrypto') }}: <span class="text-amber-400 font-mono font-bold">💎 {{ formatCrypto(authStore.player?.crypto_balance ?? 0) }}</span>
              </div>
            </div>

            <!-- FOOTER: Maintenance -->
            <div class="pt-4 border-t border-border mt-2 space-y-3">
               <h3 class="text-xs font-bold text-text-muted uppercase tracking-wider flex items-center gap-2"><span>🛠️</span> {{ t('rigManage.maintenanceZone') }}</h3>
               
               <div class="grid grid-cols-1 gap-4">
                 <!-- Repair Box -->
                 <div v-if="nextRepairInfo" class="p-3 rounded-lg border border-border bg-bg-primary/30 flex items-center justify-between gap-4">
                   <div class="flex items-center gap-3">
                     <div class="bg-bg-tertiary p-2 rounded">
                       <div class="text-[10px] text-text-muted">{{ t('rigManage.repairsUsedLabel') }}</div>
                       <div class="font-mono font-bold text-sm">{{ timesRepaired }}/{{ MAX_REPAIRS }}</div>
                     </div>
                     <div>
                       <div class="text-xs text-text-muted">{{ t('rigManage.costLabel') }}: <span class="text-amber-400 font-mono">{{ nextRepairInfo.maxCost }} GC</span></div>
                       <div class="text-xs text-text-muted">{{ t('rigManage.bonusLabel') }}: <span class="text-status-success font-mono">+{{ nextRepairInfo.bonus }}%</span></div>
                     </div>
                   </div>
                   <button @click="requestRepair" :disabled="!canRepair || !canAffordRepair || processing || isAtMaxCondition" class="px-4 py-2 rounded-lg text-sm font-medium transition-colors disabled:opacity-50 bg-status-warning text-white hover:bg-status-warning/80">
                     {{ isAtMaxCondition ? t('rigManage.alreadyAtMax') : !canAffordRepair ? t('rigManage.insufficientFunds') : t('rigManage.repair') }}
                   </button>
                 </div>
                 
                 <div v-else class="p-3 rounded-lg border border-status-danger/30 bg-status-danger/5 flex items-center justify-center text-status-danger text-sm">
                   {{ t('rigManage.maxRepairsReached') }}
                 </div>

                 <!-- Delete Zone -->
                 <div class="p-3 rounded-lg border border-status-danger/20 bg-status-danger/5">
                   <div class="flex items-center justify-between gap-4">
                     <div>
                       <div class="text-xs text-status-danger/80 max-w-[200px]">{{ t('rigManage.deleteWarning') }}</div>
                       <div class="text-[10px] text-status-warning mt-1">{{ t('slots.deleteWillConsumeUse', 'Quitar este rig consumir\u00e1 1 uso del slot.') }}</div>
                     </div>
                     <button @click="requestDelete" :disabled="rig.is_active || processing" class="px-3 py-1.5 rounded-lg text-xs font-medium bg-status-danger/10 text-status-danger hover:bg-status-danger/20 border border-status-danger/20">
                       {{ t('rigManage.deleteRig') }}
                     </button>
                   </div>
                 </div>
               </div>
            </div>

          </div>
        </div>
      </div>

      <!-- Confirmation Dialog -->
      <div
        v-if="showConfirm && confirmAction"
        class="absolute inset-0 flex items-center justify-center bg-black/50 z-10"
      >
        <div class="bg-bg-secondary rounded-xl p-6 max-w-sm w-full mx-4 border border-border animate-fade-in">
          <div class="text-center mb-4">
            <div class="text-4xl mb-3">
              {{ confirmAction.type === 'install' ? '❄️' : confirmAction.type === 'boost' ? '🚀' : confirmAction.type === 'repair' ? '🔧' : confirmAction.type === 'upgrade' ? '⬆️' : confirmAction.type === 'patch' ? '🩹' : confirmAction.type === 'destroy_cooling' ? '❄️' : confirmAction.type === 'destroy_boost' ? '🚀' : '🗑️' }}
            </div>
            <h3 class="text-lg font-bold mb-1">
              {{ confirmAction.type === 'install' ? t('rigManage.confirmInstall') : confirmAction.type === 'boost' ? t('rigManage.confirmApplyBoost', 'Aplicar Boost') : confirmAction.type === 'repair' ? t('rigManage.confirmRepair') : confirmAction.type === 'upgrade' ? t('rigManage.confirmUpgrade', 'Confirmar Mejora') : confirmAction.type === 'patch' ? t('rigManage.confirmPatch', 'Aplicar Parche') : (confirmAction.type === 'destroy_cooling' || confirmAction.type === 'destroy_boost') ? t('rigManage.confirmDestroy', 'Destruir Item') : t('rigManage.confirmDelete') }}
            </h3>
            <p class="text-text-muted text-sm">{{ t('inventory.confirm.areYouSure') }}</p>
          </div>

          <div class="bg-bg-primary rounded-lg p-4 mb-4">
            <template v-if="confirmAction.type === 'install'">
              <div class="flex items-center justify-between mb-2">
                <span class="text-text-muted text-sm">{{ t('rigManage.cooling') }}</span>
                <span class="font-medium text-cyan-400">{{ confirmAction.data.coolingName }}</span>
              </div>
              <div class="flex items-center justify-between">
                <span class="text-text-muted text-sm">{{ t('rigManage.power') }}</span>
                <span class="font-bold text-cyan-400">-{{ confirmAction.data.coolingPower }}°</span>
              </div>
            </template>
            <template v-else-if="confirmAction.type === 'boost'">
              <div class="flex items-center justify-between mb-2">
                <span class="text-text-muted text-sm">Boost</span>
                <span class="font-medium text-amber-400">{{ confirmAction.data.boostName }}</span>
              </div>
              <div class="flex items-center justify-between mb-2">
                <span class="text-text-muted text-sm">{{ t('rigManage.effect', 'Efecto') }}</span>
                <span class="font-bold text-amber-400">{{ confirmAction.data.boostEffect }}</span>
              </div>
              <div class="flex items-center justify-between">
                <span class="text-text-muted text-sm">{{ t('rigManage.duration', 'Duración') }}</span>
                <span class="font-bold text-amber-400">{{ confirmAction.data.boostDuration }} min</span>
              </div>
            </template>
            <template v-else-if="confirmAction.type === 'repair' && nextRepairInfo">
              <div class="flex items-center justify-between mb-2">
                <span class="text-text-muted text-sm">{{ t('rigManage.cost') }}</span>
                <span class="font-bold text-status-warning">{{ nextRepairInfo.maxCost }} {{ repairCurrencySymbol }}</span>
              </div>
              <div class="flex items-center justify-between mb-2">
                <span class="text-text-muted text-sm">{{ t('rigManage.newMax', 'Nuevo max') }}</span>
                <span class="font-bold text-status-success">{{ nextRepairInfo.newMax }}%</span>
              </div>
              <div class="flex items-center justify-between mb-2">
                <span class="text-text-muted text-sm">{{ t('rigManage.bonus', 'Bonus') }}</span>
                <span class="font-bold text-status-success">+{{ nextRepairInfo.bonus }}%</span>
              </div>
              <div class="flex items-center justify-between">
                <span class="text-text-muted text-sm">{{ t('rigManage.repairNumber', 'Reparacion') }}</span>
                <span class="font-bold">{{ nextRepairInfo.number }}/{{ MAX_REPAIRS }}</span>
              </div>
            </template>
            <template v-else-if="confirmAction.type === 'upgrade'">
              <div class="flex items-center justify-between mb-2">
                <span class="text-text-muted text-sm">{{ t('rigManage.upgradeType', 'Mejora') }}</span>
                <span class="font-medium text-amber-400">
                  {{ confirmAction.data.upgradeType === 'hashrate' ? 'Hashrate' : confirmAction.data.upgradeType === 'efficiency' ? 'Eficiencia' : 'Térmica' }}
                </span>
              </div>
              <div class="flex items-center justify-between mb-2">
                <span class="text-text-muted text-sm">{{ t('rigManage.newLevel', 'Nuevo nivel') }}</span>
                <span class="font-bold text-amber-400">Lv {{ confirmAction.data.upgradeNewLevel }}</span>
              </div>
              <div class="flex items-center justify-between">
                <span class="text-text-muted text-sm">{{ t('rigManage.cost') }}</span>
                <span class="font-bold text-amber-400">💎 {{ formatCrypto(confirmAction.data.upgradeCost ?? 0) }}</span>
              </div>
            </template>
            <template v-else-if="confirmAction.type === 'patch'">
              <div class="flex items-center justify-between mb-2">
                <span class="text-text-muted text-sm">{{ t('rigManage.patchCost') }}</span>
                <span class="font-bold text-fuchsia-400">1 🩹 {{ t('market.patch.name', 'Rig Patch') }}</span>
              </div>
              <div class="flex items-center justify-between mb-2">
                <span class="text-text-muted text-sm">{{ t('rigManage.conditionBonus') }}</span>
                <span class="font-bold text-status-success">+35%</span>
              </div>
              <div class="flex items-center justify-between mb-2">
                <span class="text-text-muted text-sm">Hashrate</span>
                <span class="font-bold text-status-danger">-{{ nextPatchHashPenalty }}% (total)</span>
              </div>
              <div class="flex items-center justify-between">
                <span class="text-text-muted text-sm">{{ t('rigManage.consumption') }}</span>
                <span class="font-bold text-status-danger">+{{ nextPatchConsumptionPenalty }}% (total)</span>
              </div>
            </template>
            <template v-else-if="confirmAction.type === 'destroy_cooling'">
              <p class="text-sm text-status-danger mb-3">{{ t('rigManage.destroyWarning', 'Este item será destruido permanentemente y no podrá recuperarse.') }}</p>
              <div class="flex items-center justify-between mb-2">
                <span class="text-text-muted text-sm">{{ t('rigManage.cooling') }}</span>
                <span class="font-medium text-cyan-400">{{ confirmAction.data.coolingName }}</span>
              </div>
              <div class="flex items-center justify-between mb-2">
                <span class="text-text-muted text-sm">{{ t('rigManage.power') }}</span>
                <span class="font-bold text-cyan-400">-{{ confirmAction.data.coolingPower }}°</span>
              </div>
              <div class="flex items-center justify-between">
                <span class="text-text-muted text-sm">{{ t('rigManage.durability', 'Durabilidad') }}</span>
                <span class="font-bold text-cyan-400">{{ confirmAction.data.coolingDurability?.toFixed(0) }}%</span>
              </div>
            </template>
            <template v-else-if="confirmAction.type === 'destroy_boost'">
              <p class="text-sm text-status-danger mb-3">{{ t('rigManage.destroyWarning', 'Este item será destruido permanentemente y no podrá recuperarse.') }}</p>
              <div class="flex items-center justify-between mb-2">
                <span class="text-text-muted text-sm">Boost</span>
                <span class="font-medium text-amber-400">{{ confirmAction.data.boostName }}</span>
              </div>
              <div class="flex items-center justify-between mb-2">
                <span class="text-text-muted text-sm">{{ t('rigManage.effect', 'Efecto') }}</span>
                <span class="font-bold text-amber-400">{{ confirmAction.data.boostEffect }}</span>
              </div>
              <div class="flex items-center justify-between">
                <span class="text-text-muted text-sm">{{ t('rigManage.remaining', 'Restante') }}</span>
                <span class="font-bold text-amber-400">{{ formatTime(confirmAction.data.boostRemainingSeconds ?? 0) }}</span>
              </div>
            </template>
            <template v-else-if="confirmAction.type === 'delete'">
              <p class="text-sm text-status-danger">{{ t('rigManage.deleteConfirmText') }}</p>
            </template>
          </div>

          <div class="flex gap-3">
            <button
              @click="cancelConfirm"
              class="flex-1 py-2.5 rounded-lg font-medium bg-bg-tertiary hover:bg-bg-tertiary/80 transition-colors"
            >
              {{ t('common.cancel') }}
            </button>
            <button
              @click="confirmUse"
              :disabled="processing"
              class="flex-1 py-2.5 rounded-lg font-medium transition-colors disabled:opacity-50"
              :class="confirmAction.type === 'delete' || confirmAction.type === 'destroy_cooling' || confirmAction.type === 'destroy_boost'
                ? 'bg-status-danger text-white hover:bg-status-danger/80'
                : confirmAction.type === 'repair'
                  ? 'bg-status-warning text-white hover:bg-status-warning/80'
                  : confirmAction.type === 'boost'
                    ? 'bg-amber-500 text-white hover:bg-amber-400'
                    : confirmAction.type === 'upgrade'
                      ? 'bg-amber-500 text-black hover:bg-amber-400'
                      : confirmAction.type === 'patch'
                        ? 'bg-fuchsia-500 text-white hover:bg-fuchsia-400'
                        : 'bg-cyan-500 text-white hover:bg-cyan-400'"
            >
              {{ (confirmAction.type === 'destroy_cooling' || confirmAction.type === 'destroy_boost') ? t('rigManage.destroy', 'Destruir') : t('common.confirm') }}
            </button>
          </div>
        </div>
      </div>

      <!-- Repair Minigame Overlay -->
      <div
        v-if="showMinigame"
        class="absolute inset-0 flex items-center justify-center bg-black/70 z-20"
      >
        <div class="bg-bg-secondary rounded-xl p-6 max-w-md w-full mx-4 border border-border">
          <RepairMinigame
            @complete="handleMinigameComplete"
          />
        </div>
      </div>

      <!-- Processing Modal -->
      <div
        v-if="showProcessingModal"
        class="absolute inset-0 flex items-center justify-center bg-black/70 z-20"
      >
        <div class="bg-bg-secondary rounded-xl p-6 max-w-sm w-full mx-4 border border-border animate-fade-in">
          <div v-if="processingStatus === 'processing'" class="text-center">
            <div class="w-12 h-12 mx-auto mb-4 border-2 border-accent-primary border-t-transparent rounded-full animate-spin"></div>
            <p class="text-text-muted">{{ t('common.processing') }}</p>
          </div>

          <div v-else-if="processingStatus === 'error'" class="text-center">
            <div class="w-12 h-12 mx-auto mb-4 bg-status-danger/20 rounded-full flex items-center justify-center">
              <svg class="w-6 h-6 text-status-danger" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </div>
            <p class="text-status-danger font-medium mb-2">{{ t('common.error') }}</p>
            <p class="text-text-muted text-sm mb-4">{{ processingError }}</p>
            <button
              @click="closeProcessingModal"
              class="w-full py-2 rounded-lg font-medium bg-bg-tertiary hover:bg-bg-tertiary/80 transition-colors"
            >
              {{ t('common.close') }}
            </button>
          </div>
        </div>
      </div>
    </div>
  </Teleport>
</template>
