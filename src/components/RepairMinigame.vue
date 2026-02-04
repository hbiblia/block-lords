<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();

const emit = defineEmits<{
  (e: 'complete', success: boolean): void;
  (e: 'cancel'): void;
}>();

// Game configuration
const GAME_DURATION = 20000; // 20 seconds
const GRID_SIZE = 16; // 4x4 grid
const BUGS_TO_WIN = 12; // bugs needed to win
const BUG_SPAWN_INTERVAL = 800; // ms between bug spawns
const BUG_LIFETIME_MIN = 1200; // minimum bug lifetime
const BUG_LIFETIME_MAX = 2500; // maximum bug lifetime
const MAX_ACTIVE_BUGS = 4; // max bugs at once

// Game state
const gameStarted = ref(false);
const gameEnded = ref(false);
const timeRemaining = ref(GAME_DURATION);
const bugsEliminated = ref(0);
const activeBugs = ref<Map<number, { id: number; cell: number; timeout: number }>>(new Map());

// Timers
let gameTimer: number | null = null;
let spawnTimer: number | null = null;
let countdownTimer: number | null = null;

// Bug types for variety
const bugTypes = ['🐛', '🪲', '🐜', '🦗', '🕷️'];

// Computed
const progress = computed(() => (bugsEliminated.value / BUGS_TO_WIN) * 100);
const timeProgress = computed(() => (timeRemaining.value / GAME_DURATION) * 100);
const isWinning = computed(() => bugsEliminated.value >= BUGS_TO_WIN);

// Get random bug emoji
function getRandomBug(): string {
  return bugTypes[Math.floor(Math.random() * bugTypes.length)];
}

// Get random empty cell
function getRandomEmptyCell(): number | null {
  const occupiedCells = new Set([...activeBugs.value.values()].map(b => b.cell));
  const availableCells = [];

  for (let i = 0; i < GRID_SIZE; i++) {
    if (!occupiedCells.has(i)) {
      availableCells.push(i);
    }
  }

  if (availableCells.length === 0) return null;
  return availableCells[Math.floor(Math.random() * availableCells.length)];
}

// Spawn a new bug
let bugIdCounter = 0;
function spawnBug() {
  if (gameEnded.value || activeBugs.value.size >= MAX_ACTIVE_BUGS) return;

  const cell = getRandomEmptyCell();
  if (cell === null) return;

  const bugId = ++bugIdCounter;
  const lifetime = BUG_LIFETIME_MIN + Math.random() * (BUG_LIFETIME_MAX - BUG_LIFETIME_MIN);

  const timeout = window.setTimeout(() => {
    activeBugs.value.delete(bugId);
  }, lifetime);

  activeBugs.value.set(bugId, { id: bugId, cell, timeout });
}

// Click on a bug
function squashBug(bugId: number) {
  const bug = activeBugs.value.get(bugId);
  if (!bug) return;

  window.clearTimeout(bug.timeout);
  activeBugs.value.delete(bugId);
  bugsEliminated.value++;

  // Check win condition
  if (bugsEliminated.value >= BUGS_TO_WIN) {
    endGame(true);
  }
}

// Start the game
function startGame() {
  gameStarted.value = true;
  bugsEliminated.value = 0;
  activeBugs.value.clear();
  timeRemaining.value = GAME_DURATION;
  bugIdCounter = 0;

  // Start countdown
  countdownTimer = window.setInterval(() => {
    timeRemaining.value -= 100;
    if (timeRemaining.value <= 0) {
      endGame(false);
    }
  }, 100);

  // Start spawning bugs
  spawnTimer = window.setInterval(spawnBug, BUG_SPAWN_INTERVAL);

  // Spawn first bug immediately
  spawnBug();
}

// End the game
function endGame(won: boolean) {
  gameEnded.value = true;

  // Clear all timers
  if (countdownTimer) {
    clearInterval(countdownTimer);
    countdownTimer = null;
  }
  if (spawnTimer) {
    clearInterval(spawnTimer);
    spawnTimer = null;
  }

  // Clear all bug timers
  activeBugs.value.forEach(bug => {
    window.clearTimeout(bug.timeout);
  });
  activeBugs.value.clear();

  // Emit result after short delay
  setTimeout(() => {
    emit('complete', won);
  }, 1500);
}

// Cancel game
function cancelGame() {
  endGame(false);
  emit('cancel');
}

// Cleanup on unmount
onUnmounted(() => {
  if (countdownTimer) clearInterval(countdownTimer);
  if (spawnTimer) clearInterval(spawnTimer);
  activeBugs.value.forEach(bug => {
    window.clearTimeout(bug.timeout);
  });
});

// Get bug at cell
function getBugAtCell(cellIndex: number): { id: number; emoji: string } | null {
  for (const [id, bug] of activeBugs.value) {
    if (bug.cell === cellIndex) {
      return { id, emoji: getRandomBug() };
    }
  }
  return null;
}

// Check if cell has bug
function cellHasBug(cellIndex: number): number | null {
  for (const [id, bug] of activeBugs.value) {
    if (bug.cell === cellIndex) {
      return id;
    }
  }
  return null;
}
</script>

