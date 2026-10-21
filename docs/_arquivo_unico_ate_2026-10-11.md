# STOKK — Documentação técnica

> **Documento vivo.** Descreve o estado atual do STOKK. Toda vez que algo novo for desenvolvido,
> esta documentação é atualizada na mesma entrega (seções afetadas + entrada no
> [Histórico de mudanças](#16-histórico-de-mudanças)). Convenção no [final do arquivo](#17-como-manter-este-documento).
>
> **Última atualização:** 2026-10-09 · **Versão do app (rótulo na tela):** `08.10-d`

---

## Sumário
1. [Visão geral](#1-visão-geral)
2. [Arquitetura](#2-arquitetura)
3. [Estrutura de pastas e arquivos](#3-estrutura-de-pastas-e-arquivos)
4. [Banco de dados (Supabase)](#4-banco-de-dados-supabase)
5. [Camada de dados no front-end](#5-camada-de-dados-no-front-end)
6. [Autenticação e perfis](#6-autenticação-e-perfis)
7. [Módulos do app (abas)](#7-módulos-do-app-abas)
8. [Leitura de etiquetas e leitores](#8-leitura-de-etiquetas-e-leitores)
9. [Regras de negócio](#9-regras-de-negócio)
10. [Site desktop](#10-site-desktop)
11. [Power BI](#11-power-bi)
12. [Build, deploy e CI](#12-build-deploy-e-ci)
13. [Segurança e operação](#13-segurança-e-operação)
14. [Limitações conhecidas](#14-limitações-conhecidas)
15. [Backlog](#15-backlog)
16. [Histórico de mudanças](#16-histórico-de-mudanças)
17. [Como manter este documento](#17-como-manter-este-documento)

---

## 1. Visão geral

**STOKK** é um app de controle de estoque de pátio e de rendimento metálico para uma
trefilaria/usina de aço. O estoque inicial vem de planilhas exportadas do **TOTVS Protheus**; a
partir daí o pessoal do pátio confere volumes bipando etiquetas, e a produção registra o que foi
consumido e produzido nos laminadores para calcular o **rendimento metálico**.

| Pergunta | Resposta |
|---|---|
| Quem usa | Operadores (pátio/produção) e supervisores (importação, exclusões, histórico) |
| Onde roda | Celular/coletor Android (APK ou navegador), e navegador no computador (site desktop) |
| Onde ficam os dados | Supabase (Postgres), compartilhados entre todos os aparelhos em tempo real |
| Idioma da interface | Português (Brasil) |
| Integração com Protheus | **Somente leitura de planilha** (importação manual). Não há API. |

**Funcionalidades:** início (dashboard de estoque) · bipar etiqueta · estoque · conferência de
inventário · produção (rendimento metálico por equipamento/turno) · importação de planilha ·
histórico de movimentos · exportação para Excel · relatórios no Power BI.

---

## 2. Arquitetura

```
                     ┌──────────────────────────────┐
  Planilha Protheus ─►  App STOKK (React + Vite)     │   APK Android (Capacitor)
  (.xlsx)            │  stokk-vite/src/App.jsx       │   ou navegador (GitHub Pages)
                     └──────────────┬───────────────┘
                                    │ supabase-js (HTTPS + Realtime)
  Site desktop ─────────────────────┤  (arquivo único: public/desktop/index.html)
                                    ▼
                     ┌──────────────────────────────┐
                     │ Supabase                      │
                     │  • Auth (e-mail/senha)        │
                     │  • Postgres + RLS (schema public)
                     │  • Realtime (publication)     │
                     │  • schema bi (views) ◄────────┼──── Power BI Desktop (usuário somente leitura)
                     └──────────────────────────────┘
```

### Stack
| Camada | Tecnologia |
|---|---|
| Front-end do app | **React 18** (JSX), **Vite 5**; porém grande parte da UI é feita com *template strings* e `innerHTML` dentro de `App.jsx` (herança da versão em HTML único) |
| Mobile | **Capacitor 8** (`com.stokk.app`), build Android via GitHub Actions |
| Banco / Auth / Realtime | **Supabase** (`@supabase/supabase-js` ^2) |
| Planilhas | **SheetJS** (`xlsx` 0.18.5) para importar e exportar |
| Leitura de código de barras | `BarcodeDetector` (câmera) e leitor USB/Bluetooth em modo teclado |
| OCR de etiqueta | **Tesseract.js 5** (carregado do jsDelivr sob demanda) |
| Site desktop | HTML/CSS/JS **sem framework**, arquivo único |
| BI | **Power BI Desktop** lendo views do schema `bi` |
| Fontes | Google Fonts (Oswald, IBM Plex Sans, IBM Plex Mono) |

---

## 3. Estrutura de pastas e arquivos

```
barra-app/                          (repositório git na raiz — histórico antigo)
├─ index.html                       Versão ORIGINAL em HTML único (legado, anterior ao Vite)
├─ manifest.json · icons/
├─ schema.sql                       Criação do banco (tabelas, RLS, trigger de perfil, realtime)
├─ update_001 … update_008_*.sql    Migrações incrementais (ver seção 4.4)
├─ README.md                        Guia inicial de configuração do Supabase e do primeiro teste
├─ ESQUEMA_STOKK.md                 Dicionário de dados para o Power BI
├─ GUIA_POWERBI.md                  Conexão, DAX e painéis sugeridos para o Power BI
├─ DOCUMENTACAO_TECNICA.md          (este arquivo)
├─ CLAUDE.md                        Instruções para o Claude Code (manter esta doc atualizada)
└─ stokk-vite/                      (repositório git próprio — é o que vai para o GitHub)
   ├─ index.html                    Esqueleto HTML + CSS do app (login, topbar, views, nav)
   ├─ src/
   │   ├─ main.jsx                  Entrada do React
   │   ├─ App.jsx                   TODO o app (~3,5 mil linhas)
   │   └─ index.css                 Estilos adicionais
   ├─ public/
   │   ├─ desktop/index.html        Site desktop (arquivo único, ~3,1 mil linhas)
   │   ├─ icons/ · manifest.json
   ├─ android/                      Projeto Android gerado pelo Capacitor
   ├─ capacitor.config.ts           appId com.stokk.app, webDir dist
   ├─ vite.config.js                base '/Stokk-app/' quando GH_PAGES=true; senão '/'
   ├─ .github/workflows/
   │   ├─ android.yml               Gera APK debug a cada push na master
   │   └─ pages.yml                 Publica o site no GitHub Pages a cada push na master
   └─ package.json
```

> **Dois repositórios git:** a raiz `barra-app/` e `stokk-vite/`. O que é publicado (Pages/APK) é
> o `stokk-vite/`. Em 2026-10-09 havia alterações **não commitadas** em `index.html`,
> `public/desktop/index.html`, `src/App.jsx` e `src/index.css` (último commit: `89a6e75`, 2026-09-26).

### Mapa de `src/App.jsx`
O arquivo é um único módulo grande, organizado por seções com comentários `/* ===== ... ===== */`:

| Linhas (aprox.) | Seção |
|---|---|
| 236–280 | Configuração do Supabase (URL, anon key) e `state` global |
| 277–380 | **Adaptador de banco** (`createSupabaseDB`): API `collection().doc().set/update/get/delete`, `onSnapshot`, realtime |
| 380–436 | Autenticação (login, perfil, `applyRoleUI`) |
| 437–545 | Utilitários (toast, beep, formatação), status, armazéns |
| 544–625 | Categoria/bitola/modelo do produto (extraídos da descrição) |
| 662–685 | Tema claro/escuro |
| 685–810 | Casamento de código de lote, parser de etiqueta, OCR |
| 849–935 | Assinaturas de dados e roteador de abas (`setView`, `renderView`) |
| 948–1143 | Início (dashboard) |
| 1144–1720 | Bipar (leitor, câmera, OCR, cadastro manual) |
| 1720–2094 | Estoque (filtros, seleção/exclusão em lote, detalhe do volume, troca de armazém) |
| 2094–2229 | Importar planilha |
| 2229–2727 | Conferência (inventário) e relatório |
| 2727–3482 | **Produção** (registro, dashboard de rendimento, relatório) |
| 3482–3560 | Histórico, exportação XLSX, inicialização |

---

## 4. Banco de dados (Supabase)

### 4.1 Tabelas do schema `public`

| Tabela | Chave | Conteúdo |
|---|---|---|
| `profiles` | `id` (= `auth.users.id`) | `nome`, `role` (`operador` \| `supervisor`), `ativo` (boolean; **padrão `false`**), `criado_em`. Criado por *trigger* ao cadastrar o login (`operador` e **bloqueado**). |
| `produtos` | `codigo` | Catálogo: `descricao`, `um`, `tipo`, `grupo`, `atualizado_em`. |
| `volumes` | `lote` | Cada etiqueta/volume físico. `produto_codigo` (FK para `produtos`), `produto_descricao`, `armazem`, **`quantidade` em toneladas**, `saldo_acumulado`, `categoria`, `tipo_mov`, `status`, `origem`, `status_conferencia`, `ultima_conferencia_em/sessao`, `importado_em`, `criado_em`, `atualizado_em`. |
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
| `update_008_seguranca.sql` | **Segurança:** `profiles.ativo`, funções `eh_usuario_ativo()`/`eh_supervisor()`, RLS refeita, trava de `role`/`ativo`, revoga `anon`, tabela `audit_log` + gatilhos. Ver 4.5 e 13. **Status: testado em PostgreSQL local (simulação de ataques); ainda não rodado em produção.** |
| `update_007_powerbi.sql` | Schema `bi` (views) e usuário `powerbi_leitor` somente leitura. **Trocar `TROQUE_ESTA_SENHA` antes de rodar.** |

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
| `estoque` | um registro por volume, com `quantidade_ton` e `quantidade_kg`, `status`, `situacao_conferencia` (Em estoque (contado) / Não localizado / Aguardando conferência), `origem`, datas no fuso de São Paulo |
| `movimentos` | histórico com `data_hora` e `data` locais |
| `conferencias` | nome, datas, situação (Em andamento/Finalizada), contados/esperados/faltando |
| `producoes` | uma linha por produção, com turno e data deduzidos quando não gravados |
| `producao_itens` | cada volume consumido/produzido (jsonb achatado) |
| `rendimento_turno` | dia × equipamento × turno, só finalizadas, com `faixa` Verde/Amarelo/Vermelho |

Usuário `powerbi_leitor`: `connection limit 20`, `default_transaction_read_only = on`,
`statement_timeout = 60s`, sem acesso às tabelas de `public`. Detalhes em [Power BI](#11-power-bi).

---

## 5. Camada de dados no front-end

- **Adaptador** `createSupabaseDB()` (em `App.jsx` e no site desktop) imita uma API de documentos:
  `db.collection(t).doc(id).set/update/get/delete` e `db.collection(t).orderBy(f,dir).limit(n).onSnapshot(cb)`.
- **Conversão de nomes:** o app usa `camelCase`; o banco usa `snake_case` (`camelToSnake`/`snakeToCamel`, só no primeiro nível).
  Por isso o conteúdo de colunas jsonb mantém as chaves como foram gravadas (ex.: `resultado.consumidoKg`).
- **Tempo real:** cada coleção assinada abre um canal `postgres_changes` e relê a tabela inteira a cada evento (`refetch`).
  O botão **Atualizar** do dashboard força `db.refetchAll()`.
- **Chave primária por coleção:** `PK = { volumes:'lote', produtos:'codigo', movimentos:'id', sessoes:'id' }`; as demais usam `id`.
- **Estado global:** objeto `state` (volumes e produtos em `Map`, listas de movimentos, sessões e produções, view atual, usuário, filtros).
- **Escritas de produção** passam por uma fila (`state.producaoFila`) para que uma gravação atrasada não sobrescreva outra.

---

## 6. Autenticação e perfis

- Login por e-mail e senha (Supabase Auth). Usuários são criados no painel do Supabase
  (*Authentication → Users*, marcando **Auto Confirm User**).
- Todo login novo vira `operador` **bloqueado** (`ativo = false`). Para liberar: *Table Editor → profiles → ativo = true*; para virar supervisor, `role = 'supervisor'`. Conta bloqueada vê "Conta aguardando liberação" e não carrega dados (app e desktop, em `onAuthed`). Desligar "Allow new users to sign up" no Supabase.
- A interface esconde elementos marcados com `data-role="supervisor"` para operadores (`applyRoleUI`). A **autorização real** é feita pelas políticas RLS do banco.
- A topbar mostra `nome · perfil · v<APP_VERSAO>`. `APP_VERSAO` está em `App.jsx` (formato `dd.mm-letra`).

**Supervisor:** importar planilha, excluir volumes (seleção em lote), excluir conferências, baixar não localizados, ver Histórico, cadastrar/atualizar produtos.
**Operador:** bipar, consultar estoque, conferir, registrar produção, ver dashboards.

---

## 7. Módulos do app (abas)

Barra inferior do app: **Início · Bipar · Estoque · Conferência · Produção · Mais** (o botão "Mais" abre a tela **Importar** e só aparece para supervisor).
A tela **Histórico** existe no código, mas **não tem botão no menu do app** (hoje só é acessível no site desktop — ver limitações).

### 7.1 Início (dashboard de estoque)
Cartões e gráficos sobre os volumes com `status = 'estoque'`: produtos em estoque (rosca), visão geral/comparativo por armazém,
histórico recente, status do estoque, consumo interno (armazém 92), "OK para carregar (93) × concessão (97) × retrabalho (98)",
quebra por armazém, e insights. Botão **Atualizar**.

### 7.2 Bipar
- Dois modos de leitura (lembrados no aparelho): **Coletor** (leitor USB/Bluetooth em modo teclado, campo sempre focado e sem teclado do celular) e **Câmera** (`BarcodeDetector`).
- Fallback por **foto/OCR**: lê o texto impresso (Código/Volume/Corrida/Peso) e remonta o código.
- Ao bipar: vibra e toca bipe (OK/erro), mostra aviso grande e o resultado do volume.
- **Ação em lote** ("Status ao bipar"): Bloquear, Transferir, texto livre etc.; fica valendo até trocar. Cada bipe grava movimento e muda o status.
- Se há conferência ativa, o bipe marca o volume como **contado**.
- Etiqueta não cadastrada: abre **cadastro manual** pré-preenchido pelo parser (o operador sempre confere antes de salvar).

### 7.3 Estoque
Lista de volumes com busca, filtros múltiplos (status e armazém), badges de situação, detalhe do volume, **troca de armazém**,
e (supervisor) **seleção e exclusão em lote**. Exporta o relatório de inventário em Excel.

### 7.4 Conferência (inventário)
Fluxo detalhado na [seção 9.3](#93-conferência-de-inventário).

### 7.5 Produção (rendimento metálico)
Dois modos: **Registrar** e **Dashboard**.

**Registrar:** equipamento (`LAM02/LAM03/RT200`) → turno → data do turno → *Iniciar registro*;
bipa/digita a **matéria-prima** consumida → *Finalizar matéria-prima* → informa o **código do produto gerado**
→ bipa/digita os **produtos** → *Finalizar produção*.
Na finalização (`producaoConcluirInterno`):
1. rolos consumidos viram `status = baixado` e geram movimento `baixado` ("Consumido na produção X");
2. produtos gerados entram no estoque já como `contado` (`origem = producao`) e geram movimento `entrada` ("Produzido em X"); se o lote não existe, é criado (o produto só é vinculado se existir em `produtos`);
3. por último a produção é fechada com `resultado`. Se algo falhar nos passos 1–2, a produção **continua aberta** e pode-se tentar de novo (idempotente: não duplica movimentos já gravados).

Outros recursos: retomada de produção em andamento (por usuário, em `localStorage`), digitação manual de rolo, remoção de item, exportação da produção.

**Dashboard:** matriz mês × dia × turno por equipamento, regras na [seção 9.4](#94-rendimento-metálico).

### 7.6 Importar (supervisor)
Aceita um ou mais `.xlsx` do relatório do Protheus. Um arquivo pode ter vários blocos "Produto:".
Para cada produto: grava em `produtos` e faz *upsert* dos volumes (8 em paralelo). **Toda importação marca os volumes como `nao_conferido`**
(é um retrato do ERP ainda não confirmado fisicamente). Registra um movimento `importacao`.

### 7.7 Histórico
Lista dos movimentos (até 200 na tela, 300 carregados) com filtro por tipo e exportação Excel. No app React a tela não tem entrada no menu; no site desktop ela está no menu lateral (supervisor).

---

## 8. Leitura de etiquetas e leitores

### 8.1 Formato da etiqueta
Código de barras lateral, sem separadores: **Volume (8) + Corrida (6) + Peso em kg (4 dígitos) + Código do produto (resto)**.
Exemplo: `PCI00047PCI0032173TPAIQ092B4` → volume `PCI00047`, corrida `PCI003`, peso `2173 kg`, produto `TPAIQ092B4`.
Tem ~25–30 caracteres, por isso exige leitor com **faixa de leitura larga**.

### 8.2 Parsers
| Função | Papel |
|---|---|
| `extractLoteCode` | remove tudo que não é letra/número, procura o lote no cadastro ou casa `[A-Z]{2,6}\d{4,7}` |
| `parseEtiquetaCodigo` | separa volume/corrida/peso/produto (exige > 18 caracteres, volume `[A-Z]{2,3}\d{4,6}`, peso com 4 dígitos) |
| `encontrarProdutoPorCodigoEtiqueta` | aceita código curto (`TPAIQ092B4`) quando só um produto do cadastro começa com ele (`TPAIQ092B4.20`) |
| `parseEtiquetaOCR` / `reconstruirCodigoEtiquetaOCR` | leitura por foto (Tesseract.js, idioma `eng`) |

### 8.3 Hardware
- Leitor recomendado (pendente de compra/validação): **laser 1D USB em modo teclado (HID)**, com boa distância de leitura.
  Candidato: Bright LB001. Pendente: medir a largura total do código e a barra mais fina da etiqueta real.
- No celular, leitor USB precisa de adaptador **OTG** (USB → USB-C); leitores Bluetooth funcionam em modo HID.
- **A verificar:** texto real lido pelo leitor para etiquetas `MB…` e `BCJ…` (o parser foi escrito para o padrão `PCI…`).

---

## 9. Regras de negócio

### 9.1 Status do volume
`estoque`, `bloqueado`, `transferido`, `baixado`. Para exibição, um volume `estoque` só aparece como **"Em estoque"** depois de contado numa conferência;
antes disso aparece como **"Aguardando conferência"** ou **"Não conferido"**.

### 9.2 Armazéns (selo físico da qualidade)
`02` desconhecido/outro galpão · `03` em análise (reteste) · `92` consumo interno/ajuste PCP · `93` OK para carregar ·
`96` rejeitar · `97` em análise (concessão) · `98` retrabalhar · `FATURADO` · `NAO_LOCALIZADO` (legado; hoje o app **não** move itens para esse armazém).

### 9.3 Conferência de inventário
1. Inicia sessão (nome opcional). Cada pessoa "segue" a sessão ativa; ela é retomada ao recarregar.
2. O **primeiro item bipado define o escopo** (produto) — com confirmação do operador. A lista **esperada** (volumes `estoque` do produto) é congelada em `esperados_snapshot`.
3. Itens de outro produto são rejeitados ("fora do escopo").
4. Cada bipe marca o volume como `contado`.
5. Ao registrar: grupos por status, lista de **faltando** (não localizados → `nao_conferido`, **sem mudar o armazém**), e **não cadastrados**; gera movimento `conferencia`.
6. Supervisor pode excluir a conferência (reverte os itens afetados) e dar baixa em não localizados.

### 9.4 Rendimento metálico
- **Rendimento = soma produzida ÷ soma consumida.** Nunca média de percentuais (vale para dia, turno, mês e total).
- Só entram produções com `etapa = 'finalizada'` e `resultado` preenchido.
- **Cor pelo número exibido (1 casa decimal):** ≥ 99,0 verde · ≥ 98,0 amarelo · abaixo vermelho. (98,96 aparece como 99,0% e fica verde.) Acima de 100% recebe ⚠ ("confira os pesos").
- **Turnos:** 1º 7h–15h20 · 2º 15h–23h20 · 3º 23h–7h20.
- Se a produção não tem turno gravado, deduz pelos cortes **07:10 / 15:10 / 23:10** (minutos 430 / 910 / 1390).
- O **3º turno antes das 07:10 conta para o dia anterior**; `data_producao` gravada tem prioridade.
- `volumes.quantidade` está em **toneladas**; pesos de produção estão em **kg**.

---

## 10. Site desktop

Arquivo único `stokk-vite/public/desktop/index.html` (servido em `/desktop/`). Usa o **mesmo banco e login** do app,
com o mesmo adaptador de dados e as mesmas políticas RLS. Visual de menu lateral, tema claro/escuro automático, cor de marca laranja.

| Aba | Observação |
|---|---|
| Início | dashboard de estoque |
| Estoque | lista e filtros |
| **Rendimento** | **(2026-10-09)** painel de rendimento metálico, **somente leitura** (ver abaixo) |
| Conferência | relatórios e acompanhamento |
| Importar | supervisor |
| Histórico | supervisor |

> O site desktop **não** registra produções (isso só existe no app). O Bipar existe como tela interna, acessada pela conferência.

### Aba Rendimento (desktop)
- Navegação por mês e filtro de equipamento (Todos/LAM02/LAM03/RT200).
- Seis indicadores: rendimento do mês (colorido), consumido, produzido, perda (+% do consumido), produções finalizadas, dias abaixo de 98%.
- Matriz dia × turno (dias mais recentes primeiro; mês corrente só até hoje); clicar num valor abre as produções.
- Gráfico de linha do rendimento diário com linhas de 99% e 98% e dicas ao passar o mouse.
- Perda por equipamento (sempre os três, o filtro só realça) e últimas produções do mês.
- **Exportar (Excel)** do mês filtrado; botão **Atualizar** (`refetchAll`).
- Dados: `db.collection('producoes').orderBy('iniciadoEm','desc').limit(1000)`; regras idênticas às do app (9.4).
- Funções (prefixo `rend`/`r`): `rendDados`, `rendCelula`, `rendGrafico`, `renderRendimento`, `rendDetalhe`, `rendExportar`.

---

## 11. Power BI

### 11.1 Conexão
- Conector **PostgreSQL**, modo **Importar**; servidor do **Session pooler** do Supabase (IPv4), porta `5432`, banco `postgres`.
- Usuário `powerbi_leitor.<ref-do-projeto>` (o usuário leva ponto e o ref). Senha definida no SQL (não guardar neste arquivo).
- No Windows foi necessário instalar o **certificado raiz do Supabase** nas Autoridades de Certificação Raiz Confiáveis.
- Erro `53300 too many connections for role`: o limite do papel foi elevado para 20.
- O Power BI Desktop é gratuito; **publicar/compartilhar** exige conta corporativa/escolar com licença (contas pessoais `@live.com` são recusadas).

### 11.2 Modelo no arquivo `Stokk.pbix`
Tabelas: `bi estoque`, `bi movimentos`, `bi conferencias`, `bi producoes`, `bi producao_itens`, `bi rendimento_turno`.
Relações: `producoes[id]` → `producao_itens[producao_id]` (um-para-muitos, um sentido) e `movimentos[lote]` → `estoque[lote]`.
(As relações automáticas erradas criadas pelo Power BI foram removidas em 2026-10-09.) `turno` e `rendimento_pct` estão como **Não resumir**.

### 11.3 Medidas existentes
`Consumido (kg)`, `Produzido (kg)`, `Perda (kg)`, `Rendimento %` (formato 0,0%), `Cor do rendimento` (hex verde `#2E9E5B` / amarelo `#E0A800` / vermelho `#D64545`),
`Faixa do rendimento` (não pôde se chamar `Faixa` porque existe a coluna `faixa`), `Volumes`, `Toneladas`.

### 11.4 Medidas planejadas — `medidas_stokk.json`
34 medidas em pastas (Estoque, Estoque\Conferência, Estoque\Origem, Rendimento, Rendimento\Por turno, Rendimento\Dias, Rendimento\Itens), entre elas
`Volumes em estoque`, `Toneladas em estoque`, `Peso médio por volume (t)`, `% conferido`, `Meta de rendimento`, `Diferença para a meta (p.p.)`,
`Rendimento 1º/2º/3º turno`, `Dias verdes/amarelos/vermelhos`, `Itens digitados à mão`. **Status: arquivo entregue; criação no modelo ainda não confirmada.**

### 11.5 Layout visual (página "Painel")
Tema `tema_stokk_escuro.json` (importado em *Design → Procurar temas*), fundo `fundo_stokk_1280x720.png` (página 1280 × 720), posições dos visuais em `posicoes.txt`.
Seis cartões, matriz, gráfico de linhas, barras de perda por equipamento, rosca de situação do estoque, tabela de produções e segmentação por equipamento.
**Status:** tema importado; montagem dos visuais em andamento.

### 11.6 MCP de modelagem (Claude Code no VS Code)
- Pasta `BI_Stokk` com `Stokk.pbix`, `ESQUEMA_STOKK.md`, `GUIA_POWERBI.md` e `.mcp.json` apontando para `@microsoft/powerbi-modeling-mcp` (via `npx`).
- Começar em `--readonly`; para criar/alterar medidas e relações usa-se `--readwrite` (em 2026-10-09 está assim). **Voltar a `--readonly` ao terminar** e trabalhar em modo manual com cópia de segurança do `.pbix`.
- Os termos de licença (EULA) do MCP são aceitos pelo usuário.
- O MCP **não monta visuais**; só modelo (tabelas, medidas, relações, DAX).
- Instalar a extensão **Claude Code for VS Code** (Anthropic); o terminal do Claude Code é o que carrega o `.mcp.json`.

### 11.7 Observação sobre unidades
Teste em 2026-10-09: 202 volumes e 2.358,263 t no estoque (~11,7 t/volume). Conferir se a unidade importada (t × kg) está correta.

---

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

## 13. Segurança e operação

- A **anon key** do Supabase está no código (`App.jsx` e site desktop). É pública por design; a proteção real vem da **RLS** e do login.
- **Defesa em profundidade (update_008):** o JavaScript do navegador pode ser editado por qualquer um, então toda autorização está no banco (RLS, permissões por coluna, triggers). Editar o código da página não dá acesso a dados nem permite virar supervisor.
- CDNs com versão fixa (`supabase-js@2.117.1`, `tesseract.js@5.1.1`, `xlsx 0.18.5`). `xlsx 0.18.5` tem falhas conhecidas ao ler planilhas maliciosas; só supervisores importam planilhas (arquivos de fonte confiável).
- Não publicar o `.pbix` em repositório público (pode conter dados).
- Nunca colocar no repositório: `service_role key`, senha do banco ou a senha de `powerbi_leitor`.
- `powerbi_leitor` só lê o schema `bi`, em transação somente leitura, com timeout de 60 s.
- **Pausa do Supabase (plano gratuito):** o projeto pausa após ~1 semana sem uso. Basta retomar no painel; os usuários foram orientados a não deixar pausar.
- Realtime exige as tabelas na publication `supabase_realtime` (feito nos SQLs).
- Backup: o `.pbix` e o banco devem ter cópia antes de alterações grandes.

---

## 14. Limitações conhecidas

1. **Limite de 1000 linhas** por consulta do Supabase: `volumes` e `produtos` são lidos sem paginação (hoje ~200 volumes; vai quebrar ao passar de 1000). Produções são lidas com `limit(1000)`.
2. `refetch` relê a tabela inteira a cada evento de tempo real (custo cresce com o volume de dados).
3. `App.jsx` é um arquivo único de ~3,5 mil linhas com HTML em *template strings* (difícil de testar/dividir).
4. Produções finalizadas **não podem ser excluídas** pelo app (a política RLS permite ao supervisor, mas não há botão).
4b. A tela **Histórico** não tem botão no menu do app (só no site desktop).
5. O parser de etiqueta foi validado só com o padrão `PCI…`; faltam amostras reais de `MB…` e `BCJ…`.
6. Importação do Protheus é manual (planilha), sem API.
7. OCR depende de internet (Tesseract carregado do jsDelivr).
8. O site desktop não registra produções nem edita estoque além do que já faz hoje.
9. Alterações recentes estão **sem commit** no git (ver seção 3).
10. Power BI: atualização manual (ou agendada só após publicar no serviço, que exige conta corporativa).
11. `update_008` ainda **não foi aplicado em produção**: até lá vale a RLS antiga (qualquer cadastrado pode editar o próprio `role`). `powerbi_leitor` lê as views `bi` fora da RLS: manter senha forte e fora do repositório.

---

## 15. Backlog

- Notificação push (celular) para conferência esquecida em aberto: exige Firebase (FCM) + Capacitor Push + rotina agendada no servidor.
- Rotina diária (GitHub Actions) + função `ping()` no banco para evitar a pausa do Supabase gratuito.
- Paginação de `volumes`/`produtos` (limite de 1000 linhas).
- Exclusão de produção finalizada (com reversão de estoque).
- Notificações push no celular (não construído; viável via Capacitor + FCM).
- "Pinger"/botão de restauração para o Supabase pausado.
- Impressão de etiquetas.
- Integração com a API do Protheus.
- Ajuste do parser com texto real do leitor USB (`MB…`, `BCJ…`).
- Confirmar e aplicar as 34 medidas do `medidas_stokk.json`; concluir a página "Painel" do Power BI; segunda página de estoque/conferências.
- Roteiro de apresentação para a diretoria (o app com dados reais primeiro; o Power BI como complemento).
- Aba Produção também no app com o mesmo visual do desktop (gráfico e perda por equipamento).
- Comprar/validar o leitor de código de barras de longo alcance.

---

## 16. Histórico de mudanças

> Mais recente primeiro. Datas aproximadas pelos arquivos quando não houve registro exato.

| Data | Mudança |
|---|---|
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

### Visual customizado Power BI "STOKK Gráficos" (2026-10-11)
- Arquivo `STOKK_Graficos.pbiviz` (projeto `stokkGraficos`, powerbi-visuals-tools 7.2.1, API 5.11). Um único visual com tipo escolhido em Formatar → Gráfico: barras horizontais, rosca, colunas empilhadas, linha (com meta e linhas 99/98) e alerta.
- Campos: Categoria (eixo), Valores (vários = séries empilhadas/linhas), Meta (opcional). Cores por faixa (≥99 verde, ≥98 amarelo, abaixo vermelho; 1 casa decimal) opcionais.
- Status: testado só em navegador com dados simulados; NÃO testado dentro do Power BI. Administrador do tenant pode bloquear visuais não certificados no Serviço.

