<script setup lang="ts">
import { computed } from 'vue';
import { useAuthStore } from '@/stores/auth';

const authStore = useAuthStore();
const isAuthenticated = computed(() => authStore.isAuthenticated);
</script>

<template>
  <div class="py-12">
    <!-- Hero Section -->
    <div class="text-center mb-20">
      <div class="inline-block mb-6">
        <span class="badge-primary text-sm">MMO de Minería</span>
      </div>
      <h1 class="font-display text-4xl md:text-6xl font-bold mb-6">
        <span class="gradient-text">BLOCK LORDS</span>
      </h1>
      <p class="text-xl text-text-secondary max-w-2xl mx-auto mb-10">
        Compite en tiempo real minando bloques. Economía zero-sum, mercado libre P2P y sistema de reputación.
      </p>

      <div v-if="!isAuthenticated" class="flex justify-center">
        <RouterLink to="/login" class="btn-primary text-lg px-8 py-4">
          Comenzar a Minar
        </RouterLink>
      </div>
      <div v-else>
        <RouterLink to="/mining" class="btn-primary text-lg px-8 py-4">
          Comenzar a Minar
        </RouterLink>
      </div>
    </div>

    <!-- Features -->
    <div class="grid md:grid-cols-3 gap-6 mb-20">
      <div class="card-hover group">
        <div class="w-14 h-14 rounded-xl bg-gradient-primary flex items-center justify-center text-2xl mb-4 group-hover:scale-110 transition-transform">
          ⛏️
        </div>
        <h3 class="text-xl font-semibold text-white mb-3">Minería en Tiempo Real</h3>
        <p class="text-text-secondary">
          Compite contra otros jugadores por bloques. La dificultad se ajusta dinámicamente según la actividad de la red.
        </p>
      </div>

      <div class="card-hover group">
        <div class="w-14 h-14 rounded-xl bg-gradient-secondary flex items-center justify-center text-2xl mb-4 group-hover:scale-110 transition-transform">
          💰
        </div>
        <h3 class="text-xl font-semibold text-white mb-3">Economía Zero-Sum</h3>
        <p class="text-text-secondary">
          Todo el dinero que ganas, alguien más lo perdió. Mercado P2P real con precios libres entre jugadores.
        </p>
      </div>

      <div class="card-hover group">
        <div class="w-14 h-14 rounded-xl bg-gradient-to-br from-status-warning to-orange-500 flex items-center justify-center text-2xl mb-4 group-hover:scale-110 transition-transform">
          ⭐
        </div>
        <h3 class="text-xl font-semibold text-white mb-3">Sistema de Reputación</h3>
        <p class="text-text-secondary">
          Tu reputación afecta tu eficiencia. Sube de rango: Bronce → Plata → Oro → Platino → Diamante.
        </p>
      </div>
    </div>

    <!-- How it Works -->
    <div class="card max-w-5xl mx-auto mb-20">
      <h2 class="text-2xl font-display font-bold text-center mb-8">
        <span class="gradient-text">¿Cómo funciona?</span>
      </h2>

      <div class="grid md:grid-cols-4 gap-4">
        <div class="relative p-5 rounded-xl bg-bg-secondary border border-border/50">
          <div class="absolute -top-3 -left-3 w-8 h-8 rounded-lg bg-gradient-primary flex items-center justify-center text-sm font-bold">
            1
          </div>
          <h4 class="font-semibold text-white mt-2 mb-2">Regístrate</h4>
          <p class="text-sm text-text-muted">
            Conecta con Google y recibe 100 GameCoin + un rig básico gratis.
          </p>
        </div>

        <div class="relative p-5 rounded-xl bg-bg-secondary border border-border/50">
          <div class="absolute -top-3 -left-3 w-8 h-8 rounded-lg bg-gradient-primary flex items-center justify-center text-sm font-bold">
            2
          </div>
          <h4 class="font-semibold text-white mt-2 mb-2">Mina</h4>
          <p class="text-sm text-text-muted">
            Activa tus rigs y compite por bloques. Gana CryptoCoin cada vez que minas.
          </p>
        </div>

        <div class="relative p-5 rounded-xl bg-bg-secondary border border-border/50">
          <div class="absolute -top-3 -left-3 w-8 h-8 rounded-lg bg-gradient-primary flex items-center justify-center text-sm font-bold">
            3
          </div>
          <h4 class="font-semibold text-white mt-2 mb-2">Comercia</h4>
          <p class="text-sm text-text-muted">
            Vende tu CryptoCoin, compra mejores rigs y negocia con otros jugadores.
          </p>
        </div>

        <div class="relative p-5 rounded-xl bg-bg-secondary border border-border/50">
          <div class="absolute -top-3 -left-3 w-8 h-8 rounded-lg bg-gradient-primary flex items-center justify-center text-sm font-bold">
            4
          </div>
          <h4 class="font-semibold text-white mt-2 mb-2">Prospera</h4>
          <p class="text-sm text-text-muted">
            Sube tu reputación, accede a pools premium y retira tus ganancias.
          </p>
        </div>
      </div>
    </div>

    <!-- Live Stats Preview -->
    <div class="grid md:grid-cols-4 gap-4 max-w-4xl mx-auto">
      <div class="stat-card">
        <div class="stat-value gradient-text">1,234</div>
        <div class="stat-label">Jugadores Online</div>
      </div>
      <div class="stat-card">
        <div class="stat-value text-accent-tertiary">45,678</div>
        <div class="stat-label">Bloques Minados</div>
      </div>
      <div class="stat-card">
        <div class="stat-value text-status-warning">$12.5K</div>
        <div class="stat-label">Volumen 24h</div>
      </div>
      <div class="stat-card">
        <div class="stat-value text-accent-secondary">1,892</div>
        <div class="stat-label">Dificultad</div>
      </div>
    </div>
  </div>
</template>
