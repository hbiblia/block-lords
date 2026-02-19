<script setup lang="ts">
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAuthStore } from '@/stores/auth';
import { useInventoryStore, type CoolingItem, type ModdedCoolingItem, type CoolingComponentItem, type CoolingMod } from '@/stores/inventory';
import { installCoolingMod } from '@/utils/api';
import { playSound } from '@/utils/sounds';
import { formatNumber } from '@/utils/format';

const { t } = useI18n();

const authStore = useAuthStore();
const inventoryStore = useInventoryStore();

const props = defineProps<{
  show: boolean;
  coolingItem: CoolingItem | ModdedCoolingItem | null;
}>();

const emit = defineEmits<{
  close: [];
  modded: [playerCoolingItemId: string];
}>();

// State
const installing = ref(false);
const selectedComponent = ref<CoolingComponentItem | null>(null);
const showConfirmDialog = ref(false);
const rollPhase = ref<'idle' | 'rolling' | 'result'>('idle');
const rollResult = ref<{ cooling_power_mod: number; energy_cost_mod: number; durability_mod: number; quality: string } | null>(null);
const rollAnimValues = ref({ cooling: 0, energy: 0, durability: 0 });
let rollInterval: ReturnType<typeof setInterval> | null = null;

// Is this a modded item or unmodded inventory item?
const isModded = computed(() => {
  if (!props.coolingItem) return false;
  return 'player_cooling_item_id' in props.coolingItem;
});

const sourceType = computed(() => isModded.value ? 'modded' as const : 'inventory' as const);

const itemId = computed(() => {
  if (!props.coolingItem) return '';
  if (isModded.value) {
    return (props.coolingItem as ModdedCoolingItem).player_cooling_item_id;
  }
  return (props.coolingItem as CoolingItem).id;
});

// Current stats
const currentMods = computed<CoolingMod[]>(() => {
  if (!props.coolingItem) return [];
  if (isModded.value) {
    return (props.coolingItem as ModdedCoolingItem).mods || [];
  }
  return [];
});

const maxSlots = computed(() => {
  if (!props.coolingItem) return 1;
  if (isModded.value) {
    return (props.coolingItem as ModdedCoolingItem).max_mod_slots;
  }
  return (props.coolingItem as CoolingItem).max_mod_slots || 1;
});

const usedSlots = computed(() => {
  if (!props.coolingItem) return 0;
  if (isModded.value) {
    return (props.coolingItem as ModdedCoolingItem).mod_slots_used;
  }
  return 0;
});

const slotsAvailable = computed(() => maxSlots.value - usedSlots.value > 0);

const basePower = computed(() => props.coolingItem?.cooling_power ?? 0);
const baseEnergy = computed(() => props.coolingItem?.energy_cost ?? 0);

const effectivePower = computed(() => {
  if (isModded.value) {
    return (props.coolingItem as ModdedCoolingItem).effective_cooling_power ?? basePower.value;
  }
  return basePower.value;
});

const effectiveEnergy = computed(() => {
  if (isModded.value) {
    return (props.coolingItem as ModdedCoolingItem).effective_energy_cost ?? baseEnergy.value;
  }
  return baseEnergy.value;
});

const totalDurabilityMod = computed(() => {
  if (isModded.value) {
    return (props.coolingItem as ModdedCoolingItem).total_durability_mod ?? 0;
  }
  return 0;
});

// Available components from inventory
const availableComponents = computed(() => {
  return inventoryStore.componentItems.filter(c => c.quantity > 0);
});

// Helpers
function getCoolingName(item: CoolingItem | ModdedCoolingItem | null): string {
  if (!item) return '';
  const id = isModded.value ? (item as ModdedCoolingItem).cooling_item_id : (item as CoolingItem).id;
  const key = `market.items.cooling.${id}.name`;
  const translated = t(key);
  if (translated !== key) return translated;
  return item.name || id;
}

