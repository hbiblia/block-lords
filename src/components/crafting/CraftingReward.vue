<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import { useCraftingStore } from '@/stores/crafting';

const { t } = useI18n();
const craftingStore = useCraftingStore();

function handleContinue() {
  craftingStore.dismissReward();
}
</script>

<template>
  <div
    v-if="craftingStore.showReward && craftingStore.lastReward"
    class="absolute inset-0 z-50 flex items-center justify-center bg-black/80 backdrop-blur-sm rounded-xl"
  >
    <div class="text-center p-6 animate-fade-in">
      <!-- Title -->
      <div class="text-2xl font-bold text-green-400 mb-4">
        {{ t('crafting.zoneComplete', 'Zone Complete!') }}
      </div>

      <!-- Rewards -->
      <div class="space-y-3 mb-6">
        <!-- GameCoin reward -->
        <div v-if="craftingStore.lastReward.gamecoin > 0" class="flex items-center justify-center gap-2 text-yellow-400">
          <span class="text-2xl">🪙</span>
          <span class="text-xl font-bold">+{{ craftingStore.lastReward.gamecoin }} GameCoin</span>
        </div>

        <!-- Collected elements -->
        <div class="text-sm text-slate-300 mb-2">{{ t('crafting.elementsCollected', 'Elements collected:') }}</div>
        <div class="flex flex-wrap gap-2 justify-center max-w-xs mx-auto">
          <div
            v-for="elem in craftingStore.lastReward.elements"
            :key="elem.element_id"
            class="flex items-center gap-1 px-2 py-1 bg-slate-700/50 rounded-lg text-sm"
          >
            <span>{{ elem.icon }}</span>
            <span class="text-slate-300">x{{ elem.quantity }}</span>
          </div>
        </div>
      </div>

      <!-- Continue button -->
      <button
        @click="handleContinue"
        class="px-6 py-2 bg-green-500 hover:bg-green-600 text-white font-semibold rounded-lg transition-colors"
      >
        {{ t('common.continue', 'Continue') }}
      </button>
    </div>
  </div>
</template>
