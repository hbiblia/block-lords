// =====================================================
// BLOCK LORDS - Sound Manager
// Sistema minimalista de sonidos del juego
// =====================================================

// Importar el audio como asset de Vite (debe estar al inicio)
import computerFanLoop from '@/assets/ComputerFanLoop.mp3';

export type SoundType =
  | 'click'
  | 'success'
  | 'error'
  | 'purchase'
  | 'reward'
  | 'block_mined'
  | 'mission_complete'
  | 'warning'
  | 'notification'
  | 'collect';

// Configuración de sonidos
interface SoundConfig {
  frequency: number;
  duration: number;
  type: OscillatorType;
  volume: number;
  ramp?: boolean;
}

// Sonidos sintetizados (minimalistas, sin archivos externos)
const SOUND_CONFIGS: Record<SoundType, SoundConfig[]> = {
  click: [
    { frequency: 800, duration: 0.05, type: 'sine', volume: 0.15 }
  ],
  success: [
    { frequency: 523, duration: 0.1, type: 'sine', volume: 0.2 },
    { frequency: 659, duration: 0.1, type: 'sine', volume: 0.2 },
    { frequency: 784, duration: 0.15, type: 'sine', volume: 0.2 }
  ],
  error: [
    { frequency: 200, duration: 0.15, type: 'square', volume: 0.15 },
    { frequency: 150, duration: 0.2, type: 'square', volume: 0.1 }
  ],
  purchase: [
    { frequency: 440, duration: 0.08, type: 'sine', volume: 0.2 },
    { frequency: 554, duration: 0.08, type: 'sine', volume: 0.2 },
    { frequency: 659, duration: 0.12, type: 'sine', volume: 0.25 }
  ],
  reward: [
    { frequency: 587, duration: 0.1, type: 'sine', volume: 0.2 },
    { frequency: 698, duration: 0.1, type: 'sine', volume: 0.2 },
    { frequency: 880, duration: 0.15, type: 'sine', volume: 0.25 },
    { frequency: 1047, duration: 0.2, type: 'sine', volume: 0.2, ramp: true }
  ],
  block_mined: [
    { frequency: 262, duration: 0.08, type: 'triangle', volume: 0.2 },
    { frequency: 330, duration: 0.08, type: 'triangle', volume: 0.2 },
    { frequency: 392, duration: 0.08, type: 'triangle', volume: 0.2 },
    { frequency: 523, duration: 0.15, type: 'triangle', volume: 0.25 }
  ],
  mission_complete: [
    { frequency: 392, duration: 0.1, type: 'sine', volume: 0.2 },
    { frequency: 523, duration: 0.1, type: 'sine', volume: 0.2 },
    { frequency: 659, duration: 0.1, type: 'sine', volume: 0.2 },
    { frequency: 784, duration: 0.2, type: 'sine', volume: 0.25 }
  ],
  warning: [
    { frequency: 440, duration: 0.15, type: 'sawtooth', volume: 0.12 },
    { frequency: 440, duration: 0.15, type: 'sawtooth', volume: 0.12 }
  ],
  notification: [
    { frequency: 880, duration: 0.08, type: 'sine', volume: 0.15 },
    { frequency: 1100, duration: 0.12, type: 'sine', volume: 0.18 }
  ],
  collect: [
    { frequency: 600, duration: 0.06, type: 'sine', volume: 0.18 },
    { frequency: 800, duration: 0.08, type: 'sine', volume: 0.2 },
    { frequency: 1000, duration: 0.1, type: 'sine', volume: 0.15, ramp: true }
  ]
};

class SoundManager {
  private audioContext: AudioContext | null = null;
  private enabled: boolean = true;
  private volume: number = 0.5;
  private initialized: boolean = false;

  constructor() {
    this.loadSettings();
  }

  private loadSettings(): void {
    try {
      const saved = localStorage.getItem('blockLords_soundSettings');
      if (saved) {
        const settings = JSON.parse(saved);
        this.enabled = settings.enabled ?? true;
        this.volume = settings.volume ?? 0.5;
      }
    } catch {
      // Use defaults
    }
  }

