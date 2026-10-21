# STOKK — Banco de dados (Supabase)

> Tabelas, valores, migrações `update_0NN`, RLS e schema `bi`. Tocou em SQL/permissões? Leia este e `seguranca.md`.
> Índice geral: [`docs/README.md`](README.md). Regra: mudou algo desta área, atualize ESTE arquivo e uma linha em [`historico.md`](historico.md).

## 4. Banco de dados (Supabase)

### 4.1 Tabelas do schema `public`

| Tabela | Chave | Conteúdo |
|---|---|---|
| `profiles` | `id` (= `auth.users.id`) | `nome`, `role` (`operador` \| `supervisor`), `ativo` (boolean; **padrão `false`**), `criado_em`. Criado por *trigger* ao cadastrar o login (`operador` e **bloqueado**). |
| `produtos` | `codigo` | Catálogo: `descricao`, `um`, `tipo`, `grupo`, `atualizado_em`. |
| `volumes` | `lote` | Cada etiqueta/volume físico. `produto_codigo` (FK para `produtos`), `produto_descricao`, `armazem`, **`quantidade` em kg**, `saldo_acumulado`, `categoria`, `tipo_mov`, `status`, `origem`, `status_conferencia`, `ultima_conferencia_em/sessao`, `importado_em`, `criado_em`, `atualizado_em`. |
| `movimentos` | `id` | Histórico (somente inserção): `lote`, `produto_codigo`, `produto_descricao`, `tipo`, `quantidade`, `timestamp`, `exportado`, `obs`, `usuario_id`, `usuario_nome`. |
| `sessoes` | `id` | Conferências de inventário: `iniciado_em`, `ativo`, `contados` (jsonb), `filtro_produto`, `finalizado_em`, `resultado` (jsonb), `esperados_snapshot` (jsonb), `nome`, `usuario_id`. |
| `producoes` | `id` | Produções (rendimento metálico). Ver 4.3. |

### 4.2 Valores usados
- `volumes.status`: `estoque` · `bloqueado` · `transferido` · `baixado` (também aceita texto livre).
- `volumes.status_conferencia`: `contado` · `nao_conferido` · vazio (aguardando conferência).
- `volumes.origem`: `importado` · `manual` · `producao`.
- `movimentos.tipo`: `importacao`, `conferencia`, `estoque`, `bloqueado`, `transferido`, `baixado`, `exclusao`, `troca_armazem`, `entrada`.
- `producoes.etapa`: `materia_prima` → `produtos` → `finalizada` (ou `cancelada`).

### 4.3 Tabela `producoes`
| Coluna | Tipo | Observação |
|---|---|---|
| `id` | text PK | gerado pelo app |
| `equipamento` | text | `LAM02`, `LAM03` ou `RT200` |
| `etapa` | text | ver acima |
| `codigo_produto` | text | produto gerado |
| `consumidos` | jsonb | lista de rolos consumidos |
| `produzidos` | jsonb | lista de volumes produzidos |
| `iniciado_em`, `finalizado_em` | timestamptz | |
| `resultado` | jsonb | `{consumidoKg, produzidoKg, rendimentoPct, perdaKg}` — preenchido na finalização |
| `turno` | int | 1, 2 ou 3 (pode ser nulo em registros antigos) |
| `data_producao` | date | data do turno (pode ser nula em registros antigos) |
| `usuario_id`, `usuario_nome` | | quem registrou |

Itens de `consumidos`/`produzidos` (chaves em camelCase): `lote`, `corrida`, `pesoKg`, `produtoCodigo`, `produtoDescricao`, `manual`, `divergente`, `em`.

### 4.4 Migrações (rodar no SQL Editor, nesta ordem)
| Arquivo | O que faz |
|---|---|
| `schema.sql` | Cria tabelas base, RLS, trigger de perfil e publica no realtime. |
| `update_001_excluir_volumes.sql` | Política: supervisor exclui volumes. |
| `update_002_esperados_snapshot.sql` | `sessoes.esperados_snapshot` (lista esperada congelada ao iniciar a conferência). |
| `update_003_excluir_conferencias.sql` | Política: supervisor exclui conferências. |
| `update_004_nome_conferencia.sql` | `sessoes.nome`. |
| `update_005_producao.sql` | Cria `producoes`, RLS e realtime. |
| `update_006_turno_producao.sql` | `producoes.turno` e `producoes.data_producao`. |
| `update_008_seguranca.sql` | **Segurança:** `profiles.ativo`, funções `eh_usuario_ativo()`/`eh_supervisor()`, RLS refeita, trava de `role`/`ativo`, revoga `anon`, tabela `audit_log` + gatilhos. Ver 4.5 e 13. **Status: testado em PostgreSQL local (simulação de ataques); rodado em produção em 2026-10-11 (relatado pelo usuário, sem conferência pelo Claude).** Primeira tentativa deu `deadlock detected` (nada alterado); script ganhou `lock table` + `lock_timeout`. |
| `update_007_powerbi.sql` | Schema `bi` (views) e usuário `powerbi_leitor` somente leitura. **Trocar `TROQUE_ESTA_SENHA` antes de rodar.** |

