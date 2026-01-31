import { defineStore } from 'pinia';
import { ref, computed } from 'vue';
import { supabase } from '@/utils/supabase';
import { useAuthStore } from './auth';
import { playSound } from '@/utils/sounds';

// Types
interface Rig {
  id: string;
  name: string;
  description: string;
  hashrate: number;
  power_consumption: number;
  internet_consumption: number;
  repair_cost: number;
  tier: string;
  base_price: number;
}

interface CoolingItem {
  id: string;
  name: string;
  description: string;
  cooling_power: number;
  base_price: number;
  tier: string;
}

interface PrepaidCard {
  id: string;
  name: string;
  description: string;
  card_type: 'energy' | 'internet';
  amount: number;
  base_price: number;
  tier: string;
  currency: 'gamecoin' | 'crypto';
}

interface BoostItem {
  id: string;
  name: string;
  description: string;
  boost_type: string;
  effect_value: number;
  secondary_value: number;
  duration_minutes: number;
  base_price: number;
  currency: 'gamecoin' | 'crypto';
  tier: string;
}

interface CoolingQuantity {
  installed: number;
  inventory: number;
}

export const useMarketStore = defineStore('market', () => {
  // Catalogs (rarely change, loaded once)
  const rigs = ref<Rig[]>([]);
  const coolingItems = ref<CoolingItem[]>([]);
  const prepaidCards = ref<PrepaidCard[]>([]);
  const boostItems = ref<BoostItem[]>([]);

  // Player quantities
  const rigQuantities = ref<Record<string, number>>({});
  const coolingQuantities = ref<Record<string, CoolingQuantity>>({});
  const cardQuantities = ref<Record<string, number>>({});
  const boostQuantities = ref<Record<string, number>>({});

  // Loading states
  const loadingCatalogs = ref(false);
  const loadingQuantities = ref(false);
  const catalogsLoaded = ref(false);
  const buying = ref(false);

  // Computed
  const rigsForSale = computed(() =>
    rigs.value.filter(r => r.base_price > 0)
  );

  const energyCards = computed(() =>
    prepaidCards.value.filter(c => c.card_type === 'energy')
  );

  const internetCards = computed(() =>
    prepaidCards.value.filter(c => c.card_type === 'internet')
  );

  const loading = computed(() => loadingCatalogs.value || loadingQuantities.value);

  // Getters
  function getRigOwned(id: string): number {
    return rigQuantities.value[id] || 0;
  }

  function getCoolingOwned(id: string): { installed: number; inventory: number; total: number } {
    const q = coolingQuantities.value[id] || { installed: 0, inventory: 0 };
    return { ...q, total: q.installed + q.inventory };
  }

  function getCardOwned(id: string): number {
    return cardQuantities.value[id] || 0;
  }

  function getBoostOwned(id: string): number {
    return boostQuantities.value[id] || 0;
  }

  // Load catalogs (only once per session)
  async function loadCatalogs(force = false) {
    if (catalogsLoaded.value && !force) return;

    loadingCatalogs.value = true;
    try {
      const [rigsRes, coolingRes, cardsRes, boostsRes] = await Promise.all([
        supabase.from('rigs').select('*').order('base_price', { ascending: true }),
        supabase.from('cooling_items').select('*').order('base_price', { ascending: true }),
        supabase.from('prepaid_cards').select('*').order('base_price', { ascending: true }),
        supabase.from('boost_items').select('*').order('boost_type').order('base_price', { ascending: true }),
      ]);

      rigs.value = rigsRes.data ?? [];
      coolingItems.value = coolingRes.data ?? [];
      prepaidCards.value = cardsRes.data ?? [];
      boostItems.value = boostsRes.data ?? [];
      catalogsLoaded.value = true;
    } catch (e) {
      console.error('Error loading market catalogs:', e);
    } finally {
      loadingCatalogs.value = false;
    }
  }

  // Load player quantities (can be refreshed after purchases)
  async function loadPlayerQuantities() {
    const authStore = useAuthStore();
    if (!authStore.player?.id) return;

    loadingQuantities.value = true;
    const playerId = authStore.player.id;

    try {
      const [playerRigsRes, playerCoolingRes, inventoryCoolingRes, inventoryCardsRes, inventoryBoostsRes] = await Promise.all([
        supabase.from('player_rigs').select('rig_id').eq('player_id', playerId),
        supabase.from('player_cooling').select('cooling_item_id').eq('player_id', playerId),
        supabase.from('player_inventory').select('item_id, quantity').eq('player_id', playerId).eq('item_type', 'cooling'),
        supabase.from('player_prepaid_cards').select('card_id').eq('player_id', playerId).eq('is_redeemed', false),
        supabase.from('player_boosts').select('boost_id, quantity').eq('player_id', playerId),
      ]);

      // Build rig quantities map
      const rigQty: Record<string, number> = {};
      for (const r of playerRigsRes.data ?? []) {
        rigQty[r.rig_id] = (rigQty[r.rig_id] || 0) + 1;
      }
      rigQuantities.value = rigQty;

      // Build cooling quantities map
      const quantities: Record<string, CoolingQuantity> = {};
      for (const c of playerCoolingRes.data ?? []) {
        if (!quantities[c.cooling_item_id]) {
          quantities[c.cooling_item_id] = { installed: 0, inventory: 0 };
        }
        quantities[c.cooling_item_id].installed++;
      }
      for (const c of inventoryCoolingRes.data ?? []) {
        if (!quantities[c.item_id]) {
          quantities[c.item_id] = { installed: 0, inventory: 0 };
        }
        quantities[c.item_id].inventory += c.quantity || 1;
      }
      coolingQuantities.value = quantities;

      // Build card quantities map
      const cardQty: Record<string, number> = {};
      for (const c of inventoryCardsRes.data ?? []) {
        cardQty[c.card_id] = (cardQty[c.card_id] || 0) + 1;
      }
      cardQuantities.value = cardQty;

      // Build boost quantities map
      const boostQty: Record<string, number> = {};
      for (const b of inventoryBoostsRes.data ?? []) {
        boostQty[b.boost_id] = (boostQty[b.boost_id] || 0) + (b.quantity || 1);
      }
      boostQuantities.value = boostQty;
    } catch (e) {
      console.error('Error loading player quantities:', e);
    } finally {
      loadingQuantities.value = false;
    }
  }

  // Load all data
  async function loadData() {
    await Promise.all([
      loadCatalogs(),
      loadPlayerQuantities(),
    ]);
  }

  // Purchase actions
  async function buyRig(rigId: string): Promise<{ success: boolean; error?: string }> {
    const authStore = useAuthStore();
    if (!authStore.player) return { success: false, error: 'No player' };

    buying.value = true;
    try {
      const { data, error } = await supabase.rpc('buy_rig', {
        p_player_id: authStore.player.id,
        p_rig_id: rigId,
      });

      if (error) throw error;

      if (data?.success) {
        await loadPlayerQuantities();
        await authStore.fetchPlayer();
        playSound('purchase');
        return { success: true };
      }

      playSound('error');
      return { success: false, error: data?.error ?? 'Error buying rig' };
    } catch (e) {
      console.error('Error buying rig:', e);
      playSound('error');
      return { success: false, error: 'Connection error' };
    } finally {
      buying.value = false;
    }
  }

  async function buyCooling(coolingId: string): Promise<{ success: boolean; error?: string }> {
    const authStore = useAuthStore();
    if (!authStore.player) return { success: false, error: 'No player' };

    buying.value = true;
    try {
      const { data, error } = await supabase.rpc('buy_cooling', {
        p_player_id: authStore.player.id,
        p_cooling_id: coolingId,
      });

      if (error) throw error;

      if (data?.success) {
        await loadPlayerQuantities();
        await authStore.fetchPlayer();
        playSound('purchase');
        return { success: true };
      }

      playSound('error');
      return { success: false, error: data?.error ?? 'Error buying cooling' };
    } catch (e) {
      console.error('Error buying cooling:', e);
      playSound('error');
      return { success: false, error: 'Connection error' };
    } finally {
      buying.value = false;
    }
  }

  async function buyCard(cardId: string): Promise<{ success: boolean; error?: string }> {
    const authStore = useAuthStore();
    if (!authStore.player) return { success: false, error: 'No player' };

    buying.value = true;
    try {
      const { data, error } = await supabase.rpc('buy_prepaid_card', {
        p_player_id: authStore.player.id,
        p_card_id: cardId,
      });

      if (error) throw error;

      if (data?.success) {
        await loadPlayerQuantities();
        await authStore.fetchPlayer();
        playSound('purchase');
        return { success: true };
      }

      playSound('error');
      return { success: false, error: data?.error ?? 'Error buying card' };
    } catch (e) {
      console.error('Error buying card:', e);
      playSound('error');
      return { success: false, error: 'Connection error' };
    } finally {
      buying.value = false;
    }
  }

  async function buyBoost(boostId: string): Promise<{ success: boolean; error?: string }> {
    const authStore = useAuthStore();
    if (!authStore.player) return { success: false, error: 'No player' };

    buying.value = true;
    try {
      const { data, error } = await supabase.rpc('buy_boost', {
        p_player_id: authStore.player.id,
        p_boost_id: boostId,
      });

      if (error) throw error;

      if (data?.success) {
        await loadPlayerQuantities();
        await authStore.fetchPlayer();
        playSound('purchase');
        return { success: true };
      }

      playSound('error');
      return { success: false, error: data?.error ?? 'Error buying boost' };
    } catch (e) {
      console.error('Error buying boost:', e);
      playSound('error');
      return { success: false, error: 'Connection error' };
    } finally {
      buying.value = false;
    }
  }

  function clearState() {
    rigQuantities.value = {};
    coolingQuantities.value = {};
    cardQuantities.value = {};
    boostQuantities.value = {};
    // Keep catalogs loaded
  }

  return {
    // Catalogs
    rigs,
    coolingItems,
    prepaidCards,
    boostItems,

    // Computed
    rigsForSale,
    energyCards,
    internetCards,
    loading,
    catalogsLoaded,
    buying,

    // Getters
    getRigOwned,
    getCoolingOwned,
    getCardOwned,
    getBoostOwned,

    // Actions
    loadCatalogs,
    loadPlayerQuantities,
    loadData,
    buyRig,
    buyCooling,
    buyCard,
    buyBoost,
    clearState,
  };
});
