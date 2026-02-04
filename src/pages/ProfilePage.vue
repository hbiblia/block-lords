<script setup lang="ts">
import { ref, onUnmounted, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAuthStore } from '@/stores/auth';
import { updateRonWallet, resetPlayerAccount, getPlayerTransactions, requestRonWithdrawal, getWithdrawalHistory, getPremiumStatus, depositRon, getGameStatus, type PremiumStatus, type GameStatus } from '@/utils/api';
import { playSound } from '@/utils/sounds';
import { formatGamecoin, formatCrypto, formatNumber, formatRon } from '@/utils/format';
import { useRoninWallet } from '@/composables/useRoninWallet';
import PremiumCard from '@/components/PremiumCard.vue';
import ReferralSection from '@/components/ReferralSection.vue';

const roninWallet = useRoninWallet();

const { t } = useI18n();
const router = useRouter();
const authStore = useAuthStore();

const loading = ref(true);
const hasLoaded = ref(false);
const isLoadingInProgress = ref(false);
const transactions = ref<any[]>([]);

// Wallet editing
const editingWallet = ref(false);
const walletInput = ref('');
const savingWallet = ref(false);
const walletError = ref<string | null>(null);

// Reset account
const showResetConfirm = ref(false);
const resetConfirmText = ref('');
const resettingAccount = ref(false);
const resetError = ref<string | null>(null);

// RON Withdrawal
const showWithdrawModal = ref(false);
const withdrawing = ref(false);
const withdrawError = ref<string | null>(null);
const withdrawalHistory = ref<any[]>([]);
const pendingWithdrawal = computed(() =>
  withdrawalHistory.value.find(w => w.status === 'pending' || w.status === 'processing')
);

// RON Reload/Deposit
const showReloadModal = ref(false);
const reloadAmount = ref<string>('');
const reloading = ref(false);
const reloadError = ref<string | null>(null);
const reloadStep = ref<'input' | 'connecting' | 'sending' | 'confirming' | 'crediting' | 'success' | 'error'>('input');

// Predefined reload amounts
const reloadAmounts = [1, 5, 10, 25];

// Premium status
const premiumStatus = ref<PremiumStatus | null>(null);
const isPremium = computed(() => premiumStatus.value?.is_premium ?? false);
const withdrawalFeeRate = computed(() => isPremium.value ? 0.10 : 0.25);
const withdrawalFeePercent = computed(() => isPremium.value ? 10 : 25);

// Admin / Game Status
const gameStatus = ref<GameStatus | null>(null);
const isAdmin = computed(() => authStore.player?.role === 'admin');
const adminPanelExpanded = ref(true);

const player = computed(() => authStore.player);

const memberSince = computed(() => {
  if (!player.value?.created_at) return '-';
  return new Date(player.value.created_at).toLocaleDateString();
});

const formattedWallet = computed(() => {
  const wallet = player.value?.ron_wallet;
  if (!wallet) return null;
  return `${wallet.slice(0, 6)}...${wallet.slice(-4)}`;
});

const ronBalance = computed(() => player.value?.ron_balance ?? 0);
const canWithdraw = computed(() =>
  ronBalance.value > 0 && player.value?.ron_wallet && !pendingWithdrawal.value
);

async function loadData(force = false) {
  // Prevent duplicate/concurrent loads (unless forced)
  if (isLoadingInProgress.value) {
    return;
  }

  if (hasLoaded.value && !force) {
    loading.value = false;
    return;
  }

  isLoadingInProgress.value = true;

  try {
    if (player.value?.id) {
      const [txData, withdrawals, premium] = await Promise.all([
        getPlayerTransactions(player.value.id, 20),
        getWithdrawalHistory(player.value.id, 5),
        getPremiumStatus(player.value.id),
      ]);
      transactions.value = txData || [];
      withdrawalHistory.value = withdrawals || [];
      premiumStatus.value = premium;
      hasLoaded.value = true;

      // Load game status only for admins
      if (player.value?.role === 'admin') {
        gameStatus.value = await getGameStatus();
      }
    }
  } catch (e) {
    console.error('[ProfilePage] Error loading profile:', e);
  } finally {
    loading.value = false;
    isLoadingInProgress.value = false;
  }
}

// Watch for player to become available (handles race condition on mount)
watch(() => player.value?.id, (newId) => {
  if (newId && !hasLoaded.value) {
    loading.value = true;
    loadData();
  }
}, { immediate: true });

function startEditWallet() {
  walletInput.value = player.value?.ron_wallet || '';
  walletError.value = null;
  editingWallet.value = true;
}

function cancelEditWallet() {
  editingWallet.value = false;
  walletInput.value = '';
  walletError.value = null;
}

async function saveWallet() {
  if (savingWallet.value || !player.value) return;

  savingWallet.value = true;
  walletError.value = null;

  try {
    const result = await updateRonWallet(player.value.id, walletInput.value.trim() || null);

    if (result.success) {
      // Update local player data
      if (authStore.player) {
        authStore.player.ron_wallet = result.wallet;
      }
      playSound('success');
      editingWallet.value = false;
    } else {
      walletError.value = result.error || t('profile.wallet.errorSaving');
      playSound('error');
    }
  } catch (e) {
    console.error('Error saving wallet:', e);
    walletError.value = t('profile.wallet.errorSaving');
    playSound('error');
  } finally {
    savingWallet.value = false;
  }
}

function openResetConfirm() {
  resetConfirmText.value = '';
  resetError.value = null;
  showResetConfirm.value = true;
}

function closeResetConfirm() {
  showResetConfirm.value = false;
  resetConfirmText.value = '';
  resetError.value = null;
}

async function confirmResetAccount() {
  if (resettingAccount.value || !player.value) return;

  // Require typing username to confirm
  if (resetConfirmText.value !== player.value.username) {
    resetError.value = t('profile.reset.typeUsername');
    return;
  }

  resettingAccount.value = true;
  resetError.value = null;

  try {
    const result = await resetPlayerAccount(player.value.id);

    if (result.success) {
      playSound('success');
      // Refresh player data
      await authStore.refreshPlayer();
      closeResetConfirm();
      // Redirect to mining page
      router.push('/mining');
    } else {
      resetError.value = result.error || t('profile.reset.errorResetting');
      playSound('error');
    }
  } catch (e) {
    console.error('Error resetting account:', e);
    resetError.value = t('profile.reset.errorResetting');
    playSound('error');
  } finally {
    resettingAccount.value = false;
  }
}

