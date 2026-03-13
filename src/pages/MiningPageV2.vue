<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted } from 'vue';
import { Application, Graphics, Container, Text, Assets, Sprite } from 'pixi.js';
import { RouterLink } from 'vue-router';
import { useAuthStore } from '@/stores/auth';

// Sprite assets
import rigSprite0 from '@/assets/rigs/miner_6.png';
import rigSprite1 from '@/assets/rigs/miner_7.png';
import rigSprite2 from '@/assets/rigs/miner_19.png';
import rigSprite3 from '@/assets/rigs/miner_23.png';

const RIG_SPRITES = [rigSprite0, rigSprite1, rigSprite2, rigSprite3];

// ─── Tile Config (fixed, grid size is computed in initPixi) ────────────────
const TW = 96;   // tile face width
const TH = 48;   // tile face height
const TD = 14;   // tile side depth

// ─── Types ─────────────────────────────────────────────────────────────────
type CellState = 'empty' | 'rig' | 'cooling';

interface Cell {
  col: number;
  row: number;
  state: CellState;
  variant?: number; // sprite variant index for rigs
  boosts?: number;  // boost count installed on this rig
}

interface TileColors {
  top: number;
  sideL: number;
  sideR: number;
  edge: number;
}

interface Connection {
  coolingKey: string;
  rigKey: string;
}

// ─── Stores ────────────────────────────────────────────────────────────────
const authStore = useAuthStore();

const energy    = computed(() => authStore.player?.energy    ?? 0);
const internet  = computed(() => authStore.player?.internet  ?? 0);
const maxEnergy = computed(() => authStore.effectiveMaxEnergy);
const maxInternet = computed(() => authStore.effectiveMaxInternet);

const energyPct  = computed(() => Math.min(100, (energy.value  / maxEnergy.value)   * 100));
const internetPct = computed(() => Math.min(100, (internet.value / maxInternet.value) * 100));

// ─── Reactive State ────────────────────────────────────────────────────────
// ─── PixiJS Refs ───────────────────────────────────────────────────────────
const MIN_ZOOM = 0.7;
const MAX_ZOOM = 2.5;

const stageRef     = ref<HTMLDivElement | null>(null);
const selectedCell = ref<Cell | null>(null);
const selScreenPos = ref({ x: 0, y: 0 });
const zoom         = ref(MIN_ZOOM);
const linkingFrom  = ref<Cell | null>(null);
const connections  = ref<Connection[]>([]);

// ─── Grid Data (initialized in initPixi after COLS/ROWS are known) ─────────
let COLS = 0;
let ROWS = 0;
let cells: Cell[][] = [];

let app: Application;
let world: Container;
let connLayer: Container;
const tileMap = new Map<string, Container>();
let stageW = 0;
let stageH = 0;

// ─── Pan State ─────────────────────────────────────────────────────────────
let panning    = false;
let panFrom    = { x: 0, y: 0 };
let panBase    = { x: 0, y: 0 };
let wasDragged = false;

// ─── Helpers ───────────────────────────────────────────────────────────────
function key(c: number, r: number) { return `${c}:${r}`; }

function toScreen(c: number, r: number) {
  return {
    x: (c - r) * (TW / 2),
    y: (c + r) * (TH / 2),
  };
}

// ─── Palette ───────────────────────────────────────────────────────────────
const PAL: Record<string, TileColors> = {
  empty:   { top: 0x111927, sideL: 0x09101a, sideR: 0x0d1520, edge: 0x1c2c42 },
  rig:     { top: 0x0f2045, sideL: 0x09152e, sideR: 0x0c1a3a, edge: 0x2a5aaa },
  cooling: { top: 0x0b2230, sideL: 0x071520, sideR: 0x091c28, edge: 0x208890 },
  hover:   { top: 0x1a3058, sideL: 0x0f1e3c, sideR: 0x132650, edge: 0x3a70dd },
  select:  { top: 0x1e4490, sideL: 0x112c68, sideR: 0x153880, edge: 0x5a9aff },
};

function getColors(cell: Cell, hover: boolean, sel: boolean): TileColors {
  if (sel)   return PAL.select;
  if (hover) return PAL.hover;
  return PAL[cell.state] ?? PAL.empty;
}

// ─── Draw Tile ─────────────────────────────────────────────────────────────
function drawTile(tc: Container, cell: Cell, hover = false, sel = false) {
  tc.removeChildren();
  const hw = TW / 2;
  const hh = TH / 2;
  const p  = getColors(cell, hover, sel);
  const g  = new Graphics();

  g.poly([-hw, 0, -hw, TD, 0, hh + TD, 0, hh]).fill(p.sideL);
  g.poly([hw,  0, hw,  TD, 0, hh + TD, 0, hh]).fill(p.sideR);
  g.poly([0, -hh, hw, 0, 0, hh, -hw, 0]).fill(p.top);
  g.stroke({ color: p.edge, width: 1 });

  if (!hover && !sel && cell.state === 'empty') {
    g.moveTo(-hw * 0.5, -hh * 0.5).lineTo(hw * 0.5, hh * 0.5);
    g.moveTo( hw * 0.5, -hh * 0.5).lineTo(-hw * 0.5, hh * 0.5);
    g.stroke({ color: p.edge, width: 0.5, alpha: 0.18 });
  }

  tc.addChild(g);
  if (cell.state !== 'empty') drawItem(tc, cell);
}

