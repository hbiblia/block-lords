import { ref, computed } from 'vue';
import { useAuthStore } from '@/stores/auth';
import { useScavengerStore } from '@/stores/scavenger';
import { playSound } from '@/utils/sounds';

// ─── Types ───

export type TileType =
  | 'empty'
  | 'wall'
  | 'exit'
  | 'loot_gc'
  | 'loot_material'
  | 'loot_data'
  | 'keycard'
  | 'locked_door'
  | 'terminal';

export type Difficulty = 'easy' | 'medium' | 'hard';
export type GameResult = 'success' | 'caught' | 'no_moves' | 'abandoned';

export interface Position {
  x: number;
  y: number;
}

export interface Tile {
  type: TileType;
  revealed: boolean;
  visible: boolean;
  collected: boolean;
  locked: boolean;
  lootValue?: number;
  lootRarity?: string;
}

export interface Enemy {
  id: number;
  pos: Position;
}

export interface LootItem {
  type: 'gc' | 'material' | 'data_fragment' | 'terminal_bonus';
  name: string;
  value: number;
  rarity?: string;
}

export interface ServerConfig {
  difficulty: Difficulty;
  name: string;
  energyCost: number;
  movePool: number;
  enemyCount: number;
  lootCount: number;
  wallPercent: number;
  gcRange: [number, number];
  materialRarities: string[];
}

// ─── Constants ───

const GRID_SIZE = 8;
const VISION_RANGE = 2;

export const SERVER_CONFIGS: Record<Difficulty, ServerConfig> = {
  easy: {
    difficulty: 'easy',
    name: 'Decommissioned Server',
    energyCost: 20,
    movePool: 35,
    enemyCount: 2,
    lootCount: 5,
    wallPercent: 0.15,
    gcRange: [10, 200],
    materialRarities: ['common', 'uncommon'],
  },
  medium: {
    difficulty: 'medium',
    name: 'Corrupted Datacenter',
    energyCost: 25,
    movePool: 30,
    enemyCount: 3,
    lootCount: 6,
    wallPercent: 0.20,
    gcRange: [50, 350],
    materialRarities: ['common', 'uncommon', 'rare'],
  },
  hard: {
    difficulty: 'hard',
    name: 'Quarantined Mainframe',
    energyCost: 30,
    movePool: 25,
    enemyCount: 4,
    lootCount: 8,
    wallPercent: 0.25,
    gcRange: [100, 500],
    materialRarities: ['uncommon', 'rare', 'epic'],
  },
};

// ─── Helpers ───

function manhattan(a: Position, b: Position): number {
  return Math.abs(a.x - b.x) + Math.abs(a.y - b.y);
}

function chebyshev(a: Position, b: Position): number {
  return Math.max(Math.abs(a.x - b.x), Math.abs(a.y - b.y));
}

function posEqual(a: Position, b: Position): boolean {
  return a.x === b.x && a.y === b.y;
}

