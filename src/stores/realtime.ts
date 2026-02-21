import { defineStore } from 'pinia';
import { ref, computed } from 'vue';
import { supabase } from '@/utils/supabase';

export const useRealtimeStore = defineStore('realtime', () => {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const channels = ref<Map<string, any>>(new Map());
  const connected = ref(false);

  const isConnected = computed(() => connected.value);

  // --- Connect / Disconnect (state management) ---
  function connect() {
    connected.value = true;
  }

  function disconnect() {
    // Remove all channels (market, etc.)
    channels.value.forEach((channel) => {
      supabase.removeChannel(channel);
    });
    channels.value.clear();
    connected.value = false;
  }

  // --- Market orders (on-demand, separate channel) ---
  function subscribeToMarketOrders(itemType: string) {
    const channelName = `market:${itemType}`;

    if (channels.value.has(channelName)) return;

    const channel = supabase
      .channel(channelName)
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'market_orders',
          filter: `item_type=eq.${itemType}`,
        },
        (payload) => {
          window.dispatchEvent(
            new CustomEvent('market-order-changed', {
              detail: { itemType, payload },
            })
          );
        }
      )
      .subscribe((status) => {
        if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') {
          console.error('Error en canal de market:', status);
        }
      });

    channels.value.set(channelName, channel);
  }

  function unsubscribeFromMarketOrders(itemType: string) {
    const channelName = `market:${itemType}`;
    const channel = channels.value.get(channelName);

    if (channel) {
      supabase.removeChannel(channel);
      channels.value.delete(channelName);
    }
  }

  function manualReconnect() {
    disconnect();
    connect();
  }

  return {
    channels,
    connected,
    isConnected,
    connect,
    disconnect,
    manualReconnect,
    subscribeToMarketOrders,
    unsubscribeFromMarketOrders,
  };
});
