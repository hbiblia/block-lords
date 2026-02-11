<script setup lang="ts">
import { ref, onMounted } from 'vue';
import type { CardDefinition } from '@/utils/battleCards';
import { getCardBorderClass, getCardBgClass, getCardTextClass } from '@/utils/battleCards';
import { getCardIcon, getCardIconColor, renderPixelIcon } from '@/utils/battlePixelArt';

const props = defineProps<{
  card: CardDefinition;
  disabled?: boolean;
  played?: boolean;
}>();

const emit = defineEmits<{
  play: [cardId: string];
}>();

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
</script>

<template>
  <button
    @click="handleClick"
    :disabled="disabled || played"
    class="relative flex flex-col items-center justify-between p-1.5 rounded-lg border-2 transition-all duration-200 w-full"
    :class="[
      getCardBorderClass(card.type),
      getCardBgClass(card.type),
      disabled || played
        ? 'opacity-40 grayscale cursor-not-allowed'
        : 'hover:scale-105 hover:shadow-lg cursor-pointer active:scale-95',
      animating ? 'scale-110 opacity-0' : '',
    ]"
  >
    <!-- Energy cost badge -->
    <div class="absolute -top-1.5 -right-1.5 w-5 h-5 rounded-full bg-yellow-500/90 text-black text-[10px] font-bold flex items-center justify-center shadow">
      {{ card.cost }}
    </div>

    <!-- Icon -->
    <canvas ref="iconCanvas" class="w-4 h-4 mt-0.5" />

    <!-- Value -->
    <div class="text-lg font-bold leading-none" :class="getCardTextClass(card.type)">
      {{ card.value }}
    </div>

    <!-- Name -->
    <div class="text-[9px] text-slate-300 leading-tight text-center truncate w-full">
      {{ card.name }}
    </div>
  </button>
</template>
