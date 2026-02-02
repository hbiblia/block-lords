<script setup lang="ts">
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAuthStore } from '@/stores/auth';
import { getReferralInfo, applyReferralCode, updateReferralCode, getReferralList, type ReferralInfo, type ReferralListResponse } from '@/utils/api';
import { playSound } from '@/utils/sounds';
import { formatCrypto } from '@/utils/format';

const { t } = useI18n();
const authStore = useAuthStore();

const loading = ref(true);
const applying = ref(false);
const referralInfo = ref<ReferralInfo | null>(null);
const inputCode = ref('');
const error = ref('');
const success = ref('');
const copied = ref(false);

// Edit code state
const editingCode = ref(false);
const newCodeInput = ref('');
const updatingCode = ref(false);
const editError = ref('');
const showConfirmModal = ref(false);

// Referral list state
const referralList = ref<ReferralListResponse | null>(null);
const loadingList = ref(false);
const showReferralList = ref(false);
const listPage = ref(0);
const LIST_PAGE_SIZE = 20;

const CHANGE_COST = 500;
const cryptoBalance = computed(() => authStore.player?.crypto_balance ?? 0);
const canAffordChange = computed(() => cryptoBalance.value >= CHANGE_COST);

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

async function loadReferralList(reset = false) {
  if (!authStore.player?.id) return;

  try {
    loadingList.value = true;
    if (reset) {
      listPage.value = 0;
    }
    const offset = listPage.value * LIST_PAGE_SIZE;
    const result = await getReferralList(authStore.player.id, LIST_PAGE_SIZE, offset);

    if (reset || !referralList.value) {
      referralList.value = result;
    } else {
      // Append more referrals
      referralList.value = {
        ...result,
        referrals: [...referralList.value.referrals, ...result.referrals],
      };
    }
  } catch (e) {
    console.error('Error loading referral list:', e);
  } finally {
    loadingList.value = false;
  }
}

async function openReferralList() {
  showReferralList.value = true;
  if (!referralList.value) {
    await loadReferralList(true);
  }
}

function closeReferralList() {
  showReferralList.value = false;
}

async function loadMoreReferrals() {
  if (loadingList.value || !referralList.value?.pagination.hasMore) return;
  listPage.value++;
  await loadReferralList();
}

