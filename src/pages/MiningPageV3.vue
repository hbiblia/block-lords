<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted, watch } from 'vue';
import { useAuthStore } from '@/stores/auth';
import { useMiningStore } from '@/stores/mining';
import { useInventoryStore } from '@/stores/inventory';
import { useMarketStore } from '@/stores/market';
import { playSound } from '@/utils/sounds';
import {
  repairRig, getRigCooling, getRigBoosts, getRigPower,
  removeCoolingFromRig, removeBoostFromRig, removePowerFromRig
} from '@/utils/api';
import {
  Pickaxe, Coins, Gem, Zap, Snowflake, Battery, Shield,
  Lock, Cpu, Flame, Wrench, Thermometer,
  Package, Users, X,
  TrendingUp, Activity, ChevronDown
} from 'lucide-vue-next';

const authStore = useAuthStore();
const miningStore = useMiningStore();
const inventoryStore = useInventoryStore();
const marketStore = useMarketStore();

// ── IDLE TICKER ──
const displayCoins = ref(0);
const coinsPerSecond = computed(() => {
  const hash = miningStore.effectiveHashrate || 0;
  const diff = miningStore.networkStats.difficulty || 1;
  return (hash / diff) * 0.5 * 0.033;
});

let tickerInterval: ReturnType<typeof setInterval> | null = null;
function startTicker() {
  displayCoins.value = authStore.player?.gamecoin_balance ?? 0;
  tickerInterval = setInterval(() => {
    if (coinsPerSecond.value > 0) displayCoins.value += coinsPerSecond.value;
  }, 1000);
}

// ── UPGRADE PANEL ──
type UpgradeTab = 'rigs' | 'cooling' | 'boosts';
const activeUpgradeTab = ref<UpgradeTab>('rigs');

// ── RIGS AS IDLE GENERATORS ──
const rigGenerators = computed(() => {
  return miningStore.rigs.map((rig, idx) => {
    const hash = miningStore.getRigEffectiveHashrate(rig);
    const income = (hash / (miningStore.networkStats.difficulty || 1)) * 0.5 * 0.033;
    return {
      id: rig.id,
      index: idx,
      name: rig.rig.name,
      tier: rig.rig.tier,
      active: rig.is_active,
      hashrate: Math.round(hash),
      baseHashrate: rig.rig.hashrate,
      incomePerSec: income,
      condition: Math.round(rig.condition),
      temperature: Math.round(rig.temperature),
      level: rig.hashrate_level || 1,
      mode: rig.mining_mode || 'pool',
      powerConsumption: rig.rig.power_consumption,
      internetConsumption: rig.rig.internet_consumption,
      repairCost: rig.rig.repair_cost,
      patchCount: rig.patch_count || 0,
      raw: rig
    };
  });
});

const activeRigs = computed(() => rigGenerators.value.filter(r => r.active).length);
const totalRigs = computed(() => rigGenerators.value.length);

// ── POOL PROGRESS ──
const sharesProgress = computed(() => Math.round(miningStore.sharesProgress));
const blockNumber = computed(() => miningStore.currentMiningBlock?.block_number || '---');
const blockReward = computed(() => miningStore.currentMiningBlock?.reward || 0);
const activeMiners = computed(() => miningStore.networkStats.activeMiners);
const effectiveHashrate = computed(() => miningStore.effectiveHashrate);
const blockTimeRemaining = computed(() => miningStore.blockTimeRemaining);

// ── ENERGY & RESOURCES ──
const energyPct = computed(() => {
  const e = authStore.player?.energy ?? 0;
  return Math.min(100, (e / (authStore.effectiveMaxEnergy || 100)) * 100);
});
const internetPct = computed(() => {
  const i = authStore.player?.internet ?? 0;
  return Math.min(100, (i / (authStore.effectiveMaxInternet || 100)) * 100);
});

// ══════════════════════════════════════
// RIG DETAIL DRAWER
// ══════════════════════════════════════
const selectedRigId = ref<string | null>(null);
const drawerTab = ref<'status' | 'modules'>('status');
const drawerLoading = ref(false);
const repairing = ref(false);

// Installed components for selected rig
const installedCooling = ref<any[]>([]);
const installedBoosts = ref<any[]>([]);
const installedPower = ref<any[]>([]);

const selectedRig = computed(() => rigGenerators.value.find(r => r.id === selectedRigId.value));

async function openRigDrawer(rig: any) {
  playSound('click');
  if (selectedRigId.value === rig.id) {
    selectedRigId.value = null;
    return;
  }
  selectedRigId.value = rig.id;
  drawerTab.value = 'status';
  drawerLoading.value = true;
  try {
    const [cooling, boosts, power] = await Promise.all([
      getRigCooling(rig.id),
      getRigBoosts(rig.id),
      getRigPower(rig.id),
    ]);
    installedCooling.value = cooling ?? [];
    installedBoosts.value = boosts ?? [];
    installedPower.value = power ?? [];
  } catch (e) {
    console.error(e);
  }
  drawerLoading.value = false;
}

function closeDrawer() {
  playSound('click');
  selectedRigId.value = null;
}

// ── DRAWER ACTIONS ──
async function handleToggleRig() {
  if (!selectedRig.value) return;
  playSound('click');
  try {
    await miningStore.toggleRig(selectedRig.value.id, selectedRig.value.mode);
  } catch (e) { console.error(e); }
}

async function handleToggleMode(mode: 'pool' | 'solo') {
  if (!selectedRig.value) return;
  playSound('click');
  try {
    await miningStore.toggleRig(selectedRig.value.id, mode);
  } catch (e) { console.error(e); }
}

async function handleRepair() {
  if (!selectedRig.value || !authStore.player) return;
  playSound('click');
  repairing.value = true;
  try {
    await repairRig(authStore.player.id, selectedRig.value.id);
    await miningStore.loadData();
    await authStore.fetchPlayer();
  } catch (e) { console.error(e); }
  repairing.value = false;
}

