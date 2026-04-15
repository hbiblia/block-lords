<script setup lang="ts">
import { ref, onMounted, onUnmounted, computed, nextTick, watch, type Component } from 'vue';
import { useAuthStore } from '@/stores/auth';
import { useMiningStore } from '@/stores/mining';
import { useSoloMiningStore } from '@/stores/solo-mining';
import { useInventoryStore } from '@/stores/inventory';
import { useMarketStore } from '@/stores/market';
import { usePendingBlocksStore } from '@/stores/pendingBlocks';
import { useMissionsStore } from '@/stores/missions';
import { useStreakStore } from '@/stores/streak';
import type { PendingBlock } from '@/stores/pendingBlocks';
import { useWakeLock } from '@/composables/useWakeLock';
import {
  Pickaxe, Coins, Gem, Zap, Snowflake, Shield, Battery, Sparkles,
  Rocket, Puzzle, Settings, Crown, Clover, CheckCircle, Medal, Flame,
  FlaskConical, Wrench, Cpu, Cable, Droplets, Disc, RotateCw, Dna,
  Thermometer, Network, Eye, Moon,
  Users, Package, Lock, Globe, Timer, Search, CreditCard, BookOpen, Sticker, Pause,
  Inbox, ArrowDownToLine, Layers, Trash2, Archive
} from 'lucide-vue-next';

import { playSound } from '@/utils/sounds';
import RigStatsModal from '@/components/RigStatsModal.vue';
import StoryModal from '@/components/StoryModal.vue';
import { storyChapters } from '@/data/storyChapters';
import {
  getPlayerInventory, getRigCooling, getRigPower,
  getPlayerBoosts, getRigBoosts,
  removeCoolingFromRig, removeBoostFromRig, removePowerFromRig,
  grantPlayerXp,
  createStake, claimStakingRewards, checkStakeStatus,
  activateLuckyBoost,
  exchangeCryptoToGamecoin, exchangeCryptoToRon, getExchangeRates,
  redeemPrepaidCard, useExpPack, applyRigPatch
} from '@/utils/api';


// Stores
const authStore = useAuthStore();
const miningStore = useMiningStore();
const soloMiningStore = useSoloMiningStore();
const inventoryStore = useInventoryStore();
const marketStore = useMarketStore();
const pendingBlocksStore = usePendingBlocksStore();
const missionsStore = useMissionsStore();
const streakStore = useStreakStore();
const missionsClaimable = computed(() => (missionsStore.claimableCount || 0) + (streakStore.canClaim ? 1 : 0));

function openMissions() {
  playSound('click');
  window.dispatchEvent(new CustomEvent('open-missions'));
}

// UI State
const booted = ref(false);
const activeTab = ref<'fleet' | 'staking' | 'history' | 'inventory' | 'market' | 'exchange'>('fleet');
const fleetMode = ref<'rigs' | 'forge' | 'inbox' | 'inventory' | 'market' | 'exchange'>('rigs');
const menuOpen = ref(false);
const selectedInboxBlock = ref<PendingBlock | null>(null);

// Inventory fleet mode state
const selectedInvItem = ref<{ type: string; id: string; data: any } | null>(null);
const invCategory = ref<'all' | 'rigs' | 'cooling' | 'cards' | 'boosts' | 'materials' | 'patches' | 'exp'>('all');
const invActionLoading = ref(false);

function setFleetMode(mode: 'rigs' | 'forge' | 'inbox' | 'inventory' | 'market' | 'exchange') {
  playSound('click');
  if (fleetMode.value === mode) {
    fleetMode.value = 'rigs';
    selectedRecipe.value = null;
    selectedInboxBlock.value = null;
    selectedInvItem.value = null;
    return;
  }
  fleetMode.value = mode;
  selectedRigId.value = null;
  selectedRecipe.value = null;
  selectedInboxBlock.value = null;
  selectedInvItem.value = null;
  if (mode === 'inbox') {
    pendingBlocksStore.fetchPendingBlocks();
  }
  if (mode === 'inventory') {
    inventoryStore.fetchInventory();
  }
  if (mode === 'market') {
    loadMarketData();
  }
  if (mode === 'exchange') {
    loadExchangeRates();
  }
}

// Story Modal
const showStory = ref(false);
const storyChapter = ref<typeof storyChapters[number] | null>(null);

function triggerStory(level: number) {
  const chapter = storyChapters.find(c => c.level === level);
  if (!chapter) return;
  const seen = JSON.parse(localStorage.getItem('story_seen') || '[]') as number[];
  if (seen.includes(level)) return;
  storyChapter.value = chapter;
  showStory.value = true;
}

function closeStory() {
  if (storyChapter.value) {
    const seen = JSON.parse(localStorage.getItem('story_seen') || '[]') as number[];
    if (!seen.includes(storyChapter.value.level)) {
      seen.push(storyChapter.value.level);
      localStorage.setItem('story_seen', JSON.stringify(seen));
    }
  }
  showStory.value = false;
  storyChapter.value = null;
}
const menuModalOpen = ref(false);
const menuModalTab = ref<'inventory' | 'market' | 'exchange'>('inventory');

function selectMenu(tab: typeof activeTab.value) {
  activeTab.value = tab;
  menuOpen.value = false;
}

function closeMenu(e: MouseEvent) {
  const target = e.target as HTMLElement;
  if (!target.closest('.h-menu')) menuOpen.value = false;
}

// ── INVENTORY / MARKET / EXCHANGE ──
const inventoryLoading = ref(false);
const marketLoading = ref(false);

async function loadInventoryData() {
  if (inventoryStore.loaded) return;
  inventoryLoading.value = true;
  try { await inventoryStore.fetchInventory(); } catch(e) { console.error(e); }
  inventoryLoading.value = false;
}

async function loadMarketData() {
  if (marketStore.catalogsLoaded) return;
  marketLoading.value = true;
  try { await marketStore.loadData(); } catch(e) { console.error(e); }
  marketLoading.value = false;
}

// Market: active category
const marketCategory = ref<'rigs' | 'cooling' | 'cards' | 'boosts' | 'components' | 'exp_packs' | 'crypto'>('rigs');

// Market: buy confirmation
const buyingItem = ref(false);
const buyConfirm = ref<{ show: boolean; type: string; id: string; name: string; price: number; currency: string; result: 'pending' | 'success' | 'error'; message: string }>({ show: false, type: '', id: '', name: '', price: 0, currency: 'gamecoin', result: 'pending', message: '' });

function requestBuy(type: string, id: string, name: string, price: number, currency: string) {
  buyConfirm.value = { show: true, type, id, name, price, currency, result: 'pending', message: '' };
}

async function confirmBuy() {
  const { type, id } = buyConfirm.value;
  buyingItem.value = true;
  try {
    let res: any;
    if (type === 'rig') res = await marketStore.buyRig(id);
    else if (type === 'cooling') res = await marketStore.buyCooling(id);
    else if (type === 'card') res = await marketStore.buyCard(id);
    else if (type === 'boost') res = await marketStore.buyBoost(id);
    else if (type === 'component') res = await marketStore.buyCoolingComponent(id);
    else if (type === 'exp_pack') res = await marketStore.buyExpPack(id);
    else if (type === 'crypto') res = await marketStore.buyCryptoPackage(id);
    if (res?.success) {
      buyConfirm.value.result = 'success';
      buyConfirm.value.message = 'PURCHASE_COMPLETE';
      await authStore.fetchPlayer();
    } else {
      buyConfirm.value.result = 'error';
      buyConfirm.value.message = res?.error || 'PURCHASE_FAILED';
    }
  } catch(e: any) {
    console.error(e);
    buyConfirm.value.result = 'error';
    buyConfirm.value.message = e.message || 'CONNECTION_ERROR';
  }
  buyingItem.value = false;
}

// Exchange
const exchangeRates = ref<any>(null);
const exchangeAmount = ref(0);
const exchangeTarget = ref<'gamecoin' | 'ron'>('gamecoin');
const exchanging = ref(false);

async function loadExchangeRates() {
  try { exchangeRates.value = await getExchangeRates(); } catch(e) { console.error(e); }
}

const exchQuickAmounts = computed(() => {
  if (!exchangeRates.value) return [];
  if (exchangeTarget.value === 'ron') {
    return [1, 5, 10, 50, 100];
  }
  return [100, 500, 1000, 5000, 10000];
});

function setExchQuick(targetAmount: number) {
  if (!exchangeRates.value) return;
  const rate = exchangeTarget.value === 'ron' ? exchangeRates.value.crypto_to_ron : exchangeRates.value.crypto_to_gamecoin;
  if (!rate) return;
  exchangeAmount.value = Math.ceil(targetAmount / rate);
}

async function handleExchange() {
  if (!authStore.player || exchangeAmount.value <= 0) return;
  exchanging.value = true;
  try {
    if (exchangeTarget.value === 'gamecoin') {
      await exchangeCryptoToGamecoin(authStore.player.id, exchangeAmount.value);
    } else {
      await exchangeCryptoToRon(authStore.player.id, exchangeAmount.value);
    }
    await authStore.fetchPlayer();
    exchangeAmount.value = 0;
  } catch(e: any) { console.error(e); alert(e.message || 'Exchange failed'); }
  exchanging.value = false;
}

// Load data when switching to menu tabs
function selectMenuWithLoad(tab: 'inventory' | 'market' | 'exchange') {
  menuModalTab.value = tab;
  menuModalOpen.value = true;
  menuOpen.value = false;
  if (tab === 'inventory') loadInventoryData();
  else if (tab === 'market') loadMarketData();
  else if (tab === 'exchange') loadExchangeRates();
}

function switchModalTab(tab: 'inventory' | 'market' | 'exchange') {
  menuModalTab.value = tab;
  if (tab === 'inventory') loadInventoryData();
  else if (tab === 'market') loadMarketData();
  else if (tab === 'exchange') loadExchangeRates();
}

// Currency display helper
function currencyIcon(c: string): Component {
  if (c === 'ron') return Gem;
  if (c === 'crypto') return Pickaxe;
  return Coins;
}
// Map emoji strings from server data to Lucide components
const emojiToIcon: Record<string, Component> = {
  '\u{1F9F4}': FlaskConical, '\u{1F529}': Wrench, '\u{1F532}': Cpu, '\u3030\uFE0F': Cable,
  '\u{1F9CA}': Snowflake, '\u{1F50B}': Battery, '\u{1FAE7}': Droplets, '\u{1F4BF}': Disc,
  '\u{1F300}': RotateCw, '\u{1F9EC}': Dna, '\u{1F976}': Thermometer, '\u{1F578}\uFE0F': Network,
  '\u{1F52E}': Eye, '\u{1F311}': Moon, '\u26A1': Zap, '\u2744\uFE0F': Snowflake,
  '\u{1F48E}': Gem, '\u2728': Sparkles, '\u{1FA99}': Coins, '\u26CF\uFE0F': Pickaxe,
  '\u{1F6E1}\uFE0F': Shield, '\u{1F680}': Rocket, '\u{1F9E9}': Puzzle, '\u2699\uFE0F': Settings,
  '\u{1F525}': Flame, '\u{1F451}': Crown, '\u{1F340}': Clover, '\u2705': CheckCircle
};
function emojiIcon(emoji: string): Component {
  return emojiToIcon[emoji] || Sparkles;
}

function tierColor(t: string) {
  if (t === 'legendary' || t === 'epic') return 'amber';
  if (t === 'rare') return 'cyan';
  return 'white';
}

const selectedRigId = ref<string | null>(null);
const modeSelectionId = ref<string | null>(null);
const configTab = ref<'status' | 'components'>('status');


// Skill Tree State
const researchPoints = ref(12);
const unlockedNodes = ref<string[]>(['over_1', 'therm_1']);



// Theme
const isLightMode = ref(false);
watch(isLightMode, (v) => {
  document.documentElement.classList.toggle('kawaii-light', v);
}, { immediate: true });

// Modal State
const showRigStats = ref(false);
const showSlotConfirm = ref(false);
const showEjectConfirm = ref(false);
const ejectTarget = ref<{ type: 'cooling' | 'boost' | 'power'; id: string; name: string } | null>(null);
const loadingConfig = ref(false);


// Config Data
const inventory = ref<any>({ cooling: [], boosts: [] });
const installedCooling = ref<any[]>([]);
const installedBoosts = ref<any[]>([]);
const installedPower = ref<any[]>([]);


// Resource Percentages
const formatTime = (seconds: number) => {
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${m}:${s.toString().padStart(2, '0')}`;
};

const formatBoostTime = (seconds: number) => {
  if (seconds >= 3600) {
    const h = Math.floor(seconds / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    return `${h}h ${m}m`;
  }
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${m}m ${s}s`;
};

const energyPct = computed(() => {
  const energy = authStore.player?.energy ?? 0;
  const max = authStore.effectiveMaxEnergy || 100;
  return Math.min(100, (energy / max) * 100);
});

const internetPct = computed(() => {
  const internet = authStore.player?.internet ?? 0;
  const max = authStore.effectiveMaxInternet || 100;
  return Math.min(100, (internet / max) * 100);
});

// Mining Data
const rigs = computed(() => miningStore.rigs);
const currentMiningBlock = computed(() => miningStore.currentMiningBlock);
const effectiveHashrate = computed(() => miningStore.effectiveHashrate);

// Recommended Strategies logic
const strategyTips = computed(() => {
  const tips: Array<{ title: string; desc: string; req?: string; target?: string; type: string }> = [];
  const userHash = miningStore.effectiveHashrate || 0;
  const soloHash = miningStore.soloEffectiveHashrate || 0;
  
  // Pool Strategy
  if (userHash > 0) {
    tips.push({
      title: 'POOL_MINING_PROTOCOL',
      desc: 'Consistent share distribution via network PPLNS.',
      req: 'MIN_HASH: 1 H/s',
      target: 'EST_YIELD: 0.002 - 0.05 GC/hr',
      type: 'info'
    });
  }

  // Solo Strategy
  if (userHash > 5000 || soloHash > 5000) {
    tips.push({
      title: 'SOLO_CAPTURE_STRATEGY',
      desc: 'Direct block reward capture via high-density seed finding.',
      req: 'REC_HASH: > 5000 H/s',
      target: 'EST_YIELD: 1.0 - 50.0 CRYPTO',
      type: 'success'
    });
  } else if (userHash > 1500) {
    tips.push({
      title: 'SOLO_MINING_VIABLE',
      desc: 'Solo protocol is viable but variance remains high.',
      req: 'MIN_HASH: 1000 H/s',
      target: 'EST_YIELD: HIGH_VARIANCE',
      type: 'info'
    });
  }

  return tips.length ? tips : [{ title: 'SYSTEM_AWAITING_DATA', desc: 'No active mining detected. Start units to generate advisory.', req: '', target: '', type: 'info' }];
});

/** JUGABILIDAD: Fleet Mastery Logic **/
const getRigGrade = (rig: any) => {
  const score = (rig.condition + (100 - rig.temperature) + ((rig.hashrate_level || 1) * 20)) / 3;
  if (score > 90) return { label: 'S', color: '#f59e0b' };
  if (score > 75) return { label: 'A', color: '#00ff88' };
  if (score > 50) return { label: 'B', color: '#f59e0b' };
  if (score > 30) return { label: 'C', color: '#ff8800' };
  return { label: 'D', color: '#ff4444' };
};

const getNetProfit = (rig: any) => {
  const hash = miningStore.getRigEffectiveHashrate(rig);
  // Returns number for arithmetic compatibility
  return (hash * 0.00001) - ((rig.rig.power_consumption || 10) * 0.0001);
};



async function handleStartAllHealthy() {
  const healthyRigs = rigs.value.filter(r => !r.is_active && r.condition > 90);
  for (const rig of healthyRigs) {
    try {
      await miningStore.toggleRig(rig.id, 'pool');
    } catch (e) { console.error(e); }
  }
}

/** RESEARCH LOGIC **/
const masteryBranches = [
  {
    id: 'overclock',
    title: 'COMPUTATIONAL_FREQUENCY',
    color: '#ff4444',
    nodes: [
      { id: 'over_1', tier: 1, name: 'CYCLE_OPTIMIZER', desc: '+10% Hashrate per node', cost: 5 },
      { id: 'over_2', tier: 2, name: 'MULTI_THREAD_SCHEDULER', desc: '+25% Processing Depth', cost: 15 },
      { id: 'over_3', tier: 3, name: 'QUANTUM_LOGIC_GATES', desc: '+50% Entropy Speed', cost: 40 }
    ]
  },
  {
    id: 'thermal',
    title: 'CRYOGENIC_REGULATION',
    color: '#f59e0b',
    nodes: [
      { id: 'therm_1', tier: 1, name: 'PASSIVE_HEAT_SINKS', desc: '-5°C Thermal Base', cost: 5 },
      { id: 'therm_2', tier: 2, name: 'FLOW_FLUID_LOOP', desc: '-15°C Under Load', cost: 15 },
      { id: 'therm_3', tier: 3, name: 'PHASE_CHANGE_CORE', desc: 'Immutable Cooling State', cost: 40 }
    ]
  },
  {
    id: 'integrity',
    title: 'STRUCTURAL_STABILITY',
    color: '#00ff88',
    nodes: [
      { id: 'integ_1', tier: 1, name: 'TITANIUM_CHASSIS', desc: '+20% Durability Buffer', cost: 5 },
      { id: 'integ_2', tier: 2, name: 'SELF_HEALING_BUS', desc: 'Auto-repair 0.5%/hr', cost: 15 },
      { id: 'integ_3', tier: 3, name: 'INFINITY_CYCLE', desc: 'No normal wear-and-tear', cost: 40 }
    ]
  }
];

// Forge & Crafting Logic (MASSIVE DATABASE - 100+ Recipes)
const forgeSelection = ref<any[]>([null, null]);
const forgeSearch = ref('');
const forgeActiveCat = ref('MATERIAL');
const forgeLogs = ref<string[]>([]);

// Player level system (from database)
const playerLevel = computed(() => authStore.player?.level ?? 1);
const playerXp = computed(() => authStore.player?.xp ?? 0);
const playerXpNeeded = computed(() => playerLevel.value * 200);
const playerXpPct = computed(() => (playerXp.value / playerXpNeeded.value) * 100);

const forgeTier = computed(() => {
  if (playerLevel.value >= 50) return 5;
  if (playerLevel.value >= 30) return 4;
  if (playerLevel.value >= 15) return 3;
  if (playerLevel.value >= 5) return 2;
  return 1;
});

const forgeRank = computed(() => {
  if (playerLevel.value >= 50) return 'OPERA_OMNIUM';
  if (playerLevel.value >= 30) return 'TITAN_OF_SYNTHESIS';
  if (playerLevel.value >= 15) return 'ELITE_TECHNICIAN';
  if (playerLevel.value >= 5) return 'RECOGNIZED_CRAFTER';
  return 'JUNIOR_APPRENTICE';
});

const tierMinLevel = (tier: number) => {
  if (tier >= 5) return 50;
  if (tier >= 4) return 30;
  if (tier >= 3) return 15;
  if (tier >= 2) return 5;
  return 1;
};
const isRecipeLocked = (recipe: any) => playerLevel.value < tierMinLevel(recipe.tier);

const forgeCategories = ['MATERIAL', 'THERMAL', 'COMPUTE', 'POWER', 'EXOTIC'];

const getRarity = (tier: number) => {
  if (tier >= 5) return { label: 'LEGENDARY', class: 'rarity-legendary', hex: '#d4a017' };
  if (tier >= 4) return { label: 'EPIC', class: 'rarity-epic', hex: '#9a70c0' };
  if (tier >= 2) return { label: 'RARE', class: 'rarity-rare', hex: '#6898c0' };
  return { label: 'COMMON', class: 'rarity-common', hex: '#6a9a80' };
};
const themeHex = (hex: string) => {
  return hex;
};

const generateRecipes = () => {
  const list: any[] = [];

  // ========== MATERIALS — Intermediate items, only used as inputs ==========
  const materials = [
    // ── T1 BASE (4) ── raw ingredients, no inputs
    { id: 'mat_thermal_paste', name: 'Thermal Paste', icon: FlaskConical, tier: 1, desc: 'Basic heat conductor. Foundation of all cooling crafts.', cost: { amount: 200, currency: 'gameCoin' }, time: 15, nrg: 5 },
    { id: 'mat_iron_plate', name: 'Iron Plate', icon: Wrench, tier: 1, desc: 'Sturdy metal plate. Structural base for frames and shields.', cost: { amount: 300, currency: 'gameCoin' }, time: 20, nrg: 5 },
    { id: 'mat_logic_gate', name: 'Logic Gate', icon: Cpu, tier: 1, desc: 'Basic circuit component. The building block of all processors.', cost: { amount: 500, currency: 'gameCoin' }, time: 20, nrg: 8 },
    { id: 'mat_signal_wire', name: 'Signal Wire', icon: Cable, tier: 1, desc: 'Conductive wiring. Carries power and data across components.', cost: { amount: 400, currency: 'gameCoin' }, time: 15, nrg: 5 },

    // ── T2 GENERIC (2) ── general purpose, used in cross-branch recipes
    { id: 'mat_coolant_cell', name: 'Coolant Cell', icon: Snowflake, tier: 2, desc: 'Pressurized coolant container. General-purpose thermal component.', cost: { amount: 1500, currency: 'gameCoin' }, time: 45, nrg: 15,
      inputs: [{ name: 'Thermal Paste', type: 'material', qty: 2 }, { name: 'Iron Plate', type: 'material', qty: 1 }] },
    { id: 'mat_power_core', name: 'Power Core', icon: Battery, tier: 2, desc: 'Compact energy cell. General-purpose power component.', cost: { amount: 2000, currency: 'gameCoin' }, time: 60, nrg: 18,
      inputs: [{ name: 'Signal Wire', type: 'material', qty: 3 }, { name: 'Logic Gate', type: 'material', qty: 1 }] },

    // ── T2 SPECIALIZED (4) ── branch-specific intermediates
    { id: 'mat_cryo_gel', name: 'Cryo-Gel', icon: Droplets, tier: 2, desc: 'Sub-zero thermal compound. Essential for advanced cooling modules.', cost: { amount: 1800, currency: 'gameCoin' }, time: 50, nrg: 16,
      inputs: [{ name: 'Thermal Paste', type: 'material', qty: 3 }, { name: 'Coolant Cell', type: 'recipe', qty: 1 }] },
    { id: 'mat_silicon_wafer', name: 'Silicon Wafer', icon: Disc, tier: 2, desc: 'Pure silicon substrate. Required for all compute-grade processors.', cost: { amount: 2200, currency: 'gameCoin' }, time: 55, nrg: 20,
      inputs: [{ name: 'Logic Gate', type: 'material', qty: 3 }, { name: 'Iron Plate', type: 'material', qty: 1 }] },
    { id: 'mat_copper_coil', name: 'Copper Coil', icon: RotateCw, tier: 2, desc: 'High-conductivity coil. Channels raw energy into stable output.', cost: { amount: 1900, currency: 'gameCoin' }, time: 50, nrg: 17,
      inputs: [{ name: 'Signal Wire', type: 'material', qty: 3 }, { name: 'Iron Plate', type: 'material', qty: 2 }] },

    // ── T3 GENERIC (1) ── still needed as universal advanced material
    { id: 'mat_nano_fiber', name: 'Nano Fiber', icon: Dna, tier: 3, desc: 'Ultra-light structural material. Universal ingredient for T3+ recipes.', cost: { amount: 8000, currency: 'LandWork' }, time: 120, nrg: 35,
      inputs: [{ name: 'Iron Plate', type: 'material', qty: 5 }, { name: 'Coolant Cell', type: 'recipe', qty: 1 }] },

    // ── T3 SPECIALIZED (4) ── advanced branch materials
    { id: 'mat_frost_alloy', name: 'Frost-Alloy', icon: Thermometer, tier: 3, desc: 'Cryo-infused metal alloy. Conducts cold 10x better than copper.', cost: { amount: 10000, currency: 'LandWork' }, time: 150, nrg: 40,
      inputs: [{ name: 'Cryo-Gel', type: 'recipe', qty: 2 }, { name: 'Nano Fiber', type: 'recipe', qty: 1 }] },
    { id: 'mat_neuro_silk', name: 'Neuro-Silk', icon: Network, tier: 3, desc: 'Neural-grade silicon mesh. Enables parallel processing architectures.', cost: { amount: 12000, currency: 'LandWork' }, time: 160, nrg: 45,
      inputs: [{ name: 'Silicon Wafer', type: 'recipe', qty: 2 }, { name: 'Power Core', type: 'recipe', qty: 1 }] },
    { id: 'mat_flux_capacitor', name: 'Flux-Capacitor', icon: Zap, tier: 3, desc: 'Stores and releases energy in controlled bursts. Powers T3+ modules.', cost: { amount: 11000, currency: 'LandWork' }, time: 155, nrg: 42,
      inputs: [{ name: 'Copper Coil', type: 'recipe', qty: 2 }, { name: 'Power Core', type: 'recipe', qty: 2 }] },

    // ── T4 GENERIC + CONVERGENCE ──
    { id: 'mat_quantum_chip', name: 'Quantum Chip', icon: Gem, tier: 4, desc: 'Quantum-state processor. Required for all T4+ modules across branches.', cost: { amount: 5000, currency: 'LandWork' }, time: 300, nrg: 80,
      inputs: [{ name: 'Logic Gate', type: 'material', qty: 8 }, { name: 'Nano Fiber', type: 'recipe', qty: 2 }] },
    { id: 'mat_prism_matrix', name: 'Prism-Matrix', icon: Eye, tier: 4, desc: 'Multi-dimensional energy lattice. Converges all branches into exotic potential.', cost: { amount: 18000, currency: 'LandWork' }, time: 360, nrg: 100,
      inputs: [{ name: 'Neuro-Silk', type: 'recipe', qty: 1 }, { name: 'Frost-Alloy', type: 'recipe', qty: 1 }, { name: 'Quantum Chip', type: 'recipe', qty: 1 }] },

    // ── T5 LEGENDARY ──
    { id: 'mat_void_essence', name: 'Void Essence', icon: Moon, tier: 5, desc: 'Mysterious substance from deep mining. Required for T5 legendary crafts.', cost: { amount: 2, currency: 'RON' }, time: 600, nrg: 200,
      inputs: [{ name: 'Quantum Chip', type: 'recipe', qty: 2 }, { name: 'Nano Fiber', type: 'recipe', qty: 3 }] },
  ];

  materials.forEach(mat => {
    list.push({
      id: mat.id, cat: 'MATERIAL', tier: mat.tier,
      inputs: mat.inputs || [],
      usage: 'MATERIAL', gives: 'NONE',
      desc: mat.desc,
      forgeTime: mat.time,
      forgeCost: mat.cost,
      netCost: mat.nrg,
      result: { name: mat.name, icon: mat.icon, stat: '—', abi: 'Crafting material' },
      sources: ['FORGE'],
      rarity: getRarity(mat.tier)
    });
  });

  // ========== THERMAL — uses Cryo-Gel / Frost-Alloy branch ==========
  const thermals = [
    { id: 'th_1', tier: 1, name: 'Frost-Byte', icon: Snowflake, desc: 'Basic cooling paste. Reduces rig temp by a small margin.',
      inputs: [{ name: 'Thermal Paste', type: 'recipe', qty: 2 }, { name: 'Iron Plate', type: 'recipe', qty: 1 }],
      cooling: 15, coolHP: 800, cost: { amount: 900, currency: 'gameCoin' }, time: 30, nrg: 10 },
    { id: 'th_2', tier: 2, name: 'Ice-Wall', icon: Snowflake, desc: 'Mid-grade coolant wall. Cryo-Gel core keeps temp stable under load.',
      inputs: [{ name: 'Frost-Byte', type: 'recipe', qty: 1 }, { name: 'Cryo-Gel', type: 'recipe', qty: 2 }],
      cooling: 45, coolHP: 5000, cost: { amount: 3000, currency: 'gameCoin' }, time: 120, nrg: 25 },
    { id: 'th_3', tier: 3, name: 'Cryo-Vex', icon: Snowflake, desc: 'Frost-Alloy chamber. Prevents thermal throttling on heavy tasks.',
      inputs: [{ name: 'Ice-Wall', type: 'recipe', qty: 1 }, { name: 'Frost-Alloy', type: 'recipe', qty: 2 }],
      cooling: 90, coolHP: 25000, cost: { amount: 18000, currency: 'LandWork' }, time: 300, nrg: 50 },
    { id: 'th_4', tier: 4, name: 'Zero-Kelvin', icon: Snowflake, desc: 'Quantum-cooled Frost-Alloy system. Rig runs cold at max hashrate.',
      inputs: [{ name: 'Cryo-Vex', type: 'recipe', qty: 1 }, { name: 'Frost-Alloy', type: 'recipe', qty: 1 }, { name: 'Quantum Chip', type: 'recipe', qty: 1 }],
      cooling: 160, coolHP: 100000, cost: { amount: 12000, currency: 'LandWork' }, time: 600, nrg: 120 },
    { id: 'th_5', tier: 5, name: 'Absolute-Zero', icon: Snowflake, desc: 'Absolute zero core. Void-infused cryo — eliminates all heat.',
      inputs: [{ name: 'Zero-Kelvin', type: 'recipe', qty: 1 }, { name: 'Void Essence', type: 'recipe', qty: 2 }],
      cooling: 300, coolHP: 500000, cost: { amount: 10, currency: 'RON' }, time: 1800, nrg: 300 },
  ];

  thermals.forEach(t => {
    list.push({
      id: t.id, cat: 'THERMAL', tier: t.tier, inputs: t.inputs,
      usage: 'RIG_INSTALL', gives: 'COOLING', desc: t.desc,
      forgeTime: t.time, forgeCost: t.cost, netCost: t.nrg,
      result: { name: t.name, cooling: t.cooling, coolHP: t.coolHP, icon: t.icon, stat: `${t.coolHP.toLocaleString()} HP`, abi: `-${t.cooling}°C cooling power` },
      sources: [t.tier < 3 ? 'MARKET' : 'POOL'], rarity: getRarity(t.tier)
    });
  });

  // ========== COMPUTE — uses Silicon Wafer / Neuro-Silk branch ==========
  // Each compute module consumes watts (energy field) — needs POWER modules to supply them
  const computes = [
    { id: 'ha_1', tier: 1, name: 'Core-Link', icon: Zap, desc: 'Basic logic board. +50 H/s but consumes 15W and 10 cooling HP/min.',
      inputs: [{ name: 'Logic Gate', type: 'recipe', qty: 2 }, { name: 'Signal Wire', type: 'recipe', qty: 1 }],
      hash: 50, cool: 10, energy: 15, net: 5, cost: { amount: 800, currency: 'gameCoin' }, time: 30, nrg: 12 },
    { id: 'ha_2', tier: 2, name: 'Overclocked', icon: Zap, desc: 'Silicon Wafer processor. +180 H/s. Consumes 20W — needs Volt-Cell or higher.',
      inputs: [{ name: 'Core-Link', type: 'recipe', qty: 1 }, { name: 'Silicon Wafer', type: 'recipe', qty: 2 }],
      hash: 180, cool: 14, energy: 20, net: 7, cost: { amount: 6000, currency: 'gameCoin' }, time: 120, nrg: 30 },
    { id: 'ha_3', tier: 3, name: 'Neural-Sync', icon: Zap, desc: 'Neuro-Silk processor. +500 H/s. Draws 26W — pair with Amp-Pack or higher.',
      inputs: [{ name: 'Overclocked', type: 'recipe', qty: 1 }, { name: 'Neuro-Silk', type: 'recipe', qty: 2 }],
      hash: 500, cool: 18, energy: 26, net: 9, cost: { amount: 25000, currency: 'LandWork' }, time: 300, nrg: 60 },
    { id: 'ha_4', tier: 4, name: 'Quantum-Step', icon: Zap, desc: 'Quantum logic unit. +1500 H/s. Draws 32W — needs Fusion-Core or higher.',
      inputs: [{ name: 'Neural-Sync', type: 'recipe', qty: 1 }, { name: 'Neuro-Silk', type: 'recipe', qty: 1 }, { name: 'Quantum Chip', type: 'recipe', qty: 1 }],
      hash: 1500, cool: 22, energy: 32, net: 11, cost: { amount: 50000, currency: 'LandWork' }, time: 600, nrg: 90 },
    { id: 'ha_5', tier: 5, name: 'Void-Engine', icon: Zap, desc: 'Void engine core. +15000 H/s. Draws 38W — requires Dark-Conduit or Singularity.',
      inputs: [{ name: 'Quantum-Step', type: 'recipe', qty: 1 }, { name: 'Void Essence', type: 'recipe', qty: 3 }],
      hash: 15000, cool: 26, energy: 38, net: 13, cost: { amount: 5, currency: 'RON' }, time: 1800, nrg: 350 },
  ];

  computes.forEach(c => {
    list.push({
      id: c.id, cat: 'COMPUTE', tier: c.tier, inputs: c.inputs,
      usage: 'RIG_INSTALL', gives: 'HASHRATE', desc: c.desc,
      forgeTime: c.time, forgeCost: c.cost, netCost: c.nrg,
      result: { name: c.name, icon: c.icon, hashrate: c.hash, stat: `+${c.hash}H/s`,
        consumes: { coolHP: c.cool, energy: c.energy, internet: c.net },
        abi: `Computational boost T${c.tier}` },
      sources: [c.tier < 3 ? 'MARKET' : 'POOL'], rarity: getRarity(c.tier)
    });
  });

  // ========== POWER — supplies energy that compute/cooling modules consume ==========
  // Without enough power: rig efficiency drops proportionally (e.g. 50% power deficit = 50% less hashrate)
  // Each compute module consumes W, each cooling module consumes W. Power modules supply W.
  const powers = [
    { id: 'pw_1', tier: 1, name: 'Volt-Cell', icon: Battery, stat: '+80W',
      desc: 'Basic power cell. Supplies 80W to your rig. Compute and cooling modules consume watts — without enough power, efficiency drops.',
      inputs: [{ name: 'Signal Wire', type: 'recipe', qty: 2 }, { name: 'Iron Plate', type: 'recipe', qty: 1 }], cost: { amount: 800, currency: 'gameCoin' }, time: 30, nrg: 10 },
    { id: 'pw_2', tier: 2, name: 'Amp-Pack', icon: Battery, stat: '+300W',
      desc: 'Copper Coil battery. Supplies 300W. Enough to run a T2 compute + T1 cooling without penalty.',
      inputs: [{ name: 'Volt-Cell', type: 'recipe', qty: 1 }, { name: 'Copper Coil', type: 'recipe', qty: 2 }], cost: { amount: 2500, currency: 'gameCoin' }, time: 120, nrg: 28 },
    { id: 'pw_3', tier: 3, name: 'Fusion-Core', icon: Battery, stat: '+1000W',
      desc: 'Flux-Capacitor reactor. Supplies 1000W. Powers a full T3 setup — compute, cooling, and stability.',
      inputs: [{ name: 'Amp-Pack', type: 'recipe', qty: 1 }, { name: 'Flux-Capacitor', type: 'recipe', qty: 2 }], cost: { amount: 12000, currency: 'LandWork' }, time: 300, nrg: 55 },
    { id: 'pw_4', tier: 4, name: 'Dark-Conduit', icon: Battery, stat: '+3500W',
      desc: 'Quantum Flux-Capacitor conduit. Supplies 3500W. Enough for multiple T4 modules running simultaneously.',
      inputs: [{ name: 'Fusion-Core', type: 'recipe', qty: 1 }, { name: 'Flux-Capacitor', type: 'recipe', qty: 1 }, { name: 'Quantum Chip', type: 'recipe', qty: 1 }], cost: { amount: 8000, currency: 'LandWork' }, time: 600, nrg: 140 },
    { id: 'pw_5', tier: 5, name: 'Singularity', icon: Battery, stat: '+10000W',
      desc: 'Singularity core. Supplies 10000W. Powers an entire T5 rig at full capacity with zero bottleneck.',
      inputs: [{ name: 'Dark-Conduit', type: 'recipe', qty: 1 }, { name: 'Void Essence', type: 'recipe', qty: 2 }], cost: { amount: 8, currency: 'RON' }, time: 1800, nrg: 320 },
  ];

  powers.forEach(p => {
    list.push({
      id: p.id, cat: 'POWER', tier: p.tier, inputs: p.inputs,
      usage: 'RIG_INSTALL', gives: 'ENERGY', desc: p.desc,
      forgeTime: p.time, forgeCost: p.cost, netCost: p.nrg,
      result: { name: p.name, icon: p.icon, stat: p.stat, abi: `Power module T${p.tier}` },
      sources: ['POOL_DROP'], rarity: getRarity(p.tier)
    });
  });

  // ========== EXOTIC — convergence branch, uses Prism-Matrix ==========
  const exotics = [
    { id: 'ex_1', tier: 1, name: 'Strange-Shard', icon: Sparkles, desc: 'Strange fragment. Combine with other exotics for unknown effects.',
      inputs: [{ name: 'Iron Plate', type: 'recipe', qty: 2 }, { name: 'Thermal Paste', type: 'recipe', qty: 2 }],
      gives: 'NONE', usage: 'COMBINE', stat: '—', cost: { amount: 1000, currency: 'gameCoin' }, time: 45, nrg: 15 },
    { id: 'ex_2', tier: 2, name: 'Anomaly-Gem', icon: Sparkles, desc: 'Anomaly shard. Requires materials from multiple branches to fuse.',
      inputs: [{ name: 'Strange-Shard', type: 'recipe', qty: 2 }, { name: 'Cryo-Gel', type: 'recipe', qty: 1 }, { name: 'Silicon Wafer', type: 'recipe', qty: 1 }],
      gives: 'NONE', usage: 'COMBINE', stat: '—', cost: { amount: 5000, currency: 'gameCoin' }, time: 120, nrg: 35 },
    { id: 'ex_3', tier: 3, name: 'Void-Crystal', icon: Sparkles, desc: 'Void crystal. Forged from converging branch materials.',
      inputs: [{ name: 'Anomaly-Gem', type: 'recipe', qty: 2 }, { name: 'Nano Fiber', type: 'recipe', qty: 1 }, { name: 'Copper Coil', type: 'recipe', qty: 1 }],
      gives: 'NONE', usage: 'COMBINE', stat: '—', cost: { amount: 30000, currency: 'LandWork' }, time: 300, nrg: 70 },
    { id: 'ex_4', tier: 4, name: 'Rift-Core', icon: Sparkles, desc: 'Prism-Matrix powered overclock. Boosts hashrate of all installed compute modules for 2hr.',
      inputs: [{ name: 'Void-Crystal', type: 'recipe', qty: 2 }, { name: 'Prism-Matrix', type: 'recipe', qty: 1 }],
      gives: 'BOOSTER', usage: 'BOOSTER', stat: '+40% HASH (2hr)', cost: { amount: 18000, currency: 'LandWork' }, time: 600, nrg: 160 },
    { id: 'ex_5', tier: 5, name: 'Omega-Relic', icon: Sparkles, desc: 'The ultimate overclock. Massively boosts hashrate of all compute modules for 4hr.',
      inputs: [{ name: 'Rift-Core', type: 'recipe', qty: 1 }, { name: 'Prism-Matrix', type: 'recipe', qty: 1 }, { name: 'Void Essence', type: 'recipe', qty: 2 }],
      gives: 'BOOSTER', usage: 'BOOSTER', stat: '+100% HASH (4hr)', cost: { amount: 12, currency: 'RON' }, time: 1800, nrg: 400 },
  ];

  exotics.forEach(e => {
    list.push({
      id: e.id, cat: 'EXOTIC', tier: e.tier, inputs: e.inputs,
      usage: e.usage, gives: e.gives, desc: e.desc,
      forgeTime: e.time, forgeCost: e.cost, netCost: e.nrg,
      result: { name: e.name, icon: e.icon, stat: e.stat, abi: e.gives === 'BOOSTER' ? `Booster T${e.tier}` : 'Combine material' },
      sources: ['POOL_DROP'], rarity: getRarity(e.tier)
    });
  });

  return list;
};

const forgeRecipes = generateRecipes();
const unlockedCount = computed(() => 24); // Simulated unlock progress

const handleStartForge = async () => {
  if (!forgeResult.value) return;

  // Check internet (net channel)
  const netCost = forgeResult.value.netCost ?? 0;
  const currentInternet = authStore.player?.internet ?? 0;
  if (currentInternet < netCost) {
    forgeLogs.value.unshift(`> ERROR: INSUFFICIENT_NET_CHANNEL (${Math.floor(currentInternet)}/${netCost})`);
    return;
  }

  const recipeId = forgeResult.value.id;
  isForging.value = true;
  forgeProgress.value = 0;
  forgeStepLabel.value = '';
  forgingMap.value[recipeId] = { progress: 0, label: '' };
  forgeLogs.value = [];

  const steps = [
    'INITIATING_FUSION_PROTOCOL...',
    `NET_CHANNEL: -${netCost} BANDWIDTH...`,
    'CALIBRATING_ITEM_RESONANCE...',
    'COMPRESSION_SEQ_STABLE...',
    'FORGE_COMPLETE_SUCCESS'
  ];

  for (let i = 0; i < steps.length; i++) {
    const pct = Math.round(((i + 1) / steps.length) * 100);
    forgeStepLabel.value = steps[i];
    forgeProgress.value = pct;
    forgingMap.value[recipeId] = { progress: pct, label: steps[i] };
    forgeLogs.value.unshift(`> ${steps[i]}`);
    await new Promise(r => setTimeout(r, 600));
  }

  // Deduct internet locally
  if (authStore.player) {
    authStore.player.internet = Math.max(0, currentInternet - netCost);
  }

  // Final Action
  const res = forgeResult.value.result;
  const tier = forgeResult.value.tier;
  
  inventory.value.cooling.push({
    id: 'forged-' + Date.now(),
    name: res.name,
    cooling_power: res.cooling,
    hashrate_boost: parseInt(res.power),
    icon: res.icon,
    rarity: forgeResult.value.rarity.label
  });

  // Grant XP via RPC
  const xpGain = tier * 40 + 20;
  forgeLogs.value.unshift(`> PROTOCOL_SYNC: +${xpGain} XP_ADAPTATION`);
  try {
    const xpRes = await grantPlayerXp(authStore.player!.id, xpGain, 'forge');
    if (xpRes?.success) {
      authStore.player!.xp = xpRes.new_xp;
      authStore.player!.level = xpRes.new_level;
      if (xpRes.leveled_up) {
        forgeLogs.value.unshift(`>>> LEVEL_UP: RANK_${xpRes.new_level}_UNLOCKED <<<`);
        triggerStory(xpRes.new_level);
      }
    }
  } catch (e) {
    console.error('grant_player_xp failed', e);
  }

  delete forgingMap.value[recipeId];
  isForging.value = Object.keys(forgingMap.value).length > 0;
  forgeProgress.value = 0;
  forgeStepLabel.value = '';
  forgeSelection.value = [null, null];
};

// ── INBOX: Captcha Modal + Claim handlers ──
const showClaimModal = ref(false);
const claimModalBlockId = ref<string | null>(null);
const inboxCaptchaVerified = ref(false);
const inboxCaptchaWidgetId = ref<number | null>(null);
const inboxCaptchaContainer = ref<HTMLElement | null>(null);

function renderInboxCaptcha() {
  if (typeof (window as any).hcaptcha !== 'undefined' && inboxCaptchaContainer.value) {
    if (inboxCaptchaWidgetId.value !== null) {
      (window as any).hcaptcha.reset(inboxCaptchaWidgetId.value);
    }
    inboxCaptchaWidgetId.value = (window as any).hcaptcha.render(inboxCaptchaContainer.value, {
      sitekey: '330e8d5c-9428-4450-869c-b638d490da2e',
      callback: () => { inboxCaptchaVerified.value = true; },
      'expired-callback': () => { inboxCaptchaVerified.value = false; },
      'error-callback': () => { inboxCaptchaVerified.value = false; },
      theme: 'dark',
    });
  }
}

function resetInboxCaptcha() {
  if (inboxCaptchaWidgetId.value !== null && typeof (window as any).hcaptcha !== 'undefined') {
    try { (window as any).hcaptcha.reset(inboxCaptchaWidgetId.value); } catch {}
  }
  inboxCaptchaVerified.value = false;
}

function openClaimModal(blockId: string) {
  playSound('click');
  claimModalBlockId.value = blockId;
  inboxCaptchaVerified.value = false;
  showClaimModal.value = true;
  nextTick(() => renderInboxCaptcha());
}

function closeClaimModal() {
  showClaimModal.value = false;
  claimModalBlockId.value = null;
  resetInboxCaptcha();
}

async function handleClaimAfterCaptcha() {
  if (!claimModalBlockId.value || !inboxCaptchaVerified.value) return;
  const result = await pendingBlocksStore.claim(claimModalBlockId.value);
  if (result?.success) {
    playSound('reward');
    closeClaimModal();
    selectedInboxBlock.value = null;
  }
}

// ── Claim All with RON (hold button) ──
const CLAIM_ALL_HOLD_MS = 2000;
const claimAllHoldProgress = ref(0);
const claimAllHoldTimer = ref<ReturnType<typeof setInterval> | null>(null);
const claimAllHoldStart = ref(0);

function onClaimAllHoldStart() {
  if (pendingBlocksStore.claiming || pendingBlocksStore.count === 0) return;
  playSound('click');
  claimAllHoldStart.value = Date.now();
  claimAllHoldProgress.value = 0;
  claimAllHoldTimer.value = setInterval(() => {
    const elapsed = Date.now() - claimAllHoldStart.value;
    claimAllHoldProgress.value = Math.min(100, (elapsed / CLAIM_ALL_HOLD_MS) * 100);
    if (claimAllHoldProgress.value >= 100) {
      onClaimAllHoldComplete();
    }
  }, 25);
}

function onClaimAllHoldEnd() {
  if (claimAllHoldTimer.value) {
    clearInterval(claimAllHoldTimer.value);
    claimAllHoldTimer.value = null;
  }
  claimAllHoldProgress.value = 0;
}

async function onClaimAllHoldComplete() {
  if (claimAllHoldTimer.value) {
    clearInterval(claimAllHoldTimer.value);
    claimAllHoldTimer.value = null;
  }
  claimAllHoldProgress.value = 100;
  playSound('reward');
  await pendingBlocksStore.claimAllWithRon();
  claimAllHoldProgress.value = 0;
  selectedInboxBlock.value = null;
}

// ── INVENTORY: Filtered items + handlers ──
const filteredInvItems = computed(() => {
  const items: { type: string; id: string; icon: Component; name: string; stat: string; badge: string; badgeClass: string; qty: number; data: any }[] = [];
  const cat = invCategory.value;

  if (cat === 'all' || cat === 'rigs') {
    for (const r of inventoryStore.rigItems) {
      items.push({ type: 'rig', id: r.rig_id, icon: Pickaxe, name: r.name, stat: `${r.hashrate} H/s · ${r.power_consumption}W`, badge: 'RIG', badgeClass: '', qty: r.quantity, data: r });
    }
  }
  if (cat === 'all' || cat === 'cooling') {
    for (const c of inventoryStore.coolingItems) {
      items.push({ type: 'cooling', id: c.inventory_id, icon: Snowflake, name: c.name, stat: `${c.cooling_power} CP · ${c.energy_cost} NRG`, badge: 'COOL', badgeClass: 'cool', qty: c.quantity, data: c });
    }
    for (const m of inventoryStore.moddedCoolingItems) {
      items.push({ type: 'modded_cooling', id: m.player_cooling_item_id, icon: Snowflake, name: m.name, stat: `${m.effective_cooling_power} CP · ${m.mod_slots_used}/${m.max_mod_slots} MODS`, badge: 'MOD+', badgeClass: 'mod', qty: 1, data: m });
    }
    for (const c of inventoryStore.componentItems) {
      items.push({ type: 'component', id: c.inventory_id, icon: Wrench, name: c.name, stat: `${c.cooling_power_min}-${c.cooling_power_max} CP`, badge: 'COMP', badgeClass: 'mod', qty: c.quantity, data: c });
    }
  }
  if (cat === 'all' || cat === 'cards') {
    for (const c of inventoryStore.cardItems) {
      items.push({ type: 'card', id: c.id, icon: CreditCard, name: c.name || `${c.card_type.toUpperCase()} CARD`, stat: `+${c.amount} ${c.card_type}`, badge: c.card_type.toUpperCase(), badgeClass: 'card', qty: 1, data: c });
    }
  }
  if (cat === 'all' || cat === 'boosts') {
    for (const b of inventoryStore.boostItems) {
      items.push({ type: 'boost', id: b.id, icon: Rocket, name: b.name, stat: `+${b.effect_value}% · ${b.duration_minutes}min`, badge: 'BOOST', badgeClass: 'boost', qty: b.quantity, data: b });
    }
  }
  if (cat === 'all' || cat === 'materials') {
    for (const m of inventoryStore.materialItems) {
      items.push({ type: 'material', id: m.material_id, icon: Gem, name: m.name, stat: m.rarity, badge: 'MAT', badgeClass: 'mat', qty: m.quantity, data: m });
    }
  }
  if (cat === 'all' || cat === 'patches') {
    for (const p of inventoryStore.patchItems) {
      items.push({ type: 'patch', id: p.inventory_id, icon: Sticker, name: 'RIG_PATCH', stat: '+35% condition', badge: 'PATCH', badgeClass: '', qty: p.quantity, data: p });
    }
  }
  if (cat === 'all' || cat === 'exp') {
    for (const e of inventoryStore.expPackItems) {
      items.push({ type: 'exp_pack', id: e.inventory_id, icon: BookOpen, name: e.name, stat: `+${e.xp_amount} XP`, badge: 'EXP', badgeClass: 'xp', qty: e.quantity, data: e });
    }
  }
  return items;
});

function selectInvItem(item: typeof filteredInvItems.value[0]) {
  playSound('click');
  if (selectedInvItem.value?.id === item.id && selectedInvItem.value?.type === item.type) {
    selectedInvItem.value = null;
  } else {
    selectedInvItem.value = { type: item.type, id: item.id, data: item.data };
  }
}

// Confirmation modal for inventory actions (only DISCARD)
const showInvConfirm = ref(false);
const invConfirmAction = ref<{ action: string; label: string; data: any } | null>(null);

function requestInvAction(action: string, label: string, data: any = {}) {
  invConfirmAction.value = { action, label, data };
  showInvConfirm.value = true;
}

function cancelInvAction() {
  showInvConfirm.value = false;
  invConfirmAction.value = null;
}

// Execute inventory action directly
async function executeInvAction(action: string, data: any) {
  if (invActionLoading.value) return;
  invActionLoading.value = true;

  try {
    let success = false;
    if (action === 'install_rig') {
      const res = await inventoryStore.installRig(data.rigId);
      success = res.success;
      if (success) await miningStore.fetchRigs();
    } else if (action === 'delete_item') {
      const res = await inventoryStore.deleteItem(data.itemType, data.itemId, data.quantity ?? 1);
      success = res.success;
    } else if (action === 'redeem_card') {
      const res = await redeemPrepaidCard(authStore.player!.id, data.code);
      success = !!res?.success;
      if (success) { await authStore.fetchPlayer(); await inventoryStore.refresh(); }
    } else if (action === 'use_exp_pack') {
      const res = await useExpPack(authStore.player!.id, data.packId);
      success = !!res?.success;
      if (success) { await authStore.fetchPlayer(); await inventoryStore.refresh(); }
    } else if (action === 'apply_patch') {
      const res = await applyRigPatch(authStore.player!.id, data.rigId);
      success = !!res?.success;
      if (success) { await miningStore.fetchRigs(); await inventoryStore.refresh(); }
    }

    if (success) {
      playSound('success');
      selectedInvItem.value = null;
    } else {
      playSound('error');
    }
  } catch (e) {
    console.error('Inventory action error:', e);
    playSound('error');
  }

  invActionLoading.value = false;
}

async function confirmInvAction() {
  if (!invConfirmAction.value || invActionLoading.value) return;
  const { action, data } = invConfirmAction.value;
  await executeInvAction(action, data);
  showInvConfirm.value = false;
  invConfirmAction.value = null;
}

// Hold button logic for inventory actions
const INV_HOLD_MS = 1200;
const invHoldPct = ref(0);
const invHoldActive = ref(false);
let invHoldFrame: number | null = null;
let invHoldT0 = 0;
let invHoldAction = '';
let invHoldData: any = null;

function startInvHold(action: string, data: any = {}) {
  if (invActionLoading.value) return;
  invHoldAction = action;
  invHoldData = data;
  invHoldActive.value = true;
  invHoldT0 = Date.now();
  invHoldPct.value = 0;

  const animate = () => {
    const elapsed = Date.now() - invHoldT0;
    invHoldPct.value = Math.min(100, (elapsed / INV_HOLD_MS) * 100);

    if (elapsed >= INV_HOLD_MS) {
      invHoldActive.value = false;
      invHoldPct.value = 0;
      executeInvAction(invHoldAction, invHoldData);
    } else if (invHoldActive.value) {
      invHoldFrame = requestAnimationFrame(animate);
    }
  };
  invHoldFrame = requestAnimationFrame(animate);
}

function cancelInvHold() {
  if (!invHoldActive.value) return;
  invHoldActive.value = false;
  invHoldPct.value = 0;
  if (invHoldFrame) {
    cancelAnimationFrame(invHoldFrame);
    invHoldFrame = null;
  }
}

// Rig selection for patch
const showRigSelectModal = ref(false);
const pendingInvAction = ref<{ type: string; data: any } | null>(null);

function openRigSelect(patchData: any) {
  pendingInvAction.value = { type: 'patch', data: patchData };
  showRigSelectModal.value = true;
}

function selectRigForPatch(rigId: string) {
  showRigSelectModal.value = false;
  executeInvAction('apply_patch', { rigId });
}

const filteredRecipes = computed(() => {
  return forgeRecipes.filter(r => {
    if (isRecipeLocked(r)) return false;
    const matchesCat = r.cat === forgeActiveCat.value;
    const q = forgeSearch.value.toLowerCase();
    const matchesSearch = r.result.name.toLowerCase().includes(q) ||
                          r.inputs.some((inp: any) => inp.name.toLowerCase().includes(q));
    return matchesCat && matchesSearch;
  });
});

// Infinite scroll for forge blueprints
const forgeVisibleCount = ref(12);
const visibleRecipes = computed(() => filteredRecipes.value.slice(0, forgeVisibleCount.value));
const hasMoreRecipes = computed(() => forgeVisibleCount.value < filteredRecipes.value.length);

function onForgeScroll(e: Event) {
  const el = e.target as HTMLElement;
  if (el.scrollTop + el.clientHeight >= el.scrollHeight - 80) {
    if (hasMoreRecipes.value) {
      forgeVisibleCount.value += 12;
    }
  }
}

// Reset visible count when filter changes
function resetForgeScroll() {
  forgeVisibleCount.value = 12;
}

const selectedRecipe = ref<any>(null);

const forgeResult = computed(() => {
  return selectedRecipe.value || null;
});


const isForging = ref(false);
const forgeProgress = ref(0);
const forgeStepLabel = ref('');
const forgingMap = ref<Record<string, { progress: number; label: string }>>({});

function selectForForge(item: any) {
  if (forgeSelection.value[0]?.id === item.id) { forgeSelection.value[0] = null; return; }
  if (forgeSelection.value[1]?.id === item.id) { forgeSelection.value[1] = null; return; }
  
  if (!forgeSelection.value[0]) forgeSelection.value[0] = item;
  else if (!forgeSelection.value[1]) forgeSelection.value[1] = item;
}

// Helper to check if player has an item for a recipe
function hasItem(name: string) {
  return [...inventory.value.cooling, ...inventory.value.boosts].some(i => i.name === name);
}

function selectRecipe(rec: any) {
  selectedRecipe.value = rec;
  const inv = [...inventory.value.cooling, ...inventory.value.boosts];
  const matched = rec.inputs.map((inp: any) => inv.find(i => i.name === inp.name));
  if (matched.every((m: any) => m)) {
    forgeSelection.value = matched;
  }
}

// Consolidation: handleStartForge is defined at line 247 with sequence logs.






/** NODE ABILITY LOGIC **/
function getNodeLifePercent(rig: any) {
  // Simulating 5 day cycle (120 hours) based on uses_remaining or fixed seed
  const totalHours = 120;
  const remaining = (rig.condition / 100) * totalHours; 
  return Math.min(100, (remaining / totalHours) * 100);
}

function getNodeTimeRemaining(rig: any) {
  const hours = (rig.condition / 100) * 120;
  const days = Math.floor(hours / 24);
  const h = Math.floor(hours % 24);
  return `${days}d ${h}h`;
}

function getNodeAbilities(rig: any) {
  // Based on installed components or tier
  return [
    { type: 'hash', val: '100H/s', icon: Zap },
    { type: 'cool', val: 'LIQUID', icon: Snowflake },
    { type: 'stab', val: 'ECC', icon: Shield }
  ];
}









// Selected Rig
const selectedRig = computed(() => {
  if (!selectedRigId.value) return null;
  return rigs.value.find(r => r.id === selectedRigId.value) || null;
});

// Config Logic
async function loadRigConfig(rigId: string) {
  if (!authStore.player) return;
  loadingConfig.value = true;
  try {
    const [inv, cooling, power, pBoosts, rBoosts] = await Promise.all([
      getPlayerInventory(authStore.player.id),
      getRigCooling(rigId),
      getRigPower(rigId),
      getPlayerBoosts(authStore.player.id),
      getRigBoosts(rigId)
    ]);
    inventory.value = { cooling: inv.cooling || [], boosts: pBoosts?.inventory || [] };
    installedCooling.value = cooling || [];
    installedPower.value = power || [];
    installedBoosts.value = rBoosts || [];
  } catch (e) {
    console.error('Config Load Error:', e);
  } finally {
    loadingConfig.value = false;
  }
}


function requestEject(type: 'cooling' | 'boost' | 'power', id: string, name: string) {
  ejectTarget.value = { type, id, name };
  showEjectConfirm.value = true;
}

async function confirmEject() {
  if (!ejectTarget.value || !selectedRig.value || !authStore.player) return;
  try {
    if (ejectTarget.value.type === 'cooling') {
      await removeCoolingFromRig(authStore.player.id, selectedRig.value.id, ejectTarget.value.id);
    } else if (ejectTarget.value.type === 'power') {
      await removePowerFromRig(authStore.player.id, selectedRig.value.id, ejectTarget.value.id);
    } else {
      await removeBoostFromRig(authStore.player.id, selectedRig.value.id, ejectTarget.value.id);
    }
    await loadRigConfig(selectedRig.value.id);
  } catch (e) { console.error(e); }
  showEjectConfirm.value = false;
  ejectTarget.value = null;
}

// Actions
function getRigAlert(rig: any) {
  if (rig.condition < 25) return { text: 'CRITICAL_INTEGRITY', type: 'error' };
  if (rig.temperature > 92) return { text: 'THERMAL_OVERLOAD', type: 'error' };
  if (rig.condition < 60) return { text: 'MAINTENANCE_REQ', type: 'warning' };
  if (rig.temperature > 82) return { text: 'HIGH_THERMAL', type: 'warning' };
  return null;
}

async function handleToggleRig(rigId: string) {

  const rig = rigs.value.find(r => r.id === rigId);
  if (!rig) return;
  
  if (rig.is_active) {
    await miningStore.toggleRig(rigId, undefined);
  } else {
    modeSelectionId.value = rigId;
  }
}

// Long-press activation
const HOLD_DURATION = 1500; // ms
const holdProgress = ref(0);
const holdingMode = ref<'pool' | 'solo' | null>(null);
let holdTimer: ReturnType<typeof setInterval> | null = null;
let holdStart = 0;

function onHoldStart(mode: 'pool' | 'solo') {
  if (!modeSelectionId.value) return;
  holdingMode.value = mode;
  holdProgress.value = 0;
  holdStart = Date.now();
  holdTimer = setInterval(() => {
    const elapsed = Date.now() - holdStart;
    holdProgress.value = Math.min((elapsed / HOLD_DURATION) * 100, 100);
    if (elapsed >= HOLD_DURATION) {
      onHoldComplete(mode);
    }
  }, 16);
}

function onHoldEnd() {
  if (holdTimer) { clearInterval(holdTimer); holdTimer = null; }
  holdProgress.value = 0;
  holdingMode.value = null;
}

async function onHoldComplete(mode: 'pool' | 'solo') {
  if (holdTimer) { clearInterval(holdTimer); holdTimer = null; }
  holdProgress.value = 100;
  holdingMode.value = null;
  await startMining(mode);
}

async function startMining(mode: 'pool' | 'solo') {
  if (!modeSelectionId.value) return;
  await miningStore.toggleRig(modeSelectionId.value, mode);
  modeSelectionId.value = null;
  holdProgress.value = 0;
}


async function selectRig(id: string) {
  if (selectedRigId.value === id) {
    selectedRigId.value = null;
    modeSelectionId.value = null;
  } else {
    selectedRigId.value = id;
    modeSelectionId.value = null;
    configTab.value = 'status';
    await loadRigConfig(id);
  }
}


// ===================== LUCKY BOOST =====================
const LUCKY_BOOST_COST = 10;
const luckyBoostLoading = ref(false);

const luckyBoostActive = computed(() => {
  const until = authStore.player?.lucky_boost_until;
  if (!until) return false;
  return new Date(until) > new Date();
});

const luckyBoostCountdown = computed(() => {
  const until = authStore.player?.lucky_boost_until;
  if (!until) return '';
  const ms = new Date(until).getTime() - Date.now();
  if (ms <= 0) return '';
  const h = Math.floor(ms / 3600000);
  const m = Math.floor((ms % 3600000) / 60000);
  return `${h}h ${m}m`;
});

async function handleActivateLuckyBoost() {
  if (!authStore.player?.id) return;
  if ((authStore.player.ron_balance ?? 0) < LUCKY_BOOST_COST) return;
  luckyBoostLoading.value = true;
  try {
    const result = await activateLuckyBoost(authStore.player.id);
    if (result.success) {
      authStore.player.lucky_boost_until = result.lucky_boost_until;
      authStore.player.ron_balance = result.ron_balance;
    }
  } catch (e) {
    console.error('Error activating lucky boost:', e);
  } finally {
    luckyBoostLoading.value = false;
  }
}

// ===================== STAKING SYSTEM =====================
const STAKING_APY = 0.10;        // 10% APY (Ronin validator average)
const LW_PER_RON = 35000;        // 35% of yield to player (100k LW = 1 RON)

function calcStakeLandwork(ron: number, days: number) {
  return Math.floor(ron * STAKING_APY * (days / 365) * LW_PER_RON);
}

const STAKING_PLANS = [
  { id: 'bronze', label: 'BRONZE', icon: Medal, ron: 100, days: 14, color: '#cd7f32' },
  { id: 'silver', label: 'SILVER', icon: Medal, ron: 300, days: 30, color: '#c0c0c0' },
  { id: 'gold', label: 'GOLD', icon: Medal, ron: 700, days: 60, color: '#fbbf24' },
  { id: 'diamond', label: 'DIAMOND', icon: Gem, ron: 2000, days: 90, color: '#b9f2ff' },
].map(p => ({ ...p, landwork: calcStakeLandwork(p.ron, p.days) }));

const stakeData = ref<any>(null);
const stakeLoading = ref(false);
const selectedPlan = ref<string | null>(null);
const stakeClaiming = ref(false);

const stakeStatus = computed(() => stakeData.value?.status || null);

const stakePendingLandwork = computed(() => {
  if (!stakeData.value || stakeData.value.status !== 'active') return 0;
  return stakeData.value.landwork_pending || 0;
});

const stakeLandworkPerHour = computed(() => {
  const plan = STAKING_PLANS.find(p => p.id === stakeData.value?.plan);
  if (!plan) return 0;
  return +(plan.landwork / (plan.days * 24)).toFixed(1);
});

const stakeProgressPct = computed(() => {
  if (!stakeData.value) return 0;
  const s = stakeData.value;
  if (s.status === 'warmup') {
    const total = new Date(s.warmup_ends_at).getTime() - new Date(s.started_at).getTime();
    const elapsed = Date.now() - new Date(s.started_at).getTime();
    return Math.min(100, Math.max(0, (elapsed / total) * 100));
  }
  if (s.status === 'active') {
    const total = new Date(s.ends_at).getTime() - new Date(s.warmup_ends_at).getTime();
    const elapsed = Date.now() - new Date(s.warmup_ends_at).getTime();
    return Math.min(100, Math.max(0, (elapsed / total) * 100));
  }
  if (s.status === 'cooldown') {
    const total = new Date(s.cooldown_ends_at).getTime() - new Date(s.ends_at).getTime();
    const elapsed = Date.now() - new Date(s.ends_at).getTime();
    return Math.min(100, Math.max(0, (elapsed / total) * 100));
  }
  return 100;
});

function stakeCountdown(targetDate: string) {
  const diff = new Date(targetDate).getTime() - Date.now();
  if (diff <= 0) return '0d 0h 0m';
  const d = Math.floor(diff / 86400000);
  const h = Math.floor((diff % 86400000) / 3600000);
  const m = Math.floor((diff % 3600000) / 60000);
  return `${d}d ${h}h ${m}m`;
}

async function loadStakeData() {
  if (!authStore.player) return;
  stakeLoading.value = true;
  try {
    const res = await checkStakeStatus(authStore.player.id);
    if (res?.success && res.has_stake) {
      stakeData.value = res;
      // Refresh player data if status changed (RON returned, landwork claimed)
      if (res.status_changed) await authStore.refreshPlayer();
    } else {
      stakeData.value = null;
    }
  } catch (e) { /* staking RPC may not exist yet */ }
  stakeLoading.value = false;
}

async function handleCreateStake() {
  if (!authStore.player || !selectedPlan.value) return;
  stakeLoading.value = true;
  try {
    const res = await createStake(authStore.player.id, selectedPlan.value);
    if (res?.success) {
      await authStore.refreshPlayer();
      await loadStakeData();
      selectedPlan.value = null;
    } else {
      alert(res?.error || 'Failed to create stake');
    }
  } catch (e) { console.error('handleCreateStake', e); }
  stakeLoading.value = false;
}

async function handleClaimRewards() {
  if (!authStore.player || stakeClaiming.value) return;
  stakeClaiming.value = true;
  try {
    const res = await claimStakingRewards(authStore.player.id);
    if (res?.success && res.claimed > 0) {
      await authStore.refreshPlayer();
      await loadStakeData();
    }
  } catch (e) { console.error('handleClaimRewards', e); }
  stakeClaiming.value = false;
}

// Lifecycle
const { requestWakeLock, releaseWakeLock } = useWakeLock();
let blockInterval: any = null;

onMounted(async () => {
  setTimeout(() => { booted.value = true; }, 50);
  await miningStore.loadData();
  await soloMiningStore.loadStatus();
  await loadStakeData();
  requestWakeLock();
  // Trigger story for current level if not seen
  if (authStore.player?.level) {
    setTimeout(() => triggerStory(authStore.player!.level), 2000);
  }
  blockInterval = setInterval(() => miningStore.loadMiningBlockInfo(), 30000);
});

onUnmounted(() => {
  releaseWakeLock();
  if (blockInterval) clearInterval(blockInterval);
});

// Slot buy hold
const slotHoldPct = ref(0);
const slotHoldActive = ref(false);
let slotHoldFrame: number | null = null;
let slotHoldT0 = 0;
const SLOT_HOLD_MS = 1500;

function startSlotHold() {
  slotHoldActive.value = true;
  slotHoldT0 = Date.now();
  slotHoldPct.value = 0;
  const animate = () => {
    const elapsed = Date.now() - slotHoldT0;
    slotHoldPct.value = Math.min(100, (elapsed / SLOT_HOLD_MS) * 100);
    if (elapsed >= SLOT_HOLD_MS) {
      slotHoldActive.value = false;
      slotHoldPct.value = 0;
      handleConfirmSlotBuy();
    } else if (slotHoldActive.value) {
      slotHoldFrame = requestAnimationFrame(animate);
    }
  };
  slotHoldFrame = requestAnimationFrame(animate);
}

function cancelSlotHold() {
  if (!slotHoldActive.value) return;
  slotHoldActive.value = false;
  slotHoldPct.value = 0;
  if (slotHoldFrame) { cancelAnimationFrame(slotHoldFrame); slotHoldFrame = null; }
}

async function handleConfirmSlotBuy() {
  try {
    await miningStore.buySlot();
    showSlotConfirm.value = false;
  } catch (e) {
    console.error(e);
  }
}

</script>

<template>
  <div class="deck-terminal-v8" :class="{ 'light-mode': isLightMode, 'booted': booted }" @click="closeMenu">
    <!-- SCANLINES OVERLAY -->
    <div class="terminal-overlay"></div>

    <!-- CONTENT WRAPPER -->
    <main class="terminal-body">
      <div class="v8-container body-inner">
        <!-- SUB-NAVIGATION -->
        <nav class="terminal-nav">
          <span class="nav-brand">⛏️ LOOTMINE</span>
          <button v-for="t in ['fleet', 'staking', 'history']" :key="t" @click="activeTab = t as any" :class="{ active: activeTab === t }">
            [{{ t.toUpperCase() }}]
          </button>
          <button @click="openMissions" class="nav-missions-btn">
            [MISSIONS]
            <span v-if="missionsClaimable > 0" class="nav-missions-badge">{{ missionsClaimable }}</span>
          </button>
        </nav>



      <!-- VIEWPORT -->
      <div class="terminal-viewport">
        
        <!-- FLEET VIEW -->
        <div v-if="activeTab === 'fleet'" class="view-fleet">
          <div class="fleet-layout">
            <div class="grid-section" :class="{ scroll: booted }">
              
              <!-- FLEET OPERATIONS CENTER -->
              <div class="fleet-command-v8">
                 <!-- Balances row -->
                 <div class="fc-balances">
                    <div class="fc-bal" v-tooltip="'Game coins earned from mining.'">
                       <Coins :size="14" />
                       <span class="fc-bal-val">{{ Math.floor(authStore.player?.gamecoin_balance ?? 0).toLocaleString() }}</span>
                       <span class="fc-bal-label">COINS</span>
                    </div>
                    <div class="fc-bal" v-tooltip="'Landwork earned from staking and solo mining.'">
                       <Pickaxe :size="14" />
                       <span class="fc-bal-val">{{ Math.floor(authStore.player?.crypto_balance ?? 0).toLocaleString() }}</span>
                       <span class="fc-bal-label">LANDWORK</span>
                    </div>
                    <div class="fc-bal" v-tooltip="'RON balance for staking, boosts, and transactions.'">
                       <Gem :size="14" />
                       <span class="fc-bal-val fc-bal-ron">{{ (authStore.player?.ron_balance ?? 0).toLocaleString() }}</span>
                       <span class="fc-bal-label">RON</span>
                    </div>
                    <div class="fc-online" v-tooltip="'Players currently online'">
                       <span class="online-dot"></span>
                       <span class="fc-online-count">{{ miningStore.networkStats.onlinePlayers }}</span>
                    </div>
                 </div>

                 <!-- Actions row -->
                 <div class="fc-actions">
                    <button class="fc-btn" :class="{ active: fleetMode === 'forge' }" @click="setFleetMode('forge')" v-tooltip="'Blueprint forge system.'">THE FORGE</button>
                    <button class="fc-btn" :class="{ active: fleetMode === 'inbox' }" @click="setFleetMode('inbox')" v-tooltip="'Pending block rewards.'">
                       INBOX
                       <span v-if="pendingBlocksStore.count" class="fc-badge">{{ pendingBlocksStore.count }}</span>
                    </button>
                    <button class="fc-btn" :class="{ active: fleetMode === 'inventory' }" @click="setFleetMode('inventory')" v-tooltip="'Equipment storage.'">
                       INVENTORY
                       <span v-if="inventoryStore.totalItems" class="fc-badge inv-badge">{{ inventoryStore.slotsUsed }}</span>
                    </button>
                    <button class="fc-btn" :class="{ active: fleetMode === 'market' }" @click="setFleetMode('market')" v-tooltip="'Buy rigs, cooling, boosts and more.'">MARKET</button>
                    <button class="fc-btn" :class="{ active: fleetMode === 'exchange' }" @click="setFleetMode('exchange')" v-tooltip="'Convert currencies.'">EXCHANGE</button>
                    <button v-if="fleetMode === 'rigs'" class="fc-btn neon" @click="handleStartAllHealthy" v-tooltip="'Initialize all 90%+ integrity units.'">START ALL</button>
                 </div>

                 <!-- Net channel bar -->
                 <div class="fc-net-bar" v-tooltip="'Network bandwidth. Used for forging and sync stability.'">
                    <div class="fc-net-icon"><Globe :size="14" /></div>
                    <span class="fc-net-label">NET</span>
                    <div class="fc-net-track">
                       <div class="fc-net-fill" :style="{ width: internetPct + '%' }"
                          :class="{ low: internetPct < 25, mid: internetPct >= 25 && internetPct < 60 }"></div>
                    </div>
                    <span class="fc-net-val">{{ Math.floor(authStore.player?.internet ?? 0) }}<small>%</small></span>
                 </div>

                 <!-- Level & XP bar -->
                 <div class="fc-level-bar" v-tooltip="'Your mining rank and experience progress.'">
                    <span class="fc-level-badge">LV.{{ playerLevel }}</span>
                    <span class="fc-level-rank">{{ forgeRank }}</span>
                    <div class="fc-xp-track">
                       <div class="fc-xp-fill" :style="{ width: playerXpPct + '%' }"></div>
                    </div>
                    <span class="fc-xp-val">{{ playerXp }}/{{ playerXpNeeded }} <small>XP</small></span>
                 </div>
              </div>

              <!-- === RIGS MODE === -->
              <template v-if="fleetMode === 'rigs'">

              <!-- TACTICAL DUAL MONITOR -->
              <div class="tactical-monitor-v8">
                <!-- POOL MONITOR -->
                <div class="monitor-card pool" v-tooltip="'Pool mining participation status.'">
                   <div class="m-head">
                      <span class="m-tag cyan-bg">POOL_NETWORK</span>
                      <span class="m-status">SYNCHRONIZED</span>
                   </div>
                   <div class="m-body">
                      <div class="m-stat" v-tooltip="'Consensus shares found by the global pool.'">
                         <span class="l">SHARE_PROGRESS</span>
                         <span class="v cyan">{{ Math.round(miningStore.sharesProgress) }}%</span>
                      </div>

                      <div class="m-radar">
                         <div class="fill cyan-bg" :style="{ width: miningStore.sharesProgress + '%' }"></div>
                         <div class="wave-vignette cyan"></div>
                      </div>

                      <div class="m-footer">
                         <span><Users :size="12" style="opacity: 0.85" /> {{ miningStore.networkStats.activeMiners }} MINERS</span>
                         <span class="m-timer">BLOCK #{{ currentMiningBlock?.block_number || 'SYNC' }} :: {{ miningStore.blockTimeRemaining }}</span>
                      </div>
                   </div>
                </div>

                <!-- SOLO MONITOR -->
                <div class="monitor-card solo" v-tooltip="'Private mining channel for direct block rewards.'">
                   <div class="m-head">
                      <span class="m-tag amber-bg">SOLO_CHANNEL</span>
                      <span v-if="luckyBoostActive" class="lucky-crown-mini"><Crown :size="14" style="opacity: 0.85" /></span>
                      <span class="m-status" :class="{ inactive: !soloMiningStore.isActive }">
                         {{ soloMiningStore.isActive ? 'UPLINK_STABLE' : 'OFFLINE' }}
                      </span>
                   </div>
                   <div class="m-body">
                      <template v-if="soloMiningStore.isActive && soloMiningStore.currentBlock">
                        <div class="m-stat" v-tooltip="'Specific encryption keys found for this solo block.'">
                           <span class="l">BLOCK_PROTOCOL: {{ (soloMiningStore.currentBlock.block_type).toUpperCase() }}</span>
                           <span class="v amber">{{ soloMiningStore.seedsFound }}/{{ soloMiningStore.seedsTotal }}</span>
                        </div>

                         <div class="m-radar">
                            <div class="fill amber-bg" :style="{ width: soloMiningStore.seedProgress + '%' }"></div>
                            <div class="wave-vignette amber"></div>
                         </div>

                        <div class="m-footer">
                           <span>EST_YIELD: {{ (soloMiningStore.currentBlock.reward).toLocaleString() }} CRYPTO</span>
                           <span class="m-timer amber">:: {{ formatTime(soloMiningStore.blockTimeRemaining) }}</span>
                        </div>
                      </template>
                      <div v-else class="monitor-empty">
                         <span>SOLO_CHANNEL_OFFLINE</span>
                         <small>[REQUIRES_PREMIUM]</small>
                      </div>

                      <!-- LUCKY BOOST -->
                      <div class="lucky-boost-bar" :class="luckyBoostActive ? 'lucky-active' : ''">
                        <div class="flex items-center justify-between">
                          <div class="flex items-center gap-1.5">
                            <span class="text-xs"><component :is="luckyBoostActive ? Crown : Clover" :size="14" style="opacity: 0.85" /></span>
                            <div>
                              <span v-if="luckyBoostActive" class="text-[9px] font-bold text-yellow-400">LUCKY BOOST — {{ luckyBoostCountdown }}</span>
                              <span v-else class="text-[9px] text-text-muted">LUCKY BOOST</span>
                            </div>
                          </div>
                          <button @click="handleActivateLuckyBoost"
                            :disabled="luckyBoostLoading || (authStore.player?.ron_balance ?? 0) < LUCKY_BOOST_COST"
                            class="lucky-btn text-[9px] font-bold px-2 py-0.5 rounded"
                            :class="luckyBoostActive ? 'lucky-btn-extend' : 'lucky-btn-activate'">
                            <span v-if="luckyBoostLoading">...</span>
                            <span v-else-if="luckyBoostActive">+24h · {{ LUCKY_BOOST_COST }} RON</span>
                            <span v-else>{{ LUCKY_BOOST_COST }} RON · 24h</span>
                          </button>
                        </div>
                      </div>
                   </div>
                </div>
              </div>

              <div class="rig-grid">
                <div v-for="(rig, idx) in rigs" :key="rig.id"
                  class="rig-tile"
                  :class="{ active: rig.is_active, selected: selectedRigId === rig.id, 'alert-err': getRigAlert(rig)?.type === 'error' }"
                  @click="selectRig(rig.id)"
                  v-tooltip="`NODE_${idx + 1}: ${rig.rig.name}. Lease: ${getNodeTimeRemaining(rig)} remaining.`"
                >
                  <div class="rt-corner rt-tl"></div>
                  <div class="rt-corner rt-tr"></div>
                  <div class="rt-corner rt-bl"></div>
                  <div class="rt-corner rt-br"></div>

                  <!-- RIG ALERT -->
                  <div v-if="getRigAlert(rig)" class="tile-alert" :class="getRigAlert(rig)?.type">
                    <span class="a-dot"></span>
                    {{ getRigAlert(rig)?.text }}
                  </div>

                  <!-- STATUS BADGE -->
                  <div class="t-status-badge" :class="rig.is_active ? 'online' : 'offline'">
                    <span class="tsb-dot"></span>
                    <span class="tsb-text">{{ rig.is_active ? 'ONLINE' : 'OFFLINE' }}</span>
                  </div>

                  <!-- IDLE PROCESSING ANIMATION -->
                  <div v-if="rig.is_active" class="tile-processing">
                     <div class="data-stream"></div>
                     <div class="data-stream delay-1"></div>
                     <div class="data-stream delay-2"></div>
                  </div>

                  <div class="t-body">
                    <div class="t-name-big">{{ rig.rig.name.split(' ')[0] }} <span class="t-num">{{ String(idx + 1).padStart(2, '0') }}</span></div>
                    <div class="t-meta-row">
                       <span class="t-speed monospace">{{ Math.round(miningStore.getRigEffectiveHashrate(rig)) }}H/s</span>
                       <span class="t-grade-badge" :style="{ color: getRigGrade(rig).color, borderColor: getRigGrade(rig).color + '40' }">{{ getRigGrade(rig).label }}</span>
                    </div>
                    <div class="t-lifetime">
                      <div class="lt-bar"><div class="lt-fill" :style="{ width: getNodeLifePercent(rig) + '%' }" :class="{ low: rig.condition < 25, mid: rig.condition >= 25 && rig.condition < 60 }"></div><div class="lt-segments"></div></div>
                      <span class="lt-text" :class="{ low: rig.condition < 25, paused: !rig.is_active }">{{ getNodeTimeRemaining(rig) }}<Pause v-if="!rig.is_active" :size="10" style="opacity: 0.85; margin-left: 2px;" /></span>
                    </div>
                  </div>

                  <div class="rt-scanline"></div>
                </div>

                <!-- Available Slot -->
                <div v-if="miningStore.slotInfo?.available_slots" class="rig-tile empty" v-tooltip="'Expansion slot available for equipment installation.'">
                   <div class="t-head">
                      <span class="t-id">UNIT_READY</span>
                   </div>
                   <div class="t-body centered">
                      <span class="plus">＋</span>
                      <span>AVAILABLE_SLOT</span>
                   </div>
                </div>

                <!-- Buy Next Slot -->
                <div v-if="miningStore.slotInfo?.next_upgrade" class="rig-tile buy-slot" @click="showSlotConfirm = true" v-tooltip="`Expand operational capacity to ${miningStore.slotInfo.next_upgrade.slot_number} units.`">
                   <div class="t-head">
                      <span class="t-id">EXPANSION_NODE</span>
                   </div>
                   <div class="t-body centered">
                      <span class="plus amber">＋</span>
                      <span>EXPAND_CAPACITY</span>
                      <div class="buy-price ambermonospace">PRICE: {{ miningStore.slotInfo.next_upgrade.price }} {{ miningStore.slotInfo.next_upgrade.currency.toUpperCase() }}</div>
                   </div>
                </div>
              </div>

              <!-- STRATEGIC ADVISORY -->
              <div class="strategic-advisory">
                <div class="section-label">[STRATEGIC_ADVISORY]</div>
                <div class="advisory-grid">
                   <div v-for="(tip, idx) in strategyTips" :key="idx" class="tip-card" :class="tip.type" v-tooltip="'Targeted operational advice for current network loads.'">
                      <div class="tip-head">
                         <span class="tip-status"></span>
                         <span class="tip-title">{{ tip.title }}</span>
                      </div>
                      <p class="tip-desc">{{ tip.desc }}</p>
                      <div class="tip-meta" v-if="tip.req">
                        <span>REQ: {{ tip.req }}</span>
                        <span>TARGET: {{ tip.target }}</span>
                      </div>
                   </div>
                </div>
              </div>
              </template>

              <!-- === FORGE MODE === -->
              <template v-else-if="fleetMode === 'forge'">
                <!-- Forge Header (filter + status joined) -->
                <div class="forge-header-group">
                  <div class="forge-filter-bar">
                     <nav class="forge-cats">
                        <button v-for="cat in forgeCategories" :key="cat"
                           @click="forgeActiveCat = cat; resetForgeScroll()"
                           :class="{ active: forgeActiveCat === cat }">
                           {{ cat }}
                        </button>
                     </nav>
                     <input v-model="forgeSearch" @input="resetForgeScroll()" placeholder="SEARCH_MODS..." class="f-search-input">
                  </div>
                </div>

                <!-- Blueprint Grid -->
                <div class="forge-grid-scroll" @scroll="onForgeScroll">
                  <div class="blueprint-grid-v2">
                     <div v-for="rec in visibleRecipes" :key="rec.id"
                        class="bp-card-v2"
                        :class="[rec.rarity.class, { selected: selectedRecipe?.id === rec.id, forging: !!forgingMap[rec.id] }]"
                        @click="selectRecipe(rec)">
                        <!-- Header: tier + icon -->
                        <div class="bpc-head">
                           <div class="bpc-icon-center"><component :is="rec.result.icon" :size="22" style="opacity: 0.85" /></div>
                           <div class="bpc-tier-badge" :style="{ background: themeHex(rec.rarity.hex) }">T{{ rec.tier }}</div>
                        </div>
                        <!-- Name + type -->
                        <div class="bpc-name">{{ rec.result.name }}</div>
                        <div class="bpc-gives" :class="'gives-' + rec.gives">{{ rec.gives }}</div>
                        <!-- Main stat -->
                        <div class="bpc-stat" :style="{ color: themeHex(rec.rarity.hex) }">{{ rec.result.stat }}</div>
                        <!-- Footer: cost row -->
                        <div class="bpc-meta">
                           <span class="bpc-time"><Timer :size="11" /> {{ formatTime(rec.forgeTime) }}</span>
                           <span class="bpc-cost">{{ rec.forgeCost.amount }} {{ rec.forgeCost.currency }}</span>
                        </div>
                        <!-- Forging progress -->
                        <div v-if="forgingMap[rec.id]" class="bpc-forging">
                           <div class="bpc-forging-track"><div class="bpc-forging-fill" :style="{ width: forgingMap[rec.id].progress + '%' }"></div></div>
                           <span class="bpc-forging-pct">{{ forgingMap[rec.id].progress }}%</span>
                        </div>
                     </div>
                  </div>
                  <div v-if="hasMoreRecipes" class="forge-load-more">
                     <span class="flm-dots">...</span>
                     <span class="flm-text">Scroll para ver más ({{ visibleRecipes.length }}/{{ filteredRecipes.length }})</span>
                  </div>
                  <div v-else-if="filteredRecipes.length === 0" class="forge-empty">
                     <span>No hay blueprints disponibles en esta categoría</span>
                  </div>
                </div>
              </template>

              <!-- === INBOX MODE === -->
              <template v-else-if="fleetMode === 'inbox'">
                <div class="inbox-container">
                  <!-- Inbox Header -->
                  <div class="inbox-header">
                     <div class="isb-left">
                        <Inbox :size="16" />
                        <span class="isb-label">PENDING REWARDS</span>
                        <span class="isb-count">{{ pendingBlocksStore.count }}</span>
                     </div>
                     <div class="isb-right">
                        <span class="isb-total"><Coins :size="14" /> {{ pendingBlocksStore.totalReward.toFixed(4) }}</span>
                        <button v-if="pendingBlocksStore.count > 0" class="isb-claim-all-hold"
                           @mousedown.prevent="onClaimAllHoldStart"
                           @mouseup="onClaimAllHoldEnd"
                           @mouseleave="onClaimAllHoldEnd"
                           @touchstart.prevent="onClaimAllHoldStart"
                           @touchend="onClaimAllHoldEnd"
                           @touchcancel="onClaimAllHoldEnd"
                           :disabled="pendingBlocksStore.claiming">
                           <div class="hold-fill-bar" :style="{ width: claimAllHoldProgress + '%' }"></div>
                           <span class="hold-label">
                              <ArrowDownToLine :size="13" />
                              {{ pendingBlocksStore.claiming ? 'CLAIMING...' : 'CLAIM ALL (' + pendingBlocksStore.totalRonCost.toFixed(4) + ' RON)' }}
                           </span>
                        </button>
                     </div>
                  </div>

                  <!-- Inbox Block List -->
                  <div class="inbox-grid-scroll">
                    <div v-if="pendingBlocksStore.loading" class="inbox-loading">
                       <RotateCw :size="18" class="spin" />
                       <span>Loading blocks...</span>
                    </div>
                    <div v-else-if="pendingBlocksStore.count === 0" class="inbox-empty">
                       <Inbox :size="32" style="opacity: 0.3" />
                       <span>No pending blocks</span>
                       <small>Mined blocks will appear here</small>
                    </div>
                    <div v-else class="inbox-block-list">
                       <div v-for="block in pendingBlocksStore.pendingBlocks" :key="block.id"
                          class="inbox-block-card"
                          :class="{ selected: selectedInboxBlock?.id === block.id, premium: block.is_premium }"
                          @click="selectedInboxBlock = block">
                          <div class="ibc-icon">
                             <Layers :size="16" />
                             <Crown v-if="block.is_premium" :size="10" class="ibc-crown" />
                          </div>
                          <div class="ibc-info">
                             <span class="ibc-height">#{{ block.block_height }}</span>
                             <span class="ibc-date">{{ new Date(block.created_at).toLocaleDateString() }}</span>
                          </div>
                          <div v-if="block.materials_dropped?.length" class="ibc-materials">
                             <Package :size="12" />
                             <span>{{ block.materials_dropped.length }}</span>
                          </div>
                          <div class="ibc-reward">
                             <span class="ibc-amount">+{{ Number(block.reward).toFixed(4) }}</span>
                             <span class="ibc-currency">CRYPTO</span>
                          </div>
                       </div>

                       <button v-if="pendingBlocksStore.hasMore" class="inbox-load-more"
                          @click="pendingBlocksStore.loadMore()"
                          :disabled="pendingBlocksStore.loadingMore">
                          {{ pendingBlocksStore.loadingMore ? 'Loading...' : 'Load more' }}
                       </button>
                    </div>
                  </div>
                </div>
              </template>

              <!-- === INVENTORY MODE === -->
              <template v-else-if="fleetMode === 'inventory'">
                <!-- Inventory Header (filter + status joined) -->
                <div class="forge-header-group">
                  <div class="forge-filter-bar">
                     <nav class="forge-cats">
                        <button v-for="cat in ['all','rigs','cooling','cards','boosts','materials','patches','exp']" :key="cat"
                           @click="invCategory = cat as any"
                           :class="{ active: invCategory === cat }">
                           {{ cat.toUpperCase() }}
                        </button>
                     </nav>
                  </div>
                  <div class="forge-status-bar">
                     <span class="fsb-rank">STORAGE</span>
                     <span class="fsb-level">{{ inventoryStore.slotsUsed }}/{{ inventoryStore.maxSlots }} SLOTS</span>
                     <div class="fsb-xp">
                        <div class="fsb-xp-fill" :style="{ width: (inventoryStore.slotsUsed / inventoryStore.maxSlots * 100) + '%' }"></div>
                     </div>
                  </div>
                </div>

                <!-- Inventory Grid -->
                <div class="forge-grid-scroll">
                  <div v-if="inventoryStore.loading" class="inbox-loading">
                     <RotateCw :size="18" class="spin" style="opacity: 0.85" />
                     <span>LOADING_INVENTORY...</span>
                  </div>
                  <div v-else-if="filteredInvItems.length === 0" class="inbox-empty">
                     <Archive :size="32" style="opacity: 0.4" />
                     <span>{{ invCategory === 'all' ? 'INVENTORY_EMPTY' : 'NO_ITEMS_IN_CATEGORY' }}</span>
                     <small>Visit MARKET to acquire items</small>
                  </div>
                  <div v-else class="blueprint-grid-v2">
                     <div v-for="item in filteredInvItems" :key="item.type + '-' + item.id"
                        class="bp-card-v2 inv-card"
                        :class="{ selected: selectedInvItem?.id === item.id && selectedInvItem?.type === item.type }"
                        @click="selectInvItem(item)">
                        <div class="bpc-head">
                           <div class="bpc-tier-badge" :class="'inv-badge-' + item.badgeClass">{{ item.badge }}</div>
                           <div class="bpc-icon-center"><component :is="item.icon" :size="20" style="opacity: 0.85" /></div>
                        </div>
                        <div class="bpc-name">{{ item.name }}</div>
                        <div class="bpc-stat" style="color: #71717a">{{ item.stat }}</div>
                        <div class="bpc-meta">
                           <span class="bpc-cost">x{{ item.qty }}</span>
                        </div>
                     </div>
                  </div>
                </div>
              </template>

              <!-- MARKET MODE -->
              <template v-else-if="fleetMode === 'market'">
                <div class="forge-header-group">
                  <div class="forge-filter-bar">
                    <nav class="forge-cats">
                      <button v-for="cat in [
                        { key: 'rigs', label: 'RIGS' },
                        { key: 'cooling', label: 'COOLING' },
                        { key: 'components', label: 'MODS' },
                        { key: 'cards', label: 'CARDS' },
                        { key: 'boosts', label: 'BOOSTS' },
                        { key: 'exp_packs', label: 'EXP' },
                        { key: 'crypto', label: 'LANDWORK' }
                      ]" :key="cat.key"
                        @click="marketCategory = cat.key as any"
                        :class="{ active: marketCategory === cat.key }">
                        {{ cat.label }}
                      </button>
                    </nav>
                  </div>
                  <div class="forge-status-bar">
                    <span class="fsb-rank">MARKET_TERMINAL</span>
                  </div>
                </div>
                <div class="forge-grid-scroll">
                  <div v-if="marketLoading" class="inbox-loading">
                    <RotateCw :size="18" class="spin" style="opacity: 0.85" />
                    <span>LOADING_CATALOG...</span>
                  </div>
                  <template v-else>
                    <div class="inv-grid">
                      <!-- RIGS -->
                      <template v-if="marketCategory === 'rigs'">
                        <div v-for="item in marketStore.rigs" :key="item.id" class="inv-card mkt">
                          <div class="ic-head"><span class="ic-tag" :class="tierColor(item.tier)">{{ item.tier.toUpperCase() }}</span><span class="ic-own">OWNED: {{ marketStore.getRigOwned(item.id).total }}</span></div>
                          <div class="ic-name">{{ item.name }}</div>
                          <div class="ic-desc">{{ item.description }}</div>
                          <div class="ic-stats"><span>HASH: {{ item.hashrate }} H/s</span><span>PWR: {{ item.power_consumption }}W</span><span>NET: {{ item.internet_consumption }}</span></div>
                          <div class="ic-buy"><span class="ic-price"><component :is="currencyIcon(item.currency)" :size="12" style="opacity: 0.85" /> {{ item.base_price.toLocaleString() }}</span><button class="buy-btn" :disabled="buyingItem" @click="requestBuy('rig', item.id, item.name, item.base_price, item.currency)">BUY</button></div>
                        </div>
                      </template>
                      <!-- COOLING -->
                      <template v-if="marketCategory === 'cooling'">
                        <div v-for="item in marketStore.coolingItems" :key="item.id" class="inv-card mkt">
                          <div class="ic-head"><span class="ic-tag" :class="tierColor(item.tier)">{{ item.tier.toUpperCase() }}</span><span class="ic-own">OWNED: {{ marketStore.getCoolingOwned(item.id).total }}</span></div>
                          <div class="ic-name">{{ item.name }}</div>
                          <div class="ic-desc">{{ item.description }}</div>
                          <div class="ic-stats"><span>COOL: {{ item.cooling_power }}</span><span>NRG: {{ item.energy_cost }}</span></div>
                          <div class="ic-buy"><span class="ic-price"><Coins :size="12" style="opacity: 0.85" /> {{ item.base_price.toLocaleString() }}</span><button class="buy-btn" :disabled="buyingItem" @click="requestBuy('cooling', item.id, item.name, item.base_price, 'gamecoin')">BUY</button></div>
                        </div>
                      </template>
                      <!-- COMPONENTS -->
                      <template v-if="marketCategory === 'components'">
                        <div v-for="item in marketStore.coolingComponents" :key="item.id" class="inv-card mkt">
                          <div class="ic-head"><span class="ic-tag" :class="tierColor(item.tier)">{{ item.tier.toUpperCase() }}</span><span class="ic-own">OWNED: {{ marketStore.getComponentOwned(item.id) }}</span></div>
                          <div class="ic-name">{{ item.name }}</div>
                          <div class="ic-desc">{{ item.description }}</div>
                          <div class="ic-stats"><span>COOL: {{ item.cooling_power_min }}-{{ item.cooling_power_max }}</span><span>NRG: {{ item.energy_cost_min }}-{{ item.energy_cost_max }}</span></div>
                          <div class="ic-buy"><span class="ic-price"><Coins :size="12" style="opacity: 0.85" /> {{ item.base_price.toLocaleString() }}</span><button class="buy-btn" :disabled="buyingItem" @click="requestBuy('component', item.id, item.name, item.base_price, 'gamecoin')">BUY</button></div>
                        </div>
                      </template>
                      <!-- CARDS -->
                      <template v-if="marketCategory === 'cards'">
                        <div v-for="item in marketStore.prepaidCards" :key="item.id" class="inv-card mkt">
                          <div class="ic-head"><span class="ic-tag cyan">{{ item.card_type.toUpperCase() }}</span><span class="ic-own">OWNED: {{ marketStore.getCardOwned(item.id) }}</span></div>
                          <div class="ic-name">{{ item.name }}</div>
                          <div class="ic-desc">{{ item.description }}</div>
                          <div class="ic-stats"><span>+{{ item.amount }}</span></div>
                          <div class="ic-buy"><span class="ic-price"><component :is="currencyIcon(item.currency)" :size="12" style="opacity: 0.85" /> {{ item.base_price.toLocaleString() }}</span><button class="buy-btn" :disabled="buyingItem" @click="requestBuy('card', item.id, item.name, item.base_price, item.currency)">BUY</button></div>
                        </div>
                      </template>
                      <!-- BOOSTS -->
                      <template v-if="marketCategory === 'boosts'">
                        <div v-for="item in marketStore.boostItems" :key="item.id" class="inv-card mkt">
                          <div class="ic-head"><span class="ic-tag amber">{{ item.boost_type.toUpperCase() }}</span><span class="ic-own">OWNED: {{ marketStore.getBoostOwned(item.id) }}</span></div>
                          <div class="ic-name">{{ item.name }}</div>
                          <div class="ic-desc">{{ item.description }}</div>
                          <div class="ic-stats"><span>+{{ item.effect_value }}%</span><span>{{ item.duration_minutes }}min</span></div>
                          <div class="ic-buy"><span class="ic-price"><component :is="currencyIcon(item.currency)" :size="12" style="opacity: 0.85" /> {{ item.base_price.toLocaleString() }}</span><button class="buy-btn" :disabled="buyingItem" @click="requestBuy('boost', item.id, item.name, item.base_price, item.currency)">BUY</button></div>
                        </div>
                      </template>
                      <!-- EXP PACKS -->
                      <template v-if="marketCategory === 'exp_packs'">
                        <div v-for="item in marketStore.expPacks" :key="item.id" class="inv-card mkt">
                          <div class="ic-head"><span class="ic-tag" :class="tierColor(item.tier)">{{ item.tier.toUpperCase() }}</span><span class="ic-own">OWNED: {{ marketStore.getExpPackOwned(item.id) }}</span></div>
                          <div class="ic-name">{{ item.name }}</div>
                          <div class="ic-desc">{{ item.description }}</div>
                          <div class="ic-stats"><span>+{{ item.xp_amount }} XP</span></div>
                          <div class="ic-buy"><span class="ic-price"><Coins :size="12" style="opacity: 0.85" /> {{ item.base_price.toLocaleString() }}</span><button class="buy-btn" :disabled="buyingItem" @click="requestBuy('exp_pack', item.id, item.name, item.base_price, 'gamecoin')">BUY</button></div>
                        </div>
                      </template>
                      <!-- LANDWORK -->
                      <template v-if="marketCategory === 'crypto'">
                        <div v-for="item in marketStore.cryptoPackages" :key="item.id" class="inv-card mkt" :class="{ featured: item.is_featured }">
                          <div class="ic-head"><span class="ic-tag" :class="tierColor(item.tier)">{{ item.tier.toUpperCase() }}</span><span v-if="item.bonus_percent > 0" class="ic-bonus">+{{ item.bonus_percent }}% BONUS</span></div>
                          <div class="ic-name">{{ item.name }}</div>
                          <div class="ic-desc">{{ item.description }}</div>
                          <div class="ic-stats"><span><Pickaxe :size="12" style="opacity: 0.85" /> {{ item.total_crypto.toLocaleString() }} LW</span></div>
                          <div class="ic-buy"><span class="ic-price"><Gem :size="12" style="opacity: 0.85" /> {{ item.ron_price }} RON</span><button class="buy-btn" :disabled="buyingItem" @click="requestBuy('crypto', item.id, item.name, item.ron_price, 'ron')">BUY</button></div>
                        </div>
                      </template>
                    </div>
                  </template>
                </div>
              </template>

              <!-- EXCHANGE MODE -->
              <template v-else-if="fleetMode === 'exchange'">
                <div class="forge-grid-scroll">
                  <div class="view-exchange">
                    <div v-if="exchangeRates" class="exch-rates">
                      <div class="exch-rate-title">CURRENT_RATES</div>
                      <div class="exch-rate-row" v-if="exchangeRates.crypto_to_gamecoin">
                        <span>1 LW</span>
                        <span class="exch-arrow">=</span>
                        <span class="amber">{{ exchangeRates.crypto_to_gamecoin }} GC</span>
                      </div>
                      <div class="exch-rate-row" v-if="exchangeRates.crypto_to_ron">
                        <span>1 LW</span>
                        <span class="exch-arrow">=</span>
                        <span class="cyan">{{ exchangeRates.crypto_to_ron }} RON</span>
                      </div>
                    </div>

                    <div class="exch-form">
                      <div class="exch-form-title">CONVERT_LANDWORK</div>
                      <div class="exch-input-row">
                        <label class="exch-input-label">AMOUNT:</label>
                        <input type="number" v-model.number="exchangeAmount" min="0" :max="authStore.player?.crypto_balance ?? 0" class="exch-input" placeholder="0" />
                      </div>
                      <div class="exch-target-row">
                        <label class="exch-input-label">TARGET:</label>
                        <div class="exch-target-btns">
                          <button @click="exchangeTarget = 'gamecoin'; exchangeAmount = 0" :class="{ active: exchangeTarget === 'gamecoin' }"><Coins :size="12" style="opacity: 0.85" /> GAMECOIN</button>
                          <button @click="exchangeTarget = 'ron'; exchangeAmount = 0" :class="{ active: exchangeTarget === 'ron' }"><Gem :size="12" style="opacity: 0.85" /> RON</button>
                        </div>
                      </div>
                      <div class="exch-quick-row">
                        <label class="exch-input-label">QUICK:</label>
                        <div class="exch-quick-btns">
                          <button v-for="amt in exchQuickAmounts" :key="amt" @click="setExchQuick(amt)">
                            {{ amt }} {{ exchangeTarget === 'ron' ? 'RON' : 'GC' }}
                          </button>
                        </div>
                      </div>
                      <div v-if="exchangeTarget === 'ron' && exchangeRates?.min_crypto_for_ron" class="exch-min-note">
                        MIN: {{ exchangeRates.min_crypto_for_ron.toLocaleString() }} LW
                      </div>
                      <button class="exch-submit" :disabled="exchanging || exchangeAmount <= 0 || (exchangeTarget === 'ron' && exchangeRates?.min_crypto_for_ron && exchangeAmount < exchangeRates.min_crypto_for_ron)" @click="handleExchange">
                        {{ exchanging ? 'PROCESSING...' : 'EXECUTE_EXCHANGE' }}
                      </button>
                    </div>
                  </div>
                </div>
              </template>
            </div>

            <!-- RIGHT: INTEGRATED COMMAND PANEL -->
            <aside class="command-panel" :class="{ visible: selectedRig || (fleetMode === 'forge' && selectedRecipe) || (fleetMode === 'inbox' && selectedInboxBlock) || (fleetMode === 'inventory' && selectedInvItem) }">
               <div class="cp-hud-corner cp-tl"></div>
               <div class="cp-hud-corner cp-tr"></div>
               <div class="cp-hud-corner cp-bl"></div>
               <div class="cp-hud-corner cp-br"></div>
               <div class="cp-hud-scanline"></div>

               <!-- FORGE MODE: Recipe Detail -->
               <template v-if="fleetMode === 'forge'">
                  <div v-if="!selectedRecipe" class="panel-empty">
                     <span class="pe-icon">⬡</span>
                     <span class="pe-text">SELECT_BLUEPRINT</span>
                     <small class="pe-sub">Click any recipe to see details</small>
                  </div>
                  <div v-else class="panel-inner forge-detail-panel" :key="'forge-' + selectedRecipe.id">
                     <!-- Header -->
                     <div class="detail-header">
                        <span class="badge" :style="{ background: selectedRecipe.rarity.hex }">{{ selectedRecipe.rarity.label }}</span>
                        <div class="detail-header-right">
                           <span class="detail-tier">T{{ selectedRecipe.tier }}</span>
                           <button class="detail-close" @click="selectedRecipe = null">✕</button>
                        </div>
                     </div>

                     <!-- Identity -->
                     <div class="fd-identity">
                        <div class="detail-icon"><component :is="selectedRecipe.result.icon" :size="26" /></div>
                        <div class="fd-identity-info">
                           <div class="detail-name" :style="{ color: selectedRecipe.rarity.hex }">{{ selectedRecipe.result.name }}</div>
                           <div class="detail-cat">{{ selectedRecipe.cat }}</div>
                        </div>
                     </div>

                     <!-- Tags -->
                     <div class="detail-tags">
                        <span class="gives-badge" :class="'gives-' + selectedRecipe.gives">
                           <component :is="({ HASHRATE: Zap, COOLING: Snowflake, ENERGY: Battery, DURABILITY: Shield, BOOSTER: Rocket, NONE: Puzzle } as Record<string,any>)[selectedRecipe.gives]" :size="12" />
                           {{ ({ HASHRATE: 'HASHRATE', COOLING: 'COOLING', ENERGY: 'ENERGY', DURABILITY: 'DURABILITY', BOOSTER: 'BOOSTER', NONE: 'COMBINE' } as Record<string,string>)[selectedRecipe.gives] }}
                        </span>
                        <span class="usage-badge" :class="'usage-' + selectedRecipe.usage">
                           <component :is="({ RIG_INSTALL: Settings, COMBINE: Puzzle, BOOSTER: Rocket, MATERIAL: Wrench } as Record<string,any>)[selectedRecipe.usage]" :size="12" />
                           {{ ({ RIG_INSTALL: 'INSTALL', COMBINE: 'COMBINE', BOOSTER: 'USE', MATERIAL: 'MATERIAL' } as Record<string,string>)[selectedRecipe.usage] }}
                        </span>
                     </div>

                     <!-- Description -->
                     <div class="detail-desc">{{ selectedRecipe.desc }}</div>

                     <!-- Stats card -->
                     <div class="fd-card">
                        <div class="fd-card-title">STATS</div>
                        <div class="fd-stat-main">
                           <span class="fd-stat-value" :style="{ color: selectedRecipe.rarity.hex }">{{ selectedRecipe.result.stat || '—' }}</span>
                           <span class="fd-stat-abi">{{ selectedRecipe.result.abi || '' }}</span>
                        </div>
                     </div>

                     <!-- Consumes card -->
                     <div v-if="selectedRecipe.result.consumes" class="fd-card fd-card-warn">
                        <div class="fd-card-title">CONSUMES / TICK</div>
                        <div class="fd-grid fd-grid-3">
                           <div class="fd-cell">
                              <span class="fd-label"><Snowflake :size="11" /> HP</span>
                              <span class="fd-value consume-val">-{{ selectedRecipe.result.consumes.coolHP }}</span>
                           </div>
                           <div class="fd-cell">
                              <span class="fd-label"><Battery :size="11" /> Energy</span>
                              <span class="fd-value consume-val">-{{ selectedRecipe.result.consumes.energy }}W</span>
                           </div>
                           <div class="fd-cell">
                              <span class="fd-label"><Globe :size="11" /> Net</span>
                              <span class="fd-value consume-val">-{{ selectedRecipe.result.consumes.internet }}Mb</span>
                           </div>
                        </div>
                     </div>

                     <!-- Forge cost card -->
                     <div class="fd-card">
                        <div class="fd-card-title">FORGE COST</div>
                        <div class="fd-grid fd-grid-3">
                           <div class="fd-cell">
                              <span class="fd-label"><Timer :size="11" /> Time</span>
                              <span class="fd-value">{{ formatTime(selectedRecipe.forgeTime) }}</span>
                           </div>
                           <div class="fd-cell">
                              <span class="fd-label"><Gem :size="11" /> Cost</span>
                              <span class="fd-value cost-val">{{ selectedRecipe.forgeCost.amount }}</span>
                              <span class="fd-unit">{{ selectedRecipe.forgeCost.currency }}</span>
                           </div>
                           <div class="fd-cell">
                              <span class="fd-label"><Globe :size="11" /> Net</span>
                              <span class="fd-value nrg-val">{{ selectedRecipe.netCost }}</span>
                           </div>
                        </div>
                     </div>

                     <!-- Materials -->
                     <div v-if="selectedRecipe.inputs && selectedRecipe.inputs.length" class="fd-card">
                        <div class="fd-card-title">MATERIALS</div>
                        <div class="detail-mats">
                           <div v-for="(inp, idx) in selectedRecipe.inputs" :key="idx"
                              class="dm-row" :class="{ ok: hasItem(inp.name) }">
                              <span class="dm-icon"><component :is="inp.type === 'recipe' ? Puzzle : Wrench" :size="13" /></span>
                              <span class="dm-name">{{ inp.name }}</span>
                              <span class="dm-qty">x{{ inp.qty }}</span>
                              <span class="dm-status">{{ hasItem(inp.name) ? '✓' : '✗' }}</span>
                           </div>
                        </div>
                     </div>

                     <!-- Forging progress -->
                     <div v-if="forgingMap[selectedRecipe.id]" class="forge-progress-bar">
                        <div class="fpb-label">{{ forgingMap[selectedRecipe.id].label }}</div>
                        <div class="fpb-track">
                           <div class="fpb-fill" :style="{ width: forgingMap[selectedRecipe.id].progress + '%' }"></div>
                        </div>
                        <div class="fpb-pct">{{ forgingMap[selectedRecipe.id].progress }}%</div>
                     </div>

                     <!-- Forge button -->
                     <button class="forge-trigger"
                        :disabled="isRecipeLocked(selectedRecipe) || !selectedRecipe.inputs.every((inp: any) => hasItem(inp.name)) || !!forgingMap[selectedRecipe.id] || (authStore.player?.internet ?? 0) < (selectedRecipe.netCost ?? 0)"
                        @click="handleStartForge">
                        <span v-if="isRecipeLocked(selectedRecipe)"><Lock :size="14" /> LVL {{ tierMinLevel(selectedRecipe.tier) }}</span>
                        <span v-else-if="(authStore.player?.internet ?? 0) < (selectedRecipe.netCost ?? 0)"><Globe :size="14" /> LOW NET CHANNEL</span>
                        <span v-else-if="forgingMap[selectedRecipe.id]">FORGING...</span>
                        <span v-else>FORGE</span>
                     </button>
                  </div>
               </template>

               <!-- INBOX MODE: Block Detail -->
               <template v-else-if="fleetMode === 'inbox'">
                  <div v-if="!selectedInboxBlock" class="panel-empty">
                     <span class="pe-icon"><Inbox :size="24" style="opacity: 0.5" /></span>
                     <span class="pe-text">SELECT_BLOCK</span>
                     <small class="pe-sub">Click a pending block to view details</small>
                  </div>
                  <div v-else class="panel-inner inbox-detail-panel" :key="'inbox-' + selectedInboxBlock.id">
                     <div class="detail-header">
                        <span class="badge" :style="{ background: selectedInboxBlock.is_premium ? '#d4a017' : '#8a60b0' }">
                           {{ selectedInboxBlock.is_premium ? 'PREMIUM' : 'STANDARD' }}
                        </span>
                        <div class="detail-header-right">
                           <button class="detail-close" @click="selectedInboxBlock = null">✕</button>
                        </div>
                     </div>

                     <div class="fd-identity">
                        <div class="detail-icon"><Layers :size="26" /></div>
                        <div class="fd-identity-info">
                           <div class="detail-name" style="color: #8a60b0">BLOCK #{{ selectedInboxBlock.block_height }}</div>
                           <div class="detail-cat">{{ new Date(selectedInboxBlock.created_at).toLocaleString() }}</div>
                        </div>
                     </div>

                     <div class="fd-card">
                        <div class="fd-card-title">REWARD</div>
                        <div class="fd-stat-main">
                           <span class="fd-stat-value" style="color: #d4a017">{{ Number(selectedInboxBlock.reward).toFixed(6) }} CRYPTO</span>
                        </div>
                        <div v-if="selectedInboxBlock.shares_contributed" class="fd-grid" style="margin-top: 0.4rem">
                           <div class="fd-cell">
                              <span class="fd-label"><Zap :size="11" /> Shares</span>
                              <span class="fd-value">{{ selectedInboxBlock.shares_contributed }} / {{ selectedInboxBlock.total_block_shares }}</span>
                           </div>
                           <div v-if="selectedInboxBlock.share_percentage" class="fd-cell">
                              <span class="fd-label"><Network :size="11" /> Contribution</span>
                              <span class="fd-value" style="color: #8a60b0">{{ selectedInboxBlock.share_percentage.toFixed(2) }}%</span>
                           </div>
                        </div>
                     </div>

                     <div v-if="selectedInboxBlock.materials_dropped?.length" class="fd-card">
                        <div class="fd-card-title">MATERIALS</div>
                        <div class="detail-mats">
                           <div v-for="(mat, idx) in selectedInboxBlock.materials_dropped" :key="idx" class="dm-row ok">
                              <span class="dm-icon"><Package :size="13" /></span>
                              <span class="dm-name">{{ mat.name }}</span>
                              <span class="dm-qty" v-if="mat.count">x{{ mat.count }}</span>
                           </div>
                        </div>
                     </div>

                     <div class="inbox-claim-section" style="margin-top: auto;">
                        <button class="forge-trigger inbox-claim-btn"
                           @click="openClaimModal(selectedInboxBlock.id)"
                           :disabled="pendingBlocksStore.claiming">
                           <ArrowDownToLine :size="14" /> CLAIM BLOCK
                        </button>
                        <div class="inbox-claim-cost">
                           <small>FREE CLAIM (captcha verification)</small>
                        </div>
                     </div>
                  </div>
               </template>

               <!-- INVENTORY MODE: Item Detail -->
               <template v-else-if="fleetMode === 'inventory'">
                  <div v-if="!selectedInvItem" class="panel-empty">
                     <span class="pe-icon"><Archive :size="24" style="opacity: 0.5" /></span>
                     <span class="pe-text">SELECT_ITEM</span>
                     <small class="pe-sub">Click an item to view details</small>
                  </div>
                  <div v-else class="panel-inner inv-detail-panel" :key="'inv-' + selectedInvItem.type + selectedInvItem.id">
                     <div class="detail-header">
                        <span class="badge inv-type-badge">{{ selectedInvItem.type.toUpperCase().replace('_', ' ') }}</span>
                        <div class="detail-header-right">
                           <button class="detail-close" @click="selectedInvItem = null">✕</button>
                        </div>
                     </div>

                     <!-- RIG detail -->
                     <template v-if="selectedInvItem.type === 'rig'">
                        <div class="detail-icon"><Pickaxe :size="28" style="opacity: 0.85" /></div>
                        <div class="detail-name" style="color: #f59e0b">{{ selectedInvItem.data.name }}</div>
                        <div class="section-label mt-1">SPECS</div>
                        <div class="detail-stats">
                           <div class="ds-row"><span><Zap :size="12" style="opacity: 0.85" /> HASHRATE</span><span class="ds-val" style="color: #f59e0b">{{ selectedInvItem.data.hashrate }} H/s</span></div>
                           <div class="ds-row"><span><Battery :size="12" style="opacity: 0.85" /> POWER</span><span class="ds-val">{{ selectedInvItem.data.power_consumption }}W</span></div>
                           <div class="ds-row"><span><Globe :size="12" style="opacity: 0.85" /> INTERNET</span><span class="ds-val">{{ selectedInvItem.data.internet_consumption }}Mb</span></div>
                           <div class="ds-row"><span>TIER</span><span class="ds-val">{{ selectedInvItem.data.tier }}</span></div>
                           <div class="ds-row"><span>QTY</span><span class="ds-val">x{{ selectedInvItem.data.quantity }}</span></div>
                        </div>
                        <div class="inv-actions mt-1">
                           <button class="hold-btn" :disabled="invActionLoading || !miningStore.slotInfo?.available_slots"
                              @mousedown="startInvHold('install_rig', { rigId: selectedInvItem.data.rig_id })"
                              @mouseup="cancelInvHold" @mouseleave="cancelInvHold"
                              @touchstart.prevent="startInvHold('install_rig', { rigId: selectedInvItem.data.rig_id })"
                              @touchend="cancelInvHold" @touchcancel="cancelInvHold">
                              <div class="hold-fill" :style="{ width: invHoldPct + '%' }"></div>
                              <span class="hold-label"><Settings :size="14" style="opacity: 0.85" /> HOLD · INSTALL</span>
                           </button>
                           <button class="inv-action-btn danger" @click="requestInvAction('delete_item', 'DISCARD', { itemType: 'rig', itemId: selectedInvItem.data.rig_id })">
                              <Trash2 :size="12" style="opacity: 0.85" /> DISCARD
                           </button>
                        </div>
                     </template>

                     <!-- COOLING detail -->
                     <template v-else-if="selectedInvItem.type === 'cooling'">
                        <div class="detail-icon"><Snowflake :size="28" style="opacity: 0.85" /></div>
                        <div class="detail-name" style="color: #06b6d4">{{ selectedInvItem.data.name }}</div>
                        <div class="section-label mt-1">SPECS</div>
                        <div class="detail-stats">
                           <div class="ds-row"><span><Snowflake :size="12" style="opacity: 0.85" /> COOLING</span><span class="ds-val" style="color: #06b6d4">{{ selectedInvItem.data.cooling_power }} CP</span></div>
                           <div class="ds-row"><span><Battery :size="12" style="opacity: 0.85" /> ENERGY</span><span class="ds-val">{{ selectedInvItem.data.energy_cost }} NRG</span></div>
                           <div class="ds-row"><span>MOD SLOTS</span><span class="ds-val">{{ selectedInvItem.data.max_mod_slots }}</span></div>
                           <div class="ds-row"><span>TIER</span><span class="ds-val">{{ selectedInvItem.data.tier }}</span></div>
                        </div>
                        <div class="inv-actions mt-1">
                           <button class="inv-action-btn danger" @click="requestInvAction('delete_item', 'DISCARD', { itemType: 'cooling', itemId: selectedInvItem.data.inventory_id })">
                              <Trash2 :size="12" style="opacity: 0.85" /> DISCARD
                           </button>
                        </div>
                     </template>

                     <!-- MODDED COOLING detail -->
                     <template v-else-if="selectedInvItem.type === 'modded_cooling'">
                        <div class="detail-icon"><Snowflake :size="28" style="opacity: 0.85" /></div>
                        <div class="detail-name" style="color: #06b6d4">{{ selectedInvItem.data.name }}</div>
                        <div class="detail-cat">MODDED</div>
                        <div class="section-label mt-1">EFFECTIVE_STATS</div>
                        <div class="detail-stats">
                           <div class="ds-row"><span><Snowflake :size="12" style="opacity: 0.85" /> COOLING</span><span class="ds-val" style="color: #06b6d4">{{ selectedInvItem.data.effective_cooling_power }} CP</span></div>
                           <div class="ds-row"><span><Battery :size="12" style="opacity: 0.85" /> ENERGY</span><span class="ds-val">{{ selectedInvItem.data.effective_energy_cost }} NRG</span></div>
                           <div class="ds-row"><span>MODS</span><span class="ds-val">{{ selectedInvItem.data.mod_slots_used }}/{{ selectedInvItem.data.max_mod_slots }}</span></div>
                           <div class="ds-row"><span><Shield :size="12" style="opacity: 0.85" /> DURABILITY</span><span class="ds-val">{{ selectedInvItem.data.total_durability_mod > 0 ? '+' : '' }}{{ selectedInvItem.data.total_durability_mod }}</span></div>
                        </div>
                        <div class="inv-actions mt-1">
                           <button class="inv-action-btn danger" @click="requestInvAction('delete_item', 'DISCARD', { itemType: 'modded_cooling', itemId: selectedInvItem.data.player_cooling_item_id })">
                              <Trash2 :size="12" style="opacity: 0.85" /> DISCARD
                           </button>
                        </div>
                     </template>

                     <!-- COMPONENT detail -->
                     <template v-else-if="selectedInvItem.type === 'component'">
                        <div class="detail-icon"><Wrench :size="28" style="opacity: 0.85" /></div>
                        <div class="detail-name" style="color: #a78bfa">{{ selectedInvItem.data.name }}</div>
                        <div class="section-label mt-1">MOD_RANGES</div>
                        <div class="detail-stats">
                           <div class="ds-row"><span><Snowflake :size="12" style="opacity: 0.85" /> COOLING</span><span class="ds-val">{{ selectedInvItem.data.cooling_power_min }}–{{ selectedInvItem.data.cooling_power_max }}</span></div>
                           <div class="ds-row"><span><Battery :size="12" style="opacity: 0.85" /> ENERGY</span><span class="ds-val">{{ selectedInvItem.data.energy_cost_min }}–{{ selectedInvItem.data.energy_cost_max }}</span></div>
                           <div class="ds-row"><span><Shield :size="12" style="opacity: 0.85" /> DURABILITY</span><span class="ds-val">{{ selectedInvItem.data.durability_min }}–{{ selectedInvItem.data.durability_max }}</span></div>
                           <div class="ds-row"><span>QTY</span><span class="ds-val">x{{ selectedInvItem.data.quantity }}</span></div>
                        </div>
                        <div class="inv-actions mt-1">
                           <button class="inv-action-btn danger" @click="requestInvAction('delete_item', 'DISCARD', { itemType: 'component', itemId: selectedInvItem.data.inventory_id })">
                              <Trash2 :size="12" style="opacity: 0.85" /> DISCARD
                           </button>
                        </div>
                     </template>

                     <!-- CARD detail -->
                     <template v-else-if="selectedInvItem.type === 'card'">
                        <div class="detail-icon"><CreditCard :size="28" style="opacity: 0.85" /></div>
                        <div class="detail-name" style="color: #22c55e">{{ selectedInvItem.data.name || selectedInvItem.data.card_type.toUpperCase() + ' CARD' }}</div>
                        <div class="section-label mt-1">CARD_DATA</div>
                        <div class="detail-stats">
                           <div class="ds-row"><span>TYPE</span><span class="ds-val">{{ selectedInvItem.data.card_type.toUpperCase() }}</span></div>
                           <div class="ds-row"><span>AMOUNT</span><span class="ds-val" style="color: #22c55e">+{{ selectedInvItem.data.amount }}</span></div>
                           <div class="ds-row"><span>CODE</span><span class="ds-val monospace">{{ selectedInvItem.data.code }}</span></div>
                        </div>
                        <div class="inv-actions mt-1">
                           <button class="hold-btn" :disabled="invActionLoading"
                              @mousedown="startInvHold('redeem_card', { code: selectedInvItem.data.code })"
                              @mouseup="cancelInvHold" @mouseleave="cancelInvHold"
                              @touchstart.prevent="startInvHold('redeem_card', { code: selectedInvItem.data.code })"
                              @touchend="cancelInvHold" @touchcancel="cancelInvHold">
                              <div class="hold-fill" :style="{ width: invHoldPct + '%' }"></div>
                              <span class="hold-label"><CheckCircle :size="14" style="opacity: 0.85" /> HOLD · REDEEM</span>
                           </button>
                           <button class="inv-action-btn danger" @click="requestInvAction('delete_item', 'DISCARD', { itemType: 'card', itemId: selectedInvItem.data.id })">
                              <Trash2 :size="12" style="opacity: 0.85" /> DISCARD
                           </button>
                        </div>
                     </template>

                     <!-- BOOST detail -->
                     <template v-else-if="selectedInvItem.type === 'boost'">
                        <div class="detail-icon"><Rocket :size="28" style="opacity: 0.85" /></div>
                        <div class="detail-name" style="color: #f59e0b">{{ selectedInvItem.data.name }}</div>
                        <div class="section-label mt-1">BOOST_DATA</div>
                        <div class="detail-stats">
                           <div class="ds-row"><span>TYPE</span><span class="ds-val">{{ selectedInvItem.data.boost_type }}</span></div>
                           <div class="ds-row"><span>EFFECT</span><span class="ds-val" style="color: #22c55e">+{{ selectedInvItem.data.effect_value }}%</span></div>
                           <div class="ds-row"><span>DURATION</span><span class="ds-val">{{ selectedInvItem.data.duration_minutes }} min</span></div>
                           <div class="ds-row"><span>QTY</span><span class="ds-val">x{{ selectedInvItem.data.quantity }}</span></div>
                        </div>
                        <div class="inv-hint">Install boosts from the rig command panel</div>
                        <div class="inv-actions mt-1">
                           <button class="inv-action-btn danger" @click="requestInvAction('delete_item', 'DISCARD', { itemType: 'boost', itemId: selectedInvItem.data.id })">
                              <Trash2 :size="12" style="opacity: 0.85" /> DISCARD
                           </button>
                        </div>
                     </template>

                     <!-- MATERIAL detail -->
                     <template v-else-if="selectedInvItem.type === 'material'">
                        <div class="detail-icon"><Gem :size="28" style="opacity: 0.85" /></div>
                        <div class="detail-name" style="color: #a78bfa">{{ selectedInvItem.data.name }}</div>
                        <div class="section-label mt-1">MATERIAL_DATA</div>
                        <div class="detail-stats">
                           <div class="ds-row"><span>RARITY</span><span class="ds-val" :style="{ color: { common: '#71717a', uncommon: '#22c55e', rare: '#3b82f6', epic: '#a855f7' }[selectedInvItem.data.rarity as string] || '#71717a' }">{{ selectedInvItem.data.rarity.toUpperCase() }}</span></div>
                           <div class="ds-row"><span>QTY</span><span class="ds-val">x{{ selectedInvItem.data.quantity }}</span></div>
                        </div>
                        <div class="inv-hint">Materials are used in THE_FORGE</div>
                        <div class="inv-actions mt-1">
                           <button class="inv-action-btn danger" @click="requestInvAction('delete_item', 'DISCARD', { itemType: 'material', itemId: selectedInvItem.data.material_id })">
                              <Trash2 :size="12" style="opacity: 0.85" /> DISCARD
                           </button>
                        </div>
                     </template>

                     <!-- PATCH detail -->
                     <template v-else-if="selectedInvItem.type === 'patch'">
                        <div class="detail-icon"><Sticker :size="28" style="opacity: 0.85" /></div>
                        <div class="detail-name" style="color: #22c55e">RIG_PATCH</div>
                        <div class="section-label mt-1">EFFECTS</div>
                        <div class="detail-stats">
                           <div class="ds-row"><span><Shield :size="12" style="opacity: 0.85" /> CONDITION</span><span class="ds-val" style="color: #22c55e">+35%</span></div>
                           <div class="ds-row"><span><Zap :size="12" style="opacity: 0.85" /> HASHRATE</span><span class="ds-val" style="color: #ef4444">-10%</span></div>
                           <div class="ds-row"><span><Battery :size="12" style="opacity: 0.85" /> POWER</span><span class="ds-val" style="color: #ef4444">+15%</span></div>
                           <div class="ds-row"><span>QTY</span><span class="ds-val">x{{ selectedInvItem.data.quantity }}</span></div>
                        </div>
                        <div class="inv-actions mt-1">
                           <button class="hold-btn" :disabled="invActionLoading"
                              @click="openRigSelect(selectedInvItem.data)">
                              <span class="hold-label"><Wrench :size="14" style="opacity: 0.85" /> APPLY_TO_RIG</span>
                           </button>
                           <button class="inv-action-btn danger" @click="requestInvAction('delete_item', 'DISCARD', { itemType: 'patch', itemId: selectedInvItem.data.inventory_id })">
                              <Trash2 :size="12" style="opacity: 0.85" /> DISCARD
                           </button>
                        </div>
                     </template>

                     <!-- EXP PACK detail -->
                     <template v-else-if="selectedInvItem.type === 'exp_pack'">
                        <div class="detail-icon"><BookOpen :size="28" style="opacity: 0.85" /></div>
                        <div class="detail-name" style="color: #f59e0b">{{ selectedInvItem.data.name }}</div>
                        <div class="section-label mt-1">PACK_DATA</div>
                        <div class="detail-stats">
                           <div class="ds-row"><span>XP</span><span class="ds-val" style="color: #f59e0b">+{{ selectedInvItem.data.xp_amount }}</span></div>
                           <div class="ds-row"><span>TIER</span><span class="ds-val">{{ selectedInvItem.data.tier }}</span></div>
                           <div class="ds-row"><span>QTY</span><span class="ds-val">x{{ selectedInvItem.data.quantity }}</span></div>
                        </div>
                        <div class="inv-actions mt-1">
                           <button class="hold-btn" :disabled="invActionLoading"
                              @mousedown="startInvHold('use_exp_pack', { packId: selectedInvItem.data.item_id })"
                              @mouseup="cancelInvHold" @mouseleave="cancelInvHold"
                              @touchstart.prevent="startInvHold('use_exp_pack', { packId: selectedInvItem.data.item_id })"
                              @touchend="cancelInvHold" @touchcancel="cancelInvHold">
                              <div class="hold-fill" :style="{ width: invHoldPct + '%' }"></div>
                              <span class="hold-label"><BookOpen :size="14" style="opacity: 0.85" /> HOLD · USE</span>
                           </button>
                           <button class="inv-action-btn danger" @click="requestInvAction('delete_item', 'DISCARD', { itemType: 'exp_pack', itemId: selectedInvItem.data.inventory_id })">
                              <Trash2 :size="12" style="opacity: 0.85" /> DISCARD
                           </button>
                        </div>
                     </template>
                  </div>
               </template>

               <!-- RIGS MODE: Rig Detail -->
               <template v-else>
               <div v-if="!selectedRigId || !selectedRig" class="panel-empty">
                  <span class="pe-icon">⬡</span>
                  <span class="pe-text">SELECT_NODE</span>
                  <small class="pe-sub">Choose a node to view diagnostics</small>
               </div>
               <div v-else class="panel-inner" :key="selectedRigId">
                  <!-- RIG HEADER -->
                  <div class="panel-title">
                     <div class="title-top">
                        <span class="hud-indicator ind-green" style="width:5px;height:5px;"></span>
                        <span class="diag-tag">UNIT_UPLINK</span>
                        <div v-if="selectedRig.is_active" class="mode-tag" :class="selectedRig.mining_mode || 'pool'">{{ (selectedRig.mining_mode || 'pool').toUpperCase() }}</div>
                     </div>
                     <h1 style="font-size: 1rem; margin: 0;">{{ selectedRig.rig.name }}</h1>
                  </div>

                  <!-- CONFIG TABS -->
                  <nav class="config-tabs">
                     <button v-for="t in ['status', 'components']"
                        :key="t"
                        @click="configTab = t as any"
                        :class="{ active: configTab === t }"
                        v-tooltip="t === 'status' ? 'Thermal & structural health' : 'Hardware modules & temporary boosters'">
                        {{ t.toUpperCase() }}
                     </button>
                  </nav>


                  <!-- SKELETON LOADING -->
                  <div class="config-content" v-if="loadingConfig">
                     <div class="skel-status">
                        <div class="skel-title"><div class="skel-line skel-w40"></div></div>
                        <div class="skel-card" v-for="n in 3" :key="n">
                           <div class="skel-row">
                              <div class="skel-dot"></div>
                              <div class="skel-line skel-w30"></div>
                              <div class="skel-line skel-w20" style="margin-left:auto"></div>
                           </div>
                           <div class="skel-bar"></div>
                           <div class="skel-row">
                              <div class="skel-line skel-w40"></div>
                              <div class="skel-line skel-w25" style="margin-left:auto"></div>
                           </div>
                        </div>
                        <div class="skel-title" style="margin-top:8px"><div class="skel-line skel-w50"></div></div>
                        <div class="skel-modules">
                           <div class="skel-mod" v-for="n in 3" :key="'m'+n">
                              <div class="skel-line skel-w30"></div>
                              <div class="skel-line skel-w20"></div>
                           </div>
                        </div>
                     </div>
                  </div>

                  <div class="config-content" v-if="!loadingConfig">
                     <!-- TAB: STATUS & REPAIR -->
                     <div v-if="configTab === 'status'" class="tab-pane">
                        <div class="panel-telemetry">
                           <div class="tele-hud-title">
                              <span class="thud-line"></span>
                              <span class="thud-txt">SYS_DIAGNOSTICS</span>
                              <span class="thud-line"></span>
                              <span class="thud-blink"></span>
                           </div>
                           <!-- THERMAL -->
                           <div class="tele-hud" :class="{ 'hud-warn': selectedRig.temperature > 70, 'hud-danger': selectedRig.temperature > 85 }">
                              <div class="hud-corner hud-tl"></div>
                              <div class="hud-corner hud-tr"></div>
                              <div class="hud-corner hud-bl"></div>
                              <div class="hud-corner hud-br"></div>
                              <div class="hud-scanline"></div>
                              <div class="hud-row-top">
                                 <span class="hud-indicator" :class="selectedRig.temperature > 85 ? 'ind-red' : selectedRig.temperature > 70 ? 'ind-amber' : 'ind-green'"></span>
                                 <span class="hud-sys-id">THR.CORE</span>
                                 <span class="hud-readout" :class="{ hot: selectedRig.temperature > 80 }">{{ Math.round(selectedRig.temperature) }}<small>°C</small></span>
                              </div>
                              <div class="hud-gauge">
                                 <div class="hud-gauge-track">
                                    <div class="hud-gauge-fill hud-fill-amber" :style="{ width: selectedRig.temperature + '%' }" :class="{ 'hud-fill-red': selectedRig.temperature > 80 }"></div>
                                    <div class="hud-gauge-segments"></div>
                                 </div>
                                 <div class="hud-gauge-ticks">
                                    <span>0</span><span>25</span><span>50</span><span>75</span><span>100</span>
                                 </div>
                              </div>
                              <div class="hud-row-bot">
                                 <span class="hud-tag">{{ selectedRig.temperature > 85 ? '!! CRITICAL !!' : selectedRig.temperature > 70 ? '// ELEVATED' : '// NOMINAL' }}</span>
                                 <span class="hud-aux">MAX: 100°C</span>
                              </div>
                           </div>
                           <!-- INTEGRITY -->
                           <div class="tele-hud" :class="{ 'hud-warn': selectedRig.condition < 50, 'hud-danger': selectedRig.condition < 25 }">
                              <div class="hud-corner hud-tl"></div>
                              <div class="hud-corner hud-tr"></div>
                              <div class="hud-corner hud-bl"></div>
                              <div class="hud-corner hud-br"></div>
                              <div class="hud-scanline"></div>
                              <div class="hud-row-top">
                                 <span class="hud-indicator" :class="selectedRig.condition < 25 ? 'ind-red' : selectedRig.condition < 50 ? 'ind-amber' : 'ind-cyan'"></span>
                                 <span class="hud-sys-id">INT.INDEX</span>
                                 <span class="hud-readout hud-readout-cyan">{{ selectedRig.condition }}<small>%</small></span>
                              </div>
                              <div class="hud-gauge">
                                 <div class="hud-gauge-track">
                                    <div class="hud-gauge-fill hud-fill-cyan" :style="{ width: selectedRig.condition + '%' }" :class="{ 'hud-fill-red': selectedRig.condition < 25 }"></div>
                                    <div class="hud-gauge-segments"></div>
                                 </div>
                                 <div class="hud-gauge-ticks">
                                    <span>0</span><span>25</span><span>50</span><span>75</span><span>100</span>
                                 </div>
                              </div>
                              <div class="hud-row-bot">
                                 <span class="hud-tag">{{ selectedRig.condition < 25 ? '!! FAILING !!' : selectedRig.condition < 50 ? '// DEGRADED' : '// OPERATIONAL' }}</span>
                                 <span class="hud-aux">HULL: {{ selectedRig.condition > 75 ? 'SOLID' : 'WORN' }}</span>
                              </div>
                           </div>
                           <!-- LIFETIME -->
                           <div class="tele-hud" :class="{ 'hud-warn': getNodeLifePercent(selectedRig) < 50, 'hud-danger': getNodeLifePercent(selectedRig) < 20 }">
                              <div class="hud-corner hud-tl"></div>
                              <div class="hud-corner hud-tr"></div>
                              <div class="hud-corner hud-bl"></div>
                              <div class="hud-corner hud-br"></div>
                              <div class="hud-scanline"></div>
                              <div class="hud-row-top">
                                 <span class="hud-indicator" :class="getNodeLifePercent(selectedRig) < 20 ? 'ind-red' : getNodeLifePercent(selectedRig) < 50 ? 'ind-amber' : 'ind-green'"></span>
                                 <span class="hud-sys-id">NOD.LIFE</span>
                                 <span class="hud-readout hud-readout-green">{{ getNodeTimeRemaining(selectedRig) }}</span>
                              </div>
                              <div class="hud-gauge">
                                 <div class="hud-gauge-track">
                                    <div class="hud-gauge-fill hud-fill-green" :style="{ width: getNodeLifePercent(selectedRig) + '%' }" :class="{ 'hud-fill-red': getNodeLifePercent(selectedRig) < 20 }"></div>
                                    <div class="hud-gauge-segments"></div>
                                 </div>
                                 <div class="hud-gauge-ticks">
                                    <span>0</span><span>25</span><span>50</span><span>75</span><span>100</span>
                                 </div>
                              </div>
                              <div class="hud-row-bot">
                                 <span class="hud-tag">{{ getNodeLifePercent(selectedRig) < 20 ? '!! LOW !!' : getNodeLifePercent(selectedRig) < 50 ? '// MODERATE' : '// HEALTHY' }}</span>
                                 <span class="hud-aux">CYCLE: ACTIVE</span>
                              </div>
                           </div>
                        </div>
                        <!-- Component Summary -->
                        <div class="comp-summary">
                           <div class="tele-hud-title" style="margin-top:4px;">
                              <span class="thud-line"></span>
                              <span class="thud-txt">INSTALLED_MODULES</span>
                              <span class="thud-line"></span>
                              <span class="thud-blink"></span>
                           </div>
                           <div class="cs-grid">
                              <div class="cs-item" v-if="installedCooling && installedCooling.length > 0">
                                 <span class="cs-type">COOLING</span>
                                 <span class="cs-val cyan">{{ installedCooling.length }}x</span>
                                 <div class="cs-detail">
                                    <span>HP: {{ Math.round(installedCooling.reduce((a: number, c: any) => a + c.durability, 0)) }}</span>
                                    <span>PWR: +{{ installedCooling.reduce((a: number, c: any) => a + (c.effective_cooling_power || c.cooling_power), 0) }}</span>
                                 </div>
                              </div>
                              <div class="cs-item" v-else>
                                 <span class="cs-type">COOLING</span>
                                 <span class="cs-val dim">NONE</span>
                              </div>
                              <div class="cs-item" v-if="installedPower && installedPower.length > 0">
                                 <span class="cs-type">POWER</span>
                                 <span class="cs-val amber">{{ installedPower.length }}x</span>
                                 <div class="cs-detail">
                                    <span>SUPPLY: +{{ installedPower.reduce((a: number, p: any) => a + p.power_supply, 0) }}W</span>
                                 </div>
                              </div>
                              <div class="cs-item" v-else>
                                 <span class="cs-type">POWER</span>
                                 <span class="cs-val dim">NONE</span>
                              </div>
                              <div class="cs-item" v-if="installedBoosts && installedBoosts.length > 0">
                                 <span class="cs-type">BOOSTS</span>
                                 <span class="cs-val amber">{{ installedBoosts.length }}x</span>
                                 <div class="cs-detail">
                                    <span v-for="b in installedBoosts" :key="b.id">{{ b.boost_type.toUpperCase() }} +{{ b.effect_value }}% ({{ formatBoostTime(b.remaining_seconds) }})</span>
                                 </div>
                              </div>
                              <div class="cs-item" v-else>
                                 <span class="cs-type">BOOSTS</span>
                                 <span class="cs-val dim">NONE</span>
                              </div>
                           </div>
                        </div>

                     </div>

                     <!-- TAB: COMPONENTS (UNIFIED LIST) -->
                     <div v-if="configTab === 'components'" class="tab-pane scroll">
                        <div class="socket-grid">

                           <!-- INSTALLED: Cooling -->
                           <div class="comp-section-label" v-if="installedCooling.length">COOLING ({{ installedCooling.length }})</div>
                           <div class="socket-slot" v-for="c in installedCooling" :key="'cool-'+c.id">
                              <div class="s-content">
                                 <div class="item-equipped-v2">
                                    <div class="ie-top">
                                       <span class="i-tag cyan-bg">COOLING</span>
                                       <span class="i-name">{{ c.name }}</span>
                                       <button class="i-remove" @click="requestEject('cooling', c.id, c.name)">EJECT</button>
                                    </div>
                                    <div class="ie-stats">
                                       <div class="ie-bar"><div class="ie-fill" :style="{ width: c.durability + '%' }" :class="{ low: c.durability < 25, mid: c.durability >= 25 && c.durability < 60 }"></div></div>
                                       <span class="ie-val">HP {{ Math.round(c.durability) }}</span>
                                    </div>
                                    <div class="ie-meta">
                                       <span>PWR: +{{ c.effective_cooling_power || c.cooling_power }}</span>
                                       <span>NRG: -{{ c.effective_energy_cost || c.energy_cost }}</span>
                                    </div>
                                 </div>
                              </div>
                           </div>

                           <!-- INSTALLED: Power -->
                           <div class="comp-section-label" v-if="installedPower.length">POWER ({{ installedPower.length }})</div>
                           <div class="socket-slot" v-for="p in installedPower" :key="'pwr-'+p.id">
                              <div class="s-content">
                                 <div class="item-equipped-v2">
                                    <div class="ie-top">
                                       <span class="i-tag amber-bg">POWER</span>
                                       <span class="i-name">{{ p.power_name }}</span>
                                       <button class="i-remove" @click="requestEject('power', p.id, p.power_name)">EJECT</button>
                                    </div>
                                    <div class="ie-stats">
                                       <div class="ie-bar"><div class="ie-fill" :style="{ width: p.durability + '%' }" :class="{ low: p.durability < 25, mid: p.durability >= 25 && p.durability < 60 }"></div></div>
                                       <span class="ie-val">HP {{ Math.round(p.durability) }}</span>
                                    </div>
                                    <div class="ie-meta">
                                       <span>SUPPLY: +{{ p.power_supply }}W</span>
                                    </div>
                                 </div>
                              </div>
                           </div>

                           <!-- INSTALLED: Boosts -->
                           <div class="comp-section-label" v-if="installedBoosts.length">BOOSTS ({{ installedBoosts.length }})</div>
                           <div class="socket-slot" v-for="b in installedBoosts" :key="'boost-'+b.id">
                              <div class="s-content">
                                 <div class="item-equipped-v2">
                                    <div class="ie-top">
                                       <span class="i-tag green-bg">BOOST</span>
                                       <span class="i-name">{{ b.name }}</span>
                                       <button class="i-remove" @click="requestEject('boost', b.id, b.name)">EJECT</button>
                                    </div>
                                    <div class="ie-stats">
                                       <div class="ie-bar"><div class="ie-fill" :style="{ width: (b.remaining_seconds / (b.remaining_seconds + 1)) * 100 + '%' }" :class="{ low: b.remaining_seconds < 300, mid: b.remaining_seconds >= 300 && b.remaining_seconds < 1800 }"></div></div>
                                       <span class="ie-val">{{ formatBoostTime(b.remaining_seconds) }}</span>
                                    </div>
                                    <div class="ie-meta">
                                       <span>{{ b.boost_type.toUpperCase() }}: +{{ b.effect_value }}%</span>
                                       <span v-if="b.stack_count > 1">x{{ b.stack_count }}</span>
                                    </div>
                                 </div>
                              </div>
                           </div>

                           <!-- Empty state -->
                           <div v-if="!installedCooling.length && !installedPower.length && !installedBoosts.length" class="comp-empty">
                              <div class="comp-empty-icon"><Package :size="24" style="opacity: 0.85" /></div>
                              <div class="comp-empty-text">NO_MODULES_INSTALLED</div>
                              <div class="comp-empty-hint">Forge components in THE_FORGE and install them here</div>
                           </div>
                        </div>

                     </div>


                  </div>
                  <div v-else class="panel-loading">SYNCING_RIG_HARDWARE...</div>

                  <!-- CORE CONTROLS -->
                  <div class="panel-controls-v8">
                     <template v-if="selectedRig.is_active">
                       <button class="action-btn-v8 power active" @click="handleToggleRig(selectedRig.id)" v-tooltip="'Terminate current mining cycle.'">
                          HALT_SEQUENCE
                       </button>
                     </template>
                     <template v-else-if="modeSelectionId === selectedRig.id">
                       <div class="mode-selector-v8">
                          <div class="selector-head">HOLD TO ENGAGE PROTOCOL</div>
                          <div class="selector-grid">
                             <button class="mode-opt pool"
                                @mousedown.prevent="onHoldStart('pool')"
                                @mouseup="onHoldEnd()" @mouseleave="onHoldEnd()"
                                @touchstart.prevent="onHoldStart('pool')"
                                @touchend="onHoldEnd()" @touchcancel="onHoldEnd()"
                                v-tooltip="'Hold to assign unit to global network sharing.'">
                                <span class="m-title">POOL_CHANNEL</span>
                                <span class="m-desc">STABLE_REWARDS</span>
                                <div class="hold-bar" v-if="holdingMode === 'pool'">
                                   <div class="hold-fill" :style="{ width: holdProgress + '%' }"></div>
                                </div>
                                <span class="hold-hint" v-else>HOLD</span>
                             </button>
                             <button class="mode-opt solo" :disabled="!soloMiningStore.hasRental"
                                @mousedown.prevent="soloMiningStore.hasRental && onHoldStart('solo')"
                                @mouseup="onHoldEnd()" @mouseleave="onHoldEnd()"
                                @touchstart.prevent="soloMiningStore.hasRental && onHoldStart('solo')"
                                @touchend="onHoldEnd()" @touchcancel="onHoldEnd()"
                                v-tooltip="soloMiningStore.hasRental ? 'Hold to attempt direct block discovery.' : 'No active solo contract found.'">
                                <span class="m-title">SOLO_CHANNEL</span>
                                <span class="m-desc">{{ soloMiningStore.hasRental ? 'HIGH_VALUE_CAPTURE' : 'OFFLINE: REQ_RENTAL' }}</span>
                                <div class="hold-bar" v-if="holdingMode === 'solo'">
                                   <div class="hold-fill" :style="{ width: holdProgress + '%' }"></div>
                                </div>
                                <span class="hold-hint" v-else-if="soloMiningStore.hasRental">HOLD</span>
                             </button>
                          </div>
                          <button class="mode-abort" @click="modeSelectionId = null; onHoldEnd()">CANCEL_COMMAND</button>
                       </div>
                     </template>
                     <template v-else>
                       <button class="action-btn-v8 power" @click="modeSelectionId = selectedRig.id" v-tooltip="'Initialize equipment startup sequence.'">
                          INIT_SEQUENCE
                       </button>
                     </template>
                     <button v-if="!modeSelectionId" class="sub-btn-v8" @click="showRigStats = true" v-tooltip="'Open detailed performance and configuration logs.'">ACCESS_FULL_TELEMETRY</button>
                  </div>
                  
                  <div class="panel-meta">
                     <div class="p-grade-box">
                        <span class="diag-tag">MASTERY_RANK</span>
                        <span class="m-grade-val" :style="{ color: getRigGrade(selectedRig).color }">{{ getRigGrade(selectedRig).label }}</span>
                     </div>
                     <div class="p-stats">
                       <span>NET_DAILY: {{ (getNetProfit(selectedRig) * 24).toFixed(2) }} GC</span>
                       <span>UID: {{ selectedRig.id.substring(0,8) }}</span>
                     </div>
                  </div>
               </div>
               </template>
            </aside>
          </div>
        </div>






        <!-- STAKING VIEW -->
        <div v-else-if="activeTab === 'staking'" class="view-staking">

           <!-- Loading -->
           <div v-if="stakeLoading && !stakeData" class="stake-loading">
              <span>SYNCING_STAKE_DATA...</span>
           </div>

           <!-- Estado A: No active stake — show plans -->
           <template v-else-if="!stakeData">
              <div class="stake-header">
                 <h2>RON_STAKING_PROTOCOL</h2>
                 <p class="stake-subtitle">Lock your RON to earn LANDWORK passively. RON is returned after the staking period + 3 day cooldown.</p>
                 <div class="stake-balance">YOUR_RON: <strong>{{ (authStore.player?.ron_balance ?? 0).toLocaleString() }}</strong></div>
              </div>
              <div class="stake-plans">
                 <div v-for="plan in STAKING_PLANS" :key="plan.id"
                    class="stake-card"
                    :class="{ selected: selectedPlan === plan.id, disabled: (authStore.player?.ron_balance ?? 0) < plan.ron }"
                    @click="(authStore.player?.ron_balance ?? 0) >= plan.ron && (selectedPlan = selectedPlan === plan.id ? null : plan.id)">
                    <div class="sc-icon"><component :is="plan.icon" :size="24" style="opacity: 0.85" /></div>
                    <div class="sc-name" :style="{ color: plan.color }">{{ plan.label }}</div>
                    <div class="sc-ron">{{ plan.ron.toLocaleString() }} RON</div>
                    <div class="sc-divider"></div>
                    <div class="sc-reward">
                       <span class="sc-landwork">{{ plan.landwork.toLocaleString() }}</span>
                       <span class="sc-lw-label">LANDWORK</span>
                    </div>
                    <div class="sc-meta">
                       <span>{{ plan.days }} DAYS</span>
                       <span>~{{ (plan.landwork / (plan.days * 24)).toFixed(1) }}/hr</span>
                    </div>
                    <div class="sc-phases">
                       <span>3d warmup → {{ plan.days }}d earning → 3d cooldown</span>
                    </div>
                 </div>
              </div>
              <div v-if="selectedPlan" class="stake-confirm">
                 <button class="stake-btn" @click="handleCreateStake" :disabled="stakeLoading">
                    STAKE {{ STAKING_PLANS.find(p => p.id === selectedPlan)?.ron }} RON
                 </button>
              </div>
           </template>

           <!-- Estado B: Warmup -->
           <template v-else-if="stakeData.status === 'warmup'">
              <div class="stake-active-panel">
                 <div class="sap-icon"><component :is="STAKING_PLANS.find(p => p.id === stakeData.plan)?.icon" :size="28" style="opacity: 0.85" /></div>
                 <div class="sap-plan" :style="{ color: STAKING_PLANS.find(p => p.id === stakeData.plan)?.color }">
                    {{ stakeData.plan.toUpperCase() }} STAKE
                 </div>
                 <div class="sap-status warmup">WARMUP_PHASE</div>
                 <div class="sap-info">Your RON is being processed. Landwork generation starts soon.</div>
                 <div class="sap-countdown">
                    <span class="sap-cd-label">GENERATION STARTS IN</span>
                    <span class="sap-cd-val">{{ stakeCountdown(stakeData.warmup_ends_at) }}</span>
                 </div>
                 <div class="sap-progress">
                    <div class="sap-bar"><div class="sap-fill warmup" :style="{ width: stakeProgressPct + '%' }"></div></div>
                 </div>
                 <div class="sap-details">
                    <div class="sap-row"><span>RON LOCKED</span><span>{{ Number(stakeData.ron_amount).toLocaleString() }}</span></div>
                    <div class="sap-row"><span>TOTAL REWARD</span><span>{{ stakeData.landwork_total.toLocaleString() }} LW</span></div>
                    <div class="sap-row"><span>EARNING PERIOD</span><span>{{ STAKING_PLANS.find(p => p.id === stakeData.plan)?.days }}d</span></div>
                 </div>
              </div>
           </template>

           <!-- Estado C: Active (generating landwork) -->
           <template v-else-if="stakeData.status === 'active'">
              <div class="stake-active-panel">
                 <div class="sap-icon"><component :is="STAKING_PLANS.find(p => p.id === stakeData.plan)?.icon" :size="28" style="opacity: 0.85" /></div>
                 <div class="sap-plan" :style="{ color: STAKING_PLANS.find(p => p.id === stakeData.plan)?.color }">
                    {{ stakeData.plan.toUpperCase() }} STAKE
                 </div>
                 <div class="sap-status active">GENERATING_LANDWORK</div>
                 <div class="sap-earning">
                    <div class="sap-earned-val">{{ stakePendingLandwork.toLocaleString() }}</div>
                    <div class="sap-earned-label">PENDING LANDWORK</div>
                    <div class="sap-rate">+{{ stakeLandworkPerHour }} LW/hr</div>
                 </div>
                 <button class="stake-claim-btn" @click="handleClaimRewards" :disabled="stakeClaiming || stakePendingLandwork === 0">
                    {{ stakeClaiming ? 'CLAIMING...' : 'CLAIM ' + stakePendingLandwork.toLocaleString() + ' LANDWORK' }}
                 </button>
                 <div class="sap-progress">
                    <div class="sap-bar"><div class="sap-fill active" :style="{ width: stakeProgressPct + '%' }"></div></div>
                 </div>
                 <div class="sap-countdown">
                    <span class="sap-cd-label">ENDS IN</span>
                    <span class="sap-cd-val">{{ stakeCountdown(stakeData.ends_at) }}</span>
                 </div>
                 <div class="sap-details">
                    <div class="sap-row"><span>RON LOCKED</span><span>{{ Number(stakeData.ron_amount).toLocaleString() }}</span></div>
                    <div class="sap-row"><span>CLAIMED</span><span>{{ stakeData.landwork_claimed.toLocaleString() }} / {{ stakeData.landwork_total.toLocaleString() }} LW</span></div>
                    <div class="sap-row"><span>RON RETURN</span><span>3 days after completion</span></div>
                 </div>
              </div>
           </template>

           <!-- Estado D: Cooldown -->
           <template v-else-if="stakeData.status === 'cooldown'">
              <div class="stake-active-panel">
                 <div class="sap-icon"><component :is="STAKING_PLANS.find(p => p.id === stakeData.plan)?.icon" :size="28" style="opacity: 0.85" /></div>
                 <div class="sap-plan" :style="{ color: STAKING_PLANS.find(p => p.id === stakeData.plan)?.color }">
                    {{ stakeData.plan.toUpperCase() }} STAKE
                 </div>
                 <div class="sap-status cooldown">COOLDOWN_PHASE</div>
                 <div class="sap-info">Staking completed. Your RON is being processed for return.</div>
                 <div class="sap-countdown">
                    <span class="sap-cd-label">RON RETURNS IN</span>
                    <span class="sap-cd-val">{{ stakeCountdown(stakeData.cooldown_ends_at) }}</span>
                 </div>
                 <div class="sap-progress">
                    <div class="sap-bar"><div class="sap-fill cooldown" :style="{ width: stakeProgressPct + '%' }"></div></div>
                 </div>
                 <div class="sap-details">
                    <div class="sap-row"><span>RON RETURNING</span><span>{{ Number(stakeData.ron_amount).toLocaleString() }}</span></div>
                    <div class="sap-row"><span>TOTAL EARNED</span><span>{{ stakeData.landwork_claimed.toLocaleString() }} LW</span></div>
                 </div>
              </div>
           </template>

           <!-- Estado E: Returned -->
           <template v-else-if="stakeData.status === 'returned'">
              <div class="stake-active-panel">
                 <div class="sap-icon"><CheckCircle :size="28" style="opacity: 0.85" /></div>
                 <div class="sap-status returned">STAKE_COMPLETED</div>
                 <div class="sap-info">Your RON has been returned to your balance.</div>
                 <div class="sap-details">
                    <div class="sap-row"><span>RON RETURNED</span><span>{{ Number(stakeData.ron_amount).toLocaleString() }}</span></div>
                    <div class="sap-row"><span>TOTAL EARNED</span><span>{{ stakeData.landwork_claimed.toLocaleString() }} LW</span></div>
                 </div>
                 <button class="stake-btn" @click="stakeData = null">START NEW STAKE</button>
              </div>
           </template>

        </div>

        <!-- HISTORY VIEW -->
        <div v-else-if="activeTab === 'history'" class="view-history scroll">
          <div class="history-terminal">
            <div class="history-head">LATEST_NETWORK_CYCLES</div>
            <div class="history-body">
               <div v-for="block in miningStore.recentBlocks.slice(0,25)" :key="block.id" class="history-row">
                  <span class="b-num">#{{ block.block_number || block.height }}</span>
                  <span class="b-res" :class="{ ok: block.player_participation?.participated }">
                    [{{ block.player_participation?.participated ? 'SUCCESS' : 'MISSED' }}]
                  </span>
                  <span class="b-val amber">{{ block.player_participation?.reward ? '+' + block.player_participation.reward.toFixed(4) : '--' }}</span>
               </div>
            </div>
          </div>
        </div>

        </div>
    </div>
  </main>

  <!-- CLAIM CAPTCHA MODAL -->
  <Teleport to="body">
    <div v-if="showClaimModal" class="claim-modal-overlay" @click.self="closeClaimModal">
      <div class="claim-modal">
        <div class="cm-header">
          <Lock :size="16" style="opacity: 0.85" />
          <span>VERIFY_MINER</span>
          <button class="cm-close" @click="closeClaimModal">✕</button>
        </div>
        <div class="cm-body">
          <div class="cm-info">Complete the captcha to claim this block</div>
          <div class="cm-captcha">
            <div ref="inboxCaptchaContainer" class="h-captcha"></div>
          </div>
          <button class="cm-claim-btn"
            @click="handleClaimAfterCaptcha"
            :disabled="!inboxCaptchaVerified || pendingBlocksStore.claiming">
            <span v-if="pendingBlocksStore.claiming">CLAIMING...</span>
            <span v-else-if="!inboxCaptchaVerified">COMPLETE_CAPTCHA_FIRST</span>
            <span v-else><ArrowDownToLine :size="14" style="opacity: 0.85" /> CLAIM_BLOCK</span>
          </button>
        </div>
      </div>
    </div>
  </Teleport>

  <!-- INVENTORY CONFIRM MODAL -->
  <Teleport to="body">
    <div v-if="showInvConfirm" class="claim-modal-overlay" @click.self="cancelInvAction">
      <div class="claim-modal">
        <div class="cm-header">
          <Archive :size="16" style="opacity: 0.85" />
          <span>{{ invConfirmAction?.label }}</span>
          <button class="cm-close" @click="cancelInvAction">✕</button>
        </div>
        <div class="cm-body">
          <div class="cm-info">Are you sure you want to perform this action?</div>
          <div class="inv-confirm-actions">
            <button class="inv-action-btn" @click="cancelInvAction">CANCEL</button>
            <button class="cm-claim-btn" @click="confirmInvAction" :disabled="invActionLoading">
              <span v-if="invActionLoading">PROCESSING...</span>
              <span v-else>CONFIRM</span>
            </button>
          </div>
        </div>
      </div>
    </div>
  </Teleport>

  <!-- RIG SELECT MODAL (for patches) -->
  <Teleport to="body">
    <div v-if="showRigSelectModal" class="claim-modal-overlay" @click.self="showRigSelectModal = false">
      <div class="claim-modal" style="max-height: 70vh;">
        <div class="cm-header">
          <Wrench :size="16" style="opacity: 0.85" />
          <span>SELECT_RIG</span>
          <button class="cm-close" @click="showRigSelectModal = false">✕</button>
        </div>
        <div class="cm-body" style="max-height: 50vh; overflow-y: auto;">
          <div v-for="rig in rigs" :key="rig.id" class="inv-select-row" @click="selectRigForPatch(rig.id)">
            <Pickaxe :size="14" style="opacity: 0.85" />
            <span class="inv-select-name">{{ rig.rig.name }}</span>
            <span class="inv-select-stat" :class="{ low: rig.condition < 30 }">{{ rig.condition }}%</span>
          </div>
          <div v-if="!rigs.length" class="cm-info">No rigs installed</div>
        </div>
      </div>
    </div>
  </Teleport>


  <!-- MENU MODAL -->
  <div v-if="menuModalOpen" class="menu-modal-overlay" @click.self="menuModalOpen = false">
    <div class="menu-modal">
      <div class="mm-header">
        <div class="mm-tabs">
          <button :class="{ active: menuModalTab === 'inventory' }" @click="switchModalTab('inventory')">INVENTORY</button>
          <button :class="{ active: menuModalTab === 'market' }" @click="switchModalTab('market')">MARKET</button>
          <button :class="{ active: menuModalTab === 'exchange' }" @click="switchModalTab('exchange')">EXCHANGE</button>
        </div>
        <button class="mm-close" @click="menuModalOpen = false">X</button>
      </div>
      <div class="mm-body">

        <!-- INVENTORY -->
        <div v-if="menuModalTab === 'inventory'" class="view-inv scroll">
          <div class="inv-bar">
            <span class="inv-title">INVENTORY</span>
            <span class="inv-slots">{{ inventoryStore.slotsUsed }}/{{ inventoryStore.maxSlots }} SLOTS</span>
          </div>

          <div v-if="inventoryLoading" class="inv-loading">LOADING...</div>
          <template v-else>
            <div v-if="inventoryStore.totalItems > 0" class="inv-list">
              <div v-for="item in inventoryStore.rigItems" :key="'r-'+item.rig_id" class="il-row">
                <span class="il-icon"><Settings :size="14" style="opacity: 0.85" /></span>
                <div class="il-info">
                  <span class="il-name">{{ item.name }}</span>
                  <span class="il-stat">{{ item.hashrate }} H/s · {{ item.power_consumption }}W</span>
                </div>
                <span class="it-type">RIG</span>
                <span class="il-qty">x{{ item.quantity }}</span>
              </div>
              <div v-for="item in inventoryStore.coolingItems" :key="'c-'+item.inventory_id" class="il-row">
                <span class="il-icon"><Snowflake :size="14" style="opacity: 0.85" /></span>
                <div class="il-info">
                  <span class="il-name">{{ item.name }}</span>
                  <span class="il-stat">{{ item.cooling_power }} CP · {{ item.energy_cost }} NRG</span>
                </div>
                <span class="it-type cool">COOL</span>
                <span class="il-qty">x{{ item.quantity }}</span>
              </div>
              <div v-for="item in inventoryStore.componentItems" :key="'m-'+item.inventory_id" class="il-row">
                <span class="il-icon"><Wrench :size="14" style="opacity: 0.85" /></span>
                <div class="il-info">
                  <span class="il-name">{{ item.name }}</span>
                  <span class="il-stat">{{ item.cooling_power_min }}-{{ item.cooling_power_max }} CP</span>
                </div>
                <span class="it-type mod">MOD</span>
                <span class="il-qty">x{{ item.quantity }}</span>
              </div>
              <div v-for="item in inventoryStore.cardItems" :key="'d-'+item.id" class="il-row">
                <span class="il-icon"><CreditCard :size="14" style="opacity: 0.85" /></span>
                <div class="il-info">
                  <span class="il-name">{{ item.name }}</span>
                  <span class="il-stat">+{{ item.amount }}</span>
                </div>
                <span class="it-type card">{{ item.card_type.toUpperCase() }}</span>
                <span class="il-qty">x1</span>
              </div>
              <div v-for="item in inventoryStore.boostItems" :key="'b-'+item.id" class="il-row">
                <span class="il-icon"><Rocket :size="14" style="opacity: 0.85" /></span>
                <div class="il-info">
                  <span class="il-name">{{ item.name }}</span>
                  <span class="il-stat">+{{ item.effect_value }}% · {{ item.duration_minutes }}min</span>
                </div>
                <span class="it-type boost">BOOST</span>
                <span class="il-qty">x{{ item.quantity }}</span>
              </div>
              <div v-for="item in inventoryStore.materialItems" :key="'mt-'+item.material_id" class="il-row">
                <span class="il-icon"><component :is="emojiIcon(item.icon)" :size="14" style="opacity: 0.85" /></span>
                <div class="il-info">
                  <span class="il-name">{{ item.name }}</span>
                  <span class="il-stat">{{ item.rarity }}</span>
                </div>
                <span class="it-type mat">MAT</span>
                <span class="il-qty">x{{ item.quantity }}</span>
              </div>
              <div v-for="item in inventoryStore.patchItems" :key="'p-'+item.inventory_id" class="il-row">
                <span class="il-icon"><Sticker :size="14" style="opacity: 0.85" /></span>
                <div class="il-info">
                  <span class="il-name">RIG_PATCH</span>
                  <span class="il-stat">Repair</span>
                </div>
                <span class="it-type">PATCH</span>
                <span class="il-qty">x{{ item.quantity }}</span>
              </div>
              <div v-for="item in inventoryStore.expPackItems" :key="'x-'+item.inventory_id" class="il-row">
                <span class="il-icon"><BookOpen :size="14" style="opacity: 0.85" /></span>
                <div class="il-info">
                  <span class="il-name">{{ item.name }}</span>
                  <span class="il-stat">+{{ item.xp_amount }} XP</span>
                </div>
                <span class="it-type xp">EXP</span>
                <span class="il-qty">x{{ item.quantity }}</span>
              </div>
            </div>

            <div v-else class="inv-empty">
              <span class="ph-icon"><Package :size="24" style="opacity: 0.85" /></span>
              <span class="ph-title">EMPTY</span>
              <span class="ph-sub">Visit MARKET to acquire items</span>
            </div>
          </template>
        </div>

        <!-- MARKET -->
        <div v-else-if="menuModalTab === 'market'" class="view-market scroll">
          <div class="inv-header">
            <span class="inv-title">MARKET_TERMINAL</span>
          </div>

          <!-- Category tabs -->
          <div class="mkt-tabs">
            <button v-for="cat in [
              { key: 'rigs', label: 'RIGS' },
              { key: 'cooling', label: 'COOLING' },
              { key: 'components', label: 'MODS' },
              { key: 'cards', label: 'CARDS' },
              { key: 'boosts', label: 'BOOSTS' },
              { key: 'exp_packs', label: 'EXP' },
              { key: 'crypto', label: 'LANDWORK' }
            ]" :key="cat.key"
              @click="marketCategory = cat.key as any"
              :class="{ active: marketCategory === cat.key }">
              {{ cat.label }}
            </button>
          </div>

          <div v-if="marketLoading" class="inv-loading">LOADING_CATALOG...</div>
          <template v-else>
            <!-- RIGS CATALOG -->
            <div v-if="marketCategory === 'rigs'" class="inv-grid">
              <div v-for="item in marketStore.rigs" :key="item.id" class="inv-card mkt">
                <div class="ic-head">
                  <span class="ic-tag" :class="tierColor(item.tier)">{{ item.tier.toUpperCase() }}</span>
                  <span class="ic-own">OWNED: {{ marketStore.getRigOwned(item.id).total }}</span>
                </div>
                <div class="ic-name">{{ item.name }}</div>
                <div class="ic-desc">{{ item.description }}</div>
                <div class="ic-stats">
                  <span>HASH: {{ item.hashrate }} H/s</span>
                  <span>PWR: {{ item.power_consumption }}W</span>
                  <span>NET: {{ item.internet_consumption }}</span>
                </div>
                <div class="ic-buy">
                  <span class="ic-price"><component :is="currencyIcon(item.currency)" :size="12" style="opacity: 0.85" /> {{ item.base_price.toLocaleString() }}</span>
                  <button class="buy-btn" :disabled="buyingItem" @click="requestBuy('rig', item.id, item.name, item.base_price, item.currency)">BUY</button>
                </div>
              </div>
            </div>

            <!-- COOLING CATALOG -->
            <div v-if="marketCategory === 'cooling'" class="inv-grid">
              <div v-for="item in marketStore.coolingItems" :key="item.id" class="inv-card mkt">
                <div class="ic-head">
                  <span class="ic-tag" :class="tierColor(item.tier)">{{ item.tier.toUpperCase() }}</span>
                  <span class="ic-own">OWNED: {{ marketStore.getCoolingOwned(item.id).total }}</span>
                </div>
                <div class="ic-name">{{ item.name }}</div>
                <div class="ic-desc">{{ item.description }}</div>
                <div class="ic-stats">
                  <span>COOL: {{ item.cooling_power }}</span>
                  <span>NRG: {{ item.energy_cost }}</span>
                </div>
                <div class="ic-buy">
                  <span class="ic-price"><Coins :size="12" style="opacity: 0.85" /> {{ item.base_price.toLocaleString() }}</span>
                  <button class="buy-btn" :disabled="buyingItem" @click="requestBuy('cooling', item.id, item.name, item.base_price, 'gamecoin')">BUY</button>
                </div>
              </div>
            </div>

            <!-- COMPONENTS CATALOG -->
            <div v-if="marketCategory === 'components'" class="inv-grid">
              <div v-for="item in marketStore.coolingComponents" :key="item.id" class="inv-card mkt">
                <div class="ic-head">
                  <span class="ic-tag" :class="tierColor(item.tier)">{{ item.tier.toUpperCase() }}</span>
                  <span class="ic-own">OWNED: {{ marketStore.getComponentOwned(item.id) }}</span>
                </div>
                <div class="ic-name">{{ item.name }}</div>
                <div class="ic-desc">{{ item.description }}</div>
                <div class="ic-stats">
                  <span>COOL: {{ item.cooling_power_min }}-{{ item.cooling_power_max }}</span>
                  <span>NRG: {{ item.energy_cost_min }}-{{ item.energy_cost_max }}</span>
                </div>
                <div class="ic-buy">
                  <span class="ic-price"><Coins :size="12" style="opacity: 0.85" /> {{ item.base_price.toLocaleString() }}</span>
                  <button class="buy-btn" :disabled="buyingItem" @click="requestBuy('component', item.id, item.name, item.base_price, 'gamecoin')">BUY</button>
                </div>
              </div>
            </div>

            <!-- CARDS CATALOG -->
            <div v-if="marketCategory === 'cards'" class="inv-grid">
              <div v-for="item in marketStore.prepaidCards" :key="item.id" class="inv-card mkt">
                <div class="ic-head">
                  <span class="ic-tag cyan">{{ item.card_type.toUpperCase() }}</span>
                  <span class="ic-own">OWNED: {{ marketStore.getCardOwned(item.id) }}</span>
                </div>
                <div class="ic-name">{{ item.name }}</div>
                <div class="ic-desc">{{ item.description }}</div>
                <div class="ic-stats"><span>+{{ item.amount }}</span></div>
                <div class="ic-buy">
                  <span class="ic-price"><component :is="currencyIcon(item.currency)" :size="12" style="opacity: 0.85" /> {{ item.base_price.toLocaleString() }}</span>
                  <button class="buy-btn" :disabled="buyingItem" @click="requestBuy('card', item.id, item.name, item.base_price, item.currency)">BUY</button>
                </div>
              </div>
            </div>

            <!-- BOOSTS CATALOG -->
            <div v-if="marketCategory === 'boosts'" class="inv-grid">
              <div v-for="item in marketStore.boostItems" :key="item.id" class="inv-card mkt">
                <div class="ic-head">
                  <span class="ic-tag amber">{{ item.boost_type.toUpperCase() }}</span>
                  <span class="ic-own">OWNED: {{ marketStore.getBoostOwned(item.id) }}</span>
                </div>
                <div class="ic-name">{{ item.name }}</div>
                <div class="ic-desc">{{ item.description }}</div>
                <div class="ic-stats">
                  <span>+{{ item.effect_value }}%</span>
                  <span>{{ item.duration_minutes }}min</span>
                </div>
                <div class="ic-buy">
                  <span class="ic-price"><component :is="currencyIcon(item.currency)" :size="12" style="opacity: 0.85" /> {{ item.base_price.toLocaleString() }}</span>
                  <button class="buy-btn" :disabled="buyingItem" @click="requestBuy('boost', item.id, item.name, item.base_price, item.currency)">BUY</button>
                </div>
              </div>
            </div>

            <!-- EXP PACKS CATALOG -->
            <div v-if="marketCategory === 'exp_packs'" class="inv-grid">
              <div v-for="item in marketStore.expPacks" :key="item.id" class="inv-card mkt">
                <div class="ic-head">
                  <span class="ic-tag" :class="tierColor(item.tier)">{{ item.tier.toUpperCase() }}</span>
                  <span class="ic-own">OWNED: {{ marketStore.getExpPackOwned(item.id) }}</span>
                </div>
                <div class="ic-name">{{ item.name }}</div>
                <div class="ic-desc">{{ item.description }}</div>
                <div class="ic-stats"><span>+{{ item.xp_amount }} XP</span></div>
                <div class="ic-buy">
                  <span class="ic-price"><Coins :size="12" style="opacity: 0.85" /> {{ item.base_price.toLocaleString() }}</span>
                  <button class="buy-btn" :disabled="buyingItem" @click="requestBuy('exp_pack', item.id, item.name, item.base_price, 'gamecoin')">BUY</button>
                </div>
              </div>
            </div>

            <!-- LANDWORK PACKAGES -->
            <div v-if="marketCategory === 'crypto'" class="inv-grid">
              <div v-for="item in marketStore.cryptoPackages" :key="item.id" class="inv-card mkt" :class="{ featured: item.is_featured }">
                <div class="ic-head">
                  <span class="ic-tag" :class="tierColor(item.tier)">{{ item.tier.toUpperCase() }}</span>
                  <span v-if="item.bonus_percent > 0" class="ic-bonus">+{{ item.bonus_percent }}% BONUS</span>
                </div>
                <div class="ic-name">{{ item.name }}</div>
                <div class="ic-desc">{{ item.description }}</div>
                <div class="ic-stats"><span><Pickaxe :size="12" style="opacity: 0.85" /> {{ item.total_crypto.toLocaleString() }} LW</span></div>
                <div class="ic-buy">
                  <span class="ic-price"><Gem :size="12" style="opacity: 0.85" /> {{ item.ron_price }} RON</span>
                  <button class="buy-btn" :disabled="buyingItem" @click="requestBuy('crypto', item.id, item.name, item.ron_price, 'ron')">BUY</button>
                </div>
              </div>
            </div>
          </template>
        </div>

        <!-- EXCHANGE -->
        <div v-else-if="menuModalTab === 'exchange'" class="view-exchange scroll">
          <div class="inv-header">
            <span class="inv-title">EXCHANGE_PROTOCOL</span>
          </div>

          <div class="exch-balances">
            <div class="exch-bal">
              <span class="exch-label">LANDWORK</span>
              <span class="exch-val"><Pickaxe :size="12" style="opacity: 0.85" /> {{ (authStore.player?.crypto_balance ?? 0).toLocaleString() }}</span>
            </div>
            <div class="exch-bal">
              <span class="exch-label">COINS</span>
              <span class="exch-val amber"><Coins :size="12" style="opacity: 0.85" /> {{ Math.floor(authStore.player?.gamecoin_balance ?? 0).toLocaleString() }}</span>
            </div>
            <div class="exch-bal">
              <span class="exch-label">RON</span>
              <span class="exch-val cyan"><Gem :size="12" style="opacity: 0.85" /> {{ (authStore.player?.ron_balance ?? 0).toLocaleString() }}</span>
            </div>
          </div>

          <div v-if="exchangeRates" class="exch-rates">
            <div class="exch-rate-title">CURRENT_RATES</div>
            <div class="exch-rate-row" v-if="exchangeRates.crypto_to_gamecoin">
              <span>1 LW</span>
              <span class="exch-arrow">=</span>
              <span class="amber">{{ exchangeRates.crypto_to_gamecoin }} GC</span>
            </div>
            <div class="exch-rate-row" v-if="exchangeRates.crypto_to_ron">
              <span>1 LW</span>
              <span class="exch-arrow">=</span>
              <span class="cyan">{{ exchangeRates.crypto_to_ron }} RON</span>
            </div>
          </div>

          <div class="exch-form">
            <div class="exch-form-title">CONVERT_LANDWORK</div>
            <div class="exch-input-row">
              <label class="exch-input-label">AMOUNT:</label>
              <input type="number" v-model.number="exchangeAmount" min="0" :max="authStore.player?.crypto_balance ?? 0" class="exch-input" placeholder="0" />
            </div>
            <div class="exch-target-row">
              <label class="exch-input-label">TARGET:</label>
              <div class="exch-target-btns">
                <button @click="exchangeTarget = 'gamecoin'" :class="{ active: exchangeTarget === 'gamecoin' }"><Coins :size="12" style="opacity: 0.85" /> GAMECOIN</button>
                <button @click="exchangeTarget = 'ron'" :class="{ active: exchangeTarget === 'ron' }"><Gem :size="12" style="opacity: 0.85" /> RON</button>
              </div>
            </div>
            <button class="exch-submit" :disabled="exchanging || exchangeAmount <= 0" @click="handleExchange">
              {{ exchanging ? 'PROCESSING...' : 'EXECUTE_EXCHANGE' }}
            </button>
          </div>
        </div>

      </div><!-- mm-body -->
    </div><!-- menu-modal -->
  </div><!-- menu-modal-overlay -->

  <!-- BUY CONFIRM MODAL -->
  <div v-if="buyConfirm.show" class="buy-confirm-overlay" @click.self="buyConfirm.show = false">
    <div class="buy-confirm-dialog">
      <div class="bcd-header">{{ buyConfirm.result === 'pending' ? 'CONFIRM_PURCHASE' : 'TRANSACTION_RESULT' }}</div>
      <div class="bcd-body">
        <div class="bcd-item">{{ buyConfirm.name }}</div>
        <div class="bcd-price"><component :is="currencyIcon(buyConfirm.currency)" :size="14" style="opacity: 0.85" /> {{ buyConfirm.price.toLocaleString() }} {{ buyConfirm.currency.toUpperCase() }}</div>
        <div v-if="buyConfirm.result === 'success'" class="bcd-msg success">{{ buyConfirm.message }}</div>
        <div v-if="buyConfirm.result === 'error'" class="bcd-msg error">{{ buyConfirm.message }}</div>
      </div>
      <div class="bcd-footer">
        <template v-if="buyConfirm.result === 'pending'">
          <button class="bcd-btn cancel" @click="buyConfirm.show = false">CANCEL</button>
          <button class="bcd-btn confirm" :disabled="buyingItem" @click="confirmBuy">{{ buyingItem ? 'PROCESSING...' : 'CONFIRM' }}</button>
        </template>
        <button v-else class="bcd-btn confirm" @click="buyConfirm.show = false">CLOSE</button>
      </div>
    </div>
  </div>

    <RigStatsModal
      :show="showRigStats"
      :rig="selectedRig"
      @close="showRigStats = false" />

    <StoryModal
      :show="showStory"
      :chapter="storyChapter"
      @close="closeStory" />

    <!-- SLOT EXPANSION CONFIRM MODAL -->
    <div v-if="showSlotConfirm" class="confirm-modal-overlay">
       <div class="confirm-dialog">
          <div class="diag-header">
             <span class="diag-tag">SECURITY_OVERRIDE</span>
             <h3>CONFIRM_EXPANSION_AUTHORIZATION</h3>
          </div>
          
          <div class="diag-body">
             <p>You are about to initialize an operational node expansion. This action will deduct the required resources from your balance.</p>
             
             <div class="expansion-details" v-if="miningStore.slotInfo?.next_upgrade">
                <div class="det-row">
                   <span class="l">UPGRADE_TARGET:</span>
                   <span class="v">NODE_0{{ miningStore.slotInfo.next_upgrade.slot_number }}</span>
                </div>
                <div class="det-row">
                   <span class="l">REQUIRED_CREDITS:</span>
                   <span class="v amber monospace">{{ miningStore.slotInfo.next_upgrade.price }} {{ miningStore.slotInfo.next_upgrade.currency.toUpperCase() }}</span>
                </div>
             </div>


             <div class="diag-warning">
                <span>[!] ACTION_IS_IRREVERSIBLE</span>
             </div>
          </div>

          <div class="diag-footer">
             <button class="d-btn cancel" @click="showSlotConfirm = false">ABORT_COMMAND</button>
             <button class="d-btn confirm hold-btn"
                @mousedown="startSlotHold"
                @mouseup="cancelSlotHold" @mouseleave="cancelSlotHold"
                @touchstart.prevent="startSlotHold"
                @touchend="cancelSlotHold" @touchcancel="cancelSlotHold">
                <div class="hold-fill" :style="{ width: slotHoldPct + '%' }"></div>
                <span class="hold-label">HOLD · AUTHORIZE</span>
             </button>
          </div>
       </div>
    </div>

    <!-- EJECT CONFIRM MODAL -->
    <div v-if="showEjectConfirm && ejectTarget" class="confirm-modal-overlay">
       <div class="confirm-dialog">
          <div class="diag-header">
             <span class="diag-tag">SECURITY_OVERRIDE</span>
             <h3>CONFIRM_EJECT</h3>
          </div>
          <div class="diag-body">
             <p>Ejecting <strong>{{ ejectTarget.name }}</strong> will destroy this component. This action cannot be undone.</p>
             <div class="diag-warning">
                <span>[!] COMPONENT_WILL_BE_DESTROYED</span>
             </div>
          </div>
          <div class="diag-footer">
             <button class="d-btn cancel" @click="showEjectConfirm = false; ejectTarget = null">ABORT</button>
             <button class="d-btn confirm" @click="confirmEject">CONFIRM_EJECT</button>
          </div>
       </div>
    </div>

  </div>
</template>

<style scoped>
@import url('https://fonts.googleapis.com/css2?family=Nunito:wght@400;600;700;800;900&family=Roboto:wght@400;500;700;900&display=swap');

.deck-terminal-v8 {
  position: fixed; inset: 0;
  background: #1a1528;
  background-image:
    radial-gradient(circle, #2d2545 1.5px, transparent 1.5px);
  background-size: 20px 20px;

  color: #f0e4ff;
  font-family: 'Nunito', 'Trebuchet MS', 'Segoe UI', sans-serif;
  display: flex; flex-direction: column;
  z-index: 50; overflow-y: auto; overflow-x: hidden;
}
.deck-terminal-v8::-webkit-scrollbar { width: 8px; }
.deck-terminal-v8::-webkit-scrollbar-track { background: #2d2545; }
.deck-terminal-v8::-webkit-scrollbar-thumb { background: #c4a0e8; border: 1px solid #9a70c0; border-radius: 4px; }

.scroll-v {
  overflow-y: auto;
}
.scroll-v::-webkit-scrollbar { width: 8px; }
.scroll-v::-webkit-scrollbar-track { background: #2d2545; }
.scroll-v::-webkit-scrollbar-thumb { background: #c4a0e8; border: 1px solid #9a70c0; }

.scroll {
  overflow-y: auto;
}
.scroll::-webkit-scrollbar { width: 8px; }
.scroll::-webkit-scrollbar-track { background: #2d2545; }
.scroll::-webkit-scrollbar-thumb { background: #c4a0e8; border: 1px solid #9a70c0; }



.monospace { font-family: 'Roboto', 'Nunito', sans-serif; font-weight: 700; }
.amber { color: #d4a017; text-shadow: none; }
.cyan { color: #b8a0d0; text-shadow: none; }
.white { color: #f0e4ff; }

.terminal-overlay {
  position: absolute; inset: 0;
  background: none;
  pointer-events: none; z-index: 100; opacity: 0;
}

.v8-container {
  max-width: 1280px;
  margin: 0 auto;
  width: 100%;
}


/* Header - removed, balances moved to fleet command */
.terminal-header { display: none; }

.h-inner { 
  display: flex; align-items: center; justify-content: space-between;
  height: 100%; padding: 0 1.5rem;
}

.h-main { flex: 1; display: flex; align-items: center; }
.h-brand { white-space: nowrap; margin-right: 2rem; display: flex; align-items: center; gap: 10px; }
.theme-toggle { background: #ffe566; border: 2px outset #d4c040; color: #1a1528; font-size: 0.5rem; font-weight: 800; padding: 3px 8px; cursor: pointer; font-family: inherit; letter-spacing: 1px; transition: 0.2s; border-radius: 6px; }
.theme-toggle:hover { background: #fff080; border-style: inset; color: #1a1528; }

/* Menu dropdown */
.h-menu { position: relative; margin-left: 1rem; }
.menu-toggle { background: #ffe566; border: 2px outset #d4c040; color: #1a1528; font-size: 0.6rem; font-weight: 800; padding: 4px 10px; cursor: pointer; font-family: inherit; letter-spacing: 1px; transition: 0.2s; border-radius: 6px; }
.menu-toggle:hover { background: #fff080; border-style: inset; color: #1a1528; }
.menu-dropdown { position: absolute; top: calc(100% + 6px); right: 0; background: #1f1833; border: 2px solid #5c4578; z-index: 999; min-width: 160px; box-shadow: 3px 3px 0 rgba(74,54,96,0.3); border-radius: 10px; overflow: hidden; }
.menu-dropdown button { display: block; width: 100%; background: transparent; border: none; border-bottom: 1px solid #3a2d50; color: #f0e4ff; font-size: 0.7rem; font-weight: 800; font-family: inherit; letter-spacing: 1px; padding: 10px 14px; cursor: pointer; text-align: left; transition: 0.2s; }
.menu-dropdown button:last-child { border-bottom: none; }
.menu-dropdown button:hover { background: #ffe566; color: #1a1528; }

/* Placeholder views */
/* Placeholder */
.ph-icon { font-size: 2.5rem; }
.ph-title { font-size: 1rem; font-weight: 800; letter-spacing: 2px; color: #71717a; }
.ph-sub { font-size: 0.65rem; font-weight: 800; letter-spacing: 1px; color: #52525b; }

/* Inventory / Market / Exchange shared */
.view-inv, .view-market, .view-exchange { padding: 1rem; overflow-y: auto; }
.inv-bar { display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.8rem; padding-bottom: 0.5rem; border-bottom: 2px solid #4a3660; }
.inv-title { font-size: 0.7rem; font-weight: 900; letter-spacing: 2px; color: #b8a0d0; }
.inv-slots { font-size: 0.6rem; font-weight: 800; color: #d4a017; letter-spacing: 1px; background: rgba(255,229,102,0.3); padding: 2px 8px; border: 1px solid #ffe566; }
.inv-loading { text-align: center; color: #b8a0d0; font-size: 0.7rem; font-weight: 800; letter-spacing: 1px; padding: 3rem 0; }
.inv-empty { display: flex; flex-direction: column; align-items: center; gap: 0.5rem; opacity: 0.5; padding: 3rem 0; }

/* Inventory flex list */
.inv-list { display: flex; flex-direction: column; gap: 2px; }
.il-row { display: flex; align-items: center; gap: 10px; padding: 8px 10px; border-bottom: 1px solid #3a2d50; transition: background 0.15s; }
.il-row:hover { background: rgba(196,160,232,0.1); }
.il-icon { font-size: 1rem; width: 28px; text-align: center; flex-shrink: 0; }
.il-info { display: flex; flex-direction: column; gap: 2px; flex: 1; min-width: 0; }
.il-name { font-size: 0.65rem; font-weight: 800; color: #f0e4ff; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.il-stat { font-size: 0.55rem; font-weight: 700; color: #b8a0d0; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.it-type { font-size: 0.45rem; font-weight: 900; letter-spacing: 1px; padding: 2px 6px; color: #fff; background: #c4a0e8; display: inline-block; flex-shrink: 0; border-radius: 2px; }
.it-type.cool { color: #fff; background: #ffe566; color: #1a1528; }
.it-type.mod { color: #fff; background: #c4a0e8; }
.it-type.card { color: #1a1528; background: #ffe566; }
.it-type.boost { color: #fff; background: #a8d8b0; color: #3a6a50; }
.it-type.mat { color: #fff; background: #ff9ec6; }
.it-type.xp { color: #fff; background: #c4a0e8; }
.il-qty { font-size: 0.7rem; font-weight: 900; color: #d4a017; flex-shrink: 0; min-width: 30px; text-align: right; }

/* Inventory sections */
.inv-section { margin-bottom: 1.5rem; }
.inv-section-label { font-size: 0.6rem; font-weight: 900; color: #b8a0d0; letter-spacing: 2px; margin-bottom: 0.6rem; border-left: 3px solid #ffe566; padding-left: 8px; }

/* Item grid */
.inv-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 0.8rem; }

/* Item card */
.inv-card { background: #1f1833; border: 2px solid #4a3660; box-shadow: 2px 2px 0 rgba(74,54,96,0.3); border-radius: 14px; }
.inv-card.mkt { border-color: #4a3660; padding: 0.8rem; display: flex; flex-direction: column; gap: 0.3rem; border-radius: 10px; }
.inv-card.featured { border-color: #ffe566; background: rgba(255,229,102,0.08); }
.ic-head { display: flex; justify-content: space-between; align-items: center; }
.ic-tag { font-size: 0.6rem; font-weight: 900; letter-spacing: 1px; padding: 3px 8px; background: #2d2545; color: #b8a0d0; border-radius: 6px; }
.ic-tag.amber { color: #1a1528; background: #ffe566; }
.ic-tag.cyan { color: #fff; background: #c4a0e8; }
.ic-tag.white { color: #b8a0d0; }
.ic-own { font-size: 0.6rem; font-weight: 800; color: #b8a0d0; letter-spacing: 1px; }
.ic-bonus { font-size: 0.5rem; font-weight: 900; color: #d4a017; letter-spacing: 1px; }
.ic-name { font-size: 0.85rem; font-weight: 900; color: #f0e4ff; letter-spacing: 0.5px; }
.ic-desc { font-size: 0.7rem; color: #b8a0d0; line-height: 1.3; }
.ic-stats { display: flex; gap: 0.8rem; font-size: 0.7rem; font-weight: 800; color: #b8a0d0; letter-spacing: 0.5px; }
.ic-qty { font-size: 0.6rem; font-weight: 900; color: #d4a017; text-align: right; }
.ic-buy { display: flex; justify-content: space-between; align-items: center; margin-top: auto; padding-top: 0.4rem; border-top: 1px solid #3a2d50; }
.ic-price { font-size: 0.75rem; font-weight: 900; color: #f0e4ff; }
.buy-btn { background: #ffe566; border: 2px outset #d4a017; color: #1a1528; font-size: 0.7rem; font-weight: 900; padding: 5px 14px; cursor: pointer; font-family: inherit; letter-spacing: 1px; transition: 0.2s; border-radius: 6px; }
.buy-btn:hover { background: #ffd700; border-style: inset; }
.buy-btn:disabled { opacity: 0.3; cursor: not-allowed; }

/* Market tabs */
.mkt-tabs { display: flex; gap: 0.5rem; margin-bottom: 1.2rem; flex-wrap: wrap; }
.mkt-tabs button { background: #1f1833; border: 2px outset #4a3660; color: #b8a0d0; font-size: 0.6rem; font-weight: 800; padding: 4px 10px; cursor: pointer; font-family: inherit; letter-spacing: 1px; transition: 0.2s; border-radius: 6px; }
.mkt-tabs button.active { background: #c4a0e8; color: #fff; border-style: inset; }
.mkt-tabs button:hover:not(.active) { background: #ffe566; color: #1a1528; }

/* Exchange */
.exch-balances { display: flex; gap: 2rem; margin-bottom: 1.5rem; padding: 1rem; background: #231d35; border: 2px solid #4a3660; border-radius: 10px; }
.exch-bal { display: flex; flex-direction: column; gap: 0.2rem; }
.exch-label { font-size: 0.65rem; font-weight: 900; color: #b8a0d0; letter-spacing: 1px; }
.exch-val { font-size: 1rem; font-weight: 700; color: #f0e4ff; font-family: 'Roboto', 'Nunito', sans-serif; }
.exch-val.amber { color: #d4a017; }
.exch-val.cyan { color: #b8a0d0; }
.exch-rates { margin-bottom: 1.5rem; padding: 1rem; background: #231d35; border: 2px solid #4a3660; border-radius: 10px; }
.exch-rate-title { font-size: 0.7rem; font-weight: 900; color: #b8a0d0; letter-spacing: 2px; margin-bottom: 0.6rem; }
.exch-rate-row { display: flex; gap: 0.8rem; align-items: center; font-size: 0.85rem; font-weight: 800; color: #f0e4ff; padding: 0.3rem 0; }
.exch-arrow { color: #b8a0d0; }
.exch-form { padding: 1rem; background: #231d35; border: 2px solid #4a3660; border-radius: 10px; }
.exch-form-title { font-size: 0.7rem; font-weight: 900; color: #b8a0d0; letter-spacing: 2px; margin-bottom: 1rem; }
.exch-input-row, .exch-target-row { display: flex; align-items: center; gap: 1rem; margin-bottom: 1rem; }
.exch-input-label { font-size: 0.7rem; font-weight: 900; color: #b8a0d0; letter-spacing: 1px; min-width: 70px; }
.exch-input { background: #1f1833; border: 2px inset #4a3660; color: #f0e4ff; font-size: 0.85rem; font-weight: 800; font-family: monospace; padding: 6px 10px; width: 150px; border-radius: 6px; }
.exch-input:focus { border-color: #ffe566; outline: none; }
.exch-target-btns { display: flex; gap: 0.5rem; }
.exch-target-btns button { background: #1f1833; border: 2px outset #4a3660; color: #b8a0d0; font-size: 0.7rem; font-weight: 800; padding: 6px 14px; cursor: pointer; font-family: inherit; letter-spacing: 1px; transition: 0.2s; border-radius: 6px; }
.exch-target-btns button.active { background: #c4a0e8; color: #fff; border-style: inset; }
.exch-submit { background: #ffe566; border: 2px outset #d4a017; color: #1a1528; font-size: 0.7rem; font-weight: 900; padding: 8px 20px; cursor: pointer; font-family: inherit; letter-spacing: 1px; transition: 0.2s; width: 100%; margin-top: 0.5rem; border-radius: 8px; }
.exch-submit:hover:not(:disabled) { background: #ffd700; border-style: inset; }
.exch-quick-row { display: flex; align-items: center; gap: 1rem; margin-bottom: 0.8rem; }
.exch-quick-btns { display: flex; gap: 0.4rem; flex-wrap: wrap; }
.exch-quick-btns button { background: #1f1833; border: 2px solid #3a2d50; color: #b8a0d0; font-size: 0.65rem; font-weight: 800; padding: 4px 10px; cursor: pointer; font-family: inherit; letter-spacing: 0.5px; transition: 0.2s; border-radius: 6px; }
.exch-quick-btns button:hover { background: #ffe97a; color: #1a1528; border-color: #d4a017; }
.exch-min-note { font-size: 0.8rem; font-weight: 800; color: #d4a017; letter-spacing: 1px; padding: 4px 0; }
.exch-submit:disabled { opacity: 0.3; cursor: not-allowed; }

/* Menu Modal */
.menu-modal-overlay { position: fixed; inset: 0; background: rgba(0,0,0,0.4); z-index: 1000; display: flex; justify-content: center; align-items: center; }
.menu-modal { background: #1f1833; border: 2px solid #5c4578; width: 700px; height: 500px; display: flex; flex-direction: column; box-shadow: 4px 4px 0 rgba(74,54,96,0.3); border-radius: 14px; overflow: hidden; }
.mm-header { display: flex; justify-content: space-between; align-items: center; padding: 0.8rem 1rem; border-bottom: 2px solid #4a3660; background: linear-gradient(180deg, #c9a0e8, #b088d0); }
.mm-tabs { display: flex; gap: 0.5rem; }
.mm-tabs button { background: #1f1833; border: 2px outset #4a3660; color: #b8a0d0; font-size: 0.65rem; font-weight: 900; padding: 5px 14px; cursor: pointer; font-family: inherit; letter-spacing: 1px; transition: 0.2s; border-radius: 6px; }
.mm-tabs button.active { background: #ffe566; color: #1a1528; border-style: inset; }
.mm-tabs button:hover:not(.active) { background: #2d2545; }
.mm-close { background: #ff6b6b; border: 2px outset #cc4444; color: #fff; font-size: 0.7rem; font-weight: 900; padding: 4px 10px; cursor: pointer; font-family: inherit; transition: 0.2s; border-radius: 6px; }
.mm-close:hover { background: #cc4444; border-style: inset; }
.mm-body { flex: 1; overflow-y: auto; }

/* Buy Confirm Modal */
.buy-confirm-overlay { position: fixed; inset: 0; background: rgba(0,0,0,0.4); z-index: 1100; display: flex; justify-content: center; align-items: center; }
.buy-confirm-dialog { background: #1f1833; border: 2px solid #5c4578; padding: 1.5rem; min-width: 300px; max-width: 400px; box-shadow: 4px 4px 0 rgba(74,54,96,0.3); border-radius: 14px; }
.bcd-header { font-size: 0.65rem; font-weight: 900; color: #b8a0d0; letter-spacing: 2px; margin-bottom: 1rem; }
.bcd-body { margin-bottom: 1.2rem; }
.bcd-item { font-size: 0.9rem; font-weight: 900; color: #f0e4ff; margin-bottom: 0.4rem; }
.bcd-price { font-size: 1rem; font-weight: 700; color: #d4a017; font-family: 'Roboto', 'Nunito', sans-serif; }
.bcd-footer { display: flex; gap: 0.6rem; }
.bcd-btn { flex: 1; padding: 8px; font-size: 0.65rem; font-weight: 900; font-family: inherit; letter-spacing: 1px; cursor: pointer; border: 2px outset #4a3660; background: #1f1833; transition: 0.2s; border-radius: 8px; }
.bcd-btn.cancel { color: #b8a0d0; }
.bcd-btn.cancel:hover { background: #2d2545; border-style: inset; }
.bcd-btn.confirm { color: #1a1528; background: #ffe566; border-color: #d4a017; }
.bcd-btn.confirm:hover { background: #ffd700; border-style: inset; }
.bcd-btn:disabled { opacity: 0.3; cursor: not-allowed; }
.bcd-msg { font-size: 0.7rem; font-weight: 900; letter-spacing: 1px; margin-top: 0.8rem; padding: 0.5rem; }
.bcd-msg.success { color: #4a8a6a; border: 2px solid #a8d8b0; background: #f0fff0; }
.bcd-msg.error { color: #cc4444; border: 2px solid #ff6b6b; background: rgba(232,124,138,0.08); }

.h-metrics {
  flex: 1; 
  display: flex; 
  justify-content: center; 
  gap: 3rem;
}

.h-ver { font-size: 0.6rem; color: #3a2d50; margin-left: 0.5rem; }

.m-box { display: flex; flex-direction: column; }
.l { font-size: 0.55rem; font-weight: 800; color: #5c4578; letter-spacing: 1px; }
.v { font-size: 1.1rem; font-weight: 800; color: #fff; }

.h-online { display: flex; align-items: center; gap: 6px; padding-left: 1.5rem; border-left: 1px solid rgba(255,255,255,0.3); }
.online-dot { width: 8px; height: 8px; border-radius: 50%; background: #a8d8b0; box-shadow: none; border: 1px solid #6a9a80; animation: dot-glow 2s infinite alternate; }
.online-count { font-size: 0.9rem; font-weight: 700; color: #fff; font-family: 'Roboto', 'Nunito', sans-serif; }
.online-label { font-size: 0.5rem; font-weight: 800; color: #3a2d50; letter-spacing: 1px; }

.h-resources {
  display: flex; gap: 1.5rem;
  background: rgba(255,255,255,0.2);
  height: 100%;
  padding: 0 1.5rem;
  align-items: center;
  border-left: 2px solid rgba(255,255,255,0.3);
  box-shadow: none;
}
.h-balance { display: flex; align-items: center; gap: 8px; padding: 0 0.8rem; border-right: 1px solid rgba(255,255,255,0.2); }
.h-balance:last-child { border-right: none; }
.hb-icon { font-size: 1.3rem; }
.hb-val { font-size: 1.15rem; font-weight: 700; color: #fff; font-family: 'Roboto', 'Nunito', sans-serif; letter-spacing: 1px; }
.hb-val.lw { color: #ffe566; }
.hb-val.ron { color: #ffe566; }

.res-block { display: flex; flex-direction: column; width: 140px; }
.res-meta { display: flex; justify-content: space-between; align-items: flex-end; font-size: 0.7rem; font-weight: 800; color: #71717a; margin-bottom: 6px; }
.res-meta span { color: #a1a1aa; font-size: 0.6rem; }
.res-meta strong { font-size: 1rem; letter-spacing: 1px; }

.dot { display: inline-block; width: 8px; height: 8px; border-radius: 50%; margin-right: 8px; vertical-align: middle; border: 1px solid rgba(0,0,0,0.2); }
.dot.amber { background: #ffe566; box-shadow: none; animation: dot-glow 2s infinite alternate; }
.dot.cyan { background: #c4a0e8; box-shadow: none; animation: dot-glow 2s infinite alternate-reverse; }
.dot.violet { background: #ff9ec6; box-shadow: none; animation: dot-glow 2s infinite alternate; }

@keyframes dot-glow {
  from { opacity: 0.4; }
  to { opacity: 1; }
}

@keyframes nebula-drift {
  0% { transform: translateX(0) translateY(0); }
  100% { transform: translateX(30px) translateY(-15px); }
}

@keyframes station-pulse {
  0%, 100% { border-bottom-color: rgba(245,158,11,0.1); box-shadow: 0 2px 15px rgba(0,100,255,0.05); }
  50% { border-bottom-color: rgba(245,158,11,0.25); box-shadow: 0 2px 25px rgba(0,100,255,0.15); }
}

.res-meta strong.amber { color: #f59e0b; text-shadow: 0 0 15px rgba(245, 158, 11, 0.5); }
.res-meta strong.cyan { color: #f59e0b; text-shadow: 0 0 15px rgba(245, 158, 11, 0.5); }
.res-meta strong.violet { color: #a855f7; text-shadow: 0 0 15px rgba(168, 85, 247, 0.5); }

.res-bar {
  height: 10px; background: #2d2545; position: relative;
  border: 2px inset #4a3660;
  border-radius: 5px;
  overflow: hidden;
}
.res-bar .fill {
  height: 100%; transition: 0.8s cubic-bezier(0.19, 1, 0.22, 1);
  position: relative;
}

.fill.amber {
  background: linear-gradient(90deg, #ffd700, #ffe566);
  box-shadow: none;
}
.fill.cyan {
  background: linear-gradient(90deg, #b088d0, #c4a0e8);
  box-shadow: none;
}
.fill.violet {
  background: linear-gradient(90deg, #c4a0e8, #d8b8f0);
  box-shadow: none;
}



/* Body */
.terminal-body { flex: 1; display: flex; flex-direction: column; }
.body-inner { flex: 1; display: flex; flex-direction: column; padding: 1.5rem; }


.terminal-nav { display: flex; gap: 0.5rem; margin-bottom: 2rem; justify-content: flex-start; align-items: center; }
.nav-brand {
  font-size: 1.3rem; font-weight: 900; color: #f0e4ff; letter-spacing: 3px;
  font-family: 'Nunito', sans-serif; margin-right: 1rem;
}

.terminal-nav button {
  background: #1f1833; border: 2px outset #4a3660; color: #b8a0d0; font-weight: 800; font-size: 0.9rem; cursor: pointer; transition: 0.2s; font-family: inherit; padding: 6px 16px; border-radius: 8px;
}
.terminal-nav button.active { background: #c4a0e8; color: #fff; border-style: inset; }
.terminal-nav button:hover:not(.active) { background: #ffe566; color: #1a1528; }
.nav-missions-btn {
  position: relative;
  background: #1f1833; border: 2px outset #7cc490; color: #3a7a4a; font-weight: 800; font-size: 0.9rem;
  cursor: pointer; transition: 0.2s; font-family: inherit; padding: 6px 16px; border-radius: 8px;
}
.nav-missions-btn:hover { background: #e8f8ec; }
.nav-missions-badge {
  position: absolute; top: -6px; right: -6px;
  min-width: 18px; height: 18px; padding: 0 4px;
  display: flex; align-items: center; justify-content: center;
  background: #7cc490; color: #fff; font-size: 0.6rem; font-weight: 900;
  border-radius: 9px; border: 2px solid #fff;
}

.terminal-viewport { flex: 1; display: flex; flex-direction: column; }

/* Fleet Layout */
.view-fleet { display: flex; flex-direction: column; }
.fleet-layout { display: grid; grid-template-columns: 1fr 380px; gap: 1.5rem; }

.grid-section { display: flex; flex-direction: column; gap: 1.5rem; }
.block-radar { background: #1f1833; border: 2px solid #5c4578; padding: 1rem; box-shadow: 3px 3px 0 rgba(74,54,96,0.3); border-radius: 12px; }

.radar-label { font-size: 0.65rem; font-weight: 800; color: #f0e4ff; margin-bottom: 8px; }
.radar-line { height: 2px; background: #2d2545; }
.radar-line .fill { background: #ffe566; }

/* Tactical Dual Monitor */
.tactical-monitor-v8 { display: grid; grid-template-columns: 1fr 1fr; gap: 1rem; }
.monitor-card { background: #1f1833; border: 2px solid #5c4578; padding: 0; display: flex; flex-direction: column; gap: 0; box-shadow: 3px 3px 0 rgba(74,54,96,0.3); overflow: hidden; border-radius: 12px; }
.monitor-card::before { content: ''; display: block; height: 24px; background: linear-gradient(180deg, #c9a0e8, #b088d0); border-bottom: 2px solid #5c4578; position: relative; }
.monitor-card::before { background: linear-gradient(180deg, #c9a0e8, #b088d0); background-image: radial-gradient(circle at 12px 12px, #ff6b6b 4px, transparent 4px), radial-gradient(circle at 26px 12px, #ffe566 4px, transparent 4px), radial-gradient(circle at 40px 12px, #a8d8b0 4px, transparent 4px); border-radius: 10px 10px 0 0; }
.monitor-card .m-body { padding: 1rem; }

.m-head { display: flex; justify-content: space-between; align-items: center; padding: 0 1rem; padding-top: 0.5rem; }
.m-tag { font-size: 0.65rem; font-weight: 800; padding: 3px 8px; color: #fff; }
.m-status { font-size: 0.6rem; font-weight: 800; color: #5c4578; }
.m-status:not(.inactive) { color: #f0e4ff; }

.m-stat { display: flex; justify-content: space-between; align-items: flex-end; }
.m-stat .l { font-size: 0.7rem; color: #b8a0d0; }
.m-stat .v { font-size: 1.1rem; font-weight: 800; }

.m-radar { height: 8px; background: #2d2545; position: relative; overflow: hidden; border-radius: 0; border: 1px inset #4a3660; }
.m-radar .fill { height: 100%; transition: width 0.3s; position: relative; z-index: 2; border-radius: 0; }

.wave-vignette {
  position: absolute; inset: 0; z-index: 1;
  background-image: none;
  animation: none;
}
.wave-vignette.cyan { background-image: none; }
.wave-vignette.amber { background-image: none; }

@keyframes wave-move { from { background-position: 0 0; } to { background-position: 100px 0; } }


.m-footer { font-size: 0.65rem; font-weight: 800; color: #b8a0d0; letter-spacing: 1px; display: flex; justify-content: space-between; align-items: center; margin-top: 0.6rem; padding: 0 1rem 0.5rem; }
.m-timer { font-family: inherit; color: #f0e4ff; }
.m-timer.amber { color: #d4a017; }


.monitor-empty { flex: 1; display: flex; flex-direction: column; align-items: center; justify-content: center; opacity: 0.5; cursor: pointer; padding: 1rem; }
.monitor-empty:hover { opacity: 0.8; }
.monitor-empty span { font-size: 0.8rem; font-weight: 800; color: #f0e4ff; }
.monitor-empty small { font-size: 0.6rem; color: #b8a0d0; }

.cyan-bg { background: #c4a0e8; }
.amber-bg { background: #ffe566; color: #1a1528; }

.rig-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(210px, 1fr));
  gap: 1.2rem;
  justify-content: center;
}


.rig-tile {
  background: #1f1833;
  border: 2.5px solid #4a3660; padding: 0.9rem 1rem 1rem; cursor: pointer; position: relative; transition: all 0.25s ease;
  overflow: hidden; padding-top: 2rem; box-shadow: 4px 4px 0 rgba(74,54,96,0.3), 0 1px 3px rgba(138,96,176,0.1); border-radius: 16px;
}
.rig-tile::before {
  content: ''; position: absolute; top: 0; left: 0; right: 0; height: 26px; pointer-events: none;
  background: linear-gradient(135deg, #3a2d50, #2d2545);
  background-image:
    radial-gradient(circle at 14px 13px, #ff7b7b 4px, transparent 4px),
    radial-gradient(circle at 28px 13px, #ffe97a 4px, transparent 4px),
    radial-gradient(circle at 42px 13px, #7cc490 4px, transparent 4px);
  border-bottom: 2px solid #4a3660; z-index: 3; border-radius: 13px 13px 0 0;
}
.rig-tile::after {
  content: ''; position: absolute; top: 26px; left: 0; right: 0; height: 1px;
  background: linear-gradient(90deg, transparent, #2d2545, transparent);
  z-index: 3; pointer-events: none;
}
.rig-tile.active {
  border-color: #5a9a6a;
  box-shadow: 4px 4px 0 rgba(90,154,106,0.3), 0 0 12px rgba(124,196,144,0.1);
}
.rig-tile.active::before {
  background: linear-gradient(135deg, #2a3a30, #1f3028);
  background-image:
    radial-gradient(circle at 14px 13px, #ff7b7b 4px, transparent 4px),
    radial-gradient(circle at 28px 13px, #ffe97a 4px, transparent 4px),
    radial-gradient(circle at 42px 13px, #7cc490 4px, transparent 4px);
  border-bottom-color: #3a5a48;
}
.rig-tile.alert-err { animation: tile-shake 0.3s infinite; }

/* HUD Corners - hidden in retro */
.rt-corner { display: none; }
.rt-tl, .rt-tr, .rt-bl, .rt-br { display: none; }
.rig-tile.active .rt-corner, .rig-tile.selected .rt-corner { display: none; }

/* Scanline - hidden */
.rt-scanline { display: none; }

/* Status Badge — ONLINE / OFFLINE */
.t-status-badge {
  position: absolute; top: 26px; left: 8px; right: 8px; z-index: 4;
  display: flex; align-items: center; justify-content: center; gap: 5px;
  padding: 4px 0; font-size: 0.45rem; font-weight: 800; letter-spacing: 2px;
  border-radius: 0 0 8px 8px; font-family: 'Nunito', sans-serif;
}
.t-status-badge.online {
  background: linear-gradient(180deg, rgba(124,196,144,0.15), rgba(124,196,144,0.05));
  border-bottom: none; color: #7cc490;
}
.t-status-badge.offline {
  background: linear-gradient(180deg, rgba(138,112,168,0.2), rgba(138,112,168,0.08));
  border-bottom: none; color: #8a70a8;
}
.tsb-dot { width: 6px; height: 6px; border-radius: 50%; border: 1px solid rgba(0,0,0,0.15); }
.t-status-badge.online .tsb-dot { background: #7cc490; box-shadow: 0 0 4px rgba(124,196,144,0.5); animation: ind-pulse 2s infinite; }
.t-status-badge.offline .tsb-dot { background: #5c4578; box-shadow: none; }

/* Big name */
.t-name-big {
  font-size: 1.15rem; font-weight: 700; color: #f0e4ff; letter-spacing: 1.5px;
  font-family: 'Nunito', sans-serif; margin-bottom: 6px; margin-top: 12px; position: relative; z-index: 1;
  text-transform: uppercase; line-height: 1.1;
}
.t-num { color: #c4a0e8; font-weight: 700; }

.t-meta-row {
  display: flex; justify-content: space-between; align-items: center;
  margin-bottom: 8px; position: relative; z-index: 1;
  padding: 5px 8px; background: rgba(196,160,232,0.1); border-radius: 8px;
}
.t-speed {
  font-size: 0.8rem; font-weight: 900; color: #d4a017; text-shadow: none;
  font-family: 'Nunito', sans-serif; font-size: 1rem;
}
.t-grade-badge {
  font-size: 0.55rem; font-weight: 900; padding: 2px 8px; letter-spacing: 1.5px;
  background: linear-gradient(135deg, #ffe97a, #ffd740); color: #6a5a2a !important;
  border: none; border-radius: 6px; box-shadow: 0 1px 2px rgba(0,0,0,0.1);
}

.t-profit { font-size: 0.55rem; color: #b8a0d0; font-weight: 800; margin-top: 4px; }

/* Lifetime bar — Retro segmented */
.t-lifetime {
  display: flex; align-items: center; gap: 8px; margin-top: 6px;
  position: relative; z-index: 1;
  padding: 6px 8px; background: rgba(232,208,240,0.3); border-radius: 8px;
}
.lt-bar {
  flex: 1; height: 10px; background: #2d2545;
  border: 2px solid #4a3660; overflow: hidden; position: relative; border-radius: 5px;
}
.lt-fill {
  height: 100%; background: linear-gradient(90deg, #ffe566, #ffd700, #ffcc00);
  transition: width 1s ease; box-shadow: inset 0 1px 0 rgba(255,255,255,0.15);
  border-radius: 3px;
}
.lt-fill::after { content: none; }
.lt-fill.mid { background: linear-gradient(90deg, #ffe566, #ffd700, #ffcc00); }
.lt-fill.low { background: linear-gradient(90deg, #e87c8a, #d45a6a, #cc4455); box-shadow: inset 0 1px 0 rgba(255,255,255,0.1); }
.lt-segments {
  position: absolute; inset: 0; pointer-events: none;
  background: repeating-linear-gradient(90deg, transparent 0px, transparent 18%, rgba(26,21,40,0.6) 18%, rgba(26,21,40,0.6) 20%);
}
.lt-text {
  font-size: 0.7rem; font-weight: 700; color: #f0e4ff; white-space: nowrap;
  font-family: 'Nunito', sans-serif; font-size: 0.85rem;
  min-width: 50px; text-align: right;
}
.lt-text.low { color: #dd3355; }
.lt-text.paused { opacity: 0.35; }

/* Fleet Command */
.fleet-command-v8 {
  background: #1f1833 !important; border: 2px solid #4a3660 !important; padding: 0 !important;
  box-shadow: 3px 3px 0 #3a2d50; border-radius: 14px;
  display: flex; flex-direction: column;
  overflow:hidden; 
  position: relative; z-index: 5;
  min-height:150px;
}

/* Balances row */
.fc-balances {
  display: flex !important; align-items: center; gap: 0;
  padding: 0.7rem 0; background: #231d35;
  border-bottom: 1px solid #3a2d50;
  border-radius: 12px 12px 0 0;
}
.fc-bal {
  display: flex; align-items: center; gap: 6px;
  padding: 0 1rem; border-right: 1px solid #3a2d50;
  color: #5c4578;
}
.fc-bal:last-of-type { border-right: none; }
.fc-bal-val {
  font-size: 1rem; font-weight: 700; color: #d4a017;
  font-family: 'Roboto', 'Nunito', sans-serif;
}
.fc-bal-ron { color: #5c4578; }
.fc-bal-label {
  font-size: 0.6rem; font-weight: 700; color: #8a70a8; letter-spacing: 1px;
}
.fc-online {
  display: flex; align-items: center; gap: 6px;
  margin-left: auto; padding: 0 1rem;
}
.fc-online-count {
  font-size: 0.9rem; font-weight: 700; color: #4a8a6a;
  font-family: 'Roboto', 'Nunito', sans-serif;
}
.fc-actions { display: flex !important; align-items: center; gap: 0.4rem; padding: 0.5rem 0.6rem; flex-wrap: nowrap; overflow-x: auto; }
.fc-actions::-webkit-scrollbar { display: none; }
.fc-net-bar {
  display: flex; align-items: center; gap: 10px;
  padding: 8px 1rem;
  background: #231d35; border-top: 1px solid #3a2d50;
}
.fc-net-icon {
  width: 28px; height: 28px; display: flex; align-items: center; justify-content: center;
  background: #3a2d50; border-radius: 8px; color: #5c4578; flex-shrink: 0;
}
.fc-net-label {
  font-size: 0.7rem; font-weight: 800; color: #b8a0d0; letter-spacing: 1px;
  white-space: nowrap; font-family: 'Nunito', sans-serif;
}
.fc-net-track {
  flex: 1; height: 10px; background: #2d2545; overflow: hidden;
  border: 2px solid #4a3660; border-radius: 5px;
}
.fc-net-fill {
  height: 100%; background: #c4a0e8; transition: width 0.3s ease; border-radius: 3px;
}
.fc-net-fill.mid { background: #d4a017; }
.fc-net-fill.low { background: #cc5566; }
.fc-net-val {
  font-size: 1rem; font-weight: 700; color: #f0e4ff; white-space: nowrap;
  font-family: 'Roboto', 'Nunito', sans-serif; min-width: 36px; text-align: right;
}
.fc-net-val small { font-size: 0.65rem; color: #8a70a8; }

/* Level & XP bar */
.fc-level-bar {
  display: flex; align-items: center; gap: 10px;
  padding: 8px 1rem;
  background: #231d35; border-top: 1px solid #3a2d50;
}
.fc-level-badge {
  font-size: 0.75rem; font-weight: 900; color: #fff; background: #c4a0e8;
  padding: 2px 10px; border-radius: 6px; letter-spacing: 1px;
  font-family: 'Nunito', sans-serif; white-space: nowrap;
}
.fc-level-rank {
  font-size: 0.6rem; font-weight: 800; color: #8a70a8; letter-spacing: 1.5px;
  white-space: nowrap; font-family: 'Nunito', sans-serif;
}
.fc-xp-track {
  flex: 1; height: 10px; background: #2d2545; overflow: hidden;
  border: 2px solid #4a3660; border-radius: 5px;
}
.fc-xp-fill {
  height: 100%; background: linear-gradient(90deg, #ffe566, #d4a017);
  transition: width 0.3s ease; border-radius: 3px;
}
.fc-xp-val {
  font-size: 1rem; font-weight: 700; color: #f0e4ff; white-space: nowrap;
  font-family: 'Roboto', 'Nunito', sans-serif; min-width: 60px; text-align: right;
}
.fc-xp-val small { font-size: 0.75rem; color: #8a70a8; }

.fc-btn {
  background: #1f1833; border: 2px solid #4a3660; color: #b8a0d0;
  padding: 0.45rem 0.7rem; font-size: 0.65rem; font-weight: 700; cursor: pointer;
  font-family: inherit; transition: 0.2s; border-radius: 8px; white-space: nowrap; flex-shrink: 0;
}
.fc-btn:hover { background: #ffe97a; color: #1a1528; border-color: #d4a017; }
.fc-btn.active { background: #c4a0e8; color: #fff; border-color: #9a70c0; }
.fc-btn.neon:hover { background: #ffe97a; color: #1a1528; }
.fc-stat { margin-left: auto; display: flex; flex-direction: column; text-align: right; display: none; }
.fc-stat .l { font-size: 0.5rem; color: #b8a0d0; }
.fc-stat .v { font-size: 1.1rem; color: #f0e4ff; }

/* Sockets */
.socket-grid { display: flex; flex-direction: column; gap: 8px; margin-bottom: 1rem; }
.socket-slot {
  background: #1f1833; border: 2px solid #4a3660;
  padding: 10px; position: relative;
  border-left: 4px solid #ffe97a; border-radius: 10px;
  box-shadow: 0 1px 3px rgba(138,96,176,0.06); transition: border-color 0.2s;
}
.socket-slot:hover { border-color: #b088d0; }
.socket-slot::before {
  content: none;
}
.s-label { font-size: 0.5rem; color: #8a70a8; margin-bottom: 8px; font-weight: 800; font-family: 'Nunito', sans-serif; }
.comp-section-label {
  font-size: 0.5rem; font-weight: 700; color: #8a70a8; letter-spacing: 2.5px;
  margin-top: 10px; margin-bottom: 5px; padding-left: 10px; border-left: 3px solid #ffe97a;
  font-family: 'Nunito', sans-serif;
}
.i-tag { font-size: 0.45rem; font-weight: 700; padding: 2px 8px; border-radius: 4px; color: #fff; letter-spacing: 1.5px; font-family: 'Nunito', sans-serif; }
.green-bg { background: linear-gradient(135deg, #a8d8b0, #7cc490); color: #2a5a40; }
.comp-empty { text-align: center; padding: 2rem 1rem; }
.comp-empty-icon { font-size: 2rem; margin-bottom: 0.5rem; opacity: 0.4; }
.comp-empty-text { font-size: 0.6rem; font-weight: 900; color: #b8a0d0; letter-spacing: 2px; }
.comp-empty-hint { font-size: 0.45rem; color: #b8a0d0; margin-top: 4px; }
.item-equipped { display: flex; justify-content: space-between; align-items: center; }
.item-equipped-v2 { display: flex; flex-direction: column; gap: 6px; }
.ie-top { display: flex; justify-content: space-between; align-items: center; }
.i-name { font-size: 0.75rem; color: #f0e4ff; font-weight: 800; }
.i-remove {
  background: rgba(232,124,138,0.08); color: #dd3355; border: 2px solid rgba(232,124,138,0.4);
  font-size: 0.45rem; padding: 3px 10px; cursor: pointer; font-weight: 700;
  letter-spacing: 1px; font-family: 'Nunito', sans-serif; transition: all 0.2s; border-radius: 6px;
}
.i-remove:hover { background: linear-gradient(135deg, #ff8888, #ee4455); color: #fff; border-color: #cc2233; }
.ie-stats { display: flex; align-items: center; gap: 8px; }
.ie-bar { flex: 1; height: 8px; background: #2d2545; border: 2px solid #4a3660; overflow: hidden; position: relative; border-radius: 4px; }
.ie-fill { height: 100%; background: linear-gradient(180deg, #ffe97a, #ffd740); transition: width 1s; box-shadow: inset 0 1px 0 rgba(255,255,255,0.4); border-radius: 2px; }
.ie-fill::after { content: none; }
.ie-fill.mid { background: linear-gradient(180deg, #ffe97a, #ffd740); }
.ie-fill.low { background: linear-gradient(180deg, #ffb0d0, #ff7ba0); box-shadow: inset 0 1px 0 rgba(255,255,255,0.3); }
.ie-val { font-size: 0.65rem; font-weight: 700; color: #f0e4ff; font-family: 'Roboto', 'Nunito', sans-serif; white-space: nowrap; }
.ie-meta { display: flex; gap: 10px; font-size: 0.5rem; font-weight: 700; color: #8a70a8; letter-spacing: 0.5px; font-family: 'Nunito', sans-serif; }

/* Component Summary (Status tab) */
.comp-summary { margin-top: 10px; padding-top: 8px; }
.cs-grid { display: flex; flex-direction: column; gap: 6px; }
.cs-item {
  background: #1f1833; border: 2px solid #4a3660;
  padding: 8px 10px; position: relative;
  border-left: 4px solid #ffe97a; border-radius: 10px;
  box-shadow: 0 1px 3px rgba(138,96,176,0.06);
}
.cs-type {
  font-size: 0.5rem; font-weight: 700; color: #8a70a8; letter-spacing: 2px;
  font-family: 'Nunito', sans-serif;
}
.cs-val { font-size: 0.8rem; font-weight: 900; margin-left: 8px; font-family: 'Nunito', sans-serif; }
.cs-val.dim { color: #4a3660; }
.cs-val.cyan { text-shadow: none; color: #5c4578; }
.cs-val.amber { text-shadow: none; color: #d4a017; }
.cs-detail {
  display: flex; flex-wrap: wrap; gap: 6px; margin-top: 5px;
  font-size: 0.55rem; font-weight: 700; color: #b8a0d0; font-family: 'Nunito', sans-serif;
}
.item-placeholder { font-size: 0.6rem; color: #4a3660; text-align: center; padding: 4px; font-weight: 800; }

@keyframes tile-shake {

  0% { transform: translate(0,0); }
  25% { transform: translate(1px, 1px); }
  50% { transform: translate(-1px, -1px); }
  75% { transform: translate(1px, -1px); }
  100% { transform: translate(0,0); }
}

.tile-processing {
  position: absolute; inset: 0; pointer-events: none; opacity: 0.08; z-index: 1;
  background: linear-gradient(180deg, transparent 30%, rgba(168,216,176,0.2) 60%, transparent 90%);
  animation: tile-breathe 3s ease-in-out infinite;
}
@keyframes tile-breathe { 0%,100% { opacity: 0.05; } 50% { opacity: 0.12; } }
.data-stream {
  position: absolute; top: -100px; left: 0; right: 0; height: 2px;
  background: linear-gradient(90deg, transparent, #a8d8b0, transparent);
  box-shadow: 0 0 6px rgba(168,216,176,0.3);
  animation: stream-flow 3s infinite linear; border-radius: 2px;
}
.data-stream.delay-1 { animation-delay: 1s; }
.data-stream.delay-2 { animation-delay: 2s; }

@keyframes stream-flow {
  0% { top: -10px; opacity: 0; }
  20% { opacity: 1; }
  80% { opacity: 1; }
  100% { top: 100%; opacity: 0; }
}

.tile-alert {
  position: absolute; top: 26px; left: 6px; right: 6px;
  height: 22px; display: flex; align-items: center; justify-content: center;
  font-size: 0.45rem; font-weight: 900; letter-spacing: 1.5px;
  animation: alert-pulse 1s infinite alternate;
  z-index: 5; border-radius: 0 0 6px 6px; font-family: 'Nunito', sans-serif;
}
.tile-alert.error { background: linear-gradient(135deg, #ff7b7b, #ff5555); color: #fff; }
.tile-alert.warning { background: linear-gradient(135deg, #ffe97a, #ffd740); color: #5a4a2a; }

.a-dot { width: 4px; height: 4px; background: currentColor; border-radius: 50%; margin-right: 6px; }

@keyframes alert-pulse {
  from { opacity: 0.8; }
  to { opacity: 1; }
}

.rig-tile:hover {
  border-color: #5c4578; background: #231d35;
  transform: translateY(-2px); box-shadow: 5px 6px 0 rgba(74,54,96,0.3), 0 2px 6px rgba(138,96,176,0.15);
}
.rig-tile:hover .rt-corner { display: none; }
.rig-tile.selected {
  border-color: #ffe566; background: rgba(255,229,102,0.06);
  box-shadow: 4px 4px 0 rgba(212,160,23,0.3), 0 0 16px rgba(255,229,102,0.2);
  transform: translateY(-1px);
}
.rig-tile.selected::before {
  background: linear-gradient(135deg, #ffe97a, #ffd740);
  background-image:
    radial-gradient(circle at 14px 13px, #ff7b7b 4px, transparent 4px),
    radial-gradient(circle at 28px 13px, #fff 4px, transparent 4px),
    radial-gradient(circle at 42px 13px, #98ccaa 4px, transparent 4px);
  border-bottom-color: #d4a017;
}

.rig-tile.empty {
  border: 2.5px dashed #4a3660; opacity: 0.75; background: rgba(248,240,255,0.6);
  border-radius: 16px;
}
.rig-tile.empty::before { display: none; }
.rig-tile.empty::after { display: none; }
.rig-tile.empty .plus { font-size: 2rem; color: #c4a0e8; margin-bottom: 0.5rem; }
.rig-tile.empty span { font-size: 0.55rem; font-weight: 800; color: #8a70a8; letter-spacing: 2px; font-family: 'Nunito', sans-serif; }
.rig-tile.empty:hover { border-color: #b088d0; opacity: 1; background: #2d2545; }

.rig-tile.buy-slot {
  border: 2.5px dashed #ffd740; background: linear-gradient(165deg, rgba(255,229,102,0.08), rgba(255,229,102,0.03));
  border-radius: 16px;
}
.rig-tile.buy-slot::before { display: none; }
.rig-tile.buy-slot::after { display: none; }
.rig-tile.buy-slot:hover { background: rgba(255,229,102,0.15); border-color: #d4a017; transform: translateY(-2px); }
.rig-tile.buy-slot .plus { font-size: 2rem; margin-bottom: 0.5rem; color: #d4a017; }
.rig-tile.buy-slot span { font-size: 0.55rem; font-weight: 800; color: #b8a0d0; letter-spacing: 2px; font-family: 'Nunito', sans-serif; }
.buy-price { font-size: 0.6rem; margin-top: 8px; font-weight: 900; color: #d4a017; font-family: 'Nunito', sans-serif; font-size: 0.85rem; }

.t-body { position: relative; z-index: 1; }
.t-body.centered { flex: 1; display: flex; flex-direction: column; align-items: center; justify-content: center; }
.ambermonospace { font-family: 'Nunito', sans-serif; color: #d4a017; }

/* Confirm Modal */
.confirm-modal-overlay {
  position: fixed; inset: 0; background: rgba(0,0,0,0.5);
  backdrop-filter: blur(4px); z-index: 2000;
  display: flex; align-items: center; justify-content: center; padding: 2rem;
}
.confirm-dialog {
  background: #1f1833; border: 2px solid #5c4578; width: 100%; max-width: 440px;
  box-shadow: 4px 4px 0 rgba(74,54,96,0.3); animation: modal-zoom 0.2s cubic-bezier(0.16, 1, 0.3, 1); border-radius: 14px; overflow: hidden;
}
@keyframes modal-zoom { from { transform: scale(0.95); opacity: 0; } to { transform: scale(1); opacity: 1; } }

.diag-header { padding: 1.5rem; border-bottom: 1px solid #3a2d50; background: linear-gradient(180deg, #c9a0e8, #b088d0); }
.diag-header .diag-tag { color: rgba(255,255,255,0.7); font-size: 0.6rem; }
.diag-header h3 { font-size: 1rem; font-weight: 800; color: #fff; margin-top: 8px; letter-spacing: 1px; }

.diag-body { padding: 1.5rem; }
.diag-body p { font-size: 0.85rem; color: #f0e4ff; line-height: 1.6; margin-bottom: 1.5rem; }

.expansion-details { background: #231d35; border: 2px solid #4a3660; padding: 1rem; margin-bottom: 1.5rem; border-radius: 10px; }
.det-row { display: flex; justify-content: space-between; margin-bottom: 8px; align-items: center; }
.det-row:last-child { margin-bottom: 0; }
.det-row .l { font-size: 0.7rem; font-weight: 800; color: #b8a0d0; letter-spacing: 1px; }
.det-row .v { font-size: 0.9rem; font-weight: 800; color: #f0e4ff; }

.diag-warning { text-align: center; color: #cc4444; font-size: 0.75rem; font-weight: 900; letter-spacing: 1px; }

.diag-footer { padding: 1rem 1.5rem; background: #231d35; display: flex; gap: 1rem; }
.d-btn { flex: 1; height: 44px; font-family: inherit; font-size: 0.8rem; font-weight: 800; cursor: pointer; border: 2px outset #4a3660; transition: 0.2s; border-radius: 8px; letter-spacing: 1px; }
.d-btn.cancel { background: #2d2545; color: #b8a0d0; }
.d-btn.cancel:hover { background: #1f1833; color: #f0e4ff; border-style: inset; }
.d-btn.confirm { background: #ffe566; color: #1a1528; border-color: #d4a017; }
.d-btn.confirm:hover { background: #ffd700; border-style: inset; }

/* Research View */
.view-research { height: 100%; display: flex; flex-direction: column; padding-bottom: 50px; }
.research-header {
  background: #1f1833; border: 2px solid #5c4578; padding: 2rem; border-left: 4px solid #ffe566;
  display: flex; justify-content: space-between; align-items: center; margin-bottom: 3rem; box-shadow: 3px 3px 0 rgba(74,54,96,0.3); border-radius: 12px;
}
.research-header h1 { font-size: 1.5rem; font-weight: 800; color: #f0e4ff; margin-bottom: 4px; font-family: 'Nunito', sans-serif; }
.rh-points { text-align: right; }
.rh-points .v { font-size: 2rem; color: #f0e4ff; text-shadow: none; }

.tree-container { flex: 1; display: grid; grid-template-columns: repeat(3, 1fr); gap: 2rem; padding: 0 1rem; }
.tree-branch { display: flex; flex-direction: column; align-items: center; }
.branch-label { 
  font-size: 0.6rem; font-weight: 800; border: 1px solid; padding: 4px 12px; margin-bottom: 2rem; 
  letter-spacing: 2px; background: rgba(0,0,0,0.5);
}

.nodes-path { display: flex; flex-direction: column; gap: 3rem; align-items: center; width: 100%; }
.node-wrapper { position: relative; width: 100%; display: flex; justify-content: center; }

.node-connector {
  position: absolute; bottom: 100%; left: 50%; width: 3px; height: 3rem;
  background: #c4a0e8; transform: translateX(-50%); z-index: 1;
}
.node-connector.unlocked { background: #ffe566; box-shadow: none; }

.tree-node {
  width: 100%; max-width: 240px; background: #1f1833; border: 2px solid #4a3660;
  padding: 1.25rem; display: flex; gap: 1rem; cursor: pointer; position: relative; z-index: 2; transition: 0.2s; box-shadow: 2px 2px 0 rgba(74,54,96,0.3); border-radius: 10px;
}
.tree-node:hover { border-color: #5c4578; background: #231d35; }
.tree-node.unlocked { border-color: #ffe566; background: rgba(255,229,102,0.08); }
.tree-node.locked { opacity: 0.3; cursor: not-allowed; }

.node-icon { font-size: 0.7rem; font-weight: 900; background: #231d35; width: 40px; height: 40px; display: flex; align-items: center; justify-content: center; border: 2px solid #4a3660; border-radius: 8px; }
.node-data { display: flex; flex-direction: column; gap: 4px; }
.n-name { font-size: 0.75rem; font-weight: 800; color: #f0e4ff; }
.n-desc { font-size: 0.6rem; color: #b8a0d0; font-weight: 600; line-height: 1.3; }
.n-cost { font-size: 0.55rem; font-weight: 900; color: #d4a017; margin-top: 4px; }

.node-glow { position: absolute; inset: 0; opacity: 0.05; pointer-events: none; }
.unlocked .node-glow { opacity: 0.1; }




/* Strategic Advisory */
.strategic-advisory { margin-top: 2rem; border-top: 2px solid #4a3660; padding-top: 1.5rem; }

.advisory-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 1rem; margin-top: 1rem; }
.tip-card { background: #1f1833; border: 2px solid #4a3660; padding: 1rem; border-left: 4px solid #4a3660; box-shadow: 2px 2px 0 rgba(74,54,96,0.3); border-radius: 10px; }

.tip-card.info { border-left-color: #ffe566; }
.tip-card.warning { border-left-color: #ffd700; }
.tip-card.error { border-left-color: #ff6b6b; }
.tip-card.success { border-left-color: #a8d8b0; }

.tip-head { display: flex; align-items: center; gap: 0.75rem; margin-bottom: 0.5rem; }
.tip-status { width: 6px; height: 6px; border-radius: 50%; background: currentColor; border: 1px solid rgba(0,0,0,0.2); }
.tip-title { font-size: 0.65rem; font-weight: 800; color: #f0e4ff; letter-spacing: 1px; }
.tip-desc { font-size: 0.75rem; color: #b8a0d0; line-height: 1.4; margin-bottom: 0.5rem; }
.tip-meta { display: flex; flex-direction: column; gap: 2px; }
.tip-meta span { font-size: 0.55rem; font-weight: 800; color: #b8a0d0; }
.tip-card.success .tip-meta span { color: #4a8a6a; opacity: 0.8; }
.tip-card.info .tip-meta span { color: #d4a017; opacity: 0.8; }


/* Side Panel - Retro Window */

.command-panel {
  background: #1f1833;
  border: 2.5px solid #4a3660; position: relative; overflow: hidden; transition: 0.4s ease;
  display: flex; flex-direction: column; max-height: 75vh;
  box-shadow: 5px 5px 0 rgba(74,54,96,0.3), 0 2px 8px rgba(138,96,176,0.1); border-radius: 16px;
}
.command-panel::before {
  content: ''; position: absolute; top: 0; left: 0; right: 0; height: 30px; pointer-events: none; z-index: 10;
  background: linear-gradient(135deg, #3a2d50, #2d2545);
  background-image:
    radial-gradient(circle at 16px 15px, #ff7b7b 5px, transparent 5px),
    radial-gradient(circle at 32px 15px, #ffe97a 5px, transparent 5px),
    radial-gradient(circle at 48px 15px, #7cc490 5px, transparent 5px);
  border-bottom: 2px solid #4a3660; border-radius: 13px 13px 0 0;
}
.command-panel::after {
  content: ''; position: absolute; top: 30px; left: 0; right: 0; height: 1px;
  background: linear-gradient(90deg, transparent, #3a2d50, transparent);
  z-index: 10; pointer-events: none;
}
.command-panel.visible {
  border-color: #5c4578;
  box-shadow: 6px 6px 0 rgba(74,54,96,0.3), 0 4px 16px rgba(138,96,176,0.15);
}

/* Command Panel HUD Corners - hidden in retro */
.cp-hud-corner, .cp-tl, .cp-tr, .cp-bl, .cp-br { display: none; }
.command-panel.visible .cp-hud-scanline, .cp-hud-scanline { display: none; }


.panel-inner {
  padding: 1rem; padding-top: 38px;
  display: flex; flex-direction: column;
  animation: slideUp 0.35s cubic-bezier(0.16, 1, 0.3, 1); flex: 1; min-height: 0;
}
@keyframes slideUp { from { transform: translateY(12px); opacity: 0; } to { transform: translateY(0); opacity: 1; } }

.title-top { display: flex; align-items: center; gap: 8px; margin-bottom: 6px; }
.diag-tag {
  font-size: 0.5rem; font-weight: 800; color: #8a70a8; letter-spacing: 2.5px; flex: 1;
  font-family: 'Nunito', sans-serif;
}
.hud-header-line {
  height: 2px; margin-top: 8px; border-radius: 1px;
  background: linear-gradient(90deg, #c4a0e8, #3a2d50 60%, transparent);
}
.h-brand { color: #fff; font-weight: 800; font-size: 1.1rem; letter-spacing: 2px; font-family: 'Nunito', sans-serif; }

/* Skeleton Loading */
@keyframes skel-shimmer {
  0% { background-position: 200% 0; }
  100% { background-position: -200% 0; }
}
.skel-status { display: flex; flex-direction: column; gap: 8px; }
.skel-line {
  height: 10px; border-radius: 5px;
  background: linear-gradient(90deg, #3a2d50 25%, #2d2545 50%, #3a2d50 75%);
  background-size: 200% 100%;
  animation: skel-shimmer 1.5s ease infinite;
}
.skel-w20 { width: 20%; }
.skel-w25 { width: 25%; }
.skel-w30 { width: 30%; }
.skel-w40 { width: 40%; }
.skel-w50 { width: 50%; }
.skel-title { display: flex; align-items: center; justify-content: center; padding: 4px 0; }
.skel-title .skel-line { height: 8px; }
.skel-card {
  background: #1f1833; border: 2px solid #3a2d50; border-radius: 12px;
  padding: 12px; display: flex; flex-direction: column; gap: 10px;
}
.skel-row { display: flex; align-items: center; gap: 8px; }
.skel-dot {
  width: 8px; height: 8px; border-radius: 50%;
  background: linear-gradient(90deg, #3a2d50 25%, #2d2545 50%, #3a2d50 75%);
  background-size: 200% 100%;
  animation: skel-shimmer 1.5s ease infinite;
}
.skel-bar {
  height: 6px; border-radius: 3px; width: 100%;
  background: linear-gradient(90deg, #3a2d50 25%, #2d2545 50%, #3a2d50 75%);
  background-size: 200% 100%;
  animation: skel-shimmer 1.5s ease infinite;
}
.skel-modules { display: grid; grid-template-columns: repeat(3, 1fr); gap: 6px; }
.skel-mod {
  background: #1f1833; border: 2px solid #3a2d50; border-left: 4px solid #2d2545;
  border-radius: 10px; padding: 10px; display: flex; flex-direction: column; gap: 6px;
}

/* Config Tabs — Retro style */
.config-tabs { display: flex; gap: 4px; margin-bottom: 0.75rem; border-bottom: none; }
.config-tabs button {
  flex: 1; background: linear-gradient(180deg, #f0e0ff, #2d2545);
  border: 2px solid #4a3660; border-bottom: 2px solid transparent;
  padding: 8px 0; color: #b8a0d0; font-size: 0.55rem; font-weight: 800; cursor: pointer;
  transition: all 0.25s; font-family: 'Nunito', sans-serif; letter-spacing: 1.5px;
  position: relative; border-radius: 8px 8px 4px 4px;
}
.config-tabs button:hover { color: #1a1528; background: #ffe97a; border-color: #d4a017; }
.config-tabs button.active {
  color: #fff; border-color: #9a70c0;
  background: linear-gradient(135deg, #c4a0e8, #b088d0);
  text-shadow: 0 1px 2px rgba(0,0,0,0.15); border-style: solid;
  box-shadow: inset 0 1px 0 rgba(255,255,255,0.3), 0 2px 4px rgba(138,96,176,0.15);
}

.config-content { margin-bottom: 0.5rem; flex: 1; overflow-y: auto; min-height: 0; }
.config-content::-webkit-scrollbar { width: 6px; }
.config-content::-webkit-scrollbar-track { background: #231d35; border-radius: 3px; }
.config-content::-webkit-scrollbar-thumb { background: #c4a0e8; border-radius: 3px; border: 1px solid #3a2d50; }
.tab-pane.scroll { padding-right: 4px; }
.tab-pane.scroll::-webkit-scrollbar { width: 6px; }
.tab-pane.scroll::-webkit-scrollbar-thumb { background: #c4a0e8; border-radius: 3px; }

.section-label {
  font-size: 0.6rem; font-weight: 700; color: #8a70a8; margin-bottom: 6px;
  border-left: 3px solid #ffe97a; padding-left: 8px;
  font-family: 'Nunito', sans-serif; letter-spacing: 1px;
}
.section-label.mt { margin-top: 0.6rem; }

.item-list { display: flex; flex-direction: column; gap: 8px; }
.config-item { background: #231d35; border: 2px solid #4a3660; padding: 10px; display: flex; justify-content: space-between; align-items: center; border-radius: 8px; }

.config-item.inv { border-style: dashed; }
.config-item.active { border-color: #ffe566; }
.item-info { display: flex; flex-direction: column; gap: 2px; }
.item-name { font-size: 0.75rem; font-weight: 800; color: #f0e4ff; }
.item-durability, .item-spec { font-size: 0.6rem; font-weight: 800; color: #b8a0d0; }

.remove-btn, .install-btn { background: #1f1833; border: 2px outset #4a3660; color: #b8a0d0; font-size: 0.55rem; font-weight: 800; padding: 4px 8px; cursor: pointer; font-family: inherit; border-radius: 6px; }
.remove-btn:hover { background: #ff6b6b; color: #fff; border-style: inset; }
.install-btn:hover { background: #ffe566; color: #1a1528; border-style: inset; }

.repair-box {
  margin-top: 1rem; border: 2px solid #ffe566; padding: 1rem; position: relative;
  background: rgba(255,229,102,0.08); border-radius: 10px;
}
.repair-box::before {
  content: none;
}
.repair-box::after {
  content: none;
}
.repair-msg { font-size: 0.55rem; color: #d4a017; font-weight: 900; margin-bottom: 10px; text-align: center; letter-spacing: 1px; }
.warn { display: block; text-align: center; font-size: 0.5rem; color: #cc4444; margin-top: 6px; font-weight: 900; letter-spacing: 1px; }

.upgrade-grid { display: flex; flex-direction: column; gap: 8px; }
.upgrade-card {
  background: #1f1833; border: 2px solid #4a3660; padding: 12px; position: relative;
  border-left: 3px solid #ffe566; transition: all 0.3s; border-radius: 10px;
}
.upgrade-card:hover { border-color: #5c4578; }

.u-head { display: flex; justify-content: space-between; margin-bottom: 8px; }
.u-type { font-size: 0.5rem; font-weight: 900; color: #b8a0d0; letter-spacing: 2px; }
.u-level { font-size: 0.5rem; font-weight: 900; color: #f0e4ff; letter-spacing: 1px; font-family: 'Pixelify Sans', 'Nunito', sans-serif; }
.u-body { display: flex; justify-content: space-between; align-items: center; }
.u-bonus { font-size: 1.1rem; font-weight: 700; color: #d4a017; font-family: 'Roboto', 'Nunito', sans-serif; text-shadow: none; }
.u-btn {
  background: #ffe566; color: #1a1528; border: 2px outset #d4a017;
  font-size: 0.5rem; font-weight: 900; padding: 6px 14px; cursor: pointer; font-family: inherit;
  letter-spacing: 1.5px; transition: all 0.3s; border-radius: 6px;
}
.u-btn:hover { background: #ffd700; border-style: inset; }
.u-btn:disabled { opacity: 0.2; cursor: not-allowed; }

.panel-loading { height: 100%; display: flex; align-items: center; justify-content: center; font-size: 0.6rem; color: #b8a0d0; letter-spacing: 2px; }
.panel-empty { display: flex; flex-direction: column; align-items: center; justify-content: center; padding: 3rem 1rem; gap: 10px; position: relative; z-index: 1; }
.pe-icon { font-size: 2rem; color: #c4a0e8; animation: ind-pulse 3s infinite; }
.pe-text { font-size: 0.7rem; font-weight: 900; color: #b8a0d0; letter-spacing: 3px; }
.pe-sub { font-size: 0.5rem; color: #b8a0d0; letter-spacing: 1px; }

.mode-tag {
  font-size: 0.5rem; font-weight: 700; color: #6a5a2a; padding: 3px 10px;
  border: none; display: inline-block; letter-spacing: 1.5px;
  background: linear-gradient(135deg, #ffe97a, #ffd740); position: relative;
  border-radius: 20px; font-family: 'Nunito', sans-serif;
  box-shadow: 0 1px 2px rgba(0,0,0,0.1);
}
.mode-tag::before { content: '◆'; margin-right: 4px; font-size: 0.35rem; }
.mode-tag.pool { background: linear-gradient(135deg, #ffe97a, #ffd740); color: #6a5a2a; }
.mode-tag.solo { background: linear-gradient(135deg, #d4b0f0, #b088d0); color: #fff; }

/* ═══ TELEMETRY HUD ═══ */
.panel-telemetry { display: flex; flex-direction: column; gap: 0.6rem; margin: 0.6rem 0; }

/* HUD Title */
.tele-hud-title { display: flex; align-items: center; gap: 8px; margin-bottom: 4px; }
.thud-line { flex: 1; height: 1px; background: linear-gradient(90deg, transparent, #4a3660, transparent); }
.thud-txt {
  font-size: 0.5rem; font-weight: 700; color: #8a70a8; letter-spacing: 3px; white-space: nowrap;
  font-family: 'Nunito', sans-serif;
}
.thud-blink { width: 6px; height: 6px; background: #ffe97a; border-radius: 50%; border: 1px solid #d4a017; animation: hud-blink 2s infinite; }
@keyframes hud-blink { 0%,49% { opacity: 1; } 50%,100% { opacity: 0.2; } }

/* HUD Card */
.tele-hud {
  position: relative; padding: 0.65rem 0.75rem; overflow: hidden;
  background: #1f1833;
  border: 2px solid #4a3660; transition: all 0.3s ease; border-radius: 12px;
  box-shadow: 0 1px 3px rgba(138,96,176,0.08);
}
.tele-hud::before {
  content: none;
}
.tele-hud.hud-warn {
  border-color: #ffd740; background: rgba(255,229,102,0.06);
  box-shadow: 0 1px 4px rgba(212,160,23,0.1);
}
.tele-hud.hud-danger {
  border-color: #ff7b7b; background: rgba(232,124,138,0.06);
  animation: hud-alert 1.5s infinite; box-shadow: 0 1px 4px rgba(255,80,80,0.12);
}
@keyframes hud-alert { 0%,100% { border-color: rgba(239,68,68,0.5); } 50% { border-color: rgba(239,68,68,0.15); } }

/* Corner Brackets - hidden in retro */
.hud-corner { display: none; }
.hud-tl { display: none; }
.hud-tr { display: none; }
.hud-bl { display: none; }
.hud-br { display: none; }
.hud-danger .hud-corner { display: none; }

/* Scanline sweep - disabled in retro */
.hud-scanline { display: none; }
@keyframes hud-scan { 0% { left: -100%; } 100% { left: 100%; } }

/* Top row */
.hud-row-top { display: flex; align-items: center; gap: 6px; margin-bottom: 6px; position: relative; z-index: 1; }
.hud-indicator { width: 8px; height: 8px; border-radius: 50%; flex-shrink: 0; border: 1px solid rgba(0,0,0,0.2); }
.ind-green { background: #a8d8b0; box-shadow: none; animation: ind-pulse 2s infinite; }
.ind-amber { background: #ffe566; box-shadow: none; animation: ind-pulse 1s infinite; }
.ind-red { background: #ff6b6b; box-shadow: none; animation: ind-pulse 0.5s infinite; }
.ind-cyan { background: #c4a0e8; box-shadow: none; animation: ind-pulse 2s infinite; }
@keyframes ind-pulse { 0%,100% { opacity: 1; } 50% { opacity: 0.4; } }

.hud-sys-id {
  font-size: 0.55rem; font-weight: 700; color: #8a70a8; letter-spacing: 2px; flex: 1;
  font-family: 'Nunito', sans-serif;
}
.hud-readout {
  font-size: 1.2rem; font-weight: 700; color: #d4a017;
  font-family: 'Roboto', 'Nunito', sans-serif; text-shadow: none;
}
.hud-readout small { font-size: 0.6rem; color: #8a70a8; margin-left: 2px; text-shadow: none; }
.hud-readout.hot { color: #dd3355; text-shadow: none; }
.hud-readout-cyan { color: #5c4578; text-shadow: none; }
.hud-readout-green { color: #4a8a6a; text-shadow: none; }

/* Gauge bar */
.hud-gauge { position: relative; z-index: 1; margin: 4px 0; }
.hud-gauge-track {
  height: 12px; background: #2d2545; border: 2px solid #4a3660;
  position: relative; overflow: hidden; border-radius: 6px;
}
.hud-gauge-fill {
  height: 100%; transition: width 0.6s ease; position: relative; border-radius: 4px;
  box-shadow: inset 0 1px 0 rgba(255,255,255,0.4);
}
.hud-gauge-fill::after { content: none; }
.hud-fill-amber { background: linear-gradient(180deg, #ffe97a, #ffd740); }
.hud-fill-cyan { background: linear-gradient(180deg, #c4a0e8, #b088d0); }
.hud-fill-green { background: linear-gradient(180deg, #a8d8b0, #7cc490); }
.hud-fill-red { background: linear-gradient(180deg, #ff8888, #ee4455) !important; }

/* Gauge segments overlay */
.hud-gauge-segments {
  position: absolute; inset: 0; pointer-events: none;
  background: repeating-linear-gradient(90deg, transparent 0px, transparent 9%, rgba(255,255,255,0.35) 9%, rgba(255,255,255,0.35) 10%);
}

/* Ticks */
.hud-gauge-ticks { display: flex; justify-content: space-between; margin-top: 3px; }
.hud-gauge-ticks span { font-size: 0.4rem; color: #b0a0c0; font-family: 'Nunito', sans-serif; }

/* Bottom row */
.hud-row-bot { display: flex; align-items: center; justify-content: space-between; margin-top: 5px; position: relative; z-index: 1; }
.hud-tag {
  font-size: 0.45rem; font-weight: 700; color: #4a8a6a; letter-spacing: 1.5px;
  font-family: 'Nunito', sans-serif;
  padding: 2px 6px; background: rgba(168,216,176,0.15); border-radius: 4px;
}
.hud-warn .hud-tag { color: #b8860b; background: rgba(255,229,102,0.2); }
.hud-danger .hud-tag { color: #dd3355; background: rgba(255,107,107,0.15); animation: hud-blink 0.8s infinite; }
.hud-aux { font-size: 0.4rem; color: #b0a0c0; letter-spacing: 1px; font-family: 'Nunito', sans-serif; }
.hot { color: #dd3355 !important; }

.panel-stats-inline { display: grid; grid-template-columns: 1fr 1fr; border-top: 1px solid #3a2d50; padding-top: 1.5rem; gap: 1rem; }
.s-block { display: flex; flex-direction: column; }
.sl { font-size: 0.55rem; font-weight: 800; color: #b8a0d0; }
.sv { font-size: 0.9rem; font-weight: 800; color: #f0e4ff; }

.panel-meta { margin-top: 0.5rem; border-top: 1px solid #3a2d50; padding-top: 0.5rem; display: flex; justify-content: space-between; font-size: 0.55rem; color: #b8a0d0; flex-shrink: 0; }

/* Tactical Mode Selector */
.panel-controls-v8 {
  display: flex; flex-direction: column; gap: 0.5rem;
  margin-top: auto;
  padding-top: 0.75rem;
  border-top: 2px solid #3a2d50;
  flex-shrink: 0;
}
.mode-selector-v8 {
  display: flex; flex-direction: column; gap: 0.75rem; width: 100%;
  border: 2px solid #4a3660; padding: 1rem;
  background: linear-gradient(165deg, #231d35, #231d35); border-radius: 12px;
}

.selector-head {
  font-size: 0.6rem; color: #8a70a8; letter-spacing: 2px; text-align: center;
  margin-bottom: 0.5rem; font-weight: 700; font-family: 'Nunito', sans-serif;
}
.selector-grid { display: flex; gap: 0.6rem; }

.mode-opt {
  flex: 1; display: flex; flex-direction: column; align-items: center; justify-content: center;
  padding: 1.25rem 0; background: #1f1833;
  border: 2px solid #4a3660; cursor: pointer; transition: all 0.2s;
  font-family: inherit; border-radius: 12px;
  box-shadow: 0 2px 0 rgba(74,54,96,0.2);
}

.mode-opt .m-title { font-size: 0.75rem; font-weight: 800; color: #f0e4ff; margin-bottom: 4px; font-family: 'Nunito', sans-serif; }
.mode-opt .m-desc { font-size: 0.55rem; font-weight: 700; opacity: 0.6; letter-spacing: 1px; color: #8a70a8; }

.mode-opt.pool:hover {
  background: linear-gradient(180deg, #ffe97a, #ffd740); border-color: #d4a017;
  transform: translateY(-2px); box-shadow: 0 4px 0 #c8a020;
}
.mode-opt.pool:hover .m-title { color: #4a3a1c; }
.mode-opt.pool:hover .m-desc { opacity: 0.8; color: #6a5a2a; }

.mode-opt.solo:hover:not(:disabled) {
  background: linear-gradient(180deg, #d4b0f0, #b088d0); border-color: #9a70c0;
  transform: translateY(-2px); box-shadow: 0 4px 0 #8860a8;
}
.mode-opt.solo:hover:not(:disabled) .m-title { color: #fff; text-shadow: none; }
.mode-opt.solo:hover:not(:disabled) .m-desc { opacity: 0.9; color: #3a2d50; }

.mode-opt.solo:disabled { opacity: 0.2; cursor: not-allowed; filter: grayscale(100%); }

/* Hold-to-activate bar */
.hold-bar {
  width: 80%; height: 4px; background: #1a1b2e; border: 1px solid #2f3052; margin-top: 8px;
  overflow: hidden; position: relative;
}
.hold-fill {
  height: 100%; background: linear-gradient(90deg, #92400e, #f59e0b, #fbbf24);
  box-shadow: 0 0 8px rgba(245,158,11,0.5); transition: width 0.05s linear;
}
.hold-fill::after {
  content: ''; position: absolute; top: 0; right: 0; width: 3px; height: 100%;
  background: rgba(255,255,255,0.7);
}
.hold-hint {
  font-size: 0.4rem; font-weight: 900; color: #4f4f6f; letter-spacing: 2px; margin-top: 8px;
  animation: hud-blink 1.5s infinite;
}


.mode-abort {
  background: #1f1833; border: 2px solid #4a3660; color: #8a70a8;
  font-size: 0.55rem; font-weight: 700; padding: 0.6rem; cursor: pointer;
  font-family: 'Nunito', sans-serif; margin-top: 0.25rem; border-radius: 8px; transition: all 0.2s;
}
.mode-abort:hover { color: #f0e4ff; border-color: #b088d0; background: #231d35; }

.action-btn-v8 {
  width: 100%; padding: 0.85rem; border: none; font-family: 'Nunito', sans-serif;
  font-weight: 700; font-size: 0.85rem; cursor: pointer; transition: all 0.2s; border-radius: 10px;
  letter-spacing: 1px;
}
.action-btn-v8.power {
  background: linear-gradient(135deg, #a8d8b0, #7cc490); color: #2a5a40;
  box-shadow: 0 3px 0 #5a9a78, 0 3px 8px rgba(42,138,42,0.2);
}
.action-btn-v8.power:hover { transform: translateY(-1px); box-shadow: 0 4px 0 #5a9a78, 0 4px 12px rgba(42,138,42,0.25); }
.action-btn-v8.power:active { transform: translateY(2px); box-shadow: 0 1px 0 #5a9a78; }
.action-btn-v8.power.active {
  background: linear-gradient(135deg, #ff8888, #ee4455); color: #fff;
  box-shadow: 0 3px 0 #cc2233, 0 3px 8px rgba(204,34,51,0.2);
}
.action-btn-v8.power.active:hover { box-shadow: 0 4px 0 #cc2233, 0 4px 12px rgba(204,34,51,0.25); }

.sub-btn-v8 {
  background: #1f1833; border: 2px solid #4a3660; color: #b8a0d0;
  padding: 0.65rem; font-family: 'Nunito', sans-serif; font-weight: 700; font-size: 0.65rem;
  cursor: pointer; transition: all 0.2s; width: 100%; border-radius: 8px; letter-spacing: 1px;
}
.sub-btn-v8:hover { background: linear-gradient(180deg, #ffe97a, #ffd740); color: #1a1528; border-color: #d4a017; }


/* Waiting panel */
.panel-waiting { flex: 1; display: flex; flex-direction: column; align-items: center; justify-content: center; text-align: center; color: #b8a0d0; }
.wait-vignette { width: 40px; height: 40px; border: 2px solid #4a3660; position: relative; margin-bottom: 2rem; }
.wait-vignette::after { content: ''; position: absolute; inset: 0; border: 2px solid #4a3660; animation: wait-expand 2s infinite; }
@keyframes wait-expand { 0% { opacity: 1; transform: scale(1); } 100% { opacity: 0; transform: scale(2); } }

/* History Terminal */
.history-terminal { background: #1f1833; border: 2px solid #5c4578; height: 100%; display: flex; flex-direction: column; box-shadow: 3px 3px 0 rgba(74,54,96,0.3); border-radius: 12px; overflow: hidden; }
.history-head { padding: 1rem; border-bottom: 2px solid #4a3660; font-weight: 800; font-size: 0.8rem; color: #f0e4ff; background: linear-gradient(180deg, #c9a0e8, #b088d0); color: #fff; }
.history-body { flex: 1; overflow-y: auto; padding: 1rem; }
.history-row { display: grid; grid-template-columns: 120px 180px 1fr; padding: 0.65rem 0; border-bottom: 1px solid #3a2d50; font-size: 0.8rem; color: #f0e4ff; }
.b-num { color: #b8a0d0; }
.b-res.ok { color: #d4a017; }

@media (max-width: 1200px) {
  .fleet-layout { grid-template-columns: 1fr; }
  .command-panel { position: fixed; right: -400px; top: 0; bottom: 0; width: 400px; z-index: 1000; box-shadow: -10px 0 30px #000; max-height: 100vh; }
  .command-panel.visible { right: 0; }
  .forge-grid-layout { grid-template-columns: 200px 1fr 280px; }
}

@media (max-width: 1024px) {
  .view-forge { overflow: visible; flex: none; min-height: auto; }
  .forge-grid-layout { grid-template-columns: 1fr; height: auto; }
  .forge-sidebar { max-height: none; overflow: visible; height: auto; }
  .forge-main-grid { overflow: visible; height: auto; }
  .forge-action-panel { max-height: none; overflow: visible; height: auto; }
  .stake-plans { grid-template-columns: repeat(2, 1fr); }
  .tree-container { grid-template-columns: repeat(2, 1fr); gap: 1rem; }
}

@media (max-width: 768px) {
  /* Header */
  .terminal-header { height: auto; border-bottom: 1px solid #3f3f5c; }
  .h-inner { flex-direction: column; padding: 0.6rem 0.8rem; gap: 0.5rem; height: auto; }
  .h-main { width: 100%; justify-content: space-between; }
  .h-brand { margin-right: 0; }
  .h-metrics { gap: 1rem; flex-wrap: wrap; justify-content: center; }
  .m-box .v { font-size: 0.85rem; }
  .h-resources { padding: 0 0.8rem; gap: 0.8rem; border-left: none; box-shadow: none; flex-wrap: wrap; justify-content: center; }
  .h-balance { padding: 0 0.5rem; }

  /* Body padding */
  .body-inner { padding: 0.8rem; }

  /* Nav */
  .terminal-nav { gap: 0.5rem; margin-bottom: 1rem; flex-wrap: wrap; }
  .terminal-nav button { font-size: 0.7rem; padding: 4px 6px; }

  /* Fleet */
  .fleet-layout { grid-template-columns: 1fr; gap: 1rem; height: auto; }
  .grid-section { overflow: visible; }
  .tactical-monitor-v8 { grid-template-columns: 1fr; }
  .rig-grid { grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 0.6rem; }
  .rig-tile { padding: 0.8rem; padding-top: 1.5rem; }
  .t-name-big { font-size: 1rem; }

  /* Command panel */
  .command-panel { width: 100%; right: -100%; box-shadow: -4px 0 0 rgba(74,54,96,0.3); }
  .command-panel.visible { right: 0; }

  /* Forge filter bar */
  .forge-filter-bar { flex-direction: column; gap: 0.5rem; }
  .forge-filter-bar .forge-cats { flex-wrap: wrap; }
  .forge-status-bar { flex-wrap: wrap; gap: 0.4rem; font-size: 0.55rem; }

  /* Inbox responsive */
  .inbox-summary-bar { flex-direction: column; gap: 0.4rem; align-items: flex-start; }
  .isb-right { flex-wrap: wrap; }

  /* History */
  .history-terminal { height: auto; }
  .history-row { grid-template-columns: 80px 1fr; gap: 4px; font-size: 0.7rem; }
  .history-row > span:nth-child(2) { display: none; }

  /* Menu modal */
  .menu-modal { width: 95vw; height: 85vh; max-width: 700px; max-height: 500px; }
  .mm-tabs button { font-size: 0.55rem; padding: 4px 8px; }

  /* Exchange */
  .exch-balances { flex-wrap: wrap; gap: 1rem; padding: 0.8rem; }
  .exch-input { width: 100%; }
  .exch-input-row, .exch-target-row { flex-wrap: wrap; gap: 0.5rem; }
  .exch-input-label { min-width: auto; }

  /* Market grid */
  .inv-grid { grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 0.6rem; }

  /* Staking */
  .stake-plans { grid-template-columns: repeat(2, 1fr); gap: 0.6rem; }
  .sc-icon { font-size: 1.8rem; }
  .sc-name { font-size: 0.7rem; letter-spacing: 1px; }
  .sc-ron { font-size: 1rem; }
  .sc-landwork { font-size: 1rem; }
  .stake-active-panel { padding: 1rem; }

  /* Forge */
  .view-forge { overflow: visible; flex: none; min-height: auto; }
  .forge-grid-layout { grid-template-columns: 1fr; height: auto; }
  .forge-sidebar { max-height: none; padding: 0.8rem; overflow: visible; height: auto; }
  .forge-main-grid { padding: 0.8rem; overflow: visible; height: auto; }
  .forge-action-panel { max-height: none; padding: 0.6rem; overflow: visible; height: auto; }
  .blueprint-grid-v2 { grid-template-columns: repeat(auto-fill, minmax(110px, 1fr)); }
  .collection-meter { width: 120px; }

  /* Research */
  .tree-container { grid-template-columns: 1fr; gap: 1rem; }
  .research-header { padding: 1rem; flex-direction: column; gap: 0.5rem; text-align: center; }

  /* Buy confirm */
  .buy-confirm-dialog { min-width: auto; width: 90vw; max-width: 400px; padding: 1rem; }

  /* Solo mining */
  .view-solo { padding: 0.5rem; height: auto; overflow: visible; }
}

@media (max-width: 480px) {
  /* Header compact */
  .h-inner { padding: 0.5rem; gap: 0.4rem; }
  .h-brand { gap: 6px; }
  .h-brand span:first-child { font-size: 0.8rem; }
  .h-metrics { gap: 0.6rem; }
  .m-box .l { font-size: 0.45rem; }
  .m-box .v { font-size: 0.75rem; }

  /* Body tighter */
  .body-inner { padding: 0.5rem; }

  /* Nav scroll */
  .terminal-nav { gap: 0.3rem; margin-bottom: 0.8rem; overflow-x: auto; flex-wrap: nowrap; justify-content: flex-start; padding-bottom: 4px; -webkit-overflow-scrolling: touch; }
  .terminal-nav button { font-size: 0.6rem; white-space: nowrap; flex-shrink: 0; }

  /* Cards */
  .monitor-card { padding: 0.8rem; gap: 0.6rem; }
  .m-tag { font-size: 0.55rem; padding: 2px 6px; }
  .m-stat .v { font-size: 0.9rem; }

  /* Rig tiles */
  .rig-grid { grid-template-columns: 1fr 1fr; gap: 0.5rem; }
  .rig-tile { padding: 0.6rem; padding-top: 1.2rem; }
  .t-name-big { font-size: 0.9rem; }
  .t-status-badge { font-size: 0.35rem; }

  /* Menu modal fullscreen */
  .menu-modal { width: 100vw; height: 100vh; max-width: none; max-height: none; border: none; }
  .mm-header { padding: 0.6rem 0.8rem; }
  .mm-tabs button { font-size: 0.5rem; padding: 3px 6px; letter-spacing: 0; }
  .view-inv, .view-market, .view-exchange { padding: 0.6rem; }

  /* Inventory list */
  .il-row { gap: 6px; padding: 6px 8px; }
  .il-icon { font-size: 0.85rem; width: 22px; }
  .il-name { font-size: 0.6rem; }
  .il-stat { font-size: 0.5rem; }
  .il-qty { font-size: 0.6rem; }
  .it-type { font-size: 0.4rem; padding: 1px 4px; }

  /* Market */
  .inv-grid { grid-template-columns: 1fr 1fr; gap: 0.5rem; }
  .inv-card { padding: 0.6rem; }
  .ic-name { font-size: 0.65rem; }
  .ic-stats { font-size: 0.5rem; gap: 0.4rem; }
  .mkt-tabs button { font-size: 0.5rem; padding: 3px 6px; }

  /* Exchange */
  .exch-balances { gap: 0.6rem; padding: 0.6rem; }
  .exch-val { font-size: 0.8rem; }
  .exch-rate-row { font-size: 0.65rem; }

  /* Staking */
  .view-staking { padding: 0.8rem; }
  .stake-header h2 { font-size: 0.9rem; letter-spacing: 1px; }
  .stake-plans { grid-template-columns: 1fr 1fr; gap: 0.5rem; }
  .stake-card { padding: 0.8rem 0.5rem; }
  .sc-icon { font-size: 1.5rem; }
  .sc-meta { flex-direction: column; gap: 2px; font-size: 0.55rem; }

  /* History */
  .history-row { grid-template-columns: 1fr; gap: 2px; font-size: 0.65rem; }
  .history-body { padding: 0.5rem; }

  /* Forge */
  .forge-sidebar { padding: 0.5rem; max-height: none; }
  .forge-main-grid { padding: 0.5rem; }
  .forge-action-panel { padding: 0.5rem; }
  .blueprint-grid-v2 { grid-template-columns: repeat(auto-fill, minmax(90px, 1fr)); gap: 0.4rem; }
  .collection-meter { width: 100px; }

  /* Research */
  .research-header h1 { font-size: 1rem; }
  .node-icon { width: 32px; height: 32px; }

  /* Panel stats */
  .panel-stats-inline { grid-template-columns: 1fr; }
}


/* FORGE REDESIGN 2.0 (COMFORT & PERFORMANCE) */
.view-forge { flex: 1; min-height: 0; position: relative; overflow: hidden; }

.forge-grid-layout { display: grid; grid-template-columns: 260px 1fr 340px; height: 100%; gap: 2px; background: #c4a0e8; }

.forge-sidebar { background: #231d35; padding: 1.5rem; display: flex; flex-direction: column; gap: 1.5rem; border-right: 2px solid #4a3660; }
.forge-search-box .f-search-input {
  width: 100%; background: #1f1833; border: 2px inset #4a3660; padding: 10px; color: #f0e4ff;
  font-family: 'Pixelify Sans', 'Nunito', sans-serif; font-size: 0.7rem; outline: none;
}
.forge-cats { display: flex; flex-direction: column; gap: 4px; }
.forge-cats button {
  text-align: left; padding: 8px 12px; background: transparent; border: none; color: #b8a0d0;
  font-family: inherit; font-size: 0.65rem; font-weight: 800; cursor: pointer; transition: 0.2s;
}
.forge-cats button:hover { color: #1a1528; background: #ffe566; }
.forge-cats button.active { color: #fff; background: #c4a0e8; border-left: 3px solid #ffe566; }

/* Forge Header Group (joins filter + status) */
.forge-header-group {
  display: flex; flex-direction: column;
}

/* Forge Filter Bar (inside fleet view) */
.forge-filter-bar {
  display: flex; align-items: center; gap: 1rem;
  padding: 0.6rem 0.8rem; background: #1f1833;
  border: 2px solid #4a3660; border-radius: 12px;
}
.forge-filter-bar .forge-cats {
  flex-direction: row; gap: 0; flex-shrink: 0;
}
.forge-filter-bar .forge-cats button {
  padding: 8px 18px; font-size: 0.75rem; border: 2px solid #4a3660; border-left: none;
  text-align: center; font-family: 'Nunito', sans-serif; color: #8a70a8;
  background: #1f1833; transition: all 0.2s;
}
.forge-filter-bar .forge-cats button:first-child { border-left: 2px solid #4a3660; border-radius: 8px 0 0 8px; }
.forge-filter-bar .forge-cats button:last-child { border-radius: 0 8px 8px 0; }
.forge-filter-bar .forge-cats button.active {
  background: #c4a0e8; color: #fff;
}
.forge-filter-bar .forge-cats button:hover:not(.active) { background: #ffe97a; color: #4a3a1c; }
.forge-filter-bar .f-search-input {
  flex: 1; background: #1f1833; border: 2px solid #4a3660; padding: 6px 12px; color: #f0e4ff;
  font-family: 'Nunito', sans-serif; font-size: 0.65rem; outline: none; border-radius: 8px;
  transition: border-color 0.2s;
}
.forge-filter-bar .f-search-input:focus { border-color: #b088d0; }

/* Forge Status Bar (mastery + energy compact) */
.forge-status-bar {
  display: flex; align-items: center; gap: 1rem;
  padding: 0.7rem 1rem; background: #231d35;
  border: 2px solid #4a3660; border-top: 1px solid #3a2d50;
  font-size: 0.8rem; font-weight: 700;
  margin-top: 0; border-radius: 0 0 12px 12px;
}
.fsb-rank { color: #d4a017; letter-spacing: 1px; font-family: 'Nunito', sans-serif; font-weight: 700; font-size: 0.8rem; }
.fsb-level { color: #b8a0d0; font-family: 'Nunito', sans-serif; font-size: 0.8rem; }
.fsb-xp { flex: 0 0 100px; height: 10px; background: #2d2545; overflow: hidden; border: 2px solid #4a3660; border-radius: 5px; }
.fsb-xp-fill { height: 100%; background: #ffd740; border-radius: 3px; }
.fsb-xp-text { color: #b8a0d0; font-size: 0.85rem; font-family: 'Roboto', 'Nunito', sans-serif; }
.fsb-energy-label { color: #4a8a6a; margin-left: auto; font-family: 'Nunito', sans-serif; font-size: 0.8rem; }
.fsb-energy { flex: 0 0 80px; height: 10px; background: #e8f0e8; overflow: hidden; border: 2px solid #a0c8a8; border-radius: 5px; }
.fsb-energy-fill { height: 100%; background: #7cc490; border-radius: 3px; }
.fsb-energy-val { color: #4a8a6a; font-size: 0.9rem; font-family: 'Roboto', 'Nunito', sans-serif; }

/* Forge grid scroll container */
.forge-grid-scroll {
  padding: 4px;
}
.forge-grid-scroll::-webkit-scrollbar { width: 8px; }
.forge-grid-scroll::-webkit-scrollbar-track { background: #231d35; border-radius: 4px; }
.forge-grid-scroll::-webkit-scrollbar-thumb { background: #c4a0e8; border-radius: 4px; border: 1px solid #3a2d50; }
.forge-grid-scroll::-webkit-scrollbar-thumb:hover { background: #b088d0; }

/* Forge load more indicator */
.forge-load-more {
  display: flex; flex-direction: column; align-items: center; gap: 4px;
  padding: 1.5rem 0; color: #8a70a8;
}
.flm-dots {
  font-size: 1.5rem; letter-spacing: 4px; color: #c4a0e8;
  animation: dots-pulse 1.5s ease-in-out infinite;
}
@keyframes dots-pulse { 0%,100% { opacity: 0.3; } 50% { opacity: 1; } }
.flm-text {
  font-size: 0.6rem; font-weight: 700; letter-spacing: 1px;
  font-family: 'Nunito', sans-serif;
}

.forge-empty {
  display: flex; align-items: center; justify-content: center;
  padding: 3rem 1rem; color: #b0a0c0; font-size: 0.7rem; font-weight: 700;
  font-family: 'Nunito', sans-serif;
}

/* ── INBOX ── */
.fc-badge {
  display: inline-flex; align-items: center; justify-content: center;
  min-width: 16px; height: 16px; padding: 0 4px;
  background: #ef4444; color: #fff; font-size: 0.55rem; font-weight: 800;
  border-radius: 8px; margin-left: 4px; line-height: 1;
}

/* Inbox container */
.inbox-container {
  display: flex; flex-direction: column; flex: 1; min-height: 0;
  border: 2px solid #4a3660; border-radius: 14px; overflow: hidden;
  background: #1f1833;
}
.inbox-header {
  display: flex; align-items: center; justify-content: space-between; gap: 1rem;
  padding: 0.8rem 1rem; background: #231d35;
  border-bottom: 1px solid #3a2d50; flex-shrink: 0;
}
.isb-left { display: flex; align-items: center; gap: 0.6rem; color: #5c4578; }
.isb-label { color: #b8a0d0; font-weight: 700; letter-spacing: 1px; font-family: 'Nunito', sans-serif; font-size: 0.8rem; }
.isb-count {
  color: #fff; font-weight: 800; font-family: 'Nunito', sans-serif; font-size: 0.9rem;
  background: #c4a0e8; padding: 2px 10px; border-radius: 12px;
}
.isb-right { display: flex; align-items: center; gap: 0.8rem; }
.isb-total { color: #d4a017; font-weight: 700; display: flex; align-items: center; gap: 4px; font-family: 'Roboto', 'Nunito', sans-serif; font-size: 1rem; }
.isb-claim-all-hold {
  position: relative; overflow: hidden;
  padding: 8px 18px; background: linear-gradient(135deg, #ffe97a, #ffd740); border: none;
  color: #4a3a1c; font-size: 0.75rem; font-weight: 700; cursor: pointer;
  user-select: none; -webkit-user-select: none; border-radius: 10px;
  font-family: 'Nunito', sans-serif;
  box-shadow: 0 3px 0 #c8a020;
  transition: all 0.2s;
}
.isb-claim-all-hold:hover:not(:disabled) { transform: translateY(-1px); box-shadow: 0 4px 0 #c8a020; }
.isb-claim-all-hold:disabled { opacity: 0.4; cursor: not-allowed; }
.isb-claim-all-hold .hold-fill-bar {
  position: absolute; left: 0; top: 0; bottom: 0;
  background: rgba(245,158,11,0.25); transition: width 0.05s linear;
  pointer-events: none;
}
.isb-claim-all-hold .hold-label {
  position: relative; z-index: 1;
  display: flex; align-items: center; gap: 4px; letter-spacing: 0.5px;
}

.inbox-grid-scroll {
  flex: 1; overflow-y: auto; min-height: 0;
}
.inbox-grid-scroll::-webkit-scrollbar { width: 8px; }
.inbox-grid-scroll::-webkit-scrollbar-track { background: #231d35; border-radius: 4px; }
.inbox-grid-scroll::-webkit-scrollbar-thumb { background: #c4a0e8; border-radius: 4px; }

.inbox-loading, .inbox-empty {
  display: flex; flex-direction: column; align-items: center; justify-content: center;
  gap: 0.6rem; padding: 3rem 1rem; color: #8a70a8; font-size: 0.85rem; font-weight: 700;
  font-family: 'Nunito', sans-serif;
}
.inbox-loading .spin { animation: spin 1s linear infinite; }
@keyframes spin { to { transform: rotate(360deg); } }

.inbox-block-list { display: flex; flex-direction: column; gap: 0; }

.inbox-block-card {
  display: flex; align-items: center; gap: 0.8rem;
  padding: 0.7rem 1rem; background: #1f1833;
  border-bottom: 1px solid #231d35;
  cursor: pointer; transition: all 0.15s;
}
.inbox-block-card:last-child { border-bottom: none; }
.inbox-block-card:hover { background: #231d35; }
.inbox-block-card.selected { background: #2d2545; box-shadow: inset 3px 0 0 #c4a0e8; }
.inbox-block-card.premium { box-shadow: inset 3px 0 0 #ffd740; }
.inbox-block-card.premium.selected { box-shadow: inset 3px 0 0 #d4a017; }

.ibc-icon {
  width: 36px; height: 36px; display: flex; align-items: center; justify-content: center;
  background: #231d35; border-radius: 10px; color: #5c4578; position: relative; flex-shrink: 0;
}
.ibc-crown { position: absolute; top: -3px; right: -3px; color: #d4a017; }
.ibc-info { display: flex; flex-direction: column; gap: 1px; flex: 1; min-width: 0; }
.ibc-height { font-size: 0.85rem; font-weight: 700; color: #f0e4ff; font-family: 'Roboto', 'Nunito', sans-serif; }
.ibc-date { font-size: 0.7rem; color: #8a70a8; }

.ibc-reward { text-align: right; flex-shrink: 0; }
.ibc-amount { font-size: 1rem; font-weight: 700; color: #d4a017; font-family: 'Roboto', 'Nunito', sans-serif; display: block; }
.ibc-currency { font-size: 0.6rem; color: #8a70a8; display: block; font-family: 'Nunito', sans-serif; }

.ibc-materials {
  display: flex; align-items: center; gap: 3px; color: #7cc490; font-size: 0.75rem; font-weight: 700;
  background: rgba(124,196,144,0.1); padding: 3px 8px; border-radius: 8px; flex-shrink: 0;
}

.inbox-load-more {
  width: 100%; padding: 0.7rem;
  background: none; border: none; border-top: 1px solid #231d35; color: #8a70a8;
  font-size: 0.75rem; font-weight: 700; cursor: pointer; letter-spacing: 1px;
  font-family: 'Nunito', sans-serif; transition: all 0.2s;
}
.inbox-load-more:hover { background: #231d35; color: #b8a0d0; }
.inbox-load-more:disabled { opacity: 0.4; cursor: not-allowed; }

/* Inbox detail panel */
.inbox-detail-panel { overflow-y: auto; padding: 1rem; padding-top: 40px; }
.inbox-claim-section { text-align: center; padding-top: 0.5rem; }
.inbox-claim-btn { width: 100%; display: flex; align-items: center; justify-content: center; gap: 8px; font-size: 0.9rem; }
.inbox-claim-btn:disabled { opacity: 0.4; cursor: not-allowed; }

/* Claim Captcha Modal */
.claim-modal-overlay {
  position: fixed; inset: 0; z-index: 9999;
  background: rgba(0,0,0,0.7); backdrop-filter: blur(4px);
  display: flex; align-items: center; justify-content: center;
}
.claim-modal {
  background: #1f1833; border: 2px solid #5c4578;
  width: 360px; max-width: 90vw;
  box-shadow: 4px 4px 0 rgba(74,54,96,0.3); border-radius: 14px; overflow: hidden;
}
.cm-header {
  display: flex; align-items: center; gap: 0.5rem;
  padding: 0.8rem 1rem; border-bottom: 2px solid #4a3660;
  font-size: 0.75rem; font-weight: 800; letter-spacing: 1px;
  background: linear-gradient(180deg, #3a2d50, #2d2545); color: #f0e4ff;
}
.cm-close {
  margin-left: auto; background: #ff6b6b; border: 2px outset #cc4444; color: #fff;
  cursor: pointer; font-size: 1rem; padding: 2px 6px;
}
.cm-close:hover { background: #cc4444; border-style: inset; }
.cm-body { padding: 1.2rem; text-align: center; }
.cm-info { font-size: 0.7rem; color: #b8a0d0; margin-bottom: 1rem; }
.cm-captcha { display: flex; justify-content: center; margin-bottom: 1rem; }
.cm-claim-btn {
  width: 100%; padding: 0.7rem; background: #ffe566; border: 2px outset #d4a017;
  color: #1a1528; font-size: 0.7rem; font-weight: 800; cursor: pointer;
  display: flex; align-items: center; justify-content: center; gap: 6px;
  letter-spacing: 0.5px; border-radius: 8px;
}
.cm-claim-btn:hover:not(:disabled) { background: #ffd700; border-style: inset; }
.cm-claim-btn:disabled { opacity: 0.4; cursor: not-allowed; }
.cm-claim-btn:not(:disabled) span:last-child { color: #22c55e; }
.inbox-claim-cost { margin-top: 0.4rem; }
.inbox-claim-cost small { color: #8a70a8; font-size: 0.7rem; }

/* ── INVENTORY in fleet ── */
.inv-badge { background: #8b5cf6; }
.inv-card { cursor: pointer; }
.inv-badge-cool { background: #06b6d4; }
.inv-badge-mod { background: #a78bfa; }
.inv-badge-card { background: #22c55e; }
.inv-badge-boost { background: #f59e0b; }
.inv-badge-mat { background: #8b5cf6; }
.inv-badge-xp { background: #f59e0b; }

.inv-detail-panel { overflow-y: auto; padding: 1rem; padding-top: 40px; }
.inv-type-badge { background: #3f3f5c; font-size: 0.55rem; }
.inv-hint {
  font-size: 0.6rem; color: #b8a0d0; padding: 0.4rem 0.6rem; margin-top: 0.5rem;
  border: 2px dashed #4a3660; text-align: center; font-style: italic;
}
.inv-actions { display: flex; flex-direction: column; gap: 0.4rem; }
.inv-action-btn {
  width: 100%; padding: 0.55rem 0.8rem; background: #231d35; border: 2px solid #4a3660;
  color: #b8a0d0; font-size: 0.65rem; font-weight: 800; cursor: pointer;
  display: flex; align-items: center; justify-content: center; gap: 6px; border-radius: 10px;
  transition: all 0.2s; letter-spacing: 1px;
}
.inv-action-btn:hover { background: #2d2545; border-color: #5c4578; color: #f0e4ff; }
.inv-action-btn.danger { border-color: rgba(232,124,138,0.3); color: #e87c8a; background: rgba(232,124,138,0.05); }
.inv-action-btn.danger:hover { background: rgba(232,124,138,0.12); border-color: #e87c8a; }

.inv-confirm-actions { display: flex; gap: 0.5rem; margin-top: 0.8rem; }
.inv-confirm-actions .inv-action-btn { flex: 1; }
.inv-confirm-actions .cm-claim-btn { flex: 1; }

.inv-select-row {
  display: flex; align-items: center; gap: 0.6rem;
  padding: 0.6rem 0.8rem; border: 2px solid #4a3660; cursor: pointer;
  font-size: 0.7rem; font-weight: 700; color: #f0e4ff;
  margin-bottom: 4px; border-radius: 8px;
}
.inv-select-row:hover { border-color: #5c4578; background: #231d35; }
.inv-select-name { flex: 1; }
.inv-select-stat { color: #71717a; font-size: 0.6rem; }
.inv-select-stat.low { color: #ef4444; }

/* Forge detail in command panel */
.forge-detail-panel { overflow-y: auto; padding: 1rem; padding-top: 40px; gap: 0.6rem; }

/* Forge detail - identity row */
.fd-identity {
  display: flex; align-items: center; gap: 0.75rem; margin-bottom: 0.2rem;
}
.fd-identity .detail-icon {
  margin: 0; flex-shrink: 0;
}
.fd-identity-info { display: flex; flex-direction: column; gap: 2px; min-width: 0; }
.fd-identity .detail-name { text-align: left; font-size: 1.15rem; }
.fd-identity .detail-cat { text-align: left; margin-bottom: 0; font-size: 0.7rem; }

/* Forge detail - card sections */
.fd-card {
  background: #231d35; border: 2px solid #3a2d50; border-radius: 10px;
  padding: 0.7rem 0.85rem; margin-top: 0.2rem;
}
.fd-card.fd-card-warn {
  background: rgba(212,160,23,0.06); border-color: rgba(212,160,23,0.2);
}
.fd-card-title {
  font-size: 0.7rem; font-weight: 700; color: #8a70a8; letter-spacing: 1.5px;
  font-family: 'Nunito', sans-serif; margin-bottom: 0.5rem;
  padding-bottom: 0.35rem; border-bottom: 1px solid #3a2d50;
}
.fd-card-warn .fd-card-title { color: #c08060; border-bottom-color: #f0d8c0; }

/* Forge detail - grid layout */
.fd-grid {
  display: grid; grid-template-columns: 1fr 1fr; gap: 0.5rem;
}
.fd-grid-3 {
  grid-template-columns: 1fr 1fr 1fr;
}
.fd-cell {
  display: flex; flex-direction: column; gap: 2px;
}
.fd-label {
  font-size: 0.7rem; font-weight: 700; color: #8a70a8;
  display: flex; align-items: center; gap: 4px;
}
.fd-value {
  font-size: 1.1rem; font-weight: 700; color: #f0e4ff;
  font-family: 'Roboto', 'Nunito', sans-serif;
}
.fd-unit {
  font-size: 0.6rem; color: #8a70a8; font-weight: 700; margin-top: -1px;
}

/* Stat main display */
.fd-stat-main {
  display: flex; flex-direction: column; align-items: center; gap: 2px; padding: 0.3rem 0;
}
.fd-stat-value {
  font-size: 1.4rem; font-weight: 700; font-family: 'Roboto', 'Nunito', sans-serif;
}
.fd-stat-abi {
  font-size: 0.75rem; color: #8a70a8; font-weight: 700;
}

.forge-sidebar { overflow-y: auto; }
.forge-sidebar::-webkit-scrollbar { width: 8px; }
.forge-sidebar::-webkit-scrollbar-track { background: #231d35; border-radius: 4px; }
.forge-sidebar::-webkit-scrollbar-thumb { background: #c4a0e8; border-radius: 4px; }

.forge-inv-mini { flex: 1; display: flex; flex-direction: column; gap: 6px; }
.mini-item {
  display: flex; align-items: center; gap: 10px; padding: 8px; font-size: 0.65rem;
  color: #b8a0d0; border: 1px solid transparent; cursor: pointer;
}
.mini-item:hover { color: #1a1528; background: #ffe566; }
.mini-item.selected { color: #1a1528; background: #ffe566; border-color: #d4a017; }

.forge-main-grid { background: #231d35; padding: 2rem; overflow-y: auto; }
.grid-header { display: flex; justify-content: space-between; align-items: flex-end; margin-bottom: 2rem; }
.gh-count { font-size: 0.6rem; color: #b8a0d0; font-weight: 800; }

.blueprint-grid-v2 { display: grid; grid-template-columns: repeat(auto-fill, minmax(155px, 1fr)); gap: 0.8rem; }
.bp-card-v2 {
  background: #1f1833; border: 2px solid #4a3660; padding: 0; display: flex; flex-direction: column;
  cursor: pointer; transition: all 0.2s; position: relative; text-align: center;
  box-shadow: 2px 2px 0 #3a2d50; border-radius: 14px; overflow: hidden;
}
.bp-card-v2:hover { border-color: #b088d0; box-shadow: 3px 3px 0 rgba(74,54,96,0.3); }
.bp-card-v2.can_forge { border-color: #a8d0b8; }
.bp-card-v2.selected { border-color: #ffd740; background: rgba(255,229,102,0.06); box-shadow: 3px 3px 0 rgba(212,160,23,0.3); }
.bp-card-v2.locked { opacity: 0.4; filter: grayscale(0.8); pointer-events: none; }

/* Card head: icon + tier */
.bpc-head {
  display: flex; align-items: center; justify-content: center;
  padding: 0.7rem 0.5rem 0.4rem; position: relative;
  background: #231d35;
}
.bpc-tier-badge {
  position: absolute; top: 8px; right: 8px; font-size: 0.6rem; font-weight: 700;
  color: #fff; padding: 2px 10px; letter-spacing: 1px;
  border-radius: 12px; font-family: 'Nunito', sans-serif;
  box-shadow: 0 1px 2px rgba(0,0,0,0.12);
}
.bpc-icon-center {
  width: 44px; height: 44px;
  display: flex; align-items: center; justify-content: center;
  background: #1f1833; border: 2px solid #4a3660; border-radius: 12px;
  color: #b8a0d0;
}

/* Card body */
.bpc-name {
  font-size: 0.8rem; font-weight: 700; color: #f0e4ff; line-height: 1.2;
  font-family: 'Nunito', sans-serif; padding: 0 0.5rem; margin-top: 0.3rem;
}
.bpc-gives {
  font-size: 0.55rem; font-weight: 700; letter-spacing: 1px; padding: 2px 10px;
  border: none; margin: 0.2rem auto 0; border-radius: 10px;
  font-family: 'Nunito', sans-serif;
}
.bpc-gives.gives-HASHRATE { color: #ffe566; background: rgba(255,229,102,0.1); }
.bpc-gives.gives-COOLING { color: #c4a0e8; background: #2d2545; }
.bpc-gives.gives-ENERGY { color: #7cc490; background: rgba(124,196,144,0.1); }
.bpc-gives.gives-DURABILITY { color: #8a70a8; background: rgba(138,112,168,0.15); }
.bpc-gives.gives-BOOSTER { color: #d4a017; background: rgba(212,160,23,0.1); }
.bpc-gives.gives-NONE { color: #8a70a8; background: rgba(138,112,168,0.1); }
.bpc-stat {
  font-size: 0.75rem; font-weight: 800; color: #f0e4ff; padding: 0 0.5rem;
  margin-top: 0.1rem;
}

/* Card footer: time + cost */
.bpc-meta {
  display: flex; justify-content: space-between; width: 100%;
  font-size: 0.6rem; color: #8a70a8; font-weight: 700;
  padding: 6px 10px; margin-top: auto;
  background: #231d35; border-top: 1px solid #3a2d50;
  font-family: 'Nunito', sans-serif;
}
.bpc-time { color: #8a70a8; display: flex; align-items: center; gap: 3px; }
.bpc-cost { color: #d4a017; font-weight: 800; }

/* Misc card elements (used in detail) */
.bpc-coolhp { font-size: 0.65rem; font-weight: 800; color: #5c4578; letter-spacing: 0.5px; padding: 0 0.5rem; }
.bpc-consumes { display: flex; gap: 6px; font-size: 0.6rem; font-weight: 700; color: #cc5566; padding: 0 0.5rem; }
.consume-val { color: #cc5566 !important; }
.coolhp-info {
  font-size: 0.65rem; color: #8a70a8; line-height: 1.4; text-align: center;
  padding: 0.3rem 0.5rem; border: 2px dashed #4a3660; margin-top: 0.2rem;
  border-radius: 8px; background: #231d35;
}
.bpc-inputs { display: flex; flex-direction: column; gap: 2px; width: 100%; margin-top: 0.2rem; }
.bpc-mat { display: flex; align-items: center; gap: 4px; font-size: 0.6rem; font-family: 'Nunito', sans-serif; color: #8a70a8; }
.bpc-mat.ok { color: #4a8a6a; }
.bpc-mat .mat-icon { font-size: 0.65rem; }
.bpc-mat .mat-name { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; flex: 1; }
.bpc-mat .mat-qty { color: #f0e4ff; font-weight: 900; font-size: 0.65rem; }
.bpc-nrg { color: #d4a017; font-weight: 800; }
.nrg-val { color: #d4a017; }
.bpc-deliver.active { border-color: #a8d0b8; color: #4a8a6a; }
.bpc-deliver.active:hover { background: rgba(168,208,176,0.15); }
.bpc-footer { display: flex; justify-content: space-between; border-top: 1px solid #3a2d50; padding-top: 4px; align-items: center; margin-top: auto; }
.bpc-abi { font-size: 0.5rem; color: #8a70a8; overflow: hidden; white-space: nowrap; text-overflow: ellipsis; max-width: 80px; }
.bpc-power { font-size: 0.55rem; font-weight: 800; color: #b8a0d0; }


.forge-action-panel { background: #1f1833; padding: 0.75rem; overflow-y: auto; border-left: 2px solid #4a3660; }
.forge-action-panel::-webkit-scrollbar { width: 8px; }
.forge-action-panel::-webkit-scrollbar-track { background: #231d35; border-radius: 4px; }
.forge-action-panel::-webkit-scrollbar-thumb { background: #c4a0e8; border-radius: 4px; }
.action-panel-inner { display: flex; flex-direction: column; min-height: 100%; gap: 0.4rem; position: relative; }

.view-solo { height: 100%; overflow-y: auto; }
.view-solo::-webkit-scrollbar { width: 8px; }
.view-solo::-webkit-scrollbar-track { background: #231d35; border-radius: 4px; }
.view-solo::-webkit-scrollbar-thumb { background: #c4a0e8; border-radius: 4px; }

/* Detail panel - idle state */
.detail-idle { flex: 1; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 0.5rem; }
.di-icon { font-size: 2rem; opacity: 0.4; }
.di-text { font-size: 0.7rem; font-weight: 900; color: #b8a0d0; letter-spacing: 2px; }
.di-sub { font-size: 0.45rem; color: #c4a0e8; }

/* Detail panel - recipe selected */
.detail-close {
  background: rgba(232,124,138,0.08); border: 2px solid rgba(232,124,138,0.4);
  color: #dd3355; font-size: 0.8rem; cursor: pointer; padding: 4px 8px; border-radius: 6px;
  transition: all 0.2s; font-family: 'Nunito', sans-serif;
}
.detail-header-right { display: flex; align-items: center; gap: 8px; }
.detail-close:hover { background: linear-gradient(135deg, #ff8888, #ee4455); color: #fff; border-color: #cc2233; }

.detail-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 4px; }
.detail-tier {
  font-size: 0.85rem; font-weight: 700; color: #8a70a8;
  font-family: 'Nunito', sans-serif; letter-spacing: 1px;
}

.detail-icon {
  font-size: 2.5rem; text-align: center; margin: 0.5rem 0;
  width: 56px; height: 56px; margin-left: auto; margin-right: auto;
  display: flex; align-items: center; justify-content: center;
  background: linear-gradient(135deg, #231d35, #2d2545); border: 2px solid #4a3660;
  border-radius: 14px; box-shadow: 0 2px 4px rgba(138,96,176,0.1);
}
.detail-name {
  font-size: 1.1rem; font-weight: 800; text-align: center; letter-spacing: 1px;
  color: #f0e4ff; font-family: 'Nunito', sans-serif; margin-top: 4px;
}
.detail-cat {
  font-size: 0.55rem; font-weight: 700; color: #8a70a8; text-align: center;
  letter-spacing: 2px; margin-bottom: 0.4rem; font-family: 'Nunito', sans-serif;
}

.detail-usage { text-align: center; }
.usage-badge {
  font-size: 0.7rem; font-weight: 700; padding: 5px 14px; border: none; letter-spacing: 1px;
  display: inline-block; border-radius: 20px; font-family: 'Nunito', sans-serif;
}
.usage-RIG_INSTALL { background: rgba(138,96,176,0.12); color: #5c4578; }
.usage-ENERGY { background: rgba(212,160,23,0.12); color: #b8860b; }
.usage-COMBINE { background: rgba(176,38,255,0.1); color: #9040d0; }
.usage-BOOSTER { background: rgba(255,102,0,0.1); color: #cc5500; }

.detail-tags { display: flex; gap: 6px; justify-content: center; flex-wrap: wrap; margin: 4px 0; }
.gives-badge {
  font-size: 0.7rem; font-weight: 700; padding: 5px 14px; border: none; letter-spacing: 1px;
  border-radius: 20px; font-family: 'Nunito', sans-serif;
}
.gives-badge.gives-HASHRATE { background: rgba(212,160,23,0.12); color: #b8860b; }
.gives-badge.gives-COOLING { background: rgba(138,96,176,0.12); color: #5c4578; }
.gives-badge.gives-ENERGY { background: rgba(42,138,42,0.1); color: #4a8a6a; }
.gives-badge.gives-DURABILITY { background: rgba(120,120,120,0.1); color: #777; }
.gives-badge.gives-BOOSTER { background: rgba(255,102,0,0.1); color: #cc5500; }
.gives-badge.gives-NONE { background: rgba(120,120,120,0.08); color: #999; }
.detail-desc {
  font-size: 0.85rem; color: #b8a0d0; line-height: 1.5; text-align: left;
  padding: 0.5rem 0.6rem; margin: 0;
  background: #231d35; border-radius: 8px; border: 1px solid #231d35;
}
.cost-val { color: #d4a017 !important; }

.detail-stats { display: flex; flex-direction: column; gap: 3px; }
.ds-row {
  display: flex; justify-content: space-between; font-size: 0.75rem; font-weight: 700;
  color: #8a70a8; padding: 5px 8px; border-bottom: none;
  background: #1f1833;
  border: 1px solid #3a2d50; border-radius: 6px;
}
.ds-val { color: #f0e4ff; text-align: right; max-width: 60%; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-weight: 800; }

.detail-mats { display: flex; flex-direction: column; gap: 5px; }
.dm-row {
  display: flex; align-items: center; gap: 8px; font-size: 0.8rem; font-weight: 700;
  color: #b8a0d0; padding: 6px 10px;
  background: #1f1833; border: 1px solid #3a2d50; border-radius: 8px;
  transition: all 0.2s;
}
.dm-row.ok { border-color: rgba(124,196,144,0.25); color: #f0e4ff; background: rgba(124,196,144,0.08); }
.dm-icon { font-size: 0.85rem; color: #b088d0; }
.dm-name { flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-family: 'Nunito', sans-serif; font-size: 0.8rem; }
.dm-qty { color: #f0e4ff; font-weight: 700; font-size: 0.85rem; font-family: 'Roboto', 'Nunito', sans-serif; }
.dm-status { font-size: 1rem; }
.dm-row.ok .dm-icon { color: #6a9a80; }
.dm-row.ok .dm-status { color: #4a8a6a; }
.dm-row:not(.ok) .dm-status { color: #cc5566; }

.forge-trigger {
  width: 100%; padding: 0.85rem; color: #4a3a1c; border: none;
  background: linear-gradient(135deg, #ffe97a, #ffd740);
  font-family: 'Nunito', sans-serif; font-weight: 700; font-size: 0.95rem;
  cursor: pointer; transition: all 0.2s; letter-spacing: 2px; margin-top: auto; border-radius: 10px;
  box-shadow: 0 3px 0 #c8a020, 0 3px 8px rgba(200,160,32,0.2);
}
.forge-trigger:disabled {
  background: linear-gradient(180deg, #231d35, #2d2545); color: #b0a0c0;
  cursor: not-allowed; box-shadow: none;
}
.forge-trigger:hover:not(:disabled) { transform: translateY(-1px); box-shadow: 0 4px 0 #c8a020, 0 4px 12px rgba(200,160,32,0.25); }
.forge-trigger:active:not(:disabled) { transform: translateY(2px); box-shadow: 0 1px 0 #c8a020; }

/* Hold button */
.hold-btn {
  position: relative; overflow: hidden; width: 100%; padding: 0.65rem;
  background: rgba(196,160,232,0.08); color: #c4a0e8; border: 2px solid #5c4578;
  font-family: inherit; font-weight: 900; font-size: 0.65rem; cursor: pointer;
  letter-spacing: 2px; user-select: none; -webkit-user-select: none;
  display: flex; align-items: center; justify-content: center; border-radius: 10px;
  transition: border-color 0.2s;
}
.hold-btn:disabled { opacity: 0.4; cursor: not-allowed; }
.hold-btn:active:not(:disabled) { border-color: #7cc490; }
.hold-fill {
  position: absolute; top: 0; left: 0; height: 100%;
  background: linear-gradient(90deg, rgba(124,196,144,0.15), rgba(124,196,144,0.3));
  pointer-events: none; z-index: 0; transition: none;
}
.hold-label {
  position: relative; z-index: 1;
  display: flex; align-items: center; gap: 6px;
}

/* Forge progress bar */
.forge-progress-bar { display: flex; flex-direction: column; gap: 4px; padding: 0.5rem 0; }
.fpb-label { font-size: 0.7rem; font-weight: 800; color: #d4a017; letter-spacing: 1px; animation: pulse-ring 1s infinite; font-family: 'Nunito', sans-serif; }
.fpb-track { height: 8px; background: #2d2545; overflow: hidden; border: 2px inset #4a3660; border-radius: 4px; }
.fpb-fill { height: 100%; background: linear-gradient(90deg, #ffe566, #ffd700); transition: width 0.4s ease; box-shadow: none; }
.fpb-pct { font-size: 0.7rem; font-weight: 900; color: #f0e4ff; text-align: right; letter-spacing: 1px; font-family: 'Nunito', sans-serif; }

/* Forge progress on blueprint card */
.bpc-forging { display: flex; align-items: center; gap: 4px; width: 100%; padding: 4px 10px 6px; background: #231d35; }
.bpc-forging-track { flex: 1; height: 6px; background: #2d2545; overflow: hidden; border-radius: 3px; border: 1px solid #4a3660; }
.bpc-forging-fill { height: 100%; background: #ffd740; transition: width 0.4s ease; border-radius: 2px; }
.bpc-forging-pct { font-size: 0.55rem; font-weight: 800; color: #d4a017; white-space: nowrap; min-width: 22px; text-align: right; font-family: 'Nunito', sans-serif; }
.bp-card-v2.forging { border-color: #ffd740; box-shadow: 3px 3px 0 rgba(212,160,23,0.3); animation: forging-pulse 2s infinite; }
@keyframes forging-pulse { 0%,100% { box-shadow: 0 0 8px rgba(245,158,11,0.1); } 50% { box-shadow: 0 0 16px rgba(245,158,11,0.25); } }

@keyframes pulse-ring { 0% { opacity: 0.5; } 50% { opacity: 1; } 100% { opacity: 0.5; } }
.animate-pulse { animation: pulse-ring 2s infinite; }

/* RARITY SYSTEM */
.blueprint-grid-v2 { padding-bottom: 3rem; }
.bp-card-v2.rarity-common .bpc-head { background: rgba(124,196,144,0.08); }
.bp-card-v2.rarity-rare { border-color: #4a6080; }
.bp-card-v2.rarity-rare .bpc-head { background: rgba(100,160,210,0.08); }
.bp-card-v2.rarity-rare:hover { border-color: #6090b0; }
.bp-card-v2.rarity-epic { border-color: #5c4578; }
.bp-card-v2.rarity-epic .bpc-head { background: rgba(160,112,208,0.1); }
.bp-card-v2.rarity-epic:hover { border-color: #7b5ea7; }
.bp-card-v2.rarity-legendary { border-color: #8a7030; box-shadow: 3px 3px 0 rgba(212,160,23,0.2); }
.bp-card-v2.rarity-legendary .bpc-head { background: rgba(255,229,102,0.08); }
.bp-card-v2.rarity-legendary:hover { border-color: #d4a017; }

.badge {
  font-size: 0.7rem; padding: 4px 14px; font-weight: 700; color: #fff;
  border-radius: 20px; letter-spacing: 1.5px; font-family: 'Nunito', sans-serif;
  box-shadow: 0 1px 3px rgba(0,0,0,0.15);
}

/* COLLECTION METER */
.collection-meter { width: 180px; }
.cm-meta { display: flex; justify-content: space-between; font-size: 0.5rem; font-weight: 800; margin-bottom: 4px; }
.cm-bar { height: 3px; background: #1e1f36; border-radius: 10px; overflow: hidden; }
.cm-bar .fill { height: 100%; background: #00ff88; box-shadow: none; }

/* FORGE LOGS */
.forge-terminal {
  background: linear-gradient(165deg, #231d35, #2d2545); padding: 8px 10px; height: 50px;
  font-family: 'Nunito', sans-serif; font-size: 0.6rem; color: #8a70a8;
  overflow: hidden; border: 2px solid #4a3660; border-left: 4px solid #ffe97a;
  border-radius: 8px;
}
.log-entry { margin-bottom: 2px; }

/* BIG PREVIEW */
.pa-big-stat { margin: 1.5rem 0; display: flex; justify-content: center; }
.stat-circle {
  width: 100px; height: 100px; border: 3px solid #4a3660; border-radius: 50%;
  display: flex; flex-direction: column; align-items: center; justify-content: center;
  position: relative; background: #1f1833;
}
.stat-circle::after { content: ''; position: absolute; inset: -5px; border: 2px dashed #3a2d50; border-radius: 50%; opacity: 0.6; }
.stat-circle .val { font-size: 1.5rem; font-weight: 900; color: #f0e4ff; font-family: 'Nunito', sans-serif; }
.stat-circle .unit { font-size: 0.6rem; color: #b8a0d0; font-weight: 800; }

.forge-trigger.active {
  background: linear-gradient(135deg, #a8d8b0, #7cc490); color: #2a5a40;
  text-shadow: none; box-shadow: 0 3px 0 #5a9a78, 0 3px 8px rgba(42,138,42,0.2);
}
.as-card { display: flex; flex-direction: column; }
.as-kind { font-size: 0.45rem; color: #f59e0b; font-weight: 900; }

/* Simulated forging animations would go here */


/* FORGE RANK UI */
.forge-rank-card {
  background: #1f1833; border: 2px solid #4a3660; padding: 1rem; margin-bottom: 1.5rem;
  border-left: 3px solid #ffe566; box-shadow: 2px 2px 0 rgba(74,54,96,0.3); border-radius: 10px;
}
.frc-header { display: flex; justify-content: space-between; align-items: start; margin-bottom: 0.5rem; }
.frc-rank { font-size: 0.5rem; font-weight: 900; color: #b8a0d0; letter-spacing: 1px; }
.frc-level { font-size: 1.1rem; font-weight: 900; color: #f0e4ff; margin-bottom: 0.75rem; display: flex; align-items: baseline; gap: 0.5rem; }
.frc-tier { font-size: 0.55rem; font-weight: 800; color: #d4a017; letter-spacing: 1px; }
.frc-xp-bar { height: 4px; background: #2d2545; position: relative; overflow: hidden; border: 1px inset #4a3660; }
.frc-xp-fill { height: 100%; background: #ffe566; box-shadow: none; transition: width 0.3s ease; }
.frc-xp-text { font-size: 0.45rem; color: #b8a0d0; font-weight: 800; display: block; margin-top: 4px; text-align: right; }

.frc-energy { display: flex; align-items: center; gap: 6px; margin-top: 8px; }
.frc-energy-label { font-size: 0.45rem; font-weight: 900; color: #d4a017; letter-spacing: 1px; white-space: nowrap; }
.frc-energy-bar { flex: 1; height: 4px; background: #2d2545; position: relative; overflow: hidden; border: 1px inset #4a3660; }
.frc-energy-fill { height: 100%; background: linear-gradient(90deg, #ffe566, #ffd700); transition: width 0.3s ease; }
.frc-energy-val { font-size: 0.5rem; font-weight: 900; color: #d4a017; white-space: nowrap; }

/* ===== LIGHT MODE - Kawaii Style ===== */
.light-mode { background: #faf6ff !important; color: #4a3a5c !important; background-image: radial-gradient(circle, #e8d0f0 1.5px, transparent 1.5px) !important; background-size: 20px 20px !important; font-family: 'Nunito', 'Trebuchet MS', sans-serif !important; }
.light-mode .terminal-overlay { display: none; }
.light-mode .white { color: #4a3a5c !important; }

/* Header */
.light-mode .terminal-header { background: #fff; border-color: #d0b8e8; }
.light-mode .h-brand { color: #4a3a5c; }
.light-mode .h-ver { color: #9a80b8; }
.light-mode .m-box .l { color: #9a80b8; }
.light-mode .m-box .v { color: #4a3a5c; }
.light-mode .m-box .v.cyan { color: #7b5ea7; }
.light-mode .m-box .v.amber { color: #d4a017; }
.light-mode .theme-toggle { border-color: #d0b8e8; color: #9a80b8; }
.light-mode .theme-toggle:hover { border-color: #b088d0; color: #4a3a5c; }
.light-mode .menu-toggle { border-color: #d0b8e8; color: #9a80b8; }
.light-mode .menu-toggle:hover { border-color: #b088d0; color: #4a3a5c; }
.light-mode .menu-dropdown { background: #fff; border-color: #c4a0e8; box-shadow: 3px 3px 0 #e8d0f0; border-radius: 10px; }
.light-mode .menu-dropdown button { color: #7b5ea7; border-bottom-color: #f0e4ff; }
.light-mode .menu-dropdown button:hover { background: #f8f2ff; color: #4a3a5c; }
.light-mode .ph-title { color: #9a80b8; }
.light-mode .ph-sub { color: #b8a0d0; }

/* Inventory/Market/Exchange light mode */
.light-mode .inv-bar { border-bottom-color: #d0b8e8; }
.light-mode .inv-title { color: #7b5ea7; }
.light-mode .inv-slots { color: #7b5ea7; background: rgba(196,160,232,0.1); }
.light-mode .il-row { border-bottom-color: #f0e4ff; }
.light-mode .il-row:hover { background: #f8f2ff; }
.light-mode .il-name { color: #4a3a5c; }
.light-mode .il-stat { color: #9a80b8; }
.light-mode .il-qty { color: #d4a017; }
.light-mode .inv-card { background: #fff; border-color: #d0b8e8; border-radius: 12px; }
.light-mode .inv-card.featured { border-color: #c4a0e8; background: rgba(196,160,232,0.05); }
.light-mode .ic-tag { background: rgba(196,160,232,0.1); }
.light-mode .ic-tag.amber { color: #d4a017; background: rgba(212,160,23,0.1); }
.light-mode .ic-tag.cyan { color: #7b5ea7; background: rgba(196,160,232,0.1); }
.light-mode .ic-name { color: #4a3a5c; }
.light-mode .ic-desc { color: #9a80b8; }
.light-mode .ic-stats { color: #9a80b8; }
.light-mode .ic-qty { color: #d4a017; }
.light-mode .ic-buy { border-top-color: #f0e4ff; }
.light-mode .ic-price { color: #7b5ea7; }
.light-mode .buy-btn { border-color: #d0b8e8; color: #7b5ea7; border-radius: 8px; }
.light-mode .buy-btn:hover { border-color: #c4a0e8; color: #4a3a5c; background: #f8f2ff; }
.light-mode .mkt-tabs button { border-color: #d0b8e8; color: #9a80b8; }
.light-mode .mkt-tabs button.active { border-color: #c4a0e8; color: #7b5ea7; }
.light-mode .exch-balances, .light-mode .exch-rates, .light-mode .exch-form { background: #fff; border-color: #d0b8e8; border-radius: 12px; }
.light-mode .exch-val { color: #4a3a5c; }
.light-mode .exch-val.amber { color: #d4a017; }
.light-mode .exch-val.cyan { color: #7b5ea7; }
.light-mode .exch-input { border-color: #d0b8e8; color: #4a3a5c; }
.light-mode .exch-input:focus { border-color: #c4a0e8; }
.light-mode .exch-target-btns button { border-color: #d0b8e8; color: #9a80b8; }
.light-mode .exch-target-btns button.active { border-color: #c4a0e8; color: #7b5ea7; }
.light-mode .exch-submit { border-color: #d0b8e8; color: #7b5ea7; }
.light-mode .exch-submit:hover:not(:disabled) { border-color: #c4a0e8; color: #4a3a5c; }
.light-mode .menu-modal-overlay { background: rgba(74,58,92,0.5); }
.light-mode .menu-modal { background: #fff; border-color: #c4a0e8; border-radius: 16px; box-shadow: 4px 4px 0 #e8d0f0; }
.light-mode .mm-header { border-bottom-color: #f0e4ff; }
.light-mode .mm-tabs button { border-color: #d0b8e8; color: #9a80b8; }
.light-mode .mm-tabs button.active { border-color: #c4a0e8; color: #7b5ea7; }
.light-mode .mm-close { border-color: #d0b8e8; color: #9a80b8; }
.light-mode .mm-close:hover { border-color: #e87c8a; color: #e87c8a; }
.light-mode .buy-confirm-overlay { background: rgba(74,58,92,0.5); }
.light-mode .buy-confirm-dialog { background: #fff; border-color: #c4a0e8; border-radius: 16px; box-shadow: 4px 4px 0 #e8d0f0; }
.light-mode .bcd-item { color: #4a3a5c; }
.light-mode .bcd-price { color: #d4a017; }
.light-mode .bcd-btn.cancel { color: #9a80b8; border-color: #d0b8e8; }
.light-mode .bcd-btn.confirm { color: #7b5ea7; border-color: rgba(196,160,232,0.5); }
.light-mode .bcd-btn.confirm:hover { border-color: #c4a0e8; background: #f8f2ff; }
.light-mode .bcd-msg.success { color: #7cc490; border-color: rgba(124,196,144,0.3); background: rgba(124,196,144,0.05); }
.light-mode .bcd-msg.error { color: #e87c8a; border-color: rgba(232,124,138,0.3); background: rgba(232,124,138,0.05); }

/* Resources */
.light-mode .h-resources { border-left-color: #d0b8e8; box-shadow: none; }
.light-mode .h-balance { border-right-color: rgba(196,160,232,0.2); }
.light-mode .hb-val { color: #4a3a5c; }
.light-mode .hb-val.lw { color: #d4a017; }
.light-mode .hb-val.ron { color: #7b5ea7; }
.light-mode .res-bar { background: #efe0f8; }
.light-mode .res-meta { color: #9a80b8; }
.light-mode .res-meta span { color: #7b5ea7; }
.light-mode .res-meta strong { color: #4a3a5c; }

/* Tabs */
.light-mode .view-tabs button { color: #9a80b8; border-color: #d0b8e8; background: #f8f2ff; }
.light-mode .view-tabs button.active { color: #4a3a5c; border-color: #c4a0e8; background: #fff; }
.light-mode .terminal-nav button { color: #9a80b8; }
.light-mode .terminal-nav button.active { color: #4a3a5c; }

/* Fleet Command */
.light-mode .fleet-command-v8 { background: #fff; border-color: #d0b8e8; border-radius: 12px; }
.light-mode .fc-label { color: #9a80b8; }
.light-mode .fc-btn { border-color: #d0b8e8; color: #7b5ea7; }
.light-mode .fc-net-track { background: #efe0f8; }
.light-mode .fc-net-label { color: #7b5ea7; }
.light-mode .fc-net-val { color: #7b5ea7; }
.light-mode .fc-btn:hover { border-color: #b088d0; color: #4a3a5c; background: #f8f2ff; }
.light-mode .fc-btn.active { border-color: #c4a0e8; color: #c4a0e8; background: rgba(196,160,232,0.08); box-shadow: none; }
.light-mode .fc-stat .l { color: #9a80b8; }
.light-mode .fc-stat .v { color: #4a3a5c; }
.light-mode .forge-filter-bar { background: #fff; border-color: #d0b8e8; }
.light-mode .forge-filter-bar .f-search-input { background: #f8f2ff; border-color: #d0b8e8; color: #4a3a5c; }
.light-mode .forge-filter-bar .forge-cats button { border-color: #d0b8e8; color: #7b5ea7; }
.light-mode .forge-filter-bar .forge-cats button.active { background: rgba(196,160,232,0.1); color: #7b5ea7; border-color: #c4a0e8; }
.light-mode .forge-status-bar { background: #fff; border-color: #d0b8e8; }
.light-mode .fsb-rank { color: #c4a0e8; }
.light-mode .fsb-level { color: #9a80b8; }
.light-mode .fsb-xp { background: #efe0f8; }
.light-mode .fsb-xp-text { color: #9a80b8; }

/* Inbox light mode */
.light-mode .inbox-summary-bar { background: #fff; border-color: #d0b8e8; border-radius: 12px; }
.light-mode .isb-label { color: #9a80b8; }
.light-mode .isb-count { color: #7b5ea7; }
.light-mode .isb-total { color: #d4a017; }
.light-mode .isb-claim-all-hold { background: rgba(196,160,232,0.08); border-color: #c4a0e8; color: #7b5ea7; }
.light-mode .isb-claim-all-hold .hold-fill-bar { background: rgba(196,160,232,0.2); }
.light-mode .inbox-block-card { background: #fff; border-color: #d0b8e8; border-radius: 10px; }
.light-mode .inbox-block-card:hover { background: #f8f2ff; border-color: #c4a0e8; }
.light-mode .inbox-block-card.selected { border-color: #c4a0e8; background: rgba(196,160,232,0.06); }
.light-mode .ibc-height { color: #4a3a5c; }
.light-mode .ibc-date { color: #9a80b8; }
.light-mode .ibc-amount { color: #d4a017; }
.light-mode .inbox-load-more { background: #fff; border-color: #d0b8e8; color: #9a80b8; }
.light-mode .inbox-load-more:hover { border-color: #c4a0e8; color: #7b5ea7; }
.light-mode .claim-modal { background: #fff; border-color: #c4a0e8; border-radius: 16px; box-shadow: 4px 4px 0 #e8d0f0; }
.light-mode .cm-header { border-color: #f0e4ff; color: #c4a0e8; }
.light-mode .cm-info { color: #9a80b8; }
.light-mode .cm-claim-btn { background: rgba(196,160,232,0.08); border-color: #c4a0e8; color: #7b5ea7; }
.light-mode .inv-action-btn { background: #f8f2ff; border-color: #d0b8e8; color: #4a3a5c; }
.light-mode .inv-action-btn.danger { border-color: rgba(232,124,138,0.3); color: #e87c8a; background: #fff; }
.light-mode .inv-select-row { border-color: #d0b8e8; color: #4a3a5c; }
.light-mode .inv-hint { border-color: #d0b8e8; color: #9a80b8; }

/* Block Radar & Monitors */
.light-mode .block-radar { background: #fff; border-color: #d0b8e8; border-radius: 12px; }
.light-mode .radar-label { color: #4a3a5c; }
.light-mode .radar-line { background: #efe0f8; }
.light-mode .monitor-card { background: #fff; border-color: #d0b8e8; border-radius: 12px; }
.light-mode .m-tag { color: #4a3a5c; }
.light-mode .m-status { color: #9a80b8; }
.light-mode .m-stat .l { color: #7b5ea7; }
.light-mode .m-radar { background: #efe0f8; }
.light-mode .m-footer { color: #9a80b8; }
.light-mode .m-timer { color: #4a3a5c; }
.light-mode .monitor-empty span { color: #4a3a5c; }
.light-mode .monitor-empty small { color: #7b5ea7; }

/* Rig Tiles */
.light-mode .rig-tile { background: #fff; border-color: #d0b8e8; border-radius: 12px; }
.light-mode .rig-tile::before { display: none; }
.light-mode .rt-scanline { display: none; }
.light-mode .rt-corner { border-color: #d0b8e8; }
.light-mode .rig-tile:hover { background: #f8f2ff; border-color: #c4a0e8; }
.light-mode .rig-tile.active .rt-corner { border-color: rgba(196,160,232,0.4); }
.light-mode .rig-tile.selected { background: #f0e4ff; border-color: #c4a0e8; box-shadow: 3px 3px 0 #e8d0f0; }
.light-mode .rig-tile.selected .rt-corner { border-color: #c4a0e8; }
.light-mode .rig-tile.empty { background: #f8f2ff; border-color: #d0b8e8; }
.light-mode .rig-tile.buy-slot { background: #f8f2ff; }
.light-mode .t-name-big { color: #4a3a5c; }
.light-mode .t-num { color: #c4a0e8; text-shadow: none; }
.light-mode .t-speed { color: #c4a0e8 !important; text-shadow: none !important; }
.light-mode .t-grade-badge { background: transparent; }
.light-mode .t-status-badge.online { background: rgba(124,196,144,0.1); border-color: rgba(124,196,144,0.2); color: #7cc490; }
.light-mode .t-status-badge.offline { background: rgba(232,124,138,0.08); border-color: rgba(232,124,138,0.15); color: #e87c8a; }
.light-mode .lt-bar { background: #efe0f8; border-color: #d0b8e8; }
.light-mode .lt-fill { background: linear-gradient(90deg, #b088d0, #c4a0e8); box-shadow: none; }
.light-mode .lt-segments { background: repeating-linear-gradient(90deg, transparent 0px, transparent 18%, rgba(255,255,255,0.8) 18%, rgba(255,255,255,0.8) 20%); }
.light-mode .lt-text { color: #9a80b8; }
.light-mode .lt-text.low { color: #e87c8a; }

/* Command Panel */
.light-mode .command-panel { background: #fff; border-color: #d0b8e8; border-radius: 12px; }
.light-mode .command-panel::before { display: none; }
.light-mode .cp-hud-scanline { display: none; }
.light-mode .cp-hud-corner { border-color: #c4a0e8; }
.light-mode .command-panel.visible { background: #faf6ff; border-color: #c4a0e8; box-shadow: 3px 3px 0 #e8d0f0; }
.light-mode .diag-tag { color: #9a80b8; }
.light-mode .hud-header-line { background: linear-gradient(90deg, rgba(196,160,232,0.3), #efe0f8, transparent); }
.light-mode .panel-inner h1 { color: #4a3a5c; }
.light-mode .panel-loading { color: #9a80b8; }
.light-mode .pe-icon { color: #d0b8e8; }
.light-mode .pe-text { color: #9a80b8; }
.light-mode .pe-sub { color: #b8a0d0; }

/* Config Tabs */
.light-mode .config-tabs button { color: #9a80b8; background: #f8f2ff; border-color: #d0b8e8; }
.light-mode .config-tabs button.active { color: #7b5ea7; border-color: rgba(196,160,232,0.4); border-bottom-color: #c4a0e8; background: rgba(196,160,232,0.05); text-shadow: none; }
.light-mode .config-content::-webkit-scrollbar-thumb { background: #d0b8e8; }

/* Telemetry */
.light-mode .tele-hud { background: linear-gradient(135deg, #faf6ff 0%, #f0e4ff 100%); border-color: #d0b8e8; border-radius: 12px; }
.light-mode .tele-hud::before { display: none; }
.light-mode .tele-hud .hud-scanline { display: none; }
.light-mode .hud-corner { border-color: #c4a0e8; }
.light-mode .hud-sys-id { color: #9a80b8; }
.light-mode .hud-readout { color: #c4a0e8; text-shadow: none; }
.light-mode .hud-readout-cyan { color: #7b5ea7; }
.light-mode .hud-readout-green { color: #7cc490; }
.light-mode .hud-gauge-track { background: #efe0f8; border-color: #d0b8e8; }
.light-mode .hud-gauge-segments { background: repeating-linear-gradient(90deg, transparent 0px, transparent 9%, rgba(248,242,255,0.8) 9%, rgba(248,242,255,0.8) 10%); }
.light-mode .hud-gauge-ticks span { color: #9a80b8; }
.light-mode .hud-tag { color: #7cc490; }
.light-mode .hud-aux { color: #9a80b8; }
.light-mode .hud-warn .hud-tag { color: #d4a017; }
.light-mode .hud-danger .hud-tag { color: #e87c8a; }
.light-mode .thud-txt { color: #9a80b8; }
.light-mode .thud-line { background: linear-gradient(90deg, transparent, #d0b8e8, transparent); }
.light-mode .thud-blink { background: #c4a0e8; }

/* Component Summary */
.light-mode .comp-summary { border-color: #d0b8e8; }
.light-mode .cs-item { background: #f8f2ff; border-color: #d0b8e8; border-left-color: rgba(196,160,232,0.4); }
.light-mode .cs-type { color: #7b5ea7; }
.light-mode .cs-val.dim { color: #b8a0d0; }
.light-mode .cs-val.cyan { text-shadow: none; }
.light-mode .cs-val.amber { text-shadow: none; }
.light-mode .cs-detail { color: #7b5ea7; }

/* Sockets & Items */
.light-mode .socket-slot { background: #f8f2ff; border-color: #d0b8e8; border-left-color: rgba(196,160,232,0.4); }
.light-mode .socket-slot::before { display: none; }
.light-mode .s-label { color: #9a80b8; }
.light-mode .comp-section-label { color: #9a80b8; }
.light-mode .comp-empty-text { color: #9a80b8; }
.light-mode .comp-empty-hint { color: #9a80b8; }
.light-mode .i-name { color: #7b5ea7; }
.light-mode .ie-bar { background: #efe0f8; }
.light-mode .ie-val { color: #7b5ea7; }
.light-mode .ie-meta { color: #7b5ea7; }
.light-mode .item-placeholder { color: #d0b8e8; }
.light-mode .section-label { color: #9a80b8; border-left-color: #d0b8e8; }
.light-mode .config-item { background: #f8f2ff; border-color: #d0b8e8; }
.light-mode .item-name { color: #4a3a5c; }
.light-mode .remove-btn, .light-mode .install-btn { border-color: #d0b8e8; color: #9a80b8; }
.light-mode .tab-pane.scroll::-webkit-scrollbar-thumb { background: #d0b8e8; }

/* Controls */
.light-mode .panel-controls-v8 { border-color: #f0e4ff; }
.light-mode .action-btn-v8.power { background: #4a3a5c; color: #fff; border-radius: 10px; }
.light-mode .action-btn-v8.power.active { background: #e87c8a; color: #fff; }
.light-mode .sub-btn-v8 { border-color: #d0b8e8; color: #7b5ea7; }
.light-mode .sub-btn-v8:hover { border-color: #c4a0e8; color: #4a3a5c; }
.light-mode .panel-meta { border-color: #f0e4ff; color: #9a80b8; }
.light-mode .panel-stats-inline { border-color: #f0e4ff; }
.light-mode .sl { color: #9a80b8; }

/* Mode Selector */
.light-mode .mode-selector-v8 { border-color: #d0b8e8; background: #f8f2ff; border-radius: 12px; }
.light-mode .selector-head { color: #9a80b8; }
.light-mode .mode-opt { background: #fff; border-color: #d0b8e8; border-radius: 10px; }
.light-mode .mode-opt:hover { border-color: #c4a0e8; }
.light-mode .mode-opt .m-title { color: #4a3a5c; }
.light-mode .mode-abort { border-color: #d0b8e8; color: #9a80b8; }
.light-mode .mode-abort:hover { color: #4a3a5c; border-color: #c4a0e8; background: #f0e4ff; }
.light-mode .mode-tag { background: rgba(196,160,232,0.08); border-color: rgba(196,160,232,0.3); color: #7b5ea7; }
.light-mode .mode-tag.solo { border-color: rgba(124,196,144,0.3); color: #7cc490; background: rgba(124,196,144,0.05); }

/* Strategic Advisory */
.light-mode .tip-card { background: #fff; border-color: #d0b8e8; border-left-color: #c4a0e8; border-radius: 10px; }
.light-mode .tip-title { color: #4a3a5c; }
.light-mode .tip-desc { color: #7b5ea7; }
.light-mode .tip-meta span { color: #9a80b8; }

/* Modals */
.light-mode .confirm-modal-overlay { background: rgba(74,58,92,0.4); }
.light-mode .confirm-dialog { background: #fff; border-color: #c4a0e8; border-radius: 16px; box-shadow: 4px 4px 0 #e8d0f0; }
.light-mode .diag-header { border-color: #f0e4ff; }
.light-mode .diag-header h3 { color: #4a3a5c; }
.light-mode .diag-body p { color: #7b5ea7; }
.light-mode .expansion-details { background: #f8f2ff; border-color: #d0b8e8; }
.light-mode .det-row .l { color: #9a80b8; }
.light-mode .diag-footer { background: #f8f2ff; }
.light-mode .d-btn { border-color: #d0b8e8; }
.light-mode .d-btn.cancel { background: #f0e4ff; color: #7b5ea7; border-color: #d0b8e8; }
.light-mode .diag-warning { color: #e87c8a; }

/* Research View */
.light-mode .research-header { background: #fff; border-color: #d0b8e8; border-left-color: #c4a0e8; }
.light-mode .research-header h1 { color: #4a3a5c; }
.light-mode .rh-points .v { color: #4a3a5c; }
.light-mode .branch-label { background: rgba(196,160,232,0.08); }
.light-mode .node-connector { background: #d0b8e8; }
.light-mode .tree-node { background: #f8f2ff; border-color: #d0b8e8; border-radius: 10px; }
.light-mode .tree-node:hover { border-color: #c4a0e8; background: #fff; }
.light-mode .tree-node.unlocked { background: #f0e4ff; }
.light-mode .node-icon { background: #fff; border-color: #d0b8e8; }
.light-mode .n-name { color: #4a3a5c; }
.light-mode .n-desc { color: #9a80b8; }

/* History */
.light-mode .history-terminal { background: #fff; border-color: #d0b8e8; border-radius: 12px; }
.light-mode .history-head { border-color: #f0e4ff; color: #4a3a5c; }
.light-mode .history-row { border-color: #f0e4ff; }
.light-mode .b-num { color: #9a80b8; }
.light-mode .panel-waiting { color: #d0b8e8; }
.light-mode .wait-vignette { border-color: #d0b8e8; }

/* Scrollbars */
.light-mode .scroll-v::-webkit-scrollbar-thumb { background: #d0b8e8; }
.light-mode .scroll::-webkit-scrollbar-thumb { background: #d0b8e8; }

/* Global text color catch-all */
.light-mode .v { color: #4a3a5c; }
.light-mode .l { color: #9a80b8; }
.light-mode .cyan { color: #7b5ea7 !important; }
.light-mode .amber { color: #d4a017 !important; }
.light-mode .monospace { color: #4a3a5c; }

/* Rig tile extras */
.light-mode .rig-tile.buy-slot span { color: #4a3a5c; }
.light-mode .rig-tile.buy-slot .plus { color: #c4a0e8; }
.light-mode .tile-alert.error { background: #e87c8a; color: #fff; border-radius: 8px; }

/* Hover states */
.light-mode .fc-btn:hover { border-color: #c4a0e8; color: #4a3a5c; }
.light-mode .d-btn.cancel:hover { border-color: #b088d0; color: #4a3a5c; }
.light-mode .mode-abort:hover { color: #4a3a5c; border-color: #c4a0e8; }
.light-mode .sub-btn-v8:hover { color: #4a3a5c; border-color: #c4a0e8; }
.light-mode .install-btn:hover { border-color: #c4a0e8; color: #4a3a5c; }
.light-mode .theme-toggle:hover { color: #4a3a5c; }

/* Monitor status */
.light-mode .m-status:not(.inactive) { color: #4a3a5c; }

/* Forge view */
.light-mode .forge-cats { background: #fff; border-color: #d0b8e8; border-radius: 12px; }
.light-mode .forge-cats button { color: #9a80b8; border-color: transparent; }
.light-mode .forge-cats button.active { color: #7b5ea7; background: #f0e4ff; border-left-color: #c4a0e8; }
.light-mode .forge-cats button:hover { color: #4a3a5c; }
.light-mode .bp-card-v2 { background: #fff; border-color: #d0b8e8; border-radius: 10px; }
.light-mode .bp-card-v2:hover { border-color: #c4a0e8; }
.light-mode .bp-card-v2.selected { border-color: #c4a0e8; background: #f0e4ff; }
.light-mode .bpc-name { color: #4a3a5c; }
.light-mode .bpc-mat .mat-qty { color: #4a3a5c; }
.light-mode .mini-item { color: #7b5ea7; }
.light-mode .mini-item:hover { color: #4a3a5c; background: #f0e4ff; }
.light-mode .forge-search { background: #fff; border-color: #d0b8e8; color: #4a3a5c; }

/* Detail panel (forge) */
.light-mode .detail-close:hover { color: #4a3a5c; }
.light-mode .ds-val { color: #4a3a5c; }
.light-mode .dm-qty { color: #4a3a5c; }

/* Stats & misc */
.light-mode .stat-circle .val { color: #4a3a5c; }
.light-mode .frc-level { color: #4a3a5c; }
.light-mode .frc-xp-bar { background: #efe0f8; }
.light-mode .frc-xp-text { color: #a1a1aa; }
.light-mode .frc-energy-bar { background: #ddd; }
.light-mode .frc-energy-val { color: #b45309; }
.light-mode .frc-energy-label { color: #b45309; }
.light-mode .frc-tier { color: #cc8800; }

/* Progress bars & fills */
.light-mode .lt-fill { background: #2563eb; }
.light-mode .lt-fill.mid { background: #d97706; }
.light-mode .ie-bar { background: #e2e8f0; border-color: #cbd5e1; }
.light-mode .ie-fill { background: linear-gradient(90deg, #b45309, #d97706); box-shadow: none; }
.light-mode .ie-fill.mid { background: linear-gradient(90deg, #b45309, #d97706); }
.light-mode .ie-fill.low { background: linear-gradient(90deg, #b91c1c, #dc2626); }
.light-mode .hud-fill-amber { background: linear-gradient(90deg, #b45309, #d97706, #f59e0b); }
.light-mode .hud-fill-cyan { background: linear-gradient(90deg, #0e7490, #0891b2, #22d3ee); }
.light-mode .hud-fill-green { background: linear-gradient(90deg, #15803d, #16a34a, #4ade80); }
.light-mode .fill.cyan { background: linear-gradient(90deg, #1d4ed8, #2563eb); }
.light-mode .fill.amber { background: linear-gradient(90deg, #b45309, #d97706); }
.light-mode .fill.violet { background: linear-gradient(90deg, #7c3aed, #9333ea); box-shadow: none; }
.light-mode .res-bar .fill { box-shadow: none; }
.light-mode .cyan-bg { background: #2563eb; }

/* Cyan elements */
.light-mode .dot.cyan { background: #2563eb; box-shadow: 0 0 6px #2563eb80; }
.light-mode .res-meta strong.cyan { color: #2563eb; text-shadow: none; }
.light-mode .i-name { color: #2563eb; }
.light-mode .t-status-badge.online .tsb-dot { background: #16a34a; box-shadow: 0 0 4px rgba(22,163,74,0.5); }
.light-mode .fc-btn.neon:hover { border-color: #2563eb; color: #2563eb; box-shadow: none; }
.light-mode .d-btn.confirm:hover { background: #2563eb; }
.light-mode .tip-card.info { border-left-color: #2563eb; }

/* Amber elements */
.light-mode .dot.amber { background: #d97706; box-shadow: 0 0 6px #d9770680; }
.light-mode .res-meta strong.amber { color: #d97706; text-shadow: none; }

/* Violet elements */
.light-mode .dot.violet { background: #7c3aed; box-shadow: 0 0 6px #7c3aed80; }
.light-mode .res-meta strong.violet { color: #7c3aed; text-shadow: none; }

/* Remove glows/shadows in light mode */
.light-mode .cyan { text-shadow: none !important; }
.light-mode .amber { text-shadow: none !important; }
.light-mode .violet { text-shadow: none !important; }

/* Grid section - rig tile overrides handled above */

/* ===== FORGE LIGHT MODE (Kawaii) ===== */
/* Forge layout */
.light-mode .forge-grid-layout { background: #faf6ff; }
.light-mode .forge-sidebar { background: #fff; border-right: 1px solid #d0b8e8; }
.light-mode .forge-search-box .f-search-input { background: #f8f2ff; border-color: #d0b8e8; color: #4a3a5c; }
.light-mode .forge-search-box .f-search-input::placeholder { color: #9a80b8; }
.light-mode .forge-cats button { color: #9a80b8; }
.light-mode .forge-cats button:hover { color: #4a3a5c; background: #f0e4ff; }
.light-mode .forge-cats button.active { color: #7b5ea7; background: #f0e4ff; border-left-color: #c4a0e8; }
.light-mode .forge-sidebar::-webkit-scrollbar { background: #f0e4ff; }
.light-mode .forge-sidebar::-webkit-scrollbar-thumb { background: #d0b8e8; }

/* Forge main grid */
.light-mode .forge-main-grid { background: #faf6ff; }

/* Blueprint cards */
.light-mode .bp-card-v2 { background: #fff; border-color: #d0b8e8; }
.light-mode .bp-card-v2:hover { border-color: #c4a0e8; background: #f8f2ff; }
.light-mode .bp-card-v2.can_forge { border-color: rgba(124,196,144,0.5); background: rgba(124,196,144,0.04); }
.light-mode .bp-card-v2.selected { border-color: #c4a0e8; background: #f0e4ff; box-shadow: 3px 3px 0 #e8d0f0; }
.light-mode .bp-card-v2.locked { opacity: 0.4; }
.light-mode .bpc-locked-overlay { background: rgba(255,255,255,0.5); }
.light-mode .bpc-lock-text { color: #7b5ea7; }
.light-mode .bpc-name { color: #4a3a5c; }
.light-mode .bpc-mat { color: #9a80b8; }
.light-mode .bpc-mat.ok { color: #7cc490; }
.light-mode .bpc-mat .mat-qty { color: #4a3a5c; }
.light-mode .bpc-gives { border-color: #d0b8e8; }
.light-mode .bpc-gives.gives-HASHRATE { color: #d4a017; border-color: rgba(212,160,23,0.3); }
.light-mode .bpc-gives.gives-COOLING { color: #7b5ea7; border-color: rgba(123,94,167,0.3); }
.light-mode .bpc-gives.gives-ENERGY { color: #7cc490; border-color: rgba(124,196,144,0.3); }
.light-mode .bpc-gives.gives-DURABILITY { color: #7b5ea7; border-color: rgba(123,94,167,0.3); }
.light-mode .bpc-gives.gives-BOOSTER { color: #d4a017; border-color: rgba(212,160,23,0.3); }
.light-mode .bpc-gives.gives-NONE { color: #9a80b8; border-color: rgba(154,128,184,0.3); }
.light-mode .bpc-coolhp { color: #7b5ea7; }
.light-mode .bpc-consumes { color: #e87c8a; }
.light-mode .bpc-meta { color: #9a80b8; border-top-color: #f0e4ff; }
.light-mode .bpc-time { color: #7b5ea7; }
.light-mode .bpc-cost { color: #d4a017; }
.light-mode .bpc-nrg { color: #d4a017; }
.light-mode .nrg-val { color: #d4a017; }
.light-mode .bpc-deliver.active { border-color: #7cc490; color: #7cc490; }
.light-mode .bpc-footer { border-top-color: #f0e4ff; }
.light-mode .bpc-stat { color: #7b5ea7; }

/* Rarity borders in light */
.light-mode .bp-card-v2.rarity-common { border-color: rgba(124,196,144,0.4); }
.light-mode .bp-card-v2.rarity-rare { border-color: rgba(123,94,167,0.4); }
.light-mode .bp-card-v2.rarity-epic { border-color: rgba(196,160,232,0.5); }
.light-mode .bp-card-v2.rarity-legendary { border-color: rgba(212,160,23,0.4); }

/* Forge action panel / detail */
.light-mode .forge-action-panel { background: #fff; border-left: 1px solid #d0b8e8; }
.light-mode .detail-close { color: #9a80b8; }
.light-mode .detail-close:hover { color: #4a3a5c; }
.light-mode .detail-tier { color: #9a80b8; }
.light-mode .detail-name { color: #4a3a5c; }
.light-mode .detail-cat { color: #9a80b8; }
.light-mode .detail-desc { color: #7b5ea7; }
.light-mode .detail-idle { color: #9a80b8; }

/* Material rows */
.light-mode .dm-row { background: #f8f2ff; border-color: #d0b8e8; color: #9a80b8; }
.light-mode .dm-row.ok { border-color: rgba(124,196,144,0.3); color: #7b5ea7; }

/* Forge trigger button */
.light-mode .forge-trigger { background: #4a3a5c; color: #fff; }
.light-mode .forge-trigger:hover { background: #3a2a4c; }
.light-mode .forge-trigger:disabled { background: #efe0f8; color: #9a80b8; }
.light-mode .forge-trigger.active { background: #7cc490; color: #fff; box-shadow: none; }
.light-mode .hold-btn { background: #f0e4ff; color: #4a3a5c; border-color: #d0b8e8; }
.light-mode .hold-btn:active:not(:disabled) { border-color: #7cc490; }
.light-mode .hold-fill { background: linear-gradient(90deg, rgba(124,196,144,0.2), rgba(124,196,144,0.4)); }

/* Stat circles */
.light-mode .stat-circle { border-color: #d0b8e8; background: #f8f2ff; }
.light-mode .stat-circle .val { color: #4a3a5c; }
.light-mode .stat-circle .unit { color: #9a80b8; }

/* Collection meter bar */
.light-mode .cm-bar { background: #efe0f8; }
.light-mode .cm-bar .fill { background: #7cc490; box-shadow: none; }

/* Forge terminal / logs */
.light-mode .forge-terminal { background: #f8f2ff; border-left-color: #c4a0e8; color: #7b5ea7; }

/* Forge rank card */
.light-mode .forge-rank-card { background: #fff; border-color: #d0b8e8; border-left-color: #c4a0e8; }

/* Tier badge */
.light-mode .bpc-tier-badge { color: #fff; }

/* ===================== STAKING ===================== */
.view-staking { padding: 1.5rem; max-width: 800px; margin: 0 auto; overflow-y: auto; }

.stake-loading { text-align: center; color: #b8a0d0; font-size: 0.7rem; padding: 3rem; }

/* Header */
.stake-header { text-align: center; margin-bottom: 1.5rem; }
.stake-header h2 { font-size: 1.1rem; font-weight: 900; color: #f0e4ff; letter-spacing: 3px; margin: 0 0 0.5rem; font-family: 'Nunito', sans-serif; }
.stake-subtitle { font-size: 0.65rem; color: #b8a0d0; line-height: 1.6; max-width: 500px; margin: 0 auto 0.75rem; }
.stake-balance { font-size: 0.75rem; color: #b8a0d0; }
.stake-balance strong { color: #d4a017; font-size: 1rem; text-shadow: none; }

/* Plan cards grid */
.stake-plans { display: grid; grid-template-columns: repeat(4, 1fr); gap: 1rem; }
.stake-card {
  background: #1f1833; border: 2px solid #4a3660; padding: 1.2rem 0.8rem;
  display: flex; flex-direction: column; align-items: center; gap: 0.5rem;
  cursor: pointer; transition: 0.2s; text-align: center; position: relative;
  border-radius: 12px; box-shadow: 3px 3px 0 rgba(74,54,96,0.3);
}
.stake-card:hover { border-color: #5c4578; background: #231d35; }
.stake-card.selected { border-color: #ffe566; background: rgba(255,229,102,0.08); box-shadow: 4px 4px 0 #d4a017; }
.stake-card.disabled { pointer-events: none; filter: grayscale(1); }

.sc-icon { font-size: 2.5rem; margin-bottom: 0.2rem; }
.sc-name { font-size: 0.9rem; font-weight: 900; letter-spacing: 3px; color: #f0e4ff; font-family: 'Nunito', sans-serif; }
.sc-ron { font-size: 1.2rem; font-weight: 700; color: #d4a017; text-shadow: none; font-family: 'Roboto', 'Nunito', sans-serif; }
.sc-divider { width: 60px; height: 2px; background: #c4a0e8; margin: 0.4rem 0; }
.sc-reward { display: flex; flex-direction: column; align-items: center; gap: 3px; }
.sc-landwork { font-size: 1.3rem; font-weight: 700; color: #4a8a6a; text-shadow: none; font-family: 'Roboto', 'Nunito', sans-serif; }
.sc-lw-label { font-size: 0.6rem; color: #b8a0d0; letter-spacing: 2px; font-weight: 800; }
.sc-meta { display: flex; gap: 1rem; font-size: 0.65rem; color: #b8a0d0; font-weight: 800; }
.sc-phases { font-size: 0.55rem; color: #8a70a8; margin-top: 0.3rem; line-height: 1.4; }

/* Confirm button */
.stake-confirm { text-align: center; margin-top: 1rem; }
.stake-btn {
  background: #ffe566; color: #1a1528; border: 2px outset #d4a017; padding: 0.7rem 2rem;
  font-family: inherit; font-weight: 900; font-size: 0.75rem; cursor: pointer;
  letter-spacing: 2px; transition: 0.2s; border-radius: 10px;
}
.stake-btn:hover { background: #ffd700; border-style: inset; }
.stake-btn:disabled { opacity: 0.5; cursor: not-allowed; }

/* Active stake panel */
.stake-active-panel {
  max-width: 500px; margin: 0 auto; padding: 1.5rem;
  background: #1f1833; border: 2px solid #5c4578; border-radius: 14px;
  display: flex; flex-direction: column; align-items: center; gap: 0.75rem; text-align: center;
  box-shadow: 4px 4px 0 rgba(74,54,96,0.3);
}
.sap-icon { font-size: 2.8rem; }
.sap-plan { font-size: 1.1rem; font-weight: 900; letter-spacing: 3px; color: #f0e4ff; }
.sap-status { font-size: 0.65rem; font-weight: 900; padding: 4px 14px; letter-spacing: 2px; border: 2px solid; }
.sap-status.warmup { color: #d4a017; border-color: #ffe566; background: rgba(255,229,102,0.08); }
.sap-status.active { color: #7cc490; border-color: #5a9a6a; background: rgba(124,196,144,0.08); }
.sap-status.cooldown { color: #c4a0e8; border-color: #5c4578; background: rgba(196,160,232,0.08); }
.sap-status.returned { color: #c4a0e8; border-color: #5c4578; }
.sap-info { font-size: 0.65rem; color: #b8a0d0; line-height: 1.6; max-width: 380px; }

/* Earning display */
.sap-earning { display: flex; flex-direction: column; align-items: center; gap: 0.2rem; }
.sap-earned-val { font-size: 2rem; font-weight: 700; color: #4a8a6a; text-shadow: none; font-family: 'Roboto', 'Nunito', sans-serif; }
.sap-earned-label { font-size: 0.55rem; color: #b8a0d0; letter-spacing: 2px; font-weight: 800; }
.sap-rate { font-size: 0.65rem; color: #4a8a6a; font-weight: 800; opacity: 0.7; }

/* Claim button */
.stake-claim-btn {
  background: #a8d8b0; color: #3a6a50; border: 2px outset #6a9a80; padding: 0.6rem 1.5rem;
  font-family: inherit; font-weight: 900; font-size: 0.7rem; cursor: pointer;
  letter-spacing: 1px; transition: 0.2s; border-radius: 10px;
}
.stake-claim-btn:hover { background: #7cc490; border-style: inset; }
.stake-claim-btn:disabled { opacity: 0.4; cursor: not-allowed; }

/* Countdown */
.sap-countdown { display: flex; flex-direction: column; align-items: center; gap: 0.15rem; }
.sap-cd-label { font-size: 0.55rem; color: #b8a0d0; letter-spacing: 1px; font-weight: 800; }
.sap-cd-val { font-size: 1.2rem; font-weight: 700; color: #f0e4ff; letter-spacing: 2px; font-family: 'Roboto', 'Nunito', sans-serif; }

/* Progress bar */
.sap-progress { width: 100%; max-width: 400px; }
.sap-bar { height: 6px; background: #2d2545; width: 100%; overflow: hidden; border: 2px inset #4a3660; }
.sap-fill { height: 100%; transition: width 0.5s ease; }
.sap-fill.warmup { background: linear-gradient(90deg, #ffd700, #ffe566); }
.sap-fill.active { background: linear-gradient(90deg, #6a9a80, #a8d8b0); }
.sap-fill.cooldown { background: linear-gradient(90deg, #b088d0, #c4a0e8); }

/* Details rows */
.sap-details { width: 100%; max-width: 400px; }
.sap-row {
  display: flex; justify-content: space-between; font-size: 0.65rem; font-weight: 800;
  color: #b8a0d0; padding: 6px 0; border-bottom: 1px solid #3a2d50;
}
.sap-row span:last-child { color: #f0e4ff; }

/* ===================== STAKING LIGHT MODE ===================== */
.light-mode .view-staking { color: #4a3a5c; }
.light-mode .stake-card { background: #fff; border: 2px solid #d0b8e8; box-shadow: 3px 3px 0 #e8d0f0; }
.light-mode .stake-card:hover { border-color: #c4a0e8; background: #f8f2ff; }
.light-mode .stake-active-panel { background: #fff; border: 2px solid #c4a0e8; box-shadow: 4px 4px 0 #e8d0f0; }
.light-mode .stake-header h2 { color: #4a3a5c; }
.light-mode .stake-subtitle { color: #7b5ea7; }
.light-mode .stake-balance { color: #7b5ea7; }
.light-mode .stake-balance strong { color: #d4a017; }
.light-mode .stake-card.selected { border-color: #ffe566; background: rgba(255,229,102,0.08); box-shadow: 4px 4px 0 #d4a017; }
.light-mode .sc-name { color: #4a3a5c; }
.light-mode .sc-ron { color: #d4a017; text-shadow: none; }
.light-mode .sc-landwork { color: #4a8a6a; text-shadow: none; }
.light-mode .sc-lw-label { color: #9a80b8; }
.light-mode .sc-divider { background: #d0b8e8; }
.light-mode .sc-meta { color: #7b5ea7; }
.light-mode .sc-phases { color: #9a80b8; }
.light-mode .stake-btn { background: #ffe566; color: #4a3a5c; border-color: #d4a017; }
.light-mode .sap-status.warmup { color: #d4a017; border-color: #ffe566; }
.light-mode .sap-status.active { color: #7cc490; border-color: #a8d0b8; }
.light-mode .sap-status.cooldown { color: #7b5ea7; border-color: #c4a0e8; }
.light-mode .sap-info { color: #9a80b8; }
.light-mode .sap-earned-val { color: #4a8a6a; }
.light-mode .sap-rate { color: rgba(74,138,106,0.7); }
.light-mode .sap-cd-val { color: #4a3a5c; }
.light-mode .stake-claim-btn { background: #a8d8b0; color: #3a6a50; }
.light-mode .sap-bar { background: #efe0f8; border-color: #d0b8e8; }
.light-mode .sap-fill.warmup { background: linear-gradient(90deg, #d4a017, #ffe566); }
.light-mode .sap-fill.active { background: linear-gradient(90deg, #5a9a6a, #7cc490); }
.light-mode .sap-fill.cooldown { background: linear-gradient(90deg, #b088d0, #c4a0e8); }
.light-mode .sap-row { color: #9a80b8; border-bottom-color: #f0e4ff; }
.light-mode .sap-row span:last-child { color: #4a3a5c; }

/* ===================== LUCKY BOOST (Solo Monitor) ===================== */
.lucky-crown-mini {
  font-size: 10px;
  filter: drop-shadow(0 0 3px rgba(245, 158, 11, 0.6));
  animation: crownBob 2s ease-in-out infinite;
}
@keyframes crownBob {
  0%, 100% { transform: translateY(0) rotate(-5deg); }
  50% { transform: translateY(-2px) rotate(5deg); }
}

.lucky-boost-bar {
  margin-top: 6px;
  padding: 5px 8px;
  border-radius: 8px;
  border: 2px solid #4a3660;
  background: #231d35;
}
.lucky-boost-bar.lucky-active {
  border-color: #ffe566;
  background: rgba(255,229,102,0.08);
  box-shadow: none;
}

.lucky-btn {
  white-space: nowrap;
  transition: all 0.2s;
}
.lucky-btn-activate {
  background: #a8d8b0;
  color: #3a6a50;
  border: 2px outset #6a9a80;
}
.lucky-btn-activate:hover:not(:disabled) {
  background: #7cc490; border-style: inset;
}
.lucky-btn-extend {
  background: #ffe566;
  color: #4a3a5c;
  border: 2px outset #d4a017;
}
.lucky-btn-extend:hover:not(:disabled) {
  background: #ffd700; border-style: inset;
}
.lucky-btn:disabled {
  opacity: 0.35;
  cursor: not-allowed;
}

/* Light mode */
.light-mode .lucky-boost-bar {
  background: #f8f8fc;
  border-color: #ddd;
}
.light-mode .lucky-boost-bar.lucky-active {
  background: linear-gradient(135deg, rgba(245, 158, 11, 0.1), rgba(245, 158, 11, 0.04));
  border-color: rgba(202, 138, 4, 0.4);
}

/* Forge action panel mobile backdrop (hidden on desktop) */
.fap-mobile-backdrop { display: none; }

/* ===================== BOOT-UP — disabled, everything visible ===================== */

/* ===================== MOBILE OVERRIDES (must be last to win cascade) ===================== */
@media (max-width: 1024px) {
  .view-forge { overflow: visible; flex: none; min-height: auto; position: static; }
  .forge-grid-layout { grid-template-columns: 1fr; height: auto; }
  .forge-sidebar { max-height: none; overflow: visible; height: auto; }
  .forge-main-grid { overflow: visible; height: auto; }
  .forge-action-panel { max-height: none; overflow: visible; height: auto; }
  .forge-inv-mini { flex: none; }
}
@media (max-width: 768px) {
  /* Unlock entire scroll chain — prevent horizontal overflow */
  .deck-terminal-v8 { position: fixed; inset: 0; overflow-y: auto !important; overflow-x: hidden !important; max-width: 100vw; }
  .terminal-body { overflow: visible !important; overflow-x: hidden !important; flex: none; }
  .body-inner { overflow: visible !important; overflow-x: hidden !important; min-height: auto; flex: none; box-sizing: border-box; }
  .terminal-viewport { overflow: visible !important; overflow-x: hidden !important; min-height: auto; flex: none; }
  .v8-container { max-width: 100%; box-sizing: border-box; }
  .fleet-layout { height: auto; }
  .grid-section { overflow: visible; }
  .history-terminal { height: auto; }
  .view-solo { height: auto; overflow: visible; }
  .view-staking { overflow: visible !important; }
  .view-forge { overflow: visible !important; flex: none; min-height: auto; position: static; }
  .forge-grid-layout { grid-template-columns: 1fr; height: auto; }
  .forge-sidebar { max-height: none; overflow: visible; height: auto; padding: 0.8rem; }
  .forge-main-grid { overflow: visible; height: auto; padding: 0.8rem; }
  .forge-inv-mini { flex: none; }

  /* Menu dropdown — fixed position so it escapes overflow */
  .menu-dropdown { position: fixed; top: auto; right: auto; left: 50%; transform: translateX(-50%); min-width: 200px; }
  .h-menu { position: static; }

  /* Forge sidebar compact on mobile */
  .forge-sidebar { gap: 0.6rem; }
  .forge-sidebar .section-label { margin-bottom: 0; }
  .forge-cats { flex-direction: row; flex-wrap: wrap; gap: 6px; }
  .forge-cats button { text-align: center; padding: 4px 10px; border: 1px solid #3f3f5c; font-size: 0.55rem; }
  .forge-cats button.active { border-left: none; border-color: #c4a0e8; background: #c4a0e8; color: #fff; }
  .forge-inv-mini { flex-direction: row; flex-wrap: wrap; gap: 4px; }
  .mini-item { padding: 4px 6px; font-size: 0.55rem; }

  /* Forge action panel → modal on mobile */
  .forge-action-panel {
    position: fixed; inset: 0; z-index: 1200;
    background: transparent; max-height: none;
    display: none; padding: 0; height: auto; overflow: visible;
  }
  .forge-action-panel.has-recipe {
    display: flex; align-items: center; justify-content: center;
  }
  .fap-mobile-backdrop {
    display: block; position: fixed; inset: 0; background: rgba(0,0,0,0.85);
  }
  .forge-action-panel .action-panel-inner {
    position: relative; z-index: 1;
    background: #fff; border: 2px solid #8a60b0;
    width: 92vw; max-width: 420px; max-height: 85vh;
    overflow-y: auto; padding: 1rem; box-shadow: 4px 4px 0 #c4a0e8;
  }
  .forge-action-panel .detail-idle { display: none; }

  /* Staking mobile */
  .view-staking { padding: 0.8rem; overflow: visible !important; max-width: 100%; box-sizing: border-box; }
  .stake-header h2 { font-size: 0.9rem; letter-spacing: 1px; }
  .stake-subtitle { font-size: 0.6rem; }
  .stake-plans { grid-template-columns: 1fr 1fr; gap: 0.6rem; max-width: 100%; }
  .stake-card { padding: 0.8rem 0.5rem; gap: 0.3rem; }
  .sc-icon { font-size: 1.6rem; margin-bottom: 0; }
  .sc-name { font-size: 0.65rem; letter-spacing: 1px; }
  .sc-ron { font-size: 0.9rem; }
  .sc-landwork { font-size: 0.95rem; }
  .sc-divider { width: 40px; margin: 0.2rem 0; }
  .sc-meta { gap: 0.4rem; font-size: 0.5rem; }
  .sc-phases { font-size: 0.45rem; }
  .stake-btn { padding: 0.6rem 1.5rem; font-size: 0.65rem; width: 100%; }
  .stake-active-panel { padding: 1rem; gap: 0.5rem; }
  .sap-icon { font-size: 2rem; }
  .sap-plan { font-size: 0.9rem; letter-spacing: 1px; }
  .sap-earned-val { font-size: 1.5rem; }
  .sap-cd-val { font-size: 1rem; }
  .sap-progress { max-width: 100%; }
  .sap-details { max-width: 100%; }
  .sap-row { font-size: 0.6rem; padding: 5px 0; }
  .stake-claim-btn { font-size: 0.6rem; padding: 0.5rem 1rem; width: 100%; }
}
@media (max-width: 480px) {
  .forge-sidebar { padding: 0.5rem; }
  .forge-main-grid { padding: 0.5rem; }
  .forge-action-panel .action-panel-inner { width: 96vw; padding: 0.8rem; max-height: 90vh; }
  .stake-plans { grid-template-columns: 1fr 1fr; gap: 0.5rem; }
  .stake-card { padding: 0.6rem; gap: 0.3rem; }
  .sc-icon { font-size: 1.6rem; }
  .sc-name { font-size: 0.75rem; letter-spacing: 1px; }
  .sc-ron { font-size: 0.95rem; }
  .sc-divider { display: none; }
  .sc-landwork { font-size: 0.95rem; }
  .sc-lw-label { font-size: 0.55rem; }
  .sc-meta { font-size: 0.55rem; gap: 0.3rem; }
  .sc-phases { display: none; }
}
</style>


