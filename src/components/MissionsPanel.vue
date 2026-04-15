<script setup lang="ts">
import { ref, computed, watch, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMissionsStore } from '@/stores/missions';
import { useStreakStore } from '@/stores/streak';
import { playSound } from '@/utils/sounds';
import { formatCompact } from '@/utils/format';
import { X, Check } from 'lucide-vue-next';

const { t, te } = useI18n();

function missionName(missionId: string): string {
  const key = `missions.items.${missionId}.name`;
  if (te(key)) return t(key);
  console.warn(`[MISSIONS] Falta traducción para: "${missionId}" — agregar a missions.items en locales`);
  return missionId.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
}

function missionDesc(missionId: string): string {
  const key = `missions.items.${missionId}.desc`;
  if (te(key)) return t(key);
  return '';
}

function missionCategory(missionId: string): string {
  if (missionId.startsWith('weekly_')) return 'weekly';
  if (missionId.startsWith('achievement_')) return 'achievement';
  if (missionId.startsWith('tutorial_') || missionId.startsWith('referral_') || missionId.startsWith('event_')) return 'event';
  return 'daily';
}

/*
function categoryColor(cat: string): string {
  switch (cat) {
    case 'daily': return 'bg-blue-500/20 text-blue-400';
    case 'weekly': return 'bg-amber-500/20 text-amber-400';
    case 'achievement': return 'bg-yellow-500/20 text-yellow-400';
    case 'event': return 'bg-pink-500/20 text-pink-400';
    default: return 'bg-bg-tertiary text-text-muted';
  }
}
*/
const missionsStore = useMissionsStore();
const streakStore = useStreakStore();

// Tabs
const activeTab = ref<'daily' | 'achievements'>('daily');

const dailyMissions = computed(() =>
  missionsStore.missions.filter(m => missionCategory(m.missionId) !== 'achievement')
);
const achievementMissions = computed(() =>
  missionsStore.missions.filter(m => missionCategory(m.missionId) === 'achievement')
);

const props = defineProps<{
  show: boolean;
}>();

const emit = defineEmits<{
  close: [];
}>();

// Confetti state
const showConfetti = ref(false);
const confettiPieces = ref<{ id: number; left: number; color: string; delay: number; size: number }[]>([]);

function triggerConfetti() {
  const colors = ['#f59e0b', '#10b981', '#3b82f6', '#ec4899', '#8b5cf6', '#ef4444'];
  confettiPieces.value = Array.from({ length: 50 }, (_, i) => ({
    id: i,
    left: Math.random() * 100,
    color: colors[Math.floor(Math.random() * colors.length)],
    delay: Math.random() * 0.5,
    size: Math.random() * 8 + 6,
  }));
  showConfetti.value = true;

  setTimeout(() => {
    showConfetti.value = false;
    confettiPieces.value = [];
  }, 3000);
}

// Fetch data when modal opens
watch(() => props.show, (isOpen) => {
  if (isOpen) {
    missionsStore.fetchMissions();
    streakStore.fetchStatus();
    startCountdown();
  } else {
    stopCountdown();
  }
});

onUnmounted(() => {
  stopCountdown();
});

// === Missions logic ===
async function handleClaimMission(missionId: string) {
  const result = await missionsStore.claimReward(missionId);
  if (result) {
    playSound('reward');
    triggerConfetti();
  }
}

function formatProgress(progress: number, target: number): string {
  if (target >= 1) {
    return `${Math.floor(progress)}/${Math.floor(target)}`;
  }
  return `${progress.toFixed(2)}/${target.toFixed(2)}`;
}

// === Streak logic ===
const showStreakCalendar = ref(false);
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

