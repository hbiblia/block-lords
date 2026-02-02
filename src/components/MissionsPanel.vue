<script setup lang="ts">
import { watch, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMissionsStore } from '@/stores/missions';
import { playSound } from '@/utils/sounds';

const { t } = useI18n();
const missionsStore = useMissionsStore();

const props = defineProps<{
  show: boolean;
}>();

const emit = defineEmits<{
  close: [];
}>();

// Bloquear scroll del body cuando el modal está abierto
watch(() => props.show, (isOpen) => {
  if (isOpen) {
    document.body.style.overflow = 'hidden';
    missionsStore.fetchMissions();
  } else {
    document.body.style.overflow = '';
  }
});

onUnmounted(() => {
  document.body.style.overflow = '';
});

async function handleClaim(missionId: string) {
  const result = await missionsStore.claimReward(missionId);
  if (result) {
    playSound('mission_complete');
  }
}

function handleClose() {
  missionsStore.closePanel();
  emit('close');
}

function formatProgress(progress: number, target: number): string {
  if (target >= 1) {
    return `${Math.floor(progress)}/${Math.floor(target)}`;
  }
  return `${progress.toFixed(2)}/${target.toFixed(2)}`;
}
</script>

<template>
  <Teleport to="body">
    <div
      v-if="show"
      class="fixed inset-0 z-50 flex items-center justify-center p-4"
    >
      <!-- Backdrop -->
      <div
        class="absolute inset-0 bg-black/70 backdrop-blur-sm"
        @click="handleClose"
      ></div>

      <!-- Modal -->
      <div class="relative w-full max-w-lg max-h-[85vh] overflow-hidden card animate-fade-in">
        <!-- Header -->
        <div class="flex items-center justify-between p-4 border-b border-border/50">
          <div class="flex items-center gap-3">
            <div class="text-3xl">🎯</div>
            <div>
              <h2 class="text-xl font-display font-bold">
                <span class="gradient-text">{{ t('missions.title') }}</span>
              </h2>
              <p class="text-sm text-text-muted">
                {{ missionsStore.completedCount }}/{{ missionsStore.totalCount }} {{ t('missions.completed') }}
              </p>
            </div>
          </div>
          <button
            @click="handleClose"
            class="w-8 h-8 rounded-lg bg-bg-tertiary hover:bg-bg-secondary flex items-center justify-center transition-colors"
          >
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        <!-- Content -->
        <div class="p-4 overflow-y-auto max-h-[60vh]">
          <!-- Loading -->
          <div v-if="missionsStore.loading" class="text-center py-12 text-text-muted">
            {{ t('missions.loading') }}
          </div>

          <!-- Missions List -->
          <div v-else class="space-y-3">
            <div
              v-for="mission in missionsStore.missions"
              :key="mission.id"
              class="bg-bg-secondary rounded-xl p-4 border-l-4 transition-all"
              :class="{
                'border-status-success opacity-75': mission.isClaimed,
                'border-accent-primary': mission.isCompleted && !mission.isClaimed,
                'border-border/50': !mission.isCompleted,
              }"
            >
              <!-- Header -->
              <div class="flex items-start justify-between gap-3 mb-2">
                <div class="flex items-center gap-2">
                  <span class="text-2xl">{{ mission.icon }}</span>
                  <div>
                    <h3 class="font-medium">{{ t(`missions.items.${mission.missionId}.name`) }}</h3>
                    <p class="text-xs text-text-muted">{{ t(`missions.items.${mission.missionId}.desc`) }}</p>
                  </div>
                </div>
                <span
                  class="text-xs px-2 py-0.5 rounded-full font-medium"
                  :class="missionsStore.getDifficultyBg(mission.difficulty) + ' ' + missionsStore.getDifficultyColor(mission.difficulty)"
                >
                  {{ t(`missions.difficulty.${mission.difficulty}`) }}
                </span>
              </div>

              <!-- Progress Bar -->
              <div class="mb-3">
                <div class="flex items-center justify-between text-xs mb-1">
                  <span class="text-text-muted">{{ t('missions.progress') }}</span>
                  <span class="font-mono" :class="mission.isCompleted ? 'text-status-success' : ''">
                    {{ formatProgress(mission.progress, mission.targetValue) }}
                  </span>
                </div>
                <div class="h-2 bg-bg-tertiary rounded-full overflow-hidden">
                  <div
                    class="h-full rounded-full transition-all duration-300"
                    :class="mission.isCompleted ? 'bg-status-success' : 'bg-gradient-primary'"
                    :style="{ width: `${mission.progressPercent}%` }"
                  ></div>
                </div>
              </div>

              <!-- Reward & Action -->
              <div class="flex items-center justify-between">
                <div class="flex items-center gap-2">
                  <span class="text-lg">{{ missionsStore.getRewardIcon(mission.rewardType) }}</span>
                  <span class="font-bold" :class="mission.rewardType === 'crypto' ? 'text-accent-primary' : 'text-status-warning'">
                    +{{ mission.rewardAmount }}
                  </span>
                </div>

                <button
                  v-if="mission.isCompleted && !mission.isClaimed"
                  @click="handleClaim(mission.id)"
                  :disabled="missionsStore.claiming"
                  class="px-4 py-1.5 rounded-lg bg-accent-primary text-white font-medium text-sm hover:bg-accent-primary/80 transition-colors disabled:opacity-50"
                >
                  {{ missionsStore.claiming ? '...' : t('missions.claim') }}
                </button>
                <span
                  v-else-if="mission.isClaimed"
                  class="text-xs text-status-success font-medium flex items-center gap-1"
                >
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
                  </svg>
                  {{ t('missions.claimed') }}
                </span>
                <span v-else class="text-xs text-text-muted">
                  {{ mission.progressPercent }}%
                </span>
              </div>
            </div>

            <!-- Empty State -->
            <div v-if="missionsStore.missions.length === 0" class="text-center py-8 text-text-muted">
              <div class="text-4xl mb-3">📋</div>
              <p>{{ t('missions.noMissions') }}</p>
              <p class="text-xs mt-1">{{ t('missions.comeBackTomorrow') }}</p>
            </div>
          </div>
        </div>

        <!-- Footer -->
        <div class="p-4 border-t border-border/50 bg-bg-secondary">
          <div class="flex items-center justify-between text-sm">
            <div class="flex items-center gap-2 text-text-muted">
              <span>⏱️</span>
              <span>{{ t('missions.onlineTimeToday') }} <strong class="text-white">{{ missionsStore.onlineMinutes }} {{ t('missions.min') }}</strong></span>
            </div>
            <div v-if="missionsStore.claimableCount > 0" class="text-accent-primary font-medium">
              {{ missionsStore.claimableCount }} {{ t('missions.toClaim') }}
            </div>
          </div>
        </div>
      </div>
    </div>
  </Teleport>
</template>
