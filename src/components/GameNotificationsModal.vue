<script setup lang="ts">
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useNotificationsStore } from '@/stores/notifications';
import { formatCrypto } from '@/utils/format';

const { t } = useI18n();
const router = useRouter();
const notificationsStore = useNotificationsStore();

const notification = computed(() => notificationsStore.currentNotification);

// Format notification data for display (e.g., format crypto rewards)
const formattedData = computed(() => {
  if (!notification.value?.data) return {};

  const data = { ...notification.value.data };

  // Format reward for block_mined notifications
  if (notification.value.type === 'block_mined' && typeof data.reward === 'number') {
    data.reward = formatCrypto(data.reward as number);
  }

  return data;
});

const severityColors = {
  info: {
    bg: 'bg-accent-primary/20',
    border: 'border-accent-primary',
    text: 'text-accent-primary',
  },
  warning: {
    bg: 'bg-yellow-500/20',
    border: 'border-yellow-500',
    text: 'text-yellow-500',
  },
  error: {
    bg: 'bg-status-danger/20',
    border: 'border-status-danger',
    text: 'text-status-danger',
  },
  success: {
    bg: 'bg-status-success/20',
    border: 'border-status-success',
    text: 'text-status-success',
  },
};

const currentColors = computed(() => {
  if (!notification.value) return severityColors.info;
  return severityColors[notification.value.severity] || severityColors.info;
});

function dismiss() {
  notificationsStore.dismissCurrent();
}

function goToMarket() {
  notificationsStore.dismissCurrent();
  router.push('/market');
}

function goToInventory() {
  notificationsStore.dismissCurrent();
  // Open inventory modal via event
  window.dispatchEvent(new CustomEvent('open-inventory'));
}
</script>

<template>
  <Teleport to="body">
    <div
      v-if="notificationsStore.showModal && notification"
      class="fixed inset-0 z-[100] flex items-center justify-center p-4"
    >
      <!-- Overlay -->
      <div
        class="absolute inset-0 bg-black/80 backdrop-blur-sm"
        @click="dismiss"
      ></div>

      <!-- Modal -->
      <div
        class="relative w-full max-w-md card p-6 text-center animate-fade-in border"
        :class="currentColors.border"
      >
        <!-- Icon -->
        <div
          class="w-20 h-20 mx-auto mb-4 rounded-full flex items-center justify-center text-4xl"
          :class="currentColors.bg"
        >
          {{ notification.icon || '📢' }}
        </div>

        <!-- Title -->
        <h2
          class="text-xl font-display font-bold mb-2"
          :class="currentColors.text"
        >
          {{ t(notification.title) }}
        </h2>

        <!-- Message -->
        <p class="text-text-muted mb-6">
          {{ t(notification.message, formattedData) }}
        </p>

        <!-- Action buttons based on notification type -->
        <div class="flex gap-3">
          <!-- Energy/Internet depleted - go to market -->
          <template v-if="notification.type === 'energy_depleted' || notification.type === 'internet_depleted'">
            <button
              @click="goToMarket"
              class="flex-1 py-3 rounded-lg font-medium bg-accent-primary text-white hover:bg-accent-primary/80 transition-colors"
            >
              {{ t('notifications.goToMarket') }}
            </button>
            <button
              @click="dismiss"
              class="flex-1 py-3 rounded-lg font-medium bg-bg-tertiary hover:bg-bg-tertiary/80 transition-colors"
            >
              {{ t('common.close') }}
            </button>
          </template>

          <!-- Rig broken - go to inventory -->
          <template v-else-if="notification.type === 'rig_broken'">
            <button
              @click="goToInventory"
              class="flex-1 py-3 rounded-lg font-medium bg-accent-primary text-white hover:bg-accent-primary/80 transition-colors"
            >
              {{ t('notifications.goToInventory') }}
            </button>
            <button
              @click="dismiss"
              class="flex-1 py-3 rounded-lg font-medium bg-bg-tertiary hover:bg-bg-tertiary/80 transition-colors"
            >
              {{ t('common.close') }}
            </button>
          </template>

          <!-- Rig overheated - go to inventory for cooling -->
          <template v-else-if="notification.type === 'rig_overheated' || notification.type === 'cooling_expired'">
            <button
              @click="goToInventory"
              class="flex-1 py-3 rounded-lg font-medium bg-accent-primary text-white hover:bg-accent-primary/80 transition-colors"
            >
              {{ t('notifications.manageCooling') }}
            </button>
            <button
              @click="dismiss"
              class="flex-1 py-3 rounded-lg font-medium bg-bg-tertiary hover:bg-bg-tertiary/80 transition-colors"
            >
              {{ t('common.close') }}
            </button>
          </template>

          <!-- Block mined (success) or warnings - just close -->
          <template v-else>
            <button
              @click="dismiss"
              class="flex-1 py-3 rounded-lg font-medium bg-accent-primary text-white hover:bg-accent-primary/80 transition-colors"
            >
              {{ t('common.confirm') }}
            </button>
          </template>
        </div>

        <!-- Pending notifications indicator -->
        <p
          v-if="notificationsStore.pendingNotifications.length > 1"
          class="text-xs text-text-muted mt-4"
        >
          {{ t('notifications.pendingCount', { count: notificationsStore.pendingNotifications.length - 1 }) }}
        </p>
      </div>
    </div>
  </Teleport>
</template>
