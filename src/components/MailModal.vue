<script setup lang="ts">
import { ref, watch, computed, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMailStore, type Mail } from '@/stores/mail';
import { useAuthStore } from '@/stores/auth';
import { useToastStore } from '@/stores/toast';
import { playSound } from '@/utils/sounds';
import { formatNumber } from '@/utils/format';

const { t } = useI18n();
const mailStore = useMailStore();
const authStore = useAuthStore();
const toastStore = useToastStore();

const props = defineProps<{
  show: boolean;
}>();

const emit = defineEmits<{
  close: [];
}>();

// Compose form
const composeTo = ref('');
const composeToConfirmed = ref(false);
const composeSubject = ref('');
const composeBody = ref('');
const composePassword = ref('');
const composeGamecoin = ref(0);
const composeCrypto = ref(0);
const composeEnergy = ref(0);
const composeInternet = ref(0);
const showPasswordField = ref(false);
const subjectInputRef = ref<HTMLInputElement | null>(null);

// File picker
const showFilePicker = ref(false);
const selectedFileKey = ref<string | null>(null);
const filePickerAmount = ref('');

interface ResourceFile {
  key: string;
  icon: string;
  name: string;
  ext: string;
  type: string;
  color: string;
  getBalance: () => number;
  step: string;
}

const resourceFiles: ResourceFile[] = [
  { key: 'gamecoin', icon: '🪙', name: 'gamecoin', ext: '.gc', type: 'GameCoin', color: '#fbbc05', getBalance: () => authStore.player?.gamecoin_balance ?? 0, step: '1' },
  { key: 'crypto', icon: '💎', name: 'crypto', ext: '.blc', type: 'BlockCoin', color: '#4fc3f7', getBalance: () => authStore.player?.crypto_balance ?? 0, step: '0.001' },
  { key: 'energy', icon: '⚡', name: 'energy', ext: '.nrg', type: 'Energy', color: '#66bb6a', getBalance: () => authStore.player?.energy ?? 0, step: '1' },
  { key: 'internet', icon: '📡', name: 'internet', ext: '.net', type: 'Internet', color: '#ab47bc', getBalance: () => authStore.player?.internet ?? 0, step: '1' },
];

const selectedFile = computed(() => resourceFiles.find(f => f.key === selectedFileKey.value) ?? null);

const attachedResources = computed(() => {
  const items: { key: string; icon: string; type: string; amount: number; color: string }[] = [];
  if (composeGamecoin.value > 0) items.push({ key: 'gamecoin', icon: '🪙', type: 'GC', amount: composeGamecoin.value, color: '#fbbc05' });
  if (composeCrypto.value > 0) items.push({ key: 'crypto', icon: '💎', type: 'BLC', amount: composeCrypto.value, color: '#4fc3f7' });
  if (composeEnergy.value > 0) items.push({ key: 'energy', icon: '⚡', type: 'NRG', amount: composeEnergy.value, color: '#66bb6a' });
  if (composeInternet.value > 0) items.push({ key: 'internet', icon: '📡', type: 'NET', amount: composeInternet.value, color: '#ab47bc' });
  return items;
});

function openFilePicker() {
  selectedFileKey.value = null;
  filePickerAmount.value = '';
  showFilePicker.value = true;
}

function selectResourceFile(key: string) {
  selectedFileKey.value = key;
  // Pre-fill with current amount if already attached
  const current = getAttachedAmount(key);
  filePickerAmount.value = current > 0 ? String(current) : '';
}

function getAttachedAmount(key: string): number {
  if (key === 'gamecoin') return composeGamecoin.value;
  if (key === 'crypto') return composeCrypto.value;
  if (key === 'energy') return composeEnergy.value;
  if (key === 'internet') return composeInternet.value;
  return 0;
}

function confirmAttachFile() {
  if (!selectedFileKey.value) return;
  const amount = parseFloat(filePickerAmount.value) || 0;
  if (selectedFileKey.value === 'gamecoin') composeGamecoin.value = amount;
  else if (selectedFileKey.value === 'crypto') composeCrypto.value = amount;
  else if (selectedFileKey.value === 'energy') composeEnergy.value = amount;
  else if (selectedFileKey.value === 'internet') composeInternet.value = amount;
  showFilePicker.value = false;
}

function removeAttachment(key: string) {
  if (key === 'gamecoin') composeGamecoin.value = 0;
  else if (key === 'crypto') composeCrypto.value = 0;
  else if (key === 'energy') composeEnergy.value = 0;
  else if (key === 'internet') composeInternet.value = 0;
}

// Claim password prompt
const claimPassword = ref('');
const showClaimPassword = ref(false);
const claimingMailId = ref<string | null>(null);

// Confirm delete
const confirmDeleteId = ref<string | null>(null);

// Starred mails (local only, cosmetic)
const starredIds = ref<Set<string>>(new Set());

function toggleStar(mailId: string, event: Event) {
  event.stopPropagation();
  if (starredIds.value.has(mailId)) {
    starredIds.value.delete(mailId);
  } else {
    starredIds.value.add(mailId);
  }
}

watch(() => props.show, (val) => {
  if (val) {
    mailStore.fetchInbox();
    mailStore.fetchUnreadCount();
    mailStore.currentView = 'inbox';
    mailStore.selectedMail = null;
    mailStore.error = null;
    resetCompose();
  }
});

const DRAFT_KEY = 'lootmail_draft';

function saveDraft() {
  const draft = {
    to: composeTo.value,
    toConfirmed: composeToConfirmed.value,
    subject: composeSubject.value,
    body: composeBody.value,
    gamecoin: composeGamecoin.value,
    crypto: composeCrypto.value,
    energy: composeEnergy.value,
    internet: composeInternet.value,
  };
  // Only save if there's something written
  if (draft.to || draft.subject || draft.body || draft.gamecoin || draft.crypto || draft.energy || draft.internet) {
    localStorage.setItem(DRAFT_KEY, JSON.stringify(draft));
  } else {
    localStorage.removeItem(DRAFT_KEY);
  }
}

function loadDraft() {
  try {
    const raw = localStorage.getItem(DRAFT_KEY);
    if (!raw) return;
    const draft = JSON.parse(raw);
    composeTo.value = draft.to || '';
    composeToConfirmed.value = draft.toConfirmed || false;
    composeSubject.value = draft.subject || '';
    composeBody.value = draft.body || '';
    composeGamecoin.value = draft.gamecoin || 0;
    composeCrypto.value = draft.crypto || 0;
    composeEnergy.value = draft.energy || 0;
    composeInternet.value = draft.internet || 0;
  } catch { /* ignore */ }
}

function clearDraft() {
  localStorage.removeItem(DRAFT_KEY);
}

function resetCompose() {
  composeTo.value = '';
  composeToConfirmed.value = false;
  composeSubject.value = '';
  composeBody.value = '';
  composePassword.value = '';
  composeGamecoin.value = 0;
  composeCrypto.value = 0;
  composeEnergy.value = 0;
  composeInternet.value = 0;
  showPasswordField.value = false;
  showFilePicker.value = false;
  clearDraft();
}

// Auto-save draft while composing
watch([composeTo, composeSubject, composeBody, composeGamecoin, composeCrypto, composeEnergy, composeInternet, composeToConfirmed], saveDraft, { deep: true });

