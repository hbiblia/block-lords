/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{vue,js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        // Paleta estilo Axie Infinity
        'bg': {
          'primary': '#1a1b2e',
          'secondary': '#252640',
          'tertiary': '#2f3052',
          'card': '#1e1f36',
        },
        'accent': {
          'primary': '#8b5cf6',    // Púrpura
          'secondary': '#ec4899',  // Rosa
          'tertiary': '#06b6d4',   // Cyan
          'gradient': 'linear-gradient(135deg, #8b5cf6 0%, #ec4899 100%)',
        },
        'text': {
          'primary': '#ffffff',
          'secondary': '#a1a1aa',
          'muted': '#71717a',
        },
        'border': {
          'DEFAULT': '#3f3f5c',
          'light': '#4f4f6f',
        },
        'status': {
          'success': '#22c55e',
          'warning': '#f59e0b',
          'danger': '#ef4444',
          'info': '#3b82f6',
        },
        // Colores de reputación/rangos
        'rank': {
          'bronze': '#CD7F32',
          'silver': '#C0C0C0',
          'gold': '#FFD700',
          'platinum': '#E5E4E2',
          'diamond': '#B9F2FF',
        },
      },
      fontFamily: {
        'display': ['Poppins', 'sans-serif'],
        'body': ['Inter', 'sans-serif'],
        'mono': ['JetBrains Mono', 'monospace'],
      },
      borderRadius: {
        'xl': '1rem',
        '2xl': '1.5rem',
      },
      boxShadow: {
        'glow': '0 0 20px rgba(139, 92, 246, 0.3)',
        'glow-pink': '0 0 20px rgba(236, 72, 153, 0.3)',
        'card': '0 4px 20px rgba(0, 0, 0, 0.25)',
        'card-hover': '0 8px 30px rgba(0, 0, 0, 0.35)',
      },
      backgroundImage: {
        'gradient-radial': 'radial-gradient(ellipse at center, var(--tw-gradient-stops))',
        'gradient-primary': 'linear-gradient(135deg, #8b5cf6 0%, #ec4899 100%)',
        'gradient-secondary': 'linear-gradient(135deg, #06b6d4 0%, #8b5cf6 100%)',
        'gradient-dark': 'linear-gradient(180deg, #1a1b2e 0%, #252640 100%)',
      },
      animation: {
        'pulse-slow': 'pulse 3s cubic-bezier(0.4, 0, 0.6, 1) infinite',
        'glow': 'glow 2s ease-in-out infinite alternate',
        'float': 'float 3s ease-in-out infinite',
        'shimmer': 'shimmer 2s linear infinite',
      },
      keyframes: {
        glow: {
          'from': { boxShadow: '0 0 10px rgba(139, 92, 246, 0.3)' },
          'to': { boxShadow: '0 0 25px rgba(139, 92, 246, 0.5)' },
        },
        float: {
          '0%, 100%': { transform: 'translateY(0)' },
          '50%': { transform: 'translateY(-10px)' },
        },
        shimmer: {
          '0%': { backgroundPosition: '-200% 0' },
          '100%': { backgroundPosition: '200% 0' },
        },
      },
    },
  },
  plugins: [],
}