function copyWallet() {
  if (player.value?.ron_wallet) {
    navigator.clipboard.writeText(player.value.ron_wallet);
    playSound('click');
  }
}

function openWithdrawModal() {
  if (!canWithdraw.value) return;
  withdrawError.value = null;
  showWithdrawModal.value = true;
}

function closeWithdrawModal() {
  showWithdrawModal.value = false;
  withdrawError.value = null;
}

function openReloadModal() {
  reloadAmount.value = '';
  reloadError.value = null;
  reloadStep.value = 'input';
  showReloadModal.value = true;
}

function closeReloadModal() {
  if (reloading.value) return;
  showReloadModal.value = false;
  reloadAmount.value = '';
  reloadError.value = null;
  reloadStep.value = 'input';
}

function selectReloadAmount(amount: number) {
  reloadAmount.value = amount.toString();
}

async function confirmReload() {
  const amount = parseFloat(reloadAmount.value);
  if (isNaN(amount) || amount <= 0 || !player.value) return;

  reloading.value = true;
  reloadError.value = null;

  try {
    // Step 1: Connect wallet if not connected
    if (!roninWallet.isConnected.value) {
      reloadStep.value = 'connecting';

      if (!roninWallet.isInstalled.value) {
        reloadStep.value = 'error';
        reloadError.value = t('profile.reload.walletNotInstalled');
        reloading.value = false;
        return;
      }

      const connected = await roninWallet.connect();
      if (!connected) {
        reloadStep.value = 'error';
        reloadError.value = roninWallet.error.value ?? t('profile.reload.connectionFailed');
        reloading.value = false;
        return;
      }
    }

    // Step 2: Send RON transaction
    reloadStep.value = 'sending';
    const sendResult = await roninWallet.sendRON(amount);

    if (!sendResult.success || !sendResult.txHash) {
      reloadStep.value = 'error';
      reloadError.value = sendResult.error ?? t('profile.reload.transactionFailed');
      reloading.value = false;
      return;
    }

    // Step 3: Wait for transaction confirmation
    reloadStep.value = 'confirming';
    const confirmResult = await roninWallet.waitForTransaction(sendResult.txHash);

    if (!confirmResult.confirmed) {
      reloadStep.value = 'error';
      reloadError.value = confirmResult.error ?? t('profile.reload.confirmationFailed');
      reloading.value = false;
      return;
    }

    // Step 4: Credit RON to player account
    reloadStep.value = 'crediting';
    const result = await depositRon(player.value.id, amount, sendResult.txHash);

    if (result?.success) {
      reloadStep.value = 'success';
      playSound('success');
      // Refresh player data
      await authStore.fetchPlayer();
    } else {
      reloadStep.value = 'error';
      reloadError.value = result?.error ?? t('profile.reload.creditFailed');
    }
  } catch (e: any) {
    console.error('Error reloading RON:', e);
    reloadStep.value = 'error';
    reloadError.value = e.message ?? t('profile.reload.error');
    playSound('error');
  } finally {
    reloading.value = false;
  }
}

async function confirmWithdraw() {
  if (withdrawing.value || !player.value || !canWithdraw.value) return;

  withdrawing.value = true;
  withdrawError.value = null;

  try {
    const result = await requestRonWithdrawal(player.value.id);

    if (result.success) {
      playSound('success');
      closeWithdrawModal();
      // Actualizar datos del jugador y historial
      await Promise.all([
        authStore.fetchPlayer(),
        loadData(true),
      ]);
    } else {
      withdrawError.value = result.error || t('profile.withdraw.error');
      playSound('error');
    }
  } catch (e) {
    console.error('Error withdrawing:', e);
    withdrawError.value = t('profile.withdraw.error');
    playSound('error');
  } finally {
    withdrawing.value = false;
  }
}

function getTransactionIcon(type: string): string {
  switch (type) {
    case 'welcome_bonus': return '🎁';
    case 'rig_purchase': return '⛏️';
    case 'cooling_purchase': return '❄️';
    case 'card_purchase': return '💳';
    case 'block_reward': return '🏆';
    case 'energy_recharge': return '⚡';
    case 'internet_recharge': return '📡';
    case 'rig_repair': return '🔧';
    case 'slot_purchase': return '🔓';
    case 'boost_purchase': return '🚀';
    case 'crypto_to_gamecoin': return '💱';
    case 'account_reset': return '🔄';
    default: return '📝';
  }
}

// Lock body scroll when modal is open
watch([showResetConfirm, showWithdrawModal, showReloadModal], ([reset, withdraw, reload]) => {
  document.body.style.overflow = (reset || withdraw || reload) ? 'hidden' : '';
});

// loadData is called by the watcher with immediate: true

onUnmounted(() => {
  // Ensure scroll is restored when component unmounts
  document.body.style.overflow = '';
});
</script>

