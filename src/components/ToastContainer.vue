<script setup lang="ts">
import { useToastStore } from '@/stores/toast';

const toastStore = useToastStore();

function getTypeClasses(type: string) {
  switch (type) {
    case 'success':
      return 'bg-status-success/90 border-status-success text-white';
    case 'error':
      return 'bg-status-danger/90 border-status-danger text-white';
    case 'warning':
      return 'bg-status-warning/90 border-status-warning text-bg-primary';
    case 'info':
    default:
      return 'bg-bg-secondary/95 border-accent-primary/50 text-white';
  }
}
</script>

<template>
  <Teleport to="body">
    <div class="fixed top-20 right-4 z-[200] flex flex-col gap-2 pointer-events-none">
      <TransitionGroup name="toast">
        <div
          v-for="toast in toastStore.toasts"
          :key="toast.id"
          class="pointer-events-auto flex items-center gap-3 px-4 py-3 rounded-lg border backdrop-blur-sm shadow-lg min-w-[200px] max-w-[320px] cursor-pointer transition-all hover:scale-[1.02]"
          :class="getTypeClasses(toast.type)"
          @click="toastStore.remove(toast.id)"
        >
          <span v-if="toast.icon" class="text-xl flex-shrink-0">{{ toast.icon }}</span>
          <span class="text-sm font-medium">{{ toast.message }}</span>
        </div>
      </TransitionGroup>
    </div>
  </Teleport>
</template>

<style scoped>
.toast-enter-active {
  animation: toast-in 0.3s ease-out;
}

.toast-leave-active {
  animation: toast-out 0.2s ease-in forwards;
}

.toast-move {
  transition: transform 0.3s ease;
}

@keyframes toast-in {
  0% {
    opacity: 0;
    transform: translateX(100%);
  }
  100% {
    opacity: 1;
    transform: translateX(0);
  }
}

@keyframes toast-out {
  0% {
    opacity: 1;
    transform: translateX(0);
  }
  100% {
    opacity: 0;
    transform: translateX(100%);
  }
}
</style>
