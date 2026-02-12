<script setup lang="ts">
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import type { CardDefinition } from '@/utils/battleCards';
import { getCardIcon, getCardIconColor, renderPixelIcon } from '@/utils/battlePixelArt';

const props = defineProps<{
  card: CardDefinition;
  disabled?: boolean;
  played?: boolean;
}>();

const emit = defineEmits<{
  play: [cardId: string];
  showDetail: [card: CardDefinition];
}>();

const { t } = useI18n();
const iconCanvas = ref<HTMLCanvasElement | null>(null);
const animating = ref(false);

onMounted(() => {
  if (iconCanvas.value) {
    const icon = getCardIcon(props.card.type);
    const color = getCardIconColor(props.card.type);
    renderPixelIcon(iconCanvas.value, icon, color, 2);
  }
});

function handleClick() {
  if (props.disabled || props.played) return;
  animating.value = true;
  setTimeout(() => {
    emit('play', props.card.id);
    animating.value = false;
  }, 150);
}

function handleShowDetail(e: Event) {
  e.preventDefault();
  e.stopPropagation();
  emit('showDetail', props.card);
}

function typeLabel(type: string): string {
  switch (type) {
    case 'attack': return t('battle.typeAttack', 'ATK');
    case 'defense': return t('battle.typeDefense', 'DEF');
    case 'special': return t('battle.typeSpecial', 'SPL');
    default: return '';
  }
}
</script>

<template>
  <button
    @click="handleClick"
    @contextmenu="handleShowDetail"
    :disabled="disabled || played"
    class="group relative flex flex-col items-center rounded-xl border transition-all duration-200 w-full h-full overflow-hidden"
    :class="[
      disabled || played
        ? 'opacity-35 grayscale cursor-not-allowed border-slate-700/50'
        : 'cursor-pointer hover:-translate-y-1 hover:shadow-xl active:scale-95 active:translate-y-0',
      animating ? 'scale-110 opacity-0' : '',
      card.type === 'attack'
        ? 'border-red-500/50 hover:border-red-400/80 hover:shadow-red-500/20'
        : card.type === 'defense'
          ? 'border-blue-500/50 hover:border-blue-400/80 hover:shadow-blue-500/20'
          : 'border-purple-500/50 hover:border-purple-400/80 hover:shadow-purple-500/20',
    ]"
  >
    <!-- Background gradient -->
    <div
      class="absolute inset-0 opacity-30"
      :class="{
        'bg-gradient-to-b from-red-900/80 via-red-950/40 to-slate-950': card.type === 'attack',
        'bg-gradient-to-b from-blue-900/80 via-blue-950/40 to-slate-950': card.type === 'defense',
        'bg-gradient-to-b from-purple-900/80 via-purple-950/40 to-slate-950': card.type === 'special',
      }"
    />

    <!-- Top glow line -->
    <div
      class="absolute top-0 left-0 right-0 h-[2px]"
      :class="{
        'bg-gradient-to-r from-transparent via-red-400 to-transparent': card.type === 'attack',
        'bg-gradient-to-r from-transparent via-blue-400 to-transparent': card.type === 'defense',
        'bg-gradient-to-r from-transparent via-purple-400 to-transparent': card.type === 'special',
      }"
    />

    <!-- Energy cost badge -->
    <div
      class="absolute -top-0.5 -right-0.5 w-6 h-6 rounded-bl-lg rounded-tr-xl flex items-center justify-center text-[11px] font-black z-10 shadow-md bg-gradient-to-br from-yellow-400 to-amber-500 text-black"
    >
      {{ card.cost }}
    </div>

    <!-- Info button (top-left) -->
    <div
      class="absolute -bottom-0.5 -right-0.5 w-6 h-6 rounded-tl-lg rounded-br-xl flex items-center justify-center text-[10px] font-black z-10 bg-slate-700/90 text-slate-300 hover:bg-slate-600 hover:text-white cursor-help shadow-md transition-colors"
      @click.stop="handleShowDetail($event)"
    >
      ?
    </div>

    <!-- Card content -->
    <div class="relative z-[1] flex flex-col items-center w-full px-1.5 pt-2 pb-1.5">
      <!-- Type badge + icon row -->
      <div class="flex items-center gap-1.5 w-full mb-1">
        <canvas ref="iconCanvas" class="w-5 h-5 flex-shrink-0" />
        <span
          class="text-[9px] font-black uppercase tracking-wider px-1.5 py-0.5 rounded-sm"
          :class="{
            'bg-red-500/25 text-red-300': card.type === 'attack',
            'bg-blue-500/25 text-blue-300': card.type === 'defense',
            'bg-purple-500/25 text-purple-300': card.type === 'special',
          }"
        >
          {{ typeLabel(card.type) }}
        </span>
      </div>

      <!-- Value (big number) -->
      <div
        class="text-2xl font-black leading-none mb-1 drop-shadow-sm"
        :class="{
          'text-red-300': card.type === 'attack',
          'text-blue-300': card.type === 'defense',
          'text-purple-300': card.type === 'special',
        }"
      >
        {{ card.value }}
      </div>

      <!-- Divider -->
      <div
        class="w-10 h-[1px] mb-1 opacity-40"
        :class="{
          'bg-red-400': card.type === 'attack',
          'bg-blue-400': card.type === 'defense',
          'bg-purple-400': card.type === 'special',
        }"
      />

      <!-- Name -->
      <div class="text-[11px] font-bold text-slate-100 leading-tight text-center truncate w-full">
        {{ t(card.nameKey, card.name) }}
      </div>

      <!-- Description -->
      <div class="text-[9px] text-slate-400 leading-tight text-center truncate w-full mt-0.5">
        {{ t(card.descriptionKey, card.description) }}
      </div>
    </div>
  </button>
</template>
