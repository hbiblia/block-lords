import { defineStore } from 'pinia';
import { ref, computed } from 'vue';
import { getPlayerInventory, getPlayerBoosts, getPlayerRigInventory, installRigFromInventory, getPlayerMaterials, deleteInventoryItem } from '@/utils/api';
import { useAuthStore } from './auth';
import { playSound } from '@/utils/sounds';

export interface RigItem {
  rig_id: string;
  quantity: number;
  name: string;
  description: string;
  hashrate: number;
  power_consumption: number;
  internet_consumption: number;
  tier: string;
}

export interface CoolingItem {
  inventory_id: string;
  quantity: number;
  purchased_at: string;
  id: string;
  name: string;
  description: string;
  cooling_power: number;
  energy_cost: number;
  base_price: number;
  tier: string;
  max_mod_slots: number;
}

export interface ModdedCoolingItem {
  player_cooling_item_id: string;
  cooling_item_id: string;
  mods: CoolingMod[];
  mod_slots_used: number;
  max_mod_slots: number;
  created_at: string;
  name: string;
  description: string;
  cooling_power: number;
  energy_cost: number;
  base_price: number;
  tier: string;
  effective_cooling_power: number;
  effective_energy_cost: number;
  total_durability_mod: number;
}

export interface CoolingMod {
  component_id: string;
  slot: number;
  cooling_power_mod: number;
  energy_cost_mod: number;
  durability_mod: number;
}

export interface CoolingComponentItem {
  inventory_id: string;
  quantity: number;
  id: string;
  name: string;
  description: string;
  tier: string;
  base_price: number;
  cooling_power_min: number;
  cooling_power_max: number;
  energy_cost_min: number;
  energy_cost_max: number;
  durability_min: number;
  durability_max: number;
}

export interface CardItem {
  id: string;
  code: string;
  is_redeemed: boolean;
  purchased_at: string;
  card_id: string;
  name: string;
  description: string;
  card_type: 'energy' | 'internet';
  amount: number;
  tier: string;
}

export interface BoostItem {
  id: string;
  quantity: number;
  purchased_at: string;
  boost_id: string;
  name: string;
  description: string;
  boost_type: string;
  effect_value: number;
  secondary_value: number;
  duration_minutes: number;
  tier: string;
}

export interface ActiveBoost {
  id: string;
  boost_id: string;
  boost_type: string;
  name: string;
  expires_at: string;
  seconds_remaining: number;
}

export interface MaterialItem {
  material_id: string;
  quantity: number;
  name: string;
  rarity: 'common' | 'uncommon' | 'rare' | 'epic';
  icon: string;
  drop_chance: number;
}

export interface PatchItem {
  inventory_id: string;
  item_id: string;
  quantity: number;
}