function randInt(min: number, max: number): number {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

function shuffle<T>(arr: T[]): T[] {
  const a = [...arr];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

// ─── Composable ───

export function useScavenger() {
  const authStore = useAuthStore();
  const scavengerStore = useScavengerStore();

  // State
  const grid = ref<Tile[][]>([]);
  const playerPos = ref<Position>({ x: 0, y: 0 });
  const exitPos = ref<Position>({ x: 7, y: 7 });
  const enemies = ref<Enemy[]>([]);
  const movesRemaining = ref(0);
  const movePool = ref(0);
  const turnCount = ref(0);
  const collectedLoot = ref<LootItem[]>([]);
  const hasKeycard = ref(false);
  const dataFragments = ref(0);
  const difficulty = ref<Difficulty>('easy');
  const result = ref<GameResult | null>(null);
  const serverName = ref('');
  const animatingMove = ref(false);
  const gameActive = ref(false);

  // Computed
  const canMove = computed(() =>
    gameActive.value && !animatingMove.value && movesRemaining.value > 0
  );

  const adjacentPositions = computed(() => getAdjacentTiles());

  const gcCollected = computed(() =>
    collectedLoot.value
      .filter(l => l.type === 'gc' || l.type === 'terminal_bonus')
      .reduce((sum, l) => sum + l.value, 0)
  );

  const materialsCollected = computed(() =>
    collectedLoot.value.filter(l => l.type === 'material')
  );

  // ─── BFS ───

  function bfs(start: Position, end: Position, g: Tile[][]): boolean {
    const visited = Array.from({ length: GRID_SIZE }, () =>
      new Array(GRID_SIZE).fill(false)
    );
    const queue: Position[] = [start];
    visited[start.y][start.x] = true;

    const dirs = [
      { x: 0, y: -1 },
      { x: 0, y: 1 },
      { x: -1, y: 0 },
      { x: 1, y: 0 },
    ];

    while (queue.length > 0) {
      const cur = queue.shift()!;
      if (posEqual(cur, end)) return true;

      for (const d of dirs) {
        const nx = cur.x + d.x;
        const ny = cur.y + d.y;
        if (
          nx >= 0 && nx < GRID_SIZE &&
          ny >= 0 && ny < GRID_SIZE &&
          !visited[ny][nx] &&
          g[ny][nx].type !== 'wall'
        ) {
          visited[ny][nx] = true;
          queue.push({ x: nx, y: ny });
        }
      }
    }
    return false;
  }

  // ─── Grid Generation ───

  function createEmptyGrid(): Tile[][] {
    return Array.from({ length: GRID_SIZE }, () =>
      Array.from({ length: GRID_SIZE }, () => ({
        type: 'empty' as TileType,
        revealed: false,
        visible: false,
        collected: false,
        locked: false,
      }))
    );
  }

  function getRandomEdgePosition(exclude?: Position): Position {
    const edges: Position[] = [];
    for (let i = 0; i < GRID_SIZE; i++) {
      edges.push({ x: i, y: 0 }); // top
      edges.push({ x: i, y: GRID_SIZE - 1 }); // bottom
      if (i > 0 && i < GRID_SIZE - 1) {
        edges.push({ x: 0, y: i }); // left
        edges.push({ x: GRID_SIZE - 1, y: i }); // right
      }
    }
    const filtered = exclude
      ? edges.filter(p => manhattan(p, exclude) >= 8)
      : edges;
    const candidates = filtered.length > 0 ? filtered : edges.filter(p => !exclude || !posEqual(p, exclude));
    return candidates[Math.floor(Math.random() * candidates.length)];
  }

  function getRandomEmpty(g: Tile[][], exclude: Position[], minDistFrom?: Position, minDist = 4): Position | null {
    const candidates: Position[] = [];
    for (let y = 0; y < GRID_SIZE; y++) {
      for (let x = 0; x < GRID_SIZE; x++) {
        if (g[y][x].type !== 'empty') continue;
        if (exclude.some(p => posEqual(p, { x, y }))) continue;
        if (minDistFrom && manhattan({ x, y }, minDistFrom) < minDist) continue;
        candidates.push({ x, y });
      }
    }
    if (candidates.length === 0) return null;
    return candidates[Math.floor(Math.random() * candidates.length)];
  }

  function generateGrid(diff: Difficulty): void {
    const config = SERVER_CONFIGS[diff];
    const g = createEmptyGrid();

    // Player and exit positions
    const pPos = getRandomEdgePosition();
    const ePos = getRandomEdgePosition(pPos);

    // Place walls
    const wallCount = Math.floor(GRID_SIZE * GRID_SIZE * config.wallPercent);
    let wallsPlaced = 0;
    let attempts = 0;
    while (wallsPlaced < wallCount && attempts < 200) {
      const x = randInt(0, GRID_SIZE - 1);
      const y = randInt(0, GRID_SIZE - 1);
      if (posEqual({ x, y }, pPos) || posEqual({ x, y }, ePos)) { attempts++; continue; }
      if (g[y][x].type !== 'empty') { attempts++; continue; }

      g[y][x].type = 'wall';
      // Validate path still exists
      if (!bfs(pPos, ePos, g)) {
        g[y][x].type = 'empty'; // revert
      } else {
        wallsPlaced++;
      }
      attempts++;
    }

    // Place exit
    g[ePos.y][ePos.x].type = 'exit';

    // Track occupied positions
    const occupied: Position[] = [pPos, ePos];

    // Place loot
    const lootTypes: TileType[] = [];
    // Half GC, some materials, 1-2 data fragments
    const gcCount = Math.ceil(config.lootCount * 0.5);
    const matCount = Math.floor(config.lootCount * 0.3);
    const dataCount = Math.min(3, config.lootCount - gcCount - matCount);

    for (let i = 0; i < gcCount; i++) lootTypes.push('loot_gc');
    for (let i = 0; i < matCount; i++) lootTypes.push('loot_material');
    for (let i = 0; i < dataCount; i++) lootTypes.push('loot_data');

    for (const lt of lootTypes) {
      const pos = getRandomEmpty(g, occupied);
      if (pos) {
        g[pos.y][pos.x].type = lt;
        if (lt === 'loot_gc') {
          g[pos.y][pos.x].lootValue = randInt(config.gcRange[0], config.gcRange[1]);
        } else if (lt === 'loot_material') {
          const rarities = config.materialRarities;
          g[pos.y][pos.x].lootRarity = rarities[Math.floor(Math.random() * rarities.length)];
        }
        occupied.push(pos);
      }
    }

    // Place terminal
    const termPos = getRandomEmpty(g, occupied);
    if (termPos) {
      g[termPos.y][termPos.x].type = 'terminal';
      occupied.push(termPos);
    }

    // Place keycard and locked door
    const kcPos = getRandomEmpty(g, occupied);
    if (kcPos) {
      g[kcPos.y][kcPos.x].type = 'keycard';
      occupied.push(kcPos);

      // Locked door with bonus loot behind it
      const ldPos = getRandomEmpty(g, occupied);
      if (ldPos) {
        g[ldPos.y][ldPos.x].type = 'locked_door';
        g[ldPos.y][ldPos.x].locked = true;
        g[ldPos.y][ldPos.x].lootValue = randInt(config.gcRange[0] * 2, config.gcRange[1] * 2);
        occupied.push(ldPos);
      }
    }

    // Place enemies
    for (let i = 0; i < config.enemyCount; i++) {
      const pos = getRandomEmpty(g, occupied, pPos, 4);
      if (pos) {
        enemies.value.push({ id: i, pos: { ...pos } });
        occupied.push(pos);
      }
    }

    // Set grid and player
    grid.value = g;
    playerPos.value = { ...pPos };
    exitPos.value = { ...ePos };

    // Reveal initial fog
    revealFog(pPos);
  }

  // ─── Fog of War ───

  function revealFog(center: Position): void {
    for (let y = 0; y < GRID_SIZE; y++) {
      for (let x = 0; x < GRID_SIZE; x++) {
        const dist = chebyshev(center, { x, y });
        if (dist <= VISION_RANGE) {
          grid.value[y][x].revealed = true;
          grid.value[y][x].visible = true;
        } else {
          grid.value[y][x].visible = false;
        }
      }
    }
  }

  // ─── Adjacent Tiles ───

  function getAdjacentTiles(): Position[] {
    if (!gameActive.value) return [];
    const { x, y } = playerPos.value;
    const dirs = [
      { x: x, y: y - 1 },
      { x: x, y: y + 1 },
      { x: x - 1, y: y },
      { x: x + 1, y: y },
    ];
    return dirs.filter(p => {
      if (p.x < 0 || p.x >= GRID_SIZE || p.y < 0 || p.y >= GRID_SIZE) return false;
      const tile = grid.value[p.y][p.x];
      if (tile.type === 'wall') return false;
      if (tile.type === 'locked_door' && tile.locked && !hasKeycard.value) return false;
      return true;
    });
  }

  // ─── Loot Collection ───

  function collectLoot(): void {
    const { x, y } = playerPos.value;
    const tile = grid.value[y][x];
    if (tile.collected) return;

    const config = SERVER_CONFIGS[difficulty.value];

    switch (tile.type) {
      case 'loot_gc': {
        const value = tile.lootValue || randInt(config.gcRange[0], config.gcRange[1]);
        collectedLoot.value.push({ type: 'gc', name: 'GameCoins', value });
        tile.collected = true;
        playSound('collect');
        break;
      }
      case 'loot_material': {
        const rarity = tile.lootRarity || 'common';
        collectedLoot.value.push({
          type: 'material',
          name: `${rarity} component`,
          value: 1,
          rarity,
        });
        tile.collected = true;
        playSound('collect');
        break;
      }
      case 'loot_data': {
        dataFragments.value++;
        collectedLoot.value.push({ type: 'data_fragment', name: 'Data Fragment', value: 1 });
        tile.collected = true;
        playSound('collect');
        // Bonus at 3 fragments
        if (dataFragments.value >= 3) {
          const bonus = randInt(config.gcRange[1], config.gcRange[1] * 2);
          collectedLoot.value.push({ type: 'gc', name: 'Fragment Bonus', value: bonus });
        }
        break;
      }
      case 'keycard': {
        hasKeycard.value = true;
        tile.collected = true;
        playSound('collect');
        break;
      }
      case 'locked_door': {
        if (hasKeycard.value && tile.locked) {
          tile.locked = false;
          hasKeycard.value = false;
          const value = tile.lootValue || randInt(config.gcRange[0] * 2, config.gcRange[1] * 2);
          collectedLoot.value.push({ type: 'gc', name: 'Vault Loot', value });
          tile.collected = true;
          playSound('reward');
        }
        break;
      }
      case 'terminal': {
        const bonus = randInt(config.gcRange[0], config.gcRange[1]);
        collectedLoot.value.push({ type: 'terminal_bonus', name: 'Terminal Data', value: bonus });
        tile.collected = true;
        playSound('collect');
        break;
      }
    }
  }

  // ─── Enemy Movement ───

  function moveEnemies(): void {
    const dirs = [
      { x: 0, y: -1 },
      { x: 0, y: 1 },
      { x: -1, y: 0 },
      { x: 1, y: 0 },
    ];

    for (const enemy of enemies.value) {
      const dx = playerPos.value.x - enemy.pos.x;
      const dy = playerPos.value.y - enemy.pos.y;

      // Try primary axis first (greatest distance), then secondary
      const moves: Position[] = [];
      if (Math.abs(dx) >= Math.abs(dy)) {
        if (dx !== 0) moves.push({ x: enemy.pos.x + Math.sign(dx), y: enemy.pos.y });
        if (dy !== 0) moves.push({ x: enemy.pos.x, y: enemy.pos.y + Math.sign(dy) });
      } else {
        if (dy !== 0) moves.push({ x: enemy.pos.x, y: enemy.pos.y + Math.sign(dy) });
        if (dx !== 0) moves.push({ x: enemy.pos.x + Math.sign(dx), y: enemy.pos.y });
      }

      // Also try all 4 dirs as fallback
      for (const d of shuffle(dirs)) {
        const np = { x: enemy.pos.x + d.x, y: enemy.pos.y + d.y };
        if (!moves.some(m => posEqual(m, np))) moves.push(np);
      }

      for (const np of moves) {
        if (
          np.x >= 0 && np.x < GRID_SIZE &&
          np.y >= 0 && np.y < GRID_SIZE &&
          grid.value[np.y][np.x].type !== 'wall' &&
          !(grid.value[np.y][np.x].type === 'locked_door' && grid.value[np.y][np.x].locked) &&
          !enemies.value.some(e => e.id !== enemy.id && posEqual(e.pos, np))
        ) {
          enemy.pos = { ...np };
          break;
        }
      }
    }
  }

  // ─── Check Game Over ───

  function checkGameOver(): void {
    // Check if player reached exit
    if (posEqual(playerPos.value, exitPos.value)) {
      result.value = 'success';
      gameActive.value = false;
      bankLoot();
      playSound('success');
      scavengerStore.setPhase('result');
      return;
    }

    // Check if enemy caught player
    for (const enemy of enemies.value) {
      if (posEqual(enemy.pos, playerPos.value)) {
        result.value = 'caught';
        gameActive.value = false;
        playSound('error');
        scavengerStore.setPhase('result');
        scavengerStore.recordRun(0, false);
        return;
      }
    }

    // Check if out of moves
    if (movesRemaining.value <= 0) {
      result.value = 'no_moves';
      gameActive.value = false;
      playSound('error');
      scavengerStore.setPhase('result');
      scavengerStore.recordRun(0, false);
      return;
    }
  }

  // ─── Bank Loot ───

  function bankLoot(): void {
    const totalGc = gcCollected.value;
    if (authStore.player && totalGc > 0) {
      authStore.player.gamecoin_balance += totalGc;
    }
    scavengerStore.recordRun(totalGc, true);
  }

  // ─── Move Player ───

  function movePlayer(target: Position): void {
    if (!canMove.value) return;
    if (manhattan(playerPos.value, target) !== 1) return;

    const tile = grid.value[target.y][target.x];
    if (tile.type === 'wall') return;
    if (tile.type === 'locked_door' && tile.locked && !hasKeycard.value) return;

    animatingMove.value = true;

    playerPos.value = { ...target };
    movesRemaining.value--;
    turnCount.value++;

    // Reveal fog
    revealFog(target);

    // Collect loot
    collectLoot();

    // Check exit before enemies move
    if (posEqual(playerPos.value, exitPos.value)) {
      checkGameOver();
      animatingMove.value = false;
      return;
    }

    // Move enemies
    moveEnemies();

    // Check game over
    checkGameOver();

    playSound('click');
    animatingMove.value = false;
  }

  // ─── Start Run ───

  function startRun(diff: Difficulty): boolean {
    const config = SERVER_CONFIGS[diff];
    const player = authStore.player;
    if (!player || player.energy < config.energyCost) return false;

    // Deduct energy
    player.energy -= config.energyCost;

    // Reset state
    grid.value = [];
    enemies.value = [];
    collectedLoot.value = [];
    hasKeycard.value = false;
    dataFragments.value = 0;
    turnCount.value = 0;
    result.value = null;
    difficulty.value = diff;
    serverName.value = config.name;
    movesRemaining.value = config.movePool;
    movePool.value = config.movePool;
    gameActive.value = true;

    // Generate map
    generateGrid(diff);

    scavengerStore.setPhase('playing');
    playSound('notification');
    return true;
  }

  // ─── Abandon Run ───

  function abandonRun(): void {
    result.value = 'abandoned';
    gameActive.value = false;
    scavengerStore.recordRun(0, false);
    scavengerStore.setPhase('result');
  }

  // ─── Cleanup ───

  function cleanup(): void {
    grid.value = [];
    enemies.value = [];
    collectedLoot.value = [];
    gameActive.value = false;
    animatingMove.value = false;
    result.value = null;
    scavengerStore.setPhase('select');
  }

  // ─── Tile info for rendering ───

  function getTileContent(x: number, y: number): {
    type: TileType;
    isPlayer: boolean;
    isEnemy: boolean;
    visible: boolean;
    revealed: boolean;
    collected: boolean;
    locked: boolean;
    isAdjacent: boolean;
    isExit: boolean;
  } {
    const tile = grid.value[y]?.[x];
    if (!tile) return {
      type: 'empty', isPlayer: false, isEnemy: false,
      visible: false, revealed: false, collected: false,
      locked: false, isAdjacent: false, isExit: false,
    };

    return {
      type: tile.type,
      isPlayer: posEqual(playerPos.value, { x, y }),
      isEnemy: enemies.value.some(e => posEqual(e.pos, { x, y })),
      visible: tile.visible,
      revealed: tile.revealed,
      collected: tile.collected,
      locked: tile.locked,
      isAdjacent: adjacentPositions.value.some(p => posEqual(p, { x, y })),
      isExit: posEqual(exitPos.value, { x, y }),
    };
  }

  return {
    // State
    grid,
    playerPos,
    exitPos,
    enemies,
    movesRemaining,
    movePool,
    turnCount,
    collectedLoot,
    hasKeycard,
    dataFragments,
    difficulty,
    result,
    serverName,
    animatingMove,
    gameActive,

    // Computed
    canMove,
    adjacentPositions,
    gcCollected,
    materialsCollected,

    // Methods
    movePlayer,
    startRun,
    abandonRun,
    cleanup,
    getTileContent,

    // Constants
    GRID_SIZE,
  };
}
