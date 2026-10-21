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
- **Notificações (v3, 17/10):** a mesma Edge Function atende 3 tipos, escolhidos pelo corpo `{"tipo":...}`; cada tipo tem seu cron (UTC = Brasília + 3), ver `update_011_push.sql` §4. `conferencia` (cron `push-conferencia`, 8h/12h/16h): conferências abertas há 2–72 h, 1 notificação por pessoa (quem iniciou + supervisores). `inventario` (`push-inventario`, 9h/13h): há quantos dias foi o último inventário (`sessoes.finalizado_em` mais recente), só supervisores. `rendimento` (`push-rendimento`, 15h): produções finalizadas hoje com rendimento < 98% (arredondado a 1 casa), só supervisores; não envia se não houver. `push_avisos` não é usada (tabela legada). Segredos: `CRON_SECRET` na função deve ser idêntico ao valor `x-cron-secret` escrito nos 3 crons (se diferir → 403 "proibido" silencioso; ver resposta em `net._http_response`). Crons ativos (recriados em 18/10, jobid 6, 7, 8; antes 3, 4, 5): `push-conferencia` `0 11,15,19 * * *`, `push-inventario` `0 12,16 * * *`, `push-rendimento` `0 18 * * *` (o antigo `avisar-conferencias` não existia mais, basta não rodar `unschedule` dele). Teste manual: `select net.http_post(url:=..., headers:=jsonb_build_object('Content-Type','application/json','x-cron-secret','<segredo>'), body:='{"tipo":"inventario"}'::jsonb);` e depois `select status_code, content from net._http_response order by created desc limit 1;` (resposta `{"tipo":..,"itens":N,"enviados":N}`). Para alterar horário de um tipo: `cron.unschedule('push-...')` e criar de novo. Nenhum SQL novo é necessário além dos crons (não precisa reexecutar `update_011`). **Status:** `inventario` testado em produção (200, enviados 1, também em 18/10 após corrigir o segredo); `conferencia` e `rendimento` ainda sem teste manual. Em 18/10 os 4 disparos automáticos do dia deram 403 "proibido" porque o segredo escrito nos crons era diferente do `CRON_SECRET` da função; corrigido definindo o mesmo valor nos dois lugares (função e crons) e recriando os crons. `FCM_SERVICE_ACCOUNT` não é afetado por isso.
- **APK:** após mudar plugins/Gradle: `npm install`, `npx cap sync android`, gerar no Android Studio. Subir `versionCode` a cada APK.
- **Status:** não testado em produção.
