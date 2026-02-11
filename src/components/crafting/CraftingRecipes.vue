<script setup lang="ts">
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useCraftingStore } from '@/stores/crafting';
import type { CraftingRecipe, RecipeCategory } from '@/stores/crafting';

const { t } = useI18n();
const craftingStore = useCraftingStore();

const activeCategory = ref<RecipeCategory>('all');
const confirmCraft = ref<CraftingRecipe | null>(null);
const craftingRecipeId = ref<string | null>(null);
const craftResult = ref<{ success: boolean; error?: string } | null>(null);

const categories: { key: RecipeCategory; label: string; icon: string }[] = [
  { key: 'all', label: 'All', icon: '📋' },
  { key: 'cooling', label: 'Cooling', icon: '❄️' },
  { key: 'boost', label: 'Boosts', icon: '⚡' },
  { key: 'card', label: 'Cards', icon: '💳' },
  { key: 'sellable', label: 'Sell', icon: '🪙' },
];

const categoryOutputIcons: Record<string, string> = {
  cooling: '❄️',
  boost: '⚡',
  card: '💳',
  sellable: '🪙',
};

function hasEnoughIngredient(elementId: string, required: number): boolean {
  const item = craftingStore.craftingItems.find((i) => i.element_id === elementId);
  return (item?.quantity || 0) >= required;
}

function getOwnedQuantity(elementId: string): number {
  const item = craftingStore.craftingItems.find((i) => i.element_id === elementId);
  return item?.quantity || 0;
}

function showCraftConfirm(recipe: CraftingRecipe) {
  confirmCraft.value = recipe;
  craftResult.value = null;
}

async function executeCraft() {
  if (!confirmCraft.value) return;
  craftingRecipeId.value = confirmCraft.value.id;
  const result = await craftingStore.executeCraft(confirmCraft.value.id);
  craftResult.value = result;
  craftingRecipeId.value = null;
  if (result.success) {
    setTimeout(() => {
      confirmCraft.value = null;
      craftResult.value = null;
    }, 1500);
  }
}
</script>

