<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { getActiveAnnouncements } from '@/utils/api'

const { t, locale } = useI18n()

interface Announcement {
  id: string
  message: string
  message_es?: string
  type: 'info' | 'warning' | 'success' | 'error' | 'maintenance' | 'update'
  icon: string
  link_url?: string
  link_text?: string
  priority: number
  starts_at: string
  ends_at?: string
}

const showModal = ref(false)
const updateAnnouncement = ref<Announcement | null>(null)
const dismissedId = ref<string | null>(null)
const autoRefreshCountdown = ref(0)
let checkInterval: number | null = null
let countdownInterval: number | null = null

const AUTO_REFRESH_DELAY = 30 // segundos antes de auto-refresh

const currentMessage = computed(() => {
  if (!updateAnnouncement.value) return ''
  return locale.value === 'es' && updateAnnouncement.value.message_es
    ? updateAnnouncement.value.message_es
    : updateAnnouncement.value.message
})

const progressWidth = computed(() => {
  if (autoRefreshCountdown.value === 0) return '0%'
  const percentage = ((AUTO_REFRESH_DELAY - autoRefreshCountdown.value) / AUTO_REFRESH_DELAY) * 100
  return `${percentage}%`
})

async function checkForUpdates() {
  try {
    const data = await getActiveAnnouncements()
    const updateAnnouncementData = (data ?? []).find((a: any) => a.type === 'update')

    if (updateAnnouncementData && updateAnnouncementData.id !== dismissedId.value) {
      updateAnnouncement.value = updateAnnouncementData
      showModal.value = true
      startAutoRefreshCountdown()
    } else if (!updateAnnouncementData && showModal.value) {
      // Anuncio de actualización fue removido/desactivado
      stopAutoRefreshCountdown()
      showModal.value = false
      updateAnnouncement.value = null
    }
  } catch (error) {
    console.error('Error checking for updates:', error)
  }
}

function refreshPage() {
  if (updateAnnouncement.value) {
    sessionStorage.setItem('update_dismissed', updateAnnouncement.value.id)
  }
  window.location.reload()
}

function dismissUpdate() {
  if (updateAnnouncement.value) {
    dismissedId.value = updateAnnouncement.value.id
    sessionStorage.setItem('update_dismissed', updateAnnouncement.value.id)
  }
  showModal.value = false
  stopAutoRefreshCountdown()
}

function startAutoRefreshCountdown() {
  stopAutoRefreshCountdown()
  autoRefreshCountdown.value = AUTO_REFRESH_DELAY

  countdownInterval = window.setInterval(() => {
    autoRefreshCountdown.value--
    if (autoRefreshCountdown.value <= 0) {
      stopAutoRefreshCountdown()
      refreshPage()
    }
  }, 1000)
}

function stopAutoRefreshCountdown() {
  if (countdownInterval !== null) {
    clearInterval(countdownInterval)
    countdownInterval = null
  }
  autoRefreshCountdown.value = 0
}

function startUpdateCheck() {
  // Check immediately
  checkForUpdates()

  // Check every 2 minutes
  checkInterval = window.setInterval(checkForUpdates, 2 * 60 * 1000)
}

function stopUpdateCheck() {
  if (checkInterval !== null) {
    clearInterval(checkInterval)
    checkInterval = null
  }
}

onMounted(() => {
  // Check if was dismissed in this session
  const dismissed = sessionStorage.getItem('update_dismissed')
  if (dismissed) {
    dismissedId.value = dismissed
  }

  startUpdateCheck()

  // Also check when window gains focus
  const handleVisibilityChange = () => {
    if (!document.hidden) {
      checkForUpdates()
    }
  }

  document.addEventListener('visibilitychange', handleVisibilityChange)

  onUnmounted(() => {
    stopUpdateCheck()
    stopAutoRefreshCountdown()
    document.removeEventListener('visibilitychange', handleVisibilityChange)
  })
})
</script>

<template>
  <Transition name="modal">
    <div v-if="showModal" class="modal-overlay">
      <div class="modal-container">
        <div class="modal-header">
          <div class="icon-container pulse">
            <span class="icon">{{ updateAnnouncement?.icon || '🔄' }}</span>
          </div>
          <h2 class="title">{{ t('update.available') }}</h2>
        </div>

        <div class="modal-body">
          <p class="message">{{ currentMessage }}</p>
          <p class="subtitle">{{ t('update.refreshPrompt') }}</p>
        </div>

        <div class="modal-footer">
          <button class="btn-secondary" @click="dismissUpdate">
            {{ t('update.later') }}
          </button>
          <button class="btn-primary" @click="refreshPage">
            <span class="refresh-icon">🔄</span>
            {{ t('update.refreshNow') }}
          </button>
        </div>

        <!-- Auto-refresh countdown -->
        <div v-if="autoRefreshCountdown > 0" class="auto-refresh-bar">
          <div class="countdown-text">
            {{ t('update.autoRefresh', { seconds: autoRefreshCountdown }) }}
          </div>
          <div class="progress-bar">
            <div class="progress-fill" :style="{ width: progressWidth }"></div>
          </div>
        </div>
      </div>
    </div>
  </Transition>
