import { defineStore } from 'pinia';
import { ref, computed } from 'vue';
import {
  startCraftingSession,
  tapCraftingElement,
  getCraftingSession,
  getCraftingInventory,
  getCraftingRecipes,
  craftRecipe,
  deleteCraftingElement,
  abandonCraftingSession,
} from '@/utils/api';
import { useAuthStore } from './auth';
import { playSound } from '@/utils/sounds';

export interface CraftingCell {
  index: number;
  element_id: string;
  icon: string;
  name: string;
  taps_required: number;
  taps_done: number;
  collected: boolean;
  rarity: string;
  requires_element: string | null;
}

export interface CraftingSession {
  id: string;
  player_id: string;
  zone_type: string;
  grid_config: CraftingCell[];
  elements_collected: number;
  status: string;
  created_at: string;
}

export interface CraftingInventoryItem {
  element_id: string;
  quantity: number;
  name: string;
  icon: string;
  zone_type: string;
  rarity: string;
}

export interface RecipeIngredient {
  element_id: string;
  quantity: number;
  name: string;
  icon: string;
}

export interface CraftingRecipe {
  id: string;
  name: string;
  category: string;
  output_item_type: string;
  output_item_id: string;
  gamecoin_reward: number;
  ingredients: RecipeIngredient[];
}

export type CraftingTab = 'zone' | 'inventory' | 'recipes';
export type RecipeCategory = 'all' | 'cooling' | 'boost' | 'card' | 'sellable';

