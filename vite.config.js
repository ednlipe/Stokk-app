import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const pkg = JSON.parse(readFileSync(new URL('./package.json', import.meta.url), 'utf8'));
// carimbo automático da build (horário de Brasília) — muda a cada build/APK
const BUILD = new Intl.DateTimeFormat('pt-BR',{timeZone:'America/Sao_Paulo',day:'2-digit',month:'2-digit',hour:'2-digit',minute:'2-digit'}).format(new Date()).replace(',', '');

/* ================= AMBIENTES (produção × teste) — ver docs/ambiente-teste.md =================
   Qual banco Supabase o app e o desktop usam é decidido AQUI, pelo "mode" do Vite:
     npm run dev            -> TESTE     (desenvolvimento no PC nunca grava na produção)
     npm run dev:producao   -> PRODUÇÃO  (só para conferir algo; cuidado)
     npm run build          -> PRODUÇÃO  (é o que o GitHub usa para o site e o APK da master)
     npm run build:teste    -> TESTE
   URL e anon key ficam em ambientes.json. O app recebe por __SUPABASE_URL__/__SUPABASE_ANON_KEY__;
   o desktop (public/desktop/index.html, que o Vite não processa) é reescrito no fim da build e no
   servidor de desenvolvimento. Se a troca do desktop falhar, a build PARA (para nunca sair um site
   "de teste" gravando na produção). */
const AMBIENTES = JSON.parse(readFileSync(new URL('./ambientes.json', import.meta.url), 'utf8'));
function ambienteDoModo(mode){
  if (mode === 'teste' || mode === 'development') return 'teste';
  if (mode === 'producao' || mode === 'production') return 'producao';
  throw new Error('STOKK: mode "'+mode+'" desconhecido. Use teste ou producao.');
}
const FAIXA_TESTE = '<div id="faixa-ambiente-teste" style="position:fixed;top:0;left:0;right:0;z-index:2147483647;'
  + 'background:#c62828;color:#fff;font:700 11px/16px sans-serif;letter-spacing:1px;text-align:center;'
  + 'pointer-events:none;opacity:.92;">AMBIENTE DE TESTE · não é a produção</div>';

function desktopNoAmbiente(html, nomeAmb, amb, prod){
  if (nomeAmb === 'producao') return html;
  if (!html.includes(prod.url) || !html.includes(prod.anonKey))
    throw new Error('STOKK: não achei a URL/anon key da produção em public/desktop/index.html para trocar pelo teste. Confira ambientes.json.');
  const novo = html.split(prod.url).join(amb.url).split(prod.anonKey).join(amb.anonKey)
    .replace('<title>', '<title>[TESTE] ').replace(/<body([^>]*)>/, m => m + FAIXA_TESTE);
  if (novo.includes(prod.url) || novo.includes(prod.anonKey)) throw new Error('STOKK: o desktop de teste ainda aponta para a produção.');
  return novo;
}

export default defineConfig(({ mode }) => {
  const nomeAmb = ambienteDoModo(mode);
  const amb = AMBIENTES[nomeAmb], prod = AMBIENTES.producao;
  if (!amb || !amb.url || !amb.anonKey)
    throw new Error('STOKK: o ambiente "'+nomeAmb+'" está sem url/anonKey em ambientes.json'
      + (nomeAmb === 'teste' ? ' (o projeto Supabase de teste ainda não foi configurado; para usar a produção: npm run dev:producao).' : '.'));
  if (nomeAmb === 'teste' && amb.url === prod.url) throw new Error('STOKK: o ambiente de teste está com a URL da produção.');
  let outDir = resolve(process.cwd(), 'dist');   // trocado pelo outDir real em configResolved (ex.: --outDir)
  console.log('\n  STOKK › ambiente: ' + amb.nome.toUpperCase() + ' (' + amb.url + ')\n');

  return {
    plugins: [
      react(),
      {
        name: 'stokk-desktop-ambiente',
        configResolved(cfg){ outDir = resolve(cfg.root, cfg.build.outDir); },
        configureServer(server){
          server.middlewares.use((req, res, next)=>{
            const caminho = (req.url || '').split('?')[0];
            if (!/\/desktop\/(index\.html)?$/.test(caminho)) return next();
            const html = readFileSync(new URL('./public/desktop/index.html', import.meta.url), 'utf8');
            res.setHeader('Content-Type', 'text/html; charset=utf-8');
            res.end(desktopNoAmbiente(html, nomeAmb, amb, prod));
          });
        },
        closeBundle(){
          const f = resolve(outDir, 'desktop', 'index.html');
          if (existsSync(f)) writeFileSync(f, desktopNoAmbiente(readFileSync(f, 'utf8'), nomeAmb, amb, prod));
        },
      },
    ],
    define: {
      __APP_VERSION__: JSON.stringify(pkg.version),
      __APP_BUILD__: JSON.stringify(BUILD),
      // "dono/repositório" do GitHub (no Actions vem pronto): o app procura aqui o aviso de nova versão do APK
      __REPO__: JSON.stringify(process.env.GITHUB_REPOSITORY || ''),
      __AMBIENTE__: JSON.stringify(nomeAmb),
      // pasta do APK no site da Cloudflare (ambientes.json › atualizacao); vazio = aviso de atualização pela Release do GitHub
      __ATU_BASE__: JSON.stringify(amb.atualizacao || ''),
      __SUPABASE_URL__: JSON.stringify(amb.url),
      __SUPABASE_ANON_KEY__: JSON.stringify(amb.anonKey),
    },
    // Quando builda pro GitHub Pages (site fica em usuario.github.io/Stokk-app/),
    // os arquivos precisam ser referenciados com esse prefixo. No APK e no dev
    // local isso não é usado, então fica '/' normal. (O site de teste usa GH_PAGES_BASE.)
    base: process.env.GH_PAGES_BASE || (process.env.GH_PAGES ? '/Stokk-app/' : '/'),
  };
});