// Load draft when compose view opens
watch(() => mailStore.currentView, (view) => {
  if (view === 'compose') {
    nextTick(() => {
      if (!composeTo.value && !composeSubject.value && !composeBody.value) {
        loadDraft();
      }
    });
  }
});

function handleClose() {
  playSound('click');
  emit('close');
}

function formatDate(dateStr: string) {
  const d = new Date(dateStr);
  const now = new Date();
  const isToday = d.toDateString() === now.toDateString();
  if (isToday) {
    return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  }
  return d.toLocaleDateString([], { month: 'short', day: 'numeric' });
}

function formatDateFull(dateStr: string) {
  return new Date(dateStr).toLocaleString([], {
    year: 'numeric', month: 'long', day: 'numeric',
    hour: '2-digit', minute: '2-digit',
  });
}

// === SEND ===
async function handleSend() {
  if (!composeSubject.value.trim()) {
    mailStore.error = t('mail.errorSubjectRequired');
    return;
  }
  if (!composeTo.value.trim()) {
    mailStore.error = t('mail.errorNotFound');
    return;
  }

  // Ticket mode: send support ticket
  if (isTicketMode.value) {
    const result = await mailStore.sendTicket({
      subject: composeSubject.value.trim(),
      body: composeBody.value.trim() || undefined,
    });
    if (result) {
      playSound('purchase');
      toastStore.success(t('mail.ticketSent'), '🎫');
      resetCompose();
      mailStore.goToSent();
      mailStore.fetchSent();
    } else {
      playSound('error');
    }
    return;
  }

  const result = await mailStore.sendMail({
    recipientUsername: composeTo.value.trim(),
    subject: composeSubject.value.trim(),
    body: composeBody.value.trim() || undefined,
    password: showPasswordField.value ? composePassword.value.trim() || undefined : undefined,
    gamecoin: composeGamecoin.value || undefined,
    crypto: composeCrypto.value || undefined,
    energy: composeEnergy.value || undefined,
    internet: composeInternet.value || undefined,
  });

  if (result) {
    playSound('purchase');
    toastStore.success(t('mail.sentSuccess', { username: composeTo.value.trim() }), '📧');
    resetCompose();
    mailStore.goToInbox();
    mailStore.fetchInbox();
  } else {
    playSound('error');
  }
}

// === CLAIM ===
function startClaim(mail: Mail) {
  if (mail.has_password && !mail.is_claimed) {
    claimingMailId.value = mail.id;
    claimPassword.value = '';
    showClaimPassword.value = true;
  } else {
    doClaim(mail.id);
  }
}

async function doClaim(mailId: string, password?: string) {
  const result = await mailStore.claimAttachment(mailId, password);
  if (result) {
    playSound('success');
    toastStore.success(t('mail.claimSuccess'), '📦');
    showClaimPassword.value = false;
    claimingMailId.value = null;
  } else {
    playSound('error');
  }
}

function submitClaimPassword() {
  if (claimingMailId.value) {
    doClaim(claimingMailId.value, claimPassword.value);
  }
}

// === DELETE ===
function requestDelete(mailId: string) {
  confirmDeleteId.value = mailId;
}

async function confirmDelete() {
  if (confirmDeleteId.value) {
    await mailStore.removeMail(confirmDeleteId.value);
    confirmDeleteId.value = null;
  }
}

const currentMail = computed(() => mailStore.selectedMail);

// Storage display
const storagePercent = computed(() => {
  if (mailStore.storageMax <= 0) return 0;
  return Math.min(100, Math.round((mailStore.storageUsed / mailStore.storageMax) * 100));
});

const storageColor = computed(() => {
  const pct = storagePercent.value;
  if (pct >= 80) return '#ea4335';
  if (pct >= 50) return '#fbbc05';
  return '#34a853';
});

// Client-side size estimation for compose (mirrors DB formula)
const estimatedSizeKb = computed(() => {
  let size = 1;
  const textLen = (composeSubject.value?.length || 0) + (composeBody.value?.length || 0);
  if (textLen > 0) size += Math.ceil(textLen / 50);
  if (composeGamecoin.value > 0) size += Math.ceil(composeGamecoin.value / 100);
  if (composeCrypto.value > 0) size += Math.ceil(composeCrypto.value * 100);
  if (composeEnergy.value > 0) size += Math.ceil(composeEnergy.value / 10);
  if (composeInternet.value > 0) size += Math.ceil(composeInternet.value / 10);
  return size;
});

const isTicketMode = computed(() => composeTo.value.trim().toLowerCase() === '@ticket');

const showAtSuggestions = computed(() => {
  const val = composeTo.value.trim().toLowerCase();
  return val.startsWith('@') && val !== '@ticket';
});

const atSuggestions = computed(() => {
  const val = composeTo.value.trim().toLowerCase();
  const options = [
    { value: '@ticket', label: '@ticket', desc: t('mail.ticketHint', 'Soporte'), icon: '🎫' },
  ];
  if (!val || val === '@') return options;
  return options.filter(o => o.value.startsWith(val));
});

function selectAtSuggestion(value: string) {
  composeTo.value = value;
  composeToConfirmed.value = true;
  subjectInputRef.value?.focus();
}

function confirmRecipient() {
  if (composeTo.value.trim()) {
    composeToConfirmed.value = true;
    subjectInputRef.value?.focus();
  }
}

function clearRecipient() {
  composeTo.value = '';
  composeToConfirmed.value = false;
}

function getResourceSizeLabel(key: string): string {
  switch (key) {
    case 'gamecoin': return '1KB/100';
    case 'crypto': return '100KB/1';
    case 'energy': return '1KB/10';
    case 'internet': return '1KB/10';
    default: return '';
  }
}
</script>

