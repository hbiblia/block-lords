import { ref, computed, onUnmounted } from 'vue';
import { supabase } from '@/utils/supabase';
import { useAuthStore } from '@/stores/auth';
import {
  joinBattleLobby,
  leaveBattleLobby,
  acceptBattleChallenge,
  playBattleTurn,
  forfeitBattle,
  getBattleLobby,
} from '@/utils/api';
import { getCard, type CardDefinition, TURN_DURATION, BET_AMOUNT, MAX_ENERGY } from '@/utils/battleCards';
import { playSound } from '@/utils/sounds';

export interface LobbyEntry {
  id: string;
  player_id: string;
  username: string;
  bet_amount: number;
  created_at: string;
}

export interface BattleSession {
  id: string;
  player1_id: string;
  player2_id: string;
  current_turn: string;
  turn_number: number;
  turn_deadline: string;
  player1_hp: number;
  player2_hp: number;
  player1_shield: number;
  player2_shield: number;
  game_state: {
    player1Hand: string[];
    player2Hand: string[];
    player1Deck: string[];
    player2Deck: string[];
    player1Discard: string[];
    player2Discard: string[];
    player1Energy: number;
    player2Energy: number;
    player1Weakened: boolean;
    player2Weakened: boolean;
    lastAction: LogEntry[] | null;
  };
  status: string;
  winner_id: string | null;
}

export interface LogEntry {
  type: string;
  card: string;
  damage?: number;
  shield?: number;
  heal?: number;
  selfDamage?: number;
  counterDamage?: number;
  weaken?: number;
  draw?: number;
}

