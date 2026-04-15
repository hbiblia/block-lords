<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAuthStore } from '@/stores/auth';
import { getHomeStats } from '@/utils/api';
import { toggleLocale, getLocale } from '@/plugins/i18n';
import { Pickaxe, Coins, Users, Blocks, TrendingUp, Shield, Cpu } from 'lucide-vue-next';

const { t } = useI18n();
const authStore = useAuthStore();
const loginLoading = ref(false);
const loginError = ref('');
const isAuthenticated = computed(() => authStore.isAuthenticated);
const booted = ref(false);
const currentLocale = computed(() => getLocale());

const stats = ref<{
  totalPlayers: number;
  onlinePlayers: number;
  totalBlocks: number;
  totalCryptoEmitted: number;
  difficulty: number;
} | null>(null);

const loadingStats = ref(true);

async function loadStats() {
  try {
    const data = await getHomeStats();
    if (data) stats.value = data;
  } catch (e) {
    console.error('Error loading home stats:', e);
  } finally {
    loadingStats.value = false;
  }
}

function formatNumber(num: number | undefined | null): string {
  if (num == null) return '0';
  if (num >= 1000000) return (num / 1000000).toFixed(1) + 'M';
  if (num >= 1000) return (num / 1000).toFixed(1) + 'K';
  return num.toLocaleString();
}

function formatCrypto(num: number | undefined | null): string {
  if (num == null) return '0';
  if (num >= 1000000) return (num / 1000000).toFixed(1) + 'M';
  if (num >= 1000) return (num / 1000).toFixed(1) + 'K';
  return num.toFixed(2);
}

async function handleGoogleLogin() {
  loginError.value = '';
  loginLoading.value = true;
  const pendingRefCode = localStorage.getItem('pendingReferralCode');
  const tourCompleted = localStorage.getItem('miningTourCompleted');
  const lastSeenVersion = localStorage.getItem('lootmine-last-seen-version');
  localStorage.clear();
  if (pendingRefCode) localStorage.setItem('pendingReferralCode', pendingRefCode);
  if (tourCompleted) localStorage.setItem('miningTourCompleted', tourCompleted);
  if (lastSeenVersion) localStorage.setItem('lootmine-last-seen-version', lastSeenVersion);
  try {
    const success = await authStore.loginWithGoogle();
    if (!success) {
      loginError.value = authStore.error ?? t('login.googleError');
      loginLoading.value = false;
    }
  } catch (e) {
    loginError.value = t('login.unexpectedError');
    loginLoading.value = false;
  }
}

let statsInterval: number | null = null;

onMounted(() => {
  setTimeout(() => { booted.value = true; }, 50);
  loadStats();
  statsInterval = window.setInterval(loadStats, 30000);
});

onUnmounted(() => {
  if (statsInterval) { clearInterval(statsInterval); statsInterval = null; }
});
</script>

