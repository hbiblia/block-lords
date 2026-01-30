<script setup lang="ts">
import { computed } from 'vue';
import { useAuthStore } from '@/stores/auth';

const authStore = useAuthStore();
const isAuthenticated = computed(() => authStore.isAuthenticated);
</script>

<template>
  <div class="text-center py-12">
    <!-- Hero Section -->
    <div class="mb-16">
      <h1 class="font-arcade text-3xl md:text-5xl text-arcade-primary mb-6 animate-glow">
        CRYPTO ARCADE
      </h1>
      <p class="text-xl text-gray-400 max-w-2xl mx-auto mb-8">
        Juego MMO persistente de minería de criptomonedas.
        Economía zero-sum, mercado libre y sistema de reputación.
      </p>

      <div v-if="!isAuthenticated" class="flex justify-center gap-4">
        <RouterLink to="/register" class="arcade-button text-lg px-8 py-3">
          Comenzar a Minar
        </RouterLink>
        <RouterLink to="/login" class="arcade-button-secondary text-lg px-8 py-3">
          Iniciar Sesión
        </RouterLink>
      </div>
      <div v-else>
        <RouterLink to="/dashboard" class="arcade-button text-lg px-8 py-3">
          Ir al Dashboard
        </RouterLink>
      </div>
    </div>

    <!-- Features -->
    <div class="grid md:grid-cols-3 gap-8 mb-16">
      <div class="arcade-panel">
        <div class="text-4xl mb-4">⛏️</div>
        <h3 class="text-xl text-arcade-primary mb-2">Minería Arcade</h3>
        <p class="text-gray-400">
          Compite en tiempo real por bloques. La dificultad se ajusta según la red.
          Gestiona energía e internet para maximizar tus ganancias.
        </p>
      </div>

      <div class="arcade-panel">
        <div class="text-4xl mb-4">💰</div>
        <h3 class="text-xl text-arcade-primary mb-2">Economía Zero-Sum</h3>
        <p class="text-gray-400">
          Todo el dinero que ganas, alguien más lo perdió.
          Mercado P2P real con precios libres.
          Convierte GameCoin a dinero real.
        </p>
      </div>

      <div class="arcade-panel">
        <div class="text-4xl mb-4">⭐</div>
        <h3 class="text-xl text-arcade-primary mb-2">Sistema de Reputación</h3>
        <p class="text-gray-400">
          Tu reputación afecta tu eficiencia de minado.
          Sube de rango: Bronce → Plata → Oro → Platino → Diamante.
          Accede a pools exclusivos.
        </p>
      </div>
    </div>

    <!-- How it Works -->
    <div class="arcade-panel max-w-4xl mx-auto">
      <h2 class="text-2xl text-arcade-primary mb-6">¿Cómo funciona?</h2>

      <div class="grid md:grid-cols-4 gap-4 text-left">
        <div class="p-4 border border-arcade-border rounded">
          <div class="text-arcade-secondary font-bold mb-2">1. Regístrate</div>
          <p class="text-sm text-gray-400">
            Crea tu cuenta y recibe 100 GameCoin + un rig básico gratis.
          </p>
        </div>

        <div class="p-4 border border-arcade-border rounded">
          <div class="text-arcade-secondary font-bold mb-2">2. Mina</div>
          <p class="text-sm text-gray-400">
            Activa tus rigs y compite por bloques. Gana CryptoCoin.
          </p>
        </div>

        <div class="p-4 border border-arcade-border rounded">
          <div class="text-arcade-secondary font-bold mb-2">3. Comercia</div>
          <p class="text-sm text-gray-400">
            Vende tu CryptoCoin, compra rigs mejores, negocia con otros jugadores.
          </p>
        </div>

        <div class="p-4 border border-arcade-border rounded">
          <div class="text-arcade-secondary font-bold mb-2">4. Prospera</div>
          <p class="text-sm text-gray-400">
            Sube tu reputación, accede a pools premium y retira ganancias.
          </p>
        </div>
      </div>
    </div>

    <!-- Live Stats Preview -->
    <div class="mt-16 grid md:grid-cols-4 gap-4 max-w-4xl mx-auto">
      <div class="arcade-panel text-center">
        <div class="text-3xl text-arcade-primary font-bold">1,234</div>
        <div class="text-sm text-gray-400">Jugadores Online</div>
      </div>
      <div class="arcade-panel text-center">
        <div class="text-3xl text-arcade-secondary font-bold">45,678</div>
        <div class="text-sm text-gray-400">Bloques Minados</div>
      </div>
      <div class="arcade-panel text-center">
        <div class="text-3xl text-arcade-warning font-bold">$12.5K</div>
        <div class="text-sm text-gray-400">Volumen 24h</div>
      </div>
      <div class="arcade-panel text-center">
        <div class="text-3xl text-arcade-primary font-bold">1,892</div>
        <div class="text-sm text-gray-400">Dificultad</div>
      </div>
    </div>
  </div>
</template>
