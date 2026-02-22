<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue';

const props = withDefaults(defineProps<{
  opacity?: number;
  speed?: number;
  color?: string;
  density?: number;
}>(), {
  opacity: 0.12,
  speed: 2,
  color: '#00ff41',
  density: 20,
});

const canvas = ref<HTMLCanvasElement | null>(null);
let animationId: number | null = null;
let columns: number[] = [];
let ctx: CanvasRenderingContext2D | null = null;

const chars = 'アイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワヲン0123456789ABCDEF';

function initCanvas() {
  if (!canvas.value) return;
  const el = canvas.value;
  const parent = el.parentElement;
  if (!parent) return;

  el.width = parent.clientWidth;
  el.height = parent.clientHeight;

  ctx = el.getContext('2d');
  if (!ctx) return;

  const fontSize = props.density;
  const colCount = Math.floor(el.width / fontSize);
  columns = new Array(colCount).fill(0).map(() => Math.random() * el.height / fontSize);
}

function draw() {
  if (!ctx || !canvas.value) return;
  const el = canvas.value;

  ctx.fillStyle = `rgba(0, 0, 0, 0.05)`;
  ctx.fillRect(0, 0, el.width, el.height);

  ctx.fillStyle = props.color;
  ctx.font = `${props.density}px 'JetBrains Mono', monospace`;
  ctx.globalAlpha = props.opacity;

  for (let i = 0; i < columns.length; i++) {
    const char = chars[Math.floor(Math.random() * chars.length)];
    const x = i * props.density;
    const y = columns[i] * props.density;

    ctx.fillText(char, x, y);

    if (y > el.height && Math.random() > 0.975) {
      columns[i] = 0;
    }
    columns[i] += props.speed * 0.1;
  }

  ctx.globalAlpha = 1;
  animationId = requestAnimationFrame(draw);
}

function handleVisibility() {
  if (document.hidden) {
    if (animationId) {
      cancelAnimationFrame(animationId);
      animationId = null;
    }
  } else {
    if (!animationId) {
      animationId = requestAnimationFrame(draw);
    }
  }
}

function handleResize() {
  initCanvas();
}

onMounted(() => {
  initCanvas();
  animationId = requestAnimationFrame(draw);
  document.addEventListener('visibilitychange', handleVisibility);
  window.addEventListener('resize', handleResize);
});

onUnmounted(() => {
  if (animationId) {
    cancelAnimationFrame(animationId);
    animationId = null;
  }
  document.removeEventListener('visibilitychange', handleVisibility);
  window.removeEventListener('resize', handleResize);
});
</script>

<template>
  <canvas
    ref="canvas"
    class="absolute inset-0 pointer-events-none"
  />
</template>
