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
  updateMissionProgress,
} from '@/utils/api';
import { getCard, type CardDefinition, TURN_DURATION, MAX_ENERGY, MAX_HP, MAX_HAND_SIZE, BET_OPTIONS, type BetOption } from '@/utils/battleCards';
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
    player1Poison: number;
    player2Poison: number;
    lastAction: LogEntry[] | null;
  };
  status: string;
  winner_id: string | null;
  bet_amount: number;
  bet_currency: string;
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
  poison?: number;
  poisonTick?: number;
  boost?: number;
  energyDrain?: number;
  curePoison?: boolean;
  taunt?: boolean;
  recall?: string;
}

export function useCardBattle() {
  const authStore = useAuthStore();

  // Lobby state
  const lobbyEntries = ref<LobbyEntry[]>([]);
  const inLobby = ref(false);
  const lobbyLoading = ref(false);
  const myBalances = ref<{ gamecoin: number; blockcoin: number; ronin: number }>({ gamecoin: 0, blockcoin: 0, ronin: 0 });
  const lobbyCount = ref(0);
  const playingCount = ref(0);
  const readyRoom = ref<ReadyRoom | null>(null);

  // Battle state
  const session = ref<BattleSession | null>(null);
  const myHand = ref<(string | null)[]>([]);
  const undoStack = ref<{ cardId: string; slotIndex: number }[]>([]);
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
  const myPoison = ref(0);
  const enemyPoison = ref(0);
  const turnTimer = ref(TURN_DURATION);
  const battleLog = ref<LogEntry[]>([]);
  const cardsPlayedThisTurn = ref<string[]>([]);
  const result = ref<{ won: boolean; reward: number; betAmount: number; betCurrency: string } | null>(null);
  const battleLoading = ref(false);
  const animatingEffects = ref(false);
  const currentBetAmount = ref(0);
  const currentBetCurrency = ref('GC');
  const errorMessage = ref<string | null>(null);

  // Recall card state
  const showRecallPicker = ref(false);
  const pendingRecallCardSlot = ref(-1);

  // Battle mission tracking
  const battleCardsPlayed = ref(0);
  let missionTracked = false;

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
  let staggerTimeouts: number[] = [];

  const playerId = computed(() => authStore.player?.id);
  const isP1 = computed(() => session.value?.player1_id === playerId.value);

  const handCards = computed<(CardDefinition | null)[]>(() => {
    return myHand.value.map((id) => id ? getCard(id) : null);
  });

  const myDiscard = computed<string[]>(() => {
    if (!session.value?.game_state) return [];
    const state = session.value.game_state;
    return isP1.value ? (state.player1Discard || []) : (state.player2Discard || []);
  });

  const canPlayCard = computed(() => (card: CardDefinition) => {
    if (!isMyTurn.value || animatingEffects.value || myEnergy.value < card.cost) return false;
    if (card.id === 'recall' && myDiscard.value.length === 0) return false;
    return true;
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
        lobbyCount.value = data.lobby_count ?? 0;
        playingCount.value = data.playing_count ?? 0;
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
          // Ready room disappeared (opponent cancelled or expired) → exit quick match
          if (readyRoom.value && !rr && quickMatchMode.value) {
            quickMatchMode.value = false;
            quickMatchSearching.value = false;
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

        // Auto re-join lobby if searching but server says we're not in
        if (quickMatchMode.value && !inLobby.value && !data.active_session && !readyRoom.value) {
          const joinData = await joinBattleLobby(playerId.value!);
          if (joinData?.success) {
            inLobby.value = true;
          }
        }

        // Auto-pair when in quick match mode and a waiting opponent is found
        if (quickMatchMode.value && inLobby.value && !data.active_session && !readyRoom.value && !quickMatchPairing.value && lobbyEntries.value.some(e => e.player_id !== excludedOpponentId.value && e.status === 'waiting')) {
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
        } else {
          throw new Error(data?.error || 'Failed to join lobby');
        }
      }
      // Always load lobby to trigger auto-pair immediately
      await loadLobby();
    } catch (e) {
      quickMatchMode.value = false;
      quickMatchSearching.value = false;
      throw e;
    }
  }

  async function autoQuickMatchPair() {
    const opponent = lobbyEntries.value.find(e => e.player_id !== excludedOpponentId.value && e.status === 'waiting');
    if (!opponent || !playerId.value) return;
    try {
      const data = await apiQuickMatchPair(playerId.value, opponent.id);
      if (data?.success) {
        quickMatchSearching.value = false;
        excludedOpponentId.value = null;
        await loadLobby(true);
      } else if (data?.error?.includes('lobby')) {
        // We're no longer in the lobby (cleanup/expired), re-join
        const joinData = await joinBattleLobby(playerId.value!);
        if (joinData?.success) {
          inLobby.value = true;
        }
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

  // Push log entries one by one with delay so each triggers its own combat effect
  // Also interpolates HP/shield values gradually when finalStats is provided
  interface FinalStats {
    myHp: number;
    myShield: number;
    enemyHp: number;
    enemyShield: number;
  }
  function cancelStaggeredEffects() {
    staggerTimeouts.forEach((id) => clearTimeout(id));
    staggerTimeouts = [];
    animatingEffects.value = false;
  }

  function staggerLogEntries(entries: LogEntry[], finalStats?: FinalStats) {
    if (entries.length === 0) return;
    cancelStaggeredEffects();
    const n = entries.length;
    const startMyHp = myHp.value;
    const startMyShield = myShield.value;
    const startEnemyHp = enemyHp.value;
    const startEnemyShield = enemyShield.value;

    animatingEffects.value = true;

    entries.forEach((entry, i) => {
      const tid = window.setTimeout(() => {
        battleLog.value = [...battleLog.value, entry];
        // Interpolate HP/shield toward final values with each effect
        if (finalStats) {
          const progress = (i + 1) / n;
          myHp.value = Math.round(startMyHp + (finalStats.myHp - startMyHp) * progress);
          myShield.value = Math.round(startMyShield + (finalStats.myShield - startMyShield) * progress);
          enemyHp.value = Math.round(startEnemyHp + (finalStats.enemyHp - startEnemyHp) * progress);
          enemyShield.value = Math.round(startEnemyShield + (finalStats.enemyShield - startEnemyShield) * progress);
        }
        // Clear animating flag after the last entry
        if (i === n - 1) {
          animatingEffects.value = false;
        }
      }, i * 600);
      staggerTimeouts.push(tid);
    });
  }

  // Pad a server hand array into fixed-size slots (fill with nulls)
  function padHand(cards: string[]): (string | null)[] {
    const slots: (string | null)[] = [...cards];
    while (slots.length < MAX_HAND_SIZE) slots.push(null);
    return slots;
  }

  // Merge server hand into existing slots: keep cards in position, fill empty slots with new cards
  function mergeHand(serverCards: string[]): (string | null)[] {
    const slots = [...myHand.value];
    // Ensure we have MAX_HAND_SIZE slots
    while (slots.length < MAX_HAND_SIZE) slots.push(null);

    // Build set of cards currently in our slots
    const existingSet = new Set(slots.filter((id): id is string => id !== null));

    // Remove from slots any cards the server no longer has (they were consumed)
    const serverSet = new Set(serverCards);
    for (let i = 0; i < slots.length; i++) {
      if (slots[i] !== null && !serverSet.has(slots[i]!)) {
        slots[i] = null;
      }
    }

    // Find new cards from server that aren't in any slot
    const newCards = serverCards.filter((id) => !existingSet.has(id));

    // Fill empty slots with new cards
    let newIdx = 0;
    for (let i = 0; i < slots.length && newIdx < newCards.length; i++) {
      if (slots[i] === null) {
        slots[i] = newCards[newIdx++];
      }
    }

    return slots;
  }

  function startBattle(sessionData: BattleSession) {
    session.value = sessionData;
    const state = sessionData.game_state;
    const amP1 = sessionData.player1_id === playerId.value;

    // Cache bet info from session (persists through battle)
    if (sessionData.bet_amount) {
      currentBetAmount.value = Number(sessionData.bet_amount);
      currentBetCurrency.value = sessionData.bet_currency || 'GC';
    }

    // Cache enemy username from readyRoom if not already set
    if (!enemyUsername.value && readyRoom.value) {
      const amP1RR = readyRoom.value.player1_id === playerId.value;
      enemyUsername.value = amP1RR ? readyRoom.value.player2_username : readyRoom.value.player1_username;
    }

    myHp.value = amP1 ? sessionData.player1_hp : sessionData.player2_hp;
    myShield.value = amP1 ? sessionData.player1_shield : sessionData.player2_shield;
    enemyHp.value = amP1 ? sessionData.player2_hp : sessionData.player1_hp;
    enemyShield.value = amP1 ? sessionData.player2_shield : sessionData.player1_shield;
    const serverHand: string[] = amP1 ? (state.player1Hand || []) : (state.player2Hand || []);
    myHand.value = padHand(serverHand);
    myEnergy.value = amP1 ? state.player1Energy : state.player2Energy;
    isMyTurn.value = sessionData.current_turn === playerId.value;
    myWeakened.value = amP1 ? (state.player1Weakened || false) : (state.player2Weakened || false);
    myBoosted.value = amP1 ? (state.player1Boosted || false) : (state.player2Boosted || false);
    enemyWeakened.value = amP1 ? (state.player2Weakened || false) : (state.player1Weakened || false);
    enemyBoosted.value = amP1 ? (state.player2Boosted || false) : (state.player1Boosted || false);
    myPoison.value = amP1 ? (state.player1Poison || 0) : (state.player2Poison || 0);
    enemyPoison.value = amP1 ? (state.player2Poison || 0) : (state.player1Poison || 0);
    cardsPlayedThisTurn.value = [];
    undoStack.value = [];
    result.value = null;
    battleCardsPlayed.value = 0;
    missionTracked = false;

    // Process log entries if any (stagger for animations)
    if (state.lastAction) {
      staggerLogEntries(state.lastAction);
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

    // Compute final HP/shield values from server
    const finalMyHp = amP1 ? newSession.player1_hp : newSession.player2_hp;
    const finalMyShield = amP1 ? newSession.player1_shield : newSession.player2_shield;
    const finalEnemyHp = amP1 ? newSession.player2_hp : newSession.player1_hp;
    const finalEnemyShield = amP1 ? newSession.player2_shield : newSession.player1_shield;

    const serverHand: string[] = amP1 ? (state.player1Hand || []) : (state.player2Hand || []);
    myHand.value = mergeHand(serverHand);
    myEnergy.value = amP1 ? state.player1Energy : state.player2Energy;
    isMyTurn.value = newSession.current_turn === playerId.value;
    myWeakened.value = amP1 ? (state.player1Weakened || false) : (state.player2Weakened || false);
    myBoosted.value = amP1 ? (state.player1Boosted || false) : (state.player2Boosted || false);
    enemyWeakened.value = amP1 ? (state.player2Weakened || false) : (state.player1Weakened || false);
    enemyBoosted.value = amP1 ? (state.player2Boosted || false) : (state.player1Boosted || false);
    myPoison.value = amP1 ? (state.player1Poison || 0) : (state.player2Poison || 0);
    enemyPoison.value = amP1 ? (state.player2Poison || 0) : (state.player1Poison || 0);
    cardsPlayedThisTurn.value = [];
    undoStack.value = [];

    // Process log entries (stagger for animations with gradual HP/shield changes)
    if (state.lastAction && state.lastAction.length > 0) {
      staggerLogEntries(state.lastAction, {
        myHp: finalMyHp,
        myShield: finalMyShield,
        enemyHp: finalEnemyHp,
        enemyShield: finalEnemyShield,
      });
    } else {
      // No log entries — apply values immediately
      myHp.value = finalMyHp;
      myShield.value = finalMyShield;
      enemyHp.value = finalEnemyHp;
      enemyShield.value = finalEnemyShield;
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
    if (!canPlayCard.value(card)) return;

    // Intercept recall card — show discard picker instead of playing immediately
    if (card.id === 'recall') {
      const idx = myHand.value.indexOf(cardId);
      if (idx === -1) return;
      pendingRecallCardSlot.value = idx;
      showRecallPicker.value = true;
      return;
    }

    // Find card in slot and null it out (keep position)
    const idx = myHand.value.indexOf(cardId);
    if (idx === -1) return;

    myEnergy.value -= card.cost;
    myHand.value[idx] = null;
    cardsPlayedThisTurn.value.push(cardId);
    undoStack.value.push({ cardId, slotIndex: idx });
    playBattleSound('card_play');
  }

  function selectRecallTarget(targetCardId: string) {
    const idx = pendingRecallCardSlot.value;
    if (idx === -1) return;
    const card = getCard('recall');
    myEnergy.value -= card.cost;
    myHand.value[idx] = null;
    cardsPlayedThisTurn.value.push(`recall:${targetCardId}`);
    undoStack.value.push({ cardId: 'recall', slotIndex: idx });
    showRecallPicker.value = false;
    pendingRecallCardSlot.value = -1;
    playBattleSound('card_play');
  }

  function cancelRecall() {
    showRecallPicker.value = false;
    pendingRecallCardSlot.value = -1;
  }

  function undoLastCard() {
    if (cardsPlayedThisTurn.value.length === 0 || undoStack.value.length === 0) return;
    const entry = undoStack.value.pop()!;
    cardsPlayedThisTurn.value.pop();
    const card = getCard(entry.cardId);
    myEnergy.value += card.cost;
    myHand.value[entry.slotIndex] = entry.cardId;
  }

  async function endTurn() {
    if (!playerId.value || !session.value) return;
    battleLoading.value = true;
    try {
      // Track cards played for missions before sending
      const cardsCount = cardsPlayedThisTurn.value.length;
      const data = await playBattleTurn(
        playerId.value,
        session.value.id,
        cardsPlayedThisTurn.value
      );
      if (data?.success) {
        battleCardsPlayed.value += cardsCount;
        cardsPlayedThisTurn.value = [];
        undoStack.value = [];
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
        const betAmt = Number(session.value?.bet_amount) || currentBetAmount.value || selectedBetAmount.value.amount;
        const betCur = session.value?.bet_currency || currentBetCurrency.value || 'GC';
        result.value = { won: false, reward: 0, betAmount: betAmt, betCurrency: betCur };
        playBattleSound('error');
      }
    } catch {
      // silently fail
    } finally {
      battleLoading.value = false;
    }
  }

  function handleBattleEnd(s: BattleSession) {
    cancelStaggeredEffects();
    stopTurnTimer();
    // Apply final HP/shield values immediately
    const amP1 = s.player1_id === playerId.value;
    myHp.value = amP1 ? s.player1_hp : s.player2_hp;
    myShield.value = amP1 ? s.player1_shield : s.player2_shield;
    enemyHp.value = amP1 ? s.player2_hp : s.player1_hp;
    enemyShield.value = amP1 ? s.player2_shield : s.player1_shield;

    const won = s.winner_id === playerId.value;
    const betAmt = Number(s.bet_amount) || currentBetAmount.value || selectedBetAmount.value.amount;
    const betCur = s.bet_currency || currentBetCurrency.value || 'GC';
    result.value = {
      won,
      reward: won ? betAmt * 2 : 0,
      betAmount: betAmt,
      betCurrency: betCur,
    };
    if (won) {
      playBattleSound('battle_win');
    } else {
      playBattleSound('battle_lose');
    }

    // Track card-based battle missions (fire-and-forget)
    trackBattleMissions();
  }

  async function trackBattleMissions() {
    if (missionTracked) return;
    missionTracked = true;
    const pid = playerId.value;
    if (!pid || battleCardsPlayed.value <= 0) return;
    try {
      await updateMissionProgress(pid, 'battle_cards_played', battleCardsPlayed.value);
    } catch {
      // Silent fail — mission tracking should never break battle flow
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
        if ((inLobby.value || quickMatchSearching.value) && !session.value) {
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
    undoStack.value = [];
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
    myPoison.value = 0;
    enemyPoison.value = 0;
    turnTimer.value = TURN_DURATION;
    battleLog.value = [];
    cardsPlayedThisTurn.value = [];
    result.value = null;
    battleCardsPlayed.value = 0;
    missionTracked = false;
    showRecallPicker.value = false;
    pendingRecallCardSlot.value = -1;
    battleLoading.value = false;
    animatingEffects.value = false;
    currentBetAmount.value = 0;
    currentBetCurrency.value = 'GC';
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
    lobbyCount,
    playingCount,
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
    myPoison,
    enemyPoison,
    turnTimer,
    battleLog,
    cardsPlayedThisTurn,
    result,
    battleLoading,
    animatingEffects,
    handCards,
    canPlayCard,
    isP1,

    playCard,
    undoLastCard,
    endTurn,
    doForfeit,
    resetBattle,
    cleanup,
    // Recall
    myDiscard,
    showRecallPicker,
    selectRecallTarget,
    cancelRecall,
  };
}
