import { ref, computed, onUnmounted } from 'vue';
import { supabase } from '@/utils/supabase';
import { useAuthStore } from '@/stores/auth';
import {
  joinBattleLobby,
  leaveBattleLobby,
  startBattleFromReadyRoom as apiStartBattleFromReadyRoom,
  playBattleTurn,
  forfeitBattle,
  getBattleLobby,
  quickMatchPair as apiQuickMatchPair,
  selectBattleBet as apiSelectBattleBet,
  cancelBattleReadyRoom as apiCancelBattleReadyRoom,
} from '@/utils/api';
import { getCard, type CardDefinition, TURN_DURATION, MAX_ENERGY, MAX_HP, BET_OPTIONS, type BetOption } from '@/utils/battleCards';
import { playBattleSound } from '@/utils/sounds';

export interface AvailableBet {
  amount: number;
  currency: 'GC' | 'BLC' | 'RON';
  enabled: boolean;
}

export interface LobbyEntry {
  id: string;
  player_id: string;
  username: string;
  bet_amount?: number;
  bet_currency?: string;
  proposed_bet?: number;
  proposed_currency?: string;
  status: string;
  challenged_by?: string;
  challenger_username?: string;
  challenge_expires_at?: string;
  created_at: string;
  wins?: number;
  losses?: number;
  gamecoin_balance: number;
  crypto_balance: number;
  ron_balance: number;
  available_bets: AvailableBet[];
}

export interface ReadyRoom {
  id: string;
  player1_id: string;
  player2_id: string;
  player1_username: string;
  player2_username: string;
  player1_ready: boolean;
  player2_ready: boolean;
  bet_amount: number;
  bet_currency: string;
  player1_bet_amount: number;
  player1_bet_currency: string;
  player2_bet_amount: number;
  player2_bet_currency: string;
  expires_at: string;
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
    player1Boosted: boolean;
    player2Boosted: boolean;
    lastAction: LogEntry[] | null;
  };
  status: string;
  winner_id: string | null;
  bet_amount: number;
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
  pierce?: number;
  boost?: number;
}