function getComponentName(id: string, fallback?: string): string {
  const key = `market.items.components.${id}.name`;
  const translated = t(key);
  if (translated !== key) return translated;
  return fallback || id;
}

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
    case 'elite': return 'bg-amber-500/10';
    case 'advanced': return 'bg-fuchsia-500/10';
    case 'standard': return 'bg-sky-500/10';
    case 'basic': return 'bg-emerald-500/10';
    default: return 'bg-bg-tertiary';
  }
}

function getTierBorder(tier: string) {
  switch (tier) {
    case 'elite': return 'border-amber-500/40';
    case 'advanced': return 'border-fuchsia-500/40';
    case 'standard': return 'border-sky-500/40';
    case 'basic': return 'border-emerald-500/40';
    default: return 'border-border';
  }
}

function formatMod(value: number): string {
  if (value === 0) return '—';
  const sign = value > 0 ? '+' : '';
  return `${sign}${formatNumber(value, 1)}%`;
}

function formatRange(min: number, max: number): string {
  if (min === 0 && max === 0) return '—';
  const sMin = min > 0 ? `+${formatNumber(min, 0)}%` : `${formatNumber(min, 0)}%`;
  const sMax = max > 0 ? `+${formatNumber(max, 0)}%` : `${formatNumber(max, 0)}%`;
  return `${sMin} to ${sMax}`;
}

// For stat display color: green = good, red = bad
function modColor(value: number, isInverse = false): string {
  if (value === 0) return 'text-text-muted';
  const isGood = isInverse ? value < 0 : value > 0;
  return isGood ? 'text-emerald-400' : 'text-rose-400';
}

// For range color on components
function rangeColor(min: number, max: number, isInverse = false): string {
  // If both positive (non-inverse) or both negative (inverse) = fully good
  if (isInverse) {
    if (max <= 0) return 'text-emerald-400';
    if (min >= 0) return 'text-rose-400';
    return 'text-amber-400';
  }
  if (min >= 0) return 'text-emerald-400';
  if (max <= 0) return 'text-rose-400';
  return 'text-amber-400';
}

function getQualityColor(quality: string): string {
  switch (quality) {
    case 'excellent': return 'text-emerald-300';
    case 'good': return 'text-emerald-400';
    case 'average': return 'text-amber-400';
    case 'poor': return 'text-orange-400';
    case 'terrible': return 'text-rose-400';
    default: return 'text-text-muted';
  }
}

function getQualityBg(quality: string): string {
  switch (quality) {
    case 'excellent': return 'bg-emerald-500/20 border-emerald-500/40';
    case 'good': return 'bg-emerald-500/10 border-emerald-500/30';
    case 'average': return 'bg-amber-500/10 border-amber-500/30';
    case 'poor': return 'bg-orange-500/10 border-orange-500/30';
    case 'terrible': return 'bg-rose-500/10 border-rose-500/30';
    default: return 'bg-bg-tertiary border-border';
  }
}

// Actions
function requestInstall(component: CoolingComponentItem) {
  selectedComponent.value = component;
  showConfirmDialog.value = true;
  playSound('click');
}

function cancelInstall() {
  showConfirmDialog.value = false;
  selectedComponent.value = null;
  playSound('click');
}

async function confirmInstall() {
  if (!selectedComponent.value || !props.coolingItem || !authStore.player?.id) return;

  installing.value = true;
  showConfirmDialog.value = false;
  rollPhase.value = 'rolling';
  playSound('click');

  // Start roll animation
  startRollAnimation();

  try {
    const result = await installCoolingMod(
      authStore.player.id,
      itemId.value,
      selectedComponent.value.id,
      sourceType.value,
    );

    // Keep rolling animation for suspense (minimum 1.5s total)
    await new Promise(resolve => setTimeout(resolve, 1500));

    stopRollAnimation();

    if (result?.success) {
      rollResult.value = {
        cooling_power_mod: result.mod?.cooling_power_mod ?? 0,
        energy_cost_mod: result.mod?.energy_cost_mod ?? 0,
        durability_mod: result.mod?.durability_mod ?? 0,
        quality: result.quality ?? 'average',
      };
      rollPhase.value = 'result';
      playSound('success');

      // Refresh inventory data
      await inventoryStore.refresh();
      emit('modded', result.player_cooling_item_id);
    } else {
      rollPhase.value = 'idle';
      playSound('error');
    }
  } catch (e) {
    console.error('Error installing mod:', e);
    stopRollAnimation();
    rollPhase.value = 'idle';
    playSound('error');
  } finally {
    installing.value = false;
  }
}

