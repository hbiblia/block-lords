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
  <nav class="fixed top-0 left-0 right-0 z-50 bg-arcade-panel border-b border-arcade-border">
    <div class="container mx-auto px-4 h-16 flex items-center justify-between">
      <!-- Logo -->
      <RouterLink to="/" class="flex items-center gap-3">
        <span class="text-2xl">⛏️</span>
        <span class="font-arcade text-sm text-arcade-primary hidden sm:inline">CRYPTO ARCADE</span>
      </RouterLink>

      <!-- Navigation Links -->
      <div class="flex items-center gap-6">
        <template v-if="isAuthenticated">
          <RouterLink
            to="/dashboard"
            class="text-gray-400 hover:text-arcade-primary transition-colors"
            active-class="text-arcade-primary"
          >
            Dashboard
          </RouterLink>
          <RouterLink
            to="/mining"
            class="text-gray-400 hover:text-arcade-primary transition-colors"
            active-class="text-arcade-primary"
          >
            Minería
          </RouterLink>
          <RouterLink
            to="/market"
            class="text-gray-400 hover:text-arcade-primary transition-colors"
            active-class="text-arcade-primary"
          >
            Mercado
          </RouterLink>
          <RouterLink
            to="/leaderboard"
            class="text-gray-400 hover:text-arcade-primary transition-colors"
            active-class="text-arcade-primary"
          >
            Ranking
          </RouterLink>
        </template>

        <template v-else>
          <RouterLink
            to="/leaderboard"
            class="text-gray-400 hover:text-arcade-primary transition-colors"
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
            <div class="flex items-center gap-1">
              <span class="text-arcade-warning">🪙</span>
              <span>{{ authStore.player?.gamecoin_balance?.toFixed(2) ?? '0.00' }}</span>
            </div>
            <div class="flex items-center gap-1">
              <span class="text-arcade-secondary">₿</span>
              <span>{{ authStore.player?.crypto_balance?.toFixed(4) ?? '0.0000' }}</span>
            </div>
          </div>

          <!-- Profile Dropdown -->
          <div class="relative group">
            <button class="flex items-center gap-2 px-3 py-2 rounded hover:bg-arcade-border transition-colors">
              <span class="text-arcade-primary">{{ username }}</span>
              <span class="text-gray-400">▼</span>
            </button>

            <div class="absolute right-0 top-full mt-2 w-48 arcade-panel opacity-0 invisible group-hover:opacity-100 group-hover:visible transition-all">
              <RouterLink
                to="/profile"
                class="block px-4 py-2 hover:bg-arcade-border transition-colors"
              >
                Perfil
              </RouterLink>
              <button
                @click="handleLogout"
                class="w-full text-left px-4 py-2 hover:bg-arcade-border transition-colors text-arcade-danger"
              >
                Cerrar Sesión
              </button>
            </div>
          </div>
        </template>

        <template v-else>
          <RouterLink to="/login" class="text-gray-400 hover:text-white transition-colors">
            Iniciar Sesión
          </RouterLink>
          <RouterLink to="/register" class="arcade-button text-sm">
            Registrarse
          </RouterLink>
        </template>
      </div>
    </div>
  </nav>
</template>