  private saveSettings(): void {
    try {
      localStorage.setItem('blockLords_soundSettings', JSON.stringify({
        enabled: this.enabled,
        volume: this.volume
      }));
    } catch {
      // Ignore storage errors
    }
  }

  private getAudioContext(): AudioContext | null {
    if (!this.audioContext) {
      try {
        this.audioContext = new (window.AudioContext || (window as any).webkitAudioContext)();
      } catch {
        console.warn('Web Audio API not supported');
        return null;
      }
    }
    return this.audioContext;
  }

  // Inicializar después de interacción del usuario (requerido por navegadores)
  public async init(): Promise<void> {
    if (this.initialized) return;

    const ctx = this.getAudioContext();
    if (ctx && ctx.state === 'suspended') {
      await ctx.resume();
    }
    this.initialized = true;
  }

  public play(sound: SoundType): void {
    if (!this.enabled) return;

    const ctx = this.getAudioContext();
    if (!ctx) return;

    // Asegurar que el contexto esté activo
    if (ctx.state === 'suspended') {
      ctx.resume();
    }

    const configs = SOUND_CONFIGS[sound];
    if (!configs) return;

    let startTime = ctx.currentTime;

    for (const config of configs) {
      this.playTone(ctx, config, startTime);
      startTime += config.duration;
    }
  }

  private playTone(ctx: AudioContext, config: SoundConfig, startTime: number): void {
    const oscillator = ctx.createOscillator();
    const gainNode = ctx.createGain();

    oscillator.type = config.type;
    oscillator.frequency.setValueAtTime(config.frequency, startTime);

    const effectiveVolume = config.volume * this.volume;
    gainNode.gain.setValueAtTime(effectiveVolume, startTime);

    if (config.ramp) {
      gainNode.gain.exponentialRampToValueAtTime(0.01, startTime + config.duration);
    } else {
      gainNode.gain.setValueAtTime(effectiveVolume, startTime + config.duration * 0.8);
      gainNode.gain.exponentialRampToValueAtTime(0.01, startTime + config.duration);
    }

    oscillator.connect(gainNode);
    gainNode.connect(ctx.destination);

    oscillator.start(startTime);
    oscillator.stop(startTime + config.duration + 0.05);
  }

  // Getters y setters
  public isEnabled(): boolean {
    return this.enabled;
  }

  public setEnabled(enabled: boolean): void {
    this.enabled = enabled;
    this.saveSettings();
  }

  public toggleEnabled(): boolean {
    this.enabled = !this.enabled;
    this.saveSettings();
    if (this.enabled) {
      this.play('click');
    }
    return this.enabled;
  }

  public getVolume(): number {
    return this.volume;
  }

  public setVolume(volume: number): void {
    this.volume = Math.max(0, Math.min(1, volume));
    this.saveSettings();
  }
}

// =====================================================
// RIG LOOP SOUND MANAGER
// Maneja el sonido continuo de los rigs minando
// =====================================================

class RigSoundManager {
  private audioElement: HTMLAudioElement | null = null;
  private fadeInterval: number | null = null;
  private targetVolume: number = 0;
  private isPlaying: boolean = false;
  private enabled: boolean = true;
  private baseVolume: number = 0.15; // Volumen base del loop

  constructor() {
    this.loadSettings();
  }

  private loadSettings(): void {
    try {
      const saved = localStorage.getItem('blockLords_soundSettings');
      if (saved) {
        const settings = JSON.parse(saved);
        this.enabled = settings.enabled ?? true;
        this.baseVolume = settings.rigLoopVolume ?? 0.3;
      }
    } catch {
      // Use defaults
    }
  }

  private saveSettings(): void {
    try {
      const current = localStorage.getItem('blockLords_soundSettings');
      const settings = current ? JSON.parse(current) : {};
      settings.rigLoopVolume = this.baseVolume;
      localStorage.setItem('blockLords_soundSettings', JSON.stringify(settings));
    } catch {
      // Ignore storage errors
    }
  }

