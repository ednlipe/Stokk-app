# STOKK — Histórico de mudanças e como manter a documentação

> Uma linha por mudança (data, o quê, arquivos/SQL).
> Índice geral: [`docs/README.md`](README.md). Regra: mudou algo desta área, atualize ESTE arquivo e uma linha em [`historico.md`](historico.md).

## 16. Histórico de mudanças

> Mais recente primeiro. Datas aproximadas pelos arquivos quando não houve registro exato.

| Data | Mudança |
|---|---|
| 2026-10-14 | `update_010` rodado em produção: importados 198 vol. = 352.879 kg (média 1.782 kg); produção 3 vol. = 5.384 kg. Banco todo em kg. |
| 2026-10-14 | `update_009` rodado em produção (produção t→kg). Conferência mostrou importados com média 1,8 (toneladas) → `update_010_importados_kg.sql` converte importados (<100) e seus movimentos de peso. |
| 2026-10-13 | **Unidade padronizada em KG**: app e site mostram/gravam kg; `update_009_unidade_kg.sql` converte volumes e movimentos de produção (t→kg) e atualiza `bi.estoque`. Arquivos: `App.jsx`, `public/desktop/index.html`, `update_009`. Status: pendente de publicar app e rodar o SQL. |
| 2026-10-13 | Power BI: `STOKK Matriz` 1.1 oculta dias sem dados; `STOKK Gráficos` 1.1 (linha) descarta datas sem valor da medida principal (meta sozinha não conta). PDF do dashboard exportado pelo usuário: visuais customizados saem corretamente. |
| 2026-10-12 | Power BI: novo visual `STOKK Lista` (últimas produções, 2 linhas + valor por faixa) e barrinha laranja no título da `STOKK Matriz`. Testados só no navegador. |
| 2026-10-12 | Power BI: novo visual `STOKK Matriz` (dia x turno, células por faixa, linha de total do período). Testado só no navegador. |
| 2026-10-12 | Power BI: novo visual `STOKK Segmentação` (blocos, filtro real via applyJsonFilter, seleção única/múltipla). Testado só no navegador. |
| 2026-10-12 | Power BI: roteiro da página 2 (Rendimento metálico) entregue: cards, visuais, medidas e prompt. |
| 2026-10-12 | `STOKK Gráficos`: nomes longos nas barras quebram em 2 linhas; largura dos nomes configurável. |
| 2026-10-12 | `GlowCard.pbiviz` v1.3: cor pela faixa e título em 2 linhas. |
| 2026-10-12 | Visual `STOKK Gráficos`: rosca refeita (legenda abaixo, cores por situação, rótulo central); eixo Y automático; ignora categoria vazia; multiplicador de escala. |
| 2026-10-12 | Power BI: visual `STOKK Gráficos` com alerta por faixas (limites vermelho/amarelo); medida `Dias sem inventário`; `DateSlicer.pbiviz` v1.1 (margem 3 px, brilho desligado por padrão). |
| 2026-10-12 | **App, aba Produção › Registrar:** rótulos "Equipamentos" e "Turnos" (plural) e removida a linha de horários dos turnos (`App.jsx`). No desktop (aba Rendimento) também removida a frase com os horários dos turnos, mantida a regra do 3º turno antes das 7h10; horários seguem em `regras-de-negocio.md`. Build OK, não testado em campo. |
| 2026-10-11 | Supabase: cadastro aberto ("Allow new users to sign up") **desligado** (usuário). Novas contas só criadas por Authentication → Users. |
| 2026-10-11 | `update_008_seguranca.sql` **executado em produção** (usuário). Pendente: publicar o front-end novo (tela "aguardando liberação", aviso de conferência) e conferir contas em `profiles`. |
| 2026-10-11 | `update_008_seguranca.sql`: adicionado `lock table` + `lock_timeout` no início (evita `deadlock detected` com app/Power BI lendo ao mesmo tempo). Testado local, 2 execuções seguidas. |
| 2026-10-11 | Visual Power BI `STOKK Gráficos` (`.pbiviz`); **documentação dividida em `docs/` por área** e `CLAUDE.md` virou índice. |
| 2026-10-09 | **App:** aviso na tela Início para conferência aberta há mais de 12 h (`renderAvisoConferencia`, constante `CONF_ABERTA_AVISO_H`, `App.jsx`). Só aparece com o app aberto. **Status: compilado, não testado em campo.** |
| 2026-10-09 | **Segurança:** `update_008_seguranca.sql` (contas novas bloqueadas, trava de `role`/`ativo`, RLS por conta ativa, `anon` sem acesso, `audit_log`); `onAuthed` bloqueia conta inativa no app e no desktop; versões de CDN fixadas. |
| 2026-10-09 | **Documentação técnica criada** (`DOCUMENTACAO_TECNICA.md`) e `CLAUDE.md` com a regra de mantê-la atualizada. |
| 2026-10-09 | **Site desktop:** nova aba **Rendimento** (painel de rendimento metálico, somente leitura, exporta Excel). |
| 2026-10-09 | **Power BI:** relações corrigidas (removidas 4 automáticas erradas; criada `producoes→producao_itens`), medidas `Faixa do rendimento`, `Volumes`, `Toneladas`, `Rendimento %` com 1 casa, `turno`/`rendimento_pct` em "Não resumir". Tema escuro/dourado, fundo 1280×720 e `medidas_stokk.json` (34 medidas) entregues. Claude Code + Power BI Modeling MCP configurados no VS Code. |
| 2026-10-09 | `update_007_powerbi.sql`: schema `bi`, 6 views e usuário `powerbi_leitor` (limite de conexões 20). Guias `ESQUEMA_STOKK.md` e `GUIA_POWERBI.md`. |
| 2026-10-08 | `update_006_turno_producao.sql`: seletor de turno na Produção; dashboard de rendimento por turno/dia/equipamento com cores 99/98/97; rótulo `08.10-d`. |
| 2026-10-06 | `update_005_producao.sql`: aba **Produção** (rendimento metálico LAM02/LAM03/RT200), correções na finalização. `update_004`: nome da conferência. |
| 2026-09-26 | Site desktop publicado (mesmo banco de dados). |
| 2026-09-25 | Projeto Vite + Capacitor (APK via GitHub Actions) e site no GitHub Pages; modo **coletor Bluetooth** na tela de bipar. |
| 2026-09-20 | `update_002` (lista esperada congelada) e `update_003` (excluir conferências). |
| 2026-09-18/19 | `update_001` (supervisor exclui volumes); `schema.sql` e README iniciais. |

