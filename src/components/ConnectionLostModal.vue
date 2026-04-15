<script setup lang="ts">
import { watch, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useGameTickStore } from '@/stores/game-tick';
import { playSound } from '@/utils/sounds';

const { t } = useI18n();
const gameTickStore = useGameTickStore();

const showDisconnected = computed(() =>
  gameTickStore.tickCount > 0 && !gameTickStore.isHealthy
);

watch(showDisconnected, (show) => {
  if (show) playSound('warning');
});

function handleReconnect() {
  gameTickStore.start();
}

function handleRefresh() {
  window.location.reload();
}
</script>

<template>
  <Teleport to="body">
    <Transition name="toast">
      <div v-if="showDisconnected" class="cl-wrap">
        <div class="cl-card">
          <div class="cl-accent"></div>
          <div class="cl-content">
            <div class="cl-icon">⚠️</div>
            <div class="cl-text">
              <span class="cl-label">{{ t('connection.label', 'Offline') }}</span>
              <span class="cl-msg">{{ t('connection.title') }}</span>
            </div>
            <button @click="handleReconnect" class="cl-btn reconnect">{{ t('connection.reconnect', 'Reconnect') }}</button>
            <button @click="handleRefresh" class="cl-btn reload">{{ t('connection.reloadPage') }}</button>
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
@import url('https://fonts.googleapis.com/css2?family=Nunito:wght@400;600;700;800;900&display=swap');

.cl-wrap {
  position: fixed; bottom: 1.5rem; left: 50%; transform: translateX(-50%);
  z-index: 9999; width: calc(100% - 2rem); max-width: 420px;
}
.cl-card {
  position: relative; overflow: hidden;
  background: #1f1833; border: 2px solid #ff7b7b; border-radius: 12px;
  box-shadow: 3px 3px 0 #ffc0c0;
  font-family: 'Nunito', 'Trebuchet MS', sans-serif;
}
.cl-accent {
  position: absolute; top: 0; left: 0; right: 0; height: 3px;
  background: linear-gradient(90deg, #ff7b7b, #d4a017, #ff7b7b);
  background-size: 200% 100%;
  animation: cl-shimmer 3s linear infinite;
}
@keyframes cl-shimmer { 0% { background-position: 200% 0; } 100% { background-position: -200% 0; } }

.cl-content {
  display: flex; align-items: center; gap: 10px;
  padding: 12px 14px;
}
.cl-icon { font-size: 1.2rem; flex-shrink: 0; }
.cl-text { flex: 1; min-width: 0; }
.cl-label {
  display: block; font-size: 0.6rem; font-weight: 900; color: #cc4444;
  letter-spacing: 2px; text-transform: uppercase;
}
.cl-msg {
  display: block; font-size: 0.8rem; font-weight: 700; color: #f0e4ff;
  white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
}
.cl-btn {
  flex-shrink: 0; padding: 6px 12px; border-radius: 8px;
  font-size: 0.7rem; font-weight: 900; cursor: pointer;
  font-family: 'Nunito', sans-serif; transition: 0.2s; border: 2px solid;
}
.cl-btn.reconnect {
  background: #fff8e0; border-color: #d4a017; color: #8a6a10;
}
.cl-btn.reconnect:hover { background: #ffe566; }
.cl-btn.reload {
  background: #fff0f0; border-color: #ff7b7b; color: #cc4444;
}
.cl-btn.reload:hover { background: #ffe0e0; }

/* Transitions */
.toast-enter-active { transition: all 0.3s ease-out; }
.toast-leave-active { transition: all 0.2s ease-in; }
.toast-enter-from { opacity: 0; transform: translate(-50%, 20px); }
.toast-leave-to { opacity: 0; transform: translate(-50%, 20px); }
</style>
