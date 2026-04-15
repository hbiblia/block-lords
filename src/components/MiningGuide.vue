<script setup lang="ts">
import { ref, watch, type Component } from 'vue';
import { useI18n } from 'vue-i18n';
import { Pickaxe, Server, Thermometer, Gem, Coins, Zap, BookOpen, X } from 'lucide-vue-next';

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

watch(() => props.show, (shown) => {
  if (shown) openTopic.value = null;
});
</script>

<template>
  <Teleport to="body">
    <Transition name="guide-modal">
      <div v-if="show" class="gm-overlay" @click.self="emit('close')">
        <div class="gm-backdrop" @click="emit('close')"></div>

        <div class="gm-modal">
          <!-- Header -->
          <div class="gm-header">
            <BookOpen :size="16" color="#7b5ea7" />
            <h2 class="gm-header-title">{{ t('guide.title') }}</h2>
            <button @click="emit('close')" class="gm-close"><X :size="14" /></button>
          </div>

          <!-- Content -->
          <div class="gm-content">
            <div v-for="(topic, i) in topics" :key="topic.key" class="gm-topic">
              <button @click="toggleTopic(topic.key)" class="gm-topic-btn" :class="{ 'gm-topic-open': openTopic === topic.key }">
                <span class="gm-topic-num">{{ String(i + 1).padStart(2, '0') }}</span>
                <component :is="topic.icon" :size="16" color="#c4a0e8" />
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
              {{ t('guide.startTour') }}
            </button>
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
@import url('https://fonts.googleapis.com/css2?family=Nunito:wght@400;600;700;800;900&display=swap');

.gm-overlay {
  position: fixed; inset: 0; z-index: 50;
  display: flex; align-items: flex-start; justify-content: center;
  padding: 3rem 1rem;
}
.gm-backdrop {
  position: absolute; inset: 0;
  background: rgba(0,0,0,0.4);
  backdrop-filter: blur(4px);
}

.gm-modal {
  position: relative; width: 100%; max-width: 500px;
  background: #1f1833;
  border: 2px solid #4a3660;
  border-radius: 16px;
  box-shadow: 4px 4px 0 rgba(74,54,96,0.3);
  overflow: hidden;
  font-family: 'Nunito', 'Trebuchet MS', sans-serif;
  animation: gm-enter 0.3s cubic-bezier(0.16,1,0.3,1);
}
@keyframes gm-enter { from { opacity: 0; transform: translateY(-15px); } to { opacity: 1; transform: translateY(0); } }

/* Header */
.gm-header {
  display: flex; align-items: center; gap: 8px;
  padding: 1rem 1.2rem;
  border-bottom: 2px solid #3a2d50;
  background: linear-gradient(180deg, #231d35, #1f1833);
}
.gm-header-title {
  flex: 1; font-size: 1rem; font-weight: 900; color: #f0e4ff;
  letter-spacing: 1px; margin: 0;
}
.gm-close {
  width: 28px; height: 28px;
  display: flex; align-items: center; justify-content: center;
  background: #231d35; border: 2px solid #4a3660; border-radius: 8px;
  color: #8a70a8; cursor: pointer; transition: 0.2s;
}
.gm-close:hover { background: #fff0f0; border-color: #ff7b7b; color: #cc4444; }

/* Content */
.gm-content {
  max-height: 55vh; overflow-y: auto;
  padding: 0.5rem;
}
.gm-content::-webkit-scrollbar { width: 6px; }
.gm-content::-webkit-scrollbar-track { background: #2d2545; }
.gm-content::-webkit-scrollbar-thumb { background: #c4a0e8; border-radius: 3px; }

.gm-topic { border-bottom: 1px solid #3a2d50; }
.gm-topic:last-child { border-bottom: none; }

.gm-topic-btn {
  width: 100%; display: flex; align-items: center; gap: 0.5rem;
  padding: 0.7rem 0.6rem;
  background: transparent; border: none; cursor: pointer;
  border-radius: 8px; transition: all 0.15s;
}
.gm-topic-btn:hover { background: #231d35; }
.gm-topic-open { background: #2d2545; }

.gm-topic-num {
  font-size: 0.75rem; font-weight: 900; color: #c4a0e8;
  font-family: 'Nunito', sans-serif; letter-spacing: 1px;
}
.gm-topic-name {
  flex: 1; text-align: left;
  font-size: 0.85rem; font-weight: 800; color: #b8a0d0;
}
.gm-topic-open .gm-topic-name { color: #f0e4ff; }
.gm-topic-arrow {
  font-size: 0.75rem; color: #c4a0e8; transition: transform 0.2s;
}
.gm-arrow-open { transform: rotate(180deg); color: #b8a0d0; }

.gm-topic-body { padding: 0 0.6rem 0.8rem 2.4rem; }
.gm-topic-text {
  font-size: 0.8rem; font-weight: 600; color: #8a70a8;
  line-height: 1.7; margin: 0;
}

/* Footer */
.gm-footer {
  padding: 0.8rem 1rem;
  border-top: 2px solid #3a2d50;
  background: #231d35;
}
.gm-tour-btn {
  width: 100%; padding: 10px;
  background: #ffe566; border: 2px outset #d4a017;
  border-radius: 8px;
  font-size: 0.8rem; font-weight: 900; color: #1a1528;
  font-family: 'Nunito', sans-serif; letter-spacing: 1.5px;
  cursor: pointer; transition: 0.2s;
}
.gm-tour-btn:hover { background: #ffd700; border-style: inset; }

/* Transitions */
.guide-modal-enter-active, .guide-modal-leave-active { transition: opacity 0.2s ease; }
.guide-modal-enter-from, .guide-modal-leave-to { opacity: 0; }

.accordion-enter-active, .accordion-leave-active { transition: all 0.2s ease; overflow: hidden; }
.accordion-enter-from, .accordion-leave-to { max-height: 0; opacity: 0; }
.accordion-enter-to, .accordion-leave-from { max-height: 200px; opacity: 1; }
</style>
