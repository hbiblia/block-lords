<script setup lang="ts">
import { ref } from 'vue';
import { useRouter } from 'vue-router';
import MarketModal from '@/components/MarketModal.vue';

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
        <span class="gradient-text">Mercado</span>
      </h1>
      <p class="text-text-muted mb-4">
        Compra rigs, refrigeración y tarjetas prepago
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
