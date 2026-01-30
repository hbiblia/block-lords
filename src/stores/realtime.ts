import { defineStore } from 'pinia';
import { ref, computed } from 'vue';
import { supabase } from '@/utils/supabase';
import { useAuthStore } from './auth';

export const useRealtimeStore = defineStore('realtime', () => {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const channels = ref<Map<string, any>>(new Map());
  const connected = ref(false);
  const wasConnected = ref(false); // Track if we were ever connected
  const reconnecting = ref(false);
  const reconnectAttempts = ref(0);
  const maxReconnectAttempts = 5;
  let reconnectTimeout: number | null = null;

  const isConnected = computed(() => connected.value);
  const showDisconnectedModal = computed(() => wasConnected.value && !connected.value && !reconnecting.value);

  function connect() {
    const authStore = useAuthStore();

    if (!authStore.player?.id) {
      console.warn('No player ID for realtime connection');
      return;
    }

    // Suscribirse a cambios en el jugador actual
    subscribeToPlayer(authStore.player.id);

    // Suscribirse a cambios en los rigs del jugador
    subscribeToPlayerRigs(authStore.player.id);

    // Suscribirse a cambios en el cooling de rigs
    subscribeToRigCooling(authStore.player.id);

    // Suscribirse a nuevos bloques
    subscribeToBlocks();

    // Suscribirse a stats de la red
    subscribeToNetworkStats();

    connected.value = true;
    wasConnected.value = true;
    reconnecting.value = false;
    reconnectAttempts.value = 0;
  }

  function handleChannelError() {
    connected.value = false;

    if (reconnectAttempts.value < maxReconnectAttempts) {
      reconnecting.value = true;
      reconnectAttempts.value++;

      const delay = Math.min(1000 * Math.pow(2, reconnectAttempts.value), 30000);
      console.log(`Intentando reconectar en ${delay / 1000}s (intento ${reconnectAttempts.value}/${maxReconnectAttempts})`);

      if (reconnectTimeout) {
        clearTimeout(reconnectTimeout);
      }

      reconnectTimeout = window.setTimeout(() => {
        disconnect();
        connect();
      }, delay);
    } else {
      reconnecting.value = false;
      console.error('Se agotaron los intentos de reconexión');
    }
  }

  function manualReconnect() {
    reconnectAttempts.value = 0;
    reconnecting.value = true;
    disconnect();
    connect();
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
          connected.value = true;
          reconnecting.value = false;
          reconnectAttempts.value = 0;
        } else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') {
          console.error('Error en canal del jugador:', status);
          handleChannelError();
        } else if (status === 'CLOSED') {
          connected.value = false;
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

  function subscribeToPlayerRigs(playerId: string) {
    const channel = supabase
      .channel(`player_rigs:${playerId}`)
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'player_rigs',
          filter: `player_id=eq.${playerId}`,
        },
        (payload) => {
          console.log('Rig actualizado:', payload.eventType);
          window.dispatchEvent(
            new CustomEvent('player-rigs-updated', {
              detail: payload,
            })
          );
        }
      )
      .subscribe((status: string) => {
        if (status === 'SUBSCRIBED') {
          console.log('Suscrito a cambios de rigs');
        }
      });

    channels.value.set(`player_rigs:${playerId}`, channel);
  }

  function subscribeToRigCooling(playerId: string) {
    const channel = supabase
      .channel(`rig_cooling:${playerId}`)
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'rig_cooling',
        },
        (payload) => {
          console.log('Cooling actualizado:', payload.eventType);
          window.dispatchEvent(
            new CustomEvent('rig-cooling-updated', {
              detail: payload,
            })
          );
        }
      )
      .subscribe((status: string) => {
        if (status === 'SUBSCRIBED') {
          console.log('Suscrito a cambios de cooling');
        }
      });

    channels.value.set(`rig_cooling:${playerId}`, channel);
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
    showDisconnectedModal,
    reconnecting,
    connect,
    disconnect,
    manualReconnect,
    subscribeToMarketOrders,
    unsubscribeFromMarketOrders,
  };
});