// ─── Draw Item ─────────────────────────────────────────────────────────────
function drawItem(tc: Container, cell: Cell) {
  if (cell.state === 'rig') {
    const idx     = (cell.variant ?? 0) % RIG_SPRITES.length;
    const texture = Assets.get(RIG_SPRITES[idx]);
    if (texture) {
      texture.source.scaleMode = 'nearest';
      const sprite = new Sprite(texture);
      const maxW   = TW - 8;
      const maxH   = TH * 2.2;
      const scale  = Math.min(maxW / sprite.width, maxH / sprite.height);
      sprite.scale.set(scale);
      sprite.anchor.set(0.5, 1);
      sprite.x = 0;
      sprite.y = TH / 2;
      tc.addChild(sprite);
    }
    // Boost orbs installed on this rig
    const boostCount = Math.min(cell.boosts ?? 0, 5);
    if (boostCount > 0) {
      const bg      = new Graphics();
      const spacing = 11;
      const startX  = -(boostCount - 1) * spacing / 2;
      for (let i = 0; i < boostCount; i++) {
        const ox = startX + i * spacing;
        const oy = -TH * 1.85;
        bg.circle(ox, oy, 4.5).fill(0x8822cc);
        bg.circle(ox - 1.2, oy - 1.5, 1.5).fill(0xcc88ff);
      }
      bg.stroke({ color: 0xaa55ee, width: 0.8 });
      tc.addChild(bg);
    }
    return;

  } else if (cell.state === 'cooling') {
    const g = new Graphics();
    g.circle(0, -28, 20).fill(0x0a2e3a);
    g.stroke({ color: 0x2ad0a0, width: 1.5 });
    g.circle(0, -28, 7).fill(0x061e26);
    for (let i = 0; i < 4; i++) {
      const a  = (i / 4) * Math.PI * 2 - 0.3;
      const a2 = a + 0.9;
      const R  = 14;
      g.poly([0, -28, Math.cos(a) * R, -28 + Math.sin(a) * R,
              Math.cos(a2) * R * 0.65, -28 + Math.sin(a2) * R * 0.65]).fill(0x20c0a0);
    }
    tc.addChild(g);
  }
}

// ─── Tile Selection ────────────────────────────────────────────────────────
function selectCell(cell: Cell) {
  if (selectedCell.value) {
    const prev = selectedCell.value;
    const tc   = tileMap.get(key(prev.col, prev.row));
    if (tc) drawTile(tc, cells[prev.row][prev.col], false, false);
  }
  const same = selectedCell.value?.col === cell.col && selectedCell.value?.row === cell.row;
  if (same) { selectedCell.value = null; return; }
  selectedCell.value = cell;
  const tc = tileMap.get(key(cell.col, cell.row));
  if (tc) drawTile(tc, cell, false, true);
  refreshSelPos();
}

// ─── Clamp world position to grid bounds ───────────────────────────────────
function clampWorld() {
  if (!world) return;
  const Z = zoom.value;
  // Horizontal: left edge of grid <= left of screen, right edge >= right of screen
  const halfGridW = COLS * TW / 2 * Z;
  world.x = Math.min(halfGridW, Math.max(stageW - halfGridW, world.x));
  // Vertical: top of grid <= top of screen, bottom of grid >= bottom of screen
  const gridTop    = (TH / 2) * Z;
  const gridBottom = ((2 * COLS - 1) * TH / 2 + TD) * Z;
  world.y = Math.min(gridTop, Math.max(stageH - gridBottom, world.y));
}

function refreshSelPos() {
  if (!selectedCell.value || !world) return;
  const s = toScreen(selectedCell.value.col, selectedCell.value.row);
  selScreenPos.value = {
    x: s.x * zoom.value + world.x,
    y: (s.y - TH / 2) * zoom.value + world.y,
  };
}

// ─── Place / Remove ────────────────────────────────────────────────────────
function placeItem(type: CellState) {
  if (!selectedCell.value) return;
  const { col, row } = selectedCell.value;
  cells[row][col].state  = type;
  cells[row][col].boosts = 0;
  if (type === 'rig') cells[row][col].variant = Math.floor(Math.random() * RIG_SPRITES.length);
  selectedCell.value = cells[row][col];
  const tc = tileMap.get(key(col, row));
  if (tc) drawTile(tc, cells[row][col], false, true);
}

function removeItem() {
  if (!selectedCell.value) return;
  const { col, row } = selectedCell.value;
  const k = key(col, row);
  connections.value      = connections.value.filter(c => c.coolingKey !== k && c.rigKey !== k);
  cells[row][col].state  = 'empty';
  cells[row][col].boosts = 0;
  selectedCell.value     = cells[row][col];
  const tc = tileMap.get(k);
  if (tc) drawTile(tc, cells[row][col], false, true);
  drawConnections();
}

function addBoost() {
  if (!selectedCell.value || selectedCell.value.state !== 'rig') return;
  const { col, row } = selectedCell.value;
  cells[row][col].boosts = (cells[row][col].boosts ?? 0) + 1;
  selectedCell.value     = cells[row][col];
  const tc = tileMap.get(key(col, row));
  if (tc) drawTile(tc, cells[row][col], false, true);
}

