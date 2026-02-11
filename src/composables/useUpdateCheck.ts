import { ref, onMounted, onUnmounted } from 'vue'

const UPDATE_CHECK_INTERVAL = 5 * 60 * 1000 // 5 minutos
const BUILD_TIMESTAMP_KEY = 'app_build_timestamp'

export function useUpdateCheck() {
  const updateAvailable = ref(false)
  const checking = ref(false)
  let checkInterval: number | null = null

  // Obtener timestamp del build actual desde el HTML
  const getCurrentBuildTimestamp = (): string | null => {
    const metaTag = document.querySelector('meta[name="build-timestamp"]')
    return metaTag?.getAttribute('content') || null
  }

  // Verificar si hay actualización disponible
  const checkForUpdates = async () => {
    if (checking.value) return

    checking.value = true
    try {
      // Obtener el timestamp del build almacenado
      const storedTimestamp = localStorage.getItem(BUILD_TIMESTAMP_KEY)

      // Si no hay timestamp almacenado, guardarlo y continuar
      if (!storedTimestamp) {
        const currentTimestamp = getCurrentBuildTimestamp() || Date.now().toString()
        localStorage.setItem(BUILD_TIMESTAMP_KEY, currentTimestamp)
        checking.value = false
        return
      }

      // Hacer fetch del index.html con cache-busting
      const response = await fetch(`/index.html?t=${Date.now()}`, {
        method: 'HEAD',
        cache: 'no-cache',
      })

      // Verificar si el ETag o Last-Modified cambió
      const etag = response.headers.get('ETag')
      const lastModified = response.headers.get('Last-Modified')

      const storedEtag = localStorage.getItem('app_etag')
      const storedLastModified = localStorage.getItem('app_last_modified')

      // Si hay cambios, marcar actualización disponible
      if (
        (etag && etag !== storedEtag) ||
        (lastModified && lastModified !== storedLastModified)
      ) {
        updateAvailable.value = true

        // Almacenar nuevos valores para la próxima verificación
        if (etag) localStorage.setItem('app_etag', etag)
        if (lastModified) localStorage.setItem('app_last_modified', lastModified)
      }
    } catch (error) {
      console.error('Error checking for updates:', error)
    } finally {
      checking.value = false
    }
  }

  // Refrescar la página
  const applyUpdate = () => {
    // Limpiar storage para forzar recarga completa
    const currentTimestamp = getCurrentBuildTimestamp() || Date.now().toString()
    localStorage.setItem(BUILD_TIMESTAMP_KEY, currentTimestamp)

    // Recargar la página sin caché
    window.location.reload()
  }

  // Iniciar verificación periódica
  const startUpdateCheck = () => {
    // Verificar inmediatamente
    checkForUpdates()

    // Configurar verificación periódica
    checkInterval = window.setInterval(checkForUpdates, UPDATE_CHECK_INTERVAL)
  }

  // Detener verificación periódica
  const stopUpdateCheck = () => {
    if (checkInterval !== null) {
      clearInterval(checkInterval)
      checkInterval = null
    }
  }

  // Lifecycle
  onMounted(() => {
    startUpdateCheck()

    // También verificar cuando la ventana vuelve a tener foco
    const handleVisibilityChange = () => {
      if (!document.hidden) {
        checkForUpdates()
      }
    }

    document.addEventListener('visibilitychange', handleVisibilityChange)

    // Cleanup
    onUnmounted(() => {
      stopUpdateCheck()
      document.removeEventListener('visibilitychange', handleVisibilityChange)
    })
  })

  return {
    updateAvailable,
    checking,
    checkForUpdates,
    applyUpdate,
  }
}
