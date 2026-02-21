<script setup lang="ts">
import { ref, computed, watch, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAuthStore } from '@/stores/auth';
import { useInventoryStore, type CoolingItem, type ModdedCoolingItem } from '@/stores/inventory';
import { useMiningStore } from '@/stores/mining';
import { redeemPrepaidCard, useExpPack } from '@/utils/api';
import { playSound } from '@/utils/sounds';
import CoolingWorkshopModal from './CoolingWorkshopModal.vue';

const { t } = useI18n();

const authStore = useAuthStore();
const inventoryStore = useInventoryStore();
const miningStore = useMiningStore();

const props = defineProps<{
  show: boolean;
}>();

const emit = defineEmits<{
  close: [];
  used: [];
}>();

const using = ref(false);

// --- Selection state ---
const selectedItem = ref<{ type: string; id: string } | null>(null);

function selectItem(type: string, id: string) {
  if (selectedItem.value?.type === type && selectedItem.value?.id === id) {
    selectedItem.value = null;
  } else {
    selectedItem.value = { type, id };
  }
  playSound('click');
}

// Workshop modal state
const showWorkshop = ref(false);
const workshopItem = ref<CoolingItem | ModdedCoolingItem | null>(null);

function openWorkshop(item: CoolingItem | ModdedCoolingItem) {
  workshopItem.value = item;
  showWorkshop.value = true;
  playSound('click');
}

function closeWorkshop() {
  showWorkshop.value = false;
  workshopItem.value = null;
}

async function onModded(playerCoolingItemId: string) {
  await inventoryStore.refresh();

  // Buscar el item actualizado y actualizar workshopItem + selección del grid
  const updated = inventoryStore.moddedCoolingItems.find(
    (m) => m.player_cooling_item_id === playerCoolingItemId
  );
  if (updated) {
    workshopItem.value = updated;
    // Actualizar selección al grupo correcto del item
    const modSig = (updated.mods || []).map(m => m.component_id).sort().join(',');
    const groupKey = `${updated.cooling_item_id}|${modSig}`;
    selectedItem.value = { type: 'modded_cooling', id: groupKey };
  }
}

// Group cards by card_id (same type + same value)
const groupedCards = computed(() => {
  const groups = new Map<string, { card_id: string; card_type: 'energy' | 'internet' | 'combo'; amount: number; tier: string; codes: { id: string; code: string }[]; }>();
  for (const card of inventoryStore.cardItems) {
    const existing = groups.get(card.card_id);
    if (existing) {
      existing.codes.push({ id: card.id, code: card.code });
    } else {
      groups.set(card.card_id, {
        card_id: card.card_id,
        card_type: card.card_type,
        amount: card.amount,
        tier: card.tier,
        codes: [{ id: card.id, code: card.code }],
      });
    }
  }
  return Array.from(groups.values());
});

// Group modded cooling items by base type + installed component types
interface GroupedModdedCooling {
  groupKey: string;
  cooling_item_id: string;
  items: ModdedCoolingItem[];
  representative: ModdedCoolingItem;
  count: number;
}

const groupedModdedCooling = computed<GroupedModdedCooling[]>(() => {
  const groups = new Map<string, GroupedModdedCooling>();
  for (const item of inventoryStore.moddedCoolingItems) {
    const modSignature = (item.mods || [])
      .map(m => m.component_id)
      .sort()
      .join(',');
    const key = `${item.cooling_item_id}|${modSignature}`;
    const existing = groups.get(key);
    if (existing) {
      existing.items.push(item);
      existing.count++;
    } else {
      groups.set(key, {
        groupKey: key,
        cooling_item_id: item.cooling_item_id,
        items: [item],
        representative: item,
        count: 1,
      });
    }
  }
  return Array.from(groups.values());
});

// AdSense
const inventoryAdInitialized = ref(false);
function initInventoryAd() {
  if (inventoryAdInitialized.value) return;
  nextTick(() => {
    setTimeout(() => {
      try {
        const adEl = document.querySelector('.inventory-ad-slot .adsbygoogle');
        if (adEl && adEl.clientWidth > 0 && !adEl.hasAttribute('data-adsbygoogle-status')) {
          ((window as any).adsbygoogle = (window as any).adsbygoogle || []).push({});
          inventoryAdInitialized.value = true;
        }
      } catch (e) { /* ad blocked */ }
    }, 500);
  });
}

// Fetch inventory when modal opens
watch(() => props.show, async (isOpen) => {
  if (isOpen) {
    await inventoryStore.fetchInventory();
    initInventoryAd();
  } else {
    selectedItem.value = null;
    inventoryAdInitialized.value = false;
  }
});

function handleClose() {
  playSound('click');
  emit('close');
}

// Confirmation dialog state
const showConfirm = ref(false);
const confirmAction = ref<{
  type: 'redeem' | 'install_rig' | 'delete_item';
  data: {
    cardCode?: string;
    cardName?: string;
    cardType?: 'energy' | 'internet' | 'combo';
    cardAmount?: number;
    rigId?: string;
    rigName?: string;
    deleteItemType?: string;
    deleteItemId?: string;
    deleteItemName?: string;
    deleteQuantity?: number;
    deleteMaxQuantity?: number;
  };
} | null>(null);

// 4-digit confirmation code for card redemption
const generatedCode = ref('');
const inputCode = ref('');

function generateConfirmCode(): string {
  return Math.floor(1000 + Math.random() * 9000).toString();
}

// Processing modal state
const showProcessingModal = ref(false);
const processingStatus = ref<'processing' | 'error'>('processing');
const processingError = ref<string>('');

function closeProcessingModal() {
  showProcessingModal.value = false;
  processingStatus.value = 'processing';
  processingError.value = '';
}

function requestRedeemCard(group: { card_id: string; card_type: 'energy' | 'internet' | 'combo'; amount: number; codes: { id: string; code: string }[] }) {
  confirmAction.value = {
    type: 'redeem',
    data: {
      cardCode: group.codes[0].code,
      cardName: getCardName(group.card_id),
      cardType: group.card_type,
      cardAmount: group.amount,
    },
  };
  generatedCode.value = generateConfirmCode();
  inputCode.value = '';
  showConfirm.value = true;
}

function requestInstallRig(rig: { rig_id: string; name: string }) {
  confirmAction.value = {
    type: 'install_rig',
    data: {
      rigId: rig.rig_id,
      rigName: rig.name,
    },
  };
  showConfirm.value = true;
}

// Delete quantity selector
const deleteQtyInput = ref(1);

function requestDeleteItem(itemType: string, itemId: string, itemName: string, maxQuantity: number = 1) {
  confirmAction.value = {
    type: 'delete_item',
    data: {
      deleteItemType: itemType,
      deleteItemId: itemId,
      deleteItemName: itemName,
      deleteQuantity: 1,
      deleteMaxQuantity: maxQuantity,
    },
  };
  deleteQtyInput.value = maxQuantity > 1 ? 1 : 1;
  showConfirm.value = true;
}

async function handleDeleteItem(itemType: string, itemId: string, quantity: number) {
  if (!authStore.player || using.value) return;
  using.value = true;
  showProcessingModal.value = true;
  processingStatus.value = 'processing';
  processingError.value = '';

  const result = await inventoryStore.deleteItem(itemType, itemId, quantity);

  if (result.success) {
    closeProcessingModal();
    selectedItem.value = null;
  } else {
    processingStatus.value = 'error';
    processingError.value = result.error || t('inventory.processing.errorDeleteItem', 'Error eliminando item');
  }

  using.value = false;
}

async function handleInstallRig(rigId: string) {
  if (!authStore.player || using.value) return;
  using.value = true;
  showProcessingModal.value = true;
  processingStatus.value = 'processing';
  processingError.value = '';

  const result = await inventoryStore.installRig(rigId);

  if (result.success) {
    closeProcessingModal();
    emit('used');
  } else {
    processingStatus.value = 'error';
    processingError.value = result.error || t('inventory.processing.errorInstallRig', 'Error instalando rig');
  }

  using.value = false;
}

