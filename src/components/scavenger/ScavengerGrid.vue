<script setup lang="ts">
import { inject } from 'vue';

const scavenger = inject<ReturnType<typeof import('@/composables/useScavenger').useScavenger>>('scavenger')!;

function handleClick(x: number, y: number) {
  scavenger.movePlayer({ x, y });
}

function tileClass(x: number, y: number): string {
  const info = scavenger.getTileContent(x, y);
  const base = 'scav-tile flex items-center justify-center text-sm select-none transition-all duration-150';

  // Fog of war
  if (!info.revealed) return `${base} bg-black/90`;
  if (!info.visible) return `${base} bg-[#1a1b2e]/40 opacity-40`;

  // Player
  if (info.isPlayer) return `${base} bg-green-500/25 shadow-[0_0_10px_rgba(34,197,94,0.5)] ring-1 ring-green-500/50`;

  // Enemy
  if (info.isEnemy) return `${base} bg-red-500/25 shadow-[0_0_10px_rgba(239,68,68,0.5)] animate-pulse`;

  // Tile types
  switch (info.type) {
    case 'wall':
      return `${base} bg-[#151628] border border-slate-700/40`;
    case 'exit':
      return `${base} bg-green-500/10 ring-2 ring-amber-400/60 animate-[pulse_2s_ease-in-out_infinite]`;
    case 'loot_gc':
      return info.collected
        ? `${base} bg-[#1a1b2e]`
        : `${base} bg-amber-500/15 shadow-[0_0_8px_rgba(245,158,11,0.4)]`;
    case 'loot_material':
      return info.collected
        ? `${base} bg-[#1a1b2e]`
        : `${base} bg-amber-500/10 shadow-[0_0_6px_rgba(245,158,11,0.25)]`;
    case 'loot_data':
      return info.collected
        ? `${base} bg-[#1a1b2e]`
        : `${base} bg-purple-500/15 shadow-[0_0_8px_rgba(168,85,247,0.4)]`;
    case 'terminal':
      return info.collected
        ? `${base} bg-[#1a1b2e]`
        : `${base} bg-cyan-500/15 shadow-[0_0_8px_rgba(6,182,212,0.4)]`;
    case 'keycard':
      return info.collected
        ? `${base} bg-[#1a1b2e]`
        : `${base} bg-purple-500/20 shadow-[0_0_6px_rgba(168,85,247,0.4)]`;
    case 'locked_door':
      return info.locked
        ? `${base} bg-purple-500/10 border border-purple-500/40`
        : info.collected
          ? `${base} bg-[#1a1b2e]`
          : `${base} bg-amber-500/15 shadow-[0_0_8px_rgba(245,158,11,0.4)]`;
    default:
      return `${base} bg-[#1a1b2e]`;
  }
}

function adjacentClass(x: number, y: number): string {
  const info = scavenger.getTileContent(x, y);
  if (!info.isAdjacent || !scavenger.canMove.value) return '';
  if (info.isEnemy) return '';
  return 'cursor-pointer ring-1 ring-white/20 hover:ring-white/40 hover:bg-white/5';
}

function tileIcon(x: number, y: number): string {
  const info = scavenger.getTileContent(x, y);

  if (!info.revealed || !info.visible) return '';
  if (info.isPlayer) return '🧑‍💻';
  if (info.isEnemy) return '👾';

  switch (info.type) {
    case 'wall': return '';
    case 'exit': return '🚪';
    case 'loot_gc': return info.collected ? '' : '🪙';
    case 'loot_material': return info.collected ? '' : '💎';
    case 'loot_data': return info.collected ? '' : '📡';
    case 'terminal': return info.collected ? '' : '💻';
    case 'keycard': return info.collected ? '' : '🔑';
    case 'locked_door': return info.locked ? '🔒' : info.collected ? '' : '🪙';
    default: return '';
  }
}
</script>

<template>
  <div class="flex items-center justify-center px-3 py-3">
    <div
      class="grid gap-[1px] rounded-lg overflow-hidden bg-slate-700/30"
      :style="{ gridTemplateColumns: `repeat(${scavenger.GRID_SIZE}, 1fr)` }"
    >
      <div
        v-for="y in scavenger.GRID_SIZE"
        :key="'row-' + y"
        class="contents"
      >
        <div
          v-for="x in scavenger.GRID_SIZE"
          :key="x + '-' + y"
          class="w-9 h-9 sm:w-10 sm:h-10"
          :class="[tileClass(x - 1, y - 1), adjacentClass(x - 1, y - 1)]"
          @click="handleClick(x - 1, y - 1)"
        >
          <span class="text-xs sm:text-sm leading-none">{{ tileIcon(x - 1, y - 1) }}</span>
        </div>
      </div>
    </div>
  </div>
</template>
