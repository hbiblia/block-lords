<script setup lang="ts">
import { ref, onMounted, computed } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAuthStore } from '@/stores/auth';
import { formatCompact, formatNumber } from '@/utils/format';
import { Gem, Crown, Trophy, Medal, Pickaxe, Coins, Zap, Globe } from 'lucide-vue-next';

const { t } = useI18n();
const router = useRouter();
const authStore = useAuthStore();

const player = computed(() => authStore.player);
const showContent = ref(false);
const showStats = ref(false);
const showButton = ref(false);

onMounted(async () => {
  await new Promise(resolve => setTimeout(resolve, 300));
  showContent.value = true;
  await new Promise(resolve => setTimeout(resolve, 600));
  showStats.value = true;
  await new Promise(resolve => setTimeout(resolve, 400));
  showButton.value = true;
});

function enterGame() {
  router.push('/mining');
}

function getRankName(score: number): string {
  if (score >= 85) return t('welcome.ranks.diamond');
  if (score >= 70) return t('welcome.ranks.platinum');
  if (score >= 50) return t('welcome.ranks.gold');
  if (score >= 30) return t('welcome.ranks.silver');
  return t('welcome.ranks.bronze');
}

function getRankIcon(score: number): string {
  if (score >= 85) return 'diamond';
  if (score >= 70) return 'platinum';
  if (score >= 50) return 'gold';
  if (score >= 30) return 'silver';
  return 'bronze';
}

const rankIcon = computed(() => getRankIcon(player.value?.reputation_score ?? 50));
</script>

<template>
  <div class="welcome-page">
    <div class="welcome-card">
      <!-- Avatar -->
      <div
        class="welcome-anim"
        :class="{ visible: showContent }"
      >
        <div class="welcome-avatar-wrap">
          <div class="welcome-avatar">
            {{ player?.username?.charAt(0).toUpperCase() ?? '?' }}
          </div>
          <div class="welcome-rank-badge">
            <Gem v-if="rankIcon === 'diamond'" :size="18" />
            <Crown v-else-if="rankIcon === 'platinum'" :size="18" />
            <Trophy v-else-if="rankIcon === 'gold'" :size="18" />
            <Medal v-else :size="18" />
          </div>
        </div>

        <h1 class="welcome-greeting">{{ t('welcome.greeting') }}</h1>
        <h2 class="welcome-username">{{ player?.username ?? t('welcome.defaultName') }}!</h2>
        <p class="welcome-sub">{{ t('welcome.stationReady') }}</p>
      </div>

      <!-- Stats -->
      <div
        class="welcome-stats"
        :class="{ visible: showStats }"
      >
        <div class="ws-card" v-tooltip="formatNumber(player?.gamecoin_balance ?? 0)">
          <Coins :size="16" class="ws-icon amber" />
          <span class="ws-val amber">{{ formatCompact(player?.gamecoin_balance) }}</span>
          <span class="ws-label">COINS</span>
        </div>
        <div class="ws-card" v-tooltip="formatNumber(player?.crypto_balance ?? 0, 2)">
          <Pickaxe :size="16" class="ws-icon" />
          <span class="ws-val">{{ formatCompact(player?.crypto_balance) }}</span>
          <span class="ws-label">LANDWORK</span>
        </div>
        <div class="ws-card">
          <span class="ws-val rank">{{ getRankName(player?.reputation_score ?? 50) }}</span>
          <span class="ws-label">RANK</span>
        </div>
      </div>

      <!-- Resources -->
      <div
        class="welcome-resources"
        :class="{ visible: showStats }"
      >
        <div class="wr-bar">
          <Zap :size="14" class="wr-icon amber" />
          <span class="wr-label">{{ t('welcome.energy') }}</span>
          <div class="wr-track">
            <div class="wr-fill amber" :style="{ width: `${player?.energy ?? 100}%` }"></div>
          </div>
          <span class="wr-val">{{ player?.energy?.toFixed(0) ?? 100 }}%</span>
        </div>
        <div class="wr-bar">
          <Globe :size="14" class="wr-icon" />
          <span class="wr-label">{{ t('welcome.internet') }}</span>
          <div class="wr-track">
            <div class="wr-fill" :style="{ width: `${player?.internet ?? 100}%` }"></div>
          </div>
          <span class="wr-val">{{ player?.internet?.toFixed(0) ?? 100 }}%</span>
        </div>
      </div>

      <!-- Enter button -->
      <div
        class="welcome-enter"
        :class="{ visible: showButton }"
      >
        <button class="welcome-btn" @click="enterGame">
          <span>{{ t('welcome.enterGame') }}</span>
        </button>
        <p class="welcome-hint">{{ t('welcome.pressContinue') }}</p>
      </div>
    </div>
  </div>
</template>

<style scoped>
@import url('https://fonts.googleapis.com/css2?family=Nunito:wght@400;600;700;800;900&display=swap');

