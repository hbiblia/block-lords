<script setup lang="ts">
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
</script>

<template>
  <div class="text-center py-20">
    <div class="text-8xl mb-6">💀</div>
    <h1 class="font-arcade text-3xl text-arcade-danger mb-4">404</h1>
    <p class="text-xl text-gray-400 mb-8">{{ t('notFound.message') }}</p>
    <RouterLink to="/" class="arcade-button">
      {{ t('notFound.backHome') }}
    </RouterLink>
  </div>
</template>
