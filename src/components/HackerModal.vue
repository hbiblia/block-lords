<script setup lang="ts">
import { ref, watch, nextTick, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useHackerStore } from '@/stores/hacker';
import { useHackerTerminal } from '@/composables/useHackerTerminal';
import MatrixRain from '@/components/hacker/MatrixRain.vue';
import TerminalOutput from '@/components/hacker/TerminalOutput.vue';
import { playSound } from '@/utils/sounds';

const { t } = useI18n();

const props = defineProps<{ show: boolean }>();
const emit = defineEmits<{ close: [] }>();

const hackerStore = useHackerStore();
const {
  inputValue, showWelcome, executeCommand,
  hackGameActive, hackTimer, hackCurrentStage, hackStages, hackScore, hackPrompt,
  isRecording, recordingName, isRunningScript,
  sshActive, sshPrompt,
} = useHackerTerminal();

const terminalBody = ref<HTMLElement | null>(null);
const inputEl = ref<HTMLInputElement | null>(null);

// Dynamic prompt: changes during hacking
const prompt = computed(() => {
  if (hackGameActive.value && hackPrompt.value) {
    return hackPrompt.value;
  }
  if (sshActive.value && sshPrompt.value) {
    return sshPrompt.value;
  }
  if (isRecording.value) {
    return `recording@${recordingName.value}:~$`;
  }
  if (isRunningScript.value) {
    return 'script@running:~$';
  }
  return 'lootmine@player:~$';
});

// Dynamic placeholder
const placeholder = computed(() => {
  if (hackGameActive.value) {
    return 'Type the command...';
  }
  return 'Type a command...';
});

function scrollToBottom() {
  nextTick(() => {
    if (terminalBody.value) {
      terminalBody.value.scrollTop = terminalBody.value.scrollHeight;
    }
  });
}

// Watch output changes to auto-scroll
watch(
  () => hackerStore.outputLines.length,
  () => scrollToBottom(),
);

// Watch show prop
watch(
  () => props.show,
  (open) => {
    if (open) {
      if (hackerStore.outputLines.length === 0) {
        showWelcome();
      }
      nextTick(() => {
        inputEl.value?.focus();
        scrollToBottom();
      });
    }
  },
);

function handleSubmit() {
  if (!inputValue.value.trim()) return;
  playSound('hack_keypress' as any);
  executeCommand(inputValue.value);
  inputValue.value = '';
  scrollToBottom();
}

function handleKeydown(e: KeyboardEvent) {
  if (e.key === 'Escape') {
    if (hackerStore.isHacking) return;
    emit('close');
    return;
  }

  // Command history navigation (disabled during hack)
  if (hackGameActive.value) return;

  if (e.key === 'ArrowUp') {
    e.preventDefault();
    if (hackerStore.historyIndex > 0) {
      hackerStore.historyIndex--;
      inputValue.value = hackerStore.commandHistory[hackerStore.historyIndex] || '';
    }
  } else if (e.key === 'ArrowDown') {
    e.preventDefault();
    if (hackerStore.historyIndex < hackerStore.commandHistory.length - 1) {
      hackerStore.historyIndex++;
      inputValue.value = hackerStore.commandHistory[hackerStore.historyIndex] || '';
    } else {
      hackerStore.historyIndex = hackerStore.commandHistory.length;
      inputValue.value = '';
    }
  }
}

function closeModal() {
  if (hackerStore.isHacking) return;
  emit('close');
}

function focusInput() {
  inputEl.value?.focus();
}
</script>