</template>

<style scoped>
.modal-overlay {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background: rgba(0, 0, 0, 0.85);
  backdrop-filter: blur(4px);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 10000;
  padding: 1rem;
}

.modal-container {
  background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
  border: 2px solid #00d4ff;
  border-radius: 16px;
  box-shadow: 0 20px 60px rgba(0, 212, 255, 0.3);
  max-width: 500px;
  width: 100%;
  animation: slideUp 0.3s ease-out;
}

.modal-header {
  text-align: center;
  padding: 2rem 2rem 1rem;
}

.icon-container {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 80px;
  height: 80px;
  background: linear-gradient(135deg, #00d4ff 0%, #0066ff 100%);
  border-radius: 50%;
  margin-bottom: 1rem;
  box-shadow: 0 8px 20px rgba(0, 212, 255, 0.4);
}

.icon {
  font-size: 3rem;
}

.pulse {
  animation: pulse 2s ease-in-out infinite;
}

.title {
  font-size: 1.75rem;
  font-weight: 700;
  color: #00d4ff;
  margin: 0;
  text-shadow: 0 0 20px rgba(0, 212, 255, 0.5);
}

.modal-body {
  padding: 1rem 2rem 1.5rem;
  text-align: center;
}

.message {
  font-size: 1.1rem;
  color: #fff;
  margin: 0 0 0.75rem;
  line-height: 1.5;
}

.subtitle {
  font-size: 0.9rem;
  color: #a0a0a0;
  margin: 0;
}

.modal-footer {
  display: flex;
  gap: 1rem;
  padding: 0 2rem 2rem;
}

.btn-primary,
.btn-secondary {
  flex: 1;
  padding: 0.875rem 1.5rem;
  border: none;
  border-radius: 8px;
  font-size: 1rem;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.3s ease;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 0.5rem;
}

.btn-primary {
  background: linear-gradient(135deg, #00d4ff 0%, #0066ff 100%);
  color: #fff;
  box-shadow: 0 4px 12px rgba(0, 212, 255, 0.4);
}

.btn-primary:hover {
  transform: translateY(-2px);
  box-shadow: 0 6px 16px rgba(0, 212, 255, 0.6);
}

.btn-primary:active {
  transform: translateY(0);
}

.btn-secondary {
  background: rgba(255, 255, 255, 0.1);
  color: #a0a0a0;
  border: 1px solid rgba(255, 255, 255, 0.2);
}

.btn-secondary:hover {
  background: rgba(255, 255, 255, 0.15);
  color: #fff;
}

.refresh-icon {
  animation: rotate 2s linear infinite;
}

.auto-refresh-bar {
  padding: 0 2rem 1.5rem;
}

.countdown-text {
  font-size: 0.85rem;
  color: #ffa500;
  text-align: center;
  margin-bottom: 0.5rem;
  font-weight: 600;
}

.progress-bar {
  height: 4px;
  background: rgba(255, 255, 255, 0.1);
  border-radius: 2px;
  overflow: hidden;
}

.progress-fill {
  height: 100%;
  background: linear-gradient(90deg, #00d4ff 0%, #0066ff 100%);
  transition: width 1s linear;
  box-shadow: 0 0 10px rgba(0, 212, 255, 0.6);
}

/* Animations */
@keyframes slideUp {
  from {
    opacity: 0;
    transform: translateY(30px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

@keyframes pulse {
  0%,
  100% {
    transform: scale(1);
  }
  50% {
    transform: scale(1.05);
  }
}

@keyframes rotate {
  from {
    transform: rotate(0deg);
  }
  to {
    transform: rotate(360deg);
  }
}

/* Transitions */
.modal-enter-active,
.modal-leave-active {
  transition: opacity 0.3s ease;
}

.modal-enter-from,
.modal-leave-to {
  opacity: 0;
}

.modal-enter-active .modal-container,
.modal-leave-active .modal-container {
  transition: transform 0.3s ease;
}

.modal-enter-from .modal-container,
.modal-leave-to .modal-container {
  transform: translateY(30px);
}

/* Responsive */
@media (max-width: 640px) {
  .modal-container {
    margin: 1rem;
  }

  .modal-header {
    padding: 1.5rem 1.5rem 1rem;
  }

  .icon-container {
    width: 64px;
    height: 64px;
  }

  .icon {
    font-size: 2.5rem;
  }

  .title {
    font-size: 1.5rem;
  }

  .modal-body {
    padding: 1rem 1.5rem;
  }

  .message {
    font-size: 1rem;
  }

  .modal-footer {
    flex-direction: column;
    padding: 0 1.5rem 1.5rem;
  }

  .btn-primary,
  .btn-secondary {
    width: 100%;
  }
}
</style>
