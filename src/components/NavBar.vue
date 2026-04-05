<script setup lang="ts">
import { computed, ref, inject, type Ref } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAuthStore } from '@/stores/auth';
import { useRealtimeStore } from '@/stores/realtime';
import { useMiningStore } from '@/stores/mining';
import { useMailStore } from '@/stores/mail';
import { toggleLocale, getLocale } from '@/plugins/i18n';
import { useSound } from '@/composables/useSound';
import { formatGamecoin, formatCrypto, formatCompact, formatNumber } from '@/utils/format';
import { Coins, Gem, Zap, Wifi, Mail, ChevronDown, User, LogOut, Volume2, VolumeX } from 'lucide-vue-next';

// Inject InfoBar visibility to adjust positioning
const infoBarVisible = inject<Ref<boolean>>('infoBarVisible', ref(false));

const { t } = useI18n();

const router = useRouter();
const authStore = useAuthStore();
const realtimeStore = useRealtimeStore();
const miningStore = useMiningStore();
const mailStore = useMailStore();
const { soundEnabled, toggle: toggleSound, play } = useSound();

function openMail() {
  window.dispatchEvent(new CustomEvent('open-mail'));
}

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
    class="nb-root"
    :class="{ 'nb-shifted': infoBarVisible }"
  >
    <!-- HUD Corners -->
    <div class="nb-corner nb-c-tl"></div>
    <div class="nb-corner nb-c-tr"></div>
    <div class="nb-corner nb-c-bl"></div>
    <div class="nb-corner nb-c-br"></div>

    <!-- Scanline -->
    <div class="nb-scanline"></div>

    <!-- CRT Lines -->
    <div class="nb-crt"></div>

    <div class="nb-inner">
      <!-- Logo -->
      <RouterLink :to="isAuthenticated ? '/mining' : '/'" class="nb-logo">
        <img src="/favicon.svg" alt="LootMine" class="nb-logo-img" />
        <span class="nb-logo-text">LOOTMINE</span>
        <span class="nb-logo-dot"></span>
      </RouterLink>

      <!-- Right side -->
      <div class="nb-actions">
        <template v-if="isAuthenticated">
          <!-- Mobile Resources Button -->
          <div class="nb-mobile-only">
            <button
              @click="toggleMobileResources"
              class="nb-res-btn"
              :class="{ 'nb-res-btn-active': showMobileResources }"
            >
              <Coins :size="14" color="#f59e0b" class="nb-res-lucide" />
              <span v-tooltip="formatNumber(authStore.player?.gamecoin_balance ?? 0)" class="nb-res-val cursor-help">{{ formatGamecoin(authStore.player?.gamecoin_balance) }}</span>
              <ChevronDown :size="14" class="nb-chevron" :class="{ 'nb-chevron-up': showMobileResources }" />
            </button>
          </div>

          <!-- Desktop Resources -->
          <div class="nb-desktop-only nb-resources">
            <!-- Coins -->
            <div class="nb-resource-cell">
              <Coins :size="14" color="#f59e0b" />
              <span v-tooltip="formatNumber(authStore.player?.gamecoin_balance ?? 0)" class="nb-rc-val nb-rc-amber cursor-help">{{ formatGamecoin(authStore.player?.gamecoin_balance) }}</span>
            </div>
            <div class="nb-resource-cell">
              <Gem :size="14" color="#06b6d4" />
              <span v-tooltip="formatNumber(authStore.player?.crypto_balance ?? 0, 2)" class="nb-rc-val nb-rc-cyan cursor-help">{{ formatCrypto(authStore.player?.crypto_balance) }}</span>
            </div>

            <!-- Energy Bar -->
            <div class="nb-bar-cell">
              <Zap :size="14" color="#f59e0b" class="nb-bar-lucide" :class="{ 'nb-bar-pulse': miningStore.isMining }" />
              <div class="nb-bar-track">
                <div
                  class="nb-bar-fill"
                  :class="{
                    'nb-fill-danger': energyStatus === 'critical',
                    'nb-fill-warning': energyStatus === 'warning',
                    'nb-fill-amber': energyStatus === 'normal'
                  }"
                  :style="{ width: `${energyPercent}%` }"
                ></div>
                <div class="nb-bar-segs"></div>
              </div>
              <span
                class="nb-bar-num"
                :class="{
                  'nb-num-danger': energyStatus === 'critical',
                  'nb-num-warning': energyStatus === 'warning'
                }"
              >{{ Math.round(energy) }}/{{ Math.round(maxEnergy) }}</span>
            </div>

            <!-- Internet Bar -->
            <div class="nb-bar-cell">
              <Wifi :size="14" color="#06b6d4" class="nb-bar-lucide" :class="{ 'nb-bar-pulse': miningStore.isMining }" />
              <div class="nb-bar-track">
                <div
                  class="nb-bar-fill"
                  :class="{
                    'nb-fill-danger': internetStatus === 'critical',
                    'nb-fill-warning': internetStatus === 'warning',
                    'nb-fill-cyan': internetStatus === 'normal'
                  }"
                  :style="{ width: `${internetPercent}%` }"
                ></div>
                <div class="nb-bar-segs"></div>
              </div>
              <span
                class="nb-bar-num"
                :class="{
                  'nb-num-danger': internetStatus === 'critical',
                  'nb-num-warning': internetStatus === 'warning',
                  'nb-num-cyan': internetStatus !== 'critical' && internetStatus !== 'warning'
                }"
              >{{ Math.round(internet) }}/{{ Math.round(maxInternet) }}</span>
            </div>
          </div>

          <!-- Mail Button -->
          <button @click="openMail" class="nb-icon-btn" :title="t('mail.title', 'Mail')">
            <Mail :size="16" color="#a1a1aa" />
            <span v-if="mailStore.hasUnread" class="nb-mail-badge">{{ mailStore.unreadCount }}</span>
          </button>

          <!-- Profile Dropdown -->
          <div class="nb-profile-wrap">
            <button
              @click="toggleProfileMenu"
              class="nb-profile-btn"
              :class="{ 'nb-profile-active': showProfileMenu }"
            >
              <div class="nb-avatar">{{ username.charAt(0).toUpperCase() }}</div>
              <span class="nb-username">{{ username }}</span>
              <ChevronDown :size="14" class="nb-chevron" :class="{ 'nb-chevron-up': showProfileMenu }" />
            </button>

            <Transition name="dropdown">
              <div v-if="showProfileMenu" class="nb-dropdown">
                <div class="nb-dd-corners">
                  <span class="nb-dc nb-dc-tl"></span><span class="nb-dc nb-dc-tr"></span>
                  <span class="nb-dc nb-dc-bl"></span><span class="nb-dc nb-dc-br"></span>
                </div>
                <RouterLink
                  to="/profile"
                  @click="closeProfileMenu"
                  class="nb-dd-item"
                >
                  <User :size="14" class="nb-dd-lucide" />
                  {{ t('nav.profile') }}
                </RouterLink>
                <button
                  @click="handleToggleLocale(); closeProfileMenu()"
                  class="nb-dd-item"
                >
                  <span class="nb-dd-flag">{{ currentLocale === 'en' ? '🇪🇸' : '🇺🇸' }}</span>
                  {{ currentLocale === 'en' ? 'Español' : 'English' }}
                </button>
                <button
                  @click="handleToggleSound(); closeProfileMenu()"
                  class="nb-dd-item"
                >
                  <component :is="soundEnabled ? Volume2 : VolumeX" :size="14" class="nb-dd-lucide" />
                  {{ soundEnabled ? t('nav.soundOn', 'Sound On') : t('nav.soundOff', 'Sound Off') }}
                </button>
                <button
                  @click="handleLogout(); closeProfileMenu()"
                  class="nb-dd-item nb-dd-danger"
                >
                  <LogOut :size="14" class="nb-dd-lucide" />
                  {{ t('nav.logout') }}
                </button>
              </div>
            </Transition>
          </div>
        </template>

        <template v-else>
          <!-- Non-authenticated: Language + Login -->
          <button @click="handleToggleLocale" class="nb-lang-btn" :title="currentLocale === 'en' ? 'Switch to Spanish' : 'Cambiar a Inglés'">
            <span class="nb-lang-flag">{{ currentLocale === 'en' ? '🇺🇸' : '🇪🇸' }}</span>
            <span class="nb-lang-code">{{ currentLocale === 'en' ? 'EN' : 'ES' }}</span>
          </button>
          <RouterLink to="/login" class="nb-login-btn">
            <span class="nb-login-dot"></span>
            <span class="nb-login-text">{{ t('home.startMining') }}</span>
          </RouterLink>
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
        class="nb-mobile-backdrop"
        @click="showMobileResources = false"
      ></div>
    </Transition>
  </Teleport>

  <!-- Mobile Resources Dropdown (Teleported to body) -->
  <Teleport to="body">
    <Transition name="dropdown">
      <div v-if="showMobileResources" class="nb-mobile-panel">
        <div class="nb-mp-corners">
          <span class="nb-dc nb-dc-tl"></span><span class="nb-dc nb-dc-tr"></span>
          <span class="nb-dc nb-dc-bl"></span><span class="nb-dc nb-dc-br"></span>
        </div>

        <!-- GameCoin -->
        <div class="nb-mp-row">
          <div class="nb-mp-left">
            <Coins :size="16" color="#f59e0b" />
            <span class="nb-mp-label">GameCoin</span>
          </div>
          <span v-tooltip="formatNumber(authStore.player?.gamecoin_balance ?? 0)" class="nb-mp-val nb-rc-amber cursor-help">{{ formatCompact(authStore.player?.gamecoin_balance) }}</span>
        </div>

        <!-- Landwork -->
        <div class="nb-mp-row">
          <div class="nb-mp-left">
            <Gem :size="16" color="#06b6d4" />
            <span class="nb-mp-label">Landwork</span>
          </div>
          <span v-tooltip="formatNumber(authStore.player?.crypto_balance ?? 0, 2)" class="nb-mp-val nb-rc-cyan cursor-help">{{ formatCompact(authStore.player?.crypto_balance) }}</span>
        </div>

        <!-- Energy -->
        <div class="nb-mp-bar-row">
          <div class="nb-mp-bar-header">
            <div class="nb-mp-left">
              <Zap :size="16" color="#f59e0b" :class="{ 'nb-bar-pulse': miningStore.isMining }" />
              <span class="nb-mp-label">{{ t('nav.energy', 'Energía') }}</span>
            </div>
            <span
              class="nb-mp-bar-num"
              :class="{
                'nb-num-danger': energyStatus === 'critical',
                'nb-num-warning': energyStatus === 'warning'
              }"
            >{{ Math.round(energy) }} / {{ Math.round(maxEnergy) }}</span>
          </div>
          <div class="nb-bar-track nb-bar-track-full">
            <div
              class="nb-bar-fill"
              :class="{
                'nb-fill-danger': energyStatus === 'critical',
                'nb-fill-warning': energyStatus === 'warning',
                'nb-fill-amber': energyStatus === 'normal'
              }"
              :style="{ width: `${energyPercent}%` }"
            ></div>
            <div class="nb-bar-segs"></div>
          </div>
        </div>

        <!-- Internet -->
        <div class="nb-mp-bar-row nb-mp-bar-last">
          <div class="nb-mp-bar-header">
            <div class="nb-mp-left">
              <Wifi :size="16" color="#06b6d4" :class="{ 'nb-bar-pulse': miningStore.isMining }" />
              <span class="nb-mp-label">Internet</span>
            </div>
            <span
              class="nb-mp-bar-num"
              :class="{
                'nb-num-danger': internetStatus === 'critical',
                'nb-num-warning': internetStatus === 'warning',
                'nb-num-cyan': internetStatus !== 'critical' && internetStatus !== 'warning'
              }"
            >{{ Math.round(internet) }} / {{ Math.round(maxInternet) }}</span>
          </div>
          <div class="nb-bar-track nb-bar-track-full">
            <div
              class="nb-bar-fill"
              :class="{
                'nb-fill-danger': internetStatus === 'critical',
                'nb-fill-warning': internetStatus === 'warning',
                'nb-fill-cyan': internetStatus === 'normal'
              }"
              :style="{ width: `${internetPercent}%` }"
            ></div>
            <div class="nb-bar-segs"></div>
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
/* ===== ROOT ===== */
.nb-root {
  position: fixed; left: 0; right: 0; top: 0; z-index: 50;
  border-bottom: 1px solid #2f3052;
  background: linear-gradient(135deg, rgba(16,17,35,0.98) 0%, rgba(22,23,42,0.97) 100%);
  backdrop-filter: blur(12px);
  -webkit-backdrop-filter: blur(12px);
  transition: top 0.3s;
  overflow: hidden;
}
.nb-shifted { top: 2.5rem; }