export function useCardBattle() {
  const authStore = useAuthStore();

  // Lobby state
  const lobbyEntries = ref<LobbyEntry[]>([]);
  const inLobby = ref(false);
  const lobbyLoading = ref(false);

  // Battle state
  const session = ref<BattleSession | null>(null);
  const myHand = ref<string[]>([]);
  const myHp = ref(100);
  const myShield = ref(0);
  const myEnergy = ref(MAX_ENERGY);
  const enemyHp = ref(100);
  const enemyShield = ref(0);
  const enemyUsername = ref('');
  const isMyTurn = ref(false);
  const turnTimer = ref(TURN_DURATION);
  const battleLog = ref<LogEntry[]>([]);
  const cardsPlayedThisTurn = ref<string[]>([]);
  const result = ref<{ won: boolean; reward: number } | null>(null);
  const battleLoading = ref(false);

  // Internal
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let lobbyChannel: any = null;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let sessionWatchChannel: any = null;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let battleChannel: any = null;
  let timerInterval: number | null = null;

  const playerId = computed(() => authStore.player?.id);
  const isP1 = computed(() => session.value?.player1_id === playerId.value);

  const handCards = computed<CardDefinition[]>(() => {
    return myHand.value.map((id) => getCard(id));
  });

  const canPlayCard = computed(() => (card: CardDefinition) => {
    return isMyTurn.value && myEnergy.value >= card.cost;
  });

  // === Lobby Functions ===

  async function loadLobby() {
    if (!playerId.value) return;
    lobbyLoading.value = true;
    try {
      const data = await getBattleLobby(playerId.value);
      if (data?.success) {
        lobbyEntries.value = data.lobby || [];
        inLobby.value = data.in_lobby || false;

        // Resume active session if exists
        if (data.active_session) {
          startBattle(data.active_session);
        }
      }
    } catch (e) {
      console.error('Error loading lobby:', e);
    } finally {
      lobbyLoading.value = false;
    }
  }

  async function enterLobby() {
    if (!playerId.value) return;
    lobbyLoading.value = true;
    try {
      const data = await joinBattleLobby(playerId.value, BET_AMOUNT);
      if (data?.success) {
        inLobby.value = true;
        playSound('click');
      } else {
        playSound('error');
        throw new Error(data?.error || 'Failed to join lobby');
      }
    } catch (e) {
      console.error('Error joining lobby:', e);
      throw e;
    } finally {
      lobbyLoading.value = false;
    }
  }

  async function exitLobby() {
    if (!playerId.value) return;
    lobbyLoading.value = true;
    try {
      const data = await leaveBattleLobby(playerId.value);
      if (data?.success) {
        inLobby.value = false;
        playSound('click');
      }
    } catch (e) {
      console.error('Error leaving lobby:', e);
    } finally {
      lobbyLoading.value = false;
    }
  }

  async function challengePlayer(opponentLobbyId: string) {
    if (!playerId.value) return;
    battleLoading.value = true;
    try {
      const data = await acceptBattleChallenge(playerId.value, opponentLobbyId);
      if (data?.success) {
        playSound('success');
        // Battle will start via realtime update
        await loadLobby();
      } else {
        playSound('error');
        throw new Error(data?.error || 'Challenge failed');
      }
    } catch (e) {
      console.error('Error accepting challenge:', e);
      throw e;
    } finally {
      battleLoading.value = false;
    }
  }

  // === Battle Functions ===

  function startBattle(sessionData: BattleSession) {
    session.value = sessionData;
    const state = sessionData.game_state;
    const amP1 = sessionData.player1_id === playerId.value;

    myHp.value = amP1 ? sessionData.player1_hp : sessionData.player2_hp;
    myShield.value = amP1 ? sessionData.player1_shield : sessionData.player2_shield;
    enemyHp.value = amP1 ? sessionData.player2_hp : sessionData.player1_hp;
    enemyShield.value = amP1 ? sessionData.player2_shield : sessionData.player1_shield;
    myHand.value = amP1 ? (state.player1Hand || []) : (state.player2Hand || []);
    myEnergy.value = amP1 ? state.player1Energy : state.player2Energy;
    isMyTurn.value = sessionData.current_turn === playerId.value;
    cardsPlayedThisTurn.value = [];
    result.value = null;

    // Process log entries if any
    if (state.lastAction) {
      battleLog.value = [...battleLog.value, ...state.lastAction];
    }

    // Start timer
    startTurnTimer(sessionData.turn_deadline);

    // Subscribe to battle updates
    subscribeToBattle(sessionData.id);

    // Check if already finished
    if (sessionData.status === 'completed' || sessionData.status === 'forfeited') {
      handleBattleEnd(sessionData);
    }
  }

  function handleServerUpdate(payload: { new: BattleSession }) {
    const newSession = payload.new;
    if (!newSession || !playerId.value) return;

    session.value = newSession;
    const state = newSession.game_state;
    const amP1 = newSession.player1_id === playerId.value;

    myHp.value = amP1 ? newSession.player1_hp : newSession.player2_hp;
    myShield.value = amP1 ? newSession.player1_shield : newSession.player2_shield;
    enemyHp.value = amP1 ? newSession.player2_hp : newSession.player1_hp;
    enemyShield.value = amP1 ? newSession.player2_shield : newSession.player1_shield;
    myHand.value = amP1 ? (state.player1Hand || []) : (state.player2Hand || []);
    myEnergy.value = amP1 ? state.player1Energy : state.player2Energy;
    isMyTurn.value = newSession.current_turn === playerId.value;
    cardsPlayedThisTurn.value = [];

    // Process log entries
    if (state.lastAction && state.lastAction.length > 0) {
      battleLog.value = [...battleLog.value, ...state.lastAction];
    }

    // Restart timer
    startTurnTimer(newSession.turn_deadline);

    // Check for game end
    if (newSession.status === 'completed' || newSession.status === 'forfeited') {
      handleBattleEnd(newSession);
    } else if (isMyTurn.value) {
      playSound('warning');
    }
  }

  function playCard(cardId: string) {
    const card = getCard(cardId);
    if (!isMyTurn.value || myEnergy.value < card.cost) return;

    // Find and remove from hand
    const idx = myHand.value.indexOf(cardId);
    if (idx === -1) return;

    myEnergy.value -= card.cost;
    myHand.value.splice(idx, 1);
    cardsPlayedThisTurn.value.push(cardId);
    playSound('click');
  }

  function undoLastCard() {
    if (cardsPlayedThisTurn.value.length === 0) return;
    const lastCard = cardsPlayedThisTurn.value.pop()!;
    const card = getCard(lastCard);
    myEnergy.value += card.cost;
    myHand.value.push(lastCard);
  }

  async function endTurn() {
    if (!playerId.value || !session.value) return;
    battleLoading.value = true;
    try {
      const data = await playBattleTurn(
        playerId.value,
        session.value.id,
        cardsPlayedThisTurn.value
      );
      if (data?.success) {
        cardsPlayedThisTurn.value = [];
        isMyTurn.value = false;
        // Server update will come via realtime
      } else {
        playSound('error');
        console.error('Turn failed:', data?.error);
      }
    } catch (e) {
      console.error('Error playing turn:', e);
      playSound('error');
    } finally {
      battleLoading.value = false;
    }
  }

  async function doForfeit() {
    if (!playerId.value || !session.value) return;
    battleLoading.value = true;
    try {
      const data = await forfeitBattle(playerId.value, session.value.id);
      if (data?.success) {
        result.value = { won: false, reward: 0 };
        playSound('error');
      }
    } catch (e) {
      console.error('Error forfeiting:', e);
    } finally {
      battleLoading.value = false;
    }
  }

  function handleBattleEnd(s: BattleSession) {
    stopTurnTimer();
    const won = s.winner_id === playerId.value;
    result.value = {
      won,
      reward: won ? BET_AMOUNT * 2 : 0,
    };
    if (won) {
      playSound('reward');
    } else {
      playSound('error');
    }
  }

  // === Timer ===

  function startTurnTimer(deadline: string) {
    stopTurnTimer();
    const deadlineMs = new Date(deadline).getTime();

    const updateTimer = () => {
      const remaining = Math.max(0, Math.ceil((deadlineMs - Date.now()) / 1000));
      turnTimer.value = remaining;

      if (remaining <= 0 && isMyTurn.value) {
        endTurn();
      }
    };

    updateTimer();
    timerInterval = window.setInterval(updateTimer, 1000);
  }

  function stopTurnTimer() {
    if (timerInterval) {
      clearInterval(timerInterval);
      timerInterval = null;
    }
  }

  // === Realtime Subscriptions ===

  function subscribeToLobby() {
    if (lobbyChannel) return;

    lobbyChannel = supabase
      .channel('battle-lobby')
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'battle_lobby',
        },
        () => {
          loadLobby();
        }
      )
      .subscribe();

    // Separate channel for session creation watch
    sessionWatchChannel = supabase
      .channel('battle-session-watch')
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'battle_sessions',
        },
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        (payload: any) => {
          const newData = payload.new as BattleSession;
          if (
            newData &&
            (newData.player1_id === playerId.value || newData.player2_id === playerId.value)
          ) {
            if (!session.value && newData.status === 'active') {
              startBattle(newData);
            }
          }
        }
      )
      .subscribe();
  }

  function subscribeToBattle(sessionId: string) {
    if (battleChannel) {
      supabase.removeChannel(battleChannel);
    }

    battleChannel = supabase
      .channel(`battle:${sessionId}`)
      .on(
        'postgres_changes',
        {
          event: 'UPDATE',
          schema: 'public',
          table: 'battle_sessions',
          filter: `id=eq.${sessionId}`,
        },
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        (payload: any) => {
          handleServerUpdate({ new: payload.new as BattleSession });
        }
      )
      .subscribe();
  }

  function unsubscribeAll() {
    if (lobbyChannel) {
      supabase.removeChannel(lobbyChannel);
      lobbyChannel = null;
    }
    if (sessionWatchChannel) {
      supabase.removeChannel(sessionWatchChannel);
      sessionWatchChannel = null;
    }
    if (battleChannel) {
      supabase.removeChannel(battleChannel);
      battleChannel = null;
    }
    stopTurnTimer();
  }

  function resetBattle() {
    session.value = null;
    myHand.value = [];
    myHp.value = 100;
    myShield.value = 0;
    myEnergy.value = MAX_ENERGY;
    enemyHp.value = 100;
    enemyShield.value = 0;
    isMyTurn.value = false;
    turnTimer.value = TURN_DURATION;
    battleLog.value = [];
    cardsPlayedThisTurn.value = [];
    result.value = null;
    battleLoading.value = false;

    if (battleChannel) {
      supabase.removeChannel(battleChannel);
      battleChannel = null;
    }
    stopTurnTimer();
  }

  function cleanup() {
    unsubscribeAll();
    resetBattle();
    lobbyEntries.value = [];
    inLobby.value = false;
  }

  onUnmounted(() => {
    cleanup();
  });

  return {
    // Lobby
    lobbyEntries,
    inLobby,
    lobbyLoading,
    loadLobby,
    enterLobby,
    exitLobby,
    challengePlayer,
    subscribeToLobby,

    // Battle
    session,
    myHand,
    myHp,
    myShield,
    myEnergy,
    enemyHp,
    enemyShield,
    enemyUsername,
    isMyTurn,
    turnTimer,
    battleLog,
    cardsPlayedThisTurn,
    result,
    battleLoading,
    handCards,
    canPlayCard,
    isP1,

    playCard,
    undoLastCard,
    endTurn,
    doForfeit,
    resetBattle,
    cleanup,
  };
}
