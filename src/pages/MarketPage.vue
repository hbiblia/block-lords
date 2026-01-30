<script setup lang="ts">
import { ref, onMounted } from 'vue';
import { useAuthStore } from '@/stores/auth';

const authStore = useAuthStore();

const loading = ref(true);
const activeTab = ref<'crypto' | 'rigs' | 'resources'>('crypto');

const orderBook = ref<{
  bids: any[];
  asks: any[];
}>({ bids: [], asks: [] });

const myOrders = ref<any[]>([]);
const marketStats = ref<any>({});

// Form state
const orderType = ref<'buy' | 'sell'>('buy');
const orderQuantity = ref(1);
const orderPrice = ref(1);

async function loadData() {
  try {
    // Load order book
    const bookResponse = await fetch(`/api/market/orderbook/${activeTab.value}`);
    if (bookResponse.ok) {
      orderBook.value = await bookResponse.json();
    }

    // Load my orders
    const ordersResponse = await fetch('/api/market/orders', {
      headers: { 'Authorization': `Bearer ${authStore.token}` },
    });
    if (ordersResponse.ok) {
      myOrders.value = await ordersResponse.json();
    }

    // Load market stats
    const statsResponse = await fetch('/api/market/stats');
    if (statsResponse.ok) {
      marketStats.value = await statsResponse.json();
    }
  } catch (e) {
    console.error('Error loading market data:', e);
  } finally {
    loading.value = false;
  }
}

