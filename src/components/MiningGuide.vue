<script setup lang="ts">
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps<{ show: boolean }>();
const emit = defineEmits<{ close: [] }>();

const { t } = useI18n();

const openTopic = ref<string | null>(null);

function toggleTopic(id: string) {
  openTopic.value = openTopic.value === id ? null : id;
}

const topics = [
  'howMining',
  'rigsAndSlots',
  'tempAndCondition',
  'resources',
  'currencies',
  'upgradesAndBoosts',
] as const;

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
        class="fixed inset-0 z-50 flex items-start justify-center p-4 pt-12 sm:pt-20"
        @click.self="emit('close')"
      >
        <!-- Backdrop -->
        <div class="absolute inset-0 bg-black/70 backdrop-blur-sm" @click="emit('close')" />

        <!-- Modal -->
        <div class="relative w-full max-w-lg bg-bg-card border border-border/50 rounded-2xl shadow-2xl shadow-black/60 overflow-hidden">
          <!-- Header -->
          <div class="flex items-center justify-between px-5 py-4 border-b border-border/30">
            <h2 class="text-base font-bold text-text-primary flex items-center gap-2">
              <span class="text-lg">📖</span> {{ t('guide.title') }}
            </h2>
            <button
              @click="emit('close')"
              class="w-8 h-8 rounded-full flex items-center justify-center text-text-muted hover:text-text-primary hover:bg-bg-secondary transition-colors"
            >
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M6 18L18 6M6 6l12 12"/>
              </svg>
            </button>
          </div>

          <!-- Content -->
          <div class="px-5 py-4 max-h-[60vh] overflow-y-auto space-y-1">
            <div v-for="topic in topics" :key="topic">
              <button
                @click="toggleTopic(topic)"
                class="w-full flex items-center justify-between px-3 py-2.5 rounded-lg text-sm font-medium transition-colors hover:bg-bg-secondary/60"
                :class="openTopic === topic ? 'bg-bg-secondary/60 text-text-primary' : 'text-text-muted'"
              >
                <span class="flex items-center gap-2">
                  <span>{{ t(`guide.topics.${topic}.icon`) }}</span>
                  <span>{{ t(`guide.topics.${topic}.title`) }}</span>
                </span>
                <span class="text-xs transition-transform duration-150 inline-block"
                      :class="openTopic === topic ? 'rotate-180' : 'rotate-0'">▾</span>
              </button>
              <Transition name="accordion">
                <div v-if="openTopic === topic"
                     class="px-4 pb-3 pt-1.5 text-xs text-text-muted leading-relaxed">
                  <p>{{ t(`guide.topics.${topic}.body`) }}</p>
                </div>
              </Transition>
            </div>
          </div>

          <!-- Footer -->
          <div class="px-5 py-4 border-t border-border/30">
            <button
              @click="handleStartTour"
              class="w-full flex items-center justify-center gap-2 px-4 py-2.5 rounded-xl text-sm font-semibold
                     bg-accent-primary/10 hover:bg-accent-primary/20 text-accent-primary transition-colors"
            >
              🗺️ {{ t('guide.startTour') }}
            </button>
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
.guide-modal-enter-active,
.guide-modal-leave-active {
  transition: opacity 0.2s ease;
}
.guide-modal-enter-from,
.guide-modal-leave-to {
  opacity: 0;
}

.accordion-enter-active,
.accordion-leave-active {
  transition: all 0.2s ease;
  overflow: hidden;
}
.accordion-enter-from,
.accordion-leave-to {
  max-height: 0;
  opacity: 0;
}
.accordion-enter-to,
.accordion-leave-from {
  max-height: 200px;
  opacity: 1;
}
</style>
