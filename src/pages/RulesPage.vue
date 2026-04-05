<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import { Shield, Pickaxe, Store, Swords, AlertTriangle, Users, ScrollText } from 'lucide-vue-next';

const { t } = useI18n();

const sections = [
  { num: '01', key: 'general', color: '#f59e0b', icon: Shield, items: ['oneAccount', 'fairPlay', 'noExploits', 'simulation'] },
  { num: '02', key: 'mining', color: '#06b6d4', icon: Pickaxe, items: ['slots', 'energy', 'blocks', 'cooling'] },
  { num: '03', key: 'marketplace', color: '#22c55e', icon: Store, items: ['buySell', 'prices', 'noManipulation'] },
  { num: '04', key: 'pvp', color: '#a78bfa', icon: Swords, items: ['overview', 'deck', 'turns', 'cardTypes', 'shield', 'betting', 'winCondition'] },
  { num: '05', key: 'gambling', color: '#ef4444', icon: AlertTriangle, items: ['ageRequirement', 'responsible', 'cryptoRisk', 'noGuarantee'] },
  { num: '06', key: 'community', color: '#06b6d4', icon: Users, items: ['respect', 'noSpam', 'reportBugs', 'violations'] },
];
</script>

<template>
  <div class="rp-root">
    <!-- Header -->
    <div class="rp-header">
      <ScrollText :size="20" color="#4f4f6f" style="margin: 0 auto;" />
      <span class="rp-tag">// PROTOCOL</span>
      <h1 class="rp-title">{{ t('rules.title') }}</h1>
      <p class="rp-sub">{{ t('rules.subtitle') }}</p>
    </div>

    <!-- Sections -->
    <section v-for="s in sections" :key="s.key" class="rp-section">
      <div class="rp-sc rp-sc-tl" :style="{ borderColor: s.color }"></div>
      <div class="rp-sc rp-sc-tr" :style="{ borderColor: s.color }"></div>
      <div class="rp-sc rp-sc-bl" :style="{ borderColor: s.color }"></div>
      <div class="rp-sc rp-sc-br" :style="{ borderColor: s.color }"></div>
      <div class="rp-section-crt"></div>

      <div class="rp-section-header">
        <span class="rp-num" :style="{ color: s.color, textShadow: `0 0 10px ${s.color}40` }">{{ s.num }}</span>
        <component :is="s.icon" :size="18" :color="s.color" class="rp-section-icon" />
        <h2 class="rp-section-title">{{ t(`rules.${s.key}.title`) }}</h2>
      </div>

      <ul class="rp-list">
        <li v-for="item in s.items" :key="item" class="rp-item">
          <span class="rp-bullet" :style="{ background: s.color }"></span>
          <span class="rp-item-text">{{ t(`rules.${s.key}.${item}`) }}</span>
        </li>
      </ul>

      <div class="rp-section-bar">
        <div class="rp-section-bar-fill" :style="{ background: `linear-gradient(90deg, ${s.color}30, ${s.color})` }"></div>
        <div class="rp-section-bar-segs"></div>
      </div>
    </section>
  </div>
</template>

<style scoped>
.rp-root {
  max-width: 700px; margin: 0 auto;
  padding: 1.5rem 0.5rem 2rem;
  display: flex; flex-direction: column; gap: 1rem;
}

.rp-header { text-align: center; margin-bottom: 0.5rem; }
.rp-tag { font-size: 0.75rem; font-weight: 900; color: #4f4f6f; letter-spacing: 3px; }
.rp-title {
  font-size: 1.8rem; font-weight: 900; color: #f59e0b; letter-spacing: 2px;
  text-shadow: 0 0 15px rgba(245,158,11,0.2); margin: 0.3rem 0;
}
.rp-sub { font-size: 0.9rem; font-weight: 600; color: #71717a; }

.rp-section {
  position: relative; overflow: hidden;
  border: 1px solid #2f3052;
  background: linear-gradient(135deg, rgba(16,17,35,0.98) 0%, rgba(26,27,46,0.96) 100%);
  padding: 0.8rem;
}

.rp-sc { position: absolute; width: 8px; height: 8px; pointer-events: none; z-index: 2; }
.rp-sc-tl { top: 0; left: 0; border-top: 2px solid; border-left: 2px solid; }
.rp-sc-tr { top: 0; right: 0; border-top: 2px solid; border-right: 2px solid; }
.rp-sc-bl { bottom: 0; left: 0; border-bottom: 2px solid; border-left: 2px solid; }
.rp-sc-br { bottom: 0; right: 0; border-bottom: 2px solid; border-right: 2px solid; }

.rp-section-crt {
  position: absolute; inset: 0; pointer-events: none;
  background: repeating-linear-gradient(0deg, transparent, transparent 3px, rgba(255,255,255,0.005) 3px, rgba(255,255,255,0.005) 4px);
}

.rp-section-header {
  display: flex; align-items: center; gap: 0.5rem;
  margin-bottom: 0.6rem; position: relative; z-index: 1;
}
.rp-num {
  font-size: 1.4rem; font-weight: 900;
  font-family: 'JetBrains Mono', monospace;
  opacity: 0.8;
}
.rp-section-icon { flex-shrink: 0; opacity: 0.85; }
.rp-section-title {
  font-size: 1.05rem; font-weight: 900; color: #e5e7eb;
  letter-spacing: 1px; margin: 0;
}

.rp-list {
  list-style: none; margin: 0; padding: 0;
  display: flex; flex-direction: column; gap: 0.4rem;
  position: relative; z-index: 1;
}
.rp-item { display: flex; align-items: flex-start; gap: 0.5rem; }
.rp-bullet {
  width: 4px; height: 4px; flex-shrink: 0; margin-top: 0.35rem;
  clip-path: polygon(50% 0%, 100% 50%, 50% 100%, 0% 50%);
}
.rp-item-text { font-size: 0.9rem; font-weight: 600; color: #a1a1aa; line-height: 1.6; }

.rp-section-bar {
  height: 2px; position: relative; background: #1a1b2e; overflow: hidden;
  margin-top: 0.7rem; z-index: 1;
}
.rp-section-bar-fill { position: absolute; top: 0; left: 0; height: 100%; width: 100%; }
.rp-section-bar-segs {
  position: absolute; inset: 0; pointer-events: none;
  background: repeating-linear-gradient(90deg, transparent 0px, transparent 9%, rgba(16,17,35,0.8) 9%, rgba(16,17,35,0.8) 10%);
}
</style>