<template>
  <Teleport to="body">
    <div v-if="show" class="fixed inset-0 z-50 flex items-center justify-center p-1 sm:p-4">
      <div class="absolute inset-0 bg-black/60" @click="handleClose" />

      <!-- Gmail-style container -->
      <div class="gmail-container relative w-full max-w-5xl h-[92vh] sm:h-[88vh] overflow-hidden flex flex-col animate-fade-in">

        <!-- ===== TOP BAR (Gmail blue bar) ===== -->
        <div class="gmail-topbar shrink-0">
          <div class="flex items-center justify-between px-3 sm:px-4 h-10">
            <!-- Logo -->
            <div class="flex items-center gap-2">
              <div class="lootmail-logo">
                <span class="logo-L">L</span><span class="logo-o1">o</span><span class="logo-o2">o</span><span class="logo-t">t</span><span class="logo-M">M</span><span class="logo-a">a</span><span class="logo-i">i</span><span class="logo-l">l</span>
              </div>
              <span v-if="mailStore.hasUnread" class="text-[10px] text-white/70 font-normal ml-1">({{ mailStore.unreadCount }})</span>
            </div>
            <!-- Close -->
            <button @click="handleClose" class="w-6 h-6 flex items-center justify-center text-white/60 hover:text-white rounded transition-colors text-xs font-bold">
              ✕
            </button>
          </div>
        </div>

        <!-- ===== SEARCH BAR ===== -->
        <div class="gmail-searchbar shrink-0">
          <div class="flex items-center gap-2 px-3 sm:px-4 py-1.5">
            <button
              @click="mailStore.openCompose()"
              class="gmail-compose-btn shrink-0"
            >
              <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 5v14M5 12h14"/></svg>
              <span class="hidden sm:inline">{{ t('mail.compose') }}</span>
            </button>
            <div class="flex-1 flex items-center gap-1.5 px-3 py-1 bg-white/5 border border-white/10 rounded text-xs text-white/40">
              <svg class="w-3.5 h-3.5 shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>
              <span>Search mail...</span>
            </div>
          </div>
        </div>

        <!-- ===== MAIN BODY ===== -->
        <div class="flex-1 flex overflow-hidden gmail-body">

          <!-- Sidebar -->
          <div class="gmail-sidebar shrink-0">
            <button
              @click="mailStore.goToInbox(); mailStore.fetchInbox()"
              class="gmail-nav-item"
              :class="{ 'gmail-nav-active': mailStore.currentView === 'inbox' || mailStore.currentView === 'detail' }"
            >
              <svg class="w-4 h-4 shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M3 8l9-5 9 5v11a1 1 0 01-1 1H4a1 1 0 01-1-1V8z"/><polyline points="3,8 12,14 21,8"/></svg>
              <span class="flex-1 text-left">{{ t('mail.inbox') }}</span>
              <span v-if="mailStore.hasUnread" class="gmail-badge">{{ mailStore.unreadCount }}</span>
            </button>
            <button
              @click="mailStore.goToSent()"
              class="gmail-nav-item"
              :class="{ 'gmail-nav-active': mailStore.currentView === 'sent' }"
            >
              <svg class="w-4 h-4 shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><line x1="22" y1="2" x2="11" y2="13"/><polygon points="22,2 15,22 11,13 2,9"/></svg>
              <span class="flex-1 text-left">{{ t('mail.sent') }}</span>
            </button>

            <!-- Storage info -->
            <div class="mt-auto px-3 py-2 border-t border-white/5">
              <div class="text-[9px] text-white/25 leading-relaxed">
                {{ t('mail.storageUsing', { used: mailStore.storageUsed, max: mailStore.storageMax }) }}
              </div>
              <div class="mt-1 h-1 bg-white/5 rounded-full overflow-hidden">
                <div
                  class="h-full rounded-full transition-all duration-300"
                  :style="{ width: storagePercent + '%', backgroundColor: storageColor }"
                ></div>
              </div>
              <div v-if="storagePercent >= 80" class="text-[8px] mt-0.5" :style="{ color: storageColor }">
                {{ storagePercent >= 100 ? t('mail.storageFull') : t('mail.storageWarning') }}
              </div>
            </div>
          </div>

          <!-- Content Area -->
          <div class="flex-1 overflow-y-auto gmail-content">

            <!-- ===== INBOX LIST ===== -->
            <div v-if="mailStore.currentView === 'inbox'">
              <!-- Toolbar -->
              <div class="gmail-toolbar">
                <span class="text-[10px] text-white/30">
                  {{ mailStore.inbox.length }} {{ mailStore.inbox.length === 1 ? 'message' : 'messages' }}
                </span>
                <button @click="mailStore.fetchInbox()" class="gmail-toolbar-btn" title="Refresh">
                  <svg class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="23,4 23,10 17,10"/><path d="M20.49 15a9 9 0 11-2.12-9.36L23 10"/></svg>
                </button>
              </div>

              <!-- Loading -->
              <div v-if="mailStore.loading" class="flex items-center justify-center h-40">
                <span class="text-white/30 text-xs animate-pulse">{{ t('common.loading') }}</span>
              </div>
              <!-- Empty -->
              <div v-else-if="mailStore.inbox.length === 0" class="flex flex-col items-center justify-center h-60 gap-3">
                <svg class="w-16 h-16 text-white/10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="0.5"><path d="M3 8l9-5 9 5v11a1 1 0 01-1 1H4a1 1 0 01-1-1V8z"/><polyline points="3,8 12,14 21,8"/></svg>
                <p class="text-white/30 text-sm">{{ t('mail.noMail') }}</p>
                <p class="text-white/15 text-[11px]">{{ t('mail.noMailHint') }}</p>
              </div>
              <!-- Mail rows -->
              <div v-else>
                <div
                  v-for="mail in mailStore.inbox"
                  :key="mail.id"
                  @click="mailStore.selectMail(mail)"
                  class="gmail-row"
                  :class="{ 'gmail-row-unread': !mail.is_read }"
                >
                  <!-- Star -->
                  <button
                    @click="toggleStar(mail.id, $event)"
                    class="gmail-star shrink-0"
                    :class="{ 'gmail-star-active': starredIds.has(mail.id) }"
                  >
                    {{ starredIds.has(mail.id) ? '★' : '☆' }}
                  </button>
                  <!-- Sender -->
                  <div class="gmail-sender shrink-0" :class="{ 'font-bold': !mail.is_read }">
                    <span v-if="mail.mail_type === 'admin'" class="gmail-label-admin">SYS</span>
                    {{ mail.sender_username }}
                  </div>
                  <!-- Subject + snippet -->
                  <div class="gmail-subject-area flex-1 min-w-0">
                    <span class="gmail-subject" :class="{ 'font-bold': !mail.is_read }">{{ mail.subject }}</span>
                    <span v-if="mail.body" class="gmail-snippet"> - {{ mail.body }}</span>
                  </div>
                  <!-- Indicators -->
                  <div class="flex items-center gap-1 shrink-0 ml-1">
                    <span v-if="mail.has_attachment" class="gmail-attach-icon" title="Attachment">
                      <svg class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21.44 11.05l-9.19 9.19a6 6 0 01-8.49-8.49l9.19-9.19a4 4 0 015.66 5.66l-9.2 9.19a2 2 0 01-2.83-2.83l8.49-8.48"/></svg>
                    </span>
                    <span v-if="mail.has_password" class="text-[10px] text-amber-400/70">🔒</span>
                    <span v-if="mail.has_attachment && !mail.is_claimed" class="gmail-new-badge">new</span>
                  </div>
                  <!-- Date + Size -->
                  <span class="gmail-date shrink-0" :class="{ 'font-bold': !mail.is_read }">{{ formatDate(mail.created_at) }}</span>
                  <span class="gmail-size shrink-0">{{ mail.size_kb }} KB</span>
                </div>
              </div>
            </div>

            <!-- ===== SENT LIST ===== -->
            <div v-if="mailStore.currentView === 'sent'">
              <div class="gmail-toolbar">
                <span class="text-[10px] text-white/30">{{ mailStore.sent.length }} sent</span>
              </div>
              <div v-if="mailStore.loading" class="flex items-center justify-center h-40">
                <span class="text-white/30 text-xs animate-pulse">{{ t('common.loading') }}</span>
              </div>
              <div v-else-if="mailStore.sent.length === 0" class="flex flex-col items-center justify-center h-40 gap-2">
                <p class="text-white/30 text-sm">{{ t('mail.noSentMail') }}</p>
              </div>
              <div v-else>
                <div
                  v-for="mail in mailStore.sent"
                  :key="mail.id"
                  class="gmail-row"
                >
                  <span class="gmail-star shrink-0 opacity-0">☆</span>
                  <div class="gmail-sender shrink-0 text-white/40">
                    <span v-if="mail.mail_type === 'ticket'" class="text-fuchsia-400">🎫 @ticket</span>
                    <span v-else>To: {{ mail.recipient_username }}</span>
                  </div>
                  <div class="gmail-subject-area flex-1 min-w-0">
                    <span class="gmail-subject text-white/50">{{ mail.subject }}</span>
                  </div>
                  <div class="flex items-center gap-1 shrink-0 ml-1">
                    <span v-if="mail.has_attachment" class="gmail-attach-icon">
                      <svg class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21.44 11.05l-9.19 9.19a6 6 0 01-8.49-8.49l9.19-9.19a4 4 0 015.66 5.66l-9.2 9.19a2 2 0 01-2.83-2.83l8.49-8.48"/></svg>
                    </span>
                    <span v-if="mail.is_claimed" class="text-[9px] text-green-400/60">claimed</span>
                  </div>
                  <span class="gmail-date">{{ formatDate(mail.created_at) }}</span>
                  <span class="gmail-size shrink-0">{{ mail.size_kb }} KB</span>
                </div>
              </div>
            </div>

            <!-- ===== DETAIL VIEW ===== -->
            <div v-if="mailStore.currentView === 'detail' && currentMail" class="gmail-detail">
              <!-- Back link -->
              <button @click="mailStore.goToInbox()" class="gmail-back-link">
                &larr; {{ t('mail.back') }} to {{ t('mail.inbox') }}
              </button>

              <!-- Subject line -->
              <div class="gmail-detail-header">
                <h2 class="gmail-detail-subject">{{ currentMail.subject }}</h2>
                <span v-if="currentMail.mail_type === 'admin'" class="gmail-label-admin ml-2">SYS</span>
              </div>

              <!-- Sender info -->
              <div class="gmail-detail-sender">
                <div class="gmail-avatar">
                  {{ (currentMail.sender_username || 'S').charAt(0).toUpperCase() }}
                </div>
                <div class="flex-1 min-w-0">
                  <div class="flex items-baseline gap-2">
                    <span class="text-sm font-bold text-white/90">{{ currentMail.sender_username }}</span>
                    <span class="text-[10px] text-white/25">&lt;{{ currentMail.sender_username }}@lootmail.game&gt;</span>
                  </div>
                  <div class="text-[10px] text-white/30 mt-0.5">{{ formatDateFull(currentMail.created_at) }} <span class="ml-2 text-white/20">{{ currentMail.size_kb }} KB</span></div>
                </div>
                <!-- Delete -->
                <button @click="requestDelete(currentMail.id)" class="gmail-toolbar-btn" title="Delete">
                  <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><polyline points="3,6 5,6 21,6"/><path d="M19 6v14a2 2 0 01-2 2H7a2 2 0 01-2-2V6m3 0V4a2 2 0 012-2h4a2 2 0 012 2v2"/></svg>
                </button>
              </div>

              <!-- Body -->
              <div class="gmail-detail-body">
                <p v-if="currentMail.body" class="text-[13px] text-white/80 whitespace-pre-wrap leading-relaxed">{{ currentMail.body }}</p>
                <p v-else class="text-[13px] text-white/30 italic">(no message body)</p>
              </div>

              <!-- Attachments -->
              <div v-if="currentMail.has_attachment" class="gmail-detail-attachments">
                <div class="gmail-attach-header">
                  <svg class="w-4 h-4 text-white/40" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21.44 11.05l-9.19 9.19a6 6 0 01-8.49-8.49l9.19-9.19a4 4 0 015.66 5.66l-9.2 9.19a2 2 0 01-2.83-2.83l8.49-8.48"/></svg>
                  <span>{{ t('mail.attachments') }}</span>
                  <span v-if="currentMail.has_password && !currentMail.is_claimed" class="gmail-lock-badge">🔒 {{ t('mail.passwordRequired') }}</span>
                </div>

                <!-- Attachment chips -->
                <div class="flex flex-wrap gap-2 my-3">
                  <div v-if="currentMail.attachment_gamecoin > 0" class="gmail-attach-chip gmail-chip-gc">
                    <span>🪙</span> {{ formatNumber(currentMail.attachment_gamecoin) }} GC
                  </div>
                  <div v-if="currentMail.attachment_crypto > 0" class="gmail-attach-chip gmail-chip-crypto">
                    <span>💎</span> {{ currentMail.attachment_crypto }} BLC
                  </div>
                  <div v-if="currentMail.attachment_energy > 0" class="gmail-attach-chip gmail-chip-energy">
                    <span>⚡</span> {{ formatNumber(currentMail.attachment_energy) }} Energy
                  </div>
                  <div v-if="currentMail.attachment_internet > 0" class="gmail-attach-chip gmail-chip-internet">
                    <span>📡</span> {{ formatNumber(currentMail.attachment_internet) }} Internet
                  </div>
                  <div v-if="currentMail.attachment_item_type && currentMail.attachment_item_quantity > 0" class="gmail-attach-chip gmail-chip-item">
                    <span>📦</span> {{ currentMail.attachment_item_quantity }}x {{ currentMail.attachment_item_type }}
                  </div>
                </div>

                <!-- Claim area -->
                <div v-if="!currentMail.is_claimed">
                  <div v-if="showClaimPassword && claimingMailId === currentMail.id" class="flex gap-2 mb-2">
                    <input
                      v-model="claimPassword"
                      type="text"
                      :placeholder="t('mail.passwordPlaceholder')"
                      class="gmail-input flex-1"
                      @keydown.enter="submitClaimPassword"
                    />
                    <button @click="submitClaimPassword" :disabled="mailStore.claiming" class="gmail-btn-primary px-4">
                      {{ mailStore.claiming ? '...' : 'OK' }}
                    </button>
                  </div>
                  <button
                    v-else
                    @click="startClaim(currentMail)"
                    :disabled="mailStore.claiming"
                    class="gmail-btn-claim"
                  >
                    <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4"/><polyline points="7,10 12,15 17,10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>
                    {{ mailStore.claiming ? t('mail.claiming') : t('mail.claimAttachment') }}
                  </button>
                </div>
                <div v-else class="flex items-center gap-2 py-2">
                  <svg class="w-4 h-4 text-green-400" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="20,6 9,17 4,12"/></svg>
                  <span class="text-xs text-green-400/80">{{ t('mail.claimed') }}</span>
                </div>

                <p v-if="mailStore.error" class="text-[11px] text-red-400 mt-2">{{ mailStore.error }}</p>
              </div>
            </div>

            <!-- ===== COMPOSE VIEW ===== -->
            <div v-if="mailStore.currentView === 'compose'" class="gmail-compose">
              <div class="gmail-compose-header">
                <span class="text-xs font-bold text-white/70">{{ t('mail.compose') }}</span>
                <button @click="mailStore.goToInbox()" class="text-white/30 hover:text-white/60 text-xs">✕</button>
              </div>

              <div class="gmail-compose-body">
                <!-- Ticket mode banner -->
                <div v-if="isTicketMode" class="flex items-center gap-2 px-3 py-2 rounded bg-fuchsia-500/10 border border-fuchsia-500/20 mb-2">
                  <span class="text-sm">🎫</span>
                  <span class="text-[11px] text-fuchsia-300">{{ t('mail.ticketHint') }}</span>
                </div>

                <!-- To -->
                <div class="gmail-compose-field relative">
                  <label>{{ t('mail.to') }}</label>
                  <!-- Tag mode: show chip -->
                  <div v-if="composeToConfirmed && composeTo.trim()" class="flex items-center gap-1 flex-1">
                    <span class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium max-w-[200px]"
                      :class="isTicketMode
                        ? 'bg-fuchsia-500/20 text-fuchsia-300 border border-fuchsia-500/30'
                        : 'bg-blue-500/20 text-blue-300 border border-blue-500/30'">
                      <span v-if="isTicketMode">🎫</span>
                      <span class="truncate">{{ composeTo.trim() }}</span>
                      <button @click="clearRecipient" class="ml-0.5 hover:text-white transition-colors text-[10px] shrink-0">✕</button>
                    </span>
                  </div>
                  <!-- Input mode -->
                  <input v-else v-model="composeTo" type="text"
                    :placeholder="t('mail.toPlaceholder', 'username o @ticket')"
                    class="gmail-input"
                    autocomplete="off"
                    @keydown.enter.prevent="confirmRecipient" />
                  <!-- @ autocomplete -->
                  <div v-if="!composeToConfirmed && showAtSuggestions && atSuggestions.length > 0"
                    class="absolute left-12 right-0 top-full z-10 mt-1 bg-[#2a2a4a] border border-white/10 rounded-lg shadow-lg overflow-hidden">
                    <button
                      v-for="s in atSuggestions"
                      :key="s.value"
                      @mousedown.prevent="selectAtSuggestion(s.value)"
                      class="w-full flex items-center gap-2 px-3 py-2 text-left text-xs hover:bg-white/10 transition-colors"
                    >
                      <span>{{ s.icon }}</span>
                      <span class="text-fuchsia-300 font-medium">{{ s.label }}</span>
                      <span class="text-white/30 text-[10px] ml-auto">{{ s.desc }}</span>
                    </button>
                  </div>
                </div>
                <!-- Subject -->
                <div class="gmail-compose-field">
                  <label>{{ t('mail.subject') }}</label>
                  <input ref="subjectInputRef" v-model="composeSubject" type="text" maxlength="100" :placeholder="t('mail.subject')" class="gmail-input" />
                </div>
                <!-- Body -->
                <textarea
                  v-model="composeBody"
                  rows="6"
                  maxlength="2000"
                  class="gmail-textarea"
                  :placeholder="isTicketMode ? t('mail.ticketBodyPlaceholder', 'Describe tu problema...') : t('mail.bodyPlaceholder')"
                />

                <!-- Attached resources chips (hidden in ticket mode) -->
                <div v-if="!isTicketMode && attachedResources.length > 0" class="fp-attached-chips">
                  <div
                    v-for="res in attachedResources"
                    :key="res.key"
                    class="fp-chip"
                    :style="{ borderColor: res.color + '33', background: res.color + '0f' }"
                  >
                    <span>{{ res.icon }}</span>
                    <span class="fp-chip-amount" :style="{ color: res.color }">{{ formatNumber(res.amount) }} {{ res.type }}</span>
                    <button @click="removeAttachment(res.key)" class="fp-chip-remove" title="Remove">✕</button>
                  </div>
                </div>

                <!-- Toolbar: attach + password (hidden in ticket mode) -->
                <div v-if="!isTicketMode" class="gmail-compose-extras">
                  <button @click="openFilePicker" class="gmail-extra-btn">
                    <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21.44 11.05l-9.19 9.19a6 6 0 01-8.49-8.49l9.19-9.19a4 4 0 015.66 5.66l-9.2 9.19a2 2 0 01-2.83-2.83l8.49-8.48"/></svg>
                    {{ t('mail.addAttachment') }}
                  </button>
                  <button v-if="attachedResources.length > 0" @click="showPasswordField = !showPasswordField" class="gmail-extra-btn" :class="{ 'gmail-extra-btn-active': showPasswordField }">
                    🔒 {{ t('mail.password') }}
                  </button>
                </div>

                <!-- Password field (hidden in ticket mode) -->
                <div v-if="!isTicketMode && showPasswordField && attachedResources.length > 0" class="gmail-compose-attachments">
                  <div class="gmail-attach-field">
                    <label>🔒 {{ t('mail.password') }}</label>
                    <input v-model="composePassword" type="text" maxlength="50" :placeholder="t('mail.passwordPlaceholder')" class="gmail-input" />
                  </div>
                  <p class="text-[9px] text-white/20 mt-1 px-1">{{ t('mail.passwordHint') }}</p>
                </div>

                <!-- Error -->
                <p v-if="mailStore.error" class="text-[11px] text-red-400 px-1">{{ mailStore.error }}</p>

                <!-- Footer -->
                <div class="gmail-compose-footer">
                  <button
                    @click="handleSend"
                    :disabled="mailStore.sending || !composeSubject.trim() || !composeTo.trim()"
                    class="gmail-btn-send"
                    :class="{ '!bg-fuchsia-600 hover:!bg-fuchsia-500': isTicketMode }"
                  >
                    {{ mailStore.sending ? t('mail.sending') : (isTicketMode ? t('mail.sendTicket') : t('mail.send')) }}
                  </button>
                  <span class="text-[10px] text-white/25">{{ t('mail.sendCost', { cost: 5 }) }}</span>
                  <span v-if="isTicketMode" class="text-[10px] text-fuchsia-400/50">{{ t('mail.ticketLimit') }}</span>
                  <span v-else class="text-[10px] text-white/20 ml-auto font-mono">{{ t('mail.estimatedSize', { size: estimatedSizeKb }) }}</span>
                </div>
              </div>
            </div>

          </div>
        </div>

        <!-- ===== FOOTER ===== -->
        <div class="gmail-footer shrink-0">
          <span>LootMail v2.1 &mdash; Powered by LootMine</span>
          <span>{{ t('mail.dailyLimit', { remaining: 10 }) }}</span>
        </div>

      </div>

      <!-- ===== FILE PICKER MODAL ===== -->
      <div v-if="showFilePicker" class="fixed inset-0 z-[65] flex items-center justify-center p-2 sm:p-4">
        <div class="absolute inset-0 bg-black/50" @click="showFilePicker = false" />
        <div class="fp-dialog relative">
          <!-- Title bar -->
          <div class="fp-titlebar">
            <div class="flex items-center gap-1.5">
              <svg class="w-3.5 h-3.5 text-white/60" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21.44 11.05l-9.19 9.19a6 6 0 01-8.49-8.49l9.19-9.19a4 4 0 015.66 5.66l-9.2 9.19a2 2 0 01-2.83-2.83l8.49-8.48"/></svg>
              <span>{{ t('mail.addAttachment') }}</span>
            </div>
            <button @click="showFilePicker = false" class="fp-close-btn">✕</button>
          </div>

          <!-- Location bar -->
          <div class="fp-location-bar">
            <span class="fp-location-label">Look in:</span>
            <div class="fp-location-path">
              <span>📁</span> My Resources
            </div>
          </div>

          <!-- File list -->
          <div class="fp-file-list">
            <!-- Column headers -->
            <div class="fp-file-header">
              <span class="fp-col-icon"></span>
              <span class="fp-col-name">Name</span>
              <span class="fp-col-size">Balance</span>
              <span class="fp-col-weight">Size</span>
              <span class="fp-col-type">Type</span>
            </div>
            <!-- Resource files -->
            <div
              v-for="file in resourceFiles"
              :key="file.key"
              @click="selectResourceFile(file.key)"
              @dblclick="selectResourceFile(file.key); $nextTick(() => (filePickerAmount ? confirmAttachFile() : null))"
              class="fp-file-row"
              :class="{ 'fp-file-selected': selectedFileKey === file.key }"
            >
              <span class="fp-col-icon">{{ file.icon }}</span>
              <span class="fp-col-name fp-filename">{{ file.name }}{{ file.ext }}</span>
              <span class="fp-col-size" :style="{ color: file.color }">{{ formatNumber(file.getBalance()) }}</span>
              <span class="fp-col-weight">{{ getResourceSizeLabel(file.key) }}</span>
              <span class="fp-col-type">{{ file.type }}</span>
            </div>
          </div>

          <!-- Bottom controls -->
          <div class="fp-bottom">
            <div class="fp-field-row">
              <label>File name:</label>
              <div class="fp-selected-display">
                {{ selectedFile ? selectedFile.name + selectedFile.ext : '' }}
              </div>
            </div>
            <div class="fp-field-row">
              <label>Amount:</label>
              <input
                v-model="filePickerAmount"
                type="number"
                min="0"
                :step="selectedFile?.step ?? '1'"
                :max="selectedFile?.getBalance()"
                :placeholder="selectedFile ? `Max: ${formatNumber(selectedFile.getBalance())}` : '0'"
                :disabled="!selectedFile"
                class="fp-amount-input"
                @keydown.enter="confirmAttachFile"
              />
            </div>
            <div class="fp-actions">
              <button
                @click="confirmAttachFile"
                :disabled="!selectedFile || !filePickerAmount || parseFloat(filePickerAmount) <= 0"
                class="fp-btn-attach"
              >
                📎 Attach
              </button>
              <button @click="showFilePicker = false" class="fp-btn-cancel">
                Cancel
              </button>
            </div>
          </div>
        </div>
      </div>

      <!-- Delete confirmation -->
      <div v-if="confirmDeleteId" class="fixed inset-0 z-[65] flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-black/50" @click="confirmDeleteId = null" />
        <div class="relative bg-[#303134] border border-white/10 rounded-lg p-5 max-w-xs w-full text-center shadow-2xl">
          <p class="text-sm text-white/80 mb-4">{{ t('mail.confirmDelete') }}</p>
          <div class="flex gap-2 justify-center">
            <button @click="confirmDeleteId = null" class="px-4 py-1.5 border border-white/10 text-white/50 text-xs rounded hover:bg-white/5 transition-colors">
              {{ t('common.cancel') }}
            </button>
            <button @click="confirmDelete" class="px-4 py-1.5 bg-red-600 text-white text-xs font-bold rounded hover:bg-red-500 transition-colors">
              {{ t('mail.delete') }}
            </button>
          </div>
        </div>
      </div>
    </div>
  </Teleport>
