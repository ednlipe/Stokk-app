# STOKK — Ambiente de teste

> Para testar mudanças **antes** de chegarem ao app que a fábrica usa.
> Índice geral: [`docs/README.md`](README.md). Regra: mudou algo desta área, atualize ESTE arquivo e uma linha em [`historico.md`](historico.md).
> **Status (23/11/2026):** projeto `stokk-teste` (`jxqhsdhohuqfigdvmbyx`, região ca-central-1) criado e **montado** pelo script (estrutura, extras e cadastros sem erro); conta de teste `teste@teste.com` ativa. `npm run dev` conferido: app e desktop apontam só para o teste, com a faixa. Login e uso das telas no teste ainda não conferidos. Site de teste e APK de teste ainda não existem (ver "Próximas etapas").

## Como funciona

| | Produção | Teste |
|---|---|---|
| Branch do git | `master` | `teste` |
| Banco Supabase | projeto atual (`vjzqzmigifjdxftwmxew`) | projeto `stokk-teste` (só cadastros e contas de teste) |
| Comando no PC | `npm run dev:producao` (cuidado: grava na produção) | **`npm run dev`** (padrão) |
| Build | `npm run build` (é o que o GitHub usa para o site e o APK da `master`) | `npm run build:teste` |
| Na tela | normal | **faixa vermelha "AMBIENTE DE TESTE"** no topo e `[TESTE]` no título (app e desktop) |

- **Quem escolhe o banco:** `vite.config.js`, pelo *mode* do Vite (`development`/`teste` → teste; `production`/`producao` → produção). URL e anon key de cada banco ficam em **`ambientes.json`** (só dados públicos: nunca `service_role`, senha ou `CRON_SECRET`).
- **App (`src/App.jsx`):** lê `__AMBIENTE__`, `__SUPABASE_URL__` e `__SUPABASE_ANON_KEY__` (definidos na build). Não escreva URL/chave no código.
- **Desktop (`public/desktop/index.html`):** o Vite não processa esse arquivo, então o plugin `stokk-desktop-ambiente` (no `vite.config.js`) troca a URL/chave da produção pelas do teste no fim da build e no `npm run dev`, e põe a faixa. **Se a troca falhar, a build para** (nunca sai um desktop "de teste" gravando na produção). O arquivo continua com a URL da produção escrita; não mude isso sem mudar o `ambientes.json`.
- **Travas:** `npm run dev`/`build:teste` param com aviso se o teste não estiver configurado ou se estiver com a URL da produção. A build de produção é idêntica à de antes (conferido: desktop byte a byte igual e sem a faixa no código).

## Montar o banco de teste (uma vez)

1. No Supabase: **New project** → nome `stokk-teste`, mesma região, plano Free (o plano grátis permite 2 projetos ativos). Guardar a senha do banco com o dono.
2. Colocar a **Project URL** e a **anon public key** do teste em `ambientes.json` → `teste`.
3. Rodar `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\montar_banco_teste.ps1`. Ele:
   - recusa conexão da produção (compara com `ambientes.json`) e banco que já tenha as tabelas;
   - desliga, antes de criar as tabelas, as permissões padrão que um projeto novo dá a `anon`/`authenticated`/`service_role`, para as permissões ficarem **iguais às da produção** (senão o teste seria mais liberado e esconderia erros de permissão); numa cópia temporária da foto, troca `CREATE SCHEMA` por `CREATE SCHEMA IF NOT EXISTS` e pula o comentário do schema `public` e as permissões padrão do `supabase_admin` (o projeto novo já tem);
   - cria o papel `powerbi_leitor` **sem login** e as extensões; roda `banco/estrutura.sql` e as linhas de comando de `banco/estrutura_extras.sql` (tempo real, gatilho `on_auth_user_created`, bucket `cinco-s` e políticas). **Crons não são criados** no teste;
   - copia só os **cadastros** do último backup (`areas`, `armazens_area`, `produtos`, `equipamentos`, `tanques`; "quem cadastrou" fica vazio). Nada de volumes, movimentos, conferências, pessoas ou fotos;
   - pede para criar as contas de teste no painel (**Authentication › Users › Add user**, com *Auto Confirm*) e ativa cada uma com `consultas/teste_ativar_usuarios.sql` (supervisor e operador, todas as áreas).
   A connection string do teste (sem senha) fica em `OneDrive\STOKK_backups\conexao_teste.txt`.
4. `npm run dev` e abrir no navegador (F12 › modo celular). Desktop: `/desktop/`.

**Quando a estrutura da produção mudar** (novo `update_0NN`): rode o `update_0NN` **primeiro no teste** (SQL Editor do `stokk-teste`), teste, e só depois na produção. Para recomeçar o teste do zero: apagar e recriar o projeto `stokk-teste` e rodar o script de novo (ele usa a foto mais recente de `banco/`).

## O que não funciona no teste (por enquanto)
- **Edge Functions** (`admin-usuarios`, `avisar-conferencias`) não estão publicadas no `stokk-teste`: tela **Usuários** e avisos de parada dão erro. Publicar lá quando for testar essas partes (com segredos próprios do teste).
- **Push e crons:** não existem no teste.
- **Power BI:** só produção.
- **Biometria, push e atualização do APK:** só no APK (ver próximas etapas).

## Fluxo de trabalho
1. Trabalhar na branch `teste` (`git switch teste`).
2. Testar com `npm run dev` (banco de teste) no navegador em modo celular.
3. Mudança de banco: `update_0NN` no `stokk-teste` primeiro.
4. Aprovado: rodar o backup da produção (`scripts\backup_banco.cmd`), rodar o `update_0NN` na produção, aumentar a versão (regra do `AGENTS.md`), juntar `teste` na `master` e enviar. Só aí vai para o site e para os celulares.

## Próximas etapas (ainda não feitas)
- **Site de teste no GitHub Pages** (subpasta, ex.: `…/Stokk-app/teste/`) gerado a cada push na branch `teste` (`GH_PAGES_BASE` já está previsto no `vite.config.js`).
- **APK de teste** (`com.stokk.app.teste`, nome "STOKK TESTE", instalável ao lado do normal, Release própria `apk-teste`): exige cadastrar o pacote novo no Firebase (`google-services.json`). Alternativa sem celular: emulador do Android Studio.
- Rodar os testes (`tests/*.cjs`) no GitHub antes de publicar.
