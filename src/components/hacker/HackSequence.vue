<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted } from 'vue';
import { useHackerStore, type HackMode, type HackTarget } from '@/stores/hacker';
import { playSound } from '@/utils/sounds';

const props = defineProps<{
  mode: HackMode;
  target: HackTarget;
}>();

const emit = defineEmits<{
  (e: 'complete', success: boolean, score: number, timeMs: number): void;
}>();

const hackerStore = useHackerStore();

// Hack stages config
interface StageOption {
  label: string;
  command: string;
  correct: boolean;
}

interface Stage {
  name: string;
  prompt: string;
  output: string[];
  options: StageOption[];
}

function getStages(mode: HackMode): Stage[] {
  if (mode === 'steal') {
    return [
      {
        name: 'SCAN',
        prompt: '> STAGE 1: PORT SCANNING',
        output: [
          'Initiating network reconnaissance...',
          'Probing target: ' + props.target.username,
          'Discovering open services...',
          '',
          'PORT     STATE   SERVICE',
          '22/tcp   open    ssh',
          '80/tcp   open    http',
          '443/tcp  open    https',
          '3306/tcp open    mysql',
          '',
          'SELECT SCAN METHOD:',
        ],
        options: shuffle([
          { label: 'nmap -sV --script=vuln', command: 'nmap -sV --script=vuln', correct: true },
          { label: 'ping -c 100 target', command: 'ping -c 100 target', correct: false },
          { label: 'traceroute --hops=64', command: 'traceroute --hops=64', correct: false },
        ]),
      },
      {
        name: 'EXPLOIT',
        prompt: '> STAGE 2: EXPLOIT VULNERABILITY',
        output: [
          'Vulnerability scan complete.',
          'Found 3 potential attack vectors:',
          '',
          '[CVE-2024-3891] MySQL buffer overflow - CRITICAL',
          '[CVE-2024-1205] SSH key exchange flaw - HIGH',
          '[CVE-2024-0044] HTTP header injection - MEDIUM',
          '',
          'SELECT EXPLOIT:',
        ],
        options: shuffle([
          { label: 'exploit CVE-2024-3891 --payload=reverse_shell', command: 'exploit CVE-2024-3891', correct: true },
          { label: 'bruteforce ssh --wordlist=rockyou.txt', command: 'bruteforce ssh', correct: false },
          { label: 'sqlmap -u target/login --dump', command: 'sqlmap -u target', correct: false },
        ]),
      },
      {
        name: 'ESCALATE',
        prompt: '> STAGE 3: PRIVILEGE ESCALATION',
        output: [
          'Shell obtained! User: www-data',
          'Current privileges: LIMITED',
          '',
          'uid=33(www-data) gid=33(www-data)',
          'Kernel: Linux 5.15.0-91-generic',
          '',
          'Checking for escalation vectors...',
          'SUID binary found: /usr/bin/pkexec',
          '',
          'SELECT ESCALATION METHOD:',
        ],
        options: shuffle([
          { label: 'pkexec --exploit CVE-2021-4034', command: 'pkexec exploit', correct: true },
          { label: 'sudo su (no password)', command: 'sudo su', correct: false },
          { label: 'chmod 777 /etc/shadow', command: 'chmod 777 /etc/shadow', correct: false },
        ]),
      },
      {
        name: 'EXTRACT',
        prompt: '> STAGE 4: EXTRACT FUNDS',
        output: [
          'ROOT ACCESS GRANTED!',
          '',
          'uid=0(root) gid=0(root)',
          'Accessing wallet daemon...',
          'Wallet balance detected: ████████ GC',
          '',
          'SELECT EXTRACTION METHOD:',
        ],
        options: shuffle([
          { label: 'siphon_wallet --stealth --route=tor', command: 'siphon_wallet --stealth', correct: true },
          { label: 'cat /wallet/keys > /tmp/dump', command: 'cat wallet keys', correct: false },
          { label: 'wget wallet://funds > local', command: 'wget wallet', correct: false },
        ]),
      },
    ];
  } else if (mode === 'spy') {
    return [
      {
        name: 'SCAN',
        prompt: '> STAGE 1: NETWORK MAPPING',
        output: [
          'Mapping target network topology...',
          'Target: ' + props.target.username,
          '',
          'Discovering network segments...',
          '10.0.1.0/24 - Mining Operations',
          '10.0.2.0/24 - Storage Cluster',
          '10.0.3.0/24 - Admin Panel',
          '',
          'SELECT SCAN APPROACH:',
        ],
        options: shuffle([
          { label: 'arp-scan --localnet --stealth', command: 'arp-scan --stealth', correct: true },
          { label: 'nslookup target.local', command: 'nslookup target', correct: false },
          { label: 'whois target.mining.net', command: 'whois target', correct: false },
        ]),
      },
      {
        name: 'INFILTRATE',
        prompt: '> STAGE 2: SYSTEM INFILTRATION',
        output: [
          'Network mapped successfully.',
          'Mining server located at 10.0.1.12',
          '',
          'Firewall detected: iptables v1.8.7',
          'IDS running: Snort 3.1.58',
          '',
          'SELECT INFILTRATION METHOD:',
        ],
        options: shuffle([
          { label: 'ssh -D 9050 -o ProxyCommand="ncat --proxy-type socks5"', command: 'ssh tunnel proxy', correct: true },
          { label: 'telnet 10.0.1.12 23', command: 'telnet target', correct: false },
          { label: 'ftp anonymous@10.0.1.12', command: 'ftp anonymous', correct: false },
        ]),
      },
      {
        name: 'EXTRACT',
        prompt: '> STAGE 3: DATA EXTRACTION',
        output: [
          'Tunnel established!',
          'Connected to mining server.',
          '',
          'Databases found:',
          '  - mining_stats (42MB)',
          '  - rig_config (8MB)',
          '  - wallet_data (encrypted)',
          '',
          'SELECT EXTRACTION METHOD:',
        ],
        options: shuffle([
          { label: 'mysqldump --single-transaction --hex-blob', command: 'mysqldump stealth', correct: true },
          { label: 'SELECT * FROM mining_stats', command: 'SELECT all', correct: false },
          { label: 'cp -r /var/lib/mysql /tmp/', command: 'cp database', correct: false },
        ]),
      },
    ];
  } else {
    // sabotage
    return [
      {
        name: 'SCAN',
        prompt: '> STAGE 1: RECONNAISSANCE',
        output: [
          'Scanning target infrastructure...',
          'Target: ' + props.target.username,
          '',
          'Services detected:',
          '  mining_daemon    PID:1337  RUNNING',
          '  rig_controller   PID:1338  RUNNING',
          '  cooling_monitor  PID:1339  RUNNING',
          '',
          'SELECT RECON METHOD:',
        ],
        options: shuffle([
          { label: 'enum4linux -a target && nikto -h target', command: 'enum4linux + nikto', correct: true },
          { label: 'curl http://target/robots.txt', command: 'curl robots', correct: false },
          { label: 'dig ANY target.mining.net', command: 'dig target', correct: false },
        ]),
      },
      {
        name: 'EXPLOIT',
        prompt: '> STAGE 2: GAIN ACCESS',
        output: [
          'Enumeration complete.',
          'Critical vuln found in rig_controller!',
          '',
          '[!] rig_controller v2.1 - RCE via deserialization',
          '[!] Exploit available: CVE-2025-0137',
          '',
          'SELECT EXPLOIT:',
        ],
        options: shuffle([
          { label: 'msfconsole -x "use exploit/multi/deserialize"', command: 'metasploit deserialize', correct: true },
          { label: 'hydra -l admin -P pass.txt target ssh', command: 'hydra bruteforce', correct: false },
          { label: 'nikto -h target -Tuning x', command: 'nikto scan', correct: false },
        ]),
      },
      {
        name: 'INJECT',
        prompt: '> STAGE 3: INJECT VIRUS',
        output: [
          'Access obtained to rig_controller!',
          'Preparing payload...',
          '',
          'Mining daemon: ACTIVE (hashrate: ████ TH/s)',
          'Cooling system: NOMINAL',
          '',
          'SELECT INJECTION METHOD:',
        ],
        options: shuffle([
          { label: 'inject --payload=mining_throttle --persist --stealth', command: 'inject mining_throttle', correct: true },
          { label: 'rm -rf /mining/*', command: 'rm -rf mining', correct: false },
          { label: 'echo "malware" > /tmp/virus.sh', command: 'echo malware', correct: false },
        ]),
      },
      {
        name: 'COVER',
        prompt: '> STAGE 4: COVER TRACKS',
        output: [
          'Payload injected successfully!',
          'Mining speed will degrade over time.',
          '',
          'WARNING: IDS activity detected!',
          'Log entries found in /var/log/auth.log',
          '',
          'SELECT CLEANUP METHOD:',
        ],
        options: shuffle([
          { label: 'shred -vfz /var/log/*.log && timestomp -m', command: 'shred logs + timestomp', correct: true },
          { label: 'echo "" > /var/log/auth.log', command: 'echo empty log', correct: false },
          { label: 'exit (leave without cleaning)', command: 'exit raw', correct: false },
        ]),
      },
    ];
  }
}