function removeBoost() {
  if (!selectedCell.value || selectedCell.value.state !== 'rig') return;
  const { col, row } = selectedCell.value;
  if ((cells[row][col].boosts ?? 0) <= 0) return;
  cells[row][col].boosts = (cells[row][col].boosts ?? 0) - 1;
  selectedCell.value     = cells[row][col];
  const tc = tileMap.get(key(col, row));
  if (tc) drawTile(tc, cells[row][col], false, true);
}

// ─── Connection Computeds ──────────────────────────────────────────────────
const coolingConnections = computed(() => {
  if (!selectedCell.value || selectedCell.value.state !== 'cooling') return [];
  const ck = key(selectedCell.value.col, selectedCell.value.row);
  return connections.value.filter(c => c.coolingKey === ck);
});

const rigConnections = computed(() => {
  if (!selectedCell.value || selectedCell.value.state !== 'rig') return [];
  const rk = key(selectedCell.value.col, selectedCell.value.row);
  return connections.value.filter(c => c.rigKey === rk);
});

function cellCoords(k: string) {
  const [c, r] = k.split(':');
  return `${c}, ${r}`;
}

// ─── Cable Drawing ─────────────────────────────────────────────────────────
// Returns L-path waypoints following grid axes (cols first, then rows)
function gridPath(c1: number, r1: number, c2: number, r2: number): {x:number,y:number}[] {
  const pts: {x:number,y:number}[] = [toScreen(c1, r1)];
  // Corner: align col first → corner at (c2, r1)
  if (c1 !== c2 && r1 !== r2) pts.push(toScreen(c2, r1));
  pts.push(toScreen(c2, r2));
  return pts;
}

function drawCablePath(g: Graphics, pts: {x:number,y:number}[], preview: boolean) {
  if (pts.length < 2) return;
  const color = preview ? 0x44bbff : 0x22ddff;
  const a     = preview ? 0.45 : 0.9;

  // Glow pass
  for (let i = 0; i < pts.length - 1; i++) {
    g.moveTo(pts[i].x, pts[i].y);
    g.lineTo(pts[i + 1].x, pts[i + 1].y);
    g.stroke({ color, width: 9, alpha: a * 0.18 });
  }
  // Core cable pass
  for (let i = 0; i < pts.length - 1; i++) {
    g.moveTo(pts[i].x, pts[i].y);
    g.lineTo(pts[i + 1].x, pts[i + 1].y);
    g.stroke({ color, width: 2.5, alpha: a });
  }
  // Corner dot at bend
  if (pts.length === 3) {
    g.circle(pts[1].x, pts[1].y, 3);
    g.fill({ color, alpha: a * 0.7 });
  }
  // End anchors
  g.circle(pts[0].x, pts[0].y, 4); g.fill({ color, alpha: a });
  g.circle(pts[pts.length - 1].x, pts[pts.length - 1].y, 4); g.fill({ color, alpha: a });
}

function drawConnections(hoverRig?: Cell, freePoint?: {x:number,y:number}) {
  if (!connLayer) return;
  connLayer.removeChildren();
  if (connections.value.length === 0 && !linkingFrom.value) return;
  const g = new Graphics();
  for (const conn of connections.value) {
    const [cc, cr] = conn.coolingKey.split(':').map(Number);
    const [rc, rr] = conn.rigKey.split(':').map(Number);
    drawCablePath(g, gridPath(cc, cr, rc, rr), false);
  }
  if (linkingFrom.value) {
    const from = toScreen(linkingFrom.value.col, linkingFrom.value.row);
    if (hoverRig) {
      drawCablePath(g, gridPath(linkingFrom.value.col, linkingFrom.value.row, hoverRig.col, hoverRig.row), true);
    } else if (freePoint) {
      drawCablePath(g, [from, freePoint], true);
    }
  }
  connLayer.addChild(g);
}

// ─── Linking ───────────────────────────────────────────────────────────────
function startLinking() {
  if (!selectedCell.value || selectedCell.value.state !== 'cooling') return;
  linkingFrom.value  = { ...selectedCell.value };
  selectedCell.value = null;
}

function cancelLinking() {
  linkingFrom.value = null;
  drawConnections();
}

function finishLinking(rigCell: Cell) {
  if (!linkingFrom.value) return;
  const coolingKey = key(linkingFrom.value.col, linkingFrom.value.row);
  const rigKey     = key(rigCell.col, rigCell.row);
  const exists     = connections.value.some(c => c.coolingKey === coolingKey && c.rigKey === rigKey);
  if (!exists) connections.value.push({ coolingKey, rigKey });
  linkingFrom.value = null;
  drawConnections();
}

function removeConnection(coolingKey: string, rigKey: string) {
  connections.value = connections.value.filter(
    c => !(c.coolingKey === coolingKey && c.rigKey === rigKey)
  );
  drawConnections();
}

// ─── Canvas Hit-Testing (sin eventos PixiJS por tile) ──────────────────────
let hoveredKey: string | null = null;

