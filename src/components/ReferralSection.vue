<script setup lang="ts">
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAuthStore } from '@/stores/auth';
import { getReferralInfo, applyReferralCode, type ReferralInfo } from '@/utils/api';
import { playSound } from '@/utils/sounds';

const { t } = useI18n();
const authStore = useAuthStore();

const loading = ref(true);
const applying = ref(false);
const referralInfo = ref<ReferralInfo | null>(null);
const inputCode = ref('');
const error = ref('');
const success = ref('');
const copied = ref(false);

const referralLink = computed(() => {
  if (!referralInfo.value?.referralCode) return '';
  return `${window.location.origin}?ref=${referralInfo.value.referralCode}`;
});

const canApplyCode = computed(() => {
  return !referralInfo.value?.referredBy && inputCode.value.trim().length >= 6;
});

async function loadReferralInfo() {
  if (!authStore.player?.id) return;

  try {
    loading.value = true;
    referralInfo.value = await getReferralInfo(authStore.player.id);
  } catch (e) {
    console.error('Error loading referral info:', e);
  } finally {
    loading.value = false;
  }
}

async function handleApplyCode() {
  if (!authStore.player?.id || applying.value || !canApplyCode.value) return;

  error.value = '';
  success.value = '';
  applying.value = true;

  try {
    const result = await applyReferralCode(authStore.player.id, inputCode.value.trim());

    if (result.success) {
      playSound('success');
      success.value = t('referral.applySuccess', {
        username: result.referrerUsername,
        bonus: result.playerBonus
      });
      inputCode.value = '';
      await authStore.refreshPlayer();
      await loadReferralInfo();
    } else {
      playSound('error');
      const errorKey = `referral.errors.${result.error}`;
      error.value = t(errorKey) !== errorKey ? t(errorKey) : t('referral.errors.generic');
    }
  } catch (e: any) {
    console.error('Error applying referral code:', e);
    error.value = t('referral.errors.generic');
    playSound('error');
  } finally {
    applying.value = false;
  }
}

async function copyCode() {
  if (!referralInfo.value?.referralCode) return;

  try {
    await navigator.clipboard.writeText(referralInfo.value.referralCode);
    copied.value = true;
    playSound('click');
    setTimeout(() => { copied.value = false; }, 2000);
  } catch (e) {
    console.error('Error copying code:', e);
  }
}

async function copyLink() {
  if (!referralLink.value) return;

  try {
    await navigator.clipboard.writeText(referralLink.value);
    copied.value = true;
    playSound('click');
    setTimeout(() => { copied.value = false; }, 2000);
  } catch (e) {
    console.error('Error copying link:', e);
  }
}

async function shareLink() {
  if (!referralLink.value) return;

  if (navigator.share) {
    try {
      await navigator.share({
        title: 'Block Lords',
        text: t('referral.shareText'),
        url: referralLink.value,
      });
    } catch (e) {
      // User cancelled share
    }
  } else {
    copyLink();
  }
}

onMounted(() => {
  loadReferralInfo();
});
</script>

