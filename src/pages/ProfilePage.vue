<script setup lang="ts">
import { ref, onMounted, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAuthStore } from '@/stores/auth';
import { updateRonWallet, resetPlayerAccount, getPlayerTransactions } from '@/utils/api';
import { playSound } from '@/utils/sounds';

const { t } = useI18n();
const router = useRouter();
const authStore = useAuthStore();

const loading = ref(true);
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

async function loadData() {
  try {
    if (player.value?.id) {
      const txData = await getPlayerTransactions(player.value.id, 20);
      transactions.value = txData || [];
    }
  } catch (e) {
    console.error('Error loading profile:', e);
  } finally {
    loading.value = false;
  }
}

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

onMounted(loadData);
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
          <div class="w-16 h-16 rounded-xl bg-gradient-primary flex items-center justify-center text-2xl font-bold shrink-0">
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
              <div class="text-xl font-bold text-status-warning">{{ player?.blocks_mined ?? 0 }}</div>
              <div class="text-xs text-text-muted">{{ t('profile.blocksMined', 'Bloques') }}</div>
            </div>
            <div>
              <div class="text-xl font-bold text-accent-primary">{{ (player?.total_crypto_earned ?? 0).toFixed(4) }}</div>
              <div class="text-xs text-text-muted">{{ t('profile.cryptoEarned', 'Crypto') }}</div>
            </div>
          </div>
        </div>
      </div>

      <!-- Balances -->
      <div class="grid sm:grid-cols-2 gap-4">
        <div class="card p-4">
          <div class="flex items-center justify-between">
            <div>
              <div class="text-sm text-text-muted">GameCoin</div>
              <div class="text-2xl font-bold text-status-warning">
                🪙 {{ player?.gamecoin_balance?.toFixed(2) }}
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
                💎 {{ player?.crypto_balance?.toFixed(6) }}
              </div>
            </div>
            <div class="w-12 h-12 rounded-xl bg-accent-primary/20 flex items-center justify-center text-2xl">
              💎
            </div>
          </div>
        </div>
      </div>

      <!-- RON Wallet Section -->
      <div class="card p-5">
        <div class="flex items-center justify-between mb-4">
          <h3 class="font-bold flex items-center gap-2">
            <span class="text-xl">👛</span>
            {{ t('profile.wallet.title', 'RON Wallet') }}
          </h3>
          <button
            v-if="!editingWallet"
            @click="startEditWallet"
            class="text-sm text-accent-primary hover:text-accent-primary/80 transition-colors"
          >
            {{ player?.ron_wallet ? t('common.edit', 'Editar') : t('profile.wallet.add', 'Agregar') }}
          </button>
        </div>

        <!-- Display mode -->
        <div v-if="!editingWallet">
          <div v-if="player?.ron_wallet" class="flex items-center gap-3">
            <div class="flex-1 bg-bg-tertiary rounded-lg px-4 py-3 font-mono text-sm">
              {{ formattedWallet }}
            </div>
            <button
              @click="copyWallet"
              class="p-2.5 rounded-lg bg-bg-tertiary hover:bg-bg-tertiary/80 transition-colors"
              :title="t('common.copy', 'Copiar')"
            >
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z" />
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
            <input
              v-model="walletInput"
              type="text"
              :placeholder="t('profile.wallet.placeholder', '0x...')"
              class="w-full bg-bg-tertiary border border-border rounded-lg px-4 py-2.5 font-mono text-sm focus:outline-none focus:border-accent-primary transition-colors"
              :disabled="savingWallet"
            />
            <p class="text-xs text-text-muted mt-1.5">
              {{ t('profile.wallet.hint', 'Ingresa una direccion de wallet valida (formato Ethereum/RON)') }}
            </p>
          </div>

          <div v-if="walletError" class="p-3 rounded-lg bg-status-danger/20 border border-status-danger/30">
            <p class="text-sm text-status-danger">{{ walletError }}</p>
          </div>

          <div class="flex gap-2">
            <button
              @click="cancelEditWallet"
              :disabled="savingWallet"
              class="flex-1 py-2 rounded-lg font-medium bg-bg-tertiary hover:bg-bg-tertiary/80 transition-colors"
            >
              {{ t('common.cancel') }}
            </button>
            <button
              @click="saveWallet"
              :disabled="savingWallet"
              class="flex-1 py-2 rounded-lg font-medium bg-accent-primary text-white hover:bg-accent-primary/90 transition-colors disabled:opacity-50"
            >
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
          <div
            v-for="tx in transactions"
            :key="tx.id"
            class="flex items-center gap-3 py-2 border-b border-border/30 last:border-0"
          >
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
              <div
                class="font-medium text-sm"
                :class="tx.amount >= 0 ? 'text-status-success' : 'text-status-danger'"
              >
                {{ tx.amount >= 0 ? '+' : '' }}{{ tx.amount.toFixed(2) }}
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

        <button
          @click="openResetConfirm"
          class="px-4 py-2.5 rounded-lg font-medium bg-status-danger/20 text-status-danger hover:bg-status-danger/30 border border-status-danger/30 transition-colors"
        >
          🔄 {{ t('profile.reset.button', 'Reiniciar Cuenta') }}
        </button>
      </div>
    </div>

    <!-- Reset Account Confirmation Modal -->
    <Teleport to="body">
      <Transition name="modal">
        <div
          v-if="showResetConfirm"
          class="fixed inset-0 z-50 flex items-center justify-center p-4"
          @click.self="closeResetConfirm"
        >
          <div class="absolute inset-0 bg-black/70 backdrop-blur-sm"></div>
          <div class="relative bg-bg-primary border border-status-danger/50 rounded-2xl w-full max-w-md p-6 shadow-2xl">
            <h3 class="text-lg font-bold mb-2 text-center text-status-danger">
              ⚠️ {{ t('profile.reset.title', 'Reiniciar Cuenta?') }}
            </h3>

            <div class="bg-status-danger/10 rounded-xl p-4 mb-4 text-sm">
              <p class="text-status-danger font-medium mb-2">{{ t('profile.reset.warning', 'Esta accion eliminara:') }}</p>
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
              <input
                v-model="resetConfirmText"
                type="text"
                :placeholder="player?.username"
                class="w-full bg-bg-tertiary border border-border rounded-lg px-4 py-2.5 focus:outline-none focus:border-status-danger transition-colors"
                :disabled="resettingAccount"
              />
            </div>

            <div v-if="resetError" class="mb-4 p-3 rounded-lg bg-status-danger/20 border border-status-danger/30">
              <p class="text-sm text-status-danger text-center">{{ resetError }}</p>
            </div>

            <div class="flex gap-3">
              <button
                @click="closeResetConfirm"
                :disabled="resettingAccount"
                class="flex-1 py-2.5 rounded-lg font-medium bg-bg-tertiary hover:bg-bg-tertiary/80 transition-colors"
              >
                {{ t('common.cancel') }}
              </button>
              <button
                @click="confirmResetAccount"
                :disabled="resettingAccount || resetConfirmText !== player?.username"
                class="flex-1 py-2.5 rounded-lg font-semibold bg-status-danger text-white hover:bg-status-danger/90 transition-colors disabled:opacity-50"
              >
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
</style>
