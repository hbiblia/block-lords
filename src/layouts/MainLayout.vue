<script setup lang="ts">
import { onMounted, onUnmounted, watch, ref, provide, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAuthStore } from '@/stores/auth';
import { useGameTickStore } from '@/stores/game-tick';
import { useStreakStore } from '@/stores/streak';
import { useMissionsStore } from '@/stores/missions';
import { usePendingBlocksStore } from '@/stores/pendingBlocks';
import { useMiningStore } from '@/stores/mining';
import { useGiftsStore } from '@/stores/gifts';
import { useMailStore } from '@/stores/mail';
import { useDefenseStore } from '@/stores/defense';
import { useToastStore } from '@/stores/toast';
import { formatCompact } from '@/utils/format';

const { t } = useI18n();

// Ad blocker detection (non-blocking toast)
function detectAdBlocker() {
  const script = document.createElement('script');
  script.src = 'https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js';
  script.onload = () => { script.remove(); };
  script.onerror = () => {
    script.remove();
    const toastStore = useToastStore();
    toastStore.warning(t('adblock.toastMessage'), '🛡️');
  };
  document.head.appendChild(script);
}

// Global modals state
const showMarket = ref(false);
const showInventory = ref(false);
const showExchange = ref(false);
const showDefense = ref(false);
const showForge = ref(false);
const showPrediction = ref(false);
const showGuide = ref(false);
const showMail = ref(false);

function openMarket() {
  showMarket.value = true;
}
function openExchange() {
  showExchange.value = true;
}
function openInventory() {
  showInventory.value = true;
}
function openDefense() {
  showDefense.value = true;
}
function openForge() {
  showForge.value = true;
}

import NavBar from '@/components/NavBar.vue';
import InfoBar from '@/components/InfoBar.vue';
import UpdateNotificationModal from '@/components/UpdateNotificationModal.vue';
import ConnectionLostModal from '@/components/ConnectionLostModal.vue';
import GameNotificationsModal from '@/components/GameNotificationsModal.vue';
import MissionsPanel from '@/components/MissionsPanel.vue';
import ToastContainer from '@/components/ToastContainer.vue';
import BlockClaimModal from '@/components/BlockClaimModal.vue';
import MarketModal from '@/components/MarketModal.vue';
import InventoryModal from '@/components/InventoryModal.vue';
import ExchangeModal from '@/components/ExchangeModal.vue';
import GiftModal from '@/components/GiftModal.vue';
import DefenseModal from '@/components/DefenseModal.vue';
import ForgeModal from '@/components/ForgeModal.vue';
import PredictionModal from '@/components/PredictionModal.vue';
import MailModal from '@/components/MailModal.vue';
import MiningGuide from '@/components/MiningGuide.vue';
import RewardCelebration from '@/components/RewardCelebration.vue';

const authStore = useAuthStore();
const gameTickStore = useGameTickStore();
const streakStore = useStreakStore();
const missionsStore = useMissionsStore();
const pendingBlocksStore = usePendingBlocksStore();
const miningStore = useMiningStore();
const giftsStore = useGiftsStore();
const mailStore = useMailStore();
const defenseStore = useDefenseStore();

// Combined rewards panel (missions + streak)
const showRewards = ref(false);

function openRewards() {
  showRewards.value = true;
}

function closeRewards() {
  showRewards.value = false;
}

// Handle purchase events - reload mining data
async function handlePurchased() {
  await miningStore.loadData();
}

// Handle inventory used events
function handleInventoryUsed() {
  miningStore.loadData();
}

// InfoBar visibility state - shared via provide/inject
const infoBarVisible = ref(false);
provide('infoBarVisible', infoBarVisible);

// Desktop action buttons visibility (persisted in localStorage)
const desktopButtonsVisible = ref(localStorage.getItem('desktopButtonsVisible') !== 'false');

// Escuchar evento de bloque pendiente creado (incluye pity blocks)
// El feedback visual y sonido lo maneja RewardCelebration.vue
function handlePendingBlockCreated() {
  pendingBlocksStore.fetchPendingBlocks();
}

