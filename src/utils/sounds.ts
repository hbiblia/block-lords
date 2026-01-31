// =====================================================
// BLOCK LORDS - Sound Manager
// Sistema minimalista de sonidos del juego
// =====================================================

export type SoundType =
  | 'click'
  | 'success'
  | 'error'
  | 'purchase'
  | 'reward'
  | 'block_mined'
  | 'mission_complete'
  | 'warning'
  | 'notification';

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

// Singleton
export const soundManager = new SoundManager();

// Helper para usar en componentes
export function playSound(sound: SoundType): void {
  soundManager.play(sound);
}
