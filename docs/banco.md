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

### 4.3.1 Tabelas do Diesel (`update_015`)

| Tabela | Conteúdo |
|---|---|
| `equipamentos` | `codigo` (único por área, sem diferenciar maiúscula), `nome`, `tipo` (`maquina`/`caminhao`/`outro`), `medidor` (`h` horímetro ou `km` odômetro), `area_uso` (text[]: `trefila`, `planta1`), `dias_alerta` (1–60, padrão 2), `alerta_dias_uteis`, `alerta_ativo`, `ativo`, `criado_em`. Nunca se apaga: desativa com `ativo = false`. |
| `tanques` | `nome`, `capacidade_l`, `minimo_l`, `ativo`. |
| `tanque_entradas` | Compras/descargas: `tanque_id`, `data_hora`, `litros`, `preco_litro`, `valor_total`, `fornecedor`, `nota`, `obs`. |
| `abastecimentos` | Saídas: `equipamento_id`, `equipamento_codigo` (cópia), `tanque_id`, `data_hora`, `medidor` (leitura do painel), `litros`, `custo_litro` e `custo_total` (custo médio do tanque no momento; nulos se ainda não havia compra), `troca_medidor`, `obs`. |
| `tanque_medicoes` | Conferência com a régua: `litros_medidos`, `saldo_app` (o que o app calculava), `diferenca`, `ajustar` (se a diferença passa a valer no saldo), `obs`. |

As três tabelas de lançamento (`tanque_entradas`, `abastecimentos`, `tanque_medicoes`) têm `anulado`, `anulado_motivo`, `anulado_por`, `anulado_em`. Ninguém apaga nem edita: o supervisor **anula** (o gatilho `diesel_proteger_anulacao` exige o motivo, grava quem/quando e não deixa desfazer). O **saldo do tanque e o custo médio não são gravados**: o app calcula (ver `regras-de-negocio.md` §9.5).

### 4.3.2 Paradas e manutenção (`update_016`)

| Tabela | Conteúdo |
|---|---|
| `ocorrencias` | Uma linha por parada/manutenção. **Abertura** (qualquer conta ativa da Gestão): `equipamento_id`, `equipamento_codigo` (cópia), `categoria` (`manutencao`/`parada`), `motivo`, `descricao`, `aberta_em`, `aberta_por`, `aberta_por_nome`. **Liberação** (só supervisor, na mesma linha): `liberada_em`, `motivo_liberacao`, `servico_realizado` (o que foi feito), `recebido_por` (quem pegou o equipamento), `liberada_por_nome`; o gatilho grava `liberada_por` e `liberada_registro_em`. Avisos push: `aviso_abertura_em`, `aviso_liberacao_em` (só a Edge Function grava). Anulação: `anulado`, `anulado_motivo`, `anulado_por`, `anulado_em`. Em aberto = `liberada_em is null and not anulado`. |

Travas no banco: **uma ocorrência em aberto por equipamento** (índice único parcial `ocorrencias_uma_aberta_uk`); a abertura nasce em aberto, em nome de quem abre, com data não futura; a liberação não pode ser antes da abertura nem no futuro e exige serviço, quem pegou e motivo; depois de liberada ou anulada a linha não muda mais (gatilho `ocorrencia_proteger`; única exceção: a marca de aviso enviado). Ninguém apaga: supervisor anula com motivo (a ocorrência anulada libera o equipamento para nova abertura). Leitura por área (RLS); `anon` sem acesso. View `bi.manutencao_ocorrencias` (horas paradas, situação).

### 4.3.3 Localização dos equipamentos e correção de ocorrência (`update_017`)

| Tabela / coluna | Conteúdo |
|---|---|
| `equipamento_locais` | Histórico de onde cada equipamento esteve: `equipamento_id`, `equipamento_codigo` (cópia), `local` (texto livre, até 120 caracteres, obrigatório), `obs`, `data_hora` (desde quando está lá; não pode ser futura), `usuario_id`, `usuario_nome`, `timestamp`, e os campos de anulação (`anulado`, `anulado_motivo`, `anulado_por`, `anulado_em`). O **local atual** é o último registro válido (por `data_hora`; empate vale o lançado depois). |
| `ocorrencias.editada_em`, `editada_por` | Preenchidos pelo gatilho quando o supervisor corrige categoria, motivo ou descrição de uma ocorrência **ainda em aberto**. |