async function handleEjectCooling(coolingId: string) {
  if (!selectedRig.value || !authStore.player) return;
  playSound('click');
  try {
    await removeCoolingFromRig(authStore.player.id, selectedRig.value.id, coolingId);
    installedCooling.value = installedCooling.value.filter(c => c.id !== coolingId);
    await miningStore.loadData();
  } catch (e) { console.error(e); }
}

async function handleEjectBoost(boostId: string) {
  if (!selectedRig.value || !authStore.player) return;
  playSound('click');
  try {
    await removeBoostFromRig(authStore.player.id, selectedRig.value.id, boostId);
    installedBoosts.value = installedBoosts.value.filter(b => b.id !== boostId);
    await miningStore.loadData();
  } catch (e) { console.error(e); }
}

async function handleEjectPower(powerId: string) {
  if (!selectedRig.value || !authStore.player) return;
  playSound('click');
  try {
    await removePowerFromRig(authStore.player.id, selectedRig.value.id, powerId);
    installedPower.value = installedPower.value.filter(p => p.id !== powerId);
    await miningStore.loadData();
  } catch (e) { console.error(e); }
}

function formatBoostTime(seconds: number): string {
  if (seconds >= 3600) return Math.floor(seconds / 3600) + 'h ' + Math.floor((seconds % 3600) / 60) + 'm';
  return Math.floor(seconds / 60) + 'm ' + Math.floor(seconds % 60) + 's';
}

// ── GENERAL ACTIONS ──
async function startAllRigs() {
  playSound('click');
  const idle = miningStore.rigs.filter(r => !r.is_active && r.condition > 20);
  for (const rig of idle) {
    try { await miningStore.toggleRig(rig.id, 'pool'); } catch (e) { console.error(e); }
  }
}

// ── UPGRADE LIST ──
const upgradeItems = computed(() => {
  if (activeUpgradeTab.value === 'rigs') {
    return (marketStore.rigs || []).map((m: any) => ({
      id: m.id, name: m.name, stat: `+${m.hashrate || 0} H/s`,
      price: m.base_price, currency: m.currency || 'gamecoin',
      tier: m.tier || 'common', icon: 'rig',
      locked: (authStore.player?.level ?? 1) < tierMinLevel(m.tier),
      lockLevel: tierMinLevel(m.tier), raw: m
    }));
  }
  if (activeUpgradeTab.value === 'cooling') {
    return (marketStore.coolingItems || []).map((m: any) => ({
      id: m.id, name: m.name, stat: `-${m.cooling_power || 0}°C`,
      price: m.price, currency: m.currency || 'gamecoin',
      tier: m.tier || 'common', icon: 'cooling',
      locked: (authStore.player?.level ?? 1) < tierMinLevel(m.tier),
      lockLevel: tierMinLevel(m.tier), raw: m
    }));
  }
  return (marketStore.boostItems || []).map((m: any) => ({
    id: m.id, name: m.name, stat: `+${m.effect_value || 0}%`,
    price: m.price, currency: m.currency || 'gamecoin',
    tier: m.tier || 'common', icon: 'boost',
    locked: (authStore.player?.level ?? 1) < tierMinLevel(m.tier),
    lockLevel: tierMinLevel(m.tier), raw: m
  }));
});

function tierMinLevel(tier: string): number {
  if (tier === 'legendary') return 50;
  if (tier === 'epic') return 30;
  if (tier === 'rare') return 15;
  if (tier === 'uncommon') return 5;
  return 1;
}

function tierColor(tier: string): string {
  if (tier === 'legendary') return '#f59e0b';
  if (tier === 'epic') return '#a855f7';
  if (tier === 'rare') return '#06b6d4';
  if (tier === 'uncommon') return '#22c55e';
  return '#71717a';
}

function formatNum(n: number): string {
  if (n >= 1_000_000) return (n / 1_000_000).toFixed(1) + 'M';
  if (n >= 1_000) return (n / 1_000).toFixed(1) + 'K';
  return n.toFixed(n < 10 ? 2 : 0);
}

// ── LIFECYCLE ──
let pollInterval: ReturnType<typeof setInterval> | null = null;
onMounted(async () => {
  if (authStore.player) {
    miningStore.loadData();
    inventoryStore.fetchInventory();
    marketStore.loadData();
  }
  startTicker();
  pollInterval = setInterval(() => { miningStore.loadMiningBlockInfo(); }, 30000);
});
onUnmounted(() => {
  if (tickerInterval) clearInterval(tickerInterval);
  if (pollInterval) clearInterval(pollInterval);
});
watch(() => authStore.player?.gamecoin_balance, (val) => {
  if (val !== undefined) displayCoins.value = val;
});
</script>

