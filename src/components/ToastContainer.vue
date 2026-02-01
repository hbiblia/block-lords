<script setup lang="ts">
import { useToastStore } from '@/stores/toast';

const toastStore = useToastStore();

function getTypeConfig(type: string) {
  switch (type) {
    case 'success':
      return {
        bg: 'from-emerald-500/20 to-emerald-600/10',
        border: 'border-emerald-500/50',
        iconBg: 'bg-emerald-500',
        progressBg: 'bg-emerald-500',
        glow: 'shadow-emerald-500/20',
      };
    case 'error':
      return {
        bg: 'from-red-500/20 to-red-600/10',
        border: 'border-red-500/50',
        iconBg: 'bg-red-500',
        progressBg: 'bg-red-500',
        glow: 'shadow-red-500/20',
      };
    case 'warning':
      return {
        bg: 'from-amber-500/20 to-amber-600/10',
        border: 'border-amber-500/50',
        iconBg: 'bg-amber-500',
        progressBg: 'bg-amber-500',
        glow: 'shadow-amber-500/20',
      };
    case 'info':
    default:
      return {
        bg: 'from-blue-500/20 to-blue-600/10',
        border: 'border-blue-500/50',
        iconBg: 'bg-blue-500',
        progressBg: 'bg-blue-500',
        glow: 'shadow-blue-500/20',
      };
  }
}
</script>

<template>
  <Teleport to="body">
    <div class="fixed top-20 right-4 z-[200] flex flex-col gap-3 pointer-events-none">
      <TransitionGroup name="toast">
        <div
          v-for="toast in toastStore.toasts"
          :key="toast.id"
          class="toast-item pointer-events-auto relative overflow-hidden rounded-xl border backdrop-blur-xl shadow-2xl min-w-[280px] max-w-[360px] cursor-pointer transition-all duration-200 hover:scale-[1.02] hover:shadow-3xl"
          :class="[
            `bg-gradient-to-r ${getTypeConfig(toast.type).bg}`,
            getTypeConfig(toast.type).border,
            getTypeConfig(toast.type).glow
          ]"
          @click="toastStore.remove(toast.id)"
        >
          <!-- Glass effect overlay -->
          <div class="absolute inset-0 bg-bg-primary/60 -z-10" />

          <!-- Content -->
          <div class="flex items-center gap-3 px-4 py-3">
            <!-- Icon with colored background -->
            <div
              v-if="toast.icon"
              class="flex-shrink-0 w-9 h-9 rounded-lg flex items-center justify-center shadow-lg"
              :class="getTypeConfig(toast.type).iconBg"
            >
              <span class="text-lg text-white drop-shadow">{{ toast.icon }}</span>
            </div>

            <!-- Message -->
            <div class="flex-1 min-w-0">
              <p class="text-sm font-semibold text-white leading-tight">
                {{ toast.message }}
              </p>
            </div>

            <!-- Close button -->
            <button
              class="flex-shrink-0 w-6 h-6 rounded-full flex items-center justify-center text-white/50 hover:text-white hover:bg-white/10 transition-colors"
              @click.stop="toastStore.remove(toast.id)"
            >
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>

          <!-- Progress bar with CSS animation -->
          <div class="absolute bottom-0 left-0 right-0 h-1 bg-black/20">
            <div
              class="h-full progress-bar"
              :class="getTypeConfig(toast.type).progressBg"
              :style="{ animationDuration: `${toast.duration}ms` }"
            />
          </div>
        </div>
      </TransitionGroup>
    </div>
  </Teleport>
</template>

<style scoped>
.toast-enter-active {
  animation: toast-in 0.4s cubic-bezier(0.21, 1.02, 0.73, 1);
}

.toast-leave-active {
  animation: toast-out 0.3s cubic-bezier(0.06, 0.71, 0.55, 1) forwards;
}

.toast-move {
  transition: transform 0.4s cubic-bezier(0.21, 1.02, 0.73, 1);
}

@keyframes toast-in {
  0% {
    opacity: 0;
    transform: translateX(100%) scale(0.9);
  }
  100% {
    opacity: 1;
    transform: translateX(0) scale(1);
  }
}

@keyframes toast-out {
  0% {
    opacity: 1;
    transform: translateX(0) scale(1);
  }
  100% {
    opacity: 0;
    transform: translateX(50%) scale(0.9);
  }
}

.progress-bar {
  width: 100%;
  animation: progress-shrink linear forwards;
}

@keyframes progress-shrink {
  from {
    width: 100%;
  }
  to {
    width: 0%;
  }
}

.toast-item {
  box-shadow:
    0 10px 40px -10px rgba(0, 0, 0, 0.5),
    0 0 20px -5px var(--tw-shadow-color, rgba(0, 0, 0, 0.1));
}

.toast-item:hover {
  box-shadow:
    0 15px 50px -10px rgba(0, 0, 0, 0.6),
    0 0 30px -5px var(--tw-shadow-color, rgba(0, 0, 0, 0.15));
}
</style>
