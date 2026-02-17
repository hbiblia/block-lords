<script setup lang="ts">
import { useMiningTips, type TipSeverity } from '@/composables/useMiningTips';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const { activeTips, dismiss } = useMiningTips();

const severityConfig: Record<TipSeverity, Record<string, string>> = {
  danger: {
    bar: 'border-status-danger/50 bg-status-danger/10',
    icon: 'bg-status-danger/20 text-status-danger',
    text: 'text-status-danger',
    btn: 'bg-status-danger/20 hover:bg-status-danger/30 text-status-danger',
    dismiss: 'text-status-danger/50 hover:text-status-danger',
  },
  warning: {
    bar: 'border-status-warning/50 bg-status-warning/10',
    icon: 'bg-status-warning/20 text-status-warning',
    text: 'text-status-warning',
    btn: 'bg-status-warning/20 hover:bg-status-warning/30 text-status-warning',
    dismiss: 'text-status-warning/50 hover:text-status-warning',
  },
  info: {
    bar: 'border-status-info/50 bg-status-info/10',
    icon: 'bg-status-info/20 text-status-info',
    text: 'text-status-info',
    btn: 'bg-status-info/20 hover:bg-status-info/30 text-status-info',
    dismiss: 'text-status-info/50 hover:text-status-info',
  },
};

function handleAction(event: string) {
  window.dispatchEvent(new CustomEvent(event));
}
</script>

<template>
  <TransitionGroup
    name="tip"
    tag="div"
    class="space-y-2 mb-4"
    v-if="activeTips.length > 0"
  >
    <div
      v-for="tip in activeTips"
      :key="tip.id"
      class="flex items-center gap-3 px-4 py-3 rounded-xl border backdrop-blur-sm"
      :class="severityConfig[tip.severity].bar"
    >
      <div class="shrink-0 w-8 h-8 rounded-lg flex items-center justify-center text-base"
           :class="severityConfig[tip.severity].icon">
        {{ tip.icon }}
      </div>

      <p class="flex-1 text-sm font-medium"
         :class="severityConfig[tip.severity].text">
        {{ t(tip.messageKey, tip.messageParams ?? {}) }}
      </p>

      <button
        v-if="tip.actionKey && tip.actionEvent"
        @click="handleAction(tip.actionEvent)"
        class="shrink-0 text-xs font-semibold px-3 py-1.5 rounded-lg transition-colors"
        :class="severityConfig[tip.severity].btn"
      >
        {{ t(tip.actionKey) }}
      </button>

      <button
        @click="dismiss(tip.id)"
        class="shrink-0 w-6 h-6 rounded-full flex items-center justify-center transition-colors"
        :class="severityConfig[tip.severity].dismiss"
      >
        <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M6 18L18 6M6 6l12 12"/>
        </svg>
      </button>
    </div>
  </TransitionGroup>
</template>

<style scoped>
.tip-enter-active {
  transition: all 0.3s ease-out;
}
.tip-leave-active {
  transition: all 0.2s ease-in;
}
.tip-enter-from {
  opacity: 0;
  transform: translateY(-8px);
}
.tip-leave-to {
  opacity: 0;
  transform: translateX(20px);
}
.tip-move {
  transition: transform 0.3s ease;
}
</style>