</template>

<style scoped>
/* ===== GMAIL CLASSIC CONTAINER ===== */
.gmail-container {
  background: #1a1a2e;
  border: 1px solid rgba(255,255,255,0.08);
  border-radius: 12px;
  box-shadow: 0 25px 60px rgba(0,0,0,0.5);
}

/* ===== LOOTMAIL LOGO (Gmail-style colorful) ===== */
.lootmail-logo {
  font-family: 'Arial Black', 'Segoe UI', sans-serif;
  font-size: 18px;
  font-weight: 900;
  letter-spacing: -0.5px;
  line-height: 1;
  user-select: none;
}
.logo-L { color: #4285f4; }
.logo-o1 { color: #ea4335; }
.logo-o2 { color: #fbbc05; }
.logo-t { color: #4285f4; }
.logo-M { color: #34a853; }
.logo-a { color: #ea4335; }
.logo-i { color: #fbbc05; }
.logo-l { color: #4285f4; }

/* ===== TOP BAR ===== */
.gmail-topbar {
  background: linear-gradient(180deg, #2d2d4a 0%, #242440 100%);
  border-bottom: 1px solid rgba(255,255,255,0.06);
}

/* ===== SEARCH BAR ===== */
.gmail-searchbar {
  background: #1e1e36;
  border-bottom: 1px solid rgba(255,255,255,0.05);
}

/* ===== COMPOSE BUTTON ===== */
.gmail-compose-btn {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 6px 16px;
  background: #c2185b;
  color: white;
  font-size: 12px;
  font-weight: 700;
  border-radius: 20px;
  transition: all 0.15s;
  box-shadow: 0 1px 3px rgba(194,24,91,0.3);
}
.gmail-compose-btn:hover {
  background: #d81b60;
  box-shadow: 0 2px 8px rgba(194,24,91,0.4);
}

/* ===== BODY ===== */
.gmail-body {
  background: #16162b;
}

/* ===== SIDEBAR ===== */
.gmail-sidebar {
  width: 120px;
  background: #1a1a32;
  border-right: 1px solid rgba(255,255,255,0.04);
  display: flex;
  flex-direction: column;
  padding: 4px 0;
}
@media (min-width: 640px) {
  .gmail-sidebar { width: 160px; }
}

.gmail-nav-item {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 12px;
  font-size: 12px;
  color: rgba(255,255,255,0.5);
  transition: all 0.15s;
  border-radius: 0 20px 20px 0;
  margin-right: 8px;
}
.gmail-nav-item:hover {
  background: rgba(255,255,255,0.04);
  color: rgba(255,255,255,0.7);
}
.gmail-nav-active {
  background: rgba(194,24,91,0.15) !important;
  color: #f48fb1 !important;
  font-weight: 700;
}

.gmail-badge {
  font-size: 10px;
  font-weight: 800;
  background: #c2185b;
  color: white;
  padding: 0 6px;
  border-radius: 10px;
  min-width: 18px;
  text-align: center;
  line-height: 18px;
}

/* ===== CONTENT ===== */
.gmail-content {
  background: #16162b;
}

/* ===== TOOLBAR ===== */
.gmail-toolbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 6px 12px;
  border-bottom: 1px solid rgba(255,255,255,0.04);
}
.gmail-toolbar-btn {
  padding: 4px;
  color: rgba(255,255,255,0.3);
  border-radius: 50%;
  transition: all 0.15s;
}
.gmail-toolbar-btn:hover {
  color: rgba(255,255,255,0.7);
  background: rgba(255,255,255,0.06);
}

/* ===== MAIL ROW ===== */
.gmail-row {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 6px 12px;
  border-bottom: 1px solid rgba(255,255,255,0.03);
  cursor: pointer;
  transition: background 0.1s;
  height: 40px;
}
.gmail-row:hover {
  background: rgba(255,255,255,0.03);
  box-shadow: inset 0 -1px 0 rgba(255,255,255,0.05);
}
.gmail-row-unread {
  background: rgba(255,255,255,0.02);
}

.gmail-star {
  font-size: 14px;
  color: rgba(255,255,255,0.15);
  transition: color 0.1s;
  width: 20px;
  text-align: center;
}
.gmail-star:hover { color: rgba(251,188,5,0.5); }
.gmail-star-active { color: #fbbc05 !important; }

.gmail-sender {
  width: 100px;
  font-size: 12px;
  color: rgba(255,255,255,0.7);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
@media (min-width: 640px) {
  .gmail-sender { width: 140px; }
}

.gmail-label-admin {
  display: inline-block;
  font-size: 8px;
  font-weight: 800;
  letter-spacing: 0.5px;
  color: #4285f4;
  background: rgba(66,133,244,0.15);
  padding: 1px 4px;
  border-radius: 3px;
  margin-right: 4px;
  vertical-align: middle;
}

.gmail-subject-area {
  overflow: hidden;
  white-space: nowrap;
  text-overflow: ellipsis;
}
.gmail-subject {
  font-size: 12px;
  color: rgba(255,255,255,0.7);
}
.gmail-snippet {
  font-size: 12px;
  color: rgba(255,255,255,0.25);
}

.gmail-attach-icon {
  color: rgba(255,255,255,0.25);
}

.gmail-new-badge {
  font-size: 8px;
  font-weight: 800;
  text-transform: uppercase;
  letter-spacing: 0.5px;
  color: #34a853;
  background: rgba(52,168,83,0.15);
  padding: 1px 5px;
  border-radius: 3px;
}

.gmail-date {
  font-size: 11px;
  color: rgba(255,255,255,0.35);
  width: 55px;
  text-align: right;
}
.gmail-size {
  font-size: 9px;
  color: rgba(255,255,255,0.18);
  width: 35px;
  text-align: right;
  font-family: 'Consolas', 'Courier New', monospace;
}

/* ===== DETAIL VIEW ===== */
.gmail-detail {
  padding: 16px;
}
.gmail-back-link {
  font-size: 11px;
  color: rgba(255,255,255,0.3);
  transition: color 0.15s;
  margin-bottom: 12px;
  display: inline-block;
}
.gmail-back-link:hover { color: rgba(255,255,255,0.6); }

.gmail-detail-header {
  display: flex;
  align-items: center;
  margin-bottom: 16px;
  padding-bottom: 12px;
  border-bottom: 1px solid rgba(255,255,255,0.06);
}
.gmail-detail-subject {
  font-size: 18px;
  font-weight: 400;
  color: rgba(255,255,255,0.9);
  line-height: 1.3;
}

.gmail-detail-sender {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-bottom: 16px;
}
.gmail-avatar {
  width: 36px;
  height: 36px;
  border-radius: 50%;
  background: linear-gradient(135deg, #c2185b, #7b1fa2);
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 16px;
  font-weight: 700;
  color: white;
  shrink: 0;
}

.gmail-detail-body {
  padding: 16px 0 16px 46px;
  min-height: 60px;
  border-bottom: 1px solid rgba(255,255,255,0.04);
  margin-bottom: 12px;
}

/* ===== ATTACHMENTS (Detail) ===== */
.gmail-detail-attachments {
  padding: 12px;
  background: rgba(255,255,255,0.02);
  border: 1px solid rgba(255,255,255,0.06);
  border-radius: 8px;
}
.gmail-attach-header {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 11px;
  font-weight: 600;
  color: rgba(255,255,255,0.5);
}
.gmail-lock-badge {
  font-size: 10px;
  color: #fbbc05;
  background: rgba(251,188,5,0.1);
  padding: 2px 6px;
  border-radius: 4px;
}

.gmail-attach-chip {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 6px 10px;
  font-size: 12px;
  font-weight: 600;
  border-radius: 6px;
  border: 1px solid;
}
.gmail-chip-gc { color: #fbbc05; border-color: rgba(251,188,5,0.2); background: rgba(251,188,5,0.06); }
.gmail-chip-crypto { color: #4fc3f7; border-color: rgba(79,195,247,0.2); background: rgba(79,195,247,0.06); }
.gmail-chip-energy { color: #66bb6a; border-color: rgba(102,187,106,0.2); background: rgba(102,187,106,0.06); }
.gmail-chip-internet { color: #ab47bc; border-color: rgba(171,71,188,0.2); background: rgba(171,71,188,0.06); }
.gmail-chip-item { color: #ff7043; border-color: rgba(255,112,67,0.2); background: rgba(255,112,67,0.06); }

.gmail-btn-claim {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 6px;
  width: 100%;
  padding: 8px;
  background: #34a853;
  color: white;
  font-size: 12px;
  font-weight: 700;
  border-radius: 6px;
  transition: all 0.15s;
}
.gmail-btn-claim:hover { background: #2e9748; }
.gmail-btn-claim:disabled { opacity: 0.4; }

.gmail-btn-primary {
  padding: 6px 12px;
  background: #4285f4;
  color: white;
  font-size: 12px;
  font-weight: 700;
  border-radius: 4px;
  transition: background 0.15s;
}
.gmail-btn-primary:hover { background: #5a95f5; }
.gmail-btn-primary:disabled { opacity: 0.4; }

/* ===== COMPOSE VIEW ===== */
.gmail-compose {
  margin: 12px;
  border: 1px solid rgba(255,255,255,0.08);
  border-radius: 8px;
  overflow: hidden;
  background: #1e1e38;
  box-shadow: 0 4px 16px rgba(0,0,0,0.2);
  display: flex;
  flex-direction: column;
  min-height: calc(100% - 24px);
}
.gmail-compose-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 8px 12px;
  background: #2a2a4a;
  border-bottom: 1px solid rgba(255,255,255,0.06);
}
.gmail-compose-body {
  padding: 8px 12px 12px;
  flex: 1;
  display: flex;
  flex-direction: column;
}
.gmail-compose-field {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 6px 0;
  border-bottom: 1px solid rgba(255,255,255,0.04);
}
.gmail-compose-field label {
  font-size: 11px;
  color: rgba(255,255,255,0.35);
  width: 50px;
  shrink: 0;
}

.gmail-input {
  flex: 1;
  background: transparent;
  border: none;
  outline: none;
  font-size: 12px;
  color: rgba(255,255,255,0.85);
  padding: 4px 0;
}
.gmail-input::placeholder {
  color: rgba(255,255,255,0.2);
}

.gmail-textarea {
  width: 100%;
  background: transparent;
  border: none;
  outline: none;
  font-size: 13px;
  color: rgba(255,255,255,0.85);
  padding: 8px 0;
  resize: none;
  min-height: 100px;
  flex: 1;
}
.gmail-textarea::placeholder {
  color: rgba(255,255,255,0.2);
}

.gmail-compose-extras {
  display: flex;
  gap: 8px;
  padding: 6px 0;
  border-top: 1px solid rgba(255,255,255,0.04);
}
.gmail-extra-btn {
  display: flex;
  align-items: center;
  gap: 4px;
  font-size: 11px;
  color: rgba(255,255,255,0.3);
  padding: 4px 8px;
  border-radius: 4px;
  transition: all 0.15s;
}
.gmail-extra-btn:hover { color: rgba(255,255,255,0.6); background: rgba(255,255,255,0.04); }
.gmail-extra-btn-active { color: #f48fb1; background: rgba(194,24,91,0.1); }

.gmail-compose-attachments {
  padding: 8px;
  background: rgba(255,255,255,0.02);
  border: 1px solid rgba(255,255,255,0.04);
  border-radius: 6px;
  margin-bottom: 8px;
}
.gmail-attach-field {
  display: flex;
  flex-direction: column;
  gap: 2px;
}
.gmail-attach-field label {
  font-size: 9px;
  color: rgba(255,255,255,0.35);
  text-transform: uppercase;
  letter-spacing: 0.5px;
}
.gmail-attach-field .gmail-input {
  background: rgba(0,0,0,0.2);
  border: 1px solid rgba(255,255,255,0.06);
  border-radius: 4px;
  padding: 6px 8px;
}

.gmail-compose-footer {
  display: flex;
  align-items: center;
  gap: 12px;
  padding-top: 8px;
  margin-top: auto;
}
.gmail-btn-send {
  padding: 8px 24px;
  background: #4285f4;
  color: white;
  font-size: 13px;
  font-weight: 700;
  border-radius: 4px;
  transition: all 0.15s;
}
.gmail-btn-send:hover { background: #5a95f5; box-shadow: 0 1px 4px rgba(66,133,244,0.3); }
.gmail-btn-send:disabled { opacity: 0.35; }

/* ===== ATTACHED CHIPS (compose) ===== */
.fp-attached-chips {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
  padding: 6px 0;
}
.fp-chip {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 4px 8px;
  font-size: 11px;
  border-radius: 4px;
  border: 1px solid;
}
.fp-chip-amount { font-weight: 600; }
.fp-chip-remove {
  font-size: 9px;
  color: rgba(255,255,255,0.3);
  margin-left: 2px;
  transition: color 0.15s;
}
.fp-chip-remove:hover { color: #ea4335; }

/* ===== FILE PICKER DIALOG ===== */
.fp-dialog {
  width: 100%;
  max-width: 420px;
  background: #1e1e36;
  border: 1px solid rgba(255,255,255,0.12);
  border-radius: 8px;
  overflow: hidden;
  box-shadow: 0 16px 48px rgba(0,0,0,0.5), 0 0 0 1px rgba(255,255,255,0.05);
  font-family: 'Segoe UI', 'Consolas', monospace;
}

/* Title bar */
.fp-titlebar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 6px 10px;
  background: linear-gradient(180deg, #2d2d50 0%, #252545 100%);
  border-bottom: 1px solid rgba(255,255,255,0.08);
  font-size: 11px;
  font-weight: 600;
  color: rgba(255,255,255,0.7);
}
.fp-close-btn {
  width: 20px;
  height: 20px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 10px;
  color: rgba(255,255,255,0.4);
  border-radius: 3px;
  transition: all 0.15s;
}
.fp-close-btn:hover { background: #ea4335; color: white; }

/* Location bar */
.fp-location-bar {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 5px 10px;
  background: rgba(255,255,255,0.02);
  border-bottom: 1px solid rgba(255,255,255,0.06);
}
.fp-location-label {
  font-size: 10px;
  color: rgba(255,255,255,0.35);
  white-space: nowrap;
}
.fp-location-path {
  flex: 1;
  display: flex;
  align-items: center;
  gap: 4px;
  padding: 3px 8px;
  background: rgba(0,0,0,0.2);
  border: 1px solid rgba(255,255,255,0.08);
  border-radius: 3px;
  font-size: 11px;
  color: rgba(255,255,255,0.6);
}

/* File list */
.fp-file-list {
  margin: 6px;
  background: rgba(0,0,0,0.15);
  border: 1px solid rgba(255,255,255,0.06);
  border-radius: 4px;
  overflow: hidden;
}
.fp-file-header {
  display: grid;
  grid-template-columns: 28px 1fr 70px 60px 60px;
  padding: 4px 8px;
  font-size: 9px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.5px;
  color: rgba(255,255,255,0.25);
  border-bottom: 1px solid rgba(255,255,255,0.06);
  background: rgba(255,255,255,0.02);
}
.fp-file-row {
  display: grid;
  grid-template-columns: 28px 1fr 70px 60px 60px;
  align-items: center;
  padding: 6px 8px;
  cursor: pointer;
  transition: background 0.1s;
  border-bottom: 1px solid rgba(255,255,255,0.02);
}
.fp-file-row:last-child { border-bottom: none; }
.fp-file-row:hover { background: rgba(255,255,255,0.04); }
.fp-file-selected {
  background: rgba(66,133,244,0.15) !important;
  outline: 1px solid rgba(66,133,244,0.3);
  outline-offset: -1px;
}

.fp-col-icon { font-size: 14px; text-align: center; }
.fp-col-name { font-size: 11px; color: rgba(255,255,255,0.7); }
.fp-col-size { font-size: 11px; font-weight: 600; text-align: right; padding-right: 8px; }
.fp-col-type { font-size: 10px; color: rgba(255,255,255,0.3); }
.fp-filename { font-family: 'Consolas', 'Courier New', monospace; }
.fp-col-weight { font-size: 9px; color: rgba(255,255,255,0.2); text-align: right; padding-right: 4px; }

/* Bottom controls */
.fp-bottom {
  padding: 8px 10px 10px;
  border-top: 1px solid rgba(255,255,255,0.06);
  display: flex;
  flex-direction: column;
  gap: 6px;
}
.fp-field-row {
  display: flex;
  align-items: center;
  gap: 8px;
}
.fp-field-row label {
  font-size: 10px;
  color: rgba(255,255,255,0.35);
  width: 65px;
  text-align: right;
  white-space: nowrap;
}
.fp-selected-display {
  flex: 1;
  padding: 4px 8px;
  background: rgba(0,0,0,0.2);
  border: 1px solid rgba(255,255,255,0.08);
  border-radius: 3px;
  font-size: 11px;
  color: rgba(255,255,255,0.6);
  font-family: 'Consolas', 'Courier New', monospace;
  min-height: 24px;
}
.fp-amount-input {
  flex: 1;
  padding: 4px 8px;
  background: rgba(0,0,0,0.2);
  border: 1px solid rgba(255,255,255,0.08);
  border-radius: 3px;
  font-size: 11px;
  color: rgba(255,255,255,0.85);
  outline: none;
  transition: border-color 0.15s;
}
.fp-amount-input:focus { border-color: rgba(66,133,244,0.5); }
.fp-amount-input:disabled { opacity: 0.3; }
.fp-amount-input::placeholder { color: rgba(255,255,255,0.2); }

.fp-actions {
  display: flex;
  justify-content: flex-end;
  gap: 6px;
  margin-top: 4px;
}
.fp-btn-attach {
  padding: 5px 16px;
  background: #4285f4;
  color: white;
  font-size: 11px;
  font-weight: 700;
  border-radius: 4px;
  transition: all 0.15s;
}
.fp-btn-attach:hover { background: #5a95f5; }
.fp-btn-attach:disabled { opacity: 0.35; cursor: default; }
.fp-btn-cancel {
  padding: 5px 16px;
  background: transparent;
  border: 1px solid rgba(255,255,255,0.1);
  color: rgba(255,255,255,0.5);
  font-size: 11px;
  border-radius: 4px;
  transition: all 0.15s;
}
.fp-btn-cancel:hover { background: rgba(255,255,255,0.04); color: rgba(255,255,255,0.7); }

/* ===== FOOTER ===== */
.gmail-footer {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 4px 12px;
  font-size: 9px;
  color: rgba(255,255,255,0.15);
  border-top: 1px solid rgba(255,255,255,0.04);
  background: #1a1a2e;
}
</style>
