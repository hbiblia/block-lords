<script setup lang="ts">
import { useToastStore } from '@/stores/toast';

const toastStore = useToastStore();

function getTypeConfig(type: string) {
  switch (type) {
    case 'success':
      return { color: '#7cc490', bg: '#e8f8ec', border: '#a8d0b8', text: '#3a7a4a', label: 'SYS_OK' };
    case 'error':
      return { color: '#ff7b7b', bg: '#fff0f0', border: '#ff7b7b', text: '#c04040', label: 'SYS_ERR' };
    case 'warning':
      return { color: '#d4a017', bg: '#fff8e0', border: '#e8c840', text: '#8a6a10', label: 'SYS_WARN' };
    case 'info':
    default:
      return { color: '#c4a0e8', bg: '#f8f0ff', border: '#c4a0e8', text: '#7b5ea7', label: 'SYS_INFO' };
  }
}
</script>

<template>
  <Teleport to="body">
    <div class="toast-hud-container">
      <TransitionGroup name="toast">
        <div
          v-for="toast in toastStore.toasts"
          :key="toast.id"
          class="toast-hud"
          :style="{ background: getTypeConfig(toast.type).bg, borderColor: getTypeConfig(toast.type).border }"
          @click="toastStore.remove(toast.id)"
        >
          <!-- Top label -->
          <div class="th-header">
            <span class="th-indicator" :style="{ background: getTypeConfig(toast.type).color }"></span>
            <span class="th-label" :style="{ color: getTypeConfig(toast.type).text }">{{ getTypeConfig(toast.type).label }}</span>
            <span class="th-dismiss">X</span>
          </div>

          <!-- Content -->
          <div class="th-body">
            <span v-if="toast.icon" class="th-icon">{{ toast.icon }}</span>
            <span class="th-message" :style="{ color: getTypeConfig(toast.type).text }">{{ toast.message }}</span>
          </div>

          <!-- Progress bar -->
          <div class="th-progress">
            <div
              class="th-progress-fill"
              :style="{ animationDuration: `${toast.duration}ms`, background: getTypeConfig(toast.type).color }"
            ></div>
          </div>
        </div>
      </TransitionGroup>
    </div>
  </Teleport>
</template>

<style scoped>
.toast-hud-container {
  position: fixed;
  top: 5rem;
  right: 1rem;
  z-index: 200;
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
  pointer-events: none;
}

.toast-hud {
  pointer-events: auto;
  position: relative;
  overflow: hidden;
  min-width: 280px;
  max-width: 360px;
  cursor: pointer;
  border: 2px solid #4a3660;
  background: #1f1833;
  border-radius: 12px;
  box-shadow: 3px 3px 0 rgba(74,54,96,0.3);
  transition: all 0.2s;
  font-family: 'Nunito', 'Trebuchet MS', sans-serif;
}

.toast-hud:hover {
  box-shadow: 4px 4px 0 #d8c0ee;
}

/* Header */
.th-header {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 6px 12px 2px;
}

.th-indicator {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  flex-shrink: 0;
  animation: th-pulse 1.5s infinite;
}

@keyframes th-pulse {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.3; }
}

.th-label {
  font-size: 0.55rem;
  font-weight: 900;
  letter-spacing: 2px;
  flex: 1;
}

.th-dismiss {
  font-size: 0.55rem;
  font-weight: 900;
  color: #8a70a8;
  cursor: pointer;
  opacity: 0.5;
  transition: 0.2s;
}
.th-dismiss:hover { opacity: 1; }

/* Body */
.th-body {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 4px 12px 8px;
}

.th-icon {
  font-size: 1.1rem;
  flex-shrink: 0;
}

.th-message {
  font-size: 0.8rem;
  font-weight: 700;
  line-height: 1.3;
  letter-spacing: 0.3px;
}

/* Progress bar */
.th-progress {
  height: 3px;
  background: #2d2545;
  overflow: hidden;
  border-radius: 0 0 10px 10px;
}

.th-progress-fill {
  height: 100%;
  width: 100%;
  animation: th-shrink linear forwards;
  border-radius: 0 0 10px 10px;
}

@keyframes th-shrink {
  from { width: 100%; }
  to { width: 0%; }
}

/* Transitions */
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
  0% { opacity: 0; transform: translateX(100%) scale(0.95); }
  100% { opacity: 1; transform: translateX(0) scale(1); }
}

@keyframes toast-out {
  0% { opacity: 1; transform: translateX(0) scale(1); }
  100% { opacity: 0; transform: translateX(50%) scale(0.95); }
}

/* Mobile */
@media (max-width: 480px) {
  .toast-hud-container {
    right: 0.5rem;
    left: 0.5rem;
  }
  .toast-hud {
    min-width: 0;
    max-width: none;
  }
}
</style>
