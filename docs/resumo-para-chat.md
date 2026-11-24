# STOKK — Resumo para colar no chat (fora do PC)

> Cole este arquivo inteiro no começo de uma conversa no chat do Claude (celular/navegador) para ele entender o projeto e o que mudou.
> Atualizado em **23/11/2026** · versão em produção: **1.10.8** (`versionCode 34`); na branch `teste`: **1.10.9** (`versionCode 35`).
> Não tem senha nem chave secreta aqui. **Nunca cole no chat:** senha do banco, `service_role`, `CRON_SECRET`, chave do Firebase, senha do `powerbi_leitor`, arquivos `dados_*.sql` de backup.

---

## 1. O que é o projeto

App mobile-first de **estoque e rendimento metálico** de uma trefilaria.
- **Banco:** Supabase (PostgreSQL), com segurança por linha (RLS) e áreas (`trefila`, `planta1`, `gestao`, `gestao_p1`).
- **App:** `src/App.jsx` (um arquivo grande, React + Vite), vira APK Android pelo Capacitor.
- **Site desktop:** `public/desktop/index.html` (arquivo HTML único, mesmas regras do app).
- **Banco:** mudanças só por arquivos `update_0NN_*.sql` na raiz (o último é o `update_024`). A foto completa da estrutura está em `banco/estrutura.sql` + `banco/estrutura_extras.sql`.
- **Documentação:** pasta `docs/` (índice em `docs/README.md`), regras gerais em `AGENTS.md`.
- **GitHub:** repositório `ednlipe/Stokk-app`. Push na `master` publica o site (GitHub Pages) e o APK (Release `apk-latest`, que avisa os celulares).

## 2. O que foi feito em 23/11/2026

### 2.1 Backup e foto do banco
- `scripts/backup_banco.ps1` (ou dois cliques em `scripts/backup_banco.cmd`): pede a senha na hora (não grava), gera `banco/estrutura.sql` e `banco/estrutura_extras.sql` (vão para o git) e os dados em `OneDrive\STOKK_backups\<data>` (**fora do git**).
- 1º backup feito em 23/11. A foto mostrou: `update_015` a `023` aplicados; **cron do diesel não existe** em produção (aviso "sem abastecer" nunca dispara).

### 2.2 `update_024` (corrigir registro de Locais) aplicado em produção
- Política `equipamento_locais_update`: supervisor, ou o próprio usuário em até 48 h.
- Consulta `consultas/locais_duplicados.sql` não achou duplicados.

### 2.3 Ambiente de teste (para não mexer direto no que a fábrica usa)
| | Produção | Teste |
|---|---|---|
| Branch do git | `master` | `teste` |
| Banco Supabase | `vjzqzmigifjdxftwmxew` | `stokk-teste` (`jxqhsdhohuqfigdvmbyx`), só cadastros e contas de teste |
| No PC | `npm run build` (o GitHub usa este) | `npm run dev` → http://localhost:5173 (desktop em `/desktop/`) |
| Na tela | normal | faixa vermelha "AMBIENTE DE TESTE" e `[TESTE]` no título |

- Quem escolhe o banco é o `vite.config.js`, com URL e chave pública em `ambientes.json`. **Não escrever URL/chave do Supabase no `App.jsx`.**
- O desktop tem a URL da produção escrita; no teste a troca é feita automaticamente na build (se falhar, a build para).
- Banco de teste montado por `scripts/montar_banco_teste.ps1`. Conta de teste: `teste@teste.com` (operador). Ainda **não há** conta de supervisor de teste.
- No teste **não funcionam**: Edge Functions (tela Usuários, avisos de parada), push, crons, Power BI.
- Ainda não existe link online do teste (só no PC). Próximas etapas: site de teste no GitHub Pages, APK de teste, testes rodando no GitHub.
- Detalhes: `docs/ambiente-teste.md`.

### 2.4 Correção na versão 1.10.6 (já em produção)
- **Problema:** desde a **1.9.0 (10/11)**, no **app**, os botões **Novo 5S**, **Concluir 5S**, **Abrir ocorrência** e **Liberar ocorrência** não faziam nada. Um bloco que confere o campo "Fim (opcional)" (`gl-fim`), que só existe na tela de **Locais**, tinha sido copiado por engano para essas telas. O desktop não tinha o erro.
- **Correção:** removidas as 4 cópias em `src/App.jsx` (ficou só a da tela de Locais, `gLocalSheet`).
- Testado no app de teste e publicado: APK 1.10.6 e site no ar em 23/11.
- **Falta:** confirmar no celular de alguém da fábrica que o 5S e as ocorrências salvam.

### 2.5 Biometria desligada (v1.10.7, `versionCode 33`, em produção desde 23/11)
- O dono decidiu tirar o desbloqueio por biometria do APK. `BIO_LIGADA = false` em `src/App.jsx`; o código continua para religar se precisar.
- `.gitattributes` fixa LF no `App.jsx` e no desktop (os testes comparam os dois letra por letra).