.welcome-page {
  min-height: 100vh;
  display: flex; align-items: center; justify-content: center;
  background: #1a1528;
  background-image: radial-gradient(circle, #2d2545 1.5px, transparent 1.5px);
  background-size: 20px 20px;
  padding: 2rem;
  font-family: 'Nunito', 'Trebuchet MS', sans-serif;
}

.welcome-card {
  background: #1f1833;
  border: 2px solid #4a3660;
  border-radius: 16px;
  box-shadow: 4px 4px 0 rgba(74,54,96,0.3);
  padding: 2.5rem 2rem;
  max-width: 440px;
  width: 100%;
  text-align: center;
}

/* Animations */
.welcome-anim, .welcome-stats, .welcome-resources, .welcome-enter {
  transition: all 0.7s cubic-bezier(0.16, 1, 0.3, 1);
  opacity: 0; transform: translateY(12px);
}
.welcome-anim.visible, .welcome-stats.visible, .welcome-resources.visible, .welcome-enter.visible {
  opacity: 1; transform: translateY(0);
}

/* Avatar */
.welcome-avatar-wrap {
  position: relative; display: inline-block; margin-bottom: 1.2rem;
}
.welcome-avatar {
  width: 90px; height: 90px;
  border-radius: 16px;
  background: linear-gradient(135deg, #c4a0e8, #b088d0);
  display: flex; align-items: center; justify-content: center;
  font-size: 2.5rem; font-weight: 900; color: #fff;
  box-shadow: 3px 3px 0 rgba(74,54,96,0.3);
  font-family: 'Nunito', sans-serif;
}
.welcome-rank-badge {
  position: absolute; bottom: -6px; right: -6px;
  width: 34px; height: 34px;
  background: #1f1833; border: 2px solid #4a3660; border-radius: 10px;
  display: flex; align-items: center; justify-content: center;
  color: #d4a017;
}

/* Text */
.welcome-greeting {
  font-size: 1.4rem; font-weight: 700; color: #b8a0d0;
  margin: 0 0 4px;
}
.welcome-username {
  font-size: 1.8rem; font-weight: 900; color: #f0e4ff;
  margin: 0 0 8px;
}
.welcome-sub {
  font-size: 0.85rem; color: #8a70a8; margin: 0 0 1.5rem;
}

/* Stats */
.welcome-stats {
  display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px;
  margin-bottom: 1.2rem;
}
.ws-card {
  background: #231d35; border: 2px solid #3a2d50; border-radius: 10px;
  padding: 12px 8px;
  display: flex; flex-direction: column; align-items: center; gap: 4px;
}
.ws-icon { color: #b8a0d0; }
.ws-icon.amber { color: #d4a017; }
.ws-val {
  font-size: 1.1rem; font-weight: 900; color: #f0e4ff;
  font-family: 'Nunito', sans-serif;
}
.ws-val.amber { color: #d4a017; }
.ws-val.rank { font-size: 0.8rem; color: #b8a0d0; }
.ws-label {
  font-size: 0.6rem; font-weight: 800; color: #8a70a8;
  letter-spacing: 1.5px;
}

/* Resources */
.welcome-resources {
  background: #231d35; border: 2px solid #3a2d50; border-radius: 10px;
  padding: 12px 16px; margin-bottom: 1.5rem;
  display: flex; flex-direction: column; gap: 10px;
}
.wr-bar {
  display: flex; align-items: center; gap: 8px;
}
.wr-icon { color: #b8a0d0; flex-shrink: 0; }
.wr-icon.amber { color: #d4a017; }
.wr-label {
  font-size: 0.7rem; font-weight: 800; color: #b8a0d0;
  letter-spacing: 0.5px; min-width: 60px;
}
.wr-track {
  flex: 1; height: 10px; background: #2d2545;
  border: 2px solid #5c4578; border-radius: 5px; overflow: hidden;
}
.wr-fill {
  height: 100%; background: #c4a0e8; border-radius: 3px;
  transition: width 0.5s ease;
}
.wr-fill.amber { background: #ffe566; }
.wr-val {
  font-size: 0.85rem; font-weight: 700; color: #f0e4ff;
  font-family: 'Nunito', sans-serif; min-width: 36px; text-align: right;
}

/* Button */
.welcome-enter { margin-top: 0.5rem; }
.welcome-btn {
  width: 100%; padding: 14px;
  background: #ffe566; border: 2px outset #d4a017;
  color: #1a1528; font-size: 1rem; font-weight: 900;
  font-family: 'Nunito', sans-serif; letter-spacing: 2px;
  cursor: pointer; transition: 0.2s; border-radius: 10px;
}
.welcome-btn:hover {
  background: #ffd700; border-style: inset; transform: translateY(-1px);
}
.welcome-hint {
  font-size: 0.65rem; color: #8a70a8; margin-top: 10px;
  letter-spacing: 1px; font-weight: 700;
}
</style>
