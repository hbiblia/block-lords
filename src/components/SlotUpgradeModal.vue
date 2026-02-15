<script setup lang="ts">
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAuthStore } from '@/stores/auth';
import { getPlayerSlotInfo, getRigSlotUpgrades, buyRigSlot } from '@/utils/api';

const { t } = useI18n();
const authStore = useAuthStore();

const props = defineProps<{
  show: boolean;
}>();

const emit = defineEmits<{
  close: [];
  purchased: [];
}>();

// Load data when modal opens
watch(() => props.show, (isOpen) => {
  if (isOpen) {
    loadData();
  }
});

const loading = ref(false);
const buying = ref(false);
const error = ref<string | null>(null);
const success = ref(false);

const slotInfo = ref<{
  current_slots: number;
  used_slots: number;
  available_slots: number;
  max_slots: number;
  next_upgrade: {
    slot_number: number;
    price: number;
    currency: string;
    name: string;
    description: string;
  } | null;
} | null>(null);

const allUpgrades = ref<Array<{
  slot_number: number;
  price: number;
  currency: string;
  name: string;
  description: string;
}>>([]);

const balance = computed(() => authStore.player?.gamecoin_balance ?? 0);
const cryptoBalance = computed(() => authStore.player?.crypto_balance ?? 0);
const ronBalance = computed(() => authStore.player?.ron_balance ?? 0);

const canAffordNextUpgrade = computed(() => {
  if (!slotInfo.value?.next_upgrade) return false;
  const upgrade = slotInfo.value.next_upgrade;
  if (upgrade.currency === 'gamecoin') {
    return balance.value >= upgrade.price;
  } else if (upgrade.currency === 'ron') {
    return ronBalance.value >= upgrade.price;
  }
  return cryptoBalance.value >= upgrade.price;
});

async function loadData() {
  loading.value = true;
  error.value = null;
  try {
    if (authStore.player) {
      const [info, upgrades] = await Promise.all([
        getPlayerSlotInfo(authStore.player.id),
        getRigSlotUpgrades(),
      ]);
      slotInfo.value = info;
      allUpgrades.value = upgrades ?? [];
    }
  } catch (e) {
    console.error('Error loading slot info:', e);
    error.value = 'Error cargando información de slots';
  } finally {
    loading.value = false;
  }
}

async function handleBuySlot() {
  if (!authStore.player || !slotInfo.value?.next_upgrade || buying.value) return;

  buying.value = true;
  error.value = null;
  success.value = false;

  try {
    const result = await buyRigSlot(authStore.player.id);

    if (result?.success) {
      success.value = true;
      await authStore.fetchPlayer();
      await loadData();
      emit('purchased');

      // Auto-close after success
      setTimeout(() => {
        success.value = false;
      }, 2000);
    } else {
      error.value = result?.error ?? 'Error comprando slot';
    }
  } catch (e) {
    console.error('Error buying slot:', e);
    error.value = 'Error de conexión';
  } finally {
    buying.value = false;
  }
}

function formatPrice(price: number, currency: string): string {
  if (currency === 'ron') {
    return `${price.toLocaleString()} RON`;
  }
  if (currency === 'crypto') {
    return `${price.toLocaleString()} Landwork`;
  }
  return `${price.toLocaleString()} GC`;
}

function getCurrencyIcon(currency: string): string {
  if (currency === 'ron') return '🔷';
  if (currency === 'crypto') return '💎';
  return '🪙';
}

function getDescription(descriptionKey: string): string {
  const key = `slots.descriptions.${descriptionKey}`;
  const translated = t(key);
  return translated !== key ? translated : descriptionKey;
}
</script>

