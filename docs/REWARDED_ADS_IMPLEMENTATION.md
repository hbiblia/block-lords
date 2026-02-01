# Rewarded Ads - Block Lords

## Resumen

Sistema de anuncios recompensados que permite a los jugadores obtener beneficios in-game a cambio de ver anuncios. No intrusivo, el jugador decide cuándo ver.

---

## Puntos de Integración

### 1. Energía Baja
- **Trigger:** Energía < 20%
- **Ubicación:** NavBar (mobile dropdown) + Barra de energía desktop
- **Recompensa:** +25 Energía
- **Cooldown:** 30 minutos
- **Límite diario:** 5 veces

### 2. Internet Bajo
- **Trigger:** Internet < 20%
- **Ubicación:** NavBar (mobile dropdown) + Barra de internet desktop
- **Recompensa:** +25 Internet
- **Cooldown:** 30 minutos
- **Límite diario:** 5 veces

### 3. Post-Minería (Duplicar Recompensa)
- **Trigger:** Después de minar un bloque exitosamente
- **Ubicación:** Modal de recompensa de minería
- **Recompensa:** x2 GameCoin del bloque minado
- **Cooldown:** 1 hora
- **Límite diario:** 3 veces

### 4. Reparación Gratis de Rig
- **Trigger:** Rig con durabilidad < 50%
- **Ubicación:** RigManageModal
- **Recompensa:** Reparación completa sin costo
- **Cooldown:** 2 horas
- **Límite diario:** 2 veces

### 5. Bonus Diario x2
- **Trigger:** Al reclamar streak diario
- **Ubicación:** StreakModal
- **Recompensa:** x2 recompensa del streak
- **Cooldown:** 24 horas (1 vez por día)
- **Límite diario:** 1 vez

### 6. Misión Completada +50%
- **Trigger:** Al completar una misión
- **Ubicación:** MissionsPanel / Modal de misión completada
- **Recompensa:** +50% recompensa de la misión
- **Cooldown:** 4 horas
- **Límite diario:** 3 veces

---

## Arquitectura Técnica

### Estructura de Archivos

```
src/
├── stores/
│   └── ads.ts                    # Estado global de anuncios
├── composables/
│   └── useRewardedAd.ts          # Hook para mostrar anuncios
├── components/
│   ├── RewardedAdButton.vue      # Botón reutilizable
│   └── RewardedAdModal.vue       # Modal de "cargando anuncio"
├── utils/
│   └── adProviders/
│       ├── index.ts              # Factory de providers
│       ├── admob.ts              # Google AdMob (mobile)
│       ├── adsense.ts            # Google AdSense (web)
│       └── mock.ts               # Mock para desarrollo
└── types/
    └── ads.ts                    # Tipos TypeScript
```

### Base de Datos (Supabase)

