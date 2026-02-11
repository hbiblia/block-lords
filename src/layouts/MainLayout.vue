<script setup lang="ts">
import { onMounted, onUnmounted, watch, ref, provide, nextTick, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAuthStore } from '@/stores/auth';
import { useRealtimeStore } from '@/stores/realtime';
import { useStreakStore } from '@/stores/streak';
import { useMissionsStore } from '@/stores/missions';
import { usePendingBlocksStore } from '@/stores/pendingBlocks';
import { useMiningStore } from '@/stores/mining';
import { useGiftsStore } from '@/stores/gifts';
import { useToastStore } from '@/stores/toast';
import { playSound } from '@/utils/sounds';

const { t } = useI18n();

// Global modals state
const showMarket = ref(false);
const showInventory = ref(false);
const showExchange = ref(false);
const showDefense = ref(false);

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

import NavBar from '@/components/NavBar.vue';
import InfoBar from '@/components/InfoBar.vue';
import ConnectionLostModal from '@/components/ConnectionLostModal.vue';
import GameNotificationsModal from '@/components/GameNotificationsModal.vue';
import StreakModal from '@/components/StreakModal.vue';
import MissionsPanel from '@/components/MissionsPanel.vue';
import ToastContainer from '@/components/ToastContainer.vue';
import BlockClaimModal from '@/components/BlockClaimModal.vue';
import MarketModal from '@/components/MarketModal.vue';
import InventoryModal from '@/components/InventoryModal.vue';
import ExchangeModal from '@/components/ExchangeModal.vue';
import GiftModal from '@/components/GiftModal.vue';
import DefenseModal from '@/components/DefenseModal.vue';

const authStore = useAuthStore();
const realtimeStore = useRealtimeStore();
const streakStore = useStreakStore();
const missionsStore = useMissionsStore();
const pendingBlocksStore = usePendingBlocksStore();
const miningStore = useMiningStore();
const giftsStore = useGiftsStore();
const toastStore = useToastStore();

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

// Escuchar evento de bloque minado para actualizar pending blocks
function handleBlockMined(event: CustomEvent) {
  const { winner } = event.detail;
  // Si el jugador actual minó el bloque, actualizar pending blocks
  if (winner?.id === authStore.player?.id) {
    pendingBlocksStore.fetchPendingBlocks();
  }
}

// Escuchar evento de bloque pendiente creado (incluye pity blocks)
function handlePendingBlockCreated(event: CustomEvent) {
  pendingBlocksStore.fetchPendingBlocks();

  // Mostrar toast con la recompensa del cierre de bloque
  const { reward } = event.detail;
  if (reward) {
    playSound('block_mined');
    toastStore.show(`+${Number(reward).toFixed(4)} ₿`, 'success', {
      icon: '⛏️',
      duration: 6000,
    });
  }
}

// Event handlers for modal opening from other pages
function handleOpenMarketEvent() {
  showMarket.value = true;
}
function handleOpenExchangeEvent() {
  showExchange.value = true;
}
function handleOpenInventoryEvent() {
  showInventory.value = true;
}

// Escuchar eventos
onMounted(() => {
  window.addEventListener('block-mined', handleBlockMined as EventListener);
  window.addEventListener('pending-block-created', handlePendingBlockCreated as EventListener);
  window.addEventListener('open-market', handleOpenMarketEvent);
  window.addEventListener('open-exchange', handleOpenExchangeEvent);
  window.addEventListener('open-inventory', handleOpenInventoryEvent);
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
    // Iniciar verificación periódica de sesión
    authStore.startSessionCheck();
    // Inicializar AdSense cuando el usuario se autentica
    nextTick(() => {
      try {
        ((window as any).adsbygoogle = (window as any).adsbygoogle || []).push({});
      } catch (e) {
        console.error('AdSense error:', e);
      }
    });
  } else {
    missionsStore.stopHeartbeat();
    authStore.stopSessionCheck();
    giftsStore.stopPolling();
  }
}, { immediate: true });

onUnmounted(() => {
  missionsStore.stopHeartbeat();
  authStore.stopSessionCheck();
  giftsStore.stopPolling();
  window.removeEventListener('block-mined', handleBlockMined as EventListener);
  window.removeEventListener('pending-block-created', handlePendingBlockCreated as EventListener);
  window.removeEventListener('open-market', handleOpenMarketEvent);
  window.removeEventListener('open-exchange', handleOpenExchangeEvent);
  window.removeEventListener('open-inventory', handleOpenInventoryEvent);
});

