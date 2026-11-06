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

### Painel de Diesel (desktop, v1.5.0)
Aba **Diesel**, só na área **Gestão** (as outras áreas não a mostram; na Gestão ela é a única aba). **Só leitura:** os lançamentos são feitos no app. Mesmo núcleo de cálculo do app (bloco "DIESEL — núcleo", cópia idêntica; `tests/diesel_core.test.cjs` falha se divergirem).
- **Filtros:** período (Mês com setas, 30 dias, Ano), equipamento e tipo.
- **Totais:** diesel consumido, abastecimentos (e litros por abastecimento), gasto, custo médio por litro, comprado (litros, valor, preço médio) e saldo atual do tanque.
- **Gráficos:** litros e gasto por dia (por mês no Ano), com dica ao passar o mouse; **por equipamento** (litros, abastecimentos, gasto, consumo médio); **tanques** (saldo, custo médio, dias que dura, última régua); **alertas** (sem abastecer e consumo fora do normal); últimos abastecimentos e compras.
- **Paradas e manutenção (v1.5.1):** bloco abaixo dos alertas (`dslBlocoParadas`): parados agora, ocorrências abertas no período, horas paradas, tempo médio até liberar, lista dos em aberto, horas por motivo e últimas liberações (o que foi feito e quem pegou). Respeita os filtros de período, equipamento e tipo. Sem o `update_016`, mostra só o aviso.
- **Exportar (Excel):** 4 abas (Por equipamento, Abastecimentos, Compras, Paradas) do período e filtros escolhidos.
- **Também nesta versão (desktop):** a leitura passou a ser paginada (páginas de 1000, igual ao app) e `movimentos` passou a gravar com INSERT (antes usava "upsert" e daria "permission denied" ao importar planilha).
- Funções: `renderDiesel`, `dslPeriodo`, `dslFiltrados`, `dslBaldes`, `dslGrafico`, `dslExportar`, `subscribeDiesel`. **Status:** testado no navegador com dados simulados; não testado em produção.
