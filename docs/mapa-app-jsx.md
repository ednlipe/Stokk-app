# STOKK — Mapa do `src/App.jsx` (para dividir em módulos)

> **Atualizado em 25/11/2026** (branch `teste`, depois da correção do tempo real): 6.715 linhas contando com `wc -l` (quebras de linha; 6.698 no commit `155145f` + 17 da correção), das quais 202 em branco (6.513 sem elas), ~400 funções. Só mapeamento: **nada foi movido**. Linhas aproximadas; mudam a cada entrega.
> Status: proposta, não executada. A divisão fica para uma etapa futura, quando não houver correções funcionais ou pendências prioritárias.

## Como o arquivo é hoje
- Linhas 1–9: imports (`react`, `xlsx`, `@supabase/supabase-js`, `@capacitor/core`).
- Linhas 10–277: o HTML de todas as telas (`APP_HTML`, texto). Cada tela é uma `<section class="view" id="view-…">`.
- Linhas 279–288 e 6711–6715: componente React `App`, que injeta o HTML (`dangerouslySetInnerHTML`) e roda a lógica no `useEffect`.
- Linhas 289–6710: **uma única função (IIFE)** com toda a lógica. As funções compartilham variáveis do mesmo escopo (`state`, `sb`, `db`, `esc`…). É isso que torna a divisão trabalhosa.
- **Blocos marcados `*-CORE-INICIO`/`*-CORE-FIM`** (ou com comentário "MESMA cópia no desktop"): têm cópia idêntica em `public/desktop/index.html` e testes em `tests/*.test.cjs` que comparam as duas. Ao mover, o teste tem que continuar achando o bloco (ou ser ajustado na mesma entrega).