async function handleRedeemCard(code: string) {
  if (!authStore.player || using.value) return;
  using.value = true;
  showProcessingModal.value = true;
  processingStatus.value = 'processing';
  processingError.value = '';

  try {
    const result = await redeemPrepaidCard(authStore.player.id, code);
    if (result.success) {
      await inventoryStore.refresh();
      await authStore.fetchPlayer();
      closeProcessingModal();
      playSound('success');
      emit('used');
    } else {
      processingStatus.value = 'error';
      processingError.value = result.error || t('inventory.processing.errorRedeemCard');
      playSound('error');
    }
  } catch (e) {
    console.error('Error redeeming card:', e);
    processingStatus.value = 'error';
    processingError.value = t('inventory.processing.errorRedeemCard');
    playSound('error');
  } finally {
    using.value = false;
  }
}

async function confirmUse() {
  if (!confirmAction.value) return;

  const { type, data } = confirmAction.value;
  showConfirm.value = false;

  if (type === 'redeem' && data.cardCode) {
    await handleRedeemCard(data.cardCode);
  } else if (type === 'install_rig' && data.rigId) {
    await handleInstallRig(data.rigId);
  } else if (type === 'delete_item' && data.deleteItemType && data.deleteItemId) {
    await handleDeleteItem(data.deleteItemType, data.deleteItemId, deleteQtyInput.value);
  }

  confirmAction.value = null;
}

function cancelUse() {
  showConfirm.value = false;
  confirmAction.value = null;
  generatedCode.value = '';
  inputCode.value = '';
}

function getTierColor(tier: string) {
  switch (tier) {
    case 'elite': return 'text-amber-400';
    case 'advanced': return 'text-fuchsia-400';
    case 'standard': return 'text-sky-400';
    case 'basic': return 'text-emerald-400';
    default: return 'text-text-muted';
  }
}

// Translation helpers for inventory items - fallback to DB name
function getCoolingName(id: string, fallbackName?: string): string {
  const isUUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id);
  if (isUUID) {
    if (fallbackName) return fallbackName;
    const item = inventoryStore.coolingItems.find(c => c.id === id);
    return item?.name ?? id;
  }

  const key = `market.items.cooling.${id}.name`;
  const translated = t(key);
  if (translated !== key) return translated;
  if (fallbackName) return fallbackName;
  const item = inventoryStore.coolingItems.find(c => c.id === id);
  return item?.name ?? id;
}

function getCardName(id: string): string {
  const key = `market.items.cards.${id}.name`;
  const translated = t(key);
  return translated !== key ? translated : id;
}

function getBoostName(id: string): string {
  const key = `market.items.boosts.${id}.name`;
  const translated = t(key);
  return translated !== key ? translated : id;
}

function getComponentName(id: string, fallback?: string): string {
  const key = `market.items.components.${id}.name`;
  const translated = t(key);
  if (translated !== key) return translated;
  return fallback || id;
}

function getRarityColor(rarity: string): string {
  switch (rarity) {
    case 'epic': return 'text-fuchsia-400';
    case 'rare': return 'text-amber-400';
    case 'uncommon': return 'text-sky-400';
    case 'common': return 'text-emerald-400';
    default: return 'text-text-muted';
  }
}

function getMaterialName(name: string): string {
  const key = `materials.${name}.name`;
  const translated = t(key);
  return translated !== key ? translated : name.replace(/_/g, ' ');
}

function getRigName(id: string, fallbackName?: string): string {
  const key = `market.items.rigs.${id}.name`;
  const translated = t(key);
  if (translated !== key) return translated;
  if (fallbackName) return fallbackName;
  return id;
}

function formatNumber(num: number): string {
  if (num >= 1000000) return (num / 1000000).toFixed(1) + 'M';
  if (num >= 1000) return (num / 1000).toFixed(1) + 'K';
  return num.toString();
}

function getBoostIcon(boostType: string): string {
  switch (boostType) {
    case 'hashrate': return '⚡';
    case 'energy_saver': return '🔋';
    case 'bandwidth_optimizer': return '📶';
    case 'overclock': return '🚀';
    case 'coolant_injection': return '❄️';
    case 'durability_shield': return '🛡️';
    default: return '✨';
  }
}

function getBoostTypeDescription(boostType: string): string {
  const key = `market.boosts.types.${boostType}`;
  const translated = t(key);
  return translated !== key ? translated : '';
}

function formatBoostEffect(boost: { boost_type: string; effect_value: number; secondary_value: number }): string {
  const sign = boost.boost_type === 'energy_saver' || boost.boost_type === 'bandwidth_optimizer' ||
               boost.boost_type === 'coolant_injection' || boost.boost_type === 'durability_shield' ? '-' : '+';
  let effect = `${sign}${boost.effect_value}%`;
  if (boost.boost_type === 'overclock' && boost.secondary_value > 0) {
    effect += ` / +${boost.secondary_value}% ⚡`;
  }
  return effect;
}

function formatDuration(minutes: number): string {
  if (minutes >= 60) {
    const hours = minutes / 60;
    return `${hours}h`;
  }
  return `${minutes}m`;
}

function formatTimeRemaining(seconds: number): string {
  if (seconds <= 0) return t('inventory.boosts.expired', 'Expired');
  const mins = Math.floor(seconds / 60);
  const hrs = Math.floor(mins / 60);
  if (hrs > 0) {
    return `${hrs}h ${mins % 60}m`;
  }
  return `${mins}m`;
}

// --- Unified inventory grid ---
type ItemSlot =
  | { type: 'rig'; id: string; icon: string; label: string; badge: string; tier: string }
  | { type: 'card'; id: string; icon: string; label: string; badge: string; tier: string; cardType: string }
  | { type: 'cooling'; id: string; icon: string; label: string; badge: string; tier: string }
  | { type: 'modded_cooling'; id: string; icon: string; label: string; badge: string; tier: string }
  | { type: 'material'; id: string; icon: string; label: string; badge: string; rarity: string }
  | { type: 'component'; id: string; icon: string; label: string; badge: string; tier: string }
  | { type: 'boost'; id: string; icon: string; label: string; badge: string; tier: string }
  | { type: 'patch'; id: string; icon: string; label: string; badge: string; tier: string }
  | { type: 'exp_pack'; id: string; icon: string; label: string; badge: string; tier: string };

const allItems = computed<ItemSlot[]>(() => [
  ...inventoryStore.rigItems.map(r => ({
    type: 'rig' as const, id: r.rig_id, icon: '⛏️',
    label: getRigName(r.rig_id, r.name), badge: `x${r.quantity}`, tier: r.tier,
  })),
  ...groupedCards.value.map(g => ({
    type: 'card' as const, id: g.card_id,
    icon: g.card_type === 'combo' ? '⚡📡' : g.card_type === 'energy' ? '⚡' : '📡',
    label: getCardName(g.card_id), badge: `x${g.codes.length}`,
    tier: g.tier, cardType: g.card_type,
  })),
  ...inventoryStore.coolingItems.map(c => ({
    type: 'cooling' as const, id: c.inventory_id, icon: '❄️',
    label: getCoolingName(c.id, c.name), badge: `x${c.quantity}`, tier: c.tier,
  })),
  ...groupedModdedCooling.value.map(g => ({
    type: 'modded_cooling' as const, id: g.groupKey, icon: '❄️',
    label: getCoolingName(g.representative.cooling_item_id, g.representative.name),
    badge: g.count > 1 ? `x${g.count}` : `${g.representative.mod_slots_used}/${g.representative.max_mod_slots}`,
    tier: g.representative.tier,
  })),
  ...inventoryStore.materialItems.map(m => ({
    type: 'material' as const, id: m.material_id, icon: m.icon,
    label: getMaterialName(m.name), badge: `x${m.quantity}`, rarity: m.rarity,
  })),
  ...inventoryStore.componentItems.map(c => ({
    type: 'component' as const, id: c.id, icon: '🧩',
    label: getComponentName(c.id, c.name), badge: `x${c.quantity}`, tier: c.tier,
  })),
  ...inventoryStore.boostItems.map(b => ({
    type: 'boost' as const, id: b.boost_id, icon: getBoostIcon(b.boost_type),
    label: getBoostName(b.boost_id), badge: `x${b.quantity}`, tier: b.tier,
  })),
  ...inventoryStore.patchItems.map(p => ({
    type: 'patch' as const, id: p.item_id, icon: '🩹',
    label: t('market.patch.name', 'Rig Patch'), badge: `x${p.quantity}`, tier: 'standard',
  })),
  ...inventoryStore.expPackItems.map(e => ({
    type: 'exp_pack' as const, id: e.item_id, icon: '📖',
    label: e.name || getExpPackName(e.item_id), badge: `x${e.quantity}`, tier: e.tier,
  })),
]);

