import { defineStore } from 'pinia';
import { ref, computed } from 'vue';
import { supabase } from '@/utils/supabase';

interface GameSettings {
  [key: string]: number;
}

const STORAGE_KEY = 'lootmine_game_config_cache';
const CACHE_TTL_MS = 5 * 60 * 1000; // 5 minutos

function loadFromCache(): { data: GameSettings; timestamp: number } | null {
  try {
    const cached = localStorage.getItem(STORAGE_KEY);
    if (cached) return JSON.parse(cached);
  } catch { /* ignore */ }
  return null;
}

function saveToCache(data: GameSettings) {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify({ data, timestamp: Date.now() }));
  } catch { /* ignore */ }
}

export const useGameConfigStore = defineStore('gameConfig', () => {
  const settings = ref<GameSettings | null>(null);
  const loaded = ref(false);

  // Computed getters para valores más usados
  const rigPatchCost = computed(() => settings.value?.rig_patch_cost_gamecoin ?? 10000);

  async function fetchSettings(force = false) {
    if (!force && loaded.value) return;

    const cached = loadFromCache();
    if (!force && cached && Date.now() - cached.timestamp < CACHE_TTL_MS) {
      settings.value = cached.data;
      loaded.value = true;
      return;
    }

    try {
      const { data, error } = await supabase.rpc('get_game_settings');
      if (error) throw error;
      settings.value = data as GameSettings;
      loaded.value = true;
      saveToCache(data as GameSettings);
    } catch (e) {
      console.error('Error fetching game settings:', e);
      if (cached) {
        settings.value = cached.data;
        loaded.value = true;
      }
    }
  }

  function getSetting(key: string, fallback: number = 0): number {
    return settings.value?.[key] ?? fallback;
  }

  function reset() {
    settings.value = null;
    loaded.value = false;
  }

  return {
    settings,
    loaded,
    rigPatchCost,
    fetchSettings,
    getSetting,
    reset,
  };
});