```sql
-- Tabla para tracking de anuncios vistos
CREATE TABLE IF NOT EXISTS player_ad_views (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  ad_type TEXT NOT NULL CHECK (ad_type IN (
    'energy_boost',
    'internet_boost',
    'mining_double',
    'free_repair',
    'streak_double',
    'mission_bonus'
  )),
  reward_amount DECIMAL(10, 2),
  viewed_at TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Índices
CREATE INDEX IF NOT EXISTS idx_player_ad_views_player ON player_ad_views(player_id);
CREATE INDEX IF NOT EXISTS idx_player_ad_views_type ON player_ad_views(ad_type);
CREATE INDEX IF NOT EXISTS idx_player_ad_views_date ON player_ad_views(viewed_at);

-- Función para verificar cooldown y límite diario
CREATE OR REPLACE FUNCTION can_watch_ad(
  p_player_id UUID,
  p_ad_type TEXT,
  p_cooldown_minutes INT,
  p_daily_limit INT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_last_view TIMESTAMPTZ;
  v_daily_count INT;
  v_cooldown_remaining INT;
BEGIN
  -- Obtener última vista de este tipo
  SELECT viewed_at INTO v_last_view
  FROM player_ad_views
  WHERE player_id = p_player_id AND ad_type = p_ad_type
  ORDER BY viewed_at DESC
  LIMIT 1;

  -- Contar vistas de hoy
  SELECT COUNT(*) INTO v_daily_count
  FROM player_ad_views
  WHERE player_id = p_player_id
    AND ad_type = p_ad_type
    AND viewed_at >= CURRENT_DATE;

  -- Verificar límite diario
  IF v_daily_count >= p_daily_limit THEN
    RETURN json_build_object(
      'can_watch', false,
      'reason', 'daily_limit',
      'daily_remaining', 0,
      'cooldown_remaining', 0
    );
  END IF;

  -- Verificar cooldown
  IF v_last_view IS NOT NULL THEN
    v_cooldown_remaining := GREATEST(0,
      EXTRACT(EPOCH FROM (v_last_view + (p_cooldown_minutes || ' minutes')::INTERVAL - NOW()))::INT
    );

    IF v_cooldown_remaining > 0 THEN
      RETURN json_build_object(
        'can_watch', false,
        'reason', 'cooldown',
        'daily_remaining', p_daily_limit - v_daily_count,
        'cooldown_remaining', v_cooldown_remaining
      );
    END IF;
  END IF;

  RETURN json_build_object(
    'can_watch', true,
    'reason', null,
    'daily_remaining', p_daily_limit - v_daily_count,
    'cooldown_remaining', 0
  );
END;
$$;

-- Función para registrar vista de anuncio y dar recompensa
CREATE OR REPLACE FUNCTION complete_ad_view(
  p_player_id UUID,
  p_ad_type TEXT,
  p_reward_data JSON DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_reward_amount DECIMAL(10, 2) := 0;
BEGIN
  -- Registrar la vista
  INSERT INTO player_ad_views (player_id, ad_type, reward_amount)
  VALUES (p_player_id, p_ad_type, COALESCE((p_reward_data->>'amount')::DECIMAL, 0));

  -- Aplicar recompensa según tipo
  CASE p_ad_type
    WHEN 'energy_boost' THEN
      UPDATE players
      SET energy = LEAST(energy + 25, max_energy)
      WHERE id = p_player_id;
      v_reward_amount := 25;

    WHEN 'internet_boost' THEN
      UPDATE players
      SET internet = LEAST(internet + 25, max_internet)
      WHERE id = p_player_id;
      v_reward_amount := 25;

    WHEN 'mining_double' THEN
      -- La recompensa se maneja en el frontend/mining store
      v_reward_amount := COALESCE((p_reward_data->>'amount')::DECIMAL, 0);
      UPDATE players
      SET gamecoin_balance = gamecoin_balance + v_reward_amount
      WHERE id = p_player_id;

    WHEN 'free_repair' THEN
      -- Reparar el rig especificado
      UPDATE player_rigs
      SET durability = 100
      WHERE id = (p_reward_data->>'rig_id')::UUID
        AND player_id = p_player_id;
      v_reward_amount := 100;

    WHEN 'streak_double' THEN
      -- La recompensa se maneja en streak store
      v_reward_amount := COALESCE((p_reward_data->>'amount')::DECIMAL, 0);
      UPDATE players
      SET gamecoin_balance = gamecoin_balance + v_reward_amount
      WHERE id = p_player_id;

    WHEN 'mission_bonus' THEN
      -- Bonus de misión (50% extra)
      v_reward_amount := COALESCE((p_reward_data->>'amount')::DECIMAL, 0);
      UPDATE players
      SET gamecoin_balance = gamecoin_balance + v_reward_amount
      WHERE id = p_player_id;
  END CASE;

  RETURN json_build_object(
    'success', true,
    'reward_amount', v_reward_amount,
    'ad_type', p_ad_type
  );
END;
$$;
```

---

## Implementación Frontend

### 1. Types (`src/types/ads.ts`)

```typescript
export type AdType =
  | 'energy_boost'
  | 'internet_boost'
  | 'mining_double'
  | 'free_repair'
  | 'streak_double'
  | 'mission_bonus';

export interface AdConfig {
  type: AdType;
  cooldownMinutes: number;
  dailyLimit: number;
  rewardText: string;
  rewardIcon: string;
}

export interface AdStatus {
  canWatch: boolean;
  reason: 'cooldown' | 'daily_limit' | null;
  dailyRemaining: number;
  cooldownRemaining: number; // segundos
}

export interface AdRewardData {
  amount?: number;
  rig_id?: string;
}

export const AD_CONFIGS: Record<AdType, AdConfig> = {
  energy_boost: {
    type: 'energy_boost',
    cooldownMinutes: 30,
    dailyLimit: 5,
    rewardText: '+25 Energía',
    rewardIcon: '⚡'
  },
  internet_boost: {
    type: 'internet_boost',
    cooldownMinutes: 30,
    dailyLimit: 5,
    rewardText: '+25 Internet',
    rewardIcon: '📡'
  },
  mining_double: {
    type: 'mining_double',
    cooldownMinutes: 60,
    dailyLimit: 3,
    rewardText: 'x2 Recompensa',
    rewardIcon: '💰'
  },
  free_repair: {
    type: 'free_repair',
    cooldownMinutes: 120,
    dailyLimit: 2,
    rewardText: 'Reparación Gratis',
    rewardIcon: '🔧'
  },
  streak_double: {
    type: 'streak_double',
    cooldownMinutes: 1440, // 24 horas
    dailyLimit: 1,
    rewardText: 'x2 Bonus Diario',
    rewardIcon: '🔥'
  },
  mission_bonus: {
    type: 'mission_bonus',
    cooldownMinutes: 240,
    dailyLimit: 3,
    rewardText: '+50% Recompensa',
    rewardIcon: '🎯'
  }
};
```