const emptySlots = computed(() => Math.max(0, inventoryStore.maxSlots - allItems.value.length));

const capacityPercentage = computed(() =>
  Math.min(100, Math.round((inventoryStore.slotsUsed / inventoryStore.maxSlots) * 100))
);

// Slot border color by item type
function getSlotBorder(item: ItemSlot): string {
  switch (item.type) {
    case 'rig': return 'border-amber-500/50';
    case 'card': return item.cardType === 'energy' ? 'border-emerald-500/50' : item.cardType === 'combo' ? 'border-emerald-500/50' : 'border-emerald-500/50';
    case 'cooling':
    case 'modded_cooling': return 'border-cyan-500/50';
    case 'material':
    case 'component': return 'border-fuchsia-500/50';
    case 'boost': return 'border-orange-500/50';
    case 'patch': return 'border-fuchsia-500/50';
    case 'exp_pack': return 'border-emerald-500/50';
    default: return 'border-border';
  }
}

function getSlotBg(item: ItemSlot): string {
  switch (item.type) {
    case 'rig': return 'bg-amber-500/8';
    case 'card': return 'bg-emerald-500/8';
    case 'cooling':
    case 'modded_cooling': return 'bg-cyan-500/8';
    case 'material':
    case 'component': return 'bg-fuchsia-500/8';
    case 'boost': return 'bg-orange-500/8';
    case 'patch': return 'bg-fuchsia-500/8';
    case 'exp_pack': return 'bg-emerald-500/8';
    default: return 'bg-bg-tertiary';
  }
}

function getSlotLabelColor(item: ItemSlot): string {
  switch (item.type) {
    case 'rig': return 'text-amber-400';
    case 'card': return 'text-emerald-400';
    case 'cooling':
    case 'modded_cooling': return 'text-cyan-400';
    case 'material': return 'rarity' in item ? getRarityColor(item.rarity) : 'text-fuchsia-400';
    case 'component': return 'text-fuchsia-400';
    case 'boost': return 'text-orange-400';
    case 'patch': return 'text-fuchsia-400';
    case 'exp_pack': return 'text-emerald-400';
    default: return 'text-text-muted';
  }
}

function getSlotTierLetter(item: ItemSlot): string {
  if ('tier' in item) return item.tier.charAt(0).toUpperCase();
  if ('rarity' in item) return item.rarity.charAt(0).toUpperCase();
  return '';
}

function getSlotTierColor(item: ItemSlot): string {
  if ('tier' in item) return getTierColor(item.tier);
  if ('rarity' in item) return getRarityColor(item.rarity);
  return 'text-text-muted';
}

// --- Selected item resolvers ---
const selectedRig = computed(() => {
  if (selectedItem.value?.type !== 'rig') return null;
  return inventoryStore.rigItems.find(r => r.rig_id === selectedItem.value!.id) ?? null;
});

const selectedCard = computed(() => {
  if (selectedItem.value?.type !== 'card') return null;
  return groupedCards.value.find(g => g.card_id === selectedItem.value!.id) ?? null;
});

const selectedCooling = computed(() => {
  if (selectedItem.value?.type !== 'cooling' && selectedItem.value?.type !== 'modded_cooling') return null;
  const id = selectedItem.value!.id;
  if (selectedItem.value!.type === 'cooling') {
    const unmodded = inventoryStore.coolingItems.find(c => c.inventory_id === id);
    if (unmodded) return { item: unmodded, modded: false as const, count: unmodded.quantity, group: null as GroupedModdedCooling | null };
  } else {
    const group = groupedModdedCooling.value.find(g => g.groupKey === id);
    if (group) return { item: group.representative, modded: true as const, count: group.count, group };
  }
  return null;
});

const selectedMaterial = computed(() => {
  if (selectedItem.value?.type !== 'material' && selectedItem.value?.type !== 'component') return null;
  const id = selectedItem.value!.id;
  if (selectedItem.value!.type === 'material') {
    const mat = inventoryStore.materialItems.find(m => m.material_id === id);
    if (mat) return { item: mat, kind: 'material' as const };
  } else {
    const comp = inventoryStore.componentItems.find(c => c.id === id);
    if (comp) return { item: comp, kind: 'component' as const };
  }
  return null;
});

const selectedBoost = computed(() => {
  if (selectedItem.value?.type !== 'boost') return null;
  return inventoryStore.boostItems.find(b => b.boost_id === selectedItem.value!.id) ?? null;
});

const selectedPatch = computed(() => {
  if (selectedItem.value?.type !== 'patch') return null;
  return inventoryStore.patchItems.find(p => p.item_id === selectedItem.value!.id) ?? null;
});

const selectedExpPack = computed(() => {
  if (selectedItem.value?.type !== 'exp_pack') return null;
  return inventoryStore.expPackItems.find(e => e.item_id === selectedItem.value!.id) ?? null;
});

// Patch install: rig selection + confirmation
const showRigSelect = ref(false);
const applyingPatch = ref(false);
const patchSelectedRig = ref<{ id: string; name: string; condition: number } | null>(null);

function openRigSelect() {
  patchSelectedRig.value = null;
  showRigSelect.value = true;
}

function selectRigForPatch(rig: { id: string; rig: { name: string }; condition: number }) {
  patchSelectedRig.value = { id: rig.id, name: rig.rig.name, condition: rig.condition };
}

async function confirmApplyPatch() {
  if (!patchSelectedRig.value) return;
  await applyPatchToRig(patchSelectedRig.value.id);
}

// EXP Pack: slot selection + application
const showSlotSelect = ref(false);
const applyingExpPack = ref(false);
const expPackSelectedSlot = ref<{ id: string; slot_number: number; tier: string; xp: number } | null>(null);

function openSlotSelect() {
  expPackSelectedSlot.value = null;
  showSlotSelect.value = true;
}

function selectSlotForExpPack(slot: { id: string; slot_number: number; tier: string; xp: number }) {
  expPackSelectedSlot.value = slot;
}

async function confirmApplyExpPack() {
  if (!expPackSelectedSlot.value || !selectedExpPack.value) return;
  await applyExpPackToSlot(selectedExpPack.value.item_id, expPackSelectedSlot.value.id);
}

async function applyExpPackToSlot(packId: string, slotId: string) {
  if (!authStore.player?.id) return;
  applyingExpPack.value = true;
  try {
    const result = await useExpPack(authStore.player.id, packId, slotId);
    if (result?.success) {
      playSound('success');
      showSlotSelect.value = false;
      selectedItem.value = null;
      await Promise.all([
        inventoryStore.refresh(),
        miningStore.loadData(),
      ]);
    } else {
      playSound('error');
      alert(result?.error || 'Error applying EXP pack');
    }
  } catch (e) {
    console.error('Error applying exp pack:', e);
    playSound('error');
  } finally {
    applyingExpPack.value = false;
  }
}

function getSlotNextTierXp(tier: string): number {
  switch (tier) {
    case 'basic': return 500;
    case 'standard': return 2000;
    case 'advanced': return 8000;
    default: return 0;
  }
}

function getExpPackName(id: string): string {
  const key = `market.exp_packs.${id}.name`;
  const translated = t(key);
  return translated !== key ? translated : id;
}

async function applyPatchToRig(rigId: string) {
  if (!authStore.player?.id) return;
  applyingPatch.value = true;
  try {
    const { applyRigPatch } = await import('@/utils/api');
    const result = await applyRigPatch(authStore.player.id, rigId);
    if (result?.success) {
      playSound('success');
      showRigSelect.value = false;
      selectedItem.value = null;
      await inventoryStore.refresh();
    } else {
      playSound('error');
      alert(result?.error || 'Error applying patch');
    }
  } catch (e) {
    console.error('Error applying patch:', e);
    playSound('error');
  } finally {
    applyingPatch.value = false;
  }
}
</script>