<template>
  <div class="repair-minigame">
    <!-- Pre-game instructions -->
    <div v-if="!gameStarted" class="text-center">
      <div class="text-6xl mb-4">🐛</div>
      <h3 class="text-xl font-bold text-text-primary mb-2">{{ t('minigame.bugs.title') }}</h3>
      <p class="text-text-secondary mb-4">{{ t('minigame.bugs.instructions') }}</p>

      <div class="flex items-center justify-center gap-4 mb-6 text-sm text-text-muted">
        <div class="flex items-center gap-2">
          <span class="text-lg">🎯</span>
          <span>{{ t('minigame.bugs.goal', { count: BUGS_TO_WIN }) }}</span>
        </div>
        <div class="flex items-center gap-2">
          <span class="text-lg">⏱️</span>
          <span>{{ t('minigame.bugs.time', { seconds: GAME_DURATION / 1000 }) }}</span>
        </div>
      </div>

      <div class="flex gap-3 justify-center">
        <button @click="emit('cancel')" class="btn btn-ghost">
          {{ t('common.cancel') }}
        </button>
        <button @click="startGame" class="btn btn-primary">
          {{ t('minigame.start') }}
        </button>
      </div>
    </div>

    <!-- Game in progress -->
    <div v-else-if="!gameEnded">
      <!-- Stats bar -->
      <div class="flex items-center justify-between mb-4">
        <div class="flex items-center gap-2">
          <span class="text-lg">🐛</span>
          <span class="font-bold text-text-primary">{{ bugsEliminated }} / {{ BUGS_TO_WIN }}</span>
        </div>
        <div class="flex items-center gap-2">
          <span class="text-lg">⏱️</span>
          <span class="font-bold" :class="timeRemaining < 5000 ? 'text-red-500' : 'text-text-primary'">
            {{ (timeRemaining / 1000).toFixed(1) }}s
          </span>
        </div>
      </div>

      <!-- Progress bars -->
      <div class="space-y-2 mb-4">
        <!-- Bugs progress -->
        <div class="h-2 bg-bg-tertiary rounded-full overflow-hidden">
          <div
            class="h-full bg-gradient-to-r from-green-500 to-emerald-400 transition-all duration-200"
            :style="{ width: `${progress}%` }"
          ></div>
        </div>
        <!-- Time progress -->
        <div class="h-1.5 bg-bg-tertiary rounded-full overflow-hidden">
          <div
            class="h-full transition-all duration-100"
            :class="timeRemaining < 5000 ? 'bg-red-500' : 'bg-blue-500'"
            :style="{ width: `${timeProgress}%` }"
          ></div>
        </div>
      </div>

      <!-- Game grid -->
      <div class="grid grid-cols-4 gap-2 mb-4">
        <div
          v-for="cellIndex in GRID_SIZE"
          :key="cellIndex - 1"
          class="aspect-square bg-bg-tertiary rounded-lg flex items-center justify-center cursor-pointer hover:bg-bg-secondary transition-colors relative overflow-hidden"
          @click="() => {
            const bugId = cellHasBug(cellIndex - 1);
            if (bugId !== null) squashBug(bugId);
          }"
        >
          <!-- Bug -->
          <Transition name="bug">
            <div
              v-if="cellHasBug(cellIndex - 1) !== null"
              class="text-3xl animate-bounce"
            >
              🐛
            </div>
          </Transition>
        </div>
      </div>

      <!-- Cancel button -->
      <div class="text-center">
        <button @click="cancelGame" class="text-sm text-text-muted hover:text-text-secondary">
          {{ t('common.cancel') }}
        </button>
      </div>
    </div>

    <!-- Game ended -->
    <div v-else class="text-center">
      <div class="text-6xl mb-4">{{ isWinning ? '🎉' : '😵' }}</div>
      <h3 class="text-xl font-bold mb-2" :class="isWinning ? 'text-green-500' : 'text-red-500'">
        {{ isWinning ? t('minigame.bugs.win') : t('minigame.bugs.lose') }}
      </h3>
      <p class="text-text-secondary">
        {{ t('minigame.bugs.result', { count: bugsEliminated }) }}
      </p>
      <div v-if="isWinning" class="mt-4 text-sm text-text-muted">
        {{ t('minigame.bugs.repairing') }}
      </div>
    </div>
  </div>
</template>

<style scoped>
.repair-minigame {
  min-width: 320px;
  max-width: 400px;
  margin: 0 auto;
}

/* Bug animation */
.bug-enter-active {
  animation: bug-appear 0.2s ease-out;
}

.bug-leave-active {
  animation: bug-squash 0.15s ease-in;
}

@keyframes bug-appear {
  from {
    transform: scale(0) rotate(-180deg);
    opacity: 0;
  }
  to {
    transform: scale(1) rotate(0deg);
    opacity: 1;
  }
}

@keyframes bug-squash {
  to {
    transform: scale(0);
    opacity: 0;
  }
}
</style>
