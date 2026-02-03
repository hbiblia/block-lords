import { defineStore } from 'pinia';
import { ref, computed } from 'vue';
import { getPlayerInventory, getPlayerBoosts, getPlayerRigInventory, installRigFromInventory } from '@/utils/api';
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

export const useInventoryStore = defineStore('inventory', () => {
  const rigItems = ref<RigItem[]>([]);
  const coolingItems = ref<CoolingItem[]>([]);
  const cardItems = ref<CardItem[]>([]);
  const boostItems = ref<BoostItem[]>([]);
  const activeBoosts = ref<ActiveBoost[]>([]);

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
    boostItems.value.length
  );

  async function fetchInventory(force = false) {
    const authStore = useAuthStore();
    if (!authStore.player?.id) return;

    // Use cache if available and not forcing refresh
    if (!force && hasCachedData.value) {
      return;
    }

    loading.value = true;

    try {
      const [inventoryData, boostData, rigData] = await Promise.all([
        getPlayerInventory(authStore.player.id),
        getPlayerBoosts(authStore.player.id),
        getPlayerRigInventory(authStore.player.id),
      ]);

      cardItems.value = inventoryData.cards || [];
      coolingItems.value = inventoryData.cooling || [];
      boostItems.value = boostData?.inventory || [];
      activeBoosts.value = boostData?.active || [];
      rigItems.value = rigData || [];

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

  // Force refresh after an action (redeem card, etc.)
  async function refresh() {
    return fetchInventory(true);
  }

  // Clear cache (on logout)
  function clear() {
    rigItems.value = [];
    coolingItems.value = [];
    cardItems.value = [];
    boostItems.value = [];
    activeBoosts.value = [];
    loaded.value = false;
    lastLoadTime.value = 0;
  }

  return {
    rigItems,
    coolingItems,
    cardItems,
    boostItems,
    activeBoosts,
    loading,
    installing,
    loaded,
    totalItems,
    hasCachedData,
    fetchInventory,
    installRig,
    refresh,
    clear,
  };
});
