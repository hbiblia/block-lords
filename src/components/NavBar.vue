<script setup lang="ts">
import { computed, ref, inject, type Ref } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAuthStore } from '@/stores/auth';
import { useRealtimeStore } from '@/stores/realtime';
import { useMiningStore } from '@/stores/mining';
import { toggleLocale, getLocale } from '@/plugins/i18n';
import { useSound } from '@/composables/useSound';
import { formatGamecoin, formatCrypto } from '@/utils/format';

// Inject InfoBar visibility to adjust positioning
const infoBarVisible = inject<Ref<boolean>>('infoBarVisible', ref(false));

const { t } = useI18n();

const router = useRouter();
const authStore = useAuthStore();
const realtimeStore = useRealtimeStore();
const miningStore = useMiningStore();
const { soundEnabled, toggle: toggleSound, play } = useSound();

const isAuthenticated = computed(() => authStore.isAuthenticated);
const username = computed(() => authStore.player?.username ?? 'Player');
const currentLocale = computed(() => getLocale());

function handleToggleLocale() {
  toggleLocale();
  play('click');
}

function handleToggleSound() {
  toggleSound();
}

// Resource values
const energy = computed(() => authStore.player?.energy ?? 100);
const internet = computed(() => authStore.player?.internet ?? 100);
// Use effective max values that include premium bonus (+500 for premium users)
const maxEnergy = computed(() => authStore.effectiveMaxEnergy);
const maxInternet = computed(() => authStore.effectiveMaxInternet);

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

// Mobile resources panel
const showMobileResources = ref(false);

function toggleMobileResources() {
  showMobileResources.value = !showMobileResources.value;
}

// Profile dropdown
const showProfileMenu = ref(false);

function toggleProfileMenu() {
  showProfileMenu.value = !showProfileMenu.value;
}

function closeProfileMenu() {
  showProfileMenu.value = false;
}

async function handleLogout() {
  realtimeStore.disconnect();
  await authStore.logout();
  router.push('/');
}
</script>

