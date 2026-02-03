import { defineStore } from 'pinia';
import { ref, computed } from 'vue';
import { playSound } from '@/utils/sounds';

export type NotificationType =
  | 'energy_depleted'
  | 'internet_depleted'
  | 'rig_broken'
  | 'rig_overheated'
  | 'block_mined'
  | 'cooling_expired'
  | 'low_energy'
  | 'low_internet'
  | 'welcome_back'
  | 'rig_turned_on'
  | 'rig_turned_off'
  | 'referral_applied';

export interface GameNotification {
  id: string;
  type: NotificationType;
  title: string;
  message: string;
  icon?: string;
  severity: 'info' | 'warning' | 'error' | 'success';
  timestamp: number;
  data?: Record<string, unknown>;
  dismissed?: boolean;
}

export const useNotificationsStore = defineStore('notifications', () => {
  const notifications = ref<GameNotification[]>([]);
  const currentNotification = ref<GameNotification | null>(null);
  const showModal = ref(false);

  // Track what we've already notified about to avoid spam
  const notifiedStates = ref<Set<string>>(new Set());

  const pendingNotifications = computed(() =>
    notifications.value.filter(n => !n.dismissed)
  );

  const hasNotifications = computed(() => pendingNotifications.value.length > 0);

  function generateId(): string {
    return `notif_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  }

  function addNotification(notification: Omit<GameNotification, 'id' | 'timestamp' | 'dismissed'>) {
    const newNotification: GameNotification = {
      ...notification,
      id: generateId(),
      timestamp: Date.now(),
      dismissed: false,
    };

    notifications.value.push(newNotification);

    // Play sound based on severity
    switch (notification.severity) {
      case 'error':
        playSound('warning');
        break;
      case 'warning':
        playSound('notification');
        break;
      case 'success':
        playSound('success');
        break;
      default:
        playSound('notification');
    }

    // Show modal immediately if none is currently showing
    if (!showModal.value) {
      currentNotification.value = newNotification;
      showModal.value = true;
    }

    return newNotification.id;
  }

  function dismissCurrent() {
    if (currentNotification.value) {
      const index = notifications.value.findIndex(n => n.id === currentNotification.value?.id);
      if (index !== -1) {
        notifications.value[index].dismissed = true;
      }
    }

    // Check if there are more pending notifications
    const next = pendingNotifications.value[0];
    if (next) {
      currentNotification.value = next;
    } else {
      currentNotification.value = null;
      showModal.value = false;
    }
  }

  function dismissAll() {
    notifications.value.forEach(n => n.dismissed = true);
    currentNotification.value = null;
    showModal.value = false;
  }

  function clearOldNotifications(maxAge = 3600000) { // 1 hour default
    const now = Date.now();
    notifications.value = notifications.value.filter(n =>
      !n.dismissed || (now - n.timestamp) < maxAge
    );
  }

  // Helper to check if we should notify for a state
  function shouldNotify(stateKey: string): boolean {
    if (notifiedStates.value.has(stateKey)) {
      return false;
    }
    notifiedStates.value.add(stateKey);
    return true;
  }

  // Reset a notification state (e.g., when energy goes back up)
  function resetNotificationState(stateKey: string) {
    notifiedStates.value.delete(stateKey);
  }

  // Notify about energy depletion
  function notifyEnergyDepleted() {
    if (!shouldNotify('energy_depleted')) return;

    addNotification({
      type: 'energy_depleted',
      title: 'notifications.energyDepleted.title',
      message: 'notifications.energyDepleted.message',
      icon: '⚡',
      severity: 'error',
    });
  }

  // Notify about internet depletion
  function notifyInternetDepleted() {
    if (!shouldNotify('internet_depleted')) return;

    addNotification({
      type: 'internet_depleted',
      title: 'notifications.internetDepleted.title',
      message: 'notifications.internetDepleted.message',
      icon: '📡',
      severity: 'error',
    });
  }

  // Notify about low energy (warning)
  function notifyLowEnergy(percent: number) {
    if (!shouldNotify('low_energy')) return;

    addNotification({
      type: 'low_energy',
      title: 'notifications.lowEnergy.title',
      message: 'notifications.lowEnergy.message',
      icon: '⚠️',
      severity: 'warning',
      data: { percent },
    });
  }

  // Notify about low internet (warning)
  function notifyLowInternet(percent: number) {
    if (!shouldNotify('low_internet')) return;

    addNotification({
      type: 'low_internet',
      title: 'notifications.lowInternet.title',
      message: 'notifications.lowInternet.message',
      icon: '⚠️',
      severity: 'warning',
      data: { percent },
    });
  }

  // Notify about rig broken
  function notifyRigBroken(rigName: string) {
    addNotification({
      type: 'rig_broken',
      title: 'notifications.rigBroken.title',
      message: 'notifications.rigBroken.message',
      icon: '🔧',
      severity: 'error',
      data: { rigName },
    });
  }

  // Notify about rig overheated
  function notifyRigOverheated(rigName: string) {
    addNotification({
      type: 'rig_overheated',
      title: 'notifications.rigOverheated.title',
      message: 'notifications.rigOverheated.message',
      icon: '🌡️',
      severity: 'warning',
      data: { rigName },
    });
  }

  // Notify about block mined (success)
  function notifyBlockMined(reward: number) {
    addNotification({
      type: 'block_mined',
      title: 'notifications.blockMined.title',
      message: 'notifications.blockMined.message',
      icon: '🎉',
      severity: 'success',
      data: { reward },
    });
  }

  // Notify about cooling expired
  function notifyCoolingExpired(rigName: string) {
    addNotification({
      type: 'cooling_expired',
      title: 'notifications.coolingExpired.title',
      message: 'notifications.coolingExpired.message',
      icon: '❄️',
      severity: 'warning',
      data: { rigName },
    });
  }

  return {
    notifications,
    currentNotification,
    showModal,
    pendingNotifications,
    hasNotifications,
    addNotification,
    dismissCurrent,
    dismissAll,
    clearOldNotifications,
    shouldNotify,
    resetNotificationState,
    notifyEnergyDepleted,
    notifyInternetDepleted,
    notifyLowEnergy,
    notifyLowInternet,
    notifyRigBroken,
    notifyRigOverheated,
    notifyBlockMined,
    notifyCoolingExpired,
  };
});
