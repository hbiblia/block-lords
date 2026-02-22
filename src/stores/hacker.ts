import { defineStore } from 'pinia';
import { ref } from 'vue';

export type HackView = 'mode-select' | 'target-select' | 'briefing' | 'puzzle' | 'result';
export type HackMode = 'steal' | 'spy' | 'sabotage';

export interface HackTarget {
  id: string;
  username: string;
  reputation: number;
  defense_level: number;
}

export interface HackResult {
  success: boolean;
  hack_mode: HackMode;
  reward?: {
    gamecoin_stolen?: number;
    intel?: any;
    sabotage_duration_hours?: number;
    mining_penalty_percent?: number;
  };
  penalty?: {
    energy_lost?: number;
    speed_penalty_percent?: number;
    speed_penalty_duration_min?: number;
  };
}

export interface OutputLine {
  id: number;
  text: string;
  type: 'input' | 'output' | 'success' | 'error' | 'info' | 'warning' | 'header' | 'command';
  delay?: number;
}

export interface HackStage {
  name: string;
  description: string;
  options: { label: string; command: string; correct: boolean }[];
}

export const useHackerStore = defineStore('hacker', () => {
  const showModal = ref(false);
  const loading = ref(false);

  // Terminal state
  const outputLines = ref<OutputLine[]>([]);
  const commandHistory = ref<string[]>([]);
  const historyIndex = ref(-1);
  let lineIdCounter = 0;

  // Hack state
  const isHacking = ref(false);
  const hackView = ref<HackView>('mode-select');
  const selectedMode = ref<HackMode | null>(null);
  const selectedTarget = ref<HackTarget | null>(null);
  const hackResult = ref<HackResult | null>(null);
  const hackStage = ref(0);
  const hackTimer = ref(30);
  const hackScore = ref(0);

  function openModal() {
    showModal.value = true;
  }

  function closeModal() {
    showModal.value = false;
  }

  function addOutput(lines: OutputLine[]) {
    for (const line of lines) {
      line.id = ++lineIdCounter;
      outputLines.value.push(line);
    }
  }

  function addLine(text: string, type: OutputLine['type'] = 'output', delay?: number) {
    outputLines.value.push({
      id: ++lineIdCounter,
      text,
      type,
      delay,
    });
  }

  function clearOutput() {
    outputLines.value = [];
  }

  function pushHistory(cmd: string) {
    commandHistory.value.push(cmd);
    historyIndex.value = commandHistory.value.length;
  }

  function clear() {
    isHacking.value = false;
    hackView.value = 'mode-select';
    selectedMode.value = null;
    selectedTarget.value = null;
    hackResult.value = null;
    hackStage.value = 0;
    hackTimer.value = 30;
    hackScore.value = 0;
  }

  return {
    showModal,
    loading,
    outputLines,
    commandHistory,
    historyIndex,
    isHacking,
    hackView,
    selectedMode,
    selectedTarget,
    hackResult,
    hackStage,
    hackTimer,
    hackScore,
    openModal,
    closeModal,
    addOutput,
    addLine,
    clearOutput,
    pushHistory,
    clear,
  };
});
