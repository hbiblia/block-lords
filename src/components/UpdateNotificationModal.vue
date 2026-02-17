<script setup lang="ts">
import { ref, computed, watch, onMounted, onUnmounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute } from 'vue-router'
import { getActiveAnnouncements, connectionState } from '@/utils/api'
import { playSound } from '@/utils/sounds'
import { useAuthStore } from '@/stores/auth'

const { t, locale } = useI18n()
const route = useRoute()
const authStore = useAuthStore()

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

const showToast = ref(false)
const updateAnnouncement = ref<Announcement | null>(null)
const dismissedId = ref<string | null>(null)
let checkInterval: number | null = null
const appLoadedAt = Date.now()

const isMiningPage = computed(() => route.path === '/mining')

watch(showToast, (show) => {
  if (show && isMiningPage.value) playSound('notification');
})

const currentMessage = computed(() => {
  if (!updateAnnouncement.value) return ''
  return locale.value === 'es' && updateAnnouncement.value.message_es
    ? updateAnnouncement.value.message_es
    : updateAnnouncement.value.message
})

async function checkForUpdates() {
  // No verificar si la conexión ya está fallando (evita pile-up de requests)
  if (!connectionState.isOnline) return
  // Solo verificar si el usuario está autenticado
  if (!authStore.isAuthenticated) return
  // Si el UpdateModal (changelog) aún no fue descartado, no mostrar este toast.
  // Cuando el usuario cierra el UpdateModal, guarda la versión en localStorage.
  // Si no existe valor o no coincide, significa que el UpdateModal va a mostrarse primero.
  const lastSeen = localStorage.getItem('lootmine-last-seen-version')
  if (!lastSeen) return
  try {
    const data = await getActiveAnnouncements()
    const updateAnnouncementData = (data ?? []).find((a: any) => a.type === 'update')

    // Ignorar actualizaciones anteriores a la carga de la página (ya las tenemos)
    if (updateAnnouncementData) {
      const announcementTime = new Date(updateAnnouncementData.starts_at).getTime()
      // Si el anuncio es anterior a cuando cargamos la app, asumimos que ya tenemos esa versión
      if (announcementTime <= appLoadedAt) {
        return
      }
    }

    if (updateAnnouncementData && updateAnnouncementData.id !== dismissedId.value) {
      updateAnnouncement.value = updateAnnouncementData
      showToast.value = true
    } else if (!updateAnnouncementData && showToast.value) {
      showToast.value = false
      updateAnnouncement.value = null
    }
  } catch (error) {
    console.error('Error checking for updates:', error)
  }
}

function refreshPage() {
  if (updateAnnouncement.value) {
    localStorage.setItem('update_dismissed', updateAnnouncement.value.id)
  }
  window.location.reload()
}

function startUpdateCheck() {
  // No verificar inmediatamente: si acabas de cargar/refrescar ya tienes el código más reciente.
  // Esperar 2 minutos antes del primer check para solo notificar a quienes llevan rato en la app.
  checkInterval = window.setTimeout(() => {
    checkForUpdates()
    checkInterval = window.setInterval(checkForUpdates, 2 * 60 * 1000)
  }, 2 * 60 * 1000)
}

function stopUpdateCheck() {
  if (checkInterval !== null) {
    clearInterval(checkInterval)
    clearTimeout(checkInterval)
    checkInterval = null
  }
}

onMounted(() => {
  const dismissed = localStorage.getItem('update_dismissed')
  if (dismissed) {
    dismissedId.value = dismissed
  }

  startUpdateCheck()

  // No verificar en visibility change si acaba de cargar
  const handleVisibilityChange = () => {
    if (!document.hidden && authStore.isAuthenticated && (Date.now() - appLoadedAt > 2 * 60 * 1000)) {
      checkForUpdates()
    }
  }

  document.addEventListener('visibilitychange', handleVisibilityChange)

  onUnmounted(() => {
    stopUpdateCheck()
    document.removeEventListener('visibilitychange', handleVisibilityChange)
  })
})
</script>

<template>
  <Teleport to="body">
    <Transition name="toast">
      <div
        v-if="(showToast && isMiningPage)"
        class="fixed bottom-20 left-1/2 -translate-x-1/2 z-[9999] w-[calc(100%-2rem)] max-w-sm"
      >
        <div class="relative overflow-hidden rounded-xl bg-slate-900/95 border border-emerald-500/30 shadow-lg shadow-emerald-500/10 backdrop-blur-sm">
          <!-- Barra de acento superior -->
          <div class="absolute top-0 left-0 right-0 h-[2px] bg-gradient-to-r from-emerald-400 via-cyan-400 to-emerald-400 animate-shimmer"></div>

          <div class="flex items-center gap-3 px-4 py-3">
            <!-- Icono con pulso -->
            <div class="relative flex-shrink-0">
              <span class="text-lg">{{ updateAnnouncement?.icon || '🚀' }}</span>
              <span class="absolute -top-0.5 -right-0.5 w-2 h-2 rounded-full bg-emerald-400 animate-pulse"></span>
            </div>

            <!-- Mensaje -->
            <div class="flex-1 min-w-0">
              <p class="text-[11px] font-bold text-emerald-300/60 uppercase tracking-wider mb-0.5">{{ t('update.title', 'Update') }}</p>
              <p class="text-xs font-semibold text-white/90 truncate">{{ currentMessage || t('update.defaultMessage', 'New update available!') }}</p>
            </div>

            <!-- Botón actualizar -->
            <button
              @click="refreshPage"
              class="flex-shrink-0 px-3 py-1.5 rounded-lg text-[11px] font-bold bg-emerald-500/20 text-emerald-300 hover:bg-emerald-500/30 border border-emerald-500/20 hover:border-emerald-500/40 transition-all"
            >
              {{ t('update.refreshNow') }}
            </button>
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
@keyframes shimmer {
  0% { background-position: -200% 0; }
  100% { background-position: 200% 0; }
}

.animate-shimmer {
  background-size: 200% 100%;
  animation: shimmer 3s linear infinite;
}

.toast-enter-active {
  transition: all 0.3s ease-out;
}

.toast-leave-active {
  transition: all 0.2s ease-in;
}

.toast-enter-from {
  opacity: 0;
  transform: translate(-50%, 20px);
}

.toast-leave-to {
  opacity: 0;
  transform: translate(-50%, 20px);
}
</style>
