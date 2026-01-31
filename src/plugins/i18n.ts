import { createI18n } from 'vue-i18n';
import { en, es, supportedLocales, type SupportedLocale } from '@/locales';

const LOCALE_STORAGE_KEY = 'locale';

/**
 * Detect the user's preferred locale from browser settings
 */
function getDefaultLocale(): SupportedLocale {
  const browserLang = navigator.language.split('-')[0];

  if (supportedLocales.includes(browserLang as SupportedLocale)) {
    return browserLang as SupportedLocale;
  }

  // Default to English
  return 'en';
}

/**
 * Get the stored locale from localStorage or detect from browser
 */
function getStoredLocale(): SupportedLocale {
  const stored = localStorage.getItem(LOCALE_STORAGE_KEY);

  if (stored && supportedLocales.includes(stored as SupportedLocale)) {
    return stored as SupportedLocale;
  }

  return getDefaultLocale();
}

/**
 * Create the i18n instance
 */
export const i18n = createI18n({
  legacy: false, // Use Composition API
  locale: getStoredLocale(),
  fallbackLocale: 'en',
  messages: {
    en,
    es,
  },
});

/**
 * Change the current locale
 */
export function setLocale(locale: SupportedLocale): void {
  if (!supportedLocales.includes(locale)) {
    console.warn(`Locale "${locale}" is not supported`);
    return;
  }

  i18n.global.locale.value = locale;
  localStorage.setItem(LOCALE_STORAGE_KEY, locale);
  document.documentElement.lang = locale;
}

/**
 * Get the current locale
 */
export function getLocale(): SupportedLocale {
  return i18n.global.locale.value as SupportedLocale;
}

/**
 * Toggle between available locales
 */
export function toggleLocale(): SupportedLocale {
  const currentIndex = supportedLocales.indexOf(getLocale());
  const nextIndex = (currentIndex + 1) % supportedLocales.length;
  const nextLocale = supportedLocales[nextIndex];

  setLocale(nextLocale);
  return nextLocale;
}

// Set initial document language
document.documentElement.lang = getStoredLocale();
