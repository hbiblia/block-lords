import { defineStore } from 'pinia';
import { ref } from 'vue';
import { playSound } from '@/utils/sounds';
import { i18n } from '@/plugins/i18n';

export type ToastType = 'success' | 'error' | 'warning' | 'info';

export interface Toast {
  id: string;
  message: string;
  type: ToastType;
  icon?: string;
  duration: number;
  timestamp: number;
}

export const useToastStore = defineStore('toast', () => {
  const toasts = ref<Toast[]>([]);
  const maxToasts = 5;

  function generateId(): string {
    return `toast_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  }

  function show(
    message: string,
    type: ToastType = 'info',
    options: { icon?: string; duration?: number; sound?: boolean } = {}
  ) {
    const { icon, duration = 4000, sound = true } = options;

    const toast: Toast = {
      id: generateId(),
      message,
      type,
      icon,
      duration,
      timestamp: Date.now(),
    };

    // Limit max toasts
    if (toasts.value.length >= maxToasts) {
      toasts.value.shift();
    }

    toasts.value.push(toast);

    // Play sound based on type
    if (sound) {
      switch (type) {
        case 'success':
          playSound('success');
          break;
        case 'error':
          playSound('error');
          break;
        case 'warning':
          playSound('warning');
          break;
        default:
          playSound('notification');
      }
    }

    // Auto remove after duration
    setTimeout(() => {
      remove(toast.id);
    }, duration);

    return toast.id;
  }

  function remove(id: string) {
    const index = toasts.value.findIndex(t => t.id === id);
    if (index !== -1) {
      toasts.value.splice(index, 1);
    }
  }

  function clear() {
    toasts.value = [];
  }

  // Convenience methods
  function success(message: string, icon?: string) {
    return show(message, 'success', { icon: icon ?? '✓' });
  }

  function error(message: string, icon?: string) {
    return show(message, 'error', { icon: icon ?? '✕', duration: 5000 });
  }

  function warning(message: string, icon?: string) {
    return show(message, 'warning', { icon: icon ?? '⚠' });
  }

  function info(message: string, icon?: string) {
    return show(message, 'info', { icon: icon ?? 'ℹ' });
  }

  // Game-specific toasts
  function blockMined(reward: number, isYou: boolean) {
    if (isYou) {
      return show(`+${reward.toFixed(4)} 💎`, 'success', {
        icon: '⛏️',
        duration: 6000,
      });
    }
  }

  function rigToggled(rigName: string, isActive: boolean) {
    const t = i18n.global.t;
    const translatedRigName = t(`data.rigs.${rigName}.name`);
    const message = isActive
      ? t('toast.rigActivated', { rigName: translatedRigName })
      : t('toast.rigDeactivated', { rigName: translatedRigName });
    return show(message, 'info', { icon: isActive ? '▶️' : '⏹️', duration: 2000, sound: false });
  }

  function quickTogglePenalty(temperature: number) {
    const t = i18n.global.t;
    return show(
      t('toast.rigQuickTogglePenalty', { temp: Math.round(temperature) }),
      'warning',
      { icon: '🔥', duration: 5000 }
    );
  }

  function purchaseSuccess(itemName: string) {
    const t = i18n.global.t;
    return show(t('toast.purchased', { item: itemName }), 'success', { icon: '🛒' });
  }

  function resourceLow(resource: 'energy' | 'internet', percent: number) {
    const t = i18n.global.t;
    const icon = resource === 'energy' ? '⚡' : '📡';
    const resourceName = resource === 'energy' ? t('nav.energy') : 'Internet';
    return show(t('toast.resourceLow', { resource: resourceName, percent }), 'warning', { icon });
  }

  function boostInstalled(boostName: string, rigName: string) {
    const t = i18n.global.t;
    return show(t('toast.boostActivated', { boost: boostName, rig: rigName }), 'success', {
      icon: '🚀',
      duration: 4000
    });
  }

  function boostExpired(boostName: string, rigName: string) {
    const t = i18n.global.t;
    return show(t('toast.boostExpired', { boost: boostName, rig: rigName }), 'warning', {
      icon: '⏱️',
      duration: 5000
    });
  }

  return {
    toasts,
    show,
    remove,
    clear,
    success,
    error,
    warning,
    info,
    blockMined,
    rigToggled,
    quickTogglePenalty,
    purchaseSuccess,
    resourceLow,
    boostInstalled,
    boostExpired,
  };
});