  private createAudioElement(): HTMLAudioElement {
    if (!this.audioElement) {
      this.audioElement = new Audio(computerFanLoop);
      this.audioElement.loop = true;
      this.audioElement.volume = 0;
      // Preload the audio
      this.audioElement.load();
    }
    return this.audioElement;
  }

  // Inicia el sonido con fade in
  public start(activeRigsCount: number = 1): void {
    if (!this.enabled || activeRigsCount <= 0) return;

    const audio = this.createAudioElement();

    // Calcular volumen basado en cantidad de rigs (más rigs = más fuerte, con límite)
    // 1 rig = baseVolume, cada rig extra añade 15% hasta máx 2x
    const volumeMultiplier = Math.min(2, 1 + (activeRigsCount - 1) * 0.15);
    this.targetVolume = this.baseVolume * volumeMultiplier;

    if (!this.isPlaying) {
      audio.volume = 0;
      audio.play().catch(err => {
        console.warn('Could not play rig sound:', err);
      });
      this.isPlaying = true;
    }

    // Fade in
    this.fadeToVolume(this.targetVolume, 500);
  }

  // Detiene el sonido con fade out
  public stop(): void {
    if (!this.isPlaying || !this.audioElement) return;

    // Fade out y luego pausar
    this.fadeToVolume(0, 300, () => {
      if (this.audioElement) {
        this.audioElement.pause();
        this.audioElement.currentTime = 0;
      }
      this.isPlaying = false;
    });
  }

  // Actualiza el volumen basado en rigs activos (sin reiniciar)
  public updateVolume(activeRigsCount: number): void {
    if (!this.isPlaying || activeRigsCount <= 0) {
      if (activeRigsCount <= 0) this.stop();
      return;
    }

    const volumeMultiplier = Math.min(2, 1 + (activeRigsCount - 1) * 0.15);
    this.targetVolume = this.baseVolume * volumeMultiplier;
    this.fadeToVolume(this.targetVolume, 200);
  }

  private fadeToVolume(target: number, duration: number, onComplete?: () => void): void {
    if (this.fadeInterval) {
      clearInterval(this.fadeInterval);
    }

    if (!this.audioElement) {
      onComplete?.();
      return;
    }

    const startVolume = this.audioElement.volume;
    const volumeDiff = target - startVolume;
    const steps = Math.max(1, duration / 16); // ~60fps
    const volumeStep = volumeDiff / steps;
    let currentStep = 0;

    this.fadeInterval = window.setInterval(() => {
      currentStep++;
      if (this.audioElement) {
        this.audioElement.volume = Math.max(0, Math.min(1, startVolume + volumeStep * currentStep));
      }

      if (currentStep >= steps) {
        if (this.fadeInterval) clearInterval(this.fadeInterval);
        this.fadeInterval = null;
        if (this.audioElement) {
          this.audioElement.volume = Math.max(0, Math.min(1, target));
        }
        onComplete?.();
      }
    }, 16);
  }

  public setEnabled(enabled: boolean): void {
    this.enabled = enabled;
    if (!enabled && this.isPlaying) {
      this.stop();
    }
  }

  public isEnabled(): boolean {
    return this.enabled;
  }

  public setBaseVolume(volume: number): void {
    this.baseVolume = Math.max(0, Math.min(1, volume));
    this.saveSettings();
    // Actualizar volumen actual si está sonando
    if (this.isPlaying && this.audioElement) {
      this.audioElement.volume = this.baseVolume;
    }
  }

  public getBaseVolume(): number {
    return this.baseVolume;
  }

  public getIsPlaying(): boolean {
    return this.isPlaying;
  }
}

// Singleton
export const soundManager = new SoundManager();
export const rigSoundManager = new RigSoundManager();

// Helper para usar en componentes
export function playSound(sound: SoundType): void {
  soundManager.play(sound);
}