function screenToTile(mx: number, my: number): { c: number; r: number } | null {
  if (!world) return null;
  const wx = (mx - world.x) / zoom.value;
  const wy = (my - world.y) / zoom.value;
  const c  = Math.round((wx / (TW / 2) + wy / (TH / 2)) / 2);
  const r  = Math.round((wy / (TH / 2) - wx / (TW / 2)) / 2);
  if (c < 0 || c >= COLS || r < 0 || r >= ROWS) return null;
  return { c, r };
}

function updateHover(mx: number, my: number, canvas: HTMLCanvasElement) {
  const tile   = screenToTile(mx, my);
  const newKey = tile ? key(tile.c, tile.r) : null;
  if (newKey === hoveredKey) return;

  if (hoveredKey) {
    const [pc, pr] = hoveredKey.split(':').map(Number);
    const ptc = tileMap.get(hoveredKey);
    const isSel = selectedCell.value?.col === pc && selectedCell.value?.row === pr;
    if (ptc) drawTile(ptc, cells[pr][pc], false, isSel);
  }
  hoveredKey = newKey;

  if (newKey && tile) {
    const isSel = selectedCell.value?.col === tile.c && selectedCell.value?.row === tile.r;
    if (!isSel) {
      const tc = tileMap.get(newKey);
      if (tc) drawTile(tc, cells[tile.r][tile.c], true, false);
    }
    canvas.style.cursor = linkingFrom.value
      ? (cells[tile.r][tile.c].state === 'rig' ? 'crosshair' : 'not-allowed')
      : 'pointer';
  } else {
    canvas.style.cursor = linkingFrom.value ? 'crosshair' : '';
  }
}

function handleTileClick(mx: number, my: number) {
  const tile = screenToTile(mx, my);
  if (linkingFrom.value) {
    if (tile && cells[tile.r][tile.c].state === 'rig') finishLinking(cells[tile.r][tile.c]);
    else cancelLinking();
    return;
  }
  if (tile) {
    selectCell(cells[tile.r][tile.c]);
  } else if (selectedCell.value) {
    const prev = selectedCell.value;
    const tc   = tileMap.get(key(prev.col, prev.row));
    if (tc) drawTile(tc, cells[prev.row][prev.col], false, false);
    selectedCell.value = null;
  }
}

// ─── Coord Labels ──────────────────────────────────────────────────────────
function addCoordLabels() {
  const layer = new Container();
  world.addChild(layer); // on top of tiles

  const baseStyle  = { fontFamily: 'monospace', fontSize: 10, fill: '#1e3550' } as const;
  const labelStyle = { fontFamily: 'monospace', fontSize: 10, fill: '#2a5070', fontWeight: 'bold' } as const;

  // Col numbers — above each tile in row 0, every 5
  for (let c = 0; c < COLS; c++) {
    const pos  = toScreen(c, 0);
    const t    = new Text({ text: `${c}`, style: c % 5 === 0 ? labelStyle : baseStyle });
    t.anchor.set(0.5, 1);
    t.x = pos.x;
    t.y = pos.y - TH / 2 - 5;
    layer.addChild(t);
  }

  // Row numbers — left of each tile in col 0, every 5
  for (let r = 0; r < ROWS; r++) {
    const pos  = toScreen(0, r);
    const t    = new Text({ text: `${r}`, style: r % 5 === 0 ? labelStyle : baseStyle });
    t.anchor.set(1, 0.5);
    t.x = pos.x - TW / 2 - 6;
    t.y = pos.y;
    layer.addChild(t);
  }

  // Origin marker
  const origin = new Text({ text: '0,0', style: { fontFamily: 'monospace', fontSize: 9, fill: '#3a7090' } });
  origin.anchor.set(0.5, 1);
  origin.x = 0;
  origin.y = -TH / 2 - 5;
  layer.addChild(origin);
}

