import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { readFileSync } from 'node:fs';

const pkg = JSON.parse(readFileSync(new URL('./package.json', import.meta.url), 'utf8'));
// carimbo automático da build (horário de Brasília) — muda a cada build/APK
const BUILD = new Intl.DateTimeFormat('pt-BR',{timeZone:'America/Sao_Paulo',day:'2-digit',month:'2-digit',hour:'2-digit',minute:'2-digit'}).format(new Date()).replace(',', '');

export default defineConfig({
  plugins: [react()],
  define: {
    __APP_VERSION__: JSON.stringify(pkg.version),
    __APP_BUILD__: JSON.stringify(BUILD),
  },
  // Quando builda pro GitHub Pages (site fica em usuario.github.io/Stokk-app/),
  // os arquivos precisam ser referenciados com esse prefixo. No APK e no dev
  // local isso não é usado, então fica '/' normal.
  base: process.env.GH_PAGES ? '/Stokk-app/' : '/',
});