<template>
  <Teleport to="body">
    <Transition name="modal">
      <div
        v-if="show"
        class="fixed inset-0 z-50 flex items-center justify-center p-4"
        @click.self="emit('close')"
      >
        <!-- Backdrop -->
        <div class="absolute inset-0 bg-black/70 backdrop-blur-sm"></div>

        <!-- Modal -->
        <div class="relative bg-bg-primary border border-border rounded-2xl w-full max-w-lg max-h-[90vh] overflow-hidden shadow-2xl">
          <!-- Header -->
          <div class="flex items-center justify-between p-4 border-b border-border">
            <h2 class="text-xl font-bold flex items-center gap-2">
              <span>🖥️</span>
              {{ t('slots.title', 'Slots de Rigs') }}
            </h2>
            <button
              @click="emit('close')"
              class="p-2 hover:bg-bg-secondary rounded-lg transition-colors"
            >
              ✕
            </button>
          </div>

          <!-- Content -->
          <div class="p-4 overflow-y-auto max-h-[calc(90vh-140px)]">
            <!-- Loading -->
            <div v-if="loading" class="text-center py-8">
              <div class="animate-spin w-8 h-8 border-2 border-accent-primary border-t-transparent rounded-full mx-auto mb-4"></div>
              <p class="text-text-muted">{{ t('common.loading', 'Cargando...') }}</p>
            </div>

            <template v-else-if="slotInfo">
              <!-- Current Slots Status -->
              <div class="bg-bg-secondary rounded-xl p-4 mb-4">
                <div class="flex items-center justify-between mb-3">
                  <span class="text-text-muted">{{ t('slots.currentSlots', 'Slots actuales') }}</span>
                  <span class="text-2xl font-bold">
                    <span class="text-accent-primary">{{ slotInfo.used_slots }}</span>
                    <span class="text-text-muted">/</span>
                    <span>{{ slotInfo.current_slots }}</span>
                  </span>
                </div>

                <!-- Progress bar -->
                <div class="h-3 bg-bg-tertiary rounded-full overflow-hidden mb-2">
                  <div
                    class="h-full bg-gradient-to-r from-accent-primary to-accent-secondary transition-all"
                    :style="{ width: `${(slotInfo.used_slots / slotInfo.current_slots) * 100}%` }"
                  ></div>
                </div>

                <div class="flex justify-between text-xs text-text-muted">
                  <span>{{ t('slots.used', 'Usados') }}: {{ slotInfo.used_slots }}</span>
                  <span>{{ t('slots.available', 'Disponibles') }}: {{ slotInfo.available_slots }}</span>
                </div>
              </div>

              <!-- Next Upgrade -->
              <div v-if="slotInfo.next_upgrade" class="mb-4">
                <h3 class="text-sm font-semibold text-text-muted mb-2">
                  {{ t('slots.nextUpgrade', 'Siguiente mejora') }}
                </h3>
                <div class="bg-bg-secondary rounded-xl p-4 border border-accent-primary/30">
                  <div class="flex items-center justify-between mb-3">
                    <div>
                      <div class="font-semibold">{{ slotInfo.next_upgrade.name }}</div>
                      <div class="text-sm text-text-muted">{{ getDescription(slotInfo.next_upgrade.description) }}</div>
                    </div>
                    <div class="text-right">
                      <div class="text-lg font-bold" :class="canAffordNextUpgrade ? 'text-status-success' : 'text-status-danger'">
                        {{ getCurrencyIcon(slotInfo.next_upgrade.currency) }}
                        {{ formatPrice(slotInfo.next_upgrade.price, slotInfo.next_upgrade.currency) }}
                      </div>
                    </div>
                  </div>

                  <!-- Success message -->
                  <div v-if="success" class="bg-status-success/20 text-status-success rounded-lg p-3 mb-3 text-center">
                    {{ t('slots.purchaseSuccess', 'Slot comprado exitosamente!') }}
                  </div>

                  <!-- Error message -->
                  <div v-if="error" class="bg-status-danger/20 text-status-danger rounded-lg p-3 mb-3 text-center">
                    {{ error }}
                  </div>

                  <button
                    @click="handleBuySlot"
                    :disabled="!canAffordNextUpgrade || buying"
                    class="w-full py-3 rounded-xl font-semibold transition-all"
                    :class="canAffordNextUpgrade && !buying
                      ? 'bg-gradient-primary hover:opacity-90'
                      : 'bg-bg-tertiary text-text-muted cursor-not-allowed'"
                  >
                    <span v-if="buying" class="flex items-center justify-center gap-2">
                      <span class="animate-spin">⏳</span>
                      {{ t('common.processing', 'Procesando...') }}
                    </span>
                    <span v-else-if="!canAffordNextUpgrade">
                      {{ t('slots.insufficientFunds', 'Fondos insuficientes') }}
                    </span>
                    <span v-else>
                      {{ t('slots.buySlot', 'Comprar Slot') }}
                    </span>
                  </button>
                </div>
              </div>

              <!-- Max slots reached -->
              <div v-else class="bg-status-success/10 border border-status-success/30 rounded-xl p-4 text-center">
                <div class="text-3xl mb-2">🏆</div>
                <div class="text-status-success font-semibold">{{ t('slots.maxReached', 'Has alcanzado el máximo de slots!') }}</div>
                <div class="text-sm text-text-muted">{{ slotInfo.max_slots }} slots</div>
              </div>

              <!-- Future Upgrades Preview -->
              <div v-if="allUpgrades.length > 0" class="mt-4">
                <h3 class="text-sm font-semibold text-text-muted mb-2">
                  {{ t('slots.allUpgrades', 'Todas las mejoras') }}
                </h3>
                <div class="space-y-2 max-h-48 overflow-y-auto">
                  <div
                    v-for="upgrade in allUpgrades"
                    :key="upgrade.slot_number"
                    class="flex items-center justify-between p-2 rounded-lg text-sm"
                    :class="upgrade.slot_number <= slotInfo.current_slots
                      ? 'bg-status-success/10 text-status-success'
                      : upgrade.slot_number === slotInfo.current_slots + 1
                        ? 'bg-accent-primary/10 border border-accent-primary/30'
                        : 'bg-bg-secondary/50 text-text-muted'"
                  >
                    <div class="flex items-center gap-2">
                      <span v-if="upgrade.slot_number <= slotInfo.current_slots">✓</span>
                      <span v-else-if="upgrade.slot_number === slotInfo.current_slots + 1">→</span>
                      <span v-else>○</span>
                      <span>{{ upgrade.name }}</span>
                    </div>
                    <span class="font-mono">
                      {{ getCurrencyIcon(upgrade.currency) }}
                      {{ formatPrice(upgrade.price, upgrade.currency) }}
                    </span>
                  </div>
                </div>
              </div>
            </template>
          </div>

          <!-- Footer -->
          <div class="p-4 border-t border-border bg-bg-secondary/50">
            <div class="flex items-center justify-between text-sm">
              <div class="flex items-center gap-4">
                <span class="text-text-muted">
                  🪙 {{ balance.toLocaleString() }} GC
                </span>
                <span class="text-text-muted">
                  💎 {{ cryptoBalance.toLocaleString() }} Landwork
                </span>
                <span class="text-text-muted">
                  🔷 {{ ronBalance.toFixed(4) }} RON
                </span>
              </div>
              <button
                @click="emit('close')"
                class="px-4 py-2 bg-bg-tertiary hover:bg-bg-tertiary/80 rounded-lg transition-colors"
              >
                {{ t('common.close', 'Cerrar') }}
              </button>
            </div>
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
.modal-enter-active,
.modal-leave-active {
  transition: all 0.3s ease;
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