### 2. Store (`src/stores/ads.ts`)

```typescript
import { defineStore } from 'pinia';
import { ref, computed } from 'vue';
import { supabase } from '@/utils/supabase';
import { useAuthStore } from './auth';
import type { AdType, AdStatus, AdRewardData, AD_CONFIGS } from '@/types/ads';

export const useAdsStore = defineStore('ads', () => {
  const loading = ref(false);
  const adStatuses = ref<Record<AdType, AdStatus>>({} as Record<AdType, AdStatus>);

  // Verificar si puede ver un anuncio
  async function checkAdStatus(adType: AdType): Promise<AdStatus> {
    const authStore = useAuthStore();
    if (!authStore.player?.id) {
      return { canWatch: false, reason: null, dailyRemaining: 0, cooldownRemaining: 0 };
    }

    const config = AD_CONFIGS[adType];

    const { data, error } = await supabase.rpc('can_watch_ad', {
      p_player_id: authStore.player.id,
      p_ad_type: adType,
      p_cooldown_minutes: config.cooldownMinutes,
      p_daily_limit: config.dailyLimit
    });

    if (error) {
      console.error('Error checking ad status:', error);
      return { canWatch: false, reason: null, dailyRemaining: 0, cooldownRemaining: 0 };
    }

    const status: AdStatus = {
      canWatch: data.can_watch,
      reason: data.reason,
      dailyRemaining: data.daily_remaining,
      cooldownRemaining: data.cooldown_remaining
    };

    adStatuses.value[adType] = status;
    return status;
  }

  // Completar vista de anuncio y recibir recompensa
  async function completeAdView(
    adType: AdType,
    rewardData?: AdRewardData
  ): Promise<{ success: boolean; rewardAmount: number }> {
    const authStore = useAuthStore();
    if (!authStore.player?.id) {
      return { success: false, rewardAmount: 0 };
    }

    loading.value = true;

    try {
      const { data, error } = await supabase.rpc('complete_ad_view', {
        p_player_id: authStore.player.id,
        p_ad_type: adType,
        p_reward_data: rewardData ? JSON.stringify(rewardData) : null
      });

      if (error) throw error;

      // Refrescar datos del jugador
      await authStore.fetchPlayer();

      // Actualizar status del anuncio
      await checkAdStatus(adType);

      return {
        success: data.success,
        rewardAmount: data.reward_amount
      };
    } catch (e) {
      console.error('Error completing ad view:', e);
      return { success: false, rewardAmount: 0 };
    } finally {
      loading.value = false;
    }
  }

  // Cargar todos los estados al inicio
  async function loadAllStatuses() {
    const types: AdType[] = [
      'energy_boost',
      'internet_boost',
      'mining_double',
      'free_repair',
      'streak_double',
      'mission_bonus'
    ];

    await Promise.all(types.map(t => checkAdStatus(t)));
  }

  return {
    loading,
    adStatuses,
    checkAdStatus,
    completeAdView,
    loadAllStatuses
  };
});
```

### 3. Composable (`src/composables/useRewardedAd.ts`)