<template>
  <div class="max-w-4xl mx-auto">
    <!-- Header -->
    <div class="mb-6">
      <h1 class="text-2xl font-display font-bold">
        <span class="gradient-text">{{ t('profile.title') }}</span>
      </h1>
      <p class="text-text-muted text-sm">{{ t('profile.subtitle', 'Gestiona tu cuenta y configuracion') }}</p>
    </div>

    <div v-if="loading" class="text-center py-12">
      <div class="animate-spin text-4xl mb-2">⏳</div>
      <p class="text-text-muted">{{ t('common.loading') }}</p>
    </div>

    <div v-else class="space-y-6">
      <!-- Profile Card -->
      <div class="card p-6">
        <div class="flex items-start gap-4">
          <!-- Avatar -->
          <div
            class="w-16 h-16 rounded-xl bg-gradient-primary flex items-center justify-center text-2xl font-bold shrink-0">
            {{ player?.username?.charAt(0).toUpperCase() }}
          </div>

          <!-- Info -->
          <div class="flex-1 min-w-0">
            <h2 class="text-xl font-bold truncate">{{ player?.username }}</h2>
            <p class="text-text-muted text-sm truncate">{{ player?.email }}</p>
            <div class="flex items-center gap-4 mt-2 text-sm text-text-muted">
              <span>🌍 {{ player?.region ?? 'Global' }}</span>
              <span>📅 {{ memberSince }}</span>
            </div>
          </div>

          <!-- Stats -->
          <div class="hidden sm:flex items-center gap-4 text-center">
            <div>
              <div class="text-xl font-bold text-status-warning">{{ formatNumber(player?.blocks_mined ?? 0) }}</div>
              <div class="text-xs text-text-muted">{{ t('profile.blocksMined', 'Bloques') }}</div>
            </div>
            <div>
              <div class="text-xl font-bold text-accent-primary">{{ formatCrypto(player?.total_crypto_earned) }}</div>
              <div class="text-xs text-text-muted">{{ t('profile.cryptoEarned', 'Minado') }}</div>
            </div>
          </div>
        </div>
      </div>

      <!-- Balances -->
      <div class="grid sm:grid-cols-3 gap-4">
        <div class="card p-4">
          <div class="flex items-center justify-between">
            <div>
              <div class="text-sm text-text-muted">GameCoin</div>
              <div class="text-2xl font-bold text-status-warning">
                🪙 {{ formatGamecoin(player?.gamecoin_balance) }}
              </div>
            </div>
            <div class="w-12 h-12 rounded-xl bg-status-warning/20 flex items-center justify-center text-2xl">
              🪙
            </div>
          </div>
        </div>

        <div class="card p-4">
          <div class="flex items-center justify-between">
            <div>
              <div class="text-sm text-text-muted">Crypto</div>
              <div class="text-2xl font-bold text-accent-primary">
                💎 {{ formatCrypto(player?.crypto_balance) }}
              </div>
            </div>
            <div class="w-12 h-12 rounded-xl bg-accent-primary/20 flex items-center justify-center text-2xl">
              💎
            </div>
          </div>
        </div>

        <div class="card p-4">
          <div class="flex items-center justify-between">
            <div>
              <div class="text-sm text-text-muted">RON</div>
              <div class="text-2xl font-bold text-purple-400">
                {{ formatRon(ronBalance) }}
              </div>
            </div>
            <div class="w-12 h-12 rounded-xl bg-purple-500/20 flex items-center justify-center text-2xl">
              💎
            </div>
          </div>

          <!-- Pending withdrawal status -->
          <div v-if="pendingWithdrawal"
            class="mt-3 p-2 bg-status-warning/10 border border-status-warning/30 rounded-lg">
            <div class="text-xs text-status-warning flex items-center gap-1">
              <span class="animate-pulse">⏳</span>
              {{ t('profile.withdraw.pending', 'Retiro pendiente') }}: {{ formatRon(pendingWithdrawal.net_amount ||
              pendingWithdrawal.amount) }} RON
            </div>
            <div class="text-xs text-text-muted mt-1">
              {{ t('profile.withdraw.processing', 'Procesando...') }}
            </div>
          </div>

          <!-- Action buttons -->
          <div v-else class="flex gap-2 mt-3">
            <!-- Reload button - always visible -->
            <button @click="openReloadModal"
              class="flex-1 py-2 rounded-lg text-sm font-medium bg-status-success/20 text-status-success hover:bg-status-success/30 transition-colors">
              {{ t('profile.reload.button', 'Recargar') }}
            </button>

            <!-- Withdraw button - only if has balance -->
            <button v-if="ronBalance > 0" @click="openWithdrawModal" :disabled="!canWithdraw"
              class="flex-1 py-2 rounded-lg text-sm font-medium bg-purple-500/20 text-purple-400 hover:bg-purple-500/30 transition-colors disabled:opacity-50 disabled:cursor-not-allowed">
              {{ player?.ron_wallet ? t('profile.withdraw.button', 'Retirar') : t('profile.withdraw.needWallet',
              'Configura wallet') }}
            </button>
          </div>
        </div>
      </div>

      <!-- Admin: Game Status -->
      <div v-if="isAdmin && gameStatus" class="card p-0 border-purple-500/40 bg-gradient-to-br from-purple-500/10 to-transparent overflow-hidden">
        <!-- Header (clickable) -->
        <div
          class="px-5 py-4 bg-purple-500/5 cursor-pointer select-none transition-colors hover:bg-purple-500/10"
          :class="{ 'border-b border-purple-500/20': adminPanelExpanded }"
          @click="adminPanelExpanded = !adminPanelExpanded"
        >
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-3">
              <div class="w-10 h-10 rounded-xl bg-purple-500/20 flex items-center justify-center">
                <span class="text-xl">🛡️</span>
              </div>
              <div>
                <h3 class="font-bold text-purple-400">Panel de Administrador</h3>
                <p class="text-xs text-text-muted">Estado del servidor en tiempo real</p>
              </div>
            </div>
            <div class="flex items-center gap-3">
              <div class="flex items-center gap-2">
                <span class="w-2 h-2 rounded-full bg-status-success animate-pulse"></span>
                <span class="text-xs text-status-success">Online</span>
              </div>
              <!-- Toggle button -->
              <button class="w-8 h-8 rounded-lg bg-purple-500/20 flex items-center justify-center transition-transform"
                :class="{ 'rotate-180': !adminPanelExpanded }">
                <svg class="w-4 h-4 text-purple-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
                </svg>
              </button>
            </div>
          </div>
        </div>

        <!-- Collapsible Content -->
        <Transition name="collapse">
          <div v-show="adminPanelExpanded" class="p-5">
            <div class="grid sm:grid-cols-2 lg:grid-cols-4 gap-4 mb-5 items-stretch">
              <!-- Network -->
              <div class="bg-bg-tertiary/50 rounded-xl border border-border/50 hover:border-accent-primary/30 transition-colors overflow-hidden flex flex-col h-full">
                <div class="p-4 flex-1">
                  <div class="flex items-center justify-between mb-3">
                    <div class="flex items-center gap-2">
                      <div class="w-8 h-8 rounded-lg bg-accent-primary/20 flex items-center justify-center text-sm">🌐</div>
                      <span class="text-sm font-medium">Red</span>
                    </div>
                    <span class="text-xs px-2 py-0.5 rounded-full bg-accent-primary/20 text-accent-primary">Blockchain</span>
                  </div>
                  <div class="space-y-2">
                    <div class="flex justify-between items-center">
                      <span class="text-xs text-text-muted">Dificultad</span>
                      <span class="text-sm font-bold text-accent-primary">{{ formatNumber(gameStatus.network.difficulty) }}</span>
                    </div>
                    <div class="flex justify-between items-center">
                      <span class="text-xs text-text-muted">Hashrate global</span>
                      <span class="text-sm font-bold">{{ formatNumber(gameStatus.network.hashrate) }} H/s</span>
                    </div>
                    <div class="flex justify-between items-center">
                      <span class="text-xs text-text-muted">Mineros activos</span>
                      <span class="text-sm font-bold text-status-success">{{ gameStatus.network.activeMiners }}</span>
                    </div>
                    <div class="flex justify-between items-center">
                      <span class="text-xs text-text-muted">Hashrate promedio</span>
                      <span class="text-sm font-bold">{{ gameStatus.network.activeMiners > 0 ? formatNumber(Math.round(gameStatus.network.hashrate / gameStatus.network.activeMiners)) : 0 }} H/s</span>
                    </div>
                  </div>
                </div>
                <!-- Carga de red (siempre abajo) -->
                <div class="px-4 py-2.5 border-t border-border/30 bg-bg-tertiary/30 mt-auto">
                  <div class="flex justify-between text-xs mb-1 whitespace-nowrap">
                    <span class="text-text-muted">Carga de red</span>
                    <span class="text-accent-primary font-medium">{{ Math.min(100, Math.round((gameStatus.network.activeMiners / Math.max(1, gameStatus.players.total)) * 100)) }}%</span>
                  </div>
                  <div class="w-full h-1.5 bg-bg-tertiary rounded-full overflow-hidden">
                    <div class="h-full bg-accent-primary rounded-full transition-all"
                      :style="{ width: `${Math.min(100, (gameStatus.network.activeMiners / Math.max(1, gameStatus.players.total)) * 100)}%` }"></div>
                  </div>
                </div>
              </div>

              <!-- Players -->
              <div class="bg-bg-tertiary/50 rounded-xl border border-border/50 hover:border-blue-500/30 transition-colors overflow-hidden flex flex-col h-full">
                <div class="p-4 flex-1">
                  <div class="flex items-center justify-between mb-3">
                    <div class="flex items-center gap-2">
                      <div class="w-8 h-8 rounded-lg bg-blue-500/20 flex items-center justify-center text-sm">👥</div>
                      <span class="text-sm font-medium">Jugadores</span>
                    </div>
                    <span class="text-xs px-2 py-0.5 rounded-full bg-blue-500/20 text-blue-400">Usuarios</span>
                  </div>
                  <div class="space-y-2">
                    <div class="flex justify-between items-center">
                      <span class="text-xs text-text-muted">Registrados</span>
                      <span class="text-sm font-bold">{{ formatNumber(gameStatus.players.total) }}</span>
                    </div>
                    <div class="flex justify-between items-center">
                      <span class="text-xs text-text-muted">Conectados ahora</span>
                      <span class="text-sm font-bold text-status-success flex items-center gap-1">
                        <span class="w-1.5 h-1.5 rounded-full bg-status-success animate-pulse"></span>
                        {{ gameStatus.players.online }}
                      </span>
                    </div>
                    <div class="flex justify-between items-center">
                      <span class="text-xs text-text-muted">Suscriptores Premium</span>
                      <span class="text-sm font-bold text-amber-400">⭐ {{ gameStatus.players.premium }}</span>
                    </div>
                    <div class="flex justify-between items-center">
                      <span class="text-xs text-text-muted">Tasa de actividad</span>
                      <span class="text-sm font-bold text-blue-400">{{ gameStatus.players.total > 0 ? ((gameStatus.players.online / gameStatus.players.total) * 100).toFixed(1) : 0 }}%</span>
                    </div>
                  </div>
                </div>
                <!-- Tasa conversion (siempre abajo) -->
                <div class="px-4 py-2.5 border-t border-border/30 bg-bg-tertiary/30 mt-auto">
                  <div class="flex justify-between text-xs mb-1 whitespace-nowrap">
                    <span class="text-text-muted">Conversion Premium</span>
                    <span class="text-amber-400 font-medium">{{ gameStatus.players.total > 0 ? ((gameStatus.players.premium / gameStatus.players.total) * 100).toFixed(1) : 0 }}%</span>
                  </div>
                  <div class="w-full h-1.5 bg-bg-tertiary rounded-full overflow-hidden">
                    <div class="h-full bg-amber-400 rounded-full transition-all"
                      :style="{ width: `${gameStatus.players.total > 0 ? Math.min(100, (gameStatus.players.premium / gameStatus.players.total) * 100) : 0}%` }"></div>
                  </div>
                </div>
              </div>

              <!-- Mining -->
              <div class="bg-bg-tertiary/50 rounded-xl border border-border/50 hover:border-status-warning/30 transition-colors overflow-hidden flex flex-col h-full">
                <div class="p-4 flex-1">
                  <div class="flex items-center justify-between mb-3">
                    <div class="flex items-center gap-2">
                      <div class="w-8 h-8 rounded-lg bg-status-warning/20 flex items-center justify-center text-sm">⛏️</div>
                      <span class="text-sm font-medium">Mineria</span>
                    </div>
                    <span class="text-xs px-2 py-0.5 rounded-full bg-status-warning/20 text-status-warning">Produccion</span>
                  </div>
                  <div class="space-y-2">
                    <div class="flex justify-between items-center">
                      <span class="text-xs text-text-muted">Bloques totales</span>
                      <span class="text-sm font-bold">{{ formatNumber(gameStatus.mining.totalBlocks) }}</span>
                    </div>
                    <div class="flex justify-between items-center">
                      <span class="text-xs text-text-muted">Minados hoy</span>
                      <span class="text-sm font-bold text-status-success flex items-center gap-1">
                        <span class="text-xs">📈</span>
                        +{{ gameStatus.mining.blocksToday }}
                      </span>
                    </div>
                    <div class="flex justify-between items-center">
                      <span class="text-xs text-text-muted">Total crypto emitido</span>
                      <span class="text-sm font-bold">💎 {{ formatCrypto(gameStatus.mining.totalCryptoMined) }}</span>
                    </div>
                    <div class="flex justify-between items-center">
                      <span class="text-xs text-text-muted">Crypto por bloque</span>
                      <span class="text-sm font-bold text-status-warning">{{ gameStatus.mining.totalBlocks > 0 ? formatCrypto(gameStatus.mining.totalCryptoMined / gameStatus.mining.totalBlocks) : 0 }}</span>
                    </div>
                  </div>
                </div>
                <!-- Promedio (siempre abajo) -->
                <div class="px-4 py-2.5 border-t border-border/30 bg-bg-tertiary/30 mt-auto">
                  <div class="flex justify-between text-xs mb-1 whitespace-nowrap">
                    <span class="text-text-muted">Produccion diaria</span>
                    <span class="text-status-warning font-medium">{{ gameStatus.mining.blocksToday }} bloques</span>
                  </div>
                  <div class="w-full h-1.5 bg-bg-tertiary rounded-full overflow-hidden">
                    <div class="h-full bg-status-warning rounded-full transition-all"
                      :style="{ width: `${Math.min(100, gameStatus.mining.blocksToday > 0 ? 50 + Math.min(50, gameStatus.mining.blocksToday / 10) : 0)}%` }"></div>
                  </div>
                </div>
              </div>

              <!-- Economy -->
              <div class="bg-bg-tertiary/50 rounded-xl border border-border/50 hover:border-purple-500/30 transition-colors overflow-hidden flex flex-col h-full">
                <!-- Contenido principal -->
                <div class="p-4 flex-1">
                  <div class="flex items-center justify-between mb-3">
                    <div class="flex items-center gap-2">
                      <div class="w-8 h-8 rounded-lg bg-purple-500/20 flex items-center justify-center text-sm">💰</div>
                      <span class="text-sm font-medium">Economia</span>
                    </div>
                    <span class="text-xs px-2 py-0.5 rounded-full bg-purple-500/20 text-purple-400">Finanzas</span>
                  </div>
                  <div class="space-y-2">
                    <!-- Ingresos -->
                    <div class="flex justify-between items-center">
                      <span class="text-xs text-text-muted flex items-center gap-1.5">📥 Depositado</span>
                      <span class="text-sm font-bold text-status-success">{{ formatRon(gameStatus.economy.totalRonDeposited) }} RON</span>
                    </div>
                    <!-- Saldo usuarios -->
                    <div class="flex justify-between items-center">
                      <span class="text-xs text-text-muted flex items-center gap-1.5">👛 Saldo usuarios</span>
                      <span class="text-sm font-bold text-purple-400">{{ formatRon(gameStatus.economy.totalRonBalance || 0) }} RON</span>
                    </div>
                    <!-- Egresos -->
                    <div class="flex justify-between items-center">
                      <span class="text-xs text-text-muted flex items-center gap-1.5">📤 Gastado</span>
                      <span class="text-sm font-bold text-status-danger">{{ formatRon(gameStatus.economy.totalRonSpent || 0) }} RON</span>
                    </div>
                    <div class="flex justify-between items-center">
                      <span class="text-xs text-text-muted flex items-center gap-1.5">💸 Retirado</span>
                      <span class="text-sm font-bold text-purple-400">{{ formatRon(gameStatus.economy.totalRonWithdrawn || 0) }} RON</span>
                    </div>
                    <!-- Pendientes -->
                    <div v-if="gameStatus.economy.pendingWithdrawals > 0" class="flex justify-between items-center">
                      <span class="text-xs text-text-muted flex items-center gap-1.5">⏳ Pendientes</span>
                      <span class="text-sm font-bold text-status-warning">{{ gameStatus.economy.pendingWithdrawals }} ({{ formatRon(gameStatus.economy.pendingWithdrawalsAmount) }} RON)</span>
                    </div>
                  </div>
                </div>
                <!-- Balance (depositado + gastado - retirado) -->
                <div class="px-4 py-2.5 border-t border-border/30 bg-bg-tertiary/30 mt-auto">
                  <div class="flex justify-between text-xs mb-1 whitespace-nowrap">
                    <span class="text-text-muted">Balance</span>
                    <span class="font-medium text-status-success">
                      {{ formatRon(gameStatus.economy.balance || 0) }} RON
                    </span>
                  </div>
                  <div class="w-full h-1.5 bg-bg-tertiary rounded-full overflow-hidden">
                    <div class="h-full bg-status-success rounded-full transition-all"
                      :style="{ width: `${gameStatus.economy.totalRonDeposited > 0 ? Math.min(100, ((gameStatus.economy.balance || 0) / gameStatus.economy.totalRonDeposited) * 100) : 0}%` }"></div>
                  </div>
                </div>
              </div>
            </div>

            <!-- Footer Stats -->
            <div class="flex flex-wrap items-center justify-between gap-4 pt-4 border-t border-border/30">
              <div class="flex items-center gap-6">
                <!-- Rigs -->
                <div class="flex items-center gap-3">
                  <div class="flex items-center gap-2 text-sm">
                    <span class="text-text-muted">⚙️ Rigs:</span>
                    <span class="font-medium">
                      <span class="text-status-success">{{ gameStatus.rigs.active }}</span>
                      <span class="text-text-muted">/{{ gameStatus.rigs.total }}</span>
                    </span>
                  </div>
                  <div class="w-20 h-1.5 bg-bg-tertiary rounded-full overflow-hidden">
                    <div class="h-full bg-status-success rounded-full transition-all"
                      :style="{ width: `${gameStatus.rigs.total > 0 ? (gameStatus.rigs.active / gameStatus.rigs.total) * 100 : 0}%` }"></div>
                  </div>
                </div>
              </div>
              <div class="flex items-center gap-2 text-xs text-text-muted">
                <span>🕐</span>
                <span>Actualizado: {{ new Date(gameStatus.timestamp).toLocaleTimeString() }}</span>
              </div>
            </div>
          </div>
        </Transition>
      </div>

      <!-- Premium Subscription -->
      <PremiumCard />

      <!-- Referral System -->
      <ReferralSection />

      <!-- RON Wallet Section -->
      <div class="card p-5">
        <div class="flex items-center justify-between mb-4">
          <h3 class="font-bold flex items-center gap-2">
            <span class="text-xl">👛</span>
            {{ t('profile.wallet.title', 'RON Wallet') }}
          </h3>
          <button v-if="!editingWallet" @click="startEditWallet"
            class="text-sm text-accent-primary hover:text-accent-primary/80 transition-colors">
            {{ player?.ron_wallet ? t('common.edit', 'Editar') : t('profile.wallet.add', 'Agregar') }}
          </button>
        </div>

        <!-- Display mode -->
        <div v-if="!editingWallet">
          <div v-if="player?.ron_wallet" class="flex items-center gap-3">
            <div class="flex-1 bg-bg-tertiary rounded-lg px-4 py-3 font-mono text-sm">
              {{ formattedWallet }}
            </div>
            <button @click="copyWallet"
              class="p-2.5 rounded-lg bg-bg-tertiary hover:bg-bg-tertiary/80 transition-colors"
              :title="t('common.copy', 'Copiar')">
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
                  d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z" />
              </svg>
            </button>
          </div>
          <p v-else class="text-text-muted text-sm">
            {{ t('profile.wallet.noWallet', 'No tienes una wallet configurada. Agrega tu direccion RON para recibir pagos.') }}
          </p>
        </div>

        <!-- Edit mode -->
        <div v-else class="space-y-3">
          <div>
            <input v-model="walletInput" type="text" :placeholder="t('profile.wallet.placeholder', '0x...')"
              class="w-full bg-bg-tertiary border border-border rounded-lg px-4 py-2.5 font-mono text-sm focus:outline-none focus:border-accent-primary transition-colors"
              :disabled="savingWallet" />
            <p class="text-xs text-text-muted mt-1.5">
              {{ t('profile.wallet.hint', 'Ingresa una direccion de wallet valida (formato Ethereum/RON)') }}
            </p>
          </div>

          <div v-if="walletError" class="p-3 rounded-lg bg-status-danger/20 border border-status-danger/30">
            <p class="text-sm text-status-danger">{{ walletError }}</p>
          </div>

          <div class="flex gap-2">
            <button @click="cancelEditWallet" :disabled="savingWallet"
              class="flex-1 py-2 rounded-lg font-medium bg-bg-tertiary hover:bg-bg-tertiary/80 transition-colors">
              {{ t('common.cancel') }}
            </button>
            <button @click="saveWallet" :disabled="savingWallet"
              class="flex-1 py-2 rounded-lg font-medium bg-accent-primary text-white hover:bg-accent-primary/90 transition-colors disabled:opacity-50">
              <span v-if="savingWallet" class="flex items-center justify-center gap-2">
                <span class="animate-spin">⏳</span>
              </span>
              <span v-else>{{ t('common.save', 'Guardar') }}</span>
            </button>
          </div>
        </div>
      </div>

      <!-- Recent Transactions -->
      <div class="card p-5">
        <h3 class="font-bold mb-4 flex items-center gap-2">
          <span class="text-xl">📜</span>
          {{ t('profile.transactions', 'Transacciones Recientes') }}
        </h3>

        <div v-if="transactions.length === 0" class="text-center py-6 text-text-muted">
          <div class="text-3xl mb-2">📭</div>
          <p class="text-sm">{{ t('profile.noTransactions', 'No hay transacciones') }}</p>
        </div>

        <div v-else class="space-y-2 max-h-64 overflow-y-auto">
          <div v-for="tx in transactions" :key="tx.id"
            class="flex items-center gap-3 py-2 border-b border-border/30 last:border-0">
            <div class="w-8 h-8 rounded-lg bg-bg-tertiary flex items-center justify-center">
              {{ getTransactionIcon(tx.type) }}
            </div>
            <div class="flex-1 min-w-0">
              <div class="text-sm truncate">{{ tx.description }}</div>
              <div class="text-xs text-text-muted">
                {{ new Date(tx.created_at).toLocaleDateString() }}
              </div>
            </div>
            <div class="text-right">
              <div class="font-medium text-sm" :class="tx.amount >= 0 ? 'text-status-success' : 'text-status-danger'">
                {{ tx.amount >= 0 ? '+' : '' }}{{ tx.currency === 'crypto' ? formatCrypto(tx.amount) :
                  formatGamecoin(tx.amount) }}
              </div>
              <div class="text-xs text-text-muted">
                {{ tx.currency === 'crypto' ? '💎' : '🪙' }}
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Danger Zone -->
      <div class="card p-5 border-status-danger/30">
        <h3 class="font-bold mb-2 text-status-danger flex items-center gap-2">
          <span class="text-xl">⚠️</span>
          {{ t('profile.dangerZone', 'Zona de Peligro') }}
        </h3>
        <p class="text-sm text-text-muted mb-4">
          {{ t('profile.dangerZoneDesc', 'Estas acciones son irreversibles. Procede con cuidado.') }}
        </p>

        <button @click="openResetConfirm"
          class="px-4 py-2.5 rounded-lg font-medium bg-status-danger/20 text-status-danger hover:bg-status-danger/30 border border-status-danger/30 transition-colors">
          🔄 {{ t('profile.reset.button', 'Reiniciar Cuenta') }}
        </button>
      </div>
    </div>

    <!-- Reset Account Confirmation Modal -->
    <Teleport to="body">
      <Transition name="modal">
        <div v-if="showResetConfirm" class="fixed inset-0 z-50 flex items-center justify-center p-4">
          <div class="absolute inset-0 bg-black/70 backdrop-blur-sm" @click="closeResetConfirm"></div>
          <div class="relative bg-bg-primary border border-status-danger/50 rounded-2xl w-full max-w-md p-6 shadow-2xl"
            @click.stop>
            <h3 class="text-lg font-bold mb-2 text-center text-status-danger">
              ⚠️ {{ t('profile.reset.title', 'Reiniciar Cuenta?') }}
            </h3>

            <div class="bg-status-danger/10 rounded-xl p-4 mb-4 text-sm">
              <p class="text-status-danger font-medium mb-2">{{ t('profile.reset.warning', 'Esta accion eliminara:') }}
              </p>
              <ul class="text-text-muted space-y-1">
                <li>• {{ t('profile.reset.item1', 'Todos tus rigs y equipamiento') }}</li>
                <li>• {{ t('profile.reset.item2', 'Todo tu inventario (cooling, tarjetas, boosts)') }}</li>
                <li>• {{ t('profile.reset.item3', 'Tu progreso de misiones y racha') }}</li>
                <li>• {{ t('profile.reset.item4', 'Historial de transacciones') }}</li>
              </ul>
              <p class="text-status-success mt-3">{{ t('profile.reset.keep', 'Recibiras: 1000 + 1 Rig basico') }}</p>
            </div>

            <div class="mb-4">
              <label class="text-sm text-text-muted block mb-1.5">
                {{ t('profile.reset.confirmLabel', 'Escribe tu nombre de usuario para confirmar:') }}
                <strong class="text-white">{{ player?.username }}</strong>
              </label>
              <input v-model="resetConfirmText" type="text" :placeholder="player?.username"
                class="w-full bg-bg-tertiary border border-border rounded-lg px-4 py-2.5 focus:outline-none focus:border-status-danger transition-colors"
                :disabled="resettingAccount" />
            </div>

            <div v-if="resetError" class="mb-4 p-3 rounded-lg bg-status-danger/20 border border-status-danger/30">
              <p class="text-sm text-status-danger text-center">{{ resetError }}</p>
            </div>

            <div class="flex gap-3">
              <button @click="closeResetConfirm" :disabled="resettingAccount"
                class="flex-1 py-2.5 rounded-lg font-medium bg-bg-tertiary hover:bg-bg-tertiary/80 transition-colors">
                {{ t('common.cancel') }}
              </button>
              <button @click="confirmResetAccount" :disabled="resettingAccount || resetConfirmText !== player?.username"
                class="flex-1 py-2.5 rounded-lg font-semibold bg-status-danger text-white hover:bg-status-danger/90 transition-colors disabled:opacity-50">
                <span v-if="resettingAccount" class="flex items-center justify-center gap-2">
                  <span class="animate-spin">⏳</span>
                </span>
                <span v-else>{{ t('profile.reset.confirm', 'Reiniciar') }}</span>
              </button>
            </div>
          </div>
        </div>
      </Transition>
    </Teleport>

    <!-- RON Withdrawal Modal -->
    <Teleport to="body">
      <Transition name="modal">
        <div v-if="showWithdrawModal" class="fixed inset-0 z-50 flex items-center justify-center p-4">
          <div class="absolute inset-0 bg-black/70 backdrop-blur-sm"></div>
          <div class="relative bg-bg-primary border border-purple-500/50 rounded-2xl w-full max-w-md p-6 shadow-2xl"
            @click.stop>
            <h3 class="text-lg font-bold mb-4 text-center text-purple-400">
              💎 {{ t('profile.withdraw.title', 'Retirar RON') }}
            </h3>

            <!-- Balance y desglose de comision -->
            <div class="bg-bg-tertiary rounded-xl p-4 mb-4 space-y-3">
              <div class="flex justify-between items-center">
                <span class="text-sm text-text-muted">{{ t('profile.withdraw.available', 'Disponible') }}</span>
                <span class="font-medium">{{ formatRon(ronBalance) }} RON</span>
              </div>
              <div class="flex justify-between items-center"
                :class="isPremium ? 'text-status-success' : 'text-status-danger'">
                <span class="text-sm flex items-center gap-1">
                  {{ t('profile.withdraw.fee', 'Comision') }} ({{ withdrawalFeePercent }}%)
                  <span v-if="isPremium"
                    class="text-xs bg-amber-500/20 text-amber-400 px-1.5 py-0.5 rounded">Premium</span>
                </span>
                <span class="font-medium">-{{ formatRon(ronBalance * withdrawalFeeRate) }} RON</span>
              </div>
              <div class="border-t border-border pt-3 flex justify-between items-center">
                <span class="text-sm font-medium text-status-success">{{ t('profile.withdraw.youReceive', 'Recibiras')
                  }}</span>
                <span class="text-xl font-bold text-purple-400">{{ formatRon(ronBalance * (1 - withdrawalFeeRate)) }}
                  RON</span>
              </div>
            </div>

            <div class="bg-bg-tertiary rounded-xl p-4 mb-4">
              <div class="text-sm text-text-muted mb-1">{{ t('profile.withdraw.destination', 'Wallet destino') }}</div>
              <div class="font-mono text-sm">{{ formattedWallet }}</div>
            </div>

            <div class="bg-status-warning/10 border border-status-warning/30 rounded-xl p-3 mb-4 text-sm">
              <p class="text-status-warning">
                ⚠️ {{ t('profile.withdraw.warning', 'Los retiros pueden tardar hasta 24 horas en procesarse.') }}
              </p>
            </div>

            <div v-if="withdrawError" class="mb-4 p-3 rounded-lg bg-status-danger/20 border border-status-danger/30">
              <p class="text-sm text-status-danger text-center">{{ withdrawError }}</p>
            </div>

            <div class="flex gap-3">
              <button @click="closeWithdrawModal" :disabled="withdrawing"
                class="flex-1 py-2.5 rounded-lg font-medium bg-bg-tertiary hover:bg-bg-tertiary/80 transition-colors">
                {{ t('common.cancel') }}
              </button>
              <button @click="confirmWithdraw" :disabled="withdrawing"
                class="flex-1 py-2.5 rounded-lg font-semibold bg-purple-500 text-white hover:bg-purple-500/90 transition-colors disabled:opacity-50">
                <span v-if="withdrawing" class="flex items-center justify-center gap-2">
                  <span class="animate-spin">⏳</span>
                </span>
                <span v-else>{{ t('profile.withdraw.confirm', 'Confirmar Retiro') }}</span>
              </button>
            </div>
          </div>
        </div>
      </Transition>
    </Teleport>

    <!-- RON Reload/Deposit Modal -->
    <Teleport to="body">
      <Transition name="modal">
        <div v-if="showReloadModal" class="fixed inset-0 z-50 flex items-center justify-center p-4">
          <div class="absolute inset-0 bg-black/70 backdrop-blur-sm" @click="closeReloadModal"></div>
          <div class="relative bg-bg-primary border border-status-success/50 rounded-2xl w-full max-w-md p-6 shadow-2xl"
            @click.stop>
            <!-- Input State -->
            <template v-if="reloadStep === 'input'">
              <h3 class="text-lg font-bold mb-4 text-center text-status-success">
                💰 {{ t('profile.reload.title', 'Recargar RON') }}
              </h3>

              <p class="text-sm text-text-muted text-center mb-4">
                {{ t('profile.reload.description', 'Conecta tu Ronin Wallet para depositar RON en tu cuenta.') }}
              </p>

              <!-- Amount input -->
              <div class="mb-4">
                <label class="text-sm text-text-muted block mb-2">{{ t('profile.reload.amount', 'Cantidad a depositar')
                  }}</label>
                <input v-model="reloadAmount" type="number" min="0.1" step="0.1" placeholder="0.00"
                  class="w-full bg-bg-tertiary border border-border rounded-lg px-4 py-3 text-xl font-bold text-center focus:outline-none focus:border-status-success transition-colors" />
              </div>

              <!-- Quick amount buttons -->
              <div class="grid grid-cols-4 gap-2 mb-4">
                <button v-for="amount in reloadAmounts" :key="amount" @click="selectReloadAmount(amount)" :class="[
                  'py-2 rounded-lg text-sm font-medium transition-colors',
                  reloadAmount === amount.toString()
                    ? 'bg-status-success text-white'
                    : 'bg-bg-tertiary text-text-muted hover:bg-bg-tertiary/80'
                ]">
                  {{ amount }} RON
                </button>
              </div>

              <!-- Current balance -->
              <div class="bg-bg-tertiary rounded-xl p-3 mb-4 flex justify-between items-center">
                <span class="text-sm text-text-muted">{{ t('profile.reload.currentBalance', 'Balance actual') }}</span>
                <span class="font-medium text-purple-400">{{ formatRon(ronBalance) }} RON</span>
              </div>

              <div v-if="reloadError" class="mb-4 p-3 rounded-lg bg-status-danger/20 border border-status-danger/30">
                <p class="text-sm text-status-danger text-center">{{ reloadError }}</p>
              </div>

              <div class="flex gap-3">
                <button @click="closeReloadModal"
                  class="flex-1 py-2.5 rounded-lg font-medium bg-bg-tertiary hover:bg-bg-tertiary/80 transition-colors">
                  {{ t('common.cancel') }}
                </button>
                <button @click="confirmReload" :disabled="!reloadAmount || parseFloat(reloadAmount) <= 0"
                  class="flex-1 py-2.5 rounded-lg font-semibold bg-status-success text-white hover:bg-status-success/90 transition-colors disabled:opacity-50 disabled:cursor-not-allowed">
                  {{ t('profile.reload.continue', 'Continuar') }}
                </button>
              </div>
            </template>

            <!-- Processing States -->
            <template v-else-if="['connecting', 'sending', 'confirming', 'crediting'].includes(reloadStep)">
              <div class="text-center py-4">
                <div class="relative w-16 h-16 mx-auto mb-4">
                  <div class="absolute inset-0 border-4 border-status-success/20 rounded-full"></div>
                  <div
                    class="absolute inset-0 border-4 border-status-success border-t-transparent rounded-full animate-spin">
                  </div>
                </div>
                <h3 class="text-lg font-bold mb-2">
                  {{ reloadStep === 'connecting' ? t('profile.reload.connecting', 'Conectando wallet...') :
                    reloadStep === 'sending' ? t('profile.reload.sending', 'Enviando transaccion...') :
                      reloadStep === 'confirming' ? t('profile.reload.confirming', 'Confirmando...') :
                        t('profile.reload.crediting', 'Acreditando RON...') }}
                </h3>
                <p class="text-text-muted text-sm">
                  {{ reloadStep === 'connecting' ? t('profile.reload.connectingDesc', 'Aprueba la conexion en tu Ronin Wallet') :
                     reloadStep === 'sending' ? t('profile.reload.sendingDesc', 'Confirma la transaccion en tu wallet') :
                     reloadStep === 'confirming' ? t('profile.reload.confirmingDesc', 'Esperando confirmacion en la blockchain...') :
                     t('profile.reload.creditingDesc', 'Actualizando tu balance...') }}
                </p>
                <!-- Progress indicator -->
                <div class="mt-4 flex justify-center gap-2">
                  <div class="w-2 h-2 rounded-full" :class="reloadStep ? 'bg-status-success' : 'bg-bg-tertiary'"></div>
                  <div class="w-2 h-2 rounded-full"
                    :class="['sending', 'confirming', 'crediting'].includes(reloadStep) ? 'bg-status-success' : 'bg-bg-tertiary'">
                  </div>
                  <div class="w-2 h-2 rounded-full"
                    :class="['confirming', 'crediting'].includes(reloadStep) ? 'bg-status-success' : 'bg-bg-tertiary'">
                  </div>
                  <div class="w-2 h-2 rounded-full"
                    :class="reloadStep === 'crediting' ? 'bg-status-success' : 'bg-bg-tertiary'"></div>
                </div>
              </div>
            </template>

            <!-- Success State -->
            <template v-else-if="reloadStep === 'success'">
              <div class="text-center py-4">
                <div class="w-16 h-16 mx-auto mb-4 bg-status-success/20 rounded-full flex items-center justify-center">
                  <svg class="w-8 h-8 text-status-success" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
                  </svg>
                </div>
                <h3 class="text-lg font-bold text-status-success mb-2">{{ t('profile.reload.success', 'Deposito exitoso!') }}</h3>
                <p class="text-text-muted text-sm mb-4">
                  {{ t('profile.reload.successDesc', 'Tu RON ha sido acreditado a tu cuenta.') }}
                </p>
                <div class="bg-bg-tertiary rounded-xl p-4 mb-4">
                  <div class="text-sm text-text-muted mb-1">{{ t('profile.reload.deposited', 'Depositado') }}</div>
                  <div class="text-2xl font-bold text-status-success">+{{ reloadAmount }} RON</div>
                </div>
                <button @click="closeReloadModal"
                  class="w-full py-2.5 rounded-lg font-medium bg-status-success/20 text-status-success hover:bg-status-success/30 transition-colors">
                  {{ t('common.close', 'Cerrar') }}
                </button>
              </div>
            </template>

            <!-- Error State -->
            <template v-else-if="reloadStep === 'error'">
              <div class="text-center py-4">
                <div class="w-16 h-16 mx-auto mb-4 bg-status-danger/20 rounded-full flex items-center justify-center">
                  <svg class="w-8 h-8 text-status-danger" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                  </svg>
                </div>
                <h3 class="text-lg font-bold text-status-danger mb-2">{{ t('profile.reload.errorTitle', 'Error') }}</h3>
                <p class="text-text-muted text-sm mb-4">{{ reloadError }}</p>
                <div class="flex flex-col gap-2">
                  <button v-if="reloadError === t('profile.reload.walletNotInstalled')"
                    @click="roninWallet.openInstallPage()"
                    class="w-full py-2.5 rounded-lg font-medium bg-blue-500/20 text-blue-400 hover:bg-blue-500/30 transition-colors">
                    {{ t('profile.reload.installWallet', 'Instalar Ronin Wallet') }}
                  </button>
                  <button @click="reloadStep = 'input'; reloadError = null"
                    class="w-full py-2.5 rounded-lg font-medium bg-bg-tertiary hover:bg-bg-tertiary/80 transition-colors">
                    {{ t('common.tryAgain', 'Intentar de nuevo') }}
                  </button>
                  <button @click="closeReloadModal"
                    class="w-full py-2.5 rounded-lg font-medium text-text-muted hover:text-white transition-colors">
                    {{ t('common.cancel') }}
                  </button>
                </div>
              </div>
            </template>
          </div>
        </div>
      </Transition>
    </Teleport>
  </div>
</template>

<style scoped>
.modal-enter-active,
.modal-leave-active {
  transition: opacity 0.3s ease;
}

.modal-enter-from,
.modal-leave-to {
  opacity: 0;
}

.modal-enter-from .relative,
.modal-leave-to .relative {
  transform: scale(0.95);
}

/* Collapse animation */
.collapse-enter-active,
.collapse-leave-active {
  transition: all 0.3s ease;
  overflow: hidden;
}

.collapse-enter-from,
.collapse-leave-to {
  opacity: 0;
  max-height: 0;
  padding-top: 0;
  padding-bottom: 0;
}

.collapse-enter-to,
.collapse-leave-from {
  opacity: 1;
  max-height: 600px;
}
</style>