// Event handlers for modal opening from other pages
function handleOpenMarketEvent() {
  showMarket.value = true;
}
function handleCloseMarketEvent() {
  showMarket.value = false;
}
function handleOpenExchangeEvent() {
  showExchange.value = true;
}
function handleOpenInventoryEvent() {
  showInventory.value = true;
}
function handleOpenPredictionEvent() {
  showPrediction.value = true;
}
function handleOpenMailEvent() {
  showMail.value = true;
}

// Escuchar eventos
onMounted(() => {
  window.addEventListener('pending-block-created', handlePendingBlockCreated as EventListener);
  window.addEventListener('open-market', handleOpenMarketEvent);
  window.addEventListener('close-market', handleCloseMarketEvent);
  window.addEventListener('open-exchange', handleOpenExchangeEvent);
  window.addEventListener('open-inventory', handleOpenInventoryEvent);
  window.addEventListener('open-prediction', handleOpenPredictionEvent);
  window.addEventListener('open-mail', handleOpenMailEvent);
  // Ad blocker detection (only in production)
  if (window.location.hostname !== 'localhost' && !window.location.hostname.startsWith('127.')) {
    detectAdBlocker();
  }
});

// Cargar datos cuando cambia el estado de autenticación
watch(() => authStore.isAuthenticated, (isAuth) => {
  if (isAuth) {
    // Cargar streak, misiones y bloques pendientes
    streakStore.fetchStatus();
    missionsStore.fetchMissions();
    missionsStore.startHeartbeat();
    pendingBlocksStore.fetchPendingBlocks();
    // Cargar regalos pendientes y empezar polling
    giftsStore.fetchGifts();
    giftsStore.startPolling();
    // Cargar correo y empezar polling
    mailStore.fetchUnreadCount();
    mailStore.startPolling();
    // Iniciar verificación periódica de sesión
    authStore.startSessionCheck();
    // Subscribe to lobby count for badge
    defenseStore.subscribeLobbyCount();
  } else {
    missionsStore.stopHeartbeat();
    authStore.stopSessionCheck();
    giftsStore.stopPolling();
    mailStore.stopPolling();
    defenseStore.unsubscribeLobbyCount();
  }
}, { immediate: true });

// Guardar estado del menú de botones en localStorage
watch(desktopButtonsVisible, (visible) => {
  localStorage.setItem('desktopButtonsVisible', String(visible));
});

onUnmounted(() => {
  missionsStore.stopHeartbeat();
  authStore.stopSessionCheck();
  giftsStore.stopPolling();
  mailStore.stopPolling();
  defenseStore.unsubscribeLobbyCount();
  window.removeEventListener('pending-block-created', handlePendingBlockCreated as EventListener);
  window.removeEventListener('open-market', handleOpenMarketEvent);
  window.removeEventListener('close-market', handleCloseMarketEvent);
  window.removeEventListener('open-exchange', handleOpenExchangeEvent);
  window.removeEventListener('open-inventory', handleOpenInventoryEvent);
  window.removeEventListener('open-prediction', handleOpenPredictionEvent);
  window.removeEventListener('open-mail', handleOpenMailEvent);
});

// Connection status computed properties
const isFullyConnected = computed(() => gameTickStore.isHealthy && authStore.isServerOnline && !authStore.sessionLost);
const hasApiIssue = computed(() => !authStore.isServerOnline && !authStore.sessionLost);
const hasRealtimeIssue = computed(() => !gameTickStore.isHealthy);
const hasSessionLost = computed(() => authStore.sessionLost);

const connectionDotClass = computed(() => {
  if (hasSessionLost.value) return 'bg-status-danger';
  if (isFullyConnected.value) return 'bg-status-success animate-pulse';
  if (hasApiIssue.value) return 'bg-status-warning animate-pulse';
  return 'bg-status-danger';
});

const connectionBorderClass = computed(() => {
  if (hasSessionLost.value) return 'border-status-danger/50';
  if (isFullyConnected.value) return 'border-border/30';
  if (hasApiIssue.value) return 'border-status-warning/50 animate-pulse';
  return 'border-status-danger/50';
});