export function useCardBattle() {
  const authStore = useAuthStore();

  // Lobby state
  const lobbyEntries = ref<LobbyEntry[]>([]);
  const inLobby = ref(false);
  const lobbyLoading = ref(false);
  const myBalances = ref<{ gamecoin: number; blockcoin: number; ronin: number }>({ gamecoin: 0, blockcoin: 0, ronin: 0 });
  const readyRoom = ref<ReadyRoom | null>(null);

  // Battle state
  const session = ref<BattleSession | null>(null);
  const myHand = ref<string[]>([]);
  const myHp = ref(MAX_HP);
  const myShield = ref(0);
  const myEnergy = ref(MAX_ENERGY);
  const enemyHp = ref(MAX_HP);
  const enemyShield = ref(0);
  const isMyTurn = ref(false);
  const myWeakened = ref(false);
  const myBoosted = ref(false);
  const enemyWeakened = ref(false);
  const enemyBoosted = ref(false);
  const turnTimer = ref(TURN_DURATION);
  const battleLog = ref<LogEntry[]>([]);
  const cardsPlayedThisTurn = ref<string[]>([]);
  const result = ref<{ won: boolean; reward: number } | null>(null);
  const battleLoading = ref(false);
  const errorMessage = ref<string | null>(null);

  // Bet selection state
  const selectedBetAmount = ref<BetOption>(BET_OPTIONS[0]);

  // Cached enemy username (persists through battle, not cleared by polling)
  const enemyUsername = ref<string>('');

  // Quick match state
  const quickMatchMode = ref(false);
  const quickMatchSearching = ref(false);
  const quickMatchPairing = ref(false);
  const excludedOpponentId = ref<string | null>(null);
  const cancelingReadyRoom = ref(false);

  // Internal
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let lobbyChannel: any = null;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let sessionWatchChannel: any = null;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let readyRoomChannel: any = null;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let battleChannel: any = null;
  let timerInterval: number | null = null;
  let lobbyPollInterval: ReturnType<typeof setInterval> | null = null;

  const playerId = computed(() => authStore.player?.id);
  const isP1 = computed(() => session.value?.player1_id === playerId.value);

  const handCards = computed<CardDefinition[]>(() => {
    return myHand.value.map((id) => getCard(id));
  });

  const canPlayCard = computed(() => (card: CardDefinition) => {
    return isMyTurn.value && myEnergy.value >= card.cost;
  });

  // === Lobby Functions ===

  async function loadLobby(silent = false) {
    if (!playerId.value) return;
    if (!silent) {
      lobbyLoading.value = true;
      errorMessage.value = null;
    }
    try {
      const data = await getBattleLobby(playerId.value);
      if (data?.success) {
        lobbyEntries.value = data.lobby || [];
        inLobby.value = data.in_lobby || false;
        myBalances.value = data.my_balances || { gamecoin: 0, blockcoin: 0, ronin: 0 };
        // Map ready room with defaults for per-player bet fields
        // Skip if a cancel operation is in progress to avoid race conditions
        if (!cancelingReadyRoom.value) {
          const rr = data.ready_room || null;
          if (rr) {
            rr.player1_bet_amount = rr.player1_bet_amount ?? 0;
            rr.player1_bet_currency = rr.player1_bet_currency ?? 'GC';
            rr.player2_bet_amount = rr.player2_bet_amount ?? 0;
            rr.player2_bet_currency = rr.player2_bet_currency ?? 'GC';
          }
          readyRoom.value = rr;
        }

        // If both players are ready in ready room, start the battle
        if (readyRoom.value && readyRoom.value.player1_ready && readyRoom.value.player2_ready) {
          await startBattleFromReadyRoom();
        }

        // Resume active session if exists
        if (data.active_session) {
          startBattle(data.active_session);
        }

        // Auto-pair when in quick match mode and opponent found (excluding recently left opponent)
        if (quickMatchMode.value && inLobby.value && !data.active_session && !readyRoom.value && !quickMatchPairing.value && lobbyEntries.value.some(e => e.player_id !== excludedOpponentId.value)) {
          quickMatchPairing.value = true;
          autoQuickMatchPair().finally(() => { quickMatchPairing.value = false; });
        }
      } else if (!silent) {
        errorMessage.value = data?.error || 'Error loading lobby';
      }
    } catch (e) {
      if (!silent) {
        errorMessage.value = String(e);
      }
    } finally {
      if (!silent) {
        lobbyLoading.value = false;
      }
    }
  }

  async function exitLobby() {
    if (!playerId.value) return;
    lobbyLoading.value = true;
    errorMessage.value = null;

    // Stop polling to prevent it from overriding inLobby after we leave
    if (lobbyPollInterval) {
      clearInterval(lobbyPollInterval);
      lobbyPollInterval = null;
    }

    try {
      const data = await leaveBattleLobby(playerId.value);
      if (data?.success || data?.error === 'Not in lobby') {
        inLobby.value = false;
        playBattleSound('click');
      } else {
        errorMessage.value = data?.error || 'Failed to leave lobby';
      }
    } catch {
      // Network error - force leave locally
      inLobby.value = false;
    } finally {
      lobbyLoading.value = false;
    }
  }

  // === Ready Room Functions ===

  // Cancel ready room and exit lobby entirely
  async function cancelReadyRoom() {
    if (!playerId.value) return;
    battleLoading.value = true;
    errorMessage.value = null;
    excludedOpponentId.value = null;
    // Stop polling and guard against race conditions BEFORE the API call
    cancelingReadyRoom.value = true;
    if (lobbyPollInterval) {
      clearInterval(lobbyPollInterval);
      lobbyPollInterval = null;
    }
    readyRoom.value = null;
    try {
      const data = await apiCancelBattleReadyRoom(playerId.value);
      if (data?.success || data?.error === 'No active ready room found') {
        playBattleSound('click');
        quickMatchMode.value = false;
        quickMatchSearching.value = false;
        inLobby.value = false;
      } else {
        errorMessage.value = data?.error || 'Failed to cancel ready room';
      }
    } catch (e) {
      if (!errorMessage.value) errorMessage.value = String(e);
    } finally {
      cancelingReadyRoom.value = false;
      battleLoading.value = false;
    }
  }

  // Cancel ready room but re-join lobby to find another opponent
  async function cancelReadyRoomAndSearch() {
    if (!playerId.value) return;
    battleLoading.value = true;
    errorMessage.value = null;
    // Exclude the opponent we just left (capture before clearing)
    if (readyRoom.value) {
      const amP1 = readyRoom.value.player1_id === playerId.value;
      excludedOpponentId.value = amP1 ? readyRoom.value.player2_id : readyRoom.value.player1_id;
    }
    // Stop polling and guard against race conditions BEFORE the API call
    cancelingReadyRoom.value = true;
    if (lobbyPollInterval) {
      clearInterval(lobbyPollInterval);
      lobbyPollInterval = null;
    }
    readyRoom.value = null;
    try {
      const data = await apiCancelBattleReadyRoom(playerId.value);
      if (data?.success || data?.error === 'No active ready room found') {
        playBattleSound('click');
        // SQL removed both from lobby, re-join and search
        cancelingReadyRoom.value = false;
        const joinData = await joinBattleLobby(playerId.value!);
        if (joinData?.success) {
          inLobby.value = true;
        }
        quickMatchMode.value = true;
        quickMatchSearching.value = true;
        quickMatchPairing.value = false;
        await loadLobby(true);
        // Re-start polling via subscribeToLobby if needed
        subscribeToLobby();
        // If no other opponents available, go back to start
        const available = lobbyEntries.value.filter(e => e.player_id !== excludedOpponentId.value);
        if (available.length === 0) {
          quickMatchMode.value = false;
          quickMatchSearching.value = false;
          excludedOpponentId.value = null;
          await exitLobby();
        }
        // Otherwise polling will auto-pair with next opponent
      } else {
        errorMessage.value = data?.error || 'Failed to cancel ready room';
      }
    } catch (e) {
      if (!errorMessage.value) errorMessage.value = String(e);
    } finally {
      cancelingReadyRoom.value = false;
      battleLoading.value = false;
    }
  }

  async function selectBattleBet(betAmount: number, betCurrency: 'GC' | 'BLC' | 'RON') {
    if (!playerId.value) return;
    battleLoading.value = true;
    errorMessage.value = null;
    try {
      const data = await apiSelectBattleBet(playerId.value, betAmount, betCurrency);
      if (data?.success) {
        playBattleSound('success');
        await loadLobby(true);
      } else {
        playBattleSound('error');
        errorMessage.value = data?.error || 'Failed to select bet';
        throw new Error(errorMessage.value ?? 'Failed to select bet');
      }
    } catch (e) {
      if (!errorMessage.value) errorMessage.value = String(e);
      throw e;
    } finally {
      battleLoading.value = false;
    }
  }

  async function startBattleFromReadyRoom() {
    if (!readyRoom.value) return;
    battleLoading.value = true;
    errorMessage.value = null;
    try {
      const data = await apiStartBattleFromReadyRoom(readyRoom.value.id);
      if (data?.success && data.session) {
        playBattleSound('battle_start');
        startBattle(data.session);
      } else {
        playBattleSound('error');
        errorMessage.value = data?.error || 'Failed to start battle';
        throw new Error(errorMessage.value ?? 'Failed to start battle');
      }
    } catch (e) {
      if (!errorMessage.value) errorMessage.value = String(e);
      throw e;
    } finally {
      battleLoading.value = false;
    }
  }

  // === Quick Match ===

  async function quickMatch() {
    if (!playerId.value) return;

    quickMatchMode.value = true;
    quickMatchSearching.value = true;
    errorMessage.value = null;
    excludedOpponentId.value = null;

    try {
      if (!inLobby.value) {
        const data = await joinBattleLobby(playerId.value);
        if (data?.success) {
          inLobby.value = true;
          await loadLobby();
        } else {
          throw new Error(data?.error || 'Failed to join lobby');
        }
      }
    } catch (e) {
      quickMatchMode.value = false;
      quickMatchSearching.value = false;
      throw e;
    }
  }

  async function autoQuickMatchPair() {
    const opponent = lobbyEntries.value.find(e => e.player_id !== excludedOpponentId.value);
    if (!opponent || !playerId.value) return;
    try {
      const data = await apiQuickMatchPair(playerId.value, opponent.id);
      if (data?.success) {
        quickMatchSearching.value = false;
        excludedOpponentId.value = null;
        await loadLobby(true);
      }
    } catch {
      // Opponent might have been taken, keep searching
    }
  }

  async function cancelQuickMatch() {
    quickMatchMode.value = false;
    quickMatchSearching.value = false;
    quickMatchPairing.value = false;
    excludedOpponentId.value = null;
    await exitLobby();
  }

  // === Battle Functions ===

  function startBattle(sessionData: BattleSession) {
    session.value = sessionData;
    const state = sessionData.game_state;
    const amP1 = sessionData.player1_id === playerId.value;

    // Cache enemy username from readyRoom if not already set
    if (!enemyUsername.value && readyRoom.value) {
      const amP1RR = readyRoom.value.player1_id === playerId.value;
      enemyUsername.value = amP1RR ? readyRoom.value.player2_username : readyRoom.value.player1_username;
    }

    myHp.value = amP1 ? sessionData.player1_hp : sessionData.player2_hp;
    myShield.value = amP1 ? sessionData.player1_shield : sessionData.player2_shield;
    enemyHp.value = amP1 ? sessionData.player2_hp : sessionData.player1_hp;
    enemyShield.value = amP1 ? sessionData.player2_shield : sessionData.player1_shield;
    myHand.value = amP1 ? (state.player1Hand || []) : (state.player2Hand || []);
    myEnergy.value = amP1 ? state.player1Energy : state.player2Energy;
    isMyTurn.value = sessionData.current_turn === playerId.value;
    myWeakened.value = amP1 ? (state.player1Weakened || false) : (state.player2Weakened || false);
    myBoosted.value = amP1 ? (state.player1Boosted || false) : (state.player2Boosted || false);
    enemyWeakened.value = amP1 ? (state.player2Weakened || false) : (state.player1Weakened || false);
    enemyBoosted.value = amP1 ? (state.player2Boosted || false) : (state.player1Boosted || false);
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
    myWeakened.value = amP1 ? (state.player1Weakened || false) : (state.player2Weakened || false);
    myBoosted.value = amP1 ? (state.player1Boosted || false) : (state.player2Boosted || false);
    enemyWeakened.value = amP1 ? (state.player2Weakened || false) : (state.player1Weakened || false);
    enemyBoosted.value = amP1 ? (state.player2Boosted || false) : (state.player1Boosted || false);
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
      playBattleSound('turn_start');
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
    playBattleSound('card_play');
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
        playBattleSound('error');
      }
    } catch {
      playBattleSound('error');
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
        playBattleSound('error');
      }
    } catch {
      // silently fail
    } finally {
      battleLoading.value = false;
    }
  }

  function handleBattleEnd(s: BattleSession) {
    stopTurnTimer();
    const won = s.winner_id === playerId.value;
    const betAmt = s.bet_amount || selectedBetAmount.value.amount;
    result.value = {
      won,
      reward: won ? betAmt * 2 : 0,
    };
    if (won) {
      playBattleSound('battle_win');
    } else {
      playBattleSound('battle_lose');
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
          loadLobby(true);
        }
      )
      .subscribe();

    // Subscribe to ready room changes
    readyRoomChannel = supabase
      .channel('battle-ready-rooms')
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'battle_ready_rooms',
        },
        () => {
          loadLobby(true);
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

    // Polling fallback: refresh lobby every 5s in case realtime misses events
    if (!lobbyPollInterval) {
      lobbyPollInterval = setInterval(() => {
        if (inLobby.value && !session.value) {
          loadLobby(true);
        }
      }, 5000);
    }
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
    if (readyRoomChannel) {
      supabase.removeChannel(readyRoomChannel);
      readyRoomChannel = null;
    }
    if (sessionWatchChannel) {
      supabase.removeChannel(sessionWatchChannel);
      sessionWatchChannel = null;
    }
    if (battleChannel) {
      supabase.removeChannel(battleChannel);
      battleChannel = null;
    }
    if (lobbyPollInterval) {
      clearInterval(lobbyPollInterval);
      lobbyPollInterval = null;
    }
    stopTurnTimer();
  }

  function resetBattle() {
    session.value = null;
    readyRoom.value = null;
    myHand.value = [];
    myHp.value = MAX_HP;
    myShield.value = 0;
    myEnergy.value = MAX_ENERGY;
    enemyHp.value = MAX_HP;
    enemyShield.value = 0;
    isMyTurn.value = false;
    myWeakened.value = false;
    myBoosted.value = false;
    enemyWeakened.value = false;
    enemyBoosted.value = false;
    turnTimer.value = TURN_DURATION;
    battleLog.value = [];
    cardsPlayedThisTurn.value = [];
    result.value = null;
    battleLoading.value = false;
    quickMatchMode.value = false;
    quickMatchSearching.value = false;
    quickMatchPairing.value = false;
    excludedOpponentId.value = null;
    enemyUsername.value = '';
    selectedBetAmount.value = BET_OPTIONS[0];

    if (battleChannel) {
      supabase.removeChannel(battleChannel);
      battleChannel = null;
    }
    stopTurnTimer();
  }

  function cleanup() {
    // Leave lobby in the database (not just local state)
    if (playerId.value && inLobby.value && !session.value) {
      leaveBattleLobby(playerId.value).catch(() => {});
    }
    unsubscribeAll();
    resetBattle();
    lobbyEntries.value = [];
    inLobby.value = false;
    quickMatchMode.value = false;
    quickMatchSearching.value = false;
  }

  onUnmounted(() => {
    cleanup();
  });

  return {
    // Lobby
    lobbyLoading,
    errorMessage,
    myBalances,
    readyRoom,
    loadLobby,
    subscribeToLobby,
    // Ready Room
    selectBattleBet,
    cancelReadyRoom,
    cancelReadyRoomAndSearch,
    enemyUsername,
    // Quick match
    quickMatchSearching,
    quickMatch,
    cancelQuickMatch,
    // Battle
    session,
    myHand,
    myHp,
    myShield,
    myEnergy,
    enemyHp,
    enemyShield,
    isMyTurn,
    myWeakened,
    myBoosted,
    enemyWeakened,
    enemyBoosted,
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
