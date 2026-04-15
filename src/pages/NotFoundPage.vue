<script setup lang="ts">
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
</script>

<template>
  <div class="nf-page">
    <div class="nf-card">
      <div class="nf-icon">⬡</div>
      <h1 class="nf-code">404</h1>
      <p class="nf-msg">{{ t('notFound.message') }}</p>
      <RouterLink to="/" class="nf-btn">{{ t('notFound.backHome') }}</RouterLink>
    </div>
  </div>
</template>

<style scoped>
@import url('https://fonts.googleapis.com/css2?family=Nunito:wght@400;600;700;800;900&display=swap');

.nf-page {
  min-height: 100vh; display: flex; align-items: center; justify-content: center;
  background: #1a1528;
  background-image: radial-gradient(circle, #2d2545 1.5px, transparent 1.5px);
  background-size: 20px 20px;
  padding: 2rem;
  font-family: 'Nunito', 'Trebuchet MS', sans-serif;
}
.nf-card {
  background: #1f1833; border: 2px solid #4a3660; border-radius: 16px;
  box-shadow: 4px 4px 0 rgba(74,54,96,0.3); padding: 3rem 2rem;
  max-width: 400px; width: 100%; text-align: center;
}
.nf-icon { font-size: 3rem; color: #5c4578; margin-bottom: 0.5rem; }
.nf-code { font-size: 3rem; font-weight: 900; color: #c4a0e8; margin: 0 0 0.5rem; letter-spacing: 4px; }
.nf-msg { font-size: 0.9rem; color: #8a70a8; margin: 0 0 1.5rem; }
.nf-btn {
  display: inline-block; padding: 12px 30px;
  background: #ffe566; border: 2px outset #d4a017;
  color: #1a1528; font-size: 0.85rem; font-weight: 900;
  font-family: 'Nunito', sans-serif; letter-spacing: 1px;
  text-decoration: none; border-radius: 10px; transition: 0.2s;
}
.nf-btn:hover { background: #ffd700; border-style: inset; }
</style>
