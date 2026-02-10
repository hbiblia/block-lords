<script setup lang="ts">
import { ref, onMounted, watch } from 'vue';

// Versión actual de la app (actualizar esto cuando haya cambios importantes)
const CURRENT_VERSION = '1.1.1';
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
          <!-- Sistema principal -->
          <div class="p-3 bg-gradient-to-r from-accent-primary/20 to-purple-500/20 border border-accent-primary/30 rounded-lg">
            <h3 class="text-lg font-bold text-text-primary mb-2 flex items-center gap-2">
              ⏰ Nuevo Sistema de Minería por Tiempo
            </h3>
            <p class="text-text-secondary text-sm mb-2">
              ¡El sistema de minería ha sido completamente renovado! Ahora la minería funciona con bloques de <strong class="text-accent-primary">30 minutos de duración fija</strong>.
            </p>
            <ul class="space-y-2 text-sm">
              <li class="flex items-start gap-2 text-text-secondary">
                <span class="text-accent-primary mt-0.5">⭐</span>
                <span><strong>Bloques garantizados:</strong> Cada 30 minutos se cierra un bloque sin importar la actividad</span>
              </li>
              <li class="flex items-start gap-2 text-text-secondary">
                <span class="text-accent-primary mt-0.5">⭐</span>
                <span><strong>Sistema de shares:</strong> Ganas shares proporcionalmente a tu hashrate mientras minas</span>
              </li>
              <li class="flex items-start gap-2 text-text-secondary">
                <span class="text-accent-primary mt-0.5">⭐</span>
                <span><strong>Distribución justa:</strong> Las recompensas se reparten según tu porcentaje de shares en el bloque</span>
              </li>
            </ul>
          </div>

          <!-- Mejoras principales -->
          <div>
            <h3 class="text-base font-semibold text-text-primary mb-2 flex items-center gap-2">
              🎉 Nuevas Features
            </h3>
            <ul class="space-y-2">
              <li class="flex items-start gap-2 text-text-secondary">
                <span class="text-green-500 mt-1">✓</span>
                <span><strong>Top Contributor:</strong> Ahora puedes ver quién quedó en primer lugar en cada bloque reciente</span>
              </li>
              <li class="flex items-start gap-2 text-text-secondary">
                <span class="text-green-500 mt-1">✓</span>
                <span><strong>Estadísticas en tiempo real:</strong> El hashrate de la red y tu potencia se actualizan automáticamente</span>
              </li>
              <li class="flex items-start gap-2 text-text-secondary">
                <span class="text-green-500 mt-1">✓</span>
                <span><strong>Tipos de bloques:</strong> Bronze (1000), Silver (1500) y Gold (2500 BLC) con probabilidades diferentes</span>
              </li>
              <li class="flex items-start gap-2 text-text-secondary">
                <span class="text-green-500 mt-1">✓</span>
                <span><strong>Progreso visible:</strong> Ve en tiempo real cuántas shares has generado y tu % del bloque actual</span>
              </li>
            </ul>
          </div>

          <!-- Mejoras técnicas -->
          <div>
            <h3 class="text-base font-semibold text-text-primary mb-2 flex items-center gap-2">
              🔧 Mejoras del Sistema
            </h3>
            <ul class="space-y-2">
              <li class="flex items-start gap-2 text-text-secondary">
                <span class="text-blue-500 mt-1">•</span>
                <span><strong>Acumulador fraccional:</strong> Generación de shares más suave incluso con baja actividad</span>
              </li>
              <li class="flex items-start gap-2 text-text-secondary">
                <span class="text-blue-500 mt-1">•</span>
                <span><strong>Recompensas proporcionales:</strong> Tu participación en el bloque es directamente proporcional a tu hashrate</span>
              </li>
              <li class="flex items-start gap-2 text-text-secondary">
                <span class="text-blue-500 mt-1">•</span>
                <span><strong>Condición lineal:</strong> Penalización más justa (50% condición = 50% hashrate)</span>
              </li>
              <li class="flex items-start gap-2 text-text-secondary">
                <span class="text-blue-500 mt-1">•</span>
                <span><strong>Sin ajuste mid-block:</strong> La dificultad solo cambia entre bloques, nunca durante uno activo</span>
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
