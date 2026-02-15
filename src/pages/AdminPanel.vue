<script setup lang="ts">
import { ref, computed, onMounted, watch } from 'vue';
import { useAuthStore } from '@/stores/auth';
import { useRouter } from 'vue-router';
import {
  adminGetAllAnnouncements,
  adminCreateAnnouncement,
  adminUpdateAnnouncement,
  adminDeleteAnnouncement,
  adminCreateUpdateAnnouncement,
  adminGetPlayers,
  adminGetPlayerDetail,
  adminSendGift,
  getBoostItems,
  type CreateAnnouncementParams,
  type AdminSendGiftParams
} from '@/utils/api';
import { playSound } from '@/utils/sounds';

const authStore = useAuthStore();
const router = useRouter();

interface Announcement {
  id: string;
  message: string;
  message_es?: string;
  type: 'info' | 'warning' | 'success' | 'error' | 'maintenance' | 'update';
  icon: string;
  link_url?: string;
  link_text?: string;
  is_active: boolean;
  priority: number;
  starts_at: string;
  ends_at?: string;
  created_at: string;
  updated_at: string;
}

const announcements = ref<Announcement[]>([]);
const loading = ref(true);
const showModal = ref(false);
const editingAnnouncement = ref<Announcement | null>(null);
const error = ref('');
const saving = ref(false);

// Form data
const form = ref<CreateAnnouncementParams>({
  message: '',
  message_es: '',
  type: 'info',
  icon: '📢',
  link_url: '',
  link_text: '',
  is_active: true,
  priority: 0,
  starts_at: new Date().toISOString().slice(0, 16),
  ends_at: '',
});

const isAdmin = computed(() => authStore.player?.role === 'admin');

const claimedBlocksTotalReward = computed(() => {
  if (!selectedUserDetail.value?.claimed_blocks) return 0;
  return selectedUserDetail.value.claimed_blocks.reduce((sum: number, block: any) => {
    return sum + Number(block.reward || 0);
  }, 0);
});

const activeRigsCount = computed(() => {
  if (!selectedUserDetail.value?.rigs) return 0;
  return selectedUserDetail.value.rigs.filter((rig: any) => rig.is_active).length;
});

const blcValueInRon = computed(() => {
  const Landwork = Number(selectedUser.value?.crypto_balance || 0);
  // Rate: 100,000 Landwork = 1 RON
  return Landwork / 100000;
});

const typeOptions = [
  { value: 'info', label: 'Info', color: 'text-accent-primary' },
  { value: 'warning', label: 'Warning', color: 'text-status-warning' },
  { value: 'success', label: 'Success', color: 'text-status-success' },
  { value: 'error', label: 'Error', color: 'text-status-danger' },
  { value: 'maintenance', label: 'Maintenance', color: 'text-amber-400' },
  { value: 'update', label: 'Update', color: 'text-blue-400' },
];

const iconOptions = [
  '📢', '⚠️', '✅', '❌', '🔧', 'ℹ️', '⭐', '🎉', '🚀', '💡', '🎮', '⛏️', '👑', '💰', '🔥'
];

async function loadAnnouncements() {
  try {
    loading.value = true;
    error.value = '';
    const data = await adminGetAllAnnouncements();
    announcements.value = data || [];
  } catch (e: any) {
    console.error('Error loading announcements:', e);
    error.value = e.message || 'Error al cargar anuncios';
    playSound('error');
  } finally {
    loading.value = false;
  }
}

function openCreateModal() {
  editingAnnouncement.value = null;
  form.value = {
    message: '',
    message_es: '',
    type: 'info',
    icon: '📢',
    link_url: '',
    link_text: '',
    is_active: true,
    priority: 0,
    starts_at: new Date().toISOString().slice(0, 16),
    ends_at: '',
  };
  showModal.value = true;
  playSound('click');
}

function openEditModal(announcement: Announcement) {
  editingAnnouncement.value = announcement;
  form.value = {
    message: announcement.message,
    message_es: announcement.message_es || '',
    type: announcement.type,
    icon: announcement.icon,
    link_url: announcement.link_url || '',
    link_text: announcement.link_text || '',
    is_active: announcement.is_active,
    priority: announcement.priority,
    starts_at: announcement.starts_at ? new Date(announcement.starts_at).toISOString().slice(0, 16) : '',
    ends_at: announcement.ends_at ? new Date(announcement.ends_at).toISOString().slice(0, 16) : '',
  };
  showModal.value = true;
  playSound('click');
}

function closeModal() {
  showModal.value = false;
  editingAnnouncement.value = null;
  playSound('click');
}

async function saveAnnouncement() {
  if (!form.value.message) {
    error.value = 'El mensaje es requerido';
    return;
  }

  try {
    saving.value = true;
    error.value = '';

    const params: any = {
      ...form.value,
      message_es: form.value.message_es || undefined,
      link_url: form.value.link_url || undefined,
      link_text: form.value.link_text || undefined,
      starts_at: form.value.starts_at || undefined,
      ends_at: form.value.ends_at || undefined,
    };

    if (editingAnnouncement.value) {
      // Update
      await adminUpdateAnnouncement({
        announcement_id: editingAnnouncement.value.id,
        ...params,
      });
    } else {
      // Create
      await adminCreateAnnouncement(params);
    }

    playSound('success');
    closeModal();
    await loadAnnouncements();
  } catch (e: any) {
    console.error('Error saving announcement:', e);
    error.value = e.message || 'Error al guardar anuncio';
    playSound('error');
  } finally {
    saving.value = false;
  }
}

async function deleteAnnouncement(id: string) {
  if (!confirm('¿Estás seguro de que quieres eliminar este anuncio?')) {
    return;
  }

  try {
    error.value = '';
    await adminDeleteAnnouncement(id);
    playSound('success');
    await loadAnnouncements();
  } catch (e: any) {
    console.error('Error deleting announcement:', e);
    error.value = e.message || 'Error al eliminar anuncio';
    playSound('error');
  }
}

async function toggleActive(announcement: Announcement) {
  try {
    error.value = '';
    await adminUpdateAnnouncement({
      announcement_id: announcement.id,
      is_active: !announcement.is_active,
    });
    playSound('success');
    await loadAnnouncements();
  } catch (e: any) {
    console.error('Error toggling announcement:', e);
    error.value = e.message || 'Error al actualizar anuncio';
    playSound('error');
  }
}

// Quick action: Activar anuncio de actualización
const showUpdateModal = ref(false);
const updateVersion = ref('');
const creatingUpdate = ref(false);

function openUpdateModal() {
  // Auto-generar versión basada en fecha
  const now = new Date();
  updateVersion.value = `v${now.getFullYear()}.${now.getMonth() + 1}.${now.getDate()}`;
  showUpdateModal.value = true;
  playSound('click');
}

function closeUpdateModal() {
  showUpdateModal.value = false;
  updateVersion.value = '';
  playSound('click');
}

async function createUpdateAnnouncement() {
  if (!updateVersion.value) {
    error.value = 'La versión es requerida';
    return;
  }

  try {
    creatingUpdate.value = true;
    error.value = '';

    await adminCreateUpdateAnnouncement(updateVersion.value);

    playSound('success');
    closeUpdateModal();
    await loadAnnouncements();
  } catch (e: any) {
    console.error('Error creating update announcement:', e);
    error.value = e.message || 'Error al crear anuncio de actualización';
    playSound('error');
  } finally {
    creatingUpdate.value = false;
  }
}

// Gift sending
const showGiftModal = ref(false);
const sendingGift = ref(false);
const giftSuccess = ref('');
const giftForm = ref({
  target: '@everyone',
  customTarget: '',
  title: '',
  description: '',
  icon: '🎁',
});

const giftRewards = ref<Array<{ type: string; amount: number; itemId?: string }>>([]);
const newRewardType = ref('gamecoin');
const newRewardAmount = ref<number>(0);

// Boost items para regalo de booster
const boostItems = ref<Array<any>>([]);
const selectedBoostId = ref('');

