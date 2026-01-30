<script setup lang="ts">
import { ref } from 'vue';
import { useAuthStore } from '@/stores/auth';
import { useRealtimeStore } from '@/stores/realtime';
import NavBar from '@/components/NavBar.vue';
import PrepaidCardsPanel from '@/components/PrepaidCardsPanel.vue';
import InventoryModal from '@/components/InventoryModal.vue';
import ExchangeModal from '@/components/ExchangeModal.vue';

const authStore = useAuthStore();
const realtimeStore = useRealtimeStore();

const showPrepaidCards = ref(false);
const showInventory = ref(false);
const showExchange = ref(false);

function handleRecharge() {
  showPrepaidCards.value = true;
}

function handleOpenInventory() {
  showInventory.value = true;
}

function handleOpenExchange() {
  showExchange.value = true;
}

function handleCardRedeemed() {
  authStore.fetchPlayer();
}

function handleInventoryUsed() {
  authStore.fetchPlayer();
}

function handleExchanged() {
  authStore.fetchPlayer();
}
</script>

<template>
  <div class="min-h-screen flex flex-col bg-bg-primary">
    <NavBar @recharge="handleRecharge" @inventory="handleOpenInventory" @exchange="handleOpenExchange" />

    <!-- Prepaid Cards Panel -->
    <PrepaidCardsPanel
      :show="showPrepaidCards"
      @close="showPrepaidCards = false"
      @redeemed="handleCardRedeemed"
    />

    <!-- Inventory Modal -->
    <InventoryModal
      :show="showInventory"
      @close="showInventory = false"
      @used="handleInventoryUsed"
    />

    <!-- Exchange Modal -->
    <ExchangeModal
      :show="showExchange"
      @close="showExchange = false"
      @exchanged="handleExchanged"
    />

    <!-- Main Content -->
    <main class="flex-1 container mx-auto px-4 py-6 mt-16">
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
        {{ realtimeStore.isConnected ? 'Conectado' : 'Desconectado' }}
      </span>
    </div>

    <!-- Footer -->
    <footer class="border-t border-border/30 py-6 text-center">
      <p class="text-text-muted text-sm">Block Lords &copy; 2025</p>
    </footer>
  </div>
</template>
