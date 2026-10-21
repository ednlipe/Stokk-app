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