<template>
  <div class="idle-root">
    <div class="idle-scanlines"></div>

    <!-- ═══════ TOP: CURRENCY + LEVEL ═══════ -->
    <header class="idle-top">
      <div class="idle-cur"><Coins :size="14" class="cur-icon gold" /><span class="cur-val gold">{{ formatNum(displayCoins) }}</span></div>
      <div class="idle-cur"><Pickaxe :size="14" class="cur-icon amber" /><span class="cur-val">{{ formatNum(authStore.player?.landwork ?? 0) }}</span></div>
      <div class="idle-cur"><Gem :size="14" class="cur-icon cyan" /><span class="cur-val">{{ formatNum(authStore.player?.ron_balance ?? 0) }}</span></div>
      <div class="idle-lvl">LV{{ authStore.player?.level ?? 1 }}</div>
    </header>

    <!-- ═══════ HERO: MAIN IDLE DISPLAY ═══════ -->
    <section class="idle-hero">
      <div class="idle-income">
        <span class="income-label">HASHRATE</span>
        <span class="income-big">{{ formatNum(effectiveHashrate) }}<small>H/s</small></span>
        <span class="income-persec" v-if="coinsPerSecond > 0">
          <TrendingUp :size="12" /> +{{ coinsPerSecond.toFixed(4) }} coins/s
        </span>
      </div>

      <!-- RIG VISUAL NODES -->
      <div class="idle-rigs-visual">
        <div
          v-for="rig in rigGenerators" :key="rig.id"
          class="idle-rig-node"
          :class="{ active: rig.active, hot: rig.temperature > 70, critical: rig.condition < 25, selected: selectedRigId === rig.id }"
          @click="openRigDrawer(rig)"
        >
          <div class="rig-pulse" v-if="rig.active"></div>
          <Cpu :size="20" />
          <span class="rig-hash">{{ rig.hashrate }}</span>
          <div class="rig-bars">
            <div class="rig-bar"><div class="rig-bar-fill" :style="{ width: rig.condition + '%' }" :class="{ low: rig.condition < 30 }"></div></div>
            <div class="rig-bar"><div class="rig-bar-fill hot" :style="{ width: rig.temperature + '%' }"></div></div>
          </div>
        </div>
        <div v-if="miningStore.slotInfo?.available_slots" class="idle-rig-node empty"><span class="empty-plus">+</span></div>
      </div>

      <button v-if="activeRigs < totalRigs" class="idle-start-all" @click="startAllRigs">
        <Zap :size="14" /> INICIAR TODOS ({{ totalRigs - activeRigs }})
      </button>
      <div v-else class="idle-all-running"><Activity :size="12" /> {{ activeRigs }}/{{ totalRigs }} ACTIVOS</div>
    </section>

    <!-- ═══════ BLOCK PROGRESS ═══════ -->
    <section class="idle-block">
      <div class="block-header">
        <span class="block-label">BLOQUE #{{ blockNumber }}</span>
        <span class="block-timer">{{ blockTimeRemaining }}</span>
      </div>
      <div class="block-track"><div class="block-fill" :style="{ width: sharesProgress + '%' }"></div><div class="block-glow"></div></div>
      <div class="block-footer">
        <span><Users :size="10" /> {{ activeMiners }}</span>
        <span class="block-reward"><Coins :size="10" /> {{ blockReward }}</span>
        <span>{{ sharesProgress }}%</span>
      </div>
    </section>

    <!-- ═══════ RESOURCES ═══════ -->
    <section class="idle-resources">
      <div class="res-item">
        <span class="res-label"><Zap :size="10" /> NRG</span>
        <div class="res-track"><div class="res-fill energy" :style="{ width: energyPct + '%' }"></div></div>
        <span class="res-val">{{ Math.floor(authStore.player?.energy ?? 0) }}%</span>
      </div>
      <div class="res-item">
        <span class="res-label"><Activity :size="10" /> NET</span>
        <div class="res-track"><div class="res-fill net" :style="{ width: internetPct + '%' }"></div></div>
        <span class="res-val">{{ Math.floor(authStore.player?.internet ?? 0) }}%</span>
      </div>
    </section>

    <!-- ═══════ UPGRADE PANEL (when no rig selected) ═══════ -->
    <section v-if="!selectedRigId" class="idle-upgrades">
      <div class="upgrade-tabs">
        <button :class="{ active: activeUpgradeTab === 'rigs' }" @click="activeUpgradeTab = 'rigs'"><Pickaxe :size="14" /> RIGS</button>
        <button :class="{ active: activeUpgradeTab === 'cooling' }" @click="activeUpgradeTab = 'cooling'"><Snowflake :size="14" /> COOL</button>
        <button :class="{ active: activeUpgradeTab === 'boosts' }" @click="activeUpgradeTab = 'boosts'"><Flame :size="14" /> BOOST</button>
      </div>
      <div class="upgrade-list">
        <div v-for="item in upgradeItems" :key="item.id" class="upgrade-row" :class="{ locked: item.locked }">
          <div class="up-icon" :style="{ borderColor: tierColor(item.tier) + '40' }">
            <component :is="item.icon === 'rig' ? Pickaxe : item.icon === 'cooling' ? Snowflake : Flame" :size="18" :style="{ color: tierColor(item.tier) }" />
          </div>
          <div class="up-info">
            <span class="up-name">{{ item.name }}</span>
            <span class="up-stat" :style="{ color: tierColor(item.tier) }">{{ item.stat }}</span>
          </div>
          <div class="up-action">
            <template v-if="item.locked"><Lock :size="12" /><span class="up-lock-lvl">LV{{ item.lockLevel }}</span></template>
            <template v-else>
              <button class="up-buy-btn">
                <component :is="item.currency === 'ron' ? Gem : item.currency === 'crypto' ? Pickaxe : Coins" :size="10" />
                {{ formatNum(item.price) }}
              </button>
            </template>
          </div>
        </div>
        <div v-if="upgradeItems.length === 0" class="upgrade-empty"><Package :size="24" style="opacity: 0.3" /><span>SIN DATOS</span></div>
      </div>
    </section>

    <!-- ══════════════════════════════════════════
         RIG DETAIL DRAWER (replaces upgrades)
         ══════════════════════════════════════════ -->
    <section v-if="selectedRigId && selectedRig" class="rig-drawer">
      <!-- DRAWER HEADER -->
      <div class="rd-header">
        <div class="rd-title">
          <Cpu :size="16" :style="{ color: selectedRig.active ? '#22c55e' : '#52525b' }" />
          <span class="rd-name">{{ selectedRig.name }}</span>
          <span class="rd-mode" :class="selectedRig.mode">{{ selectedRig.mode.toUpperCase() }}</span>
        </div>
        <button class="rd-close" @click="closeDrawer"><ChevronDown :size="16" /></button>
      </div>

      <!-- DRAWER TABS -->
      <div class="rd-tabs">
        <button :class="{ active: drawerTab === 'status' }" @click="drawerTab = 'status'">ESTADO</button>
        <button :class="{ active: drawerTab === 'modules' }" @click="drawerTab = 'modules'">MODULOS</button>
      </div>

      <!-- DRAWER CONTENT -->
      <div class="rd-body">
        <div v-if="drawerLoading" class="rd-loading">SINCRONIZANDO...</div>

        <!-- ── STATUS TAB ── -->
        <template v-else-if="drawerTab === 'status'">
          <!-- Gauges -->
          <div class="rd-gauges">
            <!-- TEMPERATURE -->
            <div class="rd-gauge" :class="{ warn: selectedRig.temperature > 70, danger: selectedRig.temperature > 85 }">
              <div class="gauge-head">
                <Thermometer :size="12" />
                <span class="gauge-label">TEMPERATURA</span>
                <span class="gauge-val" :class="{ hot: selectedRig.temperature > 70 }">{{ selectedRig.temperature }}°C</span>
              </div>
              <div class="gauge-track">
                <div class="gauge-fill temp" :style="{ width: selectedRig.temperature + '%' }"></div>
                <div class="gauge-segments"></div>
              </div>
              <span class="gauge-status">{{ selectedRig.temperature > 85 ? 'CRITICO' : selectedRig.temperature > 70 ? 'ELEVADO' : 'NOMINAL' }}</span>
            </div>

            <!-- CONDITION -->
            <div class="rd-gauge" :class="{ warn: selectedRig.condition < 50, danger: selectedRig.condition < 25 }">
              <div class="gauge-head">
                <Shield :size="12" />
                <span class="gauge-label">INTEGRIDAD</span>
                <span class="gauge-val" :class="{ low: selectedRig.condition < 30 }">{{ selectedRig.condition }}%</span>
              </div>
              <div class="gauge-track">
                <div class="gauge-fill cond" :style="{ width: selectedRig.condition + '%' }" :class="{ critical: selectedRig.condition < 25 }"></div>
                <div class="gauge-segments"></div>
              </div>
              <span class="gauge-status">{{ selectedRig.condition < 25 ? 'FALLANDO' : selectedRig.condition < 50 ? 'DEGRADADO' : 'OPERATIVO' }}</span>
            </div>
          </div>

          <!-- Stats grid -->
          <div class="rd-stats">
            <div class="rd-stat-row">
              <span class="stat-label"><Zap :size="10" /> HASHRATE</span>
              <span class="stat-val amber">{{ selectedRig.hashrate }} H/s</span>
            </div>
            <div class="rd-stat-row">
              <span class="stat-label"><Cpu :size="10" /> BASE</span>
              <span class="stat-val">{{ selectedRig.baseHashrate }} H/s</span>
            </div>
            <div class="rd-stat-row">
              <span class="stat-label"><Battery :size="10" /> CONSUMO</span>
              <span class="stat-val">{{ selectedRig.powerConsumption }}W</span>
            </div>
            <div class="rd-stat-row">
              <span class="stat-label"><Activity :size="10" /> INTERNET</span>
              <span class="stat-val">{{ selectedRig.internetConsumption }}Mb</span>
            </div>
            <div class="rd-stat-row" v-if="selectedRig.patchCount > 0">
              <span class="stat-label"><Wrench :size="10" /> PARCHES</span>
              <span class="stat-val warn">x{{ selectedRig.patchCount }} (-{{ selectedRig.patchCount * 10 }}%)</span>
            </div>
            <div class="rd-stat-row">
              <span class="stat-label"><TrendingUp :size="10" /> INCOME</span>
              <span class="stat-val green">+{{ selectedRig.incomePerSec.toFixed(4) }}/s</span>
            </div>
          </div>

          <!-- Installed modules summary -->
          <div class="rd-modules-summary">
            <div class="rms-item">
              <Snowflake :size="10" class="rms-icon cyan" />
              <span>COOLING</span>
              <span class="rms-val" :class="{ dim: !installedCooling.length }">{{ installedCooling.length || 'NONE' }}</span>
            </div>
            <div class="rms-item">
              <Battery :size="10" class="rms-icon amber" />
              <span>POWER</span>
              <span class="rms-val" :class="{ dim: !installedPower.length }">{{ installedPower.length || 'NONE' }}</span>
            </div>
            <div class="rms-item">
              <Flame :size="10" class="rms-icon green" />
              <span>BOOSTS</span>
              <span class="rms-val" :class="{ dim: !installedBoosts.length }">{{ installedBoosts.length || 'NONE' }}</span>
            </div>
          </div>
        </template>

        <!-- ── MODULES TAB ── -->
        <template v-else-if="drawerTab === 'modules'">
          <!-- Cooling -->
          <div v-if="installedCooling.length" class="rd-mod-section">
            <span class="rd-mod-label"><Snowflake :size="10" /> COOLING ({{ installedCooling.length }})</span>
            <div v-for="c in installedCooling" :key="c.id" class="rd-mod-item">
              <div class="mod-info">
                <span class="mod-name">{{ c.name }}</span>
                <div class="mod-stats">
                  <span>HP {{ Math.round(c.durability) }}</span>
                  <span>PWR +{{ c.effective_cooling_power || c.cooling_power }}</span>
                  <span>NRG -{{ c.effective_energy_cost || c.energy_cost }}</span>
                </div>
                <div class="mod-bar"><div class="mod-bar-fill cyan" :style="{ width: c.durability + '%' }" :class="{ low: c.durability < 25 }"></div></div>
              </div>
              <button class="mod-eject" @click="handleEjectCooling(c.id)">EJECT</button>
            </div>
          </div>

          <!-- Power -->
          <div v-if="installedPower.length" class="rd-mod-section">
            <span class="rd-mod-label"><Battery :size="10" /> POWER ({{ installedPower.length }})</span>
            <div v-for="p in installedPower" :key="p.id" class="rd-mod-item">
              <div class="mod-info">
                <span class="mod-name">{{ p.power_name }}</span>
                <div class="mod-stats"><span>SUPPLY +{{ p.power_supply }}W</span></div>
                <div class="mod-bar"><div class="mod-bar-fill amber" :style="{ width: p.durability + '%' }" :class="{ low: p.durability < 25 }"></div></div>
              </div>
              <button class="mod-eject" @click="handleEjectPower(p.id)">EJECT</button>
            </div>
          </div>

          <!-- Boosts -->
          <div v-if="installedBoosts.length" class="rd-mod-section">
            <span class="rd-mod-label"><Flame :size="10" /> BOOSTS ({{ installedBoosts.length }})</span>
            <div v-for="b in installedBoosts" :key="b.id" class="rd-mod-item">
              <div class="mod-info">
                <span class="mod-name">{{ b.name }}</span>
                <div class="mod-stats">
                  <span>{{ b.boost_type?.toUpperCase() }} +{{ b.effect_value }}%</span>
                  <span>{{ formatBoostTime(b.remaining_seconds) }}</span>
                  <span v-if="b.stack_count > 1">x{{ b.stack_count }}</span>
                </div>
                <div class="mod-bar"><div class="mod-bar-fill green" :style="{ width: Math.min(100, (b.remaining_seconds / 3600) * 100) + '%' }"></div></div>
              </div>
              <button class="mod-eject" @click="handleEjectBoost(b.id)">EJECT</button>
            </div>
          </div>

          <!-- Empty -->
          <div v-if="!installedCooling.length && !installedPower.length && !installedBoosts.length" class="rd-mod-empty">
            <Package :size="20" style="opacity: 0.3" />
            <span>SIN MODULOS</span>
            <small>Forja componentes e instálalos aquí</small>
          </div>
        </template>
      </div>

      <!-- DRAWER ACTIONS -->
      <div class="rd-actions">
        <template v-if="selectedRig.active">
          <button class="rd-btn halt" @click="handleToggleRig">
            <X :size="12" /> DETENER
          </button>
        </template>
        <template v-else>
          <button class="rd-btn pool" @click="handleToggleMode('pool')">
            <Zap :size="12" /> POOL
          </button>
          <button class="rd-btn solo" @click="handleToggleMode('solo')">
            <Pickaxe :size="12" /> SOLO
          </button>
        </template>
        <button
          class="rd-btn repair"
          :disabled="repairing || selectedRig.condition >= 100"
          @click="handleRepair"
        >
          <Wrench :size="12" /> {{ repairing ? '...' : 'REPARAR' }}
          <span class="repair-cost"><Coins :size="9" /> {{ selectedRig.repairCost }}</span>
        </button>
      </div>
    </section>
  </div>
