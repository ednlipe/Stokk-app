# STOKK — instruções para quem for mexer no projeto (pessoa ou agente de IA)

App mobile-first de estoque e rendimento metálico para uma trefilaria. Backend Supabase (PostgreSQL), app Android (Capacitor), site desktop, painel Power BI e notificações push.

## Por onde começar
1. Leia `docs/README.md` (índice). Depois leia **só** o arquivo da área em que vai mexer. Não leia tudo.
2. Veja `docs/pendencias.md` (o que falta e problemas conhecidos) e o fim de `docs/historico.md` (o que mudou por último).

## Mapa do projeto
| Parte | Onde |
|---|---|
| App (telas e regras) | `src/App.jsx` |
| Site desktop (mesmas regras do app) | `public/desktop/index.html` |
| Android / Capacitor | `android/` (versão em `android/app/build.gradle` e `package.json`) |
| Banco | `schema.sql` + `update_001…013_*.sql` na raiz |
| Notificações push (Edge Function) | `supabase/functions/avisar-conferencias/index.ts` |
| Documentação | `docs/` |

## Regras que valem sempre
- **Documentação é obrigatória.** Ao desenvolver, alterar ou configurar algo, atualize na mesma entrega: o arquivo da área em `docs/`; uma linha em `docs/historico.md` (data, o quê, arquivos/SQL); `docs/pendencias.md` (remova o resolvido, inclua o novo); e `docs/README.md` se a versão mudar. Marque com "Status" o que ainda não foi testado em produção. Escreva em português e use nomes reais de tabelas, colunas, funções e arquivos.
- **Nunca registre segredos** (senhas, `service_role`, `CRON_SECRET`, chave do Firebase, senha do `powerbi_leitor`) em arquivos, docs ou commits.
- **Mudança de banco = novo `update_0NN_*.sql`** idempotente (pode rodar mais de uma vez), na raiz, listado em `docs/banco.md`. Não edite migrações antigas.
- **Não enfraqueça a segurança (RLS).** Contas novas nascem bloqueadas (`profiles.ativo=false`); `role` e `ativo` só mudam pelo painel do Supabase. Veja `update_008_seguranca.sql` e `docs/seguranca.md`.
- **Áreas (update_012 + 013):** `trefila` e `planta1`. Uma pessoa pode ter várias áreas (`usuario_areas` + `profiles.area` principal); `volumes`, `movimentos`, `sessoes` e `producoes` têm `area` e a RLS filtra com `area = any ((select public.areas_do_usuario())::text[])` (o cast é obrigatório). Não reescreva políticas sem esse filtro. `volumes.lote` é único entre áreas; `role` vale para todas as áreas; `produtos` é compartilhado. O Power BI vê todas as áreas.
- **Todo peso está em kg** (`volumes.quantidade`, `movimentos.quantidade`, produção). O Power BI tem `quantidade_kg` e `quantidade_ton`.
- **Rendimento metálico = soma produzida ÷ soma consumida** (nunca média de percentuais). Cor pelo valor com 1 casa decimal: ≥ 99 verde, ≥ 98 amarelo, abaixo vermelho.
- **Turnos:** 1º 7h–15h20, 2º 15h–23h20, 3º 23h–7h20.
- **App e site desktop usam as mesmas regras.** Mudou numa, confira a outra.
- **Fuso:** Brasília (UTC−3). O `pg_cron` roda em UTC; some 3 horas ao agendar.

## Versão do app
- Rótulo na tela vem de `package.json` (`version`) + carimbo da build. No desktop, a constante `APP_VERSAO` em `index.html`.
- Cada APK novo precisa subir `versionCode` e `versionName` em `android/app/build.gradle`.

## Notificações push (resumo)
- Uma Edge Function atende 3 tipos pelo corpo `{"tipo": "conferencia" | "inventario" | "rendimento"}`, cada um com seu cron. Detalhes e horários em `docs/deploy.md`.
- O segredo `CRON_SECRET` da função tem que ser idêntico ao `x-cron-secret` escrito nos crons; se diferir, a resposta é 403 "proibido" (veja `net._http_response`).

## Antes de entregar
- Compile/teste o que mudou e diga o que **não** foi testado.
- Atualize `docs/` (regra acima). Uma tarefa sem documentação não está terminada.
