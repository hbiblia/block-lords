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
  const maxReconnectAttempts = 10;
  let reconnectTimeout: number | null = null;
  let heartbeatInterval: number | null = null;
  let visibilityHandler: (() => void) | null = null;
  let onlineHandler: (() => void) | null = null;
  let offlineHandler: (() => void) | null = null;
  let focusHandler: (() => void) | null = null;
  let blurHandler: (() => void) | null = null;

  const isConnected = computed(() => connected.value);
  // Mostrar modal si: estábamos conectados, ya no lo estamos, y han pasado varios intentos de reconexión
  // O si la reconexión falló completamente
  const showDisconnectedModal = computed(() => {
    if (!wasConnected.value) return false;
    if (connected.value) return false;
    // Mostrar después de 3 intentos fallidos O si ya no está reconectando (falló todo)
    return reconnectAttempts.value >= 3 || !reconnecting.value;
  });

  // Heartbeat para detectar conexiones zombie
  function startHeartbeat() {
    stopHeartbeat();
    heartbeatInterval = window.setInterval(() => {
      if (connected.value && channels.value.size > 0) {
        // Verificar si algún canal está en estado problemático
        let hasActiveChannel = false;
        channels.value.forEach((channel) => {
          if (channel.state === 'joined' || channel.state === 'joining') {
            hasActiveChannel = true;
          }
        });

        if (!hasActiveChannel && wasConnected.value) {
          console.warn('Heartbeat: No hay canales activos, reconectando...');
          handleChannelError();
        }
      }
    }, 30000); // Check every 30 seconds
  }

  function stopHeartbeat() {
    if (heartbeatInterval) {
      clearInterval(heartbeatInterval);
      heartbeatInterval = null;
    }
  }

  // Manejar visibilidad del documento (cuando el usuario cambia de pestaña)
  function setupVisibilityHandler() {
    if (visibilityHandler) return;

    visibilityHandler = () => {
      if (document.visibilityState === 'visible') {
        console.log('Página visible, verificando conexión...');
        // Si estábamos conectados pero ya no lo estamos, reconectar
        if (wasConnected.value && !connected.value) {
          manualReconnect();
        } else if (connected.value) {
          // Verificar que los canales sigan activos
          let needsReconnect = false;
          channels.value.forEach((channel) => {
            if (channel.state !== 'joined' && channel.state !== 'joining') {
              needsReconnect = true;
            }
          });
          if (needsReconnect) {
            console.log('Canales en mal estado, reconectando...');
            manualReconnect();
          }
        }
      }
    };

    document.addEventListener('visibilitychange', visibilityHandler);
  }

  // Manejar eventos de red online/offline
  function setupNetworkHandlers() {
    if (onlineHandler) return;

    onlineHandler = () => {
      console.log('Conexión de red restaurada');
      if (wasConnected.value && !connected.value) {
        // Esperar un momento para que la red se estabilice
        setTimeout(() => {
          manualReconnect();
        }, 1000);
      }
    };

    offlineHandler = () => {
      console.log('Conexión de red perdida');
      connected.value = false;
    };

    window.addEventListener('online', onlineHandler);
    window.addEventListener('offline', offlineHandler);
  }

  // Manejar eventos de focus/blur de la ventana (diferente de visibilitychange)
  function setupFocusHandlers() {
    if (focusHandler) return;

    focusHandler = () => {
      console.log('Ventana recuperó el foco, verificando conexión...');
      // Verificar inmediatamente el estado de los canales
      if (wasConnected.value) {
        let needsReconnect = false;

        // Si no estamos conectados, reconectar
        if (!connected.value) {
          needsReconnect = true;
        } else {
          // Verificar que los canales sigan activos
          channels.value.forEach((channel) => {
            if (channel.state !== 'joined' && channel.state !== 'joining') {
              needsReconnect = true;
            }
          });
        }

        if (needsReconnect) {
          console.log('Reconectando después de recuperar foco...');
          manualReconnect();
        }
      }
    };

    blurHandler = () => {
      // Cuando la ventana pierde foco, el navegador puede throttle la conexión
      // Solo logueamos para debug, no desconectamos activamente
      console.log('Ventana perdió el foco');
    };

    window.addEventListener('focus', focusHandler);
    window.addEventListener('blur', blurHandler);
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

    // Suscribirse a bloques pendientes (incluye pity blocks)
    subscribeToPendingBlocks(authStore.player.id);

    // Suscribirse a stats de la red
    subscribeToNetworkStats();

    connected.value = true;
    wasConnected.value = true;
    reconnecting.value = false;
    reconnectAttempts.value = 0;

    // Iniciar heartbeat y handlers
    startHeartbeat();
    setupVisibilityHandler();
    setupNetworkHandlers();
    setupFocusHandlers();
  }

  function handleChannelError() {
    connected.value = false;

    if (reconnectAttempts.value < maxReconnectAttempts) {
      reconnecting.value = true;
      reconnectAttempts.value++;

      const delay = Math.min(1000 * Math.pow(1.5, reconnectAttempts.value), 15000);
      console.log(`Intentando reconectar en ${delay / 1000}s (intento ${reconnectAttempts.value}/${maxReconnectAttempts})`);

      if (reconnectTimeout) {
        clearTimeout(reconnectTimeout);
      }

      reconnectTimeout = window.setTimeout(() => {
        disconnect(false); // No limpiar handlers durante reconexión
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
    disconnect(false); // No limpiar handlers durante reconexión
    connect();
  }

  function disconnect(full = true) {
    channels.value.forEach((channel) => {
      supabase.removeChannel(channel);
    });
    channels.value.clear();
    connected.value = false;

    // Solo limpiar handlers en desconexión completa (logout)
    if (full) {
      cleanupHandlers();
      wasConnected.value = false;
    }
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
      .subscribe((status) => {
        if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') {
          console.error('Error en canal de bloques:', status);
          handleChannelError();
        }
      });

    channels.value.set('blocks', channel);
  }

  function subscribeToPendingBlocks(playerId: string) {
    const channel = supabase
      .channel(`pending_blocks:${playerId}`)
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

          // Emitir evento para nuevo bloque pendiente (incluye pity blocks)
          window.dispatchEvent(
            new CustomEvent('pending-block-created', {
              detail: {
                id: pendingBlock.id,
                block_id: pendingBlock.block_id,
                reward: pendingBlock.reward,
                is_premium: pendingBlock.is_premium,
                is_pity: pendingBlock.is_pity,
                created_at: pendingBlock.created_at,
              },
            })
          );
        }
      )
      .subscribe((status) => {
        if (status === 'SUBSCRIBED') {
          console.log('Suscrito a bloques pendientes');
        } else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') {
          console.error('Error en canal de pending_blocks:', status);
          handleChannelError();
        }
      });

    channels.value.set(`pending_blocks:${playerId}`, channel);
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
      .subscribe((status) => {
        if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') {
          console.error('Error en canal de network_stats:', status);
          handleChannelError();
        }
      });

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
          // Solo loguear INSERT/DELETE (no los UPDATE frecuentes del game_tick)
          if (payload.eventType !== 'UPDATE') {
            console.log('Rig cambio:', payload.eventType);
          }
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
        } else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') {
          console.error('Error en canal de rigs:', status);
          handleChannelError();
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
          // Solo loguear INSERT/DELETE (no los UPDATE frecuentes)
          if (payload.eventType !== 'UPDATE') {
            console.log('Cooling cambio:', payload.eventType);
          }
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
        } else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') {
          console.error('Error en canal de cooling:', status);
          handleChannelError();
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
