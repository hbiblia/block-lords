// =====================================================
// BLOCK LORDS - Sound Composable
// Hook para usar sonidos en componentes Vue
// =====================================================

import { ref, onMounted } from 'vue';
import { soundManager, rigSoundManager, type SoundType } from '@/utils/sounds';

export function useSound() {
  const soundEnabled = ref(soundManager.isEnabled());
  const volume = ref(soundManager.getVolume());

  onMounted(() => {
    // Inicializar el audio context después de la primera interacción
    const initSound = () => {
      soundManager.init();
      document.removeEventListener('click', initSound);
      document.removeEventListener('keydown', initSound);
    };
    document.addEventListener('click', initSound, { once: true });
    document.addEventListener('keydown', initSound, { once: true });
  });

  function play(sound: SoundType) {
    soundManager.play(sound);
  }

  function toggle() {
    const newState = soundManager.toggleEnabled();
    soundEnabled.value = newState;
    // También sincronizar el rig loop
    rigSoundManager.setEnabled(newState);
    return newState;
  }

  function setVolume(newVolume: number) {
    soundManager.setVolume(newVolume);
    volume.value = newVolume;
  }

  function setEnabled(enabled: boolean) {
    soundManager.setEnabled(enabled);
    rigSoundManager.setEnabled(enabled);
    soundEnabled.value = enabled;
  }

  return {
    soundEnabled,
    volume,
    play,
    toggle,
    setVolume,
    setEnabled
  };
}

// =====================================================
// Hook específico para el sonido de rigs minando
// =====================================================

export function useRigSound() {
  const isPlaying = ref(rigSoundManager.getIsPlaying());
  const rigLoopVolume = ref(rigSoundManager.getBaseVolume());

  // Inicia el sonido de rigs (llamar cuando hay rigs activos)
  function startRigSound(activeRigsCount: number) {
    rigSoundManager.start(activeRigsCount);
    isPlaying.value = true;
  }

  // Detiene el sonido de rigs
  function stopRigSound() {
    rigSoundManager.stop();
    isPlaying.value = false;
  }

  // Actualiza el volumen basado en cantidad de rigs activos
  function updateRigSound(activeRigsCount: number) {
    if (activeRigsCount > 0) {
      if (!rigSoundManager.getIsPlaying()) {
        startRigSound(activeRigsCount);
      } else {
        rigSoundManager.updateVolume(activeRigsCount);
      }
    } else {
      stopRigSound();
    }
    isPlaying.value = rigSoundManager.getIsPlaying();
  }

  // Ajustar volumen base del loop
  function setRigLoopVolume(volume: number) {
    rigSoundManager.setBaseVolume(volume);
    rigLoopVolume.value = volume;
  }

  return {
    isPlaying,
    rigLoopVolume,
    startRigSound,
    stopRigSound,
    updateRigSound,
    setRigLoopVolume
  };
}
