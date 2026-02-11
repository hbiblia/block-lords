<script setup lang="ts">
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import type { CardDefinition } from '@/utils/battleCards';
import BattleCard from './BattleCard.vue';

defineProps<{
  cards: CardDefinition[];
  energy: number;
  isMyTurn: boolean;
  cardsPlayedCount?: number;
}>();

const emit = defineEmits<{
  play: [cardId: string];
}>();

const { t } = useI18n();
const selectedCard = ref<CardDefinition | null>(null);

function handlePlay(cardId: string) {
  emit('play', cardId);
}

function showCardDetail(card: CardDefinition) {
  selectedCard.value = card;
}

function closeDetail() {
  selectedCard.value = null;
}

function getEffectDescription(card: CardDefinition): string {
  const e = card.effect;
  switch (e.kind) {
    case 'damage':
      return t('battle.detail.damage', { amount: e.amount });
    case 'damage_ignore_shield':
      return t('battle.detail.damageIgnoreShield', { amount: e.amount, ignore: e.ignoreShield });
    case 'double_hit':
      return t('battle.detail.doubleHit', { amount: e.amount, total: e.amount * 2 });
    case 'damage_self':
      return t('battle.detail.damageSelf', { amount: e.amount, self: e.selfDamage });
    case 'shield':
      return t('battle.detail.shield', { amount: e.amount });
    case 'shield_counter':
      return t('battle.detail.shieldCounter', { shield: e.shield, damage: e.damage });
    case 'shield_draw':
      return t('battle.detail.shieldDraw', { shield: e.shield, draw: e.draw });
    case 'heal':
      return t('battle.detail.heal', { amount: e.amount });
    case 'weaken':
      return t('battle.detail.weaken', { reduction: e.reduction });
    case 'drain':
      return t('battle.detail.drain', { damage: e.damage, heal: e.heal });
    default:
      return '';
  }
}
</script>

