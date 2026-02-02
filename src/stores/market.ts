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
  currency: 'gamecoin' | 'crypto' | 'ron';
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
const STORAGE_KEY = 'blocklords_market_cache';

interface MarketCache {
  rigs: Rig[];
  coolingItems: CoolingItem[];
  prepaidCards: PrepaidCard[];
  boostItems: BoostItem[];
  cryptoPackages: CryptoPackage[];
}

// Default data for new accounts (shown while real data loads)
const DEFAULT_RIGS: Rig[] = [
  { id: 'default-1', name: 'Basic Miner', description: 'Entry-level mining rig', hashrate: 100, power_consumption: 50, internet_consumption: 10, repair_cost: 50, tier: 'common', base_price: 500, currency: 'gamecoin' },
  { id: 'default-2', name: 'Advanced Miner', description: 'Mid-tier mining rig', hashrate: 250, power_consumption: 100, internet_consumption: 20, repair_cost: 100, tier: 'uncommon', base_price: 1500, currency: 'gamecoin' },
  { id: 'default-3', name: 'Pro Miner', description: 'High-performance rig', hashrate: 500, power_consumption: 200, internet_consumption: 40, repair_cost: 200, tier: 'rare', base_price: 4000, currency: 'gamecoin' },
];

const DEFAULT_COOLING: CoolingItem[] = [
  { id: 'cool-1', name: 'Basic Fan', description: 'Simple cooling fan', cooling_power: 10, base_price: 100, tier: 'common' },
  { id: 'cool-2', name: 'Advanced Cooler', description: 'Efficient cooling system', cooling_power: 25, base_price: 300, tier: 'uncommon' },
];

const DEFAULT_CARDS: PrepaidCard[] = [
  { id: 'card-1', name: 'Energy Pack S', description: '100 energy units', card_type: 'energy', amount: 100, base_price: 50, tier: 'common', currency: 'gamecoin' },
  { id: 'card-2', name: 'Energy Pack M', description: '500 energy units', card_type: 'energy', amount: 500, base_price: 200, tier: 'uncommon', currency: 'gamecoin' },
  { id: 'card-3', name: 'Internet Pack S', description: '50 internet units', card_type: 'internet', amount: 50, base_price: 50, tier: 'common', currency: 'gamecoin' },
  { id: 'card-4', name: 'Internet Pack M', description: '200 internet units', card_type: 'internet', amount: 200, base_price: 150, tier: 'uncommon', currency: 'gamecoin' },
];

const DEFAULT_BOOSTS: BoostItem[] = [
  { id: 'boost-1', name: 'Hashrate Boost', description: '+10% hashrate', boost_type: 'hashrate', effect_value: 10, secondary_value: 0, duration_minutes: 60, base_price: 100, currency: 'gamecoin', tier: 'common' },
  { id: 'boost-2', name: 'Efficiency Boost', description: '-10% power usage', boost_type: 'efficiency', effect_value: 10, secondary_value: 0, duration_minutes: 60, base_price: 100, currency: 'gamecoin', tier: 'common' },
];

const DEFAULT_CRYPTO_PACKAGES: CryptoPackage[] = [
  { id: 'crypto-1', name: 'Starter Pack', description: '100 crypto', crypto_amount: 100, ron_price: 1, bonus_percent: 0, tier: 'common', is_featured: false, total_crypto: 100 },
  { id: 'crypto-2', name: 'Value Pack', description: '550 crypto', crypto_amount: 500, ron_price: 5, bonus_percent: 10, tier: 'uncommon', is_featured: true, total_crypto: 550 },
];

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

  // Catalogs - use cached data if available, otherwise use defaults
  const rigs = ref<Rig[]>(cached?.rigs ?? DEFAULT_RIGS);
  const coolingItems = ref<CoolingItem[]>(cached?.coolingItems ?? DEFAULT_COOLING);
  const prepaidCards = ref<PrepaidCard[]>(cached?.prepaidCards ?? DEFAULT_CARDS);
  const boostItems = ref<BoostItem[]>(cached?.boostItems ?? DEFAULT_BOOSTS);
  const cryptoPackages = ref<CryptoPackage[]>(cached?.cryptoPackages ?? DEFAULT_CRYPTO_PACKAGES);

  // Player quantities
  const rigQuantities = ref<Record<string, number>>({});
  const coolingQuantities = ref<Record<string, CoolingQuantity>>({});
  const cardQuantities = ref<Record<string, number>>({});
  const boostQuantities = ref<Record<string, number>>({});

  // Loading states - always have data (cached or default), so never show initial loading
  const loadingCatalogs = ref(false);
  const loadingQuantities = ref(false);
  const catalogsLoaded = ref(true); // Always true since we have defaults
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

  // Track if we've already fetched from server this session
  const catalogsFetched = ref(false);

  // Load catalogs (only fetches from server once per session unless forced)
  async function loadCatalogs(force = false) {
    if (catalogsFetched.value && !force) return;

    loadingCatalogs.value = true;
    try {
      const [rigsRes, coolingRes, cardsRes, boostsRes, cryptoRes] = await Promise.all([
        supabase.from('rigs').select('*').order('base_price', { ascending: true }),
        supabase.from('cooling_items').select('*').order('base_price', { ascending: true }),
        supabase.from('prepaid_cards').select('*').order('base_price', { ascending: true }),
        supabase.from('boost_items').select('*').order('boost_type').order('base_price', { ascending: true }),
        supabase.rpc('get_crypto_packages'),
      ]);

      rigs.value = rigsRes.data ?? [];
      coolingItems.value = coolingRes.data ?? [];
      prepaidCards.value = cardsRes.data ?? [];
      boostItems.value = boostsRes.data ?? [];
      cryptoPackages.value = cryptoRes.data ?? [];
      catalogsFetched.value = true;

      // Save to localStorage cache
      saveToCache({
        rigs: rigs.value,
        coolingItems: coolingItems.value,
        prepaidCards: prepaidCards.value,
        boostItems: boostItems.value,
        cryptoPackages: cryptoPackages.value,
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
      const [playerRigsRes, playerCoolingRes, inventoryCoolingRes, inventoryCardsRes, inventoryBoostsRes] = await Promise.all([
        supabase.from('player_rigs').select('rig_id').eq('player_id', playerId),
        supabase.from('player_cooling').select('cooling_item_id').eq('player_id', playerId),
        supabase.from('player_inventory').select('item_id, quantity').eq('player_id', playerId).eq('item_type', 'cooling'),
        supabase.from('player_cards').select('card_id').eq('player_id', playerId).eq('is_redeemed', false),
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
    cryptoPackages,

    // Computed
    rigsForSale,
    energyCards,
    internetCards,
    loading,
    catalogsLoaded,
    buying,
    refreshing,

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
    confirmRonRigPurchase,
    buyCooling,
    buyCard,
    buyBoost,
    buyCryptoPackage,
    buyCryptoPackageWithWallet,
    clearState,
  };
});
