<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import { Shield, Pickaxe, Store, Swords, AlertTriangle, Users, ScrollText } from 'lucide-vue-next';

const { t } = useI18n();

const sections = [
  { num: '01', key: 'general', color: '#c4a0e8', icon: Shield, items: ['oneAccount', 'fairPlay', 'noExploits', 'simulation'] },
  { num: '02', key: 'mining', color: '#d4a017', icon: Pickaxe, items: ['slots', 'energy', 'blocks', 'cooling'] },
  { num: '03', key: 'marketplace', color: '#7cc490', icon: Store, items: ['buySell', 'prices', 'noManipulation'] },
  { num: '04', key: 'gambling', color: '#cc4444', icon: AlertTriangle, items: ['ageRequirement', 'responsible', 'cryptoRisk', 'noGuarantee'] },
  { num: '05', key: 'community', color: '#7b5ea7', icon: Users, items: ['respect', 'noSpam', 'reportBugs', 'violations'] },
];
</script>

<template>
  <div class="rp-root">
    <div class="rp-header">
      <ScrollText :size="20" color="#9a80b8" style="margin: 0 auto;" />
      <span class="rp-tag">PROTOCOL</span>
      <h1 class="rp-title">{{ t('rules.title') }}</h1>
      <p class="rp-sub">{{ t('rules.subtitle') }}</p>
    </div>

    <section v-for="s in sections" :key="s.key" class="rp-section" :style="{ borderLeftColor: s.color }">
      <div class="rp-section-header">
        <span class="rp-num" :style="{ color: s.color }">{{ s.num }}</span>
        <component :is="s.icon" :size="18" :color="s.color" />
        <h2 class="rp-section-title">{{ t(`rules.${s.key}.title`) }}</h2>
      </div>
      <ul class="rp-list">
        <li v-for="item in s.items" :key="item" class="rp-item">
          <span class="rp-bullet" :style="{ background: s.color }"></span>
          <span class="rp-item-text">{{ t(`rules.${s.key}.${item}`) }}</span>
        </li>
      </ul>
    </section>
  </div>
</template>

<style scoped>
@import url('https://fonts.googleapis.com/css2?family=Nunito:wght@400;600;700;800;900&display=swap');

.rp-root {
  max-width: 700px; margin: 0 auto;
  padding: 2rem 1rem;
  display: flex; flex-direction: column; gap: 1rem;
  font-family: 'Nunito', 'Trebuchet MS', sans-serif;
}

.rp-header { text-align: center; margin-bottom: 0.5rem; }
.rp-tag { font-size: 0.6rem; font-weight: 900; color: #9a80b8; letter-spacing: 3px; }
.rp-title { font-size: 1.6rem; font-weight: 900; color: #4a3a5c; margin: 0.3rem 0; }
.rp-sub { font-size: 0.85rem; font-weight: 600; color: #9a80b8; }

.rp-section {
  background: #fff; border: 2px solid #d0b8e8; border-radius: 12px;
  border-left: 4px solid #c4a0e8; padding: 1rem 1.2rem;
  box-shadow: 2px 2px 0 #e8d0f0;
}

.rp-section-header {
  display: flex; align-items: center; gap: 0.5rem; margin-bottom: 0.6rem;
}
.rp-num { font-size: 1.2rem; font-weight: 900; font-family: 'Nunito', sans-serif; opacity: 0.6; }
.rp-section-title { font-size: 1rem; font-weight: 900; color: #4a3a5c; margin: 0; }

.rp-list { list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; gap: 0.4rem; }
.rp-item { display: flex; align-items: flex-start; gap: 0.5rem; }
.rp-bullet { width: 6px; height: 6px; flex-shrink: 0; margin-top: 0.4rem; border-radius: 50%; }
.rp-item-text { font-size: 0.85rem; font-weight: 600; color: #7b5ea7; line-height: 1.6; }
</style>
