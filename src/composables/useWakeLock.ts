import { ref } from 'vue';

const wakeLock = ref<WakeLockSentinel | null>(null);
const isSupported = ref(false);
const isActive = ref(false);

// Check if Wake Lock API is supported
if (typeof navigator !== 'undefined' && 'wakeLock' in navigator) {
  isSupported.value = true;
}

export function useWakeLock() {
  async function requestWakeLock() {
    if (!isSupported.value) {
      return false;
    }

    // Can only request Wake Lock when page is visible
    if (document.visibilityState !== 'visible') {
      return false;
    }

    try {
      wakeLock.value = await navigator.wakeLock.request('screen');
      isActive.value = true;

      // Listen for release event
      wakeLock.value.addEventListener('release', () => {
        isActive.value = false;
      });

      return true;
    } catch (err) {
      isActive.value = false;
      return false;
    }
  }

  async function releaseWakeLock() {
    if (wakeLock.value) {
      try {
        await wakeLock.value.release();
        wakeLock.value = null;
        isActive.value = false;
      } catch {
        // Silent fail
      }
    }
  }

  // Auto-reacquire on visibility change if needed
  async function enableAutoReacquire() {
    document.addEventListener('visibilitychange', async () => {
      if (document.visibilityState === 'visible' && isActive.value === false) {
        // Re-acquire if the page becomes visible and we had a lock before
        await requestWakeLock();
      }
    });
  }

  return {
    isSupported,
    isActive,
    requestWakeLock,
    releaseWakeLock,
    enableAutoReacquire,
  };
}
