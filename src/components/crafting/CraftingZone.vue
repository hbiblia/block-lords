<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import { useCraftingStore } from '@/stores/crafting';
import CraftingCell from './CraftingCell.vue';
import CraftingReward from './CraftingReward.vue';

const { t } = useI18n();
const craftingStore = useCraftingStore();

const zoneNames: Record<string, string> = {
  forest: 'Forest',
  mine: 'Mine',
  meadow: 'Meadow',
  swamp: 'Swamp',
};

const zoneIcons: Record<string, string> = {
  forest: '🌲',
  mine: '⛏️',
  meadow: '🌸',
  swamp: '🏚️',
};

const zoneBgClasses: Record<string, string> = {
  forest: 'from-emerald-900/20 to-emerald-950/10 border-emerald-500/20',
  mine: 'from-amber-900/20 to-amber-950/10 border-amber-500/20',
  meadow: 'from-pink-900/20 to-pink-950/10 border-pink-500/20',
  swamp: 'from-purple-900/20 to-purple-950/10 border-purple-500/20',
};

function getRequiredName(requiresElement: string | null): string | undefined {
  if (!requiresElement || !craftingStore.currentSession) return undefined;
  const dep = craftingStore.currentSession.grid_config.find(
    (c) => c.element_id === requiresElement
  );
  return dep?.name;
}

function handleTap(cellIndex: number) {
  craftingStore.tapElement(cellIndex);
}

async function handleStart() {
  await craftingStore.startSession();
}

async function handleAbandon() {
  await craftingStore.abandon();
}
</script>

<template>
  <div class="relative">
    <!-- State 1: No session, can start -->
    <div v-if="!craftingStore.hasActiveSession && !craftingStore.isOnCooldown && !craftingStore.loading" class="text-center py-8">
      <div class="text-5xl mb-4">🗺️</div>
      <h3 class="text-lg font-bold text-slate-200 mb-2">
        {{ t('crafting.readyToExplore', 'Ready to Explore') }}
      </h3>
      <p class="text-sm text-slate-400 mb-6 max-w-xs mx-auto">
        {{ t('crafting.exploreDesc', 'Start a new expedition to collect crafting materials from a random zone.') }}
      </p>
      <button
        @click="handleStart"
        :disabled="craftingStore.starting"
        class="px-6 py-3 bg-accent-primary hover:bg-accent-primary/80 disabled:opacity-50 disabled:cursor-not-allowed text-white font-semibold rounded-lg transition-all active:scale-95"
      >
        <span v-if="craftingStore.starting" class="flex items-center gap-2">
          <svg class="animate-spin w-4 h-4" viewBox="0 0 24 24"><circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" fill="none"/><path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"/></svg>
          {{ t('common.loading', 'Loading...') }}
        </span>
        <span v-else>{{ t('crafting.startExploration', 'Start Exploration') }}</span>
      </button>
    </div>

    <!-- State 2: Cooldown active -->
    <div v-else-if="!craftingStore.hasActiveSession && craftingStore.isOnCooldown" class="text-center py-8">
      <div class="text-5xl mb-4">⏳</div>
      <h3 class="text-lg font-bold text-slate-200 mb-2">
        {{ t('crafting.cooldownActive', 'Resting...') }}
      </h3>
      <p class="text-sm text-slate-400 mb-4">
        {{ t('crafting.cooldownDesc', 'You need to rest before the next expedition.') }}
      </p>
      <div class="text-2xl font-mono font-bold text-accent-primary">
        {{ craftingStore.cooldownFormatted }}
      </div>
    </div>

    <!-- State 3: Active session -->
    <div v-else-if="craftingStore.hasActiveSession && craftingStore.currentSession" class="space-y-4">
      <!-- Zone header -->
      <div
        class="flex items-center justify-between p-3 rounded-lg border bg-gradient-to-r"
        :class="zoneBgClasses[craftingStore.currentSession.zone_type] || zoneBgClasses.forest"
      >
        <div class="flex items-center gap-2">
          <span class="text-2xl">{{ zoneIcons[craftingStore.currentSession.zone_type] || '🗺️' }}</span>
          <div>
            <div class="text-sm font-bold text-slate-200">
              {{ t(`crafting.zones.${craftingStore.currentSession.zone_type}`, zoneNames[craftingStore.currentSession.zone_type] || 'Zone') }}
            </div>
            <div class="text-xs text-slate-400">
              {{ craftingStore.sessionProgress }}/16 {{ t('crafting.collected', 'collected') }}
            </div>
          </div>
        </div>
        <button
          @click="handleAbandon"
          class="text-xs text-slate-500 hover:text-red-400 transition-colors px-2 py-1"
        >
          {{ t('crafting.abandon', 'Abandon') }}
        </button>
      </div>

      <!-- Progress bar -->
      <div class="h-2 bg-slate-700 rounded-full overflow-hidden">
        <div
          class="h-full bg-green-500 rounded-full transition-all duration-500"
          :style="{ width: (craftingStore.sessionProgress / 16 * 100) + '%' }"
        />
      </div>

      <!-- 4x4 Grid -->
      <div class="grid grid-cols-4 gap-2">
        <CraftingCell
          v-for="cell in craftingStore.gridWithLockState"
          :key="cell.index"
          :cell="cell"
          :zone-type="craftingStore.currentSession.zone_type"
          :disabled="craftingStore.tapping"
          :locked="cell.locked"
          :required-name="getRequiredName(cell.requires_element)"
          @tap="handleTap"
        />
      </div>
    </div>

    <!-- Loading state -->
    <div v-else-if="craftingStore.loading" class="text-center py-12">
      <svg class="animate-spin w-8 h-8 mx-auto text-accent-primary" viewBox="0 0 24 24"><circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" fill="none"/><path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"/></svg>
    </div>

    <!-- Reward overlay -->
    <CraftingReward />
  </div>
</template>
