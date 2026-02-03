import { defineStore } from 'pinia';
import { ref, computed, watch } from 'vue';
import { supabase } from '@/utils/supabase';
import { createPlayerProfile, getPlayerProfile, applyPassiveRegeneration } from '@/utils/api';
import { useNotificationsStore } from './notifications';
import type { User, Session } from '@supabase/supabase-js';



interface Player {
  id: string;
  email: string;
  username: string;
  gamecoin_balance: number;
  crypto_balance: number;
  ron_balance: number;
  energy: number;
  internet: number;
  max_energy: number;
  max_internet: number;
  reputation_score: number;
  region: string;
  ron_wallet?: string | null;
  premium_until?: string | null;
  created_at?: string;
  blocks_mined?: number;
  total_crypto_earned?: number;
  rig_slots?: number;
}

export const useAuthStore = defineStore('auth', () => {
  const user = ref<User | null>(null);
  const player = ref<Player | null>(null);
  const session = ref<Session | null>(null);
  const loading = ref(false);
  const error = ref<string | null>(null);
  const needsUsername = ref(false);
  const initialized = ref(false);
  const isCheckingAuth = ref(false);
  // Flag para evitar aplicar regeneración múltiples veces en la misma sesión
  const hasAppliedRegeneration = ref(false);

  const isAuthenticated = computed(() => !!user.value && !!session.value && !!player.value);
  const token = computed(() => session.value?.access_token ?? null);

  // Premium status - check if premium_until is in the future
  const isPremium = computed(() => {
    if (!player.value?.premium_until) return false;
    return new Date(player.value.premium_until) > new Date();
  });

  // Premium max resource limit (fixed for premium users)
  const PREMIUM_MAX_RESOURCE = 500;

  // Effective max energy/internet - uses database values for free, fixed for premium
  const effectiveMaxEnergy = computed(() => {
    if (isPremium.value) return PREMIUM_MAX_RESOURCE;
    // Use database value for free users (defaults to 100 in DB)
    return player.value?.max_energy ?? 100;
  });

  const effectiveMaxInternet = computed(() => {
    if (isPremium.value) return PREMIUM_MAX_RESOURCE;
    // Use database value for free users (defaults to 100 in DB)
    return player.value?.max_internet ?? 100;
  });

  async function checkAuth() {
    // Prevenir llamadas concurrentes
    if (isCheckingAuth.value) return;
    isCheckingAuth.value = true;
    loading.value = true;

    try {
      const { data: { session: currentSession } } = await supabase.auth.getSession();

      if (currentSession) {
        session.value = currentSession;
        user.value = currentSession.user;
        await fetchPlayer();
      }
    } catch (e) {
      console.error('Error checking auth:', e);
    } finally {
      loading.value = false;
      initialized.value = true;
      isCheckingAuth.value = false;
    }
  }

  // Esperar a que auth esté inicializado
  async function waitForInit() {
    if (initialized.value) return;
    // Si ya está en proceso, esperar a que termine
    if (isCheckingAuth.value) {
      // Esperar hasta que initialized sea true
      return new Promise<void>((resolve) => {
        const unwatch = watch(initialized, (val: boolean) => {
          if (val) {
            unwatch();
            resolve();
          }
        });
      });
    }
    await checkAuth();
  }

  async function fetchPlayer() {
    if (!user.value) return;

    try {
      const userId = user.value.id;
      let regenResult: { success: boolean; energyGained?: number; internetGained?: number } | null = null;

      // Solo aplicar regeneración pasiva UNA VEZ por sesión (al hacer login)
      if (!hasAppliedRegeneration.value) {
        try {
          regenResult = await applyPassiveRegeneration(userId);
          hasAppliedRegeneration.value = true; // Marcar como aplicada
        } catch (e) {
          console.warn('Error applying passive regeneration:', e);
          hasAppliedRegeneration.value = true; // Marcar incluso si falla para no reintentar
        }
      }

      const result = await getPlayerProfile(userId);

      if (result.success && result.player) {
        player.value = result.player;
        needsUsername.value = false;

        // Mostrar notificación de regeneración si ganó recursos (solo en el primer fetch)
        if (regenResult?.success && (regenResult.energyGained || regenResult.internetGained)) {
          const notificationsStore = useNotificationsStore();
          const energyMsg = regenResult.energyGained ? `+${regenResult.energyGained.toFixed(0)} ⚡` : '';
          const internetMsg = regenResult.internetGained ? `+${regenResult.internetGained.toFixed(0)} 📡` : '';
          const resources = [energyMsg, internetMsg].filter(Boolean).join(' ');
          if (resources) {
            notificationsStore.addNotification({
              type: 'welcome_back',
              title: 'notifications.welcomeBack.title',
              message: 'notifications.welcomeBack.message',
              icon: '🔋',
              severity: 'success',
              data: { resources },
            });
          }
        }

        // Marcar como online (no bloquear, ejecutar en background)
        (async () => {
          try {
            await supabase
              .from('players')
              .update({ is_online: true, last_seen: new Date().toISOString() })
              .eq('id', userId);
          } catch (e) {
            console.warn('Error updating online status:', e);
          }
        })();
      } else {
        // Usuario de OAuth sin perfil, necesita crear username
        needsUsername.value = true;
        player.value = null;
      }
    } catch (e) {
      // Probablemente es un usuario nuevo de OAuth
      needsUsername.value = true;
      player.value = null;
    }
  }

  // Login con Google OAuth
  async function loginWithGoogle() {
    loading.value = true;
    error.value = null;

    try {
      const { error: authError } = await supabase.auth.signInWithOAuth({
        provider: 'google',
        options: {
          redirectTo: `${window.location.origin}/auth/callback`,
        },
      });

      if (authError) {
        throw new Error(authError.message);
      }

      // La redirección se maneja automáticamente
      return true;
    } catch (e) {
      error.value = e instanceof Error ? e.message : 'errors.googleConnection';
      loading.value = false;
      return false;
    }
  }

  // Completar registro después de OAuth (crear username)
  async function completeProfile(username: string) {
    if (!user.value) {
      error.value = 'errors.noAuthenticatedUser';
      return false;
    }

    loading.value = true;
    error.value = null;

    try {
      const email = user.value.email ?? '';
      const result = await createPlayerProfile(user.value.id, email, username);

      if (!result.success) {
        throw new Error(result.error ?? 'errors.createProfile');
      }

      player.value = result.player;
      needsUsername.value = false;

      return true;
    } catch (e) {
      error.value = e instanceof Error ? e.message : 'errors.createProfile';
      return false;
    } finally {
      loading.value = false;
    }
  }

  async function logout() {
    loading.value = true;

    try {
      // Update offline status in background (don't block logout)
      if (user.value) {
        const userId = user.value.id;
        (async () => {
          try {
            await supabase
              .from('players')
              .update({ is_online: false, last_seen: new Date().toISOString() })
              .eq('id', userId);
          } catch (e) {
            console.warn('Error updating offline status:', e);
          }
        })();
      }

      await supabase.auth.signOut();
    } catch (e) {
      console.error('Error logging out:', e);
    } finally {
      user.value = null;
      player.value = null;
      session.value = null;
      needsUsername.value = false;
      hasAppliedRegeneration.value = false; // Reset para próxima sesión
      loading.value = false;
    }
  }

  function updatePlayer(updates: Partial<Player>) {
    if (player.value) {
      const oldEnergy = player.value.energy;
      const oldInternet = player.value.internet;
      // Use effective max values (with premium bonus) for notifications
      const oldMaxEnergy = effectiveMaxEnergy.value;
      const oldMaxInternet = effectiveMaxInternet.value;

      player.value = { ...player.value, ...updates };

      // Check for resource depletion and trigger notifications
      // Note: After update, effectiveMaxEnergy/Internet will recalculate with new premium_until if changed
      checkResourceNotifications(
        oldEnergy,
        oldInternet,
        oldMaxEnergy,
        oldMaxInternet,
        player.value.energy,
        player.value.internet,
        effectiveMaxEnergy.value,
        effectiveMaxInternet.value
      );
    }
  }

  function checkResourceNotifications(
    oldEnergy: number,
    oldInternet: number,
    oldMaxEnergy: number,
    oldMaxInternet: number,
    newEnergy: number,
    newInternet: number,
    newMaxEnergy: number,
    newMaxInternet: number
  ) {
    const notificationsStore = useNotificationsStore();
    const LOW_THRESHOLD = 0.1; // 10%

    // Energy depleted
    if (newEnergy <= 0 && oldEnergy > 0) {
      notificationsStore.notifyEnergyDepleted();
    }
    // Energy recovered - reset the notification state
    else if (newEnergy > 0 && oldEnergy <= 0) {
      notificationsStore.resetNotificationState('energy_depleted');
      notificationsStore.resetNotificationState('low_energy');
    }
    // Low energy warning (when crossing the 10% threshold)
    else if (newEnergy > 0 && newMaxEnergy > 0) {
      const newPercent = newEnergy / newMaxEnergy;
      const oldPercent = oldMaxEnergy > 0 ? oldEnergy / oldMaxEnergy : 1;
      if (newPercent <= LOW_THRESHOLD && oldPercent > LOW_THRESHOLD) {
        notificationsStore.notifyLowEnergy(Math.round(newPercent * 100));
      }
    }

    // Internet depleted
    if (newInternet <= 0 && oldInternet > 0) {
      notificationsStore.notifyInternetDepleted();
    }
    // Internet recovered - reset the notification state
    else if (newInternet > 0 && oldInternet <= 0) {
      notificationsStore.resetNotificationState('internet_depleted');
      notificationsStore.resetNotificationState('low_internet');
    }
    // Low internet warning (when crossing the 10% threshold)
    else if (newInternet > 0 && newMaxInternet > 0) {
      const newPercent = newInternet / newMaxInternet;
      const oldPercent = oldMaxInternet > 0 ? oldInternet / oldMaxInternet : 1;
      if (newPercent <= LOW_THRESHOLD && oldPercent > LOW_THRESHOLD) {
        notificationsStore.notifyLowInternet(Math.round(newPercent * 100));
      }
    }
  }

  // Escuchar cambios de auth (para OAuth callback)
  supabase.auth.onAuthStateChange(async (event, newSession) => {
    // Ignorar eventos durante la inicialización para evitar race conditions
    if (isCheckingAuth.value) return;

    if (event === 'SIGNED_IN' && newSession) {
      session.value = newSession;
      user.value = newSession.user;
      // Solo cargar el player si ya estamos inicializados (evita duplicar la carga inicial)
      if (initialized.value) {
        await fetchPlayer();
      }
    } else if (event === 'SIGNED_OUT') {
      user.value = null;
      player.value = null;
      session.value = null;
      needsUsername.value = false;
    }
  });

  // Refresh player data from server (useful after account reset)
  async function refreshPlayer() {
    if (!user.value) return;
    try {
      const result = await getPlayerProfile(user.value.id);
      if (result.success && result.player) {
        player.value = result.player;
      }
    } catch (e) {
      console.error('Error refreshing player:', e);
    }
  }

  return {
    user,
    player,
    session,
    loading,
    error,
    needsUsername,
    isAuthenticated,
    initialized,
    token,
    isPremium,
    effectiveMaxEnergy,
    effectiveMaxInternet,
    checkAuth,
    waitForInit,
    fetchPlayer,
    refreshPlayer,
    loginWithGoogle,
    completeProfile,
    logout,
    updatePlayer,
  };
});
