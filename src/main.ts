import { createApp } from 'vue';
import { createPinia } from 'pinia';
import FloatingVue from 'floating-vue';
import App from './App.vue';
import router from './router';
import { i18n } from './plugins/i18n';
import './assets/main.css';
import 'floating-vue/dist/style.css';

const app = createApp(App);

app.use(createPinia());
app.use(router);
app.use(i18n);
app.use(FloatingVue, {
  themes: {
    'info-tooltip': {
      $extend: 'tooltip',
      $resetCss: false,
    },
    tooltip: {
      html: true,
    },
  },
});

app.mount('#app');