const connectionTextClass = computed(() => {
  if (hasSessionLost.value) return 'text-status-danger';
  if (isFullyConnected.value) return 'text-text-muted';
  if (hasApiIssue.value) return 'text-status-warning';
  return 'text-status-danger';
});

const connectionStatusText = computed(() => {
  if (hasSessionLost.value) return t('connection.sessionExpired', 'Sesión expirada');
  if (isFullyConnected.value) {
    const latency = authStore.pingLatency;
    if (latency !== null) {
      return `${t('nav.connected')} · ${latency}ms`;
    }
    return t('nav.connected');
  }
  if (hasApiIssue.value) return t('connection.serverSlow', 'Servidor lento');
  return t('nav.disconnected');
});

const isRetryingConnection = ref(false);

async function handleConnectionClick() {
  // Si hay problemas de conexión, intentar reconectar
  if (!isFullyConnected.value && !isRetryingConnection.value) {
    isRetryingConnection.value = true;
    try {
      if (hasApiIssue.value) {
        await authStore.retryConnection();
      }
      if (hasRealtimeIssue.value) {
        gameTickStore.start();
      }
    } finally {
      isRetryingConnection.value = false;
    }
  }
}
</script>

<template>
  <div class="min-h-screen flex flex-col bg-bg-primary">
    <!-- InfoBar (announcements) -->
    <InfoBar />

    <!-- Update Notification Modal -->
    <UpdateNotificationModal />

    <NavBar />

    <!-- Connection Lost Modal -->
    <ConnectionLostModal />

    <!-- Game Notifications Modal -->
    <GameNotificationsModal />

    <!-- Toast Notifications -->
    <ToastContainer />

    <!-- Reward Celebration Animation -->
    <RewardCelebration />


    <!-- Missions & Streak Panel -->
    <MissionsPanel
      :show="showRewards"
      @close="closeRewards"
    />

    <!-- Block Claim Modal -->
    <BlockClaimModal
      :show="pendingBlocksStore.showModal"
      @close="pendingBlocksStore.closeModal"
    />

    <!-- Market Modal -->
    <MarketModal
      :show="showMarket"
      @close="showMarket = false"
      @purchased="handlePurchased"
    />

    <!-- Inventory Modal -->
    <InventoryModal
      :show="showInventory"
      @close="showInventory = false"
      @used="handleInventoryUsed"
    />

    <!-- Forge Modal -->
    <ForgeModal
      :show="showForge"
      @close="showForge = false"
      @crafted="handleInventoryUsed"
    />

    <!-- Gift Modal -->
    <GiftModal />

    <!-- Mail Modal -->
    <MailModal
      :show="showMail"
      @close="showMail = false"
    />

    <!-- Exchange Modal -->
    <ExchangeModal
      :show="showExchange"
      @close="showExchange = false"
      @exchanged="authStore.fetchPlayer()"
    />

    <!-- Defense Modal -->
    <DefenseModal
      :show="showDefense"
      @close="showDefense = false"
    />

    <!-- Yield Prediction (admin only) -->
    <PredictionModal
      v-if="authStore.player?.role === 'admin'"
      :show="showPrediction"
      @close="showPrediction = false"
    />

    <MiningGuide
      :show="showGuide"
      @close="showGuide = false"
    />

    <!-- Main Content -->
    <main
      class="flex-1 container mx-auto px-4 py-6 pb-20 sm:pb-6 transition-[margin] duration-300"
      :class="infoBarVisible ? 'mt-[6.5rem]' : 'mt-16'"
    >
      <slot />
    </main>

    <!-- Mobile Bottom Action Bar -->
    <div
      v-if="authStore.isAuthenticated"
      class="fixed bottom-0 left-0 right-0 z-40 sm:left-auto sm:right-4 sm:w-auto"
    >
      <!-- Connection Status (mobile, above action bar) -->
      <div
        v-if="(authStore.isAuthenticated || authStore.sessionLost) && (authStore.isAuthenticated)"
        class="sm:hidden flex justify-start px-3 py-1 bg-bg-secondary/60 backdrop-blur-sm border-t border-border/20"
      >
        <div
          class="flex items-center gap-1.5 px-2 py-0.5 bg-bg-secondary/80 border rounded-full text-[10px] cursor-pointer transition-all"
          :class="connectionBorderClass"
          @click="handleConnectionClick"
        >
          <span class="w-1.5 h-1.5 rounded-full" :class="connectionDotClass"></span>
          <span :class="connectionTextClass">{{ connectionStatusText }}</span>
        </div>
      </div>

      <!-- Mobile Bar -->
      <div class="sm:hidden mobile-action-bar">
        <div class="flex items-center justify-around px-2 py-1.5 safe-area-bottom">
          <!-- Pending Blocks -->
          <button
            v-if="pendingBlocksStore.hasPending"
            @click="pendingBlocksStore.openModal"
            class="mobile-action-btn mobile-action-btn-highlight"
          >
            <div class="relative">
              <span class="text-xl">⛏️</span>
              <span class="mobile-badge bg-accent-primary">{{ pendingBlocksStore.count }}</span>
            </div>
            <span class="mobile-action-label text-accent-primary">{{ t('blocks.claim', 'Claim') }}</span>
          </button>

          <!-- Rewards -->
          <button
            @click="openRewards()"
            class="mobile-action-btn"
            :class="{ 'mobile-action-btn-success': missionsStore.claimableCount > 0 || streakStore.canClaim }"
          >
            <div class="relative">
              <span class="text-xl">🎯</span>
              <span
                v-if="missionsStore.claimableCount > 0 || streakStore.canClaim"
                class="mobile-badge bg-status-success"
              >{{ (missionsStore.claimableCount || 0) + (streakStore.canClaim ? 1 : 0) }}</span>
            </div>
            <span class="mobile-action-label">{{ t('missions.short', 'Missions') }}</span>
          </button>

          <!-- Market -->
          <button @click="openMarket" class="mobile-action-btn">
            <span class="text-xl">🛒</span>
            <span class="mobile-action-label">{{ t('mining.market', 'Market') }}</span>
          </button>

          <!-- Battle (distinctive) -->
          <button @click="openDefense" class="mobile-battle-btn relative">
            <div class="relative">
              <span class="text-xl leading-none">&#9876;</span>
            </div>
            <span class="mobile-action-label text-red-400/80">{{ t('defense.short', 'Battle') }}</span>
            <!-- Bubble badge -->
            <span
              v-if="defenseStore.lobbyCount > 0"
              class="lobby-bubble"
            >{{ t('defense.lobbyBubble', 'Someone wants to battle!') }}</span>
          </button>

          <!-- Exchange -->
          <button @click="openExchange" class="mobile-action-btn">
            <span class="text-xl">💱</span>
            <span class="mobile-action-label">{{ t('mining.exchange', 'Exchange') }}</span>
          </button>

          <!-- Forge -->
          <button @click="openForge" class="mobile-action-btn">
            <span class="text-xl">🔨</span>
            <span class="mobile-action-label">{{ t('forge.title', 'Forge') }}</span>
          </button>

          <!-- Inventory -->
          <button @click="openInventory" class="mobile-action-btn">
            <span class="text-xl">🎒</span>
            <span class="mobile-action-label">{{ t('mining.inventory', 'Inventory') }}</span>
          </button>
        </div>
      </div>

      <!-- Desktop Floating Cards -->
      <div class="hidden sm:flex flex-col justify-end gap-2 pb-4">
        <transition
          enter-active-class="transition-all duration-200 ease-out"
          leave-active-class="transition-all duration-200 ease-in"
          enter-from-class="opacity-0 -translate-y-2"
          enter-to-class="opacity-100 translate-y-0"
          leave-from-class="opacity-100 translate-y-0"
          leave-to-class="opacity-0 -translate-y-2"
        >
        <div v-show="desktopButtonsVisible" class="flex flex-col gap-2">
        <!-- Defense Button -->
        <button
          @click="openDefense"
          class="relative flex items-center gap-2 px-3 py-2 bg-slate-800 border border-slate-600 hover:bg-slate-700 transition-all rounded-lg group"
        >
          <div class="absolute left-0 top-0 bottom-0 w-[3px] bg-red-500"></div>
          <div class="w-8 h-8 rounded-md flex items-center justify-center">
            <span class="text-lg">&#9876;</span>
          </div>
          <div class="text-left">
            <div class="text-xs font-semibold text-slate-200">{{ t('defense.title', 'Block Defense') }}</div>
            <div class="text-[10px] text-slate-400">{{ t('defense.subtitle', 'Tower Defense') }}</div>
          </div>
          <!-- Bubble badge -->
          <span
            v-if="defenseStore.lobbyCount > 0"
            class="lobby-bubble lobby-bubble--desktop"
          >{{ t('defense.lobbyBubble', 'Someone wants to battle!') }}</span>
        </button>

        <!-- Market Button -->
        <button
          @click="openMarket"
          class="relative flex items-center gap-2 px-3 py-2 bg-slate-800 border border-slate-600 hover:bg-slate-700 transition-all rounded-lg group"
        >
          <div class="w-8 h-8 rounded-md flex items-center justify-center">
            <span class="text-lg">🛒</span>
          </div>
          <div class="text-left">
            <div class="text-xs font-semibold text-slate-200">{{ t('mining.market') }}</div>
            <div class="text-[10px] text-slate-400">{{ t('market.buyRigs') }}</div>
          </div>
        </button>

        <!-- Exchange Button -->
        <button
          @click="openExchange"
          class="relative flex items-center gap-2 px-3 py-2 bg-slate-800 border border-slate-600 hover:bg-slate-700 transition-all rounded-lg group"
        >
          <div class="w-8 h-8 rounded-md flex items-center justify-center">
            <span class="text-lg">💱</span>
          </div>
          <div class="text-left">
            <div class="text-xs font-semibold text-slate-200">{{ t('nav.exchange') }}</div>
            <div class="text-[10px] text-slate-400">{{ t('exchange.convertCrypto') }}</div>
          </div>
        </button>

        <!-- Forge Button -->
        <button
          @click="openForge"
          class="relative flex items-center gap-2 px-3 py-2 bg-slate-800 border border-slate-600 hover:bg-slate-700 transition-all rounded-lg group"
        >
          <div class="w-8 h-8 rounded-md flex items-center justify-center">
            <span class="text-lg">🔨</span>
          </div>
          <div class="text-left">
            <div class="text-xs font-semibold text-slate-200">{{ t('forge.title', 'Forge') }}</div>
            <div class="text-[10px] text-slate-400">{{ t('forge.subtitle', 'Craft upgrades') }}</div>
          </div>
        </button>

        <!-- Inventory Button -->
        <button
          @click="openInventory"
          class="relative flex items-center gap-2 px-3 py-2 bg-slate-800 border border-slate-600 hover:bg-slate-700 transition-all rounded-lg group"
        >
          <div class="w-8 h-8 rounded-md flex items-center justify-center">
            <span class="text-lg">🎒</span>
          </div>
          <div class="text-left">
            <div class="text-xs font-semibold text-slate-200">{{ t('nav.inventory') }}</div>
            <div class="text-[10px] text-slate-400">{{ t('inventory.manageItems') }}</div>
          </div>
        </button>

        <div class="w-full h-px bg-border/30 my-1"></div>

        <!-- Pending Blocks Button -->
        <button
          v-if="pendingBlocksStore.hasPending"
          @click="pendingBlocksStore.openModal"
          class="relative flex items-center gap-2 px-3 py-2 bg-slate-800 border border-slate-600 hover:bg-slate-700 transition-all rounded-lg group overflow-hidden"
        >
          <div class="absolute left-0 top-0 bottom-0 w-[3px] bg-green-500"></div>
          <div class="w-8 h-8 rounded-md flex items-center justify-center">
            <span class="text-lg">⛏️</span>
          </div>
          <div class="text-left">
            <div class="text-xs font-semibold text-slate-200">{{ t('blocks.claimTitle') }}</div>
            <div class="text-[10px] text-slate-400">{{ formatCompact(pendingBlocksStore.totalReward) }} ₿</div>
          </div>
          <div class="ml-auto px-1.5 py-0.5 bg-green-500 text-white text-[10px] font-bold rounded-full">
            {{ pendingBlocksStore.count }}
          </div>
        </button>

        <!-- Rewards (Missions + Streak) -->
        <button
          @click="openRewards()"
          class="relative flex items-center gap-2 px-3 py-2 bg-slate-800 border border-slate-600 hover:bg-slate-700 transition-all rounded-lg group"
          :class="{ 'border-green-500 animate-border-pulse-green': missionsStore.claimableCount > 0 || streakStore.canClaim }"
        >
          <div class="w-8 h-8 rounded-md flex items-center justify-center">
            <span class="text-lg">🎯</span>
          </div>
          <div class="text-left">
            <div class="text-xs font-semibold text-slate-200">{{ t('missions.button') }}</div>
            <div class="text-[10px] text-slate-400">
              {{ missionsStore.completedCount }}/{{ missionsStore.totalCount }}
              <span v-if="streakStore.currentStreak > 0" class="ml-1">· 🔥{{ streakStore.currentStreak }}</span>
            </div>
          </div>
          <div
            class="ml-auto px-1.5 py-0.5 text-[10px] font-bold rounded-full"
            :class="(missionsStore.claimableCount > 0 || streakStore.canClaim) ? 'bg-status-success text-white' : 'bg-slate-700 text-slate-300'"
          >
            {{ (missionsStore.claimableCount > 0 || streakStore.canClaim) ? (missionsStore.claimableCount || 0) + (streakStore.canClaim ? 1 : 0) : `${missionsStore.completedCount}/${missionsStore.totalCount}` }}
          </div>
        </button>
        </div>
        </transition>

        <!-- Connection Status (desktop, always visible above toggle button) -->
        <div
          v-if="authStore.isAuthenticated || authStore.sessionLost"
          class="flex items-center gap-1.5 px-2 py-1 bg-bg-secondary/80 backdrop-blur-sm border rounded-full text-[10px] cursor-pointer transition-all hover:bg-bg-secondary self-end"
          :class="connectionBorderClass"
          @click="handleConnectionClick"
        >
          <span class="w-1.5 h-1.5 rounded-full" :class="connectionDotClass"></span>
          <span :class="connectionTextClass">{{ connectionStatusText }}</span>
        </div>

        <!-- Toggle visibility button + badges when collapsed -->
        <div class="flex items-center gap-1.5 ml-auto">
          <template v-if="!desktopButtonsVisible">
            <span
              v-if="pendingBlocksStore.hasPending"
              class="flex items-center gap-1 px-2 py-1 bg-slate-800 border border-green-500 rounded-lg text-[10px] font-bold text-green-400 cursor-pointer animate-border-pulse-green"
              @click="pendingBlocksStore.openModal"
            >⛏️ {{ pendingBlocksStore.count }}</span>
            <span
              v-if="missionsStore.claimableCount > 0 || streakStore.canClaim"
              class="flex items-center gap-1 px-2 py-1 bg-slate-800 border border-green-500 rounded-lg text-[10px] font-bold text-green-400 cursor-pointer animate-border-pulse-green"
              @click="openRewards()"
            >🎯 {{ (missionsStore.claimableCount || 0) + (streakStore.canClaim ? 1 : 0) }}</span>
            <span
              v-if="defenseStore.lobbyCount > 0"
              class="flex items-center gap-1 px-2 py-1 bg-slate-800 border border-red-600/50 rounded-lg text-[10px] font-bold text-green-400 cursor-pointer"
              @click="openDefense"
            >&#9876; {{ defenseStore.lobbyCount }}</span>
          </template>
          <button
            @click="desktopButtonsVisible = !desktopButtonsVisible"
            class="flex items-center gap-1.5 px-2 h-8 bg-slate-800/80 border border-slate-600/50 hover:bg-slate-700 transition-all rounded-lg text-slate-400 hover:text-slate-200"
            :title="desktopButtonsVisible ? 'Hide buttons' : 'Show buttons'"
          >
            <span v-if="!desktopButtonsVisible" class="text-[11px] font-medium">{{ t('nav.menu', 'Menu') }}</span>
            <span class="text-sm transition-transform duration-200" :class="desktopButtonsVisible ? 'rotate-180' : 'rotate-0'">&#9660;</span>
          </button>
        </div>
      </div>
    </div>

    <!-- Footer -->
    <footer class="border-t border-border/30 py-8 text-center space-y-3">
      <div class="space-y-1.5">
        <p class="text-sm font-semibold text-text-secondary">{{ $t('footer.tagline') }}</p>
        <p class="text-xs text-text-muted max-w-sm mx-auto leading-relaxed">{{ $t('footer.description') }}</p>
      </div>
      <div class="flex items-center justify-center gap-4">
        <a
          href="https://discord.gg/vFK8mB58"
          target="_blank"
          rel="noopener noreferrer"
          class="inline-flex items-center gap-1.5 text-sm text-indigo-400 hover:text-indigo-300 transition-colors"
        >
          <svg class="w-4 h-4" viewBox="0 0 24 24" fill="currentColor"><path d="M20.317 4.37a19.791 19.791 0 0 0-4.885-1.515.074.074 0 0 0-.079.037c-.21.375-.444.864-.608 1.25a18.27 18.27 0 0 0-5.487 0 12.64 12.64 0 0 0-.617-1.25.077.077 0 0 0-.079-.037A19.736 19.736 0 0 0 3.677 4.37a.07.07 0 0 0-.032.027C.533 9.046-.32 13.58.099 18.057a.082.082 0 0 0 .031.057 19.9 19.9 0 0 0 5.993 3.03.078.078 0 0 0 .084-.028c.462-.63.874-1.295 1.226-1.994a.076.076 0 0 0-.041-.106 13.107 13.107 0 0 1-1.872-.892.077.077 0 0 1-.008-.128 10.2 10.2 0 0 0 .372-.292.074.074 0 0 1 .077-.01c3.928 1.793 8.18 1.793 12.062 0a.074.074 0 0 1 .078.01c.12.098.246.198.373.292a.077.077 0 0 1-.006.127 12.299 12.299 0 0 1-1.873.892.077.077 0 0 0-.041.107c.36.698.772 1.362 1.225 1.993a.076.076 0 0 0 .084.028 19.839 19.839 0 0 0 6.002-3.03.077.077 0 0 0 .032-.054c.5-5.177-.838-9.674-3.549-13.66a.061.061 0 0 0-.031-.03z"/></svg>
          {{ $t('footer.discord') }}
        </a>
        <span class="text-border">|</span>
        <button
          @click="showGuide = true"
          class="text-sm text-indigo-400 hover:text-indigo-300 transition-colors"
        >
          {{ $t('footer.howToPlay') }}
        </button>
        <span class="text-border">|</span>
        <RouterLink to="/rules" class="text-sm text-indigo-400 hover:text-indigo-300 transition-colors">
          {{ $t('footer.rules') }}
        </RouterLink>
        <span class="text-border">|</span>
        <RouterLink to="/terms" class="text-sm text-indigo-400 hover:text-indigo-300 transition-colors">
          {{ $t('footer.terms') }}
        </RouterLink>
      </div>
      <p class="text-text-muted text-xs italic">{{ $t('footer.disclaimer') }}</p>
      <p class="text-text-muted text-sm">LootMine &copy; 2025</p>
    </footer>
  </div>
