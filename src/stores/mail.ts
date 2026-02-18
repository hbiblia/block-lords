import { defineStore } from 'pinia';
import { ref, computed } from 'vue';
import {
  getPlayerInbox,
  getPlayerSent,
  getMailUnreadCount,
  getMailStorage,
  readMail as apiReadMail,
  sendPlayerMail,
  sendSupportTicket,
  claimMailAttachment,
  deletePlayerMail,
} from '@/utils/api';
import { useAuthStore } from './auth';

export interface Mail {
  id: string;
  sender_id: string | null;
  sender_username: string;
  recipient_username?: string;
  subject: string;
  body: string | null;
  mail_type: 'player' | 'system' | 'admin' | 'ticket';
  attachment_gamecoin: number;
  attachment_crypto: number;
  attachment_energy: number;
  attachment_internet: number;
  attachment_item_type: string | null;
  attachment_item_id: string | null;
  attachment_item_quantity: number;
  has_password: boolean;
  has_attachment: boolean;
  is_read: boolean;
  is_claimed: boolean;
  size_kb: number;
  expires_at: string | null;
  created_at: string;
}

export interface MailClaimResult {
  success: boolean;
  gamecoin: number;
  crypto: number;
  energy: number;
  internet: number;
  itemType: string | null;
  itemId: string | null;
  itemQuantity: number;
}

export type MailView = 'inbox' | 'sent' | 'compose' | 'detail';