```typescript
import { ref } from 'vue';
import { useAdsStore } from '@/stores/ads';
import { useToast } from '@/composables/useToast';
import { playSound } from '@/utils/sounds';
import type { AdType, AdRewardData, AD_CONFIGS } from '@/types/ads';

// Mock ad provider - reemplazar con AdMob/AdSense real
async function showAdWithProvider(): Promise<boolean> {
  // Simular carga de anuncio
  await new Promise(resolve => setTimeout(resolve, 2000));
  // En producción, esto llamaría al SDK real
  return true; // true = anuncio visto completamente
}

export function useRewardedAd() {
  const adsStore = useAdsStore();
  const { showToast } = useToast();

  const isShowing = ref(false);
  const isLoading = ref(false);

  async function showRewardedAd(
    adType: AdType,
    rewardData?: AdRewardData,
    onSuccess?: (rewardAmount: number) => void
  ): Promise<boolean> {
    if (isShowing.value || isLoading.value) return false;

    const config = AD_CONFIGS[adType];

    // Verificar si puede ver
    isLoading.value = true;
    const status = await adsStore.checkAdStatus(adType);

    if (!status.canWatch) {
      isLoading.value = false;

      if (status.reason === 'cooldown') {
        const minutes = Math.ceil(status.cooldownRemaining / 60);
        showToast(`Espera ${minutes} min para ver otro anuncio`, 'warning');
      } else if (status.reason === 'daily_limit') {
        showToast('Límite diario alcanzado', 'warning');
      }

      return false;
    }

    // Mostrar anuncio
    isShowing.value = true;

    try {
      const adCompleted = await showAdWithProvider();

      if (adCompleted) {
        // Dar recompensa
        const result = await adsStore.completeAdView(adType, rewardData);

        if (result.success) {
          playSound('reward');
          showToast(`${config.rewardIcon} ${config.rewardText}`, 'success');
          onSuccess?.(result.rewardAmount);
          return true;
        }
      } else {
        showToast('Anuncio cancelado', 'info');
      }

      return false;
    } catch (e) {
      console.error('Error showing ad:', e);
      showToast('Error al cargar anuncio', 'error');
      return false;
    } finally {
      isShowing.value = false;
      isLoading.value = false;
    }
  }

  return {
    isShowing,
    isLoading,
    showRewardedAd
  };
}
```

### 4. Componente (`src/components/RewardedAdButton.vue`)

```vue
<script setup lang="ts">
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAdsStore } from '@/stores/ads';
import { useRewardedAd } from '@/composables/useRewardedAd';
import type { AdType, AdRewardData, AD_CONFIGS } from '@/types/ads';

const props = defineProps<{
  adType: AdType;
  rewardData?: AdRewardData;
  size?: 'sm' | 'md' | 'lg';
  variant?: 'primary' | 'secondary' | 'ghost';
}>();

const emit = defineEmits<{
  success: [rewardAmount: number];
}>();

const { t } = useI18n();
const adsStore = useAdsStore();
const { isShowing, isLoading, showRewardedAd } = useRewardedAd();

const config = computed(() => AD_CONFIGS[props.adType]);
const status = computed(() => adsStore.adStatuses[props.adType]);

const cooldownText = computed(() => {
  if (!status.value?.cooldownRemaining) return '';
  const minutes = Math.ceil(status.value.cooldownRemaining / 60);
  return `${minutes}m`;
});

const isDisabled = computed(() =>
  isShowing.value ||
  isLoading.value ||
  !status.value?.canWatch
);

async function handleClick() {
  const success = await showRewardedAd(
    props.adType,
    props.rewardData,
    (amount) => emit('success', amount)
  );
}

onMounted(() => {
  adsStore.checkAdStatus(props.adType);
});
</script>

<template>
  <button
    @click="handleClick"
    :disabled="isDisabled"
    class="rewarded-ad-btn"
    :class="[
      `size-${size ?? 'md'}`,
      `variant-${variant ?? 'primary'}`,
      { 'is-loading': isLoading, 'is-disabled': isDisabled }
    ]"
  >
    <span v-if="isLoading" class="spinner"></span>
    <template v-else>
      <span class="ad-icon">📺</span>
      <span class="reward-text">{{ config.rewardText }}</span>
      <span v-if="status?.cooldownRemaining" class="cooldown">{{ cooldownText }}</span>
      <span v-else-if="status?.dailyRemaining !== undefined" class="remaining">
        ({{ status.dailyRemaining }}/{{ config.dailyLimit }})
      </span>
    </template>
  </button>
</template>

<style scoped>
.rewarded-ad-btn {
  @apply flex items-center gap-2 px-3 py-2 rounded-lg font-medium transition-all;
  @apply bg-gradient-to-r from-purple-500 to-pink-500 text-white;
  @apply hover:from-purple-600 hover:to-pink-600;
  @apply disabled:opacity-50 disabled:cursor-not-allowed;
}

.size-sm { @apply text-xs px-2 py-1; }
.size-md { @apply text-sm px-3 py-2; }
.size-lg { @apply text-base px-4 py-3; }

.variant-secondary {
  @apply bg-bg-secondary text-text-primary border border-border;
  @apply hover:bg-bg-tertiary;
}

.variant-ghost {
  @apply bg-transparent text-accent-primary;
  @apply hover:bg-accent-primary/10;
}

.spinner {
  @apply w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin;
}

.cooldown {
  @apply text-xs opacity-75;
}

.remaining {
  @apply text-xs opacity-60;
}
</style>
```