</template>

<style scoped>
/* AdSense responsive sizing */
@media (max-width: 640px) {
  .adsbygoogle {
    height: 50px !important;
  }
}

/* Mobile Action Bar */
.mobile-action-bar {
  background: linear-gradient(to top, rgba(var(--color-bg-secondary-rgb, 20, 20, 30), 0.98), rgba(var(--color-bg-secondary-rgb, 20, 20, 30), 0.95));
  backdrop-filter: blur(12px);
  -webkit-backdrop-filter: blur(12px);
  border-top: 1px solid rgba(255, 255, 255, 0.08);
  box-shadow: 0 -4px 20px rgba(0, 0, 0, 0.3);
}

.safe-area-bottom {
  padding-bottom: max(0.375rem, env(safe-area-inset-bottom));
}

.mobile-action-btn {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 0.125rem;
  padding: 0.375rem 0.4rem;
  border-radius: 0.75rem;
  transition: all 0.2s ease;
}

.mobile-action-btn:active {
  transform: scale(0.95);
  background: rgba(255, 255, 255, 0.05);
}

.mobile-action-btn-highlight {
  animation: pulse-glow 2s infinite;
}

.mobile-action-btn-success {
  animation: pulse-glow-success 2s infinite;
}

@keyframes pulse-glow {
  0%, 100% {
    box-shadow: 0 0 0 0 rgba(var(--color-accent-primary-rgb, 249, 115, 22), 0.4);
  }
  50% {
    box-shadow: 0 0 0 8px rgba(var(--color-accent-primary-rgb, 249, 115, 22), 0);
  }
}

