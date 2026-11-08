# STOKK — Site desktop

> `stokk-vite/public/desktop/index.html`.
> Índice geral: [`docs/README.md`](README.md). Regra: mudou algo desta área, atualize ESTE arquivo e uma linha em [`historico.md`](historico.md).

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

### Contagem cega (desktop, v1.4.0)
"Iniciar conferência" abre o popup Padrão/Cega; o nome opcional da cega é digitado no próprio popup (`#cega-nome-popup`).
Mesma regra do app (`regras-de-negocio.md` §9.3.1). No desktop o leitor (USB ou Bluetooth em modo teclado) digita no campo `#cega-input` da própria tela de Conferência; a lista fica abaixo. **Status:** testado em navegador com API simulada.

### Abastecimento e Localização (desktop, v1.5.3)
Na área **Veículos Móveis** (`gestao`) o desktop tem **duas abas**: **Abastecimento** (antes "Diesel": filtros, totais, gráficos, tanques, compras, alertas, últimos abastecimentos, botões + Abastecimento / + Tanque / + Equipamento, Excel de abastecimento) e **Localização** (`renderLocais`, `view-locais`).
- **Localização:** cabeçalho com contadores (Operando, Parados, Em manutenção, Sem local) e relógio; um cartão grande por equipamento ativo (local atual, desde quando e quem informou, motivo e tempo da parada; aviso se o local está sem atualização há mais de 24 h); ordenação: manutenção, parado, operando. Atualiza a tela a cada 30 s e relê o banco a cada 60 s (além do realtime).
- **Modo parede:** botão "Modo parede (tela cheia)" põe a aba em tela cheia (`requestFullscreen`), com letras maiores e sem botões/tabelas (Esc sai) — feito para TV/monitor.
- Fora do modo parede a aba traz os botões **+ Ocorrência** / **Atualizar local** / **+ Equipamento**, o bloco de paradas e manutenção (liberar, corrigir, detalhes) e a tabela "Equipamentos e onde estão", com período próprio (`state.locPer/locMes/locAno`, independente do da aba Abastecimento) e Excel próprio (abas Paradas e Local atual).
- **v1.5.4:** a releitura automática de 60 s do painel usa `db.refetchTabelas(['ocorrencias','equipamento_locais'])` (só o que o painel mostra), não mais `refetchAll()` (que relia também os 10.000 abastecimentos). O botão "↻ Atualizar" continua relendo tudo. O bloco de paradas desta aba mostra todas as ocorrências (não segue os filtros de equipamento/tipo da aba Abastecimento).
- Funções: `renderLocais`, `dslCartaoParede`, `dslSituacaoEquip`, `locPeriodo`, `locExportar`. **Status:** testado no navegador com dados simulados (abas, cartões, salvar local, exportar); **a tela cheia real (TV) não foi testada** (navegador de teste não abre tela cheia).

### 5S — Gestão Planta 1 (desktop, v1.6.0)
Na área **Gestão Planta 1** o desktop tem duas abas (`ABAS_DA_AREA`): **Resumo 5S** (`renderC5Resumo`) e **Galeria** (`renderC5Galeria`). Só leitura das fotos; o supervisor também anula.
- **Resumo 5S:** período (Mês com setas, 30 dias, Ano); alerta de abertos há mais de 7 dias; KPIs (concluídos e abertos no período, em aberto agora, tempo médio); gráfico de concluídos por dia (por mês no Ano); tabelas por setor e por pessoa; últimos 6 concluídos com antes/depois; **Exportar (Excel)** com 3 abas (5S, Por setor, Por pessoa).
- **Galeria:** cartões com ANTES e DEPOIS lado a lado; filtros Todos / Em aberto / Concluídos / Anulados e por setor; até 60 por vez. Clicar abre o detalhe com as fotos grandes (clique na foto para ampliar em outra aba) e, para supervisor, **Anular 5S**.
- **Turnos (v1.6.2):** cada cartão tem uma faixa em **negrito** com o turno (1º amarelo, 2º laranja e 3º azul, em tons pastel) e a hora; na Galeria há botões **Todos os turnos / 1º / 2º / 3º** e **Agrupar por turno** (ligado por padrão: uma seção colorida por turno, com a faixa de horário e o total); o Resumo 5S tem três cartões coloridos com concluídos e abertos de cada turno; o Excel ganhou as colunas "Turno da abertura" e "Turno da conclusão". Só no desktop (o app do celular não mostra turno).
- **Várias fotos (v1.6.1):** o cartão mostra a primeira foto de cada lado com o selo "N fotos"; o detalhe mostra todas (clique em qualquer uma para ampliar em outra aba).
- Núcleo `c5*` idêntico ao do app (`tests/cinco_s_core.test.cjs` confere). As fotos usam links temporários de 1 h (`c5Urls`).
- **Status:** testado no navegador com dados simulados (abas, filtros, fotos carregando, exportar, anular); **não testado** com fotos e banco reais.

