import { defineStore } from 'pinia';
import { ref, computed } from 'vue';
import { supabase } from '@/utils/supabase';
import { useAuthStore } from './auth';
import { useInventoryStore } from './inventory';
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
  currency: 'gamecoin' | 'crypto' | 'ron';
}

interface CoolingItem {
  id: string;
  name: string;
  description: string;
  cooling_power: number;
  energy_cost: number;
  base_price: number;
  tier: string;
}

interface PrepaidCard {
  id: string;
  name: string;
  description: string;
  card_type: 'energy' | 'internet' | 'combo';
  amount: number;
  base_price: number;
  tier: string;
  currency: 'gamecoin' | 'crypto' | 'ron';
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
  currency: 'gamecoin' | 'crypto' | 'ron';
  tier: string;
}

export interface CoolingComponent {
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

interface ExpPack {
  id: string;
  name: string;
  description: string;
  xp_amount: number;
  base_price: number;
  tier: string;
}

interface CoolingQuantity {
  installed: number;
  inventory: number;
}

interface RigQuantity {
  installed: number;
  inventory: number;
}

interface CryptoPackage {
  id: string;
  name: string;
  description: string;
  crypto_amount: number;
  ron_price: number;
  bonus_percent: number;
  tier: string;
  is_featured: boolean;
  total_crypto: number;
}

// LocalStorage cache
const STORAGE_KEY = 'lootmine_market_cache';

interface MarketCache {
  rigs: Rig[];
  coolingItems: CoolingItem[];
  prepaidCards: PrepaidCard[];
  boostItems: BoostItem[];
  cryptoPackages: CryptoPackage[];
  expPacks: ExpPack[];
}


function loadFromCache(): MarketCache | null {
  try {
    const cached = localStorage.getItem(STORAGE_KEY);
    if (cached) {
      return JSON.parse(cached);
    }
  } catch (e) {
    console.error('Error loading market cache:', e);
  }
  return null;
}

function saveToCache(data: MarketCache) {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(data));
  } catch (e) {
    console.error('Error saving market cache:', e);
  }
}

