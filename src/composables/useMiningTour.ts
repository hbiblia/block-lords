import { ref, computed } from 'vue';

export interface TourStep {
  id: string;
  targetId: string;
  placement: 'top' | 'bottom' | 'left' | 'right' | 'center';
  titleKey: string;
  bodyKey: string;
  scrollTo?: boolean;
}

const TOUR_COMPLETED_KEY = 'miningTourCompleted';

export const TOUR_STEPS: TourStep[] = [
  {
    id: 'intro',
    targetId: '',
    placement: 'center',
    titleKey: 'tour.steps.intro.title',
    bodyKey: 'tour.steps.intro.body',
  },
  {
    id: 'welcome',
    targetId: 'tour-dashboard',
    placement: 'bottom',
    titleKey: 'tour.steps.welcome.title',
    bodyKey: 'tour.steps.welcome.body',
  },
  {
    id: 'block-system',
    targetId: 'tour-block-info',
    placement: 'bottom',
    titleKey: 'tour.steps.blockSystem.title',
    bodyKey: 'tour.steps.blockSystem.body',
    scrollTo: true,
  },
  {
    id: 'rig-card',
    targetId: 'tour-rig-first',
    placement: 'right',
    titleKey: 'tour.steps.rigCard.title',
    bodyKey: 'tour.steps.rigCard.body',
    scrollTo: true,
  },
  {
    id: 'temp-condition',
    targetId: 'tour-rig-first',
    placement: 'right',
    titleKey: 'tour.steps.tempCondition.title',
    bodyKey: 'tour.steps.tempCondition.body',
  },
  {
    id: 'start-rig',
    targetId: 'tour-rig-actions',
    placement: 'top',
    titleKey: 'tour.steps.startRig.title',
    bodyKey: 'tour.steps.startRig.body',
    scrollTo: true,
  },
  {
    id: 'sidebar',
    targetId: 'tour-sidebar',
    placement: 'left',
    titleKey: 'tour.steps.sidebar.title',
    bodyKey: 'tour.steps.sidebar.body',
    scrollTo: true,
  },
  {
    id: 'market',
    targetId: 'tour-market-btn',
    placement: 'bottom',
    titleKey: 'tour.steps.market.title',
    bodyKey: 'tour.steps.market.body',
    scrollTo: true,
  },
];

// Module-level singleton state so MiningPage and MiningTour share it
const _currentStepIndex = ref(0);

export function useMiningTour() {
  const currentStep = computed(() => TOUR_STEPS[_currentStepIndex.value] ?? null);
  const isFirstStep = computed(() => _currentStepIndex.value === 0);
  const isLastStep = computed(() => _currentStepIndex.value === TOUR_STEPS.length - 1);
  const progress = computed(() => _currentStepIndex.value + 1);
  const total = computed(() => TOUR_STEPS.length);

  const isCompleted = computed(
    () => localStorage.getItem(TOUR_COMPLETED_KEY) === 'true'
  );

  function next() {
    if (!isLastStep.value) {
      _currentStepIndex.value++;
    }
  }

  function prev() {
    if (!isFirstStep.value) {
      _currentStepIndex.value--;
    }
  }

  function complete() {
    localStorage.setItem(TOUR_COMPLETED_KEY, 'true');
    _currentStepIndex.value = 0;
  }

  function start() {
    _currentStepIndex.value = 0;
  }

  return {
    TOUR_STEPS,
    currentStep,
    currentStepIndex: _currentStepIndex,
    isFirstStep,
    isLastStep,
    progress,
    total,
    isCompleted,
    next,
    prev,
    complete,
    start,
  };
}