Qualquer conta ativa da Gestão registra o local (em nome de si mesma); ninguém apaga nem edita: o supervisor **anula** com motivo (mesmo gatilho `diesel_proteger_anulacao` do diesel). Ocorrência em aberto: o supervisor pode alterar só `categoria`, `motivo` e `descricao` (o gatilho `ocorrencia_proteger` impede mexer nos campos da liberação nessa edição); liberada ou anulada, continua imutável. Views `bi.equipamento_locais` (histórico) e `bi.equipamento_local_atual`.

### 4.3.4 5S da Gestão Planta 1 e fotos (`update_018`)

| Item | Conteúdo |
|---|---|
| Área `gestao_p1` | "Gestão Planta 1", ao lado da Laminação. Só vê quem tiver a área em `usuario_areas`. |
| `cinco_s` | Uma melhoria de 5S: `setor` (≤ 80), `problema` (≤ 300), `foto_antes` (caminho no bucket), `aberto_em`, `aberto_por`, `aberto_por_nome`, `concluido_em`, `concluido_por`, `concluido_por_nome`, `foto_depois`, `acao` (≤ 500), `editado_em/por`, `anulado*`, `area` (padrão `gestao_p1`). Em aberto = `concluido_em` vazio. Concluir é tudo ou nada (data + foto do depois + o que foi feito: check). A foto tem que estar na pasta da própria área. |
| Gatilho `cinco_s_proteger` | Anulada não muda; concluída só pode ser anulada; **anular e corrigir (setor/descrição, só em aberto) = só supervisor**; **concluir = qualquer pessoa da área** (data não pode ser antes da abertura nem no futuro; setor, descrição e foto do antes não mudam junto). Mais `trg_proteger_area` (registro não muda de área). |
| RLS | select pela área; insert por qualquer conta da área, em nome próprio, já nascendo aberto; update só em linhas da área (quem pode o quê é o gatilho). Grants: select, insert e update só de `setor, problema, concluido_em, concluido_por_nome, foto_depois, acao, anulado, anulado_motivo`. Realtime ligado. |
| Storage, bucket `cinco-s` | **Privado**, só JPEG, até 2 MB. Arquivo em `<area>/<aaaa-mm>/<id>_antes.jpg` e `<id>_depois.jpg`. Políticas em `storage.objects`: select e insert só quando a primeira pasta é uma área da pessoa (`areas_do_usuario()`). **Sem política de update nem delete**: o app não troca nem apaga foto. |
| `bi.cinco_s` | View para o Power BI (sem fotos): setor, problema, abertura/conclusão (Brasília), quem abriu/concluiu, o que foi feito, `horas_ate_concluir`, situação. Só não anulados. |

O app reduz a foto no aparelho (lado maior 1280 px, JPEG ~72%, alvo ≤ 300 KB; foto de celular de 3–5 MB vira ~100–300 KB). Estimativa: um 5S com as duas fotos ocupa 0,3–0,6 MB; o plano grátis do Supabase tem 1 GB de arquivos (≈ 2 mil a 3 mil registros).

Várias fotos (`update_019`): a foto principal continua em `foto_antes`/`foto_depois`; as extras (até 4 por lado, total 5 + 5) ficam em `fotos_antes_extra` (gravadas ao abrir, nunca mudam) e `fotos_depois_extra` (só entram ao concluir). Checks: no máximo 4 extras, todas na pasta da própria área (`cinco_s_caminhos_ok`), e extras do depois só com o registro concluído. O gatilho `cinco_s_proteger` foi recriado para tratar as extras (as do antes não mudam; anulação preserva tudo). A view `bi.cinco_s` ganhou `fotos_antes` e `fotos_depois` (quantidade).

### 4.3.5 Administração de usuários (`update_020`)