export const useMarketStore = defineStore('market', () => {
  // Load from cache on init
  const cached = loadFromCache();

  // Catalogs - use cached data if available
  const rigs = ref<Rig[]>(cached?.rigs ?? []);
  const coolingItems = ref<CoolingItem[]>(cached?.coolingItems ?? []);
  const prepaidCards = ref<PrepaidCard[]>(cached?.prepaidCards ?? []);
  const boostItems = ref<BoostItem[]>(cached?.boostItems ?? []);
  const cryptoPackages = ref<CryptoPackage[]>(cached?.cryptoPackages ?? []);
  const expPacks = ref<ExpPack[]>(cached?.expPacks ?? []);

  // Cooling components catalog
  const coolingComponents = ref<CoolingComponent[]>([]);

  // Player quantities
  const rigQuantities = ref<Record<string, RigQuantity>>({});
  const coolingQuantities = ref<Record<string, CoolingQuantity>>({});
  const componentQuantities = ref<Record<string, number>>({});
  const cardQuantities = ref<Record<string, number>>({});
  const boostQuantities = ref<Record<string, number>>({});
  const patchQuantity = ref(0);
  const expPackQuantities = ref<Record<string, number>>({});

  // Loading states
  const loadingCatalogs = ref(false);
  const loadingQuantities = ref(false);
  const catalogsLoaded = ref(cached !== null);
  const buying = ref(false);
  const refreshing = ref(false); // True when reloading data (not first load)

  // Currency order for sorting (gamecoin first, then crypto, then ron)
  const currencyOrder: Record<string, number> = {
    gamecoin: 0,
    crypto: 1,
    ron: 2,
  };

  function sortByCurrencyAndPrice<T extends { base_price: number; currency?: string }>(items: T[]): T[] {
    return [...items].sort((a, b) => {
      const currA = currencyOrder[a.currency ?? 'gamecoin'] ?? 99;
      const currB = currencyOrder[b.currency ?? 'gamecoin'] ?? 99;
      if (currA !== currB) return currA - currB;
      return a.base_price - b.base_price;
    });
  }

  // Computed
  const rigsForSale = computed(() =>
    sortByCurrencyAndPrice(rigs.value.filter(r => r.base_price > 0))
  );

  const energyCards = computed(() =>
    sortByCurrencyAndPrice(prepaidCards.value.filter(c => c.card_type === 'energy'))
  );

  const internetCards = computed(() =>
    sortByCurrencyAndPrice(prepaidCards.value.filter(c => c.card_type === 'internet'))
  );

  const comboCards = computed(() =>
    sortByCurrencyAndPrice(prepaidCards.value.filter(c => c.card_type === 'combo'))
  );

  const loading = computed(() => loadingCatalogs.value || loadingQuantities.value);

  // Getters
  function getRigOwned(id: string): { installed: number; inventory: number; total: number } {
    const q = rigQuantities.value[id] || { installed: 0, inventory: 0 };
    return { ...q, total: q.installed + q.inventory };
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

  function getComponentOwned(id: string): number {
    return componentQuantities.value[id] || 0;
  }

  function getExpPackOwned(id: string): number {
    return expPackQuantities.value[id] || 0;
  }

  // Track if we've already fetched from server this session
  const catalogsFetched = ref(false);

  // Load catalogs (only fetches from server once per session unless forced)
  async function loadCatalogs(force = false) {
    if (catalogsFetched.value && !force) return;

    loadingCatalogs.value = true;
    try {
      const [rigsRes, coolingRes, cardsRes, boostsRes, cryptoRes, componentsRes, expPacksRes] = await Promise.all([
        supabase.from('rigs').select('*').order('base_price', { ascending: true }),
        supabase.from('cooling_items').select('*').order('base_price', { ascending: true }),
        supabase.from('prepaid_cards').select('*').order('base_price', { ascending: true }),
        supabase.from('boost_items').select('*').order('boost_type').order('base_price', { ascending: true }),
        supabase.rpc('get_crypto_packages'),
        supabase.rpc('get_cooling_components'),
        supabase.from('exp_packs').select('*').order('base_price', { ascending: true }),
      ]);

      rigs.value = rigsRes.data ?? [];
      coolingItems.value = coolingRes.data ?? [];
      prepaidCards.value = cardsRes.data ?? [];
      boostItems.value = boostsRes.data ?? [];
      cryptoPackages.value = cryptoRes.data ?? [];
      coolingComponents.value = componentsRes.data ?? [];
      expPacks.value = expPacksRes.data ?? [];
      catalogsFetched.value = true;
      catalogsLoaded.value = true;

      // Save to localStorage cache
      saveToCache({
        rigs: rigs.value,
        coolingItems: coolingItems.value,
        prepaidCards: prepaidCards.value,
        boostItems: boostItems.value,
        cryptoPackages: cryptoPackages.value,
        expPacks: expPacks.value,
      });
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
      const [playerRigsRes, rigInventoryRes, playerCoolingRes, inventoryCoolingRes, inventoryCardsRes, inventoryBoostsRes, inventoryComponentsRes, inventoryPatchRes, inventoryExpPacksRes] = await Promise.all([
        supabase.from('player_rigs').select('rig_id').eq('player_id', playerId),
        supabase.from('player_rig_inventory').select('rig_id, quantity').eq('player_id', playerId),
        supabase.from('player_cooling').select('cooling_item_id').eq('player_id', playerId),
        supabase.from('player_inventory').select('item_id, quantity').eq('player_id', playerId).eq('item_type', 'cooling'),
        supabase.from('player_cards').select('card_id').eq('player_id', playerId).eq('is_redeemed', false),
        supabase.from('player_boosts').select('boost_id, quantity').eq('player_id', playerId),
        supabase.from('player_inventory').select('item_id, quantity').eq('player_id', playerId).eq('item_type', 'component'),
        supabase.from('player_inventory').select('quantity').eq('player_id', playerId).eq('item_type', 'patch').eq('item_id', 'rig_patch').maybeSingle(),
        supabase.from('player_inventory').select('item_id, quantity').eq('player_id', playerId).eq('item_type', 'exp_pack'),
      ]);

      // Build rig quantities map (installed + inventory)
      const rigQty: Record<string, RigQuantity> = {};
      for (const r of playerRigsRes.data ?? []) {
        if (!rigQty[r.rig_id]) {
          rigQty[r.rig_id] = { installed: 0, inventory: 0 };
        }
        rigQty[r.rig_id].installed++;
      }
      for (const r of rigInventoryRes.data ?? []) {
        if (!rigQty[r.rig_id]) {
          rigQty[r.rig_id] = { installed: 0, inventory: 0 };
        }
        rigQty[r.rig_id].inventory += r.quantity || 1;
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

      // Build component quantities map
      const compQty: Record<string, number> = {};
      for (const c of inventoryComponentsRes.data ?? []) {
        compQty[c.item_id] = (compQty[c.item_id] || 0) + (c.quantity || 1);
      }
      componentQuantities.value = compQty;

      // Patch quantity
      patchQuantity.value = inventoryPatchRes.data?.quantity ?? 0;

      // Build exp pack quantities map
      const expQty: Record<string, number> = {};
      for (const e of inventoryExpPacksRes.data ?? []) {
        expQty[e.item_id] = (expQty[e.item_id] || 0) + (e.quantity || 1);
      }
      expPackQuantities.value = expQty;
    } catch (e) {
      console.error('Error loading player quantities:', e);
    } finally {
      loadingQuantities.value = false;
    }
  }

  // Load all data
  async function loadData() {
    // If already loaded, mark as refreshing (shows cached data while loading)
    if (catalogsLoaded.value) {
      refreshing.value = true;
    }

    try {
      await Promise.all([
        loadCatalogs(),
        loadPlayerQuantities(),
      ]);
    } finally {
      refreshing.value = false;
    }
  }

  // Purchase actions
  async function buyRig(rigId: string): Promise<{ success: boolean; error?: string; requiresRon?: boolean; ronAmount?: number }> {
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
        // Refresh inventory to show new rig
        const inventoryStore = useInventoryStore();
        inventoryStore.refresh();
        playSound('purchase');
        return { success: true };
      }

      // Handle RON payment requirement
      if (data?.requires_ron_payment) {
        return {
          success: false,
          requiresRon: true,
          ronAmount: data.ron_amount,
          error: 'RON payment required',
        };
      }

      // Handle inventory capacity errors
      if (data?.error === 'inventory_full') {
        playSound('error');
        return { success: false, error: 'Inventario lleno' };
      }
      if (data?.error === 'stack_full') {
        playSound('error');
        return { success: false, error: 'Stack máximo alcanzado (10)' };
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

  // Confirm RON rig purchase after blockchain tx
  async function confirmRonRigPurchase(rigId: string, txHash: string): Promise<{ success: boolean; error?: string }> {
    const authStore = useAuthStore();
    if (!authStore.player) return { success: false, error: 'No player' };

    buying.value = true;
    try {
      const { data, error } = await supabase.rpc('confirm_ron_rig_purchase', {
        p_player_id: authStore.player.id,
        p_rig_id: rigId,
        p_tx_hash: txHash,
      });

      if (error) throw error;

      if (data?.success) {
        await loadPlayerQuantities();
        await authStore.fetchPlayer();
        playSound('purchase');
        return { success: true };
      }

      playSound('error');
      return { success: false, error: data?.error ?? 'Error confirming purchase' };
    } catch (e) {
      console.error('Error confirming RON rig purchase:', e);
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
        // Refresh inventory
        const inventoryStore = useInventoryStore();
        inventoryStore.refresh();
        playSound('purchase');
        return { success: true };
      }

      // Handle inventory capacity errors
      if (data?.error === 'inventory_full') {
        playSound('error');
        return { success: false, error: 'Inventario lleno' };
      }
      if (data?.error === 'stack_full') {
        playSound('error');
        return { success: false, error: 'Stack máximo alcanzado (10)' };
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

  async function buyCoolingComponent(componentId: string): Promise<{ success: boolean; error?: string }> {
    const authStore = useAuthStore();
    if (!authStore.player) return { success: false, error: 'No player' };

    buying.value = true;
    try {
      const { data, error } = await supabase.rpc('buy_cooling_component', {
        p_player_id: authStore.player.id,
        p_component_id: componentId,
      });

      if (error) throw error;

      if (data?.success) {
        await loadPlayerQuantities();
        await authStore.fetchPlayer();
        const inventoryStore = useInventoryStore();
        inventoryStore.refresh();
        playSound('purchase');
        return { success: true };
      }

      // Handle inventory capacity errors
      if (data?.error === 'inventory_full') {
        playSound('error');
        return { success: false, error: 'Inventario lleno' };
      }
      if (data?.error === 'stack_full') {
        playSound('error');
        return { success: false, error: 'Stack máximo alcanzado (10)' };
      }

      playSound('error');
      return { success: false, error: data?.error ?? 'Error buying component' };
    } catch (e) {
      console.error('Error buying cooling component:', e);
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
        // Refresh inventory
        const inventoryStore = useInventoryStore();
        inventoryStore.refresh();
        playSound('purchase');
        return { success: true };
      }

      // Handle inventory capacity errors
      if (data?.error === 'inventory_full') {
        playSound('error');
        return { success: false, error: 'Inventario lleno' };
      }
      if (data?.error === 'stack_full') {
        playSound('error');
        return { success: false, error: 'Stack máximo alcanzado (10)' };
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
        // Refresh inventory
        const inventoryStore = useInventoryStore();
        inventoryStore.refresh();
        playSound('purchase');
        return { success: true };
      }

      // Handle inventory capacity errors
      if (data?.error === 'inventory_full') {
        playSound('error');
        return { success: false, error: 'Inventario lleno' };
      }
      if (data?.error === 'stack_full') {
        playSound('error');
        return { success: false, error: 'Stack máximo alcanzado (10)' };
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

  async function buyPatch(): Promise<{ success: boolean; error?: string }> {
    const authStore = useAuthStore();
    if (!authStore.player) return { success: false, error: 'No player' };

    buying.value = true;
    try {
      const { data, error } = await supabase.rpc('buy_rig_patch', {
        p_player_id: authStore.player.id,
      });

      if (error) throw error;

      if (data?.success) {
        await loadPlayerQuantities();
        await authStore.fetchPlayer();
        const inventoryStore = useInventoryStore();
        inventoryStore.refresh();
        playSound('purchase');
        return { success: true };
      }

      if (data?.error === 'inventory_full') {
        playSound('error');
        return { success: false, error: 'Inventario lleno' };
      }
      if (data?.error === 'stack_full') {
        playSound('error');
        return { success: false, error: 'Stack máximo alcanzado (10)' };
      }

      playSound('error');
      return { success: false, error: data?.error ?? 'Error buying patch' };
    } catch (e) {
      console.error('Error buying patch:', e);
      playSound('error');
      return { success: false, error: 'Connection error' };
    } finally {
      buying.value = false;
    }
  }

  async function buyExpPack(packId: string): Promise<{ success: boolean; error?: string }> {
    const authStore = useAuthStore();
    if (!authStore.player) return { success: false, error: 'No player' };

    buying.value = true;
    try {
      const { data, error } = await supabase.rpc('buy_exp_pack', {
        p_player_id: authStore.player.id,
        p_pack_id: packId,
      });

      if (error) throw error;

      if (data?.success) {
        await loadPlayerQuantities();
        await authStore.fetchPlayer();
        const inventoryStore = useInventoryStore();
        inventoryStore.refresh();
        playSound('purchase');
        return { success: true };
      }

      if (data?.error === 'inventory_full') {
        playSound('error');
        return { success: false, error: 'Inventario lleno' };
      }
      if (data?.error === 'stack_full') {
        playSound('error');
        return { success: false, error: 'Stack máximo alcanzado (10)' };
      }

      playSound('error');
      return { success: false, error: data?.error ?? 'Error buying EXP pack' };
    } catch (e) {
      console.error('Error buying exp pack:', e);
      playSound('error');
      return { success: false, error: 'Connection error' };
    } finally {
      buying.value = false;
    }
  }

  async function buyCryptoPackage(
    packageId: string
  ): Promise<{ success: boolean; error?: string; cryptoReceived?: number }> {
    const authStore = useAuthStore();
    if (!authStore.player) return { success: false, error: 'No player' };

    buying.value = true;
    try {
      const { data, error } = await supabase.rpc('buy_crypto_package', {
        p_player_id: authStore.player.id,
        p_package_id: packageId,
      });

      if (error) throw error;

      if (data?.success) {
        await authStore.fetchPlayer();
        playSound('purchase');
        return {
          success: true,
          cryptoReceived: data.crypto_received,
        };
      }

      playSound('error');
      return { success: false, error: data?.error ?? 'Error buying crypto package' };
    } catch (e) {
      console.error('Error buying crypto package:', e);
      playSound('error');
      return { success: false, error: 'Connection error' };
    } finally {
      buying.value = false;
    }
  }

  // Buy crypto package with Ronin wallet (external RON payment)
  async function buyCryptoPackageWithWallet(
    packageId: string,
    txHash: string,
    ronAmount: number
  ): Promise<{ success: boolean; error?: string; cryptoReceived?: number }> {
    const authStore = useAuthStore();
    if (!authStore.player) return { success: false, error: 'No player' };

    buying.value = true;
    try {
      // Import dynamically to avoid circular dependencies
      const { verifyRoninPayment } = await import('@/utils/api');

      const result = await verifyRoninPayment(
        txHash,
        packageId,
        authStore.player.id,
        ronAmount
      );

      if (result.success) {
        await authStore.fetchPlayer();
        playSound('purchase');
        return {
          success: true,
          cryptoReceived: result.cryptoReceived,
        };
      }

      playSound('error');
      return { success: false, error: result.error ?? 'Error verifying payment' };
    } catch (e: any) {
      console.error('Error buying crypto with wallet:', e);
      playSound('error');
      return { success: false, error: e.message || 'Connection error' };
    } finally {
      buying.value = false;
    }
  }

  function getPatchOwned(): number {
    return patchQuantity.value;
  }

  function clearState() {
    rigQuantities.value = {};
    coolingQuantities.value = {};
    componentQuantities.value = {};
    cardQuantities.value = {};
    boostQuantities.value = {};
    patchQuantity.value = 0;
    expPackQuantities.value = {};
    // Keep catalogs loaded
  }

  return {
    // Catalogs
    rigs,
    coolingItems,
    coolingComponents,
    prepaidCards,
    boostItems,
    cryptoPackages,
    expPacks,

    // Computed
    rigsForSale,
    energyCards,
    internetCards,
    comboCards,
    loading,
    catalogsLoaded,
    buying,
    refreshing,

    // Getters
    getRigOwned,
    getCoolingOwned,
    getComponentOwned,
    getCardOwned,
    getBoostOwned,
    getPatchOwned,
    getExpPackOwned,
    patchQuantity,

    // Actions
    loadCatalogs,
    loadPlayerQuantities,
    loadData,
    buyRig,
    confirmRonRigPurchase,
    buyCooling,
    buyCoolingComponent,
    buyCard,
    buyBoost,
    buyPatch,
    buyExpPack,
    buyCryptoPackage,
    buyCryptoPackageWithWallet,
    clearState,
  };
});
