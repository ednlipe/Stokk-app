# STOKK — Build, deploy e CI

> 
> Índice geral: [`docs/README.md`](README.md). Regra: mudou algo desta área, atualize ESTE arquivo e uma linha em [`historico.md`](historico.md).

## 12. Build, deploy e CI

| Ação | Como |
|---|---|
| Desenvolvimento local | `cd stokk-vite && npm install && npm run dev` |
| Build web | `npm run build` (saída em `dist/`) |
| Build para GitHub Pages | `GH_PAGES=true npm run build` (base `/Stokk-app/`) — feito pelo workflow `pages.yml` |
| APK Android | workflow `android.yml`: `npm ci` → `npm run build` → `npx cap sync android` → `./gradlew assembleDebug`; publica o APK como artefato |
| Deploy inicial (histórico) | Netlify por arrastar pasta; depois migrado para GitHub Pages |
| Site desktop | basta substituir `public/desktop/index.html` e publicar (vai junto no build do Vite) |

A câmera do navegador exige **HTTPS** (ou `localhost`).

---


### Push (Firebase + Supabase) — configurado em 2026-10-16
- **Firebase:** projeto `stokk-d7bf6`, app Android `com.stokk.app`; `google-services.json` fica em `stokk-vite/android/app/` (não é segredo de servidor). API FCM V1 ativada.
- **Chave de serviço do Firebase** (segredo, **nunca** versionar): vai só para o segredo `FCM_SERVICE_ACCOUNT` das Edge Functions.
- **Supabase:** `update_011_push.sql` (tabelas `push_tokens`, `push_avisos`, função `registrar_push_token`); Edge Function `supabase/functions/avisar-conferencias` (sem "Verify JWT"; protegida por `x-cron-secret` = segredo `CRON_SECRET`); agendamento `pg_cron` em horários fixos por tipo (extensões `pg_cron` e `pg_net`).
- **Áreas (20/10, v1.3.0):** ordem de publicação: (1) rodar `update_012_areas.sql` no SQL Editor; (2) publicar a Edge Function nova (agora separa os avisos por área; a versão nova exige as colunas do passo 1); (3) publicar o site e gerar o APK 1.3.0 (`versionCode 5`); (4) definir a área de cada usuário da Planta 1: `update public.profiles set area = 'planta1' where id = '<ID>';`; (5) no Power BI, atualizar o modelo (colunas `area`/`area_nome` novas). Reverter: ver o fim de `update_012_areas.sql`.
- **Várias áreas (20/10):** ordem completa: (1) `update_012_areas.sql`; (2) `update_013_multiarea.sql` (fora do horário de uso); (3) Edge Function nova (lê `usuario_areas`); (4) site + APK 1.3.0; (5) dar áreas: `insert into public.usuario_areas (user_id, area) values ('<ID>','planta1') on conflict do nothing;` (área única: `update public.profiles set area='planta1' where id='<ID>'`); (6) atualizar o modelo do Power BI (colunas `area`, `area_nome`). Desfazer: ver rodapé do 013.
- **Contagem cega (24/10, v1.4.0):** ordem: (1) `update_014_contagem_cega.sql` no SQL Editor (sem ele a contagem cega avisa que falta rodar); (2) site desktop + APK 1.4.0 (`versionCode 7`). Sem mudança na Edge Function. **CI (GitHub Actions):** os workflows precisam de **Node 22** (Capacitor 8) e o projeto precisa de `typescript` em `devDependencies` (por causa do `capacitor.config.ts`); corrigido em 23/10.
- **Notificações (v3, 17/10):** a mesma Edge Function atende 3 tipos, escolhidos pelo corpo `{"tipo":...}`; cada tipo tem seu cron (UTC = Brasília + 3), ver `update_011_push.sql` §4. (desde a v1.3.0 os avisos são separados por área: cada supervisor recebe só os da sua área; o título do inventário inclui o nome da área). `conferencia` (cron `push-conferencia`, 8h/12h/16h): conferências abertas há 2–72 h, 1 notificação por pessoa (quem iniciou + supervisores). `inventario` (`push-inventario`, 9h/13h): há quantos dias foi o último inventário (`sessoes.finalizado_em` mais recente), só supervisores. `rendimento` (`push-rendimento`, 15h): produções finalizadas hoje com rendimento < 98% (arredondado a 1 casa), só supervisores; não envia se não houver. `push_avisos` não é usada (tabela legada). Segredos: `CRON_SECRET` na função deve ser idêntico ao valor `x-cron-secret` escrito nos 3 crons (se diferir → 403 "proibido" silencioso; ver resposta em `net._http_response`). Crons ativos (recriados em 18/10, jobid 6, 7, 8; antes 3, 4, 5): `push-conferencia` `0 11,15,19 * * *`, `push-inventario` `0 12,16 * * *`, `push-rendimento` `0 18 * * *` (o antigo `avisar-conferencias` não existia mais, basta não rodar `unschedule` dele). Teste manual: `select net.http_post(url:=..., headers:=jsonb_build_object('Content-Type','application/json','x-cron-secret','<segredo>'), body:='{"tipo":"inventario"}'::jsonb);` e depois `select status_code, content from net._http_response order by created desc limit 1;` (resposta `{"tipo":..,"itens":N,"enviados":N}`). Para alterar horário de um tipo: `cron.unschedule('push-...')` e criar de novo. Nenhum SQL novo é necessário além dos crons (não precisa reexecutar `update_011`). **Status:** `inventario` testado em produção (200, enviados 1, também em 18/10 após corrigir o segredo); `conferencia` e `rendimento` ainda sem teste manual. Em 18/10 os 4 disparos automáticos do dia deram 403 "proibido" porque o segredo escrito nos crons era diferente do `CRON_SECRET` da função; corrigido definindo o mesmo valor nos dois lugares (função e crons) e recriando os crons. `FCM_SERVICE_ACCOUNT` não é afetado por isso.
- **APK:** após mudar plugins/Gradle: `npm install`, `npx cap sync android`, gerar no Android Studio. Subir `versionCode` a cada APK.
- **Status:** não testado em produção.
