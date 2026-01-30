import { defineStore } from 'pinia';
import { ref, computed } from 'vue';
import { supabase } from '@/utils/supabase';
import { createPlayerProfile, getPlayerProfile } from '@/utils/api';
import type { User, Session } from '@supabase/supabase-js';



interface Player {
  id: string;
  email: string;
  username: string;
  gamecoin_balance: number;
  crypto_balance: number;
  energy: number;
  internet: number;
  reputation_score: number;
  region: string;
}

export const useAuthStore = defineStore('auth', () => {
  const user = ref<User | null>(null);
  const player = ref<Player | null>(null);
  const session = ref<Session | null>(null);
  const loading = ref(false);
  const error = ref<string | null>(null);
  const needsUsername = ref(false);

  const isAuthenticated = computed(() => !!user.value && !!session.value && !!player.value);
  const token = computed(() => session.value?.access_token ?? null);

  async function checkAuth() {
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
    }
  }

  async function fetchPlayer() {
    if (!user.value) return;

    try {
      const result = await getPlayerProfile(user.value.id);

      if (result.success && result.player) {
        player.value = result.player;
        needsUsername.value = false;

        // Marcar como online
        await supabase
          .from('players')
          .update({ is_online: true, last_seen: new Date().toISOString() })
          .eq('id', user.value.id);
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
      error.value = e instanceof Error ? e.message : 'Error al conectar con Google';
      loading.value = false;
      return false;
    }
  }

  // Completar registro después de OAuth (crear username)
  async function completeProfile(username: string) {
    if (!user.value) {
      error.value = 'No hay usuario autenticado';
      return false;
    }

    loading.value = true;
    error.value = null;

    try {
      const email = user.value.email ?? '';
      const result = await createPlayerProfile(user.value.id, email, username);

      if (!result.success) {
        throw new Error(result.error ?? 'Error al crear perfil');
      }

      player.value = result.player;
      needsUsername.value = false;

      return true;
    } catch (e) {
      error.value = e instanceof Error ? e.message : 'Error al crear perfil';
      return false;
    } finally {
      loading.value = false;
    }
  }

  async function logout() {
    loading.value = true;

    try {
      if (user.value) {
        await supabase
          .from('players')
          .update({ is_online: false, last_seen: new Date().toISOString() })
          .eq('id', user.value.id);
      }

      await supabase.auth.signOut();
    } catch (e) {
      console.error('Error logging out:', e);
    } finally {
      user.value = null;
      player.value = null;
      session.value = null;
      needsUsername.value = false;
      loading.value = false;
    }
  }

  function updatePlayer(updates: Partial<Player>) {
    if (player.value) {
      player.value = { ...player.value, ...updates };
    }
  }

  // Escuchar cambios de auth (para OAuth callback)
  supabase.auth.onAuthStateChange(async (event, newSession) => {
    if (event === 'SIGNED_IN' && newSession) {
      session.value = newSession;
      user.value = newSession.user;
      await fetchPlayer();
    } else if (event === 'SIGNED_OUT') {
      user.value = null;
      player.value = null;
      session.value = null;
      needsUsername.value = false;
    }
  });

  return {
    user,
    player,
    session,
    loading,
    error,
    needsUsername,
    isAuthenticated,
    token,
    checkAuth,
    fetchPlayer,
    loginWithGoogle,
    completeProfile,
    logout,
    updatePlayer,
  };
});