export const useInventoryStore = defineStore('inventory', () => {
  const rigItems = ref<RigItem[]>([]);
  const coolingItems = ref<CoolingItem[]>([]);
  const moddedCoolingItems = ref<ModdedCoolingItem[]>([]);
  const componentItems = ref<CoolingComponentItem[]>([]);
  const cardItems = ref<CardItem[]>([]);
  const boostItems = ref<BoostItem[]>([]);
  const activeBoosts = ref<ActiveBoost[]>([]);
  const materialItems = ref<MaterialItem[]>([]);
  const patchItems = ref<PatchItem[]>([]);

  const loading = ref(false);
  const installing = ref(false);
  const loaded = ref(false);
  const lastLoadTime = ref<number>(0);

  // Cache duration: 30 seconds
  const CACHE_DURATION = 30000;

  const hasCachedData = computed(() => {
    if (!loaded.value) return false;
    return Date.now() - lastLoadTime.value < CACHE_DURATION;
  });

  const totalItems = computed(() =>
    rigItems.value.reduce((sum, r) => sum + r.quantity, 0) +
    cardItems.value.length +
    coolingItems.value.length +
    moddedCoolingItems.value.length +
    componentItems.value.reduce((sum, c) => sum + c.quantity, 0) +
    boostItems.value.length
  );

  // Inventory slot system: count unique item types (1 type = 1 slot)
  const slotsUsed = computed(() =>
    rigItems.value.length +
    new Set(cardItems.value.map(c => c.card_id)).size +
    coolingItems.value.length +
    moddedCoolingItems.value.length +
    componentItems.value.length +
    boostItems.value.length +
    materialItems.value.length +
    patchItems.value.length
  );

  const maxSlots = computed(() => {
    const authStore = useAuthStore();
    const p = authStore.player;
    if (p?.premium_until && new Date(p.premium_until) > new Date()) return 20;
    return 10;
  });

  async function fetchInventory(force = false) {
    const authStore = useAuthStore();

    // Wait for player to be available (max 5 seconds)
    if (!authStore.player?.id) {
      loading.value = true;
      for (let i = 0; i < 50; i++) {
        await new Promise(resolve => setTimeout(resolve, 100));
        if (authStore.player?.id) break;
      }
      if (!authStore.player?.id) {
        console.error('Inventory: No player available after waiting');
        loading.value = false;
        return;
      }
    }

    // Use cache if available and not forcing refresh
    if (!force && hasCachedData.value) {
      return;
    }

    loading.value = true;

    try {
      const playerId = authStore.player.id;

      // Fetch all data in parallel with individual error handling
      const [inventoryData, boostData, rigData, materialsData] = await Promise.all([
        getPlayerInventory(playerId).catch(e => {
          console.error('Error fetching inventory:', e);
          return { cards: [], cooling: [], modded_cooling: [], components: [] };
        }),
        getPlayerBoosts(playerId).catch(e => {
          console.error('Error fetching boosts:', e);
          return { inventory: [], active: [] };
        }),
        getPlayerRigInventory(playerId).catch(e => {
          console.error('Error fetching rig inventory:', e);
          return [];
        }),
        getPlayerMaterials(playerId).catch(e => {
          console.error('Error fetching materials:', e);
          return [];
        }),
      ]);

      cardItems.value = inventoryData?.cards || [];
      coolingItems.value = inventoryData?.cooling || [];
      moddedCoolingItems.value = inventoryData?.modded_cooling || [];
      componentItems.value = inventoryData?.components || [];
      boostItems.value = boostData?.inventory || [];
      activeBoosts.value = boostData?.active || [];
      rigItems.value = rigData || [];
      materialItems.value = materialsData || [];
      patchItems.value = inventoryData?.patches || [];

      loaded.value = true;
      lastLoadTime.value = Date.now();
    } catch (e) {
      console.error('Error loading inventory:', e);
    } finally {
      loading.value = false;
    }
  }

  // Install rig from inventory
  async function installRig(rigId: string): Promise<{ success: boolean; error?: string }> {
    const authStore = useAuthStore();
    if (!authStore.player?.id) return { success: false, error: 'No player' };

    installing.value = true;

    try {
      const result = await installRigFromInventory(authStore.player.id, rigId);

      if (result?.success) {
        // Refresh inventory and player data
        await Promise.all([
          fetchInventory(true),
          authStore.fetchPlayer(),
        ]);
        playSound('success');
        return { success: true };
      }

      playSound('error');
      return { success: false, error: result?.error || 'Error instalando rig' };
    } catch (e) {
      console.error('Error installing rig:', e);
      playSound('error');
      return { success: false, error: 'Error de conexión' };
    } finally {
      installing.value = false;
    }
  }

  const deleting = ref(false);

  // Delete/discard item from inventory
  async function deleteItem(itemType: string, itemId: string, quantity: number = 1): Promise<{ success: boolean; error?: string }> {
    const authStore = useAuthStore();
    if (!authStore.player?.id) return { success: false, error: 'No player' };

    deleting.value = true;

    try {
      const result = await deleteInventoryItem(authStore.player.id, itemType, itemId, quantity);

      if (result?.success) {
        await fetchInventory(true);
        playSound('success');
        return { success: true };
      }

      playSound('error');
      return { success: false, error: result?.error || 'Error eliminando item' };
    } catch (e) {
      console.error('Error deleting item:', e);
      playSound('error');
      return { success: false, error: 'Error de conexión' };
    } finally {
      deleting.value = false;
    }
  }

  // Force refresh after an action (redeem card, etc.)
  async function refresh() {
    return fetchInventory(true);
  }

  // Clear cache (on logout)
  function clear() {
    rigItems.value = [];
    coolingItems.value = [];
    moddedCoolingItems.value = [];
    componentItems.value = [];
    cardItems.value = [];
    boostItems.value = [];
    activeBoosts.value = [];
    materialItems.value = [];
    patchItems.value = [];
    loaded.value = false;
    lastLoadTime.value = 0;
  }

  return {
    rigItems,
    coolingItems,
    moddedCoolingItems,
    componentItems,
    cardItems,
    boostItems,
    activeBoosts,
    materialItems,
    patchItems,
    loading,
    installing,
    deleting,
    loaded,
    totalItems,
    slotsUsed,
    maxSlots,
    hasCachedData,
    fetchInventory,
    installRig,
    deleteItem,
    refresh,
    clear,
  };
});