</template>

<style scoped>
@import url('https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@500;700;800;900&display=swap');

/* ═══════════════════════════════════ ROOT ═══════════════════════════════════ */
.idle-root {
  position: fixed; inset: 0;
  background: #0f1023;
  background-image: radial-gradient(circle, #1a1b30 1px, transparent 1px);
  background-size: 20px 20px;
  color: #a1a1aa;
  font-family: 'JetBrains Mono', monospace;
  display: flex; flex-direction: column;
  overflow-y: auto; overflow-x: hidden;
  z-index: 50;
}

.idle-scanlines {
  position: fixed; inset: 0;
  background: repeating-linear-gradient(0deg, transparent, transparent 2px, rgba(0,0,0,0.03) 2px, rgba(0,0,0,0.03) 4px);
  pointer-events: none; z-index: 200; opacity: 0.3;
}

/* ═══════════════════════════════════ TOP BAR ═══════════════════════════════════ */
.idle-top {
  display: flex; align-items: center; justify-content: center;
  gap: 0.5rem; padding: 0.5rem 0.8rem;
  background: #13142a; border-bottom: 2px solid #1e1f3a;
  flex-shrink: 0; z-index: 10;
}
.idle-cur {
  display: flex; align-items: center; gap: 3px;
  font-size: 0.7rem; font-weight: 800;
  background: rgba(255,255,255,0.03);
  border: 1px solid #1e1f3a; padding: 3px 8px;
}
.cur-icon.gold { color: #f59e0b; }
.cur-icon.amber { color: #d97706; }
.cur-icon.cyan { color: #06b6d4; }
.cur-val { letter-spacing: 0.5px; color: #d4d4d8; }
.cur-val.gold { color: #fbbf24; }
.idle-lvl {
  font-size: 0.6rem; font-weight: 900; color: #f59e0b; letter-spacing: 1px;
  background: rgba(245,158,11,0.1); border: 1px solid rgba(245,158,11,0.25); padding: 3px 8px;
}

/* ═══════════════════════════════════ HERO ═══════════════════════════════════ */
.idle-hero { display: flex; flex-direction: column; align-items: center; padding: 1.2rem 1rem 0.8rem; flex-shrink: 0; }
.idle-income { display: flex; flex-direction: column; align-items: center; margin-bottom: 1rem; }
.income-label { font-size: 0.5rem; font-weight: 900; letter-spacing: 3px; color: #52525b; margin-bottom: 2px; }
.income-big { font-size: 2.2rem; font-weight: 900; color: #fff; text-shadow: 0 0 30px rgba(245,158,11,0.15); line-height: 1; }
.income-big small { font-size: 0.8rem; color: #71717a; margin-left: 2px; }
.income-persec { display: flex; align-items: center; gap: 4px; font-size: 0.65rem; font-weight: 800; color: #22c55e; margin-top: 4px; animation: idle-glow 2s ease-in-out infinite alternate; }
@keyframes idle-glow { from { opacity: 0.6; } to { opacity: 1; } }

/* ═══════════════════════════════════ RIG NODES ═══════════════════════════════════ */
.idle-rigs-visual { display: flex; flex-wrap: wrap; justify-content: center; gap: 0.5rem; max-width: 360px; }
.idle-rig-node {
  width: 64px; height: 72px; background: #15162e; border: 1px solid #2a2b48;
  display: flex; flex-direction: column; align-items: center; justify-content: center;
  gap: 2px; cursor: pointer; transition: all 0.2s; position: relative; color: #52525b;
}
.idle-rig-node:hover { border-color: #4f4f6f; background: #1a1b36; }
.idle-rig-node.active { border-color: rgba(34,197,94,0.3); color: #22c55e; background: rgba(34,197,94,0.03); }
.idle-rig-node.selected { border-color: #f59e0b; background: rgba(245,158,11,0.04); box-shadow: 0 0 12px rgba(245,158,11,0.1); }
.idle-rig-node.hot { border-color: rgba(239,68,68,0.3); }
.idle-rig-node.critical { animation: idle-shake 0.5s infinite; }
@keyframes idle-shake { 0%, 100% { transform: translateX(0); } 25% { transform: translateX(1px); } 75% { transform: translateX(-1px); } }
.rig-pulse { position: absolute; inset: -1px; border: 1px solid rgba(34,197,94,0.15); animation: rig-pulse-anim 2s ease-in-out infinite; pointer-events: none; }
@keyframes rig-pulse-anim { 0%, 100% { opacity: 0; transform: scale(1); } 50% { opacity: 1; transform: scale(1.03); } }
.rig-hash { font-size: 0.55rem; font-weight: 900; letter-spacing: 0.5px; }
.rig-bars { display: flex; flex-direction: column; gap: 1px; width: 80%; margin-top: 2px; }
.rig-bar { height: 2px; background: #1a1b2e; overflow: hidden; }
.rig-bar-fill { height: 100%; transition: width 0.5s; background: linear-gradient(90deg, #166534, #22c55e); }
.rig-bar-fill.low { background: linear-gradient(90deg, #7f1d1d, #ef4444); }
.rig-bar-fill.hot { background: linear-gradient(90deg, #92400e, #f59e0b); }
.idle-rig-node.empty { border-style: dashed; border-color: #2a2b48; opacity: 0.4; }
.empty-plus { font-size: 1.2rem; color: #4f4f6f; }

.idle-start-all {
  display: flex; align-items: center; gap: 6px; margin-top: 0.8rem;
  background: rgba(34,197,94,0.08); border: 1px solid rgba(34,197,94,0.3);
  color: #22c55e; font-size: 0.6rem; font-weight: 900; font-family: inherit;
  letter-spacing: 1px; padding: 6px 16px; cursor: pointer; transition: 0.2s;
}
.idle-start-all:hover { background: rgba(34,197,94,0.15); border-color: #22c55e; }
.idle-all-running { display: flex; align-items: center; gap: 6px; margin-top: 0.8rem; font-size: 0.55rem; font-weight: 800; color: #22c55e; letter-spacing: 1px; opacity: 0.7; }

/* ═══════════════════════════════════ BLOCK ═══════════════════════════════════ */
.idle-block { margin: 0 0.8rem; padding: 0.6rem 0.8rem; background: #13142a; border: 1px solid #1e1f3a; flex-shrink: 0; }
.block-header { display: flex; justify-content: space-between; margin-bottom: 4px; }
.block-label { font-size: 0.55rem; font-weight: 900; color: #71717a; letter-spacing: 1px; }
.block-timer { font-size: 0.6rem; font-weight: 900; color: #fff; letter-spacing: 0.5px; }
.block-track { height: 6px; background: #1a1b2e; border: 1px solid #2a2b48; overflow: hidden; position: relative; }
.block-fill { height: 100%; background: linear-gradient(90deg, #854d0e, #f59e0b); transition: width 0.5s; position: relative; z-index: 2; box-shadow: 0 0 8px rgba(245,158,11,0.3); }
.block-glow { position: absolute; inset: 0; background: repeating-linear-gradient(90deg, transparent 0 10px, rgba(255,255,255,0.03) 10px 11px); animation: block-scroll 3s infinite linear; z-index: 1; }
@keyframes block-scroll { from { background-position: 0 0; } to { background-position: 100px 0; } }
.block-footer { display: flex; justify-content: space-between; font-size: 0.5rem; font-weight: 800; color: #52525b; margin-top: 4px; }
.block-footer span { display: flex; align-items: center; gap: 3px; }
.block-reward { color: #f59e0b; }

/* ═══════════════════════════════════ RESOURCES ═══════════════════════════════════ */
.idle-resources { display: flex; gap: 0.5rem; margin: 0.5rem 0.8rem; flex-shrink: 0; }
.res-item { flex: 1; display: flex; align-items: center; gap: 6px; background: #13142a; border: 1px solid #1e1f3a; padding: 5px 8px; }
.res-label { font-size: 0.45rem; font-weight: 900; color: #52525b; letter-spacing: 1px; white-space: nowrap; display: flex; align-items: center; gap: 3px; }
.res-track { flex: 1; height: 4px; background: #1a1b2e; border: 1px solid #2a2b48; overflow: hidden; }
.res-fill { height: 100%; transition: width 0.5s; }
.res-fill.energy { background: linear-gradient(90deg, #854d0e, #f59e0b); }
.res-fill.net { background: linear-gradient(90deg, #164e63, #06b6d4); }
.res-val { font-size: 0.6rem; font-weight: 900; color: #a1a1aa; min-width: 26px; text-align: right; }

/* ═══════════════════════════════════ UPGRADES ═══════════════════════════════════ */
.idle-upgrades { flex: 1; display: flex; flex-direction: column; margin: 0 0.8rem 0.8rem; background: #13142a; border: 1px solid #1e1f3a; min-height: 0; overflow: hidden; }
.upgrade-tabs { display: flex; border-bottom: 1px solid #1e1f3a; flex-shrink: 0; }
.upgrade-tabs button {
  flex: 1; display: flex; align-items: center; justify-content: center; gap: 4px; padding: 0.55rem 0;
  background: transparent; border: none; border-bottom: 2px solid transparent;
  color: #52525b; font-size: 0.55rem; font-weight: 900; font-family: inherit; letter-spacing: 1px; cursor: pointer; transition: 0.2s;
}
.upgrade-tabs button:hover { color: #a1a1aa; }
.upgrade-tabs button.active { color: #f59e0b; border-bottom-color: #f59e0b; background: rgba(245,158,11,0.03); }
.upgrade-list { flex: 1; overflow-y: auto; display: flex; flex-direction: column; }
.upgrade-list::-webkit-scrollbar { width: 3px; }
.upgrade-list::-webkit-scrollbar-thumb { background: #2a2b48; }
.upgrade-row { display: flex; align-items: center; gap: 0.6rem; padding: 0.6rem 0.7rem; border-bottom: 1px solid #1a1b30; transition: background 0.15s; }
.upgrade-row:hover { background: rgba(255,255,255,0.02); }
.upgrade-row.locked { opacity: 0.35; }
.up-icon { width: 38px; height: 38px; background: rgba(255,255,255,0.02); border: 1px solid #2a2b48; display: flex; align-items: center; justify-content: center; flex-shrink: 0; }
.up-info { flex: 1; display: flex; flex-direction: column; gap: 1px; min-width: 0; }
.up-name { font-size: 0.6rem; font-weight: 800; color: #d4d4d8; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.up-stat { font-size: 0.55rem; font-weight: 900; letter-spacing: 0.5px; }
.up-action { display: flex; align-items: center; gap: 4px; flex-shrink: 0; }
.up-lock-lvl { font-size: 0.5rem; font-weight: 900; color: #52525b; letter-spacing: 1px; }
.up-buy-btn {
  display: flex; align-items: center; gap: 3px; background: rgba(245,158,11,0.06);
  border: 1px solid rgba(245,158,11,0.25); color: #f59e0b; font-size: 0.6rem; font-weight: 900;
  font-family: inherit; letter-spacing: 0.5px; padding: 5px 10px; cursor: pointer; transition: 0.2s;
}
.up-buy-btn:hover { background: rgba(245,158,11,0.12); border-color: #f59e0b; box-shadow: 0 0 10px rgba(245,158,11,0.1); }
.upgrade-empty { flex: 1; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 0.5rem; color: #3f3f5c; font-size: 0.65rem; font-weight: 800; letter-spacing: 2px; }

/* ═══════════════════════════════════════════════════════════════════════════════
   RIG DETAIL DRAWER
   ═══════════════════════════════════════════════════════════════════════════════ */
.rig-drawer {
  flex: 1; display: flex; flex-direction: column;
  margin: 0 0.8rem 0.8rem;
  background: #13142a; border: 1px solid #1e1f3a;
  min-height: 0; overflow: hidden;
  animation: drawer-slide 0.25s ease-out;
}

@keyframes drawer-slide {
  from { opacity: 0; transform: translateY(10px); }
  to { opacity: 1; transform: translateY(0); }
}

/* Drawer Header */
.rd-header {
  display: flex; align-items: center; justify-content: space-between;
  padding: 0.6rem 0.8rem;
  background: #15162e; border-bottom: 1px solid #1e1f3a;
  flex-shrink: 0;
}
.rd-title { display: flex; align-items: center; gap: 6px; }
.rd-name { font-size: 0.7rem; font-weight: 900; color: #e5e7eb; letter-spacing: 0.5px; }
.rd-mode {
  font-size: 0.45rem; font-weight: 900; letter-spacing: 1.5px; padding: 2px 6px;
  border: 1px solid #2a2b48; color: #71717a;
}
.rd-mode.pool { color: #06b6d4; border-color: rgba(6,182,212,0.3); }
.rd-mode.solo { color: #f59e0b; border-color: rgba(245,158,11,0.3); }
.rd-close {
  background: transparent; border: 1px solid #2a2b48; color: #52525b;
  width: 28px; height: 28px; display: flex; align-items: center; justify-content: center;
  cursor: pointer; transition: 0.2s;
}
.rd-close:hover { border-color: #71717a; color: #a1a1aa; }

/* Drawer Tabs */
.rd-tabs { display: flex; border-bottom: 1px solid #1e1f3a; flex-shrink: 0; }
.rd-tabs button {
  flex: 1; padding: 0.45rem; background: transparent; border: none;
  border-bottom: 2px solid transparent;
  color: #52525b; font-size: 0.5rem; font-weight: 900; font-family: inherit;
  letter-spacing: 1.5px; cursor: pointer; transition: 0.2s;
}
.rd-tabs button:hover { color: #a1a1aa; }
.rd-tabs button.active { color: #f59e0b; border-bottom-color: #f59e0b; }

/* Drawer Body */
.rd-body {
  flex: 1; overflow-y: auto; padding: 0.6rem;
  display: flex; flex-direction: column; gap: 0.5rem;
}
.rd-body::-webkit-scrollbar { width: 3px; }
.rd-body::-webkit-scrollbar-thumb { background: #2a2b48; }
.rd-loading { text-align: center; color: #52525b; font-size: 0.6rem; font-weight: 800; letter-spacing: 1px; padding: 2rem 0; }

/* ── GAUGES ── */
.rd-gauges { display: flex; flex-direction: column; gap: 0.5rem; }
.rd-gauge {
  background: #15162e; border: 1px solid #1e1f3a; padding: 0.5rem 0.6rem;
  border-left: 2px solid #2a2b48;
}
.rd-gauge.warn { border-left-color: #f59e0b; }
.rd-gauge.danger { border-left-color: #ef4444; }
.gauge-head { display: flex; align-items: center; gap: 6px; margin-bottom: 4px; }
.gauge-label { flex: 1; font-size: 0.5rem; font-weight: 900; color: #71717a; letter-spacing: 1.5px; }
.gauge-val { font-size: 0.75rem; font-weight: 900; color: #e5e7eb; font-family: 'JetBrains Mono', monospace; }
.gauge-val.hot { color: #f59e0b; }
.gauge-val.low { color: #ef4444; }
.gauge-track { height: 5px; background: #0f1023; border: 1px solid #2a2b48; overflow: hidden; position: relative; }
.gauge-fill { height: 100%; transition: width 0.5s; position: relative; z-index: 2; }
.gauge-fill.temp { background: linear-gradient(90deg, #854d0e, #f59e0b); box-shadow: 0 0 6px rgba(245,158,11,0.3); }
.gauge-fill.cond { background: linear-gradient(90deg, #166534, #22c55e); box-shadow: 0 0 6px rgba(34,197,94,0.3); }
.gauge-fill.critical { background: linear-gradient(90deg, #7f1d1d, #ef4444); box-shadow: 0 0 6px rgba(239,68,68,0.4); }
.gauge-segments {
  position: absolute; inset: 0; pointer-events: none;
  background: repeating-linear-gradient(90deg, transparent 0, transparent 18%, rgba(15,16,35,0.7) 18%, rgba(15,16,35,0.7) 20%);
}
.gauge-status { font-size: 0.4rem; font-weight: 900; color: #52525b; letter-spacing: 2px; margin-top: 3px; display: block; }

/* ── STATS ── */
.rd-stats { display: flex; flex-direction: column; gap: 1px; }
.rd-stat-row {
  display: flex; justify-content: space-between; align-items: center;
  padding: 5px 8px; background: #15162e;
}
.stat-label { font-size: 0.5rem; font-weight: 800; color: #52525b; letter-spacing: 1px; display: flex; align-items: center; gap: 4px; }
.stat-val { font-size: 0.6rem; font-weight: 900; color: #a1a1aa; font-family: 'JetBrains Mono', monospace; }
.stat-val.amber { color: #f59e0b; }
.stat-val.green { color: #22c55e; }
.stat-val.warn { color: #ef4444; }

/* ── MODULES SUMMARY (status tab) ── */
.rd-modules-summary { display: flex; gap: 0.4rem; }
.rms-item {
  flex: 1; display: flex; flex-direction: column; align-items: center; gap: 2px;
  background: #15162e; border: 1px solid #1e1f3a; padding: 6px 4px;
  font-size: 0.4rem; font-weight: 900; color: #52525b; letter-spacing: 1px;
}
.rms-icon.cyan { color: #06b6d4; }
.rms-icon.amber { color: #f59e0b; }
.rms-icon.green { color: #22c55e; }
.rms-val { font-size: 0.6rem; font-weight: 900; color: #e5e7eb; }
.rms-val.dim { color: #3f3f5c; font-size: 0.5rem; }

/* ── MODULES TAB ── */
.rd-mod-section { margin-bottom: 0.5rem; }
.rd-mod-label {
  display: flex; align-items: center; gap: 4px;
  font-size: 0.45rem; font-weight: 900; color: #71717a; letter-spacing: 2px;
  padding-bottom: 4px; margin-bottom: 4px; border-bottom: 1px solid #1e1f3a;
}
.rd-mod-item {
  display: flex; align-items: center; gap: 8px;
  padding: 6px 8px; background: #15162e; border: 1px solid #1e1f3a;
  margin-bottom: 3px;
}
.mod-info { flex: 1; display: flex; flex-direction: column; gap: 2px; min-width: 0; }
.mod-name { font-size: 0.55rem; font-weight: 800; color: #d4d4d8; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.mod-stats { display: flex; gap: 8px; font-size: 0.45rem; font-weight: 800; color: #71717a; letter-spacing: 0.5px; flex-wrap: wrap; }
.mod-bar { height: 3px; background: #0f1023; border: 1px solid #2a2b48; overflow: hidden; margin-top: 2px; }
.mod-bar-fill { height: 100%; transition: width 0.5s; }
.mod-bar-fill.cyan { background: linear-gradient(90deg, #164e63, #06b6d4); }
.mod-bar-fill.amber { background: linear-gradient(90deg, #854d0e, #f59e0b); }
.mod-bar-fill.green { background: linear-gradient(90deg, #166534, #22c55e); }
.mod-bar-fill.low { background: linear-gradient(90deg, #7f1d1d, #ef4444); }
.mod-eject {
  background: transparent; border: 1px solid rgba(239,68,68,0.2); color: #ef4444;
  font-size: 0.4rem; font-weight: 900; font-family: inherit; letter-spacing: 1px;
  padding: 3px 8px; cursor: pointer; transition: 0.2s; flex-shrink: 0;
}
.mod-eject:hover { background: rgba(239,68,68,0.08); border-color: #ef4444; }
.rd-mod-empty {
  display: flex; flex-direction: column; align-items: center; justify-content: center;
  gap: 0.4rem; padding: 2rem 0; color: #3f3f5c; font-size: 0.6rem; font-weight: 800; letter-spacing: 2px;
}
.rd-mod-empty small { font-size: 0.45rem; color: #2a2b48; letter-spacing: 1px; }

/* ── DRAWER ACTIONS ── */
.rd-actions {
  display: flex; gap: 0.4rem; padding: 0.6rem;
  border-top: 1px solid #1e1f3a; flex-shrink: 0;
}
.rd-btn {
  flex: 1; display: flex; align-items: center; justify-content: center; gap: 4px;
  padding: 8px 0; background: transparent;
  border: 1px solid #2a2b48; color: #a1a1aa;
  font-size: 0.5rem; font-weight: 900; font-family: inherit; letter-spacing: 1px;
  cursor: pointer; transition: 0.2s;
}
.rd-btn:hover { background: rgba(255,255,255,0.03); }
.rd-btn:disabled { opacity: 0.3; cursor: not-allowed; }

.rd-btn.halt { border-color: rgba(239,68,68,0.3); color: #ef4444; }
.rd-btn.halt:hover { background: rgba(239,68,68,0.08); }
.rd-btn.pool { border-color: rgba(6,182,212,0.3); color: #06b6d4; }
.rd-btn.pool:hover { background: rgba(6,182,212,0.08); }
.rd-btn.solo { border-color: rgba(245,158,11,0.3); color: #f59e0b; }
.rd-btn.solo:hover { background: rgba(245,158,11,0.08); }
.rd-btn.repair { border-color: rgba(34,197,94,0.3); color: #22c55e; }
.rd-btn.repair:hover { background: rgba(34,197,94,0.08); }
.repair-cost { font-size: 0.45rem; color: #71717a; display: flex; align-items: center; gap: 2px; margin-left: 4px; }

/* ═══════════════════════════════════ RESPONSIVE ═══════════════════════════════════ */
@media (min-width: 768px) {
  .idle-root { max-width: 480px; margin: 0 auto; border-left: 1px solid #1e1f3a; border-right: 1px solid #1e1f3a; }
  .income-big { font-size: 2.8rem; }
  .idle-rig-node { width: 72px; height: 80px; }
}
</style>
