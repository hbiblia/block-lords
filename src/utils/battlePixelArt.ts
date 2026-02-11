// === CARD BATTLE - Pixel Art Icons (8x8) ===
// Each icon is an 8x8 grid: 0 = transparent, 1 = primary color

// Sword icon (attack cards)
export const SWORD_ICON: number[][] = [
  [0, 0, 0, 0, 0, 0, 1, 1],
  [0, 0, 0, 0, 0, 1, 1, 0],
  [0, 0, 0, 0, 1, 1, 0, 0],
  [0, 0, 0, 1, 1, 0, 0, 0],
  [0, 1, 1, 1, 0, 0, 0, 0],
  [1, 1, 1, 0, 0, 0, 0, 0],
  [0, 1, 0, 0, 0, 0, 0, 0],
  [1, 0, 0, 0, 0, 0, 0, 0],
];

// Shield icon (defense cards)
export const SHIELD_ICON: number[][] = [
  [0, 1, 1, 1, 1, 1, 1, 0],
  [1, 1, 1, 1, 1, 1, 1, 1],
  [1, 1, 1, 1, 1, 1, 1, 1],
  [1, 1, 1, 1, 1, 1, 1, 1],
  [1, 1, 1, 1, 1, 1, 1, 1],
  [0, 1, 1, 1, 1, 1, 1, 0],
  [0, 0, 1, 1, 1, 1, 0, 0],
  [0, 0, 0, 1, 1, 0, 0, 0],
];

// Star icon (special cards)
export const STAR_ICON: number[][] = [
  [0, 0, 0, 1, 1, 0, 0, 0],
  [0, 0, 0, 1, 1, 0, 0, 0],
  [1, 1, 1, 1, 1, 1, 1, 1],
  [0, 1, 1, 1, 1, 1, 1, 0],
  [0, 0, 1, 1, 1, 1, 0, 0],
  [0, 1, 1, 0, 0, 1, 1, 0],
  [1, 1, 0, 0, 0, 0, 1, 1],
  [1, 0, 0, 0, 0, 0, 0, 1],
];

// Heart icon (HP)
export const HEART_ICON: number[][] = [
  [0, 1, 1, 0, 0, 1, 1, 0],
  [1, 1, 1, 1, 1, 1, 1, 1],
  [1, 1, 1, 1, 1, 1, 1, 1],
  [1, 1, 1, 1, 1, 1, 1, 1],
  [0, 1, 1, 1, 1, 1, 1, 0],
  [0, 0, 1, 1, 1, 1, 0, 0],
  [0, 0, 0, 1, 1, 0, 0, 0],
  [0, 0, 0, 0, 0, 0, 0, 0],
];

// Lightning bolt icon (energy)
export const ENERGY_ICON: number[][] = [
  [0, 0, 0, 1, 1, 1, 0, 0],
  [0, 0, 1, 1, 1, 0, 0, 0],
  [0, 1, 1, 1, 0, 0, 0, 0],
  [1, 1, 1, 1, 1, 1, 0, 0],
  [0, 0, 1, 1, 1, 1, 0, 0],
  [0, 0, 0, 1, 1, 0, 0, 0],
  [0, 0, 1, 1, 0, 0, 0, 0],
  [0, 1, 1, 0, 0, 0, 0, 0],
];

export type PixelIcon = number[][];

import type { CardType } from './battleCards';

export function getCardIcon(type: CardType): PixelIcon {
  switch (type) {
    case 'attack': return SWORD_ICON;
    case 'defense': return SHIELD_ICON;
    case 'special': return STAR_ICON;
  }
}

export function getCardIconColor(type: CardType): string {
  switch (type) {
    case 'attack': return '#ef4444'; // red-500
    case 'defense': return '#3b82f6'; // blue-500
    case 'special': return '#a855f7'; // purple-500
  }
}

// Render pixel icon to canvas
export function renderPixelIcon(
  canvas: HTMLCanvasElement,
  icon: PixelIcon,
  color: string,
  pixelSize: number = 3
): void {
  const ctx = canvas.getContext('2d');
  if (!ctx) return;

  const size = icon.length;
  canvas.width = size * pixelSize;
  canvas.height = size * pixelSize;

  ctx.clearRect(0, 0, canvas.width, canvas.height);
  ctx.fillStyle = color;

  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      if (icon[y][x]) {
        ctx.fillRect(x * pixelSize, y * pixelSize, pixelSize, pixelSize);
      }
    }
  }
}