const rewardTypeOptions = [
  { value: 'gamecoin', label: '💰 GameCoin', unit: 'GC', color: 'text-yellow-400', step: '1', defaultTitle: 'Bonus GameCoin', defaultDesc: 'Disfruta de este bono de GameCoin para tu aventura', defaultIcon: '💰' },
  { value: 'crypto', label: '💎 Landwork (Crypto)', unit: 'Landwork', color: 'text-amber-400', step: '0.0001', defaultTitle: 'Bonus Landwork', defaultDesc: 'Has recibido un bono de Landwork. ¡Úsalo sabiamente!', defaultIcon: '💎' },
  { value: 'energy', label: '⚡ Energía', unit: '', color: 'text-green-400', step: '1', defaultTitle: 'Recarga de Energía', defaultDesc: 'Recarga de energía para mantener tus rigs activos', defaultIcon: '⚡' },
  { value: 'internet', label: '🌐 Internet', unit: '', color: 'text-blue-400', step: '1', defaultTitle: 'Recarga de Internet', defaultDesc: 'Recarga de internet para tus operaciones de minería', defaultIcon: '🌐' },
  { value: 'premium', label: '👑 Premium', unit: 'días', color: 'text-amber-300', step: '1', defaultTitle: 'Premium Gratis', defaultDesc: '¡Disfruta de los beneficios Premium! +50% recompensas, menos fees y más', defaultIcon: '👑' },
  { value: 'booster', label: '🚀 Booster', unit: 'stacks', color: 'text-orange-400', step: '1', defaultTitle: 'Boost de Regalo', defaultDesc: 'Se instalará automáticamente en todos tus rigs', defaultIcon: '🚀' },
];

const giftIconOptions = [
  '🎁', '🎉', '🎊', '💰', '⚡', '🌐', '👑', '🏆', '⭐', '💎', '🔥', '🎮'
];

const currentRewardStep = computed(() => {
  return rewardTypeOptions.find(o => o.value === newRewardType.value)?.step || '1';
});

watch(newRewardType, (val) => {
  const option = rewardTypeOptions.find(o => o.value === val);
  if (!option) return;
  const isDefault = (t: string) => !t || rewardTypeOptions.some(o => o.defaultTitle === t);
  const isDefaultDesc = (d: string) => !d || rewardTypeOptions.some(o => o.defaultDesc === d);
  if (isDefault(giftForm.value.title)) {
    giftForm.value.title = option.defaultTitle;
  }
  if (isDefaultDesc(giftForm.value.description)) {
    giftForm.value.description = option.defaultDesc;
  }
  if (giftForm.value.icon === '🎁' || rewardTypeOptions.some(o => o.defaultIcon === giftForm.value.icon)) {
    giftForm.value.icon = option.defaultIcon;
  }
});

function addReward() {
  if (newRewardAmount.value <= 0) return;
  if (newRewardType.value === 'booster' && !selectedBoostId.value) return;
  const option = rewardTypeOptions.find(o => o.value === newRewardType.value);
  const itemId = newRewardType.value === 'booster' ? selectedBoostId.value : undefined;
  const existing = giftRewards.value.find(r => r.type === newRewardType.value && r.itemId === itemId);
  if (existing) {
    existing.amount = newRewardAmount.value;
  } else {
    giftRewards.value.push({ type: newRewardType.value, amount: newRewardAmount.value, itemId });
  }
  // Auto-fill title, description and icon if empty
  if (option && !giftForm.value.title) {
    giftForm.value.title = option.defaultTitle;
  }
  if (option && !giftForm.value.description) {
    giftForm.value.description = option.defaultDesc;
  }
  if (option && giftForm.value.icon === '🎁') {
    giftForm.value.icon = option.defaultIcon;
  }
  newRewardAmount.value = 0;
  playSound('click');
}

function removeReward(index: number) {
  giftRewards.value.splice(index, 1);
  playSound('click');
}

function getRewardOption(type: string) {
  return rewardTypeOptions.find(o => o.value === type);
}

function openGiftModal() {
  giftForm.value = {
    target: '@everyone',
    customTarget: '',
    title: '',
    description: '',
    icon: '🎁',
  };
  giftRewards.value = [];
  newRewardType.value = 'gamecoin';
  newRewardAmount.value = 0;
  selectedBoostId.value = '';
  giftSuccess.value = '';
  showGiftModal.value = true;
  playSound('click');
  // Cargar boost items si no se han cargado
  if (boostItems.value.length === 0) {
    getBoostItems().then((data: any) => { boostItems.value = data || []; }).catch(() => {});
  }
}

function closeGiftModal() {
  showGiftModal.value = false;
  giftSuccess.value = '';
  playSound('click');
}

async function sendGift() {
  const target = giftForm.value.target === 'specific'
    ? giftForm.value.customTarget.trim()
    : '@everyone';

  if (!target) {
    error.value = 'Debes especificar un jugador o seleccionar @everyone';
    return;
  }

  if (!giftForm.value.title) {
    error.value = 'El título del regalo es requerido';
    return;
  }

  if (giftRewards.value.length === 0) {
    error.value = 'El regalo debe incluir al menos una recompensa';
    return;
  }

  try {
    sendingGift.value = true;
    error.value = '';

    const params: AdminSendGiftParams = {
      target,
      title: giftForm.value.title,
      description: giftForm.value.description || undefined,
      icon: giftForm.value.icon,
    };

    for (const reward of giftRewards.value) {
      switch (reward.type) {
        case 'gamecoin': params.gamecoin = reward.amount; break;
        case 'crypto': params.crypto = reward.amount; break;
        case 'energy': params.energy = reward.amount; break;
        case 'internet': params.internet = reward.amount; break;
        case 'premium':
          params.item_type = 'premium';
          params.item_quantity = reward.amount;
          break;
        case 'booster':
          params.item_type = 'boost';
          params.item_id = reward.itemId;
          params.item_quantity = reward.amount;
          break;
      }
    }

    await adminSendGift(params);
    playSound('success');
    giftSuccess.value = target === '@everyone'
      ? `Regalo enviado a todos los jugadores`
      : `Regalo enviado al jugador ${target}`;
  } catch (e: any) {
    console.error('Error sending gift:', e);
    error.value = e.message || 'Error al enviar regalo';
    playSound('error');
  } finally {
    sendingGift.value = false;
  }
}

// Users management
const showUserDetailModal = ref(false);
const users = ref<any[]>([]);
const loadingUsers = ref(false);
const searchUser = ref('');
const selectedUser = ref<any>(null);
const selectedUserDetail = ref<any>(null);
const loadingUserDetail = ref(false);

// Infinite scroll for blocks
const pendingBlocksToShow = ref(10);
const claimedBlocksToShow = ref(10);
const BLOCKS_PER_PAGE = 10;

function copyUUID(uuid: string) {
  navigator.clipboard.writeText(uuid);
  playSound('click');
}

function openUserDetail(user: any) {
  selectedUser.value = user;
  selectedUserDetail.value = null;
  showUserDetailModal.value = true;
  playSound('click');
  loadUserDetail(user.id);
}

function closeUserDetail() {
  showUserDetailModal.value = false;
  selectedUser.value = null;
  selectedUserDetail.value = null;
  // Reset infinite scroll
  pendingBlocksToShow.value = BLOCKS_PER_PAGE;
  claimedBlocksToShow.value = BLOCKS_PER_PAGE;
  playSound('click');
}

function handlePendingBlocksScroll(event: Event) {
  const target = event.target as HTMLElement;
  const scrollTop = target.scrollTop;
  const scrollHeight = target.scrollHeight;
  const clientHeight = target.clientHeight;

  // Load more when scrolled to 80% of the container
  if (scrollTop + clientHeight >= scrollHeight * 0.8) {
    const totalBlocks = selectedUserDetail.value?.pending_blocks?.blocks?.length || 0;
    if (pendingBlocksToShow.value < totalBlocks) {
      pendingBlocksToShow.value += BLOCKS_PER_PAGE;
    }
  }
}

