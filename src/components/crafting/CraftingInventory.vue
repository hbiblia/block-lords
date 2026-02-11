<script setup lang="ts">
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useCraftingStore } from '@/stores/crafting';

const { t } = useI18n();
const craftingStore = useCraftingStore();

const confirmDelete = ref<{ elementId: string; name: string; icon: string; quantity: number } | null>(null);

const zoneGroups = computed(() => {
  const groups: Record<string, typeof craftingStore.craftingItems> = {};
  for (const item of craftingStore.craftingItems) {
    const zone = item.zone_type || 'unknown';
    if (!groups[zone]) groups[zone] = [];
    groups[zone].push(item);
  }
  return groups;
});

const zoneLabels: Record<string, { label: string; icon: string }> = {
  forest: { label: 'Forest', icon: '🌲' },
  mine: { label: 'Mine', icon: '⛏️' },
  meadow: { label: 'Meadow', icon: '🌸' },
  swamp: { label: 'Swamp', icon: '🏚️' },
};

const rarityColors: Record<string, string> = {
  common: 'text-slate-400',
  uncommon: 'text-green-400',
  rare: 'text-blue-400',
  epic: 'text-purple-400',
  legendary: 'text-yellow-400',
};

function showDeleteConfirm(item: typeof craftingStore.craftingItems[0]) {
  confirmDelete.value = {
    elementId: item.element_id,
    name: item.name,
    icon: item.icon,
    quantity: item.quantity,
  };
}

async function executeDelete() {
  if (!confirmDelete.value) return;
  await craftingStore.deleteElement(confirmDelete.value.elementId, confirmDelete.value.quantity);
  confirmDelete.value = null;
}
</script>

<template>
  <div>
    <!-- Empty state -->
    <div v-if="craftingStore.craftingItems.length === 0" class="text-center py-8">
      <div class="text-4xl mb-3">📦</div>
      <p class="text-sm text-slate-400">
        {{ t('crafting.emptyInventory', 'No materials yet. Complete zone explorations to collect crafting elements!') }}
      </p>
    </div>

    <!-- Grouped inventory -->
    <div v-else class="space-y-4">
      <div v-for="(items, zone) in zoneGroups" :key="zone">
        <!-- Zone header -->
        <div class="flex items-center gap-2 mb-2">
          <span>{{ zoneLabels[zone]?.icon || '📦' }}</span>
          <span class="text-sm font-semibold text-slate-300">
            {{ t(`crafting.zones.${zone}`, zoneLabels[zone]?.label || zone) }}
          </span>
          <span class="text-xs text-slate-500">({{ items.length }})</span>
        </div>

        <!-- Items grid -->
        <div class="grid grid-cols-2 sm:grid-cols-3 gap-2">
          <div
            v-for="item in items"
            :key="item.element_id"
            class="flex items-center gap-2 p-2 bg-slate-800/50 border border-slate-700/50 rounded-lg group"
          >
            <span class="text-xl">{{ item.icon }}</span>
            <div class="flex-1 min-w-0">
              <div class="text-xs font-medium text-slate-200 truncate">{{ item.name }}</div>
              <div class="flex items-center gap-1">
                <span class="text-xs text-slate-400">x{{ item.quantity }}</span>
                <span class="text-[10px]" :class="rarityColors[item.rarity] || 'text-slate-500'">
                  {{ item.rarity }}
                </span>
              </div>
            </div>
            <button
              @click="showDeleteConfirm(item)"
              class="opacity-0 group-hover:opacity-100 text-xs text-slate-500 hover:text-red-400 transition-all p-1"
              :title="t('common.delete', 'Delete')"
            >
              &#10005;
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- Delete confirmation -->
    <div v-if="confirmDelete" class="fixed inset-0 z-[100] flex items-center justify-center bg-black/60 backdrop-blur-sm">
      <div class="bg-bg-secondary border border-border rounded-xl p-4 max-w-xs w-full mx-4 animate-fade-in">
        <div class="text-center">
          <span class="text-3xl">{{ confirmDelete.icon }}</span>
          <p class="text-sm text-slate-300 mt-2">
            {{ t('crafting.deleteConfirm', 'Delete all {name}?').replace('{name}', confirmDelete.name) }}
          </p>
          <p class="text-xs text-slate-500 mt-1">x{{ confirmDelete.quantity }}</p>
        </div>
        <div class="flex gap-2 mt-4">
          <button
            @click="confirmDelete = null"
            class="flex-1 px-3 py-2 text-sm bg-slate-700 hover:bg-slate-600 text-slate-300 rounded-lg transition-colors"
          >
            {{ t('common.cancel', 'Cancel') }}
          </button>
          <button
            @click="executeDelete"
            class="flex-1 px-3 py-2 text-sm bg-red-600 hover:bg-red-500 text-white rounded-lg transition-colors"
          >
            {{ t('common.delete', 'Delete') }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
