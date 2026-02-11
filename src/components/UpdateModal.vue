<script setup lang="ts">
import { ref, onMounted, watch } from 'vue';

// Versión actual de la app (actualizar esto cuando haya cambios importantes)
const CURRENT_VERSION = '1.2.0';
const STORAGE_KEY = 'block-lords-last-seen-version';

const showModal = ref(false);

onMounted(() => {
  const lastSeenVersion = localStorage.getItem(STORAGE_KEY);

  // Si nunca vio ninguna versión o la versión cambió, mostrar el modal
  if (!lastSeenVersion || lastSeenVersion !== CURRENT_VERSION) {
    showModal.value = true;
  }
});

// Prevenir scroll del body cuando el modal está abierto
watch(showModal, (isOpen) => {
  if (isOpen) {
    document.body.style.overflow = 'hidden';
  } else {
    document.body.style.overflow = '';
  }
});

function closeModal() {
  // Guardar la versión actual como vista
  localStorage.setItem(STORAGE_KEY, CURRENT_VERSION);
  showModal.value = false;
}
</script>

<template>
  <!-- Modal overlay -->
  <Transition name="fade">
    <div
      v-if="showModal"
      class="fixed inset-0 z-[150] bg-black/50 backdrop-blur-sm flex items-center justify-center p-4"
      @click.self="closeModal"
    >
      <!-- Modal content -->
      <div class="card p-6 max-w-lg w-full border border-border/50 shadow-2xl relative animate-scale-in flex flex-col max-h-[85vh]">
        <!-- Header -->
        <div class="flex items-start justify-between mb-4 flex-shrink-0">
          <div class="flex items-center gap-3">
            <div class="w-10 h-10 rounded-xl bg-gradient-primary flex items-center justify-center text-xl">
              ✨
            </div>
            <div>
              <h2 class="text-xl font-bold text-text-primary">¡Nueva Actualización!</h2>
              <p class="text-xs text-text-muted">Versión {{ CURRENT_VERSION }}</p>
            </div>
          </div>
        </div>

        <!-- Contenido scrollable -->
        <div class="space-y-4 overflow-y-auto flex-1 pr-2 custom-scrollbar">
          <!-- Recompensas de bloques -->
          <div class="p-3 bg-gradient-to-r from-amber-500/20 to-yellow-500/20 border border-amber-500/30 rounded-lg">
            <h3 class="text-lg font-bold text-text-primary mb-2 flex items-center gap-2">
              💰 Recompensas de Bloques Aumentadas
            </h3>
            <p class="text-text-secondary text-sm mb-2">
              Las recompensas por bloque han sido <strong class="text-amber-400">duplicadas</strong>:
            </p>
            <ul class="space-y-2 text-sm">
              <li class="flex items-start gap-2 text-text-secondary">
                <span class="text-amber-400 mt-0.5">🥉</span>
                <span><strong>Bronze:</strong> 2,000 BLC</span>
              </li>
              <li class="flex items-start gap-2 text-text-secondary">
                <span class="text-gray-300 mt-0.5">🥈</span>
                <span><strong>Silver:</strong> 3,000 BLC</span>
              </li>
              <li class="flex items-start gap-2 text-text-secondary">
                <span class="text-yellow-400 mt-0.5">🥇</span>
                <span><strong>Gold:</strong> 5,000 BLC</span>
              </li>
            </ul>
            <p class="text-text-secondary text-sm mt-3">
              <strong class="text-accent-primary">Probabilidades dinámicas:</strong> Mientras más mineros activos haya en la red, mayor será la probabilidad de que aparezcan bloques Silver y Gold.
            </p>
          </div>

          <!-- Misiones -->
          <div>
            <h3 class="text-base font-semibold text-text-primary mb-2 flex items-center gap-2">
              🎯 Correcciones de Misiones
            </h3>
            <ul class="space-y-2">
              <li class="flex items-start gap-2 text-text-secondary">
                <span class="text-green-500 mt-1">✓</span>
                <span><strong>Objetivos ajustados:</strong> Misiones de bloques adaptadas al sistema actual (máx 48 bloques/día)</span>
              </li>
              <li class="flex items-start gap-2 text-text-secondary">
                <span class="text-green-500 mt-1">✓</span>
                <span><strong>Misiones semanales:</strong> Ahora se trackean correctamente (bloques, tiempo online, BLC, trades)</span>
              </li>
              <li class="flex items-start gap-2 text-text-secondary">
                <span class="text-green-500 mt-1">✓</span>
                <span><strong>Nuevas misiones:</strong> Reparar rigs, usar boosts, instalar cooling, mejora máxima y más</span>
              </li>
            </ul>
          </div>

          <!-- Mejoras de Rigs -->
          <div>
            <h3 class="text-base font-semibold text-text-primary mb-2 flex items-center gap-2">
              ⬆️ Correcciones de Mejoras de Rigs
            </h3>
            <ul class="space-y-2">
              <li class="flex items-start gap-2 text-text-secondary">
                <span class="text-green-500 mt-1">✓</span>
                <span><strong>Hashrate, Eficiencia y Térmica</strong> ahora se reflejan correctamente en la interfaz</span>
              </li>
              <li class="flex items-start gap-2 text-text-secondary">
                <span class="text-green-500 mt-1">✓</span>
                <span><strong>Valores corregidos:</strong> Los bonus de mejora ahora coinciden con el servidor (ej: Lv5 = +100% hashrate)</span>
              </li>
              <li class="flex items-start gap-2 text-text-secondary">
                <span class="text-green-500 mt-1">✓</span>
                <span><strong>Consumo real:</strong> Energía e internet ahora muestran la reducción por mejora de eficiencia</span>
              </li>
              <li class="flex items-start gap-2 text-text-secondary">
                <span class="text-green-500 mt-1">✓</span>
                <span><strong>Penalización de temperatura:</strong> Corregida para coincidir con el cálculo del servidor (>50°C)</span>
              </li>
            </ul>
          </div>

        </div>

        <!-- Footer con botón -->
        <div class="flex justify-end mt-4 pt-4 border-t border-border/30 flex-shrink-0">
          <button
            @click="closeModal"
            class="btn btn-primary px-6 py-2 font-semibold"
          >
            ¡Entendido! 🚀
          </button>
        </div>
      </div>
    </div>
  </Transition>
</template>

<style scoped>
/* Fade transition */
.fade-enter-active,
.fade-leave-active {
  transition: opacity 0.3s ease;
}

.fade-enter-from,
.fade-leave-to {
  opacity: 0;
}

/* Scale in animation para el modal */
@keyframes scale-in {
  from {
    opacity: 0;
    transform: scale(0.9);
  }
  to {
    opacity: 1;
    transform: scale(1);
  }
}

.animate-scale-in {
  animation: scale-in 0.3s ease-out;
}

/* Custom scrollbar */
.custom-scrollbar::-webkit-scrollbar {
  width: 8px;
}

.custom-scrollbar::-webkit-scrollbar-track {
  background: rgba(255, 255, 255, 0.05);
  border-radius: 4px;
}

.custom-scrollbar::-webkit-scrollbar-thumb {
  background: rgba(139, 92, 246, 0.3);
  border-radius: 4px;
}

.custom-scrollbar::-webkit-scrollbar-thumb:hover {
  background: rgba(139, 92, 246, 0.5);
}
</style>
