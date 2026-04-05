<script setup lang="ts">
import { ref, computed, watch } from 'vue';
import type { StoryChapter } from '@/data/storyChapters';

const props = defineProps<{
  show: boolean;
  chapter: StoryChapter | null;
}>();

const emit = defineEmits<{
  close: [];
}>();

const currentLine = ref(0);
const displayedText = ref('');
const typing = ref(false);
let typeTimer: ReturnType<typeof setTimeout> | null = null;

const visibleLines = computed(() => {
  if (!props.chapter) return [];
  return props.chapter.lines.slice(0, currentLine.value + 1);
});

const isLastLine = computed(() => {
  if (!props.chapter) return false;
  return currentLine.value >= props.chapter.lines.length - 1;
});

const currentSpeaker = computed(() => {
  if (!props.chapter || currentLine.value >= props.chapter.lines.length) return '';
  return props.chapter.lines[currentLine.value].speaker;
});

watch(() => props.show, (v) => {
  if (v) {
    currentLine.value = 0;
    displayedText.value = '';
    startTyping();
  } else {
    if (typeTimer) clearTimeout(typeTimer);
  }
});

function startTyping() {
  if (!props.chapter) return;
  const line = props.chapter.lines[currentLine.value];
  if (!line) return;
  displayedText.value = '';
  typing.value = true;
  let i = 0;
  function typeNext() {
    if (i < line.text.length) {
      displayedText.value += line.text[i];
      i++;
      typeTimer = setTimeout(typeNext, 22);
    } else {
      typing.value = false;
    }
  }
  typeNext();
}

function advance() {
  if (typing.value) {
    // Skip typing, show full text
    if (typeTimer) clearTimeout(typeTimer);
    if (props.chapter) {
      displayedText.value = props.chapter.lines[currentLine.value].text;
    }
    typing.value = false;
    return;
  }
  if (isLastLine.value) {
    emit('close');
    return;
  }
  currentLine.value++;
  startTyping();
}

function getSpeakerColor(speaker: string): string {
  switch (speaker) {
    case 'COMMAND': return '#f59e0b';
    case 'AI_CORE': return '#06b6d4';
    case 'YOU': return '#22c55e';
    case 'ALERT': return '#ef4444';
    case 'POOL_LEAD': return '#a78bfa';
    case 'MERCHANT': return '#fbbf24';
    case 'UNKNOWN': return '#ef4444';
    case 'UNKNOWN_SIGNAL': return '#818cf8';
    default: return '#a1a1aa';
  }
}
</script>

<template>
  <Teleport to="body">
    <div v-if="show && chapter" class="sm-overlay" @click="advance">
      <div class="sm-modal" @click.stop="advance">
        <!-- HUD Corners -->
        <div class="sm-c sm-tl"></div>
        <div class="sm-c sm-tr"></div>
        <div class="sm-c sm-bl"></div>
        <div class="sm-c sm-br"></div>
        <div class="sm-scan"></div>

        <!-- Header -->
        <div class="sm-header">
          <span class="sm-chap">CHAPTER {{ chapter.level }}</span>
          <span class="sm-title">{{ chapter.title }}</span>
          <span class="sm-level">LVL {{ chapter.level }}</span>
        </div>

        <!-- Dialogue area -->
        <div class="sm-dialogue">
          <!-- Previous lines (faded) -->
          <div
            v-for="(line, i) in visibleLines.slice(0, -1)"
            :key="i"
            class="sm-line sm-line-past"
          >
            <span class="sm-speaker" :style="{ color: getSpeakerColor(line.speaker) }">{{ line.speaker }}://</span>
            <span class="sm-text">{{ line.text }}</span>
          </div>

          <!-- Current line (typing) -->
          <div v-if="chapter.lines[currentLine]" class="sm-line sm-line-current">
            <span class="sm-speaker" :style="{ color: getSpeakerColor(currentSpeaker) }">{{ currentSpeaker }}://</span>
            <span class="sm-text">{{ displayedText }}<span v-if="typing" class="sm-cursor">█</span></span>
          </div>
        </div>

        <!-- Footer -->
        <div class="sm-footer">
          <span class="sm-progress">{{ currentLine + 1 }}/{{ chapter.lines.length }}</span>
          <span class="sm-hint">{{ isLastLine && !typing ? '[ CLICK TO CLOSE ]' : typing ? '[ CLICK TO SKIP ]' : '[ CLICK TO CONTINUE ]' }}</span>
          <span class="sm-indicator"></span>
        </div>
      </div>
    </div>
  </Teleport>
</template>

<style scoped>
.sm-overlay {
  position: fixed; inset: 0; z-index: 100; display: flex; align-items: flex-end; justify-content: center;
  background: linear-gradient(0deg, rgba(0,0,0,0.85) 0%, rgba(0,0,0,0.4) 40%, transparent 100%);
  padding: 2rem 1rem;
  cursor: pointer;
}