function startRollAnimation() {
  const comp = selectedComponent.value;
  if (!comp) return;

  rollInterval = setInterval(() => {
    rollAnimValues.value = {
      cooling: randomInRange(comp.cooling_power_min, comp.cooling_power_max),
      energy: randomInRange(comp.energy_cost_min, comp.energy_cost_max),
      durability: randomInRange(comp.durability_min, comp.durability_max),
    };
  }, 60);
}

function stopRollAnimation() {
  if (rollInterval) {
    clearInterval(rollInterval);
    rollInterval = null;
  }
}

function randomInRange(min: number, max: number): number {
  if (min === 0 && max === 0) return 0;
  return Math.round((min + Math.random() * (max - min)) * 10) / 10;
}

function dismissResult() {
  rollPhase.value = 'idle';
  rollResult.value = null;
  selectedComponent.value = null;
  playSound('click');
}

function handleClose() {
  if (rollPhase.value === 'rolling') return; // Can't close while rolling
  rollPhase.value = 'idle';
  rollResult.value = null;
  selectedComponent.value = null;
  showConfirmDialog.value = false;
  playSound('click');
  emit('close');
}

// Cleanup on unmount
watch(() => props.show, (val) => {
  if (!val) {
    stopRollAnimation();
    rollPhase.value = 'idle';
    rollResult.value = null;
    selectedComponent.value = null;
    showConfirmDialog.value = false;
  }
});
</script>