| `update_009_unidade_kg.sql` / `update_010_importados_kg.sql` | Converte pesos para kg (produção e importados) com backup; recria `bi.estoque` (`quantidade_kg`, `quantidade_ton`). Abortam se rodados duas vezes. |
| `update_012_areas.sql` | **Áreas (ambientes):** tabela `areas` (`trefila` = Trefilaria, `planta1` = Planta 1 (laminação)); `profiles.area`; coluna `area` (NOT NULL, padrão `area_padrao()`) em `volumes`, `movimentos`, `sessoes` e `producoes`; funções `area_do_usuario()` e `area_padrao()`; RLS refeita filtrando por área; `proteger_profiles()` bloqueia mudar `area` pelo app; tabela `armazens_area`; views `bi.*` ganham `area` e `area_nome` no fim, mais `bi.areas` e `bi.armazens_area`. Idempotente; testada em Postgres local. |
| `update_013_multiarea.sql` | **Várias áreas por usuário:** tabela `usuario_areas(user_id, area)` (RLS: só lê as próprias linhas; sem escrita pelo app), função `areas_do_usuario()` (text[]), políticas de `volumes`/`movimentos`/`sessoes`/`producoes`/`armazens_area` recriadas com `area = any ((select public.areas_do_usuario())::text[])` (o cast `::text[]` é obrigatório) e gatilho `proteger_area_registro` (`trg_proteger_area`) que impede mudar a `area` de um registro pelo app. Rodar depois do 012. **Status:** testado só em Postgres local. |
| `update_011_push.sql` | Push: `push_tokens`, `push_avisos`, função `registrar_push_token()`; bloco comentado com o agendamento `pg_cron`. Usada pela Edge Function `supabase/functions/avisar-conferencias`. |

Todas são idempotentes (podem rodar mais de uma vez), exceto `schema.sql` na primeira execução.

### 4.5 Segurança em nível de linha (RLS)
Todas as tabelas têm RLS ligada. Após `update_008`: só conta **ativa** (`profiles.ativo`) lê e escreve;
**insere/atualiza** (volumes, sessões, produções; movimentos só insere, sem alterar/apagar e só em nome de si mesmo);
apenas **supervisor ativo exclui** (volumes, sessões, produções) e **cadastra/atualiza produtos**.
`profiles`: cada um lê o próprio; contas ativas leem todos; cada um altera **somente o próprio `nome`**
(permissão de coluna + trigger `proteger_profiles` impedem mudar `role`/`ativo`/`id` pelo app; só painel/SQL Editor).
`anon` (sem login) não tem acesso a nenhuma tabela. `audit_log` (somente supervisor lê) registra exclusões e alterações de chave em volumes, produtos, perfis, sessões e produções.

### 4.6 Schema `bi` (para o Power BI)
Não é exposto pela API do app. Views (todas em `bi.*`):

| View | Conteúdo |
|---|---|
| `estoque` | um registro por volume, com `quantidade_kg` (valor do banco) e `quantidade_ton` (= kg/1000), `status`, `situacao_conferencia` (Em estoque (contado) / Não localizado / Aguardando conferência), `origem`, datas no fuso de São Paulo |
| `movimentos` | histórico com `data_hora` e `data` locais |
| `conferencias` | nome, datas, situação (Em andamento/Finalizada), contados/esperados/faltando |
| `producoes` | uma linha por produção, com turno e data deduzidos quando não gravados |
| `producao_itens` | cada volume consumido/produzido (jsonb achatado) |
| `rendimento_turno` | dia × equipamento × turno, só finalizadas, com `faixa` Verde/Amarelo/Vermelho |

Usuário `powerbi_leitor`: `connection limit 20`, `default_transaction_read_only = on`,
`statement_timeout = 60s`, sem acesso às tabelas de `public`. Detalhes em [Power BI](#11-power-bi).

---
