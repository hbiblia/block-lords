import { createClient } from '@supabase/supabase-js';

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL ?? '';
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY ?? '';

export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  realtime: {
    params: {
      eventsPerSecond: 25,
    },
    heartbeatIntervalMs: 15000,
    reconnectAfterMs: (tries: number) => Math.min(1000 * Math.pow(1.5, tries), 30000),
  },
});