<template>
  <Teleport to="body">
    <div
      v-if="show"
      class="fixed inset-0 z-50 flex items-center justify-center p-4"
    >
      <!-- Overlay -->
      <div
        class="absolute inset-0 bg-black/70 backdrop-blur-sm"
        @click="handleClose"
      ></div>

      <!-- Modal -->
      <div class="relative w-full max-w-4xl h-[85vh] flex flex-col bg-bg-secondary border border-border rounded-xl overflow-hidden">
        <!-- Header -->
        <div class="p-2 border-b border-border">
          <div class="flex items-center justify-between">
            <h2 class="text-lg font-semibold flex items-center gap-2">
              <span>🎒</span>
              <span>{{ t('inventory.title') }}</span>
            </h2>
            <button
              @click="handleClose"
              class="p-2 hover:bg-bg-tertiary rounded-lg transition-colors text-text-muted hover:text-white"
            >
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>
          <div v-if="authStore.player" class="flex items-center gap-2 text-xs mt-2">
            <span class="flex items-center gap-1 px-2 py-1 rounded-md bg-amber-500/10 border border-amber-500/20">
              <span>⚡</span>
              <span class="font-mono font-medium text-amber-400">{{ Math.floor(authStore.player.energy) }}/{{ authStore.player.max_energy }}</span>
            </span>
            <span class="flex items-center gap-1 px-2 py-1 rounded-md bg-cyan-500/10 border border-cyan-500/20">
              <span>📡</span>
              <span class="font-mono font-medium text-cyan-400">{{ Math.floor(authStore.player.internet) }}/{{ authStore.player.max_internet }}</span>
            </span>
          </div>
        </div>

        <!-- Capacity Bar -->
        <div class="px-3 py-1.5 border-b border-border/30 flex items-center gap-2">
          <span class="text-xs text-text-muted">🎒</span>
          <div class="flex-1 h-1.5 bg-bg-tertiary rounded-full overflow-hidden">
            <div
              class="h-full rounded-full transition-all duration-300"
              :class="capacityPercentage > 90 ? 'bg-status-danger' : capacityPercentage > 70 ? 'bg-status-warning' : 'bg-accent-primary'"
              :style="{ width: capacityPercentage + '%' }"
            ></div>
          </div>
          <span class="text-xs font-mono" :class="capacityPercentage > 90 ? 'text-status-danger' : 'text-text-muted'">
            {{ inventoryStore.slotsUsed }}/{{ inventoryStore.maxSlots }}
          </span>
        </div>

        <!-- Ad Banner -->
        <div class="inventory-ad-slot px-3 py-2 border-b border-border/30 bg-bg-primary/30">
          <div class="text-[10px] text-text-muted text-center mb-1">{{ t('blocks.sponsoredBy') }}</div>
          <div class="flex justify-center">
            <ins class="adsbygoogle"
              style="display:block"
              data-ad-client="ca-pub-7500429866047477"
              data-ad-slot="6463255272"
              data-ad-format="horizontal"
              data-full-width-responsive="true"></ins>
          </div>
        </div>

        <!-- Active Boosts Bar -->
        <div v-if="inventoryStore.activeBoosts.length > 0" class="px-3 pt-2 pb-1 border-b border-border/30">
          <div class="flex flex-wrap gap-1.5">
            <div
              v-for="boost in inventoryStore.activeBoosts"
              :key="boost.id"
              class="flex items-center gap-1 px-2 py-0.5 rounded-md bg-amber-500/20 border border-amber-500/30 text-xs"
            >
              <span class="font-medium text-amber-400">{{ getBoostName(boost.boost_id) }}</span>
              <span class="text-[10px] text-text-muted">{{ formatTimeRemaining(boost.seconds_remaining) }}</span>
            </div>
          </div>
        </div>

        <!-- Content Area -->
        <div class="flex-1 flex flex-col overflow-hidden">
          <!-- Loading -->
          <div v-if="inventoryStore.loading && !inventoryStore.loaded" class="flex-1 flex items-center justify-center">
            <div class="text-center">
              <div class="w-8 h-8 mx-auto mb-4 border-2 border-accent-primary border-t-transparent rounded-full animate-spin"></div>
              <p class="text-text-muted text-sm">{{ t('inventory.loading') }}</p>
            </div>
          </div>

          <!-- Inventory Grid -->
          <template v-else>
            <div class="flex-1 overflow-y-auto p-3">
              <div class="grid grid-cols-5 sm:grid-cols-8 gap-1.5">
                <!-- Filled slots -->
                <button
                  v-for="item in allItems"
                  :key="item.type + '-' + item.id"
                  @click="selectItem(item.type, item.id)"
                  class="aspect-square rounded-md border p-0.5 flex flex-col items-center justify-center relative transition-all duration-150 cursor-pointer"
                  :class="[
                    getSlotBorder(item), getSlotBg(item),
                    selectedItem?.type === item.type && selectedItem?.id === item.id
                      ? 'ring-2 ring-accent-primary scale-105 shadow-glow'
                      : 'hover:scale-[1.02] hover:brightness-110'
                  ]"
                >
                  <span class="absolute top-0 left-0.5 text-[8px] sm:text-[9px] uppercase font-bold" :class="getSlotTierColor(item)">{{ getSlotTierLetter(item) }}</span>
                  <span v-if="item.type === 'modded_cooling'" class="absolute top-0 right-0 text-[8px] bg-fuchsia-500/40 text-fuchsia-300 rounded px-0.5">🔧</span>
                  <span class="text-xl sm:text-2xl leading-none">{{ item.icon }}</span>
                  <span class="text-[9px] sm:text-[10px] w-full text-center leading-tight line-clamp-2 break-words" :class="getSlotLabelColor(item)">{{ item.label }}</span>
                  <span class="absolute bottom-0 right-0.5 text-[9px] sm:text-[10px] font-mono font-bold text-white bg-black/50 px-0.5 rounded">{{ item.badge }}</span>
                </button>

                <!-- Empty slots -->
                <div
                  v-for="n in emptySlots"
                  :key="'empty-' + n"
                  class="aspect-square rounded-md border border-dashed border-border/20 bg-white/[0.02]"
                ></div>
              </div>
            </div>

            <!-- Detail Panel -->
            <div
              v-if="selectedItem"
              class="shrink-0 border-t border-border/50 bg-bg-primary/80 backdrop-blur-sm p-3 sm:p-4 max-h-[40%] overflow-y-auto animate-slide-up"
            >
              <!-- Rig Detail -->
              <template v-if="selectedRig">
                <div class="flex items-start gap-3">
                  <div class="text-3xl sm:text-4xl">⛏️</div>
                  <div class="flex-1 min-w-0">
                    <h4 class="font-bold text-sm sm:text-base" :class="getTierColor(selectedRig.tier)">{{ getRigName(selectedRig.rig_id, selectedRig.name) }}</h4>
                    <p class="text-[10px] sm:text-xs text-text-muted uppercase">{{ selectedRig.tier }} Rig</p>
                  </div>
                  <span class="text-xs font-mono text-text-muted">x{{ selectedRig.quantity }}</span>
                </div>
                <div class="grid grid-cols-3 gap-2 mt-2">
                  <div class="text-center p-1.5 rounded bg-bg-secondary">
                    <div class="text-[10px] text-text-muted">Hashrate</div>
                    <div class="font-mono font-bold text-sm text-accent-primary">{{ formatNumber(selectedRig.hashrate) }} H/s</div>
                  </div>
                  <div class="text-center p-1.5 rounded bg-bg-secondary">
                    <div class="text-[10px] text-text-muted">⚡ Power</div>
                    <div class="font-mono font-bold text-sm text-amber-400">{{ selectedRig.power_consumption }}/t</div>
                  </div>
                  <div class="text-center p-1.5 rounded bg-bg-secondary">
                    <div class="text-[10px] text-text-muted">📡 Internet</div>
                    <div class="font-mono font-bold text-sm text-cyan-400">{{ selectedRig.internet_consumption }}/t</div>
                  </div>
                </div>
                <div class="flex gap-2 mt-3">
                  <button
                    @click="requestInstallRig(selectedRig)"
                    :disabled="using || inventoryStore.installing"
                    class="flex-1 py-2 rounded-lg text-sm font-medium transition-colors disabled:opacity-50 bg-accent-primary text-white hover:bg-accent-primary/80"
                  >
                    {{ inventoryStore.installing ? '...' : t('inventory.rigs.install', 'Instalar') }}
                  </button>
                  <button
                    @click="requestDeleteItem('rig', selectedRig.rig_id, getRigName(selectedRig.rig_id, selectedRig.name), selectedRig.quantity)"
                    :disabled="using"
                    class="px-3 py-2 rounded-lg text-sm font-medium transition-colors disabled:opacity-50 bg-status-danger/20 text-status-danger hover:bg-status-danger/30 border border-status-danger/30"
                    :title="t('inventory.delete.button', 'Descartar')"
                  >
                    🗑️
                  </button>
                </div>
              </template>

              <!-- Card Detail -->
              <template v-if="selectedCard">
                <div class="flex items-start gap-3">
                  <div class="text-3xl sm:text-4xl">{{ selectedCard.card_type === 'combo' ? '⚡📡' : selectedCard.card_type === 'energy' ? '⚡' : '📡' }}</div>
                  <div class="flex-1 min-w-0">
                    <h4 class="font-bold text-sm sm:text-base" :class="selectedCard.card_type === 'combo' ? 'text-white' : selectedCard.card_type === 'energy' ? 'text-amber-400' : 'text-cyan-400'">{{ getCardName(selectedCard.card_id) }}</h4>
                    <p class="text-[10px] sm:text-xs text-text-muted uppercase">{{ selectedCard.tier }}</p>
                  </div>
                  <span class="text-xs font-mono text-text-muted">x{{ selectedCard.codes.length }}</span>
                </div>
                <div class="mt-2 space-y-1">
                  <template v-if="selectedCard.card_type === 'combo'">
                    <div class="flex justify-between text-xs"><span class="text-text-muted">⚡ {{ t('welcome.energy', 'Energía') }}</span><span class="font-mono font-bold text-amber-400">+{{ selectedCard.amount }}</span></div>
                    <div class="flex justify-between text-xs"><span class="text-text-muted">📡 {{ t('welcome.internet', 'Internet') }}</span><span class="font-mono font-bold text-cyan-400">+{{ selectedCard.amount }}</span></div>
                  </template>
                  <template v-else>
                    <div class="flex justify-between text-xs">
                      <span class="text-text-muted">{{ selectedCard.card_type === 'energy' ? t('welcome.energy', 'Energía') : t('welcome.internet', 'Internet') }}</span>
                      <span class="font-mono font-bold" :class="selectedCard.card_type === 'energy' ? 'text-amber-400' : 'text-cyan-400'">+{{ selectedCard.amount }}%</span>
                    </div>
                  </template>
                </div>
                <div class="flex gap-2 mt-3">
                  <button
                    @click="requestRedeemCard(selectedCard)"
                    :disabled="using"
                    class="flex-1 py-2 rounded-lg text-sm font-medium transition-colors disabled:opacity-50"
                    :class="selectedCard.card_type === 'combo'
                      ? 'bg-gradient-to-r from-amber-500 to-cyan-500 text-white hover:from-amber-400 hover:to-cyan-400'
                      : selectedCard.card_type === 'energy'
                        ? 'bg-amber-500 text-white hover:bg-amber-400'
                        : 'bg-cyan-500 text-white hover:bg-cyan-400'"
                  >
                    {{ using ? '...' : t('inventory.cards.recharge') }}
                  </button>
                  <button
                    @click="requestDeleteItem('card', selectedCard.card_id, getCardName(selectedCard.card_id), selectedCard.codes.length)"
                    :disabled="using"
                    class="px-3 py-2 rounded-lg text-sm font-medium transition-colors disabled:opacity-50 bg-status-danger/20 text-status-danger hover:bg-status-danger/30 border border-status-danger/30"
                    :title="t('inventory.delete.button', 'Descartar')"
                  >
                    🗑️
                  </button>
                </div>
              </template>

              <!-- Cooling Detail -->
              <template v-if="selectedCooling">
                <div class="flex items-start gap-3">
                  <div class="text-3xl sm:text-4xl">❄️</div>
                  <div class="flex-1 min-w-0">
                    <template v-if="!selectedCooling.modded">
                      <h4 class="font-bold text-sm sm:text-base" :class="getTierColor(selectedCooling.item.tier)">{{ getCoolingName(selectedCooling.item.id) }}</h4>
                      <p class="text-[10px] sm:text-xs text-text-muted uppercase">{{ selectedCooling.item.tier }} · {{ selectedCooling.item.max_mod_slots || 1 }} slots</p>
                    </template>
                    <template v-else>
                      <h4 class="font-bold text-sm sm:text-base" :class="getTierColor(selectedCooling.item.tier)">{{ getCoolingName(selectedCooling.item.cooling_item_id, selectedCooling.item.name) }}</h4>
                      <p class="text-[10px] sm:text-xs text-fuchsia-400 uppercase">{{ t('inventory.cooling.modded') }} · 🧩 {{ selectedCooling.item.mod_slots_used }}/{{ selectedCooling.item.max_mod_slots }}</p>
                    </template>
                  </div>
                  <span class="text-xs font-mono text-text-muted">x{{ selectedCooling.count }}</span>
                </div>
                <div class="grid grid-cols-2 sm:grid-cols-3 gap-2 mt-2">
                  <div class="text-center p-1.5 rounded bg-bg-secondary">
                    <div class="text-[10px] text-text-muted">{{ t('inventory.cooling.power', 'Potencia') }}</div>
                    <div class="font-mono font-bold text-sm text-cyan-400">-{{ selectedCooling.modded ? selectedCooling.item.effective_cooling_power.toFixed(1) : selectedCooling.item.cooling_power }}°</div>
                  </div>
                  <div class="text-center p-1.5 rounded bg-bg-secondary">
                    <div class="text-[10px] text-text-muted">⚡ Cost</div>
                    <div class="font-mono font-bold text-sm text-amber-400">+{{ selectedCooling.modded ? selectedCooling.item.effective_energy_cost.toFixed(1) : selectedCooling.item.energy_cost }}/t</div>
                  </div>
                  <div v-if="selectedCooling.modded && selectedCooling.item.total_durability_mod !== 0" class="text-center p-1.5 rounded bg-bg-secondary">
                    <div class="text-[10px] text-text-muted">🔧 Durability</div>
                    <div class="font-mono font-bold text-sm" :class="selectedCooling.item.total_durability_mod > 0 ? 'text-emerald-400' : 'text-rose-400'">{{ selectedCooling.item.total_durability_mod > 0 ? '+' : '' }}{{ selectedCooling.item.total_durability_mod.toFixed(1) }}%</div>
                  </div>
                </div>
                <div class="flex gap-2 mt-3">
                  <button
                    @click="openWorkshop(selectedCooling.item)"
                    :disabled="selectedCooling.modded && selectedCooling.item.mod_slots_used >= selectedCooling.item.max_mod_slots"
                    class="flex-1 py-2 rounded-lg text-sm font-medium transition-colors disabled:opacity-50"
                    :class="(!selectedCooling.modded || selectedCooling.item.mod_slots_used < selectedCooling.item.max_mod_slots)
                      ? 'bg-fuchsia-600 hover:bg-fuchsia-500 text-white'
                      : 'bg-bg-tertiary text-text-muted cursor-not-allowed'"
                  >
                    🔧 {{ (!selectedCooling.modded || selectedCooling.item.mod_slots_used < selectedCooling.item.max_mod_slots) ? t('inventory.cooling.modify') : t('workshop.slotsFull') }}
                  </button>
                  <button
                    @click="selectedCooling.modded
                      ? requestDeleteItem('modded_cooling', selectedCooling.item.player_cooling_item_id, getCoolingName(selectedCooling.item.cooling_item_id, selectedCooling.item.name), selectedCooling.count)
                      : requestDeleteItem('cooling', selectedCooling.item.inventory_id, getCoolingName(selectedCooling.item.id), selectedCooling.count)"
                    :disabled="using"
                    class="px-3 py-2 rounded-lg text-sm font-medium transition-colors disabled:opacity-50 bg-status-danger/20 text-status-danger hover:bg-status-danger/30 border border-status-danger/30"
                    :title="t('inventory.delete.button', 'Descartar')"
                  >
                    🗑️
                  </button>
                </div>
              </template>

              <!-- Material / Component Detail -->
              <template v-if="selectedMaterial">
                <template v-if="selectedMaterial.kind === 'material'">
                  <div class="flex items-start gap-3">
                    <div class="text-3xl sm:text-4xl">{{ selectedMaterial.item.icon }}</div>
                    <div class="flex-1 min-w-0">
                      <h4 class="font-bold text-sm sm:text-base" :class="getRarityColor(selectedMaterial.item.rarity)">{{ getMaterialName(selectedMaterial.item.name) }}</h4>
                      <p class="text-[10px] sm:text-xs text-text-muted uppercase">{{ selectedMaterial.item.rarity }}</p>
                    </div>
                    <span class="text-xs font-mono text-text-muted">x{{ selectedMaterial.item.quantity }}</span>
                  </div>
                  <p class="text-[10px] sm:text-xs text-text-muted/70 italic mt-2">{{ t('inventory.materials.description') }}</p>
                  <button
                    @click="requestDeleteItem('material', selectedMaterial.item.material_id, getMaterialName(selectedMaterial.item.name), selectedMaterial.item.quantity)"
                    :disabled="using"
                    class="w-full mt-3 py-2 rounded-lg text-sm font-medium transition-colors disabled:opacity-50 bg-status-danger/20 text-status-danger hover:bg-status-danger/30 border border-status-danger/30"
                  >
                    🗑️ {{ t('inventory.delete.button', 'Descartar') }}
                  </button>
                </template>
                <template v-else>
                  <div class="flex items-start gap-3">
                    <div class="text-3xl sm:text-4xl">🧩</div>
                    <div class="flex-1 min-w-0">
                      <h4 class="font-bold text-sm sm:text-base" :class="getTierColor(selectedMaterial.item.tier)">{{ getComponentName(selectedMaterial.item.id, selectedMaterial.item.name) }}</h4>
                      <p class="text-[10px] sm:text-xs text-text-muted uppercase">{{ selectedMaterial.item.tier }}</p>
                    </div>
                    <span class="text-xs font-mono text-text-muted">x{{ selectedMaterial.item.quantity }}</span>
                  </div>
                  <p class="text-[10px] sm:text-xs text-text-muted/70 italic mt-2">{{ t('inventory.components.description') }}</p>
                  <button
                    @click="requestDeleteItem('component', selectedMaterial.item.id, getComponentName(selectedMaterial.item.id, selectedMaterial.item.name), selectedMaterial.item.quantity)"
                    :disabled="using"
                    class="w-full mt-3 py-2 rounded-lg text-sm font-medium transition-colors disabled:opacity-50 bg-status-danger/20 text-status-danger hover:bg-status-danger/30 border border-status-danger/30"
                  >
                    🗑️ {{ t('inventory.delete.button', 'Descartar') }}
                  </button>
                </template>
              </template>

              <!-- Boost Detail -->
              <template v-if="selectedBoost">
                <div class="flex items-start gap-3">
                  <div class="text-3xl sm:text-4xl">{{ getBoostIcon(selectedBoost.boost_type) }}</div>
                  <div class="flex-1 min-w-0">
                    <h4 class="font-bold text-sm sm:text-base text-amber-400">{{ getBoostName(selectedBoost.boost_id) }}</h4>
                    <p class="text-[10px] sm:text-xs text-text-muted uppercase">{{ selectedBoost.tier }}</p>
                  </div>
                  <span class="text-xs font-mono text-text-muted">x{{ selectedBoost.quantity }}</span>
                </div>
                <p class="text-xs text-text-muted mt-1">{{ getBoostTypeDescription(selectedBoost.boost_type) }}</p>
                <div class="grid grid-cols-2 gap-2 mt-2">
                  <div class="text-center p-1.5 rounded bg-bg-secondary">
                    <div class="text-[10px] text-text-muted">{{ t('market.boosts.effect') }}</div>
                    <div class="font-mono font-bold text-sm text-amber-400">{{ formatBoostEffect(selectedBoost) }}</div>
                  </div>
                  <div class="text-center p-1.5 rounded bg-bg-secondary">
                    <div class="text-[10px] text-text-muted">Duration</div>
                    <div class="font-mono font-bold text-sm text-white">{{ formatDuration(selectedBoost.duration_minutes) }}</div>
                  </div>
                </div>
                <p class="text-[10px] sm:text-xs text-text-muted/70 italic text-center mt-2">{{ t('inventory.boosts.installHint', 'Instalar desde gestion de rig') }}</p>
                <button
                  @click="requestDeleteItem('boost', selectedBoost.boost_id, getBoostName(selectedBoost.boost_id), selectedBoost.quantity)"
                  :disabled="using"
                  class="w-full mt-2 py-2 rounded-lg text-sm font-medium transition-colors disabled:opacity-50 bg-status-danger/20 text-status-danger hover:bg-status-danger/30 border border-status-danger/30"
                >
                  🗑️ {{ t('inventory.delete.button', 'Descartar') }}
                </button>
              </template>

              <!-- Patch Detail -->
              <template v-if="selectedPatch">
                <div class="flex items-start gap-3">
                  <div class="text-3xl sm:text-4xl">🩹</div>
                  <div class="flex-1 min-w-0">
                    <h4 class="font-bold text-sm sm:text-base text-fuchsia-400">{{ t('market.patch.name', 'Rig Patch') }}</h4>
                    <p class="text-[10px] sm:text-xs text-text-muted uppercase">{{ t('market.patch.universal', 'Universal') }}</p>
                  </div>
                  <span class="text-xs font-mono text-text-muted">x{{ selectedPatch.quantity }}</span>
                </div>
                <div class="grid grid-cols-3 gap-2 mt-2">
                  <div class="text-center p-1.5 rounded bg-bg-secondary">
                    <div class="text-[10px] text-text-muted">{{ t('rigManage.condition', 'Condición') }}</div>
                    <div class="font-mono font-bold text-sm text-emerald-400">+35%</div>
                  </div>
                  <div class="text-center p-1.5 rounded bg-bg-secondary">
                    <div class="text-[10px] text-text-muted">Hashrate</div>
                    <div class="font-mono font-bold text-sm text-status-danger">-10%</div>
                  </div>
                  <div class="text-center p-1.5 rounded bg-bg-secondary">
                    <div class="text-[10px] text-text-muted">{{ t('rigManage.consumption', 'Consumo') }}</div>
                    <div class="font-mono font-bold text-sm text-status-danger">+15%</div>
                  </div>
                </div>
                <div class="flex gap-2 mt-3">
                  <button
                    @click="openRigSelect"
                    :disabled="using || applyingPatch"
                    class="flex-1 py-2 rounded-lg text-sm font-medium transition-colors disabled:opacity-50 bg-fuchsia-600 hover:bg-fuchsia-500 text-white"
                  >
                    🔧 {{ t('inventory.patch.install', 'Instalar') }}
                  </button>
                  <button
                    @click="requestDeleteItem('patch', selectedPatch.item_id, t('market.patch.name', 'Rig Patch'), selectedPatch.quantity)"
                    :disabled="using"
                    class="px-3 py-2 rounded-lg text-sm font-medium transition-colors disabled:opacity-50 bg-status-danger/20 text-status-danger hover:bg-status-danger/30 border border-status-danger/30"
                    :title="t('inventory.delete.button', 'Descartar')"
                  >
                    🗑️
                  </button>
                </div>
              </template>

              <!-- EXP Pack Detail -->
              <template v-if="selectedExpPack">
                <div class="flex items-start gap-3">
                  <div class="text-3xl sm:text-4xl">📖</div>
                  <div class="flex-1 min-w-0">
                    <h4 class="font-bold text-sm sm:text-base text-emerald-400">{{ getExpPackName(selectedExpPack.item_id) }}</h4>
                    <p class="text-[10px] sm:text-xs text-text-muted uppercase">{{ selectedExpPack.tier }}</p>
                  </div>
                  <span class="text-xs font-mono text-text-muted">x{{ selectedExpPack.quantity }}</span>
                </div>
                <div class="grid grid-cols-1 gap-2 mt-2">
                  <div class="text-center p-1.5 rounded bg-bg-secondary">
                    <div class="text-[10px] text-text-muted">Slot XP</div>
                    <div class="font-mono font-bold text-sm text-emerald-400">+{{ selectedExpPack.xp_amount }} XP</div>
                  </div>
                </div>
                <div class="flex gap-2 mt-3">
                  <button
                    @click="openSlotSelect"
                    :disabled="using || applyingExpPack"
                    class="flex-1 py-2 rounded-lg text-sm font-medium transition-colors disabled:opacity-50 bg-emerald-600 hover:bg-emerald-500 text-white"
                  >
                    📖 {{ t('market.exp.useTitle', 'Use EXP Pack') }}
                  </button>
                  <button
                    @click="requestDeleteItem('exp_pack', selectedExpPack.item_id, getExpPackName(selectedExpPack.item_id), selectedExpPack.quantity)"
                    :disabled="using"
                    class="px-3 py-2 rounded-lg text-sm font-medium transition-colors disabled:opacity-50 bg-status-danger/20 text-status-danger hover:bg-status-danger/30 border border-status-danger/30"
                    :title="t('inventory.delete.button', 'Descartar')"
                  >
                    🗑️
                  </button>
                </div>
              </template>
            </div>
          </template>
        </div>
      </div>

      <!-- Rig Selection Modal for Patch Install -->
      <div
        v-if="showRigSelect"
        class="absolute inset-0 flex items-center justify-center bg-black/60 z-10"
      >
        <div class="bg-bg-secondary rounded-xl p-5 max-w-sm w-full mx-4 border border-fuchsia-500/30 animate-fade-in">
          <div class="text-center mb-4">
            <div class="text-3xl mb-2">🩹</div>
            <h3 class="text-lg font-bold">{{ t('inventory.patch.selectRig', 'Seleccionar Rig') }}</h3>
            <p class="text-text-muted text-xs mt-1">{{ t('inventory.patch.selectRigHint', 'Elige el rig donde instalar el parche') }}</p>
          </div>

          <div class="space-y-2 max-h-60 overflow-y-auto">
            <button
              v-for="rig in miningStore.rigs"
              :key="rig.id"
              @click="selectRigForPatch(rig)"
              :disabled="applyingPatch"
              class="w-full flex items-center gap-3 p-3 rounded-lg border transition-colors hover:bg-fuchsia-500/10 hover:border-fuchsia-500/40 disabled:opacity-50"
              :class="[
                patchSelectedRig?.id === rig.id ? 'border-fuchsia-500 bg-fuchsia-500/15 ring-1 ring-fuchsia-500/50' : rig.condition < 30 ? 'border-status-danger/40 bg-status-danger/5' : 'border-border bg-bg-primary'
              ]"
            >
              <span class="text-2xl">⛏️</span>
              <div class="flex-1 text-left min-w-0">
                <div class="font-medium text-sm truncate">{{ rig.rig.name }}</div>
                <div class="flex items-center gap-2 text-[10px] text-text-muted">
                  <span :class="rig.condition < 30 ? 'text-status-danger' : rig.condition < 60 ? 'text-status-warning' : 'text-emerald-400'">
                    ❤️ {{ rig.condition.toFixed(0) }}%
                  </span>
                  <span>⚡ {{ formatNumber(rig.rig.hashrate) }} H/s</span>
                </div>
              </div>
              <div v-if="patchSelectedRig?.id === rig.id" class="text-fuchsia-400 text-lg">✓</div>
              <div v-else-if="applyingPatch" class="w-4 h-4 border-2 border-fuchsia-400 border-t-transparent rounded-full animate-spin"></div>
            </button>

            <div v-if="!miningStore.rigs.length" class="text-center py-6 text-text-muted text-sm">
              {{ t('inventory.patch.noRigs', 'No tienes rigs instalados') }}
            </div>
          </div>

          <div class="flex gap-2 mt-4">
            <button
              @click="showRigSelect = false; patchSelectedRig = null"
              :disabled="applyingPatch"
              class="flex-1 py-2.5 rounded-lg font-medium bg-bg-tertiary hover:bg-bg-tertiary/80 transition-colors disabled:opacity-50"
            >
              {{ t('common.cancel') }}
            </button>
            <button
              @click="confirmApplyPatch"
              :disabled="!patchSelectedRig || applyingPatch"
              class="flex-1 py-2.5 rounded-lg font-medium bg-fuchsia-500 text-white hover:bg-fuchsia-400 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
            >
              <span v-if="applyingPatch" class="flex items-center justify-center gap-2">
                <span class="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin"></span>
              </span>
              <span v-else>{{ t('common.confirm', 'Confirmar') }}</span>
            </button>
          </div>
        </div>
      </div>

      <!-- Slot Selection Modal for EXP Pack -->
      <div
        v-if="showSlotSelect"
        class="absolute inset-0 flex items-center justify-center bg-black/60 z-10"
      >
        <div class="bg-bg-secondary rounded-xl p-5 max-w-sm w-full mx-4 border border-emerald-500/30 animate-fade-in">
          <div class="text-center mb-4">
            <div class="text-3xl mb-2">📖</div>
            <h3 class="text-lg font-bold">{{ t('common.selectSlot', 'Select Slot') }}</h3>
            <p class="text-text-muted text-xs mt-1">{{ t('inventory.expPack.selectSlotHint', 'Choose the slot to apply the EXP pack to') }}</p>
          </div>

          <div class="space-y-2 max-h-60 overflow-y-auto">
            <button
              v-for="slot in (miningStore.slotInfo?.slots ?? []).filter(s => !s.is_destroyed)"
              :key="slot.id"
              @click="selectSlotForExpPack(slot)"
              :disabled="applyingExpPack || slot.tier === 'elite'"
              class="w-full flex items-center gap-3 p-3 rounded-lg border transition-colors hover:bg-emerald-500/10 hover:border-emerald-500/40 disabled:opacity-50"
              :class="[
                expPackSelectedSlot?.id === slot.id ? 'border-emerald-500 bg-emerald-500/15 ring-1 ring-emerald-500/50' : 'border-border bg-bg-primary'
              ]"
            >
              <span class="text-2xl">{{ slot.has_rig ? '⛏️' : '🔲' }}</span>
              <div class="flex-1 text-left min-w-0">
                <div class="font-medium text-sm truncate">
                  Slot #{{ slot.slot_number }}
                  <span v-if="slot.rig_name" class="text-text-muted text-xs"> · {{ slot.rig_name }}</span>
                </div>
                <div class="flex items-center gap-2 text-[10px] text-text-muted">
                  <span :class="getTierColor(slot.tier)">{{ slot.tier }}</span>
                  <span>{{ slot.xp || 0 }}<template v-if="getSlotNextTierXp(slot.tier) > 0">/{{ getSlotNextTierXp(slot.tier) }}</template> XP</span>
                </div>
              </div>
              <div v-if="expPackSelectedSlot?.id === slot.id" class="text-emerald-400 text-lg">✓</div>
              <div v-else-if="slot.tier === 'elite'" class="text-[10px] text-text-muted">MAX</div>
            </button>

            <div v-if="!(miningStore.slotInfo?.slots ?? []).filter(s => !s.is_destroyed).length" class="text-center py-6 text-text-muted text-sm">
              {{ t('inventory.expPack.noSlots', 'No slots available') }}
            </div>
          </div>

          <div class="flex gap-2 mt-4">
            <button
              @click="showSlotSelect = false; expPackSelectedSlot = null"
              :disabled="applyingExpPack"
              class="flex-1 py-2.5 rounded-lg font-medium bg-bg-tertiary hover:bg-bg-tertiary/80 transition-colors disabled:opacity-50"
            >
              {{ t('common.cancel') }}
            </button>
            <button
              @click="confirmApplyExpPack"
              :disabled="!expPackSelectedSlot || applyingExpPack"
              class="flex-1 py-2.5 rounded-lg font-medium bg-emerald-500 text-white hover:bg-emerald-400 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
            >
              <span v-if="applyingExpPack" class="flex items-center justify-center gap-2">
                <span class="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin"></span>
              </span>
              <span v-else>{{ t('common.confirm', 'Confirmar') }}</span>
            </button>
          </div>
        </div>
      </div>

      <!-- Confirmation Dialog -->
      <div
        v-if="showConfirm && confirmAction"
        class="absolute inset-0 flex items-center justify-center bg-black/50 z-10"
      >
        <div class="bg-bg-secondary rounded-xl p-6 max-w-sm w-full mx-4 border border-border animate-fade-in">
          <!-- Card Redeem Confirmation -->
          <template v-if="confirmAction.type === 'redeem'">
            <div class="text-center mb-4">
              <div class="text-4xl mb-3">💳</div>
              <h3 class="text-lg font-bold mb-1">{{ t('inventory.confirm.redeemCard') }}</h3>
              <p class="text-text-muted text-sm">{{ t('inventory.confirm.areYouSure') }}</p>
            </div>

            <div class="bg-bg-primary rounded-lg p-4 mb-4">
              <div class="flex items-center justify-between mb-2">
                <span class="text-text-muted text-sm">{{ t('inventory.confirm.card') }}</span>
                <span class="font-medium text-white">{{ confirmAction.data.cardName }}</span>
              </div>
              <div class="flex items-center justify-between">
                <span class="text-text-muted text-sm">{{ t('inventory.confirm.rechargeAmount') }}</span>
                <span class="font-bold" :class="confirmAction.data.cardType === 'energy' ? 'text-status-warning' : 'text-accent-tertiary'">
                  +{{ confirmAction.data.cardAmount }}% {{ confirmAction.data.cardType === 'energy' ? t('welcome.energy') : t('welcome.internet') }}
                </span>
              </div>
            </div>

            <!-- 4-digit confirmation code -->
            <div class="bg-bg-primary rounded-lg p-4 mb-4">
              <p class="text-text-muted text-xs text-center mb-2">{{ t('inventory.confirm.enterCode', 'Ingresa el código para confirmar') }}</p>
              <div class="text-center mb-3">
                <span class="font-mono text-2xl font-bold tracking-[0.3em] text-accent-primary">{{ generatedCode }}</span>
              </div>
              <input
                v-model="inputCode"
                type="text"
                inputmode="numeric"
                maxlength="4"
                :placeholder="t('inventory.confirm.codePlaceholder', '----')"
                class="w-full text-center font-mono text-xl tracking-[0.3em] py-2 px-3 rounded-lg bg-bg-secondary border transition-colors outline-none"
                :class="inputCode.length === 4 && inputCode !== generatedCode
                  ? 'border-status-danger focus:border-status-danger'
                  : inputCode === generatedCode
                    ? 'border-status-success focus:border-status-success'
                    : 'border-border focus:border-accent-primary'"
                @keyup.enter="inputCode === generatedCode && confirmUse()"
              />
              <p v-if="inputCode.length === 4 && inputCode !== generatedCode" class="text-status-danger text-xs text-center mt-1">
                {{ t('inventory.confirm.codeError', 'Código incorrecto') }}
              </p>
            </div>
          </template>

          <!-- Rig Install Confirmation -->
          <template v-else-if="confirmAction.type === 'install_rig'">
            <div class="text-center mb-4">
              <div class="text-4xl mb-3">⛏️</div>
              <h3 class="text-lg font-bold mb-1">{{ t('inventory.confirm.installRig', 'Instalar Rig') }}</h3>
              <p class="text-text-muted text-sm">{{ t('inventory.confirm.areYouSure') }}</p>
            </div>

            <div class="bg-bg-primary rounded-lg p-4 mb-4">
              <div class="flex items-center justify-between mb-2">
                <span class="text-text-muted text-sm">Rig</span>
                <span class="font-medium text-white">{{ confirmAction.data.rigName }}</span>
              </div>
              <p class="text-xs text-text-muted/70 mt-2">
                {{ t('inventory.confirm.installRigNote', 'El rig se instalará en un slot disponible y comenzará a minar.') }}
              </p>
            </div>
          </template>

          <!-- Delete Item Confirmation -->
          <template v-else-if="confirmAction.type === 'delete_item'">
            <div class="text-center mb-4">
              <div class="text-4xl mb-3">🗑️</div>
              <h3 class="text-lg font-bold text-status-danger mb-1">{{ t('inventory.delete.title', 'Descartar Item') }}</h3>
              <p class="text-text-muted text-sm">{{ t('inventory.delete.warning', 'Esta acción no se puede deshacer') }}</p>
            </div>

            <div class="bg-bg-primary rounded-lg p-4 mb-4">
              <div class="flex items-center justify-between mb-2">
                <span class="text-text-muted text-sm">Item</span>
                <span class="font-medium text-white">{{ confirmAction.data.deleteItemName }}</span>
              </div>
              <!-- Quantity selector for stackable items -->
              <div v-if="(confirmAction.data.deleteMaxQuantity ?? 1) > 1" class="mt-3">
                <div class="flex items-center justify-between mb-1">
                  <span class="text-text-muted text-sm">{{ t('inventory.delete.quantity', 'Cantidad') }}</span>
                  <span class="font-mono text-sm text-white">{{ deleteQtyInput }} / {{ confirmAction.data.deleteMaxQuantity }}</span>
                </div>
                <div class="flex items-center gap-2">
                  <button
                    @click="deleteQtyInput = Math.max(1, deleteQtyInput - 1)"
                    class="w-8 h-8 rounded bg-bg-secondary border border-border text-white hover:bg-bg-tertiary transition-colors"
                  >-</button>
                  <input
                    v-model.number="deleteQtyInput"
                    type="range"
                    :min="1"
                    :max="confirmAction.data.deleteMaxQuantity"
                    class="flex-1 accent-status-danger"
                  />
                  <button
                    @click="deleteQtyInput = Math.min(confirmAction.data.deleteMaxQuantity ?? 1, deleteQtyInput + 1)"
                    class="w-8 h-8 rounded bg-bg-secondary border border-border text-white hover:bg-bg-tertiary transition-colors"
                  >+</button>
                </div>
                <button
                  @click="deleteQtyInput = confirmAction.data.deleteMaxQuantity ?? 1"
                  class="w-full mt-1 text-xs text-status-danger/70 hover:text-status-danger transition-colors"
                >
                  {{ t('inventory.delete.all', 'Seleccionar todo') }}
                </button>
              </div>
            </div>
          </template>

          <div class="flex gap-3">
            <button
              @click="cancelUse"
              class="flex-1 py-2.5 rounded-lg font-medium bg-bg-tertiary hover:bg-bg-tertiary/80 transition-colors"
            >
              {{ t('common.cancel') }}
            </button>
            <button
              @click="confirmUse"
              :disabled="using || (confirmAction?.type === 'redeem' && inputCode !== generatedCode)"
              class="flex-1 py-2.5 rounded-lg font-medium transition-colors disabled:opacity-50"
              :class="confirmAction?.type === 'delete_item'
                ? 'bg-status-danger text-white hover:bg-status-danger/80'
                : 'bg-accent-primary text-white hover:bg-accent-primary/80'"
            >
              {{ using ? t('common.processing') : t('common.confirm') }}
            </button>
          </div>
        </div>
      </div>

      <!-- Processing Modal -->
      <div
        v-if="showProcessingModal"
        class="absolute inset-0 flex items-center justify-center bg-black/70 z-20"
      >
        <div class="bg-bg-secondary rounded-xl p-6 max-w-sm w-full mx-4 border border-border animate-fade-in">
          <!-- Processing State -->
          <div v-if="processingStatus === 'processing'" class="text-center">
            <div class="relative w-16 h-16 mx-auto mb-4">
              <div class="absolute inset-0 border-4 border-accent-primary/20 rounded-full"></div>
              <div class="absolute inset-0 border-4 border-accent-primary border-t-transparent rounded-full animate-spin"></div>
            </div>
            <h3 class="text-lg font-bold mb-2">{{ t('inventory.processing.title') }}</h3>
            <p class="text-text-muted text-sm">{{ t('inventory.processing.wait') }}</p>
          </div>

          <!-- Error State -->
          <div v-else-if="processingStatus === 'error'" class="text-center">
            <div class="w-16 h-16 mx-auto mb-4 bg-status-danger/20 rounded-full flex items-center justify-center">
              <svg class="w-8 h-8 text-status-danger" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </div>
            <h3 class="text-lg font-bold text-status-danger mb-2">{{ t('inventory.processing.error') }}</h3>
            <p class="text-text-muted text-sm mb-4">{{ processingError }}</p>
            <button
              @click="closeProcessingModal"
              class="w-full py-2.5 rounded-lg font-medium bg-bg-tertiary hover:bg-bg-tertiary/80 transition-colors"
            >
              {{ t('common.close') }}
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- Cooling Workshop Modal -->
    <CoolingWorkshopModal
      :show="showWorkshop"
      :cooling-item="workshopItem"
      @close="closeWorkshop"
      @modded="onModded"
    />
  </Teleport>
</template>
