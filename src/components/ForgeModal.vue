<script setup lang="ts">
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAuthStore } from '@/stores/auth';
import { useInventoryStore } from '@/stores/inventory';
import { useMiningStore } from '@/stores/mining';
import { getForgeRecipes, forgeCraftItem } from '@/utils/api';
import { playSound } from '@/utils/sounds';

const { t } = useI18n();
const authStore = useAuthStore();
const inventoryStore = useInventoryStore();
const miningStore = useMiningStore();

const props = defineProps<{
  show: boolean;
}>();

const emit = defineEmits<{
  close: [];
  crafted: [];
}>();

interface Ingredient {
  material_id: string;
  quantity: number;
  material_name: string;
  material_icon: string;
  material_rarity: string;
}

interface ForgeRecipe {
  id: string;
  name: string;
  category: string;
  result_type: string;
  result_id: string | null;
  result_value: number;
  tier: string;
  icon: string;
  ingredients: Ingredient[];
}

// State
const recipes = ref<ForgeRecipe[]>([]);
const loading = ref(false);
const crafting = ref(false);
const activeCategory = ref<string>('all');
const showConfirm = ref(false);
const selectedRecipe = ref<ForgeRecipe | null>(null);
const selectedTargetSlotId = ref<string>('');
const selectedTargetRigId = ref<string>('');
const craftResult = ref<{ success: boolean; type?: string; message?: string } | null>(null);

const categories = ['all', 'tier_kit', 'rig_enhancement', 'cooling', 'utility'] as const;

// Load recipes on mount
watch(() => props.show, async (show) => {
  if (show) {
    await loadData();
  } else {
    craftResult.value = null;
    showConfirm.value = false;
    selectedRecipe.value = null;
  }
});

async function loadData() {
  loading.value = true;
  try {
    const [recipesData] = await Promise.all([
      getForgeRecipes(),
      inventoryStore.fetchInventory(true),
    ]);
    recipes.value = recipesData || [];
  } catch (e) {
    console.error('Error loading forge data:', e);
  } finally {
    loading.value = false;
  }
}

// Materials from inventory
const materials = computed(() => inventoryStore.materialItems);

function getMaterialQty(materialId: string): number {
  const mat = materials.value.find(m => m.material_id === materialId);
  return mat?.quantity || 0;
}

// Filtered recipes
const filteredRecipes = computed(() => {
  if (activeCategory.value === 'all') return recipes.value;
  return recipes.value.filter(r => r.category === activeCategory.value);
});

// Check if player has enough materials for a recipe
function canCraft(recipe: ForgeRecipe): boolean {
  return recipe.ingredients.every(ing => getMaterialQty(ing.material_id) >= ing.quantity);
}

// Needs a target slot (tier kits, durability shield)
function needsSlotTarget(recipe: ForgeRecipe): boolean {
  return recipe.result_type === 'xp_grant' || (recipe.result_type === 'slot_buff' && recipe.id === 'durability_shield');
}

// Needs a target rig (rig enhancements)
function needsRigTarget(recipe: ForgeRecipe): boolean {
  return recipe.result_type === 'rig_boost';
}

// Available slots for targeting (non-destroyed, non-elite for tier kits)
const availableSlots = computed(() => {
  const slots = miningStore.slotInfo?.slots || [];
  return slots.filter(s => !s.is_destroyed);
});

// Available rigs for targeting
const availableRigs = computed(() => {
  return miningStore.rigs || [];
});

function requestCraft(recipe: ForgeRecipe) {
  selectedRecipe.value = recipe;
  selectedTargetSlotId.value = '';
  selectedTargetRigId.value = '';
  craftResult.value = null;

  if (needsSlotTarget(recipe) || needsRigTarget(recipe)) {
    showConfirm.value = true;
  } else {
    showConfirm.value = true;
  }
}

async function confirmCraft() {
  if (!selectedRecipe.value || !authStore.player?.id) return;

  const recipe = selectedRecipe.value;

  if (needsSlotTarget(recipe) && !selectedTargetSlotId.value) return;
  if (needsRigTarget(recipe) && !selectedTargetRigId.value) return;

  crafting.value = true;
  try {
    const result = await forgeCraftItem(
      authStore.player.id,
      recipe.id,
      selectedTargetSlotId.value || undefined,
      selectedTargetRigId.value || undefined,
    );

    if (result?.success) {
      playSound('success');
      craftResult.value = { success: true, type: result.type, message: recipe.name };
      await Promise.all([
        inventoryStore.fetchInventory(true),
        miningStore.loadData(),
      ]);
    } else {
      playSound('error');
      craftResult.value = { success: false, message: result?.error || 'Error' };
    }
  } catch (e) {
    console.error('Error crafting:', e);
    playSound('error');
    craftResult.value = { success: false, message: 'Connection error' };
  } finally {
    crafting.value = false;
    showConfirm.value = false;
  }
}