@keyframes pulse-glow-success {
  0%, 100% {
    box-shadow: 0 0 0 0 rgba(var(--color-status-success-rgb, 34, 197, 94), 0.4);
  }
  50% {
    box-shadow: 0 0 0 8px rgba(var(--color-status-success-rgb, 34, 197, 94), 0);
  }
}

.mobile-action-label {
  font-size: 0.625rem;
  font-weight: 500;
  color: rgba(255, 255, 255, 0.6);
  white-space: nowrap;
}

/* Battle button inline but distinctive */
.mobile-battle-btn {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 0.125rem;
  padding: 0.375rem 0.5rem;
  min-width: 2.8rem;
  border-radius: 0.75rem;
  border: 1px solid rgba(220, 38, 38, 0.4);
  background: rgba(220, 38, 38, 0.12);
  transition: all 0.2s ease;
}

.mobile-battle-btn:active {
  transform: scale(0.95);
  background: rgba(220, 38, 38, 0.2);
}

.mobile-badge {
  position: absolute;
  top: -4px;
  right: -6px;
  min-width: 16px;
  height: 16px;
  padding: 0 4px;
  font-size: 0.625rem;
  font-weight: 700;
  color: white;
  border-radius: 9999px;
  display: flex;
  align-items: center;
  justify-content: center;
  box-shadow: 0 2px 4px rgba(0, 0, 0, 0.3);
}

