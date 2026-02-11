import { ref, onMounted, onUnmounted } from 'vue';

// Exported so stores/components can check and skip DB calls when locked
export const isTabLocked = ref(false);

const TAB_KEY = 'bl_active_tab';
const TAB_HEARTBEAT_KEY = 'bl_tab_heartbeat';
const HEARTBEAT_INTERVAL = 3000; // 3s
const HEARTBEAT_TIMEOUT = 8000;  // 8s — no heartbeat = tab is dead

// Fresh random ID on every page load — this is intentional.
// sessionStorage is cloned when duplicating a tab, so we can't use it.
// With a fresh ID each load, duplicates always get a different ID from the original.
const MY_TAB_ID = Date.now().toString(36) + Math.random().toString(36).slice(2, 9);

export function useTabLock() {
  const isSuperseded = ref(false);
  let heartbeatTimer: number | null = null;
  let supersededCheckTimer: number | null = null;

  function sendHeartbeat() {
    localStorage.setItem(TAB_HEARTBEAT_KEY, JSON.stringify({
      tabId: MY_TAB_ID,
      ts: Date.now(),
    }));
  }

  function isActiveTabAlive(): boolean {
    const activeId = localStorage.getItem(TAB_KEY);
    if (!activeId) return false;

    try {
      const hb = localStorage.getItem(TAB_HEARTBEAT_KEY);
      if (hb) {
        const { tabId, ts } = JSON.parse(hb);
        if (tabId === activeId && Date.now() - ts < HEARTBEAT_TIMEOUT) {
          return true;
        }
      }
    } catch { /* ignore */ }

    return false;
  }

  function releaseTab() {
    if (localStorage.getItem(TAB_KEY) === MY_TAB_ID) {
      localStorage.removeItem(TAB_KEY);
    }
  }

  function startHeartbeat() {
    if (!heartbeatTimer) {
      heartbeatTimer = setInterval(sendHeartbeat, HEARTBEAT_INTERVAL) as unknown as number;
    }
  }

  function stopHeartbeat() {
    if (heartbeatTimer) {
      clearInterval(heartbeatTimer);
      heartbeatTimer = null;
    }
  }

  function claimTab() {
    if (supersededCheckTimer) {
      clearInterval(supersededCheckTimer);
      supersededCheckTimer = null;
    }
    localStorage.setItem(TAB_KEY, MY_TAB_ID);
    sendHeartbeat();
    startHeartbeat();
    isSuperseded.value = false;
    isTabLocked.value = false;
  }

  function handleStorageChange(e: StorageEvent) {
    if (e.key === TAB_KEY && e.newValue !== null && e.newValue !== MY_TAB_ID) {
      isSuperseded.value = true;
      isTabLocked.value = true;
      // Stop heartbeats — superseded tabs must not overwrite the active tab's heartbeat
      stopHeartbeat();
    }
  }

  onMounted(() => {
    if (isActiveTabAlive()) {
      // Another tab is active — show overlay (don't send heartbeats)
      isSuperseded.value = true;
      isTabLocked.value = true;

      // Auto-unblock if the original tab closes without user action
      supersededCheckTimer = setInterval(() => {
        if (!isActiveTabAlive()) {
          claimTab();
        }
      }, HEARTBEAT_INTERVAL + 1000) as unknown as number;
    } else {
      claimTab();
    }

    window.addEventListener('storage', handleStorageChange);
    // Release claim on page close/refresh so new tabs don't see a stale claim
    window.addEventListener('beforeunload', releaseTab);
  });

  onUnmounted(() => {
    stopHeartbeat();
    if (supersededCheckTimer) clearInterval(supersededCheckTimer);
    window.removeEventListener('storage', handleStorageChange);
    window.removeEventListener('beforeunload', releaseTab);
    releaseTab();
  });

  return { isSuperseded, claimTab };
}
