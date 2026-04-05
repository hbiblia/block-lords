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
    'infobar-info': type === 'info',
    'infobar-warning': type === 'warning',
    'infobar-success': type === 'success',
    'infobar-error': type === 'error',
    'infobar-maintenance': type === 'maintenance',
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
      class="infobar-root"
      :class="typeClasses"
    >
      <div class="infobar-inner">
        <div class="infobar-content">
          <!-- Navigation (multiple announcements) -->
          <div v-if="visibleCount > 1" class="infobar-nav">
            <button @click="goToPrev" class="infobar-nav-btn">
              <ChevronLeft :size="14" />
            </button>
            <span class="infobar-counter">
              {{ (currentIndex % visibleCount) + 1 }}/{{ visibleCount }}
            </span>
            <button @click="goToNext" class="infobar-nav-btn">
              <ChevronRight :size="14" />
            </button>
          </div>

          <!-- Message -->
          <div class="infobar-message">
            <span class="infobar-icon">{{ currentAnnouncement.icon }}</span>
            <span class="infobar-text">{{ displayMessage }}</span>
            <a
              v-if="currentAnnouncement.link_url"
              :href="currentAnnouncement.link_url"
              target="_blank"
              rel="noopener noreferrer"
              class="infobar-link"
            >
              {{ currentAnnouncement.link_text || 'Learn more' }}
            </a>
          </div>

          <!-- Close buttons -->
          <div class="infobar-actions">
            <button
              v-if="visibleCount > 1"
              @click="dismissCurrent"
              class="infobar-close-btn"
              title="Dismiss this"
            >
              <EyeOff :size="14" />
            </button>
            <button
              @click="dismissAll"
              class="infobar-close-btn"
              title="Close"
            >
              <X :size="14" />
            </button>
          </div>
        </div>
      </div>
    </div>
  </Transition>
</template>

<style scoped>
.infobar-root {
  position: fixed; top: 0; left: 0; right: 0; z-index: 60;
  border-bottom: 2px solid #c4a0e8;
  transition: all 0.3s;
  font-family: 'Nunito', 'Trebuchet MS', sans-serif;
}
.infobar-inner {
  max-width: 1280px; margin: 0 auto; padding: 0 1rem;
}
.infobar-content {
  display: flex; align-items: center; justify-content: space-between;
  height: 36px; gap: 0.8rem;
}
.infobar-nav {
  display: flex; align-items: center; gap: 4px;
}
.infobar-nav-btn {
  padding: 2px; border-radius: 4px; background: none; border: none;
  color: inherit; cursor: pointer; opacity: 0.7; transition: 0.2s;
}
.infobar-nav-btn:hover { opacity: 1; }
.infobar-counter {
  font-size: 0.6rem; font-weight: 800; opacity: 0.7; min-width: 3ch; text-align: center;
}
.infobar-message {
  flex: 1; display: flex; align-items: center; justify-content: center;
  gap: 6px; font-size: 0.75rem; font-weight: 700; overflow: hidden;
  letter-spacing: 0.5px;
}
.infobar-icon { flex-shrink: 0; }
.infobar-text { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.infobar-link {
  flex-shrink: 0; text-decoration: underline; opacity: 0.8; transition: 0.2s;
}
.infobar-link:hover { opacity: 1; text-decoration: none; }
.infobar-actions {
  display: flex; align-items: center; gap: 4px;
}
.infobar-close-btn {
  padding: 3px; border-radius: 4px; background: none; border: none;
  color: inherit; cursor: pointer; opacity: 0.5; transition: 0.2s;
}
.infobar-close-btn:hover { opacity: 1; }

/* Type variants */
.infobar-info {
  background: #f0e4ff; border-color: #c4a0e8; color: #7b5ea7;
}
.infobar-warning {
  background: #fff8e0; border-color: #e8c840; color: #8a6a10;
}
.infobar-success {
  background: #e8f8ec; border-color: #a8d0b8; color: #3a7a4a;
}
.infobar-error {
  background: #fff0f0; border-color: #ff7b7b; color: #c04040;
}
.infobar-maintenance {
  background: #fff8e0; border-color: #d4a017; color: #8a6a10;
}

/* Transitions */
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
