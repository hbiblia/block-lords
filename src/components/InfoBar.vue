<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted, watch, inject, type Ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { getActiveAnnouncements } from '@/utils/api';

const { locale } = useI18n();

// Inject visibility ref from layout to communicate when InfoBar is visible
const infoBarVisible = inject<Ref<boolean>>('infoBarVisible', ref(false));

interface Announcement {
  id: string;
  message: string;
  message_es?: string;
  type: 'info' | 'warning' | 'success' | 'error' | 'maintenance' | 'update';
  icon: string;
  link_url?: string;
  link_text?: string;
  priority: number;
  starts_at: string;
  ends_at?: string;
}

const announcements = ref<Announcement[]>([]);
const currentIndex = ref(0);
const loading = ref(true);
const dismissed = ref(false);
const dismissedIds = ref<Set<string>>(new Set());

// Auto-rotate announcements
let rotateInterval: number | null = null;

// Throttle announcement reloading (max once per minute)
let lastAnnouncementCheck = 0;
const ANNOUNCEMENT_CHECK_INTERVAL = 60000; // 1 minute

const currentAnnouncement = computed(() => {
  const visible = announcements.value.filter(a => !dismissedIds.value.has(a.id));
  if (visible.length === 0) return null;
  return visible[currentIndex.value % visible.length];
});

const visibleCount = computed(() => {
  return announcements.value.filter(a => !dismissedIds.value.has(a.id)).length;
});

const displayMessage = computed(() => {
  if (!currentAnnouncement.value) return '';
  // Use Spanish message if available and locale is Spanish
  if (locale.value === 'es' && currentAnnouncement.value.message_es) {
    return currentAnnouncement.value.message_es;
  }
  return currentAnnouncement.value.message;
});

const typeClasses = computed(() => {
  if (!currentAnnouncement.value) return {};
  const type = currentAnnouncement.value.type;
  return {
    'bg-accent-primary/10 border-accent-primary/30 text-accent-primary': type === 'info',
    'bg-status-warning/10 border-status-warning/30 text-status-warning': type === 'warning',
    'bg-status-success/10 border-status-success/30 text-status-success': type === 'success',
    'bg-status-danger/10 border-status-danger/30 text-status-danger': type === 'error',
    'bg-amber-500/10 border-amber-500/30 text-amber-400': type === 'maintenance',
  };
});

async function loadAnnouncements() {
  try {
    const data = await getActiveAnnouncements();
    // Filter out 'update' type announcements (they are shown in UpdateNotificationModal)
    announcements.value = (data ?? []).filter((a: any) => a.type !== 'update');
  } catch (e) {
    console.error('Error loading announcements:', e);
    announcements.value = [];
  } finally {
    loading.value = false;
  }
}

function startRotation() {
  if (rotateInterval) clearInterval(rotateInterval);
  rotateInterval = window.setInterval(() => {
    if (visibleCount.value > 1) {
      currentIndex.value = (currentIndex.value + 1) % visibleCount.value;
    }
  }, 8000); // Rotate every 8 seconds
}

function stopRotation() {
  if (rotateInterval) {
    clearInterval(rotateInterval);
    rotateInterval = null;
  }
}

function dismissCurrent() {
  if (currentAnnouncement.value) {
    dismissedIds.value.add(currentAnnouncement.value.id);
    // Store in sessionStorage so it persists during session
    sessionStorage.setItem('dismissedAnnouncements', JSON.stringify([...dismissedIds.value]));
  }
}

function dismissAll() {
  dismissed.value = true;
  sessionStorage.setItem('allAnnouncementsDismissed', 'true');
}

function goToNext() {
  if (visibleCount.value > 1) {
    currentIndex.value = (currentIndex.value + 1) % visibleCount.value;
  }
}

function goToPrev() {
  if (visibleCount.value > 1) {
    currentIndex.value = (currentIndex.value - 1 + visibleCount.value) % visibleCount.value;
  }
}

