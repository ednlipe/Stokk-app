# STOKK — Power BI

> Conexão, modelo, medidas, layout, visual customizado STOKK Gráficos.
> Índice geral: [`docs/README.md`](README.md). Regra: mudou algo desta área, atualize ESTE arquivo e uma linha em [`historico.md`](historico.md).

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


### Visual customizado Power BI "STOKK Gráficos" (2026-10-11)
- Arquivo `STOKK_Graficos.pbiviz` (projeto `stokkGraficos`, powerbi-visuals-tools 7.2.1, API 5.11). Um único visual com tipo escolhido em Formatar → Gráfico: barras horizontais, rosca, colunas empilhadas, linha (com meta e linhas 99/98) e alerta.
- Campos: Categoria (eixo), Valores (vários = séries empilhadas/linhas), Meta (opcional). Cores por faixa (≥99 verde, ≥98 amarelo, abaixo vermelho; 1 casa decimal) opcionais.
- Status: testado só em navegador com dados simulados; NÃO testado dentro do Power BI. Administrador do tenant pode bloquear visuais não certificados no Serviço.
- **Alerta com faixas (2026-10-12):** Formatar → Opções → "Alerta: vermelho a partir de" (padrão 1) e "amarelo a partir de" (0 = não usar). Valor abaixo = verde com ✓. Ex.: dias sem inventário vermelho ≥ 15, amarelo ≥ 7; conferências abertas > 12 h vermelho ≥ 1. Substitui a opção antiga "zero = tudo certo".
- **Medidas DAX (sem mudar banco):** `Dias sem inventário` = `DATEDIFF(MAX(conferencias[finalizado_em]) com situacao="Finalizada" e REMOVEFILTERS(Calendario), NOW(), DAY)`; `Dias sem inventário (alerta)` devolve 999 se nunca houve conferência. Status: não testado no Power BI.
- **Rosca igual à referência (2026-10-12):** legenda abaixo (ou "ao lado"), total grande no centro com texto configurável, cores por situação (contado = verde-água, aguardando = cinza, não localizado = vermelho) ou por nome em Formatar → Rosca → "Cores por nome". Legenda mostra percentual, valor ou ambos.
- **Linha/colunas:** eixo Y com graduação automática redonda e casas decimais conforme a escala; categorias vazias sem valor são ignoradas; opção "Multiplicar valores por" (100 quando a medida vem em fração, ex.: 0,966). Status: testado só em navegador, não no Power BI.
- **Glow Card v1.3 (2026-10-12):** Formatar → Card → "Cor pela faixa" (verde ≥ 99, amarelo ≥ 98, vermelho abaixo; limites editáveis). Pinta borda e brilho com a cor da faixa; se o formato da medida tem `%`, o valor é multiplicado por 100 antes de comparar. Título pode quebrar em 2 linhas (antes cortava com "…"). Status: testado só em navegador.
- **Barras — nomes longos (2026-10-12):** o nome do item quebra em até 2 linhas (antes cortava com "…") e a largura da coluna de nomes é ajustável em Formatar → Opções → "Barras: largura dos nomes" (padrão 40% do visual).


