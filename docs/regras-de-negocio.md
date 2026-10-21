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