function shuffle<T>(arr: T[]): T[] {
  const shuffled = [...arr];
  for (let i = shuffled.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [shuffled[i], shuffled[j]] = [shuffled[j], shuffled[i]];
  }
  return shuffled;
}

// Game state
const stages = ref<Stage[]>([]);
const currentStage = ref(0);
const timer = ref(30);
const score = ref(0);
const startTime = ref(0);
const gameActive = ref(false);
const showingOutput = ref(false);
const outputIndex = ref(0);
const showOptions = ref(false);
const feedback = ref<'correct' | 'wrong' | null>(null);
const completed = ref(false);
const failed = ref(false);

let timerInterval: number | null = null;
let outputInterval: number | null = null;

const currentStageData = computed(() => stages.value[currentStage.value] || null);
const totalStages = computed(() => stages.value.length);
const displayedOutput = ref<string[]>([]);

function start() {
  stages.value = getStages(props.mode);
  currentStage.value = 0;
  timer.value = 30;
  score.value = 0;
  startTime.value = Date.now();
  gameActive.value = true;
  completed.value = false;
  failed.value = false;

  // Start timer
  timerInterval = window.setInterval(() => {
    timer.value--;
    if (timer.value <= 0) {
      endGame(false);
    }
  }, 1000);

  playSound('hack_start' as any);
  showStageOutput();
}