// ─── PixiJS Init ───────────────────────────────────────────────────────────
async function initPixi() {
  if (!stageRef.value) return;
  const W = stageRef.value.clientWidth;
  const H = stageRef.value.clientHeight;

  // ── Compute grid size to fully cover viewport ──────────────────────────
  // Horizontal coverage: need (COLS+ROWS-2)*TW/2 >= W  → for square: (2N-2)*TW/2 >= W
  // Vertical coverage:   need (2N-1)*TH/2 >= H
  // Grid sized to cover viewport even at MIN_ZOOM:
  // horizontal: (N-1)*TW >= W/MIN_ZOOM  →  N >= W/(TW*MIN_ZOOM)+1
  // vertical:   (2N-1)*TH/2 >= H/MIN_ZOOM  →  N >= H/(TH*MIN_ZOOM)+1
  const nW = Math.ceil(W / (TW  * MIN_ZOOM)) + 2;
  const nH = Math.ceil(H / (TH  * MIN_ZOOM)) + 2;
  COLS = Math.max(nW, nH) * 2;
  ROWS = COLS;
  stageW = W;
  stageH = H;

  // ── Init grid data ─────────────────────────────────────────────────────
  cells = Array.from({ length: ROWS }, (_, r) =>
    Array.from({ length: COLS }, (_, c) => ({ col: c, row: r, state: 'empty' as CellState, boosts: 0 }))
  );
  // Demo placements
  const mid = Math.floor(COLS / 2);
  cells[mid - 2][mid].state     = 'rig';     cells[mid - 2][mid].variant     = 0; cells[mid - 2][mid].boosts     = 2;
  cells[mid - 2][mid + 1].state = 'rig';     cells[mid - 2][mid + 1].variant = 1;
  cells[mid - 1][mid + 2].state = 'rig';     cells[mid - 1][mid + 2].variant = 2; cells[mid - 1][mid + 2].boosts = 1;
  cells[mid][mid - 1].state     = 'cooling';
  cells[mid + 2][mid - 2].state = 'cooling';

  // ── Pre-load rig sprites ───────────────────────────────────────────────
  await Assets.load(RIG_SPRITES);

  // ── PixiJS App ─────────────────────────────────────────────────────────
  app = new Application();
  await app.init({
    width:       W,
    height:      H,
    background:  0x070c18,
    antialias:   true,
    resolution:  window.devicePixelRatio || 1,
    autoDensity: true,
  });
  stageRef.value.appendChild(app.canvas as HTMLCanvasElement);

  world = new Container();
  app.stage.addChild(world);

  // ── Initial zoom & position: center of grid at center of viewport ────
  world.scale.set(zoom.value);
  const centerRow = Math.floor(ROWS / 2);
  world.x = W / 2;
  world.y = H / 2 - centerRow * TH * zoom.value;
  clampWorld();

  // ── Draw tiles in back-to-front diagonal order (sin eventos PixiJS) ──
  for (let d = 0; d < COLS + ROWS - 1; d++) {
    const rMin = Math.max(0, d - COLS + 1);
    const rMax = Math.min(d, ROWS - 1);
    for (let r = rMin; r <= rMax; r++) {
      const c = d - r;
      if (c < 0 || c >= COLS) continue;
      const cell = cells[r][c];
      const pos  = toScreen(c, r);
      const tc   = new Container();
      tc.x = pos.x;
      tc.y = pos.y;
      drawTile(tc, cell);
      world.addChild(tc);
      tileMap.set(key(c, r), tc);
    }
  }

  // ── Connection layer encima de tiles, debajo de labels ───────────────
  connLayer = new Container();
  world.addChild(connLayer);

  // ── Coord labels on top ───────────────────────────────────────────────
  addCoordLabels();

  // ── Canvas events: hit-testing matemático (O(1), sin lag) ────────────
  const canvas = app.canvas as HTMLCanvasElement;

  canvas.addEventListener('pointerdown', (e) => {
    if (e.button !== 0) return;
    panning    = true;
    wasDragged = false;
    panFrom    = { x: e.clientX, y: e.clientY };
    panBase    = { x: world.x,   y: world.y   };
    canvas.setPointerCapture(e.pointerId);
    canvas.style.cursor = 'grabbing';
  });

  canvas.addEventListener('pointermove', (e) => {
    const rect = canvas.getBoundingClientRect();
    const mx   = e.clientX - rect.left;
    const my   = e.clientY - rect.top;

    if (panning) {
      const dx = e.clientX - panFrom.x;
      const dy = e.clientY - panFrom.y;
      if (Math.abs(dx) > 3 || Math.abs(dy) > 3) wasDragged = true;
      world.x = panBase.x + dx;
      world.y = panBase.y + dy;
      clampWorld();
      refreshSelPos();
      return;
    }

    updateHover(mx, my, canvas);

    if (linkingFrom.value) {
      const tile = screenToTile(mx, my);
      if (tile && cells[tile.r][tile.c].state === 'rig') {
        drawConnections(cells[tile.r][tile.c]);
      } else {
        // Preview de línea libre al cursor
        const wx = (mx - world.x) / zoom.value;
        const wy = (my - world.y) / zoom.value;
        drawConnections(undefined, { x: wx, y: wy });
      }
    }
  });

  canvas.addEventListener('pointerup', (e) => {
    if (e.button !== 0) return;
    const wasPan = panning;
    panning = false;
    canvas.releasePointerCapture(e.pointerId);
    if (!wasPan) return;
    if (!wasDragged) {
      const rect = canvas.getBoundingClientRect();
      handleTileClick(e.clientX - rect.left, e.clientY - rect.top);
    }
    if (!linkingFrom.value) {
      const rect = canvas.getBoundingClientRect();
      updateHover(e.clientX - rect.left, e.clientY - rect.top, canvas);
    }
  });

  canvas.addEventListener('pointercancel', () => { panning = false; canvas.style.cursor = ''; });

  canvas.addEventListener('pointerleave', () => {
    updateHover(-9999, -9999, canvas);
    if (linkingFrom.value) drawConnections();
  });

  // ── Wheel & resize ───────────────────────────────────────────────────
  stageRef.value.addEventListener('wheel',  onWheel,  { passive: false });
  window.addEventListener('resize',  onResize);
  window.addEventListener('keydown', onKeyDown);
}

// ─── Keys ──────────────────────────────────────────────────────────────────
function onKeyDown(e: KeyboardEvent) {
  if (e.key === 'Escape') {
    if (linkingFrom.value) { cancelLinking(); return; }
    if (selectedCell.value) { selectCell(selectedCell.value); } // deselect toggle
  }
}

