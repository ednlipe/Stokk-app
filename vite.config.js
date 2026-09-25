import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  // Quando builda pro GitHub Pages (site fica em usuario.github.io/Stokk-app/),
  // os arquivos precisam ser referenciados com esse prefixo. No APK e no dev
  // local isso não é usado, então fica '/' normal.
  base: process.env.GH_PAGES ? '/Stokk-app/' : '/',
});
