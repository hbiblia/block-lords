<script setup lang="ts">
import { computed, watch, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStreakStore } from '@/stores/streak';

const { t } = useI18n();
const streakStore = useStreakStore();

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
    streakStore.fetchStatus();
  } else {
    document.body.style.overflow = '';
  }
});

onUnmounted(() => {
  document.body.style.overflow = '';
});

// Días de recompensas principales para mostrar
const mainRewardDays = [1, 2, 3, 4, 5, 6, 7, 14, 21, 30];

const rewards = computed(() => {
  const allRewards = streakStore.status?.allRewards ?? [];
  return mainRewardDays.map(day => {
    const reward = allRewards.find(r => r.day === day);
    return reward ?? {
      day,
      gamecoin: day * 10,
      crypto: 0,
      itemType: null,
      itemId: null,
      description: `Día ${day}`,
    };
  });
});

const currentDay = computed(() => streakStore.status?.currentStreak ?? 0);
const nextDay = computed(() => streakStore.status?.nextDay ?? 1);

function isCompleted(day: number) {
  return day <= currentDay.value;
}

function isCurrent(day: number) {
  return day === nextDay.value && streakStore.canClaim;
}

function getItemEmoji(itemType: string | null, itemId: string | null) {
  if (!itemType) return '';
  if (itemType === 'prepaid_card') {
    if (itemId?.includes('energy')) return '⚡';
    if (itemId?.includes('internet')) return '📡';
    return '🎴';
  }
  if (itemType === 'cooling') return '❄️';
  if (itemType === 'rig') return '⛏️';
  return '🎁';
}

async function handleClaim() {
  const result = await streakStore.claim();
  if (result) {
    // El modal mostrará el resultado
  }
}

function formatTimeRemaining(dateStr: string | null) {
  if (!dateStr) return '';
  const date = new Date(dateStr);
  const now = new Date();
  const diff = date.getTime() - now.getTime();

  if (diff <= 0) return t('streak.available');

  const hours = Math.floor(diff / (1000 * 60 * 60));
  const minutes = Math.floor((diff % (1000 * 60 * 60)) / (1000 * 60));

  if (hours > 0) {
    return `${hours}h ${minutes}m`;
  }
  return `${minutes}m`;
}