// Helpers
function getTierColor(tier: string): string {
  switch (tier) {
    case 'elite': return 'text-amber-400';
    case 'advanced': return 'text-fuchsia-400';
    case 'standard': return 'text-sky-400';
    case 'basic': return 'text-emerald-400';
    default: return 'text-text-muted';
  }
}

function getTierBg(tier: string): string {
  switch (tier) {
    case 'elite': return 'bg-amber-400/10 border-amber-400/30';
    case 'advanced': return 'bg-fuchsia-400/10 border-fuchsia-400/30';
    case 'standard': return 'bg-sky-400/10 border-sky-400/30';
    case 'basic': return 'bg-emerald-400/10 border-emerald-400/30';
    default: return 'bg-white/5 border-border/30';
  }
}

function getRarityColor(rarity: string): string {
  switch (rarity) {
    case 'epic': return 'text-fuchsia-400';
    case 'rare': return 'text-amber-400';
    case 'uncommon': return 'text-sky-400';
    case 'common': return 'text-emerald-400';
    default: return 'text-text-muted';
  }
}

function getRecipeName(recipe: ForgeRecipe): string {
  const key = `forge.recipes.${recipe.name}`;
  const translated = t(key);
  return translated !== key ? translated : recipe.name.replace(/_/g, ' ').replace(/\bcraft\s*/i, '');
}

function getCategoryLabel(cat: string): string {
  if (cat === 'all') return t('forge.categories.all');
  return t(`forge.categories.${cat}`);
}

function getMaterialName(name: string): string {
  const key = `materials.${name}.name`;
  const translated = t(key);
  return translated !== key ? translated : name.replace(/_/g, ' ');
}

function getResultDescription(recipe: ForgeRecipe): string {
  switch (recipe.result_type) {
    case 'xp_grant': return `+${recipe.result_value} XP`;
    case 'rig_boost':
      if (recipe.id === 'hashrate_booster') return `+${recipe.result_value}% Hashrate`;
      if (recipe.id === 'efficiency_module') return `-${recipe.result_value}% ${t('forge.energy')}`;
      if (recipe.id === 'thermal_paste_pro') return `-${recipe.result_value}% ${t('forge.heat')}`;
      return `+${recipe.result_value}%`;
    case 'cooling_component': return t('forge.addsToInventory');
    case 'slot_buff':
      if (recipe.id === 'durability_shield') return `+${recipe.result_value} ${t('forge.uses')}`;
      if (recipe.id === 'slot_protector') return t('forge.protectsSlot');
      return '';
    default: return '';
  }
}
</script>