// Connection status computed properties
const isFullyConnected = computed(() => realtimeStore.isConnected && authStore.isServerOnline && !authStore.sessionLost);
const hasApiIssue = computed(() => !authStore.isServerOnline && !authStore.sessionLost);
const hasRealtimeIssue = computed(() => !realtimeStore.isConnected);
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
        realtimeStore.connect();
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

    <NavBar />

    <!-- Connection Lost Modal -->
    <ConnectionLostModal />

    <!-- Game Notifications Modal -->
    <GameNotificationsModal />

    <!-- Toast Notifications -->
    <ToastContainer />

    <!-- Streak Modal -->
    <StreakModal
      :show="streakStore.showModal"
      @close="streakStore.closeModal"
    />

    <!-- Missions Panel -->
    <MissionsPanel
      :show="missionsStore.showPanel"
      @close="missionsStore.closePanel"
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

    <!-- Gift Modal -->
    <GiftModal />

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

    <!-- Main Content -->
    <main
      class="flex-1 container mx-auto px-4 py-6 pb-20 sm:pb-6 transition-[margin] duration-300"
      :class="infoBarVisible ? 'mt-[6.5rem]' : 'mt-16'"
    >
      <slot />
    </main>

    <!-- Connection Status -->
    <div
      v-if="authStore.isAuthenticated || authStore.sessionLost"
      class="fixed bottom-[4.5rem] sm:bottom-20 left-2 sm:left-4 flex items-center gap-1.5 px-2 py-1 bg-bg-secondary/80 backdrop-blur-sm border rounded-full text-[10px] sm:text-xs shadow-lg cursor-pointer transition-all hover:bg-bg-secondary"
      :class="connectionBorderClass"
      @click="handleConnectionClick"
    >
      <span
        class="w-1.5 h-1.5 sm:w-2 sm:h-2 rounded-full"
        :class="connectionDotClass"
      ></span>
      <span :class="connectionTextClass">
        {{ connectionStatusText }}
      </span>
    </div>

    <!-- Mobile Bottom Action Bar -->
    <div
      v-if="authStore.isAuthenticated"
      class="fixed bottom-0 left-0 right-0 z-40 sm:bottom-14 sm:left-auto sm:right-4 sm:w-auto"
    >
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

          <!-- Missions -->
          <button
            @click="missionsStore.openPanel"
            class="mobile-action-btn"
            :class="{ 'mobile-action-btn-success': missionsStore.claimableCount > 0 }"
          >
            <div class="relative">
              <span class="text-xl">🎯</span>
              <span
                v-if="missionsStore.claimableCount > 0"
                class="mobile-badge bg-status-success"
              >{{ missionsStore.claimableCount }}</span>
            </div>
            <span class="mobile-action-label">{{ t('missions.short', 'Missions') }}</span>
          </button>

          <!-- Streak -->
          <button
            @click="streakStore.openModal"
            class="mobile-action-btn"
            :class="{ 'mobile-action-btn-highlight': streakStore.canClaim }"
          >
            <div class="relative">
              <span class="text-xl">🔥</span>
              <span
                v-if="streakStore.canClaim"
                class="mobile-badge bg-accent-primary"
              >!</span>
            </div>
            <span class="mobile-action-label">{{ t('streak.short', 'Streak') }}</span>
          </button>

          <!-- Divider -->
          <div class="w-px h-8 bg-border/50"></div>

          <!-- Market -->
          <button @click="openMarket" class="mobile-action-btn">
            <span class="text-xl">🛒</span>
            <span class="mobile-action-label">{{ t('mining.market', 'Market') }}</span>
          </button>

          <!-- Exchange -->
          <button @click="openExchange" class="mobile-action-btn">
            <span class="text-xl">💱</span>
            <span class="mobile-action-label">{{ t('mining.exchange', 'Exchange') }}</span>
          </button>

          <!-- Inventory -->
          <button @click="openInventory" class="mobile-action-btn">
            <span class="text-xl">🎒</span>
            <span class="mobile-action-label">{{ t('mining.inventory', 'Inventory') }}</span>
          </button>

          <!-- Defense -->
          <button @click="openDefense" class="mobile-action-btn">
            <span class="text-xl">&#9876;</span>
            <span class="mobile-action-label">{{ t('defense.short', 'Defense') }}</span>
          </button>
        </div>
      </div>

      <!-- Desktop Floating Cards -->
      <div class="hidden sm:flex flex-col gap-2">
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

        <!-- Defense Button -->
        <button
          @click="openDefense"
          class="relative flex items-center gap-2 px-3 py-2 bg-slate-800 border border-red-600/50 hover:bg-slate-700 transition-all rounded-lg group"
        >
          <div class="w-8 h-8 rounded-md flex items-center justify-center">
            <span class="text-lg">&#9876;</span>
          </div>
          <div class="text-left">
            <div class="text-xs font-semibold text-slate-200">{{ t('defense.title', 'Block Defense') }}</div>
            <div class="text-[10px] text-slate-400">{{ t('defense.subtitle', 'Tower Defense') }}</div>
          </div>
        </button>

        <div class="w-full h-px bg-border/30 my-1"></div>

        <!-- Pending Blocks Button -->
        <button
          v-if="pendingBlocksStore.hasPending"
          @click="pendingBlocksStore.openModal"
          class="relative flex items-center gap-2 px-3 py-2 bg-slate-800 border border-green-500 hover:bg-slate-700 transition-all rounded-lg group animate-border-pulse-green"
        >
          <div class="w-8 h-8 rounded-md flex items-center justify-center">
            <span class="text-lg">⛏️</span>
          </div>
          <div class="text-left">
            <div class="text-xs font-semibold text-slate-200">{{ t('blocks.claimTitle') }}</div>
            <div class="text-[10px] text-slate-400">{{ pendingBlocksStore.totalReward.toFixed(2) }} ₿</div>
          </div>
          <div class="ml-auto px-1.5 py-0.5 bg-green-500 text-white text-[10px] font-bold rounded-full">
            {{ pendingBlocksStore.count }}
          </div>
        </button>

        <!-- Missions Button -->
        <button
          @click="missionsStore.openPanel"
          class="relative flex items-center gap-2 px-3 py-2 bg-slate-800 border border-slate-600 hover:bg-slate-700 transition-all rounded-lg group"
          :class="{ 'border-green-500 animate-border-pulse-green': missionsStore.claimableCount > 0 }"
        >
          <div class="w-8 h-8 rounded-md flex items-center justify-center">
            <span class="text-lg">🎯</span>
          </div>
          <div class="text-left">
            <div class="text-xs font-semibold text-slate-200">{{ t('missions.button') }}</div>
            <div class="text-[10px] text-slate-400">{{ missionsStore.completedCount }}/{{ missionsStore.totalCount }}</div>
          </div>
          <div
            class="ml-auto px-1.5 py-0.5 text-[10px] font-bold rounded-full"
            :class="missionsStore.claimableCount > 0 ? 'bg-status-success text-white' : 'bg-slate-700 text-slate-300'"
          >
            {{ missionsStore.claimableCount > 0 ? missionsStore.claimableCount : `${missionsStore.completedCount}/${missionsStore.totalCount}` }}
          </div>
        </button>

        <!-- Streak Button -->
        <button
          @click="streakStore.openModal"
          class="relative flex items-center gap-2 px-3 py-2 bg-slate-800 border border-slate-600 hover:bg-slate-700 transition-all rounded-lg group"
          :class="{ 'border-green-500 animate-border-pulse-green': streakStore.canClaim }"
        >
          <div class="w-8 h-8 rounded-md flex items-center justify-center">
            <span class="text-lg">🔥</span>
          </div>
          <div class="text-left">
            <div class="text-xs font-semibold text-slate-200">{{ t('streak.button') }}</div>
            <div class="text-[10px] text-slate-400">{{ streakStore.currentStreak }} {{ t('streak.days') }}</div>
          </div>
          <div
            class="ml-auto px-1.5 py-0.5 text-[10px] font-bold rounded-full"
            :class="streakStore.canClaim ? 'bg-accent-primary text-white' : 'bg-slate-700 text-slate-300'"
          >
            {{ streakStore.canClaim ? '!' : streakStore.currentStreak }}
          </div>
        </button>
      </div>
    </div>

    <!-- Footer -->
    <footer class="border-t border-border/30 py-6 text-center">
      <p class="text-text-muted text-sm">Block Lords &copy; 2025</p>
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
  padding: 0.5rem 0.75rem;
  border-radius: 0.75rem;
  transition: all 0.2s ease;
  min-width: 3.5rem;
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
</style>
