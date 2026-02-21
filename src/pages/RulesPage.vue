<script setup lang="ts">
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
</script>

<template>
  <div class="pt-6 pb-4 max-w-3xl mx-auto">
    <div class="text-center mb-8">
      <h1 class="font-display text-3xl md:text-4xl font-bold mb-3">
        <span class="gradient-text">{{ t('rules.title') }}</span>
      </h1>
      <p class="text-text-secondary text-sm">{{ t('rules.subtitle') }}</p>
    </div>

    <!-- General Rules -->
    <section class="card p-5 mb-4">
      <h2 class="text-lg font-semibold text-white mb-3 flex items-center gap-2">
        <span class="w-8 h-8 rounded-lg bg-gradient-primary flex items-center justify-center text-sm">1</span>
        {{ t('rules.general.title') }}
      </h2>
      <ul class="space-y-2 text-sm text-text-secondary">
        <li class="flex items-start gap-2">
          <span class="text-accent-primary mt-0.5">&#8226;</span>
          {{ t('rules.general.oneAccount') }}
        </li>
        <li class="flex items-start gap-2">
          <span class="text-accent-primary mt-0.5">&#8226;</span>
          {{ t('rules.general.fairPlay') }}
        </li>
        <li class="flex items-start gap-2">
          <span class="text-accent-primary mt-0.5">&#8226;</span>
          {{ t('rules.general.noExploits') }}
        </li>
        <li class="flex items-start gap-2">
          <span class="text-accent-primary mt-0.5">&#8226;</span>
          {{ t('rules.general.simulation') }}
        </li>
      </ul>
    </section>

    <!-- Mining -->
    <section class="card p-5 mb-4">
      <h2 class="text-lg font-semibold text-white mb-3 flex items-center gap-2">
        <span class="w-8 h-8 rounded-lg bg-gradient-primary flex items-center justify-center text-sm">2</span>
        {{ t('rules.mining.title') }}
      </h2>
      <ul class="space-y-2 text-sm text-text-secondary">
        <li class="flex items-start gap-2">
          <span class="text-accent-primary mt-0.5">&#8226;</span>
          {{ t('rules.mining.slots') }}
        </li>
        <li class="flex items-start gap-2">
          <span class="text-accent-primary mt-0.5">&#8226;</span>
          {{ t('rules.mining.energy') }}
        </li>
        <li class="flex items-start gap-2">
          <span class="text-accent-primary mt-0.5">&#8226;</span>
          {{ t('rules.mining.blocks') }}
        </li>
        <li class="flex items-start gap-2">
          <span class="text-accent-primary mt-0.5">&#8226;</span>
          {{ t('rules.mining.cooling') }}
        </li>
      </ul>
    </section>

    <!-- Marketplace -->
    <section class="card p-5 mb-4">
      <h2 class="text-lg font-semibold text-white mb-3 flex items-center gap-2">
        <span class="w-8 h-8 rounded-lg bg-gradient-primary flex items-center justify-center text-sm">3</span>
        {{ t('rules.marketplace.title') }}
      </h2>
      <ul class="space-y-2 text-sm text-text-secondary">
        <li class="flex items-start gap-2">
          <span class="text-accent-primary mt-0.5">&#8226;</span>
          {{ t('rules.marketplace.buySell') }}
        </li>
        <li class="flex items-start gap-2">
          <span class="text-accent-primary mt-0.5">&#8226;</span>
          {{ t('rules.marketplace.prices') }}
        </li>
        <li class="flex items-start gap-2">
          <span class="text-accent-primary mt-0.5">&#8226;</span>
          {{ t('rules.marketplace.noManipulation') }}
        </li>
      </ul>
    </section>

    <!-- Card Battles -->
    <section class="card p-5 mb-4">
      <h2 class="text-lg font-semibold text-white mb-3 flex items-center gap-2">
        <span class="w-8 h-8 rounded-lg bg-gradient-primary flex items-center justify-center text-sm">4</span>
        {{ t('rules.pvp.title') }}
      </h2>
      <ul class="space-y-2 text-sm text-text-secondary">
        <li class="flex items-start gap-2">
          <span class="text-accent-primary mt-0.5">&#8226;</span>
          {{ t('rules.pvp.overview') }}
        </li>
        <li class="flex items-start gap-2">
          <span class="text-accent-primary mt-0.5">&#8226;</span>
          {{ t('rules.pvp.deck') }}
        </li>
        <li class="flex items-start gap-2">
          <span class="text-accent-primary mt-0.5">&#8226;</span>
          {{ t('rules.pvp.turns') }}
        </li>
        <li class="flex items-start gap-2">
          <span class="text-accent-primary mt-0.5">&#8226;</span>
          {{ t('rules.pvp.cardTypes') }}
        </li>
        <li class="flex items-start gap-2">
          <span class="text-accent-primary mt-0.5">&#8226;</span>
          {{ t('rules.pvp.shield') }}
        </li>
        <li class="flex items-start gap-2">
          <span class="text-accent-primary mt-0.5">&#8226;</span>
          {{ t('rules.pvp.betting') }}
        </li>
        <li class="flex items-start gap-2">
          <span class="text-accent-primary mt-0.5">&#8226;</span>
          {{ t('rules.pvp.winCondition') }}
        </li>
      </ul>
    </section>

    <!-- Wagering & Responsible Play -->
    <section class="card p-5 mb-4 border-amber-500/20">
      <h2 class="text-lg font-semibold text-white mb-3 flex items-center gap-2">
        <span class="w-8 h-8 rounded-lg bg-gradient-to-br from-amber-500 to-orange-500 flex items-center justify-center text-sm">5</span>
        {{ t('rules.gambling.title') }}
      </h2>
      <ul class="space-y-2 text-sm text-text-secondary">
        <li class="flex items-start gap-2">
          <span class="text-amber-400 mt-0.5">&#8226;</span>
          {{ t('rules.gambling.ageRequirement') }}
        </li>
        <li class="flex items-start gap-2">
          <span class="text-amber-400 mt-0.5">&#8226;</span>
          {{ t('rules.gambling.responsible') }}
        </li>
        <li class="flex items-start gap-2">
          <span class="text-amber-400 mt-0.5">&#8226;</span>
          {{ t('rules.gambling.cryptoRisk') }}
        </li>
        <li class="flex items-start gap-2">
          <span class="text-amber-400 mt-0.5">&#8226;</span>
          {{ t('rules.gambling.noGuarantee') }}
        </li>
      </ul>
    </section>

    <!-- Community -->
    <section class="card p-5 mb-4">
      <h2 class="text-lg font-semibold text-white mb-3 flex items-center gap-2">
        <span class="w-8 h-8 rounded-lg bg-gradient-primary flex items-center justify-center text-sm">6</span>
        {{ t('rules.community.title') }}
      </h2>
      <ul class="space-y-2 text-sm text-text-secondary">
        <li class="flex items-start gap-2">
          <span class="text-accent-primary mt-0.5">&#8226;</span>
          {{ t('rules.community.respect') }}
        </li>
        <li class="flex items-start gap-2">
          <span class="text-accent-primary mt-0.5">&#8226;</span>
          {{ t('rules.community.noSpam') }}
        </li>
        <li class="flex items-start gap-2">
          <span class="text-accent-primary mt-0.5">&#8226;</span>
          {{ t('rules.community.reportBugs') }}
        </li>
        <li class="flex items-start gap-2">
          <span class="text-accent-primary mt-0.5">&#8226;</span>
          {{ t('rules.community.violations') }}
        </li>
      </ul>
    </section>
  </div>
</template>