## Blocos
| Bloco | Linhas | ~Tam. | Depende de | Risco ao separar |
|---|---|---|---|---|
| HTML das telas (`APP_HTML`) | 10–277 | 270 | nada | Baixo |
| Config Supabase (`__AMBIENTE__`, `__SUPABASE_URL__`, faixa de teste), `state`, `PK` e conversores `camelToSnake`/`objToCamel` | 291–359 | 70 | `vite.config.js` (define) | Médio |
| Áreas, `ABAS_DA_AREA`, `GRUPOS_MENU`, MENU-CORE (387–414), menu e troca de área | 360–544 | 185 | state, sb | Médio |
| UPD-CORE (`updExecutar`, `updMsg`; `tests/update_core.test.cjs`) | 545–556 | 12 | nada | **Baixo** |
| Adaptador do banco `createSupabaseDB` (`collection`, `onSnapshot`, `refetch`, `releituraRealtime`, `completarAntigos`, `refetchAll`) e `createBrowserDownloads` | 558–734 | 175 | sb, state, áreas, UPD-CORE | Médio (base de tudo; `tests/completar_antigos.test.cjs` e `tests/realtime_core.test.cjs` leem o adaptador do app e do desktop) |
| Autenticação, push (`registrarPush`), BIO-CORE (846–849) e `boot` | 735–948 | 215 | state, sb | Médio |
| Utilidades, status, armazém, categoria/bitola, arrastar para fechar, tema | 949–1204 | 255 | quase nada (funções puras) | **Baixo** |
| Leitura da etiqueta (lote, etiqueta de pátio, foto) | 1205–1325 | 120 | utilidades | Baixo |
| Assinaturas de dados (`subscribeData`) | 1329–1420 | 90 | state, adaptador, telas | Alto (liga tudo) |
| Navegação (`setView`, `renderAll`), NAV-CORE (1461–1466) | 1421–1537 | 115 | state, telas | Alto (liga tudo) |
| Dashboard (armazém, consumo interno, 93/97/98, status, produtos) | 1538–1753 | 215 | state, utilidades | Médio |
| Bipar | 1754–2348 | 595 | state, etiqueta, estoque | Alto |
| Estoque + seleção/exclusão em lote | 2349–2789 | 440 | state, utilidades | Médio |
| Importar planilha | 2790–2925 | 135 | state, utilidades | Baixo |
| Inventário / conferência (+ relatório) | 2926–3478 | 550 | state, etiqueta | Alto |
| Produção (rendimento metálico) | 3479–4241 | 765 | state, utilidades | Médio |
| Histórico | 4242–4276 | 35 | state | Baixo |
| Contagem cega — núcleo (`tests/cega_core.test.cjs`) | 4277–4405 | 130 | utilidades | **Baixo** |
| Contagem cega — telas | 4406–4835 | 430 | núcleo, state | Médio |
| Diesel — núcleo (`dsl*`, `dslOcorrencia*`, `dslLocalAtual`; `tests/diesel_core.test.cjs`) | 4836–5019 | 185 | nada (funções puras) | **Baixo** |
| Diesel — telas (Resumo, Abastecer, Tanque) | 5020–5325 | 305 | núcleo, state | Médio |
| LOC-CORE (turnos e linha do tempo dos locais; `tests/locais_core.test.cjs`) | 5326–5424 | 100 | nada | **Baixo** |
| Localização (`renderGLocal`, `gLocal*`, `gLocalTurnos`, `gTurnoVer`, `gTurnoExportar`) | 5426–5630 | 205 | LOC-CORE, núcleo diesel, state | Médio |
| Paradas e manutenção (`renderGManut`, `gManut*`, `MANUT_*`) | 5631–5784 | 155 | núcleo diesel, state | Médio |
| Equipamentos, anular/exportar/cliques da Gestão, `subscribeDiesel` | 5785–5912 | 130 | telas da Gestão | Médio |
| 5S — núcleo (`c5*`; `tests/cinco_s_core.test.cjs`) | 5913–5968 | 55 | nada | **Baixo** |
| 5S — telas (foto, listas, janelas, `subscribeCinco`) | 5969–6252 | 285 | núcleo 5S, state, Storage | Médio |
| Stokkbook (SBK-CORE 6259–6285; `tests/stokkbook_core.test.cjs`) | 6253–6416 | 165 | state, sb | Médio |
| Usuários (administrador; Edge Function `admin-usuarios`) | 6417–6582 | 165 | state, sb | Baixo |
| Atualização do APK (ATU-CORE 6593–6607; `tests/atualizacao_core.test.cjs`) | 6583–6667 | 85 | Capacitor | Baixo |
| Exportação XLSX | 6668–6705 | 40 | utilidades | Baixo |
| Inicialização (`resetScanOff`, `boot()`) | 6706–6710 | 5 | tudo | Médio |

## Ordem sugerida (do mais seguro ao mais arriscado)
1. **Núcleos puros já testados** (cega, diesel, LOC-CORE, 5S, UPD-CORE, NAV/MENU/SBK/ATU-CORE) → `src/lib/*.js`. Atenção: os testes leem esses blocos do `App.jsx` e comparam com o desktop; ajustar os testes na mesma entrega.
2. **Utilidades puras** (`fmtPeso`, `esc`, status, categoria/bitola) → `src/lib/util.js`.
3. **Exportação XLSX** e **leitura da etiqueta**.
4. **`state` e adaptador do banco** → módulos que os outros importam.
5. **Telas, uma por vez**, começando por Histórico, Importar, Usuários e Estoque; deixar Bipar e Conferência por último.
6. Navegação, assinaturas e `boot` ficam no fim, depois de todo o resto.

## Regras para cada passo
- Só mover código; nenhuma regra de negócio muda na mesma entrega.
- Rodar todos os `tests/*.test.cjs` (Node 22.13+ para `admin_usuarios` e `diesel_aviso`), a `npm run build:teste` e abrir as telas no ambiente de teste antes de entregar.
- Uma entrega por módulo, para voltar atrás sem perder o resto.
- O desktop (`public/desktop/index.html`) é separado e não entra nessa divisão, mas tem cópias idênticas dos núcleos: se um núcleo mudar de lugar no app, o teste que compara as duas cópias tem que continuar passando.
