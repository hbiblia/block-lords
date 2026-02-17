<script setup lang="ts">
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';

const emit = defineEmits<{
  startTour: [];
}>();

const { t } = useI18n();

const guideCollapsed = ref(localStorage.getItem('guideCollapsed') !== 'false');

function toggleGuide() {
  guideCollapsed.value = !guideCollapsed.value;
  localStorage.setItem('guideCollapsed', String(guideCollapsed.value));
}

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
</script>

<template>
  <div class="card p-3">
    <div class="flex items-center justify-between mb-2">
      <h3 class="text-sm font-semibold flex items-center gap-1.5 text-text-muted">
        <span>📖</span> {{ t('guide.title') }}
      </h3>
      <button
        @click="toggleGuide"
        class="text-text-muted hover:text-white transition-colors p-0.5 rounded"
        :title="guideCollapsed ? t('guide.show') : t('guide.hide')"
      >
        <span class="text-xs transition-transform duration-200 inline-block"
              :class="guideCollapsed ? 'rotate-180' : 'rotate-0'">▲</span>
      </button>
    </div>

    <div v-if="!guideCollapsed" class="space-y-1">
      <div v-for="topic in topics" :key="topic">
        <button
          @click="toggleTopic(topic)"
          class="w-full flex items-center justify-between px-2.5 py-2 rounded-lg text-xs font-medium transition-colors hover:bg-bg-secondary/60"
          :class="openTopic === topic ? 'bg-bg-secondary/60 text-text-primary' : 'text-text-muted'"
        >
          <span class="flex items-center gap-2">
            <span>{{ t(`guide.topics.${topic}.icon`) }}</span>
            <span>{{ t(`guide.topics.${topic}.title`) }}</span>
          </span>
          <span class="text-[10px] transition-transform duration-150 inline-block"
                :class="openTopic === topic ? 'rotate-180' : 'rotate-0'">▾</span>
        </button>
        <Transition name="accordion">
          <div v-if="openTopic === topic"
               class="px-3 pb-2.5 pt-1 text-[11px] text-text-muted leading-relaxed">
            <p>{{ t(`guide.topics.${topic}.body`) }}</p>
          </div>
        </Transition>
      </div>

      <div class="pt-2 mt-1 border-t border-border/30">
        <button
          @click="emit('startTour')"
          class="w-full flex items-center justify-center gap-2 px-3 py-2 rounded-lg text-xs font-semibold
                 bg-accent-primary/10 hover:bg-accent-primary/20 text-accent-primary transition-colors"
        >
          🗺️ {{ t('guide.startTour') }}
        </button>
      </div>
    </div>
  </div>
</template>

<style scoped>
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
