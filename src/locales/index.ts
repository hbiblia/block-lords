import en from './en';
import es from './es';

export { en, es };

export const supportedLocales = ['en', 'es'] as const;
export type SupportedLocale = (typeof supportedLocales)[number];

export const localeNames: Record<SupportedLocale, string> = {
  en: 'English',
  es: 'Español',
};
