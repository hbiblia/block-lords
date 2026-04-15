<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import { FileCheck, UserCheck, Coins, Gamepad2, Scale, FileText } from 'lucide-vue-next';

const { t } = useI18n();

const sections = [
  { num: '01', key: 'acceptance', color: '#c4a0e8', icon: FileCheck },
  { num: '02', key: 'eligibility', color: '#d4a017', icon: UserCheck },
  { num: '03', key: 'crypto', color: '#d4a017', icon: Coins },
  { num: '04', key: 'virtual', color: '#7cc490', icon: Gamepad2 },
  { num: '05', key: 'liability', color: '#b088d0', icon: Scale },
];
</script>

<template>
  <div class="tp-root">
    <div class="tp-header">
      <FileText :size="20" color="#9a80b8" style="margin: 0 auto;" />
      <span class="tp-tag">LEGAL_PROTOCOL</span>
      <h1 class="tp-title">{{ t('terms.title') }}</h1>
      <p class="tp-sub">{{ t('terms.subtitle') }}</p>
    </div>

    <section v-for="s in sections" :key="s.key" class="tp-section" :style="{ borderLeftColor: s.color }">
      <div class="tp-section-header">
        <span class="tp-num" :style="{ color: s.color }">{{ s.num }}</span>
        <component :is="s.icon" :size="18" :color="s.color" />
        <h2 class="tp-section-title">{{ t(`terms.${s.key}.title`) }}</h2>
      </div>
      <p class="tp-content">{{ t(`terms.${s.key}.content`) }}</p>
    </section>
  </div>
</template>

<style scoped>
@import url('https://fonts.googleapis.com/css2?family=Nunito:wght@400;600;700;800;900&display=swap');

.tp-root {
  max-width: 700px; margin: 0 auto;
  padding: 2rem 1rem;
  display: flex; flex-direction: column; gap: 1rem;
  font-family: 'Nunito', 'Trebuchet MS', sans-serif;
}

.tp-header { text-align: center; margin-bottom: 0.5rem; }
.tp-tag { font-size: 0.6rem; font-weight: 900; color: #8a70a8; letter-spacing: 3px; }
.tp-title { font-size: 1.6rem; font-weight: 900; color: #f0e4ff; margin: 0.3rem 0; }
.tp-sub { font-size: 0.85rem; font-weight: 600; color: #8a70a8; }

.tp-section {
  background: #1f1833; border: 2px solid #4a3660; border-radius: 12px;
  border-left: 4px solid #c4a0e8; padding: 1rem 1.2rem;
  box-shadow: 2px 2px 0 rgba(74,54,96,0.3);
}

.tp-section-header {
  display: flex; align-items: center; gap: 0.5rem; margin-bottom: 0.5rem;
}
.tp-num { font-size: 1.2rem; font-weight: 900; font-family: 'Nunito', sans-serif; opacity: 0.6; }
.tp-section-title { font-size: 1rem; font-weight: 900; color: #f0e4ff; margin: 0; }

.tp-content { font-size: 0.85rem; font-weight: 600; color: #b8a0d0; line-height: 1.7; margin: 0; }
</style>
