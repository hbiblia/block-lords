<script setup lang="ts">
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { BET_OPTIONS } from '@/utils/battleCards';

const props = defineProps<{
  readyRoom: {
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
  };
  myPlayerId: string;
  loading: boolean;
  myBalances?: { gamecoin: number; blockcoin: number; ronin: number };
  error?: string | null;
}>();

const emit = defineEmits<{
  selectBet: [betAmount: number, betCurrency: string];
  cancel: [];
  findAnother: [];
}>();

const { t } = useI18n();

const isPlayer1 = computed(() => props.myPlayerId === props.readyRoom.player1_id);
const myUsername = computed(() => isPlayer1.value ? props.readyRoom.player1_username : props.readyRoom.player2_username);
const opponentUsername = computed(() => isPlayer1.value ? props.readyRoom.player2_username : props.readyRoom.player1_username);
const bothReady = computed(() => props.readyRoom.player1_ready && props.readyRoom.player2_ready);

// Per-player bet selections
const myBetAmount = computed(() => isPlayer1.value ? props.readyRoom.player1_bet_amount : props.readyRoom.player2_bet_amount);
const myBetCurrency = computed(() => isPlayer1.value ? props.readyRoom.player1_bet_currency : props.readyRoom.player2_bet_currency);
const opponentBetAmount = computed(() => isPlayer1.value ? props.readyRoom.player2_bet_amount : props.readyRoom.player1_bet_amount);
const opponentBetCurrency = computed(() => isPlayer1.value ? props.readyRoom.player2_bet_currency : props.readyRoom.player1_bet_currency);

const iHaveSelected = computed(() => myBetAmount.value > 0);
const opponentHasSelected = computed(() => opponentBetAmount.value > 0);
const betsMismatch = computed(() => iHaveSelected.value && opponentHasSelected.value && !bothReady.value);

// Compute available bets based on my balances
const availableBets = computed(() => {
  const bal = props.myBalances || { gamecoin: 0, blockcoin: 0, ronin: 0 };
  return BET_OPTIONS.map(opt => ({
    amount: opt.amount,
    currency: opt.currency,
    label: opt.label,
    enabled: opt.currency === 'GC' ? bal.gamecoin >= opt.amount
           : opt.currency === 'Landwork' ? bal.blockcoin >= opt.amount
           : opt.currency === 'RON' ? bal.ronin >= opt.amount
           : false,
    isMySelection: iHaveSelected.value && myBetAmount.value === opt.amount && myBetCurrency.value === opt.currency,
    isOpponentSelection: opponentHasSelected.value && opponentBetAmount.value === opt.amount && opponentBetCurrency.value === opt.currency,
  }));
});

const groupedBets = computed(() => {
  const groups: { currency: string; bets: typeof availableBets.value }[] = [];
  for (const bet of availableBets.value) {
    let group = groups.find(g => g.currency === bet.currency);
    if (!group) {
      group = { currency: bet.currency, bets: [] };
      groups.push(group);
    }
    group.bets.push(bet);
  }
  return groups;
});

const pendingBet = ref<string | null>(null);

function selectBet(amount: number, currency: string) {
  pendingBet.value = `${amount}-${currency}`;
  emit('selectBet', amount, currency);
}

// Clear pending state when loading ends
watch(() => props.loading, (isLoading) => {
  if (!isLoading) pendingBet.value = null;
});
</script>