function handleClaimedBlocksScroll(event: Event) {
  const target = event.target as HTMLElement;
  const scrollTop = target.scrollTop;
  const scrollHeight = target.scrollHeight;
  const clientHeight = target.clientHeight;

  // Load more when scrolled to 80% of the container
  if (scrollTop + clientHeight >= scrollHeight * 0.8) {
    const totalBlocks = selectedUserDetail.value?.claimed_blocks?.length || 0;
    if (claimedBlocksToShow.value < totalBlocks) {
      claimedBlocksToShow.value += BLOCKS_PER_PAGE;
    }
  }
}

async function loadUsers() {
  try {
    loadingUsers.value = true;
    const data = await adminGetPlayers(searchUser.value || undefined, 50, 0);
    users.value = data || [];
  } catch (e: any) {
    console.error('Error loading users:', e);
    error.value = e.message || 'Error al cargar usuarios';
    playSound('error');
  } finally {
    loadingUsers.value = false;
  }
}

async function loadUserDetail(userId: string) {
  try {
    loadingUserDetail.value = true;
    const response = await adminGetPlayerDetail(userId);

    // La respuesta viene con { success: true, player: {...} }
    const detail = response?.player || response;

    selectedUserDetail.value = detail;
  } catch (e: any) {
    console.error('Error loading user detail:', e);
    playSound('error');
  } finally {
    loadingUserDetail.value = false;
  }
}

function formatDate(dateString: string) {
  return new Date(dateString).toLocaleString('es-ES', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit'
  });
}

onMounted(async () => {
  // Verificar acceso admin
  if (!isAdmin.value) {
    router.push('/profile');
    return;
  }

  await loadAnnouncements();
  await loadUsers();
});
</script>