<template>
  <div class="p-2 relative">
    <!-- Hand info -->
    <div class="flex items-center justify-between mb-1.5 px-1">
      <span class="text-[10px] text-slate-500 uppercase tracking-wider font-semibold">
        {{ t('battle.yourHand', 'Your Hand') }} ({{ cards.length }})
      </span>
      <span v-if="cardsPlayedCount && cardsPlayedCount > 0" class="text-[10px] text-yellow-400">
        {{ t('battle.queued', { n: cardsPlayedCount }) }}
      </span>
    </div>

    <!-- Cards grid -->
    <div v-if="cards.length > 0" class="grid grid-cols-3 gap-1.5">
      <BattleCard
        v-for="(card, index) in cards"
        :key="`${card.id}-${index}`"
        :card="card"
        :disabled="!isMyTurn || energy < card.cost"
        @play="handlePlay"
        @show-detail="showCardDetail"
      />
    </div>

    <!-- Empty hand -->
    <div v-else class="text-center py-4 text-slate-500 text-xs">
      {{ t('battle.noCards', 'No cards in hand') }}
    </div>

    <!-- Card Detail Overlay -->
    <Teleport to="body">
      <div
        v-if="selectedCard"
        class="fixed inset-0 z-[60] flex items-center justify-center p-4"
        @click="closeDetail"
      >
        <div class="absolute inset-0 bg-black/60 backdrop-blur-sm" />
        <div
          class="relative w-full max-w-[280px] rounded-2xl border overflow-hidden animate-fade-in"
          :class="{
            'border-red-500/50 shadow-lg shadow-red-500/20': selectedCard.type === 'attack',
            'border-blue-500/50 shadow-lg shadow-blue-500/20': selectedCard.type === 'defense',
            'border-purple-500/50 shadow-lg shadow-purple-500/20': selectedCard.type === 'special',
          }"
          @click.stop
        >
          <!-- Card background -->
          <div
            class="absolute inset-0"
            :class="{
              'bg-gradient-to-b from-red-950 via-slate-950 to-slate-950': selectedCard.type === 'attack',
              'bg-gradient-to-b from-blue-950 via-slate-950 to-slate-950': selectedCard.type === 'defense',
              'bg-gradient-to-b from-purple-950 via-slate-950 to-slate-950': selectedCard.type === 'special',
            }"
          />

          <!-- Top glow -->
          <div
            class="absolute top-0 left-0 right-0 h-[2px]"
            :class="{
              'bg-gradient-to-r from-transparent via-red-400 to-transparent': selectedCard.type === 'attack',
              'bg-gradient-to-r from-transparent via-blue-400 to-transparent': selectedCard.type === 'defense',
              'bg-gradient-to-r from-transparent via-purple-400 to-transparent': selectedCard.type === 'special',
            }"
          />

          <div class="relative p-5">
            <!-- Header: Type + Cost -->
            <div class="flex items-center justify-between mb-4">
              <span
                class="text-[10px] font-black uppercase tracking-widest px-2 py-1 rounded"
                :class="{
                  'bg-red-500/20 text-red-300': selectedCard.type === 'attack',
                  'bg-blue-500/20 text-blue-300': selectedCard.type === 'defense',
                  'bg-purple-500/20 text-purple-300': selectedCard.type === 'special',
                }"
              >
                <span v-if="selectedCard.type === 'attack'">&#9876; {{ t('battle.info.attack', 'Attack') }}</span>
                <span v-else-if="selectedCard.type === 'defense'">&#128737; {{ t('battle.info.defense', 'Defense') }}</span>
                <span v-else>&#10024; {{ t('battle.info.special', 'Special') }}</span>
              </span>
              <div class="flex items-center gap-1">
                <span class="text-[10px] text-slate-500 font-medium">{{ t('battle.detail.cost', 'Cost') }}:</span>
                <span class="px-2 py-0.5 rounded bg-gradient-to-br from-yellow-400 to-amber-500 text-black text-xs font-black">
                  {{ selectedCard.cost }} &#9889;
                </span>
              </div>
            </div>

            <!-- Big value -->
            <div class="text-center mb-3">
              <div
                class="text-5xl font-black leading-none drop-shadow-md"
                :class="{
                  'text-red-400': selectedCard.type === 'attack',
                  'text-blue-400': selectedCard.type === 'defense',
                  'text-purple-400': selectedCard.type === 'special',
                }"
              >
                {{ selectedCard.value }}
              </div>
            </div>

            <!-- Divider -->
            <div
              class="w-12 h-[2px] mx-auto mb-3 rounded-full"
              :class="{
                'bg-gradient-to-r from-transparent via-red-400 to-transparent': selectedCard.type === 'attack',
                'bg-gradient-to-r from-transparent via-blue-400 to-transparent': selectedCard.type === 'defense',
                'bg-gradient-to-r from-transparent via-purple-400 to-transparent': selectedCard.type === 'special',
              }"
            />

            <!-- Card name -->
            <h3 class="text-lg font-black text-white text-center mb-1">
              {{ t(selectedCard.nameKey, selectedCard.name) }}
            </h3>

            <!-- Short description -->
            <p class="text-xs text-slate-400 text-center mb-4">
              {{ t(selectedCard.descriptionKey, selectedCard.description) }}
            </p>

            <!-- Effect detail box -->
            <div class="bg-slate-800/50 rounded-xl p-3 border border-slate-700/40 mb-4">
              <div class="text-[10px] text-slate-500 uppercase tracking-wider font-semibold mb-1.5">
                {{ t('battle.detail.effect', 'Effect') }}
              </div>
              <p class="text-sm text-slate-200 leading-relaxed">
                {{ getEffectDescription(selectedCard) }}
              </p>
            </div>

            <!-- Close hint -->
            <p class="text-center text-[10px] text-slate-600">
              {{ t('battle.detail.tapToClose', 'Tap anywhere to close') }}
            </p>
          </div>
        </div>
      </div>
    </Teleport>
  </div>
</template>
