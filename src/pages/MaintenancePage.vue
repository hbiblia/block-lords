<script setup lang="ts">
import { Hammer, Pickaxe } from 'lucide-vue-next';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
</script>

<template>
  <div class="maintenance-container">
    <div class="maintenance-card">
      <div class="icon-wrapper">
        <div class="hammer-animation">
          <Hammer :size="48" class="hammer-icon" />
        </div>
        <div class="sparkle-stars">
          <Pickaxe :size="24" class="pickaxe-icon" />
        </div>
      </div>
      
      <h1 class="title">{{ t('maintenance.title') }}</h1>
      
      <p class="description">
        {{ t('maintenance.description') }}
      </p>

      <div class="status-badge">
        <div class="pulse-dot"></div>
        <span>{{ t('maintenance.status') }}</span>
      </div>

      <div class="stats-grid">
        <div class="stat-item">
          <span class="stat-label">{{ t('maintenance.stateLabel') }}</span>
          <span class="stat-value">{{ t('maintenance.stateValue') }}</span>
        </div>
        <div class="stat-item">
          <span class="stat-label">{{ t('maintenance.timeLabel') }}</span>
          <span class="stat-value">{{ t('maintenance.timeValue') }}</span>
        </div>
      </div>

      <div class="social-links">
        <a
          href="https://discord.gg/dJKQDfxE"
          target="_blank"
          rel="noopener noreferrer"
          class="social-button"
        >
          <svg class="discord-icon" viewBox="0 0 24 24" fill="currentColor">
            <path d="M20.317 4.37a19.791 19.791 0 0 0-4.885-1.515.074.074 0 0 0-.079.037c-.21.375-.444.864-.608 1.25a18.27 18.27 0 0 0-5.487 0 12.64 12.64 0 0 0-.617-1.25.077.077 0 0 0-.079-.037A19.736 19.736 0 0 0 3.677 4.37a.07.07 0 0 0-.032.027C.533 9.046-.32 13.58.099 18.057a.082.082 0 0 0 .031.057 19.9 19.9 0 0 0 5.993 3.03.078.078 0 0 0 .084-.028c.462-.63.874-1.295 1.226-1.994a.076.076 0 0 0-.041-.106 13.107 13.107 0 0 1-1.872-.892.077.077 0 0 1-.008-.128 10.2 10.2 0 0 0 .372-.292.074.074 0 0 1 .077-.01c3.928 1.793 8.18 1.793 12.062 0a.074.074 0 0 1 .078.01c.12.098.246.198.373.292a.077.077 0 0 1-.006.127 12.299 12.299 0 0 1-1.873.892.077.077 0 0 0-.041.107c.36.698.772 1.362 1.225 1.993a.076.076 0 0 0 .084.028 19.839 19.839 0 0 0 6.002-3.03.077.077 0 0 0 .032-.054c.5-5.177-.838-9.674-3.549-13.66a.061.061 0 0 0-.031-.03z"/>
          </svg>
          <span>{{ t('maintenance.contact') }}</span>
        </a>
      </div>
    </div>
  </div>
</template>

<style scoped>
.maintenance-container {
  min-height: calc(100vh - 120px);
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 1rem;
  background-color: #1a1528;
  background-image: radial-gradient(rgba(255, 255, 255, 0.05) 1px, transparent 1px);
  background-size: 20px 20px;
}

.maintenance-card {
  width: 100%;
  max-width: 450px;
  background: rgba(31, 24, 51, 0.8);
  backdrop-filter: blur(10px);
  border: 2px solid rgba(74, 54, 96, 0.5);
  border-radius: 24px;
  padding: 3rem 2rem;
  text-align: center;
  box-shadow: 
    0 20px 50px rgba(0, 0, 0, 0.5), 
    inset 0 1px 1px rgba(255, 255, 255, 0.05),
    0 0 20px rgba(196, 160, 232, 0.05);
  position: relative;
  overflow: hidden;
}

.icon-wrapper {
  position: relative;
  width: 100px;
  height: 100px;
  margin: 0 auto 2rem;
  display: flex;
  align-items: center;
  justify-content: center;
  background: rgba(196, 160, 232, 0.1);
  border-radius: 50%;
}

.hammer-animation {
  animation: hammer-swing 2s ease-in-out infinite;
  color: #c4a0e8;
}

.pickaxe-icon {
  position: absolute;
  top: -5px;
  right: -5px;
  color: #f59e0b;
  animation: float 3s ease-in-out infinite;
}

.title {
  font-size: 2rem;
  font-weight: 800;
  color: #fff;
  margin-bottom: 1rem;
  font-family: 'Nunito', sans-serif;
  letter-spacing: -0.02em;
}

.description {
  color: #a0a0c0;
  line-height: 1.6;
  margin-bottom: 2rem;
  font-size: 1.05rem;
}

.status-badge {
  display: inline-flex;
  align-items: center;
  gap: 0.75rem;
  padding: 0.5rem 1.25rem;
  background: rgba(16, 185, 129, 0.1);
  border: 1px solid rgba(16, 185, 129, 0.2);
  border-radius: 100px;
  color: #34d399;
  font-weight: 700;
  font-size: 0.85rem;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  margin-bottom: 2.5rem;
}

.pulse-dot {
  width: 8px;
  height: 8px;
  background-color: #10b981;
  border-radius: 50%;
  position: relative;
}

.pulse-dot::after {
  content: '';
  position: absolute;
  top: 0;
  left: 0;
  width: 100%;
  height: 100%;
  background-color: inherit;
  border-radius: 50%;
  animation: pulse 2s cubic-bezier(0.4, 0, 0.6, 1) infinite;
}

.stats-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 1.5rem;
  margin-bottom: 2.5rem;
  padding: 1.5rem;
  background: rgba(0, 0, 0, 0.2);
  border-radius: 16px;
}

.stat-item {
  display: flex;
  flex-direction: column;
  gap: 0.25rem;
}

.stat-label {
  font-size: 0.75rem;
  color: #6a6a8a;
  text-transform: uppercase;
  font-weight: 700;
}

.stat-value {
  font-size: 1.1rem;
  color: #fff;
  font-weight: 800;
}

.social-button {
  display: inline-flex;
  align-items: center;
  gap: 0.75rem;
  padding: 0.85rem 2rem;
  background: #5865F2; /* Discord Purple */
  color: white;
  border-radius: 14px;
  text-decoration: none;
  font-weight: 700;
  transition: all 0.2s;
}

.social-button:hover {
  transform: translateY(-2px);
  box-shadow: 0 8px 20px rgba(88, 101, 242, 0.4);
}

.discord-icon {
  width: 20px;
  height: 20px;
}

@keyframes hammer-swing {
  0%, 100% { transform: rotate(-15deg); }
  50% { transform: rotate(15deg); }
}

@keyframes float {
  0%, 100% { transform: translateY(0); }
  50% { transform: translateY(-10px); }
}

@keyframes pulse {
  0% { transform: scale(1); opacity: 0.8; }
  100% { transform: scale(3); opacity: 0; }
}
</style>
