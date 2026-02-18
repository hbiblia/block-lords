import { defineStore } from 'pinia';
import { ref } from 'vue';
import {
  getFriends,
  getFriendRequests,
  sendFriendRequest,
  acceptFriendRequest,
  rejectFriendRequest,
  removeFriend,
} from '@/utils/api';
import { useAuthStore } from './auth';

export interface Friend {
  friendship_id: string;
  friend_id: string;
  username: string;
  created_at: string;
}

export interface FriendRequest {
  request_id: string;
  sender_id: string;
  sender_username: string;
  created_at: string;
}

export const useFriendsStore = defineStore('friends', () => {
  const friends = ref<Friend[]>([]);
  const requests = ref<FriendRequest[]>([]);
  const loading = ref(false);
  const error = ref<string | null>(null);

  async function fetchFriends() {
    const authStore = useAuthStore();
    if (!authStore.player?.id) return;
    try {
      const result = await getFriends(authStore.player.id);
      if (Array.isArray(result)) {
        friends.value = result;
      }
    } catch (e) {
      console.error('Error fetching friends:', e);
    }
  }

  async function fetchRequests() {
    const authStore = useAuthStore();
    if (!authStore.player?.id) return;
    try {
      const result = await getFriendRequests(authStore.player.id);
      if (Array.isArray(result)) {
        requests.value = result;
      }
    } catch (e) {
      console.error('Error fetching friend requests:', e);
    }
  }

  async function sendRequest(receiverUsername: string) {
    const authStore = useAuthStore();
    if (!authStore.player?.id) return null;
    error.value = null;
    try {
      const result = await sendFriendRequest(authStore.player.id, receiverUsername);
      if (result?.success) {
        await fetchFriends();
        await fetchRequests();
        return result;
      } else {
        error.value = result?.error || 'Error sending request';
        return null;
      }
    } catch (e: any) {
      error.value = e.message || 'Error sending request';
      return null;
    }
  }

  async function acceptRequest(requestId: string) {
    const authStore = useAuthStore();
    if (!authStore.player?.id) return null;
    error.value = null;
    try {
      const result = await acceptFriendRequest(authStore.player.id, requestId);
      if (result?.success) {
        await fetchFriends();
        await fetchRequests();
        return result;
      } else {
        error.value = result?.error || 'Error accepting request';
        return null;
      }
    } catch (e: any) {
      error.value = e.message || 'Error accepting request';
      return null;
    }
  }

  async function rejectRequest(requestId: string) {
    const authStore = useAuthStore();
    if (!authStore.player?.id) return null;
    try {
      const result = await rejectFriendRequest(authStore.player.id, requestId);
      if (result?.success) {
        await fetchRequests();
        return result;
      }
      return null;
    } catch (e) {
      console.error('Error rejecting request:', e);
      return null;
    }
  }

  async function deleteFriend(friendId: string) {
    const authStore = useAuthStore();
    if (!authStore.player?.id) return null;
    try {
      const result = await removeFriend(authStore.player.id, friendId);
      if (result?.success) {
        await fetchFriends();
        return result;
      }
      return null;
    } catch (e) {
      console.error('Error removing friend:', e);
      return null;
    }
  }

  return {
    friends,
    requests,
    loading,
    error,
    fetchFriends,
    fetchRequests,
    sendRequest,
    acceptRequest,
    rejectRequest,
    deleteFriend,
  };
});