/* Border pulse animation - green */
.animate-border-pulse-green {
  animation: border-pulse-green 1.5s ease-in-out infinite;
}

@keyframes border-pulse-green {
  0%, 100% {
    box-shadow: 0 0 0 0 rgba(34, 197, 94, 0.4);
  }
  50% {
    box-shadow: 0 0 8px 2px rgba(34, 197, 94, 0.6);
  }
}

/* Speech-bubble badge for lobby waiting */
.lobby-bubble {
  position: absolute;
  bottom: calc(100% + 8px);
  left: 50%;
  transform: translateX(-50%);
  width: max-content;
  max-width: 140px;
  text-align: center;
  padding: 4px 8px;
  font-size: 0.6rem;
  line-height: 1.3;
  font-weight: 600;
  color: white;
  background: #16a34a;
  border-radius: 8px;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.3);
  animation: bubble-bounce 2s ease-in-out infinite;
  pointer-events: none;
  z-index: 10;
}

/* Triangle pointer */
.lobby-bubble::after {
  content: '';
  position: absolute;
  top: 100%;
  left: 50%;
  transform: translateX(-50%);
  border: 5px solid transparent;
  border-top-color: #16a34a;
}

/* Desktop variant — above the button, aligned to center */
.lobby-bubble--desktop {
  bottom: calc(100% + 8px);
  left: 50%;
  right: auto;
  top: auto;
  transform: translateX(-50%);
  max-width: 160px;
}

@keyframes bubble-bounce {
  0%, 100% {
    transform: translateX(-50%) translateY(0);
  }
  50% {
    transform: translateX(-50%) translateY(-3px);
  }
}
</style>
