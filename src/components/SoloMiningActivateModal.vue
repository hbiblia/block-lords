<script setup lang="ts">
import { computed } from 'vue';
import { useAuthStore } from '@/stores/auth';
import { useSoloMiningStore } from '@/stores/solo-mining';

defineProps<{ show: boolean }>();
const emit = defineEmits<{ close: []; activated: [] }>();

const authStore = useAuthStore();
const soloStore = useSoloMiningStore();

const isPremium = computed(() => authStore.isPremium);

async function handleActivate() {
  const result = await soloStore.activate();
  if (result?.success) {
    emit('activated');
    emit('close');
  }
}
</script>

<template>
  <Teleport to="body">
    <Transition name="modal">
      <div v-if="show" class="fixed inset-0 z-50 flex items-center justify-center p-4"
        @click.self="emit('close')">
        <div class="absolute inset-0 bg-black/70 backdrop-blur-sm"></div>

        <div class="relative bg-bg-primary border border-border rounded-2xl w-full max-w-lg max-h-[90vh] overflow-hidden shadow-2xl">
          <!-- Header -->
          <div class="flex items-center justify-between p-4 border-b border-border">
            <h2 class="text-lg font-bold text-text-primary flex items-center gap-2">
              <span>⛏️</span> Solo Mining
            </h2>
            <button @click="emit('close')" class="text-text-muted hover:text-text-primary hover:bg-bg-secondary rounded-lg p-1.5 transition-colors">
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/></svg>
            </button>
          </div>

          <!-- Content -->
          <div class="p-4 overflow-y-auto max-h-[calc(90vh-140px)]">
            <!-- Description -->
            <div class="bg-bg-secondary rounded-xl p-4 mb-4">
              <p class="text-text-primary text-sm mb-3">Mina tus propios bloques de forma independiente. Mayor riesgo, mayor recompensa.</p>
              <div class="space-y-2 text-xs text-text-muted">
                <div class="flex items-center gap-2">
                  <span class="text-accent-primary">💎</span>
                  <span>Bloques tipo: Bronze, Silver, Gold y <span class="text-cyan-400 font-bold">Diamond</span> (50,000 landwork)</span>
                </div>
                <div class="flex items-center gap-2">
                  <span class="text-accent-primary">🔑</span>
                  <span>Cada bloque tiene seeds de 4 digitos que tus rigs deben encontrar</span>
                </div>
                <div class="flex items-center gap-2">
                  <span class="text-accent-primary">⏱️</span>
                  <span>30 minutos por bloque - si no encuentras todos los seeds, lo pierdes</span>
                </div>
                <div class="flex items-center gap-2">
                  <span class="text-accent-primary">👑</span>
                  <span>Disponible mientras tengas Premium activo</span>
                </div>
              </div>
            </div>

            <!-- Warning -->
            <div class="bg-status-warning/10 border border-status-warning/30 rounded-xl p-4 mb-4">
              <p class="text-status-warning text-xs font-medium mb-1">Advertencia</p>
              <p class="text-text-muted text-xs">Los rigs en modo solo se degradan <span class="text-status-warning font-bold">3x mas rapido</span> y la temperatura sube <span class="text-status-warning font-bold">2x mas rapido</span>. Asegurate de tener buen cooling y rigs en buena condicion.</p>
            </div>

            <!-- Premium info -->
            <div class="bg-bg-secondary rounded-xl p-4 border border-accent-primary/30">
              <div class="flex items-center justify-between">
                <span class="text-text-muted text-sm">Requisito</span>
                <span :class="isPremium ? 'text-status-success' : 'text-status-danger'" class="font-bold">
                  {{ isPremium ? '✅ Premium activo' : '❌ Requiere Premium' }}
                </span>
              </div>
            </div>
          </div>

          <!-- Footer -->
          <div class="p-4 border-t border-border bg-bg-secondary/50 flex gap-3">
            <button @click="emit('close')"
              class="flex-1 px-4 py-2.5 bg-bg-tertiary text-text-muted rounded-xl text-sm font-medium hover:bg-bg-secondary transition-colors">
              Cancelar
            </button>
            <button @click="handleActivate"
              :disabled="!isPremium || soloStore.activating"
              class="flex-1 px-4 py-2.5 rounded-xl text-sm font-bold transition-all"
              :class="isPremium
                ? 'bg-gradient-primary text-white hover:opacity-90'
                : 'bg-bg-tertiary text-text-muted cursor-not-allowed'">
              {{ soloStore.activating ? 'Activando...' : !isPremium ? 'Requiere Premium' : 'Activar Solo Mining' }}
            </button>
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
.modal-enter-active,
.modal-leave-active {
  transition: all 0.3s ease;
}
.modal-enter-from,
.modal-leave-to {
  opacity: 0;
}
.modal-enter-from .relative,
.modal-leave-to .relative {
  transform: scale(0.95);
}
</style>