// Update layout visibility when our state changes
watch(
  [loading, dismissed, currentAnnouncement],
  () => {
    infoBarVisible.value = !loading.value && !dismissed.value && currentAnnouncement.value !== null;
  },
  { immediate: true }
);

// Event listener for player updates (indicates tick occurred)
function handlePlayerUpdate() {
  const now = Date.now();
  if (now - lastAnnouncementCheck >= ANNOUNCEMENT_CHECK_INTERVAL) {
    lastAnnouncementCheck = now;
    loadAnnouncements();
  }
}

onMounted(() => {
  // Check if all announcements were dismissed this session
  if (sessionStorage.getItem('allAnnouncementsDismissed') === 'true') {
    dismissed.value = true;
    loading.value = false;
    return;
  }

  // Load previously dismissed IDs
  const storedDismissed = sessionStorage.getItem('dismissedAnnouncements');
  if (storedDismissed) {
    dismissedIds.value = new Set(JSON.parse(storedDismissed));
  }

  loadAnnouncements();
  startRotation();

  // Listen for player updates (tick events)
  window.addEventListener('player-rigs-updated', handlePlayerUpdate as EventListener);
});

onUnmounted(() => {
  stopRotation();
  window.removeEventListener('player-rigs-updated', handlePlayerUpdate as EventListener);
});
</script>

<template>
  <Transition name="slide">
    <div
      v-if="!loading && !dismissed && currentAnnouncement"
      class="fixed top-0 left-0 right-0 z-[60] border-b transition-all duration-300"
      :class="typeClasses"
    >
      <div class="container mx-auto px-4">
        <div class="flex items-center justify-between h-10 gap-4">
          <!-- Navigation (multiple announcements) -->
          <div v-if="visibleCount > 1" class="flex items-center gap-1">
            <button
              @click="goToPrev"
              class="p-1 rounded hover:bg-white/10 transition-colors"
            >
              <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
              </svg>
            </button>
            <span class="text-xs opacity-70 min-w-[3ch] text-center">
              {{ (currentIndex % visibleCount) + 1 }}/{{ visibleCount }}
            </span>
            <button
              @click="goToNext"
              class="p-1 rounded hover:bg-white/10 transition-colors"
            >
              <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
              </svg>
            </button>
          </div>

          <!-- Message -->
          <div class="flex-1 flex items-center justify-center gap-2 text-sm font-medium truncate">
            <span class="shrink-0">{{ currentAnnouncement.icon }}</span>
            <span class="truncate">{{ displayMessage }}</span>
            <a
              v-if="currentAnnouncement.link_url"
              :href="currentAnnouncement.link_url"
              target="_blank"
              rel="noopener noreferrer"
              class="shrink-0 underline hover:no-underline opacity-80 hover:opacity-100"
            >
              {{ currentAnnouncement.link_text || 'Learn more' }}
            </a>
          </div>

          <!-- Close buttons -->
          <div class="flex items-center gap-1">
            <!-- Dismiss this announcement -->
            <button
              v-if="visibleCount > 1"
              @click="dismissCurrent"
              class="p-1 rounded hover:bg-white/10 transition-colors opacity-60 hover:opacity-100"
              title="Dismiss this"
            >
              <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13.875 18.825A10.05 10.05 0 0112 19c-4.478 0-8.268-2.943-9.543-7a9.97 9.97 0 011.563-3.029m5.858.908a3 3 0 114.243 4.243M9.878 9.878l4.242 4.242M9.878 9.878L6.758 6.758M9.878 9.878l4.242 4.242m4.242 4.242L21 21M9.878 9.878L3 3" />
              </svg>
            </button>
            <!-- Close all -->
            <button
              @click="dismissAll"
              class="p-1 rounded hover:bg-white/10 transition-colors opacity-60 hover:opacity-100"
              title="Close"
            >
              <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>
        </div>
      </div>
    </div>
  </Transition>
</template>

<style scoped>
.slide-enter-active,
.slide-leave-active {
  transition: transform 0.3s ease, opacity 0.3s ease;
}

.slide-enter-from,
.slide-leave-to {
  transform: translateY(-100%);
  opacity: 0;
}
</style>
