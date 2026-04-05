<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAuthStore } from '@/stores/auth';
import { getHomeStats } from '@/utils/api';
import { toggleLocale, getLocale } from '@/plugins/i18n';
import { Pickaxe, Coins } from 'lucide-vue-next';

const { t } = useI18n();

const authStore = useAuthStore();
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
    if (data) {
      stats.value = data;
    }
  } catch (e) {
    console.error('Error loading home stats:', e);
  } finally {
    loadingStats.value = false;
  }
}

function formatNumber(num: number | undefined | null): string {
  if (num == null) return '0';
  if (num >= 1000000) {
    return (num / 1000000).toFixed(1) + 'M';
  } else if (num >= 1000) {
    return (num / 1000).toFixed(1) + 'K';
  }
  return num.toLocaleString();
}

function formatCryptoStat(num: number | undefined | null): string {
  if (num == null) return '0 ₿';
  if (num >= 1000000) {
    return (num / 1000000).toFixed(1) + 'M ₿';
  } else if (num >= 1000) {
    return (num / 1000).toFixed(1) + 'K ₿';
  }
  return num.toFixed(2) + ' ₿';
}

// Polling interval for stats refresh
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

    <!-- === HERO SECTION === -->
    <section class="hp-hero">
      <div class="hp-hero-corners">
        <div class="hc hc-tl"></div>
        <div class="hc hc-tr"></div>
        <div class="hc hc-bl"></div>
        <div class="hc hc-br"></div>
      </div>
      <div class="hp-hero-scan"></div>
      <div class="hp-hero-crt"></div>

      <!-- Language toggle (top-right) -->
      <button v-if="!isAuthenticated" class="hp-lang" @click="toggleLocale()">
        <span class="hp-lang-flag">{{ currentLocale === 'en' ? '🇺🇸' : '🇪🇸' }}</span>
        <span class="hp-lang-code">{{ currentLocale === 'en' ? 'EN' : 'ES' }}</span>
      </button>

      <div class="hp-hero-inner">
        <span class="hp-badge">// {{ t('home.badge') }}</span>

        <h1 class="hp-title">{{ t('home.title') }}</h1>

        <p class="hp-subtitle">{{ t('home.subtitle') }}</p>

        <!-- Online indicator -->
        <div v-if="!isAuthenticated && !loadingStats && stats" class="hp-online">
          <span class="hp-online-dot"></span>
          <span class="hp-online-text">{{ formatNumber(stats.onlinePlayers) }} {{ t('home.stats.onlinePlayers').toLowerCase() }}</span>
        </div>

        <!-- CTA -->
        <div class="hp-cta">
          <RouterLink v-if="!isAuthenticated" to="/login" class="hp-btn">
            <span class="hp-btn-corners">
              <span class="bc bc-tl"></span><span class="bc bc-tr"></span>
              <span class="bc bc-bl"></span><span class="bc bc-br"></span>
            </span>
            <span class="hp-btn-text">{{ t('home.startMining') }}</span>
            <span class="hp-btn-arrow">▶</span>
          </RouterLink>
          <RouterLink v-else to="/mining" class="hp-btn">
            <span class="hp-btn-corners">
              <span class="bc bc-tl"></span><span class="bc bc-tr"></span>
              <span class="bc bc-bl"></span><span class="bc bc-br"></span>
            </span>
            <span class="hp-btn-text">{{ t('home.startMining') }}</span>
            <span class="hp-btn-arrow">▶</span>
          </RouterLink>
        </div>
      </div>
    </section>

    <!-- === LIVE STATS === -->
    <section class="hp-stats">
      <div class="hp-stats-label">// NETWORK_TELEMETRY</div>
      <div class="hp-stats-grid">
        <div class="hp-stat">
          <div class="hp-stat-corners">
            <span class="sc sc-tl"></span><span class="sc sc-tr"></span>
            <span class="sc sc-bl"></span><span class="sc sc-br"></span>
          </div>
          <div class="hp-stat-header">
            <span class="hp-stat-dot hp-dot-green"></span>
            <span class="hp-stat-tag">ONLINE</span>
          </div>
          <div class="hp-stat-value hp-val-green">
            <template v-if="loadingStats">---</template>
            <template v-else>{{ formatNumber(stats?.onlinePlayers ?? 0) }}</template>
          </div>
          <div class="hp-stat-label">{{ t('home.stats.onlinePlayers') }}</div>
        </div>

        <div class="hp-stat">
          <div class="hp-stat-corners">
            <span class="sc sc-tl"></span><span class="sc sc-tr"></span>
            <span class="sc sc-bl"></span><span class="sc sc-br"></span>
          </div>
          <div class="hp-stat-header">
            <span class="hp-stat-dot hp-dot-cyan"></span>
            <span class="hp-stat-tag">BLOCKS</span>
          </div>
          <div class="hp-stat-value hp-val-cyan">
            <template v-if="loadingStats">---</template>
            <template v-else>{{ formatNumber(stats?.totalBlocks ?? 0) }}</template>
          </div>
          <div class="hp-stat-label">{{ t('home.stats.blocksMined') }}</div>
        </div>

        <div class="hp-stat">
          <div class="hp-stat-corners">
            <span class="sc sc-tl"></span><span class="sc sc-tr"></span>
            <span class="sc sc-bl"></span><span class="sc sc-br"></span>
          </div>
          <div class="hp-stat-header">
            <span class="hp-stat-dot hp-dot-amber"></span>
            <span class="hp-stat-tag">EMITTED</span>
          </div>
          <div class="hp-stat-value hp-val-amber">
            <template v-if="loadingStats">---</template>
            <template v-else>{{ formatCryptoStat(stats?.totalCryptoEmitted ?? 0) }}</template>
          </div>
          <div class="hp-stat-label">{{ t('home.stats.totalCryptoEmitted') }}</div>
        </div>

        <div class="hp-stat">
          <div class="hp-stat-corners">
            <span class="sc sc-tl"></span><span class="sc sc-tr"></span>
            <span class="sc sc-bl"></span><span class="sc sc-br"></span>
          </div>
          <div class="hp-stat-header">
            <span class="hp-stat-dot hp-dot-red"></span>
            <span class="hp-stat-tag">DIFF</span>
          </div>
          <div class="hp-stat-value hp-val-red">
            <template v-if="loadingStats">---</template>
            <template v-else>{{ formatNumber(stats?.difficulty ?? 0) }}</template>
          </div>
          <div class="hp-stat-label">{{ t('home.stats.difficulty') }}</div>
        </div>
      </div>
    </section>

    <!-- === FEATURES === -->
    <section class="hp-features">
      <div class="hp-section-label">// CORE_SYSTEMS</div>
      <div class="hp-features-grid">
        <div class="hp-feature">
          <div class="hp-feature-corners">
            <span class="fc fc-tl"></span><span class="fc fc-tr"></span>
            <span class="fc fc-bl"></span><span class="fc fc-br"></span>
          </div>
          <div class="hp-feature-scan"></div>
          <div class="hp-feature-icon"><Pickaxe :size="24" color="#f59e0b" /></div>
          <div class="hp-feature-tag">SYS_01</div>
          <h3 class="hp-feature-title">{{ t('home.features.mining.title') }}</h3>
          <p class="hp-feature-desc">{{ t('home.features.mining.description') }}</p>
          <div class="hp-feature-bar">
            <div class="hp-feature-bar-fill hp-bar-amber"></div>
            <div class="hp-feature-bar-segs"></div>
          </div>
        </div>

        <div class="hp-feature">
          <div class="hp-feature-corners">
            <span class="fc fc-tl"></span><span class="fc fc-tr"></span>
            <span class="fc fc-bl"></span><span class="fc fc-br"></span>
          </div>
          <div class="hp-feature-scan"></div>
          <div class="hp-feature-icon"><Coins :size="24" color="#06b6d4" /></div>
          <div class="hp-feature-tag">SYS_02</div>
          <h3 class="hp-feature-title">{{ t('home.features.economy.title') }}</h3>
          <p class="hp-feature-desc">{{ t('home.features.economy.description') }}</p>
          <div class="hp-feature-bar">
            <div class="hp-feature-bar-fill hp-bar-cyan"></div>
            <div class="hp-feature-bar-segs"></div>
          </div>
        </div>

      </div>
    </section>

    <!-- === HOW IT WORKS === -->
    <section class="hp-hiw">
      <div class="hp-hiw-panel">
        <div class="hp-hiw-corners">
          <span class="hc hc-tl"></span><span class="hc hc-tr"></span>
          <span class="hc hc-bl"></span><span class="hc hc-br"></span>
        </div>
        <div class="hp-hiw-scan"></div>

        <div class="hp-hiw-header">
          <span class="hp-hiw-indicator"></span>
          <span class="hp-hiw-title">{{ t('home.howItWorks.title') }}</span>
          <span class="hp-hiw-tag">PROTOCOL</span>
        </div>

        <div class="hp-hiw-grid">
          <div class="hp-step" v-for="n in 4" :key="n">
            <div class="hp-step-num">{{ String(n).padStart(2, '0') }}</div>
            <div class="hp-step-content">
              <h4 class="hp-step-title">{{ t(`home.howItWorks.step${n}.title`) }}</h4>
              <p class="hp-step-desc">{{ t(`home.howItWorks.step${n}.description`) }}</p>
            </div>
            <div class="hp-step-line" v-if="n < 4"></div>
          </div>
        </div>
      </div>
    </section>

  </div>