<template>
  <nav
    class="fixed left-0 right-0 z-50 glass border-b border-border/50 transition-[top] duration-300"
    :class="infoBarVisible ? 'top-10' : 'top-0'"
  >
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
          <!-- Mobile Resources Button -->
          <div class="md:hidden relative">
            <button
              @click="toggleMobileResources"
              class="flex items-center gap-1.5 px-2.5 py-1.5 bg-bg-secondary rounded-lg text-sm"
              :class="{ 'ring-2 ring-accent-primary': showMobileResources }"
            >
              <span class="text-status-warning">🪙</span>
              <span class="font-medium">{{ formatGamecoin(authStore.player?.gamecoin_balance) }}</span>
              <svg
                class="w-3.5 h-3.5 text-text-muted transition-transform"
                :class="{ 'rotate-180': showMobileResources }"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
              </svg>
            </button>

          </div>

          <!-- Balances & Resources (Desktop) -->
          <div class="hidden md:flex items-center gap-3 text-sm">
            <!-- Coins -->
            <div class="flex items-center gap-2 px-3 py-1.5 bg-bg-secondary rounded-lg">
              <span class="text-status-warning">🪙</span>
              <span class="font-medium">{{ formatGamecoin(authStore.player?.gamecoin_balance) }}</span>
            </div>
            <div class="flex items-center gap-2 px-3 py-1.5 bg-bg-secondary rounded-lg">
              <span class="text-accent-primary">💎</span>
              <span class="font-medium">{{ formatCrypto(authStore.player?.crypto_balance) }}</span>
            </div>

            <!-- Energy Bar -->
            <div class="flex items-center gap-2 px-3 py-1.5 bg-bg-secondary rounded-lg min-w-[120px]">
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
              >{{ Math.round(energy) }}/{{ Math.round(maxEnergy) }}</span>
            </div>

            <!-- Internet Bar -->
            <div class="flex items-center gap-2 px-3 py-1.5 bg-bg-secondary rounded-lg min-w-[120px]">
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
              >{{ Math.round(internet) }}/{{ Math.round(maxInternet) }}</span>
            </div>
          </div>

          <!-- Profile Dropdown -->
          <div class="relative">
            <button
              @click="toggleProfileMenu"
              class="flex items-center gap-2 px-3 py-2 rounded-xl hover:bg-bg-tertiary transition-colors"
              :class="{ 'bg-bg-tertiary': showProfileMenu }"
            >
              <div class="w-8 h-8 rounded-lg bg-gradient-primary flex items-center justify-center text-sm font-bold">
                {{ username.charAt(0).toUpperCase() }}
              </div>
              <span class="text-white font-medium hidden sm:inline">{{ username }}</span>
              <svg
                class="w-4 h-4 text-text-muted transition-transform"
                :class="{ 'rotate-180': showProfileMenu }"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
              </svg>
            </button>

            <Transition name="dropdown">
              <div v-if="showProfileMenu" class="absolute right-0 top-full mt-2 w-max card shadow-card px-[5px] py-[10px]">
                <RouterLink
                  to="/profile"
                  @click="closeProfileMenu"
                  class="flex items-center gap-2 px-4 py-2.5 hover:bg-bg-tertiary transition-colors rounded-t-lg"
                >
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" />
                  </svg>
                  {{ t('nav.profile') }}
                </RouterLink>
                <button
                  @click="handleToggleLocale(); closeProfileMenu()"
                  class="w-full flex items-center gap-2 px-4 py-2.5 hover:bg-bg-tertiary transition-colors"
                >
                  <span class="w-4 h-4 flex items-center justify-center text-sm">{{ currentLocale === 'en' ? '🇪🇸' : '🇺🇸' }}</span>
                  {{ currentLocale === 'en' ? 'Español' : 'English' }}
                </button>
                <button
                  @click="handleToggleSound(); closeProfileMenu()"
                  class="w-full flex items-center gap-2 px-4 py-2.5 hover:bg-bg-tertiary transition-colors"
                >
                  <span class="w-4 h-4 flex items-center justify-center text-sm">{{ soundEnabled ? '🔊' : '🔇' }}</span>
                  {{ soundEnabled ? t('nav.soundOn', 'Sound On') : t('nav.soundOff', 'Sound Off') }}
                </button>
                <button
                  @click="handleLogout(); closeProfileMenu()"
                  class="w-full flex items-center gap-2 px-4 py-2.5 hover:bg-bg-tertiary transition-colors text-status-danger rounded-b-lg"
                >
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1" />
                  </svg>
                  {{ t('nav.logout') }}
                </button>
              </div>
            </Transition>
          </div>
        </template>

        <template v-else>
          <!-- Language Selector for non-authenticated users -->
          <button
            @click="handleToggleLocale"
            class="px-2 py-1.5 text-xs font-medium rounded-lg bg-bg-tertiary hover:bg-bg-tertiary/80 transition-all"
            :title="currentLocale === 'en' ? 'Switch to Spanish' : 'Cambiar a Inglés'"
          >
            {{ currentLocale === 'en' ? '🇺🇸 EN' : '🇪🇸 ES' }}
          </button>
        </template>
      </div>
    </div>
  </nav>

  <!-- Profile Menu Backdrop -->
  <Transition name="backdrop">
    <div
      v-if="showProfileMenu"
      class="fixed inset-0 z-40"
      @click="closeProfileMenu"
    ></div>
  </Transition>

  <!-- Mobile Resources Backdrop (Teleported to body) -->
  <Teleport to="body">
    <Transition name="backdrop">
      <div
        v-if="showMobileResources"
        class="fixed inset-0 z-[60] bg-black/50 backdrop-blur-sm"
        @click="showMobileResources = false"
      ></div>
    </Transition>
  </Teleport>

  <!-- Mobile Resources Dropdown (Teleported to body) -->
  <Teleport to="body">
    <Transition name="dropdown">
      <div
        v-if="showMobileResources"
        class="fixed top-[4.5rem] right-4 w-56 card p-3 shadow-card z-[70]"
      >
        <!-- GameCoin -->
        <div class="flex items-center justify-between py-2 border-b border-border/30">
          <div class="flex items-center gap-2">
            <span class="text-status-warning text-lg">🪙</span>
            <span class="text-text-muted text-sm">GameCoin</span>
          </div>
          <span class="font-bold">{{ authStore.player?.gamecoin_balance?.toFixed(2) ?? '0.00' }}</span>
        </div>

        <!-- BLC -->
        <div class="flex items-center justify-between py-2 border-b border-border/30">
          <div class="flex items-center gap-2">
            <span class="text-accent-primary text-lg">💎</span>
            <span class="text-text-muted text-sm">BLC</span>
          </div>
          <span class="font-bold">{{ authStore.player?.crypto_balance?.toFixed(2) ?? '0.00' }}</span>
        </div>

        <!-- Energy -->
        <div class="py-2 border-b border-border/30">
          <div class="flex items-center justify-between mb-1.5">
            <div class="flex items-center gap-2">
              <span :class="{ 'animate-pulse': miningStore.isMining }">⚡</span>
              <span class="text-text-muted text-sm">{{ t('nav.energy', 'Energía') }}</span>
            </div>
            <span
              class="font-bold text-sm"
              :class="{
                'text-status-danger': energyStatus === 'critical',
                'text-status-warning': energyStatus === 'warning',
                'text-white': energyStatus === 'normal'
              }"
            >{{ Math.round(energy) }} / {{ Math.round(maxEnergy) }}</span>
          </div>
          <div
            class="h-2.5 rounded-full overflow-hidden"
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

        <!-- Internet -->
        <div class="py-2">
          <div class="flex items-center justify-between mb-1.5">
            <div class="flex items-center gap-2">
              <span :class="{ 'animate-pulse': miningStore.isMining }">📡</span>
              <span class="text-text-muted text-sm">Internet</span>
            </div>
            <span
              class="font-bold text-sm"
              :class="{
                'text-status-danger': internetStatus === 'critical',
                'text-status-warning': internetStatus === 'warning',
                'text-white': internetStatus === 'normal'
              }"
            >{{ Math.round(internet) }} / {{ Math.round(maxInternet) }}</span>
          </div>
          <div
            class="h-2.5 rounded-full overflow-hidden"
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
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
.dropdown-enter-active,
.dropdown-leave-active {
  transition: all 0.2s ease;
}

.dropdown-enter-from,
.dropdown-leave-to {
  opacity: 0;
  transform: translateY(-8px);
}

.backdrop-enter-active,
.backdrop-leave-active {
  transition: opacity 0.2s ease;
}

.backdrop-enter-from,
.backdrop-leave-to {
  opacity: 0;
}
</style>
