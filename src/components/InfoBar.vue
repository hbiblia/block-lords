<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted, watch, inject, type Ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { getActiveAnnouncements } from '@/utils/api';
import { ChevronLeft, ChevronRight, EyeOff, X } from 'lucide-vue-next';

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

// Periodic announcement check
let announcementCheckInterval: number | null = null;

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

  // Check for new announcements periodically
  announcementCheckInterval = window.setInterval(loadAnnouncements, ANNOUNCEMENT_CHECK_INTERVAL);
});

onUnmounted(() => {
  stopRotation();
  if (announcementCheckInterval) { clearInterval(announcementCheckInterval); announcementCheckInterval = null; }
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
              <ChevronLeft :size="16" />
            </button>
            <span class="text-xs opacity-70 min-w-[3ch] text-center">
              {{ (currentIndex % visibleCount) + 1 }}/{{ visibleCount }}
            </span>
            <button
              @click="goToNext"
              class="p-1 rounded hover:bg-white/10 transition-colors"
            >
              <ChevronRight :size="16" />
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
              <EyeOff :size="16" />
            </button>
            <!-- Close all -->
            <button
              @click="dismissAll"
              class="p-1 rounded hover:bg-white/10 transition-colors opacity-60 hover:opacity-100"
              title="Close"
            >
              <X :size="16" />
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