<template>
  <div class="hp-root" :class="{ booted }">

    <!-- HERO -->
    <section class="hp-hero">
      <button v-if="!isAuthenticated" class="hp-lang" @click="toggleLocale()">
        <span>{{ currentLocale === 'en' ? '🇺🇸 EN' : '🇪🇸 ES' }}</span>
      </button>

      <div class="hp-hero-inner">
        <div class="hp-logo">⛏️</div>
        <span class="hp-badge">{{ t('home.badge') }}</span>
        <h1 class="hp-title">{{ t('home.title') }}</h1>
        <p class="hp-subtitle">{{ t('home.subtitle') }}</p>

        <div v-if="!loadingStats && stats" class="hp-online">
          <span class="hp-online-dot"></span>
          <span>{{ formatNumber(stats.onlinePlayers) }} {{ t('home.stats.onlinePlayers').toLowerCase() }}</span>
        </div>

        <div v-if="loginError" class="hp-error">{{ loginError }}</div>

        <RouterLink v-if="isAuthenticated" to="/mining" class="hp-btn">
          {{ t('home.startMining') }}
        </RouterLink>
        <button v-else class="hp-google-btn" :disabled="loginLoading" @click="handleGoogleLogin">
          <svg class="hp-google-icon" viewBox="0 0 24 24" width="20" height="20">
            <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/>
            <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/>
            <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"/>
            <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"/>
          </svg>
          {{ loginLoading ? t('login.connecting') : t('login.continueGoogle') }}
        </button>
      </div>
    </section>

    <!-- STATS -->
    <section class="hp-stats">
      <div class="hp-section-label">NETWORK_TELEMETRY</div>
      <div class="hp-stats-grid">
        <div class="hp-stat">
          <div class="hp-stat-icon green"><Users :size="16" /></div>
          <div class="hp-stat-info">
            <span class="hp-stat-tag">ONLINE</span>
            <span class="hp-stat-value green">
              <template v-if="loadingStats">---</template>
              <template v-else>{{ formatNumber(stats?.onlinePlayers ?? 0) }}</template>
            </span>
            <span class="hp-stat-label">{{ t('home.stats.onlinePlayers') }}</span>
          </div>
        </div>
        <div class="hp-stat">
          <div class="hp-stat-icon purple"><Blocks :size="16" /></div>
          <div class="hp-stat-info">
            <span class="hp-stat-tag">BLOCKS</span>
            <span class="hp-stat-value purple">
              <template v-if="loadingStats">---</template>
              <template v-else>{{ formatNumber(stats?.totalBlocks ?? 0) }}</template>
            </span>
            <span class="hp-stat-label">{{ t('home.stats.blocksMined') }}</span>
          </div>
        </div>
        <div class="hp-stat">
          <div class="hp-stat-icon amber"><Pickaxe :size="16" /></div>
          <div class="hp-stat-info">
            <span class="hp-stat-tag">EMITTED</span>
            <span class="hp-stat-value amber">
              <template v-if="loadingStats">---</template>
              <template v-else>{{ formatCrypto(stats?.totalCryptoEmitted ?? 0) }} LW</template>
            </span>
            <span class="hp-stat-label">{{ t('home.stats.totalCryptoEmitted') }}</span>
          </div>
        </div>
        <div class="hp-stat">
          <div class="hp-stat-icon red"><TrendingUp :size="16" /></div>
          <div class="hp-stat-info">
            <span class="hp-stat-tag">DIFFICULTY</span>
            <span class="hp-stat-value red">
              <template v-if="loadingStats">---</template>
              <template v-else>{{ formatNumber(stats?.difficulty ?? 0) }}</template>
            </span>
            <span class="hp-stat-label">{{ t('home.stats.difficulty') }}</span>
          </div>
        </div>
      </div>
    </section>

    <!-- FEATURES -->
    <section class="hp-features">
      <div class="hp-section-label">CORE_SYSTEMS</div>
      <div class="hp-features-grid">
        <div class="hp-feature">
          <div class="hp-feature-icon amber"><Pickaxe :size="22" /></div>
          <h3 class="hp-feature-title">{{ t('home.features.mining.title') }}</h3>
          <p class="hp-feature-desc">{{ t('home.features.mining.description') }}</p>
          <div class="hp-feature-bar"><div class="hp-bar-fill amber"></div></div>
        </div>
        <div class="hp-feature">
          <div class="hp-feature-icon purple"><Coins :size="22" /></div>
          <h3 class="hp-feature-title">{{ t('home.features.economy.title') }}</h3>
          <p class="hp-feature-desc">{{ t('home.features.economy.description') }}</p>
          <div class="hp-feature-bar"><div class="hp-bar-fill purple"></div></div>
        </div>
        <div class="hp-feature">
          <div class="hp-feature-icon green"><Shield :size="22" /></div>
          <h3 class="hp-feature-title">Forge & Upgrades</h3>
          <p class="hp-feature-desc">Craft components, install cooling systems, and upgrade your rigs to maximize mining efficiency.</p>
          <div class="hp-feature-bar"><div class="hp-bar-fill green"></div></div>
        </div>
        <div class="hp-feature">
          <div class="hp-feature-icon red"><Cpu :size="22" /></div>
          <h3 class="hp-feature-title">Solo Mining</h3>
          <p class="hp-feature-desc">Mine independently with your own hashrate. Higher risk, higher reward. Find blocks solo and keep the full reward.</p>
          <div class="hp-feature-bar"><div class="hp-bar-fill red"></div></div>
        </div>
      </div>
    </section>

    <!-- HOW IT WORKS -->
    <section class="hp-hiw">
      <div class="hp-section-label">HOW_IT_WORKS</div>
      <div class="hp-hiw-panel">
        <div class="hp-step" v-for="n in 4" :key="n">
          <div class="hp-step-num">{{ String(n).padStart(2, '0') }}</div>
          <div class="hp-step-body">
            <h4 class="hp-step-title">{{ t(`home.howItWorks.step${n}.title`) }}</h4>
            <p class="hp-step-desc">{{ t(`home.howItWorks.step${n}.description`) }}</p>
          </div>
        </div>
      </div>
    </section>

    <!-- FOOTER CTA -->
    <section class="hp-footer-cta">
      <p class="hp-footer-text">Ready to start mining?</p>
      <RouterLink v-if="isAuthenticated" to="/mining" class="hp-btn">
        {{ t('home.startMining') }}
      </RouterLink>
      <button v-else class="hp-google-btn" :disabled="loginLoading" @click="handleGoogleLogin">
        <svg class="hp-google-icon" viewBox="0 0 24 24" width="20" height="20">
          <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/>
          <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/>
          <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"/>
          <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"/>
        </svg>
        {{ loginLoading ? t('login.connecting') : t('login.continueGoogle') }}
      </button>
    </section>

  </div>