// ─── Zoom ──────────────────────────────────────────────────────────────────
function onWheel(e: WheelEvent) {
  e.preventDefault();
  const factor = e.deltaY > 0 ? 0.9 : 1.1;
  const newZ   = Math.min(MAX_ZOOM, Math.max(MIN_ZOOM, zoom.value * factor));
  const rect   = stageRef.value!.getBoundingClientRect();
  const mx     = e.clientX - rect.left;
  const my     = e.clientY - rect.top;
  const wx     = (mx - world.x) / zoom.value;
  const wy     = (my - world.y) / zoom.value;
  zoom.value = newZ;
  world.scale.set(newZ);
  world.x = mx - wx * newZ;
  world.y = my - wy * newZ;
  clampWorld();
  refreshSelPos();
}

// ─── Resize ────────────────────────────────────────────────────────────────
function onResize() {
  if (!app || !stageRef.value) return;
  stageW = stageRef.value.clientWidth;
  stageH = stageRef.value.clientHeight;
  app.renderer.resize(stageW, stageH);
  clampWorld();
}

// ─── Reset View ────────────────────────────────────────────────────────────
function resetView() {
  if (!app || !stageRef.value) return;
  zoom.value = MIN_ZOOM;
  world.scale.set(MIN_ZOOM);
  const W = stageRef.value.clientWidth;
  const H = stageRef.value.clientHeight;
  world.x = W / 2;
  world.y = H / 2 - Math.floor(ROWS / 2) * TH * MIN_ZOOM;
  clampWorld();
  refreshSelPos();
}

// ─── Lifecycle ─────────────────────────────────────────────────────────────
onMounted(async () => { await initPixi(); });

onUnmounted(() => {
  window.removeEventListener('resize',  onResize);
  window.removeEventListener('keydown', onKeyDown);
  stageRef.value?.removeEventListener('wheel', onWheel);
  app?.destroy(true);
});
</script>

<template>
  <div class="iso-page">

    <div ref="stageRef" class="iso-stage" />

    <!-- Link mode overlay -->
    <Transition name="panel">
      <div v-if="linkingFrom" class="link-overlay">
        <span class="link-msg">🔗 Click a Rig to connect — <kbd>ESC</kbd> to cancel</span>
        <button class="link-cancel" @click="cancelLinking()">✕</button>
      </div>
    </Transition>

    <!-- Floating tile panel -->
    <Transition name="panel">
      <div
        v-if="selectedCell && !linkingFrom"
        class="tile-panel"
        :style="{ left: `${selScreenPos.x}px`, top: `${selScreenPos.y}px` }"
      >
        <div class="panel-head">
          <span class="panel-coord">{{ selectedCell.col }}, {{ selectedCell.row }}</span>
          <span class="panel-badge" :class="`badge-${selectedCell.state}`">
            {{ selectedCell.state }}
          </span>
        </div>

        <div v-if="selectedCell.state === 'empty'" class="panel-actions">
          <button class="act-btn act-rig"     @click="placeItem('rig')">🖥️ Rig</button>
          <button class="act-btn act-cooling" @click="placeItem('cooling')">❄️ Cooling</button>
        </div>

        <div v-else class="panel-actions">
          <div class="item-name">
            <span v-if="selectedCell.state === 'rig'">🖥️ Mining Rig</span>
            <span v-else-if="selectedCell.state === 'cooling'">❄️ Cooling Unit</span>
          </div>

          <!-- Boost slots — solo en rigs -->
          <div v-if="selectedCell.state === 'rig'" class="boost-row">
            <span class="boost-label">⚡ Boosts</span>
            <div class="boost-orbs">
              <span v-for="i in Math.min(selectedCell.boosts ?? 0, 5)" :key="i" class="boost-orb" />
            </div>
            <span class="boost-count">{{ selectedCell.boosts ?? 0 }}</span>
            <div class="boost-btns">
              <button class="boost-btn" @click="removeBoost()" :disabled="(selectedCell.boosts ?? 0) === 0">−</button>
              <button class="boost-btn" @click="addBoost()">+</button>
            </div>
          </div>

          <!-- Connected coolings — en rigs -->
          <div v-if="selectedCell.state === 'rig' && rigConnections.length > 0" class="conn-list">
            <div v-for="conn in rigConnections" :key="conn.coolingKey" class="conn-item">
              <span class="conn-icon">❄️</span>
              <span class="conn-coord">{{ cellCoords(conn.coolingKey) }}</span>
              <button class="conn-remove" @click="removeConnection(conn.coolingKey, conn.rigKey)">✕</button>
            </div>
          </div>

          <!-- Cooling connections -->
          <div v-if="selectedCell.state === 'cooling'" class="conn-section">
            <div v-if="coolingConnections.length > 0" class="conn-list">
              <div v-for="conn in coolingConnections" :key="conn.rigKey" class="conn-item">
                <span class="conn-icon">🖥️</span>
                <span class="conn-coord">{{ cellCoords(conn.rigKey) }}</span>
                <button class="conn-remove" @click="removeConnection(conn.coolingKey, conn.rigKey)">✕</button>
              </div>
            </div>
            <div v-else class="conn-empty">Sin rigs conectados</div>
            <button class="act-btn act-cooling" @click="startLinking()">🔗 Connect Rig</button>
          </div>

          <button class="act-btn act-remove" @click="removeItem()">🗑️ Remove</button>
        </div>
      </div>
    </Transition>

    <!-- Resources HUD -->
    <div class="res-hud">
      <!-- Energy -->
      <div class="res-row">
        <span class="res-icon">⚡</span>
        <div class="res-bar-wrap">
          <div
            class="res-bar"
            :class="energyPct <= 10 ? 'bar-crit' : energyPct <= 25 ? 'bar-warn' : 'bar-ok'"
            :style="{ width: `${energyPct}%` }"
          />
        </div>
        <span class="res-val">{{ energy }}<span class="res-max">/{{ maxEnergy }}</span></span>
      </div>
      <!-- Internet -->
      <div class="res-row">
        <span class="res-icon">📡</span>
        <div class="res-bar-wrap">
          <div
            class="res-bar"
            :class="internetPct <= 10 ? 'bar-crit' : internetPct <= 25 ? 'bar-warn' : 'bar-ok-net'"
            :style="{ width: `${internetPct}%` }"
          />
        </div>
        <span class="res-val">{{ internet }}<span class="res-max">/{{ maxInternet }}</span></span>
      </div>
    </div>

    <!-- HUD -->
    <div class="hud">
      <button class="hud-btn" title="Reset view" @click="resetView">⌖</button>
      <span class="hud-zoom">{{ Math.round(zoom * 100) }}%</span>
    </div>

    <RouterLink to="/mining" class="btn-back">← v1</RouterLink>

  </div>