export const useMailStore = defineStore('mail', () => {
  const inbox = ref<Mail[]>([]);
  const sent = ref<Mail[]>([]);
  const unreadCount = ref(0);
  const selectedMail = ref<Mail | null>(null);
  const currentView = ref<MailView>('inbox');
  const loading = ref(false);
  const sending = ref(false);
  const claiming = ref(false);
  const error = ref<string | null>(null);
  const storageUsed = ref(0);
  const storageMax = ref(1024);

  let pollInterval: ReturnType<typeof setInterval> | null = null;

  const hasUnread = computed(() => unreadCount.value > 0);

  function playMailSound() {
    try {
      const ctx = new AudioContext();
      const now = ctx.currentTime;

      // Classic "You've got mail" two-tone chime
      const notes = [
        { freq: 784, start: 0, dur: 0.15 },     // G5
        { freq: 1047, start: 0.18, dur: 0.25 },  // C6
      ];

      for (const note of notes) {
        const osc = ctx.createOscillator();
        const gain = ctx.createGain();
        osc.type = 'sine';
        osc.frequency.value = note.freq;
        gain.gain.setValueAtTime(0.3, now + note.start);
        gain.gain.exponentialRampToValueAtTime(0.001, now + note.start + note.dur);
        osc.connect(gain);
        gain.connect(ctx.destination);
        osc.start(now + note.start);
        osc.stop(now + note.start + note.dur + 0.05);
      }

      setTimeout(() => ctx.close(), 1000);
    } catch {
      // Audio not available
    }
  }

  async function fetchInbox() {
    const authStore = useAuthStore();
    if (!authStore.player?.id) return;
    loading.value = true;
    try {
      const result = await getPlayerInbox(authStore.player.id);
      if (Array.isArray(result)) {
        inbox.value = result;
        fetchStorage();
      }
    } catch (e) {
      console.error('Error fetching inbox:', e);
    } finally {
      loading.value = false;
    }
  }

  async function fetchSent() {
    const authStore = useAuthStore();
    if (!authStore.player?.id) return;
    loading.value = true;
    try {
      const result = await getPlayerSent(authStore.player.id);
      if (Array.isArray(result)) {
        sent.value = result;
      }
    } catch (e) {
      console.error('Error fetching sent mail:', e);
    } finally {
      loading.value = false;
    }
  }

  async function fetchUnreadCount() {
    const authStore = useAuthStore();
    if (!authStore.player?.id) return;
    try {
      const result = await getMailUnreadCount(authStore.player.id);
      if (result?.success) {
        const prev = unreadCount.value;
        unreadCount.value = result.count;
        if (result.count > prev && prev >= 0) {
          playMailSound();
        }
      }
    } catch (e) {
      console.error('Error fetching unread count:', e);
    }
  }

  async function fetchStorage() {
    const authStore = useAuthStore();
    if (!authStore.player?.id) return;
    try {
      const result = await getMailStorage(authStore.player.id);
      if (result?.success) {
        storageUsed.value = result.used_kb;
        storageMax.value = result.max_kb;
      }
    } catch (e) {
      console.error('Error fetching mail storage:', e);
    }
  }

  async function markAsRead(mailId: string) {
    const authStore = useAuthStore();
    if (!authStore.player?.id) return;
    try {
      await apiReadMail(authStore.player.id, mailId);
      const mail = inbox.value.find(m => m.id === mailId);
      if (mail && !mail.is_read) {
        mail.is_read = true;
        unreadCount.value = Math.max(0, unreadCount.value - 1);
      }
    } catch (e) {
      console.error('Error marking mail as read:', e);
    }
  }

  async function sendMail(params: {
    recipientUsername: string;
    subject: string;
    body?: string;
    password?: string;
    gamecoin?: number;
    crypto?: number;
    energy?: number;
    internet?: number;
    itemType?: string;
    itemId?: string;
    itemQuantity?: number;
  }) {
    const authStore = useAuthStore();
    if (!authStore.player?.id) return null;
    sending.value = true;
    error.value = null;
    try {
      const result = await sendPlayerMail({
        senderId: authStore.player.id,
        ...params,
      });
      if (result?.success) {
        await authStore.fetchPlayer();
        fetchStorage();
        return result;
      } else {
        error.value = result?.error || 'Error sending mail';
        return null;
      }
    } catch (e: any) {
      error.value = e.message || 'Error sending mail';
      return null;
    } finally {
      sending.value = false;
    }
  }

  async function sendTicket(params: { subject: string; body?: string }) {
    const authStore = useAuthStore();
    if (!authStore.player?.id) return null;
    sending.value = true;
    error.value = null;
    try {
      const result = await sendSupportTicket(
        authStore.player.id,
        params.subject,
        params.body,
      );
      if (result?.success) {
        await authStore.fetchPlayer();
        return result;
      } else {
        error.value = result?.error || 'Error sending ticket';
        return null;
      }
    } catch (e: any) {
      error.value = e.message || 'Error sending ticket';
      return null;
    } finally {
      sending.value = false;
    }
  }

  async function claimAttachment(mailId: string, password?: string): Promise<MailClaimResult | null> {
    const authStore = useAuthStore();
    if (!authStore.player?.id) return null;
    claiming.value = true;
    error.value = null;
    try {
      const result = await claimMailAttachment(authStore.player.id, mailId, password);
      if (result?.success) {
        const mail = inbox.value.find(m => m.id === mailId);
        if (mail) mail.is_claimed = true;
        if (selectedMail.value?.id === mailId) {
          selectedMail.value = { ...selectedMail.value, is_claimed: true };
        }
        await authStore.fetchPlayer();
        return result;
      } else {
        error.value = result?.error || 'Error claiming attachment';
        return null;
      }
    } catch (e: any) {
      error.value = e.message || 'Error claiming attachment';
      return null;
    } finally {
      claiming.value = false;
    }
  }

  async function removeMail(mailId: string) {
    const authStore = useAuthStore();
    if (!authStore.player?.id) return;
    try {
      const result = await deletePlayerMail(authStore.player.id, mailId);
      if (result?.success) {
        inbox.value = inbox.value.filter(m => m.id !== mailId);
        sent.value = sent.value.filter(m => m.id !== mailId);
        if (selectedMail.value?.id === mailId) {
          selectedMail.value = null;
          currentView.value = 'inbox';
        }
        fetchStorage();
      }
    } catch (e) {
      console.error('Error deleting mail:', e);
    }
  }

  function selectMail(mail: Mail) {
    selectedMail.value = mail;
    currentView.value = 'detail';
    if (!mail.is_read) markAsRead(mail.id);
  }

  function openCompose() {
    currentView.value = 'compose';
    selectedMail.value = null;
    error.value = null;
  }

  function goToInbox() {
    currentView.value = 'inbox';
    selectedMail.value = null;
    error.value = null;
  }

  function goToSent() {
    currentView.value = 'sent';
    selectedMail.value = null;
    error.value = null;
    fetchSent();
  }

  function startPolling() {
    if (pollInterval) return;
    pollInterval = setInterval(() => fetchUnreadCount(), 60000);
  }

  function stopPolling() {
    if (pollInterval) {
      clearInterval(pollInterval);
      pollInterval = null;
    }
  }

  return {
    inbox,
    sent,
    unreadCount,
    selectedMail,
    currentView,
    loading,
    sending,
    claiming,
    error,
    storageUsed,
    storageMax,
    hasUnread,
    fetchInbox,
    fetchSent,
    fetchUnreadCount,
    fetchStorage,
    markAsRead,
    sendMail,
    sendTicket,
    claimAttachment,
    removeMail,
    selectMail,
    openCompose,
    goToInbox,
    goToSent,
    startPolling,
    stopPolling,
  };
});
