# STOKK — Regras de negócio

> Status, armazéns, conferência, rendimento metálico. App, site e Power BI devem seguir as mesmas regras.
> Índice geral: [`docs/README.md`](README.md). Regra: mudou algo desta área, atualize ESTE arquivo e uma linha em [`historico.md`](historico.md).

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

### 9.3.1 Contagem cega (v1.4.0)
Conferência ao contrário: **primeiro bipa tudo, depois compara com a planilha do Protheus**. Não altera o estoque (`volumes`); guarda em `sessoes` (`tipo='cega'`, `itens`, `contados` = lista de lotes).
- **Leitura da etiqueta (código de barras da lateral)** — campos colados, lidos **por posição** (as letras do volume e da corrida mudam e nada depende delas): volume (8) + corrida (6) + peso em kg (4 dígitos) + código do produto (termina na **bitola** `B` + número + `.` + 2 casas, ex. `B4.20`) + quantidade de peças (o que sobra). Ex.: `PCI00096PCI0032202TPAIQ092B4.20100`. Aceita também o código curto de baixo da etiqueta (só o volume). Se não separar produto/peças, o item entra marcado **"revisar"**; código fora do padrão **não é contado** (aparece em "leituras fora do padrão"). Lote repetido não conta duas vezes.
- **Chave de comparação:** o **Volume** da etiqueta é o **Lote** do Protheus.
- **Planilha:** o mesmo relatório do Protheus que a aba Importar lê (blocos `Produto:` + linhas `Saldo / Saldo Inicial`, com armazém e lote). A quantidade vem em **toneladas** (UM `TL`) e vira kg; linhas de saldo **repetidas** no relatório são ignoradas; vendas futuras (`Saída`) são ignoradas.
- **Comparação:** *conferem*, *faltando* (na planilha e não bipado), *sobrando* (bipado e fora da planilha), *peso diferente* (tolerância 1 kg; só quando a etiqueta traz o peso), *em outro armazém* (existe na planilha, mas em armazém fora do filtro escolhido), *produto diferente* (informativo) e *para revisar*. O filtro de armazéns escolhe quais armazéns da planilha entram na conta (nenhum = todos).
- **Fluxo:** Conferência › **Iniciar conferência** › popup "Qual tipo de conferência?" (**Padrão** = como antes; **Cega**) › bipar › **Comparar com a planilha** › (opcional) filtrar armazéns › **Exportar planilha** › **Encerrar e guardar**. Dá para sair e continuar depois; o app retoma a contagem deste aparelho.
- **Limites:** uma pessoa/aparelho por contagem (dois aparelhos na mesma contagem se sobrescrevem); a comparação usa a planilha que você subir (se estiver velha, aparecem falsas diferenças); só roda no app e no site desktop (no desktop, o leitor digita no campo da tela).
- **Código:** núcleo em `src/App.jsx` (bloco "CONTAGEM CEGA — núcleo": `cegaLerEtiqueta`, `cegaLerPlanilha`, `cegaComparar`) e cópia idêntica em `public/desktop/index.html`; testes em `tests/cega_core.test.cjs` (`node tests/cega_core.test.cjs`).

### 9.4 Rendimento metálico
- **Rendimento = soma produzida ÷ soma consumida.** Nunca média de percentuais (vale para dia, turno, mês e total).
- Só entram produções com `etapa = 'finalizada'` e `resultado` preenchido.
- **Cor pelo número exibido (1 casa decimal):** ≥ 99,0 verde · ≥ 98,0 amarelo · abaixo vermelho. (98,96 aparece como 99,0% e fica verde.) Acima de 100% recebe ⚠ ("confira os pesos").
- **Turnos:** 1º 7h–15h20 · 2º 15h–23h20 · 3º 23h–7h20.
- Se a produção não tem turno gravado, deduz pelos cortes **07:10 / 15:10 / 23:10** (minutos 430 / 910 / 1390).
- O **3º turno antes das 07:10 conta para o dia anterior**; `data_producao` gravada tem prioridade.
- **Todo peso é guardado e mostrado em KG** (desde 2026-10-13, `update_009`): `volumes.quantidade`, `movimentos.quantidade` e pesos de produção. A planilha importada vinha em **toneladas** (convertida por `update_010`); o importador do app agora multiplica por 1000 ao importar.

- **Áreas (desde 2026-10-20, `update_012`):** o app tem ambientes separados por área: **Trefilaria** (`trefila`, tudo que existia antes) e **Planta 1 (laminação)** (`planta1`). Cada usuário pertence a uma só área e só vê e grava dados dela; supervisor e operador valem dentro da própria área. Os armazéns são por área (`armazens_area`; os da Planta 1 ainda serão cadastrados). O número do lote é único no banco inteiro. Produtos são compartilhados. Quem precisa ver todas as áreas usa o Power BI.

---
