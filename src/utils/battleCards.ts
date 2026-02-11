// === CARD BATTLE - Card Definitions & Deck Builder ===

export type CardType = 'attack' | 'defense' | 'special';

export interface CardDefinition {
  id: string;
  name: string;
  nameKey: string; // i18n key
  type: CardType;
  cost: number; // energy cost (1-2)
  value: number; // primary effect value
  description: string;
  descriptionKey: string; // i18n key
  effect: CardEffect;
}

export type CardEffect =
  | { kind: 'damage'; amount: number }
  | { kind: 'damage_ignore_shield'; amount: number; ignoreShield: number }
  | { kind: 'double_hit'; amount: number }
  | { kind: 'damage_self'; amount: number; selfDamage: number }
  | { kind: 'shield'; amount: number }
  | { kind: 'shield_counter'; shield: number; damage: number }
  | { kind: 'shield_draw'; shield: number; draw: number }
  | { kind: 'heal'; amount: number }
  | { kind: 'weaken'; reduction: number }
  | { kind: 'drain'; damage: number; heal: number };

export interface BattleCard {
  uid: string; // unique instance id (for hand tracking)
  definitionId: string;
}

export interface GameState {
  player1Hand: string[]; // card definition IDs
  player2Hand: string[];
  player1Deck: string[];
  player2Deck: string[];
  player1Discard: string[];
  player2Discard: string[];
  player1Energy: number;
  player2Energy: number;
  player1Weakened: boolean;
  player2Weakened: boolean;
  lastAction: string | null;
}

// === Card Definitions (12 cards total) ===

export const CARD_DEFINITIONS: CardDefinition[] = [
  // ATTACK CARDS (5) - Red
  {
    id: 'quick_strike',
    name: 'Quick Strike',
    nameKey: 'battle.cards.quickStrike',
    type: 'attack',
    cost: 1,
    value: 12,
    description: '12 damage',
    descriptionKey: 'battle.cards.quickStrikeDesc',
    effect: { kind: 'damage', amount: 12 },
  },
  {
    id: 'power_slash',
    name: 'Power Slash',
    nameKey: 'battle.cards.powerSlash',
    type: 'attack',
    cost: 2,
    value: 25,
    description: '25 damage',
    descriptionKey: 'battle.cards.powerSlashDesc',
    effect: { kind: 'damage', amount: 25 },
  },
  {
    id: 'fury_attack',
    name: 'Fury Attack',
    nameKey: 'battle.cards.furyAttack',
    type: 'attack',
    cost: 2,
    value: 18,
    description: '18 damage, ignores 8 shield',
    descriptionKey: 'battle.cards.furyAttackDesc',
    effect: { kind: 'damage_ignore_shield', amount: 18, ignoreShield: 8 },
  },
  {
    id: 'double_hit',
    name: 'Double Hit',
    nameKey: 'battle.cards.doubleHit',
    type: 'attack',
    cost: 1,
    value: 16,
    description: '8 damage x2',
    descriptionKey: 'battle.cards.doubleHitDesc',
    effect: { kind: 'double_hit', amount: 8 },
  },
  {
    id: 'critical_blow',
    name: 'Critical Blow',
    nameKey: 'battle.cards.criticalBlow',
    type: 'attack',
    cost: 2,
    value: 35,
    description: '35 damage, self-damage 5 HP',
    descriptionKey: 'battle.cards.criticalBlowDesc',
    effect: { kind: 'damage_self', amount: 35, selfDamage: 5 },
  },

  // DEFENSE CARDS (4) - Blue
  {
    id: 'guard',
    name: 'Guard',
    nameKey: 'battle.cards.guard',
    type: 'defense',
    cost: 1,
    value: 12,
    description: '+12 shield',
    descriptionKey: 'battle.cards.guardDesc',
    effect: { kind: 'shield', amount: 12 },
  },
  {
    id: 'fortify',
    name: 'Fortify',
    nameKey: 'battle.cards.fortify',
    type: 'defense',
    cost: 2,
    value: 25,
    description: '+25 shield',
    descriptionKey: 'battle.cards.fortifyDesc',
    effect: { kind: 'shield', amount: 25 },
  },
  {
    id: 'counter',
    name: 'Counter',
    nameKey: 'battle.cards.counter',
    type: 'defense',
    cost: 1,
    value: 8,
    description: '+8 shield, deal 5 damage',
    descriptionKey: 'battle.cards.counterDesc',
    effect: { kind: 'shield_counter', shield: 8, damage: 5 },
  },
  {
    id: 'deflect',
    name: 'Deflect',
    nameKey: 'battle.cards.deflect',
    type: 'defense',
    cost: 1,
    value: 10,
    description: '+10 shield, draw 1 card',
    descriptionKey: 'battle.cards.deflectDesc',
    effect: { kind: 'shield_draw', shield: 10, draw: 1 },
  },

  // SPECIAL CARDS (3) - Purple
  {
    id: 'heal',
    name: 'Heal',
    nameKey: 'battle.cards.heal',
    type: 'special',
    cost: 1,
    value: 15,
    description: 'Restore 15 HP',
    descriptionKey: 'battle.cards.healDesc',
    effect: { kind: 'heal', amount: 15 },
  },
  {
    id: 'weaken',
    name: 'Weaken',
    nameKey: 'battle.cards.weaken',
    type: 'special',
    cost: 1,
    value: 8,
    description: "Enemy's next attack -8 damage",
    descriptionKey: 'battle.cards.weakenDesc',
    effect: { kind: 'weaken', reduction: 8 },
  },
  {
    id: 'drain',
    name: 'Drain',
    nameKey: 'battle.cards.drain',
    type: 'special',
    cost: 2,
    value: 12,
    description: '12 damage + heal 6 HP',
    descriptionKey: 'battle.cards.drainDesc',
    effect: { kind: 'drain', damage: 12, heal: 6 },
  },
];

// Card lookup map
export const CARDS_BY_ID = new Map<string, CardDefinition>(
  CARD_DEFINITIONS.map((c) => [c.id, c])
);

export function getCard(id: string): CardDefinition {
  const card = CARDS_BY_ID.get(id);
  if (!card) throw new Error(`Unknown card: ${id}`);
  return card;
}

// Build a full deck (all 12 cards) and shuffle
export function buildShuffledDeck(): string[] {
  const deck = CARD_DEFINITIONS.map((c) => c.id);
  return shuffleArray(deck);
}

// Fisher-Yates shuffle
export function shuffleArray<T>(arr: T[]): T[] {
  const a = [...arr];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

// Card type color helpers
export function getCardColor(type: CardType): string {
  switch (type) {
    case 'attack': return 'red';
    case 'defense': return 'blue';
    case 'special': return 'purple';
  }
}

export function getCardBorderClass(type: CardType): string {
  switch (type) {
    case 'attack': return 'border-red-500/70';
    case 'defense': return 'border-blue-500/70';
    case 'special': return 'border-purple-500/70';
  }
}

export function getCardBgClass(type: CardType): string {
  switch (type) {
    case 'attack': return 'bg-red-500/10';
    case 'defense': return 'bg-blue-500/10';
    case 'special': return 'bg-purple-500/10';
  }
}

export function getCardTextClass(type: CardType): string {
  switch (type) {
    case 'attack': return 'text-red-400';
    case 'defense': return 'text-blue-400';
    case 'special': return 'text-purple-400';
  }
}

// Constants
export const MAX_HP = 100;
export const MAX_ENERGY = 3;
export const MAX_HAND_SIZE = 6;
export const CARDS_PER_DRAW = 3;
export const TURN_DURATION = 30;
export const BET_AMOUNT = 20;