</template>

<style scoped>
/* ===== ROOT ===== */
.hp-root {
  padding: 1.5rem 1rem 2rem;
  max-width: 900px;
  margin: 0 auto;
  display: flex;
  flex-direction: column;
  gap: 2rem;
}

/* ===== HERO ===== */
.hp-hero {
  position: relative;
  overflow: hidden;
  border: 1px solid #2f3052;
  background: linear-gradient(135deg, rgba(16,17,35,0.98) 0%, rgba(26,27,46,0.96) 100%);
  padding: 2.5rem 1.5rem 2rem;
  text-align: center;
}
.hp-hero::before {
  content: ''; position: absolute; inset: 0; pointer-events: none;
  background: repeating-linear-gradient(0deg, transparent, transparent 3px, rgba(255,255,255,0.005) 3px, rgba(255,255,255,0.005) 4px);
  z-index: 1;
}

/* Hero corners */
.hc { position: absolute; width: 14px; height: 14px; pointer-events: none; z-index: 3; }
.hc-tl { top: 0; left: 0; border-top: 2px solid #f59e0b; border-left: 2px solid #f59e0b; }
.hc-tr { top: 0; right: 0; border-top: 2px solid #f59e0b; border-right: 2px solid #f59e0b; }
.hc-bl { bottom: 0; left: 0; border-bottom: 2px solid #f59e0b; border-left: 2px solid #f59e0b; }
.hc-br { bottom: 0; right: 0; border-bottom: 2px solid #f59e0b; border-right: 2px solid #f59e0b; }

.hp-hero-scan {
  position: absolute; top: 0; left: -100%; width: 100%; height: 100%; pointer-events: none; z-index: 1;
  background: linear-gradient(90deg, transparent 0%, rgba(245,158,11,0.02) 45%, rgba(245,158,11,0.05) 50%, rgba(245,158,11,0.02) 55%, transparent 100%);
  animation: hp-scan 5s linear infinite;
}
@keyframes hp-scan { 0% { left: -100%; } 100% { left: 100%; } }

.hp-hero-crt { position: absolute; inset: 0; pointer-events: none; z-index: 1; }

.hp-hero-inner { position: relative; z-index: 2; }

.hp-badge {
  display: inline-block;
  font-size: 0.55rem; font-weight: 900; letter-spacing: 3px; color: #f59e0b;
  padding: 4px 12px;
  border: 1px solid rgba(245,158,11,0.2);
  background: rgba(245,158,11,0.05);
  margin-bottom: 1rem;
}

.hp-title {
  font-size: 2rem; font-weight: 900; letter-spacing: 3px;
  color: #f59e0b;
  text-shadow: 0 0 20px rgba(245,158,11,0.3), 0 0 40px rgba(245,158,11,0.1);
  margin: 0 0 0.8rem;
  line-height: 1.2;
}

.hp-subtitle {
  font-size: 0.8rem; font-weight: 600; color: #71717a;
  max-width: 500px; margin: 0 auto 1.2rem; line-height: 1.5;
  letter-spacing: 0.5px;
}

/* Language button */
.hp-lang {
  position: absolute; top: 0.6rem; right: 0.6rem; z-index: 4;
  display: flex; align-items: center; gap: 0.3rem;
  padding: 0.25rem 0.5rem;
  border: 1px solid #2f3052;
  background: rgba(26,27,46,0.8);
  cursor: pointer;
  transition: all 0.2s;
}
.hp-lang:hover { border-color: #4f4f6f; }
.hp-lang-flag { font-size: 0.75rem; }
.hp-lang-code { font-size: 0.5rem; font-weight: 900; color: #71717a; letter-spacing: 1.5px; }

.hp-online {
  display: flex; align-items: center; justify-content: center; gap: 6px;
  margin-bottom: 1rem;
}
.hp-online-dot {
  width: 6px; height: 6px; border-radius: 50%; background: #22c55e;
  box-shadow: 0 0 6px #22c55e80;
  animation: hp-pulse 1.5s infinite;
}
@keyframes hp-pulse { 0%,100% { opacity: 1; } 50% { opacity: 0.3; } }
.hp-online-text { font-size: 0.65rem; font-weight: 800; color: #22c55e; letter-spacing: 1px; }

.hp-cta { margin-top: 0.5rem; }

/* CTA Button */
.hp-btn {
  display: inline-flex; align-items: center; gap: 10px;
  position: relative;
  padding: 10px 28px;
  border: 1px solid #f59e0b;
  background: linear-gradient(135deg, rgba(245,158,11,0.1) 0%, rgba(245,158,11,0.05) 100%);
  color: #f59e0b; font-size: 0.7rem; font-weight: 900; letter-spacing: 2.5px;
  text-decoration: none;
  transition: all 0.3s;
  cursor: pointer;
}
.hp-btn:hover {
  background: linear-gradient(135deg, rgba(245,158,11,0.2) 0%, rgba(245,158,11,0.1) 100%);
  box-shadow: 0 0 20px rgba(245,158,11,0.15), inset 0 0 20px rgba(245,158,11,0.05);
}
.hp-btn-corners { position: absolute; inset: 0; pointer-events: none; }
.bc { position: absolute; width: 6px; height: 6px; }
.bc-tl { top: -1px; left: -1px; border-top: 2px solid #f59e0b; border-left: 2px solid #f59e0b; }
.bc-tr { top: -1px; right: -1px; border-top: 2px solid #f59e0b; border-right: 2px solid #f59e0b; }
.bc-bl { bottom: -1px; left: -1px; border-bottom: 2px solid #f59e0b; border-left: 2px solid #f59e0b; }
.bc-br { bottom: -1px; right: -1px; border-bottom: 2px solid #f59e0b; border-right: 2px solid #f59e0b; }
.hp-btn-text { position: relative; z-index: 1; }
.hp-btn-arrow { font-size: 0.5rem; opacity: 0.7; animation: hp-arrow 1.5s infinite; }
@keyframes hp-arrow { 0%,100% { transform: translateX(0); } 50% { transform: translateX(3px); } }

/* ===== STATS ===== */
.hp-stats { display: flex; flex-direction: column; gap: 0.6rem; }

.hp-stats-label, .hp-section-label, .hp-ad-label {
  font-size: 0.45rem; font-weight: 900; color: #4f4f6f; letter-spacing: 3px;
  padding-left: 2px;
}

.hp-stats-grid {
  display: grid; grid-template-columns: repeat(4, 1fr); gap: 0.6rem;
}

.hp-stat {
  position: relative;
  border: 1px solid #2f3052;
  background: linear-gradient(135deg, rgba(16,17,35,0.98) 0%, rgba(26,27,46,0.96) 100%);
  padding: 0.6rem 0.7rem;
  overflow: hidden;
  transition: border-color 0.3s;
}
.hp-stat:hover { border-color: #4f4f6f; }

.hp-stat::before {
  content: ''; position: absolute; inset: 0; pointer-events: none;
  background: repeating-linear-gradient(0deg, transparent, transparent 3px, rgba(255,255,255,0.005) 3px, rgba(255,255,255,0.005) 4px);
}

/* Stat corners */
.hp-stat-corners { position: absolute; inset: 0; pointer-events: none; z-index: 2; }
.sc { position: absolute; width: 8px; height: 8px; }
.sc-tl { top: 0; left: 0; border-top: 2px solid #f59e0b; border-left: 2px solid #f59e0b; }
.sc-tr { top: 0; right: 0; border-top: 2px solid #f59e0b; border-right: 2px solid #f59e0b; }
.sc-bl { bottom: 0; left: 0; border-bottom: 2px solid #f59e0b; border-left: 2px solid #f59e0b; }
.sc-br { bottom: 0; right: 0; border-bottom: 2px solid #f59e0b; border-right: 2px solid #f59e0b; }

.hp-stat-header {
  display: flex; align-items: center; gap: 5px; margin-bottom: 0.4rem;
  position: relative; z-index: 1;
}
.hp-stat-dot {
  width: 5px; height: 5px; border-radius: 50%; flex-shrink: 0;
  animation: hp-pulse 1.5s infinite;
}
.hp-dot-green { background: #22c55e; box-shadow: 0 0 6px #22c55e80; }
.hp-dot-cyan { background: #06b6d4; box-shadow: 0 0 6px #06b6d480; }
.hp-dot-amber { background: #f59e0b; box-shadow: 0 0 6px #f59e0b80; }
.hp-dot-red { background: #ef4444; box-shadow: 0 0 6px #ef444480; }

.hp-stat-tag {
  font-size: 0.4rem; font-weight: 900; color: #4f4f6f; letter-spacing: 2px;
}

.hp-stat-value {
  font-size: 1.2rem; font-weight: 900; letter-spacing: 1px;
  position: relative; z-index: 1;
  font-family: 'JetBrains Mono', monospace;
  margin-bottom: 0.15rem;
}
.hp-val-green { color: #22c55e; text-shadow: 0 0 10px rgba(34,197,94,0.2); }
.hp-val-cyan { color: #06b6d4; text-shadow: 0 0 10px rgba(6,182,212,0.2); }
.hp-val-amber { color: #f59e0b; text-shadow: 0 0 10px rgba(245,158,11,0.2); }
.hp-val-red { color: #ef4444; text-shadow: 0 0 10px rgba(239,68,68,0.2); }

.hp-stat-label {
  font-size: 0.45rem; font-weight: 800; color: #52525b; letter-spacing: 1.5px;
  position: relative; z-index: 1;
}

/* ===== FEATURES ===== */
.hp-features { display: flex; flex-direction: column; gap: 0.6rem; }

.hp-features-grid {
  display: grid; grid-template-columns: repeat(2, 1fr); gap: 0.6rem;
}

.hp-feature {
  position: relative; overflow: hidden;
  border: 1px solid #2f3052;
  background: linear-gradient(135deg, rgba(16,17,35,0.98) 0%, rgba(26,27,46,0.96) 100%);
  padding: 1rem 0.8rem 0.7rem;
  transition: border-color 0.3s;
}
.hp-feature:hover { border-color: #4f4f6f; }

.hp-feature::before {
  content: ''; position: absolute; inset: 0; pointer-events: none;
  background: repeating-linear-gradient(0deg, transparent, transparent 3px, rgba(255,255,255,0.005) 3px, rgba(255,255,255,0.005) 4px);
  z-index: 1;
}

/* Feature corners */
.hp-feature-corners { position: absolute; inset: 0; pointer-events: none; z-index: 3; }
.fc { position: absolute; width: 10px; height: 10px; }
.fc-tl { top: 0; left: 0; border-top: 2px solid #f59e0b; border-left: 2px solid #f59e0b; }
.fc-tr { top: 0; right: 0; border-top: 2px solid #f59e0b; border-right: 2px solid #f59e0b; }
.fc-bl { bottom: 0; left: 0; border-bottom: 2px solid #f59e0b; border-left: 2px solid #f59e0b; }
.fc-br { bottom: 0; right: 0; border-bottom: 2px solid #f59e0b; border-right: 2px solid #f59e0b; }

.hp-feature-scan {
  position: absolute; top: 0; left: -100%; width: 100%; height: 100%; pointer-events: none; z-index: 1;
  background: linear-gradient(90deg, transparent 0%, rgba(245,158,11,0.02) 45%, rgba(245,158,11,0.05) 50%, rgba(245,158,11,0.02) 55%, transparent 100%);
  animation: hp-scan 6s linear infinite;
}

.hp-feature-icon {
  margin-bottom: 0.5rem;
  opacity: 0.85;
  position: relative; z-index: 2;
}

.hp-feature-tag {
  font-size: 0.4rem; font-weight: 900; color: #4f4f6f; letter-spacing: 2.5px;
  margin-bottom: 0.4rem;
  position: relative; z-index: 2;
}

.hp-feature-title {
  font-size: 0.8rem; font-weight: 900; color: #e5e7eb;
  letter-spacing: 1px; margin: 0 0 0.3rem;
  position: relative; z-index: 2;
}

.hp-feature-desc {
  font-size: 0.6rem; font-weight: 600; color: #71717a; line-height: 1.5;
  margin: 0 0 0.7rem;
  position: relative; z-index: 2;
}

.hp-feature-bar {
  height: 3px; position: relative; background: #1a1b2e; overflow: hidden; z-index: 2;
}
.hp-feature-bar-fill {
  position: absolute; top: 0; left: 0; height: 100%; width: 70%;
}
.hp-bar-amber { background: linear-gradient(90deg, rgba(245,158,11,0.3), #f59e0b); }
.hp-bar-cyan { background: linear-gradient(90deg, rgba(6,182,212,0.3), #06b6d4); }
.hp-bar-green { background: linear-gradient(90deg, rgba(34,197,94,0.3), #22c55e); }
.hp-feature-bar-segs {
  position: absolute; inset: 0; pointer-events: none;
  background: repeating-linear-gradient(90deg, transparent 0px, transparent 9%, rgba(16,17,35,0.8) 9%, rgba(16,17,35,0.8) 10%);
}

/* ===== HOW IT WORKS ===== */
.hp-hiw-panel {
  position: relative; overflow: hidden;
  border: 1px solid #2f3052;
  background: linear-gradient(135deg, rgba(16,17,35,0.98) 0%, rgba(26,27,46,0.96) 100%);
}
.hp-hiw-panel::before {
  content: ''; position: absolute; inset: 0; pointer-events: none;
  background: repeating-linear-gradient(0deg, transparent, transparent 3px, rgba(255,255,255,0.005) 3px, rgba(255,255,255,0.005) 4px);
  z-index: 1;
}

.hp-hiw-corners { position: absolute; inset: 0; pointer-events: none; z-index: 3; }

.hp-hiw-scan {
  position: absolute; top: 0; left: -100%; width: 100%; height: 100%; pointer-events: none; z-index: 1;
  background: linear-gradient(90deg, transparent 0%, rgba(245,158,11,0.02) 45%, rgba(245,158,11,0.05) 50%, rgba(245,158,11,0.02) 55%, transparent 100%);
  animation: hp-scan 7s linear infinite;
}

.hp-hiw-header {
  display: flex; align-items: center; gap: 8px;
  padding: 0.7rem 1rem;
  border-bottom: 1px solid #2f3052;
  position: relative; z-index: 2;
  background: linear-gradient(180deg, rgba(245,158,11,0.03) 0%, transparent 100%);
}
.hp-hiw-indicator {
  width: 6px; height: 6px; background: #f59e0b;
  clip-path: polygon(50% 0%, 100% 50%, 50% 100%, 0% 50%);
  animation: hp-pulse 1.5s infinite;
}
.hp-hiw-title {
  flex: 1; font-size: 0.7rem; font-weight: 900; color: #f59e0b; letter-spacing: 2px;
  text-shadow: 0 0 10px rgba(245,158,11,0.2);
}
.hp-hiw-tag {
  font-size: 0.4rem; font-weight: 900; color: #4f4f6f; letter-spacing: 2px;
  padding: 2px 8px; border: 1px solid #2f3052;
}

.hp-hiw-grid {
  display: grid; grid-template-columns: repeat(4, 1fr);
  position: relative; z-index: 2;
}

.hp-step {
  position: relative;
  padding: 1rem 0.8rem;
  border-right: 1px solid #2f3052;
  display: flex; flex-direction: column; gap: 0.4rem;
}
.hp-step:last-child { border-right: none; }

.hp-step-num {
  font-size: 1.4rem; font-weight: 900; color: #f59e0b;
  font-family: 'JetBrains Mono', monospace;
  text-shadow: 0 0 15px rgba(245,158,11,0.2);
  line-height: 1;
  opacity: 0.7;
}

.hp-step-content { flex: 1; }

.hp-step-title {
  font-size: 0.7rem; font-weight: 900; color: #e5e7eb;
  letter-spacing: 0.5px; margin: 0 0 0.3rem;
}

.hp-step-desc {
  font-size: 0.55rem; font-weight: 600; color: #71717a;
  line-height: 1.5; margin: 0;
}

.hp-step-line {
  display: none;
}

/* ===== BOOT ANIMATION ===== */
.hp-hero {
  opacity: 0; transform: translateY(-20px);
  transition: opacity 0.5s ease, transform 0.5s cubic-bezier(0.16,1,0.3,1);
}
.hp-stats {
  opacity: 0; transform: translateY(15px);
  transition: opacity 0.5s ease, transform 0.5s cubic-bezier(0.16,1,0.3,1);
}
.hp-features {
  opacity: 0; transform: translateY(15px);
  transition: opacity 0.5s ease, transform 0.5s cubic-bezier(0.16,1,0.3,1);
}
.hp-hiw {
  opacity: 0; transform: translateY(15px);
  transition: opacity 0.5s ease, transform 0.5s cubic-bezier(0.16,1,0.3,1);
}

.booted .hp-hero { opacity: 1; transform: none; transition-delay: 0.1s; }
.booted .hp-stats { opacity: 1; transform: none; transition-delay: 0.4s; }
.booted .hp-features { opacity: 1; transform: none; transition-delay: 0.7s; }
.booted .hp-hiw { opacity: 1; transform: none; transition-delay: 1s; }

/* ===== MOBILE ===== */
@media (max-width: 768px) {
  .hp-title { font-size: 1.4rem; letter-spacing: 2px; }
  .hp-stats-grid { grid-template-columns: repeat(2, 1fr); }
  .hp-features-grid { grid-template-columns: 1fr; }
  .hp-hiw-grid { grid-template-columns: 1fr; }
  .hp-step { border-right: none; border-bottom: 1px solid #2f3052; }
  .hp-step:last-child { border-bottom: none; }
}

@media (max-width: 480px) {
  .hp-root { padding: 1rem 0.5rem; gap: 1.5rem; }
  .hp-hero { padding: 1.5rem 1rem; }
  .hp-title { font-size: 1.2rem; }
  .hp-subtitle { font-size: 0.7rem; }
  .hp-stat-value { font-size: 1rem; }
}
</style>
