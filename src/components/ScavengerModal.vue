<script setup lang="ts">
import { watch, provide } from 'vue';
import { useI18n } from 'vue-i18n';
import { useScavengerStore } from '@/stores/scavenger';
import { useScavenger } from '@/composables/useScavenger';
import ScavengerServerSelect from './scavenger/ScavengerServerSelect.vue';
import ScavengerGrid from './scavenger/ScavengerGrid.vue';
import ScavengerHud from './scavenger/ScavengerHud.vue';
import ScavengerResult from './scavenger/ScavengerResult.vue';
import { playSound } from '@/utils/sounds';

const props = defineProps<{ show: boolean }>();
const emit = defineEmits<{ close: [] }>();

const { t } = useI18n();
const store = useScavengerStore();
const scavenger = useScavenger();

// Provide scavenger to children
provide('scavenger', scavenger);

watch(() => props.show, (open) => {
  if (open) {
    store.loadStats();
    store.setPhase('select');
  } else {
    scavenger.cleanup();
  }
});

function handleClose() {
  if (scavenger.gameActive.value) return;
  playSound('click');
  emit('close');
}

function handleBackdropClick() {
  if (scavenger.gameActive.value) return;
  emit('close');
}
</script>

<template>
  <Teleport to="body">
    <Transition name="fade">
      <div
        v-if="show"
        class="fixed inset-0 z-[150] flex items-center justify-center p-2 sm:p-4"
      >
        <!-- Backdrop -->
        <div
          class="absolute inset-0 bg-black/80 backdrop-blur-sm"
          @click="handleBackdropClick"
        />

        <!-- Modal -->
        <div class="relative w-full max-w-lg max-h-[90vh] flex flex-col rounded-xl overflow-hidden border border-amber-500/30 shadow-2xl bg-[#1a1b2e]">
          <!-- Header -->
          <div class="flex items-center justify-between px-4 py-3 border-b border-slate-700/50 bg-[#252640]">
            <div class="flex items-center gap-2">
              <span class="text-lg">🔍</span>
              <span class="font-semibold text-white text-sm">{{ t('scavenger.title', 'Rig Salvage') }}</span>
            </div>
            <button
              v-if="!scavenger.gameActive.value"
              @click="handleClose"
              class="text-slate-400 hover:text-white transition-colors text-lg leading-none"
            >
              ✕
            </button>
          </div>

          <!-- Content -->
          <div class="flex-1 overflow-y-auto">
            <ScavengerServerSelect v-if="store.gamePhase === 'select'" />

            <template v-else-if="store.gamePhase === 'playing'">
              <ScavengerHud />
              <ScavengerGrid />

              <!-- Collected loot bar -->
              <div class="px-3 py-2 border-t border-slate-700/50 bg-[#252640]/50">
                <div class="flex items-center justify-between">
                  <div class="flex items-center gap-1 flex-wrap">
                    <span class="text-[10px] text-slate-400 mr-1">{{ t('scavenger.lootCollected', 'Loot') }}:</span>
                    <template v-if="scavenger.collectedLoot.value.length === 0">
                      <span class="text-[10px] text-slate-500 italic">{{ t('scavenger.noLoot', 'None yet') }}</span>
                    </template>
                    <span
                      v-for="(item, i) in scavenger.collectedLoot.value.slice(-8)"
                      :key="i"
                      class="inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium"
                      :class="{
                        'bg-amber-500/20 text-amber-400': item.type === 'gc' || item.type === 'terminal_bonus',
                        'bg-cyan-500/20 text-cyan-400': item.type === 'material',
                        'bg-purple-500/20 text-purple-400': item.type === 'data_fragment',
                      }"
                    >
                      {{ item.type === 'gc' || item.type === 'terminal_bonus' ? `🪙${item.value}` : item.type === 'data_fragment' ? '📡' : `💎${item.rarity?.[0]?.toUpperCase()}` }}
                    </span>
                  </div>
                  <button
                    @click="scavenger.abandonRun()"
                    class="text-[10px] text-red-400 hover:text-red-300 transition-colors px-2 py-1 rounded hover:bg-red-500/10"
                  >
                    {{ t('scavenger.abandonRun', 'Abandon') }}
                  </button>
                </div>
              </div>
            </template>

            <ScavengerResult v-else-if="store.gamePhase === 'result'" />
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
.fade-enter-active,
.fade-leave-active {
  transition: opacity 0.2s ease;
}
.fade-enter-from,
.fade-leave-to {
  opacity: 0;
}
</style>
