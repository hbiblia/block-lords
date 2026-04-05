<script setup lang="ts">
import { ref, watch, type Component } from 'vue';
import { useI18n } from 'vue-i18n';
import { Pickaxe, Server, Thermometer, Gem, Coins, Zap, BookOpen } from 'lucide-vue-next';

const props = defineProps<{ show: boolean }>();
const emit = defineEmits<{ close: [] }>();

const { t } = useI18n();

const openTopic = ref<string | null>(null);

function toggleTopic(id: string) {
  openTopic.value = openTopic.value === id ? null : id;
}

const topics: { key: string; icon: Component }[] = [
  { key: 'howMining', icon: Pickaxe },
  { key: 'rigsAndSlots', icon: Server },
  { key: 'tempAndCondition', icon: Thermometer },
  { key: 'resources', icon: Gem },
  { key: 'currencies', icon: Coins },
  { key: 'upgradesAndBoosts', icon: Zap },
];

function handleStartTour() {
  emit('close');
  window.dispatchEvent(new CustomEvent('start-mining-tour'));
}

// Reset open topic when modal opens
watch(() => props.show, (shown) => {
  if (shown) openTopic.value = null;
});
</script>

<template>
  <Teleport to="body">
    <Transition name="guide-modal">
      <div
        v-if="show"
        class="gm-overlay"
        @click.self="emit('close')"
      >
        <!-- Backdrop -->
        <div class="gm-backdrop" @click="emit('close')"></div>

        <!-- Modal -->
        <div class="gm-modal">
          <!-- HUD Corners -->
          <div class="gm-c gm-c-tl"></div>
          <div class="gm-c gm-c-tr"></div>
          <div class="gm-c gm-c-bl"></div>
          <div class="gm-c gm-c-br"></div>
          <div class="gm-scanline"></div>
          <div class="gm-crt"></div>

          <!-- Header -->
          <div class="gm-header">
            <BookOpen :size="16" color="#f59e0b" />
            <h2 class="gm-header-title">{{ t('guide.title') }}</h2>
            <span class="gm-header-tag">GUIDE</span>
            <button @click="emit('close')" class="gm-close">ESC</button>
          </div>

          <!-- Content -->
          <div class="gm-content">
            <div v-for="(topic, i) in topics" :key="topic.key" class="gm-topic">
              <button @click="toggleTopic(topic.key)" class="gm-topic-btn" :class="{ 'gm-topic-open': openTopic === topic.key }">
                <span class="gm-topic-num">{{ String(i + 1).padStart(2, '0') }}</span>
                <component :is="topic.icon" :size="16" color="#f59e0b" class="gm-topic-icon" />
                <span class="gm-topic-name">{{ t(`guide.topics.${topic.key}.title`) }}</span>
                <span class="gm-topic-arrow" :class="{ 'gm-arrow-open': openTopic === topic.key }">&#9662;</span>
              </button>
              <Transition name="accordion">
                <div v-if="openTopic === topic.key" class="gm-topic-body">
                  <p class="gm-topic-text">{{ t(`guide.topics.${topic.key}.body`) }}</p>
                </div>
              </Transition>
            </div>
          </div>

          <!-- Footer -->
          <div class="gm-footer">
            <button @click="handleStartTour" class="gm-tour-btn">
              <span class="gm-tour-dot"></span>
              <span class="gm-tour-text">{{ t('guide.startTour') }}</span>
            </button>
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
.gm-overlay {
  position: fixed; inset: 0; z-index: 50;
  display: flex; align-items: flex-start; justify-content: center;
  padding: 3rem 1rem;
}
.gm-backdrop {
  position: absolute; inset: 0;
  background: rgba(0,0,0,0.7);
  backdrop-filter: blur(4px);
}

.gm-modal {
  position: relative; width: 100%; max-width: 500px;
  border: 1px solid #2f3052;
  background: linear-gradient(135deg, rgba(16,17,35,0.99) 0%, rgba(26,27,46,0.98) 100%);
  overflow: hidden;
  animation: gm-enter 0.3s cubic-bezier(0.16,1,0.3,1);
}
@keyframes gm-enter { from { opacity: 0; transform: translateY(-15px); } to { opacity: 1; transform: translateY(0); } }

.gm-crt {
  position: absolute; inset: 0; pointer-events: none; z-index: 0;
  background: repeating-linear-gradient(0deg, transparent, transparent 3px, rgba(255,255,255,0.005) 3px, rgba(255,255,255,0.005) 4px);
}