---

## Integración con SDKs de Anuncios

### Google AdMob (Mobile - Capacitor)

```bash
npm install @capacitor-community/admob
```

```typescript
// src/utils/adProviders/admob.ts
import { AdMob, RewardAdOptions, AdLoadInfo, RewardAdPluginEvents } from '@capacitor-community/admob';

const ADMOB_REWARDED_ID = {
  android: 'ca-app-pub-XXXXX/XXXXX',
  ios: 'ca-app-pub-XXXXX/XXXXX'
};

export async function initAdMob() {
  await AdMob.initialize({
    initializeForTesting: import.meta.env.DEV,
  });
}

export async function showRewardedAd(): Promise<boolean> {
  return new Promise(async (resolve) => {
    const options: RewardAdOptions = {
      adId: ADMOB_REWARDED_ID.android, // Detectar plataforma
    };

    // Listener para recompensa
    AdMob.addListener(RewardAdPluginEvents.Rewarded, () => {
      resolve(true);
    });

    // Listener para cierre sin recompensa
    AdMob.addListener(RewardAdPluginEvents.Dismissed, () => {
      resolve(false);
    });

    try {
      await AdMob.prepareRewardVideoAd(options);
      await AdMob.showRewardVideoAd();
    } catch (e) {
      console.error('AdMob error:', e);
      resolve(false);
    }
  });
}
```

### Google AdSense (Web)

```typescript
// src/utils/adProviders/adsense.ts
// AdSense no tiene rewarded ads nativos para web
// Alternativa: usar un modal con temporizador

export async function showWebAd(): Promise<boolean> {
  return new Promise((resolve) => {
    // Mostrar modal con anuncio por X segundos
    // El usuario debe esperar para obtener recompensa
    // Implementar con un componente modal personalizado

    // Por ahora, simular
    setTimeout(() => resolve(true), 5000);
  });
}
```

---

## Variables de Entorno

```env
# .env
VITE_ADMOB_APP_ID=ca-app-pub-XXXXX~XXXXX
VITE_ADMOB_REWARDED_ANDROID=ca-app-pub-XXXXX/XXXXX
VITE_ADMOB_REWARDED_IOS=ca-app-pub-XXXXX/XXXXX
VITE_ADS_ENABLED=true
VITE_ADS_TEST_MODE=true
```

---

## Checklist de Implementación

- [ ] Crear migración SQL para `player_ad_views`
- [ ] Crear funciones SQL `can_watch_ad` y `complete_ad_view`
- [ ] Crear tipos TypeScript (`src/types/ads.ts`)
- [ ] Crear store de ads (`src/stores/ads.ts`)
- [ ] Crear composable `useRewardedAd`
- [ ] Crear componente `RewardedAdButton.vue`
- [ ] Integrar en NavBar (energía/internet bajos)
- [ ] Integrar en StreakModal (bonus x2)
- [ ] Integrar en RigManageModal (reparación gratis)
- [ ] Integrar en MissionsPanel (bonus misión)
- [ ] Integrar post-minería (x2 recompensa)
- [ ] Configurar AdMob (si es app móvil)
- [ ] Agregar traducciones i18n
- [ ] Agregar sonido de recompensa
- [ ] Testing en desarrollo con mock
- [ ] Testing en producción con ads reales

---

## Notas Adicionales

1. **Modo Test:** En desarrollo, usar mock que siempre retorna éxito después de 2 segundos
2. **Persistencia:** Los cooldowns se guardan en servidor (no localStorage) para evitar trampas
3. **Offline:** No mostrar botones de anuncio si no hay conexión
4. **UX:** Mostrar spinner mientras carga el anuncio, toast con recompensa al completar
5. **Analytics:** Trackear vistas, completaciones, y revenue estimado
