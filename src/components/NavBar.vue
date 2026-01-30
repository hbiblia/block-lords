<script setup lang="ts">
import { computed } from 'vue';
import { useRouter } from 'vue-router';
import { useAuthStore } from '@/stores/auth';
import { useRealtimeStore } from '@/stores/realtime';
import { useMiningStore } from '@/stores/mining';

const emit = defineEmits<{
  recharge: [];
  inventory: [];
}>();

const router = useRouter();
const authStore = useAuthStore();
const realtimeStore = useRealtimeStore();
const miningStore = useMiningStore();

const isAuthenticated = computed(() => authStore.isAuthenticated);
const username = computed(() => authStore.player?.username ?? 'Jugador');

// Resource values
const energy = computed(() => authStore.player?.energy ?? 100);
const internet = computed(() => authStore.player?.internet ?? 100);
const maxEnergy = computed(() => authStore.player?.max_energy ?? 100);
const maxInternet = computed(() => authStore.player?.max_internet ?? 100);

// Percentage for bar display
const energyPercent = computed(() => maxEnergy.value > 0 ? (energy.value / maxEnergy.value) * 100 : 0);
const internetPercent = computed(() => maxInternet.value > 0 ? (internet.value / maxInternet.value) * 100 : 0);

// Status colors (based on percentage of max)
const energyStatus = computed(() => {
  if (energyPercent.value <= 10) return 'critical';
  if (energyPercent.value <= 25) return 'warning';
  return 'normal';
});

const internetStatus = computed(() => {
  if (internetPercent.value <= 10) return 'critical';
  if (internetPercent.value <= 25) return 'warning';
  return 'normal';
});

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
      <RouterLink :to="isAuthenticated ? '/mining' : '/'" class="flex items-center gap-3 group">
        <div class="w-10 h-10 rounded-xl bg-gradient-primary flex items-center justify-center text-xl group-hover:scale-110 transition-transform">
          ⛏️
        </div>
        <span class="font-display font-bold text-lg hidden sm:inline gradient-text">BLOCK LORDS</span>
      </RouterLink>


      <!-- User Menu -->
      <div class="flex items-center gap-4">
        <template v-if="isAuthenticated">
          <!-- Balances & Resources -->
          <div class="hidden md:flex items-center gap-3 text-sm">
            <!-- Coins -->
            <div class="flex items-center gap-2 px-3 py-1.5 bg-bg-secondary rounded-lg">
              <span class="text-status-warning">🪙</span>
              <span class="font-medium">{{ authStore.player?.gamecoin_balance?.toFixed(2) ?? '0.00' }}</span>
            </div>
            <div class="flex items-center gap-2 px-3 py-1.5 bg-bg-secondary rounded-lg">
              <span class="text-accent-tertiary">₿</span>
              <span class="font-medium">{{ authStore.player?.crypto_balance?.toFixed(4) ?? '0.0000' }}</span>
            </div>

            <!-- Energy Bar -->
            <div class="flex items-center gap-2 px-3 py-1.5 bg-bg-secondary rounded-lg min-w-[140px]">
              <span :class="{ 'animate-pulse': miningStore.isMining }">⚡</span>
              <div class="flex-1">
                <div
                  class="h-2 rounded-full overflow-hidden"
                  :class="{
                    'bg-status-danger/20': energyStatus === 'critical',
                    'bg-status-warning/20': energyStatus === 'warning',
                    'bg-bg-tertiary': energyStatus === 'normal'
                  }"
                >
                  <div
                    class="h-full rounded-full transition-all duration-200"
                    :class="{
                      'bg-status-danger': energyStatus === 'critical',
                      'bg-gradient-to-r from-status-warning to-yellow-400': energyStatus !== 'critical'
                    }"
                    :style="{ width: `${energyPercent}%` }"
                  ></div>
                </div>
              </div>
              <span
                class="text-xs font-mono font-bold text-right"
                :class="{
                  'text-status-danger animate-pulse': energyStatus === 'critical',
                  'text-status-warning': energyStatus !== 'critical'
                }"
              >{{ energy.toFixed(0) }}/{{ maxEnergy.toFixed(0) }}</span>
            </div>

            <!-- Internet Bar -->
            <div class="flex items-center gap-2 px-3 py-1.5 bg-bg-secondary rounded-lg min-w-[140px]">
              <span :class="{ 'animate-pulse': miningStore.isMining }">📡</span>
              <div class="flex-1">
                <div
                  class="h-2 rounded-full overflow-hidden"
                  :class="{
                    'bg-status-danger/20': internetStatus === 'critical',
                    'bg-status-warning/20': internetStatus === 'warning',
                    'bg-bg-tertiary': internetStatus === 'normal'
                  }"
                >
                  <div
                    class="h-full rounded-full transition-all duration-200"
                    :class="{
                      'bg-status-danger': internetStatus === 'critical',
                      'bg-gradient-to-r from-accent-tertiary to-cyan-400': internetStatus !== 'critical'
                    }"
                    :style="{ width: `${internetPercent}%` }"
                  ></div>
                </div>
              </div>
              <span
                class="text-xs font-mono font-bold text-right"
                :class="{
                  'text-status-danger animate-pulse': internetStatus === 'critical',
                  'text-accent-tertiary': internetStatus !== 'critical'
                }"
              >{{ internet.toFixed(0) }}/{{ maxInternet.toFixed(0) }}</span>
            </div>

            <!-- Recharge Button -->
            <button
              @click="emit('recharge')"
              class="px-2 py-1.5 text-xs font-medium rounded-lg transition-all"
              :class="energyStatus === 'critical' || internetStatus === 'critical'
                ? 'bg-status-danger text-white animate-pulse'
                : 'bg-accent-primary/20 text-accent-primary hover:bg-accent-primary/30'"
              title="Recargar recursos"
            >
              +
            </button>

            <!-- Inventory Button -->
            <button
              @click="emit('inventory')"
              class="px-2 py-1.5 text-sm rounded-lg transition-all bg-bg-tertiary hover:bg-bg-tertiary/80"
              title="Inventario"
            >
              🎒
            </button>
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
