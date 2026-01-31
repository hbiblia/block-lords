<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import { useRealtimeStore } from '@/stores/realtime';

const { t } = useI18n();
const realtimeStore = useRealtimeStore();

function handleReconnect() {
  realtimeStore.manualReconnect();
}

function handleRefresh() {
  window.location.reload();
}
</script>

<template>
  <Teleport to="body">
    <div
      v-if="realtimeStore.showDisconnectedModal"
      class="fixed inset-0 z-[100] flex items-center justify-center p-4"
    >
      <!-- Overlay -->
      <div class="absolute inset-0 bg-black/80 backdrop-blur-sm"></div>

      <!-- Modal -->
      <div class="relative w-full max-w-md card p-6 text-center animate-fade-in">
        <!-- Icon -->
        <div class="w-20 h-20 mx-auto mb-4 rounded-full bg-status-danger/20 flex items-center justify-center">
          <svg class="w-10 h-10 text-status-danger" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
              d="M18.364 5.636a9 9 0 010 12.728m0 0l-2.829-2.829m2.829 2.829L21 21M15.536 8.464a5 5 0 010 7.072m0 0l-2.829-2.829m-4.243 2.829a4.978 4.978 0 01-1.414-2.83m-1.414 5.658a9 9 0 01-2.167-9.238m7.824 2.167a1 1 0 111.414 1.414m-1.414-1.414L3 3m8.293 8.293l1.414 1.414" />
          </svg>
        </div>

        <!-- Title -->
        <h2 class="text-xl font-display font-bold text-status-danger mb-2">
          {{ t('connection.title') }}
        </h2>

        <!-- Message -->
        <p class="text-text-muted mb-6">
          {{ t('connection.description') }}
        </p>

        <!-- Reconnecting indicator -->
        <div v-if="realtimeStore.reconnecting" class="mb-4 flex items-center justify-center gap-2 text-accent-primary">
          <div class="w-4 h-4 border-2 border-accent-primary border-t-transparent rounded-full animate-spin"></div>
          <span class="text-sm">{{ t('connection.reconnecting') }}</span>
        </div>

        <!-- Actions -->
        <div class="flex gap-3">
          <button
            @click="handleReconnect"
            :disabled="realtimeStore.reconnecting"
            class="flex-1 py-3 rounded-lg font-medium bg-accent-primary text-white hover:bg-accent-primary/80 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {{ t('connection.reconnect') }}
          </button>
          <button
            @click="handleRefresh"
            class="flex-1 py-3 rounded-lg font-medium bg-bg-tertiary hover:bg-bg-tertiary/80 transition-colors"
          >
            {{ t('connection.reloadPage') }}
          </button>
        </div>

        <!-- Help text -->
        <p class="text-xs text-text-muted mt-4">
          {{ t('connection.persistsNotice') }}
        </p>
      </div>
    </div>
  </Teleport>
</template>
