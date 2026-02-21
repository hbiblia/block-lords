<script setup lang="ts">
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
</script>

<template>
  <div class="pt-6 pb-4 max-w-3xl mx-auto">
    <div class="text-center mb-8">
      <h1 class="font-display text-3xl md:text-4xl font-bold mb-3">
        <span class="gradient-text">{{ t('terms.title') }}</span>
      </h1>
      <p class="text-text-secondary text-sm">{{ t('terms.subtitle') }}</p>
    </div>

    <!-- Acceptance -->
    <section class="card p-5 mb-4">
      <h2 class="text-lg font-semibold text-white mb-3 flex items-center gap-2">
        <span class="w-8 h-8 rounded-lg bg-gradient-primary flex items-center justify-center text-sm">1</span>
        {{ t('terms.acceptance.title') }}
      </h2>
      <p class="text-sm text-text-secondary leading-relaxed">{{ t('terms.acceptance.content') }}</p>
    </section>

    <!-- Eligibility -->
    <section class="card p-5 mb-4">
      <h2 class="text-lg font-semibold text-white mb-3 flex items-center gap-2">
        <span class="w-8 h-8 rounded-lg bg-gradient-primary flex items-center justify-center text-sm">2</span>
        {{ t('terms.eligibility.title') }}
      </h2>
      <p class="text-sm text-text-secondary leading-relaxed">{{ t('terms.eligibility.content') }}</p>
    </section>

    <!-- Wagering & Betting -->
    <section class="card p-5 mb-4 border-amber-500/20">
      <h2 class="text-lg font-semibold text-white mb-3 flex items-center gap-2">
        <span class="w-8 h-8 rounded-lg bg-gradient-to-br from-amber-500 to-orange-500 flex items-center justify-center text-sm">3</span>
        {{ t('terms.gambling.title') }}
      </h2>
      <p class="text-sm text-text-secondary leading-relaxed">{{ t('terms.gambling.content') }}</p>
    </section>

    <!-- Cryptocurrency Risks -->
    <section class="card p-5 mb-4">
      <h2 class="text-lg font-semibold text-white mb-3 flex items-center gap-2">
        <span class="w-8 h-8 rounded-lg bg-gradient-primary flex items-center justify-center text-sm">4</span>
        {{ t('terms.crypto.title') }}
      </h2>
      <p class="text-sm text-text-secondary leading-relaxed">{{ t('terms.crypto.content') }}</p>
    </section>

    <!-- Virtual Assets -->
    <section class="card p-5 mb-4">
      <h2 class="text-lg font-semibold text-white mb-3 flex items-center gap-2">
        <span class="w-8 h-8 rounded-lg bg-gradient-primary flex items-center justify-center text-sm">5</span>
        {{ t('terms.virtual.title') }}
      </h2>
      <p class="text-sm text-text-secondary leading-relaxed">{{ t('terms.virtual.content') }}</p>
    </section>

    <!-- Limitation of Liability -->
    <section class="card p-5 mb-4">
      <h2 class="text-lg font-semibold text-white mb-3 flex items-center gap-2">
        <span class="w-8 h-8 rounded-lg bg-gradient-primary flex items-center justify-center text-sm">6</span>
        {{ t('terms.liability.title') }}
      </h2>
      <p class="text-sm text-text-secondary leading-relaxed">{{ t('terms.liability.content') }}</p>
    </section>
  </div>
</template>
