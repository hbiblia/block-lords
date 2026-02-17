<script setup lang="ts">
import { ref, watch, nextTick, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMiningTour } from '@/composables/useMiningTour';

const props = defineProps<{ show: boolean }>();
const emit = defineEmits<{ close: [] }>();

const { t } = useI18n();
const tour = useMiningTour();

const calloutStyle = ref<Record<string, string>>({});
const highlightedEl = ref<HTMLElement | null>(null);

function positionCallout() {
  const step = tour.currentStep.value;
  if (!step) return;

  const el = document.getElementById(step.targetId);

  // Remove previous highlight
  if (highlightedEl.value && highlightedEl.value !== el) {
    highlightedEl.value.classList.remove('tour-highlight');
  }

  if (!el) {
    highlightedEl.value = null;
    calloutStyle.value = {
      top: '50%',
      left: '50%',
      transform: 'translate(-50%, -50%)',
      width: '320px',
      position: 'fixed',
    };
    return;
  }

  if (step.scrollTo) {
    el.scrollIntoView({ behavior: 'smooth', block: 'center' });
  }

  el.classList.add('tour-highlight');
  highlightedEl.value = el;

  const delay = step.scrollTo ? 400 : 50;
  setTimeout(() => {
    const rect = el.getBoundingClientRect();
    const cardW = 320;
    const cardH = 200;
    const margin = 16;
    const vw = window.innerWidth;
    const vh = window.innerHeight;

    let style: Record<string, string> = {};

    // Mobile fallback: always center
    const placement = vw < 640 ? 'center' : step.placement;

    switch (placement) {
      case 'bottom':
        style = {
          top: `${Math.min(rect.bottom + margin, vh - cardH - margin)}px`,
          left: `${Math.max(margin, Math.min(rect.left + rect.width / 2 - cardW / 2, vw - cardW - margin))}px`,
        };
        break;
      case 'top':
        style = {
          top: `${Math.max(margin, rect.top - cardH - margin)}px`,
          left: `${Math.max(margin, Math.min(rect.left + rect.width / 2 - cardW / 2, vw - cardW - margin))}px`,
        };
        break;
      case 'right':
        style = {
          top: `${Math.max(margin, Math.min(rect.top + rect.height / 2 - cardH / 2, vh - cardH - margin))}px`,
          left: `${Math.min(rect.right + margin, vw - cardW - margin)}px`,
        };
        break;
      case 'left':
        style = {
          top: `${Math.max(margin, Math.min(rect.top + rect.height / 2 - cardH / 2, vh - cardH - margin))}px`,
          left: `${Math.max(margin, rect.left - cardW - margin)}px`,
        };
        break;
      case 'center':
      default:
        style = {
          top: '50%',
          left: '50%',
          transform: 'translate(-50%, -50%)',
        };
    }

    calloutStyle.value = { ...style, width: `${cardW}px`, position: 'fixed' };
  }, delay);
}

watch(() => tour.currentStep.value, () => {
  nextTick(positionCallout);
});

watch(() => props.show, (shown) => {
  if (shown) {
    tour.start();
    nextTick(positionCallout);
  } else {
    if (highlightedEl.value) {
      highlightedEl.value.classList.remove('tour-highlight');
      highlightedEl.value = null;
    }
  }
}, { immediate: true });

onUnmounted(() => {
  if (highlightedEl.value) {
    highlightedEl.value.classList.remove('tour-highlight');
  }
});

function handleNext() {
  if (tour.isLastStep.value) {
    tour.complete();
    emit('close');
  } else {
    tour.next();
  }
}

function handleSkip() {
  if (highlightedEl.value) {
    highlightedEl.value.classList.remove('tour-highlight');
    highlightedEl.value = null;
  }
  tour.complete();
  emit('close');
}
</script>

<template>
  <Teleport to="body">
    <Transition name="tour-fade">
      <div v-if="show" class="fixed inset-0 z-[300] pointer-events-none">
        <!-- Callout card -->
        <div
          class="pointer-events-auto bg-bg-secondary border border-accent-primary/50 rounded-2xl shadow-2xl shadow-black/60 p-5"
          :style="calloutStyle"
        >
          <!-- Progress dots -->
          <div class="flex items-center justify-between mb-3">
            <div class="flex gap-1">
              <div
                v-for="(_, i) in tour.TOUR_STEPS"
                :key="i"
                class="h-1 rounded-full transition-all duration-300"
                :class="[
                  i === tour.currentStepIndex.value
                    ? 'w-4 bg-accent-primary'
                    : i < tour.currentStepIndex.value
                      ? 'w-2 bg-accent-primary/50'
                      : 'w-2 bg-border'
                ]"
              />
            </div>
            <span class="text-[10px] text-text-muted font-mono">
              {{ tour.progress.value }}/{{ tour.total.value }}
            </span>
          </div>

          <!-- Step title -->
          <h3 class="text-sm font-bold text-text-primary mb-1.5">
            {{ t(tour.currentStep.value?.titleKey ?? '') }}
          </h3>

          <!-- Step body -->
          <p class="text-xs text-text-muted leading-relaxed mb-4">
            {{ t(tour.currentStep.value?.bodyKey ?? '') }}
          </p>

          <!-- Navigation -->
          <div class="flex items-center justify-between gap-2">
            <button
              @click="handleSkip"
              class="text-xs text-text-muted hover:text-text-primary transition-colors"
            >
              {{ t('tour.skip') }}
            </button>
            <div class="flex gap-2">
              <button
                v-if="!tour.isFirstStep.value"
                @click="tour.prev()"
                class="px-3 py-1.5 rounded-lg text-xs font-medium bg-bg-tertiary hover:bg-bg-tertiary/80 transition-colors"
              >
                {{ t('tour.prev') }}
              </button>
              <button
                @click="handleNext"
                class="px-4 py-1.5 rounded-lg text-xs font-semibold bg-accent-primary text-black hover:bg-accent-secondary transition-colors"
              >
                {{ tour.isLastStep.value ? t('tour.finish') : t('tour.next') }}
              </button>
            </div>
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
.tour-fade-enter-active,
.tour-fade-leave-active {
  transition: opacity 0.3s ease;
}
.tour-fade-enter-from,
.tour-fade-leave-to {
  opacity: 0;
}
</style>