async function handleClaimStreak() {
  const result = await streakStore.claim();
  if (result) {
    playSound('reward');
    triggerConfetti();
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

// === Mission countdown timer ===
const now = ref(new Date());
let countdownInterval: ReturnType<typeof setInterval> | null = null;

function startCountdown() {
  now.value = new Date();
  if (!countdownInterval) {
    countdownInterval = setInterval(() => { now.value = new Date(); }, 60_000);
  }
}

function stopCountdown() {
  if (countdownInterval) {
    clearInterval(countdownInterval);
    countdownInterval = null;
  }
}

const missionTimeRemaining = computed(() => {
  const n = now.value;
  // Missions expire at next midnight UTC
  const tomorrow = new Date(Date.UTC(n.getUTCFullYear(), n.getUTCMonth(), n.getUTCDate() + 1));
  const diff = tomorrow.getTime() - n.getTime();
  if (diff <= 0) return '';
  const hours = Math.floor(diff / (1000 * 60 * 60));
  const minutes = Math.floor((diff % (1000 * 60 * 60)) / (1000 * 60));
  if (hours > 0) return `${hours}h ${minutes}m`;
  return `${minutes}m`;
});

function handleClose() {
  playSound('click');
  missionsStore.closePanel();
  streakStore.closeModal();
  showStreakCalendar.value = false;
  emit('close');
}
</script>

<template>
  <Teleport to="body">
    <!-- Confetti Overlay -->
    <div v-if="showConfetti" class="fixed inset-0 z-[100] pointer-events-none overflow-hidden">
      <div
        v-for="piece in confettiPieces"
        :key="piece.id"
        class="confetti-piece"
        :style="{
          left: `${piece.left}%`,
          backgroundColor: piece.color,
          width: `${piece.size}px`,
          height: `${piece.size}px`,
          animationDelay: `${piece.delay}s`,
        }"
      ></div>
    </div>

    <div
      v-if="show"
      class="fixed inset-0 z-50 flex items-center justify-center p-4"
    >
      <!-- Backdrop -->
      <div
        class="absolute inset-0 bg-black/40 backdrop-blur-sm"
        @click="handleClose"
      ></div>

      <!-- Modal -->
      <div class="relative w-full max-w-lg h-[85vh] overflow-hidden mp-modal flex flex-col">
        <!-- Header -->
        <div class="mp-header shrink-0">
          <div class="flex items-center gap-3">
            <div class="text-3xl">🎯</div>
            <div>
              <h2 class="mp-title">{{ t('missions.title') }}</h2>
              <p class="mp-sub">
                {{ missionsStore.completedCount }}/{{ missionsStore.totalCount }} {{ t('missions.completed') }}
              </p>
            </div>
          </div>
          <button @click="handleClose" class="mp-close">
            <X :size="18" />
          </button>
        </div>

        <!-- Tabs -->
        <div class="mp-tabs shrink-0">
          <button
            @click="activeTab = 'daily'"
            class="mp-tab"
            :class="{ active: activeTab === 'daily' }"
          >
            🎯 {{ t('missions.tabDaily') }}
            <span v-if="dailyMissions.filter(m => m.isCompleted && !m.isClaimed).length" class="mp-tab-badge">
              {{ dailyMissions.filter(m => m.isCompleted && !m.isClaimed).length }}
            </span>
          </button>
          <button
            @click="activeTab = 'achievements'"
            class="mp-tab"
            :class="{ active: activeTab === 'achievements' }"
          >
            🏆 {{ t('missions.tabAchievements') }}
            <span v-if="achievementMissions.filter(m => m.isCompleted && !m.isClaimed).length" class="mp-tab-badge amber">
              {{ achievementMissions.filter(m => m.isCompleted && !m.isClaimed).length }}
            </span>
          </button>
        </div>

        <!-- Content -->
        <div class="mp-content">
          <div class="mp-list">

            <!-- ========== DAILY TAB ========== -->
            <template v-if="activeTab === 'daily'">

            <!-- Streak claim result -->
            <div v-if="streakStore.lastClaimResult" class="mp-streak-card">
              <div style="text-align:center;padding:1rem 0">
                <div style="font-size:3rem;margin-bottom:0.5rem">🎉</div>
                <h3 class="mp-item-name">{{ t('streak.congratulations', { day: streakStore.lastClaimResult.newStreak }) }}</h3>
                <div style="display:flex;align-items:center;justify-content:center;gap:1rem;margin-top:0.5rem">
                  <span v-if="streakStore.lastClaimResult.gamecoinEarned > 0" class="mp-reward-val amber">🪙 +{{ streakStore.lastClaimResult.gamecoinEarned }}</span>
                  <span v-if="streakStore.lastClaimResult.cryptoEarned > 0" class="mp-reward-val purple">💎 +{{ streakStore.lastClaimResult.cryptoEarned }}</span>
                  <span v-if="streakStore.lastClaimResult.itemType" class="mp-reward-val">{{ getItemEmoji(streakStore.lastClaimResult.itemType, streakStore.lastClaimResult.itemId) }} {{ t('streak.specialItemReceived') }}</span>
                </div>
                <button @click="streakStore.lastClaimResult = null" class="mp-btn-secondary" style="margin-top:0.8rem">{{ t('streak.continue') }}</button>
              </div>
            </div>

            <!-- Streak normal card -->
            <div v-else class="mp-streak-card" :class="{ canClaim: streakStore.canClaim }">
              <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:0.5rem">
                <div style="display:flex;align-items:center;gap:0.5rem">
                  <span style="font-size:1.5rem">🔥</span>
                  <div>
                    <div class="mp-item-name">{{ t('streak.title') }}</div>
                    <div class="mp-item-desc">{{ currentDay }} {{ t('streak.consecutiveDays') }} · {{ t('streak.longestStreak') }}: {{ streakStore.longestStreak }}</div>
                  </div>
                </div>
                <button @click="showStreakCalendar = !showStreakCalendar" class="mp-toggle">{{ showStreakCalendar ? '▲' : '▼' }}</button>
              </div>
              <div style="display:flex;align-items:center;justify-content:space-between">
                <div style="display:flex;align-items:center;gap:0.5rem">
                  <span>🎁</span>
                  <span v-if="streakStore.canClaim" class="mp-reward-val amber" style="font-size:0.8rem">{{ t('streak.claimDay', { day: nextDay }) }}</span>
                  <span v-else-if="streakStore.status?.nextClaimAvailable" class="mp-item-desc">{{ t('streak.nextRewardIn') }} <strong class="mp-reward-val purple">{{ formatTimeRemaining(streakStore.status.nextClaimAvailable) }}</strong></span>
                  <span v-else class="mp-item-desc">{{ t('streak.claimDay', { day: nextDay }) }}</span>
                </div>
                <button v-if="streakStore.canClaim" @click="handleClaimStreak" :disabled="streakStore.claiming" class="mp-claim-btn">{{ streakStore.claiming ? '...' : t('missions.claim') }}</button>
                <span v-else-if="currentDay > 0" class="mp-done"><Check :size="14" /> D{{ currentDay }}</span>
              </div>
              <div v-if="streakStore.status?.streakExpiresAt && !streakStore.canClaim" class="mp-warning">⚠️ {{ t('streak.streakExpires', { time: formatTimeRemaining(streakStore.status.streakExpiresAt) }) }}</div>

              <!-- Calendar -->
              <div v-if="showStreakCalendar" class="mp-calendar">
                <div class="mp-cal-grid">
                  <div v-for="reward in rewards" :key="reward.day" class="mp-cal-day" :class="{ completed: isCompleted(reward.day), current: isCurrent(reward.day), future: reward.day > nextDay && !isCompleted(reward.day) }">
                    <div class="mp-cal-label">D{{ reward.day }}</div>
                    <div class="mp-cal-icon">
                      <span v-if="reward.itemType">{{ getItemEmoji(reward.itemType, reward.itemId) }}</span>
                      <span v-else-if="reward.crypto > 0" class="mp-reward-val purple">💎</span>
                      <span v-else class="mp-reward-val amber">{{ reward.gamecoin }}</span>
                    </div>
                    <div v-if="isCompleted(reward.day)" class="mp-cal-check"><Check :size="10" color="#fff" :stroke-width="3" /></div>
                  </div>
                </div>
              </div>
            </div>

            <!-- Loading skeleton -->
            <div v-if="missionsStore.loading && dailyMissions.length === 0" class="mp-list">
              <div v-for="i in 3" :key="i" class="mp-item mp-skel"><div class="mp-skel-line w60"></div><div class="mp-skel-bar"></div></div>
            </div>

            <!-- Mission items -->
            <div v-for="mission in dailyMissions" :key="mission.id" class="mp-item" :class="{ claimed: mission.isClaimed, ready: mission.isCompleted && !mission.isClaimed }">
              <div style="display:flex;align-items:flex-start;justify-content:space-between;gap:0.5rem;margin-bottom:0.4rem">
                <div style="display:flex;align-items:center;gap:0.5rem">
                  <span style="font-size:1.4rem">{{ mission.icon }}</span>
                  <div>
                    <div class="mp-item-name">{{ missionName(mission.missionId) }}</div>
                    <div class="mp-item-desc">{{ missionDesc(mission.missionId) }}</div>
                  </div>
                </div>
              </div>
              <div v-if="!mission.isClaimed && missionTimeRemaining" class="mp-item-desc" style="margin-bottom:0.3rem">⏳ {{ t('missions.expiresIn', { time: missionTimeRemaining }) }}</div>
              <div class="mp-progress">
                <div class="mp-progress-header">
                  <span class="mp-item-desc">{{ t('missions.progress') }}</span>
                  <span class="mp-progress-val" :class="{ done: mission.isCompleted }">{{ formatProgress(mission.progress, mission.targetValue) }}</span>
                </div>
                <div class="mp-bar"><div class="mp-bar-fill" :class="{ done: mission.isCompleted }" :style="{ width: mission.progressPercent + '%' }"></div></div>
              </div>
              <div style="display:flex;align-items:center;justify-content:space-between;margin-top:0.5rem">
                <span class="mp-reward-val" :class="mission.rewardType === 'crypto' ? 'purple' : 'amber'">{{ missionsStore.getRewardIcon(mission.rewardType) }} +{{ formatCompact(mission.rewardAmount) }}</span>
                <button v-if="mission.isCompleted && !mission.isClaimed" @click="handleClaimMission(mission.id)" :disabled="missionsStore.claiming" class="mp-claim-btn">{{ missionsStore.claiming ? '...' : t('missions.claim') }}</button>
                <span v-else-if="mission.isClaimed" class="mp-done"><Check :size="14" /> {{ t('missions.claimed') }}</span>
                <span v-else class="mp-item-desc">{{ mission.progressPercent }}%</span>
              </div>
            </div>

            <div v-if="!missionsStore.loading && dailyMissions.length === 0" class="mp-empty">
              <div style="font-size:2.5rem">📋</div>
              <p>{{ t('missions.noMissions') }}</p>
              <p class="mp-item-desc">{{ t('missions.comeBackTomorrow') }}</p>
            </div>
            </template>

            <!-- ========== ACHIEVEMENTS TAB ========== -->
            <template v-if="activeTab === 'achievements'">
            <div v-if="achievementMissions.length > 0" class="mp-ach-grid">
              <div v-for="mission in achievementMissions" :key="mission.id" class="mp-item mp-ach" :class="{ claimed: mission.isClaimed, ready: mission.isCompleted && !mission.isClaimed }">
                <div style="display:flex;align-items:flex-start;gap:0.4rem;margin-bottom:0.4rem">
                  <span style="font-size:1.2rem">{{ mission.icon }}</span>
                  <div style="flex:1;min-width:0">
                    <div class="mp-item-name" style="font-size:0.75rem">{{ missionName(mission.missionId) }}</div>
                    <div class="mp-item-desc">{{ missionDesc(mission.missionId) }}</div>
                  </div>
                </div>
                <div class="mp-progress" style="margin-bottom:0.4rem">
                  <div class="mp-bar"><div class="mp-bar-fill" :class="{ done: mission.isCompleted }" :style="{ width: mission.progressPercent + '%' }"></div></div>
                  <span class="mp-progress-val" :class="{ done: mission.isCompleted }" style="font-size:0.6rem">{{ formatProgress(mission.progress, mission.targetValue) }}</span>
                </div>
                <div style="display:flex;align-items:center;justify-content:space-between">
                  <span class="mp-reward-val" :class="mission.rewardType === 'crypto' ? 'purple' : 'amber'" style="font-size:0.7rem">{{ missionsStore.getRewardIcon(mission.rewardType) }} +{{ formatCompact(mission.rewardAmount) }}</span>
                  <button v-if="mission.isCompleted && !mission.isClaimed" @click="handleClaimMission(mission.id)" :disabled="missionsStore.claiming" class="mp-claim-btn" style="font-size:0.65rem;padding:4px 10px">{{ missionsStore.claiming ? '...' : t('missions.claim') }}</button>
                  <span v-else-if="mission.isClaimed" class="mp-done" style="font-size:0.6rem"><Check :size="12" /> {{ t('missions.claimed') }}</span>
                  <span v-else class="mp-item-desc">{{ mission.progressPercent }}%</span>
                </div>
              </div>
            </div>
            <div v-if="!missionsStore.loading && achievementMissions.length === 0" class="mp-empty">
              <div style="font-size:2.5rem">🏆</div>
              <p>{{ t('missions.noAchievements') }}</p>
            </div>
            </template>
          </div>
        </div>

        <!-- Footer -->
        <div class="mp-footer">
          <div style="display:flex;align-items:center;justify-content:space-between">
            <span class="mp-item-desc">⏱️ {{ t('missions.onlineTimeToday') }} <strong class="mp-item-name">{{ missionsStore.onlineMinutes }} {{ t('missions.min') }}</strong></span>
            <span v-if="missionsStore.claimableCount > 0" class="mp-reward-val purple">{{ missionsStore.claimableCount }} {{ t('missions.toClaim') }}</span>
          </div>
        </div>
      </div>
    </div>
  </Teleport>
</template>

<style scoped>
@import url('https://fonts.googleapis.com/css2?family=Nunito:wght@400;600;700;800;900&display=swap');

/* Kawaii Modal Override */
.mp-modal {
  background: #fff !important;
  border: 2px solid #c4a0e8 !important;
  border-radius: 16px !important;
  box-shadow: 4px 4px 0 #e8d0f0 !important;
  font-family: 'Nunito', 'Trebuchet MS', sans-serif;
  animation: mp-enter 0.3s cubic-bezier(0.16,1,0.3,1);
}
@keyframes mp-enter { from { opacity: 0; transform: translateY(-15px); } to { opacity: 1; transform: translateY(0); } }

.mp-header {
  display: flex; align-items: center; justify-content: space-between;
  padding: 1rem 1.2rem;
  border-bottom: 2px solid #e8d8f4;
  background: linear-gradient(180deg, #f8f2ff, #fff);
}
.mp-title { font-size: 1.1rem; font-weight: 900; color: #4a3a5c; margin: 0; }
.mp-sub { font-size: 0.75rem; font-weight: 700; color: #9a80b8; margin: 0; }
.mp-close {
  width: 30px; height: 30px;
  display: flex; align-items: center; justify-content: center;
  background: #f8f2ff; border: 2px solid #d0b8e8; border-radius: 8px;
  color: #9a80b8; cursor: pointer; transition: 0.2s;
}
.mp-close:hover { background: #fff0f0; border-color: #ff7b7b; color: #cc4444; }

.mp-tabs {
  display: flex; border-bottom: 2px solid #e8d8f4;
}
.mp-tab {
  flex: 1; padding: 10px; text-align: center;
  font-size: 0.8rem; font-weight: 800; color: #9a80b8;
  background: none; border: none; cursor: pointer;
  transition: 0.2s; position: relative;
  font-family: 'Nunito', sans-serif;
}
.mp-tab:hover { color: #7b5ea7; background: #f8f2ff; }
.mp-tab.active { color: #4a3a5c; }
.mp-tab.active::after {
  content: ''; position: absolute; bottom: -2px; left: 0; right: 0;
  height: 3px; background: #c4a0e8; border-radius: 2px 2px 0 0;
}
.mp-tab-badge {
  display: inline-flex; align-items: center; justify-content: center;
  min-width: 18px; height: 18px; padding: 0 5px;
  background: #c4a0e8; color: #fff; font-size: 0.6rem; font-weight: 900;
  border-radius: 9px; margin-left: 4px;
}
.mp-tab-badge.amber { background: #d4a017; }

/* Content */
.mp-content {
  padding: 0.8rem; overflow-y: auto; flex: 1; min-height: 0;
}
.mp-content::-webkit-scrollbar { width: 6px; }
.mp-content::-webkit-scrollbar-track { background: #f0e8f8; }
.mp-content::-webkit-scrollbar-thumb { background: #c4a0e8; border-radius: 3px; }

.mp-list { display: flex; flex-direction: column; gap: 0.6rem; }

/* Streak card */
.mp-streak-card {
  background: #fff8e0; border: 2px solid #ffe566; border-left: 4px solid #d4a017;
  border-radius: 12px; padding: 0.8rem;
}
.mp-streak-card.canClaim { border-color: #d4a017; }

/* Mission item */
.mp-item {
  background: #f8f2ff; border: 2px solid #e8d8f4; border-left: 4px solid #d0b8e8;
  border-radius: 10px; padding: 0.8rem;
}
.mp-item.ready { border-left-color: #c4a0e8; background: #f0e4ff; }
.mp-item.claimed { border-left-color: #7cc490; opacity: 0.7; }

/* Text styles */
.mp-item-name { font-size: 0.85rem; font-weight: 800; color: #4a3a5c; }
.mp-item-desc { font-size: 0.7rem; font-weight: 600; color: #9a80b8; }
.mp-reward-val { font-size: 0.8rem; font-weight: 900; color: #4a3a5c; }
.mp-reward-val.amber { color: #d4a017; }
.mp-reward-val.purple { color: #7b5ea7; }
.mp-done { font-size: 0.7rem; font-weight: 800; color: #3a7a4a; display: flex; align-items: center; gap: 4px; }
.mp-warning { font-size: 0.65rem; font-weight: 700; color: #d4a017; margin-top: 0.4rem; }

/* Progress */
.mp-progress { margin-bottom: 0.3rem; }
.mp-progress-header { display: flex; align-items: center; justify-content: space-between; margin-bottom: 4px; }
.mp-progress-val { font-size: 0.7rem; font-weight: 800; color: #7b5ea7; }
.mp-progress-val.done { color: #3a7a4a; }
.mp-bar { height: 6px; background: #efe0f8; border-radius: 3px; overflow: hidden; border: 1px solid #d0b8e8; }
.mp-bar-fill { height: 100%; background: linear-gradient(90deg, #d0b8e8, #c4a0e8); border-radius: 3px; transition: width 0.3s; }
.mp-bar-fill.done { background: #7cc490; }

/* Buttons */
.mp-claim-btn {
  background: #ffe566; border: 2px outset #d4a017; border-radius: 8px;
  padding: 6px 14px; font-size: 0.75rem; font-weight: 900; color: #4a3a5c;
  font-family: 'Nunito', sans-serif; cursor: pointer; transition: 0.2s;
}
.mp-claim-btn:hover { background: #ffd700; border-style: inset; }
.mp-claim-btn:disabled { opacity: 0.4; cursor: not-allowed; }

.mp-btn-secondary {
  background: #f8f2ff; border: 2px solid #d0b8e8; border-radius: 8px;
  padding: 6px 14px; font-size: 0.75rem; font-weight: 800; color: #7b5ea7;
  font-family: 'Nunito', sans-serif; cursor: pointer; transition: 0.2s;
}
.mp-btn-secondary:hover { background: #ffe97a; border-color: #d4a017; color: #4a3a5c; }

.mp-toggle {
  font-size: 0.65rem; color: #9a80b8; background: #efe0f8; border: 1px solid #d0b8e8;
  border-radius: 6px; padding: 2px 8px; cursor: pointer; transition: 0.2s;
}
.mp-toggle:hover { background: #e0d0f0; }

/* Calendar */
.mp-calendar { margin-top: 0.6rem; padding-top: 0.6rem; border-top: 1px solid #ffe566; }
.mp-cal-grid { display: grid; grid-template-columns: repeat(5, 1fr); gap: 6px; }
.mp-cal-day {
  position: relative; text-align: center; padding: 6px 4px;
  background: #fff; border: 2px solid #e8d8f4; border-radius: 8px;
}
.mp-cal-day.completed { background: #e8f8ec; border-color: #a8d0b8; }
.mp-cal-day.current { background: #f0e4ff; border-color: #c4a0e8; animation: mp-pulse 2s infinite; }
.mp-cal-day.future { opacity: 0.4; }
@keyframes mp-pulse { 0%,100% { box-shadow: 0 0 0 0 rgba(196,160,232,0.3); } 50% { box-shadow: 0 0 0 4px rgba(196,160,232,0); } }
.mp-cal-label { font-size: 0.55rem; font-weight: 800; color: #9a80b8; }
.mp-cal-icon { font-size: 0.75rem; font-weight: 900; }
.mp-cal-check {
  position: absolute; top: -4px; right: -4px;
  width: 14px; height: 14px; background: #7cc490; border-radius: 50%;
  display: flex; align-items: center; justify-content: center;
}

/* Achievements grid */
.mp-ach-grid { display: grid; grid-template-columns: repeat(2, 1fr); gap: 8px; }
.mp-ach { padding: 0.6rem; }

/* Empty state */
.mp-empty { text-align: center; padding: 2rem 0; color: #9a80b8; font-size: 0.8rem; font-weight: 700; }

/* Skeleton */
.mp-skel { background: #f8f2ff; }
.mp-skel-line { height: 10px; background: #efe0f8; border-radius: 5px; animation: mp-shimmer 1.5s ease infinite; }
.mp-skel-line.w60 { width: 60%; margin-bottom: 8px; }
.mp-skel-bar { height: 6px; background: #efe0f8; border-radius: 3px; animation: mp-shimmer 1.5s ease infinite; }
@keyframes mp-shimmer { 0% { opacity: 0.5; } 50% { opacity: 1; } 100% { opacity: 0.5; } }

/* Footer */
.mp-footer {
  padding: 0.8rem 1rem; border-top: 2px solid #e8d8f4;
  background: #f8f2ff; flex-shrink: 0;
}

.confetti-piece {
  position: absolute;
  top: -20px;
  border-radius: 2px;
  animation: confetti-fall 3s ease-out forwards;
  transform-origin: center;
}

@keyframes confetti-fall {
  0% {
    transform: translateY(0) rotate(0deg) scale(1);
    opacity: 1;
  }
  25% {
    transform: translateY(25vh) rotate(180deg) scale(0.9);
    opacity: 1;
  }
  50% {
    transform: translateY(50vh) rotate(360deg) scale(0.8);
    opacity: 0.9;
  }
  75% {
    transform: translateY(75vh) rotate(540deg) scale(0.7);
    opacity: 0.6;
  }
  100% {
    transform: translateY(100vh) rotate(720deg) scale(0.5);
    opacity: 0;
  }
}

.confetti-piece:nth-child(odd) {
  animation-name: confetti-fall-wobble;
}

@keyframes confetti-fall-wobble {
  0% {
    transform: translateY(0) translateX(0) rotate(0deg) scale(1);
    opacity: 1;
  }
  25% {
    transform: translateY(25vh) translateX(20px) rotate(180deg) scale(0.9);
    opacity: 1;
  }
  50% {
    transform: translateY(50vh) translateX(-15px) rotate(360deg) scale(0.8);
    opacity: 0.9;
  }
  75% {
    transform: translateY(75vh) translateX(10px) rotate(540deg) scale(0.7);
    opacity: 0.6;
  }
  100% {
    transform: translateY(100vh) translateX(-5px) rotate(720deg) scale(0.5);
    opacity: 0;
  }
}

.confetti-piece:nth-child(3n) {
  border-radius: 50%;
}

.confetti-piece:nth-child(4n) {
  border-radius: 0;
  transform: rotate(45deg);
}

/* ===== DARK KAWAII MODE (default) ===== */
:root:not(.kawaii-light) .mp-modal {
  background: #1f1833 !important;
  border-color: #4a3660 !important;
  box-shadow: 4px 4px 0 rgba(74,54,96,0.3) !important;
}
:root:not(.kawaii-light) .mp-header {
  border-bottom-color: #3a2d50;
  background: linear-gradient(180deg, #231d35, #1f1833);
}
:root:not(.kawaii-light) .mp-title { color: #f0e4ff; }
:root:not(.kawaii-light) .mp-sub { color: #8a70a8; }
:root:not(.kawaii-light) .mp-close {
  background: #231d35; border-color: #4a3660; color: #8a70a8;
}
:root:not(.kawaii-light) .mp-close:hover {
  background: rgba(232,124,138,0.1); border-color: #e87c8a; color: #e87c8a;
}
:root:not(.kawaii-light) .mp-tabs { border-bottom-color: #3a2d50; }
:root:not(.kawaii-light) .mp-tab { color: #8a70a8; }
:root:not(.kawaii-light) .mp-tab:hover { color: #b8a0d0; background: #231d35; }
:root:not(.kawaii-light) .mp-tab.active { color: #f0e4ff; }
:root:not(.kawaii-light) .mp-tab.active::after { background: #c4a0e8; }
:root:not(.kawaii-light) .mp-content::-webkit-scrollbar-track { background: #1a1528; }
:root:not(.kawaii-light) .mp-content::-webkit-scrollbar-thumb { background: #4a3660; }
:root:not(.kawaii-light) .mp-streak-card {
  background: rgba(255,229,102,0.08); border-color: rgba(255,229,102,0.3);
  border-left-color: #ffe566;
}
:root:not(.kawaii-light) .mp-item {
  background: #231d35; border-color: #3a2d50; border-left-color: #4a3660;
}
:root:not(.kawaii-light) .mp-item.ready {
  border-left-color: #c4a0e8; background: #2d2545;
}
:root:not(.kawaii-light) .mp-item.claimed {
  border-left-color: #5a9a6a; opacity: 0.6;
}
:root:not(.kawaii-light) .mp-item-name { color: #f0e4ff; }
:root:not(.kawaii-light) .mp-item-desc { color: #8a70a8; }
:root:not(.kawaii-light) .mp-reward-val { color: #f0e4ff; }
:root:not(.kawaii-light) .mp-reward-val.amber { color: #ffe566; }
:root:not(.kawaii-light) .mp-reward-val.purple { color: #c4a0e8; }
:root:not(.kawaii-light) .mp-done { color: #7cc490; }
:root:not(.kawaii-light) .mp-warning { color: #ffe566; }
:root:not(.kawaii-light) .mp-progress-val { color: #c4a0e8; }
:root:not(.kawaii-light) .mp-progress-val.done { color: #7cc490; }
:root:not(.kawaii-light) .mp-bar { background: #2d2545; border-color: #4a3660; }
:root:not(.kawaii-light) .mp-bar-fill { background: linear-gradient(90deg, #5c4578, #c4a0e8); }
:root:not(.kawaii-light) .mp-bar-fill.done { background: #7cc490; }
:root:not(.kawaii-light) .mp-claim-btn {
  background: #ffe566; border-color: #d4a017; color: #1a1528;
}
:root:not(.kawaii-light) .mp-claim-btn:hover { background: #ffd700; }
:root:not(.kawaii-light) .mp-btn-secondary {
  background: #231d35; border-color: #4a3660; color: #c4a0e8;
}
:root:not(.kawaii-light) .mp-btn-secondary:hover {
  background: rgba(255,229,102,0.1); border-color: #ffe566; color: #ffe566;
}
:root:not(.kawaii-light) .mp-toggle {
  color: #8a70a8; background: #2d2545; border-color: #4a3660;
}
:root:not(.kawaii-light) .mp-toggle:hover { background: #3a2d50; }
:root:not(.kawaii-light) .mp-cal-day {
  background: #231d35; border-color: #3a2d50;
}
:root:not(.kawaii-light) .mp-cal-day.completed {
  background: rgba(124,196,144,0.1); border-color: rgba(124,196,144,0.3);
}
:root:not(.kawaii-light) .mp-cal-day.current {
  background: #2d2545; border-color: #5c4578;
}
:root:not(.kawaii-light) .mp-cal-label { color: #8a70a8; }
:root:not(.kawaii-light) .mp-empty { color: #8a70a8; }
:root:not(.kawaii-light) .mp-skel { background: #231d35; }
:root:not(.kawaii-light) .mp-skel-line { background: #2d2545; }
:root:not(.kawaii-light) .mp-skel-bar { background: #2d2545; }
:root:not(.kawaii-light) .mp-footer {
  border-top-color: #3a2d50; background: #231d35;
}
</style>
