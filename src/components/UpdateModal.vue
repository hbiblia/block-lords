<script setup lang="ts">
import { ref, onMounted, watch } from 'vue';
import { useRoute } from 'vue-router';

// Versión actual de la app (actualizar esto cuando haya cambios importantes)
const CURRENT_VERSION = '1.3.0';
const STORAGE_KEY = 'lootmine-last-seen-version';

const route = useRoute();
const showModal = ref(false);
const shouldShow = ref(false);

onMounted(() => {
  const lastSeenVersion = localStorage.getItem(STORAGE_KEY);
  if (!lastSeenVersion || lastSeenVersion !== CURRENT_VERSION) {
    shouldShow.value = true;
    // Si ya estamos en /mining, mostrar inmediatamente
    if (route.path === '/mining') {
      showModal.value = true;
    }
  }
});

// Mostrar cuando el usuario navegue a /mining
watch(() => route.path, (path) => {
  if (path === '/mining' && shouldShow.value) {
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
  localStorage.setItem(STORAGE_KEY, CURRENT_VERSION);
  shouldShow.value = false;
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
          <!-- Nuevas Ventajas Premium -->
          <div class="p-3 bg-gradient-to-r from-amber-500/20 to-yellow-500/20 border border-amber-500/30 rounded-lg">
            <h3 class="text-lg font-bold text-text-primary mb-2 flex items-center gap-2">
              👑 Nuevas Ventajas Premium
            </h3>
            <p class="text-text-secondary text-sm mb-2">
              Los usuarios <strong class="text-amber-400">Premium</strong> ahora disfrutan de beneficios exclusivos:
            </p>
            <ul class="space-y-2 text-sm">
              <li class="flex items-start gap-2 text-text-secondary">
                <span class="text-amber-400 mt-0.5">⚡</span>
                <span><strong>Boost de Hashrate:</strong> +15% de velocidad de minado</span>
              </li>
              <li class="flex items-start gap-2 text-text-secondary">
                <span class="text-amber-400 mt-0.5">💎</span>
                <span><strong>Probabilidad mejorada:</strong> Mayor chance de encontrar bloques Gold y Silver</span>
              </li>
              <li class="flex items-start gap-2 text-text-secondary">
                <span class="text-amber-400 mt-0.5">🔧</span>
                <span><strong>Desgaste reducido:</strong> Tus rigs se desgastan más lentamente</span>
              </li>
            </ul>
          </div>

          <!-- Mini-juego de Cartas -->
          <div class="p-3 bg-gradient-to-r from-blue-500/20 to-cyan-500/20 border border-blue-500/30 rounded-lg">
            <h3 class="text-lg font-bold text-text-primary mb-2 flex items-center gap-2">
              🃏 Nuevo Mini-Juego: Battle Defense
            </h3>
            <p class="text-text-secondary text-sm mb-2">
              ¡Defiende tu base en emocionantes batallas estratégicas por turnos!
            </p>
            <ul class="space-y-2 text-sm">
              <li class="flex items-start gap-2 text-text-secondary">
                <span class="text-blue-400 mt-0.5">⚔️</span>
                <span><strong>Sistema de cartas:</strong> Colecciona y mejora cartas de ataque y defensa</span>
              </li>
              <li class="flex items-start gap-2 text-text-secondary">
                <span class="text-blue-400 mt-0.5">🎮</span>
                <span><strong>Modo PvP:</strong> Enfrenta a otros jugadores en batallas estratégicas</span>
              </li>
              <li class="flex items-start gap-2 text-text-secondary">
                <span class="text-blue-400 mt-0.5">🏆</span>
                <span><strong>Recompensas:</strong> Gana BLC y recursos exclusivos al vencer</span>
              </li>
            </ul>
          </div>

          <!-- Correcciones y Mejoras -->
          <div>
            <h3 class="text-base font-semibold text-text-primary mb-2 flex items-center gap-2">
              🔧 Correcciones y Mejoras
            </h3>
            <ul class="space-y-2">
              <li class="flex items-start gap-2 text-text-secondary">
                <span class="text-green-500 mt-1">✓</span>
                <span><strong>Optimización de rendimiento:</strong> Carga más rápida y menor consumo de recursos</span>
              </li>
              <li class="flex items-start gap-2 text-text-secondary">
                <span class="text-green-500 mt-1">✓</span>
                <span><strong>Interfaz mejorada:</strong> Mejor visualización de estadísticas y tooltips más claros</span>
              </li>
              <li class="flex items-start gap-2 text-text-secondary">
                <span class="text-green-500 mt-1">✓</span>
                <span><strong>Balance general:</strong> Ajustes en costos de crafteo y recompensas de misiones</span>
              </li>
              <li class="flex items-start gap-2 text-text-secondary">
                <span class="text-green-500 mt-1">✓</span>
                <span><strong>Corrección de bugs:</strong> Solucionados varios errores menores reportados por la comunidad</span>
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
  background: rgba(245, 158, 11, 0.3);
  border-radius: 4px;
}

.custom-scrollbar::-webkit-scrollbar-thumb:hover {
  background: rgba(245, 158, 11, 0.5);
}
</style>