async function createOrder() {
  try {
    const response = await fetch('/api/market/orders', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${authStore.token}`,
      },
      body: JSON.stringify({
        type: orderType.value,
        itemType: activeTab.value,
        quantity: orderQuantity.value,
        pricePerUnit: orderPrice.value,
      }),
    });

    if (response.ok) {
      await loadData();
      orderQuantity.value = 1;
      orderPrice.value = 1;
    } else {
      const data = await response.json();
      alert(data.error ?? 'Error al crear orden');
    }
  } catch (e) {
    console.error('Error creating order:', e);
  }
}

async function cancelOrder(orderId: string) {
  try {
    const response = await fetch(`/api/market/orders/${orderId}`, {
      method: 'DELETE',
      headers: { 'Authorization': `Bearer ${authStore.token}` },
    });

    if (response.ok) {
      await loadData();
    }
  } catch (e) {
    console.error('Error cancelling order:', e);
  }
}

function changeTab(tab: 'crypto' | 'rigs' | 'resources') {
  activeTab.value = tab;
  loading.value = true;
  loadData();
}

onMounted(loadData);
</script>

<template>
  <div>
    <h1 class="text-2xl text-arcade-primary mb-6">Mercado</h1>

    <!-- Tabs -->
    <div class="flex gap-4 mb-6 border-b border-arcade-border">
      <button
        @click="changeTab('crypto')"
        class="pb-2 px-4 transition-colors"
        :class="activeTab === 'crypto' ? 'text-arcade-primary border-b-2 border-arcade-primary' : 'text-gray-400 hover:text-white'"
      >
        CryptoCoin
      </button>
      <button
        @click="changeTab('rigs')"
        class="pb-2 px-4 transition-colors"
        :class="activeTab === 'rigs' ? 'text-arcade-primary border-b-2 border-arcade-primary' : 'text-gray-400 hover:text-white'"
      >
        Rigs
      </button>
      <button
        @click="changeTab('resources')"
        class="pb-2 px-4 transition-colors"
        :class="activeTab === 'resources' ? 'text-arcade-primary border-b-2 border-arcade-primary' : 'text-gray-400 hover:text-white'"
      >
        Recursos
      </button>
    </div>

    <div v-if="loading" class="text-center py-12 text-gray-400">
      Cargando...
    </div>

    <div v-else class="grid lg:grid-cols-3 gap-6">
      <!-- Order Book -->
      <div class="lg:col-span-2">
        <div class="arcade-panel">
          <h2 class="text-lg text-arcade-primary mb-4">Libro de Órdenes</h2>

          <div class="grid grid-cols-2 gap-4">
            <!-- Bids (Buy orders) -->
            <div>
              <h3 class="text-sm text-arcade-success mb-2">Compra (Bids)</h3>
              <div class="space-y-1 text-sm">
                <div class="flex justify-between text-xs text-gray-500 pb-1 border-b border-arcade-border">
                  <span>Precio</span>
                  <span>Cantidad</span>
                </div>
                <div
                  v-for="bid in orderBook.bids.slice(0, 10)"
                  :key="bid.id"
                  class="flex justify-between text-arcade-success"
                >
                  <span>{{ bid.price_per_unit.toFixed(4) }}</span>
                  <span>{{ bid.remaining_quantity.toFixed(2) }}</span>
                </div>
                <div v-if="orderBook.bids.length === 0" class="text-gray-500 text-center py-4">
                  Sin órdenes de compra
                </div>
              </div>
            </div>

            <!-- Asks (Sell orders) -->
            <div>
              <h3 class="text-sm text-arcade-danger mb-2">Venta (Asks)</h3>
              <div class="space-y-1 text-sm">
                <div class="flex justify-between text-xs text-gray-500 pb-1 border-b border-arcade-border">
                  <span>Precio</span>
                  <span>Cantidad</span>
                </div>
                <div
                  v-for="ask in orderBook.asks.slice(0, 10)"
                  :key="ask.id"
                  class="flex justify-between text-arcade-danger"
                >
                  <span>{{ ask.price_per_unit.toFixed(4) }}</span>
                  <span>{{ ask.remaining_quantity.toFixed(2) }}</span>
                </div>
                <div v-if="orderBook.asks.length === 0" class="text-gray-500 text-center py-4">
                  Sin órdenes de venta
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- My Orders -->
        <div class="arcade-panel mt-6">
          <h2 class="text-lg text-arcade-primary mb-4">Mis Órdenes</h2>

          <div v-if="myOrders.length === 0" class="text-center py-4 text-gray-400">
            No tienes órdenes activas
          </div>

          <div v-else class="space-y-2">
            <div
              v-for="order in myOrders"
              :key="order.id"
              class="flex items-center justify-between p-3 bg-arcade-bg rounded"
            >
              <div>
                <span
                  class="text-sm font-bold"
                  :class="order.type === 'buy' ? 'text-arcade-success' : 'text-arcade-danger'"
                >
                  {{ order.type === 'buy' ? 'COMPRA' : 'VENTA' }}
                </span>
                <span class="text-sm text-gray-400 ml-2">
                  {{ order.remaining_quantity }} @ {{ order.price_per_unit.toFixed(4) }}
                </span>
              </div>
              <button
                @click="cancelOrder(order.id)"
                class="text-xs px-3 py-1 bg-arcade-danger/20 text-arcade-danger rounded hover:bg-arcade-danger/30"
              >
                Cancelar
              </button>
            </div>
          </div>
        </div>
      </div>

      <!-- Create Order -->
      <div class="space-y-6">
        <div class="arcade-panel">
          <h2 class="text-lg text-arcade-primary mb-4">Crear Orden</h2>

          <div class="space-y-4">
            <!-- Order Type -->
            <div class="flex gap-2">
              <button
                @click="orderType = 'buy'"
                class="flex-1 py-2 rounded transition-colors"
                :class="orderType === 'buy' ? 'bg-arcade-success text-arcade-bg' : 'bg-arcade-bg text-gray-400'"
              >
                Comprar
              </button>
              <button
                @click="orderType = 'sell'"
                class="flex-1 py-2 rounded transition-colors"
                :class="orderType === 'sell' ? 'bg-arcade-danger text-white' : 'bg-arcade-bg text-gray-400'"
              >
                Vender
              </button>
            </div>

            <!-- Quantity -->
            <div>
              <label class="block text-sm text-gray-400 mb-1">Cantidad</label>
              <input
                v-model.number="orderQuantity"
                type="number"
                min="0.01"
                step="0.01"
                class="arcade-input"
              />
            </div>

            <!-- Price -->
            <div>
              <label class="block text-sm text-gray-400 mb-1">Precio por unidad</label>
              <input
                v-model.number="orderPrice"
                type="number"
                min="0.0001"
                step="0.0001"
                class="arcade-input"
              />
            </div>

            <!-- Total -->
            <div class="flex justify-between text-sm py-2 border-t border-arcade-border">
              <span class="text-gray-400">Total</span>
              <span class="font-bold">{{ (orderQuantity * orderPrice).toFixed(4) }} GC</span>
            </div>

            <button
              @click="createOrder"
              class="w-full"
              :class="orderType === 'buy' ? 'arcade-button' : 'arcade-button-danger'"
            >
              {{ orderType === 'buy' ? 'Crear Orden de Compra' : 'Crear Orden de Venta' }}
            </button>
          </div>
        </div>

        <!-- Market Stats -->
        <div class="arcade-panel">
          <h2 class="text-lg text-arcade-primary mb-4">Estadísticas 24h</h2>
          <div class="space-y-2 text-sm">
            <div class="flex justify-between">
              <span class="text-gray-400">Último precio</span>
              <span>{{ marketStats[activeTab]?.lastPrice?.toFixed(4) ?? '-' }}</span>
            </div>
            <div class="flex justify-between">
              <span class="text-gray-400">Máximo</span>
              <span class="text-arcade-success">{{ marketStats[activeTab]?.high?.toFixed(4) ?? '-' }}</span>
            </div>
            <div class="flex justify-between">
              <span class="text-gray-400">Mínimo</span>
              <span class="text-arcade-danger">{{ marketStats[activeTab]?.low?.toFixed(4) ?? '-' }}</span>
            </div>
            <div class="flex justify-between">
              <span class="text-gray-400">Volumen</span>
              <span>{{ marketStats[activeTab]?.volume?.toFixed(2) ?? '-' }} GC</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