<template>
  <div>
    <!-- Category filter -->
    <div class="flex gap-1.5 mb-4 overflow-x-auto pb-1">
      <button
        v-for="cat in categories"
        :key="cat.key"
        @click="activeCategory = cat.key"
        class="flex items-center gap-1 px-3 py-1.5 text-xs font-medium rounded-full whitespace-nowrap transition-colors"
        :class="activeCategory === cat.key
          ? 'bg-accent-primary text-white'
          : 'bg-slate-800 text-slate-400 hover:bg-slate-700'"
      >
        <span>{{ cat.icon }}</span>
        {{ t(`crafting.categories.${cat.key}`, cat.label) }}
      </button>
    </div>

    <!-- Recipes list -->
    <div v-if="craftingStore.filteredRecipes(activeCategory).length === 0" class="text-center py-6">
      <p class="text-sm text-slate-400">{{ t('crafting.noRecipes', 'No recipes in this category.') }}</p>
    </div>

    <div v-else class="space-y-3">
      <div
        v-for="recipe in craftingStore.filteredRecipes(activeCategory)"
        :key="recipe.id"
        class="p-3 bg-slate-800/50 border border-slate-700/50 rounded-lg"
      >
        <!-- Recipe header -->
        <div class="flex items-center justify-between mb-2">
          <div class="flex items-center gap-2">
            <span class="text-lg">{{ categoryOutputIcons[recipe.category] || '📦' }}</span>
            <div>
              <div class="text-sm font-medium text-slate-200">{{ recipe.name }}</div>
              <div class="text-[10px] text-slate-500">
                <template v-if="recipe.gamecoin_reward > 0">+{{ recipe.gamecoin_reward }} GameCoin</template>
                <template v-else>{{ recipe.output_item_type }}</template>
              </div>
            </div>
          </div>
          <button
            @click="showCraftConfirm(recipe)"
            :disabled="!craftingStore.canCraftRecipe(recipe) || craftingStore.crafting"
            class="px-3 py-1.5 text-xs font-semibold rounded-lg transition-all"
            :class="craftingStore.canCraftRecipe(recipe)
              ? 'bg-accent-primary hover:bg-accent-primary/80 text-white active:scale-95'
              : 'bg-slate-700 text-slate-500 cursor-not-allowed'"
          >
            {{ t('crafting.craft', 'Craft') }}
          </button>
        </div>

        <!-- Ingredients -->
        <div class="flex flex-wrap gap-1.5">
          <div
            v-for="ing in recipe.ingredients"
            :key="ing.element_id"
            class="flex items-center gap-1 px-2 py-0.5 rounded text-xs"
            :class="hasEnoughIngredient(ing.element_id, ing.quantity)
              ? 'bg-green-900/30 text-green-400'
              : 'bg-red-900/30 text-red-400'"
          >
            <span>{{ ing.icon }}</span>
            <span>{{ getOwnedQuantity(ing.element_id) }}/{{ ing.quantity }}</span>
          </div>
        </div>
      </div>
    </div>

    <!-- Craft confirmation dialog -->
    <div v-if="confirmCraft" class="fixed inset-0 z-[100] flex items-center justify-center bg-black/60 backdrop-blur-sm">
      <div class="bg-bg-secondary border border-border rounded-xl p-4 max-w-sm w-full mx-4 animate-fade-in">
        <!-- Success state -->
        <div v-if="craftResult?.success" class="text-center py-4">
          <span class="text-4xl">&#10003;</span>
          <p class="text-green-400 font-semibold mt-2">{{ t('crafting.craftSuccess', 'Crafted successfully!') }}</p>
        </div>

        <!-- Confirm state -->
        <template v-else>
          <div class="text-center mb-4">
            <span class="text-3xl">{{ categoryOutputIcons[confirmCraft.category] || '📦' }}</span>
            <h3 class="text-sm font-bold text-slate-200 mt-2">{{ confirmCraft.name }}</h3>
            <p v-if="confirmCraft.gamecoin_reward > 0" class="text-xs text-yellow-400 mt-1">
              +{{ confirmCraft.gamecoin_reward }} GameCoin
            </p>
          </div>

          <!-- Ingredients needed -->
          <div class="space-y-1 mb-4">
            <div class="text-xs text-slate-500 mb-1">{{ t('crafting.ingredientsNeeded', 'Ingredients:') }}</div>
            <div
              v-for="ing in confirmCraft.ingredients"
              :key="ing.element_id"
              class="flex items-center justify-between text-xs px-2 py-1 bg-slate-800/50 rounded"
            >
              <div class="flex items-center gap-1">
                <span>{{ ing.icon }}</span>
                <span class="text-slate-300">{{ ing.name }}</span>
              </div>
              <span :class="hasEnoughIngredient(ing.element_id, ing.quantity) ? 'text-green-400' : 'text-red-400'">
                {{ getOwnedQuantity(ing.element_id) }}/{{ ing.quantity }}
              </span>
            </div>
          </div>

          <!-- Error message -->
          <div v-if="craftResult?.error" class="text-xs text-red-400 text-center mb-3">
            {{ craftResult.error }}
          </div>

          <div class="flex gap-2">
            <button
              @click="confirmCraft = null; craftResult = null"
              class="flex-1 px-3 py-2 text-sm bg-slate-700 hover:bg-slate-600 text-slate-300 rounded-lg transition-colors"
            >
              {{ t('common.cancel', 'Cancel') }}
            </button>
            <button
              @click="executeCraft"
              :disabled="craftingStore.crafting"
              class="flex-1 px-3 py-2 text-sm bg-accent-primary hover:bg-accent-primary/80 disabled:opacity-50 text-white rounded-lg transition-colors flex items-center justify-center gap-1"
            >
              <svg v-if="craftingStore.crafting" class="animate-spin w-3 h-3" viewBox="0 0 24 24"><circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" fill="none"/><path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"/></svg>
              {{ t('crafting.craft', 'Craft') }}
            </button>
          </div>
        </template>
      </div>
    </div>
  </div>
</template>
