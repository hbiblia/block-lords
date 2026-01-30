import { defineStore } from 'pinia';
import { ref, computed } from 'vue';
import { supabase } from '@/utils/supabase';
import { useAuthStore } from './auth';

export const useRealtimeStore = defineStore('realtime', () => {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const channels = ref<Map<string, any>>(new Map());
  const connected = ref(false);

  const isConnected = computed(() => connected.value);

  function connect() {
    const authStore = useAuthStore();

    if (!authStore.player?.id) {
      console.warn('No player ID for realtime connection');
      return;
    }

    // Suscribirse a cambios en el jugador actual
    subscribeToPlayer(authStore.player.id);

    // Suscribirse a nuevos bloques
    subscribeToBlocks();

    // Suscribirse a stats de la red
    subscribeToNetworkStats();

    connected.value = true;
  }

  function disconnect() {
    channels.value.forEach((channel) => {
      supabase.removeChannel(channel);
    });
    channels.value.clear();
    connected.value = false;
  }

  function subscribeToPlayer(playerId: string) {
    const channel = supabase
      .channel(`player:${playerId}`)
      .on(
        'postgres_changes',
        {
          event: 'UPDATE',
          schema: 'public',
          table: 'players',
          filter: `id=eq.${playerId}`,
        },
        (payload) => {
          const authStore = useAuthStore();
          authStore.updatePlayer(payload.new as any);
        }
      )
      .subscribe((status) => {
        if (status === 'SUBSCRIBED') {
          console.log('Suscrito a cambios del jugador');
        }
      });

    channels.value.set(`player:${playerId}`, channel);
  }

  function subscribeToBlocks() {
    const channel = supabase
      .channel('blocks')
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'blocks',
        },
        async (payload) => {
          const block = payload.new;

          // Obtener info del minero
          const { data: miner } = await supabase
            .from('players')
            .select('id, username')
            .eq('id', block.miner_id)
            .single();

          // Emitir evento global
          window.dispatchEvent(
            new CustomEvent('block-mined', {
              detail: {
                block,
                winner: miner,
              },
            })
          );
        }
      )
      .subscribe();

    channels.value.set('blocks', channel);
  }

  function subscribeToNetworkStats() {
    const channel = supabase
      .channel('network_stats')
      .on(
        'postgres_changes',
        {
          event: 'UPDATE',
          schema: 'public',
          table: 'network_stats',
        },
        (payload) => {
          window.dispatchEvent(
            new CustomEvent('network-stats-updated', {
              detail: payload.new,
            })
          );
        }
      )
      .subscribe();

    channels.value.set('network_stats', channel);
  }

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
      .subscribe();

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

  return {
    channels,
    connected,
    isConnected,
    connect,
    disconnect,
    subscribeToMarketOrders,
    unsubscribeFromMarketOrders,
  };
});