export const useCraftingStore = defineStore('crafting', () => {
  // State
  const currentSession = ref<CraftingSession | null>(null);
  const cooldownEndsAt = ref<string | null>(null);
  const cooldownRemainingSeconds = ref(0);
  const craftingItems = ref<CraftingInventoryItem[]>([]);
  const recipes = ref<CraftingRecipe[]>([]);
  const activeTab = ref<CraftingTab>('zone');
  const showModal = ref(false);

  // Loading states
  const loading = ref(false);
  const tapping = ref(false);
  const crafting = ref(false);
  const starting = ref(false);

  // Reward overlay
  const showReward = ref(false);
  const lastReward = ref<{ gamecoin: number; elements: CraftingInventoryItem[] } | null>(null);

  // Cooldown timer
  let cooldownInterval: ReturnType<typeof setInterval> | null = null;

  // Computed
  const hasActiveSession = computed(() => currentSession.value?.status === 'active');

  const sessionProgress = computed(() => {
    if (!currentSession.value) return 0;
    return currentSession.value.elements_collected;
  });

  const cooldownFormatted = computed(() => {
    const s = cooldownRemainingSeconds.value;
    if (s <= 0) return '';
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    const sec = s % 60;
    return `${h}h ${m.toString().padStart(2, '0')}m ${sec.toString().padStart(2, '0')}s`;
  });

  const isOnCooldown = computed(() => cooldownRemainingSeconds.value > 0);

  const totalCraftingItems = computed(() =>
    craftingItems.value.reduce((sum, item) => sum + item.quantity, 0)
  );

  const gridWithLockState = computed(() => {
    if (!currentSession.value?.grid_config) return [];
    const grid = currentSession.value.grid_config;
    const collectedElementIds = new Set(
      grid.filter((c) => c.collected).map((c) => c.element_id)
    );
    return grid.map((cell) => ({
      ...cell,
      locked: !!cell.requires_element && !collectedElementIds.has(cell.requires_element),
    }));
  });

  function canCraftRecipe(recipe: CraftingRecipe): boolean {
    return recipe.ingredients.every((ingredient) => {
      const item = craftingItems.value.find((i) => i.element_id === ingredient.element_id);
      return item && item.quantity >= ingredient.quantity;
    });
  }

  function filteredRecipes(category: RecipeCategory): CraftingRecipe[] {
    if (category === 'all') return recipes.value;
    return recipes.value.filter((r) => r.category === category);
  }

  // Cooldown timer management
  function startCooldownTimer() {
    stopCooldownTimer();
    if (!cooldownEndsAt.value) return;

    const updateCooldown = () => {
      const endsAt = new Date(cooldownEndsAt.value!).getTime();
      const now = Date.now();
      const remaining = Math.max(0, Math.floor((endsAt - now) / 1000));
      cooldownRemainingSeconds.value = remaining;
      if (remaining <= 0) {
        stopCooldownTimer();
        cooldownEndsAt.value = null;
      }
    };

    updateCooldown();
    cooldownInterval = setInterval(updateCooldown, 1000);
  }

  function stopCooldownTimer() {
    if (cooldownInterval) {
      clearInterval(cooldownInterval);
      cooldownInterval = null;
    }
  }

  // Helper: Supabase RPC with RETURNS JSON can sometimes return a string instead of parsed object
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  function parseResponse(data: any): any {
    if (typeof data === 'string') {
      try { return JSON.parse(data); } catch { return data; }
    }
    return data;
  }

  // Actions
  async function loadAllData() {
    const authStore = useAuthStore();
    if (!authStore.player?.id) return;

    loading.value = true;
    try {
      const [rawSession, rawInventory, rawRecipes] = await Promise.all([
        getCraftingSession(authStore.player.id).catch((e) => {
          console.warn('[Crafting] getCraftingSession error:', e);
          return null;
        }),
        getCraftingInventory(authStore.player.id).catch((e) => {
          console.warn('[Crafting] getCraftingInventory error:', e);
          return null;
        }),
        getCraftingRecipes().catch((e) => {
          console.warn('[Crafting] getCraftingRecipes error:', e);
          return null;
        }),
      ]);

      const sessionData = parseResponse(rawSession);
      const inventoryData = parseResponse(rawInventory);
      const recipesData = parseResponse(rawRecipes);

      console.log('[Crafting] sessionData:', JSON.stringify(sessionData));

      // Process session (API returns grid as 'grid', normalize to 'grid_config')
      if (sessionData?.has_session && sessionData?.session) {
        const s = typeof sessionData.session === 'string' ? JSON.parse(sessionData.session) : sessionData.session;
        currentSession.value = {
          ...s,
          grid_config: s.grid || s.grid_config,
        };
      } else {
        currentSession.value = null;
      }

      // Process cooldown
      if (sessionData?.cooldown_remaining_seconds > 0) {
        const endsAt = new Date(Date.now() + sessionData.cooldown_remaining_seconds * 1000).toISOString();
        cooldownEndsAt.value = endsAt;
        startCooldownTimer();
      } else {
        cooldownEndsAt.value = null;
        cooldownRemainingSeconds.value = 0;
      }

      // Process inventory (API returns { success, items: [...] })
      const items = Array.isArray(inventoryData) ? inventoryData : (inventoryData?.items || []);
      craftingItems.value = typeof items === 'string' ? JSON.parse(items) : items;

      // Process recipes (API returns { success, recipes: [...] })
      const recipeList = Array.isArray(recipesData) ? recipesData : (recipesData?.recipes || []);
      recipes.value = typeof recipeList === 'string' ? JSON.parse(recipeList) : recipeList;
    } catch (e) {
      console.error('Error loading crafting data:', e);
    } finally {
      loading.value = false;
    }
  }

  async function startSession(): Promise<boolean> {
    const authStore = useAuthStore();
    if (!authStore.player?.id) return false;
    if (starting.value) return false; // Prevent double-calls

    starting.value = true;
    try {
      const raw = await startCraftingSession(authStore.player.id);
      const result = parseResponse(raw);
      console.log('[Crafting] startSession result:', JSON.stringify(result));
      if (result?.success && result.session_id) {
        // API returns flat { session_id, zone_type, grid }, construct session object
        const grid = typeof result.grid === 'string' ? JSON.parse(result.grid) : result.grid;
        currentSession.value = {
          id: result.session_id,
          player_id: authStore.player.id,
          zone_type: result.zone_type,
          grid_config: grid,
          elements_collected: 0,
          status: 'active',
          created_at: new Date().toISOString(),
        };
        cooldownEndsAt.value = null;
        cooldownRemainingSeconds.value = 0;
        stopCooldownTimer();
        playSound('success');
        return true;
      }
      if (result?.error) {
        // If session already exists, recover it from the returned data
        if (result.session_id && (result.error === 'Ya tienes una sesión activa' || result.error?.includes('sesión activa'))) {
          // start_crafting_session returns full session data on conflict
          if (result.session) {
            const s = typeof result.session === 'string' ? JSON.parse(result.session) : result.session;
            currentSession.value = {
              ...s,
              player_id: authStore.player.id,
              grid_config: s.grid || s.grid_config,
            };
            console.log('[Crafting] Recovered existing session:', result.session_id);
            return true;
          }
          // Fallback: reload all data
          await loadAllData();
          if (hasActiveSession.value) {
            return true;
          }
        }
        console.error('Error starting session:', result.error);
      }
      playSound('error');
      return false;
    } catch (e) {
      console.error('Error starting crafting session:', e);
      playSound('error');
      return false;
    } finally {
      starting.value = false;
    }
  }

  async function tapElement(cellIndex: number): Promise<boolean> {
    const authStore = useAuthStore();
    if (!authStore.player?.id || !currentSession.value) return false;

    tapping.value = true;
    try {
      const raw = await tapCraftingElement(
        authStore.player.id,
        currentSession.value.id,
        cellIndex
      );
      const result = parseResponse(raw);

      if (result?.success) {
        // Update grid locally (API returns 'cell_state', not 'cell')
        const cellState = result.cell_state || result.cell;
        if (cellState) {
          const grid = [...currentSession.value.grid_config];
          grid[cellIndex] = { ...grid[cellIndex], ...cellState };
          currentSession.value = {
            ...currentSession.value,
            grid_config: grid,
            elements_collected: cellState.collected
              ? currentSession.value.elements_collected + 1
              : currentSession.value.elements_collected,
          };
        }

        // Check if element was collected (API returns 'element_collected')
        if (result.element_collected) {
          playSound('reward');
        } else {
          playSound('click');
        }

        // Check if session completed
        if (result.session_completed) {
          currentSession.value = {
            ...currentSession.value,
            status: 'completed',
          };
          // Show reward (API returns rewards inside 'rewards' object)
          const rewards = result.rewards || {};
          lastReward.value = {
            gamecoin: rewards.gamecoin || 0,
            elements: [],
          };
          showReward.value = true;
          playSound('mission_complete');
          // Refresh inventory and session (to get cooldown)
          await loadAllData();
        }
        return true;
      }
      return false;
    } catch (e) {
      console.error('Error tapping element:', e);
      return false;
    } finally {
      tapping.value = false;
    }
  }

  async function loadInventory() {
    const authStore = useAuthStore();
    if (!authStore.player?.id) return;
    try {
      const raw = await getCraftingInventory(authStore.player.id);
      const data = parseResponse(raw);
      const items = Array.isArray(data) ? data : (data?.items || []);
      craftingItems.value = typeof items === 'string' ? JSON.parse(items) : items;
    } catch (e) {
      console.error('Error loading crafting inventory:', e);
    }
  }

  async function executeCraft(recipeId: string): Promise<{ success: boolean; error?: string }> {
    const authStore = useAuthStore();
    if (!authStore.player?.id) return { success: false, error: 'No player' };

    crafting.value = true;
    try {
      const raw = await craftRecipe(authStore.player.id, recipeId);
      const result = parseResponse(raw);
      if (result?.success) {
        playSound('purchase');
        // Refresh inventory after crafting
        await loadInventory();
        // Refresh player data (in case gamecoin changed)
        await authStore.fetchPlayer();
        return { success: true };
      }
      playSound('error');
      return { success: false, error: result?.error || 'Error crafting' };
    } catch (e) {
      console.error('Error crafting recipe:', e);
      playSound('error');
      return { success: false, error: 'Connection error' };
    } finally {
      crafting.value = false;
    }
  }

  async function deleteElement(elementId: string, quantity: number): Promise<boolean> {
    const authStore = useAuthStore();
    if (!authStore.player?.id) return false;

    try {
      const raw = await deleteCraftingElement(authStore.player.id, elementId, quantity);
      const result = parseResponse(raw);
      if (result?.success) {
        await loadInventory();
        return true;
      }
      return false;
    } catch (e) {
      console.error('Error deleting element:', e);
      return false;
    }
  }

  async function abandon(): Promise<boolean> {
    const authStore = useAuthStore();
    if (!authStore.player?.id || !currentSession.value) return false;

    try {
      const raw = await abandonCraftingSession(authStore.player.id, currentSession.value.id);
      const result = parseResponse(raw);
      if (result?.success) {
        currentSession.value = null;
        playSound('click');
        return true;
      }
      return false;
    } catch (e) {
      console.error('Error abandoning session:', e);
      return false;
    }
  }

  function openModal() {
    showModal.value = true;
    loadAllData();
  }

  function closeModal() {
    showModal.value = false;
  }

  function dismissReward() {
    showReward.value = false;
    lastReward.value = null;
    currentSession.value = null;
  }

  function clear() {
    currentSession.value = null;
    cooldownEndsAt.value = null;
    cooldownRemainingSeconds.value = 0;
    craftingItems.value = [];
    recipes.value = [];
    activeTab.value = 'zone';
    showModal.value = false;
    showReward.value = false;
    lastReward.value = null;
    loading.value = false;
    tapping.value = false;
    crafting.value = false;
    starting.value = false;
    stopCooldownTimer();
  }

  return {
    // State
    currentSession,
    cooldownRemainingSeconds,
    craftingItems,
    recipes,
    activeTab,
    showModal,
    loading,
    tapping,
    crafting,
    starting,
    showReward,
    lastReward,
    // Computed
    hasActiveSession,
    sessionProgress,
    cooldownFormatted,
    isOnCooldown,
    totalCraftingItems,
    gridWithLockState,
    // Methods
    canCraftRecipe,
    filteredRecipes,
    loadAllData,
    startSession,
    tapElement,
    loadInventory,
    executeCraft,
    deleteElement,
    abandon,
    openModal,
    closeModal,
    dismissReward,
    clear,
  };
});