| Item | Conteúdo |
|---|---|
| `profiles.admin` | `boolean not null default false`. Quem é admin (conta ativa) vê a tela **Usuários** no app. **Só muda pelo SQL Editor/painel** (ex.: `update public.profiles set admin = true, role = 'supervisor', ativo = true where id = (select id from auth.users where email = '...');`). |
| `proteger_profiles` | Recriada: com `auth.uid()` não nulo (qualquer login do app) bloqueia mudança de `role`, `ativo`, `id`, `area` **e `admin`**. A Edge Function usa a chave de serviço (`auth.uid()` nulo), por isso consegue alterar. |
| `eh_admin()` | `security definer`; conta ativa com `admin = true`. |
| `admin_acoes` | Registro de tudo que o admin fez pela tela (`quando`, `admin_id`, `admin_nome`, `acao` = criar/atualizar/bloquear/reativar/senha, `alvo_id`, `alvo_email`, `detalhe` jsonb). **Nunca guarda senha.** RLS: só admin lê; ninguém grava pelo app (só a função). |

### 4.3.8 Atividade e solicitante nos locais (`update_023`)
`equipamento_locais.atividade` (o que está fazendo; obrigatória só no app, nula nos registros antigos) e `solicitante` (quem pediu o serviço; opcional). O campo `local` continua texto livre no banco; o app oferece só **Planta 1, Planta 2, Trefila** (`LOC_LOCAIS`), então os registros antigos ("Pátio 2"...) continuam válidos. Sem `data_fim`/`atividade`/`solicitante` editáveis depois (só anulação). Views BI ganharam `atividade` e `solicitante` no fim.

### 4.3.7 Locais por setor e turno (`update_022`)
`equipamento_locais.data_fim` (nulo = em andamento) e `equipamentos.setor` (texto, até 60). O **fim efetivo** de um registro é o MENOR entre `data_fim` e o início do próximo registro válido do mesmo equipamento (calculado no app; o histórico continua só inserção, nada é fechado por gatilho). Operador/supervisor não editam `data_fim` depois (só anulação). `grant update (setor)` para o supervisor. O SQL preenche `setor` só onde está vazio, pelo nome (empilhadeira → Expedição; carregadeira/caminhão/cavalo/meteor → Pátio de Tarugo). Views: `bi.equipamento_locais` ganhou `fim` e `setor`; `bi.equipamento_local_atual` ganhou `setor`.

### 4.3.6 Stokkbook (`update_021`)

