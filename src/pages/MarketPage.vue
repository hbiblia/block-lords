<script setup lang="ts">
import { ref } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import MarketModal from '@/components/MarketModal.vue';

const { t } = useI18n();
const router = useRouter();
const showMarket = ref(true);

function handleClose() {
  router.push('/mining');
}

function handlePurchased() {
  // Opcional: recargar datos si es necesario
}
</script>

<template>
  <div class="flex items-center justify-center min-h-[60vh]">
    <div class="text-center">
      <div class="text-6xl mb-4">🛒</div>
      <h1 class="text-2xl font-display font-bold mb-2">
        <span class="gradient-text">{{ t('market.title') }}</span>
      </h1>
      <p class="text-text-muted mb-4">
        {{ t('market.subtitle') }}
      </p>
    </div>

    <!-- Market Modal (se abre automáticamente) -->
    <MarketModal
      :show="showMarket"
      @close="handleClose"
      @purchased="handlePurchased"
    />
  </div>
</template>
