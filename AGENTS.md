# STOKK — instruções para quem for mexer no projeto (pessoa ou agente de IA)

App mobile-first de estoque e rendimento metálico para uma trefilaria. Backend Supabase (PostgreSQL), app Android (Capacitor), site desktop, painel Power BI e notificações push.

## Por onde começar
1. Leia `docs/README.md` (índice). Depois leia **só** o arquivo da área em que vai mexer. Não leia tudo.
2. Veja `docs/pendencias.md` (o que falta e problemas conhecidos) e o fim de `docs/historico.md` (o que mudou por último).

## Mapa do projeto
| Parte | Onde |
|---|---|
| App (telas e regras) | `stokk-vite/src/App.jsx` |
| Site desktop (mesmas regras do app) | `stokk-vite/public/desktop/index.html` |
| Android / Capacitor | `stokk-vite/android/` (versão em `build.gradle` e `package.json`) |
| Banco | `schema.sql` + `update_001…019_*.sql` (+ `schema_atual.sql`, foto do banco) na raiz |
| Notificações push (Edge Function) | `supabase/functions/avisar-conferencias/index.ts` |
| Documentação | `docs/` |

## Regras que valem sempre
- **Documentação é obrigatória.** Ao desenvolver, alterar ou configurar algo, atualize na mesma entrega: o arquivo da área em `docs/`; uma linha em `docs/historico.md` (data, o quê, arquivos/SQL); `docs/pendencias.md` (remova o resolvido, inclua o novo); e `docs/README.md` se a versão mudar. Marque com "Status" o que ainda não foi testado em produção. Escreva em português e use nomes reais de tabelas, colunas, funções e arquivos.
- **Nunca registre segredos** (senhas, `service_role`, `CRON_SECRET`, chave do Firebase, senha do `powerbi_leitor`) em arquivos, docs ou commits.
- **Mudança de banco = novo `update_0NN_*.sql`** idempotente (pode rodar mais de uma vez), na raiz, listado em `docs/banco.md`. Não edite migrações antigas.
- **Não enfraqueça a segurança (RLS).** Contas novas nascem bloqueadas (`profiles.ativo=false`); `role` e `ativo` só mudam pelo painel do Supabase. Veja `update_008_seguranca.sql` e `docs/seguranca.md`.
- **Áreas (update_012 + 013):** `trefila` e `planta1`. Uma pessoa pode ter várias áreas (`usuario_areas` + `profiles.area` principal); `volumes`, `movimentos`, `sessoes` e `producoes` têm `area` e a RLS filtra com `area = any ((select public.areas_do_usuario())::text[])` (o cast é obrigatório). Não reescreva políticas sem esse filtro. `volumes.lote` é único entre áreas; `role` vale para todas as áreas; `produtos` é compartilhado. O Power BI vê todas as áreas.
- **Contagem cega (update_014):** a etiqueta é lida por **posição** (volume 8 + corrida 6 + peso 4 + código do produto terminado na bitola + peças); o Volume da etiqueta = Lote do Protheus; a planilha vem em toneladas. Núcleo e testes em `src/App.jsx` / `tests/cega_core.test.cjs`; mesma cópia no desktop. Veja `docs/regras-de-negocio.md` §9.3.1.
- **Gestão / Diesel (update_015):** área `gestao` com abas próprias (equipamentos, tanque, abastecimentos). Tabelas só com INSERT (nada se apaga ou edita: supervisor **anula** com motivo); saldo e custo médio são calculados no app, não gravados. Núcleo `dsl*` em `src/App.jsx` e cópia idêntica no desktop; `tests/diesel_core.test.cjs` confere as duas. Veja `docs/regras-de-negocio.md` §9.5.
- **Paradas e manutenção (update_016):** tabela `ocorrencias`; qualquer conta da Gestão abre, só o supervisor libera/anula; uma em aberto por equipamento; nada se apaga. Núcleo `dslOcorrencia*`/`dslParadasResumo` (mesmo bloco do diesel). Veja `docs/regras-de-negocio.md` §9.6.
- **Localização (update_017):** tabela `equipamento_locais` (texto livre + histórico, qualquer conta da Gestão registra, supervisor anula); local atual = último registro válido (`dslLocalAtual`). O desktop da Gestão **lança e edita** (janelas copiadas do app); a permissão real é do banco. Veja `docs/regras-de-negocio.md` §9.7.
- **5S / Gestão Planta 1 (update_018):** área `gestao_p1`; tabela `cinco_s` (nasce em aberto com a foto do antes; qualquer conta da área conclui com a foto do depois; supervisor anula e corrige setor/descrição só em aberto; nada se apaga; regras no gatilho `cinco_s_proteger`). Até 5 fotos por lado (principal `foto_antes`/`foto_depois` + extras `fotos_*_extra`, update_019). Fotos no bucket **privado** `cinco-s` (políticas por pasta de área, sem update/delete), reduzidas no aparelho (`c5Comprimir`) e abertas por link temporário (`c5Urls`). Núcleo `c5*` em `src/App.jsx` e cópia idêntica no desktop; `tests/cinco_s_core.test.cjs` confere as duas. Turno do 5S (desktop): `c5Turno`, cortes 07:10/15:10/23:10. Abas por área em `ABAS_DA_AREA`/`ABA_INICIAL` (app e desktop). Veja `docs/regras-de-negocio.md` §9.8. **Ainda não há notificação do 5S** (`docs/pendencias.md` §13.3).
- **Todo peso está em kg** (`volumes.quantidade`, `movimentos.quantidade`, produção). O Power BI tem `quantidade_kg` e `quantidade_ton`.
- **Rendimento metálico = soma produzida ÷ soma consumida** (nunca média de percentuais). Cor pelo valor com 1 casa decimal: ≥ 99 verde, ≥ 98 amarelo, abaixo vermelho.
- **Turnos:** 1º 7h–15h20, 2º 15h–23h20, 3º 23h–7h20.
- **App e site desktop usam as mesmas regras.** Mudou numa, confira a outra.
- **Fuso:** Brasília (UTC−3). O `pg_cron` roda em UTC; some 3 horas ao agendar.

## Versão do app
- Rótulo na tela vem de `package.json` (`version`) + carimbo da build. No desktop, a constante `APP_VERSAO` em `index.html`.
- Cada APK novo precisa subir `versionCode` e `versionName` em `stokk-vite/android/app/build.gradle`.

## Notificações push (resumo)
- Uma Edge Function atende, pelo corpo `{"tipo": ...}`, 4 tipos com cron (`conferencia`, `inventario`, `rendimento`, `diesel`) e o tipo `ocorrencia`, que **não** usa cron: o app chama com o login do usuário ao abrir/liberar uma parada. Detalhes e horários em `docs/deploy.md`.
- O segredo `CRON_SECRET` da função tem que ser idêntico ao `x-cron-secret` escrito nos crons; se diferir, a resposta é 403 "proibido" (veja `net._http_response`).

## Antes de entregar
- Compile/teste o que mudou e diga o que **não** foi testado.
- Atualize `docs/` (regra acima). Uma tarefa sem documentação não está terminada.