function showStageOutput() {
  const stage = currentStageData.value;
  if (!stage) return;

  showingOutput.value = true;
  showOptions.value = false;
  displayedOutput.value = [];
  outputIndex.value = 0;

  // Add stage header to terminal
  hackerStore.addLine('', 'output');
  hackerStore.addLine(stage.prompt, 'header');

  // Typewriter output
  outputInterval = window.setInterval(() => {
    if (outputIndex.value < stage.output.length) {
      const line = stage.output[outputIndex.value];
      displayedOutput.value.push(line);
      hackerStore.addLine(line, 'output');
      outputIndex.value++;
    } else {
      if (outputInterval) clearInterval(outputInterval);
      outputInterval = null;
      showingOutput.value = false;
      showOptions.value = true;
    }
  }, 80);
}

function selectOption(option: StageOption) {
  if (!gameActive.value || showingOutput.value || feedback.value) return;

  showOptions.value = false;
  hackerStore.addLine('> ' + option.command, 'input');

  if (option.correct) {
    feedback.value = 'correct';
    score.value++;
    hackerStore.addLine('[OK] ACCESS GRANTED - Stage cleared', 'success');
    playSound('hack_stage_clear' as any);

    setTimeout(() => {
      feedback.value = null;
      currentStage.value++;

      if (currentStage.value >= totalStages.value) {
        endGame(true);
      } else {
        showStageOutput();
      }
    }, 800);
  } else {
    feedback.value = 'wrong';
    timer.value = Math.max(0, timer.value - 5);
    hackerStore.addLine('[ALERT] INTRUSION DETECTED - Countermeasures active (-5s)', 'error');
    playSound('hack_detected' as any);

    setTimeout(() => {
      feedback.value = null;
      showOptions.value = true;
    }, 600);
  }
}

