import { defineStore } from 'pinia';
import { ref, computed, watch } from 'vue';
import { supabase } from '@/utils/supabase';
import { createPlayerProfile, getPlayerProfile, applyPassiveRegeneration, applyReferralCode, connectionState, pingApi } from '@/utils/api';
import { useNotificationsStore } from './notifications';
import { useInventoryStore } from './inventory';
import type { User, Session } from '@supabase/supabase-js';

// Timeout para inicialización (10 segundos)
const INIT_TIMEOUT = 10000;



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
  // Intervalo para verificación periódica de sesión
  const sessionCheckInterval = ref<ReturnType<typeof setInterval> | null>(null);
  // Intervalo de verificación: cada 10 segundos
  const SESSION_CHECK_INTERVAL = 10 * 1000;
  // Intervalo para ping de API
  const apiPingInterval = ref<ReturnType<typeof setInterval> | null>(null);
  // Ping cada 30 segundos
  const API_PING_INTERVAL = 30 * 1000;
  // Estado de conexión con el servidor
  const connectionError = ref<string | null>(null);
  const isServerOnline = ref(true);
  // Flag para indicar que la sesión se perdió (para mostrar indicador rojo)
  const sessionLost = ref(false);
  // Latencia del último ping (en ms)
  const pingLatency = ref<number | null>(null);

  // Suscribirse a cambios de estado de conexión
  connectionState.subscribe(async (online, errorMsg) => {
    isServerOnline.value = online;
    connectionError.value = errorMsg || null;

    // Si hay error de conexión, verificar si la sesión sigue siendo válida
    if (!online && user.value) {
      try {
        const { data: { session: currentSession } } = await supabase.auth.getSession();
        if (!currentSession) {
          console.warn('[Auth] Session expired detected on connection error');
          handleSessionLost();
        }
      } catch (e) {
        console.warn('[Auth] Could not verify session on connection error:', e);
      }
    }
  });

  const isAuthenticated = computed(() => !!user.value && !!session.value && !!player.value);
  const token = computed(() => session.value?.access_token ?? null);

  // Premium status - check if premium_until is in the future
  const isPremium = computed(() => {
    if (!player.value?.premium_until) return false;
    return new Date(player.value.premium_until) > new Date();
  });

  // Effective max energy/internet - read directly from database
  const effectiveMaxEnergy = computed(() => {
    return player.value?.max_energy ?? 300;
  });

  const effectiveMaxInternet = computed(() => {
    return player.value?.max_internet ?? 300;
  });

  async function checkAuth() {
    // Prevenir llamadas concurrentes
    if (isCheckingAuth.value) return;
    isCheckingAuth.value = true;
    loading.value = true;
    connectionError.value = null;

    try {
      // Timeout para getSession
      const sessionPromise = supabase.auth.getSession();
      const timeoutPromise = new Promise<never>((_, reject) => {
        setTimeout(() => reject(new Error('Timeout al verificar sesión')), INIT_TIMEOUT);
      });

      const { data: { session: currentSession } } = await Promise.race([sessionPromise, timeoutPromise]);

      if (currentSession) {
        session.value = currentSession;
        user.value = currentSession.user;
        await fetchPlayer();
        // Reset sessionLost flag on successful auth
        sessionLost.value = false;
      }
      // Conexión exitosa
      isServerOnline.value = true;
      connectionError.value = null;
    } catch (e) {
      console.error('Error checking auth:', e);
      const errorMsg = e instanceof Error ? e.message : 'Error de conexión';
      connectionError.value = errorMsg;
      // Solo marcar offline si es error de timeout/red
      if (errorMsg.toLowerCase().includes('timeout') || errorMsg.toLowerCase().includes('network')) {
        isServerOnline.value = false;
      }
    } finally {
      loading.value = false;
      initialized.value = true;
      isCheckingAuth.value = false;
    }
  }

  // Esperar a que auth esté inicializado (con timeout)
  async function waitForInit() {
    if (initialized.value) return;
    // Si ya está en proceso, esperar a que termine (con timeout)
    if (isCheckingAuth.value) {
      return new Promise<void>((resolve) => {
        let resolved = false;
        const timeout = setTimeout(() => {
          if (!resolved) {
            resolved = true;
            console.warn('[Auth] waitForInit timeout - forcing initialization');
            initialized.value = true;
            loading.value = false;
            isCheckingAuth.value = false;
            connectionError.value = 'Timeout al conectar con el servidor';
            isServerOnline.value = false;
            resolve();
          }
        }, INIT_TIMEOUT);

        const unwatch = watch(initialized, (val: boolean) => {
          if (val && !resolved) {
            resolved = true;
            clearTimeout(timeout);
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

      // Aplicar código de referido pendiente si existe
      const pendingRefCode = localStorage.getItem('pendingReferralCode');
      if (pendingRefCode && result.player) {
        try {
          const refResult = await applyReferralCode(result.player.id, pendingRefCode);
          if (refResult.success) {
            // Actualizar balance del jugador con el bonus
            player.value = {
              ...player.value!,
              gamecoin_balance: (player.value?.gamecoin_balance ?? 0) + (refResult.playerBonus ?? 0),
            };
            // Notificar éxito
            const notificationsStore = useNotificationsStore();
            notificationsStore.addNotification({
              type: 'referral_applied',
              title: 'notifications.referralApplied.title',
              message: 'notifications.referralApplied.message',
              icon: '🎁',
              severity: 'success',
              data: { bonus: refResult.playerBonus, referrer: refResult.referrerUsername },
            });
          }
        } catch (e) {
          console.warn('Error applying pending referral code:', e);
        } finally {
          localStorage.removeItem('pendingReferralCode');
        }
      }

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

    // Detener verificación de sesión
    stopSessionCheck();

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

      // Clear inventory cache
      const inventoryStore = useInventoryStore();
      inventoryStore.clear();
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

  // Verificar y refrescar la sesión periódicamente
  async function verifyAndRefreshSession(): Promise<boolean> {
    try {
      // Obtener la sesión actual
      const { data: { session: currentSession }, error: sessionError } = await supabase.auth.getSession();

      if (sessionError) {
        console.error('Error getting session:', sessionError);
        return false;
      }

      // Si no hay sesión, la sesión expiró
      if (!currentSession) {
        console.warn('Session lost - no current session');
        handleSessionLost();
        return false;
      }

      // Verificar si el token está por expirar (menos de 5 minutos)
      const expiresAt = currentSession.expires_at;
      if (expiresAt) {
        const expiresAtMs = expiresAt * 1000;
        const now = Date.now();
        const fiveMinutes = 5 * 60 * 1000;

        if (expiresAtMs - now < fiveMinutes) {
          console.log('Session expiring soon, refreshing...');
          const { data: refreshData, error: refreshError } = await supabase.auth.refreshSession();

          if (refreshError || !refreshData.session) {
            console.error('Error refreshing session:', refreshError);
            handleSessionLost();
            return false;
          }

          // Actualizar la sesión local
          session.value = refreshData.session;
          user.value = refreshData.session.user;
          console.log('Session refreshed successfully');
        }
      }

      // Actualizar la sesión local si cambió
      if (currentSession.access_token !== session.value?.access_token) {
        session.value = currentSession;
        user.value = currentSession.user;
      }

      return true;
    } catch (e) {
      console.error('Error verifying session:', e);
      return false;
    }
  }

  // Manejar pérdida de sesión
  function handleSessionLost() {
    const notificationsStore = useNotificationsStore();
    notificationsStore.notifySessionExpired();

    // Marcar que la sesión se perdió (para mostrar indicador rojo)
    sessionLost.value = true;

    // Limpiar estado de autenticación
    user.value = null;
    player.value = null;
    session.value = null;
    needsUsername.value = false;
    hasAppliedRegeneration.value = false;
    stopSessionCheck();
  }

  // Iniciar verificación periódica de sesión
  function startSessionCheck() {
    if (sessionCheckInterval.value) return;

    // Verificar inmediatamente
    verifyAndRefreshSession();

    // Configurar verificación periódica
    sessionCheckInterval.value = setInterval(() => {
      if (isAuthenticated.value) {
        verifyAndRefreshSession();
      }
    }, SESSION_CHECK_INTERVAL);

    // Iniciar ping de API también
    startApiPing();
  }

  // Detener verificación periódica de sesión
  function stopSessionCheck() {
    if (sessionCheckInterval.value) {
      clearInterval(sessionCheckInterval.value);
      sessionCheckInterval.value = null;
    }
    // También detener ping de API
    stopApiPing();
  }

  // Iniciar ping periódico de API
  function startApiPing() {
    if (apiPingInterval.value) return;

    // Ping inmediato
    pingApi().then(({ success, latency }) => {
      pingLatency.value = success ? latency : null;
    });

    // Configurar ping periódico
    apiPingInterval.value = setInterval(async () => {
      if (isAuthenticated.value) {
        const { success, latency } = await pingApi();
        pingLatency.value = success ? latency : null;
      }
    }, API_PING_INTERVAL);
  }

  // Detener ping periódico de API
  function stopApiPing() {
    if (apiPingInterval.value) {
      clearInterval(apiPingInterval.value);
      apiPingInterval.value = null;
    }
  }

  // Función para reintentar conexión
  async function retryConnection() {
    connectionError.value = null;
    isServerOnline.value = true;

    // Primero verificar si la sesión sigue siendo válida
    try {
      const { data: { session: currentSession }, error: sessionError } = await supabase.auth.getSession();

      if (sessionError || !currentSession) {
        console.warn('[Auth] Session expired during retry');
        handleSessionLost();
        initialized.value = true;
        return;
      }

      // Sesión válida, reintentar conexión
      initialized.value = false;
      await checkAuth();
    } catch (e) {
      console.error('[Auth] Error checking session during retry:', e);
      // Si hay error al verificar sesión, intentar reconectar de todos modos
      initialized.value = false;
      await checkAuth();
    }
  }

  // Verificar sesión cuando hay errores de conexión
  async function checkSessionOnError() {
    try {
      const { data: { session: currentSession } } = await supabase.auth.getSession();
      if (!currentSession && user.value) {
        console.warn('[Auth] Session lost detected on connection error');
        handleSessionLost();
        return false;
      }
      return true;
    } catch {
      return true; // En caso de error, asumir sesión válida
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
    // Estado de conexión
    connectionError,
    isServerOnline,
    sessionLost,
    pingLatency,
    checkAuth,
    waitForInit,
    fetchPlayer,
    refreshPlayer,
    loginWithGoogle,
    completeProfile,
    logout,
    updatePlayer,
    startSessionCheck,
    stopSessionCheck,
    verifyAndRefreshSession,
    retryConnection,
    checkSessionOnError,
  };
});