/* CRT micro-lines */
.nb-crt {
  position: absolute; inset: 0; pointer-events: none; z-index: 0;
  background: repeating-linear-gradient(0deg, transparent, transparent 3px, rgba(255,255,255,0.005) 3px, rgba(255,255,255,0.005) 4px);
}

/* HUD Corners */
.nb-corner { position: absolute; width: 10px; height: 10px; pointer-events: none; z-index: 3; }
.nb-c-tl { top: 0; left: 0; border-top: 2px solid #f59e0b; border-left: 2px solid #f59e0b; }
.nb-c-tr { top: 0; right: 0; border-top: 2px solid #f59e0b; border-right: 2px solid #f59e0b; }
.nb-c-bl { bottom: 0; left: 0; border-bottom: 2px solid #f59e0b; border-left: 2px solid #f59e0b; }
.nb-c-br { bottom: 0; right: 0; border-bottom: 2px solid #f59e0b; border-right: 2px solid #f59e0b; }

/* Scanline */
.nb-scanline {
  position: absolute; top: 0; left: -100%; width: 100%; height: 100%;
  pointer-events: none; z-index: 1;
  background: linear-gradient(90deg, transparent 0%, rgba(245,158,11,0.02) 45%, rgba(245,158,11,0.05) 50%, rgba(245,158,11,0.02) 55%, transparent 100%);
  animation: nb-scan 5s linear infinite;
}
@keyframes nb-scan { 0% { left: -100%; } 100% { left: 100%; } }

/* Inner */
.nb-inner {
  position: relative; z-index: 2;
  max-width: 1200px; margin: 0 auto;
  padding: 0 1rem; height: 3.5rem;
  display: flex; align-items: center; justify-content: space-between;
}

/* ===== LOGO ===== */
.nb-logo {
  display: flex; align-items: center; gap: 0.6rem;
  text-decoration: none;
  transition: opacity 0.2s;
}
.nb-logo:hover { opacity: 0.85; }

.nb-logo-img {
  width: 2rem; height: 2rem;
  transition: transform 0.2s;
}
.nb-logo:hover .nb-logo-img { transform: scale(1.1); }

.nb-logo-text {
  font-size: 0.8rem; font-weight: 900; letter-spacing: 3px;
  color: #f59e0b;
  text-shadow: 0 0 10px rgba(245,158,11,0.3);
  display: none;
}
@media (min-width: 640px) { .nb-logo-text { display: inline; } }

.nb-logo-dot {
  width: 5px; height: 5px; background: #22c55e; border-radius: 50%;
  box-shadow: 0 0 6px #22c55e80;
  animation: nb-pulse 1.5s infinite;
  display: none;
}
@media (min-width: 640px) { .nb-logo-dot { display: inline-block; } }
@keyframes nb-pulse { 0%,100% { opacity: 1; } 50% { opacity: 0.3; } }

/* ===== ACTIONS ===== */
.nb-actions { display: flex; align-items: center; gap: 0.5rem; }

.nb-mobile-only { display: block; }
.nb-desktop-only { display: none; }
@media (min-width: 768px) {
  .nb-mobile-only { display: none; }
  .nb-desktop-only { display: flex; }
}

/* ===== MOBILE RESOURCES BUTTON ===== */
.nb-res-btn {
  display: flex; align-items: center; gap: 0.4rem;
  padding: 0.3rem 0.6rem;
  border: 1px solid #2f3052;
  background: rgba(26,27,46,0.8);
  color: #e5e7eb;
  font-size: 0.7rem; font-weight: 700;
  transition: all 0.2s;
  cursor: pointer;
}
.nb-res-btn-active { border-color: #f59e0b; }
.nb-res-lucide { flex-shrink: 0; }
.nb-res-val { font-family: 'JetBrains Mono', monospace; color: #f59e0b; }

.nb-chevron { color: #71717a; transition: transform 0.2s; flex-shrink: 0; }
.nb-chevron-up { transform: rotate(180deg); }

/* ===== DESKTOP RESOURCES ===== */
.nb-resources { display: flex; align-items: center; gap: 0.4rem; }

.nb-resource-cell {
  display: flex; align-items: center; gap: 0.4rem;
  padding: 0.25rem 0.6rem;
  border: 1px solid #2f3052;
  background: rgba(26,27,46,0.6);
}
.nb-rc-val {
  font-size: 0.7rem; font-weight: 800;
  font-family: 'JetBrains Mono', monospace;
}
.nb-rc-amber { color: #f59e0b; }
.nb-rc-cyan { color: #06b6d4; }

/* ===== BAR CELLS ===== */
.nb-bar-cell {
  display: flex; align-items: center; gap: 0.4rem;
  padding: 0.25rem 0.6rem;
  border: 1px solid #2f3052;
  background: rgba(26,27,46,0.6);
  min-width: 120px;
}
.nb-bar-lucide { flex-shrink: 0; }
.nb-bar-pulse { animation: nb-pulse 1s infinite; }

.nb-bar-track {
  flex: 1; height: 5px; position: relative;
  background: #1a1b2e; overflow: hidden;
}
.nb-bar-track-full { height: 6px; }

.nb-bar-fill {
  height: 100%; transition: width 0.3s;
  position: relative;
}
.nb-fill-amber { background: linear-gradient(90deg, rgba(245,158,11,0.4), #f59e0b); }
.nb-fill-cyan { background: linear-gradient(90deg, rgba(6,182,212,0.4), #06b6d4); }
.nb-fill-warning { background: linear-gradient(90deg, rgba(245,158,11,0.4), #f59e0b); }
.nb-fill-danger { background: #ef4444; animation: nb-danger-blink 1s infinite; }
@keyframes nb-danger-blink { 0%,100% { opacity: 1; } 50% { opacity: 0.5; } }

.nb-bar-segs {
  position: absolute; inset: 0; pointer-events: none;
  background: repeating-linear-gradient(90deg, transparent 0px, transparent 9%, rgba(16,17,35,0.8) 9%, rgba(16,17,35,0.8) 10%);
}

.nb-bar-num {
  font-size: 0.55rem; font-weight: 900; color: #71717a;
  font-family: 'JetBrains Mono', monospace;
  white-space: nowrap;
}
.nb-num-danger { color: #ef4444; animation: nb-danger-blink 1s infinite; }
.nb-num-warning { color: #f59e0b; }
.nb-num-cyan { color: #06b6d4; }

/* ===== MAIL BUTTON ===== */
.nb-icon-btn {
  position: relative;
  display: flex; align-items: center; justify-content: center;
  width: 2rem; height: 2rem;
  border: 1px solid #2f3052;
  background: rgba(26,27,46,0.6);
  cursor: pointer;
  transition: all 0.2s;
}
.nb-icon-btn:hover { border-color: #4f4f6f; background: rgba(36,37,56,0.8); }
.nb-mail-badge {
  position: absolute; top: -4px; right: -4px;
  min-width: 16px; height: 16px; padding: 0 4px;
  display: flex; align-items: center; justify-content: center;
  background: #ef4444; color: #fff;
  font-size: 0.55rem; font-weight: 900;
  border-radius: 9999px;
  box-shadow: 0 0 6px rgba(239,68,68,0.5);
  animation: nb-bounce 0.6s infinite alternate;
}
@keyframes nb-bounce { 0% { transform: scale(1); } 100% { transform: scale(1.1); } }

/* ===== PROFILE ===== */
.nb-profile-wrap { position: relative; }

.nb-profile-btn {
  display: flex; align-items: center; gap: 0.5rem;
  padding: 0.3rem 0.6rem;
  border: 1px solid #2f3052;
  background: rgba(26,27,46,0.6);
  cursor: pointer;
  transition: all 0.2s;
}
.nb-profile-btn:hover, .nb-profile-active { border-color: #4f4f6f; background: rgba(36,37,56,0.8); }

.nb-avatar {
  width: 1.6rem; height: 1.6rem;
  display: flex; align-items: center; justify-content: center;
  background: linear-gradient(135deg, #f59e0b, #d97706);
  font-size: 0.65rem; font-weight: 900; color: #0f1023;
}

.nb-username {
  font-size: 0.65rem; font-weight: 800; color: #e5e7eb;
  letter-spacing: 0.5px;
  display: none;
}
@media (min-width: 640px) { .nb-username { display: inline; } }

/* ===== DROPDOWN ===== */
.nb-dropdown {
  position: absolute; right: 0; top: 100%; margin-top: 0.5rem;
  min-width: 180px;
  border: 1px solid #2f3052;
  background: linear-gradient(135deg, rgba(16,17,35,0.99) 0%, rgba(26,27,46,0.98) 100%);
  padding: 0.3rem;
  z-index: 60;
  overflow: hidden;
}

.nb-dd-corners { position: absolute; inset: 0; pointer-events: none; z-index: 2; }
.nb-dc { position: absolute; width: 6px; height: 6px; }
.nb-dc-tl { top: 0; left: 0; border-top: 2px solid #f59e0b; border-left: 2px solid #f59e0b; }
.nb-dc-tr { top: 0; right: 0; border-top: 2px solid #f59e0b; border-right: 2px solid #f59e0b; }
.nb-dc-bl { bottom: 0; left: 0; border-bottom: 2px solid #f59e0b; border-left: 2px solid #f59e0b; }
.nb-dc-br { bottom: 0; right: 0; border-bottom: 2px solid #f59e0b; border-right: 2px solid #f59e0b; }

.nb-dd-item {
  display: flex; align-items: center; gap: 0.5rem; width: 100%;
  padding: 0.5rem 0.7rem;
  font-size: 0.65rem; font-weight: 700; color: #a1a1aa;
  letter-spacing: 0.5px;
  background: transparent; border: none; cursor: pointer;
  text-decoration: none;
  transition: all 0.15s;
}
.nb-dd-item:hover { background: rgba(245,158,11,0.05); color: #e5e7eb; }
.nb-dd-danger { color: #ef4444; }
.nb-dd-danger:hover { background: rgba(239,68,68,0.08); color: #f87171; }

.nb-dd-lucide { flex-shrink: 0; }
.nb-dd-flag { font-size: 0.85rem; flex-shrink: 0; width: 0.9rem; text-align: center; }

/* ===== LANGUAGE BUTTON (non-auth) ===== */
.nb-lang-btn {
  display: flex; align-items: center; gap: 0.35rem;
  padding: 0.3rem 0.6rem;
  border: 1px solid #2f3052;
  background: rgba(26,27,46,0.6);
  cursor: pointer;
  transition: all 0.2s;
}
.nb-lang-btn:hover { border-color: #4f4f6f; }
.nb-lang-flag { font-size: 0.8rem; }
.nb-lang-code { font-size: 0.55rem; font-weight: 900; color: #71717a; letter-spacing: 1.5px; }

/* ===== LOGIN BUTTON (non-auth) ===== */
.nb-login-btn {
  display: flex; align-items: center; gap: 0.5rem;
  padding: 0.35rem 0.9rem;
  border: 1px solid #f59e0b;
  background: linear-gradient(135deg, rgba(245,158,11,0.12) 0%, rgba(245,158,11,0.05) 100%);
  text-decoration: none;
  cursor: pointer;
  transition: all 0.3s;
}
.nb-login-btn:hover {
  background: linear-gradient(135deg, rgba(245,158,11,0.22) 0%, rgba(245,158,11,0.1) 100%);
  box-shadow: 0 0 15px rgba(245,158,11,0.15), inset 0 0 15px rgba(245,158,11,0.05);
}
.nb-login-dot {
  width: 5px; height: 5px; background: #f59e0b; border-radius: 50%;
  box-shadow: 0 0 6px #f59e0b80;
  animation: nb-pulse 1.5s infinite;
}
.nb-login-text {
  font-size: 0.6rem; font-weight: 900; color: #f59e0b;
  letter-spacing: 2px;
}

/* ===== MOBILE PANEL ===== */
.nb-mobile-backdrop {
  position: fixed; inset: 0; z-index: 60;
  background: rgba(0,0,0,0.5);
  backdrop-filter: blur(4px);
}

.nb-mobile-panel {
  position: fixed; top: 4rem; right: 0.5rem;
  width: 14rem; z-index: 70;
  border: 1px solid #2f3052;
  background: linear-gradient(135deg, rgba(16,17,35,0.99) 0%, rgba(26,27,46,0.98) 100%);
  padding: 0.5rem;
  overflow: hidden;
}

.nb-mp-corners { position: absolute; inset: 0; pointer-events: none; z-index: 2; }

.nb-mp-row {
  display: flex; align-items: center; justify-content: space-between;
  padding: 0.5rem 0.4rem;
  border-bottom: 1px solid #2f3052;
}

.nb-mp-left { display: flex; align-items: center; gap: 0.4rem; }
.nb-mp-label { font-size: 0.6rem; font-weight: 700; color: #71717a; letter-spacing: 0.5px; }
.nb-mp-val { font-size: 0.7rem; font-weight: 900; font-family: 'JetBrains Mono', monospace; }

.nb-mp-bar-row {
  padding: 0.5rem 0.4rem;
  border-bottom: 1px solid #2f3052;
}
.nb-mp-bar-last { border-bottom: none; }

.nb-mp-bar-header {
  display: flex; align-items: center; justify-content: space-between;
  margin-bottom: 0.35rem;
}

.nb-mp-bar-num {
  font-size: 0.6rem; font-weight: 900; color: #a1a1aa;
  font-family: 'JetBrains Mono', monospace;
}

/* ===== TRANSITIONS ===== */
.dropdown-enter-active, .dropdown-leave-active {
  transition: all 0.2s ease;
}
.dropdown-enter-from, .dropdown-leave-to {
  opacity: 0; transform: translateY(-8px);
}
.backdrop-enter-active, .backdrop-leave-active {
  transition: opacity 0.2s ease;
}
.backdrop-enter-from, .backdrop-leave-to {
  opacity: 0;
}
</style>
