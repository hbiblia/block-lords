import { createRouter, createWebHistory } from 'vue-router';
import { useAuthStore } from '@/stores/auth';

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes: [
    {
      path: '/',
      name: 'home',
      component: () => import('@/pages/HomePage.vue'),
    },
    {
      path: '/login',
      name: 'login',
      component: () => import('@/pages/LoginPage.vue'),
      meta: { guest: true },
    },
    {
      path: '/auth/callback',
      name: 'auth-callback',
      component: () => import('@/pages/AuthCallbackPage.vue'),
    },
    {
      path: '/setup-username',
      name: 'setup-username',
      component: () => import('@/pages/UsernameSetupPage.vue'),
    },
    {
      path: '/welcome',
      name: 'welcome',
      component: () => import('@/pages/WelcomePage.vue'),
      meta: { requiresAuth: true },
    },
    {
      path: '/dashboard',
      name: 'dashboard',
      component: () => import('@/pages/DashboardPage.vue'),
      meta: { requiresAuth: true },
    },
    {
      path: '/mining',
      name: 'mining',
      component: () => import('@/pages/MiningPageV2.vue'),
      // meta: { requiresAuth: true }, // TODO: restaurar auth después de probar ads
    },
    {
      path: '/mining-v1',
      name: 'mining-v1',
      component: () => import('@/pages/MiningPage.vue'),
    },
    {
      path: '/market',
      name: 'market',
      component: () => import('@/pages/MarketPage.vue'),
      meta: { requiresAuth: true },
    },
    {
      path: '/profile',
      name: 'profile',
      component: () => import('@/pages/ProfilePage.vue'),
      meta: { requiresAuth: true },
    },
    {
      path: '/admin',
      name: 'admin',
      component: () => import('@/pages/AdminPanel.vue'),
      meta: { requiresAuth: true, requiresAdmin: true },
    },
    {
      path: '/rules',
      name: 'rules',
      component: () => import('@/pages/RulesPage.vue'),
    },
    {
      path: '/terms',
      name: 'terms',
      component: () => import('@/pages/TermsPage.vue'),
    },
    {
      path: '/maintenance',
      name: 'maintenance',
      component: () => import('@/pages/MaintenancePage.vue'),
    },
    {
      path: '/:pathMatch(.*)*',
      name: 'not-found',
      component: () => import('@/pages/NotFoundPage.vue'),
    },
  ],
});

router.beforeEach(async (to, _from, next) => {
  const authStore = useAuthStore();
  const maintenanceMode = import.meta.env.VITE_MAINTENANCE_MODE === 'true';

  // Esperar a que auth esté inicializado
  await authStore.waitForInit();

  // Rutas que siempre deben ser accesible para permitir login de admins
  const isAuthRoute = ['login', 'auth-callback', 'setup-username'].includes(to.name as string);

  // Si estamos en mantenimiento y el usuario no es admin, redirigir a mantenimiento
  // (a menos que sea la propia página de mantenimiento o una ruta de autenticación)
  if (maintenanceMode && to.name !== 'maintenance' && authStore.player?.role !== 'admin' && !isAuthRoute) {
    next({ name: 'maintenance' });
    return;
  }

  // Si NO estamos en mantenimiento e intentamos entrar a la ruta de mantenimiento, redirigir al home
  if (!maintenanceMode && to.name === 'maintenance') {
    next({ name: 'home' });
    return;
  }

  // Capturar código de referido de la URL si existe
  const refCode = to.query.ref as string | undefined;
  if (refCode && refCode.length >= 6) {
    localStorage.setItem('pendingReferralCode', refCode.toUpperCase());
  }

  // Permitir acceso al callback y setup sin restricciones
  if (to.name === 'auth-callback' || to.name === 'setup-username') {
    next();
    return;
  }

  if (to.meta.requiresAuth && !authStore.isAuthenticated) {
    next({ name: 'login', query: { redirect: to.fullPath } });
  } else if (to.meta.requiresAdmin && authStore.player?.role !== 'admin') {
    // Redirigir a perfil si intenta acceder a panel admin sin ser admin
    next({ name: 'profile' });
  } else if (to.meta.guest && authStore.isAuthenticated) {
    next({ name: 'mining' });
  } else if (to.name === 'home' && authStore.isAuthenticated) {
    next({ name: 'welcome' });
  } else {
    next();
  }
});

export default router;
