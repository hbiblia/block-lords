/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{vue,js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        // Colores arcade/cyberpunk
        'arcade': {
          'bg': '#0a0a1a',
          'panel': '#12122a',
          'border': '#2a2a4a',
          'primary': '#00ff88',
          'secondary': '#00aaff',
          'warning': '#ffaa00',
          'danger': '#ff4444',
          'success': '#00ff88',
        },
        // Colores de reputación
        'rank': {
          'bronze': '#CD7F32',
          'silver': '#C0C0C0',
          'gold': '#FFD700',
          'platinum': '#E5E4E2',
          'diamond': '#B9F2FF',
        },
      },
      fontFamily: {
        'arcade': ['Press Start 2P', 'monospace'],
        'mono': ['JetBrains Mono', 'monospace'],
      },
      animation: {
        'pulse-fast': 'pulse 1s cubic-bezier(0.4, 0, 0.6, 1) infinite',
        'glow': 'glow 2s ease-in-out infinite alternate',
        'shake': 'shake 0.5s cubic-bezier(.36,.07,.19,.97) both',
      },
      keyframes: {
        glow: {
          'from': { boxShadow: '0 0 5px #00ff88, 0 0 10px #00ff88' },
          'to': { boxShadow: '0 0 20px #00ff88, 0 0 30px #00ff88' },
        },
        shake: {
          '10%, 90%': { transform: 'translate3d(-1px, 0, 0)' },
          '20%, 80%': { transform: 'translate3d(2px, 0, 0)' },
          '30%, 50%, 70%': { transform: 'translate3d(-4px, 0, 0)' },
          '40%, 60%': { transform: 'translate3d(4px, 0, 0)' },
        },
      },
    },
  },
  plugins: [],
}