<template>
  <div class="container mx-auto px-4 py-6 max-w-6xl">
    <!-- Header -->
    <div class="mb-6">
      <div class="flex items-center justify-between mb-2">
        <div>
          <h1 class="text-3xl font-bold gradient-text mb-1">Panel de Administrador</h1>
          <p class="text-text-muted">Gestión de anuncios del sistema</p>
        </div>
        <button
          @click="router.push('/profile')"
          class="px-4 py-2 rounded-lg bg-bg-tertiary hover:bg-bg-tertiary/80 transition-colors"
        >
          ← Volver al Perfil
        </button>
      </div>
    </div>

    <!-- Error Global -->
    <div
      v-if="error"
      class="mb-4 p-4 bg-status-danger/10 border border-status-danger/30 rounded-lg text-status-danger"
    >
      {{ error }}
    </div>

    <!-- Action Buttons -->
    <div class="mb-6 flex flex-wrap gap-3">
      <button
        @click="openCreateModal"
        class="px-6 py-3 rounded-xl font-medium bg-gradient-primary hover:opacity-90 transition-opacity flex items-center gap-2"
      >
        <span class="text-xl">➕</span>
        Crear Nuevo Anuncio
      </button>

      <button
        @click="openUpdateModal"
        class="px-6 py-3 rounded-xl font-medium bg-blue-600 hover:bg-blue-700 transition-colors flex items-center gap-2 border border-blue-400"
      >
        <span class="text-xl">🔄</span>
        Activar Actualización
      </button>

      <button
        @click="openGiftModal"
        class="px-6 py-3 rounded-xl font-medium bg-yellow-600 hover:bg-yellow-700 transition-colors flex items-center gap-2 border border-yellow-400"
      >
        <span class="text-xl">🎁</span>
        Enviar Regalo
      </button>
    </div>

    <!-- Users Management Section -->
    <div class="mb-6">
      <div class="flex items-center justify-between mb-4">
        <div>
          <h2 class="text-2xl font-bold gradient-text">👥 Gestión de Usuarios</h2>
          <p class="text-text-muted text-sm">{{ users.length }} usuarios cargados</p>
        </div>
      </div>

      <!-- Search -->
      <div class="mb-4 flex gap-2">
        <input
          v-model="searchUser"
          @keyup.enter="loadUsers"
          type="text"
          placeholder="Buscar por username, email o ID..."
          class="flex-1 px-4 py-2 bg-bg-secondary border border-border rounded-lg focus:border-amber-400 focus:outline-none"
        />
        <button
          @click="loadUsers"
          :disabled="loadingUsers"
          class="px-6 py-2 rounded-lg font-medium bg-amber-600 hover:bg-amber-700 transition-colors disabled:opacity-50 flex items-center gap-2"
        >
          {{ loadingUsers ? '⏳' : '🔍' }} {{ loadingUsers ? 'Buscando...' : 'Buscar' }}
        </button>
      </div>

      <!-- Users Table -->
      <div v-if="loadingUsers" class="flex justify-center py-12">
        <div class="animate-spin w-12 h-12 border-4 border-amber-400 border-t-transparent rounded-full"></div>
      </div>

      <div v-else-if="users.length === 0" class="text-center py-12 text-text-muted card">
        <div class="text-6xl mb-4">👤</div>
        <p class="text-lg">No se encontraron usuarios</p>
      </div>

      <div v-else class="overflow-x-auto">
        <table class="w-full">
          <thead>
            <tr class="border-b border-border">
              <th class="px-4 py-3 text-left text-sm font-semibold text-text-secondary">Usuario</th>
              <th class="px-4 py-3 text-left text-sm font-semibold text-text-secondary">Email</th>
              <th class="px-4 py-3 text-left text-sm font-semibold text-text-secondary">Rol</th>
              <th class="px-4 py-3 text-right text-sm font-semibold text-text-secondary">GameCoin</th>
              <th class="px-4 py-3 text-right text-sm font-semibold text-text-secondary">Landwork</th>
              <th class="px-4 py-3 text-right text-sm font-semibold text-text-secondary">Rigs</th>
              <th class="px-4 py-3 text-right text-sm font-semibold text-text-secondary">Hashrate</th>
              <th class="px-4 py-3 text-center text-sm font-semibold text-text-secondary">Acciones</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="user in users"
              :key="user.id"
              class="border-b border-border hover:bg-bg-tertiary/30 transition-colors"
            >
              <td class="px-4 py-3">
                <div class="flex items-center gap-2">
                  <span class="font-medium">{{ user.username }}</span>
                  <span
                    v-if="user.is_premium"
                    class="text-yellow-400"
                    title="Premium"
                  >
                    👑
                  </span>
                </div>
              </td>
              <td class="px-4 py-3 text-text-secondary text-sm">{{ user.email }}</td>
              <td class="px-4 py-3">
                <span
                  v-if="user.role === 'admin'"
                  class="px-2 py-0.5 rounded text-xs font-medium bg-red-500/20 text-red-400"
                >
                  ADMIN
                </span>
                <span v-else class="text-text-muted text-sm">user</span>
              </td>
              <td class="px-4 py-3 text-right font-mono text-sm">{{ Number(user.gamecoin_balance).toLocaleString() }}</td>
              <td class="px-4 py-3 text-right font-mono text-sm text-accent-primary">{{ Number(user.crypto_balance).toFixed(4) }}</td>
              <td class="px-4 py-3 text-right text-sm">
                <span class="text-status-success">{{ user.active_rigs_count }}</span>
                <span class="text-text-muted">/{{ user.rigs_count }}</span>
              </td>
              <td class="px-4 py-3 text-right font-mono text-sm">{{ Number(user.total_hashrate || 0).toLocaleString() }} H/s</td>
              <td class="px-4 py-3 text-center">
                <div class="flex items-center justify-center gap-1.5">
                  <button
                    @click="copyUUID(user.id)"
                    class="px-2 py-1.5 rounded-lg bg-bg-tertiary hover:bg-bg-tertiary/80 transition-colors text-sm"
                    title="Copiar UUID"
                  >
                    📋
                  </button>
                  <button
                    @click="openUserDetail(user)"
                    class="px-3 py-1.5 rounded-lg font-medium bg-amber-600 hover:bg-amber-700 transition-colors text-sm"
                  >
                    Ver Detalles
                  </button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <!-- Announcements Section -->
    <div class="mb-6">
      <h2 class="text-2xl font-bold gradient-text mb-4">📢 Gestión de Anuncios</h2>

      <!-- Loading -->
      <div v-if="loading" class="flex justify-center py-12">
        <div class="animate-spin w-12 h-12 border-4 border-accent-primary border-t-transparent rounded-full"></div>
      </div>

      <!-- Announcements List -->
      <div v-else class="space-y-3">
      <div
        v-for="announcement in announcements"
        :key="announcement.id"
        class="card p-4 hover:border-accent-primary/50 transition-colors"
      >
        <div class="flex items-start gap-4">
          <!-- Icon -->
          <div class="text-3xl">{{ announcement.icon }}</div>

          <!-- Content -->
          <div class="flex-1">
            <div class="flex items-start justify-between mb-2">
              <div class="flex items-center gap-2 flex-wrap">
                <span
                  class="px-2 py-0.5 rounded text-xs font-medium"
                  :class="{
                    'bg-accent-primary/20 text-accent-primary': announcement.type === 'info',
                    'bg-status-warning/20 text-status-warning': announcement.type === 'warning',
                    'bg-status-success/20 text-status-success': announcement.type === 'success',
                    'bg-status-danger/20 text-status-danger': announcement.type === 'error',
                    'bg-amber-500/20 text-amber-400': announcement.type === 'maintenance',
                    'bg-blue-500/20 text-blue-400': announcement.type === 'update',
                  }"
                >
                  {{ announcement.type }}
                </span>
                <span class="px-2 py-0.5 rounded text-xs font-medium bg-bg-tertiary">
                  Priority: {{ announcement.priority }}
                </span>
                <button
                  @click="toggleActive(announcement)"
                  class="px-2 py-0.5 rounded text-xs font-medium transition-colors"
                  :class="announcement.is_active ? 'bg-status-success/20 text-status-success' : 'bg-bg-tertiary text-text-muted'"
                >
                  {{ announcement.is_active ? '✓ Activo' : '✗ Inactivo' }}
                </button>
              </div>

              <!-- Actions -->
              <div class="flex items-center gap-2">
                <button
                  @click="openEditModal(announcement)"
                  class="p-2 rounded-lg bg-accent-primary/20 hover:bg-accent-primary/30 text-accent-primary transition-colors"
                  title="Editar"
                >
                  ✏️
                </button>
                <button
                  @click="deleteAnnouncement(announcement.id)"
                  class="p-2 rounded-lg bg-status-danger/20 hover:bg-status-danger/30 text-status-danger transition-colors"
                  title="Eliminar"
                >
                  🗑️
                </button>
              </div>
            </div>

            <!-- Messages -->
            <div class="space-y-1 mb-2">
              <p class="font-medium">
                <span class="text-xs text-text-muted">EN:</span> {{ announcement.message }}
              </p>
              <p v-if="announcement.message_es" class="text-text-secondary">
                <span class="text-xs text-text-muted">ES:</span> {{ announcement.message_es }}
              </p>
            </div>

            <!-- Link -->
            <div v-if="announcement.link_url" class="mb-2 text-sm">
              <a :href="announcement.link_url" target="_blank" class="text-accent-primary hover:underline">
                {{ announcement.link_text || announcement.link_url }}
              </a>
            </div>

            <!-- Dates -->
            <div class="flex items-center gap-4 text-xs text-text-muted">
              <span>📅 Inicia: {{ new Date(announcement.starts_at).toLocaleString() }}</span>
              <span v-if="announcement.ends_at">🏁 Termina: {{ new Date(announcement.ends_at).toLocaleString() }}</span>
              <span v-else>🏁 Sin fecha fin</span>
            </div>
          </div>
        </div>
      </div>

      <!-- Empty State -->
      <div v-if="announcements.length === 0" class="text-center py-12 text-text-muted card">
        <div class="text-6xl mb-4">📢</div>
        <p class="text-lg">No hay anuncios creados</p>
        <p class="text-sm">Crea tu primer anuncio usando el botón de arriba</p>
      </div>
      </div>
    </div>

    <!-- Create/Edit Modal -->
    <Teleport to="body">
      <div
        v-if="showModal"
        class="fixed inset-0 z-50 flex items-center justify-center p-4"
      >
        <div class="absolute inset-0 bg-black/70 backdrop-blur-sm" @click="closeModal"></div>

        <div class="relative bg-bg-secondary rounded-xl p-6 max-w-2xl w-full border border-border animate-fade-in max-h-[90vh] overflow-y-auto">
          <h3 class="text-xl font-bold mb-4">
            {{ editingAnnouncement ? 'Editar Anuncio' : 'Crear Nuevo Anuncio' }}
          </h3>

          <div class="space-y-4">
            <!-- Message (EN) -->
            <div>
              <label class="block text-sm font-medium mb-2">Mensaje (Inglés) *</label>
              <textarea
                v-model="form.message"
                rows="3"
                class="w-full px-3 py-2 bg-bg-primary border border-border rounded-lg focus:border-accent-primary focus:outline-none"
                placeholder="Enter announcement message..."
              ></textarea>
            </div>

            <!-- Message (ES) -->
            <div>
              <label class="block text-sm font-medium mb-2">Mensaje (Español)</label>
              <textarea
                v-model="form.message_es"
                rows="3"
                class="w-full px-3 py-2 bg-bg-primary border border-border rounded-lg focus:border-accent-primary focus:outline-none"
                placeholder="Mensaje del anuncio..."
              ></textarea>
            </div>

            <!-- Type & Icon -->
            <div class="grid grid-cols-2 gap-4">
              <div>
                <label class="block text-sm font-medium mb-2">Tipo</label>
                <select
                  v-model="form.type"
                  class="w-full px-3 py-2 bg-bg-primary border border-border rounded-lg focus:border-accent-primary focus:outline-none"
                >
                  <option v-for="option in typeOptions" :key="option.value" :value="option.value">
                    {{ option.label }}
                  </option>
                </select>
              </div>

              <div>
                <label class="block text-sm font-medium mb-2">Icono</label>
                <div class="flex items-center gap-2">
                  <input
                    v-model="form.icon"
                    class="flex-1 px-3 py-2 bg-bg-primary border border-border rounded-lg focus:border-accent-primary focus:outline-none"
                  />
                  <div class="text-2xl">{{ form.icon }}</div>
                </div>
                <div class="flex flex-wrap gap-1 mt-2">
                  <button
                    v-for="icon in iconOptions"
                    :key="icon"
                    @click="form.icon = icon"
                    class="w-8 h-8 text-xl hover:bg-bg-tertiary rounded transition-colors"
                  >
                    {{ icon }}
                  </button>
                </div>
              </div>
            </div>

            <!-- Link URL & Text -->
            <div class="grid grid-cols-2 gap-4">
              <div>
                <label class="block text-sm font-medium mb-2">Link URL</label>
                <input
                  v-model="form.link_url"
                  type="url"
                  class="w-full px-3 py-2 bg-bg-primary border border-border rounded-lg focus:border-accent-primary focus:outline-none"
                  placeholder="https://..."
                />
              </div>

              <div>
                <label class="block text-sm font-medium mb-2">Link Text</label>
                <input
                  v-model="form.link_text"
                  class="w-full px-3 py-2 bg-bg-primary border border-border rounded-lg focus:border-accent-primary focus:outline-none"
                  placeholder="Learn more"
                />
              </div>
            </div>

            <!-- Priority & Active -->
            <div class="grid grid-cols-2 gap-4">
              <div>
                <label class="block text-sm font-medium mb-2">Prioridad</label>
                <input
                  v-model.number="form.priority"
                  type="number"
                  min="0"
                  class="w-full px-3 py-2 bg-bg-primary border border-border rounded-lg focus:border-accent-primary focus:outline-none"
                />
                <p class="text-xs text-text-muted mt-1">Mayor número = mayor prioridad</p>
              </div>

              <div>
                <label class="block text-sm font-medium mb-2">Estado</label>
                <label class="flex items-center gap-2 cursor-pointer">
                  <input
                    v-model="form.is_active"
                    type="checkbox"
                    class="w-5 h-5"
                  />
                  <span>Activo</span>
                </label>
              </div>
            </div>

            <!-- Dates -->
            <div class="grid grid-cols-2 gap-4">
              <div>
                <label class="block text-sm font-medium mb-2">Fecha de Inicio</label>
                <input
                  v-model="form.starts_at"
                  type="datetime-local"
                  class="w-full px-3 py-2 bg-bg-primary border border-border rounded-lg focus:border-accent-primary focus:outline-none"
                />
              </div>

              <div>
                <label class="block text-sm font-medium mb-2">Fecha de Fin (opcional)</label>
                <input
                  v-model="form.ends_at"
                  type="datetime-local"
                  class="w-full px-3 py-2 bg-bg-primary border border-border rounded-lg focus:border-accent-primary focus:outline-none"
                />
              </div>
            </div>
          </div>

          <!-- Modal Actions -->
          <div class="flex gap-3 mt-6">
            <button
              @click="closeModal"
              :disabled="saving"
              class="flex-1 py-2.5 rounded-lg font-medium bg-bg-tertiary hover:bg-bg-tertiary/80 transition-colors disabled:opacity-50"
            >
              Cancelar
            </button>
            <button
              @click="saveAnnouncement"
              :disabled="saving || !form.message"
              class="flex-1 py-2.5 rounded-lg font-medium bg-gradient-primary hover:opacity-90 transition-opacity disabled:opacity-50"
            >
              {{ saving ? 'Guardando...' : editingAnnouncement ? 'Actualizar' : 'Crear' }}
            </button>
          </div>
        </div>
      </div>
    </Teleport>

    <!-- Update Announcement Modal (Quick Action) -->
    <Teleport to="body">
      <div
        v-if="showUpdateModal"
        class="fixed inset-0 z-50 flex items-center justify-center p-4"
      >
        <div class="absolute inset-0 bg-black/70 backdrop-blur-sm" @click="closeUpdateModal"></div>

        <div class="relative bg-bg-secondary rounded-xl p-6 max-w-md w-full border border-blue-400 animate-fade-in">
          <div class="text-center mb-6">
            <div class="text-5xl mb-3">🔄</div>
            <h3 class="text-xl font-bold mb-2">Activar Anuncio de Actualización</h3>
            <p class="text-sm text-text-muted">
              Esto creará un anuncio que notificará a todos los usuarios que deben actualizar la página.
            </p>
          </div>

          <div class="space-y-4">
            <!-- Version Input -->
            <div>
              <label class="block text-sm font-medium mb-2">Versión *</label>
              <input
                v-model="updateVersion"
                type="text"
                class="w-full px-3 py-2 bg-bg-primary border border-border rounded-lg focus:border-blue-400 focus:outline-none"
                placeholder="v2024.2.11"
              />
              <p class="text-xs text-text-muted mt-1">
                Los mensajes en inglés y español se generarán automáticamente
              </p>
            </div>

            <!-- Preview -->
            <div class="p-3 bg-bg-primary rounded-lg border border-blue-400/30">
              <p class="text-xs text-text-muted mb-1">Vista previa:</p>
              <p class="text-sm">
                <strong>EN:</strong> A new version ({{ updateVersion || 'v2024.2.11' }}) is available! Please refresh to update.
              </p>
              <p class="text-sm mt-1">
                <strong>ES:</strong> Una nueva versión ({{ updateVersion || 'v2024.2.11' }}) está disponible! Por favor actualiza la página.
              </p>
            </div>

            <!-- Info -->
            <div class="p-3 bg-blue-500/10 rounded-lg border border-blue-400/30">
              <p class="text-xs text-blue-400">
                ℹ️ Se desactivarán automáticamente otros anuncios de actualización y se creará uno nuevo con máxima prioridad (999).
              </p>
            </div>
          </div>

          <!-- Modal Actions -->
          <div class="flex gap-3 mt-6">
            <button
              @click="closeUpdateModal"
              :disabled="creatingUpdate"
              class="flex-1 py-2.5 rounded-lg font-medium bg-bg-tertiary hover:bg-bg-tertiary/80 transition-colors disabled:opacity-50"
            >
              Cancelar
            </button>
            <button
              @click="createUpdateAnnouncement"
              :disabled="creatingUpdate || !updateVersion"
              class="flex-1 py-2.5 rounded-lg font-medium bg-blue-600 hover:bg-blue-700 transition-colors disabled:opacity-50"
            >
              {{ creatingUpdate ? 'Activando...' : '✓ Activar' }}
            </button>
          </div>
        </div>
      </div>
    </Teleport>

    <!-- Send Gift Modal -->
    <Teleport to="body">
      <div
        v-if="showGiftModal"
        class="fixed inset-0 z-50 flex items-center justify-center p-4"
      >
        <div class="absolute inset-0 bg-black/70 backdrop-blur-sm" @click="closeGiftModal"></div>

        <div class="relative bg-bg-secondary rounded-xl p-5 max-w-lg w-full border border-yellow-400 animate-fade-in max-h-[90vh] overflow-y-auto">
          <div class="flex items-center gap-3 mb-4">
            <span class="text-2xl">🎁</span>
            <div>
              <h3 class="text-base font-bold leading-tight">Enviar Regalo</h3>
              <p class="text-xs text-text-muted">
                Envía regalos a todos los jugadores o a uno específico.
              </p>
            </div>
          </div>

          <!-- Success message -->
          <div v-if="giftSuccess" class="mb-4 p-4 bg-status-success/10 border border-status-success/30 rounded-lg text-status-success text-center">
            {{ giftSuccess }}
          </div>

          <div class="space-y-4">
            <!-- Target -->
            <div>
              <label class="block text-sm font-medium mb-2">Destinatario *</label>
              <div class="flex gap-2 mb-2">
                <button
                  @click="giftForm.target = '@everyone'"
                  class="flex-1 py-2 px-3 rounded-lg text-sm font-medium transition-colors border"
                  :class="giftForm.target === '@everyone' ? 'bg-yellow-600 border-yellow-400 text-white' : 'bg-bg-tertiary border-border hover:bg-bg-tertiary/80'"
                >
                  👥 Todos los jugadores
                </button>
                <button
                  @click="giftForm.target = 'specific'"
                  class="flex-1 py-2 px-3 rounded-lg text-sm font-medium transition-colors border"
                  :class="giftForm.target === 'specific' ? 'bg-yellow-600 border-yellow-400 text-white' : 'bg-bg-tertiary border-border hover:bg-bg-tertiary/80'"
                >
                  👤 Jugador específico
                </button>
              </div>
              <input
                v-if="giftForm.target === 'specific'"
                v-model="giftForm.customTarget"
                type="text"
                class="w-full px-3 py-2 bg-bg-primary border border-border rounded-lg focus:border-yellow-400 focus:outline-none"
                placeholder="UUID del jugador..."
              />
            </div>

            <!-- Rewards -->
            <div>
              <label class="block text-sm font-medium mb-2">Recompensas *</label>

              <!-- Added rewards list -->
              <div v-if="giftRewards.length > 0" class="flex flex-wrap gap-2 mb-3">
                <span
                  v-for="(reward, idx) in giftRewards"
                  :key="idx"
                  class="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-sm font-medium border"
                  :class="getRewardOption(reward.type)?.color"
                  style="background: rgba(255,255,255,0.05); border-color: rgba(255,255,255,0.1);"
                >
                  {{ getRewardOption(reward.type)?.label }}:
                  <template v-if="reward.itemId">{{ boostItems.find((b: any) => b.id === reward.itemId)?.name || reward.itemId }} x</template>
                  <strong>{{ reward.amount }}</strong>
                  <span class="text-xs opacity-70">{{ getRewardOption(reward.type)?.unit }}</span>
                  <button
                    @click="removeReward(idx)"
                    class="ml-1 text-status-danger hover:text-red-300 text-xs"
                  >✕</button>
                </span>
              </div>
              <div v-else class="mb-3 text-xs text-text-muted">
                Agrega al menos una recompensa
              </div>

              <!-- Add reward row -->
              <div class="flex flex-col gap-2">
                <div class="flex gap-2">
                  <select
                    v-model="newRewardType"
                    class="flex-1 px-3 py-2 bg-bg-primary border border-border rounded-lg focus:border-yellow-400 focus:outline-none text-sm"
                  >
                    <option v-for="opt in rewardTypeOptions" :key="opt.value" :value="opt.value">
                      {{ opt.label }}
                    </option>
                  </select>
                  <input
                    v-model.number="newRewardAmount"
                    type="number"
                    min="0"
                    :step="currentRewardStep"
                    :placeholder="newRewardType === 'premium' ? 'Días' : newRewardType === 'booster' ? 'Stacks' : 'Cantidad'"
                    class="w-28 px-3 py-2 bg-bg-primary border border-border rounded-lg focus:border-yellow-400 focus:outline-none text-sm"
                    @keyup.enter="addReward"
                  />
                  <button
                    @click="addReward"
                    :disabled="!newRewardAmount || newRewardAmount <= 0 || (newRewardType === 'booster' && !selectedBoostId)"
                    class="px-4 py-2 rounded-lg font-medium bg-yellow-600 hover:bg-yellow-700 transition-colors disabled:opacity-30 text-sm"
                  >
                    +
                  </button>
                </div>
                <!-- Boost item selector -->
                <select
                  v-if="newRewardType === 'booster'"
                  v-model="selectedBoostId"
                  class="w-full px-3 py-2 bg-bg-primary border border-orange-400/50 rounded-lg focus:border-orange-400 focus:outline-none text-sm"
                >
                  <option value="" disabled>Selecciona un booster...</option>
                  <option v-for="b in boostItems" :key="b.id" :value="b.id">
                    {{ b.name }} ({{ b.boost_type }}, +{{ b.effect_value }}%, {{ b.duration_minutes }}min)
                  </option>
                </select>
              </div>
            </div>

            <!-- Title -->
            <div>
              <label class="block text-sm font-medium mb-2">Título *</label>
              <input
                v-model="giftForm.title"
                type="text"
                class="w-full px-3 py-2 bg-bg-primary border border-border rounded-lg focus:border-yellow-400 focus:outline-none"
                placeholder="Ej: Reward, Compensation, Event Prize..."
              />
            </div>

            <!-- Description -->
            <div>
              <label class="block text-sm font-medium mb-2">Descripción</label>
              <input
                v-model="giftForm.description"
                type="text"
                class="w-full px-3 py-2 bg-bg-primary border border-border rounded-lg focus:border-yellow-400 focus:outline-none"
                placeholder="Descripción opcional..."
              />
            </div>

            <!-- Icon -->
            <div>
              <label class="block text-sm font-medium mb-2">Icono</label>
              <div class="flex items-center gap-2">
                <div class="text-2xl w-10 text-center">{{ giftForm.icon }}</div>
                <div class="flex flex-wrap gap-1">
                  <button
                    v-for="icon in giftIconOptions"
                    :key="icon"
                    @click="giftForm.icon = icon"
                    class="w-8 h-8 text-xl hover:bg-bg-tertiary rounded transition-colors"
                    :class="giftForm.icon === icon ? 'bg-yellow-600/30 ring-1 ring-yellow-400' : ''"
                  >
                    {{ icon }}
                  </button>
                </div>
              </div>
            </div>

            <!-- Preview -->
            <div class="p-3 bg-bg-primary rounded-lg border border-yellow-400/30">
              <p class="text-xs text-text-muted mb-2">Vista previa:</p>
              <div class="flex items-center gap-3">
                <span class="text-3xl">{{ giftForm.icon }}</span>
                <div>
                  <p class="font-medium">{{ giftForm.title || 'Sin título' }}</p>
                  <div class="flex flex-wrap gap-2 text-xs mt-1">
                    <span
                      v-for="(reward, idx) in giftRewards"
                      :key="idx"
                      :class="getRewardOption(reward.type)?.color"
                    >
                      {{ getRewardOption(reward.type)?.label.split(' ')[0] }} {{ reward.amount }} {{ getRewardOption(reward.type)?.unit }}
                    </span>
                    <span v-if="giftRewards.length === 0" class="text-text-muted">Sin recompensas</span>
                  </div>
                </div>
              </div>
              <p class="text-xs text-text-muted mt-2">
                📤 {{ giftForm.target === '@everyone' ? 'Todos los jugadores' : giftForm.customTarget || 'Jugador específico' }}
              </p>
            </div>
          </div>

          <!-- Modal Actions -->
          <div class="flex gap-3 mt-6">
            <button
              @click="closeGiftModal"
              :disabled="sendingGift"
              class="flex-1 py-2.5 rounded-lg font-medium bg-bg-tertiary hover:bg-bg-tertiary/80 transition-colors disabled:opacity-50"
            >
              Cancelar
            </button>
            <button
              @click="sendGift"
              :disabled="sendingGift || !giftForm.title || giftRewards.length === 0"
              class="flex-1 py-2.5 rounded-lg font-medium bg-yellow-600 hover:bg-yellow-700 transition-colors disabled:opacity-50"
            >
              {{ sendingGift ? 'Enviando...' : '🎁 Enviar Regalo' }}
            </button>
          </div>
        </div>
      </div>
    </Teleport>

    <!-- User Detail Modal -->
    <Teleport to="body">
      <div
        v-if="showUserDetailModal"
        class="fixed inset-0 z-50 flex items-center justify-center p-4"
      >
        <div class="absolute inset-0 bg-black/70 backdrop-blur-sm" @click="closeUserDetail"></div>

        <div class="relative bg-bg-secondary rounded-xl p-5 max-w-3xl w-full border border-amber-400 animate-fade-in max-h-[85vh] flex flex-col">
          <!-- Fixed Header -->
          <div class="flex items-center justify-between mb-4 flex-shrink-0">
            <div>
              <h3 class="text-2xl font-bold flex items-center gap-2">
                <span class="text-2xl">👤</span>
                {{ selectedUser?.username }}
              </h3>
              <p class="text-sm text-text-muted">{{ selectedUser?.email }}</p>
            </div>
            <button
              @click="closeUserDetail"
              class="p-2 rounded-lg hover:bg-bg-tertiary transition-colors text-xl"
            >
              ✕
            </button>
          </div>

          <!-- Scrollable Content -->
          <div class="flex-1 overflow-y-auto pr-2">
            <!-- Loading State -->
            <div v-if="loadingUserDetail" class="text-center py-12">
              <div class="animate-spin w-12 h-12 border-4 border-amber-400 border-t-transparent rounded-full mx-auto"></div>
              <p class="text-text-muted mt-4">Cargando detalles...</p>
            </div>

            <!-- User Detail Content -->
            <div v-else-if="selectedUserDetail" class="space-y-4">
            <!-- Basic Info Card -->
            <div class="card p-3">
              <h4 class="text-base font-semibold mb-2 text-accent-primary">📊 Información Básica</h4>
              <div class="grid grid-cols-2 md:grid-cols-3 gap-3 text-sm">
                <div>
                  <span class="text-text-muted block text-xs">ID</span>
                  <p class="font-mono text-xs">{{ selectedUser.id.substring(0, 8) }}...</p>
                </div>
                <div>
                  <span class="text-text-muted block text-xs">GameCoin Balance</span>
                  <p class="font-medium">{{ Number(selectedUser.gamecoin_balance).toLocaleString('en-US', { minimumFractionDigits: 0, maximumFractionDigits: 2 }) }}</p>
                </div>
                <div>
                  <span class="text-text-muted block text-xs">Landwork Balance</span>
                  <p class="font-medium text-accent-primary">
                    {{ Number(selectedUser.crypto_balance).toLocaleString('en-US', { minimumFractionDigits: 4, maximumFractionDigits: 4 }) }}
                    <span v-if="blcValueInRon > 0" class="text-text-muted text-xs font-normal">(~{{ blcValueInRon.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 4 }) }} RON)</span>
                  </p>
                </div>
                <div>
                  <span class="text-text-muted block text-xs">RON Balance</span>
                  <p class="font-medium">{{ Number(selectedUser.ron_balance || 0).toLocaleString('en-US', { minimumFractionDigits: 4, maximumFractionDigits: 4 }) }}</p>
                </div>
                <div>
                  <span class="text-text-muted block text-xs">RON Depositado</span>
                  <p class="font-medium text-status-success">{{ Number(selectedUserDetail.ron_movements?.total_deposited || 0).toLocaleString('en-US', { minimumFractionDigits: 4, maximumFractionDigits: 4 }) }}</p>
                </div>
                <div>
                  <span class="text-text-muted block text-xs">RON Retirado</span>
                  <p class="font-medium text-amber-400">{{ Number(selectedUserDetail.ron_movements?.total_withdrawn || 0).toLocaleString('en-US', { minimumFractionDigits: 4, maximumFractionDigits: 4 }) }}</p>
                </div>
                <div>
                  <span class="text-text-muted block text-xs">Reputación</span>
                  <p class="font-medium">{{ Number(selectedUser.reputation_score || 0).toLocaleString('en-US') }}</p>
                </div>
                <div>
                  <span class="text-text-muted block text-xs">Hashrate Total</span>
                  <p class="font-medium">{{ Number(selectedUser.total_hashrate || 0).toLocaleString('en-US') }} H/s</p>
                </div>
                <div>
                  <span class="text-text-muted block text-xs">Energía</span>
                  <p class="font-medium">{{ selectedUserDetail.energy }}/{{ selectedUserDetail.max_energy }}</p>
                </div>
                <div>
                  <span class="text-text-muted block text-xs">Internet</span>
                  <p class="font-medium">{{ selectedUserDetail.internet }}/{{ selectedUserDetail.max_internet }}</p>
                </div>
                <div>
                  <span class="text-text-muted block text-xs">Código Referido</span>
                  <p class="font-medium">{{ selectedUser.referral_code || 'N/A' }}</p>
                </div>
                <div>
                  <span class="text-text-muted block text-xs">Referidos</span>
                  <p class="font-medium">{{ selectedUser.referrals_count || 0 }}</p>
                </div>
                <div>
                  <span class="text-text-muted block text-xs">Bloques Minados</span>
                  <p class="font-medium">{{ selectedUser.blocks_mined || 0 }}</p>
                </div>
                <div v-if="selectedUser.is_premium && selectedUser.premium_until">
                  <span class="text-text-muted block text-xs">Premium hasta</span>
                  <p class="font-medium text-yellow-400 text-xs">{{ formatDate(selectedUser.premium_until) }}</p>
                </div>
              </div>
            </div>

            <!-- Rigs Section -->
            <div class="card p-3">
              <h4 class="text-base font-semibold mb-2 text-accent-primary">
                🖥️ Rigs
                <span class="text-status-success">{{ activeRigsCount }}</span>
                <span class="text-text-muted">/{{ selectedUserDetail.rigs ? selectedUserDetail.rigs.length : 0 }}</span>
              </h4>
              <div v-if="selectedUserDetail.rigs && selectedUserDetail.rigs.length > 0" class="max-h-96 overflow-y-auto pr-2 space-y-3">
                <div v-for="rig in selectedUserDetail.rigs" :key="rig.id" class="bg-bg-tertiary border border-border rounded-lg p-3">
                  <div class="flex justify-between items-start mb-2">
                    <div>
                      <p class="font-bold text-sm">{{ rig.rig_name }} <span class="text-text-muted text-xs">Tier {{ rig.tier }}</span></p>
                      <p class="text-text-muted text-xs">{{ Number(rig.hashrate).toLocaleString('en-US') }} H/s</p>
                    </div>
                    <span :class="rig.is_active ? 'bg-green-500/20 text-green-400' : 'bg-gray-500/20 text-gray-400'" class="px-2 py-1 rounded text-sm font-medium">
                      {{ rig.is_active ? '✓ Activo' : '✗ Inactivo' }}
                    </span>
                  </div>
                  <div class="grid grid-cols-3 gap-2 mb-2 text-sm">
                    <div>
                      <span class="text-text-muted">Condición:</span> {{ rig.condition }}/{{ rig.max_condition }}
                    </div>
                    <div>
                      <span class="text-text-muted">Temperatura:</span> {{ rig.temperature }}°C
                    </div>
                    <div>
                      <span class="text-text-muted">Reparaciones:</span> {{ rig.times_repaired }}
                    </div>
                    <div>
                      <span class="text-text-muted">Hashrate:</span> Lv{{ rig.hashrate_level }}
                    </div>
                    <div>
                      <span class="text-text-muted">Eficiencia:</span> Lv{{ rig.efficiency_level }}
                    </div>
                    <div>
                      <span class="text-text-muted">Thermal:</span> Lv{{ rig.thermal_level }}
                    </div>
                  </div>
                  <div v-if="rig.cooling_installed && rig.cooling_installed.length > 0" class="mb-2">
                    <p class="text-xs text-text-muted mb-1">Refrigeración:</p>
                    <div class="flex flex-wrap gap-1">
                      <span v-for="cool in rig.cooling_installed" :key="cool.id" class="bg-blue-500/20 text-blue-300 px-2 py-1 rounded text-sm">
                        ❄️ {{ cool.cooling_name }} (-{{ cool.cooling_power }}°C)
                      </span>
                    </div>
                  </div>
                  <div v-if="rig.boosts_installed && rig.boosts_installed.length > 0">
                    <p class="text-xs text-text-muted mb-1">Boosts:</p>
                    <div class="flex flex-wrap gap-1">
                      <span v-for="boost in rig.boosts_installed" :key="boost.id" class="bg-amber-500/20 text-amber-300 px-2 py-1 rounded text-sm">
                        ⚡ {{ boost.boost_name }}
                      </span>
                    </div>
                  </div>
                </div>
              </div>
              <p v-else class="text-text-muted text-center py-4">No tiene rigs</p>
            </div>

            <!-- Crypto Purchases Section -->
            <div v-if="selectedUserDetail.crypto_purchases && selectedUserDetail.crypto_purchases.length > 0" class="card p-3">
              <h4 class="text-base font-semibold mb-2 text-accent-primary">💰 Compras de Criptomonedas ({{ selectedUserDetail.crypto_purchases.length }})</h4>
              <div class="space-y-2">
                <div v-for="purchase in selectedUserDetail.crypto_purchases" :key="purchase.id" class="bg-bg-tertiary border border-border rounded-lg p-3">
                  <div class="flex justify-between items-start">
                    <div>
                      <p class="font-semibold text-sm">{{ purchase.package_name || 'Package' }}</p>
                      <p class="text-text-muted text-xs">{{ Number(purchase.crypto_amount).toLocaleString('en-US', { minimumFractionDigits: 4, maximumFractionDigits: 4 }) }} RON</p>
                      <p class="text-text-muted text-xs">{{ formatDate(purchase.purchased_at) }}</p>
                    </div>
                    <span :class="{
                      'bg-green-500/20 text-green-400': purchase.status === 'completed',
                      'bg-yellow-500/20 text-yellow-400': purchase.status === 'pending',
                      'bg-red-500/20 text-red-400': purchase.status === 'failed'
                    }" class="px-2 py-1 rounded text-sm font-medium">
                      {{ purchase.status === 'completed' ? '✓ Completado' : purchase.status === 'pending' ? '⏳ Pendiente' : '✗ Fallido' }}
                    </span>
                  </div>
                </div>
              </div>
            </div>

            <!-- Pending Blocks Section -->
            <div v-if="selectedUserDetail.pending_blocks && selectedUserDetail.pending_blocks.blocks && selectedUserDetail.pending_blocks.blocks.length > 0" class="card p-3">
              <h4 class="text-base font-semibold mb-3 text-accent-primary">
                ⏳ Bloques Pendientes ({{ selectedUserDetail.pending_blocks.pending_count }})
                <span class="text-xs text-text-muted ml-2">Total: {{ Number(selectedUserDetail.pending_blocks.total_reward || 0).toLocaleString('en-US', { minimumFractionDigits: 4, maximumFractionDigits: 4 }) }} Landwork (~{{ (Number(selectedUserDetail.pending_blocks.total_reward || 0) / 100000).toLocaleString('en-US', { minimumFractionDigits: 4, maximumFractionDigits: 4 }) }} RON)</span>
              </h4>
              <div
                @scroll="handlePendingBlocksScroll"
                class="max-h-80 overflow-y-auto"
              >
                <table class="w-full text-sm">
                  <thead class="sticky top-0 bg-bg-secondary border-b border-border">
                    <tr>
                      <th class="px-2 py-2 text-left font-semibold text-text-secondary">Bloque</th>
                      <th class="px-2 py-2 text-right font-semibold text-text-secondary">Recompensa</th>
                      <th class="px-2 py-2 text-right font-semibold text-text-secondary">Shares</th>
                      <th class="px-2 py-2 text-right font-semibold text-text-secondary">%</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr v-for="block in selectedUserDetail.pending_blocks.blocks.slice(0, pendingBlocksToShow)" :key="block.id" class="border-b border-border/50 hover:bg-bg-tertiary/30">
                      <td class="px-2 py-2">
                        <span class="font-medium">#{{ block.block_id }}</span>
                        <span v-if="block.is_premium" class="ml-1">⭐</span>
                      </td>
                      <td class="px-2 py-2 text-right text-amber-400 font-medium">
                        {{ Number(block.reward || 0).toLocaleString('en-US', { minimumFractionDigits: 4, maximumFractionDigits: 4 }) }} Landwork
                      </td>
                      <td class="px-2 py-2 text-right text-text-muted text-xs">
                        {{ Number(block.shares_contributed).toLocaleString('en-US') }}/{{ Number(block.total_block_shares).toLocaleString('en-US') }}
                      </td>
                      <td class="px-2 py-2 text-right font-medium">
                        {{ Number(block.share_percentage || 0).toFixed(1) }}%
                      </td>
                    </tr>
                  </tbody>
                </table>
                <!-- Loading indicator -->
                <div v-if="pendingBlocksToShow < selectedUserDetail.pending_blocks.blocks.length" class="text-center py-2">
                  <p class="text-xs text-text-muted">Scroll para cargar más...</p>
                </div>
              </div>
            </div>

            <!-- Claimed Blocks Section -->
            <div v-if="selectedUserDetail.claimed_blocks && selectedUserDetail.claimed_blocks.length > 0" class="card p-3">
              <h4 class="text-base font-semibold mb-3 text-accent-primary">
                ✅ Bloques Reclamados ({{ selectedUserDetail.claimed_blocks.length }})
                <span class="text-xs text-text-muted ml-2">Total: {{ claimedBlocksTotalReward.toLocaleString('en-US', { minimumFractionDigits: 4, maximumFractionDigits: 4 }) }} Landwork</span>
              </h4>
              <div
                @scroll="handleClaimedBlocksScroll"
                class="max-h-80 overflow-y-auto"
              >
                <table class="w-full text-sm">
                  <thead class="sticky top-0 bg-bg-secondary border-b border-border">
                    <tr>
                      <th class="px-2 py-2 text-left font-semibold text-text-secondary">Bloque</th>
                      <th class="px-2 py-2 text-right font-semibold text-text-secondary">Recompensa</th>
                      <th class="px-2 py-2 text-right font-semibold text-text-secondary">Shares</th>
                      <th class="px-2 py-2 text-right font-semibold text-text-secondary">%</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr v-for="block in selectedUserDetail.claimed_blocks.slice(0, claimedBlocksToShow)" :key="block.id" class="border-b border-border/50 hover:bg-bg-tertiary/30">
                      <td class="px-2 py-2">
                        <span class="font-medium">#{{ block.block_id }}</span>
                        <span v-if="block.is_premium" class="ml-1">⭐</span>
                      </td>
                      <td class="px-2 py-2 text-right text-green-400 font-medium">
                        {{ Number(block.reward || 0).toLocaleString('en-US', { minimumFractionDigits: 4, maximumFractionDigits: 4 }) }} Landwork
                      </td>
                      <td class="px-2 py-2 text-right text-text-muted text-xs">
                        {{ Number(block.shares_contributed).toLocaleString('en-US') }}/{{ Number(block.total_block_shares).toLocaleString('en-US') }}
                      </td>
                      <td class="px-2 py-2 text-right font-medium">
                        {{ Number(block.share_percentage || 0).toFixed(1) }}%
                      </td>
                    </tr>
                  </tbody>
                </table>
                <!-- Loading indicator -->
                <div v-if="claimedBlocksToShow < selectedUserDetail.claimed_blocks.length" class="text-center py-2">
                  <p class="text-xs text-text-muted">Scroll para cargar más...</p>
                </div>
              </div>
            </div>

            <!-- Recent Transactions Section -->
            <div v-if="selectedUserDetail.recent_transactions && selectedUserDetail.recent_transactions.length > 0" class="card p-3">
              <h4 class="text-base font-semibold mb-3 text-accent-primary">
                💳 Transacciones Recientes ({{ selectedUserDetail.recent_transactions.length }})
              </h4>
              <div class="max-h-80 overflow-y-auto">
                <table class="w-full text-sm">
                  <thead class="sticky top-0 bg-bg-secondary border-b border-border">
                    <tr>
                      <th class="px-2 py-2 text-left font-semibold text-text-secondary">Tipo</th>
                      <th class="px-2 py-2 text-right font-semibold text-text-secondary">Monto</th>
                      <th class="px-2 py-2 text-left font-semibold text-text-secondary">Descripción</th>
                      <th class="px-2 py-2 text-right font-semibold text-text-secondary">Fecha</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr v-for="(tx, index) in selectedUserDetail.recent_transactions" :key="index" class="border-b border-border/50 hover:bg-bg-tertiary/30">
                      <td class="px-2 py-2">
                        <span class="px-2 py-0.5 rounded text-xs font-medium bg-gray-500/20 text-gray-400">
                          {{ tx.type }}
                        </span>
                      </td>
                      <td class="px-2 py-2 text-right">
                        <div class="flex items-center justify-end gap-2">
                          <span :class="{
                            'text-green-400': tx.amount > 0,
                            'text-red-400': tx.amount < 0,
                            'text-text-muted': tx.amount === 0
                          }" class="font-semibold">
                            {{ tx.amount > 0 ? '+' : '' }}{{ Number(tx.amount || 0).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 4 }) }}
                          </span>
                          <span class="px-1.5 py-0.5 rounded text-xs font-medium uppercase" :class="{
                            'bg-yellow-500/20 text-yellow-400': tx.currency === 'gamecoin',
                            'bg-amber-500/20 text-amber-400': tx.currency === 'crypto',
                            'bg-blue-500/20 text-blue-400': tx.currency === 'ron'
                          }">
                            {{ tx.currency === 'gamecoin' ? 'GC' : tx.currency === 'crypto' ? 'Landwork' : 'RON' }}
                          </span>
                        </div>
                      </td>
                      <td class="px-2 py-2 text-text-muted text-xs">
                        {{ tx.description }}
                      </td>
                      <td class="px-2 py-2 text-right text-text-muted text-xs whitespace-nowrap">
                        {{ formatDate(tx.created_at) }}
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>
            </div>
          </div>
        </div>
      </div>
    </Teleport>
  </div>
</template>

<style scoped>
.animate-fade-in {
  animation: fadeIn 0.2s ease-out;
}

@keyframes fadeIn {
  from {
    opacity: 0;
    transform: scale(0.95);
  }
  to {
    opacity: 1;
    transform: scale(1);
  }
}

/* Custom scrollbar styles */
.overflow-y-auto::-webkit-scrollbar {
  width: 8px;
}

.overflow-y-auto::-webkit-scrollbar-track {
  background: rgba(0, 0, 0, 0.2);
  border-radius: 4px;
}

.overflow-y-auto::-webkit-scrollbar-thumb {
  background: rgba(245, 158, 11, 0.5);
  border-radius: 4px;
}

.overflow-y-auto::-webkit-scrollbar-thumb:hover {
  background: rgba(245, 158, 11, 0.7);
}
</style>
