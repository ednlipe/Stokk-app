# STOKK — Mapa do `src/App.jsx` (para dividir em módulos)

> (10/11: bloco "LOC-CORE" (turnos/linha do tempo dos locais) logo antes do trecho Localização, e `gLocalTurnos`/`gTurnoVer`/`gTurnoExportar` junto de `renderGLocal`. v1.8.0: bloco "STOKKBOOK" (feed) antes de "USUÁRIOS". v1.7.0: bloco "USUÁRIOS" (administrador) logo antes de "XLSX EXPORT". v1.6.0: blocos "5S — núcleo" e "5S — telas" no fim, antes de "XLSX EXPORT".) Só mapeamento: **nada foi movido**. Linhas aproximadas da v1.4.2 (4.480 linhas, 202 funções). Na v1.5.0 entraram mais dois blocos no fim do `App.jsx`, antes da exportação XLSX: **Diesel — núcleo** (funções puras `dsl*`, testadas; candidato fácil a módulo) e **Diesel — telas** (~500 linhas, independente das outras telas). Na v1.5.1 entrou, dentro do bloco de telas do diesel (antes de "Equipamentos"), o trecho **Paradas e manutenção** (`renderGManut`, `gManut*`, `MANUT_*`); na v1.5.2, o trecho **Localização** (`renderGLocal`, `gLocal*`) logo antes dele.
> Status: proposta, não executada.

## Como o arquivo é hoje
- Linhas 1–230: imports e o HTML de todas as telas (`APP_HTML`, texto). Cada tela é uma `<section class="view" id="view-…">`.
- Linhas 231–243: componente React `App`, que injeta o HTML (`dangerouslySetInnerHTML`) e roda a lógica no `useEffect`.
- Linhas 241–4475: **uma única função (IIFE)** com toda a lógica. As funções compartilham variáveis do mesmo escopo (`state`, `sb`, `db`, `esc`…). É isso que torna a divisão trabalhosa.
- Linhas 4476–4480: fim do componente.

## Blocos
| Bloco | Linhas | ~Tam. | Depende de | Risco ao separar |
|---|---|---|---|---|
| HTML das telas | 1–230 | 230 | nada | Baixo |
| Config Supabase, `state`, adaptador do banco, áreas | 244–492 | 250 | — (base de tudo) | Médio |
| Autenticação e push | 493–618 | 125 | state, sb | Médio |
| Utilidades, status, armazém, categoria/bitola, tema | 619–888 | 270 | quase nada (funções puras) | **Baixo** |
| Leitura da etiqueta (pátio e foto) | 889–995 | 105 | utilidades | Baixo |
| Assinaturas de dados, navegação | 996–1138 | 140 | state, telas | Alto (liga tudo) |
| Dashboard | 1139–1354 | 215 | state, utilidades | Médio |
| Bipar | 1355–1949 | 600 | state, etiqueta, estoque | Alto |
| Estoque + seleção/exclusão em lote | 1950–2390 | 440 | state, utilidades | Médio |
| Importar planilha | 2391–2526 | 135 | state, utilidades | Baixo |
| Inventário / conferência (+ relatório) | 2527–3079 | 550 | state, etiqueta | Alto |
| Produção (rendimento metálico) | 3080–3842 | 760 | state, utilidades | Médio |
| Histórico | 3843–3877 | 35 | state | Baixo |
| Contagem cega — núcleo (etiqueta, planilha, comparação) | 3878–4006 | 130 | utilidades (tem `tests/cega_core.test.cjs`) | **Baixo** |
| Contagem cega — telas | 4007–4436 | 430 | núcleo, state | Médio |
| Exportação XLSX | 4437–4470 | 35 | utilidades | Baixo |
| Inicialização (`boot`) | 4471–4475 | 5 | tudo | Médio |

## Ordem sugerida (do mais seguro ao mais arriscado)
1. **Utilidades puras** (`fmtPeso`, `esc`, status, categoria/bitola) → `src/lib/util.js`.
2. **Núcleo da contagem cega** → `src/lib/cega.js` (os testes já existem).
3. **Exportação XLSX** e **leitura da etiqueta**.
4. **`state` e adaptador do banco** → módulos que os outros importam.
5. **Telas, uma por vez**, começando por Histórico, Importar e Estoque; deixar Bipar e Conferência por último.
6. Navegação e `boot` ficam no fim, depois de todo o resto.

## Regras para cada passo
- Só mover código; nenhuma regra de negócio muda na mesma entrega.
- Rodar `node tests/cega_core.test.cjs`, a build do Vite e abrir as telas no Playwright (com Supabase simulado) antes de entregar.
- Uma entrega por módulo, para voltar atrás sem perder o resto.
- O desktop (`public/desktop/index.html`) é separado e não entra nessa divisão.
