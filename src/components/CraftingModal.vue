<script setup lang="ts">
import { watch, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useCraftingStore } from '@/stores/crafting';
import type { CraftingTab } from '@/stores/crafting';
import CraftingZone from './crafting/CraftingZone.vue';
import CraftingInventory from './crafting/CraftingInventory.vue';
import CraftingRecipes from './crafting/CraftingRecipes.vue';

const props = defineProps<{
  show: boolean;
}>();

const emit = defineEmits<{
  close: [];
}>();

const { t } = useI18n();
const craftingStore = useCraftingStore();

const tabs: { key: CraftingTab; label: string; icon: string }[] = [
  { key: 'zone', label: 'Zone', icon: '🗺️' },
  { key: 'inventory', label: 'Materials', icon: '📦' },
  { key: 'recipes', label: 'Recipes', icon: '📜' },
];

watch(() => props.show, (visible) => {
  if (visible) {
    craftingStore.loadAllData();
    document.body.style.overflow = 'hidden';
  } else {
    document.body.style.overflow = '';
  }
}, { immediate: true });

onUnmounted(() => {
  document.body.style.overflow = '';
});

function handleClose() {
  emit('close');
}
</script>

<template>
  <Teleport to="body">
    <div v-if="show" class="fixed inset-0 z-50 flex items-center justify-center p-2 sm:p-4">
      <!-- Backdrop -->
      <div class="absolute inset-0 bg-black/70 backdrop-blur-sm" @click="handleClose" />

      <!-- Modal card -->
      <div class="relative w-full max-w-lg h-[90vh] flex flex-col bg-bg-primary border border-border rounded-xl shadow-2xl animate-fade-in overflow-hidden">
        <!-- Header -->
        <div class="flex items-center justify-between p-4 border-b border-border/50">
          <div class="flex items-center gap-2">
            <span class="text-xl">⚒️</span>
            <h2 class="text-lg font-bold bg-gradient-to-r from-amber-400 to-orange-500 bg-clip-text text-transparent">
              Crafting Lords
            </h2>
          </div>
          <button
            @click="handleClose"
            class="p-1.5 text-slate-400 hover:text-slate-200 hover:bg-slate-700/50 rounded-lg transition-colors"
          >
            <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
              <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        <!-- Tabs -->
        <div class="flex border-b border-border/50">
          <button
            v-for="tab in tabs"
            :key="tab.key"
            @click="craftingStore.activeTab = tab.key"
            class="flex-1 flex items-center justify-center gap-1.5 py-2.5 text-sm font-medium transition-colors relative"
            :class="craftingStore.activeTab === tab.key
              ? 'text-accent-primary'
              : 'text-slate-400 hover:text-slate-300'"
          >
            <span>{{ tab.icon }}</span>
            <span>{{ t(`crafting.tabs.${tab.key}`, tab.label) }}</span>
            <!-- Badge for inventory count -->
            <span
              v-if="tab.key === 'inventory' && craftingStore.totalCraftingItems > 0"
              class="ml-1 px-1.5 py-0.5 text-[10px] font-bold bg-slate-700 text-slate-300 rounded-full"
            >
              {{ craftingStore.totalCraftingItems }}
            </span>
            <!-- Active indicator -->
            <div
              v-if="craftingStore.activeTab === tab.key"
              class="absolute bottom-0 left-2 right-2 h-0.5 bg-accent-primary rounded-full"
            />
          </button>
        </div>

        <!-- Content -->
        <div class="flex-1 overflow-y-auto p-4">
          <CraftingZone v-if="craftingStore.activeTab === 'zone'" />
          <CraftingInventory v-else-if="craftingStore.activeTab === 'inventory'" />
          <CraftingRecipes v-else-if="craftingStore.activeTab === 'recipes'" />
        </div>
      </div>
    </div>
  </Teleport>
</template>