.sm-modal {
  position: relative; width: 100%; max-width: 700px;
  background: linear-gradient(135deg, rgba(16,17,35,0.98) 0%, rgba(26,27,46,0.96) 100%);
  border: 1px solid #2f3052; overflow: hidden;
  animation: sm-enter 0.4s cubic-bezier(0.16,1,0.3,1);
}
.sm-modal::before {
  content: ''; position: absolute; inset: 0; pointer-events: none;
  background: repeating-linear-gradient(0deg, transparent, transparent 3px, rgba(255,255,255,0.005) 3px, rgba(255,255,255,0.005) 4px);
}
@keyframes sm-enter { from { opacity: 0; transform: translateY(20px); } to { opacity: 1; transform: translateY(0); } }

/* Corners */
.sm-c { position: absolute; width: 12px; height: 12px; pointer-events: none; z-index: 3; }
.sm-tl { top: 0; left: 0; border-top: 2px solid #f59e0b; border-left: 2px solid #f59e0b; }
.sm-tr { top: 0; right: 0; border-top: 2px solid #f59e0b; border-right: 2px solid #f59e0b; }
.sm-bl { bottom: 0; left: 0; border-bottom: 2px solid #f59e0b; border-left: 2px solid #f59e0b; }
.sm-br { bottom: 0; right: 0; border-bottom: 2px solid #f59e0b; border-right: 2px solid #f59e0b; }

/* Scanline */
.sm-scan {
  position: absolute; top: 0; left: -100%; width: 100%; height: 100%; pointer-events: none; z-index: 1;
  background: linear-gradient(90deg, transparent 0%, rgba(245,158,11,0.02) 45%, rgba(245,158,11,0.05) 50%, rgba(245,158,11,0.02) 55%, transparent 100%);
  animation: sm-scanmove 5s linear infinite;
}
@keyframes sm-scanmove { 0% { left: -100%; } 100% { left: 100%; } }

/* Header */
.sm-header {
  display: flex; align-items: center; gap: 10px; padding: 0.6rem 0.8rem;
  border-bottom: 1px solid #2f3052; position: relative; z-index: 2;
  background: linear-gradient(180deg, rgba(245,158,11,0.03) 0%, transparent 100%);
}
.sm-chap { font-size: 0.4rem; font-weight: 900; color: #4f4f6f; letter-spacing: 2.5px; }
.sm-title { flex: 1; font-size: 0.75rem; font-weight: 900; color: #f59e0b; letter-spacing: 2px; text-shadow: 0 0 10px rgba(245,158,11,0.2); }
.sm-level { font-size: 0.4rem; font-weight: 900; color: #4f4f6f; letter-spacing: 1.5px; padding: 2px 6px; border: 1px solid #2f3052; }

/* Dialogue */
.sm-dialogue {
  padding: 1rem 0.8rem; min-height: 120px; max-height: 250px; overflow-y: auto;
  display: flex; flex-direction: column; gap: 0.6rem; position: relative; z-index: 2;
}
.sm-dialogue::-webkit-scrollbar { width: 2px; }
.sm-dialogue::-webkit-scrollbar-thumb { background: #3f3f5c; }

.sm-line { display: flex; gap: 8px; align-items: flex-start; }
.sm-line-past { opacity: 0.4; }
.sm-line-current { animation: sm-line-in 0.2s ease; }
@keyframes sm-line-in { from { opacity: 0; transform: translateX(-5px); } to { opacity: 1; transform: translateX(0); } }

.sm-speaker {
  font-size: 0.5rem; font-weight: 900; letter-spacing: 1.5px; white-space: nowrap;
  flex-shrink: 0; padding-top: 2px; font-family: 'JetBrains Mono', monospace;
}
.sm-text { font-size: 0.75rem; font-weight: 600; color: #e5e7eb; line-height: 1.5; }
.sm-cursor { color: #f59e0b; animation: sm-blink 0.6s infinite; }
@keyframes sm-blink { 0%,49% { opacity: 1; } 50%,100% { opacity: 0; } }

/* Footer */
.sm-footer {
  display: flex; align-items: center; gap: 8px; padding: 0.5rem 0.8rem;
  border-top: 1px solid #2f3052; position: relative; z-index: 2;
}
.sm-progress { font-size: 0.4rem; font-weight: 900; color: #4f4f6f; letter-spacing: 1.5px; font-family: 'JetBrains Mono', monospace; }
.sm-hint { flex: 1; text-align: center; font-size: 0.4rem; font-weight: 900; color: #71717a; letter-spacing: 2px; animation: sm-hint-pulse 2s infinite; }
@keyframes sm-hint-pulse { 0%,100% { opacity: 0.5; } 50% { opacity: 1; } }
.sm-indicator { width: 5px; height: 5px; background: #f59e0b; clip-path: polygon(50% 0%, 100% 50%, 50% 100%, 0% 50%); animation: sm-blink 1.5s infinite; }

/* Mobile */
@media (max-width: 600px) {
  .sm-overlay { padding: 1rem 0.5rem; }
  .sm-dialogue { min-height: 100px; max-height: 200px; }
  .sm-text { font-size: 0.65rem; }
}
</style>
