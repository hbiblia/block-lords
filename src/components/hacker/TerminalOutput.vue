<script setup lang="ts">
import type { OutputLine } from '@/stores/hacker';

defineProps<{
  lines: OutputLine[];
}>();

function lineClass(type: OutputLine['type']): string {
  switch (type) {
    case 'input': return 'terminal-line-input';
    case 'success': return 'terminal-line-success';
    case 'error': return 'terminal-line-error';
    case 'info': return 'terminal-line-info';
    case 'warning': return 'terminal-line-warning';
    case 'header': return 'terminal-line-header';
    case 'command': return 'terminal-line-command';
    default: return 'terminal-line-output';
  }
}
</script>

<template>
  <div class="terminal-output font-mono text-sm leading-relaxed">
    <div
      v-for="line in lines"
      :key="line.id"
      class="terminal-line whitespace-pre-wrap break-all"
      :class="lineClass(line.type)"
    >
      <span v-if="line.type === 'input'" class="text-green-300 opacity-70">$ </span>
      <span>{{ line.text }}</span>
    </div>
  </div>
</template>

<style scoped>
.terminal-line {
  padding: 1px 0;
  animation: line-appear 0.05s ease-out;
}

.terminal-line-input {
  color: #4ade80;
  font-weight: 600;
}

.terminal-line-output {
  color: #00ff41;
  opacity: 0.9;
}

.terminal-line-success {
  color: #00ff41;
  text-shadow: 0 0 8px rgba(0, 255, 65, 0.6);
  font-weight: 700;
}

.terminal-line-error {
  color: #ff0040;
  text-shadow: 0 0 6px rgba(255, 0, 64, 0.4);
}

.terminal-line-info {
  color: #00d4ff;
}

.terminal-line-warning {
  color: #fbbf24;
}

.terminal-line-header {
  color: #00ff41;
  border-bottom: 1px solid rgba(0, 255, 65, 0.2);
  padding-bottom: 4px;
  margin-bottom: 4px;
  font-weight: 700;
  text-shadow: 0 0 8px rgba(0, 255, 65, 0.4);
}

.terminal-line-command {
  color: #00ffaa;
  background: rgba(0, 255, 170, 0.08);
  border-left: 2px solid #00ffaa;
  padding: 3px 8px;
  margin: 2px 0;
  font-weight: 600;
  text-shadow: 0 0 6px rgba(0, 255, 170, 0.3);
}

@keyframes line-appear {
  from {
    opacity: 0;
    transform: translateX(-4px);
  }
  to {
    opacity: 1;
    transform: translateX(0);
  }
}
</style>