/* Corners */
.gm-c { position: absolute; width: 10px; height: 10px; pointer-events: none; z-index: 3; }
.gm-c-tl { top: 0; left: 0; border-top: 2px solid #f59e0b; border-left: 2px solid #f59e0b; }
.gm-c-tr { top: 0; right: 0; border-top: 2px solid #f59e0b; border-right: 2px solid #f59e0b; }
.gm-c-bl { bottom: 0; left: 0; border-bottom: 2px solid #f59e0b; border-left: 2px solid #f59e0b; }
.gm-c-br { bottom: 0; right: 0; border-bottom: 2px solid #f59e0b; border-right: 2px solid #f59e0b; }

.gm-scanline {
  position: absolute; top: 0; left: -100%; width: 100%; height: 100%;
  pointer-events: none; z-index: 1;
  background: linear-gradient(90deg, transparent 0%, rgba(245,158,11,0.02) 45%, rgba(245,158,11,0.05) 50%, rgba(245,158,11,0.02) 55%, transparent 100%);
  animation: gm-scan 5s linear infinite;
}
@keyframes gm-scan { 0% { left: -100%; } 100% { left: 100%; } }

/* Header */
.gm-header {
  display: flex; align-items: center; gap: 8px;
  padding: 0.6rem 0.8rem;
  border-bottom: 1px solid #2f3052;
  position: relative; z-index: 2;
  background: linear-gradient(180deg, rgba(245,158,11,0.03) 0%, transparent 100%);
}
@keyframes gm-pulse { 0%,100% { opacity: 1; } 50% { opacity: 0.3; } }
.gm-header-title {
  flex: 1; font-size: 0.95rem; font-weight: 900; color: #f59e0b;
  letter-spacing: 2px; margin: 0;
  text-shadow: 0 0 10px rgba(245,158,11,0.2);
}
.gm-header-tag {
  font-size: 0.6rem; font-weight: 900; color: #4f4f6f; letter-spacing: 2px;
  padding: 2px 6px; border: 1px solid #2f3052;
}
.gm-close {
  font-size: 0.6rem; font-weight: 900; color: #4f4f6f; letter-spacing: 1px;
  padding: 2px 6px; border: 1px solid #2f3052;
  background: transparent; cursor: pointer;
  transition: all 0.2s;
}
.gm-close:hover { color: #ef4444; border-color: #ef444440; }

/* Content */
.gm-content {
  max-height: 55vh; overflow-y: auto;
  padding: 0.5rem;
  position: relative; z-index: 2;
}
.gm-content::-webkit-scrollbar { width: 2px; }
.gm-content::-webkit-scrollbar-thumb { background: #3f3f5c; }

.gm-topic { border-bottom: 1px solid #1a1b2e; }
.gm-topic:last-child { border-bottom: none; }

.gm-topic-btn {
  width: 100%; display: flex; align-items: center; gap: 0.5rem;
  padding: 0.6rem 0.4rem;
  background: transparent; border: none; cursor: pointer;
  transition: all 0.15s;
}
.gm-topic-btn:hover { background: rgba(245,158,11,0.03); }
.gm-topic-open { background: rgba(245,158,11,0.05); }

.gm-topic-num {
  font-size: 0.75rem; font-weight: 900; color: #4f4f6f;
  font-family: 'JetBrains Mono', monospace;
  letter-spacing: 1px;
}
.gm-topic-icon { flex-shrink: 0; opacity: 0.85; }
.gm-topic-name {
  flex: 1; text-align: left;
  font-size: 0.9rem; font-weight: 800; color: #a1a1aa;
  letter-spacing: 0.5px;
}
.gm-topic-open .gm-topic-name { color: #e5e7eb; }
.gm-topic-arrow {
  font-size: 0.75rem; color: #4f4f6f;
  transition: transform 0.2s;
}
.gm-arrow-open { transform: rotate(180deg); color: #f59e0b; }

.gm-topic-body {
  padding: 0 0.4rem 0.6rem 2.2rem;
}
.gm-topic-text {
  font-size: 0.85rem; font-weight: 600; color: #71717a;
  line-height: 1.7; margin: 0;
}

/* Footer */
.gm-footer {
  padding: 0.6rem 0.8rem;
  border-top: 1px solid #2f3052;
  position: relative; z-index: 2;
}
.gm-tour-btn {
  width: 100%; display: flex; align-items: center; justify-content: center; gap: 0.5rem;
  padding: 0.5rem;
  border: 1px solid #f59e0b;
  background: linear-gradient(135deg, rgba(245,158,11,0.1) 0%, rgba(245,158,11,0.05) 100%);
  cursor: pointer;
  transition: all 0.3s;
}
.gm-tour-btn:hover {
  background: linear-gradient(135deg, rgba(245,158,11,0.2) 0%, rgba(245,158,11,0.1) 100%);
  box-shadow: 0 0 15px rgba(245,158,11,0.15);
}
.gm-tour-dot {
  width: 5px; height: 5px; background: #f59e0b; border-radius: 50%;
  box-shadow: 0 0 6px #f59e0b80;
  animation: gm-pulse 1.5s infinite;
}
.gm-tour-text {
  font-size: 0.85rem; font-weight: 900; color: #f59e0b;
  letter-spacing: 2px;
}

/* Transitions */
.guide-modal-enter-active, .guide-modal-leave-active { transition: opacity 0.2s ease; }
.guide-modal-enter-from, .guide-modal-leave-to { opacity: 0; }

.accordion-enter-active, .accordion-leave-active { transition: all 0.2s ease; overflow: hidden; }
.accordion-enter-from, .accordion-leave-to { max-height: 0; opacity: 0; }
.accordion-enter-to, .accordion-leave-from { max-height: 200px; opacity: 1; }
</style>