### Painel de Diesel (desktop, v1.5.0)
Aba **Diesel**, só na área **Gestão** (as outras áreas não a mostram; na Gestão ela é a única aba). **Só leitura:** os lançamentos são feitos no app. Mesmo núcleo de cálculo do app (bloco "DIESEL — núcleo", cópia idêntica; `tests/diesel_core.test.cjs` falha se divergirem).
- **Filtros:** período (Mês com setas, 30 dias, Ano), equipamento e tipo.
- **Totais:** diesel consumido, abastecimentos (e litros por abastecimento), gasto, custo médio por litro, comprado (litros, valor, preço médio) e saldo atual do tanque.
- **Gráficos:** litros e gasto por dia (por mês no Ano), com dica ao passar o mouse; **por equipamento** (litros, abastecimentos, gasto, consumo médio); **tanques** (saldo, custo médio, dias que dura, última régua); **alertas** (sem abastecer e consumo fora do normal); últimos abastecimentos e compras.
- **Paradas e manutenção (v1.5.1):** bloco abaixo dos alertas (`dslBlocoParadas`): parados agora, ocorrências abertas no período, horas paradas, tempo médio até liberar, lista dos em aberto, horas por motivo e últimas liberações (o que foi feito e quem pegou). Respeita os filtros de período, equipamento e tipo. Sem o `update_016`, mostra só o aviso.
- **Lançar e editar pelo desktop (v1.5.2):** o painel deixou de ser só leitura. Barra de botões no topo: **+ Abastecimento**, **+ Ocorrência (parada / manutenção)** e **Atualizar local** (qualquer conta da Gestão) e, só para supervisor, **+ Tanque** e **+ Equipamento**. Nos cartões de tanque (supervisor): **+ Compra**, **Conferir régua**, **Editar**. Em **Paradas e manutenção**: cada ocorrência em aberto tem **Liberar** e **Corrigir** (supervisor) e **Detalhes** (com **Anular**); as liberações têm "ver". Novo bloco **Equipamentos e onde estão** (local atual, situação, atualizar local, histórico e, para supervisor, editar). As tabelas de últimos abastecimentos e compras têm **anular** (supervisor). São as **mesmas janelas e validações do app** (copiadas de `src/App.jsx`, bloco "DIESEL — lançamentos e cadastros (desktop)"); a permissão de verdade é a do banco (RLS), então quem não é supervisor nem vê os botões e o banco recusaria de qualquer jeito. A janela de abastecimento fica aberta para lançar o próximo. Aviso push ao abrir/liberar ocorrência também sai do desktop (mesma chamada à Edge Function).
- **Exportar (Excel):** 4 abas (Por equipamento, Abastecimentos, Compras, Paradas) do período e filtros escolhidos.
- **Também nesta versão (desktop):** a leitura passou a ser paginada (páginas de 1000, igual ao app) e `movimentos` passou a gravar com INSERT (antes usava "upsert" e daria "permission denied" ao importar planilha).
- Funções: `renderDiesel`, `dslPeriodo`, `dslFiltrados`, `dslBaldes`, `dslGrafico`, `dslExportar`, `subscribeDiesel`. **Status:** testado no navegador com dados simulados (supervisor e operador: lançar, ocorrência, liberar, corrigir, local, cadastros, compra, anular); não testado em produção.
