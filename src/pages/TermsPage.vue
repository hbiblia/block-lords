<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import { FileCheck, UserCheck, AlertTriangle, Coins, Gamepad2, Scale, FileText } from 'lucide-vue-next';

const { t } = useI18n();

const sections = [
  { num: '01', key: 'acceptance', color: '#f59e0b', icon: FileCheck },
  { num: '02', key: 'eligibility', color: '#06b6d4', icon: UserCheck },
  { num: '03', key: 'gambling', color: '#ef4444', icon: AlertTriangle },
  { num: '04', key: 'crypto', color: '#f59e0b', icon: Coins },
  { num: '05', key: 'virtual', color: '#22c55e', icon: Gamepad2 },
  { num: '06', key: 'liability', color: '#a78bfa', icon: Scale },
];
</script>

<template>
  <div class="tp-root">
    <!-- Header -->
    <div class="tp-header">
      <FileText :size="20" color="#4f4f6f" style="margin: 0 auto;" />
      <span class="tp-tag">// LEGAL_PROTOCOL</span>
      <h1 class="tp-title">{{ t('terms.title') }}</h1>
      <p class="tp-sub">{{ t('terms.subtitle') }}</p>
    </div>

    <!-- Sections -->
    <section v-for="s in sections" :key="s.key" class="tp-section">
      <div class="tp-sc tp-sc-tl" :style="{ borderColor: s.color }"></div>
      <div class="tp-sc tp-sc-tr" :style="{ borderColor: s.color }"></div>
      <div class="tp-sc tp-sc-bl" :style="{ borderColor: s.color }"></div>
      <div class="tp-sc tp-sc-br" :style="{ borderColor: s.color }"></div>
      <div class="tp-section-crt"></div>

      <div class="tp-section-header">
        <span class="tp-num" :style="{ color: s.color, textShadow: `0 0 10px ${s.color}40` }">{{ s.num }}</span>
        <component :is="s.icon" :size="18" :color="s.color" class="tp-section-icon" />
        <h2 class="tp-section-title">{{ t(`terms.${s.key}.title`) }}</h2>
      </div>

      <p class="tp-content">{{ t(`terms.${s.key}.content`) }}</p>

      <div class="tp-section-bar">
        <div class="tp-section-bar-fill" :style="{ background: `linear-gradient(90deg, ${s.color}30, ${s.color})` }"></div>
        <div class="tp-section-bar-segs"></div>
      </div>
    </section>
  </div>
</template>

<style scoped>
.tp-root {
  max-width: 700px; margin: 0 auto;
  padding: 1.5rem 0.5rem 2rem;
  display: flex; flex-direction: column; gap: 1rem;
}

.tp-header { text-align: center; margin-bottom: 0.5rem; }
.tp-tag { font-size: 0.75rem; font-weight: 900; color: #4f4f6f; letter-spacing: 3px; }
.tp-title {
  font-size: 1.8rem; font-weight: 900; color: #f59e0b; letter-spacing: 2px;
  text-shadow: 0 0 15px rgba(245,158,11,0.2); margin: 0.3rem 0;
}
.tp-sub { font-size: 0.9rem; font-weight: 600; color: #71717a; }

.tp-section {
  position: relative; overflow: hidden;
  border: 1px solid #2f3052;
  background: linear-gradient(135deg, rgba(16,17,35,0.98) 0%, rgba(26,27,46,0.96) 100%);
  padding: 0.8rem;
}

.tp-sc { position: absolute; width: 8px; height: 8px; pointer-events: none; z-index: 2; }
.tp-sc-tl { top: 0; left: 0; border-top: 2px solid; border-left: 2px solid; }
.tp-sc-tr { top: 0; right: 0; border-top: 2px solid; border-right: 2px solid; }
.tp-sc-bl { bottom: 0; left: 0; border-bottom: 2px solid; border-left: 2px solid; }
.tp-sc-br { bottom: 0; right: 0; border-bottom: 2px solid; border-right: 2px solid; }

.tp-section-crt {
  position: absolute; inset: 0; pointer-events: none;
  background: repeating-linear-gradient(0deg, transparent, transparent 3px, rgba(255,255,255,0.005) 3px, rgba(255,255,255,0.005) 4px);
}

.tp-section-header {
  display: flex; align-items: center; gap: 0.5rem;
  margin-bottom: 0.5rem; position: relative; z-index: 1;
}
.tp-num {
  font-size: 1.4rem; font-weight: 900;
  font-family: 'JetBrains Mono', monospace;
  opacity: 0.8;
}
.tp-section-icon { flex-shrink: 0; opacity: 0.85; }
.tp-section-title {
  font-size: 1.05rem; font-weight: 900; color: #e5e7eb;
  letter-spacing: 1px; margin: 0;
}

.tp-content {
  font-size: 0.9rem; font-weight: 600; color: #a1a1aa;
  line-height: 1.7; margin: 0;
  position: relative; z-index: 1;
}

.tp-section-bar {
  height: 2px; position: relative; background: #1a1b2e; overflow: hidden;
  margin-top: 0.7rem; z-index: 1;
}
.tp-section-bar-fill { position: absolute; top: 0; left: 0; height: 100%; width: 100%; }
.tp-section-bar-segs {
  position: absolute; inset: 0; pointer-events: none;
  background: repeating-linear-gradient(90deg, transparent 0px, transparent 9%, rgba(16,17,35,0.8) 9%, rgba(16,17,35,0.8) 10%);
}
</style>