<template>
  <Teleport to="body">
    <div
      v-if="show && coolingItem"
      class="fixed inset-0 z-[60] flex items-center justify-center p-4"
    >
      <!-- Overlay -->
      <div
        class="absolute inset-0 bg-black/70 backdrop-blur-sm"
        @click="handleClose"
      ></div>

      <!-- Modal -->
      <div class="relative w-full max-w-lg lg:max-w-2xl max-h-[90vh] flex flex-col bg-bg-secondary border border-border rounded-xl overflow-hidden">
        <!-- Header -->
        <div class="flex items-center justify-between p-4 border-b border-border">
          <div>
            <h2 class="text-lg font-semibold flex items-center gap-2">
              <span>🔧</span>
              <span>{{ t('workshop.title') }}</span>
            </h2>
            <p class="text-sm text-text-muted">{{ t('workshop.subtitle') }}</p>
          </div>
          <button
            @click="handleClose"
            :disabled="rollPhase === 'rolling'"
            class="p-2 hover:bg-bg-tertiary rounded-lg transition-colors text-text-muted hover:text-white disabled:opacity-50"
          >
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        <!-- Content -->
        <div class="flex-1 overflow-y-auto p-4 space-y-4">

          <!-- Cooling Item Card -->
          <div class="rounded-lg border p-4" :class="[getTierBg(coolingItem.tier), getTierBorder(coolingItem.tier)]">
            <div class="flex items-center justify-between mb-3">
              <div>
                <h3 class="font-semibold" :class="getTierColor(coolingItem.tier)">
                  ❄️ {{ getCoolingName(coolingItem) }}
                </h3>
                <span class="text-xs uppercase" :class="getTierColor(coolingItem.tier)">{{ coolingItem.tier }}</span>
              </div>
              <div class="text-xs text-text-muted">
                {{ t('workshop.modSlots') }}: {{ usedSlots }}/{{ maxSlots }}
              </div>
            </div>

            <!-- Current Stats -->
            <div class="grid grid-cols-3 gap-3 text-sm">
              <div>
                <div class="text-text-muted text-xs">❄️ {{ t('workshop.coolingPower') }}</div>
                <div class="font-medium">{{ formatNumber(effectivePower, 1) }}°</div>
                <div v-if="isModded && effectivePower !== basePower" class="text-xs" :class="effectivePower > basePower ? 'text-emerald-400' : 'text-rose-400'">
                  {{ effectivePower > basePower ? '+' : '' }}{{ formatNumber(((effectivePower - basePower) / basePower) * 100, 1) }}%
                </div>
              </div>
              <div>
                <div class="text-text-muted text-xs">⚡ {{ t('workshop.energyCost') }}</div>
                <div class="font-medium">{{ formatNumber(effectiveEnergy, 1) }}/t</div>
                <div v-if="isModded && effectiveEnergy !== baseEnergy" class="text-xs" :class="effectiveEnergy < baseEnergy ? 'text-emerald-400' : 'text-rose-400'">
                  {{ effectiveEnergy > baseEnergy ? '+' : '' }}{{ formatNumber(((effectiveEnergy - baseEnergy) / baseEnergy) * 100, 1) }}%
                </div>
              </div>
              <div>
                <div class="text-text-muted text-xs">🔧 {{ t('workshop.durability') }}</div>
                <div class="font-medium" :class="totalDurabilityMod !== 0 ? (totalDurabilityMod > 0 ? 'text-emerald-400' : 'text-rose-400') : ''">
                  {{ totalDurabilityMod === 0 ? '—' : (totalDurabilityMod > 0 ? '+' : '') + formatNumber(totalDurabilityMod, 1) + '%' }}
                </div>
                <div v-if="totalDurabilityMod !== 0" class="text-xs text-text-muted">
                  {{ totalDurabilityMod > 0 ? t('workshop.stats.slower') : t('workshop.stats.faster') }}
                </div>
              </div>
            </div>

            <!-- Mod Slots -->
            <div class="flex gap-2 mt-3">
              <div
                v-for="slot in maxSlots"
                :key="slot"
                class="flex-1 rounded-md border p-1.5 text-center text-xs"
                :class="slot <= usedSlots
                  ? 'bg-fuchsia-500/15 border-fuchsia-500/40 text-fuchsia-300'
                  : 'bg-bg-tertiary border-border text-text-muted'"
              >
                <template v-if="slot <= currentMods.length">
                  🧩 {{ getComponentName(currentMods[slot - 1].component_id) }}
                </template>
                <template v-else>
                  {{ t('workshop.empty') }}
                </template>
              </div>
            </div>
          </div>

          <!-- Roll Animation / Result Overlay -->
          <div v-if="rollPhase !== 'idle'" class="rounded-lg border border-border bg-bg-tertiary p-4">
            <!-- Rolling Animation -->
            <div v-if="rollPhase === 'rolling'" class="text-center space-y-4">
              <div class="text-lg font-semibold animate-pulse">🎲 {{ t('workshop.roll.rolling') }}</div>
              <div class="grid grid-cols-3 gap-3">
                <div v-if="selectedComponent && (selectedComponent.cooling_power_min !== 0 || selectedComponent.cooling_power_max !== 0)">
                  <div class="text-xs text-text-muted">❄️ {{ t('workshop.coolingPower') }}</div>
                  <div class="text-lg font-mono font-bold animate-pulse" :class="modColor(rollAnimValues.cooling)">
                    {{ formatMod(rollAnimValues.cooling) }}
                  </div>
                </div>
                <div v-if="selectedComponent && (selectedComponent.energy_cost_min !== 0 || selectedComponent.energy_cost_max !== 0)">
                  <div class="text-xs text-text-muted">⚡ {{ t('workshop.energyCost') }}</div>
                  <div class="text-lg font-mono font-bold animate-pulse" :class="modColor(rollAnimValues.energy, true)">
                    {{ formatMod(rollAnimValues.energy) }}
                  </div>
                </div>
                <div v-if="selectedComponent && (selectedComponent.durability_min !== 0 || selectedComponent.durability_max !== 0)">
                  <div class="text-xs text-text-muted">🔧 {{ t('workshop.durability') }}</div>
                  <div class="text-lg font-mono font-bold animate-pulse" :class="modColor(rollAnimValues.durability)">
                    {{ formatMod(rollAnimValues.durability) }}
                  </div>
                </div>
              </div>
            </div>

            <!-- Result -->
            <div v-else-if="rollPhase === 'result' && rollResult" class="space-y-4">
              <div class="text-center">
                <div class="text-sm text-text-muted mb-1">{{ t('workshop.roll.result') }}</div>
                <div class="text-2xl font-bold" :class="getQualityColor(rollResult.quality)">
                  {{ t(`workshop.roll.${rollResult.quality}`) }}
                  <span v-if="rollResult.quality === 'excellent'"> ✨</span>
                  <span v-else-if="rollResult.quality === 'terrible'"> 💀</span>
                </div>
              </div>

              <div class="rounded-lg border p-3" :class="getQualityBg(rollResult.quality)">
                <div class="grid grid-cols-3 gap-3 text-center">
                  <div v-if="rollResult.cooling_power_mod !== 0">
                    <div class="text-xs text-text-muted">❄️ {{ t('workshop.coolingPower') }}</div>
                    <div class="text-lg font-bold" :class="modColor(rollResult.cooling_power_mod)">
                      {{ formatMod(rollResult.cooling_power_mod) }}
                    </div>
                  </div>
                  <div v-if="rollResult.energy_cost_mod !== 0">
                    <div class="text-xs text-text-muted">⚡ {{ t('workshop.energyCost') }}</div>
                    <div class="text-lg font-bold" :class="modColor(rollResult.energy_cost_mod, true)">
                      {{ formatMod(rollResult.energy_cost_mod) }}
                    </div>
                  </div>
                  <div v-if="rollResult.durability_mod !== 0">
                    <div class="text-xs text-text-muted">🔧 {{ t('workshop.durability') }}</div>
                    <div class="text-lg font-bold" :class="modColor(rollResult.durability_mod)">
                      {{ formatMod(rollResult.durability_mod) }}
                    </div>
                  </div>
                </div>
              </div>

              <button
                @click="dismissResult"
                class="w-full py-2 bg-bg-secondary hover:bg-bg-tertiary border border-border rounded-lg transition-colors text-sm"
              >
                {{ t('common.close') }}
              </button>
            </div>
          </div>

          <!-- Available Components -->
          <div v-if="rollPhase === 'idle'">
            <h3 class="text-sm font-semibold text-text-muted mb-3">📦 {{ t('workshop.availableComponents') }}</h3>

            <div v-if="availableComponents.length === 0" class="text-center py-6 text-text-muted text-sm">
              {{ t('workshop.noComponents') }}
            </div>

            <div v-else class="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <div
                v-for="comp in availableComponents"
                :key="comp.id"
                class="rounded-lg border p-3 space-y-2"
                :class="[getTierBg(comp.tier), getTierBorder(comp.tier)]"
              >
                <div class="flex items-center justify-between">
                  <div>
                    <div class="font-medium text-sm" :class="getTierColor(comp.tier)">
                      🧩 {{ getComponentName(comp.id, comp.name) }}
                    </div>
                    <div class="text-xs text-text-muted">x{{ comp.quantity }} · {{ comp.tier }}</div>
                  </div>
                </div>

                <!-- Stat Ranges -->
                <div class="space-y-1 text-xs">
                  <div v-if="comp.cooling_power_min !== 0 || comp.cooling_power_max !== 0" class="flex justify-between">
                    <span class="text-text-muted">❄️ {{ t('workshop.coolingPower') }}</span>
                    <span :class="rangeColor(comp.cooling_power_min, comp.cooling_power_max)">
                      {{ formatRange(comp.cooling_power_min, comp.cooling_power_max) }}
                    </span>
                  </div>
                  <div v-if="comp.energy_cost_min !== 0 || comp.energy_cost_max !== 0" class="flex justify-between">
                    <span class="text-text-muted">⚡ {{ t('workshop.energyCost') }}</span>
                    <span :class="rangeColor(comp.energy_cost_min, comp.energy_cost_max, true)">
                      {{ formatRange(comp.energy_cost_min, comp.energy_cost_max) }}
                    </span>
                  </div>
                  <div v-if="comp.durability_min !== 0 || comp.durability_max !== 0" class="flex justify-between">
                    <span class="text-text-muted">🔧 {{ t('workshop.durability') }}</span>
                    <span :class="rangeColor(comp.durability_min, comp.durability_max)">
                      {{ formatRange(comp.durability_min, comp.durability_max) }}
                    </span>
                  </div>
                </div>

                <!-- Install Button -->
                <button
                  @click="requestInstall(comp)"
                  :disabled="!slotsAvailable || installing"
                  class="w-full py-1.5 rounded-md text-xs font-medium transition-colors"
                  :class="slotsAvailable
                    ? 'bg-fuchsia-600 hover:bg-fuchsia-500 text-white'
                    : 'bg-bg-tertiary text-text-muted cursor-not-allowed'"
                >
                  {{ slotsAvailable ? t('workshop.install') : t('workshop.slotsFull') }}
                </button>
              </div>
            </div>
          </div>

        </div>
      </div>

      <!-- Confirm Dialog -->
      <div v-if="showConfirmDialog && selectedComponent" class="fixed inset-0 z-[70] flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-black/50" @click="cancelInstall"></div>
        <div class="relative w-full max-w-sm bg-bg-secondary border border-border rounded-xl p-5 space-y-4">
          <h3 class="font-semibold text-center">{{ t('workshop.confirm.title') }}</h3>

          <p class="text-sm text-center text-text-muted">
            {{ t('workshop.confirm.question', { component: getComponentName(selectedComponent.id, selectedComponent.name), cooling: getCoolingName(coolingItem) }) }}
          </p>

          <!-- Ranges Preview -->
          <div class="bg-bg-tertiary rounded-lg p-3 space-y-2 text-sm">
            <div class="text-xs text-text-muted font-semibold">{{ t('workshop.confirm.ranges') }}</div>
            <div v-if="selectedComponent.cooling_power_min !== 0 || selectedComponent.cooling_power_max !== 0" class="flex justify-between">
              <span>❄️ {{ t('workshop.coolingPower') }}</span>
              <span :class="rangeColor(selectedComponent.cooling_power_min, selectedComponent.cooling_power_max)">
                {{ formatRange(selectedComponent.cooling_power_min, selectedComponent.cooling_power_max) }}
              </span>
            </div>
            <div v-if="selectedComponent.energy_cost_min !== 0 || selectedComponent.energy_cost_max !== 0" class="flex justify-between">
              <span>⚡ {{ t('workshop.energyCost') }}</span>
              <span :class="rangeColor(selectedComponent.energy_cost_min, selectedComponent.energy_cost_max, true)">
                {{ formatRange(selectedComponent.energy_cost_min, selectedComponent.energy_cost_max) }}
              </span>
            </div>
            <div v-if="selectedComponent.durability_min !== 0 || selectedComponent.durability_max !== 0" class="flex justify-between">
              <span>🔧 {{ t('workshop.durability') }}</span>
              <span :class="rangeColor(selectedComponent.durability_min, selectedComponent.durability_max)">
                {{ formatRange(selectedComponent.durability_min, selectedComponent.durability_max) }}
              </span>
            </div>
          </div>

          <!-- Warning -->
          <div class="bg-rose-500/10 border border-rose-500/30 rounded-lg p-3 text-center">
            <span class="text-rose-400 text-sm font-semibold">⚠️ {{ t('workshop.confirm.warning') }}</span>
          </div>

          <!-- Buttons -->
          <div class="flex gap-3">
            <button
              @click="cancelInstall"
              class="flex-1 py-2 bg-bg-tertiary hover:bg-bg-secondary border border-border rounded-lg transition-colors text-sm"
            >
              {{ t('common.cancel') }}
            </button>
            <button
              @click="confirmInstall"
              :disabled="installing"
              class="flex-1 py-2 bg-fuchsia-600 hover:bg-fuchsia-500 text-white rounded-lg transition-colors text-sm font-medium disabled:opacity-50"
            >
              {{ installing ? t('workshop.confirm.installing') : t('workshop.install') }}
            </button>
          </div>
        </div>
      </div>
    </div>
  </Teleport>
</template>