</template>

<style scoped>
.iso-page {
  position: fixed;
  inset: 0;
  z-index: 50;
  background: #070c18;
  overflow: hidden;
  user-select: none;
}
.iso-stage {
  width: 100%;
  height: 100%;
}
.iso-stage canvas {
  display: block;
  touch-action: none;
}

/* ── Floating panel ── */
.tile-panel {
  position: fixed;
  z-index: 200;
  transform: translate(-50%, calc(-100% - 18px));
  background: rgba(8, 14, 28, 0.95);
  border: 1px solid rgba(58, 112, 221, 0.45);
  border-radius: 10px;
  padding: 12px 14px;
  min-width: 174px;
  backdrop-filter: blur(10px);
  box-shadow: 0 0 28px rgba(58, 130, 246, 0.18), 0 6px 24px rgba(0, 0, 0, 0.65);
}
.panel-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 10px;
  gap: 6px;
}
.panel-coord { font-size: 11px; font-family: monospace; color: rgba(148, 163, 184, 0.6); }
.panel-badge {
  font-size: 9px;
  font-weight: 700;
  letter-spacing: 0.8px;
  text-transform: uppercase;
  padding: 2px 7px;
  border-radius: 4px;
}
.badge-empty   { background: rgba(71,85,105,.35);  color: #94a3b8; }
.badge-rig     { background: rgba(37,99,235,.3);   color: #60a5fa; }
.badge-cooling { background: rgba(6,182,212,.3);   color: #22d3ee; }
.panel-actions { display: flex; flex-direction: column; gap: 6px; }
.item-name { font-size: 13px; color: #e2e8f0; padding: 2px 0 4px; }
.act-btn {
  display: flex;
  align-items: center;
  gap: 7px;
  padding: 7px 11px;
  border-radius: 7px;
  font-size: 13px;
  font-weight: 500;
  border: 1px solid transparent;
  cursor: pointer;
  transition: background 0.12s;
  width: 100%;
}
.act-rig     { background: rgba(37,99,235,.18);  color: #93c5fd; border-color: rgba(37,99,235,.3);  }
.act-rig:hover     { background: rgba(37,99,235,.32);  }
.act-cooling { background: rgba(6,182,212,.18);  color: #67e8f9; border-color: rgba(6,182,212,.3);  }
.act-cooling:hover { background: rgba(6,182,212,.32);  }
.act-remove  { background: rgba(239,68,68,.18);  color: #fca5a5; border-color: rgba(239,68,68,.3);  }
.act-remove:hover  { background: rgba(239,68,68,.32);  }

/* ── Boost row inside rig panel ── */
.boost-row {
  display: flex;
  align-items: center;
  gap: 7px;
  padding: 6px 10px;
  background: rgba(139,92,246,.1);
  border: 1px solid rgba(139,92,246,.22);
  border-radius: 7px;
}
.boost-label { font-size: 11px; color: #a78bfa; flex-shrink: 0; }
.boost-orbs  { display: flex; gap: 3px; flex: 1; }
.boost-orb {
  width: 7px; height: 7px;
  border-radius: 50%;
  background: radial-gradient(circle at 30% 30%, #cc88ff, #7722cc);
  box-shadow: 0 0 4px #aa44ff88;
}
.boost-count { font-size: 11px; font-family: monospace; color: #c4b5fd; min-width: 12px; text-align: right; }
.boost-btns  { display: flex; gap: 4px; }
.boost-btn {
  width: 22px; height: 22px;
  border-radius: 5px;
  border: 1px solid rgba(139,92,246,.35);
  background: rgba(139,92,246,.15);
  color: #c4b5fd;
  font-size: 14px;
  line-height: 1;
  cursor: pointer;
  display: flex; align-items: center; justify-content: center;
  transition: background 0.1s;
}
.boost-btn:hover:not(:disabled) { background: rgba(139,92,246,.32); }
.boost-btn:disabled { opacity: 0.3; cursor: default; }

/* ── Connection list ── */
.conn-section { display: flex; flex-direction: column; gap: 5px; }
.conn-list { display: flex; flex-direction: column; gap: 4px; }
.conn-item {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 4px 8px;
  background: rgba(6,182,212,.08);
  border: 1px solid rgba(6,182,212,.18);
  border-radius: 5px;
  font-size: 11px;
}
.conn-icon  { font-size: 11px; }
.conn-coord { flex: 1; font-family: monospace; color: #67e8f9; }
.conn-remove {
  background: transparent;
  border: none;
  color: rgba(239,68,68,.6);
  font-size: 11px;
  cursor: pointer;
  padding: 1px 3px;
  border-radius: 3px;
  line-height: 1;
  transition: color 0.1s;
}
.conn-remove:hover { color: #f87171; }
.conn-empty { font-size: 11px; color: #475569; padding: 2px 2px 4px; }

/* ── Link mode overlay ── */
.link-overlay {
  position: fixed;
  top: 20px;
  left: 50%;
  transform: translateX(-50%);
  z-index: 300;
  display: flex;
  align-items: center;
  gap: 12px;
  background: rgba(6, 182, 212, 0.12);
  border: 1px solid rgba(6, 182, 212, 0.45);
  border-radius: 10px;
  padding: 10px 18px;
  backdrop-filter: blur(12px);
  box-shadow: 0 0 24px rgba(6,182,212,.2);
}
.link-msg { font-size: 13px; color: #22d3ee; }
.link-msg kbd {
  background: rgba(255,255,255,.08);
  border: 1px solid rgba(255,255,255,.15);
  border-radius: 4px;
  padding: 1px 5px;
  font-size: 11px;
  font-family: monospace;
}
.link-cancel {
  background: transparent;
  border: 1px solid rgba(239,68,68,.35);
  color: #f87171;
  border-radius: 5px;
  padding: 3px 9px;
  font-size: 12px;
  cursor: pointer;
  transition: background 0.1s;
}
.link-cancel:hover { background: rgba(239,68,68,.15); }

/* ── HUD ── */
.hud {
  position: fixed;
  bottom: 20px;
  right: 20px;
  display: flex;
  align-items: center;
  gap: 8px;
  background: rgba(8, 14, 28, 0.85);
  border: 1px solid rgba(58, 112, 221, 0.2);
  border-radius: 8px;
  padding: 5px 10px;
  backdrop-filter: blur(8px);
}
.hud-btn {
  background: transparent;
  border: none;
  color: #64748b;
  font-size: 18px;
  cursor: pointer;
  padding: 2px 4px;
  border-radius: 4px;
  transition: color 0.12s;
  line-height: 1;
}
.hud-btn:hover { color: #e2e8f0; }
.hud-zoom { font-size: 11px; font-family: monospace; color: #475569; min-width: 34px; }

/* ── Resources HUD ── */
.res-hud {
  position: fixed;
  bottom: 20px;
  left: 20px;
  display: flex;
  flex-direction: column;
  gap: 7px;
  background: rgba(8, 14, 28, 0.85);
  border: 1px solid rgba(58, 112, 221, 0.2);
  border-radius: 8px;
  padding: 9px 12px;
  backdrop-filter: blur(8px);
  min-width: 180px;
}
.res-row {
  display: flex;
  align-items: center;
  gap: 7px;
}
.res-icon {
  font-size: 12px;
  width: 14px;
  text-align: center;
  flex-shrink: 0;
}
.res-bar-wrap {
  flex: 1;
  height: 5px;
  background: rgba(255, 255, 255, 0.07);
  border-radius: 3px;
  overflow: hidden;
}
.res-bar {
  height: 100%;
  border-radius: 3px;
  transition: width 0.4s ease;
}
.bar-ok      { background: linear-gradient(90deg, #22c55e, #4ade80); }
.bar-ok-net  { background: linear-gradient(90deg, #06b6d4, #22d3ee); }
.bar-warn    { background: linear-gradient(90deg, #f59e0b, #fbbf24); }
.bar-crit    { background: linear-gradient(90deg, #ef4444, #f87171); }
.res-val {
  font-size: 10px;
  font-family: monospace;
  color: #64748b;
  white-space: nowrap;
  min-width: 44px;
  text-align: right;
}
.res-max { color: #334155; }

.btn-back {
  position: fixed;
  top: 16px;
  left: 16px;
  font-size: 12px;
  font-weight: 500;
  color: #64748b;
  text-decoration: none;
  background: rgba(8, 14, 28, 0.85);
  border: 1px solid rgba(58, 112, 221, 0.18);
  border-radius: 7px;
  padding: 6px 13px;
  backdrop-filter: blur(8px);
  transition: color 0.12s;
  z-index: 200;
}
.btn-back:hover { color: #e2e8f0; }

/* ── Transition ── */
.panel-enter-active, .panel-leave-active { transition: opacity 0.14s, transform 0.14s; }
.panel-enter-from { opacity: 0; transform: translate(-50%, calc(-100% - 26px)); }
.panel-leave-to   { opacity: 0; transform: translate(-50%, calc(-100% - 26px)); }
</style>