<template>
  <div class="flex-1 flex flex-col items-center justify-center p-6 bg-gradient-to-b from-slate-900 via-amber-900/20 to-slate-900 overflow-y-auto">
    <!-- Title -->
    <div class="text-center mb-6">
      <h2 class="text-2xl font-bold text-transparent bg-clip-text bg-gradient-to-r from-amber-400 to-yellow-400 mb-1">
        {{ t('battle.readyRoom.title', 'Battle Ready Room') }}
      </h2>
      <p class="text-sm text-slate-400">
        {{ bothReady
          ? t('battle.readyRoom.starting', 'STARTING BATTLE...')
          : t('battle.readyRoom.selectBetSubtitle', 'Both players select a bet to start') }}
      </p>
    </div>

    <!-- Error display -->
    <div v-if="error" class="w-full max-w-sm mb-4 px-3 py-2 bg-red-500/20 border border-red-500/40 rounded-lg">
      <p class="text-xs text-red-400 text-center">{{ error }}</p>
    </div>

    <!-- Players -->
    <div class="flex items-center gap-8 mb-6">
      <!-- Me -->
      <div class="flex flex-col items-center">
        <div class="relative mb-2">
          <div
            class="w-16 h-16 rounded-full flex items-center justify-center text-2xl font-bold text-white transition-all duration-300"
            :class="bothReady
              ? 'bg-gradient-to-br from-green-500 to-emerald-600 shadow-lg shadow-green-500/50 scale-110'
              : iHaveSelected
                ? 'bg-gradient-to-br from-yellow-500 to-amber-600 shadow-lg shadow-yellow-500/30'
                : 'bg-gradient-to-br from-amber-500 to-blue-500'"
          >
            {{ myUsername.charAt(0).toUpperCase() }}
          </div>
          <div
            v-if="bothReady"
            class="absolute -top-1 -right-1 w-6 h-6 bg-green-500 rounded-full flex items-center justify-center shadow-lg animate-bounce"
          >
            <span class="text-white text-sm">&#10003;</span>
          </div>
          <div
            v-else-if="iHaveSelected"
            class="absolute -top-1 -right-1 w-6 h-6 bg-yellow-500 rounded-full flex items-center justify-center shadow-lg"
          >
            <span class="text-white text-xs">&#9679;</span>
          </div>
        </div>
        <div class="text-center">
          <div class="text-sm font-bold text-slate-200">{{ myUsername }}</div>
          <div class="text-[10px] text-slate-500">{{ t('battle.readyRoom.you', 'You') }}</div>
          <div
            class="mt-1 px-2 py-0.5 rounded-full text-[10px] font-semibold"
            :class="bothReady
              ? 'bg-green-500/20 text-green-400'
              : iHaveSelected
                ? 'bg-yellow-500/20 text-yellow-400'
                : 'bg-slate-500/20 text-slate-400'"
          >
            {{ bothReady
              ? t('battle.readyRoom.ready', 'READY')
              : iHaveSelected
                ? `${myBetAmount} ${myBetCurrency}`
                : t('battle.readyRoom.selecting', 'Selecting...') }}
          </div>
        </div>
      </div>

      <!-- VS -->
      <div class="text-3xl font-bold text-slate-600">VS</div>

      <!-- Opponent -->
      <div class="flex flex-col items-center">
        <div class="relative mb-2">
          <div
            class="w-16 h-16 rounded-full flex items-center justify-center text-2xl font-bold text-white transition-all duration-300"
            :class="bothReady
              ? 'bg-gradient-to-br from-green-500 to-emerald-600 shadow-lg shadow-green-500/50 scale-110'
              : opponentHasSelected
                ? 'bg-gradient-to-br from-yellow-500 to-amber-600 shadow-lg shadow-yellow-500/30'
                : 'bg-gradient-to-br from-pink-500 to-red-500'"
          >
            {{ bothReady ? opponentUsername.charAt(0).toUpperCase() : '?' }}
          </div>
          <div
            v-if="bothReady"
            class="absolute -top-1 -right-1 w-6 h-6 bg-green-500 rounded-full flex items-center justify-center shadow-lg animate-bounce"
          >
            <span class="text-white text-sm">&#10003;</span>
          </div>
          <div
            v-else-if="opponentHasSelected"
            class="absolute -top-1 -right-1 w-6 h-6 bg-yellow-500 rounded-full flex items-center justify-center shadow-lg"
          >
            <span class="text-white text-xs">&#9679;</span>
          </div>
        </div>
        <div class="text-center">
          <div class="text-sm font-bold text-slate-200">{{ bothReady ? opponentUsername : t('battle.readyRoom.opponent', 'Opponent') }}</div>
          <div class="text-[10px] text-slate-500">&nbsp;</div>
          <div
            class="mt-1 px-2 py-0.5 rounded-full text-[10px] font-semibold"
            :class="bothReady
              ? 'bg-green-500/20 text-green-400'
              : opponentHasSelected
                ? 'bg-yellow-500/20 text-yellow-400'
                : 'bg-slate-500/20 text-slate-400'"
          >
            {{ bothReady
              ? t('battle.readyRoom.ready', 'READY')
              : opponentHasSelected
                ? `${opponentBetAmount} ${opponentBetCurrency}`
                : t('battle.readyRoom.selecting', 'Selecting...') }}
          </div>
        </div>
      </div>
    </div>

    <!-- Action Area -->
    <div class="w-full max-w-sm">
      <!-- STATE 1: Both ready, bets matched → Starting battle -->
      <div v-if="bothReady" class="text-center space-y-3">
        <div class="px-5 py-3 bg-amber-500/10 border border-amber-500/30 rounded-xl text-center">
          <div class="text-xs text-slate-500 uppercase tracking-wider mb-1">{{ t('battle.readyRoom.bet', 'Battle Bet') }}</div>
          <div class="text-2xl font-bold text-amber-400">{{ readyRoom.bet_amount }} {{ readyRoom.bet_currency }}</div>
          <div class="text-xs text-slate-500 mt-1">{{ t('battle.readyRoom.winner', 'Winner takes') }} {{ readyRoom.bet_amount * 2 }} {{ readyRoom.bet_currency }}</div>
        </div>
        <div class="py-4 px-6 bg-green-500/20 border border-green-500/50 rounded-xl animate-pulse">
          <div class="flex items-center justify-center gap-2 text-green-400 mb-2">
            <span class="text-2xl">&#9876;</span>
            <span class="font-bold text-lg">{{ t('battle.readyRoom.starting', 'STARTING BATTLE...') }}</span>
          </div>
          <p class="text-xs text-slate-400">{{ t('battle.readyRoom.getReady', 'Get ready for battle!') }}</p>
        </div>
      </div>

      <!-- STATE 2: Bets mismatch → Show warning + allow re-select -->
      <div v-else-if="betsMismatch" class="space-y-3">
        <div class="py-3 px-5 bg-orange-500/10 border border-orange-500/30 rounded-xl text-center">
          <div class="flex items-center justify-center gap-2 text-orange-400 mb-1">
            <span class="text-lg">&#9888;</span>
            <span class="font-semibold text-sm">{{ t('battle.readyRoom.betMismatch', 'Bets don\'t match!') }}</span>
          </div>
          <p class="text-xs text-slate-500">{{ t('battle.readyRoom.betMismatchHint', 'Select the same bet as your opponent to start') }}</p>
          <div class="mt-2 text-xs text-slate-400">
            {{ t('battle.readyRoom.yourBet', 'Your bet') }}: <span class="text-yellow-400 font-semibold">{{ myBetAmount }} {{ myBetCurrency }}</span>
            &nbsp;·&nbsp;
            {{ t('battle.readyRoom.opponentBet', 'Opponent') }}: <span class="text-pink-400 font-semibold">{{ opponentBetAmount }} {{ opponentBetCurrency }}</span>
          </div>
        </div>
        <div class="text-center mb-1">
          <div class="text-xs text-slate-500 uppercase tracking-wider font-semibold">
            {{ t('battle.readyRoom.changeBet', 'Change your bet') }}
          </div>
        </div>
        <div v-for="group in groupedBets" :key="group.currency" class="flex gap-2">
          <button
            v-for="bet in group.bets"
            :key="`${bet.amount}-${bet.currency}`"
            @click="selectBet(bet.amount, bet.currency)"
            :disabled="!bet.enabled || loading || bet.isMySelection"
            class="flex-1 px-3 py-3 rounded-lg text-sm font-bold transition-all border"
            :class="bet.isMySelection
              ? 'bg-yellow-500/20 border-yellow-500/60 text-yellow-400 cursor-default'
              : bet.isOpponentSelection && bet.enabled
                ? 'bg-pink-500/20 border-pink-500/60 text-pink-400 hover:bg-pink-500/30 shadow-sm shadow-pink-500/10 ring-1 ring-pink-500/30'
                : bet.enabled
                  ? 'bg-green-500/20 border-green-500/60 text-green-400 hover:bg-green-500/30 shadow-sm shadow-green-500/10'
                  : 'bg-slate-800/50 border-border/30 text-slate-600 cursor-not-allowed opacity-50'"
          >
            <div class="flex flex-col items-center gap-1">
              <span class="flex items-center gap-1">
                <span v-if="pendingBet === `${bet.amount}-${bet.currency}`" class="w-3 h-3 border-2 border-current border-t-transparent rounded-full animate-spin" />
                {{ bet.label }}
              </span>
              <span v-if="bet.isMySelection" class="text-[10px] text-yellow-400">
                {{ t('battle.readyRoom.currentBet', 'Current') }}
              </span>
              <span v-else-if="bet.isOpponentSelection" class="text-[10px] text-pink-400">
                &#9733; {{ t('battle.readyRoom.opponentPick', 'Opponent\'s pick') }}
              </span>
              <span v-else-if="!bet.enabled" class="text-[10px] text-red-400">
                {{ t('battle.insufficientFunds', 'Insufficient') }}
              </span>
              <span v-else class="text-[10px] text-green-400">
                {{ t('battle.winPot', 'Win') }} {{ bet.amount * 2 }} {{ bet.currency }}
              </span>
            </div>
          </button>
        </div>
      </div>

      <!-- STATE 3: I selected, waiting for opponent -->
      <div v-else-if="iHaveSelected && !opponentHasSelected" class="space-y-3">
        <div class="px-5 py-3 bg-amber-500/10 border border-amber-500/30 rounded-xl text-center">
          <div class="text-xs text-slate-500 uppercase tracking-wider mb-1">{{ t('battle.readyRoom.yourBet', 'Your bet') }}</div>
          <div class="text-2xl font-bold text-amber-400">{{ myBetAmount }} {{ myBetCurrency }}</div>
          <div class="text-xs text-slate-500 mt-1">{{ t('battle.readyRoom.winPotential', 'Potential win') }}: {{ myBetAmount * 2 }} {{ myBetCurrency }}</div>
        </div>
        <div class="py-4 px-6 bg-yellow-500/10 border border-yellow-500/30 rounded-xl text-center">
          <div class="flex items-center justify-center gap-2 text-yellow-400 mb-2">
            <span class="w-3 h-3 bg-yellow-400 rounded-full animate-pulse"></span>
            <span class="font-semibold">{{ t('battle.readyRoom.waitingOpponent', 'Waiting for opponent...') }}</span>
          </div>
          <p class="text-xs text-slate-500">{{ t('battle.readyRoom.opponentMustSelect', 'Opponent must select the same bet') }}</p>
        </div>
        <!-- Allow changing bet -->
        <div class="text-center">
          <div class="text-xs text-slate-500 uppercase tracking-wider font-semibold mb-2">
            {{ t('battle.readyRoom.changeBet', 'Change your bet') }}
          </div>
        </div>
        <div v-for="group in groupedBets" :key="group.currency" class="flex gap-2">
          <button
            v-for="bet in group.bets"
            :key="`${bet.amount}-${bet.currency}`"
            @click="selectBet(bet.amount, bet.currency)"
            :disabled="!bet.enabled || loading || bet.isMySelection"
            class="flex-1 px-3 py-2.5 rounded-lg text-sm font-bold transition-all border"
            :class="bet.isMySelection
              ? 'bg-yellow-500/20 border-yellow-500/60 text-yellow-400 cursor-default'
              : bet.enabled
                ? 'bg-slate-800/50 border-border/30 text-slate-400 hover:bg-slate-700/50'
                : 'bg-slate-800/50 border-border/30 text-slate-600 cursor-not-allowed opacity-50'"
          >
            <div class="flex flex-col items-center gap-1">
              <span class="flex items-center gap-1">
                <span v-if="pendingBet === `${bet.amount}-${bet.currency}`" class="w-3 h-3 border-2 border-current border-t-transparent rounded-full animate-spin" />
                {{ bet.label }}
              </span>
              <span v-if="bet.isMySelection" class="text-[10px] text-yellow-400">&#10003;</span>
            </div>
          </button>
        </div>
      </div>

      <!-- STATE 4: Neither has chosen (or only opponent has) → Show bet selection -->
      <div v-else class="space-y-3">
        <div class="text-center mb-2">
          <div class="text-xs text-slate-500 uppercase tracking-wider font-semibold">
            {{ t('battle.readyRoom.selectBet', 'Select Your Bet') }}
          </div>
          <div v-if="opponentHasSelected" class="text-xs text-pink-400 mt-1">
            {{ t('battle.readyRoom.opponentChose', 'Opponent chose') }}: <span class="font-semibold">{{ opponentBetAmount }} {{ opponentBetCurrency }}</span>
          </div>
        </div>
        <div v-for="group in groupedBets" :key="group.currency" class="flex gap-2">
          <button
            v-for="bet in group.bets"
            :key="`${bet.amount}-${bet.currency}`"
            @click="selectBet(bet.amount, bet.currency)"
            :disabled="!bet.enabled || loading"
            class="flex-1 px-3 py-3 rounded-lg text-sm font-bold transition-all border"
            :class="bet.isOpponentSelection && bet.enabled
              ? 'bg-pink-500/20 border-pink-500/60 text-pink-400 hover:bg-pink-500/30 shadow-sm shadow-pink-500/10 ring-1 ring-pink-500/30'
              : bet.enabled
                ? 'bg-green-500/20 border-green-500/60 text-green-400 hover:bg-green-500/30 shadow-sm shadow-green-500/10'
                : 'bg-slate-800/50 border-border/30 text-slate-600 cursor-not-allowed opacity-50'"
          >
            <div class="flex flex-col items-center gap-1">
              <span class="flex items-center gap-1">
                <span v-if="pendingBet === `${bet.amount}-${bet.currency}`" class="w-3 h-3 border-2 border-current border-t-transparent rounded-full animate-spin" />
                {{ bet.label }}
              </span>
              <span v-if="bet.isOpponentSelection && bet.enabled" class="text-[10px] text-pink-400">
                &#9733; {{ t('battle.readyRoom.matchToStart', 'Match to start!') }}
              </span>
              <span v-else-if="!bet.enabled" class="text-[10px] text-red-400">
                {{ t('battle.insufficientFunds', 'Insufficient') }}
              </span>
              <span v-else class="text-[10px] text-green-400">
                {{ t('battle.winPot', 'Win') }} {{ bet.amount * 2 }} {{ bet.currency }}
              </span>
            </div>
          </button>
        </div>
      </div>
    </div>

    <!-- Action Buttons -->
    <div v-if="!bothReady" class="mt-4 flex items-center gap-4">
      <button
        @click="emit('cancel')"
        :disabled="loading"
        class="text-sm text-red-400/70 hover:text-red-400 transition-colors"
      >
        {{ t('battle.readyRoom.exit', 'Exit') }}
      </button>
      <button
        @click="emit('findAnother')"
        :disabled="loading"
        class="text-sm text-blue-400/70 hover:text-blue-400 transition-colors"
      >
        {{ t('battle.readyRoom.findAnother', 'Find another opponent') }}
      </button>
    </div>
  </div>
</template>