function formatTimeAgo(daysAgo: number): string {
  if (daysAgo === 0) return t('referral.list.today');
  if (daysAgo === 1) return t('referral.list.yesterday');
  if (daysAgo < 7) return t('referral.list.daysAgo', { days: daysAgo });
  if (daysAgo < 30) return t('referral.list.weeksAgo', { weeks: Math.floor(daysAgo / 7) });
  return t('referral.list.monthsAgo', { months: Math.floor(daysAgo / 30) });
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

function startEditCode() {
  newCodeInput.value = referralInfo.value?.referralCode ?? '';
  editError.value = '';
  editingCode.value = true;
}

function cancelEditCode() {
  editingCode.value = false;
  newCodeInput.value = '';
  editError.value = '';
}

function requestChangeCode() {
  editError.value = '';

  // Validate input
  const cleanCode = newCodeInput.value.trim().toUpperCase();
  if (cleanCode.length < 6 || cleanCode.length > 10) {
    editError.value = t('referral.edit.errors.invalid_length');
    return;
  }

  if (!/^[A-Z0-9]+$/.test(cleanCode)) {
    editError.value = t('referral.edit.errors.invalid_characters');
    return;
  }

  if (cleanCode === referralInfo.value?.referralCode) {
    editError.value = t('referral.edit.errors.same_code');
    return;
  }

  if (!canAffordChange.value) {
    editError.value = t('referral.edit.errors.insufficient_balance');
    return;
  }

  showConfirmModal.value = true;
}

function cancelConfirm() {
  showConfirmModal.value = false;
}

async function confirmChangeCode() {
  if (!authStore.player?.id || updatingCode.value) return;

  showConfirmModal.value = false;
  updatingCode.value = true;
  editError.value = '';

  try {
    const result = await updateReferralCode(authStore.player.id, newCodeInput.value.trim());

    if (result.success) {
      playSound('success');
      editingCode.value = false;
      newCodeInput.value = '';
      await authStore.refreshPlayer();
      await loadReferralInfo();
    } else {
      playSound('error');
      const errorKey = `referral.edit.errors.${result.error}`;
      editError.value = t(errorKey) !== errorKey ? t(errorKey) : t('referral.edit.errors.generic');
    }
  } catch (e: any) {
    console.error('Error updating referral code:', e);
    editError.value = t('referral.edit.errors.generic');
    playSound('error');
  } finally {
    updatingCode.value = false;
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

      <!-- Referral Count Badge (clickable) -->
      <button
        @click="openReferralList"
        class="px-3 py-1 rounded-full text-sm font-medium bg-accent-primary/20 text-accent-primary border border-accent-primary/30 hover:bg-accent-primary/30 transition-colors cursor-pointer flex items-center gap-1"
      >
        {{ referralInfo?.referralCount ?? 0 }} {{ t('referral.invited') }}
        <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
        </svg>
      </button>
    </div>

    <!-- Loading State -->
    <div v-if="loading" class="flex justify-center py-8">
      <div class="animate-spin w-8 h-8 border-2 border-accent-primary border-t-transparent rounded-full"></div>
    </div>

    <template v-else-if="referralInfo">
      <!-- Your Referral Code -->
      <div class="bg-bg-tertiary rounded-xl p-4 mb-4">
        <div class="flex items-center justify-between mb-2">
          <p class="text-sm text-text-muted">{{ t('referral.yourCode') }}</p>
          <button
            v-if="!editingCode"
            @click="startEditCode"
            class="text-xs text-accent-primary hover:text-accent-primary/80 transition-colors flex items-center gap-1"
          >
            <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15.232 5.232l3.536 3.536m-2.036-5.036a2.5 2.5 0 113.536 3.536L6.5 21.036H3v-3.572L16.732 3.732z" />
            </svg>
            {{ t('referral.edit.button') }}
          </button>
        </div>

        <!-- View mode -->
        <div v-if="!editingCode" class="flex items-center gap-2">
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

        <!-- Edit mode -->
        <div v-else class="space-y-3">
          <input
            v-model="newCodeInput"
            type="text"
            :placeholder="t('referral.edit.placeholder')"
            class="w-full bg-bg-secondary rounded-lg px-4 py-3 font-mono text-xl font-bold tracking-wider text-center uppercase focus:outline-none focus:ring-2 focus:ring-accent-primary/50"
            maxlength="10"
            :disabled="updatingCode"
          />
          <p class="text-xs text-text-muted text-center">{{ t('referral.edit.hint') }}</p>

          <!-- Cost info -->
          <div class="flex items-center justify-center gap-2 text-sm">
            <span class="text-text-muted">{{ t('referral.edit.cost') }}:</span>
            <span class="font-bold text-accent-primary">{{ CHANGE_COST }} 💎</span>
            <span :class="canAffordChange ? 'text-status-success' : 'text-status-danger'" class="text-xs">
              ({{ t('referral.edit.yourBalance') }}: {{ formatCrypto(cryptoBalance) }})
            </span>
          </div>

          <!-- Error -->
          <div v-if="editError" class="bg-status-danger/10 border border-status-danger/30 rounded-lg p-2 text-sm text-status-danger text-center">
            {{ editError }}
          </div>

          <!-- Buttons -->
          <div class="flex gap-2">
            <button
              @click="cancelEditCode"
              :disabled="updatingCode"
              class="flex-1 py-2 rounded-lg font-medium bg-bg-secondary hover:bg-bg-secondary/80 transition-colors text-sm"
            >
              {{ t('common.cancel') }}
            </button>
            <button
              @click="requestChangeCode"
              :disabled="updatingCode || !canAffordChange || newCodeInput.trim().length < 6"
              :class="[
                'flex-1 py-2 rounded-lg font-medium text-sm transition-colors',
                canAffordChange && newCodeInput.trim().length >= 6
                  ? 'bg-accent-primary text-white hover:bg-accent-primary/80'
                  : 'bg-bg-secondary text-text-muted cursor-not-allowed'
              ]"
            >
              <span v-if="updatingCode" class="flex items-center justify-center gap-2">
                <span class="animate-spin w-4 h-4 border-2 border-white border-t-transparent rounded-full"></span>
              </span>
              <span v-else>{{ t('referral.edit.change') }}</span>
            </button>
          </div>
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

    <!-- Confirmation Modal -->
    <Teleport to="body">
      <div
        v-if="showConfirmModal"
        class="fixed inset-0 z-50 flex items-center justify-center p-4"
      >
        <div class="absolute inset-0 bg-black/70 backdrop-blur-sm" @click="cancelConfirm"></div>

        <div class="relative bg-bg-secondary rounded-xl p-6 max-w-sm w-full border border-border animate-fade-in">
          <div class="text-center mb-4">
            <div class="text-4xl mb-3">&#x1F465;</div>
            <h3 class="text-lg font-bold mb-1">{{ t('referral.edit.confirmTitle') }}</h3>
            <p class="text-text-muted text-sm">{{ t('referral.edit.confirmDesc') }}</p>
          </div>

          <div class="bg-bg-primary rounded-lg p-4 mb-4">
            <div class="flex items-center justify-between mb-2">
              <span class="text-text-muted text-sm">{{ t('referral.edit.currentCode') }}</span>
              <span class="font-mono font-bold">{{ referralInfo?.referralCode }}</span>
            </div>
            <div class="flex items-center justify-between mb-3">
              <span class="text-text-muted text-sm">{{ t('referral.edit.newCode') }}</span>
              <span class="font-mono font-bold text-accent-primary">{{ newCodeInput.toUpperCase() }}</span>
            </div>
            <div class="border-t border-border/50 pt-3">
              <div class="flex items-center justify-between">
                <span class="text-text-muted text-sm">{{ t('referral.edit.cost') }}</span>
                <span class="font-bold text-accent-primary">{{ CHANGE_COST }} 💎</span>
              </div>
              <div class="flex items-center justify-between mt-1">
                <span class="text-text-muted text-sm">{{ t('referral.edit.yourBalance') }}</span>
                <span class="font-mono" :class="canAffordChange ? 'text-status-success' : 'text-status-danger'">
                  {{ formatCrypto(cryptoBalance) }} 💎
                </span>
              </div>
              <div class="flex items-center justify-between mt-1 pt-2 border-t border-border/50">
                <span class="text-text-muted text-sm">{{ t('referral.edit.after') }}</span>
                <span class="font-mono text-white">{{ formatCrypto(cryptoBalance - CHANGE_COST) }} 💎</span>
              </div>
            </div>
          </div>

          <div class="flex gap-3">
            <button
              @click="cancelConfirm"
              class="flex-1 py-2.5 rounded-lg font-medium bg-bg-tertiary hover:bg-bg-tertiary/80 transition-colors"
            >
              {{ t('common.cancel') }}
            </button>
            <button
              @click="confirmChangeCode"
              :disabled="updatingCode"
              class="flex-1 py-2.5 rounded-lg font-medium bg-accent-primary text-white hover:bg-accent-primary/80 transition-colors disabled:opacity-50"
            >
              {{ updatingCode ? '...' : t('common.confirm') }}
            </button>
          </div>
        </div>
      </div>
    </Teleport>

    <!-- Referral List Modal -->
    <Teleport to="body">
      <div
        v-if="showReferralList"
        class="fixed inset-0 z-50 flex items-center justify-center p-4"
      >
        <div class="absolute inset-0 bg-black/70 backdrop-blur-sm" @click="closeReferralList"></div>

        <div class="relative bg-bg-secondary rounded-xl max-w-lg w-full max-h-[80vh] flex flex-col border border-border animate-fade-in">
          <!-- Header -->
          <div class="p-4 border-b border-border/50 flex items-center justify-between">
            <div class="flex items-center gap-2">
              <span class="text-2xl">&#x1F465;</span>
              <div>
                <h3 class="font-bold text-lg">{{ t('referral.list.title') }}</h3>
                <p class="text-xs text-text-muted">{{ t('referral.list.subtitle') }}</p>
              </div>
            </div>
            <button
              @click="closeReferralList"
              class="p-2 rounded-lg hover:bg-bg-tertiary transition-colors"
            >
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>

          <!-- Stats Summary -->
          <div v-if="referralList?.stats" class="p-4 border-b border-border/50">
            <div class="grid grid-cols-2 gap-3">
              <div class="bg-bg-tertiary rounded-lg p-3 text-center">
                <p class="text-2xl font-bold text-accent-primary">{{ referralList.stats.totalReferrals }}</p>
                <p class="text-xs text-text-muted">{{ t('referral.list.totalReferrals') }}</p>
              </div>
              <div class="bg-bg-tertiary rounded-lg p-3 text-center">
                <p class="text-2xl font-bold text-status-success">{{ referralList.stats.activeReferrals }}</p>
                <p class="text-xs text-text-muted">{{ t('referral.list.activeReferrals') }}</p>
              </div>
              <div class="bg-bg-tertiary rounded-lg p-3 text-center">
                <p class="text-2xl font-bold text-yellow-400">{{ referralList.stats.totalBlocksByReferrals }}</p>
                <p class="text-xs text-text-muted">{{ t('referral.list.totalBlocks') }}</p>
              </div>
              <div class="bg-bg-tertiary rounded-lg p-3 text-center">
                <p class="text-2xl font-bold text-cyan-400">{{ formatCrypto(referralList.stats.totalCryptoByReferrals) }}</p>
                <p class="text-xs text-text-muted">{{ t('referral.list.totalCrypto') }}</p>
              </div>
            </div>
          </div>

          <!-- Loading State -->
          <div v-if="loadingList && !referralList" class="flex-1 flex justify-center items-center py-12">
            <div class="animate-spin w-8 h-8 border-2 border-accent-primary border-t-transparent rounded-full"></div>
          </div>

          <!-- Empty State -->
          <div v-else-if="referralList && referralList.referrals.length === 0" class="flex-1 flex flex-col justify-center items-center py-12 text-center">
            <span class="text-4xl mb-3">&#x1F64D;</span>
            <p class="text-text-muted">{{ t('referral.list.empty') }}</p>
            <p class="text-sm text-text-muted mt-1">{{ t('referral.list.emptyHint') }}</p>
          </div>

          <!-- Referral List -->
          <div v-else-if="referralList" class="flex-1 overflow-y-auto p-4 space-y-2">
            <div
              v-for="ref in referralList.referrals"
              :key="ref.id"
              class="bg-bg-tertiary rounded-lg p-3"
            >
              <div class="flex items-center justify-between mb-2">
                <div class="flex items-center gap-2">
                  <!-- Online indicator -->
                  <span
                    :class="[
                      'w-2 h-2 rounded-full',
                      ref.isOnline ? 'bg-status-success animate-pulse' : 'bg-text-muted'
                    ]"
                  ></span>
                  <span class="font-medium">{{ ref.username }}</span>
                  <span
                    v-if="ref.isActive"
                    class="px-1.5 py-0.5 text-[10px] font-medium rounded bg-status-success/20 text-status-success"
                  >
                    {{ t('referral.list.active') }}
                  </span>
                </div>
                <span class="text-xs text-text-muted">{{ formatTimeAgo(ref.daysAgo) }}</span>
              </div>

              <div class="grid grid-cols-3 gap-2 text-xs">
                <div class="flex flex-col items-center bg-bg-secondary rounded p-1.5">
                  <span class="text-yellow-400 font-bold">{{ ref.blocksMined }}</span>
                  <span class="text-text-muted">{{ t('referral.list.blocks') }}</span>
                </div>
                <div class="flex flex-col items-center bg-bg-secondary rounded p-1.5">
                  <span class="text-cyan-400 font-bold">{{ formatCrypto(ref.cryptoEarned) }}</span>
                  <span class="text-text-muted">{{ t('referral.list.crypto') }}</span>
                </div>
                <div class="flex flex-col items-center bg-bg-secondary rounded p-1.5">
                  <span class="text-accent-primary font-bold">{{ ref.activeRigs }}</span>
                  <span class="text-text-muted">{{ t('referral.list.rigs') }}</span>
                </div>
              </div>
            </div>

            <!-- Load More Button -->
            <button
              v-if="referralList.pagination.hasMore"
              @click="loadMoreReferrals"
              :disabled="loadingList"
              class="w-full py-2.5 rounded-lg bg-bg-tertiary hover:bg-bg-tertiary/80 transition-colors text-sm font-medium"
            >
              <span v-if="loadingList" class="flex items-center justify-center gap-2">
                <span class="animate-spin w-4 h-4 border-2 border-accent-primary border-t-transparent rounded-full"></span>
                {{ t('common.loading') }}
              </span>
              <span v-else>{{ t('referral.list.loadMore') }}</span>
            </button>
          </div>
        </div>
      </div>
    </Teleport>
  </div>
</template>
