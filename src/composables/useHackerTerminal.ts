import { ref, onUnmounted } from 'vue';
import { useHackerStore, type HackMode, type OutputLine } from '@/stores/hacker';
import { useAuthStore } from '@/stores/auth';
import { useMiningStore } from '@/stores/mining';
import { useInventoryStore } from '@/stores/inventory';
import { useMarketStore } from '@/stores/market';
import { useFriendsStore } from '@/stores/friends';
import { playSound } from '@/utils/sounds';
import { i18n } from '@/plugins/i18n';
import { getReputationLeaderboard, getMiningLeaderboard } from '@/utils/api';

interface MarketListing {
  id: string;
  name: string;
  price: number;
  currency: string;
  category: string;
}

interface StageOption {
  label: string;
  command: string;
  correct: boolean;
}

interface HackStage {
  name: string;
  prompt: string;
  output: string[];
  options: StageOption[];
}

function shuffle<T>(arr: T[]): T[] {
  const shuffled = [...arr];
  for (let i = shuffled.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [shuffled[i], shuffled[j]] = [shuffled[j], shuffled[i]];
  }
  return shuffled;
}

export function useHackerTerminal() {
  const hackerStore = useHackerStore();
  const authStore = useAuthStore();
  const miningStore = useMiningStore();
  const inventoryStore = useInventoryStore();
  const marketStore = useMarketStore();
  const friendsStore = useFriendsStore();

  const inputValue = ref('');
  const isProcessing = ref(false);
  const lastListing = ref<MarketListing[]>([]);

  // Network scan: IP → username mapping (persists during session)
  const ipToUsername = ref<Record<string, string>>({});

  // Terminal variables: name → value
  const terminalVars = ref<Record<string, string>>({});

  // Scripting state
  const terminalScripts = ref<Record<string, string[]>>({});
  const isRecording = ref(false);
  const recordingName = ref('');
  const recordingBuffer = ref<string[]>([]);
  const isRunningScript = ref(false);
  const scriptAborted = ref(false);

  // SSH session state
  const sshActive = ref(false);
  const sshTarget = ref('');
  const sshPrompt = ref('');
  const sshSiphoned = ref(false);

  // Hack game state
  const hackStages = ref<HackStage[]>([]);
  const hackCurrentStage = ref(0);
  const hackTimer = ref(30);
  const hackScore = ref(0);
  const hackStartTime = ref(0);
  const hackGameActive = ref(false);
  const hackShowingOutput = ref(false);
  const hackWaitingInput = ref(false);
  const hackCurrentOptions = ref<StageOption[]>([]);
  const hackPrompt = ref('');

  let hackTimerInterval: number | null = null;
  let hackOutputInterval: number | null = null;

  // ─── Welcome ───
  function showWelcome() {
    const t = i18n.global.t;
    hackerStore.clearOutput();
    hackerStore.addLine('╔══════════════════════════════════════╗', 'success');
    hackerStore.addLine('║     LOOTMINE TERMINAL v1.0           ║', 'success');
    hackerStore.addLine('║     Hack the planet.                 ║', 'success');
    hackerStore.addLine('╚══════════════════════════════════════╝', 'success');
    hackerStore.addLine('', 'output');
    hackerStore.addLine(t('hacker.welcome', 'Type "help" for available commands.'), 'info');
    hackerStore.addLine('', 'output');
  }

  // ─── Pipe processors ───
  const NON_PIPEABLE = new Set(['bruteforce', 'brute', 'hack', 'spy', 'sabotage', 'clear', 'cls', 'exit', 'quit']);

  function processPipe(lines: OutputLine[], pipeCmd: string, pipeArgs: string[]): OutputLine[] {
    switch (pipeCmd) {
      case 'grep': {
        const pattern = pipeArgs.join(' ');
        if (!pattern) return lines;
        const re = new RegExp(pattern.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i');
        return lines.filter(l => re.test(l.text));
      }
      case 'head': {
        const n = parseInt(pipeArgs[0]) || 10;
        return lines.slice(0, n);
      }
      case 'tail': {
        const n = parseInt(pipeArgs[0]) || 10;
        return lines.slice(-n);
      }
      case 'wc': {
        const nonEmpty = lines.filter(l => l.text.trim() !== '');
        return [{ id: 0, text: `${nonEmpty.length} lines`, type: 'info' as const }];
      }
      case 'sort':
        return [...lines].sort((a, b) => a.text.localeCompare(b.text));
      default:
        return [{ id: 0, text: `Unknown pipe command: ${pipeCmd}`, type: 'error' as const }];
    }
  }

  function applyPipes(lines: OutputLine[], pipeSegments: string[]): OutputLine[] {
    let result = lines;
    for (const segment of pipeSegments) {
      const parts = segment.trim().split(/\s+/);
      const cmd = parts[0];
      const args = parts.slice(1);
      result = processPipe(result, cmd, args);
    }
    return result;
  }

  // ─── Main command router ───
  // Substitute $variables in a string
  function substituteVars(text: string): string {
    return text.replace(/\$([a-zA-Z_]\w*)/g, (match, name) => {
      return terminalVars.value[name] ?? match;
    });
  }

  async function executeCommand(input: string) {
    const trimmed = input.trim();
    if (!trimmed) return;

    // Recording mode: capture lines instead of executing (except 'end')
    if (isRecording.value && trimmed.toLowerCase() !== 'end') {
      hackerStore.pushHistory(trimmed);
      hackerStore.addLine(trimmed, 'input');
      recordingBuffer.value.push(trimmed);
      hackerStore.addLine(`  [rec ${recordingBuffer.value.length}] ${trimmed}`, 'info');
      return;
    }

    // Semicolon multi-command: split and execute sequentially
    if (trimmed.includes(';') && !isRecording.value) {
      const commands = trimmed.split(';').map(s => s.trim()).filter(Boolean);
      if (commands.length > 1) {
        hackerStore.pushHistory(trimmed);
        hackerStore.addLine(trimmed, 'input');
        for (const subCmd of commands) {
          if (scriptAborted.value) break;
          await executeSingleCommand(subCmd);
          await new Promise(r => setTimeout(r, 200));
        }
        return;
      }
    }

    hackerStore.pushHistory(trimmed);
    await executeSingleCommand(trimmed, true);
  }

  // Core single-command executor
  // showInput: whether to display the command as an input line
  async function executeSingleCommand(input: string, showInput = false) {
    const trimmed = input.trim();
    if (!trimmed) return;

    // Substitute $variables
    const resolved = substituteVars(trimmed);

    // During hack: route to hack input handler
    if (hackerStore.isHacking && hackGameActive.value) {
      if (showInput) hackerStore.addLine(trimmed, 'input');
      handleHackInput(resolved);
      return;
    }

    // During SSH session: route to SSH handler
    if (sshActive.value) {
      if (showInput) hackerStore.addLine(trimmed, 'input');
      handleSshInput(resolved);
      return;
    }

    if (showInput) hackerStore.addLine(trimmed, 'input');
    isProcessing.value = true;

    // Detect pipes
    const pipeSegments = resolved.split('|').map(s => s.trim());
    const leftCmd = pipeSegments[0];
    const hasPipes = pipeSegments.length > 1;
    const pipes = hasPipes ? pipeSegments.slice(1) : [];

    const parts = leftCmd.toLowerCase().split(/\s+/);
    const cmd = parts[0];
    const args = parts.slice(1);
    // Raw args preserve original casing (for set, echo)
    const rawParts = leftCmd.split(/\s+/);
    const rawArgs = rawParts.slice(1);

    // Validate non-pipeable commands
    if (hasPipes && NON_PIPEABLE.has(cmd)) {
      hackerStore.addLine(`${cmd}: command not pipeable`, 'error');
      isProcessing.value = false;
      return;
    }

    // Capture mode: record start index for piping
    const startIdx = hasPipes ? hackerStore.outputLines.length : -1;

    try {
      switch (cmd) {
        case 'help':
          cmdHelp();
          break;
        case 'clear':
        case 'cls':
          hackerStore.clearOutput();
          break;
        case 'exit':
        case 'quit':
          cleanupHack();
          hackerStore.clear();
          hackerStore.clearOutput();
          inputValue.value = '';
          lastListing.value = [];
          ipToUsername.value = {};
          terminalVars.value = {};
          terminalScripts.value = {};
          isRecording.value = false;
          recordingBuffer.value = [];
          isRunningScript.value = false;
          scriptAborted.value = false;
          sshActive.value = false;
          sshTarget.value = '';
          sshPrompt.value = '';
          sshSiphoned.value = false;
          window.dispatchEvent(new Event('close-hacker'));
          break;
        case 'rigs':
          cmdRigs();
          break;
        case 'rig':
          await cmdRig(args);
          break;
        case 'inventory':
        case 'inv':
          await cmdInventory();
          break;
        case 'stats':
          cmdStats();
          break;
        case 'balance':
        case 'bal':
          cmdBalance();
          break;
        case 'hashrate':
        case 'hr':
          cmdHashrate();
          break;
        case 'hack':
          cmdHack(args);
          break;
        case 'spy':
          cmdHack(['spy', ...args]);
          break;
        case 'sabotage':
          cmdHack(['sabotage', ...args]);
          break;
        case 'ssh':
          cmdSsh(args);
          break;
        case 'scan':
          if (args.length > 0) {
            cmdNmap(args, hasPipes);
          } else {
            await cmdScanNetwork(hasPipes);
          }
          break;
        case 'nmap':
        case 'portscan':
          cmdNmap(args, hasPipes);
          break;
        case 'bruteforce':
        case 'brute':
          cmdBruteforce(args);
          break;
        case 'market':
        case 'shop':
          await cmdMarket(args);
          break;
        case 'buy':
          await cmdBuy(args);
          break;
        case 'man':
          cmdMan(args);
          break;
        case 'whoami':
          cmdWhoami();
          break;
        case 'neofetch':
          cmdNeofetch();
          break;
        case 'set':
          if (rawArgs.length < 2) {
            hackerStore.addLine('Usage: set <name> <value>', 'warning');
          } else {
            const varName = rawArgs[0];
            const varValue = rawArgs.slice(1).join(' ');
            terminalVars.value[varName] = varValue;
            hackerStore.addLine(`${varName}=${varValue}`, 'success');
          }
          break;
        case 'unset':
          if (args.length === 0) {
            hackerStore.addLine('Usage: unset <name>', 'warning');
          } else {
            const name = rawArgs[0];
            if (terminalVars.value[name] !== undefined) {
              delete terminalVars.value[name];
              hackerStore.addLine(`Unset ${name}`, 'info');
            } else {
              hackerStore.addLine(`Variable "${name}" not found.`, 'error');
            }
          }
          break;
        case 'env':
          {
            const keys = Object.keys(terminalVars.value);
            if (keys.length === 0) {
              hackerStore.addLine('No variables set.', 'info');
            } else {
              hackerStore.addLine('', 'output');
              hackerStore.addLine('═══ ENVIRONMENT ═══', 'header');
              hackerStore.addLine('', 'output');
              for (const k of keys) {
                hackerStore.addLine(`  ${k}=${terminalVars.value[k]}`, 'output');
              }
              hackerStore.addLine('', 'output');
            }
          }
          break;
        case 'echo':
          hackerStore.addLine(rawArgs.join(' '), 'output');
          break;
        case 'script':
          if (args.length === 0) {
            hackerStore.addLine('Usage: script <name>', 'warning');
          } else if (isRecording.value) {
            hackerStore.addLine('Already recording. Type "end" to finish.', 'error');
          } else {
            const sName = rawArgs[0];
            isRecording.value = true;
            recordingName.value = sName;
            recordingBuffer.value = [];
            hackerStore.addLine(`Recording script "${sName}". Type commands, then "end" to save.`, 'success');
          }
          break;
        case 'end':
          if (isRecording.value) {
            const sName = recordingName.value;
            terminalScripts.value[sName] = [...recordingBuffer.value];
            const count = recordingBuffer.value.length;
            isRecording.value = false;
            recordingName.value = '';
            recordingBuffer.value = [];
            hackerStore.addLine(`Script "${sName}" saved (${count} lines).`, 'success');
          } else {
            hackerStore.addLine('Not recording. Use "script <name>" to start.', 'error');
          }
          break;
        case 'run':
          if (args.length === 0) {
            hackerStore.addLine('Usage: run <script_name>', 'warning');
          } else {
            const sName = rawArgs[0];
            if (!terminalScripts.value[sName]) {
              hackerStore.addLine(`Script "${sName}" not found. Use "scripts" to list.`, 'error');
            } else if (isRunningScript.value) {
              hackerStore.addLine('A script is already running. Type "stop" to abort.', 'error');
            } else {
              await runScript(sName);
            }
          }
          break;
        case 'stop':
          if (isRunningScript.value) {
            scriptAborted.value = true;
            hackerStore.addLine('Script aborted.', 'warning');
          } else {
            hackerStore.addLine('No script running.', 'info');
          }
          break;
        case 'scripts':
          {
            const names = Object.keys(terminalScripts.value);
            if (names.length === 0) {
              hackerStore.addLine('No scripts saved.', 'info');
            } else {
              hackerStore.addLine('', 'output');
              hackerStore.addLine('═══ SAVED SCRIPTS ═══', 'header');
              hackerStore.addLine('', 'output');
              for (const n of names) {
                hackerStore.addLine(`  ${n}  (${terminalScripts.value[n].length} lines)`, 'output');
              }
              hackerStore.addLine('', 'output');
            }
          }
          break;
        case 'cat':
          if (args.length === 0) {
            hackerStore.addLine('Usage: cat <script_name>', 'warning');
          } else {
            const sName = rawArgs[0];
            if (!terminalScripts.value[sName]) {
              hackerStore.addLine(`Script "${sName}" not found.`, 'error');
            } else {
              hackerStore.addLine('', 'output');
              hackerStore.addLine(`═══ ${sName} ═══`, 'header');
              hackerStore.addLine('', 'output');
              terminalScripts.value[sName].forEach((line, i) => {
                hackerStore.addLine(`  ${String(i + 1).padStart(2)}  ${line}`, 'command');
              });
              hackerStore.addLine('', 'output');
            }
          }
          break;
        case 'delscript':
          if (args.length === 0) {
            hackerStore.addLine('Usage: delscript <name>', 'warning');
          } else {
            const sName = rawArgs[0];
            if (!terminalScripts.value[sName]) {
              hackerStore.addLine(`Script "${sName}" not found.`, 'error');
            } else {
              delete terminalScripts.value[sName];
              hackerStore.addLine(`Script "${sName}" deleted.`, 'info');
            }
          }
          break;
        case 'sleep':
          {
            const secs = parseFloat(args[0]) || 1;
            const ms = Math.min(secs * 1000, 10000);
            hackerStore.addLine(`Sleeping ${secs}s...`, 'info');
            await new Promise(r => setTimeout(r, ms));
          }
          break;
        case 'sudo':
          hackerStore.addLine('[sudo] permission denied. Nice try.', 'error');
          break;
        case 'rm':
          if (args.join(' ').includes('-rf')) {
            hackerStore.addLine('rm: cannot remove: Operation not permitted', 'error');
            hackerStore.addLine('(Did you really think that would work?)', 'warning');
          } else {
            cmdUnknown(cmd);
          }
          break;
        default:
          cmdUnknown(cmd);
      }

      // Apply pipes if present
      if (hasPipes && startIdx >= 0) {
        const captured = hackerStore.outputLines.splice(startIdx);
        const filtered = applyPipes(captured, pipes);
        for (const line of filtered) {
          hackerStore.addLine(line.text, line.type);
        }
      }
    } catch (e) {
      hackerStore.addLine(`Error: ${e}`, 'error');
    } finally {
      isProcessing.value = false;
    }
  }

  // ─── Script runner ───
  async function runScript(name: string) {
    const lines = terminalScripts.value[name];
    if (!lines) return;

    isRunningScript.value = true;
    scriptAborted.value = false;
    hackerStore.addLine(`Running script "${name}" (${lines.length} lines)...`, 'success');
    hackerStore.addLine('', 'output');

    for (const line of lines) {
      if (scriptAborted.value) {
        hackerStore.addLine('', 'output');
        hackerStore.addLine('Script execution aborted.', 'warning');
        break;
      }
      await executeSingleCommand(line, true);
      await new Promise(r => setTimeout(r, 300));
    }

    if (!scriptAborted.value) {
      hackerStore.addLine('', 'output');
      hackerStore.addLine(`Script "${name}" completed.`, 'success');
    }

    isRunningScript.value = false;
    scriptAborted.value = false;
  }

  // ─── Help ───
  function cmdHelp() {
    hackerStore.addLine('', 'output');
    hackerStore.addLine('═══ AVAILABLE COMMANDS ═══', 'header');
    hackerStore.addLine('', 'output');
    hackerStore.addLine('  help        clear       exit        man <cmd>', 'output');
    hackerStore.addLine('  whoami      neofetch    stats       balance', 'output');
    hackerStore.addLine('  hashrate    rigs        rig         inv', 'output');
    hackerStore.addLine('  market      buy         scan        nmap', 'output');
    hackerStore.addLine('  hack        spy         sabotage    bruteforce', 'output');
    hackerStore.addLine('  ssh', 'output');
    hackerStore.addLine('  set         unset       env         echo', 'output');
    hackerStore.addLine('  script      end         run         stop', 'output');
    hackerStore.addLine('  scripts     cat         delscript   sleep', 'output');
    hackerStore.addLine('', 'output');
    hackerStore.addLine('Type "man <command>" for detailed usage and examples.', 'info');
    hackerStore.addLine('', 'output');
  }

  // ─── Man Pages ───
  function cmdMan(args: string[]) {
    if (args.length === 0) {
      hackerStore.addLine('Usage: man <command>', 'warning');
      hackerStore.addLine('Type "help" to see all available commands.', 'info');
      return;
    }

    const cmd = args[0].toLowerCase();
    hackerStore.addLine('', 'output');

    switch (cmd) {
      case 'help':
        hackerStore.addLine('HELP(1)                   LootMine Manual', 'header');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('NAME', 'info');
        hackerStore.addLine('    help - display available commands', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('DESCRIPTION', 'info');
        hackerStore.addLine('    Shows a list of all available terminal commands.', 'output');
        hackerStore.addLine('    Use "man <command>" for detailed information.', 'output');
        break;

      case 'clear':
      case 'cls':
        hackerStore.addLine('CLEAR(1)                  LootMine Manual', 'header');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('NAME', 'info');
        hackerStore.addLine('    clear - clear the terminal screen', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('ALIASES', 'info');
        hackerStore.addLine('    cls', 'output');
        break;

      case 'exit':
      case 'quit':
        hackerStore.addLine('EXIT(1)                   LootMine Manual', 'header');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('NAME', 'info');
        hackerStore.addLine('    exit - close the terminal and reset session', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('ALIASES', 'info');
        hackerStore.addLine('    quit', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('DESCRIPTION', 'info');
        hackerStore.addLine('    Closes the terminal window and clears all session', 'output');
        hackerStore.addLine('    data including scan results and market listings.', 'output');
        break;

      case 'man':
        hackerStore.addLine('MAN(1)                    LootMine Manual', 'header');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('NAME', 'info');
        hackerStore.addLine('    man - display manual page for a command', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('SYNOPSIS', 'info');
        hackerStore.addLine('    man <command>', 'command');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('EXAMPLES', 'info');
        hackerStore.addLine('    man scan', 'command');
        hackerStore.addLine('    man hack', 'command');
        break;

      case 'whoami':
        hackerStore.addLine('WHOAMI(1)                 LootMine Manual', 'header');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('NAME', 'info');
        hackerStore.addLine('    whoami - display current user identity', 'output');
        break;

      case 'neofetch':
        hackerStore.addLine('NEOFETCH(1)               LootMine Manual', 'header');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('NAME', 'info');
        hackerStore.addLine('    neofetch - display system information banner', 'output');
        break;

      case 'stats':
        hackerStore.addLine('STATS(1)                  LootMine Manual', 'header');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('NAME', 'info');
        hackerStore.addLine('    stats - display player statistics', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('DESCRIPTION', 'info');
        hackerStore.addLine('    Shows username, reputation, region, rigs, hashrate,', 'output');
        hackerStore.addLine('    energy, internet, blocks mined and rig slots.', 'output');
        break;

      case 'balance':
      case 'bal':
        hackerStore.addLine('BALANCE(1)                LootMine Manual', 'header');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('NAME', 'info');
        hackerStore.addLine('    balance - display all currency balances', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('ALIASES', 'info');
        hackerStore.addLine('    bal', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('DESCRIPTION', 'info');
        hackerStore.addLine('    Shows GameCoin (GC), Crypto, and RON balances.', 'output');
        break;

      case 'hashrate':
      case 'hr':
        hackerStore.addLine('HASHRATE(1)               LootMine Manual', 'header');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('NAME', 'info');
        hackerStore.addLine('    hashrate - display mining hashrate overview', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('ALIASES', 'info');
        hackerStore.addLine('    hr', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('DESCRIPTION', 'info');
        hackerStore.addLine('    Shows total effective hashrate, network hashrate,', 'output');
        hackerStore.addLine('    active miners, and per-rig hashrate breakdown.', 'output');
        break;

      case 'rigs':
        hackerStore.addLine('RIGS(1)                   LootMine Manual', 'header');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('NAME', 'info');
        hackerStore.addLine('    rigs - list all mining rigs', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('DESCRIPTION', 'info');
        hackerStore.addLine('    Displays a table of all owned rigs with their', 'output');
        hackerStore.addLine('    ID, name, status, temperature, hashrate, and', 'output');
        hackerStore.addLine('    condition. Use rig IDs with the "rig" command.', 'output');
        break;

      case 'rig':
        hackerStore.addLine('RIG(1)                    LootMine Manual', 'header');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('NAME', 'info');
        hackerStore.addLine('    rig - control individual mining rigs', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('SYNOPSIS', 'info');
        hackerStore.addLine('    rig on <id|all>', 'command');
        hackerStore.addLine('    rig off <id|all>', 'command');
        hackerStore.addLine('    rig status <id>', 'command');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('DESCRIPTION', 'info');
        hackerStore.addLine('    Turn rigs on/off or view detailed status.', 'output');
        hackerStore.addLine('    Use "rigs" first to see rig IDs.', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('EXAMPLES', 'info');
        hackerStore.addLine('    rig on 1            Turn on rig #1', 'command');
        hackerStore.addLine('    rig off all          Turn off all rigs', 'command');
        hackerStore.addLine('    rig status 2         Show details of rig #2', 'command');
        break;

      case 'inv':
      case 'inventory':
        hackerStore.addLine('INV(1)                    LootMine Manual', 'header');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('NAME', 'info');
        hackerStore.addLine('    inv - display inventory contents', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('ALIASES', 'info');
        hackerStore.addLine('    inventory', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('DESCRIPTION', 'info');
        hackerStore.addLine('    Lists all items in your inventory grouped by', 'output');
        hackerStore.addLine('    category: rigs, cooling, boosts, materials.', 'output');
        break;

      case 'market':
      case 'shop':
        hackerStore.addLine('MARKET(1)                 LootMine Manual', 'header');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('NAME', 'info');
        hackerStore.addLine('    market - browse and purchase items', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('ALIASES', 'info');
        hackerStore.addLine('    shop', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('SYNOPSIS', 'info');
        hackerStore.addLine('    market', 'command');
        hackerStore.addLine('    market <category>', 'command');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('CATEGORIES', 'info');
        hackerStore.addLine('    rigs, cooling, energy, internet,', 'output');
        hackerStore.addLine('    boosts, components, exp', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('DESCRIPTION', 'info');
        hackerStore.addLine('    Without arguments, shows available categories.', 'output');
        hackerStore.addLine('    With a category, lists items with prices.', 'output');
        hackerStore.addLine('    Items are numbered for use with "buy".', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('EXAMPLES', 'info');
        hackerStore.addLine('    market rigs          List available rigs', 'command');
        hackerStore.addLine('    market cooling        List cooling systems', 'command');
        hackerStore.addLine('    buy 3                Buy item #3 from listing', 'command');
        break;

      case 'buy':
        hackerStore.addLine('BUY(1)                    LootMine Manual', 'header');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('NAME', 'info');
        hackerStore.addLine('    buy - purchase item from market listing', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('SYNOPSIS', 'info');
        hackerStore.addLine('    buy <#>', 'command');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('DESCRIPTION', 'info');
        hackerStore.addLine('    Purchases the item by number from the last', 'output');
        hackerStore.addLine('    market listing. Run "market <category>" first.', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('EXAMPLES', 'info');
        hackerStore.addLine('    market energy', 'command');
        hackerStore.addLine('    buy 1                Buy first energy card', 'command');
        break;

      case 'scan':
        hackerStore.addLine('SCAN(1)                   LootMine Manual', 'header');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('NAME', 'info');
        hackerStore.addLine('    scan - discover hosts on the network', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('SYNOPSIS', 'info');
        hackerStore.addLine('    scan', 'command');
        hackerStore.addLine('    scan <ip>', 'command');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('DESCRIPTION', 'info');
        hackerStore.addLine('    Without arguments, performs a network sweep on', 'output');
        hackerStore.addLine('    10.0.0.0/8 and returns a list of discovered IPs.', 'output');
        hackerStore.addLine('    Hostnames are hidden except for friends.', 'output');
        hackerStore.addLine('    With an IP, performs a port scan (alias for nmap).', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('EXAMPLES', 'info');
        hackerStore.addLine('    scan                 Discover all hosts', 'command');
        hackerStore.addLine('    scan 143.52.201.8    Port scan a target', 'command');
        break;

      case 'nmap':
      case 'portscan':
        hackerStore.addLine('NMAP(1)                   LootMine Manual', 'header');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('NAME', 'info');
        hackerStore.addLine('    nmap - port scan and hostname resolution', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('ALIASES', 'info');
        hackerStore.addLine('    portscan', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('SYNOPSIS', 'info');
        hackerStore.addLine('    nmap <ip|username>', 'command');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('DESCRIPTION', 'info');
        hackerStore.addLine('    Performs a deep scan on a target. Reveals the', 'output');
        hackerStore.addLine('    hostname via reverse DNS, operating system,', 'output');
        hackerStore.addLine('    firewall, defense level, and open ports.', 'output');
        hackerStore.addLine('    Use "scan" first to discover IPs on the network.', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('EXAMPLES', 'info');
        hackerStore.addLine('    nmap 143.52.201.8    Scan IP from network', 'command');
        hackerStore.addLine('    nmap CryptoPhantom   Scan by username', 'command');
        break;

      case 'hack':
        hackerStore.addLine('HACK(1)                   LootMine Manual', 'header');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('NAME', 'info');
        hackerStore.addLine('    hack - steal GameCoin from another player', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('SYNOPSIS', 'info');
        hackerStore.addLine('    hack <ip|username>', 'command');
        hackerStore.addLine('    hack random', 'command');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('DESCRIPTION', 'info');
        hackerStore.addLine('    Initiates a timed hacking puzzle against the', 'output');
        hackerStore.addLine('    target. You must type the correct commands at', 'output');
        hackerStore.addLine('    each stage. Wrong answers cost -5 seconds.', 'output');
        hackerStore.addLine('    Success steals 3-8% of target GC balance.', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('COST', 'info');
        hackerStore.addLine('    Energy: 30 | Internet: 10', 'warning');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('STAGES', 'info');
        hackerStore.addLine('    1. SCAN      Port scanning', 'output');
        hackerStore.addLine('    2. EXPLOIT   Vulnerability exploitation', 'output');
        hackerStore.addLine('    3. ESCALATE  Privilege escalation', 'output');
        hackerStore.addLine('    4. EXTRACT   Fund extraction', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('EXAMPLES', 'info');
        hackerStore.addLine('    hack 143.52.201.8    Hack by IP', 'command');
        hackerStore.addLine('    hack CryptoPhantom   Hack by username', 'command');
        hackerStore.addLine('    hack random          Hack a random target', 'command');
        break;

      case 'spy':
        hackerStore.addLine('SPY(1)                    LootMine Manual', 'header');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('NAME', 'info');
        hackerStore.addLine('    spy - steal intel from another player', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('SYNOPSIS', 'info');
        hackerStore.addLine('    spy <ip|username>', 'command');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('DESCRIPTION', 'info');
        hackerStore.addLine('    Initiates a spy operation. Shorter puzzle than', 'output');
        hackerStore.addLine('    hack (3 stages). Success reveals target stats,', 'output');
        hackerStore.addLine('    rig configuration and wallet data for 24h.', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('COST', 'info');
        hackerStore.addLine('    Energy: 15 | Internet: 5', 'warning');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('STAGES', 'info');
        hackerStore.addLine('    1. SCAN        Network mapping', 'output');
        hackerStore.addLine('    2. INFILTRATE  System infiltration', 'output');
        hackerStore.addLine('    3. EXTRACT     Data extraction', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('EXAMPLES', 'info');
        hackerStore.addLine('    spy 143.52.201.8     Spy by IP', 'command');
        hackerStore.addLine('    spy CryptoPhantom    Spy by username', 'command');
        break;

      case 'sabotage':
        hackerStore.addLine('SABOTAGE(1)               LootMine Manual', 'header');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('NAME', 'info');
        hackerStore.addLine('    sabotage - slow down a player\'s mining', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('SYNOPSIS', 'info');
        hackerStore.addLine('    sabotage <ip|username>', 'command');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('DESCRIPTION', 'info');
        hackerStore.addLine('    Injects a virus that reduces the target\'s', 'output');
        hackerStore.addLine('    mining speed by 15-25% for 2-4 hours.', 'output');
        hackerStore.addLine('    4 stage puzzle. Hardest hack mode.', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('COST', 'info');
        hackerStore.addLine('    Energy: 25 | Internet: 10', 'warning');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('STAGES', 'info');
        hackerStore.addLine('    1. SCAN     Reconnaissance', 'output');
        hackerStore.addLine('    2. EXPLOIT  Gain access', 'output');
        hackerStore.addLine('    3. INJECT   Deploy virus', 'output');
        hackerStore.addLine('    4. COVER    Cover tracks', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('EXAMPLES', 'info');
        hackerStore.addLine('    sabotage 10.45.12.3  Sabotage by IP', 'command');
        hackerStore.addLine('    sabotage DarkHash    Sabotage by username', 'command');
        break;

      case 'bruteforce':
      case 'brute':
        hackerStore.addLine('BRUTEFORCE(1)             LootMine Manual', 'header');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('NAME', 'info');
        hackerStore.addLine('    bruteforce - crack a target\'s password using a rig', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('ALIASES', 'info');
        hackerStore.addLine('    brute', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('SYNOPSIS', 'info');
        hackerStore.addLine('    bruteforce <ip|username> <dict|brute> <rig_id>', 'command');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('MODES', 'info');
        hackerStore.addLine('    dict   Dictionary attack using rockyou.txt.', 'output');
        hackerStore.addLine('           Faster but depends on weak passwords.', 'output');
        hackerStore.addLine('    brute  Raw bruteforce (a-zA-Z0-9 + symbols).', 'output');
        hackerStore.addLine('           Slower but always succeeds.', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('DESCRIPTION', 'info');
        hackerStore.addLine('    Uses a specific mining rig as computing power to', 'output');
        hackerStore.addLine('    crack the target\'s password. The rig must be OFF', 'output');
        hackerStore.addLine('    (not mining). The command powers it on for cracking', 'output');
        hackerStore.addLine('    and powers it off when done. Higher hashrate rigs', 'output');
        hackerStore.addLine('    produce more attempts per second. Rig condition', 'output');
        hackerStore.addLine('    affects cracking speed.', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('    The cracked password is stored in the $key variable.', 'output');
        hackerStore.addLine('    Use it with ssh: ssh <target> $key', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('SPEED', 'info');
        hackerStore.addLine('    dict:  ~800 * rig TH/s attempts/s', 'output');
        hackerStore.addLine('    brute: ~200 * rig TH/s attempts/s', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('EXAMPLES', 'info');
        hackerStore.addLine('    bruteforce 143.52.201.8 dict 2', 'command');
        hackerStore.addLine('    brute CryptoPhantom brute 1', 'command');
        hackerStore.addLine('    ssh 143.52.201.8 $key          (use cracked pw)', 'command');
        break;

      case 'set':
        hackerStore.addLine('SET(1)                    LootMine Manual', 'header');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('NAME', 'info');
        hackerStore.addLine('    set - store a value in a terminal variable', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('SYNOPSIS', 'info');
        hackerStore.addLine('    set <name> <value>', 'command');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('DESCRIPTION', 'info');
        hackerStore.addLine('    Saves a value that can be reused in any command', 'output');
        hackerStore.addLine('    with $name. Variables persist until exit or unset.', 'output');
        hackerStore.addLine('    Use "env" to list all variables.', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('EXAMPLES', 'info');
        hackerStore.addLine('    set target 192.168.1.5', 'command');
        hackerStore.addLine('    nmap $target', 'command');
        hackerStore.addLine('    hack $target', 'command');
        hackerStore.addLine('    set mode dict', 'command');
        hackerStore.addLine('    bruteforce $target $mode 1', 'command');
        break;

      case 'unset':
        hackerStore.addLine('UNSET(1)                  LootMine Manual', 'header');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('NAME', 'info');
        hackerStore.addLine('    unset - remove a terminal variable', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('SYNOPSIS', 'info');
        hackerStore.addLine('    unset <name>', 'command');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('EXAMPLES', 'info');
        hackerStore.addLine('    unset target', 'command');
        break;

      case 'env':
        hackerStore.addLine('ENV(1)                    LootMine Manual', 'header');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('NAME', 'info');
        hackerStore.addLine('    env - list all terminal variables', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('SYNOPSIS', 'info');
        hackerStore.addLine('    env', 'command');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('DESCRIPTION', 'info');
        hackerStore.addLine('    Shows all variables set with the "set" command.', 'output');
        break;

      case 'echo':
        hackerStore.addLine('ECHO(1)                   LootMine Manual', 'header');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('NAME', 'info');
        hackerStore.addLine('    echo - print text to terminal', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('SYNOPSIS', 'info');
        hackerStore.addLine('    echo <text>', 'command');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('DESCRIPTION', 'info');
        hackerStore.addLine('    Prints text to the terminal. Variables ($name)', 'output');
        hackerStore.addLine('    are substituted with their values.', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('EXAMPLES', 'info');
        hackerStore.addLine('    echo hello world', 'command');
        hackerStore.addLine('    echo $target', 'command');
        break;

      case 'ssh':
        hackerStore.addLine('SSH(1)                    LootMine Manual', 'header');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('NAME', 'info');
        hackerStore.addLine('    ssh - connect to a target\'s server', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('SYNOPSIS', 'info');
        hackerStore.addLine('    ssh <ip|username> <password>', 'command');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('DESCRIPTION', 'info');
        hackerStore.addLine('    Opens a remote shell on the target\'s server using', 'output');
        hackerStore.addLine('    the provided password. Get a password by running', 'output');
        hackerStore.addLine('    bruteforce first — the cracked password is stored', 'output');
        hackerStore.addLine('    in the $key variable. Once inside you can browse', 'output');
        hackerStore.addLine('    files, read configs, and steal GC.', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('SESSION COMMANDS', 'info');
        hackerStore.addLine('    ls          List files', 'output');
        hackerStore.addLine('    cat <file>  Read file (wallet.dat, rig_config.txt,', 'output');
        hackerStore.addLine('                mining.log, passwd, .bash_history)', 'output');
        hackerStore.addLine('    siphon      Steal GC from wallet (one-time)', 'output');
        hackerStore.addLine('    ps          Show processes', 'output');
        hackerStore.addLine('    ifconfig    Show network config', 'output');
        hackerStore.addLine('    whoami      Current user', 'output');
        hackerStore.addLine('    exit        Disconnect', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('EXAMPLES', 'info');
        hackerStore.addLine('    bruteforce 192.168.1.5 dict 1', 'command');
        hackerStore.addLine('    ssh 192.168.1.5 $key', 'command');
        hackerStore.addLine('    cat wallet.dat', 'command');
        hackerStore.addLine('    siphon', 'command');
        hackerStore.addLine('    exit', 'command');
        break;

      case 'script':
        hackerStore.addLine('SCRIPT(1)                 LootMine Manual', 'header');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('NAME', 'info');
        hackerStore.addLine('    script - record a sequence of commands', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('SYNOPSIS', 'info');
        hackerStore.addLine('    script <name>', 'command');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('DESCRIPTION', 'info');
        hackerStore.addLine('    Enters recording mode. Every command you type', 'output');
        hackerStore.addLine('    is saved but not executed. Type "end" to finish', 'output');
        hackerStore.addLine('    recording. Use "run <name>" to execute later.', 'output');
        hackerStore.addLine('    Variables ($var) are resolved at execution time.', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('EXAMPLES', 'info');
        hackerStore.addLine('    script recon', 'command');
        hackerStore.addLine('    scan', 'command');
        hackerStore.addLine('    nmap $target', 'command');
        hackerStore.addLine('    end', 'command');
        break;

      case 'run':
        hackerStore.addLine('RUN(1)                    LootMine Manual', 'header');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('NAME', 'info');
        hackerStore.addLine('    run - execute a saved script', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('SYNOPSIS', 'info');
        hackerStore.addLine('    run <name>', 'command');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('DESCRIPTION', 'info');
        hackerStore.addLine('    Executes all commands in the named script', 'output');
        hackerStore.addLine('    sequentially with a short delay between each.', 'output');
        hackerStore.addLine('    Type "stop" to abort a running script.', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('EXAMPLES', 'info');
        hackerStore.addLine('    run recon', 'command');
        break;

      case 'scripts':
        hackerStore.addLine('SCRIPTS(1)                LootMine Manual', 'header');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('NAME', 'info');
        hackerStore.addLine('    scripts - list all saved scripts', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('SYNOPSIS', 'info');
        hackerStore.addLine('    scripts', 'command');
        break;

      case 'cat':
        hackerStore.addLine('CAT(1)                    LootMine Manual', 'header');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('NAME', 'info');
        hackerStore.addLine('    cat - display contents of a script', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('SYNOPSIS', 'info');
        hackerStore.addLine('    cat <name>', 'command');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('EXAMPLES', 'info');
        hackerStore.addLine('    cat recon', 'command');
        break;

      case 'delscript':
        hackerStore.addLine('DELSCRIPT(1)              LootMine Manual', 'header');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('NAME', 'info');
        hackerStore.addLine('    delscript - delete a saved script', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('SYNOPSIS', 'info');
        hackerStore.addLine('    delscript <name>', 'command');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('EXAMPLES', 'info');
        hackerStore.addLine('    delscript recon', 'command');
        break;

      case 'sleep':
        hackerStore.addLine('SLEEP(1)                  LootMine Manual', 'header');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('NAME', 'info');
        hackerStore.addLine('    sleep - pause execution for N seconds', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('SYNOPSIS', 'info');
        hackerStore.addLine('    sleep <seconds>', 'command');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('DESCRIPTION', 'info');
        hackerStore.addLine('    Pauses execution. Max 10 seconds.', 'output');
        hackerStore.addLine('    Useful inside scripts for timing.', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('EXAMPLES', 'info');
        hackerStore.addLine('    sleep 2', 'command');
        hackerStore.addLine('    sleep 0.5', 'command');
        break;

      case 'stop':
        hackerStore.addLine('STOP(1)                   LootMine Manual', 'header');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('NAME', 'info');
        hackerStore.addLine('    stop - abort a running script', 'output');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('SYNOPSIS', 'info');
        hackerStore.addLine('    stop', 'command');
        break;

      default:
        hackerStore.addLine(`No manual entry for "${cmd}"`, 'error');
        hackerStore.addLine('Type "help" to see available commands.', 'info');
        return;
    }

    hackerStore.addLine('', 'output');
  }

  // ─── Rigs ───
  function cmdRigs() {
    const rigs = miningStore.rigs;
    if (!rigs || rigs.length === 0) {
      hackerStore.addLine('No rigs found. Purchase rigs from the Market.', 'warning');
      return;
    }
    hackerStore.addLine('', 'output');
    hackerStore.addLine('═══ MINING RIGS ═══', 'header');
    hackerStore.addLine('', 'output');
    const header = padRight('ID', 4) + padRight('NAME', 20) + padRight('STATUS', 10) + padRight('TEMP', 8) + padRight('HASH', 12) + 'COND';
    hackerStore.addLine(header, 'info');
    hackerStore.addLine('─'.repeat(66), 'output');
    rigs.forEach((rig, idx) => {
      const status = rig.is_active ? 'ONLINE' : 'OFFLINE';
      const statusType = rig.is_active ? 'success' : 'output';
      const temp = `${Math.round(rig.temperature ?? 25)}°C`;
      const hash = `${miningStore.getRigEffectiveHashrate(rig).toFixed(1)} TH/s`;
      const cond = `${Math.round(rig.condition ?? 100)}%`;
      const line = padRight(`${idx + 1}`, 4) + padRight(rig.rig.name, 20) + padRight(status, 10) + padRight(temp, 8) + padRight(hash, 12) + cond;
      hackerStore.addLine(line, statusType as any);
    });
    hackerStore.addLine('', 'output');
    hackerStore.addLine(`Total: ${rigs.length} rigs | Active: ${miningStore.activeRigsCount}`, 'info');
    hackerStore.addLine('', 'output');
  }

  async function cmdRig(args: string[]) {
    if (args.length < 2) {
      hackerStore.addLine('Usage: rig <on|off|status> <id|all>', 'warning');
      return;
    }
    const action = args[0];
    const target = args[1];

    if (action === 'on' || action === 'off') {
      if (target === 'all') {
        const rigs = miningStore.rigs;
        const toToggle = rigs.filter(r => action === 'on' ? !r.is_active : r.is_active);
        if (toToggle.length === 0) {
          hackerStore.addLine(`All rigs are already ${action === 'on' ? 'online' : 'offline'}.`, 'info');
          return;
        }
        hackerStore.addLine(`Toggling ${toToggle.length} rigs ${action}...`, 'info');
        for (const rig of toToggle) {
          const result = await miningStore.toggleRig(rig.id);
          if (result.success) {
            hackerStore.addLine(`  [OK] ${rig.rig.name} → ${action === 'on' ? 'ONLINE' : 'OFFLINE'}`, 'success');
          } else {
            hackerStore.addLine(`  [FAIL] ${rig.rig.name}: ${result.error}`, 'error');
          }
        }
        return;
      }
      const idx = parseInt(target) - 1;
      const rig = miningStore.rigs[idx];
      if (!rig) {
        hackerStore.addLine(`Rig #${target} not found. Use "rigs" to list available rigs.`, 'error');
        return;
      }
      if ((action === 'on' && rig.is_active) || (action === 'off' && !rig.is_active)) {
        hackerStore.addLine(`${rig.rig.name} is already ${action === 'on' ? 'online' : 'offline'}.`, 'info');
        return;
      }
      hackerStore.addLine(`Toggling ${rig.rig.name} ${action}...`, 'info');
      const result = await miningStore.toggleRig(rig.id);
      if (result.success) {
        hackerStore.addLine(`[OK] ${rig.rig.name} → ${action === 'on' ? 'ONLINE' : 'OFFLINE'}`, 'success');
        playSound('success');
      } else {
        hackerStore.addLine(`[FAIL] ${result.error}`, 'error');
        playSound('error');
      }
    } else if (action === 'status') {
      const idx = parseInt(target) - 1;
      const rig = miningStore.rigs[idx];
      if (!rig) {
        hackerStore.addLine(`Rig #${target} not found.`, 'error');
        return;
      }
      hackerStore.addLine('', 'output');
      hackerStore.addLine(`═══ RIG STATUS: ${rig.rig.name} ═══`, 'header');
      hackerStore.addLine('', 'output');
      hackerStore.addLine(`  Status:      ${rig.is_active ? 'ONLINE' : 'OFFLINE'}`, rig.is_active ? 'success' : 'output');
      hackerStore.addLine(`  Tier:        ${rig.rig.tier}`, 'output');
      hackerStore.addLine(`  Temperature: ${Math.round(rig.temperature ?? 25)}°C`, 'output');
      hackerStore.addLine(`  Condition:   ${Math.round(rig.condition ?? 100)}%`, 'output');
      hackerStore.addLine(`  Hashrate:    ${miningStore.getRigEffectiveHashrate(rig).toFixed(2)} TH/s`, 'info');
      hackerStore.addLine(`  Base Hash:   ${rig.rig.hashrate} TH/s`, 'output');
      hackerStore.addLine(`  Power:       ${rig.rig.power_consumption} ⚡/min`, 'output');
      hackerStore.addLine(`  Internet:    ${rig.rig.internet_consumption} 📡/min`, 'output');
      const cooling = miningStore.rigCooling[rig.id];
      if (cooling && cooling.length > 0) {
        hackerStore.addLine(`  Cooling:     ${cooling.map((c: any) => c.name || c.cooling_item?.name).join(', ')}`, 'info');
      } else {
        hackerStore.addLine(`  Cooling:     None installed`, 'warning');
      }
      const boosts = miningStore.rigBoosts[rig.id];
      if (boosts && boosts.length > 0) {
        hackerStore.addLine(`  Boosts:      ${boosts.length} active`, 'info');
      }
      hackerStore.addLine('', 'output');
    } else {
      hackerStore.addLine(`Unknown rig action: ${action}. Use on, off, or status.`, 'error');
    }
  }

  // ─── Inventory ───
  async function cmdInventory() {
    await inventoryStore.fetchInventory();
    hackerStore.addLine('', 'output');
    hackerStore.addLine('═══ INVENTORY ═══', 'header');
    hackerStore.addLine('', 'output');
    const rigItems = inventoryStore.rigItems;
    const coolingItems = inventoryStore.coolingItems;
    const boostItems = inventoryStore.boostItems;
    const materials = inventoryStore.materialItems;
    if (rigItems.length > 0) {
      hackerStore.addLine('  RIGS:', 'info');
      rigItems.forEach((item: any) => { hackerStore.addLine(`    ${item.name} x${item.quantity} (${item.tier})`, 'output'); });
    }
    if (coolingItems.length > 0) {
      hackerStore.addLine('  COOLING:', 'info');
      coolingItems.forEach((item: any) => { hackerStore.addLine(`    ${item.name} x${item.quantity}`, 'output'); });
    }
    if (boostItems.length > 0) {
      hackerStore.addLine('  BOOSTS:', 'info');
      boostItems.forEach((item: any) => { hackerStore.addLine(`    ${item.name} x${item.quantity}`, 'output'); });
    }
    if (materials && materials.length > 0) {
      hackerStore.addLine('  MATERIALS:', 'info');
      materials.forEach((item: any) => { hackerStore.addLine(`    ${item.name} x${item.quantity}`, 'output'); });
    }
    const total = rigItems.length + coolingItems.length + boostItems.length + (materials?.length || 0);
    if (total === 0) { hackerStore.addLine('  Inventory is empty.', 'warning'); }
    hackerStore.addLine('', 'output');
  }

  // ─── Stats / Balance / Hashrate ───
  function cmdStats() {
    const player = authStore.player;
    if (!player) { hackerStore.addLine('Not authenticated.', 'error'); return; }
    hackerStore.addLine('', 'output');
    hackerStore.addLine('═══ PLAYER STATS ═══', 'header');
    hackerStore.addLine('', 'output');
    hackerStore.addLine(`  Username:    ${player.username}`, 'success');
    hackerStore.addLine(`  Reputation:  ${player.reputation_score}`, 'output');
    hackerStore.addLine(`  Region:      ${player.region || 'Unknown'}`, 'output');
    hackerStore.addLine(`  Rigs:        ${miningStore.rigs.length} (${miningStore.activeRigsCount} active)`, 'output');
    hackerStore.addLine(`  Hashrate:    ${miningStore.effectiveHashrate.toFixed(2)} TH/s`, 'info');
    hackerStore.addLine(`  Energy:      ${Math.round(player.energy)}/${player.max_energy} ⚡`, 'output');
    hackerStore.addLine(`  Internet:    ${Math.round(player.internet)}/${player.max_internet} 📡`, 'output');
    hackerStore.addLine(`  Blocks:      ${player.blocks_mined || 0} mined`, 'output');
    hackerStore.addLine(`  Rig Slots:   ${miningStore.rigs.length}/${player.rig_slots || 4}`, 'output');
    hackerStore.addLine('', 'output');
  }

  function cmdBalance() {
    const player = authStore.player;
    if (!player) { hackerStore.addLine('Not authenticated.', 'error'); return; }
    hackerStore.addLine('', 'output');
    hackerStore.addLine('═══ BALANCE ═══', 'header');
    hackerStore.addLine('', 'output');
    hackerStore.addLine(`  GameCoin:  ${formatNum(player.gamecoin_balance)} GC`, 'success');
    hackerStore.addLine(`  Crypto:    ${formatNum(player.crypto_balance, 8)} ₿`, 'info');
    hackerStore.addLine(`  RON:       ${formatNum(player.ron_balance, 4)} RON`, 'output');
    hackerStore.addLine('', 'output');
  }

  function cmdHashrate() {
    hackerStore.addLine('', 'output');
    hackerStore.addLine('═══ HASHRATE OVERVIEW ═══', 'header');
    hackerStore.addLine('', 'output');
    hackerStore.addLine(`  Total Effective: ${miningStore.effectiveHashrate.toFixed(2)} TH/s`, 'success');
    hackerStore.addLine(`  Network:         ${(miningStore.networkStats as any)?.hashrate?.toFixed(2) || '?'} TH/s`, 'output');
    hackerStore.addLine(`  Active Miners:   ${(miningStore.networkStats as any)?.activeMiners || '?'}`, 'output');
    hackerStore.addLine('', 'output');
    if (miningStore.rigs.length > 0) {
      hackerStore.addLine('  PER RIG:', 'info');
      miningStore.rigs.forEach((rig, idx) => {
        const effective = miningStore.getRigEffectiveHashrate(rig).toFixed(2);
        const status = rig.is_active ? '●' : '○';
        hackerStore.addLine(`    ${status} #${idx + 1} ${padRight(rig.rig.name, 18)} ${effective} TH/s`, rig.is_active ? 'success' : 'output');
      });
    }
    hackerStore.addLine('', 'output');
  }

  // ═══════════════════════════════════════
  // ─── HACK GAME (fully text-based) ───
  // ═══════════════════════════════════════

  function getStages(mode: HackMode, targetUsername: string): HackStage[] {
    if (mode === 'steal') {
      return [
        {
          name: 'SCAN', prompt: '> STAGE 1: PORT SCANNING',
          output: [
            'Initiating network reconnaissance...', 'Probing target: ' + targetUsername,
            'Discovering open services...', '',
            'PORT     STATE   SERVICE', '22/tcp   open    ssh', '80/tcp   open    http', '443/tcp  open    https', '3306/tcp open    mysql', '',
            'SELECT SCAN METHOD:',
          ],
          options: shuffle([
            { label: 'nmap -sV --script=vuln', command: 'nmap -sV --script=vuln', correct: true },
            { label: 'ping -c 100 target', command: 'ping -c 100 target', correct: false },
            { label: 'traceroute --hops=64', command: 'traceroute --hops=64', correct: false },
          ]),
        },
        {
          name: 'EXPLOIT', prompt: '> STAGE 2: EXPLOIT VULNERABILITY',
          output: [
            'Vulnerability scan complete.', 'Found 3 potential attack vectors:', '',
            '[CVE-2024-3891] MySQL buffer overflow - CRITICAL',
            '[CVE-2024-1205] SSH key exchange flaw - HIGH',
            '[CVE-2024-0044] HTTP header injection - MEDIUM', '',
            'SELECT EXPLOIT:',
          ],
          options: shuffle([
            { label: 'exploit CVE-2024-3891 --payload=reverse_shell', command: 'exploit CVE-2024-3891', correct: true },
            { label: 'bruteforce ssh --wordlist=rockyou.txt', command: 'bruteforce ssh', correct: false },
            { label: 'sqlmap -u target/login --dump', command: 'sqlmap -u target', correct: false },
          ]),
        },
        {
          name: 'ESCALATE', prompt: '> STAGE 3: PRIVILEGE ESCALATION',
          output: [
            'Shell obtained! User: www-data', 'Current privileges: LIMITED', '',
            'uid=33(www-data) gid=33(www-data)', 'Kernel: Linux 5.15.0-91-generic', '',
            'Checking for escalation vectors...', 'SUID binary found: /usr/bin/pkexec', '',
            'SELECT ESCALATION METHOD:',
          ],
          options: shuffle([
            { label: 'pkexec --exploit CVE-2021-4034', command: 'pkexec exploit', correct: true },
            { label: 'sudo su (no password)', command: 'sudo su', correct: false },
            { label: 'chmod 777 /etc/shadow', command: 'chmod 777 /etc/shadow', correct: false },
          ]),
        },
        {
          name: 'EXTRACT', prompt: '> STAGE 4: EXTRACT FUNDS',
          output: [
            'ROOT ACCESS GRANTED!', '', 'uid=0(root) gid=0(root)',
            'Accessing wallet daemon...', 'Wallet balance detected: ████████ GC', '',
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
          name: 'SCAN', prompt: '> STAGE 1: NETWORK MAPPING',
          output: [
            'Mapping target network topology...', 'Target: ' + targetUsername, '',
            'Discovering network segments...',
            '10.0.1.0/24 - Mining Operations', '10.0.2.0/24 - Storage Cluster', '10.0.3.0/24 - Admin Panel', '',
            'SELECT SCAN APPROACH:',
          ],
          options: shuffle([
            { label: 'arp-scan --localnet --stealth', command: 'arp-scan --stealth', correct: true },
            { label: 'nslookup target.local', command: 'nslookup target', correct: false },
            { label: 'whois target.mining.net', command: 'whois target', correct: false },
          ]),
        },
        {
          name: 'INFILTRATE', prompt: '> STAGE 2: SYSTEM INFILTRATION',
          output: [
            'Network mapped successfully.', 'Mining server located at 10.0.1.12', '',
            'Firewall detected: iptables v1.8.7', 'IDS running: Snort 3.1.58', '',
            'SELECT INFILTRATION METHOD:',
          ],
          options: shuffle([
            { label: 'ssh -D 9050 -o ProxyCommand="ncat --proxy-type socks5"', command: 'ssh tunnel proxy', correct: true },
            { label: 'telnet 10.0.1.12 23', command: 'telnet target', correct: false },
            { label: 'ftp anonymous@10.0.1.12', command: 'ftp anonymous', correct: false },
          ]),
        },
        {
          name: 'EXTRACT', prompt: '> STAGE 3: DATA EXTRACTION',
          output: [
            'Tunnel established!', 'Connected to mining server.', '',
            'Databases found:', '  - mining_stats (42MB)', '  - rig_config (8MB)', '  - wallet_data (encrypted)', '',
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
          name: 'SCAN', prompt: '> STAGE 1: RECONNAISSANCE',
          output: [
            'Scanning target infrastructure...', 'Target: ' + targetUsername, '',
            'Services detected:',
            '  mining_daemon    PID:1337  RUNNING', '  rig_controller   PID:1338  RUNNING', '  cooling_monitor  PID:1339  RUNNING', '',
            'SELECT RECON METHOD:',
          ],
          options: shuffle([
            { label: 'enum4linux -a target && nikto -h target', command: 'enum4linux + nikto', correct: true },
            { label: 'curl http://target/robots.txt', command: 'curl robots', correct: false },
            { label: 'dig ANY target.mining.net', command: 'dig target', correct: false },
          ]),
        },
        {
          name: 'EXPLOIT', prompt: '> STAGE 2: GAIN ACCESS',
          output: [
            'Enumeration complete.', 'Critical vuln found in rig_controller!', '',
            '[!] rig_controller v2.1 - RCE via deserialization', '[!] Exploit available: CVE-2025-0137', '',
            'SELECT EXPLOIT:',
          ],
          options: shuffle([
            { label: 'msfconsole -x "use exploit/multi/deserialize"', command: 'metasploit deserialize', correct: true },
            { label: 'hydra -l admin -P pass.txt target ssh', command: 'hydra bruteforce', correct: false },
            { label: 'nikto -h target -Tuning x', command: 'nikto scan', correct: false },
          ]),
        },
        {
          name: 'INJECT', prompt: '> STAGE 3: INJECT VIRUS',
          output: [
            'Access obtained to rig_controller!', 'Preparing payload...', '',
            'Mining daemon: ACTIVE (hashrate: ████ TH/s)', 'Cooling system: NOMINAL', '',
            'SELECT INJECTION METHOD:',
          ],
          options: shuffle([
            { label: 'inject --payload=mining_throttle --persist --stealth', command: 'inject mining_throttle', correct: true },
            { label: 'rm -rf /mining/*', command: 'rm -rf mining', correct: false },
            { label: 'echo "malware" > /tmp/virus.sh', command: 'echo malware', correct: false },
          ]),
        },
        {
          name: 'COVER', prompt: '> STAGE 4: COVER TRACKS',
          output: [
            'Payload injected successfully!', 'Mining speed will degrade over time.', '',
            'WARNING: IDS activity detected!', 'Log entries found in /var/log/auth.log', '',
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

  // ─── Network Scan (list all targets) ───
  async function cmdScanNetwork(piped = false) {
    const player = authStore.player;
    if (!player) { hackerStore.addLine('Not authenticated.', 'error'); return; }

    hackerStore.addLine('', 'output');
    hackerStore.addLine('Scanning network 10.0.0.0/8 ...', 'info');
    hackerStore.addLine('', 'output');

    // Fetch friends list for hostname resolution
    await friendsStore.fetchFriends();
    const friendUsernames = new Set(
      friendsStore.friends.map((f: any) => (f.username || '').toLowerCase()),
    );

    // Fetch real players from leaderboard
    let players: { username: string; reputation_score?: number; hashrate?: number }[] = [];
    try {
      const [repResult, miningResult] = await Promise.all([
        getReputationLeaderboard(20),
        getMiningLeaderboard(20),
      ]);
      const repPlayers = repResult?.data || repResult || [];
      const miningPlayers = miningResult?.data || miningResult || [];

      // Merge and deduplicate
      const seen = new Set<string>();
      for (const p of [...repPlayers, ...miningPlayers]) {
        const name = p.username || p.player_username;
        if (name && !seen.has(name.toLowerCase()) && name.toLowerCase() !== player.username.toLowerCase()) {
          seen.add(name.toLowerCase());
          players.push({
            username: name,
            reputation_score: p.reputation_score ?? p.reputation ?? 0,
            hashrate: p.total_hashrate ?? p.hashrate ?? 0,
          });
        }
      }
    } catch {
      // Fallback: generate fake players if API fails
    }

    // If no real players found, generate some NPCs
    if (players.length === 0) {
      const npcNames = [
        'CryptoPhantom', 'NeonMiner42', 'DarkHash', 'ByteReaper', 'SilkR0ad',
        'ZeroCool', 'AcidBurn', 'L0rdNikon', 'CerealKiller', 'CrashOverride',
        'Ph4ntom', 'N3tRunn3r', 'D4rkW3b', 'HashSlinger', 'BitBandit',
      ];
      players = npcNames.map(name => ({
        username: name,
        reputation_score: Math.floor(Math.random() * 2000) + 100,
        hashrate: Math.floor(Math.random() * 500) + 10,
      }));
    }

    // Store IP → username mapping for this session
    for (const p of players) {
      const ip = generateFakeIP(p.username);
      ipToUsername.value[ip] = p.username;
    }

    // Build output
    const lines: { text: string; type: OutputLine['type'] }[] = [
      { text: '═══ NETWORK SCAN RESULTS ═══', type: 'header' },
      { text: '', type: 'output' },
      { text: `${padRight('#', 4)}${padRight('IP ADDRESS', 18)}${padRight('HOSTNAME', 22)}STATUS`, type: 'info' },
      { text: '─'.repeat(54), type: 'output' },
    ];

    players.forEach((p, idx) => {
      const ip = generateFakeIP(p.username);
      const isFriend = friendUsernames.has(p.username.toLowerCase());
      const hostname = isFriend ? p.username : '???';
      const statuses = ['ONLINE', 'ONLINE', 'ONLINE', 'IDLE', 'MINING'];
      let h = 0;
      for (let i = 0; i < p.username.length; i++) h = ((h << 5) - h) + p.username.charCodeAt(i);
      const status = statuses[Math.abs(h) % statuses.length];
      const statusType: OutputLine['type'] = isFriend ? 'success' : status === 'MINING' ? 'warning' : 'output';
      const line = `${padRight(`${idx + 1}`, 4)}${padRight(ip, 18)}${padRight(hostname, 22)}${status}`;
      lines.push({ text: line, type: statusType });
    });

    lines.push({ text: '', type: 'output' });
    lines.push({ text: `${players.length} hosts discovered.`, type: 'info' });
    lines.push({ text: '', type: 'output' });

    // Output: instant if piped, typewriter if interactive
    if (piped) {
      for (const l of lines) hackerStore.addLine(l.text, l.type);
    } else {
      let lineIdx = 0;
      const scanInterval = window.setInterval(() => {
        if (lineIdx < lines.length) {
          hackerStore.addLine(lines[lineIdx].text, lines[lineIdx].type);
          lineIdx++;
        } else {
          clearInterval(scanInterval);
        }
      }, 50);
    }
  }

  // Resolve an IP or username to a username
  function resolveTarget(input: string): string {
    // Check if it's an IP in our mapping
    if (ipToUsername.value[input]) {
      return ipToUsername.value[input];
    }
    // Otherwise treat as username
    return input;
  }

  function generateFakeIP(username: string): string {
    let hash = 0;
    for (let i = 0; i < username.length; i++) {
      hash = ((hash << 5) - hash) + username.charCodeAt(i);
      hash |= 0;
    }
    const a = Math.abs(hash % 223) + 10;
    const b = Math.abs((hash >> 8) % 255);
    const c = Math.abs((hash >> 16) % 255);
    const d = Math.abs((hash >> 24) % 254) + 1;
    return `${a}.${b}.${c}.${d}`;
  }

  function cmdNmap(args: string[], piped = false) {
    if (args.length === 0) {
      hackerStore.addLine('Usage: nmap <ip|username>', 'warning');
      return;
    }

    const rawTarget = args.join(' ');
    const username = resolveTarget(rawTarget);
    const player = authStore.player;
    if (!player) { hackerStore.addLine('Not authenticated.', 'error'); return; }

    if (username.toLowerCase() === player.username.toLowerCase()) {
      hackerStore.addLine('Cannot scan yourself. Use "stats" instead.', 'warning');
      return;
    }

    const ip = generateFakeIP(username);
    // Store mapping in case they used username directly
    ipToUsername.value[ip] = username;

    const openPorts = [
      { port: 22, service: 'ssh', version: 'OpenSSH 8.9p1' },
      { port: 80, service: 'http', version: 'nginx 1.24.0' },
      { port: 443, service: 'https', version: 'nginx 1.24.0' },
      { port: 3306, service: 'mysql', version: 'MySQL 8.0.35' },
      { port: 6379, service: 'redis', version: 'Redis 7.2.3' },
      { port: 8080, service: 'mining-api', version: 'LootMine Daemon 2.1' },
      { port: 9090, service: 'rig-ctrl', version: 'RigController 1.8' },
    ];

    // Deterministic selection based on username hash
    let hash = 0;
    for (let i = 0; i < username.length; i++) {
      hash = ((hash << 5) - hash) + username.charCodeAt(i);
      hash |= 0;
    }
    const numPorts = 3 + Math.abs(hash % 5);
    const selectedPorts = [...openPorts].sort(() => (hash = (hash * 16807) % 2147483647, hash % 2 === 0 ? 1 : -1)).slice(0, numPorts);
    selectedPorts.sort((a, b) => a.port - b.port);

    const defenseLevel = (Math.abs(hash) % 5) + 1;
    const firewallNames = ['iptables', 'pfSense', 'Cloudflare WAF', 'ModSecurity', 'fail2ban'];
    const firewall = firewallNames[Math.abs(hash) % firewallNames.length];
    const osNames = ['Ubuntu 22.04 LTS', 'Debian 12', 'CentOS 9', 'Alpine 3.18', 'Arch Linux'];
    const os = osNames[Math.abs(hash >> 4) % osNames.length];

    hackerStore.addLine('', 'output');
    hackerStore.addLine(`Starting Nmap scan on ${ip}...`, 'info');
    hackerStore.addLine('', 'output');

    const lines: { text: string; type: OutputLine['type'] }[] = [
      { text: `Nmap scan report for ${ip}`, type: 'header' },
      { text: `Host is up (0.0${Math.abs(hash % 90) + 10}s latency).`, type: 'output' },
      { text: '', type: 'output' },
      { text: 'Resolving hostname via reverse DNS...', type: 'info' },
      { text: `HOSTNAME: ${username}`, type: 'success' },
      { text: '', type: 'output' },
      { text: `OS: ${os}`, type: 'output' },
      { text: `Firewall: ${firewall}`, type: defenseLevel >= 4 ? 'warning' : 'output' },
      { text: `Defense Level: ${'█'.repeat(defenseLevel)}${'░'.repeat(5 - defenseLevel)} (${defenseLevel}/5)`, type: defenseLevel >= 4 ? 'error' : defenseLevel >= 2 ? 'warning' : 'success' },
      { text: '', type: 'output' },
      { text: 'PORT      STATE   SERVICE          VERSION', type: 'info' },
      { text: '─'.repeat(55), type: 'output' },
    ];

    selectedPorts.forEach(p => {
      const portStr = `${p.port}/tcp`.padEnd(10);
      const stateStr = 'open'.padEnd(8);
      const serviceStr = p.service.padEnd(17);
      lines.push({ text: `${portStr}${stateStr}${serviceStr}${p.version}`, type: 'success' });
    });

    lines.push({ text: '', type: 'output' });
    lines.push({ text: `${selectedPorts.length} open ports found on ${ip}`, type: 'info' });

    if (defenseLevel >= 4) {
      lines.push({ text: '⚠ HIGH DEFENSE - Hack will be harder', type: 'warning' });
    } else if (defenseLevel <= 2) {
      lines.push({ text: '● LOW DEFENSE - Easy target', type: 'success' });
    }

    lines.push({ text: '', type: 'output' });

    // Output: instant if piped, typewriter if interactive
    if (piped) {
      for (const l of lines) hackerStore.addLine(l.text, l.type);
    } else {
      let idx = 0;
      const scanInterval = window.setInterval(() => {
        if (idx < lines.length) {
          hackerStore.addLine(lines[idx].text, lines[idx].type);
          idx++;
        } else {
          clearInterval(scanInterval);
        }
      }, 60);
    }
  }

  // ─── SSH Session ───
  function cmdSsh(args: string[]) {
    if (args.length < 2) {
      hackerStore.addLine('Usage: ssh <ip|username> <password>', 'warning');
      hackerStore.addLine('Get a password with: bruteforce <target> <mode> <rig>', 'info');
      return;
    }

    const rawTarget = args[0];
    const pw = args[1];
    const username = resolveTarget(rawTarget);
    const player = authStore.player;
    if (!player) { hackerStore.addLine('Not authenticated.', 'error'); return; }

    if (username.toLowerCase() === player.username.toLowerCase()) {
      hackerStore.addLine('Cannot SSH into yourself.', 'error');
      return;
    }

    const ip = generateFakeIP(username);

    // Activate SSH session
    sshActive.value = true;
    sshTarget.value = username;
    sshPrompt.value = `root@${username}:~#`;
    sshSiphoned.value = false;

    hackerStore.addLine('', 'output');
    hackerStore.addLine(`Connecting to ${ip}:22...`, 'info');
    hackerStore.addLine(`Authenticating as root (password: ${pw})...`, 'info');
    hackerStore.addLine('[OK] Authentication successful.', 'success');
    hackerStore.addLine('', 'output');
    hackerStore.addLine(`Welcome to ${username}'s mining server`, 'header');
    hackerStore.addLine('Linux mining-node 5.15.0 x86_64', 'output');
    hackerStore.addLine('', 'output');
    hackerStore.addLine('Type "help" for available commands. Type "exit" to disconnect.', 'info');
    hackerStore.addLine('', 'output');

    playSound('hack_success' as any);
  }

  function handleSshInput(input: string) {
    const parts = input.trim().toLowerCase().split(/\s+/);
    const cmd = parts[0];
    const args = parts.slice(1);
    const target = sshTarget.value;

    // Generate deterministic fake data from target username
    let h = 0;
    for (let i = 0; i < target.length; i++) h = ((h << 5) - h) + target.charCodeAt(i);
    const gcBalance = Math.abs(h % 50000) + 1000;
    const cryptoBalance = (Math.abs(h % 100000) / 100000).toFixed(8);
    const rigCount = (Math.abs(h >> 4) % 6) + 1;
    const totalHash = ((Math.abs(h >> 8) % 500) + 50) / 10;
    const defenseLevel = (Math.abs(h) % 5) + 1;
    const ip = generateFakeIP(target);

    switch (cmd) {
      case 'help':
        hackerStore.addLine('', 'output');
        hackerStore.addLine('═══ SSH SESSION COMMANDS ═══', 'header');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('  ls              List files in current directory', 'output');
        hackerStore.addLine('  cat <file>      Read file contents', 'output');
        hackerStore.addLine('  pwd             Print working directory', 'output');
        hackerStore.addLine('  whoami          Show current user', 'output');
        hackerStore.addLine('  ps              Show running processes', 'output');
        hackerStore.addLine('  ifconfig        Show network config', 'output');
        hackerStore.addLine('  siphon          Steal GC from wallet (one-time)', 'output');
        hackerStore.addLine('  exit            Disconnect from target', 'output');
        hackerStore.addLine('', 'output');
        break;

      case 'ls':
        hackerStore.addLine('drwxr-xr-x  root  .ssh/', 'info');
        hackerStore.addLine('-rw-------  root  wallet.dat', 'success');
        hackerStore.addLine('-rw-r--r--  root  rig_config.txt', 'output');
        hackerStore.addLine('-rw-r--r--  root  mining.log', 'output');
        hackerStore.addLine('-rw-------  root  .bash_history', 'output');
        hackerStore.addLine(`-rw-r--r--  root  passwd`, 'output');
        break;

      case 'cat':
        {
          const file = args[0];
          if (!file) {
            hackerStore.addLine('Usage: cat <file>', 'warning');
            break;
          }
          switch (file) {
            case 'wallet.dat':
              hackerStore.addLine('', 'output');
              hackerStore.addLine('═══ WALLET DATA ═══', 'header');
              hackerStore.addLine(`  Owner:     ${target}`, 'output');
              hackerStore.addLine(`  Balance:   ${gcBalance.toLocaleString()} GC`, 'success');
              hackerStore.addLine(`  Crypto:    ${cryptoBalance} BTC`, 'info');
              hackerStore.addLine(`  Address:   0x${Math.abs(h).toString(16).padStart(40, '0').slice(0, 40)}`, 'output');
              hackerStore.addLine('', 'output');
              if (!sshSiphoned.value) {
                hackerStore.addLine('Use "siphon" to steal GC from this wallet.', 'info');
              }
              break;
            case 'rig_config.txt':
              hackerStore.addLine('', 'output');
              hackerStore.addLine('═══ RIG CONFIGURATION ═══', 'header');
              hackerStore.addLine(`  Rigs:       ${rigCount}`, 'output');
              hackerStore.addLine(`  Total Hash: ${totalHash.toFixed(1)} TH/s`, 'info');
              hackerStore.addLine(`  Defense:    ${'█'.repeat(defenseLevel)}${'░'.repeat(5 - defenseLevel)} (${defenseLevel}/5)`, defenseLevel >= 4 ? 'warning' : 'output');
              hackerStore.addLine(`  Cooling:    Liquid (${60 + Math.abs(h % 30)}%)`, 'output');
              hackerStore.addLine(`  Mode:       Pool mining`, 'output');
              hackerStore.addLine('', 'output');
              break;
            case 'mining.log':
              hackerStore.addLine('', 'output');
              hackerStore.addLine('[INFO]  Mining daemon started', 'output');
              hackerStore.addLine(`[INFO]  Connected to pool (${rigCount} rigs)`, 'output');
              hackerStore.addLine(`[INFO]  Hashrate: ${totalHash.toFixed(1)} TH/s`, 'info');
              hackerStore.addLine(`[INFO]  Shares accepted: ${Math.abs(h % 9999)}`, 'output');
              hackerStore.addLine(`[WARN]  Temperature spike on rig #${(Math.abs(h) % rigCount) + 1}`, 'warning');
              hackerStore.addLine(`[INFO]  Last block reward: ${(Math.abs(h % 500) + 50).toFixed(0)} GC`, 'success');
              hackerStore.addLine('', 'output');
              break;
            case 'passwd':
              hackerStore.addLine(`root:$6$rounds=5000$${Math.abs(h).toString(36)}:0:0:root:/root:/bin/bash`, 'output');
              hackerStore.addLine(`${target}:$6$${Math.abs(h >> 4).toString(36)}:1000:1000::/home/${target}:/bin/bash`, 'output');
              break;
            case '.bash_history':
              hackerStore.addLine('cd /mining', 'output');
              hackerStore.addLine('./start_mining.sh --pool=lootmine', 'output');
              hackerStore.addLine(`rig status all`, 'output');
              hackerStore.addLine('cat wallet.dat', 'output');
              hackerStore.addLine(`withdraw ${Math.abs(h % 200)} GC --to=exchange`, 'output');
              break;
            case '.ssh/authorized_keys':
            case '.ssh':
              hackerStore.addLine(`ssh-rsa AAAA...${Math.abs(h).toString(36).slice(0, 20)} root@mining-node`, 'output');
              break;
            default:
              hackerStore.addLine(`cat: ${file}: No such file or directory`, 'error');
          }
        }
        break;

      case 'pwd':
        hackerStore.addLine('/root', 'output');
        break;

      case 'whoami':
        hackerStore.addLine('root', 'success');
        break;

      case 'ps':
        hackerStore.addLine('  PID  USER    CMD', 'info');
        hackerStore.addLine('    1  root    /sbin/init', 'output');
        hackerStore.addLine('  137  root    sshd: root@pts/0', 'output');
        hackerStore.addLine(' 1337  root    mining_daemon --pool', 'success');
        hackerStore.addLine(' 1338  root    rig_controller', 'output');
        hackerStore.addLine(' 1339  root    cooling_monitor', 'output');
        hackerStore.addLine(` 1340  root    firewall_lvl${defenseLevel}`, defenseLevel >= 4 ? 'warning' : 'output');
        break;

      case 'ifconfig':
        hackerStore.addLine('eth0:', 'info');
        hackerStore.addLine(`  inet ${ip}  netmask 255.255.255.0`, 'output');
        hackerStore.addLine(`  ether ${Math.abs(h).toString(16).slice(0, 2)}:${Math.abs(h >> 4).toString(16).slice(0, 2)}:${Math.abs(h >> 8).toString(16).slice(0, 2)}:aa:bb:cc`, 'output');
        hackerStore.addLine(`  RX packets: ${Math.abs(h % 999999)}  TX packets: ${Math.abs((h >> 4) % 999999)}`, 'output');
        break;

      case 'siphon':
        if (sshSiphoned.value) {
          hackerStore.addLine('Already siphoned from this session. Disconnect.', 'warning');
          break;
        }
        {
          const stolen = Math.floor(gcBalance * (0.03 + Math.random() * 0.05));
          sshSiphoned.value = true;
          hackerStore.addLine('', 'output');
          hackerStore.addLine('Accessing wallet daemon...', 'info');
          hackerStore.addLine('Injecting transaction...', 'info');
          hackerStore.addLine('', 'output');
          hackerStore.addLine('═══════════════════════════════════', 'success');
          hackerStore.addLine('  SIPHON COMPLETE', 'success');
          hackerStore.addLine('═══════════════════════════════════', 'success');
          hackerStore.addLine(`  Stolen: ${stolen.toLocaleString()} GC`, 'success');
          hackerStore.addLine(`  Remaining: ${(gcBalance - stolen).toLocaleString()} GC`, 'output');
          hackerStore.addLine('', 'output');
          hackerStore.addLine('Disconnect before they notice.', 'warning');
          hackerStore.addLine('', 'output');
          playSound('hack_success' as any);
        }
        break;

      case 'exit':
      case 'disconnect':
      case 'quit':
        hackerStore.addLine('Connection closed.', 'info');
        hackerStore.addLine(`Disconnected from ${target}.`, 'output');
        sshActive.value = false;
        sshTarget.value = '';
        sshPrompt.value = '';
        sshSiphoned.value = false;
        break;

      default:
        hackerStore.addLine(`bash: ${cmd}: command not found`, 'error');
    }
  }

  // ─── Bruteforce ───
  let bruteforceInterval: number | null = null;

  function cmdBruteforce(args: string[]) {
    if (args.length < 3) {
      hackerStore.addLine('Usage: bruteforce <ip|username> <dict|brute> <rig_id>', 'warning');
      return;
    }

    const rawTarget = args[0];
    const mode = args[1].toLowerCase();
    const rigIndex = parseInt(args[2]) - 1;
    const username = resolveTarget(rawTarget);
    const player = authStore.player;
    if (!player) { hackerStore.addLine('Not authenticated.', 'error'); return; }

    if (username.toLowerCase() === player.username.toLowerCase()) {
      hackerStore.addLine('Cannot bruteforce yourself.', 'error');
      return;
    }

    if (mode !== 'dict' && mode !== 'brute') {
      hackerStore.addLine('Mode must be "dict" (dictionary) or "brute" (raw).', 'error');
      return;
    }

    // Validate rig
    const rig = miningStore.rigs[rigIndex];
    if (!rig) {
      hackerStore.addLine(`Rig #${args[2]} not found. Use "rigs" to list available rigs.`, 'error');
      return;
    }

    if (rig.is_active) {
      hackerStore.addLine(`Rig #${args[2]} (${rig.rig.name}) is currently mining.`, 'error');
      hackerStore.addLine('Turn it off first: rig off ' + args[2], 'warning');
      return;
    }

    // Use this rig's base hashrate with condition penalty
    const condition = rig.condition ?? 100;
    const conditionPenalty = condition >= 80 ? 1.0 : 0.3 + (condition / 80) * 0.7;
    const rigHash = rig.rig.hashrate * conditionPenalty;
    const ip = generateFakeIP(username);
    ipToUsername.value[ip] = username;

    // Speed based on rig hashrate: more TH/s = more attempts/sec
    const baseSpeed = mode === 'dict' ? 800 : 200;
    const attemptsPerTick = Math.max(1, Math.floor(baseSpeed * rigHash));
    const tickMs = 400;

    // Difficulty based on username hash
    let h = 0;
    for (let i = 0; i < username.length; i++) h = ((h << 5) - h) + username.charCodeAt(i);
    const defenseLevel = (Math.abs(h) % 5) + 1;
    const totalAttempts = mode === 'dict'
      ? Math.floor((5000 + defenseLevel * 3000) * (0.8 + Math.random() * 0.4))
      : Math.floor((20000 + defenseLevel * 15000) * (0.8 + Math.random() * 0.4));

    hackerStore.addLine('', 'output');
    hackerStore.addLine(`═══ BRUTEFORCE ATTACK ═══`, 'header');
    hackerStore.addLine('', 'output');
    hackerStore.addLine(`Target:    ${ip} (${username})`, 'output');
    hackerStore.addLine(`Mode:      ${mode === 'dict' ? 'Dictionary (rockyou.txt)' : 'Raw bruteforce (a-zA-Z0-9)'}`, 'output');
    hackerStore.addLine(`Rig:       #${args[2]} ${rig.rig.name} (${rigHash.toFixed(1)} TH/s)`, 'info');
    hackerStore.addLine(`Condition: ${Math.round(condition)}%${condition < 80 ? ' [DEGRADED]' : ''}`, condition < 80 ? 'warning' : 'output');
    hackerStore.addLine(`Speed:     ~${attemptsPerTick.toLocaleString()} attempts/s`, 'info');
    hackerStore.addLine(`Defense:   ${'█'.repeat(defenseLevel)}${'░'.repeat(5 - defenseLevel)} (${defenseLevel}/5)`, defenseLevel >= 4 ? 'warning' : 'output');
    hackerStore.addLine('', 'output');
    hackerStore.addLine(`Powering on ${rig.rig.name} for cracking...`, 'info');
    hackerStore.addLine('Starting attack...', 'info');
    hackerStore.addLine('', 'output');

    // Dictionary words for display
    const dictWords = [
      'password', '123456', 'admin', 'letmein', 'welcome', 'monkey', 'dragon',
      'master', 'qwerty', 'login', 'princess', 'abc123', 'football', 'shadow',
      'iloveyou', 'trustno1', 'sunshine', 'batman', 'access', 'hello',
      'charlie', 'donald', 'hockey', 'ranger', 'buster', 'thomas', 'robert',
      'soccer', 'killer', 'george', 'andrea', 'joshua', 'matrix', 'hunter',
      'mining2024', 'crypto!', 'bl0ckch4in', 'h4shr4te', 'n0d3', 'w4ll3t',
    ];

    // Brute charset display
    const bruteChars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%';

    let currentAttempts = 0;
    let lastLineId: number | null = null;

    // Clean up previous bruteforce if running
    if (bruteforceInterval) {
      clearInterval(bruteforceInterval);
      bruteforceInterval = null;
    }

    bruteforceInterval = window.setInterval(() => {
      currentAttempts += attemptsPerTick;
      const progress = Math.min(currentAttempts / totalAttempts, 1);
      const percent = (progress * 100).toFixed(1);

      // Generate fake attempt display
      let attemptText: string;
      if (mode === 'dict') {
        const word = dictWords[Math.floor(Math.random() * dictWords.length)];
        const variants = [word, word + '123', word + '!', word.toUpperCase(), word + '2024', '_' + word];
        attemptText = variants[Math.floor(Math.random() * variants.length)];
      } else {
        const len = 6 + Math.floor(Math.random() * 6);
        attemptText = Array.from({ length: len }, () => bruteChars[Math.floor(Math.random() * bruteChars.length)]).join('');
      }

      // Progress bar
      const barLen = 30;
      const filled = Math.floor(progress * barLen);
      const bar = '█'.repeat(filled) + '░'.repeat(barLen - filled);

      // Remove last progress line and add new one
      if (lastLineId !== null) {
        const idx = hackerStore.outputLines.findIndex(l => l.id === lastLineId);
        if (idx !== -1) hackerStore.outputLines.splice(idx, 1);
      }

      const progressType: OutputLine['type'] = progress >= 0.9 ? 'success' : progress >= 0.5 ? 'warning' : 'info';
      hackerStore.addLine(
        `[${bar}] ${percent}% | ${currentAttempts.toLocaleString()}/${totalAttempts.toLocaleString()} | ${attemptText}`,
        progressType,
      );
      lastLineId = hackerStore.outputLines[hackerStore.outputLines.length - 1].id;

      // Done
      if (progress >= 1) {
        if (bruteforceInterval) {
          clearInterval(bruteforceInterval);
          bruteforceInterval = null;
        }

        // Generate a "cracked" password
        const crackedPasswords = [
          `${username.toLowerCase()}123`, 'mining2024!', 'crypto_' + username.slice(0, 4),
          'P@ssw0rd!', username.toLowerCase() + '!', 'admin' + (Math.floor(Math.random() * 9999)),
          'bl0ckl0rd$', 'h4ck3r' + Math.floor(Math.random() * 99),
        ];
        const crackedPw = crackedPasswords[Math.floor(Math.random() * crackedPasswords.length)];

        // Store cracked password in $key variable
        terminalVars.value['key'] = crackedPw;

        hackerStore.addLine('', 'output');
        hackerStore.addLine('═══════════════════════════════════', 'success');
        hackerStore.addLine('  PASSWORD CRACKED', 'success');
        hackerStore.addLine('═══════════════════════════════════', 'success');
        hackerStore.addLine('', 'output');
        hackerStore.addLine(`  User:     ${username}`, 'output');
        hackerStore.addLine(`  Password: ${crackedPw}`, 'success');
        hackerStore.addLine(`  Attempts: ${totalAttempts.toLocaleString()}`, 'output');
        hackerStore.addLine(`  Rig:      #${args[2]} ${rig.rig.name} (${rigHash.toFixed(1)} TH/s)`, 'info');
        hackerStore.addLine('', 'output');
        hackerStore.addLine('Password stored in $key. Use: ssh <host> $key', 'info');
        hackerStore.addLine(`Powering off ${rig.rig.name}...`, 'info');
        hackerStore.addLine('', 'output');

        playSound('hack_success' as any);
      }
    }, tickMs);
  }

  function cmdHack(args: string[]) {
    if (args.length === 0) {
      hackerStore.addLine('Usage: hack <ip|username|random>', 'warning');
      hackerStore.addLine('       spy <ip|username>       (spy mode)', 'warning');
      hackerStore.addLine('       sabotage <ip|username>  (sabotage mode)', 'warning');
      return;
    }

    let mode: HackMode = 'steal';
    let rawTarget = args[0];

    if (['steal', 'spy', 'sabotage'].includes(args[0])) {
      mode = args[0] as HackMode;
      rawTarget = args[1] || '';
    }

    if (!rawTarget) {
      hackerStore.addLine(`Usage: ${mode === 'steal' ? 'hack' : mode} <ip|username|random>`, 'warning');
      return;
    }

    // Resolve IP to username if needed
    const targetName = rawTarget === 'random' ? 'random' : resolveTarget(rawTarget);

    const player = authStore.player;
    if (!player) { hackerStore.addLine('Not authenticated.', 'error'); return; }

    const costs: Record<HackMode, { energy: number; internet: number }> = {
      steal: { energy: 30, internet: 10 },
      spy: { energy: 15, internet: 5 },
      sabotage: { energy: 25, internet: 10 },
    };
    const cost = costs[mode];
    if (player.energy < cost.energy) {
      hackerStore.addLine(`Insufficient energy. Need ${cost.energy}, have ${Math.round(player.energy)}.`, 'error');
      return;
    }
    if (player.internet < cost.internet) {
      hackerStore.addLine(`Insufficient internet. Need ${cost.internet}, have ${Math.round(player.internet)}.`, 'error');
      return;
    }
    if (targetName.toLowerCase() === player.username.toLowerCase()) {
      hackerStore.addLine('Cannot hack yourself. That would be recursive.', 'error');
      return;
    }

    // Store target info
    const displayTarget = targetName === 'random' ? 'RANDOM_TARGET' : targetName;
    hackerStore.isHacking = true;
    hackerStore.selectedMode = mode;
    hackerStore.selectedTarget = { id: 'pending', username: displayTarget, reputation: 0, defense_level: 1 };

    // Start hack game
    startHackGame(mode, displayTarget);
  }

  function startHackGame(mode: HackMode, targetUsername: string) {
    hackStages.value = getStages(mode, targetUsername);
    hackCurrentStage.value = 0;
    hackTimer.value = 30;
    hackScore.value = 0;
    hackStartTime.value = Date.now();
    hackGameActive.value = true;
    hackShowingOutput.value = false;
    hackWaitingInput.value = false;
    hackCurrentOptions.value = [];

    // Hack prompt
    hackPrompt.value = `hack@${targetUsername}:~#`;

    // Start timer
    hackTimerInterval = window.setInterval(() => {
      hackTimer.value--;
      if (hackTimer.value <= 0) {
        endHackGame(false);
      }
    }, 1000);

    playSound('hack_start' as any);

    // If all stages already done (e.g. spy has only 3 stages, skipped 1 = 2 left)
    if (hackCurrentStage.value >= hackStages.value.length) {
      endHackGame(true);
    } else {
      showStageOutput();
    }
  }

  function showStageOutput() {
    const stage = hackStages.value[hackCurrentStage.value];
    if (!stage) return;

    hackShowingOutput.value = true;
    hackWaitingInput.value = false;

    hackerStore.addLine('', 'output');
    hackerStore.addLine(`${stage.prompt}  [${hackCurrentStage.value + 1}/${hackStages.value.length}] ⏱ ${hackTimer.value}s`, 'header');

    let outputIdx = 0;
    hackOutputInterval = window.setInterval(() => {
      if (outputIdx < stage.output.length) {
        hackerStore.addLine(stage.output[outputIdx], 'output');
        outputIdx++;
      } else {
        if (hackOutputInterval) { clearInterval(hackOutputInterval); hackOutputInterval = null; }
        hackShowingOutput.value = false;
        hackWaitingInput.value = true;
        hackCurrentOptions.value = stage.options;

        // Print options as terminal text
        hackerStore.addLine('', 'output');
        hackerStore.addLine('┌─ AVAILABLE COMMANDS ─────────────────────────┐', 'info');
        stage.options.forEach((opt) => {
          hackerStore.addLine(`  ${opt.label}`, 'command');
        });
        hackerStore.addLine('└──────────────────────────────────────────────┘', 'info');
        hackerStore.addLine('', 'output');
      }
    }, 80);
  }

  function handleHackInput(input: string) {
    if (hackShowingOutput.value || !hackWaitingInput.value) {
      hackerStore.addLine('Wait for options to appear...', 'warning');
      return;
    }

    const trimmed = input.trim();
    let selected: StageOption | null = null;

    // Match by command text (partial or full)
    selected = hackCurrentOptions.value.find(o =>
      o.command.toLowerCase() === trimmed.toLowerCase() ||
      o.label.toLowerCase() === trimmed.toLowerCase() ||
      o.label.toLowerCase().startsWith(trimmed.toLowerCase())
    ) || null;

    if (!selected) {
      hackerStore.addLine(`Unknown command. Read the options carefully.`, 'error');
      return;
    }

    hackWaitingInput.value = false;

    if (selected.correct) {
      hackScore.value++;
      hackerStore.addLine(`> ${selected.command}`, 'success');
      hackerStore.addLine('[OK] ACCESS GRANTED - Stage cleared', 'success');
      playSound('hack_stage_clear' as any);

      setTimeout(() => {
        hackCurrentStage.value++;
        if (hackCurrentStage.value >= hackStages.value.length) {
          endHackGame(true);
        } else {
          showStageOutput();
        }
      }, 600);
    } else {
      hackTimer.value = Math.max(0, hackTimer.value - 5);
      hackerStore.addLine(`> ${selected.command}`, 'error');
      hackerStore.addLine('[ALERT] INTRUSION DETECTED - Countermeasures active (-5s)', 'error');
      playSound('hack_detected' as any);

      setTimeout(() => {
        hackWaitingInput.value = true;
        // Re-print options
        hackerStore.addLine('', 'output');
        hackerStore.addLine('┌─ AVAILABLE COMMANDS ─────────────────────────┐', 'info');
        hackCurrentOptions.value.forEach((opt) => {
          hackerStore.addLine(`  ${opt.label}`, 'command');
        });
        hackerStore.addLine('└──────────────────────────────────────────────┘', 'info');
        hackerStore.addLine('', 'output');
      }, 500);
    }
  }

  function endHackGame(success: boolean) {
    hackGameActive.value = false;
    hackWaitingInput.value = false;
    hackShowingOutput.value = false;

    if (hackTimerInterval) { clearInterval(hackTimerInterval); hackTimerInterval = null; }
    if (hackOutputInterval) { clearInterval(hackOutputInterval); hackOutputInterval = null; }

    const elapsed = Date.now() - hackStartTime.value;
    const mode = hackerStore.selectedMode;

    if (success) {
      hackerStore.addLine('', 'output');
      hackerStore.addLine('═══════════════════════════════════', 'success');
      hackerStore.addLine('  HACK SUCCESSFUL', 'success');
      hackerStore.addLine('═══════════════════════════════════', 'success');
      playSound('hack_success' as any);

      if (mode === 'steal') {
        const stolen = Math.floor(Math.random() * 500 + 100);
        hackerStore.addLine(`Siphoned ${stolen} GC from target wallet.`, 'success');
      } else if (mode === 'spy') {
        hackerStore.addLine('Intel acquired. Data stored.', 'success');
      } else {
        hackerStore.addLine('Virus injected. Target mining speed reduced.', 'success');
      }
      hackerStore.addLine(`Time: ${(elapsed / 1000).toFixed(1)}s | Score: ${hackScore.value}/${hackStages.value.length}`, 'info');
    } else {
      hackerStore.addLine('', 'output');
      hackerStore.addLine('═══════════════════════════════════', 'error');
      hackerStore.addLine('  CONNECTION TERMINATED - DETECTED', 'error');
      hackerStore.addLine('═══════════════════════════════════', 'error');
      playSound('hack_fail' as any);

      hackerStore.addLine('Hack failed. Security countermeasures triggered.', 'error');
      const penalty = mode === 'steal' ? 20 : mode === 'spy' ? 10 : 15;
      hackerStore.addLine(`Energy lost: -${penalty}`, 'warning');
    }

    hackerStore.addLine('', 'output');
    hackerStore.isHacking = false;
    hackerStore.selectedMode = null;
    hackerStore.selectedTarget = null;
    hackPrompt.value = '';
  }

  function cleanupHack() {
    if (hackTimerInterval) { clearInterval(hackTimerInterval); hackTimerInterval = null; }
    if (hackOutputInterval) { clearInterval(hackOutputInterval); hackOutputInterval = null; }
    if (bruteforceInterval) { clearInterval(bruteforceInterval); bruteforceInterval = null; }
    hackGameActive.value = false;
    hackWaitingInput.value = false;
    hackShowingOutput.value = false;
  }

  // ─── Market ───
  async function cmdMarket(args: string[]) {
    await marketStore.loadCatalogs();
    const category = args[0]?.toLowerCase();
    if (!category) {
      hackerStore.addLine('', 'output');
      hackerStore.addLine('═══ MARKET ═══', 'header');
      hackerStore.addLine('', 'output');
      hackerStore.addLine('  CATEGORIES:', 'info');
      hackerStore.addLine('    market rigs        Mining rigs', 'output');
      hackerStore.addLine('    market cooling      Cooling systems', 'output');
      hackerStore.addLine('    market energy       Energy cards', 'output');
      hackerStore.addLine('    market internet     Internet cards', 'output');
      hackerStore.addLine('    market boosts       Boost items', 'output');
      hackerStore.addLine('    market components   Cooling components', 'output');
      hackerStore.addLine('    market exp          EXP packs', 'output');
      hackerStore.addLine('', 'output');
      return;
    }
    const player = authStore.player;
    lastListing.value = [];
    const currLabel = (c: string) => c === 'crypto' ? '💎' : c === 'ron' ? 'RON' : 'GC';

    if (category === 'rigs') {
      const items = marketStore.rigsForSale;
      if (items.length === 0) { hackerStore.addLine('No rigs available.', 'warning'); return; }
      hackerStore.addLine('', 'output');
      hackerStore.addLine('═══ MARKET: RIGS ═══', 'header');
      hackerStore.addLine('', 'output');
      hackerStore.addLine(padRight('#', 4) + padRight('NAME', 22) + padRight('HASH', 10) + padRight('POWER', 8) + padRight('PRICE', 14) + 'OWNED', 'info');
      hackerStore.addLine('─'.repeat(68), 'output');
      items.forEach((item, idx) => {
        const owned = marketStore.getRigOwned(item.id).total;
        const line = padRight(`${idx + 1}`, 4) + padRight(item.name, 22) + padRight(`${item.hashrate} TH/s`, 10) + padRight(`${item.power_consumption}⚡`, 8) + padRight(`${formatNum(item.base_price)} ${currLabel(item.currency)}`, 14) + `${owned}`;
        hackerStore.addLine(line, owned > 0 ? 'success' : 'output');
        lastListing.value.push({ id: item.id, name: item.name, price: item.base_price, currency: item.currency, category: 'rig' });
      });
    } else if (category === 'cooling') {
      const items = marketStore.coolingItems;
      if (items.length === 0) { hackerStore.addLine('No cooling items available.', 'warning'); return; }
      hackerStore.addLine('', 'output');
      hackerStore.addLine('═══ MARKET: COOLING ═══', 'header');
      hackerStore.addLine('', 'output');
      hackerStore.addLine(padRight('#', 4) + padRight('NAME', 22) + padRight('COOL', 8) + padRight('ENERGY', 8) + padRight('PRICE', 14) + 'OWNED', 'info');
      hackerStore.addLine('─'.repeat(66), 'output');
      items.forEach((item, idx) => {
        const owned = marketStore.getCoolingOwned(item.id).total;
        const line = padRight(`${idx + 1}`, 4) + padRight(item.name, 22) + padRight(`${item.cooling_power}°`, 8) + padRight(`${item.energy_cost}⚡`, 8) + padRight(`${formatNum(item.base_price)} GC`, 14) + `${owned}`;
        hackerStore.addLine(line, owned > 0 ? 'success' : 'output');
        lastListing.value.push({ id: item.id, name: item.name, price: item.base_price, currency: 'gamecoin', category: 'cooling' });
      });
    } else if (category === 'energy') {
      const items = marketStore.energyCards;
      if (items.length === 0) { hackerStore.addLine('No energy cards available.', 'warning'); return; }
      hackerStore.addLine('', 'output');
      hackerStore.addLine('═══ MARKET: ENERGY CARDS ═══', 'header');
      hackerStore.addLine('', 'output');
      hackerStore.addLine(padRight('#', 4) + padRight('NAME', 24) + padRight('AMOUNT', 10) + padRight('PRICE', 14) + 'OWNED', 'info');
      hackerStore.addLine('─'.repeat(62), 'output');
      items.forEach((item, idx) => {
        const owned = marketStore.getCardOwned(item.id);
        const line = padRight(`${idx + 1}`, 4) + padRight(item.name, 24) + padRight(`+${item.amount}⚡`, 10) + padRight(`${formatNum(item.base_price)} ${currLabel(item.currency)}`, 14) + `${owned}`;
        hackerStore.addLine(line, owned > 0 ? 'success' : 'output');
        lastListing.value.push({ id: item.id, name: item.name, price: item.base_price, currency: item.currency, category: 'card' });
      });
    } else if (category === 'internet') {
      const items = marketStore.internetCards;
      if (items.length === 0) { hackerStore.addLine('No internet cards available.', 'warning'); return; }
      hackerStore.addLine('', 'output');
      hackerStore.addLine('═══ MARKET: INTERNET CARDS ═══', 'header');
      hackerStore.addLine('', 'output');
      hackerStore.addLine(padRight('#', 4) + padRight('NAME', 24) + padRight('AMOUNT', 10) + padRight('PRICE', 14) + 'OWNED', 'info');
      hackerStore.addLine('─'.repeat(62), 'output');
      items.forEach((item, idx) => {
        const owned = marketStore.getCardOwned(item.id);
        const line = padRight(`${idx + 1}`, 4) + padRight(item.name, 24) + padRight(`+${item.amount}📡`, 10) + padRight(`${formatNum(item.base_price)} ${currLabel(item.currency)}`, 14) + `${owned}`;
        hackerStore.addLine(line, owned > 0 ? 'success' : 'output');
        lastListing.value.push({ id: item.id, name: item.name, price: item.base_price, currency: item.currency, category: 'card' });
      });
    } else if (category === 'boosts') {
      const items = marketStore.boostItems;
      if (items.length === 0) { hackerStore.addLine('No boosts available.', 'warning'); return; }
      hackerStore.addLine('', 'output');
      hackerStore.addLine('═══ MARKET: BOOSTS ═══', 'header');
      hackerStore.addLine('', 'output');
      hackerStore.addLine(padRight('#', 4) + padRight('NAME', 22) + padRight('EFFECT', 10) + padRight('DURATION', 10) + padRight('PRICE', 14) + 'OWNED', 'info');
      hackerStore.addLine('─'.repeat(70), 'output');
      items.forEach((item, idx) => {
        const owned = marketStore.getBoostOwned(item.id);
        const dur = item.duration_minutes >= 60 ? `${(item.duration_minutes / 60).toFixed(0)}h` : `${item.duration_minutes}m`;
        const line = padRight(`${idx + 1}`, 4) + padRight(item.name, 22) + padRight(`+${item.effect_value}%`, 10) + padRight(dur, 10) + padRight(`${formatNum(item.base_price)} ${currLabel(item.currency)}`, 14) + `${owned}`;
        hackerStore.addLine(line, owned > 0 ? 'success' : 'output');
        lastListing.value.push({ id: item.id, name: item.name, price: item.base_price, currency: item.currency, category: 'boost' });
      });
    } else if (category === 'components' || category === 'comp') {
      const items = marketStore.coolingComponents;
      if (items.length === 0) { hackerStore.addLine('No components available.', 'warning'); return; }
      hackerStore.addLine('', 'output');
      hackerStore.addLine('═══ MARKET: COOLING COMPONENTS ═══', 'header');
      hackerStore.addLine('', 'output');
      hackerStore.addLine(padRight('#', 4) + padRight('NAME', 22) + padRight('COOL', 12) + padRight('PRICE', 14) + 'OWNED', 'info');
      hackerStore.addLine('─'.repeat(60), 'output');
      items.forEach((item, idx) => {
        const owned = marketStore.getComponentOwned(item.id);
        const line = padRight(`${idx + 1}`, 4) + padRight(item.name, 22) + padRight(`${item.cooling_power_min}-${item.cooling_power_max}°`, 12) + padRight(`${formatNum(item.base_price)} GC`, 14) + `${owned}`;
        hackerStore.addLine(line, owned > 0 ? 'success' : 'output');
        lastListing.value.push({ id: item.id, name: item.name, price: item.base_price, currency: 'gamecoin', category: 'component' });
      });
    } else if (category === 'exp' || category === 'xp') {
      const items = marketStore.expPacks;
      if (items.length === 0) { hackerStore.addLine('No EXP packs available.', 'warning'); return; }
      hackerStore.addLine('', 'output');
      hackerStore.addLine('═══ MARKET: EXP PACKS ═══', 'header');
      hackerStore.addLine('', 'output');
      hackerStore.addLine(padRight('#', 4) + padRight('NAME', 24) + padRight('XP', 10) + padRight('PRICE', 14) + 'OWNED', 'info');
      hackerStore.addLine('─'.repeat(62), 'output');
      items.forEach((item, idx) => {
        const owned = marketStore.getExpPackOwned(item.id);
        const line = padRight(`${idx + 1}`, 4) + padRight(item.name, 24) + padRight(`+${item.xp_amount}`, 10) + padRight(`${formatNum(item.base_price)} GC`, 14) + `${owned}`;
        hackerStore.addLine(line, owned > 0 ? 'success' : 'output');
        lastListing.value.push({ id: item.id, name: item.name, price: item.base_price, currency: 'gamecoin', category: 'exp' });
      });
    } else {
      hackerStore.addLine(`Unknown category: ${category}`, 'error');
      hackerStore.addLine('Type "market" to see available categories.', 'info');
      return;
    }
    hackerStore.addLine('', 'output');
    if (player) {
      hackerStore.addLine(`  Balance: ${formatNum(player.gamecoin_balance)} GC | ${formatNum(player.crypto_balance, 8)} 💎 | ${formatNum(player.ron_balance, 4)} RON`, 'info');
    }
    hackerStore.addLine('', 'output');
  }

  async function cmdBuy(args: string[]) {
    if (args.length === 0) { hackerStore.addLine('Usage: buy <#> (number from last market listing)', 'warning'); return; }
    const num = parseInt(args[0]);
    if (isNaN(num) || num < 1) { hackerStore.addLine('Invalid item number.', 'error'); return; }
    if (lastListing.value.length === 0) { hackerStore.addLine('No listing loaded. Use "market <category>" first.', 'warning'); return; }
    const item = lastListing.value[num - 1];
    if (!item) { hackerStore.addLine(`Item #${num} not found. Range: 1-${lastListing.value.length}`, 'error'); return; }
    hackerStore.addLine(`Purchasing ${item.name}...`, 'info');
    let result: { success: boolean; error?: string };
    switch (item.category) {
      case 'rig': result = await marketStore.buyRig(item.id); break;
      case 'cooling': result = await marketStore.buyCooling(item.id); break;
      case 'card': result = await marketStore.buyCard(item.id); break;
      case 'boost': result = await marketStore.buyBoost(item.id); break;
      case 'component': result = await marketStore.buyCoolingComponent(item.id); break;
      case 'exp': result = await marketStore.buyExpPack(item.id); break;
      default: hackerStore.addLine('Unknown item category.', 'error'); return;
    }
    if (result.success) {
      hackerStore.addLine(`[OK] ${item.name} purchased!`, 'success');
      await authStore.fetchPlayer();
      if (authStore.player) {
        hackerStore.addLine(`  Balance: ${formatNum(authStore.player.gamecoin_balance)} GC | ${formatNum(authStore.player.crypto_balance, 8)} 💎`, 'info');
      }
    } else {
      hackerStore.addLine(`[FAIL] ${result.error || 'Purchase failed'}`, 'error');
    }
  }

  // ─── Info commands ───
  function cmdWhoami() {
    const player = authStore.player;
    if (!player) { hackerStore.addLine('anonymous (not authenticated)', 'warning'); return; }
    hackerStore.addLine(`${player.username} [${player.email}]`, 'success');
  }

  function cmdNeofetch() {
    const player = authStore.player;
    hackerStore.addLine('', 'output');
    hackerStore.addLine('  ██╗      ███╗   ███╗', 'success');
    hackerStore.addLine('  ██║      ████╗ ████║', 'success');
    hackerStore.addLine('  ██║      ██╔████╔██║   LootMine Terminal v1.0', 'info');
    hackerStore.addLine('  ██║      ██║╚██╔╝██║   ─────────────────────', 'output');
    hackerStore.addLine('  ███████╗ ██║ ╚═╝ ██║   User: ' + (player?.username || 'anonymous'), 'output');
    hackerStore.addLine('  ╚══════╝ ╚═╝     ╚═╝   Rigs: ' + (miningStore.rigs.length || 0), 'output');
    hackerStore.addLine('                          Hash: ' + miningStore.effectiveHashrate.toFixed(2) + ' TH/s', 'output');
    hackerStore.addLine('                          GC:   ' + formatNum(player?.gamecoin_balance || 0), 'output');
    hackerStore.addLine('', 'output');
  }

  function cmdUnknown(cmd: string) {
    hackerStore.addLine(`Command not found: ${cmd}`, 'error');
    hackerStore.addLine('Type "help" for available commands.', 'info');
  }

  // ─── Utilities ───
  function padRight(str: string, len: number): string {
    return str.padEnd(len);
  }

  function formatNum(n: number, decimals: number = 2): string {
    if (n >= 1000000) return (n / 1000000).toFixed(2) + 'M';
    if (n >= 1000) return (n / 1000).toFixed(2) + 'K';
    return n.toFixed(decimals);
  }

  // Cleanup on unmount
  onUnmounted(() => {
    cleanupHack();
  });

  return {
    inputValue,
    isProcessing,
    showWelcome,
    executeCommand,
    cleanupHack,
    // Hack state (for UI: prompt, timer)
    hackGameActive,
    hackTimer,
    hackCurrentStage,
    hackStages,
    hackScore,
    hackPrompt,
    // Script state (for UI: recording indicator, prompt change)
    isRecording,
    recordingName,
    isRunningScript,
    // SSH state (for UI: prompt change)
    sshActive,
    sshPrompt,
  };
}
