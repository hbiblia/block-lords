// =====================================================
// BLOCK LORDS - Sound Composable
// Hook para usar sonidos en componentes Vue
// =====================================================

import { ref, onMounted } from 'vue';
import { soundManager, type SoundType } from '@/utils/sounds';

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
    return newState;
  }

  function setVolume(newVolume: number) {
    soundManager.setVolume(newVolume);
    volume.value = newVolume;
  }

  function setEnabled(enabled: boolean) {
    soundManager.setEnabled(enabled);
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
