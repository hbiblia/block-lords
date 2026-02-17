import { defineStore } from 'pinia';
import { ref, computed } from 'vue';
import { supabase } from '@/utils/supabase';
import { useAuthStore } from './auth';
import { useGiftsStore } from './gifts';
import { isTabLocked } from '@/composables/useTabLock';
import { updatePlayerHeartbeat, pingApi, connectionState } from '@/utils/api';

export const useRealtimeStore = defineStore('realtime', () => {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const channels = ref<Map<string, any>>(new Map());
  const connected = ref(false);
  const wasConnected = ref(false);
  const reconnecting = ref(false);
  const reconnectAttempts = ref(0);
  const maxReconnectAttempts = 10;
  // Track per-channel errors to avoid nuclear reconnection
  const channelErrors = ref<Map<string, number>>(new Map());
  let reconnectTimeout: number | null = null;
  let heartbeatInterval: number | null = null;
  let visibilityHandler: (() => void) | null = null;
  let onlineHandler: (() => void) | null = null;
  let offlineHandler: (() => void) | null = null;
  let focusHandler: (() => void) | null = null;
  let blurHandler: (() => void) | null = null;

  const isConnected = computed(() => connected.value);
  const showDisconnectedModal = computed(() => {
    if (!wasConnected.value) return false;
    if (connected.value) return false;
    return reconnectAttempts.value >= 3 || !reconnecting.value;
  });

  // --- Heartbeat ---
  function startHeartbeat() {
    stopHeartbeat();
    heartbeatInterval = window.setInterval(() => {
      if (connected.value && channels.value.size > 0) {
        let hasActiveChannel = false;
        channels.value.forEach((channel) => {
          if (channel.state === 'joined' || channel.state === 'joining') {
            hasActiveChannel = true;
          }
        });

        if (!hasActiveChannel && wasConnected.value) {
          console.warn('Heartbeat: No hay canales activos, reconectando...');
          handleFullReconnect();
        }
      }
    }, 30000);
  }

  function stopHeartbeat() {
    if (heartbeatInterval) {
      clearInterval(heartbeatInterval);
      heartbeatInterval = null;
    }
  }

  // --- Visibility & Network Handlers ---
  function setupVisibilityHandler() {
    if (visibilityHandler) return;

    visibilityHandler = () => {
      if (isTabLocked.value) return;
      if (document.visibilityState === 'visible') {
        // Ping first: verify connection before firing all handlers
        pingApi().then(({ success }) => {
          if (!success) {
            console.warn('Ping failed on tab return, skipping reconnection');
            return;
          }

          const authStore = useAuthStore();

          if (authStore.player?.id) {
            updatePlayerHeartbeat(authStore.player.id).catch(err => {
              console.warn('Failed to update heartbeat on visibility change:', err);
            });
          }

          if (wasConnected.value && !connected.value) {
            manualReconnect();
          } else if (connected.value) {
            checkAndReconnectStaleChannels();
          }
        });
      }
    };

    document.addEventListener('visibilitychange', visibilityHandler);
  }

  function setupNetworkHandlers() {
    if (onlineHandler) return;

    onlineHandler = () => {
      if (isTabLocked.value) return;
      if (wasConnected.value && !connected.value) {
        setTimeout(() => {
          if (!isTabLocked.value) manualReconnect();
        }, 1000);
      }
    };

    offlineHandler = () => {
      connected.value = false;
    };

    window.addEventListener('online', onlineHandler);
    window.addEventListener('offline', offlineHandler);
  }

  function setupFocusHandlers() {
    if (focusHandler) return;

    focusHandler = () => {
      if (isTabLocked.value) return;
      // Skip if connection already verified offline (visibility handler runs first)
      if (!connectionState.isOnline) return;

      const authStore = useAuthStore();

      if (authStore.player?.id) {
        updatePlayerHeartbeat(authStore.player.id).catch(err => {
          console.warn('Failed to update heartbeat on focus:', err);
        });
      }

      if (wasConnected.value) {
        if (!connected.value) {
          manualReconnect();
        } else {
          checkAndReconnectStaleChannels();
        }
      }
    };

    blurHandler = () => {};

    window.addEventListener('focus', focusHandler);
    window.addEventListener('blur', blurHandler);
  }

  // Check individual channels and reconnect only the ones that are stale
  function checkAndReconnectStaleChannels() {
    const authStore = useAuthStore();
    if (!authStore.player?.id) return;

    const staleChannels: string[] = [];
    channels.value.forEach((channel, name) => {
      if (channel.state !== 'joined' && channel.state !== 'joining') {
        staleChannels.push(name);
      }
    });

    if (staleChannels.length > 0) {
      console.warn(`Reconectando ${staleChannels.length} canal(es) inactivos:`, staleChannels);
      for (const name of staleChannels) {
        reconnectSingleChannel(name, authStore.player.id);
      }
    }
  }

  function cleanupHandlers() {
    stopHeartbeat();

    if (visibilityHandler) {
      document.removeEventListener('visibilitychange', visibilityHandler);
      visibilityHandler = null;
    }
    if (onlineHandler) {
      window.removeEventListener('online', onlineHandler);
      onlineHandler = null;
    }
    if (offlineHandler) {
      window.removeEventListener('offline', offlineHandler);
      offlineHandler = null;
    }
    if (focusHandler) {
      window.removeEventListener('focus', focusHandler);
      focusHandler = null;
    }
    if (blurHandler) {
      window.removeEventListener('blur', blurHandler);
      blurHandler = null;
    }
  }

  // --- Per-channel error handling (granular, not nuclear) ---
  function handleChannelError(channelName: string) {
    const errors = (channelErrors.value.get(channelName) ?? 0) + 1;
    channelErrors.value.set(channelName, errors);

    if (errors >= 3) {
      // After 3 failures for the same channel, do a full reconnect
      console.error(`Canal "${channelName}" falló ${errors} veces, reconexión completa...`);
      handleFullReconnect();
      return;
    }

    const delay = Math.min(1000 * Math.pow(1.5, errors), 10000);
    console.warn(`Canal "${channelName}" error (intento ${errors}), reconectando en ${delay / 1000}s...`);

    const authStore = useAuthStore();
    if (!authStore.player?.id) return;

    setTimeout(() => {
      if (!isTabLocked.value) {
        reconnectSingleChannel(channelName, authStore.player!.id);
      }
    }, delay);
  }

  // Reconnect a single channel without touching the others
  function reconnectSingleChannel(channelName: string, playerId: string) {
    const oldChannel = channels.value.get(channelName);
    if (oldChannel) {
      supabase.removeChannel(oldChannel);
      channels.value.delete(channelName);
    }

    // Re-subscribe based on channel name
    if (channelName === 'private') {
      subscribePrivateChannel(playerId);
    } else if (channelName === 'global') {
      subscribeGlobalChannel(playerId);
    } else if (channelName.startsWith('market:')) {
      const itemType = channelName.replace('market:', '');
      subscribeToMarketOrders(itemType);
    }
  }

  // --- Full reconnect (only when multiple channels fail) ---
  function handleFullReconnect() {
    connected.value = false;

    if (isTabLocked.value) return;

    if (reconnectAttempts.value < maxReconnectAttempts) {
      reconnecting.value = true;
      reconnectAttempts.value++;

      const delay = Math.min(1000 * Math.pow(1.5, reconnectAttempts.value), 15000);
      console.log(`Reconexión completa en ${delay / 1000}s (intento ${reconnectAttempts.value}/${maxReconnectAttempts})`);

      if (reconnectTimeout) {
        clearTimeout(reconnectTimeout);
      }

      reconnectTimeout = window.setTimeout(() => {
        disconnect(false);
        connect();
      }, delay);
    } else {
      console.error('Se agotaron los intentos de reconexión, recargando página...');
      window.location.reload();
    }
  }

  function manualReconnect() {
    reconnectAttempts.value = 0;
    channelErrors.value.clear();
    reconnecting.value = true;
    disconnect(false);
    connect();
  }

  // --- Main connect: 2 multiplexed channels instead of 7 ---
  function connect() {
    const authStore = useAuthStore();

    if (!authStore.player?.id) {
      console.warn('No player ID for realtime connection');
      return;
    }

    const playerId = authStore.player.id;

    // Channel 1: Private — all player-specific subscriptions
    subscribePrivateChannel(playerId);

    // Channel 2: Global — blocks + network_stats
    subscribeGlobalChannel(playerId);

    connected.value = true;
    wasConnected.value = true;
    reconnecting.value = false;
    reconnectAttempts.value = 0;
    channelErrors.value.clear();

    startHeartbeat();
    setupVisibilityHandler();
    setupNetworkHandlers();
    setupFocusHandlers();
  }

  // --- Channel 1: Private (player, rigs, cooling, pending_blocks, gifts) ---
  function subscribePrivateChannel(playerId: string) {
    const channel = supabase
      .channel(`private:${playerId}`)
      // Player updates
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
      // Rig INSERT/DELETE only (skip UPDATE to avoid game_tick flood)
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'player_rigs',
          filter: `player_id=eq.${playerId}`,
        },
        (payload) => {
          console.log('Rig cambio: INSERT');
          window.dispatchEvent(
            new CustomEvent('player-rigs-updated', { detail: payload })
          );
        }
      )
      .on(
        'postgres_changes',
        {
          event: 'DELETE',
          schema: 'public',
          table: 'player_rigs',
          filter: `player_id=eq.${playerId}`,
        },
        (payload) => {
          console.log('Rig cambio: DELETE');
          window.dispatchEvent(
            new CustomEvent('player-rigs-updated', { detail: payload })
          );
        }
      )
      // Rig cooling — WITH player filter
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'rig_cooling',
          filter: `player_id=eq.${playerId}`,
        },
        (payload) => {
          console.log('Cooling cambio: INSERT');
          window.dispatchEvent(
            new CustomEvent('rig-cooling-updated', { detail: payload })
          );
        }
      )
      .on(
        'postgres_changes',
        {
          event: 'DELETE',
          schema: 'public',
          table: 'rig_cooling',
          filter: `player_id=eq.${playerId}`,
        },
        (payload) => {
          console.log('Cooling cambio: DELETE');
          window.dispatchEvent(
            new CustomEvent('rig-cooling-updated', { detail: payload })
          );
        }
      )
      // Pending blocks
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'pending_blocks',
          filter: `player_id=eq.${playerId}`,
        },
        (payload) => {
          const pendingBlock = payload.new;

          window.dispatchEvent(
            new CustomEvent('pending-block-created', {
              detail: {
                id: pendingBlock.id,
                block_id: pendingBlock.block_id,
                reward: pendingBlock.reward,
                is_premium: pendingBlock.is_premium,
                is_pity: pendingBlock.is_pity,
                materials_dropped: pendingBlock.materials_dropped || [],
                created_at: pendingBlock.created_at,
              },
            })
          );
        }
      )
      // Player shares (mining)
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'player_shares',
          filter: `player_id=eq.${playerId}`,
        },
        () => {
          window.dispatchEvent(new CustomEvent('player-shares-updated'));
        }
      )
      // Player gifts
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'player_gifts',
          filter: `player_id=eq.${playerId}`,
        },
        () => {
          const giftsStore = useGiftsStore();
          giftsStore.fetchGifts();
        }
      )
      .subscribe((status) => {
        if (status === 'SUBSCRIBED') {
          console.log('Canal privado conectado');
          connected.value = true;
          reconnecting.value = false;
          reconnectAttempts.value = 0;
          channelErrors.value.delete('private');
        } else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') {
          console.error('Error en canal privado:', status);
          handleChannelError('private');
        } else if (status === 'CLOSED') {
          connected.value = false;
        }
      });

    channels.value.set('private', channel);
  }

  // --- Channel 2: Global (blocks + network_stats) ---
  function subscribeGlobalChannel(_playerId: string) {
    const channel = supabase
      .channel('global')
      // New blocks mined
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'blocks',
        },
        async (payload) => {
          const block = payload.new;

          const { data: miner } = await supabase
            .from('players')
            .select('id, username')
            .eq('id', block.miner_id)
            .single();

          window.dispatchEvent(
            new CustomEvent('block-mined', {
              detail: { block, winner: miner },
            })
          );
        }
      )
      // Network stats
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
      .subscribe((status) => {
        if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') {
          console.error('Error en canal global:', status);
          handleChannelError('global');
        }
      });

    channels.value.set('global', channel);
  }

  // --- Disconnect ---
  function disconnect(full = true) {
    channels.value.forEach((channel) => {
      supabase.removeChannel(channel);
    });
    channels.value.clear();
    connected.value = false;

    if (full) {
      cleanupHandlers();
      wasConnected.value = false;
      channelErrors.value.clear();
    }
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
          handleChannelError(channelName);
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
