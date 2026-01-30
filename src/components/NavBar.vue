<script setup lang="ts">
import { computed } from 'vue';
import { useRouter } from 'vue-router';
import { useAuthStore } from '@/stores/auth';
import { useRealtimeStore } from '@/stores/realtime';

const router = useRouter();
const authStore = useAuthStore();
const realtimeStore = useRealtimeStore();

const isAuthenticated = computed(() => authStore.isAuthenticated);
const username = computed(() => authStore.player?.username ?? 'Jugador');

async function handleLogout() {
  realtimeStore.disconnect();
  await authStore.logout();
  router.push('/');
}
</script>

<template>
  <nav class="fixed top-0 left-0 right-0 z-50 glass border-b border-border/50">
    <div class="container mx-auto px-4 h-16 flex items-center justify-between">
      <!-- Logo -->
      <RouterLink to="/" class="flex items-center gap-3 group">
        <div class="w-10 h-10 rounded-xl bg-gradient-primary flex items-center justify-center text-xl group-hover:scale-110 transition-transform">
          ⛏️
        </div>
        <span class="font-display font-bold text-lg hidden sm:inline gradient-text">BLOCK LORDS</span>
      </RouterLink>

      <!-- Navigation Links -->
      <div class="flex items-center gap-2">
        <template v-if="isAuthenticated">
          <RouterLink
            to="/dashboard"
            class="px-4 py-2 rounded-lg text-text-secondary hover:text-white hover:bg-bg-tertiary transition-all"
            active-class="!text-white bg-bg-tertiary"
          >
            Dashboard
          </RouterLink>
          <RouterLink
            to="/mining"
            class="px-4 py-2 rounded-lg text-text-secondary hover:text-white hover:bg-bg-tertiary transition-all"
            active-class="!text-white bg-bg-tertiary"
          >
            Minería
          </RouterLink>
          <RouterLink
            to="/market"
            class="px-4 py-2 rounded-lg text-text-secondary hover:text-white hover:bg-bg-tertiary transition-all"
            active-class="!text-white bg-bg-tertiary"
          >
            Mercado
          </RouterLink>
          <RouterLink
            to="/leaderboard"
            class="px-4 py-2 rounded-lg text-text-secondary hover:text-white hover:bg-bg-tertiary transition-all"
            active-class="!text-white bg-bg-tertiary"
          >
            Ranking
          </RouterLink>
        </template>

        <template v-else>
          <RouterLink
            to="/leaderboard"
            class="px-4 py-2 rounded-lg text-text-secondary hover:text-white hover:bg-bg-tertiary transition-all"
          >
            Ranking
          </RouterLink>
        </template>
      </div>

      <!-- User Menu -->
      <div class="flex items-center gap-4">
        <template v-if="isAuthenticated">
          <!-- Balances -->
          <div class="hidden md:flex items-center gap-4 text-sm">
            <div class="flex items-center gap-2 px-3 py-1.5 bg-bg-secondary rounded-lg">
              <span class="text-status-warning">🪙</span>
              <span class="font-medium">{{ authStore.player?.gamecoin_balance?.toFixed(2) ?? '0.00' }}</span>
            </div>
            <div class="flex items-center gap-2 px-3 py-1.5 bg-bg-secondary rounded-lg">
              <span class="text-accent-tertiary">₿</span>
              <span class="font-medium">{{ authStore.player?.crypto_balance?.toFixed(4) ?? '0.0000' }}</span>
            </div>
          </div>

          <!-- Profile Dropdown -->
          <div class="relative group">
            <button class="flex items-center gap-2 px-3 py-2 rounded-xl hover:bg-bg-tertiary transition-colors">
              <div class="w-8 h-8 rounded-lg bg-gradient-primary flex items-center justify-center text-sm font-bold">
                {{ username.charAt(0).toUpperCase() }}
              </div>
              <span class="text-white font-medium hidden sm:inline">{{ username }}</span>
              <svg class="w-4 h-4 text-text-muted" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
              </svg>
            </button>

            <div class="absolute right-0 top-full mt-2 w-48 card opacity-0 invisible group-hover:opacity-100 group-hover:visible transition-all shadow-card">
              <RouterLink
                to="/profile"
                class="flex items-center gap-2 px-4 py-2.5 hover:bg-bg-tertiary transition-colors rounded-t-lg"
              >
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" />
                </svg>
                Perfil
              </RouterLink>
              <button
                @click="handleLogout"
                class="w-full flex items-center gap-2 px-4 py-2.5 hover:bg-bg-tertiary transition-colors text-status-danger rounded-b-lg"
              >
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1" />
                </svg>
                Cerrar Sesión
              </button>
            </div>
          </div>
        </template>

        <template v-else>
          <RouterLink to="/login" class="btn-primary">
            Iniciar Sesión
          </RouterLink>
        </template>
      </div>
    </div>
  </nav>
</template>