<template>
  <Teleport to="body">
    <Transition name="fade">
      <div
        v-if="show"
        class="fixed inset-0 z-[150] flex items-center justify-center p-2 sm:p-4"
        @click.self="closeModal"
      >
        <!-- Backdrop -->
        <div class="absolute inset-0 bg-black/80 backdrop-blur-sm" @click="closeModal" />

        <!-- Terminal Window -->
        <div class="relative w-full max-w-3xl h-[85vh] sm:h-[80vh] flex flex-col rounded-xl overflow-hidden border border-green-500/30 shadow-2xl shadow-green-900/20 animate-scale-in">
          <!-- Matrix rain background -->
          <div class="absolute inset-0 hacker-bg">
            <MatrixRain :opacity="0.06" :speed="1.5" :density="16" />
          </div>

          <!-- CRT Scanlines overlay -->
          <div class="absolute inset-0 hacker-scanlines pointer-events-none z-[1]" />

          <!-- Header -->
          <div class="relative z-10 flex items-center justify-between px-4 py-2.5 border-b border-green-500/20 bg-black/80">
            <div class="flex items-center gap-3">
              <div class="flex items-center gap-1.5">
                <button
                  @click="closeModal"
                  class="w-3 h-3 rounded-full bg-red-500 hover:bg-red-400 transition-colors"
                  :title="t('hacker.close', 'Close')"
                />
                <div class="w-3 h-3 rounded-full bg-yellow-500/50" />
                <div class="w-3 h-3 rounded-full bg-green-500" />
              </div>
              <span class="font-mono text-xs text-green-400/80 tracking-wider">
                LOOTMINE TERMINAL v1.0
              </span>
            </div>
            <!-- Hack status in header when hacking -->
            <div v-if="hackGameActive" class="flex items-center gap-3 text-xs font-mono">
              <span class="text-green-400">
                STAGE {{ hackCurrentStage + 1 }}/{{ hackStages.length }}
              </span>
              <span class="text-green-400/60">
                SCORE: {{ hackScore }}
              </span>
              <span
                class="font-bold tabular-nums"
                :class="hackTimer <= 5 ? 'text-red-500 animate-pulse' : hackTimer <= 10 ? 'text-yellow-400' : 'text-green-400'"
              >
                {{ hackTimer }}s
              </span>
            </div>
            <div v-else class="flex items-center gap-2 text-xs font-mono text-green-400/50">
              <span>SSH</span>
              <span class="w-1.5 h-1.5 rounded-full bg-green-500 animate-pulse" />
            </div>
          </div>

          <!-- Terminal Body -->
          <div
            ref="terminalBody"
            class="relative z-10 flex-1 min-h-0 overflow-y-auto p-4 font-mono text-sm custom-scrollbar cursor-text"
            @click="focusInput"
          >
            <TerminalOutput :lines="hackerStore.outputLines" />
          </div>

          <!-- Input area -->
          <div class="relative z-10 flex items-center px-4 py-3 border-t border-green-500/20 bg-black/80">
            <span
              class="font-mono text-sm mr-2 whitespace-nowrap select-none"
              :class="hackGameActive ? 'text-red-400' : sshActive ? 'text-red-400' : isRecording ? 'text-yellow-400' : isRunningScript ? 'text-cyan-400' : 'text-green-400'"
            >
              {{ prompt }}
            </span>
            <input
              ref="inputEl"
              v-model="inputValue"
              type="text"
              class="terminal-input flex-1 bg-transparent border-none outline-none font-mono text-sm text-green-400 caret-green-400 placeholder-green-800"
              :placeholder="placeholder"
              autocomplete="off"
              autocorrect="off"
              autocapitalize="off"
              spellcheck="false"
              @keydown="handleKeydown"
              @keydown.enter="handleSubmit"
            />
            <span class="font-mono text-green-400 animate-blink select-none">▌</span>
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
.hacker-bg {
  background: #0a0f0a;
}

.hacker-scanlines::after {
  content: '';
  position: absolute;
  inset: 0;
  pointer-events: none;
  background: repeating-linear-gradient(
    0deg,
    transparent,
    transparent 2px,
    rgba(0, 255, 65, 0.02) 2px,
    rgba(0, 255, 65, 0.02) 4px
  );
}

.terminal-input::selection {
  background: rgba(0, 255, 65, 0.3);
}

@keyframes blink {
  0%, 100% { opacity: 1; }
  50% { opacity: 0; }
}

.animate-blink {
  animation: blink 0.8s step-end infinite;
}

.fade-enter-active {
  transition: opacity 0.2s ease-out;
}
.fade-leave-active {
  transition: opacity 0.15s ease-in;
}
.fade-enter-from,
.fade-leave-to {
  opacity: 0;
}
</style>
