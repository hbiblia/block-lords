<script setup lang="ts">
import { useToastStore } from '@/stores/toast';

const toastStore = useToastStore();

function getTypeConfig(type: string) {
  switch (type) {
    case 'success':
      return { color: '#22c55e', label: 'SYS_OK' };
    case 'error':
      return { color: '#ef4444', label: 'SYS_ERR' };
    case 'warning':
      return { color: '#f59e0b', label: 'SYS_WARN' };
    case 'info':
    default:
      return { color: '#06b6d4', label: 'SYS_INFO' };
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
          @click="toastStore.remove(toast.id)"
        >
          <!-- HUD Corners -->
          <div class="th-corner th-tl" :style="{ borderColor: getTypeConfig(toast.type).color }"></div>
          <div class="th-corner th-tr" :style="{ borderColor: getTypeConfig(toast.type).color }"></div>
          <div class="th-corner th-bl" :style="{ borderColor: getTypeConfig(toast.type).color }"></div>
          <div class="th-corner th-br" :style="{ borderColor: getTypeConfig(toast.type).color }"></div>

          <!-- Scanline -->
          <div class="th-scanline"></div>

          <!-- Top label -->
          <div class="th-header">
            <span class="th-indicator" :style="{ background: getTypeConfig(toast.type).color, boxShadow: `0 0 6px ${getTypeConfig(toast.type).color}80` }"></span>
            <span class="th-label">{{ getTypeConfig(toast.type).label }}</span>
            <span class="th-dismiss">ESC</span>
          </div>

          <!-- Content -->
          <div class="th-body">
            <span v-if="toast.icon" class="th-icon">{{ toast.icon }}</span>
            <span class="th-message">{{ toast.message }}</span>
          </div>

          <!-- Progress bar -->
          <div class="th-progress">
            <div
              class="th-progress-fill"
              :style="{ animationDuration: `${toast.duration}ms`, background: `linear-gradient(90deg, ${getTypeConfig(toast.type).color}40, ${getTypeConfig(toast.type).color})` }"
            ></div>
            <div class="th-progress-segments"></div>
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
  border: 1px solid #2f3052;
  background: linear-gradient(135deg, rgba(20,21,40,0.97) 0%, rgba(30,31,54,0.95) 100%);
  padding: 0;
  transition: all 0.2s;
}

/* CRT micro-lines */
.toast-hud::before {
  content: '';
  position: absolute;
  inset: 0;
  pointer-events: none;
  background: repeating-linear-gradient(
    0deg,
    transparent, transparent 3px,
    rgba(255,255,255,0.008) 3px, rgba(255,255,255,0.008) 4px
  );
  z-index: 1;
}

.toast-hud:hover {
  border-color: #4f4f6f;
  background: linear-gradient(135deg, rgba(25,26,45,0.98) 0%, rgba(35,36,60,0.97) 100%);
}

/* HUD Corners */
.th-corner {
  position: absolute;
  width: 8px;
  height: 8px;
  pointer-events: none;
  z-index: 3;
}
.th-tl { top: 0; left: 0; border-top: 2px solid; border-left: 2px solid; }
.th-tr { top: 0; right: 0; border-top: 2px solid; border-right: 2px solid; }
.th-bl { bottom: 0; left: 0; border-bottom: 2px solid; border-left: 2px solid; }
.th-br { bottom: 0; right: 0; border-bottom: 2px solid; border-right: 2px solid; }

/* Scanline sweep */
.th-scanline {
  position: absolute;
  top: 0;
  left: -100%;
  width: 100%;
  height: 100%;
  pointer-events: none;
  z-index: 1;
  background: linear-gradient(
    90deg,
    transparent 0%,
    rgba(245,158,11,0.03) 45%,
    rgba(245,158,11,0.06) 50%,
    rgba(245,158,11,0.03) 55%,
    transparent 100%
  );
  animation: toast-scan 4s linear infinite;
}

@keyframes toast-scan {
  0% { left: -100%; }
  100% { left: 100%; }
}

/* Header */
.th-header {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 5px 10px 3px;
  position: relative;
  z-index: 2;
}

.th-indicator {
  width: 5px;
  height: 5px;
  border-radius: 50%;
  flex-shrink: 0;
  animation: th-pulse 1.5s infinite;
}

@keyframes th-pulse {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.3; }
}

.th-label {
  font-size: 0.4rem;
  font-weight: 900;
  color: #71717a;
  letter-spacing: 2.5px;
  flex: 1;
}

.th-dismiss {
  font-size: 0.35rem;
  font-weight: 900;
  color: #4f4f6f;
  letter-spacing: 1px;
  padding: 1px 4px;
  border: 1px solid #2f3052;
}

/* Body */
.th-body {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 4px 10px 8px;
  position: relative;
  z-index: 2;
}

.th-icon {
  font-size: 1rem;
  flex-shrink: 0;
  filter: drop-shadow(0 0 4px rgba(245,158,11,0.3));
}

.th-message {
  font-size: 0.7rem;
  font-weight: 800;
  color: #e5e7eb;
  line-height: 1.3;
  letter-spacing: 0.3px;
}

/* Progress bar */
.th-progress {
  height: 3px;
  background: #1a1b2e;
  position: relative;
  overflow: hidden;
}

.th-progress-fill {
  height: 100%;
  width: 100%;
  animation: th-shrink linear forwards;
  position: relative;
}

.th-progress-fill::after {
  content: '';
  position: absolute;
  top: 0;
  left: 0;
  width: 3px;
  height: 100%;
  background: rgba(255,255,255,0.6);
}

.th-progress-segments {
  position: absolute;
  inset: 0;
  pointer-events: none;
  background: repeating-linear-gradient(
    90deg,
    transparent 0px, transparent 9%,
    rgba(20,21,40,0.8) 9%, rgba(20,21,40,0.8) 10%
  );
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
  0% {
    opacity: 0;
    transform: translateX(100%) scale(0.95);
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
    transform: translateX(50%) scale(0.95);
  }
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