### 2.6 Mudança para a Cloudflare (no ar desde 23/11; 1.10.8 já procura a atualização lá)
- Produção: https://stokk.khay-entertainment.workers.dev · Teste: https://teste-stokk.khay-entertainment.workers.dev
- Objetivo: repositório privado no GitHub e site + APK na Cloudflare (`https://stokk.<conta>.workers.dev`, APK em `/apk/`). Quem publica é o GitHub Actions (a Cloudflare não monta APK); a branch `teste` ganha o link `teste-stokk.<conta>.workers.dev`.
- **Cuidado:** só tornar o repositório privado depois que todos os celulares instalarem a versão que procura a atualização na Cloudflare (`ambientes.json › producao.atualizacao`). Ordem completa em `docs/deploy.md` §12.1.

### 2.7 Falha silenciosa do `update()` corrigida (v1.10.9, `versionCode 35`, na branch `teste`)
- **Antes:** quando a RLS barrava uma alteração, o Supabase respondia sem erro e com 0 linhas alteradas, e o app mostrava "salvo/anulado/corrigido" mesmo assim. Exemplo: "corrigir registro" de Locais com o prazo de 48 h vencido.
- **Agora:**
  - `doc().update()` (app e desktop) pede de volta as linhas alteradas. Se vierem 0, mostra: "Não foi possível salvar: você não tem permissão ou o registro mudou. Atualize a tela e tente de novo."
  - O bloco é o `UPD-CORE` (`updExecutar`, `updMsg`), idêntico no app e no desktop; o teste é `tests/update_core.test.cjs`.
- **Turnos:** os cortes são 07:10 / 15:10 / 23:10. Todos os cálculos (rendimento, 5S, Locais, view `bi.producoes`) já usavam isso; só a documentação dizia 7h–15h20 e foi corrigida.

## 3. Pendências importantes (resumo de `docs/pendencias.md`)
- Conferir na fábrica que o 5S e as ocorrências salvam (1.10.6).
- Criar a conta **supervisor** de teste no `stokk-teste`.
- **Cron do diesel** não existe em produção (criar se o aviso ainda for desejado; `docs/deploy.md`).
- **Backup automático** ainda não existe; as fotos do 5S (bucket `cinco-s`) não entram no backup.
- Aviso de compilação: chave `situacao` repetida num objeto em `src/App.jsx` (perto da linha 6630–6637). Não quebra nada, mas vale limpar.
- Testes `admin_usuarios` e `diesel_aviso` precisam de Node 22.13+ (o PC tem Node 20).

## 4. Regras para quem for alterar (inclusive pelo chat)
1. **Trabalhe na branch `teste`.** Só vai para a `master` (produção) depois de testar.
2. **App e desktop usam as mesmas regras:** mudou num, confira o outro (`src/App.jsx` e `public/desktop/index.html`). Os núcleos `c5*`, `dsl*`, `LOC-CORE`, `NAV-CORE` têm cópia idêntica nos dois, e os testes em `tests/*.cjs` conferem.
3. **Toda entrega para a produção sobe a versão** (senão os celulares não recebem o aviso):
   - `android/app/build.gradle`: `versionCode` +1 e `versionName`;
   - `package.json` (`version`) e `package-lock.json` (2 lugares);
   - `public/desktop/index.html`: `APP_VERSAO`;
   - `docs/README.md` (linha da versão) e uma linha em `docs/historico.md`.
4. **Mudança de banco = novo arquivo** `update_025_*.sql` (o próximo número), que possa rodar mais de uma vez sem erro. Rodar **primeiro no `stokk-teste`**, depois na produção (com backup antes). Não editar os `update` antigos.
5. **Não enfraquecer a segurança (RLS).** Políticas com área usam `area = any ((select public.areas_do_usuario())::text[])`.
6. **Documentação é obrigatória:** atualizar o arquivo da área em `docs/`, `docs/historico.md` e `docs/pendencias.md`.
7. Peso sempre em **kg**. Rendimento = soma produzida ÷ soma consumida. Turnos: 1º 07:10–15:10, 2º 15:10–23:10, 3º 23:10–07:10. Fuso de Brasília.
8. Tabelas da Gestão e do 5S são **só inserção**: nada se apaga, o supervisor **anula** com motivo.

## 5. Como trazer uma alteração feita no chat para o projeto
- Peça ao chat o **trecho exato** que muda (o texto antigo e o novo) ou o arquivo inteiro, e diga a versão nova.
- No PC: abra o Claude Code na pasta `stokk-vite`, na branch `teste`, cole a alteração e peça para aplicar, testar (`npm run dev`) e atualizar as docs.
- Só depois de testado: pedir para subir a versão, juntar na `master` e enviar.