<template>
  <div class="card p-4">
    <!-- Header -->
    <div class="flex items-center justify-between mb-4">
      <div class="flex items-center gap-2">
        <span class="text-2xl">&#x1F465;</span>
        <div>
          <h3 class="font-bold text-lg">{{ t('referral.title') }}</h3>
          <p class="text-xs text-text-muted">{{ t('referral.subtitle') }}</p>
        </div>
      </div>

      <!-- Referral Count Badge -->
      <div class="px-3 py-1 rounded-full text-sm font-medium bg-accent-primary/20 text-accent-primary border border-accent-primary/30">
        {{ referralInfo?.referralCount ?? 0 }} {{ t('referral.invited') }}
      </div>
    </div>

    <!-- Loading State -->
    <div v-if="loading" class="flex justify-center py-8">
      <div class="animate-spin w-8 h-8 border-2 border-accent-primary border-t-transparent rounded-full"></div>
    </div>

    <template v-else-if="referralInfo">
      <!-- Your Referral Code -->
      <div class="bg-bg-tertiary rounded-xl p-4 mb-4">
        <p class="text-sm text-text-muted mb-2">{{ t('referral.yourCode') }}</p>
        <div class="flex items-center gap-2">
          <div class="flex-1 bg-bg-secondary rounded-lg px-4 py-3 font-mono text-xl font-bold tracking-wider text-center">
            {{ referralInfo.referralCode }}
          </div>
          <button
            @click="copyCode"
            class="p-3 rounded-lg bg-bg-secondary hover:bg-accent-primary/20 transition-colors"
            :title="t('common.copy')"
          >
            <svg v-if="!copied" class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z" />
            </svg>
            <svg v-else class="w-5 h-5 text-status-success" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
            </svg>
          </button>
        </div>
      </div>

      <!-- Share Buttons -->
      <div class="flex gap-2 mb-4">
        <button
          @click="copyLink"
          class="flex-1 flex items-center justify-center gap-2 py-2.5 rounded-lg bg-bg-tertiary hover:bg-bg-secondary transition-colors text-sm"
        >
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1" />
          </svg>
          {{ t('referral.copyLink') }}
        </button>
        <button
          @click="shareLink"
          class="flex-1 flex items-center justify-center gap-2 py-2.5 rounded-lg bg-accent-primary hover:bg-accent-primary/80 transition-colors text-sm text-white"
        >
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8.684 13.342C8.886 12.938 9 12.482 9 12c0-.482-.114-.938-.316-1.342m0 2.684a3 3 0 110-2.684m0 2.684l6.632 3.316m-6.632-6l6.632-3.316m0 0a3 3 0 105.367-2.684 3 3 0 00-5.367 2.684zm0 9.316a3 3 0 105.368 2.684 3 3 0 00-5.368-2.684z" />
          </svg>
          {{ t('referral.share') }}
        </button>
      </div>

      <!-- Rewards Info -->
      <div class="bg-status-success/10 border border-status-success/30 rounded-xl p-3 mb-4">
        <div class="flex items-start gap-2">
          <span class="text-lg">&#x1F381;</span>
          <div class="text-sm">
            <p class="font-medium text-status-success">{{ t('referral.rewards') }}</p>
            <p class="text-text-muted">{{ t('referral.rewardsDesc') }}</p>
          </div>
        </div>
      </div>

      <!-- Already Referred Info -->
      <div v-if="referralInfo.referredBy" class="bg-bg-tertiary rounded-xl p-3 mb-4">
        <div class="flex items-center gap-2 text-sm">
          <svg class="w-4 h-4 text-status-success" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
          </svg>
          <span class="text-text-muted">{{ t('referral.referredBy') }}:</span>
          <span class="font-medium">{{ referralInfo.referredBy }}</span>
        </div>
      </div>

      <!-- Apply Code Section (only if not referred) -->
      <div v-else class="border-t border-border/50 pt-4">
        <p class="text-sm text-text-muted mb-2">{{ t('referral.haveCode') }}</p>

        <!-- Success Message -->
        <div v-if="success" class="bg-status-success/10 border border-status-success/30 rounded-lg p-3 mb-3 text-sm text-status-success">
          {{ success }}
        </div>

        <!-- Error Message -->
        <div v-if="error" class="bg-status-danger/10 border border-status-danger/30 rounded-lg p-3 mb-3 text-sm text-status-danger">
          {{ error }}
        </div>

        <div class="flex gap-2">
          <input
            v-model="inputCode"
            type="text"
            :placeholder="t('referral.enterCode')"
            class="flex-1 bg-bg-tertiary rounded-lg px-4 py-2.5 text-sm uppercase tracking-wider focus:outline-none focus:ring-2 focus:ring-accent-primary/50"
            maxlength="10"
            @keyup.enter="handleApplyCode"
          />
          <button
            @click="handleApplyCode"
            :disabled="applying || !canApplyCode"
            :class="[
              'px-4 py-2.5 rounded-lg font-medium text-sm transition-all',
              canApplyCode
                ? 'bg-accent-primary text-white hover:bg-accent-primary/80'
                : 'bg-bg-tertiary text-text-muted cursor-not-allowed'
            ]"
          >
            <span v-if="applying" class="flex items-center gap-2">
              <span class="animate-spin w-4 h-4 border-2 border-white border-t-transparent rounded-full"></span>
            </span>
            <span v-else>{{ t('referral.apply') }}</span>
          </button>
        </div>
        <p class="text-xs text-text-muted mt-2">{{ t('referral.applyHint') }}</p>
      </div>

      <!-- Recent Referrals -->
      <div v-if="referralInfo.recentReferrals && referralInfo.recentReferrals.length > 0" class="border-t border-border/50 pt-4 mt-4">
        <p class="text-sm font-medium mb-2">{{ t('referral.recentReferrals') }}</p>
        <div class="space-y-2">
          <div
            v-for="(ref, index) in referralInfo.recentReferrals"
            :key="index"
            class="flex items-center justify-between bg-bg-tertiary rounded-lg px-3 py-2 text-sm"
          >
            <span class="font-medium">{{ ref.username }}</span>
            <span class="text-text-muted text-xs">
              {{ new Date(ref.joinedAt).toLocaleDateString() }}
            </span>
          </div>
        </div>
      </div>
    </template>
  </div>
</template>
