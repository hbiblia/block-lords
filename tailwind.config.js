/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{vue,js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        // Paleta Kawaii Dark - Purple base + Cute accents
        'bg': {
          'primary': '#1a1528',
          'secondary': '#231d35',
          'tertiary': '#2d2545',
          'card': '#1f1833',
        },
        'accent': {
          'primary': '#c4a0e8',    // Lavender
          'secondary': '#b088d0',  // Purple
          'tertiary': '#ffe566',   // Yellow cute
          'gradient': 'linear-gradient(135deg, #c4a0e8 0%, #b088d0 100%)',
        },
        'text': {
          'primary': '#f0e4ff',
          'secondary': '#b8a0d0',
          'muted': '#8a70a8',
        },
        'border': {
          'DEFAULT': '#4a3660',
          'light': '#5c4578',
        },
        'status': {
          'success': '#7cc490',
          'warning': '#ffe566',
          'danger': '#e87c8a',
          'info': '#8ab4f8',
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
        'glow': '0 0 20px rgba(196, 160, 232, 0.3)',
        'glow-amber': '0 0 20px rgba(176, 136, 208, 0.3)',
        'glow-purple': '0 0 20px rgba(196, 160, 232, 0.4)',
        'card': '0 4px 20px rgba(0, 0, 0, 0.25)',
        'card-hover': '0 8px 30px rgba(0, 0, 0, 0.35)',
        'kawaii': '3px 3px 0 rgba(196, 160, 232, 0.2)',
      },
      backgroundImage: {
        'gradient-radial': 'radial-gradient(ellipse at center, var(--tw-gradient-stops))',
        'gradient-primary': 'linear-gradient(135deg, #c4a0e8 0%, #b088d0 100%)',
        'gradient-secondary': 'linear-gradient(135deg, #ffe566 0%, #c4a0e8 100%)',
        'gradient-dark': 'linear-gradient(180deg, #1a1528 0%, #231d35 100%)',
      },
      animation: {
        'pulse-slow': 'pulse 3s cubic-bezier(0.4, 0, 0.6, 1) infinite',
        'glow': 'glow 2s ease-in-out infinite alternate',
        'float': 'float 3s ease-in-out infinite',
        'shimmer': 'shimmer 2s linear infinite',
      },
      keyframes: {
        glow: {
          'from': { boxShadow: '0 0 10px rgba(196, 160, 232, 0.3)' },
          'to': { boxShadow: '0 0 25px rgba(196, 160, 232, 0.5)' },
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