<template>
  <Teleport to="body">
    <Transition name="fade">
      <div
        v-if="show"
        class="fixed inset-0 z-[55] bg-black/60 backdrop-blur-sm flex items-center justify-center p-4"
        @click.self="emit('close')"
      >
        <div class="card p-0 max-w-2xl w-full border border-border/50 shadow-2xl relative animate-scale-in flex flex-col h-[85vh]">
          <!-- Header -->
          <div class="p-4 border-b border-border/30 flex-shrink-0">
            <div class="flex items-center justify-between">
              <div class="flex items-center gap-3">
                <div class="w-10 h-10 rounded-xl bg-gradient-to-br from-orange-500 to-amber-600 flex items-center justify-center text-xl">
                  🔨
                </div>
                <div>
                  <h2 class="text-lg font-bold text-text-primary">{{ t('forge.title') }}</h2>
                  <p class="text-xs text-text-muted">{{ t('forge.subtitle') }}</p>
                </div>
              </div>
              <button @click="emit('close')" class="text-text-muted hover:text-text-primary transition-colors text-xl leading-none p-1">✕</button>
            </div>

            <!-- Materials bar -->
            <div class="flex flex-wrap gap-2 mt-3">
              <div
                v-for="mat in materials"
                :key="mat.material_id"
                class="flex items-center gap-1 px-2 py-1 rounded-lg bg-white/5 border border-border/20 text-xs"
              >
                <span>{{ mat.icon }}</span>
                <span :class="getRarityColor(mat.rarity)" class="font-medium">{{ getMaterialName(mat.name) }}</span>
                <span class="text-text-primary font-bold">x{{ mat.quantity }}</span>
              </div>
              <div v-if="materials.length === 0" class="text-xs text-text-muted italic">
                {{ t('forge.noMaterials') }}
              </div>
            </div>
          </div>

          <!-- Category filter -->
          <div class="px-4 py-2 border-b border-border/20 flex-shrink-0 overflow-x-auto">
            <div class="flex gap-1">
              <button
                v-for="cat in categories"
                :key="cat"
                @click="activeCategory = cat"
                class="px-3 py-1 rounded-lg text-xs font-medium whitespace-nowrap transition-all"
                :class="activeCategory === cat ? 'bg-accent/20 text-accent border border-accent/30' : 'bg-white/5 text-text-muted hover:text-text-primary border border-transparent'"
              >
                {{ getCategoryLabel(cat) }}
              </button>
            </div>
          </div>

          <!-- Recipes grid -->
          <div class="flex-1 overflow-y-auto p-4 custom-scrollbar">
            <!-- Loading -->
            <div v-if="loading" class="text-center py-8 text-text-muted text-sm">
              {{ t('forge.loading') }}
            </div>

            <!-- Craft result banner -->
            <div v-if="craftResult" class="mb-3 p-3 rounded-lg border" :class="craftResult.success ? 'bg-emerald-500/10 border-emerald-500/30' : 'bg-red-500/10 border-red-500/30'">
              <p class="text-sm font-medium" :class="craftResult.success ? 'text-emerald-400' : 'text-red-400'">
                {{ craftResult.success ? t('forge.craftSuccess') : (craftResult.message || t('forge.craftError')) }}
              </p>
            </div>

            <!-- Recipe cards -->
            <div v-if="!loading" class="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <div
                v-for="recipe in filteredRecipes"
                :key="recipe.id"
                class="p-3 rounded-lg border transition-all"
                :class="getTierBg(recipe.tier)"
              >
                <!-- Recipe header -->
                <div class="flex items-start justify-between mb-2">
                  <div class="flex items-center gap-2">
                    <span class="text-lg">{{ recipe.icon }}</span>
                    <div>
                      <h3 class="text-sm font-semibold text-text-primary leading-tight">{{ getRecipeName(recipe) }}</h3>
                      <span class="text-[10px] font-bold uppercase" :class="getTierColor(recipe.tier)">{{ recipe.tier }}</span>
                    </div>
                  </div>
                </div>

                <!-- Result description -->
                <p class="text-xs text-text-muted mb-2">{{ getResultDescription(recipe) }}</p>

                <!-- Ingredients -->
                <div class="flex flex-wrap gap-1 mb-3">
                  <div
                    v-for="ing in recipe.ingredients"
                    :key="ing.material_id"
                    class="flex items-center gap-0.5 px-1.5 py-0.5 rounded text-[11px] border"
                    :class="getMaterialQty(ing.material_id) >= ing.quantity ? 'bg-emerald-500/10 border-emerald-500/30 text-emerald-400' : 'bg-red-500/10 border-red-500/30 text-red-400'"
                  >
                    <span>{{ ing.material_icon }}</span>
                    <span>{{ getMaterialQty(ing.material_id) }}/{{ ing.quantity }}</span>
                  </div>
                </div>

                <!-- Craft button -->
                <button
                  @click="requestCraft(recipe)"
                  :disabled="!canCraft(recipe) || crafting"
                  class="w-full py-1.5 rounded-lg text-xs font-semibold transition-all"
                  :class="canCraft(recipe) ? 'bg-accent/20 text-accent hover:bg-accent/30 border border-accent/30' : 'bg-white/5 text-text-muted border border-border/20 cursor-not-allowed'"
                >
                  {{ crafting ? t('forge.crafting') : t('forge.craft') }}
                </button>
              </div>
            </div>

            <div v-if="!loading && filteredRecipes.length === 0" class="text-center py-8 text-text-muted text-sm">
              {{ t('forge.noRecipes') }}
            </div>
          </div>
        </div>

        <!-- Confirm dialog -->
        <Transition name="fade">
          <div
            v-if="showConfirm && selectedRecipe"
            class="fixed inset-0 z-[65] bg-black/50 flex items-center justify-center p-4"
            @click.self="showConfirm = false"
          >
            <div class="card p-5 max-w-sm w-full border border-border/50 shadow-2xl animate-scale-in">
              <h3 class="text-base font-bold text-text-primary mb-3 flex items-center gap-2">
                <span>{{ selectedRecipe.icon }}</span>
                {{ t('forge.confirmTitle') }}
              </h3>

              <p class="text-sm text-text-muted mb-3">
                {{ t('forge.confirmCraft', { item: getRecipeName(selectedRecipe) }) }}
              </p>

              <!-- Ingredients summary -->
              <div class="space-y-1 mb-3">
                <div
                  v-for="ing in selectedRecipe.ingredients"
                  :key="ing.material_id"
                  class="flex items-center justify-between text-xs"
                >
                  <span class="flex items-center gap-1">
                    <span>{{ ing.material_icon }}</span>
                    <span class="text-text-muted">{{ getMaterialName(ing.material_name) }}</span>
                  </span>
                  <span class="font-mono" :class="getMaterialQty(ing.material_id) >= ing.quantity ? 'text-emerald-400' : 'text-red-400'">
                    {{ getMaterialQty(ing.material_id) }}/{{ ing.quantity }}
                  </span>
                </div>
              </div>

              <!-- Slot selector -->
              <div v-if="needsSlotTarget(selectedRecipe)" class="mb-3">
                <label class="text-xs text-text-muted mb-1 block">{{ t('forge.selectSlot') }}</label>
                <select v-model="selectedTargetSlotId" class="w-full bg-bg-tertiary border border-border/30 rounded-lg px-3 py-2 text-sm text-text-primary">
                  <option value="">-- {{ t('forge.selectSlot') }} --</option>
                  <option v-for="slot in availableSlots" :key="slot.id" :value="slot.id">
                    Slot #{{ slot.slot_number }} ({{ slot.tier || 'basic' }} · {{ slot.xp || 0 }} XP)
                  </option>
                </select>
              </div>

              <!-- Rig selector -->
              <div v-if="needsRigTarget(selectedRecipe)" class="mb-3">
                <label class="text-xs text-text-muted mb-1 block">{{ t('forge.selectRig') }}</label>
                <select v-model="selectedTargetRigId" class="w-full bg-bg-tertiary border border-border/30 rounded-lg px-3 py-2 text-sm text-text-primary">
                  <option value="">-- {{ t('forge.selectRig') }} --</option>
                  <option v-for="rig in availableRigs" :key="rig.id" :value="rig.id">
                    {{ rig.rig.name }} (H:{{ rig.hashrate_level }} E:{{ rig.efficiency_level }} T:{{ rig.thermal_level }})
                  </option>
                </select>
              </div>

              <!-- Buttons -->
              <div class="flex gap-2">
                <button
                  @click="showConfirm = false"
                  class="flex-1 py-2 rounded-lg text-xs font-semibold bg-white/5 text-text-muted hover:text-text-primary border border-border/30 transition-colors"
                >
                  {{ t('forge.cancel') }}
                </button>
                <button
                  @click="confirmCraft"
                  :disabled="crafting || (needsSlotTarget(selectedRecipe) && !selectedTargetSlotId) || (needsRigTarget(selectedRecipe) && !selectedTargetRigId)"
                  class="flex-1 py-2 rounded-lg text-xs font-semibold transition-all"
                  :class="crafting ? 'bg-white/5 text-text-muted' : 'bg-accent/20 text-accent hover:bg-accent/30 border border-accent/30'"
                >
                  {{ crafting ? t('forge.crafting') : t('forge.confirmBtn') }}
                </button>
              </div>
            </div>
          </div>
        </Transition>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
.fade-enter-active,
.fade-leave-active {
  transition: opacity 0.3s ease;
}
.fade-enter-from,
.fade-leave-to {
  opacity: 0;
}
@keyframes scale-in {
  from { opacity: 0; transform: scale(0.9); }
  to { opacity: 1; transform: scale(1); }
}
.animate-scale-in {
  animation: scale-in 0.3s ease-out;
}
.custom-scrollbar::-webkit-scrollbar { width: 8px; }
.custom-scrollbar::-webkit-scrollbar-track { background: rgba(255,255,255,0.05); border-radius: 4px; }
.custom-scrollbar::-webkit-scrollbar-thumb { background: rgba(245,158,11,0.3); border-radius: 4px; }
.custom-scrollbar::-webkit-scrollbar-thumb:hover { background: rgba(245,158,11,0.5); }
</style>
