import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";

// base "./" keeps every asset path relative, so the build works on
// nest.potenfyr.in today and on any custom
// domain tomorrow without a rebuild.
export default defineConfig({
  base: "./",
  plugins: [react(), tailwindcss()],
  build: {
    outDir: "dist",
    emptyOutDir: true,
    target: "es2020",
  },
});