| Item | Conteúdo |
|---|---|
| `cinco_s.postar_stokkbook` | `boolean not null default true`; a caixinha "Postar no Stokkbook" da tela de concluir (o app só envia a coluna quando desmarcada). `grant update` na coluna. |
| `stokkbook_posts` | Um post por evento (`tipo` com check, hoje só `cinco_s`; `unique (tipo, ref_id)`). Copia textos e caminhos de foto do 5S (`area`, `autor_nome`, `setor`, `problema`, `acao`, `foto_antes`, `foto_depois`, `fotos_antes/depois`, `horas`, `quando`) + `oculto`, `oculto_motivo/por/em`. **Ninguém insere/apaga pelo app**: o gatilho `stokkbook_de_cinco_s` (AFTER UPDATE em `cinco_s`, security definer) cria o post ao concluir com a caixinha marcada e oculta o post se o 5S for anulado. |
| RLS posts | select: `area` ∈ áreas da pessoa **e** (não oculto **ou** supervisor). update: só supervisor da área, só colunas `oculto`, `oculto_motivo` (gatilho `stokkbook_posts_proteger` exige motivo e grava quem/quando). |
| `stokkbook_reacoes` | `(post_id, user_id)` PK (uma reação por pessoa), `emoji` ∈ palmas/confete/foguete/joia, `user_nome` preenchido pelo gatilho a partir de `profiles` (não confia no app). RLS: vê/reage quem vê o post; só mexe na própria reação. Grants de coluna: insert `(post_id, emoji)`, update `(emoji)`. |
| Realtime | As duas tabelas na publicação `supabase_realtime`. |
| Backfill | Os 5S já concluídos (não anulados, `postar_stokkbook` true) viram posts uma única vez. |
| Novo tipo de evento (futuro, ex.: máquina) | Ampliar o `check` de `tipo`, criar o gatilho do evento (security definer, `on conflict do nothing`) e o texto do cartão em `sbkCartao`. |

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
| `update_014_contagem_cega.sql` | **Contagem cega:** colunas `sessoes.tipo` (`'normal'` padrão ou `'cega'`, com check) e `sessoes.itens` (jsonb, itens lidos da etiqueta). Não mexe em `volumes`. Rodar depois do 013. **Status:** testado só em Postgres local. |
| `update_019_cinco_s_fotos.sql` | **5S com várias fotos:** colunas `cinco_s.fotos_antes_extra` e `fotos_depois_extra` (até 4 cada), função `cinco_s_caminhos_ok`, checks, gatilho `cinco_s_proteger` recriado, política de insert ajustada, `grant update (fotos_depois_extra)`, `bi.cinco_s` com quantidade de fotos. Rodar depois do 018. |
| `update_020_admin.sql` | `profiles.admin`, `proteger_profiles` protege também `admin`, `eh_admin()`, tabela `admin_acoes` (tela Usuários, v1.7.0). |
| `update_023_locais_atividade.sql` | `equipamento_locais.atividade` (até 200) e `solicitante` (até 120, opcional) + views BI. Depende do 022. |
| `update_022_locais_turnos.sql` | Locais por turno: `equipamento_locais.data_fim` (opcional), `equipamentos.setor`, views BI com fim/setor. Depende do 015/017. |
| `update_021_stokkbook.sql` | Stokkbook: posts e reações do feed, `cinco_s.postar_stokkbook` (v1.8.0). Depende do 018/019. |
| `update_018_cinco_s.sql` | **Gestão Planta 1 / 5S:** área `gestao_p1`; tabela `cinco_s` (RLS por área, gatilho `cinco_s_proteger`); bucket privado `cinco-s` no Storage com políticas por área; Realtime; view `bi.cinco_s`. Não depende do 015/016/017. Depois de rodar, libere a área para quem for usar (`usuario_areas`). |
| `update_017_localizacao.sql` | **Gestão / Localização + correção de ocorrência:** tabela `equipamento_locais` (RLS por área; registra qualquer conta da Gestão; anula o supervisor), colunas `ocorrencias.editada_em/editada_por`, gatilho `ocorrencia_proteger` atualizado (permite corrigir categoria/motivo/descrição enquanto aberta), Realtime, views `bi.equipamento_locais` e `bi.equipamento_local_atual`. Rodar depois do 016. **Status: testado num Postgres 16 local (rodou 2×, regras de acesso conferidas com perfis diferentes); não rodado em produção.** |
| `update_016_paradas.sql` | **Gestão / Paradas e manutenção:** tabela `ocorrencias` (RLS por área, abertura por qualquer conta da Gestão, liberação e anulação só do supervisor), uma em aberto por equipamento, gatilho `ocorrencia_proteger`, Realtime, view `bi.manutencao_ocorrencias`. Rodar depois do 015. **Status: testado num Postgres 16 local (rodou 2×, regras de acesso conferidas com perfis diferentes); não rodado em produção.** |
| `update_015_diesel.sql` | **Gestão / Diesel:** área `gestao`; tabelas `equipamentos`, `tanques`, `tanque_entradas`, `abastecimentos`, `tanque_medicoes` (todas com `area` e RLS por área), gatilhos (medidor não diminui; anulação só com motivo), views `bi.diesel_abastecimentos`, `bi.diesel_entradas`, `bi.diesel_equipamentos`. Rodar depois do 014. **Status: testado num Postgres 16 local (rodou 2×, regras de acesso conferidas); não rodado em produção.** |
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


> **`schema_atual.sql` (raiz):** foto das tabelas, chaves, índices e regras RLS conferidas no Supabase em 23/10/2026, feita porque o `schema.sql` original e os `update_001…006`, `009` e `010` foram perdidos. É só referência: **não rode** no banco que já existe. Funções, gatilhos e views do Power BI estão nos `update_007`, `008`, `011`, `012` e `013`.