</template>

<style scoped>
@import url('https://fonts.googleapis.com/css2?family=Nunito:wght@400;600;700;800;900&display=swap');

.hp-root {
  padding: 2rem 1rem;
  max-width: 900px;
  margin: 0 auto;
  display: flex; flex-direction: column; gap: 2rem;
  font-family: 'Nunito', 'Trebuchet MS', sans-serif;
  min-height: 100vh;
  background: #1a1528;
  background-image: radial-gradient(circle, #2d2545 1.5px, transparent 1.5px);
  background-size: 20px 20px;
}

/* ===== HERO ===== */
.hp-hero {
  position: relative;
  background: #1f1833;
  border: 2px solid #4a3660;
  border-radius: 16px;
  box-shadow: 4px 4px 0 rgba(74,54,96,0.3);
  padding: 3rem 2rem 2.5rem;
  text-align: center;
  overflow: hidden;
}
.hp-hero::before {
  content: ''; position: absolute; top: 0; left: 0; right: 0; height: 4px;
  background: linear-gradient(90deg, #4a3660, #ffe566, #4a3660);
}

.hp-lang {
  position: absolute; top: 12px; right: 12px;
  background: #231d35; border: 2px solid #5c4578; border-radius: 8px;
  padding: 4px 10px; cursor: pointer; font-size: 0.7rem; font-weight: 800;
  color: #b8a0d0; font-family: inherit; transition: 0.2s;
}
.hp-lang:hover { background: #ffe97a; border-color: #d4a017; color: #1a1528; }

.hp-hero-inner { position: relative; z-index: 1; }

.hp-logo { font-size: 3rem; margin-bottom: 0.8rem; }

.hp-badge {
  display: inline-block;
  font-size: 0.6rem; font-weight: 900; letter-spacing: 3px;
  color: #d4a017; background: #fff8e0; border: 2px solid #ffe566;
  padding: 4px 14px; border-radius: 20px; margin-bottom: 1rem;
}

.hp-title {
  font-size: 2.2rem; font-weight: 900; letter-spacing: 2px;
  color: #f0e4ff; margin: 0 0 0.6rem; line-height: 1.2;
}

.hp-subtitle {
  font-size: 0.9rem; font-weight: 600; color: #8a70a8;
  max-width: 480px; margin: 0 auto 1.2rem; line-height: 1.6;
}

.hp-online {
  display: flex; align-items: center; justify-content: center; gap: 6px;
  margin-bottom: 1.2rem; font-size: 0.75rem; font-weight: 800; color: #7cc490;
  letter-spacing: 1px;
}
.hp-online-dot {
  width: 8px; height: 8px; border-radius: 50%; background: #7cc490;
  border: 2px solid #a8d0b8;
  animation: hp-pulse 1.5s infinite;
}
@keyframes hp-pulse { 0%,100% { opacity: 1; } 50% { opacity: 0.3; } }

.hp-btn {
  display: inline-block;
  padding: 14px 40px;
  background: #ffe566; border: 2px outset #d4a017;
  color: #1a1528; font-size: 1rem; font-weight: 900;
  font-family: 'Nunito', sans-serif; letter-spacing: 2px;
  text-decoration: none; cursor: pointer;
  transition: 0.2s; border-radius: 10px;
}
.hp-btn:hover { background: #ffd700; border-style: inset; transform: translateY(-2px); }

.hp-google-btn {
  display: inline-flex; align-items: center; justify-content: center; gap: 10px;
  padding: 14px 32px;
  background: #1f1833; border: 2px solid #5c4578;
  color: #f0e4ff; font-size: 0.9rem; font-weight: 800;
  font-family: 'Nunito', sans-serif; letter-spacing: 0.5px;
  cursor: pointer; transition: 0.2s; border-radius: 10px;
  box-shadow: 2px 2px 0 rgba(74,54,96,0.3);
}
.hp-google-btn:hover { border-color: #b088d0; box-shadow: 3px 3px 0 #d8c0ee; transform: translateY(-2px); }
.hp-google-btn:disabled { opacity: 0.5; cursor: not-allowed; transform: none; }
.hp-google-icon { flex-shrink: 0; }

.hp-error {
  background: #fff0f0; border: 2px solid #ff7b7b; border-radius: 8px;
  padding: 8px 14px; margin-bottom: 1rem;
  font-size: 0.75rem; font-weight: 700; color: #c04040; text-align: center;
}

/* ===== SECTION LABEL ===== */
.hp-section-label {
  font-size: 0.6rem; font-weight: 900; color: #8a70a8;
  letter-spacing: 3px; padding-left: 4px;
}

/* ===== STATS ===== */
.hp-stats { display: flex; flex-direction: column; gap: 0.6rem; }
.hp-stats-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 10px; }

.hp-stat {
  background: #1f1833; border: 2px solid #5c4578; border-radius: 12px;
  padding: 14px; display: flex; align-items: flex-start; gap: 12px;
  box-shadow: 2px 2px 0 rgba(74,54,96,0.3); transition: 0.2s;
}
.hp-stat:hover { border-color: #b088d0; transform: translateY(-2px); }

.hp-stat-icon {
  width: 36px; height: 36px; border-radius: 10px;
  display: flex; align-items: center; justify-content: center; flex-shrink: 0;
}
.hp-stat-icon.green { background: #e8f8ec; color: #3a7a4a; }
.hp-stat-icon.purple { background: #2d2545; color: #b8a0d0; }
.hp-stat-icon.amber { background: #fff8e0; color: #d4a017; }
.hp-stat-icon.red { background: #fff0f0; color: #cc4444; }

.hp-stat-info { display: flex; flex-direction: column; gap: 2px; min-width: 0; }
.hp-stat-tag { font-size: 0.5rem; font-weight: 900; color: #8a70a8; letter-spacing: 2px; }
.hp-stat-value {
  font-size: 1.2rem; font-weight: 900;
  font-family: 'Nunito', sans-serif; line-height: 1.2;
}
.hp-stat-value.green { color: #3a7a4a; }
.hp-stat-value.purple { color: #b8a0d0; }
.hp-stat-value.amber { color: #d4a017; }
.hp-stat-value.red { color: #cc4444; }
.hp-stat-label { font-size: 0.55rem; font-weight: 700; color: #8a70a8; letter-spacing: 0.5px; }

/* ===== FEATURES ===== */
.hp-features { display: flex; flex-direction: column; gap: 0.6rem; }
.hp-features-grid { display: grid; grid-template-columns: repeat(2, 1fr); gap: 10px; }

.hp-feature {
  background: #1f1833; border: 2px solid #5c4578; border-radius: 12px;
  padding: 1.2rem; box-shadow: 2px 2px 0 rgba(74,54,96,0.3); transition: 0.2s;
}
.hp-feature:hover { border-color: #b088d0; transform: translateY(-2px); }

.hp-feature-icon {
  width: 44px; height: 44px; border-radius: 12px;
  display: flex; align-items: center; justify-content: center;
  margin-bottom: 0.8rem;
}
.hp-feature-icon.amber { background: #fff8e0; color: #d4a017; }
.hp-feature-icon.purple { background: #2d2545; color: #b8a0d0; }
.hp-feature-icon.green { background: #e8f8ec; color: #3a7a4a; }
.hp-feature-icon.red { background: #fff0f0; color: #cc4444; }

.hp-feature-title {
  font-size: 0.95rem; font-weight: 900; color: #f0e4ff;
  margin: 0 0 0.4rem; letter-spacing: 0.5px;
}
.hp-feature-desc {
  font-size: 0.75rem; font-weight: 600; color: #8a70a8;
  line-height: 1.5; margin: 0 0 0.8rem;
}
.hp-feature-bar {
  height: 4px; background: #2d2545; border-radius: 2px; overflow: hidden;
}
.hp-bar-fill { height: 100%; width: 70%; border-radius: 2px; }
.hp-bar-fill.amber { background: linear-gradient(90deg, #ffe566, #d4a017); }
.hp-bar-fill.purple { background: linear-gradient(90deg, #5c4578, #8a60b0); }
.hp-bar-fill.green { background: linear-gradient(90deg, #a8d0b8, #3a7a4a); }
.hp-bar-fill.red { background: linear-gradient(90deg, #ffb0b0, #cc4444); }

/* ===== HOW IT WORKS ===== */
.hp-hiw { display: flex; flex-direction: column; gap: 0.6rem; }
.hp-hiw-panel {
  background: #1f1833; border: 2px solid #4a3660; border-radius: 14px;
  box-shadow: 4px 4px 0 rgba(74,54,96,0.3); overflow: hidden;
  display: grid; grid-template-columns: repeat(4, 1fr);
}

.hp-step {
  padding: 1.2rem; border-right: 1px solid #3a2d50;
  display: flex; flex-direction: column; gap: 0.5rem;
}
.hp-step:last-child { border-right: none; }

.hp-step-num {
  font-size: 1.6rem; font-weight: 900; color: #c4a0e8;
  font-family: 'Nunito', sans-serif; line-height: 1; opacity: 0.6;
}
.hp-step-body { flex: 1; }
.hp-step-title {
  font-size: 0.8rem; font-weight: 900; color: #f0e4ff;
  margin: 0 0 0.3rem; letter-spacing: 0.5px;
}
.hp-step-desc {
  font-size: 0.7rem; font-weight: 600; color: #8a70a8;
  line-height: 1.5; margin: 0;
}

/* ===== FOOTER CTA ===== */
.hp-footer-cta {
  text-align: center; padding: 2rem 0;
}
.hp-footer-text {
  font-size: 1.1rem; font-weight: 800; color: #b8a0d0;
  margin: 0 0 1rem;
}

/* ===== BOOT ANIMATION ===== */
.hp-hero, .hp-stats, .hp-features, .hp-hiw, .hp-footer-cta {
  opacity: 0; transform: translateY(15px);
  transition: opacity 0.5s ease, transform 0.5s cubic-bezier(0.16,1,0.3,1);
}
.booted .hp-hero { opacity: 1; transform: none; transition-delay: 0.1s; }
.booted .hp-stats { opacity: 1; transform: none; transition-delay: 0.3s; }
.booted .hp-features { opacity: 1; transform: none; transition-delay: 0.5s; }
.booted .hp-hiw { opacity: 1; transform: none; transition-delay: 0.7s; }
.booted .hp-footer-cta { opacity: 1; transform: none; transition-delay: 0.9s; }

/* ===== MOBILE ===== */
@media (max-width: 768px) {
  .hp-title { font-size: 1.6rem; }
  .hp-stats-grid { grid-template-columns: repeat(2, 1fr); }
  .hp-features-grid { grid-template-columns: 1fr; }
  .hp-hiw-panel { grid-template-columns: 1fr; }
  .hp-step { border-right: none; border-bottom: 1px solid #3a2d50; }
  .hp-step:last-child { border-bottom: none; }
}

@media (max-width: 480px) {
  .hp-root { padding: 1rem 0.5rem; gap: 1.5rem; }
  .hp-hero { padding: 2rem 1rem; }
  .hp-title { font-size: 1.3rem; }
  .hp-stat-value { font-size: 1rem; }
  .hp-stat { flex-direction: column; gap: 8px; }
}
</style>