function endGame(success: boolean) {
  gameActive.value = false;

  if (timerInterval) {
    clearInterval(timerInterval);
    timerInterval = null;
  }
  if (outputInterval) {
    clearInterval(outputInterval);
    outputInterval = null;
  }

  if (success) {
    completed.value = true;
    hackerStore.addLine('', 'output');
    hackerStore.addLine('═══════════════════════════════════', 'success');
    hackerStore.addLine('  HACK SUCCESSFUL', 'success');
    hackerStore.addLine('═══════════════════════════════════', 'success');
    playSound('hack_success' as any);
  } else {
    failed.value = true;
    hackerStore.addLine('', 'output');
    hackerStore.addLine('═══════════════════════════════════', 'error');
    hackerStore.addLine('  CONNECTION TERMINATED - DETECTED', 'error');
    hackerStore.addLine('═══════════════════════════════════', 'error');
    playSound('hack_fail' as any);
  }

  const elapsed = Date.now() - startTime.value;

  setTimeout(() => {
    emit('complete', success, score.value, elapsed);
  }, 1500);
}

onMounted(() => {
  start();
});

onUnmounted(() => {
  if (timerInterval) clearInterval(timerInterval);
  if (outputInterval) clearInterval(outputInterval);
});
</script>

<template>
  <div class="hack-sequence">
    <!-- Status bar -->
    <div class="flex items-center justify-between px-3 py-2 border-b border-green-500/20 bg-black/50 text-xs font-mono">
      <div class="flex items-center gap-4">
        <span class="text-green-400">
          STAGE {{ currentStage + 1 }}/{{ totalStages }}
          <span v-if="currentStageData" class="text-green-300/60 ml-1">{{ currentStageData.name }}</span>
        </span>
        <span class="text-green-400/60">
          SCORE: {{ score }}/{{ totalStages }}
        </span>
      </div>
      <div
        class="font-bold tabular-nums"
        :class="timer <= 5 ? 'text-red-500 animate-pulse' : timer <= 10 ? 'text-yellow-400' : 'text-green-400'"
      >
        ⏱ {{ timer }}s
      </div>
    </div>

    <!-- Options overlay (positioned at bottom of terminal) -->
    <Transition name="options-fade">
      <div v-if="showOptions && currentStageData" class="px-3 py-2 space-y-1.5 border-t border-green-500/20 bg-black/80">
        <button
          v-for="(option, idx) in currentStageData.options"
          :key="idx"
          @click="selectOption(option)"
          class="terminal-option w-full text-left px-3 py-2 font-mono text-sm rounded border transition-all duration-150"
          :class="[
            feedback === 'correct' ? 'border-green-500/30 opacity-50 cursor-default' :
            feedback === 'wrong' ? 'border-red-500/30 opacity-50 cursor-default' :
            'border-green-500/30 hover:border-green-400 hover:bg-green-500/10 cursor-pointer text-green-400'
          ]"
        >
          <span class="text-green-300/50">[{{ idx + 1 }}]</span>
          <span class="ml-2">{{ option.label }}</span>
        </button>
      </div>
    </Transition>

    <!-- Feedback flash -->
    <Transition name="flash">
      <div
        v-if="feedback === 'correct'"
        class="absolute inset-0 bg-green-500/10 pointer-events-none z-10"
      />
    </Transition>
    <Transition name="flash">
      <div
        v-if="feedback === 'wrong'"
        class="absolute inset-0 bg-red-500/15 pointer-events-none z-10"
      />
    </Transition>
  </div>
</template>

<style scoped>
.terminal-option {
  background: rgba(0, 15, 0, 0.6);
}

.terminal-option:hover:not(:disabled) {
  text-shadow: 0 0 8px rgba(0, 255, 65, 0.4);
}

.options-fade-enter-active {
  transition: all 0.2s ease-out;
}
.options-fade-leave-active {
  transition: all 0.15s ease-in;
}
.options-fade-enter-from {
  opacity: 0;
  transform: translateY(8px);
}
.options-fade-leave-to {
  opacity: 0;
}

.flash-enter-active {
  transition: opacity 0.1s;
}
.flash-leave-active {
  transition: opacity 0.3s;
}
.flash-enter-from,
.flash-leave-to {
  opacity: 0;
}
</style>
