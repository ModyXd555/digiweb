import type { Config } from "tailwindcss";
export default {
  content: ["./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: { vault: "#08090D", panel: "#12141B", line: "#23263A", accent: "#8065FF" },
      fontFamily: { display: ["var(--font-display)"], sans: ["var(--font-body)"] },
    },
  },
  plugins: [],
} satisfies Config;