### Página 2 — Rendimento metálico (roteiro entregue 2026-10-12)
- Slicers: data (canto superior direito, igual Geral) + tiles Equipamento e Turno (y150).
- Cards (Glow Card, y208, 251×108): Rendimento no período (cor pela faixa, secundário Meta 99%), Consumido t, Produzido t, Perda t (% do consumido), Produções finalizadas (dias com produção), Dias abaixo de 98%.
- Visuais: Matriz dia × turno (300,334 620×722, cor condicional), Linha rendimento por dia (STOKK Gráficos, 938,334 958×340, faixas 99/98), Perda por equipamento (barras, 938,692 470×364), Últimas produções (tabela Top 7, 1426,692 470×364).
- Medidas novas (pasta Rendimento): Consumido t, Produzido t, Perda t, Rendimento (%), Meta rendimento, Perda % do consumido, Produções, Dias com produção, Dias abaixo de 98%, Cor rendimento (BI). Colunas: Turno (nome)/(curto), Calendario[Já passou]. Tabela Equipamentos (dimensão) ligada a rendimento_turno e producoes.
- Status: criação no modelo pelo usuário/Claude Code ainda não confirmada.
- Visual `STOKK Segmentação` (/tmp/o/STOKK_Segmentacao.pbiviz): Campo → coluna; formato: título, TODOS, seleção múltipla, orientação, fonte, cor do selecionado. Fonte em scratchpad/stokkviz/stokkSeg.
- Visual `STOKK Matriz` (/tmp/o/STOKK_Matriz.pbiviz): Linhas=Dia, Colunas=Turno (nome), Valor=Rendimento, Total do dia/Total do período por turno/Total geral = medidas com REMOVEFILTERS/ALLSELECTED. Fonte em scratchpad/stokkviz/stokkMatriz.
- Visual `STOKK Lista` (/tmp/o/STOKK_Lista.pbiviz): campos Ordenar por, Linha 1, Linha 2, Valor; colunas calculadas Título/Detalhe última em 'bi producoes' e medida Rendimento produção. Fonte em scratchpad/stokkviz/stokkLista.
- 2026-10-13: Matriz 1.1 e Gráficos 1.1 (dias sem dados não aparecem; medidas com ALLSELECTED/meta constante tornavam todas as datas do Calendario não-vazias).


### Ajustes de 2026-10-14/15 (kg e armazéns)
- Pesos em **kg**: medidas de estoque passaram a usar `bi estoque[quantidade_kg]` (formato `#,0" kg"`); sufixos dos gráficos STOKK trocados de ` t` para ` kg`. Página Rendimento usa `Consumido (kg)`, `Produzido (kg)`, `Perda (kg)`.
- Cards em "t" acima de 3.000 kg: medidas de texto `<nome> (card)` (regra: ≥ 3000 → `FORMAT(v/1000,"#,##0.0") & " t"`, senão `FORMAT(v,"#,##0") & " kg"`). A FormatString condicional do Power BI não suporta isso, por isso são medidas novas só para exibição.
- Gráfico "Peso por armazém" usa a coluna calculada `'bi estoque'[Armazém (rótulo)]` ("Arm. 44", ..., "Sem armazém"), pois os armazéns reais do estoque (44, 61, 02, 55) não existem na tabela `Armazéns` (93/97/98/92). "Comparativo de qualidade" continua com `Armazéns[nome]` (93/97/98).
- Alterações no modelo só persistem se salvar (Ctrl+S) antes de fechar o Power BI Desktop.
- Pendente no relatório: ajustar `Calendario` (início na menor data de movimentos), trocar campos dos cards pelas medidas "(card)" e sufixos ` kg` restantes na página Estoque.

### Áreas (2026-10-20, update_012)
As views `bi.estoque`, `bi.movimentos`, `bi.conferencias`, `bi.producoes`, `bi.producao_itens` e `bi.rendimento_turno` ganharam as colunas `area` (id: `trefila`/`planta1`) e `area_nome` no fim; `bi.rendimento_turno` agora também agrupa por área. Novas: `bi.areas` e `bi.armazens_area`. O `powerbi_leitor` vê **todas** as áreas, então os relatórios atuais passam a somar Trefilaria + Planta 1 até filtrarem por `area_nome`. **Ação no Power BI:** atualizar o modelo/consulta das tabelas, criar uma segmentação por `area_nome` (sincronizada entre as 3 páginas) e, se quiser, uma dimensão a partir de `bi.areas`/`bi.armazens_area` (os armazéns da Planta 1 ainda serão cadastrados em `armazens_area`). Salvar com Ctrl+S. **Status:** não aplicado no `.pbix`.