function handleClose() {
  streakStore.closeModal();
  emit('close');
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
            <div class="text-3xl">🔥</div>
            <div>
              <h2 class="text-xl font-display font-bold">
                <span class="gradient-text">{{ t('streak.title') }}</span>
              </h2>
              <p class="text-sm text-text-muted">
                {{ currentDay }} {{ t('streak.consecutiveDays') }}
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
          <div v-if="streakStore.loading" class="text-center py-12 text-text-muted">
            {{ t('common.loading') }}
          </div>

          <!-- Claim Result -->
          <div
            v-else-if="streakStore.lastClaimResult"
            class="text-center py-8"
          >
            <div class="text-6xl mb-4 animate-bounce">🎉</div>
            <h3 class="text-2xl font-bold mb-2">{{ t('streak.congratulations', { day: streakStore.lastClaimResult.newStreak }) }}</h3>
            <p class="text-text-muted mb-6">{{ t('streak.rewardsClaimed') }}</p>

            <div class="space-y-3">
              <div v-if="streakStore.lastClaimResult.gamecoinEarned > 0" class="flex items-center justify-center gap-2 text-xl">
                <span class="text-status-warning">🪙</span>
                <span class="font-bold text-status-warning">+{{ streakStore.lastClaimResult.gamecoinEarned }}</span>
              </div>
              <div v-if="streakStore.lastClaimResult.cryptoEarned > 0" class="flex items-center justify-center gap-2 text-xl">
                <span class="text-accent-primary">💎</span>
                <span class="font-bold text-accent-primary">+{{ streakStore.lastClaimResult.cryptoEarned }}</span>
              </div>
              <div v-if="streakStore.lastClaimResult.itemType" class="flex items-center justify-center gap-2 text-lg">
                <span>{{ getItemEmoji(streakStore.lastClaimResult.itemType, streakStore.lastClaimResult.itemId) }}</span>
                <span class="font-medium text-accent-secondary">{{ t('streak.specialItemReceived') }}</span>
              </div>
            </div>

            <button
              @click="streakStore.lastClaimResult = null"
              class="btn-primary mt-8"
            >
              {{ t('streak.continue') }}
            </button>
          </div>

          <!-- Main Content -->
          <div v-else>
            <!-- Stats -->
            <div class="grid grid-cols-2 gap-3 mb-6">
              <div class="bg-bg-secondary rounded-xl p-4 text-center">
                <div class="text-3xl font-bold text-status-warning">{{ currentDay }}</div>
                <div class="text-xs text-text-muted">{{ t('streak.currentStreak') }}</div>
              </div>
              <div class="bg-bg-secondary rounded-xl p-4 text-center">
                <div class="text-3xl font-bold text-accent-primary">{{ streakStore.longestStreak }}</div>
                <div class="text-xs text-text-muted">{{ t('streak.longestStreak') }}</div>
              </div>
            </div>

            <!-- Claim Button -->
            <div v-if="streakStore.canClaim" class="mb-6">
              <button
                @click="handleClaim"
                :disabled="streakStore.claiming"
                class="w-full py-4 rounded-xl bg-gradient-primary text-white font-bold text-lg hover:opacity-90 transition-opacity disabled:opacity-50"
              >
                <span v-if="streakStore.claiming">{{ t('streak.claiming') }}</span>
                <span v-else class="flex items-center justify-center gap-2">
                  🎁 {{ t('streak.claimDay', { day: nextDay }) }}
                </span>
              </button>
            </div>

            <!-- Next Claim Timer -->
            <div
              v-else-if="streakStore.status?.nextClaimAvailable"
              class="mb-6 text-center p-4 bg-bg-secondary rounded-xl"
            >
              <p class="text-text-muted text-sm mb-1">{{ t('streak.nextRewardIn') }}</p>
              <p class="text-2xl font-bold text-accent-primary">
                {{ formatTimeRemaining(streakStore.status.nextClaimAvailable) }}
              </p>
              <p v-if="streakStore.status?.streakExpiresAt" class="text-xs text-status-warning mt-2">
                ⚠️ {{ t('streak.streakExpires', { time: formatTimeRemaining(streakStore.status.streakExpiresAt) }) }}
              </p>
            </div>

            <!-- Rewards Calendar -->
            <div>
              <h3 class="text-sm font-medium text-text-muted mb-3">{{ t('streak.rewardsCalendar') }}</h3>
              <div class="grid grid-cols-5 gap-2">
                <div
                  v-for="reward in rewards"
                  :key="reward.day"
                  class="relative p-2 rounded-lg text-center transition-all"
                  :class="{
                    'bg-status-success/20 border border-status-success/50': isCompleted(reward.day),
                    'bg-accent-primary/20 border-2 border-accent-primary animate-pulse': isCurrent(reward.day),
                    'bg-bg-secondary border border-border/50': !isCompleted(reward.day) && !isCurrent(reward.day),
                    'opacity-50': reward.day > nextDay && !isCompleted(reward.day),
                  }"
                >
                  <!-- Day Number -->
                  <div class="text-xs font-medium mb-1" :class="isCompleted(reward.day) ? 'text-status-success' : 'text-text-muted'">
                    D{{ reward.day }}
                  </div>

                  <!-- Reward -->
                  <div class="text-sm font-bold" :class="isCompleted(reward.day) ? 'text-status-success' : ''">
                    <span v-if="reward.itemType" class="text-lg">
                      {{ getItemEmoji(reward.itemType, reward.itemId) }}
                    </span>
                    <span v-else-if="reward.crypto > 0" class="text-accent-primary">
                      💎
                    </span>
                    <span v-else class="text-status-warning">
                      {{ reward.gamecoin }}
                    </span>
                  </div>

                  <!-- Completed Check -->
                  <div
                    v-if="isCompleted(reward.day)"
                    class="absolute -top-1 -right-1 w-4 h-4 bg-status-success rounded-full flex items-center justify-center"
                  >
                    <svg class="w-3 h-3 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="3" d="M5 13l4 4L19 7" />
                    </svg>
                  </div>
                </div>
              </div>
            </div>

            <!-- Tips -->
            <div class="mt-6 p-3 bg-bg-tertiary rounded-lg text-xs text-text-muted">
              <p class="flex items-center gap-2">
                <span>💡</span>
                {{ t('streak.tip') }}
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
  </Teleport>
</template>
