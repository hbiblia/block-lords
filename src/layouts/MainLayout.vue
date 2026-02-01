<script setup lang="ts">
import { onMounted, onUnmounted, watch, ref, provide, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAuthStore } from '@/stores/auth';
import { useRealtimeStore } from '@/stores/realtime';
import { useStreakStore } from '@/stores/streak';
import { useMissionsStore } from '@/stores/missions';

const { t } = useI18n();
import NavBar from '@/components/NavBar.vue';
import InfoBar from '@/components/InfoBar.vue';
import ConnectionLostModal from '@/components/ConnectionLostModal.vue';
import GameNotificationsModal from '@/components/GameNotificationsModal.vue';
import StreakModal from '@/components/StreakModal.vue';
import MissionsPanel from '@/components/MissionsPanel.vue';
import ToastContainer from '@/components/ToastContainer.vue';

const authStore = useAuthStore();
const realtimeStore = useRealtimeStore();
const streakStore = useStreakStore();
const missionsStore = useMissionsStore();

// InfoBar visibility state - shared via provide/inject
const infoBarVisible = ref(false);
provide('infoBarVisible', infoBarVisible);

// Cargar estado de streak y misiones al inicio
onMounted(() => {
  if (authStore.isAuthenticated) {
    streakStore.fetchStatus();
    missionsStore.fetchMissions();
    missionsStore.startHeartbeat();
    // Inicializar AdSense
    try {
      ((window as any).adsbygoogle = (window as any).adsbygoogle || []).push({});
    } catch (e) {
      console.error('AdSense error:', e);
    }
  }
});

// Iniciar/detener heartbeat cuando cambia el estado de autenticación
watch(() => authStore.isAuthenticated, (isAuth) => {
  if (isAuth) {
    missionsStore.startHeartbeat();
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
});

onUnmounted(() => {
  missionsStore.stopHeartbeat();
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

    <!-- Main Content -->
    <main
      class="flex-1 container mx-auto px-4 py-6 transition-[margin] duration-300"
      :class="infoBarVisible ? 'mt-[6.5rem]' : 'mt-16'"
    >
      <slot />
    </main>

    <!-- Connection Status -->
    <div
      v-if="authStore.isAuthenticated"
      class="fixed bottom-4 left-4 flex items-center gap-2 px-3 py-2 card text-xs"
    >
      <span
        class="w-2 h-2 rounded-full"
        :class="realtimeStore.isConnected ? 'bg-status-success animate-pulse' : 'bg-status-danger'"
      ></span>
      <span class="text-text-muted">
        {{ realtimeStore.isConnected ? t('nav.connected') : t('nav.disconnected') }}
      </span>
    </div>

    <!-- Engagement Buttons -->
    <div
      v-if="authStore.isAuthenticated"
      class="fixed bottom-4 right-4 flex flex-col gap-2"
    >
      <!-- Missions Button -->
      <button
        @click="missionsStore.openPanel"
        class="flex items-center gap-2 px-4 py-3 card hover:bg-bg-tertiary transition-colors"
        :class="{ 'ring-2 ring-status-success animate-pulse': missionsStore.claimableCount > 0 }"
      >
        <span class="text-2xl">🎯</span>
        <div class="text-left">
          <div class="text-xs text-text-muted">{{ t('missions.button') }}</div>
          <div class="text-sm font-bold">{{ missionsStore.completedCount }}/{{ missionsStore.totalCount }}</div>
        </div>
        <div
          v-if="missionsStore.claimableCount > 0"
          class="ml-2 px-2 py-0.5 bg-status-success/20 text-status-success text-xs font-bold rounded-full"
        >
          {{ missionsStore.claimableCount }}
        </div>
      </button>

      <!-- Streak Button -->
      <button
        @click="streakStore.openModal"
        class="flex items-center gap-2 px-4 py-3 card hover:bg-bg-tertiary transition-colors"
        :class="{ 'ring-2 ring-accent-primary animate-pulse': streakStore.canClaim }"
      >
        <span class="text-2xl">🔥</span>
        <div class="text-left">
          <div class="text-xs text-text-muted">{{ t('streak.button') }}</div>
          <div class="text-sm font-bold">{{ streakStore.currentStreak }} {{ t('streak.days') }}</div>
        </div>
        <div
          v-if="streakStore.canClaim"
          class="ml-2 px-2 py-0.5 bg-accent-primary/20 text-accent-primary text-xs font-bold rounded-full"
        >
          {{ t('streak.claim') }}
        </div>
      </button>
    </div>

    <!-- Footer -->
    <footer class="border-t border-border/30 py-6 text-center pb-20">
      <p class="text-text-muted text-sm">Block Lords &copy; 2025</p>
    </footer>

    <!-- AdSense Banner (bottom fixed) -->
    <div
      v-if="authStore.isAuthenticated"
      class="fixed bottom-0 left-0 right-0 z-50 flex justify-center bg-bg-secondary/95 backdrop-blur-sm border-t border-border/30"
    >
      <ins class="adsbygoogle"
        style="display:block"
        data-ad-format="autorelaxed"
        data-ad-client="ca-pub-7500429866047477"
        data-ad-slot="7767935377"></ins>
    </div>
  </div>
</template>

<style scoped>
/* Ensure ad container doesn't break layout on mobile */
@media (max-width: 728px) {
  .adsbygoogle {
    width: 100% !important;
    height: 50px !important;
  }
}
</style>
