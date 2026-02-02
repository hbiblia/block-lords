<script setup lang="ts">
import { onMounted, onUnmounted, watch, ref, provide, nextTick, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useAuthStore } from '@/stores/auth';
import { useRealtimeStore } from '@/stores/realtime';
import { useStreakStore } from '@/stores/streak';
import { useMissionsStore } from '@/stores/missions';
import { usePendingBlocksStore } from '@/stores/pendingBlocks';

const { t } = useI18n();
const route = useRoute();

// Check if on mining page for mobile action buttons
const isMiningPage = computed(() => route.path === '/mining');

// Emit events for MiningPage to handle
function openMarket() {
  window.dispatchEvent(new CustomEvent('open-market'));
}
function openExchange() {
  window.dispatchEvent(new CustomEvent('open-exchange'));
}
function openInventory() {
  window.dispatchEvent(new CustomEvent('open-inventory'));
}
import NavBar from '@/components/NavBar.vue';
import InfoBar from '@/components/InfoBar.vue';
import ConnectionLostModal from '@/components/ConnectionLostModal.vue';
import GameNotificationsModal from '@/components/GameNotificationsModal.vue';
import StreakModal from '@/components/StreakModal.vue';
import MissionsPanel from '@/components/MissionsPanel.vue';
import ToastContainer from '@/components/ToastContainer.vue';
import BlockClaimModal from '@/components/BlockClaimModal.vue';

const authStore = useAuthStore();
const realtimeStore = useRealtimeStore();
const streakStore = useStreakStore();
const missionsStore = useMissionsStore();
const pendingBlocksStore = usePendingBlocksStore();

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

// Escuchar evento de bloque minado
onMounted(() => {
  window.addEventListener('block-mined', handleBlockMined as EventListener);
});

// Cargar datos cuando cambia el estado de autenticación
watch(() => authStore.isAuthenticated, (isAuth) => {
  if (isAuth) {
    // Cargar streak, misiones y bloques pendientes
    streakStore.fetchStatus();
    missionsStore.fetchMissions();
    missionsStore.startHeartbeat();
    pendingBlocksStore.fetchPendingBlocks();
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
  }
}, { immediate: true });

onUnmounted(() => {
  missionsStore.stopHeartbeat();
  window.removeEventListener('block-mined', handleBlockMined as EventListener);
});
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

    <!-- Main Content -->
    <main
      class="flex-1 container mx-auto px-4 py-6 pb-20 sm:pb-6 transition-[margin] duration-300"
      :class="infoBarVisible ? 'mt-[6.5rem]' : 'mt-16'"
    >
      <slot />
    </main>

    <!-- Connection Status -->
    <div
      v-if="authStore.isAuthenticated"
      class="fixed bottom-[4.5rem] sm:bottom-20 left-2 sm:left-4 flex items-center gap-1.5 px-2 py-1 bg-bg-secondary/80 backdrop-blur-sm border border-border/30 rounded-full text-[10px] sm:text-xs shadow-lg"
    >
      <span
        class="w-1.5 h-1.5 sm:w-2 sm:h-2 rounded-full"
        :class="realtimeStore.isConnected ? 'bg-status-success animate-pulse' : 'bg-status-danger'"
      ></span>
      <span class="text-text-muted">
        {{ realtimeStore.isConnected ? t('nav.connected') : t('nav.disconnected') }}
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

          <!-- Divider (only on mining page) -->
          <div v-if="isMiningPage" class="w-px h-8 bg-border/50"></div>

          <!-- Mining Actions (only on mining page) -->
          <template v-if="isMiningPage">
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
          </template>
        </div>
      </div>

      <!-- Desktop Floating Cards -->
      <div class="hidden sm:flex flex-col gap-2">
        <!-- Pending Blocks Button -->
        <button
          v-if="pendingBlocksStore.hasPending"
          @click="pendingBlocksStore.openModal"
          class="relative flex items-center justify-start gap-2 px-4 py-3 card hover:bg-bg-tertiary transition-colors ring-2 ring-accent-primary animate-pulse rounded-xl"
        >
          <span class="text-2xl">⛏️</span>
          <div class="text-left">
            <div class="text-xs text-text-muted">{{ t('blocks.claimTitle') }}</div>
            <div class="text-sm font-bold">{{ pendingBlocksStore.totalReward.toFixed(2) }} ₿</div>
          </div>
          <div class="ml-2 px-2 py-0.5 bg-accent-primary/20 text-accent-primary text-xs font-bold rounded-full">
            {{ pendingBlocksStore.count }}
          </div>
        </button>

        <!-- Missions Button -->
        <button
          @click="missionsStore.openPanel"
          class="relative flex items-center justify-start gap-2 px-4 py-3 card hover:bg-bg-tertiary transition-colors rounded-xl"
          :class="{ 'ring-2 ring-status-success animate-pulse': missionsStore.claimableCount > 0 }"
        >
          <span class="text-2xl">🎯</span>
          <div class="text-left">
            <div class="text-xs text-text-muted">{{ t('missions.button') }}</div>
            <div class="text-sm font-bold">{{ missionsStore.completedCount }}/{{ missionsStore.totalCount }}</div>
          </div>
          <div
            class="ml-2 px-2 py-0.5 text-xs font-bold rounded-full"
            :class="missionsStore.claimableCount > 0 ? 'bg-status-success/20 text-status-success' : 'bg-bg-tertiary text-text-secondary'"
          >
            {{ missionsStore.claimableCount > 0 ? missionsStore.claimableCount : `${missionsStore.completedCount}/${missionsStore.totalCount}` }}
          </div>
        </button>

        <!-- Streak Button -->
        <button
          @click="streakStore.openModal"
          class="relative flex items-center justify-start gap-2 px-4 py-3 card hover:bg-bg-tertiary transition-colors rounded-xl"
          :class="{ 'ring-2 ring-accent-primary animate-pulse': streakStore.canClaim }"
        >
          <span class="text-2xl">🔥</span>
          <div class="text-left">
            <div class="text-xs text-text-muted">{{ t('streak.button') }}</div>
            <div class="text-sm font-bold">{{ streakStore.currentStreak }} {{ t('streak.days') }}</div>
          </div>
          <div
            class="ml-2 px-2 py-0.5 text-xs font-bold rounded-full"
            :class="streakStore.canClaim ? 'bg-accent-primary/20 text-accent-primary' : 'bg-bg-tertiary text-text-secondary'"
          >
            {{ streakStore.canClaim ? '!' : streakStore.currentStreak }}
          </div>
        </button>
      </div>
    </div>

    <!-- AdSense Banner (inline) -->
    <div
      v-if="authStore.isAuthenticated"
      class="w-full flex justify-center bg-bg-secondary/50 border-t border-border/30 py-2"
    >
      <ins class="adsbygoogle"
        style="display:block; max-width:728px; width:100%; height:90px;"
        data-ad-format="horizontal"
        data-ad-client="ca-pub-7500429866047477"
        data-ad-slot="7767935377"></ins>
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
</style>