---

## 17. Como manter este documento

**Regra:** ao entregar qualquer mudança (código, SQL, regra de negócio, configuração, Power BI, deploy), atualizar na mesma entrega:
1. a(s) seção(ões) que descrevem a parte alterada;
2. a linha de **Última atualização** e a **versão** (quando `APP_VERSAO` mudar);
3. uma linha no **Histórico de mudanças** (data, o quê, arquivos/SQL afetados);
4. **Limitações** e **Backlog**: tirar o que foi resolvido, incluir o que surgiu.

**Convenções**
- Escrever em português, direto, com nomes reais de tabelas, colunas, funções e arquivos.
- Mudança de banco: sempre um `update_0NN_*.sql` idempotente, listado na seção 4.4.
- Nunca registrar segredos (senhas, `service_role`, senha do `powerbi_leitor`).
- Marcar o que ainda **não foi testado em produção** com a palavra **Status**.
| 14/10 | Versão visível no app: `APP_VERSAO` = versão do `package.json` + carimbo automático da build (vite `define`), exibida na tela de login e na barra superior (app e site desktop). APK: `versionCode 2`, `versionName 1.1.0`. A cada release subir a versão no `package.json` e o `versionCode` no `android/app/build.gradle`. |
- 14/10: Produção — supervisor pode excluir um registro de produção finalizado (relatório › 'excluir este registro de produção'). Só apaga o registro (rendimento); não mexe no estoque. Política RLS producoes_delete (supervisor) já existia. **Status:** não testado em produção.
- 16/10: **Push de conferência esquecida em aberto (v1.2.0, `versionCode 3`).** App: `@capacitor/push-notifications`, `google-services.json` (projeto Firebase `stokk-d7bf6`, pacote `com.stokk.app`) em `android/app/`, permissão `POST_NOTIFICATIONS`, `registrarPush()` em `App.jsx` (só no app nativo; registra o token via `rpc registrar_push_token`; tocar na notificação abre Conferência). Banco: `update_011_push.sql` (`push_tokens`, `push_avisos`, função `registrar_push_token`). Edge Function `supabase/functions/avisar-conferencias` (FCM HTTP v1) avisa quem iniciou a conferência + supervisores ativos de 2 em 2 h até 48 h; agendada por pg_cron de hora em hora. **Status:** não testado em produção; depende de publicar a função, criar os segredos `FCM_SERVICE_ACCOUNT` e `CRON_SECRET` e agendar o cron.
- 16/10: Documentação reconciliada: README (versão), app.md (versão/push/excluir produção), deploy.md (Firebase/push), powerbi.md (kg, armazéns, cards), pendencias.md, CLAUDE.md (regra de kg).
- 17/10: Push testado em produção: Edge Function publicada (sem Verify JWT), segredos criados, cron de hora em hora ativo, resposta 200 com avisos; celular registrado em push_tokens. Marcos alterados para 2 em 2 h até 48 h. **Status:** falta confirmar o recebimento da notificação no celular.
- 17/10: Push v1.2.1 (`versionCode 4`): ícone pequeno monocromático da notificação (`ic_stat_stokk` em `res/drawable-*`, silhueta do logo) + cor laranja (`stokk_notificacao_cor`), via `meta-data` do FCM no AndroidManifest e `icon`/`color` na mensagem da Edge Function. Exige APK novo e redeploy da função. **Status:** não testado em produção. Ícone grande colorido não incluso (exigiria URL de imagem na mensagem).
- 17/10: Push de conferência aberta agora em horários fixos (substituído depois pela v3, abaixo); função `avisar-conferencias` v2 agrupa todas as conferências abertas (≥ 2 h, ≤ 72 h) em 1 notificação por pessoa; não usa mais `push_avisos`. **Status:** pendente publicar a função e reagendar o cron.
- 17/10: Push v3: `avisar-conferencias` atende 3 tipos (`conferencia` 8h/12h/16h, `inventario` 9h/13h, `rendimento` <98% às 15h) com crons separados. **Status:** função publicada e 3 crons criados (jobid 3, 4, 5); `inventario` testado (200, enviados 1); 403 anterior era segredo diferente do `CRON_SECRET`.
- 18/10: criado `AGENTS.md` na raiz (instruções para quem for mexer: mapa do projeto, regras, versão, push). `CLAUDE.md` agora só importa `@AGENTS.md` para não duplicar regras.
- 18/10: Disparos automáticos de 18/10 deram 403 "proibido" (segredo dos crons ≠ `CRON_SECRET` da função). Corrigido: mesmo segredo nos dois lugares, crons recriados (jobid 6, 7, 8); teste manual `inventario` deu 200, enviados 1. **Status:** falta confirmar o primeiro disparo automático (19/10).
